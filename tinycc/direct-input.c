/* tinycc/direct-input.c -- the one translation unit the Forth
   compiler compiles into the first tcc (tinycc/build-first-tcc.sh
   copies it to build-out/tcc-sources/direct-input.c, the boot to
   /direct-input.c).

   The tcc defines are live-bootstrap's for tcc-mes on x86 in
   steps/tcc-0.9.26/pass1.kaem: BOOTSTRAP, HAVE_LONG_LONG 0, TCC_TARGET_I386
   and the same CONFIG_* strings, so this tcc looks for headers, crt files
   and libraries where tcc-mes does.  (pass1.kaem's -D inline= is left out;
   it does not change the output.)

   Host and target are both i386.  Mes 0.28's libc is compiled into the
   same image (tinycc/mes-libc.c, which includes it from the unpacked
   mes-0.28 tarball, with Mes's i386 headers and
   tinycc/mes-libc-native.c for its assembly), and the Forth
   compiler's runtime supplies one system-call primitive.  Because host
   and target are the same, tcc.h also compiles its -run support
   (TCC_IS_NATIVE); nothing in the route uses it.

   getcwd: with -g, tcc records the directory of tcc.c, through Mes's
   getcwd, so this tcc records
   /steps/tcc-0.9.26/build/tcc-0.9.26-1147-gee75a10c/ as tcc-mes does.

   Floating point: HAVE_FLOAT is not defined, as for tcc-mes, so tcc.c's
   strtod and strtold calls for float literals are compiled out; only an
   F-suffixed literal calls strtof, which traps
   (mes-libc-native.c), and a hex float calls Mes's ldexp stub,
   which returns 0, as in tcc-mes. */
#define __linux__ 1
#define __i386__ 1
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
