; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The legacy layer's FCB record functions, in page 3: sequential, random
; and block reads and writes, the random record set, and the FCB's row.
; Included by leg.asm beside legh.asm. An FCB and the transfer address
; are the program's memory, and the transfer address is a pointer the
; layer keeps, not a register the door stages: from here, with the
; program's own pages in view, both are read and written directly, and
; the bytes move between the kernel and the transfer address through
; _READ and _WRITE (legh.asm), by the program's map; a file's size set
; is the kernel's ftruncate. Nothing here names a label of the body's
; but through fc_doors, a table the door takes.
;
; An open FCB is a row of the handle table (HF_FCB) with a kernel
; descriptor, and the FCB's internal bytes say which row, with a stamp
; the row must still carry: a row recycled or closed since — _FCLOSE, or
; an FCB row taken back when an open finds none free — sends the FCB
; back through the body, which opens the file again by the locator the
; same bytes hold (fb_reopen, legk.asm) and writes the new row and stamp
; in. Beside each row leg_fpos keeps where the kernel's descriptor
; stands, so a record that follows the last needs no seek.

; The FCB (DOS2-PIS §3.6).
FC_DRV          equ 0           ; the drive, 0 = the current, 1 = A:
FC_NAME         equ 1           ; 11: name and extension, blank-padded
FC_EXTL         equ 0Ch         ; the extent, low
FC_ATTR         equ 0Dh         ; the attributes (S1)
FC_EXTH         equ 0Eh         ; the extent, high; the record size, low,
FC_RCNT         equ 0Fh         ;   and high, for the block functions
FC_RSIZ         equ 0Eh         ; 2: the record size, then
FC_SIZE         equ 10h         ; 4: the size, exact
FC_VOL          equ 14h         ; 4: the volume id
FC_ROW          equ 18h         ; the handle row
FC_STAMP        equ 19h         ; its stamp
FC_LDRV         equ 1Ah         ; the file's physical drive and
FC_LCLUS        equ 1Bh         ; 2: its directory's cluster: the locator
FC_CREC         equ 20h         ; the current record, 0-127
FC_RREC         equ 21h         ; 3 or 4: the random record
FC_LEN          equ 25h

; The door into the body for what page 3 asks of it: the dispatch may
; name the body's labels here and nowhere else.
fc_doors:
        dw      fb_reopen               ; 0: the file behind a stale FCB

; fc_rowix — A = a row's index: IX -> its row in leg_hand. fc_fphl — A =
; a row's index: HL -> its side row in leg_fpos. Preserve the rest but
; HL.
fc_rowix:
        push    de
        ld      l,a
        ld      h,0
        ld      e,l
        ld      d,h
        add     hl,hl
        add     hl,de
        ld      de,leg_hand
        add     hl,de
        push    hl
        pop     ix
        pop     de
        ret
fc_fphl:
        push    de
        ld      l,a
        ld      h,0
        ld      e,l
        ld      d,h
        add     hl,hl
        add     hl,hl
        add     hl,de
        ld      de,leg_fpos
        add     hl,de
        pop     de
        ret

; fc_valid — IY -> an FCB: NC with IX -> its row and fc_rown its index
; when the FCB names a row in use, taken by an FCB, with the FCB's
; stamp; CF otherwise. Corrupts AF, DE, HL.
fc_valid:
        ld      a,(iy+FC_ROW)
        cp      LEG_NHAND
        ccf
        ret     c
        ld      (fc_rown),a
        call    fc_rowix
        ld      a,(ix+HN_FD)
        cp      HD_DEAD                 ; dead, or free
        ccf
        ret     c
        bit     3,(ix+HN_FLAGS)         ; HF_FCB
        scf
        ret     z
        ld      a,(fc_rown)
        call    fc_fphl
        ld      de,FP_STAMP
        add     hl,de
        ld      a,(iy+FC_STAMP)
        sub     (hl)
        ret     z                       ; NC from a zero
        scf
        ret

; fc_enter — DE -> an FCB: kept in fc_fcb and IY; fc_valid, or the file
; opened again by the body, which writes the row and the stamp into the
; FCB; then IX -> the row, fc_rown its index. CF when the file is gone.
; Corrupts everything.
fc_enter:
        ld      (fc_fcb),de
        push    de
        pop     iy
        call    fc_valid
        ret     nc
        ld      hl,(fc_doors+0)
fc_door:                                ; HL = the body's routine: called
        ld      (leg_fn),hl             ;   with the FCB, in and out, as
        ld      a,0Fh                   ;   _FOPEN's descriptor has it
        ld      (leg_fnum),a
        ld      de,(fc_fcb)
        call    leg_body
        or      a
        scf
        ret     nz
        ld      iy,(fc_fcb)
        ld      a,(iy+FC_ROW)
        ld      (fc_rown),a
        call    fc_rowix
        or      a
        ret

; The answers: A = L = 1, or 0, B = 0.
fc_one: ld      a,1
        ld      l,a
        ld      b,0
        ret
fc_zero:
        xor     a
        ld      l,a
        ld      b,a
        ret

; fc_rcnt — IY -> an FCB: FC_RCNT = the 128-byte records of the extent in
; FC_EXTH:FC_EXTL that the size holds — 128 for a whole one, 0 for an
; extent past the end; the flags say so (Z for 0). Corrupts AF, BC, DE,
; HL.
fc_rcnt:
        ld      c,(iy+FC_EXTL)
        ld      b,(iy+FC_EXTH)
        ld      a,c
        and     3
        rrca
        rrca
        ld      d,a
        ld      e,0                     ; de = the extent's base, low
        srl     b
        rr      c                       ; bc = its high word
        ld      l,(iy+FC_SIZE)
        ld      h,(iy+FC_SIZE+1)
        or      a
        sbc     hl,de
        ex      de,hl                   ; de = size - base, low
        ld      l,(iy+FC_SIZE+2)
        ld      h,(iy+FC_SIZE+3)
        sbc     hl,bc
        jr      c,.zero                 ; the size is below the extent
        ld      a,h
        or      l
        jr      nz,.full
        ld      a,d
        cp      40h
        jr      nc,.full                ; 16384 or more: the whole extent
        ld      hl,127
        add     hl,de
        add     hl,hl
        ld      a,h                     ; (de + 127) / 128
        jr      .set
.full:  ld      a,128
        jr      .set
.zero:  xor     a
.set:   ld      (iy+FC_RCNT),a
        or      a
        ret

; fc_seqrec — IY -> an FCB: E:HL = the record the extent and the current
; record name. fc_rec2pos — E:HL = a record: fc_pos = it × 128.
; fc_seqpos, fc_rndpos — fc_pos from the extent and the current record,
; or from the three-byte random record. Corrupt AF, B, DE, HL.
fc_seqrec:
        ld      l,(iy+FC_EXTL)
        ld      h,(iy+FC_EXTH)
        ld      e,0
        ld      b,7
.sh:    add     hl,hl
        rl      e
        djnz    .sh
        ld      a,(iy+FC_CREC)
        and     7Fh
        or      l
        ld      l,a
        ret
fc_seqpos:
        call    fc_seqrec
        jr      fc_rec2pos
fc_rndpos:
        ld      l,(iy+FC_RREC)
        ld      h,(iy+FC_RREC+1)
        ld      e,(iy+FC_RREC+2)
fc_rec2pos:
        ld      d,0
        ld      b,7
.sh:    add     hl,hl
        rl      e
        rl      d
        djnz    .sh
        ld      (fc_pos),hl
        ld      (fc_pos+2),de
        ret

; fc_setseq — IY -> an FCB: the extent and the current record set to the
; random record, the record count with them. Corrupts AF, BC, DE, HL.
fc_setseq:
        ld      a,(iy+FC_RREC)
        and     7Fh
        ld      (iy+FC_CREC),a
        ld      l,(iy+FC_RREC)
        ld      h,(iy+FC_RREC+1)
        ld      e,(iy+FC_RREC+2)
        ld      d,0
        call    fc_shr7
        ld      (iy+FC_EXTL),l
        ld      (iy+FC_EXTH),h
        jp      fc_rcnt
; fc_shr7 — DE:HL >>= 7. Corrupts B.
fc_shr7:
        ld      b,7
.sh:    srl     d
        rr      e
        rr      h
        rr      l
        djnz    .sh
        ret

; fc_step — IY -> an FCB: the current record on by one, the next extent
; at 128, the record count recomputed. Corrupts AF, BC, DE, HL.
fc_step:
        ld      a,(iy+FC_CREC)
        inc     a
        and     7Fh
        ld      (iy+FC_CREC),a
        jp      nz,fc_rcnt
        inc     (iy+FC_EXTL)
        jp      nz,fc_rcnt
        inc     (iy+FC_EXTH)
        jp      fc_rcnt

; fc_end — DE:BC = fc_pos + fc_got, where the last transfer ended.
; fc_cmpsz — IY -> an FCB, DE:BC a position: CF when the size is below
; it, Z when it is the size. fc_grow — the size raised to where the
; last transfer ended when that is past it. Corrupt AF, BC, DE, HL.
fc_end: ld      hl,(fc_pos)
        ld      bc,(fc_got)
        add     hl,bc
        ld      b,h
        ld      c,l
        ld      hl,(fc_pos+2)
        ld      de,0
        adc     hl,de
        ex      de,hl
        ret
fc_cmpsz:
        ld      l,(iy+FC_SIZE)
        ld      h,(iy+FC_SIZE+1)
        or      a
        sbc     hl,bc
        ld      (fc_acc),hl
        ld      l,(iy+FC_SIZE+2)
        ld      h,(iy+FC_SIZE+3)
        sbc     hl,de
        ret     c
        ld      a,h
        or      l
        ld      hl,(fc_acc)
        or      h
        or      l
        ret
fc_grow:
        call    fc_end
        call    fc_cmpsz
        ret     nc
        ld      (iy+FC_SIZE),c
        ld      (iy+FC_SIZE+1),b
        ld      (iy+FC_SIZE+2),e
        ld      (iy+FC_SIZE+3),d
        ret

; fc_io — fc_rown the row, fc_pos the position, fc_len the bytes, A = 0
; to read, 1 to write: the kernel's descriptor sought there when it is
; not known to be, then _READ or _WRITE on the row's handle and the
; transfer address, with their cut at the TPA's top and their devices;
; fc_got = the bytes moved, 0 at the end, the row's position advanced.
; CF with the code when the kernel refused, the position unknown then.
; Corrupts everything.
fc_io:  ld      (fc_rw),a
        ld      a,(fc_rown)
        call    fc_rowix
        ld      a,(ix+HN_FD)
        cp      80h
        jr      nc,.xfer                ; a device: no position
        ld      a,(fc_rown)
        call    fc_fphl
        ld      de,fc_pos
        ld      b,4
.cmp:   ld      a,(de)
        cp      (hl)
        jr      nz,.seek
        inc     hl
        inc     de
        djnz    .cmp
        jr      .xfer
.seek:  call    fc_fpinv
        ld      hl,(fc_pos)
        ld      de,(fc_pos+2)
        ld      b,SEEK_SET
        ld      a,(ix+HN_FD)
        leg_sysx SYS_LSEEK
        call    leg_err
        ret     c
        ld      a,(fc_rown)
        call    fc_fphl
        ex      de,hl
        ld      hl,fc_pos
        ld      bc,4
        ldir
.xfer:  ld      a,(fc_rown)
        ld      b,a
        ld      de,(leg_dta)
        ld      hl,(fc_len)
        ld      a,(fc_rw)
        or      a
        jr      nz,.write
        call    f_read
        jr      nc,.got
        cp      D_EOF
        jr      nz,.inval
        ld      hl,0                    ; the end: nothing, no error
        jr      .got
.write: call    f_write
        jr      c,.inval
.got:   ld      (fc_got),hl
        ld      a,(fc_rown)
        call    fc_fphl
        ld      a,(fc_got)
        add     a,(hl)
        ld      (hl),a
        inc     hl
        ld      a,(fc_got+1)
        adc     a,(hl)
        ld      (hl),a
        inc     hl
        ld      a,0
        adc     a,(hl)
        ld      (hl),a
        inc     hl
        ld      a,0
        adc     a,(hl)
        ld      (hl),a
        xor     a
        ret
.inval: push    af
        call    fc_fpinv
        pop     af
        scf
        ret
; fc_fpinv — the row fc_rown's position unknown. Corrupts AF, HL.
fc_fpinv:
        ld      a,(fc_rown)
        call    fc_fphl
        ld      b,4
.b:     ld      (hl),0FFh
        inc     hl
        djnz    .b
        ret

; fc_pad — the transfer address from fc_got to fc_len filled with zeros:
; a partial record is padded, never past the TPA's top. Corrupts AF,
; BC, DE, HL.
fc_pad: ld      hl,(leg_dta)
        ld      de,(fc_len)
        add     hl,de
        jr      c,.top
        ld      de,LEG_BASE
        or      a
        sbc     hl,de
        jr      c,.fits
.top:   ld      hl,LEG_BASE             ; cut at the top
        ld      de,(leg_dta)
        or      a
        sbc     hl,de
        ld      (fc_len),hl
.fits:  ld      hl,(fc_len)
        ld      de,(fc_got)
        or      a
        sbc     hl,de
        ret     z
        ret     c
        ld      b,h
        ld      c,l
        ld      hl,(leg_dta)
        add     hl,de
        ld      (hl),0
        dec     bc
        ld      a,b
        or      c
        ret     z
        ld      d,h
        ld      e,l
        inc     de
        ldir
        ret

; fc_128 — A = 0 to read, 1 to write: one record of 128 at fc_pos. CF as
; fc_io.
fc_128: ld      hl,128
        ld      (fc_len),hl
        jp      fc_io

; ---------------------------------------------------------------------
; The functions

; _RDSEQ (14h): DE -> an opened FCB: the record at the extent and the
; current record into the transfer address, padded with zeros when the
; file ends inside it; the record stepped. A = 1 at the end.
f_rdseq:
        call    fc_enter
        jp      c,fc_one
        call    fc_seqpos
        xor     a
        call    fc_128
        jp      c,fc_one
        ld      hl,(fc_got)
        ld      a,h
        or      l
        jp      z,fc_one
        call    fc_pad
        ld      iy,(fc_fcb)
        call    fc_step
        jp      fc_zero

; _WRSEQ (15h): DE -> an opened FCB: the transfer address's 128 bytes at
; the extent and the current record; the record stepped, the size grown.
; A = 1 when fewer were written (the disk full).
f_wrseq:
        call    fc_enter
        jp      c,fc_one
        call    fc_seqpos
        ld      a,1
        call    fc_128
        jp      c,fc_one
        ld      iy,(fc_fcb)
        call    fc_grow
        call    fc_whole
        jp      nz,fc_one
        call    fc_step
        jp      fc_zero
; fc_whole — Z when the last transfer moved the whole 128 bytes, or went
; to a device, which takes what it takes (a console write ends at a ^Z).
fc_whole:
        ld      a,(fc_rown)
        call    fc_rowix
        ld      a,(ix+HN_FD)
        cp      80h
        jr      c,.file
        xor     a
        ret
.file:  ld      hl,(fc_got)
        ld      de,128
        or      a
        sbc     hl,de
        ret

; _RDRND (21h): DE -> an opened FCB: the record the three-byte random
; record names, the extent and the current record set to it.
f_rdrnd:
        call    fc_enter
        jp      c,fc_one
        call    fc_rndpos
        xor     a
        call    fc_128
        jp      c,fc_one
        ld      iy,(fc_fcb)
        call    fc_setseq
        ld      hl,(fc_got)
        ld      a,h
        or      l
        jp      z,fc_one
        call    fc_pad
        jp      fc_zero

; _WRRND (22h) and _WRZER (28h): DE -> an opened FCB: the transfer
; address's 128 bytes at the random record; the kernel fills what lies
; between the end and it with zeros, which is what _WRZER asks for and
; what _WRRND allows.
f_wrrnd:
        call    fc_enter
        jp      c,fc_one
        call    fc_rndpos
        ld      a,1
        call    fc_128
        jp      c,fc_one
        ld      iy,(fc_fcb)
        call    fc_grow
        call    fc_setseq
        call    fc_whole
        jp      nz,fc_one
        jp      fc_zero

; _SETRND (24h): DE -> an opened FCB: the random record set to the extent
; and the current record; its fourth byte untouched.
f_setrnd:
        push    de
        pop     iy
        call    fc_seqrec
        ld      (iy+FC_RREC),l
        ld      (iy+FC_RREC+1),h
        ld      (iy+FC_RREC+2),e
        jp      fc_zero

; fc_mul — DE:HL × BC, the low 32 bits into DE:HL. Corrupts AF, BC.
fc_mul: xor     a
        ld      (fc_acc),a
        ld      (fc_acc+1),a
        ld      (fc_acc+2),a
        ld      (fc_acc+3),a
.bit:   srl     b
        rr      c
        jr      nc,.no
        ld      a,(fc_acc)
        add     a,l
        ld      (fc_acc),a
        ld      a,(fc_acc+1)
        adc     a,h
        ld      (fc_acc+1),a
        ld      a,(fc_acc+2)
        adc     a,e
        ld      (fc_acc+2),a
        ld      a,(fc_acc+3)
        adc     a,d
        ld      (fc_acc+3),a
.no:    ld      a,b
        or      c
        jr      z,.done
        add     hl,hl
        rl      e
        rl      d
        jr      .bit
.done:  ld      hl,(fc_acc)
        ld      de,(fc_acc+2)
        ret

; fc_div — HL / BC: HL = the quotient, DE = the remainder. Corrupts AF.
fc_div: ld      de,0
        ld      a,16
.bit:   add     hl,hl
        rl      e
        rl      d
        ex      de,hl
        or      a
        sbc     hl,bc
        jr      nc,.sub
        add     hl,bc
        ex      de,hl
        jr      .next
.sub:   ex      de,hl
        inc     l
.next:  dec     a
        jr      nz,.bit
        ret

; fc_blk — IY -> an opened FCB, HL = a record count: the record size from
; the FCB (fc_rsz), the bytes (fc_len = HL × the size, at most 65 535),
; fc_pos = the random record × the size, on four bytes when the size is
; under 64 and three otherwise; fc_n = HL. CF for a size of 0 or a count
; past 64K. Corrupts everything.
fc_blk: ld      (fc_n),hl
        ld      c,(iy+FC_RSIZ)
        ld      b,(iy+FC_RSIZ+1)
        ld      (fc_rsz),bc
        ld      a,b
        or      c
        scf
        ret     z
        ld      de,0
        call    fc_mul
        ld      a,d
        or      e
        scf
        ret     nz
        ld      (fc_len),hl
        ld      l,(iy+FC_RREC)
        ld      h,(iy+FC_RREC+1)
        ld      e,(iy+FC_RREC+2)
        ld      d,(iy+FC_RREC+3)
        call    fc_four
        jr      c,.four
        ld      d,0
.four:  ld      bc,(fc_rsz)
        call    fc_mul
        ld      (fc_pos),hl
        ld      (fc_pos+2),de
        or      a
        ret
; fc_four — CF when the record size is under 64: the random record is
; four bytes. Preserves the rest but AF.
fc_four:
        ld      a,(fc_rsz+1)
        or      a
        ret     nz
        ld      a,(fc_rsz)
        cp      64
        ret

; fc_recs — fc_got, fc_rsz: the records moved, a partial one counted, in
; fc_recs_n; fc_len cut to their end; the random record of the FCB in IY
; moved past them, on the bytes fc_blk used. Corrupts everything but IY.
fc_recs:
        ld      hl,(fc_got)
        ld      bc,(fc_rsz)
        call    fc_div
        ld      a,d
        or      e
        jr      z,.whole
        inc     hl
.whole: ld      (fc_recs_n),hl
        ld      de,0
        ld      bc,(fc_rsz)
        call    fc_mul
        ld      (fc_len),hl
        ld      hl,(fc_recs_n)
        ld      a,(iy+FC_RREC)
        add     a,l
        ld      (iy+FC_RREC),a
        ld      a,(iy+FC_RREC+1)
        adc     a,h
        ld      (iy+FC_RREC+1),a
        ld      a,(iy+FC_RREC+2)
        adc     a,0
        ld      (iy+FC_RREC+2),a
        sbc     a,a
        ld      c,a                     ; FFh when a carry is left
        call    fc_four
        ret     nc
        ld      a,(iy+FC_RREC+3)
        sub     c
        ld      (iy+FC_RREC+3),a
        ret

; fc_short — Z when the records moved are the records asked. Corrupts
; AF, DE, HL.
fc_short:
        ld      hl,(fc_recs_n)
        ld      de,(fc_n)
        or      a
        sbc     hl,de
        ret

; _RDBLK (27h): DE -> an opened FCB, HL = records of the size the FCB
; holds: read from the random record into the transfer address, the
; last partial one padded with zeros; HL = the records read, the random
; record moved past them; A = 1 when fewer than asked.
f_rdblk:
        push    hl
        call    fc_enter
        pop     hl
        jr      c,.bad
        call    fc_blk
        jr      c,.bad
        ld      hl,(fc_len)
        ld      a,h
        or      l
        jr      z,.none
        xor     a
        call    fc_io
        jr      c,.bad
        ld      iy,(fc_fcb)
        call    fc_recs
        call    fc_pad
        call    fc_short
        ld      hl,(fc_recs_n)
        jr      nz,.short
        xor     a
        ret
.short: ld      a,1
        ret
.none:  ld      hl,0
        xor     a
        ret
.bad:   ld      hl,0
        ld      a,1
        ret

; _WRBLK (26h): DE -> an opened FCB, HL = records: written from the
; transfer address at the random record, which moves past them; the
; size grown. HL = 0 sets the size to the random record × the record
; size instead, by the kernel (ftruncate): cut, or grown with zeros. A =
; 1 for a short write, a device, or the kernel's refusal.
f_wrblk:
        push    hl
        call    fc_enter
        pop     hl
        jr      c,.bad
        ld      a,h
        or      l
        jr      z,.size
        call    fc_blk
        jr      c,.bad
        ld      a,1
        call    fc_io
        jr      c,.bad
        ld      iy,(fc_fcb)
        call    fc_grow
        call    fc_recs
        call    fc_short
        jr      nz,.bad
        xor     a
        ret
.bad:   ld      a,1
        ret
.size:  call    fc_blk                  ; the size set by the kernel: cut,
        jr      c,.bad                  ;   or grown with zeros (a device's
        ld      a,(fc_rown)             ;   descriptor is the kernel's to
        call    fc_rowix                ;   refuse)
        ld      a,(ix+HN_FD)
        ld      hl,(fc_pos)
        ld      de,(fc_pos+2)
        leg_sysx SYS_FTRUNC
        call    leg_err
        jr      c,.bad
        ld      iy,(fc_fcb)
        ld      hl,(fc_pos)
        ld      (iy+FC_SIZE),l
        ld      (iy+FC_SIZE+1),h
        ld      hl,(fc_pos+2)
        ld      (iy+FC_SIZE+2),l
        ld      (iy+FC_SIZE+3),h
        call    fc_rcnt
        xor     a
        ret

; _AUXIN (03h): A = 1Ah, the end. _AUXOUT (04h) and _LSTOUT (05h): the
; byte swallowed.
f_auxin:
        ld      a,1Ah
        ld      l,a
        ld      b,0
        ret
f_auxout:
        jp      fc_zero
