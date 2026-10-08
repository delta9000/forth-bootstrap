#!/usr/bin/env bash
# Print the compiler layers' paths in load order (after forth/010-lib.fth).
# The executing main must be last, including when optional library files
# have numbers greater than 120.  ROOT defaults to the current directory.
set -euo pipefail
root=${1:-.}
for path in "$root"/cc/[0-9][0-9][0-9]-cc-*.fth; do
    case "$path" in */cc/120-cc-main.fth) continue ;; esac
    printf '%s\n' "$path"
done
printf '%s\n' "$root/cc/120-cc-main.fth"
