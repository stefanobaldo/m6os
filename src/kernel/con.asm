; The console: text output straight into VRAM.
;
; The screen is the text mode the previous system left — SCREEN 0, TEXT1
; (40 columns) or TEXT2 (80) — described by the capture record: name table
; base, bytes per row, columns and rows in use. Output resumes on the row
; that system's cursor was on. A character is one VRAM write at the cursor's
; address; a newline moves to the next row and scrolls the screen up by one
; row when it runs out, and the new row is cleared first, so what the
; previous system left there does not show through. No cursor is drawn and
; no control code but 10 is understood; programming the VDP, the cursor and the keyboard come with the
; full console driver.
;
; VDP access: the two-byte address write to the control port is wrapped in
; DI/EI because reading the status register — which the interrupt handler
; does — resets the VDP's first/second byte latch. Consecutive data-port
; accesses in the scroll loops are 30 T-states apart or more, above what the
; V9938 needs in text modes with the display on.
;
; Every byte written to the screen is also written to the debug device
; (ports 2Eh/2Fh, tests/m6test.inc), which openMSX turns into a transcript
; and real hardware ignores.

; con_init — take the screen geometry from the record, set the cursor under
; the previous system's last line. Corrupts AF, BC, DE, HL.
con_init:
        ld      a,(K_REC+KR_VDPWR)
        ld      (con_dat),a
        inc     a
        ld      (con_ctl),a
        ld      c,a
        xor     a
        out     (c),a                   ; R#14 = 0: VRAM addresses below 16K
        ld      a,80h+14
        out     (c),a
        ld      a,DBG_ASCII
        out     (DBG_MODE),a
        ld      a,(K_REC+KR_CSRY)
        dec     a                       ; 1-based to 0-based
        ld      b,a
        ld      a,(K_REC+KR_ROWS)
        dec     a
        cp      b
        jr      nc,.row
        ld      b,a                     ; never below the last row
.row:   ld      a,b
        ld      (con_row),a
        xor     a
        ld      (con_col),a
        ld      hl,(K_REC+KR_NAMBAS)
        ld      a,(K_REC+KR_STRIDE)
        ld      e,a
        ld      d,0
        ld      a,b
        or      a
        jr      z,.at
.mul:   add     hl,de
        dec     a
        jr      nz,.mul
.at:    ld      (con_line),hl
        ld      (con_addr),hl
        ret

; con_puts — HL -> 0-terminated string. Corrupts AF; preserves HL's string
; end in HL.
con_puts:
        ld      a,(hl)
        or      a
        ret     z
        call    con_putc
        inc     hl
        jr      con_puts

; con_putc — A = character; 10 is a newline. Preserves BC, DE, HL.
con_putc:
        cp      10
        jr      nz,.char
        out     (DBG_DATA),a
        jr      con_nl
.char:  push    hl
        push    bc
        push    af
        out     (DBG_DATA),a
        ld      hl,(con_addr)
        call    con_setwrt
        ld      a,(con_dat)
        ld      c,a
        pop     af
        out     (c),a
        inc     hl
        ld      (con_addr),hl
        ld      hl,con_col
        inc     (hl)
        ld      a,(K_REC+KR_COLS)
        cp      (hl)
        pop     bc
        pop     hl
        ret     nz
        ; The line is full: wrap. Not echoed to the debug device, whose
        ; transcript has no line width.
con_nl:
        push    hl
        push    de
        push    bc
        push    af
        xor     a
        ld      (con_col),a
        ld      a,(K_REC+KR_ROWS)
        dec     a
        ld      b,a
        ld      a,(con_row)
        cp      b
        jr      c,.down
        call    con_scroll              ; on the last row already
        jr      .set
.down:  inc     a
        ld      (con_row),a
        ld      hl,(con_line)
        ld      a,(K_REC+KR_STRIDE)
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (con_line),hl
.set:   ld      hl,(con_line)
        ld      (con_addr),hl
        call    con_clear_row           ; whatever was on this row is gone
        pop     af
        pop     bc
        pop     de
        pop     hl
        ret

; con_clear_row — HL = a row's name-table address: fill it with spaces.
; Preserves HL; corrupts AF, BC.
con_clear_row:
        call    con_setwrt
        ld      a,(con_dat)
        ld      c,a
        ld      a,(K_REC+KR_STRIDE)
        ld      b,a
        ld      a,' '
.clr:   out     (c),a
        nop
        djnz    .clr
        ret

; con_scroll — move rows 1..rows-1 up by one, clear the last row.
; Corrupts AF, BC, DE, HL.
con_scroll:
        ld      hl,(K_REC+KR_NAMBAS)    ; hl = destination row
        ld      a,(K_REC+KR_ROWS)
        dec     a
        ld      b,a
.row:   push    bc
        push    hl
        ld      a,(K_REC+KR_STRIDE)
        ld      e,a
        ld      d,0
        add     hl,de                   ; source: the row below
        call    con_setrd
        ld      a,(con_dat)
        ld      c,a
        ld      a,(K_REC+KR_STRIDE)
        ld      b,a
        ld      hl,con_linebuf
.rd:    ini
        jr      nz,.rd
        pop     hl
        push    hl
        call    con_setwrt
        ld      a,(con_dat)
        ld      c,a
        ld      a,(K_REC+KR_STRIDE)
        ld      b,a
        ld      hl,con_linebuf
.wr:    outi
        jr      nz,.wr
        pop     hl
        ld      a,(K_REC+KR_STRIDE)
        ld      e,a
        ld      d,0
        add     hl,de
        pop     bc
        djnz    .row
        jp      con_clear_row           ; hl = the last row

; con_setwrt / con_setrd — HL = VRAM address; the next data-port access
; goes there. Corrupts AF; preserves BC, DE, HL.
con_setwrt:
        push    bc
        ld      a,(con_ctl)
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
con_setrd:
        push    bc
        ld      a,(con_ctl)
        ld      c,a
        di
        out     (c),l
        ld      a,h
        and     3Fh
        out     (c),a
        ei
        pop     bc
        ret

; con_hex16 / con_hex8 — HL / A in hexadecimal. Preserve BC, DE, HL.
con_hex16:
        ld      a,h
        call    con_hex8
        ld      a,l
con_hex8:
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
        jp      c,con_putc
        add     a,'A'-'9'-1
        jp      con_putc

; con_dec16 — HL in decimal, no leading zeros. Corrupts AF, DE, HL.
con_dec16:
        xor     a
        ld      (con_lead),a
        ld      de,10000
        call    .digit
        ld      de,1000
        call    .digit
        ld      de,100
        call    .digit
        ld      de,10
        call    .digit
        ld      a,l
        add     a,'0'
        jp      con_putc
.digit: ld      a,'0'-1
.sub:   inc     a
        or      a
        sbc     hl,de
        jr      nc,.sub
        add     hl,de
        cp      '0'
        jr      nz,.emit
        push    af
        ld      a,(con_lead)
        or      a
        jr      nz,.zero
        pop     af
        ret
.zero:  pop     af
.emit:  ld      (con_lead),a            ; any non-zero value: digits have begun
        jp      con_putc

; con_hundredths — HL = a value in hundredths, printed as N.NN.
; Corrupts AF, BC, DE, HL.
con_hundredths:
        ld      de,100
        ld      bc,0
.div:   or      a
        sbc     hl,de
        jr      c,.rem
        inc     bc
        jr      .div
.rem:   add     hl,de                   ; hl = remainder, bc = quotient
        push    hl
        ld      h,b
        ld      l,c
        call    con_dec16
        ld      a,'.'
        call    con_putc
        pop     hl
        ld      a,l
        ld      b,'0'-1
.tens:  inc     b
        sub     10
        jr      nc,.tens
        add     a,10
        ld      c,a
        ld      a,b
        call    con_putc
        ld      a,c
        add     a,'0'
        jp      con_putc

con_ctl:        db 0
con_dat:        db 0
con_row:        db 0
con_col:        db 0
con_lead:       db 0
con_addr:       dw 0
con_line:       dw 0
con_linebuf:    ds 80
