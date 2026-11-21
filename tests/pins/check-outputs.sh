#!/bin/sh
# check-outputs.sh -- compare what checks 04, 07 and 08 built with
# tests/pins/outputs.sha256.  A file those checks did not build (a SKIP) is
# reported and not compared.  Run from the repository root after them.
set -eu
cd "$(dirname "$0")/../.."
ok=0 bad=0 absent=0
while read -r h f; do
    case $h in ''|'#'*) continue ;; esac
    if [ ! -f "build-out/$f" ]; then
        echo "check-outputs: build-out/$f not built; not compared"
        absent=$((absent + 1))
    elif [ "$(sha256sum "build-out/$f" | cut -d' ' -f1)" = "$h" ]; then
        ok=$((ok + 1))
    else
        echo "check-outputs: build-out/$f is $(sha256sum "build-out/$f" | cut -d' ' -f1), pinned $h" >&2
        bad=$((bad + 1))
    fi
done < tests/pins/outputs.sha256
echo "check-outputs: $ok as pinned, $bad differ, $absent not built"
[ "$bad" = 0 ]
