/* tinycc/tools/simple-patch-unit.c -- the translation unit seed-cc compiles
   into build-out/tinycc/bin/simple-patch (tinycc/build-tools.sh).

   live-bootstrap's steps/simple-patch-1.0/src/simple-patch.c (from the
   pinned live-bootstrap archive, unchanged) calls open, read, write, lseek
   and close and uses O_RDONLY, O_WRONLY, O_CREAT and O_TRUNC, but includes
   only string.h, stdio.h, stdlib.h and M2libc/bootstrappable.h: under
   M2-Mesoplanet, M2libc's stdio.h brings in the rest.  chain/runtime/gcc-seed's
   headers do not, so they are included here first.  build-tools.sh puts
   that src directory and mescc-tools-extra on the include path. */
#include <fcntl.h>
#include <unistd.h>
#include "simple-patch.c"
