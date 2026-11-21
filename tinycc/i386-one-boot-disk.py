#!/usr/bin/env python3
"""Write builder-hex0's disk for the one-boot TinyCC step: sources and
scripts only, no program built on the host.

    python3 -I tinycc/i386-one-boot-disk.py OUT STAGE1

Run from the repository root.  OUT is a directory; STAGE1 is builder-hex0's
stage 1 as hex0-seed assembled it.  forth/i386/CONTRACT.md, section 7, is
the design.  Writes into OUT:

seed.kaem  /boot/seed.kaem, the two commands kaem-optional-seed runs: the
    seed compiles kaem, and that kaem runs /kaem.run.  kaem-optional-seed
    knows no variables, no search path and no cd, and does not check that
    a program is there, so both lines are complete paths.

i386-one-boot.kaem  /kaem.run, in this order:
      live-bootstrap's variables (steps/env, seed/seed.kaem);
      ours: every seed run, which must come before the first cd because
          the Forth files name each other relative to / and builder-hex0
          cannot change directory back to /.  The seed builds the tools as
          tinycc/build-tools.sh orders them (stock ungz and untar unpack
          live-bootstrap's archive, which holds simple-patch's source; the
          patched ungz and untar unpack it again), then the tools prepare
          the first tcc's sources in / as tinycc/build-first-tcc-i386.sh
          does in build-out/tcc-sources-i386, and the seed compiles the
          first tcc to /usr/bin/tcc-mes;
      live-bootstrap's text, cut from steps/mes-0.28/pass1.kaem and
          steps/tcc-0.9.26/pass1.kaem (build-out/tinycc/lb/) at marker
          lines that must each occur once: the lines tinycc/lb-replay.sh
          runs on the host.  Of mes-0.28, the unpacking and the header
          install; of tcc-0.9.26, "# Vars" to "# Checksums" without the two
          MesCC commands and the cp and chmod that install their tcc-mes;
      ours: copies of what tcc-mes made, the exporter, and the export.

i386-one-boot.list  what follows builder-hex0's two stages on the disk,
    one item per line, as tinycc/hex0-disk.c reads them:
        d PATH        a directory: "src 0 PATH"
        f PATH NAME   the host's file PATH as "src SIZE NAME" and its bytes
        x LINE        LINE itself, a command for builder-hex0's shell
    Every file the boot reads from the repository is at its repository
    path under /.  The three commands: the built-in hex0 assembles the
    seed and kaem-optional-seed from their sources, and kaem-optional-seed
    runs /boot/seed.kaem.

distfiles.SHA256SUM  tinycc/SOURCES with the archives' paths in the boot.

export.list  the files the boot exports, one per line, for the check.

disk.img  the disk, laid out as live-bootstrap's lib/generator.py lays it
    out: STAGE1, the stage-2 hex0 source, zeros to sector 175, the items,
    zeros to 64 MiB.
"""
import os, sys

IN = "build-out/tinycc-inputs"
BH = "builder-hex0-a2781242d19e6be891b453d8fa827137ab5db31a"
LB = "live-bootstrap-a49273cbb5c381b851198bc1e53c294702f4f7c9"
LB_TREE = f"build-out/tinycc/lb/{LB}"
TCC_PKG = "tcc-0.9.26-1147-gee75a10c"
MES = "mes-0.28"
ARCHIVES = ["tcc-0.9.26.tar.gz", "mes-0.28.tar.gz", f"{LB}.tar.gz"]
MESCC = "${MES} --no-auto-compile -e main ${BINDIR}/mescc.scm -- \\"
X = "vendor/stage0-posix/mescc-tools-extra"
KAEM = "vendor/mescc-tools/Kaem"
LIB = "/forth/i386/010-lib.fth"
TOOL = f"/seed-forth-i386 {LIB} /tinycc/i386-seed/tool.fth"
STOCK = ["catm", "sha256sum", "mkdir", "cp", "chmod", "rm", "match"]
PATCHED = [("ungz", "ungz-unsigned-bytes"), ("untar", "untar-ustar-prefix")]
# the files of the live-bootstrap archive that pass1.kaem reads
STEP_FILES = ["sources"] + [f"simple-patches/{p}.{side}"
                            for p in ("remove-fileopen", "addback-fileopen")
                            for side in ("before", "after")]
# what tcc-mes makes and the later stages overwrite, kept under /first
FIRST = ["crt1.o", "crti.o", "crtn.o", "libc.a", "tcc/libtcc1.a", "libgetopt.a"]
TOOLS = sorted(STOCK + [t for t, _ in PATCHED] + ["simple-patch", "checksum-transcriber"])
EXPORT = (["/usr/bin/tcc-mes", "/usr/bin/tcc-boot0", "/usr/bin/tcc-boot1", "/usr/bin/tcc",
           "/usr/lib/mes/libc.a", "/usr/lib/mes/libgetopt.a", "/usr/lib/mes/crt1.o",
           "/usr/lib/mes/crti.o", "/usr/lib/mes/crtn.o", "/usr/lib/mes/tcc/libtcc1.a"]
          + [f"/first/{os.path.basename(f)}" for f in FIRST]
          + ["/usr/bin/hex0-export", "/seed-forth-i386", "/kaem-optional-seed", "/x86/bin/kaem",
             "/boot/ungz", "/boot/untar"]
          + [f"/x86/bin/{t}" for t in TOOLS])
# seed.kaem's mkdir -p makes the first nine; the next seven are where
# live-bootstrap's disk has its steps, distfiles and stage0's tools; /first
# and /boot are ours.  The directories of the repository's files are added
# to these.
DIRS = ["/usr", "/usr/bin", "/usr/lib", "/usr/lib/mes", "/usr/include", "/usr/include/mes",
        "/steps", "/tmp", "/dev",
        "/steps/mes-0.28", "/steps/tcc-0.9.26", "/steps/tcc-0.9.26/simple-patches",
        "/external", "/external/distfiles", "/x86", "/x86/bin", "/first", "/boot"]


def lines(path):
    return open(f"{LB_TREE}/{path}").read().splitlines()


def cut(text, start, stop):
    """Lines from the one equal to start up to, not including, stop."""
    assert text.count(start) == 1, f"'{start}' occurs {text.count(start)} times"
    i = text.index(start)
    return text[i:text.index(stop, i)]


def seed_kaem():
    """/boot/seed.kaem: kaem, by the seed, and the rest of the boot by it."""
    return (f"{TOOL} /x86/bin/kaem /tinycc/m2libc-kaem-i386.c "
            f"/{KAEM}/variable.c /{KAEM}/kaem_globals.c /{KAEM}/kaem.c\n"
            "/x86/bin/kaem --verbose --strict --file /kaem.run\n")


def seed_runs():
    """Our lines of /kaem.run that come before the first cd: the tools, the
    first tcc's sources and the first tcc."""
    get_lb = [f"--file ${{DISTFILES}}/{LB}.tar.gz --output /tmp/live-bootstrap.tar",
              "--non-strict --file /tmp/live-bootstrap.tar"]
    out = [f"{TOOL} /x86/bin/{t} /{X}/{t}.c" for t in STOCK]
    out += [f"{TOOL} /boot/{t} /{X}/{t}.c" for t, _ in PATCHED]
    # the archives against tinycc/SOURCES, then live-bootstrap's by the
    # stock tools, in /: untar has no option for another directory
    out += ["sha256sum -c /external/distfiles.SHA256SUM",
            f"/boot/ungz {get_lb[0]}", f"/boot/untar {get_lb[1]}",
            f"{TOOL} /x86/bin/simple-patch /{LB}/steps/simple-patch-1.0/src/simple-patch.c"]
    for t, patch in PATCHED:
        out += [f"catm /tmp/{t}.c /{X}/{t}.c",
                f"simple-patch /tmp/{t}.c /tinycc/tools/{patch}.before /tinycc/tools/{patch}.after",
                f"{TOOL} /x86/bin/{t} /tmp/{t}.c"]
    out += [f"ungz {get_lb[0]}", f"untar {get_lb[1]}",
            f"{TOOL} /x86/bin/checksum-transcriber "
            f"/{LB}/steps/checksum-transcriber-1.0/src/checksum-transcriber.c"]
    # the first tcc's sources, as tinycc/build-first-tcc-i386.sh prepares them
    sp = f"/{LB}/steps/tcc-0.9.26/simple-patches"
    out += ["ungz --file ${DISTFILES}/tcc-0.9.26.tar.gz --output /tmp/tcc.tar",
            "untar --non-strict --file /tmp/tcc.tar"]
    out += [f"simple-patch /{TCC_PKG}/tcctools.c {sp}/{p}.before {sp}/{p}.after"
            for p in ("remove-fileopen", "addback-fileopen")]
    out += [f"catm /{TCC_PKG}/config.h",
            f"ungz --file ${{DISTFILES}}/{MES}.tar.gz --output /tmp/mes.tar",
            "untar --non-strict --file /tmp/mes.tar",
            f"catm /{MES}/include/mes/config.h",
            f"mkdir /{MES}/include/arch"]
    out += [f"cp /{MES}/include/linux/x86/{h} /{MES}/include/arch/{h}"
            for h in ("kernel-stat.h", "signal.h", "syscall.h")]
    out += ["catm /direct-input.c /tinycc/direct-input-i386.c",
            "catm /mes-libc.c /tinycc/mes-libc.c",
            "catm /mes-libc-native.c /tinycc/mes-libc-native-i386.c",
            f"/seed-forth-i386 {LIB} /tinycc/i386-seed/tcc-first.fth /usr/bin/tcc-mes "
            f"/direct-input.c /{MES}/include /{MES}/include/linux/x86"]
    return out


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
    out += seed_runs()
    assert not any(l.split()[0] == "cd" for l in out), "a cd before the last seed run"
    # ours: the files of live-bootstrap's archive that pass1.kaem reads,
    # copied to where it reads them
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
    out += ["tcc-mes -static -L ${LIBDIR} -o ${BINDIR}/hex0-export /tinycc/hex0-export.c"]
    part = cut(tcc, "# Install", "# Checksums")
    out += part
    theirs += part
    out += ["hex0-export /dev/hda " + " ".join(EXPORT)]                   # ours

    # One kaem runs both steps, so a variable of steps/env that a step set
    # would reach the other and change tcc-boot0's -D paths.
    names = {l.split("=")[0] for l in env}
    for l in theirs[len(env):]:
        assert l.strip().split("=")[0] not in names, f"reassigns a steps/env variable: {l}"
    return "\n".join(out) + "\n"


def tree(root):
    """Every regular file under root, as repository paths."""
    found = []
    for d, ds, fs in os.walk(root):
        ds.sort()
        found += [os.path.join(d, f) for f in sorted(fs)
                  if os.path.isfile(os.path.join(d, f)) and not os.path.islink(os.path.join(d, f))]
    return found


def repository_files():
    """What the boot reads from the repository, each at its own path."""
    files = ["seed/i386/000-seed.hex0", "vendor/stage0-posix/x86/kaem-minimal.hex0",
             "forth/i386/010-lib.fth", "forth/i386/layers.fth"]
    files += [l.split()[1] for l in open("forth/i386/layers.fth") if l.startswith("include ")]
    files += ["tinycc/tcc-compile-i386.fth", "tinycc/tool-compile.fth",
              "tinycc/i386-seed/tcc-first.fth", "tinycc/i386-seed/tool.fth",
              "tinycc/m2libc-native-i386.c", "tinycc/m2libc-kaem-i386.c",
              "tinycc/direct-input-i386.c", "tinycc/mes-libc.c", "tinycc/mes-libc-native-i386.c",
              "tinycc/hex0-export.c"]
    files += [f"tinycc/tools/{patch}.{side}" for _, patch in PATCHED for side in ("before", "after")]
    files += tree("vendor/stage0-posix/M2libc")
    files += [f"{X}/{t}.c" for t in STOCK + [t for t, _ in PATCHED]]
    files += tree(KAEM)
    files += [f"vendor/mescc-tools/M2libc/bootstrappable.{e}" for e in ("c", "h")]
    return files


def items(out):
    """The list's lines: directories, files, then the three commands."""
    files = [(p, "/" + p) for p in repository_files()]
    files += [(f"{IN}/{a}", f"/external/distfiles/{a}") for a in ARCHIVES]
    files += [(f"{out}/distfiles.SHA256SUM", "/external/distfiles.SHA256SUM"),
              (f"{out}/seed.kaem", "/boot/seed.kaem"),
              (f"{out}/i386-one-boot.kaem", "/kaem.run")]
    dirs = list(DIRS)
    for _, name in files:
        assert len(name) <= 255 and " " not in name, name
        parts = name.split("/")[1:-1]
        for i in range(1, len(parts) + 1):
            d = "/" + "/".join(parts[:i])
            if d not in dirs:
                dirs.append(d)
    # The stock untar leaves the archive's long-named files in /, under
    # their last component; none may take the name of a directory there.
    top = {d.split("/")[1] for d in dirs}
    stray = top & set(os.listdir("build-out/tinycc/lb-boot")) - {LB}
    assert not stray, f"the stock untar would overwrite {stray} in /"
    return ([f"d {d}" for d in dirs] + [f"f {p} {n}" for p, n in files]
            + ["x hex0 /seed/i386/000-seed.hex0 /seed-forth-i386",
               "x hex0 /vendor/stage0-posix/x86/kaem-minimal.hex0 /kaem-optional-seed",
               "x /kaem-optional-seed /boot/seed.kaem"])


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
    out, stage1 = sys.argv[1:3]
    os.makedirs(out, exist_ok=True)
    with open(f"{out}/seed.kaem", "w") as f:
        f.write(seed_kaem())
    with open(f"{out}/i386-one-boot.kaem", "w") as f:
        f.write(script())
    # tinycc/SOURCES, with the paths the archives have in the boot
    sources = open("tinycc/SOURCES").read()
    assert sources.count(f"  {IN}/") == len(ARCHIVES)
    with open(f"{out}/distfiles.SHA256SUM", "w") as f:
        f.write(sources.replace(f"  {IN}/", "  /external/distfiles/"))
    with open(f"{out}/export.list", "w") as f:
        f.write("\n".join(EXPORT) + "\n")
    lst = items(out)
    with open(f"{out}/i386-one-boot.list", "w") as f:
        f.write("\n".join(lst) + "\n")
    with open(f"{out}/disk.img", "wb") as f:
        f.write(image(stage1, lst))
    n = sum(l.startswith("d ") for l in lst)
    print(f"i386-one-boot-disk: {n} directories, {len(lst) - n - 3} files, no program among them")


main()
