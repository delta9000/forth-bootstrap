#!/usr/bin/env python3
"""Download the four archives the route reads and check their sha256.

    python3 tools/fetch-archives.py [PATH ...]

From the repository root.  The pins are tinycc/SOURCES (tcc, Mes and
live-bootstrap, which the boot checks again with its own sha256sum) and
tinycc/builder-hex0.SOURCES (the kernel, which is not on the boot's disk).
Each archive goes to the build-out/ path its pin names, and is used only
if its sha256 is the pinned one.  Files already in place with the right
sha256 are kept.  With PATH arguments, only those paths are fetched.

Sources: the fork of tcc and Mes at the URLs of live-bootstrap's
steps/tcc-0.9.26/sources and steps/mes-0.28/sources (Mes from the GNU
mirror network, then mirrors.kernel.org, then ftp.gnu.org), and
live-bootstrap and builder-hex0 as GitHub's archives of the pinned
commits.  Needs curl.
"""
import hashlib, os, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PINS = ["tinycc/SOURCES", "tinycc/builder-hex0.SOURCES"]
GNU = ["https://ftpmirror.gnu.org/gnu", "https://mirrors.kernel.org/gnu", "https://ftp.gnu.org/gnu"]
URLS = {
    "tcc-0.9.26.tar.gz": ["https://lilypond.org/janneke/tcc/tcc-0.9.26-1147-gee75a10c.tar.gz"],
    "mes-0.28.tar.gz": [m + "/mes/mes-0.28.tar.gz" for m in GNU],
    "live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9.tar.gz":
        ["https://github.com/fosslinux/live-bootstrap/archive/a49273cbb5c381b851198bc1e53c294702f4f7c9.tar.gz"],
    "builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a.tar.gz":
        ["https://github.com/ironmeld/builder-hex0/archive/a2781242d19e6be891b453d8fa827137ab5db31a.tar.gz"],
}


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main():
    os.chdir(ROOT)
    pinned = {}
    for pins in PINS:
        for line in pathlib.Path(pins).read_text().splitlines():
            if line.strip() and not line.startswith("#"):
                digest, path = line.split()
                pinned[path] = digest
    wanted = sys.argv[1:] or list(pinned)
    unknown = [p for p in wanted if p not in pinned]
    if unknown:
        sys.exit(f"fetch-archives: not pinned in {' or '.join(PINS)}: {' '.join(unknown)}")
    bad = 0
    for path in wanted:
        dest = pathlib.Path(path)
        if dest.is_file() and sha(dest) == pinned[path]:
            print(f"ok      {path}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=dest.parent) as tmp:
            out = pathlib.Path(tmp) / dest.name
            for url in URLS[dest.name]:
                done = subprocess.run(["curl", "-fsSL", "--retry", "3", "--connect-timeout", "30",
                                       "-o", str(out), url])
                if done.returncode == 0 and sha(out) == pinned[path]:
                    os.replace(out, dest)
                    print(f"fetched {path}")
                    break
                print(f"        {url}: failed or wrong sha256")
            else:
                print(f"FAIL    {path}")
                bad += 1
    if bad:
        sys.exit(f"fetch-archives: {bad} archive(s) missing or wrong")
    print(f"fetch-archives: all {len(wanted)} archives in place, sha256 as pinned")


main()
