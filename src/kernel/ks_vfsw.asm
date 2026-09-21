; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The filesystem's write side, in the switched part: write on a file, the
; creation and truncation open performs, unlink, mkdir, rmdir and rename.
; Runs under the window and the storage gate like ks_vfs.asm, keeps its
; variables in ST_VFSW, and reaches a process's memory through um_in
; alone.
;
; What reaches the disk, and in what order, inside one syscall: the data
; sectors first — whole aligned ones straight from the process's page,
; the rest through a buffer and bwrite the moment they change — then the
; FAT, every copy, through ks_bflush, then the directory entry. A
; removal writes the entry first and frees the chain after. So a card
; pulled at any instant leaves at worst a cluster nobody owns, never an
; entry pointing at a free cluster, and a syscall that returns has left
; nothing dirty behind: every body below ends in ks_bflush, on its error
; paths too.

; ---------------------------------------------------------------------
; Common pieces

; wr_finish — after a body whose result is in CF/A (and HL): ks_bflush,
; then the body's result — its error first, else the flush's. Corrupts
; everything but HL on success.
wr_finish:
        push    af
        push    hl
        call    ks_bflush
        jr      c,.ferr
        pop     hl
        pop     af
        ret
.ferr:  ld      c,a
        pop     hl
        pop     af
        ret     c                       ; the body's error wins
        ld      a,c
        scf
        ret

; wr_stamp — VW_DATE and VW_TIME = now, from the RTC. Corrupts everything.
wr_stamp:
        k_call  API_RTC_READ
        ld      (SG+VW_DATE),hl
        ld      (SG+VW_TIME),de
        ret

; ent_addr — HL = a directory sector's buffer, A = an entry index 0-15:
; HL -> the entry. Corrupts AF, DE.
ent_addr:
        add     a,a
        add     a,a
        add     a,a
        add     a,a                     ; * 16: at most 240
        ld      e,a
        ld      d,0
        sla     e
        rl      d                       ; * 32, in sixteen bits
        add     hl,de
        ret

; buf_base — HL = an address inside a buffer: HL = the buffer. Corrupts AF.
buf_base:
        ld      a,h
        and     0FEh
        ld      h,a
        ld      l,0
        ret

; dir_put_entry — VR_ENT written over the entry at VR_DSEC/VR_DIDX of
; volume VR_VOL. CF with the errno. Corrupts everything.
dir_put_entry:
        ld      hl,(SG+VR_DSEC)
        ld      de,(SG+VR_DSEC+2)
        ld      a,(SG+VR_VOL)
        k_call  API_BGET
        ret     c
        push    hl
        ld      a,(SG+VR_DIDX)
        call    ent_addr
        ex      de,hl
        ld      hl,SG+VR_ENT
        ld      bc,FE_SIZEOF
        ldir
        pop     hl
        k_call  API_BWRITE
        ret

; dir_free_entry — the entry at VR_DSEC/VR_DIDX of volume VR_VOL marked
; deleted (FE_FREE), written. CF with the errno. Corrupts everything.
dir_free_entry:
        ld      hl,(SG+VR_DSEC)
        ld      de,(SG+VR_DSEC+2)
        ld      a,(SG+VR_VOL)
        k_call  API_BGET
        ret     c
        push    hl
        ld      a,(SG+VR_DIDX)
        call    ent_addr
        ld      (hl),FE_FREE
        pop     hl
        k_call  API_BWRITE
        ret

; dir_free_name — the entry at VR_DSEC/VR_DIDX of volume VR_VOL marked
; deleted, after the VR_LN parts of its chain before it, from VR_LSEC/
; VR_LIDX on, reached through the directory's (VV_VOL, VV_CLUS) scan;
; every sector is written as it is left, the entry's last. CF with the
; errno. Corrupts everything.
dir_free_name:
        ld      a,(SG+VR_LN)
        or      a
        jp      z,dir_free_entry
        ld      (SG+VW_FN),a
        call    dir_scan_start
        ret     c
.find:  call    dir_scan_next
        ret     c
        jr      z,.io                   ; the chain's sector is not there
        push    hl
        push    de
        ld      bc,(SG+VR_LSEC)
        or      a
        sbc     hl,bc
        jr      nz,.other
        ex      de,hl
        ld      bc,(SG+VR_LSEC+2)
        or      a
        sbc     hl,bc
.other: pop     de
        pop     hl
        jr      nz,.find
        ld      a,(SG+VR_LIDX)
.sector:
        ld      (SG+VW_EIDX),a
        ld      a,(SG+VR_VOL)
        k_call  API_BGET
        ret     c
.part:  push    hl
        ld      a,(SG+VW_EIDX)
        call    ent_addr
        ld      (hl),FE_FREE
        pop     hl
        ld      a,(SG+VW_FN)
        dec     a
        ld      (SG+VW_FN),a
        jr      z,.last
        ld      a,(SG+VW_EIDX)
        inc     a
        ld      (SG+VW_EIDX),a
        cp      16
        jr      c,.part
        k_call  API_BWRITE
        ret     c
        call    dir_scan_next
        ret     c
        jr      z,.io
        xor     a
        jr      .sector
.last:  k_call  API_BWRITE
        ret     c
        jp      dir_free_entry
.io:    ld      a,E_IO
        scf
        ret

; vfs_busy — VR_* = a file or directory: CF with E_BUSY when an open-file
; row points at it — any row when A = 0, a writer's (OFF_WR) when A = 1.
; Matched by first cluster, or, for an empty file, by the entry's sector
; and index. Corrupts everything.
vfs_busy:
        ld      (SG+VW_BMODE),a
        ld      iy,SG_OFT
        ld      b,OFT_N
.row:   ld      a,(iy+OF_VOL)
        cp      VOL_NONE
        jr      z,.next
        ld      a,(iy+OF_FLAGS)
        and     OFF_ROOT|OFF_MNT        ; no entry of their own
        jr      nz,.next
        ld      a,(iy+OF_VOL)
        ld      hl,SG+VR_VOL
        cp      (hl)
        jr      nz,.next
        ld      hl,(SG+VR_CLUS)
        ld      a,h
        or      l
        jr      z,.byent
        ld      a,(iy+OF_FIRST)
        cp      l
        jr      nz,.next
        ld      a,(iy+OF_FIRST+1)
        cp      h
        jr      nz,.next
        jr      .match
.byent: push    iy
        pop     hl
        ld      de,OF_DSEC
        add     hl,de
        ld      de,SG+VR_DSEC
        ld      c,5                     ; the sector and the index
.cmp:   ld      a,(de)
        cp      (hl)
        jr      nz,.next
        inc     hl
        inc     de
        dec     c
        jr      nz,.cmp
.match: ld      a,(SG+VW_BMODE)
        or      a
        jr      z,.busy
        bit     4,(iy+OF_FLAGS)         ; OFF_WR
        jr      z,.next
.busy:  ld      a,E_BUSY
        scf
        ret
.next:  ld      de,OFT_SIZE
        add     iy,de
        djnz    .row
        or      a
        ret

; zw_write — A = a volume, DE:HL = a sector: written as zeros. The first
; call of a syscall zeroes a buffer for its sector and writes it; every
; later one, while that buffer's header still names that sector, writes
; the same buffer straight to the new sector through bwrite_direct — one
; 512-byte fill per syscall instead of one per sector, 3.3 ms each. A
; syscall that uses this clears VW_ZB first: the buffer is trusted only
; within the syscall that zeroed it. CF with the errno. Corrupts
; everything.
zw_write:
        ld      (SG+VW_T),hl
        ld      (SG+VW_T+2),de
        ld      (SG+VW_T+4),a
        ld      hl,(SG+VW_ZB)
        ld      a,h
        or      l
        jr      z,.make
        ld      a,(SG+VW_ZBV)
        ld      hl,(SG+VW_ZBS)
        ld      de,(SG+VW_ZBS+2)
        call    bc_find                 ; still the buffer of that sector?
        jr      nz,.make
        call    bc_index
        ld      a,c
        add     a,a
        add     a,SLOT_BUF0
        ld      c,a                     ; c = its slot
        ld      a,(K_REC+KR_SEG64K+2)
        ld      b,a
        ld      hl,(SG+VW_T)
        ld      de,(SG+VW_T+2)
        ld      a,(SG+VW_T+4)
        k_call  API_BWRITE_DIRECT
        ret
.make:  ld      hl,(SG+VW_T)
        ld      de,(SG+VW_T+2)
        ld      a,(SG+VW_T+4)
        ld      (SG+VW_ZBV),a
        ld      (SG+VW_ZBS),hl
        ld      (SG+VW_ZBS+2),de
        k_call  API_BZERO
        ret     c
        ld      (SG+VW_ZB),hl
        k_call  API_BWRITE
        ret

; dir_zero_cluster — A = a volume, HL = a cluster: every sector of it
; written as zeros, the last first, so that the first is the most recently
; touched buffer when the caller wants it. CF with the errno. Corrupts
; everything.
dir_zero_cluster:
        ld      (SG+VW_ZVOL),a
        xor     a
        ld      (SG+VW_ZB),a            ; a fresh buffer of zeros
        ld      (SG+VW_ZB+1),a
        ld      a,(SG+VW_ZVOL)
        call    fat_sector
        ret     c
        ld      (SG+VW_ZSEC),hl
        ld      (SG+VW_ZSEC+2),de
        ld      a,(SG+VW_ZVOL)
        call    fat_mnt
        ld      a,(ix+M_SPC)
        ld      (SG+VW_ZN),a
        dec     a
        ld      hl,(SG+VW_ZSEC)
        ld      de,(SG+VW_ZSEC+2)
        call    add32_a
        ld      (SG+VW_ZSEC),hl
        ld      (SG+VW_ZSEC+2),de
.sector:
        ld      hl,(SG+VW_ZSEC)
        ld      de,(SG+VW_ZSEC+2)
        ld      a,(SG+VW_ZVOL)
        call    zw_write
        ret     c
        ld      hl,(SG+VW_ZSEC)
        ld      a,h
        or      l
        jr      nz,.nb
        ld      de,(SG+VW_ZSEC+2)
        dec     de
        ld      (SG+VW_ZSEC+2),de
.nb:    dec     hl
        ld      (SG+VW_ZSEC),hl
        ld      a,(SG+VW_ZN)
        dec     a
        ld      (SG+VW_ZN),a
        jr      nz,.sector
        or      a
        ret

; dir_new_entry — the directory (VV_VOL, VV_CLUS) and the new component,
; the lookup's last, prepared by lfn_prepare; A = the attribute, DE = the
; first cluster, VW_DATE/VW_TIME the stamp: a new entry, size 0, written
; with the parts its name needs; VR_* then describe it as a lookup would.
; CF with the errno; the table may be left dirty. Corrupts everything.
dir_new_entry:
        ld      (SG+VW_NATTR),a
        ld      (SG+VW_NCLUS),de
        ld      hl,SG+VR_ENT
        ld      b,FE_SIZEOF
.zero:  ld      (hl),0
        inc     hl
        djnz    .zero
        ld      a,(SG+VW_NATTR)
        ld      (SG+VR_ENT+FE_ATTR),a
        ld      hl,(SG+VW_TIME)
        ld      (SG+VR_ENT+FE_CTIME),hl
        ld      (SG+VR_ENT+FE_MTIME),hl
        ld      hl,(SG+VW_DATE)
        ld      (SG+VR_ENT+FE_CDATE),hl
        ld      (SG+VR_ENT+FE_ADATE),hl
        ld      (SG+VR_ENT+FE_MDATE),hl
        ld      hl,(SG+VW_NCLUS)
        ld      (SG+VR_ENT+FE_CLUS),hl
        ; falls into dir_new_name

; dir_new_name — the directory (VV_VOL, VV_CLUS); VR_ENT from FE_ATTR on
; prepared — attribute, times, cluster, size; the new component at (VV_P)
; for VL_WANT bytes, with what lfn_prepare and the lookup's scan found
; for it: VW_NLFN parts and VW_ALIAS, or VV_NAME and VV_NT for a short
; name alone, and the run at VW_RSEC/VW_RIDX when VW_RFOUND. The parts
; and the short entry are written there — the run continuing into a
; cluster added at the chain's end when it runs out, or starting in one
; when none was found; a full root is E_NOSPC. Every sector is written
; as it is left, the short entry's last. VR_* then describe the short
; entry as a lookup would, its chain included. CF with the errno.
; Corrupts everything.
dir_new_name:
        ld      a,(SG+VW_NLFN)
        or      a
        jr      z,.shortn
        call    lfn_digit
        ret     c
        ld      hl,SG+VW_ALIAS
        ld      de,SG+VR_ENT+FE_NAME
        ld      bc,11
        ldir
        xor     a
        ld      (SG+VR_ENT+FE_NT),a
        ld      hl,SG+VR_ENT+FE_NAME
        call    lfn_sum
        ld      (SG+VL_SUM),a           ; what every part carries
        jr      .place
.shortn:
        ld      hl,SG+VV_NAME
        ld      de,SG+VR_ENT+FE_NAME
        ld      bc,11
        ldir
        ld      a,(SG+VV_NT)
        ld      (SG+VR_ENT+FE_NT),a
.place: ld      a,(SG+VW_RFOUND)
        or      a
        jr      nz,.known
        ld      hl,0FFFFh               ; no run: a sector no scan reaches,
        ld      (SG+VW_RSEC),hl         ; so the scan runs out and grows
        ld      (SG+VW_RSEC+2),hl
.known: call    dir_scan_start
        ret     c
.find:  call    dir_scan_next
        ret     c
        jr      z,.grow
        push    hl
        push    de
        ld      bc,(SG+VW_RSEC)
        or      a
        sbc     hl,bc
        jr      nz,.other
        ex      de,hl
        ld      bc,(SG+VW_RSEC+2)
        or      a
        sbc     hl,bc
.other: pop     de
        pop     hl
        jr      nz,.find
        ld      a,(SG+VW_RIDX)
        jr      .at
.grow:  call    dir_grow                ; the next sector is the new cluster's
        ret     c
        call    dir_scan_next
        ret     c
        ld      (SG+VW_RSEC),hl         ; the run starts there
        ld      (SG+VW_RSEC+2),de
        xor     a
        ld      (SG+VW_RIDX),a
.at:    ld      (SG+VW_EIDX),a
        ld      (SG+VW_ESEC),hl
        ld      (SG+VW_ESEC+2),de
        ld      a,(SG+VV_VOL)
        k_call  API_BGET
        ret     c
        ld      a,(SG+VW_NLFN)
        ld      (SG+VW_PN),a            ; the part to write next; 0 the entry
.slot:  push    hl
        ld      a,(SG+VW_PN)
        or      a
        jr      z,.entry
        call    lfn_part                ; (corrupts everything: the slot's
        pop     hl                      ; address comes after it)
        push    hl
        ld      a,(SG+VW_EIDX)
        call    ent_addr
        ex      de,hl                   ; de -> the slot
        ld      hl,SG+VW_PENT
        ld      bc,FE_SIZEOF
        ldir
        ld      hl,SG+VW_PN
        dec     (hl)
        pop     hl
        ld      a,(SG+VW_EIDX)          ; the next slot: in this sector, or
        inc     a                       ; in the next once this is written
        ld      (SG+VW_EIDX),a
        cp      16
        jr      c,.slot
        k_call  API_BWRITE
        ret     c
        call    dir_scan_next
        ret     c
        jr      nz,.next
        call    dir_grow
        ret     c
        call    dir_scan_next
        ret     c
.next:  xor     a
        ld      (SG+VW_EIDX),a
        ld      (SG+VW_ESEC),hl
        ld      (SG+VW_ESEC+2),de
        ld      a,(SG+VV_VOL)
        k_call  API_BGET
        ret     c
        jr      .slot
.entry: ld      a,(SG+VW_EIDX)
        call    ent_addr
        ex      de,hl                   ; de -> the slot
        ld      hl,SG+VR_ENT
        ld      bc,FE_SIZEOF
        ldir
        pop     hl
        k_call  API_BWRITE
        ret     c
        ; VR_*: the new entry, as a lookup would leave it.
        xor     a
        ld      (SG+VR_KIND),a          ; VK_ENTRY
        ld      a,(SG+VV_VOL)
        ld      (SG+VR_VOL),a
        ld      hl,(SG+VR_ENT+FE_CLUS)
        ld      (SG+VR_CLUS),hl
        ld      a,(SG+VR_ENT+FE_ATTR)
        ld      (SG+VR_ATTR),a
        ld      hl,SG+VR_ENT+FE_SIZE
        ld      de,SG+VR_SIZE
        ld      bc,4
        ldir
        ld      hl,SG+VR_ENT+FE_MTIME
        ld      de,SG+VR_MTIME
        ld      bc,4
        ldir
        ld      hl,SG+VW_ESEC
        ld      de,SG+VR_DSEC
        ld      bc,5
        ldir
        ld      a,(SG+VW_NLFN)
        ld      (SG+VR_LN),a
        ld      hl,SG+VW_RSEC
        ld      de,SG+VR_LSEC
        ld      bc,5
        ldir
        ld      a,1
        ld      (SG+VV_HASENT),a
        or      a
        ret

; dir_grow — the directory (VV_VOL, VV_CLUS), scanned to its end: a
; cluster allocated, zeroed and linked after VV_SCLUS, its last, and the
; scan's cursor set to it, so dir_scan_next yields its first sector. A
; root, a fixed area, is E_NOSPC. CF with the errno. Corrupts everything.
dir_grow:
        ld      hl,(SG+VV_CLUS)
        ld      a,h
        or      l
        jr      z,.nospc
        ld      hl,(SG+VV_SCLUS)
        ld      (SG+VW_TAIL),hl
        ld      a,(SG+VV_VOL)
        call    fat_alloc
        ret     c
        ld      (SG+VW_NEWC),hl
        ld      a,(SG+VV_VOL)
        call    dir_zero_cluster
        ret     c
        ld      hl,(SG+VW_TAIL)
        ld      de,(SG+VW_NEWC)
        ld      a,(SG+VV_VOL)
        call    fat_set
        ret     c
        ld      hl,(SG+VW_NEWC)
        ld      (SG+VV_SCLUS),hl
        ld      a,(SG+VV_VOL)
        call    fat_sector
        ret     c
        ld      (SG+VV_SSEC),hl
        ld      (SG+VV_SSEC+2),de
        ld      l,(ix+M_SPC)
        ld      h,0
        ld      (SG+VV_SN),hl
        or      a
        ret
.nospc: ld      a,E_NOSPC
        scf
        ret

; wr_truncate — VR_* = a file's entry: rewritten with size 0, no cluster
; and the time now (first), then its chain freed and the table flushed.
; VR_SIZE and VR_CLUS read 0 afterwards. CF with the errno. Corrupts
; everything.
wr_truncate:
        call    wr_stamp
        ld      hl,0
        ld      (SG+VR_ENT+FE_CLUS),hl
        ld      (SG+VR_ENT+FE_SIZE),hl
        ld      (SG+VR_ENT+FE_SIZE+2),hl
        ld      hl,(SG+VW_TIME)
        ld      (SG+VR_ENT+FE_MTIME),hl
        ld      hl,(SG+VW_DATE)
        ld      (SG+VR_ENT+FE_MDATE),hl
        ld      a,(SG+VR_ENT+FE_ATTR)
        or      DA_ARCHIVE
        ld      (SG+VR_ENT+FE_ATTR),a
        call    dir_put_entry
        ret     c
        ld      hl,(SG+VR_CLUS)
        ld      de,0
        ld      (SG+VR_CLUS),de
        ld      (SG+VR_SIZE),de
        ld      (SG+VR_SIZE+2),de
        ld      a,h
        or      l
        ret     z                       ; nothing to free
        ld      a,(SG+VR_VOL)
        call    fat_free_chain
        jp      wr_finish

; ---------------------------------------------------------------------
; write

; wr_cur_lt_p — CF when OF_POS of the row at IY is below VW_P32, where the
; caller's bytes begin. Corrupts AF, DE, HL.
wr_cur_lt_p:
        ld      l,(iy+OF_POS)
        ld      h,(iy+OF_POS+1)
        ld      de,(SG+VW_P32)
        or      a
        sbc     hl,de
        ld      l,(iy+OF_POS+2)
        ld      h,(iy+OF_POS+3)
        ld      de,(SG+VW_P32+2)
        sbc     hl,de
        ret

; wr_grow — OF_SIZE of the row at IY = max(OF_SIZE, OF_POS). Corrupts AF,
; DE, HL.
wr_grow:
        ld      l,(iy+OF_SIZE)
        ld      h,(iy+OF_SIZE+1)
        ld      e,(iy+OF_POS)
        ld      d,(iy+OF_POS+1)
        or      a
        sbc     hl,de
        ld      l,(iy+OF_SIZE+2)
        ld      h,(iy+OF_SIZE+3)
        ld      e,(iy+OF_POS+2)
        ld      d,(iy+OF_POS+3)
        sbc     hl,de
        ret     nc                      ; size >= pos
        ld      a,(iy+OF_POS)
        ld      (iy+OF_SIZE),a
        ld      a,(iy+OF_POS+1)
        ld      (iy+OF_SIZE+1),a
        ld      a,(iy+OF_POS+2)
        ld      (iy+OF_SIZE+2),a
        ld      a,(iy+OF_POS+3)
        ld      (iy+OF_SIZE+3),a
        ret

; wr_cursor — IY -> a row with a first cluster: OF_CLUS = the cluster
; holding OF_POS, walking from OF_FIRST and allocating from the tail where
; the chain ends first. CF with the errno. Corrupts everything but IY.
wr_cursor:
        ld      a,(iy+OF_VOL)
        call    fat_mnt
        ld      a,(ix+M_SPCSH)
        add     a,9
        ld      b,a
        ld      l,(iy+OF_POS)
        ld      h,(iy+OF_POS+1)
        ld      e,(iy+OF_POS+2)
        ld      d,(iy+OF_POS+3)
.shift: srl     d
        rr      e
        rr      h
        rr      l
        djnz    .shift
        ld      b,h
        ld      c,l                     ; bc = the cluster index
        ld      l,(iy+OF_FIRST)
        ld      h,(iy+OF_FIRST+1)
.step:  ld      a,b
        or      c
        jr      z,.done
        push    bc
        push    hl
        ld      a,(iy+OF_VOL)
        call    fat_next
        ld      iy,(SG+VV_ROW)
        jr      c,.err
        jr      z,.alloc
        pop     de                      ; the link followed
        pop     bc
        dec     bc
        jr      .step
.alloc: pop     hl                      ; the tail
        push    hl
        ld      a,(iy+OF_VOL)
        call    fat_alloc
        ld      iy,(SG+VV_ROW)
        jr      c,.err
        ex      de,hl                   ; de = the new cluster
        pop     hl                      ; the tail
        push    de
        ld      a,(iy+OF_VOL)
        call    fat_set
        ld      iy,(SG+VV_ROW)
        pop     hl                      ; the new cluster
        jr      c,.err1
        ld      (iy+OF_TAIL),l
        ld      (iy+OF_TAIL+1),h
        pop     bc
        dec     bc
        jr      .step
.done:  ld      (iy+OF_CLUS),l
        ld      (iy+OF_CLUS+1),h
        or      a
        ret
.err:   pop     hl
.err1:  pop     bc
        scf
        ret

; wr_update_entry — IY -> a row: its directory entry's size, first cluster
; and modification time (VW_TIME/VW_DATE) from the row, the archive bit
; set; written. CF with the errno. Corrupts everything but IY.
wr_update_entry:
        ld      l,(iy+OF_DSEC)
        ld      h,(iy+OF_DSEC+1)
        ld      e,(iy+OF_DSEC+2)
        ld      d,(iy+OF_DSEC+3)
        ld      a,(iy+OF_VOL)
        k_call  API_BGET
        ld      iy,(SG+VV_ROW)
        ret     c
        push    hl
        ld      a,(iy+OF_DIDX)
        call    ent_addr
        push    hl
        pop     ix                      ; ix -> the entry
        ld      a,(iy+OF_SIZE)
        ld      (ix+FE_SIZE),a
        ld      a,(iy+OF_SIZE+1)
        ld      (ix+FE_SIZE+1),a
        ld      a,(iy+OF_SIZE+2)
        ld      (ix+FE_SIZE+2),a
        ld      a,(iy+OF_SIZE+3)
        ld      (ix+FE_SIZE+3),a
        ld      a,(iy+OF_FIRST)
        ld      (ix+FE_CLUS),a
        ld      a,(iy+OF_FIRST+1)
        ld      (ix+FE_CLUS+1),a
        ld      hl,(SG+VW_TIME)
        ld      (ix+FE_MTIME),l
        ld      (ix+FE_MTIME+1),h
        ld      hl,(SG+VW_DATE)
        ld      (ix+FE_MDATE),l
        ld      (ix+FE_MDATE+1),h
        ld      a,(ix+FE_ATTR)
        or      DA_ARCHIVE
        ld      (ix+FE_ATTR),a
        pop     hl
        k_call  API_BWRITE
        ld      iy,(SG+VV_ROW)
        ret

; ks_write — the switched half of SYS_WRITE: A = the open-file row's index
; (the resident resolved the descriptor), HL = buffer, BC = length. Out:
; HL = bytes written; E_ISDIR on a directory, E_BADF on a row not open for
; writing; an error after some bytes were written returns them and is owed
; to the next call (OFF_ERR, OF_ERRNO), E_NOSPC included.
;
; One pass from the lower of the size and the position to the end of the
; caller's bytes: what lies below the position is a hole and is written as
; zeros, what lies at or past it is the caller's. Per sector: a whole
; sector of the caller's bytes from a 256-byte boundary of page 0-2 goes
; straight from the page; otherwise the sector's buffer — read when any
; byte of it lies below the old size, a buffer of zeros when none does —
; takes the zeros and the bytes and is written at once. A cluster is
; allocated from the chain's tail as the pass reaches it. Then the table
; is flushed and the directory entry rewritten.
ks_write:
        push    hl
        push    bc
        call    vfs_begin
        call    oft_row
        pop     bc
        pop     hl
        ld      (SG+VV_ROW),iy          ; reloaded after every call that may
                                        ; reach the driver
        bit     0,(iy+OF_FLAGS)         ; OFF_DIR
        jp      nz,.isdir
        bit     4,(iy+OF_FLAGS)         ; OFF_WR
        jp      z,.badf
        bit     3,(iy+OF_FLAGS)         ; OFF_ERR: the error owed
        jr      z,.fresh
        res     3,(iy+OF_FLAGS)
        ld      a,(iy+OF_ERRNO)
        scf
        ret
.fresh: ld      a,b
        or      c
        jp      z,.zero
        bit     5,(iy+OF_FLAGS)         ; OFF_APPEND: at the end
        jr      z,.pass
        ld      a,(iy+OF_SIZE)
        ld      (iy+OF_POS),a
        ld      a,(iy+OF_SIZE+1)
        ld      (iy+OF_POS+1),a
        ld      a,(iy+OF_SIZE+2)
        ld      (iy+OF_POS+2),a
        ld      a,(iy+OF_SIZE+3)
        ld      (iy+OF_POS+3),a
        ld      (iy+OF_CLUS),low OF_CLUS_NONE
        ld      (iy+OF_CLUS+1),high OF_CLUS_NONE
.pass:  ; The pass (ks_ftrunc enters here with no bytes, to grow a file).
        ld      (SG+VV_RBUF),hl
        ld      (SG+VV_RLEFT),bc
        ld      hl,0
        ld      (SG+VV_RDONE),hl
        ld      (SG+VW_ZB),hl           ; no buffer of zeros yet
        xor     a
        ld      (SG+VW_ERR),a
        push    iy
        pop     hl
        ld      de,OF_SIZE
        add     hl,de
        ld      de,SG+VW_S32            ; the size before
        ld      bc,4
        ldir
        push    iy
        pop     hl
        ld      de,OF_POS
        add     hl,de
        ld      de,SG+VW_P32            ; where the caller's bytes go
        ld      bc,4
        ldir
        call    wr_stamp
        ld      iy,(SG+VV_ROW)
        ; The pass begins at the size when that is below the position: the
        ; hole is laid down first.
        ld      hl,(SG+VW_S32)
        ld      de,(SG+VW_P32)
        or      a
        sbc     hl,de
        ld      hl,(SG+VW_S32+2)
        ld      de,(SG+VW_P32+2)
        sbc     hl,de
        jr      nc,.first               ; size >= position
        ld      a,(SG+VW_S32)
        ld      (iy+OF_POS),a
        ld      a,(SG+VW_S32+1)
        ld      (iy+OF_POS+1),a
        ld      a,(SG+VW_S32+2)
        ld      (iy+OF_POS+2),a
        ld      a,(SG+VW_S32+3)
        ld      (iy+OF_POS+3),a
        ld      (iy+OF_CLUS),low OF_CLUS_NONE
        ld      (iy+OF_CLUS+1),high OF_CLUS_NONE
.first: ; The first cluster, when the file has none yet: from the hint.
        ld      a,(iy+OF_FIRST)
        ld      c,a
        ld      a,(iy+OF_FIRST+1)
        or      c
        jr      nz,.cursor
        ld      a,(iy+OF_VOL)
        call    fat_mnt
        ld      l,(ix+M_HINT)
        ld      h,(ix+M_HINT+1)
        ld      a,(iy+OF_VOL)
        call    fat_alloc
        ld      iy,(SG+VV_ROW)
        jp      c,.err
        ld      (iy+OF_FIRST),l
        ld      (iy+OF_FIRST+1),h
        ld      (iy+OF_CLUS),l
        ld      (iy+OF_CLUS+1),h
        ld      (iy+OF_TAIL),l
        ld      (iy+OF_TAIL+1),h
        ld      a,(iy+OF_VOL)
        call    fat_mnt
        ld      (ix+M_HINT),l
        ld      (ix+M_HINT+1),h
.cursor:
        ; The cursor: rebuilt when lseek or a read left none — from the
        ; chain's known end when the position is the size, which is where
        ; a sequential writer always is, else walking from the first
        ; cluster.
        ld      a,(iy+OF_CLUS)
        ld      c,a
        ld      a,(iy+OF_CLUS+1)
        ld      b,a
        or      c
        jr      z,.rebuild              ; OF_CLUS_NONE
        ld      a,b                     ; both bytes FFh, not the low one
        and     c
        inc     a
        jp      nz,.havecl              ; not OF_CLUS_END
.rebuild:
        ld      a,(iy+OF_TAIL)
        ld      c,a
        ld      a,(iy+OF_TAIL+1)
        or      c
        jp      z,.walk                 ; the end is not known
        push    iy
        pop     hl
        ld      de,OF_POS
        add     hl,de
        push    iy
        pop     de
        push    hl
        ld      hl,OF_SIZE
        add     hl,de
        pop     de                      ; hl -> the size, de -> the position
        ld      b,4
.atend: ld      a,(de)
        cp      (hl)
        jr      nz,.walk                ; not at the end
        inc     hl
        inc     de
        djnz    .atend
        ; At the end. Inside the tail's last cluster the tail is the
        ; cursor; on a cluster boundary the next cluster does not exist
        ; and is allocated from the tail.
        ld      a,(iy+OF_VOL)
        call    fat_mnt
        ld      a,(ix+M_SPCSH)
        add     a,9
        ld      b,a
        ld      l,(iy+OF_POS)
        ld      h,(iy+OF_POS+1)
        ld      c,0                     ; the bits shifted out: the
.mask:  srl     h                       ; position within its cluster
        rr      l
        jr      nc,.bit
        inc     c
.bit:   djnz    .mask
        ld      a,c
        or      a
        jr      z,.newtail              ; on a cluster boundary
        ld      l,(iy+OF_TAIL)
        ld      h,(iy+OF_TAIL+1)
        ld      (iy+OF_CLUS),l
        ld      (iy+OF_CLUS+1),h
        jr      .havecl
.newtail:
        ld      l,(iy+OF_TAIL)
        ld      h,(iy+OF_TAIL+1)
        ld      a,(iy+OF_VOL)
        call    fat_alloc
        ld      iy,(SG+VV_ROW)
        jp      c,.err
        ex      de,hl                   ; de = the new cluster
        ld      l,(iy+OF_TAIL)
        ld      h,(iy+OF_TAIL+1)
        push    de
        ld      a,(iy+OF_VOL)
        call    fat_set
        ld      iy,(SG+VV_ROW)
        pop     hl
        jp      c,.err
        ld      (iy+OF_CLUS),l
        ld      (iy+OF_CLUS+1),h
        ld      (iy+OF_TAIL),l
        ld      (iy+OF_TAIL+1),h
        jr      .havecl
.walk:  call    wr_cursor
        jp      c,.err
.havecl:
        ; The running sector, as read keeps it.
        ld      a,(iy+OF_VOL)
        call    fat_mnt
        ld      a,(ix+M_SPC)
        ld      (SG+VV_RSPC),a
        ld      a,(iy+OF_POS+1)
        ld      c,a
        ld      a,(iy+OF_POS+2)
        rrca
        rr      c                       ; c = (pos >> 9) & FFh
        ld      a,(ix+M_SPC)
        dec     a
        and     c
        ld      (SG+VV_RSIDX),a
        push    af
        ld      l,(iy+OF_CLUS)
        ld      h,(iy+OF_CLUS+1)
        ld      a,(iy+OF_VOL)
        call    fat_sector
        jp      c,.poperr
        pop     af
        call    add32_a
        ld      (SG+VV_RSEC),hl
        ld      (SG+VV_RSEC+2),de
.loop:  ; More? Bytes left, or the position still below where they go.
        ld      hl,(SG+VV_RLEFT)
        ld      a,h
        or      l
        jr      nz,.more
        call    wr_cur_lt_p
        jp      nc,.done
.more:  ld      a,(iy+OF_POS)
        ld      l,a
        ld      a,(iy+OF_POS+1)
        and     1
        ld      h,a
        ld      (SG+VW_OFF),hl          ; the offset in the sector
        ld      hl,0
        ld      (SG+VW_HOLE),hl
        call    wr_cur_lt_p
        jr      nc,.nohole
        ; hole = min(where the bytes go - position, 512 - offset)
        ld      hl,(SG+VW_P32)
        ld      e,(iy+OF_POS)
        ld      d,(iy+OF_POS+1)
        or      a
        sbc     hl,de
        push    hl
        ld      hl,(SG+VW_P32+2)
        ld      e,(iy+OF_POS+2)
        ld      d,(iy+OF_POS+3)
        sbc     hl,de
        ld      a,h
        or      l
        pop     hl                      ; hl = the low word of the gap
        jr      nz,.room                ; a gap above 64K: the room
        ld      de,(SG+VW_OFF)
        push    hl                      ; the gap
        ld      hl,512
        or      a
        sbc     hl,de                   ; hl = the room to the sector's end
        pop     de                      ; de = the gap
        push    hl
        or      a
        sbc     hl,de                   ; room - gap
        pop     hl
        jr      c,.holeok               ; room < gap: the room
        ex      de,hl                   ; else the gap
        jr      .holeok
.room:  ld      hl,512
        ld      de,(SG+VW_OFF)
        or      a
        sbc     hl,de
.holeok:
        ld      (SG+VW_HOLE),hl
.nohole:
        ; data = min(bytes left, 512 - offset - hole)
        ld      hl,(SG+VW_OFF)
        ld      de,(SG+VW_HOLE)
        add     hl,de
        ld      (SG+VW_OFF2),hl
        ex      de,hl
        ld      hl,512
        or      a
        sbc     hl,de                   ; the room after the hole
        ld      de,(SG+VV_RLEFT)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      c,.dataok               ; room < left: the room
        ex      de,hl
.dataok:
        ld      (SG+VW_DATA),hl
        ; Direct: no hole, at the sector's start, 512 left, the buffer on a
        ; 256-byte boundary of page 0-2, the sector inside the page.
        ld      hl,(SG+VW_HOLE)
        ld      a,h
        or      l
        jr      nz,.rmw
        ld      hl,(SG+VW_OFF)
        ld      a,h
        or      l
        jr      nz,.rmw
        ld      bc,(SG+VV_RLEFT)
        ld      a,b
        cp      2
        jr      c,.rmw
        ld      bc,(SG+VV_RBUF)
        ld      a,c
        or      a
        jr      nz,.rmw
        ld      a,b
        cp      0C0h
        jr      nc,.rmw
        and     3Fh
        cp      3Fh
        jr      z,.rmw
        ld      c,a                     ; the slot
        ld      a,b
        rlca
        rlca
        and     3
        push    bc
        call    um_seg
        pop     bc
        ld      b,a                     ; the segment
        ld      hl,(SG+VV_RSEC)
        ld      de,(SG+VV_RSEC+2)
        ld      a,(iy+OF_VOL)
        k_call  API_BWRITE_DIRECT
        ld      iy,(SG+VV_ROW)
        jp      c,.err
        jp      .advance                ; VW_DATA is 512
.rmw:   ; The sector's buffer: read when any byte of it lies below the old
        ; size, zeros when none does.
        ld      a,(iy+OF_POS+1)
        and     0FEh
        ld      h,a
        ld      l,0                     ; hl = the sector's start, low word
        ld      de,(SG+VW_S32)
        or      a
        sbc     hl,de
        ld      l,(iy+OF_POS+2)
        ld      h,(iy+OF_POS+3)
        ld      de,(SG+VW_S32+2)
        sbc     hl,de                   ; CF: start < size
        ld      hl,(SG+VV_RSEC)
        ld      de,(SG+VV_RSEC+2)
        ld      a,(iy+OF_VOL)
        jr      c,.read
        ; Nothing of the sector is kept. All zeros — a hole's whole
        ; sector — goes through the shared buffer of zeros.
        ld      bc,(SG+VW_DATA)
        ld      a,b
        or      c
        jr      nz,.zeros
        ld      a,(iy+OF_VOL)
        call    zw_write
        ld      iy,(SG+VV_ROW)
        jp      c,.err
        jp      .advance
.zeros: ld      a,(iy+OF_VOL)
        k_call  API_BZERO
        jr      .have
.read:  k_call  API_BGET
.have:  ld      iy,(SG+VV_ROW)
        jp      c,.err
        ld      (SG+VW_BUF),hl
        ld      bc,(SG+VW_HOLE)
        ld      a,b
        or      c
        jr      z,.nozero
        ld      de,(SG+VW_OFF)
        add     hl,de
        ld      (hl),0
        dec     bc
        ld      a,b
        or      c
        jr      z,.nozero
        ld      d,h
        ld      e,l
        inc     de
        ldir
.nozero:
        ld      bc,(SG+VW_DATA)
        ld      a,b
        or      c
        jr      z,.write
        ld      hl,(SG+VW_BUF)
        ld      de,(SG+VW_OFF2)
        add     hl,de
        ld      de,-4000h
        add     hl,de                   ; as a storage offset
        ex      de,hl
        ld      hl,(SG+VV_RBUF)
        call    um_in
        ld      iy,(SG+VV_ROW)
.write: ld      hl,(SG+VW_BUF)
        k_call  API_BWRITE
        ld      iy,(SG+VV_ROW)
        jp      c,.err
.advance:
        ; The buffer and the counts by the caller's bytes, the position by
        ; the zeros and the bytes; the size follows the position.
        ld      bc,(SG+VW_DATA)
        ld      hl,(SG+VV_RBUF)
        add     hl,bc
        ld      (SG+VV_RBUF),hl
        ld      hl,(SG+VV_RDONE)
        add     hl,bc
        ld      (SG+VV_RDONE),hl
        ld      hl,(SG+VV_RLEFT)
        or      a
        sbc     hl,bc
        ld      (SG+VV_RLEFT),hl
        ld      hl,(SG+VW_HOLE)
        add     hl,bc
        ld      b,h
        ld      c,l
        ld      l,(iy+OF_POS)
        ld      h,(iy+OF_POS+1)
        add     hl,bc
        ld      (iy+OF_POS),l
        ld      (iy+OF_POS+1),h
        jr      nc,.nocarry
        inc     (iy+OF_POS+2)
        jr      nz,.nocarry
        inc     (iy+OF_POS+3)
.nocarry:
        call    wr_grow
        ld      a,(iy+OF_POS)
        or      a
        jp      nz,.loop                ; inside the sector still
        ld      a,(iy+OF_POS+1)
        and     1
        jp      nz,.loop
        ; A sector completed: the next, and the next cluster after the
        ; cluster's last — allocated when the chain ends here.
        ld      hl,(SG+VV_RSEC)
        inc     hl
        ld      (SG+VV_RSEC),hl
        ld      a,h
        or      l
        jr      nz,.samecl
        ld      hl,(SG+VV_RSEC+2)
        inc     hl
        ld      (SG+VV_RSEC+2),hl
.samecl:
        ld      a,(SG+VV_RSIDX)
        inc     a
        ld      (SG+VV_RSIDX),a
        ld      hl,SG+VV_RSPC
        cp      (hl)
        jp      c,.loop
        xor     a
        ld      (SG+VV_RSIDX),a
        ld      l,(iy+OF_CLUS)
        ld      h,(iy+OF_CLUS+1)
        ld      a,(iy+OF_VOL)
        call    fat_next
        ld      iy,(SG+VV_ROW)
        jp      c,.err
        jr      nz,.setclus
        ; The chain ends here. Nothing more to write: the cursor says so.
        ld      hl,(SG+VV_RLEFT)
        ld      a,h
        or      l
        jr      nz,.alloc
        call    wr_cur_lt_p
        jr      c,.alloc
        ld      hl,OF_CLUS_END
        ld      (iy+OF_CLUS),l
        ld      (iy+OF_CLUS+1),h
        jp      .done
.alloc: ld      l,(iy+OF_CLUS)
        ld      h,(iy+OF_CLUS+1)
        ld      a,(iy+OF_VOL)
        call    fat_alloc
        ld      iy,(SG+VV_ROW)
        jp      c,.err
        ex      de,hl                   ; de = the new cluster
        ld      l,(iy+OF_CLUS)
        ld      h,(iy+OF_CLUS+1)
        push    de
        ld      a,(iy+OF_VOL)
        call    fat_set
        ld      iy,(SG+VV_ROW)
        pop     hl
        jp      c,.err
        ld      (iy+OF_TAIL),l
        ld      (iy+OF_TAIL+1),h
.setclus:
        ld      (iy+OF_CLUS),l
        ld      (iy+OF_CLUS+1),h
        ld      a,(iy+OF_VOL)
        call    fat_sector
        ld      iy,(SG+VV_ROW)
        jp      c,.err
        ld      (SG+VV_RSEC),hl
        ld      (SG+VV_RSEC+2),de
        jp      .loop
.poperr:
        pop     de
.err:   ld      (SG+VW_ERR),a
        ld      (iy+OF_CLUS),low OF_CLUS_NONE ; the cursor is for where the
        ld      (iy+OF_CLUS+1),high OF_CLUS_NONE ; pass stopped, not the position
.done:  ; The position: where the caller's bytes go, plus what was written.
        ld      hl,(SG+VW_P32)
        ld      bc,(SG+VV_RDONE)
        add     hl,bc
        ld      (iy+OF_POS),l
        ld      (iy+OF_POS+1),h
        ld      hl,(SG+VW_P32+2)
        jr      nc,.nc2
        inc     hl
.nc2:   ld      (iy+OF_POS+2),l
        ld      (iy+OF_POS+3),h
        ; The table, every copy.
        call    ks_bflush
        ld      iy,(SG+VV_ROW)
        call    c,.first_err
        ; The entry, when anything changed: bytes written, or the size.
        ld      hl,(SG+VV_RDONE)
        ld      a,h
        or      l
        jr      nz,.entry
        push    iy
        pop     hl
        ld      de,OF_SIZE
        add     hl,de
        ld      de,SG+VW_S32
        ld      b,4
.same:  ld      a,(de)
        cp      (hl)
        jr      nz,.entry
        inc     hl
        inc     de
        djnz    .same
        jr      .result
.entry: call    wr_update_entry
        call    c,.first_err
.result:
        ld      a,(SG+VW_ERR)
        or      a
        jr      z,.ok
        ld      hl,(SG+VV_RDONE)
        ld      c,a
        ld      a,h
        or      l
        ld      a,c
        jr      z,.now
        ld      (iy+OF_ERRNO),a         ; owed to the next call
        set     3,(iy+OF_FLAGS)         ; OFF_ERR
        or      a
        ret                             ; hl = the bytes written
.now:   scf
        ret
.ok:    ld      hl,(SG+VV_RDONE)
        or      a
        ret
.zero:  ld      hl,0
        or      a
        ret
; .first_err — A = an errno: kept when none is kept yet.
.first_err:
        ld      c,a
        ld      a,(SG+VW_ERR)
        or      a
        ret     nz
        ld      a,c
        ld      (SG+VW_ERR),a
        ret
.isdir: ld      a,E_ISDIR
        scf
        ret
.badf:  ld      a,E_BADF
        scf
        ret

; ---------------------------------------------------------------------
; unlink, mkdir, rmdir, rename

; ks_chmod — SYS_CHMOD: HL = a path, A = the attributes to set — any of
; DA_RDONLY, DA_HIDDEN, DA_SYSTEM, DA_ARCHIVE; another bit is E_INVAL.
; The entry's attribute byte becomes those bits with DA_DIR as it was;
; the timestamp is not touched. A volume's root and /mnt have no entry:
; E_ACCES. The only writer of the attribute byte after creation, and the
; only way to clear a read-only bit from m6.
ks_chmod:
        ld      (SG+VW_NATTR),a
        and     ~(DA_RDONLY|DA_HIDDEN|DA_SYSTEM|DA_ARCHIVE) & 0FFh
        jr      nz,.inval
        call    vfs_getpath
        ret     c
        call    vfs_lookup
        ret     c
        ld      a,(SG+VR_KIND)
        or      a                       ; VK_ENTRY
        jr      nz,.acces
        ld      a,(SG+VR_ENT+FE_ATTR)
        and     DA_DIR
        ld      hl,SG+VW_NATTR
        or      (hl)
        ld      (SG+VR_ENT+FE_ATTR),a
        call    dir_put_entry
        jp      wr_finish
.inval: ld      a,E_INVAL
        scf
        ret
.acces: ld      a,E_ACCES
        scf
        ret

; ks_utime — SYS_UTIME: HL = path, DE = a FAT date, BC = a FAT time: the
; entry's modification stamp set to them, as given. E_ACCES for what has
; no entry — a root, /mnt.
ks_utime:
        ld      (SG+VW_UDATE),de
        ld      (SG+VW_UTIME),bc
        call    vfs_getpath
        ret     c
        call    vfs_lookup
        ret     c
        ld      a,(SG+VR_KIND)
        or      a                       ; VK_ENTRY
        jr      nz,.acces
        ld      hl,(SG+VW_UTIME)
        ld      (SG+VR_ENT+FE_MTIME),hl
        ld      hl,(SG+VW_UDATE)
        ld      (SG+VR_ENT+FE_MDATE),hl
        call    dir_put_entry
        jp      wr_finish
.acces: ld      a,E_ACCES
        scf
        ret

; ks_ftrunc — SYS_FTRUNC: A = fd, DE:HL = a size: the file cut there — the
; chain cut after the cluster holding the new last byte, freed whole for
; a size of 0 — or grown to there through the write pass with no bytes,
; which lays the zeros and allocates as it goes; the entry rewritten with
; the size and the time now, the table flushed. The position stays where
; it was; the cursor is rebuilt by the next read or write. E_BADF
; for a descriptor not open for writing, E_ISDIR for a directory.
ks_ftrunc:
        ld      (SG+VW_P32),hl          ; the new size
        ld      (SG+VW_P32+2),de
        call    vfs_begin
        call    fd_row
        ret     c
        ld      (SG+VV_ROW),iy
        bit     0,(iy+OF_FLAGS)         ; OFF_DIR
        jp      nz,.isdir
        bit     4,(iy+OF_FLAGS)         ; OFF_WR
        jp      z,.badf
        push    iy
        pop     hl
        ld      de,OF_POS
        add     hl,de
        ld      de,SG+VW_OSEC           ; the position, kept for the end
        ld      bc,4
        ldir
        push    iy
        pop     de
        ld      hl,OF_POS
        add     hl,de
        ex      de,hl                   ; de -> the position
        ld      hl,SG+VW_P32
        ld      bc,4
        ldir                            ; the position = the new size
        ld      l,(iy+OF_SIZE)
        ld      h,(iy+OF_SIZE+1)
        ld      de,(SG+VW_P32)
        or      a
        sbc     hl,de
        ld      l,(iy+OF_SIZE+2)
        ld      h,(iy+OF_SIZE+3)
        ld      de,(SG+VW_P32+2)
        sbc     hl,de
        jp      c,.longer
        ; Shorter, or the same: the size, the tail, then the chain cut.
        push    iy
        pop     de
        ld      hl,OF_SIZE
        add     hl,de
        ex      de,hl
        ld      hl,SG+VW_P32
        ld      bc,4
        ldir
        ld      (iy+OF_TAIL),0
        ld      (iy+OF_TAIL+1),0
        ld      l,(iy+OF_FIRST)
        ld      h,(iy+OF_FIRST+1)
        ld      a,h
        or      l
        jp      z,.entry                ; no chain to cut
        ld      hl,(SG+VW_P32)
        ld      a,h
        or      l
        ld      hl,(SG+VW_P32+2)
        or      h
        or      l
        jr      nz,.cut
        ld      l,(iy+OF_FIRST)         ; empty: the whole chain goes
        ld      h,(iy+OF_FIRST+1)
        ld      (iy+OF_FIRST),0
        ld      (iy+OF_FIRST+1),0
        jr      .free
.cut:   ; The cluster holding the last byte: the cursor at size - 1.
        ld      hl,(SG+VW_P32)
        ld      de,(SG+VW_P32+2)
        ld      a,h
        or      l
        jr      nz,.d1
        dec     de
.d1:    dec     hl
        ld      (iy+OF_POS),l
        ld      (iy+OF_POS+1),h
        ld      (iy+OF_POS+2),e
        ld      (iy+OF_POS+3),d
        ld      a,(iy+OF_VOL)
        call    fat_mnt
        ld      a,(ix+M_SPCSH)
        add     a,9
        push    iy
        pop     ix
        call    of_cursor
        ld      iy,(SG+VV_ROW)
        ret     c
        jr      z,.entry                ; shorter than its size said
        ld      l,(iy+OF_CLUS)
        ld      h,(iy+OF_CLUS+1)
        ld      (iy+OF_TAIL),l
        ld      (iy+OF_TAIL+1),h
        push    hl
        ld      a,(iy+OF_VOL)
        call    fat_next
        pop     de
        ret     c
        jr      z,.entry                ; the chain's end already
        push    hl                      ; the rest, to free
        ex      de,hl
        ld      iy,(SG+VV_ROW)
        ld      a,(iy+OF_VOL)
        push    hl
        call    fat_eoc
        pop     hl
        ld      a,(iy+OF_VOL)
        call    fat_set                 ; the last: an end mark
        pop     hl
        ret     c
.free:  ld      iy,(SG+VV_ROW)
        ld      a,(iy+OF_VOL)
        call    fat_free_chain
        ret     c
.entry: call    wr_stamp
        ld      iy,(SG+VV_ROW)
        call    wr_update_entry
        call    wr_finish
        jr      .back
.longer:
        ld      hl,0                    ; the write pass with no bytes,
        ld      b,h                     ;   from the size to the position
        ld      c,l
        call    ks_write.pass
.back:  push    af
        ld      iy,(SG+VV_ROW)
        ld      (iy+OF_CLUS),low OF_CLUS_NONE
        ld      (iy+OF_CLUS+1),high OF_CLUS_NONE
        push    iy
        pop     de
        ld      hl,OF_POS
        add     hl,de
        ex      de,hl
        ld      hl,SG+VW_OSEC
        ld      bc,4
        ldir                            ; the position, as it was
        pop     af
        ret
.isdir: ld      a,E_ISDIR
        scf
        ret
.badf:  ld      a,E_BADF
        scf
        ret

; ks_unlink — SYS_UNLINK: HL = a file's path: its entry deleted, then its
; chain freed.
ks_unlink:
        call    vfs_getpath
        ret     c
        call    vfs_lookup
        ret     c
        ld      a,(SG+VR_KIND)
        cp      VK_ENTRY
        jr      nz,.isdir               ; a root, /mnt, a directory by cluster
        ld      a,(SG+VR_ATTR)
        and     DA_DIR
        jr      nz,.isdir
        ld      a,(SG+VR_ATTR)
        and     DA_RDONLY
        jr      nz,.acces
        xor     a                       ; any row
        call    vfs_busy
        ret     c
        call    dir_free_name
        ret     c
        ld      hl,(SG+VR_CLUS)
        ld      a,h
        or      l
        ret     z                       ; an empty file: no chain
        ld      a,(SG+VR_VOL)
        call    fat_free_chain
        jp      wr_finish
.isdir: ld      a,E_ISDIR
        scf
        ret
.acces: ld      a,E_ACCES
        scf
        ret

; ks_mkdir — SYS_MKDIR: HL = a path whose last component is missing: a
; directory made there — its cluster allocated and zeroed, . and .. written,
; the table flushed, then the entry in the parent.
ks_mkdir:
        call    vfs_getpath
        ret     c
        ld      a,1
        ld      (SG+VW_CREATE),a
        call    vfs_lookup
        push    af
        xor     a
        ld      (SG+VW_CREATE),a
        pop     af
        jp      nc,.exist
        cp      E_NOENT
        scf                             ; cp cleared the carry
        ret     nz
        ld      a,(SG+VR_KIND)
        cp      VK_BADNAME
        jp      z,.inval
        cp      VK_PARENT
        jp      nz,.noent
        call    wr_stamp
        ; A cluster, from the hint.
        ld      a,(SG+VV_VOL)
        call    fat_mnt
        ld      l,(ix+M_HINT)
        ld      h,(ix+M_HINT+1)
        ld      a,(SG+VV_VOL)
        call    fat_alloc
        jp      c,wr_finish
        ld      (SG+VW_NCLUS),hl
        ld      a,(SG+VV_VOL)
        call    fat_mnt
        ld      (ix+M_HINT),l
        ld      (ix+M_HINT+1),h
        ld      a,(SG+VV_VOL)
        call    dir_zero_cluster
        jp      c,wr_finish
        ; Its first sector: . and .. — . the cluster itself, .. the parent's
        ; (0 for a root).
        ld      hl,(SG+VW_NCLUS)
        ld      a,(SG+VV_VOL)
        call    fat_sector
        jp      c,wr_finish
        ld      a,(SG+VV_VOL)
        k_call  API_BGET                ; a hit: zeroed last
        jp      c,wr_finish
        push    hl
        push    hl
        pop     ix
        ld      (ix+0),'.'
        ld      b,10
.pad:   ld      (ix+1),' '
        inc     ix
        djnz    .pad
        pop     hl
        push    hl
        push    hl
        pop     ix
        ld      (ix+FE_ATTR),DA_DIR
        ld      a,(SG+VW_TIME)
        ld      (ix+FE_CTIME),a
        ld      (ix+FE_MTIME),a
        ld      a,(SG+VW_TIME+1)
        ld      (ix+FE_CTIME+1),a
        ld      (ix+FE_MTIME+1),a
        ld      a,(SG+VW_DATE)
        ld      (ix+FE_CDATE),a
        ld      (ix+FE_ADATE),a
        ld      (ix+FE_MDATE),a
        ld      a,(SG+VW_DATE+1)
        ld      (ix+FE_CDATE+1),a
        ld      (ix+FE_ADATE+1),a
        ld      (ix+FE_MDATE+1),a
        ld      a,(SG+VW_NCLUS)
        ld      (ix+FE_CLUS),a
        ld      a,(SG+VW_NCLUS+1)
        ld      (ix+FE_CLUS+1),a
        ; .. : a copy of . with the second dot and the parent's cluster.
        pop     hl
        push    hl
        ld      d,h
        ld      e,l
        ld      bc,FE_SIZEOF
        add     hl,bc                   ; hl -> the second entry
        ex      de,hl                   ; de -> it, hl -> the first
        push    de
        ldir
        pop     ix
        ld      (ix+1),'.'
        ld      a,(SG+VV_CLUS)
        ld      (ix+FE_CLUS),a
        ld      a,(SG+VV_CLUS+1)
        ld      (ix+FE_CLUS+1),a
        pop     hl
        k_call  API_BWRITE
        jp      c,wr_finish
        call    ks_bflush               ; the chain exists before the entry
        ret     c
        ; The entry in the parent, which the lookup left in VV_VOL/VV_CLUS.
        ld      a,DA_DIR
        ld      de,(SG+VW_NCLUS)
        call    dir_new_entry
        jp      wr_finish
.exist: ld      a,E_EXIST
        scf
        ret
.inval: ld      a,E_INVAL
        scf
        ret
.noent: ld      a,E_NOENT
        scf
        ret

; ks_rmdir — SYS_RMDIR: HL = an empty directory's path: its entry in the
; parent deleted, then its cluster chain freed.
ks_rmdir:
        call    vfs_getpath
        ret     c
        call    vfs_lookup
        ret     c
        ld      a,(SG+VR_KIND)
        cp      VK_ENTRY
        jr      z,.entry
        cp      VK_NODE
        jp      z,.inval                ; . or .. : no entry to delete
        jp      .busy                   ; a volume's root, or /mnt
.entry: ld      a,(SG+VR_ATTR)
        and     DA_DIR
        jp      z,.notdir
        ; Somebody's current directory?
        ld      hl,K_PROC
        ld      b,NPROC
.proc:  ld      a,(hl)
        or      a                       ; PS_FREE
        jr      z,.nextp
        push    hl
        ld      de,P_CWD
        add     hl,de
        ld      a,(SG+VR_VOL)
        cp      (hl)
        jr      nz,.notcwd
        inc     hl
        ld      a,(SG+VR_CLUS)
        cp      (hl)
        jr      nz,.notcwd
        inc     hl
        ld      a,(SG+VR_CLUS+1)
        cp      (hl)
        jr      nz,.notcwd
        pop     hl
        jr      .busy
.notcwd:
        pop     hl
.nextp: ld      de,P_SIZE
        add     hl,de
        djnz    .proc
        xor     a                       ; open by anyone?
        call    vfs_busy
        ret     c
        ; Empty? Every entry but ., .., deleted and long-name ones fails it.
        ld      hl,(SG+VV_CLUS)         ; the parent, for the removal
        ld      (SG+VW_ODCLUS),hl
        ld      a,(SG+VR_VOL)
        ld      (SG+VV_VOL),a
        ld      hl,(SG+VR_CLUS)
        ld      (SG+VV_CLUS),hl
        call    dir_scan_start
        ret     c
.sector:
        call    dir_scan_next
        ret     c
        jr      z,.empty
        ld      a,(SG+VV_VOL)
        k_call  API_BGET
        ret     c
        ld      b,16
.e:     ld      a,(hl)
        or      a
        jr      z,.empty                ; FE_END: nothing further
        cp      FE_FREE
        jr      z,.skip
        cp      '.'
        jr      z,.skip                 ; . or ..
        push    hl
        ld      de,FE_ATTR
        add     hl,de
        bit     3,(hl)                  ; DA_LABEL: a long-name entry
        pop     hl
        jr      nz,.skip
        jr      .notempty
.skip:  ld      de,FE_SIZEOF
        add     hl,de
        djnz    .e
        jr      .sector
.empty: ld      hl,(SG+VW_ODCLUS)
        ld      (SG+VV_CLUS),hl
        call    dir_free_name
        ret     c
        ld      hl,(SG+VR_CLUS)
        ld      a,(SG+VR_VOL)
        call    fat_free_chain
        jp      wr_finish
.notempty:
        ld      a,E_NOTEMPTY
        scf
        ret
.notdir:
        ld      a,E_NOTDIR
        scf
        ret
.inval: ld      a,E_INVAL
        scf
        ret
.busy:  ld      a,E_BUSY
        scf
        ret

; ks_rename — SYS_RENAME: HL = the path of an entry, DE = its new path on
; the same volume. The new entry is written first — in a free slot of the
; new name's directory, or over the file the new name already is — then
; the old one deleted, a moved directory's .. corrected, a replaced file's
; chain freed.
ks_rename:
        push    de
        call    vfs_getpath
        pop     de
        ret     c
        ; The second path, before the first lookup reuses ST_VFS.
        ex      de,hl
        ld      de,VW_PATH2
        ld      bc,PATH_MAX
        call    um_in
        ld      hl,SG+VW_PATH2
        ld      bc,PATH_MAX
        xor     a
        cpir
        jp      nz,.long
        call    vfs_lookup
        ret     c
        ld      a,(SG+VR_KIND)
        cp      VK_ENTRY
        jp      nz,.busy                ; a root or /mnt cannot move
        ld      a,(SG+VR_ATTR)
        and     DA_RDONLY
        jp      nz,.acces
        xor     a
        call    vfs_busy
        ret     c
        ; The old entry, kept.
        ld      hl,SG+VR_DSEC
        ld      de,SG+VW_OSEC
        ld      bc,5
        ldir
        ld      a,(SG+VR_VOL)
        ld      (SG+VW_OVOL),a
        ld      a,(SG+VR_ATTR)
        ld      (SG+VW_OATTR),a
        ld      hl,(SG+VR_CLUS)
        ld      (SG+VW_OCLUS),hl
        ld      hl,SG+VR_ENT
        ld      de,SG+VW_OENT
        ld      bc,FE_SIZEOF
        ldir
        ld      a,(SG+VR_LN)
        ld      (SG+VW_OLN),a
        ld      hl,SG+VR_LSEC
        ld      de,SG+VW_OLSEC
        ld      bc,5
        ldir
        ld      hl,(SG+VV_CLUS)         ; its directory, for the removal
        ld      (SG+VW_ODCLUS),hl
        ; The new name, looked up as a creation would, the entry being
        ; moved no match for it: a change of case alone is a rename too.
        ld      hl,SG+VW_PATH2
        ld      de,SG+VV_PATH
        ld      bc,PATH_MAX
        ldir
        ld      hl,SG+VV_PATH
        ld      (SG+VV_P),hl
        xor     a
        ld      (SG+VW_NEW),a
        ld      a,1
        ld      (SG+VW_CREATE),a
        ld      (SG+VW_EXCL),a
        call    vfs_lookup
        push    af
        xor     a
        ld      (SG+VW_CREATE),a
        ld      (SG+VW_EXCL),a
        pop     af
        jr      nc,.exists
        cp      E_NOENT
        scf                             ; cp cleared the carry
        ret     nz
        ld      a,(SG+VR_KIND)
        cp      VK_BADNAME
        jp      z,.inval
        cp      VK_PARENT
        jp      nz,.noent
        ld      a,(SG+VV_VOL)
        ld      (SG+VW_DVOL),a
        ld      hl,(SG+VV_CLUS)
        ld      (SG+VW_DCLUS),hl
        jr      .check
.exists:
        ld      a,(SG+VR_KIND)
        cp      VK_ENTRY
        jp      nz,.exist               ; a root, /mnt, . or ..
        ; (The entry being moved is never found: the lookup left it out.)
.other: ld      a,(SG+VR_ATTR)
        ld      hl,SG+VW_OATTR
        or      (hl)
        and     DA_DIR
        jp      nz,.exist               ; a directory on either side
        ld      a,(SG+VR_ATTR)
        and     DA_RDONLY
        jp      nz,.acces
        xor     a
        call    vfs_busy                ; the file replaced is open
        ret     c
        ld      a,1
        ld      (SG+VW_NEW),a
        ld      a,(SG+VR_VOL)
        ld      (SG+VW_DVOL),a
        ld      hl,SG+VR_DSEC
        ld      de,SG+VW_TSEC
        ld      bc,5
        ldir
        ld      hl,(SG+VR_CLUS)
        ld      (SG+VW_TCLUS),hl
.check: ld      a,(SG+VW_DVOL)
        ld      hl,SG+VW_OVOL
        cp      (hl)
        jp      nz,.xdev
        ; A directory into its own subtree: climb .. from the new name's
        ; directory to the root, and refuse if the old one is met.
        ld      a,(SG+VW_OATTR)
        and     DA_DIR
        jr      z,.doit
        ld      a,(SG+VW_NEW)
        or      a
        jr      nz,.doit                ; a directory over a file: EEXIST above
        ld      hl,(SG+VW_DCLUS)
.climb: ld      a,h
        or      l
        jr      z,.doit                 ; the root
        ld      de,(SG+VW_OCLUS)
        or      a
        sbc     hl,de
        jp      z,.inval
        add     hl,de
        ld      a,(SG+VW_OVOL)
        call    fat_sector
        ret     c
        ld      a,(SG+VW_OVOL)
        k_call  API_BGET
        ret     c
        ld      de,FE_SIZEOF+FE_CLUS    ; the .. entry's cluster
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        jr      .climb
.doit:  ld      a,(SG+VW_NEW)
        or      a
        jr      nz,.over
        ; The old entry, written under the new name where the lookup
        ; found room for it, its parts before it.
        ld      a,(SG+VW_DVOL)
        ld      (SG+VV_VOL),a
        ld      hl,(SG+VW_DCLUS)
        ld      (SG+VV_CLUS),hl
        ld      hl,SG+VW_OENT
        ld      de,SG+VR_ENT
        ld      bc,FE_SIZEOF
        ldir
        call    dir_new_name
        jp      c,wr_finish
        jr      .unlinkold
.over:  ; Over the file that has the name: its slot keeps its name.
        ld      hl,(SG+VW_TSEC)
        ld      de,(SG+VW_TSEC+2)
        ld      a,(SG+VW_DVOL)
        k_call  API_BGET
        jp      c,wr_finish
        push    hl
        ld      a,(SG+VW_TIDX)
        call    ent_addr
        ld      de,FE_ATTR
        add     hl,de
        ex      de,hl
        ld      hl,SG+VW_OENT+FE_ATTR
        ld      bc,FE_SIZEOF-FE_ATTR
        ldir
        pop     hl
        k_call  API_BWRITE
        jp      c,wr_finish
.unlinkold:
        ld      hl,SG+VW_OSEC
        ld      de,SG+VR_DSEC
        ld      bc,5
        ldir
        ld      a,(SG+VW_OVOL)
        ld      (SG+VR_VOL),a
        ld      (SG+VV_VOL),a
        ld      hl,(SG+VW_ODCLUS)
        ld      (SG+VV_CLUS),hl
        ld      a,(SG+VW_OLN)
        ld      (SG+VR_LN),a
        ld      hl,SG+VW_OLSEC
        ld      de,SG+VR_LSEC
        ld      bc,5
        ldir
        call    dir_free_name
        jp      c,wr_finish
        ; A moved directory's .. names its new parent.
        ld      a,(SG+VW_OATTR)
        and     DA_DIR
        jr      z,.chain
        ld      hl,(SG+VW_OCLUS)
        ld      a,(SG+VW_OVOL)
        call    fat_sector
        jp      c,wr_finish
        ld      a,(SG+VW_OVOL)
        k_call  API_BGET
        jp      c,wr_finish
        push    hl
        ld      de,FE_SIZEOF+FE_CLUS
        add     hl,de
        ld      de,(SG+VW_DCLUS)
        ld      a,(hl)
        cp      e
        jr      nz,.dotdot
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      d
        jr      nz,.dotdot
        pop     hl
        jr      .chain                  ; the same parent
.dotdot:
        ld      (hl),e
        inc     hl
        ld      (hl),d
        pop     hl
        k_call  API_BWRITE
        jp      c,wr_finish
.chain: ; A replaced file's chain.
        ld      a,(SG+VW_NEW)
        or      a
        jr      z,.end
        ld      hl,(SG+VW_TCLUS)
        ld      a,h
        or      l
        jr      z,.end
        ld      a,(SG+VW_DVOL)
        call    fat_free_chain
        jp      wr_finish
.end:   xor     a
        jp      wr_finish
.long:  ld      a,E_NAMETOOLONG
        scf
        ret
.busy:  ld      a,E_BUSY
        scf
        ret
.acces: ld      a,E_ACCES
        scf
        ret
.exist: ld      a,E_EXIST
        scf
        ret
.inval: ld      a,E_INVAL
        scf
        ret
.noent: ld      a,E_NOENT
        scf
        ret
.xdev:  ld      a,E_XDEV
        scf
        ret
