"""Image inventories for the run under K0 and K1: explicit lists, so the
guest reads exactly the repository files named here.

k0_tree(): what K0 needs to build K1 from the seed (kernel/tools/k1-direct-start.fth
and kernel/tools/k1-direct.recipe); kernel/k0/mkfs.py adds seed-forth itself.
k1_tree(smoke, linux): K1's starting tree for kernel/k1/direct-smoke.recipe or, without
smoke, kernel/k1/direct.recipe (the seed to bash 2.05b): sources, plus hex0-seed (the
only executable, added by kernel/k1/mkdisk.py) and, for the full route, the pinned
archives the plumbing stages unpack; with linux, also what
kernel/k1/direct-linux.recipe needs after bash 2.05b, and the MANIFEST.sha256
archives it unpacks.  Paths map image names to host files.

The lists were taken from a traced run (every file the host route opens,
strace -y -e trace=open,openat,execve) and from reading the guest stages;
a file missing here fails the run that needs it.  cc/driver/seed-cc-start.fth
lists the compiler layers and chain/runtime/gcc-seed/*.c with getdents64, so
those directories hold exactly the files named here.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# K1 built by seed Forth under K0: kernel/tools/k1-direct.recipe and the runner.
K0 = """
forth/010-lib.fth
cc/020-cc-arena.fth
cc/030-cc-io.fth
cc/040-cc-prep.fth
cc/050-cc-lex.fth
cc/060-cc-types.fth
cc/070-cc-sym.fth
cc/080-cc-elf.fth
cc/081-cc-object.fth
cc/090-cc-emit.fth
cc/100-cc-expr.fth
cc/110-cc-decl.fth
cc/112-cc-stmt.fth
cc/114-cc-func.fth
cc/115-cc-native.fth
cc/116-cc-prog.fth
cc/117-cc-native-program.fth
cc/118-cc-native-init.fth
cc/119-cc-native-runtime.fth
cc/120-cc-main.fth
cc/121-cc-sysv.fth
cc/122-cc-sysv-runtime.fth
cc/123-cc-object-program.fth
cc/124-cc-target.fth
cc/125-cc-consteval.fth
cc/126-cc-varargs.fth
cc/127-cc-binary64.fth
cc/128-cc-float-literal.fth
cc/129-cc-bitfield.fth
cc/131-cc-aggregate-abi.fth
cc/132-cc-long-double.fth
cc/140-cc-link.fth
kernel/k1/ata.c
kernel/k1/boot/asm.fth
kernel/k1/boot/k0-syscalls.fth
kernel/k1/boot/link.fth
kernel/k1/boot/unit.fth
kernel/k1/fs.c
kernel/k1/k1-asm.fth
kernel/k1/k1.h
kernel/k1/linux.c
kernel/k1/main.c
kernel/k1/mm.c
kernel/k1/proc.c
kernel/k1/sys.c
kernel/tools/amd64-runner.c
kernel/tools/amd64-syscalls.fth
kernel/tools/k1-direct-start.fth
kernel/tools/k1-direct.recipe
kernel/tools/obj-asm.fth
""".split()

# The seed, seed-cc and seed-ar, kaem, and kernel/k1/direct-smoke.kaem.
SMOKE = """
seed/000-seed.hex0
forth/010-lib.fth
cc/020-cc-arena.fth
cc/030-cc-io.fth
cc/040-cc-prep.fth
cc/050-cc-lex.fth
cc/060-cc-types.fth
cc/070-cc-sym.fth
cc/080-cc-elf.fth
cc/081-cc-object.fth
cc/090-cc-emit.fth
cc/100-cc-expr.fth
cc/110-cc-decl.fth
cc/112-cc-stmt.fth
cc/114-cc-func.fth
cc/115-cc-native.fth
cc/116-cc-prog.fth
cc/117-cc-native-program.fth
cc/118-cc-native-init.fth
cc/119-cc-native-runtime.fth
cc/121-cc-sysv.fth
cc/122-cc-sysv-runtime.fth
cc/123-cc-object-program.fth
cc/124-cc-target.fth
cc/125-cc-consteval.fth
cc/126-cc-varargs.fth
cc/127-cc-binary64.fth
cc/128-cc-float-literal.fth
cc/129-cc-bitfield.fth
cc/131-cc-aggregate-abi.fth
cc/132-cc-long-double.fth
cc/140-cc-link.fth
cc/141-archive.fth
kernel/k1/direct-smoke.kaem
kernel/k1/tests/direct-smoke.c
kernel/k1/tests/direct-smoke.sha256
chain/runtime/gcc-seed/abs.c
chain/runtime/gcc-seed/access.c
chain/runtime/gcc-seed/alloc.c
chain/runtime/gcc-seed/assert.c
chain/runtime/gcc-seed/atoi.c
chain/runtime/gcc-seed/atol.c
chain/runtime/gcc-seed/atoll.c
chain/runtime/gcc-seed/bsd-string.c
chain/runtime/gcc-seed/calendar.c
chain/runtime/gcc-seed/clock-sleep.c
chain/runtime/gcc-seed/clock.c
chain/runtime/gcc-seed/creat.c
chain/runtime/gcc-seed/ctype.c
chain/runtime/gcc-seed/dbfile.c
chain/runtime/gcc-seed/decimal.c
chain/runtime/gcc-seed/descriptor-io.c
chain/runtime/gcc-seed/dirent.c
chain/runtime/gcc-seed/dirfd.c
chain/runtime/gcc-seed/dup3.c
chain/runtime/gcc-seed/environment.c
chain/runtime/gcc-seed/exec-list.c
chain/runtime/gcc-seed/fcntl.c
chain/runtime/gcc-seed/file-calls.c
chain/runtime/gcc-seed/floatfmt.c
chain/runtime/gcc-seed/flock.c
chain/runtime/gcc-seed/fpclass.c
chain/runtime/gcc-seed/ftruncate.c
chain/runtime/gcc-seed/getcwd.c
chain/runtime/gcc-seed/getline.c
chain/runtime/gcc-seed/getlogin.c
chain/runtime/gcc-seed/getopt.c
chain/runtime/gcc-seed/getpid.c
chain/runtime/gcc-seed/group.c
chain/runtime/gcc-seed/identity.c
chain/runtime/gcc-seed/include/alloca.h
chain/runtime/gcc-seed/include/ar.h
chain/runtime/gcc-seed/include/assert.h
chain/runtime/gcc-seed/include/ctype.h
chain/runtime/gcc-seed/include/dirent.h
chain/runtime/gcc-seed/include/errno.h
chain/runtime/gcc-seed/include/fcntl.h
chain/runtime/gcc-seed/include/features.h
chain/runtime/gcc-seed/include/float.h
chain/runtime/gcc-seed/include/grp.h
chain/runtime/gcc-seed/include/inttypes.h
chain/runtime/gcc-seed/include/limits.h
chain/runtime/gcc-seed/include/locale.h
chain/runtime/gcc-seed/include/math.h
chain/runtime/gcc-seed/include/memory.h
chain/runtime/gcc-seed/include/paths.h
chain/runtime/gcc-seed/include/pwd.h
chain/runtime/gcc-seed/include/seed-dbfile.h
chain/runtime/gcc-seed/include/seed-directory.h
chain/runtime/gcc-seed/include/seed-float.h
chain/runtime/gcc-seed/include/seed-frame.h
chain/runtime/gcc-seed/include/seed-syscall.h
chain/runtime/gcc-seed/include/seed-timespec.h
chain/runtime/gcc-seed/include/setjmp.h
chain/runtime/gcc-seed/include/signal.h
chain/runtime/gcc-seed/include/stdarg.h
chain/runtime/gcc-seed/include/stdbool.h
chain/runtime/gcc-seed/include/stddef.h
chain/runtime/gcc-seed/include/stdint.h
chain/runtime/gcc-seed/include/stdio.h
chain/runtime/gcc-seed/include/stdlib.h
chain/runtime/gcc-seed/include/string.h
chain/runtime/gcc-seed/include/strings.h
chain/runtime/gcc-seed/include/sys/file.h
chain/runtime/gcc-seed/include/sys/ioctl.h
chain/runtime/gcc-seed/include/sys/mman.h
chain/runtime/gcc-seed/include/sys/mtio.h
chain/runtime/gcc-seed/include/sys/param.h
chain/runtime/gcc-seed/include/sys/procfs.h
chain/runtime/gcc-seed/include/sys/resource.h
chain/runtime/gcc-seed/include/sys/stat.h
chain/runtime/gcc-seed/include/sys/sysmacros.h
chain/runtime/gcc-seed/include/sys/time.h
chain/runtime/gcc-seed/include/sys/times.h
chain/runtime/gcc-seed/include/sys/types.h
chain/runtime/gcc-seed/include/sys/utsname.h
chain/runtime/gcc-seed/include/sys/wait.h
chain/runtime/gcc-seed/include/termio.h
chain/runtime/gcc-seed/include/termios.h
chain/runtime/gcc-seed/include/time.h
chain/runtime/gcc-seed/include/unistd.h
chain/runtime/gcc-seed/include/utime.h
chain/runtime/gcc-seed/include/wchar.h
chain/runtime/gcc-seed/include/wctype.h
chain/runtime/gcc-seed/ioctl.c
chain/runtime/gcc-seed/isatty.c
chain/runtime/gcc-seed/isblank.c
chain/runtime/gcc-seed/labs.c
chain/runtime/gcc-seed/locale.c
chain/runtime/gcc-seed/localeconv.c
chain/runtime/gcc-seed/makedev.c
chain/runtime/gcc-seed/mapping.c
chain/runtime/gcc-seed/math.c
chain/runtime/gcc-seed/mbstate.c
chain/runtime/gcc-seed/memory.c
chain/runtime/gcc-seed/metadata.c
chain/runtime/gcc-seed/mkfifo.c
chain/runtime/gcc-seed/mkstemp.c
chain/runtime/gcc-seed/passwd.c
chain/runtime/gcc-seed/paths.c
chain/runtime/gcc-seed/popen.c
chain/runtime/gcc-seed/posix.c
chain/runtime/gcc-seed/process-api.c
chain/runtime/gcc-seed/process.c
chain/runtime/gcc-seed/qsort.c
chain/runtime/gcc-seed/rand.c
chain/runtime/gcc-seed/realpath.c
chain/runtime/gcc-seed/remove.c
chain/runtime/gcc-seed/resource.c
chain/runtime/gcc-seed/scan.c
chain/runtime/gcc-seed/setbuf.c
chain/runtime/gcc-seed/setenv.c
chain/runtime/gcc-seed/setgroups.c
chain/runtime/gcc-seed/sigaction.c
chain/runtime/gcc-seed/signal-send.c
chain/runtime/gcc-seed/signal.c
chain/runtime/gcc-seed/sigset.c
chain/runtime/gcc-seed/sort.c
chain/runtime/gcc-seed/startup.c
chain/runtime/gcc-seed/stat.c
chain/runtime/gcc-seed/stdio.c
chain/runtime/gcc-seed/stpcpy.c
chain/runtime/gcc-seed/stpncpy.c
chain/runtime/gcc-seed/strcasecmp.c
chain/runtime/gcc-seed/strcoll.c
chain/runtime/gcc-seed/strcspn.c
chain/runtime/gcc-seed/strerror.c
chain/runtime/gcc-seed/strftime.c
chain/runtime/gcc-seed/string.c
chain/runtime/gcc-seed/strncasecmp.c
chain/runtime/gcc-seed/strndup.c
chain/runtime/gcc-seed/strnlen.c
chain/runtime/gcc-seed/strpbrk.c
chain/runtime/gcc-seed/strsignal.c
chain/runtime/gcc-seed/strspn.c
chain/runtime/gcc-seed/strtoimax.c
chain/runtime/gcc-seed/strtok.c
chain/runtime/gcc-seed/strtoll.c
chain/runtime/gcc-seed/strtoul.c
chain/runtime/gcc-seed/strtoull.c
chain/runtime/gcc-seed/strtoumax.c
chain/runtime/gcc-seed/sysconf.c
chain/runtime/gcc-seed/system.c
chain/runtime/gcc-seed/termios.c
chain/runtime/gcc-seed/timeofday.c
chain/runtime/gcc-seed/ttyname.c
chain/runtime/gcc-seed/utimes.c
chain/runtime/gcc-seed/utsname.c
chain/runtime/gcc-seed/wide.c
chain/runtime/gcc-seed/write.c
cc/driver/seed-ar.c
cc/driver/seed-cc-boot/archive-head.fth
cc/driver/seed-cc-boot/archive-tail.fth
cc/driver/seed-cc-boot/link-seed-ar.fth
cc/driver/seed-cc-boot/link-seed-cc.fth
cc/driver/seed-cc-boot/runtime-unit.fth
cc/driver/seed-cc-boot/sysrt.fth
cc/driver/seed-cc-boot/tools-unit.fth
cc/driver/seed-cc-start.fth
cc/driver/seed-cc.c
cc/driver/seed-tool.h
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

# Plumbing stages 1-2, the parser generators and bash 2.05b (kernel/k1/direct.recipe).
DIRECT = """
chain/gcc-direct/lexer-inputs/recipe-reference/LICENSES/BSD-2-Clause.txt
chain/gcc-direct/lexer-inputs/recipe-reference/steps/flex-2.5.11/files/scan.lex.l
chain/gcc-direct/lexer-inputs/recipe-reference/steps/flex-2.5.11/patches/scan_l.patch
chain/gcc-direct/lexer-inputs/recipe-reference/steps/flex-2.5.11/patches/yyin.patch
chain/plumbing/SOURCES
chain/plumbing/bash-2.05b/Makefile
chain/plumbing/bash-2.05b/builtins.mk
chain/plumbing/bash-2.05b/common.mk
chain/plumbing/bash-2.05b/config.h
chain/plumbing/bash-2.05b/empty.h
chain/plumbing/bash-2.05b/missing-defines.patch
chain/plumbing/bash.kaem
chain/plumbing/chain.SOURCES
chain/plumbing/chain.kaem
chain/plumbing/coreutils-5.0/Makefile
chain/plumbing/coreutils-5.0/canonicalize-realloc.diff
chain/plumbing/coreutils-5.0/config.h
chain/plumbing/diffutils-2.7/Makefile
chain/plumbing/diffutils-2.7/config.h
chain/plumbing/flex-2.5.11/Makefile
chain/plumbing/flex-2.5.11/config.h
chain/plumbing/gawk-3.0.4/Makefile
chain/plumbing/gawk-3.0.4/config.h
chain/plumbing/grep-2.4/Makefile
chain/plumbing/grep-2.4/config.h
chain/plumbing/gzip-1.2.4/Makefile
chain/plumbing/heirloom-lex-070527/Makefile
chain/plumbing/heirloom-lex-070527/main-unit.c
chain/plumbing/late.SOURCES
chain/plumbing/lexer-prepare.c
chain/plumbing/lexers.GENERATED
chain/plumbing/lexers.PREPARED
chain/plumbing/lexers.SOURCES
chain/plumbing/lexers.kaem
chain/plumbing/make-3.82/config.h
chain/plumbing/oyacc-6.6/Makefile
chain/plumbing/oyacc-6.6/config.h
chain/plumbing/patch-2.5.9/Makefile
chain/plumbing/patch-2.5.9/config.h
chain/plumbing/sed-4.0.9/Makefile
chain/plumbing/sed-4.0.9/config.h
chain/plumbing/stage1.kaem
chain/plumbing/stage2.kaem
chain/plumbing/tar-1.12/Makefile
chain/plumbing/tar-1.12/config.h
vendor/stage0-posix/mescc-tools-extra/chmod.c
vendor/stage0-posix/mescc-tools-extra/cp.c
vendor/stage0-posix/mescc-tools-extra/rm.c
vendor/stage0-posix/mescc-tools-extra/unbz2.c
vendor/stage0-posix/mescc-tools-extra/ungz.c
vendor/stage0-posix/mescc-tools-extra/untar.c
""".split()

# After bash 2.05b (kernel/k1/direct-linux.recipe): the GCC chain, the late tools, gcc64's
# climb to gcc-10.5.0 and Linux.
LINUX = """
MANIFEST.sha256
chain/gcc-direct/binutils.sh
chain/gcc-direct/census.sh
chain/gcc-direct/chain-lib.sh
chain/gcc-direct/chain.sh
chain/gcc-direct/configure.sh
chain/gcc-direct/late-tools.sh
chain/gcc-direct/patches/alloca-frame.json
chain/gcc-direct/patches/alloca-frame.patch
chain/gcc-direct/stage-c.sh
chain/gcc-direct/stage-d.sh
chain/gcc64/HASHES
chain/gcc64/SOURCES
chain/gcc64/build-gcc10.sh
chain/gcc64/build-gcc4.sh
chain/gcc64/build-gcc47.sh
chain/gcc64/run-gcc64.sh
kernel/k1/direct-full.sh
chain/ladder/finish.sh
chain/ladder/getconf.sh
chain/ladder/init.c
chain/ladder/kexec.c
chain/ladder/stage10-direct.sh
chain/ladder/stage11.sh
chain/ladder/stage12.sh
chain/ladder/which.sh
chain/patches/gcc64/gcc-4.0.4/01-collect2-unlink-if-ordinary.diff
chain/patches/gcc64/gcc-10.5.0/includes.patch
chain/patches/gcc64/gcc-10.5.0/libgcc-xfmode.patch
chain/patches/gcc64/gcc-10.5.0/no-isolate-erroneous-paths-dereference.patch
chain/patches/gcc64/gcc-4.7.4/0001-libitm-fixes-for-musl-support.patch
chain/patches/gcc64/gcc-4.7.4/0002-fixincludes-update-for-musl-support.patch
chain/patches/gcc64/gcc-4.7.4/0003-unwind-fix-for-musl.patch
chain/patches/gcc64/gcc-4.7.4/0004-libstdc-gthr-workaround-for-musl.patch
chain/patches/gcc64/gcc-4.7.4/0005-musl-libc-config.patch
chain/patches/gcc64/gcc-4.7.4/0006-add-musl-support-to-gcc.patch
chain/patches/gcc64/gcc-4.7.4/0007-x86-musl-support.patch
chain/patches/gcc64/gcc-4.7.4/0008-config-linux.h-add-INCLUDE_DEFAULTS_MUSL_LOCAL.patch
chain/patches/gcc64/gcc-4.7.4/gcc-10-fself-test.patch
chain/patches/gcc64/gcc-4.7.4/gcc-10-libgcc-builtin-macros.patch
chain/patches/gcc64/gcc-4.7.4/gcc-10-mlong-double.patch
chain/patches/gcc64/gcc-4.7.4/remove_gperf_dependency.patch
chain/patches/gcc64/musl-1.1.24/06-lb-madvise_preserve_errno.patch
chain/patches/gcc64/musl-gcc/01-basename-c23.diff
chain/patches/late/bc-1.07.1/01-fix-libmath-sed.diff
chain/patches/late/diffutils-3.10/01-unparenthesize-ifdef-formats.diff
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
