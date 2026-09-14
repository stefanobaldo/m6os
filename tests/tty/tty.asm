; tty — the terminal: canonical mode on the keyboard, ttymode, kill,
; signal, the four signals and ^C. Under Nextor: find the driver behind
; the current drive, capture what the resident needs, hand the machine
; over. Then the block below runs as process 0 and drives programs on the
; volume through spawnv — the ones in progs/ — while the harness (tty.tcl)
; presses keys on the matrix at the cues the block leaves in the storage
; segment; on real hardware a person presses them. The block reads the
; kernel's tables directly for what a syscall does not show. The report is
; on screen, the verdict in the mailbox; the harness reads the screen for
; the echo and the test shell's report. Block steps 5-21 are the design's
; nine steps, each cut where a cue is needed.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "m6prog.inc"
        include "build/kernel.exp"

_STROUT     equ 09h
_CURDRV     equ 19h
_TERM       equ 62h

CALSLT      equ B_CALSLT

; The cue: three bytes in the storage segment, past the mailbox — the
; step, its complement and 5Ah — which the harness answers by zeroing the
; first. Three, because a child's page 2 shows other bytes through the
; same addresses while it runs, and one byte equal to a small number is
; not rare there.
CUE         equ MAILBOX+4
T_CUE_WAIT  equ 300             ; ticks a cue waits for the harness before
                                ; the block goes on by itself (a person)
T_WM_MAX    equ P0_FRAME        ; the handler's promise on a process's stack

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

banner:     db  "tty: the terminal, kill, signal and ^C",13,10,'$'
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
; calls the kernel the way a program does, through K_SYS. Process 0 takes
; no signal and reads the keyboard only to drain it, so every reader and
; every victim below is a program.
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
; t_cue n — the cue, then wait for the harness to answer it.
    macro t_cue Q1
        ld      a,Q1
        call    t_cue_a
    endm
; t_status n — the last child's status in A must be n.
    macro t_status Q1
        cp      Q1
        jp      nz,t_fail_status
    endm

t_entry:
; --- step 5: a line edited with BS and ^U ---------------------------------
        t_begin 5, t_k5
        t_cue   5                       ; a b BS c ^U h e l l o RET
        ld      hl,p_l1
        call    t_run_into              ; rdl, its 1 the file
        t_status 0
        ld      hl,p_l1
        ld      de,s_hello
        call    t_file_is
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 6: TAB is kept ----------------------------------------------------
        t_begin 6, t_k6
        t_cue   6                       ; x TAB y RET
        ld      hl,p_l2
        call    t_run_into
        t_status 0
        ld      hl,p_l2
        ld      de,s_xty
        call    t_file_is
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 7: a line read three bytes at a time waits once --------------------
        t_begin 7, t_k7
        t_cue   7                       ; h e l l o RET
        ld      hl,p_l3
        ld      de,p_rd3
        call    t_run_prog_into         ; rd3: exits with the ticks between
        cp      2                       ; its two reads: 0, or 1 at a boundary
        jp      nc,t_fail_status
        ld      hl,p_l3
        ld      de,s_hello
        call    t_file_is
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 8: ^D on an empty line is an end of file, once ----------------------
        t_begin 8, t_k8
        t_cue   8                       ; ^D, then z RET
        t_exec  p_rdeof, av_none, m_inh
        t_status 7                      ; 0 bytes
        t_exec  p_rdeof, av_none, m_inh
        t_status 2                      ; "z\n": the next read blocked and got a line
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 9: ttymode, and raw reads bytes as they come -------------------------
        t_begin 9, t_k9
        ld      a,TTY_RAW
        sys     SYS_TTYMODE
        jp      c,t_fail
        ld      a,l
        cp      TTY_CANON               ; what was
        ld      a,0E1h
        jp      nz,t_fail
        ld      a,TTY_RAW
        sys     SYS_TTYMODE
        jp      c,t_fail
        ld      a,l
        cp      TTY_RAW
        ld      a,0E2h
        jp      nz,t_fail
        ld      a,2
        sys     SYS_TTYMODE
        ld      b,E_INVAL
        ld      c,0E3h
        call    t_expect
        t_cue   9                       ; ESC RIGHT x
        ld      hl,p_l4
        ld      de,p_rawr
        call    t_run_prog_into
        t_status 0
        ld      hl,p_l4
        ld      de,s_escrx
        call    t_file_is
        ld      a,0E5h
        jp      nz,t_fail
        ld      a,TTY_CANON
        sys     SYS_TTYMODE
        jp      c,t_fail
        ld      a,l
        cp      TTY_RAW
        ld      a,0E6h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 10: canonical drops what is not a byte of the line ------------------
        t_begin 10, t_k10
        t_cue   10                      ; ESC RIGHT x RET
        ld      hl,p_l5
        call    t_run_into
        t_status 0
        ld      hl,p_l5
        ld      de,s_xnl
        call    t_file_is
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 11: the gate: ^C kills the foreground command, the shell reads on ---
        t_begin 11, t_k11
        t_cue   11                      ; spin RET, ^C, q RET
        t_exec  p_tsh, av_tsh, m_inh
        t_status 9                      ; tsh read q after the kill
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 12: ^C on a process blocked reading the keyboard -----------------
        t_begin 12, t_k12
        t_spawn p_rdr, av_none, m_inh
        ld      (t_pid1),a
        ld      hl,5
        sys     SYS_SLEEP               ; it blocks
        t_cue   12                      ; ^C
        ld      a,(t_pid1)
        call    t_wait_a
        t_status 128+SIGINT
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 13: ^C on a sleeper ---------------------------------------------
        t_begin 13, t_k13
        t_spawn p_slp, av_none, m_inh
        ld      (t_pid1),a
        ld      hl,5
        sys     SYS_SLEEP
        t_cue   13
        ld      a,(t_pid1)
        call    t_wait_a
        t_status 128+SIGINT
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 14: ^C on a writer blocked on a full pipe; then the counts ----------
        t_begin 14, t_k14
        sys     SYS_PIPE
        jp      c,t_fail
        ld      (t_p1),hl
        ld      a,0FFh
        ld      (t_map),a
        ld      (t_map+2),a
        ld      a,h
        ld      (t_map+1),a             ; pw: 1 = the write end
        t_spawn p_pw, av_none, t_map
        ld      (t_pid1),a
        ld      a,(t_p1+1)
        sys     SYS_CLOSE               ; only pw holds the write end now
        jp      c,t_fail
        ld      hl,5
        sys     SYS_SLEEP               ; pw fills the pipe and blocks
        t_at    1
        ld      a,(t_pid1)
        ld      hl,t_pi
        sys     SYS_PROCINFO
        jp      c,t_fail
        ld      a,(t_pi+P_STATE)
        cp      PS_PIPE
        ld      a,0E1h
        jp      nz,t_fail
        t_cue   14
        ld      a,(t_pid1)
        call    t_wait_a
        t_status 128+SIGINT
        ; What it wrote is still there: 256 bytes, then the end.
        t_at    2
        ld      a,(t_p1)
        ld      hl,t_buf256
        ld      bc,256
        call    t_read_pipe0            ; process 0 may not read a pipe:
        cp      1                       ; through a program, rd0-like (prd)
        jp      nz,t_fail_status
        t_at    3
        ld      a,(t_p1)
        sys     SYS_CLOSE
        jp      c,t_fail
        ; Nobody left blocked anywhere.
        t_at    4
        ld      a,(K_KBWAIT)
        ld      hl,K_NSLEEP
        or      (hl)
        ld      hl,K_PWAIT
        or      (hl)
        ld      a,0E4h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 15: ^C on a parent blocked in waitpid; its orphan is killed ----------
        t_begin 15, t_k15
        t_spawn p_wt, av_none, m_inh
        ld      (t_pid1),a
        ld      hl,5
        sys     SYS_SLEEP
        t_cue   15
        ld      a,(t_pid1)
        call    t_wait_a
        t_status 128+SIGINT
        ; Its child slp is an orphan now, asleep: kill sends it a SIGTERM
        ; and, with nobody to wait for it, its row is free at once.
        t_at    1
        ld      hl,K_PROC
        ld      b,NPROC-1
.orph:  ld      a,l
        add     a,P_SIZE
        ld      l,a
        ld      a,(hl)
        cp      PS_SLEEP
        jr      z,.found
        djnz    .orph
        ld      a,0E1h
        jp      t_fail                  ; no orphan asleep
.found: ld      (t_row),hl
        ld      a,l
        rrca
        rrca
        rrca
        rrca
        and     0Fh                     ; the pid
        ld      b,SIGTERM
        sys     SYS_KILL
        jp      c,t_fail
        ld      hl,4
        sys     SYS_SLEEP               ; it wakes into the stub and goes
        ld      hl,(t_row)
        ld      a,(hl)
        or      a                       ; PS_FREE: reaped by nobody
        ld      a,0E2h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 16: the handler's stack, and the byte a ^C nobody took becomes -------
        t_begin 16, t_k16
        t_cue   16                      ; ^C while wm spins, ignoring it
        t_exec  p_wm, av_none, m_inh
        ld      (t_n),a                 ; the watermark
        ld      l,a
        ld      h,0
        k_call  API_CON_DEC16
        ld      hl,t_bytes
        k_call  API_CON_PUTS
        ld      a,(t_n)
        cp      T_WM_MAX+1
        ld      c,a
        ld      a,0E1h
        jp      nc,t_fail_status        ; deeper than the promise
        ; The ^C nobody took is in the queue as 03h: a raw reader gets it.
        ld      a,TTY_RAW
        sys     SYS_TTYMODE
        t_exec  p_drain, av_none, m_inh
        t_status 3
        ld      a,TTY_CANON
        sys     SYS_TTYMODE
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 17: ^C during a long syscall: the process dies when it returns -----
        t_begin 17, t_k17
        t_cue   17                      ; ^C, 0.4 s after the cue — asked
                                        ; before rdf starts: inside its reads
                                        ; process 0 would hardly run, and the
                                        ; harness could not answer it
        t_spawn p_rdf, av_none, m_inh
        ld      (t_pid1),a
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      a,(t_pid1)
        call    t_wait_a
        push    af
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        ld      (t_t1),hl
        k_call  API_CON_DEC16
        ld      hl,t_ticks
        k_call  API_CON_PUTS
        pop     af
        t_status 128+SIGINT
        ; The ^C came 24 ticks after the cue; it died at the end of the
        ; read then in flight — not tens of seconds later, when a tick
        ; happened to find it between two reads.
        ld      hl,(t_t1)
        ld      de,90
        or      a
        sbc     hl,de
        ld      a,0E1h
        jp      nc,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 18: a ^C nobody takes, STOP, and the typeahead it discards --------------
        t_begin 18, t_k18
        t_cue   18                      ; ign RET, ^C, a b, STOP, q RET
        t_exec  p_tsh, av_tsh, m_inh
        t_status 9
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 19: kill and signal from a program ---------------------------------
        t_begin 19, t_k19
        t_exec  p_kt, av_none, m_inh
        t_status 128+SIGTERM            ; kt's last act is kill of itself
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 20: SIGPIPE ignored is EPIPE; not ignored, 141 -------------------------
        t_begin 20, t_k20
        sys     SYS_PIPE
        jp      c,t_fail
        ld      (t_p1),hl
        ld      a,0FFh
        ld      (t_map),a
        ld      (t_map+2),a
        ld      a,h
        ld      (t_map+1),a
        t_spawn p_wpipe, av_none, t_map
        ld      (t_pid1),a
        call    t_close_p1              ; no reader is left
        ld      a,(t_pid1)
        call    t_wait_a
        t_status 0                      ; EPIPE, and it went on
        sys     SYS_PIPE
        jp      c,t_fail
        ld      (t_p1),hl
        ld      a,h
        ld      (t_map+1),a
        t_spawn p_w141, av_none, t_map
        ld      (t_pid1),a
        call    t_close_p1
        ld      a,(t_pid1)
        call    t_wait_a
        t_status 128+SIGPIPE
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 21: a vfork parent killed while its child runs dies on waking --------
        t_begin 21, t_k21
        t_spawn p_vfp, av_none, m_inh
        ld      (t_pid1),a
        ld      hl,5
        sys     SYS_SLEEP
        ld      a,(t_pid1)
        ld      hl,t_pi
        sys     SYS_PROCINFO
        jp      c,t_fail
        ld      a,(t_pi+P_STATE)
        cp      PS_VFORK
        ld      a,0E1h
        jp      nz,t_fail
        ld      a,(t_pid1)
        ld      b,SIGTERM
        sys     SYS_KILL
        jp      c,t_fail
        ld      a,(t_pid1)
        call    t_wait_a
        t_status 128+SIGTERM
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

; t_cue_a — A = a cue: the three bytes into the storage segment, then wait
; for the harness to zero the first. On real hardware nothing does, so the
; block clears it itself after T_CUE_WAIT ticks and goes on: the person at
; the keyboard types what the screen asked for.
t_cue_a:
        ld      (CUE),a
        cpl
        ld      (CUE+1),a
        ld      a,5Ah
        ld      (CUE+2),a
        ld      hl,(K_TICKS)
        ld      (t_t1),hl
.wait:  ld      a,(CUE)
        or      a
        jr      z,.done
        ld      hl,(K_TICKS)
        ld      de,(t_t1)
        or      a
        sbc     hl,de
        ld      de,T_CUE_WAIT
        or      a
        sbc     hl,de
        jr      c,.wait
        xor     a                       ; nobody answered: go on
        ld      (CUE),a
.done:  xor     a
        ld      (CUE+1),a
        ld      (CUE+2),a
        ret

; t_spawn_hl — HL = a path, DE = argv, BC -> the map: spawnv; A = the
; pid. A refusal is a failure of the test.
t_spawn_hl:
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

; t_run_into — HL = a path: rdl run with its descriptor 1 that file,
; created afresh; A = rdl's status. t_run_prog_into: the same with DE =
; the program's path.
t_run_into:
        ld      de,p_rdl
t_run_prog_into:
        ld      (t_prog),de
        ld      a,O_WRONLY|O_CREAT|O_TRUNC
        sys     SYS_OPEN
        jp      c,t_fail
        ld      (t_fd),a
        ld      (t_map+1),a
        ld      a,0FFh
        ld      (t_map),a
        ld      (t_map+2),a
        ld      hl,(t_prog)
        ld      de,av_none
        ld      bc,t_map
        call    t_spawn_hl
        ld      (t_pid1),a
        ld      a,(t_fd)
        sys     SYS_CLOSE               ; the program's copy is the last
        jp      c,t_fail
        ld      a,(t_pid1)
        jr      t_wait_a

; t_read_pipe0 — A = the read end of a pipe held here: prd, a program,
; reads it until the end and exits with the number of 256-byte pieces it
; got before the end (1 expected). A = its status.
t_read_pipe0:
        ld      (t_map),a               ; prd: 0 = the read end
        ld      a,0FFh
        ld      (t_map+1),a
        ld      (t_map+2),a
        t_exec  p_prd, av_none, t_map
        ret

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

t_k5:       db  "5 edit: a b BS c ^U hello RET",10,0
t_k6:       db  "6 tab: x TAB y RET",10,0
t_k7:       db  "7 three bytes, then the rest: hello RET",10,0
t_k8:       db  "8 ^D, then z RET",10,0
t_k9:       db  "9 ttymode; raw: ESC RIGHT x",10,0
t_k10:      db  "10 canonical drops ESC RIGHT: x RET",10,0
t_k11:      db  "11 shell: spin RET, ^C, q RET",10,0
t_k12:      db  "12 ^C on a reader: ",0
t_k13:      db  "13 ^C on a sleeper: ",0
t_k14:      db  "14 ^C on a pipe writer: ",0
t_k15:      db  "15 ^C on a waiter: ",0
t_k16:      db  "16 handler stack under ^C: ",0
t_k17:      db  "17 ^C during a read: ",0
t_k18:      db  "18 shell: ign RET, ^C, a b STOP, q RET",10,0
t_k19:      db  "19 kill, signal: ",0
t_k20:      db  "20 SIGPIPE ignored, not: ",0
t_k21:      db  "21 a vfork parent killed: ",0
t_bytes:    db  " bytes: ",0
t_ticks:    db  " ticks: ",0
t_ok:       db  "ok",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_code:     db  " code ",0
t_status:   db  " status ",0
t_atstr:    db  " at ",0
p_rdl:      db  "/bin/rdl",0
p_rd3:      db  "/bin/rd3",0
p_rdeof:    db  "/bin/rdeof",0
p_rawr:     db  "/bin/rawr",0
p_tsh:      db  "/bin/tsh",0
p_rdr:      db  "/bin/rdr",0
p_slp:      db  "/bin/slp",0
p_pw:       db  "/bin/pw",0
p_prd:      db  "/bin/prd",0
p_wt:       db  "/bin/wt",0
p_wm:       db  "/bin/wm",0
p_drain:    db  "/bin/drain",0
p_rdf:      db  "/bin/rdf",0
p_kt:       db  "/bin/kt",0
p_wpipe:    db  "/bin/wpipe",0
p_w141:     db  "/bin/w141",0
p_vfp:      db  "/bin/vfp",0
p_l1:       db  "/l1.txt",0
p_l2:       db  "/l2.txt",0
p_l3:       db  "/l3.txt",0
p_l4:       db  "/l4.txt",0
p_l5:       db  "/l5.txt",0
s_hello:    db  "hello",10,0
s_xty:      db  "x",9,"y",10,0
s_escrx:    db  1Bh,1Ch,"x",0
s_xnl:      db  "x",10,0
av_none:    dw  0
av_tsh:     dw  s_tsh,0
s_tsh:      db  "tsh",0
m_inh:      db  0FFh,0FFh,0FFh
t_map:      ds  3
t_step:     db  0
t_at:       db  0
t_p1:       dw  0
t_pid1:     db  0
t_fd:       db  0
t_fd3:      db  0
t_n:        db  0
t_t0:       dw  0
t_t1:       dw  0
t_row:      dw  0
t_prog:     dw  0
t_pi:       ds  PROCINFO_SIZE
t_buf:      ds  64
t_buf256:   ds  1
tblock_end:
        ASSERT  $ < 8000h
