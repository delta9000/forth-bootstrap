\ tinycc/tcc-compile.fth -- the native-mode driver that compiles the first tcc.
\
\ From seed-forth's tools/tcc-compile.fth (commit 550a0c5, on
\ origin/qemu-final), with the output path changed from
\ build-out/tcc-seed.partial.  Loaded after
\ forth/010-lib.fth and the compiler layers 020 to 119 (without 081, which
\ native mode does not call); tinycc/build-first-tcc.sh gives the list.
\ The bytes after it on stdin are exactly build-out/tcc-sources/direct-input.c.
\ Forth does all the preprocessing and emits one complete static x86_64 ELF:
\ no assembler, linker or host C compiler takes part.
\
\ Native mode: LP64 types, a private all-stack call ABI, float and double
\ as 8-byte bit patterns only (cc-bootstrap-floatbits), and one system
\ call primitive from cc/119-cc-native-runtime.fth (cc-native-syscall-any),
\ under Mes libc's own read, write, exit and the rest.  The include paths
\ are pass1.kaem's for Mes libc: include and include/linux/x86_64.  The
\ paths are relative to the repository root, so the output does not depend
\ on where the checkout is; the [lit] after each is its length.
true cc-target-lp64 !
true cc-prep-direct !
[lit] 1 cc-bootstrap-floatbits !
true cc-native-syscall-any !
[lit] 8388608 cc-arena-map
create tcc-output s, build-out/tinycc/tcc-first [lit] 0 c,
create tcc-source s, build-out/tcc-sources/direct-input.c
tcc-source [lit] 36 cc-prep-source-name
create tcc-include s, build-out/tcc-sources/mes-0.28/include
tcc-include [lit] 38 cc-prep-add-include
create tcc-include-linux s, build-out/tcc-sources/mes-0.28/include/linux/x86_64
tcc-include-linux [lit] 51 cc-prep-add-include
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
