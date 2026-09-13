; The extension table and sleep.
;
; K_PX holds, per process, what the 16-byte row in K_PROC has no room
; for: the pipe a blocked row waits on, the tick a sleeping row wakes at,
; and the signal bytes a later phase fills. A row is K_PX + (pid << 3),
; the same trick as the descriptor table's; the kernel's own thread has
; row 0 like everyone else.
;
; sleep puts the process out of the ring until K_TICKS reaches the value
; its row holds. The interrupt handler wakes sleepers by equality, not by
; comparison — the counter wraps at 65536 and an unsigned "reached" would
; misfire across the wrap — and skips the whole walk with one compare
; while nobody sleeps.

; px_row — A = a pid: HL -> its extension row. Corrupts AF.
px_row:
        add     a,a
        add     a,a
        add     a,a
        add     a,low K_PX
        ld      l,a
        ld      h,high K_PX
        ret

; px_init — A = a new process's pid: its extension row — waiting on no
; pipe, no wake tick, the current process's ignored signals, nothing
; pending, the spare bytes 0. Corrupts AF, BC, DE, HL.
px_init:
        ld      c,a
        call    px_row
        ld      (hl),0FFh               ; PX_WCHAN
        inc     hl
        xor     a
        ld      b,PX_SIZE-1
.zero:  ld      (hl),a
        inc     hl
        djnz    .zero
        ld      a,(k_pid)
        call    px_row
        ld      de,PX_SIGIGN
        add     hl,de
        ld      b,(hl)                  ; the parent's ignored signals
        ld      a,c
        call    px_row
        ld      de,PX_SIGIGN
        add     hl,de
        ld      (hl),b
        ret

; sys_sleep — SYS_SLEEP: HL = ticks. Out: HL = 0, once K_TICKS has
; advanced by that many; 0 ticks is a yield. On the process's stack.
sys_sleep:
        ld      a,h
        or      l
        jp      z,sys_yield
        ld      de,(K_TICKS)
        add     hl,de
        ex      de,hl                   ; de = the tick to wake at
        di
        ld      a,(k_pid)
        call    px_row
        inc     hl                      ; PX_WAKE
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      hl,(k_cur)
        ld      (hl),PS_SLEEP
        ld      hl,k_nsleep
        inc     (hl)
        call    sched_unlink
        ld      hl,.woken
        push    hl
        push    af
        push    hl
        jp      sched_save_block        ; its ei is the load's
.woken: ld      hl,0
        xor     a                       ; CF clear
        ret

; sleep_tick — from the handler, once per tick, interrupts disabled:
; every PS_SLEEP row whose wake tick is now, into the ring. One compare
; when nobody sleeps. Corrupts AF, HL; preserves everything else.
sleep_tick:
        ld      a,(k_nsleep)
        or      a
        ret     z
        push    bc
        push    de
        ld      hl,K_PROC
        ld      b,NPROC
.row:   ld      a,(hl)
        cp      PS_SLEEP
        jr      nz,.next
        ld      a,l
        rrca                            ; (pid << 4) >> 1 = pid << 3
        add     a,low K_PX+PX_WAKE
        ld      e,a
        ld      d,high K_PX
        ld      a,(de)
        ld      c,a
        inc     de
        ld      a,(de)                  ; a:c = the wake tick
        ld      de,(K_TICKS)
        cp      d
        jr      nz,.next
        ld      a,c
        cp      e
        jr      nz,.next
        ld      (hl),PS_RUN
        push    bc
        call    sched_link              ; preserves HL, B
        pop     bc
        ld      a,(k_nsleep)
        dec     a
        ld      (k_nsleep),a
.next:  ld      a,l
        add     a,P_SIZE
        ld      l,a
        djnz    .row
        pop     de
        pop     bc
        ret

k_nsleep:       db 0                    ; rows in PS_SLEEP
