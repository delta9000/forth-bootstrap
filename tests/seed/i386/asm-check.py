#!/usr/bin/env python3
"""Check seed/i386/000-seed.hex0's comments against its bytes: every byte
line carries the field or instruction it encodes as a ';' comment, and GNU
as and llvm-mc in 32-bit mode, given only the comments, must write the same
bytes.  The rules are section 12 of seed/i386/SPEC.md; "rule N" below is
that section's numbering.

  python3 tests/seed/i386/asm-check.py [--as ASSEMBLER] [--llvm-mc LLVM_MC]
                                       [--keep FILE.S] [SEED]
                                                  (from the repository root)

SEED defaults to seed/i386/000-seed.hex0.  ASSEMBLER (default: as, GNU
binutils) is run as ASSEMBLER --32 FILE.S -o OUT, and LLVM_MC (default:
llvm-mc; skipped when not installed) with -triple=i386-unknown-linux-gnu;
--keep writes FILE.S out.

How the bytes are read: hex0's own rules (text after ';' or '#' is dropped,
the rest is pairs of hex digits), one line at a time, so each line has a
file offset and a length.

Verified, for the file (rules 1 and 2):
  - ASCII only, LF line ends, no CR, and the last byte is LF: builder-hex0's
    hex0 does not test for end of file inside a comment.
  - Each line is blank, a comment starting with ';' or '#', or pairs of hex
    digits optionally followed by ';' and a comment.
  - The file is at most 4096 bytes of image.

Verified, for instructions (everything after the program header):
  - The text after the first ';' (up to the next ';' and with the notes
    below taken out) is the instruction.  It goes into one .intel_syntax
    noprefix source, with every data line in the same place as the .byte
    that its comment states, so that the assembler gives each line the
    offset the hex gives it.  The bytes GNU as writes for the line must
    equal the line's hex, and llvm-mc must write the same.  The object
    must have no relocations and no undefined symbols.
  - The one rewrite from the comments' NASM spelling: "byte/word/dword ["
    becomes "byte/word/dword ptr ["; a label operand becomes its scoped
    symbol.
  - Labels: "----- NAME @ 0xNNN" headings name a routine at file offset
    NNN, and ";; .x:" lines a label inside the last routine (symbol
    NAME.x).  The stated offset must equal the offset of the next byte
    line.  A routine name must be an identifier that is neither a register
    nor a sysvar name.
  - Control transfer (rule 7): call, jmp, the conditional jumps and ret
    only; a call or jump takes a label or a 32-bit register.
  - Branch notes "(relN = A - B)" (rule 8): A must be the offset of the
    label the instruction names, B the offset just past the line, N the
    width of the displacement as written (the line's last N/8 bytes), and
    A - B that displacement.  A branch or call to a label without a note
    fails.
  - "(NAME header)" after an operand (rule 9): an operand must be
    0x08048000 plus NAME's header offset.  Any other literal operand inside
    the image must be the address of a routine heading.
  - The memory map (rule 5): the ";;   0x0NNNNNNN = ..." lines give the
    regions; the data-stack base, sysvar page, initial HERE and image end
    must be there with section 3's addresses, and the "first push lands
    at" address must be the data-stack base minus 8.  The sysvar line
    "STATE +0, LATEST +8, ..." gives each name an offset; each becomes an
    assembler constant, the page's address plus the offset, so a wrong
    offset in the map gives different bytes.  The six interface names must
    have the offsets of section 3.3 and the private ones lie in 48..399.
    Every literal operand at or above the image's end must be an address
    the map names.
  - The calling convention, as far as text shows it (rule 12): a call
    through a register, or to the code of a dictionary word, comes
    directly after a line "push 0"; and a word's code, up to the next
    heading, has no bare "ret", only "ret 4".

Verified, for data:
  - ELF32 header and program header (rule 3): the fields must come in
    Elf32_Ehdr and Elf32_Phdr order, each line's length must be its field's
    size, and its little-endian value must equal the comment's: a number,
    a named constant (ET_EXEC, PT_LOAD, R|W|X, ...), the magic string or
    the zero padding.  The notes "(_start)", "(the whole file)",
    "(32 MiB ...)", "(no section headers)" are checked against the entry
    point, the file size, 32 MiB and e_shnum.  The values must be those of
    SPEC section 2.
  - Dictionary headers ("--- NAME @ 0xNNN --- header", rule 11): stated
    offset equals the offset; link (8 bytes) equals the comment, and the
    comment's "(NAME)" is the previous header in the file, "(end of
    chain)" goes with 0; flags (1 byte) equals the comment, "1 (IMMEDIATE)"
    exactly when the heading says IMMEDIATE; nlen (1 byte) equals the
    comment and the name's length; name equals the quoted string and the
    heading's NAME.  The code heading that follows sits at header + 10 +
    nlen.  The names are exactly SPEC 6.2's 21.
  - LATEST (rule 10): the first line written exactly as
    "mov dword [LATEST], 0x0804NNNN (NAME header)" starts the chain walk:
    it must name the last header in the file, reach every header once and
    end at link 0.
  - Every ";;" line that looks like a heading or label (it has " @ 0x",
    starts with ";; ---", or is ";; .x:") must match one of the patterns
    above; one that does not fails rather than being read as prose.
  - If ./seed-forth-i386 exists (seed/i386/build.sh), the bytes as this
    script reads them must equal it, i.e. hex0-seed's reading (rule 13).

Not verified:
  - The ELF notes "(little-endian)" and "(System V)" are accepted as
    restating the constant, not checked.
  - Heading text after the address (the stack effect, the description) is
    prose; only "IMMEDIATE" after a header heading is read.
  - Prose: ";;" lines other than headings, labels and the memory map, and
    the second ';' note on an instruction line.  They describe behaviour;
    only running the seed (tests/seed/i386/test.sh) tests behaviour.
  - Which of several valid encodings a comment means: the check accepts the
    one both assemblers pick, so a comment is proved to name an instruction
    that encodes as the bytes.
  - That every call to a word's code that is made by a jump, or laid down
    at run time, keeps SPEC section 5's convention.
"""
import argparse, pathlib, re, shutil, struct, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
DEFAULT = ROOT / "seed/i386/000-seed.hex0"
BUILT = ROOT / "seed-forth-i386"
BASE = 0x08048000
LIMIT = 4096
MEMSZ = 32 << 20

EHDR = [("e_ident[0..3]", 4), ("e_ident[EI_CLASS]", 1), ("e_ident[EI_DATA]", 1),
        ("e_ident[EI_VERSION]", 1), ("e_ident[EI_OSABI]", 1),
        ("e_ident[EI_ABIVERSION]", 1), ("e_ident padding", 7), ("e_type", 2),
        ("e_machine", 2), ("e_version", 4), ("e_entry", 4), ("e_phoff", 4),
        ("e_shoff", 4), ("e_flags", 4), ("e_ehsize", 2), ("e_phentsize", 2),
        ("e_phnum", 2), ("e_shentsize", 2), ("e_shnum", 2), ("e_shstrndx", 2)]
PHDR = [("p_type", 4), ("p_offset", 4), ("p_vaddr", 4), ("p_paddr", 4),
        ("p_filesz", 4), ("p_memsz", 4), ("p_flags", 4), ("p_align", 4)]
CONSTANTS = {"ELFCLASS32": 1, "ELFDATA2LSB": 1, "EV_CURRENT": 1, "ELFOSABI_NONE": 0,
             "ET_EXEC": 2, "EM_386": 3, "PT_LOAD": 1, "R|W|X": 7}
# Parenthetical notes on ELF fields that restate the constant and need no check.
RESTATE = {"(little-endian)", "(System V)"}
# SPEC section 2's values; e_entry and p_filesz depend on the file.
REQUIRED = {"e_ident[0..3]": 0x464C457F, "e_ident[EI_CLASS]": 1, "e_ident[EI_DATA]": 1,
            "e_ident[EI_VERSION]": 1, "e_ident[EI_OSABI]": 0, "e_ident[EI_ABIVERSION]": 0,
            "e_ident padding": 0, "e_type": 2, "e_machine": 3, "e_version": 1,
            "e_phoff": 52, "e_shoff": 0, "e_flags": 0, "e_ehsize": 52, "e_phentsize": 32,
            "e_phnum": 1, "e_shentsize": 0, "e_shnum": 0, "e_shstrndx": 0,
            "p_type": 1, "p_offset": 0, "p_vaddr": BASE, "p_paddr": BASE,
            "p_memsz": MEMSZ, "p_flags": 7, "p_align": 0x1000}
# SPEC section 3: the regions the map must name, and the sysvar interface.
REGIONS = {"data-stack base": 0x08059000, "sysvar page": 0x08059000,
           "initial HERE": 0x0805A000, "image end": 0x0A048000}
SYSVARS = {"STATE": 0, "LATEST": 8, "HERE": 16, "LAST_FOUND": 24, "INPUT": 32, "ARGV": 40}
WORDS = "dup drop swap >r r> @ ! c@ c! + * / nand 0= key token find syscall6 state : ;".split()

REG32 = {"eax", "ebx", "ecx", "edx", "esi", "edi", "ebp", "esp"}
REGISTERS = REG32 | {"ax", "bx", "cx", "dx", "si", "di", "bp", "sp", "al", "bl", "cl", "dl",
                     "ah", "bh", "ch", "dh", "cs", "ds", "es", "fs", "gs", "ss"}
JCC = {"j" + c for c in ("o no b c nae nb nc ae e z ne nz be na nbe a s ns p pe np po "
                         "l nge nl ge le ng nle g").split()}
# Other instructions that transfer control: rule 7 allows none of them.
OTHER_TRANSFER = {"loop", "loope", "loopne", "loopz", "loopnz", "jcxz", "jecxz", "retf", "retn",
                  "iret", "iretd", "lcall", "ljmp", "syscall", "sysenter", "into", "enter", "leave"}

HEX_LINE = re.compile(r"^((?:[0-9A-Fa-f]{2}\s*)+)(?:;(.*))?$")
CODE_HEAD = re.compile(r"^;; ----- (\S+) @ 0x([0-9A-F]+)\b")
DICT_HEAD = re.compile(r"^;; --- (\S+) @ 0x([0-9A-F]+) --- header(  IMMEDIATE)?$")
LOCAL = re.compile(r"^;; (\.[a-z_]+):$")
REL = re.compile(r"\(rel(8|32) = 0x([0-9A-F]+) - 0x([0-9A-F]+)\)")
NOTE = re.compile(r"\(([^()]*)\)")
LATEST_INIT = re.compile(r"mov dword \[LATEST\], (0x0804[0-9A-F]{4}) \((\S+) header\)")


class Check:
    def __init__(self):
        self.failures = []
        self.counts = {}

    def ok(self, kind):
        self.counts[kind] = self.counts.get(kind, 0) + 1

    def fail(self, lineno, msg):
        self.failures.append(f"line {lineno}: {msg}")

    def expect(self, cond, lineno, kind, msg):
        if cond:
            self.ok(kind)
        else:
            self.fail(lineno, msg)


def number(text):
    return int(text, 0)


def raw(data):
    return ".byte " + ", ".join(f"0x{b:02x}" for b in data)


def read_lines(path):
    """(lineno, offset, bytes, comment) per byte line; (lineno, None, None, text)
    otherwise.  Rules 1 and 2 stop the check here."""
    blob = path.read_bytes()
    if any(b > 0x7F for b in blob):
        sys.exit("seed asm-check: the file has a byte that is not ASCII")
    if b"\r" in blob:
        sys.exit("seed asm-check: the file has a CR; lines end with LF only")
    if not blob.endswith(b"\n"):
        sys.exit("seed asm-check: the last byte of the file is not LF "
                 "(builder-hex0's hex0 would not leave a final comment)")
    rows, offset = [], 0
    for lineno, line in enumerate(blob.decode("ascii").split("\n")[:-1], 1):
        text = line.strip()
        if not text or text.startswith((";", "#")):
            rows.append((lineno, None, None, text))
            continue
        m = HEX_LINE.match(text)
        if not m:
            sys.exit(f"seed asm-check: line {lineno} is neither bytes nor a comment: {line}")
        data = bytes.fromhex(m.group(1))
        rows.append((lineno, offset, data, (m.group(2) or "").strip()))
        offset += len(data)
    return rows, offset


def memory_map(rows, ck):
    """Regions from the ';;   0x0NNNNNNN = ...' lines, as (address,
    description) pairs; sysvar names and their addresses from the page's
    'NAME +N, ...' line."""
    text = "\n".join(c for _, off, _, c in rows if off is None)
    regions = [(int(a, 16), d.strip()) for a, d in
               re.findall(r"^;;\s+0x(0[0-9A-F]{7}) = (.*)$", text, re.M)]
    lineno = next((r[0] for r in rows if r[1] is None and "data-stack base" in r[3]), 0)
    for start, address in REGIONS.items():
        found = [a for a, d in regions if d.startswith(start)]
        ck.expect(found == [address], lineno, "memory-map",
                  f"the map must have one '{start}' line, at {address:#010x}; it has {found}")
    stack = [d for a, d in regions if d.startswith("data-stack base")]
    push = stack and re.search(r"first push lands at 0x([0-9A-F]{8})", stack[0])
    ck.expect(push and int(push.group(1), 16) == REGIONS["data-stack base"] - 8, lineno, "memory-map",
              f"the data-stack base line must say: first push lands at "
              f"0x{REGIONS['data-stack base'] - 8:08X}")
    listed = re.search(r"^;;\s+([A-Z_]+ \+\d+(?:, [A-Z_]+ \+\d+)*)$", text, re.M)
    if not listed:
        sys.exit("seed asm-check: memory map has no sysvar line 'STATE +0, LATEST +8, ...'")
    pairs = [(n, int(o)) for n, o in re.findall(r"([A-Z_]+) \+(\d+)", listed.group(1))]
    names = dict(pairs)
    ck.expect(len(names) == len(pairs), lineno, "memory-map", "a sysvar name is listed twice")
    ck.expect(pairs[:len(SYSVARS)] == list(SYSVARS.items()), lineno, "memory-map",
              f"the sysvar line must start with {', '.join(f'{n} +{o}' for n, o in SYSVARS.items())}")
    for n, o in pairs[len(SYSVARS):]:
        ck.expect(48 <= o < 400, lineno, "memory-map",
                  f"private variable {n} +{o} is outside 48..399 of the sysvar page")
    page = REGIONS["sysvar page"]
    return regions, {n: page + o for n, o in names.items()}


def elf_value(field, comment, size):
    """The value an ELF field's comment states, and its parenthetical notes."""
    rhs = comment.split("=", 1)[1].strip()
    if field == "e_ident[0..3]":
        m = re.fullmatch(r'magic "\\x7fELF"', rhs)
        return (b"\x7fELF" if m else None), []
    head = rhs.split(" (", 1)[0].strip()
    notes = NOTE.findall(rhs[len(head):])
    value = CONSTANTS.get(head)
    if value is None:
        try:
            value = number(head)
        except ValueError:
            return None, notes
    return value.to_bytes(size, "little"), notes


def check_elf(rows, ck, labels, size, asm):
    table = EHDR + PHDR
    data_lines = [r for r in rows if r[1] is not None][:len(table)]
    fields = {}
    routines = [o for n, o in labels.items() if "." not in n]
    for (lineno, off, data, comment), (field, width) in zip(data_lines, table):
        if comment == "e_ident padding (7 zero bytes)":
            stated, notes = bytes(7), []
        elif not comment.startswith(field + " = "):
            ck.fail(lineno, f"expected field {field}, comment is: {comment}")
            asm.append((lineno, raw(data)))
            continue
        else:
            stated, notes = elf_value(field, comment, width)
        if stated is None:
            ck.fail(lineno, f"cannot read the value of {field}: {comment}")
            asm.append((lineno, raw(data)))
            continue
        ck.expect(len(data) == width, lineno, "elf-field", f"{field} is {width} bytes, line has {len(data)}")
        ck.expect(data == stated, lineno, "elf-field", f"{field}: bytes {data.hex(' ')}, comment states {stated.hex(' ')}")
        fields[field] = value = int.from_bytes(stated, "little")
        if field in REQUIRED:
            ck.expect(value == REQUIRED[field], lineno, "elf-value",
                      f"{field} is {value:#x}; SPEC section 2 requires {REQUIRED[field]:#x}")
        elif field == "e_entry":
            ck.expect(value - BASE in routines, lineno, "elf-value",
                      f"e_entry {value:#x} is not {BASE:#x} plus the offset of a routine heading")
        elif field == "p_filesz":
            ck.expect(value == size, lineno, "elf-value", f"p_filesz {value}, the file is {size} bytes")
        for note in notes:
            if f"({note})" in RESTATE:
                continue
            if note == "_start" and field == "e_entry":
                ck.expect("_start" in labels and value == BASE + labels["_start"], lineno, "elf-note",
                          "e_entry is not _start")
            elif note == "the whole file" and field == "p_filesz":
                ck.expect(value == size, lineno, "elf-note", f"p_filesz {value}, file is {size}")
            elif note.startswith("32 MiB") and field == "p_memsz":
                ck.expect(value == MEMSZ, lineno, "elf-note", "p_memsz is not 32 MiB")
            elif note == "no section headers":
                ck.ok("elf-note")           # checked against e_shnum below
            else:
                ck.fail(lineno, f"unrecognised note on {field}: ({note})")
        asm.append((lineno, raw(stated)))
    ck.expect(len(fields) == len(table), 0, "elf-note",
              f"{len(fields)} of the {len(table)} ELF fields were read")
    if fields.get("e_shoff") == 0:
        ck.expect(fields.get("e_shnum") == 0, 0, "elf-note", "e_shoff 0 but e_shnum not 0")
    return len(data_lines)


def build(rows, size, ck):
    """Walk the lines: the memory map, then label and header offsets."""
    regions, sysvars = memory_map(rows, ck)
    labels, label_line, headers, order = {}, {}, {}, []
    word_code = set()           # routines that directly follow a dictionary header
    pending = []                # headings and labels waiting for a byte line
    routine = None
    after_header = False
    for i, (lineno, off, data, text) in enumerate(rows):
        if off is None:
            tag = None
            for pat, kind in ((DICT_HEAD, "header"), (CODE_HEAD, "routine")):
                m = pat.match(text)
                if m:
                    tag = (lineno, kind, m.group(1), int(m.group(2), 16),
                           bool(kind == "header" and m.group(3)))
                    break
            else:
                m = LOCAL.match(text)
                if m:
                    tag = (lineno, "local", f"{routine}{m.group(1)}", None, False)
                elif (" @ 0x" in text or text.startswith(";; ---")
                      or re.match(r";;\s*\.\w*:?\s*$", text)) and not text.startswith(";; ====="):
                    ck.fail(lineno, f"a heading or label the check cannot read: {text}")
            if tag:
                if tag[1] == "routine":
                    routine = tag[2]
                    ck.expect(re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", routine) is not None
                              and routine.lower() not in REGISTERS and routine not in sysvars,
                              lineno, "heading-name",
                              f"routine name {routine} must be an identifier that is not a "
                              "register or a sysvar name")
                    if after_header:
                        word_code.add(routine)
                after_header = tag[1] == "header"
                rows[i] = (lineno, off, data, text, tag)
                pending.append(tag)
            continue
        for plineno, kind, name, stated, immediate in pending:
            if stated is not None:
                ck.expect(stated == off, plineno, "heading-address",
                          f"{name} stated at {stated:#x}, its first byte is at {off:#x}")
            if kind == "header":
                if name in headers:
                    ck.fail(plineno, f"header {name} defined twice")
                headers[name] = (off, immediate, plineno)
                order.append(name)
            else:
                if name in labels:
                    ck.fail(plineno, f"label {name} defined twice")
                labels[name], label_line[name] = off, plineno
        pending = []
    if pending:
        ck.fail(pending[0][0], "a heading or label with no byte line after it")
    return regions, sysvars, labels, headers, order, word_code


def instruction(lineno, off, data, comment, routine, labels, sysvars, headers, size, ck):
    """(GNU as text, mnemonic, operands) for one instruction line, after its
    notes are checked; None if the line is rejected."""
    insn = comment.split(";", 1)[0].strip()
    end = off + len(data)
    if not insn:
        ck.fail(lineno, "byte line without an instruction comment")
        return None
    rel = REL.search(insn)
    if rel:
        insn = REL.sub("", insn).strip()
    hdr = re.search(r"\((\S+) header\)$", insn)
    if hdr:
        insn = insn[:hdr.start()].strip()
    if "(" in insn or ")" in insn:
        ck.fail(lineno, f"unrecognised note in instruction: {comment}")
        return None
    mnemonic, _, operands = insn.partition(" ")
    ops = [o.strip() for o in operands.split(",")] if operands else []
    if mnemonic in OTHER_TRANSFER:
        ck.fail(lineno, f"{mnemonic}: only call, jmp, jcc and ret may transfer control")
        return None
    if mnemonic in ("call", "jmp") or mnemonic in JCC:
        if len(ops) != 1:
            ck.fail(lineno, f"{mnemonic} takes one operand: {insn}")
            return None
        name = ops[0]
        if name in REG32 and mnemonic in ("call", "jmp"):
            if rel:
                ck.fail(lineno, f"rel note on a branch through a register: {comment}")
        else:
            target = f"{routine}{name}" if name.startswith(".") else name
            if target not in labels:
                ck.fail(lineno, f"branch to unknown label {name}")
                return None
            if not rel:
                ck.fail(lineno, f"branch to {name} without a (relN = A - B) note")
            else:
                width, a, b = int(rel.group(1)), int(rel.group(2), 16), int(rel.group(3), 16)
                disp = int.from_bytes(data[-width // 8:], "little", signed=True)
                ck.expect(a == labels[target], lineno, "rel-note",
                          f"note's target {a:#x}, {name} is at {labels[target]:#x}")
                ck.expect(b == end, lineno, "rel-note", f"note's origin {b:#x}, the line ends at {end:#x}")
                ck.expect(disp == a - b, lineno, "rel-note",
                          f"rel{width} in the bytes is {disp:#x}, note says {a - b:#x}")
                ck.expect(len(data) - width // 8 in (1, 2), lineno, "rel-note",
                          f"rel{width} does not fit the line's {len(data)} bytes")
            ops[0] = target
    elif rel:
        ck.fail(lineno, f"rel note on a non-branch: {comment}")
    if hdr:
        name = hdr.group(1)
        lit = [number(t) for t in re.findall(r"\b0x[0-9A-Fa-f]+\b", insn)]
        ck.expect(name in headers and BASE + headers[name][0] in lit, lineno, "address-note",
                  f"({name} header): no operand equals its header address")
    for t in re.findall(r"(?<![\w.])(0x[0-9A-Fa-f]+|\d+)\b", insn):
        v = number(t)
        if BASE <= v < BASE + size and not hdr:
            ck.expect(v - BASE in [o for n, o in labels.items() if "." not in n], lineno, "address-note",
                      f"literal {v:#x} is inside the image but no routine starts there")
        elif v >= BASE + size:
            ck.expect(v in MAPPED, lineno, "memory-map", f"literal {v:#x} is not in the memory map")
    text = mnemonic + (" " + ", ".join(ops) if ops else "")
    text = re.sub(r"\b(byte|word|dword) \[", r"\1 ptr [", text)
    return text, mnemonic, ops


MAPPED = set()


def dictionary_field(lineno, data, comment, state, headers, order, ck):
    """.byte for one dictionary header field; checks its comment."""
    name, idx = state["header"], state["field"]
    if idx > 3:
        ck.fail(lineno, f"{name}: a fifth byte line before the code heading")
        return None
    m = re.fullmatch(r"(link|flags|nlen|name)\s+= (.*)", comment)
    want = ("link", "flags", "nlen", "name")[idx]
    if not m or m.group(1) != want:
        ck.fail(lineno, f"{name}: expected the {want} field, comment is: {comment}")
        return None
    rhs = m.group(2).strip()
    if want == "name":
        s = re.fullmatch(r'"(.*)"', rhs)
        if not s:
            ck.fail(lineno, f"{name}: cannot read the name: {rhs}")
            return None
        stated = s.group(1).encode()
        ck.expect(s.group(1) == name, lineno, "dict-field", f"name {s.group(1)!r}, heading says {name!r}")
        ck.expect(len(stated) == state.get("nlen"), lineno, "dict-field",
                  f"nlen {state.get('nlen')}, name is {len(stated)} bytes")
    else:
        v = re.fullmatch(r"(0x[0-9A-F]+|\d+)(?: \((.*)\))?", rhs)
        if not v:
            ck.fail(lineno, f"{name}: cannot read {want}: {rhs}")
            return None
        value, note = number(v.group(1)), v.group(2)
        width = 8 if want == "link" else 1
        stated = value.to_bytes(width, "little")
        if want == "link":
            prev = order[order.index(name) - 1] if order.index(name) else None
            if prev is None:
                ck.expect(value == 0 and note == "end of chain", lineno, "dict-field",
                          f"first header's link is {rhs}, expected 0 (end of chain)")
            else:
                ck.expect(note == prev and value == BASE + headers[prev][0], lineno, "dict-field",
                          f"link {rhs}: previous header is {prev} at {BASE + headers[prev][0]:#x}")
            state["link"] = value
        elif want == "flags":
            immediate = headers[name][1]
            ck.expect((value, note) == ((1, "IMMEDIATE") if immediate else (0, None)), lineno,
                      "dict-field", f"flags {rhs}, heading {'says' if immediate else 'does not say'} IMMEDIATE")
        else:
            state["nlen"] = value
    ck.expect(data == stated, lineno, "dict-field",
              f"{name} {want}: bytes {data.hex(' ')}, comment states {stated.hex(' ')}")
    state["field"] += 1
    return raw(stated)


def elf_symbols(path):
    """(.text content, defined symbol values, undefined names, relocation
    count) of an ELF32 object."""
    data = path.read_bytes()
    shoff, = struct.unpack_from("<I", data, 0x20)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x2E)
    sh = [struct.unpack_from("<10I", data, shoff + i * shentsize) for i in range(shnum)]
    # name, type, flags, addr, offset, size, link, info, addralign, entsize
    def name(off, table):
        start = sh[table][4] + off
        return data[start:data.index(b"\0", start)].decode()
    names = [name(s[0], shstrndx) for s in sh]
    text = next(i for i, n in enumerate(names) if n == ".text")
    symtab = next(i for i, s in enumerate(sh) if s[1] == 2)
    syms, undefined = {}, []
    for k in range(1, sh[symtab][5] // 16):
        st_name, value, size, info, other, shndx = struct.unpack_from(
            "<IIIBBH", data, sh[symtab][4] + 16 * k)
        n = name(st_name, sh[symtab][6])
        if shndx == 0 and n:
            undefined.append(n)
        elif shndx == text and n:
            syms[n] = value
    relocs = sum(s[5] // (8 if s[1] == 9 else 12) for s in sh if s[1] in (4, 9))
    content = data[sh[text][4]:sh[text][4] + sh[text][5]]
    return content, syms, undefined, relocs


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--as", dest="assembler", default="as")
    ap.add_argument("--llvm-mc", dest="llvm_mc", default="llvm-mc",
                    help="second, independent assembler; skipped if not installed")
    ap.add_argument("--keep", help="also write the generated assembler source here")
    ap.add_argument("seed", nargs="?", default=str(DEFAULT))
    args = ap.parse_args()
    ck = Check()
    rows, size = read_lines(pathlib.Path(args.seed))
    ck.expect(size <= LIMIT, 0, "size", f"the image is {size} bytes; the limit is {LIMIT}")
    regions, sysvars, labels, headers, order, word_code = build(rows, size, ck)
    MAPPED.update(a for a, _ in regions)

    asm = []                    # (lineno, text): one per byte line, in order
    n_elf = check_elf(rows, ck, labels, size, asm)
    byte_rows = [r for r in rows if r[1] is not None]
    kinds = {}                  # lineno -> "elf" | "dict" | "insn"
    for r in byte_rows[:n_elf]:
        kinds[r[0]] = "elf"
    out = [".intel_syntax noprefix", ".text"]
    out += [f".equ {n}, {v:#x}" for n, v in sysvars.items()]
    for lineno, text in asm:
        out += [f"line{lineno}:", "    " + text]
    routine, state, latest_init = None, None, None
    in_word = False             # inside the code of a dictionary word
    previous = None             # the instruction text of the byte line before
    elf_lines = {r[0] for r in byte_rows[:n_elf]}
    for row in rows:
        lineno, off, data, text = row[:4]
        if off is None:
            if len(row) == 5:
                _, kind, name, _, _ = row[4]
                if kind == "header":
                    if state is not None:
                        ck.fail(lineno, f"header {state['header']} has no code heading")
                    state = {"header": name, "field": 0}
                    in_word = False
                    out.append(f"# header {name}")
                else:
                    if kind == "routine":
                        routine = name
                        in_word = name in word_code
                        if state and state["field"] != 4:
                            ck.fail(lineno, f"header {state['header']} has {state['field']} of 4 fields")
                        elif state:
                            hoff = headers[state["header"]][0]
                            ck.expect(labels[name] == hoff + 10 + state["nlen"], lineno, "dict-field",
                                      f"{name} at {labels[name]:#x}, header {state['header']} "
                                      f"ends at {hoff + 10 + state['nlen']:#x}")
                        state = None
                    out.append(f"{name}:")
            continue
        if lineno in elf_lines:
            continue
        if state is not None:
            line = dictionary_field(lineno, data, text, state, headers, order, ck)
            kinds[lineno] = "dict"
            previous = None
        else:
            got = instruction(lineno, off, data, text, routine, labels, sysvars,
                              headers, size, ck)
            kinds[lineno] = "insn"
            line = got and got[0]
            if got:
                _, mnemonic, ops = got
                # Rule 12: the convention, as far as the text shows it.
                if mnemonic == "call" and (ops[0] in REG32 or ops[0] in word_code):
                    ck.expect(previous == "push 0", lineno, "convention",
                              f"call {ops[0]} enters a dictionary word and must come directly "
                              "after a line 'push 0'")
                if mnemonic == "ret" and in_word:
                    ck.expect(ops == ["4"], lineno, "convention",
                              f"a dictionary word's code returns with 'ret 4', not '{line}'")
                init = LATEST_INIT.fullmatch(text.split(";", 1)[0].strip())
                if init and latest_init is None:
                    latest_init = (lineno, number(init.group(1)), init.group(2))
            previous = line
        if line is None:               # rejected and reported; keep later offsets
            line = raw(data)
            kinds[lineno] = "rejected"
        out += [f"line{lineno}:", "    " + line]
    if state is not None:
        ck.fail(0, f"header {state['header']} has no code heading")
    source = "\n".join(out) + "\n"
    if args.keep:
        pathlib.Path(args.keep).write_text(source)

    # The dictionary: SPEC 6.2's names, and the chain from LATEST's initial value.
    ck.expect(sorted(order) == sorted(WORDS), 0, "names",
              f"the headers are not exactly SPEC 6.2's 21 names: missing "
              f"{sorted(set(WORDS) - set(order))}, extra {sorted(set(order) - set(WORDS))}")
    if latest_init is None:
        ck.fail(0, "no line 'mov dword [LATEST], 0x0804NNNN (NAME header)'")
    else:
        by_addr = {BASE + off: n for n, (off, _, _) in headers.items()}
        seen, addr = [], latest_init[1]
        link_of = {}
        for r in byte_rows:
            if kinds.get(r[0]) == "dict" and r[3].startswith("link"):
                link_of[r[1]] = int.from_bytes(r[2], "little")
        while addr and addr in by_addr and by_addr[addr] not in seen:
            seen.append(by_addr[addr])
            addr = link_of[addr - BASE]
        ck.expect(addr == 0 and sorted(seen) == sorted(headers), latest_init[0], "chain",
                  f"the chain from LATEST reaches {len(seen)} of {len(headers)} headers"
                  f" and stops at {addr:#x}")
        ck.expect(seen == order[::-1], latest_init[0], "chain",
                  "the chain order is not the file order, starting at the last header")
        ck.expect(order and latest_init[2] == order[-1] != ";", latest_init[0], "chain",
                  f"LATEST starts at {latest_init[2]}; it must be the last header, and not ';'")

    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        (tmp / "seed.S").write_text(source)
        obj = tmp / "seed.o"
        run = subprocess.run([args.assembler, "--32", str(tmp / "seed.S"), "-o", str(obj)],
                             capture_output=True, text=True)
        if run.returncode:
            src = {}
            for n, l in enumerate(out, 1):
                m = re.fullmatch(r"line(\d+):", l)
                if m:
                    src[n + 1] = m.group(1)
            print(re.sub(r"^.*?seed\.S:(\d+):", lambda m: f"seed line {src.get(int(m.group(1)), '?')}:",
                         run.stderr, flags=re.M), end="")
            for f in ck.failures:
                print(f"seed asm-check: FAIL {f}")
            sys.exit(f"seed asm-check: {args.assembler} failed on the comments "
                     "(its messages name lines of the generated source; --keep writes it)")
        text, syms, undefined, relocs = elf_symbols(obj)
        # The same source through LLVM's assembler, a separate implementation:
        # every byte must agree with GNU as's (and so with the hex).
        llvm_text = None
        if shutil.which(args.llvm_mc):
            lobj = tmp / "seed-llvm.o"
            lrun = subprocess.run([args.llvm_mc, "-triple=i386-unknown-linux-gnu", "-filetype=obj",
                                   "-o", str(lobj), str(tmp / "seed.S")], capture_output=True, text=True)
            if lrun.returncode:
                print(lrun.stderr, end="")
                sys.exit(f"seed asm-check: {args.llvm_mc} failed on the comments")
            llvm_text, _, _, llvm_relocs = elf_symbols(lobj)
            if llvm_relocs:
                ck.fail(0, f"{llvm_relocs} relocations from {args.llvm_mc}: an operand did not "
                        "resolve to a constant")
    if undefined:
        ck.fail(0, f"undefined symbols in the comments: {', '.join(undefined)}")
    if relocs:
        ck.fail(0, f"{relocs} relocations: an operand did not resolve to a constant")
    image = b"".join(r[2] for r in byte_rows)
    shifted = False
    totals = {"elf": 0, "dict": 0, "insn": 0}
    lines_by_kind = {"elf": 0, "dict": 0, "insn": 0}
    for lineno, off, data, comment in byte_rows:
        kind = kinds.get(lineno)
        if kind is None:
            ck.fail(lineno, "byte line is neither a data field nor an instruction")
            continue
        if kind == "rejected":
            continue
        sym = syms.get(f"line{lineno}")
        if sym is None:
            continue                    # failed earlier, already reported
        if sym != off:
            if not shifted:
                ck.fail(lineno, f"as places this line at {sym:#x}, the hex at {off:#x}"
                        " (an earlier comment assembles to a different length)")
            shifted = True
            continue
        got = text[off:off + len(data)]
        if kind == "insn":
            ck.expect(got == data, lineno, "instruction",
                      f"{comment.split(';')[0].strip()}: hex {data.hex(' ')}, as writes {got.hex(' ')}")
        totals[kind] += len(data)
        lines_by_kind[kind] += 1
    if len(text) != size:
        ck.fail(0, f"as wrote {len(text)} bytes, the hex is {size}")
    if llvm_text is not None:
        if llvm_text != text:
            for lineno, off, data, comment in byte_rows:
                if llvm_text[off:off + len(data)] != text[off:off + len(data)]:
                    ck.fail(lineno, f"{comment.split(';')[0].strip()}: as writes {text[off:off + len(data)].hex(' ')},"
                            f" llvm-mc writes {llvm_text[off:off + len(data)].hex(' ')}")
                    break
            if len(llvm_text) != len(text):
                ck.fail(0, f"llvm-mc wrote {len(llvm_text)} bytes, as {len(text)}")
    if BUILT.exists() and pathlib.Path(args.seed).resolve() == DEFAULT.resolve():
        ck.expect(BUILT.read_bytes() == image, 0, "image",
                  "this parse of the hex differs from ./seed-forth-i386")

    if ck.failures:
        for f in ck.failures:
            print(f"seed asm-check: FAIL {f}")
        sys.exit(f"seed asm-check: {len(ck.failures)} mismatches between comments and bytes")
    covered = sum(totals.values())
    c = ck.counts
    shown = pathlib.Path(args.seed).resolve()
    shown = shown.relative_to(ROOT) if shown.is_relative_to(ROOT) else shown
    print(f"seed asm-check: {shown}'s bytes equal {args.assembler} on its comments: "
          f"{covered} of {size} bytes")
    if llvm_text is not None:
        print(f"seed asm-check: and {args.llvm_mc} on the same comments writes the same {len(llvm_text)} bytes")
    else:
        print(f"seed asm-check: {args.llvm_mc} not found; the second assembler was skipped")
    print(f"  {lines_by_kind['insn']} instructions ({totals['insn']} bytes), "
          f"{lines_by_kind['elf']} ELF fields ({totals['elf']} bytes), "
          f"{lines_by_kind['dict']} dictionary fields in {len(headers)} headers ({totals['dict']} bytes)")
    print(f"  {c.get('rel-note', 0)} branch-note checks, {c.get('heading-address', 0)} heading addresses, "
          f"{len(labels)} labels, {c.get('address-note', 0)} address operands, "
          f"{c.get('memory-map', 0)} memory-map checks, {c.get('elf-value', 0)} ELF values, "
          f"{c.get('elf-note', 0)} ELF notes, {c.get('convention', 0)} convention checks, "
          f"{c.get('chain', 0)} chain checks")


if __name__ == "__main__":
    main()
