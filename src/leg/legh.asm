; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The legacy layer's files, the part that stays in page 3: the crossing
; with the program's disk error routine behind it, the errno map, the
; handle table's two lookups, and the three handle functions that may
; reach the console — _READ, _WRITE and _IOCTL — with the console as a
; file. Included by leg.asm. The rest of the file functions is the
; layer's body (legf.asm), which is outside page 3 and mapped into page 2
; for the length of a call: a transfer goes straight from here to the
; kernel with the program's own pages in place, a device handle is served
; by the BIOS with the whole TPA in view — a program's hooks point into
; it — and neither ever maps the body. Nothing here may name a label of
; the body's; the body calls into this file freely.

; ---------------------------------------------------------------------
; Crossings

; leg_xsys — C' = the number, A/HL/DE/BC the arguments: the syscall
; through the hinge. EIO and EROFS reach the program's disk error routine
; when it has one: 2 repeats the call, 3 hands the error back, 0 and 1
; end the program with .ABORT and the disk code as the secondary. The
; routine is the program's code and may call the BDOS: when the call in
; progress is the body's, the program's page 2 comes back for the
; routine's length, with interrupts enabled, and the body after it.
; Returns as the syscall did: CF with the errno in A, else the result in
; HL.
leg_xsys:
        ld      (sa_hl),hl
        ld      (sa_de),de
        ld      (sa_bc),bc
        ld      (sa_a),a
        exx
        ld      a,c
        exx
        ld      (sa_n),a
.go:    ld      a,(sa_n)
        exx
        ld      c,a
        exx
        ld      hl,(sa_hl)
        ld      de,(sa_de)
        ld      bc,(sa_bc)
        ld      a,(sa_a)
        call    leg_syscall
.tback:                                 ; (a test makes a disk error here)
        ret     nc
        ld      b,D_DISK
        cp      E_IO
        jr      z,.disk
        ld      b,D_WPROT
        cp      E_ROFS
        scf
        ret     nz
.disk:  push    af                      ; the errno
        ld      hl,(leg_defer)
        ld      a,h
        or      l
        jr      z,.back
        ld      a,b
        ld      (leg_code2),a
        ld      hl,(leg_usp)            ; the handler may call the BDOS:
        push    hl                      ; the program's SP kept
        ld      a,(leg_xwr)
        or      6                       ; ignore not recommended, abort
        ld      c,a                     ;   suggested; a write when it was
        ld      a,(leg_xdrv)
        inc     a
        ld      b,a                     ; the drive
        ld      a,(leg_code2)
        ld      de,0                    ; no sector
        ld      hl,(leg_inb)            ; l = the call in progress
        push    hl
        ld      a,l
        or      a
        call    nz,leg_bout             ; the body's: it stands aside
        ld      a,(leg_code2)
        ld      hl,(leg_defer)
        ei
        call    .call
        pop     hl
        ld      c,a                     ; the routine's answer
        ld      a,l
        or      a
        call    nz,leg_bin              ; the body's call: the body back
        ld      a,c
        pop     hl
        ld      (leg_usp),hl
        cp      2
        jr      z,.retry
        cp      3
        jr      z,.back
        ld      a,(leg_code2)
        ld      b,a
        ld      a,D_ABORT
        jp      leg_term2
.retry: pop     af
        jr      .go
.back:  pop     af
        scf
        ret
.call:  jp      (hl)

; leg_fail — A = a DOS code: kept as the last error, CF set. Preserves
; the rest.
leg_fail:
        ld      (leg_lasterr),a
        scf
        ret

; leg_err — after a crossing: A = 0 when it succeeded, else the errno
; mapped to its MSX-DOS code, kept in leg_lasterr, CF set. Preserves HL,
; DE, BC.
leg_err:
        jr      c,.map
        xor     a
        ret
.map:   push    hl
        push    bc
        ld      hl,leg_emap
        ld      b,a
.find:  ld      a,(hl)
        or      a
        jr      z,.dflt
        cp      b
        inc     hl
        jr      z,.got
        inc     hl
        jr      .find
.dflt:  inc     hl
.got:   ld      a,(hl)
        ld      (leg_lasterr),a
        pop     bc
        pop     hl
        scf
        ret
leg_emap:
        db      E_NOENT,D_NOFIL, E_NOTDIR,D_NODIR, E_ISDIR,D_DIRX
        db      E_EXIST,D_DUPF, E_NOTEMPTY,D_DIRNE, E_ACCES,D_FILRO
        db      E_BUSY,D_FOPEN, E_NOSPC,D_DKFUL, E_INVAL,D_IFNM
        db      E_NAMETOOLONG,D_PLONG, E_XDEV,D_IDRV, E_MFILE,D_NHAND
        db      E_NFILE,D_NHAND, E_BADF,D_IHAND, E_FAULT,D_IPARM
        db      E_2BIG,D_IPARM, E_NOMEM,D_NORAM, E_NODEV,D_IDRV
        db      E_IO,D_DISK, E_ROFS,D_WPROT
        db      0,D_INTER

; h_row — B = a handle: IX -> its row, A = its HN_FD. CF with .IHAND for
; one not open. Corrupts AF, DE, HL.
h_row:  ld      a,b
        cp      LEG_NHAND
        jr      nc,.ihand
        ld      l,a
        ld      h,0
        ld      e,l
        ld      d,h
        add     hl,hl
        add     hl,de                   ; * 3
        ld      de,leg_hand
        add     hl,de
        push    hl
        pop     ix
        ld      a,(ix+HN_FD)
        cp      HD_FREE
        jr      z,.ihand
        cp      HD_DEAD
        jr      z,.hdead
        or      a
        ret
.ihand: ld      a,D_IHAND
        jp      leg_fail
.hdead: ld      a,D_HDEAD
        jp      leg_fail

; h_fdrow — A = a descriptor 3-7: IY -> its row in leg_fdrow. Corrupts
; AF, DE, HL.
h_fdrow:
        sub     3
        add     a,a
        add     a,a
        add     a,a
        add     a,a                     ; * 16
        ld      l,a
        ld      h,0
        ld      de,leg_fdrow
        add     hl,de
        push    hl
        pop     iy
        ret

; _READ (48h): B = a handle, DE = the buffer, HL = bytes. Out: HL =
; bytes read; .EOF when a read of some bytes reads none. A program may
; ask for more than its memory holds from the buffer on, sure that the
; file is short — MSX-DOS reads what there is — where the kernel refuses
; a range that leaves the process's memory before it reads a byte: the
; count is cut at the TPA's top.
f_read: push    hl
        push    de
        call    h_row
        pop     de
        pop     hl
        ret     c
        bit     1,(ix+HN_FLAGS)          ; HF_NORD
        jr      nz,.accv
        cp      80h
        jr      nc,.dev
        ld      b,h
        ld      c,l
        ex      de,hl                   ; hl = the buffer, bc = the count
        ld      a,b
        or      c
        jr      z,.none
        push    hl
        ex      de,hl
        ld      hl,LEG_BASE
        or      a
        sbc     hl,de                   ; hl = the room from the buffer to
        jr      c,.asis                 ; the TPA's top (a buffer above it
        push    hl                      ; is the kernel's to refuse)
        or      a
        sbc     hl,bc
        pop     hl
        jr      nc,.asis
        ld      b,h
        ld      c,l                     ; no more than the room
.asis:  pop     hl
        push    ix
        ld      a,(ix+HN_FD)
        leg_sysx SYS_READ
        call    leg_err
        pop     ix
        ret     c
        ld      a,h
        or      l
        jr      z,.eof
        res     6,(ix+HN_FLAGS)          ; HF_EOF
        xor     a
        ret
.none:  ld      hl,0
        xor     a
        ret
.eof:   set     6,(ix+HN_FLAGS)
        ld      a,D_EOF
        jp      leg_fail
.accv:  ld      a,D_ACCV
        jp      leg_fail
.dev:   cp      HD_NUL
        jr      z,.eof
        jp      con_read

; _WRITE (49h): B = a handle, DE = the buffer, HL = bytes. Out: HL =
; bytes written.
f_write:
        push    hl
        push    de
        call    h_row
        pop     de
        pop     hl
        ret     c
        bit     0,(ix+HN_FLAGS)          ; HF_NOWR
        jr      nz,.accv
        cp      80h
        jr      nc,.dev
        ld      b,h
        ld      c,l
        ex      de,hl
        ld      a,b
        or      c
        jr      z,.none
        ld      a,1
        ld      (leg_xwr),a
        ld      a,(ix+HN_FD)
        leg_sysx SYS_WRITE
        xor     a
        ld      (leg_xwr),a
        jp      leg_err
.none:  ld      hl,0
        xor     a
        ret
.accv:  ld      a,D_ACCV
        jp      leg_fail
.dev:   cp      HD_NUL
        jp      nz,con_write
        xor     a                       ; NUL: swallowed, HL as asked
        ret

; _IOCTL (4Bh): B = a handle, A = the subfunction, DE = its argument. Out:
; DE = the result.
f_ioctl:
        push    af
        push    de
        call    h_row
        pop     de
        jp      c,.pop
        pop     af
        or      a
        jr      z,.status
        dec     a
        jr      z,.mode
        dec     a
        jr      z,.inrdy
        dec     a
        jp      z,.outrdy
        dec     a
        jp      z,.size
        ld      a,D_ISBFN
        jp      leg_fail
.status:
        ld      a,(ix+HN_FD)
        cp      80h
        jr      nc,.dstat
        push    ix
        call    h_fdrow
        ld      e,(iy+FR_DRIVE)
        pop     ix
        bit     6,(ix+HN_FLAGS)          ; HF_EOF
        jr      z,.file0
        set     6,e
.file0: ld      d,0
        xor     a
        ret
.dstat: ld      e,80h                   ; a device
        cp      HD_CON
        jr      nz,.dst2
        bit     0,(ix+HN_FLAGS)          ; HF_NOWR: not an output device
        jr      nz,.dst1
        set     1,e
.dst1:  bit     1,(ix+HN_FLAGS)          ; HF_NORD: not an input device
        jr      nz,.dst2
        set     0,e
.dst2:  ld      a,(ix+HN_FLAGS)
        and     HF_ASCII|HF_EOF
        or      e
        ld      e,a
        ld      d,0
        xor     a
        ret
.mode:  ld      a,(ix+HN_FD)
        cp      80h
        jr      c,.idev
        ld      a,e
        and     HF_ASCII
        ld      c,a
        ld      a,(ix+HN_FLAGS)
        and     ~HF_ASCII & 0FFh
        or      c
        ld      (ix+HN_FLAGS),a
        xor     a
        ret
.idev:  ld      a,D_IDEV
        jp      leg_fail
.inrdy: ld      a,(ix+HN_FD)
        cp      HD_CON
        jr      z,.key
        cp      HD_NUL
        ld      e,0
        jr      z,.rdy
        ld      e,0FFh
        bit     6,(ix+HN_FLAGS)
        jr      z,.rdy
        ld      e,0
        jr      .rdy
.key:   call    leg_chsns
        ld      e,0
        jr      z,.rdy
        ld      e,0FFh
.rdy:   ld      d,0
        xor     a
        ret
.outrdy:
        ld      e,0FFh
        jr      .rdy
.size:  ld      de,0
        ld      a,(ix+HN_FD)
        cp      HD_CON
        jr      nz,.rdy
        ld      a,(B_CRTCNT)
        ld      d,a
        ld      a,(B_LINLEN)
        ld      e,a
        xor     a
        ret
.pop:   pop     bc
        ret

; ---------------------------------------------------------------------
; The console as a file

; con_read — handle 0 (IX -> its row): DE = the buffer, HL = bytes. In
; ASCII mode a line at a time, read with _BUFIN's editor and delivered
; with CR LF, in pieces when the program asks for less than is left; a
; line that starts with ^Z is the end of the file. In binary mode the
; bytes as typed, unechoed.
con_read:
        bit     5,(ix+HN_FLAGS)          ; HF_ASCII
        jp      z,.bin
        ld      a,(leg_llen)
        or      a
        jr      nz,.give
        push    hl
        push    de
        ld      a,LEG_LINEMAX
        ld      (leg_line),a
        ld      de,leg_line
        call    f_bufin                 ; echoes; a CR at the end
        ld      a,10
        call    leg_chput
        pop     de
        pop     hl
        ld      a,(leg_line+1)          ; the count
        or      a
        jr      z,.crlf
        ld      a,(leg_line+2)
        cp      1Ah
        jr      z,.eof
        ld      a,(leg_line+1)
.crlf:  ld      c,a
        ld      b,0
        push    hl
        ld      hl,leg_line+2
        add     hl,bc
        ld      (hl),13
        inc     hl
        ld      (hl),10
        pop     hl
        inc     a
        inc     a
        ld      (leg_llen),a
        xor     a
        ld      (leg_lpos),a
.give:  ld      a,(leg_llen)
        ld      c,a
        ld      a,(leg_lpos)
        ld      b,a
        ld      a,c
        sub     b                       ; a = bytes left in the line
        ld      c,a
        ld      a,h
        or      a
        jr      nz,.all                 ; asked for 256 or more: all left
        ld      a,l
        cp      c
        jr      nc,.all
        ld      c,a                     ; asked for less
.all:   push    bc
        ld      hl,leg_line+2
        ld      a,b
        add     a,l
        ld      l,a
        jr      nc,.src
        inc     h
.src:   ld      b,0
        ld      a,c
        or      a
        jr      z,.zero
        ldir
.zero:  pop     bc
        ld      a,(leg_lpos)
        add     a,c
        ld      (leg_lpos),a
        ld      hl,leg_llen
        cp      (hl)
        jr      nz,.some
        ld      (hl),0                  ; the line is delivered
.some:  ld      l,c
        ld      h,0
        xor     a
        ret
.eof:   xor     a
        ld      (leg_llen),a
        set     6,(ix+HN_FLAGS)
        ld      a,D_EOF
        jp      leg_fail
.bin:   push    hl
.byte:  ld      a,h
        or      l
        jr      z,.bdone
        push    hl
        call    leg_chget
        pop     hl
        ld      (de),a
        inc     de
        dec     hl
        jr      .byte
.bdone: pop     hl
        xor     a
        ret

; con_write — a console handle (IX -> its row): DE = the buffer, HL =
; bytes, through the BIOS byte by byte, the break check as _CONOUT makes
; it. In ASCII mode a ^Z ends the write, as it ends a text file: the
; byte is not written and the count returned includes it, which is what
; MSX-DOS 2 answers. The flags ride in C because a BIOS call corrupts IX.
con_write:
        ld      c,(ix+HN_FLAGS)
        push    hl
.byte:  ld      a,h
        or      l
        jr      z,.done
        call    leg_break
        ld      a,(de)
        cp      1Ah
        jr      z,.ctlz
.put:   call    leg_chput
        inc     de
        dec     hl
        jr      .byte
.ctlz:  bit     5,c                     ; HF_ASCII
        jr      z,.put
        dec     hl                      ; the ^Z itself is counted
        pop     de                      ; de = the bytes asked for
        ex      de,hl
        or      a
        sbc     hl,de                   ; hl = asked - left = written
        xor     a
        ret
.done:  pop     hl
        xor     a
        ret
