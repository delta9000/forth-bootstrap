#!/bin/bash
# tinycc/lb-replay.sh -- inside the junction chroot, run live-bootstrap's
# steps/mes-0.28 header install and steps/tcc-0.9.26/pass1.kaem with the
# first tcc standing in for MesCC's tcc-mes.
#
# Run by tests/tinycc/junction-check.sh as the chroot's first program, with
# the chroot's / laid out as live-bootstrap's is when steps/mes-0.28 starts:
# /steps/env, /steps/mes-0.28/, /steps/tcc-0.9.26/ and /seed/seed.kaem from
# the pinned live-bootstrap tree, /external/distfiles/ with the two
# archives, and the directories seed.kaem makes (/usr, /usr/bin,
# /usr/lib/mes, /usr/include/mes, /steps, /tmp, /dev).  Also mounted, read
# only: /host/usr (the host's /usr: bash, and grep, awk, sed and cat for
# this script's own text handling), /forth-bootstrap/tinycc (tinycc/),
# /forth-bootstrap/tcc-first (the first tcc) and /forth-bootstrap/bin
# (build-out/tinycc/bin-i386, the tools tinycc/build-tools-i386.sh builds
# from the seed).
#
# What runs is live-bootstrap's own kaem text, cut from their files at
# marker lines that must be present, and executed by bash (the kaem lines
# these steps use are also valid sh).  Its PATH is steps/env's followed by
# /forth-bootstrap/bin and nothing from the host, so every command it runs
# that is not a bash builtin is one of live-bootstrap's programs: stage0's
# catm, chmod, cp, match, mkdir, rm, sha256sum, ungz and untar, and
# live-bootstrap's checksum-transcriber and simple-patch, built from their
# C by seed Forth against M2libc, or a tcc of the replay.
# It is printed before it runs:
#   mes-0.28    only the lines that unpack mes-0.28 and install its headers
#               under /usr/include/mes.  mes-m2, mescc and MesCC's libc are
#               not built; nothing later reads them.
#   tcc-0.9.26  pass1.kaem from "# Vars" up to "# Checksums", except the
#               two mes-m2 commands that compile tcc.c with MesCC and link
#               tcc-mes; in their place the first tcc is copied to tcc-mes.
#               Every later command is theirs: same order, flags, -g, cwd
#               and absolute paths.  The checksum comparison is done by
#               junction-check.sh outside the chroot.
# With --first-only the tcc-0.9.26 text stops at "# Install", when the
# first tcc has made its libc and tcc-boot0 and nothing has replaced them
# (tests/tinycc/i386-standin-check.sh compares those files).
set -euo pipefail

FIRST=/forth-bootstrap/tcc-first
TOOLS=/forth-bootstrap/bin

# Print the lines of FILE from the line equal to FROM up to, not including,
# the next line equal to TO.  FROM must occur exactly once, TO after it.
cut_kaem() {
    local file=$1 from=$2 to=$3 n
    n=$(grep -cxF -- "$from" "$file" || true)
    [ "$n" = 1 ] || { echo "lb-replay: $file: '$from' occurs $n times" >&2; exit 1; }
    awk -v from="$from" -v to="$to" '
        on && $0 == to { found = 1; exit }
        $0 == from { on = 1 }
        on { print }
        END { if (!found) exit 1 }' "$file" \
        || { echo "lb-replay: $file: no '$to' after '$from'" >&2; exit 1; }
}

# Run kaem text on stdin in a fresh bash, as kaem --file runs a step:
# variables it sets do not outlive it.  Its PATH is KAEM_PATH.
run_kaem() {
    local name=$1 dir=$2 text
    text=$(cat)
    echo "==== $name: running in $dir:"
    printf '%s\n' "$text" | sed 's/^/  | /'
    echo "==== $name: output"
    (
        set +u
        cd "$dir"
        export PATH=$KAEM_PATH
        eval "$text"
    )
}

# The environment live-bootstrap's steps run in: steps/env and seed.kaem's
# mes variables (which use its SRCDIR), for ARCH=x86.  steps/env's PATH is
# ${BINDIR}:/${ARCH_DIR}/bin; where live-bootstrap has stage0's tools in
# /x86/bin, the kaem text gets the seed-built ones after it.  This script's
# own commands use the host's.
ARCH=x86
PATH=/host/usr/bin
env_seed=$(grep -E '^(NYACC_PKG|MES_PKG|MES_PREFIX)=' /seed/seed.kaem)
env_steps=$(grep -E '^[A-Z]+=' /steps/env)
set +u
eval "$env_steps"
eval "$env_seed"
KAEM_PATH=$PATH:$TOOLS
PATH=/host/usr/bin
set -u
export ARCH NYACC_PKG MES_PKG MES_PREFIX DISTFILES PREFIX BINDIR LIBDIR INCDIR SRCDIR TMPDIR

# mes-0.28: unpack, the arch headers, the header install
K=/steps/mes-0.28/pass1.kaem
for line in 'mkdir build' 'cd build' \
    'ungz --file ${DISTFILES}/${MES_PKG}.tar.gz --output ${MES_PKG}.tar' \
    'untar --non-strict --file ${MES_PKG}.tar # ignore symlinks'; do
    grep -qxF -- "$line" "$K" || { echo "lb-replay: $K has no line '$line'" >&2; exit 1; }
done
{
    echo 'set -ex'
    cut_kaem "$K" 'if match ${ARCH} x86; then' 'if match ${ARCH} amd64; then'
    printf '%s\n' 'mkdir build' 'cd build' \
        'ungz --file ${DISTFILES}/${MES_PKG}.tar.gz --output ${MES_PKG}.tar' \
        'untar --non-strict --file ${MES_PKG}.tar # ignore symlinks'
    cut_kaem "$K" 'cd ${MES_PREFIX}' '# Remove pregenerated files'
    cut_kaem "$K" '# Make directories' 'cd ../..' | grep -v '^cp ${LIBDIR}/'
} | pkg=mes-0.28 run_kaem mes-0.28 /steps/mes-0.28

# tcc-0.9.26: everything but MesCC and the checksums.
K=/steps/tcc-0.9.26/pass1.kaem
{
    echo 'set -ex'
    cut_kaem "$K" '# Vars' '${MES} --no-auto-compile -e main ${BINDIR}/mescc.scm -- \'
    echo "cp $FIRST tcc-mes"
    end='# Checksums'
    [ "${1:-}" = --first-only ] && end='# Install'
    cut_kaem "$K" 'cp tcc-mes ${BINDIR}/' "$end"
} | pkg=tcc-0.9.26 run_kaem tcc-0.9.26 /steps/tcc-0.9.26

echo "==== lb-replay: done"
