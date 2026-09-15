; stamp — waits for one byte on descriptor 0, then prints the kernel's
; tick count: the last stage of a pipeline, stamping when its first
; input arrives.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   xor     a
        ld      hl,byte
        ld      bc,1
        sys     SYS_READ
        ld      hl,(K_TICKS)
        ld      b,0
        call    out_dec16
        ld      a,10
        call    out_putc
        xor     a
        ret
        include "lib/out.inc"
        m6_bss
        bss     byte,1
