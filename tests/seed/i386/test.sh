#!/usr/bin/env bash
# tests/seed/i386/test.sh -- the i386 seed alone (seed/i386/SPEC.md 13.1).
#
#   tests/seed/i386/test.sh            every case
#   tests/seed/i386/test.sh --strace   the same cases, each run under
#                                      strace -f, with its system calls
#                                      checked by strace-check.py
#
# Each case puts seed-level Forth in a file and runs ./seed-forth-i386 FILE.
# Every case runs; a failing one prints FAIL with what it got, and the script
# exits 1 at the end with the count.
#
# A case of kind "same" is its text alone.  A case of kind "prelude" starts
# with two lines that define emit and die on syscall6 (write is call 4,
# exit is call 1).
#
# The expected status and output of each case are also compared with what
# tests/reference.py computes for the case's text in Python, where it can:
# it knows the arithmetic, stack and memory words, numbers and the fatal
# error, and declines the cases that need token, find, key, syscall6, the
# system variables or a return address.  A case where the two disagree
# fails; the last line says how many cases had this second opinion.  (Until
# tag experiments-2026-11-21 the second opinion was the x86-64 seed, run on
# the same text.)
#
# The strace run checks, for every case: the only calls are brk, open, read,
# write and exit; no read of descriptor 0; every read has count 1; no brk
# below the current break; and the number of open calls.  That number is 1
# for the seed's own open of FILE, plus the opens the case's Forth makes
# itself through syscall6 (the INPUT and the failed-open cases: 2), and 0
# when there is no FILE argument.  The write and exit calls the cases make
# through syscall6 are in the allowed set, so they need no exception.
set -euo pipefail
cd "$(dirname "$0")/../../.."
ROOT=$PWD

STRACE=0
[ "${1:-}" = --strace ] && STRACE=1

seed/i386/build.sh
SEED=$ROOT/seed-forth-i386

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

PASSED=0
FAILED=0
REFERENCED=0
pass() { echo "  PASS: $*"; PASSED=$((PASSED + 1)); }
fail() { echo "  FAIL: $*"; FAILED=$((FAILED + 1)); }
hex() { od -An -v -tx1 "$1" | tr -d ' \n'; }

# The two-line prelude.  The seed has no emit, so the tests define one: the
# byte goes to a free address 400 bytes into the sysvar page and is written
# from there with syscall6.  die exits with the status on the stack.
PRE=': emit state 400 + c! 1 state 400 + 1 0 0 0 4 syscall6 drop ;
: die 0 0 0 0 0 1 syscall6 ;
'
# run OPENS ARG...: run the seed in $W with the arguments; sets ec and out
# (stdout in hex).  Under --strace, also sets trace_error if the calls break
# a rule.
run() {
    local opens=$1; shift
    ec=0; trace_error=
    if [ "$STRACE" = 1 ]; then
        (cd "$W" && timeout 60 strace -f -o trace "$SEED" "$@" > out) || ec=$?
        trace_error=$(python3 -I "$ROOT/tests/seed/i386/strace-check.py" "$W/trace" "$opens") || true
    else
        (cd "$W" && timeout 60 "$SEED" "$@" > out) || ec=$?
    fi
    out=$(hex "$W/out")
}

# verdict NAME WANT_EC WANT_OUT: compare ec and out with what is expected
# (WANT_OUT in printf %b form), and report.
verdict() {
    local name=$1 want_ec=$2 want
    printf '%b' "$3" > "$W/want"
    want=$(hex "$W/want")
    if [ "$ec" != "$want_ec" ] || [ "$out" != "$want" ]; then
        fail "$name: exit $ec (expected $want_ec), output $out (expected $want)"
        return 1
    elif [ -n "$trace_error" ]; then
        fail "$name: $trace_error"
        return 1
    fi
}

# check NAME WANT_EC WANT_OUT KIND BODY [OPENS [ARG...]]
# BODY is the file's exact bytes after the prelude (kind "same": the whole
# file).  ARGs follow the file name on the command line.
check() {
    local name=$1 want_ec=$2 want=$3 kind=$4 body=$5 opens=${6:-1}
    shift $(( $# < 6 ? $# : 6 ))
    if [ "$kind" = same ]; then
        printf '%s' "$body" > "$W/case.fth"
    else
        printf '%s%s' "$PRE" "$body" > "$W/case.fth"
    fi
    run "$opens" case.fth "$@"
    verdict "$name" "$want_ec" "$want" && reference "$name" "$want_ec" "$kind" "$body" && pass "$name"
    return 0
}

# reference NAME WANT_EC KIND BODY: what tests/reference.py computes for
# the case against what is expected ($W/want, written by verdict).  Status
# 125 from it means it does not compute this case.
reference() {
    local name=$1 want_ec=$2 ref_ec=0
    printf '%s' "$4" > "$W/body.fth"
    python3 -I "$ROOT/tests/reference.py" seed "$3" "$W/body.fth" > "$W/ref" 2> /dev/null || ref_ec=$?
    [ "$ref_ec" != 125 ] || return 0
    if [ "$ref_ec" != "$want_ec" ] || ! cmp -s "$W/ref" "$W/want"; then
        fail "$name: tests/reference.py computes exit $ref_ec, output $(hex "$W/ref") (expected $want_ec, $(hex "$W/want"))"
        return 1
    fi
    REFERENCED=$((REFERENCED + 1))
}

# Forth used by several cases.
# .8 prints a cell as its 8 bytes, lowest first.
DOT8=': .8 dup emit 256 / dup emit 256 / dup emit 256 / dup emit 256 / dup emit 256 / dup emit 256 / dup emit 256 / emit ;
'
MINUS=': - dup nand 1 + + ;
'
TICK=': tick token find ;
'
# What forth/010-lib.fth builds its control flow from, in the library's own
# text (forth/010-lib.fth:40,45,269,277-283), and immediate words to lay the
# cell after a branch: "mark" lays an empty cell and leaves its address,
# "resolve" stores HERE into the cell on top, "begin" leaves HERE, "back"
# lays the address on top, and "again" lays the one under it.
FLOW=': - dup nand 1 + + ;
: and nand dup nand ;
: here state 16 + @ ;
: , here ! here 8 + state 16 + ! ;
: c, here c! here 1 + state 16 + ! ;
: immediate 1 state 8 + @ 8 + c! ;
: execute >r ;
: r@ r> r> dup >r swap >r ;
: branch r> @ >r ;
: 0branch 0= r> dup @ swap 8 + dup >r - and r> + >r ;
: mark here 0 , ; immediate
: resolve here swap ! ; immediate
: begin here ; immediate
: back , ; immediate
: again swap , ; immediate
'
A=1311768467463790320       # 0x123456789ABCDEF0
B=18364758544493064720      # 0xFEDCBA9876543210
A8='\xf0\xde\xbc\x9a\x78\x56\x34\x12'
B8='\x10\x32\x54\x76\x98\xba\xdc\xfe'
Z8='\x00\x00\x00\x00\x00\x00\x00\x00'
F8='\xff\xff\xff\xff\xff\xff\xff\xff'

echo "----- the outer loop -----"

check "an empty file exits 0" 0 '' same ''
check "end of file in the middle of a definition exits 0" 0 '' same ': t dup'

# No FILE argument and a missing FILE: status 1 and no output.
run 0
verdict "no argument exits 1 and prints nothing" 1 '' && pass "no argument exits 1 and prints nothing"
run 1 no-such-file.fth
verdict "a missing file exits 1 and prints nothing" 1 '' && pass "a missing file exits 1 and prints nothing"

# A token that is neither a word nor an unsigned decimal number is fatal: the
# seed prints it, "?" and a newline and exits 2; nothing after it runs.
check "an unknown token is fatal" 2 'wibble?\n' prelude $'wibble\n65 emit\n'
check "an unknown token is fatal while compiling" 2 'wibble?\n' prelude $': t wibble 65 emit ;\n66 emit\n'
check "an unknown token with nothing defined" 2 'wibble?\n' same $'wibble\n'
for tok in -5 0x41 '$41' 1x 12a '('; do
    check "not a number: $tok" 2 "A$tok?\n" prelude "65 emit $tok 66 emit"$'\n'
done

echo "----- token -----"

# \ comments: a line holding only \, a trailing \ text, \ inside a longer
# token (an ordinary character), and \ as the last byte of the file.
check "\\ comments are skipped" 0 'ABCDE' prelude \
    $'\\ 90 emit this line is a comment\n65 emit\n\\\n66 emit \\ trailing 90 emit\n: a\\b 67 emit ; a\\b\n: \\\\ 68 emit ; \\\\ \n69 emit \\'
check "a \\ comment ended by the end of the file" 0 'A' prelude $'65 emit \\ 66 emit'

# Space, tab, LF and CR separate tokens; so does every byte from 1 to 32, and
# bytes from 127 up are token characters.
check "space, tab, LF and CR are whitespace" 0 'ABC' prelude $'65\temit\r\n66\remit  \t 67 emit'
check "bytes 1 to 32 are whitespace, 127 and above are not" 0 'AB' prelude \
    $': \x7f\xff 66 emit ;\x0165\x1femit\x0c\x7f\xff\x02'

# A 255-byte token is looked up; a 256-byte one is fatal, and its message is
# 256 bytes, "?" and a newline: 258 bytes.
n255=$(printf 'a%.0s' $(seq 255))
check "a 255-byte token is looked up" 0 'A' prelude ": $n255 65 emit ; $n255"$'\n'
check "a 255-byte unknown token: 257-byte message" 2 "$n255?\n" same "$n255 "
check "a 256-byte token is fatal: 258-byte message" 2 "${n255}a?\n" prelude "${n255}a 65 emit"$'\n'
check "a 300-byte token is fatal after 256 bytes" 2 "${n255}a?\n" same "${n255}abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

echo "----- numbers -----"

check "a number is pushed, or compiled in a definition" 0 'AHiHi' prelude \
    $'65 emit\n: greet 72 emit 105 emit ;\ngreet greet\n'
check "0, 2^63 and 2^64-191 are exact" 0 "$Z8"'\x00\x00\x00\x00\x00\x00\x00\x80\x41\xff\xff\xff\xff\xff\xff\xff' prelude \
    "${DOT8}0 .8 9223372036854775808 .8 18446744073709551425 .8"$'\n'
check "the same three as compiled literals" 0 "$Z8"'\x00\x00\x00\x00\x00\x00\x00\x80\x41\xff\xff\xff\xff\xff\xff\xff' prelude \
    "${DOT8}: n0 0 ; : n1 9223372036854775808 ; : n2 18446744073709551425 ; n0 .8 n1 .8 n2 .8"$'\n'
check "numbers wrap past 2^64" 0 "$Z8"'\x41\x00\x00\x00\x00\x00\x00\x00\x41\x00\x00\x00\x00\x00\x00\x00' prelude \
    "${DOT8}18446744073709551616 .8 18446744073709551681 .8 : w 36893488147419103297 ; w .8"$'\n'
check "leading zeros and 4294967296" 0 '\x07\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00' prelude \
    "${DOT8}007 .8 4294967296 .8"$'\n'
check "a defined word whose name starts with digits is a word" 0 'BC' prelude \
    $': 2x dup + ; 33 2x emit : 67 66 ; 67 1 + emit\n'

echo "----- the words of section 7.1, on values with a nonzero high half -----"

check "dup" 0 "$A8$A8" prelude "${DOT8}$A dup .8 .8"$'\n'
check "drop" 0 "$A8" prelude "${DOT8}$A $B drop .8"$'\n'
check "swap" 0 "$A8$B8" prelude "${DOT8}$A $B swap .8 .8"$'\n'
check ">r r>" 0 "$B8$A8" prelude "${DOT8}: t $A >r $B .8 r> .8 ; t"$'\n'
check ">r r> keep the stack under them" 0 "$B8$A8"'C' prelude "${DOT8}: t >r .8 r> .8 ; 67 $B $A t emit"$'\n'
check "@ ! at an odd address" 0 "$A8"'\x00\xf0\xde\xbc\x9a\x78\x56\x34\x12\x00\x00\x00\x00\x00\x00\x00' prelude \
    "${DOT8}0 state 500 + ! 0 state 508 + ! $A state 501 + ! state 501 + @ .8 state 500 + @ .8 state 508 + @ .8"$'\n'
check "! pops both cells" 0 'C' prelude "67 $A state 500 + ! emit"$'\n'
check "c@ reads one byte" 0 '\xf0\x00\x00\x00\x00\x00\x00\x00\x12\x00\x00\x00\x00\x00\x00\x00' prelude \
    "${DOT8}$A state 500 + ! state 500 + c@ .8 state 507 + c@ .8"$'\n'
check "c! writes one byte" 0 '\xff\xff\xff\x10\xff\xff\xff\xffC' prelude \
    "${DOT8}18446744073709551615 state 500 + ! 67 $B state 503 + c! state 500 + @ .8 emit"$'\n'
check "+ modulo 2^64" 0 '\x00\x11\x11\x11\x11\x11\x11\x11' prelude "${DOT8}$A $B + .8"$'\n'
check "+ carries from the low half into the high half" 0 '\x00\x00\x00\x00\x01\x00\x00\x00'"$Z8" prelude \
    "${DOT8}4294967295 1 + .8 18446744073709551615 1 + .8"$'\n'
check "*" 0 '\x00\xcf\x18\x56\xfe\x88\x6d\x23' prelude "${DOT8}$A $B * .8"$'\n'
check "/" 0 '\x00\x00\x00\xe0\x00\x00\x00\x00\x0e\x00\x00\x00\x00\x00\x00\x00' prelude \
    "${DOT8}$B 4886718345 / .8 $B $A / .8"$'\n'
check "/ is unsigned, with a 64-bit quotient" 0 '\xff\xff\xff\xff\xff\xff\xff\x00\x01\x00\x00\x00\x00\x00\x00\x00' prelude \
    "${DOT8}18446744073709551615 256 / .8 18446744073709551615 9223372036854775808 / .8"$'\n'
check "/ * + on small values" 0 '03?A' prelude $'4096 16 / 48 + emit 17 5 / 48 + emit 7 9 * emit 60 5 + emit\n'
check "nand" 0 '\xef\xed\xeb\xed\xe7\xed\xeb\xed' prelude "${DOT8}$A $B nand .8"$'\n'
check "0=" 0 "$F8$Z8$Z8$Z8" prelude "${DOT8}0 0= .8 1 0= .8 4294967296 0= .8 $A 0= .8"$'\n'
check "0= nand on small values" 0 'AAA' prelude $'0 0= 66 + emit 5 0= 65 + emit 12 10 nand 74 + emit\n'

echo "----- Appendix B: vectors for * and / -----"

APPB=': - dup nand 1 + + ;
0
100 7 / 14 - 0= 1 + +
18446744073709551615 1 / 18446744073709551615 - 0= 1 + +
18446744073709551615 10 / 1844674407370955161 - 0= 1 + +
9223372036854775808 10 / 922337203685477580 - 0= 1 + +
18446744073709551615 4294967295 / 4294967297 - 0= 1 + +
18446744073709551615 4294967296 / 4294967295 - 0= 1 + +
18446744073709551615 4294967297 / 4294967295 - 0= 1 + +
9223372036854775808 9223372036854775808 / 1 - 0= 1 + +
9223372036854775807 9223372036854775808 / 0 - 0= 1 + +
18446744073709551615 9223372036854775808 / 1 - 0= 1 + +
18446744073709551615 9223372036854775809 / 1 - 0= 1 + +
18446744073709551615 18446744073709551615 / 1 - 0= 1 + +
18446744073709551614 18446744073709551615 / 0 - 0= 1 + +
1311768467463790320 4294967297 / 305419896 - 0= 1 + +
18364758544493064720 4886718345 / 3758096384 - 0= 1 + +
18446744069414584320 4294967295 / 4294967296 - 0= 1 + +
9223372036854775808 3 / 3074457345618258602 - 0= 1 + +
18446744073709551615 18446744065119617025 / 1 - 0= 1 + +
12345678901234567890 9876543210 / 1249999988 - 0= 1 + +
9223372036854775807 2147483648 / 4294967295 - 0= 1 + +
4294967296 4294967295 / 1 - 0= 1 + +
5 18446744073709551615 / 0 - 0= 1 + +
0 5 / 0 - 0= 1 + +
16045690984503098046 281479271612417 / 57004 - 0= 1 + +
18446744073709551615 9223372036854775807 / 2 - 0= 1 + +
6 7 * 42 - 0= 1 + +
4294967295 4294967295 * 18446744065119617025 - 0= 1 + +
4294967296 4294967296 * 0 - 0= 1 + +
18446744073709551615 18446744073709551615 * 1 - 0= 1 + +
18446744073709551615 2 * 18446744073709551614 - 0= 1 + +
9223372036854775808 2 * 0 - 0= 1 + +
1311768467463790320 18364758544493064720 * 2552847189736476416 - 0= 1 + +
4294967295 4294967297 * 18446744073709551615 - 0= 1 + +
4294967297 4294967295 * 18446744073709551615 - 0= 1 + +
12345678901234567890 10 * 12776324570088369204 - 0= 1 + +
3735928559 14627333964952502272 * 9858198585802227712 - 0= 1 + +
14627333964952502272 3735928559 * 9858198585802227712 - 0= 1 + +
33 5381 * 177573 - 0= 1 + +
die
'
check "Appendix B: all 38 vectors, exit 0" 0 '' prelude "$APPB"
check "Appendix B with one expectation made wrong exits 1" 1 '' prelude "${APPB/100 7 \/ 14 -/100 7 \/ 15 -}"

echo "----- token, find, key, : and ; -----"

check "token find: a found word's xt runs" 0 'A' prelude \
    "${TICK}"$'65 tick emit state 600 + ! : run state 600 + @ >r ; run\n'
check "find: a miss is a whole cell of 0" 0 "$Z8" prelude "${DOT8}${TICK}"$'tick no-such-word .8\n'
check "find: the newest definition wins" 0 'AB' prelude $': w 65 emit ; w : w 66 emit ; w\n'
check "find: a word is findable inside its own definition" 0 'A' prelude $': again again ; 65 emit\n'
check "find: any address, exact length, exact case" 0 "$F8$Z8$Z8$Z8" prelude \
    "${DOT8}${MINUS}${TICK}"$'100 state 500 + c! 117 state 501 + c! 112 state 502 + c! 68 state 503 + c!\nstate 500 + 3 find tick dup - 0= .8 state 500 + 2 find .8 state 500 + 4 find .8 state 503 + 1 find .8\n'
check "find: LAST_FOUND is the header, xt = header + 10 + nlen" 0 "$F8" prelude \
    "${DOT8}${MINUS}${TICK}"$': t tick state 24 + @ 14 + - 0= .8 ; t swap\n'
check "key: the byte right after the calling token, and 0 at the end" 0 'ZA' prelude \
    $': k key emit ; : z key 65 + emit ; k\nZz'
check "key: the byte after a one-byte separator, whatever it is" 0 '\x0a ' prelude $': k key emit ; k \nk\t \n'
# : at the end of the file: the name is empty.  The word go runs as the last
# token, so : finds no token; its header has nlen 0, find matches it for
# u = 0, and HERE is just after it.
check ": at the end of the file makes a header with an empty name" 0 'AAA' prelude \
    "${MINUS}"$': latest state 8 + @ ;\n: go : latest 9 + c@ 65 + emit state 0 find latest 10 + - 0= 66 + emit state 16 + @ latest 10 + - 0= 66 + emit ;\ngo'
check ": is not immediate, sets STATE to 1 and links to the header before" 0 'BAA' prelude \
    "${MINUS}"$': latest state 8 + @ ;\n: mk : state @ 65 + emit 0 state ! ;\nlatest state 600 + ! mk new latest @ state 600 + @ - 0= 66 + emit latest 8 + c@ 65 + emit\n'
check "; is immediate and sets STATE to 0" 0 'BA' prelude "${TICK}"$': f tick drop state 24 + @ 8 + c@ 65 + emit ; f ; : t ; state @ 65 + emit\n'
# The bytes laid down: ; lays C2 04 00, a compiled word lays 6A 00 E8 and a
# rel32 counted from the end of those seven bytes.  w's body is a call to
# nop, 21 bytes back from the call's end; rec's is a call to itself.
check "; lays C2 04 00 and a compiled word lays 6A 00 E8 rel32" 0 '\x6a\x00\xe8\xeb\xff\xff\xff\xc2\x04\x00\x6a\x00\xe8\xf9\xff\xff\xff\xc2\x04\x00' prelude \
    "${TICK}"$': nop ; : w nop ; : rec rec ;\n: b dup c@ emit 1 + ; : dump b b b b b b b b b b drop ;\ntick w dump tick rec dump\n'
check "a compiled literal takes at most 18 bytes and : lays no prologue" 0 'AA' prelude \
    "${MINUS}${TICK}"$': here state 16 + @ ;\n: lit 12345678901234567890 ;\nhere tick lit - 3 - 19 / 0= 66 + emit\n: e ; here tick e - 3 - 0= 66 + emit\n'

echo "----- the five traces of section 5.2 -----"

check "execute: >r and a return enter the xt" 0 'AB' prelude \
    "${FLOW}${TICK}"$': a 65 emit ; : t tick execute 66 emit ; t a\n'
check "execute from the outer loop" 0 'A' prelude "${FLOW}${TICK}"$': a 65 emit ; tick a execute\n'
check "r@ copies the cell under the return cell" 0 'BBC' prelude \
    "${FLOW}"$': t 66 >r r@ emit r> emit 67 emit ; t\n'
check "branch jumps over code" 0 'AC' prelude \
    "${FLOW}"$': t 65 emit branch mark 66 emit resolve 67 emit ; t\n'
check "0branch: taken on 0, not taken otherwise" 0 'BABAB' prelude \
    "${FLOW}"$': t 0branch mark 65 emit resolve 66 emit ; 0 t 1 t 4294967296 t\n'
check "0branch backward: a loop" 0 'ABCD' prelude \
    "${FLOW}"$': t begin dup emit 1 + dup 69 - 0= 0branch back drop ; 65 t\n'
check "branch backward and 0branch forward: a loop with its test first" 0 'ABCD!' prelude \
    "${FLOW}"$': t begin dup 69 - 0branch mark dup emit 1 + branch again resolve drop 33 emit ; 65 t\n'
# A definition that ends in a jump (E9 rel32) to the seed's >r, as
# cc/020-cc-arena.fth:183-193 lays it: compiled, and from the outer loop,
# where the only return cell is the loop's.
check "a definition ending in a jump to >r" 0 'GFH' prelude \
    "${FLOW}"$': ,4 dup c, 256 / dup c, 256 / dup c, 256 / c, ;\n: jmp, 233 c, token find here 4 + - ,4 0 state ! ; immediate\n: my>r jmp, >r\n: t 70 my>r 71 emit r> emit ; t\n72 my>r r> emit\n'

echo "----- INPUT, ARGV, syscall6 and a large dictionary -----"

# A second file, f2, opened with syscall6; its descriptor stored in INPUT
# makes key read it from the next byte on, and the old descriptor stored
# back continues the first file after the point where it was left.
printf '68 emit old @ state 32 + ! 69 emit\n' > "$W/f2"
check "INPUT: a second file, and back to the first where it left off" 0 'ADBC' prelude \
    $': old state 608 + ; state 32 + @ old !\n102 state 600 + c! 50 state 601 + c! 0 state 602 + c!\n65 emit state 600 + 0 0 0 0 0 5 syscall6 state 32 + ! 66 emit\n67 emit\n' 2
# ARGV holds the address of the argv[0] pointer; the pointers are 4 bytes.
check "ARGV: the bytes of argv[1] and argv[2]" 0 'case.fthXYZ' prelude \
    "${MINUS}"$': low dup 4294967296 / 4294967296 * - ;\n: arg 4 * state 40 + @ + @ low ;\n: b dup c@ emit 1 + ;\n1 arg b b b b b b b b drop 2 arg b b b drop\n' 1 XYZ second
check "ARGV: its high half is 0, and argv[argc] is a null pointer" 0 "$F8$F8" prelude \
    "${DOT8}${MINUS}"$': low dup 4294967296 / 4294967296 * - ;\nstate 40 + @ 4294967296 / 0= .8 state 40 + @ 12 + @ low 0= .8\n' 1 XYZ
check "INPUT, LATEST and HERE are clean cells" 0 "$F8$F8$F8" prelude \
    "${DOT8}"$'state 32 + @ 4294967296 / 0= .8 state 8 + @ 4294967296 / 0= .8 state 16 + @ 4294967296 / 0= .8\n'
# 0< as forth/010-lib.fth:131 builds it.  A failed open (no such file: the
# path is the two bytes "f3") is negative as a cell.
check "syscall6: a failed open is negative as a cell" 0 'A' prelude \
    $': 0< 9223372036854775808 / 0= 0= ;\n102 state 600 + c! 51 state 601 + c! 0 state 602 + c!\nstate 600 + 0 0 0 0 0 5 syscall6 0< 66 + emit\n' 2
check "syscall6: write returns its count, and the seven cells are popped" 0 'f3\nDC' prelude \
    $'102 state 600 + c! 51 state 601 + c! 10 state 602 + c!\n67 1 state 600 + 3 0 0 0 4 syscall6 65 + emit emit\n'
check "syscall6: exit with a status" 7 'A' prelude $'65 emit 7 die 66 emit\n'
# 150,000 bytes laid with c, (more than 0x20000), read back and summed; then
# a word defined after them.
check "a dictionary of more than 0x20000 bytes, read back" 0 'AAB' prelude \
    "${FLOW}"$': fill begin dup c, 1 + dup 150000 - 0= 0branch back drop ;\n: sum begin swap dup c@ state 600 + @ + state 600 + ! 1 + swap 1 + dup 150000 - 0= 0branch back drop drop ;\nhere state 608 + ! 0 fill here state 608 + @ - 150000 - 0= 66 + emit\n0 state 600 + ! state 608 + @ 0 sum state 600 + @ 19123080 - 0= 66 + emit\n: far 66 emit ; far\n'

echo
if [ "$STRACE" = 1 ]; then
    echo "tests/seed/i386/test.sh --strace: $PASSED passed, $FAILED failed; every run's system calls checked"
else
    echo "tests/seed/i386/test.sh: $PASSED passed, $FAILED failed"
fi
echo "  $REFERENCED cases' expected values agree with tests/reference.py"
[ "$FAILED" = 0 ]
