; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; hproc — fork and join over the handles, a join to nowhere, the drive
; assignment asked, set and cleared, the disk error routine set, and the
; flags and the transfer address kept and given back.
        include "dosf/progs/dosf.inc"
        org     100h
        d_step  1                       ; a level, a handle in it, joined away
        d_fn    _FORK
        d_ok
        ld      a,b
        or      a
        jp      nz,t_fail
        ld      de,s_self
        ld      a,1
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        ld      b,0
        d_fn    _JOIN
        d_ok
        ld      a,(h1)
        ld      b,a
        ld      de,buf
        ld      hl,1
        d_fn    _READ
        d_err   D_IHAND
        d_step  2                       ; two levels, the inner joined
        d_fn    _FORK
        d_ok
        ld      a,b
        or      a
        jp      nz,t_fail
        ld      de,s_self
        ld      a,1
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        d_fn    _FORK
        d_ok
        ld      a,b
        cp      1
        jp      nz,t_fail
        ld      de,s_self
        ld      a,1
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h2),a
        ld      b,1
        d_fn    _JOIN
        d_ok
        ld      a,(h2)
        ld      b,a
        d_fn    _ENSURE
        d_err   D_IHAND
        ld      a,(h1)
        ld      b,a
        d_fn    _ENSURE
        d_ok
        ld      b,0
        d_fn    _JOIN
        d_ok
        ld      a,(h1)
        ld      b,a
        d_fn    _ENSURE
        d_err   D_IHAND
        d_step  3                       ; a join to a level that is not
        ld      b,5
        d_fn    _JOIN
        d_err   D_IPROC
        d_step  4                       ; the assignment
        ld      b,1
        ld      d,0FFh
        d_fn    _ASSIGN
        d_ok
        ld      a,d
        cp      1
        jp      nz,t_fail
        ld      b,1
        ld      d,2
        d_fn    _ASSIGN
        d_ok
        ld      b,1                     ; A: is B: now: B:'s directory
        ld      d,0FFh
        d_fn    _ASSIGN
        d_ok
        ld      a,d
        cp      2
        jp      nz,t_fail
        ld      de,s_hd                 ; B:'s BD, from hdir, is A:\BD now
        ld      a,1
        d_fn    _OPEN
        d_ok
        d_fn    _CLOSE
        d_ok
        ld      b,1
        ld      d,0
        d_fn    _ASSIGN
        d_ok
        ld      b,1
        ld      d,0FFh
        d_fn    _ASSIGN
        d_ok
        ld      a,d
        cp      1
        jp      nz,t_fail
        ld      b,0
        ld      d,0
        d_fn    _ASSIGN
        d_ok
        ld      b,9
        ld      d,0FFh
        d_fn    _ASSIGN
        d_err   D_IDRV
        d_step  5                       ; the routines, set and cleared
        ld      de,defer
        d_fn    _DEFER
        d_ok
        ld      de,0
        d_fn    _DEFER
        d_ok
        d_step  6                       ; the flags
        xor     a
        d_fn    _DSKCHK
        d_ok
        ld      a,b
        or      a
        jp      nz,t_fail
        ld      a,1
        ld      b,0FFh
        d_fn    _DSKCHK
        d_ok
        xor     a
        d_fn    _DSKCHK
        d_ok
        ld      a,b
        cp      0FFh
        jp      nz,t_fail
        xor     a
        d_fn    _REDIR
        d_ok
        ld      a,b
        or      a
        jp      nz,t_fail
        ld      e,1
        d_fn    _VERIFY
        d_fn    _GETVFY
        d_ok
        ld      a,b
        cp      0FFh
        jp      nz,t_fail
        ld      e,0
        d_fn    _VERIFY
        d_fn    _GETVFY
        d_ok
        ld      a,b
        or      a
        jp      nz,t_fail
        ld      b,0FFh
        ld      d,0
        d_fn    _FLUSH
        d_ok
        d_step  7                       ; the transfer address
        ld      de,1234h
        d_fn    _SETDTA
        d_fn    _GETDTA
        d_ok
        ex      de,hl
        d_hlis  1234h
        d_fn    _DSKRST
        d_fn    _GETDTA
        d_ok
        ex      de,hl
        d_hlis  0080h
        jp      t_ok
defer:  ld      a,1
        ret

        d_lib   "hproc"
s_self: db      '\DOSF\HPROC.COM',0
s_hd:   db      'A:\BD',0
h1:     db      0
h2:     db      0
buf:    ds      16
