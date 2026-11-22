#!/usr/bin/env bash
# check-all.sh -- the repository's checks in one run.
#
# Quick steps (under a minute):
#   01  seed/build.sh: hex0-seed assembles seed/000-seed.hex0 into the
#       930-byte seed-forth
#   02  ./test.sh: the seed primitives, forth/010-lib.fth and the first
#       compiler layers
#   05  tests/cc/gates/run-gates.sh: the i386 seed compiles the gate
#       fixtures in native mode, each program exits as expected, and the
#       compiler rejects the die-* fixtures with the expected error code
#       and line; then
#       tests/cc/gates/check-coverage.sh puts every error code of the compiler in
#       one list (tested, unreachable from C, or to do) and prints "N of M
#       codes tested"
#   09  tests/seed/asm-check.py: seed/000-seed.hex0 equals GNU as on its
#       comments (with llvm-mc installed, LLVM's assembler must write the
#       same bytes too), its branch notes and addresses add up, and the
#       seed's ELF and dictionary fields equal what their comments state
#       (needs as; SKIP without)
#
# Long steps, opt in:
#   CHECK_I386=1    the i386 back end (cc/i386/) and what it builds
#                   (tinycc/README.md): its encoders against GNU as, no
#                   x86-64 encoder reached, the run-time corpus against
#                   gcc -m32, the junction with the i386 first tcc and
#                   tools under strace, and the gcc -m32 stand-in.  Then
#                   the i386 host (forth/i386/CONTRACT.md): its stand-ins
#                   against the x86-64 files and its bytes against GNU as,
#                   and the high-half vectors; the i386 kaem seed Forth
#                   builds from vendor/mescc-tools/Kaem, with its own
#                   tests on Linux and, on builder-hex0, the exit statuses
#                   of the programs it starts; and, with an i386 seed
#                   (./seed-forth-i386), the first tcc, the tools and kaem
#                   built by it, byte for byte the x86-64 seed's, under
#                   strace (about a minute; needs what CHECK_TINYCC needs,
#                   gcc -m32, as, objcopy, strace and python3, and for the
#                   two builder-hex0 boots QEMU, KVM and the archive of
#                   tinycc/builder-hex0.SOURCES; SKIP without)
#   CHECK_I386_BOOT=1  tests/tinycc/i386-one-boot-check.sh: builder-hex0
#                   boots a disk of sources with no program on it.  Its
#                   built-in hex0 assembles the i386 seed and
#                   kaem-optional-seed; the seed compiles kaem, the tools
#                   and the first tcc; the tools unpack the archives; and
#                   pass1.kaem runs to live-bootstrap's published tcc and
#                   libraries.  The 33 files the boot exports equal the
#                   pins and the host's seed (under half a minute with
#                   KVM; needs QEMU, KVM, python3, the vendor/stage0-posix
#                   submodule and the archives of tinycc/SOURCES and
#                   tinycc/builder-hex0.SOURCES; SKIP without them)
#   CHECK_I386_SEED=1  the i386 seed alone (seed/i386/SPEC.md 13.1):
#                   seed/i386/build.sh assembles seed/i386/000-seed.hex0
#                   into the 1191-byte seed-forth-i386; its comments equal
#                   GNU as and llvm-mc in 32-bit mode
#                   (tests/seed/i386/asm-check.py); tests/seed/i386/test.sh,
#                   every case also against the x86-64 seed where the text
#                   allows; the same cases under strace; and
#                   tests/seed/i386/boot-check.sh, where builder-hex0's hex0
#                   assembles the seed in a boot and the result equals the
#                   host's (seconds; needs the host kernel's i386 support,
#                   as and python3; strace for the strace run; QEMU, KVM and
#                   the archive of tinycc/builder-hex0.SOURCES for the boot;
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
run "05-cc-gates" tests/cc/gates/run-gates.sh
if have as && have python3; then
    run "09-hex0-asm" python3 tests/seed/asm-check.py
else
    skip "09-hex0-asm" "missing: as or python3"
fi
if [ "${CHECK_I386:-0}" = 1 ]; then
    if ! why=$(tests/tinycc/junction-check.sh --probe); then
        skip "15-i386" "$why"
    elif ! { have as && have objcopy && have strace && have python3; }; then
        skip "15-i386" "missing: as, objcopy, strace or python3"
    elif ! echo 'int main (void) { return 0; }' | gcc -m32 -x c - -o /dev/null 2> /dev/null; then
        skip "15-i386" "gcc -m32 does not build a program here"
    else
        run "15-i386-encoders" python3 tests/cc/i386/asm-check.py
        run "16-i386-corpus" tests/cc/i386/run-corpus.sh
        run "17-i386-junction" tests/tinycc/i386-syscall-check.sh
        run "18-i386-standin" tests/tinycc/i386-standin-check.sh
        run "20-i386-host" sh -c 'tests/forth/i386/standin-check.sh && python3 tests/forth/i386/asm-check.py && tests/forth/i386/high-halves-check.sh'
        run "21-i386-kaem" tests/tinycc/i386-kaem-check.sh
        if why=$(tests/tinycc/i386-kaem-boot-check.sh --probe); then
            run "22-i386-kaem-boot" tests/tinycc/i386-kaem-boot-check.sh
        else
            skip "22-i386-kaem-boot" "$why"
        fi
        # The i386 seed is built from its source here, so this step does
        # not depend on CHECK_I386_SEED having run first.
        [ -n "${SEED_I386:-}" ] || seed/i386/build.sh > /dev/null 2>&1 || true
        if why=$(tests/tinycc/i386-seed-check.sh --probe); then
            run "23-i386-seed" tests/tinycc/i386-seed-check.sh
        else
            skip "23-i386-seed" "$why"
        fi
    fi
fi
if [ "${CHECK_I386_BOOT:-0}" = 1 ]; then
    if why=$(tests/tinycc/i386-one-boot-check.sh --probe); then
        run "19-i386-one-boot" tests/tinycc/i386-one-boot-check.sh
    else
        skip "19-i386-one-boot" "$why"
    fi
fi
if [ "${CHECK_I386_SEED:-0}" = 1 ]; then
    if have as && have python3; then
        run "24-i386-seed" sh -c 'seed/i386/build.sh && [ "$(wc -c < seed-forth-i386)" -eq 1191 ] && python3 tests/seed/i386/asm-check.py'
    else
        skip "24-i386-seed" "missing: as or python3"
    fi
    run "25-i386-seed-test" tests/seed/i386/test.sh
    if have strace && have python3; then
        run "26-i386-seed-strace" tests/seed/i386/test.sh --strace
    else
        skip "26-i386-seed-strace" "missing: strace or python3"
    fi
    if why=$(tests/seed/i386/boot-check.sh --probe); then
        run "27-i386-seed-boot" tests/seed/i386/boot-check.sh
    else
        skip "27-i386-seed-boot" "$why"
    fi
fi

echo
echo "check-all: $PASS OK, $SKIP SKIP, $FAIL FAIL"
[ "$FAIL" = 0 ]
