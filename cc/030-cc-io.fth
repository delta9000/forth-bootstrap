\ 030-cc-io.fth — Input and source buffers, output-buffer emitter, file I/O
\ wrappers, and a few helpers shared by the preprocessor, lexer and symbol
\ table.  Loaded after 010-lib.fth and 020-cc-arena.fth.
\
\ Four responsibilities:
\   A. Read the input files into the 1 MiB cc-in-buf.  The preprocessor (040) turns
\      it into the 2 MiB cc-src-buf, which the lexer walks via peek/next.
\   B. Accumulate the output ELF into cc-out-buf via emit-byte / 4le / 8le
\      with patch-byte / patch-4le for back-fixups.
\   C. Write cc-out-buf to a path via 010-lib.fth's open/write/close.
\   D. Shared helpers: identifier classifiers, cell[], cc-name-find.
\
\ Depends on 010-lib.fth: constant, variable, create, allot, [lit], if,/then,/else,,
\   begin,/while,/repeat,, exit,, +, -, /, =, >, >=, 0=, 0<, +!, !, @, c!, c@,
\   drop, dup, over, swap, >r, r@, r>, read, write, open, close, bytes-eq;
\   020-cc-arena.fth: cc-src-pos, cc-src-line, cc-die, cc-check-cap.

\ ===========================================================================
\ A. Input buffer, source buffer + reader
\ ===========================================================================

\ cc-in-buf holds the input files exactly as read; nothing but the preprocessor reads it.
1048576 constant cc-in-cap
create cc-in-buf cc-in-cap allot
variable cc-in-len

\ cc-src-buf holds the preprocessed source the lexer reads: #include'd files
\ spliced in, directives blanked. Its capacity is twice the raw one.  The
\ reader's cursor is in the lexer's state block (020-cc-arena.fth).
2097152 constant cc-src-cap
create cc-src-buf cc-src-cap allot
variable cc-src-len

\ cc-src-init ( -- )  Empty the source buffer and rewind the reader.
: cc-src-init
  0 cc-src-len !
  0 cc-src-pos !
  1 cc-src-line ! ;

\ cc-read-all ( fd buf cap code -- n )  Read fd to end of file into buf and
\ return the byte count.  Each read asks for all the room left.  A buffer
\ that fills up dies with code: a full buffer and a longer file look the
\ same, so the data must leave at least one byte of buf unused.
variable cc-ra-fd
variable cc-ra-buf
variable cc-ra-cap
variable cc-ra-code
variable cc-ra-n
: cc-read-all
  cc-ra-code ! cc-ra-cap ! cc-ra-buf ! cc-ra-fd !
  0 cc-ra-n !
  begin,
    cc-ra-fd @  cc-ra-buf @ cc-ra-n @ +  cc-ra-cap @ cc-ra-n @ -  read
    dup 0 >
  while,
    cc-ra-n +!
    cc-ra-n @ 1+ cc-ra-cap @ cc-ra-code @ cc-check-cap   \ full: die
  repeat,
  drop cc-ra-n @ ;

\ cc-eof? ( -- f )  -1 if pos has reached len; 0 otherwise.
: cc-eof?  cc-src-pos @ cc-src-len @ >= ;

\ cc-peek-char ( -- c )  Returns byte at the current position; 0 at EOF.
\ Both arms of if,/else, produce exactly one value, so stack stays balanced.
: cc-peek-char
  cc-eof? if,
    0
  else,
    cc-src-buf cc-src-pos @ + c@
  then, ;

\ cc-next-char ( -- c )  Returns current byte and advances pos.
\ Tracks line number when consuming '\n' (10).
: cc-next-char
  cc-peek-char
  1 cc-src-pos +!
  dup nl = if,
    1 cc-src-line +!
  then, ;

\ ===========================================================================
\ B. Output buffer + ELF-aware emit helpers
\ ===========================================================================

\ 1 MiB output cap — fits any reasonable ELF the C-subset compiler emits.
1048576 constant cc-out-cap
create cc-out-buf cc-out-cap allot
variable cc-out-pos

\ cc-out-init ( -- )
: cc-out-init  0 cc-out-pos ! ;

\ cc-emit-byte ( b -- )  Append a byte at cc-out-buf[cc-out-pos++]; die 21
\ if the buffer is full.
: cc-emit-byte
  cc-out-pos @ 1+ cc-out-cap [lit] 21 cc-check-cap
  cc-out-buf cc-out-pos @ + c!
  1 cc-out-pos +! ;

\ x{ hh ... }  010-lib.fth's c{ with cc-emit-byte as the sink: `x{ 48 89 f8 }`
\ emits what `[lit] 72 cc-emit-byte [lit] 137 cc-emit-byte [lit] 248
\ cc-emit-byte` emits, and compiles to the same code.
' cc-emit-byte constant cc-emit-byte-xt
: x{  cc-emit-byte-xt hex{ ; immediate

\ cc-emit-4le ( v -- )  Emit low 4 bytes of v in little-endian.
: cc-emit-4le
  dup cc-emit-byte                              \ byte 0
  256 / dup cc-emit-byte                        \ byte 1
  256 / dup cc-emit-byte                        \ byte 2
  256 / cc-emit-byte ;                          \ byte 3

\ cc-emit-8le ( v -- )  Emit all 8 bytes of v in little-endian.
\ Reuses cc-emit-4le for both halves; shifts by 32 between halves.
: cc-emit-8le
  dup cc-emit-4le                                              \ low 4 bytes
  256 / 256 / 256 / 256 /                                      \ shift right 32
  cc-emit-4le ;                                                \ high 4 bytes

\ cc-out-patch-byte ( v offset -- )  Overwrite cc-out-buf[offset] with low byte of v.
: cc-out-patch-byte  cc-out-buf + c! ;

\ cc-out-patch-4le ( v offset -- )  Overwrite 4 bytes at offset (LE).
\ Stash offset on the return stack so we can compute offset+1, +2, +3.
: cc-out-patch-4le
  >r                                                  ( v       ; R: offset )
  dup r@                       cc-out-patch-byte      ( v       ; R: offset )
  256 / dup r@ 1+ cc-out-patch-byte             ( v>>8    ; R: offset )
  256 / dup r@ 2 + cc-out-patch-byte      ( v>>16   ; R: offset )
  256 /     r> 3 + cc-out-patch-byte ;    ( v>>24>>8 popped )

\ ===========================================================================
\ D. Helpers shared by the preprocessor, lexer and symbol table
\ ===========================================================================

\ ident-start? ( c -- f )  letter or '_'.
: ident-start?
  dup alpha?  swap [char] _ = or ;

\ ident-cont? ( c -- f )  ident-start? or digit.
: ident-cont?
  dup ident-start?  swap digit? or ;

\ cell[] ( i arr -- addr )  Address of cell i of an array of 8-byte cells —
\ how every parallel-array table (macros, symbols, ...) is indexed.
: cell[]  swap 8 * + ;

\ cc-name-find ( a u addrs lens count -- i | -1 )  Look the name a u up in
\ a table kept as two parallel arrays, addrs (where each name's bytes are)
\ and lens (how many), of count entries.  Walks from the newest entry to the
\ oldest and returns the first match, so a later entry hides an earlier one
\ of the same name.  The loop index runs down to -1, so "not found" is
\ simply the final index.  The needle waits in globals so the loop body can
\ reach it without deep stack juggling.
variable cc-nf-a
variable cc-nf-u
variable cc-nf-addrs
variable cc-nf-lens
: cc-name-find
  >r  cc-nf-lens ! cc-nf-addrs ! cc-nf-u ! cc-nf-a !
  r> 1-                                          ( i = count-1 )
  begin,
    dup 0< 0=
  while,
    dup cc-nf-lens @ cell[] @  cc-nf-u @ = if,   \ same length?
      dup cc-nf-addrs @ cell[] @  cc-nf-a @  cc-nf-u @
      bytes-eq if, exit, then,                   \ found: return i
    then,
    1-                                           \ i--
  repeat, ;                                      \ not found: i = -1

\ cc-name-hash ( a u -- h )  djb2 over the name, as the linker hashes
\ symbols (140-cc-link.fth), masked to cc-name-buckets.  The macro and
\ symbol tables (040, 070) keep, per hash, their newest entry in a bucket
\ and link the older ones behind it, so a lookup compares only the names
\ that share its hash.
4096 constant cc-name-buckets
: cc-name-hash
  5381 >r
  begin, dup while,
    over c@ r> 33 * + >r
    1- swap 1+ swap
  repeat, 2drop
  r> cc-name-buckets 1- and ;

\ Round before mmap only after rejecting zero, negative and overflowing sizes.
\ Requests are policy constants at callers; this helper never grows a buffer.
: cc-workspace-round ( bytes code -- page-bytes )
  >r dup [lit] 0 <= if, r@ cc-die then,
  dup [lit] 9223372036854771712 > if, r@ cc-die then,
  4095 + 4096 / 4096 * r> drop ;
\ The memory comes from the break (brk-alloc, forth/010-lib.fth, which
\ answers 0 when it cannot give it): builder-hex0 has no mmap.
: cc-workspace-map ( bytes code -- address )
  >r r@ cc-workspace-round brk-alloc
  dup [lit] 0 <= if, r@ cc-die then, r> drop ;

\ ===========================================================================
\ E. The C source files
\ ===========================================================================
\ The C source comes from files named beforehand: builder-hex0's
\ descriptor 0 is the boot disk's command stream and never ends.
\
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

\ cc-load-files ( -- )  Read the listed files into cc-in-buf, in order,
\ with nothing between them.  Rewinds the reader first, so an error here
\ reports line 1.
: cc-load-files
  cc-src-init
  [lit] 0 cc-in-len !
  [lit] 0
  begin, dup cc-input-count @ < while,
    dup cc-input-files cell[] @ cc-load-file
    1+
  repeat,
  drop ;
