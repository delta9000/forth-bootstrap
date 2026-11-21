/* tinycc/direct-input.c -- the one translation unit the Forth compiler
   compiles into the first tcc (tinycc/build-first-tcc.sh copies it to
   build-out/tcc-sources/direct-input.c).

   From seed-forth's tools/tcc-direct-input.c (commit 550a0c5, on
   origin/qemu-final), with TinyCC 0.9.27 and the x86_64 target replaced
   by janneke's 0.9.26 fork and i386, and with live-bootstrap's paths.

   The tcc defines are live-bootstrap's for tcc-mes on x86 in
   steps/tcc-0.9.26/pass1.kaem: BOOTSTRAP, HAVE_LONG_LONG 0, TCC_TARGET_I386
   and the same CONFIG_* strings, so this tcc looks for headers, crt files
   and libraries where tcc-mes does.  (pass1.kaem's -D inline= is left out;
   it does not change the output.)  With HAVE_LONG_LONG 1, as the study
   had it, the final tcc is the same but boot1 is e3576448..., not
   live-bootstrap's d9116def....

   The host side is x86_64 Linux: Mes 0.28's libc is compiled into the
   same image (tinycc/mes-libc.c, which includes it from the unpacked
   mes-0.28 tarball with tinycc/mes-libc-native.c for its assembly), and
   the Forth compiler's native runtime supplies one system-call primitive.
   The target is i386.

   getcwd: with -g, tcc records the directory of tcc.c, through Mes's
   getcwd, a real Linux getcwd here, so this tcc records
   /steps/tcc-0.9.26/build/tcc-0.9.26-1147-gee75a10c/ as tcc-mes does.

   Floating point: HAVE_FLOAT is not defined, as for tcc-mes, so tcc.c's
   strtod and strtold calls for float literals are compiled out; only an
   F-suffixed literal calls strtof, which traps (mes-libc-native.c), and
   a hex float calls Mes's ldexp stub, which returns 0, as in tcc-mes. */
#define __linux__ 1
#define __x86_64__ 1
#define BOOTSTRAP 1
#define HAVE_LONG_LONG 0
#define TCC_TARGET_I386 1
#define CONFIG_SYSROOT "/"
#define CONFIG_TCC_CRTPREFIX "/usr/lib/mes"
#define CONFIG_TCC_ELFINTERP "/mes/loader"
#define CONFIG_TCC_SYSINCLUDEPATHS "/usr/include/mes"
#define TCC_LIBGCC "/usr/lib/mes/libc.a"
#define CONFIG_TCC_LIBTCC1_MES 0
#define CONFIG_TCCBOOT 1
#define CONFIG_TCC_STATIC 1
#define CONFIG_USE_LIBGCC 1
#define TCC_VERSION "0.9.26"
#define ONE_SOURCE 1
#define CONFIG_TCCDIR "/usr/lib/mes/tcc"
#include "mes-libc.c"
#include "tcc-0.9.26-1147-gee75a10c/tcc.c"
