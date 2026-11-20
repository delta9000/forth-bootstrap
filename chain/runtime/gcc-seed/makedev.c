/* Original implementation; see LICENSE and README.md. */
#include <sys/types.h>

unsigned long __seed_makedev(unsigned int high, unsigned int low)
{
    unsigned long major = high;
    unsigned long minor = low;
    return ((major & 0xfffUL) << 8) | ((major & 0xfffff000UL) << 32)
         | (minor & 0xffUL) | ((minor & 0xffffff00UL) << 12);
}
