#!/usr/bin/env bash
# Utilise pendant la construction de l'image (etape "fetch" du Dockerfile).
# Telecharge le fichier officiel d'un mineur (archive .tar.gz ou binaire nu),
# verifie son empreinte SHA-256, puis installe le binaire dans /opt/miners/<nom>/
# (et, si demande, des fichiers ou dossiers de l'archive a cote du binaire :
# lib/, libcudart.so.13, run.sh...). Si l'archive contient un SHA256SUMS a cote
# du binaire, il est verifie aussi.
#
# Usage : fetch-miner.sh <nom> <version> <url> <sha256> <nom-du-binaire> [fichier-ou-dossier...]
#
# Sources acceptees : une release GitHub (empreinte donnee par l'API GitHub), ou
# eu.lproute.com (lpminer) et dl.ariabrain.com (ariaenergy-prl), empreintes
# figees dans scripts/resolve-versions.sh.
set -euo pipefail

name="${1:?nom manquant}"
version="${2:?version manquante pour $name}"
url="${3:?URL manquante pour $name (build-arg vide ?)}"
sha256="${4:?empreinte SHA-256 manquante pour $name}"
binary="${5:?nom du binaire manquant}"
shift 5
extras=("$@")

case "$url" in
  https://github.com/*/releases/download/*) ;;
  https://eu.lproute.com/*) ;;
  https://dl.ariabrain.com/*) ;;
  *)
    echo "ERREUR: $name : le fichier doit venir d'une release GitHub, de eu.lproute.com ou de dl.ariabrain.com : $url" >&2
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
    # Le binaire le moins profond de l'archive (ariaenergy-prl en a un second dans cuda12/).
    found=$(find "$work/extract" -type f -name "$binary" | awk '{ print gsub("/", "/"), $0 }' | sort -n | head -n 1 | cut -d' ' -f2-)
    depth=$(find "$work/extract" -type f -name "$binary" | awk '{ print gsub("/", "/") }' | sort -n | uniq -c | head -n 1 | awk '{ print $1 }')
    if [[ -z "$found" || "$depth" != 1 ]]; then
      echo "ERREUR: $name : binaire '$binary' introuvable (ou en double au meme niveau) dans l'archive." >&2
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

# Empreintes publiees par l'auteur dans l'archive, si presentes.
if [[ -f "$(dirname "$found")/SHA256SUMS" ]]; then
  (cd "$(dirname "$found")" && sha256sum -c --quiet SHA256SUMS) \
    || { echo "ERREUR: $name : le SHA256SUMS de l'archive ne correspond pas a son contenu." >&2; exit 1; }
  echo "   SHA256SUMS de l'archive : OK"
fi

install -D -m 0755 -o root -g root "$found" "/opt/miners/${name}/${binary}"

# Fichiers ou dossiers de l'archive a garder a cote du binaire (bibliotheques, second
# build, lanceur fournis par l'auteur).
for extra in "${extras[@]}"; do
  src="$(dirname "$found")/$extra"
  if [[ -d "$src" ]]; then
    mkdir -p "/opt/miners/${name}/${extra}"
    cp -a "$src/." "/opt/miners/${name}/${extra}/"
  elif [[ -f "$src" ]]; then
    cp -a "$src" "/opt/miners/${name}/${extra}"
  else
    echo "ERREUR: $name : '$extra' introuvable a cote du binaire dans l'archive." >&2
    exit 1
  fi
done
chown -R root:root "/opt/miners/${name}"

echo "${name}=${version}" >> /opt/miners/VERSIONS
rm -rf "$work"
