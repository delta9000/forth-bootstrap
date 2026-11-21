#!/usr/bin/env python3
"""Read strace traces of i386 seed runs and check each against what the
host side may do on builder-hex0 (forth/i386/CONTRACT.md, section 5).
tests/tinycc/i386-seed-check.sh says what is checked and why.

  python3 tests/tinycc/i386-seed-syscall-check.py TRACE...

Each TRACE is one run of the seed under strace, without -f: the seed starts
no other process.
"""
import collections, re, sys

ALLOWED = {"brk", "open", "read", "write", "close", "exit"}
CAP = 0x28000000                        # brk-cap of forth/i386/010-lib.fth
CALL = re.compile(r"(\w+)\((.*)\) += +(-?\w+)")


def check(path):
    """The violations of one trace, and its counts."""
    bad = []
    count = collections.Counter()
    open_files = {}                     # fd -> name
    break_now = None
    output = None                       # fd of the file being written
    lines = open(path, errors="replace").read().splitlines()
    assert lines and lines[0].startswith("execve("), f"{path}: not a trace of one program"
    for line in lines[1:]:
        m = CALL.match(line)
        if not m:
            if line.startswith("exit("):
                count["exit"] += 1
            elif not line.startswith(("+++", "[")):
                bad.append(f"not understood: {line[:70]}")
            continue
        name, args, result = m.groups()
        count[name] += 1
        if name not in ALLOWED:
            bad.append(f"{name}({args[:50]}) is not one of the host's calls")
            continue
        if output is not None and name not in ("write", "close"):
            bad.append(f"{name}({args[:50]}) after the output file was opened")
        if name == "brk":
            asked = 0 if args == "NULL" else int(args, 0)
            if asked and asked < break_now:
                bad.append(f"brk({asked:#x}) below the break {break_now:#x}")
            if asked > CAP:
                bad.append(f"brk({asked:#x}) above the cap {CAP:#x}")
            break_now = int(result, 0)
        elif name == "open" and not result.startswith("-"):
            open_files[result] = args.split('"')[1]
            if "O_CREAT" in args:
                output = result
        elif name == "close":
            if open_files.pop(args, None) is None:
                bad.append(f"close({args}) of a descriptor that is not open")
        elif name in ("read", "write"):
            fd = args.split(",")[0]
            if name == "read" and fd == "0":
                bad.append("read of descriptor 0")
            if name == "write" and fd != output:
                bad.append(f"write to descriptor {fd}, which is not the output file")
    # What is still open at exit: the Forth files the run was in the middle of.
    for fd, name in open_files.items():
        if not name.endswith(".fth"):
            bad.append(f"{name} was not closed")
    if len(open_files) > 3:
        bad.append(f"{len(open_files)} Forth files left open: {' '.join(open_files.values())}")
    if output is None:
        bad.append("no output file was created")
    return bad, count, break_now or 0


def main():
    total = collections.Counter()
    failures = 0
    highest = 0
    for path in sys.argv[1:]:
        bad, count, break_end = check(path)
        total += count
        highest = max(highest, break_end)
        for line in bad[:10]:
            print(f"  FAIL  {path}: {line}")
        failures += len(bad)
    print(f"i386-seed-syscall-check: {len(sys.argv) - 1} runs, {sum(total.values())} calls, highest break {highest:#x}")
    for name, n in sorted(total.items(), key=lambda kv: -kv[1]):
        print(f"  {n:8}  {name}")
    if failures:
        sys.exit(f"i386-seed-syscall-check: FAIL: {failures} violation(s)")
    print("i386-seed-syscall-check: OK, only brk, open, read, write, close and exit; no brk downward or\n"
          "  above the cap; no read of descriptor 0; every file but the Forth being read is closed;\n"
          "  and the output is opened last, after which the run only writes it and closes it")


main()
