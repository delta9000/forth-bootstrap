/* tinycc/m2libc-native.c -- M2libc's amd64/linux layer for the Forth
   compiler's native mode, in plain C.

   tinycc/build-tools.sh puts this ahead of each tool's C source on the
   compiler's stdin.  M2libc (vendor/stage0-posix/M2libc) is compiled in
   its own M2 mode, as M2-Mesoplanet builds stage0's tools: __M2__ makes
   its headers include its .c files.  This file stands in for what
   M2-Planet and M2libc's assembly provide:
     amd64/linux/unistd.c, fcntl.c, sys/stat.c  system calls in M1
         assembly; their include guards are defined here so the headers
         skip them, and the calls the tools reach are below;
     amd64/libc-full.M1's _start and exit  main below;
     M2-Planet's built-in types (SCM, FUNCTION, the fixed-width integers)
         and its va_* builtins, which M2libc's stdarg.h names.
   Every system call goes through __native_syscall, the one primitive
   cc/119-cc-native-runtime.fth emits when tinycc/tool-compile.fth sets
   cc-native-syscall-any.  It returns what Linux returns, as M2libc's
   assembly does: -errno on failure. */
#define __M2__ 1
#define __x86_64__ 1
#define _UNISTD_C 1
#define __FCNTL_C 1
#define _SYS_STAT_C 1

typedef unsigned long SCM;
typedef void (*FUNCTION) ();
typedef unsigned char uint8_t;
typedef signed char int8_t;
typedef unsigned short uint16_t;
typedef short int16_t;
typedef unsigned uint32_t;
typedef int int32_t;
typedef unsigned long uint64_t;
typedef long int64_t;

/* Native mode passes every argument in an eight-byte stack slot, the
   first lowest. */
#define _STDARG_H 1
typedef char *va_list;
#define va_start(ap, last) ((ap) = (char *) &(last) + 8)
#define va_arg(ap, type) ((type) ((long *) ((ap) = (ap) + 8))[-1])
#define va_end(ap) ((ap) = 0)
#define va_copy(dest, src) ((dest) = (src))

/* From amd64/linux/fcntl.c */
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 00100
#define O_EXCL 00200
#define O_TRUNC 001000
#define O_APPEND 002000
#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2

/* From amd64/linux/sys/stat.c */
#define S_IRWXU 00700
#define S_IXUSR 00100
#define S_IWUSR 00200
#define S_IRUSR 00400
#define S_ISUID 04000
#define S_ISGID 02000
#define S_IXGRP 00010
#define S_IXOTH 00001
#define S_IRGRP 00040
#define S_IROTH 00004
#define S_IWGRP 00020
#define S_IWOTH 00002
#define S_IRWXG 00070
#define S_IRWXO 00007

long __native_syscall (long n, long a, long b, long c, long d, long e, long f);

int read (int fd, char *buf, unsigned count) { return __native_syscall (0, fd, (long) buf, count, 0, 0, 0); }
int write (int fd, char *buf, unsigned count) { return __native_syscall (1, fd, (long) buf, count, 0, 0, 0); }
int _open (char *name, int flag, int mode) { return __native_syscall (2, (long) name, flag, mode, 0, 0, 0); }
int close (int fd) { return __native_syscall (3, fd, 0, 0, 0, 0, 0); }
int lseek (int fd, int offset, int whence) { return __native_syscall (8, fd, offset, whence, 0, 0, 0); }
int brk (void *addr) { return __native_syscall (12, (long) addr, 0, 0, 0, 0, 0); }
int access (char *pathname, int mode) { return __native_syscall (21, (long) pathname, mode, 0, 0, 0, 0); }
int _getcwd (char *buf, int size) { return __native_syscall (79, (long) buf, size, 0, 0, 0, 0); }
int chdir (char *path) { return __native_syscall (80, (long) path, 0, 0, 0, 0, 0); }
int mkdir (char const *a, int b) { return __native_syscall (83, (long) a, b, 0, 0, 0, 0); }
int unlink (char *filename) { return __native_syscall (87, (long) filename, 0, 0, 0, 0, 0); }
int symlink (char *path1, char *path2) { return __native_syscall (88, (long) path1, (long) path2, 0, 0, 0, 0); }
int chmod (char *pathname, int mode) { return __native_syscall (90, (long) pathname, mode, 0, 0, 0, 0); }

/* As amd64/linux/unistd.c's: NULL only when the call returns 0. */
char *
getcwd (char *buf, unsigned size)
{
  if (0 == _getcwd (buf, size))
    return 0;
  return buf;
}

void
_exit (int value)
{
  __native_syscall (60, value, 0, 0, 0, 0, 0);
}

/* libc-full.M1: _start sets _envp and calls __init_malloc, __init_io and
   main; exit flushes through __kill_io.  The native entry calls
   main (argc, argv); the program's main is renamed. */
char **_envp;
void __init_malloc ();
void __init_io ();
void __kill_io ();

void
exit (int value)
{
  __kill_io ();
  _exit (value);
}

int __native_main ();

int
main (int argc, char **argv)
{
  _envp = argv + argc + 1;
  __init_malloc ();
  __init_io ();
  exit (__native_main (argc, argv, _envp));
}

/* stdlib.c and string.c both define memset; M2-Planet accepts that,
   native mode does not (error 211).  stdlib.c's, which only its calloc
   calls, is renamed. */
#define memset __m2libc_stdlib_memset
#include <stdlib.h>
#undef memset
#define main __native_main
