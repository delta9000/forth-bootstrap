#!/usr/bin/env python3
"""Write K1's input disk: the chain root's starting tree as one archive.

  mkdisk.py OUT [--direct-smoke | --direct | --direct-linux] [--jobs N]

The tree is kernel/k1/direct_inputs.py's k1_tree() -- hex0-seed (the only
executable), seed/000-seed.hex0, the Forth and C sources the route reads and, for
the longer runs, the pinned archives -- plus /k1.args and /k1.recipe, which
tell K1 what to run.  Format: see kernel/k1/ata.c.

/k1.recipe is kernel/k1/direct-smoke.recipe (--direct-smoke), kernel/k1/direct.recipe
(--direct, the seed to bash 2.05b) or kernel/k1/direct.recipe followed by
kernel/k1/direct-linux.recipe (--direct-linux, the default: on to Linux).
"""
import argparse, os, pathlib, struct, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
HEX0 = ROOT / "vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed"
sys.path.insert(0, str(ROOT / "kernel/k1"))
S_IFDIR, S_IFREG = 0o040000, 0o100000


def direct_tree(smoke, linux=False):
    from direct_inputs import k1_tree
    out = {name: (path, 0o644) for name, path in k1_tree(smoke, linux).items()}
    out["hex0-seed"] = (HEX0, 0o755)
    return out

def positive_jobs(value):
    if not value.isascii() or not value.isdecimal() or not 1 <= int(value) <= 256:
        raise argparse.ArgumentTypeError("jobs must be an integer from 1 to 256")
    return int(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output")
    parser.add_argument("--direct-smoke", action="store_true",
                        help="direct-GCC route: seed-cc, seed-ar and kaem under K1 (kernel/k1/direct-smoke.recipe)")
    parser.add_argument("--direct", action="store_true",
                        help="direct-GCC route: the seed to bash 2.05b under K1 (kernel/k1/direct.recipe)")
    parser.add_argument("--direct-linux", action="store_true",
                        help="direct-GCC route to Linux: kernel/k1/direct.recipe, then kernel/k1/direct-linux.recipe")
    parser.add_argument("--jobs", type=positive_jobs,
                        help="the make job count for the --direct-linux stages (default 2)")
    args = parser.parse_args()
    dest = args.output
    if args.direct_smoke + args.direct + args.direct_linux > 1:
        parser.error("choose one of --direct-smoke, --direct and --direct-linux")
    if args.direct_smoke or args.direct:
        if args.jobs is not None:
            parser.error("--jobs applies to --direct-linux only")
        files = direct_tree(args.direct_smoke)
        recipe = ROOT / ("kernel/k1/direct-smoke.recipe" if args.direct_smoke else "kernel/k1/direct.recipe")
        recipe = recipe.read_bytes()
    else:
        files = direct_tree(False, linux=True)
        recipe = (ROOT / "kernel/k1/direct.recipe").read_bytes() + (ROOT / "kernel/k1/direct-linux.recipe").read_bytes()
        if args.jobs is not None:
            text = recipe.decode()
            if text.count("JOBS=2") != 3:
                raise ValueError("expected three JOBS=2 in kernel/k1/direct-linux.recipe")
            recipe = text.replace("JOBS=2", f"JOBS={args.jobs}").encode()
    extra = {"k1.args": b"/k0/build-out/amd64-runner\n--recipe\n/k1.recipe\n",
             "k1.recipe": recipe}
    dirs = {"build-out", "tmp", "proc"}
    for name in list(files) + list(extra):
        d = os.path.dirname(name)
        while d:
            dirs.add(d)
            d = os.path.dirname(d)
    total = 0
    with open(dest, "wb") as o:
        o.write(b"K1DISK1\0")
        def rec(name, mode, data_iter, size):
            n = name.encode()
            o.write(struct.pack("<IIQ", len(n), mode, size) + n)
            for chunk in data_iter:
                o.write(chunk)
            o.write(b"\0" * (-o.tell() % 8))
        for d in sorted(dirs, key=lambda d: (d.count("/"), d)):
            rec(d, S_IFDIR | 0o755, [], 0)
        for name in sorted(files):
            p, mode = files[name]
            size = p.stat().st_size
            def chunks(p=p):
                with open(p, "rb") as f:
                    while True:
                        b = f.read(1 << 20)
                        if not b:
                            return
                        yield b
            rec(name, S_IFREG | mode, chunks(), size)
            total += size
        for name, data in extra.items():
            rec(name, S_IFREG | 0o644, [data], len(data))
        o.write(struct.pack("<IIQ", 0, 0, 0))
        o.write(b"\0" * (-o.tell() % 512))
    print(f"{dest}: {len(files) + len(extra)} files, {total >> 20} MiB")

if __name__ == "__main__":
    main()
