; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; pattern — a driver block written to m6's contract (docs/drivers.md) for
; the test ROM: the contract's vehicle until a real driver exists. It is
; included at DRV_BASE of the ROM's driver bank and serves one device of
; PT_SECTORS sectors that is a FAT12 superfloppy: the first PT_K sectors
; — boot sector, FAT, root, and READER, the program the test spawns — are
; carried here from build/drvrom.vol (tests/drvrom/mkvol.py); every
; sector from PT_K is generated as it is read, byte i of sector n being
; the low byte of 7 n + i, xor 55h in the sector's second half, written
; byte by byte with interrupts enabled — 2-4 ms a sector, so that ticks
; land inside a long transfer, which is what the handler's invariant is
; tested against. The volume is read-only; a write is refused with E_ROFS
; except to the last sector, whose bytes are summed into a checksum the
; test reads back. The test drives it through query numbers of the
; block's own (80h and up): a failure to return on the next transfer, the
; counters, the status to answer, a spin of N ticks inside every transfer,
; and whether a transfer was left open — entered and never returned from.
; Variables: PT_RAM bytes of page 3, IX on every entry.
        include "drvrom/layout.inc"

PT_RAM          equ 64
PT_CALLS        equ 0           ; 2: transfers so far
PT_TICKS        equ 2           ; 2: ticks that passed inside the last one
PT_LCNT         equ 4           ; its count,
PT_LSLOT        equ 5           ; its first slot,
PT_LTGT         equ 6           ; its target segment
PT_STATUS       equ 7           ; what status answers
PT_FERR         equ 8           ; the errno the next transfer fails with,
PT_FCODE        equ 9           ; and the code; 0 = none armed
PT_SPIN         equ 10          ; ticks every transfer spins for
PT_SUM          equ 11          ; 2: the last write's checksum
PT_T0           equ 13          ; 2: the tick at the transfer's entry
PT_SEC          equ 15          ; 4: the sector being moved
PT_N            equ 19          ; sectors left
PT_SLOT         equ 20          ; the slot being filled
PT_WR           equ 21          ; 1 = a write
PT_SECS         equ 22          ; sectors of this transfer (for the sum)
PT_OPEN         equ 23          ; 1 from a transfer's entry to its return

        db      "M6DRV"                 ; DRV_SIGN
        db      DRV_VER_1               ; DRV_VER
        db      0                       ; DRV_FLAGS
        jp      pt_init                 ; DRV_INIT
        jp      pt_info                 ; DRV_INFO
        jp      pt_status               ; DRV_STATUS
        jp      pt_rw                   ; DRV_RW
        jp      pt_query                ; DRV_QUERY
        jp      pt_nosys                ; DRV_RES1
        jp      pt_nosys                ; DRV_RES2
        dw      PT_RAM                  ; DRV_RAM
        dw      0                       ; DRV_RELOC
        db      "pattern         "      ; DRV_NAME
        ASSERT  $-DRV_BASE == DRV_HDR

; init — one device. The RAM comes cleared; status answers "unchanged".
pt_init:
        ld      (ix+PT_STATUS),DS_SAME
        ld      a,1
        or      a
        ret

; info — A = device, HL -> the DI_SIZE buffer.
pt_info:
        dec     a
        jr      nz,pt_nxio
        push    hl
        ld      (hl),0
        ld      d,h
        ld      e,l
        inc     de
        ld      bc,DI_SIZE-1
        ldir
        pop     hl
        push    hl
        ld      (hl),DIF_RO             ; DI_FLAGS
        ld      bc,DI_COUNT
        add     hl,bc
        ld      (hl),PT_SECTORS
        pop     hl
        push    hl
        ld      bc,DI_NAME
        add     hl,bc
        ex      de,hl
        ld      hl,pt_name
        ld      bc,32
        ldir
        pop     hl
        ld      bc,DI_IDENT
        add     hl,bc
        ld      (hl),7Fh                ; slot: none
        inc     hl
        ld      (hl),1                  ; device
        inc     hl
        ld      (hl),1                  ; LUN
        xor     a
        ret
pt_nxio:
        ld      b,0
        ld      a,E_NXIO
        scf
        ret
pt_nosys:
        ld      b,0
        ld      a,E_NOSYS
        scf
        ret

; status — A = device: what the test set, DS_SAME at init.
pt_status:
        dec     a
        jr      nz,pt_nxio
        ld      a,(ix+PT_STATUS)
        or      a
        ret

; rw — A = device, CF = write, B = count, C = slot, DE:HL = sector.
pt_rw:
        ld      (ix+PT_OPEN),1
        push    af
        ld      (ix+PT_N),b
        ld      (ix+PT_SECS),b
        ld      (ix+PT_LCNT),b
        ld      (ix+PT_SLOT),c
        ld      (ix+PT_LSLOT),c
        ld      (ix+PT_SEC),l
        ld      (ix+PT_SEC+1),h
        ld      (ix+PT_SEC+2),e
        ld      (ix+PT_SEC+3),d
        inc     (ix+PT_CALLS)
        jr      nz,.counted
        inc     (ix+PT_CALLS+1)
.counted:
        call    K_API2+3*API2_DRV_TGTSEG
        ld      (ix+PT_LTGT),a
        ld      hl,(K_TICKS)
        ld      (ix+PT_T0),l
        ld      (ix+PT_T0+1),h
        pop     af
        push    af
        ld      a,0
        rla                             ; a = CF
        ld      (ix+PT_WR),a
        pop     af
        dec     a
        jr      nz,pt_nxio
        ; A spin armed: as many ticks pass inside every call, the
        ; interrupts on, before a byte moves.
        ld      a,(ix+PT_SPIN)
        or      a
        jr      z,.nospin
        ld      b,a
.spin:  ld      hl,(K_TICKS)
        ld      d,h
        ld      e,l
.wait:  ld      hl,(K_TICKS)
        or      a
        sbc     hl,de
        jr      z,.wait
        djnz    .spin
.nospin:
        ; A failure armed: this call returns it.
        ld      a,(ix+PT_FERR)
        or      a
        jr      z,.bounds
        ld      (ix+PT_FERR),0
        ld      b,(ix+PT_FCODE)
        scf
        jp      .done
.bounds:
        ; sector + count <= PT_SECTORS, the high bytes 0.
        ld      a,(ix+PT_SEC+1)
        or      (ix+PT_SEC+2)
        or      (ix+PT_SEC+3)
        jp      nz,.eio
        ld      a,(ix+PT_SEC)
        add     a,(ix+PT_N)
        jp      c,.eio
        cp      PT_SECTORS+1
        jp      nc,.eio
.sector:
        ld      a,(ix+PT_WR)
        or      a
        jr      nz,.write
        ld      a,(ix+PT_SEC)
        cp      PT_K
        jr      c,.carried
        ; A generated sector: 512 bytes of the pattern.
        ld      d,a
        add     a,a
        add     a,a
        add     a,a
        sub     d                       ; a = 7 n, low byte
        ld      c,a
        ld      a,(ix+PT_SLOT)
        add     a,80h
        ld      h,a
        ld      l,0
        ld      e,0
.lo:    ld      a,c
        add     a,e
        ld      (hl),a
        inc     hl
        inc     e
        jr      nz,.lo
.hi:    ld      a,c
        add     a,e
        xor     55h
        ld      (hl),a
        inc     hl
        inc     e
        jr      nz,.hi
        jr      .next
.carried:
        ; A carried sector: from the image in this bank.
        ld      h,a
        ld      l,0
        add     hl,hl                   ; * 512
        ld      de,pt_vol
        add     hl,de
        ld      a,(ix+PT_SLOT)
        add     a,80h
        ld      d,a
        ld      e,0
        ld      bc,512
        ldir
        jr      .next
.write: ld      a,(ix+PT_SEC)
        cp      PT_SECTORS-1
        jr      nz,.rofs
        ld      a,(ix+PT_SLOT)
        add     a,80h
        ld      h,a
        ld      l,0
        ld      de,0                    ; the sum
        ld      bc,512
.sum:   ld      a,(hl)
        add     a,e
        ld      e,a
        jr      nc,.nc
        inc     d
.nc:    inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.sum
        ld      (ix+PT_SUM),e
        ld      (ix+PT_SUM+1),d
.next:  inc     (ix+PT_SLOT)
        inc     (ix+PT_SLOT)
        inc     (ix+PT_SEC)
        dec     (ix+PT_N)
        jr      nz,.sector
        xor     a
        ld      b,a
        jr      .done
.rofs:  ld      a,E_ROFS
        ld      b,0
        scf
        jr      .done
.eio:   ld      a,E_IO
        ld      b,0
        scf
.done:  ld      (ix+PT_OPEN),0
        push    af
        push    bc
        ld      hl,(K_TICKS)
        ld      e,(ix+PT_T0)
        ld      d,(ix+PT_T0+1)
        or      a
        sbc     hl,de
        ld      (ix+PT_TICKS),l
        ld      (ix+PT_TICKS+1),h
        pop     bc
        pop     af
        ret

; query — A = device, B = the number, HL -> its block in page 2.
pt_query:
        dec     a
        jp      nz,pt_nxio
        ld      a,b
        cp      80h
        jr      z,.fail
        cp      81h
        jr      z,.calls
        cp      82h
        jr      z,.ticks
        cp      83h
        jr      z,.last
        cp      84h
        jr      z,.status
        cp      85h
        jr      z,.spin
        cp      86h
        jr      z,.sum
        cp      87h
        jr      z,.open
        jp      pt_nosys
.fail:  ld      a,(hl)                  ; +0 the errno, +1 the code
        ld      (ix+PT_FERR),a
        inc     hl
        ld      a,(hl)
        ld      (ix+PT_FCODE),a
        jr      .ok
.calls: ld      l,(ix+PT_CALLS)
        ld      h,(ix+PT_CALLS+1)
        jr      .ok
.ticks: ld      l,(ix+PT_TICKS)
        ld      h,(ix+PT_TICKS+1)
        jr      .ok
.last:  ld      a,(ix+PT_LCNT)          ; +0 count, +1 slot, +2 segment
        ld      (hl),a
        inc     hl
        ld      a,(ix+PT_LSLOT)
        ld      (hl),a
        inc     hl
        ld      a,(ix+PT_LTGT)
        ld      (hl),a
        jr      .ok
.status:
        ld      a,(hl)
        ld      (ix+PT_STATUS),a
        jr      .ok
.spin:  ld      a,(hl)
        ld      (ix+PT_SPIN),a
        jr      .ok
.open:  ld      l,(ix+PT_OPEN)
        ld      h,0
        jr      .ok
.sum:   ld      l,(ix+PT_SUM)
        ld      h,(ix+PT_SUM+1)
.ok:    xor     a
        ld      b,a
        ret

pt_name:
        db      "pattern test device             "
        ASSERT  $-pt_name == 32
pt_vol:
        incbin  "build/drvrom.vol"
        ASSERT  $-pt_vol == PT_K*512
