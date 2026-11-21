\ tinycc/i386-seed/tcc-first.fth -- the i386 seed's job that compiles the
\ first tcc.
\
\     seed-forth-i386 forth/i386/010-lib.fth tinycc/i386-seed/tcc-first.fth \
\         OUT SOURCE INCLUDE INCLUDE-LINUX
\
\ The library reads this file because it is the second argument, and the
\ four after it are arguments 3 to 6.  They are the paths
\ tinycc/tcc-names-i386.fth types in for the x86-64 seed: the file to
\ write, direct-input.c, and Mes libc's include and include/linux/x86.  On
\ the host they are those same paths; in the boot the sources are
\ elsewhere.  SOURCE is also the one file of C the compiler reads, where
\ the x86-64 seed reads it from its standard input after the Forth text.
\ The driver is the x86-64 seed's.
include forth/i386/layers.fth
: tcc-output  [lit] 3 arg ;
[lit] 4 arg dup zlen cc-prep-source-name
[lit] 5 arg dup zlen cc-prep-add-include
[lit] 6 arg dup zlen cc-prep-add-include
[lit] 4 arg cc-input-file
include tinycc/tcc-compile-i386.fth
