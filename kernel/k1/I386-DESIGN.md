# Running the junction's i386 stages without the host kernel: three designs

Status: option 3 is implemented with choice 1 (K0 writes the disk) as
`tests/tinycc/hex0-handoff-check.sh`; `tinycc/README.md` describes it.
What the implementation found that this text did not know is marked
"Measured since" below.  Written for review before any of it existed.  The measurements behind it are
in `kernel/k1/I386.md`.  The question is which kernel runs tcc-boot0,
tcc-boot1 and tcc-boot2 (i386, `int 0x80`, mes libc) once the x86-64 part
(seed Forth, the Forth compiler, the first tcc and its runs as `tcc-mes`)
has made tcc-boot0 and mes libc.

## What every design has to provide

**For the i386 stages** (`I386.md`): `int 0x80` with ten calls (exit 1,
read 3, write 4, open 5, close 6, unlink 10, lseek 19, brk 45, getcwd 183,
stat64 195); a loader for a two-segment static ELF32 at 0x08048000; the
Linux i386 argv/envp stack (no auxv); and the tree at live-bootstrap's
absolute paths, because getcwd's answer
`/steps/tcc-0.9.26/build/tcc-0.9.26-1147-gee75a10c` is written into
tcc-boot1 and tcc-boot2.

**For the script driver.**  pass1.kaem needs kaem and `catm`, `match`,
`mkdir`, `cp`, `chmod`, `rm`, `sha256sum`, `ungz`, `untar`, plus
live-bootstrap's `simple-patch` and `checksum-transcriber`.  A probe on
the host showed that the route's own first tcc builds working i386
versions of kaem (`vendor/mescc-tools/Kaem`) and the nine
mescc-tools-extra programs.  The probe linked against the mes libc the
junction leaves in `/usr/lib/mes` (rebuilt last by tcc-boot2, with
live-bootstrap's hashes), not the boot-1 copy `tcc-mes` makes; that
variant was not tried:

```
/tcc-first -static -L /usr/lib/mes -o kaem Kaem/kaem.c Kaem/variable.c \
    Kaem/kaem_globals.c M2libc/bootstrappable.c          # ELF 32-bit, i386
kaem --verbose --strict --file t.kaem    # set -ex, if match ...; then ... fi,
                                         # catm, sha256sum: rc=0
ungz --file h.gz --output h2             # matched gzip -d
untar --file t.tar                       # matched tar
```

Measured since: that `sha256sum` exits 0 but hashes every file as that
many zero bytes ("abc" gives `709e80c8…`, the sha256 of three NULs): it
reads with `fseek` to the end, `ftell`, `rewind`, `fread`, and the libc
pass1.kaem builds takes `rewind` from `stub/rewind.c`.  The one the final
tcc builds does the same; the first tcc's build was not tried on "abc".
The hand-off hashes boot 2's results on the host instead.

Traced, that kaem and those tools use 16 i386 calls: the ten above minus
stat64, plus fork 2, waitpid 7, execve 11, chdir 12, chmod 15, access 33
and mkdir 39.  With the stages' stat64 that is 17 for the whole i386
side.  So an i386 driver costs no seed-cc and no stage0-posix x86.

**Before the Forth segment** (shared by all three, not solved here).
The first tcc's sources must be unpacked and patched in the guest:
tcc-0.9.26 and pnut tarballs, live-bootstrap's two `tcctools.c`
simple-patches, `tinycc/patches/tcc-0.9.26/01-tinyc-version.diff`, and
mes-0.28 for the headers.  Today `tinycc/build-first-tcc.sh` does this
with host tar, gzip, python3 and patch.  Two ways to do it in the guest:
mescc-tools-extra's `ungz`/`untar` and `simple-patch` built by seed-cc
(what K1's smoke recipe does for kaem today), or the same sources built
by the Forth compiler in native mode with pnut's libc, as the first tcc
is.  A first try at the native-mode `ungz` stopped with cc error 93 (an
undeclared identifier, `cc/100-cc-expr.fth`); it was not pursued.  The
pivot's plan to delete seed-cc decides which of the two is available.

**K0 and the x86-64 part.**  K0 (`kernel/k0/k0.hex0`, 1,313 bytes then;
1,435 with the hand-off's two changes)
implements read, write, open, close, lstat, lseek, mmap, dup2, fork,
execve, exit, wait4, getcwd, chdir, rename, mkdir and unlink.  The x86-64
programs need:

- seed-forth building the first tcc: open, read, close, three anonymous
  mmaps (2, 8 and 9 MiB), one write, exit;
- the first tcc as `tcc-mes` (11 runs): read, write (727,345 calls, nearly
  all one byte), open with `O_RDONLY`, `O_WRONLY|O_CREAT|O_TRUNC` and
  `O_RDWR|O_CREAT|O_TRUNC`, close, lseek (SET, CUR, END), unlink (half
  ENOENT), exit.  No brk, mmap, stat or getcwd.  One `PT_LOAD` at
  0x400000, 26 MiB in memory; no path with `..`, `/./` or `//`.

(Since route/tinycc's merge the first tcc has Mes libc, whose malloc
calls brk; K0 gained it, 1,461 bytes.  Its remove also calls stat, which
K0 still lacks: tcc -ar leaves its .tmp file, outside boot 2's stream.)

K0 has every one of these, with the semantics used (O_CREAT, O_TRUNC,
ENOENT on a missing file, lseek's three origins, files grown by write).
K0's runner (`kernel/tools/amd64-runner.c`) already has `cd`, `copy`,
`mkdir`, `chmod`, `unlink`, sha256 pins and `run`, enough to drive the
`tcc-mes` lines of pass1.kaem.  What K0 lacks for this part is not a
system call but the unpacking tools above, and any way to write a disk
(it has no driver; its only output is the serial port).

## Option 1: dual-mode K1

Today's x86-64 K1 also runs 32-bit tasks.

What it takes, with what K1 already has:

- **Ambient.**  K1's GDT already holds a 32-bit user code descriptor at
  0x20 (`0x00CFFA000000FFFF`, "unused" in `main.c`), and STAR's SYSRET
  base is 0x23, so `sysretl` (`0f 07` without REX.W) would return to it.
  No GDT change.
- **Entry.**  One IDT gate at 0x80 with DPL 3, and a three-line stub in
  `k1-asm.fth` (`push $0; push $0x80; jmp isr_common`).  `trap_c` sends
  vector 0x80 to the i386 table; `isr_return`'s `iretq` restores CS 0x23.
  A process flag picks `sysretl` or `sysretq` (or `iret_frame`) when an
  exec'd i386 program first enters user mode: 3-6 lines of asm.
- **Calls.**  A table of the ten numbers onto existing handlers, taking
  ebx, ecx, edx; lseek's offset sign-extended from 32 bits; stat64
  written in the i386 layout (96 bytes).  K1 already has getcwd (x86-64
  79, `path_of`).  About 60 lines of C in `sys.c`.
- **Loader.**  An ELF32 branch in `load_elf` (about 40 lines), a 4-byte
  argv/envp stack (about 30), and for 32-bit tasks a stack top and mmap
  top below 4 GiB (about 15).

New code: about 150-200 lines of C and under 10 lines of `k1-asm.fth`,
then a recipe that builds the driver with seed-cc (the smoke recipe's
pattern) and runs pass1.kaem in one QEMU run.  K1's sha256 and README
pin move.

Deleted: nothing.  K1 (4,481 lines of C, 470 of `k1-asm.fth`) stays, and
with it what builds K1: seed-cc's layers (`kernel/k1/boot/unit.fth`),
`kernel/tools/obj-asm.fth`, the linker `cc/140-cc-link.fth`.  That is the
System V back end and object path the pivot wants to delete.

Trust and review: reviewers already read K1 for the direct route; the
addition is small and local.  But the i386 stages would then rest on a
4,500-line C kernel compiled by the seed's C compiler, where
live-bootstrap uses a 3.5 KiB hex0 kernel.

Risks: low technically (one QEMU run, K1's FPU, fault and timer paths
unchanged; existing x86-64 programs unaffected if the flag defaults to
64-bit).  The cost is strategic: it ties the TinyCC route to K1 and to
seed-cc.

## Option 2: an i386-only kernel built by the first tcc

A 32-bit protected-mode kernel whose only job is the i386 chain,
compiled by the route's own first tcc (an x86-64 program whose target is
i386) under K0.

**K0's part.**  As above, K0 runs seed Forth, the first tcc and every
`tcc-mes` line with the system calls it has.  The first tcc also builds
the i386 kaem and tools (shown to work) and the kernel itself.

**Hand-over, one QEMU boot, no disk.**  K0 runs a program by copying its
`PT_LOAD`s and jumping to it in ring 0, still in long mode, with the
first 4 GiB identity-mapped; that is how K1 starts.  The i386 kernel
would be wrapped as an ELF64 whose entry is a 64-bit stub of about 15
instructions: load a GDT with a 32-bit code segment, far-jump into it,
clear CR0.PG, clear EFER.LME, load the data segments and jump to the
kernel.  It runs from identity-mapped memory, so turning paging off is
safe.  K0's loader reads ELF64 headers only (phdrs at offset 64,
`e_phnum` at 56), so tcc's ELF32 cannot be handed to it directly: tcc's
output would be linked flat (`-nostdlib -static -Wl,-Ttext=...`) and the
wrapper's header and stub written by a few lines of Forth or a runner
verb.  The kernel then imports K0's file table from 0x50000000 as K1
does today.

The other hand-over is a second QEMU boot: `-kernel` with a multiboot
header puts the CPU in 32-bit protected mode, which is how K0 itself
starts (`start32` in `k0.hex0`), so the kernel needs no mode switch.  But
then boot 1's files have to leave K0, which has no disk driver, and the
i386 kernel has to read them back: the same export problem as option 3
below, plus an IDE read in the new kernel.  The one-boot drop is the
cheaper of the two.

**What the kernel contains.**  No paging and no scheduler: every program
the chain runs is an ET_EXEC at 0x08048000, and only kaem forks, each
time to exec and wait.  fork can save the parent's image and stack and
run the child to completion, as K0 and builder-hex0 both do.  Parts:

| part | from K1 | estimate |
|---|---|---:|
| boot: GDT, IDT (0x80 and faults), serial, import of K0's files | `main.c` 517 | 150 |
| files: tree, path walk, fds, getcwd, chdir, mkdir, unlink, stat64 | `fs.c` 719 | 300 |
| processes: ELF32 load, i386 stack, fork snapshot, exec, wait, brk | `proc.c` 778, `mm.c` 599 | 250 |
| the 17 calls | `sys.c` 1,208 | 150 |
| assembly: int 0x80 entry and `iret`, `lgdt`/`lidt`, `in`/`out`, `rep movs` | `k1-asm.fth` 470 | 40-60 |

About 850 lines of C and 50 of assembly, plus the 64-bit stub as bytes.
tcc 0.9.26's i386 assembler encodes what the kernel needs (`i386-asm.h`
has `cli`, `sti`, `hlt`, `iret`, `lret`, `ljmp`, `lgdt`, `lidt`, `ltr`,
`in`/`out`, moves to and from CR registers, `fxsave`), so the assembly
can be a `.S` file or inline `asm` that tcc builds.  A probe confirmed
it: `tcc-first -c` on a `.S` with `cli`, `sti`, `hlt`, `lgdt`, `lidt`,
`ltr`, moves to and from CR0/CR2/CR3, `inb`/`outb`, `rep movsb`/`stosb`,
`iret`, `lret`, `ljmp $0x08,$0x1000`, `fxsave`/`fxrstor`, `int $0x80`,
`rdmsr` and `wrmsr` gave a `.text` byte-identical to `as --32`'s.

The compiler has to be the first tcc, since tcc-boot0 does not exist
until the first tcc has built it, and the kernel must be built before
boot 1 ends.  The first tcc is built with `HAVE_LONG_LONG 0` and without
`HAVE_FLOAT` or `HAVE_BITFIELD` (`tinycc/direct-input.c`), which in
janneke's fork may restrict what it compiles correctly; the kernel's C
should keep to `int`, `long` and pointers, with no `long long`, floating
point or bit-fields.  `k1-asm.fth` would
become that file, and an `asm-check` would compare tcc's object with
`as --32`.  The 64-bit stub cannot be assembled by an i386 assembler;
it would stay as hex bytes with comments.

Deleted: if the pivot also retires the direct-GCC chain, all of K1 and
its build (about 5,000 lines of C and assembly, `kernel/k1/boot/`,
`kernel/tools/obj-asm.fth`, `k1-direct*.recipe`, the disk writers), and
the kernel no longer needs seed-cc.  If the direct chain stays, this is a
second kernel next to K1.

Trust and review: a new kernel, smaller than K1, compiled by a compiler
that the route already trusts for everything after it.  Reviewers have
to read 900 new lines that do what builder-hex0 already does for
live-bootstrap.

Risks: medium.  The 64-to-32 drop and the fork snapshot are small but
must be right first time with no debugger.  tcc 0.9.26 compiling a
kernel is less tested than compiling the boot stages.  Everything stays
in one QEMU run and below 4 GiB.

## Option 3: live-bootstrap's builder-hex0

builder-hex0 (`ironmeld/builder-hex0`, live-bootstrap's submodule at
a278124) is a 32-bit kernel of about 2,400 lines of commented hex0 (3.5
KiB) that live-bootstrap boots first in its kernel-bootstrap mode.  Its
manifest runs `checksum-transcriber-1.0`, `simple-patch-1.0`, `mes-0.28`,
`tcc-0.9.26`, `tcc-0.9.27`, then builds Fiwix, lwext4 and kexec-fiwix
and jumps to Fiwix, all under builder-hex0.  So these exact tcc steps
already run on it and reach the checksums the junction compares.

**System calls.**  Its dispatcher (`builder-hex0.hex2`,
`syscall_interrupt_handler`) handles exit 1, fork 2, read 3, write 4,
open 5, close 6, waitpid 7, execve 11, chdir 12, lseek 19, access 33,
mkdir 39, brk 45, wait4 114 and getcwd 183, and answers 0 to every other
number.  Against the measured list:

- the i386 stages' ten: eight handled; unlink 10 and stat64 195 return 0
  without doing anything.  That is enough because opening an existing
  file for writing makes a new file there, and mes `remove()` only tests
  `st_mode` of a struct stat64 that is left as it was (either branch then
  returns 0);
- the i386 kaem and tools' 16: also covered (chmod 15 returns 0);
- getcwd copies the process's directory, so `-g` records the same path.

**Disk format.**  It boots from a BIOS disk: sector 0 is the
`builder-hex0-x86-stage1.hex0` binary (a 192-byte-code MBR), followed by
the stage-2 hex0 source, which stage 1 compiles at boot, padded to a
sector.  From sector 175 (0xAF in stage 2; the two stages fill 175
sectors) the kernel reads a text stream as a shell's
stdin: `src 0 DIR` makes a directory, `src N PATH` followed by N bytes
makes a file, `hex0 IN OUT` assembles, and any other line runs a program
with at most one argument.  live-bootstrap's `lib/generator.py`
(`create_builder_hex0_disk_image`, `append_srcfs`) writes it: every file
of the tree, then the lines that start kaem.  It needs BIOS int 13h
(LBA read/write) and int 10h; live-bootstrap starts it with
`qemu -enable-kvm -m ... -drive file=X.img,format=raw -nographic` and
its console is BIOS int 10h teletype.  Whether that output reaches a
serial log under QEMU (SeaBIOS's serial console) was not checked here;
the boot-2 checks need some way to report, or a final `f` flush of a
result file to the disk.

Measured since: with `-nographic` SeaBIOS copies int 10h output to the
serial port, so the console reaches QEMU's stdout (wrapped at 80
columns).  live-bootstrap's own kernel-bootstrap disk, written by their
`Generator` with the manifest cut after `build: tcc-0.9.26`, ran from
hex0 through stage0-posix, mes-0.28 and tcc-0.9.26 in 5 min 56 s under
KVM and printed `OK` for all ten lines of tcc-0.9.26.x86.checksums.  When
the stream ends builder-hex0 writes the file `/dev/hda`, if one exists,
to the disk from sector 0 and reboots; the hand-off exports its results
that way.  kaem's `cd /` fails under builder-hex0 ("cd failed!").

**Could a K0 run write it?**  The stream is trivial to produce (`src N
path\n` and the bytes), and the stage-1 binary can be assembled under K0
by `hex0-seed` from the hex0 text, as K0 already does for
`seed/000-seed.hex0`.  What K0 cannot do is put it on a disk.  Two
choices:

1. A new K0 system call that writes a memory range to the IDE disk by
   PIO: about 25 instructions in `k0.hex0` (K1's `ata.c` shows
   the port sequence).  Boot 1 then writes the boot-2 disk itself, and
   the same image file is the drive in both boots.
2. No K0 change: a program writes the stream to stdout, which under K0
   is the serial port, with everything else redirected to files; QEMU's
   `-serial file:` captures it and the host concatenates it after the
   stage-1/stage-2 bytes.  The host then copies guest output into the
   next guest's input, which the K1 route has not needed so far; the
   guest prints the stream's sha256 and the host and boot 2 check it.

Measured since: choice 1 took 42 instructions and a table entry (call
248 takes an fd, not a memory range: the file's data and size are in
K0's file table).  A second K0 change was needed: K0 did not clear a
new program's stack, and the first tcc's `-g` reads its getcwd buffer
although pnut's getcwd fails and leaves it unwritten, so tcc-boot0
recorded four bytes of an earlier program's stack ("qm\xa3\xe7/" for
"/") and was `f0327572…`, not `4e3e525a…`.  K0's execve now zeroes the
8 MiB below the new stack (4 instructions).  K0 also does not resolve
`..`, which kaem's `#include "../M2libc/bootstrappable.h"` needs; the
boot-1 recipe copies the header to the literal name tcc asks for.

**Two-boot hand-over.**

- Boot 1, QEMU with `-kernel k0.bin` and the drive: K0 runs `hex0-seed`,
  seed Forth, the first tcc, the unpacking (see "Before the Forth
  segment"), every `tcc-mes` line of pass1.kaem (crt1/crti/crtn,
  `libc.a`, `libtcc1.a`, `libgetopt.a`, tcc-boot0), the i386 kaem and
  tools, and writes the disk: builder-hex0 stage 1 and 2, then the
  stream holding `/steps`, the unpacked trees, `/usr/bin/tcc-boot0`,
  `/usr/lib/mes/*`, the i386 tools, and a kaem script that is the rest of
  pass1.kaem from `cp tcc-boot0 ${BINDIR}/` on.
- Boot 2, QEMU with only the drive (SeaBIOS boots its MBR): builder-hex0
  imports the stream and starts kaem (with no argument it reads
  `kaem.run`), which runs boot1, boot2 and the libraries and checks them
  with `sha256sum -c`: live-bootstrap's lines for tcc-boot1, tcc and the
  six libraries, this route's pins for tcc-mes and tcc-boot0.  From here
  live-bootstrap's own manifest could continue unchanged: tcc-0.9.27,
  Fiwix, kexec-fiwix.

The host starts QEMU twice and, in choice 2, concatenates bytes.

New code: no kernel code beyond the optional K0 PIO write (about 25
instructions).  A boot-1 recipe (about 60 lines), a stream writer (a
runner verb or a small program, about 50 lines), the boot-2 kaem script
(about 80 lines, mostly live-bootstrap's text), the two-boot driver
script (about 40 lines of sh), and a pin for builder-hex0 (it is a
submodule: the pinned live-bootstrap tarball has an empty
`builder-hex0/`).

Deleted: the same as option 2 (all of K1, if the pivot retires the
direct chain), with no new kernel in its place.

Trust and review: the i386 stages run on the kernel live-bootstrap
already uses for them, so a reviewer from that community sees nothing
new under the i386 stages.  What they would check is the hand-over: the
files boot 1 puts on the disk are binaries made by the Forth-built tcc,
exactly the trust the junction already claims, and in choice 2 the host
copies them.  Reviewers would also see that builder-hex0's unlink and
stat64 are no-ops, which live-bootstrap already depends on.

Risks: builder-hex0's limits (one child at a time, 670 MiB per process,
1.8 GB of files in total, file names under 1 KiB, a one-argument shell)
are far above what these stages use (19 MiB heap, a few MB of files).
The new work is in boot 1 and the disk writer.  Two QEMU runs instead of
one.

## Comparison

| | 1: dual-mode K1 | 2: i386-only kernel | 3: builder-hex0 |
|---|---|---|---|
| new kernel code | ~150-200 C, <10 asm (K1) | ~850 C, ~50 asm, stub bytes | none, or ~25 instructions in K0 |
| other new code | recipe, driver built by seed-cc | wrapper, recipe | stream writer, recipes, two-boot script |
| QEMU runs | 1 | 1 | 2 |
| host role | write the input disk | write K0's image (as today) | start QEMU twice (and, choice 2, copy the stream) |
| needs seed-cc | yes (K1 and the x86-64 driver) | no | no |
| deletable after | nothing | K1, if the direct chain goes | K1, if the direct chain goes |
| kernel under the i386 stages | K1, 4,500 lines of C | new, ~900 lines | live-bootstrap's own, 3.5 KiB of hex0 |
| reviewer burden | small diff, large existing base | a new kernel | the hand-over only |

## Recommendation

Option 3, with K0's PIO write (choice 1).  It adds the least code,
nothing under the i386 stages that live-bootstrap does not already run,
and leaves the route at the point where live-bootstrap's own kernel
bootstrap continues to Fiwix, so the junction stops being a replay and
becomes the real thing.  It also lets K1 and seed-cc go if the pivot
retires the direct chain.

Option 1 is the right choice only if K1 and the direct-GCC chain stay
regardless: then 200 lines buys a one-boot junction with no new
dependency.  Option 2 sits between them and is hard to justify while
builder-hex0 exists, unless a single QEMU run matters more than reusing
reviewed code.

All three still need the unpacking step in the guest before the Forth
segment; that should be settled first, because it decides whether
seed-cc can go at all.

A fourth possibility, not costed here: K0 itself could learn i386 tasks
(an IDT with a 0x80 gate, a compatibility-mode code segment, an ELF32
loader, brk, stat64).  K0 is hex0, so that is a few hundred bytes of new
hex in the route's first kernel.
