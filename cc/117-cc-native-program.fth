\ 117-cc-native-program.fth — functions, the entry stub and the program.
\ All linked code is generated together. No system libc or host object is used.
variable cc-native-param-count
variable cc-native-frame-patch

: cc-native-params
  [lit] 0 cc-native-param-count !
  begin,
    cc-next-token-keep
    [char] ) cc-tok-punct? if, exit, then,
    pt-ellipsis cc-tok-punct? if, [char] ) cc-expect-punct-c exit, then,
    kw-void cc-tok-kw? if,
      cc-peek-mark cc-lex-mark cc-next-token-keep
      [char] ) cc-tok-punct? if, exit, then,
      cc-peek-mark cc-lex-reset
    then,
    cc-nbase nc-sdesc ! nc-base !
    cc-ndeclarator
    nc-array @ if, [lit] 1 nc-ty +! [lit] 0 nc-array ! then,
    nc-ty @ dup ty-base ty-struct = swap ty-ptr 0= and if, [lit] 212 cc-die then,
    nc-nlen @ if,
      sk-local [lit] 0 cc-native-param-count @ [lit] 3 + -
      cc-ninstall-symbol drop
    then,
    [lit] 1 cc-native-param-count +!
    [char] , cc-tok-punct? 0= if,
      [char] ) cc-tok-punct? 0= if, [lit] 184 cc-die then,
      exit,
    then,
  again, ;

: cc-native-function
  nc-ty @ dup ty-base ty-struct = swap ty-ptr 0= and if, [lit] 212 cc-die then,
  nc-name @ nc-nlen @ cc-sym-find
  dup 0< 0= if,
    dup cc-sym-kind-of sk-func <> if, drop true then,
  then,
  dup 0< if,
    drop nc-name @ nc-nlen @ sk-func nc-ty @ [lit] 0 cc-sym-add
    nc-desc @ over cc-sym-set-struct-desc
  then,
  nc-id !
  nc-ty @ nc-id @ cc-sym-type cell[] !
  nc-desc @ nc-id @ cc-sym-set-struct-desc
  [char] { cc-tok-punct? 0= if, exit, then,
  nc-id @ cc-sym-val-of if, [lit] 211 cc-die then,
  cc-here-vaddr nc-id @ cc-sym-val cell[] !
  nc-id @ cc-sym-call-fixups @ cc-here-vaddr cc-walk-and-patch-to-vaddr
  [lit] 0 nc-id @ cc-sym-call-fixups !
  nc-id @ cc-sym-addr-fixups @ cc-here-vaddr cc-walk-and-patch-address
  [lit] 0 nc-id @ cc-sym-addr-fixups !
  nc-name @ nc-nlen @ cc-is-main? if, cc-here-vaddr cc-main-vaddr ! then,
  nc-ty @ cc-native-return-type ! nc-desc @ cc-native-return-desc !
  nc-params cc-lex-reset
  cc-nctx @ >r cc-ncontext
  cc-scope-push
  [lit] 0 cc-fn-local-count !
  [lit] 0 cc-label-count !
  [lit] 0 cc-break-stack-head ! [lit] 0 cc-continue-stack-head !
  [lit] 0 cc-switch-depth ! [lit] 0 cc-loop-switch-depth !
  cc-native-params
  [char] { cc-expect-punct-c
  [lit] 0 cc-emit-prologue
  cc-out-pos @ [lit] 4 - cc-native-frame-patch !
  begin,
    cc-next-token-keep [char] } cc-tok-punct? 0= while,
    cc-putback-token cc-parse-stmt
  repeat,
  cc-emit-zero-edx:eax cc-emit-epilogue
  cc-native-finish-gotos
  cc-fn-local-count @ [lit] 8 * [lit] 16 cc-nalign
  cc-native-frame-patch @ cc-out-patch-4le
  cc-scope-pop r> cc-nctx ! ;
' cc-native-function is cc-native-function-fwd

\ cc-native-entry ( -- )  Emit the entry stub of the program.
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

defer cc-native-runtime-fwd

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
