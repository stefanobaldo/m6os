; The block layer's resident half: the volume table, the transfer path
; from a driver into any segment, the driver queries the enumeration
; needs, and the copy between two segments. The cold half — the
; enumeration, the listing, the cache, the RTC — is ks_blk.asm, in the
; switched part.
;
; Everything here is called under the window (page 2 = the switched part)
; and the storage gate (page 1 = the storage segment): by the switched part
; itself, or by a test that entered both. A routine that maps another
; segment into page 2 for a driver call puts the window back before it
; returns, from K_KSEG, without reading the mapper register; page 1 is
; never remapped by the mapper during a driver call — nx_enter and
; nx_leave switch its slot and put the RAM slot back, and the mapper
; register keeps saying what the gate put there. k_copy, which does remap
; page 1, restores it from K_PAGE1, which the gate wrote.
;
; A sector number is 32 bits, DE:HL with DE high. A target is a segment
; and a 256-byte slot in it (0-62; the sector must not cross the page), so
; that a whole sector goes from the driver into a process page at any
; 256-byte boundary — P0_PROG, where a program is loaded, included — with
; no copy. One sector per driver call (BLK_PER_CALL): the
; interrupt-disabled region of the call stays inside one frame.

; blk_rw — one sector of a volume, read or written.
; In:  A = volume, CF = 0 read / 1 write, DE:HL = sector relative to the
;      volume, B = target segment, C = target slot 0-62.
; Out: CF clear with A = 0; or CF set with A = the errno: E_INVAL (no such
;      volume or slot), E_IO (sector >= count, or a driver error), E_NXIO
;      (device or LUN not there, not ready), E_ROFS (write protected).
;      blk_lasterr = the driver's own code, 0 for a refused call;
;      blk_calls counts the calls that reached the driver. Corrupts
;      everything. Interrupts enabled on return.
blk_rw:
        ld      (blk_tgt),bc
        push    af                      ; the volume and CF
        ld      a,c
        cp      BLK_SLOTS
        jp      nc,.inval
        pop     af
        push    af
        ld      c,a                     ; c = the volume
        ld      a,(K_BLK_NVOL)
        dec     a
        cp      c                       ; CF if volume > nvol - 1
        jp      c,.inval
        ld      a,c
        ld      ix,K_VOL
        or      a
        jr      z,.row
        ld      bc,VOL_SIZE
.mul:   add     ix,bc
        dec     a
        jr      nz,.mul
.row:   ; The bounds check: DE:HL < V_COUNT, high words first.
        push    hl
        push    de
        ld      l,(ix+V_COUNT+2)
        ld      h,(ix+V_COUNT+3)
        or      a
        sbc     hl,de                   ; count.hi - sector.hi
        jp      c,.eio
        jr      nz,.inrange             ; count.hi > sector.hi
        pop     de
        pop     hl
        push    hl
        push    de
        ex      de,hl                   ; de = sector.lo
        ld      l,(ix+V_COUNT)
        ld      h,(ix+V_COUNT+1)
        or      a
        sbc     hl,de                   ; count.lo - sector.lo
        jp      c,.eio
        jp      z,.eio                  ; equal: sector == count
.inrange:
        pop     de
        pop     hl
        ; blk_sec = first + sector.
        ld      c,(ix+V_FIRST)
        ld      b,(ix+V_FIRST+1)
        add     hl,bc
        ld      (blk_sec),hl
        ld      l,(ix+V_FIRST+2)
        ld      h,(ix+V_FIRST+3)
        adc     hl,de
        ld      (blk_sec+2),hl
        ld      a,(ix+V_DRV)
        ld      b,(ix+V_DEV)
        ld      c,(ix+V_LUN)
        call    blk_desc_set
        ld      a,(blk_tgt+1)           ; the target segment into page 2
        out     (0FEh),a
        ld      a,(blk_tgt)             ; hl = 8000h + slot * 256
        add     a,80h
        ld      h,a
        ld      l,0
        ld      de,blk_sec
        ld      b,BLK_PER_CALL
        ld      ix,blk_desc
        pop     af                      ; CF = write
        call    nx_rw
        jr      blk_done
.eio:   pop     de
        pop     hl
        pop     af
        xor     a
        ld      (K_BLK_LASTERR),a
        ld      a,E_IO
        scf
        ret
.inval: pop     af
        xor     a
        ld      (K_BLK_LASTERR),a
        ld      a,E_INVAL
        scf
        ret

; blk_dev_rw — one sector of a device, read into the storage segment's
; BUF_SCRATCH: what the enumeration reads sector 0, EBRs and boot sectors
; with. In: A = driver 0-3 (a valid index; not checked), B = device, C =
; LUN, DE:HL = device sector. Out: as blk_rw. Corrupts everything.
blk_dev_rw:
        ld      (blk_sec),hl
        ld      (blk_sec+2),de
        call    blk_desc_set
        ld      a,(K_REC+KR_SEG64K+2)   ; the storage segment into page 2
        out     (0FEh),a
        ld      hl,8000h+ST_BUF+BUF_SCRATCH*512
        ld      de,blk_sec
        ld      b,BLK_PER_CALL
        ld      ix,blk_desc
        or      a                       ; read
        call    nx_rw
        ; fall through

; blk_done — A = the driver's code: record it, count the call, the window
; back, the code to an errno.
blk_done:
        ld      (K_BLK_LASTERR),a
        push    af
        ld      hl,(K_BLK_CALLS)
        inc     hl
        ld      (K_BLK_CALLS),hl
        ld      a,(K_KSEG)
        out     (0FEh),a
        pop     af
        or      a
        ret     z                       ; CF clear, A = 0
        ld      b,E_ROFS
        cp      0F8h                    ; .WPROT
        jr      z,.err
        ld      b,E_NXIO
        cp      0FCh                    ; .NRDY
        jr      z,.err
        cp      0B5h                    ; .IDEVL
        jr      z,.err
        ld      b,E_IO
.err:   ld      a,b
        scf
        ret

; blk_desc_set — blk_desc from driver A (its slot and bank in the record),
; device B, LUN C. Corrupts AF, DE; preserves BC, HL.
blk_desc_set:
        push    hl
        add     a,a
        add     a,KR_DRVS
        ld      e,a
        ld      d,0
        ld      hl,K_REC
        add     hl,de
        ld      a,(hl)
        ld      (blk_desc+NXD_SLOT),a
        inc     hl
        ld      a,(hl)
        ld      (blk_desc+NXD_BANK),a
        ld      a,b
        ld      (blk_desc+NXD_DEV),a
        ld      a,c
        ld      (blk_desc+NXD_LUN),a
        pop     hl
        ret

; blk_query — ask a driver about a device, a LUN, or itself, into ST_INFO
; of the storage segment: D = BQ_DEVINFO (DEV_INFO basic information, 2
; bytes), BQ_LUNINFO (LUN_INFO, 12 bytes), BQ_DRVNAME (DRV_NAME, 32
; bytes). In: A = driver, B = device, C = LUN. Out: CF clear, or CF with
; A = E_NXIO when the driver says the device or LUN is not there. Not a
; DEV_RW: blk_calls does not count it. Corrupts everything.
blk_query:
        push    de
        call    blk_desc_set
        ld      a,(K_REC+KR_SEG64K+2)   ; the storage segment into page 2
        out     (0FEh),a
        push    bc
        ld      ix,blk_desc
        call    nx_enter                ; interrupts off until nx_leave
        pop     bc
        pop     de
        ld      hl,8000h+ST_INFO
        ld      a,d
        or      a
        jr      z,.devinfo
        dec     a
        jr      z,.luninfo
        ex      de,hl                   ; the name: 32 bytes from the bank
        ld      hl,NX_DRV_NAME
        ld      bc,32
        ldir
        xor     a
        jr      .leave
.devinfo:
        ld      a,b                     ; device
        ld      b,0                     ; basic information
        call    NX_DEV_INFO
        jr      .leave
.luninfo:
        ld      a,b                     ; device
        ld      b,c                     ; LUN
        call    NX_LUN_INFO
.leave: push    af
        call    nx_leave                ; interrupts on
        ld      a,(K_KSEG)
        out     (0FEh),a
        pop     af
        or      a
        ret     z
        ld      a,E_NXIO
        scf
        ret

; k_copy — BC bytes from (segment IXH, offset HL) to (segment IXL, offset
; DE); neither range crosses its page. The source goes into page 1, the
; destination into page 2; page 1 comes back from K_PAGE1 (the gate's),
; page 2 from K_KSEG (the window). No DI: the interrupt handler touches
; page 3 and the VDP only and never switches with the PC in page 3.
; Corrupts AF, BC, DE, HL.
k_copy:
        ld      a,ixh
        out     (0FDh),a
        ld      a,ixl
        out     (0FEh),a
        set     6,h                     ; + 4000h
        set     7,d                     ; + 8000h
        ldir
        ld      a,(K_PAGE1)
        out     (0FDh),a
        ld      a,(K_KSEG)
        out     (0FEh),a
        ret

; The volume table and the scalars a test reads are in the header (K_VOL,
; K_BLK_NVOL, K_BLK_ROOT, K_BLK_CALLS, K_BLK_LASTERR); the rest is here.
blk_sec:        ds 4            ; the device sector handed to the driver
blk_desc:       ds NXD_SIZE     ; the descriptor handed to nx_rw
blk_tgt:        dw 0            ; low: the slot, high: the segment
