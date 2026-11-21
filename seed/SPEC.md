# SEED-SPEC: the Forth seed, `seed/000-seed.hex0`

Specification for a clean-room rewrite. It describes what the seed must do
and every interface another file depends on. It does not describe how the
present seed does it. Paths are relative to the repository root; `file:line`
citations name the dependent that forces a detail.

Conventions: MUST marks something a dependent or a check relies on. FREE marks
a choice the implementer owns. "Cell" is 8 bytes, little-endian.

## 1. What the seed is

A static x86-64 Linux ELF executable, written as commented hex0 and assembled
by stage0-posix's `hex0-seed` (`seed/build.sh:27`) into `./seed-forth`. It is
a minimal Forth: it reads whitespace-separated tokens from standard input,
executes or compiles the words they name, and accepts unsigned decimal
numbers. It has exactly 21 named words. Everything else is Forth text fed to
it on stdin, starting with `forth/010-lib.fth` or one of three launchers
(`cc/driver/seed-cc-start.fth`, `kernel/tools/k1-direct-start.fth`,
`tinycc/catm-start.fth`).

It runs on three kernels: Linux, K0 (`kernel/k0/`) and K1 (`kernel/k1/`). It
MUST use only what all three provide:

- the `syscall` instruction (K0 has no `int 0x80` and no IDT), with rax =
  number, arguments in rdi, rsi, rdx, r10, r8, r9, result in rax;
- for its own needs only three calls: `read` (0), `write` (1), `exit` (60).
  Not `exit_group` (231): K0 does not have it.

## 2. ELF requirements

One ELF64 header (64 bytes) directly followed by one program header (56
bytes), then the program. No section headers.

| field | value | why |
|---|---|---|
| `e_ident` | `7F 45 4C 46`, class 2 (64-bit), data 1 (LSB), version 1, rest 0 | Linux; K1 compares the first 6 bytes (`kernel/k1/proc.c:197`) |
| `e_type` | 2 (`ET_EXEC`) | K1 accepts 2 or 3 (`kernel/k1/proc.c:198`) |
| `e_machine` | 62 (`EM_X86_64`) | `kernel/k1/proc.c:198` |
| `e_version` | 1 | Linux convention |
| `e_entry` | 0x400000 + offset of the entry code | K0 uses its low 32 bits |
| `e_phoff` | 64 | K0 reads program headers at file offset 64 without consulting `e_phoff`; `tests/seed/asm-check.py:228` requires 64 |
| `e_ehsize` | 64 | `tests/seed/asm-check.py:228` |
| `e_phentsize` | 56 | `kernel/k1/proc.c:198`; `tests/seed/asm-check.py:229` |
| `e_phnum` | 1 | K0 loads every program header as a `PT_LOAD`; the checker parses exactly one (the first 28 byte lines are the ELF fields) |
| `e_shoff`, `e_shentsize`, `e_shnum`, `e_shstrndx`, `e_flags` | 0 | `tests/seed/asm-check.py:226-227` |
| `p_type` | 1 (`PT_LOAD`) | |
| `p_flags` | 7 (R, W, X) | the dictionary is code written at run time, and `native!` patches code inside the file image (`cc/020-cc-arena.fth:23-26`) |
| `p_offset` | 0 | `tests/seed/asm-check.py:230` |
| `p_vaddr`, `p_paddr` | 0x400000 | `tests/seed/asm-check.py:88,230`; K1 refuses a segment below 0x400000 (`kernel/k1/proc.c:215`) |
| `p_filesz` | the file's size in bytes | Linux; checker note "(the whole file)" |
| `p_memsz` | 0x1000000 (16 MiB) | see below |
| `p_align` | 0x1000 | Linux requires vaddr and offset congruent modulo the alignment |

`p_memsz`: the image spans 0x400000 to 0x1400000. The kernel zero-fills
everything past the file. The library puts megabyte buffers above 0x414000
(`cc/030-cc-io.fth:26-48,116-117`, `forth/130-asm.fth:45-63`) and never asks
the kernel for that memory, so the segment MUST reach at least 0x1400000.
Keep exactly 16 MiB: K0 copies and zero-fills the whole segment on
every `execve` and on `fork`, and its `brk` starts at the segment's end, so a
different size changes K0's memory use. No dependent states the number, so
"exactly" is caution, not a proven need.

Zero fill is an interface: the library relies on untouched memory reading
as zero. The seed MUST NOT write anywhere outside the regions of section 3,
and within the dictionary space only at HERE, where section 7 says so.

## 3. Memory map

| address | what | status |
|---|---|---|
| 0x400000 | the file image (headers, code, the 21 dictionary headers) | MUST |
| 0x401000 | initial HERE: first free byte for the dictionary, growing up | see 3.1 |
| 0x411000 | data-stack base; the stack grows down; first cell pushed is at 0x410FF8 | see 3.1 |
| 0x413000 | the sysvar page (`state` returns this address) | MUST, see 3.2 |
| 0x414000 to 0x1400000 | free, zero; the library moves HERE here | MUST stay untouched |
| kernel-provided | the return stack is the process stack the kernel hands over in rsp | MUST |

### 3.1 Dictionary space and the data stack

The library's `skip-vm-pages` sets HERE to `state + 4096` and documents the
layout it assumes: the data stack below 0x411000, the sysvar page at
0x413000, HERE below 0x410000 when it runs (`forth/010-lib.fth:574-580`,
`cc/030-cc-io.fth:22-26`, `forth/130-asm.fth:42-45`). The three launchers do
the same thing by hand (`kernel/tools/k1-direct-start.fth:96`,
`tinycc/catm-start.fth:96`, `cc/driver/seed-cc-start.fth:160`).

Until that jump, everything the library defines is laid down from the
initial HERE upward, and the data stack sits above it. Measured with the
present seed (initial HERE 0x401000): HERE is 0x402B3C after
`forth/010-lib.fth`, 0x40F42E after `cc/020-cc-arena.fth`, and 0x40F970 in
K1's load order, where `kernel/k1/boot/k0-syscalls.fth` comes between them.
That leaves 1,680 bytes below 0x410000. Consequences:

- Initial HERE MUST be at most 0x401000 and the data-stack base MUST be at
  least 0x411000. Use exactly those two values unless there is a reason not
  to. Starting HERE lower is the only deviation known to be safe: every
  pinned output survived earlier seeds whose library dictionary was a
  different size, so no output depends on absolute dictionary addresses
  below 0x410000.
- The bytes the seed's compiler lays down (section 7) count against that
  headroom: 5 bytes per compiled word, and at most 13 bytes per compiled
  number.
- The data stack has no overflow or underflow checks and needs none.

### 3.2 The sysvar page

`state` pushes the address of the page. The first four cells are an
interface, in this order, 8 bytes each:

| offset | name | content | depended on by |
|---|---|---|---|
| +0 | STATE | 0 interpreting, 1 compiling | `forth/010-lib.fth:215,364,391,506`; library stores a whole cell of 0 |
| +8 | LATEST | address of the newest dictionary header | `forth/010-lib.fth:23,182`; `cc/020-cc-arena.fth:339`; launchers |
| +16 | HERE | address of the first free dictionary byte | `forth/010-lib.fth:24-34,572,580`; `cc/020-cc-arena.fth:25,115` |
| +24 | LAST_FOUND | address of the header `find` matched last | `forth/010-lib.fth:495` (`latest 16 +`); `cc/020-cc-arena.fth:345` |

All four are read and written by the library as full 64-bit cells with `@`
and `!`. The seed MUST read them from memory each time it needs them (the
library changes HERE and LATEST behind its back, for example
`test.sh:211`: `here-addr ! latest !`) and MUST keep STATE a clean 64-bit 0
or 1. STATE and LAST_FOUND start as 0; the kernel's zero fill provides that.

The rest of the page:

- The page address 0x413000 MUST be kept. `skip-vm-pages` turns it into
  HERE = 0x414000, where every large buffer of the compiler then sits. No
  dependent types the number in, and I found no proof that outputs depend on
  it, but no seed has ever used another and the documentation of three files
  states it.
- Everything the seed keeps in memory besides the two stacks (the token
  buffer, a byte to read into, any other variable) MUST lie inside
  [0x413000 + 32, 0x414000), because the library assumes all of the seed's
  state is below `state + 4096`.
- `test.sh` uses bytes of this page as scratch: `state + 400` (1 byte,
  `test.sh:28`), `state + 500` to `+ 507` (`test.sh:89`) and `state + 600`
  to `+ 607` (`test.sh:93`). The seed MUST NOT use those bytes. Keeping all
  seed state inside `state + 32` to `state + 399` satisfies this.
- The token buffer (TIB) needs 258 bytes: 256 for the longest token the
  fatal message prints, 2 for `?` and newline. The library's `unknown` writes
  two bytes directly after a token of up to 255 bytes in this buffer
  (`forth/010-lib.fth:432-434`). Its placement is FREE within the
  constraints above: nothing learns its address except from `token`.

## 4. Registers

Forced by downstream code that lays machine code of its own:

| register | role | forced by |
|---|---|---|
| rdi | top of the data stack (TOS) | `forth/010-lib.fth:203-207` (the push body: `sub rbp,8; mov [rbp],rdi; movabs rdi,imm64`); every inline primitive in `cc/020-cc-arena.fth:28-31,116-119,134-230` |
| rbp | data-stack pointer; `[rbp]` is the second item, `[rbp+8]` the third; push decrements by 8 | same |
| rsp | return stack: the x86 call stack. A word is entered by `call` and leaves by `ret` | `forth/010-lib.fth:40` (`execute` is `>r ;`), `:269,277-283` (`branch`, `0branch`), `cc/020-cc-arena.fth:190-193` (inline `push rdi`, `pop rdi`, `[rsp]`) |
| rbx | holds the sysvar page address from entry on, never changed | the checker's memory-map rule (`tests/seed/asm-check.py:165-167`) and its LATEST rule (`:474`); `cc/020-cc-arena.fth:19-21` promises that no native word changes rbx |

With an empty data stack rdi holds nothing meaningful; nobody reads it.

What the seed may assume of code it calls through a dictionary entry (a
word executed by the loop, and `key`, see 6.2): rbx, rbp and rsp are as the
stack effect says, rdi is the new TOS, and every other register may have
changed. `cc/020`'s replacement for `key` changes rax, rcx, rdx, rsi and r11
(`cc/020-cc-arena.fth:68-87`). What code calling a seed word may assume is
the same and no more: a seed word is FREE to change any register other than
rbx, rbp, rsp and rdi.

The direction flag is clear on entry and MUST be left clear.

## 5. Dictionary

### 5.1 Header layout

A header is, byte by byte:

| offset | size | field |
|---|---|---|
| 0 | 8 | link: address of the previous header, 0 for the oldest |
| 8 | 1 | flags: bit 0 (value 1) is IMMEDIATE; all other bits 0 |
| 9 | 1 | nlen: length of the name, 0 to 255 |
| 10 | nlen | the name's bytes, no terminator, no padding |
| 10 + nlen | | the word's machine code |

A word's execution token (xt) is the address of its code, which is
header + 10 + nlen. There is no alignment and no code-field pointer.

Depended on by: `forth/010-lib.fth:182` (`immediate` stores the byte 1 at
header + 8), `:495` (flags byte of LAST_FOUND, bit 0), and
`cc/020-cc-arena.fth:327-350` (`fh-insert`, `fh-find`: nlen at +9, name at
+10, xt = header + 10 + nlen, link at +0, chain ends at link 0). `fh-find`
computes the xt of the seed's own 21 words by that formula, so the built-in
words MUST have exactly this layout too, with their code directly after
their name. The checker enforces it (`tests/seed/asm-check.py:455-461`).

### 5.2 The chain

LATEST starts as the address of one of the 21 headers, and following links
from it MUST reach all 21 exactly once and end at link 0. The order of the
21 words in the chain is FREE: there are no duplicate names, and the only
walks are `find`'s and `fh-index`'s (`cc/020-cc-arena.fth:334-336`), which
recurses once per header on the return stack. The checker requires the
chain order to be the file order: the first header in the file has link 0,
each later one links to the header before it in the file, and LATEST starts
at the last (`tests/seed/asm-check.py:373-379,485-500`). The last header
MUST NOT be `;` (section 10, rule 9).

Exactly these 21 names MUST be present, and no others: a token the seed
does not know has to be fatal (`test.sh:184-191`), and the repository's
documents and the book count 21.

## 6. The 21 words

Stack effects are `( before -- after )`, top rightmost; `R:` is the return
stack. All arithmetic is on 64-bit cells and wraps. Every word except `;`
has flags 0.

### 6.1 Stack, memory, arithmetic

| name | effect | semantics |
|---|---|---|
| `dup` | ( a -- a a ) | |
| `drop` | ( a -- ) | |
| `swap` | ( a b -- b a ) | |
| `>r` | ( n -- ; R: -- n ) | moves n to the return stack, underneath `>r`'s own return address, so the caller finds n on top of the return stack after `>r` returns |
| `r>` | ( -- n ; R: n -- ) | the reverse: takes the cell that was on top of the return stack when the caller called `r>` |
| `@` | ( addr -- v ) | the 64-bit cell at addr; any alignment |
| `!` | ( v addr -- ) | stores 64 bits; any alignment |
| `c@` | ( addr -- b ) | one byte, zero-extended. MUST read exactly one byte |
| `c!` | ( b addr -- ) | stores the low byte of b. MUST write exactly one byte |
| `+` | ( a b -- a+b ) | modulo 2^64 |
| `*` | ( a b -- a*b ) | low 64 bits of the product |
| `/` | ( a b -- q ) | unsigned 64-bit quotient of a by b, truncated. b = 0 is the caller's error (a hardware divide fault is acceptable) |
| `nand` | ( a b -- ~(a&b) ) | bitwise |
| `0=` | ( n -- f ) | f is -1 (all 64 bits set) if n = 0, otherwise 0 |

Edge cases the library builds on:

- `/` unsigned: `forth/010-lib.fth:99-106` (`digit?`: a wrapped negative
  difference divided by 10 must be non-zero), `:131` (`0<` is
  `2^63 / 0= 0=`), `:162-170` (`256 /` as a logical right shift by 8 on
  values with bit 63 set). A signed divide breaks all three.
- `0=` returns exactly -1 or 0: `:114` (`true`), `:277-283` (`0branch` uses
  the result as an and-mask).
- `>r` and `r>` act relative to their own return address: `:40` (`execute`
  is `>r ;`: the colon word's `ret` then jumps to the xt), `:45` (`r@`),
  `:269` (`branch`), `cc/020-cc-arena.fth:183-193` (a JMP to the seed's
  `>r` or `r>` from a word that was itself called).
- `c@` and `c!` touch one byte: they are used at the last byte of buffers.

### 6.2 `key` ( -- c )

Reads the next byte of standard input (fd 0) and pushes it, 0 to 255.
Pushes 0 at end of input, and also if the read fails.

- MUST consume exactly one byte of fd 0 per call, with one `read` of
  count 1. No read-ahead: `forth/130-asm.fth:88-91` and
  `cc/030-cc-io.fth:68-82` read the rest of fd 0 with `read` directly after
  the Forth text, and `test.sh:97` checks that `key` returns the byte right
  after the token that called it.
- A 0 byte in the input is therefore indistinguishable from end of input.
  No source contains one.
- At end of input every later call returns 0 again.

### 6.3 `token` ( -- c-addr u )

Reads the next token from standard input into the token buffer and pushes
the buffer's address and the token's length. u = 0 means end of input; the
address is still pushed.

1. Skip whitespace. Whitespace is every byte from 0x01 to 0x20. (Space,
   tab, LF and CR are exercised, `test.sh:53-55`; the other control bytes
   occur in no source.) End of input here gives u = 0.
2. Collect bytes greater than 0x20 (this includes 0x7F and all bytes above
   it) until a whitespace byte or end of input. The terminating whitespace
   byte is consumed; nothing after it is. No pushback, no look-ahead.
3. If the token is exactly one byte and that byte is `\` (0x5C), it starts
   a comment. Discard input up to and including the next LF (0x0A), or to
   end of input, then start again at step 1. If the byte that terminated
   the `\` token was itself the LF, the comment is already over. A `\`
   inside a longer token is an ordinary character. (`test.sh:50`: a line
   holding only `\`, a trailing `\ text`, and `\` as the last byte of
   input.)
4. A token of 1 to 255 bytes is returned. When a 256th byte would be
   stored, the token is fatal as in section 8.3: the first 256 bytes are
   printed, followed by `?` and a newline, and the seed exits with status 2
   without reading further (`test.sh:57-62,183-184`).

Other requirements:

- The bytes stay valid in the buffer until the next call of `token`.
  `forth/010-lib.fth:230` (`char`), `:503-509` (`interpret` looks the token
  up and then parses it as a number) and `:591` (`s,`) read them after
  `token` returns.
- After end of input, every later call returns u = 0 again.
  (`test.sh:172-180`: end of input right after `:`, `constant` or `'`.)
- `token` MUST obtain every input byte by calling the code at `key`'s xt,
  the address `' key` yields, as it is at the time of the call. See 6.7.
- It MUST NOT skip `( )` comments; the library does that itself
  (`forth/010-lib.fth:436-446`).

### 6.4 `find` ( c-addr u -- xt | 0 )

Looks up the u bytes at c-addr. Starts at the header LATEST holds at the
time of the call and follows links to 0. The first header whose nlen
equals u and whose name bytes equal the given bytes is a hit: its address
is stored in LAST_FOUND and its xt (header + 10 + nlen) is returned. With
no hit the result is 0; LAST_FOUND is then not relied on, and whether
`find` writes it on a miss is FREE.

- The comparison is byte-exact and case-sensitive.
- Flags play no part. There is no hidden bit: a word is findable from the
  moment `:` has created its header, including inside its own definition.
  `cc/020-cc-arena.fth:334-336` (`fh-index` calls itself) depends on that.
- The newest definition of a name wins, because the walk starts at LATEST.
- c-addr may point anywhere, not only at the token buffer.
- u = 0 matches a header with an empty name if one exists (see `:`).

### 6.5 `syscall6` ( a b c d e f n -- rax )

Executes the `syscall` instruction with rax = n, rdi = a, rsi = b,
rdx = c, r10 = d, r8 = e, r9 = f. Removes all seven cells and pushes the
kernel's raw return value (a negative errno on failure). It MUST work for
calls that do not return in the usual sense: `exit` (60), `execve` (59),
and `fork` (57), after which both parent and child continue from the same
point with the same stacks (`kernel/tools/k1-direct-start.fth:128-139`).

`kernel/k1/boot/k0-syscalls.fth:13-22` takes `syscall6`'s xt with `'` and
calls it with `execute` from a replacement of the same name.

### 6.6 `state`, `:`, `;`

`state` ( -- addr ): pushes the address of the STATE cell, which is the
sysvar page address (section 3.2).

`:` ( "name" -- ): reads one token with `token`'s semantics and creates a
header for it at HERE:

- link = the current LATEST, flags = 0, nlen = the token's length, then the
  name's bytes;
- LATEST = the new header's address, at once;
- HERE = header + 10 + nlen;
- STATE = 1 (the whole cell reads as 1).

The data stack is unchanged. At end of input the token is empty and the
header gets nlen 0; that is not an error (`test.sh:178`). `:` is not
immediate: the library calls it from inside other definitions to build
headers (`forth/010-lib.fth:215,364,389`; `cc/020-cc-arena.fth:22,302-303`),
then lays the body itself and stores 0 into STATE.

`;` ( -- ), IMMEDIATE (flags = 1): lays one byte C3 (`ret`) at HERE, adds 1
to HERE, sets STATE to 0.

### 6.7 Words whose address or first bytes are relied on

`native!` (`cc/020-cc-arena.fth:23-26`) overwrites the first 5 bytes of a
word's code with `E9 rel32`, a jump to a replacement. It is applied to two
seed words:

- `key` (`cc/020-cc-arena.fth:68-87`): the replacement reads stdin through
  a 4096-byte buffer, and `key-drain` (`:93-99`, used by
  `cc/030-cc-io.fth:71-74`) hands the unread part of that buffer to the
  compiler. All input MUST therefore pass through the code at `key`'s xt
  after the patch: `token`, and through it `:`, the outer loop and every
  library word that reads a token. `test.sh:138-145` runs every interpreter
  case a second time after `cc/020` to check this.
- `find` (`cc/020-cc-arena.fth:351`): the replacement is a hash-table
  lookup with the same interface.

Requirements that follow, for `key` and `find`:

1. The code at the xt MUST be at least 5 bytes long before anything else
   begins.
2. Nothing else in the seed may enter, fall into, or branch into the 5
   bytes at xt .. xt+4 except by transferring control to xt itself. No
   other routine, label or entry point may lie in that range.
3. Callers inside the seed MUST reach the word by transferring control to
   its xt (a direct `call` or `jmp` to that address is fine), not by a
   private copy of its body or an entry point further in.
4. The seed may not assume anything about registers after such a call
   beyond section 4.

Rule 3 is a hard requirement for `token` calling `key`. For the outer
loop calling `find` and `token`, and for `:` calling `token`, it is a
design rule and MUST be kept, although no file patches `token`, and the seed's own loop has
been replaced by the library's before `find` is patched.

Every other seed word's xt is taken with `'` and used with `execute`,
`call,` or a JMP (`cc/020-cc-arena.fth:140-218`, `forth/010-lib.fth:383`).
That needs nothing beyond section 6's semantics at the xt. No file copies
bytes out of a seed word's body, decodes them, or types a seed address in
(`forth/010-lib.fth:13-14`).

## 7. What the compiler lays down

- **A word, in compile state**: 5 bytes at HERE, `E8` followed by a
  little-endian rel32 equal to xt minus the address just after those 5
  bytes; HERE advances by 5. It MUST be a plain near CALL: compiled words
  such as `r@`, `branch` and `0branch` depend on a call pushing exactly one
  return address (`forth/010-lib.fth:45,269,277-283`).
- **`;`**: one byte `C3`; HERE advances by 1.
- **A number, in compile state**: code that, when the definition runs,
  pushes the number and continues with what follows. Its encoding is FREE;
  no file reads those bytes back, and the library compiles its own literals
  differently once it has taken over (`forth/010-lib.fth:418-422`). The
  constraint is size: at most 13 bytes per literal (section 3.1). Any
  helper routine a literal calls MUST NOT be a dictionary word.
- **`:`**: the header of section 5.1 and nothing else: no prologue, no
  padding.

A colon definition is thus straight-line machine code entered by CALL and
left by the RET that `;` lays. The library relies on that when it appends
its own bytes to a definition with `c,` (`forth/010-lib.fth:200-210`) and
when it lays a RET in the middle of one (`:349`).

## 8. The outer loop

Entry: set up the registers of section 4, LATEST and HERE, then loop
forever:

1. Read a token (section 6.3). If u = 0, exit with status 0. This holds
   in compile state as well (`test.sh:31-36`).
2. Look it up (section 6.4).
3. Found: if the header's IMMEDIATE bit is set, or STATE is 0, execute the
   word. Otherwise compile a CALL to it (section 7).
4. Not found: the token must be an unsigned decimal number (8.2). If STATE
   is 0 push it; otherwise compile it as a literal.
5. Neither: fatal (8.3).

### 8.1 Executing a word

The word is entered with a `call`, so its `ret` returns to the loop. While
it runs, nothing of the loop's may be on the data stack: the word sees the
stack exactly as earlier tokens left it, and what it leaves stays for later
tokens. STATE, HERE and LATEST may have changed when it returns, and
`fork` may have duplicated the process (section 6.5); the loop MUST carry
no stale copy of them across the call. The word may never return (`die`,
`interpret`, `exec`).

Compiling leaves the data stack exactly as it was: laying down a CALL
(step 3) or a literal (step 4) takes nothing from it and leaves nothing
on it. The library's control-flow words keep their fixup addresses on the
data stack between the tokens of a definition
(`forth/010-lib.fth:293-342`).

Lookup comes before number parsing: a defined word whose name is all
digits, or starts with digits, is a word (`test.sh:75-78`, `2x`;
`forth/010-lib.fth:69`, `1+`).

### 8.2 Numbers

One or more ASCII digits `0` to `9` and nothing else: no sign, no `0x`, no
`$`, no separators. The value is accumulated in 64 bits and wraps silently
past 2^64 - 1 (`forth/010-lib.fth:122-125,460`). 9223372036854775808 and
18446744073709551425 MUST come out exact (`forth/010-lib.fth:125`,
`test.sh:70-73`). Any other token is fatal: `-5`, `0x41`, `$41`, `1x`,
`12a`, `(` (`test.sh:44-47`).

### 8.3 The fatal error

There is one error: a token that is neither a word nor a number, or that
reaches 256 bytes. The seed writes the token's bytes, then `?` (0x3F), then
one newline (0x0A), to fd 1 (standard output), and exits with status 2.
Nothing after the token is read or run. The same in compile state.
(`test.sh:40-47,57-62`; the library copies this behaviour in `unknown`,
`forth/010-lib.fth:430-434`.) Use a single `write` for the whole message.

For a 256-byte token the message is the first 256 bytes, `?`, newline.

### 8.4 Exit

Exit is `exit` (60) with status 0 at end of input and 2 on the fatal
error. There is no other exit and no other output: the seed prints nothing
except the fatal message.

## 9. What is not required

- Code size, and the file's size and hash. Both will change. See section
  11 for the places that state them.
- The order of the 21 words in the file and in the chain, and which one
  is last (except that it is not `;`).
- Where the entry code and the internal routines sit, how many there are,
  and their names.
- Which registers hold what inside a routine, other than rdi, rbp, rsp
  and rbx as in section 4, and rax as the only register the checker
  accepts for an indirect `call` or `jmp` (section 10, rule 6).
- The encoding of a compiled literal, within 13 bytes.
- The placement of the token buffer and other private variables on the
  sysvar page, within section 3.2.
- Whether a failed `read` is distinguished from end of input; treating
  both as end of input is enough.
- What happens on stack underflow, division by zero, a name longer than
  the buffer could hold (it cannot happen: 256 is fatal), or input
  containing a 0 byte.
- Error checking of any kind beyond the one fatal error.
- Initial HERE may be lower than 0x401000.

## 10. Format rules: `tests/seed/asm-check.py`

The check assembles the file's comments with GNU as, and with `llvm-mc`
when installed, and requires the same bytes as the hex. The file MUST be
written so that it can. Read the script's docstring; the rules that bind
the author:

1. **Lines.** Each line is blank, a comment starting with `;` or `#`, or
   pairs of hex digits (either case, spaces allowed between pairs)
   optionally followed by `;` and a comment. Anything else stops the check
   (`asm-check.py:137-150`). One field or one instruction per byte line.
2. **ELF fields.** The first 28 byte lines are the Elf64_Ehdr and
   Elf64_Phdr fields in order, with `e_ident` split as `e_ident[0..3]`,
   `[EI_CLASS]`, `[EI_DATA]`, `[EI_VERSION]`, `[EI_OSABI]`,
   `[EI_ABIVERSION]` and a 7-byte padding line (`:90-97`). A comment is
   `FIELD = VALUE`, where VALUE is a number, one of `ELFCLASS64`,
   `ELFDATA2LSB`, `EV_CURRENT`, `ELFOSABI_NONE`, `ET_EXEC`, `EM_X86_64`,
   `PT_LOAD`, `R|W|X`, or for the magic exactly `magic "\x7fELF"`; the
   padding line's comment is exactly `e_ident padding (7 zero bytes)`.
   Optional notes in parentheses after the value: `(_start)` on `e_entry`
   (then a routine named `_start` must be the entry), `(the whole file)` on
   `p_filesz`, `(16 MiB ...)` on `p_memsz`, `(no section headers)`,
   `(little-endian)`, `(System V)`, `(ignored on Linux)`. Any other note
   fails (`:175-232`).
3. **No raw data elsewhere.** After the ELF fields every byte line is a
   dictionary header field or an instruction. There is no way to write a
   string or a table as data; a constant such as `?` and newline has to be
   an immediate operand.
4. **The memory map**, in comment lines (`:153-172`):
   - regions as `;;   0x4NNNNN = description` (six uppercase hex digits).
     One description MUST start with `sysvar page`. One MUST start with
     `data-stack base` and contain `first push lands at 0xNNNNNN`, equal to
     the base minus 8.
   - a line `;;   rbx      = the sysvar page, 0x413000` (the pattern is
     `rbx`, spaces, `= the sysvar page, 0x` and the address).
   - the sysvar offsets on one comment line that holds nothing else:
     `;;   STATE +0, LATEST +8, HERE +16, LAST_FOUND +24, ...` (uppercase
     names, decimal offsets). It must be the first comment line of that
     shape in the file. Each name becomes an assembler constant, so
     instructions write `[rbx+HERE]`.
   - every numeric operand of an instruction that is at or above
     0x400000 + file size MUST be one of the region addresses (`:331-332`).
     So 0x401000, 0x411000 and 0x413000 need region lines.
5. **Routines and labels.** `;; ----- NAME @ 0xNNN` starts a routine at
   file offset NNN (uppercase hex, no 0x400000 added); `;; .name:` (lower
   case letters and underscores) is a label local to the last routine. The
   stated offset must be the offset of the next byte line. A `;;` line
   that contains ` @ 0x`, starts with `;; ---`, or looks like `.name:` and
   does not match a pattern fails, except lines starting `;; =====`.
   Routine names become assembler symbols: keep them plain identifiers
   that are not register names and not the sysvar names.
6. **Instructions.** The comment up to its second `;` is the instruction
   in Intel syntax with NASM's `byte [`, `word [`, `qword [` (rewritten to
   `... ptr [`). After the second `;` anything may follow; the checker
   reads only `(movabs)` there, which makes `mov r64, imm` assemble as
   `movabs`. Inside the instruction part the only parentheses allowed are
   the two notes of rules 7 and 8. The bytes must be the encoding GNU as
   chooses for that text, and llvm-mc must choose the same. They differ
   on register-to-register `xchg` when neither register is rax: they put
   the two registers in opposite ModRM fields (`xchg rsp, rbp` is
   `48 87 EC` from as and `48 87 E5` from llvm-mc), and this checker,
   unlike K0's, allows no exception, so such an `xchg` cannot pass. `xchg`
   with rax (the one-byte `90+r` form) and `mov` through a third register
   both pass. A `call`,
   `jmp` or conditional jump takes a label, or the register `rax`; no
   other register operand is accepted (`:299-300`). Use only `call`, `jmp`
   and `jcc` to transfer control.
7. **Branch notes.** A branch or call to a label carries
   `(rel8 = 0xA - 0xB)` or `(rel32 = 0xA - 0xB)`: A the target's file
   offset, B the offset just past the line, and A - B the displacement in
   the line's last 1 or 4 bytes; the opcode before it is 1 or 2 bytes
   (`:306-317`).
8. **Addresses as operands.** A numeric operand inside the image
   (0x400000 up to 0x400000 + file size) MUST be the address of a routine
   heading (not of a local label), unless the instruction carries
   `(NAME header)`, in which case some operand must equal 0x400000 plus
   NAME's header offset (`:321-330`). The note comes last in the
   instruction part.
9. **LATEST.** The initial LATEST MUST be set by an instruction written
   exactly as `mov qword [rbx+LATEST], 0x4NNNNN (NAME header)`; the chain
   walk starts from the first such line (`:474-476,485-500`). NAME cannot
   be `;`, because the comment is split at `;` first.
10. **Dictionary headers.** `;; --- NAME @ 0xNNN --- header`, with
    `  IMMEDIATE` (two spaces) appended for an immediate word, then
    exactly four byte lines:
    `link  = 0x4NNNNN (PREVNAME)` or `link  = 0 (end of chain)` (8 bytes),
    `flags = 0` or `flags = 1 (IMMEDIATE)` (1 byte),
    `nlen  = N` (1 byte), `name  = "NAME"` (N bytes),
    and then at once a routine heading at header offset + 10 + N
    (`:346-390,455-461`). PREVNAME is the header before this one in the
    file.
11. **The image.** If `./seed-forth` exists it must equal the bytes as the
    script reads them (`:571-573`).

The script's regular expressions are the final word; run it early and
often: `python3 tests/seed/asm-check.py`.

## 11. Acceptance

All of these MUST pass. Each is run from the repository root.

Keep the checkout outside `/tmp`: `tests/cc/gates/run-gates.sh` mounts a
private `/tmp` in its sandbox, which hides a checkout there, and step 05
then fails gates die-32 and die-36 with error 30, whatever the seed. The
checks write temporaries and logs under `$TMPDIR`, or `/tmp` if it is
unset.

| check | what it proves |
|---|---|
| `seed/build.sh` | hex0-seed assembles the file into `./seed-forth` |
| `python3 tests/seed/asm-check.py` | section 10: comments equal bytes under GNU as and llvm-mc, branch notes, header fields, memory map and chain are consistent |
| `./test.sh` | the seed alone (end of input, the fatal error, comments, whitespace, the 255/256 limit, numbers, all word groups, `token`/`find`, `key`), then `forth/010-lib.fth`, the interpreter cases with and without `cc/020-cc-arena.fth` (the `native!` patches of `key` and `find`), and the first compiler layers. All pass, 0 failed |
| `CHECK_TINYCC=1 CHECK_HEX0_HANDOFF=1 ./check-all.sh` | `check-all: 12 OK, 0 SKIP, 0 FAIL`. Steps 01 to 10, 13 (TinyCC junction) and 14 (hex0 hand-off) |
| step 10 inside it (`tests/pins/check-outputs.sh`) | `check-outputs: 5 as pinned, 0 differ, 0 not built`: seed-cc, seed-ar, Stage A's `cc-out-v1`, `amd64-runner` and K1 have the hashes in `tests/pins/outputs.sha256`, so the compiler the seed runs produces the same bytes |
| step 13 (`tests/tinycc/junction-check.sh`) | the first tcc is `d9e97270...` (`tests/pins/tinycc.sha256`), and live-bootstrap's `/usr/bin/tcc` `b9dce87d...` and its libraries are reached from it |
| step 14 (`tests/tinycc/hex0-handoff-check.sh`) | the seed runs under K0, builds the first tcc there, and boot 2 reaches the published tcc |
| `kernel/k1/run-chain.sh --direct-smoke` | the seed under K0 builds K1; under K1, hex0-seed assembles `seed/000-seed.hex0` again and that seed builds seed-cc. QEMU exits 1 and the serial log has the two markers the script greps (`kernel/k1/run-chain.sh:61-72`) |

What changes and has to be updated with the new seed:

- `check-all.sh:92` compares `seed-forth`'s size with a literal (930
  now). Step 01 fails until that number is the new size.
- No file in `tests/pins/` holds the seed's own hash. If one is added
  later it is expected to change.
- Documents that state the seed's size, all of which have to change
  with it: `README.md:7,21,71,82,216`, `CLAUDE.md:8`, `check-all.sh:6`,
  `seed/README.md:3` and its size table, and
  `tinycc/build-first-tcc.sh:10`.
- The book (forth-bootstrap-book, a separate repository) quotes
  `seed/000-seed.hex0` byte for byte (`CLAUDE.md`, Invariants).

Not affected, and the proof that the rewrite is a drop-in: every hash in
`tests/pins/outputs.sha256` and `tests/pins/tinycc.sha256` stays as it is.
