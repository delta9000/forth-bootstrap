#!/usr/bin/env bash
# tinycc/build-tools-i386.sh -- the source-preparation tools as i386
# programs, built from the seed.
#
#     tinycc/build-tools-i386.sh    (from anywhere; works in the repo root)
#
# Writes build-out/tinycc/bin-i386/: the thirteen programs of
# tinycc/build-tools.sh, from the same C (stage0-posix's mescc-tools-extra
# with our two patches, live-bootstrap's simple-patch and
# checksum-transcriber, against M2libc), compiled by seed-forth with the
# i386 layers (cc/i386/layers.sh) and tinycc/m2libc-native-i386.c in place
# of M2libc's assembly.  They are static ELF32 programs for Linux's int
# 0x80 and for builder-hex0.
#
# build-tools.sh runs first: it checks the archives, unpacks
# live-bootstrap's tree and patches ungz.c and untar.c, and its catm joins
# each tool's Forth input here.  seed-forth is the x86-64 one.  So this
# script shows that the i386 back end compiles the tools; building them
# with no x86-64 program is the i386 seed's work, not done here.
#
# tests/tinycc/i386-tools-check.sh runs them against build-tools.sh's.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build-out/tinycc
BIN=$OUT/bin
BIN32=$OUT/bin-i386
TS=$OUT/tools-src
X=vendor/stage0-posix/mescc-tools-extra
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9

fail() { echo "build-tools-i386: $*" >&2; exit 1; }

tinycc/build-tools.sh
rm -rf "$BIN32"
mkdir -p "$BIN32"
mapfile -t layers < <(cc/i386/layers.sh)

# tool NAME SOURCE: seed-forth compiles SOURCE to $BIN32/NAME.  The Forth
# outer interpreter reports an unknown word on stdout and goes on, so
# anything on stdout is a failure even when the exit status is 0.
tool() {
    local out=$BIN32/$1 rc=0
    printf 'create tool-output s, %s [lit] 0 c,\ncreate tool-source s, %s\ntool-source [lit] %d cc-prep-source-name\n' \
        "$out" "$2" "${#2}" > "$OUT/tool-names-i386.fth"
    "$BIN/catm" "$OUT/tool-i386.input" "${layers[@]}" "$OUT/tool-names-i386.fth" \
        tinycc/tool-compile.fth tinycc/m2libc-native-i386.c "$2"
    ./seed-forth < "$OUT/tool-i386.input" > "$OUT/tool-i386.stdout" 2>&1 || rc=$?
    if [ "$rc" != 0 ] || [ -s "$OUT/tool-i386.stdout" ] || [ ! -s "$out" ]; then
        head -c 2000 "$OUT/tool-i386.stdout" >&2
        fail "seed-forth exited $rc building $out (cc/ error codes are the exit status)"
    fi
}

for t in catm sha256sum mkdir cp chmod rm match; do
    tool $t "$X/$t.c"
done
for t in ungz untar; do
    tool $t "$TS/$t.c"
done
tool simple-patch "$OUT/lb/$LB/steps/simple-patch-1.0/src/simple-patch.c"
tool checksum-transcriber "$OUT/lb/$LB/steps/checksum-transcriber-1.0/src/checksum-transcriber.c"

# The pins
bad=0
for f in "$BIN32"/*; do
    name=tinycc/${f#"$OUT/"}
    want=$(sed -n "s|^\([0-9a-f]\{64\}\)  $name\$|\1|p" tests/pins/tinycc.sha256)
    got=$(sha256sum "$f" | cut -d' ' -f1)
    if [ "$got" != "$want" ]; then
        echo "build-tools-i386: $f is $got, tests/pins/tinycc.sha256 says ${want:-nothing}" >&2
        bad=$((bad + 1))
    fi
done
[ "$bad" = 0 ] || fail "$bad tool(s) differ from tests/pins/tinycc.sha256"
echo "build-tools-i386: build-out/tinycc/bin-i386 as pinned in tests/pins/tinycc.sha256"
