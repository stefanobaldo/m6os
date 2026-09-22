; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; noeol — a word and no CR LF after it, then _TERM0: the cursor is left
; away from column 0 when the program ends.
        include "dos/progs/dos.inc"
        org     100h
        d_puts  s
        ld      c,_TERM0
        call    BDOS
s:      db      "noeol$"
