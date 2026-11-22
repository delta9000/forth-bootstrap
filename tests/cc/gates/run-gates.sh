#!/usr/bin/env bash
# run-gates.sh -- the Forth C compiler's gate fixtures, compiled and run.
#
#     tests/cc/gates/run-gates.sh               (from anywhere)
#
# The compiler was built one feature at a time behind these gates
# (HISTORY.md, "Gates as the unit of work").  Each fixture is compiled by
# one run of the seed,
#     seed-forth-i386 forth/i386/010-lib.fth tests/cc/i386/job.fth OUT FIXTURE
# into a static i386 program, which runs on the host's kernel through its
# IA32 support and must exit with the status listed here.  The two
# fixtures marked libc include <stdio.h> and call putchar and exit, so
# they are compiled as the tools are, against M2libc
# (tinycc/i386-seed/tool.fth in place of job.fth).
#
# A die gate is a program the compiler must refuse: the seed exits with
# the listed code, the last line it writes to stderr is cc-die's
# "cc: line N: error C" (forth/i386/020-cc-arena.fth), and no OUT is
# written.  A .c fixture is compiled as it is.  A .sh fixture is a
# generator for an input too large or too repetitive to check in: run
# with sh, it prints the C source on stdout and may write helper files (a
# header to #include) into $CC_DIE_TMP, which is build-out/gates/die-tmp.
#
# Every gate runs; the script prints PASS or FAIL for each, then runs
# check-coverage.sh (error codes against the die gates), and exits 1 at the
# end if any gate or the coverage check failed.
#
# Needs a kernel that runs i386 programs (the seed is one:
# ./seed-forth-i386, or the program SEED_I386 names).
set -euo pipefail
cd "$(dirname "$0")/../../.."

[ -n "${SEED_I386:-}" ] || seed/i386/build.sh > /dev/null
SEED=${SEED_I386:-./seed-forth-i386}

# "<fixture> <expected exit> [libc]"
gates=(
  "G0.c 42"
  "G1.c 10"
  "G2.c 41"
  "G3.c 42"
  "G4.c 42 libc"
  "G5.c 60 libc"
  "G6a.c 50"
  "G6b.c 7"
  "G7.c 7"
  "G8.c 30"
  "G9a.c 42"
  "G9b.c 42"
  "G10a.c 204"
  "G10b.c 42"
  "G10c.c 48"
  "G11.c 141"
  "G12.c 47"
  "G13.c 114"
  "G14a.c 95"
  "G14b.c 42"
  "G14c.c 8"
  "G14d.c 221"
  "M1b.c 51"
)
# Die gates: "<fixture>|<expected seed exit>|<expected last stderr line>".
# tests/cc/gates/check-coverage.sh, run at the end, reads this list and
# counts which of the compiler's error codes it tests.
die_gates=(
  "die-10-arena-full.sh|10|cc: line 9119: error 10"
  "die-20-input-too-big.sh|20|cc: line 1: error 20"
  "die-21-output-full.sh|21|cc: line 19784: error 21"
  "die-30-include-missing.c|30|cc: line 2: error 30"
  "die-31-include-deep.c|31|cc: line 67: error 31"
  "die-32-include-too-big.sh|32|cc: line 1: error 32"
  "die-33-include-path-long.sh|33|cc: line 1: error 33"
  "die-34-macro-table-full.sh|34|cc: line 4097: error 34"
  "die-35-macro-pool-full.sh|35|cc: line 1311: error 35"
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
  "die-50-struct-fields.sh|50|cc: line 1025: error 50"
  "die-58-bitfield.c|58|cc: line 3: error 58"
  "die-58-field-struct-no-tag.c|58|cc: line 2: error 58"
  "die-60-symbols-full.sh|60|cc: line 8193: error 60"
  "die-61-scopes-deep.c|61|cc: line 66: error 61"
  "die-80-globals-full.sh|80|cc: line 1: error 80"
  "die-81-global-refs-full.sh|81|cc: line 16387: error 81"
  "die-82-bss-full.c|82|cc: line 3: error 82"
  "die-90-field-unknown.c|90|cc: line 3: error 90"
  "die-93-addr-of-undeclared.c|93|cc: line 2: error 93"
  "die-93-ident-undeclared.c|93|cc: line 2: error 93"
  "die-93-line-macro.c|93|cc: line 6: error 93"
  "die-93-sizeof-undeclared.c|93|cc: line 2: error 93"
  "die-95-typedef-as-value.c|95|cc: line 3: error 95"
  "die-96-paren-unclosed.c|96|cc: line 2: error 96"
  "die-97-expr-bad-start.c|97|cc: line 2: error 97"
  "die-97-sizeof-bad-keyword.c|97|cc: line 2: error 97"
  "die-97-sizeof-no-paren.c|97|cc: line 2: error 97"
  "die-99-postfix-subscript-no-bracket.c|99|cc: line 2: error 99"
  "die-99-subscript-no-bracket.c|99|cc: line 2: error 99"
  "die-100-float-arithmetic.c|100|cc: line 7: error 100"
  "die-100-member-of-non-struct.c|100|cc: line 2: error 100"
  "die-101-member-not-name.c|101|cc: line 3: error 101"
  "die-110-sizeof-struct-no-tag.c|110|cc: line 2: error 110"
  "die-110-sizeof-unclosed.c|110|cc: line 2: error 110"
  "die-113-inc-not-lvalue.c|113|cc: line 4: error 113"
  "die-113-postinc-not-lvalue.c|113|cc: line 2: error 113"
  "die-116-addr-of-literal.c|116|cc: line 2: error 116"
  "die-117-ternary-no-colon.c|117|cc: line 2: error 117"
  "die-120-assign-not-lvalue.c|120|cc: line 2: error 120"
  "die-121-call-unclosed.c|121|cc: line 3: error 121"
  "die-124-const-div-zero.c|124|cc: line 2: error 124"
  "die-125-const-not-enum.c|125|cc: line 4: error 125"
  "die-126-const-bad.c|126|cc: line 4: error 126"
  "die-127-const-paren.c|127|cc: line 2: error 127"
  "die-128-const-colon.c|128|cc: line 2: error 128"
  "die-129-if-trailing.c|129|cc: line 2: error 129"
  "die-131-long-long-divide.c|131|cc: line 7: error 131"
  "die-131-long-long-modulo.c|131|cc: line 7: error 131"
  "die-140-do-without-while.c|140|cc: line 2: error 140"
  "die-141-do-wrong-keyword.c|141|cc: line 2: error 141"
  "die-142-while-no-paren.c|142|cc: line 2: error 142"
  "die-143-local-array-no-bracket.c|143|cc: line 2: error 143"
  "die-143-missing-semicolon.c|143|cc: line 2: error 143"
  "die-144-fnptr-no-name.c|144|cc: line 2: error 144"
  "die-144-typedef-fnptr-no-name.c|144|cc: line 2: error 144"
  "die-152-field-no-name.c|152|cc: line 2: error 152"
  "die-162-frame-full.c|162|cc: line 6: error 162"
  "die-170-case-no-colon.c|170|cc: line 2: error 170"
  "die-171-labels-full.sh|171|cc: line 67: error 171"
  "die-172-label-twice.c|172|cc: line 2: error 172"
  "die-173-goto-not-name.c|173|cc: line 2: error 173"
  "die-174-label-undefined.c|174|cc: line 2: error 174"
  "die-184-fnptr-params-eof.c|184|cc: line 3: error 184"
  "die-190-enum-not-name.c|190|cc: line 2: error 190"
  "die-192-enum-no-comma.c|192|cc: line 2: error 192"
  "die-194-param-type-undeclared.c|194|cc: line 2: error 194"
  "die-194-typedef-undeclared.c|194|cc: line 2: error 194"
  "die-195-param-type-not-typedef.c|195|cc: line 3: error 195"
  "die-195-typedef-of-variable.c|195|cc: line 3: error 195"
  "die-203-fn-name-not-ident.c|203|cc: line 2: error 203"
  "die-203-global-no-name.c|203|cc: line 2: error 203"
  "die-203-local-no-name.c|203|cc: line 2: error 203"
  "die-203-local-struct-no-tag.c|203|cc: line 2: error 203"
  "die-203-prototype-name-not-ident.c|203|cc: line 2: error 203"
  "die-203-return-struct-no-tag.c|203|cc: line 2: error 203"
  "die-203-struct-def-no-tag.c|203|cc: line 2: error 203"
  "die-203-typedef-name-not-ident.c|203|cc: line 2: error 203"
  "die-205-fnptr-no-terminator.c|205|cc: line 2: error 205"
  "die-205-global-no-semicolon.c|205|cc: line 2: error 205"
  "die-205-local-init-no-semicolon.c|205|cc: line 2: error 205"
  "die-205-struct-ptr-local-bad.c|205|cc: line 3: error 205"
  "die-206-fn-undefined.c|206|cc: line 8: error 206"
  "die-207-no-main.c|207|cc: line 5: error 207"
  "die-211-fn-defined-twice.c|211|cc: line 3: error 211"
  "die-212-struct-argument.c|212|cc: line 5: error 212"
  "die-213-member-array-of-arrays.c|213|cc: line 2: error 213"
  "die-219-static-init-not-constant.c|219|cc: line 3: error 219"
  "die-220-string-for-int-array.c|220|cc: line 3: error 220"
  "die-221-initializer-eof.c|221|cc: line 4: error 221"
  "die-223-string-too-long.c|223|cc: line 2: error 223"
  "die-224-struct-init-other-type.c|224|cc: line 5: error 224"
  "die-225-array-init-no-brace.c|225|cc: line 2: error 225"
  "die-227-scalar-init-unclosed.c|227|cc: line 2: error 227"
  "die-238-member-function.c|238|cc: line 2: error 238"
)

D=tests/cc/gates
WORK=build-out/gates
rm -rf "$WORK"
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
CC_DIE_TMP=$WORK/die-tmp
export CC_DIE_TMP
OUT=$WORK/out

# compile JOB SRC: run the compiler on SRC; sets crc, leaves what the seed
# wrote to stdout and stderr in $WORK/stdout and $WORK/err.
compile() {
    rm -f "$OUT"
    crc=0
    "$SEED" forth/i386/010-lib.fth "$1" "$OUT" "$2" > "$WORK/stdout" 2> "$WORK/err" || crc=$?
}

PASSED=0
FAILED=0
pass() { echo "PASS: $*"; PASSED=$((PASSED + 1)); }
fail() { echo "FAIL: $*"; FAILED=$((FAILED + 1)); }

for g in "${gates[@]}"; do
    read -r file want libc <<< "$g"
    job=tests/cc/i386/job.fth
    [ "${libc:-}" = libc ] && job=tinycc/i386-seed/tool.fth
    compile "$job" "$D/$file"
    # The Forth outer interpreter reports an unknown word on stdout and
    # goes on, so anything on stdout is a failure too.
    if [ "$crc" != 0 ] || [ -s "$WORK/stdout" ] || [ ! -f "$OUT" ]; then
        fail "$file: compiler exit $crc ($(tail -n 1 "$WORK/err")$(head -c 100 "$WORK/stdout"))"
        continue
    fi
    rc=0
    "$OUT" > /dev/null 2>&1 || rc=$?
    if [ "$rc" != "$want" ]; then
        fail "$file: expected exit $want, got $rc"
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
    compile tests/cc/i386/job.fth "$src"
    got_err=$(tail -n 1 "$WORK/err")
    if [ "$crc" != "$want" ]; then
        fail "$file: expected compiler exit $want, got $crc ($got_err)"
    elif [ "$got_err" != "$want_err" ]; then
        fail "$file: expected '$want_err', got '$got_err'"
    elif [ -s "$WORK/stdout" ]; then
        fail "$file: the seed wrote to stdout: $(head -c 100 "$WORK/stdout")"
    elif [ -f "$OUT" ]; then
        fail "$file: died but still wrote $OUT"
    else
        pass "$file -> $crc ($got_err)"
    fi
done

[ "$(ls "$D" | grep -c '^die-')" = "${#die_gates[@]}" ] \
    || fail "$D has $(ls "$D" | grep -c '^die-') die-* fixtures, the list has ${#die_gates[@]}"

echo
coverage=0
"$D/check-coverage.sh" || coverage=$?
echo
echo "run-gates: $PASSED passed, $FAILED failed"
[ "$coverage" = 0 ] || echo "run-gates: check-coverage.sh failed"
[ "$FAILED" = 0 ] && [ "$coverage" = 0 ]
