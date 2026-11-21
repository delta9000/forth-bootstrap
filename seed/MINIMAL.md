# A smaller seed: census and design

`seed/000-seed.hex0` is the root of trust and the hardest file in the
repository to review, because it is hand-written machine code.  This note
records what the 1,772-byte seed's features are used for, which of them
can be Forth in `forth/010-lib.fth` instead, and the smaller seed that
follows from that.  Sections 1 and 2 were written before the prototype;
sections 3 and 4 give its measured results and the review of it.

## 1. Census of the 1,772-byte seed

The 1,772 bytes are 120 of ELF headers, 421 of dictionary header fields
(32 headers) and 1,231 of code.

### Who reads the seed's own REPL

Four texts are read by the seed's REPL and never hand over to anything
else, so every seed feature one of them uses has to stay or be supplied
in each of them:

| text | lines | tokens |
|---|---|---|
| `forth/010-lib.fth` up to the `interpret` line (the preamble) | 483 | 728 |
| `cc/driver/seed-cc-start.fth` (check 04, the chain's entry 2) | 352 | 1,993 |
| `kernel/tools/k1-direct-start.fth` (check 08, K0's init) | 147 | 934 |
| `tinycc/catm-start.fth` (the TinyCC route's first step) | 109 | 691 |

The three launchers are single files because nothing exists yet to join
files with; each starts with its own copy of the library's first words.
Everything else (the rest of `010-lib.fth`, `cc/`, `forth/130-asm.fth`,
the drivers the C programs generate) is read by `010-lib.fth`'s
`interpret`, over 60,000 tokens for a compiler run.

### Use of each seed word, by token count

"preamble" and the launchers are the bare-seed texts above; the other
columns are read by `interpret`.

| word | preamble | launchers | 010 rest | cc/020 | cc/030+ | 130-asm | later re-implemented in cc/020 |
|---|---|---|---|---|---|---|---|
| `dup` | 21 | 75 | 12 | 21 | 1382 | 41 | inlined |
| `drop` | 9 | 37 | 5 | 11 | 715 | 36 | inlined |
| `swap` | 17 | 37 | 14 | 31 | 525 | 19 | inlined |
| `>r` | 4 | 5 | 4 | 12 | 432 | 7 | inlined |
| `r>` | 5 | 6 | 5 | 14 | 479 | 11 | inlined |
| `r@` | 2 | 1 | 0 | 2 | 339 | 9 | inlined |
| `@` | 9 | 135 | 4 | 52 | 4172 | 116 | inlined |
| `!` | 10 | 95 | 4 | 44 | 1747 | 66 | inlined |
| `c@` | 5 | 25 | 7 | 8 | 129 | 17 | inlined |
| `c!` | 4 | 14 | 1 | 4 | 68 | 2 | inlined |
| `+` | 18 | 56 | 7 | 37 | 971 | 37 | inlined |
| `nand` | 6 | 7 | 0 | 2 | 4 | 0 | inlined |
| `0=` | 12 | 29 | 7 | 12 | 687 | 10 | inlined |
| `/` | 11 | 25 | 0 | 5 | 151 | 6 | inlined |
| `*` | 1 | 6 | 1 | 7 | 266 | 8 | inlined |
| `bye` | 1 | 0 | 0 | 0 | 1 | 1 | |
| `emit` | 0 | 0 | 0 | 0 | 0 | 0 | |
| `key` | 0 | 0 | 0 | 1 | 0 | 0 | `native!`: `key-fill`, buffered |
| `syscall6` | 2 | 29 | 3 | 2 | 14 | 0 | |
| `find` | 1 | 0 | 0 | 1 | 0 | 0 | `native!`: `fh-find`, hashed |
| `here` | 11 | 28 | 0 | 27 | 11 | 0 | |
| `,` | 9 | 70 | 1 | 1 | 88 | 0 | |
| `execute` | 2 | 1 | 1 | 27 | 9 | 0 | |
| `state` | 7 | 12 | 2 | 5 | 0 | 0 | |
| `latest` | 3 | 6 | 0 | 4 | 0 | 0 | |
| `'` | 10 | 11 | 2 | 75 | 327 | 2 | |
| `:` | 59 | 174 | 24 | 102 | 1489 | 51 | |
| `;` | 55 | 168 | 24 | 98 | 1512 | 52 | |
| `lit` | 1 | 0 | 0 | 0 | 0 | 0 | superseded by the inline push |
| `[lit]` | 80 | 413 | 0 | 4 | 4898 | 142 | wrapped: un-lays the seed's 13 bytes |
| `branch` `0branch` | 1 each | 1 each | 0 | 0 | 0 | 0 | superseded by inline `jz`/`jmp` |

"Inlined" means `cc/020-cc-arena.fth` defines an immediate word of the same
name that lays the instruction bytes in place of the CALL; code compiled
before it, and the same word run from the interpreter, still reach the
seed's.  Only `key` and `find` are patched in place (`native!` writes a
JMP over their first bytes), because the seed's own reader and REPL call
them by address.

### Use of each seed feature

| feature | used by |
|---|---|
| `\` comments in the reader | every text: 293 in the preamble, 55 in the launchers |
| `( )` comments in the reader | none of the bare-seed texts; about 1,000 after the hand-over |
| `[lit] N` interpreting | 8 in the preamble, 22 in the launchers |
| `[lit] N` compiling | 72 in the preamble, 391 in the launchers |
| a miss prints `tok?` and reading goes on | nothing relies on it; `interpret` exits 2 instead |
| IMMEDIATE and STATE in the REPL | every text (`;`, `if,` and so on) |
| the 255-byte token limit | no text has such a token; it protects the token buffer |
| `[lit]`'s rejection of non-decimal tokens | nothing relies on it; tested in `test.sh` |
| `emit`, `bye` in the seed | `emit`: only `test.sh`.  `bye`: the REPL at end of input, `interpret` |
| `'` as a word | the preamble and launchers; also the only way Forth could reach the reader (`char`, `token`, and `read-word-addr`, which decodes `'`'s first CALL) |
| LAST_FOUND | the REPL; `found-immediate?`; `fh-find` writes it |

## 2. Design

### What a word must be to stay in the seed

A word stays in machine code only if Forth cannot express it, or the
seed's own loop needs it before any Forth exists.  That gives 21:

| group | words | why not Forth |
|---|---|---|
| data stack | `dup drop swap` | nothing simpler to build them from |
| return stack | `>r r>` | reach the x86 stack |
| memory | `@ ! c@ c!` | reach memory; `c@` and `c!` from `@` and `!` would touch 7 bytes past the address |
| arithmetic | `+ nand 0= * /` | see "Considered and kept" for `*` and `/` |
| system | `syscall6` | the SYSCALL instruction |
| reader | `key token find` | the loop needs them before any Forth exists |
| compiler | `state : ;` | the loop needs them; `state` is how Forth finds the sysvars |

Compared with other small Forths (their sources read for this note):

- sectorforth (`sectorforth.asm`, a 512-byte 16-bit boot sector) has
  `@ ! sp@ rp@ 0= + nand exit key emit`, `:` and `;`, and the variables
  `tib state >in here latest`.  It has no number parser at all (its
  example library builds `-1`, `0` and `1` from `nand`), and an unknown
  token prints `!!` and resets.  Its examples define `dup`, `swap`,
  `branch` and `?branch` in Forth; `?branch` picks its return address by
  arithmetic, as `0branch` does here.  milliForth (`sector.asm`) is a
  smaller variant of the same word set.
- jonesforth (`jonesforth.S`, i386) is the other extreme: about a hundred
  dictionary entries in assembly, among them `WORD`, `NUMBER`, `FIND`,
  `INTERPRET`, `BRANCH`, `0BRANCH`, the comparisons and four syscall
  words; only the control structures are Forth.
- stage0's own Forth (`stage2/forth.s`, for stage0's register machine)
  is like jonesforth: about 70 words in assembly, including `NUMBER`,
  `FIND`, `INTERPRET`, `EXECUTE`, `BRANCH`, `0BRANCH`, `LIT`, `HERE`,
  the comma, the comparisons and `R@`.

The 1,772-byte seed sat between the two, with 32 words.  This one keeps
sectorforth's core, with three differences.  It has `dup drop swap >r r>`
in place of `sp@ rp@`: the top of stack is in a register and the code is
subroutine-threaded, so stack words built on `sp@` would be slower and
harder to follow than three two-instruction words.  It parses unsigned
decimal numbers, because the library lays machine code and system call
numbers from its first lines, and seventy constants built from `nand`
would be less readable than 74 bytes of parser.  And it adds what a C
compiler's host needs to be usable: bytes (`c@ c!`), `* /` and
`syscall6` in place of `emit`.

### The loop

```
repl:   token                      none left -> exit(0)
        find
          found, IMMEDIATE or interpreting -> run it
          found, compiling                 -> CALL xt at HERE
          not found -> the token as unsigned decimal
                         interpreting -> push it
                         compiling    -> CALL lit, then the cell
                       not a number   -> the token and "?", exit(2)
```

Numbers moved from the word `[lit]` into the loop's miss path.  That
removes `[lit]`'s header and its second parser entry, lets every
bare-seed text write `8 +` for `[lit] 8 +`, and makes a miss fatal: the
loop now has one failure, a token that is neither a word nor a number,
and it stops there as `interpret` does.

### Removed from the seed, and where each went

Bytes are header plus code in the 1,772-byte seed.  "Forth" is the
replacement in `forth/010-lib.fth`; each launcher has the same lines
where it uses the word.

| removed | bytes | replacement |
|---|---|---|
| `emit` | 60 | `: emit  here c!  1 here 1 write drop ;` (after the hand-over; nothing before it prints) |
| `bye` | 25 | `: bye  0 die ;`  The loop keeps a 9-byte `exit(0)` for end of input |
| `r@` | 29 | `: r@  r> r> dup >r swap >r ;` |
| `here` | 31 | `: here  here-addr @ ;` |
| `,` | 43 | `: ,  here !  here 8 + here-addr ! ;` |
| `execute` | 30 | `: execute  >r ;`  The loop runs a word with `call rax` |
| `latest` | 35 | `: latest  state 8 + ;` (and `here-addr` is `state 16 +`) |
| `'` | 21 | `: '  token find ;`, with `token` exposed in its place |
| `lit` header | 13 | none: `lit` stays as code the loop compiles CALLs to; the library's literals are the inline push from the start |
| `[lit]`, `parse_decimal` | 164 | numbers in the loop (74 bytes); `[lit]` in Forth after the number parser, 3 lines |
| `branch` | 22 | `: branch  r> @ >r ;` |
| `0branch` | 45 | 7 lines: the return address chosen by arithmetic (below) |
| `( )` in the reader | 20 | `read-token` in Forth, 4 lines, used by `interpret`, `[lit]` and `c{ }` |
| miss-and-continue | 15 | none: a miss is fatal |
| STATE and LAST_FOUND initialisation | 24 | none: the kernel zero-fills the page |
| `xor rdi, rdi` at entry | 3 | none: an empty stack's TOS is never read |

`0branch` is the one replacement that needs explaining.  Called from
compiled code, it finds its own return address on the return stack, and
that is the address of the inline target cell.  It must return either to
the cell's contents or to the address after the cell, and it has no
branch to choose with, so it computes `past + (mask and (target - past))`
with `mask = flag 0=`.

### Encoding changes that are not removals

- `rbx` holds the sysvar page.  `mov rax, [rbx+HERE]` is 4 bytes where
  `mov rax, [0x413010]` is 8, and the seed has 26 such lines.
  The cost is a rule for all machine code that ever runs in the process:
  `rbx` is the seed's.  `cc/020`'s native words use `rax rdx rsi rdi`
  only, Linux and K0 preserve `rbx` across SYSCALL, and the compiler's
  output never runs in this process.
- The token's length is in `rcx`, saved around the call to `key`, instead
  of in a register reserved for it.
- The token buffer and `key`'s byte moved onto the sysvar page (TIB at
  `state + 64`), so they are one-byte displacements from `rbx`.
- A routine that ends by dropping the top of stack jumps to `drop`; one
  that starts by pushing calls `dup`.
- `find` compares names with an index register instead of two pointers.

### Dependencies the design keeps

- The header layout: link (8), flags (1), nlen (1), name; xt = header +
  10 + nlen.  `immediate`, `found-immediate?` and `cc/020`'s `fh-*` words
  use it, and it is unchanged.
- The sysvar order STATE, LATEST, HERE, LAST_FOUND, 8 bytes each, and the
  page at 0x413000, so `skip-vm-pages` (`state 4096 +`) still lands on
  0x414000.
- `:` leaves STATE = 1; `constant`, `create`, `defer` and `code:` reset it.
- `find` returns the xt and leaves the header in LAST_FOUND; `fh-find`
  replaces it with the same interface.
- The reader gets every byte through `key`'s dictionary entry point, and
  the loop and `:` get every token through `token`'s, so `native!` on
  `key` still reroutes all input and `key-drain` still sees every byte
  read ahead.
- `cc/020`'s `[lit]` un-laid the seed's 13 bytes (CALL `lit` plus cell)
  and laid the inline push instead.  With `[lit]` in Forth laying the
  push itself, that wrapper goes; this is the one change to `cc/`.

### Behaviour that changes

- A token the seed's loop cannot take is fatal (`tok?`, exit 2) instead
  of being reported and skipped.
- The seed takes bare unsigned decimal numbers; `[lit]` is a library word
  from the hand-over on (same rule: unsigned decimal or fatal).
- `( )` comments are skipped where `interpret`, `[lit]` and `c{ }` read
  tokens, as before, but no longer after `:`, `'`, `char`, `[char]` or
  `s,`, which read one token with the seed's `token`.  No file has a
  comment there.
- Whitespace is any byte up to 0x20, not just space, tab, LF and CR.  No
  `.fth` file contains another control byte.
- The documented addresses: TIB 0x412800 becomes 0x413040, the I/O
  scratch byte 0x412000 becomes 0x413020.

### Considered and kept

- `*` and `/` (49 bytes with headers).  They can be Forth: shift-and-add
  and long division, 64 iterations each, an estimated 15 lines (not
  written), in the library
  and again in each launcher that multiplies or divides (all three
  divide).  `forth/130-asm.fth` and the launchers run without `cc/020`,
  so they would run at that speed.  Nine instructions of the plainest
  machine code in the file against some 15 lines of intricate Forth in
  four places: kept.  It is the next 49 bytes if the owner wants them.
- `c@` and `c!` (43 bytes).  `: c@ @ 255 and ;` reads 7 bytes past the
  address, and a `c!` built on `@` and `!` writes them; both fault at the
  end of a mapping.  Kept.
- `\` in the reader (27 bytes).  As a Forth word it could only be defined
  after the control-flow words, 200 lines into a file that explains
  itself in comments from line 1.  Kept.
- The "tok?" message (26 bytes of the 33 in `fatal`).  Without it a typo
  in 1,900 lines of bare-seed Forth exits 2 and says nothing.  Kept.
- The 256-byte token check (4 bytes).  It is the seed's one bounds check.
  Kept.
- 4-byte links, or flags and nlen in one byte, would save about 80 bytes
  of header fields, and change the layout `cc/020` and the book rely on.
  Not done.
- Overlapping the ELF headers: K0's loader reads the program header at
  offset 64, and it would be the opposite of readable.  Not done.

### How the seed is written

The 1,091-byte prototype of section 3 was written as NASM source
(`seed/seed.asm`) and turned into hex0 by a script.  Section 5 replaced
that: `seed/000-seed.hex0` is now written directly and is the only source
of the program.  Offsets, link fields and branch distances are computed by
hand and written into the comments, and `tests/seed/asm-check.py` is what
proves them: GNU as on every comment, and LLVM's llvm-mc too when it is
installed, must write exactly the line's bytes, and every branch note,
header field, memory-map address and the dictionary chain is checked.

## 3. The prototype, measured

| | 1,772-byte seed | this seed |
|---|---|---|
| file | 1,772 | 1,091 |
| ELF headers | 120 | 120 |
| dictionary header fields | 421 (32 headers) | 267 (21 headers) |
| code | 1,231 | 704 |
| instructions (lines of machine code) | 338 | 222 |
| words with a header | 32 | 21 |

Where the 704 bytes of code are:

| routine | bytes | | routine | bytes |
|---|---|---|---|---|
| `_start` | 26 | | `token` | 78 |
| `repl` | 61 | | `key` | 32 |
| `number` | 74 | | `find` | 64 |
| `fatal` | 33 | | `:` | 61 |
| `end_of_input`, `exit` | 9 | | `;` | 22 |
| `read_char` | 14 | | `syscall6` | 37 |
| `compile_call` | 26 | | `state` | 9 |
| `lit` | 15 | | the other 14 words | 143 |

Forth code lines (not counting comments, blank lines, or `[lit] N`
becoming `N`):

| file | added | removed | tokens before | after |
|---|---|---|---|---|
| `forth/010-lib.fth` | 34 | 25 | 1,042 | 1,022 |
| `cc/020-cc-arena.fth` | 0 | 10 | 1,976 | 1,940 |
| `cc/driver/seed-cc-start.fth` | 10 | 8 | 1,993 | 1,829 |
| `kernel/tools/k1-direct-start.fth` | 9 | 8 | 934 | 811 |
| `tinycc/catm-start.fth` | 10 | 8 | 691 | 634 |

The library's 34 lines are the replacements of section 2 (`latest`,
`here`, `,`, `execute`, `r@`, `'`, `bye`, `branch`, `0branch`, `[lit]`,
`read-token`, `emit`); its 25 removed lines are what worked around the
old seed: `read-word-addr`, which decoded the CALL inside `'` to reach
the reader; `token`, which blanked the token buffer to recover a length
the seed kept in a register; `tib`; `lit-xt` and `lit-literal`.  The
launchers lose the same `token` and `tib` and gain the replacements they
use.  No machine code moved into Forth: the library lays the same bytes
with `c,` as before (the 18-byte push and the CALL opcode).

Loading the library and every compiler layer (775 KB, then failing on an
empty C source), `perf stat`, three runs each:

| | instructions | cycles |
|---|---|---|
| 1,772-byte seed | 126.1 M | 353 to 358 M |
| this seed | 175.0 M | 320 to 352 M |

More instructions, because `here`, `,`, `c,`, `branch` and `0branch` are
Forth now; no more cycles, because the library's literals are an inline
push from the start instead of a CALL to `lit`, whose rewritten return
address the processor mispredicts.  `./check-all.sh` takes 29.9 s with
either seed.  The library's dictionary is about 510 bytes larger.  HERE
after `cc/020`, which must stay below 0x410000 for `skip-vm-pages`, is
0x40F2xx in the host's load order (0x40F0xx before) and 0x40F7CC in
K1's, where `kernel/k1/boot/k0-syscalls.fth` comes first (0x40F5xx
before): 2,100 bytes of headroom left there, of about 2,600.

Every oracle, on a clean `build-out`, with the seed as it is after the
review of section 4 (`seed-forth` 8a1a5655...):

- `CHECK_TINYCC=1 CHECK_HEX0_HANDOFF=1 ./check-all.sh`: 12 OK, 0 SKIP,
  0 FAIL (the two extra steps are the junction check below and the
  hand-off: K0 runs the seed, which builds the first tcc and
  builder-hex0's disk, and boot 2 reaches live-bootstrap's `tcc`); `check-outputs: 5 as pinned,
  0 differ, 0 not built` (seed-cc, seed-ar, Stage A's `cc-out-v1`, the K1
  runner, K1).
- `tinycc/build-first-tcc.sh`: `d9e97270...`, as pinned.
- `tests/tinycc/junction-check.sh`: `/usr/bin/tcc` `b9dce87d...` and the
  six libraries the same as live-bootstrap's.
- `kernel/k1/run-chain.sh --direct-smoke` (the seed under K0 in QEMU):
  PASS in 17.4 s (18.1 s with the 1,772-byte seed).  Its serial log has
  `k0: K1 built by seed Forth; handing over`, `k1: seed-forth built by
  hex0-seed` and the K1 PASS line.
- `tests/seed/asm-check.py`: GNU as on the comments writes 1091 of 1091
  bytes; `seed/check.sh` (since removed, with `seed.asm`): nasm's bytes
  equal hex0-seed's.

Not run: `CHECK_CHAIN=1` and `CHECK_K1=linux`.  Swept instead: every
place either runs `seed-forth` gives it a ported launcher
(`cc/driver/seed-cc-start.fth` in `chain/plumbing-root.sh` and
`kernel/k1/direct.recipe`; `kernel/tools/k1-direct-start.fth` as K0's
init) or an input that starts with `forth/010-lib.fth` (seed-cc's
generated inputs, `kernel/tools/k1-direct.recipe`); no file under
`chain/` or `kernel/` states the seed's size or hash; the Linux
initramfs holds only `chain/ladder/init.c`'s program.  The smoke run
covers the first minute of `CHECK_K1=linux` (K0, the seed building K1,
K1 running the seed and seed-cc).

What adopting it would still need: the book (forth-bootstrap-book)
quotes `seed/000-seed.hex0`, `forth/010-lib.fth`, `forth/130-asm.fth`,
`cc/020-cc-arena.fth` and `cc/030-cc-io.fth` byte for byte (130 and 030
change by one comment each, naming the seed's pages), and its seed
chapters teach the 32 primitives in the old order; `HISTORY.md` and the results table in
`README.md` still describe the 1,772-byte seed as history.

## 4. Readability review

The seed was read top to bottom, in the hex0, as a reviewer who trusts
nothing would read it.  What was changed, and where size and clarity
pulled against each other:

Changed for clarity, at a cost in bytes:

- `key` zeroed `rdi` once for two purposes: the fd argument, and the
  answer at end of input.  It now has its own `xor edi, edi` on an
  end-of-input path (+3 bytes).
- `read_char` sat among the loop's routines; it moved next to `token`,
  its only caller (and `token`'s jump to `fatal` became short, -4 bytes).
- `;` was the last header, so `_start`'s LATEST line read
  `0x400423 (; header) ; the last header`, a comment that seems to start
  inside the parentheses, and `asm-check.py` needed a special case to
  split it.  `state` is last now and the checker's split is as it was.

Chosen for size, and why it is still clear enough:

- `rbx` as the sysvar page (about 100 bytes, computed from the encodings
  of the 26 lines that use it, not assembled both ways).  One more reserved register,
  stated in the conventions block and in `cc/020`'s note on native words.
  The lines get shorter and name what they touch: `mov rax, [rbx+HERE]`.
- `jmp drop_code` at the end of `>r`, `!`, `c!`, `compile_call` and
  `read_char`, and `call dup_code` at the start of `key`, `state`, `r>`,
  `lit` and `token` (3 to 6 bytes each).  Each such line carries the stack
  effect; the alternative is the same two instructions written out ten
  more times.
- `test ch, ch` for "length reached 256" (4 bytes less than `cmp ecx,
  256`).  The old seed had the same line with `bh`; its comment says what
  `ch` is.
- `number` starts from the 0 that `find` left on the stack instead of
  zeroing a register.  The routine's stack comment, `( 0 -- n | )`, is
  that fact.
- Whitespace is one compare, `cmp al, 0x20`, with end of input (0) falling
  on the whitespace side; the two loops that would spin on it test for 0
  first.  The header comment of `token` says so.  Four compares, as
  before, would cost an estimated 14 bytes more.
- `cmp eax, 9` / `ja` after subtracting '0' rejects bytes on both sides of
  the digits with one unsigned compare; the line says so.

Chosen for clarity over size:

- `find` compares names with a plain indexed loop (20 bytes) instead of
  `repe cmpsb` with two registers saved around it (15), whose result for
  an empty name depends on flags left by an earlier compare.
- `0=` is `test`, `sete`, `movzx`, `neg` (15 bytes), not `cmp rdi, 1` /
  `sbb rdi, rdi` (7).
- Pointers are moved with 64-bit instructions (`add rbp, 8`) although
  every address fits in 32 bits; only constants and counters use the
  32-bit forms, and the conventions block says what those do to the upper
  half.
- No entry-state assumptions except the zero-filled segment (ELF's
  definition of p_memsz > p_filesz, relied on for STATE and LAST_FOUND).
  The registers are set, not assumed.
- The ELF headers stay two full, separate structures.

In the library, the two definitions that a reader has to stop at are
`: execute  >r ;` and `0branch`.  Both are short, both have the
explanation next to them, and both are Forth that `test.sh` exercises
(every `if,` and loop in the repository goes through `0branch` until
`cc/020` lays inline jumps); in the old seed they were 12 and 28 bytes of
machine code.

Left as it was although it could be smaller: the `"tok?"` message, the
256-byte check, `\` comments in the reader, `*` and `/` (section 2).

## 5. The hand-written seed: 1,051 bytes

The prototype's design is kept whole: the same 21 words, the same header
layout (link, flags, nlen, name, which the library and `cc/020` read), the
same loop and the same memory map.  The file was rewritten directly in
hex0 with tighter encodings, each of which its line's comment explains.
Nothing moved into the library and no downstream output changed.

| | 1,091-byte prototype | hand-written |
|---|---|---|
| file | 1,091 | 1,051 |
| ELF headers | 120 | 120 |
| dictionary header fields | 267 (21 headers) | 267 (21 headers) |
| code | 704 (222 instructions) | 664 (218 instructions) |

| routine | was | now | change |
|---|---|---|---|
| `number` | 74 | 71 | `add qword [rbx+HERE], 8` replaces load, add and store |
| `fatal`, `end_of_input`, `exit` | 42 | 32 | `push 1` / `pop rax` / `mov edi, eax` (1 is both SYS_write and stdout); `inc edi` for status 2, since syscall keeps rdi; `push 60` / `pop rax` |
| `key` | 32 | 30 | `lea edx, [rdi+1]`: rdi is 0 there, so edx = 1 |
| `swap` | 12 | 5 | `xchg rdi, [rbp]` |
| `0=` | 15 | 8 | `cmp rdi, 1` / `sbb rdi, rdi`: n - 1 borrows only when n = 0 |
| `:` | 61 | 57 | `mov byte [rbx+STATE], 1` |
| `;` | 22 | 15 | `inc qword [rbx+HERE]`; `mov byte [rbx+STATE], 0` |

The byte stores to STATE rely on one invariant, stated in the file's
conventions block and in both comments: STATE only ever holds 0 or 1.  The
seed writes only 0 and 1, and every library and launcher write is a whole
cell of 0 (`0 state !`), so STATE's upper seven bytes are never set.

Considered and not done:

- Moving `*` and `/` to Forth (49 bytes).  The library has no shifts, so
  multiplication would be repeated doubling and addition, and division a
  bit-at-a-time loop on top of `0<`, which the library itself builds from
  `/`.  Both would be needed in the library and again in each launcher
  that uses them, before `cc/020` replaces them with native code, and the
  compiler divides constantly (`,4`, the byte writers).  About 30 lines of
  Forth in four places, and slower loads, for 49 bytes: kept in the seed.
- A 4-byte link field (21 x 4 = 84 bytes): every address is below 4 GiB,
  but the library, the launchers and `cc/020` read the 8-byte layout.  Not
  done.
- Overlapping the ELF headers: as before, not done.

Checked: `tests/seed/asm-check.py` gives "1051 of 1051 bytes" from GNU as
and the same 1,051 bytes from llvm-mc; the check-all, TinyCC and hand-off
results are in the commit that made the change.

