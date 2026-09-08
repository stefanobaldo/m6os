; The process: what one is, how it is created, how it ends, how it waits.
;
; A process owns pages 0-2, 48K. Page 0 opens with the kernel's region —
; a jump to the exit stub at 0000h, the interrupt vector at 0038h, the
; subslot stub at 0040h, the exit stub itself at P0_EXIT — and the program
; starts at P0_PROG, as a .COM does. It is born with its saved context
; already on its stack at the top of its highest page, under P0_EXIT, so
; that its first switch-in is the same as every other one and a program
; that ends in ret exits with status 0. Everything else is the program's.
;
; Its row in the table (sched.asm) is where its state lives; spawn, fork
; and vfork fill one, exit turns it into a zombie or frees it, wait reaps
; it. Nothing here returns to a caller when a process ends: exit hands the
; CPU to the scheduler and the parent learns the status from wait.
;
; fork and vfork return twice. Both push on the parent's stack the frame a
; tick would — the ten register pairs under the call's return address,
; with HL = 0 — so that the child, resumed on it by the scheduler, comes
; back from the call with 0 where the parent gets the pid. fork copies
; every page of the parent into segments of the child's, the frame with
; them, and drops its own copy of the frame on the way out. vfork copies
; nothing: the child runs on the parent's pages and stack, the parent
; sleeps until the child exits, and the return address the child's pushes
; overwrite is kept in the parent's row. A vfork child does nothing but
; exit (or, later, exec) — the classic rule, documented rather than
; enforced.
;
; Every change to the ring of runnable rows outside the interrupt handler
; is made with interrupts disabled, because the handler makes its own — a
; key wakes a reader — and a ring half-relinked when a tick lands is a
; ring with a row lost.

; spawn — HL = the program image, anywhere but page 2 (pages 0-1 of the
; caller, or page 3 for process 0); BC = its length; A = pages, 1-3. Out:
; CF clear and HL = A = the child's pid; CF set with A = E_INVAL (pages not
; 1-3, length 0, image in page 2, or too long for the pages), E_AGAIN (no
; row free) or E_NOMEM (a segment short — nothing kept). Runs on the
; syscall stack: it writes the child through page 2, where a three-page
; caller keeps its own stack. Corrupts everything.
spawn:
        ld      (k_usp),sp
        ld      sp,k_sstack
        call    sp_create
        ld      sp,(k_usp)
        ret

sp_create:
        or      a
        jp      z,.inval
        cp      4
        jp      nc,.inval
        ld      (sp_pages),a
        ld      (sp_src),hl
        ld      (sp_rem),bc
        ld      a,b
        or      c
        jp      z,.inval
        ld      a,h
        cp      80h
        jr      c,.src                  ; pages 0-1
        cp      0C0h
        jp      c,.inval                ; page 2: the window itself
.src:   ld      a,(sp_pages)
        rrca
        rrca                            ; pages * 40h: 40h, 80h, C0h
        ld      h,a
        ld      l,0                     ; hl = pages * 4000h, the top
        ld      de,P0_FRAME
        or      a
        sbc     hl,de
        ld      (sp_sp),hl              ; the initial stack pointer: under
                                        ; the frame and the exit address
        ld      de,P0_PROG
        or      a
        sbc     hl,de                   ; the room for the program
        or      a
        sbc     hl,bc                   ; minus its length
        jp      c,.inval                ; it does not fit
        ; A row.
        ld      hl,K_PROC
        ld      b,NPROC-1
.row:   ld      a,l
        add     a,P_SIZE
        ld      l,a
        ld      a,(hl)
        or      a                       ; PS_FREE
        jr      z,.got
        djnz    .row
        ld      a,E_AGAIN
        scf
        ret
.got:   ld      (sp_row),hl
        ld      a,l
        rrca
        rrca
        rrca
        rrca                            ; the pid: the row's index
        ld      (sp_pid),a
        ; The segments, as that pid.
        ld      a,(sp_pages)
        ld      c,a
        ld      hl,(sp_row)
        ld      de,P_SEG
        add     hl,de
.alloc: ld      a,(sp_pid)
        ld      b,a
        call    mem_alloc
        jp      c,.nomem
        ld      (hl),a
        inc     hl
        dec     c
        jr      nz,.alloc
        ; Each page in turn through the window: the header in page 0, the
        ; program's slice in every page it reaches.
        ld      hl,P0_PROG
        ld      (sp_dst),hl
        ld      a,(sp_pages)
        ld      c,a                     ; c = pages left
        ld      b,0                     ; b = this page
        ld      hl,(sp_row)
        ld      de,P_SEG
        add     hl,de
.page:  ld      a,(hl)
        out     (0FEh),a
        push    hl
        push    bc
        ld      a,b
        or      a
        call    z,sp_header
        ld      hl,(sp_rem)
        ld      a,h
        or      l
        jr      z,.copied
        ld      de,(sp_dst)             ; where the next byte goes, in the
        ld      a,d                     ; process's addresses
        and     3Fh
        or      80h
        ld      d,a                     ; de = the same, in the window
        ld      hl,0C000h
        or      a
        sbc     hl,de                   ; hl = room left in this page
        ld      bc,(sp_rem)
        push    hl
        or      a
        sbc     hl,bc                   ; room - remaining
        pop     hl
        jr      c,.chunk                ; less room than remains: the room
        ld      h,b
        ld      l,c                     ; all that remains fits
.chunk: ld      b,h
        ld      c,l                     ; bc = this page's slice
        ld      hl,(sp_src)
        push    bc
        ldir
        ld      (sp_src),hl
        pop     bc
        ld      hl,(sp_dst)
        add     hl,bc
        ld      (sp_dst),hl
        ld      hl,(sp_rem)
        or      a
        sbc     hl,bc
        ld      (sp_rem),hl
.copied:
        pop     bc
        pop     hl
        inc     hl
        inc     b
        dec     c
        jr      nz,.page
        ; The highest page is in the window: the initial frame at its top —
        ; the exit stub's address for the program's final ret, the entry
        ; point, and zeros for every register sched_resume pops.
        ld      hl,P0_EXIT
        ld      (KS_BASE+3FFEh),hl
        ld      hl,P0_PROG
        ld      (KS_BASE+3FFCh),hl
        ld      hl,KS_BASE+4000h-P0_FRAME
        ld      (hl),0
        ld      de,KS_BASE+4000h-P0_FRAME+1
        ld      bc,P0_FRAME-4-1
        ldir
        ld      a,(k_map+2)
        out     (0FEh),a
        ; The row.
        ld      hl,(sp_row)
        ld      de,(sp_sp)
        inc     hl
        ld      (hl),e                  ; P_SP
        inc     hl
        ld      (hl),d
        inc     hl
        ld      a,(sp_pid)
        ld      (hl),a                  ; P_PID
        inc     hl
        ld      a,(k_pid)
        ld      (hl),a                  ; P_PPID
        inc     hl
        ld      a,(sp_pages)
        ld      (hl),a                  ; P_NPAGES
        ld      hl,(sp_row)
        ld      de,P_STATUS
        add     hl,de
        ld      (hl),0
        ld      hl,(sp_row)
        ld      (hl),PS_RUN             ; P_STATE, then into the ring
        di
        call    sched_link
        ei
        ld      a,(sp_pid)
        ld      l,a
        ld      h,0
        or      a                       ; CF clear
        ret
.inval: ld      a,E_INVAL
        scf
        ret
.nomem: ld      a,(sp_pid)
        ld      b,a
        call    mem_free_all            ; whatever was taken, back
        ld      a,E_NOMEM
        scf
        ret

; sp_header — page 0 of the process is in the window: zero the kernel's
; region and write its four entries. Corrupts AF, BC, DE, HL.
sp_header:
        ld      hl,KS_BASE
        ld      (hl),0
        ld      de,KS_BASE+1
        ld      bc,P0_PROG-1
        ldir
        ld      a,0C3h
        ld      (KS_BASE),a             ; 0000h: jp P0_EXIT
        ld      hl,P0_EXIT
        ld      (KS_BASE+1),hl
        ld      (KS_BASE+K_INTRPT),a    ; 0038h: jp K_ISR
        ld      hl,K_ISR
        ld      (KS_BASE+K_INTRPT+1),hl
        ld      hl,(K_STUB)             ; 0040h: the subslot stub
        ld      de,KS_BASE+K_SSLOT
        ld      bc,K_SSLOT_LEN
        ldir
        ld      hl,KS_BASE+P0_EXIT      ; P0_EXIT: xor a; jp exit
        ld      (hl),0AFh
        inc     hl
        ld      (hl),0C3h
        inc     hl
        ld      de,K_SYS+3*SYS_EXIT
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ret

; sys_exit — SYS_EXIT: A = status. The segments back, the children
; orphaned or reaped, the row a zombie — or free, if nobody will wait —
; the parent woken if it is waiting in wait or in vfork, and the CPU to
; the next process. Runs on the syscall stack from its first instruction:
; the dead process's own may be its vfork parent's, where the parent's
; frame is about to be rebuilt.
sys_exit:
        ld      sp,k_sstack
        ld      hl,(k_cur)
        ld      de,P_STATUS
        add     hl,de
        ld      (hl),a
        ld      a,(k_pid)
        ld      b,a
        call    mem_free_all
        ; The children.
        ld      a,(k_pid)
        ld      c,a
        ld      hl,K_PROC
        ld      b,NPROC-1
.child: ld      a,l
        add     a,P_SIZE
        ld      l,a
        ld      a,(hl)
        or      a
        jr      z,.next                 ; PS_FREE
        push    hl
        inc     hl
        inc     hl
        inc     hl
        inc     hl                      ; P_PPID
        ld      a,(hl)
        cp      c
        jr      nz,.notmine
        ld      (hl),PP_NONE            ; a living child: nobody will wait
        pop     hl
        push    hl
        ld      a,(hl)
        cp      PS_ZOMBIE
        jr      nz,.notmine
        ld      (hl),PS_FREE            ; a dead one: reaped now
.notmine:
        pop     hl
.next:  djnz    .child
        ; My row.
        ld      hl,(k_cur)
        ld      de,P_PPID
        add     hl,de
        ld      a,(hl)
        cp      PP_NONE
        jr      z,.free
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,K_PROC
        add     hl,de                   ; the parent's row
        ld      a,(hl)
        cp      PS_WAIT
        jr      z,.wake
        cp      PS_VFORK
        jr      nz,.zombie
        call    vf_resume               ; the parent's frame, HL = my pid
.wake:  ld      (hl),PS_RUN             ; the parent wakes: into the ring
        di
        call    sched_link
        ei
.zombie:
        ld      hl,(k_cur)
        ld      (hl),PS_ZOMBIE
        jr      .gone
.free:  ld      hl,(k_cur)
        ld      (hl),PS_FREE
.gone:  di
        call    sched_unlink            ; out of the ring; my P_NEXT still
        ei                              ; says who runs next
        ld      hl,(k_cur)
        jp      sched_next_idle

; vf_resume — HL = the row of a parent blocked in vfork: the frame it will
; resume on, on the pages it shares with the exiting child — every
; register zero but HL = the child's pid, and the return address the row
; kept back at the top. Preserves HL; corrupts AF, BC, DE.
vf_resume:
        push    hl
        push    hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; de = P_SP: where the frame goes
        ld      h,d
        ld      l,e
        ld      (hl),0
        inc     de
        ld      bc,19
        ldir                            ; the ten pairs, zero
        ; de -> the return address's slot; the pid into HL's slot, four
        ; below it.
        ld      h,d
        ld      l,e
        dec     hl
        dec     hl
        dec     hl
        dec     hl
        ld      a,(k_pid)
        ld      (hl),a                  ; L = the pid; H stays 0
        pop     hl
        ld      bc,P_VPC
        add     hl,bc
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        ld      a,(hl)
        ld      (de),a
        pop     hl
        ret

; sys_wait — SYS_WAIT. Out: H = the pid of a child that has exited, L = A
; = its status, the row free; CF and E_CHILD with no child alive or dead.
; Blocks while children live and none has exited.
sys_wait:
.again: ld      a,(k_pid)
        ld      c,a
        ld      d,0                     ; d = living children seen
        ld      hl,K_PROC
        ld      b,NPROC-1
.child: ld      a,l
        add     a,P_SIZE
        ld      l,a
        ld      a,(hl)
        or      a
        jr      z,.next                 ; PS_FREE
        push    hl
        inc     hl
        inc     hl
        inc     hl
        inc     hl                      ; P_PPID
        ld      a,(hl)
        pop     hl
        cp      c
        jr      nz,.next
        ld      a,(hl)
        cp      PS_ZOMBIE
        jr      z,.reap
        inc     d
.next:  djnz    .child
        ld      a,d
        or      a
        jr      z,.nochild
        ld      hl,(k_cur)
        ld      (hl),PS_WAIT
        di
        call    sched_unlink
        ei
        ld      hl,.again               ; resume at the top of the loop
        push    hl
        push    af
        push    hl
        jp      sched_save_switch
.reap:  ld      (hl),PS_FREE
        push    hl
        ld      de,P_STATUS
        add     hl,de
        ld      a,(hl)                  ; the status
        pop     hl
        inc     hl
        inc     hl
        inc     hl
        ld      h,(hl)                  ; P_PID
        ld      l,a
        or      a                       ; CF clear
        ret
.nochild:
        ld      a,E_CHILD
        scf
        ret

; sys_yield — SYS_YIELD: the CPU to the next runnable process. With no
; other, it returns at once: a process yielding to itself pays a compare,
; not a walk of the table and a save and restore of its own registers.
sys_yield:
        ld      a,(k_nrun)
        cp      2
        jr      nc,.go
        or      a                       ; CF clear
        ret
.go:    push    af
        push    hl
        jp      sched_save_switch

; The frame fork and vfork push under the call's return address: what a
; tick pushes, with HL = 0 for the child.
    macro fk_frame
        push    af
        ld      hl,0
        push    hl
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
    endm
FK_FRAME        equ 20

; sys_fork — SYS_FORK. Out: HL = A = the child's pid in the parent, 0 in
; the child; CF with E_PERM from process 0, E_AGAIN with no row free,
; E_NOMEM with a segment short — nothing kept. The copy runs on the
; syscall stack and cannot be preempted; two pages are 13 ticks.
sys_fork:
        ld      a,(k_pid)
        or      a
        jp      z,fk_perm
        fk_frame
        ld      hl,FK_FRAME
        add     hl,sp
        ld      (fk_ssp),hl             ; the stack without the frame
        ld      (k_usp),sp              ; the stack with it: the child's
        ld      sp,k_sstack
        call    fk_create
        ld      sp,(fk_ssp)             ; flags kept: the result's CF
        ret
fk_perm:
        ld      a,E_PERM
        scf
        ret

fk_create:
        ld      hl,(k_cur)
        ld      de,P_NPAGES
        add     hl,de
        ld      a,(hl)
        ld      (sp_pages),a
        ; A row.
        ld      hl,K_PROC
        ld      b,NPROC-1
.row:   ld      a,l
        add     a,P_SIZE
        ld      l,a
        ld      a,(hl)
        or      a                       ; PS_FREE
        jr      z,.got
        djnz    .row
        ld      a,E_AGAIN
        scf
        ret
.got:   ld      (sp_row),hl
        ld      a,l
        rrca
        rrca
        rrca
        rrca                            ; the pid: the row's index
        ld      (sp_pid),a
        ; The segments, as that pid.
        ld      a,(sp_pages)
        ld      c,a
        ld      hl,(sp_row)
        ld      de,P_SEG
        add     hl,de
.alloc: ld      a,(sp_pid)
        ld      b,a
        call    mem_alloc
        jp      c,.nomem
        ld      (hl),a
        inc     hl
        dec     c
        jr      nz,.alloc
        ; The copy: each page of the parent into the child's segment in
        ; the window. Page 0 stays where it is — the interrupt vector is
        ; there — so the parent's page 2 is read through page 1.
        ld      b,0                     ; b = the page
        ld      hl,(sp_row)
        ld      de,P_SEG
        add     hl,de
.page:  ld      a,(hl)
        out     (0FEh),a                ; the child's page, in the window
        push    hl
        push    bc
        ld      hl,0000h
        ld      a,b
        or      a
        jr      z,.copy
        ld      hl,4000h
        dec     a
        jr      z,.copy
        ld      a,(k_map+2)
        out     (0FDh),a                ; the parent's page 2, in page 1
.copy:  ld      de,8000h
        ld      bc,4000h
        ldir
        pop     bc
        pop     hl
        inc     hl
        inc     b
        ld      a,(sp_pages)
        cp      b
        jr      nz,.page
        ld      a,(k_map+1)
        out     (0FDh),a                ; the parent's pages back
        ld      a,(k_map+2)
        out     (0FEh),a
        ; The row.
        ld      hl,(sp_row)
        ld      de,(k_usp)
        inc     hl
        ld      (hl),e                  ; P_SP: the frame's, in the copy
        inc     hl
        ld      (hl),d
        inc     hl
        ld      a,(sp_pid)
        ld      (hl),a                  ; P_PID
        inc     hl
        ld      a,(k_pid)
        ld      (hl),a                  ; P_PPID
        inc     hl
        ld      a,(sp_pages)
        ld      (hl),a                  ; P_NPAGES
        ld      hl,(sp_row)
        ld      de,P_STATUS
        add     hl,de
        ld      (hl),0
        ld      hl,(sp_row)
        ld      (hl),PS_RUN             ; P_STATE, then into the ring
        di
        call    sched_link
        ei
        ld      a,(sp_pid)
        ld      l,a
        ld      h,0
        or      a                       ; CF clear
        ret
.nomem: ld      a,(sp_pid)
        ld      b,a
        call    mem_free_all            ; whatever was taken, back
        ld      a,E_NOMEM
        scf
        ret

; sys_vfork — SYS_VFORK. Out: as fork's; CF with E_PERM from process 0 or
; E_AGAIN with no row free. The child takes the parent's pages and stack
; and runs at once; the parent sleeps in PS_VFORK until sys_exit rebuilds
; its frame and wakes it, with HL = the child's pid.
sys_vfork:
        ld      a,(k_pid)
        or      a
        jp      z,fk_perm
        fk_frame
        ; A row.
        ld      hl,K_PROC
        ld      b,NPROC-1
.row:   ld      a,l
        add     a,P_SIZE
        ld      l,a
        ld      a,(hl)
        or      a                       ; PS_FREE
        jr      z,.got
        djnz    .row
        ld      hl,FK_FRAME             ; the frame off again
        add     hl,sp
        ld      sp,hl
        ld      a,E_AGAIN
        scf
        ret
.got:   ld      (sp_row),hl             ; not pushed: the frame is the
        ; The child's row: the parent's pages, this stack.
        ld      (hl),PS_RUN             ; top of the stack
        inc     hl
        ld      de,0
        ex      de,hl
        add     hl,sp
        ex      de,hl                   ; de = sp, hl -> P_SP
        ld      (hl),e                  ; P_SP
        inc     hl
        ld      (hl),d
        inc     hl
        ld      a,l
        sub     P_SP+2
        rrca
        rrca
        rrca
        rrca
        ld      (hl),a                  ; P_PID
        inc     hl
        ld      a,(k_pid)
        ld      (hl),a                  ; P_PPID
        inc     hl
        ex      de,hl
        ld      hl,(k_cur)
        ld      bc,P_NPAGES
        add     hl,bc
        ld      bc,4
        ldir                            ; P_NPAGES, P_SEG
        ex      de,hl
        ld      (hl),0                  ; P_STATUS
        ; The parent's row: asleep, its frame's place, its return address.
        ld      hl,(k_cur)
        ld      (hl),PS_VFORK
        inc     hl
        ld      de,0
        ex      de,hl
        add     hl,sp
        ex      de,hl
        ld      (hl),e                  ; P_SP
        inc     hl
        ld      (hl),d
        ld      hl,FK_FRAME
        add     hl,sp
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; de = the return address
        ld      hl,(k_cur)
        ld      bc,P_VPC
        add     hl,bc
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ; Into the ring after the parent, then the parent out: whoever
        ; pointed at the parent now points at the child, and the parent's
        ; own next says the child runs now.
        ld      hl,(sp_row)
        di
        call    sched_link
        call    sched_unlink
        ld      hl,(k_cur)
        jp      sched_next              ; ei is the resume's

fk_ssp:         dw 0            ; fork: the parent's stack pointer without
                                ;   the frame
sp_pages:       db 0            ; spawn: the child's pages
sp_pid:         db 0            ;   its pid
sp_row:         dw 0            ;   its row
sp_sp:          dw 0            ;   its initial stack pointer
sp_src:         dw 0            ;   the next byte of the image
sp_dst:         dw 0            ;   where it goes, in the child's addresses
sp_rem:         dw 0            ;   bytes left
