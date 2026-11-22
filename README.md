# forth-bootstrap

forth-bootstrap builds a C compiler from hex0 source alone, with as little
hand-written code as it can manage, and checks the result against binaries
that other people built by a different path.

builder-hex0, live-bootstrap's kernel, boots a disk that holds no program,
only sources.  Its built-in hex0 assembler assembles a 1,191-byte Forth
(`seed/000-seed.hex0`) and stage0-posix's kaem-optional-seed.  A C
compiler written in that Forth compiles kaem, eleven small tools, and
TinyCC 0.9.26 (janneke's bootstrappable fork, the source live-bootstrap's
own `tcc-0.9.26` step builds) together with GNU Mes's C library.  That tcc
takes the place of the copy MesCC would build, and live-bootstrap's step
runs on from there, in the same boot.  From `tcc-boot1` on, every binary
the step produces is byte-identical to the one live-bootstrap publishes:
`/usr/bin/tcc` is `b9dce87d...`, and `libc.a`, `libgetopt.a`, the crt
files and `libtcc1.a` match too.  live-bootstrap reaches those binaries
through M2-Planet and GNU Mes; this route uses neither.

```
builder-hex0 (live-bootstrap's kernel; its stage 1 is the one binary)
 ├─ hex0  seed/000-seed.hex0       ->  /seed-forth          (1,191 bytes)
 ├─ hex0  kaem-minimal.hex0        ->  /kaem-optional-seed
 └─ seed-forth
     └─ Forth library (forth/010-lib.fth, 020-cc-arena.fth)
         └─ C compiler in Forth (cc/030 to 119)
             ├─ kaem, sha256sum, ungz, untar, simple-patch, ... against M2libc
             └─ tcc 0.9.26 + Mes libc = /usr/bin/tcc-mes        (tinycc/)
                 └─ live-bootstrap's steps/tcc-0.9.26/pass1.kaem:
                    tcc-boot0, tcc-boot1, tcc                 = live-bootstrap's
```

Why it is built this way:

- What has to be trusted should be small enough to read.  To reach that
  tcc, what only this route reads is 8,266 lines: 6,754 of its own (the
  seed, the Forth library, the compiler, the C shims under the two C
  libraries, the jobs and scripts) and 1,512 of Mes libc, kaem and
  M2libc that MesCC's path does not compile.  What only the stage0-posix,
  M2-Planet, Mes and MesCC path to the same compiler reads is 42,057.
  Both counts leave out comments and blank lines, and the inputs the two
  routes share (tcc, the rest of Mes libc, M2libc, stage0's tool sources,
  kaem, builder-hex0).
- A match is evidence; a build that only works is not.  Two paths that
  share no compiler, written by different people in different languages,
  produce the same `tcc`.  A compromised compiler on either path would have
  to be reproduced exactly on the other to go unnoticed.
- Existing, small, published components are used where they exist:
  builder-hex0 as the kernel, Mes's and stage0's C libraries as sources,
  live-bootstrap's own step scripts.  Each one this route does not rewrite
  is code nobody has to review again for it.
- Every byte of machine code written here by hand carries its instruction
  as a comment and is checked against GNU `as` on those comments: the seed
  (`tests/seed/asm-check.py`), the Forth system's own code
  (`tests/forth/asm-check.py`) and the compiler's encoders
  (`tests/cc/asm-check.py`).

Most of this code was written with AI models under my direction;
HISTORY.md records how.  I am reviewing it chapter by chapter through the
book.

## What you trust

| What | Why it is there |
|---|---|
| builder-hex0's stage 1, 512 bytes, assembled from its hex0 source by `hex0-seed` on the host | the boot sector; it assembles builder-hex0's stage 2 from the hex0 text on the disk |
| builder-hex0's source, at live-bootstrap's pinned commit | the kernel everything runs on, and its built-in `hex0` |
| this repository's sources | the seed, the Forth, the C compiler, the C shims, the jobs and the two scripts the boot runs; read them |
| the archives in `tinycc/SOURCES` | tcc, Mes and live-bootstrap as released, sha256-pinned and checked again in the boot |
| `vendor/` sources (kaem-minimal, kaem, mescc-tools-extra, M2libc) | assembled or compiled in the boot; no binary from them is on the disk |
| QEMU, KVM and the CPU | run builder-hex0 |
| host `python3`, `bash`, `hex0-seed` | write the disk image, assemble stage 1, read the drive back and compare hashes.  They put no program but stage 1 on the disk |
| host `gcc -m32`, GNU `as`, `llvm-mc`, `strace`, `bwrap` | checks only: references to compare against and traces.  None of their output is used |

## The parts

Each directory has a README that says where to start.

| Directory | What is in it |
|---|---|
| `seed/` | `000-seed.hex0`, the Forth, written directly as annotated hex0 (the only source of it); `SPEC.md`; `build.sh`, which assembles it on the host |
| `forth/` | `010-lib.fth`, the Forth library on the seed's 21 machine-code words; `020-cc-arena.fth`, the faster primitives and the compiler's arena; `layers.fth`, the compiler's load list; `CONTRACT.md`; `test-010-lib.fth`, the library's test |
| `cc/` | the C compiler in Forth, loaded in numeric order (`030-cc-io.fth` to `119-cc-runtime.fth`), and the tests of its first layers |
| `tinycc/` | what the seed is asked to build and how: the two build scripts, the jobs and drivers, the C shims, the boot's disk writer, the replay of live-bootstrap's step (`tinycc/README.md`) |
| `tests/` | `seed/`, `forth/`, `cc/` (gates, run-time corpus, encoder check), `tinycc/` (the junction on the host, the boots), `pins/`, `reference.py` (the seed's and the host primitives' expected values, computed again in Python), and `builder-hex0/`, a measurement of the kernel's behaviour that two boot checks borrow their disk writer from |
| `tools/` | `fetch-archives.py` |
| `vendor/` | stage0-posix and mescc-tools, as submodules |

The literate book that teaches the seed, the library and the compiler is a
separate project, forth-bootstrap-book.

## Running it

An x86-64 Linux host whose kernel runs i386 programs (IA32 emulation),
with `bash`, coreutils and `python3`.  The boots need
`qemu-system-x86_64` and a writable `/dev/kvm`; the checks also use GNU
`as` and `objcopy`, `strace`, `bwrap` and `gcc -m32`, and skip what they
cannot run.

```sh
git clone https://github.com/delta9000/forth-bootstrap.git && cd forth-bootstrap
git submodule update --init --recursive
python3 tools/fetch-archives.py    # four archives, 2.2 MB, sha256-pinned
./check-all.sh                     # fourteen checks, about two minutes
```

`check-all.sh`'s header lists the checks.  A fifteenth, step 11, runs
only when asked (`CHECK_STANDIN=1 ./check-all.sh`) and is otherwise
reported as SKIP: it compares the route's first tcc with a gcc `-m32`
build of the same program, and that gcc-built reference does not make the
same `tcc-boot0` on every run (about one in eight differs;
`tinycc/README.md`, "What does not reproduce").  The first tcc the seed
builds makes the pinned `tcc-boot0` every time, and steps 10 and 15 check
that.  The ones to start with:

```sh
seed/build.sh                       # seed-forth, 1,191 bytes
tinycc/build-first-tcc.sh           # the seed builds the tools and the first tcc on the host
tests/tinycc/junction-check.sh           # live-bootstrap's step from that tcc, in a sandbox
tests/tinycc/one-boot-check.sh      # the route: one boot of builder-hex0 from sources
```

The last prints, after a boot of 24 s:

```
one-boot-check: OK, 33 files; live-bootstrap's published tcc-0.9.26 reached on builder-hex0
  in one boot, from sources: no program on the disk
```

## Reading order

- `seed/000-seed.hex0`: the seed's 21 machine-code words, one
  instruction per annotated line; `seed/SPEC.md` specifies it.
- `forth/010-lib.fth`, then `forth/020-cc-arena.fth`.
- `cc/` in load order (`forth/layers.fth`): I/O buffers,
  preprocessor, lexer, types, symbols, ELF header, code emission,
  expressions, declarations, statements, the typed declaration parser,
  functions and the program, initializers, the system-call primitive.
- `tinycc/README.md`, then `tinycc/one-boot-disk.py` for the order
  everything runs in.

## Experiments

This repository used to hold several routes at once, and the compiler had
a mode for each.  They were verified together one last time and then
removed from `main`, which keeps only the route above.  They are at tag
`experiments-2026-11-21` (branch `experiments/all-routes`):

- an x86-64 seed (930 bytes) with its own library, and an x86-64 back end;
- K0 and K1, two small kernels that hosted the run under QEMU, and the
  hand-off from K0 to builder-hex0;
- the GCC route: seed-cc, an object-file target with the System V ABI, a
  linker and archiver, the chain from make and bash to the GCC 4.0.4
  fixed point, GCC 10.5.0 and a Linux kernel;
- the M2-Planet subset of the compiler and Stage A, which compared it
  with a gcc-built M2-Planet.

```sh
git checkout experiments-2026-11-21      # README.md there describes them
```

## History and credits

[HISTORY.md](HISTORY.md) tells how the project was built and where its
files came from.  [CREDITS.md](CREDITS.md) lists the upstream sources and
their licenses.  The repository's own files are under the MIT License.
