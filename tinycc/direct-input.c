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

   The host side is x86_64 Linux: pnut's portable libc is compiled into the
   same image, with tinycc/libc-sscanf.c for the sscanf it declares but does
   not define, PNUT_CC selects its configuration without inline assembly,
   and the Forth compiler's native runtime supplies the system calls.  The
   target is i386.

   getcwd: under PNUT_CC, portable libc's getcwd returns NULL, and with -g
   tcc then records the directory of tcc.c as "/".
   tinycc/libc-getcwd.after makes it call _getcwd, the Linux getcwd call
   that cc/119-cc-native-runtime.fth emits when tinycc/tcc-compile.fth
   sets cc-native-getcwd, so this tcc records
   /steps/tcc-0.9.26/build/tcc-0.9.26-1147-gee75a10c/ as tcc-mes does,
   and its tcc-boot0 equals the stand-ins' (c1696e57...). */
#define PNUT_CC 1
#define PNUT_EXE 1
#define PNUT_EXE_64 1
#define PNUT_X86_64 1
#define PNUT_X86_64_LINUX 1
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
#define __intptr_t_defined 1
#include "pnut-abc34a5207b1373d0a4e3dcb3d3d6df6e22ae23d/portable_libc/libc.c"
#include "libc-sscanf.c"
#include "tcc-0.9.26-1147-gee75a10c/tcc.c"
