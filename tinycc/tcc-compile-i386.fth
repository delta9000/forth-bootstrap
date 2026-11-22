\ tinycc/tcc-compile-i386.fth -- the native-mode driver that compiles the
\ i386 first tcc.
\
\ Loaded by the seed's job, tinycc/i386-seed/tcc-first.fth, after the
\ compiler (forth/i386/layers.fth) and after the job has taken four paths
\ from its command line: tcc-output, a word that pushes the output file's
\ name with its NUL, and the source's name and the two include paths,
\ given to cc-prep-source-name and cc-prep-add-include.  The C the
\ compiler then reads is exactly direct-input.c.  Forth does all the
\ preprocessing and emits one complete static i386 ELF: no assembler,
\ linker or host C compiler takes part.
\
\ Native mode, under the ILP32 types of
\ cc/i386/065-ilp32-types.fth (cc-target-lp64 selects the typed model,
\ not its sizes): a private all-stack call ABI, float and double as
\ 8-byte bit patterns only, and the one system call primitive of
\ cc/i386/119-runtime.fth.
true cc-target-lp64 !
true cc-prep-direct !
[lit] 1 cc-bootstrap-floatbits !
[lit] 8388608 cc-arena-map
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
