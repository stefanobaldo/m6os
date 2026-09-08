; Slot switching without the BIOS.
;
; k_enaslt does what the BIOS ENASLT does — select a slot, expanded or not,
; in the page an address falls in, and keep SLTTBL true so that code
; reading it (a Nextor driver's GWORK) keeps working. It runs from page 3,
; so it can switch pages 1 and 2 only: switching page 3 would remove the
; code, and switching page 0 would remove the stub below.
;
; The subslot register lives at FFFFh of the expanded slot, so to write it
; page 3 must show that slot for a few instructions. During those, page 3's
; RAM — this code and the stack — is not there. The write is therefore done
; by k_sslot_stub (sslot.asm), present at K_SSLOT in every page 0 the
; kernel runs with, which uses no stack and returns only after page 3 is
; RAM again.

; k_enaslt — A = slot id (E000SSPP), HL = an address in page 1 or 2.
; Returns with interrupts disabled. Corrupts AF, BC, DE, HL.
k_enaslt:
        di
        ld      c,a                     ; c = slot id
        ld      a,h
        rlca
        rlca
        and     3
        add     a,a                     ; a = 2 * page: the shift for this page
        ld      b,a
        ld      a,c
        and     3
        ld      e,a                     ; e = primary slot bits
        ld      a,c
        rrca
        rrca
        and     3
        ld      h,a                     ; h = subslot bits
        ld      d,3                     ; d = mask
        ld      a,b
        or      a
        jr      z,.placed
.shift: sla     e
        sla     d
        sla     h
        dec     a
        jr      nz,.shift
.placed:                                ; d, e, h are in the page's position
        bit     7,c
        jr      z,.primary
        push    de
        in      a,(0A8h)
        ld      b,a                     ; b = primary register, to restore
        and     3Fh
        ld      l,a
        ld      a,c
        and     3
        rrca
        rrca                            ; primary slot in page 3's bits
        or      l
        ld      e,a                     ; e = primary register with the target
                                        ;     slot in page 3
        ld      a,d
        cpl
        ld      d,a                     ; d = complemented mask
        call    K_SSLOT                 ; l = the new subslot register value
        ld      a,c
        and     3
        add     a,low B_SLTTBL          ; no carry: C5h + 3
        ld      e,a
        ld      d,high B_SLTTBL
        ld      a,l
        ld      (de),a                  ; SLTTBL[primary] = new value
        pop     de
.primary:
        in      a,(0A8h)
        ld      b,a
        ld      a,d
        cpl
        and     b
        or      e
        out     (0A8h),a
        ret

; k_sslot_stub — the image of the routine at K_SSLOT (sslot.asm, included
; by kernel.asm after this file and by the switched image on its own).
