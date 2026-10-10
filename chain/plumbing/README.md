# Plumbing: the build tools, from the seed

The GCC chain (binutils, stage C, stage D; [CHAIN.md](CHAIN.md)) builds GCC
with no host compiler, but configure scripts and Makefiles still need a
shell, make, sed, awk, grep and the file utilities.  This directory builds
those tools from their pinned upstream tarballs with seed-cc, driven by
[kaem](../../vendor/mescc-tools/Kaem) scripts.  No host program runs: not a
shell, not a host compiler.  How these stages were developed is recorded in
seed-forth's [PLUMBING.md](https://github.com/delta9000/seed-forth/blob/0dd2b88/gcc-direct/PLUMBING.md).

## Running it

From the repository root, after `./seed/build.sh` and
`python3 tools/fetch-archives.py` (which puts the tarballs listed in
[SOURCES](SOURCES) in `build-out/plumbing-inputs/`):

```sh
./seed-forth < cc/driver/seed-cc-start.fth          # build-out/seed-cc/{seed-cc,seed-ar}
mkdir -p build-out/plumbing/bin
build-out/seed-cc/seed-cc -static vendor/mescc-tools/Kaem/kaem.c \
  vendor/mescc-tools/Kaem/variable.c vendor/mescc-tools/Kaem/kaem_globals.c \
  vendor/stage0-posix/mescc-tools-extra/M2libc/bootstrappable.c \
  -o build-out/plumbing/bin/kaem
build-out/plumbing/bin/kaem --verbose --strict --file chain/plumbing/stage1.kaem
build-out/plumbing/bin/kaem --verbose --strict --file chain/plumbing/stage2.kaem
```

On a 24-thread host stage 1 takes about 15 seconds and stage 2 about 35
(four parallel jobs), measured 2026-10-10.
Everything is written under `build-out/plumbing/`: sources unpack into
`src/`, programs install into `bin/`.

## Stage 1: [stage1.kaem](stage1.kaem)

1. seed-cc compiles stage0-posix's small tools: `mkdir`, `sha256sum`,
   `unbz2`, `ungz`, `untar`, `cp`, `chmod`, `rm`.
2. Every tarball is checked against [SOURCES](SOURCES).
3. GNU make 3.82 is built from an explicit file list with
   [make-3.82/config.h](make-3.82/config.h); no configure runs.

## Stage 2: [stage2.kaem](stage2.kaem)

Each package is unpacked by the stage0 tools, given its `config.h`, and built
by our make from `chain/plumbing/PKG/Makefile`:

| Package | Installed | Source changes |
|---|---|---|
| [sed 4.0.9](sed-4.0.9) | `sed` | none |
| [gzip 1.2.4](gzip-1.2.4) | `gzip`, `gunzip`, `zcat` | none |
| [patch 2.5.9](patch-2.5.9) | `patch` | none |
| [diffutils 2.7](diffutils-2.7) | `cmp`, `diff`, `diff3`, `sdiff` | none |
| [grep 2.4](grep-2.4) | `grep`, `egrep`, `fgrep` | none |
| [gawk 3.0.4](gawk-3.0.4) | `gawk`, `awk` | none |
| [tar 1.12](tar-1.12) | `tar` | none |
| [coreutils 5.0](coreutils-5.0) | 80 programs (below) | one patch |

The coreutils programs are `[` `basename` `cat` `chgrp` `chmod` `chown`
`chroot` `cksum` `comm` `cp` `csplit` `cut` `date` `dd` `dir` `dircolors`
`dirname` `du` `echo` `env` `expand` `expr` `factor` `false` `fmt` `fold`
`head` `hostname` `id` `install` `join` `kill` `link` `ln` `logname` `ls`
`md5sum` `mkdir` `mkfifo` `mknod` `mv` `nice` `nl` `od` `paste` `pathchk`
`pr` `printenv` `printf` `ptx` `pwd` `readlink` `rm` `rmdir` `seq`
`sha1sum` `shred` `sleep` `sort` `split` `stty` `sum` `sync` `tac` `tail`
`tee` `test` `touch` `tr` `true` `tsort` `tty` `uname` `unexpand` `uniq`
`unlink` `vdir` `wc` `whoami` `yes`. They replace the stage0 `cp`, `rm`,
`mkdir` and `chmod`. Not built: `df` and `stat` (no `statfs` or mount list),
`hostid`, `who`, `users`, `pinky`, `uptime` (no utmp), `su` (no crypt), and
the shell scripts `groups` and `nohup`.

### How the packages are configured

No configure script runs, because no shell exists yet. Each `config.h`
holds the answers configure would give for `chain/runtime/gcc-seed`: every
`HAVE_` that is defined is true of the runtime, and a feature that is left
undefined makes the package use its own portable code. Each file says why
any answer departs from what configure would print. Values that the
upstream Makefiles pass as quoted `-D` options (program and data paths) are
in `config.h` too, set as a `/usr` prefix gives them.

Our make runs a recipe line without a shell only when the line has no shell
metacharacters, so every Makefile here uses plain command lines: one
compile per object, `seed-ar` for archives, links with objects before
archives, and `cp` for the few headers configure would copy. Every compile
passes `-Werror=implicit-function-declaration`, which turns each call of an
undeclared function into an error instead of a silent LP64 truncation. Where
an upstream source calls a function without including its header (GNU libc
declares more than POSIX asks), `config.h` includes the real header and
says which file needed it.

### The coreutils patch

[canonicalize-realloc.diff](coreutils-5.0/canonicalize-realloc.diff) fixes an
upstream bug and is applied by the `patch` built earlier in stage 2; the file
carries its provenance and reason. `canonicalize.c` keeps a pointer into a
buffer across a `realloc` that may move it; glibc's in-place growth hides it,
the runtime's moving `realloc` exposes it (`readlink -f RELATIVE` crashed).
Later gnulib makes the same correction. (`human.c`, which computes its rare
floating fallback in `long double`, once needed a second patch; it builds
unchanged now that the compiler supports `long double`.)

## Known limits

- `diff3` and `sdiff` run `DIFF_PROGRAM`, `/usr/bin/diff`, as a `/usr`
  build does; until these tools are installed there they use whatever diff
  the host has at that path.
- Upstream `getline.h` in coreutils declares `int getline`, while the
  runtime's returns `ssize_t`; coreutils calls it only on lines shorter than
  2 GiB.

## Verification

The host is used only as an oracle: the same upstream versions built by host
GCC during discovery, and host GNU tools where versions agree.

| Tool | Result |
|---|---|
| sed | 31 of 35 scripts identical to host GNU sed 4.9; the 4 others are version differences (`-E`, message wording) and `sed -f`, which failed then because the runtime's `fopen` rejected mode `"rt"` (fixed since; the stage-2 cases include `sed -f`) |
| grep | 49/49 cases identical to grep 2.4 built by GCC |
| gawk | 63/64 cases identical to gawk 3.0.4 built by GCC (the one difference is `017`, which ours reads as 17 like mawk; the oracle prints 0); the upstream `bigtest` suite passes except the `/dev/fd` test it marks as allowed to fail |
| coreutils | 376/376 differential cases identical to coreutils 5.0 built by GCC |
| gzip | output byte-identical to gzip 1.2.4 built by GCC at levels 1, 6, 9; decompresses every input tarball to host gzip's bytes; `-l`, `-t`, mode and time preservation, `-r` identical |
| tar | lists every input tarball as tar 1.12 built by GCC does; extracts them to host tar's trees (except `patch-2.5.9`'s setgid directories, which tar 1.12 keeps, as the oracle does); archives it creates are byte-identical to the oracle's; `-z`, `-r`, `--delete`, `-d` work |
| patch | 20-case transcript identical to patch 2.5.9 built by GCC |
| diffutils | 50-case transcript (`diff` formats and options, `cmp`, `diff3`, `sdiff`) identical to diffutils 2.7 built by GCC |

These comparisons were made in seed-forth, whose
[tests/plumbing/stage2-check.sh](https://github.com/delta9000/seed-forth/blob/0dd2b88/tests/plumbing/stage2-check.sh)
repeats them: it builds stages 1 and 2 from a clean `build-out/plumbing`,
requires every `execve` to be kaem, seed-cc/seed-ar, the seed they run, or
a program the stages built, then runs the fixed cases in
[tests/plumbing/stage2-cases.sh](https://github.com/delta9000/seed-forth/blob/0dd2b88/tests/plumbing/stage2-cases.sh)
with `PATH` holding only `build-out/plumbing/bin`.  Those scripts were not
carried over.  Here, `chain/plumbing-root.sh` runs these stages in a root
whose only starting executable is `hex0-seed` and traces every `execve`
([results/host-2026-10-08/](../../results/host-2026-10-08/)).

## Parser generators without host plumbing

`lexers.kaem` builds oyacc 6.6, ordinary Heirloom lex 070527 and its
five-member `libl.a`, then flex 2.5.11. The stage runs only project-built
kaem, seed-cc, seed-ar, make 3.82 and the stage-1 file tools, plus the
seed-cc-built [lexer-prepare.c](lexer-prepare.c). Python is used only for
reference builds and verification, outside the native stage.

From the repository root:

```sh
./seed-forth < cc/driver/seed-cc-start.fth
mkdir -p build-out/plumbing/bin
build-out/seed-cc/seed-cc -static vendor/mescc-tools/Kaem/kaem.c vendor/mescc-tools/Kaem/variable.c vendor/mescc-tools/Kaem/kaem_globals.c vendor/stage0-posix/mescc-tools-extra/M2libc/bootstrappable.c -o build-out/plumbing/bin/kaem
build-out/plumbing/bin/kaem --verbose --strict --file chain/plumbing/stage1.kaem
build-out/plumbing/bin/kaem --verbose --strict --file chain/plumbing/lexers.kaem
```

The initial `mkdir` above prepares the kaem output directory; after stage 1,
all stage commands use built tools.  `tools/fetch-archives.py` puts the
stage-1 archives in `build-out/plumbing-inputs/` and the three lexer
archives in `build-out/lexer-inputs/archives/`.
[lexers.SOURCES](lexers.SOURCES) pins the exact archives and repository
reference files from [sources.json](../gcc-direct/lexer-inputs/sources.json).
The native stage uses the repository's pinned reference files directly;
seed-forth's Python reference recipe needed a copy of `recipe-reference/`
in its inputs tree.

Outputs are `build-out/plumbing/bin/{oyacc,lex,flex}`. Ordinary lex form
files remain in `build-out/plumbing/src/heirloom-devtools-070527/lex/`;
`lexer-prepare lexconfig` records that absolute path in a generated header,
and `main-unit.c` includes that header before unchanged upstream `main.c`.
Retain that source directory when using lex. The stage requires fresh
`oyacc-6.6`, `heirloom-devtools-070527` and
`flex-d160f0247ba1611aa59d28f027d6292ba24abb50` directories under
`build-out/plumbing/src/`; it fails if any already exists. For a rebuild,
remove only those three scratch directories first. Other plumbing stages
and installed tools are independent.

### Source preparation and configuration

The preparation reproduces seed-forth's Python reference,
[lexers.py](https://github.com/delta9000/seed-forth/blob/0dd2b88/gcc-direct/lexers.py) and
[prepare-lexer-sources.py](https://github.com/delta9000/seed-forth/blob/0dd2b88/gcc-direct/prepare-lexer-sources.py): unpack
pinned originals, apply unchanged `scan_l.patch` then `yyin.patch`, copy
unchanged `scan.lex.l`, remove shipped `parse.c`, `parse.h`, `scan.c` and
`skel.c`, then regenerate the skeleton from original `flex.skl`. No shipped
parser/scanner C becomes a build input. Provenance and licenses for the
patches and restricted temporary scanner remain in
[PROVENANCE.md](../gcc-direct/lexer-inputs/PROVENANCE.md).

The built `lexer-prepare patch` applies each full unified hunk at its unique,
exact context, allowing line offsets (the first historical patch needs -1)
but no fuzz. It consumes the original patch payloads, checks hunk counts,
and rejects missing or ambiguous context. `skeleton` emits the same header,
line escaping and terminator as `mkskel.sh`. `ascii` requires exactly one
UTF-8 U+0160 and transliterates it to S in the attribution comment, then
checks that all bytes are ASCII. `scanner` replaces every `yylex` with
`flexscan`, matching Python's byte replacement. The Heirloom intermediate
is retained before flex-tmp regenerates original patched `scan.l`.
[lexers.PREPARED](lexers.PREPARED) checks patched sources and skeleton before
flex compilation; [lexers.GENERATED](lexers.GENERATED) checks all generated
parser/scanner C, parser header, ASCII input and `libl.a` at the end.

The per-tool Makefiles contain simple direct commands, with objects before
archives. Fixed configuration reflects the original Python recipe's probes
with this compiler/runtime: oyacc enables only `HAVE_PROGNAME` and empty
`__dead`; its attribute, asprintf, pledge, reallocarray, strlcpy and `-w`
probes fail. Flex enables string.h, sys/types.h, unistd.h, stdbool.h and
`STDC_HEADERS`; malloc.h fails. Its config also supplies `VERSION "2.5.11"`.
Heirloom uses `unix=1`, as in the original recipe. GNU make 3.82 must retain
its default `SHELL`: changing it disables the direct-command fast path.
There are no shell metacharacters in expanded recipe lines.

### Recorded equivalence (2026-10-06, in seed-forth)

The native stage and seed-forth's Python reference recipe were both run and
compared with seed-forth's `tests/gcc/plumbing-lexers-check.py`; the Python
recipe and the check stayed in seed-forth.

The comparison checks prepared sources, all six generated C intermediates
(including `skel.c`), `parse.h`, ASCII input, `libl.a`, and fixed configuration
against the actual reference probe results. All bytes agree; the ordinary
five-member archive retains SHA-256
`d5a855998abc0a3bbb84a714b49d0dbf1e507910f528711b55aca16d07694212`.
The built preparation tool also matched the original patch/skeleton outputs
and rejected incorrect patch context in a targeted check.

Ten consumer cases passed, comparing generated C byte for byte as well as
stdout/stderr; oyacc's header and verbose report also match. GCC's
`c-parse.y` is prepared from `gcc/c-parse.in` using the original Makefile's
warning line and sed rules, removing ObjC blocks and C markers. The
`c-parse.in` SHA-256 is
`3bd54640653c969ea5b6673fbcf31895f94dcbf445676c913c13070bdcb5ffbb`.
Scanners use GCC 4.0.4, binutils 2.30, and the prepared flex inputs. Each pair
runs sequentially in the same directory with identical input/output names,
so `#line` filename spelling agrees. Generated C SHA-256 values:

| Consumer | SHA-256 (both builds) |
|---|---|
| gcc-c-parse | `f8e1b2f552778b15e9788614d2922dd85f5f44d0a9673912661f1bdfe6730e08` |
| gcc-gengtype | `7d88ec03bd79716e6cd9e2ea25d43e18a6e003cc3d66eaf1d98ef55679d127cf` |
| binutils-arlex | `418eff5841f2d10d9c4f05f04cebd9250e0d98039c436166abb3a1565f958ef3` |
| binutils-deflex | `1f6ab5fcc0c0aeb2d740eb2f524576eb23cc8fce5cb8f70fc0be111573d253a4` |
| binutils-syslex | `50cf8173e7f4e605805010c21d5fdbe6e7f7a57afba1772857d0c8768ba45814` |
| binutils-itbl-lex | `2a7cb89af15f7dd9e5dbff67095e8689a847998867b6ecebb46970976d1e7ea6` |
| binutils-bfin-lex | `c5601a293420671ba60dd826bd8f426ca29ebaac62443a42e15b349d0c616b17` |
| binutils-ldlex | `a66acb9cc4a829e8a21c058af8e588e1c560a66b7d496a3ed35027e732811419` |
| flex-scanner | `4cb3e1ce267d106449d734cec1a48d2b4213522f1f781c2591a918e028bd2a53` |
| heirloom-bootstrap-scanner | `48a6e083b06fcdd5c57c97c6be9ed02e7d3f5a72d6023c7b0d50bc1a9ec7e52a` |

A fresh complete stage also passed seed-forth's execution audit
(`tests/gcc/plumbing-lexers-audit.py`, which denies executable access
outside `seed-forth`, `build-out/seed-cc/`, `build-out/plumbing/` and
`/tmp`), including every prepared and generated hash check and `flex -V`
reporting 2.5.11.  Wide/EUC lex variants are outside this stage's evidence.

## Bash: [bash.kaem](bash.kaem)

After the parser generators, `bash.kaem` builds GNU bash 2.05b with the
stage-1 make: the parser is regenerated from `parse.y` by the chain's
oyacc (the shipped `y.tab.c` is deleted), one reviewed patch
(`bash-2.05b/missing-defines.patch`) is applied by the stage-2 `patch`, and
configure's answers are in [bash-2.05b/config.h](bash-2.05b/config.h)
([NOTES.md](bash-2.05b/NOTES.md) gives the reasons).  It installs `bash`
and `sh` into `build-out/plumbing/bin`, and the GCC chain
([CHAIN.md](CHAIN.md)) runs under that bash:

```sh
build-out/plumbing/bin/kaem --verbose --strict --file chain/plumbing/bash.kaem
```

`chain/plumbing/chain.kaem` runs stage 1, stage 2, the lexers and bash in
that order, then the GCC chain.
