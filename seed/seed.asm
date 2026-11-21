; seed.asm -- seed/000-seed.hex0 as NASM source.
;
; 000-seed.hex0 is what gets built, by stage0-posix's hex0-seed alone.
; This file is the same program with labels where the hex0 has numbers;
; seed/asm2hex0.py writes the hex0 from it, and seed/check.sh proves the
; two agree.  Edit this file, then run seed/asm2hex0.py.
;
; A ";;" line is copied into the hex0 as it stands, so the text there is
; written for a reader of the hex0.  A ";" line, like these, is not copied.
; A comment on an instruction becomes that line's comment in the hex0.

;; 000-seed.hex0 — x86-64 Linux Forth Seed
;;
;; This file is a synthesis artifact of AI-collaborative research.
;; Co-authored by an ensemble of LLMs (Claude, Gemini, Codex, DeepSeek,
;; Qwen, Kimi, Gemma, MiniMax) under human architectural direction.
;;
;; License: MIT (see /LICENSE)
;;
;; What this is: the smallest Forth that can load forth/010-lib.fth.  It
;; reads whitespace-separated tokens from stdin.  A token that names a
;; word is run, or, inside a colon definition, compiled as a CALL to it;
;; any other token must be an unsigned decimal number, which is pushed or
;; compiled.  It has 21 words written in machine code; everything else,
;; from `here` and `if,` to the outer interpreter that replaces the loop
;; below, is Forth in forth/010-lib.fth.  seed/MINIMAL.md says what was
;; left out and where it went.
;;
;; How to read this file: the two ELF headers, then the code in the order
;; it runs: _start, the read-evaluate loop (repl) and the routines only it
;; calls, then the 21 words.  A word is its dictionary header (link,
;; flags, nlen, name) directly followed by its machine code, so a word's
;; execution token (xt) is the address of its code.  Every line is one
;; field or one instruction; the text after ';' is a comment (hex0
;; ignores it).  Addresses are file offsets; the image loads at 0x400000,
;; so offset 0xNNN is address 0x400NNN.
;;
;; This file is generated from seed/seed.asm by seed/asm2hex0.py, which
;; computes the offsets and branch distances; seed/check.sh proves that
;; nasm on seed.asm and hex0 on this file give the same bytes, and
;; tests/seed/asm-check.py that GNU as on the comments below does too.
bits 64
org 0x400000

STATE      equ 0
LATEST     equ 8
HERE       equ 16
LAST_FOUND equ 24
KEYBUF     equ 32
TIB        equ 64

; HEADER label, "name", flags: one dictionary header, linked to the one
; before it.  asm2hex0.py writes its four fields out one per line.
%define LINK 0
%macro HEADER 3
hdr_%1:
        dq LINK
        db %3
        db %%end - %%name
%%name: db %2
%%end:
%xdefine LINK hdr_%1
%endmacro

;;
;; ===== ELF64 header (64 bytes) @ 0x000 =====
;; Layout reference: man 5 elf, Elf64_Ehdr
        db 0x7F, "ELF"          ; e_ident[0..3]     = magic "\x7fELF"
        db 2                    ; e_ident[EI_CLASS] = ELFCLASS64
        db 1                    ; e_ident[EI_DATA]  = ELFDATA2LSB (little-endian)
        db 1                    ; e_ident[EI_VERSION] = EV_CURRENT
        db 0                    ; e_ident[EI_OSABI] = ELFOSABI_NONE (System V)
        db 0                    ; e_ident[EI_ABIVERSION] = 0
        times 7 db 0            ; e_ident padding (7 zero bytes)
        dw 2                    ; e_type      = ET_EXEC
        dw 62                   ; e_machine   = EM_X86_64
        dd 1                    ; e_version   = 1
        dq _start               ; e_entry     = ? (_start)
        dq 64                   ; e_phoff     = 64
        dq 0                    ; e_shoff     = 0 (no section headers)
        dd 0                    ; e_flags     = 0
        dw 64                   ; e_ehsize    = 64
        dw 56                   ; e_phentsize = 56
        dw 1                    ; e_phnum     = 1
        dw 0                    ; e_shentsize = 0
        dw 0                    ; e_shnum     = 0
        dw 0                    ; e_shstrndx  = 0

;; ===== Program header (56 bytes) @ 0x040, one PT_LOAD =====
        dd 1                    ; p_type   = PT_LOAD
        dd 7                    ; p_flags  = R|W|X
        dq 0                    ; p_offset = 0
        dq 0x400000             ; p_vaddr  = 0x400000
        dq 0x400000             ; p_paddr  = 0x400000 (ignored on Linux)
        dq file_end - $$        ; p_filesz = ? (the whole file)
        dq 0x1000000            ; p_memsz  = 0x1000000 (16 MiB; the kernel zero-fills past the file)
        dq 0x1000               ; p_align  = 0x1000

;; ===== Code at 0x400078 =====
;; Register and memory conventions used by every routine below:
;;   rbp      = data-stack pointer (grows down); rdi = top of stack (TOS)
;;   rsp      = return stack (the x86 call stack)
;;   rbx      = the sysvar page, 0x413000; never changed after _start
;;   0x411000 = data-stack base (first push lands at 0x410FF8)
;;   0x413000 = sysvar page.  Offsets from rbx:
;;              STATE +0, LATEST +8, HERE +16, LAST_FOUND +24, KEYBUF +32, TIB +64
;;              STATE       0 = interpreting, 1 = compiling a definition
;;              LATEST      the newest dictionary header
;;              HERE        the first free byte (code and data grow up)
;;              LAST_FOUND  the header find matched last
;;              KEYBUF      the byte key reads into
;;              TIB         the token buffer: 256 bytes, and 2 for fatal's "?\n"
;;   0x401000 = first free byte, the initial HERE
;; Stack comments ( before -- after ) show the data stack, top rightmost.
;; "push" is sub rbp, 8 / mov [rbp], rdi (dup); "pop" is the reverse (drop).
;; A write to a 32-bit register (mov edi, 2) clears the upper half of the
;; 64-bit one, so it is used where the value fits in 32 bits.
_start:                         ; entry point: the two stacks' registers and the sysvars
        mov ebp, 0x411000       ; data-stack base (empty: TOS holds nothing yet)
        mov ebx, 0x413000       ; the sysvar page
        mov qword [rbx+LATEST], hdr_semicolon ; the last header in this file
        mov qword [rbx+HERE], 0x401000
;; STATE and LAST_FOUND start at 0: the page is past the end of the file,
;; and the kernel zero-fills the segment from p_filesz to p_memsz.
;; Execution continues into repl.

repl:                           ; read a token, find it, run or compile it; loop.  Never returns.
        call token_code         ; ( -- c-addr u )
        test rdi, rdi
        jz end_of_input         ; u = 0: nothing left to read
        push rdi                ; keep u for number, in case find misses
        call find_code          ; ( c-addr u -- xt | 0 )
        pop rcx                 ; rcx = u
        test rdi, rdi
        jz number               ; not a word: it has to be a number
        mov rax, [rbx+LAST_FOUND]
        test byte [rax+8], 1    ; the flags byte: IMMEDIATE?
        jnz .execute            ; yes: run it now, in either mode
        cmp qword [rbx+STATE], 0
        je .execute             ; interpreting: run it
        call compile_call       ; ( xt -- ) compiling: CALL xt at HERE
        jmp repl
.execute:
        mov rax, rdi            ; rax = xt
        call drop_code          ; ( xt -- )
        call rax                ; run the word; it returns here
        jmp repl

number:                         ; ( 0 -- n | ) the token as unsigned decimal; rcx = its length.  Jumps back to repl.
;; Reached from repl when find misses, so TOS is find's 0 and becomes n:
;; n = n*10 + digit for each byte.  A byte that is not a digit is fatal;
;; a value past 64 bits wraps.  Interpreting, n stays on the stack.
;; Compiling, CALL lit and the cell n are laid at HERE.
        xor edx, edx            ; rdx = index of the next byte
.digit:
        movzx eax, byte [rbx+rdx+TIB]
        sub eax, 0x30           ; - '0'
        cmp eax, 9
        ja fatal                ; unsigned compare: also true for bytes below '0'
        imul rdi, rdi, 10       ; n * 10
        add rdi, rax            ; + digit
        inc edx
        cmp edx, ecx
        jne .digit
        cmp qword [rbx+STATE], 0
        je repl                 ; interpreting: n stays on the stack
        call dup_code           ; ( n -- n n )
        mov edi, lit_code       ; ( n lit ) TOS = lit's address
        call compile_call       ; ( n lit -- n ) CALL lit at HERE
        mov rax, [rbx+HERE]
        mov [rax], rdi          ; the cell n, right after the CALL
        add rax, 8
        mov [rbx+HERE], rax     ; HERE += 8
        call drop_code          ; ( n -- )
        jmp repl

fatal:                          ; write the token and "?\n" to stdout, then exit(2); rcx = the token's length
;; The seed's only error: a token that is neither a word nor a decimal
;; number, or one 256 bytes long (too long for a header's nlen byte).
        mov word [rbx+rcx+TIB], 0x0A3F ; '?' and newline after the token
        lea edx, [rcx+2]        ; count = length + 2
        lea rsi, [rbx+TIB]      ; buf = the token
        mov edi, 1              ; fd 1 (stdout)
        mov eax, 1              ; SYS_write
        syscall
        mov edi, 2              ; status 2: bad input
        jmp exit

end_of_input:                   ; exit(0)
        xor edi, edi            ; status 0
;; Execution continues into exit.

exit:                           ; exit(edi); never returns
        mov eax, 60             ; SYS_exit
        syscall

compile_call:                   ; ( xt -- ) lay down CALL xt (E8 rel32) at HERE
        mov rax, [rbx+HERE]
        mov byte [rax], 0xE8    ; the CALL opcode
        add rax, 5              ; rax = the address after the CALL
        mov [rbx+HERE], rax     ; HERE += 5
        sub rdi, rax            ; rel32 = xt - the address after the CALL
        mov [rax-4], edi
        jmp drop_code           ; ( xt -- ) and return to our caller

lit_code:                       ; ( -- n ) push the 8-byte cell after the CALL, resume after the cell
;; What number compiles a CALL to.  Not a dictionary word.
        pop rax                 ; rax = our return address = the cell
        call dup_code           ; push the old TOS
        mov rdi, [rax]          ; TOS = the cell
        add rax, 8              ; step past it
        jmp rax                 ; resume there

;; ===== The 21 words =====
;; The reader first: token, its helper read_char, and the word they read
;; through, key.

HEADER token, "token", 0
token_code:                     ; ( -- c-addr u ) the next token from stdin, in the TIB; u = 0 at end of input
;; Skips whitespace, then copies bytes to the TIB until whitespace or end
;; of input.  Whitespace is any byte up to space (0x20): tab, newline and
;; carriage return are below it, and so is key's 0 for end of input, which
;; the two places that could loop on it test for.  A token that is exactly
;; \ starts a comment: the rest of its line is skipped and reading starts
;; over.  A token of 256 bytes is fatal.  Bytes come through key's
;; dictionary entry point, so a library that replaces key (cc/020) is read
;; through its replacement.
.restart:
        xor ecx, ecx            ; rcx = length so far
.skip:
        call read_char          ; al = the next byte
        test al, al
        jz .done                ; end of input before a token: u = 0
        cmp al, 0x20
        jbe .skip               ; whitespace: keep skipping
.store:
        mov [rbx+rcx+TIB], al   ; TIB[length] = the byte
        inc ecx
        test ch, ch             ; ch = bits 8-15 of rcx: non-zero once length is 256
        jnz fatal
        call read_char
        cmp al, 0x20
        ja .store               ; not whitespace or end of input: part of the token
;; The token is complete; al holds the byte that ended it.
        cmp ecx, 1
        jne .done
        cmp byte [rbx+TIB], 0x5C ; is the token exactly '\'?
        jne .done
.comment:
        cmp al, 0x0A            ; reached the newline?
        je .restart             ; comment over: read the next token
        test al, al
        jz .restart             ; end of input: start over (and return u = 0)
        call read_char
        jmp .comment
.done:
        call dup_code           ; push the old TOS
        lea rdi, [rbx+TIB]      ; c-addr = the TIB
        call dup_code           ; push c-addr
        mov rdi, rcx            ; u = length
        ret

read_char:                      ; ( -- ) al = the next input byte, 0 at end of input.  Keeps rcx.
        push rcx                ; key's syscall overwrites rcx
        call key_code           ; ( -- c )
        pop rcx
        mov eax, edi            ; al = c
        jmp drop_code           ; ( c -- ) and return to our caller

HEADER key, "key", 0
key_code:                       ; ( -- c ) read one byte from stdin; 0 at end of input
        call dup_code           ; push the old TOS
        xor eax, eax            ; SYS_read
        xor edi, edi            ; fd 0 (stdin)
        lea rsi, [rbx+KEYBUF]   ; buf
        mov edx, 1              ; count 1
        syscall                 ; overwrites rcx and r11
        test rax, rax
        jle .end                ; 0 bytes read = end of input; negative = error, taken as the same
        movzx edi, byte [rsi]   ; c = the byte
        ret
.end:
        xor edi, edi            ; c = 0
        ret

HEADER find, "find", 0
find_code:                      ; ( c-addr u -- xt | 0 ) look a name up in the dictionary
;; Walks the chain of headers from LATEST.  On a hit, stores the header's
;; address in LAST_FOUND (repl reads its flags byte) and returns the xt:
;; the first byte after the name, which is where the word's code starts.
        mov rsi, [rbp]          ; rsi = c-addr
        add rbp, 8              ; pop it; rdi = u
        mov rdx, [rbx+LATEST]   ; rdx = the newest header
.next:
        test rdx, rdx
        jz .miss                ; link 0: end of the chain
        movzx eax, byte [rdx+9] ; nlen
        cmp rax, rdi
        jne .skip               ; lengths differ
        xor eax, eax            ; rax = index of the next byte to compare
.bytes:
        cmp rax, rdi
        je .hit                 ; all u bytes matched
        mov cl, [rdx+rax+10]    ; a byte of the header's name
        cmp cl, [rsi+rax]       ; the same byte of the token
        jne .skip
        inc eax
        jmp .bytes
.skip:
        mov rdx, [rdx]          ; follow the link to the header before
        jmp .next
.hit:
        mov [rbx+LAST_FOUND], rdx
        lea rdi, [rdx+rdi+10]   ; xt = header + 10 + nlen (rdi is u, and u = nlen here)
        ret
.miss:
        xor edi, edi            ; not found: 0
        ret

;; The data stack.

HEADER dup, "dup", 0
dup_code:                       ; ( a -- a a )
        sub rbp, 8
        mov [rbp], rdi
        ret

HEADER drop, "drop", 0
drop_code:                      ; ( a -- )
        mov rdi, [rbp]
        add rbp, 8
        ret

HEADER swap, "swap", 0
swap_code:                      ; ( a b -- b a )
        mov rax, [rbp]
        mov [rbp], rdi
        mov rdi, rax
        ret

;; The return stack.  These are CALLed, so their own return address is on
;; top of it; they take it off first and go back through it at the end.

HEADER to_r, ">r", 0
to_r_code:                      ; ( n -- ; R: -- n )
        pop rax                 ; our return address
        push rdi                ; n onto the return stack
        push rax                ; return address back on top
        jmp drop_code           ; ( n -- ) and return to our caller

HEADER r_from, "r>", 0
r_from_code:                    ; ( -- n ; R: n -- )
        pop rax                 ; our return address
        call dup_code           ; push the old TOS
        pop rdi                 ; TOS = n, off the return stack
        jmp rax                 ; return to our caller

;; Memory.

HEADER fetch, "@", 0
fetch_code:                     ; ( addr -- v )
        mov rdi, [rdi]
        ret

HEADER store, "!", 0
store_code:                     ; ( v addr -- )
        mov rax, [rbp]          ; rax = v
        mov [rdi], rax          ; *addr = v
        add rbp, 8              ; pop v
        jmp drop_code           ; ( addr -- ) and return to our caller

HEADER cfetch, "c@", 0
cfetch_code:                    ; ( addr -- b )
        movzx edi, byte [rdi]
        ret

HEADER cstore, "c!", 0
cstore_code:                    ; ( b addr -- )
        mov rax, [rbp]          ; rax = b
        mov [rdi], al           ; store the low byte only
        add rbp, 8              ; pop b
        jmp drop_code           ; ( addr -- ) and return to our caller

;; Arithmetic and logic.

HEADER plus, "+", 0
plus_code:                      ; ( a b -- a+b )
        add rdi, [rbp]
        add rbp, 8
        ret

HEADER nand, "nand", 0
nand_code:                      ; ( a b -- ~(a&b) )
        and rdi, [rbp]
        not rdi
        add rbp, 8
        ret

HEADER zeq, "0=", 0
zeq_code:                       ; ( n -- flag ) -1 if n = 0, else 0
        test rdi, rdi
        sete dil                ; dil = 1 if n = 0, else 0
        movzx edi, dil
        neg rdi                 ; 1 -> -1 (Forth true)
        ret

HEADER star, "*", 0
star_code:                      ; ( a b -- a*b ) low 64 bits of the product
        imul rdi, [rbp]
        add rbp, 8
        ret

HEADER divide, "/", 0
divide_code:                    ; ( a b -- a/b ) unsigned 64-bit divide
;; rdx:rax / rdi -> rax = quotient, rdx = remainder.  rdx is zeroed, so the
;; dividend is 64-bit.  b = 0 traps (SIGFPE); callers must not pass it.
        mov rax, [rbp]          ; rax = a (dividend)
        xor edx, edx            ; high half = 0
        div rdi                 ; rdx:rax / rdi
        mov rdi, rax            ; TOS = quotient
        add rbp, 8              ; pop a
        ret

;; The operating system.

HEADER syscall6, "syscall6", 0
syscall6_code:                  ; ( a b c d e f n -- rax )
;; Linux x86-64: rax=n, rdi=a, rsi=b, rdx=c, r10=d, r8=e, r9=f.
;; Pops the six arguments; the new TOS is the syscall's return value.
        mov rax, rdi            ; rax = n (syscall number)
        mov r9, [rbp]           ; f
        mov r8, [rbp+8]         ; e
        mov r10, [rbp+16]       ; d
        mov rdx, [rbp+24]       ; c
        mov rsi, [rbp+32]       ; b
        mov rdi, [rbp+40]       ; a
        syscall                 ; overwrites rcx and r11
        add rbp, 48             ; pop the 6 argument cells
        mov rdi, rax            ; TOS = result
        ret

;; The compiler: state gives the library the sysvar page, : and ; make
;; definitions.

HEADER state, "state", 0
state_code:                     ; ( -- addr ) address of STATE, which is the sysvar page
        call dup_code           ; push the old TOS
        mov rdi, rbx
        ret

HEADER colon, ":", 0
colon_code:                     ; ( -- ) read a name, lay down its header at HERE, STATE = 1
        call token_code         ; ( -- c-addr u )
        mov rdx, [rbx+HERE]     ; rdx = the new header
        mov rax, [rbx+LATEST]
        mov [rdx], rax          ; link  = the newest header so far
        mov byte [rdx+8], 0     ; flags = 0
        mov [rdx+9], dil        ; nlen  = u
        mov [rbx+LATEST], rdx   ; the new header is the newest
        mov rcx, rdi            ; count = u
        mov rsi, [rbp]          ; from = c-addr
        lea rdi, [rdx+10]       ; to = the name field
        rep movsb               ; copy the name; rdi ends just past it
        mov [rbx+HERE], rdi     ; HERE = header + 10 + u
        mov rdi, [rbp+8]        ; drop c-addr and u
        add rbp, 16
        mov qword [rbx+STATE], 1
        ret

HEADER semicolon, ";", 1
semicolon_code:                 ; ( -- ) IMMEDIATE: append ret, STATE = 0
        mov rax, [rbx+HERE]
        mov byte [rax], 0xC3    ; the ret opcode
        inc rax
        mov [rbx+HERE], rax     ; HERE += 1
        mov qword [rbx+STATE], 0
        ret
file_end:
