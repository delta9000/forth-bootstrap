/* Original implementation; see LICENSE and README.md. */
#include <sys/stat.h>

int mkfifo(const char *path, mode_t mode)
{
    /* Only permission bits come from MODE; the umask still applies. */
    return mknod(path, (mode & 07777) | S_IFIFO, 0);
}
