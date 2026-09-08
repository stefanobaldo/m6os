; k_main — the boot sequence, once the loader has jumped here with the
; record filled: the interrupt vector, the console, memory, the switched
; part of the kernel, the process table with the kernel as process 0, the
; loader's memory released, the summary of the memory printed from the
; switched part. Then, if the record names an address, jump there — a
; program the loader put above the image, which runs as process 0 — else
; halt with interrupts on, so the tick keeps counting for anyone watching
; it.

k_main:
        call    k_irq_init
        ei
        call    con_init
        ld      hl,K_REC+KR_SEG64K      ; what is in each page now
        ld      de,k_map
        ld      bc,4
        ldir
        call    mem_init
        jr      nz,k_boot_fail
        call    kwin_load
        jr      nz,k_boot_fail
        call    sched_init
        call    sched_release_boot
        ld      a,(K_KSEG)
        or      a
        jr      z,.nosummary            ; no switched part: no summary
        kwin_call KS_SUMMARY
.nosummary:
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

; k_boot_fail — A = code; C = the slot the code is about, for F8.
k_boot_fail:
        push    bc
        push    af
        ld      hl,s_bootfail
        call    con_puts
        pop     af
        push    af
        call    con_hex8
        pop     af
        pop     bc
        cp      0F8h
        jr      nz,.nl
        ld      hl,s_bootslot
        call    con_puts
        ld      a,c
        call    con_hex8
.nl:    call    con_newline
        m6_verdict M6_FAIL
        jr      k_halt

s_bootfail: db  "FAIL boot code ",0
s_bootslot: db  " slot ",0
