; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; con10k — 10 000 _CONOUTs on one cell (a dot, then a backspace), the
; BIOS's JIFFY read before and after: the console line's figure.
        include "dos/progs/dos.inc"
        org     100h
        ld      hl,(JIFFY)
        ld      (t0),hl
        ld      hl,5000
.loop:  push    hl
        ld      e,'.'
        ld      c,_CONOUT
        call    BDOS
        ld      e,8
        ld      c,_CONOUT
        call    BDOS
        pop     hl
        dec     hl
        ld      a,h
        or      l
        jr      nz,.loop
        ld      hl,(JIFFY)
        ld      de,(t0)
        or      a
        sbc     hl,de
        push    hl
        d_puts  s
        pop     hl
        call    d_dec16
        d_puts  s_crlf
        ld      c,_TERM0
        call    BDOS
        d_declib
s:      db      "conout 10000: $"
s_crlf: db      " ticks",13,10,"$"
t0:     dw      0
