#!/usr/bin/env python3
"""Write K0's boot image for the K1 run.  mkboot.py OUT

Only what seed Forth needs to build K1 (k1/direct_inputs.py's k0_tree()),
with init reading tools/k1-direct-start.fth and tools/k1-direct-boot.recipe
appended to tools/k1-direct.recipe, so K0 builds K1 with the Forth compiler,
tools/obj-asm.fth and the Forth linker, then starts it."""
import pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "k0"))
sys.path.insert(0, str(ROOT / "k1"))
import mkfs
from direct_inputs import k0_tree
if len(sys.argv) != 2:
    sys.exit("usage: mkboot.py OUT")
extra = {"tools/k1-direct.recipe": (ROOT / "tools/k1-direct.recipe").read_bytes()
         + (ROOT / "tools/k1-direct-boot.recipe").read_bytes()}
mkfs.write(sys.argv[1], k0_tree(), extra, stdin="tools/k1-direct-start.fth")
