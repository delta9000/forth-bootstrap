\ tests/forth/high-halves-job.fth -- the i386 seed's job that runs
\ high-halves.fth:
\     seed-forth forth/010-lib.fth tests/forth/high-halves-job.fth
\ The judge goes before 020 (high-halves-judge.fth says why).
include tests/forth/high-halves-judge.fth
include forth/020-cc-arena.fth
include tests/forth/high-halves.fth
