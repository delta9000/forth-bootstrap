#!/usr/bin/env bash
# tests/cc/i386/run-corpus.sh -- the i386 back end against gcc -m32, at run
# time.
#
#     tests/cc/i386/run-corpus.sh               (from anywhere)
#
# Each tests/cc/i386/*.c is compiled twice, after prelude.h: by the seed
# (tests/cc/i386/job.fth) and by gcc -m32 -O0.  Both programs run on the host through its IA32 support
# with the arguments "a b", and must print the same lines and exit with
# the same status.  The programs print each value as two 32-bit halves, so
# a wrong high half of a long long shows, which the TinyCC junction's pins
# cannot see.
#
# A die-N-*.c must instead be refused by the Forth compiler with exit
# status N.
#
# Needs gcc with -m32 support, and a kernel that runs i386 programs (the
# seed is one: ./seed-forth-i386, or the program SEED_I386 names).
set -euo pipefail
cd "$(dirname "$0")/../../.."

T=tests/cc/i386
B=build-out/i386-corpus
[ -n "${SEED_I386:-}" ] || seed/i386/build.sh > /dev/null
SEED=${SEED_I386:-./seed-forth-i386}
echo 'int main (void) { return 0; }' | gcc -m32 -x c - -o /dev/null 2> /dev/null \
    || { echo "run-corpus: cannot run: gcc -m32 does not build a program here" >&2; exit 1; }
rm -rf "$B"
mkdir -p "$B"

# forth NAME: compile $T/NAME.c to $B/NAME.forth; the status is the seed's
forth() {
    local src=$B/$1.c
    cat "$T/prelude.h" "$T/$1.c" > "$src"
    "$SEED" forth/i386/010-lib.fth "$T/job.fth" "$B/$1.forth" "$src" > "$B/$1.stdout" 2> "$B/$1.stderr"
}

pass=0
bad=0
for c in "$T"/*.c; do
    name=$(basename "$c" .c)
    rc=0
    forth "$name" || rc=$?
    case $name in
        die-*)
            want=${name#die-}
            want=${want%%-*}
            if [ "$rc" = "$want" ]; then
                echo "  refused  $name (error $rc)"
                pass=$((pass + 1))
            else
                echo "  FAIL     $name: the seed exited $rc, expected $want"
                bad=$((bad + 1))
            fi
            continue ;;
    esac
    if [ "$rc" != 0 ] || [ -s "$B/$name.stdout" ] || [ ! -s "$B/$name.forth" ]; then
        echo "  FAIL     $name: the seed exited $rc: $(head -c 200 "$B/$name.stdout" "$B/$name.stderr" | tr '\n' ' ')"
        bad=$((bad + 1))
        continue
    fi
    gcc -m32 -O0 -w -static -fno-stack-protector -include "$T/prelude.h" "$c" -o "$B/$name.gcc"
    for k in forth gcc; do
        rc=0
        "$B/$name.$k" a b > "$B/$name.$k.out" 2>&1 || rc=$?
        echo "exit $rc" >> "$B/$name.$k.out"
    done
    if cmp -s "$B/$name.forth.out" "$B/$name.gcc.out"; then
        echo "  same     $name ($(wc -l < "$B/$name.gcc.out") lines)"
        pass=$((pass + 1))
    else
        echo "  FAIL     $name: the outputs differ (gcc <, Forth >)"
        diff "$B/$name.gcc.out" "$B/$name.forth.out" | head -10 | sed 's/^/           /'
        bad=$((bad + 1))
    fi
done
[ "$bad" = 0 ] || { echo "run-corpus: FAIL: $bad of $((pass + bad)) programs" >&2; exit 1; }
echo "run-corpus: OK, $pass programs"
