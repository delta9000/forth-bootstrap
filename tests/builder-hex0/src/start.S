/* Entry: record every register, eflags, segment selectors and esp exactly
   as builder-hex0's execve left them, before any C runs. */
        .text
        .globl _start
_start:
        mov %eax, entry_regs+0
        mov %ebx, entry_regs+4
        mov %ecx, entry_regs+8
        mov %edx, entry_regs+12
        mov %esi, entry_regs+16
        mov %edi, entry_regs+20
        mov %ebp, entry_regs+24
        mov %esp, entry_regs+28
        pushf
        popl entry_regs+32
        xor %eax, %eax
        mov %cs, %ax
        mov %eax, entry_regs+36
        mov %ss, %ax
        mov %eax, entry_regs+40
        mov %ds, %ax
        mov %eax, entry_regs+44
        mov %esp, %eax          /* eax = &argc */
        lea 4(%eax), %ecx       /* argv */
        mov (%eax), %edx        /* argc */
        lea 8(%eax,%edx,4), %ebx /* envp = argv + argc + 1 */
        push %ebx
        push %ecx
        push %edx
        call main
        mov %eax, %ebx
        mov $1, %eax
        int $0x80
1:      jmp 1b

/* long sc(n, a, b, c, d, e, f): int 0x80 with eax=n, ebx..ebp=a..f.
   Records ebx, ecx, edx, esi, edi, ebp as the kernel returned them in
   post_regs[0..5], then restores the C callee-saved registers. */
        .globl sc
sc:
        push %ebp
        push %ebx
        push %esi
        push %edi
        mov 20(%esp), %eax
        mov 24(%esp), %ebx
        mov 28(%esp), %ecx
        mov 32(%esp), %edx
        mov 36(%esp), %esi
        mov 40(%esp), %edi
        mov 44(%esp), %ebp
        int $0x80
        mov %ebx, post_regs+0
        mov %ecx, post_regs+4
        mov %edx, post_regs+8
        mov %esi, post_regs+12
        mov %edi, post_regs+16
        mov %ebp, post_regs+20
        pop %edi
        pop %esi
        pop %ebx
        pop %ebp
        ret

/* long canary(depth, pattern, n, a, b, c): fill [esp-depth, esp) with
   pattern (no stack use between fill and check), do int 0x80 with
   eax=n, ebx=a, ecx=b, edx=c (n = -1: no syscall, spin a times instead),
   then scan from esp-depth upward and return esp - (lowest changed byte),
   0 if none.  canary_count gets the number of changed bytes, canary_eax
   the syscall's return. */
        .globl canary
canary:
        push %ebp
        push %ebx
        push %esi
        push %edi
        mov 20(%esp), %esi      /* depth */
        mov 24(%esp), %eax      /* pattern byte */
        mov 28(%esp), %ebp      /* n */
        mov 32(%esp), %ebx
        mov 36(%esp), %ecx
        mov 40(%esp), %edx
        mov %ecx, canary_tmp
        /* fill */
        mov %esp, %edi
        sub %esi, %edi
        mov %esi, %ecx
        mov %edi, canary_lo
        rep stosb
        mov canary_tmp, %ecx
        mov %ebp, %eax
        cmp $-1, %eax
        jne 2f
        /* spin ebx iterations, no stack use */
3:      dec %ebx
        jnz 3b
        xor %eax, %eax
        jmp 4f
2:      int $0x80
4:      mov %eax, canary_eax
        /* scan */
        mov canary_lo, %edi
        mov 24(%esp), %eax
        xor %edx, %edx          /* count */
        xor %ebx, %ebx          /* lowest changed */
5:      cmp %esp, %edi
        jae 7f
        cmpb %al, (%edi)
        je 6f
        inc %edx
        test %ebx, %ebx
        jnz 6f
        mov %edi, %ebx
6:      inc %edi
        jmp 5b
7:      mov %edx, canary_count
        xor %eax, %eax
        test %ebx, %ebx
        jz 8f
        mov %esp, %eax
        sub %ebx, %eax
8:      pop %edi
        pop %esi
        pop %ebx
        pop %ebp
        ret

        .globl rdtsc64
rdtsc64:
        rdtsc
        ret

        .globl read_cr0
read_cr0:
        mov %cr0, %eax
        ret

        .globl get_esp
get_esp:
        lea 4(%esp), %eax
        ret

        .bss
        .globl entry_regs, post_regs, canary_count, canary_eax
entry_regs: .space 48
post_regs:  .space 24
canary_count: .space 4
canary_eax: .space 4
canary_lo:  .space 4
canary_tmp: .space 4

/* irq probe: counting handlers for vectors 8..15, no EOI (like the
   kernel's stub at vector 8). */
        .text
        .globl irq_handlers
        .align 16
irq_handlers:
        .irp v,0,1,2,3,4,5,6,7
        .align 16
        incl irq_counts+4*\v
        iret
        .endr
        .globl inb_, outb_, sidt_
inb_:   mov 4(%esp), %edx
        xor %eax, %eax
        inb %dx, %al
        ret
outb_:  mov 4(%esp), %edx
        mov 8(%esp), %eax
        outb %al, %dx
        ret
sidt_:  mov 4(%esp), %eax
        sidt (%eax)
        ret
        .bss
        .globl irq_counts
irq_counts: .space 32
