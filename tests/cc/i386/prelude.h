/* tests/cc/i386/prelude.h -- what every corpus program starts with, for
   both compilers: output through one system call, so that neither needs a
   C library of the other's, and va_list for the Forth compiler's 8-byte
   argument slots (gcc uses its own). */
#ifdef __GNUC__
#include <stdarg.h>
#include <unistd.h>
#include <sys/syscall.h>
long __native_syscall (long n, long a, long b, long c, long d, long e, long f) { return syscall (n, a, b, c, d, e, f); }
#else
long __native_syscall (long n, long a, long b, long c, long d, long e, long f);
typedef char *va_list;
#define va_start(ap, last) ((ap) = (char *) &(last) + 8)
#define va_arg(ap, type) ((type) ((long long *) ((ap) = (ap) + 8))[-1])
#define va_end(ap) ((ap) = 0)
#endif

void
out (char *s)
{
  int n = 0;
  while (s[n])
    n = n + 1;
  __native_syscall (4, 1, (long) s, n, 0, 0, 0);
}

void
hex32 (unsigned v)
{
  char b[9];
  int i;
  for (i = 0; i < 8; i = i + 1)
    {
      unsigned d = (v >> (28 - 4 * i)) & 15;
      b[i] = d < 10 ? '0' + d : 'a' + d - 10;
    }
  b[8] = 0;
  out (b);
}

/* The halves are printed apart, so a wrong high half shows as itself. */
void
show (char *name, unsigned long long v)
{
  out (name);
  out (" ");
  hex32 ((unsigned) (v >> 32));
  out (":");
  hex32 ((unsigned) v);
  out ("\n");
}
