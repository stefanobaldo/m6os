; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; echo — a line read with _BUFIN, written back through _CONOUT with its
; length.
        include "dos/progs/dos.inc"
        org     100h
        d_puts  s_type
        ld      de,buf
        ld      c,_BUFIN
        call    BDOS
        d_puts  s_crlf
        ld      a,(buf+1)
        ld      b,a
        ld      hl,buf+2
        or      a
        jr      z,.count
.out:   push    bc
        push    hl
        ld      e,(hl)
        ld      c,_CONOUT
        call    BDOS
        pop     hl
        pop     bc
        inc     hl
        djnz    .out
.count: ld      e,' '
        ld      c,_CONOUT
        call    BDOS
        ld      a,(buf+1)
        ld      l,a
        ld      h,0
        call    d_dec16
        d_puts  s_crlf
        ld      c,_TERM0
        call    BDOS
        d_declib
s_type: db      "type: $"
s_crlf: db      13,10,"$"
buf:    db      40,0
        ds      40
