\ 110-cc-decl.fth — what every declaration parser shares.
\
\ Qualifiers, storage classes and the other pieces of a type, type names
\ and casts, the `return` statement, and the words that end a program.
\ The rest of the parser follows in load order: statements in
\ 112-cc-stmt.fth, declarations in 115-cc-native.fth, functions and the
\ program in 117-cc-native-program.fth.
\
\ Depends on 010-lib.fth, 030-cc-io.fth, 050-cc-lex.fth, 060-cc-types.fth, 070-cc-sym.fth,
\ 080-cc-elf.fth, 090-cc-emit.fth, 100-cc-expr.fth.

\ ===========================================================================
\ Bookkeeping
\ ===========================================================================

defer cc-parse-type-name
defer cc-native-decl-fwd
\ A function's frame is sized after its body and patched into the prologue.
variable cc-native-return-type
[lit] 131072 constant cc-native-frame-limit        \ slots in one function's frame

variable cc-main-vaddr                            \ vaddr where main starts
variable cc-call-main-patch                       \ file-offset of rel32 to patch
variable cc-fn-local-count                        \ # locals in current function

\ A function's locals share one frame of 8-byte slots, sized when its body
\ ends (a slot is never reused).  cc-fn-add-slots ( n -- ) claims the next
\ n; the one that would pass cc-native-frame-limit dies with code 162.
: cc-fn-add-slots
  dup cc-fn-local-count @ +
  cc-native-frame-limit
  [lit] 162 cc-check-cap
  cc-fn-local-count +! ;

\ ===========================================================================
\ Token-expectation helpers
\ ===========================================================================

\ Each error path dies through cc-die with its own code, so a failure names
\ its site.

\ cc-expect-kw-id ( kw-id -- )  Consume one token; abort if not the given kw.
: cc-expect-kw-id
  cc-next-token-keep
  tok-kind @ tk-kw <> if,
    drop
    [lit] 140 cc-die
  then,
  tok-kw-id @ <> if,
    [lit] 141 cc-die
  then, ;

\ cc-expect-punct-c ( char -- )  Consume one token; abort if not that punct.
: cc-expect-punct-c
  cc-next-token-keep
  tok-kind @ tk-punct <> if,
    drop
    [lit] 142 cc-die
  then,
  tok-num @ <> if,
    [lit] 143 cc-die
  then, ;

\ cc-expect-ident ( -- )  Consume one token; abort if not tk-ident.
: cc-expect-ident
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 144 cc-die
  then, ;

\ ===========================================================================
\ The end of a program
\ ===========================================================================
\ What cc-native-program (117-cc-native-program.fth) and the drivers need
\ once the last function is compiled.

\ Pre-baked literal "main" for cc-is-main? — laid out as 4 raw bytes (no length
\ prefix here, because cc-is-main? only consumes 4 bytes).
create cc-main-name-bytes  s, main

\ cc-is-main? ( name-addr name-len -- f )  -1 if (addr, len) names "main".
: cc-is-main?                                     ( addr len -- f )
  dup [lit] 4 = if,
    drop                                          ( addr )
    cc-main-name-bytes swap [lit] 4 bytes-eq
  else,
    drop drop [lit] 0
  then, ;

\ cc-finalize-globals ( -- )  After the entire program has been parsed and
\ all functions emitted, append cc-globals-buf to cc-out-buf, place the bss
\ after it, and patch every recorded fixup to point at the now-known global
\ vaddrs.
\
\ cc-globals-base-vaddr is set to cc-base-vaddr + (cc-out-pos at the moment
\ globals are appended).  The bss starts at the next 8-aligned vaddr (the
\ file is padded with zeros to reach it), and cc-bss-size tells
\ cc-finalize-elf how much memory it adds.  Then each fixup's imm32
\ placeholder is overwritten with the slot's vaddr: cc-globals-base-vaddr
\ + slot for a data slot, cc-bss-base-vaddr + (slot - cc-bss-flag) for a
\ bss one.
: cc-finalize-globals
  cc-here-vaddr cc-globals-base-vaddr !
  \ Append cc-globals-pos bytes from cc-globals-buf to cc-out-buf.
  [lit] 0
  begin, dup cc-globals-pos @ < while,
    dup cc-globals-buf + c@ cc-emit-byte
    1+
  repeat, drop
  \ Align the bss, if there is one.
  cc-bss-pos @ if,
    begin, cc-out-pos @ [lit] 7 and while, [lit] 0 cc-emit-byte repeat,
  then,
  cc-here-vaddr cc-bss-base-vaddr !
  cc-bss-pos @ cc-bss-size !
  \ Patch each fixup.  i walks 0..cc-gfixup-count-1.
  [lit] 0
  begin, dup cc-gfixup-count @ < while,
    dup cc-gfixup-slot     cell[] @                \ slot
    dup cc-bss-flag < if,
      cc-globals-base-vaddr @ +                     \ vaddr = base + slot
    else,
      cc-bss-flag - cc-bss-base-vaddr @ +           \ vaddr = bss base + offset
    then,
    over cc-gfixup-out-pos cell[] @                \ patch-offset
    cc-out-patch-address
    1+
  repeat, drop ;

\ cc-patch-call-main ( -- )  Compute and store the call's rel32.
\ rel32 = main_vaddr - vaddr_of_next_instr
\       = main_vaddr - (cc-base-vaddr + cc-call-main-patch + 4)
: cc-patch-call-main
  cc-main-vaddr @
  cc-base-vaddr cc-call-main-patch @ + [lit] 4 + -
  cc-call-main-patch @
  cc-out-patch-4le ;

\ cc-check-fns-defined ( -- )  After the whole program: a function that was
\ called or used as a value but never defined still has pending call or
\ address fixups — each would run a rel32 of 0 (falling through to the next
\ instruction) or load address 0.  Die 206 instead.  Then die 207 if there
\ is no main for the entry stub to call.
: cc-check-fns-defined
  [lit] 0                                         ( id )
  begin, dup cc-sym-count @ < while,
    dup cc-sym-kind-of sk-func = if,
      dup cc-sym-call-fixups @  over cc-sym-addr-fixups @  or if,
        dup cc-sym-name-addr cell[] @ over cc-sym-name-len cell[] @ cc-err-write
        cc-die-end [lit] 1 cc-err-write
        [lit] 206 cc-die
      then,
    then,
    1+
  repeat, drop
  cc-main-vaddr @ 0= if, [lit] 207 cc-die then, ;

\ ===========================================================================
\ Statement parsing
\ ===========================================================================

\ cc-qualifier? ( -- f )  True if the current token is a type qualifier
\ (const / volatile / restrict).  They change nothing in this subset, so
\ every place that reads a type skips them.
: cc-qualifier?
  tok-kind @ tk-kw =
    tok-kw-id @ kw-const    =
    tok-kw-id @ kw-volatile = or
    tok-kw-id @ kw-restrict = or
  and ;

\ cc-qualifier-bit ( -- bit )  The current qualifier's bit in a qualifier
\ set: const 1, volatile 2, restrict 4.  The compiler records sets, not
\ a yes/no flag, so `const` and `volatile` rows stay distinct types.
: cc-qualifier-bit
  tok-kw-id @ kw-const = if, [lit] 1 exit, then,
  tok-kw-id @ kw-volatile = if, [lit] 2 exit, then,
  [lit] 4 ;

\ cc-skip-qualifiers ( -- )  Read past any qualifiers; the first token that
\ isn't one is left pending.
defer cc-qual-note                                \ 115: cc-native-qual-note
variable cc-prefix-qualified
variable cc-type-name-qualified

: cc-skip-qualifiers
  begin,
    cc-next-token-keep cc-qualifier?
  while, cc-qual-note
  repeat,
  cc-putback-token ;

\ cc-count-stars ( -- depth )  After consuming a base type (e.g. 'int'), peek
\ zero or more '*' tokens and return the resulting pointer depth.  A
\ qualifier may follow each '*' (`char * const msg`).  Leaves the first
\ other token pending for the caller.
: cc-count-stars                                  ( -- depth )
  [lit] 0
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] * = and
  while,
    1+ cc-skip-qualifiers
  repeat,
  cc-putback-token ;

\ Skip storage-class specifiers (static / extern / auto / register) and
\ type qualifiers (const / volatile / restrict).  Reads tokens via
\ cc-next-token-keep; whenever one of these keywords is seen, it's consumed
\ and the loop continues.  When a non-qualifier is encountered it is put back
\ so the caller sees it as the next token.
\
\ Only `static` matters: cc-decl-static records whether it was seen, and a
\ local declared static gets file-scope storage instead of a frame slot
\ (cc-parse-local-declarator).  The rest are no-ops.
variable cc-decl-static
variable cc-decl-extern

: cc-skip-storage-quals
  [lit] 0 cc-prefix-qualified !
  [lit] 0 cc-decl-static ! [lit] 0 cc-decl-extern !
  begin,
    cc-next-token-keep
    cc-qualifier? if,
      cc-qualifier-bit cc-prefix-qualified @ or cc-prefix-qualified !
    then,
    kw-static cc-tok-kw? if, true cc-decl-static ! then,
    kw-extern cc-tok-kw? if, true cc-decl-extern ! then,
    tok-kind @ tk-kw =
      tok-kw-id @ kw-static    =
      tok-kw-id @ kw-extern    = or
      tok-kw-id @ kw-auto      = or
      tok-kw-id @ kw-register  = or
      tok-kw-id @ kw-inline    = or
      tok-kw-id @ kw-const     = or
      tok-kw-id @ kw-volatile  = or
      tok-kw-id @ kw-restrict  = or
    and
  while,
    \ already consumed; just loop
  repeat,
  cc-putback-token ;

\ ===========================================================================
\ Pieces of a type: a struct tag, a function pointer's parameters, a keyword
\ ===========================================================================

\ cc-skip-fnptr-params ( -- )  Skip everything from the current position
\ through the matching ')'.  Uses paren-depth counter starting at 1
\ (the opening '(' has just been consumed).  Tokens are consumed one at
\ a time via cc-next-token-keep so cc-tok-pending is left clear at exit.
: cc-skip-fnptr-params
  [lit] 1
  begin,
    dup [lit] 0 >
  while,
    cc-next-token-keep
    tok-kind @ tk-eof = if, [lit] 184 cc-die then,
    tok-kind @ tk-punct = if,
      tok-num @ lparen = if, 1+ then,
      tok-num @ [char] ) = if, 1- then,
    then,
  repeat,
  drop ;

\ cc-tok-is-basic-type-kw? ( -- f )  -1 iff current token is a basic-type
\ keyword that introduces a local declaration: int / char / void / long /
\ short / unsigned / signed.  All are treated as 8-byte slot in codegen.
: cc-tok-is-basic-type-kw?
  tok-kind @ tk-kw =
    tok-kw-id @ kw-int      =
    tok-kw-id @ kw-char     = or
    tok-kw-id @ kw-void     = or
    tok-kw-id @ kw-long     = or
    tok-kw-id @ kw-short    = or
    tok-kw-id @ kw-unsigned = or
    tok-kw-id @ kw-signed   = or
  and ;

\ ===========================================================================
\ Type names and casts
\ ===========================================================================
\ A cast `( TYPE ) operand` names a type without declaring anything:
\ qualifiers, a base (a type keyword or several, struct TAG, enum TAG, or
\ a typedef-name), then '*'s.  Its value is the operand's; only the type
\ the parser tracks changes, so `*(char*)p` loads one byte and
\ `((struct T*)p)->f` finds the field.  A (char) cast keeps the low byte.

variable cc-cast-desc                              \ struct TAG's descriptor, or 0

\ cc-try-cast ( -- f )  The current token is '('.  If a type name follows,
\ compile the whole cast — type, ')', then the operand, a unary
\ expression — and answer true.  Otherwise answer false with the token
\ after the '(' put back, for cc-parse-paren.
: cc-try-cast
  cc-next-token-keep
  cc-type-start? 0= if,
    cc-putback-token [lit] 0 exit,
  then,
  cc-parse-type-name >r                            ( ; R: ty )
  [char] ) cc-expect-punct-c
  cc-type-name-qualified @ >r
  cc-cast-desc @ >r                                ( ; R: ty qualification desc )
  cc-parse-unary
  cc-emit-materialize
  r> r> r> swap >r                                 ( desc ty ; R: qualification )
  over cc-cast-desc !                              \ the operand may hold casts
  dup cc-emit-convert-edx:eax
  cc-mark-not-lvalue
  cc-last-expr-type !
  cc-last-struct-desc !
  r> cc-last-expr-qualified !
  true ;

' cc-try-cast is cc-try-cast-fwd

\ ===========================================================================
\ Switch-scrutinee unwind
\ ===========================================================================
\ cc-parse-switch (112-cc-stmt.fth) parks the outer edi:esi with
\ `push edi:esi` and restores it with `pop edi:esi` at the switch's end
\ label.  Any statement that jumps out of the switch body without passing
\ the end label — return, continue, goto — must first emit compensating
\ pops, or each traversal leaks 8 bytes of stack per open switch (and
\ return hands the caller its own switch's scrutinee overwritten).
\
\ cc-switch-depth counts the switches lexically open at the current parse
\ point; cc-loop-switch-depth snapshots it at the innermost enclosing loop.
\   return:    pop cc-switch-depth times (every open switch in the function),
\   continue:  pop (cc-switch-depth - cc-loop-switch-depth) times (the
\              switches between the statement and the loop it continues),
\   goto:      pop cc-switch-depth times — correct for labels outside any
\              switch; goto to a label INSIDE a switch is unsupported.
\ break needs nothing: it targets the innermost loop or switch end label,
\ so it never jumps across a scrutinee push.
variable cc-switch-depth
variable cc-loop-switch-depth

\ cc-emit-switch-unwind ( n -- )  Emit n `pop edi:esi` instructions.
: cc-emit-switch-unwind                           ( n -- )
  begin,
    dup [lit] 0 >
  while,
    cc-emit-pop-edi:esi
    1-
  repeat,
  drop ;

\ cc-parse-return ( -- )  "return" already consumed; parse [expr] ';'.
\ Bare `return;` (no expression) is legal C — emit edx:eax := 0 + epilogue.
\ Peek the next token: if it's ';' the peek already consumed it, so do NOT
\ call cc-expect-punct-c again.  Otherwise putback and parse the expression.
\ Either way, unwind any open switch scrutinees so edi:esi is restored before
\ the epilogue's ret.
: cc-parse-return
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] ; = and if,
    cc-emit-zero-edx:eax                          \ no value returned
    cc-switch-depth @ cc-emit-switch-unwind
    cc-emit-epilogue
  else,
    cc-putback-token
    cc-parse-expr
    cc-native-return-type @ cc-emit-convert-edx:eax
    cc-switch-depth @ cc-emit-switch-unwind
    cc-emit-epilogue
    [char] ; cc-expect-punct-c
  then, ;

\ Bind the expression parser's sizeof type query after declaration parsing.
: cc-native-sizeof-type cc-parse-type-name cc-cast-desc @ ;
' cc-native-sizeof-type is cc-sizeof-type-fwd
