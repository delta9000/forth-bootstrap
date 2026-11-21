#!/usr/bin/env bash
# tinycc/build-tools.sh -- the source-preparation tools of the TinyCC route,
# built from the seed.
#
#     tinycc/build-tools.sh        (from anywhere; works in the repo root)
#
# Writes build-out/tinycc/bin/: the programs live-bootstrap's kaem steps
# call, compiled by seed-cc (cc/driver/seed-cc-start.fth: seed Forth builds
# it with no other compiler; tests/pins/outputs.sha256 pins it) against
# chain/runtime/gcc-seed, as chain/plumbing/stage1.kaem builds them:
#   sha256sum catm mkdir cp chmod rm match
#       vendor/stage0-posix/mescc-tools-extra, unchanged
#   ungz, untar  mescc-tools-extra's, each with one simple-patch of ours
#       (tinycc/tools/*.before, *.after):
#       ungz-unsigned-bytes  stored() reads the block length bytes as plain
#           char.  Where char is signed, as in gcc-seed, a length byte of
#           0x80 or more fails the complement check ("puff() failed with
#           return code -2"); the pnut archive has such blocks.  bits()
#           already masks with 0xFF; the patch masks these four reads too.
#       untar-ustar-prefix  untar reads only the 100-byte name field.
#           GitHub's archive of live-bootstrap stores 200 long paths as
#           ustar prefix + name, among them steps/tcc-0.9.26/simple-patches/*;
#           stock untar writes those to the bare name in the current
#           directory, where tcc-0.9.27's files of the same names then
#           overwrite them.  The patch joins prefix and name.
#   simple-patch, checksum-transcriber  live-bootstrap's own C, from
#       steps/simple-patch-1.0/src and steps/checksum-transcriber-1.0/src of
#       the pinned live-bootstrap archive, unchanged.  simple-patch.c uses
#       open() and O_WRONLY without including their headers (M2-Mesoplanet
#       supplies them); tinycc/tools/simple-patch-unit.c includes them first.
#
# The patched tools need simple-patch, which is in live-bootstrap's
# archive, so: the archives are checked against tinycc/SOURCES by the
# seed-built sha256sum; stock ungz and untar (build-out/tinycc/bin-boot/)
# unpack live-bootstrap's archive into build-out/tinycc/lb-boot/;
# simple-patch is built from there (its path fits the name field, and that
# archive has no stored blocks with such lengths); it patches copies of
# ungz.c and untar.c; the patched ungz and untar unpack the archive again
# into build-out/tinycc/lb/, which build-first-tcc.sh and the junction read.
#
# Host programs here: bash runs this script; rm -rf and mkdir -p clear and
# make build-out directories; sha256sum, sed and cut compare the tools with
# tests/pins/tinycc.sha256 at the end.  None of them reads or writes a
# source file.  The tools are the same for any checkout path.
set -euo pipefail
cd "$(dirname "$0")/.."

IN=build-out/tinycc-inputs
OUT=build-out/tinycc
BIN=$OUT/bin
BOOT=$OUT/bin-boot
TS=$OUT/tools-src
CC=build-out/seed-cc/seed-cc
X=vendor/stage0-posix/mescc-tools-extra
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9

fail() { echo "build-tools: $*" >&2; exit 1; }

[ -f "$X/untar.c" ] || fail "$X missing; git submodule update --init vendor/stage0-posix"
[ -x seed-forth ] || seed/build.sh > /dev/null
[ -x "$CC" ] || ./seed-forth < cc/driver/seed-cc-start.fth \
    || fail "cc/driver/seed-cc-start.fth exited $?"

rm -rf "$BIN" "$BOOT" "$OUT/lb-boot" "$OUT/lb" "$TS"
mkdir -p "$BIN" "$BOOT" "$OUT/lb-boot" "$OUT/lb" "$TS/include"

# stage0-posix's tools as published; ungz and untar only to bootstrap
for t in sha256sum catm mkdir cp chmod rm match; do
    "$CC" -static "$X/$t.c" "$X/M2libc/bootstrappable.c" -o "$BIN/$t"
done
for t in ungz untar; do
    "$CC" -static "$X/$t.c" "$X/M2libc/bootstrappable.c" -o "$BOOT/$t"
done

# Every archive, before anything is unpacked
for a in tcc-0.9.26.tar.gz mes-0.28.tar.gz pnut-abc34a5207b1373d0a4e3dcb3d3d6df6e22ae23d.tar.gz $LB.tar.gz; do
    [ -f "$IN/$a" ] || fail "$IN/$a missing; run python3 tools/fetch-archives.py $IN/$a"
done
"$BIN/sha256sum" --check tinycc/SOURCES > "$OUT/sources.check" \
    || { cat "$OUT/sources.check" >&2; fail "an archive differs from tinycc/SOURCES"; }

# live-bootstrap's tree, by the stock tools; simple-patch from it
"$BOOT/ungz" --file "$IN/$LB.tar.gz" --output "$OUT/lb.tar" 2> /dev/null \
    || fail "stock ungz failed on $LB.tar.gz"
(cd "$OUT/lb-boot" && ../bin-boot/untar --non-strict --file ../lb.tar > /dev/null 2>&1) \
    || fail "stock untar failed on $LB.tar"
SP=$OUT/lb-boot/$LB/steps/simple-patch-1.0/src
"$CC" -static -I "$SP" -I "$X" tinycc/tools/simple-patch-unit.c -o "$BIN/simple-patch"

# ungz and untar with our patches, and live-bootstrap's tree again
for p in ungz:ungz-unsigned-bytes untar:untar-ustar-prefix; do
    t=${p%%:*}
    "$BIN/catm" "$TS/$t.c" "$X/$t.c"
    "$BIN/simple-patch" "$TS/$t.c" "tinycc/tools/${p#*:}.before" "tinycc/tools/${p#*:}.after" \
        || fail "tinycc/tools/${p#*:}.before is not in $X/$t.c"
    "$CC" -static -I "$X" "$TS/$t.c" "$X/M2libc/bootstrappable.c" -o "$BIN/$t"
done
"$BIN/ungz" --file "$IN/$LB.tar.gz" --output "$OUT/lb.tar" 2> /dev/null \
    || fail "ungz failed on $LB.tar.gz"
(cd "$OUT/lb" && ../bin/untar --non-strict --file ../lb.tar > /dev/null 2>&1) \
    || fail "untar failed on $LB.tar"
"$BIN/rm" "$OUT/lb.tar"

# checksum-transcriber includes <bootstrappable.h>.  -I M2libc would also
# put M2libc's stdio.h and the rest ahead of the runtime's, so that one
# header is copied into a directory of its own.
"$BIN/catm" "$TS/include/bootstrappable.h" "$X/M2libc/bootstrappable.h"
CT=$OUT/lb/$LB/steps/checksum-transcriber-1.0/src
"$CC" -static -I "$TS/include" "$CT/checksum-transcriber.c" \
    "$X/M2libc/bootstrappable.c" -o "$BIN/checksum-transcriber"

# The pins
bad=0
for f in "$BOOT"/* "$BIN"/*; do
    name=tinycc/${f#"$OUT/"}
    want=$(sed -n "s|^\([0-9a-f]\{64\}\)  $name\$|\1|p" tests/pins/tinycc.sha256)
    got=$(sha256sum "$f" | cut -d' ' -f1)
    if [ "$got" != "$want" ]; then
        echo "build-tools: $f is $got, tests/pins/tinycc.sha256 says ${want:-nothing}" >&2
        bad=$((bad + 1))
    fi
done
[ "$bad" = 0 ] || fail "$bad tool(s) differ from tests/pins/tinycc.sha256"
echo "build-tools: build-out/tinycc/bin-boot and bin as pinned in tests/pins/tinycc.sha256"
