# Credits

forth-bootstrap's own files (the seed, the Forth library, the C compiler,
the C shims, the jobs, scripts and checks) are under the MIT License in
[LICENSE](LICENSE).  Everything below comes from elsewhere and keeps its
own license.

## In this repository

| What | Where | From | License |
|---|---|---|---|
| hex0-seed (229 bytes; assembles builder-hex0's stage 1 and the reference seed on the host), `kaem-minimal.hex0` (assembled in the boot as kaem-optional-seed) | `vendor/stage0-posix/bootstrap-seeds`, `vendor/stage0-posix/x86` | [stage0-posix](https://github.com/oriansj/stage0-posix) / [bootstrap-seeds](https://github.com/oriansj/bootstrap-seeds) | GPL-3.0-or-later |
| mescc-tools-extra (`catm`, `match`, `mkdir`, `cp`, `rm`, `chmod`, `sha256sum`, `untar`, `ungz`) and M2libc, compiled by the seed (`tinycc/build-tools.sh`) | `vendor/stage0-posix/mescc-tools-extra`, `vendor/stage0-posix/M2libc` | stage0-posix | GPL-3.0-or-later |
| kaem, compiled by the seed, and its test scripts | `vendor/mescc-tools/Kaem` | [mescc-tools](https://github.com/oriansj/mescc-tools) | GPL-3.0-or-later |
| One gate fixture taken from M2-Planet | `tests/cc/gates/G4.c` | [M2-Planet](https://github.com/oriansj/M2-Planet) | GPL-3.0-or-later |
| The other gate fixtures and the run-time corpus | `tests/cc/gates/`, `tests/cc/` | written for seed-forth and for this repository | MIT |

## Read as pinned archives (tinycc/SOURCES, tinycc/builder-hex0.SOURCES; not in the repository)

| Archive | License |
|---|---|
| janneke's TinyCC fork tcc-0.9.26-1147-gee75a10c | LGPL-2.1-or-later |
| GNU Mes 0.28, whose libc (`tinycc/mes-libc.c` lists the files) is compiled into the first tcc | GPL-3.0-or-later |
| live-bootstrap a49273cb, whose simple-patch, checksum-transcriber, simple-patches and kaem text the route uses | each file's SPDX header (simple-patch GPL-3.0-or-later, checksum-transcriber MIT) |
| builder-hex0 a2781242, the kernel of the boot | Apache-2.0 or Boost-1.0 at your option (its COPYRIGHT file); the two stage files carry `SPDX-License-Identifier: MIT` |

`build-out/tinycc/tcc-first` is TinyCC and Mes libc compiled into one
program, so it is under GPL-3.0-or-later as a whole.  The repository's
own files that go into it, `tinycc/direct-input.c`,
`tinycc/mes-libc.c` (a list of Mes's file names) and
`tinycc/mes-libc-native.c` (written for this route: Mes's function
names and signatures, our bodies; no Mes code is copied), are MIT.

`tinycc/m2libc-native.c` and `tinycc/m2libc-kaem.c` (MIT,
written for this route) stand in for M2libc's GPL-3.0-or-later
`x86/linux/unistd.c`, `fcntl.c`, `sys/stat.c` and `libc-full.M1`.  They
restate their constants, function names and signatures and the
three-line logic of `getcwd`, `exit` and `_start`; the system calls are
rewritten in C.

## People and projects

The route stands on the work of the bootstrappable-builds community:
Jeremiah Orians' stage0-posix, mescc-tools, M2-Planet and M2libc;
janneke's GNU Mes and TinyCC fork; Richard Masters' builder-hex0; and the
live-bootstrap project, whose `tcc-0.9.26` step this route joins.
