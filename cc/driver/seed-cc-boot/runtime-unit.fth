\ seed-cc bootstrap: compile one chain/runtime/gcc-seed C file (on stdin after
\ this text) to build-out/seed-cc/boot/unit.o.  The same driver words, arena
\ and include order as cc/driver/seed-cc.c; cc/driver/seed-cc-start.fth renames the
\ object.  Quoted includes resolve from chain/runtime/gcc-seed/.
cc-sysv-object-enable
[lit] 22020096 cc-arena-map
cc-io-direct-workspace cc-prep-direct-workspace
cc-om-direct-workspace cc-label-direct-workspace
cc-obj-direct-workspace cc-gfixup-direct-workspace
create driver-output s, build-out/seed-cc/boot/unit.o [lit] 0 c,
create driver-source s, chain/runtime/gcc-seed/unit.c [lit] 0 c,
driver-source [lit] 29 cc-prep-source-name
create driver-inc-0 s, chain/runtime/gcc-seed/include [lit] 0 c,
driver-inc-0 [lit] 30 cc-prep-add-include
: driver-main cc-load-stdin cc-preprocess cc-out-init cc-globals-init
cc-sysv-object-program driver-output cc-obj-write bye ;
driver-main
