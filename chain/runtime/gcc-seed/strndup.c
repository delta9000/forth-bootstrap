/* Original implementation; see LICENSE and README.md. */
#include <string.h>
#include <stdlib.h>

char *strndup(const char *string, size_t count)
{
    size_t length = strnlen(string, count);
    char *copy = malloc(length + 1);
    if (copy == NULL) return NULL;
    memcpy(copy, string, length);
    copy[length] = '\0';
    return copy;
}
