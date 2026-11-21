#!/bin/sh
# k0.hex0 is what gets built; k0.asm is the same program as NASM source.
# Prove they agree: k0.hex0 is exactly what asm2hex0.py writes from
# k0.asm, hex0-seed's k0.bin is byte-identical to nasm's, and its sha256
# is tests/pins/k0.sha256's.  Needs nasm;
# HEX0 names another hex0 assembler to use instead of stage0-posix's.
set -eu
HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
python3 kernel/k0/asm2hex0.py kernel/k0/k0.asm "$t/k0.hex0"
cmp kernel/k0/k0.hex0 "$t/k0.hex0" || { echo "k0.hex0 is stale: rerun asm2hex0.py" >&2; exit 1; }
nasm -f bin -o "$t/nasm.bin" kernel/k0/k0.asm
"$HEX0" kernel/k0/k0.hex0 "$t/hex0.bin"
cmp "$t/nasm.bin" "$t/hex0.bin"
want=$(sed -n 's/^\([0-9a-f]\{64\}\)  k0.bin$/\1/p' tests/pins/k0.sha256)
got=$(sha256sum "$t/hex0.bin" | cut -d' ' -f1)
[ "$got" = "$want" ] || { echo "k0.bin is $got, tests/pins/k0.sha256 says $want" >&2; exit 1; }
echo "k0: k0.hex0 matches k0.asm ($(wc -c < "$t/hex0.bin") bytes, sha256 $got as pinned)"
