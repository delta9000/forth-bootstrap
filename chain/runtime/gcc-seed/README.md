# Bounded Linux AMD64 C runtime

These are original implementations under the repository MIT
license, except `qsort.c`, which is musl 1.1.24's (see
[Why qsort is musl's](#why-qsort-is-musls)). The target is Linux AMD64 with
LP64 types, signed plain `char`, and the measured System V calling contracts.
The public headers intentionally declare only implemented
interfaces; they do not claim a complete ISO C or POSIX environment.

The Forth compiler builds `memory.c`, `string.c`, and `alloc.c` as relocatable
objects. `122-cc-sysv-runtime.fth` supplies the raw Linux syscall bridge and
single-threaded errno object. No state in these C files requires a global
data initializer. The allocator stores a pair of LP64 sizes immediately
before each allocation. Payloads up to 2048 bytes use eight power-of-two
classes from 16 to 2048 bytes, sharing 64 KiB slabs. Freeing a small block
returns it to its class free list. Slabs stay mapped until process exit;
retention follows each class's lifetime high-water demand. Larger requests
use individual mappings, released by free. This single-threaded bootstrap
allocator is not safe for concurrent or signal-handler allocation.

## Defined allocation choices

- Successful pointers have 16-byte alignment
- `malloc(0)` requests a distinct minimal allocation that can be freed
- Either zero argument to `calloc` behaves like `malloc(0)`
- An overflowing `calloc` fails with `ENOMEM`
- Requests exceeding `LONG_MAX` minus metadata fail with `ENOMEM`
- Kernel mapping errors become `NULL` plus the kernel errno value
- `free(NULL)` is a no-op, and `free` preserves errno
- `realloc(NULL, n)` is `malloc(n)`
- `realloc(p, 0)` frees a nonnull `p` and returns `NULL`
- Shrinking `realloc` can retain the mapping; growing allocates and copies
- Failed growing `realloc` leaves the original allocation and bytes intact

As with ordinary C allocation APIs, freeing an invalid pointer, double-freeing,
or accessing an allocation after its lifetime has ended is undefined. The
runtime provides no threads, dynamic loader, or whole-libc compatibility promise. Signal handling and the fixed C/POSIX locale
have separate bounded contracts below. Add interfaces when an original source
consumer on the documented bootstrap path and a corresponding test establish
the need.


## Interfaces

Every system call goes through one `__seed_syscall6` call. A raw result in
-4095..-1 becomes `errno` and -1; success leaves `errno` unchanged; nothing
is retried unless the row says so. `setjmp`/`longjmp`, `_start`, the
`errno` object, the syscall bridge and the signal restorer are emitted by
the compiler's Forth runtime (`cc/122-cc-sysv-runtime.fth`), not by C files
here. Each row names the narrowing from ISO C or POSIX that a caller could
notice; the source files' comments give the detail.

| Group | Interfaces | Sources | Narrowed from ISO C / POSIX |
|---|---|---|---|
| Memory and strings | `mem*`, `str*`, `strdup`, `strndup`, `strnlen`, `stpcpy`, `stpncpy`, `strtok(_r)`, `strcoll`, `strxfrm`; `strings.h`, `memory.h` | memory.c, string.c, strcspn.c, strspn.c, strpbrk.c, strnlen.c, strndup.c, stpcpy.c, stpncpy.c, strtok.c, strcoll.c, strcasecmp.c, strncasecmp.c, bsd-string.c | C locale only: `strcoll` is `strcmp`, `strxfrm` copies; case folding is ASCII A-Z |
| Allocation | `malloc`, `calloc`, `realloc`, `free` | alloc.c | as above; a growing `realloc` always allocates and copies |
| ctype | the `is*` classes, `isascii`, `isblank`, `tolower`, `toupper` | ctype.c, isblank.c | ASCII C locale; real functions that evaluate their argument once |
| Integer conversion | `strto[u]l[l]`, `strto[u]max`, `ato[i,l,ll]`, `[l,ll]abs`, `[l,ll]div` | strtoul.c, strtoll.c, strtoull.c, strtoimax.c, strtoumax.c, atoi.c, atol.c, atoll.c, abs.c, labs.c | 64-bit forms alias the `long` ones; `0x` is a prefix only when a hex digit follows; `atoi` saturates and sets `ERANGE` |
| Random numbers | `rand`, `srand`, `random`, `srandom` | rand.c | no `initstate`/`setstate` |
| Floating input | `strtod`, `strtof`, `strtold`, `atof` | decimal.c | `.` only as decimal point; `errno` only `ERANGE`, by glibc's tininess rule; not reentrant |
| printf | `[v][f,s,sn]printf` | stdio.c, floatfmt.c | positional arguments and unknown conversions stop with `EINVAL`; `%ls`/`%lc` ASCII only; not reentrant; no `dprintf` or `asprintf` |
| scanf | `sscanf`, `fscanf` | scan.c | only `%d %u %o %x %c %s %n %%`, `l` on the integers, a width only on `%s`; anything else fails with `EINVAL` |
| Streams | `fopen` to `perror`, the `_unlocked` forms, `flockfile` family, `getline`, `getdelim`, `getwc`; `BUFSIZ` 8192 | stdio.c, setbuf.c, getline.c | `freopen(NULL, ...)` unsupported; `getwc` ASCII only; no `tmpfile`, `tmpnam`, `fgetpos`, `fsetpos`, `gets` or wide output; locking calls do nothing |
| Errors | `errno.h` (Linux AMD64 1-133), `strerror`, `perror` | strerror.c, stdio.c | `errno` is one global; no `strerror_r` |
| Search and sort | `qsort`, `bsearch` | qsort.c (musl), sort.c | see [Why qsort is musl's](#why-qsort-is-musls) |
| Environment, locale | `getenv`, `putenv`, `setenv`, `unsetenv`, `environ`, `__progname`, `setlocale`, `localeconv` | environment.c, setenv.c, locale.c, localeconv.c, startup.c | only the `C`/`POSIX` locale; `putenv` stores the caller's pointer; replaced `setenv` strings are never freed |
| Wide characters | `wchar_t`, `MB_CUR_MAX` 1, the `mb*`/`wc*` conversions, `btowc`, `wctob`, `iswprint`, `iswspace`, `towlower`, `wcstol` | wide.c, mbstate.c | ASCII only: bytes above 127 give `EILSEQ`; no wide string functions or `wprintf` |
| Math | `frexp`, `ldexp`, `scalbn`, `modf`, `copysign`, classification; with `-lm`, the double functions from `fabs` to `tanh` | fpclass.c, math.c | double only; `FLT_ROUNDS` -1; no `fenv.h`; `math.c` is linked only for `-lm` |
| Time | `time`, `clock`, `localtime`, `gmtime`, `mktime`, `timegm`, `asctime`, `ctime`, `strftime`, `tzset`, POSIX clocks, `nanosleep`, `usleep`, `gettimeofday`, `times`, `sleep`, `alarm` | calendar.c, strftime.c, clock.c, clock-sleep.c, timeofday.c, resource.c, process-api.c, signal-send.c | see [Time zones](#time-zones); no `tm_gmtoff`/`tm_zone`; no interval timers or `select` |
| Files and descriptors | `open` to `fsync`, `stat` family, links, ownership, `getcwd`, `realpath`, `mkstemp`, `mktemp`, `isatty`, `flock`, `utime(s)`, `major`/`minor`/`makedev`; `ar.h`, `sys/mtio.h`, `paths.h` | descriptor-io.c, creat.c, write.c, posix.c, dup3.c, fcntl.c, stat.c, metadata.c, access.c, remove.c, paths.c, file-calls.c, getcwd.c, mkfifo.c, ftruncate.c, flock.c, utimes.c, realpath.c, mkstemp.c, isatty.c, makedev.c | `open` rejects unknown flags with `EINVAL`; `fcntl` supports only the dup, `FD` and `FL` commands; `getcwd` needs a buffer; no `openat` family or `mkdtemp` |
| Directories | `opendir`, `readdir`, `closedir`, `rewinddir`, `dirfd`, `DT_*` | dirent.c, dirfd.c | no `seekdir`, `telldir` or `readdir_r` |
| Mappings | `mmap`, `munmap` | mapping.c | private mappings, read/write protections only |
| Processes | `fork`, `vfork`, the `exec` family, `wait*`, `kill`, `system`, `popen`, `exit` family, `atexit`, `on_exit`, `abort`, `getpid` | process-api.c, exec-list.c, system.c, popen.c, process.c, getpid.c | `vfork` is `fork` (see [below](#why-vfork-is-fork)); `execvp` does not retry with `/bin/sh`; 64 exit handlers; nothing flushes before `fork`/`exec` |
| Signals | `signal`, `sigaction`, the mask and set calls, `raise`, `killpg`, `pause`, `strsignal`, `psignal` | signal.c, sigaction.c, sigset.c, signal-send.c, strsignal.c | `signal` is persistent with `SA_RESTART`; no `sigaltstack`, `sigqueue` or `sigsetjmp` |
| Nonlocal jumps | `setjmp`, `longjmp` | Forth runtime, include/setjmp.h | private 64-byte `jmp_buf`; signal masks and floating-point control are not saved |
| Identity and users | `get*id`/`set*id`, groups, sessions, `getpw*`, `getgr*`, `getlogin` | identity.c, setgroups.c, passwd.c, group.c, dbfile.c, getlogin.c | `/etc/passwd` and `/etc/group` only, no NSS; `getlogin` reads `/proc/self/loginuid`; no `_r` lookups |
| System information | `uname`, `gethostname`, `sysconf`, `pathconf`, `getpagesize`, `getdtablesize`, resource limits, priorities | utsname.c, sysconf.c, resource.c | only the `_SC_*`/`_PC_*` names in `unistd.h` |
| Terminals | `termios.h`, `ioctl`, the `tc*` and `cf*` calls, `ttyname` | termios.c, ioctl.c, ttyname.c | old `Bnnn` speed codes; `ttyname` reads `/proc/self/fd` |
| Headers | `stdint.h`, `inttypes.h`, `stddef.h`, `stdbool.h`, `stdarg.h`, `limits.h`, `features.h`, `sys/*.h`, `alloca.h` | include/ | all 64-bit types are `long`; no `PRI*`/`SCN*`; `features.h` is empty; `alloca.h` declares `alloca` but nothing defines it |
| assert, getopt | `assert`, `getopt` | assert.c, getopt.c | `getopt`: short options, no permutation |

## Rules every interface follows

**No threads.** `errno` is one global, and `strerror`, `strsignal`, the
calendar functions, the user and group lookups, `ttyname`, `getlogin` and
the printf and strtod digit buffers use static storage. None is
async-signal-safe: a handler should only `write`, `_exit` or set a
`sig_atomic_t`.

**Declare only what exists.** Under C90 an undeclared function returns
`int`, so a call to an undeclared function that returns a pointer is
truncated to 32 bits. The first Forth-built cc1 crashed that way on every
variable-length array: `tree-eh.c` called `bsearch`, which the headers did
not declare, and libiberty's object satisfied the link. Headers therefore
declare exactly the implemented interfaces, and
`chain/gcc-direct/census.sh` builds cc1 with
`-Werror=implicit-function-declaration`.

**Buffering and exit.** A stream picks its mode at its first I/O:
line-buffered when `TCGETS` succeeds on its descriptor, fully buffered
otherwise, `stderr` unbuffered. `exit` runs the exit handlers newest first,
flushes every output stream, then makes the exit system call. `_exit`,
`_Exit` and `abort` flush nothing.

**Nonlocal jumps.** Flex 2.5.11 needs `setjmp` and `longjmp`, which the
compiler's Forth runtime emits. `jmp_buf` is eight `long`s: the six preserved
registers, the caller's RSP and the continuation RIP. Only the C90 `setjmp`
contexts are supported: the whole controlling expression of `if`, `switch`
or a loop, alone, negated by `!` or compared with an integer constant; or a
whole expression statement. The function that called `setjmp` must still be
active when `longjmp` runs.

**One locale.** The C/POSIX locale with ASCII is the only one; every wide or
multibyte function treats bytes 0-127 as characters and rejects the rest
with `EILSEQ`.

**Linking.** The driver archives every `.c` file here except `math.c`, which
it builds only for `-lm`. Functions that programs often bring themselves
(`creat`, `ftruncate`, `dirfd`, `mkfifo` and others) are separate archive
members, so the program's own copy wins.

## Time zones

The zone comes only from a POSIX `TZ` string. Unset, empty, a value starting
with `:`, a zoneinfo name or anything unparsable means UTC; neither
`/etc/localtime` nor a zoneinfo database is read, so build output never
depends on the host's zone. glibc reads `/etc/localtime` when `TZ` is unset.
`calendar.c` documents the accepted grammar and the transition rules.

## Why qsort is musl's

GCC 4.0.4 sorts with comparators that tie: `simplify_plus_minus` in
`simplify-rtx.c` ranks every register the same, and ISO C leaves the order
of equal elements unspecified. Whatever order `qsort` leaves them in becomes
the order cc1 writes them, as in `-112(%rbp,%rdx)` against
`-112(%rdx,%rbp)`: both correct, different bytes. An original heapsort made
GCC built on this runtime differ from GCC built on musl in seven
executables; relinking with musl's smoothsort, and nothing else, made them
identical. That is why `chain/gcc-direct/stage-d.sh` can require stage 2 to
equal stages 3 and 4. `qsort.c` is musl 1.1.24's `src/stdlib/qsort.c` (MIT,
copyright 2011 Valentin Ochs), unchanged except for the one marked
replacement of musl's internal `a_ctz_l`; its upstream sha256 is in
[CREDITS.md](../../../CREDITS.md).

## Why vfork is fork

A real `vfork` child runs on the parent's stack until it execs or exits, and
this compiler cannot promise that the child leaves the parent's frame
intact. POSIX allows `vfork` to be an ordinary `fork`, so it is one.

## Why there is no alloca

The Forth compiler supports no stack `alloca`, and an `alloca.h` that mapped
to libiberty's `C_alloca` would make a runtime header depend on libiberty.
libiberty's `putenv.c` would reference a plain `alloca`; with the runtime's
`putenv`, configure answers `HAVE_PUTENV` and drops that object.

## Configure

Run each package's original configure against these headers; do not reuse
answers from another libc. A stale `HAVE_TIME_H`, for example, makes
libiberty's `getruntime.c` assume one clock tick per second.

## What checks this runtime

- `chain/gcc-direct/census.sh` compiles every cc1 translation unit with
  `-Werror=implicit-function-declaration`.
- `chain/gcc-direct/stage-d.sh` requires GCC 4.0.4 stages 2, 3 and 4 to be
  identical; stage 2 is built against this runtime, stages 3 and 4 against
  musl.
- `kernel/k1/tests/direct-smoke.c` exercises its system calls under K1.
- The full route (`CHECK_CHAIN=1`, `CHECK_K1=linux` in `./check-all.sh`)
  builds every plumbing tool, binutils and GCC on it.
