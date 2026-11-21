\ tests/seed/i386/boot.fth -- what the i386 seed runs in the builder-hex0
\ boot of tests/seed/i386/boot-check.sh.  Seed-level Forth: only the seed's
\ 21 words and decimal numbers.  It prints, each on a line of its own,
\   OK        the seed runs and writes to the console
\   A         Appendix B's 38 vectors for * and / : 65 + the number that fail
\   AAAAAA    six checks of the break and of memory above the file, below
\   S:...     /seed-forth-i386, the file builder-hex0's hex0 has just built,
\             as hex, 32 bytes to a line
\   END
\ and boot-check.sh compares all of it with the host's ./seed-forth-i386.

: emit state 400 + c! 1 state 400 + 1 0 0 0 4 syscall6 drop ;
: nl 10 emit ;
: - dup nand 1 + + ;
: and nand dup nand ;
: here state 16 + @ ;
: , here ! here 8 + state 16 + ! ;
: c, here c! here 1 + state 16 + ! ;
: immediate 1 state 8 + @ 8 + c! ;

\ Control flow as forth/010-lib.fth builds it: a call to branch or 0branch
\ followed by a cell holding the target.  mark lays an empty cell and leaves
\ its address, resolve stores HERE into it, begin leaves HERE, back lays the
\ address on top of the stack and again the one under it.
: branch r> @ >r ;
: 0branch 0= r> dup @ swap 8 + dup >r - and r> + >r ;
: mark here 0 , ; immediate
: resolve here swap ! ; immediate
: begin here ; immediate
: back , ; immediate
: again swap , ; immediate

nl 79 emit 75 emit nl

\ Appendix B of seed/i386/SPEC.md: each line adds 0 if the result is right.
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
65 + emit nl

\ Six checks, each printing A (66 - 1) when it holds and B when it does not.
\ 1. The break is at the image's end, 0x0A048000 = 168067072: the seed
\    raised it.  builder-hex0 starts it 0x20000 above the file.
0 0 0 0 0 0 45 syscall6 168067072 - 0= 66 + emit
\ 2, 3. Memory far above the first break (0x09000000 = 150994944) reads as
\    zero, and holds what is stored there.
150994944 @ 0= 66 + emit
1311768467463790320 150994944 ! 150994944 @ 1311768467463790320 - 0= 66 + emit
\ 4, 5, 6. 150,000 bytes laid in the dictionary, past the first break at
\    0x20000 above the file; read back and summed; a word defined after them.
: fill begin dup c, 1 + dup 150000 - 0= 0branch back drop ;
: sum begin swap dup c@ state 600 + @ + state 600 + ! 1 + swap 1 + dup 150000 - 0= 0branch back drop drop ;
here state 608 + ! 0 fill here state 608 + @ - 150000 - 0= 66 + emit
0 state 600 + ! state 608 + @ 0 sum state 600 + @ 19123080 - 0= 66 + emit
: far 65 emit ; far

\ The dump.  open-next opens the file named by the next token, read only;
\ the name is in the token buffer, which has room for the 0 after it.
: fd state 616 + ;
: n state 624 + ;
: digit dup 10 / 39 * + 48 + emit ;
: .byte dup 16 / digit dup 16 / 16 * - digit ;
: ?prefix n @ dup 32 / 32 * - 0= 0branch mark nl 83 emit 58 emit resolve ;
: open-next token swap dup state 600 + ! + 0 swap c! state 600 + @ 0 0 0 0 0 5 syscall6 fd ! ;
: dump begin fd @ state 408 + 1 0 0 0 3 syscall6 0branch mark ?prefix state 408 + c@ .byte n @ 1 + n ! branch again resolve nl ;
open-next /seed-forth-i386
0 n ! dump
69 emit 78 emit 68 emit nl
