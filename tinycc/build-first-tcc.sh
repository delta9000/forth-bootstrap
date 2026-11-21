#!/usr/bin/env bash
# tinycc/build-first-tcc.sh -- seed Forth compiles the first tcc.
#
#     tinycc/build-first-tcc.sh        (from anywhere; works in the repo root)
#     tinycc/build-first-tcc.sh --prepare   only the source tree, no compile
#
# Writes build-out/tinycc/tcc-first: janneke's tcc-0.9.26-1147-gee75a10c
# targeting i386, the compiler live-bootstrap builds with MesCC as
# /usr/bin/tcc-mes, here compiled by the Forth compiler in native mode.
# The only program that runs to build it is seed-forth (1,772 bytes, from
# seed/000-seed.hex0), reading forth/010-lib.fth, the compiler layers,
# tinycc/tcc-compile.fth and the C source on stdin.  No host compiler,
# preprocessor, assembler or linker takes part.  Host tools do the source
# preparation only: sha256sum checks the archives, tar and gzip unpack them,
# python3 -I tinycc/simple-patch.py and patch apply the patches.
#
# The source tree, build-out/tcc-sources/:
#   tcc-0.9.26-1147-gee75a10c/  tinycc-inputs/tcc-0.9.26.tar.gz with what
#       live-bootstrap's steps/tcc-0.9.26/pass1.kaem does before it runs
#       MesCC: its two simple-patches to tcctools.c (from the pinned
#       live-bootstrap tree) and an empty config.h; then
#       tinycc/patches/tcc-0.9.26/*.diff, for the Forth compiler
#   libc64/  pnut's portable_libc/ (tinycc-inputs/pnut-<commit>.tar.gz) as
#       published, compiled into the same image.  seed-forth's six libc
#       patches are for its x86_64 boot stages and are not needed here.
#   direct-input.c  tinycc/direct-input.c
#
# The result's sha256 is pinned in tests/pins/tinycc.sha256 and checked at
# the end.  It is the same for any checkout path: every path the Forth
# compiler sees is relative to the repository root.
set -euo pipefail
cd "$(dirname "$0")/.."

IN=build-out/tinycc-inputs
SRC=build-out/tcc-sources
OUT=build-out/tinycc
TCC_PKG=tcc-0.9.26-1147-gee75a10c
PNUT=pnut-abc34a5207b1373d0a4e3dcb3d3d6df6e22ae23d
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9

fail() { echo "build-first-tcc: $*" >&2; exit 1; }

# The archives, against tinycc/SOURCES
for a in tcc-0.9.26.tar.gz $PNUT.tar.gz $LB.tar.gz; do
    [ -f "$IN/$a" ] || fail "$IN/$a missing; run python3 tools/fetch-archives.py $IN/$a"
    grep -F "  $IN/$a" tinycc/SOURCES | sha256sum --check --quiet - \
        || fail "$IN/$a: sha256 differs from tinycc/SOURCES"
done

rm -rf "$SRC" "$OUT/simple-patches"
mkdir -p "$SRC" "$OUT"

# tcc: unpack, live-bootstrap's own changes, then ours
tar -xzf "$IN/tcc-0.9.26.tar.gz" -C "$SRC" --no-same-owner "$TCC_PKG"
tar -xzf "$IN/$LB.tar.gz" -C "$OUT" --no-same-owner --strip-components=3 \
    "$LB/steps/tcc-0.9.26/simple-patches"
for p in remove-fileopen addback-fileopen; do
    python3 -I tinycc/simple-patch.py "$SRC/$TCC_PKG/tcctools.c" \
        "$OUT/simple-patches/$p.before" "$OUT/simple-patches/$p.after"
done
: > "$SRC/$TCC_PKG/config.h"
for p in tinycc/patches/tcc-0.9.26/*.diff; do
    patch --quiet --forward --no-backup-if-mismatch -F0 -p1 -d "$SRC/$TCC_PKG" < "$p"
done

# portable libc
tar -xzf "$IN/$PNUT.tar.gz" -C "$SRC" --no-same-owner --strip-components=1 "$PNUT/portable_libc"
mv "$SRC/portable_libc" "$SRC/libc64"

cp tinycc/direct-input.c "$SRC/direct-input.c"
# --prepare: stop here; tests/tinycc/hex0-handoff-check.sh compiles under K0
if [ "${1:-}" = --prepare ]; then
    echo "build-first-tcc: sources prepared in $SRC"
    exit 0
fi

# Compile.  Native mode loads 020 to 119 except 081 (seed-forth's
# tools/tcc-start.fth list); 120's main is not loaded.
[ -x seed-forth ] || seed/build.sh > /dev/null
layers=(forth/010-lib.fth)
for n in 020 030 040 050 060 070 080 090 100 110 112 114 115 116 117 118 119; do
    layers+=(cc/$n-*.fth)
done
rm -f "$OUT/tcc-first"
rc=0
cat "${layers[@]}" tinycc/tcc-compile.fth "$SRC/direct-input.c" \
    | ./seed-forth > "$OUT/compile.stdout" 2>&1 || rc=$?
# The Forth outer interpreter reports an unknown word on stdout and goes on,
# so anything on stdout is a failure even when the exit status is 0.
if [ "$rc" != 0 ] || [ -s "$OUT/compile.stdout" ] || [ ! -s "$OUT/tcc-first" ]; then
    head -c 2000 "$OUT/compile.stdout" >&2
    fail "seed-forth exited $rc (cc/ error codes are the exit status)"
fi
chmod 755 "$OUT/tcc-first"

echo "build-first-tcc: $(wc -c < "$OUT/tcc-first") bytes"
sha256sum "$OUT/tcc-first"
want=$(sed -n 's|^\([0-9a-f]\{64\}\)  tinycc/tcc-first$|\1|p' tests/pins/tinycc.sha256)
got=$(sha256sum "$OUT/tcc-first" | cut -d' ' -f1)
if [ "$got" != "$want" ]; then
    fail "build-out/tinycc/tcc-first is $got, tests/pins/tinycc.sha256 says ${want:-nothing}"
fi
echo "build-first-tcc: as pinned in tests/pins/tinycc.sha256"
