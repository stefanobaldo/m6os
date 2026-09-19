; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; henv — the environment strings: PARAMETERS as typed, PROGRAM as the
; whole path, a name not set, one set and read back, too long a buffer,
; removed, the items walked, names that are none, the store filled.
        include "dosf/progs/dosf.inc"
        org     100h
        d_step  1                       ; PARAMETERS: the tail, its case kept
        ld      hl,n_params
        ld      de,buf
        ld      b,64
        d_fn    _GENV
        d_ok
        ld      hl,buf
        ld      de,v_params
        call    d_streq
        jp      nz,t_fail
        d_step  2                       ; PROGRAM
        ld      hl,n_program
        ld      de,buf
        ld      b,64
        d_fn    _GENV
        d_ok
        ld      hl,buf
        ld      de,v_program
        call    d_streq
        jp      nz,t_fail
        d_step  3                       ; not set: empty
        ld      hl,n_nope
        ld      de,buf
        ld      b,64
        d_fn    _GENV
        d_ok
        ld      a,(buf)
        or      a
        jp      nz,t_fail
        d_step  4                       ; set, read back, too small a buffer
        ld      hl,n_foo
        ld      de,v_bar
        d_fn    _SENV
        d_ok
        ld      hl,n_FOO
        ld      de,buf
        ld      b,64
        d_fn    _GENV
        d_ok
        ld      hl,buf
        ld      de,v_bar
        call    d_streq
        jp      nz,t_fail
        ld      hl,n_foo
        ld      de,buf
        ld      b,2
        d_fn    _GENV
        d_err   D_ELONG
        d_step  5                       ; removed
        ld      hl,n_foo
        ld      de,s_empty
        d_fn    _SENV
        d_ok
        ld      hl,n_foo
        ld      de,buf
        ld      b,64
        d_fn    _GENV
        d_ok
        ld      a,(buf)
        or      a
        jp      nz,t_fail
        d_step  6                       ; the items by number
        ld      de,1
        ld      hl,buf
        d_fn    _FENV
        d_ok
        ld      hl,buf
        ld      de,n_params
        call    d_streq
        jp      nz,t_fail
        ld      de,2
        ld      hl,buf
        d_fn    _FENV
        d_ok
        ld      hl,buf
        ld      de,n_program
        call    d_streq
        jp      nz,t_fail
        ld      de,3
        ld      hl,buf
        d_fn    _FENV
        d_ok
        ld      a,(buf)
        or      a
        jp      nz,t_fail
        ld      hl,n_x
        ld      de,v_1
        d_fn    _SENV
        d_ok
        ld      hl,n_y
        ld      de,v_2
        d_fn    _SENV
        d_ok
        ld      de,4
        ld      hl,buf
        d_fn    _FENV
        d_ok
        ld      hl,buf
        ld      de,n_y
        call    d_streq
        jp      nz,t_fail
        ld      de,5
        ld      hl,buf
        d_fn    _FENV
        d_ok
        ld      a,(buf)
        or      a
        jp      nz,t_fail
        d_step  7                       ; names that are none
        ld      hl,s_empty
        ld      de,v_1
        d_fn    _SENV
        d_err   D_IENV
        ld      hl,n_aeqb
        ld      de,v_1
        d_fn    _SENV
        d_err   D_IENV
        d_step  8                       ; the store filled: NORAM in the end
        ld      c,0
.fill:  ld      a,c
        add     a,'A'
        ld      (n_v+1),a
        push    bc
        ld      hl,n_v
        ld      de,v_long
        d_fn    _SENV
        pop     bc
        or      a
        jr      nz,.full
        inc     c
        ld      a,c
        cp      10
        jr      c,.fill
        jp      t_fail                  ; ten of 60 bytes fitted 256
.full:  d_err   D_NORAM
        ld      a,c
        cp      2
        jp      c,t_fail
        jp      t_ok

        d_lib   "henv"
s_empty: db     0
n_params: db    'PARAMETERS',0
v_params: db    'Ab cd',0
n_program: db   'PROGRAM',0
v_program: db   'A:\DOSF\HENV.COM',0
n_nope: db      'NOPE',0
n_foo:  db      'Foo',0
n_FOO:  db      'FOO',0
v_bar:  db      'bar',0
n_x:    db      'X',0
n_y:    db      'Y',0
v_1:    db      '1',0
v_2:    db      '2',0
n_aeqb: db      'A=B',0
n_v:    db      'V?',0
v_long: db      '0123456789012345678901234567890123456789012345678901234567',0
buf:    ds      64
