#!/usr/bin/env bash
# check-all.sh -- the repository's checks in one run.
#
# Quick steps (about a minute):
#   01  seed/build.sh: hex0-seed assembles seed/000-seed.hex0 into the
#       1,772-byte seed-forth
#   02  ./test.sh: the seed primitives, forth/010-lib.fth and the first
#       compiler layers
#   03  tools/check-pins.py: every archive pin agrees with MANIFEST.sha256
#   04  Stage A (tests/cc/stage-a-check.sh): the Forth compiler's M1 for
#       M2-Planet equals a GCC-built M2-Planet's (needs gcc; SKIP without)
#   05  kernel/k1/tests/direct-build-check.sh: seed Forth builds K1 with no
#       other program running, its objects equal seed-cc's, and
#       k1-asm.fth's bytes equal GNU as on its comments (needs strace and
#       as; SKIP without)
#
# Long steps, opt in:
#   CHECK_CHAIN=1   chain/plumbing-root.sh: hex0-seed to the GCC 4.0.4 fixed
#                   point in a root whose only executable is hex0-seed
#                   (about 40 minutes; needs bwrap, strace and the archives
#                   of MANIFEST.sha256 in build-out/)
#   CHECK_K1=smoke  kernel/k1/run-chain.sh --direct-smoke under QEMU (a minute)
#   CHECK_K1=linux  kernel/k1/run-chain.sh --direct-linux: hex0 to Linux under
#                   K1 (about 80 minutes with KVM; 24 GiB guest RAM)
#
# Each step's output goes to $TMPDIR/check-all-NAME.log (default /tmp); the
# console shows one OK, SKIP or FAIL line per step and the verdict.
set -euo pipefail
cd "$(dirname "$0")"

LOGDIR=${TMPDIR:-/tmp}
PASS=0
SKIP=0
FAIL=0

run() {
    local name=$1; shift
    local log=$LOGDIR/check-all-$name.log
    printf '%-28s' "$name ..."
    if "$@" > "$log" 2>&1; then
        echo " OK"
        PASS=$((PASS + 1))
    else
        echo " FAIL (see $log)"
        FAIL=$((FAIL + 1))
        tail -20 "$log" | sed 's/^/    | /'
    fi
}

skip() {
    printf '%-28s' "$1 ..."
    echo " SKIP ($2)"
    SKIP=$((SKIP + 1))
}

have() { command -v "$1" >/dev/null 2>&1; }

run "01-seed" bash -c 'seed/build.sh && [ "$(wc -c < seed-forth)" -eq 1772 ]'
run "02-test" ./test.sh
if have python3; then
    run "03-pins" python3 tools/check-pins.py
else
    skip "03-pins" "missing: python3"
fi
if have gcc; then
    run "04-stage-a" tests/cc/stage-a-check.sh
else
    skip "04-stage-a" "missing: gcc"
fi
if have strace && have as && have python3; then
    run "05-k1-build" sh kernel/k1/tests/direct-build-check.sh
else
    skip "05-k1-build" "missing: strace, as or python3"
fi
if [ "${CHECK_CHAIN:-0}" = 1 ]; then
    run "06-chain" sh chain/plumbing-root.sh
fi
case ${CHECK_K1:-} in
    smoke) run "07-k1-smoke" kernel/k1/run-chain.sh --direct-smoke ;;
    linux) run "07-k1-linux" kernel/k1/run-chain.sh --direct-linux ;;
    '') ;;
    *) echo "check-all: CHECK_K1 is smoke or linux" >&2; exit 2 ;;
esac

echo
echo "check-all: $PASS OK, $SKIP SKIP, $FAIL FAIL"
[ "$FAIL" = 0 ]
