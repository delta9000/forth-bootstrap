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

# ----- forth/010-lib.fth: the outer interpreter -----

# The library ends by handing over to interpret, so everything after it is
# read by interpret.  interp_case NAME EXIT STDOUT INPUT runs each case twice:
# after the library alone, and after cc/020-cc-arena.fth too, whose native!
# replaces key and find and whose [lit] lays an inline push.
interp_case() {
    local name=$1 want_ec=$2 want=$3 input=$4 ec out pre
    for pre in "" cc/020-cc-arena.fth; do
        ec=0; out=$(cat forth/010-lib.fth $pre <(printf '%s' "$input") | timeout 5 ./seed-forth) || ec=$?
        [ "$ec" = "$want_ec" ] && [ "$out" = "$want" ] && pass "interpret${pre:+ after 020}: $name" ||
            fail "interpret${pre:+ after 020}: $name: exit $ec (want $want_ec), got '$out' want '$want'"
    done
}
# Numbers: decimal, -decimal and $hex only.
interp_case "decimal" 0 "A" $'65 emit\n'
interp_case "\$hex, either case" 0 "JJ" $'$4a emit $4A emit\n'
interp_case "negative decimal" 0 "Y" $'-2 91 + emit\n'
interp_case "-1 is all ones" 0 "U" $'-1 18446744073709551615 = 0= 0= 86 + emit\n'
interp_case "unsigned wrap, as [lit]" 0 "A" $'18446744073709551681 emit\n'
interp_case "compiled numbers" 0 "AJC" $': t 65 emit $4a emit -3 70 + emit ; t\n'
interp_case "[lit] still works" 0 "AB" $'[lit] 65 emit : t [lit] 66 emit ; t\n'
interp_case "1+ 0= - are words" 0 "B" $'64 1+ 1+ emit 0 0= drop 5 3 - drop\n'
# An unknown token is fatal: the token and "?" on stdout, exit 2, nothing after it runs.
interp_case "unknown word: exit 2" 2 "zork?" $'zork 65 emit\n'
interp_case "unknown word while compiling: exit 2" 2 "zork?" $': t zork 65 emit ; t\n'
for tok in 0x41 0X41 "'A'" '-$10' '$-10' '$' '--1' '1x' '$4g' '-'"'"; do
    interp_case "not a number: $tok" 2 "B$tok?" "66 emit $tok 65 emit"$'\n'
done
# The defining and control words, run and compiled through interpret.
interp_case "user immediate" 0 "IR" $': i 73 emit ; immediate : u i 82 emit ; u\n'
interp_case "control flow" 0 "0123" $': d 0 begin, dup 4 < while, dup 48 + emit 1+ repeat, drop ; d\n'
interp_case "constant/variable" 0 "ZZ" $'90 constant z z emit variable v 90 v ! v @ emit\n'
interp_case "defer/is" 0 "D" $'defer w : x 68 emit ; '"' x is w w"$'\n'
interp_case "[char] / char" 0 "PQ" $': t [char] P emit ; t char Q emit\n'
interp_case ">r r> across tokens" 0 "BA" $'65 >r 66 emit r> emit\n'
# Comments, in both states.
interp_case "line comment" 0 "A" $'\\ 66 emit\n65 emit\n'
interp_case "paren comment" 0 "AC" $'65 ( 66 emit ) emit ( two\nlines ) 67 emit\n'
interp_case "comments compiled" 0 "AB" $': t 65 ( 0 0 ) emit \\ 0 0\n 66 emit ; t\n'
# End of input exits 0 wherever it falls, also right after a word that reads
# a name (`:` then lays a header with an empty name, which find would hit).
interp_case "EOF without newline" 0 "A" $'65 emit'
interp_case "EOF in \\ comment" 0 "A" $'65 emit \\ no newline'
interp_case "EOF in ( comment" 0 "A" $'65 emit ( never closed'
interp_case "EOF in definition" 0 "" $': t 65 emit'
interp_case "EOF after :" 0 "A" $'65 emit :'
interp_case "EOF after constant" 0 "A" $'65 emit 5 constant'
interp_case "EOF after '" 0 "A" $'65 emit \''
interp_case "bye" 0 "A" $'65 emit bye 66 emit\n'
# The seed's reader limits still apply.
interp_case "255-byte name" 0 "A" ": $n255 65 emit ; $n255"$'\n'
interp_case "256-byte token: exit 2" 2 "${n255}a?" "${n255}a 65 emit"$'\n'
interp_case "[lit] -5: exit 2" 2 "-5?" $'[lit] -5 65 emit\n'
# A bare number compiles to the same bytes as [lit] N: after 020 both lay
# the inline push, so two definitions of t differ only in their link cell.
ec=0; out=$(cat forth/010-lib.fth cc/020-cc-arena.fth <(printf '%s\n' \
    'here : t 4660 $ffff -7 ; here over - >r 8 + 1 swap r> 8 - write drop' \
    'here : t [lit] 4660 [lit] 65535 [lit] 18446744073709551609 ; here over - >r 8 + 1 swap r> 8 - write drop') |
    timeout 5 ./seed-forth | od -An -tx1 -v | tr -d ' \n') || ec=$?
[ "$ec" = 0 ] && [ ${#out} = 232 ] && [ "${out:0:116}" = "${out:116}" ] &&
    pass "interpret after 020: bare numbers lay [lit]'s bytes" || fail "bare vs [lit] bytes: exit $ec, got '$out'"

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
