# tinycc/ -- the TinyCC route and its junction with live-bootstrap

This route builds one compiler with seed Forth: janneke's TinyCC fork
`tcc-0.9.26-1147-gee75a10c`, targeting i386.  It then hands over to
live-bootstrap's `steps/tcc-0.9.26`, where that compiler stands in for
`tcc-mes`, the copy MesCC builds.

## The first tcc

`tinycc/build-first-tcc.sh` writes `build-out/tinycc/tcc-first`, an x86_64
static ELF of 790,384 bytes with sha256
`7b2efd95a84f1d7c83369db586ffc113a8931c7c417b6d7854f7e577b42f4d97`.  The
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
- one patch of ours, `patches/tcc-0.9.26/01-tinyc-version.diff`.  It writes
  in the version numbers because the libc has no `sscanf`;
- pnut's `portable_libc`, unchanged, in the same translation unit;
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
| `/usr/bin/tcc-mes` | `2b15c85f…` | `7b2efd95…` (pinned) |
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
  support, not under K0 or K1.  K1 loads only x86_64 ELF.  The hex0
  hand-off below runs them on builder-hex0 instead.
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

## The hex0 hand-off: the i386 stages on builder-hex0

`tests/tinycc/hex0-handoff-check.sh`, also `CHECK_HEX0_HANDOFF=1
./check-all.sh`, runs the junction without the host kernel, in two QEMU
boots and under a minute with KVM.

**Boot 1, K0.**  QEMU starts K0 with an empty 64 MiB drive.  K0 runs seed
Forth, which builds the recipe runner, which runs
`tinycc/hex0-handoff.recipe`:
1. seed Forth compiles the first tcc: `7b2efd95…`, as on the host;
2. the first tcc, as `/usr/bin/tcc-mes`, runs pass1.kaem's `tcc-mes` lines
   (translated into runner commands): crt1.o, crti.o, crtn.o, libc.a,
   libtcc1.a, libgetopt.a and tcc-boot0 `4e3e525a…`, as on the host;
3. the first tcc builds the i386 kaem, cp, chmod, match and rm
   (`vendor/`) and `tinycc/hex0-export.c` against that libc;
4. hex0-seed assembles builder-hex0's stage 1, and `tinycc/hex0-disk.c`
   (compiled by seed Forth like the runner) writes the disk image
   live-bootstrap's `lib/generator.py` writes: stage 1, the stage-2 hex0
   source, zeros to sector 175, then a stream of `src` records holding the
   trees, the boot-1 files and boot 2's script as `/kaem.run`, and the
   command `/usr/bin/kaem --verbose`.  K0's call 248 copies the image to
   the drive by PIO.

**Boot 2, builder-hex0.**  QEMU boots the drive with the arguments
live-bootstrap's `rootfs.py` uses, less its network card.  builder-hex0's stage 1 compiles stage 2 from hex0,
which reads the stream and runs kaem.  The script
(`tinycc/hex0-handoff-stream.py`) is live-bootstrap's text: their
variables, `cd build`, `cd ${TCC_PKG}` and ARCH blocks, and pass1.kaem from
"# Install" to "# Checksums".  Its last line, ours, runs `hex0-export`,
which writes the ten checksummed files as `src` records to `/dev/hda`;
builder-hex0 writes that file to the drive's first sectors when its
stream ends.

The host then reads the drive (`tinycc/hex0-records.py`) and hashes:

| file | live-bootstrap | boot 2 |
|---|---|---|
| `/usr/bin/tcc-mes` | `2b15c85f…` | `7b2efd95…` (pinned) |
| `/usr/bin/tcc-boot0` | `ea464b2f…` | `4e3e525a…` (pinned) |
| `/usr/bin/tcc-boot1` | `d9116def…` | same |
| `/usr/bin/tcc` | `b9dce87d…` | same |
| `/usr/lib/mes/libc.a` | `a6172e52…` | same |
| `/usr/lib/mes/libgetopt.a` | `12c07ae1…` | same |
| `/usr/lib/mes/crt1.o` | `76d280e0…` | same |
| `/usr/lib/mes/crti.o` | `09d4f982…` | same |
| `/usr/lib/mes/crtn.o` | `461ca149…` | same |
| `/usr/lib/mes/tcc/libtcc1.a` | `136f97c3…` | same |

Before boot 2 it also hashes the hand-off files in boot 1's stream
against `tests/pins/tinycc.sha256` (`tinycc/hex0-handoff/boot1/…`).

The hashes are taken on the host, not in boot 2: mescc-tools-extra's
`sha256sum.c` linked against this mes libc hashes every file as that many
zero bytes ("abc" gives `709e80c8…`, the sha256 of three NULs), because
it reads after `rewind` and the libc's `rewind` is `stub/rewind.c`.  A
guest-side `sha256sum -c` would prove nothing.

**Host involvement, item by item:** `tinycc/build-first-tcc.sh --prepare`
and `tinycc/lb-replay.sh --prepare` (in bwrap) unpack and patch the
sources with host tar, gzip and python3; host hex0-seed builds seed-forth
and K0; `tinycc/hex0-handoff-stream.py` cuts boot 2's script from the
pinned pass1.kaem and lists the stream's files; `kernel/k0/mkfs.py` (via
`tinycc/hex0-handoff-image.py`) writes K0's memory image; the host creates
the empty drive, starts QEMU twice and reads the drive.  It writes no
byte of boot 2's disk.

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

`tinycc/SOURCES` and `MANIFEST.sha256` pin five archives under
`build-out/tinycc-inputs/`:
- `tcc-0.9.26.tar.gz` and `mes-0.28.tar.gz`, with the URLs and sha256 of
  live-bootstrap's `sources` files;
- pnut at `abc34a52`;
- live-bootstrap at `a49273cb`;
- builder-hex0 at `a2781242`, live-bootstrap's submodule commit (the hex0
  hand-off only).

`python3 tools/fetch-archives.py build-out/tinycc-inputs/<name>` downloads
them.
