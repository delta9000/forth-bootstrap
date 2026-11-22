#!/usr/bin/env python3
"""tests/reference.py -- a second opinion on the expected values in the
seed's and the host primitives' tests.

    python3 -I tests/reference.py seed KIND FILE
    python3 -I tests/reference.py high-halves FILE

The tests of the seed (tests/seed/i386/test.sh) and of the host's
primitives (tests/forth/i386/high-halves.fth) compare what the seed
computes with values written in those files.  This program computes the
same values a second way: Python's integers, reduced modulo 2^64, under
the words' meanings as seed/i386/SPEC.md gives them (sections 7.1, 9.2
and 9.3) and as the comments of forth/i386/010-lib.fth give the
library's.  It shares no code with the seed and was not written from the
expected values.  It is not a Forth: it knows the words below, straight
line definitions, and memory a case wrote itself.  Anything else (token,
find, key, syscall6, the system variables, a return address used as data,
control flow) it declines.

seed KIND FILE: FILE is one case of test.sh without its two-line prelude;
KIND is "prelude" if the case had one (emit and die are then words) or
"same".  Writes what the seed must print to stdout and exits with the
seed's status; exits 125, with the reason on stderr, for a case it
declines.

high-halves FILE: runs the vectors; `same` compares the value computed
here with the value the file expects.  A line with if, while, or until,
is not computed.  Prints the count, and exits 1 if a value differs.
"""
import sys

CELL = 1 << 64                 # a cell is 64 bits
TRUE = CELL - 1                # a true flag: all 64 bits set
STATE = 0x08059000             # the address `state` pushes
DECLINED = 125


class Declined(Exception):
    """The case uses something this reference does not model."""


class Stop(Exception):
    """The program ended; args[0] is its exit status."""


class Machine:
    def __init__(self):
        self.stack = []        # the data stack
        self.rstack = []       # cells moved by >r
        self.floor = 0         # len(rstack) when the running definition began
        self.depth = 0         # how many definitions are running
        self.library = False   # high-halves: >r and r> also work when typed
        self.memory = {}       # address -> byte, only bytes the case stored
        self.output = bytearray()
        self.words = {}        # name -> Python function or list (a definition)
        self.differ = []       # high-halves: (line, computed, expected)
        self.compared = 0

    def pop(self):
        return self.stack.pop()

    def push(self, n):
        self.stack.append(n % CELL)

    def load(self, addr, count):
        if any(addr + i not in self.memory for i in range(count)):
            raise Declined(f"reads memory at {addr:#x} that the case did not store")
        return sum(self.memory[addr + i] << (8 * i) for i in range(count))

    def store(self, value, addr, count):
        if STATE <= addr < STATE + 400:
            raise Declined("stores into the seed's own variables")
        for i in range(count):
            self.memory[addr + i] = (value >> (8 * i)) & 255

    def run(self, word):
        """Run a Python word, or a definition: a list of words and numbers."""
        if callable(word):
            return word(self)
        outer, self.floor = self.floor, len(self.rstack)
        self.depth += 1
        for item in word:
            if isinstance(item, int):
                self.push(item)
            else:
                self.run(item)
        if len(self.rstack) != self.floor:
            raise Declined("a definition returns with its >r and r> unbalanced")
        self.floor = outer
        self.depth -= 1


def to_r(m):
    if m.depth == 0 and not m.library:
        raise Declined(">r from the outer loop")
    m.rstack.append(m.pop())


def r_from(m):
    if len(m.rstack) == m.floor or m.depth == 0 and not m.library:
        raise Declined("r> takes a return address")
    m.push(m.rstack.pop())


def binary(function):
    def word(m):
        b = m.pop()
        a = m.pop()
        m.push(function(a, b))
    return word


def unary(function):
    return lambda m: m.push(function(m.pop()))


def flag(condition):
    return TRUE if condition else 0


def negative(n):
    return n % CELL >= CELL // 2


def swap(m):
    b, a = m.pop(), m.pop()
    m.push(b)
    m.push(a)


def over(m):
    m.push(m.stack[-2])


def plus_store(sign):
    def word(m):
        addr, n = m.pop(), m.pop()
        m.store((m.load(addr, 8) + sign * n) % CELL, addr, 8)
    return word


# The seed's words of SPEC.md 7.1 and `state`.
SEED_WORDS = {
    "dup": lambda m: m.push(m.stack[-1]),
    "drop": lambda m: m.pop(),
    "swap": swap,
    ">r": to_r,
    "r>": r_from,
    "@": lambda m: m.push(m.load(m.pop(), 8)),
    "!": lambda m: m.store(m.stack.pop(-2), m.pop(), 8),
    "c@": lambda m: m.push(m.load(m.pop(), 1)),
    "c!": lambda m: m.store(m.stack.pop(-2), m.pop(), 1),
    "+": binary(lambda a, b: a + b),
    "*": binary(lambda a, b: a * b),
    "/": binary(lambda a, b: a // b),          # unsigned: both are 0 .. 2^64-1
    "nand": binary(lambda a, b: ~(a & b)),
    "0=": unary(lambda n: flag(n == 0)),
    "state": lambda m: m.push(STATE),
}
SEED_DECLINED = ["key", "token", "find", "syscall6"]

# The library's words that high-halves.fth uses, by their comments in
# forth/i386/010-lib.fth.  < is the sign of the difference.
LIBRARY_WORDS = {
    "-": binary(lambda a, b: a - b),
    "1+": unary(lambda n: n + 1),
    "1-": unary(lambda n: n - 1),
    "=": binary(lambda a, b: flag(a == b)),
    "<>": binary(lambda a, b: flag(a != b)),
    "0<": unary(lambda n: flag(negative(n))),
    "<": binary(lambda a, b: flag(negative(a - b))),
    ">": binary(lambda a, b: flag(negative(b - a))),
    "<=": binary(lambda a, b: flag(not negative(b - a))),
    ">=": binary(lambda a, b: flag(not negative(a - b))),
    "and": binary(lambda a, b: a & b),
    "or": binary(lambda a, b: a | b),
    "over": over,
    "r@": lambda m: m.push(m.rstack[-1]),
    "+!": plus_store(+1),
    "-!": plus_store(-1),
    "digit?": unary(lambda c: flag(48 <= c <= 57)),
    "alpha-lower?": unary(lambda c: flag(97 <= c <= 122)),
    "alpha-upper?": unary(lambda c: flag(65 <= c <= 90)),
}


def tokens(text):
    """The seed's tokens (SPEC.md 7.3) with their line numbers: bytes 1 to
    32 separate them, and the token \\ skips the rest of its line."""
    out = []
    for number, line in enumerate(text.split(b"\n"), 1):
        for byte in range(1, 33):
            line = line.replace(bytes([byte]), b" ")
        for token in line.split():
            if token == b"\\":
                break
            out.append((number, token.decode("latin-1")))
    return out


def interpret(m, text):
    """The outer loop (SPEC.md 9): a word runs or is compiled, a number is
    pushed or compiled, anything else is the fatal error."""
    m.compiling = None         # the definition being compiled, or None
    source = iter(tokens(text))
    for m.line, token in source:
        if len(token) > 255:
            raise Declined("a token of more than 255 bytes")
        if token in m.declined:
            raise Declined(f"uses {token}")
        if token == ":":
            name = next(source, (0, None))[1]
            if name is None:
                raise Declined(": at the end of the file")
            m.compiling = m.words[name] = []
        elif token == ";":
            if m.compiling is None:
                raise Declined("; outside a definition")
            m.compiling = None
        elif token in m.words:
            if m.compiling is not None:
                m.compiling.append(m.words[token])
            else:
                m.run(m.words[token])
        elif token.isascii() and token.isdigit():
            if m.compiling is not None:
                m.compiling.append(int(token) % CELL)
            else:
                m.push(int(token))
        else:
            m.output += token.encode("latin-1") + b"?\n"
            raise Stop(2)
    raise Stop(0)


def emit(m):
    """The prelude's emit: the byte goes through state + 400."""
    m.memory[STATE + 400] = m.pop() & 255
    m.output.append(m.memory[STATE + 400])


def die(m):
    raise Stop(m.pop() & 255)


def seed_case(kind, path):
    m = Machine()
    m.words = dict(SEED_WORDS)
    m.declined = SEED_DECLINED
    if kind == "prelude":
        m.words.update(emit=emit, die=die)
    try:
        interpret(m, open(path, "rb").read())
    except Stop as stop:
        sys.stdout.buffer.write(m.output)
        return stop.args[0]
    except (Declined, IndexError) as why:
        print(f"reference.py: not computed: {why or 'an empty stack'}", file=sys.stderr)
        return DECLINED


def same(m):
    expected, computed = m.pop(), m.pop()
    m.compared += 1
    if computed != expected:
        m.differ.append((m.line, computed, expected))
    m.push(flag(computed == expected))


def high_halves(path):
    m = Machine()
    m.words = {**SEED_WORDS, **LIBRARY_WORDS, "same": same, "tally": lambda m: m.pop()}
    m.declined = []
    m.library = True
    control = ("if,", "while,", "until,")
    lines = open(path, "rb").read().split(b"\n")
    skipped = 0
    for i, line in enumerate(lines):
        words = line.split(b"\\")[0].decode().split()
        if words[:1] == ["create"]:        # the last lines print and exit
            lines[i:] = []
            break
        if any(w in control for w in words):
            skipped += words.count("same")
            lines[i] = b""
        elif words[:1] == ["variable"]:    # variable NAME
            addr = STATE + 4096
            m.words[words[1]] = lambda m: m.push(addr)
            lines[i] = b""
        elif words[1:2] == ["constant"]:   # VALUE constant NAME
            value = int(words[0])
            m.words[words[2]] = lambda m: m.push(value)
            lines[i] = b""
    try:
        interpret(m, b"\n".join(lines))
    except Stop:
        pass
    for line, computed, expected in m.differ:
        print(f"reference.py: {path}:{line}: the file expects {expected}, the reference computes {computed}")
    if m.stack:
        print(f"reference.py: {path}: {len(m.stack)} cell(s) left on the stack")
    print(f"reference.py: {path}: {m.compared - len(m.differ)} of {m.compared + skipped} expected values "
          f"agree with the reference; {skipped} on lines with control flow not computed")
    return 1 if m.differ or m.stack else 0


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "seed":
        sys.exit(seed_case(sys.argv[2], sys.argv[3]))
    if len(sys.argv) == 3 and sys.argv[1] == "high-halves":
        sys.exit(high_halves(sys.argv[2]))
    sys.exit(__doc__)
