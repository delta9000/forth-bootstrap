\ tests/forth/i386/high-halves.fth -- the host's primitives on cells whose
\ halves both matter.
\
\ On the i386 host a cell is two 32-bit words, and every primitive of
\ forth/i386/020-cc-arena.fth has to carry, borrow, compare, load, store
\ or test across the two.  The compiler's output would show a dropped
\ carry only if some compiled program's bytes happened to depend on it, so
\ these cases ask directly.
\
\ Loaded after the library, high-halves-judge.fth and 020
\ (tests/forth/i386/high-halves-check.sh).  The expected values were first
\ checked on a host where a cell is one register (the x86-64 seed of tag
\ experiments-2026-11-21, with its library alone).
\
\ Each case computes a value, then `EXPECTED same tally`.  A true flag is
\ expected as 18446744073709551615, spelt out: the library's `true` is `0 0=`,
\ which 020 compiles again with its own 0=.  Every case
\ comes twice, because 020 gives each primitive two forms: typed at the
\ top level it runs the word (the code: words, or the seed's); inside a
\ definition it is the instructions copied in place.  The word c is
\ redefined for each compiled case and run at once.
\
\ The first line leaves a value on the stack and the end expects to find
\ it on top: a primitive that takes or leaves one cell too many moves it.
\ The end prints "high-halves: done" and exits with the number of cases
\ that failed.  The line matters: a broken primitive can also end the run
\ early with status 0, when the interpreter takes it for the end of input.
\
\   4294967295            2^32 - 1: the low half full
\   4294967296            2^32: the low half 0, the high half 1
\   9223372036854775808   2^63: the sign bit alone
\   18446744073709551615  2^64 - 1, which is -1
\   1311768467463790320   0x123456789ABCDEF0: every byte different

1311768467463790320                   \ stays until the end

\ ----- + - 1+ 1-: the carry and the borrow between the halves -----
4294967295 1 +                        4294967296 same tally
: c  4294967295 1 +                   4294967296 same tally ; c
18446744073709551615 1 +              0 same tally
: c  18446744073709551615 1 +         0 same tally ; c
4294967296 4294967295 +               8589934591 same tally
: c  4294967296 4294967295 +          8589934591 same tally ; c
4294967296 1 -                        4294967295 same tally
: c  4294967296 1 -                   4294967295 same tally ; c
0 1 -                                 18446744073709551615 same tally
: c  0 1 -                            18446744073709551615 same tally ; c
8589934591 4294967295 -               4294967296 same tally
: c  8589934591 4294967295 -          4294967296 same tally ; c
1311768467463790320 4294967296 -      1311768463168823024 same tally
: c  1311768467463790320 4294967296 - 1311768463168823024 same tally ; c
4294967295 1+                         4294967296 same tally
: c  4294967295 1+                    4294967296 same tally ; c
18446744073709551615 1+               0 same tally
: c  18446744073709551615 1+          0 same tally ; c
4294967296 1-                         4294967295 same tally
: c  4294967296 1-                    4294967295 same tally ; c
0 1-                                  18446744073709551615 same tally
: c  0 1-                             18446744073709551615 same tally ; c

\ ----- = <> 0=: a difference in the high half alone is a difference -----
4294967296 0 =                        0 same tally
: c  4294967296 0 =                   0 same tally ; c
1 4294967297 =                        0 same tally
: c  1 4294967297 =                   0 same tally ; c
1311768467463790320 1311768467463790320 =       18446744073709551615 same tally
: c  1311768467463790320 1311768467463790320 =  18446744073709551615 same tally ; c
4294967297 4294967298 =               0 same tally
: c  4294967297 4294967298 =          0 same tally ; c
4294967297 4294967298 <>              18446744073709551615 same tally
: c  4294967297 4294967298 <>         18446744073709551615 same tally ; c
1311768467463790320 0 <>              18446744073709551615 same tally
: c  1311768467463790320 0 <>         18446744073709551615 same tally ; c
4294967296 0 <>                       18446744073709551615 same tally
: c  4294967296 0 <>                  18446744073709551615 same tally ; c
1311768467463790320 1311768467463790320 <>      0 same tally
: c  1311768467463790320 1311768467463790320 <> 0 same tally ; c
4294967296 0=                         0 same tally
: c  4294967296 0=                    0 same tally ; c
0 0=                                  18446744073709551615 same tally
: c  0 0=                             18446744073709551615 same tally ; c

\ ----- < > <= >= 0<: the sign of the whole difference -----
\ 4294967295 < 4294967296 although its low half is the larger; and -1 < 0.
\ 0 - 1 is negative through the borrow out of the low half, and
\ 1 - (2^63 - 1) is negative with a high half that is not all ones.
0 1 <                                 18446744073709551615 same tally
: c  0 1 <                            18446744073709551615 same tally ; c
1 9223372036854775807 <               18446744073709551615 same tally
: c  1 9223372036854775807 <          18446744073709551615 same tally ; c
9223372036854775807 1 <               0 same tally
: c  9223372036854775807 1 <          0 same tally ; c
1 0 >                                 18446744073709551615 same tally
: c  1 0 >                            18446744073709551615 same tally ; c
9223372036854775807 1 >               18446744073709551615 same tally
: c  9223372036854775807 1 >          18446744073709551615 same tally ; c
0 1 <=                                18446744073709551615 same tally
: c  0 1 <=                           18446744073709551615 same tally ; c
1 9223372036854775807 >=              0 same tally
: c  1 9223372036854775807 >=         0 same tally ; c
4294967295 4294967296 <               18446744073709551615 same tally
: c  4294967295 4294967296 <          18446744073709551615 same tally ; c
4294967296 4294967295 <               0 same tally
: c  4294967296 4294967295 <          0 same tally ; c
4294967296 4294967296 <               0 same tally
: c  4294967296 4294967296 <          0 same tally ; c
18446744073709551615 0 <              18446744073709551615 same tally
: c  18446744073709551615 0 <         18446744073709551615 same tally ; c
0 18446744073709551615 <              0 same tally
: c  0 18446744073709551615 <         0 same tally ; c
4294967296 4294967295 >               18446744073709551615 same tally
: c  4294967296 4294967295 >          18446744073709551615 same tally ; c
4294967295 4294967296 >               0 same tally
: c  4294967295 4294967296 >          0 same tally ; c
0 18446744073709551615 >              18446744073709551615 same tally
: c  0 18446744073709551615 >         18446744073709551615 same tally ; c
4294967295 4294967296 <=              18446744073709551615 same tally
: c  4294967295 4294967296 <=         18446744073709551615 same tally ; c
4294967296 4294967295 <=              0 same tally
: c  4294967296 4294967295 <=         0 same tally ; c
4294967296 4294967296 <=              18446744073709551615 same tally
: c  4294967296 4294967296 <=         18446744073709551615 same tally ; c
4294967296 4294967295 >=              18446744073709551615 same tally
: c  4294967296 4294967295 >=         18446744073709551615 same tally ; c
4294967295 4294967296 >=              0 same tally
: c  4294967295 4294967296 >=         0 same tally ; c
4294967296 4294967296 >=              18446744073709551615 same tally
: c  4294967296 4294967296 >=         18446744073709551615 same tally ; c
2147483648 0<                         0 same tally
: c  2147483648 0<                    0 same tally ; c
9223372036854775808 0<                18446744073709551615 same tally
: c  9223372036854775808 0<           18446744073709551615 same tally ; c
18446744073709551615 0<               18446744073709551615 same tally
: c  18446744073709551615 0<          18446744073709551615 same tally ; c

\ ----- and or nand: both halves -----
18446744073709551615 4294967296 and   4294967296 same tally
: c  18446744073709551615 4294967296 and        4294967296 same tally ; c
4294967296 18446744073709551615 and   4294967296 same tally
: c  4294967296 18446744073709551615 and        4294967296 same tally ; c
4294967296 1 or                       4294967297 same tally
: c  4294967296 1 or                  4294967297 same tally ; c
4294967296 4294967296 nand            18446744069414584319 same tally
: c  4294967296 4294967296 nand       18446744069414584319 same tally ; c

\ ----- dup drop swap over: whole cells move -----
4294967296 dup                        4294967296 same tally  4294967296 same tally
: c  4294967296 dup                   4294967296 same tally  4294967296 same tally ; c
1 4294967296 drop                     1 same tally
: c  1 4294967296 drop                1 same tally ; c
4294967296 8589934592 swap            4294967296 same tally  8589934592 same tally
: c  4294967296 8589934592 swap       4294967296 same tally  8589934592 same tally ; c
4294967296 1 over                     4294967296 same tally  1 same tally  4294967296 same tally
: c  4294967296 1 over                4294967296 same tally  1 same tally  4294967296 same tally ; c

\ ----- @ ! c@ c! +! -!: eight bytes, low half first; c! writes one -----
variable cell
1311768467463790320 cell !  cell @    1311768467463790320 same tally
: c  0 cell !  1311768467463790320 cell !  cell @  1311768467463790320 same tally ; c
cell c@  240 same tally   cell 4 + c@  120 same tally   cell 7 + c@  18 same tally
: c  cell c@  240 same tally   cell 4 + c@  120 same tally   cell 7 + c@  18 same tally ; c
18446744073709551615 cell !  0 cell 4 + c!  cell @    18446742978492891135 same tally
: c  18446744073709551615 cell !  0 cell 4 + c!  cell @  18446742978492891135 same tally ; c
\ ! and c! leave the cell under their two operands as it was
1311768467463790320 7 cell !          305419896 4294967296 * 2596069104 + same tally
: c  1311768467463790320 7 cell !     305419896 4294967296 * 2596069104 + same tally ; c
1311768467463790320 7 cell c!         305419896 4294967296 * 2596069104 + same tally
: c  1311768467463790320 7 cell c!    305419896 4294967296 * 2596069104 + same tally ; c
4294967295 cell !  1 cell +!  cell @  4294967296 same tally
: c  4294967295 cell !  1 cell +!  cell @  4294967296 same tally ; c
4294967296 cell !  1 cell -!  cell @  4294967295 same tally
: c  4294967296 cell !  1 cell -!  cell @  4294967295 same tally ; c

\ ----- >r r@ r>: whole cells on the return stack -----
8589934593 >r r@ r> +                 17179869186 same tally
: c  8589934593 >r r@ r> +            17179869186 same tally ; c

\ ----- literals and constants: the value 0x12345678 * 2^32 + 0x9ABCDEF0 -----
1311768467463790320                   305419896 4294967296 * 2596069104 + same tally
: c  1311768467463790320              305419896 4294967296 * 2596069104 + same tally ; c
1311768467463790320 constant every-byte
every-byte                            305419896 4294967296 * 2596069104 + same tally
: c  every-byte                       305419896 4294967296 * 2596069104 + same tally ; c

\ ----- if, while, until,: a flag is true when only its high half is set -----
\ Each loop ends either way, so a wrong answer is a failed case, not a hang.
: c  4294967296 if, 1 else, 0 then,                     1 same tally ; c
: c  4294967296 begin, dup while, drop 0 repeat,        0 same tally ; c
: c  0 begin, 1+ dup 3 = 4294967296 or until,           1 same tally ; c

\ ----- digit? alpha-lower? alpha-upper?: the whole cell is in range -----
\ 2^32 + 48 has the low half of the digit 0, and is not a digit.
48 digit?                             18446744073709551615 same tally
57 digit?                             18446744073709551615 same tally
47 digit?                             0 same tally
58 digit?                             0 same tally
4294967344 digit?                     0 same tally
97 alpha-lower?                       18446744073709551615 same tally
4294967393 alpha-lower?               0 same tally
65 alpha-upper?                       18446744073709551615 same tally
4294967361 alpha-upper?               0 same tally
: c  4294967344 digit?  0 same tally  4294967393 alpha-lower?  0 same tally ; c

\ ----- the value the first line left -----
305419896 4294967296 * 2596069104 +   same tally

create done-line  s, high-halves: bl c, s, done nl c,
1 done-line 18 write drop
failures @ die
