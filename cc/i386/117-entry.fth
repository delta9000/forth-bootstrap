\ 117-entry.fth — the entry stub of an i386 program.
\
\ Loaded after 117-cc-native-program.fth, whose cc-native-entry and
\ cc-native-program these two words replace.
\
\ The stub runs first, at cc-entry-vaddr.  Linux needs none of its first
\ two steps; builder-hex0, the kernel these programs are also for, does:
\
\ 1. The break.  builder-hex0 starts a program's break 0x20000 bytes past
\    its file image, whatever the bss needs, and zeroes memory whenever
\    the break grows.  A larger bss would be wiped by the C library's first
\    allocation, so the stub moves the break to the end of the bss first.
\    Only upwards: builder-hex0 answers a request below the break by
\    zeroing all memory above it, files included.
\ 2. The stack.  builder-hex0 leaves the previous program's bytes below
\    esp, and a program that reads an uninitialized local (tcc's getcwd
\    buffer, which ends up in its debug output) would depend on them.  The
\    stub zeroes cc-entry-stack-zero bytes below esp, after the two system
\    calls, which write there themselves.  The first tcc needs far less:
\    the whole junction replay passes with a 48 KiB stack limit.
\ 3. The initializers of globals run (118), then main (argc, argv), each
\    argument in an 8-byte slot, argc nearest the return address.  The
\    kernel left argc at [esp] and argv's first element at [esp+4].
\ 4. exit with main's result.

[lit] 1048576 constant cc-entry-stack-zero       \ 1 MiB

: cc-native-entry
  x{ 31 db }                                      \ xor ebx, ebx
  x{ b8 } [lit] 45 cc-emit-4le                    \ mov eax, 45  (brk)
  x{ cd 80 }                                      \ int 0x80  (eax := the break)
  cc-out-pos @ 1+ cc-bss-end-patch !
  x{ bb } [lit] 0 cc-emit-4le                     \ mov ebx, imm32  (the end of the bss)
  x{ 39 d8 }                                      \ cmp eax, ebx
  x{ 73 07 }                                      \ jae +7
  x{ b8 } [lit] 45 cc-emit-4le                    \ mov eax, 45  (brk)
  x{ cd 80 }                                      \ int 0x80
  x{ 89 e7 }                                      \ mov edi, esp
  x{ 81 ef } cc-entry-stack-zero cc-emit-4le      \ sub edi, imm32
  x{ b9 } cc-entry-stack-zero cc-emit-4le         \ mov ecx, imm32
  x{ 31 c0 }                                      \ xor eax, eax
  x{ f3 aa }                                      \ rep stosb
  cc-native-init-entry-fwd
  x{ 8b 04 24 }                                   \ mov eax, dword [esp]  (argc)
  x{ 8d 4c 24 04 }                                \ lea ecx, [esp+4]  (argv)
  x{ 6a 00 }                                      \ push 0
  x{ 51 }                                         \ push ecx
  x{ 6a 00 }                                      \ push 0
  x{ 50 }                                         \ push eax
  cc-emit-call-rel32-placeholder cc-call-main-patch !
  x{ 89 c3 }                                      \ mov ebx, eax
  x{ b8 } [lit] 1 cc-emit-4le                     \ mov eax, 1  (exit)
  x{ cd 80 } ;                                    \ int 0x80

\ cc-native-program ( -- )  117's, word for word, so that it calls the
\ entry above and the runtime of cc/i386/119-runtime.fth.
: cc-native-program
  cc-native-entry
  cc-native-runtime-fwd
  begin,
    cc-skip-storage-quals cc-next-token-keep
    tok-kind @ tk-eof = 0= while,
    true cc-native-declaration
  repeat,
  cc-native-init-finish-fwd
  cc-check-fns-defined cc-patch-call-main ;
