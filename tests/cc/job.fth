\ tests/cc/job.fth -- the seed's job that compiles one test program.
\
\     seed-forth forth/010-lib.fth tests/cc/job.fth OUT SOURCE
\
\ tinycc/jobs/tool.fth without M2libc's system-call layer: the
\ compiler reads SOURCE alone, so a test supplies what it calls.  The
\ driver is the tools' (tinycc/tool-compile.fth).
include forth/layers.fth
: tool-output  [lit] 3 arg ;
[lit] 4 arg dup zlen cc-prep-source-name
[lit] 4 arg cc-input-file
include tinycc/tool-compile.fth
