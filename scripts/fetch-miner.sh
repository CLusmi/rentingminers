#!/usr/bin/env bash
# Utilise pendant la construction de l'image (etape "fetch" du Dockerfile).
# Telecharge le fichier officiel d'un mineur (archive .tar.gz ou binaire nu),
# verifie son empreinte SHA-256, puis installe le binaire dans /opt/miners/<nom>/
# (et, si demande, des dossiers de l'archive a cote du binaire, ex. lib/).
#
# Usage : fetch-miner.sh <nom> <version> <url> <sha256> <nom-du-binaire> [dossier...]
#
# Sources acceptees : une release GitHub (empreinte donnee par l'API GitHub), ou
# eu.lproute.com pour lpminer (empreinte figee dans scripts/resolve-versions.sh).
set -euo pipefail

name="${1:?nom manquant}"
version="${2:?version manquante pour $name}"
url="${3:?URL manquante pour $name (build-arg vide ?)}"
sha256="${4:?empreinte SHA-256 manquante pour $name}"
binary="${5:?nom du binaire manquant}"
shift 5
extra_dirs=("$@")

case "$url" in
  https://github.com/*/releases/download/*) ;;
  https://eu.lproute.com/*) ;;
  *)
    echo "ERREUR: $name : le fichier doit venir d'une release GitHub ou de eu.lproute.com : $url" >&2
    exit 1
    ;;
esac
if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ERREUR: $name : empreinte SHA-256 invalide : $sha256" >&2
  exit 1
fi

work="/tmp/fetch-${name}"
mkdir -p "$work/extract"
file="$work/$(basename "$url")"

echo ">> $name $version : $url"
curl -fsSL --retry 3 -o "$file" "$url"

echo "${sha256}  ${file}" | sha256sum -c -

case "$file" in
  *.tar.gz|*.tgz)
    tar -xzf "$file" -C "$work/extract"
    found=$(find "$work/extract" -type f -name "$binary")
    if [[ $(printf '%s\n' "$found" | grep -c .) -ne 1 ]]; then
      echo "ERREUR: $name : binaire '$binary' introuvable (ou en double) dans l'archive." >&2
      exit 1
    fi
    ;;
  *)
    # Binaire nu (PeakMiner) : le fichier telecharge est le binaire lui-meme.
    found="$file"
    ;;
esac

# Un executable Linux commence par les quatre octets 7f 45 4c 46 (« ELF ») : on refuse
# une page d'erreur ou une archive mal nommee.
magic=$(od -An -tx1 -N4 "$found" | tr -d ' \n')
if [[ "$magic" != "7f454c46" ]]; then
  echo "ERREUR: $name : '$binary' n'est pas un executable Linux (en-tete $magic)." >&2
  exit 1
fi

install -D -m 0755 -o root -g root "$found" "/opt/miners/${name}/${binary}"

# Dossiers de l'archive a garder a cote du binaire (bibliotheques fournies par l'auteur).
for dir in "${extra_dirs[@]}"; do
  src="$(dirname "$found")/$dir"
  if [[ ! -d "$src" ]]; then
    echo "ERREUR: $name : dossier '$dir' introuvable a cote du binaire dans l'archive." >&2
    exit 1
  fi
  mkdir -p "/opt/miners/${name}/${dir}"
  cp -a "$src/." "/opt/miners/${name}/${dir}/"
  chown -R root:root "/opt/miners/${name}/${dir}"
done

echo "${name}=${version}" >> /opt/miners/VERSIONS
rm -rf "$work"
