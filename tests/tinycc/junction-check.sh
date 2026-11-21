#!/usr/bin/env bash
# tests/tinycc/junction-check.sh -- the TinyCC junction with live-bootstrap.
#
#     tests/tinycc/junction-check.sh            the Forth-built first tcc
#     tests/tinycc/junction-check.sh FIRST_TCC  any other first compiler
#     tests/tinycc/junction-check.sh --probe    exit 0 when this can run here
#
# What it proves.  A first compiler built by seed Forth alone
# (tinycc/build-first-tcc.sh; no MesCC, Mes, M2-Planet or host compiler
# involved) takes the place of live-bootstrap's MesCC-built tcc-mes, and
# live-bootstrap's own steps/tcc-0.9.26/pass1.kaem, run from there with its
# commands, flags, -g, working directories and absolute paths, and with
# mes-0.28's libc source, ends at the files live-bootstrap publishes in
# steps/tcc-0.9.26/tcc-0.9.26.x86.checksums: /usr/bin/tcc b9dce87d...,
# libc.a, libgetopt.a, crt1.o, crti.o, crtn.o and libtcc1.a.  That is a
# diverse double-compile: two unrelated first compilers (MesCC and the
# Forth compiler) reach the same bytes through the same script, so the
# published tcc does not depend on which of them was trusted.
#
# What it does not prove.  The i386 stages (tcc-boot0 onward) run on the
# host's Linux kernel through its 32-bit (IA32) support, not under K0/K1,
# and the host's bash stands in for kaem.  The other programs the kaem text
# calls (stage0's catm, chmod, cp, match, mkdir, rm, sha256sum, ungz,
# untar; live-bootstrap's checksum-transcriber and simple-patch) are built
# from their C by seed-cc (tinycc/build-tools.sh), and the kaem text's PATH
# holds nothing from the host.  tcc-mes and
# tcc-boot0 are MesCC's own output and are not expected to match; they are
# checked against this route's pins in tests/pins/tinycc.sha256 instead.
#
# How.  The chroot is a bwrap root, build-out/tinycc/junction-root, laid out
# as live-bootstrap's / is before steps/mes-0.28; tinycc/lb-replay.sh runs
# in it and says exactly which kaem lines it runs.  The root is filled by
# the seed-built tools: live-bootstrap's tree is the one build-tools.sh
# unpacked (build-out/tinycc/lb/), bind-mounted; the two distfiles are
# bind-mounted read only.  Needs bwrap, a kernel that runs i386 ELF
# executables, bash, grep, awk, sed and cat in the host's /usr/bin (for
# lb-replay.sh's own text handling), the vendor/stage0-posix submodule
# (with its own submodules) and all four archives of tinycc/SOURCES, also
# with FIRST_TCC (python3 tools/fetch-archives.py
# build-out/tinycc-inputs/...).  Under
# half a minute.
set -euo pipefail
cd "$(dirname "$0")/../.."

IN=build-out/tinycc-inputs
OUT=build-out/tinycc
R=$OUT/junction-root
LB=live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9

# --probe: bwrap works, and the kernel runs a 96-byte i386 ELF that
# exits 42 through int 0x80.
probe() {
    command -v bwrap > /dev/null || { echo "missing: bwrap"; return 1; }
    # the chroot runs these from the host's /usr, mounted at /host/usr
    for t in bash grep awk sed cat; do
        [ -x /usr/bin/$t ] || { echo "missing: /usr/bin/$t"; return 1; }
    done
    bwrap --ro-bind / / --dev /dev true 2> /dev/null || { echo "bwrap cannot create a sandbox here"; return 1; }
    local d rc=0
    d=$(mktemp -d)
    # ELF32 header and one PT_LOAD at 0x08048000; code at 0x08048054:
    # mov eax,1; mov ebx,42; int 0x80
    printf '\177ELF\1\1\1\0\0\0\0\0\0\0\0\0\2\0\3\0\1\0\0\0\124\200\4\10\64\0\0\0\0\0\0\0\0\0\0\0\64\0\40\0\1\0\0\0\0\0\0\0\1\0\0\0\0\0\0\0\0\200\4\10\0\200\4\10\140\0\0\0\140\0\0\0\5\0\0\0\0\20\0\0\270\1\0\0\0\273\52\0\0\0\315\200' > "$d/exit42"
    chmod 755 "$d/exit42"
    "$d/exit42" 2> /dev/null || rc=$?
    rm -rf "$d"
    [ "$rc" = 42 ] || { echo "the kernel does not run i386 executables (IA32 emulation off?)"; return 1; }
}
if [ "${1:-}" = --probe ]; then
    probe
    exit
fi
why=$(probe) || { echo "junction-check: cannot run: $why" >&2; exit 1; }

fail() { echo "junction-check: FAIL: $*" >&2; exit 1; }

# The first compiler, and the tools (build-first-tcc.sh builds them too)
if [ $# -ge 1 ]; then
    FIRST=$1
    own=0
    tinycc/build-tools.sh
else
    tinycc/build-first-tcc.sh
    FIRST=$OUT/tcc-first
    own=1
fi
[ -x "$FIRST" ] || fail "$FIRST is not an executable"

# The root: what seed.kaem makes; live-bootstrap's tree and the distfiles
# are mounted.  build-tools.sh checked the archives against tinycc/SOURCES
# and unpacked live-bootstrap's into $OUT/lb.  The steps directory is
# mounted read-write and pass1.kaem builds in it, so build-tools.sh
# unpacked a fresh copy.
BIN=$OUT/bin
rm -rf "$R"
"$BIN/mkdir" -p "$R"/usr/bin "$R"/usr/lib/mes "$R"/usr/include/mes "$R"/tmp \
    "$R"/dev "$R"/external/distfiles

# The host's dynamic loader at the path its programs name
interp=/lib64/ld-linux-x86-64.so.2
[ -e "$interp" ] || fail "no $interp for the host tools"
libpath=/host/usr/lib
for d in /usr/lib64 /usr/lib/x86_64-linux-gnu; do
    [ -d "$d" ] && libpath=$libpath:/host$d
done

echo "junction-check: first compiler $FIRST"
sha256sum "$FIRST"
rc=0
bwrap --bind "$R" / \
    --bind "$OUT/lb/$LB/steps" /steps \
    --ro-bind "$OUT/lb/$LB/seed" /seed \
    --ro-bind "$IN/tcc-0.9.26.tar.gz" /external/distfiles/tcc-0.9.26.tar.gz \
    --ro-bind "$IN/mes-0.28.tar.gz" /external/distfiles/mes-0.28.tar.gz \
    --ro-bind "$BIN" /forth-bootstrap/bin \
    --ro-bind /usr /host/usr \
    --ro-bind "$(realpath "$interp")" "$interp" \
    --ro-bind tinycc /forth-bootstrap/tinycc \
    --ro-bind "$FIRST" /forth-bootstrap/tcc-first \
    --dev /dev --proc /proc \
    --clearenv --setenv LD_LIBRARY_PATH "$libpath" \
    --chdir / \
    /host/usr/bin/bash /forth-bootstrap/tinycc/lb-replay.sh > "$OUT/junction.log" 2>&1 || rc=$?
grep -E '^(==== |tcc version)' "$OUT/junction.log" | grep -v ': running in' || true
[ "$rc" = 0 ] || { tail -30 "$OUT/junction.log" >&2; fail "lb-replay.sh exited $rc (log: $OUT/junction.log)"; }

# Compare.  live-bootstrap's checksums file names absolute paths in its /.
echo "junction-check: against live-bootstrap's steps/tcc-0.9.26/tcc-0.9.26.x86.checksums"
bad=0
while read -r want path; do
    got=$(sha256sum "$R$path" | cut -d' ' -f1)
    case $path in
        /usr/bin/tcc-mes|/usr/bin/tcc-boot0)
            # MesCC's output in live-bootstrap; this route's own pins instead
            pin=$(sed -n "s|^\([0-9a-f]\{64\}\)  tinycc/junction$path\$|\1|p" tests/pins/tinycc.sha256)
            if [ "$path" = /usr/bin/tcc-mes ] && [ "$own" = 1 ]; then
                pin=$(sed -n 's|^\([0-9a-f]\{64\}\)  tinycc/tcc-first$|\1|p' tests/pins/tinycc.sha256)
            fi
            if [ "$own" = 0 ]; then
                echo "  ---   $got  $path (MesCC's in live-bootstrap; another first compiler, not compared)"
            elif [ "$got" = "$pin" ]; then
                echo "  pin   $got  $path (MesCC's is ${want:0:8}...; equals tests/pins/tinycc.sha256)"
            else
                echo "  FAIL  $got  $path (tests/pins/tinycc.sha256 says ${pin:-nothing})"
                bad=$((bad + 1))
            fi ;;
        *)
            if [ "$got" = "$want" ]; then
                echo "  same  $got  $path"
            else
                echo "  FAIL  $got  $path (live-bootstrap publishes $want)"
                bad=$((bad + 1))
            fi ;;
    esac
done < "$OUT/lb/$LB/steps/tcc-0.9.26/tcc-0.9.26.x86.checksums"
[ "$bad" = 0 ] || fail "$bad file(s) differ (log: $OUT/junction.log)"
echo "junction-check: OK, live-bootstrap's published tcc-0.9.26 reached from $FIRST"
