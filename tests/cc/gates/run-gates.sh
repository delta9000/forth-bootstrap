#!/usr/bin/env bash
# run-gates.sh -- the Forth C compiler's gate fixtures, compiled and run.
#
# The compiler was built one feature at a time behind these gates
# (HISTORY.md, "Gates as the unit of work").  Each fixture goes to the
# compiler the way seed-forth's tests/cc/run-gate.sh fed it: on stdin, after
# forth/010-lib.fth and the layers from cc/compiler-layers.sh; cc-main reads
# the rest of stdin as C and writes an ELF to /tmp/cc-out.  The expected
# exit statuses are seed-forth's (tests/cc/run-gates.sh at 0dd2b88).
#
# The compiler's output path /tmp/cc-out is fixed (cc/120-cc-main.fth), so
# seed-forth runs with a private /tmp, bind-mounted from build-out/gates/tmp
# via `unshare -rm`, when the kernel allows it, and on the shared /tmp/cc-out
# otherwise.  The compiler runs from the repository root, where a quoted
# include is looked up as given and then under tests/cc/; that is why
# G14b.c includes "gates/g14_helper.h" (seed-forth's copy, which sat in
# tests/cc/, includes "g14_helper.h").
#
# Every gate runs; the script prints PASS or FAIL for each and exits 1 at
# the end if any failed.
set -euo pipefail
cd "$(dirname "$0")/../../.."

[ -x seed-forth ] || seed/build.sh >/dev/null

# "<fixture> <expected exit> [expected stdout]"
gates=(
  "G0.c 42"
  "G1.c 10"
  "G2.c 41"
  "G3.c 42"
  "G4.c 42"
  "G5.c 60"
  "G6a.c 50"
  "G6b.c 7"
  "G7.c 7"
  "G8.c 30"
  "G9a.c 42"
  "G9b.c 42"
  "G10a.c 204"
  "G10b.c 42"
  "G10c.c 96"
  "G11.c 141"
  "G12.c 47"
  "G13.c 114"
  "G14a.c 95"
  "G14b.c 42"
  "G14c.c 8"
  "G14d.c 221"
  "M1a.c 127"
  "M1b.c 51"
)
# M1.c is kept but not run.  It is an early copy of M2-Planet's cc.c main()
# and calls functions defined in the rest of M2-Planet, so alone it stops at
# error 206 (undefined function).  It also targets an older M2-Planet than
# vendor/M2-Planet (it declares `struct token_list* program()`; the pinned
# cc_core.c defines `void program(void)`).  seed-forth's registry excluded
# it too; M2-Planet's own cc.c is compiled by tests/cc/stage-a-check.sh.
not_run=(
  "M1.c|not standalone; M2-Planet's cc.c is covered by tests/cc/stage-a-check.sh"
)

D=tests/cc/gates
WORK=build-out/gates
rm -rf "$WORK"
mkdir -p "$WORK/tmp"
WORK=$(cd "$WORK" && pwd)
if unshare -rm sh -c 'mount --bind "$1" /tmp' _ "$WORK/tmp" 2>/dev/null; then
    OUT=$WORK/tmp/cc-out
    private=1
else
    OUT=/tmp/cc-out
    private=0
    echo "run-gates: unshare -rm refused; using the shared /tmp/cc-out"
fi

# compile SRC: run the compiler on SRC; sets crc, leaves stderr in $WORK/err.
compile() {
    rm -f "$OUT"
    crc=0
    if [ "$private" = 1 ]; then
        cat forth/010-lib.fth $(cc/compiler-layers.sh) "$1" \
            | unshare -rm sh -c 'mount --bind "$1" /tmp && exec /proc/self/fd/3 3<&3' \
                _ "$WORK/tmp" 3< ./seed-forth > /dev/null 2> "$WORK/err" || crc=$?
    else
        cat forth/010-lib.fth $(cc/compiler-layers.sh) "$1" \
            | ./seed-forth > /dev/null 2> "$WORK/err" || crc=$?
    fi
}

PASSED=0
FAILED=0
pass() { echo "PASS: $*"; PASSED=$((PASSED + 1)); }
fail() { echo "FAIL: $*"; FAILED=$((FAILED + 1)); }

for g in "${gates[@]}"; do
    read -r file want want_out <<< "$g"
    compile "$D/$file"
    if [ "$crc" != 0 ] || [ ! -f "$OUT" ]; then
        fail "$file: compiler exit $crc ($(tail -n 1 "$WORK/err"))"
        continue
    fi
    chmod +x "$OUT"
    rc=0
    "$OUT" > "$WORK/stdout" 2> /dev/null || rc=$?
    got_out=$(cat "$WORK/stdout")
    if [ "$rc" != "$want" ]; then
        fail "$file: expected exit $want, got $rc"
    elif [ -n "${want_out:-}" ] && [ "$got_out" != "$want_out" ]; then
        fail "$file: expected stdout '$want_out', got '$got_out'"
    else
        pass "$file -> $rc"
    fi
done

for n in "${not_run[@]}"; do
    IFS='|' read -r file why <<< "$n"
    echo "NOT RUN: $file ($why)"
done

[ "$private" = 1 ] || rm -f "$OUT"
echo
echo "run-gates: $PASSED passed, $FAILED failed, ${#not_run[@]} not run"
[ "$FAILED" = 0 ]
