\ tests/forth/i386/high-halves-job.fth -- the i386 seed's job that runs
\ high-halves.fth:
\     seed-forth-i386 forth/i386/010-lib.fth tests/forth/i386/high-halves-job.fth
\ The judge goes before 020 (high-halves-judge.fth says why).
include tests/forth/i386/high-halves-judge.fth
include forth/i386/020-cc-arena.fth
include tests/forth/i386/high-halves.fth
