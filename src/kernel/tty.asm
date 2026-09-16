; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The line discipline: read on the keyboard, in canonical mode, returns
; edited lines. A layer over the raw read of kbd.asm, taken when the
; terminal's mode is TTY_CANON — the default — and skipped, the raw read
; being what it always was, in TTY_RAW.
;
; The line is the terminal's, not the process's: one buffer, ld_buf, that
; a reader fills one key event at a time — blocking as the raw read
; blocks while the queue is empty — echoing every byte it keeps through
; con_write, until RET, ^D or a ^C nobody took closes it. Then the reader
; is handed min(BC, what is left) and the rest waits for the next read,
; so a program reading a byte at a time gets the line without blocking
; again. Editing: BS and DEL rub out one byte (BS SP BS), ^U the line,
; ^L (and SHIFT+HOME, the same byte) clears the screen and writes the
; line again at the top, after what its row held before it — the prompt;
; TAB is kept and echoed as con_write moves the cursor, every other
; control byte — arrows, HOME, ESC, F-keys — is dropped without echo. The
; line holds TTY_LINE-1 bytes; a printable past that is dropped. ^D on an
; empty line is a read of 0 bytes, once. The byte 03h, which the handler
; queues only when no process took the ^C, ends the line empty with an LF
; delivered: a shell at its prompt prints a fresh one.
;
; The user buffer and length ride in IX and IY across a block, as the raw
; read's do — the frame saves them, and con_write, vdp_t2 and kbd_pop
; leave them alone — so two readers blocked at once each keep their own.
; The mode is not the process's and nothing restores it at exit: the shell
; sets canonical before each prompt.

; tty_read — HL = the buffer, BC = the length, both non-zero (sys_read
; checks). Out: HL = bytes delivered, 1 to BC; 0 for ^D on an empty line.
; On the process's stack. Corrupts everything.
tty_read:
        push    hl
        pop     ix                      ; ix = the buffer
        push    bc
        pop     iy                      ; iy = the length
        ; Bytes left over from the last line go first.
        ld      a,(ld_len)
        ld      hl,ld_pos
        cp      (hl)
        jp      nz,.deliver
        ; None: an EOF owed?
        ld      a,(ld_eof)
        or      a
        jr      z,.build
        xor     a
        ld      (ld_eof),a
        ld      hl,0
        ret                             ; CF clear from or a
.build: xor     a
        ld      (ld_len),a
        ld      (ld_pos),a
        ld      a,(con_col)
        ld      (ld_col),a              ; where the line starts, for ^L
.loop:  ld      a,(kbd_count)
        or      a
        jr      nz,.have
        ; Block: the cursor on, the row out of the ring — then a last look
        ; at the queue with interrupts off, as the raw read does.
        call    tty_cursor_on
        di
        ld      a,(kbd_count)
        or      a
        jr      nz,.woken
        ld      hl,(k_cur)
        ld      (hl),PS_KBD
        ld      hl,k_kbwait
        inc     (hl)
        call    sched_unlink
        ld      hl,.loop                ; resume at the loop, the line kept
        push    hl
        push    af
        push    hl
        jp      sched_save_block        ; its ei is the load's
.ff:    ; ^L: the screen cleared, then the cells of the line's first row
        ; before ld_col — the prompt the reader wrote — and the line so
        ; far. That row is the cursor's less the rows the line's echo
        ; took, walked from ld_col the way con_write moves; a prompt
        ; longer than a row comes back as its last row only. Neither
        ; write scrolls, so con_linebuf, which a scroll uses, holds the
        ; prompt safely.
        ld      hl,ld_buf
        ld      a,(ld_len)
        ld      c,a
        ld      b,0
        push    hl
        push    bc                      ; the line, for the last write
        ld      a,(ld_col)
        ld      d,a                     ; d = the column
        ld      e,b                     ; e = the rows the echo took
        inc     c
        jr      .next
.walk:  ld      a,(hl)
        cp      9
        ld      a,d
        jr      nz,.char
        or      7                       ; TAB: the next stop, less one
.char:  inc     a
        cp      CON_COLS
        jr      c,.col
        inc     e                       ; past the row: the next one
        xor     a
.col:   ld      d,a
        inc     hl
.next:  dec     c
        jr      nz,.walk
        ld      a,(con_row)
        sub     e
        ld      c,b                     ; bc = the prompt's length, 0
        jr      c,.cls                  ; not on the screen: no prompt
        call    vdp_row_read            ; into con_linebuf
        ld      a,(ld_col)
        ld      c,a
        ld      b,0
.cls:   ld      a,12
        call    con_putc                ; BC kept
        ld      hl,con_linebuf
        call    con_write               ; nothing for a length of 0
        pop     bc
        pop     hl
        call    con_write
.again: jr      .loop
.woken: ei
.have:  call    kbd_pop                 ; a = the byte; CF: nothing from it
        jr      c,.loop
        cp      13
        jr      z,.ret
        cp      8
        jr      z,.bs
        cp      127
        jr      z,.bs
        cp      21                      ; ^U
        jr      z,.kill
        cp      12                      ; ^L
        jr      z,.ff
        cp      4                       ; ^D
        jr      z,.eof
        cp      3                       ; a ^C nobody took
        jr      z,.intr
        cp      9                       ; TAB: kept, con_write moves
        jr      z,.store
        cp      20h
        jr      c,.again                ; any other control: dropped
.store: push    af
        ld      a,(ld_len)
        cp      TTY_LINE-1
        jr      nc,.full
        ld      hl,ld_buf
        ld      e,a
        ld      d,0
        add     hl,de
        pop     af
        ld      (hl),a
        ld      hl,ld_len
        inc     (hl)
        call    con_putc                ; the echo
        jp      .loop
.full:  pop     af
        jp      .loop
.bs:    ld      a,(ld_len)
        or      a
        jp      z,.loop                 ; nothing to rub out
        dec     a
        ld      (ld_len),a
        call    tty_erase
        jp      .loop
.kill:  ld      a,(ld_len)
        or      a
        jp      z,.loop
.kloop: call    tty_erase
        ld      hl,ld_len
        dec     (hl)
        jr      nz,.kloop
        jp      .loop
.ret:   ld      a,(ld_len)
        cp      TTY_LINE-1
        jr      nc,.close               ; no room for the LF: without it
        ld      hl,ld_buf
        ld      e,a
        ld      d,0
        add     hl,de
        ld      (hl),10
        ld      hl,ld_len
        inc     (hl)
        ld      a,10
        call    con_putc
        jr      .close
.eof:   ld      a,(ld_len)
        or      a
        jr      nz,.close               ; mid-line: what is there, no LF
        call    tty_cursor_off
        ld      hl,0
        xor     a                       ; CF clear
        ret
.intr:  ld      a,10                    ; the line the handler emptied,
        ld      (ld_buf),a              ; delivered as an empty one
        ld      a,1
        ld      (ld_len),a
        ld      a,10
        call    con_putc
.close: xor     a
        ld      (ld_pos),a
.deliver:
        ; n = min(the length, what is left); copy; advance.
        ld      a,(ld_len)
        ld      hl,ld_pos
        sub     (hl)
        ld      c,a                     ; c = what is left, 1 to 127
        ld      a,iyh
        or      a
        jr      nz,.n                   ; 256 or more asked: all of it
        ld      a,iyl
        cp      c
        jr      nc,.n
        ld      c,a                     ; fewer asked than left
.n:     ld      a,(ld_pos)
        ld      e,a
        ld      d,0
        ld      hl,ld_buf
        add     hl,de
        push    ix
        pop     de
        ld      b,0
        push    bc
        ldir
        pop     bc
        ld      a,(ld_pos)
        add     a,c
        ld      (ld_pos),a
        ld      hl,ld_len
        cp      (hl)
        jr      nz,.done
        xor     a                       ; the line is spent
        ld      (ld_len),a
        ld      (ld_pos),a
.done:  push    bc
        call    tty_cursor_off
        pop     bc
        ld      l,c
        ld      h,0
        xor     a                       ; CF clear
        ret

; tty_erase — BS SP BS to the console: one byte rubbed out. Corrupts
; everything.
tty_erase:
        ld      hl,tty_bsseq
        ld      bc,3
        jp      con_write

; tty_cursor_on / tty_cursor_off — the cursor drawn while a reader waits,
; erased when it returns; as the raw read does, through con_shown.
; Corrupt everything.
tty_cursor_on:
        ld      a,(con_shown)
        or      a
        ret     nz
        inc     a
        ld      (con_shown),a
        ld      a,(con_row)
        ld      hl,con_col
        ld      c,(hl)
        jp      vdp_cursor_on
tty_cursor_off:
        ld      a,(con_shown)
        or      a
        ret     z
        xor     a
        ld      (con_shown),a
        ld      a,(con_row)
        ld      hl,con_col
        ld      c,(hl)
        jp      vdp_cursor_off

; sys_ttymode — SYS_TTYMODE: A = TTY_CANON or TTY_RAW. Out: L = the mode
; that was. EINVAL for anything else. The mode is the terminal's; a
; partial line stays in the buffer across a switch.
sys_ttymode:
        cp      TTY_RAW+1
        jr      nc,.inval
        ld      hl,tty_mode
        ld      l,(hl)
        ld      h,0
        ld      (tty_mode),a
        xor     a                       ; CF clear
        ret
.inval: ld      a,E_INVAL
        scf
        ret

tty_mode:       db TTY_CANON            ; the terminal's mode
ld_len:         db 0                    ; bytes in the line
ld_pos:         db 0                    ; of them, delivered already
ld_eof:         db 0                    ; a ^D on an empty line is owed
ld_col:         db 0                    ; the column the line started at
tty_bsseq:      db 8,32,8
ld_buf:         ds TTY_LINE             ; the line
