; uniq [file] — the lines of the file, or of descriptor 0, with each
; run of equal adjacent lines printed once. A line longer than 1 KB is
; cut there, the rest dropped.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   call    arg_next
        jr      c,.stdin
        ld      (name),hl
        call    arg_next
        jr      nc,usage
        ld      hl,(name)
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      c,.err
        ld      (fd),a
        call    run
        ld      a,(fd)
        sys     SYS_CLOSE
.done:  ld      a,(lib_status)
        ret
.err:   ld      de,(name)
        call    err_file
        jr      .done
.stdin: xor     a
        ld      (fd),a
        ld      hl,0
        ld      (name),hl
        call    run
        jr      .done
usage:  ld      de,s_usage
        jp      err_usage

; run — the descriptor in fd, line by line: a line is printed when it is
; the first or differs from the one before it. Two buffers alternate: a
; printed line becomes the one to compare with, a dropped one is read
; over.
run:    ld      a,(fd)
        call    in_open
        ld      hl,bufa
        ld      (cur),hl
        ld      hl,bufb
        ld      (prev),hl
        xor     a
        ld      (have),a
.loop:  ld      de,(cur)
        ld      bc,LINE_MAX
        call    in_line
        jr      c,.end
        ld      a,(have)
        or      a
        jr      z,.print
        ld      hl,(cur)
        ld      de,(prev)
        call    str_cmp
        jr      z,.loop                 ; the same again: dropped
.print: ld      a,1
        ld      (have),a
        ld      hl,(cur)
        call    out_puts
        ld      a,10
        call    out_putc
        ld      hl,(cur)
        ld      de,(prev)
        ld      (cur),de
        ld      (prev),hl
        ld      hl,(in_ptr)
        ld      de,(in_end)
        or      a
        sbc     hl,de
        call    z,out_flush             ; the read is used up: show it
        jr      .loop
.end:   ld      a,(in_err)
        or      a
        ret     z
        ld      de,(name)
        jp      err_file

LINE_MAX equ    1024
s_usage: db     "uniq [file]",0

        include "lib/out.inc"
        include "lib/in.inc"
        include "lib/line.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     fd,1
        bss     name,2
        bss     cur,2
        bss     prev,2
        bss     have,1
        bss     bufa,LINE_MAX
        bss     bufb,LINE_MAX
