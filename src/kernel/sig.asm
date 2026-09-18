; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; Signals: four, each terminates the process it reaches or is ignored, and
; never runs a handler. A process a signal ended reports 128 + the signal
; through waitpid — 130, 137, 141, 143.
;
; Delivery is by redirection, because whoever sends a signal cannot reach
; into the victim to close its descriptors: the open-file table is in the
; storage segment, out of the interrupt handler's page 3. Every save path
; leaves a process's PC ten pairs into its saved frame, at P_SP+20
; (sched.asm), and the stub sig_stub is written there; the process dies the
; next time it would have run, calling sys_exit, which closes its
; descriptors on the normal path, on the kernel stack.
;
; The frame is on the victim's own stack, in the victim's own pages, which
; are mapped only while the victim runs — so the stub is planted at the
; two moments the frame can be addressed: by the interrupt handler, in its
; own frame, when the victim is the process it interrupted in user space
; (sig_cur); and by sched_load, once it has mapped the pages of the process
; it is about to resume (sig_load). Sending a signal therefore only marks
; the victim as owing it (PX_SIGPEND, bit 7 clear), wakes it if it was
; blocked, and raises SF_PLANT so that sched_load looks; a victim running
; in a syscall when the handler sees the signal keeps it owed with SF_PEND
; set, and the handler tries again every tick until the syscall returns to
; user space or the process blocks — so a signal never interrupts a
; syscall, and a 64 KB write dies at its end. A process that leaves the
; CPU with SF_PEND still set — it blocked, yielded, or paid an owed switch
; at its syscall's return — has it turned into SF_PLANT by sched_load, so
; that its next load plants the stub; otherwise the next tick's sig_cur
; would read the flag against whoever is current then and the signal
; would stay owed with nobody looking.
; Planting sets bit 7 of PX_SIGPEND (armed), so nothing plants or wakes a
; row twice. A second signal is dropped while one is owed or armed, unless
; it is SIGKILL, which replaces the number; a signal its owner has come to
; ignore since it was sent is dropped when it would be planted (sig_owed).
; kill of oneself marks and dies at once through the stub. kill and
; signal themselves are in the switched part (ks_sys.asm) and reach
; sig_send, sig_bit and sig_stub through K_API2.

; sig_bit — A = a signal: A = its PX_SIGIGN bit, CF clear; CF set for
; SIGKILL or a number that is none of the four. Corrupts F.
sig_bit:
        cp      SIGINT
        jr      z,.int
        cp      SIGPIPE
        jr      z,.pipe
        cp      SIGTERM
        jr      z,.term
        scf
        ret
.int:   ld      a,SIGIGN_INT
        or      a
        ret
.pipe:  ld      a,SIGIGN_PIPE
        or      a
        ret
.term:  ld      a,SIGIGN_TERM
        or      a
        ret

; sig_send — HL = a process row, C = a signal. Nothing happens for process
; 0, a free row or a zombie, or when the process ignores the signal (and it
; is not SIGKILL): A = 0. Otherwise the signal is owed (PX_SIGPEND) and,
; for a process with a frame — blocked, or runnable and not current — it is
; planted at once; the current process keeps it owed with SF_PEND set; a
; vfork parent keeps it owed for vf_resume. A = 1. Interrupts must be
; disabled: the handler holds them, sys_kill wraps this in di/ei. Corrupts
; everything.
sig_send:
        ld      (sig_row),hl
        ld      a,c
        ld      (sig_num),a
        ld      a,l
        cp      low K_PROC
        jr      z,.no                   ; process 0
        ld      a,(hl)
        or      a
        jr      z,.no                   ; PS_FREE
        cp      PS_ZOMBIE
        jr      z,.no
        ld      a,c
        cp      SIGKILL
        jr      z,.pend                 ; never ignored
        call    sig_bit                 ; a = the bit
        ld      e,a
        ld      hl,(sig_row)
        ld      a,l
        rrca                            ; (pid << 4) >> 1 = pid << 3
        add     a,low K_PX+PX_SIGIGN
        ld      l,a
        ld      h,high K_PX
        ld      a,(hl)
        and     e
        jr      nz,.no                  ; ignored
.pend:  ld      hl,(sig_row)
        ld      a,l
        rrca
        add     a,low K_PX+PX_SIGPEND
        ld      l,a
        ld      h,high K_PX             ; hl -> PX_SIGPEND
        ld      a,(hl)
        or      a
        jr      z,.set                  ; nothing owed: this one
        ld      a,(sig_num)
        cp      SIGKILL
        jr      nz,.state               ; one already owed or armed: kept
.set:   ld      a,(sig_num)
        ld      (hl),a                  ; owed, bit 7 clear
.state: ld      hl,(sig_row)
        ld      a,(hl)                  ; P_STATE
        cp      PS_RUN
        jr      nz,.blocked
        ld      a,(k_cur)
        cp      l
        jr      nz,.plant               ; runnable, not current: sched_load
        ld      hl,k_sigflag
        set     1,(hl)                  ; SF_PEND: the current one owes it
        jr      .yes
.blocked:
        cp      PS_VFORK
        jr      z,.yes                  ; no frame yet: vf_resume plants it
        ld      hl,(sig_row)
        call    sig_wake                ; out of its block, into the ring
.plant: ld      hl,k_sigflag
        set     2,(hl)                  ; SF_PLANT: sched_load plants it
.yes:   ld      a,1
        ret
.no:    xor     a
        ret

; sig_wake — HL = the row of a blocked process that owes a signal: its
; block is undone and it is made runnable, so that sched_load plants the
; stub when it loads it. A pipe waiter's slot in the pipe's row is left as
; it is: pipe_wake clears a slot it finds taken and links nothing whose
; row is not PS_PIPE, so a stale pid costs one walk at most and never
; wakes a wrong process. Interrupts disabled. Corrupts everything.
sig_wake:
        ld      (sig_dl),hl
        ld      a,(hl)
        cp      PS_KBD
        jr      z,.kbd
        cp      PS_SLEEP
        jr      z,.slp
        cp      PS_PIPE
        jr      z,.pipe
        jr      .link                   ; PS_WAIT: left the ring, no count
.kbd:   ld      hl,k_kbwait
        dec     (hl)
        jr      .link
.slp:   ld      hl,k_nsleep
        dec     (hl)
        jr      .link
.pipe:  ld      hl,k_pwait
        dec     (hl)
.link:  ld      hl,(sig_dl)
        ld      (hl),PS_RUN
        jp      sched_link              ; hl = the row

; sig_load — from sched_load, with the pages of the process it is about
; to resume mapped and SP at that process's frame, this call's return
; address on top: if the process owes a signal it has not been planted
; with, sig_stub goes into the frame's PC — SP+2 past the return address,
; +20 into the frame — and the row is armed. On the new process's stack,
; below its frame. Corrupts AF, DE, HL.
sig_load:
        ld      a,(k_pid)
        call    px_row
        ld      de,PX_SIGPEND
        add     hl,de
        call    sig_owed
        ret     z                       ; owes nothing it still has to take
        ld      a,(hl)
        or      80h
        ld      (hl),a                  ; armed
        ld      hl,22
        add     hl,sp                   ; -> the frame's PC
        ld      de,sig_stub
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ret

; sig_stub — a process resumes here when a signal reached it: it exits
; with 128 + the signal it owed. On the process's own stack; sys_exit moves
; to the kernel stack at once.
sig_stub:
        ld      a,(k_pid)
        call    px_row
        ld      de,PX_SIGPEND
        add     hl,de
        ld      a,(hl)
        and     7Fh                     ; the number, without the armed bit
        add     a,128
        jp      sys_exit

; sig_owed — HL -> a row's PX_SIGPEND. Out: A = the signal the row owes
; and has not been planted with (bit 7 clear), NZ; or A = 0, Z — owing
; nothing, armed already, or owing a signal it has come to ignore since it
; was sent, in which case the byte is cleared: a ^C that lands while a
; process is inside the signal call that makes it ignore SIGINT must not
; kill it when that call returns. Preserves HL;
; corrupts F, DE.
sig_owed:
        ld      a,(hl)
        or      a
        ret     z                       ; owes nothing
        bit     7,a
        jr      nz,.none                ; armed: planted already
        cp      SIGKILL
        jr      z,.take                 ; never ignored
        push    hl
        call    sig_bit                 ; a = the bit
        pop     hl
        dec     hl                      ; PX_SIGIGN, the byte before
        and     (hl)
        inc     hl
        jr      nz,.drop
.take:  ld      a,(hl)
        or      a                       ; NZ: owed
        ret
.drop:  xor     a
        ld      (hl),a                  ; ignored since: dropped
        ret
.none:  xor     a
        ret

; sig_bcast — a ^C: SIGINT to every process that does not ignore it. When
; none took it, the byte 03h is queued instead, so that a reader — a shell
; at its prompt — sees it; every blocked reader is woken for it. From the
; handler, interrupts disabled. Corrupts everything.
sig_bcast:
        ld      hl,K_PROC
        ld      c,0                     ; c = how many took it
        ld      b,NPROC-1
.row:   ld      a,l
        add     a,P_SIZE
        ld      l,a
        push    bc
        push    hl
        ld      c,SIGINT
        call    sig_send
        pop     hl
        pop     bc
        or      a
        jr      z,.next
        inc     c
.next:  djnz    .row
        ld      a,c
        or      a
        ret     nz                      ; somebody dies: no byte
        ld      e,24                    ; the 'c' key
        ld      c,~2 & 0FFh             ; the modifiers, CTRL alone down
        call    kbd_enqueue
        ld      a,(k_kbwait)
        or      a
        ret     z
        jp      kbd_wake

; sig_isr — from k_isr when k_sigflag is set, interrupts disabled, with
; sig_fpc pointing at the interrupted PC in this interrupt's own frame and
; BC and DE saved by the caller (the interrupted code may be a copy loop
; counting in B: found when one wrote the VRAM over kbd.asm). A
; ^C is broadcast; the current process, if it owes a signal, takes it in
; that frame when it was interrupted in user space, or keeps SF_PEND for
; the next tick; and while SF_PLANT says some process owes a signal not
; yet planted, the table is walked to see whether that is still so — the
; victims sched_load has planted since are armed, one that has come to
; ignore its signal is dropped — and the flag is cleared when none is
; left, so that sched_load stops looking. Corrupts everything.
sig_isr:
        ld      hl,k_sigflag
        bit     0,(hl)                  ; SF_INT
        jr      z,.owed
        res     0,(hl)
        call    sig_bcast
.owed:  ld      hl,k_sigflag
        bit     1,(hl)                  ; SF_PEND
        jr      z,.plant
        res     1,(hl)                  ; set again by sig_cur if still stuck
        ld      a,(k_pid)
        or      a
        call    nz,sig_cur
.plant: ld      hl,k_sigflag
        bit     2,(hl)                  ; SF_PLANT
        ret     z
        ld      hl,K_PROC
        ld      b,NPROC-1
.row:   ld      a,l
        add     a,P_SIZE
        ld      l,a
        ld      a,(hl)
        or      a
        jr      z,.next                 ; PS_FREE
        cp      PS_ZOMBIE
        jr      z,.next
        cp      PS_VFORK
        jr      z,.next                 ; vf_resume's
        push    bc
        push    hl
        ld      a,l
        rrca
        add     a,low K_PX+PX_SIGPEND
        ld      l,a
        ld      h,high K_PX
        call    sig_owed
        pop     hl
        pop     bc
        ret     nz                      ; one still owes: the flag stays
.next:  djnz    .row
        ld      hl,k_sigflag
        res     2,(hl)                  ; nobody owes: sched_load may stop looking
        ret

; sig_cur — the current process may owe a signal: if it does, the stub is
; planted where its frame can be reached from here, and the row armed —
; or SF_PEND is set again for the next tick. Three cases, told apart by
; the two tests k_isr makes for a switch. Interrupted in user space — PC
; and SP both below page 3: the stub goes into the interrupt's own frame
; (sig_fpc). Interrupted in the switched image — PC in page 2, SP on the
; kernel stack in page 3: the syscall in flight is left to finish, and the
; stub replaces the return address the process's call pushed, which k_usp
; points at — provided that stack is in page 0, the process's own during
; the gate; a stack in page 1 or 2 has the storage segment or the window
; over it now and is left for a later tick. Interrupted in the resident
; with SP anywhere — a resident syscall body, spawn, the gate's stubs: the
; frame cannot be found, and the next tick tries again. Corrupts
; everything.
sig_cur:
        ld      a,(k_pid)
        call    px_row
        ld      de,PX_SIGPEND
        add     hl,de
        call    sig_owed
        ret     z                       ; owes nothing it still has to take
        push    hl
        ld      hl,(sig_fpc)
        inc     hl
        ld      a,(hl)                  ; PCh
        cp      0C0h
        jr      nc,.stuck               ; the resident: a body, spawn, a stub
        ld      hl,(sig_fpc)
        inc     hl
        inc     hl                      ; = the interrupted SP
        ld      a,h
        cp      0C0h
        jr      nc,.switched            ; SP in page 3: the switched image
        ld      hl,(sig_fpc)            ; user space: the frame's PC
        jr      .plant
.switched:
        ld      hl,(k_usp)              ; -> the call's return into user code
        ld      a,h
        cp      40h
        jr      nc,.stuck               ; a stack above page 0: not reachable
.plant: ld      de,sig_stub
        ld      (hl),e
        inc     hl
        ld      (hl),d
        pop     hl                      ; -> PX_SIGPEND
        ld      a,(hl)
        or      80h
        ld      (hl),a                  ; armed
        ret
.stuck: pop     hl
        ld      hl,k_sigflag
        set     1,(hl)                  ; SF_PEND: again next tick
        ret

k_sigflag:      db 0                    ; SF_INT, SF_PEND
sig_fpc:        dw 0                    ; -> the interrupted PC in k_isr's
                                        ;   frame, for the length of sig_isr
sig_row:        dw 0                    ; sig_send: the row
sig_num:        db 0                    ;   the signal
sig_dl:         dw 0                    ; sig_wake: the row
