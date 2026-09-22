; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; hdir — directories and drives: the current directory read and changed
; on A: and on B:, a name made twice refused with the code of what is
; there, a drive selected, a file named through the other drive's
; directory; rename with a ? kept, the duplicate refused; move, into
; itself refused; the attributes and the stamp by name and by handle; a
; handle renamed and deleted; the deletes and what they refuse.
        include "dosf/progs/dosf.inc"
        org     100h
        d_step  1                       ; A:'s directory, up and down
        ld      de,s_empty
        call    cwd0
        ld      de,s_d1
        ld      b,10h
        call    mk
        ld      de,s_d1                 ; there already: which code says
        ld      b,10h                   ;   depends on what is there
        xor     a
        d_fn    _CREATE
        d_err   D_DIRX
        ld      de,s_d1
        ld      b,90h
        xor     a
        d_fn    _CREATE
        d_err   D_FILEX
        ld      de,s_d1
        ld      b,0
        xor     a
        d_fn    _CREATE
        d_err   D_DIRX
        ld      de,s_d1
        d_fn    _CHDIR
        d_ok
        ld      de,n_d1
        call    cwd0
        ld      de,s_d2
        ld      b,10h
        call    mk
        ld      de,s_d2
        d_fn    _CHDIR
        d_ok
        ld      de,n_d1d2
        call    cwd0
        ld      de,s_root
        d_fn    _CHDIR
        d_ok
        ld      de,s_empty
        call    cwd0
        ld      de,s_d1d2
        d_fn    _CHDIR
        d_ok
        ld      de,n_d1d2
        call    cwd0
        ld      de,s_dotdot
        d_fn    _CHDIR
        d_ok
        ld      de,n_d1
        call    cwd0
        ld      de,s_nope
        d_fn    _CHDIR
        d_err   D_NODIR
        d_step  2                       ; B: has its own; the drives
        d_fn    _LOGIN
        ld      a,l
        cp      3
        jp      nz,t_fail
        ld      b,2
        ld      de,buf
        d_fn    _GETCD
        d_ok
        ld      a,(buf)
        or      a
        jp      nz,t_fail
        ld      de,s_bbd
        ld      b,10h
        call    mk
        ld      de,s_bbd
        d_fn    _CHDIR
        d_ok
        ld      b,2
        ld      de,buf
        d_fn    _GETCD
        d_ok
        ld      hl,buf
        ld      de,n_bd
        call    d_streq
        jp      nz,t_fail
        ld      de,n_d1                 ; A:'s untouched
        call    cwd0
        ld      e,1
        d_fn    _SELDSK
        cp      2
        jp      nz,t_fail
        d_fn    _CURDRV
        cp      1
        jp      nz,t_fail
        ld      de,s_bf                 ; relative: on B:, in BD
        ld      b,0
        call    mk
        d_fn    _CLOSE
        d_ok
        ld      e,0
        d_fn    _SELDSK
        cp      2
        jp      nz,t_fail
        d_fn    _CURDRV
        or      a
        jp      nz,t_fail
        ld      de,s_bcolbf             ; B:BF.TXT: through B:'s directory
        ld      a,1
        d_fn    _OPEN
        d_ok
        d_fn    _CLOSE
        d_ok
        ld      de,s_bbdbf
        ld      a,1
        d_fn    _OPEN
        d_ok
        d_fn    _CLOSE
        d_ok
        ld      de,s_root
        d_fn    _CHDIR
        d_ok
        d_step  3                       ; rename
        ld      de,s_r1
        ld      b,0
        call    mk
        d_fn    _CLOSE
        d_ok
        ld      de,s_r1
        ld      hl,n_r2
        d_fn    _RENAME
        d_ok
        ld      de,s_r3
        ld      b,0
        call    mk
        d_fn    _CLOSE
        d_ok
        ld      de,s_r3
        ld      b,10h
        xor     a
        d_fn    _CREATE
        d_err   D_FILEX
        ld      de,s_r2
        ld      hl,n_r3
        d_fn    _RENAME
        d_err   D_DUPF
        ld      de,s_r2
        ld      hl,n_q4
        d_fn    _RENAME
        d_ok
        ld      de,s_r4
        ld      a,1
        d_fn    _OPEN
        d_ok
        d_fn    _CLOSE
        d_ok
        ld      de,s_r4
        ld      hl,n_bx
        d_fn    _RENAME
        d_err   D_IFNM
        d_step  4                       ; move
        ld      de,s_r4
        ld      hl,s_d1d2
        d_fn    _MOVE
        d_ok
        ld      de,s_d2r4
        ld      a,1
        d_fn    _OPEN
        d_ok
        d_fn    _CLOSE
        d_ok
        ld      de,s_d1d2
        ld      hl,s_d1d2
        d_fn    _MOVE
        d_err   D_DIRE
        ld      de,s_d2r4
        ld      hl,s_broot
        d_fn    _MOVE
        d_err   D_IPATH
        d_step  5                       ; attributes
        ld      de,s_r3
        xor     a
        d_fn    _ATTR
        d_ok
        ld      a,l
        cp      20h
        jp      nz,t_fail
        ld      de,s_r3
        ld      a,1
        ld      l,3
        d_fn    _ATTR
        d_ok
        ld      de,s_r3
        xor     a
        d_fn    _ATTR
        d_ok
        ld      a,l
        cp      3
        jp      nz,t_fail
        ld      de,s_r3
        ld      a,1
        ld      l,40h
        d_fn    _ATTR
        d_err   D_IATTR
        ld      de,s_r3
        ld      a,1
        ld      l,20h
        d_fn    _ATTR
        d_ok
        d_step  6                       ; the stamp
        ld      de,s_r3
        ld      a,1
        ld      ix,5678h
        ld      hl,1234h
        d_fn    _FTIME
        d_ok
        ld      de,s_r3
        xor     a
        d_fn    _FTIME
        d_ok
        push    de
        d_hlis  1234h
        pop     hl
        d_hlis  5678h
        d_step  7                       ; by handle
        ld      de,s_r3
        ld      a,1
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        ld      a,1
        ld      ix,1111h
        ld      hl,2222h
        d_fn    _HFTIME
        d_ok
        ld      a,(h1)
        ld      b,a
        xor     a
        d_fn    _HFTIME
        d_ok
        push    de
        d_hlis  2222h
        pop     hl
        d_hlis  1111h
        ld      a,(h1)
        ld      b,a
        xor     a
        d_fn    _HATTR
        d_ok
        ld      a,l
        cp      20h
        jp      nz,t_fail
        ld      a,(h1)
        ld      b,a
        ld      hl,n_r5
        d_fn    _HRENAME
        d_ok
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        ld      de,s_r5
        ld      a,1
        d_fn    _OPEN
        d_ok
        d_fn    _HDELETE
        d_ok
        ld      de,s_r5
        ld      a,1
        d_fn    _OPEN
        d_err   D_NOFIL
        d_step  8                       ; deletes
        ld      de,s_d1
        d_fn    _DELETE
        d_err   D_DIRNE
        ld      de,s_d2r4
        d_fn    _DELETE
        d_ok
        ld      de,s_d1d2
        d_fn    _DELETE
        d_ok
        ld      de,s_d1
        d_fn    _DELETE
        d_ok
        ld      de,s_dot
        d_fn    _DELETE
        d_err   D_DOT
        jp      t_ok

; cwd0 — DE -> what _GETCD of the current drive must say.
cwd0:   push    de
        ld      b,0
        ld      de,buf
        d_fn    _GETCD
        d_ok
        pop     de
        ld      hl,buf
        call    d_streq
        jp      nz,t_fail
        ret
; mk — DE -> a path, B = attributes: made, a file left open on B.
mk:     xor     a
        d_fn    _CREATE
        d_ok
        ret

        d_lib   "hdir"
s_empty: db     0
s_root: db      '\',0
s_dot:  db      '.',0
s_dotdot: db    '..',0
s_nope: db      'NOPE',0
s_d1:   db      'D1',0
s_d2:   db      'D2',0
s_d1d2: db      'D1\D2',0
n_d1:   db      'D1',0
n_d1d2: db      'D1\D2',0
s_bbd:  db      'B:\BD',0
n_bd:   db      'BD',0
s_bf:   db      'BF.TXT',0
s_bcolbf: db    'B:BF.TXT',0
s_bbdbf: db     'B:\BD\BF.TXT',0
s_broot: db     'B:\',0
s_r1:   db      'D1\R1.TXT',0
s_r2:   db      'D1\R2.TXT',0
s_r3:   db      'D1\R3.TXT',0
s_r4:   db      'D1\R4.TXT',0
s_r5:   db      'D1\R5.TXT',0
s_d2r4: db      'D1\D2\R4.TXT',0
n_r2:   db      'R2.TXT',0
n_r3:   db      'R3.TXT',0
n_q4:   db      '?4.TXT',0
n_r5:   db      'R5.TXT',0
n_bx:   db      'B:X',0
h1:     db      0
buf:    ds      64
