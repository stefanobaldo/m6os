; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; grep [-vn] pattern [file...] — the lines that hold the pattern, a
; literal, one per line as they are; -v the lines that do not; -n each
; line after its number and a colon; "file:" before each line with more
; than one file; descriptor 0 without a file. A line longer than 1 KB is
; cut there, the rest dropped. Status 0 when a line was selected, 1 when
; none was, 2 when a file failed.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,opts
        ld      de,s_usage
        call    arg_opts
        call    arg_next
        jr      c,usage
        ld      (pat),hl
        ld      a,(hl)
        ld      (p0),a
        call    str_len
        ld      (plen),bc
        ld      hl,(lib_argc)
        ld      de,(arg_i)
        or      a
        sbc     hl,de
        ld      (nfiles),hl
        xor     a
        ld      (found),a
        call    arg_next
        jr      c,.stdin
.file:  ld      (name),hl
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      c,.err
        ld      (fd),a
        call    lines
        ld      a,(fd)
        sys     SYS_CLOSE
.next:  call    arg_next
        jr      nc,.file
.done:  ld      a,(lib_status)
        or      a
        ld      a,2
        ret     nz                      ; a file failed
        ld      a,(found)
        xor     1                       ; 0 when a line was selected
        ret
.err:   ld      de,(name)
        call    err_file
        jr      .next
.stdin: xor     a
        ld      (fd),a
        ld      hl,0
        ld      (name),hl
        call    lines
        jr      .done
usage:  ld      de,s_usage
        jp      err_usage

; lines — the descriptor in fd, line by line, each selected line printed.
lines:  ld      a,(fd)
        call    in_open
        ld      hl,0
        ld      (lno),hl
        ld      (lno+2),hl
.loop:  ld      de,line
        ld      bc,LINE_MAX
        call    in_line
        jr      c,.end
        ld      hl,(lno)
        inc     hl
        ld      (lno),hl
        ld      a,h
        or      l
        jr      nz,.num
        ld      hl,(lno+2)
        inc     hl
        ld      (lno+2),hl
.num:   ld      hl,line
        call    match                   ; Z when the pattern is in it
        ld      a,(opt_flags)
        jr      z,.hit
        bit     0,a
        jr      z,.loop                 ; no match, no -v: dropped
        jr      .print
.hit:   bit     0,a
        jr      nz,.loop                ; a match under -v: dropped
.print: ld      a,1
        ld      (found),a
        ld      hl,(nfiles)
        ld      de,2
        or      a
        sbc     hl,de
        jr      c,.nonm                 ; one file, or none: no name
        ld      hl,(name)
        call    out_puts
        ld      a,':'
        call    out_putc
.nonm:  ld      a,(opt_flags)
        bit     1,a
        jr      z,.line
        ld      hl,(lno)
        ld      de,(lno+2)
        ld      b,0
        call    out_dec32
        ld      a,':'
        call    out_putc
.line:  ld      hl,line
        call    out_puts
        ld      a,10
        call    out_putc
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

; match — HL -> a line, BC = its length: Z when the pattern is in it.
; The pattern's first byte is found with cpir, then the rest compared.
match:  ld      de,(plen)
        ld      a,d
        or      e
        ret     z                       ; the empty pattern: every line
.scan:  push    hl
        ld      h,b
        ld      l,c
        or      a
        sbc     hl,de
        pop     hl
        jr      c,.no                   ; fewer bytes left than the pattern
        ld      a,(p0)
        cpir                            ; Z: found, hl -> after it, bc = the rest
        jr      nz,.no
        push    hl
        push    bc
        ld      de,(plen)
        dec     de
        ld      a,d
        or      e
        jr      z,.yes                  ; a pattern of one byte
        push    hl
        ld      h,b
        ld      l,c
        or      a
        sbc     hl,de
        pop     hl
        jr      c,.short                ; the rest cannot hold the pattern
        ld      b,d
        ld      c,e
        ld      de,(pat)
        inc     de                      ; de -> the pattern's second byte
.cmp:   ld      a,(de)
        cp      (hl)
        jr      nz,.again
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.cmp
.yes:   pop     bc
        pop     hl
        xor     a
        ret
.again: pop     bc
        pop     hl
        ld      de,(plen)
        jr      .scan
.short: pop     bc
        pop     hl
.no:    or      1
        ret

LINE_MAX equ    1024
opts:    db     "vn",0
s_usage: db     "grep [-vn] pattern [file...]",0

        include "lib/out.inc"
        include "lib/in.inc"
        include "lib/line.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     fd,1
        bss     name,2
        bss     pat,2
        bss     plen,2
        bss     p0,1
        bss     nfiles,2
        bss     found,1
        bss     lno,4
        bss     line,LINE_MAX
