; blkspike — what a driver call of 1, 2, 4 and 8 sectors costs: the
; interrupt-disabled region per call and per sector, by difference between
; a loop with the call and the same loop without it, and the ticks the
; kernel counts against the real-time clock while the calls are made. The
; numbers decide nothing in the emulator; on the Omega they are what one
; sector per call is measured against. The verdict is functional: every
; B returned the same bytes as B = 1. Under Nextor: the driver behind the
; current drive and the capture, then the takeover; the block above the
; image does the loops, calling the driver directly through the resident.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "build/kernel.exp"

_STROUT     equ 09h
_CURDRV     equ 19h
_TERM       equ 62h

        org     100h

start:
        ld      sp,KT_LSTACK
        ld      a,DBG_ASCII
        out     (DBG_MODE),a
        call    ld_screen80
        ld      de,banner
        call    puts
        ld      a,1
        ld      (step),a
        call    ld_nextor2
        jp      nz,fail
        ld      a,2
        ld      (step),a
        ld      c,_CURDRV
        call    BDOS
        ld      ix,REC+KR_DRV
        ld      hl,KT_SCRATCH
        call    nx_find
        or      a
        jp      nz,fail
        ld      (REC+KR_FIRST),hl
        ld      (REC+KR_FIRST+2),de
        ld      a,3
        ld      (step),a
        ld      ix,REC
        call    nx_capture
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
        jp      fail

fail:
        push    af
        ld      de,s_fail
        call    puts
        ld      a,(step)
        add     a,'0'
        call    putc
        ld      de,s_code
        call    puts
        pop     af
        call    puthex8
        ld      de,s_nl
        call    puts
        m6_verdict M6_FAIL
        ld      b,1
        ld      c,_TERM
        jp      BDOS

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

banner:     db  "blkspike: sectors per driver call",13,10,'$'
s_takeover: db  "-- taking the machine --",13,10,'$'
s_fail:     db  "FAIL step $"
s_code:     db  " code $"
s_nl:       db  13,10,'$'
chbuf:      db  0,'$'
step:       db  0
REC:        ds  KREC_SIZE

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
        ASSERT  ksimage_end < 8000h

; The block: for B in 1, 2, 4, 8 — N calls of B sectors from the boot
; volume's first sector into the storage segment's buffers 0-7 (process
; 0's page 2, as DEV_RW wants), the same N iterations without the call,
; the difference as the call's cost, and the RTC's seconds watched during
; the loop with the call as takeover's step 12 does. N = 600 / B, so that
; every B moves the same 600 sectors and the loop with the call lasts the
; same ~13 s on the bench and the RTC sees several whole seconds at every
; B. Both loops compare the B sectors with a reference read once before
; them (buffers 8-15), so the compare cancels in the difference and the
; verdict is that every B returned the same bytes.
N_SECTORS       equ 2400
BUF_XFER        equ 8000h+ST_BUF        ; buffers 0-7: up to 8 sectors
BUF_REF         equ 8000h+ST_BUF+8*512  ; buffers 8-15: the reference

tblock:
        DISP    K_IMAGE_END
t_entry:
        ld      hl,t_head
        k_call  API_CON_PUTS
        ; The reference: the volume's first eight sectors, once. Eight,
        ; not one: a call of B sectors returns B consecutive sectors, and
        ; the check below holds each of them against the sector that
        ; belongs at its place.
        ld      a,8
        ld      (t_b),a
        call    t_rw
        jp      nz,t_fail
        ld      hl,BUF_XFER
        ld      de,BUF_REF
        ld      bc,8*512
        ldir
        ld      a,1
        ld      (t_b),a
.b:     ; The loop with the call, watched against the RTC; its watch kept
        ; aside before the loop without the call overwrites it.
        ld      hl,t_rw
        ld      (t_fn),hl
        call    t_loop
        ld      (t_tcall),hl
        ld      hl,t_rtc_n
        ld      de,t_rtcs_n
        ld      bc,5
        ldir
        ld      hl,t_none
        ld      (t_fn),hl
        call    t_loop
        ld      (t_tnone),hl
        ; The line: B, ms per call, ms per sector, RTC seconds, ticks
        ; counted and expected, lost.
        ld      hl,t_sb
        k_call  API_CON_PUTS
        ld      a,(t_b)
        call    k_dec8
        ld      hl,t_scall
        k_call  API_CON_PUTS
        ld      hl,(t_tcall)
        ld      de,(t_tnone)
        or      a
        sbc     hl,de                   ; the calls' ticks over N calls
        push    hl
        ld      de,1667                 ; hundredths of a ms per tick
        ld      bc,(t_n)
        call    k_muldiv                ; hl = hundredths of a ms per call
        call    k_hundredths
        ld      hl,t_ssector
        k_call  API_CON_PUTS
        pop     hl
        ld      de,1667
        ld      bc,N_SECTORS
        call    k_muldiv                ; per sector
        call    k_hundredths
        ld      hl,t_srtc
        k_call  API_CON_PUTS
        ld      a,(t_rtcs_n)
        dec     a
        jp      m,.nortc
        jr      z,.nortc
        ld      (t_rtcs_n),a
        call    k_dec8
        ld      hl,t_sticks
        k_call  API_CON_PUTS
        ld      hl,(t_rtcs_last)
        ld      de,(t_rtcs_first)
        or      a
        sbc     hl,de
        push    hl
        k_call  API_CON_DEC16
        ld      hl,t_sexp
        k_call  API_CON_PUTS
        ld      a,(t_rtcs_n)
        ld      d,0
        ld      e,a
        ld      hl,0
        ld      b,60
.x60:   add     hl,de
        djnz    .x60                    ; hl = 60 n
        push    hl
        k_call  API_CON_DEC16
        ld      hl,t_slost
        k_call  API_CON_PUTS
        pop     de                      ; expected
        pop     hl                      ; counted
        ex      de,hl
        or      a
        sbc     hl,de                   ; expected - counted = lost
        jp      p,.lost
        ld      hl,0                    ; more than expected: none lost
.lost:  k_call  API_CON_DEC16
        jr      .nl
.nortc: ld      hl,t_snortc
        k_call  API_CON_PUTS
.nl:    k_call  API_CON_NEWLINE
        ld      a,(t_b)
        add     a,a
        ld      (t_b),a
        cp      9
        jp      c,.b
        ld      hl,t_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
t_halt: ei
        halt
        jr      t_halt

; t_loop — N = 600 / B iterations of (t_fn), the RTC's seconds digit
; watched, k_ticks at the first and last change noted. HL = ticks elapsed.
t_loop:
        ld      a,13                    ; RTC mode register: block 0
        out     (0B4h),a
        ld      a,08h
        out     (0B5h),a
        call    t_rtc_sec
        ld      (t_rtc_prev),a
        xor     a
        ld      (t_rtc_n),a
        ld      hl,N_SECTORS
        ld      a,(t_b)
.div:   srl     a
        jr      c,.n
        srl     h
        rr      l
        jr      .div
.n:     ld      (t_n),hl
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      hl,(t_n)
.loop:  ld      (t_i),hl
        call    t_rtc_watch
        ld      hl,(t_fn)
        call    k_call_hl
        jp      nz,t_fail
        call    t_check                 ; in both loops, so it cancels
        jp      nz,t_fail
        ld      hl,(t_i)
        dec     hl
        ld      a,h
        or      l
        jr      nz,.loop
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        ret

; t_rw — B sectors from the volume's first sector into BUF_XFER, through
; the driver directly. Z if ok; NZ with A = the driver's code.
t_rw:   ld      hl,K_REC+KR_FIRST
        ld      de,t_secnum
        ld      bc,4
        ldir
        ld      ix,K_REC+KR_DRV
        ld      a,(t_b)
        ld      b,a
        ld      hl,BUF_XFER
        ld      de,t_secnum
        or      a                       ; read
        k_call  API_NX_RW
        or      a
        ret

; t_check — the B sectors in BUF_XFER against the B reference sectors,
; each against the one that belongs at its place. Z if every one is the
; same; NZ with A = 0F0h otherwise.
t_check:
        ld      a,(t_b)
        ld      b,a
        ld      hl,BUF_XFER
        ld      de,BUF_REF
.sec:   push    bc
        push    hl
        push    de
        call    k_cmp512
        pop     de
        pop     hl
        pop     bc
        ld      a,0F0h
        ret     nz
        inc     h
        inc     h                       ; + 512
        inc     d
        inc     d
        djnz    .sec
        xor     a
        ret

; t_none — the loop without the call.
t_none: xor     a
        ret

t_rtc_sec:
        xor     a
        out     (0B4h),a
        in      a,(0B5h)
        and     0Fh
        ret

t_rtc_watch:
        call    t_rtc_sec
        ld      b,a
        ld      a,(t_rtc_prev)
        cp      b
        ret     z
        inc     a
        cp      10
        jr      nz,.next
        xor     a
.next:  cp      b
        ret     nz
        ld      (t_rtc_prev),a
        ld      hl,(K_TICKS)
        ld      (t_rtc_last),hl
        ld      a,(t_rtc_n)
        or      a
        jr      nz,.count
        ld      (t_rtc_first),hl
.count: inc     a
        ld      (t_rtc_n),a
        ret

t_fail:
        push    af
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_b)
        call    k_dec8
        ld      hl,t_scode
        k_call  API_CON_PUTS
        pop     af
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
        jp      t_halt

        include "m6util.asm"

t_head:     db  "sectors per call: the call by difference, ticks against the rtc",10,0
t_sb:       db  "B=",0
t_scall:    db  "  call ",0
t_ssector:  db  " ms  per sector ",0
t_srtc:     db  " ms  rtc ",0
t_sticks:   db  " s  ticks ",0
t_sexp:     db  " expected ",0
t_slost:    db  " lost ",0
t_snortc:   db  "did not advance twice",0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL B=",0
t_scode:    db  " code ",0

t_b:        db  0
t_n:        dw  0
t_i:        dw  0
t_t0:       dw  0
t_tcall:    dw  0
t_tnone:    dw  0
t_fn:       dw  0
t_rtc_prev: db  0
t_rtc_n:    db  0
t_rtc_first: dw 0
t_rtc_last: dw  0
t_rtcs_n:   db  0               ; the call loop's watch, kept aside
t_rtcs_first: dw 0
t_rtcs_last: dw 0
t_secnum:   ds  4
        ENT
tblock_end:
        ASSERT $ < 4000h
