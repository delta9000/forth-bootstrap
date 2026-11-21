/* tinycc/hex0-export.c -- boot 2's last program: OUT FILE... writes each
 * FILE to OUT as "src SIZE PATH\n" and its bytes, the record format of
 * builder-hex0's own input stream, then "end\n".  Boot 2 runs it with OUT
 * /dev/hda, which builder-hex0 writes to the drive's first sectors when
 * its stream ends; tests/tinycc/hex0-handoff-check.sh reads the records
 * back and hashes the files on the host.
 *
 * Compiled for i386 in boot 1 by the first tcc against the mes libc that
 * tcc made (tinycc/hex0-handoff.recipe).  Only open, read, write, lseek
 * and close. */
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

char buf[65536];

void put(int fd, char *p, int n)
{
	int k;
	while (n > 0) {
		k = write(fd, p, n);
		if (k <= 0)
			exit(2);
		p = p + k;
		n = n - k;
	}
}

void puts_fd(int fd, char *s)
{
	int n;
	n = 0;
	while (s[n])
		n = n + 1;
	put(fd, s, n);
}

void putnum(int fd, int v)
{
	char d[16];
	int i;
	i = 15;
	d[i] = 0;
	do {
		i = i - 1;
		d[i] = '0' + v % 10;
		v = v / 10;
	} while (v);
	puts_fd(fd, d + i);
}

int main(int argc, char **argv)
{
	int out;
	int in;
	int i;
	int size;
	int n;
	if (argc < 3)
		return 1;
	out = open(argv[1], O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (out < 0)
		return 1;
	for (i = 2; i < argc; i = i + 1) {
		in = open(argv[i], O_RDONLY, 0);
		if (in < 0)
			return 3;
		size = lseek(in, 0, 2);       /* SEEK_END */
		lseek(in, 0, 0);               /* SEEK_SET */
		puts_fd(out, "src ");
		putnum(out, size);
		puts_fd(out, " ");
		puts_fd(out, argv[i]);
		puts_fd(out, "\n");
		while (size > 0) {
			n = read(in, buf, 65536);
			if (n <= 0)
				return 4;
			put(out, buf, n);
			size = size - n;
		}
		close(in);
	}
	puts_fd(out, "end\n");
	close(out);
	return 0;
}
