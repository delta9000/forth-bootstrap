# tinycc/ -- the TinyCC route and its junction with live-bootstrap

This route builds one compiler with seed Forth: janneke's TinyCC fork
`tcc-0.9.26-1147-gee75a10c`, targeting i386.  It then hands over to
live-bootstrap's `steps/tcc-0.9.26`, where that compiler stands in for
`tcc-mes`, the copy MesCC builds.

## The first tcc

`tinycc/build-first-tcc.sh` writes `build-out/tinycc/tcc-first`, an x86_64
static ELF of 856,568 bytes with sha256
`d9e97270f8d39587b2ef57d675cf733aa239b11f288c75d6b2fcc4adf7019fec`.  The
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
- Mes 0.28's libc in the same translation unit, from the `mes-0.28`
  tarball the junction already needs: `mes-libc.c` includes the files
  live-bootstrap's `pass1.kaem` compiles into tcc-mes's `libc.a` (its
  `unified-libc.c` list, with x86_64 for the architecture), in that order,
  without seven.  Four are inline assembly (`syscall.c`, `_exit.c`,
  `_write.c`, `setjmp.c` under `x86_64-mes-gcc`); two are the double
  conversions under `strtod`, `atof` and printf's `%f` (`mes/abtod.c`,
  `mes/dtoab.c`), and `math/ceil.c` is double arithmetic that nothing
  calls.  Native mode keeps doubles as bit patterns and has no arithmetic
  on them.  As `steps/mes-0.28` does, `include/arch/` gets copies of
  `include/linux/x86_64`'s three headers, and `include/mes/config.h` is
  empty;
- `mes-libc-native.c`, ours, first in the unit: the system-call layer
  (`__sys_call*`, `_sys_call*` with Mes's errno handling, `_exit`,
  `_write`) on `__native_syscall`, the one primitive
  `cc/119-cc-native-runtime.fth` emits when `tcc-compile.fth` sets
  `cc-native-syscall-any`; a `setjmp` that returns 0 and a `longjmp` that
  exits 125 (tcc only longjmps after printing an error); `abtod` and
  `dtoab` that exit 125 rather than return wrong bits; and crt1's work, a
  `main` that sets `environ` and stdio as `__init_io` does before calling
  the program's, renamed.  It also replaces Mes's `jmp_buf`, an array of
  one struct, which native mode cannot pass as an argument;
- tcc-mes's defines for x86 (`direct-input.c`), so the compiler looks for
  headers and libraries where tcc-mes does.

## Source preparation

`tinycc/build-tools.sh` (run by `build-first-tcc.sh`) builds the programs
that check, unpack and patch the sources, with no host compiler.
seed-forth compiles each in native mode, as it compiles the first tcc
(layers 020 to 119), against stage0-posix's M2libc
(`vendor/stage0-posix/M2libc`, in the repository):

| program | source |
|---|---|
| `sha256sum` `catm` `mkdir` `cp` `chmod` `rm` `match` | stage0-posix `mescc-tools-extra`, unchanged |
| `ungz` | `mescc-tools-extra`, with `tools/ungz-unsigned-bytes` |
| `untar` | `mescc-tools-extra`, with `tools/untar-ustar-prefix` |
| `simple-patch` | live-bootstrap `steps/simple-patch-1.0/src`, unchanged |
| `checksum-transcriber` | live-bootstrap `steps/checksum-transcriber-1.0/src`, unchanged |

Their sha256 are pinned in `tests/pins/tinycc.sha256`; two checkouts at
different paths built the same bytes, the second with no seed-cc in its
`build-out`.  All thirteen build in under two seconds.

M2libc is compiled in its own M2 mode, as M2-Mesoplanet builds these
tools for stage0-posix: `__M2__` makes its headers include its `.c`
files, so each tool is one translation unit.  `tinycc/m2libc-native.c`,
ours, goes ahead of the tool's source and stands in for what M2-Planet
and M2libc's M1 assembly provide:
- `amd64/linux/unistd.c`, `fcntl.c` and `sys/stat.c`: it defines their
  include guards, their constants, and in C the thirteen system calls the
  tools reach, each on `__native_syscall` (cc-native-syscall-any, as for
  the first tcc), plus `getcwd` and `_exit`;
- `libc-full.M1`'s `_start` and `exit`: a `main` that sets `_envp` and
  calls `__init_malloc` and `__init_io` before the tool's `main` (renamed),
  and an `exit` that flushes through `__kill_io`;
- M2-Planet's built-in types (`SCM`, `FUNCTION`, the fixed-width
  integers), and `va_list` for native mode's eight-byte stack slots in
  place of the `__va_*` builtins M2libc's `stdarg.h` names;
- `stdlib.c` and `string.c` both define `memset`, which M2-Planet accepts
  and native mode does not (error 211); `stdlib.c`'s, called only by its
  `calloc`, is renamed.

M2libc's `malloc` grows the heap with `brk`, so ungz holds a whole archive
in memory: the 36 MB pnut archive unpacked in 4.1 s and 122 MB.

The Forth input for each tool is the layers, three lines naming the output
and the source, `tinycc/tool-compile.fth`, the shim and the source, joined
by the seed-built `catm`; bash's builtin `printf` writes the three lines,
as a command line would carry them.  `catm`'s own input has to be joined
before `catm` exists: `tinycc/catm-start.fth`, a Forth program for the
seed alone (its first words are `cc/driver/seed-cc-start.fth`'s), writes
it, with catm's names in `tinycc/tools/catm.fth`.  The driver writes each
tool with mode 0755, so nothing needs `chmod` before `chmod` is built.

The two changes of ours are simple-patch before/after pairs:
- `ungz-unsigned-bytes`: `stored()` reads a stored block's length bytes as
  plain `char` and compares them with `~len & 0xff`.  Where plain `char`
  is signed, as in gcc-seed, which built these tools before, a byte of
  0x80 or more fails ("puff() failed with
  return code -2").  The pnut archive, an input until the first tcc moved
  to Mes libc, has such blocks; the three archives left do not (stock ungz
  gives the same tars).  `bits()` already masks with `0xFF`; the patch
  masks these four reads the same way.
- `untar-ustar-prefix`: untar reads only the 100-byte name field.  GitHub's
  archive of live-bootstrap stores 200 long paths as ustar prefix plus
  name, among them `steps/tcc-0.9.26/simple-patches/*`.  Stock untar writes
  those to the bare name in the current directory, and tcc-0.9.27's files
  of the same names then overwrite them.  The patch joins prefix and name.

simple-patch is in the live-bootstrap archive, so stock ungz and untar
(`build-out/tinycc/bin-boot/`) unpack that archive first; its
`simple-patch.c` path fits the name field.  The patched tools then unpack
it again into `build-out/tinycc/lb/`.  With host `tar` as the reference,
the native tools' trees of the live-bootstrap, Mes, tcc and pnut archives
compared equal under `diff -r` (symlinks included), apart from untar's
`pax_global_header` file; so did the seed-cc tools' trees before them.

Host programs left, from `strace -f -e trace=execve`:
- Source preparation (`build-first-tcc.sh`, which runs `build-tools.sh`):
  bash runs the scripts; `rm` and `mkdir -p` clear and make build-out
  directories; `dirname` finds the repository; `wc`, `sha256sum`, `sed`
  and `cut` print the size and compare tools and tcc-first with their
  pins.  None of them reads or writes a source file or the Forth input;
  the seed-built `catm` joins that (`catm-start.fth` for catm's own), and
  seed-forth reads it as stdin.  One part of each tool's Forth input is
  not a file from the repository or an archive: the three-line names
  file, which bash itself writes with its builtin `printf`.
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

This route uses only the compiler layers 020 to 119 in native mode: not
seed-cc, the layers 120 and up, or `chain/runtime/gcc-seed`.

## The junction

`tests/tinycc/junction-check.sh`, also `CHECK_TINYCC=1 ./check-all.sh`,
sets up a bwrap root laid out as live-bootstrap's.  It runs their kaem
text: the mes-0.28 header install, then `steps/tcc-0.9.26/pass1.kaem` with
the two MesCC commands replaced by copying the first tcc to `tcc-mes`
(`tinycc/lb-replay.sh`).  It then compares the result with their
`tcc-0.9.26.x86.checksums`:

| file | live-bootstrap (MesCC) | this route |
|---|---|---|
| `/usr/bin/tcc-mes` | `2b15c85f…` | `d9e97270…` (pinned) |
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
  support, not under K0 or K1.  K1 loads only x86_64 ELF.  The hex0
  hand-off below runs them on builder-hex0 instead.
- Host bash stands in for kaem.  The other commands of the kaem text are
  the programs live-bootstrap uses, built by seed Forth in native mode
  against M2libc (above); two of them carry a patch of ours.
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
1. seed Forth compiles the first tcc: `d9e97270…`, as on the host.  Its
   Mes libc's malloc grows the heap with brk, which K0 has for it;
2. the first tcc, as `/usr/bin/tcc-mes`, runs pass1.kaem's `tcc-mes` lines
   (translated into runner commands): crt1.o, crti.o, crtn.o, libc.a,
   libtcc1.a, libgetopt.a and tcc-boot0 `c1696e57…`, as on the host;
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
| `/usr/bin/tcc-mes` | `2b15c85f…` | `d9e97270…` (pinned) |
| `/usr/bin/tcc-boot0` | `ea464b2f…` | `c1696e57…` (pinned) |
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

**Host involvement, item by item:** no host program unpacks or patches
a source.  The seed-built tools do it, as for the junction:
`tinycc/build-first-tcc.sh --prepare` (which runs `tinycc/build-tools.sh`)
checks the archives and lays out `build-out/tcc-sources/`; the seed-built
`sha256sum`, `ungz` and `untar` check and unpack builder-hex0; and
`tinycc/lb-replay.sh --prepare` runs pass1.kaem's lines before MesCC in
bwrap, on the live-bootstrap tree `build-tools.sh` unpacked.  What the
host still does: bash runs those scripts and stands in for kaem in
`lb-replay.sh`, whose kaem text is cut by host grep, awk, sed and cat;
bash's printf writes each tool's three-line names file, part of its
Forth input (`tinycc/build-tools.sh`); the scripts' rm, mkdir, dirname,
wc, sha256sum, sed and cut clear `build-out/` directories and compare the
tools and the first tcc with their pins; host hex0-seed builds seed-forth
and K0;
`tinycc/hex0-handoff-stream.py` cuts boot 2's script from the pinned
pass1.kaem and lists the stream's files; `kernel/k0/mkfs.py` (via
`tinycc/hex0-handoff-image.py`) writes K0's memory image, copying every
prepared source file into it; the host creates the empty drive, starts
QEMU twice and reads the drive (`tinycc/hex0-records.py`).  It writes no
byte of boot 2's disk.

## The i386 first tcc

`tinycc/build-first-tcc-i386.sh` writes `build-out/tinycc/tcc-first-i386`,
the same program as an i386 static ELF of 975,624 bytes: the first step
towards running the whole route on builder-hex0, which is an i386 kernel.
The seed that compiles it is still the x86-64 one, on the host.

The compiler is the same layers with the i386 back end among them
(`cc/i386/`, `cc/README.md`; `cc/i386/layers.sh` prints the load order).
The C is the same too, with what the target changes:
- `include/arch/` gets Mes's `include/linux/x86` headers, and
  `direct-input-i386.c` defines `__i386__` where `direct-input.c` defines
  `__x86_64__`.  `__SIZEOF_LONG_LONG__` stays undefined, as MesCC leaves
  it, so Mes's `struct stat` is the old i386 one the kernel fills.
- `mes-libc-native-i386.c` is the system-call layer.  Besides the numbers
  it differs from `mes-libc-native.c` in two ways.  It replaces Mes's
  `stdarg.h`, because native mode keeps every argument in an 8-byte slot
  while a pointer is now 4 bytes.  And it passes to the kernel only the
  calls builder-hex0 has (exit, fork, read, write, open, close, waitpid,
  execve, chdir, lseek, access, mkdir, brk, getcwd); any other gets
  builder-hex0's answer, 0, without a system call.  tcc makes three such
  calls: `unlink` before it writes an output file, and `stat` and
  `unlink` in Mes's `remove`, after `tcc -ar` has copied its temporary
  file.  So on Linux, as on builder-hex0, the first tcc leaves
  `libc.a.tmp`, `libtcc1.a.tmp` and `libgetopt.a.tmp` behind.
- the entry stub (`cc/i386/117-entry.fth`) raises the break to the end of
  the bss if it is below it, and zeroes 1 MiB of stack below esp.  The
  replay passes with `ulimit -s 48`, so the first tcc uses under 48 KiB.

`tinycc/build-tools-i386.sh` builds the thirteen tools the same way into
`build-out/tinycc/bin-i386/`, with `m2libc-native-i386.c`.

Checks, all on the host through its IA32 support (`CHECK_I386=1
./check-all.sh` runs them):
- `tests/tinycc/junction-check.sh --i386`: the replay with the i386 first
  tcc and the i386 tools reaches tcc-boot0 `c1696e57…`, tcc-boot1
  `d9116def…`, `/usr/bin/tcc` `b9dce87d…` and the six libraries, as the
  x86-64 first tcc does.
- `tests/tinycc/i386-standin-check.sh`: gcc `-m32` compiles the same unit
  with Mes's own i386 assembly files; every file the two first compilers
  write in the replay (the crt files, `unified-libc.o`, `libc.a`,
  `libtcc1`, getopt and tcc-boot0) has the same bytes.
- `tests/tinycc/i386-syscall-check.sh`: under `strace -f`, the first tcc
  and the tools make only builder-hex0's calls (rm's `unlink`, chmod's
  `chmod` and untar's `symlink` apart), never lower the break, never
  write past the end of a file and only grow the newest file.
- `tests/cc/i386/run-corpus.sh`: small C programs compiled by the i386
  back end and by gcc `-m32` print the same lines.  They cover what the
  pins cannot see: the high halves of `long long` values.
- `tests/cc/i386/asm-check.py` and `tests/cc/i386/x86-64-bytes-check.sh`:
  the encoders' bytes equal GNU as on their comments, and no x86-64
  encoder of `cc/090-cc-emit.fth` or REX prefix of a later layer is
  reached when the first tcc is compiled.

Not done here: the i386 seed.

## One boot on builder-hex0

`tests/tinycc/i386-one-boot-check.sh`, also `CHECK_I386_BOOT=1
./check-all.sh`, runs live-bootstrap's whole tcc-0.9.26 step on
builder-hex0 in one QEMU boot of 15 to 17 s with KVM, from the i386 first tcc
and the i386 tools.  It is an experiment on the way to a one-boot route:
the programs on the disk are still built on the host.

**The disk.**  `tinycc/i386-one-boot-disk.py` writes it in the layout of
live-bootstrap's `lib/generator.py`: builder-hex0's stage 1 (assembled by
hex0-seed), its stage-2 hex0 source, zeros to sector 175, then:
- the directories live-bootstrap's `seed.kaem` and disk have, and ours:
  `/x86/bin`, `/external/distfiles`, `/first`;
- `/usr/bin/tcc-mes`, the i386 first tcc (`92d11438…`);
- `/x86/bin/`, the second directory of `steps/env`'s PATH, with the eleven
  i386 tools of `tinycc/build-tools-i386.sh` and `kaem`;
- `/external/distfiles/` with the three archives of `tinycc/SOURCES`, and
  that file with their paths in the boot;
- `/hex0-export.c` (`tinycc/hex0-export.c`) and the script, `/kaem.run`;
- the command `/x86/bin/kaem --verbose`.

**kaem is host-built.**  The i386 first tcc compiles
`vendor/mescc-tools/Kaem` against the Mes libc it has just made, as boot 1
of the hand-off does under K0, but here on the host's Linux kernel through
its IA32 support, in the bwrap root of `tests/tinycc/junction-check.sh
--i386`.  It has the bytes of the hand-off's kaem (`3b1ce310…`).

**The script** (`build-out/tinycc/i386-one-boot/i386-one-boot.kaem`) is
live-bootstrap's text, the lines `tinycc/lb-replay.sh` runs on the host,
cut at the same markers:
1. `steps/env`'s and `seed.kaem`'s variables.
2. Ours: `sha256sum -c` of the three archives; `ungz` and `untar` of
   live-bootstrap's archive in `/`; `cp` of the five files of it that
   pass1.kaem reads (`sources` and the four simple-patch files) to
   `/steps/tcc-0.9.26/`.  builder-hex0 cannot rename a directory, and
   tcc's `-g` records the working directory, so the build has to be at
   live-bootstrap's path.
3. Of `steps/mes-0.28/pass1.kaem`: the unpacking and the header install.
4. `steps/tcc-0.9.26/pass1.kaem` from "# Vars" to "# Checksums", without
   the two MesCC commands and the `cp` and `chmod` that install their
   tcc-mes: the archive check, `ungz`, `untar`, the two `simple-patch`
   lines, then tcc-mes, tcc-boot0, tcc-boot1 and tcc-boot2.
5. Ours, before "# Install": `cp` of the six library files tcc-mes made to
   `/first`, because the later stages overwrite them, and `tcc-mes -static`
   of `hex0-export`.  Ours, last: `hex0-export /dev/hda` with the files
   below.

The host reads the drive (`tinycc/hex0-records.py`) and hashes:

| file | expected | the boot |
|---|---|---|
| `/usr/bin/tcc-mes` | `92d11438…` (pinned; MesCC's is `2b15c85f…`) | same |
| `/usr/bin/tcc-boot0` | `c1696e57…` (pinned; MesCC's is `ea464b2f…`) | same |
| `/usr/bin/tcc-boot1` | `d9116def…` (live-bootstrap) | same |
| `/usr/bin/tcc` | `b9dce87d…` (live-bootstrap) | same |
| `/usr/lib/mes/libc.a` | `a6172e52…` (live-bootstrap) | same |
| `/usr/lib/mes/libgetopt.a`, `crt1.o`, `crti.o`, `crtn.o`, `tcc/libtcc1.a` | live-bootstrap's | same |
| `/first/libc.a` | `84d12efe…` (pinned, `hex0-handoff/boot1`) | same |
| `/first/crt1.o`, `crti.o`, `crtn.o`, `libtcc1.a`, `libgetopt.a` | pinned, `hex0-handoff/boot1` | same |
| `/x86/bin/kaem` | `3b1ce310…` (pinned, `hex0-handoff/boot1`) | same |
| `/usr/bin/hex0-export` | `498dea62…` (pinned, `hex0-handoff/boot1`) | same |

**What it shows.**  The Forth compiler's i386 programs run on builder-hex0
as they run on Linux: the first tcc and the tools make the
same bytes there, with no change to the back end, the entry stub or the
two system-call layers.  The M2libc-built `sha256sum` hashes correctly in
the boot, which the Mes-libc one of the hand-off does not.

**What it does not show.**
- No program on the disk has more than 0x20000 bytes of bss (the first
  tcc has 80,592), so builder-hex0 starts each with its break above the
  bss and the entry stub's brk is never made in this boot.
- The host builds every program on the disk: the x86-64 seed-forth
  compiles the first tcc and the tools, and the first tcc compiles kaem
  under Linux.
- The host cuts the script from the pinned kaem files (python3), checks
  and unpacks builder-hex0's archive with the seed-built tools, runs
  hex0-seed for stage 1, writes the disk, starts QEMU and reads the drive.

## What does not reproduce

- tcc-boot0 is `c1696e57…`, as the stand-ins that the junction study built
  with gcc, tcc 0.9.27 and seed-cc, using the same defines, gave.  MesCC's
  tcc-mes gives `ea464b2f…`.  Every first compiler other than MesCC now
  agrees from tcc-boot0 on.  Before the first tcc had a real `getcwd`,
  it recorded `/` as the `-g` directory, giving `4e3e525a…`.
- The gcc `-m32` stand-in of `tests/tinycc/i386-standin-check.sh` does
  not always make that tcc-boot0, so the check fails about one run in
  eight.  Compiling tcc-boot0 1,000 times in the replay's root, the
  stand-in made `c1696e57…` 869 times and `9cb082b3…`, 356 bytes longer,
  131 times; the i386 first tcc made `c1696e57…` 1,000 times.  The two
  files differ in `unary`, where the longer one computes three
  floating-point constant expressions at run time that the other has
  folded.  The outcome follows the stand-in's stack address: with
  `setarch -R` (stack at `0xffff…`) it made `9cb082b3…` 100 times of 100,
  with `setarch -R -3` (stack below `0xc0000000`) `c1696e57…` 100 times of
  100; the i386 first tcc made `c1696e57…` 200 times of 200 under
  `setarch -R`.  Not found: which value the stand-in reads before
  writing it.  A stack address of `0xfff00000` or more read as the high
  half of a double is not finite, which tcc's folder checks, and one
  eighth of an 8 MiB range of stack addresses lies there; that reading
  fits the numbers but was not traced.
- Changing the first tcc's libc from pnut's to Mes's (tcc-first
  `1a3a95ab…` to `d9e97270…`) left tcc-boot0 at `c1696e57…`.  A libc's
  float parsing could reach boot0 through float literals, but this tcc,
  like tcc-mes, is built without `HAVE_FLOAT`, so `tccpp.c` compiles out
  its `strtod` and `strtold` calls; `strtof` (an `F` suffix) traps, and
  the replay ran to the end, so no trap was reached.
- tcc-mes is a different program by design: an x86_64 binary with Mes's
  libc compiled by the Forth compiler, not MesCC's i386 one.

## Inputs

`tinycc/SOURCES` and `MANIFEST.sha256` pin three archives under
`build-out/tinycc-inputs/`.  `tinycc/SOURCES` has no comments, because the
seed-built `sha256sum --check` reads it as it is:
- `tcc-0.9.26.tar.gz`: janneke's `tcc-0.9.26-1147-gee75a10c`, with the
  name, URL and sha256 of live-bootstrap's `steps/tcc-0.9.26/sources`;
- `mes-0.28.tar.gz`: GNU Mes 0.28, as `steps/mes-0.28/sources` pins it.
  Its headers and libc source are the libc compiled into the first tcc,
  and what the junction compiles;
- live-bootstrap at `a49273cb`: the simple-patches, simple-patch and
  checksum-transcriber, and the kaem text and checksums of the junction.

`tinycc/hex0-handoff.SOURCES` and `MANIFEST.sha256` pin a fourth,
builder-hex0 at `a2781242`, live-bootstrap's submodule commit, which only
the hex0 hand-off reads.  It has its own file so that the junction, which
checks `tinycc/SOURCES` whole, does not need it; the hand-off checks it
with the seed-built `sha256sum`.

GitHub generates the live-bootstrap and builder-hex0 archives from the
commit and does not promise their bytes stay the same.  If one changes,
the commit in its name is the identity of the source: compare `git
archive` of that commit with the new archive's contents before moving its
pin.

`python3 tools/fetch-archives.py build-out/tinycc-inputs/<name>` downloads
them.
