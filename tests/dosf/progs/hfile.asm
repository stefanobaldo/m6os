; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; hfile — the handle functions on one file: created and written, read
; back in pieces to the end, the pointer moved three ways, a duplicate
; sharing it, ensured, tested against a path, its status asked; then a
; hole written past the end, the read-only attribute, the one writer,
; the sixth file, "create new" on what exists, and the delete.
        include "dosf/progs/dosf.inc"
        org     100h
        ld      hl,pat                  ; the pattern: byte i = i + 3*(i/256)
        ld      bc,2048
.fill:  ld      a,c
        add     a,b
        add     a,b
        add     a,b
        ld      (hl),a
        inc     hl
        inc     c
        jr      nz,.fill
        inc     b
        ld      a,b
        cp      8
        jr      c,.fill
        d_step  1                       ; a directory
        ld      de,s_t
        xor     a
        ld      b,10h
        d_fn    _CREATE
        d_ok
        ld      a,b
        cp      0FFh
        jp      nz,t_fail
        d_step  2                       ; 1543 bytes written
        ld      de,s_f1
        xor     a
        ld      b,0
        d_fn    _CREATE
        d_ok
        ld      a,b
        ld      (h1),a
        ld      de,pat
        ld      hl,1543
        d_fn    _WRITE
        d_ok
        d_hlis  1543
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        d_step  3                       ; read in two pieces, then the end
        ld      de,s_f1
        ld      a,1
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        ld      de,buf
        ld      hl,1000
        d_fn    _READ
        d_ok
        d_hlis  1000
        ld      hl,buf
        ld      de,pat
        ld      bc,1000
        call    d_memeq
        jp      nz,t_fail
        ld      a,(h1)
        ld      b,a
        ld      de,buf
        ld      hl,1000
        d_fn    _READ
        d_ok
        d_hlis  543
        ld      hl,buf
        ld      de,pat+1000
        ld      bc,543
        call    d_memeq
        jp      nz,t_fail
        ld      a,(h1)
        ld      b,a
        ld      de,buf
        ld      hl,10
        d_fn    _READ
        d_err   D_EOF
        ld      a,h
        or      l
        jp      nz,t_fail
        d_step  4                       ; the pointer, three ways
        ld      a,(h1)
        ld      b,a
        xor     a
        ld      de,0
        ld      hl,100
        d_fn    _SEEK
        d_ok
        ld      a,d
        or      e
        jp      nz,t_fail
        d_hlis  100
        ld      a,(h1)
        ld      b,a
        ld      de,buf
        ld      hl,4
        d_fn    _READ
        d_ok
        ld      hl,buf
        ld      de,pat+100
        ld      bc,4
        call    d_memeq
        jp      nz,t_fail
        ld      a,(h1)
        ld      b,a
        ld      a,1
        ld      de,0FFFFh
        ld      hl,0FFFCh               ; -4
        d_fn    _SEEK
        d_ok
        d_hlis  100
        ld      a,(h1)
        ld      b,a
        ld      a,2
        ld      de,0
        ld      hl,0
        d_fn    _SEEK
        d_ok
        d_hlis  1543
        d_step  5                       ; a duplicate shares the pointer
        ld      a,(h1)
        ld      b,a
        d_fn    _DUP
        d_ok
        ld      a,b
        ld      (h2),a
        xor     a
        ld      de,0
        ld      hl,200
        d_fn    _SEEK
        d_ok
        ld      a,(h1)
        ld      b,a
        ld      de,buf
        ld      hl,1
        d_fn    _READ
        d_ok
        ld      a,(buf)
        ld      hl,pat+200
        cp      (hl)
        jp      nz,t_fail
        d_step  6                       ; ensure; the same file, another
        ld      a,(h1)
        ld      b,a
        d_fn    _ENSURE
        d_ok
        ld      a,(h1)
        ld      b,a
        ld      de,s_f1
        d_fn    _HTEST
        d_ok
        ld      a,b
        cp      0FFh
        jp      nz,t_fail
        ld      a,(h1)
        ld      b,a
        ld      de,s_self
        d_fn    _HTEST
        d_ok
        ld      a,b
        or      a
        jp      nz,t_fail
        d_step  7                       ; the status: the drive, then the end
        ld      a,(h1)
        ld      b,a
        xor     a
        d_fn    _IOCTL
        d_ok
        ld      a,e
        or      a
        jp      nz,t_fail
        ld      a,(h1)
        ld      b,a
        ld      a,2
        ld      de,0
        ld      hl,0
        d_fn    _SEEK
        d_ok
        ld      a,(h1)
        ld      b,a
        ld      de,buf
        ld      hl,1
        d_fn    _READ
        d_err   D_EOF
        ld      a,(h1)
        ld      b,a
        xor     a
        d_fn    _IOCTL
        d_ok
        ld      a,e
        cp      40h
        jp      nz,t_fail
        ld      a,(h1)
        ld      b,a
        ld      a,2
        d_fn    _IOCTL
        d_ok
        ld      a,e
        or      a
        jp      nz,t_fail
        d_step  8                       ; closed, both; then no handle
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        ld      a,(h2)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        ld      a,(h1)
        ld      b,a
        ld      de,buf
        ld      hl,1
        d_fn    _READ
        d_err   D_IHAND
        d_step  9                       ; a hole past the end, no reads
        ld      de,s_f1
        ld      a,2
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        xor     a
        ld      de,0
        ld      hl,2000
        d_fn    _SEEK
        d_ok
        ld      a,(h1)
        ld      b,a
        ld      de,pat
        ld      hl,8
        d_fn    _WRITE
        d_ok
        d_hlis  8
        ld      a,(h1)
        ld      b,a
        ld      de,buf
        ld      hl,1
        d_fn    _READ
        d_err   D_ACCV
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        ld      de,s_f1
        ld      a,1
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        ld      a,2
        ld      de,0
        ld      hl,0
        d_fn    _SEEK
        d_ok
        d_hlis  2008
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        d_step  10                      ; read-only refuses a writer
        ld      de,s_f1
        ld      a,1
        ld      l,1
        d_fn    _ATTR
        d_ok
        ld      de,s_f1
        xor     a
        d_fn    _OPEN
        d_err   D_FILRO
        ld      de,s_f1
        ld      a,1
        ld      l,20h
        d_fn    _ATTR
        d_ok
        d_step  11                      ; one writer at a time
        ld      de,s_f1
        xor     a
        d_fn    _OPEN
        d_ok
        ld      a,b
        ld      (h1),a
        ld      de,s_f1
        xor     a
        d_fn    _OPEN
        d_err   D_FOPEN
        ld      de,s_f1
        ld      a,1
        d_fn    _OPEN
        d_err   D_FOPEN
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        d_step  12                      ; five files open; the sixth is not
        ld      hl,hs
        ld      b,5
.five:  push    bc
        push    hl
        ld      de,s_f1
        ld      a,1
        d_fn    _OPEN
        pop     hl
        d_ok
        ld      (hl),b                  ; the handle, before the count
        inc     hl
        pop     bc
        djnz    .five
        ld      de,s_f1
        ld      a,1
        d_fn    _OPEN
        d_err   D_NHAND
        ld      hl,hs
        ld      b,5
.close5:
        push    bc
        push    hl
        ld      b,(hl)
        d_fn    _CLOSE
        pop     hl
        pop     bc
        d_ok
        inc     hl
        djnz    .close5
        d_step  13                      ; create new: it exists
        ld      de,s_f1
        xor     a
        ld      b,80h
        d_fn    _CREATE
        d_err   D_FILEX
        d_step  14                      ; deleted, gone; the directory too
        ld      de,s_f1
        d_fn    _DELETE
        d_ok
        ld      de,s_f1
        ld      a,1
        d_fn    _OPEN
        d_err   D_NOFIL
        ld      de,s_t
        d_fn    _DELETE
        d_ok
        d_step  15                      ; the flags say what A says: a
        ld      de,s_f1                 ; program may branch on Z with no
        ld      a,1                     ; test of A
        d_fn    _OPEN
        jp      z,t_fail                ; an error, and Z
        ld      de,s_self
        ld      a,1
        d_fn    _OPEN
        jp      nz,t_fail               ; 0, and NZ
        ld      a,b
        ld      (h1),a
        ld      a,(h1)
        ld      b,a
        d_fn    _CLOSE
        d_ok
        jp      t_ok

        d_lib   "hfile"
s_t:    db      'HFT',0
s_f1:   db      'HFT\F1.TXT',0
s_self: db      '\DOSF\HFILE.COM',0
h1:     db      0
h2:     db      0
hs:     ds      5
pat:    ds      2048
buf:    ds      1024
