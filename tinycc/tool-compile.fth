\ tinycc/tool-compile.fth -- the driver that compiles one program against
\ M2libc: a source-preparation tool, kaem, or a test.
\
\ Loaded by the seed's job (tinycc/i386-seed/tool.fth, or
\ tests/cc/i386/job.fth for a test) after the compiler
\ (forth/i386/layers.fth) and after the job has defined tool-output, a
\ word that pushes the output file's name with its NUL, has given the
\ unit's name to cc-prep-source-name, so that quoted includes resolve
\ beside it, and has listed the C files to read with cc-input-file.  Like
\ tinycc/tcc-compile-i386.fth, but with M2libc's include paths, and the
\ output is written executable (0755), so that no chmod is needed before
\ chmod itself is built.
[lit] 8388608 cc-arena-map
create tool-include s, vendor/stage0-posix/M2libc
tool-include [lit] 26 cc-prep-add-include
create tool-include-stage0 s, vendor/stage0-posix
tool-include-stage0 [lit] 19 cc-prep-add-include
variable tool-fd
variable tool-pointer
variable tool-count
: tool-write-output
  tool-output [lit] 577 [lit] 493 open
  dup 0< if, [lit] 121 die then, tool-fd !
  cc-out-buf tool-pointer ! cc-out-pos @ tool-count !
  begin, tool-count @ while,
    tool-fd @ tool-pointer @ tool-count @ write
    dup 0< if, [lit] 122 die then,
    dup 0= if, [lit] 123 die then,
    dup tool-pointer +! tool-count @ swap - tool-count !
  repeat,
  tool-fd @ close if, [lit] 124 die then, ;
: tool-main
  cc-load-files cc-preprocess cc-out-init cc-globals-init
  cc-emit-elf-header cc-native-program cc-finalize-globals cc-finalize-elf
  tool-write-output bye ;
tool-main
