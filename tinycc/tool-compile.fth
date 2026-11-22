\ tinycc/tool-compile.fth -- the native-mode driver that compiles one source
\ preparation tool against M2libc (tinycc/build-tools.sh).
\
\ Loaded after forth/010-lib.fth, the compiler layers 020 to 119 (without
\ 081, 114 and 116) and two definitions that name the tool:
\     create tool-output s, build-out/tinycc/bin/NAME [lit] 0 c,
\     create tool-source s, PATH  tool-source [lit] LENGTH cc-prep-source-name
\ (build-tools.sh prints them with bash's printf; tinycc/tools/catm.fth has
\ catm's).  The bytes after this file on stdin are tinycc/m2libc-native.c
\ followed by the tool's C source; PATH is that source's, so its quoted
\ includes resolve beside it.  Like tinycc/tcc-compile.fth, but with
\ M2libc's include paths, and the output is written executable (0755),
\ so that no chmod is needed before chmod itself is built.
true cc-target-lp64 !
true cc-prep-direct !
[lit] 1 cc-bootstrap-floatbits !
true cc-native-syscall-any !
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
  cc-load-stdin cc-preprocess cc-out-init cc-globals-init
  cc-emit-elf-header cc-native-program cc-finalize-globals cc-finalize-elf
  tool-write-output bye ;
tool-main
