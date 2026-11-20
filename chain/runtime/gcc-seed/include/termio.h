#ifndef SEED_GCC_TERMIO_H
#define SEED_GCC_TERMIO_H
/* Original interface; see LICENSE and ../README.md. As in
   glibc, the System V struct termio and TCGETA/TCSETA* requests come from
   <sys/ioctl.h>; their flag bits are the low 16 bits of <termios.h>'s. */
#include <termios.h>
#include <sys/ioctl.h>
#endif
