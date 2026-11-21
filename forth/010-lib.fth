\ 010-lib.fth — minimal helpers built on top of the 32 hand-encoded primitives.
\ Loaded before any Forth-level vocabulary.
\
\ Conventions:
\   - Up to the outer interpreter (interpret, near the end), all arithmetic
\     constants use [lit] (the decimal literal compiler) because the seed
\     has no interpret-mode number parser at all — [lit] is the only path
\     (the seed's parse_decimal_code).  Characters use char / [char]
\     (defined below), so no ASCII code needs a comment to explain it.
\     After the hand-over to interpret, numbers are written bare.
\   - No seed address is typed in: sysvar cells are found from the seed's
\     state and latest primitives, and primitive xts with ' (tick).

\ here-addr ( -- a )  push the address of the HERE sysvar cell.
\ Useful because most "advance HERE" idioms want to update the cell, not just
\ read its current value (which is what `here` does).  The seed's sysvars are
\ consecutive cells STATE, LATEST, HERE, so HERE's cell follows LATEST's.
: here-addr  latest [lit] 8 + ;         \ &HERE = &LATEST + 8 = 0x413010

\ c, ( b -- )  store low byte of TOS at HERE and advance HERE by 1.
\ This is the workhorse for any code-emission vocabulary built in Forth.
: c,
  here c!                                 \ *HERE = byte
  here-addr @ [lit] 1 + here-addr !       \ HERE += 1
;

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
: -  dup nand [lit] 1 + + ;

\ 1+ ( n -- n+1 )   1- ( n -- n-1 )  Step by one: the commonest arithmetic
\ in the C compiler (pointers, counters, lengths), so it gets a name.
: 1+  [lit] 1 + ;
: 1-  [lit] 1 - ;

\ ===== Linux syscall wrappers (via syscall6 primitive) =====
\ syscall6 ( a b c d e f n -- rax )  loads a..f into rdi/rsi/rdx/r10/r8/r9
\ and n into rax.  We pad with zeros for unused argument slots.
\
\ Linux x86-64 syscall numbers:
\   read=0  write=1  open=2  close=3  exit=60  brk=12  mmap=9

\ write ( fd buf count -- n )        SYS_write=1
: write  [lit] 0 [lit] 0 [lit] 0 [lit]  1 syscall6 ;

\ die ( n -- )  Exit with status n via SYS_exit=60.
\ Used by the C compiler's error paths instead of inlining the full syscall.
: die  [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 60 syscall6 ;

\ ===== Character classification helpers =====
\ All return -1 if true, 0 if false (Forth boolean convention).
\ Approach: just hard-code the literal byte values and use 0= equality chains.
\ (char / [char] come later, in the section on immediate words, so these
\ few spell their ASCII codes in decimal.)

\ digit? ( c -- flag )  true if c is in '0'..'9' (ASCII 48..57)
\ Approach: compute (c-48)/10.  If c<48 the subtract underflows to a huge
\ unsigned, /10 is huge, 0= is 0.  If c in 48..57, (c-48)/10 = 0, 0= is -1.
\ If c >= 58, (c-48)/10 >= 1, 0= is 0.  ✓
: digit?  [lit] 48 - [lit] 10 / 0= ;

\ alpha-lower? ( c -- flag )  true if c is 'a'..'z' (97..122)
\ Same trick: (c-97)/26 = 0 iff c in 97..122.
: alpha-lower?  [lit] 97 - [lit] 26 / 0= ;

\ alpha-upper? ( c -- flag )  true if c is 'A'..'Z' (65..90)
: alpha-upper?  [lit] 65 - [lit] 26 / 0= ;

\ ===== Comparison operators =====
\ All return -1 (true) / 0 (false), Forth boolean convention.

\ true ( -- -1 )  the canonical true flag, all 64 bits set.  The decimal
\ literal parser is unsigned-only, so -1 cannot be written as [lit] -1;
\ `0 0=` manufactures it (0 is zero, so 0= answers -1).
: true  [lit] 0 0= ;

\ = ( a b -- f )  -1 if a = b, else 0.  Equal iff (a - b) = 0.
: =   - 0= ;

\ <> ( a b -- f )  inverse of =.
: <>  = 0= ;

\ 2^63 ( -- 2^63 )  9223372036854775808 = 0x8000000000000000, the sign bit
\ of a 64-bit signed integer.  The literal round-trips through
\ parse_decimal_code because that parser uses an unsigned 64-bit
\ accumulator.
: 2^63  [lit] 9223372036854775808 ;

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
  [lit] 256 / dup c,           \ byte 1
  [lit] 256 / dup c,           \ byte 2
  [lit] 256 / c, ;             \ byte 3

\ ,8 ( v -- )  emit all 8 bytes of v at HERE in LE order.
\ Used for movabs imm64 in defining words and for 8-byte branch target slots.
: ,8
  dup ,4                                                 \ low 4 bytes
  [lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 /        \ shift right 32
  ,4 ;                                                   \ high 4 bytes

\ ===== immediate flag toggle =====
\ immediate ( -- )  Set the IMMEDIATE bit in the flags byte of the most-recent
\ dict entry.  An immediate word executes at compile time even when STATE=1
\ (inside : ... ;).  Mirrors the manual `01` flags byte on `;` in 000-seed.hex0.
\
\ Layout reminder: a dict entry is  link(8) flags(1) name-len(1) name(N) body.
\ `latest` is a seed primitive — it pushes the address of the LATEST sysvar
\ cell; `latest @` fetches the current dict tail pointer; `+ 8` is the
\ flags-byte address.
: immediate  latest @ [lit] 8 + [lit] 1 swap c! ;

\ ===== the push body: constant (and create / variable, further below) =====
\ constant is defined early so branch-xt/0branch-xt can use it: the
\ control-flow combinators below need the xts of branch/0branch, and
\ hard-coding them as numeric literals would break every time
\ 000-seed.hex0's dictionary layout changes; instead, resolve them at load
\ time via the seed's `'` (tick) primitive, captured into a constant.
\
\ A word that pushes one value has a 19-byte runtime body:
\   48 83 ED 08          sub rbp, 8       ; make data-stack room
\   48 89 7D 00          mov [rbp+0], rdi ; spill old TOS
\   48 BF <imm64>        movabs rdi, V    ; load the value as the new TOS
\   C3                   ret
\ constant, create and variable all lay it down; they differ only in V
\ and in what follows the ret.

\ ret, ( -- )  emit C3, the x86 `ret` instruction.
: ret,  [lit] 195 c, ;

\ push-imm64, ( v -- )  emit the 18 bytes that push v: the body minus ret.
: push-imm64,
  [lit] 72 c, [lit] 131 c, [lit] 237 c, [lit] 8 c,         \ 48 83 ED 08  sub rbp, 8
  [lit] 72 c, [lit] 137 c, [lit] 125 c, [lit] 0 c,         \ 48 89 7D 00  mov [rbp], rdi
  [lit] 72 c, [lit] 191 c,                                 \ 48 BF        movabs rdi, ...
  ,8 ;                                                     \ imm64 = v (consumes v)

\ push-body, ( v -- )  emit the whole 19-byte body of a word that pushes v.
: push-body,  push-imm64, ret, ;

\ constant ( v "name" -- )  define name as a word that pushes v.
\ `:` parses the name, builds the header and sets STATE=1; we emit the body
\ by hand and set STATE back to 0 (a `;` here would end constant itself).
: constant  : push-body, [lit] 0 state ! ;

\ ===== call, and character literals =====

\ call, ( target -- )  Emit a 5-byte x86-64 CALL to absolute `target`
\ at HERE.  rel32 = target - (HERE + 5).  After `[lit] 232 c,` advances
\ HERE by 1, HERE points at the rel32's first byte and HERE+4 points just
\ past the 5-byte CALL — so rel32 = target - (HERE_now + 4).
\ Kept here so [char] and the control-flow combinators do not need another
\ assembler layer.
: call,
  [lit] 232 c,                 \ 0xE8 CALL opcode
  here [lit] 4 + - ,4 ;        \ rel32 = target - (HERE+4); emit 4 LE bytes

\ lit-xt — the xt of the seed's `lit` primitive, which pushes the cell that
\ follows its CALL (the runtime half of [lit]).
' lit constant lit-xt

\ tib ( -- a )  the seed's token buffer, where its reader leaves the token
\ it read last.  It sits 2048 bytes below the sysvar page, which starts at
\ STATE's cell: 0x413000 - 2048 = 0x412800.
: tib  state [lit] 2048 - ;

\ char ( "tok" -- c )  read the next token and push its first byte.
\ The seed's one Forth-callable token reader is ' (tick): it reads a token
\ into the TIB and looks it up.  We drop its answer (an xt, or 0 when no word
\ has that name) and take the byte straight from the TIB.
: char  ' drop tib c@ ;

\ [char] ( "tok" -- )  IMMEDIATE, used inside : ... ;  Compile the next
\ token's first byte as a literal: CALL lit and the cell, the same 13 bytes
\ `[lit] N` lays down.  So `[char] ;` compiles exactly what `[lit] 59` does.
: [char]  char lit-xt call, , ;
immediate

\ Characters char cannot quote.  The reader never makes a token of
\ whitespace, and a token that is exactly \ or ( starts a comment.
[lit]  9 constant tab
[lit] 10 constant nl
[lit] 32 constant bl
[lit] 40 constant lparen                    \ (
[lit] 92 constant backslash

\ ===== Control-flow combinators =====
\ Compile-time helpers that emit calls to the seed's `branch` and `0branch`
\ primitives, plus inline 8-byte target slots, structured per traditional
\ Forth idiom (begin/until/again/while/repeat/if/else/then).
\
\ The seed's branch/0branch primitives work with inline 8-byte target cells.
\ Their x86 machine code is:
\     pop rax           ; rax = return address = address of inline slot
\     mov rax, [rax]    ; rax = contents of slot = branch destination
\     push rax          ; push destination as new return address
\     ret               ; "return" to destination (indirect jump)
\
\ zbranch_code is the same except it first inspects TOS (in rdi/rdx) and
\ either loads the slot (branch taken) or skips past it (fall through).
\
\ This means the combinators must emit a 5-byte CALL rel32 followed
\ immediately by an 8-byte absolute target address.  The CALL lands
\ inside branch_code / zbranch_code which pop their own return address
\ (pointing at the slot), dereference it, and jump.
\
\ The slot is thus "consumed" — it does NOT remain on the return stack.
\ backward branches simply emit the back-target cell; forward branches
\ reserve a slot, return its address as a fixup, and patch it later.
\
\ slot-layout for a forward branch (e.g. if, ... then,):
\     E8 xx xx xx xx    ; CALL rel32 -> 0branch_code
\     <8-byte slot>     ; initially 0, patched by then, to target HERE
\ After CALL, rax -> slot; zbranch_code tests flag, either:
\   - flag==0: mov rax,[rax] -> load slot -> push -> ret to target
\   - flag!=0: add rax,8    -> skip slot -> push -> ret past slot
\
\ Names end in `,` per Forth-asm convention ("emits code") and to keep them
\ distinct from any plain runtime `if`/`then` words.
\
\ branch-xt / 0branch-xt — the xts of the seed's `branch` and `0branch`
\ primitives, captured via `'` at load time so any 000-seed.hex0 layout change
\ is automatically tracked.
' branch  constant branch-xt
' 0branch constant 0branch-xt

\ if, ( -- fixup )  At compile time: emit `CALL 0branch` + reserved 8-byte
\ target slot.  Returns the slot's address as a fixup for `then,` or `else,`.
\ Runtime semantics: pops a flag; if flag = 0, jumps to the patched target
\ (the matching `then,`/`else,`'s HERE).  If flag is non-zero, falls through.
: if,
  0branch-xt call,
  here                         \ slot address, returned as fixup
  [lit] 0 ,                    \ reserve 8 bytes (` ,` emits a cell)
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
  [lit] 0 ,                    \ reserve 8 bytes
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
  here [lit] 0 , ;
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

\ exit, ( -- )  Compile a `ret`: return from the word being defined, here.
\ Every colon word is x86 code entered by CALL, so a ret anywhere in its body
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
\ 19-byte push body, and resets STATE=0 (since `:` left it at 1).

\ create ( "name" -- )  Define name as a word that pushes the address of
\ the data area immediately following its body.  Caller fills the data
\ area via `,` / `c,` / `allot`.  HERE is at the start of the body when
\ push-body, runs, and the body is 19 bytes, so the data area starts at
\ HERE + 19.
: create  : here [lit] 19 + push-body, [lit] 0 state ! ;

\ variable ( "name" -- )  Define name as a word that pushes the address of
\ an 8-byte cell, initialized to 0: a create whose data area is one cell.
: variable  create [lit] 0 , ;

\ ===== Deferred words: defer / is =====
\ A word can only call words that already exist, but two words that call
\ each other (a statement parser and the if-statement parser inside it)
\ cannot both come first.  defer names a word now and says what it does
\ later: its body calls whatever xt sits in a cell after its code, and is
\ fills that cell once the real word exists.
\
\ A deferred word's body is 29 bytes of code, then the cell:
\   <18 bytes>   push-imm64, of the cell's address   ; rdi = &cell
\   E8 <rel32>   call @                              ; rdi = the xt
\   E8 <rel32>   call execute                        ; run it
\   C3           ret
\   <8 bytes>    the cell (0 until is fills it)
' @       constant fetch-xt
' execute constant execute-xt
[lit] 29 constant defer-code-size

\ defer ( "name" -- )  Define name as a word that runs the xt in its cell.
: defer
  : here defer-code-size + push-imm64,           \ rdi = address of the cell
  fetch-xt call,  execute-xt call,  ret,
  [lit] 0 ,  [lit] 0 state ! ;

\ is ( xt "name" -- )  Make the deferred word name run xt from now on.
\ ' finds name's code; its cell sits defer-code-size bytes further on.
: is  ' defer-code-size + ! ;

\ ===== The outer interpreter =====
\ The seed's REPL knows words and [lit] only: a number typed bare is a miss,
\ and a miss prints the token and "?" and reads on.  interpret, below, is a
\ second REPL that also reads numbers and stops at the first token it cannot
\ take.  The token `interpret` after its definition hands over to it; it
\ never returns, and at end of input it runs bye (exit 0), as the seed does.
\ The library above it is the preamble it needs; the rest of the library,
\ and every file loaded after it, is read by interpret.
\
\ It dispatches as the seed's REPL (000-seed.hex0, repl):
\   read a token                            -> none left: bye
\   find it; found, IMMEDIATE or STATE = 0  -> execute
\   found, otherwise                        -> CALL xt at HERE (call,)
\ and then, tried only after find has failed, so 1+ and - stay words:
\   a number: decimal, -decimal or $hex     -> push it, or compile-literal
\   anything else                           -> the token and "?" on stdout,
\                                              exit 2 (the seed's fatal_token)
\ Nothing of the interpreter's sits on either stack while a word runs, so an
\ interpreted >r ... r>, or a value left across tokens, behaves as under the
\ seed's REPL.

\ read-token ( -- a u )  the seed's own reader, made callable: the token's
\ address in the TIB and its length, u = 0 at end of input; comments are
\ skipped and a 256-byte token is fatal (exit 2), as the seed's REPL reads.
\ ' is `call read_word; jmp find`, so read_word is the end of that 5-byte
\ CALL plus its rel32.  @ fetches the rel32 and 4 bytes more; the sum is
\ right in its low 32 bits, and the seed lives below 4 GiB.
' ' dup [lit] 5 + swap 1+ @ + [lit] 4294967295 and constant read-word-addr
: header:  : [lit] 0 state ! ;          \ ( "name" -- ) header only; c, lays the body
header: read-token  read-word-addr call, ret,

\ ----- Numbers -----
\ digit ( c -- n )  c's value as a digit, 0..35, or 99 for any other byte.
: digit
  dup digit? if, [char] 0 - exit, then,
  dup alpha-lower? if, [lit] 87 - exit, then,
  dup alpha-upper? if, [lit] 55 - exit, then,
  drop [lit] 99 ;

\ advance ( a u -- a+1 u-1 )  step past the first byte.
: advance  1- swap 1+ swap ;

\ >digits ( a u base -- n true | false )  a non-empty run of digits below
\ base.  The accumulator wraps silently, as the seed's parse_decimal does.
variable np-base
: >digits
  np-base !
  dup 0= if, 2drop [lit] 0 exit, then,
  [lit] 0 >r
  begin, dup while,
    over c@ digit dup np-base @ < 0= if, r> drop drop 2drop [lit] 0 exit, then,
    r> np-base @ * + >r
    advance
  repeat,
  2drop r> true ;

\ number? ( a u -- n true | false )  decimal digits, - and decimal digits, or
\ $ and hex digits (either case).  Nothing else: no 0x, no -$, no 'c'.
: number?
  dup if, over c@ [char] $ = if, advance [lit] 16 >digits exit, then, then,
  dup if, over c@ [char] - = if,
    advance [lit] 10 >digits dup if, swap [lit] 0 swap - swap then, exit,
  then, then,
  [lit] 10 >digits ;

\ compile-literal ( n -- )  What a number does in compile state.  The seed's
\ [lit] lays CALL lit and the cell; cc/020-cc-arena.fth's [lit] lays an
\ inline push instead, and points this at it (`is compile-literal`), so a
\ bare number and [lit] lay the same bytes at every point.
defer compile-literal
: lit-literal  lit-xt call, , ;
' lit-literal is compile-literal

\ unknown ( a u -- )  As the seed's fatal_token: the token, "?" and a
\ newline in one write to stdout, then exit 2.
: unknown
  >r [char] ? over r@ + c!  nl over r@ + 1+ c!
  [lit] 1 swap r> [lit] 2 + write drop  [lit] 2 die ;

\ found-immediate? ( -- f )  the IMMEDIATE bit of the entry find just hit.
\ find leaves that entry in the sysvar cell after HERE's (LAST_FOUND); its
\ flags byte is at entry + 8.
: found-immediate?  latest [lit] 16 + @ [lit] 8 + c@ [lit] 1 and ;

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

\ ----- File syscalls (see the syscall wrappers above) -----
\ open  ( path flags mode -- fd )    SYS_open=2
: open   0 0 0 2 syscall6 ;

\ read  ( fd buf count -- n )        SYS_read=0
: read   0 0 0 0 syscall6 ;

\ close ( fd -- err )                SYS_close=3
\ Pads 5 zero args + syscall #.
: close  0 0 0 0 0 3 syscall6 ;

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

\ skip-vm-pages ( -- )  Jump HERE to the first page above the seed's fixed VM
\ pages: data stack (below 0x411000), I/O scratch byte (0x412000), token
\ buffer (0x412800) and the sysvar page, which starts at STATE's cell.  So
\ HERE becomes STATE + 4096 = 0x414000.  030-cc-io.fth and 130-asm.fth call
\ it before creating their megabyte buffers, which then cannot overlap VM
\ state.  HERE must still be below the data stack (0x410000) when it runs.
: skip-vm-pages  state 4096 + here-addr ! ;

\ token ( "tok" -- a u )  read the next token; leave its address in the TIB
\ and its length.  The seed keeps the length in a register Forth cannot
\ see, so we blank the TIB's 256 bytes first and then count the token's
\ bytes up to the first blank (a token is at most 255 bytes).
: token
  tib 256 + tib                                  ( end p )
  begin, 2dup > while, bl over c! 1+ repeat,     \ fill the TIB with blanks
  2drop  ' drop                                  \ read the token into it
  tib 0                                          ( a 0 )
  begin, 2dup + c@ bl <> while, 1+ repeat, ;     ( a u )

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
\ compiling, as `n sink` would compile (a literal, then CALL sink).
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
