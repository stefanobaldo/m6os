; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The line discipline: read on the keyboard, in canonical mode, returns
; edited lines. A layer over the raw read of kbd.asm, taken when the
; terminal's mode is TTY_CANON — the default — or TTY_RECALL, and
; skipped, the raw read being what it always was, in TTY_RAW.
;
; The line is the terminal's, not the process's: one buffer, ld_buf, that
; a reader fills one key event at a time — blocking as the raw read
; blocks while the queue is empty — until RET, ^D or a ^C nobody took
; closes it. Then the reader is handed min(BC, what is left) and the rest
; waits for the next read, so a program reading a byte at a time gets the
; line without blocking again. Every other key is the editor's, and the
; editor is in the switched part of the kernel (ks_tty.asm): a keystroke
; is the coldest path there is, and the page switch it costs — ~60 µs —
; is nothing beside a key's own latency. The editor keeps a cursor,
; ld_cur, inside the line: printables and TAB are inserted at it, BS and
; DEL rub out beside it, the arrows, HOME, ^A and ^E move it, ^U empties
; the line, ^L (and SHIFT+HOME, the same byte) clears the screen and
; writes the prompt and the line again at the top; every other control
; byte is dropped without echo. The line holds TTY_LINE-1 bytes; a byte
; past that is dropped. ^D on an empty line is a read of 0 bytes, once.
; The byte 03h, which the handler queues only when no process took the
; ^C, ends the line empty with an LF delivered: a shell at its prompt
; prints a fresh one.
;
; TTY_RECALL is canonical mode for a program that keeps a history — the
; shell: UP and DOWN, dropped in TTY_CANON, end the read with two bytes
; handed to the reader — the arrow's own byte and an LF — and the line
; kept open: its bytes, cursor and echo stay, and the next read goes on
; editing it instead of starting one. ttyline replaces an open line, or
; opens one, with the bytes the caller gives: the old line's cells
; blanked, the new line echoed, the cursor at its end. So the shell reads
; the arrow, looks the line up and puts it in place with ttyline, and
; reads again. A line closes as any other; ttymode drops an open line.
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
        ld      a,(ld_open)
        or      a
        jp      nz,.loop                ; an open line: go on with it
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
        ld      (ld_cur),a
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
.woken: ei
.have:  call    kbd_pop                 ; a = the byte; CF: nothing from it
        jr      c,.loop
        cp      13
        jr      z,.ret
        cp      4                       ; ^D
        jr      z,.eof
        cp      3                       ; a ^C nobody took
        jr      z,.intr
        cp      1Eh                     ; UP
        jr      z,.arrow
        cp      1Fh                     ; DOWN
        jr      z,.arrow
.edit:  ld      hl,KS_TTY_KEY           ; everything else: the editor's
        call    tty_ks
        jr      .loop
.arrow: ld      hl,tty_mode
        bit     1,(hl)                  ; TTY_RECALL
        jr      z,.edit                 ; not asked for: the editor drops it
        ld      (ld_key),a
        ld      a,1
        ld      (ld_open),a
        ; The arrow and an LF, from ld_key, not the line: n = min(the
        ; length, 2); a reader asking for one byte gets the arrow alone.
        ld      c,2
        ld      a,iyh
        or      a
        jr      nz,.keyn
        ld      a,iyl
        cp      2
        jr      nc,.keyn
        ld      c,1
.keyn:  ld      hl,ld_key
        push    ix
        pop     de
        ld      b,0
        push    bc
        ldir
        pop     bc
        jp      .done
.ret:   call    tty_end
        ld      a,(ld_len)
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
        jr      nz,.mid
        call    tty_cursor_off
        ld      hl,0
        xor     a                       ; CF clear
        ld      (ld_open),a
        ret
.mid:   call    tty_end                 ; mid-line: what is there, no LF
        jr      .close
.intr:  call    tty_end
        ld      a,10                    ; the line the handler emptied,
        ld      (ld_buf),a              ; delivered as an empty one
        ld      a,1
        ld      (ld_len),a
        ld      a,10
        call    con_putc
.close: xor     a
        ld      (ld_pos),a
        ld      (ld_open),a
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

; tty_end — the cursor to the line's end, when it is not there: what a
; key that closes the line does first, so that the LF, or the program's
; output, starts after the line and not inside it. Corrupts everything
; but IX, IY.
tty_end:
        ld      a,(ld_cur)
        ld      hl,ld_len
        cp      (hl)
        ret     z
        ld      a,5                     ; ^E
        ld      hl,KS_TTY_KEY
; tty_ks — HL = an entry of the switched part, A = its argument: the
; call, the way k_switched makes one — the stack moved to k_sstack, since
; the process's may be in page 2, and the window in — with the line's
; state in IX and the console's cursor in IY for the callee, and the
; caller's IX and IY kept. k_usp is free here: sys_read on the keyboard
; is resident, never entered through the gate. The switch a tick may have
; marked as owed inside is paid at the read's return, as for any tick
; that lands in the loop. Corrupts everything but IX, IY.
tty_ks:
        push    ix
        push    iy
        ld      (k_usp),sp
        ld      sp,k_sstack
        ld      ix,ld_state
        ld      iy,con_row
        kwin_enter
        call    .go
        kwin_leave
        ld      sp,(k_usp)
        pop     iy
        pop     ix
        ret
.go:    jp      (hl)

; tty_row_read — A = a row: API_ROW_READ, the row into con_linebuf and
; HL -> it, for the editor's ^L. Corrupts everything.
tty_row_read:
        call    vdp_row_read
        ld      hl,con_linebuf
        ret

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

; sys_ttymode — SYS_TTYMODE: A = TTY_CANON, TTY_RAW or TTY_RECALL. Out:
; L = the mode that was. EINVAL for anything else. The mode is the
; terminal's; a line delivered in part stays in the buffer across a
; switch, an open line is dropped.
sys_ttymode:
        cp      TTY_RECALL+1
        jr      nc,.inval
        ld      hl,tty_mode
        ld      l,(hl)
        ld      h,0
        ld      (tty_mode),a
        ld      a,(ld_open)
        or      a
        jr      z,.set
        xor     a
        ld      (ld_open),a
        ld      (ld_len),a
        ld      (ld_pos),a
.set:   xor     a                       ; CF clear
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; sys_ttyline — SYS_TTYLINE: HL = a line, BC = its length, 0 to
; TTY_LINE-1. The open line replaced by it, or one opened at the cursor:
; the old line's cells blanked, the bytes copied, echoed, the cursor at
; their end. EINVAL for a longer one, EFAULT for a buffer reaching page 3
; (process 0's may be anywhere), both before anything is touched. The
; copy is resident — the caller's buffer may be in page 2, which the
; switched part takes — around two calls into the editor. Corrupts
; everything. Its EINVAL exit is sys_ttymode's.
sys_ttyline:
        ld      a,b
        or      a
        jr      nz,sys_ttymode.inval
        ld      a,c
        cp      TTY_LINE
        jr      nc,sys_ttymode.inval
        call    k_ubuf
        jp      c,pi_fault              ; refused, not written through
        push    hl
        push    bc
        ld      a,(ld_open)
        or      a
        jr      nz,.open
        xor     a                       ; nothing open: a line at the cursor
        ld      (ld_len),a
        ld      (ld_pos),a
        ld      (ld_cur),a
        ld      a,(con_col)
        ld      (ld_col),a
        ld      a,1
        ld      (ld_open),a
.open:  ld      a,15h                   ; ^U: the old line's cells blanked
        ld      hl,KS_TTY_KEY
        call    tty_ks
        pop     bc
        pop     hl
        ld      a,c
        ld      (ld_len),a
        ld      de,ld_buf
        or      a
        jr      z,.set
        ldir
.set:   ld      hl,KS_TTY_SET
        call    tty_ks
        xor     a                       ; CF clear
        ret

tty_mode:       db TTY_CANON            ; the terminal's mode
; The line's state, laid out as LD_* in kernel.inc say: the editor in the
; switched part reaches it through IX.
ld_state:
ld_len:         db 0                    ; bytes in the line
ld_pos:         db 0                    ; of them, delivered already
ld_eof:         db 0                    ; a ^D on an empty line is owed
ld_col:         db 0                    ; the column the line started at
ld_cur:         db 0                    ; the cursor: an index, 0 to ld_len
ld_open:        db 0                    ; the line is open (TTY_RECALL)
ld_buf:         ds TTY_LINE             ; the line
ld_key:         db 0,10                 ; what an arrow delivers
        ASSERT  ld_len == ld_state+LD_LEN && ld_pos == ld_state+LD_POS
        ASSERT  ld_eof == ld_state+LD_EOF && ld_col == ld_state+LD_COL
        ASSERT  ld_cur == ld_state+LD_CUR && ld_open == ld_state+LD_OPEN
        ASSERT  ld_buf == ld_state+LD_BUF
