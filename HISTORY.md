# History

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
| `tools/tangle.sh`, `tangle.awk`, `check-*.py`, `gen-index.py` | `tools/` (unchanged) |
| `tests/cc/`, `tests/gcc/`, `tests/gcc64/` | `tests/` (unchanged; `cc/040-cc-prep.fth` searches `tests/cc/` for quoted includes) |
| `book/`, `book.toml`, `vendor/` | unchanged |
| `k1/chain-inputs.sha256` and the archive pins in `ladder/stage12.sh` | `MANIFEST.sha256` |
| `k1/k1.S` | removed; `kernel/k1/k1-asm.fth` carries the instructions as comments |
| `patches/ladder/diffutils-3.10/01-tcc-paren-init.diff` | `chain/patches/late/diffutils-3.10/01-unparenthesize-ifdef-formats.diff` |

The guest sees the same layout: K1's root is the repository root, so
`/chain/ladder/stage12.sh` is `chain/ladder/stage12.sh`.

The compiler layers' own text did not change, so the book's `file=` blocks
still tangle byte-for-byte; the paths that did change are the ones scripts
open.  seed-cc and seed-ar name their inputs (cc/, forth/, the runtime's
directory), so those two programs differ from seed-forth's.  The objects
they compile and the K1 they build do not.
