#!/bin/sh
# Downloads a Path of Building Community release and keeps only what the
# headless calculator needs: src/ and runtime/lua/, without images
# (the .zip files are compressed data PoB reads, e.g. timeless jewels).
# Usage: scripts/fetch-pob.sh v2.68.1 [dest]   (dest defaults to .pob/<tag>)
set -eu
tag="${1:?usage: fetch-pob.sh <tag> [dest]}"
dest="${2:-.pob/$tag}"
[ -f "$dest/.complete" ] && { echo "$dest"; exit 0; }
mkdir -p "$dest"
curl -fsSL "https://codeload.github.com/PathOfBuildingCommunity/PathOfBuilding/tar.gz/refs/tags/$tag" |
  tar xz -C "$dest" --strip-components=1 \
    --exclude='*.png' --exclude='*.jpg' --exclude='*.webp' --exclude='*.dds' \
    "PathOfBuilding-${tag#v}/src" "PathOfBuilding-${tag#v}/runtime/lua"
touch "$dest/.complete"
echo "$dest"
