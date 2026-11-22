#!/usr/bin/env bash
# test.sh -- the library's and the first compiler layers' own tests, on
# the seed.
#
#     ./test.sh        (from anywhere)
#
# forth/test-010-lib.fth and each cc/test-NNN-*.fth is a Forth file that
# exits 0 when every case in it holds and 255 at the first that does not.
# Each runs as the seed's job,
#     seed-forth-i386 forth/i386/010-lib.fth JOB
# where JOB includes the compiler's files in the order of
# forth/i386/layers.fth up to the layer under test, then the test.  Every
# test runs; the script exits 1 at the end if one failed.  The seed's own
# tests are tests/seed/i386/test.sh.
set -euo pipefail
cd "$(dirname "$0")"

[ -n "${SEED_I386:-}" ] || seed/i386/build.sh > /dev/null
SEED=${SEED_I386:-./seed-forth-i386}
W=build-out/test
rm -rf "$W"
mkdir -p "$W"

PASSED=0
FAILED=0
# run NAME JOB: anything the seed prints is a failure too (an unknown word
# is reported on stdout).
run() {
    local ec=0 out
    out=$("$SEED" forth/i386/010-lib.fth "$2" 2>&1) || ec=$?
    if [ "$ec" = 0 ] && [ -z "$out" ]; then
        echo "  PASS: $1"; PASSED=$((PASSED + 1))
    else
        echo "  FAIL: $1: exit $ec, printed '${out: -200}'"; FAILED=$((FAILED + 1))
    fi
}

run forth/test-010-lib.fth forth/test-010-lib.fth
for t in cc/test-[0-9][0-9][0-9]-*.fth; do
    n=${t#cc/test-}
    n=${n%%-*}
    # the lines of layers.fth up to and including layer n's last file
    awk -v n="$n" '/^include / { split($2, a, "/"); if (substr(a[length(a)], 1, 3) > n) exit; print }' \
        forth/i386/layers.fth > "$W/$n.fth"
    echo "include $t" >> "$W/$n.fth"
    run "$t" "$W/$n.fth"
done

echo
echo "test.sh: $PASSED passed, $FAILED failed"
[ "$FAILED" = 0 ]
