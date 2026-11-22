#!/usr/bin/env bash
# tests/tinycc/i386-seed-check.sh -- the seed's host builds under strace:
# the pinned bytes, with builder-hex0's system calls only.
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
#    tests/forth/i386/high-halves-check.sh runs its vectors;
#    tests/forth/i386/host-words-check.sh runs include and brk-alloc where
#    no compile takes them.
# 2. The oracle (seed/i386/SPEC.md 13.2, forth/i386/CONTRACT.md 9).
#    tinycc/build-tools-i386.sh and tinycc/build-first-tcc-i386.sh build
#    kaem, the stock ungz and untar, the eleven tools and the first tcc,
#    and compare all fifteen with tests/pins/tinycc.sha256.
# 3. Every one of those fifteen seed runs is made under strace
#    (SEED_TRACE), and tests/tinycc/i386-seed-syscall-check.py reads the
#    traces: only brk, open, read, write, close and exit; the break never
#    lowered and never above 0x28000000; no read of descriptor 0; every C
#    file closed; the output file opened after everything else was read.
#    Linux is the kernel here, so this shows the calls made, not
#    builder-hex0's answers; tests/tinycc/i386-one-boot-check.sh is the
#    run on builder-hex0.
set -euo pipefail
cd "$(dirname "$0")/../.."

[ -n "${SEED_I386:-}" ] || seed/i386/build.sh > /dev/null 2>&1 || true
SEED=${SEED_I386:-./seed-forth-i386}
W=build-out/tinycc/i386-seed
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

# ---- 1. the library on the seed ----
rc=0
"$SEED" $LIB forth/test-010-lib.fth || rc=$?
[ "$rc" = 0 ] || fail "forth/test-010-lib.fth through $LIB exited $rc"
echo "i386-seed-check: forth/test-010-lib.fth passes through $LIB"
SEED_I386=$SEED tests/forth/i386/high-halves-check.sh | tail -1
SEED_I386=$SEED tests/forth/i386/host-words-check.sh | tail -1

# ---- 2 and 3. the builds, every seed run under strace ----
rm -rf "$W"
mkdir -p "$W"
SEED_TRACE=$W tinycc/build-first-tcc-i386.sh | grep -v '^build-first-tcc-i386: [0-9]'
[ "$(ls "$W" | wc -l)" = 15 ] || fail "$(ls "$W" | wc -l) traces in $W, not 15"
python3 tests/tinycc/i386-seed-syscall-check.py "$W"/*.strace
echo "i386-seed-check: OK"
