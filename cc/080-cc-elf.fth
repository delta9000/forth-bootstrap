\ 080-cc-elf.fth — ELF32 header + program header of the output.
\
\ Layout: 52-byte Elf32_Ehdr + 32-byte Elf32_Phdr (one PT_LOAD) = 84 bytes.
\ Code begins at vaddr 0x08048054, file offset 84.  0x08048000 is where
\ builder-hex0 puts a process and where Linux i386 programs traditionally
\ load.
\
\ Depends on 030-cc-io.fth (x{, cc-emit-4le, cc-out-pos, cc-out-patch-4le).

[lit] 134512640 constant cc-base-vaddr           \ 0x08048000
[lit] 134512724 constant cc-entry-vaddr          \ 0x08048054

\ cc-here-vaddr ( -- vaddr )  The address the next emitted byte will have
\ when the output runs: its file offset (cc-out-pos) plus the load address.
: cc-here-vaddr  cc-base-vaddr cc-out-pos @ + ;

\ p_filesz lives at file offset 68, 4 bytes LE; p_memsz at 72.
[lit] 68 constant cc-filesz-offset
[lit] 72 constant cc-memsz-offset

\ cc-emit-elf-header ( -- )  Emit the 84-byte header at start of cc-out-buf.
\ p_filesz and p_memsz are left 0 (patched in cc-finalize-elf).
: cc-emit-elf-header
  x{ 7f 45 4c 46 }                                \ e_ident: magic
  x{ 01 01 01 00 }                                \ 32-bit, little-endian, version 1, System V
  x{ 00 00 00 00 00 00 00 00 }                    \ e_ident padding
  x{ 02 00 }                                      \ e_type = ET_EXEC
  x{ 03 00 }                                      \ e_machine = EM_386
  [lit] 1 cc-emit-4le                             \ e_version
  cc-entry-vaddr cc-emit-4le                      \ e_entry = 0x08048054
  [lit] 52 cc-emit-4le                            \ e_phoff
  [lit] 0 cc-emit-4le                             \ e_shoff
  [lit] 0 cc-emit-4le                             \ e_flags
  x{ 34 00 }                                      \ e_ehsize = 52
  x{ 20 00 }                                      \ e_phentsize = 32
  x{ 01 00 }                                      \ e_phnum = 1
  x{ 00 00 00 00 00 00 }                          \ e_shentsize, e_shnum, e_shstrndx
  \ Program header (32 bytes, one PT_LOAD):
  [lit] 1 cc-emit-4le                             \ p_type = PT_LOAD
  [lit] 0 cc-emit-4le                             \ p_offset
  cc-base-vaddr cc-emit-4le                       \ p_vaddr = 0x08048000
  cc-base-vaddr cc-emit-4le                       \ p_paddr
  [lit] 0 cc-emit-4le                             \ p_filesz (patched later)
  [lit] 0 cc-emit-4le                             \ p_memsz (patched later)
  [lit] 7 cc-emit-4le                             \ p_flags = R|W|X
  [lit] 4096 cc-emit-4le ;                        \ p_align = 0x1000

\ cc-bss-size ( -- a )  Bytes of zeroed memory the program needs after its
\ file image (its bss, 090-cc-emit.fth); cc-finalize-globals sets it.
variable cc-bss-size

\ cc-bss-end-patch ( -- a )  File offset of the imm32 in the entry stub
\ (117-cc-native-program.fth) that holds the address just past the bss.
variable cc-bss-end-patch

\ cc-finalize-elf ( -- )  After codegen: p_filesz is the file's length,
\ p_memsz adds the bss, and the entry stub learns where the bss ends.
: cc-finalize-elf
  cc-out-pos @ cc-filesz-offset cc-out-patch-4le
  cc-out-pos @ cc-bss-size @ + cc-memsz-offset cc-out-patch-4le
  cc-here-vaddr cc-bss-size @ + cc-bss-end-patch @ cc-out-patch-4le ;
