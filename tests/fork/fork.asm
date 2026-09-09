; fork — a process forks: the child gets 0 and the parent its pid, the
; child's memory is a copy, a three-page process forks from a stack in
; page 2, a vfork child shares the parent's memory and runs while the
; parent sleeps, wait reaps both kinds, the refusals — EPERM from process
; 0, ENOMEM with the memory out, EAGAIN with the table full — leak
; nothing, and a two-page fork is timed over 32 of them. Under Nextor:
; check the kernel, capture what the resident needs, hand the machine
; over. Then, as process 0, in a block the loader put above the image.
; The report is on screen, the verdict in the mailbox.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "build/kernel.exp"

_STROUT     equ 09h
_TERM       equ 62h

T_FORKS     equ 32              ; two-page forks timed
T_MS100     equ 1667            ; ticks * 1667 / 32 = hundredths of a ms
T_MS100_DIV equ T_FORKS         ; per fork at 60 Hz
T_FORK_MAX  equ 25000           ; the gate: 250.00 ms per two-page fork
T_FORK_CALC equ 21096           ; 2 x 105.48 ms, the page copy measured

        org     100h

start:
        ld      sp,KT_LSTACK            ; page 2: the DOS stack dies in the
                                        ; takeover
        ld      a,DBG_ASCII
        out     (DBG_MODE),a

; --- step 0: SCREEN 0 at 80 columns, while the BIOS can still be asked --
        call    ld_screen80
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

banner:     db  "fork: a process forks, with and without a copy",13,10,'$'
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

; The capture module needs the driver module's loader half (nx_header)
; and, through it, the BIOS ENASLT and the DOS RAMAD1; the loader module,
; the four symbols below.
nx_enaslt   equ ENASLT
nx_ramslot1 equ RAMAD1
        include "nextor/abi2.asm"
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
        k_call  API_MEM_INFO
        ld      (t_free0),bc            ; free at the start: every step
                                        ; ends with the same count

; --- step 5: fork returns twice; the child's memory is a copy ---------------
        ld      a,5
        ld      (t_step),a
        ld      hl,t_k5
        k_call  API_CON_PUTS
        ld      hl,u_fork1
        ld      bc,u_fork1_end-u_fork1
        ld      a,1
        call    t_run                   ; a = 40 + the child's status
        cp      45
        ld      c,a
        ld      a,0E1h
        jp      nz,t_fail_status
        call    t_all_back
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 6: the child's change is the child's alone ------------------------
        ld      a,6
        ld      (t_step),a
        ld      hl,t_k6
        k_call  API_CON_PUTS
        ld      hl,u_fork2
        ld      bc,u_fork2_end-u_fork2
        ld      a,1
        call    t_run                   ; a = the parent's variable after
        cp      5
        ld      c,a
        ld      a,0E2h
        jp      nz,t_fail_status
        call    t_all_back
        ld      a,0E2h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 7: three pages, the stack in page 2 -------------------------------
; Six segments: three for the process, three for the copy. Not the floor,
; whose five are what step 10 refuses with.
        ld      a,7
        ld      (t_step),a
        ld      hl,t_k7
        k_call  API_CON_PUTS
        ld      hl,(t_free0)
        ld      de,6
        or      a
        sbc     hl,de
        jr      c,.floor7
        ld      hl,u_fork3
        ld      bc,u_fork3_end-u_fork3
        ld      a,3
        call    t_run
        cp      23
        ld      c,a
        ld      a,0E3h
        jp      nz,t_fail_status
        call    t_all_back
        ld      a,0E3h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS
        jr      .done7
.floor7:
        ld      hl,t_k7b
        k_call  API_CON_PUTS
.done7:

; --- step 8: vfork shares, and the parent sleeps; step 9: wait reaps it -----
        ld      a,8
        ld      (t_step),a
        ld      hl,t_k8
        k_call  API_CON_PUTS
        ld      hl,u_vfork
        ld      bc,u_vfork_end-u_vfork
        ld      a,1
        call    t_run
        cp      7
        ld      c,a
        ld      a,0E4h
        jp      nz,t_fail_status
        call    t_all_back
        ld      a,0E4h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 10: the refusals --------------------------------------------------
        ld      a,10
        ld      (t_step),a
        ld      hl,t_k10
        k_call  API_CON_PUTS
        sys     SYS_FORK                ; process 0 has no pages of its own
        ld      c,a
        ld      a,0E5h
        jp      nc,t_fail
        ld      a,c
        cp      E_PERM
        ld      a,0E5h
        jp      nz,t_fail_status
        sys     SYS_VFORK
        ld      c,a
        ld      a,0E5h
        jp      nc,t_fail
        ld      a,c
        cp      E_PERM
        ld      a,0E5h
        jp      nz,t_fail_status
        ld      hl,t_k10b
        k_call  API_CON_PUTS
        ; ENOMEM: a three-page process forks with fewer than three
        ; segments left — the floor; anywhere larger the fork succeeds and
        ; the child exits 0.
        ld      hl,(t_free0)
        ld      de,6
        or      a
        sbc     hl,de                   ; free0 - 6: three for the process,
        ld      a,E_NOMEM               ; three for the copy
        jr      c,.expect
        xor     a
.expect:
        ld      (t_expect),a
        ld      hl,u_fork3
        ld      bc,u_fork3_end-u_fork3
        ld      a,3
        call    t_run                   ; 23, or 1 + the errno the fork gave
        ld      c,a
        ld      a,(t_expect)
        or      a
        jr      z,.ok23
        ld      a,c
        cp      1+E_NOMEM
        ld      a,0E5h
        jp      nz,t_fail_status
        ld      hl,t_k10c
        k_call  API_CON_PUTS
        jr      .again
.ok23:  ld      a,c
        cp      23
        ld      a,0E5h
        jp      nz,t_fail_status
        ld      hl,t_k10d
        k_call  API_CON_PUTS
.again: call    t_all_back
        ld      a,0E5h
        jp      nz,t_fail               ; a refused fork kept something
        ; EAGAIN: fourteen sleepers fill the table but one row, a fifteenth
        ; process takes it, and its fork finds none. Needs sixteen free
        ; segments: not the floor.
        ld      hl,(t_free0)
        ld      de,16
        or      a
        sbc     hl,de
        jr      c,.floor
        ld      b,NPROC-2
.fill:  push    bc
        ld      hl,u_nap
        ld      bc,u_nap_end-u_nap
        ld      a,1
        call    t_spawn
        pop     bc
        djnz    .fill
        ld      hl,u_fork1
        ld      bc,u_fork1_end-u_fork1
        ld      a,1
        call    t_run                   ; its fork: EAGAIN, exit 1 + errno
        cp      1+E_AGAIN
        ld      c,a
        ld      a,0E5h
        jp      nz,t_fail_status
        ld      b,NPROC-2
.drain: push    bc
        ld      a,0E5h
        ld      (t_code),a
        call    t_wait_status
        pop     bc
        or      a
        ld      c,a
        ld      a,0E5h
        jp      nz,t_fail_status
        djnz    .drain
        ld      hl,t_k10e
        k_call  API_CON_PUTS
        jr      .refused
.floor: ld      hl,t_k10f
        k_call  API_CON_PUTS
.refused:
        call    t_all_back
        ld      a,0E5h
        jp      nz,t_fail

; --- step 11: the measurement -----------------------------------------------
        ld      a,11
        ld      (t_step),a
        ld      hl,t_k11
        k_call  API_CON_PUTS
        ld      hl,u_forks
        ld      bc,u_forks_end-u_forks
        ld      a,2
        call    t_spawn
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      a,0E6h
        ld      (t_code),a
        call    t_wait_status
        or      a
        ld      c,a
        ld      a,0E6h
        jp      nz,t_fail_status
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        push    hl
        ld      hl,t_k11b
        k_call  API_CON_PUTS
        pop     hl
        push    hl
        k_call  API_CON_DEC16
        ld      hl,t_k11c
        k_call  API_CON_PUTS
        pop     hl
        ld      de,T_MS100
        ld      bc,T_MS100_DIV
        call    k_muldiv                ; hl = hundredths of a ms per fork
        push    hl
        call    k_hundredths
        ld      hl,t_k11d
        k_call  API_CON_PUTS
        ld      hl,T_FORK_CALC
        call    k_hundredths
        ld      hl,t_k11e
        k_call  API_CON_PUTS
        pop     hl
        ld      de,T_FORK_MAX+1
        or      a
        sbc     hl,de
        ld      a,0E6h
        jp      nc,t_fail
        call    t_all_back
        ld      a,0E6h
        jp      nz,t_fail

; --- step 12: verdict ------------------------------------------------------
        ld      hl,t_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
        jp      t_halt

; t_all_back — Z if every row but 0 is free and every segment is back.
t_all_back:
        ld      hl,K_PROC
        ld      b,NPROC-1
.row:   ld      a,l
        add     a,P_SIZE
        ld      l,a
        ld      a,(hl)
        or      a
        ret     nz
        djnz    .row
        k_call  API_MEM_INFO
        ld      hl,(t_free0)
        or      a
        sbc     hl,bc
        ret

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

; t_fail_status — A = error code, C = the status (or errno) seen.
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

t_k5:       db  "5 fork: pid to the parent, 0 to the child, the child's memory a copy: ",0
t_ok:       db  "ok",10,0
t_k6:       db  "6 the child's change stays the child's: ",0
t_k7:       db  "7 three pages, the stack in page 2: ",0
t_k7b:      db  "(skipped: six segments needed, the floor has five)",10,0
t_k8:       db  "8 vfork shares memory and the parent sleeps; 9 wait reaps the child: ",0
t_k10:      db  "10 refused: ",0
t_k10b:     db  "EPERM from process 0, ",0
t_k10c:     db  "ENOMEM with the memory out, ",0
t_k10d:     db  "(a fork fits here, no ENOMEM), ",0
t_k10e:     db  "EAGAIN with the table full: ok",10,0
t_k10f:     db  "(no EAGAIN on the floor: the memory goes first): ok",10,0
t_k11:      db  "11 a two-page fork, 32 times",10,0
t_k11b:     db  "   ticks: ",0
t_k11c:     db  "; per fork ",0
t_k11d:     db  " ms, calculated ",0
t_k11e:     db  " ms",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_scode:    db  " code ",0
t_status:   db  " status ",0

t_step:     db  0
t_code:     db  0
t_expect:   db  0
t_free0:    dw  0
t_t0:       dw  0
        ENT

; The user programs, each assembled for P0_PROG and copied there by spawn.
; u_x is where an image is after the loader's copy, u_x_k where it is
; here.
    macro u_image name
name        equ K_IMAGE_END+(name_k-tblock)
name_end    equ name+(name_k_end-name_k)
    endm

; u_fork1 — forks; the parent then changes a variable the child exits
; with: a copy exits with the old value, 5. The parent writes P, the child
; C. Parent's status: 40 + the child's; 1 + errno if the fork was refused;
; 2 if wait failed; 3 if the child saw 0 in HL but the parent did not get
; a pid.
u_fork1_k:
        DISP    P0_PROG
        sys     SYS_FORK
        jr      c,.refused
        ld      a,h
        or      l
        jr      z,.child
        ld      a,9
        ld      (.var),a                ; after the fork: the child's copy
        ld      a,1                     ; still says 5
        ld      hl,.p
        ld      bc,1
        sys     SYS_WRITE
        sys     SYS_WAIT
        jr      c,.s2
        ld      a,l
        add     a,40
        sys     SYS_EXIT
.child: ld      a,1
        ld      hl,.c
        ld      bc,1
        sys     SYS_WRITE
        ld      a,(.var)
        sys     SYS_EXIT
.refused:
        inc     a
        sys     SYS_EXIT
.s2:    ld      a,2
        sys     SYS_EXIT
.var:   db      5
.p:     db      'P'
.c:     db      'C'
        ENT
u_fork1_k_end:
        u_image u_fork1

; u_fork2 — forks; the child changes the variable and exits; the parent
; waits and exits with its own copy, still 5. 1 + errno if refused; 2 if
; wait failed.
u_fork2_k:
        DISP    P0_PROG
        sys     SYS_FORK
        jr      c,.refused
        ld      a,h
        or      l
        jr      z,.child
        sys     SYS_WAIT
        jr      c,.s2
        ld      a,(.var)
        sys     SYS_EXIT
.child: ld      a,7
        ld      (.var),a
        xor     a
        sys     SYS_EXIT
.refused:
        inc     a
        sys     SYS_EXIT
.s2:    ld      a,2
        sys     SYS_EXIT
.var:   db      5
        ENT
u_fork2_k_end:
        u_image u_fork2

; u_fork3 — three pages, the stack at BFFEh: forks from there; the child
; exits 3; the parent exits 20 + that. 1 + errno if refused (the fork's
; errno, which is what the memory-out step wants to see); 2 if wait
; failed; 4 if the stack was not in page 2.
u_fork3_k:
        DISP    P0_PROG
        ld      hl,0
        add     hl,sp
        ld      a,h
        cp      0BFh
        jr      nz,.s4
        ld      hl,.msg
        ld      de,0A000h
        ld      bc,.msglen
        ldir                            ; something in page 2 to copy
        sys     SYS_FORK
        jr      c,.refused
        ld      a,h
        or      l
        jr      z,.child
        sys     SYS_WAIT
        jr      c,.s2
        ld      a,l
        add     a,20
        sys     SYS_EXIT
.child: ld      a,1
        ld      hl,0A000h               ; the copy of page 2, from the copy
        ld      bc,.msglen
        sys     SYS_WRITE
        ld      a,3
        sys     SYS_EXIT
.refused:
        inc     a                       ; 1 + errno
        sys     SYS_EXIT
.s2:    ld      a,2
        sys     SYS_EXIT
.s4:    ld      a,4
        sys     SYS_EXIT
.msg:   db      "  the child of three pages, writing from its page 2",10
.msglen equ     $-.msg
        ENT
u_fork3_k_end:
        u_image u_fork3

; u_vfork — vforks; the child sets the variable to 7, marks that it ran,
; spins five ticks and exits 0. The parent, resumed, must see the pid in
; HL, the mark set — it did not run before the child finished — and the
; variable at 7: shared. Then wait reaps the child with that pid and
; status 0, and a second wait is ECHILD. Exits 7 when all of that holds;
; 1 + errno if refused; 2 if the parent ran before the child finished;
; 3 if the variable is not shared; 4 if HL was 0 in the parent too; 5 if
; wait did not reap the child; 6 if a second wait found one.
u_vfork_k:
        DISP    P0_PROG
        sys     SYS_VFORK
        jr      c,.refused
        ld      a,h
        or      l
        jr      z,.child
        ld      (.pid),hl
        ld      a,(.ran)
        or      a
        jr      z,.s2
        ld      a,(.var)
        cp      7
        jr      nz,.s3
        sys     SYS_WAIT
        jr      c,.s5
        ld      a,(.pid)
        cp      h
        jr      nz,.s5
        ld      a,l
        or      a
        jr      nz,.s5
        sys     SYS_WAIT
        jr      nc,.s6
        ld      a,7
        sys     SYS_EXIT
.child: ld      a,7
        ld      (.var),a
        ld      de,(K_TICKS)
.spin:  ld      hl,(K_TICKS)
        or      a
        sbc     hl,de
        ld      a,l
        cp      5
        jr      c,.spin
        ld      a,1
        ld      (.ran),a
        xor     a
        sys     SYS_EXIT
.refused:
        inc     a
        sys     SYS_EXIT
.s2:    ld      a,2
        sys     SYS_EXIT
.s3:    ld      a,3
        sys     SYS_EXIT
.s5:    ld      a,5
        sys     SYS_EXIT
.s6:    ld      a,6
        sys     SYS_EXIT
.var:   db      5
.ran:   db      0
.pid:   dw      0
        ENT
u_vfork_k_end:
        u_image u_vfork

; u_nap — spins for 20 ticks and exits 0: a process that stays alive while
; the table is filled.
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
        cp      20
        jr      c,.loop
.done:  xor     a
        sys     SYS_EXIT
        ENT
u_nap_k_end:
        u_image u_nap

; u_forks — two pages: forks T_FORKS times, each child exiting at once
; and waited for; exits 0, or 1 + errno at the first refusal, or 2 if a
; wait failed.
u_forks_k:
        DISP    P0_PROG
        ld      a,T_FORKS
        ld      (.left),a
.next:  sys     SYS_FORK
        jr      c,.refused
        ld      a,h
        or      l
        jr      z,.child
        sys     SYS_WAIT
        jr      c,.s2
        ld      hl,.left
        dec     (hl)
        jr      nz,.next
        xor     a
        sys     SYS_EXIT
.child: xor     a
        sys     SYS_EXIT
.refused:
        inc     a
        sys     SYS_EXIT
.s2:    ld      a,2
        sys     SYS_EXIT
.left:  db      0
        ENT
u_forks_k_end:
        u_image u_forks

tblock_end:

        ASSERT  $ < 4000h
