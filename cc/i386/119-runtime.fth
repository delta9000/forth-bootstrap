\ 119-runtime.fth — the one kernel primitive of an i386 program.
\
\ Loaded in place of 119-cc-native-runtime.fth.  It emits
\ __native_syscall (n, a1, a2, a3, a4, a5, a6): Linux i386 call n through
\ int 0x80, returning eax as the kernel gives it (-errno on failure),
\ sign-extended into edx.  A C library defines read, exit and the rest on
\ it (tinycc/mes-libc-native-i386.c, tinycc/m2libc-native-i386.c).
\
\ It is a leaf function with no frame.  Every argument occupies an 8-byte
\ caller-owned stack slot, and after the push below the first is at
\ [esp+8].  The sixth argument travels in ebp, the caller's frame base, so
\ that is saved.  The other registers hold nothing across a call, which
\ builder-hex0 needs: some of its calls return with ebx or esi changed.
\ Nothing lives below esp either, where the kernel's own frame may land.

\ cc-native-syscall-any ( -- addr )  The x86-64 runtime emits the primitive
\ only when a driver sets this; here there is nothing else to emit.  The
\ variable stays so that one driver (tinycc/tool-compile.fth) serves both.
variable cc-native-syscall-any
create cc-native-name-syscall s, __native_syscall

: cc-native-runtime
  cc-native-name-syscall [lit] 16 ty-long [lit] 0 ty-make
  sk-func swap cc-here-vaddr cc-sym-add drop
  x{ 55 }                                         \ push ebp
  x{ 8b 44 24 08 }                                \ mov eax, dword [esp+8]
  x{ 8b 5c 24 10 }                                \ mov ebx, dword [esp+16]
  x{ 8b 4c 24 18 }                                \ mov ecx, dword [esp+24]
  x{ 8b 54 24 20 }                                \ mov edx, dword [esp+32]
  x{ 8b 74 24 28 }                                \ mov esi, dword [esp+40]
  x{ 8b 7c 24 30 }                                \ mov edi, dword [esp+48]
  x{ 8b 6c 24 38 }                                \ mov ebp, dword [esp+56]
  x{ cd 80 }                                      \ int 0x80
  x{ 5d }                                         \ pop ebp
  x{ 99 }                                         \ cdq
  x{ c3 } ;                                       \ ret
' cc-native-runtime is cc-native-runtime-fwd
