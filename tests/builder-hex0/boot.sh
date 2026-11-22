#!/bin/sh
# boot.sh LIST LOG [TIMEOUT]: build the disk from LIST and boot it the way
# tests/tinycc/i386-one-boot-check.sh boots its disk (live-bootstrap's rootfs.py
# flags), serial on stdout, each line timestamped by the host.
# Extra QEMU flags: QEMU_EXTRA (e.g. a monitor socket).  LIST is a name in
# tests/builder-hex0/; the disk, the log and the probe binary (build.sh)
# are in build-out/builder-hex0-probe/.
set -e
H=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$H/../.." && pwd)
mkdir -p "$R/build-out/builder-hex0-probe"
cd "$R/build-out/builder-hex0-probe"
BH=$R/build-out/tinycc-inputs/builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a
[ -f builder-hex0-x86-stage2.hex0 ] || cp "$BH/builder-hex0-x86-stage2.hex0" .
[ -f stage1.bin ] || "$R/vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed" \
    "$BH/builder-hex0-x86-stage1.hex0" stage1.bin
list=$1 log=$2 to=${3:-300}
img=$(basename "${list%.list}").img
python3 -I "$H/mkdisk.py" "$img" stage1.bin builder-hex0-x86-stage2.hex0 "$H/$list"
rc=0
timeout "$to" qemu-system-x86_64 -enable-kvm -m 4096M -smp 1 -drive file="$img",format=raw \
    -machine kernel-irqchip=split -no-reboot -nographic $QEMU_EXTRA < /dev/null 2>&1 \
    | python3 -I "$H/tsserial.py" > "$log" || rc=$?
echo "boot.sh: pipeline exit $rc" >> "$log"
