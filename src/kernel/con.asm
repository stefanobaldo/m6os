; The console: a terminal of 80 columns and 24 rows over the VDP backend
; (vdp_t2.asm), which is the only thing here that knows the chip.
;
; What it understands: printable bytes (20h and above), which go to the
; cell under the cursor and advance it, wrapping at column 80; and the C0
; controls BS (8), TAB (9, stops every 8), LF (10, next row and column 0),
; FF (12, clear and home), CR (13, column 0). Every other byte below 20h
; is ignored. No escape sequences.
;
; A write is done in two passes. The first walks the bytes without
; touching the screen, only to learn where the cursor ends up — and so
; how many rows, k, the whole write scrolls — echoing every byte to the
; debug device on the way. The screen then scrolls once, by k, and the
; second pass writes the bytes: those that land on rows scrolled off the
; top only move the cursor; the rest go to VRAM a run at a time, one
; address set per run. Output that arrives many lines at once — a listing,
; a file — thus pays one scroll instead of one per line, which is the
; difference between a screen that keeps up and one that does not.
;
; The cursor is drawn only while a process is blocked in read (kbd.asm),
; and erased by the first write after it: output never pays for it.

; con_init — the backend up, the cursor under the loader's last line if
; the record says the screen is already 80 columns at the kernel's name
; table, else a cleared screen. Corrupts everything.
con_init:
        call    vdp_init
        ld      a,DBG_ASCII
        out     (DBG_MODE),a
        xor     a
        ld      (con_col),a
        ld      (con_shown),a
        ld      a,(K_REC+KR_STRIDE)
        cp      CON_COLS
        jr      nz,.clear
        ld      hl,(K_REC+KR_NAMBAS)
        ld      de,V_NAME
        or      a
        sbc     hl,de
        jr      nz,.clear
        ld      a,(K_REC+KR_CSRY)
        dec     a                       ; 1-based to 0-based
        cp      CON_ROWS
        jr      c,.row
        ld      a,CON_ROWS-1            ; never below the last row
.row:   ld      (con_row),a
        ret
.clear: xor     a
        ld      b,CON_ROWS
        call    vdp_clear_rows
        xor     a
        ld      (con_row),a
        ret

; con_write — HL -> bytes, BC = count. Corrupts everything.
con_write:
        ld      a,b
        or      c
        ret     z
        ld      (cw_ptr),hl
        ld      (cw_rem),bc
        ld      a,(con_shown)           ; the cursor off, at its old place
        or      a
        jr      z,.pass1
        xor     a
        ld      (con_shown),a
        ld      a,(con_row)
        ld      hl,con_col
        ld      c,(hl)
        call    vdp_cursor_off
.pass1: ; Pass 1: simulate, echo, find the end row and the last FF.
        xor     a
        ld      (cw_cut+1),a
        ld      (cw_cut),a              ; no cut
        ld      a,(con_row)
        ld      (cw_row0),a
        ld      l,a
        ld      h,0
        ld      (cw_row),hl
        ld      a,(con_col)
        ld      (cw_col),a
        ld      hl,(cw_ptr)
        ld      bc,(cw_rem)
.s1:    ld      a,(hl)
        out     (DBG_DATA),a
        cp      20h
        jr      c,.ctl1
        call    cw_advance
.n1:    inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.s1
        jr      .scroll
.ctl1:  cp      12
        jr      nz,.notff
        inc     hl                      ; the cut: pass 2 starts here
        ld      (cw_cut),hl
        dec     hl
        push    hl
        ld      hl,0
        ld      (cw_row),hl
        ld      a,l
        ld      (cw_col),a
        ld      (cw_row0),a
        pop     hl
        jr      .n1
.notff: call    cw_control
        jr      .n1
.scroll:
        ; k = end row - 23, or 0; then the scroll, or the clear.
        ld      hl,(cw_row)
        ld      de,CON_ROWS-1
        or      a
        sbc     hl,de                   ; hl = k, signed
        jp      m,.zero
        ld      a,h
        or      l
        jr      nz,.k
.zero:  ld      hl,0
.k:     ld      (cw_k),hl
        ld      de,(cw_cut)
        ld      a,d
        or      e
        jr      nz,.all                 ; a cut: the screen is cleared, once
        ld      a,h
        or      a
        jr      nz,.all                 ; k >= 256: everything goes
        ld      a,l
        or      a
        jr      z,.start                ; k = 0: nothing moves
        cp      CON_ROWS
        jr      nc,.all
        push    af
        call    vdp_scroll
        pop     af
        ld      b,a
        ld      a,CON_ROWS
        sub     b
        call    vdp_clear_rows          ; rows 24-k..23
        jr      .start
.all:   xor     a
        ld      b,CON_ROWS
        call    vdp_clear_rows
.start:
        ; The start row: row0 - k, possibly negative; the start pointer.
        ld      a,(cw_row0)
        ld      l,a
        ld      h,0
        ld      de,(cw_k)
        or      a
        sbc     hl,de
        ld      (cw_row),hl
        ld      hl,(cw_cut)
        ld      a,h
        or      l
        jr      z,.from0
        ; From the cut: the bytes after it.
        ld      de,(cw_ptr)
        or      a
        sbc     hl,de                   ; hl = bytes before the cut
        ex      de,hl
        ld      hl,(cw_rem)
        or      a
        sbc     hl,de
        ld      (cw_rem),hl             ; bytes from the cut
        ld      hl,(cw_cut)
        ld      (cw_ptr),hl
        xor     a
        ld      (cw_col),a
        jr      .pass2
.from0: ld      a,(con_col)
        ld      (cw_col),a
.pass2: ; Pass 2: write. A run of printable bytes on a visible row is one
        ; vdp_row_write.
        ld      hl,(cw_rem)
        ld      a,h
        or      l
        jr      z,.done
.s2:    ld      hl,(cw_ptr)
        ld      a,(hl)
        cp      20h
        jr      c,.ctl2
        ld      a,(cw_row+1)
        or      a
        jp      m,.hidden               ; a row above the screen: move only
        ; The run: from cw_ptr, while printable, while the row lasts,
        ; while bytes last.
        ld      a,(cw_col)
        ld      c,a                     ; c = the column it starts at
        ld      b,0                     ; b = its length
        ld      de,(cw_rem)
.run:   ld      a,(hl)
        cp      20h
        jr      c,.runend
        inc     b
        inc     hl
        dec     de
        ld      a,c
        add     a,b
        cp      CON_COLS
        jr      z,.runend               ; the row is full
        ld      a,d
        or      e
        jr      nz,.run
.runend:
        push    bc
        push    de
        push    hl
        ld      a,(cw_row)
        ld      hl,(cw_ptr)
        call    vdp_row_write           ; a = row, c = column, b = count
        pop     hl
        ld      (cw_ptr),hl
        pop     de
        ld      (cw_rem),de
        pop     bc
        ld      a,c
        add     a,b
        ld      (cw_col),a
        cp      CON_COLS
        jr      nz,.more
        xor     a                       ; wrap
        ld      (cw_col),a
        ld      hl,(cw_row)
        inc     hl
        ld      (cw_row),hl
.more:  ld      hl,(cw_rem)
        ld      a,h
        or      l
        jr      nz,.s2
        jr      .done
.hidden:
        call    cw_advance
        jr      .next2
.ctl2:  cp      12
        jr      z,.next2                ; the FF was done in pass 1
        call    cw_control
.next2: ld      hl,(cw_ptr)
        inc     hl
        ld      (cw_ptr),hl
        ld      hl,(cw_rem)
        dec     hl
        ld      (cw_rem),hl
        ld      a,h
        or      l
        jr      nz,.s2
.done:  ld      a,(cw_row)
        ld      (con_row),a
        ld      a,(cw_col)
        ld      (con_col),a
        ret

; cw_advance — one printable byte: the column on, wrapping to the next
; row. Preserves BC, HL; corrupts AF, DE.
cw_advance:
        ld      a,(cw_col)
        inc     a
        cp      CON_COLS
        jr      nz,.col
        ex      de,hl
        ld      hl,(cw_row)
        inc     hl
        ld      (cw_row),hl
        ex      de,hl
        xor     a
.col:   ld      (cw_col),a
        ret

; cw_control — A = a control byte other than FF: the cursor as it says.
; Preserves BC, HL; corrupts AF, DE.
cw_control:
        cp      10
        jr      z,.lf
        cp      13
        jr      z,.cr
        cp      8
        jr      z,.bs
        cp      9
        ret     nz                      ; ignored
        ld      a,(cw_col)              ; TAB: the next stop
        or      7
        inc     a
        cp      CON_COLS
        jr      c,.col
.lf:    ex      de,hl
        ld      hl,(cw_row)
        inc     hl
        ld      (cw_row),hl
        ex      de,hl
.cr:    xor     a
.col:   ld      (cw_col),a
        ret
.bs:    ld      a,(cw_col)
        or      a
        ret     z
        dec     a
        ld      (cw_col),a
        ret

; con_puts — HL -> 0-terminated string. Corrupts AF; returns HL at the
; string's end; preserves BC, DE.
con_puts:
        push    bc
        push    de
        push    hl
        ld      bc,0
.len:   ld      a,(hl)
        or      a
        jr      z,.write
        inc     hl
        inc     bc
        jr      .len
.write: pop     hl
        push    hl
        call    con_write
        pop     hl
        pop     de
        pop     bc
        ; HL to the end: the length again, cheaply.
        xor     a
.end:   cp      (hl)
        ret     z
        inc     hl
        jr      .end

; con_putc — A = character. Preserves BC, DE, HL.
con_putc:
        push    hl
        push    de
        push    bc
        ld      (con_chbuf),a
        ld      hl,con_chbuf
        ld      bc,1
        call    con_write
        pop     bc
        pop     de
        pop     hl
        ret

; con_newline — a newline. Preserves BC, DE, HL.
con_newline:
        ld      a,10
        jp      con_putc

; con_dec8 — A in decimal. Corrupts AF, DE, HL.
con_dec8:
        ld      l,a
        ld      h,0
        jp      con_dec16

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

con_row:        db 0            ; the cursor, 0-based
con_col:        db 0
con_shown:      db 0            ; the cursor is drawn (a read is blocked)
con_lead:       db 0
con_chbuf:      db 0
cw_ptr:         dw 0            ; con_write: the next byte
cw_rem:         dw 0            ;   bytes left
cw_row:         dw 0            ;   the simulated row, signed
cw_col:         db 0            ;   the simulated column
cw_row0:        db 0            ;   the row the write started on
cw_k:           dw 0            ;   rows scrolled
cw_cut:         dw 0            ;   the byte after the last FF, or 0
con_linebuf:    ds 80
