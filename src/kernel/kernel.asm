; The resident kernel image: everything that lives in page 3 once m6 owns
; the machine. Assembled at K_BASE into build/kernel.bin; a loader copies it
; there after filling the capture record, then jumps to K_ENTRY.
;
; What is here today: slot switching, the interrupt entry, the console, the
; Nextor driver call, and k_main — the second half of tests/takeover, which
; is why the image also includes the tests' shared definitions (mailbox,
; debug device). The stack is the last thing in the image and its top is
; K_END.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"

        org     K_BASE
        jp      k_main
        jp      k_isr
k_ticks:
        dw      0
        dw      k_end
        dw      k_sslot_stub
k_rec:  ds      KREC_SIZE
        ASSERT  k_ticks == K_TICKS
        ASSERT  k_rec == K_REC

; The driver module's two external needs, supplied by this image: its own
; slot switch, and the RAM slot for page 1 as captured.
nx_enaslt       equ k_enaslt
nx_ramslot1     equ K_REC+KR_RAMAD+1
        define  NX_RW_ONLY              ; nx_find needs the BDOS; not here

        include "kernel/slot.asm"
        include "kernel/irq.asm"
        include "kernel/con.asm"
        include "nextor/abi2.asm"
        include "kernel/main.asm"

k_stack:
        ds      256
k_end:
