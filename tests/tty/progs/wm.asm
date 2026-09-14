; wm — the handler's stack watermark. Ignoring SIGINT, it says "^C now: ",
; fills its stack below SP with 55h, spins three seconds in user space —
; every tick's handler, and the ^C pressed meanwhile with its broadcast,
; push on this stack — then counts, from just under SP downward, the bytes
; that are no longer 55h, and exits with that count: how deep the kernel
; reached, against the 24 bytes it promises to keep to. Whether a ^C came
; at all the block reads in the keyboard queue, which wm cannot see. SP is
; read, not assumed: the argument block sits above the frame and moves it.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      a,SIGINT
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
        m6_puts now                     ; before the fill: the write's own
        ld      hl,0                    ; pushes are painted over
        add     hl,sp
        ld      (sp0),hl                ; sp0 = SP
        ld      de,3F00h
        or      a
        sbc     hl,de                   ; hl = SP - 3F00h: bytes to fill
        ld      b,h
        ld      c,l
        dec     bc
        ld      hl,3F00h
        ld      (hl),55h
        ld      de,3F01h
        ldir                            ; 3F00h .. SP-1
        ld      hl,(K_TICKS)
        ld      de,180
        add     hl,de
        ex      de,hl                   ; de = the tick to stop at
.spin:  ld      hl,(K_TICKS)
        or      a
        sbc     hl,de
        jr      c,.spin
        ld      hl,(sp0)
        dec     hl                      ; just under SP
        ld      b,0
.scan:  ld      a,(hl)
        cp      55h
        jr      z,.done
        inc     b
        dec     hl
        jr      .scan
.done:  ld      a,b
        sys     SYS_EXIT
        m6_proglib
now:    db      "^C now: ",0
sp0:    dw      0
