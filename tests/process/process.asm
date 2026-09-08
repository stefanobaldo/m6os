; process — the kernel creates a process, runs it in the 48K window, serves
; its syscalls and takes its exit; and the syscall round trip is measured.
; Under Nextor: check the kernel, capture what the resident needs, hand the
; machine over with the switched part of the kernel in the record. Then, in
; a block the loader put above the image: the window kernel-side, a process
; that exercises every syscall and every error, a program that ends in ret
; and one that jumps to 0, a three-page process with its stack in page 2,
; ENOMEM, and three processes that time the resident and the switched
; paths. The report is on screen, the verdict in the mailbox.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "build/kernel.exp"

_STROUT     equ 09h
_TERM       equ 62h
CALSLT      equ B_CALSLT

; The measurement: iterations of sixteen calls each, and the constant that
; turns ticks over that many calls into hundredths of a microsecond at
; 60 Hz — 16 666.67 us per tick / 524 288 calls = 0.031789 us, times 100,
; as 3179 / 1000.
T_ITER      equ 32768
T_US100     equ 3179
T_RES_MAX   equ 2000            ; the gate: 20.00 us resident
T_SW_MAX    equ 10000           ; 100.00 us switched

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

banner:     db  "process: m6 runs a process and serves its syscalls",13,10,'$'
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
; --- step 5: the window, kernel-side ---------------------------------------
        ld      a,5
        ld      (t_step),a
        ld      hl,t_k5
        k_call  API_CON_PUTS
        ld      a,(K_KSEG)
        or      a
        ld      a,0E1h
        jp      z,t_fail                ; not loaded
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
        ld      hl,SC_PAGESIZE
        ld      a,(K_KSEG)
        out     (0FEh),a                ; the window in, by hand
        call    KS_SYSCONF
        ld      a,(K_REC+KR_SEG64K+2)
        out     (0FEh),a                ; and out
        ld      a,0E1h
        jp      c,t_fail
        ld      de,4000h
        or      a
        sbc     hl,de
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 6: a process, every syscall, every error, exit(42) ---------------
        ld      a,6
        ld      (t_step),a
        ld      hl,t_k6
        k_call  API_CON_PUTS
        ld      hl,u_hello
        ld      bc,u_hello_end-u_hello
        ld      a,1
        call    t_run                   ; a = status
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
        ld      hl,t_k6b
        k_call  API_CON_PUTS

; --- step 7: ret, and jp 0 ---------------------------------------------------
        ld      a,7
        ld      (t_step),a
        ld      hl,t_k7
        k_call  API_CON_PUTS
        ld      hl,u_ret
        ld      bc,u_ret_end-u_ret
        ld      a,1
        call    t_run
        ld      c,a
        or      a
        ld      a,0E3h
        jp      nz,t_fail_status
        ld      hl,t_ok2
        k_call  API_CON_PUTS
        ld      hl,t_k7b
        k_call  API_CON_PUTS
        ld      hl,u_jp0
        ld      bc,u_jp0_end-u_jp0
        ld      a,1
        call    t_run
        ld      c,a
        or      a
        ld      a,0E3h
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 8: three pages, the stack in page 2 ---------------------------
        ld      a,8
        ld      (t_step),a
        ld      hl,t_k8
        k_call  API_CON_PUTS
        ld      hl,u_stack3
        ld      bc,u_stack3_end-u_stack3
        ld      a,3
        call    t_run
        cp      7
        ld      c,a
        ld      a,0E4h
        jp      nz,t_fail_status
        ld      hl,t_k8b
        k_call  API_CON_PUTS

; --- step 9: ENOMEM ---------------------------------------------------------
        ld      a,9
        ld      (t_step),a
        ld      hl,t_k9
        k_call  API_CON_PUTS
.take:  ld      b,2                     ; every free segment, as owner 2
        k_call  API_MEM_ALLOC
        jr      nc,.take
        ld      hl,u_ret
        ld      bc,u_ret_end-u_ret
        ld      a,1
        k_call  API_SPAWN
        ld      c,a
        ld      a,0E5h
        jp      nc,t_fail               ; it created one out of nothing
        ld      a,c
        cp      E_NOMEM
        ld      a,0E5h
        jp      nz,t_fail
        k_call  API_MEM_INFO
        ld      a,b
        or      c
        ld      a,0E5h
        jp      nz,t_fail               ; it left something allocated
        ld      b,2
        k_call  API_MEM_FREE_ALL
        k_call  API_MEM_INFO
        ld      hl,(t_free0)
        or      a
        sbc     hl,bc
        ld      a,0E5h
        jp      nz,t_fail
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 10: the measurement ---------------------------------------------
        ld      a,10
        ld      (t_step),a
        ld      hl,t_k10
        k_call  API_CON_PUTS
        ld      hl,u_ctl
        ld      bc,u_ctl_end-u_ctl
        call    t_time
        ld      (t_ctl),hl
        ld      hl,u_res
        ld      bc,u_res_end-u_res
        call    t_time
        ld      de,(t_ctl)
        or      a
        sbc     hl,de
        ld      (t_res),hl
        ld      hl,u_sw
        ld      bc,u_sw_end-u_sw
        call    t_time
        ld      de,(t_ctl)
        or      a
        sbc     hl,de
        ld      (t_sw),hl
        ld      hl,t_k10b
        k_call  API_CON_PUTS
        ld      hl,(t_res)
        call    t_percall               ; hl = hundredths of us
        ld      de,T_RES_MAX+1
        or      a
        sbc     hl,de
        ld      a,0E6h
        jp      nc,t_fail
        ld      hl,t_k10c
        k_call  API_CON_PUTS
        ld      hl,(t_sw)
        call    t_percall
        ld      de,T_SW_MAX+1
        or      a
        sbc     hl,de
        ld      a,0E6h
        jp      nc,t_fail

; --- step 11: verdict ------------------------------------------------------
        ld      hl,t_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
        jp      t_halt

; t_run — HL = image, BC = length, A = pages: spawn it and wait for it.
; Out: A = the exit status. A refused spawn fails the step with code E0 and
; the errno printed.
t_run:
        k_call  API_SPAWN
        jr      nc,.run
        ld      c,a
        ld      a,0E0h
        jp      t_fail_status
.run:   k_call  API_WAIT
        ld      a,l
        ret

; t_time — HL = image, BC = length, one page: run it and return the ticks
; it took in HL. A status other than 0 fails the step (E6).
t_time:
        ld      a,1
        k_call  API_SPAWN
        jr      nc,.run
        ld      c,a
        ld      a,0E0h
        jp      t_fail_status
.run:   ld      hl,(K_TICKS)
        ld      (t_t0),hl
        k_call  API_WAIT
        ld      a,l
        ld      c,a
        or      a
        ld      a,0E6h
        jp      nz,t_fail_status
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        ret

; t_percall — HL = ticks over T_ITER*16 calls: print "T ticks = N.NN us",
; return HL = the hundredths of a microsecond.
t_percall:
        push    hl
        k_call  API_CON_DEC16
        ld      hl,t_ticks
        k_call  API_CON_PUTS
        pop     hl
        ld      de,T_US100
        ld      bc,1000
        call    k_muldiv
        push    hl
        call    k_hundredths
        ld      hl,t_us
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
        ld      hl,t_code
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
        ld      hl,t_code
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

t_halt:
        ei
        halt
        jr      t_halt

        include "m6util.asm"

t_k5:       db  "5 switched kernel: ",0
t_k5b:      db  "segment ",0
t_k5c:      db  ", sysconf through the window: ",0
t_ok:       db  "ok",10,0
t_ok2:      db  "ok  ",0
t_k6:       db  "6 ",0
t_k6b:      db  "  exit 42, segments freed: ok",10,0
t_k7:       db  "7 ret: ",0
t_k7b:      db  "jp 0: ",0
t_k8:       db  "8 three pages:",10,0
t_k8b:      db  "  exit 7: ok",10,0
t_k9:       db  "9 no segment: ",0
t_k10:      db  "10 round trip over 524288 calls",10,0
t_k10b:     db  "   resident: ",0
t_k10c:     db  "   switched: ",0
t_ticks:    db  " ticks = ",0
t_us:       db  " us",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_code:     db  " code ",0
t_status:   db  " status ",0

t_step:     db  0
t_free0:    dw  0
t_t0:       dw  0
t_ctl:      dw  0
t_res:      dw  0
t_sw:       dw  0
        ENT

; The user programs, each assembled for P0_PROG and copied there by spawn.
; They call the kernel through K_SYS and nothing else. They live in the
; block, in page 3 once the loader has copied it, where process 0 reads
; them: u_x is where an image is after the copy, u_x_k where it is here.

; u_hello — every syscall and every error, then exit(42). A check that
; fails exits with its own status, 1 to 4.
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
        cp      1
        jr      nz,.s1
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
.msg:   db      "hello from pid "
.msglen equ     $-.msg
.digit: db      "?",10
        ENT
u_hello_k_end:
u_hello      equ K_IMAGE_END+(u_hello_k-tblock)
u_hello_end  equ u_hello+(u_hello_k_end-u_hello_k)

; u_ret — a program that simply returns: status 0 through P0_EXIT.
u_ret_k:
        DISP    P0_PROG
        ret
        ENT
u_ret_k_end:
u_ret      equ K_IMAGE_END+(u_ret_k-tblock)
u_ret_end  equ u_ret+(u_ret_k_end-u_ret_k)

; u_jp0 — a program that jumps to 0: the same.
u_jp0_k:
        DISP    P0_PROG
        jp      0
        ENT
u_jp0_k_end:
u_jp0      equ K_IMAGE_END+(u_jp0_k-tblock)
u_jp0_end  equ u_jp0+(u_jp0_k_end-u_jp0_k)

; u_stack3 — three pages: the stack starts at BFFEh, in the page the window
; takes. A switched syscall from there, then a write of a buffer it puts in
; page 2, then exit(7). Status 1: the stack is not where it should be;
; 2: sysconf failed.
u_stack3_k:
        DISP    P0_PROG
        ld      hl,0
        add     hl,sp
        ld      a,h
        cp      0BFh
        jr      nz,.s1
        ld      hl,SC_PAGESIZE
        sys     SYS_SYSCONF
        jr      c,.s2
        ld      de,4000h
        or      a
        sbc     hl,de
        jr      nz,.s2
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
.msg:   db      "  stack in page 2, buffer at A000h",10
.msglen equ     $-.msg
        ENT
u_stack3_k_end:
u_stack3      equ K_IMAGE_END+(u_stack3_k-tblock)
u_stack3_end  equ u_stack3+(u_stack3_k_end-u_stack3_k)

; The three timing loops: T_ITER iterations of push bc, sixteen argument
; loads, sixteen calls or none, pop bc. The push and pop are there because
; the ABI preserves nothing; the loads are in all three so that the
; difference is the call, the body and the return alone.
    macro t_arg
        ld      hl,SC_PAGESIZE
    endm

u_ctl_k:
        DISP    P0_PROG
        ld      bc,T_ITER
.loop:  push    bc
        DUP     16
        t_arg
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
u_ctl      equ K_IMAGE_END+(u_ctl_k-tblock)
u_ctl_end  equ u_ctl+(u_ctl_k_end-u_ctl_k)

u_res_k:
        DISP    P0_PROG
        ld      bc,T_ITER
.loop:  push    bc
        DUP     16
        t_arg
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
u_res_k_end:
u_res      equ K_IMAGE_END+(u_res_k-tblock)
u_res_end  equ u_res+(u_res_k_end-u_res_k)

u_sw_k:
        DISP    P0_PROG
        ld      bc,T_ITER
.loop:  push    bc
        DUP     16
        t_arg
        sys     SYS_SYSCONF
        EDUP
        pop     bc
        dec     bc
        ld      a,b
        or      c
        jr      nz,.loop
        xor     a
        sys     SYS_EXIT
        ENT
u_sw_k_end:
u_sw      equ K_IMAGE_END+(u_sw_k-tblock)
u_sw_end  equ u_sw+(u_sw_k_end-u_sw_k)

tblock_end:

        ASSERT  $ < 4000h
