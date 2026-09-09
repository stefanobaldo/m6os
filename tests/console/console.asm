; console — the kernel programs the screen and reads the keyboard: TEXT2 on
; its own layout with the loader's lines kept, the control codes, a write
; of many lines scrolled once, a form feed, a clear without a copy; then a
; process reads what is typed — shifted, control, CAPS, the keypad, a
; special key — keys typed ahead of a reader, a key held down repeating,
; the queue overflowing, two readers, the cursor while a reader waits,
; and the kernel's own thread reading with nothing else to run. Under
; Nextor: check the kernel, capture what the resident needs, hand the
; machine over. Then, as process 0, in a block the loader put above the
; image. The report is on screen, the verdict in the mailbox.
;
; The keys are pressed by the harness (console.tcl) on cues this program
; leaves in the mailbox's fourth byte, and the screen is checked by it at
; the same cues; on real hardware a person presses them, and the screen
; says which.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "build/kernel.exp"

_STROUT     equ 09h
_TERM       equ 62h

CUE         equ MAILBOX+3       ; the cue byte: a step number, 0 when the
                                ; harness has done its part
T_SCROLL_MAX equ 4              ; ticks a 12-line write may take from the
                                ; bottom: one copy, not twelve
T_CLEAR_MAX equ 3               ; ticks a 50-line write may take: no copy
T_TYPEAHEAD equ 60              ; ticks process 0 spins while keys arrive
T_CUE_WAIT  equ 300             ; ticks a cue waits for the harness before
                                ; the program goes on by itself
T_REP_MIN   equ 6               ; bytes from a key held 60 ticks: 1 + 30/5,
T_REP_MAX   equ 9               ; give or take the scan's phase
; What step 9's keys add up to: "hello M6", CTRL-c, CAPS a, keypad 1,
; RIGHT, RET, summed into a byte.
K_SUM9      equ ('h'+'e'+'l'+'l'+'o'+' '+'M'+'6'+3+'A'+'1'+1Ch+0Dh) & 0FFh
K_SUM10     equ ('a'+'b'+0Dh) & 0FFh

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
        ld      de,s_kbd                ; the ROM's keyboard type, and the
        call    puts                    ; VDP registers the BIOS left
        ld      a,(REC+KR_KBDTYPE)
        call    puthex8
        ld      de,s_vdp
        call    puts
        ld      a,(REC+KR_VDPREG+4)
        call    puthex8
        ld      a,' '
        call    putc
        ld      a,(REC+KR_VDPREG+7)
        call    puthex8
        ld      a,' '
        call    putc
        ld      a,(REC+KR_VDPREG+8)
        call    puthex8
        ld      a,' '
        call    putc
        ld      a,(REC+KR_VDPREG+9)
        call    puthex8
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

banner:     db  "console: m6 writes the screen and reads the keyboard",13,10,'$'
s_version:  db  "1 kernel: Nextor $"
s_notnextor: db "MSX-DOS 2, not Nextor: not supported",13,10,'$'
s_nextor3:  db  "Nextor 3 kernel: not supported",13,10,'$'
s_capture:  db  "2 wall $"
s_resident: db  "h resident $"
s_room:     db  " room $"
s_switched: db  " switched $"
s_kbd:      db  " keyboard $"
s_vdp:      db  " vdp r4 r7 r8 r9 $"
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
; --- step 5: the boot: TEXT2, the record, the screen kept --------------------
        ld      a,5
        ld      (t_step),a
        ld      hl,t_k5
        k_call  API_CON_PUTS
        ld      a,(K_REC+KR_STRIDE)
        cp      CON_COLS
        ld      c,a
        ld      a,0E1h
        jp      nz,t_fail_status        ; the loader did not leave 80 columns
        ld      hl,(K_REC+KR_NAMBAS)
        ld      a,h
        or      l
        ld      c,a
        ld      a,0E1h
        jp      nz,t_fail_status        ; the name table is not at 0
        ld      a,5
        call    t_cue                   ; the harness: the blink table zero,
        ld      hl,t_ok                 ; the banner still on row 0
        k_call  API_CON_PUTS

; --- step 6: the control codes ---------------------------------------------
        ld      a,6
        ld      (t_step),a
        ld      hl,t_k6
        ld      bc,t_k6_len
        call    t_write                 ; FF, then the script
        ld      a,6
        call    t_cue                   ; the harness reads the rows
        ld      hl,t_k6b
        k_call  API_CON_PUTS

; --- step 7: twelve lines from the bottom, one scroll ------------------------
        ld      a,7
        ld      (t_step),a
        ld      hl,t_k7
        ld      bc,t_k7_len
        call    t_write                 ; down to row 23
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      hl,t_k7b
        ld      bc,t_k7b_len
        call    t_write                 ; L01..L12
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        ld      (t_ticks),hl
        ld      a,7
        call    t_cue                   ; the harness reads the rows
        ld      hl,t_k7c
        k_call  API_CON_PUTS
        ld      hl,(t_ticks)
        k_call  API_CON_DEC16
        ld      hl,t_ticksok
        k_call  API_CON_PUTS
        ld      hl,(t_ticks)
        ld      de,T_SCROLL_MAX+1
        or      a
        sbc     hl,de
        ld      a,0E3h
        jp      nc,t_fail               ; twelve copies, not one

; --- step 8: a form feed; fifty lines, cleared without a copy ----------------
        ld      a,8
        ld      (t_step),a
        ld      hl,t_k8
        ld      bc,t_k8_len
        call    t_write                 ; FF, "8 ff"
        ld      a,8
        call    t_cue                   ; the harness: row 0, the rest blank
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      hl,t_k8b
        ld      bc,t_k8b_len
        call    t_write                 ; N01..N50
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        ld      (t_ticks),hl
        ld      a,18
        call    t_cue                   ; the harness: N28 on row 0, N50 on 22
        ld      hl,t_k8c
        k_call  API_CON_PUTS
        ld      hl,(t_ticks)
        k_call  API_CON_DEC16
        ld      hl,t_ticksok
        k_call  API_CON_PUTS
        ld      hl,(t_ticks)
        ld      de,T_CLEAR_MAX+1
        or      a
        sbc     hl,de
        ld      a,0E4h
        jp      nc,t_fail

; --- step 9: a process reads what is typed ----------------------------------
        ld      a,9
        ld      (t_step),a
        ld      hl,t_k9
        k_call  API_CON_PUTS
        ld      a,9
        call    t_cue                   ; the harness types; a person types
        ld      hl,u_echo
        ld      bc,u_echo_end-u_echo
        ld      a,1
        call    t_run                   ; a = the sum of what it read
        cp      K_SUM9
        ld      c,a
        ld      a,0E5h
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 10: typeahead ----------------------------------------------------
        ld      a,10
        ld      (t_step),a
        ld      hl,t_k10
        k_call  API_CON_PUTS
        ld      a,10
        call    t_cue                   ; the keys arrive while nobody reads
        ld      a,T_TYPEAHEAD
        call    t_spin
        ld      hl,u_echo
        ld      bc,u_echo_end-u_echo
        ld      a,1
        call    t_run
        cp      K_SUM10
        ld      c,a
        ld      a,0E6h
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 11: a key held down repeats ---------------------------------------
        ld      a,11
        ld      (t_step),a
        ld      hl,t_k11
        k_call  API_CON_PUTS
        ld      a,11
        call    t_cue                   ; 'a' held a second, then RET
        ld      hl,u_count
        ld      bc,u_count_end-u_count
        ld      a,1
        call    t_run                   ; a = bytes before the RET
        ld      c,a
        push    bc
        call    k_dec8
        pop     bc
        ld      a,c
        cp      T_REP_MIN
        ld      a,0E7h
        jp      c,t_fail_status
        ld      a,c
        cp      T_REP_MAX+1
        ld      a,0E7h
        jp      nc,t_fail_status
        ld      hl,t_k11b
        k_call  API_CON_PUTS

; --- step 12: twenty keys at once, sixteen kept -----------------------------
        ld      a,12
        ld      (t_step),a
        ld      hl,t_k12
        k_call  API_CON_PUTS
        ld      a,12
        call    t_cue                   ; twenty keys in one tick, nobody
        ld      a,30                    ; reading; then a RET once the
        call    t_spin                  ; reader has drained the queue
        ld      hl,u_count
        ld      bc,u_count_end-u_count
        ld      a,1
        call    t_run
        cp      KBD_RING_N
        ld      c,a
        ld      a,0E8h
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 13: two readers, two keys -----------------------------------------
        ld      a,13
        ld      (t_step),a
        ld      hl,t_k13
        k_call  API_CON_PUTS
        ld      a,13
        call    t_cue                   ; 'x', then 'y'
        ld      hl,u_one
        ld      bc,u_one_end-u_one
        ld      a,1
        call    t_spawn
        ld      hl,u_one
        ld      bc,u_one_end-u_one
        ld      a,1
        call    t_spawn
        ld      a,0E9h
        ld      (t_code),a
        call    t_wait_status
        ld      (t_st),a
        call    t_wait_status
        ld      c,a
        ld      a,(t_st)
        add     a,c
        cp      'x'+'y'
        ld      a,0E9h
        jp      nz,t_fail_status
        ld      a,(t_st)
        cp      'x'
        jr      z,.xy
        cp      'y'
        ld      c,a
        ld      a,0E9h
        jp      nz,t_fail_status
.xy:    ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 14: the cursor while a reader waits -------------------------------
        ld      a,14
        ld      (t_step),a
        ld      hl,t_k14
        k_call  API_CON_PUTS
        ld      a,14
        call    t_cue                   ; the harness reads the blink table
        ld      hl,u_one                ; while the reader waits, then 'z'
        ld      bc,u_one_end-u_one
        ld      a,1
        call    t_run
        cp      'z'
        ld      c,a
        ld      a,0EAh
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 15: process 0 reads with nothing else to run ----------------------
        ld      a,15
        ld      (t_step),a
        ld      hl,t_k15
        k_call  API_CON_PUTS
        ld      a,15
        call    t_cue                   ; 'q', in a while
        xor     a
        ld      hl,t_buf
        ld      bc,4
        k_call  API_READ                ; the ring is empty: the idle loop
        ld      c,a
        ld      a,0EBh
        jp      c,t_fail_status
        ld      a,l
        cp      1
        ld      c,a
        ld      a,0EBh
        jp      nz,t_fail_status        ; one byte, not more
        ld      a,(t_buf)
        cp      'q'
        ld      c,a
        ld      a,0EBh
        jp      nz,t_fail_status
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 16: verdict ------------------------------------------------------
        ld      hl,t_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
        jp      t_halt

; t_cue — A = a cue: into the mailbox's fourth byte, then wait for the
; harness to clear it. On real hardware nothing clears it, so the program
; clears it itself after T_CUE_WAIT ticks and goes on: the person at the
; keyboard types what the screen asked for, and the reader that follows
; the cue gets it, typed ahead or not.
t_cue:
        ld      (CUE),a
        ld      hl,(K_TICKS)
        ld      (t_t1),hl
.wait:  ld      a,(CUE)
        or      a
        ret     z
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
        ret

; t_spin — A = ticks: spin that long, calling nothing.
t_spin:
        ld      c,a
        ld      de,(K_TICKS)
.loop:  ld      hl,(K_TICKS)
        or      a
        sbc     hl,de
        ld      a,l
        cp      c
        jr      c,.loop
        ret

; t_write — HL -> bytes, BC = count: one write through the syscall table,
; as a process would.
t_write:
        ld      a,1
        sys     SYS_WRITE
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

; t_fail_status — A = error code, C = the status (or errno, or byte) seen.
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

t_k5:       db  "5 the boot: 80 columns, the name table at 0, the screen kept: ",0
t_ok:       db  "ok",10,0
t_k6:       db  12,"6 controls:",10,"abc",8,"d",9,"x",13,"Z",10
            DUP 80
            db  "w"
            EDUP
            db  "!",10
t_k6_len    equ $-t_k6
t_k6b:      db  "  BS, TAB, CR, wrap: ok",10,0
t_k7:       db  "7 twelve lines from the bottom in one write:"
            DUP 19
            db  10
            EDUP
t_k7_len    equ $-t_k7
t_k7b:      db  "L01",10,"L02",10,"L03",10,"L04",10,"L05",10,"L06",10
            db  "L07",10,"L08",10,"L09",10,"L10",10,"L11",10,"L12",10
t_k7b_len   equ $-t_k7b
t_k7c:      db  "  one scroll of twelve rows in ",0
t_ticksok:  db  " ticks: ok",10,0
t_k8:       db  12,"8 ff",10
t_k8_len    equ $-t_k8
t_k8b:
    DUP 50, i
            db  "N",'0'+(i+1)/10,'0'+(i+1)%10,10
    EDUP
t_k8b_len   equ $-t_k8b
t_k8c:      db  "  fifty lines, cleared without a copy, in ",0
t_k9:       db  "9 type: hello SHIFT-m 6 CTRL-c CAPS a CAPS keypad-1 RIGHT RET",10,0
t_k10:      db  "10 typeahead: type a b RET within a second, nobody reading",10,0
t_k11:      db  "11 repeat: hold a for a second, then RET",10,0
t_k11b:     db  " bytes: ok",10,0
t_k12:      db  "12 overflow: twenty keys at once, then RET after a second",10,0
t_k13:      db  "13 two readers: x, then y",10,0
t_k14:      db  "14 the cursor while a reader waits: z",10,0
t_k15:      db  "15 process 0 reads with nothing to run: q",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_scode:    db  " code ",0
t_status:   db  " status ",0

t_step:     db  0
t_code:     db  0
t_st:       db  0
t_t0:       dw  0
t_t1:       dw  0
t_ticks:    dw  0
t_buf:      ds  4
        ENT

; The user programs, each assembled for P0_PROG and copied there by spawn.
; u_x is where an image is after the loader's copy, u_x_k where it is
; here.
    macro u_image name
name        equ K_IMAGE_END+(name_k-tblock)
name_end    equ name+(name_k_end-name_k)
    endm

; u_echo — reads a byte at a time, echoes each, sums them, and exits with
; the sum after a RET (13, which is in the sum). A failed read exits 1.
u_echo_k:
        DISP    P0_PROG
.next:  xor     a
        ld      hl,.buf
        ld      bc,1
        sys     SYS_READ
        jr      c,.bad
        ld      a,(.buf)
        ld      hl,.sum
        add     a,(hl)
        ld      (hl),a
        ld      a,1
        ld      hl,.buf
        ld      bc,1
        sys     SYS_WRITE
        ld      a,(.buf)
        cp      13
        jr      nz,.next
        ld      a,(.sum)
        sys     SYS_EXIT
.bad:   ld      a,1
        sys     SYS_EXIT
.buf:   db      0
.sum:   db      0
        ENT
u_echo_k_end:
        u_image u_echo

; u_count — reads a byte at a time and exits with how many came before
; the RET.
u_count_k:
        DISP    P0_PROG
.next:  xor     a
        ld      hl,.buf
        ld      bc,1
        sys     SYS_READ
        jr      c,.bad
        ld      a,(.buf)
        cp      13
        jr      z,.done
        ld      hl,.n
        inc     (hl)
        jr      .next
.done:  ld      a,(.n)
        sys     SYS_EXIT
.bad:   ld      a,1
        sys     SYS_EXIT
.buf:   db      0
.n:     db      0
        ENT
u_count_k_end:
        u_image u_count

; u_one — reads one byte and exits with it.
u_one_k:
        DISP    P0_PROG
        xor     a
        ld      hl,.buf
        ld      bc,1
        sys     SYS_READ
        jr      c,.bad
        ld      a,(.buf)
        sys     SYS_EXIT
.bad:   ld      a,1
        sys     SYS_EXIT
.buf:   db      0
        ENT
u_one_k_end:
        u_image u_one

tblock_end:

        ASSERT  $ < 4000h
