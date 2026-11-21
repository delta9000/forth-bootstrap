# tinycc/ -- the TinyCC route and its junction with live-bootstrap

This route builds one compiler with seed Forth: janneke's TinyCC fork
`tcc-0.9.26-1147-gee75a10c`, targeting i386.  It then hands over to
live-bootstrap's `steps/tcc-0.9.26`, where that compiler stands in for
`tcc-mes`, the copy MesCC builds.

## The first tcc

`tinycc/build-first-tcc.sh` writes `build-out/tinycc/tcc-first`, an x86_64
static ELF of 792,624 bytes with sha256
`3c11f52b2937bdfbd7e9197cdfe79cc57e84058a9b9c4067602e1f6279649bca`.  The
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
- pnut's `portable_libc`, unchanged, in the same translation unit, and
  after it `libc-sscanf.c`: the `sscanf` that pnut's `stdio.h` declares
  but does not define, enough for tcc's one call,
  `sscanf(TCC_VERSION, "%d.%d.%d", ...)` in `libtcc.c`;
- tcc-mes's defines for x86 (`direct-input.c`), so the compiler looks for
  headers and libraries where tcc-mes does.

## The junction

`tests/tinycc/junction-check.sh`, also `CHECK_TINYCC=1 ./check-all.sh`,
sets up a bwrap root laid out as live-bootstrap's.  It runs their kaem
text: the mes-0.28 header install, then `steps/tcc-0.9.26/pass1.kaem` with
the two MesCC commands replaced by copying the first tcc to `tcc-mes`
(`tinycc/lb-replay.sh`).  It then compares the result with their
`tcc-0.9.26.x86.checksums`:

| file | live-bootstrap (MesCC) | this route |
|---|---|---|
| `/usr/bin/tcc-mes` | `2b15c85f…` | `3c11f52b…` (pinned) |
| `/usr/bin/tcc-boot0` | `ea464b2f…` | `4e3e525a…` (pinned) |
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
- Host bash and coreutils stand in for kaem and the stage0-posix tools
  (`tinycc/kaem-shims.sh`).
- MesCC itself was not run.  Its column above is live-bootstrap's
  published file.

`tests/tinycc/junction-check.sh FIRST_TCC` runs the same replay from
another first compiler.  It expects that compiler to be configured like
tcc-mes: the study found that a first tcc built with the boot stages'
full feature set (`HAVE_FLOAT`, `HAVE_BITFIELD`, `HAVE_LONG_LONG`) gives
tcc-boot1 `b9dce87d…` already, so the boot1 line does not match although
`tcc` and the libraries do.

## What does not reproduce

- tcc-boot0 is `4e3e525a…`.  MesCC's tcc-mes gives `ea464b2f…`.  The stand-ins
  that the junction study built with gcc, tcc 0.9.27 and seed-cc, using the
  same defines, gave `c1696e57…`.  The difference from `c1696e57…` is the
  `-g` directory string.  Under `PNUT_CC`, portable libc's `getcwd` returns
  NULL, because the native runtime has no getcwd call.  So the first tcc
  records `/` instead of `/steps/tcc-0.9.26/build/tcc-0.9.26-1147-gee75a10c/`.
  Compiled without `-g`, `tcc.c` gives the same object from both.  A getcwd
  primitive in `cc/119-cc-native-runtime.fth` would probably close the gap,
  but this was not tried.
- tcc-mes is a different program by design: an x86_64 binary with pnut's
  libc, not MesCC's i386 one.

## Inputs

`tinycc/SOURCES` and `MANIFEST.sha256` pin four archives under
`build-out/tinycc-inputs/`:
- `tcc-0.9.26.tar.gz` and `mes-0.28.tar.gz`, with the URLs and sha256 of
  live-bootstrap's `sources` files;
- pnut at `abc34a52`;
- live-bootstrap at `a49273cb`.

`python3 tools/fetch-archives.py build-out/tinycc-inputs/<name>` downloads
them.
