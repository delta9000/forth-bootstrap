#!/usr/bin/env bash
# tests/tinycc/i386-one-boot-check.sh -- from two hex0 sources to
# live-bootstrap's tcc-0.9.26 on builder-hex0, in one QEMU boot, with no
# program on the disk.
#
#     tests/tinycc/i386-one-boot-check.sh        (CHECK_I386_BOOT=1 ./check-all.sh)
#     tests/tinycc/i386-one-boot-check.sh --probe    exit 0 when this can run here
#
# The disk (tinycc/i386-one-boot-disk.py) holds builder-hex0's two stages
# and then only sources: the i386 seed and stage0-posix's kaem-minimal as
# hex0, the Forth library and compiler, the C of kaem, M2libc and the
# tools, the three archives of tinycc/SOURCES, and two scripts.  In the
# boot (forth/i386/CONTRACT.md, section 7):
#   1. builder-hex0's built-in hex0 assembles /seed-forth-i386 and
#      /kaem-optional-seed;
#   2. kaem-optional-seed runs /boot/seed.kaem: the seed compiles
#      vendor/mescc-tools/Kaem into /x86/bin/kaem (eight arguments), and
#      that kaem runs /kaem.run;
#   3. the seed compiles the eleven tools; they check and unpack the
#      archives and prepare the first tcc's sources; the seed compiles the
#      first tcc, /usr/bin/tcc-mes.  All of this before the first cd;
#   4. live-bootstrap's text: the mes-0.28 header install and
#      steps/tcc-0.9.26/pass1.kaem from "# Vars" to "# Checksums", less the
#      MesCC commands: tcc-mes makes mes libc and tcc-boot0, and tcc-boot0,
#      tcc-boot1 and tcc-boot2 follow;
#   5. tcc-mes builds tinycc/hex0-export.c, which writes the files compared
#      below to /dev/hda; builder-hex0 writes that file to the drive's
#      first sectors when its stream ends.
#
# This script compares what the boot exported:
#   - the ten files of live-bootstrap's tcc-0.9.26.x86.checksums (tcc-mes
#     and tcc-boot0 with this route's pins);
#   - with tests/pins/tinycc.sha256: what tcc-mes made before the later
#     stages overwrote it (kept under /first), hex0-export, kaem, the eleven
#     tools and the stock ungz and untar.  Those pins are what the seed
#     builds on the host (tinycc/build-tools-i386.sh,
#     build-first-tcc-i386.sh), so the seed on builder-hex0 and the seed on
#     Linux compile the same bytes;
#   - /seed-forth-i386 with ./seed-forth-i386, which hex0-seed assembles on
#     the host from the same source, and /kaem-optional-seed with the
#     binary stage0-posix publishes.
#
# What the host does: it cuts /kaem.run from the pinned kaem files
# (python3) of live-bootstrap's tree, which the seed-built tools of
# tinycc/build-tools-i386.sh unpacked; checks and unpacks builder-hex0's archive
# with those tools; runs hex0-seed for stage 1 and for the reference seed;
# writes the disk; starts QEMU; reads the drive and compares hashes.  It
# builds nothing that goes on the disk.
set -euo pipefail
cd "$(dirname "$0")/../.."

IN=build-out/tinycc-inputs
OUT=build-out/tinycc/i386-one-boot
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9
BH=builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a
HEX0=vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
QEMU=${QEMU:-qemu-system-x86_64}

probe() {
    [ -x "$HEX0" ] || { echo "missing: $HEX0 (the vendor/stage0-posix submodule)"; return 1; }
    command -v "$QEMU" > /dev/null || { echo "missing: $QEMU"; return 1; }
    command -v python3 > /dev/null || { echo "missing: python3"; return 1; }
    [ -w /dev/kvm ] || { echo "no KVM (/dev/kvm)"; return 1; }
    for a in tcc-0.9.26.tar.gz mes-0.28.tar.gz $LB.tar.gz $BH.tar.gz; do
        [ -f "$IN/$a" ] || { echo "missing $IN/$a (python3 tools/fetch-archives.py $IN/$a)"; return 1; }
    done
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

# ---- on the host: live-bootstrap's tree, builder-hex0's stages, the disk ----
tinycc/build-tools-i386.sh | tail -1
seed/i386/build.sh > /dev/null
BIN=build-out/tinycc/bin-i386
"$BIN/sha256sum" --check tinycc/hex0-handoff.SOURCES > /dev/null \
    || fail "$IN/$BH.tar.gz: sha256 differs from tinycc/hex0-handoff.SOURCES"
rm -rf "$IN/$BH"
"$BIN/ungz" --file "$IN/$BH.tar.gz" --output "$OUT/builder-hex0.tar" 2> /dev/null \
    || fail "ungz failed on $BH.tar.gz"
(cd "$IN" && ../tinycc/bin-i386/untar --non-strict --file ../tinycc/i386-one-boot/builder-hex0.tar \
    > /dev/null 2>&1) \
    || fail "untar failed on $BH.tar"
"$HEX0" "$IN/$BH/builder-hex0-x86-stage1.hex0" "$OUT/stage1.bin"
python3 -I tinycc/i386-one-boot-disk.py "$OUT" "$OUT/stage1.bin"

# ---- the boot: builder-hex0, as live-bootstrap's rootfs.py starts it ----
# A command that is not there stops the machine without ending QEMU, hence
# the timeout.
rc=0
start=$(date +%s)
timeout 600 "$QEMU" -enable-kvm -m 4096M -smp 1 -drive file="$OUT/disk.img",format=raw \
    -machine kernel-irqchip=split -no-reboot -nographic < /dev/null > "$OUT/boot.log" 2>&1 || rc=$?
echo "i386-one-boot-check: the boot (builder-hex0) qemu exit $rc after $(($(date +%s) - start)) s"
[ "$rc" = 0 ] || { tail -20 "$OUT/boot.log" >&2; fail "the boot (log: $OUT/boot.log)"; }
tr -d '\r' < "$OUT/boot.log" > "$OUT/boot.txt"
# kaem-optional-seed echoes each command after " +> "; the console wraps at
# 80 columns, so only the first line of the seed's command is looked for.
grep -aqF ' +> /seed-forth-i386 /forth/i386/010-lib.fth /tinycc/i386-seed/tool.fth /x86/bin' "$OUT/boot.txt" \
    || fail "kaem-optional-seed did not start the seed on kaem (log: $OUT/boot.log)"
# sha256sum -c in the boot: our line for the three archives, pass1.kaem's for tcc's
echo "i386-one-boot-check: $(grep -ac ': OK$' "$OUT/boot.txt") archive checksums OK in the boot"
grep -aE '^(tcc version|Build finished)' "$OUT/boot.txt" || true

# ---- what the boot exported ----
python3 -I tinycc/hex0-records.py "$OUT/disk.img" 0 > "$OUT/export.sha256"
grep -qxF '# end: end' "$OUT/export.sha256" || { tail -20 "$OUT/boot.log" >&2; fail "no export from the boot"; }
bad=0
checked=0
check() {    # PATH WANT WORD NOTE: one line, WORD when PATH's sha256 is WANT
    local got
    got=$(sed -n "s|^\([0-9a-f]\{64\}\)  $1\$|\1|p" "$OUT/export.sha256")
    checked=$((checked + 1))
    if [ -n "$got" ] && [ "$got" = "$2" ]; then
        echo "  $3  $got  $1${4:+ ($4)}"
    else
        echo "  FAIL  ${got:-missing}  $1 (expected ${2:-nothing})"
        bad=$((bad + 1))
    fi
}
echo "i386-one-boot-check: the two programs the built-in hex0 assembled"
check /seed-forth-i386 "$(sha256sum seed-forth-i386 | cut -d' ' -f1)" same \
    "hex0-seed's ./seed-forth-i386 on the host"
check /kaem-optional-seed \
    "$(sha256sum vendor/stage0-posix/bootstrap-seeds/POSIX/x86/kaem-optional-seed | cut -d' ' -f1)" same \
    "stage0-posix's published kaem-optional-seed"
echo "i386-one-boot-check: what the seed compiled in the boot, against tests/pins/tinycc.sha256"
check /x86/bin/kaem "$(pin tinycc/kaem-i386)" "pin "
for t in ungz untar; do
    check /boot/$t "$(pin tinycc/bin-boot-i386/$t)" "pin " "stage0-posix's source as published"
done
for t in $(sed -n 's|^/x86/bin/||p' "$OUT/export.list" | grep -vx kaem); do
    check /x86/bin/$t "$(pin tinycc/bin-i386/$t)" "pin "
done
echo "i386-one-boot-check: the boot's files against live-bootstrap's steps/tcc-0.9.26/tcc-0.9.26.x86.checksums"
while read -r want path; do
    case $path in
        /usr/bin/tcc-mes)
            check $path "$(pin tinycc/tcc-first-i386)" "pin " \
                "compiled by the seed; MesCC's is ${want:0:8}...; equals tests/pins/tinycc.sha256" ;;
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
check /usr/bin/hex0-export "$(pin tinycc/hex0-handoff/boot1/usr/bin/hex0-export)" "pin "
[ "$checked" = "$(wc -l < "$OUT/export.list")" ] || fail "$checked files compared, $(wc -l < "$OUT/export.list") exported"
[ "$bad" = 0 ] || fail "$bad file(s) differ (log: $OUT/boot.log)"
echo "i386-one-boot-check: OK, $checked files; live-bootstrap's published tcc-0.9.26 reached on builder-hex0"
echo "  in one boot, from sources: no program on the disk"
