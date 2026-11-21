#!/bin/sh
# cc/i386/layers.sh -- print the files of the i386 native compiler, in load
# order, relative to the repository root.
#
# The native layers of the x86-64 compiler (020 to 118 without 081, 114 and
# 116), with the i386 files among them: each redefines words of the layer
# before it, for the layers after it.  080 and 119 are not loaded;
# 080-elf32.fth and 119-runtime.fth stand in their place.
cd "$(dirname "$0")/../.." || exit 1
echo forth/010-lib.fth
for n in 020 030 040 050 060 i386/065 070 i386/080 090 i386/090 100 i386/100 \
         110 112 115 117 i386/117 118 i386/119; do
    case $n in
        i386/*) ls cc/i386/${n#i386/}-*.fth ;;
        *)      ls cc/$n-cc-*.fth ;;
    esac
done
