# kernel/

The two kernels the QEMU run boots.  `k0/` is K0, 1,313 bytes of hex0
(`k0.hex0`, assembled by `hex0-seed`; `k0.asm` is the same program as
commented NASM) that enters long mode and runs one program at a time:
seed Forth.  `tools/` holds what seed Forth uses to build K1 under K0: the
recipe runner (`amd64-runner.c`, compiled by the Forth compiler), the
object writer for K1's assembly, and the recipes.  `k1/` is K1, a small C
kernel that runs static Linux x86-64 programs as processes, runs the whole
chain, and hands the machine to the Linux kernel the chain built; its
README describes the runs.  Start with `k0/k0.asm`, then `k1/README.md`.
Checks: `kernel/k1/tests/direct-build-check.sh` (`./check-all.sh` step
07); `kernel/k0/check.sh` compares K0 with NASM's build (needs nasm);
`kernel/k1/run-chain.sh --direct-smoke` and `--direct-linux` are the
opt-in runs (`CHECK_K1=smoke|linux`).
