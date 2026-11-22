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

## Known accepts

The compiler's input is fixed: tcc, Mes libc, M2libc, kaem and the tools,
all valid C and all pinned by hash.  It therefore refuses what it cannot
compile and does not check that its input is C.  These thirteen programs
are not C (gcc `-m32` rejects each), and the compiler writes a program
for every one without a message.  No refusal is added for them: none can
occur in the pinned sources, and each would be code to read that the
route never runs.

| program | what it is |
|---|---|
| `int f() { return 0; }  int main() { return f[0]; }` | a subscript on a function name |
| `int main() { int x; return x(1); }` | a call of an `int` variable |
| `int main() { return sizeof(struct nosuch); }` | `sizeof` of a struct tag never declared |
| `int x;  int main() { return sizeof(struct x); }` | `sizeof` of a struct tag that is only a variable's name |
| `int main() { struct nosuch x; return 0; }` | a local whose struct type is never declared |
| `int y;  int main() { struct y x; return 0; }` | a local whose struct tag is only a variable's name |
| `struct s { return a; };` | a member declaration that starts with a statement keyword |
| `struct s { 1 a; };` | a member declaration that starts with a number |
| `int f(1 x) { return 0; }` | a parameter whose type is a number |
| `int main() { return 0; } }` | a stray `}` at file scope |
| `typedef return T;` | `typedef` of a keyword that is not a type |
| `typedef 1 T;` | `typedef` of a number |
| `1;` | an expression statement at file scope |

They were die fixtures 91, 94, 104, 105, 146, 147, 150, 151, 182, 186,
193, 196 and 202 of the M2-Planet subset this compiler once also had
(`tests/cc/gates/` at tag `experiments-2026-11-21`); that mode's parser
refused them and this one never did.

## Checks

The `test-0N0-*.fth` files here run in `./test.sh`.
`tests/cc/gates/run-gates.sh` compiles and runs the gate fixtures, and
expects each `die-N-*` fixture to be refused with code N on a given line;
`tests/cc/gates/check-coverage.sh` counts which error codes those cover.
`tests/cc/i386/run-corpus.sh` compares run-time behaviour with gcc `-m32`,
and `tests/cc/i386/asm-check.py` compares every encoder's bytes with GNU
as on its comment.

Earlier modes of this compiler (an x86-64 back end, an object-file target
with the System V ABI, a linker, an M2-Planet subset) are at tag
`experiments-2026-11-21`.
