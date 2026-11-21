\ tinycc/tcc-names-i386.fth -- the first tcc's four paths on the host.
\
\ Loaded between the compiler layers and tinycc/tcc-compile-i386.fth, as
\ the three lines tinycc/build-tools-i386.sh prints are loaded ahead of
\ tinycc/tool-compile.fth.  The driver itself names no file, so the i386
\ seed's job (tinycc/i386-seed/tcc-first.fth) loads the same driver after
\ taking these four paths from its command line.
\
\ tcc-output is the file the driver writes, with its NUL.  The source's
\ name is where quoted includes are looked for; the include paths are
\ pass1.kaem's for Mes libc on x86: include and include/linux/x86.
create tcc-output s, build-out/tinycc/tcc-first-i386 [lit] 0 c,
create tcc-source s, build-out/tcc-sources-i386/direct-input.c
tcc-source [lit] 41 cc-prep-source-name
create tcc-include s, build-out/tcc-sources-i386/mes-0.28/include
tcc-include [lit] 43 cc-prep-add-include
create tcc-include-linux s, build-out/tcc-sources-i386/mes-0.28/include/linux/x86
tcc-include-linux [lit] 53 cc-prep-add-include
