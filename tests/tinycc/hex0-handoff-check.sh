#!/usr/bin/env bash
# tests/tinycc/hex0-handoff-check.sh -- the TinyCC route's i386 stages on
# live-bootstrap's own kernel, builder-hex0, in two QEMU boots.
#
#     tests/tinycc/hex0-handoff-check.sh        (CHECK_HEX0_HANDOFF=1 ./check-all.sh)
#     tests/tinycc/hex0-handoff-check.sh --probe    exit 0 when this can run here
#
# Boot 1: QEMU starts K0 (kernel/k0/k0.hex0) with no disk image of ours but
# an empty drive.  K0 runs seed Forth; seed Forth builds the recipe runner,
# which runs tinycc/hex0-handoff.recipe: seed Forth compiles the first tcc,
# the first tcc runs pass1.kaem's tcc-mes lines (mes libc and tcc-boot0)
# and builds boot 2's i386 programs, and tinycc/hex0-disk.c writes
# builder-hex0's disk onto the drive through K0's disk call.
#
# Boot 2: QEMU boots that drive.  builder-hex0 (stage 1 assembled in boot 1
# by hex0-seed, stage 2 compiled from hex0 by stage 1) reads the file
# stream from sector 175 and starts kaem, which runs live-bootstrap's
# pass1.kaem from "# Install" (tcc-boot0 -> tcc-boot1 -> tcc-boot2 -> tcc and
# the libraries).  tinycc/hex0-export.c then writes the ten files of
# tcc-0.9.26.x86.checksums to /dev/hda, which builder-hex0 flushes to the
# drive's first sectors when its stream ends.
#
# This script compares: the hand-off files boot 1 wrote into the stream
# with tests/pins/tinycc.sha256, and boot 2's exported files with
# live-bootstrap's published tcc-0.9.26.x86.checksums (tcc-mes and
# tcc-boot0 with this route's pins).
#
# Host involvement: the sources are unpacked and patched by the tools
# tinycc/build-tools.sh builds from the seed (tinycc/build-first-tcc.sh
# --prepare; tinycc/lb-replay.sh --prepare in bwrap, where host bash runs
# live-bootstrap's kaem text and host grep, awk, sed and cat cut it);
# hex0-seed builds seed-forth and K0; this script cuts boot 2's script
# from the pinned pass1.kaem, lists the files of the stream, writes K0's
# memory image (python3, copying the prepared sources into it), creates
# the empty drive, starts QEMU twice and reads the drive.  No byte of the
# drive is written by the host.
set -euo pipefail
cd "$(dirname "$0")/../.."

IN=build-out/tinycc-inputs
OUT=build-out/tinycc/hex0-handoff
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9
BH=builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a
HEX0=vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed
QEMU=${QEMU:-qemu-system-x86_64}

probe() {
    command -v "$QEMU" > /dev/null || { echo "missing: $QEMU"; return 1; }
    command -v bwrap > /dev/null || { echo "missing: bwrap"; return 1; }
    # lb-replay.sh runs these from the host's /usr, mounted at /host/usr
    for t in bash grep awk sed cat; do
        [ -x /usr/bin/$t ] || { echo "missing: /usr/bin/$t"; return 1; }
    done
    [ -w /dev/kvm ] || { echo "no KVM (/dev/kvm)"; return 1; }
    [ -f vendor/stage0-posix/mescc-tools-extra/untar.c ] \
        || { echo "missing vendor/stage0-posix (git submodule update --init --recursive)"; return 1; }
    for a in tcc-0.9.26.tar.gz mes-0.28.tar.gz $LB.tar.gz $BH.tar.gz; do
        [ -f "$IN/$a" ] || { echo "missing $IN/$a (python3 tools/fetch-archives.py $IN/$a)"; return 1; }
    done
}
if [ "${1:-}" = --probe ]; then
    probe
    exit
fi
why=$(probe) || { echo "hex0-handoff-check: cannot run: $why" >&2; exit 1; }
fail() { echo "hex0-handoff-check: FAIL: $*" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"

# ---- preparation: sources, boot 2's script, K0's image ----
# The seed-built tools (tinycc/build-tools.sh, run by build-first-tcc.sh)
# check tinycc/SOURCES's archives, unpack live-bootstrap's tree into
# build-out/tinycc/lb/ and lay out build-out/tcc-sources/.
tinycc/build-first-tcc.sh --prepare
BIN=build-out/tinycc/bin
# builder-hex0's two stages: its archive against tinycc/hex0-handoff.SOURCES
# (not tinycc/SOURCES, which the junction checks whole), then ungz and untar
"$BIN/sha256sum" --check tinycc/hex0-handoff.SOURCES > /dev/null \
    || fail "$IN/$BH.tar.gz: sha256 differs from tinycc/hex0-handoff.SOURCES"
rm -rf "$IN/$BH"
"$BIN/ungz" --file "$IN/$BH.tar.gz" --output "$OUT/builder-hex0.tar" 2> /dev/null \
    || fail "ungz failed on $BH.tar.gz"
(cd "$IN" && ../tinycc/bin/untar --non-strict --file ../tinycc/hex0-handoff/builder-hex0.tar \
    > /dev/null 2>&1) \
    || fail "untar failed on $BH.tar"
# lb-replay.sh --prepare's root is the live-bootstrap tree build-tools.sh
# unpacked: its steps/ and seed/ are where live-bootstrap's / has them,
# plus the directories seed.kaem makes and the two distfiles, mounted
P=build-out/tinycc/lb/$LB
"$BIN/mkdir" -p "$P"/usr/bin "$P"/usr/lib/mes "$P"/usr/include/mes "$P"/tmp \
    "$P"/dev "$P"/external/distfiles
interp=/lib64/ld-linux-x86-64.so.2
libpath=/host/usr/lib
for d in /usr/lib64 /usr/lib/x86_64-linux-gnu; do
    [ -d "$d" ] && libpath=$libpath:/host$d
done
bwrap --bind "$P" / \
    --ro-bind "$IN/tcc-0.9.26.tar.gz" /external/distfiles/tcc-0.9.26.tar.gz \
    --ro-bind "$IN/mes-0.28.tar.gz" /external/distfiles/mes-0.28.tar.gz \
    --ro-bind "$BIN" /forth-bootstrap/bin \
    --ro-bind /usr /host/usr \
    --ro-bind "$(realpath "$interp")" "$interp" \
    --ro-bind tinycc /forth-bootstrap/tinycc \
    --dev /dev --proc /proc --clearenv --setenv LD_LIBRARY_PATH "$libpath" --chdir / \
    /host/usr/bin/bash /forth-bootstrap/tinycc/lb-replay.sh --prepare > "$OUT/prep.log" 2>&1 \
    || { tail -20 "$OUT/prep.log" >&2; fail "lb-replay.sh --prepare (log: $OUT/prep.log)"; }

python3 -I tinycc/hex0-handoff-stream.py "$P" "$OUT"
[ -x seed-forth ] || seed/build.sh > /dev/null
"$HEX0" kernel/k0/k0.hex0 "$OUT/k0.bin"
python3 -I tinycc/hex0-handoff-image.py "$OUT/boot1.img" "$P"

# ---- boot 1: K0 ----
truncate -s 64M "$OUT/disk.img"
rc=0
"$QEMU" -accel kvm -cpu host -m 4G -display none -monitor none \
    -serial file:"$OUT/boot1.log" -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x01 \
    -kernel "$OUT/k0.bin" \
    -device loader,file="$OUT/boot1.img",addr=0x50000000,force-raw=on \
    -drive file="$OUT/disk.img",format=raw,if=ide,index=0 || rc=$?
echo "hex0-handoff-check: boot 1 (K0) qemu exit $rc (1 is K0's exit 0)"
[ "$rc" = 1 ] || { tail -20 "$OUT/boot1.log" >&2; fail "boot 1 (log: $OUT/boot1.log)"; }
grep -a '^hex0-handoff' "$OUT/boot1.log"

# ---- the stream boot 1 wrote, hashed on the host ----
python3 -I tinycc/hex0-records.py "$OUT/disk.img" 175 > "$OUT/stream.sha256"
tail -1 "$OUT/stream.sha256"
grep -qxF '# end: /usr/bin/kaem --verbose' "$OUT/stream.sha256" || fail "the stream does not end in kaem's start"
pin() { sed -n "s|^\([0-9a-f]\{64\}\)  $1\$|\1|p" tests/pins/tinycc.sha256; }
TCCDIR=/steps/tcc-0.9.26/build/tcc-0.9.26-1147-gee75a10c
bad=0
check_stream() {    # PATH-IN-STREAM PIN-NAME
    local got want
    got=$(sed -n "s|^\([0-9a-f]\{64\}\)  $1\$|\1|p" "$OUT/stream.sha256")
    want=$(pin "$2")
    if [ -n "$got" ] && [ "$got" = "$want" ]; then
        echo "  pin   $got  $1"
    else
        echo "  FAIL  ${got:-missing}  $1 (tests/pins/tinycc.sha256 $2: ${want:-nothing})"
        bad=$((bad + 1))
    fi
}
echo "hex0-handoff-check: boot 1's hand-off files in the stream, against tests/pins/tinycc.sha256"
check_stream /usr/bin/tcc-mes tinycc/tcc-first
check_stream $TCCDIR/tcc-boot0 tinycc/junction/usr/bin/tcc-boot0
for f in /usr/lib/mes/crt1.o /usr/lib/mes/crti.o /usr/lib/mes/crtn.o /usr/lib/mes/libc.a \
         /usr/lib/mes/libgetopt.a /usr/lib/mes/tcc/libtcc1.a /usr/bin/kaem /usr/bin/cp \
         /usr/bin/chmod /usr/bin/match /usr/bin/rm /usr/bin/hex0-export; do
    check_stream $f tinycc/hex0-handoff/boot1$f
done
[ "$bad" = 0 ] || fail "$bad hand-off file(s) differ"

# ---- boot 2: builder-hex0, as live-bootstrap's rootfs.py starts it ----
rc=0
"$QEMU" -enable-kvm -m 4096M -smp 1 -drive file="$OUT/disk.img",format=raw \
    -machine kernel-irqchip=split -no-reboot -nographic < /dev/null > "$OUT/boot2.log" 2>&1 || rc=$?
echo "hex0-handoff-check: boot 2 (builder-hex0) qemu exit $rc"
tr -d '\r' < "$OUT/boot2.log" | grep -aE '^(tcc version|Build finished)' || true
[ "$rc" = 0 ] || { tail -20 "$OUT/boot2.log" >&2; fail "boot 2 (log: $OUT/boot2.log)"; }

# ---- what boot 2 exported, against live-bootstrap's published checksums ----
python3 -I tinycc/hex0-records.py "$OUT/disk.img" 0 > "$OUT/export.sha256"
grep -qxF '# end: end' "$OUT/export.sha256" || { tail -20 "$OUT/boot2.log" >&2; fail "no export from boot 2"; }
echo "hex0-handoff-check: boot 2's files against live-bootstrap's steps/tcc-0.9.26/tcc-0.9.26.x86.checksums"
while read -r want path; do
    got=$(sed -n "s|^\([0-9a-f]\{64\}\)  $path\$|\1|p" "$OUT/export.sha256")
    case $path in
        /usr/bin/tcc-mes) p=$(pin tinycc/tcc-first) ;;
        /usr/bin/tcc-boot0) p=$(pin tinycc/junction/usr/bin/tcc-boot0) ;;
        *) p= ;;
    esac
    if [ -n "$p" ]; then
        if [ "$got" = "$p" ]; then
            echo "  pin   $got  $path (MesCC's is ${want:0:8}...; equals tests/pins/tinycc.sha256)"
        else
            echo "  FAIL  ${got:-missing}  $path (tests/pins/tinycc.sha256 says $p)"
            bad=$((bad + 1))
        fi
    elif [ "$got" = "$want" ]; then
        echo "  same  $got  $path"
    else
        echo "  FAIL  ${got:-missing}  $path (live-bootstrap publishes $want)"
        bad=$((bad + 1))
    fi
done < "$P/steps/tcc-0.9.26/tcc-0.9.26.x86.checksums"
[ "$bad" = 0 ] || fail "$bad file(s) differ (logs: $OUT/boot1.log, $OUT/boot2.log)"
echo "hex0-handoff-check: OK, live-bootstrap's published tcc-0.9.26 reached on builder-hex0 from K0's boot"
