#!/usr/bin/env bash
# tinycc/build-first-tcc-i386.sh -- the first tcc, built by the i386 seed.
#
#     tinycc/build-first-tcc-i386.sh    (from anywhere; works in the repo root)
#
# Writes build-out/tinycc/tcc-first-i386: janneke's
# tcc-0.9.26-1147-gee75a10c with Mes 0.28's libc in one translation unit,
# compiled by one run of the seed,
#     seed-forth-i386 forth/i386/010-lib.fth tinycc/i386-seed/tcc-first.fth \
#         OUT SOURCE INCLUDE INCLUDE-LINUX
# into a static ELF32 program for Linux's int 0x80 and for builder-hex0.
# It takes the place of live-bootstrap's MesCC-built tcc-mes.
#
# The sources are prepared in build-out/tcc-sources-i386/ by the seed-built
# tools (tinycc/build-tools-i386.sh, which this runs first), with the
# commands the one boot runs (tinycc/i386-one-boot-disk.py):
#   tcc is unpacked and gets what steps/tcc-0.9.26/pass1.kaem does before
#       MesCC runs: two simple-patches of tcctools.c and an empty config.h;
#   Mes is unpacked; include/arch/ gets Mes's include/linux/x86 headers,
#       as live-bootstrap's steps/mes-0.28 gives it on x86;
#   tinycc/direct-input-i386.c is the one file the compiler is given: it
#       defines __i386__ and includes tinycc/mes-libc.c, whose system-call
#       layer is tinycc/mes-libc-native-i386.c, and tcc.c.
#
# With SEED_TRACE=DIR in the environment the seed runs under strace and
# leaves DIR/tcc-first-i386.strace.
set -euo pipefail
cd "$(dirname "$0")/.."

IN=build-out/tinycc-inputs
OUT=build-out/tinycc
SRC=build-out/tcc-sources-i386
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9
TCC_PKG=tcc-0.9.26-1147-gee75a10c
MES=mes-0.28

fail() { echo "build-first-tcc-i386: $*" >&2; exit 1; }

tinycc/build-tools-i386.sh
BIN=build-out/tinycc/bin-i386
SEED=${SEED_I386:-./seed-forth-i386}

rm -rf "$SRC"
mkdir -p "$SRC"

# tcc: unpack, then what pass1.kaem does before MesCC runs
"$BIN/ungz" --file "$IN/tcc-0.9.26.tar.gz" --output "$SRC/tcc.tar" 2> /dev/null \
    || fail "ungz failed on tcc-0.9.26.tar.gz"
(cd "$SRC" && ../tinycc/bin-i386/untar --non-strict --file tcc.tar > /dev/null 2>&1) \
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
(cd "$SRC" && ../tinycc/bin-i386/untar --non-strict --file mes.tar > /dev/null 2>&1) \
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

# Compile.  Anything the seed prints is a failure: the Forth outer
# interpreter reports an unknown word on stdout and goes on, and the
# compiler reports an error on stderr.
rm -f "$OUT/tcc-first-i386"
rc=0
${SEED_TRACE:+strace -o "$SEED_TRACE/tcc-first-i386.strace"} \
    "$SEED" forth/i386/010-lib.fth tinycc/i386-seed/tcc-first.fth "$OUT/tcc-first-i386" \
    "$SRC/direct-input.c" "$SRC/$MES/include" "$SRC/$MES/include/linux/x86" \
    > "$OUT/compile-i386.log" 2>&1 || rc=$?
if [ "$rc" != 0 ] || [ -s "$OUT/compile-i386.log" ] || [ ! -s "$OUT/tcc-first-i386" ]; then
    head -c 2000 "$OUT/compile-i386.log" >&2
    fail "$SEED exited $rc (cc/ error codes are the exit status)"
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
