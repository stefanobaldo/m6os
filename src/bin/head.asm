; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; head [-n N] [file...] — the first N lines of each file, 10 without -n;
; descriptor 0 without a file. With more than one file, "==> file <=="
; before each and a blank line between them. Bytes go through in_getc,
; so a line longer than any buffer is printed whole; the output is
; flushed at a LF that empties the input buffer, so a line typed at the
; keyboard comes back at once.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,10
        ld      (nlines),hl
        ld      hl,opts
        ld      de,s_usage
        call    arg_opts
        ld      a,(opt_flags)
        bit     0,a
        jr      z,.count
        ld      hl,(opt_val)
        call    str_atoi
        jr      c,usage
        ld      a,(de)
        or      a
        jr      nz,usage                ; not a number to the end
        ld      (nlines),hl
.count: ld      hl,(lib_argc)
        ld      de,(arg_i)
        or      a
        sbc     hl,de
        ld      (nfiles),hl
        ld      a,1
        ld      (first),a
        call    arg_next
        jr      c,.stdin
.file:  ld      (name),hl
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      c,.err
        ld      (fd),a
        call    header
        call    lines
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
        call    lines
        jr      .done
usage:  ld      de,s_usage
        jp      err_usage

; header — with more than one file: a blank line before every file but
; the first, then "==> name <==".
header: ld      hl,(nfiles)
        dec     hl
        ld      a,h
        or      l
        ret     z
        ld      a,(first)
        or      a
        jr      nz,.first
        ld      a,10
        call    out_putc
.first: xor     a
        ld      (first),a
        ld      hl,s_open
        call    out_puts
        ld      hl,(name)
        call    out_puts
        ld      hl,s_close
        jp      out_puts

; lines — the first nlines lines of the descriptor in fd.
lines:  ld      a,(fd)
        call    in_open
        ld      hl,(nlines)
        ld      (left),hl
.loop:  ld      hl,(left)
        ld      a,h
        or      l
        ret     z
        call    in_getc
        jr      c,.end
        call    out_putc
        cp      10
        jr      nz,.loop
        ld      hl,(left)
        dec     hl
        ld      (left),hl
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

opts:    db     "n:",0
s_usage: db     "head [-n N] [file...]",0
s_open:  db     "==> ",0
s_close: db     " <==",10,0

        include "lib/out.inc"
        include "lib/in.inc"
        include "lib/line.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     fd,1
        bss     name,2
        bss     nlines,2
        bss     nfiles,2
        bss     left,2
        bss     first,1
