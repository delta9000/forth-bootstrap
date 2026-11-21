#!/usr/bin/env bash
# tests/cc/i386/x86-64-bytes-check.sh -- no x86-64 instruction reaches the
# i386 first tcc.
#
#     tests/cc/i386/x86-64-bytes-check.sh       (from anywhere)
#
# The i386 back end redefines the encoders of cc/090-cc-emit.fth, but an
# encoder it missed, or raw bytes inside a later layer, would still emit
# x86-64 code, silently.  This builds the i386 first tcc again from a copy
# of the shared layers in which such places die with error 130 instead:
#   in cc/090-cc-emit.fth, every x{ ... }, except in the five words whose
#   bytes are the same on i386 (the rel32 jz, jnz, jmp and call
#   placeholders, and call rax, FF D0);
#   in the layers after it, every `[lit] N cc-emit-byte` with N from 64 to
#   79, a REX prefix (those layers spell their bytes in decimal).  What
#   they emit without one is the same on i386: E8, E9, 0F 84, 0F 85, C3,
#   rep movsb, rep stosb, and data.
# The compile must still succeed and give the same bytes as
# build-out/tinycc/tcc-first-i386: nothing it runs was changed.  That
# covers the code this one compile reaches, not every C program.
set -euo pipefail
cd "$(dirname "$0")/../../.."

OUT=build-out/tinycc
fail() { echo "x86-64-bytes-check: FAIL: $*" >&2; exit 1; }

tinycc/build-first-tcc-i386.sh > /dev/null
traps=0
for f in $(cc/i386/layers.sh); do
    case $f in
        cc/090-*)
            awk '/^: / { same = ($2 ~ /^cc-emit-(jz|jnz|jmp|call)-rel32-placeholder$/ || $2 == "cc-emit-call-rax") }
                 !same && !/^\\/ { sub(/x\{ /, "[lit] 130 cc-die x{ ") }
                 { print }' "$f" ;;
        cc/1[0-9][0-9]-*)
            sed -E 's/\[lit\] +(6[4-9]|7[0-9]) cc-emit-byte/[lit] 130 cc-die/' "$f" ;;
        *)
            cat "$f" ;;
    esac
done > "$OUT/x86-64-bytes.layers"
traps=$(grep -c '\[lit\] 130 cc-die' "$OUT/x86-64-bytes.layers")
sed 's|build-out/tinycc/tcc-first-i386 |build-out/tinycc/x86-64-bytes.tcc |' tinycc/tcc-compile-i386.fth \
    > "$OUT/x86-64-bytes.driver"
rm -f "$OUT/x86-64-bytes.tcc"
rc=0
cat "$OUT/x86-64-bytes.layers" "$OUT/x86-64-bytes.driver" build-out/tcc-sources-i386/direct-input.c \
    | ./seed-forth > "$OUT/x86-64-bytes.stdout" 2>&1 || rc=$?
[ "$rc" = 0 ] && [ ! -s "$OUT/x86-64-bytes.stdout" ] \
    || { head -c 500 "$OUT/x86-64-bytes.stdout" >&2; fail "seed-forth exited $rc: an x86-64 encoder was reached"; }
cmp "$OUT/x86-64-bytes.tcc" "$OUT/tcc-first-i386" || fail "the trapped layers built a different tcc"
echo "x86-64-bytes-check: OK, $traps x86-64 sequences trapped, none reached, same bytes as $OUT/tcc-first-i386"
