#!/usr/bin/env bash
# seed-cc-rebuild-check.sh -- seed-cc rebuilds itself and seed-ar byte for
# byte.
#
# Generation 1: the seed reads cc/driver/seed-cc-start.fth and writes
# build-out/seed-cc/seed-cc and seed-ar (no C compiler runs).
# Generation 2: generation 1's seed-cc compiles cc/driver/seed-cc.c and
# cc/driver/seed-ar.c into build-out/seed-cc-gen2/.  Generation 2 must equal
# generation 1.  The output directory sits at the same depth as
# build-out/seed-cc/, since seed-cc finds the source tree from its own path.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -x seed-forth ] || seed/build.sh >/dev/null

./seed-forth < cc/driver/seed-cc-start.fth
G1=build-out/seed-cc
G2=build-out/seed-cc-gen2
rm -rf "$G2"
mkdir -p "$G2"
"$G1/seed-cc" -static cc/driver/seed-cc.c -o "$G2/seed-cc"
"$G1/seed-cc" -static cc/driver/seed-ar.c -o "$G2/seed-ar"
for tool in seed-cc seed-ar; do
    cmp "$G1/$tool" "$G2/$tool" || {
        echo "seed-cc-rebuild-check: FAIL: generation 2 $tool differs from generation 1" >&2
        exit 1
    }
done
echo "seed-cc-rebuild-check: PASS (generation 2 seed-cc and seed-ar equal generation 1:" \
     "$(wc -c < "$G1/seed-cc") and $(wc -c < "$G1/seed-ar") bytes)"
