# K1

K1 is a small kernel in C that runs ordinary static Linux x86-64 programs
as real processes, imports the route's sources and archives from a disk,
runs the whole chain from `hex0-seed` to GCC 10.5.0 and Linux 7.2.8, and
finally hands the machine to the Linux kernel the chain built.  Nothing
but seed Forth compiles it: K0 (1,313 bytes of hex0, `kernel/k0/`) runs
seed Forth, which builds K1 with its own C compiler, assembler writer and
linker, and K0 then starts it.

```sh
./seed-forth < kernel/tools/k1-direct-start.fth   # build K1 on the host: build-out/k1-direct/k1
sh kernel/k1/tests/direct-build-check.sh           # the same, audited (see Tests)
kernel/k1/run-chain.sh --direct-smoke              # K0 -> K1 -> seed-cc, seed-ar, kaem under K1 (3 GiB, under a minute)
kernel/k1/run-chain.sh --direct                    # ... then the plumbing stages to bash 2.05b (8 GiB)
kernel/k1/run-chain.sh --direct-linux              # ... then on to Linux and kexec (24 GiB, 1 h 38 min)
```

## How seed Forth builds K1

`./seed-forth < kernel/tools/k1-direct-start.fth` builds the recipe runner
(`kernel/tools/amd64-runner.c`, compiled by the Forth compiler) and runs
`kernel/tools/k1-direct.recipe` with it.  The seed is the only program
that runs besides that runner:

- each C file is compiled by the Forth compiler with the layers, arena and
  driver words of `seed-cc -nostdinc -c` (`kernel/k1/boot/unit.fth`); the
  objects are byte-identical to seed-cc's;
- `k1-asm.fth` holds K1's assembly (entry from K0, SYSCALL entry and exit,
  the context switch, exception stubs, port I/O, MSRs, descriptor tables)
  as hex bytes, one instruction per line with the instruction as a
  comment, plus labels and relocations; `kernel/tools/obj-asm.fth` writes
  it as an object on the compiler's object writer (`cc/081-cc-object.fth`).
  The C files have no inline assembly (each privileged instruction is a
  small function in `k1-asm.fth`);
- the Forth linker (`cc/140-cc-link.fth`) links them at
  0x200000 (`kernel/k1/boot/link.fth`).

K0 lacks `stat`, `fstat`, `munmap` and `getpid`, which the object writer
and the linker use; `kernel/k1/boot/k0-syscalls.fth` retries those calls
with what K0 has when they return ENOSYS, and changes nothing on Linux.
On the host the whole build takes under a second.  K1 is 221,672 bytes,
sha256 `f90229b116c5a3b5...`.

## The runs

`kernel/k1/run-chain.sh` assembles K0 from `kernel/k0/k0.hex0` with
`hex0-seed`, writes two images and starts QEMU (KVM if `/dev/kvm` is
writable):

- `kernel/k1/mkboot.py` writes K0's memory image: the files of
  `direct_inputs.py`'s `k0_tree()`, `seed-forth`, and
  `kernel/tools/k1-direct.recipe` followed by
  `kernel/tools/k1-direct-boot.recipe`, which starts the K1 just built;
- `kernel/k1/mkdisk.py` writes K1's input disk: the files of
  `direct_inputs.py`'s `k1_tree()` (an explicit list of the repository
  files and `MANIFEST.sha256` archives the guest reads), `hex0-seed` as the
  only executable, `/k1.args` and `/k1.recipe`.

`/k1.recipe` is one of three:

- `direct-smoke.recipe` (`--direct-smoke`): hex0-seed builds seed-forth,
  seed Forth builds seed-cc and seed-ar (`cc/driver/seed-cc-start.fth`),
  seed-cc builds kaem, and kaem runs `direct-smoke.kaem`: a program built
  from a seed-ar archive checks the runtime's system calls
  (`tests/direct-smoke.c`: files, directories, `/proc/self/exe`,
  fork/exec/wait, pipes, large malloc and mmap, a page fault with DF set,
  clocks, signals), and two stage0-posix tools run;
- `direct.recipe` (`--direct`): the same, then `chain/plumbing/stage1.kaem`,
  `stage2.kaem`, `lexers.kaem` and `bash.kaem`;
- `direct.recipe` plus `direct-linux.recipe` (`--direct-linux`, the
  default): after bash 2.05b, `direct-full.sh` runs
  `chain/gcc-direct/chain.sh` (binutils 2.30, stage C, stage D to the GCC
  4.0.4 fixed point) and `chain/gcc-direct/late-tools.sh`;
  `chain/ladder/stage10-direct.sh` installs the late tools as `/usr`;
  `chain/ladder/stage11.sh` runs gcc64's bridge and stages 6-10;
  `chain/ladder/stage12.sh` builds Linux 7.2.8 with an initramfs holding
  `chain/ladder/init.c`; and `chain/ladder/finish.sh` tars the results to
  the output disk and kexecs into the new kernel.

The wrapper checks QEMU's exit status (1 for the first two, 85 after
Linux) and the guest's markers in `serial.log`; for `--direct-linux` they
end with `init: hello from a Linux kernel built from hex0 and seed-forth`
and `init: Linux version 7.2.8`.  The output disk (`out.img`) is a tar of
`build-out/linux` (the bzImage, its config and init), the stage logs and
reports, and `build-out/g64/logs/hashes.txt`.

`JOBS=N` is passed into the guest's make runs (the recipe runner starts
programs with an empty environment, so `mkdisk.py --jobs` writes it into
the recipe); `K1_MEM` sets the guest RAM and `K1_DISKS` the image
directory.  K1 keeps the whole build file system in guest RAM; 24 GiB is
what the full run has used, not a measured minimum.  `K1_RAM_FILE` backs
guest RAM with a sparse file instead, for a host without that much free
memory; on an SSD a full run writes terabytes through it.

K1 has one CPU, so `JOBS=2` only keeps it busy while another job waits on
I/O; the run takes longer than the same chain on a many-core host.

Result (2026-10-08, `JOBS=2 K1_MEM=24G`, QEMU with KVM): 1 h 38 min from
hex0 to the Linux greeting; stage D at its fixed point under K1 (54 files,
0 differ); all 31 `chain/gcc64/HASHES` pins as pinned; the bzImage
1,278,976 bytes, CRC-32 `0014e6cc`, sha256 `881e96ad05da8e18...`.  The
run's reports and serial log are in
[results/k1-2026-10-08/](../../results/k1-2026-10-08/).

## Boot

K0 knows nothing about K1: the boot recipe has K0's runner exec `k1`
like any program (ring 0, K0's identity map, rsp at an argv block), and
K1 then:

1. reads the e820 map from QEMU's fw_cfg (`etc/e820`);
2. builds its own page tables: the low 4 MiB identity-mapped,
   supervisor-only, for K1's image (linked at 0x200000), and all physical
   memory at `KBASE` = 0xFFFF800000000000 with 1 GiB pages;
3. loads its GDT (kernel 0x10/0x18, user 0x2B/0x33, TSS 0x38), IDT, TSS
   and the SYSCALL MSRs (STAR's sysret base is 0x23 so SS gets RPL 3),
   and programs the 8259 PICs so that only the PIT (IRQ 0) is unmasked;
4. calibrates the TSC against PIT channel 2 and reads the CMOS clock;
5. imports the input disk (hda) into its RAM file system, and K0's file
   table under `/k0/`, then gives K0's image memory to its page
   allocator;
6. starts init (pid 1) from `/k1.args` (`[-v] [-i stdin] prog args...`,
   one per line): here `/k0/build-out/amd64-runner --recipe /k1.recipe`,
   with stdout and stderr on the serial console.  When init exits, QEMU
   exits with its status (signals as 128+n).

## Design

- **Memory.** Physical pages come from a free list, else a bump pointer
  over the e820 RAM, so RAM never touched is never written and KVM never
  backs it.  `kmalloc` has power-of-two classes up to a page; larger
  requests take contiguous pages from the bump area.
- **Address spaces.** One 4-level page table per process.  The upper half
  is the shared direct map; PD entries 0-1 map K1 (so user programs start
  at 0x400000, as static ELFs do).  User memory is demand-zero within
  VMAs (image, brk, mmap, a 64 MiB stack below 0x7FFFFFFFF000), each
  with its protection; `mprotect` splits VMAs and rewrites PTEs, and a
  write to a read-only page is a fault.  mmap addresses grow down from
  0x7F0000000000, stepping under any mapping in the way; a page-aligned
  hint is honoured when its range is free (GCC's PCH files need their
  address back), and `brk` refuses to grow over a mapping, so musl's
  malloc falls back to mmap.  fork copies every present page — no
  copy-on-write.
- **Processes.** Ring 3, entered and left through SYSCALL/SYSRET;
  exceptions use the IDT and IRETQ, and exception entry clears DF first
  (user code may be inside musl's backward `memmove`).  Each process has a
  32 KiB kernel stack with its user registers (`struct tframe`) on top.  A
  process runs until it blocks (wait4, a pipe, poll, a vfork child,
  pause), exits, or is preempted by the PIT tick (100 Hz, PIC vectors
  32-47) while in user mode; `make -j` and alarm-driven configure probes
  need both.  SSE state is saved with FXSAVE on every switch; FS base per
  process (musl's TLS).
- **Files.** A RAM file system: regular files in a 3-level radix tree of
  pages (sparse holes read zero), directories as a creation-ordered list
  plus a hash table past 16 entries, symlinks, hard links, modes,
  ownership, ns timestamps (make needs mtimes), `/dev/{null,zero,tty,
  console,random,urandom}`, `/tmp` (1777), FIFOs (`mknod`), and
  `/proc/self/fd/N` and `/proc/self/maps`.  An inode is freed when it has
  no names and no open files.
- **Disks.** `ata.c` drives QEMU's primary IDE channel by PIO (LBA48,
  `rep insw`/`outsw`, no interrupts).  hda holds the starting tree as an
  archive `mkdisk.py` writes, imported at boot; hdb is `/dev/hdb`, which
  `chain/ladder/finish.sh` tars its results to for the host to read back.
- **Pipes.** 64 KiB rings with blocking reads and writes; writing with no
  readers raises SIGPIPE (so `yes | head` ends).
- **Signals.** sigaction, sigprocmask, kill/tkill/tgkill, pause,
  sigsuspend, default actions (SIGCHLD and friends ignored, others
  terminate), handlers via an on-stack frame and the sa_restorer that
  musl supplies, SA_RESTART (an interrupted blocking call is re-executed
  by backing up rip), SA_NODEFER, SA_RESETHAND, `sigaltstack`.  Signals
  are delivered on return from a syscall or from an interrupt (with every
  register restored); a user page fault or other trap is delivered as
  SIGSEGV/SIGILL/SIGFPE to a handler if there is one.  `alarm`,
  `setitimer` and `getitimer` (ITIMER_REAL) run off the tick.
- **exec.** Static ELF only (ET_EXEC, or ET_DYN loaded at
  0x555555554000); PT_INTERP is ENOEXEC.  `#!` scripts with one optional
  argument, nested up to 4.  The auxv carries AT_PHDR, AT_ENTRY,
  AT_RANDOM, AT_EXECFN and friends.  A segment whose p_filesz runs past
  the end of the file is zero-filled, as Linux's mmap would.
- **Linux hand-off.** `reboot(2)` with `LINUX_REBOOT_CMD_KEXEC` loads
  `/boot/bzImage` (64-bit boot protocol ≥ 2.12, XLF_KERNEL_64) at an
  address aligned to its `kernel_alignment` and at least its
  `pref_address`, with room for `init_size`; builds boot_params from the
  bzImage's setup header, the fw_cfg e820 map, `/boot/cmdline` and
  `/boot/initrd.cpio`; switches to page tables identity-mapping the first
  512 GiB; and jumps to load+0x200 with rsi = &boot_params.  K1's GDT
  already has the flat 0x10/0x18 segments the protocol requires.

## Linux ABI shortcuts

Everything here is deliberate and holds for the bootstrap's workloads;
each is a place K1 differs from Linux.

- One CPU; only the timer interrupt.  `nanosleep` and timed
  `poll`/`select` spin, yielding.
- No permission checks (everything runs as root, uid 0); `access(X_OK)`
  checks only that some x bit is set.
- File-backed `mmap` is a private copy; `MAP_SHARED` writes are not
  written back.  `PROT_EXEC` is accepted and not enforced (no NX bit).
- `clone` supports fork, vfork and `CLONE_VM|CLONE_VFORK` (musl's
  posix_spawn); `CLONE_THREAD` is EINVAL, `clone3` ENOSYS; `futex` returns
  0 (one thread per process).
- A bad user pointer faults in the kernel and kills the process with
  SIGSEGV instead of returning EFAULT.
- `/proc` is only `self/fd`, `self/maps` and `self/exe` (the image's
  canonical path, which seed-cc locates its tree by); no sockets
  (EAFNOSUPPORT), no ttys (`ioctl` is ENOTTY, so every program sees a
  non-interactive stdin).  `getdents64` lists `.`, `..`, then names in
  creation order.
- `statx`, `copy_file_range`, `sendfile`, `fallocate`, `rseq`, `waitid`
  are ENOSYS (musl and coreutils fall back).  Any syscall not listed in
  `sys.c` is ENOSYS and is reported once on the console.

## Files

| File | Lines | What |
|---|---:|---|
| `k1-asm.fth` | 470 | the assembly, as bytes with the instructions as comments |
| `k1.h` | 341 | shared declarations |
| `main.c` | 531 | boot: memory primitives, kprintf, TSC/RTC, fw_cfg e820, GDT/IDT/TSS/MSRs, kernel page tables, traps |
| `mm.c` | 599 | physical pages, kmalloc, page tables, VMAs, fork copy, mmap/munmap/mremap/brk |
| `fs.c` | 719 | inodes, radix data, directories, path walk, pipes, FIFOs, devices, `/proc/self`, K0 import |
| `ata.c` | 207 | IDE PIO disks, the hda archive import |
| `proc.c` | 778 | processes, scheduler, fork/clone, exec (ELF, `#!`), exit/wait, signals, init |
| `sys.c` | 1,208 | the syscall table |
| `linux.c` | 112 | the bzImage hand-off |
| `boot/` | | the Forth drivers that compile and link K1 |
| `direct*.recipe`, `direct-smoke.kaem`, `direct-full.sh` | | the guest's recipes |
| `run-chain.sh`, `mkboot.py`, `mkdisk.py`, `direct_inputs.py`, `mkram.py` | | the host side of a run |
| `tests/` | | the checks below |

## Tests

- `sh kernel/k1/tests/direct-build-check.sh` (about ten seconds; needs strace
  and GNU as): `kernel/tools/k1-direct.recipe` lists exactly the compiler
  layers seed-cc uses; the K1 build under strace runs only the seed and
  the runner; each C object equals `seed-cc -nostdinc -c`'s; `k1-asm.fth`'s
  object equals GNU as on its own comments (`tests/asm-check.py`); and K1
  is a static ELF at 0x200000 whose image ends below 4 MiB.
- `kernel/k1/run-chain.sh --direct-smoke`: K0 builds K1, K1 runs the
  smoke recipe and `tests/direct-smoke.c`'s 26 checks, among them a demand
  page fault taken with DF set, which fails on a K1 without the `cld`.
- `kernel/k1/run-chain.sh --direct-linux`: the full run, above.
