; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The line discipline's editor: every key that changes the line or moves
; the cursor, entered from tty_read (tty.asm) through KS_TTY_KEY with the
; byte in A. The line's state — length, cursor, the column it started at,
; the bytes — is the resident's, reached through IX as LD_* lay it out;
; the console's cursor, row then column, through IY. The screen is
; written through the resident's console, which handles TAB and the wrap
; at CON_COLS; where a byte's cell is on the screen is computed here the
; same way (lt_pos), relative to the line's first row, and the cursor is
; put on a cell by writing the console's row and column (lt_place) —
; the console has no way back across a row boundary, and none is needed.
; An edit writes the line again from the cursor's cell and, when the line
; got shorter on the screen — a byte gone, or a TAB after it grown or
; shrunk — blanks the cells it no longer covers, up to where it ended
; before (lt_redraw). Nothing here blocks, and nothing is kept between
; calls but the state IX points at.

; ks_tty_key — A = the byte. IX -> the line's state, IY -> the console's
; cursor. Corrupts everything but IX, IY.
ks_tty_key:
        cp      7Fh
        jp      z,lt_del
        cp      20h
        jr      nc,lt_ins
        cp      9
        jr      z,lt_ins
        cp      8
        jp      z,lt_bs
        cp      1Dh
        jp      z,lt_left
        cp      1Ch
        jp      z,lt_right
        cp      0Bh
        jp      z,lt_home
        cp      1                       ; ^A
        jp      z,lt_home
        cp      5                       ; ^E
        jp      z,lt_end
        cp      15h                     ; ^U
        jp      z,lt_kill
        cp      0Ch                     ; ^L, and SHIFT+HOME
        jp      z,lt_ff
        ret                             ; any other control: dropped

; lt_ins — A = a printable or TAB: inserted at the cursor, the tail moved
; up one, the line written again from the cursor's cell. On the screen
; the line only grows — a TAB after the cursor gives a cell to the byte
; put before it, or jumps to the next stop — so nothing is blanked.
lt_ins:
        ld      b,a                     ; b = the byte
        ld      a,(ix+LD_LEN)
        cp      TTY_LINE-1
        ret     nc                      ; full: dropped
        ld      c,a                     ; c = len
        sub     (ix+LD_CUR)             ; the tail's length
        jr      z,.store
        push    bc
        push    ix
        pop     hl
        ld      d,0
        ld      e,c
        add     hl,de
        ld      de,LD_BUF
        add     hl,de                   ; hl -> buf[len]
        ld      d,h
        ld      e,l
        dec     hl                      ; hl -> buf[len-1]
        ld      c,a
        ld      b,0
        lddr                            ; buf[cur..len) up one
        pop     bc
.store: push    ix
        pop     hl
        ld      d,0
        ld      e,(ix+LD_CUR)
        add     hl,de
        ld      de,LD_BUF
        add     hl,de                   ; hl -> buf[cur]
        ld      (hl),b
        inc     (ix+LD_LEN)
        ld      c,(ix+LD_CUR)
        call    lt_write                ; from the cursor's cell
        ld      a,(ix+LD_LEN)
        call    lt_pos                  ; d = the rows the cursor is down
        ld      a,(ix+LD_CUR)
        inc     a
        jp      lt_place

; lt_bs — BS: the byte before the cursor removed; at 0, nothing.
lt_bs:  ld      a,(ix+LD_CUR)
        or      a
        ret     z
        dec     a
        call    lt_move                 ; the cursor one cell back first
        jr      lt_cut
; lt_del — DEL: the byte under the cursor removed; at the end, nothing.
lt_del: ld      a,(ix+LD_CUR)
        cp      (ix+LD_LEN)
        ret     z
; lt_cut — the byte under the cursor removed, the console's cursor at the
; cursor's cell: the tail moved down, written again from there, and the
; cells the line no longer covers blanked to where it ended before.
lt_cut: ld      a,(ix+LD_LEN)
        call    lt_pos                  ; de = the old end
        push    de
        dec     (ix+LD_LEN)
        ld      a,(ix+LD_LEN)
        sub     (ix+LD_CUR)             ; the tail after the byte
        jr      z,.moved
        ld      c,a
        push    ix
        pop     hl
        ld      d,0
        ld      e,(ix+LD_CUR)
        add     hl,de
        ld      de,LD_BUF
        add     hl,de                   ; hl -> buf[cur]
        ld      d,h
        ld      e,l
        inc     hl                      ; hl -> buf[cur+1]
        ld      b,0
        ldir
.moved: pop     de
        ld      c,(ix+LD_CUR)
        call    lt_redraw
        ld      a,(ix+LD_CUR)
        jp      lt_place

; lt_pos — A = an index: D = the rows below the line's first row and E =
; the column of that byte's cell, walked from ld_col the way con_write
; moves — a cell per byte, TAB to the next stop, wrapping at CON_COLS.
; Corrupts AF, BC, HL.
lt_pos: push    ix
        pop     hl
        ld      bc,LD_BUF
        add     hl,bc
        ld      c,a
        ld      e,(ix+LD_COL)
        ld      d,0
        inc     c
        jr      .next
.walk:  ld      a,(hl)
        cp      9
        ld      a,e
        jr      nz,.char
        or      7                       ; TAB: the next stop, less one
.char:  inc     a
        cp      CON_COLS
        jr      c,.col
        inc     d                       ; past the row: the next one
        xor     a
.col:   ld      e,a
        inc     hl
.next:  dec     c
        jr      nz,.walk
        ret

; lt_place — A = an index, D = the rows the console's cursor is below the
; line's first row now: the cursor put on that byte's cell — the console's
; row and column written — and ld_cur set. Corrupts AF, BC, DE, HL.
lt_place:
        ld      (ix+LD_CUR),a
        push    de
        call    lt_pos
        pop     bc                      ; b = the rows now
        ld      a,(iy+0)
        sub     b
        add     a,d
        ld      (iy+0),a
        ld      (iy+1),e
        ret

; lt_move — A = an index: the cursor there, from where it is.
lt_move:
        push    af
        ld      a,(ix+LD_CUR)
        call    lt_pos
        pop     af
        jr      lt_place

lt_left:
        ld      a,(ix+LD_CUR)
        or      a
        ret     z
        dec     a
        jr      lt_move
lt_right:
        ld      a,(ix+LD_CUR)
        cp      (ix+LD_LEN)
        ret     z
        inc     a
        jr      lt_move
lt_home:
        xor     a
        jr      lt_move
lt_end: ld      a,(ix+LD_LEN)
        jr      lt_move

; lt_write — C = an index, the console's cursor at its cell: buf[C..len)
; written. Corrupts everything.
lt_write:
        ld      a,(ix+LD_LEN)
        sub     c
        push    ix
        pop     hl
        ld      b,0
        add     hl,bc
        ld      bc,LD_BUF
        add     hl,bc                   ; hl -> buf[C]
        ld      c,a
        ld      b,0
        k_call  API_CON_WRITE           ; nothing for a length of 0
        ret

; lt_redraw — C = an index, DE = where the line ended before the edit,
; the console's cursor at C's cell: the tail written, then spaces up to
; the old end when the line got shorter. Out: D = the rows the console's
; cursor is down. Corrupts everything.
lt_redraw:
        push    de
        call    lt_write
        ld      a,(ix+LD_LEN)
        call    lt_pos                  ; de = the new end
        pop     bc                      ; bc = the old end
.blank: ld      a,d
        cp      b
        jr      c,.space
        ret     nz                      ; below the old end's row: done
        ld      a,e
        cp      c
        ret     nc
.space: ld      a,' '
        k_call  API_CON_PUTC            ; preserves BC, DE, HL
        inc     e
        ld      a,e
        cp      CON_COLS
        jr      c,.blank
        ld      e,0
        inc     d
        jr      .blank

; lt_kill — ^U: the line emptied, its cells blanked from the first.
lt_kill:
        ld      a,(ix+LD_LEN)
        or      a
        ret     z
        xor     a
        call    lt_move                 ; the cursor to the start
        ld      a,(ix+LD_LEN)
        call    lt_pos                  ; de = the old end
        ld      (ix+LD_LEN),0
        ld      c,0
        call    lt_redraw
        xor     a
        jp      lt_place

; lt_ff — ^L: the screen cleared, then the cells of the line's first row
; before ld_col — the prompt the reader wrote — and the line, written
; again at the top, the cursor on the cell it was on. The first row is
; the cursor's less the rows the line's echo took to the cursor; a
; prompt longer than a row comes back as its last row only. Neither
; write scrolls, so con_linebuf, which a scroll uses, holds the prompt
; safely.
lt_ff:  ld      a,(ix+LD_CUR)
        call    lt_pos
        ld      a,(iy+0)
        sub     d
        jr      c,.none                 ; not on the screen: no prompt
        k_call  API_ROW_READ            ; hl -> the row's cells
        ld      c,(ix+LD_COL)
        ld      b,0
        jr      .cls
.none:  ld      (ix+LD_COL),0           ; the line starts at the left
        ld      bc,0
.cls:   ld      a,12
        k_call  API_CON_PUTC            ; BC, HL kept
        k_call  API_CON_WRITE           ; the prompt; nothing for 0
        ld      c,0
        call    lt_write                ; the line
        ld      a,(ix+LD_LEN)
        call    lt_pos
        ld      a,(ix+LD_CUR)
        jp      lt_place
