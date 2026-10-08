#!/usr/bin/env python3
"""Check that every archive pin agrees with MANIFEST.sha256.

The stages check their own inputs from the pin files they have always read:
plumbing/SOURCES and plumbing/lexers.SOURCES (sha256sum --check in kaem),
plumbing/chain.SOURCES (gcc-direct/chain.sh), plumbing/late.SOURCES
(gcc-direct/late-tools.sh) and gcc64/SOURCES (gcc64/run-gcc64.sh, which also
holds the download URLs); ladder/stage12.sh reads MANIFEST.sha256 itself.
This proves each of those pins is in MANIFEST.sha256 with the same sha256
and that every MANIFEST entry is pinned by some stage.

    python3 tools/check-pins.py      (from the repository root)
"""
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CHAIN_DIRS = {"gcc-4.0.4-git-944765863e.tar": "build-out/direct-gcc-inputs/",
              "binutils-2.30.tar": "build-out/stage-b-inputs/",
              "musl-1.1.24.tar.gz": "build-out/stage-c-inputs/"}


def rows(rel):
    for line in (ROOT / rel).read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            yield line.split()


def main():
    manifest = {path: sha for sha, path in rows("MANIFEST.sha256")}
    pins = []                                   # (file, path, sha)
    for f in ("plumbing/SOURCES", "plumbing/lexers.SOURCES"):
        pins += [(f, path, sha) for sha, path, *_ in rows(f) if path.startswith("build-out/")]
    pins += [("plumbing/chain.SOURCES", CHAIN_DIRS[n] + n, sha) for n, sha, *_ in rows("plumbing/chain.SOURCES")]
    for f in ("plumbing/late.SOURCES", "gcc64/SOURCES"):
        pins += [(f, "build-out/distfiles/" + n, sha) for n, sha, *_ in rows(f)]
    stage12 = (ROOT / "ladder/stage12.sh").read_text()
    pins += [("ladder/stage12.sh", "build-out/distfiles/" + line.split()[2], None)
             for line in stage12.splitlines() if line.strip().startswith("unpack ")]
    bad = 0
    for f, path, sha in pins:
        if path not in manifest:
            print(f"check-pins: {f}: {path} is not in MANIFEST.sha256"); bad += 1
        elif sha is not None and manifest[path] != sha:
            print(f"check-pins: {f}: {path} is {sha}, MANIFEST.sha256 says {manifest[path]}"); bad += 1
    for path in sorted(set(manifest) - {p for _, p, _ in pins}):
        print(f"check-pins: MANIFEST.sha256: {path} is pinned by no stage"); bad += 1
    if bad:
        sys.exit(1)
    print(f"check-pins: {len(pins)} stage pins agree with the {len(manifest)} entries of MANIFEST.sha256")


main()
