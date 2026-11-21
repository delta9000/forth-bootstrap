#!/usr/bin/env python3
"""Boot 2's script and the list of its files, for the hex0 hand-off.

    python3 -I tinycc/hex0-handoff-stream.py PREP OUT

PREP is the root `tinycc/lb-replay.sh --prepare` left (live-bootstrap's
steps/, seed/seed.kaem and the unpacked trees).  Writes into OUT:

hex0-handoff.kaem  boot 2's kaem script.  Every line between our first and
    last lines is live-bootstrap's, cut from PREP's steps/env,
    seed/seed.kaem and steps/tcc-0.9.26/pass1.kaem at marker lines that
    must each occur once: the variables, `cd build`, and `cd ${TCC_PKG}`
    with the ARCH blocks after it, which run before MesCC, and everything from "# Install"
    (tcc-boot0 onward) up to "# Checksums".  Ours: `set -ex`, ARCH, pkg,
    the first `cd` (live-bootstrap's script generator does it), and the
    last line, which exports the ten checksummed files to /dev/hda.

hex0-handoff.list  what tinycc/hex0-disk.c writes after builder-hex0's two
    stages, one item per line:
        d PATH          a directory: "src 0 PATH"
        f PATH [NAME]   K0's file PATH as "src SIZE NAME" and its bytes
        x LINE          LINE itself, a command for builder-hex0's shell
    The files are live-bootstrap's trees as PREP has them (symbolic links
    left out, as `untar --non-strict` does), the files boot 1 makes in them
    (unified-libc.c, tcc-boot0, mes libc, the i386 tools), and the script
    as /kaem.run, which kaem reads when started with no file.
"""
import os, sys

TCC_PKG = "tcc-0.9.26-1147-gee75a10c"
BUILD = "/steps/tcc-0.9.26/build"
EXPORT = ["/usr/bin/tcc-mes", "/usr/bin/tcc-boot0", "/usr/bin/tcc-boot1", "/usr/bin/tcc",
          "/usr/lib/mes/libc.a", "/usr/lib/mes/libgetopt.a", "/usr/lib/mes/crt1.o",
          "/usr/lib/mes/crti.o", "/usr/lib/mes/crtn.o", "/usr/lib/mes/tcc/libtcc1.a"]
# made in boot 1 (tinycc/hex0-handoff.recipe), not in PREP
MADE = [f"{BUILD}/mes-0.28/unified-libc.c", f"{BUILD}/{TCC_PKG}/tcc-boot0",
        "/usr/bin/tcc-mes", "/usr/bin/kaem", "/usr/bin/cp", "/usr/bin/chmod",
        "/usr/bin/match", "/usr/bin/rm", "/usr/bin/hex0-export",
        "/usr/lib/mes/crt1.o", "/usr/lib/mes/crti.o", "/usr/lib/mes/crtn.o",
        "/usr/lib/mes/libc.a", "/usr/lib/mes/libgetopt.a", "/usr/lib/mes/tcc/libtcc1.a"]


def cut(lines, start, stop):
    """Lines from the one equal to start up to, not including, stop."""
    assert lines.count(start) == 1, f"'{start}' occurs {lines.count(start)} times"
    i = lines.index(start)
    j = lines.index(stop, i)
    return lines[i:j]


def script(prep):
    k = open(f"{prep}/steps/tcc-0.9.26/pass1.kaem").read().splitlines()
    env = [l for l in open(f"{prep}/steps/env").read().splitlines()
           if l[:1].isupper() and "=" in l]
    seed = [l for l in open(f"{prep}/seed/seed.kaem").read().splitlines()
            if l.split("=")[0] in ("NYACC_PKG", "MES_PKG", "MES_PREFIX")]
    assert len(seed) == 3
    for line in ("cd build", "cd ${TCC_PKG}"):
        assert k.count(line) == 1, line
    out = ["set -ex", "ARCH=x86", "ARCH_DIR=x86"] + env + seed
    out += ["pkg=tcc-0.9.26", "cd /steps/tcc-0.9.26"]
    out += cut(k, "# Vars", "# Check tarball checksums")
    out += ["cd build"]
    out += cut(k, "cd ${TCC_PKG}",
               "${MES} --no-auto-compile -e main ${BINDIR}/mescc.scm -- \\")
    out += cut(k, "# Install", "# Checksums")
    out += ["hex0-export /dev/hda " + " ".join(EXPORT)]
    return "\n".join(out) + "\n"


def main():
    prep, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    with open(f"{out}/hex0-handoff.kaem", "w") as f:
        f.write(script(prep))
    files = []
    for d in (f"{BUILD}/{TCC_PKG}", f"{BUILD}/mes-0.28", "/usr/include/mes"):
        for dp, dns, fns in os.walk(prep + d):
            dns.sort()
            for n in sorted(fns):
                p = os.path.join(dp, n)
                if not os.path.islink(p) and os.path.isfile(p):
                    files.append(p[len(prep):])
    files += MADE
    dirs = {"/tmp", "/dev"}
    for p in files:
        d = os.path.dirname(p)
        while d != "/":
            dirs.add(d)
            d = os.path.dirname(d)
    with open(f"{out}/hex0-handoff.list", "w") as f:
        for d in sorted(dirs):
            f.write(f"d {d}\n")
        for p in files:
            f.write(f"f {p}\n")
        f.write(f"f /{out}/hex0-handoff.kaem /kaem.run\n")
        f.write("x /usr/bin/kaem --verbose\n")
    print(f"hex0-handoff-stream: {len(dirs)} directories, {len(files) + 1} files")


main()
