; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The legacy layer's FCB name functions, in the body: open, make, close,
; search, delete, rename and size, and the door page 3's record
; functions come through (legc.asm): the file behind a stale FCB opened
; again. Included by leg.asm after legf.asm, whose
; drives, paths, handles and searches this reuses: an FCB names a drive
; and eleven bytes, which become a name in the drive's current directory
; or a pattern over it, and a file found is opened as _OPEN opens one,
; on a row of the handle table marked HF_FCB. What the FCB then carries
; is in legc.asm's comment.
;
; The FCB in DE is staged by the door when it lies in page 2 (LK_FIB: 64
; bytes, in and out), so it is read and written here as it stands; the
; transfer address is not, and the search result goes to it through the
; door's IX slot, which fb_found points at it.

; fb_begin — DE -> an FCB: IY and fb_fcb. Preserves the rest.
fb_begin:
        ld      (fb_fcb),de
        push    de
        pop     iy
        ret

; fb_drive — IY -> an FCB: its drive, 0 for the current one, made
; leg_xdrv (physical) and leg_xlog, its current directory's cluster
; leg_xcur. CF with .IDRV. Corrupts AF, DE, HL.
fb_drive:
        ld      a,(iy+FC_DRV)
        or      a
        jr      nz,.given
        ld      a,(leg_drive)
        inc     a
.given: dec     a
        cp      8
        jr      nc,.idrv
        ld      (leg_xlog),a
        call    leg_phys
        ld      (leg_xdrv),a
        call    leg_hasdrv
        jr      z,.idrv
        ld      a,(leg_xdrv)
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,leg_dcwd
        add     hl,de
        ld      a,(hl)
        inc     hl
        ld      h,(hl)
        ld      l,a
        ld      (leg_xcur),hl
        xor     a
        ret
.idrv:  ld      a,D_IDRV
        jp      leg_fail

; fb_enter — the directory leg_xdrv, leg_xcur made the kernel's
; (leg_xback). CF with the code. Corrupts everything.
fb_enter:
        ld      a,(leg_xdrv)
        ld      hl,(leg_xcur)
        call    leg_setcwd
        call    leg_err
        ret     c
        ld      a,1
        ld      (leg_xback),a
        xor     a
        ret

; fb_name11 — IY -> an FCB: leg_name = its eleven bytes as "NAME.EXT";
; Z when the name holds no ?. Corrupts AF, BC, DE, HL.
fb_name11:
        push    iy
        pop     hl
        inc     hl
        ld      de,leg_name
        call    leg_n11str
        ld      hl,leg_name
.q:     ld      a,(hl)
        or      a
        ret     z
        cp      '?'
        ret     z
        inc     hl
        jr      .q

; fb_find — IY -> an FCB, leg_xdrv, leg_xlog, leg_xcur its drive: the
; search begun over its eleven bytes in the drive's directory, files
; only (hidden ones too, not system ones, no directories), the extent
; of FC_EXTL kept for the matches to hold; the first match in leg_rec,
; s_fcbfib the search. fb_next — the next. CF with .NOFIL. Corrupt
; everything.
fb_find:
        ld      a,(iy+FC_EXTL)
        ld      (s_fcbext),a
        ld      ix,s_fcbfib
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
        ld      (ix+FI_ATTR),DA_HIDDEN
        push    iy
        pop     hl
        inc     hl
        ld      de,s_fcbfib+FI_PAT
        ld      b,11
.pat:   ld      a,(hl)
        call    leg_upper
        ld      (de),a
        inc     hl
        inc     de
        djnz    .pat
fb_next:
        ld      ix,s_fcbfib
        ld      (s_fib),ix
        call    leg_find
        ret     c
        call    fb_entry                ; the extent held: a record count
        jr      nz,.held                ;   of 0 says it is not — unless
        ld      a,(s_fcbext)            ;   it is extent 0, which every
        or      a                       ;   file holds, the empty one too
        jr      nz,fb_next
.held:  xor     a
        ret

; fb_entry — leg_rec a file's record, s_fcbext an extent: the entry as
; _SFIRST leaves it in the transfer address, built in the door's IX
; staging buffer — the drive, then the entry as a directory holds it,
; the extent at 0Ch, the attributes at 0Dh, the record count at 0Fh,
; the size at 10h as well as at 1Dh, so that the record functions read
; it as an FCB. Z when the extent is past the end. Corrupts everything.
fb_entry:
        ld      hl,lb_six
        ld      de,lb_six+1
        ld      bc,32
        ld      (hl),0
        ldir
        ld      a,(s_fcbfib+FI_LOG)
        inc     a
        ld      (lb_six),a
        ld      hl,leg_rec+DE_NAME
        ld      de,lb_six+1
        call    leg_exp11
        ld      a,(s_fcbext)
        ld      (lb_six+FC_EXTL),a
        ld      a,(leg_rec+DE_ATTR)
        ld      (lb_six+FC_ATTR),a
        ld      hl,leg_rec+DE_SIZE
        ld      de,lb_six+FC_SIZE
        ld      bc,4
        ldir
        ld      hl,leg_rec+DE_MTIME+2   ; the time, the date,
        ld      de,lb_six+23
        ld      bc,2
        ldir
        ld      hl,leg_rec+DE_MTIME
        ld      bc,2
        ldir
        ld      hl,leg_rec+DE_NAME+DE_LOC+DL_CLUS
        ld      bc,2                    ; the first cluster,
        ldir
        ld      hl,leg_rec+DE_SIZE
        ld      bc,4                    ; the size
        ldir
        ld      iy,lb_six
        jp      fc_rcnt

; fb_lookup — IY -> an FCB, (fb_fcb) its address: the file it names —
; the first match of an ambiguous name, files only, holding the
; extent; an exact name by a stat, neither a directory nor a system
; file — its record in leg_rec, its alias in leg_name, its directory
; leg_xdrv, leg_xcur. CF with .IDRV or .NOFIL. Corrupts everything.
fb_lookup:
        call    fb_drive
        ret     c
        call    fb_name11
        jr      nz,.amb
        call    fb_enter
        ret     c
        ld      hl,leg_name
        ld      de,leg_rec
        leg_sysx SYS_STATL
        call    leg_err
        ret     c
        ld      a,(leg_rec+DE_ATTR)
        and     DA_DIR|DA_SYSTEM
        jr      nz,.nofil
        jr      .alias
.amb:   ld      iy,(fb_fcb)
        call    fb_find
        ret     c
.alias: ld      hl,leg_rec+DE_NAME
        ld      de,leg_name
        ld      bc,13
        ldir
        xor     a
        ret
.nofil: ld      a,D_NOFIL
        jp      leg_fail

; fb_open — leg_name a file in the directory leg_xdrv, leg_xcur, fb_omode
; the kernel's flags: opened, reads alone when the file refuses writes
; or has a writer already; a row taken with HF_FCB (o_take, which stats
; the file into leg_rec); an FCB row closed for it, and its descriptor,
; when the kernel or the table has none free; fb_rown = the row. CF
; with the code. Corrupts everything.
fb_open:
        call    fb_enter
        ret     c
        ld      a,(fb_omode)
        ld      hl,leg_name
        leg_sysx SYS_OPEN
        jr      nc,.got
        cp      E_ACCES                 ; a read-only file, or one another
        jr      z,.ro                   ;   FCB or handle writes: reads
        cp      E_BUSY                  ;   alone
        jr      nz,.chk
.ro:    ld      a,O_RDONLY
        ld      hl,leg_name
        leg_sysx SYS_OPEN
        jr      nc,.gotro
.chk:   cp      E_MFILE                 ; no descriptor: an FCB row's
        jr      z,.evict                ;   taken back, and again
        cp      E_NFILE
        jr      nz,.err
.evict: call    fb_evict
        ret     c
        jr      fb_open
.err:   scf
        jp      leg_err
.gotro: ld      a,HF_FCB|HF_NOWR
        jr      .take
.got:   ld      a,HF_FCB
.take:  ld      (o_hflags),a
        ld      a,l
        ld      (o_fd),a
        call    o_take
        jr      nc,fb_took
        cp      D_NHAND
        scf
        ret     nz
        call    fb_evict                ; the descriptor was closed: again
        ret     c
        jr      fb_open
; fb_took — B = the row taken: fb_rown. NC.
fb_took:
        ld      a,b
        ld      (fb_rown),a
        xor     a
        ret

; fb_evict — an FCB row closed and freed, its descriptor with it when
; no other row names it: the next one after the last taken back, round
; the table. CF with .NHAND when there is none. Corrupts everything.
fb_evict:
        ld      b,LEG_NHAND
        ld      a,(fb_victim)
.row:   inc     a
        cp      LEG_NHAND
        jr      c,.at
        xor     a
.at:    push    af
        call    fc_rowix
        pop     af
        ld      c,(ix+HN_FD)
        inc     c
        jr      z,.next                 ; free
        bit     3,(ix+HN_FLAGS)         ; HF_FCB
        jr      nz,.this
.next:  djnz    .row
        ld      a,D_NHAND
        jp      leg_fail
.this:  ld      (fb_victim),a
        ld      b,a
; fb_closerow — B = a row's index: freed, its descriptor closed when no
; other row names it. Corrupts everything.
fb_closerow:
        call    h_row
        ret     c
        cp      80h
        jr      nc,.free
        push    ix
        call    h_count
        pop     ix
        dec     b
        jr      nz,.free
        ld      a,(ix+HN_FD)
        push    ix
        leg_sysx SYS_CLOSE
        pop     ix
.free:  ld      (ix+HN_FD),HD_FREE
        xor     a
        ret

; fb_fillrow — (fb_fcb) the FCB, fb_rown its row: the row and a new
; stamp written into the FCB and the row's side table, the position
; there 0, where a descriptor just opened stands. NC. Corrupts AF, C,
; HL, IY.
fb_fillrow:
        ld      iy,(fb_fcb)
        ld      a,(fb_rown)
        ld      (iy+FC_ROW),a
        ld      hl,leg_fstamp
        inc     (hl)
        ld      a,(hl)
        ld      (iy+FC_STAMP),a
        ld      c,a
        ld      a,(fb_rown)
        call    fc_fphl
        xor     a
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),c
        ret

; fb_fill — (fb_fcb) the FCB, leg_rec the file's record, leg_xdrv and
; leg_xcur its directory, fb_rown its row: the FCB filled as an open
; fills it (legc.asm's table): the name from the alias, the attributes,
; the extent's high byte 0, the size, the volume id, the row, the stamp,
; the locator, the record count. Corrupts everything.
fb_fill:
        ld      hl,leg_rec+DE_NAME
        ld      de,(fb_fcb)
        inc     de
        call    leg_exp11
        ld      iy,(fb_fcb)
        ld      a,(leg_rec+DE_ATTR)
        ld      (iy+FC_ATTR),a
        ld      (iy+FC_EXTH),0
        push    iy
        pop     hl
        ld      de,FC_SIZE
        add     hl,de
        ex      de,hl
        ld      hl,leg_rec+DE_SIZE
        ld      bc,4
        ldir
        ld      a,(leg_xdrv)            ; de -> the volume id
        ld      (de),a
        ld      (iy+FC_LDRV),a
        inc     de
        ex      de,hl
        ld      b,FC_CREC-FC_VOL-1
.z:     ld      (hl),0
        inc     hl
        djnz    .z
        ld      hl,(leg_xcur)
        ld      (iy+FC_LCLUS),l
        ld      (iy+FC_LCLUS+1),h
        call    fb_fillrow
        ld      iy,(fb_fcb)
        jp      fc_rcnt

; The answers of an FCB name function: A = L = 0, or FFh, B = 0, the
; kernel's directory the program's again. fb_done — from the carry.
fb_done:
        jr      c,fb_ff
fb_ok:  xor     a
        jr      fb_answer
fb_ff:  ld      a,0FFh
fb_answer:
        push    af
        call    leg_xdone
        pop     af
        ld      l,a
        ld      b,0
        ret

; ---------------------------------------------------------------------
; The functions

; _FOPEN (0Fh): DE -> an unopened FCB: the file it names opened — the
; first match of an ambiguous name — for reading and writing, the FCB
; filled; a device name a device row.
f_fopen:
        call    fb_begin
        call    fb_reuse
        call    fb_name11
        ld      de,leg_name
        call    leg_isdev
        jr      z,fb_openfile
        call    fb_opendev
        jr      fb_done
; fb_openfile — the file (fb_fcb) names, opened and the FCB filled: the
; tail of _FOPEN and of _FMAKE on an existing extent.
fb_openfile:
        ld      iy,(fb_fcb)
        call    fb_lookup
        jr      c,fb_ff
        ld      a,O_RDWR
fb_openas:                              ; A = the kernel's flags
        ld      (fb_omode),a
        call    fb_open
        jr      c,fb_ff
        call    fb_fill
        jr      fb_ok
; fb_reuse — IY -> an FCB: when it is open already, its row freed and
; its descriptor closed first — MSX-DOS opens an open FCB again as if it
; were not, and the kernel's one writer must be given back for that.
; Corrupts everything but IY.
fb_reuse:
        call    fc_valid
        ret     c
        ld      a,(fc_rown)
        ld      b,a
        push    iy
        call    fb_closerow
        pop     iy
        ret

; fb_opendev — A = a device's code: a row on it, the FCB (fb_fcb) given
; the row and a stamp. CF with .NHAND. Corrupts everything.
fb_opendev:
        push    af
        ld      a,HF_FCB
        ld      (o_hflags),a
        pop     af
        call    o_dev
        ret     c
        call    fb_took
        jp      fb_fillrow

; _FMAKE (16h): DE -> an unopened FCB: with the extent 0, the file made
; anew — one that exists is emptied; with another extent, the existing
; file opened as _FOPEN opens it. An ambiguous name is .IFNM.
f_fmake:
        call    fb_begin
        call    fb_reuse
        call    fb_name11
        jr      nz,.ifnm
        ld      a,(iy+FC_EXTL)
        or      a
        jr      nz,fb_openfile
        call    fb_drive
        jr      c,fb_ff
        ld      a,O_RDWR|O_CREAT|O_TRUNC
        jr      fb_openas
.ifnm:  ld      a,D_IFNM
        call    leg_fail
        jr      fb_ff

; _FCLOSE (10h): DE -> an opened FCB: its row freed, the descriptor
; closed when no other row names it (fb_reuse). Nothing waits to be
; written. A stale FCB has nothing to close: 0 too.
f_fclose:
        call    fb_begin
        call    fb_reuse
        jp      fb_ok

; _SFIRST (11h): DE -> an unopened FCB: the first file matching its
; name in its drive's directory — hidden ones too, no system files, no
; directories — that holds the extent; the drive and the directory
; entry into the transfer address. _SNEXT (12h): the next.
f_sfirst:
        call    fb_begin
        call    fb_drive
        jp      c,fb_ff
        call    fb_find
        jr      fb_found
f_snext:
        call    fb_next
; fb_found — fb_entry has built the 33 bytes in the door's IX staging
; buffer: the slot pointed at the transfer address, for the door to
; copy them out on the way back.
fb_found:
        jp      c,fb_ff
        ld      hl,(leg_dta)
        ld      de,LEG_BASE-33
        or      a
        sbc     hl,de
        jr      nc,.iparm
        ld      ix,lb_rix
        ld      hl,(leg_dta)
        ld      (ix+LS_PTR),l
        ld      (ix+LS_PTR+1),h
        ld      (ix+LS_LEN),33
        ld      (ix+LS_FLAGS),3
        jp      fb_ok
.iparm: ld      a,D_IPARM
        call    leg_fail
        jp      fb_ff

; fb_walk — IY -> an unopened FCB, HL = a routine: the routine called
; for every file matching the FCB's name but system and hidden ones,
; with leg_rec its record and leg_name its alias; it returns CF to stop
; the walk with its error, and NZ when it did something. A = 0 when
; anything was done, FFh when nothing, the walk's error kept. Corrupts
; everything.
fb_walk:
        ld      (fb_each),hl
        call    fb_drive
        jp      c,fb_ff
        call    fb_find
        jp      c,fb_ff
        xor     a
        ld      (fb_any),a
.each:  ld      a,(leg_rec+DE_ATTR)
        and     DA_SYSTEM|DA_HIDDEN
        jr      nz,.next
        ld      hl,leg_rec+DE_NAME
        ld      de,leg_name
        ld      bc,13
        ldir
        ld      hl,(fb_each)
        call    .call
        jp      c,fb_ff
        jr      z,.next
        ld      a,1
        ld      (fb_any),a
.next:  call    fb_next
        jr      nc,.each
        ld      a,(fb_any)
        or      a
        jp      nz,fb_ok
        jp      fb_ff
.call:  jp      (hl)

; _FDEL (13h): DE -> an unopened FCB: every file matching its name
; deleted, but system, hidden and read-only ones. FFh when none was.
f_fdel: call    fb_begin
        ld      hl,.one
        jr      fb_walk
.one:   ld      a,(leg_rec+DE_ATTR)
        and     DA_RDONLY
        ret     nz                      ; Z: left alone
        call    fb_enter
        ret     c
        ld      a,1
        ld      (leg_xwr),a
        ld      hl,leg_name
        leg_sysx SYS_UNLINK
        jr      fb_wrote

; _FREN (17h): DE -> an unopened FCB with a second name at 17: every
; file matching the first renamed to the second, a ? there keeping the
; character it had; system and hidden files left alone. .DUPF stops
; the walk; FFh when none was renamed.
f_fren: call    fb_begin
        ld      hl,.one
        jr      fb_walk
.one:   ld      hl,leg_rec+DE_NAME
        ld      de,s_name11
        call    leg_exp11
        ld      hl,(fb_fcb)
        ld      de,17
        add     hl,de
        ld      de,s_name11
        ld      ix,s_new11f
        ld      b,11
.fill:  ld      a,(hl)
        call    leg_upper
        cp      '?'
        jr      nz,.kp
        ld      a,(de)
.kp:    ld      (ix+0),a
        inc     hl
        inc     de
        inc     ix
        djnz    .fill
        ld      hl,s_new11f
        ld      de,leg_path2
        call    leg_n11str
        call    fb_enter
        ret     c
        ld      hl,leg_path2
        ld      de,leg_rec
        leg_sysx SYS_STATL
        jr      nc,.dupf
        ld      a,1
        ld      (leg_xwr),a
        ld      hl,leg_name
        ld      de,leg_path2
        leg_sysx SYS_RENAME
        jr      fb_wrote
.dupf:  ld      a,D_DUPF
        jp      leg_fail
; fb_wrote — after a walk's write: the write flag down, the errno
; mapped, NZ for the walk when it went through.
fb_wrote:
        push    af
        xor     a
        ld      (leg_xwr),a
        pop     af
        call    leg_err
        ret     c
        inc     a                       ; NZ
        ret

; _FSIZE (23h): DE -> an unopened FCB: the file found as _FOPEN finds
; it, its size in 128-byte records, rounded up, into the random record's
; three bytes; the fourth untouched.
f_fsize:
        call    fb_begin
        call    fb_lookup
        jp      c,fb_ff
        ld      hl,(leg_rec+DE_SIZE)
        ld      de,(leg_rec+DE_SIZE+2)
        ld      bc,127
        add     hl,bc
        jr      nc,.nc
        inc     de
.nc:    call    fc_shr7
        ld      iy,(fb_fcb)
        ld      (iy+FC_RREC),l
        ld      (iy+FC_RREC+1),h
        ld      (iy+FC_RREC+2),e
        jp      fb_ok

; ---------------------------------------------------------------------
; The doors from page 3

; fb_reopen — DE -> an FCB whose row is gone: the file its locator and
; name say, opened again for reading and writing (a device by its
; name), a row taken and written into the FCB with a new stamp; the
; size the FCB holds is kept. A = 0, or FFh with .NOFIL.
fb_reopen:
        call    fb_begin
        ld      a,O_RDWR
        call    fb_again
        jp      fb_done
; fb_again — A = the kernel's flags: the file behind (fb_fcb) opened
; again as fb_reopen says. CF with the code.
fb_again:
        ld      (fb_omode),a
        ld      iy,(fb_fcb)
        ld      a,(iy+FC_LDRV)
        cp      8
        jr      nc,.nofil
        ld      (leg_xdrv),a
        ld      l,(iy+FC_LCLUS)
        ld      h,(iy+FC_LCLUS+1)
        ld      (leg_xcur),hl
        call    fb_name11
        ld      de,leg_name
        call    leg_isdev
        jp      nz,fb_opendev
        call    fb_open
        ret     c
        jp      fb_fillrow
.nofil: ld      a,D_NOFIL
        jp      leg_fail
