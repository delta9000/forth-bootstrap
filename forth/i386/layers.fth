\ forth/i386/layers.fth -- the files of the C compiler, in load order.
\
\ The library is not listed: the seed has read forth/i386/010-lib.fth
\ already, and this file is read through its include.
include forth/i386/020-cc-arena.fth
include cc/030-cc-io.fth
include cc/040-cc-prep.fth
include cc/050-cc-lex.fth
include cc/060-cc-types.fth
include cc/070-cc-sym.fth
include cc/080-cc-elf.fth
include cc/090-cc-emit.fth
include cc/100-cc-expr.fth
include cc/110-cc-decl.fth
include cc/112-cc-stmt.fth
include cc/115-cc-native.fth
include cc/117-cc-native-program.fth
include cc/118-cc-native-init.fth
include cc/119-cc-runtime.fth
