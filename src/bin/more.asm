; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; more [file...] — the files to the output, in order, descriptor 0
; without one, stopping each time a screenful has gone by. The rows are
; counted as the console moves its cursor: a wrap at column 80, TAB to
; the next stop, LF, CR, BS, and FF for a cleared screen. After 23 rows,
; with more to come, "--More--" goes to descriptor 2 and a key is read
; there in raw mode: SPACE a screenful more, RET a line more, q the end.
; A read of no bytes on 2 tells the console, which refuses it with
; EINVAL, from anything else; when 2 is not the console, every read goes
; to the output as it is, as cat does.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1

ROWS    equ     23              ; a screenful: the 24th row holds the prompt
COLS    equ     80

main:   xor     a
        ld      (rows),a
        ld      (col),a
        ld      (paging),a
        ld      a,2
        ld      hl,key
        ld      bc,0
        sys     SYS_READ
        jr      nc,.args
        cp      E_INVAL
        jr      nz,.args
        ld      a,1                     ; 2 is the console
        ld      (paging),a
.args:  call    arg_next
        jr      c,.stdin
.file:  ld      (name),hl
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      c,.err
        ld      (fd),a
        call    copy
        ld      a,(fd)
        sys     SYS_CLOSE
.next:  call    arg_next
        jr      nc,.file
.done:  ld      a,(lib_status)
        ret
.err:   ld      de,(name)
        call    err_file
        jr      .next
.stdin: xor     a
        ld      (fd),a
        ld      hl,0
        ld      (name),hl
        call    copy
        jr      .done

; copy — the descriptor in fd to the output, to its end: each read
; written whole, or paged when 2 is the console.
copy:   ld      a,(fd)
        call    in_open
.loop:  call    in_fill                 ; hl -> the bytes, bc = how many
        jr      c,.rerr
        ld      a,b
        or      c
        ret     z
        ld      a,(paging)
        or      a
        jr      nz,.page
        ld      a,1
        sys     SYS_WRITE
        jp      c,err_out
        jr      .loop
.page:  call    page
        jr      .loop
.rerr:  ld      de,(name)
        jp      err_file

; page — HL -> bytes, BC = how many: the bytes written a run at a time,
; the rows counted in D and the column in E, a stop before the first
; byte past a screenful. Corrupts everything.
page:   ld      (run),hl
        ld      a,(rows)
        ld      d,a
        ld      a,(col)
        ld      e,a
.byte:  ld      a,d
        cp      ROWS
        call    z,stop
        ld      a,(hl)
        inc     hl
        cp      20h
        jr      c,.ctl
        inc     e
        ld      a,e
        cp      COLS
        jr      z,.row                  ; the row is full: wrapped
.next:  dec     bc
        ld      a,b
        or      c
        jr      nz,.byte
        ld      a,d
        ld      (rows),a
        ld      a,e
        ld      (col),a
        jr      emit
.ctl:   cp      10
        jr      z,.row
        cp      13
        jr      z,.cr
        cp      9
        jr      z,.tab
        cp      8
        jr      z,.bs
        cp      12
        jr      nz,.next                ; ignored by the console
        ld      d,0                     ; FF: the screen cleared
.cr:    ld      e,0
        jr      .next
.tab:   ld      a,e
        or      7
        inc     a
        ld      e,a
        cp      COLS
        jr      c,.next
.row:   ld      e,0
        inc     d
        jr      .next
.bs:    ld      a,e
        or      a
        jr      z,.next
        dec     e
        jr      .next

; emit — HL -> past the run that began at run: the run written to 1, and
; run moved to HL. Corrupts everything.
emit:   ld      de,(run)
        ld      (run),hl
        or      a
        sbc     hl,de
        ret     z
        ld      b,h
        ld      c,l
        ex      de,hl
        ld      a,1
        sys     SYS_WRITE
        jp      c,err_out
        ret

; stop — HL -> the next byte, a screenful shown: the run so far written,
; the prompt, then keys read raw on 2 until one means something. SPACE
; gives D = 0, a screenful more; RET D = ROWS-1, a line more; q ends the
; program. The prompt is erased and the terminal left canonical before
; the output goes on. Preserves BC, E, HL.
stop:   push    bc
        push    de
        push    hl
        call    emit
        ld      a,2
        ld      hl,s_prompt
        ld      bc,s_prompt_n
        sys     SYS_WRITE
        ld      a,TTY_RAW
        sys     SYS_TTYMODE
.key:   ld      a,2
        ld      hl,key
        ld      bc,1
        sys     SYS_READ
        ld      b,0
        jr      c,.go                   ; nothing to read: go on
        ld      a,(key)
        cp      ' '
        jr      z,.go
        ld      b,ROWS-1
        cp      13
        jr      z,.go
        or      20h
        cp      'q'
        jr      nz,.key
        call    erase
        ld      a,(lib_status)
        jp      lib_exit
.go:    ld      a,b
        ld      (key),a
        call    erase
        pop     hl
        pop     de
        ld      a,(key)
        ld      d,a
        pop     bc
        ret

; erase — the terminal canonical again and the prompt's row blank, the
; cursor at its start. Corrupts everything.
erase:  ld      a,TTY_CANON
        sys     SYS_TTYMODE
        ld      a,2
        ld      hl,s_erase
        ld      bc,s_erase_n
        sys     SYS_WRITE
        ret

s_prompt:       db      "--More--"
s_prompt_n      equ     $-s_prompt
s_erase:        db      13,"        ",13
s_erase_n       equ     $-s_erase

        include "lib/in.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        m6_bss
        bss     fd,1
        bss     name,2
        bss     paging,1
        bss     rows,1
        bss     col,1
        bss     run,2
        bss     key,1
