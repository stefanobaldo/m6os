; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; copy64 — 64 KB written in four 16K pieces from page 1, then copied to
; a second file through handles in 16K pieces, then the copy read back
; and compared. The shell's tick stamps around the launch, in /etc/rc,
; time the whole: the XCOPY line's m6 half, an emulator's hint in CI (the
; BIOS's JIFFY stands still inside a disk call, so the program itself
; cannot time its disk work).
        include "dosf/progs/dosf.inc"
BUF     equ 4000h
        org     100h
        d_step  1                       ; the source, 64 KB
        ld      de,s_big
        xor     a
        ld      b,0
        d_fn    _CREATE
        d_ok
        ld      a,b
        ld      (h1),a
        ld      c,0
.w:     push    bc
        ld      a,c
        call    fill
        ld      a,(h1)
        ld      b,a
        ld      de,BUF
        ld      hl,16384
        d_fn    _WRITE
        pop     bc
        d_ok
        d_hlis  16384
        inc     c
        ld      a,c
        cp      4
        jr      c,.w
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        d_step  2                       ; the copy
        ld      de,s_big
        ld      a,1
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        ld      de,s_copy
        xor     a
        ld      b,0
        d_fn    _CREATE
        d_ok
        ld      a,b
        ld      (h2),a
        ld      c,0
.c:     push    bc
        ld      a,(h1)
        ld      b,a
        ld      de,BUF
        ld      hl,16384
        d_fn    _READ
        pop     bc
        d_ok
        d_hlis  16384
        push    bc
        ld      a,(h2)
        ld      b,a
        ld      de,BUF
        ld      hl,16384
        d_fn    _WRITE
        pop     bc
        d_ok
        d_hlis  16384
        inc     c
        ld      a,c
        cp      4
        jr      c,.c
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        ld      a,(h2)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        d_step  3                       ; the copy read back
        ld      de,s_copy
        ld      a,1
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        ld      c,0
.v:     push    bc
        ld      a,(h1)
        ld      b,a
        ld      de,BUF
        ld      hl,16384
        d_fn    _READ
        pop     bc
        d_ok
        d_hlis  16384
        push    bc
        ld      a,c
        call    check
        pop     bc
        jp      nz,t_fail
        inc     c
        ld      a,c
        cp      4
        jr      c,.v
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        jp      t_ok

; fill — A = the piece: BUF filled with byte i = (i + piece) ^ (i >> 8).
; check — the same compared: Z when it holds.
fill:   ld      hl,BUF
        ld      c,a
        ld      b,0
.f:     ld      a,l
        add     a,c
        xor     h
        ld      (hl),a
        inc     hl
        ld      a,h
        cp      80h
        jr      c,.f
        ret
check:  ld      hl,BUF
        ld      c,a
.k:     ld      a,l
        add     a,c
        xor     h
        cp      (hl)
        ret     nz
        inc     hl
        ld      a,h
        cp      80h
        jr      c,.k
        xor     a
        ret

        d_lib   "copy64"
s_big:  db      'BIG.BIN',0
s_copy: db      'COPY.BIN',0
h1:     db      0
h2:     db      0
