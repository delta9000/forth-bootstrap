# The host contract: Forth-laid machine code on the i386 seed

`seed/SPEC.md` specifies the seed. This document specifies everything
between that seed and the C compiler's output: the machine code that the
Forth library and the compiler lay down *for the Forth system itself to
execute*, the system calls they make, how they get memory and input,
which files carry that code, and the boot that runs it all on
builder-hex0.

It was written before any of those files. The seed, the host files,
kaem, the boot and the checks all exist now, and the text says what they
do. When it was written an x86-64 seed, library and compiler stood
beside these files, and each file here began as a counterpart of one of
those; they are at tag `experiments-2026-11-21`, and this document
mentions them only where they explain a choice.

Conventions are `seed/SPEC.md`'s: MUST and FREE, 8-byte cells, a file
with a word's name for a dependent, `B2:<line>` for builder-hex0's stage
2, `P§n` for `tests/builder-hex0/README.md`, **[measured]** and
**[designed]**. "SPEC n" is a section of `seed/SPEC.md`.

## 1. Two axes: the host and the target

Machine code is written in two places in this repository, for two
different programs.

- **The target**: what the C compiler emits. `cc/090-cc-emit.fth`,
  `cc/117-cc-native-program.fth` and `cc/119-cc-runtime.fth` hold the
  i386 encoders (ILP32, ELF32, `int 0x80`). Their bytes go to the output
  file through `cc-emit-byte` and `x{ }` and are executed by the
  compiled C program. `tests/cc/asm-check.py` checks them.
- **The host**: the processor the Forth system itself runs on. Host code
  goes into the dictionary through `c,` and `c{ }` and is executed
  during the compile. `tests/forth/asm-check.py` checks it.

Both are i386. They are still independent: the two use different
registers for different things (the host's top of stack is edx:eax and
its stack pointer esi; the compiled program's value is edx:eax and its
stack is esp), and a change to one leaves the other's bytes alone.

This document is about the host axis only.

## 2. The machine model for host code

Forced by SPEC 4 and 5; restated here as the rules for anyone writing a
host code word.

| register | role |
|---|---|
| edx:eax | top of the data stack: eax the low half, edx the high half |
| esi | data-stack pointer; `[esi]`, `[esi+4]` the second item; a push subtracts 8 |
| esp | return stack, 8-byte cells |
| ebx, ecx, edi, ebp | scratch: free inside a word, undefined across any call |

- **Cells.** 8 bytes, low half at the lower address, in memory and on
  both stacks. Addresses, lengths and descriptors have a zero high half.
  A word that takes an address uses the low half.
- **Calling.** `push 0` then `call` (7 bytes: `6A 00 E8 rel32`); return
  with `ret 4` (`C2 04 00`). A word may also be left by a jump to another
  word's first byte.
- **Inline `>r`, `r>`, `r@`.** `>r` pushes the high half, then the low
  half, so the cell's low half is at `[esp]`.
- **System calls.** Host code makes none itself. Every call goes through
  the seed's `syscall6`, which restores esi and sign-extends the result
  (SPEC 7.5). This keeps the two builder-hex0 rules in one place: nothing
  below esp, and nothing assumed preserved across `int 0x80` (SPEC 4.1).
- **Multiply and divide.** Host code lays no `mul`, `imul` or `div`. `*`
  and `/` stay compiled calls to the seed's words, which carry the 64-bit
  semantics (SPEC 7.1).
- **Flags.** The direction flag stays clear. No word relies on flags
  across a call.
- **String instructions** use esi, so a word that wants one saves and
  restores esi. None of the sites below needs one.

Why TOS is edx:eax: it is the pair the processor itself uses for 64-bit
products, dividends and sign extension, so the seed's `*`, `/` and
`syscall6` need no moves, and `xchg` with eax has the one encoding both
assemblers agree on (SPEC 12, rule 7). Why esi and not ebp: `[esi]`
needs no displacement byte, and with the sysvars reached by absolute
address no base register is needed at all, which leaves four scratch
registers.

## 3. Which files carry the host

| file | what it holds for the host |
|---|---|
| `forth/010-lib.fth` | the library: the system-call words, the code-laying words (`ret,`, `push-imm64,`, `call,`), `native!`, `brk-alloc` (section 5) and the input words (section 6) |
| `forth/020-cc-arena.fth` | the library's primitives again as machine code, and inline forms of them for later definitions (section 4.2); the hash-table `find`; the compiler's arena |
| `forth/layers.fth` | the load list: `include` lines for `forth/020-cc-arena.fth` and then `cc/030-cc-io.fth` to `cc/119-cc-runtime.fth` in numeric order. The library is not in it: the seed has read it already (section 6) |
| `cc/030-cc-io.fth` | no machine code; the two places the compiler meets the kernel: `cc-workspace-map` gets memory from `brk-alloc`, and `cc-input-file`, `cc-load-file` and `cc-load-files` read the C sources by name (section 6.4) |

The two files of machine code are quoted byte for byte by the book.

Nothing above `forth/020-cc-arena.fth` lays host machine code.
`cc-nzero` in `cc/115-cc-native.fth`, which zeroes 24 to 2,600 bytes at
a time, is a loop of `c!` in Forth.

### 3.1 How the two files came to be

Both began as copies of the x86-64 library and arena file with a known
set of lines changed, and a check held each difference to a committed
`.diff` until the x86-64 files left the branch. That check and its pins
are at tag `experiments-2026-11-21`. What holds the files now is section
9: the assembler check on every byte line, the vectors, and the pinned
bytes of everything the compiler builds.

## 4. Every host machine-code site

The complete list of bytes that the Forth host executes and that some
Forth file lays down above the seed. The encodings were assembled with
GNU as 2.47 and llvm-mc 23.1.5, which agree on all of them
**[measured]**; `tests/forth/asm-check.py` repeats that on the files' 94
byte lines.

In `forth/020-cc-arena.fth` each sequence used more than once is a word
of its own, named with a trailing comma (`push-tos,`, `pop-tos,`,
`pop-sub,`, `pop-xor,`, `0=,`, `sign-ebx,`, `sign-edx,`, `not,`, `-,`,
`1+,`, `1-,`, `over,`, `drop-2,`, `and,`, `or,`, `pop-rsub,`), and the
code word and the inline form of a primitive both call it. On this host
a sequence is two to five instructions and would otherwise be written
out up to five times.

Building blocks used below:

| name | bytes | instruction |
|---|---|---|
| `push-tos,` | `83 EE 08` `89 06` `89 56 04` | `sub esi, 8`; `mov [esi], eax`; `mov [esi+4], edx` |
| `pop-tos,` | `8B 06` `8B 56 04` `83 C6 08` | `mov eax, [esi]`; `mov edx, [esi+4]`; `add esi, 8` |
| `pop-sub,` | `8B 0E` `8B 5E 04` `29 C1` `19 D3` `83 C6 08` | ebx:ecx = second - TOS, second dropped: `mov ecx, [esi]`; `mov ebx, [esi+4]`; `sub ecx, eax`; `sbb ebx, edx`; `add esi, 8` |
| `pop-xor,` | `33 06` `33 56 04` `83 C6 08` | TOS = second xor TOS, second dropped: `xor eax, [esi]`; `xor edx, [esi+4]`; `add esi, 8` |
| `0=,` | `09 D0` `83 F8 01` `19 C0` `89 C2` | all ones if edx:eax = 0: `or eax, edx`; `cmp eax, 1`; `sbb eax, eax`; `mov edx, eax` |
| `sign-ebx,` | `C1 FB 1F` `89 D8` `89 DA` | TOS = ebx's sign bit, 64 times: `sar ebx, 31`; `mov eax, ebx`; `mov edx, ebx` |
| `sign-edx,` | `C1 FA 1F` `89 D0` | TOS = its own sign bit, 64 times: `sar edx, 31`; `mov eax, edx` |
| `not,` | `F7 D0` `F7 D2` | `not eax`; `not edx` |
| `drop-2,` | `8B 46 08` `8B 56 0C` `83 C6 10` | the third item becomes TOS: `mov eax, [esi+8]`; `mov edx, [esi+12]`; `add esi, 16` |

### 4.1 `forth/010-lib.fth`

The library is Forth text built on the seed's words. These are its
definitions that depend on the machine:

| word | what | on this host |
|---|---|---|
| the comment on `syscall6` | the argument registers and the call numbers | ebx, ecx, edx, esi, edi, ebp; 1, 3, 4, 5, 6, 45 |
| `write` | | `0 0 0 4 syscall6` |
| `die` | | `0 0 0 0 0 1 syscall6` |
| `open`, `read`, `close` | | numbers 5, 3, 6 |
| `brk` | | `0 0 0 0 0 45 syscall6` |
| `ret,` | a return | `C2 04 00` |
| `push-imm64,` | 18 bytes that push a literal | `push-tos,`'s bytes, then `B8 imm32` (`mov eax,` the low half) and `BA imm32` (`mov edx,` the high half) |
| `push-body,` | the push and a return | 21 bytes |
| `call,` | a call | `6A 00 E8 rel32`, rel32 from the address after the 7 bytes |
| `exit,` | | `ret,` |
| `create` | the data area's address | `here 21 +` |
| `defer-code-size` | | 35 = 18 + 7 + 7 + 3 |
| `native!` | a jump over a word's first 5 bytes | `E9 rel32`. Every word it is applied to is at least 10 bytes long (a call and a return) |

Before `c{ }` exists the library lays these bytes with decimal `N c,`;
each such line carries the hex and the instruction as its comment, and
the assembler check reads them.

Definitions whose text depends on the machine without naming a byte, and
why they hold:

- `latest`, `here-addr`, `,`: the sysvars are 8-byte cells at fixed
  offsets (SPEC 3.3).
- `execute`, `r@`, `branch`, `0branch`: return addresses are cells (SPEC
  5.2 traces all four).
- the control-flow words `if,` to `again,`: the cell after a branch call
  is laid by `,` and read by `@`, 8 bytes.
- `immediate`, `found-immediate?`: the header layout (SPEC 6.1).
- `,4`: `256 /` on a 64-bit cell, with the seed's unsigned `/`.
- `compile-literal`, `hex-lay`: built on `push-imm64,` and `call,`.

HERE starts at `state` + 4096, above the data stack and the sysvar page
(SPEC 3.1), and no word moves it over them.

The last section of the file has the words of section 5 (`brk`,
`brk-alloc`) and section 6 (`arg`, `included`, `include`, `file-key`,
`include-job`).

### 4.2 `forth/020-cc-arena.fth`

| word | what | bytes |
|---|---|---|
| `code:` | a header only; `c,` lays the body | |
| `-` | | `pop-sub,`, `89 C8` `89 DA` (`mov eax, ecx`; `mov edx, ebx`) |
| `0<` | | `sign-edx,` |
| `<` | the sign of a - b | `pop-sub,`, `sign-ebx,` |
| `=` | | `pop-xor,`, `0=,` |
| `1+` | | `83 C0 01` `83 D2 00` (`add eax, 1`; `adc edx, 0`) |
| `1-` | | `83 E8 01` `83 DA 00` (`sub eax, 1`; `sbb edx, 0`) |
| `rel32!` | stores a displacement with `,4` | Forth |
| `flag-test,` | pop the flag and test it | `09 D0` `8B 06` `8B 56 04` `8D 76 08` (`or eax, edx`; `mov eax, [esi]`; `mov edx, [esi+4]`; `lea esi, [esi+8]`). The `lea` is there in place of `pop-tos,`'s `add` so that the zero flag from `or` reaches the jump |
| `jz-fwd,` `jmp-fwd,` `jz-back,` `jmp-back,` | | `0F 84 rel32`, `E9 rel32` |
| `if,` … `again,` | | Forth, on the four above |
| `dup`, `drop` inline | | `push-tos,`; `pop-tos,` |
| `swap` inline | | `87 06` `87 56 04` (`xchg eax, [esi]`; `xchg edx, [esi+4]`) |
| `over` inline, and as a code word | | `push-tos,`, `8B 46 08` `8B 56 0C` (`mov eax, [esi+8]`; `mov edx, [esi+12]`) |
| `@` inline | | `8B 50 04` `8B 00` (`mov edx, [eax+4]`; `mov eax, [eax]`): the high half first, because the second load overwrites the address |
| `c@` inline | | `0F B6 00` `31 D2` (`movzx eax, byte [eax]`; `xor edx, edx`) |
| `!` inline | | `8B 0E` `89 08` `8B 4E 04` `89 48 04` (`mov ecx, [esi]`; `mov [eax], ecx`; `mov ecx, [esi+4]`; `mov [eax+4], ecx`), then `drop-2,` |
| `c!` inline | | `8B 0E` `88 08` (`mov ecx, [esi]`; `mov [eax], cl`), then `drop-2,` |
| `+` inline | | `03 06` `13 56 04` `83 C6 08` (`add eax, [esi]`; `adc edx, [esi+4]`; `add esi, 8`) |
| `-`, `1+`, `1-` inline | | as their code words |
| `jmp-xt,` | a jump to an xt | `E9 rel32` |
| `>r` inline | | `52` `50` (`push edx`; `push eax`), `pop-tos,` |
| `r>` inline | | `push-tos,`, `58` `5A` (`pop eax`; `pop edx`) |
| `r@` inline | | `push-tos,`, `8B 04 24` `8B 54 24 04` (`mov eax, [esp]`; `mov edx, [esp+4]`) |
| `>r`, `r>`, `r@` interpreted | must add no call frame of their own | a jump (`jmp-xt,`) to the seed's word (SPEC 5.2, the fifth case) |
| `*` and `/` | | none: both stay calls to the seed (section 2) |
| `0=` inline | | `0=,` |
| `and`, `or`, `nand` | code words for `and` and `or`, inline forms of all three | `23 06` `23 56 04` `83 C6 08`; `0B 06` `0B 56 04` `83 C6 08`; for `nand` the `and` bytes and `not,` |
| `in-range,` for `digit?`, `alpha-lower?`, `alpha-upper?` | an unsigned compare of the whole cell | `83 E8 low` `83 DA 00` `83 F8 count` `83 DA 00` `19 C0` `89 C2`: `sub eax, low`; `sbb edx, 0`; `cmp eax, count`; `sbb edx, 0`; `sbb eax, eax`; `mov edx, eax`. The second `sbb` leaves carry set exactly when the 64-bit difference is below count |
| `alpha?`, `space?`, `true`, `<>`, `>`, `<=`, `>=`, `nip`, `rot`, `2dup`, `2drop`, `+!`, `-!`, `bytes-eq` | the library's text compiled again with the inline forms, and the old word redirected with `native!` | Forth |
| `=` inline | | `pop-xor,`, `0=,` |
| `<>` inline | | `pop-xor,`, then `09 D0` `F7 D8` `19 C0` `89 C2` (`or eax, edx`; `neg eax`; `sbb eax, eax`; `mov edx, eax`) |
| `<` inline | | `pop-sub,`, `sign-ebx,` |
| `>=` inline | | `<`, then `not,` |
| `>` inline | the sign of b - a | `pop-rsub,`: `2B 06` `1B 56 04` `83 C6 08` (`sub eax, [esi]`; `sbb edx, [esi+4]`; `add esi, 8`), then `sign-edx,` |
| `<=` inline | | `>`, then `not,` |
| `0<` inline | | `sign-edx,` |
| `constant`, `create` | the push, a call to `push-or-compile`, a return | 28 bytes = 18 + 7 + 3; `here 28 +` |
| the hash table of `fh-find` | 2 MiB | `2097152 brk-alloc` (section 5) |
| `cc-arena-map` | the arena | `brk-alloc`; dies 10 if the result is 0 |

Comparisons keep the meaning the library's own definitions have: `<` is
the sign bit of the wrapped 64-bit difference, and so on
(`forth/010-lib.fth`, `<`).

The hash walk (`fh-insert`, `fh-index`, `fh-find`) is Forth: 8-byte
links and nodes, header offsets 9 and 10, LAST_FOUND through
`latest 16 +`. `' find ' fh-find native!` puts it in place of the seed's
`find`. Everything after it in the file (the lexer's state block,
`cc-die`, `cc-check-cap`, `cc-alloc`) is Forth as well.

There is no buffered `key`: input is section 6's, in Forth.

### 4.3 The other files

| site | what |
|---|---|
| `cc/030-cc-io.fth`, `cc-workspace-map` | memory for the preprocessor's workspaces, from `brk-alloc`; dies when the answer is 0 or less. Its one caller is in `cc/040-cc-prep.fth` |
| `cc/030-cc-io.fth`, `cc-input-file`, `cc-load-file`, `cc-load-files` | the C source read by name (section 6.4): descriptor 0 has no end on builder-hex0 |
| `cc/115-cc-native.fth`, `cc-nzero` | Forth, a loop of `c!` |
| `tinycc/tcc-compile.fth`, `tinycc/tool-compile.fth` | no machine code. They call `cc-arena-map` with 8,388,608, `cc-load-files`, and `open`, `write`, `close` with flags 577 and mode 384 or 493 (`O_WRONLY`, `O_CREAT`, `O_TRUNC` as i386 Linux numbers them) |

A search of every `.fth` file in the repository for `c{`, `code:`,
`native!`, runs of `N c,` and `syscall6` finds host code in
`forth/010-lib.fth` and `forth/020-cc-arena.fth` and in no other file
the route loads **[measured]**; `tests/seed/boot.fth` calls `syscall6`
for its own output.

## 5. System calls and memory

### 5.1 The calls the host makes

| word | effect | number |
|---|---|---|
| `die` | ( status -- ) | 1, `exit` |
| `read` | ( fd buf count -- n ) | 3 |
| `write` | ( fd buf count -- n ) | 4 |
| `open` | ( path flags mode -- fd ) | 5 |
| `close` | ( fd -- err ) | 6 |
| `brk` | ( addr -- break ) | 45 |

No other call is made by Forth: no `mmap` (builder-hex0 answers 0, which
a caller would take for an address, P§1), no `lseek`, no `fork`, no `execve`. All six are implemented by
builder-hex0 (P§1).

What survives a `syscall6`: edx:eax is the result, esi and esp are as
the stack effect says, and nothing else (SPEC 7.5). Failure is a
negative cell on both kernels and MUST be tested with `0<`, never by
comparing with an errno: builder-hex0 answers -1 where Linux answers -2
(P§5).

File rules the host keeps on builder-hex0 (P§5):

- a path is at most 255 bytes;
- the output file is created and written after every input has been
  read, and nothing else is created until it is closed: only the newest
  file can grow without overwriting its neighbour. The drivers already
  write the output in one loop at the end;
- every file opened is closed: a process has 448 descriptor slots and
  the kernel does not check the bound (B2:98, 1077-1085). A first-tcc
  compile makes 980 `open` calls **[measured]**.

### 5.2 `brk-alloc` ( bytes -- addr | 0 )

The only way the host gets memory outside the image.

1. `0 brk` gives the current break, cur.
2. new = cur + bytes rounded up to a multiple of 4096. If new is above
   0x28000000, or the addition wrapped, answer 0.
3. `new brk`. If the result is not new, answer 0. (Linux answers the old
   break when it refuses.)
4. Answer cur.

Properties:

- The break only rises. A request below the current break never returns
  on builder-hex0 and wipes every file (P§2). There is no word that
  frees.
- The memory is zero: builder-hex0 zeroes from the old break to the new
  (B2:1435-1441), and Linux hands out fresh pages.
- It cannot overlap the dictionary: the seed has raised the break to the
  image's end, 0x0A048000, before any Forth runs (SPEC 3.2).
- The cap keeps it out of 0x30000000 and above, where builder-hex0 keeps
  this process's argument strings and the saved parents, kaem among
  them; the break has no bound of its own (P§2). The need is 19 MiB:
  a compile makes three requests, of 2,097,152 bytes for the hash table
  (`forth/020-cc-arena.fth`), 8,388,608 for the arena (`cc-arena-map`
  in the drivers) and 9,437,184 for the preprocessor's workspaces
  (`cc/040-cc-prep.fth`).
- On Linux the break of a 32-bit program is below 2^31, so the
  sign-extended result of `brk` is the address.

## 6. Input

The seed reads one file, the one named by its first
argument, and exposes two cells: INPUT, the descriptor `key` reads, and
ARGV, where the kernel left the argument pointers (SPEC 3.3). The
library builds the rest. The command line of every run is

    seed-forth forth/010-lib.fth JOB [ARG ...]

Why one name and an `include` in the library, not several names read by
the seed: the seed then needs no loop over its arguments and no rule for
which arguments are files, and the arguments after JOB are free to carry
names (section 6.5). The cost in the seed is two stores at entry and a
`key` that fetches its descriptor from memory.

### 6.1 The words

| word | effect | behaviour |
|---|---|---|
| `arg` | ( i -- zaddr \| 0 ) | the i-th argument's address, 0 past the last. The kernel's pointers are 4 bytes: the cell read at ARGV + 4·i is masked to its low half |
| `included` | ( zaddr -- ) | open the NUL-terminated path read-only. A negative descriptor is fatal: the path, `?` and a newline on descriptor 1, exit 2. Otherwise push the current INPUT on the include stack and make the new descriptor INPUT |
| `include` | ( "name" -- ) | read a token, put a NUL after it in the token buffer (which has two spare bytes, SPEC 3.3), `included` |

The include stack holds 16 descriptors; a 17th is fatal in the same way.

### 6.2 The `key` replacement

`key` is redirected, with `native!`, to `file-key`, a word written in
Forth:

- read one byte from INPUT with `read`; if there is one, answer it;
- at the end of a file with an empty include stack, answer 0: this is
  the end of input, and the interpreter exits 0 as before;
- at the end of an included file: close it, pop the previous descriptor
  into INPUT, and answer 10, a line feed.

The line feed makes the end of an included file act as whitespace and as
the end of a line. Without it a last token with no newline after it
would join the includer's next token, and a `\` comment on the last line
would swallow the includer's next line.

Because the seed's `token` fetches every byte through `key`'s xt (SPEC
7.7), and its `key` neither reads ahead nor remembers the end of a file
(SPEC 7.2), the switch is seamless: `include` returns to the
interpreter, whose next token comes from the new file, and when that
file ends the rest of the includer's line follows.

The redirection is done once, in the library, as soon as the words it
needs exist (after the outer interpreter has taken over, where control
flow is available). The library therefore defines `native!` itself, and
`forth/020-cc-arena.fth` uses the library's.

Reading is one `read` per byte. A first-tcc run reads 367 KB of Forth:
about 23 ms on builder-hex0 at 242 cycles a call (P§7) and a few tenths
of a second on Linux. No buffer is kept.

### 6.3 The library's last line

After its last definition the library runs `include-job`: `2 arg`, and
if that is not 0, `included`. So JOB is read next, and when JOB ends the library
file ends, which is the end of input.

### 6.4 C source by name

`cc/030-cc-io.fth` has:

- `cc-input-file` ( zaddr -- ): append a path to a list of at most 8; a
  ninth dies with 20;
- `cc-load-file` ( zaddr -- ): open the path (die 20 if that fails), read
  it to its end with `cc-read-all` into `cc-in-buf` directly after the
  bytes already there (die 20 when the buffer fills), and close it;
- `cc-load-files` ( -- ): `cc-src-init`, then `cc-load-file` for each
  listed path in order; `cc-in-len` is the total.

The compiler then sees the listed files one after another with nothing
between them, as one translation unit. Quoted `#include` lines resolve
beside the path given to `cc-prep-source-name`.

### 6.5 The two jobs

Two small files, each read as JOB.

`tinycc/jobs/tcc-first.fth`, run as
`… tcc-first.fth OUT SOURCE INCLUDE INCLUDE-LINUX`:
`include forth/layers.fth`; define `tcc-output` as argument 3; give
SOURCE to `cc-prep-source-name` and the two include paths to
`cc-prep-add-include`, each with its length; list SOURCE as the one
input file; `include tinycc/tcc-compile.fth`. The driver names no file,
so the boot's paths can differ from the host's (section 7.3).

`tinycc/jobs/tool.fth`, run as `… tool.fth OUT SOURCE [SOURCE ...]`:
`include forth/layers.fth`; define `tool-output` as argument 3 and
`tool-source` as the last argument, and give that one and its length to
`cc-prep-source-name`; list `tinycc/m2libc-native.c` and then each
SOURCE as input files; `include tinycc/tool-compile.fth`. Several SOURCE
arguments are for kaem: `tinycc/m2libc-kaem.c` (section 7.4) and its
three files, which M2-Mesoplanet also compiles as one unit
(`vendor/stage0-posix/x86/mescc-tools-mini-kaem.kaem:262-274`).

The compiler's output does not depend on these strings **[measured]**
(SPEC Appendix C): the first tcc has the same bytes with its sources in
another directory, and a tool has the same bytes when its source is
named by an absolute path of 142 bytes.

## 7. The boot

`tinycc/one-boot-disk.py` writes this disk and
`tests/tinycc/one-boot-check.sh` boots it and compares what it exports.
**[measured]** The boot takes 25 s with KVM and reaches every pinned and
published hash (section 9). Nothing on the disk is built on the host
except builder-hex0's stage 1.

### 7.1 The disk

builder-hex0's stage 1, its stage-2 hex0 source, zeros to sector
175, then the stream. The stream is what builder-hex0's shell reads
(B2:2621-2653): `src N PATH` lines with N bytes of file, and commands.

- `src 0 DIR` for every directory, each level before the ones below it:
  `open` with `O_CREAT` fails when the parent has no entry (P§5).
- Files, at their repository paths under `/`, so that the relative names
  in the Forth and C files resolve from the working directory `/`
  (relative `open` with the working directory `/` works, P§5):
  - `seed/000-seed.hex0` and
    `vendor/stage0-posix/x86/kaem-minimal.hex0`;
  - `forth/010-lib.fth`, `forth/layers.fth` and the files it lists, the
    two drivers and the two jobs;
  - the C the seed compiles: `vendor/stage0-posix/M2libc/`,
    `vendor/stage0-posix/mescc-tools-extra/`, `vendor/mescc-tools/Kaem/`
    and `vendor/mescc-tools/M2libc/bootstrappable.*`,
    `tinycc/m2libc-native.c`, `tinycc/m2libc-kaem.c`,
    `tinycc/direct-input.c`,
    `tinycc/mes-libc.c`, `tinycc/mes-libc-native.c`, the four files
    of `tinycc/tools/` that patch `ungz.c` and `untar.c`,
    `tinycc/hex0-export.c`;
  - the three archives of `tinycc/SOURCES` and their checksum file;
  - the two scripts below.
- Then three commands:

      hex0 /seed/000-seed.hex0 /seed-forth
      hex0 /vendor/stage0-posix/x86/kaem-minimal.hex0 /kaem-optional-seed
      /kaem-optional-seed /boot/seed.kaem

  and the zero byte that ends the stream.

The built-in `hex0` takes exactly this form: after the `h` it skips four
characters, reads the source name up to a space and the output name up to
a newline (B2:2245-2283), and creates the output (B2:2295). A command's
first letter selects it: `s` is `src`, `h` is `hex0`, `f` is `flush`
(B2:2626-2644), so every program path starts with `/`. The shell passes a
program exactly one argument (B2:2439-2457).

### 7.2 `/boot/seed.kaem`, run by kaem-optional-seed

kaem-optional-seed (`vendor/stage0-posix/x86/kaem-minimal.hex0`) runs
plain commands: tokens split at spaces, tabs and newlines, `#` comments,
no variables, no `cd`, no search path, and it stops when a command's
status is not 0. It does not check that a program exists, and `execve` of
a missing file stops the machine (P§4), so every path in this script
MUST be on the disk or made by an earlier line. Two lines:

    /seed-forth /forth/010-lib.fth /tinycc/jobs/tool.fth /x86/bin/kaem /tinycc/m2libc-kaem.c /vendor/mescc-tools/Kaem/variable.c /vendor/mescc-tools/Kaem/kaem_globals.c /vendor/mescc-tools/Kaem/kaem.c
    /x86/bin/kaem --verbose --strict --file /kaem.run

Each argument is under 255 bytes (P§4).

### 7.3 `/kaem.run`, run by the full kaem

**The working directory decides the order.** On builder-hex0 the root
has no entry: `chdir("/")` and `chdir("..")` fail, so a process that
leaves `/` cannot return (P§5). A program inherits the directory of the
one that starts it (read: `execve` copies it, B2:1698-1707). Every
relative path in the Forth files, from `include forth/layers.fth` on, is
relative to `/`. So every seed run MUST come before kaem's first
`cd`, and nothing before that point may need a `cd`. live-bootstrap's
text does `cd`; it comes last.

With variables and a search path, in this order:

1. The eleven tools, each one seed run of `tool.fth`, in
   `tinycc/build-tools.sh`'s order, which the sources force:
   `simple-patch.c` and `checksum-transcriber.c` are not on the disk but
   inside live-bootstrap's archive. So: the seven whose sources are on
   the disk (`catm`, `sha256sum`, `mkdir`, `cp`, `chmod`, `rm`, `match`),
   and `ungz` and `untar` from stage0-posix's sources as published, to
   `/boot/`; the three archives are checked; the stock pair unpacks
   live-bootstrap's archive in `/`; `simple-patch` is compiled from it and
   applies the two patches of `tinycc/tools/` to copies of `ungz.c` and
   `untar.c`; the patched `ungz` and `untar` are compiled and unpack the
   archive again, over the first copy; `checksum-transcriber` is
   compiled.
2. The stock `untar` reads only a 100-byte name, so it leaves the
   archive's 146 long-named files in `/` under their last components
   (`tinycc/README.md`, "Source preparation"). The disk writer checks
   that none of them has the name of a directory in `/`. The second
   unpacking puts them where they belong; builder-hex0 keeps the newer
   file of a name.
3. The first tcc's sources are prepared **in `/`**. `untar` unpacks into
   the working directory and has no option for another
   (`vendor/stage0-posix/mescc-tools-extra/untar.c:391-427`), and
   `tinycc/build-first-tcc.sh` changes directory for it, which the boot
   cannot. So tcc's and Mes's archives are unpacked to
   `/tcc-0.9.26-1147-gee75a10c` and `/mes-0.28`, and `direct-input.c`,
   `mes-libc.c` and `mes-libc-native.c` are written beside them, because
   their quoted includes are relative to their own directory
   (`tinycc/direct-input.c`). The other commands are those of
   `tinycc/build-first-tcc.sh` with `/` for the source directory.
4. One seed run of `tcc-first.fth`, with `/usr/bin/tcc-mes`,
   `direct-input.c`, `mes-0.28/include` and `mes-0.28/include/linux/x86`
   as its arguments, writes the first tcc.
5. live-bootstrap's text, with its `cd` lines: of
   `steps/mes-0.28/pass1.kaem` the unpacking and the header install, and
   `steps/tcc-0.9.26/pass1.kaem` from "# Vars" to "# Checksums" without
   the MesCC commands. It unpacks both archives again, at its own paths.
6. `hex0-export /dev/hda` with the 33 files the host compares,
   including `/seed-forth`, `/kaem-optional-seed`, `/x86/bin/kaem`,
   the eleven tools and the stock `ungz` and `untar`.

The paths the seed is given in the boot are not the host's: absolute
source names in `/boot/seed.kaem`, and the first tcc's sources in `/`.
The outputs are the same bytes all the same **[measured]** (section 6.5).

Process depth is four: the shell, kaem-optional-seed, kaem, and the seed
or a tool. builder-hex0 has 16 process slots (B2:83). A seed run under
kaem needs 32 MiB of image and 19 MiB of break, well inside the 670 MB
process area, and kaem is saved meanwhile in the area above 0x30000000.

### 7.4 kaem, compiled by the Forth compiler

`vendor/mescc-tools/Kaem` is compiled like a tool, against M2libc, with
`tinycc/m2libc-native.c` in place of M2libc's assembly. That file
lacks three calls kaem makes (`vendor/mescc-tools/Kaem/kaem.c:1070,
1097, 1106`), which M2libc defines in assembly
(`vendor/stage0-posix/M2libc/x86/linux/unistd.c:55-85`). They are in a
second file, `tinycc/m2libc-kaem.c`, which goes between
`tinycc/m2libc-native.c` and kaem's three files and is listed for
no other program:

- `fork` (2). builder-hex0 answers 0 in the child and 1 in the parent
  (P§3); kaem tests only for -1 and 0.
- `execve` (11), guarded: it calls `access` (33) first and answers -1
  without calling `execve` when the file is missing, because `execve` of
  a missing file stops the machine (P§4). kaem's own search only tests
  names without a leading `/` or `.`
  (`vendor/mescc-tools/Kaem/kaem.c:110-114,161`).
- `waitpid` (7). builder-hex0 stores the exit code shifted left by 8,
  unmasked, and answers 0 (P§3); kaem reads bits 8 to 15 and the low 7
  bits (`kaem.c:890-891`). That is what Linux gives for every code: Linux
  keeps the low 8 bits of an exit code, so 300 is 44 on both, and 256 is
  0 on both. No guard is added; a program that exits with a multiple of
  256 to report failure reports success under any kaem on Linux too.

**[measured]** `tinycc/build-tools.sh` builds it as
`build-out/tinycc/kaem`, 99,008 bytes, pinned as `tinycc/kaem`.

- On Linux through IA32 (`tests/tinycc/kaem-check.sh`): the
  eighteen scripts of `vendor/mescc-tools/Kaem/test.sh` give the output
  of `test/test.answers`; a command that exits 1 stops a script with
  "Subprocess error 1"; a command that is not there is refused by
  `access`, and no `execve` is made for it.
- On builder-hex0 (`tests/tinycc/kaem-boot-check.sh`, two boots):
  kaem under kaem, four processes deep, runs four commands that exit 0,
  stops on a status of 1, and reports the probe's exit of 300 as
  "Subprocess error 44", which is bits 8 to 15 of the unmasked
  `300 << 8`. With `/no-such-program` in its script the machine stays
  up, kaem's child exits, and the shell runs its next command: the first
  point below, observed.

Two things follow on builder-hex0:

- When the guard refuses, kaem's child calls `_exit` (`kaem.c:1101`)
  without having run `execve`. builder-hex0 then never resumes the
  parent; control returns to its shell (P§3). The stream ends there, so
  the boot stops with "Build finished" and no export, which the check
  reports. It does not hang, as a real `execve` of a missing file would.
- `fork` saves kaem's memory up to its break (P§3). The entry stub of
  every compiled program already raises the break over the bss
  (`cc/117-cc-native-program.fth`, `cc-native-entry`), and M2libc's `malloc` takes its memory
  from `brk`, so the whole of kaem is below the break.

**The pins.** The eleven tools are compiled without the second file, so
the eleven `tinycc/bin/` lines of `tests/pins/tinycc.sha256` do not
depend on it. kaem has a pin of its own. The first tcc's pin and
everything after it do not depend on either file: the first tcc is
compiled with Mes's libc.

## 8. What is not required

- Buffered input: one `read` per byte is enough (section 6.2).
- Inline `*` and `/`, or any speed-up that is not in section 4.
- Particular dictionary addresses, sizes or a particular HERE. The
  output does not depend on them **[measured]** (SPEC Appendix C): with
  an extra word in the library and 12,347 extra bytes allotted after
  `cc/030-cc-io.fth`, the first tcc keeps its hash.
- A general `mmap` replacement: three requests, all served by
  `brk-alloc`.
- Freeing memory, closing the top-level file, or reclaiming the include
  stack.
- `fork`, `execve`, `lseek` or any call beyond section 5.1 in Forth.
- The names of the words, apart from those other files call
  (`cc-arena-map`, `cc-workspace-map`, `cc-input-file`, `cc-load-files`,
  `native!`, `code:`, `brk-alloc`, `arg`, `include`).

Not free, although they look like shortcuts:

- `0<` as the failure test for every call (section 5.1);
- the cap and the rise-only rule in `brk-alloc` (section 5.2);
- the line feed at the end of an included file (section 6.2);
- closing each included file and each `#include`d one (section 5.1);
- `lea`, not `add`, in `flag-test,` (section 4.2);
- the guard before `execve` in the shim (section 7.4);
- every seed run before kaem's first `cd` (section 7.3).

## 9. Acceptance

`./check-all.sh` runs these as the steps given. Those that need the seed
build it first (`seed/build.sh` writes `./seed-forth`) or take the
program `SEED_FORTH` names.

| check | script, step | what it proves |
|---|---|---|
| the library's own cases and the first compiler layers' | `./test.sh`, 04 | `forth/test-010-lib.fth` and the `cc/test-NNN-*.fth` files exit 0 as the seed's jobs |
| every byte line carries its instruction as a comment, and GNU as and llvm-mc in 32-bit mode write the same bytes | `tests/forth/asm-check.py`, 05 | section 4's bytes are the instructions they claim |
| vectors for the primitives on cells whose high halves matter; `tests/reference.py` computes 150 of the 153 expected values again in Python (not the three under control flow) | `tests/forth/high-halves-check.sh`, 05 | no primitive of 020 drops a carry, a borrow or a half |
| `forth/test-010-lib.fth` again; `include`, the end of an included file and `brk-alloc`'s refusals | `tests/tinycc/seed-check.sh`, 09, with `tests/forth/host-words-check.sh` | the library's own words, before the compiler is involved |
| `./seed-forth forth/010-lib.fth tinycc/jobs/tcc-first.fth …` gives `build-out/tinycc/tcc-first` (`92d11438…`, 975,624 bytes), and `tool.fth` gives kaem, the stock `ungz` and `untar` and the eleven tools, all as pinned in `tests/pins/tinycc.sha256` | the same script (`tinycc/build-tools.sh`, `tinycc/build-first-tcc.sh`) | fifteen programs whose bytes differ if any primitive, comparison, literal, branch or call differs in a way the compiler's work reaches |
| the same fifteen runs under `strace` | the same script, with `tests/tinycc/seed-syscall-check.py` | only `brk`, `open`, `read`, `write`, `close` and `exit`; the break never lowered and never above the cap; no `read` of descriptor 0; every opened file closed except the Forth files still being read at exit; the output opened last, after which the run only writes and closes it |
| from the first tcc, live-bootstrap's `pass1.kaem` reaches its published `tcc` | `tests/tinycc/syscall-check.sh`, 10 | the pinned first tcc is a working compiler; this is what stands behind its pin |
| kaem runs `vendor/mescc-tools/Kaem/test.sh`'s scripts on Linux, and starts programs and reads their statuses on builder-hex0 | `tests/tinycc/kaem-check.sh`, 12; `tests/tinycc/kaem-boot-check.sh`, 13 | section 7.4 |
| the boot of section 7 | `tests/tinycc/one-boot-check.sh`, 15 | the whole of it on builder-hex0: the built-in `hex0` assembles the seed, the seed builds kaem, the tools and the first tcc, and the boot reaches live-bootstrap's published `tcc`, `libc.a` and the other files. The exported `/seed-forth`, kaem, tools and `/usr/bin/tcc-mes` equal the host's |

Step 11, `tests/tinycc/standin-check.sh`, compares the first tcc with a
gcc `-m32` build of the same C. It is about the target, not the host,
and runs only with `CHECK_STANDIN=1`.

The pins do not move. They were first produced by the x86-64 host of
tag `experiments-2026-11-21` compiling the same sources; this host
reproduced them, and since that host left the branch they are fixed
values with step 10 behind them.

**[measured]** with the seed, `seed/000-seed.hex0` (1,191 bytes,
`b5f70ffb…`): `tests/tinycc/seed-check.sh` passes on Linux, and the one
boot exports 33 files that all compare equal: the two programs the
built-in `hex0` assembled (the seed as hex0-seed assembles it on the
host; kaem-optional-seed as stage0-posix publishes it, `545f8953…`),
kaem, the eleven tools, the stock `ungz` and `untar` and the first tcc
as the seed builds them on Linux, and live-bootstrap's `tcc-boot1`,
`tcc` and libraries. kaem-optional-seed starts the seed with eight
arguments there, and the seed runs four processes deep.

**[measured]** before the seed existed, on a seed written from
`seed/SPEC.md` alone in GNU as for that purpose and not kept, with the
host files as they were then (the compiler's files have been folded
since, and there were 13 runs, not 15):

- the first tcc (`92d11438…`), the eleven tools and kaem had their
  pinned bytes, in 13 runs making 7.4 million calls: 7,406,304 reads, of
  which 7,403,494 were the one-byte reads of Forth text and 2,810 read C
  files. The first-tcc run took 0.8 s.
- HERE at the end of the first-tcc compile was 144,025,149
  (0x0895A63D): 9.00 MiB above the initial HERE, of the image's 31.9
  MiB.
- On builder-hex0, under the kaem of section 7.4, the same host files
  built `catm`, kaem and the first tcc from sources on the disk, and the
  M2libc-built `sha256sum` printed their pinned hashes.

Those runs said that the host files and the two documents agreed with
each other before there was a seed to say it. They have not been
repeated; the checks in the table are what runs now.

What no check above exercises:

- `c@` on an address whose cell has a nonzero high half. The inline form
  clears edx after the load; every address has a zero high half
  (section 2), so no valid operand shows whether it does.
- the first `sbb edx, 0` of `in-range,`. It makes the subtraction a
  64-bit one, as the table in 4.2 says, but the answer is the same
  without it: when the low halves borrow, the low half of the difference
  is at least 2^32 - 97, never below the count, and the second `sbb`
  alone decides the rest. No vector can tell the two apart.
- the guard's refusal inside the one boot. Its scripts name no missing
  program; `tests/tinycc/kaem-boot-check.sh` has the refusal alone.
  kaem-optional-seed has no guard at all: a wrong path in
  `/boot/seed.kaem` stops the machine, and the check's timeout ends it.
- a dictionary that outgrows the 32 MiB image. Nothing checks HERE
  against the image's end; the measurement above left 22.9 MiB.
- `forth/test-010-lib.fth` ends by exiting with its verdict, so a run
  that stops early at a broken primitive, which the interpreter takes
  for the end of input, also exits 0. The vectors print a last line for
  this reason; that file does not.

## 10. Decisions

- **The three process calls** are in a file listed only for kaem,
  `tinycc/m2libc-kaem.c`, so the eleven tools are compiled without them.
- **The drivers name no file.** The paths of a compile come from the
  command line, through the two jobs of section 6.5, so the host and the
  boot run the same drivers with different paths.
- **`native!` is in the library.** Section 6.2 needs it before
  `forth/020-cc-arena.fth` loads. It is the only place where the
  library, not 020, patches a seed word.
- **The image size.** 32 MiB is one field of the seed and one constant
  of its checker. The measured need was 9.00 MiB (section 9).
- **The book** is a separate project and not part of this contract.
