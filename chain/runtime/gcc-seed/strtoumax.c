/* Original implementation; see LICENSE and README.md.
   LP64: long long, intmax_t and long share one 64-bit range, so the
   long conversion gives exactly the required result and errno. */
#include <stdlib.h>
#include <inttypes.h>

uintmax_t strtoumax(const char *text, char **end, int base)
{
    return strtoul(text, end, base);
}
