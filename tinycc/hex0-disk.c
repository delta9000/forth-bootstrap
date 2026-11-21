/* tinycc/hex0-disk.c -- boot 1's last program: write builder-hex0's disk.
 *
 *     hex0-disk OUT STAGE1 STAGE2 LIST
 *
 * OUT becomes the disk image live-bootstrap's lib/generator.py
 * (create_builder_hex0_disk_image) writes: STAGE1, builder-hex0's stage 1
 * as bytes (assembled from its hex0 by hex0-seed in boot 1), then STAGE2,
 * its stage-2 hex0 source as text, zeros up to sector 175 where
 * builder-hex0 starts reading its input, then the items of LIST:
 *     d PATH         "src 0 PATH\n"            a directory
 *     f PATH [NAME]  "src SIZE NAME\n" + bytes  the file PATH (NAME
 *                                               defaults to PATH)
 *     x LINE         "LINE\n"                   a shell command
 * then zeros to a whole sector.  Last, K0's call 248 writes OUT to the
 * drive from sector 0: that drive is the one boot 2 boots.
 *
 * Compiled by the Forth compiler like kernel/tools/amd64-runner.c (int
 * is 64-bit), and runs under K0. */
long syscall3(long number, long a, long b, long c);
long open(char *p, long flags, long mode);
long read(long fd, char *p, long n);
long write(long fd, char *p, long n);
long close(long fd);
void *malloc(long n);
void exit(long n);
long strlen(char *p);

char iobuf[65536];
char zero[512];
char num[24];
long out;
long total;

void fail(char *s) {
    write(2, "hex0-disk: FAIL: ", 17);
    write(2, s, strlen(s));
    write(2, "\n", 1);
    exit(1);
}
void put(char *p, long n) {
    long k;
    total = total + n;
    while (n > 0) {
        k = write(out, p, n);
        if (k <= 0)
            fail("write");
        p = p + k;
        n = n - k;
    }
}
void puts_out(char *s) {
    put(s, strlen(s));
}
void putnum(long v) {
    long i;
    i = 23;
    num[i] = 0;
    do {
        i = i - 1;
        num[i] = '0' + v % 10;
        v = v / 10;
    } while (v);
    puts_out(num + i);
}
/* Copy the file at path to out. */
void copy(char *path) {
    long fd;
    long n;
    fd = open(path, 0, 0);
    if (fd < 0)
        fail(path);
    while (1) {
        n = read(fd, iobuf, 65536);
        if (n < 0)
            fail("read");
        if (!n)
            break;
        put(iobuf, n);
    }
    close(fd);
}
long size_of(char *path) {
    long fd;
    long size;
    fd = open(path, 0, 0);
    if (fd < 0)
        fail(path);
    size = syscall3(8, fd, 0, 2);       /* lseek SEEK_END */
    close(fd);
    return size;
}
void pad(long to) {
    long n;
    while (total < to) {
        n = to - total;
        if (n > 512)
            n = 512;
        put(zero, n);
    }
}
char *slurp(char *path) {
    long size;
    long fd;
    long got;
    long n;
    char *p;
    size = size_of(path);
    p = malloc(size + 1);
    if (!p)
        fail("allocation");
    fd = open(path, 0, 0);
    got = 0;
    while (got < size) {
        n = read(fd, p + got, size - got);
        if (n <= 0)
            fail("read");
        got = got + n;
    }
    close(fd);
    p[size] = 0;
    return p;
}
int main(int ac, char **av) {
    char *p;
    char *line;
    char *path;
    char *name;
    long kind;
    if (ac != 5)
        fail("usage: hex0-disk OUT STAGE1 STAGE2 LIST");
    out = open(av[1], 577, 420);
    if (out < 0)
        fail(av[1]);
    copy(av[2]);
    copy(av[3]);
    if (total > 175 * 512)
        fail("builder-hex0's stages pass sector 175");
    pad(175 * 512);
    p = slurp(av[4]);
    while (*p) {
        line = p;
        while (*p && *p != '\n')
            p = p + 1;
        if (*p) {
            *p = 0;
            p = p + 1;
        }
        kind = line[0];
        if (!kind)
            continue;
        if (line[1] != ' ')
            fail(line);
        path = line + 2;
        if (kind == 'x') {
            puts_out(path);
            puts_out("\n");
        } else if (kind == 'd') {
            puts_out("src 0 ");
            puts_out(path);
            puts_out("\n");
        } else if (kind == 'f') {
            name = path;
            while (*name && *name != ' ')
                name = name + 1;
            if (*name) {
                *name = 0;
                name = name + 1;
            } else
                name = path;
            puts_out("src ");
            putnum(size_of(path));
            puts_out(" ");
            puts_out(name);
            puts_out("\n");
            copy(path);
        } else
            fail(line);
    }
    pad((total + 511) / 512 * 512);
    if (syscall3(248, out, 0, 0) != 0)
        fail("K0 disk write");
    close(out);
    return 0;
}
