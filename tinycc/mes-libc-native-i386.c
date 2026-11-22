/* tinycc/mes-libc-native-i386.c -- Mes libc's system-call and startup
   layer for the Forth compiler, in plain C.

   tinycc/build-first-tcc-i386.sh copies this to
   build-out/tcc-sources-i386/mes-libc-native.c, the name tinycc/mes-libc.c
   includes first; then come the Mes libc files that live-bootstrap's
   steps/tcc-0.9.26/pass1.kaem compiles into libc.a, then the program.  It
   stands in for the files of that list that are assembly or that need
   floating-point arithmetic:
     lib/linux/x86-mes-gcc/syscall.c, _exit.c, _write.c  inline asm
     lib/x86-mes-gcc/setjmp.c                            inline asm
     lib/linux/x86-mes-gcc/crt1.c (_start)               inline asm
     lib/mes/abtod.c, lib/mes/dtoab.c                    double arithmetic
   Every system call goes through __native_syscall, the one primitive
   cc/i386/119-runtime.fth emits; it returns what Linux returns, -errno on
   failure, and the _sys_call wrappers set errno as Mes's do.  The call
   numbers are Mes's own, from include/linux/x86/syscall.h; only exit and
   write are spelt here. */

/* Mes's jmp_buf is an array of one struct, which native mode cannot pass
   as an argument.  setjmp below keeps nothing, so any array type will do;
   this stands in for Mes's setjmp.h. */
#define __MES_SETJMP_H 1
typedef long jmp_buf[3];
int setjmp (jmp_buf env);
void longjmp (jmp_buf env, int val);

/* Native mode passes every argument in an 8-byte stack slot, the first
   lowest, and a pointer is 4 bytes here.  Mes's stdarg.h steps by
   sizeof (void *) and aligns va_arg8 to 8, which esp is not; this stands
   in for it, stepping 8 for every argument. */
#define __MES_STDARG_H 1
#include <sys/types.h>
typedef char *va_list;
#define va_start(ap, last) (void) ((ap) = (char *) (&(last)) + 8)
#define va_arg(ap, type) (type) (((long long *) ((ap) = ((ap) + 8)))[-1])
#define va_arg8(ap, type) (type) (((double *) ((ap) = ((ap) + 8)))[-1])
#define va_end(ap) (void) ((ap) = 0)
#define va_copy(dest, src) dest = src
int vexec (char const *file_name, va_list ap);

#include <errno.h>
#include <stdlib.h>
#include <unistd.h>
#include <mes/lib.h>

long __native_syscall (long n, long a, long b, long c, long d, long e, long f);

/* The system calls builder-hex0 has: exit 1, fork 2, read 3, write 4,
   open 5, close 6, waitpid 7, execve 11, chdir 12, lseek 19, access 33,
   mkdir 39, brk 45 and getcwd 183.  It answers 0 to every other number and
   does nothing.  tcc unlinks each output file before it writes it, and
   Mes's remove calls stat and then unlink or rmdir; none of those is in
   the list.  Such a call gets builder-hex0's answer here and never enters
   the kernel, so a run on Linux also has to manage without it.  (Linux
   then keeps an *.a.tmp file that builder-hex0 would start afresh.) */
long
__native_call (long n, long a, long b, long c, long d)
{
  if (n == 1 || n == 2 || n == 3 || n == 4 || n == 5 || n == 6 || n == 7
      || n == 11 || n == 12 || n == 19 || n == 33 || n == 39 || n == 45
      || n == 183)
    return __native_syscall (n, a, b, c, d, 0, 0);
  return 0;
}

long __sys_call (long n) { return __native_call (n, 0, 0, 0, 0); }
long __sys_call1 (long n, long a) { return __native_call (n, a, 0, 0, 0); }
long __sys_call2 (long n, long a, long b) { return __native_call (n, a, b, 0, 0); }
long __sys_call3 (long n, long a, long b, long c) { return __native_call (n, a, b, c, 0); }
long __sys_call4 (long n, long a, long b, long c, long d) { return __native_call (n, a, b, c, d); }

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
  __native_call (1, code, 0, 0, 0);
}

ssize_t
_write (int fd, void const *buffer, size_t size)
{
  return __native_call (4, fd, (long) buffer, size, 0);
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
