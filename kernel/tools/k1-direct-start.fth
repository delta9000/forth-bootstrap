\ K1 built by seed Forth: the launcher. Run from the repository root:
\     ./seed-forth < kernel/tools/k1-direct-start.fth
\ The seed is the only pre-existing executable. Linux or K0 supplies the
\ syscall substrate. This builds the recipe
\ runner with the Forth compiler, then runs it on kernel/tools/k1-direct.recipe,
\ which builds K1 with the Forth compiler, kernel/tools/obj-asm.fth and the Forth
\ linker (build-out/k1-direct/k1).  Under K0, kernel/k1/mkboot.py appends
\ the line that starts K1.
\ Minimal defining/control words below use the same primitives as forth/010-lib.fth.
: latest state 8 + ;
: here-addr state 16 + ;
: here here-addr @ ;
: , here ! here 8 + here-addr ! ;
: c, here c! here 1 + here-addr ! ;
: ' token find ;
: over >r dup r> swap ;
: - dup nand 1 + + ;
: and nand dup nand ;
: 1+ 1 + ;
: 1- 1 - ;
: = - 0= ;
: <> = 0= ;
: 0< 9223372036854775808 / 0= 0= ;
: > swap - 0< ;
: 2dup over over ;
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
: begin, here ; immediate
: while, 0branch-xt call, here 0 , ; immediate
: repeat, swap branch-xt call, , here swap ! ; immediate
: create : here 19 + push-body, 0 state ! ;
: variable create 0 , ;
: allot here-addr @ + here-addr ! ;
: s0,
 token begin, dup while, over c@ c, 1- swap 1+ swap repeat,
 2drop 0 c, ;
: die 0 0 0 0 0 60 syscall6 ;
: open 0 0 0 2 syscall6 ;
: read 0 0 0 0 syscall6 ;
: write 0 0 0 1 syscall6 ;
: close 0 0 0 0 0 3 syscall6 ;
: checked-close close if, 101 die then, ;
: unlink 0 0 0 0 0 87 syscall6 ;
: exec 0 0 0 0 59 syscall6 ;
create build-dir s0, build-out
create input-path s0, build-out/amd64-runner.input
create output-path s0, build-out/amd64-runner
create cc-path s0, /tmp/cc-out
create seed-path s0, ./seed-forth
create runner-source s0, kernel/tools/amd64-runner.c
create f010 s0, forth/010-lib.fth
create f020 s0, cc/020-cc-arena.fth
create f030 s0, cc/030-cc-io.fth
create f040 s0, cc/040-cc-prep.fth
create f050 s0, cc/050-cc-lex.fth
create f060 s0, cc/060-cc-types.fth
create f070 s0, cc/070-cc-sym.fth
create f080 s0, cc/080-cc-elf.fth
create f090 s0, cc/090-cc-emit.fth
create f100 s0, cc/100-cc-expr.fth
create f110 s0, cc/110-cc-decl.fth
create f112 s0, cc/112-cc-stmt.fth
create f114 s0, cc/114-cc-func.fth
create f116 s0, cc/116-cc-prog.fth
create runner-syscalls s0, kernel/tools/amd64-syscalls.fth
create f120 s0, cc/120-cc-main.fth
create files
 f010 , f020 , f030 , f040 , f050 , f060 , f070 , f080 , f090 ,
 f100 , f110 , f112 , f114 , f116 , runner-syscalls , f120 , runner-source , 0 ,
create seed-argv seed-path , 0 ,
create recipe-option s0, --recipe
create recipe-path s0, kernel/tools/k1-direct.recipe
create runner-argv output-path , recipe-option , recipe-path , 0 ,
variable source-fd
variable output-fd
variable pointer
variable count
variable file-cursor
variable pid
variable status
\ Keep data above the fixed VM pages, addressed through STATE, not constants.
state 4096 + here-addr !
create buffer 65536 allot
: write-all
 count ! buffer pointer !
 begin, count @ while,
   output-fd @ pointer @ count @ write
   dup 0< if, 102 die then,
   dup 0= if, 103 die then,
   dup pointer @ + pointer ! count @ swap - count !
 repeat, ;
: append-file
 0 0 open dup 0< if, 104 die then, source-fd !
 begin,
   source-fd @ buffer 65536 read
   dup 0< if, 105 die then,
   dup
 while, write-all repeat, drop
 source-fd @ checked-close ;
: new-output
 577 384 open dup 0< if, 106 die then, output-fd ! ;
: main
 build-dir 493 0 0 0 0 83 syscall6
 dup 0 17 - = if, drop 0 then,
 if, 107 die then,
 input-path new-output
 files file-cursor !
 begin, file-cursor @ @ dup while,
   append-file file-cursor @ 8 + file-cursor !
 repeat, drop
 output-fd @ checked-close
 cc-path unlink dup 0 2 - = if, drop 0 then,
 if, 108 die then,
 0 0 0 0 0 0 57 syscall6
 dup 0< if, 109 die then,
 dup 0= if,
   drop
   input-path 0 0 open dup 0< if, 110 die then,
   dup source-fd ! 0 0 0 0 0 33 syscall6
   if, 111 die then,
   source-fd @ checked-close
   seed-path seed-argv exec drop 112 die
 then,
 pid !
 pid @ status 0 0 0 0 61 syscall6
 pid @ <> if, 113 die then,
 status @ if, 114 die then,
 \ /tmp can be another filesystem: copy rather than assume rename works.
 output-path new-output cc-path append-file output-fd @ checked-close
 cc-path unlink if, 115 die then,
 output-path 493 0 0 0 0 90 syscall6
 if, 116 die then,
 output-path runner-argv exec drop 117 die ;
main
