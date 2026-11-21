#!/usr/bin/env bash
# tests/tinycc/i386-kaem-check.sh -- the Forth-built i386 kaem runs scripts
# on Linux.
#
#     tests/tinycc/i386-kaem-check.sh        (from anywhere)
#
# tinycc/build-tools-i386.sh builds build-out/tinycc/kaem-i386 from
# vendor/mescc-tools/Kaem with seed-forth and compares it with its pin.
# This runs it on the host's kernel through its IA32 support:
#   - kaem's own tests, vendor/mescc-tools/Kaem/test.sh, unchanged, in a
#     copy of that directory: eighteen scripts whose output must have the
#     sha256 of test/test.answers.  They start host programs (printf and
#     the like) through fork, execve and waitpid;
#   - a script whose commands are i386 tools of build-out/tinycc/bin-i386:
#     kaem must go on after a status of 0, stop with "Subprocess error 1"
#     after a status of 1, and answer a command that is not there with
#     tinycc/m2libc-kaem-i386.c's guard, never reaching execve.
# tests/tinycc/i386-kaem-boot-check.sh runs the same kaem on builder-hex0.
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=build-out/tinycc
W=$OUT/kaem-check
fail() { echo "i386-kaem-check: FAIL: $*" >&2; exit 1; }

tinycc/build-tools-i386.sh | tail -1
rm -rf "$W"
mkdir -p "$W/bin"
cp -r vendor/mescc-tools/Kaem "$W/Kaem"
cp vendor/mescc-tools/sha256.sh "$W/sha256.sh"
cp "$OUT/kaem-i386" "$W/bin/kaem"
mkdir "$W/Kaem/test/results"
(cd "$W/Kaem" && bash ./test.sh) > "$W/test.log" 2>&1 \
    || { tail -25 "$W/test.log" >&2; fail "vendor/mescc-tools/Kaem/test.sh (log: $W/test.log)"; }
echo "i386-kaem-check: $(grep -c ': OK$' "$W/test.log") of kaem's own tests OK"

# Exit statuses, with the i386 tools as the commands.
BIN32=$PWD/$OUT/bin-i386
cat > "$W/status.kaem" <<SCRIPT
$BIN32/match yes yes
$BIN32/catm $PWD/$W/copy $PWD/$W/status.kaem
$BIN32/match yes no
$BIN32/catm $PWD/$W/not-reached $PWD/$W/status.kaem
SCRIPT
rc=0
"$W/bin/kaem" --file "$W/status.kaem" > "$W/status.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "kaem exited $rc on a failing command, not 1"
grep -qx 'Subprocess error 1' "$W/status.log" || fail "no 'Subprocess error 1' (log: $W/status.log)"
cmp -s "$W/copy" "$W/status.kaem" || fail "the command before the failing one did not run"
[ ! -e "$W/not-reached" ] || fail "kaem went on after the failing command"
echo "i386-kaem-check: status 0 goes on, status 1 stops with 'Subprocess error 1'"

# A command that is not there: the guard answers, and execve is not called.
printf '%s\n' "$PWD/$W/no-such-program" > "$W/missing.kaem"
rc=0
strace -f -o "$W/missing.strace" "$W/bin/kaem" --file "$W/missing.kaem" > "$W/missing.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "kaem exited $rc on a missing command, not 1"
grep -q 'access(.*no-such-program", F_OK) *= -1' "$W/missing.strace" || fail "no access() of the missing command"
! grep -q 'execve(.*no-such-program' "$W/missing.strace" || fail "execve was called for a missing command"
echo "i386-kaem-check: a missing command is refused by access, with no execve"
echo "i386-kaem-check: OK"
