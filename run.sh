#!/bin/sh
# Runs oracle.lua in the PoB test image against a fetched PoB release.
# Usage: ./run.sh [tag] < builds.jsonl > results.jsonl
set -eu
tag="${1:-v2.68.1}"
here="$(cd "$(dirname "$0")" && pwd)"
pob="$("$here/scripts/fetch-pob.sh" "$tag" "$here/.pob/$tag")"
image="ghcr.io/pathofbuildingcommunity/pathofbuilding-tests@sha256:171dc3da232b8c874882e4ae3b3aa4a6e130a6c9450a31904b312435a6bf5daf"
docker run --rm -i --platform linux/amd64 \
  -v "$pob:/pob:ro" -v "$here/oracle.lua:/oracle/oracle.lua:ro" \
  -w /pob/src -e HOME=/tmp \
  -e LUA_PATH="../runtime/lua/?.lua;../runtime/lua/?/init.lua;./?.lua" \
  "$image" luajit /oracle/oracle.lua | grep '^ORACLE	' | cut -f2-
