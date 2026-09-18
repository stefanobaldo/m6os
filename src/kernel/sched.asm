; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The scheduler: who runs, and the switch from one process to the next.
;
; The process table is NPROC rows of P_SIZE bytes at K_PROC, one aligned
; page, so a row is K_PROC + (pid << 4) and the circular scan wraps by
; adding 16 to the low byte. Row 0 is process 0, the kernel's own thread:
; the code k_main jumps into, running in page 3 on k_stack with the
; kernel's pages — the switched image's segment in pages 0 and 1, where it
; carries the interrupt vector and the subslot stub, and the kernel's
; scratch segment in page 2. It is never preempted, because its PC is in
; page 3, and it gives the CPU up in wait and yield only.
;
; A process that is not running keeps its registers on its own stack, in
; the frame sched_save_switch pushes and sched_resume pops — PC, AF, HL,
; BC, DE, IX, IY, BC', DE', HL', AF' from the bottom — and P_SP points at
; it. A tick and a syscall build the same frame: the PC at the bottom is
; the interrupt's return address, or the process's own call's, or the
; address wait pushes to resume at; then AF and HL, then the rest here.
; Every register is saved because a tick may land on any instruction.
;
; The policy is round-robin, a switch at every tick in user space, no
; priorities. A tick that finds the process in the kernel cannot switch
; and sets k_owed instead (irq.asm); the syscall's return pays it
; (k_owed_gate, kwin.asm), so the wait for a turn is bounded by one call.
; sched_load clears k_owed, since whoever owed it has left. The runnable
; rows form a ring through P_NEXT — the low byte of the next row, since
; the table is one page — so that the next process is one load away
; however sparse the table is; a row enters the ring after the current
; one (sched_link) and the current row leaves it (sched_unlink) when it
; blocks or exits. k_nrun is the ring's size, so that the tick with one
; runnable process costs a compare.
;
; The save and the scan run with interrupts enabled; the load — the pages
; and the stack pointer — is one DI region closed by the resume's EI, so
; that a tick never finds the stack pointer in one process's pages and the
; mapper in another's. The load is also where a signal owed by the process
; coming in is planted in its frame (sig.asm): the frame is in the
; process's own pages, and this is the one place they are known to be in.

; sched_link — HL = a row that becomes runnable: into the ring after the
; current row, or alone in it when it was empty. Corrupts AF, C, DE.
sched_link:
        ld      a,(K_NRUN)
        or      a
        jr      z,.alone
        inc     a
        ld      (K_NRUN),a
        ld      de,(k_cur)
        ld      a,e
        add     a,P_NEXT
        ld      e,a                     ; de -> the current row's P_NEXT
        ld      a,(de)
        ld      c,a                     ; c = what followed the current row
        ld      a,l
        ld      (de),a                  ; current.next = new
        add     a,P_NEXT
        ld      e,a                     ; de -> the new row's P_NEXT
        ld      a,c
        ld      (de),a                  ; new.next = what followed
        ret
.alone: ld      a,1
        ld      (K_NRUN),a
        ld      (k_cur),hl
        ld      a,l
        add     a,P_NEXT
        ld      e,a
        ld      d,h
        ld      a,l
        ld      (de),a                  ; new.next = new
        ret

; sched_unlink — the current row leaves the ring: whoever pointed at it
; points past it. Its own P_NEXT keeps pointing into the ring, which is
; where sched_next goes from here. Corrupts AF, BC, DE, HL.
sched_unlink:
        ld      hl,k_nrun
        dec     (hl)
        ld      hl,(k_cur)
        ld      c,l                     ; c = the current row
        ld      a,l
        add     a,P_NEXT
        ld      l,a
        ld      b,(hl)                  ; b = what follows it
        ld      e,b
        ld      d,h                     ; de -> a row of the ring
.walk:  ld      a,e
        add     a,P_NEXT
        ld      l,a
        ld      a,(hl)                  ; that row's next
        cp      c
        jr      z,.pred                 ; it is the current row: found
        ld      e,a
        jr      .walk
.pred:  ld      (hl),b                  ; pred.next = current.next
        ret

; sched_save — AF and HL are on the stack already: push the rest and save
; the stack pointer in the current row. A macro, because the frame is
; built by whoever jumps here and a call would put its return address in
; it. Leaves HL = the current row.
    macro sched_save
        push    bc
        push    de
        push    ix
        push    iy
        exx
        push    bc
        push    de
        push    hl
        exx
        ex      af,af'
        push    af
        ex      af,af'
        ld      hl,0
        add     hl,sp
        ex      de,hl
        ld      hl,(k_cur)
        inc     hl
        ld      (hl),e                  ; P_SP
        inc     hl
        ld      (hl),d
        dec     hl
        dec     hl
    endm

; sched_save_block — the current row has left the ring, possibly leaving
; it empty: save the context, move to the syscall stack — the process's
; own has its 24 bytes spoken for — and go through the idle loop. read
; comes here. Entered by a jump; never returns.
sched_save_block:
        sched_save
        ld      sp,k_sstack
        jp      sched_next_idle

; sched_save_switch — AF and HL are on the stack already: push the rest,
; save the stack pointer in the current row, and switch to the next
; runnable process. Entered by a jump; never returns to its caller.
sched_save_switch:
        push    bc
        push    de
        push    ix
        push    iy
        exx
        push    bc
        push    de
        push    hl
        exx
        ex      af,af'
        push    af
        ex      af,af'
        ld      hl,0
        add     hl,sp
        ex      de,hl
        ld      hl,(k_cur)
        inc     hl
        ld      (hl),e                  ; P_SP
        inc     hl
        ld      (hl),d
        ld      a,l
        add     a,P_NEXT-2
        ld      l,a
        ld      l,(hl)                  ; the next runnable row: falls into
                                        ; sched_load
        jr      sched_load

; sched_next_idle — HL = the row whose successor in the ring runs next,
; when the ring may be empty: with nothing runnable, wait for a tick to
; put something in it and look again. exit and wait come here; a yield or
; a tick knows the ring holds two at least and takes sched_next.
sched_next_idle:
        ld      a,(K_NRUN)
        or      a
        jr      nz,sched_next
        ei                              ; idle: nothing to run until a tick
sched_idle_halt:
        halt                            ; wakes a process
        ld      hl,(k_cur)
        jr      sched_next_idle

; sched_next — HL = a row of the ring: its successor runs next — its pages,
; its stack, its registers.
sched_next:
        ld      a,l
        add     a,P_NEXT
        ld      l,a
        ld      l,(hl)                  ; the next runnable row
sched_load:
        di                              ; the load: pages and stack together
        ld      (k_cur),hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; de = P_SP
        inc     hl
        ld      a,(hl)
        ld      (k_pid),a               ; P_PID
        inc     hl
        inc     hl                      ; P_PPID, P_NPAGES
        inc     hl
        ld      a,(hl)
        ld      (k_map+0),a
        out     (0FCh),a
        inc     hl
        ld      a,(hl)
        ld      (k_map+1),a
        out     (0FDh),a
        inc     hl
        ld      a,(hl)
        ld      (k_map+2),a
        out     (0FEh),a
        ex      de,hl
        ld      sp,hl                   ; the process's stack, at its frame
        xor     a
        ld      (k_owed),a              ; a switch the one leaving owed: paid
        ; A signal it owes and has not been planted with (sig.asm): now that
        ; its pages are in, the stub goes into the frame — on this stack,
        ; below the frame, never on the outgoing process's. SF_PEND here
        ; belongs to the process that left — the current one owed a signal
        ; sig_cur could not plant, and gave the CPU up before the next tick
        ; — and becomes SF_PLANT, so that its next load plants it instead
        ; of the next tick's sig_cur consulting it against another pid.
        ld      a,(k_sigflag)
        or      a
        jr      z,sched_resume
        bit     1,a                     ; SF_PEND
        jr      z,.plant
        res     1,a
        set     2,a                     ; SF_PLANT
        ld      (k_sigflag),a
.plant: and     SF_PLANT
        call    nz,sig_load

; sched_resume — the frame off the current stack, and back to the process.
sched_resume:
        ex      af,af'
        pop     af
        ex      af,af'
        exx
        pop     hl
        pop     de
        pop     bc
        exx
        pop     iy
        pop     ix
        pop     de
        pop     bc
        pop     hl
        pop     af
        ei
        reti

; k_cur, k_pid and k_nrun are in the header (K_CUR, K_PID, K_NRUN), where
; the switched part reads and, at boot, writes them (ks_boot.asm).
k_owed:         db 0            ; the current process owes a switch: a tick
                                ; found it in the kernel with k_nrun >= 2
