; The resident kernel image: everything that lives in page 3 once m6 owns
; the machine. Assembled at K_BASE into build/kernel.bin; a loader copies it
; there after filling the capture record, then jumps to K_ENTRY.
;
; What is here: slot switching, the interrupt entry, the console, the
; Nextor driver call, and k_main, the boot sequence, which ends by jumping
; wherever the record says. The image includes the tests' shared
; definitions for the mailbox and the debug device. The stack is the last
; thing in the image and its top is K_END; a loader may put a program's own
; block above it.
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
k_probe:
        db      0
k_probe_slot:
        db      0
        ds      2
k_api:
        jp      con_puts                ; API_CON_PUTS
        jp      con_putc                ; API_CON_PUTC
        jp      con_newline             ; API_CON_NEWLINE
        jp      con_hex8                ; API_CON_HEX8
        jp      con_hex16               ; API_CON_HEX16
        jp      con_dec16               ; API_CON_DEC16
        jp      nx_rw                   ; API_NX_RW
        jp      k_enaslt                ; API_K_ENASLT
k_rec:  ds      KREC_SIZE
        ASSERT  k_ticks == K_TICKS
        ASSERT  k_probe == K_PROBE
        ASSERT  k_probe_slot == K_PROBE_SLOT
        ASSERT  k_api == K_API
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

; Exported for programs that assemble a block to run at K_END.
K_IMAGE_END     equ k_end
        EXPORT  K_IMAGE_END
