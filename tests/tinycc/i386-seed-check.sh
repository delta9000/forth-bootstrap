#!/usr/bin/env bash
# tests/tinycc/i386-seed-check.sh -- the i386 seed and the i386 host files
# compile what the x86-64 seed compiles, byte for byte, with builder-hex0's
# system calls only.
#
#     tests/tinycc/i386-seed-check.sh           (from anywhere)
#     tests/tinycc/i386-seed-check.sh --probe   exit 0 when this can run here
#
# The seed is ./seed-forth-i386 (seed/i386/build.sh), or the program
# SEED_I386 names.  It runs on the host's kernel through its IA32 support,
# always as
#     seed-forth-i386 forth/i386/010-lib.fth JOB [ARG ...]
#
# 1. The library's own tests: forth/test-010-lib.fth as the job exits 0;
#    tests/forth/i386/high-halves-check.sh runs its vectors on this seed;
#    tests/forth/i386/host-words-check.sh runs include and brk-alloc where
#    no compile takes them.
# 2. The oracle (seed/i386/SPEC.md 13.2, forth/i386/CONTRACT.md 9).  The
#    x86-64 seed builds the i386 first tcc, the eleven tools and kaem
#    (tinycc/build-first-tcc-i386.sh, tinycc/build-tools-i386.sh), all
#    pinned.  The i386 seed builds the same thirteen programs from the same
#    sources with tinycc/i386-seed/tcc-first.fth and tool.fth, and each
#    must have the same bytes.  The two hosts share every file from
#    cc/030-cc-io.fth on and both drivers; they differ in the seed, the
#    library, 020 and the two shadows, that is, in every instruction the
#    Forth system itself executes.
# 3. Every one of those thirteen runs is made under strace, and
#    tests/tinycc/i386-seed-syscall-check.py reads the traces: only brk,
#    open, read, write, close and exit; the break never lowered and never
#    above 0x28000000; no read of descriptor 0; every C file closed; the
#    output file opened after everything else was read.  Linux is the
#    kernel here, so this shows the calls made, not builder-hex0's answers.
set -euo pipefail
cd "$(dirname "$0")/../.."

SEED=${SEED_I386:-./seed-forth-i386}
OUT=build-out/tinycc
W=$OUT/i386-seed
LIB=forth/i386/010-lib.fth

probe() {
    [ -x "$SEED" ] || { echo "no i386 seed: $SEED (seed/i386/build.sh, or set SEED_I386)"; return 1; }
    tests/tinycc/junction-check.sh --probe || return 1
    command -v strace > /dev/null || { echo "missing: strace"; return 1; }
    command -v python3 > /dev/null || { echo "missing: python3"; return 1; }
}
if [ "${1:-}" = --probe ]; then
    probe
    exit
fi
why=$(probe) || { echo "i386-seed-check: cannot run: $why" >&2; exit 1; }
fail() { echo "i386-seed-check: FAIL: $*" >&2; exit 1; }

# ---- 1. the library on this seed ----
rc=0
"$SEED" $LIB forth/test-010-lib.fth || rc=$?
[ "$rc" = 0 ] || fail "forth/test-010-lib.fth through $LIB exited $rc"
echo "i386-seed-check: forth/test-010-lib.fth passes through $LIB"
SEED_I386=$SEED tests/forth/i386/high-halves-check.sh | tail -1
SEED_I386=$SEED tests/forth/i386/host-words-check.sh | tail -1

# ---- 2. the x86-64 seed's builds, the reference ----
tinycc/build-first-tcc-i386.sh | tail -1
tinycc/build-tools-i386.sh | tail -1

# ---- 2 and 3. the same programs by the i386 seed, under strace ----
rm -rf "$W"
mkdir -p "$W/bin"
same=0
# build REFERENCE JOB OUT ARG...: one seed run; OUT must equal REFERENCE.
# Anything the run prints is a failure: an unknown word is reported on
# stdout, a compiler error on stderr.
build() {
    local ref=$1 job=$2 out=$3 rc=0
    shift 3
    strace -o "$out.strace" "$SEED" $LIB "$job" "$out" "$@" > "$out.log" 2>&1 || rc=$?
    if [ "$rc" != 0 ] || [ -s "$out.log" ]; then
        head -c 1000 "$out.log" >&2
        fail "$SEED exited $rc building $out (cc/ error codes are the exit status)"
    fi
    cmp "$out" "$ref" || fail "$out is not the x86-64 seed's $ref"
    same=$((same + 1))
}
tool() { build "$OUT/bin-i386/$1" tinycc/i386-seed/tool.fth "$W/bin/$1" "${@:2}"; }

S=build-out/tcc-sources-i386
build "$OUT/tcc-first-i386" tinycc/i386-seed/tcc-first.fth "$W/tcc-first-i386" \
    "$S/direct-input.c" "$S/mes-0.28/include" "$S/mes-0.28/include/linux/x86"
echo "i386-seed-check: the first tcc, $(wc -c < "$W/tcc-first-i386") bytes, $(sha256sum "$W/tcc-first-i386" | cut -c1-8)..., as the x86-64 seed's"

# the sources tinycc/build-tools-i386.sh gives the x86-64 seed
X=vendor/stage0-posix/mescc-tools-extra
TS=$OUT/tools-src
LB=$OUT/lb/live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9
K=vendor/mescc-tools/Kaem
for t in catm sha256sum mkdir cp chmod rm match; do
    tool $t "$X/$t.c"
done
for t in ungz untar; do
    tool $t "$TS/$t.c"
done
tool simple-patch "$LB/steps/simple-patch-1.0/src/simple-patch.c"
tool checksum-transcriber "$LB/steps/checksum-transcriber-1.0/src/checksum-transcriber.c"
[ "$(ls "$W/bin" | grep -cv '\.')" = "$(ls "$OUT/bin-i386" | wc -l)" ] \
    || fail "$OUT/bin-i386 has a tool this script does not build"
build "$OUT/kaem-i386" tinycc/i386-seed/tool.fth "$W/kaem-i386" \
    tinycc/m2libc-kaem-i386.c "$K/variable.c" "$K/kaem_globals.c" "$K/kaem.c"
echo "i386-seed-check: $same programs (the first tcc, eleven tools, kaem) have the x86-64 seed's bytes"

python3 tests/tinycc/i386-seed-syscall-check.py "$W"/*.strace "$W"/bin/*.strace
echo "i386-seed-check: OK"
