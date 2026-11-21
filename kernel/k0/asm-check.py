#!/usr/bin/env python3
"""Check kernel/k0/k0.hex0's comments against its bytes: every byte line
carries the instruction or data field it encodes as a ';' comment, and GNU
as (and LLVM's llvm-mc, when installed), given only the comments, must
write the same bytes.

  python3 kernel/k0/asm-check.py [--as AS] [--llvm-mc LLVM_MC] [--keep FILE.S] [K0.HEX0]
                                                  (from the repository root)

This is the same method as tests/seed/asm-check.py, for K0's shape: a
multiboot image with 32-bit and 64-bit code, a constants block, and no ELF
header or dictionary.

How the bytes are read: hex0's own rules (text after ';' or '#' is
dropped, the rest is pairs of hex digits), one line at a time, so each
line has a file offset and a length.  K0 loads at 0x100000, so offset N is
address 0x100000 + N.

Verified:
  - Every byte line is one instruction or one data field.  The text after
    the first ';' (up to the next ';', notes taken out) goes into one
    .intel_syntax noprefix source, every line in file order, so as gives
    each line the offset the hex gives it; its bytes must equal the
    line's hex.  The object must have no relocations and no undefined
    symbols, and as must write exactly the file's size.
  - Code mode: ";; ===== bits 32 ..." and ";; ===== bits 64 ..." lines
    switch the mode (.code32, .code64) for the lines that follow, so each
    instruction is assembled as the CPU runs it.  The file must start
    with a mode line.
  - Constants: ";;   NAME = VALUE" lines (VALUE a decimal or 0x number)
    become .equ NAME, VALUE, and the instructions use the names.  as sees
    only the stated value, so a wrong value gives different bytes.
  - Data: "db/dw/dd/dq EXPR" becomes .byte/.short/.long/.quad EXPR.  EXPR
    may name labels (sctab's "dw sys_read - handlers").
  - Labels: ";; ----- NAME @ 0xNNN" headings name a routine at NNN, and
    ";; .x @ 0xNNN" lines a label inside the last routine (symbol NAME.x).
    The stated address must equal the offset of the next byte line.
  - Branch notes "(relN = A - B)": A must be the label the instruction
    names, B the offset just past the line, N the width of the
    displacement as written, and A - B that displacement.  A branch or
    call to a label without a note fails.
  - "(NAME)" after an operand: some literal in the instruction must be
    0x100000 plus NAME's offset.  Any other literal inside the image
    (0x100000 to 0x100000 + file size) must carry such a note.
  - Rewrites from the comments' NASM spelling to GNU as, and nothing
    else: "byte/word/dword/qword [" becomes "... ptr [", and a label
    operand of a branch becomes its scoped symbol.
  - Every ";;" line that looks like a heading or label (it has " @ 0x",
    starts with ";; -----", or is ";; .x" alone) must match a pattern
    above; one that does not fails rather than being read as prose.
  - The two assemblers must agree on every byte, with one exception:
    "xchg r, r" is symmetric, and as and llvm-mc put its two registers in
    opposite ModRM fields, so there llvm-mc's bytes may be as's with the
    reg and r/m fields swapped (the same instruction).

Not verified:
  - Prose: other ";;" lines, and the second ';' note on an instruction
    line (what a register holds, why).  They describe behaviour; running
    K0 (the TinyCC hand-off, the K1 smoke test) tests behaviour.
  - Which of several valid encodings a comment means: the check accepts
    the one GNU as picks, so a comment is proved to name an instruction
    that encodes as the bytes.
"""
import argparse, pathlib, re, shutil, struct, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASE = 0x100000

HEX_LINE = re.compile(r"^((?:[0-9A-Fa-f]{2}\s*)+)(?:[;#](.*))?$")
MODE = re.compile(r"^;; ===== bits (32|64)\b")
CONST = re.compile(r"^;;\s+([A-Z][A-Z0-9_]*) = (-?0x[0-9A-Fa-f]+|-?\d+)\b")
HEAD = re.compile(r"^;; ----- (\S+) @ 0x([0-9A-F]+)\b")
LOCAL = re.compile(r"^;; (\.[a-z0-9_]+) @ 0x([0-9A-F]+)$")
REL = re.compile(r"\(rel(8|32) = 0x([0-9A-F]+) - 0x([0-9A-F]+)\)")
ADDR = re.compile(r"\(([a-z_][a-z0-9_]*)\)")
DATA = {"db": ".byte", "dw": ".short", "dd": ".long", "dq": ".quad"}


class Check:
    def __init__(self):
        self.failures, self.counts = [], {}

    def expect(self, cond, lineno, kind, msg):
        if cond:
            self.counts[kind] = self.counts.get(kind, 0) + 1
        else:
            self.failures.append(f"line {lineno}: {msg}")


def read_lines(path):
    """(lineno, offset, bytes, comment): offset None for non-byte lines."""
    rows, offset = [], 0
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        s = line.strip()
        m = HEX_LINE.match(s)
        if not s or s.startswith((";", "#")) or not m:
            if s and not s.startswith((";", "#")):
                sys.exit(f"k0 asm-check: line {lineno} is neither bytes nor a comment: {line}")
            rows.append((lineno, None, None, s))
            continue
        data = bytes.fromhex(m.group(1))
        rows.append((lineno, offset, data, (m.group(2) or "").strip()))
        offset += len(data)
    return rows, offset


def labels_of(rows, ck):
    """Label offsets from headings and local labels, checked against the bytes."""
    labels, pending, routine = {}, [], None
    for lineno, off, data, text in rows:
        if off is None:
            m = HEAD.match(text)
            if m:
                routine = m.group(1)
                pending.append((lineno, routine, int(m.group(2), 16)))
                continue
            m = LOCAL.match(text)
            if m:
                if routine is None:
                    ck.expect(False, lineno, "label", f"local label {m.group(1)} before any routine")
                pending.append((lineno, f"{routine}{m.group(1)}", int(m.group(2), 16)))
                continue
            if (" @ 0x" in text or text.startswith(";; -----")
                    or re.fullmatch(r";;\s*\.\w*:?", text)):
                ck.expect(False, lineno, "label", f"a heading or label the check cannot read: {text}")
            continue
        for plineno, name, stated in pending:
            ck.expect(stated == off, plineno, "label",
                      f"{name} stated at {stated:#x}, its first byte is at {off:#x}")
            ck.expect(name not in labels, plineno, "label", f"label {name} defined twice")
            labels[name] = off
        pending = []
    for plineno, name, stated in pending:      # labels after the last byte (file_end)
        ck.expect(stated == offset_end(rows), plineno, "label",
                  f"{name} stated at {stated:#x}, the file ends at {offset_end(rows):#x}")
        labels[name] = offset_end(rows)
    return labels


def offset_end(rows):
    last = [r for r in rows if r[1] is not None][-1]
    return last[1] + len(last[2])


def translate(lineno, off, data, comment, routine, labels, size, ck):
    """GNU as text for one byte line, after its notes are checked."""
    insn = comment.split(";", 1)[0].strip()
    if not insn:
        ck.expect(False, lineno, "line", "byte line without an instruction or data comment")
        return None
    end = off + len(data)
    rel = REL.search(insn)
    if rel:
        insn = REL.sub("", insn).strip()
    notes = ADDR.findall(insn)
    insn = ADDR.sub("", insn).strip()
    if "(" in insn or ")" in insn:
        ck.expect(False, lineno, "note", f"unrecognised note in: {comment}")
        return None
    mnemonic, _, operands = insn.partition(" ")
    literals = [int(t, 0) for t in re.findall(r"(?<![\w.])(0x[0-9A-Fa-f]+|\d+)\b", insn)]
    for name in notes:
        ck.expect(name in labels and BASE + labels[name] in literals, lineno, "address-note",
                  f"({name}): no literal equals its address {BASE + labels.get(name, 0):#x}")
    for v in literals:
        if BASE <= v < BASE + size:
            ck.expect(any(BASE + labels.get(n, -1) == v for n in notes), lineno, "address-note",
                      f"literal {v:#x} is inside the image but carries no (label) note")
    if mnemonic in DATA:
        if rel:
            ck.expect(False, lineno, "rel-note", "rel note on a data line")
        ck.counts["data"] = ck.counts.get("data", 0) + 1
        return f"{DATA[mnemonic]} {operands.strip()}"
    ops = [o.strip() for o in operands.split(",")] if operands else []
    is_branch = mnemonic in ("call", "jmp", "loop", "jrcxz") or (mnemonic.startswith("j") and mnemonic != "jmp")
    if is_branch and ops and re.fullmatch(r"\.?[a-z_][a-z0-9_]*", ops[0]) \
            and ops[0] not in ("rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp"):
        name = ops[0]
        target = f"{routine}{name}" if name.startswith(".") else name
        if target not in labels:
            ck.expect(False, lineno, "rel-note", f"branch to unknown label {name}")
            return None
        if not rel:
            ck.expect(False, lineno, "rel-note", f"branch to {name} without a (relN = A - B) note")
        else:
            width, a, b = int(rel.group(1)), int(rel.group(2), 16), int(rel.group(3), 16)
            disp = int.from_bytes(data[-width // 8:], "little", signed=True)
            ck.expect(a == labels[target], lineno, "rel-note",
                      f"note's target {a:#x}, {name} is at {labels[target]:#x}")
            ck.expect(b == end, lineno, "rel-note", f"note's origin {b:#x}, the line ends at {end:#x}")
            ck.expect(disp == a - b, lineno, "rel-note",
                      f"rel{width} in the bytes is {disp:#x}, note says {a - b:#x}")
        ops[0] = target
    elif rel:
        ck.expect(False, lineno, "rel-note", f"rel note on a non-branch: {comment}")
    text = mnemonic + (" " + ", ".join(ops) if ops else "")
    text = re.sub(r"\b(byte|word|dword|qword) \[", r"\1 ptr [", text)
    ck.counts["insn"] = ck.counts.get("insn", 0) + 1
    return text


def xchg_swapped(comment, a, b):
    """xchg r, r is symmetric, and as and llvm-mc put the two registers in
    opposite ModRM fields: accept b when it is a with reg and r/m swapped."""
    insn = comment.split(";", 1)[0].split()
    if not insn or insn[0] != "xchg" or len(a) != len(b) or a[:-1] != b[:-1]:
        return False
    m, n = a[-1], b[-1]
    return m >> 6 == 3 and n >> 6 == 3 and (m >> 3) & 7 == n & 7 and m & 7 == (n >> 3) & 7


def section_text(path):
    """(.text bytes, defined symbols, undefined names, relocation count) of an ELF64 object."""
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
        st_name, info, other, shndx, value, size = struct.unpack_from("<IBBHQQ", data, sh[symtab][4] + 24 * k)
        n = name(st_name, sh[symtab][6])
        if shndx == 0 and n:
            undefined.append(n)
        elif shndx == text and n:
            syms[n] = value
    relocs = sum(s[5] // 24 for s in sh if s[1] == 4)
    return data[sh[text][4]:sh[text][4] + sh[text][5]], syms, undefined, relocs


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--as", dest="assembler", default="as")
    ap.add_argument("--llvm-mc", dest="llvm_mc", default="llvm-mc",
                    help="second, independent assembler; skipped if not installed")
    ap.add_argument("--keep", help="also write the generated assembler source here")
    ap.add_argument("hex0", nargs="?", default=str(ROOT / "kernel/k0/k0.hex0"))
    args = ap.parse_args()
    ck = Check()
    rows, size = read_lines(pathlib.Path(args.hex0))
    labels = labels_of(rows, ck)
    out = [".intel_syntax noprefix", ".text"]
    routine, mode, byte_rows = None, None, []
    for lineno, off, data, text in rows:
        if off is None:
            m = MODE.match(text)
            if m:
                mode = m.group(1)
                out.append(f".code{mode}")
            m = CONST.match(text)
            if m:
                out.append(f".equ {m.group(1)}, {m.group(2)}")
                ck.counts["constant"] = ck.counts.get("constant", 0) + 1
            m = HEAD.match(text)
            if m:
                routine = m.group(1)
                out.append(f"{routine}:")
            m = LOCAL.match(text)
            if m:
                out.append(f"{routine}{m.group(1)}:")
            continue
        if mode is None:
            ck.expect(False, lineno, "mode", "byte line before any ';; ===== bits NN' line")
            mode = "32"
        line = translate(lineno, off, data, text, routine, labels, size, ck)
        if line is None:
            line = ".byte " + ", ".join(f"0x{b:02x}" for b in data)
        byte_rows.append((lineno, off, data, text))
        out += [f"line{lineno}:", "    " + line]
    source = "\n".join(out) + "\n"
    if args.keep:
        pathlib.Path(args.keep).write_text(source)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        (tmp / "k0.S").write_text(source)
        run = subprocess.run([args.assembler, "--64", str(tmp / "k0.S"), "-o", str(tmp / "k0.o")],
                             capture_output=True, text=True)
        if run.returncode:
            print(run.stderr, end="")
            sys.exit(f"k0 asm-check: {args.assembler} failed on the comments (--keep writes the source)")
        text, syms, undefined, relocs = section_text(tmp / "k0.o")
        llvm = None
        if shutil.which(args.llvm_mc):
            lrun = subprocess.run([args.llvm_mc, "-triple=x86_64-unknown-linux-gnu", "-filetype=obj",
                                   "-o", str(tmp / "k0-llvm.o"), str(tmp / "k0.S")],
                                  capture_output=True, text=True)
            if lrun.returncode:
                print(lrun.stderr, end="")
                sys.exit(f"k0 asm-check: {args.llvm_mc} failed on the comments")
            llvm = section_text(tmp / "k0-llvm.o")[0]
    ck.expect(not undefined, 0, "object", f"undefined symbols in the comments: {', '.join(undefined)}")
    ck.expect(not relocs, 0, "object", f"{relocs} relocations: an operand did not resolve to a constant")
    ck.expect(len(text) == size, 0, "object", f"as wrote {len(text)} bytes, the hex is {size}")
    shifted = False
    for lineno, off, data, comment in byte_rows:
        sym = syms.get(f"line{lineno}")
        if sym != off:
            if not shifted:
                ck.expect(False, lineno, "bytes", f"as places this line at {sym}, the hex at {off:#x}"
                          " (an earlier comment assembles to a different length)")
            shifted = True
            continue
        got = text[off:off + len(data)]
        ck.expect(got == data, lineno, "bytes",
                  f"{comment.split(';')[0].strip()}: hex {data.hex(' ')}, as writes {got.hex(' ')}")
        if llvm is not None:
            lgot = llvm[off:off + len(data)]
            if lgot != got and xchg_swapped(comment, got, lgot):
                ck.counts["xchg"] = ck.counts.get("xchg", 0) + 1
                continue
            ck.expect(lgot == got, lineno, "llvm",
                      f"{comment.split(';')[0].strip()}: as writes {got.hex(' ')}, llvm-mc writes {lgot.hex(' ')}")
    if llvm is not None:
        ck.expect(len(llvm) == len(text), 0, "llvm", f"llvm-mc wrote {len(llvm)} bytes, as {len(text)}")

    if ck.failures:
        for f in ck.failures[:40]:
            print(f"k0 asm-check: FAIL {f}")
        sys.exit(f"k0 asm-check: {len(ck.failures)} mismatches between comments and bytes")
    c = ck.counts
    shown = pathlib.Path(args.hex0).resolve()
    shown = shown.relative_to(ROOT) if shown.is_relative_to(ROOT) else shown
    print(f"k0 asm-check: {shown}'s bytes equal {args.assembler} on its comments: {len(text)} of {size} bytes")
    if llvm is not None:
        print(f"k0 asm-check: and {args.llvm_mc} on the same comments writes the same {len(llvm)} bytes")
    else:
        print(f"k0 asm-check: {args.llvm_mc} not found; the second assembler was skipped")
    print(f"  {c.get('insn', 0)} instructions, {c.get('data', 0)} data fields, {c.get('constant', 0)} constants, "
          f"{len(labels)} labels, {c.get('rel-note', 0)} branch-note checks, {c.get('address-note', 0)} address notes")


if __name__ == "__main__":
    main()
