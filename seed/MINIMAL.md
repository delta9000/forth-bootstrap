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

Compared with other small Forths: sectorforth and milliforth keep `@ !
sp@ rp@ 0= + nand exit key emit` plus `:` and `;` and build the rest in
Forth, with indirect threading on a 16-bit machine.  This seed keeps the
same core, with `dup drop swap >r r>` in place of `sp@ rp@` (the top of
stack is in a register, so `sp@`-built stack words would be slower and
harder to follow than three two-instruction words), no `emit` (see
below), and adds only what a C compiler's host needs to be usable:
bytes (`c@ c!`), `* /` and `syscall6`.  jonesforth is the other extreme:
well over a hundred words in assembly, including the number parser, the
interpreter and the control-flow words; the previous seed was a small
step in that direction with 32.

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
with `mask = flag 0=`.  sectorforth's `?branch` does the same.

### Encoding changes that are not removals

- `rbx` holds the sysvar page.  `mov rax, [rbx+HERE]` is 4 bytes where
  `mov rax, [0x413010]` is 8, and the seed has about twenty such lines.
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
  and long division, 64 iterations each, about 15 lines, in the library
  and again in each launcher that multiplies or divides (all three
  divide).  `forth/130-asm.fth` and the launchers run without `cc/020`,
  so they would run at that speed.  Nine instructions of the plainest
  machine code in the file against 15 lines of intricate Forth in four
  places: kept.
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

As assembly first: `seed/seed.asm` (NASM), from which `seed/asm2hex0.py`
writes `seed/000-seed.hex0` in the commented form it has always had, the
way `kernel/k0/k0.asm` becomes `k0.hex0`.  The hex0 is still what is
built and still what a reviewer reads; the assembly source exists so that
offsets, link fields and branch distances are never recomputed by hand,
which is where an edit to the old file went wrong most easily.  Three
tools then have to agree on every byte: nasm (via `asm2hex0.py`),
stage0's hex0 (`seed/check.sh` compares its output with nasm's) and GNU
as on the hex0's comments (`tests/seed/asm-check.py`, which needed only
the new memory-map form: sysvar names are offsets from `rbx`).

## 3. The prototype, measured

| | 1,772-byte seed | this seed |
|---|---|---|
| file | 1,772 | 1,092 |
| ELF headers | 120 | 120 |
| dictionary header fields | 421 (32 headers) | 267 (21 headers) |
| code | 1,231 | 705 |
| instructions (lines of machine code) | 338 | 220 |
| words with a header | 32 | 21 |

Where the 705 bytes of code are:

| routine | bytes | | routine | bytes |
|---|---|---|---|---|
| `_start` | 26 | | `token` | 82 |
| `repl` | 61 | | `key` | 29 |
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
either seed.  HERE is 0x40F2xx after `cc/020` (0x40F0xx before), below
the 0x410000 that `skip-vm-pages` needs.

Every oracle, on a clean `build-out`, with `seed-forth` 9c1de563...:

- `./check-all.sh`: 10 OK, 0 SKIP, 0 FAIL; `check-outputs: 5 as pinned,
  0 differ, 0 not built` (seed-cc, seed-ar, Stage A's `cc-out-v1`, the K1
  runner, K1).
- `tinycc/build-first-tcc.sh`: `d9e97270...`, as pinned.
- `tests/tinycc/junction-check.sh`: `/usr/bin/tcc` `b9dce87d...` and the
  six libraries the same as live-bootstrap's.
- `kernel/k1/run-chain.sh --direct-smoke` (the seed under K0 in QEMU):
  PASS.
- `tests/seed/asm-check.py`: GNU as on the comments writes 1092 of 1092
  bytes; `seed/check.sh`: nasm's bytes equal hex0-seed's.

Not run: `CHECK_CHAIN=1` and `CHECK_K1=linux`.

What adopting it would still need: the book (forth-bootstrap-book)
quotes `seed/000-seed.hex0`, `forth/010-lib.fth` and
`cc/020-cc-arena.fth` byte for byte, and its seed chapters teach the 32
primitives in the old order; `HISTORY.md` and the results table in
`README.md` still describe the 1,772-byte seed as history.
