# cc/

A C compiler written in Forth.  The seed loads it after
`forth/i386/010-lib.fth`, in the order `forth/i386/layers.fth` lists:
`forth/i386/020-cc-arena.fth`, then the files here in numeric order.

| file | what |
|---|---|
| `030-cc-io.fth` | input, source and output buffers, the workspace allocator, the list of C files to read |
| `040-cc-prep.fth` | the preprocessor |
| `050-cc-lex.fth` | the lexer |
| `060-cc-types.fth` | types (ILP32) and struct descriptors |
| `070-cc-sym.fth` | the symbol table |
| `080-cc-elf.fth` | the ELF32 header of the output |
| `090-cc-emit.fth` | branches and fixups, the globals' two areas, the i386 instruction encoders |
| `100-cc-expr.fth` | expressions and constant expressions |
| `110-cc-decl.fth` | what declarations share, casts, `return`, the end of a program |
| `112-cc-stmt.fth` | statements |
| `115-cc-native.fth` | the declaration parser: specifiers, declarators, structs, locals |
| `117-cc-native-program.fth` | functions, the entry stub, the program |
| `118-cc-native-init.fth` | initializers |
| `119-cc-runtime.fth` | `__native_syscall`, the one kernel primitive a compiled program gets |

The compiler reads the C files a job names, preprocesses them, and writes
one static i386 ELF directly: no object files, assembler or linker.  The
drivers are in `tinycc/` (`tool-compile.fth`, `tcc-compile-i386.fth`).

What it compiles is the C that tcc 0.9.26, Mes libc, M2libc, kaem and
stage0's tools are written in.  What it does not have, it refuses with an
error code (`cc: line N: error C`, and C is the exit status):
floating-point arithmetic (a float or double is carried as its 8-byte bit
pattern; error 100), 64-bit division (131), bitfields (58), a struct
passed or returned by value (212), `__LINE__` and `__FILE__` (93).

The encoders in 090 are named for the registers of a 64-bit machine
(`cc-emit-mov-rcx-rdi`); each name stands for a pair of 32-bit registers,
and 090's header has the table.  Values are 64 bits wide in the compiler
and in the code it emits, so `long long` costs nothing extra.

Not diagnosed.  The compiler accepts some programs that are not C: a
subscript on a function name, a call of an `int` variable, `sizeof` of an
unknown struct tag, a struct member list that starts with a keyword or a
number, a stray `}` or `1;` at file scope, `typedef` of a non-type.  It
compiles the sources of this route; it is not a checker.

Checks: the `test-0N0-*.fth` files here run in `./test.sh`.
`tests/cc/gates/run-gates.sh` compiles and runs the gate fixtures, and
expects each `die-N-*` fixture to be refused with code N on a given line;
`tests/cc/gates/check-coverage.sh` counts which error codes those cover.
`tests/cc/i386/run-corpus.sh` compares run-time behaviour with gcc `-m32`,
and `tests/cc/i386/asm-check.py` compares every encoder's bytes with GNU
as on its comment.

Earlier modes of this compiler (an x86-64 back end, an object-file target
with the System V ABI, a linker, an M2-Planet subset) are at tag
`experiments-2026-11-21`.
