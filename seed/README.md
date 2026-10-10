# seed/

`000-seed.hex0` is the whole starting program: a 1,772-byte x86-64 Linux
ELF written as commented hexadecimal, one instruction per line with its
assembly as a comment. stage0-posix's 229-byte `hex0-seed` turns it into
`seed-forth` byte for byte (`build.sh`). It is a Forth with two stacks
(data and return) and 32 primitives (the words written in machine code), a
dictionary, a token reader, a colon compiler and a REPL; everything else
in the repository is loaded into it or built by what it loads. Read the
file from the top: the ELF header, the entry code and memory map, then the
primitives. `./check-all.sh` step 01 builds it and checks its size; step
02 (`./test.sh`) exercises the primitives.
