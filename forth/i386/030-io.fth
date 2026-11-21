\ forth/i386/030-io.fth — memory and C source for the compiler on the i386
\ seed.
\
\ Loaded after cc/030-cc-io.fth, which is the same file for both hosts.
\ Two things in it reach the kernel in a way builder-hex0 does not have
\ (tests/builder-hex0/README.md): its workspaces come from mmap, which
\ answers 0 there, and the C source is whatever follows the Forth text on
\ descriptor 0, which there is the boot disk's command stream and never
\ ends.  Here the workspaces come from the break and the C source from
\ files named beforehand.
\
\ Depends on forth/i386/010-lib.fth (brk-alloc, open, close) and
\ cc/030-cc-io.fth (cc-workspace-syscall-fwd, cc-src-init, cc-read-all,
\ cc-in-buf, cc-in-cap, cc-in-len, cell[]).

\ cc-workspace-map (030) asks its deferred word for page-bytes of memory
\ and dies when the answer is 0 or less; brk-alloc answers 0 when it
\ cannot give them.
' brk-alloc is cc-workspace-syscall-fwd

\ cc-input-file ( zaddr -- )  Add a NUL-terminated path to the list of C
\ source files, at most 8; a ninth dies with 20, the code for input that
\ does not fit.
create cc-input-files  [lit] 64 allot             \ 8 cells
variable cc-input-count
: cc-input-file
  cc-input-count @ 1+ [lit] 8 [lit] 20 cc-check-cap
  cc-input-count @ cc-input-files cell[] !
  [lit] 1 cc-input-count +! ;

\ cc-load-file ( zaddr -- )  Append the file's bytes to cc-in-buf, directly
\ after those already there.  Dies 20 if it cannot be opened or the buffer
\ fills.
: cc-load-file
  [lit] 0 [lit] 0 open                            ( fd )  \ O_RDONLY
  dup 0< if, [lit] 20 cc-die then,
  dup  cc-in-buf cc-in-len @ +  cc-in-cap cc-in-len @ -  [lit] 20 cc-read-all
  cc-in-len +!
  close drop ;

\ cc-load-stdin ( -- )  030's word reads descriptor 0 to its end.  This one
\ reads the listed files, in order, with nothing between them: the bytes
\ the x86-64 host finds on its standard input after the Forth text, where
\ catm has joined the same files.  The drivers call it by this name.
: cc-load-stdin
  cc-src-init
  [lit] 0 cc-in-len !
  [lit] 0
  begin, dup cc-input-count @ < while,
    dup cc-input-files cell[] @ cc-load-file
    1+
  repeat,
  drop ;
