#!/usr/bin/env python3
"""Hash the files of a builder-hex0 record stream on a disk image.

    python3 -I tinycc/hex0-records.py DISK SECTOR

Reads "src SIZE PATH\\n" records (and the SIZE bytes after each) from
sector SECTOR of DISK until the first line that is not one, and prints
`sha256  PATH` for every record with SIZE > 0, then that line as
`# end: LINE`.  tests/tinycc/i386-one-boot-check.sh uses it on what the
boot exported (sector 0).
"""
import hashlib, sys

disk, sector = sys.argv[1], int(sys.argv[2])
with open(disk, "rb") as f:
    img = f.read()
off = sector * 512
while True:
    nl = img.index(b"\n", off)
    line = img[off:nl].decode("ascii", "replace")
    parts = line.split(" ", 2)
    if len(parts) != 3 or parts[0] != "src" or not parts[1].isdigit():
        print(f"# end: {line[:80]}")
        break
    n = int(parts[1])
    off = nl + 1
    if n:
        print(f"{hashlib.sha256(img[off:off + n]).hexdigest()}  {parts[2]}")
    off += n
