#!/usr/bin/env bash
# test.sh -- the seed primitives, forth/010-lib.fth and the first compiler
# layers.  Every check runs; a failing one prints FAIL with its exit status
# and output, and the script exits 1 at the end with the count.
set -euo pipefail
cd "$(dirname "$0")"

./seed/build.sh

PASSED=0
FAILED=0
pass() { echo "  PASS: $*"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $*"; FAILED=$((FAILED + 1)); }

# Each check captures the exit status as `ec=0; out=$(...) || ec=$?`, so a
# failing seed-forth reaches its FAIL line instead of ending the script
# under `set -e`.
#
# Forth source goes to seed-forth as-is: the seed's token reader skips
# `\ ...` line comments and `( ... )` comments itself.

# ----- Seed primitives -----

# The REPL exits 0 on EOF with no input.
ec=0; ./seed-forth </dev/null || ec=$?
[ "$ec" = 0 ] && pass "repl: EOF exits 0" || fail "repl: EOF exit $ec"

# The REPL executes `bye` from its input.
ec=0; echo "bye" | ./seed-forth || ec=$?
[ "$ec" = 0 ] && pass "repl: bye" || fail "repl: bye exit $ec"

# An unknown word is echoed back followed by "?\n", and the REPL reads on.
ec=0; out=$(printf 'wibble\n[lit] 65 emit\n' | ./seed-forth) || ec=$?
[ "$ec" = 0 ] && [ "$out" = $'wibble?\nA' ] && pass "repl: unknown -> wibble?, then continues" || fail "unknown word: exit $ec, got '$out'"

# The reader skips \ line comments and ( ... ) comments itself.
ec=0; out=$(printf '\\ emit this line is a comment\n[lit] 65 ( emit [lit] 66 ) emit\n( a comment\nover two lines ) [lit] 67 emit \\ trailing\n[lit] 68 emit \\' | ./seed-forth) || ec=$?
[ "$ec" = 0 ] && [ "$out" = "ACD" ] && pass "reader: \\ and ( ) comments skipped" || fail "comments: exit $ec, got '$out'"

# A 255-byte name is accepted; a 256-byte token is fatal (exit 2).
n255=$(printf 'a%.0s' $(seq 255))
ec=0; out=$(printf ': %s [lit] 65 emit ; %s\n' "$n255" "$n255" | ./seed-forth) || ec=$?
[ "$ec" = 0 ] && [ "$out" = "A" ] && pass "reader: 255-byte token accepted" || fail "255-byte token: exit $ec, got '$out'"
ec=0; out=$(printf '%sa [lit] 65 emit\n' "$n255" | ./seed-forth) || ec=$?
[ "$ec" = 2 ] && [ "$out" = "${n255}a?" ] && pass "reader: 256-byte token -> prints it + ?, exit 2" || fail "256-byte token: exit $ec, got '${out:250}'"

# A colon definition that calls `bye` exits cleanly when invoked.
ec=0; out=$(printf ': greet bye ;\ngreet\nemit\n' | timeout 3 ./seed-forth) || ec=$?
[ "$ec" = 0 ] && [ -z "$out" ] && pass "colon: define+invoke" || fail "colon: exit $ec, got '$out'"

# [lit] in interpret mode pushes a decimal value.
ec=0; out=$(echo "[lit] 65 emit" | timeout 3 ./seed-forth) || ec=$?
[ "$ec" = 0 ] && [ "$out" = "A" ] && pass "[lit] interpret -> A" || fail "[lit] interpret: exit $ec, got '$out'"

# [lit] in compile mode compiles 'lit + cell' into a colon definition.
ec=0; out=$(printf ': greet [lit] 72 emit [lit] 105 emit ;\ngreet\n' | timeout 3 ./seed-forth) || ec=$?
[ "$ec" = 0 ] && [ "$out" = "Hi" ] && pass "[lit] compile -> Hi" || fail "[lit] compile: exit $ec, got '$out'"

# A [lit] token that is not unsigned decimal is fatal: the seed prints it
# followed by "?" and exits 2 instead of compiling a silent 0.
ec=0; out=$(echo "[lit] -5 [lit] 65 emit" | ./seed-forth) || ec=$?
[ "$ec" = 2 ] && [ "$out" = "-5?" ] && pass "[lit] -5 -> '-5?', exit 2" || fail "[lit] -5: exit $ec, got '$out'"
ec=0; out=$(printf ': t [lit] 0x41 emit ;\nt\n' | ./seed-forth) || ec=$?
[ "$ec" = 2 ] && [ "$out" = "0x41?" ] && pass "[lit] 0x41 in a definition -> exit 2" || fail "[lit] 0x41: exit $ec, got '$out'"
ec=0; out=$(printf '[lit]' | ./seed-forth) || ec=$?
[ "$ec" = 2 ] && [ "$out" = "?" ] && pass "[lit] at EOF -> '?', exit 2" || fail "[lit] at EOF: exit $ec, got '$out'"

# [lit] handles large values (4337704 = 0x423028); emit prints the low byte.
ec=0; out=$(echo "[lit] 4337704 emit" | timeout 3 ./seed-forth) || ec=$?
[ "$ec" = 0 ] && [ "$out" = "(" ] && pass "[lit] large value (low byte of 0x423028 is 0x28)" || fail "[lit] large: exit $ec, got '$out'"

# The divide primitive.
ec=0; out=$(echo "[lit] 4096 [lit] 16 / [lit] 48 + emit" | timeout 3 ./seed-forth) || ec=$?
[ "$ec" = 0 ] && [ "$out" = "0" ] && pass "div: 4096/16=256, low byte+'0' = '0'" || fail "div 4096/16: exit $ec, got '$out'"
ec=0; out=$(echo "[lit] 17 [lit] 5 / [lit] 48 + emit" | timeout 3 ./seed-forth) || ec=$?
[ "$ec" = 0 ] && [ "$out" = "3" ] && pass "div: 17/5=3" || fail "div 17/5: exit $ec, got '$out'"

# syscall6 writes a byte to stdout through the raw Linux write syscall.
ec=0; out=$(printf ': t [lit] 65 [lit] 4268032 c! [lit] 1 [lit] 4268032 [lit] 1 [lit] 0 [lit] 0 [lit] 0 [lit] 1 syscall6 drop bye ;\nt\n' | timeout 3 ./seed-forth) || ec=$?
[ "$ec" = 0 ] && [ "$out" = "A" ] && pass "syscall6: write 'A'" || fail "syscall6: exit $ec, got '$out'"

# ----- forth/010-lib.fth -----

# digit?/alpha?/space? return -1/0.
ec=0; out=$(cat forth/010-lib.fth <(printf '[lit] 53 digit? [lit] 90 + [lit] 89 + emit\n[lit] 65 digit? [lit] 90 + [lit] 89 + emit\n[lit] 65 alpha? [lit] 90 + [lit] 89 + emit\n[lit] 32 space? [lit] 90 + [lit] 89 + emit\nbye\n') | timeout 5 ./seed-forth | od -An -tx1 | tr -d ' \n') || ec=$?
[ "$ec" = 0 ] && [ "$out" = "b2b3b2b2" ] && pass "lib: digit?/alpha?/space? classifiers" || fail "classify: exit $ec, got '$out'"

# open+write+close round-trip, into a fresh temporary directory.
fwio=$(mktemp -d)
trap 'rm -rf "$fwio"' EXIT
cat > "$fwio/test-fileio.fth" <<TFEOF
create path  s, $fwio/forth-fwio-test  [lit] 0 c,

: payload  ( -- bufaddr )
  here
  [lit] 79 c, [lit] 75 c, [lit] 10 c, ;        \ "OK\n"

: go
  path payload swap                            ( bufaddr pathaddr )
  [lit] 577 [lit] 420 open                     ( bufaddr fd )
  swap [lit] 3 write drop                      ( fd )
  close drop  bye ;
go
TFEOF
ec=0; cat forth/010-lib.fth "$fwio/test-fileio.fth" | timeout 5 ./seed-forth || ec=$?
out=$(cat "$fwio/forth-fwio-test" 2>/dev/null || true)
[ "$ec" = 0 ] && [ "$out" = "OK" ] && pass "lib: open/write/close round-trip writes correct bytes" || fail "fileio: exit $ec, got '$out'"

# forth/test-010-lib.fth: comparison, stack, arithmetic, control flow and
# defining words.
ec=0; out=$(cat forth/010-lib.fth forth/test-010-lib.fth | timeout 5 ./seed-forth) || ec=$?
[ "$ec" = 0 ] && pass "forth/010-lib.fth: all comparisons/arith/control/defining words" || fail "forth/010-lib.fth: exit $ec, got '${out: -200}'"

# ----- cc-*.fth layer -----

# Each layer test loads the library and the layers up to the one under
# test, then its cc/test-*.fth, which exits nonzero on the first failure.
layer_test() {
    local name=$1 desc=$2; shift 2
    local ec=0 out
    out=$(cat forth/010-lib.fth "$@" | timeout 5 ./seed-forth) || ec=$?
    [ "$ec" = 0 ] && pass "$name: $desc" || fail "$name: exit $ec, got '${out: -200}'"
}

layer_test cc-arena "alloc/align/bytes-eq" \
    cc/020-cc-arena.fth cc/test-020-cc-arena.fth
layer_test cc-io "peek/next/eof, emit/patch" \
    cc/020-cc-arena.fth cc/030-cc-io.fth cc/test-030-cc-io.fth
layer_test cc-lex "tokens (kw/id/punct/num/str/chr/comment/escape)" \
    cc/020-cc-arena.fth cc/030-cc-io.fth cc/040-cc-prep.fth cc/050-cc-lex.fth \
    cc/test-050-cc-lex.fth
layer_test cc-types "make/base/ptr/size" \
    cc/020-cc-arena.fth cc/030-cc-io.fth cc/040-cc-prep.fth cc/050-cc-lex.fth \
    cc/060-cc-types.fth cc/test-060-cc-types.fth
layer_test cc-sym "add/find/kind/val/scope" \
    cc/020-cc-arena.fth cc/030-cc-io.fth cc/040-cc-prep.fth cc/050-cc-lex.fth \
    cc/060-cc-types.fth cc/070-cc-sym.fth cc/test-070-cc-sym.fth

echo
echo "test.sh: $PASSED passed, $FAILED failed"
[ "$FAILED" = 0 ]
