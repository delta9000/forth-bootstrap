\ tinycc/i386-seed/tool.fth -- the i386 seed's job that compiles one
\ program against M2libc: a source-preparation tool, or kaem.
\
\     seed-forth-i386 forth/i386/010-lib.fth tinycc/i386-seed/tool.fth \
\         OUT SOURCE [SOURCE ...]
\
\ The library reads this file because it is the second argument; OUT is
\ argument 3 and the SOURCEs follow.  The compiler reads
\ tinycc/m2libc-native-i386.c and then each SOURCE, one after another as
\ one unit, as tinycc/build-tools-i386.sh joins them for the x86-64 seed.
\ The last SOURCE gives the unit its name, beside which quoted includes
\ are looked for.  kaem is the program with more than one SOURCE:
\ tinycc/m2libc-kaem-i386.c and its three files.  The driver is the x86-64
\ seed's, which wants tool-output and the unit's name from whoever loads
\ it.
include forth/i386/layers.fth
: tool-output  [lit] 3 arg ;

\ tool-source ( -- zaddr )  the last argument.
: tool-source
  [lit] 4 begin, dup 1+ arg while, 1+ repeat, arg ;
tool-source dup zlen cc-prep-source-name

\ tool-inputs ( -- )  list the C the compiler reads: the system-call layer,
\ then every SOURCE.
create tool-shim s, tinycc/m2libc-native-i386.c [lit] 0 c,
: tool-inputs
  tool-shim cc-input-file
  [lit] 4 begin, dup arg while, dup arg cc-input-file 1+ repeat, drop ;
tool-inputs
include tinycc/tool-compile.fth
