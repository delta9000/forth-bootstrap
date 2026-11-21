#!/usr/bin/env bash
# check-all.sh -- the repository's checks in one run.
#
# Quick steps (under a minute):
#   01  seed/build.sh: hex0-seed assembles seed/000-seed.hex0 into the
#       930-byte seed-forth
#   02  ./test.sh: the seed primitives, forth/010-lib.fth and the first
#       compiler layers
#   03  tests/asm/hi-check.sh: forth/130-asm.fth assembles and links a small
#       M1 program; it prints "hi", exits 42 and is 160 bytes
#   04  tests/cc/seed-cc-rebuild-check.sh: seed Forth builds seed-cc and
#       seed-ar; that seed-cc rebuilds both, byte for byte the same
#   05  tests/cc/gates/run-gates.sh: the Forth compiler compiles the gate
#       fixtures G0.c to M1b.c, each program exits as expected, and it
#       rejects the die-* fixtures with the expected error code; then
#       tests/cc/gates/check-coverage.sh puts every error code in cc/ in
#       one list (tested, unreachable from C, or to do) and prints "N of M
#       codes tested"
#   06  tools/check-pins.py: every archive pin agrees with MANIFEST.sha256
#   07  Stage A (tests/cc/stage-a-check.sh): the Forth compiler's M1 for
#       M2-Planet equals a GCC-built M2-Planet's (needs gcc; SKIP without)
#   08  kernel/k1/tests/direct-build-check.sh: seed Forth builds K1 with no
#       other program running, its objects equal seed-cc's, and
#       k1-asm.fth's bytes equal GNU as on its comments (needs strace and
#       as; SKIP without)
#   09  tests/seed/asm-check.py and kernel/k0/check.sh: the two hex0
#       sources, seed/000-seed.hex0 and kernel/k0/k0.hex0, equal GNU as on
#       their comments (with llvm-mc installed, LLVM's assembler must write
#       the same bytes too), their branch notes and addresses add up, the
#       seed's ELF and dictionary fields equal what their comments state,
#       and K0's build has its pinned sha256 (needs as; SKIP without)
#   10  tests/pins/check-outputs.sh: seed-cc, seed-ar, Stage A's cc-out-v1,
#       the K1 recipe runner and K1 equal tests/pins/outputs.sha256 (files a
#       skipped step did not build are reported, not compared)
#
# Long steps, opt in:
#   CHECK_CHAIN=1   chain/plumbing-root.sh: hex0-seed to the GCC 4.0.4 fixed
#                   point in a root whose only executable is hex0-seed
#                   (18 minutes on 24 threads; needs bwrap, strace and the
#                   archives of MANIFEST.sha256 in build-out/)
#   CHECK_K1=smoke  kernel/k1/run-chain.sh --direct-smoke under QEMU (under a minute)
#   CHECK_K1=linux  kernel/k1/run-chain.sh --direct-linux: hex0 to Linux under
#                   K1 (1 h 38 min with KVM; 24 GiB guest RAM)
#   CHECK_TINYCC=1  tests/tinycc/junction-check.sh: seed Forth builds the
#                   first tcc, and live-bootstrap's tcc-0.9.26 pass1.kaem
#                   from it reaches their published tcc and libraries
#                   (seconds; needs bwrap, the host kernel's i386 support,
#                   the vendor/stage0-posix submodule and the archives of
#                   tinycc/SOURCES; SKIP without the first two)
#   CHECK_I386=1    the i386 back end (cc/i386/) and what it builds
#                   (tinycc/README.md): its encoders against GNU as, no
#                   x86-64 encoder reached, the run-time corpus against
#                   gcc -m32, the junction with the i386 first tcc and
#                   tools under strace, and the gcc -m32 stand-in (under a
#                   minute; needs what CHECK_TINYCC needs, gcc -m32, as,
#                   objcopy, strace and python3; SKIP without)
#   CHECK_I386_BOOT=1  tests/tinycc/i386-one-boot-check.sh: builder-hex0
#                   boots a disk with the i386 first tcc, the i386 tools,
#                   a kaem and the archives, and in that one boot unpacks
#                   the sources and runs pass1.kaem to live-bootstrap's
#                   published tcc and libraries (under half a minute with KVM;
#                   needs what CHECK_TINYCC needs, QEMU, KVM, python3 and
#                   the archive of tinycc/hex0-handoff.SOURCES; SKIP
#                   without them)
#   CHECK_HEX0_HANDOFF=1  tests/tinycc/hex0-handoff-check.sh: K0 runs seed
#                   Forth, which builds the first tcc; the first tcc makes
#                   tcc-boot0 and mes libc and writes live-bootstrap's
#                   builder-hex0 disk through K0; builder-hex0 boots it and
#                   runs pass1.kaem from tcc-boot0 to their published tcc and
#                   libraries (under a minute with KVM; needs QEMU, KVM,
#                   bwrap, the vendor/stage0-posix submodule and the
#                   archives of tinycc/SOURCES and tinycc/hex0-handoff.SOURCES;
#                   SKIP without them)
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

run "01-seed" bash -c 'seed/build.sh && [ "$(wc -c < seed-forth)" -eq 930 ]'
run "02-test" ./test.sh
run "03-asm" tests/asm/hi-check.sh
run "04-seed-cc" tests/cc/seed-cc-rebuild-check.sh
run "05-cc-gates" tests/cc/gates/run-gates.sh
if have python3; then
    run "06-pins" python3 tools/check-pins.py
else
    skip "06-pins" "missing: python3"
fi
if have gcc; then
    run "07-stage-a" tests/cc/stage-a-check.sh
else
    skip "07-stage-a" "missing: gcc"
fi
if have strace && have as && have python3; then
    run "08-k1-build" sh kernel/k1/tests/direct-build-check.sh
else
    skip "08-k1-build" "missing: strace, as or python3"
fi
if have as && have python3; then
    run "09-hex0-asm" sh -c 'python3 tests/seed/asm-check.py && sh kernel/k0/check.sh'
else
    skip "09-hex0-asm" "missing: as or python3"
fi
run "10-outputs" sh tests/pins/check-outputs.sh
if [ "${CHECK_CHAIN:-0}" = 1 ]; then
    run "11-chain" sh chain/plumbing-root.sh
fi
if [ "${CHECK_TINYCC:-0}" = 1 ]; then
    if why=$(tests/tinycc/junction-check.sh --probe); then
        run "13-tinycc-junction" tests/tinycc/junction-check.sh
    else
        skip "13-tinycc-junction" "$why"
    fi
fi
if [ "${CHECK_I386:-0}" = 1 ]; then
    if ! why=$(tests/tinycc/junction-check.sh --probe); then
        skip "15-i386" "$why"
    elif ! { have as && have objcopy && have strace && have python3; }; then
        skip "15-i386" "missing: as, objcopy, strace or python3"
    elif ! echo 'int main (void) { return 0; }' | gcc -m32 -x c - -o /dev/null 2> /dev/null; then
        skip "15-i386" "gcc -m32 does not build a program here"
    else
        run "15-i386-encoders" sh -c 'python3 tests/cc/i386/asm-check.py && tests/cc/i386/x86-64-bytes-check.sh'
        run "16-i386-corpus" tests/cc/i386/run-corpus.sh
        run "17-i386-junction" tests/tinycc/i386-syscall-check.sh
        run "18-i386-standin" tests/tinycc/i386-standin-check.sh
    fi
fi
if [ "${CHECK_I386_BOOT:-0}" = 1 ]; then
    if why=$(tests/tinycc/i386-one-boot-check.sh --probe); then
        run "19-i386-one-boot" tests/tinycc/i386-one-boot-check.sh
    else
        skip "19-i386-one-boot" "$why"
    fi
fi
if [ "${CHECK_HEX0_HANDOFF:-0}" = 1 ]; then
    if why=$(tests/tinycc/hex0-handoff-check.sh --probe); then
        run "14-hex0-handoff" tests/tinycc/hex0-handoff-check.sh
    else
        skip "14-hex0-handoff" "$why"
    fi
fi
case ${CHECK_K1:-} in
    smoke) run "12-k1-smoke" kernel/k1/run-chain.sh --direct-smoke ;;
    linux) run "12-k1-linux" kernel/k1/run-chain.sh --direct-linux ;;
    '') ;;
    *) echo "check-all: CHECK_K1 is smoke or linux" >&2; exit 2 ;;
esac

echo
echo "check-all: $PASS OK, $SKIP SKIP, $FAIL FAIL"
[ "$FAIL" = 0 ]
