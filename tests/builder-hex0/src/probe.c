/* probe.c -- builder-hex0 kernel behaviour probes.  i386, freestanding,
   int 0x80 only (start.S).  Every result goes to fd 1 (the console). */
typedef unsigned int u32;
typedef unsigned long long u64;
long sc(long n, long a, long b, long c, long d, long e, long f);
long canary(long depth, long pattern, long n, long a, long b, long c);
u64 rdtsc64(void);
u32 read_cr0(void);
u32 get_esp(void);
extern u32 entry_regs[12];
extern u32 post_regs[6];
extern u32 canary_count, canary_eax;
extern char edata_mark[], end_mark[], _start[];

#define S1 0x11111111
#define S2 0x22222222
#define S3 0x33333333
#define S4 0x44444444
#define S5 0x55555555
#define S6 0x66666666

static long slen(const char *s) { long n = 0; while (s[n]) n++; return n; }
static void out(const char *s) { sc(4, 1, (long)s, slen(s), S4, S5, S6); }
static void outn(const char *s, long n) { sc(4, 1, (long)s, n, S4, S5, S6); }
static void hex(u32 v) {
    char b[11]; int i; b[0] = '0'; b[1] = 'x';
    for (i = 0; i < 8; i++) b[2 + i] = "0123456789abcdef"[(v >> (28 - 4 * i)) & 15];
    b[10] = 0; out(b);
}
static void dec(long v) {
    char b[24]; int i = 23; int neg = v < 0; unsigned long u = neg ? -(unsigned long)v : v;
    b[i] = 0;
    do { b[--i] = '0' + u % 10; u /= 10; } while (u);
    if (neg) b[--i] = '-';
    out(b + i);
}
static void kv(const char *k, u32 v) { out(k); out("="); hex(v); out(" ("); dec((long)v); out(")\n"); }
static int seq(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a == *b; }
static void mset(void *p, int c, u32 n) { char *q = p; while (n--) *q++ = c; }
static void mcpy(void *d, const void *s, u32 n) { char *q = d; const char *r = s; while (n--) *q++ = *r++; }

/* Report which of ebx..ebp the last sc() got back changed.  in = what was passed. */
static void clob_from(const u32 *pr, long a, long b, long c, long d, long e, long f) {
    long in[6]; int i; const char *nm[6] = {"ebx", "ecx", "edx", "esi", "edi", "ebp"}; int any = 0;
    in[0] = a; in[1] = b; in[2] = c; in[3] = d; in[4] = e; in[5] = f;
    for (i = 0; i < 6; i++)
        if ((long)pr[i] != in[i]) {
            if (!any) out(" clobbered:");
            any = 1;
            out(" "); out(nm[i]); out("->"); hex(pr[i]);
        }
    if (!any) out(" regs-preserved");
}
#define clob(a, b, c, d, e, f) clob_from(snap, a, b, c, d, e, f)
static u32 snap[6];
/* call, print "name ret=… clobbered…" */
static long call(const char *name, long n, long a, long b, long c, long d, long e, long f) {
    long r = sc(n, a, b, c, d, e, f);
    mcpy(snap, post_regs, 24);
    out(name); out(" ret="); hex(r); out(" ("); dec(r); out(")");
    clob(a, b, c, d, e, f); out("\n");
    return r;
}
#define O_RDONLY 0
#define O_WRONLY 1
#define O_RDWR 2
#define O_CREAT 0x40
#define O_TRUNC 0x200
static long sopen(const char *p, long fl) { return sc(5, (long)p, fl, 0644, S4, S5, S6); }
static long swrite(long fd, const void *p, long n) { return sc(4, fd, (long)p, n, S4, S5, S6); }
static long sread(long fd, void *p, long n) { return sc(3, fd, (long)p, n, S4, S5, S6); }
static long sclose(long fd) { return sc(6, fd, S2, S3, S4, S5, S6); }
static long slseek(long fd, long off, long wh) { return sc(19, fd, off, wh, S4, S5, S6); }
static long sbrk(long v) { return sc(45, v, S2, S3, S4, S5, S6); }
static void sexit(long c) { sc(1, c, 0, 0, 0, 0, 0); }

static char buf[4096];
/* print the whole of a file as text, with its length */
static void showfile(const char *p) {
    long fd = sopen(p, O_RDONLY), n, len;
    out("  "); out(p); out(": open="); dec(fd);
    if (fd < 0) { out("\n"); return; }
    len = slseek(fd, 0, 2); slseek(fd, 0, 0);
    out(" len(SEEK_END)="); dec(len);
    mset(buf, '?', 200);
    n = sread(fd, buf, 200);
    out(" read="); dec(n); out(" bytes=[");
    { long i; for (i = 0; i < n; i++) { char c = buf[i]; if (c >= 32 && c < 127) outn(&c, 1); else { out("\\x"); { char h[3]; h[0] = "0123456789abcdef"[(c >> 4) & 15]; h[1] = "0123456789abcdef"[c & 15]; h[2] = 0; out(h); } } } }
    out("]\n");
    sclose(fd);
}

/* ---------------------------------------------------------------- */
static char bssbig[0x30000];    /* > 0x20000 so memsz end is past filesz end + 0x20000 */
static int datavar = 0x1234;

static void t_unimpl(void) {
    static char st[256];
    u32 i; int same;
    out("== unimpl begin\n");
    /* a file to name */
    { long fd = sopen("/u1", O_WRONLY | O_CREAT); swrite(fd, "hello", 5); sclose(fd); }
    call("mmap(90,ebx=0)", 90, 0, S2, S3, S4, S5, S6);
    { static u32 args[6] = {0, 4096, 3, 0x22, -1, 0}; call("mmap(90,old_mmap struct)", 90, (long)args, S2, S3, S4, S5, S6); }
    call("mmap2(192,0,4096,3,0x22,-1,0)", 192, 0, 4096, 3, 0x22, -1, 0);
    call("munmap(91)", 91, 0x10000000, 4096, S3, S4, S5, S6);
    call("dup2(63,4,0)", 63, 4, 0, S3, S4, S5, S6);
    call("dup(41,1)", 41, 1, S2, S3, S4, S5, S6);
    call("unlink(10,/u1)", 10, (long)"/u1", S2, S3, S4, S5, S6);
    showfile("/u1");
    call("rename(38,/u1,/u2)", 38, (long)"/u1", (long)"/u2", S3, S4, S5, S6);
    showfile("/u1"); showfile("/u2");
    mset(st, 0xAA, 256);
    call("lstat(107,/u1,st)", 107, (long)"/u1", (long)st, S3, S4, S5, S6);
    for (same = 1, i = 0; i < 256; i++) if ((unsigned char)st[i] != 0xAA) same = 0;
    out("  lstat buffer unchanged="); dec(same); out("\n");
    mset(st, 0xAA, 256);
    call("lstat(107,/nonexistent,st)", 107, (long)"/nonexistent", (long)st, S3, S4, S5, S6);
    call("stat(106,/nonexistent,st)", 106, (long)"/nonexistent", (long)st, S3, S4, S5, S6);
    call("lstat64(196,/nonexistent,st)", 196, (long)"/nonexistent", (long)st, S3, S4, S5, S6);
    call("stat64(195,/nonexistent,st)", 195, (long)"/nonexistent", (long)st, S3, S4, S5, S6);
    call("fstat64(197,1,st)", 197, 1, (long)st, S3, S4, S5, S6);
    for (same = 1, i = 0; i < 256; i++) if ((unsigned char)st[i] != 0xAA) same = 0;
    out("  stat buffers unchanged="); dec(same); out("\n");
    { long fd = sopen("/", O_RDONLY); out("  open(/)="); dec(fd); out("\n");
      call("getdents(141,fd,st,256)", 141, fd, (long)st, 256, S4, S5, S6);
      call("getdents64(220,fd,st,256)", 220, fd, (long)st, 256, S4, S5, S6);
      for (same = 1, i = 0; i < 256; i++) if ((unsigned char)st[i] != 0xAA) same = 0;
      out("  getdents buffer unchanged="); dec(same); out("\n"); }
    call("chmod(15,/u1,0755)", 15, (long)"/u1", 0755, S3, S4, S5, S6);
    call("rmdir(40,/nonexistent)", 40, (long)"/nonexistent", S2, S3, S4, S5, S6);
    call("getpid(20)", 20, S1, S2, S3, S4, S5, S6);
    call("ioctl(54,1,TCGETS,st)", 54, 1, 0x5401, (long)st, S4, S5, S6);
    call("uname(122,st)", 122, (long)st, S2, S3, S4, S5, S6);
    call("clock_gettime(265,0,st)", 265, 0, (long)st, S3, S4, S5, S6);
    call("pipe(42,st)", 42, (long)st, S2, S3, S4, S5, S6);
    call("exit_group(252,9) [should not exit if unimplemented]", 252, 9, S2, S3, S4, S5, S6);
    /* aliasing: only al is compared */
    call("sys 0x104=260 (al=4 write) fd1 'ALIAS\\n'", 0x104, 1, (long)"ALIAS\n", 6, S4, S5, S6);
    call("sys 0x121=289 (al=0x21 access) /u1", 0x121, (long)"/u1", 0, S3, S4, S5, S6);
    call("sys 0x121=289 (al=0x21 access) /nonexistent", 0x121, (long)"/nonexistent", 0, S3, S4, S5, S6);
    call("openat(295=0x127, al=0x27 mkdir?) ebx=\"/u3\"", 295, (long)"/u3", (long)"/u3", O_RDONLY, S4, S5, S6);
    call("  access(33,/u3)", 33, (long)"/u3", 0, S3, S4, S5, S6);
    /* implemented calls: clobbers */
    out("-- implemented calls, register clobbers\n");
    call("access(33,/u1)", 33, (long)"/u1", 0, S3, S4, S5, S6);
    call("access(33,/nonexistent)", 33, (long)"/nonexistent", 0, S3, S4, S5, S6);
    { long fd = call("open(5,/u4,O_WRONLY|O_CREAT)", 5, (long)"/u4", O_WRONLY | O_CREAT, 0644, S4, S5, S6);
      call("write(4,fd,'x',1) to file", 4, fd, (long)"x", 1, S4, S5, S6);
      call("write(4,1,'y\\n',2) to console", 4, 1, (long)"y\n", 2, S4, S5, S6);
      call("lseek(19,fd,0,0)", 19, fd, 0, 0, S4, S5, S6);
      call("close(6,fd)", 6, fd, S2, S3, S4, S5, S6);
      fd = sopen("/u4", O_RDONLY);
      call("read(3,fd,buf,10)", 3, fd, (long)buf, 10, S4, S5, S6);
      call("close(6,fd)", 6, fd, S2, S3, S4, S5, S6); }
    call("mkdir(39,/ud)", 39, (long)"/ud", 0755, S3, S4, S5, S6);
    call("chdir(12,/ud)", 12, (long)"/ud", S2, S3, S4, S5, S6);
    call("getcwd(183,buf,256)", 183, (long)buf, 256, S3, S4, S5, S6);
    out("  cwd="); out(buf); out("\n");
    call("chdir(12,/nonexistent)", 12, (long)"/nonexistent", S2, S3, S4, S5, S6);
    call("chdir(12,/u1) (non-empty file)", 12, (long)"/u1", S2, S3, S4, S5, S6);
    call("chdir(12,/)", 12, (long)"/", S2, S3, S4, S5, S6);
    call("brk(45,0)", 45, 0, S2, S3, S4, S5, S6);
    out("== unimpl end\n");
}

static void t_brk(char **argv) {
    u32 b0, t, i, nz; volatile unsigned char *p;
    u32 targets[3]; const char *tn[3] = {"64MB", "256MB", "600MB"};
    out("== brk begin\n");
    kv("_start", (u32)_start);
    kv("file end (edata_mark, = vaddr+filesz)", (u32)edata_mark);
    kv("memsz end (end_mark)", (u32)end_mark);
    b0 = sbrk(0);
    kv("brk(0) initial", b0);
    kv("brk - file end", b0 - (u32)edata_mark);
    kv("brk - memsz end", b0 - (u32)end_mark);
    for (nz = 0, i = 0; i < sizeof bssbig; i++) nz += bssbig[i] != 0;
    kv("nonzero bytes in bss (0x30000 array)", nz);
    for (nz = 0, p = (unsigned char *)end_mark; p < (unsigned char *)b0; p++) nz += *p != 0;
    kv("nonzero bytes between memsz end and brk", nz);
    /* above-brk memory is plain RAM: write and read back */
    p = (unsigned char *)(b0 + 0x1000); *p = 0x5A;
    kv("byte written at brk+0x1000 reads back", *p);
    p = (unsigned char *)0x20000000; *p = 0x6B;
    kv("byte written at 0x20000000 (above brk) reads back", *p);
    targets[0] = 0x08048000 + 64u * 1024 * 1024;
    targets[1] = 0x08048000 + 256u * 1024 * 1024;
    targets[2] = 0x08048000 + 600u * 1024 * 1024;
    for (t = 0; t < 3; t++) {
        u32 cur = sbrk(0), r; u64 c0, c1;
        /* dirty every 4 KiB page of [cur, target) and its last byte */
        for (p = (unsigned char *)cur; p < (unsigned char *)targets[t]; p += 4096) *p = 0xA5;
        *(unsigned char *)(targets[t] - 1) = 0xA5;
        c0 = rdtsc64();
        r = sbrk(targets[t]);
        c1 = rdtsc64();
        out("brk("); out(tn[t]); out(" = "); hex(targets[t]); out(") ret="); hex(r);
        out(" tsc-cycles="); dec((long)((c1 - c0) / 1000)); out("k\n");
        kv("  brk(0) now", sbrk(0));
        for (nz = 0, p = (unsigned char *)cur; p < (unsigned char *)targets[t]; p++) nz += *p != 0;
        kv("  nonzero bytes in [old brk, new brk) after growth (was dirtied)", nz);
    }
    kv("brk(current) ret", sbrk(sbrk(0)));
    kv("brk(0) after brk(current)", sbrk(0));
    /* past the 670 MB process area: into the saved-process area where this
       process's argv strings were copied */
    out("argv[0] before = '"); out(argv[0]); out("' at "); hex((u32)argv[0]); out("\n");
    kv("brk(0x30001000) ret", sbrk(0x30001000));
    out("argv[0] after = '"); out(argv[0]); out("' strlen="); dec(slen(argv[0])); out("\n");
    out("== brk end\n");
}

static volatile u32 g_data = 0;   /* .bss: here above the initial brk (bss overlap) */
static volatile u32 g_below = 0x77; /* .data: below brk */
static char *child_argv[3] = {"/probe", "child", 0};
static char *child_env[2] = {"CHILD=1", 0};
#define ABOVE_BRK_OFF 0x10000
#define FAR_ADDR 0x20000000u

static void t_fork(char **envp) {
    volatile u32 stackvar = 0;
    volatile u32 *above, *far = (volatile u32 *)FAR_ADDR, *belowesp;
    u32 b, st; long r;
    out("== fork begin\n");
    b = sbrk(0);
    above = (volatile u32 *)(b + ABOVE_BRK_OFF);
    belowesp = (volatile u32 *)(get_esp() - 0x2000);
    g_data = 0x1111; g_below = 0x1111; *above = 0x1111; *far = 0x1111; stackvar = 0x1111; *belowesp = 0x1111;
    kv("parent brk", b);
    kv("&g_data (bss)", (u32)&g_data); kv("&g_below (data)", (u32)&g_below); kv("above(brk+0x10000)", (u32)above); kv("far", FAR_ADDR);
    kv("&stackvar", (u32)&stackvar); kv("belowesp(esp-0x2000)", (u32)belowesp);
    r = sc(2, S1, S2, S3, S4, S5, S6);
    if (r == 0) {
        mcpy(snap, post_regs, 24);
        out("child: fork ret=0"); clob(S1, S2, S3, S4, S5, S6); out("\n");
        kv("child sees g_data", g_data); kv("child sees g_below", g_below); kv("child sees above", *above); kv("child sees far", *far);
        kv("child sees stackvar", stackvar); kv("child sees belowesp", *belowesp);
        kv("child brk(0)", sbrk(0));
        g_data = 0x2222; g_below = 0x2222; *above = 0x2222; *far = 0x2222; stackvar = 0x2222; *belowesp = 0x2222;
        out("child wrote 0x2222 everywhere; execve /probe child\n");
        r = sc(11, (long)"/probe", (long)child_argv, (long)child_env, S4, S5, S6);
        out("child: execve returned "); dec(r); out("\n");
        sexit(99);
    }
    mcpy(snap, post_regs, 24);
    out("parent: fork ret="); dec(r); clob(S1, S2, S3, S4, S5, S6); out("\n");
    kv("parent sees g_data (bss, above brk)", g_data); kv("parent sees g_below (data, below brk)", g_below); kv("parent sees above", *above); kv("parent sees far", *far);
    kv("parent sees stackvar", stackvar); kv("parent sees belowesp", *belowesp);
    kv("parent brk(0) after child", sbrk(0));
    st = 0xDEADBEEF;
    call("waitpid(7,-1,&st,0)", 7, -1, (long)&st, 0, S4, S5, S6);
    kv("  status", st);
    /* second child: exit code 300, collected by wait4 */
    r = sc(2, 0, 0, 0, 0, 0, 0);
    if (r == 0) {
        static char *a2[3] = {"/probe", "exit300", 0};
        sc(11, (long)"/probe", (long)a2, (long)child_env, 0, 0, 0);
        sexit(98);
    }
    out("parent: second fork ret="); dec(r); out("\n");
    st = 0xDEADBEEF;
    call("wait4(114,-1,&st,0,0)", 114, -1, (long)&st, 0, 0, S5, S6);
    kv("  status", st);
    st = 0xDEADBEEF;
    call("waitpid(7,-1,&st,0) after wait4", 7, -1, (long)&st, 0, S4, S5, S6);
    kv("  status", st);
    /* third child: exit 0 */
    r = sc(2, 0, 0, 0, 0, 0, 0);
    if (r == 0) {
        static char *a3[3] = {"/probe", "exit0", 0};
        sc(11, (long)"/probe", (long)a3, (long)child_env, 0, 0, 0);
        sexit(97);
    }
    st = 0xDEADBEEF;
    call("waitpid(7,-1,&st,0) child exit 0", 7, -1, (long)&st, 0, S4, S5, S6);
    kv("  status", st);
    /* execve of a missing program, in a child */
    out("== fork end\n");
}

static void t_child(char **argv) {
    volatile u32 *above = (volatile u32 *)0, *far = (volatile u32 *)FAR_ADDR;
    out("[child program] brk(0)="); hex(sbrk(0)); out("\n");
    { u32 fl; __asm__ volatile("pushf; pop %0" : "=r"(fl)); out("[child program] eflags after console writes="); hex(fl); out(" IF="); dec((fl >> 9) & 1); out("\n"); }
    kv("[child program] g_data (fresh image)", g_data);
    kv("[child program] value at far before write", *far);
    *far = 0x3333;
    /* also write just above where the parent's brk will be: the parent
       reported it; use the same image so the same brk */
    above = (volatile u32 *)(sbrk(0) + ABOVE_BRK_OFF);
    kv("[child program] value at above before write", *above);
    *above = 0x3333;
    kv("[child program] g_below (fresh image)", g_below);
    g_data = 0x3333; g_below = 0x3333;
    out("[child program] wrote 0x3333 to far, above, g_data, g_below; exit 42\n");
    sexit(42);
}

static void scan_below(u32 esp, u32 n) {
    u32 i, z = 0, cc = 0, other = 0, first = 0; unsigned char *p = (unsigned char *)(esp - n);
    for (i = 0; i < n; i++) { if (p[i] == 0) z++; else if (p[i] == 0xCC) cc++; else { other++; if (!first) first = esp - (u32)(p + i); } }
    out("  stack below entry esp, "); dec(n); out(" bytes: zero="); dec(z); out(" 0xCC(parent fill)="); dec(cc);
    out(" other="); dec(other); out(" (highest non-zero/non-CC at esp-"); dec(first); out(")\n");
}

static void t_entry(int argc, char **argv, char **envp) {
    const char *rn[12] = {"eax", "ebx", "ecx", "edx", "esi", "edi", "ebp", "esp", "eflags", "cs", "ss", "ds"};
    int i; u32 esp = entry_regs[7];
    out("== entry begin ("); out(argv[1]); out(")\n");
    { u32 fl; __asm__ volatile("pushf; pop %0" : "=r"(fl)); out("  eflags after a console write="); hex(fl); out(" IF="); dec((fl >> 9) & 1); out("\n"); }
    for (i = 0; i < 12; i++) { out("  entry "); out(rn[i]); out("="); hex(entry_regs[i]); out("\n"); }
    out("  eflags.IF="); dec((entry_regs[8] >> 9) & 1); out(" IOPL="); dec((entry_regs[8] >> 12) & 3); out("\n");
    out("  argc="); dec(argc); out("\n");
    for (i = 0; i < argc; i++) {
        out("  argv["); dec(i); out("]="); hex((u32)argv[i]); out(" strlen="); dec(slen(argv[i]));
        out(" text='"); outn(argv[i], slen(argv[i]) > 40 ? 40 : slen(argv[i])); out(slen(argv[i]) > 40 ? "...'" : "'");
        if (slen(argv[i]) > 40) { out(" last 8='"); out(argv[i] + slen(argv[i]) - 8); out("'"); }
        out("\n");
    }
    out("  argv[argc]="); hex((u32)argv[argc]); out("\n");
    for (i = 0; envp[i]; i++) { out("  envp["); dec(i); out("]="); hex((u32)envp[i]); out(" '"); out(envp[i]); out("'\n"); }
    out("  envp count="); dec(i); out("\n");
    out("  stack words from esp: ");
    for (i = 0; i < 12; i++) { hex(((u32 *)esp)[i]); out(" "); }
    out("\n");
    scan_below(esp, 65536);
    scan_below(esp, 1024);
    out("== entry end\n");
}

static char longarg[301];
static void t_exec(int fork_first) {
    char *av[6]; char *ev[4]; long r; u32 esp; volatile unsigned char *p;
    int i;
    out(fork_first ? "== execfork begin\n" : "== execoverlay begin\n");
    for (i = 0; i < 300; i++) longarg[i] = 'L';
    longarg[299] = 'E'; longarg[300] = 0;
    av[0] = "/probe"; av[1] = fork_first ? "entry-forked" : "entry-overlay"; av[2] = "a"; av[3] = longarg; av[4] = "zz"; av[5] = 0;
    ev[0] = "E0=zero"; ev[1] = "E1=one"; ev[2] = "E2=two"; ev[3] = 0;
    /* fill 64 KiB below our esp with 0xCC so leftovers are visible */
    esp = get_esp();
    for (p = (unsigned char *)(esp - 256 - 65536 * 2); p < (unsigned char *)(esp - 256); p++) *p = 0xCC;
    if (fork_first) {
        r = sc(2, 0, 0, 0, 0, 0, 0);
        if (r == 0) { sc(11, (long)"/probe", (long)av, (long)ev, 0, 0, 0); sexit(96); }
        { u32 st = 0; sc(7, -1, (long)&st, 0, 0, 0, 0); out("parent: child status "); hex(st); out("\n"); }
        out("== execfork end\n");
    } else {
        sc(11, (long)"/probe", (long)av, (long)ev, 0, 0, 0);
        out("execve returned!\n");
    }
}

static void t_execmissing(void) {
    long r; static char *ev[2] = {"E=1", 0};
    out("== execmissing begin\n");
    /* execve of a program that does not exist */
        r = sc(2, 0, 0, 0, 0, 0, 0);
        if (r == 0) {
            static char *bad[3] = {"/nonexistent", "x", 0};
            out("child: access(/nonexistent)="); dec(sc(33, (long)"/nonexistent", 0, 0, 0, 0, 0)); out("; execve(/nonexistent) next\n");
            r = sc(11, (long)"/nonexistent", (long)bad, (long)ev, 0, 0, 0);
            out("child: execve(/nonexistent) returned "); dec(r); out("\n");
            sexit(95);
        }
    out("parent: after execve(/nonexistent) child, fork ret="); dec(r); out("\n");
    out("== execmissing end\n");
}

static void t_files(void) {
    long fd, fd2, r;
    out("== files begin\n");
    out("-- open missing\n");
    kv("open(/missing, O_RDONLY)", sopen("/missing", O_RDONLY));
    kv("open(/missing, O_WRONLY)", sopen("/missing", O_WRONLY));
    kv("open(/missing, O_RDWR|O_TRUNC)", sopen("/missing", O_RDWR | O_TRUNC));
    fd = sopen("/missing", O_WRONLY | O_CREAT | O_TRUNC); kv("open(/missing, O_WRONLY|O_CREAT|O_TRUNC)", fd); sclose(fd);
    kv("open(/nodir/x, O_WRONLY|O_CREAT)", sopen("/nodir/x", O_WRONLY | O_CREAT));
    kv("open(/nodir/x, O_RDONLY)", sopen("/nodir/x", O_RDONLY));
    kv("open(/a/b/c, O_WRONLY|O_CREAT)", sopen("/a/b/c", O_WRONLY | O_CREAT));
    kv("mkdir(/a)", sc(39, (long)"/a", 0755, 0, 0, 0, 0));
    kv("open(/a/b/c, O_WRONLY|O_CREAT) after mkdir /a only", sopen("/a/b/c", O_WRONLY | O_CREAT));
    kv("mkdir(/a/b/c/d) (parents missing)", sc(39, (long)"/a/b/c/d", 0755, 0, 0, 0, 0));
    kv("open(relname, O_WRONLY|O_CREAT) with cwd /", fd = sopen("relname", O_WRONLY | O_CREAT)); sclose(fd);
    kv("access(/relname)", sc(33, (long)"/relname", 0, 0, 0, 0, 0));
    kv("open(/a/../relname, O_RDONLY)", fd = sopen("/a/../relname", O_RDONLY)); sclose(fd);
    out("-- fd numbering\n");
    fd = sopen("/missing", O_RDONLY); fd2 = sopen("/missing", O_RDONLY);
    kv("first fd", fd); kv("second fd", fd2);
    sclose(fd); kv("after close(first), next open fd", fd = sopen("/missing", O_RDONLY));
    sclose(fd); sclose(fd2);
    kv("close(77) (never opened)", sclose(77));
    kv("read(77,...) (never opened)", sread(77, buf, 4));

    out("-- grow a file that is not the newest\n");
    fd = sopen("/fa", O_WRONLY | O_CREAT | O_TRUNC); swrite(fd, "AAAAAAAAAA", 10); sclose(fd);
    fd = sopen("/fb", O_WRONLY | O_CREAT | O_TRUNC); swrite(fd, "BBBBBBBBBB", 10); sclose(fd);
    showfile("/fa"); showfile("/fb");
    fd = sopen("/fa", O_WRONLY); kv("reopen /fa O_WRONLY (no O_CREAT)", fd);
    kv("lseek(/fa,0,SEEK_END)", slseek(fd, 0, 2));
    kv("write 'aaaaa'", swrite(fd, "aaaaa", 5)); sclose(fd);
    showfile("/fa"); showfile("/fb");
    fd = sopen("/fc", O_WRONLY | O_CREAT); swrite(fd, "CCCC", 4); sclose(fd);
    out(" after creating /fc with CCCC:\n");
    showfile("/fa"); showfile("/fb"); showfile("/fc");
    out("-- overwrite in place without O_CREAT\n");
    fd = sopen("/fb", O_WRONLY); swrite(fd, "bb", 2); sclose(fd);
    showfile("/fb");
    out("-- O_CREAT on an existing name\n");
    fd = sopen("/fb", O_WRONLY | O_CREAT); kv("open(/fb, O_CREAT) fd", fd); sclose(fd);
    showfile("/fb");

    out("-- lseek past end, then write\n");
    fd = sopen("/fd", O_RDWR | O_CREAT | O_TRUNC); swrite(fd, "0123456789", 10);
    kv("lseek(fd,100,SEEK_SET)", slseek(fd, 100, 0));
    kv("write 'X'", swrite(fd, "X", 1));
    kv("lseek(fd,0,SEEK_CUR)", slseek(fd, 0, 1));
    kv("lseek(fd,0,SEEK_END)", slseek(fd, 0, 2));
    sclose(fd);
    { /* newest file named /fd in the kernel's name table (0x200000, 1 KiB each),
         its address from the descriptor table (0x01000000, 16 bytes, address at +4) */
      u32 n = *(u32 *)0x8303, idx, addr; int i;
      for (idx = n - 1; idx > 2; idx--) if (seq((char *)(0x200000 + idx * 0x400), "/fd")) break;
      addr = *(u32 *)(0x01000000 + idx * 16 + 4);
      out("  /fd: file index="); dec(idx); out(" address="); hex(addr); out(" length(table)="); dec(*(u32 *)(0x01000000 + idx * 16 + 8));
      out(" bytes at address+9..+11:"); for (i = 9; i < 12; i++) { out(" "); hex(((unsigned char *)addr)[i]); }
      out(" byte at address+100="); hex(((unsigned char *)addr)[100]); out("\n");
      kv("  next_file_address (0x8307)", *(u32 *)0x8307); }
    showfile("/fd");
    fd = sopen("/fe", O_WRONLY | O_CREAT); swrite(fd, "e", 1); sclose(fd);
    showfile("/fd"); showfile("/fe");
    out("-- lseek beyond end and read\n");
    fd = sopen("/fa", O_RDONLY);
    kv("lseek(/fa,1000,SEEK_SET)", slseek(fd, 1000, 0)); kv("read 4", sread(fd, buf, 4));
    kv("lseek(/fa,-5,SEEK_SET)", slseek(fd, -5, 0)); 
    kv("read at end: lseek(0,SEEK_END)", slseek(fd, 0, 2)); kv("read 4 at EOF", sread(fd, buf, 4));
    sclose(fd);

    out("-- close and reopen, position\n");
    fd = sopen("/fa", O_RDONLY); mset(buf, 0, 8); r = sread(fd, buf, 3);
    out("  read 3 -> "); dec(r); out(" '"); out(buf); out("'\n");
    kv("  lseek(SEEK_CUR)", slseek(fd, 0, 1));
    sclose(fd);
    fd = sopen("/fa", O_RDONLY); kv("  reopen fd", fd); kv("  lseek(SEEK_CUR) after reopen", slseek(fd, 0, 1));
    mset(buf, 0, 8); r = sread(fd, buf, 3); out("  read 3 -> "); dec(r); out(" '"); out(buf); out("'\n");
    fd2 = sopen("/fa", O_RDONLY); mset(buf, 0, 8); sread(fd2, buf, 2);
    out("  second simultaneous fd read 2 -> '"); out(buf); out("' (independent offset if 'AA')\n");
    sclose(fd); sclose(fd2);
    out("-- read sizes from a file\n");
    fd = sopen("/fa", O_RDONLY); kv("  read(fd,buf,4096) on 15-byte file", sread(fd, buf, 4096)); sclose(fd);
    out("-- read/write on stdio fds\n");
    kv("  write(2,'e2\\n',3)", swrite(2, "e2\n", 3));
    kv("  write(0,'e0\\n',3)", swrite(0, "e0\n", 3));
    out("-- chdir then relative open\n");
    kv("  mkdir(/w)", sc(39, (long)"/w", 0755, 0, 0, 0, 0));
    kv("  chdir(/w)", sc(12, (long)"/w", 0, 0, 0, 0, 0));
    fd = sopen("rel2", O_WRONLY | O_CREAT); kv("  open(rel2,O_CREAT)", fd); swrite(fd, "r2", 2); sclose(fd);
    kv("  access(/w/rel2)", sc(33, (long)"/w/rel2", 0, 0, 0, 0, 0));
    kv("  getcwd ret", sc(183, (long)buf, 256, 0, 0, 0, 0)); out("  cwd='"); out(buf); out("'\n");
    kv("  chdir(..) from /w", sc(12, (long)"..", 0, 0, 0, 0, 0));
    sc(183, (long)buf, 256, 0, 0, 0, 0); out("  cwd after chdir(..)='"); out(buf); out("'\n");
    kv("  chdir(/) from /w", sc(12, (long)"/", 0, 0, 0, 0, 0));
    sc(183, (long)buf, 256, 0, 0, 0, 0); out("  cwd after chdir(/)='"); out(buf); out("'\n");
    mset(buf, 0xEE, 64);
    kv("  getcwd(buf,2) ret (buffer too small)", sc(183, (long)buf, 2, 0, 0, 0, 0));
    out("  buf after (was 0xee): "); { int i; for (i = 0; i < 8; i++) { hex((unsigned char)buf[i]); out(" "); } } out("\n");
    sc(12, (long)"/", 0, 0, 0, 0, 0);
    out("== files end\n");
}

static void t_stdin(void) {
    char c[64]; long r, i;
    out("== stdin begin\n");
    mset(c, '#', 64);
    r = sread(0, c, 64);
    out("  read(0,buf,64) ret="); dec(r); out(" first byte="); hex((unsigned char)c[0]); out(" buf[1]="); hex((unsigned char)c[1]); out("\n");
    out("  next bytes one call each (ret:byte):");
    for (i = 0; i < 24; i++) { c[0] = '#'; r = sread(0, c, 1); out(" "); dec(r); out(":"); hex((unsigned char)c[0]); }
    out("\n== stdin end\n");
}

static void t_ring(void) {
    u32 fl; long d; u32 i, n;
    out("== ring begin\n");
    kv("cs", entry_regs[9]); kv("cs & 3 (CPL)", entry_regs[9] & 3);
    __asm__ volatile("pushf; pop %0" : "=r"(fl));
    kv("eflags now", fl); kv("IF now", (fl >> 9) & 1);
    kv("cr0 (readable => CPL 0)", read_cr0());
    { long fd = sopen("/cfile", O_RDWR | O_CREAT);
      long rfd;
      struct { const char *name; long n, a, b, c; } t[] = {
        {"write(1,'.',1) console", 4, 1, (long)".", 1},
        {"write(fd,'.',1) file", 4, fd, (long)".", 1},
        {"brk(0)", 45, 0, 0, 0},
        {"getpid (unimplemented)", 20, 0, 0, 0},
        {"open(/cfile,O_RDONLY)", 5, (long)"/cfile", 0, 0},
        {"access(/cfile)", 33, (long)"/cfile", 0, 0},
        {"getcwd(buf,256)", 183, (long)buf, 256, 0},
        {"lseek(fd,0,0)", 19, fd, 0, 0},
        {"read(fd,buf,1) file", 3, fd, (long)buf, 1},
      };
      for (i = 0; i < sizeof t / sizeof t[0]; i++) {
          d = canary(16384, 0xC3, t[i].n, t[i].a, t[i].b, t[i].c);
          out("\n  canary "); out(t[i].name); out(": deepest write below caller esp = "); dec(d);
          out(" bytes, changed bytes="); dec(canary_count); out(" ret="); hex(canary_eax); out("\n");
      }
      (void)rfd;
    }
    /* spin with no syscalls: interrupts on the program's stack? */
    for (n = 1; n <= 4; n++) {
        u64 c0 = rdtsc64(), c1;
        __asm__ volatile("pushf; pop %0" : "=r"(fl));
        d = canary(16384, 0xC3, -1, 4000000000u, 0, 0);
        c1 = rdtsc64();
        out("  spin "); dec(n); out(" (IF="); dec((fl >> 9) & 1); out(", ");
        dec((long)((c1 - c0) / 1000000)); out("M tsc cycles, no syscall): deepest write below esp = ");
        dec(d); out(", changed bytes="); dec(canary_count); out("\n");
    }
    out("== ring end\n");
}

static void t_speed(long n) {
    long fd, i, r; u64 c0, c1; char c = 'x';
    out("== speed begin\n");
    fd = sopen("/spd", O_RDWR | O_CREAT | O_TRUNC);
    out("SPD-WRITE-BEGIN n="); dec(n); out("\n");
    c0 = rdtsc64();
    for (i = 0; i < n; i++) sc(4, fd, (long)&c, 1, 0, 0, 0);
    c1 = rdtsc64();
    out("SPD-WRITE-END tsc="); dec((long)((c1 - c0) / 1000)); out("k\n");
    kv("  length", slseek(fd, 0, 2));
    slseek(fd, 0, 0);
    out("SPD-READ-BEGIN n="); dec(n); out("\n");
    c0 = rdtsc64(); r = 0;
    for (i = 0; i < n; i++) r += sc(3, fd, (long)&c, 1, 0, 0, 0);
    c1 = rdtsc64();
    out("SPD-READ-END tsc="); dec((long)((c1 - c0) / 1000)); out("k got="); dec(r); out("\n");
    out("SPD-NULL-BEGIN n="); dec(n); out("\n");
    c0 = rdtsc64();
    for (i = 0; i < n; i++) sc(20, 0, 0, 0, 0, 0, 0);
    c1 = rdtsc64();
    out("SPD-NULL-END tsc="); dec((long)((c1 - c0) / 1000)); out("k\n");
    out("SPD-CON-BEGIN n=2000\n");
    c0 = rdtsc64();
    for (i = 0; i < 2000; i++) sc(4, 2, (long)".", 1, 0, 0, 0);
    c1 = rdtsc64();
    out("\nSPD-CON-END tsc="); dec((long)((c1 - c0) / 1000)); out("k\n");
    out("== speed end\n");
}

static void t_forknoexec(void) {
    long r; volatile u32 v = 1;
    out("== forknoexec begin\n");
    r = sc(2, 0, 0, 0, 0, 0, 0);
    if (r == 0) { v = 2; out("child (no execve): exiting 7\n"); sexit(7); }
    out("parent resumed: fork ret="); dec(r); out(" v="); dec(v); out("\n");
    out("== forknoexec end\n");
}

extern char irq_handlers[]; extern volatile u32 irq_counts[8];
u32 inb_(u32 port); void outb_(u32 port, u32 v); void sidt_(void *p);
static void pic(const char *when) {
    u32 imr1 = inb_(0x21), imr2 = inb_(0xA1), irr, isr;
    outb_(0x20, 0x0A); irr = inb_(0x20); outb_(0x20, 0x0B); isr = inb_(0x20);
    out("  PIC "); out(when); out(": master IMR="); hex(imr1); out(" slave IMR="); hex(imr2);
    out(" master IRR="); hex(irr); out(" master ISR="); hex(isr); out("\n");
}
static void spin_count(const char *what) {
    u32 i, fl; u64 c0, c1; u32 before[8];
    unsigned char idtr[6]; u32 base; unsigned char *e;
    sidt_(idtr); base = *(u32 *)(idtr + 2);
    for (i = 0; i < 8; i++) {   /* vectors 8..15 -> counting handlers */
        u32 h = (u32)irq_handlers + 16 * i;
        e = (unsigned char *)(base + 8 * (8 + i));
        e[0] = h; e[1] = h >> 8; e[2] = 8; e[3] = 0; e[4] = 0; e[5] = 0x8E; e[6] = h >> 16; e[7] = h >> 24;
    }
    for (i = 0; i < 8; i++) before[i] = irq_counts[i];
    __asm__ volatile("pushf; pop %0" : "=r"(fl));
    c0 = rdtsc64();
    for (i = 0; i < 4000000000u; i++) __asm__ volatile("");
    c1 = rdtsc64();
    out("  spin "); out(what); out(" IF="); dec((fl >> 9) & 1); out(" "); dec((long)((c1 - c0) / 1000000)); out("M tsc: IRQ0..7 counts:");
    for (i = 0; i < 8; i++) { out(" "); dec(irq_counts[i] - before[i]); }
    out("\n");
}
static void t_irq(void) {
    unsigned char idtr[6];
    out("== irq begin\n");
    sidt_(idtr); kv("IDT base", *(u32 *)(idtr + 2)); kv("IDT limit", *(unsigned short *)idtr);
    pic("at start");
    spin_count("1 (no EOI sent)");
    pic("after spin 1");
    outb_(0x20, 0x20);
    out("  sent one non-specific EOI to the master PIC\n");
    spin_count("2 (after EOI)");
    pic("after spin 2");
    out("== irq end\n");
}

static void t_brkdown(void) {
    u32 b = sbrk(0); volatile unsigned char *p;
    out("== brkdown begin\n");
    kv("brk(0)", b);
    { int i; out("bytes at 0x54000000 (first file, /probe):"); for (i = 0; i < 8; i++) { out(" "); hex(((unsigned char *)0x54000000)[i]); } out("\n"); }
    for (p = (unsigned char *)b; p < (unsigned char *)(b + 0x100000); p++) *p = 0x5A;
    kv("pattern 0x5A over [brk, brk+1MiB); brk(brk-4096) next, target", b - 4096);
    kv("brk(brk-4096) ret", sbrk(b - 4096));
    out("== brkdown end (returned)\n");
}

int main(int argc, char **argv, char **envp) {
    const char *m = argc > 1 ? argv[1] : "";
    if (seq(m, "unimpl")) t_unimpl();
    else if (seq(m, "brk")) t_brk(argv);
    else if (seq(m, "fork")) t_fork(envp);
    else if (seq(m, "child")) t_child(argv);
    else if (seq(m, "exit300")) return 300;
    else if (seq(m, "exit0")) return 0;
    else if (seq(m, "entry-shell") || seq(m, "entry-forked") || seq(m, "entry-overlay")) t_entry(argc, argv, envp);
    else if (seq(m, "execoverlay")) t_exec(0);
    else if (seq(m, "execfork")) t_exec(1);
    else if (seq(m, "files")) t_files();
    else if (seq(m, "execmissing")) t_execmissing();
    else if (seq(m, "stdin")) t_stdin();
    else if (seq(m, "ring")) t_ring();
    else if (seq(m, "speed1m")) t_speed(1000000);
    else if (seq(m, "speed10m")) t_speed(10000000);
    else if (seq(m, "forknoexec")) t_forknoexec();
    else if (seq(m, "brkdown")) t_brkdown();
    else if (seq(m, "irq")) t_irq();
    else { out("probe: unknown mode '"); out(m); out("'\n"); return 2; }
    (void)datavar;
    return 0;
}
