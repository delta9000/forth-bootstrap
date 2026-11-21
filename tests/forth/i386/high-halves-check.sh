#!/usr/bin/env bash
# tests/forth/i386/high-halves-check.sh -- run the vectors of
# tests/forth/i386/high-halves.fth.
#
#     tests/forth/i386/high-halves-check.sh     (from anywhere)
#
# The vectors ask each primitive of 020 for an answer on cells whose two
# halves both matter.  The same text runs on every host:
#   - the x86-64 seed with forth/010-lib.fth alone, where each word is the
#     library's Forth on the seed's 64-bit arithmetic.  This is where the
#     expected values come from: they are right if they pass here;
#   - the x86-64 seed with cc/020-cc-arena.fth, its machine code;
#   - the i386 seed with forth/i386/020-cc-arena.fth, the code the vectors
#     are for: ./seed-forth-i386 (seed/i386/build.sh) or the program
#     SEED_I386 names.  Without one, that run is reported as not made.
# A run passes when it prints "high-halves: done" and exits 0; the exit
# status is the number of failed cases.
set -euo pipefail
cd "$(dirname "$0")/../../.."

D=tests/forth/i386
SEED=${SEED_I386:-./seed-forth-i386}
fail() { echo "high-halves-check: FAIL: $*" >&2; exit 1; }
passed() {    # WHAT STATUS OUTPUT
    [ "$3" = "high-halves: done" ] || fail "$1: the vectors did not reach their end (exit $2, printed '$3')"
    [ "$2" = 0 ] || fail "$1: $2 case(s) failed"
}

[ -x seed-forth ] || seed/build.sh > /dev/null
cases=$(grep -v '^\\' $D/high-halves.fth | grep -o 'same tally' | wc -l)
rc=0; out=$(cat forth/010-lib.fth $D/high-halves-judge.fth $D/high-halves.fth | ./seed-forth) || rc=$?
passed "the x86-64 seed, library only" "$rc" "$out"
rc=0; out=$(cat forth/010-lib.fth $D/high-halves-judge.fth cc/020-cc-arena.fth $D/high-halves.fth | ./seed-forth) || rc=$?
passed "the x86-64 seed with cc/020-cc-arena.fth" "$rc" "$out"
if [ -x "$SEED" ]; then
    rc=0; out=$("$SEED" forth/i386/010-lib.fth $D/high-halves-job.fth) || rc=$?
    passed "the i386 seed with forth/i386/020-cc-arena.fth" "$rc" "$out"
    echo "high-halves-check: OK, $cases cases on the x86-64 seed (library only, and with 020) and on the i386 seed"
else
    echo "high-halves-check: OK, $cases cases on the x86-64 seed (library only, and with 020); NOT RUN on the i386 seed: no $SEED"
fi
