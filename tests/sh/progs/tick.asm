; tick — the kernel's tick count, in decimal, and a LF: what a script of
; sixty of these measures is the time from one command's start to the
; next's, which holds the shell's read, its parse, spawnv and the exit.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,(K_TICKS)
        ld      b,0
        call    out_dec16
        ld      a,10
        call    out_putc
        xor     a
        ret
        include "lib/out.inc"
        m6_bss
