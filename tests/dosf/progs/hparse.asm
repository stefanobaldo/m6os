; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; hparse — the string functions: a path parsed with its flags and drive,
; the root alone, .., an ambiguous name, a filename expanded to eleven
; bytes, a character checked.
        include "dosf/progs/dosf.inc"
        org     100h
        d_step  1                       ; A:\XYZ\P.Q /F
        ld      de,s_p1
        ld      b,0
        d_fn    _PARSE
        d_ok
        ld      a,b
        cp      1Fh
        jp      nz,t_fail
        ld      a,c
        cp      1
        jp      nz,t_fail
        push    hl
        ld      hl,s_p1+10              ; " /F"
        or      a
        sbc     hl,de
        jp      nz,t_fail
        pop     hl
        ld      de,s_p1+7               ; "P.Q /F"
        or      a
        sbc     hl,de
        jp      nz,t_fail
        d_step  2                       ; \ alone: no last item
        ld      de,s_p2
        ld      b,0
        d_fn    _PARSE
        d_ok
        ld      a,b
        cp      3
        jp      nz,t_fail
        or      a
        sbc     hl,de
        jp      nz,t_fail
        d_step  3                       ; ..
        ld      de,s_p3
        ld      b,0
        d_fn    _PARSE
        d_ok
        ld      a,b
        cp      0C1h
        jp      nz,t_fail
        d_step  4                       ; *.*, the current drive
        ld      de,s_p4
        ld      b,0
        d_fn    _PARSE
        d_ok
        ld      a,b
        cp      39h
        jp      nz,t_fail
        ld      a,c
        cp      1
        jp      nz,t_fail
        d_step  5                       ; ab*.c d expanded
        ld      de,s_p5
        ld      hl,buf
        d_fn    _PFILE
        d_ok
        ld      a,b
        cp      38h
        jp      nz,t_fail
        ld      hl,s_p5+5               ; " d"
        or      a
        sbc     hl,de
        jp      nz,t_fail
        ld      hl,buf
        ld      de,n_p5
        ld      bc,11
        call    d_memeq
        jp      nz,t_fail
        d_step  6                       ; characters
        ld      d,0
        ld      e,'a'
        d_fn    _CHKCHR
        d_ok
        ld      a,e
        cp      'A'
        jp      nz,t_fail
        ld      a,d
        or      a
        jp      nz,t_fail
        ld      d,0
        ld      e,'\'
        d_fn    _CHKCHR
        ld      a,d
        cp      10h
        jp      nz,t_fail
        ld      d,0
        ld      e,'.'
        d_fn    _CHKCHR
        ld      a,d
        cp      10h
        jp      nz,t_fail
        ld      d,8
        ld      e,'.'
        d_fn    _CHKCHR
        ld      a,d
        cp      8
        jp      nz,t_fail
        ld      d,1
        ld      e,'a'
        d_fn    _CHKCHR
        ld      a,e
        cp      'a'
        jp      nz,t_fail
        jp      t_ok

        d_lib   "hparse"
s_p1:   db      'A:\XYZ\P.Q /F',0
s_p2:   db      '\',0
s_p3:   db      '..',0
s_p4:   db      '*.*',0
s_p5:   db      'ab*.c d',0
n_p5:   db      'AB??????C  '
buf:    ds      16
