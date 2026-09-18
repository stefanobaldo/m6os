; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; swap — M6 written at C800h, in the legacy page 3's TPA, and a key
; waited for: the harness reads C800h now, and again after the prompt is
; back, when the kernel's own page 3 must be there.
        include "dos/progs/dos.inc"
        org     100h
        ld      hl,'M'+256*'6'
        ld      (0C800h),hl
        d_puts  s
        ld      c,_CONIN
        call    BDOS
        d_puts  s_crlf
        ld      c,_TERM0
        call    BDOS
s:      db      "swap: M6 at C800h, press a key$"
s_crlf: db      13,10,"$"
