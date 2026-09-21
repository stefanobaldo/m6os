; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; fcb — the CP/M-compatible file functions on FCBs: a file made and
; written record by record, closed, opened again and read back, a
; partial record padded, random records read and written past the end,
; block reads and writes with a record size of its own, the size asked
; and set, a search with ?, an ambiguous rename and delete, an FCB and a
; transfer address in page 2, six FCBs open without a close, an FCB
; read after its close, a device on an FCB, the auxiliary device, and
; _EXPLAIN's message read from /bin/dos.
        include "dosf/progs/dosf.inc"
_AUXIN      equ 03h
_FOPEN      equ 0Fh
_FCLOSE     equ 10h
_SFIRST     equ 11h
_SNEXT      equ 12h
_FDEL       equ 13h
_RDSEQ      equ 14h
_WRSEQ      equ 15h
_FMAKE      equ 16h
_FREN       equ 17h
_RDRND      equ 21h
_WRRND      equ 22h
_FSIZE      equ 23h
_SETRND     equ 24h
_WRBLK      equ 26h
_RDBLK      equ 27h
_WRZER      equ 28h
FC_EXTL     equ 0Ch
FC_ATTR     equ 0Dh
FC_EXTH     equ 0Eh
FC_RSIZ     equ 0Eh
FC_RCNT     equ 0Fh
FC_SIZE     equ 10h
FC_ROW      equ 18h
FC_CREC     equ 20h
FC_RREC     equ 21h
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

        d_step  1                       ; made: empty, a row, no records
        ld      hl,n_t
        ld      de,fcb1
        call    fcb_set
        ld      de,fcb1
        d_fn    _FMAKE
        d_ok
        ld      a,(fcb1+FC_ROW)
        cp      16
        jp      nc,t_fail
        ld      hl,(fcb1+FC_SIZE)
        d_hlis  0
        ld      a,(fcb1+FC_RCNT)
        or      a
        jp      nz,t_fail
        d_step  2                       ; five records written in turn
        ld      de,pat
        ld      (dta),de
        d_fn    _SETDTA
        ld      b,5
.wr:    push    bc
        ld      de,fcb1
        d_fn    _WRSEQ
        d_ok
        ld      de,(dta)
        ld      hl,128
        add     hl,de
        ld      (dta),hl
        ex      de,hl
        d_fn    _SETDTA
        pop     bc
        djnz    .wr
        ld      a,(fcb1+FC_CREC)
        cp      5
        jp      nz,t_fail
        ld      hl,(fcb1+FC_SIZE)
        d_hlis  640
        ld      a,(fcb1+FC_RCNT)
        cp      5
        jp      nz,t_fail
        d_step  3                       ; closed
        ld      de,fcb1
        d_fn    _FCLOSE
        d_ok
        d_step  4                       ; opened again: the size, the count
        ld      hl,n_t
        ld      de,fcb2
        call    fcb_set
        ld      de,fcb2
        d_fn    _FOPEN
        d_ok
        ld      hl,(fcb2+FC_SIZE)
        d_hlis  640
        ld      a,(fcb2+FC_RCNT)
        cp      5
        jp      nz,t_fail
        ld      a,(fcb2+FC_ATTR)
        and     20h                     ; archive: a file just written
        jp      z,t_fail
        d_step  5                       ; read back, then the end
        ld      b,5
        ld      hl,pat
        ld      (cmp),hl
.rd:    push    bc
        ld      de,buf
        d_fn    _SETDTA
        ld      de,fcb2
        d_fn    _RDSEQ
        d_ok
        ld      hl,buf
        ld      de,(cmp)
        ld      bc,128
        call    d_memeq
        jp      nz,t_fail
        ld      hl,(cmp)
        ld      de,128
        add     hl,de
        ld      (cmp),hl
        pop     bc
        djnz    .rd
        ld      de,fcb2
        d_fn    _RDSEQ
        d_err   1
        d_step  6                       ; 100 bytes more by a block write of
        ld      hl,1                    ;   size 1; the partial record padded
        ld      (fcb2+FC_RSIZ),hl
        ld      hl,640
        ld      (fcb2+FC_RREC),hl
        ld      hl,0
        ld      (fcb2+FC_RREC+2),hl
        ld      de,pat+640
        d_fn    _SETDTA
        ld      de,fcb2
        ld      hl,100
        d_fn    _WRBLK
        d_ok
        ld      hl,(fcb2+FC_SIZE)
        d_hlis  740
        ld      hl,(fcb2+FC_RREC)
        d_hlis  740
        ld      de,buf
        d_fn    _SETDTA
        ld      hl,buf                  ; the buffer marked, to see the zeros
        ld      (hl),55h
        ld      de,buf+1
        ld      bc,127
        ldir
        xor     a                       ; the record size's low byte is the
        ld      (fcb2+FC_EXTH),a        ;   extent's high byte: 0 again
        ld      de,fcb2                 ; the current record is still 5
        d_fn    _RDSEQ
        d_ok
        ld      hl,buf
        ld      de,pat+640
        ld      bc,100
        call    d_memeq
        jp      nz,t_fail
        ld      hl,buf+100
        ld      b,28
.zero:  ld      a,(hl)
        or      a
        jp      nz,t_fail
        inc     hl
        djnz    .zero
        ld      a,(fcb2+FC_CREC)
        cp      6
        jp      nz,t_fail
        ld      de,fcb2
        d_fn    _RDSEQ
        d_err   1
        d_step  7                       ; a random record: the fields follow
        ld      hl,2
        ld      (fcb2+FC_RREC),hl
        xor     a
        ld      (fcb2+FC_RREC+2),a
        ld      de,fcb2
        d_fn    _RDRND
        d_ok
        ld      hl,buf
        ld      de,pat+256
        ld      bc,128
        call    d_memeq
        jp      nz,t_fail
        ld      a,(fcb2+FC_CREC)
        cp      2
        jp      nz,t_fail
        ld      a,(fcb2+FC_EXTL)
        or      a
        jp      nz,t_fail
        ld      a,(fcb2+FC_RCNT)
        cp      6
        jp      nz,t_fail
        d_step  8                       ; record 10 written past the end:
        ld      hl,10                   ;   a hole of zeros before it
        ld      (fcb2+FC_RREC),hl
        ld      de,pat+1280
        d_fn    _SETDTA
        ld      de,fcb2
        d_fn    _WRRND
        d_ok
        ld      hl,(fcb2+FC_SIZE)
        d_hlis  1408
        ld      de,buf
        d_fn    _SETDTA
        ld      hl,7
        ld      (fcb2+FC_RREC),hl
        ld      de,fcb2
        d_fn    _RDRND
        d_ok
        ld      hl,buf
        ld      b,128
.hole:  ld      a,(hl)
        or      a
        jp      nz,t_fail
        inc     hl
        djnz    .hole
        ld      hl,10
        ld      (fcb2+FC_RREC),hl
        ld      de,fcb2
        d_fn    _RDRND
        d_ok
        ld      hl,buf
        ld      de,pat+1280
        ld      bc,128
        call    d_memeq
        jp      nz,t_fail
        d_step  9                       ; block reads of 100: three, then
        ld      hl,100                  ;   the rest, short and padded
        ld      (fcb2+FC_RSIZ),hl
        ld      hl,0
        ld      (fcb2+FC_RREC),hl
        ld      (fcb2+FC_RREC+2),hl
        ld      de,fcb2
        ld      hl,3
        d_fn    _RDBLK
        d_ok
        d_hlis  3
        ld      hl,buf
        ld      de,pat
        ld      bc,300
        call    d_memeq
        jp      nz,t_fail
        ld      hl,(fcb2+FC_RREC)
        d_hlis  3
        ld      hl,buf+1100             ; marked past the file's bytes
        ld      (hl),0AAh
        ld      de,buf+1101
        ld      bc,99
        ldir
        ld      de,fcb2
        ld      hl,20
        d_fn    _RDBLK
        d_err   1
        d_hlis  12
        ld      hl,buf
        ld      de,pat+300
        ld      bc,340                  ; to the hole's start
        call    d_memeq
        jp      nz,t_fail
        ld      hl,buf+1108             ; 1408 - 300: the padding
        ld      b,92
.padz:  ld      a,(hl)
        or      a
        jp      nz,t_fail
        inc     hl
        djnz    .padz
        ld      hl,(fcb2+FC_RREC)
        d_hlis  15
        d_step  10                      ; the size in records, unopened
        ld      hl,n_t
        ld      de,fcb3
        call    fcb_set
        ld      de,fcb3
        d_fn    _FSIZE
        d_ok
        ld      hl,(fcb3+FC_RREC)
        d_hlis  11
        d_step  11                      ; the size set: grown, cut short,
        ld      hl,1                    ;   emptied
        ld      (fcb2+FC_RSIZ),hl
        ld      hl,2000
        ld      (fcb2+FC_RREC),hl
        ld      hl,0
        ld      (fcb2+FC_RREC+2),hl
        ld      de,fcb2
        ld      hl,0
        d_fn    _WRBLK
        d_ok
        ld      hl,(fcb2+FC_SIZE)
        d_hlis  2000
        ld      de,fcb3
        d_fn    _FSIZE
        d_ok
        ld      hl,(fcb3+FC_RREC)
        d_hlis  16
        ld      hl,1000                 ; cut short
        ld      (fcb2+FC_RREC),hl
        ld      de,fcb2
        ld      hl,0
        d_fn    _WRBLK
        d_ok
        ld      hl,(fcb2+FC_SIZE)
        d_hlis  1000
        ld      de,fcb3
        d_fn    _FSIZE
        d_ok
        ld      hl,(fcb3+FC_RREC)
        d_hlis  8
        ld      hl,0
        ld      (fcb2+FC_RREC),hl
        ld      de,fcb2
        ld      hl,0
        d_fn    _WRBLK
        d_ok
        ld      hl,(fcb2+FC_SIZE)
        d_hlis  0
        ld      de,fcb3
        d_fn    _FSIZE
        d_ok
        ld      hl,(fcb3+FC_RREC)
        d_hlis  0
        ld      de,pat                  ; two records again, from the start
        d_fn    _SETDTA
        xor     a
        ld      (fcb2+FC_EXTL),a
        ld      (fcb2+FC_EXTH),a        ; the record size's byte, again
        ld      (fcb2+FC_CREC),a
        ld      de,fcb2
        d_fn    _WRSEQ
        d_ok
        ld      de,pat+128
        d_fn    _SETDTA
        ld      de,fcb2
        d_fn    _WRSEQ
        d_ok
        ld      de,fcb2
        d_fn    _FCLOSE
        d_ok
        d_step  12                      ; a search with ?, then a second file
        ld      de,buf
        d_fn    _SETDTA
        ld      hl,n_q
        ld      de,fcb3
        call    fcb_set
        ld      de,fcb3
        d_fn    _SFIRST
        d_ok
        ld      hl,buf+1
        ld      de,e_t
        ld      bc,11
        call    d_memeq
        jp      nz,t_fail
        ld      a,(buf)
        or      a
        jp      z,t_fail                ; the drive, 1 = A:
        ld      hl,(buf+29)
        d_hlis  256
        ld      hl,(buf+FC_SIZE)
        d_hlis  256
        ld      a,(buf+FC_RCNT)
        cp      2
        jp      nz,t_fail
        d_fn    _SNEXT
        d_err   0FFh
        ld      hl,n_u
        ld      de,fcb1
        call    fcb_set
        ld      de,fcb1
        d_fn    _FMAKE
        d_ok
        ld      de,fcb1
        d_fn    _FCLOSE
        d_ok
        ld      de,fcb3
        d_fn    _SFIRST
        d_ok
        d_fn    _SNEXT
        d_ok
        d_fn    _SNEXT
        d_err   0FFh
        d_step  13                      ; renamed by pattern
        ld      hl,n_q
        ld      de,fcb3
        call    fcb_set
        ld      hl,n_x
        ld      de,fcb3+17
        ld      bc,11
        ldir
        ld      de,fcb3
        d_fn    _FREN
        d_ok
        ld      hl,n_q
        ld      de,fcb3
        call    fcb_set
        ld      de,fcb3
        d_fn    _SFIRST
        d_err   0FFh
        ld      hl,n_xq
        ld      de,fcb3
        call    fcb_set
        ld      de,fcb3
        d_fn    _SFIRST
        d_ok
        d_fn    _SNEXT
        d_ok
        d_step  14                      ; deleted, once
        ld      hl,n_xu
        ld      de,fcb3
        call    fcb_set
        ld      de,fcb3
        d_fn    _FDEL
        d_ok
        ld      de,fcb3
        d_fn    _SFIRST
        d_err   0FFh
        ld      de,fcb3
        d_fn    _FDEL
        d_err   0FFh
        d_step  15                      ; the FCB and the transfer address
        ld      hl,n_xt                 ;   in page 2
        ld      de,8100h
        call    fcb_set
        ld      de,8100h
        d_fn    _FOPEN
        d_ok
        ld      de,8200h
        d_fn    _SETDTA
        ld      de,8100h
        d_fn    _RDSEQ
        d_ok
        ld      hl,8200h
        ld      de,pat
        ld      bc,128
        call    d_memeq
        jp      nz,t_fail
        ld      de,8100h
        d_fn    _FCLOSE
        d_ok
        d_step  16                      ; six files, six FCBs open, none
        ld      de,pat                  ;   closed: the first still reads
        d_fn    _SETDTA
        ld      b,6                     ; FCB1.DAT to FCB6.DAT, two
        ld      a,'1'                   ;   records each
.mk:    push    bc
        ld      (n_n+3),a
        push    af
        ld      hl,n_n
        ld      de,fcb1
        call    fcb_set
        ld      de,fcb1
        d_fn    _FMAKE
        d_ok
        ld      de,fcb1
        d_fn    _WRSEQ
        d_ok
        ld      de,fcb1
        d_fn    _WRSEQ
        d_ok
        ld      de,fcb1
        d_fn    _FCLOSE
        d_ok
        pop     af
        inc     a
        pop     bc
        djnz    .mk
        ld      de,buf
        d_fn    _SETDTA
        ld      ix,fcbs
        ld      b,6
        ld      a,'1'
.six:   push    bc
        push    ix
        ld      (n_n+3),a
        push    af
        ld      hl,n_n
        push    ix
        pop     de
        call    fcb_set
        pop     af
        pop     ix
        push    ix
        push    af
        push    ix
        pop     de
        d_fn    _FOPEN
        d_ok
        pop     af
        inc     a
        pop     ix
        ld      de,37
        add     ix,de
        pop     bc
        djnz    .six
        ld      de,fcbs                 ; the first: its row went to the
        d_fn    _RDSEQ                  ;   sixth, the file opened again
        d_ok
        ld      hl,buf
        ld      de,pat
        ld      bc,128
        call    d_memeq
        jp      nz,t_fail
        ld      de,fcbs+37*5            ; and the last, still open
        d_fn    _RDSEQ
        d_ok
        ld      hl,buf
        ld      de,pat
        ld      bc,128
        call    d_memeq
        jp      nz,t_fail
        d_step  17                      ; closed, then read: opened again
        ld      de,fcbs
        d_fn    _FCLOSE
        d_ok
        ld      de,fcbs
        d_fn    _RDSEQ
        d_ok
        ld      hl,buf
        ld      de,pat
        ld      bc,128
        call    d_memeq
        jp      nz,t_fail
        ld      de,fcbs
        d_fn    _RDSEQ
        d_err   1
        ld      ix,fcbs
        ld      b,6
.close: push    bc
        push    ix
        push    ix
        pop     de
        d_fn    _FCLOSE
        d_ok
        pop     ix
        ld      de,37
        add     ix,de
        pop     bc
        djnz    .close
        d_step  18                      ; the console on an FCB
        ld      hl,n_con
        ld      de,fcb3
        call    fcb_set
        ld      de,fcb3
        d_fn    _FOPEN
        d_ok
        ld      a,(fcb3+FC_ROW)
        cp      16
        jp      nc,t_fail
        ld      hl,buf
        ld      (hl),' '
        ld      de,buf+1
        ld      bc,127
        ldir
        ld      hl,s_via
        ld      de,buf
        ld      bc,s_vialen
        ldir
        ld      de,fcb3
        d_fn    _WRSEQ
        d_ok
        ld      de,fcb3
        d_fn    _FCLOSE
        d_ok
        d_step  19                      ; the auxiliary input
        d_fn    _AUXIN
        d_err   1Ah
        d_step  20                      ; _EXPLAIN reads its message
        ld      b,D_NOFIL
        ld      de,buf
        d_fn    _EXPLAIN
        d_ok
        ld      hl,buf
        ld      de,s_nofil
        call    d_streq
        jp      nz,t_fail
        ld      b,12h                   ; one the layer does not know
        ld      de,buf
        d_fn    _EXPLAIN
        d_ok
        ld      hl,buf
        ld      de,s_e12
        call    d_streq
        jp      nz,t_fail
        jp      t_ok

; fcb_set — HL -> eleven bytes, DE -> an FCB: the drive 0, the name,
; the rest zero.
fcb_set:
        xor     a
        ld      (de),a
        inc     de
        ld      bc,11
        ldir
        ld      b,37-12
.z:     ld      (de),a
        inc     de
        djnz    .z
        ret

        d_lib   "fcb"
n_t:    db      "FCBT    DAT"
e_t:    db      "FCBT    DAT"
n_u:    db      "FCBU    DAT"
n_q:    db      "FCB?    DAT"
n_x:    db      "XCB?    DAT"
n_xq:   db      "XCB?    DAT"
n_xu:   db      "XCBU    DAT"
n_xt:   db      "XCBT    DAT"
n_n:    db      "FCBn    DAT"
n_con:  db      "CON        "
s_via:  db      "fcb via fcb con",13,10,1Ah
s_vialen equ    $-s_via
s_nofil: db     "File not found",0
s_e12:  db      "Error 12H",0
dta:    dw      0
cmp:    dw      0
fcb1:   ds      37
fcb2:   ds      37
fcb3:   ds      37
fcbs:   ds      37*6
pat:    ds      2048
buf:    ds      2048
