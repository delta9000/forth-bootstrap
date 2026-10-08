# CLAUDE.md

Briefing for Claude Code sessions on forth-bootstrap.

## What this is

One bootstrap route, from stage0-posix's 229-byte `hex0-seed` to a Linux
kernel: a 1,772-byte hex0 Forth (`seed/`), a Forth library (`forth/`), a
C compiler written in Forth (`cc/`), the kernels K0 and K1 that host the
run under QEMU (`kernel/`), and the build chain from plumbing tools to
GCC 4.0.4, GCC 10.5.0 and Linux (`chain/`).  `README.md` has the map,
`HISTORY.md` the seed-forth origin and the path mapping.

## Invariants

- The literate book is a separate project (forth-bootstrap-book) whose
  `file=` blocks quote `seed/000-seed.hex0`, `forth/*.fth` and `cc/*.fth`
  byte for byte, and whose checks run against a checkout of this
  repository.  A change to those files means a matching change there.
- Compiled inputs keep their bytes unless the change is the point:
  `chain/runtime/`, `chain/plumbing/<package>/`, `chain/patches/`,
  `chain/gcc-direct/patches/`, `kernel/k1/*.c`, `*.h`, `k1-asm.fth`.  A
  comment edit there can still move a pinned hash (an `assert`'s
  `__FILE__`, a line number).  The pins that catch it: the stage D report,
  `chain/gcc64/HASHES`, K1's sha256 (printed by
  `kernel/k1/tests/direct-build-check.sh`), and the bzImage.
- `kernel/k1/k1-asm.fth`: every byte line carries its instruction as a
  comment; `kernel/k1/tests/asm-check.py` assembles the comments with GNU
  as and compares.  Change both together.
- The guest reads exactly the files in `kernel/k1/direct_inputs.py`.  A
  new file a stage reads goes there too; the archives come from
  `MANIFEST.sha256`, and `tools/check-pins.py` keeps the stages' own pin
  files in step with it.
- Repository paths are root-relative everywhere, and K1's root is the
  repository root, so the guest uses the same paths with a leading `/`.

## Checks

`./check-all.sh` runs the quick ones (about a minute).  The long ones
are opt in: `CHECK_CHAIN=1` (host chain to the GCC 4.0.4 fixed point,
about 40 minutes) and `CHECK_K1=linux` (hex0 to Linux under K1, about 80
minutes with KVM and 24 GiB for the guest).  Do not run the long ones on
every commit.

## Style

Prose in the docs and commit messages is plain and specific: say what a
thing does and what was measured, with the numbers.  Name files by their
repository paths.
