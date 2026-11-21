#!/bin/sh
# k0.hex0 is K0's only source, written directly as commented hex0.  Check
# it: every comment assembles to its line's bytes with GNU as (and with
# llvm-mc, when installed; kernel/k0/asm-check.py), and hex0-seed's k0.bin
# has the sha256 tests/pins/k0.sha256 pins.  Needs as and python3;
# HEX0 names another hex0 assembler to use instead of stage0-posix's.
set -eu
HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
python3 kernel/k0/asm-check.py kernel/k0/k0.hex0
"$HEX0" kernel/k0/k0.hex0 "$t/k0.bin"
want=$(sed -n 's/^\([0-9a-f]\{64\}\)  k0.bin$/\1/p' tests/pins/k0.sha256)
got=$(sha256sum "$t/k0.bin" | cut -d' ' -f1)
[ "$got" = "$want" ] || { echo "k0.bin is $got, tests/pins/k0.sha256 says $want" >&2; exit 1; }
echo "k0: hex0-seed builds k0.hex0 to $(wc -c < "$t/k0.bin") bytes, sha256 $got as pinned"
