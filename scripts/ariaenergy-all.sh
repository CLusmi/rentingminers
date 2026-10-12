#!/usr/bin/env bash
# Lanceur d'ARIAEnergy PRL dans l'image : ce mineur mine UNE carte par processus
# (CUDA_VISIBLE_DEVICES). Avec une seule carte visible (SaladCloud), il lance le
# run.sh de l'auteur tel quel. Avec plusieurs cartes (rig vast.ai), un processus par
# carte, le worker suffixe -gpu0, -gpu1... et chaque ligne prefixee [gpuN] ; des
# qu'un processus s'arrete, les autres sont arretes et le lanceur sort en erreur :
# l'entrypoint relance alors l'ensemble.
# run.sh (fourni par l'auteur) choisit le build : CUDA 13 a partir du pilote 580,
# sinon cuda12/ ; ARIA_CUDA12=1 force le build CUDA 12.
set -u
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -x "$dir/run.sh" ]] || { echo "[ariaenergy] run.sh introuvable dans $dir" >&2; exit 1; }

count=$(nvidia-smi -L 2>/dev/null | grep -c '^GPU ')
if [[ "${ARIA_ONE_PROCESS:-0}" == 1 || "$count" -le 1 ]]; then
  exec "$dir/run.sh" "$@"
fi

# Nom du worker donne par l'utilisateur (--worker NOM ou --worker=NOM), "aria" sinon.
args=("$@")
worker=""
worker_at=-1
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" == --worker && $((i + 1)) -lt ${#args[@]} ]]; then worker_at=$((i + 1)); worker="${args[$worker_at]}"
  elif [[ "${args[$i]}" == --worker=* ]]; then worker_at=$i; worker="${args[$i]#--worker=}"
  fi
done
[[ -n "$worker" ]] || worker=aria

pids=()
stop_all() { kill -TERM "${pids[@]}" 2>/dev/null; }
trap stop_all TERM INT

echo "[ariaenergy] $count cartes visibles : un processus par carte, workers ${worker}-gpu0 a ${worker}-gpu$((count - 1))."
for ((g = 0; g < count; g++)); do
  a=("${args[@]}")
  if [[ $worker_at -ge 0 ]]; then
    if [[ "${a[$worker_at]}" == --worker=* ]]; then a[$worker_at]="--worker=${worker}-gpu${g}"; else a[$worker_at]="${worker}-gpu${g}"; fi
  else
    a+=(--worker "${worker}-gpu${g}")
  fi
  CUDA_VISIBLE_DEVICES=$g "$dir/run.sh" "${a[@]}" > >(sed -u "s/^/[gpu${g}] /") 2>&1 &
  pids+=($!)
done

wait -n "${pids[@]}" 2>/dev/null
code=$?
echo "[ariaenergy] un processus s'est arrete (code $code) : arret des autres, l'image relance l'ensemble."
stop_all
wait
exit 1
