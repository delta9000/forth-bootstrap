\ forth/i386/layers.fth — the files of the i386 native compiler on the
\ i386 seed, in load order.
\
\ What cc/i386/layers.sh prints for the x86-64 seed, with three changes.
\ The library is not listed: the seed has read forth/i386/010-lib.fth
\ already, and this file is read through its include.  The i386 host's
\ own 020 stands in for cc/020-cc-arena.fth.  And forth/i386/030-io.fth
\ and forth/i386/115-nzero.fth follow the layers whose words they replace.
\ Every other file is the one the x86-64 seed reads.
\ tests/forth/i386/standin-check.sh compares this list with layers.sh's.
include forth/i386/020-cc-arena.fth
include cc/030-cc-io.fth
include forth/i386/030-io.fth
include cc/040-cc-prep.fth
include cc/050-cc-lex.fth
include cc/060-cc-types.fth
include cc/i386/065-ilp32-types.fth
include cc/070-cc-sym.fth
include cc/i386/080-elf32.fth
include cc/090-cc-emit.fth
include cc/i386/090-emit.fth
include cc/100-cc-expr.fth
include cc/i386/100-divide.fth
include cc/110-cc-decl.fth
include cc/112-cc-stmt.fth
include cc/115-cc-native.fth
include forth/i386/115-nzero.fth
include cc/117-cc-native-program.fth
include cc/i386/117-entry.fth
include cc/118-cc-native-init.fth
include cc/i386/119-runtime.fth
