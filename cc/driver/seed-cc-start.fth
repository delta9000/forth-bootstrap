\ Python-free bootstrap of the native compiler driver. From the repository root:
\     ./seed-forth < cc/driver/seed-cc-start.fth
\ writes build-out/seed-cc/seed-cc and build-out/seed-cc/seed-ar (scratch in
\ build-out/seed-cc/boot/). The seed is the only executable that runs: this
\ file forks and execs ./seed-forth once per step, feeding each a file that
\ concatenates the Forth compiler layers, a fixed driver from
\ cc/driver/seed-cc-boot/ and one C source. Steps, as cc/driver/seed-cc.c does them:
\   1. compile every chain/runtime/gcc-seed/*.c except math.c, then cc/driver/seed-cc.c
\      and cc/driver/seed-ar.c; compiler layers are forth/010-lib.fth and the sorted
\      cc/NNN-cc-*.fth except 120-cc-main.fth and 140-cc-link.fth
\   2. write the seven Forth runtime objects (syscall ... longjmp)
\   3. archive every runtime object except start.o into libseed.a, sorted
\      sources first, then the Forth objects
\   4. link start.o, the program object and libseed.a, for each program
\ Both directories are listed with getdents64, so new runtime files and
\ compiler layers are picked up without editing this file. Exit status 0 is
\ success; 1xx codes identify the failing operation below.
\ Minimal defining/control words below use the same primitives as forth/010-lib.fth.
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
: getdents 0 0 0 217 syscall6 ;
: mkdir 0 0 0 0 83 syscall6 ;
: rename 0 0 0 0 82 syscall6 ;
: exec 0 0 0 0 59 syscall6 ;
: wait4 0 0 0 0 61 syscall6 ;
: fork 0 0 0 0 0 0 57 syscall6 ;
: dup2 0 0 0 0 33 syscall6 ;
: checked-close close if, 101 die then, ;
\ Fixed names. Every path is relative to the repository root.
create d-build s0, build-out
create d-out s0, build-out/seed-cc
create d-boot s0, build-out/seed-cc/boot
create d-layers s0, cc
create layers-prefix s0, cc/
create no-prefix 0 c,
create d-runtime s0, chain/runtime/gcc-seed
create boot-prefix s0, build-out/seed-cc/boot/
create runtime-prefix s0, chain/runtime/gcc-seed/
create tools-prefix s0, cc/driver/
create input-path s0, build-out/seed-cc/boot/input
create unit-object s0, build-out/seed-cc/boot/unit.o
create seed-path s0, ./seed-forth
create seed-argv seed-path , 0 ,
create f010 s0, forth/010-lib.fth
create f020 s0, cc/020-cc-arena.fth
create f030 s0, cc/030-cc-io.fth
create f081 s0, cc/081-cc-object.fth
create f122 s0, cc/122-cc-sysv-runtime.fth
create f140 s0, cc/140-cc-link.fth
create f141 s0, cc/141-archive.fth
create runtime-unit s0, cc/driver/seed-cc-boot/runtime-unit.fth
create tools-unit s0, cc/driver/seed-cc-boot/tools-unit.fth
create sysrt-driver s0, cc/driver/seed-cc-boot/sysrt.fth
create archive-head s0, cc/driver/seed-cc-boot/archive-head.fth
create archive-tail s0, cc/driver/seed-cc-boot/archive-tail.fth
create link-cc s0, cc/driver/seed-cc-boot/link-seed-cc.fth
create link-ar s0, cc/driver/seed-cc-boot/link-seed-ar.fth
create seed-cc-c s0, seed-cc.c
create seed-ar-c s0, seed-ar.c
create k-cc s0, -cc-
create k-fth s0, .fth
create k-main s0, 120-cc-main.fth
create k-link s0, 140-cc-link.fth
create k-dot-c s0, .c
create k-math s0, math.c
create k-dot-o s0, .o
create t-create s0, create
create t-m s0, m
create t-s s0, s,
create t-lit s0, [lit]
create t-zero s0, 0
create t-c s0, c,
create t-add s0, arc-add-object
create m1 s0, syscall.o
create m2 s0, errno.o
create m3 s0, frame.o
create m4 s0, sigreturn.o
create m5 s0, setjmp.o
create m6 s0, longjmp.o
create sysrt-list m1 , m2 , m3 , m4 , m5 , m6 , 0 ,
create newline 10 c,
create space 32 c,
variable out-fd
variable source-fd
variable wp
variable wn
variable pid
variable status
variable dfd
variable dlen
variable dpos
variable rec
variable scan-prefix
variable names-here
variable scan-filter
variable scan-table
variable scan-count
variable layer-count
variable source-count
variable za
variable zb
variable sort-table
variable sort-count
variable si
variable sj
variable sv
variable pb
variable cursor
\ Keep data above the fixed VM pages, addressed through STATE, not constants.
state 4096 + here-addr !
create buffer 65536 allot
create dirbuf 32768 allot
create names-area 65536 allot
create layer-table 4096 allot
create source-table 4096 allot
create pathbuf 1024 allot
create srcbuf 1024 allot
\ ----- strings: NUL-terminated byte sequences
: zlen dup begin, dup c@ while, 1+ repeat, over - ;
: mem=
 >r zb ! za !
 begin, r@ while,
   za @ c@ zb @ c@ <> if, r> drop 0 exit, then,
   za @ 1+ za ! zb @ 1+ zb ! r> 1- >r
 repeat, r> drop 0 0= ;
: z= over zlen nip 1+ mem= ;
variable ea
variable eb
: ends? eb ! ea !
 ea @ zlen nip eb @ zlen nip
 2dup < if, 2drop 0 exit, then,
 - ea @ + eb @ eb @ zlen nip mem= ;
: z< zb ! za !
 begin, za @ c@ zb @ c@ = za @ c@ 0= 0= and while,
   za @ 1+ za ! zb @ 1+ zb !
 repeat,
 za @ c@ zb @ c@ < ;
\ ----- directory filters ( name -- flag )
: digit? 48 - 10 / 0= ;
: layer?
 dup zlen nip 11 < if, drop 0 exit, then,
 dup c@ digit? over 1+ c@ digit? and over 2 + c@ digit? and
 0= if, drop 0 exit, then,
 dup 3 + k-cc 4 mem= 0= if, drop 0 exit, then,
 dup k-fth ends? 0= if, drop 0 exit, then,
 dup k-main z= if, drop 0 exit, then,
 k-link z= 0= ;
: source?
 dup zlen nip 3 < if, drop 0 exit, then,
 dup k-dot-c ends? 0= if, drop 0 exit, then,
 k-math z= 0= ;
' layer? constant layer-xt
' source? constant source-xt
\ ----- directory listing into a table of name pointers
\ copy-prefix: put scan-prefix's bytes (no terminator) at names-here, so a
\ listed layer is stored as cc/NNN-cc-NAME.fth, openable from the root.
: copy-prefix
 scan-prefix @
 begin, dup c@ while,
   dup c@ names-here @ c! names-here @ 1+ names-here ! 1+
 repeat, drop ;
: copy-name
 names-here @ copy-prefix swap
 begin,
   dup c@ dup names-here @ c! names-here @ 1+ names-here !
 while, 1+ repeat, drop
 names-here @ names-area - 65000 < 0= if, 123 die then, ;
: table-add
 scan-count @ @ 500 < 0= if, 122 die then,
 scan-table @ scan-count @ @ 8 * + !
 scan-count @ @ 1+ scan-count @ ! ;
: scan
 65536 0 open dup 0< if, 120 die then, dfd !
 begin,
   dfd @ dirbuf 32768 getdents
   dup 0< if, 121 die then,
   dup
 while,
   dlen ! 0 dpos !
   begin, dpos @ dlen @ < while,
     dirbuf dpos @ + rec !
     rec @ 19 + scan-filter @ execute
     if, rec @ 19 + copy-name table-add then,
     rec @ 16 + c@ rec @ 17 + c@ 256 * + dpos @ + dpos !
   repeat,
 repeat, drop
 dfd @ checked-close ;
\ ----- insertion sort by bytes, as Python's sorted() orders these names
: slot 8 * sort-table @ + ;
: shift? sj @ 0= if, 0 exit, then, sv @ sj @ 1- slot @ z< ;
: sort
 sort-count ! sort-table ! 1 si !
 begin, si @ sort-count @ < while,
   si @ slot @ sv ! si @ sj !
   begin, shift? while,
     sj @ 1- slot @ sj @ slot ! sj @ 1- sj !
   repeat,
   sv @ sj @ slot ! si @ 1+ si !
 repeat, ;
\ ----- the seed's input file
: write-all
 wn ! wp !
 begin, wn @ while,
   out-fd @ wp @ wn @ write
   dup 0< if, 102 die then,
   dup 0= if, 103 die then,
   dup wp @ + wp ! wn @ swap - wn !
 repeat, ;
: put zlen write-all ;
: put-word put space 1 write-all ;
: nl newline 1 write-all ;
: append-file
 0 0 open dup 0< if, 104 die then, source-fd !
 begin,
   source-fd @ buffer 65536 read
   dup 0< if, 105 die then,
   dup
 while, buffer swap write-all repeat, drop
 source-fd @ checked-close ;
: new-input
 input-path 577 384 open dup 0< if, 106 die then, out-fd ! ;
: end-input out-fd @ checked-close ;
: module append-file nl ;
: compiler-layers
 f010 module
 0 cursor !
 begin, cursor @ layer-count @ < while,
   layer-table cursor @ 8 * + @ module
   cursor @ 1+ cursor !
 repeat, ;
: linker-layers f010 module f020 module f030 module f140 module f141 module ;
\ ----- run ./seed-forth on the input file; any failure stops the bootstrap
: run-seed
 fork dup 0< if, 109 die then,
 dup 0= if,
   drop
   input-path 0 0 open dup 0< if, 110 die then,
   dup 0 dup2 0< if, 111 die then,
   close drop
   seed-path seed-argv exec drop 112 die
 then,
 pid !
 pid @ status wait4 pid @ <> if, 113 die then,
 status @ if, 114 die then, ;
\ ----- path assembly in pathbuf / srcbuf
: pb-add begin, dup c@ while, dup c@ pb @ c! pb @ 1+ pb ! 1+ repeat, drop ;
: pb-end 0 pb @ c! ;
: pb-stem
 dup zlen nip 2 -
 begin, dup while, over c@ pb @ c! pb @ 1+ pb ! 1- swap 1+ swap repeat, 2drop ;
: object-path pathbuf pb ! boot-prefix pb-add pb-stem k-dot-o pb-add pb-end ;
: member-path pathbuf pb ! boot-prefix pb-add pb-add pb-end ;
: source-path srcbuf pb ! swap pb-add pb-add pb-end ;
: mkdir-ok
 493 mkdir dup 0 17 - = if, drop 0 then,
 if, 107 die then, ;
\ ----- the build steps
variable unit-name
variable unit-driver
variable unit-index
: compile-unit
 unit-driver ! dup unit-name ! source-path
 new-input compiler-layers unit-driver @ append-file srcbuf append-file end-input
 run-seed
 unit-name @ object-path
 unit-object pathbuf rename if, 115 die then, ;
: make-sysrt
 new-input f010 module f020 module f030 module f081 module f122 module
 sysrt-driver append-file end-input run-seed ;
: member-line
 t-create put-word t-m put-word t-s put-word pathbuf put-word
 t-lit put-word t-zero put-word t-c put-word t-m put-word t-add put nl ;
: make-archive
 new-input linker-layers archive-head append-file
 0 cursor !
 begin, cursor @ source-count @ < while,
   source-table cursor @ 8 * + @ object-path member-line
   cursor @ 1+ cursor !
 repeat,
 sysrt-list cursor !
 begin, cursor @ @ while,
   cursor @ @ member-path member-line
   cursor @ 8 + cursor !
 repeat,
 archive-tail append-file end-input run-seed ;
: link-program new-input linker-layers append-file end-input run-seed ;
: main
 d-build mkdir-ok d-out mkdir-ok d-boot mkdir-ok
 names-area names-here !
 layers-prefix scan-prefix ! layer-xt scan-filter ! layer-table scan-table ! layer-count scan-count ! d-layers scan
 no-prefix scan-prefix ! source-xt scan-filter ! source-table scan-table ! source-count scan-count ! d-runtime scan
 layer-table layer-count @ sort
 source-table source-count @ sort
 0 unit-index !
 begin, unit-index @ source-count @ < while,
   runtime-prefix source-table unit-index @ 8 * + @ runtime-unit compile-unit
   unit-index @ 1+ unit-index !
 repeat,
 tools-prefix seed-cc-c tools-unit compile-unit
 tools-prefix seed-ar-c tools-unit compile-unit
 make-sysrt make-archive
 link-cc link-program link-ar link-program
 0 die ;
main
