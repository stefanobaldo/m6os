; The loader's side of the contract: what a program started by Nextor does
; to hand the machine to the resident. Two routines, with no dependency on
; the program beyond four assembly-time symbols it defines before including
; this file:
;
;   ld_image      where the resident image (build/kernel.bin) sits in the
;                 program
;   ld_rec        the KREC_SIZE-byte record the program has filled
;   ld_block      a block to copy to K_END, above the image — the program's
;                 own code to run once the kernel has booted, entered
;                 through KR_TEST
;   ld_block_len  its length, 0 for none
;
; Both expect a stack outside page 3 (the DOS stack sits under DOSHIM,
; which the takeover overwrites) and interrupts enabled on entry.

LD_DOSVER       equ 6Fh         ; MSX-DOS 2 _DOSVER

; ld_screen80 — SCREEN 0 at 80 columns, through the BIOS, before the
; capture: the name table is then where the resident's console keeps it,
; 80 bytes per row, and the lines printed from here on stay on screen when
; the resident reprograms the VDP. Corrupts everything.
ld_screen80:
        ld      a,80
        ld      (B_LINL40),a
        ld      ix,B_INITXT
        ld      iy,(B_EXPTBL-1)
        jp      B_CALSLT

; ld_nextor2 — is this a Nextor 2 kernel? Out: A = 0 and IX/IY as _DOSVER
; returns them (IYh.IYl the version) if so; else A = 0F0h (not MSX-DOS 2),
; 0F1h (MSX-DOS 2, not Nextor) or 0F2h (Nextor, not a 2.x kernel), NZ.
; Corrupts everything.
ld_nextor2:
        ld      c,LD_DOSVER
        ld      b,5Ah
        ld      hl,1234h
        ld      de,0ABCDh
        ld      ix,0
        call    BDOS
        or      a
        ret     nz
        ld      a,b
        cp      2
        ld      a,0F0h
        ret     c
        ld      a,ixh
        cp      1
        ld      a,0F1h
        ret     nz
        ld      a,ixl
        cp      2
        ld      a,0F2h
        ret     nz
        xor     a
        ret

; ld_takeover — take the machine. Returns only if the image and the block
; do not fit below the wall: A = 0F3h, NZ, nothing written. Otherwise:
; the cursor row into the record; interrupts off; the hooks Nextor set
; restored from the record; the image copied to K_BASE, the block to K_END,
; the record into K_REC; 55h from the block's end to the wall; the subslot
; stub and the interrupt vector into page 0; the stack at K_END; K_ENTRY.
ld_takeover:
        ld      hl,(ld_image+K_END-K_BASE)  ; the image's end, from its header
        ld      de,ld_block_len
        add     hl,de                   ; the block's end
        ex      de,hl
        ld      hl,(ld_rec+KR_WALL)
        or      a
        sbc     hl,de                   ; wall - end
        ld      a,0F3h
        ret     c
        ret     z
        ld      a,(B_CSRY)              ; where the screen output stands now
        ld      (ld_rec+KR_CSRY),a
        di
        ld      hl,ld_rec+KR_TIMISAVE   ; the hooks as they were before Nextor
        ld      de,B_HTIMI
        ld      bc,5
        ldir
        ld      hl,ld_rec+KR_FCALSAVE
        ld      de,B_FCALL
        ld      bc,5
        ldir
        ld      hl,(ld_image+K_END-K_BASE)
        ld      de,K_BASE
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; bc = the image's length
        ld      hl,ld_image             ; the resident
        ld      de,K_BASE
        ldir
        ld      bc,ld_block_len
        ld      a,b
        or      c
        jr      z,.noblock
        ld      hl,ld_block             ; the program's block above it
        ld      de,(K_END)
        ldir
.noblock:
        ld      hl,ld_rec               ; the record into the image
        ld      de,K_REC
        ld      bc,KREC_SIZE
        ldir
        ld      hl,(K_END)              ; 55h from the block's end to the wall
        ld      de,ld_block_len
        add     hl,de
        ex      de,hl                   ; de = the first byte to fill
        ld      hl,(K_REC+KR_WALL)
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l                     ; bc = bytes to fill, > 0 as checked
        ex      de,hl                   ; hl = the first byte
        ld      (hl),55h
        dec     bc
        ld      a,b
        or      c
        jr      z,.filled
        ld      d,h
        ld      e,l
        inc     de
        ldir
.filled:
        ld      hl,(K_STUB)             ; the subslot stub into page 0
        ld      de,K_SSLOT
        ld      bc,K_SSLOT_LEN
        ldir
        ld      a,0C3h                  ; the interrupt vector
        ld      (K_INTRPT),a
        ld      hl,K_ISR
        ld      (K_INTRPT+1),hl
        ld      sp,(K_END)
        jp      K_ENTRY
