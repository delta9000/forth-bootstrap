\ 114-cc-func.fth — declarations and function definitions for the C subset
\ needed to compile M2-Planet.
\
\ Struct definitions and local declarations (scalars, pointers, arrays,
\ function pointers, struct locals), each value in an 8-byte slot; then
\ functions: a parameter list, the register arguments spilled into the
\ frame, and one `T NAME(params) { body }` between a prologue and an
\ epilogue.  Native mode does not load this file: 115-cc-native.fth has its
\ declarations and 117-cc-native-program.fth its functions.
\
\ Depends on 112-cc-stmt.fth (the body's statements) and everything it
\ depends on.

\ ===========================================================================
\ Struct definitions
\ ===========================================================================

\ Scratch globals used while building one struct descriptor.  cc-parse-struct-
\ def runs single-threaded (no recursion / nested struct defs), so a
\ single set of globals is enough — they're saved here and read back when the
\ field loop body needs them.
variable cc-sd-build-desc                         \ descriptor under construction
variable cc-sd-build-fname-a
variable cc-sd-build-fname-u
variable cc-sd-build-field-ty
variable cc-sd-build-field-desc                   \ pointee desc for struct-ptr fields (0 if none)

\ cc-sd-append-field ( -- )  Append the field whose name is in cc-sd-build-
\ fname-{a,u}, type in cc-sd-build-field-ty, pointee descriptor in
\ cc-sd-build-field-desc, to the descriptor in cc-sd-build-desc.  Assigns
\ offset = total-size BEFORE this field, then bumps total-size by 8.  This
\ subset stores every field in an 8-byte slot.  Increments field-count.
: cc-sd-append-field                              ( -- )
  cc-sd-build-desc @ cc-sd-field-count            ( i )
  cc-sd-build-desc @ swap cc-sd-field-rec         ( rec )
  cc-sd-build-fname-a @ over cc-sf-set-name-addr
  cc-sd-build-fname-u @ over cc-sf-set-name-len
  cc-sd-build-field-ty @ over cc-sf-set-type
  cc-sd-build-field-desc @ over cc-sf-set-desc
  cc-sd-build-desc @ cc-sd-total-size swap cc-sf-set-offset
  \ Increment field-count and total-size by 8.
  cc-sd-build-desc @ cc-sd-field-count 1+
  cc-sd-build-desc @ cc-sd-set-field-count
  cc-sd-build-desc @ cc-sd-total-size [lit] 8 +
  cc-sd-build-desc @ cc-sd-set-total-size ;

\ cc-lookup-struct-tag ( -- desc )  Reads an IDENT token (must be the current
\ position; will be advanced past), looks it up as sk-struct in the symbol
\ table, returns the descriptor pointer.  Aborts on lookup failure.
: cc-lookup-struct-tag                            ( -- desc )
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 145 cc-die
  then,
  tok-str-addr @ tok-str-len @ cc-sym-find-tag        ( id-or-neg1 )
  dup 0< if,
    drop
    [lit] 146 cc-die
  then,
  dup cc-sym-kind-of sk-struct <> if,
    drop
    [lit] 147 cc-die
  then,
  cc-sym-val-of ;                                  \ descriptor pointer

\ cc-parse-struct-def ( -- )  Called with the 'struct' keyword ALREADY consumed
\ (it's the current token).  Handles ONLY the definition form:
\
\    struct TAG '{' (field-decl)* '}' ';'
\
\ Registers TAG in the symbol table as sk-struct with val = descriptor pointer.
\ Descriptor layout: see 060-cc-types.fth.
: cc-parse-struct-def                             ( -- )
  \ Expect IDENT tag.
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 149 cc-die
  then,
  \ Snapshot tag bytes on data stack (rstack would be clobbered by ';' etc.).
  tok-str-addr @ tok-str-len @                    ( tag-addr tag-len )
  \ Expect '{'.
  [char] { cc-expect-punct-c

  \ Allocate a zeroed descriptor; its field table grows as fields arrive.
  cc-sd-alloc cc-sd-build-desc !                  ( tag-addr tag-len )

  \ Pre-register the struct tag (with the still-empty descriptor) BEFORE
  \ parsing the body, so self-referential field types `struct T* next` can
  \ resolve their own tag.  We snapshot tag-addr/tag-len off-stack via 2>r so
  \ the symbol-add doesn't disturb the stack layout the loop expects.
  over over                                       ( tag-a tag-u tag-a tag-u )
  sk-struct
  [lit] 0
  cc-sd-build-desc @
  cc-sym-add drop                                 ( tag-a tag-u )

  \ Field-parsing loop.  Each iteration parses `T '*'* IDENT ;` where T is
  \ one of: int / char / void / struct TAG / IDENT (typedef-name).  All
  \ fields are 8 bytes in our codegen, so the *type* is mostly cosmetic;
  \ what matters is correctness of name+offset.
  begin,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] } = and 0=
  while,
    cc-putback-token
    \ Parse base type.  Default the pointee-descriptor to 0; the struct-tag
    \ branch overrides when the field is `struct TAG ...`.
    [lit] 0 cc-sd-build-field-desc !
    cc-skip-qualifiers
    cc-next-token-keep
    tok-kind @ tk-kw = if,
      tok-kw-id @ kw-int     = if, ty-int  cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-char    = if, ty-char cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-void    = if, ty-void cc-sd-build-field-ty ! else,
      tok-kw-id @ kw-enum    = if,
        cc-skip-enum-tag ty-int cc-sd-build-field-ty !
      else,
      tok-kw-id @ kw-struct  = if,
        \ Look up the tag's descriptor (soft — self-referential `struct T*
        \ next` inside `struct T {...}` works because cc-parse-struct-def
        \ pre-registers the tag with a still-empty descriptor before parsing
        \ fields, and forward refs return 0).  Stored in the field record so
        \ chained '->' can propagate the type.
        cc-lookup-struct-tag-soft cc-sd-build-field-desc !
        ty-struct cc-sd-build-field-ty !
      else,
        [lit] 150 cc-die
      then, then, then, then, then,
    else,
      \ tk-ident — treat as typedef-name used as a type.  Record as int
      \ (we only care about the storage size = 8).
      tok-kind @ tk-ident <> if,
        [lit] 151 cc-die
      then,
      ty-int cc-sd-build-field-ty !
    then,

    cc-count-stars                                ( ... ptr-depth )
    \ Re-pack the type word with the ptr-depth.
    cc-sd-build-field-ty @ swap ty-make cc-sd-build-field-ty !

    \ Read field name.
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 152 cc-die
    then,
    tok-str-addr @ cc-sd-build-fname-a !
    tok-str-len  @ cc-sd-build-fname-u !
    [char] ; cc-expect-punct-c
    cc-sd-append-field
  repeat,
  \ '}' was the loop test; we consumed it via cc-next-token-keep but DIDN'T
  \ putback this time (the test went 0=, so we entered the exit path).
  \ Expect ';' after '}'.
  [char] ; cc-expect-punct-c
  drop drop ;                                     \ discard tag-a tag-u

\ ===========================================================================
\ Function-pointer declaration parsing.
\ ===========================================================================
\ A function-pointer decl has the shape:
\
\    RETURN_TYPE '(' '*' NAME ')' '(' PARAM_TYPES ')' (= expr)? ';'
\
\ Detection: after the base type is parsed, we need 2-token lookahead to
\ distinguish `int (*fp)(int);` from `int x;` and `int *p;`.  Putback holds
\ only one token, so we mark the lexer state in cc-peek-mark (050-cc-lex.fth),
\ read ahead, and reset to the mark.

\ cc-peek-fnptr? ( -- f )  Look ahead 2 tokens; -1 iff we see '(' then '*'.
\ The first may be a token put back (the mark saves the putback flag too).
\ Always restores the lexer state so the caller resumes at the original
\ position regardless of the result.
: cc-peek-fnptr?
  cc-peek-mark cc-lex-mark
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ lparen = and 0= if,
    cc-peek-mark cc-lex-reset
    [lit] 0
  else,
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] * = and
    cc-peek-mark cc-lex-reset
  then, ;

\ cc-parse-fnptr-decl ( -- )  The base type has been consumed by the caller;
\ the next two tokens are '(' and '*'.  Parses
\
\    '(' '*' NAME ')' '(' PARAM_TYPES ')' ('=' expr)? ';'
\
\ and registers NAME as an sk-local with type ty-func + ptr-depth=1.  The
\ parameter types are skipped; signatures are not validated.
: cc-parse-fnptr-decl
  \ Consume '(' and '*'.
  lparen cc-expect-punct-c
  [char] * cc-expect-punct-c

  \ NAME (IDENT).
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 153 cc-die
  then,
  tok-str-addr @ tok-str-len @                    ( name-a name-u )

  \ ')' '(' PARAM-TYPES ')'
  [char] ) cc-expect-punct-c
  lparen cc-expect-punct-c
  cc-skip-fnptr-params

  \ Register as an sk-local function pointer: ty-func + ptr-depth=1.
  sk-local
  ty-func [lit] 1 ty-make                         ( a u kind type )
  cc-fn-local-count @                             ( a u kind type slot )
  cc-sym-add drop
  [lit] 1 cc-fn-add-slots

  \ Optional '= expr;' initializer.
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] = = and if,
    cc-parse-expr
    cc-fn-local-count @ 1- cc-emit-store-local
    [char] ; cc-expect-punct-c
  else,
    tok-kind @ tk-punct = tok-num @ [char] ; = and 0= if,
      [lit] 154 cc-die
    then,
  then, ;

variable cc-decl-base                              \ base type kind

\ cc-parse-local-declarator ( init-ptr -- )  One declarator of a local
\ declaration whose base type is in cc-decl-base: '*'* NAME, then
\ '[' SIZE ']' or ('=' EXPR)? .  SIZE is a constant expression.  Ends with
\ the token after the declarator read (the caller wants ',' or ';').
\ init-ptr is non-zero only when the base came from a pointer-typed
\ typedef (`typedef int* int_ptr;`).
\
\ An array's element 0 sits in its deepest slot.  A `static` local
\ (cc-decl-static) gets file-scope storage instead of frame slots, so it
\ keeps its value between calls: the symbol is an sk-global that only
\ this block can see, an array in the bss, a scalar in the data area with
\ its constant initializer.
: cc-parse-local-declarator                       ( init-ptr -- )
  cc-count-stars +                                 ( ptr-depth )
  cc-expect-ident
  tok-str-addr @ tok-str-len @ rot                 ( a u ptr-depth )
  cc-decl-base @ swap ty-make                      ( a u type )
  cc-next-token-keep
  [char] [ cc-tok-punct? if,
    \ -------- Array: T name [ N ] --------
    cc-parse-const                                 ( a u type N )
    dup [lit] 0 <= if, [lit] 156 cc-die then,
    cc-next-token-keep
    [char] ] cc-tok-punct? 0= if, [lit] 157 cc-die then,
    >r                                             ( a u type ; R: N )
    cc-decl-static @ if,
      sk-global swap  r@ [lit] 8 * cc-bss-alloc    ( a u kind type slot )
    else,
      sk-local swap  cc-fn-local-count @ r@ + 1-
    then,
    cc-sym-add                                     ( id ; R: N )
    r@ swap cc-sym-set-array-len
    cc-decl-static @ 0= if, r@ cc-fn-add-slots then,
    r> drop
    cc-next-token-keep exit,
  then,
  \ -------- Scalar: T name ('=' expr)? --------
  cc-decl-static @ if,
    sk-global swap  [lit] 8 cc-globals-alloc       ( a u kind type slot )
    dup >r cc-sym-add drop                         ( ; R: slot )
    [char] = cc-tok-punct? if,
      cc-parse-const r@ cc-globals-store-8le
      cc-next-token-keep
    then,
    r> drop exit,
  then,
  sk-local swap  cc-fn-local-count @               ( a u kind type slot )
  cc-sym-add drop
  [lit] 1 cc-fn-add-slots
  [char] = cc-tok-punct? if,
    cc-parse-expr
    cc-fn-local-count @ 1- cc-emit-store-local
    cc-next-token-keep
  then, ;

\ cc-parse-decl-with-base ( base initial-ptr -- )
\ A local declaration after its base type: one or more declarators
\ separated by ',', then ';' (else die 159).  The caller has consumed the
\ keyword or typedef-name that gave the base type, and supplies (base,
\ initial-ptr-depth).
\
\ If the next two tokens after the base are '(' '*', dispatch to
\ cc-parse-fnptr-decl instead (function-pointer declaration).
: cc-parse-decl-with-base                         ( base init-ptr -- )
  swap cc-decl-base !                              ( init-ptr )
  \ Detect function-pointer decl shape.  Only when there are no leading
  \ stars from the caller (init-ptr=0) — `int* (*fp)()` is a func-ptr returning
  \ int*, which is outside this subset.
  dup [lit] 0 = cc-peek-fnptr? and if,
    drop cc-parse-fnptr-decl exit,
  then,
  begin,
    dup cc-parse-local-declarator                  ( init-ptr )
    [char] , cc-tok-punct?
  while,
  repeat,
  drop
  [char] ; cc-tok-punct? 0= if,
    [lit] 159 cc-die
  then, ;

\ cc-more-type-kws ( base -- base' )  After a basic-type keyword, read any
\ more (`unsigned int`, `long long`, `unsigned char`): they all name the
\ one 8-byte integer, except that a char among them makes the type char.
: cc-more-type-kws
  begin,
    cc-next-token-keep cc-tok-is-basic-type-kw?
  while,
    kw-char cc-tok-kw? if, drop ty-char then,
  repeat,
  cc-putback-token ;

\ cc-parse-decl ( -- )  Entry from cc-parse-stmt.  The basic-type kw is
\ the current token (still in tok-*); pick ty-char for `char`, ty-int for the
\ rest (int / long / short / unsigned / signed), then read any further type
\ keywords.  ty-char matters because the
\ array-index path uses base==ty-char + ptr-depth==1 to decide on a byte-wide
\ load/store for `s[i]` where s is `char*` — without this distinction every
\ char pointer is treated like an int pointer (qword stride / qword load).
\ void as a local doesn't make sense; it would have been rejected anyway.
: cc-parse-decl
  tok-kw-id @ kw-char = if,
    ty-char
  else,
    ty-int
  then,
  cc-more-type-kws
  [lit] 0 cc-parse-decl-with-base ;

\ ===========================================================================
\ cc-parse-struct-local-decl
\ ===========================================================================
\ Called with 'struct' keyword ALREADY consumed (it was the dispatch token).
\ Parses:
\
\    struct TAG '*'* IDENT ';'
\
\ ptr-depth=0 form (`struct TAG name;`): reserves total-size/8 local slots
\ (one per int field) with field-0 at the LOWEST address (deepest slot).
\ Symbol entry: val = slot of field 0; struct-desc = descriptor pointer.
\
\ ptr-depth>=1 form (`struct TAG* p;`): reserves a single slot for the pointer.
\ Symbol entry: val = slot, struct-desc = descriptor pointer of the pointee
\ (so '->field' can resolve field offsets).
\
\ Uses globals to avoid deep stack juggling.

variable cc-sld-desc
variable cc-sld-ptr-depth
variable cc-sld-name-a
variable cc-sld-name-u

: cc-parse-struct-local-decl                      ( -- )
  cc-lookup-struct-tag cc-sld-desc !
  cc-count-stars cc-sld-ptr-depth !
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 160 cc-die
  then,
  tok-str-addr @ cc-sld-name-a !
  tok-str-len  @ cc-sld-name-u !

  cc-sld-ptr-depth @ [lit] 0 = if,
    \ struct TAG name; — reserve slot-count slots.  No initializer support.
    [char] ; cc-expect-punct-c
    cc-sld-name-a @ cc-sld-name-u @
    sk-local
    ty-struct [lit] 0 ty-make
    cc-fn-local-count @ cc-sld-desc @ cc-sd-total-size [lit] 8 / + 1-
                                                  ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-sld-desc @ swap cc-sym-set-struct-desc
    \ Reserve slots.
    cc-sld-desc @ cc-sd-total-size [lit] 8 / cc-fn-add-slots
  else,
    \ struct TAG* p ('=' expr)? ; — one slot for the pointer.
    cc-sld-name-a @ cc-sld-name-u @
    sk-local
    ty-struct cc-sld-ptr-depth @ ty-make          ( a u kind ty )
    cc-fn-local-count @                           ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-sld-desc @ swap cc-sym-set-struct-desc
    [lit] 1 cc-fn-add-slots

    \ Optional '= expr;' initializer (M2-Planet uses `struct T* i = expr;`).
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] = = and if,
      cc-parse-expr
      cc-fn-local-count @ 1- cc-emit-store-local
      [char] ; cc-expect-punct-c
    else,
      tok-kind @ tk-punct = tok-num @ [char] ; = and 0= if,
        [lit] 161 cc-die
      then,
    then,
  then, ;

\ ===========================================================================
\ Statements that declare
\ ===========================================================================
\ cc-parse-decl-or-stmt ( -- )  112's statement parser, with this subset's
\ local declarations in front of it: a statement that starts with a type
\ keyword, `enum TAG`, `struct TAG` or a typedef-name declares, and
\ anything else goes back for cc-parse-stmt.  `struct TAG ... ;` in a block
\ is always a declaration (a struct definition is only allowed at top
\ level), and `enum TAG x;` declares an int.  With cc-target-lp64 set,
\ declarations are native mode's and cc-parse-stmt dispatches them itself.
\
\ 112 reaches its statement parser through cc-parse-stmt-fwd, so binding
\ that to this word makes every nested statement come here first too.
: cc-parse-decl-or-stmt
  cc-target-lp64 @ if, cc-parse-stmt exit, then,
  cc-skip-storage-quals
  cc-next-token-keep
  cc-tok-is-basic-type-kw? if, cc-parse-decl exit, then,
  kw-enum cc-tok-kw? if,
    cc-skip-enum-tag  ty-int [lit] 0 cc-parse-decl-with-base exit,
  then,
  kw-struct cc-tok-kw? if, cc-parse-struct-local-decl exit, then,
  tok-kind @ tk-ident = if,
    tok-str-addr @ tok-str-len @ cc-sym-find      ( id | -1 )
    dup 0< 0= if,
      dup cc-sym-kind-of sk-typedef = if,
        \ The typedef's name is consumed; declare with its base and
        \ pointer depth.
        cc-sym-val-of                             ( ty )
        dup ty-base swap ty-ptr                   ( base ptr-depth )
        cc-parse-decl-with-base exit,
      then,
    then,
    drop
  then,
  cc-putback-token
  cc-parse-stmt ;
' cc-parse-decl-or-stmt is cc-parse-stmt-fwd

\ ===========================================================================
\ Function parsing: multiple functions, params, SYS-V calling convention
\ ===========================================================================
\ The current-function bookkeeping uses two globals so the name token's bytes
\ aren't lost when subsequent tokens are read for the parameter list.
variable cc-fn-name-addr
variable cc-fn-name-len
variable cc-fn-param-count                        \ # params in current function
variable cc-fn-prior-sym-id                       \ prior sk-func id for fwd-fixup walk; -1 if none

\ cc-block-end? ( -- f )  After cc-next-token-keep, returns -1 if current
\ token is '}'.  Helper used by the function body loop.
: cc-block-end?
  tok-kind @ tk-punct =
  tok-num @ [char] } = and ;

\ ===========================================================================
\ Parameter-list parsing + spill
\ ===========================================================================

\ cc-parse-param-list-loop ( -- )  Parse one or more parameters separated by
\ ','.  T may be int / char / void / long / short / struct TAG / enum TAG /
\ typedef-name, with '*' modifiers.  Consumes the closing ')'.
: cc-parse-param-list-loop
  begin,
    \ Base type.  Both branches leave ( base ptr-depth-so-far ); the kw path
    \ starts ptr-depth at 0; the typedef path inherits the typedef's encoded
    \ ptr-depth (so FUNCTION = void (*)() stays a function pointer in params).
    \ Qualifiers before the type (`const int size`) are skipped.
    cc-skip-qualifiers
    cc-next-token-keep
    tok-kind @ tk-kw = if,
      tok-kw-id @ kw-struct = if,
        cc-lookup-struct-tag cc-pending-struct-desc !
        ty-struct [lit] 0
      else,
        \ int/char/void/long/short/unsigned/signed — char is distinguished so
        \ `char* s` params get ty-char + ptr-depth, which the array-index path
        \ needs to emit byte stride / byte load for `s[i]`.  Others collapse
        \ to ty-int.
        [lit] 0 cc-pending-struct-desc !
        tok-kw-id @ kw-enum = if, cc-skip-enum-tag then,
        tok-kw-id @ kw-char = if,
          ty-char
        else,
          ty-int
        then,
        cc-tok-is-basic-type-kw? if, cc-more-type-kws then,
        [lit] 0
      then,
    else,
      tok-kind @ tk-ident = if,
        \ Typedef-name (e.g. FILE, FUNCTION).  Look up and unpack its encoded
        \ base+ptr-depth so function-pointer typedefs survive into param type.
        tok-str-addr @ tok-str-len @ cc-sym-find   ( id )
        dup 0< if,
          [lit] 180 cc-die
        then,
        dup cc-sym-kind-of sk-typedef <> if,
          [lit] 181 cc-die
        then,
        [lit] 0 cc-pending-struct-desc !
        cc-sym-val-of                              ( ty )
        dup ty-base swap ty-ptr                    ( base ptr-depth )
      else,
        [lit] 182 cc-die
        ty-int [lit] 0                            \ unreachable
      then,
    then,
    ( base ptr-depth )
    cc-count-stars                                ( base ptr-depth extra )
    +                                              ( base total-ptr )
    ty-make                                       ( ty )
    \ Expect IDENT.
    cc-next-token-keep
    tok-kind @ tk-ident <> if,
      [lit] 183 cc-die
    then,
    \ Add as a local: name in tok-str-addr/len, kind=sk-local, type=ty,
    \ val=current local count (= slot).  Stack on entry: ( ty ).
    tok-str-addr @ tok-str-len @                  ( ty a u )
    rot                                            ( a u ty )
    sk-local swap                                  ( a u sk-local ty )
    cc-fn-local-count @                            ( a u kind ty slot )
    cc-sym-add                                    ( id )
    cc-pending-struct-desc @ swap cc-sym-set-struct-desc
    [lit] 1 cc-fn-add-slots
    [lit] 1 cc-fn-param-count +!
    \ Continue if next is ','.
    cc-next-token-keep
    tok-kind @ tk-punct = tok-num @ [char] , = and 0=
  until,
  cc-putback-token
  \ Now consume the closing ')'.
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] ) = and 0= if,
    [lit] 184 cc-die
  then, ;

\ cc-parse-param-list ( -- )  Parse a possibly-empty comma-separated list of
\ parameters.  Caller has NOT yet consumed any tokens.  When this returns the
\ closing ')' has been consumed.  Each parameter becomes an sk-local symbol.
: cc-parse-param-list
  [lit] 0 cc-fn-param-count !
  cc-next-token-keep
  tok-kind @ tk-punct = tok-num @ [char] ) = and if,
    \ ')' — empty list, done.
  else,
    \ Special case: `(void)` = no params.  Peek for kw-void followed by ')'.
    tok-kind @ tk-kw = tok-kw-id @ kw-void = and if,
      cc-peek-mark cc-lex-mark
      cc-next-token                               \ advance past void; tok-* := next
      tok-kind @ tk-punct = tok-num @ [char] ) = and >r
      cc-peek-mark cc-lex-reset
      r> if,
        \ It IS '(void)'.  void is already consumed; now consume ')'.
        cc-next-token
      else,
        cc-putback-token
        cc-parse-param-list-loop
      then,
    else,
      cc-putback-token
      cc-parse-param-list-loop
    then,
  then, ;

\ cc-emit-spill-params ( -- )  In the function prologue, spill the SYS-V
\ argument registers (rdi/rsi/rdx/rcx/r8/r9) into the local slots reserved
\ for them by cc-parse-param-list (slots 0..cc-fn-param-count-1).
: cc-emit-spill-params
  cc-fn-param-count @ [lit] 1 >= if,
    [lit] 0 cc-emit-store-local
  then,
  cc-fn-param-count @ [lit] 2 >= if,
    [lit] 1 cc-emit-store-local-from-rsi
  then,
  cc-fn-param-count @ [lit] 3 >= if,
    [lit] 2 cc-emit-store-local-from-rdx
  then,
  cc-fn-param-count @ [lit] 4 >= if,
    [lit] 3 cc-emit-store-local-from-rcx
  then,
  cc-fn-param-count @ [lit] 5 >= if,
    [lit] 4 cc-emit-store-local-from-r8
  then,
  cc-fn-param-count @ [lit] 6 >= if,
    [lit] 5 cc-emit-store-local-from-r9
  then, ;

\ ===========================================================================
\ cc-parse-fn-return-type ( -- )
\ Consume the function's return type, which may be:
\   - int / char / void, after any storage classes and qualifiers
\   - struct TAG       (tag ident consumed)
\   - enum TAG         (tag ident consumed)
\   - typedef-name     (any non-keyword ident — FILE, etc.)
\ Followed by zero or more '*' modifiers.  Codegen treats every return as a
\ single rax-sized value, so the type is not recorded — it's just consumed.
: cc-parse-fn-return-type
  cc-skip-storage-quals
  cc-next-token-keep
  tok-kind @ tk-kw = if,
    tok-kw-id @ kw-struct = if,
      cc-next-token-keep
      tok-kind @ tk-ident <> if,
        [lit] 185 cc-die
      then,
    then,
    tok-kw-id @ kw-enum = if, cc-skip-enum-tag then,
    cc-tok-is-basic-type-kw? if, [lit] 0 cc-more-type-kws drop then,
  else,
    tok-kind @ tk-ident <> if,
      [lit] 186 cc-die
    then,
  then,
  cc-count-stars drop ;

\ cc-parse-function — one user-defined `T NAME(params) { body }`.  T may be
\ int / char / void / struct TAG / typedef-name, optionally followed by '*'s.
\ ===========================================================================
\ Layout:
\   1. Consume return type, NAME, '('.
\   2. Capture the function's start vaddr (cc-here-vaddr) and
\      register it in the symbol table BEFORE parsing params/body — this lets
\      the body call this function recursively, and is also needed before any
\      forward-call patch.
\   3. If the name is "main", record cc-main-vaddr for the entry stub.
\   4. Push a fresh scope.  Reset local counter.
\   5. Parse the parameter list — each param becomes a local in slots 0..N-1.
\   6. Consume `{`.
\   7. Emit prologue (cc-frame-slots * 8 = 256-byte frame, room for 32
\      locals incl. params).
\   8. Spill arg registers into their slots.
\   9. Loop: parse statements until `}`.
\  10. Emit implicit return (xor rax,rax + epilogue) — wasted bytes if the
\      function already ended with a `return`, but harmless.
\  11. Pop scope.
: cc-parse-function
  cc-parse-fn-return-type
  \ Function name.
  cc-next-token-keep
  tok-kind @ tk-ident <> if,
    [lit] 187 cc-die
  then,
  tok-str-addr @ cc-fn-name-addr !
  tok-str-len  @ cc-fn-name-len  !

  lparen cc-expect-punct-c

  \ Capture any prior sk-func entry for this name BEFORE adding our own,
  \ so we can walk its forward-call fixup list and patch each call site.
  \ cc-sym-find returns the newest match; if a prototype was registered
  \ earlier (cc-register-fn-proto), that's what we get.  -1 means none.
  cc-fn-name-addr @ cc-fn-name-len @ cc-sym-find
  cc-fn-prior-sym-id !

  \ Register the function in the symbol table BEFORE pushing the per-function
  \ scope, so the entry survives cc-scope-pop at function-end and remains
  \ visible to subsequent function bodies.  Its vaddr is the address of the
  \ next byte we'll emit (the prologue's first byte, which we haven't emitted
  \ yet — but we will, immediately after the param list and the spill).
  cc-fn-name-addr @ cc-fn-name-len @
  sk-func
  ty-int [lit] 0 ty-make
  cc-here-vaddr                                   ( a u kind ty vaddr )
  cc-sym-add drop

  \ Patch any forward-call fixups registered against the prior prototype.
  \ The fixup list head lives in that entry's call-fixups cell.  After
  \ patching we zero the head so a repeat definition doesn't double-patch.
  \ Its addr-fixups cell holds a parallel list for `movabs rdi, imm64` rvalue
  \ sites (function-pointer references that appear before the definition).
  cc-fn-prior-sym-id @ [lit] 0 >= if,
    cc-fn-prior-sym-id @ cc-sym-kind-of sk-func = if,
      cc-fn-prior-sym-id @ cc-sym-call-fixups @
      cc-here-vaddr
      cc-walk-and-patch-to-vaddr
      [lit] 0 cc-fn-prior-sym-id @ cc-sym-call-fixups !
      cc-fn-prior-sym-id @ cc-sym-addr-fixups @
      cc-here-vaddr
      cc-walk-and-patch-imm64-to-vaddr
      [lit] 0 cc-fn-prior-sym-id @ cc-sym-addr-fixups !
    then,
  then,

  \ If this is main, also record the vaddr for the entry-stub patch.
  cc-fn-name-addr @ cc-fn-name-len @ cc-is-main? if,
    cc-here-vaddr cc-main-vaddr !
  then,

  \ Reset locals; push scope (so params + body locals are popped together).
  [lit] 0 cc-fn-local-count !
  \ Reset per-function label table, break/continue stacks, switch depths.
  [lit] 0 cc-label-count !
  [lit] 0 cc-break-stack-head    !
  [lit] 0 cc-continue-stack-head !
  [lit] 0 cc-switch-depth        !
  [lit] 0 cc-loop-switch-depth   !
  cc-scope-push

  \ Parameter list (consumes through ')').
  cc-parse-param-list

  [char] { cc-expect-punct-c

  \ Prologue.
  cc-frame-slots [lit] 8 * cc-emit-prologue

  \ Spill SYS-V argument registers into local slots 0..N-1.
  cc-emit-spill-params

  \ Body: stmt* until '}'.
  begin,
    cc-next-token-keep
    cc-block-end? 0=
  while,
    cc-putback-token
    cc-parse-decl-or-stmt
  repeat,
  \ '}' was consumed by the loop test.

  \ Implicit return: if the body already ended with `return`, this is a few
  \ bytes of unreachable epilogue — harmless.  If it didn't, the function
  \ falls through to here and we need to terminate properly.
  cc-emit-xor-rax-rax                             \ rax := 0 (default return)
  cc-emit-epilogue

  cc-scope-pop ;
