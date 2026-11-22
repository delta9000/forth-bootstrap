# CLAUDE.md

Briefing for Claude Code sessions on forth-bootstrap.

## What this is

One bootstrap route, in one boot of builder-hex0 from a disk of sources:
the kernel's built-in hex0 assembles a 1,191-byte Forth
(`seed/000-seed.hex0`); that Forth loads a library (`forth/`) and a C
compiler written in Forth (`cc/`); the compiler builds kaem, eleven tools
and tcc 0.9.26 with Mes libc (`tinycc/`); live-bootstrap's own
`tcc-0.9.26` step runs from that tcc and ends in the binaries
live-bootstrap publishes.  `README.md` has the map, `HISTORY.md` the
origin of the files.

Everything else the repository once held (an x86-64 seed and back end,
the kernels K0 and K1, the GCC chain, the M2-Planet subset) is at tag
`experiments-2026-11-21`, branch `experiments/all-routes`.  A comparison
with those files belongs in a sentence that names the tag.

## Oracles

`./check-all.sh` is the gate for every commit: all default steps OK
(about two minutes; its header lists the fifteen steps).  Step 11, the
gcc stand-in, runs only with `CHECK_STANDIN=1`, because the gcc-built
reference varies about one run in eight; a failure there on `tcc-boot0`
alone is that variation.

What the steps hold fixed:

- `tests/pins/tinycc.sha256`: the first tcc (`92d11438…`), kaem, the
  tools and what the boot builds first.  A refactor of `cc/`, `forth/` or
  `tinycc/` leaves every hash as it is; a hash that moves is a changed
  compiler, and the commit that means it updates the line and says why.
- The seed: `seed/000-seed.hex0` is frozen, bytes and comments.  Its
  header comment still names the paths from before the rename
  (`seed/i386/…`); `seed/SPEC.md`, section 12, records that.
- The gates: `tests/cc/gates/run-gates.sh`, 130 cases.  A die gate pins
  an error code and a line; a refusal is removed only with its gate and a
  reason.
- The junction and the one boot (steps 10 and 15): live-bootstrap's
  published `tcc-boot1`, `tcc` and libraries, byte for byte.

After renaming anything a script writes under `build-out/`, run the
checks from a `build-out/` that holds only the four archives, so nothing
passes on a stale file.

## Invariants

- The literate book is a separate project (forth-bootstrap-book) whose
  `file=` blocks quote `seed/000-seed.hex0`, `forth/*.fth` and `cc/*.fth`
  byte for byte, and whose checks run against a checkout of this
  repository.  A change to those files, or to their paths, means a
  matching change there; say which files changed when you report.
- Every byte of machine code written by hand carries its instruction as
  a comment, and an assembler check compares the two:
  `tests/seed/asm-check.py`, `tests/forth/asm-check.py`,
  `tests/cc/asm-check.py`.  Change bytes and comment together.
- The compiler's input is fixed (tcc, Mes libc, M2libc, kaem, the tools,
  all pinned), so it is as small as that input allows: prefer deleting to
  adding, and add a refusal only for input the route can meet.
  `cc/README.md` lists the invalid programs it accepts.
- The boot reads every repository file at its repository path under `/`.
  A file a seed run reads has to be on the disk
  (`tinycc/one-boot-disk.py`), and the run may make only the system
  calls builder-hex0 answers (`tests/tinycc/seed-check.sh` checks the
  calls on the host).
- The code is read by auditors: conventional, readable Forth; names say
  what a word does on i386 (`cc/090-cc-emit.fth`'s header has the
  register-pair convention).
- AI use is disclosed plainly, once: the README and PR descriptions say
  that most of the code was written with AI models under the owner's
  direction, and HISTORY.md records how.  Commits and files carry no
  Co-Authored-By trailers, session links or "generated with" lines.

## Style

Prose in the docs and commit messages is plain and specific: say what a
thing does and what was measured, with the numbers.  Name files by their
repository paths.  One logical change per commit, and the message says
why.
