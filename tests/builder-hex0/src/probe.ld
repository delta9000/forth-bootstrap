/* One RWX PT_LOAD at 0x08048000 holding the ELF and program headers,
   so builder-hex0's execve (which copies every header and takes brk
   from the last) sees exactly one segment. */
ENTRY(_start)
PHDRS { all PT_LOAD FILEHDR PHDRS FLAGS(7); }
SECTIONS {
  . = 0x08048000 + SIZEOF_HEADERS;
  .text : { *(.text .text.*) } :all
  .rodata : { *(.rodata .rodata.*) } :all
  .data : { *(.data .data.*) } :all
  edata_mark = .;
  .bss : { *(.bss .bss.* COMMON) } :all
  end_mark = .;
  /DISCARD/ : { *(.note*) *(.eh_frame*) *(.comment) *(.got*) *(.igot*) *(.rel*) *(.dynamic) *(.interp) }
}
