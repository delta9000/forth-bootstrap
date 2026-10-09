#!/usr/bin/env python3
"""Download every archive in MANIFEST.sha256 and check its sha256.

    python3 tools/fetch-archives.py [--cache DIR] [PATH ...]

From the repository root.  Each archive goes to the build-out/ path that
MANIFEST.sha256 names, and is used only if its sha256 is the pinned one.
Files already in place with the right sha256 are kept.  With PATH
arguments, only those MANIFEST paths are fetched.

Sources: the upstream release URLs below (GNU packages from the GNU
mirror network, then mirrors.kernel.org, then ftp.gnu.org); chain/gcc64/SOURCES's URLs (and
its git export of GCC 4.0.4) for the archives it pins; three files are
derived rather than downloaded: build-out/stage-b-inputs/binutils-2.30.tar
is `xz -dc` of binutils-2.30.tar.xz (the chain's tools read no xz), and the
GCC and musl archives under direct-gcc-inputs/ and stage-c-inputs/ are
copies of the distfiles ones.  Needs curl, git and xz.  About 1.1 GB on
disk (some archives are kept at two paths).
"""
import argparse, hashlib, os, pathlib, shutil, subprocess, sys, tarfile, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
GNU = "@GNU@"     # expanded to the mirrors in GNU_MIRRORS, tried in order
GNU_MIRRORS = ["https://ftpmirror.gnu.org/gnu", "https://mirrors.kernel.org/gnu", "https://ftp.gnu.org/gnu"]
URLS = {
    # plumbing stages 1-2 and bash (chain/plumbing/SOURCES)
    "bash-2.05b.tar.gz": f"{GNU}/bash/bash-2.05b.tar.gz",
    "coreutils-5.0.tar.bz2": f"{GNU}/coreutils/coreutils-5.0.tar.bz2",
    "diffutils-2.7.tar.gz": f"{GNU}/diffutils/diffutils-2.7.tar.gz",
    "gawk-3.0.4.tar.gz": f"{GNU}/gawk/gawk-3.0.4.tar.gz",
    "grep-2.4.tar.gz": f"{GNU}/grep/grep-2.4.tar.gz",
    "gzip-1.2.4.tar.gz": f"{GNU}/gzip/gzip-1.2.4.tar.gz",
    "make-3.82.tar.bz2": f"{GNU}/make/make-3.82.tar.bz2",
    "patch-2.5.9.tar.gz": f"{GNU}/patch/patch-2.5.9.tar.gz",
    "sed-4.0.9.tar.gz": f"{GNU}/sed/sed-4.0.9.tar.gz",
    "tar-1.12.tar.gz": f"{GNU}/tar/tar-1.12.tar.gz",
    # parser generators (chain/plumbing/lexers.SOURCES)
    "oyacc-6.6.tar.gz": "https://github.com/ibara/yacc/releases/download/oyacc-6.6/oyacc-6.6.tar.gz",
    "heirloom-devtools-070527.tar.bz2": "https://downloads.sourceforge.net/project/heirloom/heirloom-devtools/070527/heirloom-devtools-070527.tar.bz2",
    "flex-d160f0247ba1611aa59d28f027d6292ba24abb50.tar.gz": "https://github.com/westes/flex/archive/d160f0247ba1611aa59d28f027d6292ba24abb50.tar.gz",
    "flex-2.6.4.tar.gz": "https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz",
    # late tools (chain/plumbing/late.SOURCES)
    "make-4.4.1.tar.gz": f"{GNU}/make/make-4.4.1.tar.gz",
    "sed-4.9.tar.gz": f"{GNU}/sed/sed-4.9.tar.gz",
    "grep-3.11.tar.gz": f"{GNU}/grep/grep-3.11.tar.gz",
    "gzip-1.13.tar.gz": f"{GNU}/gzip/gzip-1.13.tar.gz",
    "xz-5.6.3.tar.gz": "https://github.com/tukaani-project/xz/releases/download/v5.6.3/xz-5.6.3.tar.gz",
    "bzip2-1.0.8.tar.gz": "https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz",
    "tar-1.35.tar.gz": f"{GNU}/tar/tar-1.35.tar.gz",
    "gawk-5.3.1.tar.gz": f"{GNU}/gawk/gawk-5.3.1.tar.gz",
    "patch-2.7.6.tar.gz": f"{GNU}/patch/patch-2.7.6.tar.gz",
    "coreutils-9.5.tar.gz": f"{GNU}/coreutils/coreutils-9.5.tar.gz",
    "bash-5.2.37.tar.gz": f"{GNU}/bash/bash-5.2.37.tar.gz",
    "diffutils-3.10.tar.xz": f"{GNU}/diffutils/diffutils-3.10.tar.xz",
    "findutils-4.10.0.tar.xz": f"{GNU}/findutils/findutils-4.10.0.tar.xz",
    "m4-1.4.19.tar.gz": f"{GNU}/m4/m4-1.4.19.tar.gz",
    "bison-3.8.2.tar.gz": f"{GNU}/bison/bison-3.8.2.tar.gz",
    "bc-1.07.1.tar.gz": f"{GNU}/bc/bc-1.07.1.tar.gz",
    # stage 12 (chain/ladder/stage12.sh)
    "zlib-1.3.1.tar.gz": "https://zlib.net/fossils/zlib-1.3.1.tar.gz",
    "elfutils-0.192.tar.bz2": "https://sourceware.org/elfutils/ftp/0.192/elfutils-0.192.tar.bz2",
    "linux-7.2.8.tar.xz": "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.8.tar.xz",
}
COPIES = {  # MANIFEST path: the MANIFEST path it is a copy of
    "build-out/direct-gcc-inputs/gcc-4.0.4-git-944765863e.tar": "build-out/distfiles/gcc-4.0.4-git-944765863e.tar",
    "build-out/stage-c-inputs/musl-1.1.24.tar.gz": "build-out/distfiles/musl-1.1.24.tar.gz",
}
XZ = {"build-out/stage-b-inputs/binutils-2.30.tar": "build-out/distfiles/binutils-2.30.tar.xz"}


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def gcc64_urls():
    urls = {}
    for line in (ROOT / "chain/gcc64/SOURCES").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            name, _, *rest = line.split()
            urls[name] = rest
    return urls


def fetch(url, out, tmp):
    """One URL form of chain/gcc64/SOURCES: plain, URL!MEMBER or git+REPO#REF@COMMIT:PREFIX."""
    if url.startswith("git+"):
        u = url[4:]
        u, prefix = u.rsplit(":", 1)
        u, commit = u.rsplit("@", 1)
        repo, ref = u.split("#", 1)
        g = tmp / "git"
        subprocess.run(["git", "-c", "advice.detachedHead=false", "clone", "-q", "--depth", "1",
                        "--branch", ref, repo, str(g)], check=True)
        head = subprocess.run(["git", "-C", str(g), "rev-parse", "HEAD"], check=True,
                              capture_output=True, text=True).stdout.strip()
        if head != commit:
            raise RuntimeError(f"{repo} {ref} is {head}, not {commit}")
        with open(out, "wb") as f:
            subprocess.run(["git", "-C", str(g), "archive", "--format=tar", f"--prefix={prefix}/", "HEAD"],
                           check=True, stdout=f)
        shutil.rmtree(g)
        return
    member = None
    if "!" in url:
        url, member = url.split("!", 1)
    dl = tmp / "download"
    subprocess.run(["curl", "-fsSL", "--retry", "3", "--connect-timeout", "30", "-o", str(dl), url], check=True)
    if member is None:
        shutil.move(dl, out)
        return
    with tarfile.open(dl) as t, open(out, "wb") as f:
        shutil.copyfileobj(t.extractfile(member), f)
    dl.unlink()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="*")
    args = ap.parse_args()
    os.chdir(ROOT)
    manifest = {}
    for line in pathlib.Path("MANIFEST.sha256").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            digest, path = line.split()
            manifest[path] = digest
    wanted = args.paths or list(manifest)
    unknown = [p for p in wanted if p not in manifest]
    if unknown:
        sys.exit(f"fetch-archives: not in MANIFEST.sha256: {' '.join(unknown)}")
    # copies and derived files after what they come from
    order = [p for p in wanted if p not in COPIES and p not in XZ]
    for p in wanted:
        src = COPIES.get(p) or XZ.get(p)
        if src:
            if src not in order:
                order.append(src)
            order.append(p)
    g64 = gcc64_urls()
    bad = 0
    for path in order:
        dest = pathlib.Path(path)
        if dest.is_file() and sha(dest) == manifest[path]:
            print(f"ok      {path}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        name = dest.name
        with tempfile.TemporaryDirectory(dir=dest.parent) as tmp:
            tmp = pathlib.Path(tmp)
            out = tmp / name
            try:
                if path in COPIES:
                    shutil.copyfile(COPIES[path], out)
                elif path in XZ:
                    with open(out, "wb") as f:
                        subprocess.run(["xz", "-dc", XZ[path]], check=True, stdout=f)
                else:
                    if name in g64:
                        urls = g64[name]
                    elif URLS[name].startswith(GNU):
                        urls = [URLS[name].replace(GNU, m) for m in GNU_MIRRORS]
                    else:
                        urls = [URLS[name]]
                    for i, url in enumerate(urls):
                        try:
                            fetch(url, out, tmp)
                            if sha(out) == manifest[path]:
                                break
                            print(f"        {url}: wrong sha256, trying the next source")
                        except Exception as e:      # try the next URL
                            print(f"        {url}: {e}")
                            if i == len(urls) - 1:
                                raise
            except Exception as e:
                print(f"FAIL    {path}: {e}")
                bad += 1
                continue
            got = sha(out)
            if got != manifest[path]:
                print(f"FAIL    {path}: sha256 {got}, pinned {manifest[path]}")
                bad += 1
                continue
            os.replace(out, dest)
            print(f"fetched {path}")
    if bad:
        sys.exit(f"fetch-archives: {bad} archive(s) missing or wrong")
    print(f"fetch-archives: all {len(wanted)} archives in place, sha256 as pinned")


main()
