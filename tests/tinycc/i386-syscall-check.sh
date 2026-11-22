#!/usr/bin/env bash
# tests/tinycc/i386-syscall-check.sh -- the i386 first tcc keeps to what
# builder-hex0 can do.
#
#     tests/tinycc/i386-syscall-check.sh        (from anywhere)
#
# Runs tests/tinycc/junction-check.sh under strace -f and reads
# every system call of every process whose program is tcc-mes, the name the
# replay gives build-out/tinycc/tcc-first-i386, or one of the i386 tools
# (build-out/tinycc/bin-i386, /forth-bootstrap/bin in the chroot).  It
# fails unless
#   - each call is one builder-hex0 implements: exit, fork, read, write,
#     open, close, waitpid, execve, chdir, lseek, access, mkdir, brk,
#     getcwd.  builder-hex0 answers 0 to any other and does nothing.  rm's
#     unlink, chmod's chmod and untar's symlink are let through: they are
#     what those tools are for, and on builder-hex0 they do nothing;
#   - no brk asks for less than the current break.  builder-hex0 would
#     zero all memory above it, files included;
#   - no write to a file happens at an offset past its end, after an
#     lseek.  builder-hex0 puts such bytes outside the file.  Only files
#     opened with O_CREAT can be followed (builder-hex0 always makes a new,
#     empty file for it); a write to any other file is a failure too;
#   - a file grows only while it is the newest one its process created.
#     builder-hex0 keeps files end to end, so an older one would grow over
#     its neighbour.
# Linux is the kernel here, so this shows the calls made, not that
# builder-hex0 answers them the same way.  Needs strace and what
# junction-check.sh needs.
set -euo pipefail
cd "$(dirname "$0")/../.."

command -v strace > /dev/null || { echo "i386-syscall-check: cannot run: missing strace" >&2; exit 1; }
trace=build-out/tinycc/junction-i386.strace
rm -f "$trace"
JUNCTION_STRACE=$trace tests/tinycc/junction-check.sh > build-out/tinycc/junction-i386.out 2>&1 \
    || { tail -20 build-out/tinycc/junction-i386.out >&2; echo "i386-syscall-check: FAIL: the junction failed" >&2; exit 1; }
tail -1 build-out/tinycc/junction-i386.out
python3 tests/tinycc/i386-syscall-check.py "$trace"
