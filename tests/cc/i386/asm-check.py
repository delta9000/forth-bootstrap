#!/usr/bin/env python3
"""Check the i386 encoders against an assembler: every byte line of
cc/090-cc-emit.fth, 117-cc-native-program.fth and 119-cc-runtime.fth
carries its instruction as a comment, and GNU as must assemble that
comment to those bytes.

  python3 tests/cc/i386/asm-check.py            (from the repository root)

An instruction is the x{ ... } bytes up to its comment, which may span
lines.  Bytes the Forth computes are not compared, only counted:
cc-emit-4le is four (the comment says imm32, or an offset from esp), a
cc-emit-byte is one, cc-emit-half-ea is its ModR/M byte, given as $hh, and
a disp8 (the comment says [ebp+disp]).  `if, $aa else, $bb then,` selects
between the two instructions a comment names as "movzx/movsx"; "setX"
stands for any setcc, and "+N" for a branch over the next N bytes.
Requires GNU as and objcopy (binutils).
"""
import pathlib, re, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
FILES = ["090-cc-emit.fth", "117-cc-native-program.fth", "119-cc-runtime.fth"]


def items(code):
    """The bytes a piece of Forth emits: ints, None for a computed byte, or
    a tuple of two alternatives."""
    out = []
    tokens = code.split()
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t == "x{":
            i += 1
            while tokens[i] != "}":
                out.append(int(tokens[i], 16))
                i += 1
        elif t == "if," and tokens[i + 2:i + 5:2] == ["else,", "then,"]:
            out.append((int(tokens[i + 1][1:], 16), int(tokens[i + 3][1:], 16)))
            i += 5                      # the cc-emit-byte that follows
        elif t == "cc-emit-4le":
            out += [None] * 4
        elif t == "cc-emit-byte":
            out.append(None)
        elif t == "cc-emit-half-ea":
            out += [int(tokens[i - 1][1:], 16), None]
        i += 1
    return out


def instructions(path):
    """Yield (line number, items, comment) for each commented instruction."""
    pending = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if line.startswith("\\"):
            continue
        m = re.match(r"(.*?)\s\\ (.*)$", line)
        code, comment = (m.group(1), m.group(2)) if m else (line, None)
        if "x{" not in code and not pending:
            continue
        if re.match(r"\s*:", code) and "x{" not in code:
            continue
        pending += items(code)
        if comment:
            yield n, pending, comment
            pending = []
    assert not pending, f"{path}: bytes without an instruction comment at the end"


def variants(comment):
    """The assembler lines a comment stands for."""
    text = re.sub(r"\s\s\(.*\)$", "", comment).strip()
    text = text.replace("setX", "sete").replace("0 or -1", "0")
    text = re.sub(r"\bimm32\b|\bn\*8\b", "0x12345678", text)
    text = re.sub(r"\[esp\+(off1|off2|0x12345678)\]", "[esp+0x12345678]", text)
    text = re.sub(r"\[ebp\+disp(\+4)?\]", "[ebp-16]", text)
    text = re.sub(r"\b(byte|word|dword) \[", r"\1 ptr [", text)
    m = re.match(r"(j\w+) \+(\d+)$", text)
    if m:
        text = f"{m.group(1)} .+{int(m.group(2)) + 2}"
    m = re.match(r"(\w+)/(\w+) (.*)$", text)
    return [f"{m.group(1)} {m.group(3)}", f"{m.group(2)} {m.group(3)}"] if m else [text]


def assemble(text, tmp):
    src = pathlib.Path(tmp, "i.s")
    src.write_text(f".intel_syntax noprefix\n{text}\n")
    subprocess.run(["as", "--32", "-o", f"{tmp}/i.o", str(src)], check=True)
    subprocess.run(["objcopy", "-O", "binary", "-j", ".text", f"{tmp}/i.o", f"{tmp}/i.bin"], check=True)
    return pathlib.Path(tmp, "i.bin").read_bytes()


def main():
    bad = count = 0
    with tempfile.TemporaryDirectory() as tmp:
        for name in FILES:
            path = ROOT / "cc" / name
            for n, want, comment in instructions(path):
                for k, text in enumerate(variants(comment)):
                    count += 1
                    expect = [w[k] if isinstance(w, tuple) else w for w in want]
                    got = assemble(text, tmp)
                    if len(got) != len(expect) or any(e is not None and e != g for e, g in zip(expect, got)):
                        bad += 1
                        show = " ".join("??" if e is None else f"{e:02x}" for e in expect)
                        print(f"cc/{name}:{n}: {text}: the file has {show}, as gives {got.hex(' ')}")
    if bad:
        sys.exit(f"asm-check: FAIL: {bad} of {count} instructions differ")
    print(f"asm-check: OK, {count} instructions in cc/ equal GNU as on their comments")


main()
