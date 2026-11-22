\ forth/010-lib.fth — the Forth library on the i386 seed, built on its
\ 21 machine-code words:
\   dup drop swap >r r>   @ ! c@ c!   + nand 0= * /
\   key token find   syscall6   state : ;
\ Loaded before any Forth-level vocabulary.
\
\ The seed is a program for a processor in 32-bit mode whose cells are
\ 8 bytes (seed/SPEC.md); forth/CONTRACT.md specifies this file.  The top
\ of the data stack is the register pair edx:eax (eax the low half), esi
\ is the data-stack pointer, and a call pushes a zero before its return
\ address, so that a return address is a cell as well.  The last section
\ gets memory from brk and reads input from files named on the command
\ line.
\
\ Conventions:
\   - Up to the outer interpreter (interpret, further down) this file is
\     read by the seed's own loop (seed/000-seed.hex0).  It knows
\     words and unsigned decimal numbers, and \ comments; nothing else.
\     So there are no ( ) comments, negative or hex numbers above the
\     hand-over.  Characters use char / [char], so no ASCII code needs a
\     comment to explain it.
\   - No seed address is typed in: the sysvar cells are found from the
\     seed's state word, and its words' xts with ' (tick).

\ ===== Words the seed leaves to the library =====
\ Each of these was machine code in an earlier seed and needs none.

\ The seed's sysvars are consecutive 8-byte cells: STATE, LATEST, HERE,
\ LAST_FOUND, INPUT, ARGV.  state pushes the address of the first; the
\ others follow.  (input and argv are named in the last section.)
\ latest ( -- a )     the cell holding the newest dictionary header's address.
\ here-addr ( -- a )  the cell holding HERE, the first free byte.
: latest     state 8 + ;
: here-addr  state 16 + ;

\ here ( -- addr )  the value of HERE: where the next byte laid down goes.
: here  here-addr @ ;

\ , ( v -- )  store the 8-byte cell v at HERE and advance HERE past it.
: ,  here !  here 8 + here-addr ! ;

\ c, ( b -- )  store low byte of TOS at HERE and advance HERE by 1.
\ This is the workhorse for any code-emission vocabulary built in Forth.
: c,  here c!  here 1 + here-addr ! ;

\ execute ( xt -- )  run the word whose code starts at xt.  A colon word
\ is machine code that ends in ret 4, and the return stack is the x86 stack:
\ >r puts xt on it, and this word's own ret 4 then "returns" into xt.  When
\ xt's word returns, it returns to whoever called execute.
: execute  >r ;

\ r@ ( -- n ; R: n -- n )  copy the top of the caller's return stack.
\ Inside r@ the top of the return stack is r@'s own return address, so
\ that comes off first and goes back last.
: r@  r> r> dup >r swap >r ;

\ ' ( "name" -- xt | 0 )  read the next token and look it up.
: '  token find ;

\ ----- bool / bitwise helpers built on nand -----
\ All derived because nand is the only logical primitive in the seed.

\ and ( a b -- a&b ) = ~~(a&b) = nand of nand-of-itself
: and  nand dup nand ;

\ or  ( a b -- a|b ) via De Morgan: ~(~a & ~b)
: or   dup nand swap dup nand nand ;

\ over ( a b -- a b a )  copy second-from-top to top.
\ Standard Forth idiom, missing from our seed primitives.
: over  >r dup r> swap ;

\ - ( a b -- a-b )  subtract via 2's complement (we have + and nand).
\ Used by classifier helpers and the local rel32 CALL encoder below.
: -  dup nand 1 + + ;

\ 1+ ( n -- n+1 )   1- ( n -- n-1 )  Step by one: the commonest arithmetic
\ in the C compiler (pointers, counters, lengths), so it gets a name.
: 1+  1 + ;
: 1-  1 - ;

\ ===== Linux syscall wrappers (via syscall6 primitive) =====
\ syscall6 ( a b c d e f n -- eax )  loads a..f into ebx/ecx/edx/esi/edi/ebp
\ and n into eax, runs int 0x80 and answers eax sign-extended to a cell, so
\ a failure is negative.  We pad with zeros for unused argument slots.
\
\ Linux i386 syscall numbers, which builder-hex0 answers too:
\   exit=1  read=3  write=4  open=5  close=6  brk=45

\ write ( fd buf count -- n )        SYS_write=4
: write  0 0 0 4 syscall6 ;

\ die ( n -- )  Exit with status n via SYS_exit=1.
\ Used by the C compiler's error paths instead of inlining the full syscall.
: die  0 0 0 0 0 1 syscall6 ;

\ bye ( -- )  exit with status 0.
: bye  0 die ;

\ ===== Character classification helpers =====
\ All return -1 if true, 0 if false (Forth boolean convention).
\ Approach: just hard-code the literal byte values and use 0= equality chains.
\ (char / [char] come later, in the section on immediate words, so these
\ few spell their ASCII codes in decimal.)

\ digit? ( c -- flag )  true if c is in '0'..'9' (ASCII 48..57)
\ Approach: compute (c-48)/10.  If c<48 the subtract underflows to a huge
\ unsigned, /10 is huge, 0= is 0.  If c in 48..57, (c-48)/10 = 0, 0= is -1.
\ If c >= 58, (c-48)/10 >= 1, 0= is 0.  ✓
: digit?  48 - 10 / 0= ;

\ alpha-lower? ( c -- flag )  true if c is 'a'..'z' (97..122)
\ Same trick: (c-97)/26 = 0 iff c in 97..122.
: alpha-lower?  97 - 26 / 0= ;

\ alpha-upper? ( c -- flag )  true if c is 'A'..'Z' (65..90)
: alpha-upper?  65 - 26 / 0= ;

\ ===== Comparison operators =====
\ All return -1 (true) / 0 (false), Forth boolean convention.

\ true ( -- -1 )  the canonical true flag, all 64 bits set.  The decimal
\ literal parser is unsigned-only, so -1 cannot be written as a number;
\ `0 0=` manufactures it (0 is zero, so 0= answers -1).
: true  0 0= ;

\ = ( a b -- f )  -1 if a = b, else 0.  Equal iff (a - b) = 0.
: =   - 0= ;

\ <> ( a b -- f )  inverse of =.
: <>  = 0= ;

\ 2^63 ( -- 2^63 )  9223372036854775808 = 0x8000000000000000, the sign bit
\ of a 64-bit signed integer.  The literal round-trips through the seed's
\ number because it accumulates in an unsigned 64-bit register.
: 2^63  9223372036854775808 ;

\ 0< ( n -- f )  -1 if n is signed-negative (bit 63 set), else 0.
\ Strategy: the seed's `/` is unsigned (DIV instruction).  A value with
\ bit 63 set, divided by 2^63, yields exactly 1; any non-negative value
\ yields 0.  Then `0= 0=` canonicalises (1 -> -1, 0 -> 0).
: 0<  2^63 / 0= 0= ;

\ < ( a b -- f )  signed less-than: a < b iff (a - b) is negative.
\ Domain: exact only while a - b fits in 64 signed bits, i.e. when a and b
\ are less than 2^63 apart — always so for operands of the same sign, and
\ for every size, count, offset and character the compiler compares.
\ Outside it the subtraction wraps: MAX-INT -1 < answers -1 (true).
: <   - 0< ;

\ > ( a b -- f )  signed greater-than: b < a.  Same domain as <.
: >   swap < ;

\ ===== Stack shuffles =====
\ Standard Forth stack-manipulation words built on the seed primitives
\ swap, dup, drop, >r, r>, plus over (defined above).

\ nip ( a b -- b )  drop second-from-top.
: nip   swap drop ;

\ 2dup ( a b -- a b a b )  duplicate the top pair.
: 2dup  over over ;

\ 2drop ( a b -- )  drop the top pair.
: 2drop drop drop ;

\ ===== 4-byte little-endian writer =====
\ ,4 ( v -- )  emit low 4 bytes of v at HERE in LE order.
\ Used by call, (rel32) and any Forth-level code emitter that needs
\ compact little-endian immediates.
: ,4
  dup c,                       \ byte 0
  256 / dup c,           \ byte 1
  256 / dup c,           \ byte 2
  256 / c, ;             \ byte 3

\ ===== immediate flag toggle =====
\ immediate ( -- )  Set the IMMEDIATE bit in the flags byte of the most-recent
\ dict entry.  An immediate word executes at compile time even when STATE=1
\ (inside : ... ;).  Mirrors the manual `01` flags byte on `;` in 000-seed.hex0.
\
\ Layout reminder: a dict entry is  link(8) flags(1) name-len(1) name(N) body.
\ `latest` is a seed primitive — it pushes the address of the LATEST sysvar
\ cell; `latest @` fetches the current dict tail pointer; `+ 8` is the
\ flags-byte address.
: immediate  latest @ 8 + 1 swap c! ;

\ ===== the push body: constant (and create / variable, further below) =====
\ constant is defined early so branch-xt/0branch-xt can use it: the
\ control-flow combinators below need the xts of branch/0branch, and
\ hard-coding them as numeric literals would break every time
\ 000-seed.hex0's dictionary layout changes; instead, resolve them at load
\ time via `'` (tick), captured into a constant.
\
\ A word that pushes one value has a 21-byte runtime body:
\   83 EE 08             sub esi, 8       ; make data-stack room
\   89 06                mov [esi], eax   ; spill old TOS, low half
\   89 56 04             mov [esi+4], edx ; and high half
\   B8 <imm32>           mov eax, V's low half
\   BA <imm32>           mov edx, V's high half: the new TOS
\   C2 04 00             ret 4
\ constant, create and variable all lay it down; they differ only in V
\ and in what follows the ret.

\ ret, ( -- )  emit C2 04 00, `ret 4`: return, and drop the zero the call
\ pushed above the return address (call, below).
: ret,
  194 c, 4 c, 0 c, ;               \ C2 04 00  ret 4

\ push-imm64, ( v -- )  emit the 18 bytes that push v: the body minus ret.
: push-imm64,
  131 c, 238 c, 8 c,               \ 83 EE 08  sub esi, 8
  137 c, 6 c,                      \ 89 06  mov [esi], eax
  137 c, 86 c, 4 c,                \ 89 56 04  mov [esi+4], edx
  184 c, dup ,4                    \ B8  mov eax, imm32  (v's low half)
  256 / 256 / 256 / 256 /          \ shift right 32
  186 c, ,4 ;                      \ BA  mov edx, imm32  (v's high half)

\ push-body, ( v -- )  emit the whole 21-byte body of a word that pushes v.
: push-body,  push-imm64, ret, ;

\ constant ( v "name" -- )  define name as a word that pushes v.
\ `:` parses the name, builds the header and sets STATE=1; we emit the body
\ by hand and set STATE back to 0 (a `;` here would end constant itself).
: constant  : push-body, 0 state ! ;

\ ===== call, and character literals =====

\ call, ( target -- )  Emit a 7-byte call to absolute `target` at HERE:
\ push 0, then CALL rel32.  The zero is the high half of the return cell
\ and the CALL's return address its low half, so r> takes a whole cell;
\ ret, drops the zero again.  rel32 = target - (HERE + 7).  After
\ `232 c,` HERE points at the rel32's first byte and HERE+4 points just
\ past the CALL — so rel32 = target - (HERE_now + 4).
\ Kept here so [char] and the control-flow combinators do not need another
\ assembler layer.
: call,
  106 c, 0 c,            \ 6A 00  push 0
  232 c, here 4 + - ,4 ; \ E8  call rel32  (rel32 = target - (HERE+4))

\ char ( "tok" -- c )  read the next token and push its first byte.
: char  token drop c@ ;

\ Characters char cannot quote, or that would start a comment where a
\ later word quotes them.  The reader never makes a token of whitespace, a
\ token that is exactly \ starts a comment, and the outer interpreter
\ below takes one that is exactly ( as a comment too.
9 constant tab
10 constant nl
32 constant bl
40 constant lparen                    \ (
92 constant backslash

\ ===== Control-flow combinators =====
\ Compile-time helpers that emit calls to `branch` and `0branch`, plus
\ inline 8-byte target slots, structured per traditional
\ Forth idiom (begin/until/again/while/repeat/if/else/then).
\
\ branch and 0branch, defined below, work with inline 8-byte target cells:
\ the combinators emit a 7-byte call (call,) to one of them, followed
\ immediately by an 8-byte absolute target address.  The word called takes
\ its own return address (which points at the slot) off the return stack
\ and puts back the address to go on at: the slot's contents for a jump,
\ or the address after the slot to fall through.
\
\ The slot is thus "consumed" — it does NOT remain on the return stack.
\ backward branches simply emit the back-target cell; forward branches
\ reserve a slot, return its address as a fixup, and patch it later.
\
\ slot-layout for a forward branch (e.g. if, ... then,):
\     6A 00             ; push 0
\     E8 xx xx xx xx    ; CALL rel32 -> 0branch
\     <8-byte slot>     ; initially 0, patched by then, to target HERE
\
\ Names end in `,` per Forth-asm convention ("emits code") and to keep them
\ distinct from any plain runtime `if`/`then` words.
\
\ branch ( -- )  jump to the address in the cell that follows the CALL.
\ Called from compiled code, branch finds its own return address on top of
\ the return stack, and that is the cell's address: r> takes it, @ reads
\ the target, >r leaves the target as the address branch returns to.
: branch  r> @ >r ;

\ 0branch ( flag -- )  jump to the cell's target if flag = 0; otherwise go
\ on after the cell.  It has to choose between two return addresses with
\ no branch to choose with, so it does it by arithmetic.  With
\   past = cell + 8        where execution goes on if flag is not 0
\   mask = -1 if flag = 0, else 0        which is what 0= answers
\ the address to return to is  past + (mask and (target - past)).
: 0branch
  0=                    \ mask
  r> dup @              \ mask cell target
  swap 8 +              \ mask target past
  dup >r                \ mask target past     R: past
  - and                 \ mask and (target - past)
  r> + >r ;             \ R: past, or target when flag was 0

\ branch-xt / 0branch-xt — their xts, for the combinators to compile CALLs to.
' branch  constant branch-xt
' 0branch constant 0branch-xt

\ if, ( -- fixup )  At compile time: emit `CALL 0branch` + reserved 8-byte
\ target slot.  Returns the slot's address as a fixup for `then,` or `else,`.
\ Runtime semantics: pops a flag; if flag = 0, jumps to the patched target
\ (the matching `then,`/`else,`'s HERE).  If flag is non-zero, falls through.
: if,
  0branch-xt call,
  here                         \ slot address, returned as fixup
  0 ,                    \ reserve 8 bytes (` ,` emits a cell)
;
immediate

\ then, ( fixup -- )  Patch the fixup slot to current HERE so the matching
\ if,/while,/else, jumps here when its branch is taken.
: then,
  here swap ! ;
immediate

\ else, ( fixup-if -- fixup-else )  Emit unconditional `CALL branch` + slot
\ to leap over the else-arm; patch the if-fixup to land at the start of the
\ else-arm; return the new (else-arm-end) fixup for `then,` to patch.
: else,
  branch-xt call,
  here                         \ start of new (else-end) target slot
  0 ,                    \ reserve 8 bytes
  swap                         \ ( fixup-else fixup-if )
  here swap !                  \ patch fixup-if -> just past unconditional branch
;
immediate

\ begin, ( -- back-target )  Mark the top of a loop; just records HERE.
: begin,  here ;
immediate

\ while, ( back-target -- back-target fixup )  Test flag, exit loop if false.
\ Emits `CALL 0branch` + reserved slot; returns the slot addr as the loop-exit
\ fixup, leaving back-target underneath for repeat,.
: while,
  0branch-xt call,
  here 0 , ;
immediate

\ repeat, ( back-target fixup -- )  Emit unconditional jump back to begin-target;
\ patch the loop-exit fixup to land just past it.
: repeat,
  swap branch-xt call, ,       \ unconditional `CALL branch` + back-target cell
  here swap !                  \ patch loop-exit fixup -> just-past-repeat
;
immediate

\ again, ( back-target -- )  Jump back to begin, unconditionally: a loop
\ that only exit, can leave.
: again,
  branch-xt call, , ;          \ `CALL branch` + back-target cell
immediate

\ exit, ( -- )  Compile a `ret 4`: return from the word being defined, here.
\ Every colon word is x86 code entered by call,, so a ret, anywhere in its body
\ returns to its caller.  Rule: the return stack must be as the word found
\ it, so an exit, between >r and its r> must first r> (or r> drop) what it
\ pushed.  Loops and if, keep nothing on the return stack, so they are safe.
: exit,  ret, ;
immediate

\ ===== Defining-words: allot / create / variable =====
\ These let Forth code build variables and arbitrary data structures
\ without escaping back into 000-seed.hex0.  Like constant, create calls
\ the seed's `:` primitive to tokenize the next input word and build a
\ dictionary header (link, flags=0, name-len, name bytes), lays down the
\ 21-byte push body, and resets STATE=0 (since `:` left it at 1).

\ create ( "name" -- )  Define name as a word that pushes the address of
\ the data area immediately following its body.  Caller fills the data
\ area via `,` / `c,` / `allot`.  HERE is at the start of the body when
\ push-body, runs, and the body is 21 bytes, so the data area starts at
\ HERE + 21.
: create  : here 21 + push-body, 0 state ! ;

\ variable ( "name" -- )  Define name as a word that pushes the address of
\ an 8-byte cell, initialized to 0: a create whose data area is one cell.
: variable  create 0 , ;

\ ===== Deferred words: defer / is =====
\ A word can only call words that already exist, but two words that call
\ each other (a statement parser and the if-statement parser inside it)
\ cannot both come first.  defer names a word now and says what it does
\ later: its body calls whatever xt sits in a cell after its code, and is
\ fills that cell once the real word exists.
\
\ A deferred word's body is 35 bytes of code, then the cell:
\   <18 bytes>   push-imm64, of the cell's address   ; edx:eax = &cell
\   <7 bytes>    call, @                             ; edx:eax = the xt
\   <7 bytes>    call, execute                       ; run it
\   C2 04 00     ret 4
\   <8 bytes>    the cell (0 until is fills it)
' @       constant fetch-xt
' execute constant execute-xt
35 constant defer-code-size

\ defer ( "name" -- )  Define name as a word that runs the xt in its cell.
: defer
  : here defer-code-size + push-imm64,           \ TOS = address of the cell
  fetch-xt call,  execute-xt call,  ret,
  0 ,  0 state ! ;

\ is ( xt "name" -- )  Make the deferred word name run xt from now on.
\ ' finds name's code; its cell sits defer-code-size bytes further on.
: is  ' defer-code-size + ! ;

\ ===== The outer interpreter =====
\ The seed's REPL knows words and unsigned decimal numbers only, and
\ compiles a number its own way.  interpret, below, is a second REPL
\ that also reads negative and hex numbers, and compiles a number as the
\ 18-byte push.  The token `interpret` after its definition hands over to it; it
\ never returns, and at end of input it runs bye (exit 0), as the seed does.
\ The library above it is the preamble it needs; the rest of the library,
\ and every file loaded after it, is read by interpret.
\
\ It dispatches as the seed's REPL (seed/SPEC.md, section 9):
\   read a token                            -> none left: bye
\   find it; found, IMMEDIATE or STATE = 0  -> execute
\   found, otherwise                        -> a call to xt at HERE (call,)
\ and then, tried only after find has failed, so 1+ and - stay words:
\   a number: decimal, -decimal or $hex     -> push it, or compile-literal
\   anything else                           -> the token and "?" on stdout,
\                                              exit 2 (the seed's fatal)
\ Nothing of the interpreter's sits on either stack while a word runs, so an
\ interpreted >r ... r>, or a value left across tokens, behaves as under the
\ seed's REPL.

\ compile-literal ( n -- )  What a number does in compile state: lay the
\ 18 bytes that push it (push-imm64,).  A bare number, [lit] and [char]
\ all come here, so they lay the same bytes.
defer compile-literal
' push-imm64, is compile-literal

\ [char] ( "tok" -- )  IMMEDIATE, used inside : ... ;  Compile the next
\ token's first byte as a literal, so `[char] ;` compiles what 59 does.
: [char]  char compile-literal ;
immediate


\ unknown ( a u -- )  As the seed's fatal: the token, "?" and a newline in
\ one write to stdout, then exit 2.
: unknown
  >r [char] ? over r@ + c!  nl over r@ + 1+ c!
  1 swap r> 2 + write drop  2 die ;

\ read-token ( -- a u )  the next token, as the seed's token reads it (its
\ address in the token buffer and its length, u = 0 at end of input, \
\ comments skipped, a 256-byte token fatal), and with ( ) comments skipped
\ too: a token that is exactly ( is dropped with everything up to the next
\ ) byte, or to the end of input.  interpret, [lit] and c{ } read through
\ it; the seed's : and the words that read one name or character (' char
\ s,) call token and do not skip ( ).
: paren?  dup 1 = if, over c@ lparen = exit, then, 0 ;        \ ( a u -- a u f )
: skip-to-paren  begin, key dup 0= swap [char] ) = or 0= while, repeat, ;
: read-token
  begin, token paren? while, 2drop skip-to-paren repeat, ;

\ ----- Numbers -----
\ digit ( c -- n )  c's value as a digit, 0..35, or 99 for any other byte.
: digit
  dup digit? if, [char] 0 - exit, then,
  dup alpha-lower? if, 87 - exit, then,
  dup alpha-upper? if, 55 - exit, then,
  drop 99 ;

\ advance ( a u -- a+1 u-1 )  step past the first byte.
: advance  1- swap 1+ swap ;

\ >digits ( a u base -- n true | false )  a non-empty run of digits below
\ base.  The accumulator wraps silently, as the seed's number does.
variable np-base
: >digits
  np-base !
  dup 0= if, 2drop 0 exit, then,
  0 >r
  begin, dup while,
    over c@ digit dup np-base @ < 0= if, r> drop drop 2drop 0 exit, then,
    r> np-base @ * + >r
    advance
  repeat,
  2drop r> true ;

\ number? ( a u -- n true | false )  decimal digits, - and decimal digits, or
\ $ and hex digits (either case).  Nothing else: no 0x, no -$, no 'c'.
: number?
  dup if, over c@ [char] $ = if, advance 16 >digits exit, then, then,
  dup if, over c@ [char] - = if,
    advance 10 >digits dup if, swap 0 swap - swap then, exit,
  then, then,
  10 >digits ;

\ [lit] ( "n" -- n | )  IMMEDIATE.  The next token as an unsigned decimal
\ number: pushed when interpreting, compiled as a literal in a definition.
\ Any other token (-5, $41, a word's name, the end of input) is fatal, as
\ an unknown word is.  The interpreter below reads numbers bare; [lit] is
\ how every file loaded after this one has always spelt them.
: [lit]
  read-token 2dup 10 >digits if, nip nip state @ if, compile-literal then, exit, then,
  unknown ;
immediate

\ found-immediate? ( -- f )  the IMMEDIATE bit of the entry find just hit.
\ find leaves that entry in the sysvar cell after HERE's (LAST_FOUND); its
\ flags byte is at entry + 8.
: found-immediate?  latest 16 + @ 8 + c@ 1 and ;

\ interpret ( -- )  The loop.  execute stays in this word's own body: a word
\ run from a helper that returned would find the helper's return address
\ on top of the return stack, and an interpreted >r or r> would take it.
: interpret
  begin,
    read-token  dup 0= if, bye then,
    2dup find
    dup if,
      nip nip
      found-immediate? state @ 0= or if, execute else, call, then,
    else,
      drop 2dup number? if,
        nip nip state @ if, compile-literal then,
      else,
        unknown
      then,
    then,
  again, ;
interpret

\ ===== The rest of the library =====
\ The interpreter needs none of these words, so they come after the
\ hand-over.

\ emit ( c -- )  write the byte c to stdout.  The byte needs an address to
\ be written from; the free byte at HERE serves.
: emit  here c!  1 here 1 write drop ;

\ ----- File syscalls (see the syscall wrappers above) -----
\ open  ( path flags mode -- fd )    SYS_open=5
: open   0 0 0 5 syscall6 ;

\ read  ( fd buf count -- n )        SYS_read=3
: read   0 0 0 3 syscall6 ;

\ close ( fd -- err )                SYS_close=6
\ Pads 5 zero args + syscall #.
: close  0 0 0 0 0 6 syscall6 ;

\ ----- Character classification -----
\ alpha? ( c -- flag )  true if c is alphabetic
: alpha?  dup alpha-lower? swap alpha-upper? or ;

\ space? ( c -- flag )  true if c is ' '|tab|LF|CR
: space?  dup 32 - 0= over 9 - 0= or
          over 10 - 0= or  swap 13 - 0= or ;

\ ----- Comparisons -----
\ <= ( a b -- f )  not (a > b).
: <=  > 0= ;

\ >= ( a b -- f )  not (a < b).
: >=  < 0= ;

\ ----- Stack shuffles -----
\ rot ( a b c -- b c a )  rotate third-from-top to top.
: rot   >r swap r> swap ;

\ ----- Memory update helpers -----
\ +! ( n addr -- )  add n to the cell at addr.
: +!  swap over @ + swap ! ;

\ -! ( n addr -- )  subtract n from the cell at addr.
: -!  swap over @ swap - swap ! ;

\ ----- Control flow -----
\ until, ( back-target -- )  Pop a flag; jump back to begin, while it is 0.
\ A post-test loop: begin, BODY until, runs BODY at least once.
: until,
  0branch-xt call, , ;         \ `CALL 0branch` + back-target cell
immediate

\ ----- HERE -----
\ allot ( n -- )  Bump HERE by n bytes (no initialization).
\ Used after `create` to grow an array, or stand-alone for scratch buffers.
: allot  here-addr @ + here-addr ! ;

\ bytes, ( a u -- )  copy u bytes from a to HERE, advancing HERE.
: bytes,
  begin, dup while,
    over c@ c,  1- swap 1+ swap
  repeat,
  2drop ;

\ s, ( "tok" -- )  copy the next token's bytes to HERE: `create name s, text`
\ lays down the string "text" without a terminator or a length.
: s,  token bytes, ;

\ ===== bytes-eq =====
\ bytes-eq ( a1 a2 u -- f )  -1 if first u bytes at a1 match those at a2; 0 else.
\ Used by symbol-table name comparison and keyword recognition in the C
\ compiler.  Stops at the first mismatch: exit, returns 0 from inside the
\ loop, after r> drop has taken the parked count off the return stack.
: bytes-eq
  begin,
    dup 0 >
  while,
    >r                                           ( a1 a2  R: u )
    over c@ over c@ <> if,                       ( a1 a2 )
      r> drop 2drop 0 exit,                      \ mismatch: answer 0
    then,
    1+ swap 1+ swap                              ( a1+1 a2+1 )
    r> 1-                                        ( a1+1 a2+1 u-1 )
  repeat,
  drop 2drop true ;                              \ all u bytes matched

\ ===== Bytes in hex: c{ ... } =====
\ c{ hh ... }  lay bytes spelt in hex, as objdump and the Intel manual spell
\ them: `c{ 48 89 f8 }` lays what `72 c, 137 c, 248 c,` lays, now when
\ interpreting and as compiled code inside a definition.  A token between
\ the braces is an even number of hex digits, so `4889f8` is the same
\ bytes; \ and ( ) comments may sit between them, so a long string can
\ take one instruction per line.  Any other token, or the end of input
\ before }, is fatal as an unknown word is (the token and "?", exit 2).
\ cc/030-cc-io.fth's x{ is the same reader with cc-emit-byte as the sink.

\ hex-digit ( c -- n )  c's value as a hex digit, or 256 if it is not one.
: hex-digit  digit dup 15 > if, drop 256 then, ;

\ hex-byte ( a -- n )  the byte spelt by the two digits at a; above 255 if
\ either is not a hex digit.
: hex-byte  dup c@ hex-digit 16 *  swap 1+ c@ hex-digit + ;

\ hex-check ( a u -- a u )  fatal unless a u is an even run of hex digits.
: hex-check
  dup 1 and if, unknown then,
  2dup begin, dup while,
    over hex-byte 255 > if, 2drop unknown then,
    advance advance
  repeat, 2drop ;

\ hex-lay ( sink n -- sink )  give byte n to sink: interpreting, now;
\ compiling, as `n sink` would compile (a literal, then a call to sink).
: hex-lay  state @ if, compile-literal dup call, else, over execute then, ;

\ hex-bytes ( sink a u -- sink )  hex-lay each byte the digits spell.
: hex-bytes
  begin, dup while,
    >r dup >r hex-byte hex-lay r> 2 + r> 2 -
  repeat, 2drop ;

\ hex{ ( sink "hh ... }" -- )  read hex tokens up to }, laying each byte.
: hex{
  begin,
    read-token  dup 0= if, unknown then,
    over c@ [char] } = over 1 = and if, 2drop drop exit, then,
    hex-check hex-bytes
  again, ;

' c, constant c,-xt
: c{  c,-xt hex{ ; immediate

\ ===== Patching a word, memory, input by file name =====
\ The seed runs on builder-hex0 as well as Linux
\ (tests/builder-hex0/README.md).  There descriptor 0 is the boot disk's
\ command stream, and mmap answers 0.  So the seed reads the file its
\ first argument names, which is this one, and leaves the rest to these
\ words: memory comes from brk, and further input from files opened by
\ name.  The command line of every run is
\     seed-forth forth/010-lib.fth JOB [ARG ...]

\ native! ( old new -- )  Make the word whose code is at old run new's code
\ from now on, for every caller already compiled: old's first five bytes
\ become a jump to new.  forth/020-cc-arena.fth uses it for the
\ compiler's arithmetic; it is here because key needs it first.
: native!
  over 5 + -  swap                       \ rel32 first: old may be - itself
  here >r  here-addr !
  c{ e9 } ,4                             \ jmp rel32
  r> here-addr ! ;

\ ----- Memory -----
\ brk ( addr -- break )  SYS_brk=45: move the end of the program's memory
\ to addr and answer where it is now.  0 moves nothing.
: brk  0 0 0 0 0 45 syscall6 ;

\ brk-alloc ( bytes -- addr | 0 )  bytes of zeroed memory above the break,
\ or 0.  The only way to get memory outside the dictionary; there is no
\ word that gives it back.  The break moves up to the next multiple of 4096
\ past the request, and only up: builder-hex0 answers a break below the
\ current one by zeroing all memory above it, every file included.  It
\ also lets the break go anywhere, and from 0x30000000 it keeps this
\ program's arguments and the programs that wait for it, so the break
\ stops at brk-cap.  Linux says no by answering the old break.
671088640 constant brk-cap                       \ 0x28000000
: brk-alloc
  0 brk swap over +                      ( break end )
  2dup > if, 2drop 0 exit, then,         \ the sum wrapped
  4095 + 4096 / 4096 *                   ( break new )
  dup brk-cap > if, 2drop 0 exit, then,
  dup brk <> if, drop 0 then, ;          \ the kernel did not move it

\ ----- Input -----
\ input ( -- a )  the cell holding the descriptor the seed's key reads.
\ argv ( -- a )   the cell holding the address of the kernel's argv[0] slot.
: input  state 32 + ;
: argv   state 40 + ;

\ arg ( i -- zaddr | 0 )  the i-th argument, NUL-terminated; 0 after the
\ last.  The kernel's pointers are 4 bytes each, so the cell read at slot i
\ holds slot i+1 in its high half, which the mask removes.
: arg  4 * argv @ + @ 4294967295 and ;

\ zlen ( zaddr -- u )  length of a NUL-terminated string.
: zlen  dup begin, dup c@ while, 1+ repeat, swap - ;

\ include-fatal ( zaddr -- )  A file that cannot be read: its name, "?" and
\ a newline on stdout, then exit 2, as an unknown word ends.
: include-fatal
  dup zlen 1 rot rot write drop
  [char] ? emit  nl emit  2 die ;

\ included ( zaddr -- )  Read the file named zaddr next.  The descriptor in
\ use waits on the include stack until that file ends (file-key, below).
\ Sixteen files can wait; a seventeenth is fatal, as a file that does not
\ open is.
create include-stack 128 allot                   \ 16 cells
variable include-depth
: included
  include-depth @ 16 = if, include-fatal then,
  dup 0 0 open                           ( zaddr fd )  \ O_RDONLY
  dup 0< if, drop include-fatal then,
  nip
  input @  include-stack include-depth @ 8 * + !
  1 include-depth +!
  input ! ;

\ include ( "name" -- )  Read the file whose name is the next token.  The
\ token buffer has room for the NUL after the longest token.
: include  token over + 0 swap c!  included ;

\ file-key ( -- c )  The seed's key, with the include stack behind it: the
\ next byte of the current file, one read call per byte, so that a file
\ can be switched between any two bytes.  At the end of an included file,
\ close it, go back to the file that included it, and answer a newline:
\ the file's last token, or a \ comment on its last line, must not run on
\ into the includer's next line.  At the end of the first file, answer 0,
\ which is the end of input.
variable key-byte
: file-key
  input @ key-byte 1 read 1 = if, key-byte c@ exit, then,
  include-depth @ 0= if, 0 exit, then,
  input @ close drop
  1 include-depth -!
  include-stack include-depth @ 8 * + @ input !
  nl ;

\ The seed's token reads every byte through key's code, so sending key to
\ file-key is all it takes.
' key ' file-key native!

\ include-job ( -- )  Go on with the file the second argument names, if
\ there is one.  This is the library's last line: when the job ends, so
\ does this file, and the run.
: include-job  2 arg dup if, included exit, then, drop ;
include-job
