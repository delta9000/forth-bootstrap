/* tinycc/direct-input-i386.c -- the one translation unit the Forth
   compiler compiles into the i386 first tcc
   (tinycc/build-first-tcc-i386.sh copies it to
   build-out/tcc-sources-i386/direct-input.c).

   tinycc/direct-input.c with __i386__ for __x86_64__: the same tcc
   defines, live-bootstrap's for tcc-mes on x86, and the same Mes libc in
   the same image, here with Mes's i386 headers and
   tinycc/mes-libc-native-i386.c for its assembly.  Host and target are
   both i386, so tcc.h also compiles its -run support (TCC_IS_NATIVE);
   nothing in the route uses it. */
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
