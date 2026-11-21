#!/usr/bin/env python3
"""Count the system calls of the TinyCC junction's compilers, from strace.

  kernel/k1/tests/i386-trace.py TRACE

TRACE is `strace -n -f -o TRACE` of the junction's bwrap (kernel/k1/I386.md
says how to take it).  For every process whose program is tcc-mes,
tcc-boot0, tcc-boot1, tcc-boot2 or tcc, from its execve on, it prints the
calls by name and number (the number is strace -n's: i386 numbers for the
i386 programs, x86-64 numbers for tcc-mes), then each call's argument
pattern with strings, addresses and large numbers folded.  The execve that
starts a program is its parent's call and is not counted.
"""
import collections, re, sys

LINE = re.compile(r'^(\d+) (?:\[ *(\d+)\] )?(.*)$')
CALL = re.compile(r'^(\w+)\((.*)\)\s+= (.*)$')


def fold(name, args, ret):
    if name in ("read", "write"):
        fd = args.split(",")[0]
        args = fd + ", ..., " + ("1" if ret.split()[0] == "1" else "n")
    args = re.sub(r'"[^"]*"(\.\.\.)?', '"..."', args)
    args = re.sub(r'\{st_dev.*\}', '{...}', args)
    args = re.sub(r'0x[0-9a-f]+', 'ADDR', args)
    args = re.sub(r'\b\d{3,}\b', 'N', args)
    ret = re.sub(r'0x[0-9a-f]+', 'ADDR', ret)
    ret = re.sub(r'^\d+.*', 'n', ret) if not ret.startswith("-1") else ret.split(" (")[0]
    return f"{name}({args}) = {ret}"


def main():
    prog, pending = {}, {}
    calls = collections.defaultdict(collections.Counter)
    shapes = collections.defaultdict(collections.Counter)
    runs = collections.Counter()
    for raw in open(sys.argv[1], errors="replace"):
        m = LINE.match(raw.rstrip("\n"))
        if not m:
            continue
        pid, num, rest = int(m.group(1)), m.group(2) or "?", m.group(3)
        if rest.endswith("<unfinished ...>"):
            pending[pid] = (num, rest[:-len("<unfinished ...>")])
            continue
        r = re.match(r'^<\.\.\. \w+ resumed>(.*)$', rest)
        if r:
            num, head = pending.pop(pid, (num, ""))
            rest = head + r.group(1)
        c = CALL.match(rest)
        if not c:
            continue
        name, args, ret = c.groups()
        if name == "execve" and ret.startswith("0"):
            prog[pid] = re.match(r'"([^"]*)"', args).group(1).rsplit("/", 1)[-1]
            runs[prog[pid]] += 1
            continue
        if name in ("clone", "fork", "vfork") and ret.split()[0].isdigit():
            prog[int(ret.split()[0])] = prog.get(pid, "?")
        p = prog.get(pid, "?")
        if p not in ("tcc-mes", "tcc-boot0", "tcc-boot1", "tcc-boot2", "tcc"):
            continue
        calls[p][f"{name} ({num})"] += 1
        shapes[p][fold(name, args, ret)] += 1
    for p in calls:
        print(f"== {p}: {runs[p]} runs, {sum(calls[p].values())} calls")
        for k, n in calls[p].most_common():
            print(f"  {n:7d}  {k}")
    for p in shapes:
        print(f"== {p}: argument patterns")
        for k, n in shapes[p].most_common():
            print(f"  {n:7d}  {k[:160]}")


if __name__ == "__main__":
    main()
