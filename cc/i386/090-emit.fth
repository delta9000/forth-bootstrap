\ 090-emit.fth — the i386 instruction encoders.
\
\ Loaded after 090-cc-emit.fth.  Each word here redefines the x86-64 encoder
\ of the same name, so the layers loaded after this file (100 onwards)
\ emit i386 code without knowing it.  The names keep their x86-64 registers,
\ because those layers are written in terms of them; this is what each one
\ means on i386:
\
\   rdi  the current expression result   edx:eax  (eax the low half)
\   rcx  the right operand               ebx:ecx  (ecx the low half)
\   rdx  the old value of a postfix ++   edi:esi  (esi the low half)
\   rbx  the scrutinee of a switch       edi:esi
\   rsi  the source address of a copy    esi
\   rax  a function's result             edx:eax, so moves to and from rdi vanish
\   rbp  the frame base                  ebp
\
\ A 64-bit register becomes a pair of 32-bit ones, and every instruction on
\ it an instruction on each half.  The layers above rely on rdi holding
\ every value extended to 64 bits from its C type (cc-emit-convert-rdi
\ restores that after each operation), so the pair holds it the same way:
\ edx is the sign or zero extension of eax for every type of 4 bytes or
\ less, and the high half of a long long.  Loads, stores, add, subtract,
\ multiply, shifts, the logic operations, comparisons and the test for
\ zero therefore work on the whole pair for every type.  Division works on
\ the low halves only; cc/i386/100-divide.fth deals with an 8-byte type.
\
\ Stack slots stay 8 bytes: a local, an argument and a pushed temporary
\ each hold a whole pair, low half at the lower address.
\
\ Not redefined, because the bytes are the same on i386: the rel32 jump and
\ call placeholders, cc-patch-rel32-to-here, and cc-emit-call-rax (FF D0 is
\ call eax).
\
\ Depends on 090-cc-emit.fth (cc-gfixup-add) and 060 with
\ cc/i386/065-ilp32-types.fth (ty-size, ty-unsigned?).

\ ===========================================================================
\ Encoders with no i386 form
\ ===========================================================================
\ The legacy model's in-place increments, the System V argument registers
\ and the libc shims are never reached in native mode.  If one is, the
\ compile stops with error 130 rather than emit x86-64 bytes.
: cc-emit-x86-64-only  [lit] 130 cc-die ;

: cc-emit-pop-rsi               cc-emit-x86-64-only ;
: cc-emit-pop-r8                cc-emit-x86-64-only ;
: cc-emit-pop-r9                cc-emit-x86-64-only ;
: cc-emit-shl-rdi-imm8          cc-emit-x86-64-only ;
: cc-emit-store-local-from-rsi  cc-emit-x86-64-only ;
: cc-emit-store-local-from-rdx  cc-emit-x86-64-only ;
: cc-emit-store-local-from-rcx  cc-emit-x86-64-only ;
: cc-emit-store-local-from-r8   cc-emit-x86-64-only ;
: cc-emit-store-local-from-r9   cc-emit-x86-64-only ;
: cc-emit-load-local-into-rax   cc-emit-x86-64-only ;
: cc-emit-inc-mem-local         cc-emit-x86-64-only ;
: cc-emit-dec-mem-local         cc-emit-x86-64-only ;
: cc-emit-inc-via-rcx           cc-emit-x86-64-only ;
: cc-emit-dec-via-rcx           cc-emit-x86-64-only ;
: cc-emit-load-via-rcx          cc-emit-x86-64-only ;
: cc-emit-putchar-shim          cc-emit-x86-64-only ;
: cc-emit-exit-shim             cc-emit-x86-64-only ;
: cc-emit-getchar-shim          cc-emit-x86-64-only ;
: cc-emit-fputs-shim            cc-emit-x86-64-only ;
: cc-emit-fputc-shim            cc-emit-x86-64-only ;
: cc-emit-fopen-shim            cc-emit-x86-64-only ;
: cc-emit-fclose-shim           cc-emit-x86-64-only ;
: cc-emit-fwrite-shim           cc-emit-x86-64-only ;
: cc-emit-fread-shim            cc-emit-x86-64-only ;
: cc-emit-calloc-shim           cc-emit-x86-64-only ;
: cc-emit-free-shim             cc-emit-x86-64-only ;
: cc-emit-syscall-shim          cc-emit-x86-64-only ;
: cc-emit-malloc-shim           cc-emit-x86-64-only ;
: cc-emit-strlen-shim           cc-emit-x86-64-only ;
: cc-emit-memcpy-shim           cc-emit-x86-64-only ;
: cc-emit-strrchr-shim          cc-emit-x86-64-only ;

\ ===========================================================================
\ Extending the low half
\ ===========================================================================

\ cc-emit-extend-rdi ( unsigned? -- )  edx := the zero or sign extension of
\ eax.
: cc-emit-extend-rdi
  if,
    x{ 31 d2 }                                    \ xor edx, edx
  else,
    x{ 99 }                                       \ cdq
  then, ;

\ cc-emit-extend-rcx ( unsigned? -- )  ebx := the zero or sign extension of
\ ecx.
: cc-emit-extend-rcx
  if,
    x{ 31 db }                                    \ xor ebx, ebx
  else,
    x{ 89 cb }                                    \ mov ebx, ecx
    x{ c1 fb 1f }                                 \ sar ebx, 31
  then, ;

\ ===========================================================================
\ Immediate loads
\ ===========================================================================

\ cc-emit-mov-rdi-imm32 ( v -- )  The pair := v, a signed 32-bit value.
: cc-emit-mov-rdi-imm32
  x{ b8 } cc-emit-4le                             \ mov eax, imm32
  x{ 99 } ;                                       \ cdq

\ cc-emit-movabs-rdi-imm64 ( v -- )  The pair := v, all 64 bits: the low
\ four bytes of v, then v divided by 2^32.
: cc-emit-movabs-rdi-imm64
  x{ b8 } dup cc-emit-4le                         \ mov eax, imm32
  x{ ba } [lit] 4294967296 / cc-emit-4le ;        \ mov edx, imm32

\ cc-emit-mov-rdi-int ( v -- )  Load an integer literal by the shorter of
\ the two.  Literals are never negative (a leading `-` is unary minus), so
\ one unsigned division finds those that fit a signed 32-bit immediate.
: cc-emit-mov-rdi-int
  dup [lit] 2147483648 / if,
    cc-emit-movabs-rdi-imm64
  else,
    cc-emit-mov-rdi-imm32
  then, ;

\ cc-emit-movabs-rdi-imm64-placeholder ( -- patch-offset )  The pair := an
\ address not known yet.  An address is 4 bytes; patch-offset is where they
\ go (cc-out-patch-address).
: cc-emit-movabs-rdi-imm64-placeholder
  x{ b8 } cc-out-pos @ [lit] 0 cc-emit-4le        \ mov eax, imm32
  x{ 31 d2 } ;                                    \ xor edx, edx

\ cc-out-patch-address ( vaddr offset -- )  Fill in such a placeholder.
: cc-out-patch-address  cc-out-patch-4le ;

\ ===========================================================================
\ Stack ops
\ ===========================================================================
\ A push stores the high half first, so the low half lies at the lower
\ address, as it does in memory.

: cc-emit-push-rdi
  x{ 52 }                                         \ push edx
  x{ 50 } ;                                       \ push eax

: cc-emit-pop-rdi
  x{ 58 }                                         \ pop eax
  x{ 5a } ;                                       \ pop edx

: cc-emit-pop-rcx
  x{ 59 }                                         \ pop ecx
  x{ 5b } ;                                       \ pop ebx

: cc-emit-pop-rdx
  x{ 5e }                                         \ pop esi
  x{ 5f } ;                                       \ pop edi

\ A switch saves the outer scrutinee around itself.
: cc-emit-push-rbx
  x{ 57 }                                         \ push edi
  x{ 56 } ;                                       \ push esi

: cc-emit-pop-rbx
  x{ 5e }                                         \ pop esi
  x{ 5f } ;                                       \ pop edi

\ ===========================================================================
\ Local-variable access
\ ===========================================================================
\ Locals live at [ebp - 8*(slot+1)], the high half 4 bytes above the low.
\
\ cc-emit-half-ea ( slot half modrm8 -- )  Emit the ModR/M byte and the
\ displacement for [ebp - 8*(slot+1) + half]; half is 0 or 4.  modrm8 is
\ the mod=01 (disp8) form.  A displacement of -128..127 is emitted that
\ way; any other switches to mod=10 (modrm8 + 0x40) and a disp32.  The
\ range test adds 128 and divides, unsigned, by 256.
: cc-emit-half-ea
  >r swap 1+ [lit] 8 * -                          ( disp ; R: modrm8 )
  dup [lit] 128 + [lit] 256 / if,
    r> $40 + cc-emit-byte
    cc-emit-4le
  else,
    r> cc-emit-byte
    $ff and cc-emit-byte
  then, ;

: cc-emit-load-local                              ( slot -- )
  dup
  x{ 8b } [lit] 0 $45 cc-emit-half-ea             \ mov eax, dword [ebp+disp]
  x{ 8b } [lit] 4 $55 cc-emit-half-ea ;           \ mov edx, dword [ebp+disp+4]

: cc-emit-store-local                             ( slot -- )
  dup
  x{ 89 } [lit] 0 $45 cc-emit-half-ea             \ mov dword [ebp+disp], eax
  x{ 89 } [lit] 4 $55 cc-emit-half-ea ;           \ mov dword [ebp+disp+4], edx

\ The address of a local.  A pointer is 4 bytes, so its high half is 0.
: cc-emit-lea-rdi-local                           ( slot -- )
  x{ 8d } [lit] 0 $45 cc-emit-half-ea             \ lea eax, [ebp+disp]
  x{ 31 d2 } ;                                    \ xor edx, edx

\ ===========================================================================
\ Loads and stores through an address
\ ===========================================================================
\ The address is the low half: eax for a load, ecx for a store.

: cc-emit-load-via-rdi
  x{ 8b 50 04 }                                   \ mov edx, dword [eax+4]
  x{ 8b 00 } ;                                    \ mov eax, dword [eax]

: cc-emit-load-byte-via-rdi
  x{ 0f b6 00 }                                   \ movzx eax, byte [eax]
  x{ 31 d2 } ;                                    \ xor edx, edx

: cc-emit-zx-byte-rdi
  x{ 0f b6 c0 }                                   \ movzx eax, al
  x{ 31 d2 } ;                                    \ xor edx, edx

: cc-emit-store-via-rcx
  x{ 89 01 }                                      \ mov dword [ecx], eax
  x{ 89 51 04 } ;                                 \ mov dword [ecx+4], edx

: cc-emit-store-byte-via-rcx
  x{ 88 01 } ;                                    \ mov byte [ecx], al

\ cc-emit-load-typed-via-rdi ( ty -- )  The pair := *(T *)eax, extended.
: cc-emit-load-typed-via-rdi
  dup ty-size [lit] 1 = if,
    x{ 0f }
    dup ty-unsigned? if, $b6 else, $be then, cc-emit-byte
    x{ 00 }                                       \ movzx/movsx eax, byte [eax]
    ty-unsigned? cc-emit-extend-rdi exit,
  then,
  dup ty-size [lit] 2 = if,
    x{ 0f }
    dup ty-unsigned? if, $b7 else, $bf then, cc-emit-byte
    x{ 00 }                                       \ movzx/movsx eax, word [eax]
    ty-unsigned? cc-emit-extend-rdi exit,
  then,
  dup ty-size [lit] 4 = if,
    x{ 8b 00 }                                    \ mov eax, dword [eax]
    ty-unsigned? cc-emit-extend-rdi exit,
  then,
  drop cc-emit-load-via-rdi ;

\ cc-emit-store-typed-via-rcx ( ty -- )  *(T *)ecx := the pair, as wide as T.
: cc-emit-store-typed-via-rcx
  ty-size
  dup [lit] 1 = if, drop cc-emit-store-byte-via-rcx exit, then,
  dup [lit] 2 = if,
    drop x{ 66 89 01 } exit,                      \ mov word [ecx], ax
  then,
  [lit] 4 = if,
    x{ 89 01 }                                    \ mov dword [ecx], eax
  else, cc-emit-store-via-rcx then, ;

\ cc-emit-load-local-typed ( slot ty -- )
: cc-emit-load-local-typed
  swap cc-emit-lea-rdi-local cc-emit-load-typed-via-rdi ;

\ cc-emit-store-local-typed ( slot ty -- )  The pair is preserved.
: cc-emit-store-local-typed
  ty-size
  dup [lit] 1 = if,
    drop x{ 88 } [lit] 0 $45 cc-emit-half-ea exit,  \ mov byte [ebp+disp], al
  then,
  dup [lit] 2 = if,
    drop x{ 66 89 } [lit] 0 $45 cc-emit-half-ea exit,  \ mov word [ebp+disp], ax
  then,
  [lit] 4 = if,
    x{ 89 } [lit] 0 $45 cc-emit-half-ea           \ mov dword [ebp+disp], eax
  else, cc-emit-store-local then, ;

\ ===========================================================================
\ Conversions
\ ===========================================================================

\ cc-emit-convert-rdi ( ty -- )  Truncate the pair to T and extend it again.
\ An 8-byte type needs nothing.
: cc-emit-convert-rdi
  dup ty-size [lit] 1 = if,
    x{ 0f }
    dup ty-unsigned? if, $b6 else, $be then, cc-emit-byte
    x{ c0 }                                       \ movzx/movsx eax, al
    ty-unsigned? cc-emit-extend-rdi exit,
  then,
  dup ty-size [lit] 2 = if,
    x{ 0f }
    dup ty-unsigned? if, $b7 else, $bf then, cc-emit-byte
    x{ c0 }                                       \ movzx/movsx eax, ax
    ty-unsigned? cc-emit-extend-rdi exit,
  then,
  dup ty-size [lit] 4 = if,
    ty-unsigned? cc-emit-extend-rdi exit,
  then,
  drop ;

\ 090 bound its deferred conversions to the x86-64 words; bind them again.
: cc-emit-convert-value-default ( source destination -- ) nip cc-emit-convert-rdi ;
' cc-emit-convert-value-default is cc-emit-convert-value

\ cc-emit-convert-rcx ( ty -- )  Same conversion for the right operand.
: cc-emit-convert-rcx
  dup ty-size [lit] 1 = if,
    x{ 0f }
    dup ty-unsigned? if, $b6 else, $be then, cc-emit-byte
    x{ c9 }                                       \ movzx/movsx ecx, cl
    ty-unsigned? cc-emit-extend-rcx exit,
  then,
  dup ty-size [lit] 2 = if,
    x{ 0f }
    dup ty-unsigned? if, $b7 else, $bf then, cc-emit-byte
    x{ c9 }                                       \ movzx/movsx ecx, cx
    ty-unsigned? cc-emit-extend-rcx exit,
  then,
  dup ty-size [lit] 4 = if,
    ty-unsigned? cc-emit-extend-rcx exit,
  then,
  drop ;

: cc-emit-convert-right-default ( source destination -- ) nip cc-emit-convert-rcx ;
' cc-emit-convert-right-default is cc-emit-convert-right

\ ===========================================================================
\ Register-to-register moves
\ ===========================================================================

: cc-emit-mov-rcx-rdi
  x{ 89 c1 }                                      \ mov ecx, eax
  x{ 89 d3 } ;                                    \ mov ebx, edx

\ A function returns its value in edx:eax, where expressions keep theirs.
: cc-emit-mov-rax-rdi ;
: cc-emit-mov-rdi-rax ;

: cc-emit-xor-rax-rax
  x{ 31 c0 }                                      \ xor eax, eax
  x{ 31 d2 } ;                                    \ xor edx, edx

: cc-emit-mov-rbx-rdi
  x{ 89 c6 }                                      \ mov esi, eax
  x{ 89 d7 } ;                                    \ mov edi, edx

: cc-emit-mov-rdi-rdx
  x{ 89 f0 }                                      \ mov eax, esi
  x{ 89 fa } ;                                    \ mov edx, edi

: cc-emit-mov-rsi-rdi
  x{ 89 c6 } ;                                    \ mov esi, eax

\ ===========================================================================
\ Switch dispatch
\ ===========================================================================
\ The pair is free during dispatch.  cc-emit-cmp-rbx-rdi sets ZF when the
\ scrutinee in edi:esi equals it, and destroys it.
: cc-emit-cmp-rbx-rdi
  x{ 31 f0 }                                      \ xor eax, esi
  x{ 31 fa }                                      \ xor edx, edi
  x{ 09 d0 } ;                                    \ or eax, edx

: cc-emit-cmp-rbx-imm32                           ( v -- )
  cc-emit-mov-rdi-imm32 cc-emit-cmp-rbx-rdi ;

\ ===========================================================================
\ Arithmetic and logic on the pair, with ebx:ecx as the right operand
\ ===========================================================================

: cc-emit-add-rdi-rcx
  x{ 01 c8 }                                      \ add eax, ecx
  x{ 11 da } ;                                    \ adc edx, ebx

: cc-emit-sub-rdi-rcx
  x{ 29 c8 }                                      \ sub eax, ecx
  x{ 19 da } ;                                    \ sbb edx, ebx

: cc-emit-and-rdi-rcx
  x{ 21 c8 }                                      \ and eax, ecx
  x{ 21 da } ;                                    \ and edx, ebx

: cc-emit-or-rdi-rcx
  x{ 09 c8 }                                      \ or eax, ecx
  x{ 09 da } ;                                    \ or edx, ebx

: cc-emit-xor-rdi-rcx
  x{ 31 c8 }                                      \ xor eax, ecx
  x{ 31 da } ;                                    \ xor edx, ebx

: cc-emit-not-rdi
  x{ f7 d0 }                                      \ not eax
  x{ f7 d2 } ;                                    \ not edx

\ Negating the low half borrows from the high one unless it was 0.
: cc-emit-neg-rdi
  x{ f7 d8 }                                      \ neg eax
  x{ 83 d2 00 }                                   \ adc edx, 0
  x{ f7 da } ;                                    \ neg edx

\ cc-emit-add-rdi-imm32 ( imm32 -- )  Add a signed 32-bit constant: its
\ high half is 0 or -1.
: cc-emit-add-rdi-imm32
  x{ 05 } dup cc-emit-4le                         \ add eax, imm32
  x{ 83 d2 } 0< $ff and cc-emit-byte ;            \ adc edx, 0 or -1

\ The low 64 bits of a product: the product of the low halves, plus both
\ cross products in the high half.
: cc-emit-imul-rdi-rcx
  x{ 0f af d1 }                                   \ imul edx, ecx
  x{ 0f af d8 }                                   \ imul ebx, eax
  x{ 01 d3 }                                      \ add ebx, edx
  x{ f7 e1 }                                      \ mul ecx
  x{ 01 da } ;                                    \ add edx, ebx

\ An index times an element size is a signed 32-bit offset.
: cc-emit-shl-rdi-3
  x{ c1 e0 03 }                                   \ shl eax, 3
  x{ 99 } ;                                       \ cdq

: cc-emit-scale-rdi                               ( bytes -- )
  dup [lit] 1 = if, drop exit, then,
  dup [lit] 8 = if, drop cc-emit-shl-rdi-3 exit, then,
  x{ 69 c0 } cc-emit-4le                          \ imul eax, eax, imm32
  x{ 99 } ;                                       \ cdq

: cc-emit-scale-rcx                               ( bytes -- )
  dup [lit] 1 = if, drop exit, then,
  x{ 69 c9 } cc-emit-4le                          \ imul ecx, ecx, imm32
  [lit] 0 cc-emit-extend-rcx ;                   \ signed, as cdq above

\ ===========================================================================
\ Shifts of the pair by cl
\ ===========================================================================
\ The processor takes a 32-bit shift count modulo 32.  shld and shrd move
\ bits across the halves for counts 0..31; for 32..63 the half that was
\ shifted by (count - 32) moves over and the other is filled.

: cc-emit-shl-rdi-cl
  x{ 0f a5 c2 }                                   \ shld edx, eax, cl
  x{ d3 e0 }                                      \ shl eax, cl
  x{ f6 c1 20 }                                   \ test cl, 32
  x{ 74 04 }                                      \ jz +4
  x{ 89 c2 }                                      \ mov edx, eax
  x{ 31 c0 } ;                                    \ xor eax, eax

: cc-emit-shr-rdi-cl
  x{ 0f ad d0 }                                   \ shrd eax, edx, cl
  x{ d3 ea }                                      \ shr edx, cl
  x{ f6 c1 20 }                                   \ test cl, 32
  x{ 74 04 }                                      \ jz +4
  x{ 89 d0 }                                      \ mov eax, edx
  x{ 31 d2 } ;                                    \ xor edx, edx

: cc-emit-sar-rdi-cl
  x{ 0f ad d0 }                                   \ shrd eax, edx, cl
  x{ d3 fa }                                      \ sar edx, cl
  x{ f6 c1 20 }                                   \ test cl, 32
  x{ 74 05 }                                      \ jz +5
  x{ 89 d0 }                                      \ mov eax, edx
  x{ c1 fa 1f } ;                                 \ sar edx, 31

\ ===========================================================================
\ Division of the low halves
\ ===========================================================================
\ idiv and div divide edx:eax by ecx, leaving the quotient in eax and the
\ remainder in edx.  Both operands are 4 bytes wide, so the dividend's high
\ half is the extension of eax, and the result is extended again.

: cc-emit-idiv-quotient
  x{ 99 }                                         \ cdq
  x{ f7 f9 }                                      \ idiv ecx
  x{ 99 } ;                                       \ cdq

: cc-emit-idiv-remainder
  x{ 99 }                                         \ cdq
  x{ f7 f9 }                                      \ idiv ecx
  x{ 89 d0 }                                      \ mov eax, edx
  x{ 99 } ;                                       \ cdq

: cc-emit-udiv-quotient
  x{ 31 d2 }                                      \ xor edx, edx
  x{ f7 f1 }                                      \ div ecx
  x{ 31 d2 } ;                                    \ xor edx, edx

: cc-emit-udiv-remainder
  x{ 31 d2 }                                      \ xor edx, edx
  x{ f7 f1 }                                      \ div ecx
  x{ 89 d0 }                                      \ mov eax, edx
  x{ 31 d2 } ;                                    \ xor edx, edx

\ ===========================================================================
\ Comparisons of the pairs: the pair := 0 or 1.
\ ===========================================================================
\ cc-emit-set-rdi ( setX-opcode -- )  The common tail; as in 090, the
\ caller passes the second byte of the setcc opcode.
: cc-emit-set-rdi
  x{ 0f } cc-emit-byte x{ c0 }                    \ setX al  (X: the opcode byte passed in)
  x{ 0f b6 c0 }                                   \ movzx eax, al
  x{ 31 d2 } ;                                    \ xor edx, edx

\ Equal pairs differ in no bit of either half.
: cc-emit-cmp-equal                               ( setX-opcode -- )
  x{ 31 c8 }                                      \ xor eax, ecx
  x{ 31 da }                                      \ xor edx, ebx
  x{ 09 d0 }                                      \ or eax, edx
  cc-emit-set-rdi ;

\ Subtracting the low halves and then, with the borrow, the high ones
\ leaves the sign, overflow and carry flags of the 64-bit difference
\ left - right, which is all that "less" and "not less" read.
: cc-emit-cmp-less                                ( setX-opcode -- )
  x{ 39 c8 }                                      \ cmp eax, ecx
  x{ 19 da }                                      \ sbb edx, ebx
  cc-emit-set-rdi ;

\ The zero flag is not that of the whole difference, so "greater" is
\ "less" with the operands exchanged: right - left.
: cc-emit-cmp-greater                             ( setX-opcode -- )
  x{ 39 c1 }                                      \ cmp ecx, eax
  x{ 19 d3 }                                      \ sbb ebx, edx
  cc-emit-set-rdi ;

: cc-emit-cmp-eq  $94 cc-emit-cmp-equal ;         \ sete al
: cc-emit-cmp-ne  $95 cc-emit-cmp-equal ;         \ setne al
: cc-emit-cmp-lt  $9c cc-emit-cmp-less ;          \ setl al
: cc-emit-cmp-ge  $9d cc-emit-cmp-less ;          \ setge al
: cc-emit-cmp-gt  $9c cc-emit-cmp-greater ;       \ setl al
: cc-emit-cmp-le  $9d cc-emit-cmp-greater ;       \ setge al
: cc-emit-cmp-ult $92 cc-emit-cmp-less ;          \ setb al
: cc-emit-cmp-uge $93 cc-emit-cmp-less ;          \ setae al
: cc-emit-cmp-ugt $92 cc-emit-cmp-greater ;       \ setb al
: cc-emit-cmp-ule $93 cc-emit-cmp-greater ;       \ setae al

\ ===========================================================================
\ Tests for zero, on the whole pair
\ ===========================================================================

\ ZF := the pair is 0.  The pair is preserved.
: cc-emit-test-rdi
  x{ 85 c0 }                                      \ test eax, eax
  x{ 75 02 }                                      \ jnz +2
  x{ 85 d2 } ;                                    \ test edx, edx

\ The pair := (the pair == 0).  Used by unary '!'.
: cc-emit-not-zero-flag
  x{ 09 d0 }                                      \ or eax, edx
  x{ 0f 94 c0 }                                   \ sete al
  x{ 0f b6 c0 }                                   \ movzx eax, al
  x{ 31 d2 } ;                                    \ xor edx, edx

\ ===========================================================================
\ Function prologue / epilogue
\ ===========================================================================
\ A call pushes a 4-byte return address and the prologue a 4-byte ebp, half
\ of what they take on x86-64.  The layers above number the parameters as
\ slots below zero: slot -3 is the first, at [ebp+16].  Eight more bytes
\ under the saved ebp put it there.
\
\   [ebp+16]  the first argument (slot -3)
\   [ebp+12]  the return address
\   [ebp+8]   the caller's ebp
\   [ebp]     8 unused bytes
\   [ebp-8]   the first local (slot 0)

: cc-emit-prologue                                ( frame-bytes -- )
  x{ 55 }                                         \ push ebp
  x{ 83 ec 08 }                                   \ sub esp, 8
  x{ 89 e5 }                                      \ mov ebp, esp
  x{ 81 ec } cc-emit-4le ;                        \ sub esp, imm32

: cc-emit-epilogue
  x{ 8d 65 08 }                                   \ lea esp, [ebp+8]
  x{ 5d }                                         \ pop ebp
  x{ c3 } ;                                       \ ret

\ ===========================================================================
\ Global references
\ ===========================================================================

\ cc-emit-global-ref ( slot -- )  The pair := the global's address, through
\ a placeholder that cc-finalize-globals (110) patches.
: cc-emit-global-ref
  x{ b8 } cc-out-pos @ [lit] 0 cc-emit-4le        \ mov eax, imm32
  swap cc-gfixup-add
  x{ 31 d2 } ;                                    \ xor edx, edx

\ ===========================================================================
\ Sequences of the native call ABI and of struct copies
\ ===========================================================================

\ cc-native-swap-args ( off1 off2 -- )  Exchange the 8-byte slots at two
\ offsets from esp, a half at a time.
: cc-native-swap-halves                           ( off1 off2 -- )
  >r
  dup x{ 8b 84 24 } cc-emit-4le                   \ mov eax, dword [esp+off1]
  r@ x{ 8b 8c 24 } cc-emit-4le                    \ mov ecx, dword [esp+off2]
  x{ 89 8c 24 } cc-emit-4le                       \ mov dword [esp+off1], ecx
  r> x{ 89 84 24 } cc-emit-4le ;                  \ mov dword [esp+off2], eax
: cc-native-swap-args
  2dup cc-native-swap-halves
  [lit] 4 + swap [lit] 4 + swap cc-native-swap-halves ;

: cc-native-drop-args                             ( n -- )
  dup if,
    x{ 81 c4 } [lit] 8 * cc-emit-4le              \ add esp, n*8
  else, drop then, ;

\ The function address pushed before a call's n arguments, for call eax.
: cc-native-load-call-target                      ( n -- )
  x{ 8b 84 24 } [lit] 8 * cc-emit-4le ;           \ mov eax, dword [esp+n*8]

\ cc-emit-rep-count ( n -- )  ecx := n, the byte count of the rep movsb or
\ rep stosb that follows.  Those write through edi, and the destination is
\ in eax, so it moves over first.
: cc-emit-rep-count
  x{ 89 c7 }                                      \ mov edi, eax
  x{ b9 } cc-emit-4le ;                           \ mov ecx, imm32
: cc-emit-rep-count-rcx  cc-emit-rep-count ;
