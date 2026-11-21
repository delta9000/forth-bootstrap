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
# Every gate runs; the script prints PASS or FAIL for each, then runs
# check-coverage.sh (error codes against the die gates), and exits 1 at the
# end if any gate or the coverage check failed.
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
# Die gates: programs the compiler must reject.  "<fixture>|<expected
# compiler exit>|<expected last stderr line>"; the line is cc-die's
# "cc: line N: error C" (cc/020-cc-arena.fth), and no /tmp/cc-out may be
# written.  One per code: seed-forth's die gates at 0dd2b88 (10 to 82,
# 113, 124 to 129, 162, 171, 206, 207) and short programs for the parser's
# codes from 90 to 205.  A .c fixture is fed as it is.  A .sh fixture is a
# generator for an input too large or too repetitive to check in: run with
# sh, it prints the C source on stdout and may write helper files (a header
# to #include) into $CC_DIE_TMP, which is build-out/gates/die-tmp, not
# /tmp, because the compiler may run with a private /tmp.  die-31-include-deep.c includes
# itself as "gates/die-31-include-deep.c" for the reason G14b.c does.
# tests/cc/gates/check-coverage.sh, run at the end, reads this list and
# counts which of the compiler's error codes it tests.
die_gates=(
  "die-10-arena-full.sh|10|cc: line 88: error 10"
  "die-20-input-too-big.sh|20|cc: line 1: error 20"
  "die-21-output-full.sh|21|cc: line 38819: error 21"
  "die-30-include-missing.c|30|cc: line 2: error 30"
  "die-31-include-deep.c|31|cc: line 11: error 31"
  "die-32-include-too-big.sh|32|cc: line 1: error 32"
  "die-33-include-path-long.sh|33|cc: line 1: error 33"
  "die-34-macro-table-full.sh|34|cc: line 1014: error 34"
  "die-35-macro-pool-full.sh|35|cc: line 328: error 35"
  "die-36-source-too-big.sh|36|cc: line 69: error 36"
  "die-37-macro-scratch-full.sh|37|cc: line 2: error 37"
  "die-38-if-too-deep.sh|38|cc: line 65: error 38"
  "die-39-if-unterminated.c|39|cc: line 7: error 39"
  "die-40-error-directive.c|40|cc: line 5: error 40"
  "die-41-else-without-if.c|41|cc: line 5: error 41"
  "die-42-ifdef-no-name.c|42|cc: line 2: error 42"
  "die-43-macro-scratch-deep.sh|43|cc: line 2: error 43"
  "die-44-macro-call-open.c|44|cc: line 6: error 44"
  "die-45-macro-args.c|45|cc: line 5: error 45"
  "die-46-macro-args-max.c|46|cc: line 4: error 46"
  "die-47-define-params.c|47|cc: line 3: error 47"
  "die-48-define-params-max.c|48|cc: line 2: error 48"
  "die-50-struct-fields.c|50|cc: line 19: error 50"
  "die-60-symbols-full.sh|60|cc: line 8162: error 60"
  "die-61-scopes-deep.c|61|cc: line 66: error 61"
  "die-80-globals-full.sh|80|cc: line 515: error 80"
  "die-81-global-refs-full.sh|81|cc: line 16387: error 81"
  "die-82-bss-full.c|82|cc: line 3: error 82"
  "die-90-field-unknown.c|90|cc: line 3: error 90"
  "die-91-subscript-not-variable.c|91|cc: line 3: error 91"
  "die-92-subscript-no-bracket.c|92|cc: line 2: error 92"
  "die-93-ident-undeclared.c|93|cc: line 2: error 93"
  "die-94-call-not-function.c|94|cc: line 2: error 94"
  "die-95-typedef-as-value.c|95|cc: line 3: error 95"
  "die-96-paren-unclosed.c|96|cc: line 2: error 96"
  "die-97-expr-bad-start.c|97|cc: line 2: error 97"
  "die-98-postinc-not-lvalue.c|98|cc: line 2: error 98"
  "die-99-postfix-subscript-no-bracket.c|99|cc: line 2: error 99"
  "die-100-member-of-non-struct.c|100|cc: line 2: error 100"
  "die-101-member-not-name.c|101|cc: line 3: error 101"
  "die-102-sizeof-no-paren.c|102|cc: line 2: error 102"
  "die-103-sizeof-struct-no-tag.c|103|cc: line 2: error 103"
  "die-104-sizeof-struct-unknown.c|104|cc: line 2: error 104"
  "die-105-sizeof-struct-not-tag.c|105|cc: line 3: error 105"
  "die-106-sizeof-bad-keyword.c|106|cc: line 2: error 106"
  "die-107-sizeof-undeclared.c|107|cc: line 2: error 107"
  "die-108-sizeof-function.c|108|cc: line 3: error 108"
  "die-109-sizeof-literal.c|109|cc: line 2: error 109"
  "die-110-sizeof-unclosed.c|110|cc: line 2: error 110"
  "die-113-inc-not-lvalue.c|113|cc: line 4: error 113"
  "die-114-addr-of-literal.c|114|cc: line 2: error 114"
  "die-115-addr-of-undeclared.c|115|cc: line 2: error 115"
  "die-116-addr-of-function.c|116|cc: line 3: error 116"
  "die-117-ternary-no-colon.c|117|cc: line 2: error 117"
  "die-120-assign-not-lvalue.c|120|cc: line 2: error 120"
  "die-121-call-unclosed.c|121|cc: line 3: error 121"
  "die-122-call-seven-args.c|122|cc: line 3: error 122"
  "die-124-const-div-zero.c|124|cc: line 2: error 124"
  "die-125-const-not-enum.c|125|cc: line 4: error 125"
  "die-126-const-bad.c|126|cc: line 4: error 126"
  "die-127-const-paren.c|127|cc: line 2: error 127"
  "die-128-const-colon.c|128|cc: line 2: error 128"
  "die-129-if-trailing.c|129|cc: line 2: error 129"
  "die-140-do-without-while.c|140|cc: line 2: error 140"
  "die-141-do-wrong-keyword.c|141|cc: line 2: error 141"
  "die-142-while-no-paren.c|142|cc: line 2: error 142"
  "die-143-missing-semicolon.c|143|cc: line 2: error 143"
  "die-144-local-no-name.c|144|cc: line 2: error 144"
  "die-145-local-struct-no-tag.c|145|cc: line 2: error 145"
  "die-146-local-struct-unknown.c|146|cc: line 2: error 146"
  "die-147-local-struct-not-tag.c|147|cc: line 3: error 147"
  "die-148-field-struct-no-tag.c|148|cc: line 2: error 148"
  "die-149-struct-def-no-tag.c|149|cc: line 2: error 149"
  "die-150-field-bad-keyword.c|150|cc: line 2: error 150"
  "die-151-field-bad-type.c|151|cc: line 2: error 151"
  "die-152-field-no-name.c|152|cc: line 2: error 152"
  "die-153-fnptr-no-name.c|153|cc: line 2: error 153"
  "die-154-fnptr-no-terminator.c|154|cc: line 2: error 154"
  "die-156-local-array-zero.c|156|cc: line 2: error 156"
  "die-157-local-array-no-bracket.c|157|cc: line 2: error 157"
  "die-159-local-init-no-semicolon.c|159|cc: line 2: error 159"
  "die-160-struct-local-no-name.c|160|cc: line 3: error 160"
  "die-161-struct-ptr-local-bad.c|161|cc: line 3: error 161"
  "die-162-frame-full.c|162|cc: line 7: error 162"
  "die-170-case-no-colon.c|170|cc: line 2: error 170"
  "die-171-labels-full.sh|171|cc: line 67: error 171"
  "die-172-label-twice.c|172|cc: line 2: error 172"
  "die-173-goto-not-name.c|173|cc: line 2: error 173"
  "die-180-param-type-undeclared.c|180|cc: line 2: error 180"
  "die-181-param-type-not-typedef.c|181|cc: line 3: error 181"
  "die-182-param-type-bad.c|182|cc: line 2: error 182"
  "die-183-param-no-name.c|183|cc: line 2: error 183"
  "die-184-fnptr-params-eof.c|184|cc: line 3: error 184"
  "die-185-return-struct-no-tag.c|185|cc: line 2: error 185"
  "die-186-stray-brace.c|186|cc: line 2: error 186"
  "die-187-fn-name-not-ident.c|187|cc: line 2: error 187"
  "die-190-enum-not-name.c|190|cc: line 2: error 190"
  "die-192-enum-no-comma.c|192|cc: line 2: error 192"
  "die-193-typedef-bad-keyword.c|193|cc: line 2: error 193"
  "die-194-typedef-undeclared.c|194|cc: line 2: error 194"
  "die-195-typedef-of-variable.c|195|cc: line 3: error 195"
  "die-196-typedef-bad-base.c|196|cc: line 2: error 196"
  "die-197-typedef-fnptr-no-name.c|197|cc: line 2: error 197"
  "die-198-typedef-name-not-ident.c|198|cc: line 2: error 198"
  "die-199-prototype-name-not-ident.c|199|cc: line 2: error 199"
  "die-202-toplevel-bad-start.c|202|cc: line 2: error 202"
  "die-203-global-no-name.c|203|cc: line 2: error 203"
  "die-205-global-no-semicolon.c|205|cc: line 2: error 205"
  "die-206-fn-undefined.c|206|cc: line 8: error 206"
  "die-207-no-main.c|207|cc: line 5: error 207"
)

D=tests/cc/gates
WORK=build-out/gates
rm -rf "$WORK"
mkdir -p "$WORK/tmp"
WORK=$(cd "$WORK" && pwd)
CC_DIE_TMP=$WORK/die-tmp
export CC_DIE_TMP
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

for g in "${die_gates[@]}"; do
    IFS='|' read -r file want want_err <<< "$g"
    src=$D/$file
    case "$file" in
        *.sh)
            rm -rf "$CC_DIE_TMP"
            mkdir -p "$CC_DIE_TMP"
            sh "$D/$file" > "$WORK/die-src.c"
            src=$WORK/die-src.c
            ;;
    esac
    compile "$src"
    got_err=$(tail -n 1 "$WORK/err")
    if [ "$crc" != "$want" ]; then
        fail "$file: expected compiler exit $want, got $crc ($got_err)"
    elif [ "$got_err" != "$want_err" ]; then
        fail "$file: expected '$want_err', got '$got_err'"
    elif [ -f "$OUT" ]; then
        fail "$file: died but still wrote $OUT"
    else
        pass "$file -> $crc ($got_err)"
    fi
done

for n in "${not_run[@]}"; do
    IFS='|' read -r file why <<< "$n"
    echo "NOT RUN: $file ($why)"
done

[ "$private" = 1 ] || rm -f "$OUT"
echo
coverage=0
"$D/check-coverage.sh" || coverage=$?
echo
echo "run-gates: $PASSED passed, $FAILED failed, ${#not_run[@]} not run"
[ "$coverage" = 0 ] || echo "run-gates: check-coverage.sh failed"
[ "$FAILED" = 0 ] && [ "$coverage" = 0 ]
