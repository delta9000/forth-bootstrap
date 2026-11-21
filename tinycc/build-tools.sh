#!/usr/bin/env bash
# tinycc/build-tools.sh -- the source-preparation tools of the TinyCC route,
# built from the seed.
#
#     tinycc/build-tools.sh        (from anywhere; works in the repo root)
#
# Writes build-out/tinycc/bin/: the programs live-bootstrap's kaem steps
# call, each compiled by seed-forth in native mode (the compiler layers 020
# to 119, as for the first tcc) against stage0-posix's M2libc, with
# tinycc/m2libc-native.c in place of M2libc's assembly:
#   sha256sum catm mkdir cp chmod rm match
#       vendor/stage0-posix/mescc-tools-extra, unchanged
#   ungz, untar  mescc-tools-extra's, each with one simple-patch of ours
#       (tinycc/tools/*.before, *.after):
#       ungz-unsigned-bytes  stored() reads the block length bytes as plain
#           char.  Where char is signed, a length byte of 0x80 or more
#           fails the complement check ("puff() failed with return code
#           -2"); the pnut archive, an input until the first tcc moved to
#           Mes libc, has such blocks; the three left do not.  bits()
#           already masks with 0xFF; the patch masks these four reads too.
#       untar-ustar-prefix  untar reads only the 100-byte name field.
#           GitHub's archive of live-bootstrap stores 200 long paths as
#           ustar prefix + name, among them steps/tcc-0.9.26/simple-patches/*;
#           stock untar writes those to the bare name in the current
#           directory, where tcc-0.9.27's files of the same names then
#           overwrite them.  The patch joins prefix and name.
#   simple-patch, checksum-transcriber  live-bootstrap's own C, from
#       steps/simple-patch-1.0/src and steps/checksum-transcriber-1.0/src of
#       the pinned live-bootstrap archive, unchanged.
#
# Each tool's Forth input is build-out/tinycc/tool.input: the layers,
# three lines naming the output and the C source (bash's printf writes
# them to build-out/tinycc/tool-names.fth; they are what a command line
# would say), tinycc/tool-compile.fth, tinycc/m2libc-native.c and the
# tool's C source, joined by the seed-built catm.  catm's own input is
# joined by tinycc/catm-start.fth, which seed-forth runs before catm
# exists, with its names in tinycc/tools/catm.fth.
#
# The patched tools need simple-patch, which is in live-bootstrap's
# archive, so: the archives are checked against tinycc/SOURCES by the
# seed-built sha256sum; stock ungz and untar (build-out/tinycc/bin-boot/)
# unpack live-bootstrap's archive into build-out/tinycc/lb-boot/;
# simple-patch is built from there (its path fits the name field); it
# patches copies of ungz.c and untar.c; the patched ungz and untar unpack
# the archive again into build-out/tinycc/lb/, which build-first-tcc.sh
# and the junction read.
#
# Host programs here: bash runs this script and its printf writes the
# names; rm -rf and mkdir -p clear and make build-out directories;
# sha256sum, sed and cut compare the tools with tests/pins/tinycc.sha256
# at the end.  None of them reads or writes a source file.  The tools are
# the same for any checkout path.
set -euo pipefail
cd "$(dirname "$0")/.."

IN=build-out/tinycc-inputs
OUT=build-out/tinycc
BIN=$OUT/bin
BOOT=$OUT/bin-boot
TS=$OUT/tools-src
X=vendor/stage0-posix/mescc-tools-extra
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9

fail() { echo "build-tools: $*" >&2; exit 1; }

[ -f "$X/untar.c" ] || fail "$X missing; git submodule update --init --recursive vendor/stage0-posix"
[ -x seed-forth ] || seed/build.sh > /dev/null

rm -rf "$BIN" "$BOOT" "$OUT/lb-boot" "$OUT/lb" "$TS"
mkdir -p "$BIN" "$BOOT" "$OUT/lb-boot" "$OUT/lb" "$TS"

# Native mode loads 020 to 119 except 081, as for the first tcc.
layers=(forth/010-lib.fth)
for n in 020 030 040 050 060 070 080 090 100 110 112 114 115 116 117 118 119; do
    layers+=(cc/$n-*.fth)
done

# compile INPUT OUTPUT: seed-forth reads INPUT and writes OUTPUT.  The
# Forth outer interpreter reports an unknown word on stdout and goes on,
# so anything on stdout is a failure even when the exit status is 0.
compile() {
    local rc=0
    rm -f "$2"
    ./seed-forth < "$1" > "$OUT/tool.stdout" 2>&1 || rc=$?
    if [ "$rc" != 0 ] || [ -s "$OUT/tool.stdout" ] || [ ! -s "$2" ]; then
        head -c 2000 "$OUT/tool.stdout" >&2
        fail "seed-forth exited $rc building $2 (cc/ error codes are the exit status)"
    fi
}

# tool OUTPUT SOURCE
tool() {
    printf 'create tool-output s, %s [lit] 0 c,\ncreate tool-source s, %s\ntool-source [lit] %d cc-prep-source-name\n' \
        "$1" "$2" "${#2}" > "$OUT/tool-names.fth"
    "$BIN/catm" "$OUT/tool.input" "${layers[@]}" "$OUT/tool-names.fth" \
        tinycc/tool-compile.fth tinycc/m2libc-native.c "$2"
    compile "$OUT/tool.input" "$1"
}

# catm, from an input the seed joins
./seed-forth < tinycc/catm-start.fth || fail "tinycc/catm-start.fth exited $?"
compile "$OUT/catm.input" "$BIN/catm"

# stage0-posix's tools as published; ungz and untar only to bootstrap
for t in sha256sum mkdir cp chmod rm match; do
    tool "$BIN/$t" "$X/$t.c"
done
for t in ungz untar; do
    tool "$BOOT/$t" "$X/$t.c"
done

# Every archive, before anything is unpacked
for a in tcc-0.9.26.tar.gz mes-0.28.tar.gz $LB.tar.gz; do
    [ -f "$IN/$a" ] || fail "$IN/$a missing; run python3 tools/fetch-archives.py $IN/$a"
done
"$BIN/sha256sum" --check tinycc/SOURCES > "$OUT/sources.check" \
    || { cat "$OUT/sources.check" >&2; fail "an archive differs from tinycc/SOURCES"; }

# live-bootstrap's tree, by the stock tools; simple-patch from it
"$BOOT/ungz" --file "$IN/$LB.tar.gz" --output "$OUT/lb.tar" 2> /dev/null \
    || fail "stock ungz failed on $LB.tar.gz"
(cd "$OUT/lb-boot" && ../bin-boot/untar --non-strict --file ../lb.tar > /dev/null 2>&1) \
    || fail "stock untar failed on $LB.tar"
tool "$BIN/simple-patch" "$OUT/lb-boot/$LB/steps/simple-patch-1.0/src/simple-patch.c"

# ungz and untar with our patches, and live-bootstrap's tree again
for p in ungz:ungz-unsigned-bytes untar:untar-ustar-prefix; do
    t=${p%%:*}
    "$BIN/catm" "$TS/$t.c" "$X/$t.c"
    "$BIN/simple-patch" "$TS/$t.c" "tinycc/tools/${p#*:}.before" "tinycc/tools/${p#*:}.after" \
        || fail "tinycc/tools/${p#*:}.before is not in $X/$t.c"
    tool "$BIN/$t" "$TS/$t.c"
done
"$BIN/ungz" --file "$IN/$LB.tar.gz" --output "$OUT/lb.tar" 2> /dev/null \
    || fail "ungz failed on $LB.tar.gz"
(cd "$OUT/lb" && ../bin/untar --non-strict --file ../lb.tar > /dev/null 2>&1) \
    || fail "untar failed on $LB.tar"
"$BIN/rm" "$OUT/lb.tar"

tool "$BIN/checksum-transcriber" "$OUT/lb/$LB/steps/checksum-transcriber-1.0/src/checksum-transcriber.c"

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
