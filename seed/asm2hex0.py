#!/usr/bin/env python3
"""Write seed/000-seed.hex0 from seed/seed.asm.

000-seed.hex0 is what gets built: stage0's hex0-seed turns it into
seed-forth with no other tool.  seed.asm is the same program as NASM
source, where offsets, links and branch distances are labels instead of
numbers; this script runs nasm for the bytes and writes them out one
instruction or field per line, each with its source text as the comment,
in the form tests/seed/asm-check.py reads back and assembles with GNU as.
seed/check.sh proves the two files agree.

What it adds to each source line:
  - a label line becomes a heading with the label's file offset
    (";; ----- NAME @ 0xNNN  text -----"); a local label becomes ";; .x:";
  - HEADER NAME, "name", FLAGS becomes ";; --- name @ 0xNNN --- header"
    and its four fields, with the link's value and whose header it is;
  - a branch or call to a label gets "(relN = target - next)", both as
    file offsets;
  - a label used as a value (mov edi, lit_code) is written as its address;
  - "?" in an ELF field's comment becomes the field's value.
";;" comment lines are copied as they are; ";" lines, equ, %macro and the
directives are not copied.

Usage: seed/asm2hex0.py [seed.asm [000-seed.hex0]]   (needs nasm)
"""
import os, pathlib, re, subprocess, sys, tempfile

ORG = 0x400000
HERE = pathlib.Path(__file__).resolve().parent


def assemble(src):
    """nasm's bytes for src, and per source line the (offset, length) runs."""
    with tempfile.TemporaryDirectory() as t:
        lst, binf = os.path.join(t, "l"), os.path.join(t, "b")
        subprocess.run(["nasm", "-f", "bin", "-l", lst, "-o", binf, str(src)], check=True)
        image = pathlib.Path(binf).read_bytes()
        listing = pathlib.Path(lst).read_text().splitlines()
    # A listing row: line number, then (offset, hex bytes, "-" if the bytes
    # continue on the next row, "<rep Nh>" for times N), "<1>" on a row of
    # a macro's expansion (numbered by the macro's own lines), the text.
    row = re.compile(r"^\s*(\d+) (?:([0-9A-F]{8}) ([0-9A-F\[\]()]+)(-?)(<rep [0-9A-F]+h>)?)?\s*(<\d+>)?\s?(.*)$")
    runs, cont, invoked = {}, False, None
    for line in listing:
        m = row.match(line)
        if not m:
            continue
        if not m.group(6):
            invoked = int(m.group(1))       # a source line; a macro's rows follow it
        if m.group(2) is None:
            cont = False
            continue
        off = int(m.group(2), 16)
        n = len(re.sub(r"[\[\]()]", "", m.group(3))) // 2
        if m.group(5):
            n *= int(m.group(5)[5:-2], 16)  # times N db ...
        if cont:
            runs[invoked][-1][1] += n
        else:
            runs.setdefault(invoked, []).append([off, n])
        cont = bool(m.group(4))
    return image, runs


def main():
    src = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "seed.asm"
    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else HERE / "000-seed.hex0"
    image, runs = assemble(src)
    source = src.read_text().splitlines()

    # First pass: every label's offset (that of the next byte), and the
    # dictionary name each HEADER gives its hdr_ label.
    labels, names, pending, scope = {}, {}, [], None
    for num, line in enumerate(source, 1):
        m = re.match(r"\s*([.\w]+):", line)
        h = re.match(r"\s*HEADER\s+(\w+),\s*\"(.*)\",\s*(\d+)", line)
        if h:
            pending.append("hdr_" + h.group(1))
            names["hdr_" + h.group(1)] = h.group(2)
        elif m and not line.lstrip().startswith(("%", ";")):
            name = m.group(1)
            if not name.startswith("."):
                scope = name
            pending.append(name if not name.startswith(".") else scope + name)
        if num in runs and not line.lstrip().startswith("%"):
            for name in pending:
                labels[name] = runs[num][0][0]
            pending = []
    for name in pending:
        labels[name] = len(image)
    by_offset = {off: names[n] for n, off in labels.items() if n in names}

    lines = []

    def emit(data, comment):
        lines.append(f"{' '.join(f'{b:02X}' for b in data):<42}; {comment}".rstrip())

    scope = None
    for num, line in enumerate(source, 1):
        text = line.strip()
        if text.startswith(";;"):
            lines.append(text)
            continue
        if not text:
            if lines and lines[-1] != "":
                lines.append("")
            continue
        if text.startswith((";", "%")) or re.match(r"(bits|org)\b|\w+\s+equ\b|hdr_%1:|dq LINK|db %", text):
            continue
        h = re.match(r"HEADER\s+(\w+),\s*\"(.*)\",\s*(\d+)", text)
        if h:
            name, flags = h.group(2), int(h.group(3))
            (lo, _), (fo, _), (no, _), (so, sn) = runs[num]
            lines.append(f";; --- {name} @ 0x{lo:03X} --- header" + ("  IMMEDIATE" if flags else ""))
            link = int.from_bytes(image[lo:lo + 8], "little")
            emit(image[lo:lo + 8], f"link  = 0x{link:X} ({by_offset[link - ORG]})" if link
                 else "link  = 0 (end of chain)")
            emit(image[fo:fo + 1], "flags = 1 (IMMEDIATE)" if flags else "flags = 0")
            emit(image[no:no + 1], f"nlen  = {image[no]}")
            emit(image[so:so + sn], f'name  = "{name}"')
            continue
        m = re.match(r"([.\w]+):\s*(?:;\s*(.*))?$", text)
        if m:
            name, desc = m.group(1), m.group(2)
            if name.startswith("."):
                lines.append(f";; {name}:")
            elif name != "file_end":
                scope = name
                lines.append(f";; ----- {name} @ 0x{labels[name]:03X}" + (f"  {desc}" if desc else "") + " -----")
            continue
        (off, n), = runs[num]
        data = image[off:off + n]
        code, _, note = text.partition(";")
        code, note = " ".join(code.split()), note.strip()
        if re.match(r"(db|dw|dd|dq|times)\b", code):          # an ELF field
            value = int.from_bytes(data, "little")
            emit(data, note.replace("?", f"0x{value:X}" if "e_entry" in note else str(value)))
            continue
        mnemonic, _, operands = code.partition(" ")
        ops = [o.strip() for o in operands.split(",")] if operands else []
        if (mnemonic == "call" or mnemonic.startswith("j")) and ops[0] != "rax":
            target = labels[scope + ops[0] if ops[0].startswith(".") else ops[0]]
            width = 8 if n == 2 else 32
            code += f"  (rel{width} = 0x{target:03X} - 0x{off + n:03X})"
        else:
            for i, op in enumerate(ops):
                if op in names:
                    ops[i] = f"0x{ORG + labels[op]:X} ({names[op]} header)"
                elif op in labels:
                    ops[i] = f"0x{ORG + labels[op]:X}"
            code = mnemonic + (" " + ", ".join(ops) if ops else "")
        emit(data, f"{code:<28} ; {note}" if note else code)

    text = re.sub(r"\n{3,}", "\n\n", "\n".join(lines).strip("\n")) + "\n"
    out.write_text(text)
    print(f"asm2hex0: {out} written, {len(image)} bytes")


if __name__ == "__main__":
    main()
