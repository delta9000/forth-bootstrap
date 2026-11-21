# cc/

A C compiler written in Forth, loaded into the seed after
`forth/010-lib.fth` in numeric order (`compiler-layers.sh` prints the
order).  Files 020 to 120 are the core: arena and buffers, preprocessor,
lexer, types and symbols, ELF output and code generation, expressions,
declarations, statements, functions and the entry word `cc-main`, which
reads C on stdin and writes an executable.  115, 117, 118 and 119 add
native mode (LP64 storage with a private calling convention), and 121 to
141 the
System V target that GCC's sources need: relocatable objects, calls,
the runtime, target headers, constant expressions, varargs, floating
values, bitfields, records passed by value, the linker and archives.
`i386/` holds a second native back end, for i386 with ILP32 types: files
loaded between the layers above (`i386/layers.sh` prints the order), each
redefining the machine words of the layer before it for the layers after
it.  `090-emit.fth` keeps every value in a pair of 32-bit registers
where `090-cc-emit.fth` has one 64-bit register; `065-ilp32-types.fth`
makes long and pointers 4 bytes; `080-elf32.fth`, `117-entry.fth` and
`119-runtime.fth` write the ELF32 header, the entry stub and the `int
0x80` primitive; `100-divide.fth` refuses a `long long` division, which
the back end does not have.  `tinycc/README.md` says what it builds and
how it is checked.
`driver/` holds seed-cc and seed-ar, the C driver and archiver
(`seed-cc.c`, `seed-ar.c`) and the Forth controller that builds them from
the seed alone (`seed-cc-start.fth`).  Start at `020-cc-arena.fth` and
follow the numbers.  Checks: the `test-0N0-*.fth` files run in
`./test.sh`; `tests/cc/seed-cc-rebuild-check.sh` and
`tests/cc/stage-a-check.sh` are `./check-all.sh` steps 04 and 07.
