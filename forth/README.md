# forth/

`010-lib.fth` builds a Forth vocabulary on the seed's 32 primitives:
stack words, logic from `nand`, comparisons, Linux system call wrappers,
control flow, defining words and buffers.  Every later Forth file loads
it first.  `130-asm.fth` uses the library to assemble stage0-posix's M1
macro assembly and link hex2 into an ELF file, with no other assembler.
Start with `010-lib.fth`'s header comment, then read it top to bottom,
then `130-asm.fth`.  `test-010-lib.fth` runs in `./test.sh`
(`./check-all.sh` step 02); `tests/asm/hi-check.sh` assembles and runs a
small M1 program (step 03).
