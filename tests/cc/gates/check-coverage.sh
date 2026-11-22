#!/usr/bin/env bash
# check-coverage.sh -- which of the Forth C compiler's error codes a die gate
# tests.
#
# A compiler failure ends in cc-die (cc/020-cc-arena.fth), which prints
# "cc: line N: error C" and exits with C, or in the library's `die` with a
# message of its own.  This script finds every code C that the compiler's
# files (the ones forth/i386/layers.fth includes) can die with, and puts
# each in exactly one of three lists:
#
#   tested       a die gate in tests/cc/gates/run-gates.sh expects it (read
#                from that script's die_gates, not kept here)
#   unreachable  no C program can reach it; each entry says why
#   todo         untested: a test is still to be written
#
# It fails when a code is in none of the lists or in more than one, when a
# listed code is no longer raised anywhere, or when the way codes reach
# cc-die changes (a new forwarding word, below).  A new error site with a new
# code therefore fails here until it is tested or listed; a new test moves
# its code out of todo.
#
# How a code is found.  The layers are read as Forth tokens, with `\` and
# `( ... )` comments dropped, so a call split over two lines still counts:
#   1. `C W` (or `[lit] C W`, before the library interpreter took over),
#      where W is a word that dies with its last argument:
#      cc-die and cc-check-cap themselves, the wrappers that hand their code
#      to one of them (cc-workspace-map, cc-read-all), and the library's
#      `die`.
#   2. The hand-kept list `indirect` below: codes stored as the
#      preprocessor sink's die code and raised later by cc-prep-emit-byte.
#      The script checks each entry against the source, and fails on a
#      literal C before cc-pp-sink-push or `cc-pp-out-code !` that the list
#      does not name.
# Every other call of those words takes its code from the stack or a
# variable.  Those forwarding sites are pinned in `forwarding` by file and
# line text (not line number, so moving code does not break the check); a
# new one fails the check, because the codes it raises are invisible to 1.
#
# Usage: tests/cc/gates/check-coverage.sh [-v]
#   -v  also print, for each code, its list and the files that raise it.
set -euo pipefail
cd "$(dirname "$0")/../../.."

verbose=0
[ "${1:-}" = -v ] && verbose=1

die_words="cc-die cc-check-cap cc-workspace-map cc-read-all die"
files=$(sed -n 's/^include //p' forth/i386/layers.fth)

# "<file>|<line text, trimmed>": the calls of a die word whose code is not a
# literal right before it.
forwarding=(
  "forth/i386/020-cc-arena.fth|die ;"                           # cc-die: the exit itself
  "forth/i386/020-cc-arena.fth|>r > if, r> cc-die then,"        # cc-check-cap
  "cc/030-cc-io.fth|cc-ra-n @ 1+ cc-ra-cap @ cc-ra-code @ cc-check-cap"   # cc-read-all, stdin
  "cc/030-cc-io.fth|cc-ra-n @ 1+ cc-ra-cap @ cc-ra-code @ cc-check-cap   \\ full: die"
  "cc/030-cc-io.fth|>r dup [lit] 0 <= if, r@ cc-die then,"      # cc-workspace-round
  "cc/030-cc-io.fth|dup [lit] 9223372036854771712 > if, r@ cc-die then,"
  "cc/030-cc-io.fth|dup [lit] 0 <= if, r@ cc-die then, r> drop ;"   # cc-workspace-map
  "cc/040-cc-prep.fth|cc-pp-out-pos @ 1+ cc-pp-out-cap @ cc-pp-out-code @ cc-check-cap"  # cc-prep-emit-byte
)

# "<code>|<file>|<word>|<how it reaches cc-die>": codes that become the
# preprocessor sink's die code (cc-pp-out-code, cc/040-cc-prep.fth) and are
# raised by cc-prep-emit-byte when that sink fills.
indirect=(
  "35|cc/040-cc-prep.fth|cc-pp-to-pool|macro pool as the sink; cc-pp-sink-push stores 35"
  "36|cc/040-cc-prep.fth|cc-preprocess|the 2 MiB source buffer as the sink; stored straight into cc-pp-out-code"
  "37|cc/040-cc-prep.fth|cc-pp-temp-begin|a 64 KiB macro temp buffer as the sink; cc-pp-sink-push stores 37"
)

# "<code>|<why no C program reaches it>"
unreachable=(
  "62|cc-scope-pop (cc/070-cc-sym.fth) with no push; every pop is paired with a push in the parser, so reaching it is a parser bug"
)

# Untested, to do.  Grouped by the first file that raises each code; -v
# prints them all.
todo=(
  213 240                                       # 060-cc-types.fth
  210                                           # 115-cc-native.fth
  222 226                                       # 118-cc-native-init.fth
  130                                           # i386/090-emit.fth
)

# ---------------------------------------------------------------------------

# scan: one line per finding, from the layers as Forth tokens.
#   LIT <code> <file>:<line>            [lit] code then a die word
#   IND <code> <file>:<line> <word>     [lit] code then a sink-code store
#   FWD <file>|<line text>              die word without a literal code
scan() {
    awk -v diewords="$die_words" '
    BEGIN { n = split(diewords, a, " "); for (i = 1; i <= n; i++) dw[a[i]] = 1 }
    FNR == 1 { incomment = 0; pl2 = prev2 = prev1 = ""; word = "" }
    {
        line = $0; sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
        nt = split($0, t, /[ \t]+/)
        for (i = 1; i <= nt; i++) {
            tok = t[i]
            if (tok == "") continue
            if (incomment) { if (tok ~ /\)$/) incomment = 0; continue }
            if (tok == "\\" && prev1 != "[char]" && prev1 != "char") break
            if (tok == "(" && prev1 != "[char]" && prev1 != "char") {
                incomment = 1; continue
            }
            if (prev1 == ":") word = tok
            else if (tok in dw && prev1 != ":" && prev1 != "'\''") {
                if (prev1 ~ /^[0-9]+$/)
                    print "LIT", prev1, FILENAME ":" FNR
                else
                    print "FWD", FILENAME "|" line
            }
            else if (tok == "cc-pp-sink-push" && prev1 ~ /^[0-9]+$/)
                print "IND", prev1, FILENAME ":" FNR, word
            else if (tok == "!" && prev1 == "cc-pp-out-code" && prev2 ~ /^[0-9]+$/)
                print "IND", prev2, FILENAME ":" FNR, word
            pl2 = prev2; prev2 = prev1; prev1 = tok
        }
    }' $files
}

scan_out=$(scan)
errors=0
err() { echo "check-coverage: $*" >&2; errors=$((errors + 1)); }

# Forwarding sites: the scan's set must equal the pinned set.
got_fwd=$(grep '^FWD ' <<< "$scan_out" | cut -c5- | sort -u)
want_fwd=$(printf '%s\n' "${forwarding[@]}" | sort -u)
while IFS= read -r s; do
    [ -n "$s" ] && err "new forwarding site, codes it raises are not counted: $s"
done < <(comm -23 <(echo "$got_fwd") <(echo "$want_fwd"))
while IFS= read -r s; do
    [ -n "$s" ] && err "pinned forwarding site no longer found: $s"
done < <(comm -13 <(echo "$got_fwd") <(echo "$want_fwd"))

# Indirect codes: every sink-code store must be listed, and every entry found.
declare -A src_of
while read -r _ code where word; do
    hit=0
    for e in "${indirect[@]}"; do
        IFS='|' read -r c f w _ <<< "$e"
        if [ "$c" = "$code" ] && [ "$f" = "${where%%:*}" ] && [ "$w" = "$word" ]; then hit=1; fi
    done
    [ "$hit" = 1 ] || err "code $code is stored as a sink die code at $where ($word) but is not in indirect"
    src_of[$code]="${src_of[$code]:-} $where"
done < <(grep '^IND ' <<< "$scan_out")
for e in "${indirect[@]}"; do
    IFS='|' read -r c f w _ <<< "$e"
    grep -qE "^IND $c $f:[0-9]+ $w\$" <<< "$scan_out" \
        || err "indirect entry not found in the source: $c in $f, $w"
done

# All codes: literal sites plus indirect ones.
while read -r _ code where; do
    src_of[$code]="${src_of[$code]:-} $where"
done < <(grep '^LIT ' <<< "$scan_out")
n_lit=$(grep '^LIT ' <<< "$scan_out" | awk '{print $2}' | sort -un | wc -l)
all=$(printf '%s\n' "${!src_of[@]}" | sort -n)

# The three lists.
tested=$(sed -nE 's/^ *"(die-[^|]+)\|([0-9]+)\|.*/\2/p' tests/cc/gates/run-gates.sh | sort -nu)
unr=$(printf '%s\n' "${unreachable[@]}" | cut -d'|' -f1 | sort -n)
todo_codes=$(printf '%s\n' ${todo[@]} | sort -n)

declare -A list_of
for pair in "tested:$tested" "unreachable:$unr" "todo:$todo_codes"; do
    name=${pair%%:*}
    for c in ${pair#*:}; do
        if [ -n "${list_of[$c]:-}" ]; then
            err "code $c is in both ${list_of[$c]} and $name"
        fi
        list_of[$c]=${list_of[$c]:-}${list_of[$c]:+,}$name
        [ -n "${src_of[$c]:-}" ] || err "code $c is in $name but the compiler never raises it"
    done
done
for c in $all; do
    [ -n "${list_of[$c]:-}" ] \
        || err "code $c (${src_of[$c]# }) is not tested and not listed as unreachable or todo"
done

count() { [ -z "$1" ] && echo 0 || wc -w <<< "$1"; }
n_all=$(count "$all")
n_tested=$(count "$tested")

if [ "$verbose" = 1 ]; then
    for c in $all; do
        printf '%4s %-12s %s\n' "$c" "${list_of[$c]:-NONE}" \
            "$(tr ' ' '\n' <<< "${src_of[$c]}" | sed 's/:.*//' | sort -u | tr '\n' ' ')"
    done
fi
echo "check-coverage: $n_all error codes ($n_lit at a literal call, $(count "${indirect[*]/|*/}") indirect)"
echo "  tested by a die gate: $n_tested"
echo "  unreachable from C:   $(count "$unr")"
echo "  untested, to do:      $(count "$todo_codes")"
echo "  to do: $(echo $todo_codes)"
echo "check-coverage: $n_tested of $n_all codes tested"
if [ "$errors" != 0 ]; then
    echo "check-coverage: $errors problem(s)" >&2
    exit 1
fi
