; The console's VDP backend: TEXT2 on a V9938 — 80 columns, 24 rows.
;
; con.asm is the terminal and knows rows, columns and control codes; this
; file is the chip, and knows registers, VRAM addresses and timing. The
; contract between them is the vdp_* routines below and nothing else: a
; backend for another chip — TEXT1 on a TMS9918, say — is another file
; implementing the same names, chosen when the kernel is assembled. No
; call goes through a table: the per-character path pays no dispatch.
;
; The layout of VRAM is the kernel's own (kernel.inc): the name table at
; V_NAME, 80 bytes per row, which is where the BIOS keeps SCREEN 0's, so
; that the lines the loader printed are still there when the registers
; are reprogrammed; the blink table at V_BLINK, zero but for the cursor's
; bit; the font at V_PAT. The font is whatever the previous system had —
; the machine's own ROM font, loaded by its BIOS — found through the R#4
; that system wrote (its shadow, captured in the record) and moved to
; V_PAT if it is elsewhere, which it is after a 40-column SCREEN 0.
;
; Timing: consecutive data-port accesses are 30 T-states apart or more,
; above what the V9938 needs in text modes with the display on. The two
; bytes of an address go to the control port under di/ei, because the
; interrupt handler reads S#0 and that resets the port's byte latch;
; data-port accesses between two addresses need no such care.

; vdp_init — the ports from the record, the font, the registers, the
; blink table. Corrupts everything.
vdp_init:
        ld      a,(K_REC+KR_VDPWR)
        ld      (vdp_dat),a
        inc     a
        ld      (vdp_ctl),a
        ld      a,(K_REC+KR_VDPREG+4)   ; R#4: A16-A11 of the font
        and     3Fh
        cp      V_PAT>>11
        call    nz,vdp_move_font
        di
        ld      a,(vdp_ctl)
        ld      c,a
        ld      hl,vdp_regs
        ld      b,VDP_NREGS
.reg:   ld      a,(hl)
        inc     hl
        out     (c),a                   ; the value
        ld      a,(hl)
        inc     hl
        out     (c),a                   ; 80h + the register
        djnz    .reg
        ld      a,(K_REC+KR_VDPREG+7)   ; R#7: the colours the BIOS had
        out     (c),a
        ld      a,80h+7
        out     (c),a
        ld      a,(K_REC+KR_VDPREG+7)   ; R#12: the cursor's colours, the
        rrca                            ; inverse
        rrca
        rrca
        rrca
        out     (c),a
        ld      a,80h+12
        out     (c),a
        ld      a,(K_REC+KR_VDPREG+8)   ; R#8: the VRAM type bit, as the
        out     (c),a                   ; BIOS had it
        ld      a,80h+8
        out     (c),a
        ld      a,(K_REC+KR_VDPREG+9)   ; R#9: 192 lines, 50/60 Hz, as the
        out     (c),a                   ; BIOS had it
        ld      a,80h+9
        out     (c),a
        ld      a,70h                   ; R#1 last: display on, IE0, M1
        out     (c),a
        ld      a,80h+1
        out     (c),a
        ei
        ld      hl,V_BLINK              ; the blink table: all zero
        call    vdp_setwrt
        ld      a,(vdp_dat)
        ld      c,a
        ld      b,CON_ROWS*10
        xor     a
.blk:   out     (c),a
        nop
        djnz    .blk
        ret

vdp_regs:
        db      04h,80h+0               ; M4: TEXT2
        db      (V_NAME>>11)<<2|3,80h+2 ; name table
        db      (V_BLINK>>6)|7,80h+3    ; blink table, low bits set
        db      V_PAT>>11,80h+4         ; pattern table
        db      00h,80h+10              ; blink table's A16-A14
        db      22h,80h+13              ; blink 1/3 s on, 1/3 s off
        db      00h,80h+14              ; VRAM A16-A14
        db      00h,80h+15              ; S#0 is what IN reads
VDP_NREGS equ   ($-vdp_regs)/2

; vdp_move_font — A = the previous system's R#4: copy the 2048-byte font
; from where it says to V_PAT, 64 bytes at a time through con_linebuf.
; A16-A14 are ignored: no BIOS keeps SCREEN 0's font above 16K. Corrupts
; everything.
vdp_move_font:
        and     07h
        add     a,a
        add     a,a
        add     a,a
        ld      h,a
        ld      l,0                     ; hl = the source
        ld      de,V_PAT
        ld      b,2048/64
.chunk: push    bc
        push    de
        push    hl
        call    vdp_setrd
        ld      a,(vdp_dat)
        ld      c,a
        ld      b,64
        ld      hl,con_linebuf
.rd:    ini
        jr      nz,.rd
        pop     hl
        ld      bc,64
        add     hl,bc
        ex      (sp),hl                 ; hl = the destination, source saved
        call    vdp_setwrt
        ld      a,(vdp_dat)
        ld      c,a
        ld      b,64
        push    hl
        ld      hl,con_linebuf
.wr:    outi
        jr      nz,.wr
        pop     hl
        ld      bc,64
        add     hl,bc
        ex      de,hl                   ; de = the next destination
        pop     hl                      ; hl = the next source
        pop     bc
        djnz    .chunk
        ret

; vdp_setwrt / vdp_setrd — HL = VRAM address; the next data-port access
; goes there. Corrupts AF; preserves BC, DE, HL.
vdp_setwrt:
        push    bc
        ld      a,(vdp_ctl)
        ld      c,a
        di
        out     (c),l
        ld      a,h
        and     3Fh
        or      40h
        out     (c),a
        ei
        pop     bc
        ret
vdp_setrd:
        push    bc
        ld      a,(vdp_ctl)
        ld      c,a
        di
        out     (c),l
        ld      a,h
        and     3Fh
        out     (c),a
        ei
        pop     bc
        ret

; vdp_cell — A = row, C = column: HL = the cell's name-table address.
; Corrupts AF, DE; preserves BC.
vdp_cell:
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; row * 16
        ld      e,l
        ld      d,h
        add     hl,hl
        add     hl,hl                   ; row * 64
        add     hl,de                   ; row * 80
        ld      e,c
        ld      d,0
        add     hl,de
        ld      de,V_NAME
        add     hl,de
        ret

; vdp_row_write — A = row, C = column, HL -> bytes, B = count (1-80):
; the bytes into the row from that column. Corrupts everything.
vdp_row_write:
        push    hl
        push    bc
        call    vdp_cell
        call    vdp_setwrt
        pop     bc
        pop     hl
        ld      a,(vdp_dat)
        ld      c,a
.wr:    outi
        jr      nz,.wr
        ret

; vdp_row_read — A = row: the row into con_linebuf. Corrupts everything.
vdp_row_read:
        ld      c,0
        call    vdp_cell
        call    vdp_setrd
        ld      a,(vdp_dat)
        ld      c,a
        ld      b,CON_COLS
        ld      hl,con_linebuf
.rd:    ini
        jr      nz,.rd
        ret

; vdp_clear_rows — A = first row, B = count: spaces. Corrupts everything.
vdp_clear_rows:
        push    bc
        ld      c,0
        call    vdp_cell
        call    vdp_setwrt
        pop     de                      ; d = rows left
        ld      a,(vdp_dat)
        ld      c,a
.row:   ld      b,CON_COLS
        ld      a,' '
.clr:   out     (c),a
        nop
        djnz    .clr
        dec     d
        jr      nz,.row
        ret

; vdp_scroll — A = k, 1 to 23: rows k..23 to rows 0..23-k, one at a time
; through con_linebuf. The rows left at the bottom are not cleared: the
; caller does that. Corrupts everything.
vdp_scroll:
        ld      d,a                     ; d = the row read
        ld      e,0                     ; e = the row written
        ld      a,CON_ROWS
        sub     d
        ld      b,a                     ; b = rows to move
.row:   push    bc
        push    de
        ld      a,d
        call    vdp_row_read
        pop     de
        push    de
        ld      a,e
        ld      c,0
        ld      hl,con_linebuf
        ld      b,CON_COLS
        call    vdp_row_write
        pop     de
        pop     bc
        inc     d
        inc     e
        djnz    .row
        ret

; vdp_cursor_on / vdp_cursor_off — A = row, C = column: the cell's blink
; bit set, or cleared. One byte of the blink table, which holds nothing
; else. Corrupts everything.
vdp_cursor_on:
        call    vdp_blink_cell
        ld      a,80h
        jr      z,.out
.shift: rrca
        djnz    .shift
.out:   push    af
        call    vdp_setwrt
        pop     af
        push    af
        ld      a,(vdp_dat)
        ld      c,a
        pop     af
        out     (c),a
        ret
vdp_cursor_off:
        call    vdp_blink_cell
        call    vdp_setwrt
        ld      a,(vdp_dat)
        ld      c,a
        xor     a
        out     (c),a
        ret

; vdp_blink_cell — A = row, C = column: HL = the cell's byte in the blink
; table, B = the bit's index from the left (0-7), Z when it is 0.
vdp_blink_cell:
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      e,l
        ld      d,h
        add     hl,hl
        add     hl,hl
        add     hl,de                   ; row * 10
        ld      a,c
        rrca
        rrca
        rrca
        and     0Fh
        ld      e,a
        ld      d,0
        add     hl,de                   ; + column / 8
        ld      de,V_BLINK
        add     hl,de
        ld      a,c
        and     7
        ld      b,a
        ret

vdp_ctl:        db 0
vdp_dat:        db 0
