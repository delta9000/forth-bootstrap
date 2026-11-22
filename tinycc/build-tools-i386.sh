#!/usr/bin/env bash
# tinycc/build-tools-i386.sh -- kaem and the source-preparation tools,
# built by the i386 seed.
#
#     tinycc/build-tools-i386.sh    (from anywhere; works in the repo root)
#
# The host runs what the one boot runs (tinycc/i386-one-boot-disk.py writes
# the same commands into /kaem.run), in the same order.  Every program is
# compiled by one run of the seed,
#     seed-forth-i386 forth/i386/010-lib.fth tinycc/i386-seed/tool.fth OUT SOURCE...
# which reads tinycc/m2libc-native-i386.c and then the SOURCEs as one unit
# and writes OUT, a static ELF32 program for Linux's int 0x80 and for
# builder-hex0.  The seed is ./seed-forth-i386 (seed/i386/build.sh builds
# it here), an i386 program, so the host kernel needs its IA32 support.
#
# Writes
#   build-out/tinycc/kaem-i386   vendor/mescc-tools/Kaem, its three files
#       behind tinycc/m2libc-kaem-i386.c, the process calls only kaem makes
#   build-out/tinycc/bin-boot-i386/   ungz and untar from stage0-posix's
#       sources as published, used once, to reach simple-patch's source
#   build-out/tinycc/bin-i386/
#       sha256sum catm mkdir cp chmod rm match
#           vendor/stage0-posix/mescc-tools-extra, unchanged
#       ungz, untar  mescc-tools-extra's, each with one simple-patch of
#           ours (tinycc/tools/*.before, *.after):
#           ungz-unsigned-bytes  stored() reads the block length bytes as
#               plain char.  Where char is signed, a length byte of 0x80 or
#               more fails the complement check ("puff() failed with return
#               code -2").  bits() already masks with 0xFF; the patch masks
#               these four reads too.
#           untar-ustar-prefix  untar reads only the 100-byte name field.
#               GitHub's archive of live-bootstrap stores 200 long paths as
#               ustar prefix + name, among them
#               steps/tcc-0.9.26/simple-patches/*; stock untar writes those
#               to the bare name in the current directory, where
#               tcc-0.9.27's files of the same names then overwrite them.
#               The patch joins prefix and name.
#       simple-patch, checksum-transcriber  live-bootstrap's own C, from
#           steps/simple-patch-1.0/src and steps/checksum-transcriber-1.0/src
#           of the pinned live-bootstrap archive, unchanged
#   build-out/tinycc/lb/   live-bootstrap's tree, unpacked by the patched
#       ungz and untar, which build-first-tcc-i386.sh and the checks read
#
# The order: the seed-built sha256sum checks the archives against
# tinycc/SOURCES; stock ungz and untar unpack live-bootstrap's archive
# into build-out/tinycc/lb-boot/; simple-patch is built from there (its
# path fits the name field); it patches copies of ungz.c and untar.c; the
# patched ungz and untar unpack the archive again.
#
# With SEED_TRACE=DIR in the environment every seed run is made under
# strace and leaves DIR/NAME.strace, NAME being the program's path under
# build-out/tinycc with - for / (tests/tinycc/i386-seed-check.sh).
#
# Host programs here: bash runs this script; rm -rf and mkdir -p clear and
# make build-out directories; sha256sum, sed and cut compare the programs
# with tests/pins/tinycc.sha256 at the end.  None of them reads or writes
# a source file.
set -euo pipefail
cd "$(dirname "$0")/.."

IN=build-out/tinycc-inputs
OUT=build-out/tinycc
BIN=$OUT/bin-i386
BOOT=$OUT/bin-boot-i386
TS=$OUT/tools-src
X=vendor/stage0-posix/mescc-tools-extra
K=vendor/mescc-tools/Kaem
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9
SEED=${SEED_I386:-./seed-forth-i386}

fail() { echo "build-tools-i386: $*" >&2; exit 1; }

[ -f "$X/untar.c" ] || fail "$X missing; git submodule update --init --recursive vendor/stage0-posix"
[ -n "${SEED_I386:-}" ] || seed/i386/build.sh > /dev/null

rm -rf "$BIN" "$BOOT" "$OUT/kaem-i386" "$OUT/lb-boot" "$OUT/lb" "$TS"
mkdir -p "$BIN" "$BOOT" "$OUT/lb-boot" "$OUT/lb" "$TS"

# compile OUT SOURCE...: one seed run.  Anything it prints is a failure:
# the Forth outer interpreter reports an unknown word on stdout and goes
# on, and the compiler reports an error on stderr.
compile() {
    local out=$1 rc=0 name=${1#"$OUT/"}
    shift
    ${SEED_TRACE:+strace -o "$SEED_TRACE/${name//\//-}.strace"} \
        "$SEED" forth/i386/010-lib.fth tinycc/i386-seed/tool.fth "$out" "$@" \
        > "$OUT/tool-i386.log" 2>&1 || rc=$?
    if [ "$rc" != 0 ] || [ -s "$OUT/tool-i386.log" ] || [ ! -s "$out" ]; then
        head -c 2000 "$OUT/tool-i386.log" >&2
        fail "$SEED exited $rc building $out (cc/ error codes are the exit status)"
    fi
}

compile "$OUT/kaem-i386" tinycc/m2libc-kaem-i386.c "$K/variable.c" "$K/kaem_globals.c" "$K/kaem.c"

# stage0-posix's tools as published; ungz and untar only to bootstrap
for t in catm sha256sum mkdir cp chmod rm match; do
    compile "$BIN/$t" "$X/$t.c"
done
for t in ungz untar; do
    compile "$BOOT/$t" "$X/$t.c"
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
(cd "$OUT/lb-boot" && ../bin-boot-i386/untar --non-strict --file ../lb.tar > /dev/null 2>&1) \
    || fail "stock untar failed on $LB.tar"
compile "$BIN/simple-patch" "$OUT/lb-boot/$LB/steps/simple-patch-1.0/src/simple-patch.c"

# ungz and untar with our patches, and live-bootstrap's tree again
for p in ungz:ungz-unsigned-bytes untar:untar-ustar-prefix; do
    t=${p%%:*}
    "$BIN/catm" "$TS/$t.c" "$X/$t.c"
    "$BIN/simple-patch" "$TS/$t.c" "tinycc/tools/${p#*:}.before" "tinycc/tools/${p#*:}.after" \
        || fail "tinycc/tools/${p#*:}.before is not in $X/$t.c"
    compile "$BIN/$t" "$TS/$t.c"
done
"$BIN/ungz" --file "$IN/$LB.tar.gz" --output "$OUT/lb.tar" 2> /dev/null \
    || fail "ungz failed on $LB.tar.gz"
(cd "$OUT/lb" && ../bin-i386/untar --non-strict --file ../lb.tar > /dev/null 2>&1) \
    || fail "untar failed on $LB.tar"
"$BIN/rm" "$OUT/lb.tar"

compile "$BIN/checksum-transcriber" "$OUT/lb/$LB/steps/checksum-transcriber-1.0/src/checksum-transcriber.c"

# The pins
bad=0
for f in "$BOOT"/* "$BIN"/* "$OUT/kaem-i386"; do
    name=tinycc/${f#"$OUT/"}
    want=$(sed -n "s|^\([0-9a-f]\{64\}\)  $name\$|\1|p" tests/pins/tinycc.sha256)
    got=$(sha256sum "$f" | cut -d' ' -f1)
    if [ "$got" != "$want" ]; then
        echo "build-tools-i386: $f is $got, tests/pins/tinycc.sha256 says ${want:-nothing}" >&2
        bad=$((bad + 1))
    fi
done
[ "$bad" = 0 ] || fail "$bad program(s) differ from tests/pins/tinycc.sha256"
echo "build-tools-i386: build-out/tinycc/bin-boot-i386, bin-i386 and kaem-i386 as pinned in tests/pins/tinycc.sha256"
