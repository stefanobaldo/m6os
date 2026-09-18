; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; jp0 — a line, then jp 0: the warm boot ends the program with 0.
        include "dos/progs/dos.inc"
        org     100h
        d_puts  s
        jp      0
s:      db      "jp0",13,10,"$"
