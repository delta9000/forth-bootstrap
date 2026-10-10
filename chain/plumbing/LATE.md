# The late tools, built by the stage-D GCC

[chain/gcc-direct/late-tools.sh](../gcc-direct/late-tools.sh) builds the
modern userland the rest of the route needs: 17 packages, with nothing
captured from a host.  Each package's own `./configure` runs under the
plumbing bash 2.05b, its Makefile under the plumbing make 3.82, and its C
goes through the stage-D GCC 4.0.4 with the stage-C musl 1.1.24 and
binutils 2.30.  The packages and pins are in [late.SOURCES](late.SOURCES):

gzip 1.13, bash 5.2.37, tar 1.35, sed 4.9, grep 3.11, gawk 5.3.1,
coreutils 9.5, patch 2.7.6, xz 5.6.3, make 4.4.1, bzip2 1.0.8, diffutils
3.10, findutils 4.10.0, m4 1.4.19, bison 3.8.2, flex 2.6.4, bc 1.07.1.

Two patches apply: `chain/patches/late/bc-1.07.1/01-fix-libmath-sed.diff`
(the chain has no `ed`) and
`chain/patches/late/diffutils-3.10/01-unparenthesize-ifdef-formats.diff`
(drops the parentheses around a string initializer, which leaves the
string the same and lets tcc compile it too).  Under K1,
[chain/ladder/stage10-direct.sh](../ladder/stage10-direct.sh) then installs
the late tools as `/usr`, with bash 5.2 as `/bin/sh`, for gcc64's climb.

## Running it

After [chain/gcc-direct/chain.sh](../gcc-direct/chain.sh), with the 17 archives
in `build-out/distfiles` (`tools/fetch-archives.py` puts them there):

```sh
build-out/plumbing/bin/bash chain/gcc-direct/late-tools.sh -j 8     # into build-out/late
```

Run this way on the host, `#!/bin/sh` scripts and `system()` still reach the
host's `/bin/sh`, and config.guess runs `/usr/bin/uname` by absolute path.
Under K1 (`kernel/k1/run-chain.sh --direct-linux`, through
`kernel/k1/direct-full.sh`) there is no host: `/bin` is the plumbing tools,
and the same script builds the packages as root, which tar and coreutils
accept only with `FORCE_UNSAFE_CONFIGURE=1`, which late-tools.sh sets.

## Result (2026-10-08, under K1)

All 17 packages built in 631 s; the report, with each package's configure
and make times and the sha256 of all 159 installed programs, is
[results/k1-2026-10-08/late-tools-report.txt](../../results/k1-2026-10-08/late-tools-report.txt).
An earlier, independent run produced the same hashes ([HISTORY.md](../../HISTORY.md)).

## A traced host run and the test suites (2026-10-07)

late-tools.sh was also run on the host in a copy of a finished
`chain/plumbing-root.sh` root (one that started with `hex0-seed` as its
only executable), through bwrap under `strace -f -e trace=execve`, and
each package's `make -k check` was run there.  The wrapper and check
scripts used for that run are not kept in this repository.

All 17 packages built in 409 s (configure is most of it).  76,974
successful `execve` calls; one was the host's `bwrap`, the rest programs the
chain wrote (the plumbing tools, the stage-D GCC, the stage-C binutils,
configure's `conftest`s and the packages' own build programs).  The 262
failed lookups were config.guess probing other systems' `uname` variants,
the bc build running its `fix-libmath_h` (no `#!` line, so bash runs it),
and packages' tests of their own uninstalled programs.  Every installed
program was a static x86-64 ELF whose `.comment` is `GCC: (GNU) 4.0.4`;
all 17 answered `--version`.

The test suites ran with the late tools first in `PATH` and bash 5.2 as
`/bin/sh` and as make's `SHELL` and `CONFIG_SHELL` (the suites' scripts use
`unalias`, `<(...)` and `echo -e`, which the chain's bash 2.05b lacks):

| package | result |
|---|---|
| grep | 282 pass, 69 skip, 2 xfail, 0 fail |
| sed | 210 pass, 50 skip, 0 fail |
| m4 | 233 pass, 34 skip, 0 fail |
| diffutils | 203 pass, 37 skip, 0 fail |
| patch | 42 pass, 2 xfail, 0 fail |
| xz | 16 pass, 3 skip, 0 fail |
| tar | 215 autotest tests pass |
| bison | 377 autotest tests pass (399 skipped: C++, D, Java), 7 more pass |
| findutils | 302 pass, 61 skip, 1 fail: `test-c32ispunct` (musl, below) |
| gzip | 52 pass, 2 skip, 2 fail: `zmore`, and `help-version` through it (no `more`) |
| coreutils | 1638 pass, 614 skip, 15 fail, 6 error (below) |
| gawk | all but 3: `commas` (no `en_US` locale), `nonfatal3` (no network), `clos1way6` (output order of a two-way pipe) |
| bash | diffs only where the root lacks `/etc`, `/dev/tty`, `locale` and locales, in output ordering (`run-trap`, `run-execscript`), and in `run-cond`'s `[[=d=]]` / `[[.o.]]` regex classes, which musl 1.1.24's regcomp does not support |
| make | suite not run: it needs perl |
| flex | not run: building its tests needs a C++ compiler (`g++`) |
| bc | no test suite |

coreutils' failures and errors, each read from its log:

- `chgrp/*`, `test-chown`, `test-fchownat`, `test-lchown`, `id/uid`, `id/zero`, `whoami`, `help-version` (through `whoami`): the bwrap
  user namespace maps one uid and one gid and the root has no
  `/etc/passwd` or `/etc/group`.
- `rm-readdir-fail`, `nfs-removal-race`, `no-mtab-status`, `skip-duplicates`,
  `getxattr-speedup`: set-up failures; they build an `LD_PRELOAD` shared
  library, and this toolchain is static only.
- `test-localtime_r`, `test-localtime_r-mt`: no `/usr/share/zoneinfo` in the
  root (both pass when the same binaries run on the host).
- `chown/separator`: its set-up runs `id` for the user name, which has none
  here.
- `test-canonicalize`, `test-c32ispunct`: gnulib's tests expect newer musl
  when `MUSL_LIBC` is set (realpath keeping `//`, `iswpunct` of U+E003A TAG
  COLON). Both fail the same way when run on the host.

The attributions above come from reading each log; none of the failures was
checked against a second compiler, so a GCC 4.0.4 miscompilation hiding
behind one of them is not ruled out.

## Three fixes in late-tools.sh

1. **The build triple.** config.guess tells musl from glibc by whether
   `<stdarg.h>` defines musl's `__DEFINED_va_list`; GCC's own `stdarg.h` is
   found first, so it answered `x86_64-pc-linux-gnu`, and gnulib then
   assumed glibc's thread-safe `setlocale` (`test-setlocale_null-mt-all`
   failed in grep, sed, findutils, diffutils and coreutils). The script
   passes `--build=x86_64-pc-linux-musl`.
2. **Script paths.** configure records the shell and tools it ran with.
   Where `/bin/sh` is the plumbing bash (under K1, or in a traced root), the
   script names it `/bin/sh`, so installed scripts that begin `#!/bin/sh`
   say so instead of naming a path into `build-out/plumbing`.  zgrep and
   updatedb also keep the `grep` and `sort` configure found; grep 2.4 lacks
   `--label` and coreutils 5.0's sort lacks `-z`, so grep and sed are built
   before gzip, and gzip and findutils are given the late grep and sort.
3. **`/dev`.** With only `/dev/null` in a root, bash configures without
   `/dev/fd` and `/dev/stdin`; the root needs a minimal `/dev` (K1
   provides one).

## Not done

- No second run compared for reproducibility on the host; the absolute
  prefix (`/build-out/late/usr`) is compiled into several programs, so a
  different output directory gives different bytes.  Under K1 the prefix
  is the same each run, and the 159 program hashes match an earlier
  independent run.
