#!/usr/bin/env bash
# tinycc/build-first-tcc-i386.sh -- the i386 first tcc, by seed Forth.
#
#     tinycc/build-first-tcc-i386.sh    (from anywhere; works in the repo root)
#
# Writes build-out/tinycc/tcc-first-i386: the program
# tinycc/build-first-tcc.sh builds (janneke's tcc-0.9.26-1147-gee75a10c
# with Mes 0.28's libc in one translation unit), compiled by the i386 back
# end (cc/i386/, in the order cc/i386/layers.sh prints) into a static ELF32
# that runs on Linux through int 0x80 and is written for builder-hex0.
# seed-forth, the x86-64 one, is still the only program that compiles
# anything.
#
# What differs from build-first-tcc.sh:
#   the sources are prepared in build-out/tcc-sources-i386/, the same way,
#       but include/arch/ gets Mes's include/linux/x86 headers, as
#       live-bootstrap's steps/mes-0.28 gives it on x86;
#   tinycc/direct-input-i386.c defines __i386__;
#   tinycc/mes-libc-native-i386.c is the system-call layer;
#   tinycc/tcc-compile-i386.fth is the driver, and tinycc/tcc-names-i386.fth
#       gives it its four paths.
# The source-preparation tools are build-tools.sh's, which this runs first.
set -euo pipefail
cd "$(dirname "$0")/.."

IN=build-out/tinycc-inputs
OUT=build-out/tinycc
SRC=build-out/tcc-sources-i386
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9
TCC_PKG=tcc-0.9.26-1147-gee75a10c
MES=mes-0.28

fail() { echo "build-first-tcc-i386: $*" >&2; exit 1; }

tinycc/build-tools.sh
BIN=build-out/tinycc/bin

rm -rf "$SRC"
mkdir -p "$SRC"

# tcc: unpack, then what pass1.kaem does before MesCC runs
"$BIN/ungz" --file "$IN/tcc-0.9.26.tar.gz" --output "$SRC/tcc.tar" 2> /dev/null \
    || fail "ungz failed on tcc-0.9.26.tar.gz"
(cd "$SRC" && ../tinycc/bin/untar --non-strict --file tcc.tar > /dev/null 2>&1) \
    || fail "untar failed on tcc.tar"
SP=$OUT/lb/$LB/steps/tcc-0.9.26/simple-patches
for p in remove-fileopen addback-fileopen; do
    "$BIN/simple-patch" "$SRC/$TCC_PKG/tcctools.c" "$SP/$p.before" "$SP/$p.after" \
        || fail "simple-patch $p failed"
done
"$BIN/catm" "$SRC/$TCC_PKG/config.h"

# Mes libc, with the x86 headers in include/arch
"$BIN/ungz" --file "$IN/$MES.tar.gz" --output "$SRC/mes.tar" 2> /dev/null \
    || fail "ungz failed on $MES.tar.gz"
(cd "$SRC" && ../tinycc/bin/untar --non-strict --file mes.tar > /dev/null 2>&1) \
    || fail "untar failed on mes.tar"
"$BIN/catm" "$SRC/$MES/include/mes/config.h"
"$BIN/mkdir" "$SRC/$MES/include/arch"
for h in kernel-stat.h signal.h syscall.h; do
    "$BIN/cp" "$SRC/$MES/include/linux/x86/$h" "$SRC/$MES/include/arch/$h"
done
"$BIN/rm" "$SRC/tcc.tar"
"$BIN/rm" "$SRC/mes.tar"

"$BIN/catm" "$SRC/direct-input.c" tinycc/direct-input-i386.c
"$BIN/catm" "$SRC/mes-libc.c" tinycc/mes-libc.c
"$BIN/catm" "$SRC/mes-libc-native.c" tinycc/mes-libc-native-i386.c

# Compile, with the i386 layers.
[ -x seed-forth ] || seed/build.sh > /dev/null
mapfile -t layers < <(cc/i386/layers.sh)
rm -f "$OUT/tcc-first-i386" "$OUT/compile-i386.input"
rc=0
"$BIN/catm" "$OUT/compile-i386.input" "${layers[@]}" tinycc/tcc-names-i386.fth \
    tinycc/tcc-compile-i386.fth "$SRC/direct-input.c"
./seed-forth < "$OUT/compile-i386.input" > "$OUT/compile-i386.stdout" 2>&1 || rc=$?
# The Forth outer interpreter reports an unknown word on stdout and goes on,
# so anything on stdout is a failure even when the exit status is 0.
if [ "$rc" != 0 ] || [ -s "$OUT/compile-i386.stdout" ] || [ ! -s "$OUT/tcc-first-i386" ]; then
    head -c 2000 "$OUT/compile-i386.stdout" >&2
    fail "seed-forth exited $rc (cc/ error codes are the exit status)"
fi
"$BIN/chmod" 755 "$OUT/tcc-first-i386"

echo "build-first-tcc-i386: $(wc -c < "$OUT/tcc-first-i386") bytes"
sha256sum "$OUT/tcc-first-i386"
want=$(sed -n 's|^\([0-9a-f]\{64\}\)  tinycc/tcc-first-i386$|\1|p' tests/pins/tinycc.sha256)
got=$(sha256sum "$OUT/tcc-first-i386" | cut -d' ' -f1)
if [ "$got" != "$want" ]; then
    fail "build-out/tinycc/tcc-first-i386 is $got, tests/pins/tinycc.sha256 says ${want:-nothing}"
fi
echo "build-first-tcc-i386: as pinned in tests/pins/tinycc.sha256"
