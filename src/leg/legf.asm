; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The legacy layer's files: what a .COM program reaches through the
; MSX-DOS 2 file functions, served over the kernel through the hinge.
; Included by leg.asm, which holds the dispatch, the console and the
; machine; this file holds the drives and their directories, the paths,
; the handles, the file info blocks and the searches, the environment
; strings and the process functions. Written from the MSX-DOS 2 Function
; Call and Program Interface specifications.
;
; A directory is a locator, the volume and its cluster — what the
; kernel's chdir takes with HL = 0 — and never a path: a drive's current
; directory is its cluster (leg_dcwd), a handle's file is its directory
; and its 8.3 alias (leg_fdrow), a file info block carries the directory
; searched and the position reached (FI_*). Every function that names a
; file makes that directory the kernel's current one for the length of
; the call (leg_arg, leg_enter) and gives the program's own back on the
; way out (leg_xdone), so the kernel sees bare names and walks nothing.
; Outside a call the kernel's current directory is the current drive's.
;
; A crossing goes through leg_xsys, which keeps the arguments for the
; program's disk error routine (_DEFER) to have the call repeated, and
; leg_err, which turns the errno into the MSX-DOS code the program sees.

; ---------------------------------------------------------------------
; Crossings

; leg_xsys — C' = the number, A/HL/DE/BC the arguments: the syscall
; through the hinge. EIO and EROFS reach the program's disk error routine
; when it has one: 2 repeats the call, 3 hands the error back, 0 and 1
; end the program with .ABORT and the disk code as the secondary. Returns
; as the syscall did: CF with the errno in A, else the result in HL.
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
        ld      hl,(leg_defer)
        call    .call
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

; leg_fail — A = a DOS code: kept as the last error, CF set. leg_xfail —
; the same after leg_xdone. Preserves the rest.
leg_xfail:
        push    af
        call    leg_xdone
        pop     af
        ret     nc
leg_fail:
        ld      (leg_lasterr),a
        scf
        ret

; ---------------------------------------------------------------------
; Drives and their directories

; leg_phys — A = a logical drive 0-7: A = the physical one, through the
; assignment table. Preserves the rest.
leg_phys:
        push    hl
        push    de
        ld      e,a
        ld      d,0
        ld      hl,leg_assign
        add     hl,de
        ld      a,(hl)
        dec     a
        pop     de
        pop     hl
        ret

; leg_hasdrv — A = a physical drive: NZ when a volume is mounted there.
; Preserves the rest.
leg_hasdrv:
        push    bc
        ld      b,a
        ld      a,(leg_login)
        inc     b
.sh:    dec     b
        jr      z,.t
        rrca
        jr      .sh
.t:     and     1
        pop     bc
        ret

; leg_setcwd — A = a physical drive, HL = a cluster: the kernel's current
; directory. Corrupts everything.
leg_setcwd:
        ld      (leg_loc),a
        ld      (leg_loc+1),hl
        ld      hl,0
        ld      de,leg_loc
        leg_sysx SYS_CHDIR
        ret

; leg_enter — A = a physical drive: its current directory made the
; kernel's. leg_leave — the current drive's made the kernel's, the
; invariant outside a call. Both corrupt everything.
leg_enter:
        push    af
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,leg_dcwd
        add     hl,de
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        pop     af
        jr      leg_setcwd
leg_leave:
        ld      a,(leg_curp)
        jr      leg_enter

; leg_xdone — a path function is over: the kernel's directory back when
; leg_arg or leg_xlate moved it. Preserves A, HL, DE, BC.
leg_xdone:
        push    af
        ld      a,(leg_xback)
        or      a
        jr      z,.same
        push    hl
        push    de
        push    bc
        call    leg_leave
        pop     bc
        pop     de
        pop     hl
        xor     a
        ld      (leg_xback),a
.same:  pop     af
        ret

; ---------------------------------------------------------------------
; Paths

; leg_upper — A = a byte: upper-cased when a letter. Preserves the rest.
leg_upper:
        cp      'a'
        ret     c
        cp      'z'+1
        ret     nc
        sub     20h
        ret

; leg_isterm — A = a byte: Z when it ends a pathname string — a control
; character, a space, or one of " < > | = , ; + [ ]. Preserves the rest.
leg_isterm:
        cp      ' '+1
        jr      c,.yes
        push    hl
        push    bc
        ld      hl,s_terms
        ld      bc,10
        cpir
        pop     bc
        pop     hl
        ret                             ; Z from cpir when found
.yes:   cp      a
        ret
s_terms:        db '"',"<>|=,;+[]"

; leg_xlate — DE -> a DOS drive/path string: the buffer (leg_xbuf) holds
; it as the kernel wants it — upper case, / for \, "/mnt/x/" in front of
; an absolute one, "." for an empty one — and leg_xdrv the physical drive
; it names, leg_xlog the logical. A relative path on another drive has
; that drive's directory made the kernel's first (leg_xback). CF with
; .IDRV or .PLONG. DE -> the terminator. Corrupts everything.
leg_xlate:
        ld      a,(leg_drive)
        ld      (leg_xlog),a
        ld      a,(de)
        or      a
        jr      z,.drv0
        inc     de
        ld      a,(de)
        dec     de
        cp      ':'
        jr      nz,.drv0
        ld      a,(de)
        inc     de
        inc     de
        call    leg_upper
        sub     'A'
        cp      8
        jp      nc,.idrv
        ld      (leg_xlog),a
.drv0:  ld      a,(leg_xlog)
        call    leg_phys
        ld      (leg_xdrv),a
        call    leg_hasdrv
        jp      z,.idrv
        ld      hl,(leg_xbuf)
        ld      a,(de)
        cp      '\'
        jr      z,.abs
        cp      '/'
        jr      z,.abs
        ld      a,(leg_xdrv)
        ld      hl,leg_curp
        cp      (hl)
        jr      z,.rel
        push    de
        call    leg_enter
        pop     de
        ld      a,1
        ld      (leg_xback),a
.rel:   ld      hl,(leg_xbuf)
        jr      .copy
.abs:   inc     de
        ld      hl,(leg_xbuf)
        ld      (hl),'/'
        inc     hl
        ld      (hl),'m'
        inc     hl
        ld      (hl),'n'
        inc     hl
        ld      (hl),'t'
        inc     hl
        ld      (hl),'/'
        inc     hl
        ld      a,(leg_xdrv)
        add     a,'a'
        ld      (hl),a
        inc     hl
        ld      (hl),'/'
        inc     hl
.copy:  ld      bc,(leg_xbuf)
        ld      a,(de)
        call    leg_isterm
        jr      z,.end
        call    leg_upper
        cp      '\'
        jr      nz,.put
        ld      a,'/'
.put:   ld      (hl),a
        inc     hl
        inc     de
        push    hl
        or      a
        sbc     hl,bc
        ld      a,l
        cp      LEG_PATHMAX
        pop     hl
        jr      c,.copy
        ld      a,D_PLONG
        jp      leg_fail
.end:   ; a trailing / dropped, and noted, unless it is the whole path
        xor     a
        ld      (leg_xslash),a
        push    hl
        or      a
        sbc     hl,bc
        ld      a,l
        pop     hl
        or      a
        jr      z,.term                 ; empty: the directory itself
        cp      1
        jr      z,.term
        dec     hl
        ld      a,(hl)
        cp      '/'
        jr      nz,.keep
        ld      a,1
        ld      (leg_xslash),a
        jr      .term
.keep:  inc     hl
.term:  ld      (hl),0
        xor     a
        ret
.idrv:  ld      a,D_IDRV
        jp      leg_fail

; leg_split — the path in (leg_xbuf) split at its last /: the directory
; part stays there — "." when there is none, "/" when the slash is the
; first byte, the whole path when it ended in a slash (leg_xslash) — and
; the last item goes to leg_name, LEG_NAMEMAX bytes at most, cut short
; beyond. Corrupts AF, HL, DE, BC.
leg_split:
        ld      a,(leg_xslash)
        or      a
        jr      z,.find
        xor     a
        ld      (leg_name),a            ; no last item
        ret
.find:  ld      hl,(leg_xbuf)
        ld      d,h
        ld      e,l                     ; de -> the last item's start
.scan:  ld      a,(hl)
        or      a
        jr      z,.at
        inc     hl
        cp      '/'
        jr      nz,.scan
        ld      d,h
        ld      e,l
        jr      .scan
.at:    push    de                      ; the item's start
        ld      hl,leg_name
        ex      de,hl
        ld      b,LEG_NAMEMAX-1
.cp:    ld      a,(hl)
        ld      (de),a
        or      a
        jr      z,.copied
        inc     hl
        inc     de
        djnz    .cp
        xor     a
        ld      (de),a
.copied:
        pop     hl                      ; the item's start
        ld      de,(leg_xbuf)
        or      a
        sbc     hl,de                   ; hl = its offset in the buffer
        ld      a,h
        or      l
        jr      nz,.dir
        ex      de,hl                   ; a bare name: the directory is .
        ld      (hl),'.'
        inc     hl
        ld      (hl),0
        ret
.dir:   dec     hl                      ; the slash's offset
        ld      a,h
        or      l
        add     hl,de                   ; -> the slash
        jr      nz,.cut
        inc     hl                      ; "/NAME": the directory is /
.cut:   ld      (hl),0
        ret

; leg_arg — DE -> a DOS string, or a file info block (FFh first): the
; directory it names made the kernel's current one (leg_xback), leg_xdrv
; and leg_xcur its drive and cluster, leg_name the last item — empty for
; a string that ends in \ or names a drive alone. CF with the code:
; .IDRV, .PLONG, .NODIR. Corrupts everything.
leg_arg:
        ld      hl,leg_path
        ld      (leg_xbuf),hl
        ld      a,(de)
        inc     a
        jr      z,.fib
        call    leg_xlate
        ret     c
        call    leg_split
        ld      hl,(leg_xbuf)
        ld      de,leg_rec
        leg_sysx SYS_STATL
        call    leg_err
        jr      c,.nodir
        ld      a,(leg_rec+DE_ATTR)
        and     DA_DIR
        jr      z,.nodir
        ld      hl,(leg_rec+DE_NAME+DE_LOC+DL_CLUS)
        ld      (leg_xcur),hl
        ld      a,(leg_xdrv)
        call    leg_setcwd
        call    leg_err
        ret     c
        ld      a,1
        ld      (leg_xback),a
        xor     a
        ret
.nodir: ld      a,D_NODIR
        jp      leg_xfail
.fib:   push    de
        pop     ix
        ld      a,(ix+FI_DRIVE)
        ld      (leg_xdrv),a
        ld      a,(ix+FI_LOG)
        ld      (leg_xlog),a
        ld      l,(ix+FI_CLUS)
        ld      h,(ix+FI_CLUS+1)
        ld      (leg_xcur),hl
        push    de
        pop     hl
        inc     hl                      ; the name, 13 bytes
        ld      de,leg_name
        ld      bc,13
        ldir
        ld      a,(leg_xdrv)
        ld      hl,(leg_xcur)
        call    leg_setcwd
        call    leg_err
        ret     c
        ld      a,1
        ld      (leg_xback),a
        xor     a
        ret

; leg_isdev — DE -> a string: NZ with A = the device's code when it is
; CON, NUL, AUX or PRN alone, with or without a colon; Z otherwise.
; Preserves DE.
leg_isdev:
        ld      ix,leg_devs
.dev:   ld      a,(ix+0)
        or      a
        jr      z,.no
        push    de
        push    ix
        pop     hl
        ld      b,3
.ch:    ld      a,(de)
        call    leg_upper
        cp      (hl)
        jr      nz,.next
        inc     hl
        inc     de
        djnz    .ch
        ld      a,(de)
        cp      ':'
        jr      nz,.end
        inc     de
        ld      a,(de)
.end:   call    leg_isterm
        jr      nz,.next
        pop     de
        ld      a,(ix+3)
        or      a                       ; NZ: a code is 80h or above
        ret
.next:  pop     de
        ld      bc,4
        add     ix,bc
        jr      .dev
.no:    xor     a
        ret
leg_devs:       db "CON",HD_CON,"NUL",HD_NUL,"AUX",HD_NUL,"PRN",HD_NUL,0

; leg_exp11 — HL -> a name as "NAME.EXT", ending at a terminator, a \,
; a / or a colon: DE -> eleven bytes, name and extension padded with
; spaces, upper case, a * spread as ?s. Out: HL -> what ended it, B =
; the parse flags of the item (DOS2-FCS 3.71, bits 3 to 5). Corrupts AF,
; BC, DE.
leg_exp11:
        ld      c,0
        ld      b,8
        call    .part
        jr      z,.noname
        set     3,c
.noname:
        ld      a,(hl)
        cp      '.'
        jr      nz,.noext
        inc     hl
        ld      b,3
        call    .part
        jr      z,.done
        set     4,c
        jr      .done
.noext: ld      b,3
        call    .pad
.done:  ld      b,c
        ret
; .part — B bytes of a part from HL: the characters to a dot or the end,
; a * spreading ?s, spaces padding, the excess of a long part dropped.
; NZ when a byte was stored.
.part:  xor     a
        ld      (ex_n),a
.p:     ld      a,(hl)
        call    .ends
        jr      z,.padn
        cp      '.'
        jr      z,.padn
        inc     hl
        cp      '*'
        jr      z,.star
        cp      '?'
        jr      nz,.plain
        set     5,c
.plain: call    leg_upper
        ld      (de),a
        inc     de
        ld      a,1
        ld      (ex_n),a
        djnz    .p
.skip:  ld      a,(hl)
        call    .ends
        jr      z,.stored
        cp      '.'
        jr      z,.stored
        inc     hl
        jr      .skip
.star:  set     5,c
        ld      a,1
        ld      (ex_n),a
.starq: ld      a,'?'
        ld      (de),a
        inc     de
        djnz    .starq
        jr      .skip
.padn:  call    .pad
.stored:
        ld      a,(ex_n)
        or      a
        ret
.pad:   ld      a,' '
        ld      (de),a
        inc     de
        djnz    .pad
        ret
.ends:  call    leg_isterm
        ret     z
        cp      '\'
        ret     z
        cp      '/'
        ret     z
        cp      ':'
        ret

; leg_match — HL -> an eleven-byte pattern, DE -> an eleven-byte name:
; Z when every byte matches, ? matching any. Corrupts AF, HL, DE, B.
leg_match:
        ld      b,11
.b:     ld      a,(hl)
        cp      '?'
        jr      z,.any
        ex      de,hl
        cp      (hl)
        ex      de,hl
        ret     nz
.any:   inc     hl
        inc     de
        djnz    .b
        xor     a
        ret

; leg_n11str — HL -> eleven bytes: DE -> "NAME.EXT", 0-terminated, the
; padding dropped, no dot for an empty extension. Corrupts AF, BC, HL,
; DE.
leg_n11str:
        push    de
        ld      b,8
.n:     ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,.nn
        ld      (de),a
        inc     de
.nn:    djnz    .n
        ld      a,(hl)
        cp      ' '
        jr      z,.end
        ld      a,'.'
        ld      (de),a
        inc     de
        ld      b,3
.e:     ld      a,(hl)
        inc     hl
        cp      ' '
        jr      z,.ee
        ld      (de),a
        inc     de
.ee:    djnz    .e
.end:   xor     a
        ld      (de),a
        pop     de
        ret

; ---------------------------------------------------------------------
; Handles

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

; h_new — IX -> the lowest free row, A = its handle; CF with .NHAND.
; Corrupts AF, BC, DE, HL.
h_new:  ld      ix,leg_hand
        ld      c,0
.row:   ld      a,(ix+HN_FD)
        cp      HD_FREE
        jr      z,.got
        ld      de,3
        add     ix,de
        inc     c
        ld      a,c
        cp      LEG_NHAND
        jr      c,.row
        ld      a,D_NHAND
        jp      leg_fail
.got:   ld      a,c
        or      a
        ret

; h_count — A = a descriptor: B = the rows that name it. Corrupts AF, C,
; HL.
h_count:
        ld      hl,leg_hand
        ld      b,0
        ld      c,LEG_NHAND
.row:   cp      (hl)
        jr      nz,.no
        inc     b
.no:    inc     hl
        inc     hl
        inc     hl
        dec     c
        jr      nz,.row
        ret
; h_count.first — A = a descriptor: HL -> the first row that names it.
.first: ld      hl,leg_hand
.f:     cp      (hl)
        ret     z
        inc     hl
        inc     hl
        inc     hl
        jr      .f

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

; h_flags — A = an open mode (bit 0 no write, bit 1 no read, bit 2
; inheritable): A = the row's flags. Preserves the rest.
h_flags:
        and     HF_NOWR|HF_NORD|HF_INH
        ret

; o_flags — A = an open mode: A = the kernel's O_* for it. Preserves the
; rest.
o_flags:
        and     3
        jr      z,.rw                   ; neither bit: both ways
        cp      2
        ld      a,O_WRONLY              ; no read: writes alone
        ret     z
        ld      a,O_RDONLY              ; no write, or neither: reads
        ret
.rw:    ld      a,O_RDWR
        ret

; o_take — the file leg_name in the directory entered is open on
; descriptor (o_fd): its row in leg_fdrow filled from a short stat, a
; handle row taken with the flags (o_hflags), B = the handle. CF with the
; code and the descriptor closed. Corrupts everything.
o_take: ld      hl,leg_name
        ld      de,leg_rec
        leg_sysx SYS_STATL
        call    leg_err
        jr      c,.undo
        ld      a,(o_fd)
        call    h_fdrow
        ld      a,(leg_xdrv)
        ld      (iy+FR_DRIVE),a
        ld      hl,(leg_xcur)
        ld      (iy+FR_CLUS),l
        ld      (iy+FR_CLUS+1),h
        push    iy
        pop     de
        ld      hl,FR_ALIAS
        add     hl,de
        ex      de,hl
        ld      hl,leg_rec+DE_NAME
        ld      bc,13
        ldir
        call    h_new
        jr      c,.undo
        ld      b,a
        ld      a,(o_fd)
        ld      (ix+HN_FD),a
        ld      a,(o_hflags)
        ld      (ix+HN_FLAGS),a
        ld      a,(leg_level)
        ld      (ix+HN_LEVEL),a
        xor     a
        ret
.undo:  push    af
        ld      a,(o_fd)
        leg_sysx SYS_CLOSE
        pop     af
        ret

; o_dev — A = a device code, (o_hflags) the flags: a handle row on the
; device, B = the handle. CF with .NHAND. Corrupts everything.
o_dev:  ld      (o_fd),a
        call    h_new
        ret     c
        ld      b,a
        ld      a,(o_fd)
        ld      (ix+HN_FD),a
        ld      a,(o_hflags)
        or      HF_ASCII
        ld      (ix+HN_FLAGS),a
        ld      a,(leg_level)
        ld      (ix+HN_LEVEL),a
        xor     a
        ret

; _OPEN (43h): DE -> a string or a FIB, A = the open mode. Out: B = the
; handle.
f_open: ld      (o_mode),a
        call    h_flags
        ld      (o_hflags),a
        ld      a,(de)
        inc     a
        jr      z,.file
        call    leg_isdev
        jp      nz,o_dev
.file:  call    leg_arg
        ret     c
        ld      a,(o_mode)
        call    o_flags
        ld      hl,leg_name
        leg_sysx SYS_OPEN
        call    leg_err
        jp      c,leg_xfail
        ld      a,l
        ld      (o_fd),a
        call    o_take
        jp      leg_xfail               ; xdone; A and CF as they are

; _CREATE (44h): DE -> a string, A = the open mode, B = the attributes,
; bit 7 the "create new" flag. Out: B = the handle, FFh for a
; sub-directory.
f_create:
        ld      (o_mode),a
        ld      a,b
        ld      (o_attr),a
        ld      a,(o_mode)
        call    h_flags
        ld      (o_hflags),a
        call    leg_isdev
        jp      nz,o_dev
        call    leg_arg
        ret     c
        call    x_create
        jp      leg_xfail

; x_create — leg_name in the directory entered, (o_attr) the attributes
; and the flag: made as _CREATE says, a file left open on (o_fd) with the
; handle in B, a directory closed with B = FFh. CF with the code.
x_create:
        ld      a,(o_attr)
        and     DA_LABEL
        jr      nz,.iattr
        ld      a,(o_attr)
        and     DA_DIR
        jr      nz,.dir
        ld      a,(o_attr)
        rlca
        jr      nc,.make
        ld      hl,leg_name             ; create new: nothing may be there
        ld      de,leg_rec
        leg_sysx SYS_STATL
        ld      a,D_FILEX
        jp      nc,leg_fail
.make:  ld      a,(o_mode)
        call    o_flags
        or      O_CREAT|O_TRUNC
        cp      O_RDONLY|O_CREAT|O_TRUNC
        jr      nz,.open
        ld      a,O_RDWR|O_CREAT|O_TRUNC ; emptied even when the handle
                                        ; will not write: the row's flags
                                        ; refuse the writes
.open:  ld      hl,leg_name
        leg_sysx SYS_OPEN
        call    leg_err
        ret     c
        ld      a,l
        ld      (o_fd),a
        ld      a,(o_attr)
        and     DA_RDONLY|DA_HIDDEN|DA_SYSTEM
        jr      z,.take
        or      DA_ARCHIVE
        ld      hl,leg_name
        leg_sysx SYS_CHMOD
.take:  jp      o_take
.dir:   ld      hl,leg_name
        leg_sysx SYS_MKDIR
        call    leg_err
        ret     c
        ld      a,(o_attr)
        and     DA_HIDDEN
        jr      z,.dirok
        ld      hl,leg_name
        leg_sysx SYS_CHMOD
.dirok: ld      b,0FFh
        xor     a
        ret
.iattr: ld      a,D_IATTR
        jp      leg_fail

; _CLOSE (45h): B = a handle: its row freed, the descriptor closed when no
; other row names it.
f_close:
        call    h_row
        jr      nc,.open
        cp      D_HDEAD
        ret     nz
        ld      (ix+HN_FD),HD_FREE       ; deleted under it: freed
        xor     a
        ret
.open:  cp      80h
        jr      nc,.free
        push    ix
        call    h_count                 ; b = the rows on the descriptor
        pop     ix
        dec     b
        jr      nz,.free
        ld      a,(ix+HN_FD)
        push    ix                      ; a crossing keeps no register
        leg_sysx SYS_CLOSE
        pop     ix
.free:  ld      (ix+HN_FD),HD_FREE
        xor     a
        ret

; _ENSURE (46h): B = a handle. Write-through: nothing to flush.
f_ensure:
        call    h_row
        ret     c
        xor     a
        ret

; _DUP (47h): B = a handle. Out: B = a second handle on the same file.
f_dup:  call    h_row
        ret     c
        ld      c,(ix+HN_FLAGS)
        push    af
        push    bc
        call    h_new
        pop     bc
        jr      c,.no
        ld      b,a
        pop     af
        ld      (ix+HN_FD),a
        ld      (ix+HN_FLAGS),c
        ld      a,(leg_level)
        ld      (ix+HN_LEVEL),a
        xor     a
        ret
.no:    pop     bc
        ld      a,D_NHAND
        jp      leg_fail

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

; _SEEK (4Ah): B = a handle, A = the method, DE:HL = the offset. Out:
; DE:HL = the position.
f_seek: push    af
        push    hl
        push    de
        call    h_row
        pop     de
        pop     hl
        jr      c,.no
        cp      80h
        jr      nc,.devs
        pop     af
        ld      b,a                     ; the whence
        ld      a,(ix+HN_FD)
        leg_sysx SYS_LSEEK
        jp      leg_err
.devs:  pop     af
        ld      hl,0
        ld      de,0
        xor     a
        ret
.no:    pop     bc
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

; _HTEST (4Ch): B = a handle, DE -> a string or a FIB. Out: B = FFh when
; they name the same file, 0 when not.
f_htest:
        push    de
        call    h_row
        pop     de
        ret     c
        cp      80h
        jr      nc,.not
        push    ix
        push    de
        call    h_fdrow                 ; corrupts DE
        pop     de
        push    iy
        call    leg_arg
        pop     iy
        pop     ix
        ret     c
        push    iy                      ; a crossing keeps no register
        ld      hl,leg_name
        ld      de,leg_rec
        leg_sysx SYS_STATL
        pop     iy
        call    leg_err
        jp      c,leg_xfail
        ld      a,(leg_xdrv)
        cp      (iy+FR_DRIVE)
        jr      nz,.no
        ld      hl,(leg_xcur)
        ld      a,(iy+FR_CLUS)
        cp      l
        jr      nz,.no
        ld      a,(iy+FR_CLUS+1)
        cp      h
        jr      nz,.no
        push    iy
        pop     hl
        ld      de,FR_ALIAS
        add     hl,de
        ld      de,leg_rec+DE_NAME
        call    leg_streq
        jr      nz,.no
        ld      b,0FFh
        xor     a
        jp      leg_xdone
.no:    ld      b,0
        xor     a
        jp      leg_xdone
.not:   ld      b,0
        xor     a
        ret

; leg_streq — HL, DE -> 0-terminated strings: Z when equal. Corrupts AF,
; HL, DE.
leg_streq:
        ld      a,(de)
        cp      (hl)
        ret     nz
        or      a
        ret     z
        inc     hl
        inc     de
        jr      leg_streq

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

; ---------------------------------------------------------------------
; Searches

; _FFIRST (40h): DE -> a string, or a FIB naming a directory with the
; name in HL; B = the attributes wanted; IX -> the FIB to fill.
f_ffirst:
        ld      (s_fib),ix
        ld      a,b
        ld      (s_attr),a
        and     DA_LABEL
        jp      nz,.nofil               ; no volume label is shown
        ld      a,(de)
        inc     a
        jr      z,.fib
        call    leg_arg
        ret     c
        call    s_wpath                 ; the whole path: the directory part
        jr      .go
.fib:   call    s_fibarg
        ret     c
.go:    ld      ix,(s_fib)
        ld      a,(leg_xdrv)
        ld      (ix+FI_DRIVE),a
        ld      a,(leg_xlog)
        ld      (ix+FI_LOG),a
        ld      hl,(leg_xcur)
        ld      (ix+FI_CLUS),l
        ld      (ix+FI_CLUS+1),h
        xor     a
        ld      (ix+FI_POS),a
        ld      (ix+FI_POS+1),a
        ld      (ix+FI_POS+2),a
        ld      (ix+FI_POS+3),a
        ld      a,(s_attr)
        ld      (ix+FI_ATTR),a
        ld      hl,leg_name
        ld      a,(hl)
        or      a
        jr      nz,.pat
        ld      hl,s_starstar           ; no name: *.*
.pat:   push    ix
        pop     de
        ld      bc,FI_PAT
        ex      de,hl
        add     hl,bc
        ex      de,hl
        call    leg_exp11
        call    leg_find
        jp      leg_xfail
.nofil: ld      a,D_NOFIL
        jp      leg_fail
.iattr: ld      a,D_IATTR
        jp      leg_fail
s_starstar:     db "*.*",0

; s_fibarg — DE -> a FIB naming a directory, HL -> a name: the directory
; made the kernel's (leg_xback), leg_xdrv, leg_xlog and leg_xcur from the
; FIB, leg_name from HL, the whole path continued. CF with .IATTR for a
; FIB that is no directory. Corrupts everything.
s_fibarg:
        push    hl                      ; the name
        push    de
        pop     ix
        ld      a,(ix+14)               ; the FIB's attribute
        and     DA_DIR
        jr      z,.iattr
        ld      a,(ix+FI_DRIVE)
        ld      (leg_xdrv),a
        ld      a,(ix+FI_LOG)
        ld      (leg_xlog),a
        ld      l,(ix+19)               ; its cluster: the directory
        ld      h,(ix+20)
        ld      (leg_xcur),hl
        ld      a,(leg_xdrv)
        call    leg_setcwd
        call    leg_err
        pop     hl
        ret     c
        ld      a,1
        ld      (leg_xback),a
        ld      de,leg_name             ; the name from HL, cut at a
        ld      b,LEG_NAMEMAX-1         ; terminator
.nm:    ld      a,(hl)
        call    leg_isterm
        jr      z,.nmend
        ld      (de),a
        inc     hl
        inc     de
        djnz    .nm
.nmend: xor     a
        ld      (de),a
        jp      s_wpathfib
.iattr: pop     hl
        ld      a,D_IATTR
        jp      leg_fail

; _FNEXT (41h): IX -> a FIB from a find: the next match.
f_fnext:
        ld      (s_fib),ix
        jp      leg_find

; leg_find — (s_fib) -> a FIB: the directory FI_CLUS on FI_DRIVE searched
; from FI_POS for the next entry matching FI_PAT with the attributes
; FI_ATTR; the FIB filled with it and FI_POS moved past it, or .NOFIL.
; The kernel's directory is the current drive's afterwards. Corrupts
; everything.
leg_find:
        ld      ix,(s_fib)
        ld      a,(ix+FI_DRIVE)
        ld      l,(ix+FI_CLUS)
        ld      h,(ix+FI_CLUS+1)
        call    leg_setcwd
        call    leg_err
        jp      c,.out
        ld      hl,s_dot
        ld      a,O_RDONLY|O_SHORT
        leg_sysx SYS_OPEN
        call    leg_err
        jp      c,.out
        ld      a,l
        ld      (s_fd),a
        ld      ix,(s_fib)
        ld      l,(ix+FI_POS)
        ld      h,(ix+FI_POS+1)
        ld      e,(ix+FI_POS+2)
        ld      d,(ix+FI_POS+3)
        ld      b,SEEK_SET
        leg_sysx SYS_LSEEK
        call    leg_err
        jp      c,.close
.next:  ld      a,(s_fd)
        ld      hl,leg_rec
        leg_sysx SYS_READDIR
        call    leg_err
        jr      c,.close
        ld      a,h
        or      l
        jr      z,.nofil
        ld      ix,(s_fib)
        ld      a,(leg_rec+DE_ATTR)
        ld      b,a
        and     DA_HIDDEN|DA_SYSTEM
        ld      c,a
        ld      a,(ix+FI_ATTR)
        cpl
        and     c
        jr      nz,.next                ; hidden or system, not asked for
        ld      a,b
        and     DA_DIR
        jr      z,.pat
        ld      a,(ix+FI_ATTR)
        and     DA_DIR
        jr      z,.next                 ; a directory, not asked for
.pat:   ld      hl,leg_rec+DE_NAME
        ld      de,s_name11
        call    leg_exp11
        ld      ix,(s_fib)
        push    ix
        pop     hl
        ld      de,FI_PAT
        add     hl,de
        ld      de,s_name11
        call    leg_match
        jr      nz,.next
        ; a match: the position past it, the FIB filled
        ld      a,(s_fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_CUR
        leg_sysx SYS_LSEEK
        call    leg_err
        jr      c,.close
        ld      ix,(s_fib)
        ld      (ix+FI_POS),l
        ld      (ix+FI_POS+1),h
        ld      (ix+FI_POS+2),e
        ld      (ix+FI_POS+3),d
        call    leg_fibfill
        call    s_wpathadd
        xor     a
        jr      .close
.nofil: ld      a,D_NOFIL
        call    leg_fail
.close: push    af
        ld      a,(s_fd)
        leg_sysx SYS_CLOSE
        pop     af
.out:   push    af
        call    leg_leave
        pop     af
        ret
s_dot:          db ".",0

; leg_fibfill — (s_fib) -> a FIB, leg_rec a short record: the FIB's
; public part from it. Corrupts AF, BC, DE, HL.
leg_fibfill:
        ld      de,(s_fib)
        ld      a,0FFh
        ld      (de),a
        inc     de
        ld      hl,leg_rec+DE_NAME
        ld      bc,13
        ldir                            ; the name
        ld      a,(leg_rec+DE_ATTR)
        ld      (de),a                  ; 14: the attribute
        inc     de
        ld      hl,leg_rec+DE_MTIME+2   ; 15-16: the time,
        ld      bc,2
        ldir
        ld      hl,leg_rec+DE_MTIME     ; 17-18: the date
        ld      bc,2
        ldir
        ld      hl,leg_rec+DE_NAME+DE_LOC+DL_CLUS
        ld      bc,2                    ; 19-20: the first cluster
        ldir
        ld      hl,leg_rec+DE_SIZE
        ld      bc,4                    ; 21-24: the size
        ldir
        ld      hl,(s_fib)
        ld      bc,FI_LOG
        add     hl,bc
        ld      a,(hl)
        inc     a
        ld      (de),a                  ; 25: the logical drive, 1 = A:
        ret

; _FNEW (42h): as _FFIRST, but the entry is made: the name with its ?s
; and *s filled from the FIB's template name; B = the attributes, bit 7
; the "create new" flag.
f_fnew: ld      (s_fib),ix
        ld      a,b
        ld      (o_attr),a
        and     DA_LABEL
        jp      nz,x_create.iattr
        ld      a,(de)
        inc     a
        jr      z,.fib
        call    leg_arg
        ret     c
        call    s_wpath
        jr      .go
.fib:   call    s_fibarg
        ret     c
.go:    ; the template: the FIB's name, expanded; the name given,
        ; expanded, its ?s filled from the template; still ambiguous, or
        ; empty, is no name
        ld      hl,(s_fib)
        inc     hl
        ld      de,s_tmpl11
        call    leg_exp11
        ld      hl,leg_name
        ld      a,(hl)
        or      a
        jr      nz,.given
        ld      hl,s_starstar
.given: ld      de,s_name11
        call    leg_exp11
        ld      hl,s_name11
        ld      de,s_tmpl11
        ld      b,11
.fill:  ld      a,(hl)
        cp      '?'
        jr      nz,.keep
        ld      a,(de)
        ld      (hl),a
        cp      '?'
        jp      z,.ifnm
.keep:  inc     hl
        inc     de
        djnz    .fill
        ld      a,(s_name11)
        cp      ' '
        jp      z,.ifnm
        ld      hl,s_name11
        ld      de,leg_name
        call    leg_n11str
        ; made as _CREATE makes it, the descriptor closed at once
        xor     a
        ld      (o_mode),a
        ld      (o_hflags),a
        call    x_create
        jp      c,leg_xfail
        ld      a,b
        cp      0FFh
        jr      z,.made
        push    bc
        ld      a,(o_fd)
        leg_sysx SYS_CLOSE
        pop     bc
        ld      ix,leg_hand             ; the row o_take gave: freed
        ld      d,0
        ld      e,b
        add     ix,de
        add     ix,de
        add     ix,de
        ld      (ix+HN_FD),HD_FREE
.made:  ld      hl,leg_name
        ld      de,leg_rec
        leg_sysx SYS_STATL
        call    leg_err
        jp      c,leg_xfail
        ld      ix,(s_fib)
        ld      a,(leg_xdrv)
        ld      (ix+FI_DRIVE),a
        ld      a,(leg_xlog)
        ld      (ix+FI_LOG),a
        ld      hl,(leg_xcur)
        ld      (ix+FI_CLUS),l
        ld      (ix+FI_CLUS+1),h
        xor     a
        ld      (ix+FI_POS),a
        ld      (ix+FI_POS+1),a
        ld      (ix+FI_POS+2),a
        ld      (ix+FI_POS+3),a
        ld      (ix+FI_ATTR),a
        push    ix
        pop     de
        ld      hl,FI_PAT
        add     hl,de
        ex      de,hl
        ld      hl,s_name11
        ld      bc,11
        ldir
        call    leg_fibfill
        call    s_wpathadd
        xor     a
        jp      leg_xfail
.ifnm:  ld      a,D_IFNM
        jp      leg_xfail

; s_wpath — the whole path string begun from the directory part of the
; string leg_arg translated (leg_path): its /mnt/x and leading / dropped,
; \ for /, and a \ after it when it is not empty; the last item goes
; where leg_wpos points. s_wpathfib — begun from what the FIB search's
; whole path held, its last item now a directory. s_wpathadd — the name
; found written as the last item. Corrupt AF, BC, DE, HL.
s_wpath:
        ld      hl,leg_path
        ld      de,leg_wpath
        call    leg_dosform
s_wpathfib:
        ld      hl,leg_wpath
        ld      a,(hl)
        or      a
        jr      z,.set
.end:   ld      a,(hl)
        or      a
        jr      z,.sep
        inc     hl
        jr      .end
.sep:   ld      (hl),'\'
        inc     hl
.set:   ld      (hl),0
        ld      (leg_wpos),hl
        ret
s_wpathadd:
        ld      de,(leg_wpos)
        ld      hl,leg_rec+DE_NAME
        ld      bc,13
        ldir
        ret

; leg_dosform — HL -> an m6 path (/mnt/x/A/B, /A/B, /, .): DE -> it in
; DOS form — no drive, no leading \, \ between components, "" for a
; root or "." — 0-terminated, at most 63 bytes and a 0. Corrupts AF, BC,
; DE, HL.
leg_dosform:
        ld      a,(hl)
        cp      '.'
        jr      z,.empty
        cp      '/'
        jr      nz,.copy
        inc     hl
        ld      a,(hl)
        cp      'm'
        jr      nz,.copy
        inc     hl
        ld      a,(hl)
        cp      'n'
        jr      nz,.back1
        inc     hl
        ld      a,(hl)
        cp      't'
        jr      nz,.back2
        inc     hl                      ; /mnt: the letter, if any
        ld      a,(hl)
        or      a
        jr      z,.empty
        inc     hl
        inc     hl                      ; past x
        ld      a,(hl)
        or      a
        jr      z,.empty
        inc     hl                      ; past the /
        jr      .copy
.back2: dec     hl
.back1: dec     hl
.copy:  ld      b,63
.c:     ld      a,(hl)
        or      a
        jr      z,.done
        cp      '/'
        jr      nz,.put
        ld      a,'\'
.put:   ld      (de),a
        inc     hl
        inc     de
        djnz    .c
.done:  xor     a
        ld      (de),a
        ret
.empty: xor     a
        ld      (de),a
        ret

; ---------------------------------------------------------------------
; Files and directories by name, FIB or handle

; hx_arg — B = a handle on a file: its directory made the kernel's,
; leg_xdrv, leg_xcur and leg_name from its row. CF with .IHAND, or the
; handle on a device (Z, A = 0: nothing to do). Corrupts everything.
hx_arg: call    h_row
        ret     c
        cp      80h
        jr      nc,.dev
        ld      (hx_fd),a
        ld      (hx_row),ix
        call    h_fdrow
        ld      a,(iy+FR_DRIVE)
        ld      (leg_xdrv),a
        ld      l,(iy+FR_CLUS)
        ld      h,(iy+FR_CLUS+1)
        ld      (leg_xcur),hl
        push    iy
        pop     hl
        ld      de,FR_ALIAS
        add     hl,de
        ld      de,leg_name
        ld      bc,13
        ldir
        ld      a,(leg_xdrv)
        ld      hl,(leg_xcur)
        call    leg_setcwd
        call    leg_err
        ret     c
        ld      a,1
        ld      (leg_xback),a
        or      a                       ; NZ: a file
        ret
.dev:   xor     a                       ; Z: a device
        ret

; _DELETE (4Dh): DE -> a string or a FIB.
f_delete:
        call    leg_arg
        ret     c
        call    x_delete
        jp      leg_xfail
x_delete:
        ld      hl,leg_name
        ld      a,(hl)
        cp      '.'
        jr      nz,.go
        inc     hl
        ld      a,(hl)
        or      a
        jr      z,.dot
        cp      '.'
        jr      nz,.go
        inc     hl
        ld      a,(hl)
        or      a
        jr      z,.dot
.go:    ld      a,1
        ld      (leg_xwr),a
        ld      hl,leg_name
        leg_sysx SYS_UNLINK
        jr      nc,.ok
        cp      E_ISDIR
        jr      nz,.err
        ld      hl,leg_name
        leg_sysx SYS_RMDIR
        jr      nc,.ok
.err:   scf
        call    leg_err
.ok:    push    af
        xor     a
        ld      (leg_xwr),a
        pop     af
        ret
.dot:   ld      a,D_DOT
        jp      leg_fail

; _HDELETE (52h): B = a handle: its file deleted and the handle closed,
; whatever the outcome.
f_hdelete:
        call    hx_arg
        ret     c
        jr      z,.dev
        ld      ix,(hx_row)             ; a crossing keeps no register
        ld      (ix+HN_FD),HD_FREE
        ld      a,(hx_fd)
        leg_sysx SYS_CLOSE              ; the descriptor first: a delete
        ld      a,(hx_fd)               ;   needs the file closed
        ld      hl,leg_hand             ; its duplicates are dead
        ld      b,LEG_NHAND
.dup:   cp      (hl)
        jr      nz,.nd
        ld      (hl),HD_DEAD
.nd:    inc     hl
        inc     hl
        inc     hl
        djnz    .dup
        call    x_delete
        jp      leg_xfail
.dev:   xor     a
        ret

; _RENAME (4Eh): DE -> a string or a FIB, HL -> the new name, whose ?s
; keep the old name's characters.
f_rename:
        push    hl
        call    leg_arg
        pop     hl
        ret     c
        call    x_rename
        jp      leg_xfail
x_rename:
        ld      de,s_new11
        push    hl
        call    leg_exp11
        pop     de
        ld      a,(hl)                  ; what ended the new name: a
        call    leg_isterm              ;   drive or a path is no name
        jr      nz,.ifnm
        ld      hl,leg_name
        ld      de,s_name11
        call    leg_exp11
        ld      hl,s_new11
        ld      de,s_name11
        ld      b,11
.fill:  ld      a,(hl)
        cp      '?'
        jr      nz,.keep
        ld      a,(de)
        ld      (hl),a
.keep:  inc     hl
        inc     de
        djnz    .fill
        ld      a,(s_new11)
        cp      ' '
        jr      z,.ifnm
        ld      hl,s_new11
        ld      de,leg_path2
        call    leg_n11str
        ld      hl,leg_path2            ; the new name must not exist
        ld      de,leg_rec
        leg_sysx SYS_STATL
        ld      a,D_DUPF
        jp      nc,leg_fail
        ld      hl,leg_name
        ld      de,leg_path2
        leg_sysx SYS_RENAME
        jp      leg_err
.ifnm:  ld      a,D_IFNM
        jp      leg_fail

; _HRENAME (53h): B = a handle, HL -> the new name. The kernel renames no
; open file: the descriptor is closed, its position kept, the file renamed
; and opened again by its new name, every handle on it moved to the new
; descriptor (hx_close, hx_reopen).
f_hrename:
        push    hl
        call    hx_arg
        pop     hl
        ret     c
        jr      z,.dev
        push    hl
        call    hx_close
        pop     hl
        jr      c,.fail
        call    x_rename
        jr      c,.back
        call    hx_reopen               ; by the new name, leg_path2
        jp      leg_xfail
.back:  push    af                      ; the old name stands: open again
        ld      hl,leg_name
        ld      de,leg_path2
        ld      bc,14
        ldir
        call    hx_reopen
        pop     af
.fail:  jp      leg_xfail
.dev:   xor     a
        ret

; hx_close — the descriptor hx_fd: its position kept in hx_pos, closed.
; CF with the code. Corrupts everything.
hx_close:
        ld      a,(hx_fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_CUR
        leg_sysx SYS_LSEEK
        call    leg_err
        ret     c
        ld      (hx_pos),hl
        ld      (hx_pos+2),de
        ld      a,(hx_fd)
        leg_sysx SYS_CLOSE
        jp      leg_err

; hx_reopen — the file leg_path2 names, in the kernel's directory, opened
; again for the handles that were on hx_fd: the mode from their row's
; flags, the position hx_pos, the new descriptor's row copied from the
; old one with the alias renewed, hx_fd replaced in every handle row. CF
; with the code, the handles dead. Corrupts everything.
hx_reopen:
        ld      a,(hx_fd)
        call    h_count.first           ; hl -> the first row on it
        ld      a,(hl)
        inc     hl
        ld      a,(hl)                  ; its flags
        and     HF_NOWR|HF_NORD
        call    o_flags
        ld      hl,leg_path2
        leg_sysx SYS_OPEN
        call    leg_err
        jr      c,.dead
        ld      a,l
        ld      (hx_new),a
        ld      hl,(hx_pos)
        ld      de,(hx_pos+2)
        ld      b,SEEK_SET
        leg_sysx SYS_LSEEK
        ld      hl,leg_path2            ; the alias
        ld      de,leg_rec
        leg_sysx SYS_STATL
        ld      a,(hx_fd)
        call    h_fdrow
        push    iy
        pop     hl
        ld      a,(hx_new)
        call    h_fdrow
        push    iy
        pop     de
        ld      bc,FR_SIZE
        ldir                            ; the row copied
        ld      a,(hx_new)
        call    h_fdrow
        ld      a,(leg_xdrv)
        ld      (iy+FR_DRIVE),a
        ld      hl,(leg_xcur)           ; the directory: the new one after
        ld      (iy+FR_CLUS),l          ;   a move
        ld      (iy+FR_CLUS+1),h
        push    iy
        pop     de
        ld      hl,FR_ALIAS
        add     hl,de
        ex      de,hl
        ld      hl,leg_rec+DE_NAME
        ld      bc,13
        ldir
        ld      a,(hx_new)
        ld      c,a
        jr      .move
.dead:  ld      c,HD_DEAD
.move:  ld      a,(hx_fd)
        ld      hl,leg_hand
        ld      b,LEG_NHAND
.row:   cp      (hl)
        jr      nz,.next
        ld      (hl),c
.next:  inc     hl
        inc     hl
        inc     hl
        djnz    .row
        ld      a,c
        cp      HD_DEAD
        jr      z,.hdead
        xor     a
        ret
.hdead: ld      a,D_HDEAD
        jp      leg_fail

; _MOVE (4Fh): DE -> a string or a FIB, HL -> the new directory's path,
; no drive in it.
f_move: push    hl
        call    leg_arg
        pop     hl
        ret     c
        call    x_move
        jp      leg_xfail
x_move: push    hl
        ; the source as an absolute path: its directory's, then the name
        ld      hl,leg_path
        ld      bc,LEG_PATHMAX|8000h
        leg_sysx SYS_GETCWD
        call    leg_err
        jp      c,.pop
        ld      de,leg_path
        add     hl,de                   ; -> the terminator
        ld      a,(leg_path+1)
        or      a
        jr      z,.slashed              ; the root: / is there already
        ld      a,'/'
        ld      (hl),a
        inc     hl
.slashed:
        ex      de,hl
        ld      hl,leg_name
        ld      bc,14
        ldir
        call    leg_leave               ; the destination is relative
        xor     a                       ;   to the program's directory
        ld      (leg_xback),a
        pop     de
        ld      a,(de)
        inc     de
        ld      a,(de)
        dec     de
        cp      ':'
        jp      z,.ipath
        ld      hl,leg_path2
        ld      (leg_xbuf),hl
        call    leg_xlate
        ret     c
        ld      a,(leg_xdrv)
        ld      hl,leg_curp
        cp      (hl)
        jr      nz,.idrv
        ld      hl,leg_path2            ; the destination: a directory,
        ld      de,leg_rec              ;   its cluster kept for a handle
        leg_sysx SYS_STATL
        call    leg_err
        ret     c
        ld      a,(leg_rec+DE_ATTR)
        and     DA_DIR
        jr      z,.nodir
        ld      hl,(leg_rec+DE_NAME+DE_LOC+DL_CLUS)
        ld      (x_mvclus),hl
        ld      hl,leg_path2            ; the directory, then the name
.end:   ld      a,(hl)
        or      a
        jr      z,.at
        inc     hl
        jr      .end
.at:    ld      (hl),'/'
        inc     hl
        ex      de,hl
        ld      hl,leg_name
        ld      bc,14
        ldir
        ld      hl,leg_path2
        ld      de,leg_rec
        leg_sysx SYS_STATL
        ld      a,D_DUPF
        jp      nc,leg_fail
        ld      a,1
        ld      (leg_xwr),a
        ld      hl,leg_path
        ld      de,leg_path2
        leg_sysx SYS_RENAME
        push    af
        xor     a
        ld      (leg_xwr),a
        pop     af
        call    leg_err
        ret     nc
        cp      D_IFNM                  ; EINVAL: a directory into itself
        ret     nz
        ld      a,D_DIRE
        jp      leg_fail
.idrv:  ld      a,D_IDRV
        jp      leg_fail
.ipath: ld      a,D_IPATH
        jp      leg_fail
.nodir: ld      a,D_NODIR
        jp      leg_fail
.pop:   pop     hl
        ret

; _HMOVE (54h): B = a handle, HL -> the new directory's path. As
; _HRENAME: closed, moved, opened again — by the whole new path, which
; x_move leaves in leg_path2 relative to the program's directory.
f_hmove:
        push    hl
        call    hx_arg
        pop     hl
        ret     c
        jr      z,.dev
        push    hl
        call    hx_close
        pop     hl
        jr      c,.fail
        call    x_move
        jr      c,.back
        ld      hl,(x_mvclus)           ; the new directory
        ld      (leg_xcur),hl
        call    hx_reopen
        jp      leg_xfail
.back:  push    af
        call    leg_leave               ; the old name, in the old directory
        ld      a,(leg_xdrv)
        ld      hl,(leg_xcur)
        call    leg_setcwd
        ld      hl,leg_name
        ld      de,leg_path2
        ld      bc,14
        ldir
        call    hx_reopen
        pop     af
.fail:  jp      leg_xfail
.dev:   xor     a
        ret

; _ATTR (50h): DE -> a string or a FIB, A = 0 to get or 1 to set, L =
; the new attributes. Out: L = the attributes.
f_attr: push    af
        push    hl
        call    leg_arg
        pop     hl
        jr      c,.pop
        pop     af
        call    x_attr
        jp      leg_xfail
.pop:   pop     bc
        ret
x_attr: or      a
        jr      z,.get
        ld      a,l
        and     ~(DA_RDONLY|DA_HIDDEN|DA_SYSTEM|DA_ARCHIVE) & 0FFh
        jr      nz,.iattr
        push    hl
        ld      a,l
        ld      hl,leg_name
        leg_sysx SYS_CHMOD
        call    leg_err
        pop     hl
        ret
.get:   ld      hl,leg_name
        ld      de,leg_rec
        leg_sysx SYS_STATL
        call    leg_err
        ret     c
        ld      a,(leg_rec+DE_ATTR)
        ld      l,a
        xor     a
        ret
.iattr: ld      a,D_IATTR
        jp      leg_fail

; _HATTR (55h): B = a handle, A and L as _ATTR.
f_hattr:
        push    af
        push    hl
        call    hx_arg
        pop     hl
        jr      c,.pop
        jr      z,.dev
        pop     af
        call    x_attr
        jp      leg_xfail
.dev:   pop     af
        xor     a
        ret
.pop:   pop     bc
        ret

; _FTIME (51h): DE -> a string or a FIB, A = 0 to get or 1 to set, IX =
; the new time, HL = the new date. Out: DE = the time, HL = the date.
f_ftime:
        push    af
        push    hl
        push    ix
        call    leg_arg
        pop     ix
        pop     hl
        jr      c,.pop
        pop     af
        call    x_ftime
        jp      leg_xfail
.pop:   pop     bc
        ret
x_ftime:
        or      a
        jr      z,.get
        push    ix
        pop     bc                      ; the time
        ex      de,hl                   ; the date
        ld      hl,leg_name
        leg_sysx SYS_UTIME
        jp      leg_err
.get:   ld      hl,leg_name
        ld      de,leg_rec
        leg_sysx SYS_STATL
        call    leg_err
        ret     c
        ld      hl,(leg_rec+DE_MTIME)
        ld      de,(leg_rec+DE_MTIME+2)
        xor     a
        ret

; _HFTIME (56h): B = a handle, A, IX and HL as _FTIME.
f_hftime:
        push    af
        push    hl
        push    ix
        call    hx_arg
        pop     ix
        pop     hl
        jr      c,.pop
        jr      z,.dev
        pop     af
        call    x_ftime
        jp      leg_xfail
.dev:   pop     af
        xor     a
        ret
.pop:   pop     bc
        ret

; ---------------------------------------------------------------------
; Drives and the current directories

; _SELDSK (0Eh): E = a drive, 0 = A:. Out: A = L = the number of drives.
f_seldsk:
        ld      a,e
        cp      8
        jr      nc,.count
        push    af
        call    leg_phys
        call    leg_hasdrv
        jr      z,.skip
        pop     af
        ld      (leg_drive),a
        ld      (0004h),a
        call    leg_phys
        ld      (leg_curp),a
        call    leg_leave
        jr      .count
.skip:  pop     af
.count: ld      a,(leg_login)
        ld      l,0
.bit:   or      a
        jr      z,.done
        srl     a
        inc     l
        jr      .bit
.done:  ld      a,l
        ld      b,0
        ret

; _LOGIN (18h): HL = the login vector, bit 0 for A:.
f_login:
        ld      a,(leg_login)
        ld      l,a
        ld      h,0
        ld      b,h
        ret

; _CURDRV (19h): A = L = the current drive, 0 = A:.
f_curdrv:
        ld      a,(leg_drive)
        ld      l,a
        ld      b,0
        ret

; _ASSIGN (6Ah): B = a logical drive, D = a physical one, 1 = A: for both;
; D = FFh asks, D = 0 clears, B = 0 clears all. Out: D = the physical
; drive.
f_assign:
        ld      a,b
        or      a
        jr      z,.all
        cp      9
        jr      nc,.idrv
        ld      c,d                     ; the physical drive asked for
        ld      l,b
        ld      h,0
        dec     l
        ld      de,leg_assign
        add     hl,de
        ld      a,c
        cp      0FFh
        jr      z,.ask
        or      a
        jr      nz,.set
        ld      a,b                     ; identity
.set:   cp      9
        jr      nc,.idrv
        ld      (hl),a
        call    leg_redrive
.ask:   ld      d,(hl)
        xor     a
        ret
.all:   ld      hl,leg_assign
        ld      b,8
        ld      a,1
.id:    ld      (hl),a
        inc     hl
        inc     a
        djnz    .id
        call    leg_redrive
        ld      d,0
        xor     a
        ret
.idrv:  ld      a,D_IDRV
        jp      leg_fail

; leg_redrive — the current drive's physical drive again, after the
; assignment changed, and the kernel's directory with it.
leg_redrive:
        push    hl
        ld      a,(leg_drive)
        call    leg_phys
        ld      (leg_curp),a
        call    leg_leave
        pop     hl
        ret

; _GETCD (59h): B = a drive, 0 = the current, 1 = A:; DE -> 64 bytes.
; Out: the directory's path, no drive, no leading \, "" for the root.
f_getcd:
        push    de
        ld      a,b
        or      a
        jr      nz,.given
        ld      a,(leg_drive)
        inc     a
.given: dec     a
        cp      8
        jr      nc,.idrv
        call    leg_phys
        ld      c,a
        call    leg_hasdrv
        jr      z,.idrv
        ld      a,c
        call    leg_enter
        ld      hl,leg_path
        ld      bc,LEG_PATHMAX|8000h
        leg_sysx SYS_GETCWD
        call    leg_err
        push    af
        call    leg_leave
        pop     af
        pop     de
        ret     c
        push    de
        ld      hl,leg_path
        call    leg_dosform
        pop     de
        xor     a
        ret
.idrv:  pop     de
        ld      a,D_IDRV
        jp      leg_fail

; _CHDIR (5Ah): DE -> a directory's path: that drive's current directory.
f_chdir:
        ld      hl,leg_path
        ld      (leg_xbuf),hl
        call    leg_xlate
        ret     c
        ld      hl,leg_path
        ld      de,leg_rec
        leg_sysx SYS_STATL
        call    leg_err
        jr      c,.nodir
        ld      a,(leg_rec+DE_ATTR)
        and     DA_DIR
        jr      z,.nodir
        ld      a,(leg_xdrv)
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,leg_dcwd
        add     hl,de
        ld      de,(leg_rec+DE_NAME+DE_LOC+DL_CLUS)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      a,1
        ld      (leg_xback),a           ; the current drive's may be the
        xor     a                       ;   new one: put in place
        jp      leg_xfail
.nodir: ld      a,D_NODIR
        jp      leg_xfail

; _WPATH (5Eh): DE -> 64 bytes: the whole path of the last find. Out: HL
; -> its last item.
f_wpath:
        push    de
        ld      hl,leg_wpath
        ld      bc,64
        ldir
        pop     de
        ld      hl,(leg_wpos)
        ld      bc,leg_wpath
        or      a
        sbc     hl,bc
        add     hl,de
        xor     a
        ret

; _PARSE (5Bh): DE -> a string, B = bit 4 for a volume name. Out: DE ->
; the terminator, HL -> the last item, B = the parse flags, C = the
; logical drive, 1 = A:.
f_parse:
        ld      c,0                     ; the flags
        ld      a,(leg_drive)
        inc     a
        ld      (p_drv),a
        ld      a,(de)
        or      a
        jr      z,.items
        inc     de
        ld      a,(de)
        dec     de
        cp      ':'
        jr      nz,.items
        ld      a,(de)
        call    leg_upper
        sub     'A'
        cp      8
        jr      nc,.idrv
        inc     a
        ld      (p_drv),a
        set     2,c
        inc     de
        inc     de
.items: ld      h,d
        ld      l,e                     ; hl -> the last item
.scan:  ld      a,(de)
        call    leg_isterm
        jr      z,.end
        set     0,c
        inc     de
        cp      '\'
        jr      z,.sep
        cp      '/'
        jr      nz,.scan
.sep:   set     1,c
        ld      h,d
        ld      l,e
        jr      .scan
.end:   push    hl
        push    de
        push    bc
        ld      de,s_name11             ; the last item's own flags
        call    leg_exp11
        ld      a,b
        pop     bc
        or      c
        ld      c,a
        pop     de
        pop     hl
        ld      a,(hl)                  ; . and ..
        cp      '.'
        jr      nz,.flags
        inc     hl
        ld      a,(hl)
        dec     hl
        call    leg_isterm
        jr      z,.dot
        cp      '.'
        jr      nz,.flags
        inc     hl
        inc     hl
        ld      a,(hl)
        dec     hl
        dec     hl
        call    leg_isterm
        jr      nz,.flags
        set     7,c
.dot:   set     6,c
        res     3,c
        res     4,c
.flags: ld      b,c
        ld      a,(p_drv)
        ld      c,a
        xor     a
        ret
.idrv:  ld      a,D_IDRV
        jp      leg_fail

; _PFILE (5Ch): DE -> a string, HL -> eleven bytes. Out: the name
; expanded there, DE -> the terminator, B = the parse flags of the item.
f_pfile:
        push    hl
        ex      de,hl
        call    leg_exp11
        ex      de,hl
        pop     hl
        xor     a
        ret

; _CHKCHR (5Dh): D = the flags, E = a character. Out: E upper-cased
; unless bit 0 of D, bit 4 of D when it ends a name.
f_chkchr:
        ld      a,d
        and     ~(2|4|16) & 0FFh        ; no 16-bit characters here
        ld      d,a
        bit     0,d
        jr      nz,.case
        ld      a,e
        call    leg_upper
        ld      e,a
.case:  ld      a,e
        call    leg_isterm
        jr      z,.term
        cp      '\'
        jr      z,.term
        cp      '/'
        jr      z,.term
        cp      ':'
        jr      z,.term
        cp      '.'
        jr      nz,.done
        bit     3,d                     ; a dot ends a filename part,
        jr      nz,.done                ;   not a volume name
.term:  set     4,d
.done:  xor     a
        ret

; ---------------------------------------------------------------------
; The volume's parameters

; _DPARM (31h): L = a drive, 0 = the current, 1 = A:; DE -> 32 bytes.
f_dparm:
        push    de
        ld      a,l
        call    leg_drvarg
        jr      c,.pop
        ld      hl,leg_sf
        ld      b,0
        leg_sysx SYS_STATFS
        call    leg_err
        pop     de
        ret     c
        push    de
        ld      hl,leg_sf
        ld      bc,32
        ldir
        pop     de
        xor     a
        ret
.pop:   pop     de
        ret

; _ALLOC (1Bh): E = a drive, 0 = the current, 1 = A:. Out: A = sectors
; per cluster, BC = 512, DE = the clusters, HL = the free ones, IX = IY
; = 0 — no parameter block and no table sector to point at.
f_alloc:
        ld      a,e
        call    leg_drvarg
        jr      c,.bad
        ld      hl,leg_sf
        ld      b,1
        leg_sysx SYS_STATFS
        call    leg_err
        jr      c,.bad
        ld      hl,2                    ; the saved IX and IY: zeros
        add     hl,sp
        ld      b,4
.z:     ld      (hl),0
        inc     hl
        djnz    .z
        ld      hl,(leg_sf+SF_FREE)
        ld      de,(leg_sf+SF_MAXCLUS)
        dec     de
        ld      bc,512
        ld      a,(leg_sf+SF_SPC)
        ret
.bad:   ld      a,0FFh                  ; the CP/M form: an error flag
        ld      l,a
        ld      b,0
        ret

; leg_drvarg — A = a drive argument, 0 = the current, 1 = A:: A = the
; physical drive; CF with .IDRV.
leg_drvarg:
        or      a
        jr      nz,.given
        ld      a,(leg_drive)
        inc     a
.given: dec     a
        cp      8
        jr      nc,.idrv
        call    leg_phys
        push    af
        call    leg_hasdrv
        jr      z,.no
        pop     af
        ret
.no:    pop     af
.idrv:  ld      a,D_IDRV
        jp      leg_fail

; ---------------------------------------------------------------------
; The small ones

; _DSKRST (0Dh): the transfer address back to 80h; nothing to flush.
f_dskrst:
        ld      hl,0080h
        ld      (leg_dta),hl
        xor     a
        ld      l,a
        ld      b,a
        ret

; _SETDTA (1Ah): DE = the transfer address. _GETDTA (57h): DE = it.
f_setdta:
        ld      (leg_dta),de
        xor     a
        ld      l,a
        ld      b,a
        ret
f_getdta:
        ld      de,(leg_dta)
        xor     a
        ret

; _VERIFY (2Eh): E = 0 off, else on. _GETVFY (58h): B = FFh on, 0 off.
; Kept and never acted on: the driver is asked for no verification.
f_verify:
        ld      a,e
        or      a
        jr      z,.set
        ld      a,0FFh
.set:   ld      (leg_vfy),a
        xor     a
        ld      l,a
        ld      b,a
        ret
f_getvfy:
        ld      a,(leg_vfy)
        ld      b,a
        xor     a
        ret

; _FLUSH (5Fh): write-through: nothing waits.
f_flush:
        xor     a
        ret

; _DSKCHK (6Eh): A = 0 to get, 1 to set B: 0 enabled, FFh disabled.
; Kept and never acted on.
f_dskchk:
        or      a
        jr      z,.get
        ld      a,b
        ld      (leg_chk),a
.get:   ld      a,(leg_chk)
        ld      b,a
        xor     a
        ret

; _REDIR (70h): A = 0 to get, 1 to set. Nothing is redirected: B = 0.
f_redir:
        ld      b,0
        xor     a
        ret

; _DEFER (64h): DE = the disk error routine, 0 for none.
f_defer:
        ld      (leg_defer),de
        xor     a
        ret

; _FORK (60h): a new level; B = the parent's id, the level before.
f_fork: ld      a,(leg_level)
        ld      b,a
        inc     a
        ld      (leg_level),a
        xor     a
        ret

; _JOIN (61h): B = a level: every handle opened above it closed, the
; level back; 0 closes everything but the standard handles. Out: B = C =
; 0. Segments stay with the program to its end.
f_join: ld      a,(leg_level)
        cp      b
        jr      c,.iproc
        ld      a,b
        ld      (leg_level),a
        ld      ix,leg_hand
        ld      c,0
.row:   ld      a,(ix+HN_FD)
        cp      HD_FREE
        jr      z,.next
        ld      a,(leg_level)
        cp      (ix+HN_LEVEL)
        jr      nc,.next                ; opened at or below the level
        push    bc
        ld      b,c
        push    ix
        call    f_close
        pop     ix
        pop     bc
.next:  ld      de,3
        add     ix,de
        inc     c
        ld      a,c
        cp      LEG_NHAND
        jr      c,.row
        ld      b,0
        ld      c,0
        xor     a
        ret
.iproc: ld      a,D_IPROC
        jp      leg_fail

; _GDATE (2Ah): HL = the year, D = the month, E = the day, A = the
; weekday, 0 = Sunday. _SDATE (2Bh), _STIME (2Dh): A = FFh — the clock
; is never written.
f_gdate:
        leg_sys SYS_TIME                ; HL = the FAT date
        ld      a,l
        and     1Fh
        ld      e,a                     ; the day
        ld      a,h
        rrca
        and     7Fh
        ld      c,a                     ; the year - 1980
        ld      a,l
        rlca
        rlca
        rlca
        and     7
        ld      b,a
        ld      a,h
        and     1
        rlca
        rlca
        rlca
        or      b
        ld      d,a                     ; the month
        push    de
        push    bc
        ; Zeller: h = (d + 13(m+1)/5 + y + y/4 + c/4 + 5c) mod 7, with
        ; January and February the 13th and 14th month of the year
        ; before; 0 = Saturday
        ld      a,c
        add     a,80                    ; the year in the century, 1980+
        ld      c,a                     ; c = 80..179: y = c mod 100
        ld      b,19                    ; the century
        cp      100
        jr      c,.cent
        sub     100
        ld      c,a
        inc     b
.cent:  ld      a,d
        cp      3
        jr      nc,.m
        add     a,12
        ld      d,a
        dec     c
        ld      a,c
        cp      0FFh
        jr      nz,.m
        ld      c,99
        dec     b
.m:     ld      a,d
        inc     a
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; 16(m+1)
        ld      a,l
        sub     d
        dec     a
        sub     d
        dec     a
        sub     d
        dec     a                       ; 13(m+1)
        ld      l,a
        ld      h,0
        push    de
        ld      de,5
        call    leg_div
        pop     de                      ; l = 13(m+1)/5
        ld      a,l
        add     a,e                     ; + the day
        add     a,c                     ; + y
        ld      l,a
        ld      a,c
        srl     a
        srl     a
        add     a,l                     ; + y/4
        ld      l,a
        ld      a,b
        srl     a
        srl     a
        add     a,l                     ; + c/4
        ld      l,a
        ld      a,b
        add     a,a
        add     a,a
        add     a,b                     ; 5c
        add     a,l
        ld      l,a
        ld      h,0
        ld      de,7
        call    leg_div
        ld      a,e                     ; the remainder: 0 = Saturday
        add     a,6
        cp      7
        jr      c,.wd
        sub     7
.wd:    pop     bc
        pop     de
        push    af
        ld      l,c
        ld      h,0
        ld      bc,1980
        add     hl,bc
        pop     af
        ret
f_sdate:
f_stime:
        ld      a,0FFh
        ld      l,a
        ld      b,0
        ret

; leg_div — HL / DE: HL = the quotient, E = the remainder (DE < 256, HL
; < 256). Corrupts AF, BC.
leg_div:
        ld      b,0
.sub:   or      a
        sbc     hl,de
        jr      c,.done
        inc     b
        jr      .sub
.done:  add     hl,de
        ld      e,l
        ld      l,b
        ld      h,0
        ret

; ---------------------------------------------------------------------
; The environment

; leg_stricmp — HL, DE -> 0-terminated strings: Z when equal without
; regard to case. Corrupts AF, HL, DE.
leg_stricmp:
        ld      a,(de)
        call    leg_upper
        ld      b,a
        ld      a,(hl)
        call    leg_upper
        cp      b
        ret     nz
        or      a
        ret     z
        inc     hl
        inc     de
        jr      leg_stricmp

; _GENV (6Bh): HL -> a name, DE -> a buffer, B = its size. Out: the
; value, "" for a name not set; .ELONG when it does not fit.
f_genv: push    de
        push    bc
        call    e_find                  ; hl -> the value
        pop     bc
        pop     de
        ret     c
        push    de
.copy:  ld      a,(hl)
        or      a
        jr      z,.end
        ld      a,b
        or      a
        jr      z,.long
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        dec     b
        jr      .copy
.end:   ld      a,b
        or      a
        jr      z,.long                 ; no room for the 0
        xor     a
        ld      (de),a
        pop     de
        ret
.long:  pop     de
        ld      a,D_ELONG
        jp      leg_fail

; e_find — HL -> a name: HL -> its value, 0-terminated — PARAMETERS and
; PROGRAM made up here, the store searched otherwise, s_empty for a name
; not set. CF with .IENV for a name that is none. Corrupts everything.
e_find: ld      a,(hl)
        or      a
        jr      z,.ienv
        push    hl
        ld      de,s_parameters
        call    leg_stricmp
        pop     hl
        jr      z,.params
        push    hl
        ld      de,s_program
        call    leg_stricmp
        pop     hl
        jr      z,.prog
        ex      de,hl                   ; de -> the name wanted
        ld      hl,leg_env
.pair:  ld      a,(hl)
        or      a
        jr      z,.none
        push    de
        push    hl
        call    e_namecmp               ; hl -> past the =, Z when it is
        pop     bc
        pop     de
        ret     z
        ld      h,b
        ld      l,c
        call    e_skip                  ; past the pair
        jr      .pair
.none:  ld      hl,s_empty
        xor     a
        ret
.params:
        ld      hl,leg_params
        ld      a,(hl)
        cp      ' '
        ret     nz
        inc     hl
        xor     a
        ret
.prog:  call    e_program
        ret
.ienv:  ld      a,D_IENV
        jp      leg_fail
s_parameters:   db "PARAMETERS",0
s_program:      db "PROGRAM",0
s_empty:        db 0

; e_namecmp — HL -> a pair "NAME=value", DE -> a name: Z with HL -> the
; value when the names match. Corrupts AF, HL, DE.
e_namecmp:
        ld      a,(de)
        or      a
        jr      z,.dend
        call    leg_upper
        cp      (hl)
        ret     nz
        inc     hl
        inc     de
        jr      e_namecmp
.dend:  ld      a,(hl)
        cp      '='
        ret     nz
        inc     hl
        ret                             ; Z

; e_skip — HL -> a pair: HL -> the next. Corrupts AF.
e_skip: ld      a,(hl)
        inc     hl
        or      a
        jr      nz,e_skip
        ret

; e_program — HL -> the PROGRAM string, made in leg_path2: the drive, the
; program's directory in DOS form, its alias. Corrupts everything.
e_program:
        ld      a,(LEG_PROG+PR_DRIVE)
        ld      hl,(LEG_PROG+PR_CLUS)
        call    leg_setcwd
        ld      hl,leg_path
        ld      bc,LEG_PATHMAX|8000h
        leg_sysx SYS_GETCWD
        call    leg_err
        push    af
        call    leg_leave
        pop     af
        ret     c
        ld      hl,leg_path2
        ld      a,(LEG_PROG+PR_DRIVE)
        add     a,'A'
        ld      (hl),a
        inc     hl
        ld      (hl),':'
        inc     hl
        ld      (hl),'\'
        inc     hl
        ex      de,hl
        ld      hl,leg_path
        call    leg_dosform
        ld      a,(leg_path2+3)
        or      a
        jr      z,.root
.end:   ld      a,(de)
        or      a
        jr      z,.sep
        inc     de
        jr      .end
.sep:   ld      a,'\'
        ld      (de),a
        inc     de
.root:  ld      hl,LEG_PROG+PR_ALIAS
        ld      bc,13
        ldir
        ld      hl,leg_path2
        xor     a
        ret

; _SENV (6Ch): HL -> a name, DE -> a value: the pair set, an old one
; removed; an empty value removes. .IENV for a name that is none, .NORAM
; when the store is full.
f_senv: push    de
        ld      de,leg_name             ; the name, upper-cased and checked
        ld      b,LEG_NAMEMAX-1
        ld      a,(hl)
        or      a
        jp      z,.ienvp
.nm:    ld      a,(hl)
        or      a
        jr      z,.nmend
        call    leg_isterm
        jp      z,.ienvp
        cp      '='
        jp      z,.ienvp
        call    leg_upper
        ld      (de),a
        inc     hl
        inc     de
        djnz    .nm
        jr      .ienvp                  ; too long for this store
.nmend: ld      (de),a
        ; the old pair, if any, taken out
.search:
        ld      hl,leg_env
.pair:  ld      a,(hl)
        or      a
        jr      z,.add
        push    hl
        ld      de,leg_name
        call    e_namecmp
        pop     hl
        jr      z,.remove
        call    e_skip
        jr      .pair
.remove:
        push    hl                      ; the pair's start
        call    e_skip                  ; hl -> the next pair
        pop     de
.mv:    ld      a,(hl)                  ; the rest moved down, its end 0
        ld      (de),a
        inc     hl
        inc     de
        or      a
        jr      nz,.mv
        ld      a,(hl)
        or      a
        jr      nz,.mv
        ld      (de),a
        jr      .search
.add:   pop     de                      ; hl -> the store's end
        ld      a,(de)
        or      a
        ret     z                       ; an empty value: removed
        ; room: the name, =, the value, two 0s
        push    hl
        push    de
        ld      bc,0
        ld      hl,leg_name
.nl:    ld      a,(hl)
        inc     hl
        inc     bc
        or      a
        jr      nz,.nl
        ex      de,hl
.vl:    ld      a,(hl)
        inc     hl
        inc     bc
        or      a
        jr      nz,.vl
        inc     bc                      ; bc = name+1 + value+1 + 1
        pop     de
        pop     hl
        push    hl
        ld      a,l
        add     a,c
        ld      l,a
        ld      a,h
        adc     a,b
        ld      h,a                     ; hl = the end after the pair
        ld      bc,leg_env+LEG_ENVMAX
        or      a
        sbc     hl,bc
        pop     hl
        jr      nc,.noram
        ex      de,hl                   ; hl -> the value, de -> the end
        push    hl
        ld      hl,leg_name
.cn:    ld      a,(hl)
        or      a
        jr      z,.eq
        ld      (de),a
        inc     hl
        inc     de
        jr      .cn
.eq:    ld      a,'='
        ld      (de),a
        inc     de
        pop     hl
.cv:    ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        or      a
        jr      nz,.cv
        ld      (de),a                  ; the store's end
        ret
.noram: ld      a,D_NORAM
        jp      leg_fail
.ienvp: pop     de
        ld      a,D_IENV
        jp      leg_fail

; _FENV (6Dh): DE = an item number from 1, HL -> a buffer: the item's
; name, "" past the end; .ELONG when it does not fit 255... the buffer
; is the program's: 255 bytes assumed.
f_fenv: push    hl
        ld      a,d
        or      a
        jr      nz,.none
        ld      a,e
        or      a
        jr      z,.none
        dec     a
        ld      hl,s_parameters
        jr      z,.copy
        dec     a
        ld      hl,s_program
        jr      z,.copy
        ld      c,a
        ld      hl,leg_env
.pair:  ld      a,(hl)
        or      a
        jr      z,.none
        dec     c
        jr      z,.name
        call    e_skip
        jr      .pair
.name:  pop     de
        push    de
.cn:    ld      a,(hl)
        cp      '='
        jr      z,.end
        ld      (de),a
        inc     hl
        inc     de
        jr      .cn
.end:   xor     a
        ld      (de),a
        pop     hl
        ret
.copy:  pop     de
        push    de
.cc:    ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        or      a
        jr      nz,.cc
        pop     hl
        ret
.none:  pop     hl
        xor     a
        ld      (hl),a
        ret

