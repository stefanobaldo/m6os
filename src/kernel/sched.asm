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
; priorities. The runnable rows form a ring through P_NEXT — the low byte
; of the next row, since the table is one page — so that the next process
; is one load away however sparse the table is; a row enters the ring
; after the current one (sched_link) and the current row leaves it
; (sched_unlink) when it blocks or exits. k_nrun is the ring's size, so
; that the tick with one runnable process costs a compare.
;
; The save and the scan run with interrupts enabled; the load — the pages
; and the stack pointer — is one DI region closed by the resume's EI, so
; that a tick never finds the stack pointer in one process's pages and the
; mapper in another's.

; sched_init — row 0 and the scalars, before anything runs. Corrupts
; everything.
sched_init:
        ld      hl,K_PROC
        ld      (hl),PS_FREE
        ld      de,K_PROC+1
        ld      bc,NPROC*P_SIZE-1
        ldir
        ld      hl,K_PROC
        ld      (hl),PS_RUN             ; process 0: runnable, pid 0, a
        ld      (k_cur),hl              ; ring of one
        ld      a,low K_PROC
        ld      (K_PROC+P_NEXT),a
        ld      hl,0
        ld      (k_pid),hl
        ld      a,1
        ld      (k_nrun),a
        ld      a,PP_NONE
        ld      (K_PROC+P_PPID),a
        ld      hl,k_map                ; its pages: what is mapped now,
        ld      de,K_PROC+P_SEG         ; until sched_release_boot
        ld      bc,3
        ldir
        ; Every descriptor closed, then process 0's three: the keyboard on
        ; 0, the console on 1 and 2.
        ld      hl,K_FD
        ld      (hl),FD_NONE
        ld      de,K_FD+1
        ld      bc,NPROC*NOFILE-1
        ldir
        ld      a,FD_KBD
        ld      (K_FD+0),a
        ld      a,FD_CON
        ld      (K_FD+1),a
        ld      (K_FD+2),a
        ret

; sched_release_boot — once the switched image is loaded: the boot
; segments of pages 0 and 1 go to the allocator, the boot segment of page
; 2 stays as the kernel's scratch page, and process 0's pages 0 and 1
; become the switched image's segment, which carries the vector and the
; stub. With no switched image nothing changes hands. Corrupts everything.
sched_release_boot:
        ld      a,(K_KSEG)
        or      a
        ret     z
        ld      b,MEM_KERNEL
        call    mem_own                 ; the switched image's segment
        ld      a,(K_REC+KR_SEG64K+2)
        ld      b,MEM_KERNEL
        call    mem_own                 ; the scratch page
        ld      a,(K_REC+KR_SEG64K+0)
        call    mem_release
        ld      a,(K_REC+KR_SEG64K+1)
        call    mem_release
        ld      a,(K_KSEG)
        ld      (K_PROC+P_SEG+0),a
        ld      (k_map+0),a
        out     (0FCh),a                ; the vector is in the new page 0
        ld      (K_PROC+P_SEG+1),a
        ld      (k_map+1),a
        out     (0FDh),a
        ret

; sched_link — HL = a row that becomes runnable: into the ring after the
; current row, or alone in it when it was empty. Corrupts AF, C, DE.
sched_link:
        ld      a,(k_nrun)
        or      a
        jr      z,.alone
        inc     a
        ld      (k_nrun),a
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
        ld      (k_nrun),a
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
        ld      a,(k_nrun)
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
        ld      sp,hl

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

; k_cur and k_pid are in the header (K_CUR, K_PID), where the switched
; part reads them.
k_nrun:         db 0            ; rows in PS_RUN, the current one included
