#!/bin/sh
# tests/seed/i386/boot-check.sh -- the i386 seed on builder-hex0, in one
# boot under QEMU/KVM (a second or two).
#
# The disk (tests/seed/i386/boot.list) holds seed/i386/000-seed.hex0 and
# two Forth files.  In the boot:
#   1. builder-hex0's built-in hex0 assembles the seed's source into
#      /seed-forth-i386;
#   2. /seed-forth-i386 /boot.fth runs tests/seed/i386/boot.fth, which
#      prints OK, the result of SPEC Appendix B's vectors, six checks of the
#      break and of memory above the file, and /seed-forth-i386 itself as
#      hex, read back with open and read through syscall6;
#   3. /seed-forth-i386 /fatal.fth meets an unknown token: "wibble?" on the
#      console (exit status 2 is not visible in the log);
#   4. /seed-forth-i386 /no-such-file exits 1 without output.
# The serial log must hold exactly the expected lines, and the hex dump
# must equal the host's ./seed-forth-i386, which seed/i386/build.sh makes
# from the same source with hex0-seed: the two assemblies agree byte for
# byte.
#
# The disk, the log (seed-i386-boot.log) and stage 1 are in
# build-out/builder-hex0-probe/, made by tests/builder-hex0/boot.sh and
# mkdisk.py.  --probe prints why the check cannot run and exits 1, or
# exits 0.
set -eu
cd "$(dirname "$0")/../../.."

probe() {
    for tool in qemu-system-x86_64 python3 od; do
        command -v "$tool" > /dev/null 2>&1 || { echo "missing: $tool"; return 1; }
    done
    [ -w /dev/kvm ] || { echo "no KVM (/dev/kvm)"; return 1; }
    [ -x vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed ] \
        || { echo "missing: the vendor/stage0-posix submodule"; return 1; }
    [ -f build-out/tinycc-inputs/builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a/builder-hex0-x86-stage2.hex0 ] \
        || { echo "missing: the builder-hex0 archive of tinycc/hex0-handoff.SOURCES, unpacked"; return 1; }
}
if [ "${1:-}" = --probe ]; then
    probe
    exit
fi
why=$(probe) || { echo "tests/seed/i386/boot-check.sh: $why" >&2; exit 1; }

seed/i386/build.sh
W=build-out/builder-hex0-probe
mkdir -p "$W"
tests/builder-hex0/boot.sh ../seed/i386/boot.list seed-i386-boot.log "${BOOT_TIMEOUT:-120}"

# The serial log without the host's timestamps.
sed 's/^\[[ 0-9.]*\] //' "$W/seed-i386-boot.log" > "$W/seed-i386-boot.txt"

# What the boot must print between the shell's echo of the second command
# and "Build finished.": the shell echoes each command as two lines.
{
    echo /seed-forth-i386
    echo /boot.fth
    echo
    echo OK
    echo A
    echo AAAAAA
    od -An -v -tx1 -w32 seed-forth-i386 | tr -d ' ' | sed 's/^/S:/'
    echo END
    echo /seed-forth-i386
    echo /fatal.fth
    echo 'wibble?'
    echo /seed-forth-i386
    echo /no-such-file
    echo Build finished.
} > "$W/seed-i386-boot.expected"
# From the first echo of the program's name (after the hex0 command) on,
# up to and including "Build finished.".
sed -n '/^\/seed-forth-i386$/,/^Build finished\.$/p' "$W/seed-i386-boot.txt" > "$W/seed-i386-boot.got"

if ! cmp -s "$W/seed-i386-boot.expected" "$W/seed-i386-boot.got"; then
    echo "tests/seed/i386/boot-check.sh: FAIL: the boot's console differs from what is expected"
    diff "$W/seed-i386-boot.expected" "$W/seed-i386-boot.got" | head -40
    exit 1
fi

# The dump alone, back to bytes, against the host's file.
grep '^S:' "$W/seed-i386-boot.got" | sed 's/^S://' | python3 -I -c '
import sys
sys.stdout.buffer.write(bytes.fromhex(sys.stdin.read()))' > "$W/seed-forth-i386.from-boot"
cmp "$W/seed-forth-i386.from-boot" seed-forth-i386
size=$(wc -c < seed-forth-i386)
echo "builder-hex0's hex0 assembled seed/i386/000-seed.hex0 into /seed-forth-i386,"
echo "  and that seed ran tests/seed/i386/boot.fth: OK, Appendix B A, checks AAAAAA"
echo "  /seed-forth-i386 dumped by the boot: $size bytes, equal to the host's ./seed-forth-i386"
echo "  sha256 of both: $(sha256sum < "$W/seed-forth-i386.from-boot" | cut -d' ' -f1)"
echo "  the fatal error printed wibble?, and the boot reached Build finished."
echo "tests/seed/i386/boot-check.sh: OK"
