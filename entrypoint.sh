#!/usr/bin/env bash
# Lance le mineur GPU choisi et, en option, XMRig sur le CPU.
#
# GPU (obligatoire) :
#   MINER        srbminer (defaut) | bzminer
#   COIN         pearl (defaut) | quantus | autre nom d'algorithme (passe tel quel)
#                ALGO est accepte a la place de COIN (ex. ALGO=pearlhash)
#   POOL         adresse:port de la pool
#   WALLET       adresse du wallet
#   WORKER       nom du worker (facultatif)
#   PASS         mot de passe pool (facultatif)
#   EXTRA_ARGS   options supplementaires passees telles quelles au mineur GPU
#
# CPU avec XMRig (optionnel : actif si CPU_POOL et CPU_WALLET sont renseignes) :
#   CPU_POOL        adresse:port de la pool Monero
#   CPU_WALLET      adresse Monero
#   CPU_WORKER      nom du worker (envoye en mot de passe de pool et en rig-id)
#   CPU_THREADS     nombre de threads (vide : XMRig choisit seul)
#   CPU_COIN        monero (defaut), passe a --coin
#   CPU_EXTRA_ARGS  options supplementaires passees telles quelles a XMRig
#
# Commun :
#   RESTART_DELAY  secondes avant relance d'un mineur qui s'arrete (defaut 10)
#   DRY_RUN=1      affiche les commandes sans lancer les mineurs
#
# Avec des arguments (docker run image --help), le mineur GPU choisi est lance
# directement avec ces arguments ; une commande (bash, nvidia-smi) est executee.
set -uo pipefail

MINERS_DIR=/opt/miners

log() { echo "[rentingminers] $*"; }
die() { echo "[rentingminers] ERREUR: $*" >&2; exit 1; }

miner=$(echo "${MINER:-srbminer}" | tr '[:upper:]' '[:lower:]')
case "$miner" in
  srb|srbminer|srbminer-multi) miner=srbminer; bin="$MINERS_DIR/srbminer/SRBMiner-MULTI" ;;
  bz|bzminer)                  miner=bzminer;  bin="$MINERS_DIR/bzminer/bzminer" ;;
  *) die "MINER=${MINER} inconnu. Valeurs possibles : srbminer, bzminer." ;;
esac
[[ -x "$bin" ]] || die "binaire introuvable : $bin"
xmrig="$MINERS_DIR/xmrig/xmrig"

# Mode direct : arguments passes au conteneur.
if [[ $# -gt 0 ]]; then
  if [[ "$1" != -* ]] && command -v "$1" >/dev/null 2>&1; then
    exec "$@"
  fi
  exec "$bin" "$@"
fi

log "Versions installees : $(tr '\n' ' ' < "$MINERS_DIR/VERSIONS")"

# --- Mineur GPU --------------------------------------------------------------
coin=$(echo "${COIN:-${ALGO:-pearl}}" | tr '[:upper:]' '[:lower:]')
[[ "$coin" == pearlhash || "$coin" == prl ]] && coin=pearl

[[ -n "${POOL:-}" ]]   || die "POOL est obligatoire (ex. POOL=prl.kryptex.network:7048)."
[[ -n "${WALLET:-}" ]] || die "WALLET est obligatoire."
worker="${WORKER:-}"
pass="${PASS:-}"
extra=()
[[ -n "${EXTRA_ARGS:-}" ]] && read -r -a extra <<< "$EXTRA_ARGS"

case "$miner:$coin" in
  srbminer:pearl) algo=pearlhash ;;
  *:pearl)        algo=pearl ;;
  *)              algo="$coin" ;;
esac

gpu_cmd=("$bin")
logfile=""
case "$miner" in
  srbminer)
    pool="${POOL#stratum+tcp://}"
    # SRBMiner n'ecrit rien sur la sortie standard hors terminal : on passe par
    # son fichier de log, recopie dans les logs du conteneur plus bas.
    logfile="$PWD/srbminer.log"
    gpu_cmd+=(--disable-cpu --algorithm "$algo" --pool "$pool" --wallet "$WALLET" --log-file "$logfile")
    [[ -n "$worker" ]] && gpu_cmd+=(--worker "$worker")
    [[ -n "$pass" ]]   && gpu_cmd+=(--password "$pass")
    ;;
  bzminer)
    pool="$POOL"
    [[ "$pool" == *://* ]] || pool="stratum+tcp://$pool"
    # --nvidia : seules les cartes NVIDIA minent (le CPU est laisse a XMRig).
    # -o log   : journal en texte simple, lisible dans les logs du conteneur.
    gpu_cmd+=(-a "$algo" -p "$pool" -w "$WALLET" --nvidia -o log)
    [[ -n "$worker" ]] && gpu_cmd+=(--worker "$worker")
    [[ -n "$pass" ]]   && gpu_cmd+=(--pass "$pass")
    ;;
esac
gpu_cmd+=("${extra[@]}")
log "GPU : ${gpu_cmd[*]}"

# --- XMRig (CPU) --------------------------------------------------------------
cpu_cmd=()
if [[ -n "${CPU_POOL:-}" || -n "${CPU_WALLET:-}" ]]; then
  [[ -n "${CPU_POOL:-}" ]]   || die "CPU_WALLET est renseigne mais CPU_POOL manque."
  [[ -n "${CPU_WALLET:-}" ]] || die "CPU_POOL est renseigne mais CPU_WALLET manque."
  if [[ -n "${CPU_THREADS:-}" && ! "${CPU_THREADS}" =~ ^[1-9][0-9]*$ ]]; then
    die "CPU_THREADS doit etre un nombre entier positif (recu : '${CPU_THREADS}')."
  fi
  cpu_cmd=("$xmrig" --no-color --coin "${CPU_COIN:-monero}" -o "$CPU_POOL" -u "$CPU_WALLET")
  [[ -n "${CPU_WORKER:-}" ]]  && cpu_cmd+=(-p "$CPU_WORKER" --rig-id "$CPU_WORKER")
  [[ -n "${CPU_THREADS:-}" ]] && cpu_cmd+=(-t "$CPU_THREADS")
  if [[ -n "${CPU_EXTRA_ARGS:-}" ]]; then
    read -r -a cpu_extra <<< "$CPU_EXTRA_ARGS"
    cpu_cmd+=("${cpu_extra[@]}")
  fi
  log "CPU : ${cpu_cmd[*]}"
else
  log "CPU : pas de minage CPU (CPU_POOL et CPU_WALLET vides)."
fi

if [[ "${DRY_RUN:-0}" == 1 ]]; then
  exit 0
fi

if ! ls /dev/nvidia* >/dev/null 2>&1 && [[ ! -e /usr/lib/x86_64-linux-gnu/libcuda.so.1 ]]; then
  log "ATTENTION : aucun GPU NVIDIA visible dans le conteneur (lancer avec --gpus all)."
fi

# --- Lancement et surveillance -------------------------------------------------
gpu_pid=0
cpu_pid=0
tailer=0
delay="${RESTART_DELAY:-10}"

if [[ -n "$logfile" && ! -t 1 ]]; then
  : > "$logfile"
  tail -n0 -F "$logfile" 2>/dev/null &
  tailer=$!
fi

start_gpu() {
  "${gpu_cmd[@]}" &
  gpu_pid=$!
}

start_cpu() {
  # Les lignes de XMRig sont prefixees par [cpu] pour les distinguer du GPU.
  "${cpu_cmd[@]}" > >(sed -u 's/^/[cpu] /') 2>&1 &
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
  [[ $tailer -ne 0 ]] && kill "$tailer" 2>/dev/null
  exit 0
}
trap stop TERM INT

start_gpu
[[ ${#cpu_cmd[@]} -gt 0 ]] && start_cpu

# Surveillance toutes les 2 s : un mineur arrete est relance apres le delai,
# sans bloquer l'autre, qui continue de miner.
gpu_restart_at=0
cpu_restart_at=0
while true; do
  sleep 2 & wait $!
  now=$(date +%s)

  if [[ $gpu_restart_at -eq 0 ]] && ! kill -0 "$gpu_pid" 2>/dev/null; then
    wait "$gpu_pid"; code=$?
    log "Le mineur GPU s'est arrete (code $code). Relance dans ${delay}s."
    gpu_restart_at=$((now + delay))
  fi
  if [[ $gpu_restart_at -ne 0 && $now -ge $gpu_restart_at ]]; then
    start_gpu
    gpu_restart_at=0
  fi

  if [[ $cpu_pid -ne 0 ]]; then
    if [[ $cpu_restart_at -eq 0 ]] && ! kill -0 "$cpu_pid" 2>/dev/null; then
      wait "$cpu_pid"; code=$?
      log "XMRig s'est arrete (code $code). Relance dans ${delay}s."
      cpu_restart_at=$((now + delay))
    fi
    if [[ $cpu_restart_at -ne 0 && $now -ge $cpu_restart_at ]]; then
      start_cpu
      cpu_restart_at=0
    fi
  fi
done
