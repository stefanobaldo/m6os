; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; blk — the test block of tests/blk: the block layer after the takeover —
; the volume table, a sector read through the volume-relative path with
; its bounds check, the cache hit, missed, evicted and written through, a
; direct read into a fresh segment, the RTC — calling the resident and
; the switched part through the jump table, under the window and the
; storage gate it enters itself. Run in two forms: inside blk.com, in
; page 0 before the kernel images, where the loader has found the file
; M6BLK.TST's sector, read the boot sector and left both in the record
; and the buffers; and from the kernel ROM, assembled on its own for
; 0100h of page 0 (tests/romblock.asm, M6_ROM defined), where step 7
; does what the loader did, through the block layer's device-relative
; path, from the file files.tcl wrote. The host includes m6test.inc and
; the kernel's exports before it.
    macro t_enter
        kwin_enter
        k_stgate_enter
    endm
    macro t_leave
        k_stgate_leave
        kwin_leave
    endm

t_entry:

    IFDEF M6_ROM
; --- step 7: what the loader prepared, from the volume itself ----------
; The ROM's boot wrote no KR_FIRST, no KR_TARGET and read no boot
; sector. The block takes the boot volume's first device sector from
; its row and puts it in the record; reads the boot sector through the
; device-relative path into KT_BUF_B; walks the root directory for
; M6BLK.TST, which files.tcl wrote with pattern P1, and puts its device
; sector in the record as the loader would have; reads that sector and
; requires P1, which stays in KT_BUF_A as the file's reference.
        ld      a,7
        ld      (t_step),a
        ld      hl,t_k7
        k_call  API_CON_PUTS
        ld      a,(K_BLK_ROOT)
        cp      VOL_NONE
        ld      a,0D0h                  ; no volume is the boot one
        jp      z,t_fail
        ld      a,(K_BLK_ROOT)
        call    t_row                   ; ix -> the boot volume's row
        ld      a,(ix+V_DRV)
        ld      (t_drv),a
        ld      a,(ix+V_DEV)
        ld      (t_dev),a
        ld      l,(ix+V_FIRST)
        ld      h,(ix+V_FIRST+1)
        ld      (K_REC+KR_FIRST),hl
        ld      e,(ix+V_FIRST+2)
        ld      d,(ix+V_FIRST+3)
        ld      (K_REC+KR_FIRST+2),de
        ; The boot sector, device sector first, into KT_BUF_B.
        call    t_sec_first
        call    t_dev_read
        jp      c,t_fail
        ld      hl,8000h+ST_SCRATCH
        ld      de,KT_BUF_B
        ld      bc,512
        ldir
        ; From it: root = reserved + fats * fatsz; rootsecs = rootent / 16;
        ; data = root + rootsecs. Sector size must be 512.
        ld      hl,(KT_BUF_B+0Bh)
        ld      de,512
        or      a
        sbc     hl,de
        ld      a,0D4h                  ; sector size is not 512
        jp      nz,t_fail
        ld      hl,(KT_BUF_B+0Eh)
        ld      de,(KT_BUF_B+16h)
        ld      a,(KT_BUF_B+10h)
.fats:  add     hl,de
        dec     a
        jr      nz,.fats
        ld      (t_dirsec),hl
        ld      hl,(KT_BUF_B+11h)
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        ld      (t_rootsecs),hl
        ld      de,(t_dirsec)
        add     hl,de
        ld      (t_data),hl
        ; Scan the root directory, one sector at a time.
        ld      hl,0
.scan:  ld      (t_n),hl
        ex      de,hl
        ld      hl,(t_rootsecs)
        or      a
        sbc     hl,de
        ld      a,0D5h                  ; entry not in the root directory
        jp      z,t_fail
        call    t_sec_first
        ld      hl,(t_dirsec)
        call    t_add32
        ld      hl,(t_n)
        call    t_add32
        call    t_dev_read
        jp      c,t_fail
        ld      hl,8000h+ST_SCRATCH
        ld      b,16
.entry: push    hl
        push    bc
        ld      de,t_fname11
        ld      b,11
.ch:    ld      a,(de)
        cp      (hl)
        jr      nz,.other
        inc     hl
        inc     de
        djnz    .ch
        pop     bc
        pop     ix                      ; the entry
        ld      l,(ix+1Ah)              ; first cluster
        ld      h,(ix+1Bh)
        ld      (t_cluster),hl
        jr      .found
.other: pop     bc
        pop     hl
        ld      de,32
        add     hl,de
        djnz    .entry
        ld      hl,(t_n)
        inc     hl
        jr      .scan
.found: ; target = first + data + (cluster - 2) * sectors per cluster
        call    t_sec_first
        ld      hl,(t_data)
        call    t_add32
        ld      hl,(t_cluster)
        dec     hl
        dec     hl
        ld      a,(KT_BUF_B+0Dh)
.mul:   push    af
        push    hl
        call    t_add32
        pop     hl
        pop     af
        dec     a
        jr      nz,.mul
        ld      hl,(t_sec)
        ld      (K_REC+KR_TARGET),hl
        ld      hl,(t_sec+2)
        ld      (K_REC+KR_TARGET+2),hl
        ld      hl,t_at
        k_call  API_CON_PUTS
        ld      hl,(K_REC+KR_TARGET+2)
        k_call  API_CON_HEX16
        ld      hl,(K_REC+KR_TARGET)
        k_call  API_CON_HEX16
        ; P1 into KT_BUF_A, and the file's sector must hold it.
        ld      a,5Ah
        call    k_fill_c
        ld      hl,KT_BUF_C
        ld      de,KT_BUF_A
        ld      bc,512
        ldir
        call    t_dev_read              ; t_sec is still the target
        jp      c,t_fail
        ld      hl,8000h+ST_SCRATCH
        ld      de,KT_BUF_A
        call    k_cmp512
        jp      nz,t_fail_cmp
        ld      hl,t_ok
        k_call  API_CON_PUTS
    ENDIF
; --- step 8: the table -------------------------------------------------
        ld      a,8
        ld      (t_step),a
        ld      hl,t_k8
        k_call  API_CON_PUTS
        ld      a,(K_BLK_NVOL)
        call    k_dec8
        ld      hl,t_root
        k_call  API_CON_PUTS
        ld      a,(K_BLK_ROOT)
        cp      VOL_NONE
        ld      a,0E0h                  ; no volume is the boot one
        jp      z,t_fail
        ld      a,(K_BLK_ROOT)
        call    k_dec8
        k_call  API_CON_NEWLINE
        ; t_rel = target - first: the file's sector relative to /.
        ld      hl,(K_REC+KR_TARGET)
        ld      de,(K_REC+KR_FIRST)
        or      a
        sbc     hl,de
        ld      (t_rel),hl
        ld      hl,(K_REC+KR_TARGET+2)
        ld      de,(K_REC+KR_FIRST+2)
        sbc     hl,de
        ld      (t_rel+2),hl

; --- step 9: blk_rw, and its bounds check -----------------------------
        ld      a,9
        ld      (t_step),a
        ld      hl,t_k9
        k_call  API_CON_PUTS
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,0
        ld      de,0                    ; sector 0 of /
        call    t_seg_bc                ; b = the storage segment
        ld      c,(ST_BUF+BUF_SCRATCH*512)/256
        or      a                       ; read
        k_call  API_BLK_RW
        t_leave
        jp      c,t_fail
        ld      hl,8000h+ST_BUF+BUF_SCRATCH*512
        ld      de,KT_BUF_B
        call    k_cmp512
        jp      nz,t_fail_cmp
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        dec     hl
        ld      a,h
        or      l
        ld      a,0E1h                  ; not exactly one driver call
        jp      nz,t_fail
        ; sector = count: EIO before the driver.
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        ld      a,(K_BLK_ROOT)
        call    t_row                   ; ix -> the row
        ld      l,(ix+V_COUNT)
        ld      h,(ix+V_COUNT+1)
        ld      e,(ix+V_COUNT+2)
        ld      d,(ix+V_COUNT+3)
        t_enter
        ld      a,(K_BLK_ROOT)
        call    t_seg_bc
        ld      c,(ST_BUF+BUF_SCRATCH*512)/256
        or      a
        k_call  API_BLK_RW
        t_leave
        ld      b,a
        ld      a,0E2h                  ; a sector at count was accepted
        jp      nc,t_fail
        ld      a,b
        cp      E_IO
        ld      a,0E3h                  ; refused with the wrong errno
        jp      nz,t_fail
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        ld      a,h
        or      l
        ld      a,0E4h                  ; the driver was called anyway
        jp      nz,t_fail
        ld      a,(K_BLK_LASTERR)
        or      a
        ld      a,0E5h                  ; a refused call left a code
        jp      nz,t_fail
        ; volume = nvol: EINVAL.
        t_enter
        ld      a,(K_BLK_NVOL)
        ld      hl,0
        ld      de,0
        call    t_seg_bc
        ld      c,(ST_BUF+BUF_SCRATCH*512)/256
        or      a
        k_call  API_BLK_RW
        t_leave
        ld      b,a
        ld      a,0E6h                  ; a volume past the table was accepted
        jp      nc,t_fail
        ld      a,b
        cp      E_INVAL
        ld      a,0E7h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 10: the cache -----------------------------------------------
        ld      a,10
        ld      (t_step),a
        ld      hl,t_k10
        k_call  API_CON_PUTS
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        call    t_bget_target           ; a miss
        jp      c,t_fail
        ld      (t_buf),hl
        call    t_bget_target           ; a hit: the same buffer, no call
        jp      c,t_fail
        ld      de,(t_buf)
        or      a
        sbc     hl,de
        ld      a,0E8h                  ; a hit returned another buffer
        jp      nz,t_fail
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        dec     hl
        ld      a,h
        or      l
        ld      a,0E9h                  ; two bgets, not one driver call
        jp      nz,t_fail
        ld      hl,(t_buf)
        call    t_page2                 ; 4000h+offset -> 8000h+offset
        ld      de,KT_BUF_A             ; the file's sector, P1
        call    k_cmp512
        jp      nz,t_fail_cmp
        ; A direct write of P3 from the buffer below the scratch one — the path
        ; data sectors are written through — while the cache holds the sector: the
        ; next bget must miss and return P3, not the copy it had.
        ld      a,03Ch                  ; pattern P3
        call    k_fill_c
        ld      hl,KT_BUF_C
        ld      de,8000h+ST_BUF+(BUF_SCRATCH-1)*512
        ld      bc,512
        ldir
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,(t_rel)
        ld      de,(t_rel+2)
        call    t_seg_bc
        ld      c,(ST_BUF+(BUF_SCRATCH-1)*512)/256 ; that buffer's first slot
        k_call  API_BWRITE_DIRECT
        t_leave
        jp      c,t_fail
        call    t_bget_target           ; dropped by the write: a miss
        jp      c,t_fail
        call    t_page2
        ld      de,KT_BUF_C             ; P3, from the disk
        call    k_cmp512
        jp      nz,t_fail_cmp
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        dec     hl
        dec     hl
        ld      a,h
        or      l
        ld      a,0EEh                  ; direct write + reread, not two calls
        jp      nz,t_fail
        ; 25 distinct sectors: the table fills and the target leaves it;
        ; then sector 0 again, which the 25th evicted.
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        ld      hl,0
.fill:  ld      (t_n),hl
        push    hl
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      de,0
        k_call  API_BGET
        t_leave
        pop     hl
        jp      c,t_fail
        inc     hl
        ld      a,l
        cp      25
        jr      c,.fill
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        ld      de,25
        or      a
        sbc     hl,de
        ld      a,h
        or      l
        ld      a,0EAh                  ; 25 distinct sectors, not 25 calls
        jp      nz,t_fail
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,0
        ld      de,0
        k_call  API_BGET
        t_leave
        jp      c,t_fail
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        dec     hl
        ld      a,h
        or      l
        ld      a,0EBh                  ; sector 0 was not evicted
        jp      nz,t_fail
        ; Write through: P2 into the target's buffer, bwrite, drop, get.
        ld      a,0A5h
        call    k_fill_c
        call    t_bget_target
        jp      c,t_fail
        ld      (t_buf),hl
        call    t_page2
        ex      de,hl
        ld      hl,KT_BUF_C
        ld      bc,512
        ldir
        ld      hl,(K_BLK_CALLS)
        ld      (t_calls),hl
        t_enter
        ld      hl,(t_buf)
        k_call  API_BWRITE
        t_leave
        jp      c,t_fail
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,(t_rel)
        ld      de,(t_rel+2)
        k_call  API_BDROP
        t_leave
        call    t_bget_target           ; from the disk again
        jp      c,t_fail
        call    t_page2
        ld      de,KT_BUF_C
        call    k_cmp512
        jp      nz,t_fail_cmp
        ld      hl,(K_BLK_CALLS)
        ld      de,(t_calls)
        or      a
        sbc     hl,de
        dec     hl
        dec     hl
        ld      a,h
        or      l
        ld      a,0ECh                  ; write + reread, not two calls
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 11: a direct read into a fresh segment, copied both ways -----
        ld      a,11
        ld      (t_step),a
        ld      hl,t_k11
        k_call  API_CON_PUTS
        ; The highest free segment: take every one, give them back, take
        ; the first the allocator hands out — the last it pushed.
.take:  ld      b,1                     ; owner 1: the test
        k_call  API_MEM_ALLOC
        jr      nc,.take
        ld      b,1
        k_call  API_MEM_FREE_ALL
        ld      b,1
        k_call  API_MEM_ALLOC
        jp      c,t_fail
        ld      (t_seg),a
        ld      l,a
        ld      h,0
        k_call  API_CON_DEC16
        k_call  API_MEM_INFO            ; de = usable segments
        ld      hl,128
        or      a
        sbc     hl,de                   ; 128 - usable
        jr      nc,.small               ; usable <= 128
        ld      a,(t_seg)
        cp      128
        ld      a,0EDh                  ; a large machine gave a low segment
        jp      c,t_fail
.small: t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,(t_rel)
        ld      de,(t_rel+2)
        ld      a,(t_seg)
        ld      b,a
        ld      c,6                     ; slot 6: offset 0600h
        ld      a,(K_BLK_ROOT)
        k_call  API_BREAD_DIRECT
        t_leave
        jp      c,t_fail
        ; From (seg, 0600h) into the storage segment's scratch buffer.
        t_enter
        ld      a,(t_seg)
        ld      ixh,a
        ld      a,(K_REC+KR_SEG64K+2)
        ld      ixl,a
        ld      hl,0600h
        ld      de,ST_BUF+BUF_SCRATCH*512
        ld      bc,512
        k_call  API_K_COPY
        t_leave
        ld      hl,8000h+ST_BUF+BUF_SCRATCH*512
        ld      de,KT_BUF_C             ; P2, what the file holds now
        call    k_cmp512
        jp      nz,t_fail_cmp
        ; And back: from the scratch buffer into (seg, 0A00h), then from
        ; there into buffer 22, and compare.
        t_enter
        ld      a,(K_REC+KR_SEG64K+2)
        ld      ixh,a
        ld      a,(t_seg)
        ld      ixl,a
        ld      hl,ST_BUF+BUF_SCRATCH*512
        ld      de,0A00h
        ld      bc,512
        k_call  API_K_COPY
        ld      a,(t_seg)
        ld      ixh,a
        ld      a,(K_REC+KR_SEG64K+2)
        ld      ixl,a
        ld      hl,0A00h
        ld      de,ST_BUF+(BUF_SCRATCH-1)*512
        ld      bc,512
        k_call  API_K_COPY
        t_leave
        ld      hl,8000h+ST_BUF+(BUF_SCRATCH-1)*512
        ld      de,KT_BUF_C
        call    k_cmp512
        jp      nz,t_fail_cmp
        ld      a,(t_seg)
        ld      b,1
        k_call  API_MEM_FREE
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 12: the RTC --------------------------------------------------
        ld      a,12
        ld      (t_step),a
        ld      hl,t_k12
        k_call  API_CON_PUTS
        t_enter
        k_call  API_RTC_READ
        t_leave
        ld      (t_date),hl
        ld      (t_time),de
        ; YYYY-MM-DD HH:MM:SS from the two words.
        ld      hl,(t_date)
        ld      a,h
        srl     a                       ; year - 1980
        ld      l,a
        ld      h,0
        ld      de,1980
        add     hl,de
        k_call  API_CON_DEC16
        ld      a,'-'
        k_call  API_CON_PUTC
        ld      hl,(t_date)
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; month into bits 8-11 of h
        ld      a,h
        and     0Fh
        call    t_dec2
        ld      a,'-'
        k_call  API_CON_PUTC
        ld      a,(t_date)
        and     1Fh
        call    t_dec2
        ld      a,' '
        k_call  API_CON_PUTC
        ld      a,(t_time+1)
        srl     a
        srl     a
        srl     a                       ; hour
        call    t_dec2
        ld      a,':'
        k_call  API_CON_PUTC
        ld      hl,(t_time)
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      a,h
        and     3Fh                     ; minute
        call    t_dec2
        ld      a,':'
        k_call  API_CON_PUTC
        ld      a,(t_time)
        and     1Fh
        add     a,a                     ; second
        call    t_dec2
        k_call  API_CON_NEWLINE

; --- step 13: verdict -------------------------------------------------
        ld      hl,t_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
        jr      t_halt

; t_fail — A = error code, (t_step) = the step.
t_fail:
        push    af
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_step)
        call    k_dec8
        ld      hl,t_code
        k_call  API_CON_PUTS
        pop     af
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
t_halt: ei
        halt
        jr      t_halt

; t_fail_cmp — HL = offset of the first difference, B = expected, C = found.
t_fail_cmp:
        push    hl
        push    bc
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_step)
        call    k_dec8
        ld      hl,t_diff
        k_call  API_CON_PUTS
        pop     bc
        pop     hl
        push    bc
        k_call  API_CON_HEX16
        ld      a,' '
        k_call  API_CON_PUTC
        pop     bc
        ld      a,b
        k_call  API_CON_HEX8
        ld      a,' '
        k_call  API_CON_PUTC
        ld      a,c
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
        jr      t_halt

; t_bget_target — bget of the file's sector on /, under the gate. Out: HL
; = the buffer (page 1 address), or CF.
t_bget_target:
        t_enter
        ld      a,(K_BLK_ROOT)
        ld      hl,(t_rel)
        ld      de,(t_rel+2)
        k_call  API_BGET
        t_leave
        ret

; t_page2 — HL, a page-1 address of the storage segment as the cache
; returns it, to the same byte as process 0 sees it in page 2.
t_page2:
        ld      a,h
        add     a,40h
        ld      h,a
        ret

; t_seg_bc — B = the storage segment. Preserves everything else.
t_seg_bc:
        push    af
        ld      a,(K_REC+KR_SEG64K+2)
        ld      b,a
        pop     af
        ret

; t_row — A = a volume: IX -> its row.
t_row:  ld      ix,K_VOL
        or      a
        ret     z
        ld      de,VOL_SIZE
.mul:   add     ix,de
        dec     a
        jr      nz,.mul
        ret

; t_dec2 — A as two decimal digits.
t_dec2: ld      c,'0'
.tens:  cp      10
        jr      c,.units
        sub     10
        inc     c
        jr      .tens
.units: push    af
        ld      a,c
        k_call  API_CON_PUTC
        pop     af
        add     a,'0'
        k_call  API_CON_PUTC
        ret


    IFDEF M6_ROM
; t_sec_first — t_sec = the boot volume's first device sector.
t_sec_first:
        ld      hl,(K_REC+KR_FIRST)
        ld      (t_sec),hl
        ld      hl,(K_REC+KR_FIRST+2)
        ld      (t_sec+2),hl
        ret

; t_add32 — t_sec += HL, HL zero-extended.
t_add32:
        ld      de,(t_sec)
        add     hl,de
        ld      (t_sec),hl
        ret     nc
        ld      hl,(t_sec+2)
        inc     hl
        ld      (t_sec+2),hl
        ret

; t_dev_read — the device sector t_sec of the boot volume's device, read
; through the device-relative path into the storage segment's scratch
; buffer, under the gate. CF with the code on failure.
t_dev_read:
        t_enter
        ld      a,(t_drv)
        ld      ixh,a
        ld      ixl,1
        call    t_seg_bc
        ld      c,ST_SCRATCH/256
        ld      hl,(t_sec)
        ld      de,(t_sec+2)
        ld      a,(t_dev)
        or      a                       ; read
        k_call  API_BLK_DEV_RW
        t_leave
        ret
    ENDIF

        include "m6util.asm"

t_k8:       db  "8 volumes ",0
t_root:     db  " root ",0
t_k9:       db  "9 blk_rw, bounds: ",0
t_k10:      db  "10 cache hit, evict, write through: ",0
t_k11:      db  "11 direct read into segment ",0
t_k12:      db  "12 rtc ",0
t_ok:       db  " ok",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_code:     db  " code ",0
t_diff:     db  " differ at ",0

t_step:     db  0
t_seg:      db  0
t_n:        dw  0
t_calls:    dw  0
t_buf:      dw  0
t_rel:      ds  4
t_date:     dw  0
t_time:     dw  0

    IFDEF M6_ROM
t_k7:       db  "7 the file on the volume",0
t_at:       db  " at ",0
t_fname11:  db  "M6BLK   TST"
t_drv:      db  0
t_dev:      db  0
t_sec:      ds  4
t_dirsec:   dw  0
t_rootsecs: dw  0
t_data:     dw  0
t_cluster:  dw  0
    ENDIF
