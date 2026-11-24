# poe-pob-oracle

Headless [Path of Building Community](https://github.com/PathOfBuildingCommunity/PathOfBuilding)
as a reference calculator for [poe-lib](https://github.com/Mi7teR/poe-lib)'s
engine: builds go in, the stats PoB computes come out. poe-lib stores only the
resulting JSON fixtures and this repository's version; no Lua lives there.

```bash
./run.sh v2.68.1 < builds.jsonl > results.jsonl
```

PoB keeps some state between builds loaded in one process, so one build can
change another's results. For reference fixtures use `run-each.sh`, which
starts a fresh PoB per build (`JOBS` in parallel, default 4):

```bash
JOBS=6 ./run-each.sh v2.68.1 < builds.jsonl > results.jsonl
```

- Input: one JSON object per line, `{"name": "...", "xml": "<PathOfBuilding>..."}`
  (poe-lib's `cmd/goldencorpus input` writes it).
- Output: `{"name", "output", "error"}` per line; `output` is
  `build.calcsTab.mainOutput` (numbers, booleans, strings).

`scripts/fetch-pob.sh` downloads the PoB release once into `.pob/<tag>`,
keeping `src/` and `runtime/lua/` without images. `run.sh` mounts it into
PoB's own test image (`ghcr.io/pathofbuildingcommunity/pathofbuilding-tests`,
pinned by digest, linux/amd64; it runs under emulation on Apple Silicon).
`oracle.lua` replaces the headless `Inflate` stub with zlib through LuaJIT's
FFI, which PoB needs for the compressed timeless jewel data.

License: MIT, with the Path of Building Community notice (see LICENSE).
