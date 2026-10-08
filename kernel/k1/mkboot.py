#!/usr/bin/env python3
"""Write K0's boot image for the K1 run.  mkboot.py OUT

Only what seed Forth needs to build K1 (kernel/k1/direct_inputs.py's k0_tree()),
with init reading kernel/tools/k1-direct-start.fth and kernel/tools/k1-direct-boot.recipe
appended to kernel/tools/k1-direct.recipe, so K0 builds K1 with the Forth compiler,
kernel/tools/obj-asm.fth and the Forth linker, then starts it."""
import pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "kernel/k0"))
sys.path.insert(0, str(ROOT / "kernel/k1"))
import mkfs
from direct_inputs import k0_tree
if len(sys.argv) != 2:
    sys.exit("usage: mkboot.py OUT")
extra = {"kernel/tools/k1-direct.recipe": (ROOT / "kernel/tools/k1-direct.recipe").read_bytes()
         + (ROOT / "kernel/tools/k1-direct-boot.recipe").read_bytes()}
mkfs.write(sys.argv[1], k0_tree(), extra, stdin="kernel/tools/k1-direct-start.fth")
