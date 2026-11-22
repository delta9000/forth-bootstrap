#!/usr/bin/env bash
# check-all.sh -- the repository's checks in one run (about two minutes).
#
# The route: builder-hex0's built-in hex0 assembles seed/i386/000-seed.hex0
# and kaem-optional-seed; the seed compiles kaem, the tools and the first
# tcc; live-bootstrap's pass1.kaem reaches its published tcc from there.
#
# The seed (seed/i386/SPEC.md 13.1)
#   01  seed/i386/build.sh: hex0-seed assembles seed/i386/000-seed.hex0
#       into the 1191-byte seed-forth-i386; tests/seed/i386/asm-check.py:
#       its comments equal GNU as, and llvm-mc where installed (needs as)
#   02  tests/seed/i386/test.sh: the seed's own cases
#   03  the same cases under strace, each run's system calls checked
#       (needs strace)
# The Forth library and the compiler
#   04  ./test.sh: forth/test-010-lib.fth and the cc/test-NNN-*.fth files
#   05  the host's machine code: tests/forth/i386/asm-check.py (the bytes of
#       forth/i386/*.fth equal GNU as on their comments; needs as) and
#       tests/forth/i386/high-halves-check.sh (its primitives on cells
#       whose two halves both matter)
#   06  tests/cc/i386/asm-check.py: the bytes of the compiler's encoders
#       equal GNU as on their comments (needs as and objcopy)
#   07  tests/cc/gates/run-gates.sh: the gate fixtures compile and exit as
#       expected, the die-* fixtures are refused with the expected error
#       code and line, and tests/cc/gates/check-coverage.sh puts every
#       error code of the compiler in one list (tested, unreachable from
#       C, or to do) and prints "N of M codes tested"
#   08  tests/cc/i386/run-corpus.sh: the run-time corpus prints and exits
#       as the same programs built by gcc -m32 do (needs gcc -m32)
# What the seed builds, on the host
#   09  tests/tinycc/i386-seed-check.sh: tinycc/build-tools-i386.sh and
#       build-first-tcc-i386.sh build kaem, the tools and the first tcc
#       with the bytes of tests/pins/tinycc.sha256, every seed run under
#       strace with builder-hex0's system calls only (needs strace)
#   10  tests/tinycc/i386-syscall-check.sh: the junction.  From the first
#       tcc, live-bootstrap's tcc-0.9.26 pass1.kaem reaches their
#       published tcc and libraries (tests/tinycc/junction-check.sh), and
#       under strace the first tcc and the tools keep to what builder-hex0
#       can do (needs bwrap and strace)
#   11  tests/tinycc/i386-standin-check.sh: a gcc -m32 build of the first
#       tcc leaves the same bytes in every file of the junction's first
#       stage (needs bwrap and gcc -m32)
#   12  tests/tinycc/i386-kaem-check.sh: the seed-built kaem passes
#       mescc-tools' own kaem tests and stops on a failing command (needs
#       strace)
# On builder-hex0, under QEMU with KVM
#   13  tests/tinycc/i386-kaem-boot-check.sh: that kaem starts programs
#       and reads their exit statuses on builder-hex0
#   14  tests/seed/i386/boot-check.sh: builder-hex0's hex0 assembles the
#       seed in a boot, and the result equals the host's
#   15  tests/tinycc/i386-one-boot-check.sh: the route itself.  A disk of
#       sources with no program on it boots to live-bootstrap's published
#       tcc; the 33 files the boot exports equal the pins, live-bootstrap's
#       checksums and the host's seed
#
# Every step needs the host kernel's i386 (IA32) support, the
# vendor/stage0-posix and vendor/mescc-tools submodules and python3; steps
# 09 to 15 need the four archives of tinycc/SOURCES and
# tinycc/builder-hex0.SOURCES (python3 tools/fetch-archives.py).  A step
# whose other needs are missing is reported as SKIP with the reason.
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
    printf '%-24s' "$name ..."
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
    printf '%-24s' "$1 ..."
    echo " SKIP ($2)"
    SKIP=$((SKIP + 1))
}

# need NAME TOOL...: true when every TOOL is there; otherwise SKIP NAME.
need() {
    local name=$1 t; shift
    for t in "$@"; do
        if [ "$t" = gcc-m32 ]; then
            echo 'int main (void) { return 0; }' | gcc -m32 -x c - -o /dev/null 2> /dev/null \
                || { skip "$name" "gcc -m32 does not build a program here"; return 1; }
        else
            command -v "$t" > /dev/null 2>&1 || { skip "$name" "missing: $t"; return 1; }
        fi
    done
}

# probed NAME SCRIPT: run SCRIPT when its own --probe says it can run.
probed() {
    local why
    if why=$("$2" --probe); then run "$1" "$2"; else skip "$1" "$why"; fi
}

need 01-seed as python3 && run "01-seed" sh -c \
    'seed/i386/build.sh && [ "$(wc -c < seed-forth-i386)" -eq 1191 ] && python3 tests/seed/i386/asm-check.py'
run "02-seed-tests" tests/seed/i386/test.sh
need 03-seed-strace strace python3 && run "03-seed-strace" tests/seed/i386/test.sh --strace
run "04-library-layers" ./test.sh
need 05-host-code as python3 && run "05-host-code" sh -c \
    'python3 tests/forth/i386/asm-check.py && tests/forth/i386/high-halves-check.sh'
need 06-encoders as objcopy python3 && run "06-encoders" python3 tests/cc/i386/asm-check.py
run "07-gates" tests/cc/gates/run-gates.sh
need 08-corpus gcc-m32 && run "08-corpus" tests/cc/i386/run-corpus.sh
probed "09-seed-builds" tests/tinycc/i386-seed-check.sh
if why=$(tests/tinycc/junction-check.sh --probe); then
    need 10-junction strace python3 && run "10-junction" tests/tinycc/i386-syscall-check.sh
    need 11-standin gcc-m32 && run "11-standin" tests/tinycc/i386-standin-check.sh
else
    skip "10-junction" "$why"
    skip "11-standin" "$why"
fi
need 12-kaem strace && run "12-kaem" tests/tinycc/i386-kaem-check.sh
probed "13-kaem-boot" tests/tinycc/i386-kaem-boot-check.sh
probed "14-seed-boot" tests/seed/i386/boot-check.sh
probed "15-one-boot" tests/tinycc/i386-one-boot-check.sh

echo
echo "check-all: $PASS OK, $SKIP SKIP, $FAIL FAIL"
[ "$FAIL" = 0 ]
