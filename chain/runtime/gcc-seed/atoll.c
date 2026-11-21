/* Original implementation; see LICENSE and README.md.
   LP64: long long, intmax_t and long share one 64-bit range, so the
   long conversion gives exactly the required result and errno. */
#include <stdlib.h>

long long atoll(const char *text)
{
    return strtol(text, (char **)0, 10);
}
