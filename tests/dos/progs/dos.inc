; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; Shared by the raw .COM programs of tests/dos: they are MSX-DOS 2
; programs, with no m6 header, and reach the system through CALL 5.
BDOS        equ 0005h
_TERM0      equ 00h
_CONIN      equ 01h
_CONOUT     equ 02h
_STROUT     equ 09h
_BUFIN      equ 0Ah
_JOIN       equ 61h
_TERM       equ 62h
EXTBIO      equ 0FFCAh
JIFFY       equ 0FC9Eh

    macro d_puts str
        ld      de,str
        ld      c,_STROUT
        call    BDOS
    endm

; d_dec16 — HL in decimal through _CONOUT, no leading zeros. Corrupts
; everything.
    macro d_declib
d_dec16:
        ld      de,d_buf+5
        xor     a
        ld      (de),a
.digit: ld      bc,10
        call    d_div16
        add     a,'0'
        dec     de
        ld      (de),a
        ld      a,h
        or      l
        jr      nz,.digit
.out:   ld      a,(de)
        or      a
        ret     z
        push    de
        ld      e,a
        ld      c,_CONOUT
        call    BDOS
        pop     de
        inc     de
        jr      .out
d_div16:
        push    de
        ld      d,0
        ld      e,16
.bit:   add     hl,hl
        rl      d
        ld      a,d
        sub     c
        jr      c,.no
        ld      d,a
        inc     l
.no:    dec     e
        jr      nz,.bit
        ld      a,d
        pop     de
        ret
d_buf:  ds      6
    endm
