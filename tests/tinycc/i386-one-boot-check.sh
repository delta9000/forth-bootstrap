#!/usr/bin/env bash
# tests/tinycc/i386-one-boot-check.sh -- live-bootstrap's whole tcc-0.9.26
# step on its own kernel, builder-hex0, in one QEMU boot, from the i386
# first tcc and the i386 tools.
#
#     tests/tinycc/i386-one-boot-check.sh        (CHECK_I386_BOOT=1 ./check-all.sh)
#     tests/tinycc/i386-one-boot-check.sh --probe    exit 0 when this can run here
#
# The disk (tinycc/i386-one-boot-disk.py) holds builder-hex0's two stages,
# the first tcc as /usr/bin/tcc-mes, the eleven tools and a kaem in
# /x86/bin, the three archives of tinycc/SOURCES, tinycc/hex0-export.c and
# the script, /kaem.run.  builder-hex0 (stage 1 assembled by hex0-seed,
# stage 2 compiled from hex0 by stage 1) reads them and starts kaem.  The
# script checks and unpacks the archives, installs mes-0.28's headers and
# runs live-bootstrap's steps/tcc-0.9.26/pass1.kaem from "# Vars" to
# "# Checksums", less the MesCC commands: tcc-mes makes mes libc and
# tcc-boot0, and tcc-boot0, tcc-boot1 and tcc-boot2 follow.  tcc-mes also
# builds tinycc/hex0-export.c, which at the end writes the files compared
# below to /dev/hda; builder-hex0 writes that file to the drive's first
# sectors when its stream ends.
#
# This script compares what the boot exported: the ten files of
# live-bootstrap's tcc-0.9.26.x86.checksums (tcc-mes and tcc-boot0 with
# this route's pins), and with tests/pins/tinycc.sha256 what tcc-mes made
# before the later stages overwrote it (kept under /first), kaem and
# hex0-export.
#
# Built on the host, not in the boot: seed-forth (the x86-64 one) compiles
# the first tcc and the tools (tinycc/build-first-tcc-i386.sh,
# tinycc/build-tools-i386.sh).  kaem is HOST-BUILT in a second sense: the
# i386 first tcc compiles vendor/mescc-tools/Kaem on the host's kernel,
# through its IA32 support, in the bwrap root where
# tests/tinycc/junction-check.sh --i386 has just made mes libc with it.
# The host also cuts the script from the pinned kaem files, checks and
# unpacks builder-hex0's archive with the seed-built tools, assembles stage
# 1 with hex0-seed, writes the disk, starts QEMU and reads the drive.
set -euo pipefail
cd "$(dirname "$0")/../.."

IN=build-out/tinycc-inputs
OUT=build-out/tinycc/i386-one-boot
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9
BH=builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a
HEX0=vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
QEMU=${QEMU:-qemu-system-x86_64}

probe() {
    tests/tinycc/junction-check.sh --probe || return 1
    command -v "$QEMU" > /dev/null || { echo "missing: $QEMU"; return 1; }
    command -v python3 > /dev/null || { echo "missing: python3"; return 1; }
    [ -w /dev/kvm ] || { echo "no KVM (/dev/kvm)"; return 1; }
    [ -f "$IN/$BH.tar.gz" ] \
        || { echo "missing $IN/$BH.tar.gz (python3 tools/fetch-archives.py $IN/$BH.tar.gz)"; return 1; }
}
if [ "${1:-}" = --probe ]; then
    probe
    exit
fi
why=$(probe) || { echo "i386-one-boot-check: cannot run: $why" >&2; exit 1; }
fail() { echo "i386-one-boot-check: FAIL: $*" >&2; exit 1; }
pin() { sed -n "s|^\([0-9a-f]\{64\}\)  $1\$|\1|p" tests/pins/tinycc.sha256; }

rm -rf "$OUT"
mkdir -p "$OUT"

# ---- on the host: the first tcc, the tools and kaem ----
# The replay builds the first tcc and the tools as pinned and stops when
# the first tcc has made mes libc in build-out/tinycc/junction-root; there
# it compiles kaem with the command of tinycc/hex0-handoff.recipe.
JUNCTION_FIRST_ONLY=1 tests/tinycc/junction-check.sh --i386 > "$OUT/junction.log" 2>&1 \
    || { tail -20 "$OUT/junction.log" >&2; fail "junction-check.sh --i386 (log: $OUT/junction.log)"; }
bwrap --bind build-out/tinycc/junction-root / --ro-bind vendor /vendor --bind "$OUT" /out \
    --clearenv --chdir / \
    /usr/bin/tcc-mes -static -L /usr/lib/mes -o /out/kaem \
    /vendor/mescc-tools/Kaem/kaem.c /vendor/mescc-tools/Kaem/variable.c \
    /vendor/mescc-tools/Kaem/kaem_globals.c /vendor/mescc-tools/M2libc/bootstrappable.c \
    || fail "the first tcc did not build kaem"
got=$(sha256sum "$OUT/kaem" | cut -d' ' -f1)
[ "$got" = "$(pin tinycc/hex0-handoff/boot1/usr/bin/kaem)" ] \
    || fail "the host-built kaem is $got, not the one K0's boot builds (tests/pins/tinycc.sha256)"
echo "i386-one-boot-check: kaem, host-built by the i386 first tcc, as pinned"

# ---- on the host: builder-hex0's stage 1 and the disk ----
BIN=build-out/tinycc/bin
"$BIN/sha256sum" --check tinycc/hex0-handoff.SOURCES > /dev/null \
    || fail "$IN/$BH.tar.gz: sha256 differs from tinycc/hex0-handoff.SOURCES"
rm -rf "$IN/$BH"
"$BIN/ungz" --file "$IN/$BH.tar.gz" --output "$OUT/builder-hex0.tar" 2> /dev/null \
    || fail "ungz failed on $BH.tar.gz"
(cd "$IN" && ../tinycc/bin/untar --non-strict --file ../tinycc/i386-one-boot/builder-hex0.tar \
    > /dev/null 2>&1) \
    || fail "untar failed on $BH.tar"
"$HEX0" "$IN/$BH/builder-hex0-x86-stage1.hex0" "$OUT/stage1.bin"
python3 -I tinycc/i386-one-boot-disk.py "$OUT" "$OUT/stage1.bin" "$OUT/kaem"

# ---- the boot: builder-hex0, as live-bootstrap's rootfs.py starts it ----
# A command that is not there stops the machine without ending QEMU, hence
# the timeout.
rc=0
start=$(date +%s)
timeout 600 "$QEMU" -enable-kvm -m 4096M -smp 1 -drive file="$OUT/disk.img",format=raw \
    -machine kernel-irqchip=split -no-reboot -nographic < /dev/null > "$OUT/boot.log" 2>&1 || rc=$?
echo "i386-one-boot-check: the boot (builder-hex0) qemu exit $rc after $(($(date +%s) - start)) s"
[ "$rc" = 0 ] || { tail -20 "$OUT/boot.log" >&2; fail "the boot (log: $OUT/boot.log)"; }
# sha256sum -c in the boot: our line for the three archives, pass1.kaem's for tcc's
echo "i386-one-boot-check: $(tr -d '\r' < "$OUT/boot.log" | grep -ac ': OK$') archive checksums OK in the boot"
tr -d '\r' < "$OUT/boot.log" | grep -aE '^(tcc version|Build finished)' || true

# ---- what the boot exported ----
python3 -I tinycc/hex0-records.py "$OUT/disk.img" 0 > "$OUT/export.sha256"
grep -qxF '# end: end' "$OUT/export.sha256" || { tail -20 "$OUT/boot.log" >&2; fail "no export from the boot"; }
bad=0
check() {    # PATH WANT WORD NOTE: one line, WORD when PATH's sha256 is WANT
    local got
    got=$(sed -n "s|^\([0-9a-f]\{64\}\)  $1\$|\1|p" "$OUT/export.sha256")
    if [ -n "$got" ] && [ "$got" = "$2" ]; then
        echo "  $3  $got  $1${4:+ ($4)}"
    else
        echo "  FAIL  ${got:-missing}  $1 (expected ${2:-nothing})"
        bad=$((bad + 1))
    fi
}
echo "i386-one-boot-check: the boot's files against live-bootstrap's steps/tcc-0.9.26/tcc-0.9.26.x86.checksums"
while read -r want path; do
    case $path in
        /usr/bin/tcc-mes)
            check $path "$(pin tinycc/tcc-first-i386)" "pin " \
                "MesCC's is ${want:0:8}...; equals tests/pins/tinycc.sha256" ;;
        /usr/bin/tcc-boot0)
            check $path "$(pin tinycc/junction/usr/bin/tcc-boot0)" "pin " \
                "MesCC's is ${want:0:8}...; equals tests/pins/tinycc.sha256" ;;
        *) check $path "$want" same ;;
    esac
done < "build-out/tinycc/lb/$LB/steps/tcc-0.9.26/tcc-0.9.26.x86.checksums"
echo "i386-one-boot-check: what tcc-mes made in the boot, against tests/pins/tinycc.sha256"
for f in crt1.o crti.o crtn.o libc.a tcc/libtcc1.a libgetopt.a; do
    check /first/${f##*/} "$(pin tinycc/hex0-handoff/boot1/usr/lib/mes/$f)" "pin "
done
check /x86/bin/kaem "$(pin tinycc/hex0-handoff/boot1/usr/bin/kaem)" "pin "
check /usr/bin/hex0-export "$(pin tinycc/hex0-handoff/boot1/usr/bin/hex0-export)" "pin "
[ "$bad" = 0 ] || fail "$bad file(s) differ (log: $OUT/boot.log)"
echo "i386-one-boot-check: OK, live-bootstrap's published tcc-0.9.26 reached on builder-hex0 in one boot"
