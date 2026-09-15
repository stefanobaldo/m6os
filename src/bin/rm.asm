; rm file... — each file removed; a failure is reported and the next one
; follows. A directory is EISDIR: rmdir removes an empty one.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   call    arg_next
        jr      c,usage
.loop:  push    hl
        sys     SYS_UNLINK
        pop     de
        call    c,err_file
        call    arg_next
        jr      nc,.loop
        ld      a,(lib_status)
        ret
usage:  ld      de,s_usage
        jp      err_usage
s_usage: db     "rm file...",0

        include "lib/args.inc"
        include "lib/err.inc"
        m6_bss
