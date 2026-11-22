#!/usr/bin/env python3
"""Check one run of ./seed-forth from its strace -f -o TRACE output
(seed/SPEC.md 13.1, "the same under strace -f").

  python3 tests/seed/strace-check.py TRACE OPENS

Rules:
  - the only calls are brk, open, read, write and exit;
  - open is called OPENS times: once by the seed for FILE, plus the opens the
    test's own Forth makes through syscall6;
  - no read of descriptor 0, and every read has count 1;
  - no brk below the current break: a brk with an address is compared with
    the result of the brk before it.
The first line is strace's own execve of the seed and is skipped, as are the
"runs in 32 bit mode" and "+++ exited" lines.  Anything else, a signal
included, fails.  Prints the first violation and exits 1, or exits 0.
"""
import re, sys

trace, opens = sys.argv[1], int(sys.argv[2])
lines = [re.sub(r"^\d+\s+", "", l.rstrip("\n")) for l in open(trace, errors="replace")]
if not lines or not lines[0].startswith("execve("):
    sys.exit("strace: the trace does not start with the seed's execve")
count, current = 0, None
for line in lines[1:]:
    if re.fullmatch(r"\[ Process PID=\d+ runs in 32 bit mode\. \]", line) \
            or re.fullmatch(r"\+\+\+ exited with \d+ \+\+\+", line):
        continue
    name = line.split("(", 1)[0]
    if name == "brk":
        m = re.fullmatch(r"brk\((NULL|0x[0-9a-f]+)\)\s+= (0x[0-9a-f]+)", line)
        if not m:
            sys.exit(f"strace: cannot read: {line}")
        if m.group(1) != "NULL" and (current is None or int(m.group(1), 16) < current):
            sys.exit(f"strace: brk below the current break: {line}")
        current = int(m.group(2), 16)
    elif name == "open":
        count += 1
    elif name == "read":
        m = re.fullmatch(r"read\((\d+), .*, (\d+)\)\s+= .*", line)
        if not m:
            sys.exit(f"strace: cannot read: {line}")
        if m.group(1) == "0":
            sys.exit(f"strace: read of descriptor 0: {line}")
        if m.group(2) != "1":
            sys.exit(f"strace: read with a count that is not 1: {line}")
    elif name not in ("write", "exit"):
        sys.exit(f"strace: a call other than brk, open, read, write, exit: {line}")
if count != opens:
    sys.exit(f"strace: {count} open calls, expected {opens}")
