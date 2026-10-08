"""Image inventories for the run under K0 and K1: explicit lists, so the
guest reads exactly the repository files named here.

k0_tree(): what K0 needs to build K1 from the seed (tools/k1-direct-start.fth
and tools/k1-direct.recipe); k0/mkfs.py adds seed-forth itself.
k1_tree(smoke, linux): K1's starting tree for k1/direct-smoke.recipe or, without
smoke, k1/direct.recipe (the seed to bash 2.05b): sources, plus hex0-seed (the
only executable, added by k1/mkdisk.py) and, for the full route, the pinned
archives the plumbing stages unpack; with linux, also what
k1/direct-linux.recipe needs after bash 2.05b, and the MANIFEST.sha256
archives it unpacks.  Paths map image names to host files.

The lists were taken from a traced run (every file the host route opens,
strace -y -e trace=open,openat,execve) and from reading the guest stages;
a file missing here fails the run that needs it.  tools/seed-cc-start.fth
lists the compiler layers and runtime/gcc-seed/*.c with getdents64, so
those directories hold exactly the files named here.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# K1 built by seed Forth under K0: tools/k1-direct.recipe and the runner.
K0 = """
010-lib.fth
020-cc-arena.fth
030-cc-io.fth
040-cc-prep.fth
050-cc-lex.fth
060-cc-types.fth
070-cc-sym.fth
080-cc-elf.fth
081-cc-object.fth
090-cc-emit.fth
100-cc-expr.fth
110-cc-decl.fth
112-cc-stmt.fth
114-cc-func.fth
115-cc-native.fth
116-cc-prog.fth
117-cc-native-program.fth
118-cc-native-init.fth
119-cc-native-runtime.fth
120-cc-main.fth
121-cc-sysv.fth
122-cc-sysv-runtime.fth
123-cc-object-program.fth
124-cc-target.fth
125-cc-consteval.fth
126-cc-varargs.fth
127-cc-binary64.fth
128-cc-float-literal.fth
129-cc-bitfield.fth
131-cc-aggregate-abi.fth
132-cc-long-double.fth
140-cc-link.fth
k1/ata.c
k1/boot/asm.fth
k1/boot/k0-syscalls.fth
k1/boot/link.fth
k1/boot/unit.fth
k1/fs.c
k1/k1-asm.fth
k1/k1.h
k1/linux.c
k1/main.c
k1/mm.c
k1/proc.c
k1/sys.c
tools/amd64-runner.c
tools/amd64-syscalls.fth
tools/k1-direct-start.fth
tools/k1-direct.recipe
tools/obj-asm.fth
""".split()

# The seed, seed-cc and seed-ar, kaem, and k1/direct-smoke.kaem.
SMOKE = """
000-seed.hex0
010-lib.fth
020-cc-arena.fth
030-cc-io.fth
040-cc-prep.fth
050-cc-lex.fth
060-cc-types.fth
070-cc-sym.fth
080-cc-elf.fth
081-cc-object.fth
090-cc-emit.fth
100-cc-expr.fth
110-cc-decl.fth
112-cc-stmt.fth
114-cc-func.fth
115-cc-native.fth
116-cc-prog.fth
117-cc-native-program.fth
118-cc-native-init.fth
119-cc-native-runtime.fth
121-cc-sysv.fth
122-cc-sysv-runtime.fth
123-cc-object-program.fth
124-cc-target.fth
125-cc-consteval.fth
126-cc-varargs.fth
127-cc-binary64.fth
128-cc-float-literal.fth
129-cc-bitfield.fth
131-cc-aggregate-abi.fth
132-cc-long-double.fth
140-cc-link.fth
141-archive.fth
k1/direct-smoke.kaem
k1/tests/direct-smoke.c
k1/tests/direct-smoke.sha256
runtime/gcc-seed/abs.c
runtime/gcc-seed/access.c
runtime/gcc-seed/alloc.c
runtime/gcc-seed/assert.c
runtime/gcc-seed/atoi.c
runtime/gcc-seed/atol.c
runtime/gcc-seed/atoll.c
runtime/gcc-seed/bsd-string.c
runtime/gcc-seed/calendar.c
runtime/gcc-seed/clock-sleep.c
runtime/gcc-seed/clock.c
runtime/gcc-seed/creat.c
runtime/gcc-seed/ctype.c
runtime/gcc-seed/dbfile.c
runtime/gcc-seed/decimal.c
runtime/gcc-seed/descriptor-io.c
runtime/gcc-seed/dirent.c
runtime/gcc-seed/dirfd.c
runtime/gcc-seed/dup3.c
runtime/gcc-seed/environment.c
runtime/gcc-seed/exec-list.c
runtime/gcc-seed/fcntl.c
runtime/gcc-seed/file-calls.c
runtime/gcc-seed/floatfmt.c
runtime/gcc-seed/flock.c
runtime/gcc-seed/fpclass.c
runtime/gcc-seed/ftruncate.c
runtime/gcc-seed/getcwd.c
runtime/gcc-seed/getline.c
runtime/gcc-seed/getlogin.c
runtime/gcc-seed/getopt.c
runtime/gcc-seed/getpid.c
runtime/gcc-seed/group.c
runtime/gcc-seed/identity.c
runtime/gcc-seed/include/alloca.h
runtime/gcc-seed/include/ar.h
runtime/gcc-seed/include/assert.h
runtime/gcc-seed/include/ctype.h
runtime/gcc-seed/include/dirent.h
runtime/gcc-seed/include/errno.h
runtime/gcc-seed/include/fcntl.h
runtime/gcc-seed/include/features.h
runtime/gcc-seed/include/float.h
runtime/gcc-seed/include/grp.h
runtime/gcc-seed/include/inttypes.h
runtime/gcc-seed/include/limits.h
runtime/gcc-seed/include/locale.h
runtime/gcc-seed/include/math.h
runtime/gcc-seed/include/memory.h
runtime/gcc-seed/include/paths.h
runtime/gcc-seed/include/pwd.h
runtime/gcc-seed/include/seed-dbfile.h
runtime/gcc-seed/include/seed-directory.h
runtime/gcc-seed/include/seed-float.h
runtime/gcc-seed/include/seed-frame.h
runtime/gcc-seed/include/seed-syscall.h
runtime/gcc-seed/include/seed-timespec.h
runtime/gcc-seed/include/setjmp.h
runtime/gcc-seed/include/signal.h
runtime/gcc-seed/include/stdarg.h
runtime/gcc-seed/include/stdbool.h
runtime/gcc-seed/include/stddef.h
runtime/gcc-seed/include/stdint.h
runtime/gcc-seed/include/stdio.h
runtime/gcc-seed/include/stdlib.h
runtime/gcc-seed/include/string.h
runtime/gcc-seed/include/strings.h
runtime/gcc-seed/include/sys/file.h
runtime/gcc-seed/include/sys/ioctl.h
runtime/gcc-seed/include/sys/mman.h
runtime/gcc-seed/include/sys/mtio.h
runtime/gcc-seed/include/sys/param.h
runtime/gcc-seed/include/sys/procfs.h
runtime/gcc-seed/include/sys/resource.h
runtime/gcc-seed/include/sys/stat.h
runtime/gcc-seed/include/sys/sysmacros.h
runtime/gcc-seed/include/sys/time.h
runtime/gcc-seed/include/sys/times.h
runtime/gcc-seed/include/sys/types.h
runtime/gcc-seed/include/sys/utsname.h
runtime/gcc-seed/include/sys/wait.h
runtime/gcc-seed/include/termio.h
runtime/gcc-seed/include/termios.h
runtime/gcc-seed/include/time.h
runtime/gcc-seed/include/unistd.h
runtime/gcc-seed/include/utime.h
runtime/gcc-seed/include/wchar.h
runtime/gcc-seed/include/wctype.h
runtime/gcc-seed/ioctl.c
runtime/gcc-seed/isatty.c
runtime/gcc-seed/isblank.c
runtime/gcc-seed/labs.c
runtime/gcc-seed/locale.c
runtime/gcc-seed/localeconv.c
runtime/gcc-seed/makedev.c
runtime/gcc-seed/mapping.c
runtime/gcc-seed/math.c
runtime/gcc-seed/mbstate.c
runtime/gcc-seed/memory.c
runtime/gcc-seed/metadata.c
runtime/gcc-seed/mkfifo.c
runtime/gcc-seed/mkstemp.c
runtime/gcc-seed/passwd.c
runtime/gcc-seed/paths.c
runtime/gcc-seed/popen.c
runtime/gcc-seed/posix.c
runtime/gcc-seed/process-api.c
runtime/gcc-seed/process.c
runtime/gcc-seed/qsort.c
runtime/gcc-seed/rand.c
runtime/gcc-seed/realpath.c
runtime/gcc-seed/remove.c
runtime/gcc-seed/resource.c
runtime/gcc-seed/scan.c
runtime/gcc-seed/setbuf.c
runtime/gcc-seed/setenv.c
runtime/gcc-seed/setgroups.c
runtime/gcc-seed/sigaction.c
runtime/gcc-seed/signal-send.c
runtime/gcc-seed/signal.c
runtime/gcc-seed/sigset.c
runtime/gcc-seed/sort.c
runtime/gcc-seed/startup.c
runtime/gcc-seed/stat.c
runtime/gcc-seed/stdio.c
runtime/gcc-seed/stpcpy.c
runtime/gcc-seed/stpncpy.c
runtime/gcc-seed/strcasecmp.c
runtime/gcc-seed/strcoll.c
runtime/gcc-seed/strcspn.c
runtime/gcc-seed/strerror.c
runtime/gcc-seed/strftime.c
runtime/gcc-seed/string.c
runtime/gcc-seed/strncasecmp.c
runtime/gcc-seed/strndup.c
runtime/gcc-seed/strnlen.c
runtime/gcc-seed/strpbrk.c
runtime/gcc-seed/strsignal.c
runtime/gcc-seed/strspn.c
runtime/gcc-seed/strtoimax.c
runtime/gcc-seed/strtok.c
runtime/gcc-seed/strtoll.c
runtime/gcc-seed/strtoul.c
runtime/gcc-seed/strtoull.c
runtime/gcc-seed/strtoumax.c
runtime/gcc-seed/sysconf.c
runtime/gcc-seed/system.c
runtime/gcc-seed/termios.c
runtime/gcc-seed/timeofday.c
runtime/gcc-seed/ttyname.c
runtime/gcc-seed/utimes.c
runtime/gcc-seed/utsname.c
runtime/gcc-seed/wide.c
runtime/gcc-seed/write.c
tools/seed-ar.c
tools/seed-cc-boot/archive-head.fth
tools/seed-cc-boot/archive-tail.fth
tools/seed-cc-boot/link-seed-ar.fth
tools/seed-cc-boot/link-seed-cc.fth
tools/seed-cc-boot/runtime-unit.fth
tools/seed-cc-boot/sysrt.fth
tools/seed-cc-boot/tools-unit.fth
tools/seed-cc-start.fth
tools/seed-cc.c
tools/seed-tool.h
vendor/mescc-tools/Kaem/kaem.c
vendor/mescc-tools/Kaem/kaem.h
vendor/mescc-tools/Kaem/kaem_globals.c
vendor/mescc-tools/Kaem/kaem_globals.h
vendor/mescc-tools/Kaem/variable.c
vendor/mescc-tools/M2libc/bootstrappable.h
vendor/stage0-posix/mescc-tools-extra/M2libc/bootstrappable.c
vendor/stage0-posix/mescc-tools-extra/M2libc/bootstrappable.h
vendor/stage0-posix/mescc-tools-extra/mkdir.c
vendor/stage0-posix/mescc-tools-extra/sha256sum.c
""".split()

# Plumbing stages 1-2, the parser generators and bash 2.05b (k1/direct.recipe).
DIRECT = """
gcc-direct/lexer-inputs/recipe-reference/LICENSES/BSD-2-Clause.txt
gcc-direct/lexer-inputs/recipe-reference/steps/flex-2.5.11/files/scan.lex.l
gcc-direct/lexer-inputs/recipe-reference/steps/flex-2.5.11/patches/scan_l.patch
gcc-direct/lexer-inputs/recipe-reference/steps/flex-2.5.11/patches/yyin.patch
plumbing/SOURCES
plumbing/bash-2.05b/Makefile
plumbing/bash-2.05b/builtins.mk
plumbing/bash-2.05b/common.mk
plumbing/bash-2.05b/config.h
plumbing/bash-2.05b/empty.h
plumbing/bash-2.05b/missing-defines.patch
plumbing/bash.kaem
plumbing/chain.SOURCES
plumbing/chain.kaem
plumbing/coreutils-5.0/Makefile
plumbing/coreutils-5.0/canonicalize-realloc.diff
plumbing/coreutils-5.0/config.h
plumbing/diffutils-2.7/Makefile
plumbing/diffutils-2.7/config.h
plumbing/flex-2.5.11/Makefile
plumbing/flex-2.5.11/config.h
plumbing/gawk-3.0.4/Makefile
plumbing/gawk-3.0.4/config.h
plumbing/grep-2.4/Makefile
plumbing/grep-2.4/config.h
plumbing/gzip-1.2.4/Makefile
plumbing/heirloom-lex-070527/Makefile
plumbing/heirloom-lex-070527/main-unit.c
plumbing/late.SOURCES
plumbing/lexer-prepare.c
plumbing/lexers.GENERATED
plumbing/lexers.PREPARED
plumbing/lexers.SOURCES
plumbing/lexers.kaem
plumbing/make-3.82/config.h
plumbing/oyacc-6.6/Makefile
plumbing/oyacc-6.6/config.h
plumbing/patch-2.5.9/Makefile
plumbing/patch-2.5.9/config.h
plumbing/sed-4.0.9/Makefile
plumbing/sed-4.0.9/config.h
plumbing/stage1.kaem
plumbing/stage2.kaem
plumbing/tar-1.12/Makefile
plumbing/tar-1.12/config.h
vendor/stage0-posix/mescc-tools-extra/chmod.c
vendor/stage0-posix/mescc-tools-extra/cp.c
vendor/stage0-posix/mescc-tools-extra/rm.c
vendor/stage0-posix/mescc-tools-extra/unbz2.c
vendor/stage0-posix/mescc-tools-extra/ungz.c
vendor/stage0-posix/mescc-tools-extra/untar.c
""".split()

# After bash 2.05b (k1/direct-linux.recipe): the GCC chain, the late tools, gcc64's
# climb to gcc-10.5.0 and Linux.
LINUX = """
MANIFEST.sha256
gcc-direct/binutils.sh
gcc-direct/census.sh
gcc-direct/chain-lib.sh
gcc-direct/chain.sh
gcc-direct/configure.sh
gcc-direct/late-tools.sh
gcc-direct/patches/alloca-frame.json
gcc-direct/patches/alloca-frame.patch
gcc-direct/stage-c.sh
gcc-direct/stage-d.sh
gcc64/HASHES
gcc64/SOURCES
gcc64/build-gcc10.sh
gcc64/build-gcc4.sh
gcc64/build-gcc47.sh
gcc64/run-gcc64.sh
k1/direct-full.sh
ladder/finish.sh
ladder/getconf.sh
ladder/init.c
ladder/kexec.c
ladder/stage10-direct.sh
ladder/stage11.sh
ladder/stage12.sh
ladder/which.sh
patches/gcc64/gcc-4.0.4/01-collect2-unlink-if-ordinary.diff
patches/gcc64/gcc-10.5.0/includes.patch
patches/gcc64/gcc-10.5.0/libgcc-xfmode.patch
patches/gcc64/gcc-10.5.0/no-isolate-erroneous-paths-dereference.patch
patches/gcc64/gcc-4.7.4/0001-libitm-fixes-for-musl-support.patch
patches/gcc64/gcc-4.7.4/0002-fixincludes-update-for-musl-support.patch
patches/gcc64/gcc-4.7.4/0003-unwind-fix-for-musl.patch
patches/gcc64/gcc-4.7.4/0004-libstdc-gthr-workaround-for-musl.patch
patches/gcc64/gcc-4.7.4/0005-musl-libc-config.patch
patches/gcc64/gcc-4.7.4/0006-add-musl-support-to-gcc.patch
patches/gcc64/gcc-4.7.4/0007-x86-musl-support.patch
patches/gcc64/gcc-4.7.4/0008-config-linux.h-add-INCLUDE_DEFAULTS_MUSL_LOCAL.patch
patches/gcc64/gcc-4.7.4/gcc-10-fself-test.patch
patches/gcc64/gcc-4.7.4/gcc-10-libgcc-builtin-macros.patch
patches/gcc64/gcc-4.7.4/gcc-10-mlong-double.patch
patches/gcc64/gcc-4.7.4/remove_gperf_dependency.patch
patches/gcc64/musl-1.1.24/06-lb-madvise_preserve_errno.patch
patches/gcc64/musl-gcc/01-basename-c23.diff
patches/late/bc-1.07.1/01-fix-libmath-sed.diff
patches/late/diffutils-3.10/01-unparenthesize-ifdef-formats.diff
tests/gcc/stage-c-hello.c
tests/gcc/stage-c-hello.expected
tests/gcc64/cxx-test.cc
tests/gcc64/libc-test.c
""".split()



def _files(names):
    out = {}
    for name in names:
        p = ROOT / name
        if not p.is_file() or p.is_symlink():
            raise SystemExit(f"direct_inputs: {name} is not a regular file"
                             + (" (initialize the submodules)" if name.startswith("vendor/") else ""))
        out[name] = p
    return out


def _archives(prefixes):
    """MANIFEST.sha256 entries under the given build-out directories."""
    names = []
    for line in (ROOT / "MANIFEST.sha256").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            path = line.split()[1]
            if path.startswith(prefixes):
                names.append(path)
    return _files(names)


def k0_tree():
    return _files(K0)


def k1_tree(smoke, linux=False):
    tree = _files(SMOKE)
    if not smoke:
        tree.update(_files(DIRECT))
        tree.update(_archives(("build-out/plumbing-inputs/", "build-out/lexer-inputs/")))
    if linux:
        # direct-full.sh links the chain's gcc and musl archives to their
        # build-out/distfiles copies; chain.SOURCES' plain binutils tar is the
        # one input that is not a release archive as published.
        tree.update(_files(LINUX))
        tree.update(_archives(("build-out/distfiles/", "build-out/stage-b-inputs/")))
    return tree
