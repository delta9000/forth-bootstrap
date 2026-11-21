# tinycc/ -- the TinyCC route and its junction with live-bootstrap

This route builds one compiler with seed Forth: janneke's TinyCC fork
`tcc-0.9.26-1147-gee75a10c`, targeting i386.  It then hands over to
live-bootstrap's `steps/tcc-0.9.26`, where that compiler stands in for
`tcc-mes`, the copy MesCC builds.

## The first tcc

`tinycc/build-first-tcc.sh` writes `build-out/tinycc/tcc-first`, an x86_64
static ELF of 792,776 bytes with sha256
`1a3a95abb749bd0d8877bb61121c86cda3aab0f97ff26ac56b546f3415d13fa8`.  The
pin is in `tests/pins/tinycc.sha256`.  Two checkouts at different paths
built the same bytes.

seed-forth is the only program that compiles anything.  It reads
`forth/010-lib.fth`, the compiler layers 020 to 119 without 081,
`tinycc/tcc-compile.fth` and `build-out/tcc-sources/direct-input.c`.  The
layers are loaded in native mode (`cc/115`, `117`-`119`): LP64 types,
float and double as 8-byte bit patterns, and a complete static ELF written
directly, with no object files or linker.  The driver comes from
seed-forth's `tools/tcc-compile.fth`.

The source it compiles:
- the fork from live-bootstrap's tarball, with what `pass1.kaem` does to it
  before MesCC runs: two `tcctools.c` simple-patches and an empty
  `config.h`;
- no patch of ours;
- pnut's `portable_libc` in the same translation unit, with two additions
  of ours: `libc-sscanf.c` after it, the `sscanf` that pnut's `stdio.h`
  declares but does not define, enough for tcc's one call,
  `sscanf(TCC_VERSION, "%d.%d.%d", ...)` in `libtcc.c`; and
  `libc-getcwd.before`/`.after`, a simple-patch to `src/unistd.c`, so that
  `getcwd` under `PNUT_CC` calls `_getcwd`, the Linux call
  `cc/119-cc-native-runtime.fth` emits when `tcc-compile.fth` sets
  `cc-native-getcwd`, instead of returning NULL;
- tcc-mes's defines for x86 (`direct-input.c`), so the compiler looks for
  headers and libraries where tcc-mes does.

## Source preparation

`tinycc/build-tools.sh` (run by `build-first-tcc.sh`) builds the programs
that check, unpack and patch the sources, with no host compiler:
seed-cc, which seed Forth builds (`cc/driver/seed-cc-start.fth`, pinned in
`tests/pins/outputs.sha256`), compiles them against
`chain/runtime/gcc-seed`, as `chain/plumbing/stage1.kaem` does:

| program | source |
|---|---|
| `sha256sum` `catm` `mkdir` `cp` `chmod` `rm` `match` | stage0-posix `mescc-tools-extra`, unchanged |
| `ungz` | `mescc-tools-extra`, with `tools/ungz-unsigned-bytes` |
| `untar` | `mescc-tools-extra`, with `tools/untar-ustar-prefix` |
| `simple-patch` | live-bootstrap `steps/simple-patch-1.0/src`, unchanged (`tools/simple-patch-unit.c` adds two headers) |
| `checksum-transcriber` | live-bootstrap `steps/checksum-transcriber-1.0/src`, unchanged |

Their sha256 are pinned in `tests/pins/tinycc.sha256`; two checkouts at
different paths built the same bytes.

The two changes of ours are simple-patch before/after pairs:
- `ungz-unsigned-bytes`: `stored()` reads a stored block's length bytes as
  plain `char` and compares them with `~len & 0xff`.  Plain `char` is
  signed in gcc-seed, so a byte of 0x80 or more fails ("puff() failed with
  return code -2").  The pnut archive has such blocks.  `bits()` already
  masks with `0xFF`; the patch masks these four reads the same way.
- `untar-ustar-prefix`: untar reads only the 100-byte name field.  GitHub's
  archive of live-bootstrap stores 200 long paths as ustar prefix plus
  name, among them `steps/tcc-0.9.26/simple-patches/*`.  Stock untar writes
  those to the bare name in the current directory, and tcc-0.9.27's files
  of the same names then overwrite them.  The patch joins prefix and name.

simple-patch is in the live-bootstrap archive, so stock ungz and untar
(`build-out/tinycc/bin-boot/`) unpack that archive first; its
`simple-patch.c` path fits the name field.  The patched tools then unpack
it again into `build-out/tinycc/lb/`.  With host `tar` as the reference,
the seed tools' trees of the live-bootstrap, pnut and tcc archives
compared equal under `diff -r` (symlinks included), apart from untar's
`pax_global_header` file.

The Forth compiler's native mode, which builds the first tcc, does not
build the tools.  They would need a libc that is not inside an archive
they must unpack: pnut's libc is in the pnut archive, and its 25 MB bump
heap cannot hold ungz's whole-file buffers for that 36 MB archive.
M2libc's system calls are M1 inline assembly, which the Forth compiler
does not read (found by reading M2libc's `amd64/linux/*.c`; no build was
tried).  seed-cc with gcc-seed is in the repository and already builds
these programs for the GCC chain.

Host programs left, from `strace -f -e trace=execve`:
- Source preparation (`build-first-tcc.sh`, which runs `build-tools.sh`):
  bash runs the scripts; `rm` and `mkdir -p` clear and make build-out
  directories; `dirname` finds the repository; `wc`, `sha256sum`, `sed`
  and `cut` print the size and compare tools and tcc-first with their
  pins.  None of them reads or writes a source file or the Forth input;
  the seed-built `catm` joins that, and seed-forth reads it as stdin.
- Replay (`tests/tinycc/junction-check.sh`), in addition: `bwrap` makes the
  root; `--probe` runs `chmod`, `mktemp`, `true` and `rm` for its i386
  test; `realpath` names the host's dynamic loader for the bind mount;
  `grep`, `sed`, `cut` and `sha256sum` print the log and compare the
  results.  Inside the root, host bash runs `lb-replay.sh`, which cuts
  live-bootstrap's kaem files and prints them with the host's `grep`,
  `awk`, `sed` and `cat`.  The kaem text itself runs in that bash with
  steps/env's PATH (the root's own `/usr/bin`, where the replay installs
  its tcc, and `/x86/bin`, which does not exist) followed by the
  seed-built tools, and nothing from the host.
- `tools/fetch-archives.py` (python3) downloads the archives.

The tools are built by seed-cc in SysV mode, so this route now also
depends on the compiler layers 120 and up and on
`chain/runtime/gcc-seed`, as the GCC chain already does.  A native-mode
build would need an in-tree copy of pnut's libc with a larger heap and a
`symlink` stub for untar.

## The junction

`tests/tinycc/junction-check.sh`, also `CHECK_TINYCC=1 ./check-all.sh`,
sets up a bwrap root laid out as live-bootstrap's.  It runs their kaem
text: the mes-0.28 header install, then `steps/tcc-0.9.26/pass1.kaem` with
the two MesCC commands replaced by copying the first tcc to `tcc-mes`
(`tinycc/lb-replay.sh`).  It then compares the result with their
`tcc-0.9.26.x86.checksums`:

| file | live-bootstrap (MesCC) | this route |
|---|---|---|
| `/usr/bin/tcc-mes` | `2b15c85f…` | `1a3a95ab…` (pinned) |
| `/usr/bin/tcc-boot0` | `ea464b2f…` | `c1696e57…` (pinned) |
| `/usr/bin/tcc-boot1` | `d9116def…` | same |
| `/usr/bin/tcc` | `b9dce87d…` | same |
| `/usr/lib/mes/libc.a` | `a6172e52…` | same |
| `/usr/lib/mes/libgetopt.a` | `12c07ae1…` | same |
| `/usr/lib/mes/crt1.o` | `76d280e0…` | same |
| `/usr/lib/mes/crti.o` | `09d4f982…` | same |
| `/usr/lib/mes/crtn.o` | `461ca149…` | same |
| `/usr/lib/mes/tcc/libtcc1.a` | `136f97c3…` | same |

**What this proves:** live-bootstrap's own script, with the same commands,
`-g`, working directories and paths, reaches the tcc and libraries it
publishes from either of two unrelated first compilers, MesCC or the Forth
compiler.  This is a diverse double-compile check of live-bootstrap's
`/usr/bin/tcc`.  The two routes differ up to tcc-boot0 and have the same
bytes from tcc-boot1 on.

**What it does not prove:**
- The i386 stages run on the host's Linux kernel through its 32-bit
  support, not under K0 or K1.  K1 loads only x86_64 ELF.
- Host bash stands in for kaem.  The other commands of the kaem text are
  the programs live-bootstrap uses, built by seed-cc (above); two of them
  carry a patch of ours.
- MesCC itself was not run.  Its column above is live-bootstrap's
  published file.

`tests/tinycc/junction-check.sh FIRST_TCC` runs the same replay from
another first compiler.  It expects that compiler to be configured like
tcc-mes: the study found that a first tcc built with the boot stages'
full feature set (`HAVE_FLOAT`, `HAVE_BITFIELD`, `HAVE_LONG_LONG`) gives
tcc-boot1 `b9dce87d…` already, so the boot1 line does not match although
`tcc` and the libraries do.

## What does not reproduce

- tcc-boot0 is `c1696e57…`, as the stand-ins that the junction study built
  with gcc, tcc 0.9.27 and seed-cc, using the same defines, gave.  MesCC's
  tcc-mes gives `ea464b2f…`.  Every first compiler other than MesCC now
  agrees from tcc-boot0 on.  Before the getcwd primitive, pnut's `getcwd`
  returned NULL and the first tcc recorded `/` as the `-g` directory,
  giving `4e3e525a…`.
- tcc-mes is a different program by design: an x86_64 binary with pnut's
  libc, not MesCC's i386 one.

## Inputs

`tinycc/SOURCES` and `MANIFEST.sha256` pin four archives under
`build-out/tinycc-inputs/`.  `tinycc/SOURCES` has no comments, because the
seed-built `sha256sum --check` reads it as it is:
- `tcc-0.9.26.tar.gz`: janneke's `tcc-0.9.26-1147-gee75a10c`, with the
  name, URL and sha256 of live-bootstrap's `steps/tcc-0.9.26/sources`;
- `mes-0.28.tar.gz`: GNU Mes 0.28, as `steps/mes-0.28/sources` pins it.
  Its headers and libc source are what the junction compiles;
- pnut at `abc34a52`, the commit seed-forth vendored.  Only
  `portable_libc/` is read, the libc compiled into the first tcc;
- live-bootstrap at `a49273cb`: the simple-patches, simple-patch and
  checksum-transcriber, and the kaem text and checksums of the junction.

GitHub generates the pnut and live-bootstrap archives from the commit and
does not promise their bytes stay the same.  If one changes, the commit in
its name is the identity of the source: compare `git archive` of that
commit with the new archive's contents before moving its pin.

`python3 tools/fetch-archives.py build-out/tinycc-inputs/<name>` downloads
them.
