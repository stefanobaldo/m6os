; The kernel window and the syscall gate.
;
; The kernel is in two parts. The resident, page 3, holds the hot path:
; slot switching, the interrupt entry, the allocator, the console, the
; driver call, the process, the gate itself. The rest — the cold path — is
; a second image, kseg.asm, assembled at KS_BASE and living in a segment of
; its own (K_KSEG, allocated at boot as the kernel's); it is switched into
; page 2, the kernel window, for the length of a call and switched out
; again. The window is page 2 because a one-page program has nothing there
; and loses nothing while the kernel is in, and because the driver's ROM
; takes page 1.
;
; kwin_enter and kwin_leave are the backend of the window, and the only
; place that knows what backs it: here a mapper segment and one OUT each
; way. A kernel started from a cartridge ROM replaces them with a slot
; switch and a bank select and changes nothing else. Both use AF', which
; no syscall preserves, instead of the stack. k_map is what the kernel
; believes is in each page; the mapper register is never read.
;
; A switched syscall's entry in K_SYS is a stub emitted by k_switched, one
; per syscall: it moves the stack to k_sstack — the process's stack may be
; in page 2 — switches the window in, calls the body directly, and returns
; through k_gate_ret, which switches the window out and the stack back.
; Interrupts stay enabled throughout: the interrupt handler touches page 3
; and the VDP only, and pushes on whatever stack is current.

    macro kwin_enter                    ; the switched part into page 2
        ex      af,af'
        ld      a,(K_KSEG)
        out     (0FEh),a
        ex      af,af'
    endm

    macro kwin_leave                    ; what belongs in page 2, back
        ex      af,af'
        ld      a,(k_map+2)
        out     (0FEh),a
        ex      af,af'
    endm

; kwin_call target — a kernel-side call into the switched part, on the
; caller's own stack, which is in page 3. Every register reaches the callee
; and comes back as it leaves them.
    macro kwin_call target
        kwin_enter
        call    target
        kwin_leave
    endm

; k_switched target — the K_SYS entry of a syscall whose body is at target
; in the switched part.
    macro k_switched target
        ld      (k_usp),sp
        ld      sp,k_sstack
        kwin_enter
        call    target
        jp      k_gate_ret
    endm

k_gate_ret:
        kwin_leave
        ld      sp,(k_usp)
        ret

; kwin_load — load the switched part from where the record says into a
; segment of the kernel's. Out: Z if done, or if there is none to load
; (K_KSEG stays 0); NZ with A = 0F4h when the source is not in pages 0-1
; or the length is not 1 to 4000h, 0F5h when no segment is free. Corrupts
; everything.
kwin_load:
        ld      hl,(K_REC+KR_KSEG_SRC)
        ld      a,h
        or      l
        ret     z                       ; none: Z
        ld      a,h
        cp      80h
        jr      nc,.bad                 ; not in pages 0-1
        ld      de,(K_REC+KR_KSEG_LEN)
        ld      a,d
        or      e
        jr      z,.bad                  ; empty
        ld      a,d
        cp      40h
        jr      c,.fits
        jr      nz,.bad                 ; above 4000h
        ld      a,e
        or      a
        jr      nz,.bad
.fits:  ld      b,MEM_KERNEL
        call    mem_alloc
        jr      c,.noseg
        ld      (K_KSEG),a
        out     (0FEh),a                ; the new segment into the window
        ld      b,d
        ld      c,e
        ld      de,KS_BASE
        ldir
        ld      a,(k_map+2)
        out     (0FEh),a
        xor     a                       ; Z
        ret
.bad:   ld      a,0F4h
        or      a                       ; NZ
        ret
.noseg: ld      a,0F5h
        or      a
        ret

k_map:          ds 4            ; the segment in each page, as the kernel
                                ; believes it: from the record at boot,
                                ; then proc_run's and sys_exit's
k_usp:          dw 0            ; the process's stack pointer during a
                                ; switched syscall
