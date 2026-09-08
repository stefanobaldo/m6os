; sched — the kernel runs several processes at once: two of them alternate
; on the tick, one that never calls the kernel does not stop another, a
; parent waits for a child and is woken, a zombie is reaped and an orphan
; reaps itself, the table and the memory run out cleanly, a three-page
; process spawns and waits from a stack in page 2, and the context switch
; is measured. Under Nextor: check the kernel, capture what the resident
; needs, hand the machine over with the switched part of the kernel in the
; record. Then, as process 0, in a block the loader put above the image.
; The report is on screen, the verdict in the mailbox.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "build/kernel.exp"

_STROUT     equ 09h
_TERM       equ 62h
CALSLT      equ B_CALSLT

; The measurement: a process alone making 524 288 getpid calls, against
; two processes making 524 288 yields between them — 524 288 switches.
; The constant turns ticks over that many calls into hundredths of a
; microsecond at 60 Hz — 16 666.67 us per tick / 524 288 = 0.031789 us,
; times 100, as 3179 / 1000 — applied to a quarter of the ticks as
; 3179 / 250, because k_muldiv's product is 24 bits and a pair of
; processes switching for three minutes counts more than 5277 ticks;
; T_GETPID100 is the resident round trip the control loop pays per call,
; 62 T at 3.58 MHz, added back to the difference to give the switch.
T_ITER      equ 32768           ; iterations of sixteen calls: the control
T_ITER_PP   equ 16384           ; each of the pair
T_US100     equ 3179
T_US100_DIV equ 250
T_GETPID100 equ 1732
T_SW_MAX    equ 25000           ; the gate: 250.00 us per switch
T_SPIN      equ 60              ; ticks each spinner runs for
T_SPIN_EVERY equ 6              ; ticks between its letters
T_ELAPSED_MIN equ 55            ; both spinners done within these ticks:
T_ELAPSED_MAX equ 90            ; interleaved, not one after the other

        org     100h

start:
        ld      sp,KT_LSTACK            ; page 2: the DOS stack dies in the
                                        ; takeover
        ld      a,DBG_ASCII
        out     (DBG_MODE),a

; --- step 0: SCREEN 0, while the BIOS can still be asked ----------------
        ld      a,(B_SCRMOD)
        or      a
        jr      z,.screen0
        ld      ix,B_INITXT
        ld      iy,(B_EXPTBL-1)
        call    CALSLT
.screen0:
        ld      de,banner
        call    puts

; --- step 1: a Nextor 2 kernel ----------------------------------------
        ld      a,1
        ld      (step),a
        ld      de,s_version
        call    puts
        call    ld_nextor2
        jr      z,.nextor2
        cp      0F1h
        jr      nz,.not1
        ld      de,s_notnextor
        call    puts
.not1:  cp      0F2h
        jr      nz,.not2
        ld      de,s_nextor3
        call    puts
.not2:  jp      fail
.nextor2:
        ld      a,ixl
        call    putdec
        ld      a,'.'
        call    putc
        ld      a,iyh
        call    putdec
        ld      a,'.'
        call    putc
        ld      a,iyl
        call    putdec
        call    newline

; --- step 2: capture what the resident needs --------------------------
        ld      a,2
        ld      (step),a
        ld      de,s_capture
        call    puts
        ld      ix,REC
        call    nx_capture
        ld      hl,(REC+KR_WALL)
        call    puthex16
        ld      de,s_resident
        call    puts
        ld      hl,(kimage+K_END-K_BASE) ; the image's end, from its header
        push    hl
        ld      de,K_BASE
        or      a
        sbc     hl,de
        call    putdec16
        ld      de,s_room
        call    puts
        pop     de
        ld      hl,(REC+KR_WALL)
        or      a
        sbc     hl,de                   ; room = wall - end
        ld      a,0F3h                  ; the image does not fit below the wall
        jp      c,fail
        jp      z,fail
        call    putdec16
        ld      de,s_switched
        call    puts
        ld      hl,ksimage_end-ksimage
        call    putdec16
        call    newline

; --- step 3: the takeover -----------------------------------------------
        ld      a,3
        ld      (step),a
        ld      de,s_takeover
        call    puts
        ld      hl,t_entry
        ld      (REC+KR_TEST),hl
        xor     a
        ld      (REC+KR_MEMCAP),a       ; no cap
        ld      hl,ksimage              ; the switched part of the kernel
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

; putdec — A as decimal, no leading zeros.
putdec:
        ld      l,a
        ld      h,0
; putdec16 — HL as decimal, no leading zeros.
putdec16:
        xor     a
        ld      (leading),a
        ld      de,10000
        call    .digit
        ld      de,1000
        call    .digit
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

banner:     db  "sched: m6 runs processes at once and switches on the tick",13,10,'$'
s_version:  db  "1 kernel: Nextor $"
s_notnextor: db "MSX-DOS 2, not Nextor: not supported",13,10,'$'
s_nextor3:  db  "Nextor 3 kernel: not supported",13,10,'$'
s_capture:  db  "2 wall $"
s_resident: db  "h resident $"
s_room:     db  " room $"
s_switched: db  " switched $"
s_takeover: db  "-- taking the machine --",13,10,'$'
s_fail:     db  "FAIL step $"
s_code:     db  " code $"
chbuf:      db  0,'$'
step:       db  0
leading:    db  0
REC:        ds  KREC_SIZE

; The capture module needs the BIOS RDSLT only; the loader module, the four
; symbols below.
        include "nextor/capture.asm"
ld_image    equ kimage
ld_rec      equ REC
ld_block    equ tblock
ld_block_len equ tblock_end-tblock
        include "loader/takeover.asm"

kimage:
        incbin  "build/kernel.bin"
kimage_end:
ksimage:
        incbin  "build/kseg.bin"
ksimage_end:


; The second half, assembled for K_IMAGE_END (build/kernel.exp), where the
; loader copies it: the test's code and data, and the user images after
; them. It runs as process 0.
tblock:
        DISP    K_IMAGE_END
t_entry:
; --- step 5: process 0 and the kernel's memory ------------------------------
        ld      a,5
        ld      (t_step),a
        ld      hl,t_k5
        k_call  API_CON_PUTS
        ld      c,1                     ; the check, named on a failure
        ld      a,(K_PROC+P_STATE)
        cp      PS_RUN
        ld      a,0E1h
        jp      nz,t_fail_status        ; row 0 is not running
        inc     c
        ld      a,(K_PROC+P_PID)
        or      a
        ld      a,0E1h
        jp      nz,t_fail_status        ; row 0 is not pid 0
        inc     c
        ld      a,(K_KSEG)
        or      a
        ld      a,0E1h
        jp      z,t_fail_status         ; no switched image
        inc     c
        ld      a,(K_KSEG)
        ld      hl,K_PROC+P_SEG
        cp      (hl)
        ld      a,0E1h
        jp      nz,t_fail_status        ; page 0 is not the switched image
        inc     c
        ld      a,(K_INTRPT)
        cp      0C3h
        ld      a,0E1h
        jp      nz,t_fail_status        ; no jp at 0038h
        ld      hl,(K_INTRPT+1)
        ld      de,K_ISR
        or      a
        sbc     hl,de
        ld      a,0E1h
        jp      nz,t_fail_status        ; not to the kernel's entry
        inc     c
        ld      hl,(K_STUB)
        ld      de,K_SSLOT
        ld      b,K_SSLOT_LEN
.stub:  ld      a,(de)
        cp      (hl)
        ld      a,0E1h
        jp      nz,t_fail_status        ; the stub in page 0 is not the stub
        inc     hl
        inc     de
        djnz    .stub
        ld      hl,t_k5b
        k_call  API_CON_PUTS
        ld      a,(K_KSEG)
        call    k_dec8
        ld      hl,t_k5c
        k_call  API_CON_PUTS
        k_call  API_MEM_INFO
        ld      (t_free0),bc            ; free now: usable - page 3 - the
        ld      hl,-3                   ; switched image - the scratch page
        add     hl,de
        or      a
        sbc     hl,bc
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,(t_free0)
        k_call  API_CON_DEC16
        ld      hl,t_k5d
        k_call  API_CON_PUTS
        ; The two released boot segments are on the free stack: the next
        ; two allocations return them, in either order.
        ld      b,2
        k_call  API_MEM_ALLOC
        ld      c,a
        ld      a,0E1h
        jp      c,t_fail
        ld      b,2
        k_call  API_MEM_ALLOC
        ld      b,a
        ld      a,0E1h
        jp      c,t_fail                ; b, c = the two segments
        ld      a,(K_REC+KR_SEG64K+0)
        cp      b
        jr      z,.b0
        cp      c
        ld      a,0E1h
        jp      nz,t_fail               ; page 0's boot segment not released
        ld      a,(K_REC+KR_SEG64K+1)
        cp      b
        jr      .other
.b0:    ld      a,(K_REC+KR_SEG64K+1)
        cp      c
.other: ld      a,0E1h
        jp      nz,t_fail               ; page 1's boot segment not released
        ld      b,2
        k_call  API_MEM_FREE_ALL
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 6: spawn and wait; ECHILD; ret and jp 0 ---------------------------
        ld      a,6
        ld      (t_step),a
        ld      hl,t_k6
        k_call  API_CON_PUTS
        ld      hl,u_hello
        ld      bc,u_hello_end-u_hello
        ld      a,1
        k_call  API_SPAWN
        ld      c,a
        ld      a,0E0h
        jp      c,t_fail_status
        ld      a,l
        cp      1
        ld      c,a
        ld      a,0E2h
        jp      nz,t_fail_status        ; the first child is pid 1
        k_call  API_WAIT
        ld      c,a
        ld      a,0E2h
        jp      c,t_fail_status
        ld      a,h
        cp      1
        ld      c,a
        ld      a,0E2h
        jp      nz,t_fail_status        ; wait named another pid
        ld      a,l
        cp      42
        ld      c,a
        ld      a,0E2h
        jp      nz,t_fail_status
        k_call  API_MEM_INFO
        ld      hl,(t_free0)
        or      a
        sbc     hl,bc
        ld      a,0E2h
        jp      nz,t_fail               ; segments not all back
        k_call  API_WAIT
        ld      c,a
        ld      a,0E2h
        jp      nc,t_fail               ; a second wait found a child
        ld      a,c
        cp      E_CHILD
        ld      a,0E2h
        jp      nz,t_fail
        ld      hl,t_k6b
        k_call  API_CON_PUTS
        ld      hl,u_ret
        ld      bc,u_ret_end-u_ret
        ld      a,1
        call    t_run
        ld      c,a
        or      a
        ld      a,0E2h
        jp      nz,t_fail_status
        ld      hl,u_jp0
        ld      bc,u_jp0_end-u_jp0
        ld      a,1
        call    t_run
        ld      c,a
        or      a
        ld      a,0E2h
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 7: two spinners alternate on the tick ------------------------------
        ld      a,7
        ld      (t_step),a
        ld      hl,t_k7
        k_call  API_CON_PUTS
        ld      hl,u_spin_a
        ld      bc,u_spin_a_end-u_spin_a
        ld      a,1
        call    t_spawn
        ld      hl,u_spin_b
        ld      bc,u_spin_b_end-u_spin_b
        ld      a,1
        call    t_spawn
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      a,0E3h
        ld      (t_code),a
        call    t_wait_status           ; a = status of whichever came first
        cp      T_SPIN/T_SPIN_EVERY
        ld      c,a
        ld      a,0E3h
        jp      nz,t_fail_status        ; not every letter written, or a
        call    t_wait_status           ; register lost across a tick
        cp      T_SPIN/T_SPIN_EVERY
        ld      c,a
        ld      a,0E3h
        jp      nz,t_fail_status
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de                   ; hl = ticks for both
        push    hl
        k_call  API_CON_NEWLINE
        ld      hl,t_k7b
        k_call  API_CON_PUTS
        pop     hl
        push    hl
        k_call  API_CON_DEC16
        ld      hl,t_k7c
        k_call  API_CON_PUTS
        pop     hl
        ld      de,T_ELAPSED_MIN
        or      a
        sbc     hl,de
        ld      a,0E3h
        jp      c,t_fail                ; too fast to be true
        ld      de,T_ELAPSED_MAX+1-T_ELAPSED_MIN
        or      a
        sbc     hl,de
        ld      a,0E3h
        jp      nc,t_fail               ; one after the other, not at once
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 8: a process that never calls the kernel is preempted -------------
        ld      a,8
        ld      (t_step),a
        ld      hl,t_k8
        k_call  API_CON_PUTS
        ld      hl,u_hog
        ld      bc,u_hog_end-u_hog
        ld      a,1
        call    t_spawn
        ld      (t_pid),a               ; the hog's pid
        ld      hl,u_hello
        ld      bc,u_hello_end-u_hello
        ld      a,1
        call    t_spawn
        ld      a,0E4h
        ld      (t_code),a
        call    t_wait                  ; hl = pid, status
        ld      a,(t_pid)
        cp      h
        ld      c,h
        ld      a,0E4h
        jp      z,t_fail_status         ; the hog finished first
        ld      a,l
        cp      42
        ld      c,a
        ld      a,0E4h
        jp      nz,t_fail_status
        call    t_wait
        ld      a,(t_pid)
        cp      h
        ld      c,h
        ld      a,0E4h
        jp      nz,t_fail_status        ; not the hog
        ld      a,l
        cp      3
        ld      c,a
        ld      a,0E4h
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 9: a zombie reaped, an orphan reaping itself; the table's edge ----
        ld      a,9
        ld      (t_step),a
        ld      hl,t_k9
        k_call  API_CON_PUTS
        ld      hl,u_parent
        ld      bc,u_parent_end-u_parent
        ld      a,1
        call    t_run
        cp      5
        ld      c,a
        ld      a,0E5h
        jp      nz,t_fail_status
        ld      b,4                     ; the orphan may not have run yet:
.orphan:                                ; give it the CPU
        push    bc
        k_call  API_YIELD
        pop     bc
        djnz    .orphan
        call    t_rows_free
        ld      a,0E5h
        jp      nz,t_fail               ; a row is still taken
        k_call  API_MEM_INFO
        ld      hl,(t_free0)
        or      a
        sbc     hl,bc
        ld      a,0E5h
        jp      nz,t_fail               ; a segment is still taken
        ld      hl,t_k9b
        k_call  API_CON_PUTS
        ; Spawn until it fails: the memory runs out first on the floor,
        ; the table first anywhere with fifteen free segments or more.
        ld      hl,0
        ld      (t_count),hl
.fill:  ld      hl,u_nap
        ld      bc,u_nap_end-u_nap
        ld      a,1
        k_call  API_SPAWN
        jr      c,.full
        ld      hl,(t_count)
        inc     hl
        ld      (t_count),hl
        jr      .fill
.full:  ld      (t_errno),a
        ld      hl,(t_count)
        k_call  API_CON_DEC16
        ld      hl,t_k9c
        k_call  API_CON_PUTS
        ld      hl,(t_free0)
        ld      de,NPROC-1
        or      a
        sbc     hl,de                   ; free0 - 15
        jr      c,.mem                  ; fewer than fifteen: memory first
        ld      a,(t_errno)
        cp      E_AGAIN
        ld      c,a
        ld      a,0E5h
        jp      nz,t_fail_status
        ld      hl,(t_count)
        ld      de,NPROC-1
        or      a
        sbc     hl,de
        ld      a,0E5h
        jp      nz,t_fail               ; not fifteen
        ld      hl,t_k9d
        k_call  API_CON_PUTS
        jr      .drain
.mem:   ld      a,(t_errno)
        cp      E_NOMEM
        ld      c,a
        ld      a,0E5h
        jp      nz,t_fail_status
        ld      hl,(t_count)
        ld      de,(t_free0)
        or      a
        sbc     hl,de
        ld      a,0E5h
        jp      nz,t_fail               ; not every free segment
        ld      hl,t_k9e
        k_call  API_CON_PUTS
.drain: ld      hl,(t_count)
        ld      a,h
        or      l
        jr      z,.drained
        dec     hl
        ld      (t_count),hl
        ld      a,0E5h
        ld      (t_code),a
        call    t_wait_status
        or      a
        ld      c,a
        ld      a,0E5h
        jp      nz,t_fail_status
        jr      .drain
.drained:
        call    t_rows_free
        ld      a,0E5h
        jp      nz,t_fail
        k_call  API_MEM_INFO
        ld      hl,(t_free0)
        or      a
        sbc     hl,bc
        ld      a,0E5h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 10: three pages, the stack in page 2: spawn, yield, wait ----------
        ld      a,10
        ld      (t_step),a
        ld      hl,t_k10
        k_call  API_CON_PUTS
        ld      hl,u_stack3
        ld      bc,u_stack3_end-u_stack3
        ld      a,3
        call    t_run
        cp      7
        ld      c,a
        ld      a,0E6h
        jp      nz,t_fail_status
        ld      hl,t_k10b
        k_call  API_CON_PUTS

; --- step 11: the measurement -----------------------------------------------
        ld      a,11
        ld      (t_step),a
        ld      hl,t_k11
        k_call  API_CON_PUTS
        ld      hl,u_ctl
        ld      bc,u_ctl_end-u_ctl
        ld      a,1
        call    t_spawn
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      a,0E7h
        ld      (t_code),a
        call    t_wait_status
        or      a
        ld      c,a
        ld      a,0E7h
        jp      nz,t_fail_status
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        ld      (t_ctl),hl
        ld      hl,u_pp
        ld      bc,u_pp_end-u_pp
        ld      a,1
        call    t_spawn
        ld      hl,u_pp
        ld      bc,u_pp_end-u_pp
        ld      a,1
        call    t_spawn
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        call    t_wait_status
        or      a
        ld      c,a
        ld      a,0E7h
        jp      nz,t_fail_status
        call    t_wait_status
        or      a
        ld      c,a
        ld      a,0E7h
        jp      nz,t_fail_status
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        ld      (t_pair),hl
        ld      hl,t_k11b
        k_call  API_CON_PUTS
        ld      hl,(t_ctl)
        k_call  API_CON_DEC16
        ld      hl,t_k11c
        k_call  API_CON_PUTS
        ld      hl,(t_pair)
        k_call  API_CON_DEC16
        ld      hl,t_k11d
        k_call  API_CON_PUTS
        ld      hl,(t_pair)
        ld      de,(t_ctl)
        or      a
        sbc     hl,de
        call    t_percall               ; hl = hundredths of us per switch,
        ld      de,T_GETPID100          ; less the getpid the control paid
        add     hl,de
        push    hl
        call    k_hundredths
        ld      hl,t_us
        k_call  API_CON_PUTS
        pop     hl
        ld      de,T_SW_MAX+1
        or      a
        sbc     hl,de
        ld      a,0E7h
        jp      nc,t_fail

; --- step 12: verdict ------------------------------------------------------
        ld      hl,t_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
        jp      t_halt

; t_spawn — HL = image, BC = length, A = pages: spawn it. Out: A = the
; child's pid. A refused spawn fails the step with code E0 and the errno
; printed.
t_spawn:
        k_call  API_SPAWN
        ret     nc
        ld      c,a
        ld      a,0E0h
        jp      t_fail_status

; t_wait — wait for a child. Out: H = its pid, L = its status. ECHILD fails
; the step with the code in (t_code).
t_wait:
        k_call  API_WAIT
        ret     nc
        ld      c,a
        ld      a,(t_code)
        jp      t_fail_status

; t_wait_status — t_wait, with A = the status.
t_wait_status:
        call    t_wait
        ld      a,l
        ret

; t_run — HL = image, BC = length, A = pages: spawn it and wait for it.
; Out: A = the exit status.
t_run:
        call    t_spawn
        ld      a,0E0h
        ld      (t_code),a
        jr      t_wait_status

; t_rows_free — Z if every row of the table but 0 is free.
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
        ret                             ; Z from the last or a

; t_percall — HL = ticks over 524 288 calls: print "T ticks = N.NN us",
; return HL = the hundredths of a microsecond.
t_percall:
        push    hl
        k_call  API_CON_DEC16
        ld      hl,t_ticks
        k_call  API_CON_PUTS
        pop     hl
        srl     h
        rr      l
        srl     h
        rr      l                       ; a quarter of the ticks
        ld      de,T_US100
        ld      bc,T_US100_DIV
        call    k_muldiv
        push    hl
        call    k_hundredths
        ld      hl,t_us2
        k_call  API_CON_PUTS
        pop     hl
        ret

; t_fail — A = error code, (t_step) = the step.
t_fail:
        push    af
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_step)
        call    k_dec8
        ld      hl,t_scode
        k_call  API_CON_PUTS
        pop     af
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
        jr      t_halt

; t_fail_status — A = error code, C = the status (or errno, or pid) seen.
t_fail_status:
        push    bc
        push    af
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_step)
        call    k_dec8
        ld      hl,t_scode
        k_call  API_CON_PUTS
        pop     af
        k_call  API_CON_HEX8
        ld      hl,t_status
        k_call  API_CON_PUTS
        pop     bc
        ld      a,c
        call    k_dec8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
        jr      t_halt

; t_halt — process 0 has nothing left to do and no child left to wait for.
t_halt:
        ei
        halt
        jr      t_halt

        include "m6util.asm"

t_k5:       db  "5 process 0: ",0
t_k5b:      db  "page 0 is segment ",0
t_k5c:      db  ", ",0
t_k5d:      db  " free, boot pages released: ",0
t_ok:       db  "ok",10,0
t_k6:       db  "6 ",0
t_k6b:      db  "  exit 42 from pid 1, segments freed, ECHILD; ret, jp 0: ",0
t_k7:       db  "7 alternation: ",0
t_k7b:      db  "  both wrote every letter in ",0
t_k7c:      db  " ticks: ",0
t_k8:       db  "8 a process that never calls the kernel: ",0
t_k9:       db  "9 zombie reaped, orphan reaped itself: ",0
t_k9b:      db  "ok",10,"  spawn until it fails: ",0
t_k9c:      db  " spawned, ",0
t_k9d:      db  "EAGAIN, the table is full",10,"  all waited for: ",0
t_k9e:      db  "ENOMEM, the memory is out",10,"  all waited for: ",0
t_k10:      db  "10 three pages, stack in page 2:",10,0
t_k10b:     db  "  spawn, yield, wait, exit 7: ok",10,0
t_k11:      db  "11 context switch over 524288 yields",10,0
t_k11b:     db  "   ticks: control ",0
t_k11c:     db  ", pair ",0
t_k11d:     db  "; difference ",0
t_ticks:    db  " ticks = ",0
t_us2:      db  " us",10,"   switch: ",0
t_us:       db  " us",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_scode:    db  " code ",0
t_status:   db  " status ",0

t_step:     db  0
t_code:     db  0
t_pid:      db  0
t_errno:    db  0
t_free0:    dw  0
t_t0:       dw  0
t_ctl:      dw  0
t_pair:     dw  0
t_count:    dw  0
        ENT

; The user programs, each assembled for P0_PROG and copied there by spawn.
; They call the kernel through K_SYS — and read the tick counter straight
; out of page 3, which a test program may. They live in the block, in page
; 3 once the loader has copied it, where process 0 reads them: u_x is where
; an image is after the copy, u_x_k where it is here.

; u_image name — the two addresses of an image, after its u_name_k_end.
    macro u_image name
name        equ K_IMAGE_END+(name_k-tblock)
name_end    equ name+(name_k_end-name_k)
    endm

; u_hello — 2.2's: every syscall and every error; then a spawn of a
; one-byte child, ret, waited for; then exit(42). A check that fails exits
; with its own status, 1 to 6.
u_hello_k:
        DISP    P0_PROG
        ld      a,1
        ld      hl,.msg
        ld      bc,.msglen
        sys     SYS_WRITE
        sys     SYS_GETPID
        ld      a,h
        or      a
        jr      nz,.s1
        ld      a,l
        or      a
        jr      z,.s1                   ; pid 0 is the kernel's
        add     a,'0'
        ld      (.digit),a
        ld      a,1
        ld      hl,.digit
        ld      bc,2
        sys     SYS_WRITE
        ld      hl,SC_PAGESIZE
        sys     SYS_SYSCONF
        jr      c,.s2
        ld      de,4000h
        or      a
        sbc     hl,de
        jr      nz,.s2
        ld      a,7                     ; not a file descriptor
        ld      hl,.msg
        ld      bc,1
        sys     SYS_WRITE
        jr      nc,.s3
        cp      E_BADF
        jr      nz,.s3
        call    K_SYS+3*(K_SYS_N-1)     ; the last entry: nothing there
        jr      nc,.s4
        cp      E_NOSYS
        jr      nz,.s4
        ld      hl,.child
        ld      bc,1
        ld      a,1
        sys     SYS_SPAWN               ; a child of my own, from my page 0
        jr      c,.s5
        sys     SYS_WAIT
        jr      c,.s6
        ld      a,l
        or      a
        jr      nz,.s6
        ld      a,42
        sys     SYS_EXIT
.s1:    ld      a,1
        sys     SYS_EXIT
.s2:    ld      a,2
        sys     SYS_EXIT
.s3:    ld      a,3
        sys     SYS_EXIT
.s4:    ld      a,4
        sys     SYS_EXIT
.s5:    ld      a,5
        sys     SYS_EXIT
.s6:    ld      a,6
        sys     SYS_EXIT
.msg:   db      "  hello from pid "
.msglen equ     $-.msg
.digit: db      "?",10
.child: db      0C9h                    ; ret
        ENT
u_hello_k_end:
        u_image u_hello

; u_ret — a program that simply returns: status 0 through P0_EXIT.
u_ret_k:
        DISP    P0_PROG
        ret
        ENT
u_ret_k_end:
        u_image u_ret

; u_jp0 — a program that jumps to 0: the same.
u_jp0_k:
        DISP    P0_PROG
        jp      0
        ENT
u_jp0_k_end:
        u_image u_jp0

; u_spin ch — a spinner: for T_SPIN ticks, read the tick counter and
; write the letter every T_SPIN_EVERY ticks, checking on every turn that a
; pattern loaded into every register the switch saves is still there.
; Exits with the count of letters written, or 1 to 8 naming the register
; that changed (BC, DE, IX, IY, BC', DE', HL', A').
    macro u_spin ch
        DISP    P0_PROG
        ld      hl,(K_TICKS)
        ld      (.t0),hl
        call    .load
.loop:  ld      a,b
        cp      12h
        jp      nz,.r1
        ld      a,c
        cp      34h
        jp      nz,.r1
        ld      a,d
        cp      56h
        jp      nz,.r2
        ld      a,e
        cp      78h
        jp      nz,.r2
        push    ix
        pop     hl
        ld      a,h
        cp      9Ah
        jp      nz,.r3
        ld      a,l
        cp      0BCh
        jp      nz,.r3
        push    iy
        pop     hl
        ld      a,h
        cp      0DEh
        jp      nz,.r4
        ld      a,l
        cp      0F0h
        jp      nz,.r4
        exx
        ld      a,b
        cp      11h
        jp      nz,.r5x
        ld      a,c
        cp      22h
        jp      nz,.r5x
        ld      a,d
        cp      33h
        jp      nz,.r6x
        ld      a,e
        cp      44h
        jp      nz,.r6x
        ld      a,h
        cp      55h
        jp      nz,.r7x
        ld      a,l
        cp      66h
        jp      nz,.r7x
        exx
        ex      af,af'
        ld      l,a
        ex      af,af'
        ld      a,l
        cp      77h
        jp      nz,.r8
        ld      hl,(K_TICKS)
        ld      de,(.t0)
        or      a
        sbc     hl,de                   ; hl = ticks since the start
        ld      de,5678h                ; the pattern back into DE
        ld      a,h
        or      a
        jr      nz,.late                ; 256 or more: long over
        ld      a,(.next)
        ld      h,a
        ld      a,l
        cp      h
        jp      c,.loop                 ; not yet time for a letter
        ld      a,h
        add     a,T_SPIN_EVERY
        ld      (.next),a
        ld      a,(.count)
        inc     a
        ld      (.count),a
        push    hl
        ld      a,1
        ld      hl,.ltr
        ld      bc,1
        sys     SYS_WRITE
        call    .load                   ; the syscall preserved nothing
        pop     hl
        ld      a,l
.late:  cp      T_SPIN
        jp      c,.loop
        ld      a,(.count)
        sys     SYS_EXIT
.r5x:   exx
        jr      .r5
.r6x:   exx
        jr      .r6
.r7x:   exx
        jr      .r7
.r1:    ld      a,1
        sys     SYS_EXIT
.r2:    ld      a,2
        sys     SYS_EXIT
.r3:    ld      a,3
        sys     SYS_EXIT
.r4:    ld      a,4
        sys     SYS_EXIT
.r5:    ld      a,5
        sys     SYS_EXIT
.r6:    ld      a,6
        sys     SYS_EXIT
.r7:    ld      a,7
        sys     SYS_EXIT
.r8:    ld      a,8
        sys     SYS_EXIT
.load:  ld      bc,1234h
        ld      de,5678h
        ld      ix,9ABCh
        ld      iy,0DEF0h
        exx
        ld      bc,1122h
        ld      de,3344h
        ld      hl,5566h
        exx
        ex      af,af'
        ld      a,77h
        ex      af,af'
        ret
.t0:    dw      0
.next:  db      T_SPIN_EVERY
.count: db      0
.ltr:   db      ch
        ENT
    endm

u_spin_a_k:
        u_spin  'A'
u_spin_a_k_end:
        u_image u_spin_a
u_spin_b_k:
        u_spin  'B'
u_spin_b_k_end:
        u_image u_spin_b

; u_hog — never calls the kernel: spins on the tick counter for 30 ticks,
; then exit(3). Anything else that runs meanwhile runs because the tick
; took the CPU from it.
u_hog_k:
        DISP    P0_PROG
        ld      de,(K_TICKS)
.loop:  ld      hl,(K_TICKS)
        or      a
        sbc     hl,de
        ld      a,h
        or      a
        jr      nz,.done
        ld      a,l
        cp      30
        jr      c,.loop
.done:  ld      a,3
        sys     SYS_EXIT
        ENT
u_hog_k_end:
        u_image u_hog

; u_parent — spawns a one-byte child and exits 5 without waiting for it:
; the child is an orphan and reaps itself. Status 1: the spawn failed.
u_parent_k:
        DISP    P0_PROG
        ld      hl,.child
        ld      bc,1
        ld      a,1
        sys     SYS_SPAWN
        jr      c,.bad
        ld      a,5
        sys     SYS_EXIT
.bad:   ld      a,1
        sys     SYS_EXIT
.child: db      0C9h                    ; ret
        ENT
u_parent_k_end:
        u_image u_parent

; u_nap — spins for 10 ticks and exits 0: a process that stays alive while
; the table and the memory are filled.
u_nap_k:
        DISP    P0_PROG
        ld      de,(K_TICKS)
.loop:  ld      hl,(K_TICKS)
        or      a
        sbc     hl,de
        ld      a,h
        or      a
        jr      nz,.done
        ld      a,l
        cp      10
        jr      c,.loop
.done:  xor     a
        sys     SYS_EXIT
        ENT
u_nap_k_end:
        u_image u_nap

; u_stack3 — three pages: the stack starts at BFFEh, in the page the window
; takes and the page spawn writes a child through. From there: a spawn of
; a one-byte child, a yield, a wait for it, a switched syscall, a write of
; a buffer it puts in page 2, then exit(7). Status 1: the stack is not
; where it should be; 2: spawn failed; 3: wait failed; 4: the child's
; status; 5: sysconf failed.
u_stack3_k:
        DISP    P0_PROG
        ld      hl,0
        add     hl,sp
        ld      a,h
        cp      0BFh
        jr      nz,.s1
        ld      hl,.child
        ld      bc,1
        ld      a,1
        sys     SYS_SPAWN
        jr      c,.s2
        sys     SYS_YIELD
        sys     SYS_WAIT
        jr      c,.s3
        ld      a,l
        or      a
        jr      nz,.s4
        ld      hl,SC_PAGESIZE
        sys     SYS_SYSCONF
        jr      c,.s5
        ld      de,4000h
        or      a
        sbc     hl,de
        jr      nz,.s5
        ld      hl,.msg
        ld      de,0A000h
        ld      bc,.msglen
        ldir
        ld      a,1
        ld      hl,0A000h
        ld      bc,.msglen
        sys     SYS_WRITE
        ld      a,7
        sys     SYS_EXIT
.s1:    ld      a,1
        sys     SYS_EXIT
.s2:    ld      a,2
        sys     SYS_EXIT
.s3:    ld      a,3
        sys     SYS_EXIT
.s4:    ld      a,4
        sys     SYS_EXIT
.s5:    ld      a,5
        sys     SYS_EXIT
.child: db      0C9h                    ; ret
.msg:   db      "  child waited for from a stack in page 2, buffer at A000h",10
.msglen equ     $-.msg
        ENT
u_stack3_k_end:
        u_image u_stack3

; The two timing loops: T_ITER (or T_ITER_PP) iterations of push bc,
; sixteen calls, pop bc. The push and pop are there because the ABI
; preserves nothing.
u_ctl_k:
        DISP    P0_PROG
        ld      bc,T_ITER
.loop:  push    bc
        DUP     16
        sys     SYS_GETPID
        EDUP
        pop     bc
        dec     bc
        ld      a,b
        or      c
        jr      nz,.loop
        xor     a
        sys     SYS_EXIT
        ENT
u_ctl_k_end:
        u_image u_ctl

u_pp_k:
        DISP    P0_PROG
        ld      bc,T_ITER_PP
.loop:  push    bc
        DUP     16
        sys     SYS_YIELD
        EDUP
        pop     bc
        dec     bc
        ld      a,b
        or      c
        jr      nz,.loop
        xor     a
        sys     SYS_EXIT
        ENT
u_pp_k_end:
        u_image u_pp

tblock_end:

        ASSERT  $ < 4000h
