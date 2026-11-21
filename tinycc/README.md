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
  support, not under K0 or K1.  K1 loads only x86_64 ELF.
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

## What does not reproduce

- tcc-boot0 is `c1696e57…`, as the stand-ins that the junction study built
  with gcc, tcc 0.9.27 and seed-cc, using the same defines, gave.  MesCC's
  tcc-mes gives `ea464b2f…`.  Every first compiler other than MesCC now
  agrees from tcc-boot0 on.  Before the first tcc had a real `getcwd`,
  it recorded `/` as the `-g` directory, giving `4e3e525a…`.
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

GitHub generates the live-bootstrap archive from the commit and does not
promise its bytes stay the same.  If it changes, the commit in its name is
the identity of the source: compare `git archive` of that commit with the
new archive's contents before moving its pin.

`python3 tools/fetch-archives.py build-out/tinycc-inputs/<name>` downloads
them.
