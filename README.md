# forth-bootstrap

From a 229-byte hex0 program to a Linux kernel, with no compiler from
outside.  stage0-posix's `hex0-seed` assembles a 1,772-byte Forth; a C
compiler written in that Forth builds a C driver, a shell and the first
Unix tools; those build GCC 4.0.4 until it reproduces itself, then GCC
10.5.0, then Linux 7.2.8.  The whole run can happen inside two small
kernels under QEMU: K0, 1,313 bytes of hex0, and K1, a C kernel that seed
Forth compiles.  K1 then hands the machine to the Linux kernel the run
built.

```
hex0-seed (229 bytes)
 └─ seed-forth (seed/000-seed.hex0, 1,772 bytes)
     └─ Forth library (forth/010-lib.fth)
         └─ C compiler in Forth (cc/020-141) ── seed-cc, seed-ar (cc/driver/)
             └─ kaem, mescc-tools-extra, make 3.82, sed, grep, gawk, coreutils,
                tar, gzip, patch, diffutils, oyacc, lex, flex 2.5.11, bash 2.05b
                 └─ binutils 2.30, GCC 4.0.4 + musl 1.1.24 (stage C), GCC 4.0.4
                    stage 2 = 3 = 4 (stage D)                       (chain/plumbing,
                     └─ late tools: make 4.4.1, bash 5.2, coreutils 9.5, ...   chain/gcc-direct)
                         └─ gcc-4.0.4 B = C, musl, gmp, mpfr, mpc, gcc-4.7.4,
                            binutils 2.41, gcc-10.5.0          (chain/ladder, chain/gcc64)
                             └─ Linux 7.2.8, kexec
```

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
| host `gcc`, GNU `as`, `nasm` | build references to compare against: Stage A's M2-Planet, `asm-check.py`'s object, `k0/check.sh`'s K0.  None of their output is used | checks only |

## The parts

| Directory | What is in it |
|---|---|
| `seed/` | `000-seed.hex0`, the annotated hex of the Forth; `build.sh` |
| `forth/` | `010-lib.fth`, the Forth library on the seed's 32 primitives; `130-asm.fth`, an M1 assembler and hex2 linker; their test |
| `cc/` | the C compiler in Forth, loaded in numeric order (`020-cc-arena.fth` to `141-archive.fth`); its tests; `driver/`, seed-cc and seed-ar, the compiler driver and archiver seed Forth builds |
| `kernel/` | `k0/` (K0 in hex0, with its NASM source), `k1/` (K1 in C and `k1-asm.fth`, its recipes, disk writers and tests), `tools/` (the recipe runner and the files that build K1) |
| `chain/` | `runtime/gcc-seed` (seed-cc's C library), `plumbing/` (the first tools, as kaem scripts), `gcc-direct/` (binutils, stage C, stage D, the late tools), `ladder/` and `gcc64/` (the climb to GCC 10.5.0 and Linux), `patches/`, `plumbing-root.sh` |
| `tests/` | Stage A and the M2-Planet headers the compiler falls back to; the chain's test programs |
| `tools/` | `check-pins.py` |
| `vendor/` | stage0-posix, mescc-tools and M2-Planet, as submodules |

The literate book that teaches `seed/`, `forth/` and `cc/` is a separate
project, forth-bootstrap-book, being rewritten in four parts.

## Running it

```sh
git submodule update --init --recursive
```

**1. The seed and the Forth** (seconds):

```sh
seed/build.sh                      # seed-forth, 1,772 bytes
./test.sh                          # seed primitives, 010-lib.fth, the first compiler layers
```

**2. The C compiler** (seconds; needs gcc for the reference):

```sh
tests/cc/stage-a-check.sh          # the Forth compiler's M1 for M2-Planet equals a GCC-built M2-Planet's
```

**3. The chain, on the host, to the GCC 4.0.4 fixed point** (about 40
minutes; needs `bwrap` and `strace`).  Put the archives of
`MANIFEST.sha256` under `build-out/` at the paths it names
(`chain/gcc64/SOURCES` has download URLs for the GCC climb's), then:

```sh
sha256sum -c MANIFEST.sha256
sh chain/plumbing-root.sh          # hex0-seed -> ... -> stage D: "fixed point reached"
```

The root it builds in starts with one executable, `hex0-seed`; every other
program that runs is one the chain built.  The traces of every `execve`
land in `build-out/plumbing-root.trace/`.

**4. K1** (a minute; needs QEMU):

```sh
sh kernel/k1/tests/direct-build-check.sh   # seed Forth builds K1; needs strace and as
kernel/k1/run-chain.sh --direct-smoke      # K0 -> K1 -> seed-cc, seed-ar and kaem under K1
```

**5. hex0 to Linux under K1** (about 80 minutes with KVM; 24 GiB of free
host RAM for the guest.  `K1_RAM_FILE` backs guest RAM with a file instead,
but on an SSD that costs terabytes of writes: avoid it):

```sh
JOBS=2 kernel/k1/run-chain.sh --direct-linux
```

QEMU loads K0 and its memory image; K0 runs seed Forth, which builds the
recipe runner and K1; K1 imports the input disk (the sources and archives
of `kernel/k1/direct_inputs.py`), builds seed-forth, seed-cc and the chain
of step 3 again under itself, then the late tools, the climb to GCC 10.5.0 and Linux, writes the results
to the output disk and kexecs into the new kernel, which prints
`init: hello from a Linux kernel built from hex0 and seed-forth`.

`./check-all.sh` runs the quick checks; `CHECK_CHAIN=1` and
`CHECK_K1=smoke|linux` add the long ones.

## Results

Measured on korriban (24 cores, 30 GiB, QEMU with KVM), 2026-10-08:

| Run | Result |
|---|---|
| `seed/build.sh` | `seed-forth`, 1,772 bytes |
| `./check-all.sh` | 5 OK: the seed, tests, 45 archive pins, Stage A (2,367,260 bytes of identical M1), K1's build check |
| `chain/plumbing-root.sh` | 18 minutes; about 63,000 programs run (2,581 distinct paths) in a root that started with `hex0-seed` as its only executable; stage D at its fixed point: stage 2 = 3 = 4, 54 files each, 0 differ |
| K1 | 221,672 bytes, sha256 `f90229b116c5a3b5...`, built by seed Forth with no other program running |
| `kernel/k1/run-chain.sh --direct-linux` | 1 h 38 min (`JOBS=2 K1_MEM=24G`); stage D at its fixed point under K1, the late tools, gcc64's climb with all 31 `chain/gcc64/HASHES` pins as pinned, Linux 7.2.8 booted by kexec |
| bzImage | 1,278,976 bytes, CRC-32 `0014e6cc`, sha256 `881e96ad05da8e186c78bf055641c81bd5fd47d1a0bb4cc548c07d876d607179` |

The bzImage, the 31 gcc64 pins, the stage D report and the hashes of all
159 late-tool programs are the same as those of seed-forth's run of this
route (0dd2b88), whose bzImage in turn is byte-identical to the one
seed-forth's TinyCC route builds.  K1 differs from seed-forth's
(`7621950c...`) by the `cld` its exception entry now starts with; seed-cc
and seed-ar differ because they name this repository's paths.

## Where it came from

This is route D of [seed-forth](https://github.com/delta9000/seed-forth),
moved here on its own; [HISTORY.md](HISTORY.md) says what stayed behind
and maps the old paths to the new ones.  [CREDITS.md](CREDITS.md) lists
the upstream sources and their licenses.  The repository's own files are
under the MIT License.
