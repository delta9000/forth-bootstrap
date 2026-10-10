# forth-bootstrap

From a 229-byte hex0 program to a Linux kernel, with no compiler from
outside: every compiler that builds the route is itself built by the route.
stage0-posix's `hex0-seed` assembles a 1,772-byte Forth; a C compiler
written in that Forth builds a C driver, a shell and the first Unix tools;
those build GCC 4.0.4 until it reproduces itself, then GCC 10.5.0, then
Linux 7.2.8.  The whole run can happen inside two small kernels under QEMU:
K0, 1,313 bytes of hex0, and K1, a C kernel that seed Forth compiles.  K1
then hands the machine to the Linux kernel the run built.  A host `gcc`
appears only in the checks, as the reference Stage A compares against.
The terms in the tree below are defined under Names.

```
hex0-seed (229 bytes)
 └─ seed-forth (seed/000-seed.hex0, 1,772 bytes)
     └─ Forth library and M1 assembler (forth/)
         └─ C compiler in Forth (cc/020-141) ── seed-cc, seed-ar (cc/driver/)
             └─ kaem, mescc-tools-extra, make 3.82, sed, grep, gawk, coreutils,
                tar, gzip, patch, diffutils, oyacc, lex, flex 2.5.11, bash 2.05b
                 └─ binutils 2.30, GCC 4.0.4 + musl 1.1.24 (stage C), GCC 4.0.4
                    stage 2 = 3 = 4 (stage D)                       (chain/plumbing,
                     └─ late tools: make 4.4.1, bash 5.2, coreutils 9.5, ...   chain/gcc-direct)
                         └─ gcc-A, gcc-B = gcc-C, musl, gmp, mpfr, mpc, gcc-4.7.4,
                            binutils 2.41, gcc-10.5.0          (chain/ladder, chain/gcc64)
                             └─ Linux 7.2.8, kexec
```

## Names

The tools and formats:

- **stage0-posix**: the bootstrap project (`vendor/stage0-posix`) whose
  229-byte `hex0-seed` is the only program this route starts from; its
  kaem and mescc-tools-extra sources are compiled here by seed-cc.
- **hex0**: hexadecimal bytes with comments, which `hex0-seed` turns into
  a file byte for byte.  The seed and K0 are written in it.
- **M1, hex2**: stage0-posix's assembler-level formats.  M1 is macro
  assembly (named opcodes and labels); hex2 is hex with label references.
  `forth/130-asm.fth` assembles and links them.
- **kaem**: stage0-posix's minimal shell for build scripts (`*.kaem`),
  one command per line.  It runs the plumbing stages before any real shell
  exists.
- **mescc-tools, mescc-tools-extra**: stage0-posix's small C tools (kaem,
  `mkdir`, `cp`, `sha256sum`, `untar` and others), compiled here by seed-cc.
- **M2libc**: the small C library of the stage0-posix tools
  (`vendor/stage0-posix/mescc-tools-extra/M2libc`); kaem and
  mescc-tools-extra are compiled against its `bootstrappable.c`.
- **plumbing**: the first Unix tools the route builds with seed-cc (make,
  sed, grep, gawk, coreutils, tar, gzip, patch, diffutils, the parser
  generators and bash 2.05b), before any GCC; `chain/plumbing/`.
- **seed-cc, seed-ar**: the C compiler driver and archiver, written in C
  and compiled by the Forth compiler; both run the seed underneath.
- **K0, K1**: the two kernels the QEMU run boots, one after the other.
- **LP64**: `long` and pointers are 64 bits, `int` 32: Linux x86-64's data
  model, which the compiler's later layers implement.
- **System V**: the AMD64 System V ABI, Linux x86-64's calling convention
  and object format; seed-cc's objects and calls follow it.
- **fixed point**: a compiler that, rebuilt with itself, produces the same
  files again.  Stage D checks this for GCC 4.0.4 and
  `tests/cc/seed-cc-rebuild-check.sh` for seed-cc.
- **kexec**: replacing the running kernel with another without a reboot;
  K1 does it to start the Linux it built.

The stages:

- **Stage A**: the M2-Planet comparison.  The Forth compiler compiles
  M2-Planet, and that M2-Planet's M1 output for its own source must equal
  a GCC-built M2-Planet's.  It checks the compiler against a reference; it
  is not a step of the route.
- **stage B**: binutils 2.30, built by seed-cc (`chain/gcc-direct/binutils.sh`
  writes its report under `stage-b/`).
- **stage C**: GCC 4.0.4 compiled by seed-cc, then libgcc and musl 1.1.24
  compiled by that GCC.
- **stage D**: GCC 4.0.4 rebuilt three times (stages 2, 3 and 4) by the
  previous GCC; the installed files of 2, 3 and 4 must agree.
- **gcc-A, gcc-B, gcc-C**: `chain/gcc64`'s GCC 4.0.4 builds on the way to
  GCC 10.5.0.  gcc-A is built by the stage-D GCC; gcc-B by gcc-A; gcc-C by
  gcc-B, and gcc-B = gcc-C.  Then gcc-4.7.4, binutils 2.41 and gcc-10.5.0.

## What you trust

| What | Why it is there | Where |
|---|---|---|
| `hex0-seed`, 229 bytes from stage0-posix | the one program the route starts from: it assembles `seed/000-seed.hex0` and `kernel/k0/k0.hex0` | every run |
| this repository's sources | the seed, the Forth, the C compiler, K0 and K1, and the chain's scripts, recipes, configurations and patches; read them | every run |
| the archives in `MANIFEST.sha256` | upstream sources as released, sha256-pinned; their shipped `configure` scripts run under the chain's own bash | the chain |
| `vendor/` sources (kaem, mescc-tools-extra, M2libc) | compiled by seed-cc; no binary from them runs | the chain |
| QEMU, KVM and the CPU | run K0, which starts everything else | the K1 run |
| the host's Linux kernel, `bwrap`, `strace` | the host run's system calls, and a root whose only executable is `hex0-seed` | the host run (`chain/plumbing-root.sh`) |
| host `python3`, `sh`, `tar` | copy files into disk images and into the host run's root; check results.  They never compile, unpack, patch or configure anything | both |
| host `gcc`, GNU `as`, `nasm` | build references to compare against: Stage A's M2-Planet, `asm-check.py`'s object, `kernel/k0/check.sh`'s K0.  None of their output is used | checks only |

## The parts

Each directory has a README that says where to start.

| Directory | What is in it |
|---|---|
| `seed/` | `000-seed.hex0`, the annotated hex of the Forth; `build.sh` |
| `forth/` | `010-lib.fth`, the Forth library on the seed's 32 primitives; `130-asm.fth`, an M1 assembler and hex2 linker; the library's test |
| `cc/` | the C compiler in Forth, loaded in numeric order (`020-cc-arena.fth` to `141-archive.fth`); its tests; `driver/`, seed-cc and seed-ar |
| `kernel/` | `k0/` (K0 in hex0, with its NASM source), `k1/` (K1 in C and `k1-asm.fth`, its recipes, disk writers and tests), `tools/` (the recipe runner and the files that build K1) |
| `chain/` | `runtime/gcc-seed` (seed-cc's C library), `plumbing/` (the first tools, as kaem scripts), `gcc-direct/` (binutils, stage C, stage D, the late tools), `ladder/` and `gcc64/` (the climb to GCC 10.5.0 and Linux), `patches/`, `plumbing-root.sh` |
| `tests/` | Stage A and the M2-Planet headers the compiler falls back to; the assembler and seed-cc checks; the chain's test programs |
| `tools/` | `fetch-archives.py`, `check-pins.py` |
| `results/` | reports from the recorded runs |
| `vendor/` | stage0-posix, mescc-tools and M2-Planet, as submodules |

The literate book that teaches `seed/`, `forth/` and `cc/` is a separate
project, forth-bootstrap-book.

## Prerequisites

An x86-64 Linux host.  By step below; times are from the recorded runs
(see Results):

| Step | Needs | Time | Disk |
|---|---|---|---|
| clone | `git` (the three submodules come from GitHub) | a minute | 60 MB |
| 1-2 | `bash`, coreutils, `python3`; `gcc` for Stage A's reference only | seconds | a few MB |
| archives | `curl`, `git`, `xz` (`tools/fetch-archives.py`) | depends on the network | 1.1 GB |
| 3 | `bwrap` (bubblewrap) and `strace`, unprivileged user namespaces | 18 minutes on 24 threads; longer with fewer | 1.6 GB |
| 4 | `strace` and GNU `as` (binutils) for the build check; `qemu-system-x86_64` | under a minute | small |
| 5 | QEMU with KVM (`/dev/kvm` writable) and 24 GiB of free RAM for the guest | 1 h 38 min | 0.9 GB of disk images |

`./check-all.sh` skips the steps whose tools are missing and says so.

## Running it

```sh
git clone https://github.com/delta9000/forth-bootstrap.git && cd forth-bootstrap
git submodule update --init --recursive
./check-all.sh                     # the seven quick checks, under a minute
```

`check-all.sh` runs: the seed build, `./test.sh`, the M1 assembler
(`tests/asm/hi-check.sh`), seed-cc rebuilding itself
(`tests/cc/seed-cc-rebuild-check.sh`), the archive pins, Stage A, and K1's
build check.  The steps below run them one at a time, and then the long
runs.

**1. The seed and the Forth** (seconds):

```sh
seed/build.sh                      # seed-forth, 1,772 bytes
./test.sh                          # seed primitives, 010-lib.fth, the first compiler layers
tests/asm/hi-check.sh              # 130-asm.fth assembles a small M1 program; it prints "hi"
```

**2. The C compiler** (seconds; Stage A needs gcc for the reference):

```sh
tests/cc/seed-cc-rebuild-check.sh  # seed Forth builds seed-cc and seed-ar; seed-cc rebuilds both, byte for byte
tests/cc/stage-a-check.sh          # the Forth compiler's M1 for M2-Planet equals a GCC-built M2-Planet's
```

**3. The chain, on the host, to the GCC 4.0.4 fixed point** (18 minutes on
24 threads; needs `bwrap` and `strace`).  First the 45 pinned archives:
`tools/fetch-archives.py` downloads each from its upstream release (the
URLs are in the script, and in `chain/gcc64/SOURCES` for the GCC climb's)
into the `build-out/` path `MANIFEST.sha256` names, and keeps it only if
its sha256 is the pinned one.

```sh
python3 tools/fetch-archives.py    # or place them yourself; then:
sha256sum -c MANIFEST.sha256
sh chain/plumbing-root.sh          # hex0-seed -> ... -> stage D: "fixed point reached"
```

The root it builds in starts with one executable, `hex0-seed`; every other
program that runs is one the chain built.  The traces of every `execve`
land in `build-out/plumbing-root.trace/`.

**4. K1** (under a minute; needs QEMU):

```sh
sh kernel/k1/tests/direct-build-check.sh   # seed Forth builds K1; needs strace and as
kernel/k1/run-chain.sh --direct-smoke      # K0 -> K1 -> seed-cc, seed-ar and kaem under K1
```

**5. hex0 to Linux under K1** (1 h 38 min with KVM; 24 GiB of free host
RAM for the guest):

```sh
JOBS=2 kernel/k1/run-chain.sh --direct-linux
```

QEMU loads K0 and its memory image; K0 runs seed Forth, which builds the
recipe runner and K1; K1 imports the input disk (the sources and archives
of `kernel/k1/direct_inputs.py`), builds seed-forth, seed-cc and the chain
of step 3 again under itself, then the late tools, the climb to GCC 10.5.0
and Linux, writes the results to the output disk and kexecs into the new
kernel, which prints
`init: hello from a Linux kernel built from hex0 and seed-forth`.

K1 has one CPU, so this takes longer than step 3 on a many-core host;
`JOBS=2` keeps that CPU busy while another job waits on I/O.  A host
without 24 GiB free can set `K1_RAM_FILE=build-out/NAME` to back the guest
RAM with a sparse file instead, but a full run writes terabytes through
it: not on an SSD.

`./check-all.sh` runs the quick checks; `CHECK_CHAIN=1` and
`CHECK_K1=smoke|linux` add the long ones.

## Reading order

- **seed/, forth/:** `seed/000-seed.hex0` (the seed's 32 primitives, one
  instruction per annotated line), then `forth/010-lib.fth`, then
  `forth/130-asm.fth` (the M1 assembler and hex2 linker).
- **cc/:** the compiler in load order: `cc/020-cc-arena.fth` to
  `cc/120-cc-main.fth` (arena, preprocessor, lexer, types, code
  generation, expressions, declarations, statements, functions, main),
  then `cc/121` to `cc/141` with `cc/driver/` (what the compiler grew to
  build GCC: objects, the System V ABI, the runtime, the linker,
  archives).  `cc/115` to `cc/119` are native mode, an LP64 profile with a
  private calling convention that the System V layers build on.  The book,
  a separate project, walks through the same files.
- **kernel/:** `kernel/k0/k0.asm` (K0, about 600 lines of commented NASM;
  `k0.hex0` is the same bytes), then `kernel/k1/README.md` and `k1.h`,
  then `kernel/tools/k1-direct-start.fth` and `k1-direct.recipe` for how
  seed Forth builds K1, and `kernel/k1/run-chain.sh` for the run.
- **chain/:** `chain/plumbing/README.md` (the first tools), then
  `chain/plumbing/CHAIN.md` (binutils, stage C, stage D) and `LATE.md`
  (the late tools), then the headers of `chain/gcc64/run-gcc64.sh` and
  `chain/ladder/stage12.sh`.  `chain/plumbing-root.sh` and
  `kernel/k1/direct-linux.recipe` show the order everything runs in.

## Results

Measured on korriban (24 hardware threads, 30 GiB, QEMU with KVM).  The
reports these figures come from are in [results/](results/).

| Run | Result |
|---|---|
| `./check-all.sh` (2026-10-10) | 7 OK: the seed (1,772 bytes), tests, the assembler (`hi`, exit 42, 160 bytes), seed-cc rebuilding seed-cc (160,136 bytes) and seed-ar (98,624 bytes) byte for byte, 45 archive pins, Stage A (2,367,260 bytes of identical M1), K1's build check |
| `chain/plumbing-root.sh` (2026-10-08) | 18 minutes wall clock for all four entries, the GCC chain (binutils through stage D, `-j 6`) taking 967 s of it; 63,048 programs run (2,581 distinct paths) in a root that started with `hex0-seed` as its only executable; stage D at its fixed point: stage 2 = 3 = 4, 54 files each, 0 differ. |
| K1 | 221,672 bytes, sha256 `f90229b116c5a3b5...`, built by seed Forth with no other program running |
| `kernel/k1/run-chain.sh --direct-linux` (2026-10-08) | 1 h 38 min (`JOBS=2 K1_MEM=24G`; GCC chain 2,130 s, late tools 631 s, gcc64 2,334 s); stage D at its fixed point under K1, the late tools, gcc64's climb with all 31 `chain/gcc64/HASHES` pins as pinned, Linux 7.2.8 booted by kexec |
| bzImage | 1,278,976 bytes, CRC-32 `0014e6cc`, sha256 `881e96ad05da8e186c78bf055641c81bd5fd47d1a0bb4cc548c07d876d607179` |

An earlier, independent run of the same route produced the same bzImage,
gcc64 pins, stage D report and late-tool hashes ([HISTORY.md](HISTORY.md)).

## History and credits

[HISTORY.md](HISTORY.md) tells how the project was built and where its
files came from.  [CREDITS.md](CREDITS.md) lists the upstream sources and
their licenses.  The repository's own files are under the MIT License.
