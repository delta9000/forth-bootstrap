#!/usr/bin/env bash
# Stage A: the Forth C compiler checked against a GCC-built reference.
#
# A COMPARISON AGAINST A GCC-BUILT REFERENCE: it trusts the host gcc for
# m2-ref only.
#
# Verifies that M2-Planet compiled by the Forth compiler (cc-out-v1)
# produces the same .M1 output as the gcc-built reference (m2-ref) when
# self-compiling M2-Planet for amd64.  cc-out-v1 and m2-ref are rebuilt on
# every run.
#
# It does not go on to assemble that M1 or self-host M2-Planet again: those
# steps exercise M2-Planet's self-hosting, not the Forth compiler.
#
# Env overrides:
#   M2_PLANET   - path to M2-Planet checkout  (default vendor/M2-Planet)
#   BUILDROOT   - artifact directory          (default /tmp/seed-bootstrap)

set -euo pipefail
cd "$(dirname "$0")/../.."

M2_PLANET=${M2_PLANET:-vendor/M2-Planet}
BUILDROOT=${BUILDROOT:-/tmp/seed-bootstrap}

mkdir -p "$BUILDROOT"

fail() { printf 'stage-a-check: FAIL: %s\n' "$1" >&2; exit 1; }

# --- Build seed-forth if needed ---
[ -x seed-forth ] || ./seed/build.sh >/dev/null
[ -x seed-forth ] || fail "seed-forth build failed"

[ -f "$M2_PLANET/cc.c" ] || fail "M2_PLANET=$M2_PLANET is not initialized (run git submodule update --init --recursive)"
[ -f "$M2_PLANET/M2libc/bootstrappable.c" ] || fail "M2_PLANET/M2libc is not initialized (run git submodule update --init --recursive)"

# Resolve to absolute paths — the per-arch self-compile cd's into M2_PLANET
# and references BUILDROOT, so a relative BUILDROOT override would break.
M2_PLANET=$(cd "$M2_PLANET" && pwd)
BUILDROOT=$(cd "$BUILDROOT" && pwd)

# --- Build m2-ref (gcc reference), fresh on every run ---
# Never reuse an m2-ref left in $BUILDROOT: it may come from another pin,
# a STAGE0_COMPAT experiment, or another compiler.  Rebuilding takes ~1 s.
M2_PLANET=$M2_PLANET tests/cc/build-gcc-refs.sh "$BUILDROOT/gcc-ref" >/dev/null \
    || fail "gcc reference build failed"
cp "$BUILDROOT/gcc-ref/m2-ref" "$BUILDROOT/m2-ref"

# --- Build cc-out-v1 (seed-forth compiles M2-Planet monolith) ---
# CC_OUT: the compiler goes straight to $BUILDROOT, and seed-forth gets a
# private /tmp (unshare -rm) when the kernel allows it,
# so this never reads or clobbers a shared /tmp/cc-out.
rm -f "$BUILDROOT/cc-out-v1" "$BUILDROOT"/self-*-amd64.M1
CC_OUT="$BUILDROOT/cc-out-v1" ./tests/cc/build-m2planet-monolith.sh >/dev/null \
    || fail "monolith build failed"
[ -x "$BUILDROOT/cc-out-v1" ] || fail "$BUILDROOT/cc-out-v1 not produced"

# --- Stage A: M1 parity for amd64 ---
m2_srcs=(M2libc/bootstrappable.c cc_reader.c cc_strings.c cc_types.c
         cc_emit.c cc_core.c cc_macro.c cc.c cc.h cc_globals.c gcc_req.h)
m2_args=()
for s in "${m2_srcs[@]}"; do m2_args+=( -f "$s" ); done

ARCH=amd64

(cd "$M2_PLANET" && "$BUILDROOT/cc-out-v1" --architecture "$ARCH" --expand-includes \
    "${m2_args[@]}" -o "$BUILDROOT/self-v1-$ARCH.M1") \
    || fail "v1 self-compile ($ARCH) failed"

(cd "$M2_PLANET" && "$BUILDROOT/m2-ref" --architecture "$ARCH" --expand-includes \
    "${m2_args[@]}" -o "$BUILDROOT/self-ref-$ARCH.M1") \
    || fail "reference self-compile ($ARCH) failed"

cmp "$BUILDROOT/self-v1-$ARCH.M1" "$BUILDROOT/self-ref-$ARCH.M1" \
    || fail "v1 != reference at $ARCH"

echo "stage-a-check: self-v1-$ARCH.M1 == self-ref-$ARCH.M1 ($(wc -c < "$BUILDROOT/self-v1-$ARCH.M1") bytes)"
echo "stage-a-check: PASS"
