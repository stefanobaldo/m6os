; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The kernel ROM's boot: what bank 0 runs at the slot scan and at H.RUNC
; (rom.asm includes this file after the page a driver calls into).
;
; At the slot scan, rom_init0 hooks H.RUNC with an inter-slot call to
; rom_runc and returns: nothing else, so a Nextor kernel ROM in a later
; slot hooks after it and boots Nextor, and one in an earlier slot is
; passed over — Nextor's own disable key, held at boot, is how a user
; chooses m6 over an internal kernel.
;
; At H.RUNC, with the BIOS in page 0, RAM in pages 2 and 3 and this slot in
; page 1 (bank 0: the trampoline selected it at INIT and nothing in the
; machine writes the register after that), rom_runc finds the RAM slot —
; page 3's, which the kernel takes as the primary mapper — and which
; segment page 3 shows, chooses three more for pages 0 to 2, and copies
; the routine below to page 2 and runs it from there, where switching the
; bank in page 1 costs nothing. That routine initialises the driver
; (DRV_INIT twice, as Nextor does: the work area's size, then the
; hardware), fills the takeover record — the BIOS half of the capture, the
; RAM slot, the segments, the current H.TIMI and FCALL, this slot's driver
; in bank K_SIZE — copies the switched image to page 1's segment, the boot
; image to KB_BASE in page 0's and the resident to C000h, gives page 1 to
; RAM and takes the machine over with ld_takeover (loader/takeover.asm,
; the image already in place).
;
; Up to the first copy a failure prints its code and returns from the
; hook: the BIOS goes on to BASIC with no disk system. The codes:
;   F3  the resident and its record do not fit under the wall
;   F4  no mapper segment answers in page 3's slot
;   F5  the driver wants more work area than RM_WORK_MAX
; From the first copy on there is no machine to return to; a failure
; after it is the kernel's, as in every boot mode.

RM_HRUNC        equ 0FECBh      ; H.RUNC: the BIOS, every INIT run
RM_RAMLOW       equ 0F380h      ; the BIOS work area's start: the driver's
                                ; work area ends here, and the wall is
                                ; where it begins
RM_WORK_MAX     equ RM_RAMLOW-K_IMAGE_ROOF  ; the most a driver may ask:
                                ; what keeps the wall above the roof the
                                ; build checks the resident against
RM_BOOT         equ 8000h       ; the routine's address in page 2
RM_STACK        equ 0C000h      ; its stack, down from page 2's end
RM_PROBE2       equ 8000h+(K_PROBE-K_BASE)  ; K_PROBE seen through page 2
; Eight bytes of page 3 under the resident's header, for what rom_runc
; learns before there is a page 2 of its own; the resident's copy lands on
; them last.
RM_TMP_JIFFY    equ K_BASE+16   ; 2: JIFFY on entry
RM_TMP_SP       equ K_BASE+18   ; 2: the BIOS's stack, for the way back
RM_TMP_SLOT     equ K_BASE+20   ; 1: this slot
RM_TMP_RAM      equ K_BASE+21   ; 1: the RAM slot
RM_TMP_SEG      equ K_BASE+22   ; 4: the segments for pages 0 to 3
RMC_FIT         equ 0F3h
RMC_NOSEG       equ 0F4h
RMC_WORK        equ 0F5h

; rom_init0 — INIT, in bank 0: hook H.RUNC. Corrupts AF, HL.
rom_init0:
        call    rom_gslt1
        ld      hl,RM_HRUNC
        ld      (hl),0F7h               ; RST 30h
        inc     hl
        ld      (hl),a                  ; this slot
        inc     hl
        ld      (hl),low rom_runc
        inc     hl
        ld      (hl),high rom_runc
        inc     hl
        ld      (hl),0C9h
        ret

; rom_runc — the hook. It unhooks itself first: the BIOS calls H.RUNC
; again on every RUN, NEW and CLEAR, and a boot that failed back to BASIC
; must not start over under a program.
rom_runc:
        ld      a,0C9h
        ld      (RM_HRUNC),a
        ld      hl,(B_JIFFY)            ; the boot's clock, before anything
        ld      (RM_TMP_JIFFY),hl
        ld      (RM_TMP_SP),sp
        call    rom_gslt1
        ld      (RM_TMP_SLOT),a
        ; Page 3's slot: the PPI's bits 7-6, SLTTBL's when expanded.
        in      a,(PPI_A)
        rlca
        rlca
        and     3
        ld      c,a
        ld      b,0
        ld      hl,B_EXPTBL
        add     hl,bc
        bit     7,(hl)
        jr      z,.plain
        ld      hl,B_SLTTBL
        add     hl,bc
        ld      a,(hl)
        rrca
        rrca
        rrca
        rrca
        and     0Ch
        or      c
        or      80h
        ld      c,a
.plain: ld      a,c
        ld      (RM_TMP_RAM),a
        ld      h,80h
        call    B_ENASLT                ; page 2 := the RAM slot; DI
        ei
        ; Page 3's segment: the one that shows K_PROBE's byte through
        ; page 2, and keeps showing it when the byte changes.
        ld      hl,RM_PROBE2
        ld      bc,0                    ; b: 256 tries; c: the segment
.probe: ld      a,0AAh
        ld      (K_PROBE),a
        ld      a,c
        out     (0FEh),a
        ld      a,(hl)
        cp      0AAh
        jr      nz,.next
        ld      a,55h
        ld      (K_PROBE),a
        ld      a,(hl)
        cp      55h
        jr      z,.found
.next:  inc     c
        djnz    .probe
        ld      a,1
        out     (0FEh),a                ; some segment, for BASIC
        ld      a,RMC_NOSEG
        jp      rom_fail
.found: ld      a,c
        ld      (RM_TMP_SEG+3),a
        ; The three lowest other segments: the highest to page 0, as the
        ; MSX-DOS 2 kernel lays them out.
        cp      3
        jr      c,.tab
        ld      a,3
.tab:   ld      l,a
        add     a,a
        add     a,l
        ld      l,a
        ld      h,0
        ld      de,rom_segtab
        add     hl,de
        ld      de,RM_TMP_SEG
        ld      bc,3
        ldir
        ; The routine into page 2's segment, and run from there.
        ld      a,(RM_TMP_SEG+2)
        out     (0FEh),a
        ld      hl,rom_boot
        ld      de,RM_BOOT
        ld      bc,rom_boot_end-rom_boot
        ldir
        jp      rm_start

rom_segtab:
        db      3,2,1, 3,2,0, 3,1,0, 2,1,0  ; pages 0-2, by page 3's segment

; rom_fail — A = the code: the line, then back to the BIOS through the
; hook's return. Bank 0 in page 1 and the BIOS in page 0, from either side
; of the relocation; page 2 shows one of the segments the boot chose, as
; good as the one it had, and the routine's first bytes there are cleared:
; BASIC's program text starts at 8000h, and an empty one is three zeros.
rom_fail:
        ld      hl,0
        ld      (RM_BOOT),hl
        ld      (RM_BOOT+1),hl
        push    af
        ld      hl,s_fail
        call    rom_puts
        pop     af
        call    rom_puthex8
        ld      hl,s_crlf
        call    rom_puts
        ld      sp,(RM_TMP_SP)
        ret

; rom_puts — HL -> a 0-terminated string, through the BIOS. Corrupts AF, HL.
rom_puts:
        ld      a,(hl)
        or      a
        ret     z
        call    B_CHPUT
        inc     hl
        jr      rom_puts

; rom_puthex16, rom_puthex8 — HL, A in hexadecimal. Corrupts AF.
rom_puthex16:
        ld      a,h
        call    rom_puthex8
        ld      a,l
rom_puthex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    .nib
        pop     af
.nib:   and     0Fh
        add     a,'0'
        cp      '9'+1
        jp      c,B_CHPUT
        add     a,'A'-'9'-1
        jp      B_CHPUT

s_banner:   db  "m6 ",M6_VERSION,13,10,0
s_fail:     db  "m6: boot failed, code ",0
s_timi:     db  "m6: driver timer hook not served",13,10,0
s_wall:     db  "wall ",0
s_drivers:  db  "h, drivers ",0
s_crlf:     db  13,10,0

        include "nextor/capbios.asm"

; ----------------------------------------------------------------------
; The routine that runs from page 2, assembled for RM_BOOT. From here the
; ROM in page 1 is data and the driver; nothing below returns to the BIOS
; but rom_fail, before the first copy.
rom_boot:
        DISP    RM_BOOT
rm_start:
        ld      sp,RM_STACK
        ; What rom_runc learned, into the record and the variables.
        ld      hl,(RM_TMP_JIFFY)
        ld      (rm_rec+KR_JIFFY),hl
        ld      a,(RM_TMP_SLOT)
        ld      (rm_slot),a
        ld      (rm_rec+KR_KSLOTS),a
        ld      (rm_rec+KR_DRVS),a      ; the driver's slot
        ld      a,(RM_TMP_RAM)
        ld      (rm_ram),a
        ld      (rm_rec+KR_MAPSLOT),a
        ld      hl,rm_rec+KR_RAMAD      ; RAMAD0-3: the one slot
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        ld      hl,RM_TMP_SEG
        ld      de,rm_rec+KR_SEG64K
        ld      bc,4
        ldir
        ld      hl,B_HTIMI              ; the hooks as they are: nothing
        ld      de,rm_rec+KR_TIMISAVE   ; has set them, the takeover
        ld      bc,5                    ; writes them back unchanged
        ldir
        ld      hl,B_FCALL
        ld      de,rm_rec+KR_FCALSAVE
        ld      bc,5
        ldir
        ld      a,(NX_K_SIZE)           ; the driver's bank, from the ROM
        ld      (rm_drvbank),a
        ld      (rm_rec+KR_DRVS+1),a
        ld      a,1
        ld      (rm_rec+KR_NDRV),a
        ld      hl,4000h                ; the switched image: page 1's
        ld      (rm_rec+KR_KSEG_SRC),hl ; segment, from its start
        ld      hl,rom_kseg_end-rom_kseg
        ld      (rm_rec+KR_KSEG_LEN),hl
        ld      hl,KB_BASE              ; the boot image: in place
        ld      (rm_rec+KR_BOOT_SRC),hl
        ld      hl,rom_kboot_end-rom_kboot
        ld      (rm_rec+KR_BOOT_LEN),hl
        ; The driver's first call: the work area's size, and whether it
        ; wants the timer hook, which m6 does not serve.
        ld      a,(rm_drvbank)
        call    NX_CHGBNK
        xor     a
        ld      bc,0                    ; no drive letters, no flags
        ld      hl,RM_WORK_MAX
        call    NX_DRV_INIT
        push    af
        push    hl
        xor     a
        call    NX_CHGBNK
        pop     bc                      ; bc = the size
        pop     af
        jr      nc,.notimi
        ld      hl,s_timi
        call    rom_puts
.notimi:
        ld      hl,RM_WORK_MAX
        or      a
        sbc     hl,bc
        ld      a,RMC_WORK
        jp      c,rom_fail
        ld      hl,RM_RAMLOW
        or      a
        sbc     hl,bc                   ; the wall: RAMLOW less the area
        ld      (rm_wall),hl
        ld      (rm_rec+KR_WALL),hl
        ld      de,(rom_resident+K_END-K_BASE)  ; the image's end
        or      a
        sbc     hl,de
        ld      a,RMC_FIT
        jp      c,rom_fail
        jp      z,rom_fail
        ; The work area, when there is one: cleared, and its address in
        ; this slot's SLTWRK entry, where GWORK leads the driver.
        ld      a,b
        or      c
        jr      z,.nowork
        ld      hl,(rm_wall)
        ld      (hl),0
        ld      d,h
        ld      e,l
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      z,.cleared
        ldir
.cleared:
        ld      a,(rm_slot)
        call    rom_gwork
        ld      hl,(rm_wall)
        ld      (ix+0),l
        ld      (ix+1),h
.nowork:
        ; The screen, the banner, then the driver's second call: the
        ; hardware, and its own lines. A driver may put the screen back to
        ; the RTC's settings (the Sunrise driver's MYSETSCR does when they
        ; differ); then 80 columns again, and the banner again, and its
        ; lines are lost on such a machine, as they are in every mode.
        call    ld_screen80
        ld      hl,s_banner
        call    rom_puts
        ld      a,(rm_drvbank)
        call    NX_CHGBNK
        ld      a,1
        ld      b,0
        call    NX_DRV_INIT
        xor     a
        call    NX_CHGBNK
        ei
        ld      a,(B_LINLEN)
        cp      80
        jr      z,.cols
        call    ld_screen80
        ld      hl,s_banner
        call    rom_puts
.cols:
        ld      ix,rm_rec
        call    nx_capture_bios
        ld      hl,s_wall
        call    rom_puts
        ld      hl,(rm_wall)
        call    rom_puthex16
        ld      hl,s_drivers
        call    rom_puts
        ld      a,(rm_rec+KR_NDRV)
        add     a,'0'
        call    B_CHPUT
        ld      hl,s_crlf
        call    rom_puts
        ; The copies. Page 0 goes to the RAM slot — the BIOS is gone from
        ; here, interrupts off — and shows, in turn, page 1's segment for
        ; the switched image (at 4000h once that segment is in page 1) and
        ; its own for the boot image; then the resident, from bank 0.
        di
        ld      a,(rm_ram)
        bit     7,a
        jr      z,.prim
        ld      a,(rm_ram)              ; the RAM slot's subslot register
        rrca                            ; (page 3 shows that slot): page
        rrca                            ; 0's field only, page 1 still
        and     3                       ; shows the ROM, which may be
        ld      b,a                     ; behind the same register
        ld      a,(0FFFFh)
        cpl
        and     0FCh
        or      b
        ld      (0FFFFh),a
        ld      a,(rm_ram)
.prim:  and     3
        ld      c,a
        in      a,(PPI_A)
        and     0FCh
        or      c
        out     (PPI_A),a               ; page 0 := RAM
        ld      a,(rm_rec+KR_SEG64K+1)
        out     (0FCh),a
        ld      a,ROM_KSEG_BANK
        call    NX_CHGBNK
        ld      hl,ROM_HEAD
        ld      de,0
        ld      bc,rom_kseg_end-rom_kseg
        ldir
        ld      a,(rm_rec+KR_SEG64K+0)
        out     (0FCh),a
        ld      a,ROM_KBOOT_BANK
        call    NX_CHGBNK
        ld      hl,ROM_HEAD
        ld      de,KB_BASE
        ld      bc,rom_kboot_end-rom_kboot
        ldir
        xor     a
        call    NX_CHGBNK
        ld      hl,rom_resident
        ld      de,K_BASE
        ld      bc,rom_resident_end-rom_resident
        ldir
        ; Page 1 to RAM, its segment in: the ROM is gone.
        ld      a,(rm_rec+KR_SEG64K+1)
        out     (0FDh),a
        ld      a,(rm_ram)
        bit     7,a
        jr      z,.prim1
        and     0Ch                     ; page 1's subslot field
        ld      b,a
        ld      a,(0FFFFh)
        cpl
        and     0F3h
        or      b
        ld      (0FFFFh),a
        ld      a,(rm_ram)
.prim1: and     3
        rlca
        rlca
        ld      c,a
        in      a,(PPI_A)
        and     0F3h
        or      c
        out     (PPI_A),a
        call    ld_takeover             ; returns only if it does not fit,
.halt:  di                              ; which was checked above
        halt
        jr      .halt

ld_image        equ K_BASE              ; the resident, already in place
ld_rec          equ rm_rec
ld_block        equ 0
ld_block_len    equ 0
        DEFINE  LD_IMAGE_IN_PLACE
        include "loader/takeover.asm"

rm_slot:    db  0                       ; this slot
rm_ram:     db  0                       ; the RAM slot
rm_drvbank: db  0                       ; the driver's bank
rm_wall:    dw  0
rm_rec:     ds  KREC_SIZE               ; the record, zero in the ROM
        ENT
rom_boot_end:
        ASSERT  rom_boot_end-rom_boot <= 1000h
