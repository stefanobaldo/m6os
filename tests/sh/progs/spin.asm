; spin N — reads the kernel's tick count in user space until N ticks have
; passed (600 without N); exits 0. Never calls the kernel while it runs:
; the runnable process that makes the ring two, so that a tick finding
; another process in the kernel has someone to owe the switch to.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   call    arg_next
        jr      c,.default
        call    str_atoi
        jr      .go
.default:
        ld      hl,600
.go:    ld      (span),hl
        ld      hl,(K_TICKS)
        ld      (t0),hl
.loop:  ld      hl,(K_TICKS)
        ld      de,(t0)
        or      a
        sbc     hl,de                   ; elapsed
        ld      de,(span)
        or      a
        sbc     hl,de
        jr      c,.loop
        xor     a
        ret
        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     span,2
        bss     t0,2
