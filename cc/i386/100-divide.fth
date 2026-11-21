\ 100-divide.fth — division of 8-byte types on i386.
\
\ Loaded after 100-cc-expr.fth.  cc/i386/090-emit.fth divides the low
\ halves of its register pairs, which is the whole value for every type of
\ 4 bytes or less.  For an 8-byte common type that would be a wrong
\ answer, and there is no 64-bit division here to give the right one:
\
\   long long   the compile stops with error 131.
\   a double    native mode keeps it as its bit pattern and has no
\               arithmetic on it; the x86-64 back end divides the patterns
\               as integers.  tcc's constant folding has such divisions,
\               in code the route never runs.  Here the program is
\               compiled, and exits with status 125 if it ever gets there
\               (tinycc/mes-libc-native-i386.c's convention for missing
\               floating point).
\
\ Every / and %, and /= and %=, reaches its encoder through
\ cc-native-binop-emit, with the common type in cc-expr-common.

: cc-emit-exit-125
  x{ b8 } [lit] 1 cc-emit-4le                     \ mov eax, 1  (exit)
  x{ bb } [lit] 125 cc-emit-4le                   \ mov ebx, 125
  x{ cd 80 } ;                                    \ int 0x80

: cc-i386-binop-emit
  cc-expr-common @ ty-size [lit] 8 = if,
    cc-expr-op-row @ bo-op + @
    dup [char] / = swap [char] % = or if,
      cc-expr-common @ ty-long-long? if, [lit] 131 cc-die then,
      cc-emit-exit-125 exit,
    then,
  then,
  cc-native-binop-emit-default ;
' cc-i386-binop-emit is cc-native-binop-emit
