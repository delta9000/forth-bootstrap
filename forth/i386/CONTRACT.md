# The i386 host contract: Forth-laid machine code on the i386 seed

`seed/i386/SPEC.md` specifies the i386 seed. This document specifies
everything between that seed and the C compiler's output: the machine
code that the Forth library and the compiler lay down *for the Forth
system itself to execute*, the system calls they make, how they get
memory and input, which files carry the i386 versions, and the boot that
runs it all on builder-hex0.

It was written before any of those files. The seed, the host files,
kaem, the boot and the checks all exist now. Where they differ from what
was first written here, the text has been changed to say what they do.

It lives in `forth/i386/` because `forth/` is the host side of the
repository and the i386 host files go beside it (section 3).

Conventions are `seed/i386/SPEC.md`'s: MUST and FREE, 8-byte cells,
`file:line` citations, `B2:<line>` for builder-hex0's stage 2, `P§n` for
`tests/builder-hex0/README.md`,
**[measured]** and **[designed]**. "SPEC n" is a section of
`seed/i386/SPEC.md`.

## 1. Two axes: the host and the target

"i386" names two different things in this repository.

- **The target**: what the C compiler emits. `cc/i386/` is the i386
  target back end (ILP32, ELF32, `int 0x80`), finished and pinned. Its
  bytes go to the output file through `cc-emit-byte` and `x{ }` and are
  executed by the compiled C program.
- **The host**: the processor the Forth system itself runs on. Until now
  it has been x86-64 only. Host code goes into the dictionary through
  `c,` and `c{ }` and is executed during the compile.

The two are independent, and three of the four combinations matter:

| host | target | use |
|---|---|---|
| x86-64 | x86-64 | every existing route |
| x86-64 | i386 | `tinycc/build-first-tcc-i386.sh`, `tinycc/build-tools-i386.sh`: today's way to the i386 first tcc and tools, and from now on the reference |
| i386 | i386 | this document: the same compile in the boot |

This document is about the host axis only. `cc/i386/` and
`cc/i386/layers.sh` keep their meaning and their bytes. The x86-64 host
MUST keep building the i386 target, because that build is the oracle
(section 9).

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
  semantics (SPEC 7.1). The x86-64 file inlines them
  (`cc/020-cc-arena.fth:196-207`); the i386 file does not.
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

## 3. Which files carry the i386 host

Two files hold nearly all the host machine code, and both are quoted
byte for byte by the book and loaded by every x86-64 route:
`forth/010-lib.fth` and `cc/020-cc-arena.fth`. They stay as they are.
The i386 host gets **stand-ins** for those two and **shadows** for the
few host-specific words elsewhere. `cc/i386/layers.sh` set both
patterns: its 080 and 119 are stand-ins ("not loaded; 080-elf32.fth and
119-runtime.fth stand in their place"), and its 065, 090, 100 and 117
are shadows, loaded after the file whose words they redefine.

A shadow by redefinition only reaches words compiled later. Where
earlier code already calls the word, the shadow MUST redirect the old
word with `native!`, or go through a `defer`. Each row says which.

| new file | role | replaces or follows |
|---|---|---|
| `forth/i386/010-lib.fth` | stand-in | `forth/010-lib.fth` |
| `forth/i386/020-cc-arena.fth` | stand-in | `cc/020-cc-arena.fth` |
| `forth/i386/030-io.fth` | shadow, after `cc/030-cc-io.fth` | `cc-workspace-syscall` through its `defer` (`cc/030-cc-io.fth:276-277`); `cc-load-stdin` by redefinition, which is enough because only the drivers call it (`tinycc/tcc-compile-i386.fth:40`, `tinycc/tool-compile.fth:38`) |
| `forth/i386/115-nzero.fth` | shadow, after `cc/115-cc-native.fth` | `cc-nzero` through `native!`: 115 itself calls it at `:52` and `:225` |
| `forth/i386/layers.fth` | the load list | `cc/i386/layers.sh` |

`forth/i386/layers.fth` is a file of `include` lines: the files
`cc/i386/layers.sh` prints, in its order, without the library (the seed
has read it already, section 6), with `forth/i386/020-cc-arena.fth` for
`cc/020-cc-arena.fth`, and with the two shadows after 030 and 115:

    forth/i386/020-cc-arena.fth
    cc/030-cc-io.fth          forth/i386/030-io.fth
    cc/040-cc-prep.fth        cc/050-cc-lex.fth       cc/060-cc-types.fth
    cc/i386/065-ilp32-types.fth                       cc/070-cc-sym.fth
    cc/i386/080-elf32.fth     cc/090-cc-emit.fth      cc/i386/090-emit.fth
    cc/100-cc-expr.fth        cc/i386/100-divide.fth
    cc/110-cc-decl.fth        cc/112-cc-stmt.fth      cc/114-cc-func.fth
    cc/115-cc-native.fth      forth/i386/115-nzero.fth
    cc/116-cc-prog.fth        cc/117-cc-native-program.fth
    cc/i386/117-entry.fth     cc/118-cc-native-init.fth
    cc/i386/119-runtime.fth

Everything from `cc/030-cc-io.fth` on is the same file for both hosts.
The drivers (`tinycc/tcc-compile-i386.fth`, `tinycc/tool-compile.fth`)
are the same files too.

### 3.1 Keeping the stand-ins honest

A stand-in is a copy with a known set of lines changed. Three checks,
all in `tests/forth/i386/standin-check.sh`, keep the copies from
drifting:

- **The difference is pinned.** `diff forth/010-lib.fth
  forth/i386/010-lib.fth` and `diff cc/020-cc-arena.fth
  forth/i386/020-cc-arena.fth` MUST equal two committed files,
  `tests/forth/i386/010-lib.diff` and `020-cc-arena.diff`. A change to
  either side then fails until someone has looked at the other.
- **Vocabulary parity.** Every name the x86-64 file defines and a later
  layer or driver uses MUST be defined by the stand-in, with the same
  stack effect. `key-drain` is the case to watch: nothing on this route
  calls it at run time, but `cc/030-cc-io.fth:72` compiles a reference to
  it (section 6.4). The check compares names; the stack effects are read
  from the pinned difference. Eighteen names of the x86-64 pair are not
  in the stand-ins (the register helpers, the buffered `key`, `seed-star`
  and `seed-slash`), and no later file uses one.
- **The load list.** `forth/i386/layers.fth`, with its `include` words
  removed and the substitutions above undone, MUST equal the output of
  `cc/i386/layers.sh` without its first line.

## 4. Every host machine-code site

The complete list of bytes that the Forth host executes and that some
Forth file lays down above the seed. "Port" says what the i386 host file
holds. The i386 encodings were assembled with GNU as 2.47 and llvm-mc
23.1.5, which agree on all of them **[measured]**;
`tests/forth/i386/asm-check.py` repeats that on the files' 94 byte
lines. They ran first on a stand-in seed written from
`seed/i386/SPEC.md` for that purpose and not kept, and then on the seed
(section 9).

The stand-in for 020 lays these bytes, but arranges them differently
from the table in 4.2, which follows the x86-64 file line by line: each
sequence used more than once is a word of its own (`pop-sub,` is the
table's diff, `0=,` its zero-flag, and `pop-xor,`, `sign-ebx,`,
`sign-edx,`, `not,`, `-,`, `1+,`, `1-,`, `over,`, `drop-2,`), and the
code word and the inline form of a primitive both call it. On this host
a sequence is two to five instructions and would otherwise be written
out up to five times.

Building blocks used below:

| name | bytes | instruction |
|---|---|---|
| push-tos | `83 EE 08` `89 06` `89 56 04` | `sub esi, 8`; `mov [esi], eax`; `mov [esi+4], edx` |
| pop-tos | `8B 06` `8B 56 04` `83 C6 08` | `mov eax, [esi]`; `mov edx, [esi+4]`; `add esi, 8` |
| diff | `8B 0E` `8B 5E 04` `29 C1` `19 D3` `83 C6 08` | ebx:ecx = second - TOS, second dropped: `mov ecx, [esi]`; `mov ebx, [esi+4]`; `sub ecx, eax`; `sbb ebx, edx`; `add esi, 8` |
| zero-flag | `09 D0` `83 F8 01` `19 C0` `89 C2` | all ones if edx:eax = 0: `or eax, edx`; `cmp eax, 1`; `sbb eax, eax`; `mov edx, eax` |

### 4.1 `forth/010-lib.fth` (14 lines with machine content)

| lines | what | x86-64 | port |
|---|---|---|---|
| 71-77 | the comment on `syscall6` and the call numbers | rdi…r9, numbers 0, 1, 2, 3, 60 | ebx…ebp, numbers 3, 4, 5, 6, 1 |
| 80 | `write` | `0 0 0 1 syscall6` | `0 0 0 4 syscall6` |
| 84 | `die` | `0 0 0 0 0 60 syscall6` | `0 0 0 0 0 1 syscall6` |
| 527 | `open` | number 2 | number 5 |
| 530 | `read` | number 0 | number 3 |
| 534 | `close` | number 3 | number 6 |
| 200 | `ret,` | `C3` | `C2 04 00` |
| 203-207 | `push-imm64,`: 18 bytes that push a literal | `48 83 ED 08` `48 89 7D 00` `48 BF imm64` | push-tos, then `B8 imm32` (`mov eax,` the low half) and `BA imm32` (`mov edx,` the high half): also 18 bytes |
| 210 | `push-body,`: the push and a return | 19 bytes | 21 bytes |
| 225-227 | `call,` | `E8 rel32`, rel32 from the address after 5 bytes | `6A 00 E8 rel32`, rel32 from the address after 7 bytes |
| 349 | `exit,` | `ret,` | `ret,` (no change in the text) |
| 364 | `create`: the data area's address | `here 19 +` | `here 21 +` |
| 385 | `defer-code-size` | 29 = 18 + 5 + 5 + 1 | 35 = 18 + 7 + 7 + 3 |
| 580 | `skip-vm-pages` | `state 4096 + here-addr !` | an empty definition: HERE starts there (SPEC 3.1), and moving it back would land on the library |

Lines whose text stays although they depend on the machine, with the
reason it holds on i386:

- `:23-34` (`latest`, `here-addr`, `,`): the sysvars are 8-byte cells at
  the same offsets (SPEC 3.3).
- `:40` (`execute`), `:45` (`r@`), `:269` (`branch`), `:277-283`
  (`0branch`): return addresses are cells (SPEC 5.2 traces all four).
- `:293-342` (the control-flow words): the cell after a branch call is
  laid by `,` and read by `@`, 8 bytes in both.
- `:182` (`immediate`), `:495` (`found-immediate?`): the header layout is
  the same (SPEC 6.1).
- `:160-171` (`,4`, `,8`): `256 /` on a 64-bit cell.
- `:421-422` (`compile-literal`), `:638` (`hex-lay`): built on
  `push-imm64,` and `call,`.

Added to the stand-in, with no counterpart in `forth/010-lib.fth`: the
input words of section 6 and `brk` and `brk-alloc` of section 5.

### 4.2 `cc/020-cc-arena.fth` (74 lines with `c{ }`, 2 with `mmap`)

| lines | what | x86-64 | port |
|---|---|---|---|
| 22 | `code:` | header only | the same text |
| 23-26 | `native!`: a jump over a word's first 5 bytes | `E9 rel32` | the same bytes. Every word it is applied to is at least 10 bytes long on i386 (a call and a return) |
| 28-32 | the helpers `mov-rax-[rbp],` … `sar63,` | | replaced by the building blocks above |
| 33-35 | `-` | rax = [rbp] - rdi | diff, `89 C8` `89 DA` (`mov eax, ecx`; `mov edx, ebx`) |
| 36-38 | `0<` | `sar rdi, 63` | `C1 FA 1F` `89 D0` (`sar edx, 31`; `mov eax, edx`) |
| 39-41 | `<` | sign of a - b | diff, `C1 FB 1F` `89 D8` `89 DA` (`sar ebx, 31`; `mov eax, ebx`; `mov edx, ebx`) |
| 42-48 | `=` | `sete`, `movzx`, `neg` | `33 06` `33 56 04` `83 C6 08` (`xor eax, [esi]`; `xor edx, [esi+4]`; `add esi, 8`), zero-flag |
| 49-51 | `1+` | `add rdi, 1` | `83 C0 01` `83 D2 00` (`add eax, 1`; `adc edx, 0`) |
| 52-54 | `1-` | `sub rdi, 1` | `83 E8 01` `83 DA 00` (`sub eax, 1`; `sbb edx, 0`) |
| 62-87 | `key-fill`: a buffered `key` on descriptor 0, with a raw `syscall` | 18 machine lines | **dropped.** Input is section 6's, in Forth |
| 88-99 | `key-drain` | hands the buffer's rest to `cc-read-all` | `( buf cap -- 0 )`: drops both and answers 0 |
| 113-115 | `rel32!` | | the same text |
| 116-119 | `flag-test,`: pop the flag and test it | `mov rax, rdi`; pop; `test rax, rax` | `09 D0` `8B 06` `8B 56 04` `8D 76 08` (`or eax, edx`; `mov eax, [esi]`; `mov edx, [esi+4]`; `lea esi, [esi+8]`). The `lea` replaces pop-tos's `add` so that the zero flag from `or` reaches the jump |
| 120-123 | `jz-fwd,` `jmp-fwd,` `jz-back,` `jmp-back,` | `0F 84 rel32`, `E9 rel32` | the same bytes |
| 124-131 | `if,` … `again,` | | the same text |
| 134-136 | `push-tos,` `pop-tos,` | | the building blocks |
| 140-141 | `dup`, `drop` | | push-tos; pop-tos |
| 142-145 | `swap` | `xchg rdi, [rbp]` | `87 06` `87 56 04` (`xchg eax, [esi]`; `xchg edx, [esi+4]`) |
| 146-149 | `over` | | push-tos, `8B 46 08` `8B 56 0C` (`mov eax, [esi+8]`; `mov edx, [esi+12]`) |
| 150-152 | `@` | `mov rdi, [rdi]` | `8B 50 04` `8B 00` (`mov edx, [eax+4]`; `mov eax, [eax]`): the high half first, because the second load overwrites the address |
| 153-155 | `c@` | `movzx rdi, byte [rdi]` | `0F B6 00` `31 D2` (`movzx eax, byte [eax]`; `xor edx, edx`) |
| 156-160 | `!` | | `8B 0E` `89 08` `8B 4E 04` `89 48 04` (`mov ecx, [esi]`; `mov [eax], ecx`; `mov ecx, [esi+4]`; `mov [eax+4], ecx`), then `8B 46 08` `8B 56 0C` `83 C6 10` (the third item becomes TOS; `add esi, 16`) |
| 161-165 | `c!` | | `8B 0E` `88 08` (`mov ecx, [esi]`; `mov [eax], cl`), then the same three as `!` |
| 166-169 | `+` | `add rdi, [rbp]` | `03 06` `13 56 04` `83 C6 08` (`add eax, [esi]`; `adc edx, [esi+4]`; `add esi, 8`) |
| 170-173 | `-` inline | | as lines 33-35 |
| 174-179 | `1+`, `1-` inline | | as lines 49-54 |
| 183 | `jmp-xt,` | `E9 rel32` | the same bytes |
| 190 | `>r` inline | `push rdi`; pop-tos | `52` `50` (`push edx`; `push eax`), pop-tos |
| 191 | `r>` inline | push-tos; `pop rdi` | push-tos, `58` `5A` (`pop eax`; `pop edx`) |
| 192-193 | `r@` inline | `mov rdi, [rsp]` | push-tos, `8B 04 24` `8B 54 24 04` (`mov eax, [esp]`; `mov edx, [esp+4]`) |
| 196-207 | `*` and `/` inline | `imul`, `div` | **not ported**: both stay calls to the seed (section 2). The two definitions are left out |
| 208-213 | `0=` | `test`, `sete`, `movzx`, `neg` | zero-flag |
| 214-224 | `and`, `or`, `nand` | | `23 06` `23 56 04` `83 C6 08`; `0B 06` `0B 56 04` `83 C6 08`; for `nand` the `and` bytes and `F7 D0` `F7 D2` (`not eax`; `not edx`) |
| 227-233 | `in-range,` for `digit?`, `alpha-lower?`, `alpha-upper?` | `sub`, `cmp`, `sbb` | `83 E8 low` `83 DA 00` `83 F8 count` `83 DA 00` `19 C0` `89 C2`: `sub eax, low`; `sbb edx, 0`; `cmp eax, count`; `sbb edx, 0`; `sbb eax, eax`; `mov edx, eax`. The second `sbb` leaves carry set exactly when the 64-bit difference is below count |
| 236-240 | `over` as a code word | | as lines 146-149, and a return |
| 241-266 | library words compiled again and redirected | Forth text | the same text |
| 269-271 | `pop-sub,`, `flag-al,` | | diff; zero-flag |
| 272-274 | `=` inline | | as lines 42-48 |
| 275-277 | `<>` inline | `setne` | the three `xor`/`add` bytes of `=`, then `09 D0` `F7 D8` `19 C0` `89 C2` (`or eax, edx`; `neg eax`; `sbb eax, eax`; `mov edx, eax`) |
| 278-280 | `<` inline | | as lines 39-41 |
| 281-284 | `>=` inline | | `<`, then `F7 D0` `F7 D2` |
| 285-289 | `>` inline | sign of b - a | `2B 06` `1B 56 04` `83 C6 08` `C1 FA 1F` `89 D0` (`sub eax, [esi]`; `sbb edx, [esi+4]`; `add esi, 8`; `sar edx, 31`; `mov eax, edx`) |
| 290-293 | `<=` inline | | `>`, then `F7 D0` `F7 D2` |
| 294-295 | `0<` inline | | as lines 36-38 |
| 300-304 | `constant`, `create`: the push, a call to `push-or-compile`, a return | 24 bytes; `here 24 +` | 28 bytes = 18 + 7 + 3; `here 28 +` |
| 318 | the hash table's 2 MiB | `mmap` (call 9) | `2097152 brk-alloc` (section 5) |
| 425-429 | `cc-arena-map` | `mmap`; dies 10 if the result is negative | `brk-alloc`; dies 10 if the result is 0 |

Comparisons keep the x86-64 file's meaning exactly: `<` is the sign bit
of the wrapped 64-bit difference, and so on
(`forth/010-lib.fth:133-141`).

Lines whose text stays: `:320-350` (the hash walk: 8-byte links and
nodes, header offsets 9 and 10, LAST_FOUND through `latest 16 +`), `:351`
(`' find ' fh-find native!`), and everything from `:353` on except
`cc-arena-map`.

### 4.3 The other files

| site | what | port |
|---|---|---|
| `cc/030-cc-io.fth:26` | `skip-vm-pages` | no change: the i386 library's is empty |
| `cc/030-cc-io.fth:71-74` | the descriptor-0 branch of `cc-read-all` calls `key-drain` | no change; never taken, because nothing reads descriptor 0 |
| `cc/030-cc-io.fth:86-88` | `cc-load-stdin` reads descriptor 0 to its end | shadowed in `forth/i386/030-io.fth` (section 6.4): descriptor 0 has no end on builder-hex0 |
| `cc/030-cc-io.fth:274-275` | `cc-workspace-syscall`: `mmap` (call 9) | `forth/i386/030-io.fth` sets the `defer` to `brk-alloc`. Its callers are `cc/030-cc-io.fth:287`, `cc/040-cc-prep.fth:155,686,689`, `cc/090-cc-emit.fth:981` and `cc/112-cc-stmt.fth:672`; `cc-workspace-map` dies when the answer is 0 or less (`:280`) |
| `cc/030-cc-io.fth:183-195` | the flags and mode for `open`: 577, 493 | no change: `O_WRONLY`, `O_CREAT`, `O_TRUNC` have the same values on i386 |
| `cc/115-cc-native.fth:45-50` | `cc-nzero`, 5 lines of x86-64 bytes (`rep stosb`) | `forth/i386/115-nzero.fth`: the same word in Forth (a loop of `c!`), and the old word redirected to it with `native!`. Its callers zero 24 to 2,600 bytes at a time, so machine code buys nothing |
| `tinycc/tcc-compile-i386.fth`, `tinycc/tool-compile.fth` | no machine code. They call `cc-arena-map` (`:23`, `:18`), `cc-load-stdin` (`:40`, `:38`) and `open`, `write`, `close` with 577 and 384 or 493 | no change: both words are replaced underneath them |
| `tinycc/tools/catm.fth`, the three lines `tinycc/build-tools-i386.sh:51-52` prints for each tool, and `tinycc/tcc-names-i386.fth` | the output and source names as Forth text | not used: the names come from the command line (section 6.5) |

Not on this route, so not ported:

- `kernel/tools/amd64-syscalls.fth:9-16`: 7 lines that emit a `syscall3`
  shim. They go to the compiler's output through `cc-emit-byte`, for the
  recipe runner: target code, x86-64, K1 route.
- `tinycc/catm-start.fth` (111 lines; machine bytes at `:32-35`, `:37`,
  `:48`, the 19 at `:49`, call numbers at `:57-61`): it joins the Forth
  input for the first catm on the host. The i386 seed reads files by
  name, so nothing is joined and no catm is needed for input.
- `cc/driver/seed-cc-start.fth`, `kernel/tools/k1-direct-start.fth`,
  `kernel/k1/boot/k0-syscalls.fth`, `forth/130-asm.fth`,
  `cc/081-cc-object.fth`, `cc/120` and above: x86-64 routes only; none is
  in `cc/i386/layers.sh`.

A search of every `.fth` file in the repository for `c{`, `code:`,
`native!`, runs of `N c,` and `syscall6` found host code in the files
above and nowhere else **[measured]**.

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

No other call is made by Forth on this route: no `mmap` (builder-hex0
answers 0, which `cc/020-cc-arena.fth:428` would take for an address,
P§1), no `lseek`, no `fork`, no `execve`. All six are implemented by
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
  compile makes 960 `open` calls **[measured]**.

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
  them; the break has no bound of its own (P§2). The need is 19 MiB
  **[measured]**: the x86-64 host compiling the i386 first tcc makes
  three `mmap` calls, of 2,097,152 bytes for the hash table, 8,388,608
  for the arena and 9,437,184 for the preprocessor's workspaces.
- On Linux the break of a 32-bit program is below 2^31, so the
  sign-extended result of `brk` is the address.

## 6. Input

**[designed]** The seed reads one file, the one named by its first
argument, and exposes two cells: INPUT, the descriptor `key` reads, and
ARGV, where the kernel left the argument pointers (SPEC 3.3). The
library builds the rest. The command line of every run is

    seed-forth-i386 forth/i386/010-lib.fth JOB [ARG ...]

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

`key` is redirected, with `native!`, to a word written in Forth:

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

The redirection is done once, in the stand-in library, as soon as the
words it needs exist (after the outer interpreter has taken over, where
control flow is available). The library therefore defines `native!`
itself; the 020 stand-in does not define it again.

Reading is one `read` per byte. A first-tcc run reads 554 KB of Forth:
about 35 ms on builder-hex0 at 242 cycles a call (P§7) and a few tenths
of a second on Linux. No buffer is kept, so `key-drain` has nothing to
hand over (section 4.2).

### 6.3 The library's last line

After its last definition the stand-in library runs `2 arg`, and if that
is not 0, `included`. So JOB is read next, and when JOB ends the library
file ends, which is the end of input.

### 6.4 C source by name

`forth/i386/030-io.fth` adds:

- `cc-input-file` ( zaddr -- ): append a path to a list of at most 8; a
  ninth dies with 20;
- a new `cc-load-stdin` ( -- ): `cc-src-init`, then for each listed path
  in order, open it (die 20 if that fails), read it to its end with
  `cc-read-all` into `cc-in-buf` directly after the bytes already there
  (die 20 when the buffer fills, as before), and close it; `cc-in-len`
  is the total.

The compiler then sees exactly the bytes the x86-64 host reads from
standard input after the Forth text: the listed files one after another
with nothing between them, which is what `catm` joins for it today
(`tinycc/build-first-tcc-i386.sh:75-76`, `tinycc/build-tools-i386.sh:53-54`).
Quoted `#include` lines resolve as before, beside the path given to
`cc-prep-source-name`.

### 6.5 The two jobs

Two small files, each read as JOB.

`tinycc/i386-seed/tcc-first.fth`, run as
`… tcc-first.fth OUT SOURCE INCLUDE INCLUDE-LINUX`:
`include forth/i386/layers.fth`; define `tcc-output` as argument 3; give
SOURCE to `cc-prep-source-name` and the two include paths to
`cc-prep-add-include`, each with its length; list SOURCE as the one
input file; `include tinycc/tcc-compile-i386.fth`. The driver names no
file: on the x86-64 host the same four paths come from
`tinycc/tcc-names-i386.fth`, which is read ahead of it, as the three
printed lines are read ahead of `tinycc/tool-compile.fth`. So both hosts
run one driver, and the boot's paths can differ from the host's (section
7.3). On the host the arguments are the names file's paths.

`tinycc/i386-seed/tool.fth`, run as `… tool.fth OUT SOURCE [SOURCE ...]`:
`include forth/i386/layers.fth`; define `tool-output` as argument 3 with
its NUL and `tool-source` as the last argument, and give that one's
length to `cc-prep-source-name`, as the printed lines do today; list
`tinycc/m2libc-native-i386.c` and then each SOURCE as input files;
`include tinycc/tool-compile.fth`. Several SOURCE arguments are for
kaem: `tinycc/m2libc-kaem-i386.c` (section 7.4) and its three files,
which M2-Mesoplanet also compiles as one unit
(`vendor/stage0-posix/x86/mescc-tools-mini-kaem.kaem:262-274`).

The compiler's output does not depend on these strings **[measured]**
(SPEC Appendix C): the first tcc has the same bytes with its sources in
another directory, and a tool has the same bytes when its source is
named by an absolute path of 142 bytes.

## 7. The boot

`tinycc/i386-one-boot-disk.py` writes this disk and
`tests/tinycc/i386-one-boot-check.sh` boots it and compares what it
exports. **[measured]** The boot takes 25 s with KVM and reaches every
pinned and published hash (section 9). Before the seed existed the same
two files put a host-built first tcc, tools and kaem on the disk; that
form is gone, because this one runs the same live-bootstrap text from
the same tcc-mes bytes and needs nothing built on the host.

### 7.1 The disk

As now: builder-hex0's stage 1, its stage-2 hex0 source, zeros to sector
175, then the stream. The stream is what builder-hex0's shell reads
(B2:2621-2653): `src N PATH` lines with N bytes of file, and commands.

- `src 0 DIR` for every directory, each level before the ones below it:
  `open` with `O_CREAT` fails when the parent has no entry (P§5).
- Files, at their repository paths under `/`, so that the relative names
  in the Forth and C files resolve from the working directory `/`
  (relative `open` with the working directory `/` works, P§5):
  - `seed/i386/000-seed.hex0` and
    `vendor/stage0-posix/x86/kaem-minimal.hex0`;
  - `forth/i386/`, the shared `cc/*.fth` and `cc/i386/*.fth` of the load
    list, the two drivers and the two jobs;
  - the C the seed compiles: `vendor/stage0-posix/M2libc/`,
    `vendor/stage0-posix/mescc-tools-extra/`, `vendor/mescc-tools/Kaem/`
    and `vendor/mescc-tools/M2libc/bootstrappable.*`,
    `tinycc/m2libc-native-i386.c`, `tinycc/m2libc-kaem-i386.c`,
    `tinycc/direct-input-i386.c`,
    `tinycc/mes-libc.c`, `tinycc/mes-libc-native-i386.c`, the four files
    of `tinycc/tools/` that patch `ungz.c` and `untar.c`,
    `tinycc/hex0-export.c`;
  - the three archives of `tinycc/SOURCES` and their checksum file;
  - the two scripts below.
- Then three commands:

      hex0 /seed/i386/000-seed.hex0 /seed-forth-i386
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

    /seed-forth-i386 /forth/i386/010-lib.fth /tinycc/i386-seed/tool.fth /x86/bin/kaem /tinycc/m2libc-kaem-i386.c /vendor/mescc-tools/Kaem/variable.c /vendor/mescc-tools/Kaem/kaem_globals.c /vendor/mescc-tools/Kaem/kaem.c
    /x86/bin/kaem --verbose --strict --file /kaem.run

Each argument is under 255 bytes (P§4).

### 7.3 `/kaem.run`, run by the full kaem

**The working directory decides the order.** On builder-hex0 the root
has no entry: `chdir("/")` and `chdir("..")` fail, so a process that
leaves `/` cannot return (P§5). A program inherits the directory of the
one that starts it (read: `execve` copies it, B2:1698-1707). Every
relative path in the Forth files, from `include forth/i386/layers.fth`
on, is relative to `/`. So every seed run MUST come before kaem's first
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
   `tinycc/build-first-tcc-i386.sh:44,56` changes directory for it, which
   the boot cannot. So tcc's and Mes's archives are unpacked to
   `/tcc-0.9.26-1147-gee75a10c` and `/mes-0.28`, and `direct-input.c`,
   `mes-libc.c` and `mes-libc-native.c` are written beside them, because
   their quoted includes are relative to their own directory
   (`tinycc/direct-input-i386.c:29-30`). The other commands are those of
   `tinycc/build-first-tcc-i386.sh:46-68` with `/` for the source
   directory.
4. One seed run of `tcc-first.fth`, with `/usr/bin/tcc-mes`,
   `direct-input.c`, `mes-0.28/include` and `mes-0.28/include/linux/x86`
   as its arguments, writes the first tcc.
5. live-bootstrap's text as now, with its `cd` lines: of
   `steps/mes-0.28/pass1.kaem` the unpacking and the header install, and
   `steps/tcc-0.9.26/pass1.kaem` from "# Vars" to "# Checksums" without
   the MesCC commands. It unpacks both archives again, at its own paths.
6. `hex0-export /dev/hda` with the 33 files the host compares, now
   including `/seed-forth-i386`, `/kaem-optional-seed`, `/x86/bin/kaem`,
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
`tinycc/m2libc-native-i386.c` in place of M2libc's assembly. That file
lacks three calls kaem makes (`vendor/mescc-tools/Kaem/kaem.c:1070,
1097, 1106`), which M2libc defines in assembly
(`vendor/stage0-posix/M2libc/x86/linux/unistd.c:55-85`). They are in a
second file, `tinycc/m2libc-kaem-i386.c`, which goes between
`tinycc/m2libc-native-i386.c` and kaem's three files and is listed for
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

**[measured]** `tinycc/build-tools-i386.sh` builds it with the x86-64
seed as `build-out/tinycc/kaem-i386`, 99,008 bytes, pinned as
`tinycc/kaem-i386`.

- On Linux through IA32 (`tests/tinycc/i386-kaem-check.sh`): the
  eighteen scripts of `vendor/mescc-tools/Kaem/test.sh` give the output
  of `test/test.answers`; a command that exits 1 stops a script with
  "Subprocess error 1"; a command that is not there is refused by
  `access`, and no `execve` is made for it.
- On builder-hex0 (`tests/tinycc/i386-kaem-boot-check.sh`, two boots):
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
  (`cc/i386/117-entry.fth:7-13`), and M2libc's `malloc` takes its memory
  from `brk`, so the whole of kaem is below the break.

**No pin moves.** The eleven tools are compiled without the second file,
so their bytes and the eleven `tinycc/bin-i386/` lines of
`tests/pins/tinycc.sha256` stay. kaem has a pin of its own; it is not
the Mes-libc kaem of `tinycc/hex0-handoff/boot1/usr/bin/kaem`. The first
tcc's pin and everything after it stay too: the first tcc is compiled
with Mes's libc.

## 8. What is not required

- Buffered input: one `read` per byte is enough (section 6.2).
- Inline `*` and `/`, or any other speed-up the x86-64 file has that is
  not in section 4.
- The same dictionary addresses, sizes or HERE as the x86-64 host. The
  output does not depend on them **[measured]** (SPEC Appendix C): with
  an extra word in the library and 12,347 extra bytes allotted after
  `cc/030-cc-io.fth`, the first tcc keeps its hash.
- A general `mmap` replacement: three callers, all served by
  `brk-alloc`.
- Freeing memory, closing the top-level file, or reclaiming the include
  stack.
- `fork`, `execve`, `lseek` or any call beyond section 5.1 in Forth.
- The names proposed here for new files and words, apart from the words
  later layers already call (`cc-load-stdin`, `cc-arena-map`,
  `key-drain`, `cc-nzero`, `skip-vm-pages`, `native!`, `code:`).

Not free, although they look like shortcuts:

- `0<` as the failure test for every call (section 5.1);
- the cap and the rise-only rule in `brk-alloc` (section 5.2);
- the line feed at the end of an included file (section 6.2);
- closing each included file and each `#include`d one (section 5.1);
- `lea`, not `add`, in `flag-test,` (section 4.2);
- the `native!` redirection of `cc-nzero`: redefining it leaves 115's
  own two calls on x86-64 bytes (section 3);
- the guard before `execve` in the shim (section 7.4);
- every seed run before kaem's first `cd` (section 7.3).

## 9. Acceptance

The host-side checks run under `CHECK_I386=1 ./check-all.sh`. Those
that need the seed build it first (`seed/i386/build.sh` writes
`./seed-forth-i386`).

| check | script | what it proves |
|---|---|---|
| the three checks of section 3.1 | `tests/forth/i386/standin-check.sh` | the stand-ins differ from the x86-64 files only where pinned, define what later layers use, and the load list is `cc/i386/layers.sh`'s |
| every byte line carries its instruction as a comment, and GNU as and llvm-mc in 32-bit mode write the same bytes | `tests/forth/i386/asm-check.py` | section 4's bytes are the instructions they claim |
| vectors for the primitives on cells whose high halves matter; the same text on the x86-64 seed gives the expected values | `tests/forth/i386/high-halves-check.sh` | no primitive of 020 drops a carry, a borrow or a half; needs the seed for its i386 run |
| `./seed-forth-i386 forth/i386/010-lib.fth tinycc/i386-seed/tcc-first.fth` gives a file equal to the `build-out/tinycc/tcc-first-i386` that the x86-64 seed built (`92d11438…`), and `tool.fth` gives eleven tools equal to `build-out/tinycc/bin-i386/` and a kaem equal to `build-out/tinycc/kaem-i386` | `tests/tinycc/i386-seed-check.sh`; needs the seed | the i386 host compiles as the x86-64 host does: 975,624 bytes and twelve programs that differ if any primitive, comparison, literal, branch or call differs in a way the compiler's work reaches |
| the same thirteen runs under `strace` | the same script, with `tests/tinycc/i386-seed-syscall-check.py` | only `brk`, `open`, `read`, `write`, `close` and `exit`; the break never lowered and never above the cap; no `read` of descriptor 0; every opened file closed except the Forth files still being read at exit; the output opened last, after which the run only writes and closes it |
| `forth/test-010-lib.fth`'s cases through the i386 library; `include`, the end of an included file and `brk-alloc`'s refusals | the same script, with `tests/forth/i386/host-words-check.sh` | the library's own words on this host, before the compiler is involved |
| kaem runs `vendor/mescc-tools/Kaem/test.sh`'s scripts on Linux, and starts programs and reads their statuses on builder-hex0 | `tests/tinycc/i386-kaem-check.sh`, `tests/tinycc/i386-kaem-boot-check.sh` | section 7.4 |
| the boot of section 7 | `tests/tinycc/i386-one-boot-check.sh`, under `CHECK_I386_BOOT=1` | the whole of it on builder-hex0: the built-in `hex0` assembles the seed, the seed builds kaem, the tools and the first tcc, and the boot reaches live-bootstrap's published `tcc`, `libc.a` and the other files as it does today. The exported `/seed-forth-i386`, kaem, tools and `/usr/bin/tcc-mes` equal the host's |

"Both seeds build the same bytes" is the oracle, against pins that do
not move.

**[measured]** with the seed, `seed/i386/000-seed.hex0` (1,191 bytes,
`b5f70ffb…`): `tests/tinycc/i386-seed-check.sh` passes on Linux, and the
one boot exports 33 files that all compare equal: the two programs the
built-in `hex0` assembled (the seed as hex0-seed assembles it on the
host; kaem-optional-seed as stage0-posix publishes it, `545f8953…`),
kaem, the eleven tools, the stock `ungz` and `untar` and the first tcc
as the x86-64 seed builds them on
Linux, and live-bootstrap's `tcc-boot1`, `tcc` and libraries.
kaem-optional-seed starts the seed with eight arguments there, and the
seed runs four processes deep.

**[measured]** on a stand-in seed, before the seed existed. To run the
host files then, a seed was written from `seed/i386/SPEC.md` alone in
GNU as, kept out of the repository, and used as `SEED_I386`. On it:

- `tests/tinycc/i386-seed-check.sh` passes: the first tcc (`92d11438…`),
  the eleven tools and kaem have the x86-64 seed's bytes, in 13 runs
  making 7.4 million calls: 7,406,304 reads, of which 7,403,494 are the
  one-byte reads of Forth text and 2,810 read C files. The first-tcc run
  takes 0.8 s.
- HERE at the end of the first-tcc compile is 144,025,149 (0x0895A63D):
  9.00 MiB above the initial HERE, of the image's 31.9 MiB. The x86-64
  host ends 9.01 MiB above its load address.
- On builder-hex0, under the kaem of section 7.4, the same host files
  built `catm`, kaem and the first tcc from sources on the disk, at the
  boot's paths (`/src/direct-input.c` for the first tcc), and the
  M2libc-built `sha256sum` printed their pinned hashes. That boot is not
  a check in the repository, because its seed is not.

This says the host files and the two documents agree with each other. It
does not say the seed is right: the stand-in was written by the author
of the host files, from the same reading of the specification.

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
  program; `tests/tinycc/i386-kaem-boot-check.sh` has the refusal alone.
  kaem-optional-seed has no guard at all: a wrong path in
  `/boot/seed.kaem` stops the machine, and the check's timeout ends it.
- a dictionary that outgrows the 32 MiB image. Nothing checks HERE
  against the image's end; the measurement above leaves 22.9 MiB.
- `forth/test-010-lib.fth` ends by exiting with its verdict, so a run
  that stops early at a broken primitive, which the interpreter takes
  for the end of input, also exits 0. The vectors print a last line for
  this reason; that file is the x86-64 route's and was left as it is.

## 10. Questions for the owner

Decided:

- **The three process calls** are in a file listed only for kaem,
  `tinycc/m2libc-kaem-i386.c`. The eleven tool pins do not move.
- **The first-tcc job loads the x86-64 host's driver.** The four paths
  are out of `tinycc/tcc-compile-i386.fth`, in
  `tinycc/tcc-names-i386.fth` for the x86-64 host and on the command
  line for this one. The first tcc keeps `92d11438…`.
- **The acceptance scripts** are in `tests/forth/i386/` and
  `tests/tinycc/`, and run under `CHECK_I386=1`.
- **The book** is not part of this work.

Open:

- **`native!` in the library.** Section 6.2 needs it before 020 loads,
  so the i386 library defines it. That is one more pinned difference in
  both stand-ins, and the only place where the library, not 020, patches
  a seed word.
- **The image size.** 32 MiB is one field of the seed and one constant
  of the checker. The measured need is 9.00 MiB (section 9).
