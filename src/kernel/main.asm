; k_main — the boot sequence, once the loader has jumped here with the
; record filled: the interrupt vector, then the console. Then, if the
; record names an address, jump there — a program the loader put above the
; image — else halt with interrupts on, so the tick keeps counting for
; anyone watching it.

k_main:
        call    k_irq_init
        ei
        call    con_init
        ld      hl,(K_REC+KR_TEST)
        ld      a,h
        or      l
        jr      z,k_halt
        jp      (hl)

; k_halt — nothing left to do.
k_halt:
        ei
        halt
        jr      k_halt
