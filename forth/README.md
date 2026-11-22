# forth/

`i386/010-lib.fth` builds a Forth vocabulary on the seed's 21 machine-code
words: stack words, logic from `nand`, comparisons, system call wrappers,
control flow, defining words and buffers, and at its end `brk-alloc`,
`arg`, `include` and a `key` that reads files by name.  The seed reads it
first on every run: `seed-forth-i386 forth/i386/010-lib.fth JOB [ARG ...]`.

`i386/020-cc-arena.fth` lays the library's primitives down again as
machine code, compiles later definitions with them inline, and holds the
compiler's arena and its `cc-die`.  `i386/layers.fth` lists the compiler's
files in load order.  `i386/CONTRACT.md` is the design of these files; it
describes each against an x86-64 original that is now at tag
`experiments-2026-11-21`.

Start with `i386/010-lib.fth`'s header comment, then read it top to
bottom.  `test-010-lib.fth` runs in `./test.sh`;
`tests/forth/i386/` has the checks of the machine code.
