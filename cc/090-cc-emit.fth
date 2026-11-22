\ 090-cc-emit.fth — code-emission helpers for the C-subset compiler.
\ Builds tiny instruction-encoders on top of cc-emit-byte / cc-emit-4le from
\ 030-cc-io.fth.  All output goes to cc-out-buf; nothing here touches the seed's
\ HERE pointer.
\
\ Register convention for the compiled code:
\   rdi  — scratch / current expression result
\   rcx  — temp for binary-op right operand
\   rax  — used by idiv (low quotient/remainder); also by SYS-V return
\   rbp  — frame base; locals at [rbp - 8*(slot+1)]
\
\ Depends on 020-cc-arena.fth (cc-die, cc-check-cap, cc-alloc) and
\ 030-cc-io.fth (cc-emit-byte, cc-emit-4le, cell[]).  cc-decode-escape comes
\ from 050-cc-lex.fth.

\ ===========================================================================
\ Immediate-load instructions (REX.W + C7 /0 + imm32)
\ ===========================================================================

\ cc-emit-mov-rdi-imm32 ( v -- )   48 C7 C7 <imm32>
: cc-emit-mov-rdi-imm32
  x{ 48 c7 c7 } cc-emit-4le ;                     \ mov rdi, imm32

\ ===========================================================================
\ Stack ops
\ ===========================================================================

\ Optional compile-time accounting; native defaults emit no extra bytes.
: cc-emit-track-noop ;
defer cc-emit-track-push-fwd
defer cc-emit-track-pop-fwd
' cc-emit-track-noop is cc-emit-track-push-fwd
' cc-emit-track-noop is cc-emit-track-pop-fwd

\ push rdi: 0x57
: cc-emit-push-rdi  cc-emit-track-push-fwd x{ 57 } ;  \ push rdi

\ pop rdi:  0x5F
: cc-emit-pop-rdi   cc-emit-track-pop-fwd x{ 5f } ;  \ pop rdi

\ pop rdx:  0x5A
: cc-emit-pop-rdx   cc-emit-track-pop-fwd x{ 5a } ;  \ pop rdx

\ pop rcx:  0x59
: cc-emit-pop-rcx   cc-emit-track-pop-fwd x{ 59 } ;  \ pop rcx

\ push rbx (0x53) / pop rbx (0x5B).  Used by switch to preserve the outer
\ value of rbx across the switch (which uses rbx to hold the scrutinee).
: cc-emit-push-rbx  x{ 53 } ;                     \ push rbx
: cc-emit-pop-rbx   x{ 5b } ;                     \ pop rbx

\ ===========================================================================
\ Local-variable access
\ ===========================================================================
\ Locals live at [rbp - 8*(slot+1)].  Slots 0..15 have displacements
\ -8..-128, which fit a signed disp8 (ModR/M mod=01); deeper slots need the
\ disp32 form (mod=10).  cc-emit-local-ea picks the right one per slot.
\ Note: the frame itself is fixed at 256 bytes = 32 slots (cc-frame-slots in
\ 110-cc-decl.fth, which dies rather than hand out a 33rd) — the encoding
\ handles any slot; the frame does not.
\
\ cc-disp8-from-slot ( slot -- byte )
\   = (256 - 8*(slot+1)) AND 255 = the unsigned-byte representation of the
\   signed displacement -8*(slot+1).  Only valid for slots 0..15.

: cc-disp8-from-slot
  1+ [lit] 8 *                                   \ 8 * (slot+1)
  [lit] 0 swap -                                  \ negate
  $ff and ;                                       \ low byte

\ cc-emit-local-ea ( slot modrm8 -- )
\   Emit the ModR/M byte + displacement for [rbp + disp] access to a local
\   slot.  modrm8 is the mod=01 (disp8) form of the ModR/M byte.  Slots
\   0..15 emit it unchanged plus a disp8; deeper slots switch to mod=10
\   (modrm8 + 0x40) plus the 32-bit two's-complement displacement.
: cc-emit-local-ea
  over [lit] 16 < >r over [lit] 0 [lit] 16 - >= r> and if,
    cc-emit-byte
    cc-disp8-from-slot cc-emit-byte
  else,
    $40 + cc-emit-byte                            \ mod=01 -> mod=10
    1+ [lit] 8 *                                  \ 8 * (slot+1)
    [lit] 0 swap - cc-emit-4le                    \ negate; low 4 bytes = disp32
  then, ;

\ mov rdi, [rbp + disp]:  48 8B 7D <disp8>  (or 48 8B BD <disp32>)
: cc-emit-load-local                              ( slot -- )
  x{ 48 8b } $7d cc-emit-local-ea ;               \ mov rdi, qword [rbp+disp]

\ lea rdi, [rbp + disp]:  48 8D 7D <disp8>  (or 48 8D BD <disp32>)
\ ModR/M(mod=01, reg=rdi=7, rm=rbp=5) = 0x7D.  Loads the *address* of the local
\ slot into rdi (used to implement `&local`).
: cc-emit-lea-rdi-local                           ( slot -- )
  x{ 48 8d } $7d cc-emit-local-ea ;               \ lea rdi, [rbp+disp]

\ mov rdi, [rdi]:  48 8B 3F
\ ModR/M(mod=00, reg=rdi=7, rm=rdi=7) = 0x3F.  Loads the qword at the address
\ currently in rdi into rdi (dereference).
: cc-emit-load-via-rdi
  x{ 48 8b 3f } ;                                 \ mov rdi, qword [rdi]

\ movzx rdi, BYTE PTR [rdi]:  48 0F B6 3F
\ Zero-extends a single byte from [rdi] into rdi.  Used by `s[i]` rvalue use
\ where s is `char*` (or any other byte-element access path).
: cc-emit-load-byte-via-rdi
  x{ 48 0f b6 3f } ;                              \ movzx rdi, byte [rdi]

\ movzx edi, dil:  40 0F B6 FF
\ Keeps only rdi's low byte (writing edi clears the upper half of rdi).
\ REX=0x40 selects dil rather than bh.  Used by a (char) cast.
: cc-emit-zx-byte-rdi
  x{ 40 0f b6 ff } ;                              \ movzx edi, dil

\ mov [rcx], rdi:  48 89 39
\ ModR/M(mod=00, reg=rdi=7, rm=rcx=1) = 0x39.  Stores rdi to the qword address
\ in rcx (assignment via dereference).
: cc-emit-store-via-rcx
  x{ 48 89 39 } ;                                 \ mov qword [rcx], rdi

\ mov BYTE PTR [rcx], dil:  40 88 39
\ Stores the low byte of rdi to [rcx].  REX=0x40 is needed to select dil
\ instead of bh.  Used by `s[i] = c;` where s is char*.
: cc-emit-store-byte-via-rcx
  x{ 40 88 39 } ;                                 \ mov byte [rcx], dil

\ shl rdi, imm8:  48 C1 E7 <imm8>
\ ModR/M(mod=11, reg=/4 = SHL, rm=rdi=7) = 11_100_111 = 0xE7.  Multiplies rdi
\ by 2^imm8 (used to scale array index by sizeof(T) when T is 8 bytes).
: cc-emit-shl-rdi-imm8                            ( imm8 -- )
  x{ 48 c1 e7 } cc-emit-byte ;                    \ shl rdi, imm8

\ Convenience: rdi <<= 3 (multiply by 8 = sizeof(int)/sizeof(ptr)).
: cc-emit-shl-rdi-3   [lit] 3 cc-emit-shl-rdi-imm8 ;

\ add rdi, imm32:  48 81 C7 <imm32>
\ ModR/M(mod=11, reg=/0 = ADD, rm=rdi=7) = 11_000_111 = 0xC7.  Used to bias
\ a struct base/pointer in rdi by a field offset.  imm32 is sign-extended.
: cc-emit-add-rdi-imm32                           ( imm32 -- )
  x{ 48 81 c7 } cc-emit-4le ;                     \ add rdi, imm32

\ call rax:  FF D0   (no REX needed; rax = reg 0).
\ ModR/M(mod=11, reg=/2 = CALL r/m64, rm=rax=0) = 11_010_000 = 0xD0.
: cc-emit-call-rax
  x{ ff d0 } ;                                    \ call rax

\ ===========================================================================
\ Register-to-register moves
\ ===========================================================================
\ ADD/SUB/IMUL r/m64, r64 has reg-field=src, rm-field=dst.  We use rdi as the
\ destination accumulator and rcx for the right-operand temp.

\ mov rcx, rdi:  48 89 F9     (89 /r, mod=11 reg=rdi=7 rm=rcx=1 -> 11_111_001 = F9)
: cc-emit-mov-rcx-rdi
  x{ 48 89 f9 } ;                                 \ mov rcx, rdi

\ mov rax, rdi:  48 89 F8     (mod=11 reg=rdi=7 rm=rax=0 -> 11_111_000 = F8)
: cc-emit-mov-rax-rdi
  x{ 48 89 f8 } ;                                 \ mov rax, rdi

\ mov rdi, rax:  48 89 C7     (mod=11 reg=rax=0 rm=rdi=7 -> 11_000_111 = C7)
\ Used after a function call to transfer the SYS-V return value into our
\ scratch rdi so the rest of the expression machinery sees it.
: cc-emit-mov-rdi-rax
  x{ 48 89 c7 } ;                                 \ mov rdi, rax

\ mov rbx, rdi:  48 89 FB   (89 /r, mod=11 reg=rdi=7 rm=rbx=3 -> 11_111_011 = FB)
\ Used at switch entry to stash the scrutinee in a callee-saved register so
\ it survives across case-body codegen (including any function calls).
: cc-emit-mov-rbx-rdi
  x{ 48 89 fb } ;                                 \ mov rbx, rdi

\ cmp rbx, imm32:  48 81 FB <imm32>   (81 /7, mod=11 /7=111 rm=rbx=3 -> FB)
\ Used by switch dispatch to compare the saved scrutinee against each case
\ constant.  Sets ZF iff rbx == imm32.  imm32 is sign-extended to 64 bits.
: cc-emit-cmp-rbx-imm32                           ( v -- )
  x{ 48 81 fb } cc-emit-4le ;                     \ cmp rbx, imm32

\ xor rax, rax:  48 31 C0     (zero rax in 3 bytes; for implicit return).
: cc-emit-xor-rax-rax
  x{ 48 31 c0 } ;                                 \ xor rax, rax

\ ===========================================================================
\ ALU on rdi using rcx as the right operand
\ ===========================================================================
\ The binary-op pattern emitted by the parser is:
\     <eval left>          ; rdi = left
\     push rdi
\     <eval right>         ; rdi = right
\     mov rcx, rdi         ; rcx = right
\     pop rdi              ; rdi = left
\     <op> rdi, rcx        ; rdi = left <op> right
\
\ ADD r/m64, r64 (0x01 /r): rm=dst, reg=src.
\   add rdi, rcx -> mod=11 reg=rcx=1 rm=rdi=7 -> 11_001_111 = 0xCF
: cc-emit-add-rdi-rcx
  x{ 48 01 cf } ;                                 \ add rdi, rcx

\ SUB r/m64, r64 (0x29 /r): same encoding shape.
\   sub rdi, rcx -> 0xCF
: cc-emit-sub-rdi-rcx
  x{ 48 29 cf } ;                                 \ sub rdi, rcx

\ IMUL r64, r/m64 (0x0F AF /r): reg=dst, rm=src (NOTE the operand order is
\ flipped from add/sub).
\   imul rdi, rcx -> mod=11 reg=rdi=7 rm=rcx=1 -> 11_111_001 = 0xF9
: cc-emit-imul-rdi-rcx
  x{ 48 0f af f9 } ;                              \ imul rdi, rcx

\ Signed division: idiv divides rdx:rax by r/m64, leaving quotient in rax,
\ remainder in rdx.  We want rdi := rdi / rcx (or rdi % rcx).  Sequence:
\     mov rax, rdi      ; 48 89 F8
\     cqo               ; 48 99            (sign-extend rax into rdx)
\     idiv rcx          ; 48 F7 F9         (F7 /7, mod=11 rm=rcx=1 -> 11_111_001=0xF9)
\     mov rdi, rax|rdx  ; 48 89 C7 (rax) or 48 89 D7 (rdx)
: cc-emit-idiv-quotient
  x{ 48 89 f8 }                                   \ mov rax, rdi
  x{ 48 99 }                                      \ cqo
  x{ 48 f7 f9 }                                   \ idiv rcx
  x{ 48 89 c7 } ;                                 \ mov rdi, rax

: cc-emit-idiv-remainder
  x{ 48 89 f8 }                                   \ mov rax, rdi
  x{ 48 99 }                                      \ cqo
  x{ 48 f7 f9 }                                   \ idiv rcx
  x{ 48 89 d7 } ;                                 \ mov rdi, rdx

\ ===========================================================================
\ Function prologue / epilogue
\ ===========================================================================
\ Prologue:  push rbp ; mov rbp, rsp ; sub rsp, imm32
\ Epilogue:  mov rsp, rbp ; pop rbp ; ret

: cc-emit-prologue                                ( frame-bytes -- )
  x{ 55 }                                         \ push rbp
  x{ 48 89 e5 }                                   \ mov rbp, rsp
  x{ 48 81 ec } cc-emit-4le ;                     \ sub rsp, imm32

: cc-emit-restore-noop ;
defer cc-emit-restore-callee-fwd
' cc-emit-restore-noop is cc-emit-restore-callee-fwd

: cc-emit-epilogue
  cc-emit-restore-callee-fwd
  x{ 48 89 ec }                                   \ mov rsp, rbp
  x{ 5d }                                         \ pop rbp
  x{ c3 } ;                                       \ ret

\ ===========================================================================
\ Comparisons: set rdi to 0 or 1 based on signed comparison of left/right.
\ ===========================================================================
\ The binary-op pattern (same as ALU) leaves rdi=left, rcx=right.  Each helper
\ emits 12 bytes:
\     xor rax, rax     48 31 C0
\     cmp rdi, rcx     48 39 CF      (sets flags from rdi - rcx = left - right)
\     setX al          0F 9X C0      (X = 4=E, 5=NE, C=L, D=GE, E=LE, F=G)
\     mov rdi, rax     48 89 C7
\
\ cc-emit-cmp-set ( setX-opcode -- )  Common tail; caller passes the second
\ byte of the setcc opcode (0x94, 0x95, 0x9C, 0x9D, 0x9E, 0x9F).
: cc-emit-cmp-set
  x{ 48 31 c0 }                                   \ xor rax, rax
  x{ 48 39 cf }                                   \ cmp rdi, rcx
  x{ 0f } cc-emit-byte x{ c0 }                    \ setX al  (X: the opcode byte passed in)
  x{ 48 89 c7 } ;                                 \ mov rdi, rax

: cc-emit-cmp-eq  $94 cc-emit-cmp-set ;           \ sete al
: cc-emit-cmp-ne  $95 cc-emit-cmp-set ;           \ setne al
: cc-emit-cmp-lt  $9c cc-emit-cmp-set ;           \ setl al
: cc-emit-cmp-ge  $9d cc-emit-cmp-set ;           \ setge al
: cc-emit-cmp-le  $9e cc-emit-cmp-set ;           \ setle al
: cc-emit-cmp-gt  $9f cc-emit-cmp-set ;           \ setg al

\ ===========================================================================
\ Conditional / unconditional branches with rel32 fixups.
\ ===========================================================================

\ test rdi, rdi  -> 48 85 FF  (sets ZF=1 iff rdi == 0).
: cc-emit-test-rdi
  x{ 48 85 ff } ;                                 \ test rdi, rdi

\ cc-emit-jz-rel32-placeholder ( -- patch-offset )
\ Emits `0F 84 00 00 00 00`; returns the file-offset of the rel32 cell
\ so the caller can later patch it with cc-patch-rel32-to-here.
: cc-emit-jz-rel32-placeholder
  x{ 0f 84 } cc-out-pos @ 0 cc-emit-4le ;         \ jz rel32

\ cc-emit-jmp-rel32-placeholder ( -- patch-offset )
\ Emits `E9 00 00 00 00`; returns the rel32 file-offset.
: cc-emit-jmp-rel32-placeholder
  x{ e9 } cc-out-pos @ 0 cc-emit-4le ;            \ jmp rel32

\ cc-emit-call-rel32-placeholder ( -- patch-offset )
\ Emits `E8 00 00 00 00`; returns the rel32 file-offset.  Used for forward
\ function calls whose target vaddr is not yet known.  The caller threads the
\ patch offset onto a fixup list attached to the callee's prototype symbol;
\ the list is walked and patched when the function is later defined.
: cc-emit-call-rel32-placeholder
  x{ e8 } cc-out-pos @ 0 cc-emit-4le ;            \ call rel32

\ cc-emit-jnz-rel32-placeholder ( -- patch-offset )
\ Emits `0F 85 00 00 00 00`; returns the rel32 file-offset.  Used by `||`'s
\ short-circuit fast-path: if LHS is non-zero, skip RHS and produce 1.
: cc-emit-jnz-rel32-placeholder
  x{ 0f 85 } cc-out-pos @ 0 cc-emit-4le ;         \ jnz rel32

\ cc-patch-rel32-to-here ( patch-offset -- )
\ rel32 = current cc-out-pos - (patch-offset + 4).
: cc-patch-rel32-to-here
  cc-out-pos @                                    ( patch-off target-off )
  over [lit] 4 + -                                ( patch-off rel32 )
  swap cc-out-patch-4le ;

\ NOTE: cc-emit-jmp-vaddr (which emits a backward unconditional jump to an
\ absolute vaddr — needed for `while`/`for` loops) lives in 112-cc-stmt.fth
\ alongside the loop constructs that use it, not here with the primitive
\ encoders.  Both cc-base-vaddr and cc-out-pos are already available when this
\ file loads, so the split is organizational, not a load-order dependency.

\ ===========================================================================
\ movabs rdi, imm64 — used for loading string-literal addresses.
\ ===========================================================================
\ Encoding: 48 BF <imm64-LE>  (10 bytes total).

: cc-emit-movabs-rdi-imm64                        ( v -- )
  x{ 48 bf } cc-emit-8le ;                        \ movabs rdi, imm64

\ cc-emit-mov-rdi-int ( v -- )  Load an integer literal into rdi using the
\ shortest correct encoding.  `mov rdi, imm32` (7 bytes) sign-extends its
\ 32-bit field, so it only represents values in signed-32 range; a wider
\ constant (e.g. 0x80000000 or 2^32) would be sign-extended or truncated.
\ For those, fall back to the 10-byte `movabs rdi, imm64`.  C literals are
\ always non-negative here (a leading `-` is unary minus, applied later), so
\ only the upper bound needs checking — which keeps every in-range constant
\ on the exact imm32 bytes it emitted before.
: cc-emit-mov-rdi-int                             ( v -- )
  \ Unsigned magnitude also catches literals with bit 63 set.
  dup [lit] 2147483648 / if,
    cc-emit-movabs-rdi-imm64
  else, cc-emit-mov-rdi-imm32 then, ;

\ cc-emit-movabs-rdi-imm64-placeholder ( -- patch-offset )
\ Emits `48 BF 00 00 00 00 00 00 00 00`; returns the imm64 file-offset.
\ Used when a forward-declared function's name is taken as an rvalue
\ (function-pointer load) before its definition is reached.  Caller threads
\ patch-offset onto the prototype symbol's cc-sym-addr-fixups list; the
\ list is walked and each 8-byte imm64 is patched to the function's real
\ vaddr when cc-parse-function processes its definition.
: cc-emit-movabs-rdi-imm64-placeholder
  x{ 48 bf } cc-out-pos @ 0 cc-emit-8le ;         \ movabs rdi, imm64

\ cc-add-fixup-to-list ( fixup-offset list-var -- )  Allocate a 16-byte node
\ and prepend it to the linked list rooted at list-var.  Defined here so
\ 100-cc-expr.fth (loaded before 112-cc-stmt.fth) can reference it from the
\ forward-function-rvalue path in cc-parse-primary.
: cc-add-fixup-to-list                            ( off var -- )
  [lit] 16 cc-alloc                               ( off var node )
  >r                                              ( off var ; R: node )
  swap r@ !                                       ( var ; R: node )
  dup @ r@ [lit] 8 + !                            ( var ; R: node )
  r> swap ! ;                                     ( -- )

\ ===========================================================================
\ String-literal byte emission with C-escape decoding.
\ ===========================================================================
\ Walks ( src-addr src-len ) and copies bytes into cc-out-buf, decoding each
\ escape with cc-decode-escape (050), the same table character literals
\ use.  Appends a trailing NUL byte.
\
\ Stack convention inside the loop: ( src len ).

: cc-emit-string-bytes                            ( src-addr src-len -- )
  begin,
    dup [lit] 0 >
  while,
    over c@ backslash = if,
      dup [lit] 2 >= if,
        \ Have at least one more byte for the escape.
        over 1+ cc-decode-escape                  ( src len byte n )
        swap cc-emit-byte 1+                      ( src len k )
        \ Advance src by k (the backslash and the escape), len by -k.
        >r swap r@ + swap r> -
      else,
        \ Trailing backslash with no follow-up char: emit literally.
        over c@ cc-emit-byte
        swap 1+ swap 1-
      then,
    else,
      over c@ cc-emit-byte
      swap 1+ swap 1-
    then,
  repeat,
  drop drop
  0 cc-emit-byte ;                                \ trailing NUL terminator

\ ===========================================================================
\ Shifts, bitwise ops, inc/dec/neg/not on rdi
\ ===========================================================================
\ Variable-count shifts use rcx (specifically CL).  The binary-op pattern
\ leaves rdi=left and rcx=right (already in rcx because of mov rcx,rdi+pop).
\
\ shl rdi, cl: 48 D3 E7   (D3 /4, mod=11 rm=rdi=7 -> 11_100_111=0xE7)
: cc-emit-shl-rdi-cl
  x{ 48 d3 e7 } ;                                 \ shl rdi, cl

\ sar rdi, cl (arithmetic right shift, signed): 48 D3 FF  (D3 /7 -> 11_111_111=0xFF)
: cc-emit-sar-rdi-cl
  x{ 48 d3 ff } ;                                 \ sar rdi, cl

\ and rdi, rcx: 48 21 CF  (21 /r, mod=11 reg=rcx=1 rm=rdi=7 -> 11_001_111=0xCF)
: cc-emit-and-rdi-rcx
  x{ 48 21 cf } ;                                 \ and rdi, rcx

\ or rdi, rcx: 48 09 CF
: cc-emit-or-rdi-rcx
  x{ 48 09 cf } ;                                 \ or rdi, rcx

\ xor rdi, rcx: 48 31 CF
: cc-emit-xor-rdi-rcx
  x{ 48 31 cf } ;                                 \ xor rdi, rcx

\ not rdi: 48 F7 D7  (F7 /2 = NOT, mod=11 rm=rdi=7 -> 11_010_111=0xD7)
: cc-emit-not-rdi
  x{ 48 f7 d7 } ;                                 \ not rdi

\ neg rdi: 48 F7 DF  (F7 /3 = NEG, mod=11 rm=rdi=7 -> 11_011_111=0xDF)
: cc-emit-neg-rdi
  x{ 48 f7 df } ;                                 \ neg rdi


\ cc-emit-not-zero-flag.  Canonicalize rdi to 0/1 = (rdi == 0).
\ Pattern: xor rax,rax; test rdi,rdi; sete al; mov rdi,rax.  Used by unary '!'.
: cc-emit-not-zero-flag
  x{ 48 31 c0 }                                   \ xor rax, rax
  x{ 48 85 ff }                                   \ test rdi, rdi
  x{ 0f 94 c0 }                                   \ sete al
  x{ 48 89 c7 } ;                                 \ mov rdi, rax

\ ===========================================================================
\ File-scope global variables.
\ ===========================================================================
\ Globals live in two areas placed after the code, in the same PT_LOAD
\ segment:
\   data  scalars, and whatever has an initializer.  Built in
\         cc-globals-buf during parsing (initializer bytes are written
\         straight in; the rest stays zero) and appended to the output
\         file.
\   bss   arrays.  They start zeroed, so they take no room in the file:
\         the segment's p_memsz simply extends past its p_filesz, and
\         the kernel zero-fills the difference.
\ Each global gets a SLOT: its offset in the data area, or cc-bss-flag
\ plus its offset in the bss.
\
\ At codegen time, an IDENT referring to a sk-global emits
\     movabs rdi, <imm64 placeholder = 0>          ; 10 bytes
\ and records (patch-offset-in-cc-out-buf, slot) into the cc-gfixup arrays.
\
\ At cc-finalize-globals (called after parsing, before cc-finalize-elf):
\   1. cc-globals-base-vaddr := cc-here-vaddr (080); the bss starts at
\      the first 8-aligned address after the data.
\   2. Append cc-globals-buf bytes to cc-out-buf.
\   3. For each fixup, compute the slot's vaddr and patch the placeholder
\      imm64 in cc-out-buf at the recorded patch-offset.

[lit] 65536 constant cc-globals-cap                \ data area: 64 KiB
create cc-globals-buf  cc-globals-cap allot
variable cc-globals-pos

[lit] 268435456 constant cc-bss-cap                \ bss: 256 MiB
variable cc-bss-pos
[lit] 1099511627776 constant cc-bss-flag           \ 2^40: "this slot is in the bss"

\ Capacity for deferred global-vaddr fixups (each use of a global's name
\ is one).  M2-Planet's source has about 1,600.
[lit] 16384 constant cc-gfixup-default-cap
variable cc-gfixup-limit
cc-gfixup-default-cap cc-gfixup-limit !
: cc-gfixup-cap ( -- entries ) cc-gfixup-limit @ ;
create cc-gfixup-default-out-pos cc-gfixup-default-cap [lit] 8 * allot
variable cc-gfixup-out-pos-buffer
cc-gfixup-default-out-pos cc-gfixup-out-pos-buffer !
: cc-gfixup-out-pos ( -- address ) cc-gfixup-out-pos-buffer @ ;
create cc-gfixup-default-slot cc-gfixup-default-cap [lit] 8 * allot
variable cc-gfixup-slot-buffer
cc-gfixup-default-slot cc-gfixup-slot-buffer !
: cc-gfixup-slot ( -- address ) cc-gfixup-slot-buffer @ ;
variable cc-gfixup-count

variable cc-globals-base-vaddr                   \ set by cc-finalize-globals
variable cc-bss-base-vaddr                       \ set by cc-finalize-globals

\ cc-globals-init ( -- )  Reset globals + fixup state at the start of compile.
: cc-globals-init
  [lit] 0 cc-globals-pos !
  [lit] 0 cc-bss-pos !
  [lit] 0 cc-gfixup-count !
  [lit] 0 cc-globals-base-vaddr !
  \ Zero the globals buffer so uninitialized globals are guaranteed zero
  \ even if a previous run left bytes in there.  Loop walks i = 0..cap-1.
  [lit] 0
  begin, dup cc-globals-cap < while,
    [lit] 0 over cc-globals-buf + c!
    1+
  repeat, drop ;

\ cc-globals-alloc ( bytes -- slot )  Reserve `bytes` bytes of the data
\ area; return the offset of the first reserved byte.  Dies with 80 if
\ cc-globals-buf would overflow.
: cc-globals-alloc                                 ( bytes -- slot )
  dup cc-globals-pos @ + cc-globals-cap [lit] 80 cc-check-cap
  cc-globals-pos @                                 ( bytes slot )
  swap                                              ( slot bytes )
  cc-globals-pos +! ;

\ cc-bss-alloc ( bytes -- slot )  Reserve `bytes` zeroed bytes in the bss;
\ return the slot (cc-bss-flag + offset).  Dies with 82 past cc-bss-cap.
: cc-bss-alloc                                     ( bytes -- slot )
  dup cc-bss-pos @ + cc-bss-cap [lit] 82 cc-check-cap
  cc-bss-pos @ cc-bss-flag +                       ( bytes slot )
  swap cc-bss-pos +! ;

\ cc-gfixup-add ( patch-offset slot -- )  Record a deferred global-vaddr fixup.
\ Indexes its two parallel arrays with cell[] (030-cc-io.fth).
: cc-gfixup-add                                    ( patch-off slot -- )
  cc-gfixup-count @ 1+ cc-gfixup-cap [lit] 81 cc-check-cap
  cc-gfixup-count @                                 ( patch-off slot i )
  >r                                                \ park i on rstack
  r@ cc-gfixup-slot     cell[] !                   \ store slot
  r@ cc-gfixup-out-pos  cell[] !                   \ store patch-off
  r> drop
  [lit] 1 cc-gfixup-count +! ;

\ cc-emit-global-ref ( slot -- )  Emit `movabs rdi, <vaddr placeholder>` and
\ record a deferred fixup so the imm64 will be patched to the slot's
\ address once globals are placed.  Used by the sk-global IDENT path in
\ cc-parse-primary.
: cc-emit-global-ref                                ( slot -- )
  x{ 48 bf } cc-out-pos @ 0 cc-emit-8le           \ movabs rdi, imm64
  swap cc-gfixup-add ;

\ ===========================================================================
\ Opt-in LP64 integer encoders.
\ ===========================================================================
\ The original words above stay byte-identical.  The typed wrappers retain
\ their legacy encodings while cc-target-lp64 is 0.  Scalar floating types
\ have storage sizes in 060, but these words implement integer operations.
\ A typed store writes only the destination width; use convert-rdi first
\ when the assignment expression must retain a correctly converted result.

\ cc-emit-load-typed-via-rdi ( ty -- )  rdi := *(T *)rdi.
: cc-emit-type-check-noop ;
defer cc-emit-type-check-fwd
' cc-emit-type-check-noop is cc-emit-type-check-fwd

: cc-emit-load-typed-via-rdi
  cc-emit-type-check-fwd
  dup ty-size [lit] 1 = if,
    ty-unsigned? if, cc-emit-load-byte-via-rdi else,
      x{ 48 0f be 3f }                            \ movsx rdi, byte [rdi]
    then, exit,
  then,
  dup ty-size [lit] 2 = if,
    x{ 48 0f }
    ty-unsigned? if, $b7 else, $bf then, cc-emit-byte
    x{ 3f } exit,                                 \ movzx/movsx rdi, word [rdi]
  then,
  dup ty-size [lit] 4 = if,
    ty-unsigned? if,
      x{ 8b 3f }                                  \ mov edi, dword [rdi]
    else,
      x{ 48 63 3f }                               \ movsxd rdi, dword [rdi]
    then, exit,
  then,
  drop cc-emit-load-via-rdi ;

\ cc-emit-store-typed-via-rcx ( ty -- )  *(T *)rcx := rdi.
: cc-emit-store-typed-via-rcx
  cc-emit-type-check-fwd
  ty-size
  dup [lit] 1 = if, drop cc-emit-store-byte-via-rcx exit, then,
  dup [lit] 2 = if,
    drop x{ 66 89 39 } exit,                      \ mov word [rcx], di
  then,
  [lit] 4 = if,
    x{ 89 39 }                                    \ mov dword [rcx], edi
  else, cc-emit-store-via-rcx then, ;

\ cc-emit-convert-rdi ( ty -- )  Truncate/sign-extend the integer in rdi.
: cc-emit-convert-rdi
  cc-emit-type-check-fwd
  dup ty-size [lit] 1 = if,
    ty-unsigned? if, cc-emit-zx-byte-rdi else,
      x{ 48 0f be ff }                            \ movsx rdi, dil
    then, exit,
  then,
  dup ty-size [lit] 2 = if,
    x{ 48 0f }
    ty-unsigned? if, $b7 else, $bf then, cc-emit-byte
    x{ ff } exit,                                 \ movzx/movsx rdi, di
  then,
  dup ty-size [lit] 4 = if,
    ty-unsigned? if,
      x{ 89 ff }                                  \ mov edi, edi
    else,
      x{ 48 63 ff }                               \ movsxd rdi, edi
    then, exit,
  then,
  drop ;

\ Conversions with source type preserve the integer emitter by default.
: cc-emit-convert-value-default ( source destination -- ) nip cc-emit-convert-rdi ;
defer cc-emit-convert-value
' cc-emit-convert-value-default is cc-emit-convert-value

\ cc-emit-convert-rcx ( ty -- )  Same conversion for the right operand.
: cc-emit-convert-rcx
  cc-emit-type-check-fwd
  dup ty-size [lit] 1 = if,
    x{ 48 0f }
    ty-unsigned? if, $b6 else, $be then, cc-emit-byte
    x{ c9 } exit,                                 \ movzx/movsx rcx, cl
  then,
  dup ty-size [lit] 2 = if,
    x{ 48 0f }
    ty-unsigned? if, $b7 else, $bf then, cc-emit-byte
    x{ c9 } exit,                                 \ movzx/movsx rcx, cx
  then,
  dup ty-size [lit] 4 = if,
    ty-unsigned? if,
      x{ 89 c9 }                                  \ mov ecx, ecx
    else,
      x{ 48 63 c9 }                               \ movsxd rcx, ecx
    then, exit,
  then,
  drop ;

: cc-emit-convert-right-default ( source destination -- ) nip cc-emit-convert-rcx ;
defer cc-emit-convert-right
' cc-emit-convert-right-default is cc-emit-convert-right

\ cc-emit-load-local-typed ( slot ty -- )  LP64 memory width, legacy qword.
: cc-emit-load-local-typed
  swap cc-emit-lea-rdi-local cc-emit-load-typed-via-rdi ;

\ Unsigned division clears rdx, then DIV rcx uses the full rdx:rax dividend.
\ Both operands must already have been converted to the common C type.
: cc-emit-udiv-quotient
  cc-emit-mov-rax-rdi
  x{ 31 d2 }                                      \ xor edx, edx
  x{ 48 f7 f1 }                                   \ div rcx
  cc-emit-mov-rdi-rax ;                            \ div rcx; mov rdi, rax

: cc-emit-udiv-remainder
  cc-emit-mov-rax-rdi
  x{ 31 d2 }                                      \ xor edx, edx
  x{ 48 f7 f1 }                                   \ div rcx
  x{ 48 89 d7 } ;                                 \ mov rdi, rdx

: cc-emit-cmp-ult $92 cc-emit-cmp-set ;           \ setb al
: cc-emit-cmp-uge $93 cc-emit-cmp-set ;           \ setae al
: cc-emit-cmp-ule $96 cc-emit-cmp-set ;           \ setbe al
: cc-emit-cmp-ugt $97 cc-emit-cmp-set ;           \ seta al

\ Logical (unsigned) right shift: shr rdi, cl = 48 D3 EF.
: cc-emit-shr-rdi-cl
  x{ 48 d3 ef } ;                                 \ shr rdi, cl

\ ===========================================================================
\ Sequences of the native call ABI and of struct copies.
\ ===========================================================================
\ Their callers are in 100, 112, 116 and 118.  They are named here, with
\ the other encoders, so that a second target can supply its own by
\ redefining them after this file (cc/i386/090-emit.fth does).

\ cc-emit-scale-rdi ( bytes -- )  rdi *= bytes: an index becomes an offset.
: cc-emit-scale-rdi
  dup [lit] 1 = if, drop exit, then,
  dup [lit] 8 = if, drop cc-emit-shl-rdi-3 exit, then,
  x{ 48 69 ff } cc-emit-4le ;                     \ imul rdi, rdi, imm32

\ The native bootstrap image uses an internal all-stack call ABI.
\ Arguments occupy eight-byte slots; arg 0 is nearest the return address.
\ cc-native-swap-args ( off1 off2 -- )  Exchange the slots at two offsets
\ from rsp.
: cc-native-swap-args
  >r
  dup x{ 48 8b 84 24 } cc-emit-4le                \ mov rax, qword [rsp+off1]
  r@ x{ 48 8b 8c 24 } cc-emit-4le                 \ mov rcx, qword [rsp+off2]
  x{ 48 89 8c 24 } cc-emit-4le                    \ mov qword [rsp+off1], rcx
  r> x{ 48 89 84 24 } cc-emit-4le ;               \ mov qword [rsp+off2], rax

\ cc-native-drop-args ( n -- )  Release n argument slots after a call.
: cc-native-drop-args
  dup if,
    x{ 48 81 c4 } [lit] 8 * cc-emit-4le           \ add rsp, n*8
  else, drop then, ;

\ cc-native-load-call-target ( n -- )  rax := the function address pushed
\ before a call's n arguments.
: cc-native-load-call-target
  x{ 48 8b 84 24 } [lit] 8 * cc-emit-4le ;        \ mov rax, qword [rsp+n*8]

\ mov rdi, rdx: 48 89 D7.  A postfix ++ or -- kept the old value in rdx.
: cc-emit-mov-rdi-rdx
  x{ 48 89 d7 } ;                                 \ mov rdi, rdx

\ mov rsi, rdi: 48 89 FE.  rdi holds the source address of a copy.
: cc-emit-mov-rsi-rdi
  x{ 48 89 fe } ;                                 \ mov rsi, rdi

\ cc-emit-rep-count ( n -- )  rcx := n, the byte count of the rep movsb or
\ rep stosb that follows; rdi holds its destination.  cc-emit-rep-count-rcx
\ is the same instruction in its REX.W spelling, which struct assignment
\ (100) has always emitted; initializers (118) emit the short one.
: cc-emit-rep-count
  x{ b9 } cc-emit-4le ;                           \ mov ecx, imm32
: cc-emit-rep-count-rcx
  x{ 48 c7 c1 } cc-emit-4le ;                     \ mov rcx, imm32

\ cmp rbx, rdi: 48 39 FB.  A switch label too wide for cmp rbx, imm32 is
\ loaded into rdi first.
: cc-emit-cmp-rbx-rdi
  x{ 48 39 fb } ;                                 \ cmp rbx, rdi

\ cc-out-patch-address ( vaddr offset -- )  Fill in the placeholder that
\ cc-emit-movabs-rdi-imm64-placeholder or cc-emit-global-ref left at offset.
: cc-out-patch-address  cc-out-patch-8le ;
