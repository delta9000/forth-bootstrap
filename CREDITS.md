# Credits

forth-bootstrap's own files (the seed, the Forth library, the C compiler,
K0, K1, the chain's scripts, recipes and configurations) are
under the MIT License in [LICENSE](LICENSE).  Everything below comes from
elsewhere and keeps its own license.

## In this repository

| What | Where | From | License |
|---|---|---|---|
| hex0-seed (229 bytes, the only binary the route starts from) | `vendor/stage0-posix/bootstrap-seeds` | [stage0-posix](https://github.com/oriansj/stage0-posix) / [bootstrap-seeds](https://github.com/oriansj/bootstrap-seeds) | GPL-3.0-or-later |
| mescc-tools-extra (`mkdir`, `cp`, `rm`, `chmod`, `sha256sum`, `untar`, `ungz`, `unbz2`) and its M2libc, compiled by seed-cc in plumbing stage 1 | `vendor/stage0-posix/mescc-tools-extra` | stage0-posix | GPL-3.0-or-later |
| kaem, compiled by seed-cc as the first shell | `vendor/mescc-tools/Kaem` | [mescc-tools](https://github.com/oriansj/mescc-tools) | GPL-3.0-or-later |
| M2-Planet, compiled by the Forth compiler for Stage A (and its headers, copied into `tests/cc/` for the compiler's include fallback) | `vendor/M2-Planet`, `tests/cc/*.h` | [M2-Planet](https://github.com/oriansj/M2-Planet) | GPL-3.0-or-later |
| Patches for gcc-4.7.4, gcc-10.5.0, musl-1.1.24 and bash-2.05b, each with a provenance header | `chain/patches/gcc64/`, `chain/plumbing/bash-2.05b/missing-defines.patch` | [live-bootstrap](https://github.com/fosslinux/live-bootstrap) b1ceced7, `steps/*/patches` | each patch's SPDX header (the patched project's license) |
| flex 2.5.11's `scan.lex.l` and two patches | `chain/gcc-direct/lexer-inputs/recipe-reference/` | live-bootstrap b1ceced7, `steps/flex-2.5.11` (`chain/gcc-direct/lexer-inputs/PROVENANCE.md`) | BSD-2-Clause (`LICENSES/BSD-2-Clause.txt` there) |
| Test programs `tests/gcc64/libc-test.c`, `cxx-test.cc` and the other patches in `chain/patches/` and `chain/plumbing/` | as named | written for seed-forth | MIT, unless a header says otherwise |

## Read as pinned archives (MANIFEST.sha256, not in the repository)

Each archive is unpacked, patched and built inside the chain.  The
programs built from them keep their upstream licenses.

| Archives | License |
|---|---|
| GNU make 3.82 and 4.4.1, bash 2.05b and 5.2.37, sed 4.0.9 and 4.9, grep 2.4 and 3.11, gawk 3.0.4 and 5.3.1, coreutils 5.0 and 9.5, tar 1.12 and 1.35, gzip 1.2.4 and 1.13, patch 2.5.9 and 2.7.6, diffutils 2.7 and 3.10, findutils 4.10.0, m4 1.4.19, bison 3.8.2, bc 1.07.1 | GPL (version per package) |
| binutils 2.30 and 2.41; GCC 4.0.4 (git export of releases/gcc-4.0.4), 4.7.4 and 10.5.0 | GPL-3.0-or-later (GCC 4.0.4: GPL-2.0-or-later), runtime-library exceptions as shipped |
| musl 1.1.24 | MIT |
| GMP 6.2.1 (Debian DFSG repack), MPFR 4.1.0, MPC 1.2.1 | LGPL-3.0-or-later (GMP: LGPL-3.0-or-later or GPL-2.0-or-later) |
| oyacc 6.6 | BSD |
| Heirloom devtools 070527 (lex) | CDDL-1.0 and BSD-style, per file |
| flex 2.5.11 (git d160f024) and flex 2.6.4 | BSD-style (flex license) |
| xz 5.6.3 | 0BSD and public domain (the programs), GPL/LGPL for some scripts |
| bzip2 1.0.8 | bzip2 license (BSD-style) |
| zlib 1.3.1 | zlib |
| elfutils 0.192 (libelf only) | LGPL-3.0-or-later or GPL-2.0-or-later |
| Linux 7.2.8 | GPL-2.0 |

## People and projects

The route stands on the work of the bootstrappable-builds community:
Jeremiah Orians' stage0-posix, mescc-tools, M2-Planet and M2libc, and the
live-bootstrap project, whose patches and ordering much of the GCC climb
follows.  seed-forth, where this repository started, also drew on
[pnut](https://github.com/udem-dlteam/pnut) and TinyCC for its other route
(see [HISTORY.md](HISTORY.md)).
