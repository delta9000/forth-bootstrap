\ tinycc/jobs/tcc-first.fth -- the i386 seed's job that compiles the
\ first tcc.
\
\     seed-forth forth/010-lib.fth tinycc/jobs/tcc-first.fth \
\         OUT SOURCE INCLUDE INCLUDE-LINUX
\
\ The library reads this file because it is the second argument, and the
\ four after it are arguments 3 to 6: the file to write, direct-input.c,
\ and Mes libc's include and include/linux/x86, which are pass1.kaem's
\ include paths for Mes libc on x86.  SOURCE is the one file of C the
\ compiler reads, and quoted includes are looked for beside it.  The host
\ (tinycc/build-first-tcc.sh) and the boot
\ (tinycc/one-boot-disk.py) run this job with their own paths.
include forth/layers.fth
: tcc-output  [lit] 3 arg ;
[lit] 4 arg dup zlen cc-prep-source-name
[lit] 5 arg dup zlen cc-prep-add-include
[lit] 6 arg dup zlen cc-prep-add-include
[lit] 4 arg cc-input-file
include tinycc/tcc-compile.fth
