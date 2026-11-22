\ tests/forth/high-halves-judge.fth -- the judge for high-halves.fth.
\
\ Loaded after the library and BEFORE 020-cc-arena.fth, on purpose.  The
\ cases test what 020 lays down, so what judges them must not be made of
\ it.  At this point a definition is compiled as calls, and the five words
\ used below (dup nand + 0= and the @ ! of tally) are the seed's own, which
\ 020 never redirects: it replaces them for definitions that come after
\ it.  So these two words stay calls to the seed, whose own tests cover
\ its arithmetic on both halves of a cell (seed/SPEC.md, 13.1).

\ same ( a b -- f )  true if a and b are equal in all 64 bits:
\ a + (~b + 1) = 0.
: same  dup nand 1 + + 0= ;

\ tally ( f -- )  count a case whose answer was not what it expected.
variable failures
: tally  0= 1 nand dup nand  failures @ +  failures ! ;
