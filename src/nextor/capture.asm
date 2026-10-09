; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; nx_capture — fill the takeover record from Nextor's RAM and the BIOS work
; area, while Nextor is still there. This is the second and last routine in
; this directory that needs the Nextor kernel (nx_find is the first); a
; kernel that has taken the machine reads the record and nothing else.
;
; In:  IX -> KREC_SIZE-byte record. Fills every field except KR_DRV,
;      KR_FIRST, KR_TARGET and KR_TPRE, which the caller fills. Uses
;      KT_SCRATCH for the _GDRVR blocks, nx_header (abi2.asm, which the
;      including file includes first) and nx_capture_bios (capbios.asm,
;      the half that reads the BIOS alone, included at the end of this
;      file; a loader with no Nextor under it includes that file alone).
; Out: interrupts enabled. Corrupts everything but IX.
;
; The wall — the lowest page-3 address a driver still refers to — comes
; from SLTWRK: Nextor stores each kernel slot's work-area pointer in the
; first two bytes of that slot's 8-byte SLTWRK block when the driver asked
; for space, and lets the driver use the block itself otherwise. A block
; whose first word lies in [C000h, F1C9h) — ALLOC's range, below Nextor's
; fixed area — is a pointer; anything else is the driver's own data.
nx_capture:
        push    ix
        pop     de
        ld      hl,NX_RAMAD0            ; +0: RAMAD0-3
        ld      bc,4
        ldir
        ld      hl,NX_P0_64K            ; +4: the four segments in place
        ld      bc,4
        ldir
        ld      a,(NX_CODE_SEG)
        ld      (ix+KR_CODESEG),a
        ld      a,(NX_DATA_SEG)
        ld      (ix+KR_DATASEG),a
        ld      hl,(NX_MAP_TAB)         ; the primary mapper's record
        ld      a,(hl)
        ld      (ix+KR_MAPSLOT),a
        inc     hl
        ld      a,(hl)
        ld      (ix+KR_MAPTOTAL),a
        ld      hl,(NX_DOSHIM)
        ld      (ix+KR_DOSHIM),l
        ld      (ix+KR_DOSHIM+1),h
        push    ix
        pop     de
        ld      hl,KR_TIMISAVE
        add     hl,de
        ex      de,hl
        ld      hl,NX_TIMI_SAVE         ; +16: H.TIMI before Nextor
        ld      bc,5
        ldir
        ld      hl,NX_FCALSAV           ; +21: FCALL before Nextor
        ld      bc,5
        ldir
        push    ix
        pop     de
        ld      hl,KR_KSLOTS
        add     hl,de
        ex      de,hl
        ld      hl,NX_KER250            ; +48: the kernel slots
        ld      bc,4
        ldir
        ; The wall.
        ld      hl,0F1C9h
        ld      b,4
        push    ix
        pop     de
        push    hl
        ld      hl,KR_KSLOTS
        add     hl,de
        ex      de,hl                   ; de -> the record's KER250 copy
        pop     hl
.slot:  ld      a,(de)
        or      a
        jr      z,.next                 ; an empty entry
        and     10001111b               ; drop the flag bits 5 and 6
        ld      c,a
        and     3
        rrca
        rrca
        rrca                            ; primary * 32
        push    bc
        ld      b,a
        ld      a,c
        rrca
        rrca
        and     3
        add     a,a
        add     a,a
        add     a,a                     ; subslot * 8
        or      b
        pop     bc
        push    de
        ld      e,a
        ld      d,0
        push    hl
        ld      hl,B_SLTWRK
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; de = the block's first word
        pop     hl
        ld      a,d
        cp      0C0h
        jr      c,.pop                  ; below C000h: not a pointer
        push    hl
        or      a
        sbc     hl,de                   ; wall - word
        pop     hl
        jr      c,.pop                  ; word above the wall
        jr      z,.pop
        ex      de,hl                   ; a lower pointer: the new wall
.pop:   pop     de
.next:  inc     de
        djnz    .slot
        ld      (ix+KR_WALL),l
        ld      (ix+KR_WALL+1),h
        call    nx_capture_bios         ; the BIOS half (capbios.asm)
        ; The drivers: _GDRVR for index 1 to 7; kept when the flags say a
        ; device-based Nextor driver and the header is where K_SIZE says;
        ; four stored, a fifth counted.
        xor     a
        ld      (ix+KR_NDRV),a
        ld      a,1
        ld      (nxc_index),a
.drv:   ld      a,(nxc_index)
        cp      8
        jr      nc,.drvdone
        ld      c,NX_GDRVR
        ld      hl,KT_SCRATCH
        push    ix
        call    BDOS
        pop     ix
        or      a
        jr      nz,.drvdone             ; .IDRVR: past the last; else stop
        ld      a,(KT_SCRATCH+4)        ; flags
        rlca                            ; bit 7: a Nextor driver
        jr      nc,.drvnext
        ld      a,(KT_SCRATCH+4)
        rrca                            ; bit 0: device-based
        jr      nc,.drvnext
        ld      a,(KT_SCRATCH+0)        ; slot
        push    ix
        call    nx_header
        pop     ix
        jr      nz,.drvnext
        ld      a,(ix+KR_NDRV)
        cp      4
        jr      nc,.drvfull
        add     a,a
        add     a,KR_DRVS
        ld      e,a
        ld      d,0
        push    ix
        pop     hl
        add     hl,de
        ld      a,(KT_SCRATCH+0)
        ld      (hl),a                  ; the slot
        inc     hl
        ld      (hl),b                  ; the bank
.drvfull:
        inc     (ix+KR_NDRV)
.drvnext:
        ld      a,(nxc_index)
        inc     a
        ld      (nxc_index),a
        jr      .drv
.drvdone:
        ret

nxc_index:
        db      0

        include "nextor/capbios.asm"
