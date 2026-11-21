#!/bin/sh
# 000-seed.hex0 is what gets built; seed.asm is the same program as NASM
# source.  Prove they agree: 000-seed.hex0 is exactly what asm2hex0.py
# writes from seed.asm, and hex0-seed's seed-forth is byte-identical to
# nasm's.  Needs nasm and python3; HEX0 names another hex0 assembler to
# use instead of stage0-posix's.  Run from the repository root.
set -eu
HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
python3 seed/asm2hex0.py seed/seed.asm "$t/seed.hex0" > /dev/null
cmp seed/000-seed.hex0 "$t/seed.hex0" || { echo "000-seed.hex0 is stale: rerun seed/asm2hex0.py" >&2; exit 1; }
nasm -f bin -o "$t/nasm.bin" seed/seed.asm
"$HEX0" seed/000-seed.hex0 "$t/hex0.bin"
cmp "$t/nasm.bin" "$t/hex0.bin"
echo "seed: 000-seed.hex0 matches seed.asm ($(wc -c < "$t/hex0.bin") bytes)"
