; Nextor 2 driver access: find the driver behind a drive letter, then read
; and write device sectors by calling its DEV_RW entry point directly —
; slot switch, bank switch, call — never through the Nextor kernel.
;
; nx_find needs the Nextor BDOS and exists only while Nextor is resident;
; a file that defines NX_RW_ONLY before including this one leaves it out.
; nx_rw needs nothing of Nextor. Its two external needs are supplied by the
; including file: nx_enaslt, a routine with the BIOS ENASLT's contract
; (A = slot, HL = address, interrupts disabled on return), and nx_ramslot1,
; the address of a byte holding the RAM slot to put back in page 1. A
; program under Nextor points them at ENASLT and RAMAD1; a kernel that has
; taken the machine points them at its own.
;
; Both expect a stack outside page 1, run the driver with interrupts
; disabled and return with them enabled. The including file includes
; nextor/nextor.inc first.

    IFNDEF NX_RW_ONLY
; nx_find — fill a driver descriptor for a drive.
; In:  A = drive (0 = A:), IX -> NXD_SIZE-byte descriptor,
;      HL -> 64-byte scratch buffer, not in page 1.
; Out: A = NXE_OK, an NXE_* code, or a BDOS error code (80h and above);
;      DE:HL = first device sector of the drive's partition (DE high).
;      IX preserved; other registers corrupted.
nx_find:
        push    ix
        push    hl
        ld      c,NX_GDLI
        call    BDOS
        pop     hl
        or      a
        jp      nz,.done
        ld      a,(hl)                  ; +0 status: 1 = a device driver
        cp      1
        ld      a,NXE_NODEV
        jp      nz,.done
        inc     hl
        ld      a,(hl)                  ; +1 driver slot
        ld      (ix+NXD_SLOT),a
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)                  ; +4 device index
        ld      (ix+NXD_DEV),a
        inc     hl
        ld      a,(hl)                  ; +5 logical unit
        ld      (ix+NXD_LUN),a
        inc     hl
        ld      e,(hl)                  ; +6..+9 first device sector
        inc     hl
        ld      d,(hl)
        inc     hl
        push    de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        push    de
        ld      bc,9
        or      a
        sbc     hl,bc                   ; HL -> scratch again
        push    hl
        ld      d,(ix+NXD_SLOT)
        ld      e,0FFh                  ; a driver embedded in the kernel ROM
        xor     a                       ; by slot and segment, not by index
        ld      c,NX_GDRVR
        call    BDOS
        pop     hl
        or      a
        jr      nz,.pop2
        ld      bc,4
        add     hl,bc
        ld      a,(hl)                  ; +4 flags
        rlca                            ; bit 7: a Nextor driver
        ld      a,NXE_NOTNEXTOR
        jr      nc,.pop2
        ld      a,(hl)
        rrca                            ; bit 0: device-based
        ld      a,NXE_NOTDEVICE
        jr      nc,.pop2
        ; The ROM itself: read the driver's bank number, then check the
        ; header in that bank.
        push    ix
        ld      a,(ix+NXD_SLOT)
        ld      hl,4000h
        call    nx_enaslt
        pop     ix
        ei
        ld      a,(NX_K_SIZE)
        ld      (ix+NXD_BANK),a
        push    ix
        ld      a,(nx_ramslot1)
        ld      hl,4000h
        call    nx_enaslt
        pop     ix
        ei
        call    nx_enter
        ld      hl,NX_DRV_SIGN
        ld      de,nx_sign
        ld      b,NX_SIGN_LEN
.cmp:   ld      a,(de)
        cp      (hl)
        jr      nz,.nosign
        inc     hl
        inc     de
        djnz    .cmp
        ld      a,(NX_DRV_FLAGS)
        rrca
        ld      a,NXE_NOTDEVICE
        jr      nc,.leave
        xor     a
        jr      .leave
.nosign:
        ld      a,NXE_NOSIGN
.leave:
        push    af
        call    nx_leave
        pop     af
.pop2:
        pop     de                      ; high word
        pop     hl                      ; low word
.done:
        pop     ix
        ret

nx_sign:
        db      "NEXTOR_DRIVER",0
    ENDIF

; nx_rw — read or write device sectors through the driver's DEV_RW.
; In:  IX -> descriptor, Cy = 0 read / 1 write, B = sector count,
;      HL = buffer, DE -> 4-byte device sector number; neither in page 1.
; Out: A = the driver's error code (0 = ok), B = as DEV_RW returns it.
;      IX preserved; other registers, including IY and the alternates,
;      may be corrupted by the driver.
nx_rw:
        push    ix
        push    af
        push    bc
        push    de
        push    hl
        call    nx_enter
        pop     hl
        pop     de
        pop     bc
        pop     af
        ld      c,(ix+NXD_LUN)
        ld      a,(ix+NXD_DEV)
        call    NX_DEV_RW
        push    af
        push    bc
        call    nx_leave
        pop     bc
        pop     af
        pop     ix
        ret

; nx_enter — make the driver bank visible in page 1: the descriptor's slot
; through ENASLT, then its bank through CHGBNK, remembering the bank that
; was visible. Interrupts stay disabled from here until nx_leave's end, as
; they are when the kernel calls a driver: the kernel's timer hook switches
; banks through CHGBNK, and on the Sunrise IDE that write also turns the
; IDE registers off, so a tick landing inside DEV_RW breaks the transfer.
; In: IX -> descriptor. Preserves IX; corrupts AF, BC, DE, HL.
nx_enter:
        push    ix
        ld      a,(ix+NXD_SLOT)
        ld      hl,4000h
        call    nx_enaslt               ; returns with interrupts disabled
        pop     ix
        ld      a,(NX_CUR_BANK)
        ld      (nx_saved_bank),a
        ld      a,(ix+NXD_BANK)
        call    NX_CHGBNK
        ret

; nx_leave — undo nx_enter: the saved bank back, then RAM back in page 1,
; then interrupts on. Corrupts AF, BC, DE, HL.
nx_leave:
        ld      a,(nx_saved_bank)
        call    NX_CHGBNK
        ld      a,(nx_ramslot1)
        ld      hl,4000h
        call    nx_enaslt
        ei
        ret

nx_saved_bank:
        db      0
