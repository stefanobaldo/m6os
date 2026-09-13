; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; Pipes: NPIPE buffers of 256 bytes in page 3 (K_PIPEBUF), a table of
; NPIPE rows (k_pipe), and read, write, close and pipe on the descriptors
; that name their ends — all resident, on the process's own stack, with
; its pages in place, so a transfer is one LDIR between the process's
; buffer and the pipe's and no window or gate opens.
;
; A pipe holds the whole 256 bytes of its buffer: the head and the tail
; are the buffer's index, which wraps by itself, and a full pipe — head
; back at the tail — is told from an empty one by PI_FULL. A row is free
; when it has neither readers nor writers; the counts are references — a
; descriptor in some process's row — and spawn's inheritance and exit's
; close move them as they move an open file's.
;
; read blocks while the pipe is empty and a writer exists, and returns 0
; when it is empty and none does; write delivers every byte, blocking when
; the pipe is full, and a write to a pipe with no reader ends the writer
; with status 141 before a byte moves. A process that blocks leaves the
; ring (PS_PIPE, the pipe's index in its PX_WCHAN) and the other end runs
; at once; every change to a pipe wakes what waits on it — the row
; remembers one waiter per end, and walks the process table only when a
; second one queued on the same end — and a woken call looks again. Nothing here needs a last look under di before sleeping:
; the other end changes a pipe only from a syscall, and a syscall is never
; preempted.

; pi_row — A = a pipe index: HL -> its row. Corrupts AF, DE.
pi_row:
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      h,0
        ld      de,k_pipe
        add     hl,de
        ret

; pi_addr — A = an index into pipe (pp_n)'s buffer: HL -> the byte.
; Corrupts AF.
pi_addr:
        ld      l,a
        ld      a,(pp_n)
        add     a,high K_PIPEBUF
        ld      h,a
        ret

; sys_pipe — SYS_PIPE. Out: L = the read end's descriptor, H = the write
; end's; CF with E_NFILE (no pipe free) or E_MFILE (fewer than two
; descriptors free), nothing taken. The table is looked at first.
sys_pipe:
        ld      hl,k_pipe
        ld      b,NPIPE
        ld      c,0
.row:   push    hl
        inc     hl
        inc     hl
        inc     hl                      ; PI_READERS
        ld      a,(hl)
        inc     hl
        or      (hl)                    ; PI_WRITERS
        pop     hl
        jr      z,.free
        ld      de,PI_SIZE
        add     hl,de
        inc     c
        djnz    .row
        ld      a,E_NFILE
        scf
        ret
.free:  ld      (pp_row),hl
        ld      a,c
        ld      (pp_n),a
        ; The two lowest free descriptors.
        ld      a,(k_pid)
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      h,high K_FD
        ld      b,NOFILE
        ld      c,0
.fd1:   ld      a,(hl)
        cp      FD_NONE
        jr      z,.got1
        inc     hl
        inc     c
        djnz    .fd1
        jr      .mfile
.got1:  ld      (pp_slot),hl
        ld      a,c
        ld      (pp_fd),a
.fd2:   dec     b
        jr      z,.mfile
        inc     hl
        inc     c
        ld      a,(hl)
        cp      FD_NONE
        jr      nz,.fd2
        ld      a,(pp_n)
        or      FD_PIPE_W
        ld      (hl),a
        ld      hl,(pp_slot)
        ld      a,(pp_n)
        or      FD_PIPE_R
        ld      (hl),a
        ; The row: empty, one reader, one writer, nobody waiting.
        ld      hl,(pp_row)
        xor     a
        ld      (hl),a                  ; PI_HEAD
        inc     hl
        ld      (hl),a                  ; PI_TAIL
        inc     hl
        ld      (hl),a                  ; PI_FULL
        inc     hl
        inc     a
        ld      (hl),a                  ; PI_READERS
        inc     hl
        ld      (hl),a                  ; PI_WRITERS
        inc     hl
        ld      (hl),0FFh               ; PI_RWAIT
        inc     hl
        ld      (hl),0FFh               ; PI_WWAIT
        inc     hl
        ld      (hl),0                  ; PI_MANY
        ld      a,(pp_fd)
        ld      l,a
        ld      h,c
        or      a                       ; CF clear
        ret
.mfile: ld      a,E_MFILE
        scf
        ret

; pipe_read — A = FD_PIPE_R + n, HL = buffer, BC = length. Out: HL =
; bytes read, 1 to min(BC, 256); 0 at the end. E_INVAL for a length of 0,
; E_PERM from process 0, E_FAULT for a buffer reaching page 3.
;
; What a call must remember across a block travels in registers the
; frame saves — C = the pipe, IX = the buffer, IY = the length — because
; the variables below are one set for every process, and another
; process's call overwrites them while this one sleeps. The variables
; are reloaded from the registers at .again, which is where a woken call
; resumes.
pipe_read:
        push    bc
        pop     iy                      ; iy = the length
        push    hl
        pop     ix                      ; ix = the buffer
        and     0Fh
        ld      c,a                     ; c = the pipe
        ld      a,iyh
        or      iyl
        jp      z,pi_inval
        ld      a,(k_pid)
        or      a
        jp      z,pi_perm
        ; The buffer must not reach page 3, the kernel's: a wrong one is
        ; refused, not written through.
        ld      a,ixh
        cp      0C0h
        jp      nc,pi_fault
        push    ix
        pop     hl
        ld      de,0C000h
        ex      de,hl
        or      a
        sbc     hl,de                   ; the room before page 3
        push    iy
        pop     de
        or      a
        sbc     hl,de                   ; minus the length
        jp      c,pi_fault
.again: ld      a,c
        ld      (pp_n),a
        ld      (pp_buf),ix
        ld      (pp_len),iy
        call    pi_row
        ld      (pp_row),hl
        inc     hl
        inc     hl                      ; PI_FULL
        ld      a,(hl)
        or      a
        jr      nz,.full
        ld      hl,(pp_row)
        ld      a,(hl)                  ; PI_HEAD
        inc     hl
        sub     (hl)                    ; - PI_TAIL: the bytes held
        jr      nz,.some
        ; Empty: the end, or a wait.
        ld      hl,(pp_row)
        ld      de,PI_WRITERS
        add     hl,de
        ld      a,(hl)
        or      a
        jr      z,.eof
        ld      a,PI_RWAIT
        ld      hl,.again
        jp      pi_block                ; resumes at .again with C, IX, IY
.eof:   ld      hl,0
        xor     a                       ; CF clear
        ret
.full:  ld      bc,256
        jr      .min
.some:  ld      c,a
        ld      b,0
.min:   ; bc = bytes held, 1-256; n = min(bc, the length in iy).
        ld      a,iyh
        or      a
        jr      nz,.n                   ; 256 or more asked: what is held
        ld      a,b
        or      a
        jr      nz,.len                 ; 256 held, fewer asked
        ld      a,iyl
        cp      c
        jr      nc,.n                   ; as many asked as held, or more
.len:   ld      c,iyl
        ld      b,0
.n:     ld      (pp_cnt),bc
        ld      hl,(pp_row)
        inc     hl                      ; PI_TAIL
        ld      a,(hl)
        call    pi_addr                 ; hl -> the oldest byte
        ld      de,(pp_buf)
        ld      bc,(pp_cnt)
        call    pi_copy_out
        ld      hl,(pp_row)
        inc     hl                      ; PI_TAIL
        ld      a,(pp_cnt)
        add     a,(hl)
        ld      (hl),a                  ; tail += n, mod 256
        inc     hl
        ld      (hl),0                  ; PI_FULL: not any more
        ld      a,(pp_n)
        call    pipe_wake               ; a writer may have room now
        ld      hl,(pp_cnt)
        ld      a,l
        or      a                       ; CF clear
        ret

; pipe_write — A = FD_PIPE_W + n, HL = buffer, BC = length. Out: HL =
; BC, every byte delivered. E_PERM from process 0. With no reader the
; process exits with status 141 and nothing is copied. Across a block:
; C = the pipe, IX = the buffer's cursor, IY = bytes left, HL' = the
; length asked for, as pipe_read explains.
pipe_write:
        push    bc
        pop     iy                      ; iy = bytes left
        push    hl
        pop     ix                      ; ix = the cursor
        and     0Fh
        ld      c,a                     ; c = the pipe
        ld      a,(k_pid)
        or      a
        jp      z,pi_perm
        exx
        push    iy
        pop     hl                      ; hl' = the length asked for
        exx
.again: ld      a,c
        ld      (pp_n),a
        ld      (pp_buf),ix
        ld      (pp_len),iy
        call    pi_row
        ld      (pp_row),hl
        ld      de,PI_READERS
        add     hl,de
        ld      a,(hl)
        or      a
        jr      z,.noreader
        ld      a,iyh
        or      iyl
        jr      z,.done
        ld      hl,(pp_row)
        inc     hl
        inc     hl                      ; PI_FULL
        ld      a,(hl)
        or      a
        jr      z,.notfull
        ld      a,PI_WWAIT
        ld      hl,.again
        jp      pi_block                ; resumes at .again with C, IX, IY
.notfull:
        dec     hl                      ; PI_TAIL
        ld      a,(hl)
        dec     hl
        sub     (hl)                    ; - PI_HEAD: the room, 0 = all of it
        jr      nz,.room8
        ld      bc,256
        jr      .min
.room8: ld      c,a
        ld      b,0
.min:   ; bc = room, 1-256; n = min(bc, left).
        ld      a,iyh
        or      a
        jr      nz,.n
        ld      a,b
        or      a
        jr      nz,.len
        ld      a,iyl
        cp      c
        jr      nc,.n
.len:   ld      c,iyl
        ld      b,0
.n:     ld      (pp_cnt),bc
        ld      hl,(pp_row)
        ld      a,(hl)                  ; PI_HEAD
        call    pi_addr                 ; hl -> where the next byte goes
        ex      de,hl
        push    ix
        pop     hl
        ld      bc,(pp_cnt)
        call    pi_copy_in
        push    hl
        pop     ix                      ; the cursor, past what was copied
        ld      hl,(pp_row)
        ld      a,(pp_cnt)
        add     a,(hl)
        ld      (hl),a                  ; head += n, mod 256
        inc     hl
        cp      (hl)                    ; back at the tail: full
        jr      nz,.notfull2
        inc     hl
        ld      (hl),1                  ; PI_FULL
.notfull2:
        push    iy
        pop     hl
        ld      bc,(pp_cnt)
        or      a
        sbc     hl,bc
        push    hl
        pop     iy                      ; left -= n
        ld      a,(pp_n)
        call    pipe_wake               ; a reader may have bytes now
        ld      a,(pp_n)
        ld      c,a                     ; c = the pipe again
        jp      .again
.done:  exx
        push    hl
        exx
        pop     hl                      ; the length asked for
        or      a                       ; CF clear
        ret
.noreader:
        ld      a,141                   ; 128 + SIGPIPE
        jp      sys_exit

pi_inval:
        ld      a,E_INVAL
        scf
        ret
pi_fault:
        ld      a,E_FAULT
        scf
        ret
pi_perm:
        ld      a,E_PERM
        scf
        ret

; pi_copy_out — BC = a count 1-256 from the pipe's buffer at HL to DE:
; one LDIR, or two when the run wraps at the buffer's end. Corrupts
; everything.
pi_copy_out:
        ld      a,l
        neg                             ; bytes to the buffer's end; 0 = 256
        jr      z,.one                  ; from the start: any count fits
        ld      (pc_first),a
        ld      a,b
        or      a
        jr      nz,.two                 ; 256 asked: past the end for sure
        ld      a,(pc_first)
        cp      c
        jr      nc,.one                 ; the run ends before the buffer does
.two:   push    hl
        ld      h,b
        ld      l,c
        ld      a,(pc_first)
        ld      c,a
        ld      b,0
        or      a
        sbc     hl,bc                   ; the second piece
        ld      (pc_second),hl
        pop     hl
        ldir                            ; the first: hl = the page after
        dec     h                       ; the buffer's start
        ld      bc,(pc_second)
.one:   ldir
        ret

; pi_copy_in — BC = a count 1-256 from HL to the pipe's buffer at DE: the
; same, wrapping the destination. Leaves HL past the source. Corrupts
; everything else.
pi_copy_in:
        ld      a,e
        neg
        jr      z,.one
        ld      (pc_first),a
        ld      a,b
        or      a
        jr      nz,.two
        ld      a,(pc_first)
        cp      c
        jr      nc,.one
.two:   push    hl
        ld      h,b
        ld      l,c
        ld      a,(pc_first)
        ld      c,a
        ld      b,0
        or      a
        sbc     hl,bc
        ld      (pc_second),hl
        pop     hl
        ldir
        dec     d
        ld      bc,(pc_second)
.one:   ldir
        ret

; pi_block — HL = where to resume, A = PI_RWAIT or PI_WWAIT: the current
; process out of the ring, waiting on pipe (pp_n), the CPU to whoever is
; runnable. The pid goes into the row's slot for its end, so that a wake
; finds it in one load; a second waiter on the same end sets PI_MANY, and
; the wake walks the process table until the pipe is next made. Never
; returns here; the process resumes at HL with the pipe to look at again
; and with BC, DE, IX and IY as they were.
pi_block:
        di
        push    hl
        push    bc                      ; what the caller keeps across the
        push    de                      ; block: sched_unlink corrupts them
        ld      (pp_end),a
        ld      a,(pp_n)
        call    pi_row                  ; corrupts DE: the slot kept aside
        ld      a,(pp_end)
        ld      e,a
        ld      d,0
        add     hl,de                   ; hl -> the end's waiter slot
        ld      a,(hl)
        cp      0FFh
        jr      z,.slot
        ld      a,(pp_n)
        call    pi_row
        ld      de,PI_MANY
        add     hl,de
        ld      (hl),1
        jr      .state
.slot:  ld      a,(k_pid)
        ld      (hl),a
.state: ld      hl,(k_cur)
        ld      (hl),PS_PIPE
        ld      a,(k_pid)
        call    px_row
        ld      a,(pp_n)
        ld      (hl),a                  ; PX_WCHAN
        ld      hl,k_pwait
        inc     (hl)
        call    sched_unlink
        pop     de
        pop     bc
        pop     hl
        push    hl
        push    af
        push    hl
        jp      sched_save_block        ; its ei is the load's

; pipe_wake — A = a pipe index: every row waiting on it into the ring —
; the two the row names, or, after a second waiter on an end set
; PI_MANY, every PS_PIPE row with this pipe in its PX_WCHAN. Skipped in
; one compare when nobody waits on any pipe. Called from a syscall,
; interrupts enabled; the ring changes under di. Corrupts everything.
pipe_wake:
        ld      c,a
        ld      a,(k_pwait)
        or      a
        ret     z
        ld      a,c
        call    pi_row
        ld      de,PI_RWAIT
        add     hl,de                   ; hl -> PI_RWAIT, PI_WWAIT, PI_MANY
        di
        inc     hl
        inc     hl
        ld      a,(hl)                  ; PI_MANY
        or      a
        jr      nz,.walk
        dec     hl
        dec     hl
        call    .slot                   ; the reader waiting, if one
        inc     hl
        call    .slot                   ; the writer waiting, if one
        ei
        ret
.slot:  ld      a,(hl)
        cp      0FFh
        ret     z
        ld      (hl),0FFh
        push    hl
        add     a,a
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      h,high K_PROC           ; the waiter's row
        call    .row
        pop     hl
        ret
.walk:  ld      (hl),0                  ; PI_MANY, and both slots: the
        dec     hl                      ; walk finds everyone
        ld      (hl),0FFh
        dec     hl
        ld      (hl),0FFh
        ld      hl,K_PROC
        ld      b,NPROC-1
.next0: ld      a,l
        add     a,P_SIZE
        ld      l,a
        push    bc
        call    .row
        pop     bc
        djnz    .next0
        ei
        ret
; .row — HL = a process row: into the ring if it is PS_PIPE on pipe C.
; Preserves HL, C.
.row:   ld      a,(hl)
        cp      PS_PIPE
        ret     nz
        ld      a,l
        rrca                            ; (pid << 4) >> 1 = pid << 3
        add     a,low K_PX
        ld      e,a
        ld      d,high K_PX
        ld      a,(de)                  ; PX_WCHAN
        cp      c
        ret     nz
        ld      (hl),PS_RUN
        push    bc
        call    sched_link              ; preserves HL, B
        pop     bc
        ld      a,(k_pwait)
        dec     a
        ld      (k_pwait),a
        ret

; pipe_ref — A = a pipe end's descriptor code: one more reader or writer.
; pipe_unref — the same, one fewer, and the pipe's waiters woken: the last
; writer's leaving is a reader's EOF, the last reader's a writer's end.
; Both preserve HL, BC; corrupt AF, DE.
pipe_ref:
        push    hl
        push    bc
        call    pi_count
        inc     (hl)
        pop     bc
        pop     hl
        ret
pipe_unref:
        push    hl
        push    bc
        call    pi_count
        dec     (hl)
        ld      a,(pp_n)
        call    pipe_wake
        pop     bc
        pop     hl
        ret

; pi_count — A = a pipe end's code: HL -> its PI_READERS or PI_WRITERS,
; (pp_n) = the pipe. Corrupts AF, C, DE.
pi_count:
        ld      c,a
        and     0Fh
        ld      (pp_n),a
        call    pi_row
        ld      de,PI_READERS
        add     hl,de
        bit     4,c                     ; FD_PIPE_W has it, FD_PIPE_R not
        ret     z
        inc     hl                      ; PI_WRITERS
        ret

k_pipe:         ds NPIPE*PI_SIZE        ; the rows: free when readers and
                                        ;   writers are both 0
k_pwait:        db 0                    ; rows in PS_PIPE
pp_n:           db 0                    ; the pipe a call is about
pp_row:         dw 0                    ;   its row
pp_buf:         dw 0                    ;   the process's buffer, advancing
pp_len:         dw 0                    ;   bytes still asked for
pp_total:       dw 0                    ;   write: bytes asked for
pp_cnt:         dw 0            ;   this piece, 1-256
pc_first:       db 0            ; a copy's first piece, to the wrap
pc_second:      dw 0            ;   and its second
pp_end:         db 0                    ; pi_block: the end's waiter slot
pp_slot:        dw 0                    ; pipe: the first descriptor's byte
pp_fd:          db 0                    ;   its number
