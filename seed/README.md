# The seed

`000-seed.hex0` is a 1,191-byte Forth for i386, written as commented
hex0.  builder-hex0's built-in `hex0` assembles it in the boot;
`seed/build.sh` assembles it on the host into `./seed-forth`
with stage0-posix's `hex0-seed`.  Everything else the route runs before
the first tcc is Forth text that this program reads from files.

`SPEC.md` is its specification: the 21 words, 64-bit cells on a
32-bit machine, how it reads its input by file name, its memory map and
its system calls (`brk`, `open`, `read`, `write`, `exit`).

## How it was written

The file was written directly in hex0, byte by byte, from the
specification alone, with an AI model under the owner's direction, as
most of this repository was (HISTORY.md).  There is no assembler source it
was converted from and no program that generated it.

Because nobody should have to trust hand-written hex, it is checked by
independent assemblers: `tests/seed/asm-check.py` takes the
instruction written in each line's comment, assembles the comments with
GNU as and again with llvm-mc, and requires both to produce exactly the
bytes in the file.  What the code does, as opposed to what it encodes, is
tested by `tests/seed/test.sh` (76 cases, and again under strace) and
by `tests/seed/boot-check.sh` on builder-hex0.

## How to read the file

A hex0 file is pairs of hex digits; `;` or `#` starts a comment that runs
to the end of the line.  Each line with bytes holds one thing only: an ELF
field, a field of a dictionary header, or one instruction.  The first
comment on a line is the instruction, and it is what the assemblers check;
a second comment is prose.  The comment block at the top of the file gives
the memory map, the registers with a fixed role and the layout of a
dictionary header.  Read that first; after it every routine can be read on
its own.

## Checking it

From the repository root:

    seed/build.sh
    python3 tests/seed/asm-check.py
    tests/seed/test.sh

An earlier seed for x86-64 (930 bytes, `seed/000-seed.hex0`) is at tag
`experiments-2026-11-21`.
