# tinycc/ -- from the seed to live-bootstrap's tcc

The seed compiles one C compiler: janneke's TinyCC fork
`tcc-0.9.26-1147-gee75a10c`, with GNU Mes 0.28's C library in the same
program, as an i386 static ELF.  It then hands over to live-bootstrap's
`steps/tcc-0.9.26`, where that compiler stands in for `tcc-mes`, the copy
MesCC builds, and live-bootstrap's own script runs on to the tcc it
publishes.  All of it runs on builder-hex0, live-bootstrap's kernel, in
one boot from a disk with no program on it.

Other routes this repository used to hold (an x86-64 seed, the kernels K0
and K1, the hand-off from K0 to builder-hex0, the GCC chain) are at tag
`experiments-2026-11-21`; the top-level README says how to get them.

## The first tcc

`tinycc/build-first-tcc-i386.sh` writes `build-out/tinycc/tcc-first-i386`,
975,624 bytes, sha256
`92d1143823045f9324c2d4b34c64dfc11bc994c958b92bfbd80a99de371e4d2d`.  The
pin is in `tests/pins/tinycc.sha256`.  The boot builds the same bytes as
`/usr/bin/tcc-mes`.

One run of the seed compiles it:

    seed-forth-i386 forth/i386/010-lib.fth tinycc/i386-seed/tcc-first.fth \
        OUT SOURCE INCLUDE INCLUDE-LINUX

The job (`i386-seed/tcc-first.fth`) loads the compiler
(`forth/i386/layers.fth`), takes its four paths from the command line and
loads the driver, `tcc-compile-i386.fth`.  The compiler writes a complete
static ELF directly: no object files, assembler or linker.  The compiled
program has ILP32 types, float and double as 8-byte bit patterns with no
arithmetic, and a private calling convention with every argument in an
8-byte stack slot (`cc/README.md`).

The source it compiles:
- the fork from live-bootstrap's tarball, with what `pass1.kaem` does to it
  before MesCC runs: two `tcctools.c` simple-patches and an empty
  `config.h`;
- no patch of ours;
- Mes 0.28's libc in the same translation unit: `mes-libc.c` includes the
  files live-bootstrap's `pass1.kaem` compiles into tcc-mes's `libc.a`
  (its `unified-libc.c` list), in that order, without seven.  Four are
  inline assembly (`syscall.c`, `_exit.c`, `_write.c`, `setjmp.c`); two
  are the double conversions under `strtod`, `atof` and printf's `%f`
  (`mes/abtod.c`, `mes/dtoab.c`), and `math/ceil.c` is double arithmetic
  that nothing calls.  As `steps/mes-0.28` does on x86, `include/arch/`
  gets copies of `include/linux/x86`'s three headers, and
  `include/mes/config.h` is empty.  `__SIZEOF_LONG_LONG__` stays
  undefined, as MesCC leaves it, so Mes's `struct stat` is the old i386
  one the kernel fills;
- `mes-libc-native-i386.c`, ours, first in the unit: the system-call layer
  (`__sys_call*`, `_sys_call*` with Mes's errno handling, `_exit`,
  `_write`) on `__native_syscall`, the one primitive
  `cc/119-cc-runtime.fth` emits; a `setjmp` that returns 0 and a `longjmp`
  that exits 125 (tcc only longjmps after printing an error); `abtod` and
  `dtoab` that exit 125 rather than return wrong bits; and crt1's work, a
  `main` that sets `environ` and stdio as `__init_io` does before calling
  the program's, renamed.  It replaces Mes's `jmp_buf`, an array of one
  struct, which the compiler cannot pass as an argument, and Mes's
  `stdarg.h`, because every argument is in an 8-byte slot while a pointer
  is 4 bytes.  It passes to the kernel only the calls builder-hex0 has
  (exit, fork, read, write, open, close, waitpid, execve, chdir, lseek,
  access, mkdir, brk, getcwd); any other gets builder-hex0's answer, 0,
  without a system call.  tcc makes three such calls: `unlink` before it
  writes an output file, and `stat` and `unlink` in Mes's `remove`, after
  `tcc -ar` has copied its temporary file.  So on Linux, as on
  builder-hex0, the first tcc leaves `libc.a.tmp`, `libtcc1.a.tmp` and
  `libgetopt.a.tmp` behind;
- tcc-mes's defines for x86 (`direct-input-i386.c`), so the compiler looks
  for headers and libraries where tcc-mes does;
- the entry stub the compiler emits (`cc/117-cc-native-program.fth`)
  raises the break to the end of the bss if it is below it, and zeroes
  1 MiB of stack below esp.  The junction passes with `ulimit -s 48`, so
  the first tcc uses under 48 KiB of stack.

## Source preparation

`tinycc/build-tools-i386.sh` (run by `build-first-tcc-i386.sh`) builds the
programs that check, unpack and patch the sources, and kaem, with no host
compiler.  The seed compiles each as it compiles the first tcc, against
stage0-posix's M2libc (`vendor/stage0-posix/M2libc`, in the repository),
with the job `i386-seed/tool.fth` and the driver `tool-compile.fth`:

| program | source |
|---|---|
| `sha256sum` `catm` `mkdir` `cp` `chmod` `rm` `match` | stage0-posix `mescc-tools-extra`, unchanged |
| `ungz` | `mescc-tools-extra`, with `tools/ungz-unsigned-bytes` |
| `untar` | `mescc-tools-extra`, with `tools/untar-ustar-prefix` |
| `simple-patch` | live-bootstrap `steps/simple-patch-1.0/src`, unchanged |
| `checksum-transcriber` | live-bootstrap `steps/checksum-transcriber-1.0/src`, unchanged |
| `kaem` | `vendor/mescc-tools/Kaem`, its three files, unchanged |

They are in `build-out/tinycc/bin-i386/` and `build-out/tinycc/kaem-i386`
(99,008 bytes), and their sha256 are pinned in `tests/pins/tinycc.sha256`.
The script also builds `build-out/tinycc/bin-boot-i386/`, `ungz` and
`untar` from the sources as published, which are used once.

M2libc is compiled in its own M2 mode, as M2-Mesoplanet builds these
tools for stage0-posix: `__M2__` makes its headers include its `.c`
files, so each tool is one translation unit.  `m2libc-native-i386.c`,
ours, goes ahead of the tool's source and stands in for what M2-Planet
and M2libc's M1 assembly provide:
- `x86/linux/unistd.c`, `fcntl.c` and `sys/stat.c`: it defines their
  include guards, their constants, and in C the thirteen system calls the
  tools reach, each on `__native_syscall`, plus `getcwd` and `_exit`;
- `libc-full.M1`'s `_start` and `exit`: a `main` that sets `_envp` and
  calls `__init_malloc` and `__init_io` before the tool's `main` (renamed),
  and an `exit` that flushes through `__kill_io`;
- M2-Planet's built-in types (`SCM`, `FUNCTION`, the fixed-width
  integers), and `va_list` for eight-byte stack slots in place of the
  `__va_*` builtins M2libc's `stdarg.h` names;
- `stdlib.c` and `string.c` both define `memset`, which M2-Planet accepts
  and this compiler does not (error 211); `stdlib.c`'s, called only by its
  `calloc`, is renamed.

kaem starts each command with `fork`, `execve` and `waitpid`;
`m2libc-kaem-i386.c` has those three, with an `execve` that asks `access`
first, and goes ahead of kaem's files only.  kaem reads exit statuses on
builder-hex0 as on Linux: builder-hex0 stores the code unmasked and kaem
takes bits 8 to 15, which are the low 8 bits Linux keeps (300 is 44 on
both, 256 is 0 on both).

The driver writes each program with mode 0755, so nothing needs `chmod`
before `chmod` is built.

The two changes of ours are simple-patch before/after pairs:
- `ungz-unsigned-bytes`: `stored()` reads a stored block's length bytes as
  plain `char` and compares them with `~len & 0xff`.  Where plain `char`
  is signed, a byte of 0x80 or more fails ("puff() failed with return
  code -2").  `bits()` already masks with `0xFF`; the patch masks these
  four reads the same way.  The three archives of this route have no such
  block (stock ungz gives the same tars).
- `untar-ustar-prefix`: untar reads only the 100-byte name field.  GitHub's
  archive of live-bootstrap stores 200 long paths as ustar prefix plus
  name, among them `steps/tcc-0.9.26/simple-patches/*`.  Stock untar writes
  those to the bare name in the current directory, and tcc-0.9.27's files
  of the same names then overwrite them.  The patch joins prefix and name.

simple-patch is in the live-bootstrap archive, so stock ungz and untar
unpack that archive first; its `simple-patch.c` path fits the name field.
The patched tools then unpack it again into `build-out/tinycc/lb/`.

The host runs the commands the boot runs, in the same order
(`i386-one-boot-disk.py` writes them into the boot's `/kaem.run`).  Host
programs left in the two build scripts: bash runs them; `rm -rf` and
`mkdir -p` clear and make build-out directories; `wc`, `sha256sum`, `sed`
and `cut` print the size and compare the programs with their pins.  None
of them reads or writes a source file.  `tools/fetch-archives.py`
(python3) downloads the archives.

## The junction, on the host

`tests/tinycc/junction-check.sh` sets up a bwrap root laid out as
live-bootstrap's.  It runs their kaem text: the mes-0.28 header install,
then `steps/tcc-0.9.26/pass1.kaem` with the two MesCC commands replaced by
copying the first tcc to `tcc-mes` (`tinycc/lb-replay.sh`).  It then
compares the result with their `tcc-0.9.26.x86.checksums`:

| file | live-bootstrap (MesCC) | this route |
|---|---|---|
| `/usr/bin/tcc-mes` | `2b15c85f…` | `92d11438…` (pinned) |
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
- Every program runs on the host's Linux kernel through its 32-bit
  support.  The one boot below runs them on builder-hex0.
- Host bash stands in for kaem.  The other commands of the kaem text are
  the programs live-bootstrap uses, built by the seed against M2libc
  (above); two of them carry a patch of ours.
- MesCC itself was not run.  Its column above is live-bootstrap's
  published file.

`tests/tinycc/junction-check.sh FIRST_TCC` runs the same replay from
another first compiler.  It expects that compiler to be configured like
tcc-mes: a first tcc built with the boot stages' full feature set
(`HAVE_FLOAT`, `HAVE_BITFIELD`, `HAVE_LONG_LONG`) gives tcc-boot1
`b9dce87d…` already, so the boot1 line does not match although `tcc` and
the libraries do.

The checks around it (`./check-all.sh` steps 08 to 12):
- `tests/tinycc/i386-syscall-check.sh`: under `strace -f`, the first tcc
  and the tools make only builder-hex0's calls (rm's `unlink`, chmod's
  `chmod` and untar's `symlink` apart), never lower the break, never
  write past the end of a file and only grow the newest file.
- `tests/tinycc/i386-standin-check.sh`: gcc `-m32` compiles the same unit
  with Mes's own i386 assembly files; every file the two first compilers
  write in the replay (the crt files, `unified-libc.o`, `libc.a`,
  `libtcc1`, getopt and tcc-boot0) has the same bytes.  The stand-in is
  not deterministic; see "What does not reproduce".
- `tests/tinycc/i386-seed-check.sh`: the two build scripts with every
  seed run under strace: only `brk`, `open`, `read`, `write`, `close` and
  `exit`, and the pinned bytes.
- `tests/tinycc/i386-kaem-check.sh`: kaem's own eighteen test scripts on
  Linux; a status of 1 stops a script; a missing command is refused by
  `access` with no `execve`.
- `tests/cc/i386/run-corpus.sh`: small C programs compiled by the Forth
  compiler and by gcc `-m32` print the same lines.  They cover what the
  pins cannot see: the high halves of `long long` values.
- `tests/cc/gates/run-gates.sh`: programs that must compile and exit with
  a given status, and programs the compiler must refuse with a given
  error code and line.

## One boot on builder-hex0

`tests/tinycc/i386-one-boot-check.sh` (`./check-all.sh` step 15) goes
from two hex0 sources to live-bootstrap's tcc-0.9.26 on builder-hex0 in
one QEMU boot of 24 s with KVM.  No program
is on the disk: everything that runs is assembled or compiled in the
boot.  `forth/i386/CONTRACT.md`, section 7, is the design.

**The disk.**  `tinycc/i386-one-boot-disk.py` writes it in the layout of
live-bootstrap's `lib/generator.py`: builder-hex0's stage 1 (assembled by
hex0-seed), its stage-2 hex0 source, zeros to sector 175, then 80
directories and 186 files:
- `seed/i386/000-seed.hex0` and stage0-posix's
  `vendor/stage0-posix/x86/kaem-minimal.hex0`;
- the Forth the seed reads: `forth/i386/`, the compiler layers of
  `forth/i386/layers.fth`, the two drivers and the two jobs;
- the C it compiles: M2libc, the nine tool sources of
  `mescc-tools-extra`, `vendor/mescc-tools/Kaem`, our two system-call
  layers and the two tool patches, and for the first tcc
  `direct-input-i386.c`, `mes-libc.c` and `mes-libc-native-i386.c`;
  `hex0-export.c`;
- `/external/distfiles/` with the three archives of `tinycc/SOURCES`, and
  that file with their paths in the boot;
- two scripts, `/boot/seed.kaem` and `/kaem.run`.

Every repository file is at its repository path under `/`.  Three
commands follow for builder-hex0's shell:

    hex0 /seed/i386/000-seed.hex0 /seed-forth-i386
    hex0 /vendor/stage0-posix/x86/kaem-minimal.hex0 /kaem-optional-seed
    /kaem-optional-seed /boot/seed.kaem

**The boot.**
1. The built-in `hex0` assembles the seed and kaem-optional-seed.
2. kaem-optional-seed runs `/boot/seed.kaem`, two lines of complete
   paths: the seed compiles kaem (`/x86/bin/kaem`, eight arguments), and
   that kaem runs `/kaem.run`.
3. `/kaem.run` starts with `steps/env`'s and `seed.kaem`'s variables,
   then ours, all before the first `cd`: builder-hex0 cannot change
   directory back to `/`, and the Forth files name each other relative to
   it.  The seed compiles the tools in `tinycc/build-tools-i386.sh`'s order:
   seven from the disk, and stock `ungz` and `untar`; `sha256sum -c` of
   the three archives; the stock pair unpacks live-bootstrap's archive;
   `simple-patch` from it; the patched `ungz` and `untar`, which unpack
   the archive again; `checksum-transcriber`.  The tools then prepare the
   first tcc's sources in `/` with `tinycc/build-first-tcc-i386.sh`'s
   commands, and the seed compiles `/usr/bin/tcc-mes`.
4. live-bootstrap's text, the lines `tinycc/lb-replay.sh` runs on the
   host, cut at the same markers: of `steps/mes-0.28/pass1.kaem` the
   unpacking and the header install; `steps/tcc-0.9.26/pass1.kaem` from
   "# Vars" to "# Checksums", without the two MesCC commands and the `cp`
   and `chmod` that install their tcc-mes: the archive check, `ungz`,
   `untar`, the two `simple-patch` lines, then tcc-mes, tcc-boot0,
   tcc-boot1 and tcc-boot2.  builder-hex0 cannot rename a directory, and
   tcc's `-g` records the working directory, so this build is at
   live-bootstrap's path and unpacks both archives a second time.
5. Ours, before "# Install": `cp` of the six library files tcc-mes made to
   `/first`, because the later stages overwrite them, and `tcc-mes
   -static` of `hex0-export`.  Ours, last: `hex0-export /dev/hda` with the
   33 files below.

The host reads the drive (`tinycc/hex0-records.py`) and hashes:

| file | expected | the boot |
|---|---|---|
| `/seed-forth-i386` | `b5f70ffb…`, hex0-seed's assembly of the same source on the host | same |
| `/kaem-optional-seed` | `545f8953…`, the binary stage0-posix publishes | same |
| `/x86/bin/kaem` | `d87baff1…` (pinned: the seed's build on Linux) | same |
| `/x86/bin/` the eleven tools, `/boot/ungz`, `/boot/untar` | pinned: the seed's builds on Linux | same |
| `/usr/bin/tcc-mes` | `92d11438…` (pinned; MesCC's is `2b15c85f…`) | same |
| `/usr/bin/tcc-boot0` | `c1696e57…` (pinned; MesCC's is `ea464b2f…`) | same |
| `/usr/bin/tcc-boot1` | `d9116def…` (live-bootstrap) | same |
| `/usr/bin/tcc` | `b9dce87d…` (live-bootstrap) | same |
| `/usr/lib/mes/libc.a` | `a6172e52…` (live-bootstrap) | same |
| `/usr/lib/mes/libgetopt.a`, `crt1.o`, `crti.o`, `crtn.o`, `tcc/libtcc1.a` | live-bootstrap's | same |
| `/first/libc.a` | `84d12efe…` (pinned, `tinycc/first`) | same |
| `/first/crt1.o`, `crti.o`, `crtn.o`, `libtcc1.a`, `libgetopt.a` | pinned, `tinycc/first` | same |
| `/usr/bin/hex0-export` | `498dea62…` (pinned, `tinycc/first`) | same |

**What it shows.**  From builder-hex0's stage 1 and text, the route
reaches live-bootstrap's published `tcc` without MesCC, M2-Planet or any
binary but stage 1.  The seed on builder-hex0 compiles the bytes it
compiles on Linux, for fifteen programs.  The built-in
`hex0` and the host's hex0-seed assemble the seed alike.

**What the host still does.**  It cuts `/kaem.run` from the pinned kaem
files (python3), reading live-bootstrap's tree as the seed-built tools of
`tinycc/build-tools-i386.sh` unpacked it; checks and unpacks builder-hex0's
archive with those tools; runs hex0-seed for stage 1 and for the
reference seed; writes the disk; starts QEMU; reads the drive and
compares.  The seed's builds on Linux are the pins.

**What it does not show.**
- No program in the boot has more than 0x20000 bytes of bss (the first
  tcc has 80,592), so builder-hex0 starts each with its break above the
  bss and the entry stub's brk is never made.  The seed's own break is
  raised by the seed.
- A script that names a missing program.  The full kaem's guard is
  checked alone (`tests/tinycc/i386-kaem-boot-check.sh`);
  kaem-optional-seed has none, so a wrong path in `/boot/seed.kaem` stops
  the machine.
- The hashes are taken on the host, from the exported files.

## The seed and the Forth under the compiler

Two documents specify what runs on builder-hex0 below the C compiler:

- `seed/i386/SPEC.md`: the seed, an i386 Forth with 64-bit cells that
  builder-hex0's built-in `hex0` assembles in the boot.  It takes its
  Forth source by file name, because descriptor 0 there is the disk
  stream.  `seed/i386/000-seed.hex0` is 1,191 bytes, written from the
  specification alone.  Its checks: `tests/seed/i386/asm-check.py` (its
  bytes equal GNU as and llvm-mc on its comments),
  `tests/seed/i386/test.sh` (the 76 cases of SPEC 13.1, and all of them
  again under strace), and `tests/seed/i386/boot-check.sh` (builder-hex0
  assembles the source in a boot, the seed runs a Forth file there, and
  the binary it built equals the host's).
- `forth/i386/CONTRACT.md`: what is laid down on top of it: the machine
  code the Forth library and `020-cc-arena.fth` lay for the Forth system
  itself (as opposed to `cc/090-cc-emit.fth`, which is the code of the
  compiled C program), `include`, allocation by `brk`, the boot's disk
  and scripts, and kaem built by the seed.  It was written when an x86-64
  seed and library stood beside these files and describes each i386 file
  against its x86-64 original; those originals are at tag
  `experiments-2026-11-21`.

Every run is `seed-forth-i386 forth/i386/010-lib.fth JOB [ARG ...]`.

Checks: `tests/forth/i386/asm-check.py` (the 94 byte lines of
`forth/i386/` equal GNU as and llvm-mc on their comments),
`tests/forth/i386/high-halves-check.sh` (153 cases on cells whose two
halves both matter, each primitive interpreted and compiled in place),
`tests/forth/i386/host-words-check.sh` (`include` and `brk-alloc` where no
compile takes them), and `tests/tinycc/i386-kaem-boot-check.sh` (on
builder-hex0, kaem under kaem runs commands that exit 0, stops on a
status of 1, reports an exit of 300 as 44, and a missing command leaves
the machine running).

## What does not reproduce

- tcc-boot0 is `c1696e57…`, as a gcc `-m32` build of the same first tcc
  gives (when it gives one answer; next item).  MesCC's tcc-mes gives
  `ea464b2f…`.
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
- tcc-mes is a different program by design: tcc with Mes's libc compiled
  by the Forth compiler, not by MesCC.  A libc's float parsing could reach
  tcc-boot0 through float literals, but this tcc, like MesCC's tcc-mes, is
  built without `HAVE_FLOAT`, so `tccpp.c` compiles out its `strtod` and
  `strtold` calls; `strtof` (an `F` suffix) traps, and the replay runs to
  the end, so no trap is reached.

## Inputs

`tinycc/SOURCES` pins three archives under `build-out/tinycc-inputs/`.  It
has no comments, because the seed-built `sha256sum --check` reads it as it
is:
- `tcc-0.9.26.tar.gz`: janneke's `tcc-0.9.26-1147-gee75a10c`, with the
  name, URL and sha256 of live-bootstrap's `steps/tcc-0.9.26/sources`;
- `mes-0.28.tar.gz`: GNU Mes 0.28, as `steps/mes-0.28/sources` pins it.
  Its headers and libc source are the libc compiled into the first tcc,
  and what the junction compiles;
- live-bootstrap at `a49273cb`: the simple-patches, simple-patch and
  checksum-transcriber, and the kaem text and checksums of the junction.

`tinycc/builder-hex0.SOURCES` pins a fourth, builder-hex0 at `a2781242`,
live-bootstrap's submodule commit: the kernel of the boots.  It has its
own file because the boot checks `tinycc/SOURCES` whole and builder-hex0's
archive is not on its disk; the checks that boot verify it with the
seed-built `sha256sum`.

GitHub generates the live-bootstrap and builder-hex0 archives from the
commit and does not promise their bytes stay the same.  If one changes,
the commit in its name is the identity of the source: compare `git
archive` of that commit with the new archive's contents before moving its
pin.

`python3 tools/fetch-archives.py` downloads all four.
