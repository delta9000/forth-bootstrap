\ 100-cc-expr.fth — recursive-descent expression parser for the C subset.
\ Emits code that leaves the expression's value in rdi.  Uses 090-cc-emit.fth's
\ instruction encoders.
\
\ Expression grammar, loosest-binding first (one cc-parse-LEVEL word each):
\   expr    := assign                                 \ then materialize
\   assign  := ternary (ASSIGN-OP assign)?            \ = += -= *= /= %= <<= >>= &= |= ^=
\   ternary := log-or ('?' assign ':' assign)?
\   log-or  := log-and ('||' log-and)*
\   log-and := bit-or ('&&' bit-or)*
\   bit-or  := bit-xor ('|' bit-xor)*
\   bit-xor := bit-and ('^' bit-and)*
\   bit-and := eq ('&' eq)*
\   eq      := rel (('=='|'!=') rel)*
\   rel     := shift (('<'|'<='|'>'|'>=') shift)*
\   shift   := add (('<<'|'>>') add)*
\   add     := mul (('+'|'-') mul)*
\   mul     := unary (('*'|'/'|'%') unary)*
\   unary   := ('*'|'&'|'-'|'!'|'~'|'++'|'--') unary | 'sizeof' '(' ... ')'
\            | primary
\   primary := (NUMBER | CHAR | STRING | IDENT | IDENT '(' args ')'
\               | IDENT '[' expr ']' | '(' expr ')')
\              ('.' IDENT | '->' IDENT | '[' expr ']' | '++' | '--')*
\
\ Tokens come from the lexer's interface (050-cc-lex.fth): cc-next-token-keep
\ reads the next one, and cc-putback-token hands the current one back when a
\ parser has read one token too many.
\
\ Depends on 010-lib.fth, 030-cc-io.fth, 050-cc-lex.fth, 060-cc-types.fth, 070-cc-sym.fth,
\ 090-cc-emit.fth.

\ ===========================================================================
\ Forward references.  The grammar is recursive: a primary's '(' expr ')'
\ and a call's arguments re-enter the whole grammar, and the ternary's arms
\ parse assignments.  cc-parse-expr and cc-parse-assign are defined near the
\ end of this file, so the words before them call these deferred words
\ (010-lib.fth), which the last lines of the file fill in.  A cast needs
\ the type parser of 110-cc-decl.fth, which fills in cc-try-cast-fwd.
\ ===========================================================================

defer cc-parse-expr-fwd                           \ runs cc-parse-expr
defer cc-parse-comma-fwd                          \ native comma expressions, no materialize
defer cc-parse-assign-fwd                         \ runs cc-parse-assign
defer cc-try-cast-fwd                             \ runs cc-try-cast (110)
defer cc-parse-unary-fwd                          \ runs cc-parse-unary
defer cc-type-start?                    \ current token starts a type?
defer cc-sizeof-type-fwd                          \ current type token -> ty desc
defer cc-parse-const-fwd                          \ constant expression evaluator
variable cc-expr-unevaluated
variable cc-native-static-init                    \ restrict runtime lowering to static constants

: cc-check-static-init
  cc-native-static-init @ cc-expr-unevaluated @ 0= and if,
    [lit] 219 cc-die
  then, ;

\ ===========================================================================
\ Token tests.  Is the current token this punctuation, or this keyword?
\ ===========================================================================

\ cc-tok-punct? ( code -- f )  True if the current token is punctuation code
\ (a character such as [char] ( or a pt-* constant such as pt-arrow).
: cc-tok-punct?  tok-kind @ tk-punct =  swap tok-num @ =  and ;

\ cc-tok-kw? ( id -- f )  True if the current token is the keyword id (kw-*).
: cc-tok-kw?  tok-kind @ tk-kw =  swap tok-kw-id @ =  and ;

\ ===========================================================================
\ Lvalue tracking for assignment, address-of, and dereference.
\ ===========================================================================
\ Every parse function leaves a value in rdi and four facts about it here.
\ The cc-mark words below write the kind and slot and clear the struct
\ descriptor and the type, which the parser sets afterwards when it knows
\ them; cc-emit-materialize is the only other writer of the kind.
\
\   cc-last-lvalue-kind  what rdi holds — one of the lv-* constants:
\       lv-value      a value; not assignable
\       lv-local      a local's value, already loaded; the local is
\                     cc-last-ident-slot, so `x = ...` stores back there
\       lv-deref      the ADDRESS of a qword that has not been loaded yet
\       lv-deref-byte the ADDRESS of a single byte (a char) not loaded yet
\     A consumer that wants the value calls cc-emit-materialize, which loads
\     through a pending address; assignment instead stores through it.
\   cc-last-ident-slot   slot index of an lv-local (-1 otherwise).
\   cc-last-struct-desc  struct descriptor of a struct or struct-pointer
\                        value (0 if none), for a following '.' / '->'.
\   cc-last-expr-type    encoded C type (ty-base + ptr-depth) of the value,
\                        0 if unknown.  A following '[' or unary '*' reads it
\                        to pick byte or qword stride and width.
\
\ A binary operator's result is a plain value: it marks lv-value, which
\ clears all four.  cc-parse-assign reads kind and slot once, right after
\ parsing the left side, and keeps them on the data stack while the right
\ side's parse overwrites them.

[lit] 0 constant lv-value
[lit] 1 constant lv-local
[lit] 2 constant lv-deref
[lit] 3 constant lv-deref-byte
[lit] 4 constant lv-temporary                     \ non-lvalue record or materialized member

variable cc-last-lvalue-kind                       \ lv-value .. lv-deref-byte
variable cc-last-ident-slot
variable cc-last-expr-qualified
variable cc-last-field-rec                         \ 0 or aggregate field metadata
variable cc-last-struct-desc
variable cc-last-expr-type
variable cc-last-expr-null
variable cc-last-expr-array-len                    \ undecayed array length for sizeof
variable cc-last-expr-array-inner                  \ row width for a two-dimensional array

\ cc-mark ( slot kind -- )  Record kind and slot; clear desc and type.
: cc-mark
  cc-last-lvalue-kind !
  cc-last-ident-slot !
  [lit] 0 cc-last-expr-qualified !
  [lit] 0 cc-last-field-rec !
  [lit] 0 cc-last-struct-desc !
  [lit] 0 cc-last-expr-type !
  [lit] 0 cc-last-expr-null !
  [lit] 0 cc-last-expr-array-len !
  [lit] 0 cc-last-expr-array-inner ! ;

\ cc-mark-not-lvalue ( -- )  rdi holds a plain value.
: cc-mark-not-lvalue     true lv-value cc-mark ;

\ cc-mark-local-lvalue ( slot -- )  rdi holds the loaded value of local slot.
: cc-mark-local-lvalue   lv-local cc-mark ;

\ cc-mark-deref ( byte? -- )  rdi holds an address not yet loaded; byte? is
\ true when it addresses a single byte (`s[i]` or `*s` with s a char*).
: cc-mark-deref
  if, lv-deref-byte else, lv-deref then,
  true swap cc-mark ;

\ cc-deref-pending? ( -- f )  True if rdi holds an address not yet loaded.
: cc-deref-pending?
  cc-last-lvalue-kind @ lv-deref =
  cc-last-lvalue-kind @ lv-deref-byte = or ;

\ Native expression metadata uses the existing encoded type plus descriptor.
\ A plain aggregate is represented by its address, never by its first word.
: cc-expr-symbol-desc                             ( id -- desc )
  dup cc-sym-type-of ty-base dup ty-struct = over ty-array = or swap ty-func = or if,
    cc-sym-struct-desc-of
  else, drop [lit] 0 then, ;

: cc-expr-type-size                               ( ty desc -- bytes )
  over ty-base ty-array = if,
    over ty-ptr if, drop ty-size else, nip cc-ad-size then, exit,
  then,
  over ty-base ty-struct = over [lit] 0 <> and
  [lit] 0 = if, drop ty-size exit, then,
  over ty-ptr if, drop ty-size else, nip cc-sd-total-size then, ;

: cc-expr-pointee-type                            ( ty -- ty' )
  dup ty-ptr if, [lit] 1 - then, ;

: cc-expr-pointee-size                            ( ty desc -- bytes )
  \ GNU C treats void-pointer arithmetic as byte arithmetic. Keep this
  \ separate from ty-size(void), which is also used by sizeof.
  over ty-base ty-void = if,
    over ty-ptr [lit] 1 = if, 2drop [lit] 1 exit, then,
  then,
  swap cc-expr-pointee-type swap cc-expr-type-size ;

: cc-mark-int-value                               ( -- )
  cc-mark-not-lvalue
  ty-int [lit] 0 ty-make cc-last-expr-type ! ;

: cc-unary-type                                  ( ty -- promoted-ty )
  dup ty-ptr if, exit, then,
  dup ty-size [lit] 4 < if, drop ty-int [lit] 0 ty-make then, ;

: cc-mark-typed-value                             ( ty desc -- )
  cc-mark-not-lvalue
  cc-last-struct-desc ! cc-last-expr-type ! ;

\ Typed value operations share the historical encoders until a target binds them.
: cc-value-literal [lit] 0 ;
: cc-value-ternary-split [lit] 0 ;
\ A record conditional consumes saved left metadata and the true-arm fixup,
\ patches the join and publishes its value. Scalars leave both in place.
: cc-aggregate-ternary [lit] 0 ;
\ Integer-only consumers have a distinct check from scalar load/store support.
: cc-value-integer-use drop ;
: cc-value-shape ( source descriptor destination descriptor -- ) 2drop 2drop ;
: cc-value-init ( source destination -- ) 2drop ;

: cc-opaque-scalar ( type descriptor -- flag ) 2drop [lit] 0 ;

: cc-mark-typed-deref                             ( ty desc -- )
  over ty-base ty-array = if,
    over ty-ptr 0= if,
      nip dup cc-ad-count >r dup cc-ad-inner >r
      dup cc-ad-type [lit] 1 + swap cc-ad-desc cc-mark-typed-value
      r> cc-last-expr-array-inner ! r> cc-last-expr-array-len ! exit,
    then,
  then,
  over ty-base ty-func = if,
    over ty-ptr 0= if, cc-mark-typed-value exit, then,
  then,
  over ty-base ty-struct = over [lit] 0 <> and
  if,
    over ty-ptr 0= if,
      2dup cc-opaque-scalar 0= if, cc-mark-typed-value exit, then,
    then,
  then,
  over ty-size [lit] 1 = cc-mark-deref
  cc-last-struct-desc ! cc-last-expr-type ! ;

\ cc-emit-materialize ( -- )  If rdi holds an address not yet loaded, load
\ through it (one byte or eight) so rdi holds the value, and mark it a plain
\ value.  The struct descriptor and type describe the value either way, so
\ they are kept.  A no-op for lv-value and lv-local.
\ Record members can override scalar storage without changing ordinary lvalues.
: cc-field-load ( ty rec -- ) drop cc-emit-load-typed-via-rdi ;
: cc-field-store ( ty rec -- ) drop cc-emit-store-typed-via-rcx ;
: cc-field-value-type ( ty rec -- ty ) drop ;
: cc-field-use ( rec -- ) drop ;

: cc-emit-materialize
  cc-deref-pending? if,
    cc-check-static-init
    cc-last-expr-type @ cc-last-field-rec @ cc-field-load
    cc-last-expr-type @ cc-last-field-rec @ cc-field-value-type cc-last-expr-type !
    true cc-last-ident-slot !
    lv-value cc-last-lvalue-kind !
  then, ;

\ ===========================================================================
\ Struct-field name lookup.
\ ===========================================================================
\ Walks the descriptor's field array and returns the first matching field's
\ byte offset, leaving its pointee desc and encoded type in cc-ff-result-desc
\ and cc-ff-result-type for the caller.  Dies with code 90 if no field
\ matches (compile-time error: field not found).  Uses globals to stash the
\ needle so the loop body has predictable stack effect.

variable cc-ff-needle-addr
variable cc-ff-needle-len
variable cc-ff-desc
variable cc-ff-result-desc                           \ matched field's pointee desc (0 if not a struct ptr)
variable cc-ff-result-type                           \ matched field's encoded type (ty-base + ptr-depth)
variable cc-ff-result-array                          \ matched field's inline array length
variable cc-ff-result-record

\ cc-find-field ( name-addr name-len desc -- offset )
: cc-find-field
  cc-ff-desc           !
  cc-ff-needle-len     !
  cc-ff-needle-addr    !
  \ Loop i = 0..field-count-1.
  cc-ff-desc @ cc-sd-field-count                    ( count )
  [lit] 0                                            ( count i )
  begin,
    over over >                                      ( count i count>i? )
  while,
    \ Compare names at field i.
    cc-ff-desc @ over cc-sd-field-rec                ( count i rec )
    dup cc-sf-name-len cc-ff-needle-len @ = if,
      dup cc-sf-name-addr                           ( count i rec entry-addr )
      cc-ff-needle-addr @ swap                      ( count i rec needle entry )
      cc-ff-needle-len  @                           ( count i rec needle entry u )
      bytes-eq if,                                  ( count i rec )
        dup cc-ff-result-record !
        dup cc-sf-desc cc-ff-result-desc !
        dup cc-sf-type cc-ff-result-type !
        dup cc-sf-array-len cc-ff-result-array !
        cc-sf-offset nip nip exit,                  ( offset )
      then,
    then,
    drop                                            ( count i )
    1+                                              ( count i+1 )
  repeat,
  [lit] 90 cc-die ;

\ ===========================================================================
\ Function calls: `NAME ( args )`.  cc-parse-primary calls cc-parse-call
\ once it has seen an identifier followed by '('.
\ ===========================================================================

\ cc-emit-call-vaddr ( target-vaddr -- )  Emit `call <abs-target>` (5 bytes).
\ rel32 = target_vaddr - (callsite_after_E8 + 4) = target - (callsite_vaddr+5)
\ where callsite_vaddr = cc-here-vaddr at the moment of E8.
: cc-emit-call-vaddr
  [lit] 232 cc-emit-byte                          \ E8 opcode
  \ At this point cc-out-pos@ points at the rel32 slot's first byte.
  \ rel32 = target - (cc-here-vaddr + 4)
  cc-here-vaddr [lit] 4 + -                       ( rel32 )
  cc-emit-4le ;

: cc-native-reverse-args                         ( n -- )
  [lit] 0
  begin, over [lit] 2 / over > while,
    dup [lit] 8 * >r
    over 1- over - [lit] 8 * r> swap cc-native-swap-args
    1+
  repeat, 2drop ;

: cc-native-parse-args                           ( -- n )
  [lit] 0
  cc-next-token-keep
  [char] ) cc-tok-punct? if, exit, then,
  cc-putback-token
  begin,
    cc-parse-assign-fwd cc-emit-materialize
    cc-last-expr-type @ dup ty-base ty-struct = swap ty-ptr 0= and if,
      [lit] 212 cc-die
    then,
    cc-emit-push-rdi 1+
    cc-next-token-keep [char] , cc-tok-punct? 0=
  until,
  [char] ) cc-tok-punct? 0= if, [lit] 121 cc-die then,
  dup cc-native-reverse-args ;

: cc-native-call                           ( id -- )
  cc-check-static-init
  dup cc-sym-kind-of sk-func <> if,
    dup cc-sym-kind-of sk-local = if,
      cc-sym-val-of cc-emit-load-local
    else,
      cc-sym-val-of cc-emit-global-ref cc-emit-load-via-rdi
    then,
    cc-emit-push-rdi
    cc-native-parse-args
    dup cc-native-load-call-target cc-emit-call-rax
    1+ cc-native-drop-args
  else,
    cc-native-parse-args >r
    dup cc-sym-val-of [lit] 0 = if,
      cc-emit-call-rel32-placeholder
      cc-expr-unevaluated @ if,
        2drop
      else, swap cc-sym-call-fixups cc-add-fixup-to-list then,
    else,
      cc-sym-val-of cc-emit-call-vaddr
    then,
    r> cc-native-drop-args
  then,
  cc-emit-mov-rdi-rax ;

: cc-native-indirect                         ( -- )
  cc-check-static-init
  cc-emit-materialize cc-emit-push-rdi
  cc-native-parse-args
  dup cc-native-load-call-target cc-emit-call-rax
  1+ cc-native-drop-args
  cc-emit-mov-rdi-rax
  ty-int [lit] 0 ty-make [lit] 0 cc-mark-typed-value ;

\ Optional ABI hooks preserve the native default until an explicit opt-in.
: cc-native-call-result ( id -- ty desc )
  dup cc-sym-kind-of sk-func = if, dup cc-sym-type-of
  else, ty-int [lit] 0 ty-make then,
  swap cc-expr-symbol-desc ;
: cc-native-function-desc drop [lit] 0 ;

\ cc-parse-call ( id -- )  The '(' has been consumed.  Parse the arguments,
\ emit the call, and leave the result in rdi.
: cc-parse-call cc-native-call ;

\ ===========================================================================
\ cc-parse-primary: the operand, then its postfix operators
\ ===========================================================================
\ A primary is an operand (a literal, a name, or a parenthesised expression)
\ followed by any number of postfix operators ('.' '->' '[' '++' '--').
\ Each word below handles one form and returns with exit, as soon as it has
\ compiled it.  Each failure dies through cc-die (020-cc-arena.fth) with its
\ own code; Appendix G of the book lists them.

\ cc-parse-string-literal ( -- )  The current token is a string literal.
\ We emit the bytes inline in the code stream and jump over them, then load
\ their absolute vaddr into rdi:
\     jmp +N            E9 <rel32>          (5 bytes; rel32 patched)
\     <decoded string bytes + NUL>
\   skip:
\     movabs rdi, vaddr 48 BF <imm64>       (10 bytes)
\ Native strings concatenate adjacent tokens after escape decoding. Each
\ piece's temporary terminator is removed; exactly one final NUL remains.
\ Output positions count decoded bytes, including any explicit embedded NUL.
: cc-native-string
  cc-emit-jmp-rel32-placeholder
  cc-here-vaddr swap                              ( str-vaddr fixup-off )
  cc-out-pos @ >r
  begin,
    tok-str-addr @ tok-str-len @ cc-emit-string-bytes
    [lit] 1 cc-out-pos -!
    cc-next-token-keep
    tok-kind @ tk-str <>
  until,
  cc-putback-token
  [lit] 0 cc-emit-byte
  cc-out-pos @ r> - cc-last-expr-array-len !
  cc-patch-rel32-to-here
  cc-emit-movabs-rdi-imm64 ;


: cc-parse-string-literal cc-native-string ;

\ cc-parse-func-ref ( id -- )  A function name as a value — `op = square;`.
\ Load the function's absolute vaddr into rdi via movabs.  Result is not an
\ lvalue.  When val == 0 the function is still a forward prototype; emit a
\ 10-byte movabs placeholder and thread the imm64 patch-offset onto its
\ cc-sym-addr-fixups list so cc-parse-function can patch it once the real
\ vaddr is known.  Without this, M2-Planet code like
\ `common_recursion(expression)` (where `expression` is forward-declared)
\ loads 0 into rdi and crashes at the indirect call.
: cc-parse-func-ref
  dup cc-native-function-desc >r
  dup cc-sym-val-of [lit] 0 = if,
    cc-emit-movabs-rdi-imm64-placeholder          ( id patch-off )
    cc-expr-unevaluated @ if,
      2drop
    else,
      swap cc-sym-addr-fixups                     ( patch-off list-cell )
      cc-add-fixup-to-list
    then,
  else,
    cc-sym-val-of cc-emit-movabs-rdi-imm64
  then,
  ty-func [lit] 1 ty-make r> cc-mark-typed-value ;

\ cc-parse-global-ref ( id -- )  A file-scope global.  Emit movabs rdi,
\ <vaddr-placeholder> with a deferred fixup.  Scalar globals are
\ deref-pending lvalues (lv-deref); array globals decay to their address
\ (lv-value).
\
\ The type decides which extra fact the symbol carries (070):
\   ty-struct base -> cc-sym-struct-desc-of (NOT an array length).
\   any other      -> cc-sym-array-len-of (>0 for arrays, 0 otherwise).
: cc-parse-global-ref
  dup cc-sym-qualified cell[] @ >r
  dup cc-sym-array-inner-of >r
  dup cc-sym-val-of cc-emit-global-ref
  dup cc-sym-type-of
  over cc-expr-symbol-desc
  rot cc-sym-array-len-of dup if,                ( ty desc n )
    >r swap [lit] 1 + swap cc-mark-typed-value
    r> cc-last-expr-array-len !
  else,
    drop cc-mark-typed-deref
  then,
  r> cc-last-expr-array-inner !
  r> cc-last-expr-qualified ! ;

\ cc-parse-local-ref ( id -- )  A local: struct, struct pointer, array or
\ scalar, told apart by its type.

: cc-parse-local-ref
  dup cc-sym-qualified cell[] @ >r
  cc-check-static-init
  dup cc-sym-array-inner-of >r
  dup cc-sym-array-len-of
  over cc-sym-type-of ty-base ty-struct =
  over [lit] 0 <> or if,                        ( id n )
    over cc-sym-type-of ty-ptr 0= over [lit] 0 <> or if,
      >r dup cc-sym-val-of cc-emit-lea-rdi-local
      dup cc-sym-type-of swap cc-expr-symbol-desc
      r@ if, swap [lit] 1 + swap then,
      cc-mark-typed-value
      cc-last-expr-type @ cc-last-struct-desc @ cc-opaque-scalar if,
        lv-deref cc-last-lvalue-kind !
      then,
      r> cc-last-expr-array-len !
      r> cc-last-expr-array-inner ! r> cc-last-expr-qualified ! exit,
    then,
  then,
  drop
  dup cc-sym-val-of dup cc-mark-local-lvalue
  over cc-sym-type-of cc-native-local-load
  dup cc-sym-type-of cc-last-expr-type !
  cc-expr-symbol-desc cc-last-struct-desc !
  r> cc-last-expr-array-inner ! r> cc-last-expr-qualified ! ;

\ cc-parse-ident ( -- )  The current token is an identifier.  Look it up,
\ then peek one token to tell a call, a subscript and a plain reference
\ apart.
\ Optional target intrinsics consume the complete call when handled.
: cc-native-intrinsic [lit] 0 ;

: cc-native-unknown-ident true ;

: cc-native-call-qualified drop [lit] 0 ;

: cc-parse-ident
  cc-native-intrinsic if, exit, then,
  tok-str-addr @ tok-str-len @ cc-sym-find        ( id | -1 )
  dup 0< if, drop cc-native-unknown-ident then,
  dup 0< if,
    drop
    [lit] 93 cc-die
  then,
  \ Enum constants resolve to their integer value (mov rdi, imm32).
  \ Handle this BEFORE the suffix peek so RED, GREEN etc. work in any
  \ expression context — they're never callable / indexable / assignable.
  dup cc-sym-kind-of sk-enum = if,
    cc-sym-val-of cc-emit-mov-rdi-imm32
    cc-mark-int-value exit,
  then,
  cc-next-token-keep                              \ peek the suffix
  lparen cc-tok-punct? if,
    \ A call.  cc-parse-call consumes the '(' (already peeked), parses
    \ the arguments, emits the call, and leaves the result in rdi.
    dup cc-native-call-qualified >r
    dup cc-native-call-result swap >r >r
    cc-parse-call
    r> r> swap cc-mark-typed-value
    r> cc-last-expr-qualified ! exit,
  then,
  \ A plain reference.  Put back the peeked token.
  cc-putback-token
  dup cc-sym-kind-of sk-func   = if, cc-parse-func-ref   exit, then,
  dup cc-sym-kind-of sk-global = if, cc-parse-global-ref exit, then,
  dup cc-sym-kind-of sk-local  = if, cc-parse-local-ref  exit, then,
  drop
  [lit] 95 cc-die ;

\ cc-parse-paren ( -- )  '(' expr ')'.  Parentheses only group: the inner
\ expression's lvalue kind, slot, type and struct descriptor are left as
\ its parse set them, so `(*p)++`, `(x) = 1` and `(p)->f` work.
: cc-parse-paren
  cc-parse-comma-fwd
  cc-next-token-keep
  [char] ) cc-tok-punct? 0= if,
    [lit] 96 cc-die
  then, ;

\ cc-parse-operand ( -- )  Read one token and compile the operand it starts:
\ a literal, a name, a cast or a parenthesised expression.
: cc-parse-operand
  cc-next-token-keep
  cc-value-literal if, exit, then,
  tok-kind @ tk-num = if,
    cc-integer-literal-type cc-last-expr-type !
    tok-num @ 0= cc-last-expr-null !
    tok-num @ cc-emit-mov-rdi-int exit,           \ widen to imm64 if out of imm32 range
  then,
  tok-kind @ tk-chr = if,
    \ Character literal — value is in tok-num just like a number.
    ty-int [lit] 0 ty-make cc-last-expr-type !
    tok-num @ 0= cc-last-expr-null !
    tok-num @ cc-emit-mov-rdi-imm32 exit,
  then,
  tok-kind @ tk-str   = if,
    \ A string literal is a char*: "abc"[1] is one byte.
    cc-parse-string-literal
    ty-char [lit] 1 ty-make cc-last-expr-type ! exit,
  then,
  tok-kind @ tk-ident = if, cc-parse-ident          exit, then,
  lparen cc-tok-punct? if,
    cc-try-cast-fwd if, exit, then,              \ '(' TYPE ')' operand
    cc-parse-paren exit,
  then,
  [lit] 97 cc-die ;

variable cc-change-qualified
variable cc-change-type
variable cc-change-desc
variable cc-change-field
variable cc-change-postfix
variable cc-change-delta

\ Validate before inspecting lvalue form: long double uses an address value.
: cc-change-check cc-last-expr-type @ cc-value-integer-use ;

\ Update RDI's value; the shared caller saves the address and old payload.
: cc-change-value
  cc-change-type @ ty-ptr if,
    cc-change-type @ cc-change-desc @ cc-expr-pointee-size
  else, [lit] 1 then,
  cc-change-delta @ * cc-emit-add-rdi-imm32
  \ The sum has the promoted type; converting it, not truncating it, lets a
  \ _Bool's b++ and b-- produce 1 and !b as C requires.
  cc-change-type @ dup cc-unary-type swap cc-emit-convert-value ;

\ cc-native-inc-dec ( delta postfix? -- )  Mutate one typed lvalue.
: cc-native-inc-dec
  cc-check-static-init cc-change-check
  cc-change-postfix ! cc-change-delta !
  cc-last-expr-qualified @ cc-change-qualified !
  cc-last-expr-type @ cc-change-type !
  cc-last-struct-desc @ cc-change-desc !
  cc-last-field-rec @ cc-change-field !
  cc-last-lvalue-kind @ lv-local = if,
    cc-last-ident-slot @ cc-emit-lea-rdi-local
  else,
    cc-deref-pending? 0= if, [lit] 113 cc-die then,
  then,
  cc-emit-push-rdi
  cc-change-type @ cc-change-field @ cc-field-load
  cc-change-postfix @ if, cc-emit-push-rdi then,
  cc-change-value
  cc-change-postfix @ if, cc-emit-pop-rdx then,
  cc-emit-pop-rcx
  cc-change-type @ cc-change-field @ cc-field-store
  cc-change-postfix @ if, cc-emit-mov-rdi-rdx then,  \ rdi := the old value
  cc-change-type @ cc-change-field @ cc-field-value-type
  cc-change-desc @ cc-mark-typed-value
  cc-change-qualified @ cc-last-expr-qualified ! ;

\ cc-parse-postfix-inc-dec ( op -- )  Postfix '++' / '--' on an lvalue.
\ rdi keeps the old value, which is not an lvalue but keeps the operand's
\ type, so `*s++` on a char* loads one byte.
: cc-parse-postfix-inc-dec
  pt-plus-plus = if, [lit] 1 else, [lit] 0 [lit] 1 - then,
  true cc-native-inc-dec ;

: cc-parse-postfix-index
  cc-last-expr-qualified @ >r
  \ An inline matrix already denotes its storage. Subscript it without
  \ manufacturing a pointer-to-row, which would discard qualification.
  cc-last-expr-array-len @ 0= if, cc-emit-materialize then,
  cc-last-expr-type @ cc-last-struct-desc @      ( ty desc )
  cc-last-expr-array-inner @ >r
  cc-emit-push-rdi
  cc-parse-expr-fwd
  cc-last-expr-type @ cc-value-integer-use
  2dup cc-expr-pointee-size
  r@ if, r@ * then,
  cc-emit-scale-rdi
  cc-emit-pop-rcx cc-emit-add-rdi-rcx
  cc-next-token-keep
  [char] ] cc-tok-punct? 0= if, [lit] 99 cc-die then,
  r@ if,
    cc-mark-typed-value
    r> cc-last-expr-array-len !
  else,
    r> drop swap cc-expr-pointee-type swap cc-mark-typed-deref
  then,
  r> cc-last-expr-qualified ! ;

\ cc-parse-postfix-field ( op -- )  '.' or '->' followed by a field name.
: cc-parse-postfix-field
  dup [char] . = cc-last-lvalue-kind @ lv-temporary = and >r
  cc-last-struct-desc @ [lit] 0 = if,
    [lit] 100 cc-die
  then,
  \ '->': rdi must hold the pointer's value.  A struct-pointer local is
  \ already loaded (lv-local, materialize is a no-op); a struct-pointer
  \ global or field is still an address (lv-deref), so load it.
  \ '.': rdi holds the struct's base address (lv-value); no load.
  \ Materialize keeps cc-last-struct-desc, which the lookup reads.
  pt-arrow = if,
    cc-emit-materialize
  then,
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 101 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-last-struct-desc @
  cc-find-field                                   ( offset )
  cc-emit-add-rdi-imm32
  cc-last-expr-qualified @ >r
  cc-ff-result-type @ cc-ff-result-desc @
  cc-ff-result-array @ if,
    swap [lit] 1 + swap cc-mark-typed-value
    cc-ff-result-array @ cc-last-expr-array-len !
    cc-ff-result-record @ cc-sf-array-inner cc-last-expr-array-inner !
  else, cc-mark-typed-deref then,
  cc-ff-result-record @ cc-last-field-rec !
  cc-ff-result-record @ cc-field-qualified r> or cc-last-expr-qualified !
  \ A scalar member of a non-lvalue record is a value too. Arrays retain
  \ their normal decay into the independent temporary's inline storage.
  r> if,
    cc-last-expr-array-len @ 0= if, cc-emit-materialize then,
    lv-temporary cc-last-lvalue-kind !
  then, ;

\ cc-postfix-op? ( -- f )  True if the current token is a postfix operator.
: cc-postfix-op?
  [char] . cc-tok-punct?
  pt-arrow cc-tok-punct? or
  pt-plus-plus cc-tok-punct? or
  pt-minus-minus cc-tok-punct? or
  [char] [ cc-tok-punct? or
  lparen cc-tok-punct? or ;

\ cc-parse-postfix-ops ( -- )  Zero or more postfix operators applied to
\ the operand just parsed.
: cc-parse-postfix-ops
  begin,
    cc-next-token-keep
    cc-postfix-op?
  while,
    tok-num @                                     ( op )
    dup pt-plus-plus = over pt-minus-minus = or if,
      cc-parse-postfix-inc-dec
    else,
      dup [char] [ = if,
        drop cc-parse-postfix-index
      else,
        dup lparen = if,
          drop cc-native-indirect
        else,
          cc-parse-postfix-field
        then,
      then,
    then,
  repeat,
  cc-putback-token ;                              \ not a postfix operator

\ cc-parse-primary ( -- )  An operand, then zero or more postfix operators.
: cc-parse-primary
  cc-mark-not-lvalue                              \ default: not an lvalue
  cc-parse-operand cc-parse-postfix-ops ;

\ ===========================================================================
\ cc-parse-unary: ('&' unary | '*' unary | primary)
\ ===========================================================================
\ Disambiguation: at unary position, '*' is dereference and '&' is address-of;
\ at binary position (handled by cc-parse-mul) '*' means multiply.
\
\ The address-of operand is restricted to a simple local IDENT; it emits
\ `lea rdi, [rbp - 8*(slot+1)]`.  More complex address expressions such as
\ `&*p` or `&arr[i]` are not implemented.
\
\ For dereference, the operand is parsed as a (recursive) unary expression so
\ `**p` works.  We materialize the operand (turning any pending deref into a
\ loaded value) so rdi holds the *address* that the outer '*' should target,
\ then mark it lv-deref — leaving the load for the consumer.

\ cc-parse-sizeof: `sizeof ( TYPE )` or `sizeof EXPR`.  Called with the
\ `sizeof` keyword already consumed.  Emits the size in bytes as an
\ unsigned long constant; the result is not an lvalue.
\
\ sizeof parses its operand without retaining any emitted code or
\ Native sizeof parses its operand without retaining any emitted code or
\ relocations. An array's length/row metadata prevents its normal decay.
: cc-native-sizeof-expr-size                     ( -- bytes )
  cc-last-field-rec @ cc-field-use
  cc-last-expr-type @ cc-last-struct-desc @
  cc-last-expr-array-len @ if,
    cc-expr-pointee-size cc-last-expr-array-len @ *
    cc-last-expr-array-inner @ if, cc-last-expr-array-inner @ * then,
  else, cc-expr-type-size then, ;


: cc-native-sizeof                              ( -- bytes )
  cc-out-pos @ >r cc-gfixup-count @ >r
  cc-expr-unevaluated @ >r true cc-expr-unevaluated !
  cc-next-token-keep
  lparen cc-tok-punct? if,
    cc-next-token-keep
    cc-type-start? if,
      cc-sizeof-type-fwd cc-expr-type-size
      cc-next-token-keep
      begin, [char] [ cc-tok-punct? while,
        cc-parse-const-fwd *
        cc-next-token-keep
        [char] ] cc-tok-punct? 0= if, [lit] 110 cc-die then,
        cc-next-token-keep
      repeat,
      [char] ) cc-tok-punct? 0= if, [lit] 110 cc-die then,
    else,
      \ `(expr)` is only the primary of a unary operand: postfix operators
      \ after it still apply, so `sizeof (a)[0]` is sizeof ((a)[0]).
      cc-putback-token cc-mark-not-lvalue
      cc-parse-paren cc-parse-postfix-ops
      cc-native-sizeof-expr-size
    then,
  else,
    cc-putback-token cc-parse-unary-fwd
    cc-native-sizeof-expr-size
  then,
  r> cc-expr-unevaluated ! r> cc-gfixup-count ! r> cc-out-pos ! ;

: cc-parse-sizeof
  cc-native-sizeof cc-emit-mov-rdi-int
  ty-ulong [lit] 0 ty-make [lit] 0 cc-mark-typed-value ;

\ cc-parse-prefix-inc-dec ( delta -- )  delta = 1 (for ++) else dec.
\ Called with the '++' / '--' punct ALREADY consumed.  The operand is
\ parsed as a unary expression, which must leave a local or the address
\ of a pointer target, element or field (else die 113).  The result is not
\ an lvalue; it keeps the operand's type.
: cc-parse-prefix-inc-dec                         ( delta -- )
  cc-parse-unary-fwd
  0= if, [lit] 0 [lit] 1 - else, [lit] 1 then,
  [lit] 0 cc-native-inc-dec ;

: cc-array-address ( type descriptor count inner -- type descriptor )
  2drop swap [lit] 1 + swap ;

: cc-parse-unary
  cc-next-token-keep
  kw-sizeof cc-tok-kw? if,
    \ sizeof(TYPE).  The `sizeof` keyword is the current token; we just
    \ leave it as "consumed" (no putback) and dispatch into cc-parse-sizeof.
    cc-parse-sizeof exit,
  then,
  [char] & cc-tok-punct? if,
    cc-parse-unary
    cc-last-lvalue-kind @ lv-temporary = if, [lit] 116 cc-die then,
    cc-last-field-rec @ cc-field-use
    cc-last-lvalue-kind @ lv-local = if,
      cc-last-ident-slot @ cc-emit-lea-rdi-local
    else,
      cc-deref-pending? cc-last-struct-desc @ [lit] 0 <> or
      cc-last-expr-array-len @ [lit] 0 <> or
      cc-last-expr-type @ ty-base ty-func = or
      0= if, [lit] 116 cc-die then,
    then,
    cc-last-expr-array-len @ if,
      cc-last-expr-type @ cc-last-struct-desc @
      cc-last-expr-array-len @ cc-last-expr-array-inner @ cc-array-address
    else,
      cc-last-expr-type @
      dup ty-func [lit] 1 ty-make = cc-last-lvalue-kind @ lv-value = and
      0= if, [lit] 1 + then, cc-last-struct-desc @
    then,
    cc-last-expr-qualified @ >r cc-mark-typed-value
    r> cc-last-expr-qualified ! exit,
  then,
  [char] * cc-tok-punct? if,
    \ '*' = dereference.  The operand's value is the address; the load is
    \ left for the consumer, at the pointee's width.
    cc-parse-unary
    cc-emit-materialize                           \ operand is now a value (an address)
    cc-last-expr-qualified @ >r
    cc-last-expr-type @ cc-expr-pointee-type
    cc-last-struct-desc @ cc-mark-typed-deref
    r> cc-last-expr-qualified ! exit,
  then,
  \ Prefix '++' / '--'.  Bump the operand in place, leave the new value in
  \ rdi.  cc-parse-prefix-inc-dec takes 1 for ++, anything else for --.
  pt-plus-plus   cc-tok-punct? if, [lit] 1 cc-parse-prefix-inc-dec exit, then,
  pt-minus-minus cc-tok-punct? if, [lit] 0 cc-parse-prefix-inc-dec exit, then,
  \ '-', '!' and '~' parse their operand, materialize it, and emit one
  \ operation on rdi ('!' gives rdi := (rdi == 0)).
  [char] - cc-tok-punct? if,
    cc-parse-unary cc-emit-materialize
    cc-last-expr-type @ cc-unary-type
    cc-value-negate dup cc-emit-convert-rdi
    cc-last-struct-desc @ cc-mark-typed-value exit,
  then,
  [char] ! cc-tok-punct? if,
    cc-parse-unary cc-emit-materialize
    cc-value-not cc-mark-int-value exit,
  then,
  [char] ~ cc-tok-punct? if,
    cc-parse-unary cc-emit-materialize
    cc-last-expr-type @ cc-unary-type
    cc-value-complement dup cc-emit-convert-rdi
    [lit] 0 cc-mark-typed-value exit,
  then,
  [char] + cc-tok-punct? if,
    cc-parse-unary cc-emit-materialize
    cc-last-expr-type @ cc-unary-type dup cc-emit-convert-rdi
    cc-last-struct-desc @ cc-mark-typed-value exit,
  then,
  \ Not a unary operator — putback so primary sees the same token.
  cc-putback-token
  cc-parse-primary ;

\ ===========================================================================
\ Arithmetic at compile time
\ ===========================================================================
\ A constant expression (an array size, a case label, an #if line) is
\ computed while compiling, so each operator also needs a Forth word that
\ does what its instructions do at run time, on two 64-bit values.  The
\ seed's / is unsigned and it has no shift or xor, so the signed
\ versions are built here.

: cc-negate  [lit] 0 swap - ;                     ( n -- -n )
: cc-invert  dup nand ;                           ( n -- ~n )
: cc-xor     2dup or >r and cc-invert r> and ;     ( a b -- a^b )
: cc-flag    0= 1+ ;                              \ ( f -- 1|0 ): C truth
: cc-abs     dup 0< if, cc-negate then, ;         ( n -- |n| )

\ cc-divisor ( b -- b )  Die with 124 if a constant divisor is 0.
: cc-divisor  dup 0= if, [lit] 124 cc-die then, ;

\ cc-div ( a b -- q )  Signed division, truncating toward zero like idiv.
\ cc-mod ( a b -- r )  Its remainder, which takes the sign of a.
: cc-div
  cc-divisor
  2dup cc-xor 0< >r  cc-abs swap cc-abs swap /  r> if, cc-negate then, ;
: cc-mod
  cc-divisor
  over 0< >r  cc-abs swap cc-abs swap  2dup / * -  r> if, cc-negate then, ;

\ cc-pow2 ( n -- 2^n )
: cc-pow2
  [lit] 1 swap
  begin, dup while, swap dup + swap 1- repeat,
  drop ;
\ cc-shl ( a n -- a<<n )   cc-sar ( a n -- a>>n ), the sign bit copied in.
: cc-shl  cc-pow2 * ;
: cc-sar
  over 0< if,
    swap cc-invert swap cc-pow2 / cc-invert
  else,
    cc-pow2 /
  then, ;

\ The comparisons answer C's 1 or 0.
: cc-lt  <  cc-flag ;
: cc-gt  >  cc-flag ;
: cc-le  <= cc-flag ;
: cc-ge  >= cc-flag ;
: cc-eq  =  cc-flag ;
: cc-ne  <> cc-flag ;

\ ===========================================================================
\ The binary-operator table
\ ===========================================================================
\ Eight levels of the grammar, mul down to bit-or, have one shape: parse an
\ operand at the next-tighter level, then, while the next token is one of
\ this level's operators, parse another operand and combine the two.  Only
\ the operators and the instructions that combine differ, so those live in
\ this table, one row of five cells per operator:
\
\   op        the operator's punct code (tok-num)
\   compound  the code of its compound assignment (`+` has `+=`); 0 if none
\   level     which level parses it (level-mul .. level-bit-or)
\   emitter   xt of the 090 word that emits rdi := rdi OP rcx
\   evaluator xt of the word above that computes a OP b now
\
\ Each level's parser looks its operators up by op; cc-parse-assign looks
\ `+=` and the rest up by compound, so `a + b` and `a += b` share an
\ emitter.  A row whose op is 0 ends the table.

[lit] 1 constant level-mul                        \ * / %
[lit] 2 constant level-add                        \ + -
[lit] 3 constant level-shift                      \ << >>
[lit] 4 constant level-rel                        \ < > <= >=
[lit] 5 constant level-eq                         \ == !=
[lit] 6 constant level-bit-and                    \ &
[lit] 7 constant level-bit-xor                    \ ^
[lit] 8 constant level-bit-or                     \ |

[lit]  0 constant bo-op                           \ byte offsets within a row
[lit]  8 constant bo-compound
[lit] 16 constant bo-level
[lit] 24 constant bo-emitter
[lit] 32 constant bo-eval
[lit] 40 constant bo-size

\ cc-binop, ( op compound level "emitter" "evaluator" -- )  Lay down one
\ row; the emitter's and the evaluator's names follow in the input.
: cc-binop,  rot , swap , ,  ' ,  ' , ;

create cc-binops
\ op          compound       level                  emitter                evaluator
char *      pt-star-eq     level-mul      cc-binop, cc-emit-imul-rdi-rcx   *
char /      pt-slash-eq    level-mul      cc-binop, cc-emit-idiv-quotient  cc-div
char %      pt-percent-eq  level-mul      cc-binop, cc-emit-idiv-remainder cc-mod
char +      pt-plus-eq     level-add      cc-binop, cc-emit-add-rdi-rcx    +
char -      pt-minus-eq    level-add      cc-binop, cc-emit-sub-rdi-rcx    -
pt-shl      pt-shl-eq      level-shift    cc-binop, cc-emit-shl-rdi-cl     cc-shl
pt-shr      pt-shr-eq      level-shift    cc-binop, cc-emit-sar-rdi-cl     cc-sar   \ signed
char <      [lit] 0        level-rel      cc-binop, cc-emit-cmp-lt         cc-lt
char >      [lit] 0        level-rel      cc-binop, cc-emit-cmp-gt         cc-gt
pt-le       [lit] 0        level-rel      cc-binop, cc-emit-cmp-le         cc-le
pt-ge       [lit] 0        level-rel      cc-binop, cc-emit-cmp-ge         cc-ge
pt-eq-eq    [lit] 0        level-eq       cc-binop, cc-emit-cmp-eq         cc-eq
pt-bang-eq  [lit] 0        level-eq       cc-binop, cc-emit-cmp-ne         cc-ne
char &      pt-amp-eq      level-bit-and  cc-binop, cc-emit-and-rdi-rcx    and
char ^      pt-caret-eq    level-bit-xor  cc-binop, cc-emit-xor-rdi-rcx    cc-xor
char |      pt-pipe-eq     level-bit-or   cc-binop, cc-emit-or-rdi-rcx     or
[lit] 0 ,                                         \ end of table

\ cc-binop-row ( key field -- row | 0 )  The first row whose cell at byte
\ offset field holds key, or 0 when no row does.
: cc-binop-row
  >r cc-binops                                    ( key row ; R: field )
  begin,
    dup bo-op + @                                 \ stop at the end row
  while,
    2dup r@ + @ = if,                             ( key row )
      nip r> drop exit,                           \ found: answer the row
    then,
    bo-size +
  repeat,
  2drop r> drop [lit] 0 ;

\ cc-binop? ( level -- row | 0 )  Read the next token.  If it is one of
\ this level's operators, answer its row; otherwise 0, and the caller
\ puts the token back.
: cc-binop?
  cc-next-token-keep
  tok-kind @ tk-punct <> if,
    drop [lit] 0 exit,                            \ not an operator at all
  then,
  tok-num @ bo-op cc-binop-row                    ( level row | level 0 )
  dup 0= if,
    nip exit,                                     \ no row: answer 0
  then,
  swap over bo-level + @ = if,                    ( row )
    exit,                                         \ ours: answer the row
  then,
  drop [lit] 0 ;                                  \ another level's operator

\ Native arithmetic preserves type information and applies pointer scaling.
\ These temporary cells are only used after recursive operand parsing ends.
variable cc-expr-left-qualified
variable cc-expr-right-qualified
variable cc-expr-left-type
variable cc-expr-left-desc
variable cc-expr-right-type
variable cc-expr-right-desc
variable cc-expr-left-inner
variable cc-expr-left-null
variable cc-expr-right-null
variable cc-expr-right-inner
variable cc-expr-common
variable cc-expr-op-row

: cc-expr-promote                                ( ty -- ty' )
  dup ty-ptr if, exit, then,
  dup ty-size [lit] 4 < if, drop ty-int [lit] 0 ty-make then, ;

\ Equal-size operands differ only in rank and signedness. Long long ranks
\ above every other eight-byte kind, so either long long operand makes the
\ result long long, unsigned when either operand is unsigned (C99 6.3.1.8).
: cc-expr-long-long-common                       ( left right -- ty )
  ty-unsigned? swap ty-unsigned? or if, ty-ullong else, ty-llong then,
  [lit] 0 ty-make ;

: cc-expr-common-type                            ( left right -- ty )
  cc-expr-promote swap cc-expr-promote swap
  over ty-ptr if, drop exit, then,
  dup ty-ptr if, nip exit, then,
  2dup ty-size swap ty-size > if, nip exit, then,
  2dup ty-size swap ty-size < if, drop exit, then,
  over ty-long-long? over ty-long-long? or if,
    cc-expr-long-long-common exit,
  then,
  dup ty-unsigned? if, nip else, drop then, ;


: cc-expr-save-types                             ( left-ty left-desc right-ty right-desc -- )
  cc-expr-right-desc ! cc-expr-right-type !
  cc-expr-left-desc ! cc-expr-left-type !
  cc-expr-left-type @ cc-expr-right-type @ cc-expr-common-type cc-expr-common ! ;

: cc-expr-save-native-types ( left-ty left-desc left-inner left-null qualified -- )
  cc-expr-left-qualified !
  cc-last-expr-qualified @ cc-expr-right-qualified !
  cc-expr-left-null ! cc-last-expr-null @ cc-expr-right-null !
  cc-expr-left-inner !
  cc-last-expr-array-inner @ cc-expr-right-inner !
  cc-last-expr-type @ cc-last-struct-desc @ cc-expr-save-types ;

: cc-expr-common-inner                           ( -- row-width )
  cc-expr-common @ ty-ptr if,
    cc-expr-left-type @ cc-expr-common @ = if,
      cc-expr-left-inner @
    else, cc-expr-right-inner @ then,
  else, [lit] 0 then, ;

: cc-expr-left-step
  cc-expr-left-type @ cc-expr-left-desc @ cc-expr-pointee-size
  cc-expr-left-inner @ if, cc-expr-left-inner @ * then, ;
: cc-expr-right-step
  cc-expr-right-type @ cc-expr-right-desc @ cc-expr-pointee-size
  cc-expr-right-inner @ if, cc-expr-right-inner @ * then, ;

: cc-expr-common-desc                            ( -- desc )
  cc-expr-common @ ty-base dup ty-struct = over ty-func = or swap ty-array = or if,
    cc-expr-left-type @ cc-expr-common @ = if,
      cc-expr-left-desc @
    else, cc-expr-right-desc @ then,
  else, [lit] 0 then, ;

\ cc-native-binop-emit ( -- )  Emit the operation of cc-expr-op-row on the
\ common type in cc-expr-common; every / and %, and /= and %=, comes
\ through here.  The encoders divide the low halves of their register
\ pairs, which is the whole value for every type of 4 bytes or less.  For
\ an 8-byte common type that would be a wrong answer, and there is no
\ 64-bit division to give the right one:
\   long long   the compile stops with error 131.
\   a double    is kept as its bit pattern and has no arithmetic.  tcc's
\               constant folding has such divisions, in code the route
\               never runs.  The program is compiled, and exits with
\               status 125 if it ever gets there
\               (tinycc/mes-libc-native-i386.c's convention for missing
\               floating point).
: cc-native-binop-emit                           ( -- )
  cc-expr-common @ ty-size [lit] 8 = if,
    cc-expr-op-row @ bo-op + @
    dup [char] / = swap [char] % = or if,
      cc-expr-common @ ty-long-long? if, [lit] 131 cc-die then,
      cc-emit-exit-125 exit,
    then,
  then,
  cc-expr-common @ ty-unsigned? if,
    cc-expr-op-row @ bo-op + @
    dup [char] / = if, drop cc-emit-udiv-quotient exit, then,
    dup [char] % = if, drop cc-emit-udiv-remainder exit, then,
    dup pt-shr = if, drop cc-emit-shr-rdi-cl exit, then,
    dup [char] < = if, drop cc-emit-cmp-ult exit, then,
    dup pt-le = if, drop cc-emit-cmp-ule exit, then,
    dup [char] > = if, drop cc-emit-cmp-ugt exit, then,
    dup pt-ge = if, drop cc-emit-cmp-uge exit, then,
    drop
  then,
  cc-expr-op-row @ bo-emitter + @ execute ;

: cc-native-binop-apply                          ( left-ty left-desc left-inner left-null row -- )
  cc-expr-op-row !
  cc-emit-materialize
  cc-expr-save-native-types
  cc-expr-op-row @ bo-level + @ level-shift = if,
    cc-expr-left-type @ cc-expr-promote cc-expr-common !
  then,
  cc-expr-op-row @ bo-level + @ level-add = if,
    cc-expr-left-type @ ty-ptr
    cc-expr-right-type @ ty-ptr 0= and if,
      cc-expr-left-step cc-emit-scale-rdi
    then,
  then,
  cc-emit-mov-rcx-rdi cc-emit-pop-rdi
  cc-expr-op-row @ bo-op + @ [char] + = if,
    cc-expr-left-type @ ty-ptr 0=
    cc-expr-right-type @ ty-ptr [lit] 0 <> and if,
      cc-expr-right-step cc-emit-scale-rdi
    then,
  then,
  cc-expr-left-type @ cc-expr-common @ cc-emit-convert-value
  cc-expr-right-type @ cc-expr-common @ cc-emit-convert-right
  cc-native-binop-emit
  cc-expr-op-row @ bo-op + @ [char] - = if,
    cc-expr-left-type @ ty-ptr cc-expr-right-type @ ty-ptr and if,
      cc-expr-left-step
      dup [lit] 1 <> if,
        cc-emit-push-rdi cc-emit-mov-rdi-int
        cc-emit-mov-rcx-rdi cc-emit-pop-rdi cc-emit-idiv-quotient
      else, drop then,
      ty-long [lit] 0 ty-make cc-expr-common !
    then,
  then,
  cc-expr-op-row @ bo-level + @
  dup level-rel = swap level-eq = or if,
    ty-int [lit] 0 ty-make cc-expr-common !
  then,
  cc-expr-common @ cc-emit-convert-rdi
  cc-expr-common @ cc-expr-common-desc cc-mark-typed-value
  cc-expr-common @ ty-ptr if,
    cc-expr-left-qualified @ cc-expr-right-qualified @ or cc-last-expr-qualified !
  then,
  cc-expr-common-inner cc-last-expr-array-inner ! ;

\ ===========================================================================
\ cc-parse-mul: unary (('*'|'/'|'%') unary)*
\ ===========================================================================

: cc-parse-mul
  cc-parse-unary
  begin,
    level-mul cc-binop? dup                       ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-last-expr-type @ cc-last-struct-desc @ cc-last-expr-array-inner @ cc-last-expr-null @ cc-last-expr-qualified @
    cc-emit-push-rdi                              \ save left
    cc-parse-unary                                \ rdi = right
    r> cc-native-binop-apply
                                                  \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ cc-parse-add: mul (('+'|'-') mul)*
\ ===========================================================================

: cc-parse-add
  cc-parse-mul
  begin,
    level-add cc-binop? dup                       ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-last-expr-type @ cc-last-struct-desc @ cc-last-expr-array-inner @ cc-last-expr-null @ cc-last-expr-qualified @
    cc-emit-push-rdi                              \ save left
    cc-parse-mul                                  \ rdi = right
    r> cc-native-binop-apply
                                                  \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ cc-parse-shift: add (('<<'|'>>') add)*
\ ===========================================================================
\ C puts shift between relational and additive: `a + b << c` is
\ `(a + b) << c`.  Variable-count shifts take the count in rcx (CL).

: cc-parse-shift
  cc-parse-add
  begin,
    level-shift cc-binop? dup                     ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-last-expr-type @ cc-last-struct-desc @ cc-last-expr-array-inner @ cc-last-expr-null @ cc-last-expr-qualified @
    cc-emit-push-rdi                              \ save left
    cc-parse-add                                  \ rdi = right
    r> cc-native-binop-apply
                                                  \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ cc-parse-rel: shift (('<'|'<='|'>'|'>=') shift)*
\ ===========================================================================

: cc-parse-rel
  cc-parse-shift
  begin,
    level-rel cc-binop? dup                       ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-last-expr-type @ cc-last-struct-desc @ cc-last-expr-array-inner @ cc-last-expr-null @ cc-last-expr-qualified @
    cc-emit-push-rdi                              \ save left
    cc-parse-shift                                \ rdi = right
    r> cc-native-binop-apply
                                                  \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ cc-parse-eq: rel (('=='|'!=') rel)*
\ ===========================================================================

: cc-parse-eq
  cc-parse-rel
  begin,
    level-eq cc-binop? dup                        ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-last-expr-type @ cc-last-struct-desc @ cc-last-expr-array-inner @ cc-last-expr-null @ cc-last-expr-qualified @
    cc-emit-push-rdi                              \ save left
    cc-parse-rel                                  \ rdi = right
    r> cc-native-binop-apply
                                                  \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ cc-parse-bit-and: eq ('&' eq)*
\ ===========================================================================
\ This '&' is the binary (infix) bitwise-and.  Unary '&' (address-of) is
\ cc-parse-unary's: operator position vs operand position tells them apart.

: cc-parse-bit-and
  cc-parse-eq
  begin,
    level-bit-and cc-binop? dup                   ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-last-expr-type @ cc-last-struct-desc @ cc-last-expr-array-inner @ cc-last-expr-null @ cc-last-expr-qualified @
    cc-emit-push-rdi                              \ save left
    cc-parse-eq                                   \ rdi = right
    r> cc-native-binop-apply
                                                  \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ cc-parse-bit-xor: bit-and ('^' bit-and)*
\ ===========================================================================

: cc-parse-bit-xor
  cc-parse-bit-and
  begin,
    level-bit-xor cc-binop? dup                   ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-last-expr-type @ cc-last-struct-desc @ cc-last-expr-array-inner @ cc-last-expr-null @ cc-last-expr-qualified @
    cc-emit-push-rdi                              \ save left
    cc-parse-bit-and                              \ rdi = right
    r> cc-native-binop-apply
                                                  \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ cc-parse-bit-or: bit-xor ('|' bit-xor)*
\ ===========================================================================

: cc-parse-bit-or
  cc-parse-bit-xor
  begin,
    level-bit-or cc-binop? dup                    ( row row | 0 0 )
  while,
    >r                                            ( ; R: row )
    cc-emit-materialize                           \ left must be a value
    cc-last-expr-type @ cc-last-struct-desc @ cc-last-expr-array-inner @ cc-last-expr-null @ cc-last-expr-qualified @
    cc-emit-push-rdi                              \ save left
    cc-parse-bit-xor                              \ rdi = right
    r> cc-native-binop-apply
                                                  \ rdi = left OP right
  repeat,
  drop                                            \ cc-binop?'s 0
  cc-putback-token ;                              \ we read one too many

\ ===========================================================================
\ Short-circuit logical && and || — produce 1 or 0 (not the operand).
\ ===========================================================================
\ For `a && b`:
\   eval a; if zero, skip b and produce 0; else eval b; if zero, produce 0;
\   else produce 1.
\
\ Codegen sketch (with three rel32 fixups stashed on rstack):
\   <eval a>
\   test rdi,rdi
\   jz   .false_LHS
\   <eval b>
\   test rdi,rdi
\   jz   .false_RHS
\   mov rdi, 1
\   jmp  .end
\ .false_LHS:
\ .false_RHS:
\   mov rdi, 0
\ .end:
\
\ We push the three fixups onto rstack so the data stack stays clear for the
\ nested parse calls and any pending operator codes.

: cc-parse-log-and
  cc-parse-bit-or
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ pt-and-and = and
  while,
    cc-emit-materialize
    cc-value-test
    cc-emit-jz-rel32-placeholder >r               \ R: fixup-false-LHS
    cc-parse-bit-or
    cc-emit-materialize
    cc-value-test
    cc-emit-jz-rel32-placeholder >r               \ R: f-LHS f-RHS
    [lit] 1 cc-emit-mov-rdi-imm32
    cc-emit-jmp-rel32-placeholder >r              \ R: f-LHS f-RHS f-end
    \ False-target lands here for both fixups.
    r> r>                                         ( f-end f-RHS ; R: f-LHS )
    cc-patch-rel32-to-here                        \ patch f-RHS
    r>                                            ( f-end f-LHS )
    cc-patch-rel32-to-here                        \ patch f-LHS
    [lit] 0 cc-emit-mov-rdi-imm32
    cc-patch-rel32-to-here                        \ patch f-end
    cc-mark-int-value
  repeat,
  cc-putback-token ;

: cc-parse-log-or
  cc-parse-log-and
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ pt-or-or = and
  while,
    cc-emit-materialize
    cc-value-test
    cc-emit-jnz-rel32-placeholder >r              \ R: fixup-true-LHS
    cc-parse-log-and
    cc-emit-materialize
    cc-value-test
    cc-emit-jnz-rel32-placeholder >r              \ R: t-LHS t-RHS
    [lit] 0 cc-emit-mov-rdi-imm32
    cc-emit-jmp-rel32-placeholder >r              \ R: t-LHS t-RHS f-end
    \ True-target lands here for both fixups.
    r> r>                                         ( f-end t-RHS ; R: t-LHS )
    cc-patch-rel32-to-here
    r>                                            ( f-end t-LHS )
    cc-patch-rel32-to-here
    [lit] 1 cc-emit-mov-rdi-imm32
    cc-patch-rel32-to-here                        \ patch f-end
    cc-mark-int-value
  repeat,
  cc-putback-token ;

\ ===========================================================================
\ Ternary  cond '?' then ':' else
\ ===========================================================================
\ Right-associative; the two arms recurse through cc-parse-assign so that
\ chained `a ? b : c ? d : e` parses as `a ? b : (c ? d : e)` and lower-
\ precedence comma-free assignment lives inside an arm.
\
\ Codegen:
\   <eval cond>
\   test rdi,rdi
\   jz   .else
\   <eval then-arm>
\   jmp  .end
\ .else:
\   <eval else-arm>
\ .end:

: cc-parse-ternary
  cc-parse-log-or
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] ? = and if,
    \ '?' — consume and emit branch.
    cc-emit-materialize
    cc-value-test
    cc-emit-jz-rel32-placeholder >r               \ R: f-else
    cc-parse-comma-fwd                            \ then-arm
    cc-emit-materialize
    cc-last-expr-type @ cc-last-struct-desc @ cc-last-expr-array-inner @ cc-last-expr-null @ cc-last-expr-qualified @
    cc-emit-jmp-rel32-placeholder >r              \ R: f-else f-end
    \ Expect ':' — inline check (cc-expect-punct-c lives in 110-cc-decl.fth).
    cc-next-token-keep
    tok-kind @ tk-punct <> tok-num @ [char] : <> or if,
      [lit] 117 cc-die
    then,
    \ Pop fixups: top of rstack is f-end, second is f-else.
    r> r>                                         ( f-end f-else )
    cc-patch-rel32-to-here                        \ patch f-else
    >r
    cc-parse-assign-fwd                         \ else-arm
    cc-emit-materialize
    r> cc-aggregate-ternary 0= if,
      \ The true arm jumps past the false arm and its conversion. Only
      \ after both types are known can either selected value be converted.
      cc-value-ternary-split if,
        >r cc-expr-save-native-types
        cc-expr-right-type @ cc-expr-common @ cc-emit-convert-value
        cc-emit-jmp-rel32-placeholder r> cc-patch-rel32-to-here >r
        cc-expr-left-type @ cc-expr-common @ cc-emit-convert-value
        r> cc-patch-rel32-to-here
      else,
        cc-patch-rel32-to-here
        cc-expr-save-native-types
        cc-expr-common @ cc-emit-convert-rdi
      then,
      cc-expr-common @ cc-expr-common-desc cc-mark-typed-value
      cc-expr-common @ ty-ptr if,
        cc-expr-left-qualified @ cc-expr-right-qualified @ or cc-last-expr-qualified !
      then,
      cc-expr-common-inner cc-last-expr-array-inner !
    then,
  else,
    cc-putback-token
  then, ;

\ ===========================================================================
\ cc-parse-assign: ternary (ASSIGN-OP assign)?
\ ===========================================================================
\ Right-recursive.  After parsing the LHS via cc-parse-ternary, snapshot
\ cc-last-ident-slot on the data stack BEFORE recursing into the RHS (which
\ would otherwise overwrite it).
\
\ We test the next token without immediately committing: if it's '=', we use
\ the snapshot to emit a store; otherwise we put the token back and discard
\ the snapshot.
\
\ NOTE: assignment is right-associative, so the RHS recurses through
\ cc-parse-assign (not cc-parse-eq) — chained `a = b = 1` works.

\ cc-assign-op? ( -- f )  After cc-next-token-keep, returns -1 if the
\ current token is '=' or the compound form of an operator in the table
\ ('+=' '-=' '*=' '/=' '%=' '<<=' '>>=' '&=' '|=' '^=').
: cc-assign-op?
  tok-kind @ tk-punct = if,
    tok-num @ [char] = =
    tok-num @ bo-compound cc-binop-row 0= 0= or
  else,
    [lit] 0
  then, ;

variable cc-assign-qualified
variable cc-assign-type
variable cc-assign-desc
variable cc-assign-op
variable cc-assign-field

\ A target may give compound assignment to a record type its own diagnostic.
: cc-aggregate-compound ( type descriptor -- ) 2drop ;

\ One native store path handles locals, globals, fields and dereferences.
\ Snapshots live on the return stack across the recursive RHS parse.
: cc-parse-native-assign                          ( kind slot -- )
  over lv-temporary = if, [lit] 120 cc-die then,
  cc-check-static-init
  over lv-local = if,
    nip cc-emit-lea-rdi-local
  else,
    drop dup lv-deref = swap lv-deref-byte = or
    cc-last-expr-type @ ty-base ty-struct =
    cc-last-expr-type @ ty-ptr 0= and or
    0= if, [lit] 120 cc-die then,
  then,
  cc-last-expr-qualified @ >r
  cc-last-field-rec @ >r
  cc-last-expr-type @ >r cc-last-struct-desc @ >r tok-num @ >r
  cc-emit-push-rdi
  r@ [char] = <> if,
    cc-last-expr-type @ cc-last-field-rec @ cc-field-load
    cc-emit-push-rdi
  then,
  cc-parse-assign-fwd cc-emit-materialize
  r> cc-assign-op ! r> cc-assign-desc ! r> cc-assign-type !
  r> cc-assign-field ! r> cc-assign-qualified !
  cc-assign-op @ [char] = = if,
    cc-last-expr-type @ cc-last-struct-desc @
    cc-assign-type @ cc-assign-desc @ cc-value-shape
  then,
  cc-assign-type @ ty-base ty-struct = cc-assign-type @ ty-ptr 0= and
  cc-assign-type @ cc-assign-desc @ cc-opaque-scalar 0= and if,
    cc-assign-op @ [char] = <> if,
      cc-assign-type @ cc-assign-desc @ cc-aggregate-compound
      [lit] 120 cc-die
    then,
    cc-emit-mov-rsi-rdi
    cc-emit-pop-rdi cc-emit-push-rdi               \ rsi=source; rdi=destination
    cc-assign-type @ cc-assign-desc @ cc-expr-type-size cc-emit-rep-count-rcx
    [lit] 243 cc-emit-byte [lit] 164 cc-emit-byte  \ rep movsb
    cc-emit-pop-rdi
    cc-assign-type @ cc-assign-desc @ cc-mark-typed-value
    cc-assign-qualified @ cc-last-expr-qualified ! exit,
  then,
  cc-assign-op @ [char] = <> if,
    cc-assign-type @ cc-assign-field @ cc-field-value-type cc-assign-desc @
    cc-last-expr-type @ cc-last-struct-desc @ cc-expr-save-types
    cc-assign-op @ bo-compound cc-binop-row cc-expr-op-row !
    cc-expr-op-row @ bo-level + @ level-shift = if,
      cc-expr-left-type @ cc-expr-promote cc-expr-common !
    then,
    cc-assign-type @ ty-ptr if,
      cc-expr-op-row @ bo-level + @ level-add = if,
        cc-assign-type @ cc-assign-desc @ cc-expr-pointee-size cc-emit-scale-rdi
      then,
    then,
    cc-emit-mov-rcx-rdi cc-emit-pop-rdi
    cc-expr-left-type @ cc-expr-common @ cc-emit-convert-value
    cc-expr-right-type @ cc-expr-common @ cc-emit-convert-right
    cc-native-binop-emit cc-expr-common @ cc-last-expr-type !
  then,
  cc-last-expr-type @ cc-assign-type @ cc-emit-convert-value
  cc-emit-pop-rcx
  cc-assign-type @ cc-assign-field @ cc-field-store
  cc-assign-type @ cc-assign-field @ cc-field-value-type
  cc-assign-desc @ cc-mark-typed-value
  cc-assign-qualified @ cc-last-expr-qualified ! ;

: cc-parse-assign
  cc-parse-ternary
  \ Snapshot lvalue state BEFORE the recursive RHS parse can clobber it.
  cc-last-lvalue-kind @                           ( kind )
  cc-last-ident-slot @                            ( kind slot )
  cc-next-token-keep
  cc-assign-op? if, cc-parse-native-assign exit, then,
  2drop                                           \ discard kind/slot snapshot
  cc-putback-token ;

\ ===========================================================================
\ cc-parse-expr: top-level entry
\ ===========================================================================

\ cc-parse-expr always ends with a materialize so any consumer (return,
\ if/while cond, expression-statement, function-call argument, decl
\ initializer, ...) receives an actual value in rdi rather than a pending
\ deref-address.
: cc-parse-comma
  cc-parse-assign
  begin,
    cc-next-token-keep [char] , cc-tok-punct?
  while,
    cc-check-static-init
    cc-emit-materialize cc-parse-assign
    [lit] 0 cc-last-expr-null !                 \ comma results are not constants
  repeat,
  cc-putback-token ;

: cc-parse-expr
  cc-parse-comma
  cc-emit-materialize ;

\ ===========================================================================
\ Constant expressions
\ ===========================================================================
\ An array size, a case label, an enum value, a global's initializer and an
\ #if line need a value while compiling, not code.  cc-parse-const reads
\ the grammar of cc-parse-ternary and computes it with the operator
\ table's evaluator column instead of emitting instructions.  An operand
\ is a number, a character, an enum constant or a parenthesised constant
\ expression.  On an #if line (cc-cx-pp true) any identifier the
\ preprocessor left is 0, as C says.  Errors: 125 for a name that isn't
\ an enum constant, 126 for a token that can't start an operand, 127 for
\ a missing ')', 128 for a '?' without its ':'.

variable cc-cx-pp
variable cc-cx-skip                              \ true in an unevaluated constant arm
variable cc-cx-unsigned                          \ signedness of the current value
: cc-cx-typed?  cc-cx-pp @ ;

\ Comparisons must also work across opposite signs, where 010's < wraps.
: cc-cx-lt ( a b -- flag )
  2dup cc-xor 0< if, drop 0< else, < then, ;
: cc-cx-ult ( a b -- flag )
  2dup cc-xor 0< if, swap drop 0< else, < then, ;

\ cc-cx-eval ( a b row left-unsigned -- v )  The recursive caller
\ saved the left flag; the right flag is current. Shifts use only the
\ left type. All other arithmetic uses uintmax_t if either is unsigned.
variable cc-cx-op
variable cc-cx-comparison
: cc-cx-eval
  over bo-level + @ level-shift = if,
    cc-cx-unsigned !
  else, cc-cx-unsigned @ or cc-cx-unsigned ! then,
  dup bo-op + @ cc-cx-op !
  dup bo-level + @ dup level-rel = swap level-eq = or cc-cx-comparison !
  cc-cx-skip @ if,
    drop 2drop [lit] 0
  else,
    cc-cx-comparison @ if,
      cc-cx-op @ [char] < = if, drop cc-cx-unsigned @ if, cc-cx-ult else, cc-cx-lt then, cc-flag else,
      cc-cx-op @ [char] > = if, drop swap cc-cx-unsigned @ if, cc-cx-ult else, cc-cx-lt then, cc-flag else,
      cc-cx-op @ pt-le = if, drop swap cc-cx-unsigned @ if, cc-cx-ult else, cc-cx-lt then, 0= cc-flag else,
      cc-cx-op @ pt-ge = if, drop cc-cx-unsigned @ if, cc-cx-ult else, cc-cx-lt then, 0= cc-flag else,
        bo-eval + @ execute
      then, then, then, then,
    else,
      cc-cx-unsigned @ if,
        cc-cx-op @ [char] / = if, drop cc-divisor / else,
        cc-cx-op @ [char] % = if, drop cc-divisor 2dup / * - else,
        cc-cx-op @ pt-shr = if, drop cc-pow2 / else,
          bo-eval + @ execute
        then, then, then,
      else, bo-eval + @ execute then,
    then,
  then,
  cc-cx-comparison @ if, [lit] 0 cc-cx-unsigned ! then, ;

\ cc-cx-operand ( -- v )  Under LP64 a number's suffix is checked by
\ the same parser that types runtime literals (060), so #if 1LLL is 240.
: cc-cx-operand
  [lit] 0 cc-cx-unsigned !
  cc-next-token-keep
  tok-kind @ tk-num = if, cc-integer-literal-check then,
  tok-kind @ tk-num = if,
    cc-cx-typed? if,
      cc-literal-unsigned @ tok-num @ 0< or cc-cx-unsigned !
    then,
    tok-num @ exit,
  then,
  tok-kind @ tk-chr = if, tok-num @ exit, then,
  tok-kind @ tk-ident = if,
    cc-cx-pp @ if, [lit] 0 exit, then,
    tok-str-addr @ tok-str-len @ cc-sym-find                ( id )
    dup 0< 0= if, dup cc-sym-kind-of sk-enum = else, [lit] 0 then,
    0= if, [lit] 125 cc-die then,
    cc-sym-val-of exit,
  then,
  lparen cc-tok-punct? if,
    cc-parse-const-fwd
    cc-next-token-keep
    [char] ) cc-tok-punct? 0= if, [lit] 127 cc-die then,
    exit,
  then,
  [lit] 126 cc-die ;

\ cc-cx-unary ( -- v )  '-' '+' '!' '~' then an operand.
: cc-cx-unary
  cc-next-token-keep
  kw-sizeof cc-tok-kw? if, cc-native-sizeof exit, then,
  [char] - cc-tok-punct? if, cc-cx-unary cc-negate       exit, then,
  [char] + cc-tok-punct? if, cc-cx-unary                 exit, then,
  [char] ! cc-tok-punct? if, cc-cx-unary 0= cc-flag [lit] 0 cc-cx-unsigned ! exit, then,
  [char] ~ cc-tok-punct? if, cc-cx-unary cc-invert       exit, then,
  cc-putback-token
  cc-cx-operand ;

\ cc-cx-binary ( level -- v )  One level of the operator table: operands
\ from the level below, combined by this level's evaluators.  Level 0 is
\ the unary operators.
: cc-cx-binary
  dup 0= if, drop cc-cx-unary exit, then,
  dup 1- cc-cx-binary                               ( level v )
  begin,
    over cc-binop? dup                              ( level v row row | .. 0 0 )
  while,
    >r cc-cx-unsigned @ >r
    over 1- cc-cx-binary                            ( level v w ; R: row left-u )
    r> r> swap                                     ( level v w row left-u )
    cc-cx-typed? if, cc-cx-eval else,
    drop cc-cx-skip @ if,
      \ Still consume/check every operand, but do not execute a dead arm.
      drop 2drop [lit] 0
    else,
      bo-eval + @ execute
    then, then,                                    ( level v' )
  repeat,
  drop cc-putback-token nip ;

\ cc-cx-and ( -- v )   cc-cx-or ( -- v )   && and ||, answering 1 or 0.
: cc-cx-and
  level-bit-or cc-cx-binary
  begin,
    cc-next-token-keep pt-and-and cc-tok-punct?
  while,
    cc-cx-skip @ >r
    dup 0= if, true cc-cx-skip ! then,
    level-bit-or cc-cx-binary
    r> cc-cx-skip !
    0= 0= swap 0= 0= and cc-flag [lit] 0 cc-cx-unsigned !
  repeat,
  cc-putback-token ;

: cc-cx-or
  cc-cx-and
  begin,
    cc-next-token-keep pt-or-or cc-tok-punct?
  while,
    cc-cx-skip @ >r
    dup if, true cc-cx-skip ! then,
    cc-cx-and
    r> cc-cx-skip !
    0= 0= swap 0= 0= or cc-flag [lit] 0 cc-cx-unsigned !
  repeat,
  cc-putback-token ;

\ cc-parse-const ( -- v )  cond ? a : b, or just cond.
: cc-parse-const
  cc-cx-or
  cc-next-token-keep
  [char] ? cc-tok-punct? if,
    cc-cx-skip @ >r                                 ( c ; R: outer-skip )
    dup 0= if, true cc-cx-skip ! then,
    cc-parse-const                                  ( c a ; R: outer-skip )
    r@ cc-cx-skip !
    cc-cx-unsigned @ >r
    >r                                              ( c ; R: outer-skip a-u a )
    cc-next-token-keep
    [char] : cc-tok-punct? 0= if, [lit] 128 cc-die then,
    dup if, true cc-cx-skip ! then,
    cc-parse-const                                  ( c b ; R: outer-skip a-u a )
    swap if, drop r> else, r> drop then,
    r> cc-cx-unsigned @ or cc-cx-unsigned !
    r> cc-cx-skip !
  else,
    cc-putback-token
  then, ;


' cc-parse-const is cc-parse-const-fwd

\ cc-pp-eval-text ( a u -- n )  #if's evaluator (cc-pp-eval, 040): lex
\ the expanded line a u by pointing the reader at it. Its source-relative
\ offsets can be negative when cc-src-buf is mapped; both endpoints use
\ the same base, so signed range checks and address addition still agree.  The lexer's state and cc-src-len are
\ put back afterwards; anything left after the expression dies with 129.
create cc-cx-save  cc-lex-state-size allot

: cc-pp-eval-text
  cc-cx-save cc-lex-mark
  cc-src-len @ >r
  over + cc-src-buf - cc-src-len !                  ( a )
  cc-src-buf - cc-src-pos !
  [lit] 0 cc-tok-pending !
  true cc-cx-pp !
  [lit] 0 cc-cx-skip !
  cc-parse-const
  cc-next-token-keep  tok-kind @ tk-eof <> if, [lit] 129 cc-die then,
  [lit] 0 cc-cx-pp !
  r> cc-src-len !
  cc-cx-save cc-lex-reset ;

' cc-pp-eval-text is cc-pp-eval

\ Fill in the forward references declared at the top of the file.
' cc-parse-expr   is cc-parse-expr-fwd
' cc-parse-comma  is cc-parse-comma-fwd
' cc-parse-assign is cc-parse-assign-fwd
' cc-parse-unary  is cc-parse-unary-fwd
