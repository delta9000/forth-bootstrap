/* tinycc/mes-libc-native.c -- Mes libc's system-call and startup layer for
   the Forth compiler's native mode, in plain C.

   tinycc/mes-libc.c includes this first, then the Mes libc files that
   live-bootstrap's steps/tcc-0.9.26/pass1.kaem compiles into libc.a, then
   the program.  It stands in for the files of that list that are assembly
   or that need floating-point arithmetic:
     lib/linux/x86_64-mes-gcc/syscall.c, _exit.c, _write.c  inline asm
     lib/x86_64-mes-gcc/setjmp.c                            inline asm
     lib/linux/x86_64-mes-gcc/crt1.c (_start)               inline asm
     lib/mes/abtod.c, lib/mes/dtoab.c                       double arithmetic
   Every system call goes through __native_syscall, the one primitive
   cc/119-cc-native-runtime.fth emits when tinycc/tcc-compile.fth sets
   cc-native-syscall-any; it returns what Linux returns, -errno on failure,
   and the _sys_call wrappers set errno as Mes's do. */

/* Mes's jmp_buf is an array of one struct, which native mode cannot pass
   as an argument.  setjmp below keeps nothing, so any array type will do;
   this stands in for Mes's setjmp.h. */
#define __MES_SETJMP_H 1
typedef long jmp_buf[3];
int setjmp (jmp_buf env);
void longjmp (jmp_buf env, int val);

#include <errno.h>
#include <stdlib.h>
#include <unistd.h>
#include <mes/lib.h>

long __native_syscall (long n, long a, long b, long c, long d, long e, long f);

long __sys_call (long n) { return __native_syscall (n, 0, 0, 0, 0, 0, 0); }
long __sys_call1 (long n, long a) { return __native_syscall (n, a, 0, 0, 0, 0, 0); }
long __sys_call2 (long n, long a, long b) { return __native_syscall (n, a, b, 0, 0, 0, 0); }
long __sys_call3 (long n, long a, long b, long c) { return __native_syscall (n, a, b, c, 0, 0, 0); }
long __sys_call4 (long n, long a, long b, long c, long d) { return __native_syscall (n, a, b, c, d, 0, 0); }

long
__native_errno (long r)
{
  if (r < 0)
    {
      errno = -r;
      return -1;
    }
  errno = 0;
  return r;
}

long _sys_call (long n) { return __native_errno (__sys_call (n)); }
long _sys_call1 (long n, long a) { return __native_errno (__sys_call1 (n, a)); }
long _sys_call2 (long n, long a, long b) { return __native_errno (__sys_call2 (n, a, b)); }
long _sys_call3 (long n, long a, long b, long c) { return __native_errno (__sys_call3 (n, a, b, c)); }
long _sys_call4 (long n, long a, long b, long c, long d) { return __native_errno (__sys_call4 (n, a, b, c, d)); }

void
_exit (int code)
{
  __native_syscall (60, code, 0, 0, 0, 0, 0);
}

ssize_t
_write (int fd, void const *buffer, size_t size)
{
  return __native_syscall (1, fd, (long) buffer, size, 0, 0, 0);
}

/* tcc calls setjmp before compiling and longjmp only on an error, after
   printing it. */
int
setjmp (long *env)
{
  return 0;
}

void
longjmp (long *env, int val)
{
  eputs ("longjmp: not available in native mode\n");
  _exit (125);
}

/* Native mode keeps a double as its bit pattern and has no arithmetic on
   it, so the two conversions under strtod, atof and printf's %f stop here
   instead of returning wrong bits. */
void
__native_no_float (char const *name)
{
  eputs (name);
  eputs (": no floating point in native mode\n");
  _exit (125);
}

double
abtod (char const **p, int base)
{
  __native_no_float ("abtod");
  return 0;
}

char *
dtoab (double d, int base, int signed_p)
{
  __native_no_float ("dtoab");
  return 0;
}

/* crt1.c's _start: the native entry calls main (argc, argv) and exits with
   its value; the program's main is renamed. */
int __native_main ();

int
main (int argc, char **argv)
{
  __init_io (argc, argv, argv + argc + 1);
  exit (__native_main (argc, argv));
}
#define main __native_main
