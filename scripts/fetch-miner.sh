#!/usr/bin/env bash
# Utilise pendant la construction de l'image (etape "fetch" du Dockerfile).
# Telecharge l'archive officielle d'un mineur, verifie son empreinte SHA-256,
# puis installe le binaire dans /opt/miners/<nom>/.
#
# Usage : fetch-miner.sh <nom> <version> <url> <sha256> <nom-du-binaire>
set -euo pipefail

name="${1:?nom manquant}"
version="${2:?version manquante pour $name}"
url="${3:?URL manquante pour $name (build-arg vide ?)}"
sha256="${4:?empreinte SHA-256 manquante pour $name}"
binary="${5:?nom du binaire manquant}"

if [[ "$url" != https://github.com/*/releases/download/* ]]; then
  echo "ERREUR: $name : l'archive doit venir d'une release GitHub : $url" >&2
  exit 1
fi
if [[ ! "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ERREUR: $name : empreinte SHA-256 invalide : $sha256" >&2
  exit 1
fi

work="/tmp/fetch-${name}"
mkdir -p "$work/extract"
archive="$work/$(basename "$url")"

echo ">> $name $version : $url"
curl -fsSL --retry 3 -o "$archive" "$url"

echo "${sha256}  ${archive}" | sha256sum -c -

tar -xzf "$archive" -C "$work/extract"

found=$(find "$work/extract" -type f -name "$binary")
if [[ $(printf '%s\n' "$found" | grep -c .) -ne 1 ]]; then
  echo "ERREUR: $name : binaire '$binary' introuvable (ou en double) dans l'archive." >&2
  exit 1
fi

install -D -m 0755 -o root -g root "$found" "/opt/miners/${name}/${binary}"
echo "${name}=${version}" >> /opt/miners/VERSIONS
rm -rf "$work"
