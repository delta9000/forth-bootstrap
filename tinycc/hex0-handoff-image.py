#!/usr/bin/env python3
"""Write K0's boot image for boot 1 of the hex0 hand-off.

    python3 -I tinycc/hex0-handoff-image.py OUT PREP

OUT is the memory image kernel/k0/mkfs.py writes.  PREP is the root that
`tinycc/lb-replay.sh --prepare` left: live-bootstrap's tcc-0.9.26 and
mes-0.28 trees unpacked and simple-patched under
/steps/tcc-0.9.26/build/, and mes-0.28's headers in /usr/include/mes.

The image holds, at the paths the guest uses:
  - what seed Forth needs to build the recipe runner
    (kernel/tools/k1-direct-start.fth, init's stdin) and the first tcc
    (the compiler layers, tinycc/tcc-compile.fth, build-out/tcc-sources/
    from `tinycc/build-first-tcc.sh --prepare`);
  - tinycc/hex0-handoff.recipe, under the name the launcher runs,
    kernel/tools/k1-direct.recipe;
  - live-bootstrap's trees from PREP: steps/tcc-0.9.26/build/<tcc>/,
    steps/tcc-0.9.26/build/mes-0.28/ and usr/include/mes/.  Symbolic links
    are left out, as live-bootstrap's `untar --non-strict` leaves them out;
  - the sources of the i386 programs boot 2 runs: kaem
    (vendor/mescc-tools/Kaem), cp, chmod, match and rm
    (vendor/stage0-posix/mescc-tools-extra) and tinycc/hex0-export.c;
  - what boot 1 writes onto builder-hex0's disk: the two builder-hex0
    stages (BH, below), stage0-posix's AMD64 hex0-seed to assemble stage 1,
    and boot 2's script and stream list from tinycc/hex0-handoff-stream.py.
"""
import os, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "kernel/k0"))
import mkfs

LAYERS = ["forth/010-lib.fth"] + [
    f"cc/{n}" for n in sorted(os.listdir(ROOT / "cc"))
    if n.endswith(".fth") and n[:3] in (
        "020 030 040 050 060 070 080 090 100 110 112 114 115 116 117 118 119 120"
        .split())]
REPO = LAYERS + [
    "kernel/tools/k1-direct-start.fth",
    "kernel/tools/amd64-syscalls.fth",
    "kernel/tools/amd64-runner.c",
    "tinycc/tcc-compile.fth",
    "tinycc/hex0-export.c",
    "tinycc/hex0-disk.c",
    "vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed",
    "vendor/mescc-tools/Kaem/kaem.c",
    "vendor/mescc-tools/Kaem/kaem.h",
    "vendor/mescc-tools/Kaem/kaem_globals.c",
    "vendor/mescc-tools/Kaem/kaem_globals.h",
    "vendor/mescc-tools/Kaem/variable.c",
    "vendor/mescc-tools/M2libc/bootstrappable.c",
    "vendor/mescc-tools/M2libc/bootstrappable.h",
] + [f"vendor/stage0-posix/mescc-tools-extra/{n}" for n in (
    "cp.c", "chmod.c", "match.c", "rm.c",
    "M2libc/bootstrappable.c", "M2libc/bootstrappable.h")]
TCC_PKG = "tcc-0.9.26-1147-gee75a10c"
BH = "build-out/tinycc-inputs/builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a"


def tree(files, host_dir, image_dir):
    """Every regular file under host_dir, named under image_dir."""
    for dp, dns, fns in os.walk(host_dir):
        dns.sort()
        for f in sorted(fns):
            p = os.path.join(dp, f)
            if os.path.islink(p) or not os.path.isfile(p):
                continue
            files[os.path.join(image_dir, os.path.relpath(p, host_dir))] = p


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: hex0-handoff-image.py OUT PREP")
    out, prep = sys.argv[1], os.path.abspath(sys.argv[2])
    os.chdir(ROOT)
    files = {f: f for f in REPO}
    tree(files, "build-out/tcc-sources", "build-out/tcc-sources")
    for d in (f"steps/tcc-0.9.26/build/{TCC_PKG}", "steps/tcc-0.9.26/build/mes-0.28",
              "usr/include/mes"):
        tree(files, os.path.join(prep, d), d)
    for n in ("builder-hex0-x86-stage1.hex0", "builder-hex0-x86-stage2.hex0"):
        files[f"{BH}/{n}"] = f"{BH}/{n}"
    for n in ("hex0-handoff.kaem", "hex0-handoff.list"):
        files[f"build-out/tinycc/hex0-handoff/{n}"] = f"build-out/tinycc/hex0-handoff/{n}"
    recipe = (ROOT / "tinycc/hex0-handoff.recipe").read_bytes()
    mkfs.write(out, files, {"kernel/tools/k1-direct.recipe": recipe},
               stdin="kernel/tools/k1-direct-start.fth")


main()
