#!/bin/sh
# The route under K0 -> K1: QEMU runs K0 (from kernel/k0/k0.hex0); K0 runs seed
# Forth, which builds K1 with its own compiler (kernel/tools/k1-direct.recipe); K1
# imports the input disk and runs /k1.recipe (hex0-seed -> ... -> Linux),
# writes results to the output disk, and kexecs into the Linux it built.
# Host Python only copies raw pinned inputs into disk images; unpacking,
# patching and compilation all happen in the guest.
#   kernel/k1/run-chain.sh --direct-smoke   seed -> seed-cc, seed-ar, kaem (3 GiB)
#   kernel/k1/run-chain.sh --direct         seed -> bash 2.05b; needs the plumbing
#                                    and lexer archives in build-out/
#   kernel/k1/run-chain.sh [--direct-linux] seed -> GCC 4.0.4 fixed point -> late
#                                    tools -> gcc-10.5.0 -> Linux, kexec; also
#                                    build-out/distfiles and stage-b-inputs
# Optional: JOBS=N passes into guest make; K1_DISKS names the disk directory;
# K1_MEM the guest RAM; K1_RAM_FILE (avoid on an SSD: terabytes of writes
# over a full run) names a new build-out file for shared,
# non-preallocated RAM backing (K1_RAM_RESERVE defaults to 8G); QEMU names
# the emulator (default qemu-system-x86_64); HEX0 names another hex0
# assembler for K0 (the guest's own hex0-seed still comes from vendor/).
set -eu
cd "$(dirname "$0")/../.."
usage="usage: $0 [--direct-smoke | --direct | --direct-linux]"
[ "$#" -le 1 ] || { echo "$usage" >&2; exit 2; }
mode=${1:---direct-linux}
case $mode in
    --direct-smoke) D=${K1_DISKS:-build-out/k1-direct-smoke}; memory=${K1_MEM:-3G}; expected=1 ;;
    --direct)       D=${K1_DISKS:-build-out/k1-direct}; memory=${K1_MEM:-8G}; expected=1 ;;
    --direct-linux) D=${K1_DISKS:-build-out/k1-direct-linux}; memory=${K1_MEM:-24G}; expected=85 ;;
    *) echo "$usage" >&2; exit 2 ;;
esac
HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}
mkdir -p build-out/k1 "$D"
"$HEX0" kernel/k0/k0.hex0 build-out/k1/k0.bin
python3 kernel/k1/mkboot.py build-out/k1/boot.img
set -- "$D/in.img" "$mode"
[ "$mode" != --direct-linux ] || [ -z "${JOBS:-}" ] || set -- "$@" --jobs "$JOBS"
python3 kernel/k1/mkdisk.py "$@"
rm -f "$D/out.img"
truncate -s 4G "$D/out.img"
accel="-accel kvm -cpu host"
[ -w /dev/kvm ] || accel="-cpu max"
set --
if [ -n "${K1_RAM_FILE:-}" ]; then
    ram_file=$(python3 kernel/k1/mkram.py "$K1_RAM_FILE" "$memory" --reserve "${K1_RAM_RESERVE:-8G}")
    echo "run-chain: shared sparse RAM backing: $ram_file ($memory; reserve ${K1_RAM_RESERVE:-8G})"
    set -- -object "memory-backend-file,id=k1ram,size=$memory,mem-path=$ram_file,share=on,prealloc=off" \
           -machine memory-backend=k1ram
fi
set +e
"${QEMU:-qemu-system-x86_64}" "$@" $accel -m "$memory" -display none -monitor none \
    -serial file:"$D/serial.log" -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x01 \
    -kernel build-out/k1/k0.bin \
    -device loader,file=build-out/k1/boot.img,addr=0x50000000,force-raw=on \
    -drive file="$D/in.img",format=raw,if=ide,index=0 \
    -drive file="$D/out.img",format=raw,if=ide,index=1
rc=$?
set -e
echo "run-chain: qemu exit $rc (expected $expected)"
[ "$rc" -eq "$expected" ]
set -- "k0: K1 built by seed Forth; handing over"
case $mode in
    --direct-smoke) set -- "$@" "k1: PASS (seed-cc, seed-ar and kaem work under the K1 that seed Forth built)" ;;
    --direct) set -- "$@" "k1: PASS (direct route under K1: seed to bash 2.05b" ;;
    --direct-linux) set -- "$@" "k1: PASS (direct route under K1: seed to bash 2.05b" \
        "k1: GCC 4.0.4 fixed point and late tools built under K1" \
        'finish: K1 hands the machine to the Linux kernel it built' \
        'init: hello from a Linux kernel built from hex0 and seed-forth' \
        'init: Linux version 7.2.8' ;;
esac
for m in "$@"; do
    grep -Fq "$m" "$D/serial.log" || { echo "run-chain: missing guest marker: $m" >&2; exit 1; }
done
echo "run-chain: PASS ($mode)"
