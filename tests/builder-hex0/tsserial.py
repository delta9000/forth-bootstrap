#!/usr/bin/env python3
"""Copy stdin to stdout, prefixing each line with host monotonic seconds."""
import sys, time
t0 = time.monotonic()
buf = b""
inp = sys.stdin.buffer
while True:
    c = inp.read1(65536)
    if not c:
        break
    buf += c
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        sys.stdout.write(f"[{time.monotonic() - t0:10.4f}] " + line.decode("latin-1").rstrip("\r") + "\n")
        sys.stdout.flush()
if buf:
    sys.stdout.write(f"[{time.monotonic() - t0:10.4f}] " + buf.decode("latin-1") + "\n")
