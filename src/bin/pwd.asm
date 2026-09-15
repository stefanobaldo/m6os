; pwd — the current directory, as getcwd names it: the shortest path that
; reaches it.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,buf
        ld      bc,PATH_MAX
        sys     SYS_GETCWD
        jr      c,.err
        ld      hl,buf
        call    out_puts
        ld      a,10
        call    out_putc
        xor     a
        ret
.err:   ld      de,0
        call    err_file
        ld      a,1
        ret

        include "lib/out.inc"
        include "lib/err.inc"
        m6_bss
        bss     buf,PATH_MAX
