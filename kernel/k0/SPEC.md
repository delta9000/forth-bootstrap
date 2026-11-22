# K0-SPEC: the bootstrap kernel, `kernel/k0/k0.hex0`

Specification for a clean-room rewrite. It describes what K0 must do and
every interface another file depends on. It does not describe how the
present K0 does it. Paths are relative to the repository root; `file:line`
citations name the dependent that forces a detail.

Conventions: MUST marks something a dependent or a check relies on. FREE
marks a choice the implementer owns. All numbers a program passes to K0, and
all addresses K0 handles, are below 4 GiB.

## 1. What K0 is

A flat binary written as commented hex0, assembled by stage0-posix's
`hex0-seed` into `k0.bin` (`kernel/k1/run-chain.sh:33`,
`tests/tinycc/hex0-handoff-check.sh:111`, `kernel/k0/check.sh:12`). QEMU
loads it as a multiboot kernel. K0 switches the CPU to 64-bit long mode and
then runs static Linux x86-64 programs, one at a time, in ring 0, giving
them 19 Linux system calls and one of its own over a file system held in
RAM. It has no interrupts, no timer, no user mode and no memory protection.

It has two jobs:

- **The K1 route** (`kernel/k1/run-chain.sh`): K0 runs `seed-forth` on
  `kernel/tools/k1-direct-start.fth`. That builds a recipe runner
  (`kernel/tools/amd64-runner.c`) and runs
  `kernel/tools/k1-direct.recipe`, which builds the K1 kernel and then
  executes it as an ordinary program. K1 takes the machine over and never
  returns (section 9).
- **Boot 1 of the hex0 hand-off** (`tests/tinycc/hex0-handoff-check.sh`):
  the same start, with `tinycc/hex0-handoff.recipe` as the recipe. Seed
  Forth builds the first tcc, the first tcc builds more programs, and
  `tinycc/hex0-disk.c` writes a disk image to the IDE drive through K0's
  own call 248. Then the top-level program exits and QEMU stops.

Programs that run under K0, all static ELF64, all entered with the
`syscall` instruction as their only way into the kernel:

| program | load range | notes |
|---|---|---|
| `seed-forth` | 0x400000, memsz 16 MiB | one RWX segment |
| `amd64-runner`, `hex0-disk` (Forth compiler output) | 0x400000 | one RWX segment; `malloc` is one 256 MiB anonymous `mmap` (`cc/116-cc-prog.fth:818-853`) |
| the first tcc, as `/usr/bin/tcc-mes` | 0x400000 | one RWX segment; Mes libc: heap by `brk` |
| `hex0-seed` (stage0-posix, 229 bytes) | 0x600000 | one segment, flags X only, filesz = memsz |
| K1 (`build-out/k1-direct/k1`) | 0x200000 to below 0x400000 | two segments (R X, then RW with bss), entry 0x201000 (`kernel/k1/tests/direct-build-check.sh:59-60`) |

## 2. Boot

### 2.1 The QEMU command lines

K0 MUST work under both, unchanged:

```
qemu-system-x86_64 [-accel kvm -cpu host | -cpu max] -m 3G -display none -monitor none \
    -serial file:serial.log -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x01 \
    -kernel k0.bin \
    -device loader,file=boot.img,addr=0x50000000,force-raw=on \
    -drive file=in.img,format=raw,if=ide,index=0 \
    -drive file=out.img,format=raw,if=ide,index=1
```
(`kernel/k1/run-chain.sh:40-56`; `-cpu max` is TCG, used when `/dev/kvm`
is not writable; memory is 3G, 8G or 24G by mode.)

```
qemu-system-x86_64 -accel kvm -cpu host -m 4G -display none -monitor none \
    -serial file:boot1.log -no-reboot \
    -device isa-debug-exit,iobase=0xf4,iosize=0x01 \
    -kernel k0.bin \
    -device loader,file=boot1.img,addr=0x50000000,force-raw=on \
    -drive file=disk.img,format=raw,if=ide,index=0
```
(`tests/tinycc/hex0-handoff-check.sh:117-122`.)

What K0 may assume from them: one CPU; at least 3 GiB of RAM, with
physical 1 MiB to 0xC0000000 all RAM; 1 GiB pages available; the boot image
(section 6) already in memory at 0x50000000 when K0 starts; COM1 at I/O
port 0x3F8; an IDE primary master at ports 0x1F0 to 0x1F7; the
isa-debug-exit device at port 0xF4. RAM that neither QEMU's loaders nor
K0 has written reads as zero.

Known emulator constraint: QEMU 8.2's TCG aborts on `rep outsb` in K0, so
port output MUST NOT use the repeated string-output instructions; write
one byte (or word) at a time.

### 2.2 The multiboot header

QEMU's `-kernel` accepts `k0.bin` as a Multiboot 1 image that is not an
ELF, so the header MUST use the address fields ("a.out kludge"):

- within the first 8192 bytes, 4-byte aligned: magic 0x1BADB002, flags
  with bit 16 set and no bit that asks for something QEMU must provide
  (use exactly 0x00010000), and a checksum making the three sum to 0
  modulo 2^32;
- then `header_addr`, `load_addr`, `load_end_addr`, `bss_end_addr`,
  `entry_addr`, consistent with the file being loaded whole at its load
  address.

The load address MUST be 0x100000: `kernel/k0/asm-check.py:67` takes file
offset N as address 0x100000 + N. The whole of K0, code and any data it
keeps in its own image, MUST stay below 0x200000, where K1 is loaded
(`kernel/k1/boot/link.fth:3`).

### 2.3 Entry state and the switch to long mode

On entry (Multiboot): 32-bit protected mode, paging off, interrupts off,
A20 on, flat code and data segments, no usable stack. K0 MUST reach this
state before running any program:

- 64-bit long mode, ring 0, interrupts disabled and never enabled;
- paging with physical addresses 0 to 4 GiB identity-mapped, writable and
  executable. The boot image supplies ready page tables for exactly that
  (section 6.1); using them is the intended way, building others is FREE;
- the `syscall` instruction enabled and directed at K0's entry point
  (EFER.SCE, the STAR and LSTAR MSRs);
- SSE usable without faulting: CR4.OSFXSR and OSXMMEXCPT set, CR0.MP set,
  CR0.EM clear. I could not prove that any program under K0 executes an
  SSE instruction, nor that none does, so this is required.

Nothing outside K0 depends on its GDT, its selector values, or its kernel
stack: K1 loads its own tables immediately (`kernel/k1/main.c:249-272`),
and no program reads a segment register. They are FREE, with one caution:
the arrangement has to work under KVM (`-cpu host`) and under TCG
(`-cpu max`) alike, and only running both tells. No IDT is needed; a CPU
exception may simply reset the machine (`-no-reboot` then ends QEMU).

After setup K0 starts the first program: `execve` of the path and argument
vector the boot image holds (section 6.1), with the file descriptors and
working directory the image holds.

## 3. Processes

### 3.1 One program at a time

Exactly one program runs. It runs in ring 0 with K0's page tables and
full access to memory and I/O ports. This is an interface, not a
shortcut: K1 is started as a program and immediately executes privileged
instructions (`kernel/k1/main.c:1-6`, `kernel/k1/README.md:108-109`).

### 3.2 Loading a program: `execve`

The file is an ELF64 executable. K0 MUST handle:

- program headers at file offset 64 (`e_phoff` is 64 in every program),
  56 bytes each, `e_phnum` of them (1 or 2);
- every program header a `PT_LOAD`, in ascending address order. For each:
  copy `p_filesz` bytes from file offset `p_offset` to address `p_vaddr`,
  then zero bytes up to `p_vaddr + p_memsz`. `p_vaddr` and `p_offset`
  need not be page-aligned, `p_flags` is ignored, and segments are not
  rounded to pages;
- load addresses 0x200000, 0x400000 and 0x600000 (table in section 1);
- entry at `e_entry`.

K0 need not validate the file. The program break (section 4, `brk`) starts
at the end of the last segment, exactly at `p_vaddr + p_memsz`, not
rounded.

The new program starts with:

- every general register zero, RFLAGS with interrupts disabled and the
  direction flag clear;
- rsp 16-byte aligned and pointing at the System V initial stack: `argc` (8 bytes), `argc`
  pointers to the argument strings, a null pointer, a null pointer ending
  an empty environment, and an `AT_NULL` auxiliary entry (two zero
  quadwords, of which one is the minimum a reader needs). The strings are
  copies. Programs read `argc` and `argv` from rsp (`hex0-seed`, the
  compiled C programs' entry stub, K1: `kernel/k1/k1-asm.fth:19`,
  `kernel/k1/main.c:449-457`); none reads the environment or auxiliary
  vector, but a C library's start code may compute `envp`'s address from
  `argc`, so the two null terminators MUST be there;
- a stack of at least 8 MiB below rsp, all of it reading as zero. Linux's
  fresh stack pages are zero, and `tcc -g` reads a stack buffer it never
  wrote (its `getcwd` buffer), whose content reaches its output.
  K0 MUST zero the region on every `execve`, because stacks are reused;
- memory above the segments' end available for `brk`: the first tcc
  grows its break by up to 19.5 MiB (`kernel/k1/I386.md`), and seed
  Forth's image alone is 16 MiB;
- open file descriptors and the working directory unchanged from the
  caller.

`execve(path, argv, envp)`: `envp` is ignored. `argv` is read up to its
null terminator; the longest command line in use is about 1.2 KiB in 50
arguments, and 64 KiB for the whole block is ample. If the path does not
resolve the call returns -2 and the caller continues
(`kernel/tools/amd64-runner.c:552-553`). On success it does not return.
The path and the argument strings live in the caller's image, heap or
stack, so K0 MUST have copied them out before it overwrites the old image
and zeroes the stack.

Where the stack lives is FREE, subject to: inside the identity map and RAM, clear of images and their
`brk` growth from 0x200000 upward, clear of the boot image and file heap
at 0x50000000 upward and of the `mmap` area at 0x80000000 upward.

### 3.3 `fork`, `exit`, `wait4`

Every fork in the chain has the same shape: the parent forks and at once
waits; the child redirects file descriptors, calls `execve`, and the new
program runs to its exit (`kernel/tools/k1-direct-start.fth:128-141`,
`kernel/tools/amd64-runner.c:521-560`). K0 MUST give exactly that:

- `fork` returns 0 and execution continues as the child, immediately. The
  parent is suspended.
- When the child (or the program it became) calls `exit`, the parent
  resumes as if its `fork` call now returned the child's pid. These are
  as they were when it called `fork`: its registers; its stack, which
  means everything from 128 bytes below its rsp (the System V red zone)
  up to and including its argument block and argument strings; its loaded
  image including memory obtained with `brk`; its file descriptor table;
  its working directory.
- Memory the parent obtained with `mmap` stays intact at the same
  addresses for the child's whole lifetime, and whatever the child or its
  successor program maps is disjoint from it. The runner's entire `malloc`
  heap is one such mapping (`cc/116-cc-prog.fth:818-853`).
- Changes the child made to the file system persist.
- The pid is a positive number, different for each fork.
- `wait4(pid, status, options, rusage)` after that returns the pid of the
  last child that exited and stores a 32-bit status at `status`:
  `(exit code & 0xFF) << 8`, so the low 7 bits are 0. The `pid`,
  `options` and `rusage` arguments are ignored. The launcher compares the
  result with fork's return value and the status cell with 0
  (`kernel/tools/k1-direct-start.fth:139-141`); the runner checks
  `status & 127` and `(status >> 8) & 255`
  (`kernel/tools/amd64-runner.c:557-565`).
- Memory the child obtained with `mmap`, and whatever K0 used to keep the
  parent, MUST be released when the child exits: a run forks dozens of
  children one after another, and each compiled C program takes a 256 MiB
  mapping for its `malloc`.
- `exit(status)` with no parent suspended ends the run (section 8).

Forks nest one deep in practice (the top-level program forks a child that
does not fork). Support arbitrary nesting if it costs nothing; depth 1 is
the measured need.

The parent's `mmap` memory need not be protected against a child that
itself writes into it before `execve`; no child does. Whether file positions
of inherited descriptors are shared with the child or copied is FREE: no
child reads or writes an inherited file descriptor that is a file and
whose position the parent uses afterwards.

## 4. System calls

Convention: Linux x86-64. The program executes `syscall` with the number
in rax and arguments in rdi, rsi, rdx, r10, r8, r9. The result comes back
in rax; failure is a negative errno. K0 MUST preserve every other general
register across the call: rbx, rbp, rsp, rsi, rdi, rdx, r8 to r10, r12 to
r15. rcx and r11 hold what the `syscall` instruction put there (the return
address and RFLAGS), as on Linux. On return the program's RFLAGS MUST be
the value `syscall` saved in r11. Under QEMU's TCG the flags register on
entry to K0 is not that value, and no acceptance check below catches the
difference; it has to be right by construction. K0 MUST NOT
write to the caller's stack: nothing at or below the caller's rsp may
change during a call. Programs run in ring 0 on the same stack pointer,
and the System V ABI lets a program keep data in the 128 bytes below rsp.
(A search of the compiler's emitters found no use of that area; the code
of the first tcc and of Mes libc was not examined.) Seed Forth keeps
its sysvar pointer in rbx, its data stack in rbp and its return stack in
rsp across every call (`cc/020-cc-arena.fth:19-21`; `seed/SPEC.md`).

Errors used: -2 `ENOENT`, -9 `EBADF`, -17 `EEXIST`, -38 `ENOSYS`.

**Any number not listed below MUST return -38.** That is an interface:
`kernel/k1/boot/k0-syscalls.fth:20-35` detects K0 by `stat` (4), `fstat`
(5), `munmap` (11) and `getpid` (39) answering -38 and substitutes what
K0 can do; the first tcc's Mes libc calls `stat`, gets -38 and carries
on (`kernel/k1/I386.md`, "The x86-64 side"). Do not add calls. Whether a call number above 255 is compared in
full or by its low 8 bits only is FREE: no program is known to pass one.

"fd" below is a small non-negative integer; a descriptor that is not open
gives -9. Only single-digit descriptors are used; the table MUST hold at
least 16. Each open descriptor has its own file position, starting at 0.
A descriptor refers either to a file or to the console (section 7).

### 4.1 Files

| nr | call | semantics | callers |
|---|---|---|---|
| 0 | `read(fd, buf, count)` | Copies up to `count` bytes from the file at the descriptor's position, advances it, returns the number copied; 0 at or past the end. Reading the console is not used and is FREE. | seed `key`; `forth/010-lib.fth:530`; `kernel/tools/k1-direct-start.fth:109`; runner; tcc; hex0-seed; `tinycc/hex0-disk.c:73,114` |
| 1 | `write(fd, buf, count)` | File: stores `count` bytes at the position, extending the file as needed, advances the position, returns `count`. If the position is past the end, the gap reads as zero. Console: section 7; returns `count`. `count` 0 returns 0 and changes nothing, even with the position past the end: the file does not grow, as on Linux. | everything; the first tcc writes single bytes hundreds of thousands of times (`kernel/k1/I386.md`, "The x86-64 side") |
| 2 | `open(path, flags, mode)` | Resolves the path (section 5.2). Not found: with `O_CREAT` (0x40) creates an empty regular file, without it returns -2. Found: with `O_EXCL` (0x80) returns -17; with `O_TRUNC` (0x200) the file becomes empty. Returns the lowest descriptor that is not open, position 0. The access mode bits, every other flag and `mode` are ignored: every descriptor reads and writes. The parent directory need not exist (5.3). | all; flags in use: 0, 0x241 (577), `O_RDWR\|O_CREAT\|O_TRUNC` |
| 3 | `close(fd)` | Returns 0; -9 if not open. | all; the launcher treats non-zero as failure (`kernel/tools/k1-direct-start.fth:56`) |
| 6 | `lstat(path, buf)` | Not found: -2. Found: stores `st_mode` as a 16-bit value at `buf + 24`: 0x81ED (regular file, 0755) or 0x41ED (directory, 0755), and returns 0. Nothing else in `buf` need be written. | `kernel/tools/amd64-runner.c:788,989-996`; `kernel/k1/boot/k0-syscalls.fth:26` (as `stat`'s stand-in, into a buffer it zeroed) |
| 8 | `lseek(fd, offset, whence)` | whence 0: position = offset; 1: position + offset; 2: file size + offset. Returns the new position. Offsets are below 2 GiB; a small negative offset with whence 1 occurs. | `cc/140-cc-link.fth:100,103`; `tinycc/hex0-disk.c:88`; tcc |
| 33 | `dup2(old, new)` | `new` becomes open on what `old` is open on, at `old`'s position; returns `new`. -9 if `old` is not open. | `kernel/tools/k1-direct-start.fth:133` (result must be 0 for new = 0); `kernel/tools/amd64-runner.c:529-548` (result must equal `new`) |
| 79 | `getcwd(buf, size)` | Stores `/` followed by the working directory's name and a 0 byte; returns the number of bytes stored including the 0 (so 2 at the root, where the string is `/`). `size` is ignored. | `kernel/tools/amd64-runner.c:1014` (result must be > 0); the string becomes the runner's `${ROOT}` |
| 80 | `chdir(path)` | Resolves the path; not found: -2. Otherwise the working directory becomes the path's canonical form (5.2) and the result is 0. | `kernel/tools/amd64-runner.c:858` |
| 82 | `rename(old, new)` | `old` not found: -2. Otherwise, if `new` names a different existing entry, that entry is removed; then `old`'s entry takes `new`'s canonical name. Returns 0. Descriptors open on the file keep working. | `cc/081-cc-object.fth:505`; `cc/140-cc-link.fth:605`; `kernel/tools/amd64-runner.c:803,895` |
| 83 | `mkdir(path, mode)` | Path already resolves: -17. Otherwise creates a directory entry; returns 0. | `kernel/tools/k1-direct-start.fth:117-119` and `kernel/tools/amd64-runner.c:197-199` (0 and -17 both accepted) |
| 87 | `unlink(path)` | Not found: -2. Otherwise removes the entry; returns 0. | `kernel/tools/k1-direct-start.fth:126,144`; `cc/081-cc-object.fth:484`; `cc/140-cc-link.fth:590`; `kernel/tools/amd64-runner.c:246,899`; tcc (-2 is expected half the time) |
| 90 | `chmod(path, mode)` | Does nothing; returns 0, whatever the path. | `kernel/tools/k1-direct-start.fth:145`; `kernel/tools/amd64-runner.c:891` |

Storage behaviour that is part of the contract:

- Writes extend a file by any amount; a file can reach tens of megabytes
  (the hand-off's disk image) and is built by many small writes. Growth
  MUST be amortised, so that a file written one byte at a time costs
  memory and time proportional to its final size, not to its square.
- A file's bytes MUST be contiguous in memory, at one address, when K1
  imports them (section 9) and when call 248 writes them out.
- Storage of truncated, outgrown or deleted contents need not be
  reclaimed, but the whole file heap MUST stay between the boot image and
  0x80000000 (section 6.2). A design that never reclaims and at most
  doubles a file's allocation when it outgrows it is known to fit. One
  measurement: with a K0 that never reclaims and grows a file to its old
  capacity plus the write's end, the file heap ended between 0x52000000
  and 0x53000000 at the end of the hand-off's boot 1, leaving at least
  720 MiB below 0x80000000.

### 4.2 Memory

| nr | call | semantics | callers |
|---|---|---|---|
| 9 | `mmap(addr, length, prot, flags, fd, offset)` | Anonymous memory only. Returns the address of `length` bytes (rounded up to 4096) of page-aligned memory that reads as zero. Every argument except `length` is ignored. Never fails. Never freed except when a forked child exits (3.3). | `cc/020-cc-arena.fth:318,427`; `cc/140-cc-link.fth:61`; compiled C `malloc` (`cc/116-cc-prog.fth:818-853`, one 256 MiB request per program) |
| 12 | `brk(addr)` | `addr` at or below the current break, including 0: returns the current break, unchanged. Above it: the memory from the old break to `addr` is zeroed, the break becomes `addr`, and `addr` is returned. Never fails. Memory below the break belongs to the program image for `fork` (3.3). | the first tcc (Mes libc `malloc`: one `brk(0)`, then one growing call per allocation, up to about 20 MiB; `kernel/k1/I386.md`) |

There is no `munmap` (11): -38, and `kernel/k1/boot/k0-syscalls.fth:34`
turns that into success.

Capacity: the largest single mapping is 256 MiB, and a parent holding one
256 MiB mapping runs children that map another 256 MiB, or 22 MiB plus
several workspaces (`kernel/k1/boot/unit.fth:6-9`). With 3 GiB of RAM the
area from 0x80000000 to 0xC0000000 holds that. K0 need not check for
exhaustion.

### 4.3 Processes

| nr | call | semantics | callers |
|---|---|---|---|
| 57 | `fork()` | section 3.3 | `kernel/tools/k1-direct-start.fth:128`; `kernel/tools/amd64-runner.c:521` |
| 59 | `execve(path, argv, envp)` | section 3.2 | `kernel/tools/k1-direct-start.fth:136,147`; `kernel/tools/amd64-runner.c:552` |
| 60 | `exit(status)` | section 3.3 with a parent suspended, section 8 without | all |
| 61 | `wait4(pid, status, options, rusage)` | section 3.3 | `kernel/tools/k1-direct-start.fth:139`; `kernel/tools/amd64-runner.c:557` |

### 4.4 Call 248: write a file to the disk

`syscall(248, fd)`: the file open on `fd` is written to the IDE primary
master starting at sector 0, as `size / 512` whole 512-byte sectors (a
remainder is not written; the caller pads the file). The descriptor's
position plays no part. Returns 0; -9 if `fd` is not open; with fewer
than 512 bytes nothing is written and the result is 0.

The transfer is ATA PIO with 28-bit LBA through the primary channel's
ports: data 0x1F0 (16-bit words, little-endian, 256 per sector), sector
count 0x1F2, LBA bits 0-7, 8-15 and 16-23 at 0x1F3 to 0x1F5, drive select
at 0x1F6 (master, LBA mode, LBA bits 24-27), command and status at 0x1F7.
Use the WRITE SECTORS command (0x30). Honour the status register's DRQ
bit before sending data and its BSY bit before the next command. One
sector per command is enough, and no cache-flush command is needed under
QEMU. No interrupt is used or enabled.

Caller: `tinycc/hex0-disk.c:180` (a non-zero result is its failure). The
drive's content after boot 1 is compared byte for byte, through its
hashes, by `tests/tinycc/hex0-handoff-check.sh:128-153`, and boot 2 boots
from it.

## 5. The file system

### 5.1 Model

A flat table of entries held in RAM, initialised from the boot image
(section 6). An entry is a name, a type (regular file or directory) and,
for a file, its bytes. Names are whole paths without a leading `/`, such
as `forth/010-lib.fth`; the root directory is the entry with the empty
name. A directory is only a name: it has no content and no list of
children, and nothing checks that a file's parent directories exist.
There are no links, permissions, owners or times.

### 5.2 Path resolution

A path argument is turned into a canonical name by these steps, and no
others:

1. If the path begins with `/`: drop all leading `/` characters.
   Otherwise: prefix the working directory's name and, if that name is not
   empty, a `/`.
2. From the path's remaining part (not from the prefix), drop any number
   of leading `./`.
3. The rest is taken literally up to its terminating 0.

The canonical name is then compared, as a whole string, with the names of
live entries. The working directory is itself a canonical name, empty for
the root.

Examples: `/tmp/x` and `//tmp/x` give `tmp/x`; with working directory
`a/b`, `c.h` gives `a/b/c.h` and `./c.h` the same; `/` gives the empty
name, the root.

**`..` is not resolved, and `.` only as a leading `./`.** This is relied
on: `tinycc/hex0-handoff.recipe:64-66` creates a file whose literal name
is `vendor/mescc-tools/Kaem/../M2libc/bootstrappable.h`, a copy of the
real header, so that tcc's `#include "../M2libc/bootstrappable.h"` finds
it. A K0 that collapsed `..` would make that copy overwrite its own
source. The recipes avoid `cd ..` for the same reason
(`tinycc/hex0-handoff.recipe:8-10`). No path in use contains an inner
`//` or `/./`, or a trailing `/` (`kernel/k1/I386.md`), so their
treatment is FREE.

`${ROOT}` in recipes expands to `/` at the root, so paths such as
`//build-out/k1-direct` occur (`kernel/tools/k1-direct.recipe:11-13`);
step 1 covers them.

### 5.3 Creation, deletion, renaming

- `open` with `O_CREAT` and `mkdir` create an entry under the canonical
  name without looking at any other entry. Files are created in
  directories that have no entry, for example `usr/bin/tcc-mes` and
  `usr/lib/mes/crt1.o` in the hand-off (`tinycc/hex0-handoff.recipe:27,39`).
  This MUST work.
- `chdir` and `lstat` succeed only on a name that has an entry. The boot
  image has an entry for every directory that contains a file, and for
  `tmp` (`kernel/k0/mkfs.py:34-39,48-50`).
- `open` does not distinguish files from directories; opening a directory
  is not used.
- `unlink` removes exactly the named entry. `rename` changes exactly one
  entry's name; entries "under" a renamed directory are not touched
  (directories are not renamed in use).
- At most one live entry has a given name.
- The table has room for 16,384 entries in total (section 6.2). Reusing
  a removed entry's slot is FREE and not needed.

### 5.4 The working directory

Per process state: inherited across `fork` and `execve`, restored in the
parent when a child exits. Initially the root. Its name must be able to
hold at least 64 bytes (the longest in use is 50,
`/steps/tcc-0.9.26/build/tcc-0.9.26-1147-gee75a10c`). The runner builds every `${ROOT}` path from `getcwd`'s answer, so
it MUST be exactly `/` plus the canonical name.

## 6. The boot image (`kernel/k0/mkfs.py`)

`mkfs.py` writes the image that QEMU's loader device places at physical
0x50000000 (`FSIMG`). It is K0's initial state, not an archive: K0 uses it
in place. `mkfs.py` is not rewritten; K0 MUST accept exactly what it
writes. All fields are little-endian; all pointers are absolute physical
addresses.

### 6.1 Layout

| image offset | content | source |
|---|---|---|
| +0x0000 to +0x0FFF | kernel state page. Zero except the fields below. | `mkfs.py:40,61-68` |
| +0x0010 | u32: address just past the last file-table entry | `mkfs.py:65` |
| +0x0018 | u32: first free address of the file heap | `mkfs.py:66` |
| +0x0020 | u32: first free address of the `mmap` area, initially 0x80000000 | `mkfs.py:25,67` |
| +0x00D8 | the initial descriptor table: 8 bytes per descriptor, u32 target then u32 position. Three are filled: fd 0 = address of the file-table entry of init's standard input, position 0; fd 1 and fd 2 = target 1, meaning the console. Target 0 means not open. | `mkfs.py:68` |
| +0x1000 | PML4: entry 0 points at +0x2000 (present, writable) | `mkfs.py:69` |
| +0x2000 | PDPT: four 1 GiB pages mapping 0 to 4 GiB onto themselves (present, writable, page-size bit) | `mkfs.py:70-71` |
| +0x3000 | init's argument vector: one pointer to the string at +0x3010, then a null pointer | `mkfs.py:72` |
| +0x3010 | init's path, `seed-forth`, 0-terminated. It is a canonical name, and also `argv[0]`. | `mkfs.py:26,73` |
| +0x4000 | the file table: 24-byte entries, room for 16,384 | `mkfs.py:22-24,58-60` |
| +0x64000 | names and file contents, packed; the file heap starts after them | `mkfs.py:24,44-47` |

The whole image below +0x64000 that is not listed is zero, and K0 may use
the unlisted parts of the first page for its own state. The three u32
fields at +0x10, +0x18 and +0x20 are read again by K1 after K0 has run
(section 9), so K0 MUST keep them there, current, with these meanings.
Where K0 keeps the live descriptor table and the rest of its state is
FREE; only the initial content at +0xD8 is fixed.

### 6.2 File-table entry

Six u32 fields (`mkfs.py:58-60`):

| offset | field |
|---|---|
| 0 | address of the name (not 0-terminated) |
| 4 | length of the name |
| 8 | address of the content |
| 12 | size of the content in bytes |
| 16 | capacity: bytes allocated at the content address (equal to size in the image) |
| 20 | type: 0 removed, 1 regular file, 2 directory |

Entry 0 is the root: all fields 0 except type 2. Then one entry per
directory, sorted, then one per file, sorted (`mkfs.py:42-55`). K0 adds
entries after the last one and updates the u32 at +0x10. K1 reads fields
0, 4, 8, 12 and 20 (`kernel/k1/fs.c:675-711`); the capacity field is
K0's own. Setting the type to 0 is all a removal needs: K1 skips an entry
whose type is 0 or whose name length is 0 (section 9), so the other
fields may keep their values.

Memory regions the image fixes:

- the file heap begins at the address in +0x18 and grows upward; it MUST
  stay below 0x80000000 (`mkfs.py:57` asserts the image itself does), and
  the u32 at +0x18 MUST always be at or above the end of every name and
  content K0 has stored;
- the `mmap` area begins at the address in +0x20 and grows upward; the
  u32 at +0x20 MUST always be at or above the end of everything K0 has
  placed there.

### 6.3 What the image holds

`kernel/k1/mkboot.py` (K1 route) and `tinycc/hex0-handoff-image.py`
(hand-off) choose the files. Both make `seed-forth` init and
`kernel/tools/k1-direct-start.fth` its standard input, with standard
output and standard error on the console and the root as working
directory (`mkfs.py:12-13`).

## 7. The console

Writing to a descriptor whose target is the console sends each byte, in
order, to I/O port 0x3F8 (COM1's data register). No UART initialisation
is needed under QEMU and none is done; no status polling is required.
QEMU records the bytes in the `-serial file:` log.

The scripts grep that log for lines the programs print, for example
`k0: K1 built by seed Forth; handing over`
(`kernel/tools/k1-direct-boot.recipe:5`, `kernel/k1/run-chain.sh:61-72`)
and lines starting `hex0-handoff`
(`tests/tinycc/hex0-handoff-check.sh:125`). K0 itself MUST print nothing:
it has no messages, and bytes of its own would land inside those lines.

There is no console input. Standard input is always a file.

## 8. Ending the run

When a program calls `exit(status)` and no parent is suspended, K0 writes
the low byte of `status` to I/O port 0xF4 (one byte). QEMU's
isa-debug-exit device then terminates QEMU with exit status
`(status << 1) | 1`. If the write returns, halt.

So a successful run of K0 alone ends QEMU with status 1:
`tests/tinycc/hex0-handoff-check.sh:123-124` ("1 is K0's exit 0"). In the
K1 route K0 never gets there: K1 takes over and ends QEMU itself, also
with 1 for success (`kernel/k1/run-chain.sh:26,59-60`). A failing
launcher exits with 101 to 117 (`kernel/tools/k1-direct-start.fth`), which
QEMU reports as 203 to 235; any status other than the expected one fails
the scripts.

## 9. The hand-off to K1

K0 knows nothing about K1. The recipe runner forks, and the child
`execve`s `build-out/k1-direct/k1`
(`kernel/tools/k1-direct-boot.recipe:5-6`). What K1 needs at that moment,
and afterwards, from K0:

1. **Entry.** Loaded per section 3.2 at 0x200000 with its bss zeroed,
   entered at `e_entry` in 64-bit ring 0 with interrupts off, on K0's
   identity map, with rsp at the argument block: `argc`, then `argv`
   pointers (`kernel/k1/k1-asm.fth:17-21`, `kernel/k1/main.c:449-462`).
   K1 copies its arguments before doing anything else.
2. **Page tables that stay valid** until K1 has built and loaded its own
   (`kernel/k1/main.c:308`): identity mapping of at least the low 4 MiB,
   the argument block and the boot image. K1's page allocator starts
   only after that (`kernel/k1/main.c:466-480`).
3. **The file table**, read after K1 has its own page tables
   (`kernel/k1/fs.c:669-717`): from 0x50004000 up to the address stored at
   0x50000010, 24-byte entries as in section 6.2. K1 skips entries with
   type 0 or name length 0, makes a directory for type 2, and for type 1
   copies `size` bytes from the content address into a file of that name
   under `/k0/`. Every file created under K0 has to be there with its
   final name and bytes: K1's init is `/k0/build-out/amd64-runner`
   (`kernel/k1/README.md:122-124`).
4. **Truthful extents** (`kernel/k1/mm.c:38-58`). Before the import K1
   keeps its allocator out of: the low 4 MiB; 0x50000000 up to the
   address stored at 0x50000018; and 0x80000000 up to the address stored
   at 0x50000020 (when that is above 0x80000000). Every other piece of
   RAM may be overwritten before the import. So every name and every file
   content MUST lie in one of the two protected ranges. With the file
   heap as in section 6.2 this holds. After the import K1 frees
   0x50000000 up to the heap end.
5. **The machine**: nothing K0 set up that K1 keeps. K1 installs its own
   GDT, IDT, TSS, `syscall` MSRs, page tables and FPU state, reads the
   memory map from QEMU's fw_cfg, and drives the serial port and the IDE
   disks itself. K0 MUST NOT leave a device in a state that needs undoing:
   it enables no interrupt source and touches the IDE controller only in
   call 248, which the K1 route never makes.

`kernel/k1/` is compiled input with pinned hashes
(`tests/pins/outputs.sha256`); it cannot be changed to suit a new K0.

## 10. What is not required

- Size, hash and internal layout of K0. The hash pin changes (section 12).
- How system calls are dispatched, where K0's own state, stack, scratch
  buffers and fork snapshots live, and how `fork` is implemented, within
  sections 3.3, 6 and 9.
- GDT contents and selector values, subject to working under KVM and TCG.
- Where a program's stack is, within section 3.2.
- Any error checking beyond the four error returns specified: bad
  pointers, descriptor numbers out of range, table or memory exhaustion,
  malformed ELF files and overlong paths need no handling.
- Linux behaviour that no caller uses: access modes, `O_APPEND`, file
  permissions, `chmod` effects, directory semantics, reading the console,
  `lseek` on the console, `wait4` options, a non-empty environment.
- Reclaiming file storage, and reusing table slots.
- Resolving inner `//` or `/./` or a trailing `/` in paths.
- Sharing file positions between a parent and its forked child.

Not free, although they look like shortcuts: ring 0 for programs (3.1);
-38 for every other call number (4); no `..` resolution (5.2); files
creatable without their directories (5.3); zeroed stack on `execve`
(3.2); all registers preserved across a call (4); silence on the console
(7).

## 11. Format rules: `kernel/k0/asm-check.py`

The check assembles the file's comments with GNU as (`as --64`), and with
`llvm-mc` when installed, and requires the same bytes as the hex. Read the
script's docstring; the rules that bind the author:

1. **Lines.** Blank, a comment starting with `;` or `#`, or pairs of hex
   digits optionally followed by `;` and a comment
   (`asm-check.py:69,90-104`). One instruction or one data field per byte
   line. File offset N is address 0x100000 + N (`:67`).
2. **Mode lines.** `;; ===== bits 32 ...` and `;; ===== bits 64 ...`
   switch between 32-bit and 64-bit assembly for the lines that follow.
   One MUST come before the first byte line (`:70,252-255,268-270`). Code
   that runs before the switch to long mode goes under `bits 32`.
3. **Constants.** A comment line `;;   NAME = VALUE` defines NAME for the
   assembler; NAME is upper case letters, digits and underscores, VALUE a
   decimal or `0x` number, optionally negative; prose may follow the
   value (`:71,256-259`). Instructions then use the names, also in
   expressions such as `NAME + 16`, and as memory displacements. Any comment line of
   that shape is taken as a definition, so prose must not look like one.
   Define a name before the first line that uses it.
4. **Labels.** `;; ----- name @ 0xNNN -----` names a routine at file
   offset NNN (uppercase hex); `;; .name @ 0xNNN` (lower case, digits,
   underscores) a label local to the last routine. The stated offset must
   be the offset of the next byte line; a label after the last byte must
   state the file's size (`:72-73,107-137`). A `;;` line that contains
   ` @ 0x`, starts with `;; -----`, or is `.name` or `.name:` alone, and
   does not match, fails. Each label may be defined once.
5. **Instructions.** The comment up to its second `;` is the instruction
   in Intel syntax with NASM's `byte [`, `word [`, `dword [`, `qword [`.
   After the second `;` anything may follow. The bytes must be the
   encoding GNU as chooses, and llvm-mc must choose the same, with one
   tolerated difference: register-to-register `xchg` with the two
   registers in the opposite ModRM fields (`:202-209`). Any other
   spelling passes to both assemblers unchanged, so it must be one both
   accept. In particular llvm-mc rejects a direct far jump such as
   `jmp 8:0x100040` in Intel syntax; the jump into 64-bit code can be
   written as an indirect far jump through a 6-byte pointer in the image,
   `jmp fword ptr [0x1000NN (name)]`, which both accept.
6. **Data.** `db`, `dw`, `dd`, `dq` followed by an expression, which may
   use constants and routine labels, for example a difference of two
   labels (`:76,169-173`).
7. **Branch notes.** `call`, `jmp`, `loop`, `jrcxz` and conditional jumps
   to a label carry `(rel8 = 0xA - 0xB)` or `(rel32 = 0xA - 0xB)`: A the
   target's file offset, B the offset just past the line, A - B the
   displacement in the line's last 1 or 4 bytes (`:175-195`). An indirect
   `call` or `jmp` may use only rax, rbx, rcx, rdx, rsi, rdi, rbp or rsp;
   any other operand is read as a label.
8. **Addresses as operands.** A number inside the image (0x100000 up to
   0x100000 + file size) in an instruction or data line MUST be followed,
   in the same instruction part, by `(name)`, the routine label at that
   address (`:155-168`). Local labels cannot be named this way. Any
   parenthesised lower-case identifier in the instruction part is read as
   such a note, so write no other parentheses before the second `;`.
9. **Whole file.** No relocations, no undefined symbols, and the
   assembler's output is exactly the file's size (`:298-300`).

`kernel/k0/check.sh` runs the script and then compares the sha256 of
hex0-seed's `k0.bin` with the line `<64 hex digits>  k0.bin` in
`tests/pins/k0.sha256` (`check.sh:11-15`).

## 12. Acceptance

All of these MUST pass, from the repository root.

Before running them:

- Build seed Forth first (`seed/build.sh`): `run-chain.sh` fails in
  `kernel/k1/mkboot.py` while `seed-forth` is missing, because the boot
  image carries it.
- The checks write their temporaries and logs under `$TMPDIR`, or `/tmp`
  if it is unset (`check-all.sh:60-65`; `check.sh` and `asm-check.py`
  through `mktemp` and Python's `tempfile`). Set `TMPDIR` to keep them
  elsewhere.
- Keep the checkout outside `/tmp`: `tests/cc/gates/run-gates.sh` mounts
  a private `/tmp` in its sandbox, which hides a checkout there, and step
  05 then fails gates die-32 and die-36 with error 30. This is a fault of
  the harness, not of K0.
- To run the smoke test under TCG on a machine with KVM, set `QEMU` to a
  wrapper that drops `-accel kvm`, replaces `-cpu host` with `-cpu max`
  and runs `qemu-system-x86_64 -accel tcg` with the remaining arguments
  (`kernel/k1/run-chain.sh:50`), and set `K1_DISKS` to a separate
  directory. It takes about 9 minutes, against 15 seconds with KVM.

| check | what it proves |
|---|---|
| `python3 kernel/k0/asm-check.py` | section 11 |
| `sh kernel/k0/check.sh` | the same, and the pinned hash, after `tests/pins/k0.sha256` has the new binary's sha256 |
| `kernel/k1/run-chain.sh --direct-smoke` | K0 boots under QEMU with 3 GiB, runs seed Forth, which builds the runner and K1 through `open`, `read`, `write`, `close`, `lseek`, `mmap`, `dup2`, `fork`, `execve`, `exit`, `wait4`, `getcwd`, `chdir`, `rename`, `mkdir`, `unlink`, `chmod`, `lstat` and the -38 answers; K1 starts, imports K0's files and runs programs from them. QEMU exits 1; `serial.log` has `k0: K1 built by seed Forth; handing over` and the K1 PASS line. Run it with and without KVM if possible (the script picks TCG when `/dev/kvm` is not writable) |
| `tests/tinycc/hex0-handoff-check.sh` | K0 alone to the end: the first tcc under K0 (`brk`, the zeroed stack, single-byte writes, `getcwd` output in the binaries), literal `..` names, call 248. Boot 1 exits 1; the hand-off files in the stream have the hashes of `tests/pins/tinycc.sha256`; boot 2 boots the disk K0 wrote and reaches live-bootstrap's published tcc |
| `CHECK_TINYCC=1 CHECK_HEX0_HANDOFF=1 ./check-all.sh` | `check-all: 12 OK, 0 SKIP, 0 FAIL`. Step 09 is `check.sh`; step 14 is the hand-off; step 10 reports `5 as pinned`. K1's hash (`f90229b1...`, `tests/pins/outputs.sha256`) is built on the host there; the smoke run is what builds it under K0 |

What changes and has to be updated with the new K0:

- `tests/pins/k0.sha256`: the hash line, and its comment's size and
  history.
- Documents that state K0's size: `README.md:20,75`,
  `kernel/README.md:3`, `kernel/k1/README.md:7`.

Not affected, and the proof that the rewrite is a drop-in: every hash in
`tests/pins/outputs.sha256` and `tests/pins/tinycc.sha256` stays as it
is, and the two QEMU runs pass unchanged.

What no check above exercises. A K0 can be wrong in each of these and
still pass every check, so each has to be right by reading the code
against this specification:

- RFLAGS restored from r11 under TCG (section 4);
- nothing written at or below the caller's rsp, including the red zone
  (section 4);
- the -9, -17 and -38 returns other than those the runs happen to reach;
- a write that starts past the end of a file, and the zero gap it leaves
  (section 4.1);
- `fork` nested more than one level deep, where a K0 supports it
  (section 3.3).
