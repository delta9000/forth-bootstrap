#!/usr/bin/env python3
"""Check seed/000-seed.hex0's comments against its bytes: every byte line
carries the field or instruction it encodes as a ';' comment, and GNU as,
given only the comments, must write the same 1,772 bytes.

  python3 tests/seed/asm-check.py [--as ASSEMBLER] [--keep FILE.S] [SEED]
                                                  (from the repository root)

SEED defaults to seed/000-seed.hex0.  ASSEMBLER (default: as, GNU binutils)
is run as ASSEMBLER --64 FILE.S -o OUT; --keep writes FILE.S out.

How the bytes are read: hex0's own rules (text after ';' or '#' is dropped,
the rest is pairs of hex digits), one line at a time, so each line has a
file offset and a length.  Every line with bytes must be a data field or an
instruction; a line that is neither fails the check.

Verified, for instructions (everything after the program header):
  - The text after the first ';' (up to the next ';' and with the notes below
    taken out) is the instruction.  It goes into one .intel_syntax noprefix
    source, with every data line in the same place as the .byte/.quad that
    its comment states, so that GNU as gives each line the offset the hex
    gives it.  The bytes as writes for the line must equal the line's hex.
    The object must have no relocations and no undefined symbols.
  - Rewrites from the comments' NASM spelling to GNU as, and nothing else:
    "byte/word/qword [" becomes "byte/word/qword ptr ["; a label operand
    becomes its scoped symbol (below); "mov r64, imm" becomes "movabs r64,
    imm" where the line's note says (movabs).
  - Labels: "----- NAME @ 0xNNN" headings name a routine at NNN, and
    ";; .x:" lines a label inside the last routine (symbol NAME.x).  The
    stated address must equal the offset of the next byte line.
  - Branch notes "(relN = A - B)": A must be the address of the label the
    instruction names, B the offset just past the line, N the width of the
    displacement as written (the line's last N/8 bytes), and A - B that
    displacement.  A branch or call to a label without a note fails.
  - "(NAME header)" after an operand: the operand must be 0x400000 plus
    NAME's header address.  Any other literal operand inside the image
    (0x400000 to 0x400000 + file size) must be the address of a routine.
  - The memory map (the ";;   0x4NNNNN = ..." block) is parsed for the
    sysvar names STATE, LATEST, HERE, LAST_FOUND and their addresses (the
    page base plus 8 each, and the listed addresses must agree); the
    instructions use those names.  The "first push lands at" address must
    be the data-stack base minus 8.  Every literal operand outside the image
    must be an address the map names.

Verified, for data:
  - ELF64 header and program header: the fields must come in Elf64_Ehdr and
    Elf64_Phdr order, each line's length must be its field's size, and its
    little-endian value must equal the comment's: a number, a named
    constant (ET_EXEC, PT_LOAD, R|W|X, ...), the magic string or the zero
    padding.  The parenthetical notes "(_start)", "(the whole file)",
    "(16 MiB ...)", "(no section headers)" are checked against the entry
    point, the file size, 16 MiB and e_shnum.
  - Dictionary headers ("--- NAME @ 0xNNN --- header"): stated address
    equals the offset; link (8 bytes) equals the comment, and the comment's
    "(NAME)" is the previous header, "(end of chain)" goes with 0; flags
    (1 byte) equals the comment, "1 (IMMEDIATE)" exactly when the heading
    says IMMEDIATE; nlen (1 byte) equals the comment and the name's length;
    name equals the quoted string and the heading's NAME.  The code
    heading that follows sits at header + 10 + nlen.  The chain is walked
    from LATEST's initial value (in sysvar_init): it must reach every header
    once and end at link 0.
  - Every ";;" line that looks like a heading or label (it has " @ 0x",
    starts with ";; ---", or is ";; .x:") must match one of the patterns
    above; one that does not fails rather than being read as prose.
  - The load address: the check uses offset N = address 0x400000 + N, and
    requires p_vaddr = 0x400000 and p_offset = 0.
  - If ./seed-forth exists (seed/build.sh, check-all step 01), the bytes as
    this script reads them must equal it, i.e. hex0-seed's reading.

Not verified:
  - The ELF notes "(little-endian)", "(System V)" and "(ignored on Linux)"
    are accepted as restating the constant, not checked.
  - Heading text after the address (the stack effect, the description) is
    prose; only "IMMEDIATE" after a header heading is read.
  - Prose: ";;" lines other than headings, labels and the memory map, and
    the second ';' note on an instruction line (stack effects, what a
    register holds, "clobbers rcx, r11").  They describe behaviour; only
    running the seed (./test.sh) tests behaviour.
  - Which of several valid encodings a comment means, beyond the movabs
    rule above: the check accepts the one GNU as picks, so a comment is
    proved to name an instruction that encodes as the bytes.
"""
import argparse, pathlib, re, struct, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = 0x400000

EHDR = [("e_ident[0..3]", 4), ("e_ident[EI_CLASS]", 1), ("e_ident[EI_DATA]", 1),
        ("e_ident[EI_VERSION]", 1), ("e_ident[EI_OSABI]", 1),
        ("e_ident[EI_ABIVERSION]", 1), ("e_ident padding", 7), ("e_type", 2),
        ("e_machine", 2), ("e_version", 4), ("e_entry", 8), ("e_phoff", 8),
        ("e_shoff", 8), ("e_flags", 4), ("e_ehsize", 2), ("e_phentsize", 2),
        ("e_phnum", 2), ("e_shentsize", 2), ("e_shnum", 2), ("e_shstrndx", 2)]
PHDR = [("p_type", 4), ("p_flags", 4), ("p_offset", 8), ("p_vaddr", 8),
        ("p_paddr", 8), ("p_filesz", 8), ("p_memsz", 8), ("p_align", 8)]
CONSTANTS = {"ELFCLASS64": 2, "ELFDATA2LSB": 1, "EV_CURRENT": 1, "ELFOSABI_NONE": 0,
             "ET_EXEC": 2, "EM_X86_64": 62, "PT_LOAD": 1, "R|W|X": 7}
# Parenthetical notes on ELF fields that restate the constant and need no check.
RESTATE = {"(little-endian)", "(System V)", "(ignored on Linux)"}

HEX_LINE = re.compile(r"^((?:[0-9A-Fa-f]{2}\s*)+)(?:[;#](.*))?$")
CODE_HEAD = re.compile(r"^;; ----- (\S+) @ 0x([0-9A-F]+)\b")
DICT_HEAD = re.compile(r"^;; --- (\S+) @ 0x([0-9A-F]+) --- header(  IMMEDIATE)?$")
LOCAL = re.compile(r"^;; (\.[a-z_]+):$")
REL = re.compile(r"\(rel(8|32) = 0x([0-9A-F]+) - 0x([0-9A-F]+)\)")
NOTE = re.compile(r"\(([^()]*)\)")


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
    """(lineno, offset, bytes, comment) per byte line; (lineno, text) otherwise."""
    rows, offset = [], 0
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        m = HEX_LINE.match(line.strip())
        if not line.strip() or line.lstrip().startswith((";", "#")) or not m:
            if line.strip() and not line.lstrip().startswith((";", "#")):
                sys.exit(f"seed asm-check: line {lineno} is neither bytes nor a comment: {line}")
            rows.append((lineno, None, None, line.strip()))
            continue
        data = bytes.fromhex(m.group(1))
        rows.append((lineno, offset, data, (m.group(2) or "").strip()))
        offset += len(data)
    return rows, offset


def memory_map(rows, ck):
    """Names and addresses from the ';;   0x4NNNNN = ...' block."""
    text = "\n".join(c for _, off, _, c in rows if off is None)
    regions = dict((int(a, 16), d.strip()) for a, d in
                   re.findall(r"^;;\s+0x(4[0-9A-F]{5}) = (.*)$", text, re.M))
    names = {}
    lineno = next((r[0] for r in rows if r[1] is None and "data-stack base" in r[3]), 0)
    for addr, desc in regions.items():
        m = re.match(r"sysvar page, 8 bytes each: ([A-Z_, ]+)$", desc)
        if m:
            for i, n in enumerate(x.strip() for x in m.group(1).split(",")):
                names[n] = addr + 8 * i
    listed = re.search(r"^;;\s+\((0x[0-9A-F]+(?:, 0x[0-9A-F]+)*)\)$", text, re.M)
    if not names or not listed:
        sys.exit("seed asm-check: memory map has no sysvar page line")
    ck.expect([number(x) for x in listed.group(1).split(", ")] == list(names.values()),
              lineno, "memory-map", f"sysvar addresses listed {listed.group(1)}, "
              f"page base + 8 each gives {[hex(v) for v in names.values()]}")
    stack = next(a for a, d in regions.items() if d.startswith("data-stack base"))
    push = re.search(r"first push lands at 0x([0-9A-F]+)", regions[stack])
    ck.expect(push and int(push.group(1), 16) == stack - 8, lineno, "memory-map",
              f"first push stated {push and push.group(1)}, data-stack base - 8 is {stack - 8:#x}")
    return regions, names


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
    for (lineno, off, data, comment), (field, width) in zip(data_lines, table):
        if comment == "e_ident padding (7 zero bytes)":
            stated, notes = bytes(7), []
        elif not comment.startswith(field) or "=" not in comment:
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
        fields[field] = int.from_bytes(stated, "little")
        for note in notes:
            if f"({note})" in RESTATE:
                continue
            if note == "_start":
                ck.expect(fields[field] == BASE + labels["_start"], lineno, "elf-note", "e_entry is not _start")
            elif note == "the whole file":
                ck.expect(fields[field] == size, lineno, "elf-note", f"p_filesz {fields[field]}, file is {size}")
            elif note.startswith("16 MiB"):
                ck.expect(fields[field] == 16 << 20, lineno, "elf-note", "p_memsz is not 16 MiB")
            elif note == "no section headers":
                ck.ok("elf-note")           # checked against e_shnum below
            else:
                ck.fail(lineno, f"unrecognised note on {field}: ({note})")
        asm.append((lineno, raw(stated)))
    if fields.get("e_shoff") == 0:
        ck.expect(fields.get("e_shnum") == 0, 0, "elf-note", "e_shoff 0 but e_shnum not 0")
    ck.expect(fields.get("e_phoff") == 64 and fields.get("e_ehsize") == 64
              and fields.get("e_phentsize") == 56, 0, "elf-note", "header sizes or e_phoff wrong")
    ck.expect(fields.get("p_vaddr") == BASE and fields.get("p_offset") == 0, 0, "elf-note",
              f"the check takes file offset N as address {BASE:#x} + N; p_vaddr/p_offset disagree")
    return len(data_lines)


def build(rows, size, ck):
    """Walk the lines after the ELF headers: labels, headers, instructions."""
    regions, sysvars = memory_map(rows, ck)
    labels, label_line, headers, order = {}, {}, {}, []
    pending = []                # headings and labels waiting for a byte line
    routine = None
    # First pass: label and header addresses (stated, then the actual offset).
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
                rows[i] = (lineno, off, data, text, tag)
                pending.append(tag)
            continue
        for plineno, kind, name, stated, immediate in pending:
            if stated is not None:
                ck.expect(stated == off, plineno, "heading-address",
                          f"{name} stated at {stated:#x}, its first byte is at {off:#x}")
            if kind == "header":
                headers[name] = (off, immediate, plineno)
                order.append(name)
            else:
                if name in labels:
                    ck.fail(plineno, f"label {name} defined twice")
                labels[name], label_line[name] = off, plineno
        pending = []
    return regions, sysvars, labels, headers, order


def instruction(lineno, off, data, comment, routine, labels, sysvars, headers, size, ck):
    """GNU as text for one instruction line, after its notes are checked."""
    insn = comment.split(";", 1)[0].strip()
    after = comment.split(";", 1)[1] if ";" in comment else ""
    end = off + len(data)
    if not insn:
        ck.fail(lineno, "byte line without an instruction comment")
        return None
    rel = REL.search(insn)
    if rel:
        insn = REL.sub("", insn).strip()
    hdr = re.search(r"\((\S+) header\)", insn)
    if hdr:
        insn = insn[:hdr.start()].strip()
    if "(" in insn or ")" in insn:
        ck.fail(lineno, f"unrecognised note in instruction: {comment}")
        return None
    mnemonic, _, operands = insn.partition(" ")
    ops = [o.strip() for o in operands.split(",")] if operands else []
    target = None
    if mnemonic in ("call", "jmp") or (mnemonic.startswith("j") and mnemonic != "jmp"):
        if ops and not ops[0] in ("rax",):
            name = ops[0]
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
    text = re.sub(r"\b(byte|word|dword|qword) \[", r"\1 ptr [", text)
    movabs = "(movabs)" in after
    if movabs:
        if not re.fullmatch(r"mov r\w+, \S+", text):
            ck.fail(lineno, f"movabs applies to mov r64, imm only: {text}")
        text = "movabs" + text[3:]
    return text


MAPPED = set()


def dictionary_field(lineno, data, comment, state, headers, order, ck):
    """.byte/.quad for one dictionary header field; checks its comment."""
    name, idx = state["header"], state["field"]
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
        ck.expect(len(stated) == state["nlen"], lineno, "dict-field",
                  f"nlen {state['nlen']}, name is {len(stated)} bytes")
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
    """(defined symbol values, undefined names, relocation count) of an ELF64 object."""
    data = path.read_bytes()
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    sh = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize) for i in range(shnum)]
    def name(off, table):
        start = sh[table][4] + off
        return data[start:data.index(b"\0", start)].decode()
    names = [name(s[0], shstrndx) for s in sh]
    text = next(i for i, n in enumerate(names) if n == ".text")
    symtab = next(i for i, s in enumerate(sh) if s[1] == 2)
    syms, undefined = {}, []
    for k in range(1, sh[symtab][5] // 24):
        st_name, info, other, shndx, value, size = struct.unpack_from(
            "<IBBHQQ", data, sh[symtab][4] + 24 * k)
        n = name(st_name, sh[symtab][6])
        if shndx == 0 and n:
            undefined.append(n)
        elif shndx == text and n:
            syms[n] = value
    relocs = sum(s[5] // 24 for s in sh if s[1] == 4)
    content = data[sh[text][4]:sh[text][4] + sh[text][5]]
    return content, syms, undefined, relocs


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--as", dest="assembler", default="as")
    ap.add_argument("--keep", help="also write the generated assembler source here")
    ap.add_argument("seed", nargs="?", default=str(ROOT / "seed/000-seed.hex0"))
    args = ap.parse_args()
    ck = Check()
    rows, size = read_lines(pathlib.Path(args.seed))
    regions, sysvars, labels, headers, order = build(rows, size, ck)
    MAPPED.update(regions)
    MAPPED.update(sysvars.values())

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
    elf_lines = {r[0] for r in byte_rows[:n_elf]}
    for row in rows:
        lineno, off, data, text = row[:4]
        if off is None:
            if len(row) == 5:
                _, kind, name, _, _ = row[4]
                if kind == "header":
                    state = {"header": name, "field": 0}
                    out.append(f"# header {name}")
                else:
                    if kind == "routine":
                        routine = name
                        if state and state["field"] != 4:
                            ck.fail(lineno, f"header {state['header']} has {state['field']} of 4 fields")
                        if state:
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
        else:
            line = instruction(lineno, off, data, text, routine, labels, sysvars,
                               headers, size, ck)
            kinds[lineno] = "insn"
            if line and "[LATEST]," in line.replace(" ", "").replace("ptr", "") and latest_init is None:
                latest_init = (lineno, number(line.rsplit(",", 1)[1]))
        if line is None:               # rejected and reported; keep later offsets
            line = raw(data)
            kinds[lineno] = "rejected"
        out += [f"line{lineno}:", "    " + line]
    source = "\n".join(out) + "\n"
    if args.keep:
        pathlib.Path(args.keep).write_text(source)

    # The dictionary chain from LATEST's initial value.
    if latest_init is None:
        ck.fail(0, "no mov qword [LATEST], imm in sysvar_init")
    else:
        by_addr = {BASE + off: n for n, (off, _, _) in headers.items()}
        seen, addr, links = [], latest_init[1], {}
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

    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        (tmp / "seed.S").write_text(source)
        obj = tmp / "seed.o"
        run = subprocess.run([args.assembler, "--64", str(tmp / "seed.S"), "-o", str(obj)],
                             capture_output=True, text=True)
        if run.returncode:
            src = {}
            for n, l in enumerate(out, 1):
                m = re.fullmatch(r"line(\d+):", l)
                if m:
                    src[n + 1] = m.group(1)
            print(re.sub(r"^.*?seed\.S:(\d+):", lambda m: f"seed line {src.get(int(m.group(1)), '?')}:",
                         run.stderr, flags=re.M), end="")
            sys.exit(f"seed asm-check: {args.assembler} failed on the comments "
                     "(its messages name lines of the generated source; --keep writes it)")
        text, syms, undefined, relocs = elf_symbols(obj)
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
    built = ROOT / "seed-forth"
    if built.exists() and pathlib.Path(args.seed).resolve() == (ROOT / "seed/000-seed.hex0").resolve():
        ck.expect(built.read_bytes() == image, 0, "image", "this parse of the hex differs from ./seed-forth")

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
    print(f"  {lines_by_kind['insn']} instructions ({totals['insn']} bytes), "
          f"{lines_by_kind['elf']} ELF fields ({totals['elf']} bytes), "
          f"{lines_by_kind['dict']} dictionary fields in {len(headers)} headers ({totals['dict']} bytes)")
    print(f"  {c.get('rel-note', 0)} branch-note checks, {c.get('heading-address', 0)} heading addresses, "
          f"{len(labels)} labels, {c.get('address-note', 0)} address operands, "
          f"{c.get('memory-map', 0)} memory-map checks, {c.get('elf-note', 0)} ELF notes, "
          f"{c.get('chain', 0)} chain walk")


if __name__ == "__main__":
    main()
