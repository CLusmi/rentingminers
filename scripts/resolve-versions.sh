#!/usr/bin/env bash
# Trouve la derniere version stable de chaque mineur sur sa page GitHub
# officielle et affiche les build-args du Dockerfile (une ligne CLE=VALEUR).
#
# Pour chaque mineur GitHub : URL du fichier Linux + empreinte SHA-256 calculee
# par GitHub au moment ou l'auteur a publie le fichier (champ "digest" de l'API).
# Le Dockerfile refuse tout fichier dont l'empreinte ne correspond pas.
#
# lpminer (LuckyPool) et ariaenergy-prl (ARIAEnergy) ne sont pas sur GitHub :
# version, URL et empreinte sont figees ici. Nouvelle version = changer la
# ligne correspondante de FIXED ci-dessous.
#
# Necessite : gh (CLI GitHub, authentifie via GH_TOKEN) et jq.
set -euo pipefail

# cle | depot GitHub officiel | nom du fichier Linux (regex : archive .tar.gz ou binaire nu)
MINERS=(
  "SRB|doktor83/SRBMiner-Multi|^SRBMiner-Multi-.*-Linux\\.tar\\.gz$"
  "XMRIG|xmrig/xmrig|^xmrig-[0-9.]+-linux-static-x64\\.tar\\.gz$"
  "FORGE|0xHashRaptor/ForgeMiner|^ForgeMiner-[0-9.]+-linux\\.tar\\.gz$"
  "OZM|OneZeroMiner/onezerominer|^onezerominer-linux-[0-9.]+\\.tar\\.gz$"
  "PEAK|peakminer/peakminer|^peakminer-[0-9.]+-linux-x86_64$"
)

# Mineurs hors GitHub, figes : cle | version | URL | SHA-256
# (empreintes calculees sur les archives telechargees le 2026-10-11)
FIXED=(
  "LPMINER|0.0.3|https://eu.lproute.com/lpminerquantus/lpminerquantus-0.0.3.tar.gz|72501a42933cb52ed519ea30bf3223b531b5f5858b19a641e45e82dc5fe46b90"
  "ARIA|v1.1.1|https://dl.ariabrain.com/pearl-dl/ariaenergy-prl-v1.1.1-linux-x86_64.tar.gz|7cbb4db0c33a9ec44afa9c88ac8fadcaf65b3145f8542813623d2937e53a9aeb"
)

for entry in "${MINERS[@]}"; do
  IFS='|' read -r key repo pattern <<< "$entry"

  # /releases/latest ignore les pre-releases et les brouillons.
  json=$(gh api "repos/${repo}/releases/latest")

  tag=$(jq -r '.tag_name' <<< "$json")
  matches=$(jq -c --arg re "$pattern" '[.assets[] | select(.name | test($re))]' <<< "$json")
  count=$(jq 'length' <<< "$matches")
  if [[ "$count" -ne 1 ]]; then
    echo "ERREUR: ${repo} ${tag} : ${count} fichier(s) Linux trouve(s) au lieu d'un seul (motif ${pattern})." >&2
    echo "Fichiers de la release :" >&2
    jq -r '.assets[].name' <<< "$json" >&2
    exit 1
  fi

  url=$(jq -r '.[0].browser_download_url' <<< "$matches")
  digest=$(jq -r '.[0].digest // empty' <<< "$matches")

  if [[ "$url" != "https://github.com/${repo}/releases/download/"* ]]; then
    echo "ERREUR: ${repo} : URL inattendue : ${url}" >&2
    exit 1
  fi
  if [[ ! "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "ERREUR: ${repo} ${tag} : pas d'empreinte SHA-256 publiee par GitHub pour $(basename "$url")." >&2
    exit 1
  fi

  echo "${key}_VERSION=${tag}"
  echo "${key}_URL=${url}"
  echo "${key}_SHA256=${digest#sha256:}"
done

for entry in "${FIXED[@]}"; do
  IFS='|' read -r key version url sha256 <<< "$entry"
  echo "${key}_VERSION=${version}"
  echo "${key}_URL=${url}"
  echo "${key}_SHA256=${sha256}"
done
