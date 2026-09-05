; Shared definitions for the programs under tests/. Include with
; `include "m6test.inc"` (the build passes -Itests).
;
; The mailbox is how a program reports its verdict to the harness: the
; signature "M6", a status byte, a reserved byte, at a fixed TPA address.
; tools/harness.tcl defines the same address and values.
MAILBOX     equ 8000h
M6_PASS     equ 0A5h
M6_FAIL     equ 05Ah

; openMSX's debug device: diagnostics and measurements, never a verdict.
; On real hardware nothing answers these ports and the writes are harmless.
DBG_MODE    equ 2Eh         ; mode port
DBG_DATA    equ 2Fh         ; data port
DBG_ASCII   equ 23h         ; mode: multi-byte ASCII

; m6_verdict status — write the signature and the status to the mailbox.
; The status is written last, so the harness never sees a signature with a
; stale status. Clobbers HL.
    macro m6_verdict status
        ld      hl,MAILBOX
        ld      (hl),'M'
        inc     hl
        ld      (hl),'6'
        inc     hl
        ld      (hl),status
    endm

; m6_dbg_puts str — send the NUL-terminated string at str through the debug
; device in ASCII mode. Clobbers A, HL.
    macro m6_dbg_puts str
        ld      a,DBG_ASCII
        out     (DBG_MODE),a
        ld      hl,str
1:      ld      a,(hl)
        or      a
        jr      z,2F
        out     (DBG_DATA),a
        inc     hl
        jr      1B
2:
    endm
