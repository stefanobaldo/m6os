; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; hmisc — the volume's parameters and its free clusters, the drives that
; exist, the date and the clock, the messages, the last error, the
; console as a handle and its status, NUL, devices opened by name, and
; what is refused.
        include "dosf/progs/dosf.inc"
        org     100h
        d_step  1                       ; _DPARM of the current drive
        ld      l,0
        ld      de,buf
        d_fn    _DPARM
        d_ok
        ld      hl,buf
        or      a
        sbc     hl,de
        jp      nz,t_fail               ; DE preserved
        ld      a,(buf)
        cp      1
        jp      nz,t_fail
        ld      hl,(buf+1)
        d_hlis  512
        ld      a,(buf+3)
        or      a
        jp      z,t_fail
        ld      a,(buf+6)
        cp      2
        jp      nz,t_fail
        ld      hl,(buf+7)
        ld      a,h
        or      l
        jp      z,t_fail
        ld      a,(buf+19)
        or      a
        jp      nz,t_fail
        d_step  2                       ; _ALLOC: the same, and the free ones
        ld      e,0
        d_fn    _ALLOC
        ld      (free),hl
        ld      hl,buf+3
        cp      (hl)
        jp      nz,t_fail
        push    de
        ld      h,b
        ld      l,c
        d_hlis  512
        pop     de
        ld      hl,(buf+17)
        dec     hl
        or      a
        sbc     hl,de
        jp      nz,t_fail
        push    ix
        pop     hl
        ld      a,h
        or      l
        jp      nz,t_fail
        push    iy
        pop     hl
        ld      a,h
        or      l
        jp      nz,t_fail
        ld      hl,(free)
        ld      a,h
        or      l
        jp      z,t_fail
        ld      hl,(buf+17)
        ld      de,(free)
        or      a
        sbc     hl,de
        jp      c,t_fail
        d_step  3                       ; the drives: A: and B:
        d_fn    _LOGIN
        ld      a,l
        cp      3
        jp      nz,t_fail
        ld      l,3
        ld      de,buf
        d_fn    _DPARM
        d_err   D_IDRV
        d_step  4                       ; the date and the clock
        d_fn    _GDATE
        cp      7
        jp      nc,t_fail
        ld      a,d
        or      a
        jp      z,t_fail
        cp      13
        jp      nc,t_fail
        ld      a,e
        or      a
        jp      z,t_fail
        cp      32
        jp      nc,t_fail
        ld      de,1980
        or      a
        sbc     hl,de
        jp      c,t_fail
        d_fn    _GTIME
        ld      a,h
        cp      24
        jp      nc,t_fail
        d_fn    _SDATE
        cp      0FFh
        jp      nz,t_fail
        d_step  5                       ; the messages
        ld      b,D_NOFIL
        ld      de,buf
        d_fn    _EXPLAIN
        d_ok
        ld      hl,buf
        ld      de,m_nofil
        call    d_streq
        jp      nz,t_fail
        ld      b,D_ISBFN
        ld      de,buf
        d_fn    _EXPLAIN
        d_ok
        ld      hl,buf
        ld      de,m_isbfn
        call    d_streq
        jp      nz,t_fail
        ld      b,12h
        ld      de,buf
        d_fn    _EXPLAIN
        d_ok
        ld      hl,buf
        ld      de,m_12
        call    d_streq
        jp      nz,t_fail
        d_step  6                       ; the last error
        ld      de,s_nope
        ld      a,1
        d_fn    _OPEN
        d_err   D_NOFIL
        d_fn    _ERROR
        ld      a,b
        cp      D_NOFIL
        jp      nz,t_fail
        d_step  7                       ; the console handles' status
        ld      b,1
        xor     a
        d_fn    _IOCTL
        d_ok
        ld      a,e
        cp      0A2h
        jp      nz,t_fail
        ld      b,0
        xor     a
        d_fn    _IOCTL
        d_ok
        ld      a,e
        cp      0A1h
        jp      nz,t_fail
        ld      b,3
        xor     a
        d_fn    _IOCTL
        d_ok
        ld      a,e
        cp      0A0h
        jp      nz,t_fail
        ld      b,1
        ld      a,4
        d_fn    _IOCTL
        d_ok
        ld      a,d
        cp      24
        jp      nz,t_fail
        ld      a,e
        cp      80
        jp      nz,t_fail
        ld      b,1
        ld      a,7
        d_fn    _IOCTL
        d_err   D_ISBFN
        d_step  8                       ; written through handle 1
        ld      b,1
        ld      de,s_via
        ld      hl,17
        d_fn    _WRITE
        d_ok
        d_hlis  17
        d_step  9                       ; NUL reads nothing, takes anything
        ld      b,3
        ld      de,buf
        ld      hl,4
        d_fn    _READ
        d_err   D_EOF
        ld      b,3
        ld      de,buf
        ld      hl,5
        d_fn    _WRITE
        d_ok
        d_hlis  5
        d_step  10                      ; devices by name
        ld      de,s_con
        xor     a
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        ld      de,s_conh
        ld      hl,12
        d_fn    _WRITE
        d_ok
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        ld      de,s_nul
        xor     a
        d_fn    _OPEN
        d_ok
        ld      de,buf
        ld      hl,1
        d_fn    _READ
        d_err   D_EOF
        d_step  12                      ; a device in ASCII mode ends at ^Z
        ld      de,s_con
        xor     a
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        ld      de,s_ctlz
        ld      hl,6
        d_fn    _WRITE
        d_ok
        d_hlis  3                       ; "ab" out, the ^Z counted, "cd" not
        ld      a,(h1)
        ld      b,a
        xor     a
        d_fn    _IOCTL                  ; 0: the device's word, ASCII set
        d_ok
        bit     5,e
        jp      z,t_fail
        res     5,e                     ; 1: binary, and the whole buffer
        ld      d,0                     ;    goes out, ^Z and all
        ld      a,(h1)
        ld      b,a
        ld      a,1
        d_fn    _IOCTL
        d_ok
        ld      a,(h1)
        ld      b,a
        ld      de,s_ctlz
        ld      hl,6
        d_fn    _WRITE
        d_ok
        d_hlis  6
        ld      a,(h1)
        ld      b,a
        ld      de,s_crlf2
        ld      hl,2
        d_fn    _WRITE
        d_ok
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        d_step  11                      ; refused
        ld      c,67h
        call    BDOS
        d_err   D_IBDOS
        ld      c,35h
        call    BDOS
        cp      D_IBDOS
        jp      nz,t_fail
        ld      c,71h
        call    BDOS
        d_err   D_IBDOS
        jp      t_ok

        d_lib   "hmisc"
s_nope: db      'NOPE.TXT',0
s_con:  db      'CON',0
s_nul:  db      'NUL:',0
s_via:  db      'hmisc via write',13,10
s_conh: db      'con handle',13,10
m_nofil: db     'File not found',0
m_isbfn: db     'Invalid sub-function number',0
m_12:   db      'Error 12H',0
s_ctlz: db      'ab',1Ah,'cd'
s_crlf2: db     13,10
h1:     db      0
free:   dw      0
buf:    ds      64
