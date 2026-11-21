#!/usr/bin/env bash
# tests/forth/i386/host-words-check.sh -- the words forth/i386/010-lib.fth
# adds to the library: include, the end of an included file, and
# brk-alloc's refusals.
#
#     tests/forth/i386/host-words-check.sh      (from anywhere)
#
# Needs the i386 seed: ./seed-forth-i386 (seed/i386/build.sh) or the
# program SEED_I386 names.  A compile never asks brk-alloc for too much,
# nests seventeen files or names a missing one, and every file it includes
# ends in a newline, so the byte-for-byte oracle of
# tests/tinycc/i386-seed-check.sh does not reach these.  Each case is a
# small job written to a temporary directory; the files without a final
# newline are why they are not kept in the repository.
set -euo pipefail
cd "$(dirname "$0")/../../.."

SEED=${SEED_I386:-./seed-forth-i386}
LIB=forth/i386/010-lib.fth
[ -x "$SEED" ] || { echo "host-words-check: cannot run: no i386 seed: $SEED" >&2; exit 1; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "host-words-check: FAIL: $*" >&2; exit 1; }
# expect WHAT STATUS OUTPUT JOB: run JOB; it must print OUTPUT and exit STATUS
expect() {
    local rc=0 out
    out=$("$SEED" $LIB "$4") || rc=$?
    [ "$rc" = "$2" ] && [ "$out" = "$3" ] || fail "$1: exit $rc and '$out', not exit $2 and '$3'"
    echo "host-words-check: $1"
}

# The end of an included file is a newline: a last token with nothing after
# it does not join the includer's next token, and a comment on a last line
# does not swallow the includer's next line.
printf '65 emit 66' > "$T/token.fth"
printf '67 emit \\ a comment and no newline' > "$T/comment.fth"
printf 'include %s\nemit include %s\n68 emit 10 emit\n' "$T/token.fth" "$T/comment.fth" > "$T/ends.fth"
expect "an included file ends as a line ends" 0 "ABCD" "$T/ends.fth"

# include nests, and goes on in the includer where it left off.
printf '66 emit include %s 68 emit\n' "$T/inner.fth" > "$T/middle.fth"
printf '67 emit\n' > "$T/inner.fth"
printf '65 emit include %s 69 emit 10 emit\n' "$T/middle.fth" > "$T/nest.fth"
expect "include nests and returns" 0 "ABCDE" "$T/nest.fth"

# A file that is not there: its name and "?", exit 2, and nothing after it.
printf '65 emit include %s 66 emit\n' "$T/no-such-file" > "$T/missing.fth"
expect "a missing file is fatal" 2 "A$T/no-such-file?" "$T/missing.fth"

# Sixteen files can wait on the include stack.  A file that includes itself
# is the job at depth 1 and is refused when it would be the seventeenth:
# sixteen marks, then its name and "?".
printf '88 emit include %s\n' "$T/self.fth" > "$T/self.fth"
expect "the seventeenth nested file is fatal" 2 "XXXXXXXXXXXXXXXX$T/self.fth?" "$T/self.fth"

# brk-alloc.  A request that wraps past 2^64 and one that would pass the
# cap answer 0 and leave the break alone; a page is granted, starts at the
# old break, is zero and can be written; then the break has moved by it.
cat > "$T/brk.fth" <<'JOB'
: mark  ( f -- )  if, 89 else, 78 then, emit ;      \ Y or N
0 brk                                               \ the break before
18446744073709551615 brk-alloc 0=  mark
671088640 brk-alloc 0=  mark
dup 0 brk =  mark                                   \ neither moved it
4096 brk-alloc  2dup =  mark                        \ granted at the old break
dup @ 0=  mark   1311768467463790320 over !  dup @ 1311768467463790320 =  mark
drop  0 brk swap - 4096 =  mark                     \ and the break rose a page
10 emit
JOB
expect "brk-alloc refuses a wrapped sum and the cap, and grants a zeroed page" 0 "YYYYYYY" "$T/brk.fth"

# A kernel that will not move the break: with the data segment limited,
# Linux answers the old break, and brk-alloc answers 0.
printf ': mark if, 89 else, 78 then, emit ;\n268435456 brk-alloc 0= mark 10 emit\n' > "$T/refused.fth"
out=$(ulimit -d 65536; "$SEED" $LIB "$T/refused.fth") || fail "the run under ulimit -d exited $?"
[ "$out" = Y ] || fail "brk-alloc under ulimit -d: '$out', not 'Y'"
echo "host-words-check: brk-alloc answers 0 when the kernel does not move the break"
echo "host-words-check: OK"
