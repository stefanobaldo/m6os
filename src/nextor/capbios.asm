; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; nx_capture_bios — the half of the capture that reads the BIOS work area
; and the main ROM, and nothing of Nextor's: the VDP ports, the screen as
; SCREEN 0 has it, the VDP register shadows, the keyboard type. nx_capture
; (capture.asm) calls it under Nextor; a loader that runs with no Nextor in
; the machine — the kernel ROM — includes this file alone and calls it
; itself, after it has set the screen.
;
; In:  IX -> KREC_SIZE-byte record; the BIOS in page 0.
; Out: KR_VDPRD, KR_VDPWR, KR_NAMBAS, KR_COLS, KR_STRIDE, KR_ROWS,
;      KR_CSRY, KR_VDPREG and KR_KBDTYPE filled; interrupts enabled.
;      Corrupts everything but IX.
nx_capture_bios:
        ; The VDP ports, from the main ROM.
        ld      a,(B_EXPTBL)
        ld      hl,0006h
        call    B_RDSLT
        ei
        ld      (ix+KR_VDPRD),a
        ld      a,(B_EXPTBL)
        ld      hl,0007h
        call    B_RDSLT
        ei
        ld      (ix+KR_VDPWR),a
        ; The screen as SCREEN 0 has it.
        ld      hl,(B_TXTNAM)
        ld      (ix+KR_NAMBAS),l
        ld      (ix+KR_NAMBAS+1),h
        ld      a,(B_LINLEN)
        ld      (ix+KR_COLS),a
        ld      a,(B_LINL40)
        cp      41
        ld      a,40
        jr      c,.stride
        ld      a,80
.stride:
        ld      (ix+KR_STRIDE),a
        ld      a,(B_CRTCNT)
        ld      (ix+KR_ROWS),a
        ld      a,(B_CSRY)
        ld      (ix+KR_CSRY),a
        ; The VDP registers as the BIOS's shadows have them: R#0-R#7 from
        ; RG0SAV, R#8 and R#9 from RG8SAV.
        push    ix
        pop     de
        ld      hl,KR_VDPREG
        add     hl,de
        ex      de,hl
        ld      hl,B_RG0SAV
        ld      bc,8
        ldir
        ld      hl,B_RG8SAV
        ld      bc,2
        ldir
        ; The keyboard type, from the main ROM.
        ld      a,(B_EXPTBL)
        ld      hl,002Ch
        call    B_RDSLT
        ei
        ld      (ix+KR_KBDTYPE),a
        ret
