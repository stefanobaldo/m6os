; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; wboot — what a file manager does to run a program and come back: the
; WBOOT jump that (0001h) points at is aimed at the program's own code,
; then the program ends by ret and again by _TERM with 5, and both ends
; reach that code through 0000h, as under MSX-DOS; there _JOIN answers
; the code the program ended with, as a file manager reads its child's.
; The jump put back, a line, and jp 0 ends the program with _TERM's code.
        include "dos/progs/dos.inc"
        org     100h
        ld      hl,(0001h)
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (orig),de
        ld      de,hook
        ld      (hl),d
        dec     hl
        ld      (hl),e
        ret                             ; the first end
hook:   ld      sp,stack
        ld      hl,count
        inc     (hl)
        ld      a,(hl)
        cp      2
        jr      nc,.back
        ld      b,5
        ld      c,_TERM
        call    BDOS                    ; the second end
.back:  ld      b,0
        ld      c,_JOIN
        call    BDOS
        ld      a,b
        cp      5
        ld      de,s_join
        jr      nz,.say
        ld      de,s
.say:   push    de
        ld      hl,(0001h)
        inc     hl
        ld      de,(orig)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        pop     de
        ld      c,_STROUT
        call    BDOS
        jp      0
s:      db      "wboot twice",13,10,"$"
s_join: db      "wboot join not 5",13,10,"$"
orig:   dw      0
count:  db      0
        ds      64
stack:
