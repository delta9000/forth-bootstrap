# The seed

`000-seed.hex0` is a 930-byte Forth for x86-64 Linux, written as commented
hex0. `seed/build.sh` assembles it into `./seed-forth` with stage0-posix's
`hex0-seed`. Everything else in this repository is Forth text that this
program reads from standard input.

## How it was written

The file was written directly in hex0, byte by byte, from a behavioural
specification (`SPEC.md`), by an AI model under the owner's direction. The
model did not see any earlier implementation of the seed. There is no
assembler source it was converted from and no program that generated it.

Because nobody should have to trust hand-written hex, it is checked by
independent assemblers: `tests/seed/asm-check.py` takes the instruction
written in each line's comment, assembles the comments with GNU as and again
with llvm-mc, and requires both to produce exactly the bytes in the file. It
also checks the ELF fields, the dictionary headers, the branch displacements
and the memory map against what the comments state. What the code does, as
opposed to what it encodes, is tested by `./test.sh`.

## What it does

It reads whitespace-separated tokens from standard input. A token that names
a word is executed, or, inside a colon definition, compiled as a `call` to
it. Any other token has to be an unsigned decimal number, which is pushed or
compiled as a literal. A token that is neither is fatal: the seed prints it
followed by `?` and a newline and exits with status 2. End of input exits
with status 0. A token that is a lone `\` starts a comment to the end of the
line.

The 21 words:

| group | words |
|---|---|
| stack | `dup` `drop` `swap` `>r` `r>` |
| memory | `@` `!` `c@` `c!` |
| arithmetic and logic | `+` `*` `/` (unsigned) `nand` `0=` |
| input and lookup | `key` `token` `find` |
| compiler | `state` `:` `;` |
| system | `syscall6` |

Its own system calls are `read`, `write` and `exit`, made with the `syscall`
instruction.

## Size

| part | bytes |
|---|---|
| ELF header and program header | 120 |
| 21 dictionary headers | 267 |
| machine code, 203 instructions | 543 |
| total | 930 |

## How to read the file

A hex0 file is pairs of hex digits; `;` or `#` starts a comment that runs to
the end of the line. Each line with bytes holds one thing only: an ELF field,
a field of a dictionary header, or one instruction.

    48 8B 7D 00                ; mov rdi, [rbp]                 ; the second item becomes TOS

The bytes are on the left. The first comment is the instruction in Intel
syntax, and it is what the assemblers check. The second comment is prose.

Lines that start with `;;` are prose or headings:

- `;; ----- NAME @ 0xNNN` starts a routine at file offset NNN. The address in
  memory is 0x400000 + NNN.
- `;; .name:` is a label inside the routine above it.
- `;; --- NAME @ 0xNNN --- header` starts the dictionary header of the word
  NAME: link, flags, name length, name. The word's code follows directly.
- `(rel8 = 0xA - 0xB)` on a branch: A is the target's offset, B the offset
  just past the branch, and A - B is the displacement in the last byte
  (`rel32`: the last four bytes).

The comment block at the top of the file gives the memory map, the four
registers with a fixed role (rdi is the top of the data stack, rbp the
data-stack pointer, rsp the return stack, rbx the sysvar page) and the layout
of a dictionary header. Read that first; after it every routine can be read
on its own.

A good order: `_start` and `outer` (the interpreter loop), then `token`,
`find`, `:` and `;`, then `compile_call` and `lit` (how a number is
compiled). The rest are short. Several words end by jumping into a shared
tail: `push_rax` (the end of `dup`) pushes rax on the data stack, `nip` (the
end of `drop`) removes the second item, `drop_two` (the end of `!`) removes
two.

## Checking it

From the repository root:

    seed/build.sh
    python3 tests/seed/asm-check.py
    ./test.sh
