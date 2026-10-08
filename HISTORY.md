# History

forth-bootstrap is route D of [seed-forth](https://github.com/delta9000/seed-forth),
taken from commit 0dd2b88 (branch qemu-final, PR #18).  seed-forth grew a
1,772-byte hex0 Forth and a C compiler in Forth, then several routes from
them, all built by Ben Sandbrook with AI models (see
[AI_STRATEGIES.md](AI_STRATEGIES.md)).  Route D is the one that reaches
Linux with no other compiler at all: seed-cc, plumbing tools built by it,
GCC 4.0.4 to a stage 2 = 3 = 4 fixed point, the late tools, gcc64's climb
to GCC 10.5.0, and Linux 7.2.8 under K1.  seed-forth recorded its full run
under K1 on 2026-10-07 (78 minutes, `JOBS=2 K1_MEM=24G`): stage D at its
fixed point (54 files, 0 differ) and a 1,278,976-byte bzImage, sha256
`881e96ad05da8e18...`, identical to the TinyCC route's.  Everything
else stayed in seed-forth with its results:

- **The TinyCC route.**  seed Forth compiles TinyCC 0.9.27 directly
  (an 870,752-byte intermediate compiler), and tcc-boot2 = tcc-boot3
  (305,496 bytes, sha256 `514bc4d3...`, the same as through pnut); under K0 and K1 the "ladder" goes on to GCC 10.5.0 and
  Linux, which passed under QEMU/KVM on 2026-10-07 (about 1h15m, with the
  DF fix of seed-forth 7c1c422).
- **pnut** (`vendor/pnut`, `tests/pnut/`): seed Forth builds pnut
  unmodified for i386 and amd64 and pnut self-hosts.
- **gcc64 on to GCC 15.2.0**: stages 0-5 (TinyCC, musl, binutils, gcc-A by
  tcc) and 11-12 (GCC 15.2.0's own three-stage bootstrap, stage2 = stage3;
  about 1.5 hours), with artifact pins in seed-forth's `gcc64/HASHES`.
- **bootstrap.sh and handoff.sh**: hex0-seed to a self-hosted M2-Planet
  (v2 = v3) in about 30 seconds, and stage0-posix's own amd64 and x86
  recipes fed by the Forth route, reproducing all 19 `amd64.answers` and
  all 19 `x86.answers` binaries.
- The Python stage drivers for the GCC chain (`gcc-direct/*.py`), which
  the shell stages here (`chain/gcc-direct/*.sh`, "the bash port of
  ...py") replaced, and seed-forth's design notes (`DIRECT-GCC.md`,
  `REPRODUCIBLE.md`, `HOST-TOOLS.md`).

seed-forth's literate book, which teaches the seed, the Forth and the C
compiler chapter by chapter, is not in this repository either: it is a
separate project, forth-bootstrap-book, being rewritten in four parts.
Its `file=` blocks quote this repository's `seed/`, `forth/` and `cc/`
sources byte for byte, and its checks run against a checkout of this
repository.

Some files here still describe themselves in seed-forth's terms
(`kernel/k1/README.md`, `chain/plumbing/*.md`): the route they describe
is this one, and the TinyCC parts they mention are in seed-forth.

## Path mapping from seed-forth

forth-bootstrap started as a copy of the files route D reads in seed-forth
0dd2b88, kept at their old paths (the first commit), and was then laid out
by part.  Every path below is relative to the repository root; `NNN` is a
three-digit layer number, kept in the file names.

| seed-forth (0dd2b88) | forth-bootstrap |
|---|---|
| `000-seed.hex0`, `build.sh` | `seed/` |
| `010-lib.fth`, `130-asm.fth`, `test-010-lib.fth` | `forth/` |
| `NNN-cc-*.fth`, `141-archive.fth`, `test-0N0-cc-*.fth` | `cc/` |
| `tools/compiler-layers.sh` | `cc/compiler-layers.sh` |
| `tools/seed-cc.c`, `seed-ar.c`, `seed-tool.h`, `seed-cc-start.fth`, `seed-cc-boot/` | `cc/driver/` |
| `runtime/gcc-seed/` | `chain/runtime/gcc-seed/` |
| `plumbing/` | `chain/plumbing/` |
| `gcc-direct/` (shell stages and patches; the Python drivers stayed behind) | `chain/gcc-direct/` |
| `ladder/` (stage10-direct, 11, 12, finish and their helpers) | `chain/ladder/` |
| `gcc64/` (bridge and stages 6-10) | `chain/gcc64/` |
| `patches/gcc64/`, `patches/ladder/` | `chain/patches/gcc64/`, `chain/patches/late/` |
| `tools/plumbing-root.sh` | `chain/plumbing-root.sh` |
| `k0/` | `kernel/k0/` |
| `k1/` | `kernel/k1/` |
| `tools/amd64-runner.c`, `amd64-syscalls.fth`, `obj-asm.fth`, `k1-direct-start.fth`, `k1-direct.recipe`, `k1-direct-boot.recipe` | `kernel/tools/` |
| `book/`, `book.toml`, `tools/tangle.sh`, `tangle.awk`, `check-numbers.py`, `check-tryit.py`, `check-links.py`, `gen-index.py` | forth-bootstrap-book, a separate project |
| `tests/cc/`, `tests/gcc/`, `tests/gcc64/` | `tests/` (unchanged; `cc/040-cc-prep.fth` searches `tests/cc/` for quoted includes) |
| `vendor/` | unchanged |
| `k1/chain-inputs.sha256` and the archive pins in `ladder/stage12.sh` | `MANIFEST.sha256` |
| `k1/k1.S` | removed; `kernel/k1/k1-asm.fth` carries the instructions as comments |
| `patches/ladder/diffutils-3.10/01-tcc-paren-init.diff` | `chain/patches/late/diffutils-3.10/01-unparenthesize-ifdef-formats.diff` |

The guest sees the same layout: K1's root is the repository root, so
`/chain/ladder/stage12.sh` is `chain/ladder/stage12.sh`.

The compiler layers' own text did not change, so the book's `file=` blocks
still quote them byte for byte; the paths that did change are the ones
scripts open.  seed-cc and seed-ar name their inputs (cc/, forth/, the runtime's
directory), so those two programs differ from seed-forth's.  The objects
they compile and the K1 they build do not.
