; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; hello — one line through _STROUT, then _TERM0.
        include "dos/progs/dos.inc"
        org     100h
        d_puts  s
        ld      c,_TERM0
        call    BDOS
s:      db      "hello from dos",13,10,"$"
