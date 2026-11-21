\ tinycc/catm-start.fth -- the Forth input that builds the first catm.
\     ./seed-forth < tinycc/catm-start.fth
\     ./seed-forth < build-out/tinycc/catm.input
\ tinycc/build-tools.sh joins every other tool's Forth input with the
\ seed-built catm; catm's own has to be joined before catm exists.  This
\ file does it with the seed alone: it writes build-out/tinycc/catm.input,
\ the files below one after another, as catm would.  Exit status 0 is
\ success; 11x names the failing operation.  The words up to `close` are
\ cc/driver/seed-cc-start.fth's, unchanged.
: latest state 8 + ;
: here-addr state 16 + ;
: here here-addr @ ;
: , here ! here 8 + here-addr ! ;
: c, here c! here 1 + here-addr ! ;
: ' token find ;
: execute >r ;
: r@ r> r> dup >r swap >r ;
: over >r dup r> swap ;
: nip swap drop ;
: - dup nand 1 + + ;
: 1+ 1 + ;
: 1- 1 - ;
: = - 0= ;
: <> = 0= ;
: and nand dup nand ;
: 0< 9223372036854775808 / 0= 0= ;
: < - 0< ;
: 2drop drop drop ;
: immediate latest @ 8 + 1 swap c! ;
: ,4 dup c, 256 / dup c, 256 / dup c, 256 / c, ;
: ,8 dup ,4 256 / 256 / 256 / 256 / ,4 ;
: push-body,
 72 c, 131 c, 237 c, 8 c,
 72 c, 137 c, 125 c, 0 c,
 72 c, 191 c, ,8 195 c, ;
: constant : push-body, 0 state ! ;
: call, 232 c, here 4 + - ,4 ;
: branch r> @ >r ;
: 0branch 0= r> dup @ swap 8 + dup >r - and r> + >r ;
' branch constant branch-xt
' 0branch constant 0branch-xt
: if, 0branch-xt call, here 0 , ; immediate
: then, here swap ! ; immediate
: else, branch-xt call, here 0 , swap here swap ! ; immediate
: begin, here ; immediate
: while, 0branch-xt call, here 0 , ; immediate
: repeat, swap branch-xt call, , here swap ! ; immediate
: exit, 195 c, ; immediate
: create : here 19 + push-body, 0 state ! ;
: variable create 0 , ;
: allot here-addr @ + here-addr ! ;
: 2dup over over ;
: > swap < ;
: s0,
 token begin, dup while, over c@ c, 1- swap 1+ swap repeat,
 2drop 0 c, ;
: die 0 0 0 0 0 60 syscall6 ;
: open 0 0 0 2 syscall6 ;
: read 0 0 0 0 syscall6 ;
: write 0 0 0 1 syscall6 ;
: close 0 0 0 0 0 3 syscall6 ;
\ The files, as build-tools.sh joins them for the other tools: the
\ Forth library and compiler layers 020 to 119 without 081, catm's names,
\ the driver, then the C source on the compiler's stdin.
create out-path s0, build-out/tinycc/catm.input
create f00 s0, forth/010-lib.fth
create f01 s0, cc/020-cc-arena.fth
create f02 s0, cc/030-cc-io.fth
create f03 s0, cc/040-cc-prep.fth
create f04 s0, cc/050-cc-lex.fth
create f05 s0, cc/060-cc-types.fth
create f06 s0, cc/070-cc-sym.fth
create f07 s0, cc/080-cc-elf.fth
create f08 s0, cc/090-cc-emit.fth
create f09 s0, cc/100-cc-expr.fth
create f10 s0, cc/110-cc-decl.fth
create f11 s0, cc/112-cc-stmt.fth
create f12 s0, cc/114-cc-func.fth
create f13 s0, cc/115-cc-native.fth
create f14 s0, cc/116-cc-prog.fth
create f15 s0, cc/117-cc-native-program.fth
create f16 s0, cc/118-cc-native-init.fth
create f17 s0, cc/119-cc-native-runtime.fth
create f18 s0, tinycc/tools/catm.fth
create f19 s0, tinycc/tool-compile.fth
create f20 s0, tinycc/m2libc-native.c
create f21 s0, vendor/stage0-posix/mescc-tools-extra/catm.c
create file-list
  f00 , f01 , f02 , f03 , f04 , f05 , f06 , f07 , f08 , f09 , f10 ,
  f11 , f12 , f13 , f14 , f15 , f16 , f17 , f18 , f19 , f20 , f21 ,
  0 ,
variable out-fd
variable in-fd
variable count
\ Keep data above the fixed VM pages, addressed through STATE, not constants.
state 4096 + here-addr !
create buffer 65536 allot
\ copy-file ( zname -- )  Append the whole file to out-fd.
: copy-file
  0 0 open dup 0< if, 111 die then, in-fd !
  begin, in-fd @ buffer 65536 read dup count ! while,
    count @ 0< if, 112 die then,
    out-fd @ buffer count @ write count @ <> if, 113 die then,
  repeat,
  in-fd @ close if, 114 die then, ;
: main
  out-path 577 384 open dup 0< if, 110 die then, out-fd !
  file-list begin, dup @ while, dup @ copy-file 8 + repeat, drop
  out-fd @ close if, 115 die then,
  0 die ;
main
