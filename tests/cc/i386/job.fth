\ tests/cc/i386/job.fth -- the seed's job that compiles one test program.
\
\     seed-forth-i386 forth/i386/010-lib.fth tests/cc/i386/job.fth OUT SOURCE
\
\ tinycc/i386-seed/tool.fth without M2libc's system-call layer: the
\ compiler reads SOURCE alone, so a test supplies what it calls.  The
\ driver is the tools' (tinycc/tool-compile.fth).
include forth/i386/layers.fth
: tool-output  [lit] 3 arg ;
[lit] 4 arg dup zlen cc-prep-source-name
[lit] 4 arg cc-input-file
include tinycc/tool-compile.fth
