/* direct-smoke.c -- the gcc-seed runtime's system calls under K1.
 *
 * Built by seed-cc inside K1 (kernel/k1/direct-smoke.kaem) and run there; the same
 * source passes on Linux.  Each check prints "ok N name"; the first failure
 * prints "not ok N name" and exits 1.  Run with no arguments; it re-executes
 * itself with "child" to test execve and exit statuses.
 * K1_SMOKE must be "from-kaem" in the environment (kaem sets it). */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#ifdef __SEED_FORTH__
#include <seed-syscall.h>
#else
#include <sys/syscall.h>
#define __seed_syscall6 syscall
#endif

static int n;
static volatile int got_signal;

static void check(int ok, const char *name)
{
    n++;
    if (!ok) {
        printf("not ok %d %s (errno %d)\n", n, name, errno);
        exit(1);
    }
    printf("ok %d %s\n", n, name);
    fflush(stdout);             /* nothing buffered is inherited by fork */
}

/* std; movb $1, (%rdi); cld; ret -- seed-cc has no inline assembly, and
 * the runtime's mmap() takes no PROT_EXEC, so the page for it comes from
 * the mmap system call itself (prot 7 = read, write, exec). */
static const unsigned char df_touch_code[] = { 0xfd, 0xc6, 0x07, 0x01, 0xfc, 0xc3 };

/* A fresh page can fault in while DF is set (musl's backward memmove runs
 * std; rep movsb).  The kernel must still zero it forwards and leave the
 * page below it alone: dirty some pages for the free list, then touch the
 * first byte of each page of a new mapping with DF set. */
static int df_fault_ok(void)
{
    long len = 64 * 4096, i, bad = 0;
    char *code, *p;
    void (*touch)(char *);
    code = (char *)__seed_syscall6(9, 0, 4096, 7, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if ((unsigned long)code >= (unsigned long)-4095)
        return 0;
    memcpy(code, df_touch_code, sizeof df_touch_code);
    touch = (void (*)(char *))code;
    p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED)
        return 0;
    memset(p, 0x5a, len);
    munmap(p, len);
    p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (p == MAP_FAILED)
        return 0;
    for (i = 0; i < len; i += 4096)
        touch(p + i);
    for (i = 0; i < len; i++)
        bad += p[i] != (i % 4096 == 0);
    munmap(p, len);
    munmap(code, 4096);
    return bad == 0;
}

static void on_usr1(int sig)
{
    got_signal = sig;
}

int main(int argc, char **argv)
{
    char buf[4096], cwd[1024], exe[1024];
    struct stat st;
    FILE *f;
    DIR *d;
    struct dirent *e;
    int fd, p[2], status, i, count;
    pid_t pid;
    char *big;
    long r;
    struct timespec t0, t1;
    struct sigaction sa;

    if (argc == 2 && strcmp(argv[1], "child") == 0)
        return 42;

    check(getenv("K1_SMOKE") && strcmp(getenv("K1_SMOKE"), "from-kaem") == 0, "environment from kaem");

    f = fopen("smoke.txt", "w");
    check(f != NULL, "fopen for writing");
    for (i = 0; i < 1000; i++)
        fprintf(f, "line %d %.3f\n", i, i / 8.0);
    check(fclose(f) == 0, "fclose");
    check(stat("smoke.txt", &st) == 0 && st.st_size > 10000 && S_ISREG(st.st_mode), "stat");
    f = fopen("smoke.txt", "r");
    count = 0;
    while (fgets(buf, sizeof buf, f))
        count++;
    fclose(f);
    check(count == 1000 && strcmp(buf, "line 999 124.875\n") == 0, "fgets and printf %f");
    fd = open("smoke.txt", O_RDONLY);
    check(fd >= 0 && lseek(fd, 5, SEEK_SET) == 5 && read(fd, buf, 3) == 3 && memcmp(buf, "0 0", 3) == 0,
          "open, lseek, read");
    close(fd);
    check(rename("smoke.txt", "smoke2.txt") == 0 && access("smoke.txt", F_OK) != 0, "rename");

    check(mkdir("smoke.d", 0755) == 0 && mkdir("smoke.d/a", 0755) == 0 && mkdir("smoke.d/b", 0755) == 0,
          "mkdir");
    d = opendir("smoke.d");
    count = 0;
    while (d && (e = readdir(d)))
        count++;
    check(d && count == 4, "opendir and readdir");
    closedir(d);
    check(getcwd(cwd, sizeof cwd) != NULL && chdir("smoke.d/a") == 0 && getcwd(buf, sizeof buf) != NULL
          && strlen(buf) == strlen(cwd) + (strcmp(cwd, "/") ? 10 : 9) && chdir(cwd) == 0, "getcwd and chdir");
    check(rmdir("smoke.d/a") == 0 && rmdir("smoke.d/b") == 0 && rmdir("smoke.d") == 0, "rmdir");
    check(unlink("smoke2.txt") == 0, "unlink");
    /* rm -r: unlink each name as readdir returns it; the directory is read in
     * several getdents calls, and none may skip a name */
    check(mkdir("smoke.e", 0755) == 0, "mkdir for readdir-unlink");
    for (count = 0; count < 500; count++) {
        sprintf(buf, "smoke.e/a-name-long-enough-to-fill-several-reads-%d", count);
        f = fopen(buf, "w");
        if (f)
            fclose(f);
    }
    d = opendir("smoke.e");
    count = 0;
    while (d && (e = readdir(d))) {
        if (e->d_name[0] == '.')
            continue;
        sprintf(buf, "smoke.e/%s", e->d_name);
        if (unlink(buf) == 0)
            count++;
    }
    if (d)
        closedir(d);
    check(count == 500 && rmdir("smoke.e") == 0, "readdir while unlinking skips nothing");

    r = readlink("/proc/self/exe", exe, sizeof exe - 1);
    check(r > 0 && exe[0] == '/', "readlink /proc/self/exe");
    exe[r] = 0;

    pid = fork();
    if (pid == 0) {
        char *args[3];
        args[0] = exe;
        args[1] = "child";
        args[2] = NULL;
        execv(exe, args);
        _exit(9);
    }
    check(pid > 0 && waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 42,
          "fork, execv, waitpid");

    check(pipe(p) == 0, "pipe");
    pid = fork();
    if (pid == 0) {
        close(p[0]);
        dup2(p[1], 1);
        printf("through the pipe\n");
        fflush(stdout);
        _exit(0);
    }
    close(p[1]);
    count = 0;
    while ((r = read(p[0], buf + count, sizeof buf - 1 - count)) > 0)
        count += r;
    buf[count] = 0;
    close(p[0]);
    waitpid(pid, &status, 0);
    check(strcmp(buf, "through the pipe\n") == 0 && WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "pipe, dup2 and fork");

    big = malloc(64 << 20);
    check(big != NULL, "malloc 64 MiB");
    for (i = 0; i < 64 << 20; i += 4096)
        big[i] = (char)i;
    big = realloc(big, 128 << 20);
    check(big != NULL && big[4096 * 3] == (char)(4096 * 3), "realloc 128 MiB keeps contents");
    free(big);
    big = mmap(NULL, 1 << 20, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    check(big != MAP_FAILED && big[12345] == 0 && munmap(big, 1 << 20) == 0, "mmap and munmap");

    check(df_fault_ok(), "page fault with DF set zeroes the page forwards");

    check(clock_gettime(CLOCK_MONOTONIC, &t0) == 0, "clock_gettime");
    for (i = 0; i < 1000000; i++)
        got_signal += 0;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    check(t1.tv_sec > t0.tv_sec || (t1.tv_sec == t0.tv_sec && t1.tv_nsec >= t0.tv_nsec), "time moves forward");
    check(time(NULL) > 1000000000, "time");

    memset(&sa, 0, sizeof sa);
    sa.sa_handler = on_usr1;
    sigemptyset(&sa.sa_mask);
    check(sigaction(SIGUSR1, &sa, NULL) == 0 && kill(getpid(), SIGUSR1) == 0 && got_signal == SIGUSR1,
          "sigaction and kill");

    printf("direct-smoke: all %d checks passed\n", n);
    return 0;
}
