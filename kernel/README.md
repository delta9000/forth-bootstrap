# kernel/

The two kernels the QEMU run boots.  `k0/` is K0 (`k0.hex0`,
1,276 bytes): a Multiboot image that enters 64-bit long mode on the page
tables its boot image brings (`kernel/k0/mkfs.py`), and then runs static Linux
x86-64 programs one at a time, in ring 0, over a file table held in RAM.
It answers 19 Linux system calls (read, write, open, close, lstat, lseek,
mmap, brk, dup2, fork, execve, exit, wait4, getcwd, chdir, rename, mkdir,
unlink, chmod) and one of its own, 248, which writes a file to the IDE
disk; every other number returns -38.  `fork` copies the parent's state,
stack and image aside and runs the child to its exit, and writing to the
console is one `out` per byte to COM1.  K0 was written directly in hex0,
from a behavioural specification (`kernel/k0/SPEC.md`), by an AI model under the
owner's direction, without sight of any earlier K0, and it is checked by
independent assemblers: every byte line carries its instruction as a
comment, and GNU as and llvm-mc must both turn the comments back into the
same bytes.

`tools/` holds what seed Forth uses to build K1 under K0: the
recipe runner (`amd64-runner.c`, compiled by the Forth compiler), the
object writer for K1's assembly, and the recipes.  `k1/` is K1, a small C
kernel that runs static Linux x86-64 programs as processes, runs the whole
chain, and hands the machine to the Linux kernel the chain built; its
README describes the runs.  Start with `k0/k0.hex0`, then `k1/README.md`.
Checks: `kernel/k1/tests/direct-build-check.sh` (`./check-all.sh` step
08); `kernel/k0/check.sh` assembles every comment in `k0.hex0` with GNU as
(and llvm-mc) against its bytes (`kernel/k0/asm-check.py`) and checks
`tests/pins/k0.sha256` (step 09);
`kernel/k1/run-chain.sh --direct-smoke` and `--direct-linux` are the
opt-in runs (`CHECK_K1=smoke|linux`).
