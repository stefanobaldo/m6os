; k_main — what the resident does once it owns the machine. Today that is
; the second half of tests/takeover: prove the Nextor kernel is gone and the
; cartridge's driver still answers, measure the call, report, halt. The
; step numbers continue the loader's; the report goes to the console and
; the verdict to the mailbox the harness reads.

k_main:
        call    k_irq_init
        ei
        call    con_init

; --- step 8: destroy the Nextor kernel's RAM segments ------------------
        ld      a,8
        ld      (k_step),a
        ld      a,(K_REC+KR_CODESEG)
        out     (0FEh),a                ; page 2 shows the kernel code segment
        call    k_fill_p2
        ld      a,(K_REC+KR_DATASEG)
        out     (0FEh),a
        call    k_fill_p2
        ld      a,(K_REC+KR_SEG64K+2)
        out     (0FEh),a                ; page 2 is the test's again
        ld      hl,s_k8
        call    con_puts
        ld      a,(K_REC+KR_CODESEG)
        call    con_dec8
        ld      hl,s_and
        call    con_puts
        ld      a,(K_REC+KR_DATASEG)
        call    con_dec8
        ld      hl,s_k8b
        call    con_puts

; --- step 9: where m6 is ----------------------------------------------
        ld      a,9
        ld      (k_step),a
        ld      hl,s_k9
        call    con_puts
        ld      hl,(K_REC+KR_WALL)
        call    con_hex16
        ld      hl,s_resident
        call    con_puts
        ld      hl,(K_END)
        ld      de,K_BASE
        or      a
        sbc     hl,de
        call    con_dec16
        ld      hl,s_room
        call    con_puts
        ld      hl,(K_REC+KR_WALL)
        ld      de,(K_END)
        or      a
        sbc     hl,de
        call    con_dec16
        ld      hl,s_nl
        call    con_puts

; --- step 10: read with the kernel gone -------------------------------
        ld      a,10
        ld      (k_step),a
        ld      hl,s_k10
        call    con_puts
        call    k_sec_first
        call    k_rw_read
        jp      nz,k_fail
        ld      hl,KT_BUF_A
        ld      de,KT_BUF_B
        call    k_cmp512
        jp      nz,k_fail_cmp
        ld      hl,s_ok
        call    con_puts

; --- step 11: write with the kernel gone ------------------------------
        ld      a,11
        ld      (k_step),a
        ld      hl,s_k11
        call    con_puts
        ld      a,0A5h                  ; pattern P2
        call    k_fill_c
        ld      hl,K_REC+KR_TARGET
        ld      de,k_secnum
        ld      bc,4
        ldir
        ld      ix,K_REC+KR_DRV
        scf                             ; write
        ld      b,1
        ld      hl,KT_BUF_C
        ld      de,k_secnum
        call    nx_rw
        or      a
        jp      nz,k_fail
        call    k_rw_read               ; k_secnum is still the target
        jp      nz,k_fail
        ld      hl,KT_BUF_C
        ld      de,KT_BUF_B
        call    k_cmp512
        jp      nz,k_fail_cmp
        ld      hl,s_ok
        call    con_puts

; --- step 12: the same 600 reads, counted by m6, checked against the RTC --
; Ticks count real time, so this loop takes fewer of them than it did under
; Nextor by whatever the BIOS and Nextor interrupt handlers used to cost —
; which is also what a lost tick would look like, so the two counts cannot
; be compared. The real-time clock is the independent reference: the loop
; watches its seconds digit, and between the first and the last change it
; sees, n whole seconds pass; k_ticks must have advanced by 60 n, within
; K_TICK_TOL, while the driver was being called.
        ld      a,12
        ld      (k_step),a
        ld      hl,s_k12
        call    con_puts
        ld      hl,k_rw_read
        ld      (k_loop_fn),hl
        call    k_loop600
        ld      (k_tpost),hl
        call    con_dec16
        ld      hl,s_nextor
        call    con_puts
        ld      hl,(K_REC+KR_TPRE)
        call    con_dec16
        ld      hl,s_close
        call    con_puts
        ld      hl,s_rtc
        call    con_puts
        ld      a,(k_rtc_n)
        dec     a                       ; changes seen - 1 = whole seconds
        ld      a,0F7h                  ; the clock did not advance twice
        jp      m,k_fail
        jp      z,k_fail
        ld      a,(k_rtc_n)
        dec     a
        ld      (k_rtc_n),a
        call    con_dec8
        ld      hl,s_rtcb
        call    con_puts
        ld      hl,(k_rtc_last)
        ld      de,(k_rtc_first)
        or      a
        sbc     hl,de                   ; ticks over those seconds
        push    hl
        call    con_dec16
        pop     hl
        ld      a,(k_rtc_n)
        ld      d,0
        ld      e,a
        ld      b,60
.x60:   or      a
        sbc     hl,de                   ; hl -= n, sixty times: hl - 60 n
        djnz    .x60
        jr      nc,.abs
        ex      de,hl
        ld      hl,0
        or      a
        sbc     hl,de                   ; |ticks - 60 n|
.abs:   ld      de,K_TICK_TOL+1
        or      a
        sbc     hl,de
        ld      a,0F6h                  ; ticks were lost
        jp      nc,k_fail
        ld      hl,s_tickok
        call    con_puts

; --- step 13: the loop without the call, and the call isolated ----------
        ld      a,13
        ld      (k_step),a
        ld      hl,s_k13
        call    con_puts
        ld      hl,k_rw_none
        ld      (k_loop_fn),hl
        call    k_loop600
        ld      (k_tcmp),hl
        call    con_dec16
        ld      hl,s_nextor
        call    con_puts
        ld      hl,(K_REC+KR_TPRECMP)
        call    con_dec16
        ld      hl,s_close
        call    con_puts
        ld      hl,s_call
        call    con_puts
        ld      hl,(k_tpost)
        ld      de,(k_tcmp)
        or      a
        sbc     hl,de                   ; the call's ticks over 600 iterations
        push    hl
        call    con_dec16
        ld      hl,s_callb
        call    con_puts
        pop     hl
        ld      de,1667                 ; hundredths of a millisecond per tick
        ld      bc,600
        call    k_muldiv
        call    con_hundredths
        ld      hl,s_callc
        call    con_puts

; --- step 14: verdict -------------------------------------------------
        ld      hl,s_pass
        call    con_puts
        m6_verdict M6_PASS
        jr      k_halt

; k_fail — A = error code, (k_step) = the step.
k_fail:
        push    af
        ld      a,10
        call    con_putc
        ld      hl,s_fail
        call    con_puts
        ld      a,(k_step)
        call    con_dec8
        ld      hl,s_code
        call    con_puts
        pop     af
        call    con_hex8
        ld      a,10
        call    con_putc
        m6_verdict M6_FAIL
        jr      k_halt

; k_fail_cmp — HL = offset of the first difference, B = expected, C = found.
k_fail_cmp:
        push    hl
        push    bc
        ld      a,10
        call    con_putc
        ld      hl,s_fail
        call    con_puts
        ld      a,(k_step)
        call    con_dec8
        ld      hl,s_diff
        call    con_puts
        pop     bc
        pop     hl
        push    bc
        call    con_hex16
        ld      a,' '
        call    con_putc
        pop     bc
        ld      a,b
        call    con_hex8
        ld      a,' '
        call    con_putc
        ld      a,c
        call    con_hex8
        ld      a,10
        call    con_putc
        m6_verdict M6_FAIL
        jr      k_halt

; k_halt — nothing left to do: halt with interrupts on, so the tick counter
; keeps running for anyone watching it, and stay halted.
k_halt:
        ei
        halt
        jr      k_halt

; k_loop600 — 600 times: k_secnum = first, call (k_loop_fn), compare
; KT_BUF_A with KT_BUF_B; meanwhile watch the RTC's seconds digit and note
; k_ticks at its first and last change (k_rtc_first, k_rtc_last, k_rtc_n
; changes). Returns HL = ticks elapsed. Fails through k_fail.
k_loop600:
        ld      a,13                    ; RTC mode register: block 0 (time),
        out     (0B4h),a                ; timer running
        ld      a,08h
        out     (0B5h),a
        call    k_rtc_sec
        ld      (k_rtc_prev),a
        xor     a
        ld      (k_rtc_n),a
        ld      hl,(K_TICKS)
        ld      (k_t0),hl
        ld      hl,600
.loop:  ld      (k_n),hl
        call    k_rtc_watch
        call    k_sec_first
        ld      hl,(k_loop_fn)
        call    k_call_hl
        jp      nz,k_fail
        ld      hl,KT_BUF_A
        ld      de,KT_BUF_B
        call    k_cmp512
        jp      nz,k_fail_cmp
        ld      hl,(k_n)
        dec     hl
        ld      a,h
        or      l
        jr      nz,.loop
        ld      hl,(K_TICKS)
        ld      de,(k_t0)
        or      a
        sbc     hl,de
        ret

; k_rtc_sec — A = the RTC's seconds units digit (register 0, block 0).
k_rtc_sec:
        xor     a
        out     (0B4h),a
        in      a,(0B5h)
        and     0Fh
        ret

; k_rtc_watch — if the seconds digit has moved on by one since the last
; look, note k_ticks. A value that is not the next digit is a read caught
; mid-carry and is ignored.
k_rtc_watch:
        call    k_rtc_sec
        ld      b,a
        ld      a,(k_rtc_prev)
        cp      b
        ret     z
        inc     a
        cp      10
        jr      nz,.next
        xor     a
.next:  cp      b
        ret     nz
        ld      (k_rtc_prev),a
        ld      hl,(K_TICKS)
        ld      (k_rtc_last),hl
        ld      a,(k_rtc_n)
        or      a
        jr      nz,.count
        ld      (k_rtc_first),hl
.count: inc     a
        ld      (k_rtc_n),a
        ret
k_call_hl:
        jp      (hl)

; k_rw_read — one sector, k_secnum, into KT_BUF_B through the driver.
; Z if ok, else NZ with A = the driver's error code.
k_rw_read:
        ld      ix,K_REC+KR_DRV
        or      a
        ld      b,1
        ld      hl,KT_BUF_B
        ld      de,k_secnum
        call    nx_rw
        or      a
        ret

; k_rw_none — what the loop calls instead of the driver in step 13.
k_rw_none:
        xor     a
        ret

; k_sec_first — k_secnum = the partition's first device sector.
k_sec_first:
        ld      hl,K_REC+KR_FIRST
        ld      de,k_secnum
        ld      bc,4
        ldir
        ret

; k_fill_p2 — fill page 2 with AAh.
k_fill_p2:
        ld      hl,8000h
        ld      (hl),0AAh
        ld      de,8001h
        ld      bc,3FFFh
        ldir
        ret

; k_fill_c — KT_BUF_C byte i = (i and 0FFh) xor A.
k_fill_c:
        ld      c,a
        ld      hl,KT_BUF_C
        ld      d,2
.outer: ld      b,0
        ld      e,0
.inner: ld      a,e
        xor     c
        ld      (hl),a
        inc     hl
        inc     e
        djnz    .inner
        dec     d
        jr      nz,.outer
        ret

; k_cmp512 — compare 512 bytes at HL and DE. Z if equal; otherwise NZ with
; HL = offset of the first difference, B = byte at HL, C = byte at DE.
k_cmp512:
        push    hl
        ld      bc,512
.loop:  ld      a,(de)
        cp      (hl)
        jr      nz,.diff
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.loop
        pop     hl
        ret
.diff:  ld      b,(hl)
        ld      c,a
        pop     de
        or      a
        sbc     hl,de
        ret

; k_muldiv — HL = HL * DE / BC, through a 24-bit product; HL and the
; quotient must fit 16 bits. Multiplies by repeated addition and divides by
; repeated subtraction: slow and obviously right, for numbers printed once.
; Corrupts AF, BC, DE.
k_muldiv:
        push    bc
        ld      b,h
        ld      c,l                     ; bc = multiplier
        ld      hl,0
        exx
        ld      hl,0                    ; hl' = quotient; c' = product high
        ld      c,0
        exx
.mul:   ld      a,b
        or      c
        jr      z,.divide
        add     hl,de
        jr      nc,.nc
        exx
        inc     c
        exx
.nc:    dec     bc
        jr      .mul
.divide:
        pop     de                      ; de = divisor
.div:   exx
        ld      a,c
        exx
        or      a
        jr      nz,.sub                 ; high byte set: certainly >= divisor
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      c,.done
.sub:   or      a
        sbc     hl,de
        jr      nc,.nb
        exx
        dec     c
        exx
.nb:    exx
        inc     hl
        exx
        jr      .div
.done:  exx
        push    hl
        exx
        pop     hl
        ret

; con_dec8 — A in decimal. Corrupts AF, DE, HL.
con_dec8:
        ld      l,a
        ld      h,0
        jp      con_dec16

K_TICK_TOL      equ 4           ; ticks the count over n RTC seconds may
                                ; differ from 60 n by: 59.92 Hz over ~8 s is
                                ; under one, plus one at each end

s_k8:       db  "8 kernel segments ",0
s_and:      db  " and ",0
s_k8b:      db  " overwritten",10,0
s_k9:       db  "9 m6: wall ",0
s_resident: db  "h resident ",0
s_room:     db  " room ",0
s_k10:      db  "10 read with kernel out: ",0
s_k11:      db  "11 write with kernel out: ",0
s_k12:      db  "12 600 reads under m6: ",0
s_nextor:   db  " ticks (Nextor: ",0
s_close:    db  ")",10,0
s_rtc:      db  "   rtc: ",0
s_rtcb:     db  " s = ",0
s_tickok:   db  " ticks: tick ok",10,0
s_k13:      db  "13 without the call: ",0
s_call:     db  "   call = ",0
s_callb:    db  " ticks/600 = ",0
s_callc:    db  " ms at 60 Hz",10,0
s_ok:       db  "ok",10,0
s_nl:       db  10,0
s_pass:     db  "PASS",10,0
s_fail:     db  "FAIL step ",0
s_code:     db  " code ",0
s_diff:     db  " differ at ",0

k_step:     db  0
k_n:        dw  0
k_t0:       dw  0
k_tpost:    dw  0
k_tcmp:     dw  0
k_rtc_prev: db  0
k_rtc_n:    db  0
k_rtc_first: dw 0
k_rtc_last: dw  0
k_loop_fn:  dw  0
k_secnum:   ds  4
