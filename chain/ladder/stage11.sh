# chain/ladder/stage11.sh: gcc64's climb inside the chain root under K1, after
# chain/ladder/stage10-direct.sh: the bridge (stage D's GCC 4.0.4, its stage-C
# binutils and musl, and the Forth-built oyacc and flex 2.5.11) and stages
# 6-10 (gcc-4.0.4 B = C, musl/gmp/mpfr/mpc, gcc-4.7.4, binutils-2.41,
# gcc-10.5.0), with only stage 10's tools on PATH.
set -eu
export PATH=/usr/bin:/bin HOME=/ SHELL=/bin/sh LC_ALL=C TZ=UTC0 TAR_OPTIONS=--no-same-owner
export lt_cv_sys_max_cmd_len=1572864
B=/build-out/g64
mkdir -p $B $B/src
chmod 755 /chain/gcc64/*.sh            # copied into the root as plain files
export GCC64_DIRECT=/build-out/chain/stage-d GCC64_OYACC=/build-out/plumbing/bin/oyacc \
    GCC64_FLEX=/build-out/plumbing/bin/flex
[ $# -gt 0 ] || set -- bridge stage6 stage7 stage8 stage9 stage10
GCC64_CACHE=/build-out/distfiles BUILDROOT=$B JOBS=${JOBS:-16} \
    bash /chain/gcc64/run-gcc64.sh "$@" || {
    # Show the failing stage's log on the console (it is inside the build).
    log=$(ls -t $B/logs/*.log 2>/dev/null | head -1)
    [ -n "$log" ] && { echo "=== tail of $log"; tail -n 60 "$log"; }
    exit 1
}
