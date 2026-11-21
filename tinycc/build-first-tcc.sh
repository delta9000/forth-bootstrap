#!/usr/bin/env bash
# tinycc/build-first-tcc.sh -- seed Forth compiles the first tcc.
#
#     tinycc/build-first-tcc.sh        (from anywhere; works in the repo root)
#
# Writes build-out/tinycc/tcc-first: janneke's tcc-0.9.26-1147-gee75a10c
# targeting i386, the compiler live-bootstrap builds with MesCC as
# /usr/bin/tcc-mes, here compiled by the Forth compiler in native mode.
# The only program that runs to build it is seed-forth (1,772 bytes, from
# seed/000-seed.hex0), reading forth/010-lib.fth, the compiler layers,
# tinycc/tcc-compile.fth and the C source on stdin.  No host compiler,
# preprocessor, assembler or linker takes part.
#
# The source preparation is done by the tools tinycc/build-tools.sh builds
# from the seed (native mode against M2libc, from stage0-posix's and
# live-bootstrap's C): its
# sha256sum checks the archives against tinycc/SOURCES, ungz and untar
# unpack them, simple-patch applies live-bootstrap's simple-patches, mkdir
# and cp lay out Mes's include/arch as live-bootstrap's steps/mes-0.28 does,
# and catm writes the empty config.h files, copies our three files and
# joins the Forth input (layers, driver, direct-input.c) that seed-forth
# reads on stdin.  Host programs left here: bash runs this script; rm and
# mkdir -p clear and make build-out directories; dirname finds the
# repository; wc, sha256sum, sed and cut print the size and compare the
# result with its pin.
#
# The source tree, build-out/tcc-sources/:
#   tcc-0.9.26-1147-gee75a10c/  tinycc-inputs/tcc-0.9.26.tar.gz with what
#       live-bootstrap's steps/tcc-0.9.26/pass1.kaem does before it runs
#       MesCC: its two simple-patches to tcctools.c (from the pinned
#       live-bootstrap tree) and an empty config.h.  Nothing else.
#   mes-0.28/  tinycc-inputs/mes-0.28.tar.gz, whole, with what
#       live-bootstrap does before compiling its libc: an empty
#       include/mes/config.h (steps/tcc-0.9.26/pass1.kaem) and
#       include/arch/ holding include/linux/x86_64's kernel-stat.h, signal.h
#       and syscall.h (steps/mes-0.28/pass1.kaem).  Only include/ and the
#       lib/ files tinycc/mes-libc.c names are read.
#   mes-libc.c, mes-libc-native.c  tinycc/'s: the list of Mes libc files
#       and the plain-C stand-in for its assembly
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
MES=mes-0.28
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9

fail() { echo "build-first-tcc: $*" >&2; exit 1; }

# The tools; they check the archives against tinycc/SOURCES and unpack
# live-bootstrap's tree into build-out/tinycc/lb/
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

# Mes libc
"$BIN/ungz" --file "$IN/$MES.tar.gz" --output "$SRC/mes.tar" 2> /dev/null \
    || fail "ungz failed on $MES.tar.gz"
(cd "$SRC" && ../tinycc/bin/untar --non-strict --file mes.tar > /dev/null 2>&1) \
    || fail "untar failed on mes.tar"
"$BIN/catm" "$SRC/$MES/include/mes/config.h"
"$BIN/mkdir" "$SRC/$MES/include/arch"
for h in kernel-stat.h signal.h syscall.h; do
    "$BIN/cp" "$SRC/$MES/include/linux/x86_64/$h" "$SRC/$MES/include/arch/$h"
done
"$BIN/rm" "$SRC/tcc.tar"
"$BIN/rm" "$SRC/mes.tar"

"$BIN/catm" "$SRC/direct-input.c" tinycc/direct-input.c
"$BIN/catm" "$SRC/mes-libc.c" tinycc/mes-libc.c
"$BIN/catm" "$SRC/mes-libc-native.c" tinycc/mes-libc-native.c

# Compile.  Native mode loads 020 to 119 except 081 (seed-forth's
# tools/tcc-start.fth list); 120's main is not loaded.
[ -x seed-forth ] || seed/build.sh > /dev/null
layers=(forth/010-lib.fth)
for n in 020 030 040 050 060 070 080 090 100 110 112 114 115 116 117 118 119; do
    layers+=(cc/$n-*.fth)
done
rm -f "$OUT/tcc-first" "$OUT/compile.input"
rc=0
"$BIN/catm" "$OUT/compile.input" "${layers[@]}" tinycc/tcc-compile.fth "$SRC/direct-input.c"
./seed-forth < "$OUT/compile.input" > "$OUT/compile.stdout" 2>&1 || rc=$?
# The Forth outer interpreter reports an unknown word on stdout and goes on,
# so anything on stdout is a failure even when the exit status is 0.
if [ "$rc" != 0 ] || [ -s "$OUT/compile.stdout" ] || [ ! -s "$OUT/tcc-first" ]; then
    head -c 2000 "$OUT/compile.stdout" >&2
    fail "seed-forth exited $rc (cc/ error codes are the exit status)"
fi
"$BIN/chmod" 755 "$OUT/tcc-first"

echo "build-first-tcc: $(wc -c < "$OUT/tcc-first") bytes"
sha256sum "$OUT/tcc-first"
want=$(sed -n 's|^\([0-9a-f]\{64\}\)  tinycc/tcc-first$|\1|p' tests/pins/tinycc.sha256)
got=$(sha256sum "$OUT/tcc-first" | cut -d' ' -f1)
if [ "$got" != "$want" ]; then
    fail "build-out/tinycc/tcc-first is $got, tests/pins/tinycc.sha256 says ${want:-nothing}"
fi
echo "build-first-tcc: as pinned in tests/pins/tinycc.sha256"
