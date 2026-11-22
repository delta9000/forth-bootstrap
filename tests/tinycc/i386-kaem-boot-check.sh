#!/usr/bin/env bash
# tests/tinycc/i386-kaem-boot-check.sh -- the Forth-built i386 kaem starts
# programs and reads their exit statuses on builder-hex0.
#
#     tests/tinycc/i386-kaem-boot-check.sh           (from anywhere)
#     tests/tinycc/i386-kaem-boot-check.sh --probe   exit 0 when this can run here
#
# Two QEMU boots of about a second each, on disks tests/builder-hex0/mkdisk.py
# writes.  The programs on them are build-out/tinycc/kaem-i386, three of the
# i386 tools (tinycc/build-tools-i386.sh) and the probe of
# tests/builder-hex0/, whose modes exit0 and exit300 exit with those
# statuses and whose unknown modes print their name.
#
# Boot 1, statuses.  builder-hex0's shell gives a program one argument, so
# it starts "/kaem --non-strict", which reads /kaem.run; that script runs
# kaem three more times, each on a script of its own in strict mode:
#   /zero.kaem   four commands that exit 0, the last a sha256sum of a copy
#                catm made of the script: all four ran, with their
#                arguments, and each status was read as 0;
#   /one.kaem    "match yes no" exits 1: "Subprocess error 1", and the line
#                after it does not run;
#   /wide.kaem   "probe exit300": builder-hex0 stores 300 << 8 unmasked, of
#                which kaem reads bits 8 to 15, so "Subprocess error 44".
# Four processes deep (shell, kaem, kaem, command), as the one-boot route
# will be.
#
# Boot 2, a command that is not there.  /kaem.run names /no-such-program.
# tinycc/m2libc-kaem-i386.c's guard answers -1 without calling execve, and
# kaem's child exits.  builder-hex0 does not resume kaem after that; its
# shell runs the next command and the boot ends.  Without the guard the
# machine stops and QEMU stays up until the timeout.
set -euo pipefail
cd "$(dirname "$0")/../.."

IN=build-out/tinycc-inputs
OUT=build-out/tinycc
W=$OUT/kaem-boot
BH=builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a
HEX0=vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
QEMU=${QEMU:-qemu-system-x86_64}

probe() {
    [ -x "$HEX0" ] || { echo "missing: $HEX0 (the vendor/stage0-posix submodule)"; return 1; }
    command -v "$QEMU" > /dev/null || { echo "missing: $QEMU"; return 1; }
    command -v python3 > /dev/null || { echo "missing: python3"; return 1; }
    [ -w /dev/kvm ] || { echo "no KVM (/dev/kvm)"; return 1; }
    echo 'int main (void) { return 0; }' | gcc -m32 -x c - -o /dev/null 2> /dev/null \
        || { echo "gcc -m32 does not build a program here"; return 1; }
    [ -f "$IN/$BH.tar.gz" ] \
        || { echo "missing $IN/$BH.tar.gz (python3 tools/fetch-archives.py $IN/$BH.tar.gz)"; return 1; }
}
if [ "${1:-}" = --probe ]; then
    probe
    exit
fi
why=$(probe) || { echo "i386-kaem-boot-check: cannot run: $why" >&2; exit 1; }
fail() { echo "i386-kaem-boot-check: FAIL: $*" >&2; exit 1; }

tinycc/build-tools-i386.sh | tail -1
tests/builder-hex0/build.sh
rm -rf "$W"
mkdir -p "$W"

# builder-hex0's two stages, checked and unpacked by the seed-built tools
BIN=build-out/tinycc/bin-i386
"$BIN/sha256sum" --check tinycc/builder-hex0.SOURCES > /dev/null \
    || fail "$IN/$BH.tar.gz: sha256 differs from tinycc/builder-hex0.SOURCES"
rm -rf "$IN/$BH"
"$BIN/ungz" --file "$IN/$BH.tar.gz" --output "$W/builder-hex0.tar" 2> /dev/null \
    || fail "ungz failed on $BH.tar.gz"
(cd "$IN" && ../tinycc/bin-i386/untar --non-strict --file ../tinycc/kaem-boot/builder-hex0.tar > /dev/null 2>&1) \
    || fail "untar failed on $BH.tar"
"$HEX0" "$IN/$BH/builder-hex0-x86-stage1.hex0" "$W/stage1.bin"

# boot N: write the disk from $W/bootN.list and boot it; the serial output,
# without carriage returns, goes to $W/bootN.log.
boot() {
    local rc=0
    python3 -I tests/builder-hex0/mkdisk.py "$W/boot$1.img" "$W/stage1.bin" \
        "$IN/$BH/builder-hex0-x86-stage2.hex0" "$W/boot$1.list"
    timeout 60 "$QEMU" -enable-kvm -m 4096M -smp 1 -drive file="$W/boot$1.img",format=raw \
        -machine kernel-irqchip=split -no-reboot -nographic < /dev/null 2>&1 \
        | tr -d '\r' > "$W/boot$1.log" || rc=$?
    [ "$rc" = 0 ] || { tail -20 "$W/boot$1.log" >&2; fail "boot $1: qemu exit $rc (log: $W/boot$1.log)"; }
    grep -aq '^Build finished' "$W/boot$1.log" || fail "boot $1 did not reach the end of its stream"
}
has() { grep -aqF -- "$2" "$W/boot$1.log" || fail "boot $1: no '$2' in $W/boot$1.log"; }
hasnot() { ! grep -aqF -- "$2" "$W/boot$1.log" || fail "boot $1: '$2' in $W/boot$1.log"; }

programs="f build-out/builder-hex0-probe/probe /probe
f $OUT/kaem-i386 /kaem
f $OUT/bin-i386/match /match
f $OUT/bin-i386/catm /catm
f $OUT/bin-i386/sha256sum /sha256sum"

# ---- boot 1: statuses ----
printf '%s\n' '/kaem --file /zero.kaem' '/kaem --file /one.kaem' '/kaem --file /wide.kaem' \
    '/probe after-three-scripts' > "$W/kaem.run"
printf '%s\n' '/probe exit0' '/match yes yes' '/catm /copy /zero.kaem' '/sha256sum /copy' > "$W/zero.kaem"
printf '%s\n' '/match yes no' '/probe after-status-1' > "$W/one.kaem"
printf '%s\n' '/probe exit300' '/probe after-status-300' > "$W/wide.kaem"
{
    echo "$programs"
    for f in kaem.run zero.kaem one.kaem wide.kaem; do echo "f $W/$f /$f"; done
    echo "x /kaem --non-strict"
    echo "x /probe after-kaem"
} > "$W/boot1.list"
boot 1
has 1 "$(sha256sum "$W/zero.kaem" | cut -d' ' -f1)  /copy"
has 1 "Subprocess error 1"
has 1 "Subprocess error 44"
hasnot 1 "after-status-"
has 1 "unknown mode 'after-three-scripts'"
has 1 "unknown mode 'after-kaem'"
echo "i386-kaem-boot-check: boot 1: four commands with status 0 ran, status 1 and 300 stopped their scripts"

# ---- boot 2: a command that is not there ----
printf '%s\n' '/probe exit0' '/no-such-program' '/probe after-missing' > "$W/missing.kaem"
{
    echo "$programs"
    echo "f $W/missing.kaem /kaem.run"
    echo "x /kaem --verbose"
    echo "x /probe after-kaem"
} > "$W/boot2.list"
boot 2
has 2 "/no-such-program"
hasnot 2 "after-missing"
hasnot 2 "KVM internal error"
has 2 "unknown mode 'after-kaem'"
echo "i386-kaem-boot-check: boot 2: a missing command did not stop the machine; the shell went on"
echo "i386-kaem-boot-check: OK"
