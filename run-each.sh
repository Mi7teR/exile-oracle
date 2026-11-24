#!/bin/sh
# Runs every input line in its own oracle process: PoB keeps state between
# builds loaded in one process (a build can change another's results), so
# reference results come from a fresh PoB per build.
# Usage: ./run-each.sh [tag] < builds.jsonl > results.jsonl  (env JOBS, default 4)
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
split -l 1 -a 4 - "$tmp/in."
ls "$tmp"/in.* | xargs -P "${JOBS:-4}" -I{} sh -c '"$1/run.sh" ${2:+"$2"} < "$3" > "$3.out"' _ "$here" "${1:-}" {}
for f in "$tmp"/in.*.out; do cat "$f"; done
