#!/usr/bin/env bash
# tests/forth/i386/high-halves-check.sh -- run the vectors of
# tests/forth/i386/high-halves.fth.
#
#     tests/forth/i386/high-halves-check.sh     (from anywhere)
#
# The vectors ask each primitive of forth/i386/020-cc-arena.fth for an
# answer on cells whose two halves both matter, on the seed:
# ./seed-forth-i386 (seed/i386/build.sh) or the program SEED_I386 names.
# The run passes when it prints "high-halves: done" and exits 0; the exit
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

[ -x "$SEED" ] || { echo "high-halves-check: cannot run: no i386 seed: $SEED" >&2; exit 1; }
cases=$(grep -v '^\\' $D/high-halves.fth | grep -o 'same tally' | wc -l)
rc=0; out=$("$SEED" forth/i386/010-lib.fth $D/high-halves-job.fth) || rc=$?
passed "the seed with forth/i386/020-cc-arena.fth" "$rc" "$out"
echo "high-halves-check: OK, $cases cases"
