#!/usr/bin/env bash
# tests/tinycc/i386-standin-check.sh -- the i386 first tcc against a gcc
# build of the same program, file by file.
#
#     tests/tinycc/i386-standin-check.sh        (from anywhere)
#
# The junction's pins are the last files of a long build.  This compares
# everything on the way: gcc -m32 compiles the unit the i386 back end
# compiles (build-out/tcc-sources-i386/direct-input.c: the same tcc, the
# same Mes libc C and headers, the same ILP32 model), with Mes's own i386
# assembly files where the Forth build has tinycc/mes-libc-native-i386.c.
# Each first compiler then runs the junction replay as far as its own
# work goes (tests/tinycc/junction-check.sh with JUNCTION_FIRST_ONLY: Mes
# libc's crt files, unified-libc.o, libc.a, libtcc1, getopt and tcc-boot0,
# before tcc-boot0 rebuilds any of them), and every file each run leaves
# in its root and in live-bootstrap's steps/ must have the same bytes.
# Two differences are expected and listed: tcc-mes, the first compiler
# itself, and the *.a.tmp files tcc -ar leaves behind when its unlink does
# nothing, which is what the Forth build's system-call layer does for a
# call builder-hex0 lacks.
#
# The stand-in's own output is not always the same.  Measured on
# 2026-11-21: of 12 runs of the stand-in, 10 made the tcc-boot0 the Forth
# build makes (c1696e57...) and 2 made 9cb082b3...; under setarch -R (no
# address randomization) all 12 made 9cb082b3....  So what the gcc build
# of this tcc writes depends on where the kernel loads it, and this check
# then fails on tcc-boot0 alone; run it again.  The Forth-built first tcc
# is loaded at a fixed address with a zeroed stack and always makes the
# pinned file.  Why the gcc build varies has not been found.
#
# The stand-in is a test reference built by a host compiler, never part of
# the route.  Needs gcc with -m32 support and its 32-bit libgcc, and what
# junction-check.sh needs.
set -euo pipefail
cd "$(dirname "$0")/../.."
export LC_ALL=C

OUT=build-out/tinycc
SRC=build-out/tcc-sources-i386
D=$OUT/standin
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9
MES=mes-0.28

fail() { echo "i386-standin-check: FAIL: $*" >&2; exit 1; }

echo 'int main (void) { return 0; }' | gcc -m32 -x c - -o /dev/null 2> /dev/null \
    || { echo "i386-standin-check: cannot run: gcc -m32 does not build a program here" >&2; exit 1; }

# sums ROOT STEPS: sha256 and name of every file of a finished replay
sums() {
    {
        (cd "$OUT/junction-root" && find . -type f -exec sha256sum {} +)
        (cd "$OUT/lb/$LB/steps" && find . -type f -exec sha256sum {} + | sed 's|  \./|  ./steps/|')
    } | sort
}

# The Forth-built i386 first tcc, and its replay
JUNCTION_FIRST_ONLY=1 tests/tinycc/junction-check.sh > "$OUT/standin-forth.out" 2>&1 \
    || { tail -20 "$OUT/standin-forth.out" >&2; fail "the junction failed with the i386 first tcc"; }
sums > "$OUT/standin-forth.sums"

# The stand-in: Mes's assembly files in place of mes-libc-native.c
rm -rf "$D"
mkdir -p "$D"
cp "$SRC/direct-input.c" "$SRC/mes-libc.c" "$D/"
for f in linux/x86-mes-gcc/syscall.c linux/x86-mes-gcc/_exit.c linux/x86-mes-gcc/_write.c \
         x86-mes-gcc/setjmp.c mes/abtod.c mes/dtoab.c math/ceil.c; do
    echo "#include \"$MES/lib/$f\""
done > "$D/mes-libc-native.c"
flags=(-m32 -std=gnu99 -nostdinc -O0 -w -fno-stack-protector -fno-pie -U__SIZEOF_LONG_LONG__
       -iquote "$SRC" -I "$SRC/$MES/include" -I "$SRC/$MES/include/linux/x86")
gcc "${flags[@]}" -c "$D/direct-input.c" -o "$D/unit.o" || fail "gcc could not compile the unit"
gcc "${flags[@]}" -c "$SRC/$MES/lib/linux/x86-mes-gcc/crt1.c" -o "$D/crt1.o" || fail "gcc could not compile crt1.c"
gcc -m32 -static -no-pie -nostdlib -o "$D/tcc-standin" "$D/crt1.o" "$D/unit.o" -lgcc || fail "the stand-in did not link"

JUNCTION_FIRST_ONLY=1 tests/tinycc/junction-check.sh "$D/tcc-standin" > "$OUT/standin-gcc.out" 2>&1 \
    || { tail -20 "$OUT/standin-gcc.out" >&2; fail "the junction failed with the stand-in"; }
sums > "$OUT/standin-gcc.sums"

# Compare
same=$(comm -12 "$OUT/standin-forth.sums" "$OUT/standin-gcc.sums" | wc -l)
comm -3 "$OUT/standin-forth.sums" "$OUT/standin-gcc.sums" | sed 's/^\t*//' | cut -d' ' -f3 | sort -u > "$OUT/standin.differ"
bad=0
while read -r f; do
    case $f in
        ./usr/bin/tcc-mes|./steps/tcc-0.9.26/build/*/tcc-mes)
            echo "  expected  $f (the first compiler itself)" ;;
        *.a.tmp)
            echo "  expected  $f (left by tcc -ar; only the Forth build's unlink does nothing)" ;;
        *)
            echo "  FAIL      $f differs"
            bad=$((bad + 1)) ;;
    esac
done < "$OUT/standin.differ"
echo "i386-standin-check: $same files the same; the first compiler's own:"
comm -12 "$OUT/standin-forth.sums" "$OUT/standin-gcc.sums" | grep -E '\.[oa]$|/tcc-boot0$' | sed 's/^/  same      /'
[ "$bad" = 0 ] || fail "$bad file(s) differ between the two first compilers"
echo "i386-standin-check: OK, both first compilers leave the same bytes in every other file"
