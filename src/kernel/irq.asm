; The interrupt entry.
;
; The Z80 runs in mode 1: every interrupt jumps to 0038h, which the loader
; and k_irq_init point at k_isr. The VDP is the only interrupt source on the
; base machine; it raises INT at every vertical retrace (60 Hz) and holds it
; until status register 0 is read, so reading S#0 is the acknowledgement.
; Then the tick is counted and the keyboard scanned when it is due — a
; reader woken by a key counts as runnable for the decision that follows —
; and the CPU changes hands when it may: another
; process is runnable, and the one interrupted was in user space — its PC
; and its stack pointer both below page 3. A PC in page 3 is the resident,
; a syscall body or a stub; a stack pointer in page 3 is the switched image
; on the syscall stack, or process 0. The kernel is never preempted; a tick
; that lands inside a syscall leaves the switch to the next one. The BIOS's
; own handler — hooks, keyboard scan every third tick — never runs again.

; k_irq_init — install the vector, select S#0, zero the counter. Call with
; interrupts disabled; the caller enables them. Corrupts AF, BC, HL.
k_irq_init:
        ld      a,0C3h
        ld      (K_INTRPT),a
        ld      hl,K_ISR
        ld      (K_INTRPT+1),hl
        ld      a,(K_REC+KR_VDPRD)
        inc     a
        ld      (k_isr_in+1),a          ; the status port, into the IN below
        ld      a,(K_REC+KR_VDPWR)
        inc     a
        ld      c,a
        xor     a
        out     (c),a                   ; R#15 = 0: S#0 is what IN reads
        ld      a,80h+15
        out     (c),a
        ld      hl,0
        ld      (K_TICKS),hl
        ret

; k_isr — acknowledge the VDP, count, and switch when it is time.
; Preserves everything the interrupted code will see.
k_isr:
        push    af
k_isr_in:
        in      a,(0)                   ; S#0; the port is patched at init
        push    hl
        ld      hl,(K_TICKS)
        inc     hl
        ld      (K_TICKS),hl
        call    kbd_tick                ; the keyboard: a scan when due,
                                        ; readers woken into the ring
        ld      a,(k_nrun)
        cp      2
        jr      c,.ret                  ; nobody else to run
        ld      hl,5
        add     hl,sp                   ; [L][H][F][A][PCl][PCh]: hl -> PCh
        ld      a,(hl)
        cp      0C0h
        jr      nc,.ret                 ; PC in page 3: the kernel
        ld      a,l
        sub     5
        ld      a,h
        sbc     a,0                     ; a = the interrupted SP's high byte
        cp      0C0h
        jr      nc,.ret                 ; SP in page 3: the switched image
                                        ; on the syscall stack, or process 0
        jp      sched_save_switch
.ret:   pop     hl
        pop     af
        ei
        reti
