/* Original implementation; see LICENSE and README.md. */
#include <string.h>

char *stpcpy(char *destination, const char *source)
{
    while ((*destination = *source++) != '\0') destination++;
    return destination;
}
