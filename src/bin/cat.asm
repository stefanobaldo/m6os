; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; cat [file...] — the files to the output, in order; descriptor 0 without
; one. The output is flushed after every read, so a line typed at the
; keyboard comes back at once.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   call    arg_next
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

; copy — the descriptor in fd to the output, to its end.
copy:   ld      a,(fd)
        call    in_open
.loop:  call    in_fill
        jr      c,.rerr
        ld      a,b
        or      c
        ret     z
        call    out_write
        call    out_flush
        jr      .loop
.rerr:  ld      de,(name)
        jp      err_file

        include "lib/out.inc"
        include "lib/in.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        m6_bss
        bss     fd,1
        bss     name,2
