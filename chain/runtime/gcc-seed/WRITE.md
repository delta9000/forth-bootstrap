# One-call POSIX write

Original Heirloom getopt.c needs write for diagnostics. The source-built
write.c makes one Linux AMD64 write syscall, returns successful partial byte
counts unchanged, preserves errno on success, and converts a negative kernel
result to minus one plus errno. It returns EINTR to its caller rather than
silently retrying. The ssize_t, size_t and descriptor ABI are declared in the
bounded unistd.h interface. No read wrapper is implied by this increment.

A real nonblocking pipe, EAGAIN, EBADF, a 4096-byte
partial result from an 8192-byte request, and zero count were validated. A separate provider
double verified every syscall argument, no retry on EINTR, ENOSPC and errno.
Independent host C90 builds at O0 and O2 repeated the real-pipe contract. No host
output or fault provider supplies production behavior.
