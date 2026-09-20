; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; htpa — the transient program area: its top where MSX-DOS 2 puts it,
; DC06h, the stack under it on entry, every byte from the program's end
; to a page below the top written and read back, and a file opened by a
; path that lies on that stack — as high as a program's memory goes —
; with the bytes below it still there afterwards.
        include "dosf/progs/dosf.inc"
TOP             equ 0DC06h
        org     100h
        ld      (sp0),sp
        d_step  1                       ; the BDOS entry is the TPA's top
        ld      hl,(0006h)
        d_hlis  TOP
        d_step  2                       ; the stack on entry: just under it
        ld      hl,TOP
        ld      de,(sp0)
        or      a
        sbc     hl,de
        jp      c,t_fail                ; above the top
        ld      a,h
        or      a
        jp      nz,t_fail               ; a page or more below it
        d_step  3                       ; the memory, to a page under the top
        call    fill
        call    check
        jp      nz,t_fail
        d_step  4                       ; a path on the stack, opened
        ld      hl,0
        add     hl,sp
        ld      de,-16
        add     hl,de
        ld      sp,hl                   ; sixteen bytes of it
        ex      de,hl
        push    de
        ld      hl,s_self
        ld      bc,16
        ldir
        pop     de
        xor     a
        d_fn    _OPEN
        ld      hl,16
        add     hl,sp
        ld      sp,hl
        d_ok
        d_fn    _CLOSE
        d_ok
        d_step  5                       ; and nothing below it was touched
        call    check
        jp      nz,t_fail
        jp      t_ok

; fill — every byte from the program's end to TOP-256: its address's two
; bytes, exclusive-ored. check — Z when every one is still that.
fill:   ld      hl,last
.b:     ld      a,h
        xor     l
        ld      (hl),a
        inc     hl
        ld      a,h
        cp      high (TOP-256)
        jr      nz,.b
        ret
check:  ld      hl,last
.b:     ld      a,h
        xor     l
        cp      (hl)
        ret     nz
        inc     hl
        ld      a,h
        cp      high (TOP-256)
        jr      nz,.b
        ret

        d_lib   "htpa"
sp0:    dw      0
s_self: db      '\DOSF\HTPA.COM',0,0
last:
