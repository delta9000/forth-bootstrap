\ tinycc/tcc-compile-i386.fth -- the native-mode driver that compiles the
\ i386 first tcc.
\
\ tinycc/tcc-compile.fth for the i386 back end: loaded after the files
\ cc/i386/layers.sh lists; tinycc/build-first-tcc-i386.sh joins them.  The
\ bytes after it on stdin are exactly
\ build-out/tcc-sources-i386/direct-input.c.  Forth does all the
\ preprocessing and emits one complete static i386 ELF: no assembler,
\ linker or host C compiler takes part.
\
\ Native mode as there, under the ILP32 types of
\ cc/i386/065-ilp32-types.fth (cc-target-lp64 selects the typed model,
\ not its sizes): a private all-stack call ABI, float and double as
\ 8-byte bit patterns only, and the one system call primitive of
\ cc/i386/119-runtime.fth.  The include paths are pass1.kaem's for Mes
\ libc on x86: include and include/linux/x86.
true cc-target-lp64 !
true cc-prep-direct !
[lit] 1 cc-bootstrap-floatbits !
[lit] 8388608 cc-arena-map
create tcc-output s, build-out/tinycc/tcc-first-i386 [lit] 0 c,
create tcc-source s, build-out/tcc-sources-i386/direct-input.c
tcc-source [lit] 41 cc-prep-source-name
create tcc-include s, build-out/tcc-sources-i386/mes-0.28/include
tcc-include [lit] 43 cc-prep-add-include
create tcc-include-linux s, build-out/tcc-sources-i386/mes-0.28/include/linux/x86
tcc-include-linux [lit] 53 cc-prep-add-include
variable tcc-fd
variable tcc-pointer
variable tcc-count
\ Unlike the legacy single-write helper, check every write and the close.
: tcc-write-output
  tcc-output [lit] 577 [lit] 384 open
  dup 0< if, [lit] 121 die then, tcc-fd !
  cc-out-buf tcc-pointer ! cc-out-pos @ tcc-count !
  begin, tcc-count @ while,
    tcc-fd @ tcc-pointer @ tcc-count @ write
    dup 0< if, [lit] 122 die then,
    dup 0= if, [lit] 123 die then,
    dup tcc-pointer +! tcc-count @ swap - tcc-count !
  repeat,
  tcc-fd @ close if, [lit] 124 die then, ;
: tcc-main
  cc-load-stdin cc-preprocess cc-out-init cc-globals-init
  cc-emit-elf-header cc-native-program cc-finalize-globals cc-finalize-elf
  tcc-write-output bye ;
tcc-main
