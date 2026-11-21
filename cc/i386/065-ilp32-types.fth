\ 065-ilp32-types.fth — the ILP32 data model for the i386 back end.
\
\ Loaded after 060-cc-types.fth and before every layer that asks a type its
\ size.  060's ty-size answers for LP64: long and pointers are 8 bytes.  On
\ i386 they are 4, as int is; long long stays 8.  Nothing else in the type
\ model changes, because every other size, struct layout, sizeof and
\ pointer step in the compiler comes from ty-size and ty-align.
\
\ A word defined here shadows 060's for the layers loaded after this file.
\ Nothing in 060 itself calls ty-size apart from ty-align, redefined below.

\ ty-size ( ty -- bytes )  060's answer, except 4 for a pointer, long and
\ unsigned long.
' ty-size constant ty-size-lp64
: ty-size
  dup ty-ptr if, drop [lit] 4 exit, then,
  dup ty-base dup ty-long = swap ty-ulong = or if, drop [lit] 4 exit, then,
  ty-size-lp64 execute ;

\ ty-align ( ty -- bytes )  The i386 System V alignment inside a struct:
\ the size, but never more than 4, so long long and double sit on 4-byte
\ boundaries.  void uses 1, as in 060.
: ty-align
  ty-size
  dup 0= if, drop [lit] 1 then,
  dup [lit] 4 > if, drop [lit] 4 then, ;

\ cc-integer-literal-type ( -- ty )  Type of the current tk-num token under
\ ILP32 (C99 6.4.4.1).  int and long both hold 31 bits, their unsigned kinds
\ 32, and the long long kinds take what is wider:
\   bit 63 set                        unsigned long long
\   an LL suffix, or 2^32 and above   long long, unsigned with a U
\   a U suffix                        unsigned int, unsigned long with an L
\   below 2^31                        int, long with an L
\   2^31 to 2^32-1, decimal           long long
\   2^31 to 2^32-1, hex or octal      unsigned int, unsigned long with an L
\ A leading 0 marks hex and octal, as in 060.
: cc-integer-literal-type
  cc-integer-literal-check
  tok-num @ 2^63 / if, ty-ullong [lit] 0 ty-make exit, then,
  cc-literal-long @ [lit] 1 > tok-num @ [lit] 4294967296 / or if,
    cc-literal-unsigned @ if, ty-ullong else, ty-llong then,
    [lit] 0 ty-make exit,
  then,
  cc-literal-unsigned @ 0= if,
    tok-num @ [lit] 2147483648 / 0= if,
      cc-literal-long @ if, ty-long else, ty-int then,
      [lit] 0 ty-make exit,
    then,
    tok-str-addr @ c@ [char] 0 <> if,
      ty-llong [lit] 0 ty-make exit,
    then,
  then,
  cc-literal-long @ if, ty-ulong else, ty-uint then,
  [lit] 0 ty-make ;
