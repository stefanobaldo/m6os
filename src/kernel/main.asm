; k_main — the boot sequence, once the loader has jumped here with the
; record filled: the interrupt vector, the console, memory. Then, if the
; record names an address, jump there — a program the loader put above the
; image — else halt with interrupts on, so the tick keeps counting for
; anyone watching it.

k_main:
        call    k_irq_init
        ei
        call    con_init
        call    mem_init
        jr      nz,k_boot_fail
        call    mem_summary
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

; k_boot_fail — A = code, C = the slot the code is about.
k_boot_fail:
        push    bc
        push    af
        ld      hl,s_bootfail
        call    con_puts
        pop     af
        call    con_hex8
        ld      hl,s_bootslot
        call    con_puts
        pop     bc
        ld      a,c
        call    con_hex8
        call    con_newline
        m6_verdict M6_FAIL
        jr      k_halt

s_bootfail: db  "FAIL boot code ",0
s_bootslot: db  " slot ",0
