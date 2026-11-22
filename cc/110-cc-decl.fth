\ 110-cc-decl.fth — what every declaration parser shares.
\
\ Qualifiers, storage classes and the other pieces of a type, type names
\ and casts, the `return` statement, and the words that end a program.
\ The rest of the parser follows in load order: statements in
\ 112-cc-stmt.fth, then one of two sets of declarations, functions and
\ driver.  The C subset needed to compile M2-Planet has its own in
\ 114-cc-func.fth and 116-cc-prog.fth; native mode loads neither and has
\ 115-cc-native.fth and 117-cc-native-program.fth.
\
\ Depends on 010-lib.fth, 030-cc-io.fth, 050-cc-lex.fth, 060-cc-types.fth, 070-cc-sym.fth,
\ 080-cc-elf.fth, 090-cc-emit.fth, 100-cc-expr.fth.

\ ===========================================================================
\ Bookkeeping
\ ===========================================================================

defer cc-native-type-name-fwd
defer cc-native-decl-fwd
defer cc-native-type-start-fwd
\ Native declarations use dynamically sized frames, patched after the body.
variable cc-native-return-type
variable cc-native-return-desc
variable cc-type-name-array
variable cc-type-name-inner
\ Declaration spelling and executable value support are separate decisions.
: cc-native-float-types-default cc-bootstrap-floatbits @ ;
defer cc-native-float-types-fwd
' cc-native-float-types-default is cc-native-float-types-fwd
variable cc-native-frame-limit
[lit] 131072 cc-native-frame-limit !

variable cc-main-vaddr                            \ vaddr where main starts
variable cc-call-main-patch                       \ file-offset of rel32 to patch
variable cc-fn-local-count                        \ # locals in current function

\ Every function gets the same frame: cc-frame-slots 8-byte slots below rbp,
\ shared by its parameters and every local in every block of its body (a
\ slot is never reused).  cc-fn-add-slots ( n -- ) claims the next n; the
\ one that would pass the frame's end dies with code 162 instead of
\ silently overlapping the stack below it.
[lit] 32 constant cc-frame-slots
: cc-fn-add-slots
  dup cc-fn-local-count @ +
  cc-target-lp64 @ if, cc-native-frame-limit @ else, cc-frame-slots then,
  [lit] 162 cc-check-cap
  cc-fn-local-count +! ;

\ cc-pending-struct-desc is set by cc-parse-param-list-loop (114) when a
\ parameter's base is `struct TAG`, and read when that loop records the
\ parameter's symbol-table entry (so the struct descriptor pointer ends up
\ in the symbol's struct-desc cell).  For non-struct types it stays at 0.
variable cc-pending-struct-desc

\ ===========================================================================
\ Token-expectation helpers
\ ===========================================================================

\ Each error path dies through cc-die with its own code, so a failure names
\ its site.  This file's codes are 140..169; 112, 114 and 116 have
\ 170..179, 180..189 and 190..219 (Appendix G).

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
\ What every program driver needs once the last function is compiled,
\ whichever parser it ran: 116-cc-prog.fth's cc-parse-program,
\ 117-cc-native-program.fth's cc-native-program, or the object program of
\ 121-cc-sysv.fth.  They sit here, not beside the buffers they walk in
\ 090-cc-emit.fth, because cc-out-patch-address is the back end's word and
\ cc/i386/090-emit.fth defines its own after that file.

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
\ cc-finalize-elf how much memory it adds.  Then each fixup's imm64
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
\ is no main for the entry stub to call.  116-cc-prog.fth registers memset
\ with no body, so a program it compiles that uses memset dies here too:
\ this compiler has no memset to link.
: cc-check-fns-defined
  [lit] 0                                         ( id )
  begin, dup cc-sym-count @ < while,
    dup cc-sym-kind-of sk-func = if,
      dup cc-sym-call-fixups @  over cc-sym-addr-fixups @  or if,
        cc-target-lp64 @ if,
          dup cc-sym-name-addr cell[] @ over cc-sym-name-len cell[] @ cc-err-write
          cc-die-end [lit] 1 cc-err-write
        then,
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
\ set: const 1, volatile 2, restrict 4.  The LP64 targets record sets, not
\ a yes/no flag, so `const` and `volatile` rows stay distinct types.
: cc-qualifier-bit
  tok-kw-id @ kw-const = if, [lit] 1 exit, then,
  tok-kw-id @ kw-volatile = if, [lit] 2 exit, then,
  [lit] 4 ;

\ cc-skip-qualifiers ( -- )  Read past any qualifiers; the first token that
\ isn't one is left pending.
: cc-qual-note-noop ;
defer cc-qual-note
' cc-qual-note-noop is cc-qual-note
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
\ (cc-parse-local-declarator).  The rest are no-ops.  cc-decl-storage
\ counts the storage-class keywords read, for targets that reject two.
variable cc-decl-static
variable cc-decl-extern
variable cc-decl-storage

: cc-skip-storage-quals
  [lit] 0 cc-prefix-qualified !
  [lit] 0 cc-decl-static ! [lit] 0 cc-decl-extern ! [lit] 0 cc-decl-storage !
  begin,
    cc-next-token-keep
    cc-qualifier? if,
      cc-qualifier-bit cc-prefix-qualified @ or cc-prefix-qualified !
    then,
    kw-static cc-tok-kw? if, true cc-decl-static ! then,
    kw-extern cc-tok-kw? if, true cc-decl-extern ! then,
    kw-static cc-tok-kw? kw-extern cc-tok-kw? or
    kw-auto cc-tok-kw? or kw-register cc-tok-kw? or if,
      [lit] 1 cc-decl-storage +!
    then,
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

\ cc-skip-enum-tag ( -- )  The current token is `enum` used as a type
\ (`enum BINDING kind`): consume the tag.  An enum's values are ints, so
\ the type is int.
: cc-skip-enum-tag
  cc-next-token-keep
  tok-kind @ tk-ident <> if, cc-putback-token then, ;

\ ===========================================================================
\ Pieces of a type: a struct tag, a function pointer's parameters, a keyword
\ ===========================================================================

\ cc-lookup-struct-tag-soft ( -- desc-or-0 )  Read an IDENT token and look
\ it up as a struct tag: its descriptor, or 0 if the tag isn't found or
\ isn't registered as a struct.  Lets the parser tolerate opaque/incomplete
\ struct references in headers that declare but don't define the struct
\ (e.g. cc_globals.c's `struct type* foo;`).
: cc-lookup-struct-tag-soft                       ( -- desc-or-0 )
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 148 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-sym-find-tag        ( id-or-neg1 )
  dup 0< if,
    drop [lit] 0
  else,
    dup cc-sym-kind-of sk-struct <> if,
      drop [lit] 0
    else,
      cc-sym-val-of
    then,
  then, ;

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
    cc-target-lp64 @ cc-native-float-types-fwd 0= and if,
      kw-float cc-tok-kw? kw-double cc-tok-kw? or if, [lit] 214 cc-die then,
    then,
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

\ cc-type-start? ( -- f )  Does the current token begin a type name?
: cc-type-start?
  cc-target-lp64 @ if, cc-native-type-start-fwd exit, then,
  cc-tok-is-basic-type-kw?  cc-qualifier? or
  kw-struct cc-tok-kw? or  kw-enum cc-tok-kw? or
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find
    dup 0< if, drop else, cc-sym-kind-of sk-typedef = or then,
  then, ;

\ cc-parse-type-name ( -- ty )  The current token begins a type name; read
\ it, stars and all, and leave the token after it pending.
: cc-parse-type-name
  cc-target-lp64 @ if, cc-native-type-name-fwd exit, then,
  [lit] 0 cc-cast-desc !
  begin, cc-qualifier? while, cc-next-token-keep repeat,
  kw-struct cc-tok-kw? if,
    cc-lookup-struct-tag-soft cc-cast-desc !
    ty-struct [lit] 0
  else,
  kw-enum cc-tok-kw? if,
    cc-skip-enum-tag ty-int [lit] 0
  else,
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find cc-sym-val-of
    dup ty-base swap ty-ptr
  else,
    \ Keywords: int, char, void, and combinations such as `unsigned int`
    \ or `long long`; any char makes it char.
    ty-int
    begin,
      kw-char cc-tok-kw? if, drop ty-char then,
      kw-void cc-tok-kw? if, drop ty-void then,
      cc-next-token-keep cc-tok-is-basic-type-kw?
    while,
    repeat,
    cc-putback-token
    [lit] 0
  then, then, then,                                ( base ptr )
  cc-skip-qualifiers
  cc-count-stars + ty-make ;

\ cc-try-cast ( -- f )  The current token is '('.  If a type name follows,
\ compile the whole cast — type, ')', then the operand, a unary
\ expression — and answer true.  Otherwise answer false with the token
\ after the '(' put back, for cc-parse-paren.
: cc-cast-types-default ( source destination -- ) 2drop ;
defer cc-cast-types-fwd
' cc-cast-types-default is cc-cast-types-fwd
\ Runtime conversion stays separate from the pure cast-type policy.
: cc-cast-value-default ( source destination -- ) cc-emit-convert-value ;
defer cc-cast-value-fwd
' cc-cast-value-default is cc-cast-value-fwd
\ Only target-approved integer constant zero casts retain null provenance.
: cc-cast-null-default ( source destination null qualified -- null ) 2drop 2drop [lit] 0 ;
defer cc-cast-null-fwd
' cc-cast-null-default is cc-cast-null-fwd

: cc-try-cast
  cc-next-token-keep
  cc-type-start? 0= if,
    cc-putback-token [lit] 0 exit,
  then,
  cc-parse-type-name >r                            ( ; R: ty )
  cc-target-lp64 @ if, cc-type-name-array @ if, [lit] 238 cc-die then, then,
  [char] ) cc-expect-punct-c
  cc-type-name-qualified @ >r
  cc-cast-desc @ >r                                ( ; R: ty qualification desc )
  cc-parse-unary
  cc-emit-materialize
  r> r> r> swap >r                                 ( desc ty ; R: qualification )
  over cc-cast-desc !                              \ the operand may hold casts
  cc-target-lp64 @ if,
    cc-last-expr-type @ over cc-cast-types-fwd
    cc-last-expr-type @ over cc-cast-value-fwd
  else,
    dup ty-base ty-char = over ty-ptr 0= and if, cc-emit-zx-byte-rdi then,
  then,
  cc-last-expr-type @ over cc-last-expr-null @ r@ cc-cast-null-fwd >r
  cc-mark-not-lvalue
  cc-last-expr-type !
  cc-last-struct-desc !
  r> cc-last-expr-null !
  r> cc-last-expr-qualified !
  true ;

' cc-try-cast is cc-try-cast-fwd

\ ===========================================================================
\ Switch-scrutinee unwind
\ ===========================================================================
\ cc-parse-switch (112-cc-stmt.fth) parks the outer rbx with
\ `push rbx` and restores it with `pop rbx` at the switch's end label.  Any
\ statement that jumps out of the switch body without passing the end label —
\ return, continue, goto — must first emit compensating pops, or each
\ traversal leaks 8 bytes of stack per open switch (and return hands the
\ caller a clobbered callee-saved rbx).
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

\ cc-emit-switch-unwind ( n -- )  Emit n `pop rbx` instructions.
: cc-emit-switch-unwind                           ( n -- )
  begin,
    dup [lit] 0 >
  while,
    cc-emit-pop-rbx
    1-
  repeat,
  drop ;

\ cc-parse-return ( -- )  "return" already consumed; parse [expr] ';'.
\ Bare `return;` (no expression) is legal C — emit rax := 0 + epilogue.
\ Peek the next token: if it's ';' the peek already consumed it, so do NOT
\ call cc-expect-punct-c again.  Otherwise putback and parse the expression.
\ Either way, unwind any open switch scrutinees so rbx is restored before
\ the epilogue's ret.
defer cc-value-return-fwd
' cc-emit-mov-rax-rdi is cc-value-return-fwd
\ A target may reject a result shape before any conversion is emitted.
: cc-return-shape-default ( type descriptor type descriptor -- ) 2drop 2drop ;
defer cc-return-shape-fwd
' cc-return-shape-default is cc-return-shape-fwd

: cc-parse-return
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] ; = and if,
    cc-emit-xor-rax-rax                           \ rax := 0 (no value returned)
    cc-switch-depth @ cc-emit-switch-unwind
    cc-emit-epilogue
  else,
    cc-putback-token
    cc-parse-expr
    cc-target-lp64 @ if,
      cc-last-expr-type @ cc-last-struct-desc @
      cc-native-return-type @ cc-native-return-desc @ cc-return-shape-fwd
      cc-last-expr-type @ cc-native-return-type @ cc-emit-convert-value
    then,
    cc-value-return-fwd                           \ result -> rax (SYS-V)
    cc-switch-depth @ cc-emit-switch-unwind
    cc-emit-epilogue
    [char] ; cc-expect-punct-c
  then, ;

\ Bind the expression parser's native sizeof type queries after declaration parsing.
: cc-native-sizeof-type cc-parse-type-name cc-cast-desc @ ;
' cc-type-start? is cc-sizeof-type-start-fwd
' cc-native-sizeof-type is cc-sizeof-type-fwd
