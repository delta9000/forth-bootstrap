# builder-hex0 measured: kernel behaviours an i386 Forth and C compiler rely on (2026-11-21)

The seed, the library and the C shims are written defensively against
this kernel: no read of descriptor 0, no `mmap`, a guard in front of
`execve`, files written once and in order.  This note is the evidence for
those choices.  A first list of the kernel's hazards came from reading
its source only; here builder-hex0 was booted under QEMU/KVM, and probe
programs measured each behaviour.  `seed/SPEC.md` (section 10) and
`forth/CONTRACT.md` cite the sections below as `P§n`.

- **Kernel:** builder-hex0 at a2781242, booted as
  `tests/tinycc/one-boot-check.sh` boots it. Stage 1 is assembled by the
  host `hex0-seed`, and stage 2 is compiled from
  `builder-hex0-x86-stage2.hex0` by stage 1.
- **Citations:** `B2:<line>` refers to that stage-2 file.
- **Probes:** one i386 static ELF, `probe`, with a mode per test. It is
  built by host `gcc -m32 -static -nostdlib` with its own `int 0x80` stubs:
  no libc and no tcc.

**What the checks use, and what is kept as evidence.**  `./check-all.sh`
runs none of the five measurement boots.  Two of its steps borrow tools
from this directory:

- step 14, `tests/seed/boot-check.sh`: `boot.sh`, and through it
  `mkdisk.py` and `tsserial.py`;
- step 13, `tests/tinycc/kaem-boot-check.sh`: `mkdisk.py`, and `build.sh`
  with `src/start.S`, `src/probe.c` and `src/probe.ld`, because it puts
  `probe` on its disks as a program whose exit status is known (`exit0`,
  `exit300`).

Everything else is the record of the measurement and is run by hand
only: the lists `boot-{a,b,c,d,e}.list`, `hmp.py`, `src/tscfreq.c` and
the serial logs in `logs/`.  "Rebuilding the probe disk" below is how to
run a measurement boot again; the logs are those of 2026-11-21 and no
check compares a new run with them.

Everything in the table was measured unless it is marked **not measured**.
The raw serial logs are in `logs/`, and the main log is
reproduced in the appendix.

## Files (in `tests/builder-hex0/`)

| file | what |
|---|---|
| `src/probe.c` | all probe modes (`unimpl brk fork child exit300 exit0 entry-* execoverlay execfork execmissing files stdin ring irq speed1m speed10m forknoexec brkdown`) |
| `src/start.S` | `_start` (records every register, eflags, cs/ss/ds and esp before any C runs), `sc()` (int 0x80 with eax, ebx…ebp set; records ebx…ebp as returned), `canary()` (fill below esp, syscall or spin, scan, with no stack use in between), IRQ counting handlers, `rdtsc`, `inb`/`outb`/`sidt` |
| `src/probe.ld` | one RWX `PT_LOAD` at 0x08048000 holding the headers. execve copies every program header and takes brk from the last one, so a default gcc link, which ends with `PT_GNU_STACK` (vaddr 0), would get brk = 0x20000 |
| `src/tscfreq.c` | host TSC rate (3792.8 MHz on this Ryzen 7 9700X; `constant_tsc nonstop_tsc`) |
| `build.sh` | builds `probe` |
| `mkdisk.py` | the disk: stage 1, stage-2 text, zeros to sector 175, then `src`/command records (the layout `tinycc/one-boot-disk.py` writes, with one addition: `r TEXT`, raw bytes for fd 0), padded to 64 MiB |
| `boot.sh` | builds the disk from a list and boots it with the boot-2 QEMU line; the serial output goes through `tsserial.py` (host timestamps) |
| `hmp.py` | sends commands to a QEMU monitor socket (used for the runaway brk) |
| `boot-{a,b,c,d,e}.list` | the five boots |
| `logs/` | serial logs (ANSI escapes stripped); `boot-c*-hmp.txt` holds the monitor samples |

### Rebuilding the probe disk

```sh
tests/builder-hex0/build.sh                          # gcc -m32 ... -T src/probe.ld -o probe src/start.S src/probe.c -lgcc
tests/builder-hex0/boot.sh boot-a.list boot-a.log 300
```

`boot.sh` works in `build-out/builder-hex0-probe/`: it copies the
stage-2 source from `build-out/tinycc-inputs/builder-hex0-a2781242…/`,
assembles `stage1.bin` with
`vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed`, writes the
disk with `mkdisk.py`, and boots it with live-bootstrap's boot-2 QEMU line
(`-enable-kvm -m 4096M -smp 1 -machine kernel-irqchip=split -no-reboot
-nographic`), timestamping the serial output with `tsserial.py`.

**Reproducibility.** Copying the directory to a fresh location and rerunning
`build.sh` and `boot.sh boot-b.list` gave a serial log identical to the
recorded one except for the TSC counts.

The `probe` bytes differ between build directories only after the loaded
segment: the symbol table holds gcc's temporary object names. The loaded
image is identical. The disk images therefore differ per build, so no image
hashes are pinned. `stage1.bin` is `87c3d445…`.

**List format.** Each line is one of:
- `f HOSTPATH NAME`: a file;
- `d PATH`: a directory;
- `x PROG ARG`: an internal-shell command;
- `r TEXT`: raw bytes.

Every `x` line needs exactly one argument, because the internal shell reads
the name up to a space and the argument up to a newline (B2:2439-2457).
A first letter of `s`, `h` or `f` is taken as a builtin.

**Ending the boot.** The stream ends at the first zero byte: the shell
prints "Build finished.", flushes `/dev/hda` (here "ERROR: no hda writes!")
and reboots. `-no-reboot` then ends QEMU.

### The boots

| boot | list | content |
|---|---|---|
| A | `boot-a.list` | `unimpl brk entry-shell fork execfork execoverlay files ring speed1m speed10m stdin`, then the line `STDIN-MARKER-0123456789` |
| B | `boot-b.list` | `irq`, `forknoexec`, `entry-shell` |
| C | `boot-c.list` | `brkdown` (runaway brk), with `QEMU_EXTRA="-monitor unix:$PWD/mon.sock,server,nowait"` and `hmp.py` sampling |
| D | `boot-d.list` | `execmissing` (execve of a missing file from a forked child) |
| E | `boot-e.list` | the shell command `/nosuchprog arg` |

The first run of boot A had execmissing inside `execfork` and died there.
That log is `logs/boot-a-run1.log`. The test was moved to boot D.

## Results

**Addresses and cycle counts** in the tables come from boot-A runs of the
previous build. The appendix log comes from the final build, which only
added prints. Its addresses differ by a few hundred bytes (initial break
0x0806e788, still exactly file end + 0x20000; memsz end 70,424 bytes above
it). Every value, status and canary depth is the same. The TSC counts are
within 1 % (10 M writes: 2,880 M cycles).

The Agree column takes these values:
- **yes**: the measurement confirms the study;
- **no**: it contradicts the study;
- **new**: the study did not say.

### 1. Unimplemented calls (boot A, `unimpl`)

| behaviour | study | observed | agree |
|---|---|---|---|
| mmap 90 (ebx=0, and old_mmap struct), mmap2 192, munmap 91, dup2 63, dup 41, unlink 10, rename 38, lstat 107, stat 106, lstat64 196, stat64 195, fstat64 197, getdents 141, getdents64 220, chmod 15, rmdir 40, getpid 20, ioctl 54, uname 122, clock_gettime 265, pipe 42, exit_group 252 | eax = 0, nothing done | every one returned 0 with ebx…ebp preserved. The stat, lstat and getdents buffers (pre-filled with 0xAA) were unchanged. After unlink, `/u1` still read `hello`. After rename, `/u1` was still there and `/u2` failed to open. exit_group(9) returned 0 and the program went on | yes |
| aliasing modulo 256 (only `al` compared) | yes | 0x104 (260) acted as write: it printed `ALIAS` and returned 6. 0x121 (289) acted as access: 0 for `/u1`, -1 for `/nonexistent`. 0x127 (295, Linux openat) with ebx = "/u3" acted as mkdir: it returned 0, and afterwards `access("/u3")` returned 0 | yes |
| register clobbers of implemented calls | file write: ebx; chdir and access: ebx; waitpid: esi | file write: ebx → 0x01000070. access and chdir: ebx → 0x00050000. waitpid: esi → 0x00021018. Console write, open, close, read, lseek, mkdir, getcwd, brk and wait4 preserved ebx…ebp | yes |

### 2. brk (boot A `brk`; boot C `brkdown`)

| behaviour | study | observed | agree |
|---|---|---|---|
| initial break | end of the last segment's file bytes + 0x20000 | file end 0x0804dca8, brk(0) 0x0806dca8: exactly +0x20000 | yes |
| relation to memsz | the bss can overlap the heap | memsz end 0x0807efa0 is 70,392 bytes **above** the initial brk. In boot A's `fork`, a bss variable at 0x0807ed40 was overwritten by the child program and **not** restored (section 3) | yes |
| bss zero at entry | (execve zeroes 0x08048000…) | all 0x30000 bytes of the bss array read 0 | yes |
| memory above brk | plain RAM | brk+0x1000 and 0x20000000 can be written and read back | yes |
| growing to 64 / 256 / 600 MB (break = 0x08048000 + N MB) | zeroes from the old to the new break | each returned the new break, and brk(0) agreed. Every 4 KiB page of the new range, and its last byte, had been set to 0xA5 beforehand; afterwards there were 0 nonzero bytes in each range. Cost: 141 M, 420 M and 751 M TSC cycles (37, 111 and 198 ms), about 2.1 cycles per byte grown | yes |
| brk(current) | (no-op) | returned the current break, unchanged | yes |
| brk above the 670 MB process area | (no limit stated) | brk(0x30001000) returned 0x30001000. It zeroed this process's argv strings, which live at 0x30000000+: argv[0] went from `/probe` to `''` | new: there is no upper bound |
| brk below the current break | runs away and zeroes memory until it wraps (B2:1435-1441) | `brk(brk-4096)` never returned: not within 75 s (boot C), nor within about 70 s in an earlier run. The monitor showed EIP = 0x8585, the `jmp init_loop`, with EDI rising, and **within about 6 s** EDI was past 0xC0000000. Final run (`logs/boot-c-hmp.txt`, break 0x0806e788):
- the break and break+0x1000, which the probe had filled with 0x5A, read 0;
- the first file (`/probe` at 0x54000000, which read `7f 45 4c 46 01 01 01 00` just before the call) read all zeros;
- 0x30000000, where this process's argument strings were placed, read 0, although its value before the call was not printed;
- the image below the break was **intact**: 0x08048000 still read `7f 45 4c 46…`;
- the kernel at 0x7C00 was intact.

After that it crept through the PCI hole at about 200 KB/s (0xc00f86a6 → 0xc08cadbf over 41 s). **Not measured:** the wrap to 0 and its end. At 200 KB/s the wrap would take about 1.5 h | yes; and it destroys every in-memory file within seconds |

### 3. fork (boot A `fork`; boot B `forknoexec`)

Setup: the parent wrote 0x1111 to each of these:
- `g_below`, in .data below brk;
- `g_data`, in .bss above the initial brk;
- `above`, at brk+0x10000;
- `far`, at 0x20000000;
- a stack local;
- a word at esp-0x2000.

Then it forked. The child wrote 0x2222 to all six and called
`execve("/probe", {"/probe","child"})`. The child program wrote 0x3333 to
`far`, `above`, `g_data` and `g_below`, then exited 42.

| behaviour | study | observed | agree |
|---|---|---|---|
| return values | child 0, parent 1 | child 0, parent 1, ebx…ebp preserved in both | yes |
| child's view before execve | same memory | the child saw every 0x1111 | yes |
| what the new program sees | execve zeroes the process area | g_data, far and above read 0; g_below read 0x77 (its fresh .data) | yes |
| parent, below brk (.data) | saved and restored | 0x1111 | yes |
| parent, .bss above brk | not saved | **0x3333**, the child program's write | yes |
| parent, above brk (brk+0x10000, 0x20000000) | not saved | **0x3333**. Without the child program's write it would be 0 from the wipe; the child program read 0 before writing | yes |
| parent, stack local (above the esp at fork) | saved from esp to 0x08000000 and restored | 0x1111 | yes |
| parent, below the fork esp (esp-0x2000) | (not saved) | **0x2222**, the child's pre-execve write, still there | yes (implied) |
| parent brk after the child | restored | 0x0806dca8, unchanged | yes |
| waitpid(7) | status `code << 8`, returns 0 | exit 42 gave 0x2a00, exit 0 gave 0, **exit 300 gave 0x12c00**: the code is not masked to 8 bits (Linux gives 0x2c00). The call returned 0 each time and clobbered esi | yes, plus the masking detail |
| wait4(114) | status 0, returns 0 | status 0 for an exit of 300; returned 0. A waitpid afterwards still gave 0x12c00 | yes |
| fork, then exit without execve | (not stated) | boot B: the child printed `exiting 7` and exited. **The parent never resumed:** no `parent resumed` line, and the internal shell went on to the next command. Measured only one level below the shell. The source suggests the reason (read, not measured): fork does not take a process slot, so the child's exit is taken as the exit of the shell-launched process | **new** |

### 4. execve (boot A `entry-shell`, `execfork`, `execoverlay`; boots D and E)

| behaviour | study | observed | agree |
|---|---|---|---|
| registers at entry | (eax…ebp xored, `ret` to entry, B2:1785-1794) | eax…ebp = 0. cs = 0x08, ss = ds = 0x10. esp is 0x07ffffd0 when the shell starts the program and 0x07fffed0 for an exec'd child | yes |
| eflags at entry | ("interrupts stay off") | **0x246 (IF = 1)** when the internal shell starts the program. It runs `sti` before execve (B2:2435-2436). **0x46 (IF = 0)** after an `int 0x80` execve, by fork or overlay, because entry is a `ret` from inside the interrupt gate | **no**: see section 6 |
| stack zeroed? | no | no. The parent filled 128 KiB below its esp with 0xCC before exec. In the child, 65,184 of the 65,536 bytes below the entry esp still held 0xCC. The other bytes all lie within about 470 bytes of esp, where the probe's own C frames sit, so they are not evidence either way | yes |
| layout | argc, argv, NULL, envp, NULL | argc, argv[0…], NULL, envp…, NULL, then a kernel return address (0x000082ba). There is **no auxv**. argv is in order. **envp is reversed:** passed E0, E1, E2, the program saw envp[0] = `E2=two`, envp[1] = `E1=one`, envp[2] = `E0=zero` (the env push loop, B2:1642-1656) | **no**: envp is reversed |
| where the strings live | 256-byte slots | at 0x30000000+ (the saved-process area), 256 bytes apart. argv[i+1] is at a **lower** address than argv[i], and envp comes below argv | yes |
| argument length | 255 bytes | a 300-byte argument (`L`…`E`) arrived with strlen 257, ending `…LLLLLLLa`. The first 256 bytes are copied with no NUL, and the string runs on into the next slot up, which holds argv[i-1] (`a`). It is truncated and concatenated, and nothing reports it | yes, plus the failure mode |
| a program started by the shell | one argument | argc = 2, envp empty | yes |
| overlay (execve without fork) | replaces the image | worked; at exit the shell continued | yes |
| execve of a missing file | (not stated) | **the machine dies.** Boot D, from a forked child (`access` had returned -1): `KVM internal error … emulation failure`, EIP = f000ff53, and QEMU hung until the timeout. Boot E, the shell command `/nosuchprog arg`: the same. execve does not check `find_file`'s -1 (B2:1715-1732) | **new** |

### 5. Files (boot A `files`, `stdin`)

| behaviour | study | observed | agree |
|---|---|---|---|
| open of a missing file, no O_CREAT | -1 | -1 for O_RDONLY, O_WRONLY and O_RDWR\|O_TRUNC | yes |
| open of a missing file with O_CREAT | new empty file | fd 4: the first fd is 4, and the lowest free slot is reused | yes |
| O_CREAT with a missing parent | -1 | `/nodir/x` gave -1. `/a/b/c` gave -1 even after `mkdir /a`. `mkdir /a/b/c/d` also gave -1 | yes |
| O_CREAT on an existing name | new empty file shadows the old | `/fb` then read length 0 | yes |
| open without O_CREAT for writing | (opens the existing file) | it writes in place with no truncation: `/fb` `aaaaaBBBBB` became `bbaaaBBBBB` | yes |
| growing a file that is not the newest | overwrites the next file | `/fa` (10 bytes), then `/fb` (10 bytes). Reopening `/fa`, seeking to its end and writing 5 bytes left `/fa` as 15 bytes `AAAAAAAAAAaaaaa` and `/fb` as `aaaaaBBBBB` | yes |
| lseek past the end, then write | (not stated) | `lseek(fd,100,SEEK_SET)` = 100, write 1 = 1, SEEK_CUR = 101, but **SEEK_END = 11**. Reading back gave `0123456789\x00`: the `X` is not in the file, and the length grew by 1 only. Peeking at kernel memory (allowed in ring 0): the file table gave `/fd` address 0x54006fff, length 11; the byte at address+100 was 0x58 (`X`), and `next_file_address` was 0x5400700a (address+11). So the byte lies outside the file, in space the next file will take | **new** |
| lseek beyond the end or negative, then read | — | lseek to 1000 returned 1000 and read returned 0. lseek to -5 was accepted and returned -5. read at the end returned 0 | new |
| reading fd 0 | the disk stream, one byte per call, no EOF | `read(0,buf,64)` returned **1**. It and later calls returned the bytes after the command line (`STDIN-MARKER-0123456789\n`), which the shell never saw. After the stream ended: return 1, byte 0x00 | yes |
| close, reopen, position | — | after reading 3 bytes, SEEK_CUR = 3. After close and reopen, SEEK_CUR = 0 and the read gives `AAA` again. Two fds on one file have independent offsets | new (as expected) |
| read of a memory file | — | `read(fd,buf,4096)` on a 15-byte file returned 15 | — |
| close or read of an fd never opened | — | close(77) = 0, read(77) = 0 | new |
| write to fd 0 and fd 2 | fd ≤ 2 goes to the console | both printed | yes |
| `open("/")`, `chdir("/")` | (chdir needs a zero-length entry) | **both -1**: the root has no entry. From `/w`, `chdir("..")` and `chdir("/")` both returned -1 and getcwd stayed `/w`: a process that leaves `/` cannot get back. chdir to an existing directory worked | **new** |
| getcwd | returns the buffer pointer | returned the buffer pointer. **`getcwd(buf, 2)` changed 4 bytes** of a 0xEE-filled buffer (`2f 77 00 00`): the size is ignored | yes, plus the overflow |

### 6. Ring, interrupts and the stack (boot A `ring`; boot B `irq`)

| behaviour | study | observed | agree |
|---|---|---|---|
| privilege | ring 0 | cs = 0x08 (CPL 0). `mov eax, cr0` works: 0x11, PE+ET, **no paging** | yes |
| IF | "interrupts stay off (`have_userspace` is 0, B2:649)" | **IF = 1** in programs the shell starts (eflags 0x246 at entry, 0x202 and 0x206 later): `handle_other_command` sets `have_userspace` and runs `sti` (B2:2435-2436). Programs exec'd through `int 0x80` start with IF = 0, **and stay at IF = 0 in user code after console writes** (eflags 0x06 measured after console output in the `child` program and in `entry-forked` and `entry-overlay`). A shell-started program read 0x206 after console output. That the handler itself runs with IF = 1 after a BIOS call is read from B2:785 and 636, not measured | **no** for shell-started programs; matches the study for exec'd children such as programs under kaem |
| hardware interrupts actually delivered | — | **none were observed.** With IF = 1 and counting handlers on vectors 8-15, two spins of about 0.74 s each counted 0 interrupts. The master PIC read IMR = 0xb8, IRR = 0x11 and **ISR = 0x01**: IRQ0 is in service and unacknowledged. The kernel's vector-8 stub is a bare `iret` (read). That an in-service IRQ0 blocks IRQ0-7 is 8259 behaviour, not measured here. One EOI sent by the probe changed nothing measurable: ISR read 0x01 again and the next spin counted 0. That a timer IRQ was taken straight back into the kernel's stub is an inference, not measured | new; the effect matches the study's assumption. Specific to this QEMU line (SeaBIOS, `-machine kernel-irqchip=split`, KVM) |
| asynchronous writes below esp | — | a canary of 16 KiB below esp, over 4 spins of about 0.74 s with IF = 1 and no syscalls: **0 bytes changed** | — |
| syscalls write below the caller's esp | yes (the frame and pushes land on the program's stack) | yes, always. Depth below the caller's esp: unimplemented (getpid) **12**, brk(0) 20, lseek 20, getcwd 24, file write 40, console write 48, file read 48, access 56, **open 72** (16 KiB canary, 0xC3 fill). fork and execve were not canaried: fork saves from its own esp, and execve pushes argc, argv and envp below it | yes |

### 7. Speed (boot A `speed1m`, `speed10m`; KVM, `-smp 1`, host TSC 3792.8 MHz)

| loop | TSC cycles | per call | rate |
|---|---:|---:|---:|
| 1,000,000 × write 1 byte to a file | 289 M | 289 | 13.1 M/s |
| 10,000,000 × write 1 byte to a file | 2,889 M (0.76 s) | 289 | **13.1 M/s** |
| 10,000,000 × read 1 byte from a file | 2,421 M | 242 | 15.7 M/s |
| 10,000,000 × unimplemented call (getpid) | 2,392 M | 239 | 15.9 M/s |
| 2,000 × write 1 byte to the console | 510-515 M | about 257,000 (68 µs) | about 15 k chars/s |

The file length afterwards was exactly 1,000,000 and 10,000,000. The guest
read the TSC; under KVM the guest TSC runs at the host rate.

The host timestamps agree only roughly. The serial output lags: a line
printed before a loop arrives after it. The gap between the lines around
the 10 M write loop is 0.79 s, against the TSC's 0.76 s.

**Not measured:** speed without KVM (TCG).

## Blockers for running a Forth and a C compiler as processes

None was found. These rules must be followed on the program side:
- `access` before every execve;
- never fork without execve;
- never brk downward;
- arguments of 255 bytes or less;
- mkdir each directory level;
- grow only the newest file, and never write after seeking past the end;
- brk in place of mmap, and brk over the bss before a fork;
- do not rely on the order of envp or on `chdir("/")`.

## Disagreements with the study

1. **Interrupts.** The study says interrupts stay off. In fact IF = 1 in
   any program the shell starts; exec'd children run with IF = 0, as the
   study assumed. No
   hardware interrupt was observed reaching a program, because IRQ0 is
   stuck in service on the master PIC. The study's conclusion (nothing
   asynchronous writes on the program's stack) holds in practice, but for a
   different reason. It would change if anything sent an EOI.
2. **envp is reversed** relative to the array passed to execve. argv is in
   order. There is no auxv.

These hazards are not in the study, and all are program side:
- **execve of a missing path crashes the machine** (boots D and E). Check
  with `access` first.
- **fork followed by exit without execve** loses the parent: control
  returns to the internal shell.
- **lseek past the end, then write:** the bytes go outside the file and the
  length grows by the count written, not to the offset.
- **`chdir("/")` and `open("/")` fail.** A process that leaves the root
  cannot return to it.
- **getcwd ignores its size argument.**
- **exit_group (252) returns 0 and does not exit.** A libc whose `_exit` uses it carries on running.
- **brk has no upper bound:** past 0x30000000 it zeroes the process's
  argv strings and the saved parents.
- **An argument over 255 bytes** is cut to 256 bytes and runs on into the
  previous argument.
- **waitpid's status** is the unmasked `code << 8`.
- **The runaway brk** (confirmed) wipes every in-memory file within about
  5 s, long before it wraps.

Everything else in section 1 of the study was confirmed: the dispatch, the
values returned for unimplemented calls, the brk start, fork's save to brk,
the waitpid and wait4 values, the stack not being zeroed, the 256-byte
slots, files growing only at the newest, the -1 errors, fds from 4, the
register clobbers, and getcwd returning a pointer.

## Appendix: raw serial output

Each line is prefixed with host seconds by `tsserial.py`; the BIOS console wraps lines at 80 columns. Logs are complete from "Booting" unless marked.

### boot A (`logs/boot-a.log`)

```
[    0.0798] Booting from Hard Disk...
[    0.0800] src
[    0.0858] /probe
[    0.0861] /probe
[    0.1206] unimpl
[    0.1212] == unimpl begin
[    0.1228] mmap(90,ebx=0) ret=0x00000000 (0) regs-preserved
[    0.1247] mmap(90,old_mmap struct) ret=0x00000000 (0) regs-preserved
[    0.1268] mmap2(192,0,4096,3,0x22,-1,0) ret=0x00000000 (0) regs-preserved
[    0.1283] munmap(91) ret=0x00000000 (0) regs-preserved
[    0.1299] dup2(63,4,0) ret=0x00000000 (0) regs-preserved
[    0.1314] dup(41,1) ret=0x00000000 (0) regs-preserved
[    0.1330] unlink(10,/u1) ret=0x00000000 (0) regs-preserved
[    0.1347]   /u1: open=4 len(SEEK_END)=5 read=5 bytes=[hello]
[    0.1365] rename(38,/u1,/u2) ret=0x00000000 (0) regs-preserved
[    0.1382]   /u1: open=4 len(SEEK_END)=5 read=5 bytes=[hello]
[    0.1387]   /u2: open=-1
[    0.1433] lstat(107,/u1,st) ret=0x00000000 (0) regs-preserved
[    0.1471]   lstat buffer unchanged=1
[    0.1521] lstat(107,/nonexistent,st) ret=0x00000000 (0) regs-preserved
[    0.1569] stat(106,/nonexistent,st) ret=0x00000000 (0) regs-preserved
[    0.1620] lstat64(196,/nonexistent,st) ret=0x00000000 (0) regs-preserved
[    0.1669] stat64(195,/nonexistent,st) ret=0x00000000 (0) regs-preserved
[    0.1715] fstat64(197,1,st) ret=0x00000000 (0) regs-preserved
[    0.1753]   stat buffers unchanged=1
[    0.1786]   open(/)=-1
[    0.1835] getdents(141,fd,st,256) ret=0x00000000 (0) regs-preserved
[    0.1884] getdents64(220,fd,st,256) ret=0x00000000 (0) regs-preserved
[    0.1923]   getdents buffer unchanged=1
[    0.1970] chmod(15,/u1,0755) ret=0x00000000 (0) regs-preserved
[    0.2018] rmdir(40,/nonexistent) ret=0x00000000 (0) regs-preserved
[    0.2062] getpid(20) ret=0x00000000 (0) regs-preserved
[    0.2109] ioctl(54,1,TCGETS,st) ret=0x00000000 (0) regs-preserved
[    0.2154] uname(122,st) ret=0x00000000 (0) regs-preserved
[    0.2202] clock_gettime(265,0,st) ret=0x00000000 (0) regs-preserved
[    0.2246] pipe(42,st) ret=0x00000000 (0) regs-preserved
[    0.2301] exit_group(252,9) [should not exit if unimplemented] ret=0x00000000 (0) regs-pre
[    0.2333] served
[    0.2364] ALIAS
[    0.2417] sys 0x104=260 (al=4 write) fd1 'ALIAS\n' ret=0x00000006 (6) regs-preserved
[    0.2502] sys 0x121=289 (al=0x21 access) /u1 ret=0x00000000 (0) clobbered: ebx->0x00050000
[    0.2502] 
[    0.2557] sys 0x121=289 (al=0x21 access) /nonexistent ret=0xffffffff (-1) clobbered: ebx->
[    0.2590] 0x00050000
[    0.2645] openat(295=0x127, al=0x27 mkdir?) ebx="/u3" ret=0x00000000 (0) regs-preserved
[    0.2695]   access(33,/u3) ret=0x00000000 (0) clobbered: ebx->0x00050000
[    0.2736] -- implemented calls, register clobbers
[    0.2786] access(33,/u1) ret=0x00000000 (0) clobbered: ebx->0x00050000
[    0.2838] access(33,/nonexistent) ret=0xffffffff (-1) clobbered: ebx->0x00050000
[    0.2888] open(5,/u4,O_WRONLY|O_CREAT) ret=0x00000005 (5) regs-preserved
[    0.2941] write(4,fd,'x',1) to file ret=0x00000001 (1) clobbered: ebx->0x01000070
[    0.2970] y
[    0.3021] write(4,1,'y\n',2) to console ret=0x00000002 (2) regs-preserved
[    0.3065] lseek(19,fd,0,0) ret=0x00000000 (0) regs-preserved
[    0.3108] close(6,fd) ret=0x00000000 (0) regs-preserved
[    0.3153] read(3,fd,buf,10) ret=0x00000001 (1) regs-preserved
[    0.3196] close(6,fd) ret=0x00000000 (0) regs-preserved
[    0.3240] mkdir(39,/ud) ret=0x00000000 (0) regs-preserved
[    0.3287] chdir(12,/ud) ret=0x00000000 (0) clobbered: ebx->0x00050000
[    0.3335] getcwd(183,buf,256) ret=0x0804e840 (134539328) regs-preserved
[    0.3367]   cwd=/ud
[    0.3418] chdir(12,/nonexistent) ret=0xffffffff (-1) clobbered: ebx->0x00050000
[    0.3471] chdir(12,/u1) (non-empty file) ret=0xffffffff (-1) clobbered: ebx->0x00050000
[    0.3518] chdir(12,/) ret=0xffffffff (-1) clobbered: ebx->0x00050000
[    0.3564] brk(45,0) ret=0x0806e788 (134670216) regs-preserved
[    0.3596] == unimpl end
[    0.3627] /probe
[    0.3775] brk
[    0.3807] == brk begin
[    0.3845] _start=0x08048060 (134512736)
[    0.3893] file end (edata_mark, = vaddr+filesz)=0x0804e788 (134539144)
[    0.3935] memsz end (end_mark)=0x0807faa0 (134740640)
[    0.3976] brk(0) initial=0x0806e788 (134670216)
[    0.4016] brk - file end=0x00020000 (131072)
[    0.4056] brk - memsz end=0xfffeece8 (-70424)
[    0.4101] nonzero bytes in bss (0x30000 array)=0x00000000 (0)
[    0.4147] nonzero bytes between memsz end and brk=0x00000000 (0)
[    0.4193] byte written at brk+0x1000 reads back=0x0000005a (90)
[    0.4617] byte written at 0x20000000 (above brk) reads back=0x0000006b (107)
[    0.4665] brk(64MB = 0x0c048000) ret=0x0c048000 tsc-cycles=141567k
[    0.5006]   brk(0) now=0x0c048000 (201621504)
[    0.6195]   nonzero bytes in [old brk, new brk) after growth (was dirtied)=0x00000000 (0)
[    0.6243] brk(256MB = 0x18048000) ret=0x18048000 tsc-cycles=429126k
[    0.7194]   brk(0) now=0x18048000 (402948096)
[    0.9304]   nonzero bytes in [old brk, new brk) after growth (was dirtied)=0x00000000 (0)
[    0.9352] brk(600MB = 0x2d848000) ret=0x2d848000 tsc-cycles=776586k
[    1.1018]   brk(0) now=0x2d848000 (763658240)
[    1.1073]   nonzero bytes in [old brk, new brk) after growth (was dirtied)=0x00000000 (0)
[    1.1116] brk(current) ret=0x2d848000 (763658240)
[    1.1161] brk(0) after brk(current)=0x2d848000 (763658240)
[    1.1447] argv[0] before = '/probe' at 0x30000300
[    1.1490] brk(0x30001000) ret=0x30001000 (805310464)
[    1.1528] argv[0] after = '' strlen=0
[    1.1561] == brk end
[    1.1593] /probe
[    1.1748] entry-shell
[    1.1787] == entry begin (entry-shell)
[    1.1831]   eflags after a console write=0x00000206 IF=1
[    1.1867]   entry eax=0x00000000
[    1.1904]   entry ebx=0x00000000
[    1.1940]   entry ecx=0x00000000
[    1.1977]   entry edx=0x00000000
[    1.2013]   entry esi=0x00000000
[    1.2050]   entry edi=0x00000000
[    1.2086]   entry ebp=0x00000000
[    1.2123]   entry esp=0x07ffffd0
[    1.2160]   entry eflags=0x00000246
[    1.2197]   entry cs=0x00000008
[    1.2233]   entry ss=0x00000010
[    1.2269]   entry ds=0x00000010
[    1.2305]   eflags.IF=1 IOPL=0
[    1.2337]   argc=2
[    1.2380]   argv[0]=0x30000500 strlen=6 text='/probe'
[    1.2426]   argv[1]=0x30000400 strlen=11 text='entry-shell'
[    1.2463]   argv[argc]=0x00000000
[    1.2497]   envp count=0
[    1.2552]   stack words from esp: 0x00000002 0x30000500 0x30000400 0x00000000 0x00000000 0
[    1.2607] x00008b8a 0x00008c45 0x00000080 0x00000000 0x00000000 0x0000012f 0x00008cfe 
[    1.2662]   stack below entry esp, 65536 bytes: zero=65240 0xCC(parent fill)=1 other=295 (
[    1.2703] highest non-zero/non-CC at esp-468)
[    1.2758]   stack below entry esp, 1024 bytes: zero=700 0xCC(parent fill)=0 other=324 (hig
[    1.2798] hest non-zero/non-CC at esp-468)
[    1.2831] == entry end
[    1.2863] /probe
[    1.3013] fork
[    1.3046] == fork begin
[    1.3086] parent brk=0x0806e788 (134670216)
[    1.3127] &g_data (bss)=0x0807f840 (134740032)
[    1.3169] &g_below (data)=0x0804e72c (134539052)
[    1.3212] above(brk+0x10000)=0x0807e788 (134735752)
[    1.3250] far=0x20000000 (536870912)
[    1.3289] &stackvar=0x07ffff68 (134217576)
[    1.3333] belowesp(esp-0x2000)=0x07ffdf60 (134209376)
[    1.3373] child: fork ret=0 regs-preserved
[    1.3414] child sees g_data=0x00001111 (4369)
[    1.3455] child sees g_below=0x00001111 (4369)
[    1.3495] child sees above=0x00001111 (4369)
[    1.3535] child sees far=0x00001111 (4369)
[    1.3577] child sees stackvar=0x00001111 (4369)
[    1.3618] child sees belowesp=0x00001111 (4369)
[    1.3659] child brk(0)=0x0806e788 (134670216)
[    1.3827] child wrote 0x2222 everywhere; execve /probe child
[    1.3867] [child program] brk(0)=0x0806e788
[    1.3916] [child program] eflags after console writes=0x00000006 IF=0
[    1.3962] [child program] g_data (fresh image)=0x00000000 (0)
[    1.4010] [child program] value at far before write=0x00000000 (0)
[    1.4058] [child program] value at above before write=0x00000000 (0)
[    1.4105] [child program] g_below (fresh image)=0x00000077 (119)
[    1.4156] [child program] wrote 0x3333 to far, above, g_data, g_below; exit 42
[    1.4197] parent: fork ret=1 regs-preserved
[    1.4243] parent sees g_data (bss, above brk)=0x00003333 (13107)
[    1.4291] parent sees g_below (data, below brk)=0x00001111 (4369)
[    1.4332] parent sees above=0x00003333 (13107)
[    1.4372] parent sees far=0x00003333 (13107)
[    1.4414] parent sees stackvar=0x00001111 (4369)
[    1.4456] parent sees belowesp=0x00002222 (8738)
[    1.4501] parent brk(0) after child=0x0806e788 (134670216)
[    1.4552] waitpid(7,-1,&st,0) ret=0x00000000 (0) clobbered: esi->0x00021018
[    1.4710]   status=0x00002a00 (10752)
[    1.4747] parent: second fork ret=1
[    1.4794] wait4(114,-1,&st,0,0) ret=0x00000000 (0) regs-preserved
[    1.4831]   status=0x00000000 (0)
[    1.4885] waitpid(7,-1,&st,0) after wait4 ret=0x00000000 (0) clobbered: esi->0x00021018
[    1.5047]   status=0x00012c00 (76800)
[    1.5102] waitpid(7,-1,&st,0) child exit 0 ret=0x00000000 (0) clobbered: esi->0x00021018
[    1.5139]   status=0x00000000 (0)
[    1.5172] == fork end
[    1.5203] /probe
[    1.5361] execfork
[    1.5532] == execfork begin
[    1.5571] == entry begin (entry-forked)
[    1.5618]   eflags after a console write=0x00000006 IF=0
[    1.5655]   entry eax=0x00000000
[    1.5693]   entry ebx=0x00000000
[    1.5731]   entry ecx=0x00000000
[    1.5769]   entry edx=0x00000000
[    1.5806]   entry esi=0x00000000
[    1.5844]   entry edi=0x00000000
[    1.5881]   entry ebp=0x00000000
[    1.5919]   entry esp=0x07fffed0
[    1.5957]   entry eflags=0x00000046
[    1.5993]   entry cs=0x00000008
[    1.6031]   entry ss=0x00000010
[    1.6068]   entry ds=0x00000010
[    1.6104]   eflags.IF=0 IOPL=0
[    1.6137]   argc=5
[    1.6181]   argv[0]=0x300279a4 strlen=6 text='/probe'
[    1.6228]   argv[1]=0x300278a4 strlen=12 text='entry-forked'
[    1.6270]   argv[2]=0x300277a4 strlen=1 text='a'
[    1.6327]   argv[3]=0x300276a4 strlen=257 text='LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL..
[    1.6364] .' last 8='LLLLLLLa'
[    1.6407]   argv[4]=0x300275a4 strlen=2 text='zz'
[    1.6445]   argv[argc]=0x00000000
[    1.6485]   envp[0]=0x300274a4 'E2=two'
[    1.6524]   envp[1]=0x300273a4 'E1=one'
[    1.6564]   envp[2]=0x300272a4 'E0=zero'
[    1.6598]   envp count=3
[    1.6655]   stack words from esp: 0x00000005 0x300279a4 0x300278a4 0x300277a4 0x300276a4 0
[    1.6711] x300275a4 0x00000000 0x300274a4 0x300273a4 0x300272a4 0x00000000 0x000082ba 
[    1.6767]   stack below entry esp, 65536 bytes: zero=126 0xCC(parent fill)=65177 other=233
[    1.6809]  (highest non-zero/non-CC at esp-372)
[    1.6866]   stack below entry esp, 1024 bytes: zero=128 0xCC(parent fill)=600 other=296 (h
[    1.6904] ighest non-zero/non-CC at esp-436)
[    1.6937] == entry end
[    1.6975] parent: child status 0x00000000
[    1.7007] == execfork end
[    1.7037] /probe
[    1.7189] execoverlay
[    1.7342] == execoverlay begin
[    1.7379] == entry begin (entry-overlay)
[    1.7422]   eflags after a console write=0x00000006 IF=0
[    1.7456]   entry eax=0x00000000
[    1.7492]   entry ebx=0x00000000
[    1.7527]   entry ecx=0x00000000
[    1.7562]   entry edx=0x00000000
[    1.7597]   entry esi=0x00000000
[    1.7632]   entry edi=0x00000000
[    1.7667]   entry ebp=0x00000000
[    1.7702]   entry esp=0x07fffed0
[    1.7738]   entry eflags=0x00000046
[    1.7773]   entry cs=0x00000008
[    1.7807]   entry ss=0x00000010
[    1.7842]   entry ds=0x00000010
[    1.7876]   eflags.IF=0 IOPL=0
[    1.7907]   argc=5
[    1.7948]   argv[0]=0x30001300 strlen=6 text='/probe'
[    1.7994]   argv[1]=0x30001200 strlen=13 text='entry-overlay'
[    1.8035]   argv[2]=0x30001100 strlen=1 text='a'
[    1.8089]   argv[3]=0x30001000 strlen=257 text='LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL..
[    1.8125] .' last 8='LLLLLLLa'
[    1.8166]   argv[4]=0x30000f00 strlen=2 text='zz'
[    1.8203]   argv[argc]=0x00000000
[    1.8240]   envp[0]=0x30000e00 'E2=two'
[    1.8279]   envp[1]=0x30000d00 'E1=one'
[    1.8317]   envp[2]=0x30000c00 'E0=zero'
[    1.8350]   envp count=3
[    1.8405]   stack words from esp: 0x00000005 0x30001300 0x30001200 0x30001100 0x30001000 0
[    1.8459] x30000f00 0x00000000 0x30000e00 0x30000d00 0x30000c00 0x00000000 0x000082ba 
[    1.8514]   stack below entry esp, 65536 bytes: zero=126 0xCC(parent fill)=65177 other=233
[    1.8554]  (highest non-zero/non-CC at esp-372)
[    1.8609]   stack below entry esp, 1024 bytes: zero=132 0xCC(parent fill)=600 other=292 (h
[    1.8649] ighest non-zero/non-CC at esp-436)
[    1.8684] == entry end
[    1.8715] /probe
[    1.8876] files
[    1.8910] == files begin
[    1.8950] -- open missing
[    1.8994] open(/missing, O_RDONLY)=0xffffffff (-1)
[    1.9037] open(/missing, O_WRONLY)=0xffffffff (-1)
[    1.9081] open(/missing, O_RDWR|O_TRUNC)=0xffffffff (-1)
[    1.9128] open(/missing, O_WRONLY|O_CREAT|O_TRUNC)=0x00000004 (4)
[    1.9172] open(/nodir/x, O_WRONLY|O_CREAT)=0xffffffff (-1)
[    1.9214] open(/nodir/x, O_RDONLY)=0xffffffff (-1)
[    1.9259] open(/a/b/c, O_WRONLY|O_CREAT)=0xffffffff (-1)
[    1.9296] mkdir(/a)=0x00000000 (0)
[    1.9347] open(/a/b/c, O_WRONLY|O_CREAT) after mkdir /a only=0xffffffff (-1)
[    1.9393] mkdir(/a/b/c/d) (parents missing)=0xffffffff (-1)
[    1.9441] open(relname, O_WRONLY|O_CREAT) with cwd /=0x00000005 (5)
[    1.9481] access(/relname)=0x00000000 (0)
[    1.9524] open(/a/../relname, O_RDONLY)=0x00000005 (5)
[    1.9559] -- fd numbering
[    1.9596] first fd=0x00000005 (5)
[    1.9633] second fd=0x00000006 (6)
[    1.9678] after close(first), next open fd=0x00000005 (5)
[    1.9719] close(77) (never opened)=0x00000000 (0)
[    1.9763] read(77,...) (never opened)=0x00000000 (0)
[    1.9804] -- grow a file that is not the newest
[    1.9853]   /fa: open=5 len(SEEK_END)=10 read=10 bytes=[AAAAAAAAAA]
[    1.9900]   /fb: open=5 len(SEEK_END)=10 read=10 bytes=[BBBBBBBBBB]
[    1.9946] reopen /fa O_WRONLY (no O_CREAT)=0x00000005 (5)
[    1.9987] lseek(/fa,0,SEEK_END)=0x0000000a (10)
[    2.0026] write 'aaaaa'=0x00000005 (5)
[    2.0075]   /fa: open=5 len(SEEK_END)=15 read=15 bytes=[AAAAAAAAAAaaaaa]
[    2.0122]   /fb: open=5 len(SEEK_END)=10 read=10 bytes=[aaaaaBBBBB]
[    2.0160]  after creating /fc with CCCC:
[    2.0210]   /fa: open=5 len(SEEK_END)=15 read=15 bytes=[AAAAAAAAAAaaaaa]
[    2.0257]   /fb: open=5 len(SEEK_END)=10 read=10 bytes=[aaaaaBBBBB]
[    2.0302]   /fc: open=5 len(SEEK_END)=4 read=4 bytes=[CCCC]
[    2.0343] -- overwrite in place without O_CREAT
[    2.0390]   /fb: open=5 len(SEEK_END)=10 read=10 bytes=[bbaaaBBBBB]
[    2.0429] -- O_CREAT on an existing name
[    2.0469] open(/fb, O_CREAT) fd=0x00000005 (5)
[    2.0513]   /fb: open=5 len(SEEK_END)=0 read=0 bytes=[]
[    2.0551] -- lseek past end, then write
[    2.0593] lseek(fd,100,SEEK_SET)=0x00000064 (100)
[    2.0629] write 'X'=0x00000001 (1)
[    2.0671] lseek(fd,0,SEEK_CUR)=0x00000065 (101)
[    2.0712] lseek(fd,0,SEEK_END)=0x0000000b (11)
[    2.0766]   /fd: file index=16 address=0x54006fff length(table)=11 bytes at address+9..+11
[    2.0816] : 0x00000039 0x00000000 0x00000000 byte at address+100=0x00000058
[    2.0862]   next_file_address (0x8307)=0x5400700a (1409314826)
[    2.0910]   /fd: open=5 len(SEEK_END)=11 read=11 bytes=[0123456789\x00]
[    2.0959]   /fd: open=5 len(SEEK_END)=11 read=11 bytes=[0123456789\x00]
[    2.1003]   /fe: open=5 len(SEEK_END)=1 read=1 bytes=[e]
[    2.1041] -- lseek beyond end and read
[    2.1083] lseek(/fa,1000,SEEK_SET)=0x000003e8 (1000)
[    2.1119] read 4=0x00000000 (0)
[    2.1160] lseek(/fa,-5,SEEK_SET)=0xfffffffb (-5)
[    2.1204] read at end: lseek(0,SEEK_END)=0x0000000f (15)
[    2.1242] read 4 at EOF=0x00000000 (0)
[    2.1280] -- close and reopen, position
[    2.1315]   read 3 -> 3 'AAA'
[    2.1354]   lseek(SEEK_CUR)=0x00000003 (3)
[    2.1392]   reopen fd=0x00000005 (5)
[    2.1436]   lseek(SEEK_CUR) after reopen=0x00000000 (0)
[    2.1473]   read 3 -> 3 'AAA'
[    2.1524]   second simultaneous fd read 2 -> 'AA' (independent offset if 'AA')
[    2.1563] -- read sizes from a file
[    2.1612]   read(fd,buf,4096) on 15-byte file=0x0000000f (15)
[    2.1652] -- read/write on stdio fds
[    2.1687] e2
[    2.1728]   write(2,'e2\n',3)=0x00000003 (3)
[    2.1759] e0
[    2.1802]   write(0,'e0\n',3)=0x00000003 (3)
[    2.1842] -- chdir then relative open
[    2.1881]   mkdir(/w)=0x00000000 (0)
[    2.1920]   chdir(/w)=0x00000000 (0)
[    2.1963]   open(rel2,O_CREAT)=0x00000006 (6)
[    2.2004]   access(/w/rel2)=0x00000000 (0)
[    2.2046]   getcwd ret=0x0804e840 (134539328)
[    2.2078]   cwd='/w'
[    2.2121]   chdir(..) from /w=0xffffffff (-1)
[    2.2159]   cwd after chdir(..)='/w'
[    2.2200]   chdir(/) from /w=0xffffffff (-1)
[    2.2238]   cwd after chdir(/)='/w'
[    2.2287]   getcwd(buf,2) ret (buffer too small)=0x0804e840 (134539328)
[    2.2344]   buf after (was 0xee): 0x0000002f 0x00000077 0x00000000 0x00000000 0x000000ee 0
[    2.2385] x000000ee 0x000000ee 0x000000ee 
[    2.2422] == files end
[    2.2460] /probe
[    2.2642] ring
[    2.2678] == ring begin
[    2.2712] cs=0x00000008 (8)
[    2.2758] cs & 3 (CPL)=0x00000000 (0)
[    2.2806] eflags now=0x00000202 (514)
[    2.2853] IF now=0x00000001 (1)
[    2.2905] cr0 (readable => CPL 0)=0x00000011 (17)
[    2.2942] .
[    2.2997]   canary write(1,'.',1) console: deepest write below caller esp = 48 bytes, chan
[    2.3066] ged bytes=48 ret=0x00000001
[    2.3066] 
[    2.3121]   canary write(fd,'.',1) file: deepest write below caller esp = 40 bytes, change
[    2.3187] d bytes=40 ret=0x00000001
[    2.3187] 
[    2.3242]   canary brk(0): deepest write below caller esp = 20 bytes, changed bytes=20 ret
[    2.3302] =0x0806e788
[    2.3303] 
[    2.3355]   canary getpid (unimplemented): deepest write below caller esp = 12 bytes, chan
[    2.3420] ged bytes=12 ret=0x00000000
[    2.3420] 
[    2.3475]   canary open(/cfile,O_RDONLY): deepest write below caller esp = 72 bytes, chang
[    2.3541] ed bytes=72 ret=0x00000005
[    2.3541] 
[    2.3598]   canary access(/cfile): deepest write below caller esp = 56 bytes, changed byte
[    2.3663] s=56 ret=0x00000000
[    2.3663] 
[    2.3717]   canary getcwd(buf,256): deepest write below caller esp = 24 bytes, changed byt
[    2.3782] es=24 ret=0x0804e840
[    2.3782] 
[    2.3838]   canary lseek(fd,0,0): deepest write below caller esp = 20 bytes, changed bytes
[    2.3904] =20 ret=0x00000000
[    2.3904] 
[    2.3960]   canary read(fd,buf,1) file: deepest write below caller esp = 48 bytes, changed
[    3.2297]  bytes=48 ret=0x00000001
[    3.2353]   spin 1 (IF=1, 3147M tsc cycles, no syscall): deepest write below esp = 0, chan
[    3.9951] ged bytes=0
[    4.0006]   spin 2 (IF=1, 2869M tsc cycles, no syscall): deepest write below esp = 0, chan
[    4.7787] ged bytes=0
[    4.7840]   spin 3 (IF=1, 2938M tsc cycles, no syscall): deepest write below esp = 0, chan
[    5.5285] ged bytes=0
[    5.5339]   spin 4 (IF=1, 2811M tsc cycles, no syscall): deepest write below esp = 0, chan
[    5.5371] ged bytes=0
[    5.5404] == ring end
[    5.5434] /probe
[    5.5585] speed1m
[    5.5618] == speed begin
[    5.6415] SPD-WRITE-BEGIN n=1000000
[    5.6451] SPD-WRITE-END tsc=288537k
[    5.6489]   length=0x000f4240 (1000000)
[    5.7148] SPD-READ-BEGIN n=1000000
[    5.7188] SPD-READ-END tsc=236477k got=1000000
[    5.7848] SPD-NULL-BEGIN n=1000000
[    5.7884] SPD-NULL-END tsc=236437k
[    5.7919] SPD-CON-BEGIN n=2000
[    5.7972] ................................................................................
[    5.8025] ................................................................................
[    5.8079] ................................................................................
[    5.8132] ................................................................................
[    5.8186] ................................................................................
[    5.8241] ................................................................................
[    5.8294] ................................................................................
[    5.8347] ................................................................................
[    5.8400] ................................................................................
[    5.8453] ................................................................................
[    5.8506] ................................................................................
[    5.8559] ................................................................................
[    5.8612] ................................................................................
[    5.8665] ................................................................................
[    5.8719] ................................................................................
[    5.8772] ................................................................................
[    5.8825] ................................................................................
[    5.8878] ................................................................................
[    5.8931] ................................................................................
[    5.8984] ................................................................................
[    5.9038] ................................................................................
[    5.9091] ................................................................................
[    5.9144] ................................................................................
[    5.9197] ................................................................................
[    5.9278] ................................................................................
[    5.9278] 
[    5.9314] SPD-CON-END tsc=504767k
[    5.9346] == speed end
[    5.9378] /probe
[    5.9528] speed10m
[    5.9561] == speed begin
[    6.7192] SPD-WRITE-BEGIN n=10000000
[    6.7231] SPD-WRITE-END tsc=2880376k
[    6.7271]   length=0x00989680 (10000000)
[    7.3593] SPD-READ-BEGIN n=10000000
[    7.3634] SPD-READ-END tsc=2383079k got=10000000
[    7.9937] SPD-NULL-BEGIN n=10000000
[    7.9974] SPD-NULL-END tsc=2376875k
[    8.0009] SPD-CON-BEGIN n=2000
[    8.0063] ................................................................................
[    8.0116] ................................................................................
[    8.0170] ................................................................................
[    8.0224] ................................................................................
[    8.0278] ................................................................................
[    8.0332] ................................................................................
[    8.0386] ................................................................................
[    8.0439] ................................................................................
[    8.0493] ................................................................................
[    8.0547] ................................................................................
[    8.0601] ................................................................................
[    8.0655] ................................................................................
[    8.0708] ................................................................................
[    8.0762] ................................................................................
[    8.0816] ................................................................................
[    8.0870] ................................................................................
[    8.0924] ................................................................................
[    8.0978] ................................................................................
[    8.1031] ................................................................................
[    8.1085] ................................................................................
[    8.1139] ................................................................................
[    8.1192] ................................................................................
[    8.1246] ................................................................................
[    8.1300] ................................................................................
[    8.1382] ................................................................................
[    8.1383] 
[    8.1418] SPD-CON-END tsc=510070k
[    8.1450] == speed end
[    8.1481] /probe
[    8.1635] stdin
[    8.1668] == stdin begin
[    8.1719]   read(0,buf,64) ret=1 first byte=0x00000053 buf[1]=0x00000023
[    8.1772]   next bytes one call each (ret:byte): 1:0x00000054 1:0x00000044 1:0x00000049 1:
[    8.1826] 0x0000004e 1:0x0000002d 1:0x0000004d 1:0x00000041 1:0x00000052 1:0x0000004b 1:0x
[    8.1879] 00000045 1:0x00000052 1:0x0000002d 1:0x00000030 1:0x00000031 1:0x00000032 1:0x00
[    8.1933] 000033 1:0x00000034 1:0x00000035 1:0x00000036 1:0x00000037 1:0x00000038 1:0x0000
[    8.1971] 0039 1:0x0000000a 1:0x00000000
[    8.2003] == stdin end
[    8.2036] Build finished.
[    8.2072] ERROR: no hda writes!
boot.sh: pipeline exit 0
```

### boot B (`logs/boot-b.log`)

```
[    0.0768] Booting from Hard Disk...
[    0.0770] src
[    0.0828] /probe
[    0.0831] /probe
[    0.1202] irq
[    0.1207] == irq begin
[    0.1216] IDT base=0x00010000 (65536)
[    0.1226] IDT limit=0x000007ff (2047)
[    0.1252]   PIC at start: master IMR=0x000000b8 slave IMR=0x0000008e master IRR=0x00000010
[    0.9057]  master ISR=0x00000000
[    0.9081]   spin 1 (no EOI sent) IF=1 2957M tsc: IRQ0..7 counts: 1 0 0 0 0 0 0 0
[    0.9107]   PIC after spin 1: master IMR=0x000000b8 slave IMR=0x0000008e master IRR=0x0000
[    0.9116] 0011 master ISR=0x00000001
[    1.7402]   sent one non-specific EOI to the master PIC
[    1.7425]   spin 2 (after EOI) IF=1 3137M tsc: IRQ0..7 counts: 0 0 0 0 0 0 0 0
[    1.7451]   PIC after spin 2: master IMR=0x000000b8 slave IMR=0x0000008e master IRR=0x0000
[    1.7460] 0011 master ISR=0x00000001
[    1.7492] == irq end
[    1.7525] /probe
[    1.7698] forknoexec
[    1.7734] == forknoexec begin
[    1.7774] child (no execve): exiting 7
[    1.7806] /probe
[    1.7988] entry-shell
[    1.8028] == entry begin (entry-shell)
[    1.8075]   eflags after a console write=0x00000206 IF=1
[    1.8113]   entry eax=0x00000000
[    1.8156]   entry ebx=0x00000000
[    1.8192]   entry ecx=0x00000000
[    1.8228]   entry edx=0x00000000
[    1.8264]   entry esi=0x00000000
[    1.8300]   entry edi=0x00000000
[    1.8340]   entry ebp=0x00000000
[    1.8378]   entry esp=0x07ffffd0
[    1.8415]   entry eflags=0x00000246
[    1.8451]   entry cs=0x00000008
[    1.8487]   entry ss=0x00000010
[    1.8523]   entry ds=0x00000010
[    1.8557]   eflags.IF=1 IOPL=0
[    1.8589]   argc=2
[    1.8632]   argv[0]=0x30026d64 strlen=6 text='/probe'
[    1.8678]   argv[1]=0x30026c64 strlen=11 text='entry-shell'
[    1.8714]   argv[argc]=0x00000000
[    1.8747]   envp count=0
[    1.8801]   stack words from esp: 0x00000002 0x30026d64 0x30026c64 0x00000000 0x00000000 0
[    1.8856] x00008b8a 0x00008c45 0x00000080 0x00000000 0x00000000 0x0000012f 0x00008cfe 
[    1.8913]   stack below entry esp, 65536 bytes: zero=65277 0xCC(parent fill)=1 other=258 (
[    1.8956] highest non-zero/non-CC at esp-404)
[    1.9018]   stack below entry esp, 1024 bytes: zero=722 0xCC(parent fill)=0 other=302 (hig
[    1.9062] hest non-zero/non-CC at esp-436)
[    1.9096] == entry end
[    1.9136] Build finished.
[    1.9181] ERROR: no hda writes!
boot.sh: pipeline exit 0
```

### boot C (`logs/boot-c.log`)

```
[    0.0730] Booting from Hard Disk...
[    0.0732] src
[    0.0788] /probe
[    0.0790] /probe
[    0.1121] brkdown
[    0.1126] == brkdown begin
[    0.1136] brk(0)=0x0806e788 (134670216)
[    0.1161] bytes at 0x54000000 (first file, /probe): 0x0000007f 0x00000045 0x0000004c 0x000
[    0.1180] 00046 0x00000001 0x00000001 0x00000001 0x00000000
[    0.1205] pattern 0x5A over [brk, brk+1MiB); brk(brk-4096) next, target=0x0806d788 (134666
[   74.9856] 120qemu-system-x86_64: terminating on signal 15 from pid 51564 (timeout)
boot.sh: pipeline exit 0
```

### boot D (`logs/boot-d.log`)

```
[    0.0796] Booting from Hard Disk...
[    0.0816] src
[    0.0873] /probe
[    0.0875] /probe
[    0.1253] execmissing
[    0.1260] == execmissing begin
[    1.0575] child: access(/nonexistent)=-1; execve(/nonexistent) nexKVM internal error. Suberror: 1
[    1.0575] extra data[0]: 0x0000000000000000
[    1.0575] extra data[1]: 0x0000000000000400
[    1.0575] extra data[2]: 0x0000000100000019
[    1.0575] extra data[3]: 0x00000000f000f000
[    1.0575] extra data[4]: 0x0000000000000000
[    1.0575] extra data[5]: 0x0000000000000000
[    1.0575] emulation failure
[    1.0575] EAX=00000000 EBX=00000000 ECX=00000000 EDX=00000000
[    1.0575] ESI=00000000 EDI=00000000 EBP=00000000 ESP=07ffff24
[    1.0575] EIP=f000ff53 EFL=00000046 [---Z-P-] CPL=0 II=0 A20=1 SMM=0 HLT=0
[    1.0575] ES =0010 00000000 ffffffff 00c09300 DPL=0 DS   [-WA]
[    1.0575] CS =0008 00000000 ffffffff 00c09b00 DPL=0 CS32 [-RA]
[    1.0575] SS =0010 00000000 ffffffff 00c09300 DPL=0 DS   [-WA]
[    1.0576] DS =0010 00000000 ffffffff 00c09300 DPL=0 DS   [-WA]
[    1.0576] FS =0010 00000000 ffffffff 00c09300 DPL=0 DS   [-WA]
[    1.0576] GS =0010 00000000 ffffffff 00c09300 DPL=0 DS   [-WA]
[    1.0576] LDT=0000 00000000 0000ffff 00008200 DPL=0 LDT
[    1.0576] TR =0000 00000000 0000ffff 00008b00 DPL=0 TSS32-busy
[    1.0576] GDT=     00007f70 00000027
[    1.0576] IDT=     00010000 000007ff
[    1.0576] CR0=00000011 CR2=00000000 CR3=00000000 CR4=00000000
[    1.0576] DR0=0000000000000000 DR1=0000000000000000 DR2=0000000000000000 DR3=0000000000000000 
[    1.0576] DR6=00000000ffff0ff0 DR7=0000000000000400
[... the QEMU register dump continues; full text in the log file]
```

### boot E (`logs/boot-e.log`)

```
[    0.0738] Booting from Hard Disk...
[    0.0740] src
[    0.0797] /probe
[    0.0801] /nosuchprog
[    1.0218] arKVM internal error. Suberror: 1
[    1.0218] extra data[0]: 0x0000000000000000
[    1.0218] extra data[1]: 0x0000000000000400
[    1.0218] extra data[2]: 0x0000000100000019
[    1.0218] extra data[3]: 0x00000000f000f000
[    1.0218] extra data[4]: 0x0000000000000000
[    1.0218] extra data[5]: 0x0000000000000000
[    1.0218] emulation failure
[    1.0218] EAX=00000000 EBX=00000000 ECX=00000000 EDX=00000000
[    1.0218] ESI=00000000 EDI=00000000 EBP=00000000 ESP=07ffffd0
[    1.0218] EIP=f000ff53 EFL=00000246 [---Z-P-] CPL=0 II=0 A20=1 SMM=0 HLT=0
[    1.0218] ES =0010 00000000 ffffffff 00c09300 DPL=0 DS   [-WA]
[    1.0218] CS =0008 00000000 ffffffff 00c09b00 DPL=0 CS32 [-RA]
[    1.0218] SS =0010 00000000 ffffffff 00c09300 DPL=0 DS   [-WA]
[    1.0218] DS =0010 00000000 ffffffff 00c09300 DPL=0 DS   [-WA]
[    1.0218] FS =0010 00000000 ffffffff 00c09300 DPL=0 DS   [-WA]
[    1.0218] GS =0010 00000000 ffffffff 00c09300 DPL=0 DS   [-WA]
[    1.0218] LDT=0000 00000000 0000ffff 00008200 DPL=0 LDT
[    1.0219] TR =0000 00000000 0000ffff 00008b00 DPL=0 TSS32-busy
[    1.0219] GDT=     00007f70 00000027
[    1.0219] IDT=     00010000 000007ff
[    1.0219] CR0=00000011 CR2=00000000 CR3=00000000 CR4=00000000
[    1.0219] DR0=0000000000000000 DR1=0000000000000000 DR2=0000000000000000 DR3=0000000000000000 
[    1.0219] DR6=00000000ffff0ff0 DR7=0000000000000400
[    1.0219] EFER=0000000000000000
[    1.0219] Code=?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? <??> ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ?? ??
[... the QEMU register dump continues; full text in the log file]
```

### boot C monitor samples (`logs/boot-c-hmp.txt`)

```
--- info registers @ 11:32:46
ESI=00021000 EDI=c00f86a6 EBP=66666666 ESP=07ffff14
EIP=00008585 EFL=00000096 [--S-AP-] CPL=0 II=0 A20=1 SMM=0 HLT=0
--- xp /8bx 0x806d788 @ 11:32:47
0806d788: 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
--- xp /8bx 0x0806e788 @ 11:32:49
0806e788: 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
--- xp /8bx 0x806f788 @ 11:32:50
0806f788: 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
--- xp /8bx 0x08048000 @ 11:32:51
08048000: 0x7f 0x45 0x4c 0x46 0x01 0x01 0x01 0x00
--- xp /8bx 0x30000000 @ 11:32:52
30000000: 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
--- xp /8bx 0x54000000 @ 11:32:54
54000000: 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00
--- xp /8bx 0x7c00 @ 11:32:55
00007c00: 0x33 0xc0 0x8e 0xd8 0x8e 0xc0 0x8e 0xd0
--- info registers @ 11:33:27
ESI=00021000 EDI=c08cadbf EBP=66666666 ESP=07ffff14
EIP=00008585 EFL=00000086 [--S--P-] CPL=0 II=0 A20=1 SMM=0 HLT=0
```
