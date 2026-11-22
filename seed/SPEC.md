# SEED-SPEC: the Forth seed for builder-hex0, `seed/000-seed.hex0`

Specification of the seed, `seed/000-seed.hex0` (1,191 bytes when
assembled). It was written before the seed, for an implementer who had
seen no seed: it describes what the seed must do and every interface
another file depends on, and nothing of how to do it. The seed was then
written from it. `./check-all.sh` runs the checks of section 13 as steps
01 to 03, 09, 14 and 15.

The seed is the first program of the route: one boot of builder-hex0
from sources to live-bootstrap's tcc. `forth/CONTRACT.md` specifies the
Forth files that are loaded on top of this seed, and the boot.

An earlier seed, for x86-64, with its own library and specification, is
at tag `experiments-2026-11-21`. This document mentions it only where it
explains a choice made here.

Conventions:

- MUST marks something a dependent or a check relies on. FREE marks a
  choice the implementer owns.
- "Cell" is 8 bytes, little-endian: the low 32 bits at the lower address.
  "Low half" and "high half" are those two 32-bit words. Cells are 64-bit
  although the processor is in 32-bit mode: the library and the compiler
  were written for 64-bit cells, on the x86-64 seed of tag
  `experiments-2026-11-21`, and keep their text and their arithmetic.
- Paths are relative to the repository root. A file with a word's name
  in parentheses names the dependent that forces a detail.
- `B2:<line>` cites builder-hex0's stage 2,
  `build-out/tinycc-inputs/builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a/builder-hex0-x86-stage2.hex0`.
- `P§n` cites section n of the measured kernel behaviour,
  `tests/builder-hex0/README.md` (the facts used here are also restated in
  section 10).
- **[measured]** marks a number or behaviour observed in a run made for
  this document (Appendix C); **[designed]** marks a choice made here
  before the seed existed. Section 13 says which checks exercise the seed
  now, and 13.4 what none of them does.

## 1. What the seed is

A static i386 ELF executable, written as commented hex0. It is a minimal
Forth: it reads whitespace-separated tokens from one named file, executes
or compiles the words they name, and accepts unsigned decimal numbers. It
has exactly 21 named words. Everything else is Forth text.

    seed-forth FILE [ARG ...]

The seed opens FILE and reads only it. It never reads standard input: on
builder-hex0, descriptor 0 is the boot disk's command stream, one byte per
call and no end of file (P§5, B2:1335). It does not look at ARG; it leaves
the argument vector where the library can find it (section 3.3).

It is assembled twice from the same source:

- on the host by stage0-posix's `hex0-seed`
  (`vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed`), into
  `./seed-forth`, by `seed/build.sh`;
- in the boot by builder-hex0's built-in `hex0` command (B2:2237-2393),
  as live-bootstrap's `lib/generator.py:208-233` has it assemble
  `hex0-seed` and `kaem-optional-seed`.

It runs on two kernels, and MUST use only what both provide:

- Linux, through its IA32 support (the acceptance runs on the host);
- builder-hex0, where every program runs in ring 0 with no paging (P§6).

What both provide, and all the seed may use:

- `int 0x80` with eax = the call number, arguments in ebx, ecx, edx, esi,
  edi, ebp, and the result in eax;
- for its own needs five calls: `exit` (1), `read` (3), `write` (4),
  `open` (5), `brk` (45). Not `exit_group` (252): builder-hex0 answers it
  with 0 and carries on (P§1).

## 2. The ELF32 image

One ELF32 header (52 bytes) directly followed by one program header (32
bytes), then the program. No section headers. 84 bytes in 28 fields.

| field | value | why |
|---|---|---|
| `e_ident` | `7F 45 4C 46`, class 1 (32-bit), data 1 (LSB), version 1, OS ABI 0, rest 0 | Linux |
| `e_type` | 2 (`ET_EXEC`) | Linux |
| `e_machine` | 3 (`EM_386`) | Linux |
| `e_version` | 1 | convention |
| `e_entry` | 0x08048000 + offset of the entry code | builder-hex0 jumps to the word at file offset 0x18 (B2:1736, 1786-1795) |
| `e_phoff` | 52 | builder-hex0 adds the word at 0x1C to the file address (B2:1737) |
| `e_shoff`, `e_flags` | 0 | |
| `e_ehsize` | 52 | |
| `e_phentsize` | 32 | Linux requires it; builder-hex0 steps by 0x20 without reading it (B2:1747) |
| `e_phnum` | 1 | builder-hex0 copies every program header's bytes whatever its type (B2:1739-1749) and takes the break from the last (B2:1767) |
| `e_shentsize`, `e_shnum`, `e_shstrndx` | 0 | |
| `p_type` | 1 (`PT_LOAD`) | Linux; builder-hex0 does not read it |
| `p_offset` | 0 | the checker takes file offset N as address 0x08048000 + N |
| `p_vaddr`, `p_paddr` | 0x08048000 | builder-hex0 zeroes the process area from 0x08048000 (B2:1723-1724) and nothing below it; 0x400000 lies in its file-name table (B2:66-83) |
| `p_filesz` | the file's size in bytes | builder-hex0 copies exactly this many bytes (B2:1744-1745) |
| `p_memsz` | 0x02000000 (32 MiB) | section 3 |
| `p_flags` | 7 (R, W, X) | the dictionary is code written at run time, and the library patches code inside the file image (section 7.7) |
| `p_align` | 0x1000 | Linux requires vaddr and offset congruent modulo the alignment |

MUST: exactly one program header, and the file MUST be at most 4096
bytes, so that it ends below 0x08049000 (section 3).

`p_memsz` and `p_filesz` mean different things to the two kernels:

- Linux maps 32 MiB at 0x08048000, the file's bytes first and zeros
  after, and starts the break at or above the end, 0x0A048000.
- builder-hex0 ignores `p_memsz`. It zeroes 0x26FB8000 bytes from
  0x08048000 on every `execve` (B2:1723-1724), copies `p_filesz` bytes,
  and starts the break at 0x08048000 + `p_filesz` + 0x20000 (B2:1767;
  measured, P§2: file end 0x0804dca8, break 0x0806dca8). Memory above the
  break is plain RAM that reads and writes (P§2).

So on both kernels every byte from the end of the file to 0x0A048000
reads as zero at entry. On builder-hex0 the break starts about 28 MiB
below the image's end, inside the dictionary space, and growing the break
zeroes everything from the old break to the new (B2:1435-1441, P§2).
Section 3.2 deals with that.

Why 32 MiB: the library never asks the kernel for the megabyte buffers it
creates in the dictionary (`cc/030-cc-io.fth`: the input, source and
output buffers). When the size was chosen, the compile of the first tcc
on the x86-64 seed of that tag left HERE 9.01 MiB above its load address
**[measured]** (Appendix C), and this seed's compiled calls and returns
are longer (section 8). With this document's layout the same compile
ended 9.00 MiB above the initial HERE **[measured]**
(`forth/CONTRACT.md`, section 9).
32 MiB costs nothing on Linux and about 18 ms of zeroing on builder-hex0
(2.1 cycles per byte, P§2).

Zero fill is an interface: the library relies on untouched memory reading
as zero. The seed MUST NOT write anywhere outside the regions of section
3, and within the dictionary space only at HERE, where section 8 says so.

## 3. Memory map

| address | what | status |
|---|---|---|
| 0x08048000 | the file image: headers, code, the 21 dictionary headers; at most 4096 bytes | MUST |
| 0x08049000 to 0x08059000 | the data stack's 64 KiB; it grows down from 0x08059000, and the first cell pushed is at 0x08058FF8 | MUST |
| 0x08059000 | the sysvar page (`state` returns this address) | MUST, section 3.3 |
| 0x0805A000 | initial HERE: the first free dictionary byte, growing up | MUST |
| 0x0A048000 | the end of the image | MUST |
| kernel-provided | the return stack is the process stack the kernel hands over in esp | MUST |

### 3.1 Dictionary space and the data stack

Everything fixed sits below initial HERE, so the dictionary grows upward
with nothing in its way until the image's end. Initial HERE MUST be
exactly the sysvar page's address plus 4096. No word of the library moves
HERE past the stack or the sysvar page: `cc/030-cc-io.fth` creates its
megabyte buffers at HERE as soon as it is loaded, and relies on the
layout having put HERE above both already.

The data stack has no overflow or underflow checks and needs none. 64 KiB
is 8,192 cells.

### 3.2 The break

On entry, before it executes or compiles any token, the seed MUST make
the break at least 0x0A048000:

1. call `brk` with ebx = 0, which returns the current break;
2. if the result, compared unsigned, is below 0x0A048000, call `brk`
   with ebx = 0x0A048000.

Why, on builder-hex0:

- The break starts at 0x08068000 plus the file's size. The first `brk`
  the library makes would otherwise zero from there upward, through
  whatever the dictionary held (growth zeroes from the old break,
  B2:1435-1441).
- At entry nothing lies above the old break, so this one growth zeroes
  only zeros.
- `fork` saves a process's memory only up to its break (B2:1571-1582,
  P§3). With the break at the image's end the whole dictionary is saved.

Why compare first: a request below the current break never returns on
builder-hex0. Its loop zeroes memory until the address wraps and wipes
every file within seconds (B2:1435-1441; P§2, boot C). On Linux the
break starts at or above 0x0A048000, so the second call is never made
there. The seed MUST NOT call `brk` anywhere else.

### 3.3 The sysvar page

`state` pushes the address of the page, 0x08059000. The first six cells
are an interface, in this order, 8 bytes each:

| offset | name | content | depended on by |
|---|---|---|---|
| +0 | STATE | 0 interpreting, 1 compiling | `forth/010-lib.fth` (`constant`, `create`, `defer`, `interpret`, `hex-lay`) and `forth/020-cc-arena.fth` (`code:`, `compiling?`); the library stores a whole cell of 0 |
| +8 | LATEST | address of the newest dictionary header | `forth/010-lib.fth` (`latest`, `immediate`); `forth/020-cc-arena.fth` (`fh-find`) |
| +16 | HERE | address of the first free dictionary byte | `forth/010-lib.fth` (`here-addr`, `here`, `,`, `c,`, `allot`, `native!`); `forth/020-cc-arena.fth` (`rel32!`) |
| +24 | LAST_FOUND | address of the header `find` matched last | `forth/010-lib.fth` (`found-immediate?`: `latest 16 +`); `forth/020-cc-arena.fth` (`fh-find` stores it) |
| +32 | INPUT | the file descriptor `key` reads | the library's `included` and `file-key` (`forth/CONTRACT.md`, section 6) |
| +40 | ARGV | address of the kernel's `argv[0]` slot: the entry esp plus 4 | the library's `arg` (the same) |

Rules for all six:

- The library reads and writes them as full cells with `@` and `!`. The
  seed MUST leave every one a clean cell: the value in the low half, 0 in
  the high half. Zero fill provides the high halves; the seed may write
  low halves only.
- The seed MUST read STATE, LATEST, HERE and INPUT from memory each time
  it needs them. The library changes all four behind its back.
- STATE and LAST_FOUND start as 0. INPUT is set once, to the descriptor
  `open` returned for FILE. ARGV is set once and never read by the seed.
- A value in an address cell is at most 32 bits. ARGV's can be above
  2^31 on Linux, where the stack is near 0xFFFFD000: it MUST be stored
  zero-extended, not sign-extended.

The rest of the page:

- Everything the seed keeps in memory besides the two stacks (the token
  buffer, a byte to read into, any other variable) MUST lie inside
  [0x08059000 + 48, 0x08059000 + 400).
- The bytes from `state` + 400 to the end of the page are free for
  tests (`tests/seed/test.sh` uses +400, and bytes and cells from +500
  and from +600).
- The token buffer needs 258 bytes: 256 for the longest token the fatal
  message prints, 2 for `?` and newline. The library also writes into the
  two bytes after a token of up to 255 bytes: `unknown` puts `?` and a
  newline there and `include` a NUL (`forth/010-lib.fth`). Its
  placement is FREE within the first rule: nothing learns its address
  except from `token`.

## 4. Registers, cells and the entry state

### 4.1 Register roles

| register | role |
|---|---|
| edx:eax | the top of the data stack (TOS): eax the low half, edx the high half |
| esi | the data-stack pointer. `[esi]` and `[esi+4]` are the low and high halves of the second item, `[esi+8]` and `[esi+12]` those of the third. A push subtracts 8 |
| esp | the return stack: the processor's stack. Section 5 |
| ebx, ecx, edi, ebp | scratch |

These roles are the interface to every piece of machine code the library
and the compiler lay down themselves
(`forth/CONTRACT.md`, section 4, lists the bytes), so they are MUST at every
boundary between the seed and a dictionary word: on entry to a word, on
return from one, and around the seed's calls to `key`, `token` and `find`.

- With an empty data stack edx:eax holds nothing meaningful.
- No register holds the sysvar page: the sysvars are reached by absolute
  address.
- What the seed may assume of code it reaches through a dictionary entry:
  esi and esp are as the stack effect says, edx:eax is the new TOS, and
  ebx, ecx, edi and ebp may have changed. What code calling a seed word
  may assume is the same and no more.
- The direction flag is clear on entry on both kernels (Linux's ABI;
  builder-hex0's entry eflags were 0x246 and 0x46, P§4). It MUST be clear
  whenever control leaves the seed for a dictionary word or the kernel.
- Nothing may be kept below esp at any time. A system call on
  builder-hex0 writes up to 72 bytes below the caller's esp (`open`,
  P§6), because the interrupt frame and the handler's pushes land on the
  program's own stack.
- The seed MUST NOT assume that `int 0x80` preserves ebx, ecx, edx, esi,
  edi or ebp. builder-hex0 returns from a write to a file, `chdir` and
  `access` with ebx changed, and from `waitpid` with esi changed (P§1).
  Whatever the seed needs after a call it saves on the return stack
  first, or reloads.

### 4.2 Cells in registers and memory

- A cell on the data stack or in memory is 8 bytes, low half first.
- An address, a length, a descriptor or a flag travels as a cell. A word
  that takes an address uses the low half only and ignores the high half.
  A word that produces an address, a byte or a count produces it with the
  high half 0.
- Arithmetic is on all 64 bits and wraps (section 7.1).

### 4.3 Entry

At the entry point esp points at the kernel's argument block: `argc` (4
bytes), then the 4-byte pointers `argv[0]`, `argv[1]`, ..., then a null
pointer. Both kernels lay it out so (P§4). The general registers hold
nothing the seed may rely on. The stack below and above the block is not
zeroed on builder-hex0 (P§4): the seed MUST read nothing from the stack
that it did not put there, except `argc` and `argv[1]`.

The seed then, in an order that respects section 3.2:

1. raises the break (section 3.2);
2. stores the entry esp plus 4 in ARGV;
3. exits with status 1 if `argc` is less than 2;
4. opens `argv[1]`: `open` with ebx = the pointer, ecx = 0 (read only),
   edx = 0. A result with the sign bit set is a failure (Linux returns a
   negative errno, builder-hex0 returns -1, B2:1060-1063 and P§5): exit with
   status 1. Otherwise the result goes into INPUT;
5. sets esi to 0x08059000, HERE to 0x0805A000 and LATEST to one of its
   headers (section 6.2), and enters the outer loop (section 9).

The kernel's argument block stays on the return stack below everything
the seed pushes; the seed never returns to it.

## 5. Calls and returns

The return stack holds cells, like the data stack: every return address
occupies 8 bytes, the address in the low half and 0 in the high half. The
library needs this, because it treats return addresses as ordinary cells
(`forth/010-lib.fth`: `execute`, `r@`, `branch`, `0branch`; the traces
are in section 5.2).

### 5.1 The convention

- **A call to a dictionary word** is the two instructions
  `push 0` (`6A 00`) and `call` (`E8 rel32`, or an indirect `call`). The
  `push` supplies the high half, the `call` the low half.
- **A return from a dictionary word** is `ret 4` (`C2 04 00`): it takes
  the low half as the address and discards the high half.
- A jump to a dictionary word's first byte (`jmp`, with the caller's
  return cell still on the return stack) is equivalent to calling it and
  returning.

MUSTs that follow:

1. All 21 words leave by `ret 4`, or by a jump as in the third point.
2. The compiler lays calls and returns in exactly these bytes (section 8).
3. When the seed itself calls `key`, `find` or `token` it MUST use the
   same convention, with the registers of section 4.1 in place. The
   library replaces `key` and `find` with words of its own (section 7.7),
   and those return with `ret 4`.
4. The pushed high half MUST be exactly 0. The library takes return
   addresses off the stack and does 64-bit arithmetic on them
   (`forth/010-lib.fth`, `0branch`).
5. `>r` and `r>` move whole cells, both halves, in either direction.
6. Calls between routines of the seed that are not dictionary words are
   FREE: plain `call` and `ret` are fine there.

A call is thus 7 bytes and a return 3.

### 5.2 The traces

These four must come out as shown; they are definitions of
`forth/010-lib.fth`, and its text is fixed. R: lists
the return stack with its top rightmost, one cell per name.

`: execute >r ;`. The body is a call to `>r`
and a return.

| step | data stack | R: |
|---|---|---|
| the caller does `push 0`, `call execute` | xt | A |
| execute's body does `push 0`, `call >r` | xt | A B |
| `>r` moves xt under its own return cell B, and returns to B | | A xt |
| at B: `ret 4` takes the cell xt | | A |
| the word at xt runs and ends with `ret 4`: back at A | | |

`: r@ r> r> dup >r swap >r ;`, called with n on the return stack.

| step | data stack | R: |
|---|---|---|
| on entry | | n A |
| `r>` | A | n |
| `r>` | A n | |
| `dup` | A n n | |
| `>r` | A n | n |
| `swap` | n A | n |
| `>r` | n | n A |
| `ret 4`: back at A | n | n |

`: branch r> @ >r ;`. The library compiles a call to `branch` followed at once by an 8-byte cell holding a target
address, so the call's return address S is the address of that cell.

| step | data stack | R: |
|---|---|---|
| on entry | | S |
| `r>` | S | |
| `@`: the 8 bytes at S | target | |
| `>r` | | target |
| `ret 4`: execution continues at target | | |

`: 0branch 0= r> dup @ swap 8 + dup >r - and r> + >r ;`, compiled the
same way, with a flag on the data stack. `past` is S + 8, the address after the cell.

| step | data stack | R: |
|---|---|---|
| on entry | flag | S |
| `0=` | mask (all ones if flag = 0) | S |
| `r> dup @` | mask S target | |
| `swap 8 +` | mask target past | |
| `dup >r` | mask target past | past |
| `-` | mask (target - past) | past |
| `and` | 0, or target - past | past |
| `r> +` | past, or target | |
| `>r`, `ret 4`: execution continues there | | |

target - past is negative for a backward jump. The sum is exact only
because `-`, `and` and `+` work on all 64 bits and the return cell's high
half is 0.

A fifth case comes from `forth/020-cc-arena.fth` (`jmp-xt,` and its
`>r`, `r>` and `r@`): a word defined in Forth that ends in a jump
(`E9 rel32`) to the seed's `>r` or `r>`. When
the library's interpreter executes it, the return stack holds one cell,
the return into the interpreter. The jump adds none, so the seed's `>r`
takes that cell for its own return address, puts n under it and returns
into the interpreter with n on top. That is what an interpreted `>r` has
to do, and it needs nothing beyond section 7.1's definition of `>r`.

## 6. Dictionary

### 6.1 Header layout

A header is, byte by byte:

| offset | size | field |
|---|---|---|
| 0 | 8 | link: a cell, the address of the previous header in the low half and 0 in the high half; the whole cell is 0 for the oldest |
| 8 | 1 | flags: bit 0 (value 1) is IMMEDIATE; all other bits 0 |
| 9 | 1 | nlen: length of the name, 0 to 255 |
| 10 | nlen | the name's bytes, no terminator, no padding |
| 10 + nlen | | the word's machine code |

A word's execution token (xt) is the address of its code, header + 10 +
nlen. There is no alignment and no code-field pointer.

Depended on by: `forth/010-lib.fth` (`immediate` stores the byte 1 at
header + 8; `found-immediate?` reads the flags byte of LAST_FOUND, bit
0), and `forth/020-cc-arena.fth` (`fh-insert`, `fh-find`: nlen at +9, name
at +10, xt = header + 10 + nlen, the link read with `@` as a cell, the
chain ending at a link cell of 0). `fh-find` computes the xt of the
seed's own 21 words by that formula, so the built-in words MUST have
exactly this layout too, with their code directly after their name.

### 6.2 The chain

LATEST starts as the address of one of the 21 headers, and following
links from it MUST reach all 21 exactly once and end at a link of 0. The
checker requires the chain order to be the file order: the first header
in the file has link 0, each later one links to the header before it in
the file, and LATEST starts at the last. The last header MUST NOT be `;`
(section 12, rule 10).

Exactly these 21 names MUST be present, and no others:

    dup drop swap >r r>   @ ! c@ c!   + * / nand 0=
    key token find   syscall6   state : ;

All 21 are used by the files the route loads **[measured]**: Appendix C
has the counts.

## 7. The 21 words

Stack effects are `( before -- after )`, top rightmost; `R:` is the
return stack. Every word except `;` has flags 0.

### 7.1 Stack, memory, arithmetic

| name | effect | semantics |
|---|---|---|
| `dup` | ( a -- a a ) | both halves |
| `drop` | ( a -- ) | |
| `swap` | ( a b -- b a ) | both halves |
| `>r` | ( n -- ; R: -- n ) | moves the cell n to the return stack, underneath `>r`'s own return cell, so the caller finds n on top of the return stack after `>r` returns |
| `r>` | ( -- n ; R: n -- ) | the reverse: takes the cell that was on top of the return stack when the caller called `r>` |
| `@` | ( addr -- v ) | the 8 bytes at addr, any alignment |
| `!` | ( v addr -- ) | stores 8 bytes, any alignment |
| `c@` | ( addr -- b ) | one byte, zero-extended to a cell. MUST read exactly one byte |
| `c!` | ( b addr -- ) | stores the lowest byte of b. MUST write exactly one byte |
| `+` | ( a b -- a+b ) | modulo 2^64: the carry out of the low halves goes into the high halves |
| `*` | ( a b -- a*b ) | the low 64 bits of the product, for every a and b |
| `/` | ( a b -- q ) | the unsigned 64-bit quotient of a by b, truncated, for every a and every b except 0 |
| `nand` | ( a b -- ~(a&b) ) | bitwise, both halves |
| `0=` | ( n -- f ) | f is all 64 bits set if both halves of n are 0, otherwise all 64 bits clear |

`addr` is the low half of its cell.

**Multiply.** With a = aH·2^32 + aL and b = bH·2^32 + bL, the result's
low half is the low 32 bits of aL·bL, and its high half is the high 32
bits of aL·bL, plus aL·bH, plus aH·bL, modulo 2^32. The term aH·bH never
reaches the low 64 bits. So the forms needed are one 32×32→64 unsigned
multiply and two 32×32→32 multiplies. In the first-tcc compile
**[measured]**, 443,827 of 3,234,871 multiplies had an operand of 2^32 or
more, 127,305 wrapped past 64 bits, and none had both operands at or
above 2^32; 143 multiplied by 2^64 - 1.

**Divide.** MUST be exact for the whole range. The forms that occur
**[measured]**:

- a divisor below 2^32 with a dividend of 2^32 or more and a quotient of
  2^32 or more: 45,061 of 1,054,373 divides in the first-tcc compile.
  This needs a 64-bit quotient. Two chained 32-bit divide instructions do
  it: the high half first, and its remainder as the high part of the
  second dividend;
- a divisor of exactly 2^32 (13,950 times) or 2^63 (12,283 times, plus
  every `0<` the library runs before `forth/020-cc-arena.fth` replaces
  it: the library's `0<` is `2^63 / 0= 0=`);
- no other divisor of 2^32 or more occurred, in that compile or in a
  tool's (Appendix C). The seed MUST still be right for them: a 64-bit
  divisor with a nonzero high half gives a quotient below 2^32, and a
  shift-and-subtract loop over 64 bits is correct for every case. Which
  algorithm is FREE. Appendix B has vectors for the cases no build
  reaches.

b = 0 is the caller's error and never occurs. A hardware divide fault is
acceptable on Linux. On builder-hex0 it stops the machine, because
vector 0 has no handler.

`/` and `*` are also the library's only divide and multiply. The host
code compiles calls to these two words and lays no multiply or divide
instruction of its own (`forth/CONTRACT.md`, section 2), so their speed
matters a little: about a million divides and three million multiplies
per compile.

Edge cases the library builds on:

- `/` unsigned, in `forth/010-lib.fth`: `digit?` (a wrapped negative
  difference divided by 10 must be non-zero), `0<` (`2^63 / 0= 0=`) and
  `,4` (`256 /` as a logical right shift by 8 on values with bit 63
  set). A signed divide breaks all three.
- `0=` returns exactly all ones or 0: `true` is `0 0=`, and `0branch`
  uses the result as an and-mask over 64 bits.
- `>r` and `r>` act relative to their own return cell: section 5.2.
- `c@` and `c!` touch one byte: they are used at the last byte of
  buffers.

### 7.2 `key` ( -- c )

Reads the next byte of the input file and pushes it, 0 to 255, as a
cell. Pushes 0 at end of file, and also if the read fails.

- The descriptor is the low half of INPUT, read from memory on every
  call. The library changes INPUT to switch files.
- MUST consume exactly one byte per call, with one `read` of count 1. No
  read-ahead: the library changes INPUT between two calls and expects the
  old file's position to be just after the last byte handed out.
- MUST NOT remember that end of file was reached. Every call makes its
  own `read`. After INPUT changes, the next call returns the new file's
  next byte.
- A 0 byte in the input is indistinguishable from end of file. No source
  contains one.
- MUST NOT read descriptor 0.

### 7.3 `token` ( -- c-addr u )

Reads the next token into the token buffer and pushes the buffer's
address and the token's length. u = 0 means end of input; the address is
still pushed.

1. Skip whitespace. Whitespace is every byte from 0x01 to 0x20. End of
   input here gives u = 0.
2. Collect bytes greater than 0x20 (this includes 0x7F and all bytes
   above it) until a whitespace byte or end of input. The terminating
   whitespace byte is consumed; nothing after it is. No pushback, no
   look-ahead.
3. If the token is exactly one byte and that byte is `\` (0x5C), it
   starts a comment. Discard input up to and including the next LF
   (0x0A), or to end of input, then start again at step 1. If the byte
   that terminated the `\` token was itself the LF, the comment is
   already over. A `\` inside a longer token is an ordinary character.
4. A token of 1 to 255 bytes is returned. When a 256th byte would be
   stored, the token is fatal as in section 9.3: the first 256 bytes are
   printed, followed by `?` and a newline, and the seed exits with status
   2 without reading further.

Other requirements:

- The bytes stay valid in the buffer until the next call of `token`.
  In `forth/010-lib.fth`, `char`, `interpret` (which looks the token up
  and then parses it as a number) and `s,` read them after `token`
  returns.
- After end of input, a later call returns u = 0 again as long as `key`
  keeps returning 0.
- `token` MUST obtain every input byte by calling the code at `key`'s xt
  (section 7.7).
- It MUST NOT skip `( )` comments; the library does that itself
  (`forth/010-lib.fth`, `skip-to-paren`).

### 7.4 `find` ( c-addr u -- xt | 0 )

Looks up the u bytes at c-addr. Starts at the header LATEST holds at the
time of the call and follows links to 0. The first header whose nlen
equals u and whose name bytes equal the given bytes is a hit: its address
is stored in LAST_FOUND and its xt (header + 10 + nlen) is returned. With
no hit the result is a cell of 0; LAST_FOUND is then not relied on, and
whether `find` writes it on a miss is FREE.

- The comparison is byte-exact and case-sensitive.
- Flags play no part. There is no hidden bit: a word is findable from the
  moment `:` has created its header, including inside its own definition.
  `fh-index` in `forth/020-cc-arena.fth` calls itself and depends on that.
- The newest definition of a name wins, because the walk starts at LATEST.
- c-addr may point anywhere, not only at the token buffer.
- u = 0 matches a header with an empty name if one exists (see `:`).
- The xt and the 0 are whole cells; the header address goes into
  LAST_FOUND with a high half of 0.

### 7.5 `syscall6` ( a b c d e f n -- r )

Executes `int 0x80` with eax = n, ebx = a, ecx = b, edx = c, esi = d,
edi = e, ebp = f, each the low half of its cell. Removes all seven cells
and pushes r.

- r is eax as the kernel returned it, **sign-extended** to 64 bits. Every
  error test above the seed is `0<` on the cell (`included` in
  `forth/010-lib.fth`, `cc-load-file` in `cc/030-cc-io.fth`, the drivers
  in `tinycc/`): a failure is a negative errno on Linux
  and -1 on builder-hex0 (P§5), and either must come out negative as a
  cell.
- eax MUST hold n exactly. builder-hex0 looks only at al (P§1); Linux
  looks at all of eax.
- The word itself saves and restores what it needs across the call:
  esi, the data-stack pointer, at least. The kernel may return with ebx
  or esi changed (section 4.1), and esi carries an argument anyway.
- It keeps nothing below esp (section 4.1).
- It MUST work for calls that do not return in the usual sense: `exit`
  (1) and `execve` (11). After `fork` (2), parent and child continue from
  the same point with the same stacks.

### 7.6 `state`, `:`, `;`

`state` ( -- addr ): pushes 0x08059000, the address of the STATE cell.

`:` ( "name" -- ): reads one token with `token`'s semantics and creates a
header for it at HERE:

- link = the current LATEST as a cell, flags = 0, nlen = the token's
  length, then the name's bytes;
- LATEST = the new header's address, at once;
- HERE = header + 10 + nlen;
- STATE = 1.

The data stack is unchanged. At end of input the token is empty and the
header gets nlen 0; that is not an error. `:` is not immediate: the
library calls it from inside other definitions to build headers
(`constant`, `create` and `defer` in `forth/010-lib.fth`; `code:`,
`constant` and `create` in `forth/020-cc-arena.fth`), then
lays the body itself and stores 0 into STATE. `:` lays no prologue and no
padding.

`;` ( -- ), IMMEDIATE (flags = 1): lays the three bytes `C2 04 00`
(`ret 4`) at HERE, adds 3 to HERE, sets STATE to 0.

### 7.7 Words whose address or first bytes are relied on

The library overwrites the first 5 bytes of a word's code with
`E9 rel32`, a jump to a replacement (`native!`, in
`forth/010-lib.fth`). It does so to two seed words:

- `key`: the replacement, `file-key`, reads INPUT as `key` does and adds
  nested `include` (`forth/CONTRACT.md`, section 6.2). All input MUST therefore pass
  through the code at `key`'s xt after the patch: `token`, and through
  it `:`, the outer loop and every library word that reads a token.
- `find`: the replacement, `fh-find` in `forth/020-cc-arena.fth`, is a
  hash-table lookup with the same interface.

Requirements that follow, for `key` and `find`:

1. The code at the xt MUST be at least 5 bytes long before anything else
   begins.
2. Nothing else in the seed may enter, fall into, or branch into the 5
   bytes at xt .. xt+4 except by transferring control to xt itself. No
   other routine, label or entry point may lie in that range.
3. Callers inside the seed MUST reach the word by transferring control to
   its xt under the convention of section 5, not by a private copy of its
   body or an entry point further in.
4. The seed may not assume anything about registers after such a call
   beyond section 4.1.

Rule 3 is a hard requirement for `token` calling `key`. For the outer
loop calling `find` and `token`, and for `:` calling `token`, it is a
design rule and MUST be kept, although no file patches `token`, and the
seed's own loop has been replaced by the library's before `find` is
patched.

Every other seed word's xt is taken with `'` and used with `execute`, a
compiled call, or a jump (the `seed-` constants and `jmp-xt,` of
`forth/020-cc-arena.fth`; `defer` in `forth/010-lib.fth`). That needs nothing beyond this section's
semantics at the xt. No file copies bytes out of a seed word's body,
decodes them, or types a seed address in.

`native!` writes its 4 displacement bytes with `,4`, which divides by 256
between bytes. So `/` cannot itself be patched this way, nor any word
`,4` runs: the half-written jump would be executed **[measured]** (it
crashed the instrumented run of Appendix C). No file does.

## 8. What the compiler lays down

- **A word, in compile state**: 7 bytes at HERE, `6A 00 E8` followed by a
  little-endian rel32 equal to the xt minus the address just after those
  7 bytes; HERE advances by 7.
- **`;`**: `C2 04 00`; HERE advances by 3.
- **A number, in compile state**: code that, when the definition runs,
  pushes the number as a cell and continues with what follows. Its
  encoding is FREE, in at most 18 bytes; no file reads those bytes back,
  and the library compiles its own literals once it has taken over. Any
  helper routine a literal calls MUST NOT be a dictionary word.
- **`:`**: the header of section 6.1 and nothing else.

A colon definition is thus straight-line machine code, entered by the
call of section 5 and left by the `ret 4` that `;` lays. The library
relies on that when it appends its own bytes to a definition with `c,`
and when it lays a return in the middle of one.

## 9. The outer loop

After the entry steps of section 4.3, loop forever:

1. Read a token (section 7.3). If u = 0, exit with status 0. This holds
   in compile state as well.
2. Look it up (section 7.4).
3. Found: if the header's IMMEDIATE bit is set, or STATE is 0, execute
   the word. Otherwise compile a call to it (section 8).
4. Not found: the token must be an unsigned decimal number (9.2). If
   STATE is 0 push it; otherwise compile it as a literal.
5. Neither: fatal (9.3).

### 9.1 Executing a word

The word is entered under section 5's convention, so its `ret 4` returns
to the loop. While it runs, nothing of the loop's may be on the data
stack: the word sees the stack exactly as earlier tokens left it, and
what it leaves stays for later tokens. STATE, HERE, LATEST and INPUT may
have changed when it returns; the loop MUST carry no stale copy of them
across the call. The word may never return (the library's `interpret`
and `die` do not).

Compiling leaves the data stack exactly as it was. The library's
control-flow words keep their fixup addresses on the data stack between
the tokens of a definition (`forth/010-lib.fth`, `if,` to `again,`).

Lookup comes before number parsing: a defined word whose name is all
digits, or starts with digits, is a word (`1+` in `forth/010-lib.fth`).

### 9.2 Numbers

One or more ASCII digits `0` to `9` and nothing else: no sign, no `0x`,
no `$`, no separators. The value is accumulated in 64 bits (value × 10 +
digit) and wraps silently past 2^64 - 1. 9223372036854775808 and
18446744073709551425 MUST come out exact (the library writes 2^63 as a
decimal literal, `forth/010-lib.fth`, `2^63`). Any
other token is fatal: `-5`, `0x41`, `$41`, `1x`, `12a`, `(`.

### 9.3 The fatal error

There is one error after startup: a token that is neither a word nor a
number, or that reaches 256 bytes. The seed writes the token's bytes,
then `?` (0x3F), then one newline (0x0A), to descriptor 1, and exits with
status 2. Nothing after the token is read or run. The same in compile
state. Use a single `write` for the whole message. For a 256-byte token
the message is the first 256 bytes, `?`, newline.

On builder-hex0 descriptors 1 and 2 are the console (B2:1470). Nothing
there can capture the message, so the exit status is the signal:
kaem-optional-seed and kaem both stop on a non-zero status.

### 9.4 Exit

`exit` (1) with ebx = the status:

| status | when |
|---|---|
| 0 | end of input |
| 1 | no FILE argument, or FILE cannot be opened |
| 2 | the fatal error |

There is no other exit and no other output: the seed prints nothing
except the fatal message.

## 10. builder-hex0's behaviour, and where this document meets it

Every row was measured (P§n) unless marked "read".

| behaviour | source | met by |
|---|---|---|
| a system call writes up to 72 bytes below the caller's esp | P§6 | 4.1: nothing live below esp |
| a write to a file, `chdir` and `access` change ebx; `waitpid` changes esi | P§1 | 4.1, 7.5: nothing assumed preserved; `syscall6` restores esi itself |
| the stack is not zeroed, at entry or later | P§4 | 4.3: only `argc` and `argv` are read |
| the break starts at file end + 0x20000 whatever `p_memsz` says | P§2, B2:1767 | 3.2 |
| growing the break zeroes from the old break to the new | P§2, B2:1435-1441 | 3.2: raised once, before the dictionary holds anything |
| a break request below the current break never returns and wipes the files | P§2 | 3.2: compare first; no other `brk` in the seed |
| the break has no upper bound; at 0x30000000 it zeroes the argument strings | P§2 | the seed stops at 0x0A048000; the library's allocator has a cap (`forth/CONTRACT.md`, section 5.2) |
| `fork` saves the image only up to the break | P§3 | 3.2 |
| unimplemented calls return 0; `exit_group` returns | P§1 | 1: only calls 1, 3, 4, 5 and 45 |
| only al of the call number is compared | P§1 | 7.5: eax holds the exact number, as Linux needs |
| descriptor 0 is the disk stream, with no end of file | P§5 | 1, 7.2 |
| `open` of a missing file returns -1, not an errno | P§5 | 4.3: the sign bit is the test |
| descriptors start at 4; 448 slots per process, not bounds-checked (read, B2:98, 1077-1085) | P§5 | the seed opens one file; the library closes each included file |
| `read` of a file returns the bytes asked for, and 0 at its end | P§5 | 7.2 |
| descriptors 1 and 2 write to the console | P§5, B2:1470 | 9.3 |
| registers are zero at entry; `argc`, `argv`, null, `envp` on the stack; no auxv | P§4 | 4.3: nothing assumed of the registers |
| interrupts are enabled in a program the shell starts and disabled in one a program starts; none was seen delivered | P§6 | nothing live below esp covers either case |
| an argument longer than 255 bytes is cut and runs into its neighbour | P§4 | the boot's commands keep to 255 bytes (`forth/CONTRACT.md`, section 7.2) |
| `execve` of a missing file stops the machine | P§4 | the boot runs the seed only after `hex0` has built it (the same) |
| `fork` followed by `exit` without `execve` loses the parent | P§3 | the seed never forks |
| the internal shell passes one argument | P§ "List format", B2:2439-2457 | the seed is started by kaem-optional-seed, which passes many |
| the built-in `hex0` has no end-of-file test inside a comment (read, B2:2361-2368) | | 12, rule 2 |

## 11. What is not required

- Code size, and the file's size and hash, within 4096 bytes.
- The order of the 21 words in the file and in the chain, and which one
  is last (except that it is not `;`).
- Where the entry code and the internal routines sit, how many there
  are, and their names.
- Which scratch register holds what inside a routine.
- The multiply and divide algorithms, within section 7.1's results.
- The encoding of a compiled literal, within 18 bytes.
- The placement of the token buffer and other private variables on the
  sysvar page, within section 3.3.
- Whether a failed `read` is distinguished from end of file.
- A message for exit status 1.
- What happens on stack underflow or overflow, division by zero, input
  containing a 0 byte, or a dictionary that passes 0x0A048000.
- Closing the input file.
- Error checking of any kind beyond the two exits of section 9.4.

Not free, although they look like shortcuts:

- the `push 0` before every call to a dictionary word, also the seed's
  own calls to `key`, `find` and `token` (section 5);
- the comparison before the second `brk` (section 3.2);
- sign extension of `syscall6`'s result, and zero extension everywhere
  else (sections 7.5, 4.2);
- one `read` per `key`, with INPUT fetched each time and no remembered
  end of file (section 7.2);
- saving esi across `int 0x80` (section 4.1);
- 64-bit `0=`, `nand`, `+`, `swap`, `dup`, `>r` and `r>`: a version
  that handles the low half only passes most small tests.

## 12. The source form and its checker

The source is hex0 that three readers must turn into the same bytes:
stage0-posix's `hex0-seed`, builder-hex0's built-in `hex0`, and the
checker. The first two share these rules (B2:2308-2393;
`vendor/stage0-posix/AMD64/hex0_AMD64.hex0:79-133`): `#` or `;` starts a
comment that runs to the next LF (the checker accepts only `;` after the
bytes of a line, though hex0 takes either); outside comments the characters
`0-9A-Fa-f` are hex digits, taken two at a time, and every other
character is ignored.

The checker is `tests/seed/asm-check.py`. It assembles the comments with
`as --32`, and with `llvm-mc -triple=i386-unknown-linux-gnu` when
installed, and requires both to write the bytes the hex gives. Its
rules:

1. **Lines.** Each line is blank, a comment starting with `;` or `#`, or
   pairs of hex digits (either case, spaces allowed between pairs)
   optionally followed by `;` and a comment. Anything else stops the
   check. One field or one instruction per byte line. A pair never spans
   two lines.
2. **Bytes of the file.** ASCII only; lines end with LF, with no CR; the
   last byte of the file is LF. The last rule is not cosmetic:
   builder-hex0's comment loop reads until LF and does not test for end
   of file (B2:2361-2368), so a file that ends inside a comment hangs the
   boot.
3. **ELF fields.** The first 28 byte lines are the Elf32_Ehdr and
   Elf32_Phdr fields in order, with `e_ident` split as `e_ident[0..3]`,
   `[EI_CLASS]`, `[EI_DATA]`, `[EI_VERSION]`, `[EI_OSABI]`,
   `[EI_ABIVERSION]` and a 7-byte padding line; then `e_type`,
   `e_machine`, `e_version`, `e_entry`, `e_phoff`, `e_shoff`, `e_flags`,
   `e_ehsize`, `e_phentsize`, `e_phnum`, `e_shentsize`, `e_shnum`,
   `e_shstrndx`; then `p_type`, `p_offset`, `p_vaddr`, `p_paddr`,
   `p_filesz`, `p_memsz`, `p_flags`, `p_align`. A comment is
   `FIELD = VALUE`, where VALUE is a number, one of `ELFCLASS32`,
   `ELFDATA2LSB`, `EV_CURRENT`, `ELFOSABI_NONE`, `ET_EXEC`, `EM_386`,
   `PT_LOAD`, `R|W|X`, or for the magic exactly `magic "\x7fELF"`; the
   padding line's comment is exactly `e_ident padding (7 zero bytes)`.
   Optional notes in parentheses after the value: `(_start)` on
   `e_entry` (then a routine named `_start` must be the entry),
   `(the whole file)` on `p_filesz`, `(32 MiB ...)` on `p_memsz`,
   `(no section headers)`, `(little-endian)`, `(System V)`. Any other
   note fails. The checker also requires the values of section 2, and a
   file of at most 4096 bytes.
4. **No raw data elsewhere.** After the ELF fields every byte line is a
   dictionary header field or an instruction. A constant such as `?` and
   newline has to be an immediate operand.
5. **The memory map**, in comment lines:
   - regions as `;;   0x0NNNNNNN = description` (eight uppercase hex
     digits). One description MUST start with each of `data-stack base`,
     `sysvar page`, `initial HERE` and `image end`, with the addresses
     of section 3. The `data-stack base` line MUST contain
     `first push lands at 0x08058FF8`.
   - the sysvar offsets on one comment line that holds nothing else:
     `;;   STATE +0, LATEST +8, HERE +16, LAST_FOUND +24, INPUT +32, ARGV +40, ...`
     (uppercase names, decimal offsets). The six names MUST have those
     offsets; further names, for the seed's private variables, follow on
     the same line with offsets from 48 to 399. Each name becomes an
     assembler constant equal to the page's address plus the offset, so
     instructions write `[HERE]`, `[HERE+4]` or `mov edi, TIB`.
   - every numeric operand of an instruction that is at or above
     0x08048000 + file size MUST be one of the region addresses. Write
     any other large constant in a form that is not such a number (-1,
     not 0xFFFFFFFF).
6. **Routines and labels.** `;; ----- NAME @ 0xNNN` starts a routine at
   file offset NNN (uppercase hex, no load address added); `;; .name:`
   (lower-case letters and underscores) is a label local to the last
   routine. The stated offset must be the offset of the next byte line.
   A `;;` line that contains ` @ 0x`, starts with `;; ---`, or looks like
   `.name:` and does not match a pattern fails, except lines starting
   `;; =====`. Routine names become assembler symbols: keep them plain
   identifiers that are not register names and not the sysvar names.
7. **Instructions.** The comment up to its second `;` is the instruction
   in Intel syntax with NASM's `byte [`, `word [`, `dword [` (rewritten
   to `... ptr [`). After the second `;` anything may follow. Inside the
   instruction part the only parentheses allowed are the notes of rules
   8 and 9. The bytes must be the encoding GNU as chooses for that text,
   and llvm-mc must choose the same.
   - **The `xchg` trap.** The two assemblers differ on register-to-register
     `xchg` when neither register is eax: `xchg ebx, ecx` is `87 CB` from
     as and `87 D9` from llvm-mc **[measured]**, and each gives the other
     bytes for `xchg ecx, ebx`. The checker allows no exception, so such
     an `xchg` cannot pass. `xchg` with eax (the one-byte `90+r` form)
     and `xchg` between a register and memory both pass **[measured]**.
   - A `call`, `jmp` or conditional jump takes a label or a 32-bit
     register. Use only `call`, `jmp`, `jcc` and `ret` to transfer
     control.
8. **Branch notes.** A branch or call to a label carries
   `(rel8 = 0xA - 0xB)` or `(rel32 = 0xA - 0xB)`: A the target's file
   offset, B the offset just past the line, and A - B the displacement
   in the line's last 1 or 4 bytes; the opcode before it is 1 or 2 bytes.
9. **Addresses as operands.** A numeric operand inside the image
   (0x08048000 up to 0x08048000 + file size) MUST be the address of a
   routine heading (not of a local label), unless the instruction carries
   `(NAME header)`, in which case some operand must equal 0x08048000 plus
   NAME's header offset. The note comes last in the instruction part.
10. **LATEST.** The initial LATEST MUST be set by an instruction written
    exactly as `mov dword [LATEST], 0x0804NNNN (NAME header)`; the chain
    walk starts from the first such line. NAME cannot be `;`, because the
    comment is split at `;` first.
11. **Dictionary headers.** `;; --- NAME @ 0xNNN --- header`, with
    `  IMMEDIATE` (two spaces) appended for an immediate word, then
    exactly four byte lines:
    `link  = 0x0804NNNN (PREVNAME)` or `link  = 0 (end of chain)` (8
    bytes), `flags = 0` or `flags = 1 (IMMEDIATE)` (1 byte),
    `nlen  = N` (1 byte), `name  = "NAME"` (N bytes),
    and then at once a routine heading at header offset + 10 + N.
    PREVNAME is the header before this one in the file.
12. **The convention.** Checked from the text, as far as text can show
    it: a `call` whose operand is a register, or the routine heading that
    directly follows a dictionary header, MUST come directly after a line
    `push 0`; and between a dictionary header and the next heading of
    either kind there MUST be no bare `ret`, only `ret 4`. A routine with
    its own heading that is not a word's code may end in `ret`.
13. **The image.** If `./seed-forth` exists it must equal the bytes
    as the script reads them.

**The file's bytes are frozen.** Its comments change only to keep a
path or a cross-reference true: every comment is stripped before the
bytes are read, so such an edit leaves the image as it is, and check 13
above holds it to that.

## 13. Acceptance

Every check named here is a script in the repository, and
`./check-all.sh` runs it as the step given.

### 13.1 The seed alone

These need only the seed.

| check | step | what it proves |
|---|---|---|
| `seed/build.sh` | 01 | hex0-seed assembles the file into `./seed-forth`, 1,191 bytes |
| `python3 tests/seed/asm-check.py` | 01 | section 12 |
| `tests/seed/test.sh` | 02 | the cases below; all pass |
| `tests/seed/test.sh --strace` | 03 | the same cases under `strace -f` (`tests/seed/strace-check.py`): the only calls are `brk`, `open`, `read`, `write` and `exit`; `open` once per case, twice in the two cases that open a second file through `syscall6`, and not at all with no argument; no `read` of descriptor 0; every `read` has count 1; no `brk` below the current break |
| `tests/seed/boot-check.sh` | 14 | builder-hex0's built-in `hex0` assembles the same source in a boot, the result equals the host's `./seed-forth`, and it runs there |

The cases of `tests/seed/test.sh`, 76 of them. Each puts seed-level
Forth in a file and runs `./seed-forth FILE`. A case that prints or
exits by itself starts with a two-line prelude that defines `emit` and
an exit word on `syscall6`, with Linux's i386 call numbers (4 for write
and 1 for exit):

- an empty file exits 0; end of file in the middle of a definition
  exits 0;
- no argument exits 1; a missing file exits 1; neither prints anything;
- an unknown token prints the token, `?` and a newline and exits 2, and
  nothing after it runs; the same in compile state; `-5`, `0x41`, `$41`,
  `1x`, `12a` and `(` are unknown;
- `\` comments: a line holding only `\`, a trailing `\ text`, `\` as the
  last byte of the file, `\` inside a longer token;
- whitespace: space, tab, LF and CR separate tokens;
- a 255-byte token is looked up; a 256-byte one is fatal, with a message
  of exactly 258 bytes;
- numbers: 0, 9223372036854775808 and 18446744073709551425 exact, and
  wrap past 2^64;
- a defined word whose name starts with digits is a word;
- every word of section 7.1, each on values with a nonzero high half;
- Appendix B's vectors for `*` and `/`;
- `token` and `find`: a found word's xt runs; a miss is 0; the newest
  definition wins; a word is findable inside its own definition; an
  empty name;
- `key` returns the byte right after the token that called it, and 0 at
  the end;
- `:` at the end of the file makes a header with an empty name;
- `;` lays `C2 04 00` and a compiled word lays `6A 00 E8`: read back
  with `c@` from a definition's body;
- the five traces of section 5.2, written as tests: `execute`, `r@`, a
  `branch`, a `0branch` both ways, and a definition ending in a jump to
  `>r`;
- INPUT: a file that opens a second file with `syscall6` and stores the
  descriptor in INPUT continues with the second file's tokens; storing
  the old descriptor back continues after the point where the first
  file left off;
- ARGV: the bytes of `argv[1]` and `argv[2]` are reachable from the
  ARGV cell;
- `syscall6`: a failed `open` is negative as a cell (`0<` built from `/`
  as `forth/010-lib.fth` builds it); `write` returns its count;
- a file that creates more than 0x20000 bytes of dictionary and reads it
  back.

**The second opinion.** The expected status and output of a case are
written in `test.sh`, and a wrong expectation that agreed with a wrong
seed would pass. `tests/reference.py` therefore computes them a second
way, in Python: 64-bit cells as Python integers, the words of section
7.1 by this document's definitions, numbers by 9.2, the fatal error by
9.3, and straight-line definitions. `test.sh` compares every case's
expectation with it and fails on a disagreement. It computes 46 of the
76 cases, among them every word of 7.1 on values with a nonzero high
half and Appendix B's vectors, and declines the rest. The cases with no
second opinion are those that need `token`, `find`, `key` or `syscall6`,
the system variables (LATEST, HERE, INPUT, ARGV, STATE), a return
address used as data (the traces of section 5.2), control flow, or a
token of 256 bytes or more, and the two that give the seed no file. For
those the expectation rests on this document and on the seed.

Until tag `experiments-2026-11-21` the second opinion was the x86-64
seed: 65 of the 76 cases ran on both seeds and had to print the same
bytes.

Judge every case by its output as well as its exit status. A broken
primitive can make the outer loop read the next token as the end of
input and exit 0 (a broken `0=` did this to the host's vector check), so
a case whose expected output is empty, judged by its exit status alone,
proves little. Each case SHOULD print a last line after its last test,
and the script require it. `tests/seed/test.sh` compares each case's
whole output, so this holds wherever a case's expected output is not
empty; the cases that expect no output are not yet covered.

### 13.2 With the host files

These need the files `forth/CONTRACT.md` specifies. They are the strong
checks: the first compares 975,624 bytes of compiler output.

| check | step | what it proves |
|---|---|---|
| `tests/tinycc/seed-check.sh`: the seed, the library and the compiler build kaem, the stock `ungz` and `untar`, the eleven tools and the first tcc (`tinycc/build-tools.sh`, `tinycc/build-first-tcc.sh`), and all fifteen equal `tests/pins/tinycc.sha256`; the first tcc is `build-out/tinycc/tcc-first`, sha256 `92d1143823045f9324c2d4b34c64dfc11bc994c958b92bfbd80a99de371e4d2d` | 09 | every error of the seed that reaches the compiler's output, over fifteen programs |
| the same fifteen runs under `strace` (`tests/tinycc/seed-syscall-check.py`): only `brk`, `open`, `read`, `write`, `close` and `exit`; the break never lowered; the output file written after everything else was read | 09 | the host side keeps to builder-hex0's calls |
| `tests/tinycc/one-boot-check.sh`: a disk with no program on it | 15 | the seed, assembled by the built-in `hex0`, builds kaem, the tools and the first tcc on builder-hex0, and the boot reaches live-bootstrap's published hashes. The boot also exports `/seed-forth`, which must equal the host's `./seed-forth` byte for byte |

The pins are fixed values. They were first produced by the x86-64 seed
of tag `experiments-2026-11-21` compiling the same sources, and this
seed reproduced them; nothing in the branch builds them a second way
now. What stands behind the first tcc's pin is downstream of it: from
that tcc, live-bootstrap's own step reaches the `tcc` live-bootstrap
publishes (steps 10 and 15).

kaem needs three process calls the tools do not. They are in a file of
their own, `tinycc/m2libc-kaem.c`, which only kaem's command lists
(`forth/CONTRACT.md`, section 7.4), so the eleven tools are compiled
without it. kaem has its own pin, `tinycc/kaem`.

### 13.3 What a change to the seed touches

The seed's bytes are frozen. If they ever change:

- `check-all.sh` step 01 tests the size, 1,191 bytes; `README.md`,
  `seed/README.md` and `tinycc/README.md` state it, and `tinycc/README.md`
  and `forth/CONTRACT.md`, section 9, the sha256 `b5f70ffb…`.
- No file under `tests/pins/` holds the seed's hash, and none needs to:
  the boot compares the two assemblies of it with each other (steps 14
  and 15).
- No pin of `tests/pins/tinycc.sha256` depends on the seed's bytes; all
  depend on its behaviour.
- The book, a separate project, quotes `seed/000-seed.hex0`,
  `forth/*.fth` and `cc/*.fth` byte for byte.

### 13.4 What no check exercises

A seed can be wrong in each of these and still pass everything above, so
each has to be right by reading the code against this document:

- `/` with a divisor of 2^32 or more that is not 2^32 or 2^63, outside
  Appendix B's vectors. No build makes one.
- `*` with both operands at or above 2^32, outside Appendix B's vectors.
  No build makes one.
- the comparison before the second `brk`. On Linux the break is never
  below the image's end, so the raising call is made only on
  builder-hex0, and the comparison's false branch only on Linux. A seed
  that always raises passes both; so does one whose comparison is signed.
- nothing kept below esp. Linux writes nothing there, and on
  builder-hex0 a violation shows only if the bytes are read back after a
  call.
- esi saved across `int 0x80` in the seed's own `read`, `open` and
  `brk`. builder-hex0 was measured to preserve it for those three (P§1),
  so a seed that relies on that passes.
- the high half of INPUT, ARGV, LATEST, HERE and LAST_FOUND being 0, and
  the `push 0` being 0 and not some other value, beyond what the first
  tcc's bytes happen to depend on.
- `syscall6` for `fork` and `execve`. Forth runs neither; kaem does,
  through C.
- interrupts. None was seen delivered on builder-hex0 in the probe's
  rerun (P§6), but the recorded log of the same test counts one IRQ0, so
  the question is not settled. If one were delivered, it would write
  below esp like a system call.
- a non-zero exit status on builder-hex0. Its shell carries on after
  any status, so the boot checks judge the fatal path by its console
  text.
- a dictionary larger than the image, a data stack deeper than 8,192
  cells, and more than 448 open descriptors. Nothing checks them.

## Appendix A. The interface at a glance

What `forth/010-lib.fth`, `forth/020-cc-arena.fth` and the later layers
rely on in the seed, and the section that specifies each. (This appendix
used to map the x86-64 seed's interface onto this one; that table is in
this file at tag `experiments-2026-11-21`.)

| interface | here |
|---|---|
| the 21 words | names and stack effects (7) |
| `syscall6` | `int 0x80`; ebx, ecx, edx, esi, edi, ebp; eax sign-extended (7.5) |
| `key` | the descriptor in INPUT (7.2) |
| cell | 8 bytes in a register pair, or two words of memory (4.2) |
| TOS | edx:eax (4.1) |
| data-stack pointer | esi, push subtracts 8 (4.1) |
| return stack | esp, 8-byte return cells made by `push 0` and `ret 4` (5) |
| sysvar base register | none |
| sysvars | STATE +0, LATEST +8, HERE +16, LAST_FOUND +24, INPUT +32, ARGV +40 (3.3) |
| header | link 8, flags 1, nlen 1, name, code (6.1) |
| `find` and LAST_FOUND | 7.4 |
| `'` | `token find`: the xt, a cell with a zero high half |
| `execute` | `>r ;`, a `ret 4` into the xt (5.2) |
| a compiled call (`call,`) | `6A 00 E8 rel32`, 7 bytes (8) |
| a return (`ret,`, `;`) | `C2 04 00` (8) |
| the jump of `native!` | `E9 rel32` over the first 5 bytes of `key` and `find` (7.7) |
| a compiled literal | at most 18 bytes (8) |
| load address | 0x08048000 (2) |
| initial HERE, stack base, sysvar page | 0x0805A000, 0x08059000, 0x08059000 (3) |
| image size | 32 MiB, and the break raised to its end (2, 3.2) |
| input | FILE, by name (1) |
| end of input | exit 0 (9) |
| the fatal error | token, `?`, newline; exit 2 (9.3) |
| seed's own calls | exit 1, read 3, write 4, open 5, brk 45 (1) |
| token buffer | 258 bytes on the sysvar page (3.3) |

## Appendix B. Vectors for `*` and `/`

Seed-level text: it uses only seed words and decimal numbers. Each line
adds 0 to a counter when the result is as stated and 1 when it is not,
and the last line exits with the counter as the status, so 0 means every
line passed. `-` is built as the library builds it.

```
: - dup nand 1 + + ;
: die 0 0 0 0 0 1 syscall6 ;
0
100 7 / 14 - 0= 1 + +
18446744073709551615 1 / 18446744073709551615 - 0= 1 + +
18446744073709551615 10 / 1844674407370955161 - 0= 1 + +
9223372036854775808 10 / 922337203685477580 - 0= 1 + +
18446744073709551615 4294967295 / 4294967297 - 0= 1 + +
18446744073709551615 4294967296 / 4294967295 - 0= 1 + +
18446744073709551615 4294967297 / 4294967295 - 0= 1 + +
9223372036854775808 9223372036854775808 / 1 - 0= 1 + +
9223372036854775807 9223372036854775808 / 0 - 0= 1 + +
18446744073709551615 9223372036854775808 / 1 - 0= 1 + +
18446744073709551615 9223372036854775809 / 1 - 0= 1 + +
18446744073709551615 18446744073709551615 / 1 - 0= 1 + +
18446744073709551614 18446744073709551615 / 0 - 0= 1 + +
1311768467463790320 4294967297 / 305419896 - 0= 1 + +
18364758544493064720 4886718345 / 3758096384 - 0= 1 + +
18446744069414584320 4294967295 / 4294967296 - 0= 1 + +
9223372036854775808 3 / 3074457345618258602 - 0= 1 + +
18446744073709551615 18446744065119617025 / 1 - 0= 1 + +
12345678901234567890 9876543210 / 1249999988 - 0= 1 + +
9223372036854775807 2147483648 / 4294967295 - 0= 1 + +
4294967296 4294967295 / 1 - 0= 1 + +
5 18446744073709551615 / 0 - 0= 1 + +
0 5 / 0 - 0= 1 + +
16045690984503098046 281479271612417 / 57004 - 0= 1 + +
18446744073709551615 9223372036854775807 / 2 - 0= 1 + +
6 7 * 42 - 0= 1 + +
4294967295 4294967295 * 18446744065119617025 - 0= 1 + +
4294967296 4294967296 * 0 - 0= 1 + +
18446744073709551615 18446744073709551615 * 1 - 0= 1 + +
18446744073709551615 2 * 18446744073709551614 - 0= 1 + +
9223372036854775808 2 * 0 - 0= 1 + +
1311768467463790320 18364758544493064720 * 2552847189736476416 - 0= 1 + +
4294967295 4294967297 * 18446744073709551615 - 0= 1 + +
4294967297 4294967295 * 18446744073709551615 - 0= 1 + +
12345678901234567890 10 * 12776324570088369204 - 0= 1 + +
3735928559 14627333964952502272 * 9858198585802227712 - 0= 1 + +
14627333964952502272 3735928559 * 9858198585802227712 - 0= 1 + +
33 5381 * 177573 - 0= 1 + +
die
```

The expected values were computed with Python's integers.
`tests/seed/test.sh` holds this text as one case, and
`tests/reference.py` computes the 38 results again on every run. On the
seed the text exits 0, and with one expectation made wrong it exits 1
(a second case of `test.sh`).

## Appendix C. Measurements

These were made before the seed existed, to size it and to find out
what its `*` and `/` have to handle: on the host, with the x86-64 seed
and library of tag `experiments-2026-11-21` and the i386 back end loaded
over that tree's compiler, in a scratch copy at commit 47d0d5b. The
compiler's files have been folded and renamed since, so the counts
describe that tree. None has been repeated on this seed except where
`forth/CONTRACT.md`, section 9, says so.

**The first tcc built as pinned**: `92d11438…`, 975,624 bytes, in
0.46 s.

**Uses of the 21 words** in that load set (tokens outside `\` comments):

| word | the library (010) | the arena file (020) | the other layers and the drivers |
|---|---:|---:|---:|
| `dup` | 37 | 21 | 631 |
| `drop` | 14 | 11 | 441 |
| `swap` | 33 | 31 | 282 |
| `>r` | 14 | 12 | 222 |
| `r>` | 15 | 14 | 239 |
| `@` | 15 | 50 | 1844 |
| `!` | 15 | 43 | 889 |
| `c@` | 12 | 8 | 67 |
| `c!` | 5 | 4 | 27 |
| `+` | 25 | 37 | 341 |
| `*` | 2 | 7 | 159 |
| `/` | 11 | 5 | 103 |
| `nand` | 6 | 2 | 1 |
| `0=` | 22 | 12 | 277 |
| `key` | 1 | 1 | 0 |
| `token` | 4 | 0 | 1 |
| `find` | 2 | 1 | 0 |
| `syscall6` | 5 | 2 | 1 |
| `state` | 10 | 4 | 0 |
| `:` | 92 | 99 | 936 |
| `;` | 89 | 95 | 960 |

**Multiply and divide.** A copy of that tree's 020 had its inline `*`
and `/` removed and, early in the file, the seed's `*` and `/`
redirected to machine-code wrappers that count and then do the
operation. The counts therefore start at that point; before it the
library divides by 10, 26, 256 and 2^63 and multiplies by 10 and 16. The
outputs kept their pinned hashes.

| | first tcc | `sha256sum` (a tool) |
|---|---:|---:|
| divides | 1,054,373 | 164,064 |
| divisor at or above 2^32 | 26,233 | 1,911 |
| dividend at or above 2^32 | 45,084 | 22,588 |
| of those, quotient at or above 2^32 | 45,061 | 22,565 |
| multiplies | 3,234,871 | 355,448 |
| an operand at or above 2^32 | 443,827 | 117,682 |
| both operands at or above 2^32 | 0 | 0 |
| product wraps past 2^64 | 127,305 | 48,910 |

Divisors, first tcc: 65536 (590,321), 256 (375,057), 2^31 (24,781), 8
(17,872), 2^32 (13,950), 6 (12,423), 2^63 (12,283), 2 (5,387), 16, 10,
4, 26, 1, 4096, 32. The tool's are a subset. The multiplier on top of the
stack was 8 in 2,098,992 multiplies and 33 in 918,822.

**HERE.** At the end of the first-tcc compile HERE was 13,644,672: 9.01
MiB above 0x400000, that seed's load address, of which the megabyte buffers are the larger part.
The arena held 1,247,376 bytes, the preprocessed source 1,762,051, the
output 975,624.

**The first tcc's bytes do not depend on where its sources are.** The
same sources under `build-out/other-dir/`, with the driver's four paths
changed to match, gave the same 975,624 bytes.

**Nor on the path strings of a tool.** `sha256sum` compiled with its
source named by an absolute path of 142 bytes has the pinned bytes.

**Nor on dictionary addresses.** With one extra word defined after the
library and 12,347 bytes allotted after `cc/030-cc-io.fth`, so that
every later dictionary address moves by an odd amount, the first tcc
keeps its hash. This seed's dictionary differs from that one's in every
address and size, and it reproduced the pins of section 13.2, which
confirms it.

**Assemblers.** GNU as 2.47 and llvm-mc 23.1.5 in 32-bit mode write the
same bytes for every instruction form this document and
`forth/CONTRACT.md` name, including operands that are assembler
constants (`mov eax, [HERE]`), except register-to-register `xchg` without
eax (section 12, rule 7).
