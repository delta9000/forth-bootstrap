#!/usr/bin/env bash
# hi-check.sh -- forth/130-asm.fth assembles and links a hand-written M1
# program (ELF header included) that writes "hi" and exits 42.
#
# The assembler writes its output to the fixed path /tmp/asm-out
# (asm-out-path in forth/130-asm.fth); any existing file there is moved
# aside and restored. Checks: stdout "hi", exit status 42, 160 bytes.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -x seed-forth ] || seed/build.sh >/dev/null

work=$(mktemp -d)
saved=
if [ -e /tmp/asm-out ] || [ -L /tmp/asm-out ]; then
    saved=$work/saved-asm-out
    mv /tmp/asm-out "$saved"
fi
cleanup() {
    rm -f /tmp/asm-out
    [ -z "$saved" ] || mv "$saved" /tmp/asm-out
    rm -rf "$work"
}
trap cleanup EXIT

cat > "$work/hi.M1" <<'M1'
DEFINE mov_eax, B8
DEFINE mov_edi, BF
DEFINE mov_esi, BE
DEFINE mov_edx, BA
DEFINE jmp8 EB
DEFINE syscall 0F05

:ELF_base
'7F454C46 02 01 01 03 00 00000000000000'
'0200 3E00 01000000'
&_start '00000000'
%ELF_phdr>ELF_base '00000000'
'0000000000000000 00000000'
'4000 3800 0100 0000 0000 0000'
:ELF_phdr
'01000000 07000000 0000000000000000'
&ELF_base '00000000' &ELF_base '00000000'
%ELF_end>ELF_base '00000000'
%ELF_end>ELF_base '00000000'
'0100000000000000'

:_start
    mov_eax, %1  mov_edi, %1
    mov_esi, &msg  mov_edx, %3
    syscall
    jmp8 !done
:msg "hi
"
:done
    mov_eax, %60  mov_edi, %42  syscall
:ELF_end
M1

{ cat forth/010-lib.fth forth/130-asm.fth; echo asm-main; cat "$work/hi.M1"; } \
    | ./seed-forth
mv /tmp/asm-out "$work/hi"
chmod +x "$work/hi"
status=0
out=$("$work/hi") || status=$?
size=$(wc -c < "$work/hi")
fail() { echo "hi-check: FAIL: $*" >&2; exit 1; }
[ "$out" = hi ] || fail "output '$out', expected 'hi'"
[ "$status" = 42 ] || fail "exit $status, expected 42"
[ "$size" = 160 ] || fail "$size bytes, expected 160"
echo "hi-check: PASS (hi, exit 42, 160 bytes)"
