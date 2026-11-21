#!/usr/bin/env python3
"""Write builder-hex0's disk for the one-boot TinyCC step.

    python3 -I tinycc/i386-one-boot-disk.py OUT STAGE1 KAEM

Run from the repository root.  OUT is a directory; STAGE1 is builder-hex0's
stage 1 as hex0-seed assembled it; KAEM is the i386 kaem that
tests/tinycc/i386-one-boot-check.sh built on the host.  Writes into OUT:

i386-one-boot.kaem  the script of the boot.  Ours are the lines marked
    below; every other line is live-bootstrap's, cut from steps/env,
    seed/seed.kaem, steps/mes-0.28/pass1.kaem and
    steps/tcc-0.9.26/pass1.kaem (build-out/tinycc/lb/) at marker lines
    that must each occur once.  They are the lines tinycc/lb-replay.sh
    runs on the host: of mes-0.28, the unpacking and the header install; of
    tcc-0.9.26, "# Vars" to "# Checksums" without the two MesCC commands
    and the cp and chmod that install their tcc-mes, which the disk has
    in place.

i386-one-boot.list  what follows builder-hex0's two stages on the disk,
    one item per line, as tinycc/hex0-disk.c reads them:
        d PATH        a directory: "src 0 PATH"
        f PATH NAME   the host's file PATH as "src SIZE NAME" and its bytes
        x LINE        LINE itself, a command for builder-hex0's shell

distfiles.SHA256SUM  tinycc/SOURCES with the archives' paths in the boot.

disk.img  the disk, laid out as live-bootstrap's lib/generator.py lays it
    out: STAGE1, the stage-2 hex0 source, zeros to sector 175, the items,
    zeros to 64 MiB.
"""
import os, sys

IN = "build-out/tinycc-inputs"
BH = "builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a"
LB = "live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9"
LB_TREE = f"build-out/tinycc/lb/{LB}"
ARCHIVES = ["tcc-0.9.26.tar.gz", "mes-0.28.tar.gz", f"{LB}.tar.gz"]
MESCC = "${MES} --no-auto-compile -e main ${BINDIR}/mescc.scm -- \\"
# the files of the live-bootstrap archive that pass1.kaem reads
STEP_FILES = ["sources"] + [f"simple-patches/{p}.{side}"
                            for p in ("remove-fileopen", "addback-fileopen")
                            for side in ("before", "after")]
# what tcc-mes makes and the later stages overwrite, kept under /first
FIRST = ["crt1.o", "crti.o", "crtn.o", "libc.a", "tcc/libtcc1.a", "libgetopt.a"]
EXPORT = (["/usr/bin/tcc-mes", "/usr/bin/tcc-boot0", "/usr/bin/tcc-boot1", "/usr/bin/tcc",
           "/usr/lib/mes/libc.a", "/usr/lib/mes/libgetopt.a", "/usr/lib/mes/crt1.o",
           "/usr/lib/mes/crti.o", "/usr/lib/mes/crtn.o", "/usr/lib/mes/tcc/libtcc1.a"]
          + [f"/first/{os.path.basename(f)}" for f in FIRST]
          + ["/x86/bin/kaem", "/usr/bin/hex0-export"])
# seed.kaem makes the first six; live-bootstrap's disk has the next three
DIRS = ["/usr", "/usr/bin", "/usr/lib", "/usr/lib/mes", "/usr/include", "/usr/include/mes",
        "/steps", "/tmp", "/dev",
        "/steps/mes-0.28", "/steps/tcc-0.9.26", "/steps/tcc-0.9.26/simple-patches",
        "/external", "/external/distfiles", "/x86", "/x86/bin", "/first"]


def lines(path):
    return open(f"{LB_TREE}/{path}").read().splitlines()


def cut(text, start, stop):
    """Lines from the one equal to start up to, not including, stop."""
    assert text.count(start) == 1, f"'{start}' occurs {text.count(start)} times"
    i = text.index(start)
    return text[i:text.index(stop, i)]


def script():
    env = [l for l in lines("steps/env") if l[:1].isupper() and "=" in l]
    seed = [l for l in lines("seed/seed.kaem")
            if l.split("=")[0] in ("NYACC_PKG", "MES_PKG", "MES_PREFIX")]
    assert len(seed) == 3
    mes = lines("steps/mes-0.28/pass1.kaem")
    tcc = lines("steps/tcc-0.9.26/pass1.kaem")
    unpack = ["mkdir build", "cd build",
              "ungz --file ${DISTFILES}/${MES_PKG}.tar.gz --output ${MES_PKG}.tar",
              "untar --non-strict --file ${MES_PKG}.tar # ignore symlinks"]
    for line in unpack:
        assert line in mes, line

    ours = ["set -ex", "ARCH=x86", "ARCH_DIR=x86"]
    theirs = env + seed
    out = ours + theirs
    # ours: the archives against tinycc/SOURCES; live-bootstrap's unpacked
    # in /, and the files of it that pass1.kaem reads copied to where it
    # reads them
    out += ["sha256sum -c /external/distfiles.SHA256SUM",
            f"ungz --file ${{DISTFILES}}/{LB}.tar.gz --output /tmp/live-bootstrap.tar",
            "untar --non-strict --file /tmp/live-bootstrap.tar"]
    out += [f"cp /{LB}/steps/tcc-0.9.26/{f} ${{SRCDIR}}/tcc-0.9.26/{f}" for f in STEP_FILES]
    out += ["cd /steps/mes-0.28"]
    part = cut(mes, "if match ${ARCH} x86; then", "if match ${ARCH} amd64; then")
    part += unpack
    part += cut(mes, "cd ${MES_PREFIX}", "# Remove pregenerated files")
    part += [l for l in cut(mes, "# Make directories", "cd ../..")
             if not l.startswith("cp ${LIBDIR}/")]
    out += part
    theirs += part
    out += ["cd /steps/tcc-0.9.26"]                                       # ours
    part = cut(tcc, "# Vars", MESCC) + cut(tcc, "# test tcc-mes", "# Install")
    out += part
    theirs += part
    # ours: keep what tcc-mes made, and build the exporter with it
    out += [f"cp ${{LIBDIR}}/{f} /first/{os.path.basename(f)}" for f in FIRST]
    out += ["tcc-mes -static -L ${LIBDIR} -o ${BINDIR}/hex0-export /hex0-export.c"]
    part = cut(tcc, "# Install", "# Checksums")
    out += part
    theirs += part
    out += ["hex0-export /dev/hda " + " ".join(EXPORT)]                   # ours

    # One kaem runs both steps, so a variable of steps/env that a step set
    # would reach the other and change tcc-boot0's -D paths.
    names = {l.split("=")[0] for l in env}
    for l in theirs[len(env):]:
        assert l.split("=")[0] not in names, f"reassigns a steps/env variable: {l}"
    return "\n".join(out) + "\n"


def items(out, kaem):
    """The list's lines: directories, files, then kaem's start."""
    tools = "build-out/tinycc/bin-i386"
    files = [(f"{tools}/{t}", f"/x86/bin/{t}") for t in sorted(os.listdir(tools))]
    files += [(kaem, "/x86/bin/kaem"),
              ("build-out/tinycc/tcc-first-i386", "/usr/bin/tcc-mes"),
              ("tinycc/hex0-export.c", "/hex0-export.c")]
    files += [(f"{IN}/{a}", f"/external/distfiles/{a}") for a in ARCHIVES]
    files += [(f"{out}/distfiles.SHA256SUM", "/external/distfiles.SHA256SUM"),
              (f"{out}/i386-one-boot.kaem", "/kaem.run")]
    return ([f"d {d}" for d in DIRS] + [f"f {p} {n}" for p, n in files]
            + ["x /x86/bin/kaem --verbose"])


def image(stage1, lst):
    img = bytearray(open(stage1, "rb").read())
    img += open(f"{IN}/{BH}/builder-hex0-x86-stage2.hex0", "rb").read()
    assert len(img) <= 175 * 512, "the two stages pass sector 175"
    img += bytes(175 * 512 - len(img))
    for line in lst:
        kind, rest = line[0], line[2:]
        if kind == "d":
            img += f"src 0 {rest}\n".encode()
        elif kind == "f":
            path, name = rest.split(" ")
            data = open(path, "rb").read()
            img += f"src {len(data)} {name}\n".encode() + data
        else:
            img += (rest + "\n").encode()
    assert len(img) < 64 << 20, "the stream passes 64 MiB"
    return img + bytes((64 << 20) - len(img))


def main():
    out, stage1, kaem = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    with open(f"{out}/i386-one-boot.kaem", "w") as f:
        f.write(script())
    # tinycc/SOURCES, with the paths the archives have in the boot
    sources = open("tinycc/SOURCES").read()
    assert sources.count(f"  {IN}/") == len(ARCHIVES)
    with open(f"{out}/distfiles.SHA256SUM", "w") as f:
        f.write(sources.replace(f"  {IN}/", "  /external/distfiles/"))
    lst = items(out, kaem)
    with open(f"{out}/i386-one-boot.list", "w") as f:
        f.write("\n".join(lst) + "\n")
    with open(f"{out}/disk.img", "wb") as f:
        f.write(image(stage1, lst))
    print(f"i386-one-boot-disk: {len(DIRS)} directories, {len(lst) - len(DIRS) - 1} files")


main()
