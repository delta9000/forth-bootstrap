#!/usr/bin/env python3
"""Host-side builder-hex0 disk, laid out as tinycc/hex0-disk.c (and
live-bootstrap's lib/generator.py) does it:

    python3 -I mkdisk.py OUT STAGE1 STAGE2 LIST

STAGE1 (bytes), STAGE2 (hex0 text), zeros to sector 175, then LIST's items:
    d PATH         "src 0 PATH\n"            a directory
    f PATH [NAME]  "src SIZE NAME\n" + bytes
    x LINE         "LINE\n"                  a shell command ("prog arg")
    r TEXT         "TEXT\n"                  raw bytes for a program reading fd 0
then zeros to a whole sector, and the image is padded to 64 MiB.
"""
import sys

out, stage1, stage2, lst = sys.argv[1:5]
img = bytearray(open(stage1, "rb").read() + open(stage2, "rb").read())
assert len(img) <= 175 * 512, "stages pass sector 175"
img += bytes(175 * 512 - len(img))
for line in open(lst).read().splitlines():
    if not line or line.startswith("#"):
        continue
    kind, rest = line[0], line[2:]
    if kind == "d":
        img += f"src 0 {rest}\n".encode()
    elif kind == "f":
        path, _, name = rest.partition(" ")
        data = open(path, "rb").read()
        img += f"src {len(data)} {name or path}\n".encode() + data
    elif kind in "xr":
        img += (rest + "\n").encode()
    else:
        raise SystemExit(f"bad line: {line}")
img += bytes(-len(img) % 512)
img += bytes(64 * 1024 * 1024 - len(img))
open(out, "wb").write(img)
