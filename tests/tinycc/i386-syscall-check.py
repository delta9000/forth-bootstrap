#!/usr/bin/env python3
"""Read an strace -f trace of the junction replay and check the system
calls of the first tcc (every process whose program is named tcc-mes) and
of the seed-built tools (every program in /forth-bootstrap/bin) against
what builder-hex0 can do.  tests/tinycc/i386-syscall-check.sh says what
is checked and why.

  python3 tests/tinycc/i386-syscall-check.py TRACE
"""
import collections, re, sys

ALLOWED = {"exit", "fork", "read", "write", "open", "close", "waitpid", "execve",
           "chdir", "lseek", "access", "mkdir", "brk", "getcwd"}
# What rm and chmod are for, and untar's symbolic links (three in
# mes-0.28, which nothing reads); builder-hex0 answers 0 and does nothing.
TOOL_ONLY = {"rm": {"unlink"}, "chmod": {"chmod"}, "untar": {"symlink"}}


def kind(path):
    """The first tcc, a tool's name, or None for any other program."""
    if path.endswith("/tcc-mes"):
        return "tcc-mes"
    if path.startswith("/forth-bootstrap/bin/"):
        return path.rsplit("/", 1)[1]
    return None


def calls(path):
    """Yield (pid, name, arguments, result) for each completed call."""
    unfinished = {}
    for line in open(path, errors="replace"):
        m = re.match(r"(\d+) +(.*)", line.rstrip("\n"))
        if not m:
            continue
        pid, text = m.groups()
        if text.endswith("<unfinished ...>"):
            unfinished[pid] = text[:-len("<unfinished ...>")].rstrip()
            continue
        m = re.match(r"<\.\.\. \w+ resumed>(.*)", text)
        if m:
            text = unfinished.pop(pid, "") + m.group(1)
        m = re.match(r"(\w+)\((.*)\) += +(-?\w+|\?)", text)
        if m:
            yield pid, m.group(1), m.group(2), m.group(3)
        else:
            m = re.match(r"(\w+)\((.*)", text)       # exit never returns
            if m and m.group(1) in ("exit", "exit_group"):
                yield pid, m.group(1), m.group(2), "?"


def number(text):
    return 0 if text in ("NULL", "?") else int(text, 0)


def main():
    program = {}                        # pid -> path of its last execve
    brk = {}                            # pid -> current break
    files = {}                          # (pid, fd) -> [name, position, length or None]
    newest = {}                         # pid -> (pid, fd) of the file it created last
    count = collections.Counter()
    bad = []
    processes = [0, 0]                  # runs of the tools, of the first tcc
    highest = 0
    for pid, name, args, result in calls(sys.argv[1]):
        if name == "execve" and result == "0":
            program[pid] = kind(args.split('"')[1])
            if program[pid]:
                processes[program[pid] == "tcc-mes"] += 1
                brk.pop(pid, None)
            continue
        who = program.get(pid)
        if not who:
            continue
        count[name] += 1
        if name in TOOL_ONLY.get(who, ()):
            continue
        if name not in ALLOWED:
            bad.append(f"{pid} {who}: {name}({args[:60]}) is not a builder-hex0 call")
            continue
        if name == "brk":
            asked = number(args)
            if asked and pid in brk and asked < brk[pid]:
                bad.append(f"{pid} {who}: brk({asked:#x}) below the break {brk[pid]:#x}")
            brk[pid] = number(result)
            highest = max(highest, brk[pid])
        elif name == "open" and not result.startswith("-"):
            created = "O_CREAT" in args
            files[pid, result] = [args.split('"')[1], 0, 0 if created else None]
            if created:
                newest[pid] = (pid, result)
        elif name in ("read", "write", "lseek"):
            fd = args.split(",")[0]
            f = files.get((pid, fd))
            if f is None or result.startswith("-"):
                continue                # the console, or a failed call
            if name == "lseek":
                f[1] = number(result)
            elif name == "read":
                f[1] += number(result)
            elif f[2] is None:
                bad.append(f"{pid} {who}: write to {f[0]}, opened without O_CREAT")
            else:
                if f[1] > f[2]:
                    bad.append(f"{pid} {who}: write to {f[0]} at {f[1]}, past its end {f[2]}")
                f[1] += number(result)
                if f[1] > f[2] and newest[pid] != (pid, fd):
                    bad.append(f"{pid} {who}: {f[0]} grows, but is not the newest file")
                f[2] = max(f[2], f[1])
    print(f"i386-syscall-check: {processes[1]} runs of the first tcc and {processes[0]} of the tools, "
          f"{sum(count.values())} calls, highest break {highest:#x}")
    for name, n in sorted(count.items(), key=lambda kv: -kv[1]):
        print(f"  {n:6}  {name}")
    for line in bad[:20]:
        print("  FAIL  " + line)
    if bad or not processes[0] or not processes[1]:
        sys.exit(f"i386-syscall-check: FAIL: {len(bad)} violation(s) in {sum(processes)} run(s)")
    print("i386-syscall-check: OK, only builder-hex0's calls, no brk downward, "
          "no write past the end of a file,\n  and only the newest file grows")


main()
