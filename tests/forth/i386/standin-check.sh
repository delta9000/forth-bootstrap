#!/usr/bin/env bash
# tests/forth/i386/standin-check.sh -- the i386 host's stand-ins stay in
# step with the x86-64 files they stand in for.
#
#     tests/forth/i386/standin-check.sh         (from anywhere)
#
# forth/i386/010-lib.fth and forth/i386/020-cc-arena.fth are copies of
# forth/010-lib.fth and cc/020-cc-arena.fth with their machine code, their
# system calls and their input changed for a 32-bit host
# (forth/i386/CONTRACT.md, section 3.1).  Three checks:
#
#   1. The difference is pinned: `diff` of each pair equals the committed
#      tests/forth/i386/010-lib.diff and 020-cc-arena.diff.  A change to
#      either side fails here until someone has looked at the other side
#      and written the new difference down:
#          diff forth/010-lib.fth forth/i386/010-lib.fth > tests/forth/i386/010-lib.diff
#          diff cc/020-cc-arena.fth forth/i386/020-cc-arena.fth > tests/forth/i386/020-cc-arena.diff
#
#   2. Vocabulary: no name that the x86-64 pair defines and the stand-ins
#      do not is used by a file loaded after them (the layers from 030 on,
#      the two drivers, the two jobs).  A name counts as defined when it
#      follows :, code:, create, variable, constant or defer, or is one of
#      the seed's 21 words.  This sees names only; that a word of the same
#      name has the same stack effect is for the reader of the pinned
#      difference.
#
#   3. The load list: forth/i386/layers.fth holds only comments and
#      `include` lines, and its files, with the stand-in for 020 put back
#      and the two shadows taken out, are what cc/i386/layers.sh prints
#      after the library.
set -euo pipefail
cd "$(dirname "$0")/../../.."

D=tests/forth/i386
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "standin-check: FAIL: $*" >&2; exit 1; }

# ---- 1. the pinned difference ----
pinned() {    # ORIGINAL STAND-IN DIFF
    diff "$1" "$2" > "$T/diff" || true
    cmp -s "$T/diff" "$3" || fail "diff $1 $2 is no longer $3"
    echo "standin-check: $2 differs from $1 as pinned, $(grep -c '^[<>]' "$3") lines"
}
pinned forth/010-lib.fth forth/i386/010-lib.fth $D/010-lib.diff
pinned cc/020-cc-arena.fth forth/i386/020-cc-arena.fth $D/020-cc-arena.diff

# ---- 2. vocabulary ----
# words FILE...: every token outside \ comments, one per line
words() { sed -e '/^\\/d' -e 's/[[:space:]]\\ .*$//' "$@" | tr -s ' \t' '\n'; }
defined() {
    words "$@" | awk 'prev ~ /^(:|code:|create|variable|constant|defer)$/ { print } { prev = $0 }' | sort -u
}
mapfile -t later < <(sed -n 's/^include //p' forth/i386/layers.fth | grep -v '^forth/i386/020-')
later+=(tinycc/tcc-compile-i386.fth tinycc/tool-compile.fth tinycc/i386-seed/tcc-first.fth tinycc/i386-seed/tool.fth)
defined forth/010-lib.fth cc/020-cc-arena.fth > "$T/x86-64"
# the seed's 21 words are there on either host; the x86-64 020 redefines
# * and /, which the i386 host leaves to its seed
{ defined forth/i386/010-lib.fth forth/i386/020-cc-arena.fth
  printf '%s\n' dup drop swap '>r' 'r>' @ ! c@ c! + '*' / nand 0= key token find syscall6 state : ';'
} | sort -u > "$T/i386"
comm -23 "$T/x86-64" "$T/i386" > "$T/missing"
words "${later[@]}" | sort -u > "$T/used"
comm -12 "$T/missing" "$T/used" > "$T/missed"
[ ! -s "$T/missed" ] || fail "the files loaded after the stand-ins use words only the x86-64 files define: $(tr '\n' ' ' < "$T/missed")"
echo "standin-check: $(wc -l < "$T/x86-64") names in the x86-64 pair; $(wc -l < "$T/missing") are not in the stand-ins," \
    "and none of those is used by the ${#later[@]} files loaded after them"

# ---- 3. the load list ----
! grep -v -e '^\\' -e '^include [^ ]*$' forth/i386/layers.fth \
    || fail "forth/i386/layers.fth has a line that is neither a comment nor an include"
sed -n 's/^include //p' forth/i386/layers.fth \
    | sed -e 's|^forth/i386/020-cc-arena.fth$|cc/020-cc-arena.fth|' \
          -e '\|^forth/i386/030-io.fth$|d' -e '\|^forth/i386/115-nzero.fth$|d' > "$T/list"
cc/i386/layers.sh | tail -n +2 > "$T/layers"
cmp -s "$T/list" "$T/layers" || { diff "$T/list" "$T/layers" >&2 || true; fail "forth/i386/layers.fth is not cc/i386/layers.sh's list"; }
echo "standin-check: forth/i386/layers.fth loads cc/i386/layers.sh's $(wc -l < "$T/layers") files after the library, and two shadows"
echo "standin-check: OK"
