\ forth/i386/115-nzero.fth — cc-nzero for the i386 seed.
\
\ Loaded after cc/115-cc-native.fth, whose cc-nzero is five lines of
\ x86-64 machine code (rep stosb) that this host cannot run.  115 itself
\ calls it twice, so a new definition alone would not reach those calls:
\ native! sends the old word here.  Its callers zero 24 to 2,600 bytes at
\ a time, which a loop in Forth does soon enough.

\ cc-nzero ( a n -- )  Zero n bytes at a.
' cc-nzero
: cc-nzero
  begin, dup while,
    over [lit] 0 swap c!
    1- swap 1+ swap
  repeat,
  2drop ;
' cc-nzero native!
