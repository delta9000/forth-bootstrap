#!/usr/bin/env bash
# tests/forth/high-halves-check.sh -- run the vectors of
# tests/forth/high-halves.fth.
#
#     tests/forth/high-halves-check.sh     (from anywhere)
#
# The vectors ask each primitive of forth/020-cc-arena.fth for an
# answer on cells whose two halves both matter, on the seed:
# ./seed-forth (seed/build.sh) or the program SEED_FORTH names.
# The run passes when it prints "high-halves: done" and exits 0; the exit
# status is the number of failed cases.
#
# First, tests/reference.py computes each case in Python and compares the
# value the file expects with its own, so that the expected values do not
# rest on the seed they judge.  It does not compute the three cases with
# control flow.
set -euo pipefail
cd "$(dirname "$0")/../.."

D=tests/forth
SEED=${SEED_FORTH:-./seed-forth}
fail() { echo "high-halves-check: FAIL: $*" >&2; exit 1; }
passed() {    # WHAT STATUS OUTPUT
    [ "$3" = "high-halves: done" ] || fail "$1: the vectors did not reach their end (exit $2, printed '$3')"
    [ "$2" = 0 ] || fail "$1: $2 case(s) failed"
}

[ -x "$SEED" ] || { echo "high-halves-check: cannot run: no i386 seed: $SEED" >&2; exit 1; }
cases=$(grep -v '^\\' $D/high-halves.fth | grep -o 'same tally' | wc -l)
python3 -I tests/reference.py high-halves $D/high-halves.fth \
    || fail "an expected value differs from what tests/reference.py computes"
rc=0; out=$("$SEED" forth/010-lib.fth $D/high-halves-job.fth) || rc=$?
passed "the seed with forth/020-cc-arena.fth" "$rc" "$out"
echo "high-halves-check: OK, $cases cases"
