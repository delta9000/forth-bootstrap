# seed/

`000-seed.hex0` is the whole starting program: a 1,091-byte x86-64 Linux
ELF written as commented hexadecimal, one instruction per line with its
assembly as a comment. stage0-posix's 229-byte `hex0-seed` turns it into
`seed-forth` byte for byte (`build.sh`). It is a Forth with two stacks
(data and return), 21 words written in machine code, a dictionary, a
token reader, a colon compiler and a read-evaluate loop that knows words
and unsigned decimal numbers; everything else in the repository is loaded
into it or built by what it loads, starting with `forth/010-lib.fth`.
Read the file from the top: the ELF header, the entry code and memory
map, the loop and its routines, then the words.

`seed.asm` is the same program as NASM source, where the addresses are
labels. `asm2hex0.py` writes `000-seed.hex0` from it, so an edit starts
there; `check.sh` proves that the hex0 is what the script writes and that
nasm's bytes are hex0-seed's. `MINIMAL.md` says why the seed has the 21
words it has, what the library took over from the 1,772-byte seed before
it, and where size and clarity pulled apart.

`./check-all.sh` step 01 builds the seed and checks its size; step 02
(`./test.sh`) exercises its words; step 09 runs
`tests/seed/asm-check.py` (GNU as on the hex0's comments gives the same
bytes) and `check.sh`.
