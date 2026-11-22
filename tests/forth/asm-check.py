#!/usr/bin/env python3
"""Check the i386 host's machine code against an assembler: every line of
forth/*.fth that lays bytes carries its instruction as a comment, and
GNU as in 32-bit mode must assemble that comment to those bytes.  With
llvm-mc installed, LLVM's assembler must write the same bytes too.

  python3 tests/forth/asm-check.py         (from the repository root)

This is the Forth system's own code, which the processor runs while the
compiler compiles; tests/cc/asm-check.py checks cc/, the code of
the compiled program.

A byte line has one of two forms, and holds one instruction:

    c{ 8b 56 04 }                    \\ mov edx, [esi+4]
    137 c, 86 c, 4 c,                \\ 89 56 04  mov [esi+4], edx

The second is forth/010-lib.fth's before c{ exists: the bytes in
decimal, and in the comment the same bytes in hex ahead of the
instruction.  Both spellings are compared.  A note in parentheses after
two spaces is not part of the instruction.

Bytes the Forth computes are counted, not compared: a `,4` is four (the
comment says imm32 or rel32) and a `c,` after `c{ }` is one (imm8).  A
line that has c{ or `N c,` outside a comment and no instruction fails.
Requires GNU as and objcopy (binutils).
"""
import pathlib, re, shutil, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
FILES = sorted((ROOT / "forth").glob("*.fth"))


def byte_lines(path):
    """Yield (line number, fixed bytes, computed count, comment) for each
    line that lays bytes."""
    for n, line in enumerate(path.read_text().splitlines(), 1):
        if line.startswith("\\"):
            continue
        m = re.match(r"(.*?)\s\\ (.*)$", line)
        code, comment = (m.group(1), m.group(2)) if m else (line, "")
        tokens = code.split()
        if "c{" in tokens and ":" not in tokens[:tokens.index("c{")][-1:]:
            i = tokens.index("c{")
            j = tokens.index("}", i)
            fixed = bytes(int(t, 16) for t in tokens[i + 1:j])
            rest = tokens[j + 1:]
            assert "c{" not in rest, f"{path.name}:{n}: two c{{ }} on one line"
            yield n, fixed, 4 * rest.count(",4") + rest.count("c,"), comment
        elif re.search(r"(^|\s)\d+ c,", code):
            fixed = bytes(int(a) for a, b in zip(tokens, tokens[1:]) if b == "c," and a.isdigit())
            m = re.match(r"((?:[0-9A-F]{2} )+) (.*)$", comment)
            if not m or bytes.fromhex(m.group(1)) != fixed:
                yield n, fixed, 0, None            # the hex does not restate the decimal
                continue
            yield n, fixed, 4 * tokens.count(",4"), m.group(2)


def assembler_text(comment):
    """The assembler line a comment stands for."""
    text = re.sub(r"\s\s\(.*\)$", "", comment).strip()
    text = re.sub(r"\bimm32\b", "0x12345678", text)
    text = re.sub(r"\bimm8\b", "0x12", text)
    text = re.sub(r"\brel32\b", "elsewhere", text)       # undefined: a rel32 to relocate
    return re.sub(r"\bbyte \[", "byte ptr [", text)


def gnu_as(text, tmp):
    src = pathlib.Path(tmp, "i.s")
    src.write_text(f".intel_syntax noprefix\n{text}\n")
    if subprocess.run(["as", "--32", "-o", f"{tmp}/i.o", str(src)], capture_output=True).returncode:
        return None
    return text_section(tmp)


def llvm_mc(text, tmp):
    src = pathlib.Path(tmp, "i.s")
    src.write_text(f".intel_syntax noprefix\n{text}\n")
    if subprocess.run(["llvm-mc", "-triple=i386-unknown-linux-gnu", "-filetype=obj",
                       "-o", f"{tmp}/i.o", str(src)], capture_output=True).returncode:
        return None
    return text_section(tmp)


def text_section(tmp):
    subprocess.run(["objcopy", "-O", "binary", "-j", ".text", f"{tmp}/i.o", f"{tmp}/i.bin"], check=True)
    return pathlib.Path(tmp, "i.bin").read_bytes()


def main():
    assemblers = [("as", gnu_as)] + ([("llvm-mc", llvm_mc)] if shutil.which("llvm-mc") else [])
    bad = count = 0
    with tempfile.TemporaryDirectory() as tmp:
        for path in FILES:
            name = path.relative_to(ROOT)
            for n, fixed, computed, comment in byte_lines(path):
                count += 1
                if not comment:
                    bad += 1
                    print(f"{name}:{n}: {fixed.hex(' ')} has no instruction comment")
                    continue
                text = assembler_text(comment)
                for which, run in assemblers:
                    got = run(text, tmp)
                    if got is None or got[:len(fixed)] != fixed or len(got) != len(fixed) + computed:
                        bad += 1
                        show = fixed.hex(" ") + " ??" * computed
                        print(f"{name}:{n}: {text}: the file has {show}, "
                              f"{which} gives {got.hex(' ') if got is not None else 'an error'}")
    if bad:
        sys.exit(f"asm-check: FAIL: {bad} of {count} byte lines differ")
    second = "and llvm-mc" if len(assemblers) == 2 else "(llvm-mc not found; the second assembler was skipped)"
    print(f"asm-check: OK, {count} byte lines in forth equal GNU as {second} on their comments")


main()
