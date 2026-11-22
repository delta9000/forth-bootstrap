#!/usr/bin/env bash
# Build seed-forth from seed/000-seed.hex0 with stage0-posix's
# hex0-seed, a 229-byte assembler.  The AMD64 hex0-seed runs on the host;
# the file it writes is an i386 ELF, which needs the host kernel's IA32
# support to run.
#
# In the boot the same source is assembled by builder-hex0's built-in hex0
# command; the two results must be equal byte for byte.  Any hex0 assembler
# gives the same bytes, for instance
# `sed 's/[;#].*$//g' seed/000-seed.hex0 | xxd -r -p`.
set -euo pipefail
cd "$(dirname "$0")/.."

HEX0=${HEX0:-vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed}

if [ ! -x "$HEX0" ]; then
    cat >&2 <<EOT
seed/build.sh: hex0 assembler not found at $HEX0
Initialize the submodule:
    git submodule update --init vendor/stage0-posix
    git -C vendor/stage0-posix submodule update --init bootstrap-seeds
or set HEX0=/path/to/hex0 to use an alternative assembler.
EOT
    exit 1
fi

"$HEX0" seed/000-seed.hex0 seed-forth
chmod +x seed-forth
echo "Built seed-forth ($(wc -c < seed-forth) bytes) using $HEX0"
