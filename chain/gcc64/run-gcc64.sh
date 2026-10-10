#!/usr/bin/env bash
# chain/gcc64/run-gcc64.sh -- the climb from the direct route's GCC 4.0.4 to GCC 10.5.0,
# by way of musl:
#
#   bridge    the direct route's GCC 4.0.4 (chain/gcc-direct/stage-d.sh, built from the Forth
#             compiler) builds binutils-2.30 and gcc-4.0.4 "gcc-A"
#   stage 6   gcc-A builds gcc-B, gcc-B builds gcc-C; B = C
#   stage 7   gcc-B rebuilds musl (the sysroot), gmp, mpfr, mpc (+ make check)
#   stage 8   gcc-4.7.4 (C, C++) by gcc-B
#   stage 9   binutils-2.41 by gcc-4.7.4
#   stage 10  gcc-10.5.0 (C, C++) by gcc-4.7.4
#   then      pins     : every artifact in chain/gcc64/HASHES is compared (see below)
#
# The bridge builds gcc-A from the stage-D GCC; the stage numbers 6-10 that
# follow are kept from the ladder these scripts were first written for.
#
# Layout: this script and its helpers (build-gcc4.sh, build-gcc47.sh, build-gcc10.sh)
# live in chain/gcc64/; patches in chain/patches/gcc64/; test programs in tests/gcc64/;
# sources are listed with their sha256 in chain/gcc64/SOURCES and fetched into a cache.
# Everything built goes into BUILDROOT; nothing is written into the tree outside it.
#
# Host tools (build glue only; never a compiler/assembler/linker): the HOSTTOOLS list
# below, symlinked into $W/hostbin.  PATH is exactly $W/guard:$W/hostbin (plus a
# stage's own chain-built bin dirs), so /usr/bin is not searched at all.  $W/guard
# shadows gcc/cc/ld/as/ar/... with scripts that fail loudly and log to
# $W/guard/hits.log (cwd in where.log).  Absolute host paths still reachable: /bin/sh
# (#! lines, system()) and /usr/bin/env.  Under K1 (chain/ladder/stage11.sh) every one of
# these tools is one the chain built.
#
# As root (real, or mapped root in a user namespace), the script re-execs itself in
# a private mount namespace in which /dev/null is bind-mounted onto itself, so no
# tool can unlink or replace the host's /dev/null (unlink gets EBUSY), and a refusing
# script is bind-mounted over every host compiler, assembler and linker reachable by
# absolute path (/lib/cpp, /usr/bin/gcc*, ...).  GCC64_TRACE=FILE additionally runs
# everything under strace -f (execve and unlink only) to list every program executed.
#
# Usage: chain/gcc64/run-gcc64.sh [stage ...]           all stages, or the ones named, in
#                                                 BUILDROOT (each stage wipes and
#                                                 rebuilds only its own outputs, so a
#                                                 later stage can be re-run in place)
#        chain/gcc64/run-gcc64.sh --new DIR [stage ...] the same, in DIR, which must not exist
#        chain/gcc64/run-gcc64.sh --fetch               fill the source cache and exit
#
# Env:   BUILDROOT     build directory (default build-out/gcc64; created if missing,
#                      never wiped as a whole).  Absolute paths under it are baked
#                      into the binaries, so artifact hashes depend on it; see HASHES.
#        GCC64_CACHE   source cache (default build-out/gcc64-cache).  Every file is
#                      checked against chain/gcc64/SOURCES before use; with all of them
#                      cached, no network is needed.
#        GCC64_DIRECT, GCC64_OYACC, GCC64_FLEX  required by the bridge: a finished
#                      chain/gcc-direct/stage-d.sh WORK and the Forth-built oyacc and flex
#                      2.5.11.
#        GCC64_REPIN=1 print the pins step's hashes instead of failing on them.
#        JOBS          make -j (default 4).
#
# Exit:  0 pass, 1 fail, 77 skip (a source is neither cached nor fetchable).
set -euo pipefail
GCC64=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$GCC64/../.." && pwd)
me=run-gcc64
SELF=$GCC64/run-gcc64.sh

if [ "${1:-}" = --new ]; then
    [ -n "${2:-}" ] || { echo "$me: --new needs a directory" >&2; exit 1; }
    [ ! -e "$2" ] || { echo "$me: $2 exists; --new wants a fresh directory" >&2; exit 1; }
    mkdir -p "$2"; BUILDROOT=$2; shift 2
fi
BUILDROOT=${BUILDROOT:-$ROOT/build-out/gcc64}
mkdir -p "$BUILDROOT"
W=$(cd "$BUILDROOT" && pwd)
GCC64_CACHE=${GCC64_CACHE:-$ROOT/build-out/gcc64-cache}
mkdir -p "$GCC64_CACHE"
GCC64_CACHE=$(cd "$GCC64_CACHE" && pwd)
export BUILDROOT=$W GCC64_CACHE

if [ "$(id -u)" = 0 ] && [ -z "${GCC64_NS:-}" ] && [ "${1:-}" != --fetch ] && command -v unshare > /dev/null; then
    export GCC64_NS=1 GCC64_W=$W
    # _abs: bind-mounted (inside the namespace only) over every host compiler, assembler
    # and linker reachable by absolute path, e.g. autoconf's /lib/cpp fallback and
    # /usr/libexec/gcc/*/cc1plus behind it; the gcc/llvm libexec trees get an empty tmpfs.
    mkdir -p "$W/guard"
    printf '#!/bin/sh\necho "GUARD: host $0 invoked: $*" >&2\necho "GUARD $0 $*" >> %s/guard/hits.log\necho "GUARD $0 $* [cwd $PWD]" >> %s/guard/where.log\nexit 99\n' \
        "$W" "$W" > "$W/guard/_abs"
    chmod +x "$W/guard/_abs"
    exec unshare -m --propagation private /bin/sh -c '
        mount --bind /dev/null /dev/null || exit 1
        for f in /lib/cpp /usr/bin/cpp* /usr/bin/gcc* /usr/bin/g++* /usr/bin/cc /usr/bin/c++ /usr/bin/c89* \
                 /usr/bin/c99* /usr/bin/x86_64-linux-gnu-* /usr/bin/as /usr/bin/ld /usr/bin/ld.bfd /usr/bin/ld.gold /usr/bin/ld.lld* /usr/bin/ld64* \
                 /usr/bin/clang* /usr/bin/lto-dump* /usr/bin/tcc /usr/local/bin/gcc /usr/local/bin/cc; do
            [ -e "$f" ] || continue
            mount --bind "$GCC64_W/guard/_abs" "$f" || exit 1
        done
        for d in /usr/libexec/gcc /usr/lib/gcc /usr/lib/llvm-*; do
            [ -d "$d" ] && { mount -t tmpfs -o ro,size=64k none "$d" || exit 1; }
        done
        if [ -n "${GCC64_TRACE:-}" ]; then
            exec strace -f --seccomp-bpf -qq -e trace=execve,unlink,unlinkat -e signal=none \
                 -s 200 -o "$GCC64_TRACE" "$@"
        fi
        exec "$@"' sh "$SELF" "$@"
fi
unset GCC64_W
D=$GCC64_CACHE
PATCHES=$ROOT/chain/patches/gcc64
TESTS=$ROOT/tests/gcc64
LOG=$W/logs; mkdir -p "$LOG"
JOBS=${JOBS:-4}
export GCC64_W=$W GCC64_PATCHES=$PATCHES JOBS
HOSTPATH=$PATH
# every host program the build may find on PATH (none is a compiler, assembler or linker)
HOSTTOOLS="bash sh make sed grep egrep fgrep awk mawk tr cut sort uniq comm join paste cat tac head tail
  wc cp mv rm rmdir mkdir ln ls touch chmod install readlink realpath basename dirname pwd
  tar gzip gunzip zcat xz unxz bzip2 patch diff cmp sha256sum md5sum cksum find xargs expr env
  uname date sleep test [ true false printf echo tee mktemp od dd du stat id hostname nproc
  getconf timeout nice seq split tsort fold nl sync which bison m4 python3
  git bc unshare mount"   # source fetching and namespace isolation
mkhostbin() {
    local t p; rm -rf "$W/hostbin"; mkdir -p "$W/hostbin"
    for t in $HOSTTOOLS; do
        p=$(PATH=$HOSTPATH type -P "$t") || { echo "$me: host tool $t not found (skipped)" >&2; continue; }
        case $p in /*) ln -s "$p" "$W/hostbin/$t" ;; esac
    done
}
export LC_ALL=C
T0=$(date +%s)
say() { echo "[$me +$(( $(date +%s) - T0 ))s] $*"; }
sha() { sha256sum "$1" | cut -c1-64; }
fail() { echo "$me: FAIL: $*" >&2; exit 1; }
skip() { echo "$me: SKIP: $*"; exit 77; }
# timing: t_start NAME / t_end NAME
declare -A TS
t_start() { TS[$1]=$(date +%s); }
t_end() { local n=$(( $(date +%s) - ${TS[$1]} )); say "$1 done in ${n}s"; echo "$1 ${n}s" >> "$LOG/timings.txt"; }

# --- guard: no host compiler, assembler or linker may run -------------------
mkguard() {
    mkdir -p "$W/guard"
    for t in gcc cc c89 c99 ld as ar ranlib cpp g++ c++ gcc-ar gcc-nm gcc-ranlib nm strip objcopy \
             objdump readelf size strings addr2line c++filt gprof ld.bfd ld.gold gold \
             tcc clang x86_64-linux-gnu-gcc x86_64-linux-gnu-ld x86_64-linux-gnu-as; do
        printf '#!/bin/sh\necho "GUARD: host %s invoked: $*" >&2\necho "GUARD %s $*" >> %s/guard/hits.log\necho "GUARD %s $* [cwd $PWD]" >> %s/guard/where.log\nexit 99\n' \
            "$t" "$t" "$W" "$t" "$W" > "$W/guard/$t"
        chmod +x "$W/guard/$t"
    done
    rm -f "$W/guard/hits.log" "$W/guard/where.log"
}
# configure scripts probe for gcc/cc/ld/nm... by name; those probes hit the guard and
# fail, which is fine.  What must never happen is a guard hit outside configure.
checkguard_probes() {
    [ -s "$W/guard/hits.log" ] || return 0
    say "guard: $(wc -l < "$W/guard/hits.log") configure-time probes of host tools (all refused): $(cut -d' ' -f2 "$W/guard/hits.log" | sort | uniq -c | tr '\n' ' ')"
    grep -v -E ' (conftest|-v$|-V$|--version|-qversion|-B |-p conftest|--help|/dev/null)' "$W/guard/hits.log" \
        && fail "a host tool was invoked outside a configure probe" || true
    cat "$W/guard/where.log" >> "$LOG/guard-probes.log"; rm -f "$W/guard/hits.log" "$W/guard/where.log"
}

# --- sources: chain/gcc64/SOURCES, fetched into $GCC64_CACHE, sha256-checked before use ----
declare -A SRC_SHA SRC_URLS
while read -r name hash urls; do
    case $name in ''|'#'*) continue ;; esac
    SRC_SHA[$name]=$hash; SRC_URLS[$name]=$urls
done < "$GCC64/SOURCES"
# fetch_one NAME URL: put NAME into the cache from URL (see SOURCES for the forms)
fetch_one() {
    local f=$1 u=$2 tmp=$D/.fetch.$$ repo ref commit prefix
    rm -rf "$tmp"; mkdir -p "$tmp"
    case $u in
        git+*)
            u=${u#git+}; prefix=${u##*:}; u=${u%:*}; commit=${u##*@}; u=${u%@*}; ref=${u##*#}; repo=${u%#*}
            PATH=$HOSTPATH git -c advice.detachedHead=false clone -q --depth 1 --branch "$ref" "$repo" "$tmp/git" || return 1
            [ "$(PATH=$HOSTPATH git -C "$tmp/git" rev-parse HEAD)" = "$commit" ] \
                || { echo "$me: $repo $ref is not $commit" >&2; return 1; }
            PATH=$HOSTPATH git -C "$tmp/git" archive --format=tar --prefix="$prefix/" HEAD > "$tmp/out" || return 1 ;;
        *!*)
            PATH=$HOSTPATH curl -fsSL --connect-timeout 20 --max-time 3600 -o "$tmp/outer" "${u%%!*}" || return 1
            tar -xf "$tmp/outer" -O "${u#*!}" > "$tmp/out" || return 1 ;;
        *)
            PATH=$HOSTPATH curl -fsSL --connect-timeout 20 --max-time 3600 -o "$tmp/out" "$u" || return 1 ;;
    esac
    mv "$tmp/out" "$D/$f"; rm -rf "$tmp"
}
# need NAME: make sure the cache holds NAME with the pinned sha256; else fetch it
need() {
    local f=$1 u got
    [ -n "${SRC_SHA[$f]:-}" ] || fail "$f is not listed in chain/gcc64/SOURCES"
    if [ -f "$D/$f" ]; then
        got=$(sha "$D/$f")
        [ "$got" = "${SRC_SHA[$f]}" ] || fail "$D/$f has sha256 $got, not the pinned ${SRC_SHA[$f]}; delete it to refetch"
        return 0
    fi
    for u in ${SRC_URLS[$f]}; do
        say "fetching $f from $u"
        if fetch_one "$f" "$u"; then
            got=$(sha "$D/$f")
            [ "$got" = "${SRC_SHA[$f]}" ] && return 0
            echo "$me: $u gave sha256 $got, not the pinned ${SRC_SHA[$f]}; discarded" >&2
            rm -f "$D/$f"
        fi
        rm -rf "$D/.fetch.$$"
    done
    skip "$f is not in $D and none of its URLs gave the pinned bytes"
}
if [ "${1:-}" = --fetch ]; then
    for f in "${!SRC_SHA[@]}"; do need "$f"; done
    say "all $(echo "${!SRC_SHA[@]}" | wc -w) sources in $D, sha256 as pinned"; exit 0
fi


# binutils-2.30's configuration for the bridge: the top-level configure with the
# tarball's pregenerated files (configure scripts, bison/flex outputs, opcodes tables)
BU230_CONF=(--build=x86_64-unknown-linux-gnu --host=x86_64-unknown-linux-gnu
    --target=x86_64-unknown-linux-gnu --prefix="$W/bu" --with-sysroot= --disable-nls
    --disable-shared --enable-static --disable-gold --disable-plugins --disable-werror
    --enable-deterministic-archives --enable-64-bit-bfd --disable-gdb --disable-sim
    --disable-readline --disable-libdecnumber)

# --- bridge: the direct route's GCC 4.0.4 builds binutils-2.30 and gcc-A ----------------
# GCC64_DIRECT names a finished chain/gcc-direct/stage-d.sh WORK: GCC 4.0.4 whose first
# generation was compiled by the Forth compiler, at its stage 2 = 3 = 4 fixed point,
# with the stage-C musl sysroot and Forth-built binutils-2.30 it was configured with.
# GCC64_OYACC and GCC64_FLEX name the Forth-built oyacc and flex 2.5.11
# (chain/plumbing/lexers.kaem).  The bridge leaves stage 6 this layout:
#   bu/       binutils-2.30, configured with BU230_CONF, built by the direct GCC
#   tools/    oyacc and flex 2.5.11, copied (no host bison or flex anywhere)
#   sysroot/  the direct route's musl (stage C), copied; stage 7 rebuilds it anyway
#   g4/       gcc-4.0.4 "gcc-A" by build-gcc4.sh, built by the direct GCC
# bridge/inputs.txt records the inputs and their sha256.
bridge_env() {  # gcc-4.0.4 builds (bridge, stage 6): the Forth-built parser generators
    export GCC4_YACC=$W/tools/bin/oyacc GCC4_LEX=$W/tools/bin/flex GCC4_BYACC=1
}
bridge() {
    t_start bridge
    local DW=${GCC64_DIRECT:?bridge needs GCC64_DIRECT=a finished chain/gcc-direct/stage-d.sh WORK}
    local Y=${GCC64_OYACC:?bridge needs GCC64_OYACC=the Forth-built oyacc}
    local X=${GCC64_FLEX:?bridge needs GCC64_FLEX=the Forth-built flex 2.5.11}
    local DT0=x86_64-pc-linux-gnu f h got
    DW=$(cd "$DW" && pwd)
    local G=$DW/prefix/bin/gcc
    # stage-d.sh writes report.txt, which must record the fixed point
    local R=$DW/report.json
    if [ -f "$R" ]; then grep -q '"fixed_point": true' "$R" || fail "$R: no stage-D fixed point"
    else R=$DW/report.txt; [ "$(head -n 1 "$R" 2>/dev/null)" = "# Stage D: fixed point reached" ] \
        || fail "$DW: no stage-D report with a fixed point"; fi
    [ -x "$G" ] || fail "$G: no stage-D gcc"
    # stage C: where the direct GCC's own (absolute, configured) as and sysroot are
    local DTC SC; DTC=$(dirname "$("$G" -print-prog-name=as)"); SC=$(dirname "$DTC")
    [ "$("$G" -print-file-name=libc.a)" = "$SC/sysroot/usr/lib/libc.a" ] && [ -x "$DTC/as" ] && [ -x "$DTC/ld" ] \
        || fail "stage C $SC: the direct gcc's toolchain or sysroot is missing"
    # stage 2 (prefix/) must be the fixed point stage-D's report recorded for stage 4
    for f in bin/gcc libexec/gcc/$DT0/4.0.4/cc1 libexec/gcc/$DT0/4.0.4/collect2; do
        h=$(sed -n -e "s|^ *\"$f\": \"\([0-9a-f]*\)\".*|\1|p" -e "s|^- $f: \([0-9a-f]*\)$|\1|p" "$R")
        got=$(sha "$DW/prefix/$f")
        [ -n "$h" ] && [ "$got" = "$h" ] || fail "direct $f is $got, not stage-D's fixed point ${h:-(unrecorded)}"
    done
    [ "$("$G" -dumpversion)" = 4.0.4 ] || fail "$G is not gcc-4.0.4"
    rm -rf "$W/bridge" "$W/bu" "$W/tools" "$W/sysroot" "$W/g4"; mkdir -p "$W/bridge" "$W/tools/bin" "$W/src"
    {
        echo "# bridge inputs: the direct route (gcc-direct stage D), $(date -u +%FT%TZ)"
        echo "stage_d $DW"; echo "stage_c $SC"
        for f in "$G" "$DW/prefix/libexec/gcc/$DT0/4.0.4/cc1" "$DTC/as" "$DTC/ld" "$DTC/ar" "$Y" "$X"; do
            echo "sha256 $(sha "$f") $f"
        done
    } > "$W/bridge/inputs.txt"
    cp "$Y" "$W/tools/bin/oyacc"; cp "$X" "$W/tools/bin/flex"
    say "direct gcc-4.0.4 (stage-D fixed point) cc1: $(sha "$DW/prefix/libexec/gcc/$DT0/4.0.4/cc1")"
    say "oyacc: $(sha "$W/tools/bin/oyacc")  flex-2.5.11: $(sha "$W/tools/bin/flex")"
    # binutils-2.30 into bu/, compiled by the direct GCC (which
    # assembles and links with the Forth-built binutils it was configured with)
    need binutils-2.30.tar.xz
    local s=$W/src/binutils-2.30 b=$W/src/bu-build
    rm -rf "$s" "$b"; tar -xJf "$D/binutils-2.30.tar.xz" -C "$W/src"; mkdir -p "$b"
    (
        cd "$b"
        export CXXCPP="$G -E -xc"
        PATH=$DTC:$PATH ../binutils-2.30/configure "${BU230_CONF[@]}" CC="$G" CPP="$G -E" CXX=false \
            CC_FOR_BUILD="$G" CPP_FOR_BUILD="$G -E" CXX_FOR_BUILD=false AR="$DTC/ar" RANLIB="$DTC/ranlib" \
            NM="$DTC/nm" CFLAGS=-g0
        PATH=$DTC:$PATH make -j"$JOBS" MAKEINFO=true
        PATH=$DTC:$PATH make install MAKEINFO=true
    ) > "$LOG/binutils.log" 2>&1 || fail "binutils by the direct gcc (see $LOG/binutils.log)"
    rm -rf "$s" "$b"
    for f in as ld ar nm objcopy objdump strip ranlib; do
        [ -x "$W/bu/bin/$f" ] || fail "binutils: no bu/bin/$f"
    done
    say "binutils-2.30 by the direct gcc: as $(sha "$W/bu/bin/as")  ld $(sha "$W/bu/bin/ld")"
    # sysroot: the direct route's musl-1.1.24, as stage C installed it
    cp -a "$SC/sysroot" "$W/sysroot"
    say "sysroot: direct musl libc.a $(sha "$W/sysroot/usr/lib/libc.a")"
    # gcc-A: build-gcc4.sh with the direct GCC as CC
    bridge_env
    need gcc-4.0.4-git-944765863e.tar
    PATH=$W/bu/bin:$PATH "$GCC64/build-gcc4.sh" "$G" "$W/g4" A > "$LOG/gcc4-A.log" 2>&1 \
        || fail "gcc-4.0.4 by the direct gcc (see $LOG/gcc4-A.log)"
    local T=x86_64-unknown-linux-gnu
    say "gcc-A (gcc-4.0.4 built by the direct gcc) cc1: $(sha "$W/g4/libexec/gcc/$T/4.0.4/cc1")"
    PATH=$W/bu/bin:$PATH "$W/g4/bin/gcc" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-A" -lm
    "$W/src/lt-A" > "$LOG/libc-test-gccA.log" || fail "libc-test under gcc-A"
    say "gcc-A -O2 libc-test: $(tail -1 "$LOG/libc-test-gccA.log")"
    checkguard_probes; t_end bridge
}

# --- stage 6: gcc-4.0.4 builds itself twice; B = C ---------------------------------------
stage6() {
    t_start stage6
    local T=x86_64-unknown-linux-gnu f
    need gcc-4.0.4-git-944765863e.tar
    rm -rf "$W/g4s" "$W/destC"; bridge_env
    PATH=$W/bu/bin:$PATH "$GCC64/build-gcc4.sh" "$W/g4/bin/gcc" "$W/g4s" B > "$LOG/gcc4-B.log" 2>&1 \
        || fail "gcc-B (see $LOG/gcc4-B.log)"
    PATH=$W/bu/bin:$PATH "$GCC64/build-gcc4.sh" "$W/g4s/bin/gcc" "$W/g4s" C "$W/destC" > "$LOG/gcc4-C.log" 2>&1 \
        || fail "gcc-C (see $LOG/gcc4-C.log)"
    for f in bin/gcc bin/cpp libexec/gcc/$T/4.0.4/cc1 libexec/gcc/$T/4.0.4/collect2 \
             lib/gcc/$T/4.0.4/libgcc.a lib/gcc/$T/4.0.4/crtbegin.o lib/gcc/$T/4.0.4/crtend.o; do
        cmp -s "$W/g4s/$f" "$W/destC$W/g4s/$f" || fail "gcc-B and gcc-C differ in $f"
        say "gcc-B = gcc-C: $f $(sha "$W/g4s/$f")"
    done
    rm -rf "$W/destC" "$W/src/gcc-4.0.4-work"
    PATH=$W/bu/bin:$PATH "$W/g4s/bin/gcc" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-B" -lm
    "$W/src/lt-B" > "$LOG/libc-test-gccB.log" || fail "libc-test under gcc-B"
    say "gcc-B -O2 libc-test: $(tail -1 "$LOG/libc-test-gccB.log")"
    checkguard_probes; t_end stage6
}

# --- stage 7: musl rebuilt by gcc-4.0.4 (pristine source + GNU as), gmp/mpfr/mpc ---------
GB=$W/bu/bin
gnu_env() {  # gnu_env CC -- sets GNUENV: autoconf variables for a gcc + binutils-2.30 build
    GNUENV=(CC="$1" CPP="$1 -E" AR=$GB/ar NM=$GB/nm RANLIB=$GB/ranlib AS=$GB/as LD=$GB/ld
            OBJDUMP=$GB/objdump STRIP=$GB/strip OBJCOPY=$GB/objcopy)
}
stage7() {
    t_start stage7
    local C=$W/g4s/bin/gcc U=$W/sysroot/usr T=x86_64-unknown-linux-gnu s
    need musl-1.1.24.tar.gz
    s=$W/src/musl-gcc; rm -rf "$s" "$s.tmp"; mkdir "$s.tmp"
    tar -xzf "$D/musl-1.1.24.tar.gz" -C "$s.tmp"; mv "$s.tmp/musl-1.1.24" "$s"; rmdir "$s.tmp"
    patch -s -p1 -F0 -d "$s" < "$PATCHES/musl-1.1.24/06-lb-madvise_preserve_errno.patch"
    for p in "$PATCHES"/musl-gcc/*.diff; do patch -s -p1 -F0 -d "$s" < "$p"; done
    rm -rf "$W/sysroot"
    ( cd "$s" && PATH=$GB:$PATH CC=$C ./configure --target=x86_64 --host=x86_64 --disable-shared \
          --prefix="$U" --syslibdir="$W/sysroot/lib" \
      && PATH=$GB:$PATH make -j"$JOBS" CROSS_COMPILE= AR=$GB/ar RANLIB=$GB/ranlib \
      && PATH=$GB:$PATH make install CROSS_COMPILE= AR=$GB/ar RANLIB=$GB/ranlib ) > "$LOG/musl-gcc.log" 2>&1 \
        || fail "musl by gcc-4.0.4 (see $LOG/musl-gcc.log)"
    rm -rf "$s"
    say "musl-1.1.24 by gcc-4.0.4: libc.a $(sha "$U/lib/libc.a")"
    PATH=$GB:$PATH "$C" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-m" -lm
    "$W/src/lt-m" > "$LOG/libc-test-muslgcc.log" || fail "libc-test with gcc-built musl"
    local name tarball dir extra; gnu_env "$C"
    for name in gmp mpfr mpc; do
        case $name in
            gmp)  tarball=gmp-6.2.1+dfsg.tar.xz; dir=gmp-6.2.1+dfsg; extra="CC_FOR_BUILD=$C" ;;
            mpfr) tarball=mpfr-4.1.0.tar.xz; dir=mpfr-4.1.0; extra="--with-gmp=$U" ;;
            mpc)  tarball=mpc-1.2.1.tar.gz; dir=mpc-1.2.1; extra="--with-gmp=$U --with-mpfr=$U" ;;
        esac
        need "$tarball"
        rm -rf "$W/src/$dir"; tar -xf "$D/$tarball" -C "$W/src"
        ( cd "$W/src/$dir" && PATH=$GB:$PATH env "${GNUENV[@]}" ./configure --build=$T --host=$T \
              --prefix="$U" --disable-shared --enable-static $extra \
          && PATH=$GB:$PATH make -j"$JOBS" && PATH=$GB:$PATH make install \
          && PATH=$GB:$PATH make -j"$JOBS" check ) > "$LOG/$name.log" 2>&1 || fail "$name (see $LOG/$name.log)"
        say "$name: $(grep -E '^# (PASS|FAIL):' "$LOG/$name.log" | awk '{s[$2]+=$3} END{printf "check PASS %d FAIL %d", s["PASS:"], s["FAIL:"]}')"
        rm -rf "$W/src/$dir"
    done
    checkguard_probes; t_end stage7
}

# --- stage 8: gcc-4.7.4 (C, C++) built by gcc-4.0.4 -----------------------------------------
stage8() {
    t_start stage8
    local T=x86_64-linux-musl
    rm -rf "$W/g47"; need gcc-4.7.4.tar.xz; need binutils-2.41.tar.xz
    PATH=$GB:$PATH "$GCC64/build-gcc47.sh" "$W/g4s/bin/gcc" "$W/g47" > "$LOG/gcc47-A.log" 2>&1 \
        || fail "gcc-4.7.4 (see $LOG/gcc47-A.log)"
    say "gcc-4.7.4 cc1: $(sha "$W/g47/libexec/gcc/$T/4.7.4/cc1")  cc1plus: $(sha "$W/g47/libexec/gcc/$T/4.7.4/cc1plus")"
    PATH=$GB:$PATH "$W/g47/bin/gcc" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-47" -lm
    PATH=$GB:$PATH "$W/g47/bin/g++" -O2 "$TESTS/cxx-test.cc" -o "$W/src/cxx-47"
    "$W/src/lt-47" > "$LOG/libc-test-gcc47.log" && "$W/src/cxx-47" > "$LOG/cxx-test-gcc47.log" \
        || fail "gcc-4.7.4 tests"
    say "gcc-4.7.4: $(tail -1 "$LOG/libc-test-gcc47.log"); $(tail -1 "$LOG/cxx-test-gcc47.log")"
    rm -rf "$W/src/gcc-4.7.4" "$W/src/g47-build"
    checkguard_probes; t_end stage8
}

# --- stage 9: binutils-2.41 built by gcc-4.7.4 -----------------------------------------------
stage9() {
    t_start stage9
    local C=$W/g47/bin/gcc X=$W/g47/bin/g++ b=$W/src/bu2-build; gnu_env "$C"
    need binutils-2.41.tar.xz
    rm -rf "$W/src/binutils-2.41" "$b" "$W/bu2"; tar -xJf "$D/binutils-2.41.tar.xz" -C "$W/src"; mkdir "$b"
    ( cd "$b" && PATH=$GB:$PATH env "${GNUENV[@]}" CXX="$X" CC_FOR_BUILD="$C" CXX_FOR_BUILD="$X" \
          ../binutils-2.41/configure --build=x86_64-linux-musl --host=x86_64-linux-musl \
          --target=x86_64-linux-musl --prefix="$W/bu2" --with-sysroot= --disable-nls --disable-shared \
          --enable-static --disable-gold --disable-gprofng --disable-plugins --disable-werror \
          --enable-deterministic-archives --enable-64-bit-bfd --disable-gdb --disable-gdbserver \
          --disable-sim --disable-readline --disable-libdecnumber --without-zstd --without-debuginfod \
          MAKEINFO=true \
      && PATH=$GB:$PATH make -j"$JOBS" MAKEINFO=true && PATH=$GB:$PATH make install MAKEINFO=true ) \
        > "$LOG/binutils-2.41.log" 2>&1 || fail "binutils-2.41 (see $LOG/binutils-2.41.log)"
    rm -rf "$W/src/binutils-2.41" "$b"
    say "binutils-2.41 as: $(sha "$W/bu2/bin/as")  ld: $(sha "$W/bu2/bin/ld")"
    checkguard_probes; t_end stage9
}

# --- stage 10: gcc-10.5.0 (C, C++) built by gcc-4.7.4 + binutils-2.41 ----------------------------
stage10() {
    t_start stage10
    local T=x86_64-linux-musl
    rm -rf "$W/g10"; need gcc-10.5.0.tar.xz
    PATH=$W/bu2/bin:$PATH "$GCC64/build-gcc10.sh" "$W/g47/bin/gcc" "$W/g47/bin/g++" "$W/g10" > "$LOG/gcc10-A.log" 2>&1 \
        || fail "gcc-10.5.0 (see $LOG/gcc10-A.log)"
    say "gcc-10.5.0 cc1: $(sha "$W/g10/libexec/gcc/$T/10.5.0/cc1")  cc1plus: $(sha "$W/g10/libexec/gcc/$T/10.5.0/cc1plus")"
    PATH=$W/bu2/bin:$PATH "$W/g10/bin/gcc" -O2 "$TESTS/libc-test.c" -o "$W/src/lt-10" -lm
    PATH=$W/bu2/bin:$PATH "$W/g10/bin/g++" -O2 -Wno-deprecated-declarations "$TESTS/cxx-test.cc" -o "$W/src/cxx-10"
    "$W/src/lt-10" > "$LOG/libc-test-gcc10.log" && "$W/src/cxx-10" > "$LOG/cxx-test-gcc10.log" \
        || fail "gcc-10.5.0 tests"
    say "gcc-10.5.0: $(tail -1 "$LOG/libc-test-gcc10.log"); $(tail -1 "$LOG/cxx-test-gcc10.log")"
    rm -rf "$W/src/gcc-10.5.0" "$W/src/g10-build"
    checkguard_probes; t_end stage10
}


# --- pins: sha256 of every stage's key outputs vs chain/gcc64/HASHES ----------------------------
# HASHES lists "SHA256  FILE  SCOPE".  SCOPE "any": the file must have that hash
# whatever BUILDROOT is.  SCOPE "root": the file embeds absolute paths under
# BUILDROOT, so the hash holds only when BUILDROOT is the one on HASHES's "root" line
# (/build-out/g64, chain/ladder/stage11.sh's under K1); elsewhere it is reported, not
# enforced.  Files a partial run did not build are skipped.
hashes() {
    local h f scope root got n_ok=0 n_skip=0 n_bad=0
    : > "$LOG/hashes.txt"
    root=$(sed -n 's/^root //p' "$GCC64/HASHES")
    while read -r h f scope; do
        case $h in ''|'#'*|root) continue ;; esac
        [ -f "$W/$f" ] || continue
        got=$(sha "$W/$f"); echo "$got  $f" >> "$LOG/hashes.txt"
        if [ "$scope" = root ] && [ "$W" != "$root" ]; then
            n_skip=$((n_skip+1))
        elif [ "$got" = "$h" ]; then
            n_ok=$((n_ok+1))
        else
            n_bad=$((n_bad+1)); echo "$me: $f is $got, not the pinned $h ($scope)" >&2
        fi
    done < "$GCC64/HASHES"
    local why=""; [ "$n_skip" = 0 ] || why=" (BUILDROOT is not $root)"
    say "pins: $n_ok as pinned, $n_bad differ, $n_skip path-dependent and not comparable here$why; all in $LOG/hashes.txt"
    if [ "$n_bad" != 0 ]; then
        [ "${GCC64_REPIN:-0}" = 1 ] && { say "GCC64_REPIN=1: not failing; new values in $LOG/hashes.txt"; return 0; }
        fail "$n_bad artifact(s) differ from chain/gcc64/HASHES"
    fi
}

stages=("$@")
[ ${#stages[@]} != 0 ] || stages=(bridge stage6 stage7 stage8 stage9 stage10)
for s in "${stages[@]}"; do
    case $s in stage[6-9]|stage10|bridge) ;; *) echo "$me: unknown stage '$s' (bridge, stage6 ... stage10)" >&2; exit 1 ;; esac
done
# Check the selected stages' pinned sources up front.
stage_sources() {
    case $1 in
        bridge) echo binutils-2.30.tar.xz gcc-4.0.4-git-944765863e.tar ;;
        stage6) echo gcc-4.0.4-git-944765863e.tar ;;
        stage7) echo musl-1.1.24.tar.gz gmp-6.2.1+dfsg.tar.xz mpfr-4.1.0.tar.xz mpc-1.2.1.tar.gz ;;
        stage8) echo gcc-4.7.4.tar.xz binutils-2.41.tar.xz ;;
        stage9) echo binutils-2.41.tar.xz ;;
        stage10) echo gcc-10.5.0.tar.xz ;;
    esac
}
for s in "${stages[@]}"; do
    for f in $(stage_sources "$s"); do need "$f"; done
done
mkhostbin
export PATH="$W/guard:$W/hostbin"
mkguard
devnull() { [ -c /dev/null ] || fail "/dev/null is no longer a character device (after $1)"; }
devnull start
say "BUILDROOT=$W  GCC64_CACHE=$D  stages: ${stages[*]}"
for s in "${stages[@]}"; do "$s"; devnull "$s"; done
hashes
say "all requested stages passed"
