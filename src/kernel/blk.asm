; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The block layer's resident half: the volume table, the transfer path
; from a driver into any segment, the queries the enumeration needs, the
; one path every driver is called through, and the copy between two
; segments. The cold half — the enumeration, the listing, the cache, the
; RTC — is kboot.asm and ks_blk.asm.
;
; Everything here is called under the window (page 2 = the switched part)
; and the storage gate (page 1 = the storage segment): by the switched part
; itself, or by a test that entered both. A routine that maps another
; segment into page 2 for a driver call puts the window back before it
; returns, from K_KSEG, without reading the mapper register; page 1 is
; never remapped by the mapper during a driver call — blk_drv_call
; switches its slot to the driver's and puts the RAM slot back, and the
; mapper register keeps saying what the gate put there. k_copy, which
; does remap page 1, restores it from K_PAGE1, which the gate wrote.
;
; A driver is a row of the record's KR_DRVS: a slot, a bank and a kind — a
; bank of m6's own kernel ROM holding a driver block at DRV_BASE (KD_M6),
; or a Nextor 2 driver bank (KD_NEXTOR), which the second half of
; blk_drv_call, the legacy adapter, calls as nx_rw did, under M6_ADAPTER.
; Both run in page 1 of the driver's slot with its bank selected, on the
; kernel's stack, page 0 the process's with its vector: a block with
; interrupts enabled and IX -> its page-3 variables, a Nextor bank under
; DI for the length of each sector. The interrupt handler, finding SP in
; page 3, counts the tick and returns (irq.asm): a driver call is never
; preempted and never loses a tick.
;
; A sector number is 32 bits, DE:HL with DE high. A target is a segment
; and a 256-byte slot in it (0-62), the sector landing at slot * 256; a
; call moves 1 to 32 sectors and never crosses the page (slot + 2 * count
; <= 64), so that whole sectors go from the driver into a process page at
; any 256-byte boundary — P0_PROG, where a program is loaded, included —
; with no copy.

; blk_rw — sectors of a volume, read or written.
; In:  A = volume | (count - 1) << 3: the volume 0-7, the count 1-32;
;      CF = 0 read / 1 write; DE:HL = the first sector relative to the
;      volume; B = target segment; C = target slot 0-62.
; Out: CF clear with A = 0; or CF set with A = the errno: E_INVAL (no such
;      volume, or slot + 2 * count past the page), E_IO (a sector past the
;      volume's end, or a driver error), E_NXIO (device not there, not
;      ready), E_ROFS (write protected). blk_lasterr = the driver's own
;      code, 0 for a refused call; blk_calls counts the calls that reached
;      the driver. Corrupts everything. Interrupts enabled on return.
blk_rw:
        ld      (blk_tgt),bc
        push    af                      ; CF
        ld      c,a
        and     7
        ld      b,a                     ; b = the volume; DE:HL is the sector
        ld      a,c
        rrca
        rrca
        rrca
        and     1Fh
        inc     a                       ; the count, 1-32
        ld      (blk_n),a
        add     a,a
        ld      c,a                     ; 2 * count
        ld      a,(blk_tgt)             ; the slot
        add     a,c
        jp      c,.inval                ; a slot past 255 - 2 * count
        cp      65
        jp      nc,.inval               ; slot + 2 * count > 64
        ld      a,(K_BLK_NVOL)
        dec     a
        cp      b                       ; CF if volume > nvol - 1
        jp      c,.inval
        ld      a,b
        ld      ix,K_VOL
        or      a
        jr      z,.row
        ld      bc,VOL_SIZE
.mul:   add     ix,bc
        dec     a
        jr      nz,.mul
.row:   ; The bounds check: sector + count <= V_COUNT, 32 bits.
        push    hl
        push    de
        ld      a,(blk_n)
        ld      c,a
        ld      b,0
        add     hl,bc                   ; hl = end.lo
        jr      nc,.nc
        inc     de                      ; de = end.hi
        ld      a,d
        or      e
        jp      z,.eio                  ; wrapped past 2^32
.nc:    push    hl
        ld      l,(ix+V_COUNT+2)
        ld      h,(ix+V_COUNT+3)
        or      a
        sbc     hl,de                   ; count.hi - end.hi
        pop     hl
        jp      c,.eio
        jr      nz,.inrange             ; count.hi > end.hi
        ex      de,hl                   ; de = end.lo
        ld      l,(ix+V_COUNT)
        ld      h,(ix+V_COUNT+1)
        or      a
        sbc     hl,de                   ; count.lo - end.lo
        jp      c,.eio
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
        ld      (blk_drvi),a
        ld      a,(ix+V_DEV)
        ld      (blk_dev),a
        pop     af                      ; CF
        jr      blk_go
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

; blk_dev_rw — sectors of a device, no bounds: what the enumeration reads
; sector 0, EBRs and boot sectors with, and what a test writes with. In:
; A = device, IXH = driver index 0-3 (a valid one; not checked), IXL =
; count 1-32, B = target segment, C = target slot (slot + 2 * count <= 64,
; not checked), DE:HL = device sector, CF = write. Out: as blk_rw.
; Corrupts everything.
blk_dev_rw:
        ld      (blk_tgt),bc
        ld      (blk_sec),hl
        ld      (blk_sec+2),de
        ld      (blk_dev),a
        push    ix
        pop     hl
        ld      (blk_n),hl              ; blk_n = IXL, blk_drvi = IXH
        ; fall through

; blk_go — the transfer: CF, blk_tgt, blk_sec, blk_n, blk_dev and blk_drvi
; set. The target segment into page 2, the call, the window back.
blk_go:
        ld      a,0
        rla                             ; a = CF
        ld      (blk_wr),a
        ld      a,BO_RW
        ld      (blk_op),a
        ld      a,(blk_tgt+1)
        out     (0FEh),a                ; the target segment into page 2
        call    blk_drv_call
        push    af
        ld      a,b
        ld      (K_BLK_LASTERR),a
        ld      hl,(K_BLK_CALLS)
        inc     hl
        ld      (K_BLK_CALLS),hl
        ld      a,(K_KSEG)
        out     (0FEh),a
        pop     af
        ret

; blk_query — ask a driver about itself or a device, into a buffer of the
; storage segment, which the call maps into page 2. In: A = driver index,
; B = device, D = the query (BQ_*), E = its number (BQ_QUERY) or LUN
; (BQ_LUNINFO), HL = the buffer, as page 2 sees it (8000h + offset).
; BQ_INIT, BQ_INFO, BQ_STATUS and BQ_QUERY are the contract's entries,
; which the adapter answers for a Nextor bank as it can (init: 49 devices;
; status: DEV_STATUS; info and query: E_NOSYS); BQ_DEVINFO, BQ_LUNINFO and
; BQ_DRVNAME are Nextor's own, for the enumeration to build a record from,
; with B = Nextor's device and E = its LUN. Out: CF clear and A, B as the
; entry says; CF set with A = the errno. Not a transfer: blk_calls does
; not count it. Corrupts everything.
blk_query:
        ld      (blk_drvi),a
        ld      a,b
        ld      (blk_dev),a
        ld      a,d
        ld      (blk_op),a
        ld      a,e
        ld      (blk_n),a
        ld      (blk_sec),hl
        ld      a,(K_REC+KR_SEG64K+2)   ; the storage segment into page 2
        out     (0FEh),a
        call    blk_drv_call
        push    af
        ld      a,(K_KSEG)
        out     (0FEh),a
        pop     af
        ret

; blk_drv_call — the one path to a driver. The row blk_drvi names: its
; slot into page 1, the bank in view there saved, its bank selected; then
; the entry blk_op names, by the row's kind — an m6 block's, with the
; contract's registers from the variables, IX -> its page-3 variables and
; interrupts enabled; or, under M6_ADAPTER, a Nextor bank's routine with
; Nextor's registers, under DI, its code mapped to the errno after it —
; then the bank back, the RAM slot back in page 1, interrupts on. Out: A
; and CF as the entry's contract says, B = the driver's own code, HL and
; DE as the entry left them (a query's answer). Corrupts everything else.
blk_drv_call:
        ld      a,(blk_drvi)
        ld      e,a
        add     a,a
        add     a,e                     ; * KD_SIZE
        add     a,KR_DRVS
        ld      l,a
        ld      h,0
        ld      de,K_REC
        add     hl,de                   ; hl -> the row
        ld      a,(hl)                  ; KD_SLOT
        inc     hl
        ld      c,(hl)                  ; KD_BANK
        inc     hl
        ld      b,(hl)                  ; KD_KIND
        ld      (blk_kb),bc
        ld      hl,4000h
        call    k_enaslt                ; interrupts off from here
        ld      a,(NX_CUR_BANK)
        ld      (blk_saved),a
        ld      a,(blk_kb)
        call    NX_CHGBNK
        ld      a,(blk_kb+1)
        or      a
        jr      nz,.block
    IFDEF M6_ADAPTER
        call    blk_nx                  ; the adapter: a Nextor bank
    ELSE
        ld      a,E_NXIO                ; no adapter in this kernel
        ld      b,0
        scf
    ENDIF
        jr      .leave
.block: ld      a,(blk_op)
        ld      hl,blk_optab
        add     a,l
        ld      l,a                     ; the table lies in one page
        ld      l,(hl)
        ld      h,high DRV_BASE
        ld      (blk_jp+1),hl
        ld      ix,(K_REC+KR_WALL)      ; the block's variables
        ld      bc,(blk_tgt)            ; c = the slot
        ld      a,(blk_n)
        ld      b,a                     ; the count, or the query number
        ld      hl,(blk_sec)            ; the sector, or the buffer
        ld      de,(blk_sec+2)
        ld      a,(blk_wr)
        rrca                            ; CF = write
        ld      a,(blk_dev)
        ei
        call    blk_jp
.leave: push    af
        push    bc
        push    de
        push    hl                      ; a query's answer
        ld      a,(blk_saved)
        call    NX_CHGBNK
        ld      a,(K_REC+KR_RAMAD+1)
        ld      hl,4000h
        call    k_enaslt
        ei
        pop     hl
        pop     de
        pop     bc
        pop     af
        ret
blk_jp: jp      0                       ; the operand is the entry

; A block's entry for each query, by BO_*: offsets into its header.
; Nextor's own queries have no entry in a block: the reserved one answers.
blk_optab:
        db      DRV_RW, DRV_INIT, DRV_INFO, DRV_STATUS, DRV_QUERY
        db      DRV_RES1, DRV_RES1, DRV_RES1
        ASSERT  high blk_optab == high (blk_optab+7)

; blk_tgtseg — A = the segment the current transfer's target is in: what
; API2_DRV_TGTSEG returns to a driver that hands the device the segment
; itself. Corrupts F.
blk_tgtseg:
        ld      a,(blk_tgt+1)
        ret

    IFDEF M6_ADAPTER
; blk_nx — the adapter: blk_op on a Nextor driver bank, in page 1 with
; interrupts off. A device number of the contract is Nextor's device
; (n - 1) / 7 + 1 and LUN (n - 1) mod 7 + 1. A transfer is one DEV_RW
; per sector, interrupts enabled for an instant between two. Out: A, CF
; as the contract says, B = Nextor's code. Corrupts everything.
blk_nx:
        ld      a,(blk_op)
        or      a
        jr      z,.rw
        dec     a
        jr      z,.init
        dec     a
        jr      z,.nosys                ; info: the enumeration asks Nextor's
        dec     a
        jr      z,.status
        dec     a
        jr      z,.nosys                ; query
        dec     a
        jr      z,.devinfo
        dec     a
        jr      z,.luninfo
        ld      hl,NX_DRV_NAME          ; drvname: 32 bytes from the bank
        ld      de,(blk_sec)
        ld      bc,32
        ldir
.ok:    xor     a
        ld      b,a
        ret
.init:  ld      a,49
        ld      b,0
        or      a
        ret
.nosys: ld      a,E_NOSYS
        ld      b,0
        scf
        ret
.status:
        ld      a,(blk_dev)
        call    blk_nx_devlun           ; a = device, b = LUN
        call    NX_DEV_STATUS
        ld      b,0
        or      a
        ret
.devinfo:
        ld      a,(blk_dev)             ; Nextor's device
        ld      b,0                     ; basic information
        ld      hl,(blk_sec)
        call    NX_DEV_INFO
        jr      .asked
.luninfo:
        ld      a,(blk_dev)
        ld      hl,blk_n
        ld      b,(hl)                  ; the LUN
        ld      hl,(blk_sec)
        call    NX_LUN_INFO
.asked: ld      b,a
        or      a
        ret     z
        ld      a,E_NXIO
        scf
        ret
.rw:    ld      a,(blk_dev)
        call    blk_nx_devlun
        ld      (blk_dl),de             ; the LUN, then the device
.sector:
        ld      a,(blk_tgt)
        add     a,80h
        ld      h,a
        ld      l,0                     ; the buffer, in page 2
        ld      de,blk_sec              ; -> the sector number
        ld      b,1
        ld      a,(blk_dl)
        ld      c,a                     ; the LUN
        ld      a,(blk_wr)
        rrca                            ; CF = write
        ld      a,(blk_dl+1)            ; the device
        call    NX_DEV_RW
        or      a
        jr      nz,.err
        ld      hl,blk_tgt
        inc     (hl)
        inc     (hl)                    ; the next slot
        ld      hl,(blk_sec)
        inc     hl
        ld      (blk_sec),hl
        ld      a,h
        or      l
        jr      nz,.more
        ld      hl,(blk_sec+2)
        inc     hl
        ld      (blk_sec+2),hl
.more:  ld      hl,blk_n
        dec     (hl)
        jp      z,.ok
        ei                              ; the tick, between two sectors
        nop
        di
        jr      .sector
.err:   ld      b,a                     ; the driver's code
        ld      c,E_ROFS
        cp      0F8h                    ; .WPROT
        jr      z,.errno
        ld      c,E_NXIO
        cp      0FCh                    ; .NRDY
        jr      z,.errno
        cp      0B5h                    ; .IDEVL
        jr      z,.errno
        ld      c,E_IO
.errno: ld      a,c
        scf
        ret

; blk_nx_devlun — A = a device of the contract: D = A = Nextor's device,
; E = B = its LUN. Corrupts F.
blk_nx_devlun:
        dec     a
        ld      e,1
.sub:   cp      7
        jr      c,.done
        sub     7
        inc     e
        jr      .sub
.done:  inc     a
        ld      d,e                     ; d = the device
        ld      e,a                     ; e = the LUN
        ld      a,d
        ld      b,e
        ret
    ENDIF

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
blk_sec:        ds 4            ; the device sector handed to the driver,
                                ; or the buffer of a query
blk_tgt:        dw 0            ; low: the slot, high: the segment
blk_n:          db 0            ; the count, or a query's number or LUN
blk_drvi:       db 0            ; the driver's index (after blk_n: a word)
blk_dev:        db 0            ; the device
blk_wr:         db 0            ; 1 = write
blk_op:         db 0            ; BO_*
blk_kb:         dw 0            ; the row's bank, then its kind
blk_saved:      db 0            ; the bank in view before the call
    IFDEF M6_ADAPTER
blk_dl:         dw 0            ; the adapter's LUN, then device
    ENDIF
