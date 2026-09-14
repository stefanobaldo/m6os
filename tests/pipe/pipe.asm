; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; pipe — the pipeline path in the kernel: pipes, processes created from a
; file with their descriptors chosen, waitpid, sleep, getcwd, chmod, time
; and procinfo. Under Nextor: find the driver behind the current drive,
; capture what the resident needs, hand the machine over. Then the block
; below runs as process 0 and drives programs on the volume through
; spawnv — the ones in progs/ — reading the kernel's tables directly for
; what a syscall does not show. The report is on screen, the verdict in
; the mailbox; the harness (pipe.tcl) exports the pipeline's output file,
; turns the two timed steps into figures for the log and checks the
; clock's reading against the host's. Block steps 5-19 are the design's
; steps 1-15, in that order.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "m6prog.inc"
        include "build/kernel.exp"

_STROUT     equ 09h
_CURDRV     equ 19h
_TERM       equ 62h

CALSLT      equ B_CALSLT

        org     100h

start:
        ld      sp,KT_LSTACK
        ld      a,DBG_ASCII
        out     (DBG_MODE),a

; --- step 0: SCREEN 0 at 80 columns ------------------------------------
        call    ld_screen80
        ld      de,banner
        call    puts

; --- step 1: a Nextor 2 kernel ----------------------------------------
        ld      a,1
        ld      (step),a
        call    ld_nextor2
        jp      nz,fail

; --- step 2: the driver behind the current drive ----------------------
        ld      a,2
        ld      (step),a
        ld      de,s_drive
        call    puts
        ld      c,_CURDRV
        call    BDOS
        ld      (drive),a
        add     a,'A'
        call    putc
        ld      a,(drive)
        ld      ix,REC+KR_DRV
        ld      hl,KT_SCRATCH
        call    nx_find
        or      a
        jp      nz,fail
        ld      (REC+KR_FIRST),hl
        ld      (REC+KR_FIRST+2),de
        call    newline

; --- step 3: capture, the driver table included -----------------------
        ld      a,3
        ld      (step),a
        ld      de,s_capture
        call    puts
        ld      ix,REC
        call    nx_capture
        ld      hl,(REC+KR_WALL)
        call    puthex16
        ld      de,s_drivers
        call    puts
        ld      a,(REC+KR_NDRV)
        call    putdec
        ld      a,(REC+KR_NDRV)
        or      a
        ld      a,0F6h                  ; no driver in the table
        jp      z,fail
        call    newline

; --- the takeover -----------------------------------------------------
        ld      de,s_takeover
        call    puts
        ld      hl,t_entry
        ld      (REC+KR_TEST),hl
        xor     a
        ld      (REC+KR_MEMCAP),a
        ld      hl,ksimage
        ld      (REC+KR_KSEG_SRC),hl
        ld      hl,ksimage_end-ksimage
        ld      (REC+KR_KSEG_LEN),hl
        call    ld_takeover
        jp      fail                    ; it returns only with A = F3h

; fail — A = error code, (step) = the step that failed.
fail:
        push    af
        call    newline
        ld      de,s_fail
        call    puts
        ld      a,(step)
        call    putdec
        ld      de,s_code
        call    puts
        pop     af
        call    puthex8
        call    newline
        m6_verdict M6_FAIL
        ld      b,1
        ld      c,_TERM
        jp      BDOS

; --- console helpers, through the BDOS, echoed to the debug device -----
puts:   push    de
.echo:  ld      a,(de)
        cp      '$'
        jr      z,.out
        out     (DBG_DATA),a
        inc     de
        jr      .echo
.out:   pop     de
        ld      c,_STROUT
        jp      BDOS

putc:   push    hl
        push    de
        push    bc
        ld      (chbuf),a
        ld      de,chbuf
        call    puts
        pop     bc
        pop     de
        pop     hl
        ret

newline:
        ld      a,13
        call    putc
        ld      a,10
        jp      putc

puthex16:
        ld      a,h
        call    puthex8
        ld      a,l
puthex8:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    .nib
        pop     af
.nib:   and     0Fh
        add     a,'0'
        cp      '9'+1
        jr      c,putc
        add     a,'A'-'9'-1
        jr      putc

putdec:
        ld      l,a
        ld      h,0
        xor     a
        ld      (leading),a
        ld      de,100
        call    .digit
        ld      de,10
        call    .digit
        ld      a,l
        add     a,'0'
        jp      putc
.digit: ld      a,'0'-1
.sub:   inc     a
        or      a
        sbc     hl,de
        jr      nc,.sub
        add     hl,de
        cp      '0'
        jr      nz,.emit
        push    af
        ld      a,(leading)
        or      a
        jr      nz,.zero
        pop     af
        ret
.zero:  pop     af
.emit:  ld      (leading),a
        jp      putc

banner:     db  "pipe: pipes, spawnv and the small calls",13,10,'$'
s_drive:    db  "2 drive $"
s_capture:  db  "3 wall $"
s_drivers:  db  "h drivers $"
s_takeover: db  "-- taking the machine --",13,10,'$'
s_fail:     db  "FAIL step $"
s_code:     db  " code $"
chbuf:      db  0,'$'
step:       db  0
drive:      db  0
leading:    db  0
REC:        ds  KREC_SIZE

nx_enaslt   equ ENASLT
nx_ramslot1 equ RAMAD1
        include "nextor/abi2.asm"
        include "nextor/capture.asm"

ld_image    equ kimage
ld_rec      equ REC
ld_block    equ 0                   ; nothing above the image: the block
ld_block_len equ 0                  ; runs where it lies, in page 1
        include "loader/takeover.asm"

; Everything above runs, or is read, while a driver call or an inter-slot
; call may have switched page 1 away, so it stays in page 0; the two images
; and the block below are only copied once page 1 is RAM again, and may
; extend into it, never into page 2, where the tests' buffers are.
        ASSERT  $ < 4000h
kimage:
        incbin  "build/kernel.bin"
kimage_end:
ksimage:
        incbin  "build/kseg.bin"
ksimage_end:
        ASSERT  ksimage_end < 8000h

; The second half, in page 1 of the loader's memory, which the kernel
; keeps as process 0's page 1 so the block runs where it lies. It runs
; once the kernel has booted and mounted the volumes, as process 0, and
; calls the kernel the way a program does, through K_SYS — except that
; process 0 may not read or write a pipe, so every transfer is a program's
; and the block wires the ends and waits. Its paths and buffers are in
; page 1, which the switched part reaches through k_copy.
tblock:
        ASSERT  tblock >= 4000h         ; in page 1: the loader's boot segment,
                                        ; which the kernel keeps as process 0's

; t_begin n, s — the step number and its title.
    macro t_begin Q1, Q2
        ld      a,Q1
        ld      (t_step),a
        xor     a
        ld      (t_at),a
        ld      hl,Q2
        k_call  API_CON_PUTS
    endm
; t_at n — the point within a step, printed by t_fail after the code.
    macro t_at Q1
        ld      a,Q1
        ld      (t_at),a
    endm
; t_spawn path, argv, map — spawnv, A = the pid, or the test fails.
    macro t_spawn Q1, Q2, Q3
        ld      hl,Q1
        ld      de,Q2
        ld      bc,Q3
        call    t_spawn_hl
    endm
; t_exec path, argv, map — spawnv and waitpid: A = the status.
    macro t_exec Q1, Q2, Q3
        ld      hl,Q1
        ld      de,Q2
        ld      bc,Q3
        call    t_exec_hl
    endm

t_entry:
; --- step 5: the pipe's basics, from a process ---------------------------
        t_begin 5, t_k5
        sys     SYS_PIPE                ; two pipes held here, so that the
        jp      c,t_fail                ; program finds the table full
        ld      (t_p1),hl
        sys     SYS_PIPE
        jp      c,t_fail
        ld      (t_p2),hl
        t_exec  p_pp1, av_none, m_inh
        or      a
        jp      nz,t_fail_status
        call    t_close_p1
        ld      hl,(t_p2)
        ld      (t_p1),hl
        call    t_close_p1
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 6: a reader blocks on an empty pipe, a writer fills it -----------
        t_begin 6, t_k6
        t_at    1
        sys     SYS_PIPE
        jp      c,t_fail
        ld      (t_p1),hl
        ld      a,l
        ld      (t_map),a               ; cons: 0 = the read end
        ld      a,0FFh
        ld      (t_map+1),a
        ld      (t_map+2),a
        t_at    2
        t_spawn p_cons, av_none, t_map
        ld      (t_pid1),a
        t_at    3
        ld      hl,3
        sys     SYS_SLEEP               ; cons runs, and blocks on nothing
        t_at    4
        ld      a,(t_pid1)
        ld      hl,t_pi
        sys     SYS_PROCINFO
        jp      c,t_fail
        ld      a,(t_pi+P_STATE)
        cp      PS_PIPE
        ld      a,0E1h
        jp      nz,t_fail               ; cons is not blocked on a pipe
        ld      a,(t_p1)
        call    t_pipe_idx              ; the pipe behind the read end
        ld      hl,t_pi+P_SIZE+PX_WCHAN
        cp      (hl)
        ld      a,0E2h
        jp      nz,t_fail               ; not on this pipe
        ld      a,0FFh
        ld      (t_map),a
        ld      a,(t_p1+1)
        ld      (t_map+1),a             ; prod: 1 = the write end
        t_at    5
        t_spawn p_prod, av_none, t_map
        ld      (t_pid2),a
        t_at    6
        call    t_close_p1
        t_at    7
        ld      a,(t_pid2)
        call    t_wait_a
        or      a
        jp      nz,t_fail_status
        t_at    8
        ld      a,(t_pid1)
        call    t_wait_a
        or      a
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 7: 64 KB through a pipe, timed ----------------------------------
; With the pair that does nothing per byte (prodf, consf), so that the
; ticks are the pipe's two copies and two switches per 255 bytes and not
; the programs' own loops: cons's byte check alone costs more than the
; kernel's copy.
        t_begin 7, t_k7
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        sys     SYS_PIPE
        jp      c,t_fail
        ld      (t_p1),hl
        ld      a,l
        ld      (t_map),a
        ld      a,0FFh
        ld      (t_map+1),a
        ld      (t_map+2),a
        t_spawn p_consf, av_none, t_map
        ld      (t_pid1),a
        ld      a,0FFh
        ld      (t_map),a
        ld      a,(t_p1+1)
        ld      (t_map+1),a
        t_spawn p_prodf, av_none, t_map
        ld      (t_pid2),a
        call    t_close_p1
        ld      a,(t_pid2)
        call    t_wait_a
        or      a
        jp      nz,t_fail_status
        ld      a,(t_pid1)
        call    t_wait_a
        or      a
        jp      nz,t_fail_status
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        k_call  API_CON_DEC16
        ld      hl,t_ticks
        k_call  API_CON_PUTS

; --- step 8: a writer whose reader has gone ------------------------------
        t_begin 8, t_k8
        sys     SYS_PIPE
        jp      c,t_fail
        ld      (t_p1),hl
        ld      a,0FFh
        ld      (t_map),a
        ld      (t_map+2),a
        ld      a,h
        ld      (t_map+1),a             ; w141: 1 = the write end
        t_spawn p_w141, av_none, t_map
        ld      (t_pid1),a
        ld      a,(t_p1)
        call    t_pipe_idx
        ld      (t_n),a                 ; the pipe, before its ends go
        call    t_close_p1              ; both ends here: no reader is left
        ld      a,(t_pid1)
        call    t_wait_a
        cp      141
        jp      nz,t_fail_status
        ld      a,(t_n)
        call    t_pipe_row              ; hl -> the row: empty, nobody's
        ld      a,(hl)                  ; PI_HEAD: nothing was written
        inc     hl
        or      (hl)                    ; PI_TAIL
        inc     hl
        or      (hl)                    ; PI_FULL
        inc     hl
        or      (hl)                    ; PI_READERS
        inc     hl
        or      (hl)                    ; PI_WRITERS
        ld      a,0E3h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 9: inheritance: the child gets 0-2 and nothing else --------------
        t_begin 9, t_k9
        sys     SYS_PIPE
        jp      c,t_fail
        ld      (t_p1),hl
        ld      hl,p_inh
        ld      a,O_WRONLY|O_CREAT|O_TRUNC
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      a,0FFh
        ld      (t_map),a
        ld      (t_map+2),a
        ld      a,(t_p1+1)
        ld      (t_map+1),a             ; gen: 1 = the write end
        t_spawn p_gen, av_none, t_map
        ld      (t_pid1),a
        ld      a,(t_p1)
        ld      (t_map),a               ; sum: 0 = the read end,
        ld      a,(t_fd)
        ld      (t_map+1),a             ; 1 = the file
        ld      a,0FFh
        ld      (t_map+2),a
        t_spawn p_sum, av_none, t_map
        ld      (t_pid2),a
        ; Their descriptor rows, while they live: gen's 1 is the write
        ; end, sum's 0 the read end and 1 a file; 3-7 closed in both.
        ld      a,(t_p1)
        call    t_pipe_idx
        ld      (t_n),a                 ; the pipe
        ld      a,(t_pid1)
        call    t_fd_row
        inc     hl
        ld      a,(t_n)
        or      FD_PIPE_W
        cp      (hl)
        ld      a,0E4h
        jp      nz,t_fail
        dec     hl
        call    t_fds_closed
        ld      a,0E5h
        jp      nz,t_fail
        ld      a,(t_pid2)
        call    t_fd_row
        ld      a,(t_n)
        or      FD_PIPE_R
        cp      (hl)
        ld      a,0E6h
        jp      nz,t_fail
        inc     hl
        ld      a,(hl)
        cp      80h
        ld      a,0E7h
        jp      nc,t_fail               ; sum's 1 is not an open file
        dec     hl
        call    t_fds_closed
        ld      a,0E8h
        jp      nz,t_fail
        call    t_close_p1
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jp      c,t_fail
        ld      a,(t_pid1)
        call    t_wait_a
        or      a
        jp      nz,t_fail_status
        ld      a,(t_pid2)              ; would never return if sum held
        call    t_wait_a                ; the write end too
        or      a
        jp      nz,t_fail_status
        ld      hl,p_inh
        ld      de,s_5050
        call    t_file_is
        ld      a,0E9h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 10: spawnv: arguments, the map, every refusal ---------------------
        t_begin 10, t_k10
        t_exec  p_hello, av_hello, m_inh
        cp      7
        jp      nz,t_fail_status
        ; wr1 abc, its 1 a file: the file holds "abc\n".
        ld      hl,p_wr1txt
        ld      a,O_WRONLY|O_CREAT|O_TRUNC
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      (t_map+1),a
        ld      a,0FFh
        ld      (t_map),a
        ld      (t_map+2),a
        t_exec  p_wr1, av_wr1, t_map
        or      a
        jp      nz,t_fail_status
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jp      c,t_fail
        ld      hl,p_wr1txt
        ld      de,s_abc
        call    t_file_is
        ld      a,0EAh
        jp      nz,t_fail
        ; rd0, its 0 that file and its 1 another: a copy.
        ld      hl,p_wr1txt
        xor     a
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      (t_map),a
        ld      hl,p_rd0txt
        ld      a,O_WRONLY|O_CREAT|O_TRUNC
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd2),a
        ld      (t_map+1),a
        t_exec  p_rd0, av_none, t_map
        or      a
        jp      nz,t_fail_status
        ld      a,(t_fd)
        sys     SYS_CLOSE
        ld      a,(t_fd2)
        sys     SYS_CLOSE
        ld      hl,p_rd0txt
        ld      de,s_abc
        call    t_file_is
        ld      a,0EBh
        jp      nz,t_fail
        ; A closed descriptor in the map: EBADF, and no process was made.
        ld      a,7
        ld      (t_map),a
        ld      a,0FFh
        ld      (t_map+1),a
        ld      (t_map+2),a
        ld      hl,p_tiny
        ld      de,av_none
        ld      bc,t_map
        xor     a                       ; the child's signals: the caller's
        sys     SYS_SPAWNV
        ld      b,E_BADF
        ld      c,0ECh
        call    t_expect
        call    t_rows_free
        ld      a,0EDh
        jp      nz,t_fail
        ; A program that asks for the kernel's page as its buffer: refused
        ; on a file, a pipe and procinfo alike, and it exits 0.
        t_exec  p_badbuf, av_none, m_inh
        or      a
        jp      nz,t_fail_status
        ; A path that is not there; a file that is not a program.
        ld      hl,p_none
        ld      de,av_none
        ld      bc,m_inh
        xor     a                       ; the child's signals: the caller's
        sys     SYS_SPAWNV
        ld      b,E_NOENT
        ld      c,0EEh
        call    t_expect
        ld      hl,p_notm6
        ld      de,av_none
        ld      bc,m_inh
        xor     a                       ; the child's signals: the caller's
        sys     SYS_SPAWNV
        ld      b,E_NOEXEC
        ld      c,0F0h
        call    t_expect
        ; The limits: with fifteen free segments the sixteenth process is
        ; EAGAIN; with fewer, the one past the free count is ENOMEM.
        ld      hl,SC_SEGMENTS_FREE
        sys     SYS_SYSCONF
        jp      c,t_fail
        ld      a,l
        cp      NPROC-1
        jr      c,.fewer
        ld      a,NPROC-1
        ld      (t_n),a
        ld      a,E_AGAIN
        jr      .limit
.fewer: ld      (t_n),a
        ld      a,E_NOMEM
.limit: ld      (t_want),a
.spawn: t_spawn p_nap, av_nap30, m_inh
        ld      hl,t_n
        dec     (hl)
        jr      nz,.spawn
        ld      hl,p_nap
        ld      de,av_nap30
        ld      bc,m_inh
        xor     a                       ; the child's signals: the caller's
        sys     SYS_SPAWNV
        ld      a,(t_want)
        ld      b,a
        ld      c,0F2h
        call    t_expect
.reap:  xor     a
        ld      b,a
        sys     SYS_WAITPID
        jr      c,.reaped
        ld      a,l
        cp      30
        jp      nz,t_fail_status
        jr      .reap
.reaped:
        cp      E_CHILD
        ld      a,0F4h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 11: sixty spawnv of a one-sector program, timed -----------------
        t_begin 11, t_k11
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      a,60
        ld      (t_n),a
.tiny:  t_exec  p_tiny, av_none, m_inh
        or      a
        jp      nz,t_fail_status
        ld      hl,t_n
        dec     (hl)
        jr      nz,.tiny
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        k_call  API_CON_DEC16
        ld      hl,t_ticks
        k_call  API_CON_PUTS

; --- step 12: waitpid by name, WNOHANG, ECHILD --------------------------------
        t_begin 12, t_k12
        t_spawn p_nap, av_nap10, m_inh
        ld      (t_pid1),a
        t_spawn p_tiny, av_none, m_inh
        ld      (t_pid2),a              ; exits at once: a zombie meanwhile
        ld      a,(t_pid1)
        ld      b,0
        sys     SYS_WAITPID
        jp      c,t_fail
        ld      a,(t_pid1)
        cp      h
        ld      a,0E1h
        jp      nz,t_fail               ; another child came back
        ld      a,l
        cp      10
        jp      nz,t_fail_status
        xor     a
        ld      b,a
        sys     SYS_WAITPID
        jp      c,t_fail
        ld      a,(t_pid2)
        cp      h
        ld      a,0E2h
        jp      nz,t_fail
        ld      a,l
        or      a
        jp      nz,t_fail_status
        t_spawn p_nap, av_nap20, m_inh
        ld      (t_pid1),a
        xor     a
        ld      b,WNOHANG
        sys     SYS_WAITPID
        jp      c,t_fail
        ld      a,h
        or      l
        ld      a,0E3h
        jp      nz,t_fail               ; WNOHANG returned a live child
        ld      a,(t_pid1)
        call    t_wait_a
        cp      20
        jp      nz,t_fail_status
        ld      a,NPROC-1
        ld      b,0
        sys     SYS_WAITPID
        ld      b,E_CHILD
        ld      c,0E4h
        call    t_expect
        xor     a
        ld      b,a
        sys     SYS_WAITPID
        ld      b,E_CHILD
        ld      c,0E6h
        call    t_expect
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 13: sleep --------------------------------------------------------
        t_begin 13, t_k13
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      hl,30
        sys     SYS_SLEEP
        jp      c,t_fail
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        ld      a,h
        or      a
        ld      a,0E1h
        jp      nz,t_fail
        ld      a,l
        cp      30
        jr      z,.slept
        cp      31
        ld      a,0E1h
        jp      nz,t_fail               ; not 30 or 31 ticks
.slept: t_spawn p_nap, av_nap20, m_inh
        ld      (t_pid1),a
        t_spawn p_nap, av_nap10, m_inh
        ld      (t_pid2),a
        xor     a
        ld      b,a
        sys     SYS_WAITPID
        jp      c,t_fail
        ld      a,(t_pid2)
        cp      h
        ld      a,0E2h
        jp      nz,t_fail               ; the longer sleeper came first
        ld      a,l
        cp      10
        jp      nz,t_fail_status
        ld      a,(t_pid1)
        call    t_wait_a
        cp      20
        jp      nz,t_fail_status
        ld      hl,0
        sys     SYS_SLEEP
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 14: getcwd -------------------------------------------------------
        t_begin 14, t_k14
        ld      de,s_root
        call    t_cwd_is
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,p_abc
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      de,p_abc
        call    t_cwd_is
        ld      a,0E2h
        jp      nz,t_fail
        ld      hl,p_mntbd
        sys     SYS_MKDIR
        jp      c,t_fail
        ld      hl,p_mntbd
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      de,p_mntbd
        call    t_cwd_is
        ld      a,0E3h
        jp      nz,t_fail
        ld      hl,p_mnt
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      de,p_mnt
        call    t_cwd_is
        ld      a,0E4h
        jp      nz,t_fail
        ld      hl,p_abc
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,t_buf
        ld      bc,4
        sys     SYS_GETCWD
        ld      b,E_NAMETOOLONG
        ld      c,0E5h
        call    t_expect
        ld      hl,p_root
        sys     SYS_CHDIR
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 15: chmod --------------------------------------------------------
        t_begin 15, t_k15
        ld      hl,p_rotxt
        ld      a,O_WRONLY|O_CREAT
        sys     SYS_OPEN
        jp      c,t_fail
        sys     SYS_CLOSE
        jp      c,t_fail
        ld      hl,p_rotxt
        ld      a,DA_RDONLY
        sys     SYS_CHMOD
        jp      c,t_fail
        ld      hl,p_rotxt
        sys     SYS_UNLINK
        ld      b,E_ACCES
        ld      c,0E1h
        call    t_expect
        ld      hl,p_rotxt
        ld      de,t_rec
        sys     SYS_STAT
        jp      c,t_fail
        ld      a,(t_rec+DE_ATTR)
        cp      DA_RDONLY
        ld      a,0E3h
        jp      nz,t_fail
        ld      hl,p_rotxt
        ld      a,DA_ARCHIVE
        sys     SYS_CHMOD
        jp      c,t_fail
        ld      hl,p_rotxt
        ld      de,t_rec
        sys     SYS_STAT
        jp      c,t_fail
        ld      a,(t_rec+DE_ATTR)
        cp      DA_ARCHIVE
        ld      a,0E4h
        jp      nz,t_fail
        ld      hl,p_rotxt
        sys     SYS_UNLINK
        jp      c,t_fail
        ld      hl,p_notm6
        ld      a,DA_DIR
        sys     SYS_CHMOD
        ld      b,E_INVAL
        ld      c,0E5h
        call    t_expect
        ld      hl,p_root
        ld      a,DA_ARCHIVE
        sys     SYS_CHMOD
        ld      b,E_ACCES
        ld      c,0E7h
        call    t_expect
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 16: procinfo and time --------------------------------------------
        t_begin 16, t_k16
        xor     a
        ld      hl,t_pi
        sys     SYS_PROCINFO
        jp      c,t_fail
        ld      a,(t_pi+P_STATE)
        cp      PS_RUN
        ld      a,0E1h
        jp      nz,t_fail
        ld      a,(t_pi+P_PID)
        or      a
        ld      a,0E2h
        jp      nz,t_fail
        ld      a,NPROC-1
        ld      hl,t_pi
        sys     SYS_PROCINFO
        ld      b,E_SRCH
        ld      c,0E3h
        call    t_expect
        ld      a,NPROC
        ld      hl,t_pi
        sys     SYS_PROCINFO
        ld      b,E_INVAL
        ld      c,0E5h
        call    t_expect
        sys     SYS_TIME
        jp      c,t_fail
        push    de
        push    hl
        k_call  API_CON_HEX16           ; the date word
        ld      a,' '
        k_call  API_CON_PUTC
        pop     hl
        pop     de
        push    hl
        ex      de,hl
        k_call  API_CON_HEX16           ; the time word
        pop     hl
        ld      a,h
        cp      (2026-1980) << 1        ; year >= 2026: the field's high byte
        ld      a,0E7h
        jp      c,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 17: a three-program pipeline into a file --------------------------
        t_begin 17, t_k17
        sys     SYS_PIPE
        jp      c,t_fail
        ld      (t_p1),hl
        sys     SYS_PIPE
        jp      c,t_fail
        ld      (t_p2),hl
        ld      hl,p_out
        ld      a,O_WRONLY|O_CREAT|O_TRUNC
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      a,0FFh
        ld      (t_map),a
        ld      (t_map+2),a
        ld      a,(t_p1+1)
        ld      (t_map+1),a             ; gen | ...
        t_spawn p_gen, av_none, t_map
        ld      (t_pid1),a
        ld      a,(t_p1)
        ld      (t_map),a
        ld      a,(t_p2+1)
        ld      (t_map+1),a             ; ... | filt | ...
        t_spawn p_filt, av_none, t_map
        ld      (t_pid2),a
        ld      a,(t_p2)
        ld      (t_map),a
        ld      a,(t_fd)
        ld      (t_map+1),a             ; ... | sum > /out.txt
        t_spawn p_sum, av_none, t_map
        ld      (t_pid3),a
        call    t_close_p1
        ld      hl,(t_p2)
        ld      (t_p1),hl
        call    t_close_p1
        ld      a,(t_fd)
        sys     SYS_CLOSE
        jp      c,t_fail
        ld      a,(t_pid1)
        call    t_wait_a
        or      a
        jp      nz,t_fail_status
        ld      a,(t_pid2)
        call    t_wait_a
        or      a
        jp      nz,t_fail_status
        ld      a,(t_pid3)
        call    t_wait_a
        or      a
        jp      nz,t_fail_status
        ld      hl,p_out
        ld      de,s_2500
        call    t_file_is
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- verdict --------------------------------------------------------------
        ld      hl,t_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
        jr      t_halt

; t_fail — A = error code, (t_step) = the step.
t_fail:
        push    af
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_step)
        call    k_dec8
        ld      hl,t_code
        k_call  API_CON_PUTS
        pop     af
        k_call  API_CON_HEX8
        ld      hl,t_atstr
        k_call  API_CON_PUTS
        ld      a,(t_at)
        call    k_dec8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
t_halt: ei
        halt
        jr      t_halt

; t_fail_status — A = a child's exit status that was not the one expected.
t_fail_status:
        push    af
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_step)
        call    k_dec8
        ld      hl,t_status
        k_call  API_CON_PUTS
        pop     af
        call    k_dec8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
        jr      t_halt

; t_spawn_hl — HL = a path, DE = argv, BC -> the map: spawnv; A = the
; pid. A refusal is a failure of the test.
t_spawn_hl:
        xor     a                       ; the child's signals: the caller's
        sys     SYS_SPAWNV
        jp      c,t_fail
        ret

; t_wait_a — A = a pid: waitpid, A = its status; a refusal fails the test.
t_wait_a:
        ld      b,0
        sys     SYS_WAITPID
        jp      c,t_fail
        ld      a,l
        ret

; t_exec_hl — t_spawn_hl, then t_wait_a: A = the status.
t_exec_hl:
        call    t_spawn_hl
        jr      t_wait_a

; t_expect — after a syscall: CF must be set with A = B, else fail with
; code C (C+1 when the call succeeded). Preserves nothing.
t_expect:
        jr      c,.failed
        inc     c
        ld      a,c
        jp      t_fail
.failed:
        cp      b
        ret     z
        ld      a,c
        jp      t_fail

; t_close_p1 — both ends of the pipe (t_p1) closed here.
t_close_p1:
        ld      a,(t_p1)
        sys     SYS_CLOSE
        jp      c,t_fail
        ld      a,(t_p1+1)
        sys     SYS_CLOSE
        jp      c,t_fail
        ret

; t_pipe_idx — A = one of this process's descriptors, a pipe end: A = the
; pipe's index, from the descriptor's byte in the kernel's table.
t_pipe_idx:
        ld      l,a
        ld      h,high K_FD             ; process 0's row is the first
        ld      a,(hl)
        and     0Fh
        ret

; t_pipe_row — A = a pipe index: HL -> its row in the kernel's table.
t_pipe_row:
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      h,0
        ld      de,K_PIPE_TAB
        add     hl,de
        ret

; t_fd_row — A = a pid: HL -> its descriptor row.
t_fd_row:
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      h,high K_FD
        ret

; t_fds_closed — HL -> a descriptor row: Z if its 3-7 are all FD_NONE.
t_fds_closed:
        push    hl
        ld      de,3
        add     hl,de
        ld      b,NOFILE-3
.fd:    ld      a,(hl)
        cp      FD_NONE
        jr      nz,.no
        inc     hl
        djnz    .fd
.no:    pop     hl
        ret

; t_rows_free — Z if every row but 0 is PS_FREE.
t_rows_free:
        ld      hl,K_PROC
        ld      b,NPROC-1
.row:   ld      a,l
        add     a,P_SIZE
        ld      l,a
        ld      a,(hl)
        or      a
        ret     nz
        djnz    .row
        ret

; t_file_is — HL = a path, DE = a 0-terminated string: Z if the file holds
; exactly that string. A syscall's refusal fails the test.
t_file_is:
        push    de
        xor     a
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd3),a
        ld      hl,t_buf
        ld      bc,63
        sys     SYS_READ
        jp      c,t_fail
        ld      de,t_buf
        add     hl,de
        ld      (hl),0
        ld      a,(t_fd3)
        sys     SYS_CLOSE
        pop     de
        ld      hl,t_buf
        jr      t_streq

; t_cwd_is — DE = a string: Z if getcwd answers it, with the length right.
t_cwd_is:
        push    de
        ld      hl,t_buf
        ld      bc,64
        sys     SYS_GETCWD
        jp      c,t_fail
        pop     de
        push    de
        push    hl
        ex      de,hl
        ld      bc,0
.len:   ld      a,(hl)
        or      a
        jr      z,.gotlen
        inc     hl
        inc     bc
        jr      .len
.gotlen:
        pop     hl
        or      a
        sbc     hl,bc
        pop     de
        ret     nz                      ; the length is wrong
        ld      hl,t_buf
; t_streq — the 0-terminated strings at HL and DE: Z if equal.
t_streq:
        ld      a,(de)
        cp      (hl)
        ret     nz
        or      a
        ret     z
        inc     hl
        inc     de
        jr      t_streq

        include "m6util.asm"

t_k5:       db  "5 pipe basics: ",0
t_k6:       db  "6 a reader blocked, then fed: ",0
t_k7:       db  "7 pipe: 64K in ",0
t_k8:       db  "8 a writer with no reader: ",0
t_k9:       db  "9 the child gets 0-2 and nothing else: ",0
t_k10:      db  "10 spawnv: ",0
t_k11:      db  "11 spawnv: 60 in ",0
t_k12:      db  "12 waitpid: ",0
t_k13:      db  "13 sleep: ",0
t_k14:      db  "14 getcwd: ",0
t_k15:      db  "15 chmod: ",0
t_k16:      db  "16 procinfo, time ",0
t_k17:      db  "17 gen | filt | sum > /out.txt: ",0
t_ticks:    db  " ticks",10,0
t_ok:       db  "ok",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_code:     db  " code ",0
t_status:   db  " status ",0
t_atstr:    db  " at ",0
p_pp1:      db  "/bin/pp1",0
p_cons:     db  "/bin/cons",0
p_prod:     db  "/bin/prod",0
p_consf:    db  "/bin/consf",0
p_prodf:    db  "/bin/prodf",0
p_w141:     db  "/bin/w141",0
p_gen:      db  "/bin/gen",0
p_filt:     db  "/bin/filt",0
p_sum:      db  "/bin/sum",0
p_hello:    db  "/bin/hello",0
p_wr1:      db  "/bin/wr1",0
p_rd0:      db  "/bin/rd0",0
p_tiny:     db  "/bin/tiny",0
p_badbuf:   db  "/bin/badbuf",0
p_nap:      db  "/bin/nap",0
p_none:     db  "/bin/nothere",0
p_notm6:    db  "/notm6.bin",0
p_inh:      db  "/inh.txt",0
p_wr1txt:   db  "/wr1.txt",0
p_rd0txt:   db  "/rd0.txt",0
p_out:      db  "/out.txt",0
p_rotxt:    db  "/ro.txt",0
p_abc:      db  "/a/b/c",0
p_mntbd:    db  "/mnt/b/d",0
p_mnt:      db  "/mnt",0
p_root:     db  "/",0
s_root      equ p_root
s_5050:     db  "5050",10,0
s_2500:     db  "2500",10,0
s_abc:      db  "abc",10,0
av_none:    dw  0
av_hello:   dw  p_hello,s_one,s_two,0
s_one:      db  "one",0
s_two:      db  "two",0
av_wr1:     dw  p_wr1,s_abcarg,0
s_abcarg:   db  "abc",0
av_nap10:   dw  p_nap,s_10,0
av_nap20:   dw  p_nap,s_20,0
av_nap30:   dw  p_nap,s_30,0
s_10:       db  "10",0
s_20:       db  "20",0
s_30:       db  "30",0
m_inh:      db  0FFh,0FFh,0FFh
t_map:      ds  3
t_step:     db  0
t_at:       db  0
t_p1:       dw  0
t_p2:       dw  0
t_pid1:     db  0
t_pid2:     db  0
t_pid3:     db  0
t_fd:       db  0
t_fd2:      db  0
t_fd3:      db  0
t_n:        db  0
t_want:     db  0
t_t0:       dw  0
t_pi:       ds  PROCINFO_SIZE
t_rec:      ds  DIRENT_SIZE
t_buf:      ds  64
tblock_end:
        ASSERT  $ < 8000h
