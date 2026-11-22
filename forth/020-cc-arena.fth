\ forth/020-cc-arena.fth — the compiler's ground floor on the i386
\ seed: the lexer's state block, how the compiler fails (cc-die,
\ cc-check-cap), and a bump allocator for variable-size data (struct
\ descriptors, call/goto fixup lists, switch-case lists — anything that
\ doesn't fit a fixed slot in a parallel array).  Most compiler state lives
\ in fixed-size buffers (parallel arrays declared with `create NAME N
\ allot`); this arena handles the rest.
\
\ forth/CONTRACT.md specifies this file.  Its machine code is i386
\ instructions on cells that are register pairs.  native!, which puts
\ that code in place of the library's definitions, is in
\ forth/010-lib.fth, which needs it first.  key is not buffered here:
\ the library reads files by name, one byte a call.  And * and / stay
\ calls to the seed's words, which do the 64-bit work in 32-bit steps.
\
\ Depends on forth/010-lib.fth: constant, variable, create, allot, s,,
\ char, [lit], if,/then,, begin,/until,, swap, dup, over, nip, drop, >r, r>,
\ +, -, /, *, >, !, @, c!, c,, write, die, native!, brk-alloc.

\ ----- The compiler's arithmetic in machine code -----
\ 010-lib.fth builds - from nand and +, and the sign test 0< from the
\ unsigned / (a 64-bit divide per comparison).  The compiler runs them
\ hundreds of millions of times, so here they become x86 code with the
\ same answers: < is still (a - b)'s sign bit, wrapping as before.  Each
\ native word gets a fresh header (code:), and native! turns the first
\ definition into a jump to it, so every word compiled earlier, in
\ 010-lib.fth too, runs the new code.  TOS is in edx:eax, eax the low half,
\ and the data stack grows down from esi, as in the seed's +: [esi] and
\ [esi+4] are the halves of the second item.  ebx, ecx, edi and ebp are
\ free.  Every sum and difference carries from the low half into the high.
: code:  : 0 state ! ;                   \ header only; c, lays the body
variable code-start
: push-tos,                              \ what dup lays: room, then TOS under it
  c{ 83 ee 08 }                                             \ sub esi, 8
  c{ 89 06 }                                                \ mov [esi], eax
  c{ 89 56 04 } ;                                           \ mov [esi+4], edx
: pop-tos,                               \ what drop lays: the second item is TOS
  c{ 8b 06 }                                                \ mov eax, [esi]
  c{ 8b 56 04 }                                             \ mov edx, [esi+4]
  c{ 83 c6 08 } ;                                           \ add esi, 8
: pop-sub,                               \ ebx:ecx = a - b; both leave the stack
  c{ 8b 0e }                                                \ mov ecx, [esi]
  c{ 8b 5e 04 }                                             \ mov ebx, [esi+4]
  c{ 29 c1 }                                                \ sub ecx, eax
  c{ 19 d3 }                                                \ sbb ebx, edx
  c{ 83 c6 08 } ;                                           \ add esi, 8
: pop-xor,                               \ TOS = a xor b: 0 when they are equal
  c{ 33 06 }                                                \ xor eax, [esi]
  c{ 33 56 04 }                                             \ xor edx, [esi+4]
  c{ 83 c6 08 } ;                                           \ add esi, 8
: 0=,                                    \ TOS = -1 if it was 0, else 0
  c{ 09 d0 }                                                \ or eax, edx
  c{ 83 f8 01 }                                             \ cmp eax, 1
  c{ 19 c0 }                                                \ sbb eax, eax
  c{ 89 c2 } ;                                              \ mov edx, eax
: sign-ebx,                              \ TOS = ebx's sign bit, 64 times
  c{ c1 fb 1f }                                             \ sar ebx, 31
  c{ 89 d8 }                                                \ mov eax, ebx
  c{ 89 da } ;                                              \ mov edx, ebx
: sign-edx,                              \ TOS = its own sign bit, 64 times
  c{ c1 fa 1f }                                             \ sar edx, 31
  c{ 89 d0 } ;                                              \ mov eax, edx
: not,                                   \ TOS = its complement
  c{ f7 d0 }                                                \ not eax
  c{ f7 d2 } ;                                              \ not edx
: -,                                     \ ( a b -- a-b )
  pop-sub,
  c{ 89 c8 }                                                \ mov eax, ecx
  c{ 89 da } ;                                              \ mov edx, ebx
: 1+,
  c{ 83 c0 01 }                                             \ add eax, 1
  c{ 83 d2 00 } ;                                           \ adc edx, 0
: 1-,
  c{ 83 e8 01 }                                             \ sub eax, 1
  c{ 83 da 00 } ;                                           \ sbb edx, 0
' - code: -  here code-start !            \ ( a b -- a-b )
  -, ret,
  code-start @ native!
' 0< code: 0<  here code-start !          \ ( n -- f )
  sign-edx, ret,
  code-start @ native!
' < code: <  here code-start !            \ ( a b -- f )  sign of a - b
  pop-sub, sign-ebx, ret,
  code-start @ native!
' = code: =  here code-start !            \ ( a b -- f )  a xor b = 0
  pop-xor, 0=, ret,
  code-start @ native!
' 1+ code: 1+  here code-start !
  1+, ret,
  code-start @ native!
' 1- code: 1-  here code-start !
  1-, ret,
  code-start @ native!

\ ----- A light optimizing compile -----
\ The seed compiles every word as a CALL, and 010-lib.fth's branches are
\ CALLs to branch or 0branch, which take their own return address off the
\ return stack and put another back, so the processor mispredicts the
\ return each time.  From here on the control-flow words lay test and jump
\ instructions, and the commonest primitives are copied in place of the
\ CALL.  (Literals are an inline push already: 010-lib.fth's
\ compile-literal.)  Each new word acts only while compiling (state @); run from
\ the interpreter it does what the old one did.  Words already compiled,
\ 010-lib.fth's included, keep their CALLs.
\ Branches: if, while, and until, pop the flag and jz rel32; else, repeat,
\ and again, jmp rel32.  A forward fixup is the address of the rel32 field.
: rel32!  ( target fixup -- )
  dup 4 + rot swap -  swap
  here >r  here-addr ! ,4  r> here-addr ! ;
: flag-test,                             \ pop the flag; ZF = it was 0
  c{ 09 d0 }                                                \ or eax, edx
  c{ 8b 06 }                                                \ mov eax, [esi]
  c{ 8b 56 04 }                                             \ mov edx, [esi+4]
  c{ 8d 76 08 } ;                                           \ lea esi, [esi+8]  (an add would change ZF)
: jz-fwd,    flag-test,
  c{ 0f 84 } here 0 ,4 ;                                    \ jz rel32
: jmp-fwd,
  c{ e9 } here 0 ,4 ;                                       \ jmp rel32
: jz-back,   flag-test,
  c{ 0f 84 } here 4 + - ,4 ;                                \ jz rel32
: jmp-back,
  c{ e9 } here 4 + - ,4 ;                                   \ jmp rel32
: if,      jz-fwd, ;                        immediate
: then,    here swap rel32! ;               immediate
: else,    jmp-fwd, swap here swap rel32! ; immediate
: begin,   here ;                           immediate
: while,   jz-fwd, ;                        immediate
: repeat,  swap jmp-back, here swap rel32! ; immediate
: until,   jz-back, ;                       immediate
: again,   jmp-back, ;                      immediate
\ Primitives copied in place of the CALL: the seed's bodies without their
\ ret, with the return-stack words' own return address left out.
\ A word can see its own name while it is being defined, so the new @ must
\ not read state with @: compiling? was compiled with the seed's.
: compiling?  state @ ;
' dup constant seed-dup     : dup   compiling? if, push-tos, else, seed-dup execute then, ; immediate
' drop constant seed-drop   : drop  compiling? if, pop-tos, else, seed-drop execute then, ; immediate
' swap constant seed-swap
: swap  compiling? if,
    c{ 87 06 }                                              \ xchg eax, [esi]
    c{ 87 56 04 }                                           \ xchg edx, [esi+4]
  else, seed-swap execute then, ; immediate
: over,
  push-tos,
  c{ 8b 46 08 }                                             \ mov eax, [esi+8]
  c{ 8b 56 0c } ;                                           \ mov edx, [esi+12]
' over constant seed-over
: over  compiling? if, over, else, seed-over execute then, ; immediate
' @ constant seed-fetch
: @  compiling? if,
    c{ 8b 50 04 }                                           \ mov edx, [eax+4]  (first: eax is the address)
    c{ 8b 00 }                                              \ mov eax, [eax]
  else, seed-fetch execute then, ; immediate
' c@ constant seed-cfetch
: c@  compiling? if,
    c{ 0f b6 00 }                                           \ movzx eax, byte [eax]
    c{ 31 d2 }                                              \ xor edx, edx
  else, seed-cfetch execute then, ; immediate
: drop-2,                                \ the third item becomes TOS
  c{ 8b 46 08 }                                             \ mov eax, [esi+8]
  c{ 8b 56 0c }                                             \ mov edx, [esi+12]
  c{ 83 c6 10 } ;                                           \ add esi, 16
' ! constant seed-store
: !  compiling? if,
    c{ 8b 0e }                                              \ mov ecx, [esi]
    c{ 89 08 }                                              \ mov [eax], ecx
    c{ 8b 4e 04 }                                           \ mov ecx, [esi+4]
    c{ 89 48 04 }                                           \ mov [eax+4], ecx
    drop-2,
  else, seed-store execute then, ; immediate
' c! constant seed-cstore
: c!  compiling? if,
    c{ 8b 0e }                                              \ mov ecx, [esi]
    c{ 88 08 }                                              \ mov [eax], cl
    drop-2,
  else, seed-cstore execute then, ; immediate
' + constant seed-plus
: +  compiling? if,
    c{ 03 06 }                                              \ add eax, [esi]
    c{ 13 56 04 }                                           \ adc edx, [esi+4]
    c{ 83 c6 08 }                                           \ add esi, 8
  else, seed-plus execute then, ; immediate
' - constant native-minus
: -  compiling? if, -, else, native-minus execute then, ; immediate
' 1+ constant native-1+
: 1+  compiling? if, 1+, else, native-1+ execute then, ; immediate
' 1- constant native-1-
: 1-  compiling? if, 1-, else, native-1- execute then, ; immediate
\ The return stack is the x86 stack and holds cells too, the low half
\ nearest esp, so inline >r, r> and r@ are two pushes, two pops and two
\ loads from [esp].  Interpreted, they must not add a call frame of their
\ own, so they end in a jump to the word they replace (jmp-xt,): the
\ seed's >r and r>, the library's r@.
: jmp-xt,  ( xt -- )
  c{ e9 } here 4 + - ,4 ;                                   \ jmp rel32
' >r constant seed->r
' r> constant seed-r>
' r@ constant seed-r@
: jmp-seed->r,  seed->r jmp-xt, ; immediate
: jmp-seed-r>,  seed-r> jmp-xt, ; immediate
: jmp-seed-r@,  seed-r@ jmp-xt, ; immediate
: >r  compiling? if,
    c{ 52 }                                                 \ push edx
    c{ 50 }                                                 \ push eax
    pop-tos, exit, then, jmp-seed->r, ; immediate
: r>  compiling? if, push-tos,
    c{ 58 }                                                 \ pop eax
    c{ 5a }                                                 \ pop edx
    exit, then, jmp-seed-r>, ; immediate
: r@  compiling? if, push-tos,
    c{ 8b 04 24 }                                           \ mov eax, [esp]
    c{ 8b 54 24 04 }                                        \ mov edx, [esp+4]
    exit, then, jmp-seed-r@, ; immediate

\ More primitives copied in: 0=, nand, and, or.  * and / are not: they
\ stay calls to the seed's words.
' 0= constant seed-0=
: 0=  compiling? if, 0=, else, seed-0= execute then, ; immediate
: and,
  c{ 23 06 }                                                \ and eax, [esi]
  c{ 23 56 04 }                                             \ and edx, [esi+4]
  c{ 83 c6 08 } ;                                           \ add esi, 8
: or,
  c{ 0b 06 }                                                \ or eax, [esi]
  c{ 0b 56 04 }                                             \ or edx, [esi+4]
  c{ 83 c6 08 } ;                                           \ add esi, 8
' nand constant seed-nand
: nand  compiling? if, and, not, else, seed-nand execute then, ; immediate
' and code: and  here code-start !  and, ret,  code-start @ native!
' and constant native-and
: and  compiling? if, and, else, native-and execute then, ; immediate
' or code: or  here code-start !  or, ret,  code-start @ native!
' or constant native-or
: or  compiling? if, or, else, native-or execute then, ; immediate
\ 010-lib.fth's character tests subtract and divide; as x86 they are an
\ unsigned compare of the whole cell.  After the subtraction, cmp borrows
\ when the low half is below count, and the sbb after it borrows again
\ only when the high half is 0: carry is then set exactly when the cell is
\ below count.
: in-range,  ( low count -- )
  c{ 83 e8 } swap c,                                        \ sub eax, imm8  (low)
  c{ 83 da 00 }                                             \ sbb edx, 0
  c{ 83 f8 } c,                                             \ cmp eax, imm8  (count)
  c{ 83 da 00 }                                             \ sbb edx, 0
  c{ 19 c0 }                                                \ sbb eax, eax
  c{ 89 c2 }                                                \ mov edx, eax
  ret, ;
' digit? code: digit?  here code-start !  48 10 in-range,  code-start @ native!
' alpha-lower? code: alpha-lower?  here code-start !  97 26 in-range,  code-start @ native!
' alpha-upper? code: alpha-upper?  here code-start !  65 26 in-range,  code-start @ native!
\ The rest of 010-lib.fth's hot words, compiled again from the same text
\ so the copies above take effect, and the old bodies sent to the new ones.
\ over's old body is seed-over: ' over would find the immediate over above.
seed-over code: over  here code-start !
  over, ret,  code-start @ native!
' over constant native-over
: over  compiling? if, over, else, native-over execute then, ; immediate
' alpha? : alpha?  dup alpha-lower? swap alpha-upper? or ;  ' alpha? native!
' space? : space?  dup 32 - 0= over 9 - 0= or
          over 10 - 0= or  swap 13 - 0= or ;  ' space? native!
' true : true  0 0= ;  ' true native!
' <> : <>  = 0= ;  ' <> native!
' > : >   swap < ;  ' > native!
' <= : <=  > 0= ;  ' <= native!
' >= : >=  < 0= ;  ' >= native!
' nip : nip   swap drop ;  ' nip native!
' rot : rot   >r swap r> swap ;  ' rot native!
' 2dup : 2dup  over over ;  ' 2dup native!
' 2drop : 2drop drop drop ;  ' 2drop native!
' +! : +!  swap over @ + swap ! ;  ' +! native!
' -! : -!  swap over @ swap - swap ! ;  ' -! native!
' bytes-eq : bytes-eq
  begin,
    dup 0 >
  while,
    >r
    over c@ over c@ <> if,
      r> drop 2drop 0 exit,
    then,
    1+ swap 1+ swap
    r> 1-
  repeat,
  drop 2drop true ;  ' bytes-eq native!

\ Comparisons copied in place (same answers as 010-lib.fth's).
' = constant native-=
: =   compiling? if, pop-xor, 0=, else, native-= execute then, ; immediate
' <> constant forth-<>
: <>  compiling? if, pop-xor,
    c{ 09 d0 }                                              \ or eax, edx
    c{ f7 d8 }                                              \ neg eax  (carry unless it was 0)
    c{ 19 c0 }                                              \ sbb eax, eax
    c{ 89 c2 }                                              \ mov edx, eax
  else, forth-<> execute then, ; immediate
' < constant native-<
: <   compiling? if, pop-sub, sign-ebx, else, native-< execute then, ; immediate
' >= constant forth->=
: >=  compiling? if, pop-sub, sign-ebx, not, else, forth->= execute then, ; immediate
: pop-rsub,                              \ TOS = b - a
  c{ 2b 06 }                                                \ sub eax, [esi]
  c{ 1b 56 04 }                                             \ sbb edx, [esi+4]
  c{ 83 c6 08 } ;                                           \ add esi, 8
' > constant forth->
: >   compiling? if, pop-rsub, sign-edx, else, forth-> execute then, ; immediate
' <= constant forth-<=
: <=  compiling? if, pop-rsub, sign-edx, not, else, forth-<= execute then, ; immediate
' 0< constant native-0<
: 0<  compiling? if, sign-edx, else, native-0< execute then, ; immediate
\ Constants and variables: a word made by constant, create or variable from
\ here on is immediate.  Compiling, it lays an inline push of its value
\ rather than a CALL; interpreted, it pushes the value as before.  Its body
\ is the 18-byte push, a 7-byte call to push-or-compile, then ret (28 bytes).
: push-or-compile  ( v -- v | )  compiling? if, push-imm64, then, ;
' push-or-compile constant poc-xt
: constant  : push-imm64, poc-xt call, ret, 0 state ! immediate ;
: create  : here 28 + push-imm64, poc-xt call, ret, 0 state ! immediate ;
: variable  create 0 , ;

\ The seed's find walks every header from LATEST, and about a third of each
\ run went there while the compiler's own source was read.  fh-find answers
\ the same (the newest entry of that name, its header left in LAST_FOUND)
\ from a hash table it brings up to date first: headers are only ever added
\ at LATEST, so the ones newer than the last indexed are new.  Nodes
\ { next, header } live in 2 MiB above the break, after 4096 buckets.
variable fh-buckets
variable fh-pool
variable fh-pos
variable fh-latest
variable fh-a
variable fh-u
2097152 brk-alloc
dup fh-buckets !  32768 + fh-pool !
: fh-hash  ( a u -- bucket )
  5381 >r
  begin, dup while,
    over c@ r> 33 * + >r
    1- swap 1+ swap
  repeat, 2drop
  r> 4095 and ;
: fh-insert  ( header -- )
  dup 10 + over 9 + c@ fh-hash 8 * fh-buckets @ +
  fh-pool @ fh-pos @ +
  over @ over !
  rot over 8 + !
  swap !
  16 fh-pos +! ;
: fh-index  ( header -- )  \ every header newer than fh-latest, oldest first
  dup fh-latest @ = over 0= or if, drop exit, then,
  dup @ fh-index fh-insert ;
: fh-find  ( c-addr u -- xt | 0 )
  fh-u ! fh-a !
  latest @ fh-latest @ <> if, latest @ fh-index  latest @ fh-latest ! then,
  fh-a @ fh-u @ fh-hash 8 * fh-buckets @ + @
  begin, dup while,
    dup 8 + @
    dup 9 + c@ fh-u @ = if,
      dup 10 + fh-a @ fh-u @ bytes-eq if,
        nip dup latest 16 + !                          \ LAST_FOUND
        10 + fh-u @ + exit,
      then,
    then,
    drop @
  repeat, ;
' find ' fh-find native!

\ ----- The lexer's state: one block -----
\ Everything the source reader (030) and the lexer (050) change as they move
\ through the program lives in this one 8-cell block, so a parser that wants
\ to look ahead can copy the block away and later copy it back
\ (cc-lex-mark / cc-lex-reset, 050).  Each name below is the address of its
\ cell, used exactly like a variable.  The block comes first because cc-die
\ reports the current line from it.
64 constant cc-lex-state-size
create cc-lex-state  cc-lex-state-size allot
cc-lex-state             constant cc-src-pos     \ reader: offset of the next byte
cc-lex-state 8 +  constant cc-src-line           \ reader: 1-based line number
cc-lex-state 16 +  constant tok-kind             \ lexer: tk-* of the current token
cc-lex-state 24 +  constant tok-num              \ lexer: number / char / punct code
cc-lex-state 32 +  constant tok-str-addr         \ lexer: identifier or string bytes
cc-lex-state 40 +  constant tok-str-len          \ lexer: ... and their length
cc-lex-state 48 +  constant tok-kw-id            \ lexer: kw-* when tok-kind = tk-kw
cc-lex-state 56 +  constant cc-tok-pending       \ lexer: -1 = current token put back

\ ----- Failing: cc-die -----
\ cc-err-write ( a u -- )  Write u bytes at a to stderr (fd 2).
: cc-err-write  >r >r 2 r> r> write drop ;

\ cc-err-dec ( u -- )  Write u in decimal to stderr.  Digits come out lowest
\ first, so they fill cc-err-digits from its end backwards.
create cc-err-digits  20 allot                   \ 2^64 has 20 digits
: cc-err-dec
  cc-err-digits 20 +                       ( u p )
  begin,
    1-  over 10 / 10 * >r  over r> - ( u p digit )
    [char] 0 +  over c!                          ( u p )
    swap 10 / swap                         ( u/10 p )
    over 0=
  until,
  nip  cc-err-digits 20 + over -  cc-err-write ;

create cc-die-where  s, cc: bl c, s, line bl c,       \ "cc: line "  9 bytes
create cc-die-what   char : c, bl c, s, error bl c,   \ ": error "   8 bytes
create cc-die-end    nl c,                            \ "\n"         1 byte

\ cc-die ( code -- )  Every compiler failure ends here: write
\ "cc: line N: error CODE" to stderr and exit with status CODE.  N is the
\ reader's line in the preprocessed source, where #include'd files are
\ already spliced in (Appendix G).
: cc-die
  cc-die-where 9 cc-err-write
  cc-src-line @ cc-err-dec
  cc-die-what 8 cc-err-write
  dup cc-err-dec
  cc-die-end 1 cc-err-write
  die ;

\ cc-check-cap ( n cap code -- )  Die with code unless n <= cap.  n is how
\ full a buffer or table will be once the write about to happen is done.
: cc-check-cap
  >r > if, r> cc-die then,
  r> drop ;

\ ----- Storage -----
\ The buffer lives in the dictionary alongside the cc-arena-base header (it's
\ what `create` builds: a header + data area; allot extends the data area).
\ Sized to fit within the seed's mapped segment with room for the compiler
\ dictionary, struct descriptors, labels, and string overflow.
32768 constant cc-arena-cap
create cc-arena-base  cc-arena-cap allot
variable cc-arena-ptr
\ Initialize the bump pointer to the base of the buffer.
cc-arena-base cc-arena-ptr !
variable cc-arena-start
variable cc-arena-limit
cc-arena-base cc-arena-start !
cc-arena-cap cc-arena-limit !
\ Opt-in workspace for larger translation units; the seed itself is unchanged.
: cc-arena-map ( bytes -- )
  dup cc-arena-limit !
  brk-alloc
  dup 0= if, [lit] 10 cc-die then,
  dup cc-arena-start ! cc-arena-ptr ! ;

\ ----- cc-alloc -----
\ cc-alloc ( n -- addr )  Bump n bytes (rounded up to an 8-byte boundary)
\ off the arena and return the start address of the allocation.  On exhaustion
\ the compiler dies with code 10.
\
\ Stack trace:
\   ( n )
\   align up to 8:  (n+7)/8*8
\   ( n' )
\   cc-arena-ptr @ swap over +     ( old-top new-top )
\   dup cc-arena-start @ -         ( old-top new-top used )
\   cc-arena-limit @ 10 cc-check-cap  ( old-top new-top )
\   cc-arena-ptr !                 ( old-top )
: cc-alloc                                       ( n -- addr )
  7 + 8 / 8 *                                    \ align up to 8 bytes
  cc-arena-ptr @ swap over +                     ( old-top new-top )
  dup cc-arena-start @ -  cc-arena-limit @ [lit] 10 cc-check-cap
  cc-arena-ptr ! ;                               ( -- old-top )
