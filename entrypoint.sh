#!/usr/bin/env bash
# Lance un mineur sur les GPU (SRBMiner-MULTI) et/ou un mineur sur le CPU (XMRig ou
# SRBMiner-MULTI). Les arguments sont passes aux mineurs tels quels.
#
# Rien n'est lance par defaut : un cote demarre seulement si SON mineur ET SES
# arguments sont renseignes. GPU seul, CPU seul ou les deux, au choix.
#
# Variables :
#   GPU_MINER      srbminer (seule valeur possible, XMRig ne mine que sur CPU)
#   GPU_ARGS       arguments SRBMiner
#                  ex. --algorithm pearlhash --pool prl.kryptex.network:7048 --wallet ADRESSE --worker FARM
#   CPU_MINER      xmrig | srbminer
#   CPU_ARGS       arguments du mineur CPU
#                  ex. --coin monero -o xmr.kryptex.network:7029 -u ADRESSE/RENT -t 184 -k
#   RESTART_DELAY  secondes avant relance d'un mineur qui s'arrete (defaut 10)
#   DRY_RUN=1      affiche les commandes finales sans lancer les mineurs
#
# Options ajoutees automatiquement, sauf si elles sont deja dans tes arguments :
#   SRBMiner GPU : --disable-cpu --log-file
#   SRBMiner CPU : --disable-gpu --disable-numa-binding --log-file (dans un dossier a part)
#   XMRig        : --randomx-no-numa --no-color
#
# Avec des arguments (docker run image --help), SRBMiner est lance directement
# avec ces arguments ; une commande (bash, nvidia-smi) est executee.
set -uo pipefail

MINERS_DIR=/opt/miners
srb="$MINERS_DIR/srbminer/SRBMiner-MULTI"
xmrig="$MINERS_DIR/xmrig/xmrig"

log() { echo "[rentingminers] $*"; }
die() { echo "[rentingminers] ERREUR: $*" >&2; exit 1; }

# Mode direct : arguments passes au conteneur.
if [[ $# -gt 0 ]]; then
  if [[ "$1" != -* ]] && command -v "$1" >/dev/null 2>&1; then
    exec "$@"
  fi
  exec "$srb" "$@"
fi

log "Versions installees : $(tr '\n' ' ' < "$MINERS_DIR/VERSIONS")"

# --- Anciennes variables (versions precedentes de l'image) ---------------------
old_vars=()
for name in MINER COIN ALGO POOL WALLET WORKER PASS EXTRA_ARGS \
            CPU_POOL CPU_WALLET CPU_WORKER CPU_THREADS CPU_ALGO CPU_COIN CPU_EXTRA_ARGS; do
  [[ -n "${!name:-}" ]] && old_vars+=("$name")
done
if [[ ${#old_vars[@]} -gt 0 ]]; then
  die "variables d'une ancienne version detectees : ${old_vars[*]}. Cette version utilise GPU_MINER, GPU_ARGS, CPU_MINER et CPU_ARGS (voir le README)."
fi

# --- Outils ----------------------------------------------------------------------

# Decoupe une chaine d'arguments en tableau, en respectant les guillemets
# ("mot de passe avec espace"). Resultat dans le tableau nomme par $2.
split_args() {
  local text="$1" target="$2" out
  local -a parsed=()
  # Guillemets autour de toute la valeur (l'interface de vast.ai peut les garder
  # quand la variable vient du champ Docker Options) : retires.
  if [[ "$text" =~ ^[[:space:]]*\"([^\"]*)\"[[:space:]]*$ || "$text" =~ ^[[:space:]]*\'([^\']*)\'[[:space:]]*$ ]]; then
    text="${BASH_REMATCH[1]}"
  fi
  if [[ -n "${text// /}" ]]; then
    out=$(printf '%s' "$text" | xargs printf '%s\n' 2>/dev/null) \
      || die "impossible de lire les arguments : guillemet non ferme ? ($text)"
    mapfile -t parsed <<< "$out"
  fi
  eval "$target=(\"\${parsed[@]}\")"
}

# Affiche une commande, en remettant des guillemets autour des valeurs qui en ont besoin.
show_cmd() {
  local out="" arg
  for arg in "$@"; do
    if [[ "$arg" == *[[:space:]\"\'\$]* || -z "$arg" ]]; then out+=" \"${arg//\"/\\\"}\""; else out+=" $arg"; fi
  done
  echo "${out# }"
}

# Vrai si l'option $1 figure deja dans les arguments ($2...), seule ou en --opt=valeur.
has_opt() {
  local opt="$1" arg
  shift
  for arg in "$@"; do
    [[ "$arg" == "$opt" || "$arg" == "$opt="* ]] && return 0
  done
  return 1
}

# Valeur qui suit l'option $1 dans les arguments ($2...), ou vide.
opt_value() {
  local opt="$1" prev="" arg
  shift
  for arg in "$@"; do
    [[ "$prev" == "$opt" ]] && { echo "$arg"; return; }
    [[ "$arg" == "$opt="* ]] && { echo "${arg#*=}"; return; }
    prev="$arg"
  done
}

lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# --- Qu'est-ce qui doit tourner ? -----------------------------------------------
# Un cote est actif seulement si son mineur ET ses arguments sont renseignes.
# Une variable seule est refusee : rien ne demarre sans choix explicite.
gpu_on=0
cpu_on=0
if [[ -n "${GPU_MINER:-}" && -n "${GPU_ARGS:-}" ]]; then gpu_on=1
elif [[ -n "${GPU_MINER:-}" ]]; then die "GPU_MINER est renseigne mais GPU_ARGS manque (ou vide)."
elif [[ -n "${GPU_ARGS:-}" ]]; then die "GPU_ARGS est renseigne mais GPU_MINER manque (GPU_MINER=srbminer)."
fi
if [[ -n "${CPU_MINER:-}" && -n "${CPU_ARGS:-}" ]]; then cpu_on=1
elif [[ -n "${CPU_MINER:-}" ]]; then die "CPU_MINER est renseigne mais CPU_ARGS manque (ou vide)."
elif [[ -n "${CPU_ARGS:-}" ]]; then die "CPU_ARGS est renseigne mais CPU_MINER manque (CPU_MINER=xmrig ou srbminer)."
fi
if [[ $gpu_on -eq 0 && $cpu_on -eq 0 ]]; then
  die "rien a miner : renseigne GPU_MINER + GPU_ARGS (GPU), CPU_MINER + CPU_ARGS (CPU), ou les deux."
fi

# --- GPU : SRBMiner ------------------------------------------------------------
gpu_cmd=()
gpu_log=""
if [[ $gpu_on -eq 1 ]]; then
  gpu_miner=$(lower "$GPU_MINER")
  case "$gpu_miner" in
    srb|srbminer|srbminer-multi) gpu_miner=srbminer ;;
    xmrig) die "GPU_MINER=xmrig : XMRig ne mine que sur CPU. Pour le GPU, GPU_MINER=srbminer." ;;
    *) die "GPU_MINER=${GPU_MINER} inconnu. Seule valeur possible : srbminer." ;;
  esac
  [[ -x "$srb" ]] || die "binaire introuvable : $srb"
  split_args "$GPU_ARGS" gpu_user
  gpu_cmd=("$srb")
  has_opt --disable-cpu "${gpu_user[@]}" || gpu_cmd+=(--disable-cpu)
  # SRBMiner n'ecrit rien sur la sortie standard hors terminal : on passe par son
  # fichier de log, recopie dans les logs du conteneur plus bas.
  gpu_log=$(opt_value --log-file "${gpu_user[@]}")
  if [[ -z "$gpu_log" ]]; then
    gpu_log="$PWD/srbminer-gpu.log"
    gpu_cmd+=(--log-file "$gpu_log")
  elif [[ "$gpu_log" != /* ]]; then
    gpu_log="$PWD/$gpu_log"
  fi
  gpu_cmd+=("${gpu_user[@]}")
  log "GPU ($gpu_miner) : $(show_cmd "${gpu_cmd[@]}")"
else
  log "GPU : desactive (GPU_MINER et GPU_ARGS vides)."
fi

# --- CPU : XMRig ou SRBMiner --------------------------------------------------
cpu_cmd=()
cpu_dir=""
cpu_log=""
if [[ $cpu_on -eq 1 ]]; then
  cpu_miner=$(lower "$CPU_MINER")
  split_args "$CPU_ARGS" cpu_user
  case "$cpu_miner" in
    xmrig)
      [[ -x "$xmrig" ]] || die "binaire introuvable : $xmrig"
      cpu_cmd=("$xmrig")
      # --randomx-no-numa : dans un conteneur, XMRig ne peut pas placer sa memoire
      # par processeur ; sans cette option il passe en mode lent sur les machines
      # a plusieurs processeurs (environ 10 fois moins de hashrate).
      has_opt --randomx-no-numa "${cpu_user[@]}" || cpu_cmd+=(--randomx-no-numa)
      has_opt --no-color "${cpu_user[@]}"        || cpu_cmd+=(--no-color)
      ;;
    srb|srbminer|srbminer-multi)
      cpu_miner=srbminer
      # Dossier a part : SRBMiner y cree ses dossiers Cache et Autotune, separes
      # de ceux du SRBMiner GPU.
      cpu_dir="$PWD/cpu"
      cpu_cmd=("$srb")
      has_opt --disable-gpu "${cpu_user[@]}"          || cpu_cmd+=(--disable-gpu)
      # --disable-numa-binding : meme raison que --randomx-no-numa pour XMRig.
      has_opt --disable-numa-binding "${cpu_user[@]}" || cpu_cmd+=(--disable-numa-binding)
      cpu_log=$(opt_value --log-file "${cpu_user[@]}")
      if [[ -z "$cpu_log" ]]; then
        cpu_log="$cpu_dir/srbminer-cpu.log"
        cpu_cmd+=(--log-file "$cpu_log")
      elif [[ "$cpu_log" != /* ]]; then
        cpu_log="$cpu_dir/$cpu_log"
      fi
      ;;
    *) die "CPU_MINER=${CPU_MINER} inconnu. Valeurs possibles : xmrig, srbminer." ;;
  esac
  cpu_cmd+=("${cpu_user[@]}")
  log "CPU ($cpu_miner) : $(show_cmd "${cpu_cmd[@]}")"
else
  log "CPU : desactive (CPU_MINER et CPU_ARGS vides)."
fi

if [[ "${DRY_RUN:-0}" == 1 ]]; then
  exit 0
fi

if [[ $gpu_on -eq 1 ]] && ! ls /dev/nvidia* >/dev/null 2>&1 && [[ ! -e /usr/lib/x86_64-linux-gnu/libcuda.so.1 ]]; then
  log "ATTENTION : aucun GPU NVIDIA visible dans le conteneur (lancer avec --gpus all)."
fi

# --- Lancement et surveillance -------------------------------------------------
gpu_pid=0
cpu_pid=0
gpu_tailer=0
cpu_tailer=0
delay="${RESTART_DELAY:-10}"

# Journaux SRBMiner recopies dans les logs du conteneur (lignes CPU prefixees [cpu]).
if [[ -n "$gpu_log" && ! -t 1 ]]; then
  : > "$gpu_log"
  tail -n0 -F "$gpu_log" 2>/dev/null &
  gpu_tailer=$!
fi
if [[ -n "$cpu_dir" ]]; then
  mkdir -p "$cpu_dir"
  if [[ ! -t 1 ]]; then
    : > "$cpu_log"
    tail -n0 -F "$cpu_log" 2>/dev/null > >(sed -u 's/^/[cpu] /') &
    cpu_tailer=$!
  fi
fi

start_gpu() {
  "${gpu_cmd[@]}" &
  gpu_pid=$!
}

start_cpu() {
  # Les lignes du mineur CPU sont prefixees par [cpu] pour les distinguer du GPU.
  if [[ -n "$cpu_dir" ]]; then
    ( cd "$cpu_dir" && exec "${cpu_cmd[@]}" ) > >(sed -u 's/^/[cpu] /') 2>&1 &
  else
    "${cpu_cmd[@]}" > >(sed -u 's/^/[cpu] /') 2>&1 &
  fi
  cpu_pid=$!
}

stop() {
  log "Arret demande, fermeture des mineurs..."
  for pid in "$gpu_pid" "$cpu_pid"; do
    [[ $pid -ne 0 ]] && kill -TERM "$pid" 2>/dev/null
  done
  for pid in "$gpu_pid" "$cpu_pid"; do
    [[ $pid -ne 0 ]] && wait "$pid" 2>/dev/null
  done
  for pid in "$gpu_tailer" "$cpu_tailer"; do
    [[ $pid -ne 0 ]] && kill "$pid" 2>/dev/null
  done
  exit 0
}
trap stop TERM INT

[[ $gpu_on -eq 1 ]] && start_gpu
[[ $cpu_on -eq 1 ]] && start_cpu

# Surveillance toutes les 2 s : un mineur arrete est relance apres le delai,
# sans bloquer l'autre, qui continue de miner.
gpu_restart_at=0
cpu_restart_at=0
while true; do
  sleep 2 & wait $!
  now=$(date +%s)

  if [[ $gpu_pid -ne 0 ]]; then
    if [[ $gpu_restart_at -eq 0 ]] && ! kill -0 "$gpu_pid" 2>/dev/null; then
      wait "$gpu_pid"; code=$?
      log "Le mineur GPU s'est arrete (code $code). Relance dans ${delay}s."
      gpu_restart_at=$((now + delay))
    fi
    if [[ $gpu_restart_at -ne 0 && $now -ge $gpu_restart_at ]]; then
      start_gpu
      gpu_restart_at=0
    fi
  fi

  if [[ $cpu_pid -ne 0 ]]; then
    if [[ $cpu_restart_at -eq 0 ]] && ! kill -0 "$cpu_pid" 2>/dev/null; then
      wait "$cpu_pid"; code=$?
      log "Le mineur CPU s'est arrete (code $code). Relance dans ${delay}s."
      cpu_restart_at=$((now + delay))
    fi
    if [[ $cpu_restart_at -ne 0 && $now -ge $cpu_restart_at ]]; then
      start_cpu
      cpu_restart_at=0
    fi
  fi
done
