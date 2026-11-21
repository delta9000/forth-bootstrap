#!/bin/sh
# Build the i386 probe with host gcc (no libc, own int 0x80 stubs).
# Writes build-out/builder-hex0-probe/probe.
set -e
H=$(cd "$(dirname "$0")" && pwd)
W=$H/../../build-out/builder-hex0-probe
mkdir -p "$W"
cd "$W"
gcc -m32 -march=i386 -static -nostdlib -ffreestanding -fno-pic -no-pie \
    -fno-stack-protector -fno-asynchronous-unwind-tables -fno-builtin -O0 -Wall \
    -Wno-unused-function -T "$H/src/probe.ld" -Wl,--build-id=none -Wl,-z,norelro \
    -Wl,--no-warn-rwx-segments -o probe "$H/src/start.S" "$H/src/probe.c" -lgcc
