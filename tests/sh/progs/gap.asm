; gap N cmd args... — runs the command as a child and reads the kernel's
; tick count in a loop, never yielding, until the child exits; prints the
; largest gap between two consecutive readings, the ticks the child ran,
; and ok when the gap is within N (FAIL otherwise, status 1). Alone a
; reader sees 1; beside one other runnable process 2, the turn alternating;
; anything beyond is time that process held the CPU inside a syscall —
; the delay a key's echo would have waited. Spawning the load itself is
; what makes the reading the kernel's and not the host's: this process is
; in its loop, in user space, when the child first runs, so no host's
; timing can put the child first and leave the reader an idle machine.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   call    arg_next                ; N
        jp      c,usage
        call    str_atoi
        jp      c,usage
        ld      (bound),hl
        ld      hl,(arg_i)              ; argv[arg_i] is the command: its
        ld      de,(lib_argc)           ; tail of the vector is the child's
        or      a
        sbc     hl,de
        jp      nc,usage
        ld      hl,(arg_i)
        add     hl,hl
        ld      de,(lib_argv)
        add     hl,de                   ; hl -> &argv[arg_i]
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        dec     hl
        ex      de,hl                   ; hl -> the path, de -> the vector
        ld      (path),hl
        ld      bc,fdmap
        xor     a
        sys     SYS_SPAWNV
        jp      c,nospawn
        ld      a,l
        ld      (pid),a
        ld      hl,(K_TICKS)
        ld      (t0),hl
        ld      (last),hl
        ld      hl,0
        ld      (gap),hl
.poll:  ld      b,0                     ; 256 reads between two waitpids
.read:  ld      hl,(K_TICKS)
        ld      de,(last)
        ld      (last),hl
        or      a
        sbc     hl,de                   ; hl = the gap
        ld      de,(gap)
        or      a
        sbc     hl,de                   ; the new gap less the largest
        jr      c,.same
        jr      z,.same
        add     hl,de
        ld      (gap),hl
.same:  djnz    .read
        ld      a,(pid)
        ld      b,WNOHANG
        sys     SYS_WAITPID
        jr      c,.done                 ; ECHILD: reaped by someone else
        ld      a,h
        or      l
        jr      z,.poll                 ; 0: still running
.done:  ld      hl,(K_TICKS)
        ld      de,(t0)
        or      a
        sbc     hl,de
        ld      (span),hl
        ld      hl,s_gap
        call    out_puts
        ld      hl,(gap)
        ld      b,0
        call    out_dec16
        ld      hl,s_span
        call    out_puts
        ld      hl,(span)
        ld      b,0
        call    out_dec16
        ld      hl,(bound)
        ld      de,(gap)
        or      a
        sbc     hl,de                   ; bound - gap: CF when over
        ld      hl,s_ok
        ld      a,0
        jr      nc,.say
        ld      hl,s_fail
        ld      a,1
.say:   push    af
        call    out_puts
        pop     af
        ret
nospawn:
        ld      de,(path)
        call    err_file
        ld      a,1
        ret
usage:  ld      de,s_usage
        jp      err_usage
s_gap:  db      "gap ",0
s_span: db      " span ",0
s_ok:   db      " ok",10,0
s_fail: db      " FAIL",10,0
s_usage: db     "gap N cmd args...",0
fdmap:  db      0FFh,0FFh,0FFh          ; the child's 0, 1, 2: our own
        include "lib/out.inc"
        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     bound,2
        bss     path,2
        bss     pid,1
        bss     t0,2
        bss     last,2
        bss     gap,2
        bss     span,2
