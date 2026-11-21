"""simple-patch FILE BEFORE AFTER: replace the one occurrence of BEFORE's bytes
in FILE with AFTER's bytes, the job live-bootstrap's simple-patch does in
its kaem steps.  Fails, leaving FILE alone, when BEFORE occurs other than once.

Used for live-bootstrap's simple-patches and for tinycc/patches/*.before
and *.after.  Run with python3 -I.
"""
import sys

path, before, after = sys.argv[1:4]
text = open(path, "rb").read()
old = open(before, "rb").read()
new = open(after, "rb").read()
n = text.count(old)
if n != 1:
    sys.exit(f"simple-patch: {path}: {before} occurs {n} times, not once")
open(path, "wb").write(text.replace(old, new))
