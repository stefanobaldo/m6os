; mapper — the kernel detects the machine's memory mappers and allocates
; segments of the one it runs in. Under Nextor: check the kernel, capture
; what the resident needs, read a cap from the command line (mem=<K>),
; hand the machine over. Then, in a block the loader put above the image:
; check the count against Nextor's, allocate every free segment and prove
; each one distinct, exercise the refusals, check the cap, measure a 16K
; page copy. The report is on screen, the verdict in the mailbox.
        include "m6test.inc"
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "build/kernel.exp"

_STROUT     equ 09h
_TERM       equ 62h
CALSLT      equ B_CALSLT
CMDLINE     equ 0080h           ; DOS: length byte, the string, a NUL

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
        call    newline

; --- step 3: the cap, from the command line ----------------------------
        ld      a,3
        ld      (step),a
        ld      de,s_cap
        call    puts
        call    parse_mem
        jr      nc,.parsed
        push    af
        ld      de,s_below
        cp      0F9h
        jr      z,.say
        ld      de,s_notnum
        cp      0FAh
        jr      z,.say
        ld      de,s_notmult
.say:   call    puts
        pop     af
        jp      fail
.parsed:
        ld      a,(REC+KR_MEMCAP)
        or      a
        jr      nz,.capped
        ld      de,s_nocap
        call    puts
        jr      .takeover
.capped:
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        call    putdec16
        ld      de,s_capk
        call    puts
        ld      a,(REC+KR_MEMCAP)
        call    putdec
        ld      de,s_capsegs
        call    puts
.takeover:

; --- step 4: the takeover -----------------------------------------------
        ld      a,4
        ld      (step),a
        ld      de,s_takeover
        call    puts
        ld      hl,t_entry
        ld      (REC+KR_TEST),hl
        call    ld_takeover
        jp      fail                    ; it returns only with A = F3h

; parse_mem — look for mem=<K> on the command line. Out: CF clear and
; REC+KR_MEMCAP set (0 when absent, or when K is 4096 or more: no cap);
; CF set and A = 0F9h if K is below 128, 0FAh if K is not a number, 0FBh
; if K is not a multiple of 16.
parse_mem:
        xor     a
        ld      (REC+KR_MEMCAP),a
        ld      hl,CMDLINE
        ld      b,(hl)                  ; length
        inc     hl
.scan:  ld      a,b
        cp      4
        jr      c,.absent               ; "mem=" no longer fits
        ld      a,(hl)
        and     0DFh                    ; upper case
        cp      'M'
        jr      nz,.next
        inc     hl
        ld      a,(hl)
        and     0DFh
        cp      'E'
        dec     hl
        jr      nz,.next
        inc     hl
        inc     hl
        ld      a,(hl)
        and     0DFh
        cp      'M'
        dec     hl
        dec     hl
        jr      nz,.next
        inc     hl
        inc     hl
        inc     hl
        ld      a,(hl)
        cp      '='
        jr      z,.number
        dec     hl
        dec     hl
        dec     hl
.next:  inc     hl
        dec     b
        jr      .scan
.absent:
        or      a                       ; CF clear: no cap
        ret
.number:
        inc     hl                      ; hl -> the digits
        ld      de,0                    ; de = K
        ld      c,0                     ; c = digits seen
.digit: ld      a,(hl)
        sub     '0'
        jr      c,.end
        cp      10
        jr      nc,.end
        inc     c
        inc     hl
        push    hl
        ld      hl,6553
        or      a
        sbc     hl,de                   ; de > 6553 would overflow times 10
        pop     hl
        jr      c,.overflow
        push    hl
        ld      h,d
        ld      l,e
        add     hl,hl                   ; 2 K
        add     hl,hl                   ; 4 K
        add     hl,de                   ; 5 K
        add     hl,hl                   ; 10 K
        ld      e,a
        ld      d,0
        add     hl,de                   ; + the digit
        ex      de,hl
        pop     hl
        jr      .digit
.overflow:
        ld      c,0                     ; treated as not a number
.end:   ld      a,c
        or      a
        ld      a,0FAh                  ; not a number
        scf
        ret     z
        ld      a,e
        and     0Fh
        ld      a,0FBh                  ; not a multiple of 16
        scf
        ret     nz
        ld      hl,128
        ex      de,hl
        or      a
        sbc     hl,de                   ; K - 128
        ld      a,0F9h                  ; below the floor
        ret     c
        add     hl,de                   ; hl = K
        ld      de,4096
        or      a
        sbc     hl,de
        jr      nc,.nocap               ; 4096 and above: no cap
        add     hl,de
        srl     h                       ; K / 16 = segments (K < 4096: fits)
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        ld      a,l
        ld      (REC+KR_MEMCAP),a
.nocap: or      a
        ret

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

banner:     db  "mapper: m6 detects and allocates the mapper",13,10,'$'
s_version:  db  "1 kernel: Nextor $"
s_notnextor: db "MSX-DOS 2, not Nextor: not supported",13,10,'$'
s_nextor3:  db  "Nextor 3 kernel: not supported",13,10,'$'
s_capture:  db  "2 wall $"
s_resident: db  "h resident $"
s_room:     db  " room $"
s_cap:      db  "3 mem= $"
s_below:    db  "below the 128K floor",13,10,'$'
s_notnum:   db  "not a number",13,10,'$'
s_notmult:  db  "not a multiple of 16",13,10,'$'
s_nocap:    db  "no cap",13,10,'$'
s_capk:     db  " K, $"
s_capsegs:  db  " segments",13,10,'$'
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

; The second half, assembled for K_IMAGE_END (build/kernel.exp), where the
; loader copies it. Pages 1 and 2 are free windows here; the test's own
; data lives in this block, in page 3, so switching page 2 never hides it.
tblock:
        DISP    K_IMAGE_END
t_entry:
; --- step 5: the count, against what Nextor saw ------------------------
        ld      a,5
        ld      (t_step),a
        ld      hl,t_k5
        k_call  API_CON_PUTS
        k_call  API_MEM_INFO
        ld      (t_free0),bc            ; free segments at the start
        ld      (t_usable),de
        ld      b,(hl)                  ; mappers
        inc     hl
.prim:  ld      a,b
        or      a
        ld      a,0E1h
        jp      z,t_fail                ; no primary in the table
        ld      a,(hl)                  ; slot
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        ld      a,(hl)
        inc     hl
        and     MMF_PRIMARY
        jr      nz,.found
        dec     b
        jr      .prim
.found: ld      (t_total),de
        ex      de,hl
        k_call  API_CON_DEC16
        ld      hl,t_k5b
        k_call  API_CON_PUTS
        ld      a,(K_REC+KR_MAPTOTAL)
        call    k_dec8
        ld      hl,t_colon
        k_call  API_CON_PUTS
        ld      hl,(t_total)
        ld      a,(K_REC+KR_MAPTOTAL)
        ld      e,a
        ld      d,0
        or      a
        sbc     hl,de
        jr      z,.same
        ld      de,1
        or      a
        sbc     hl,de                   ; total - nextor = 1?
        ld      a,0E1h
        jp      nz,t_fail
        ld      a,(K_REC+KR_MAPTOTAL)
        cp      255                     ; 256 against 255
        ld      a,0E1h
        jp      nz,t_fail
        ld      hl,t_expected
        k_call  API_CON_PUTS
        jr      .k6
.same:  ld      hl,t_ok
        k_call  API_CON_PUTS
.k6:

; --- step 6: every free segment allocated, written at both ends, read back
        ld      a,6
        ld      (t_step),a
        ld      hl,t_k6
        k_call  API_CON_PUTS
        xor     a
        ld      (t_highest),a
        ld      hl,0
        ld      (t_count),hl
        ld      hl,t_segs
.alloc: ld      b,1                     ; owner 1: the test
        k_call  API_MEM_ALLOC
        jr      c,.allocated
        ld      (hl),a
        inc     hl
        push    hl
        ld      hl,(t_count)
        inc     hl
        ld      (t_count),hl
        ld      hl,t_highest
        cp      (hl)
        jr      c,.nothigh
        ld      (hl),a
.nothigh:
        pop     hl
        jr      .alloc
.allocated:
        ; Write each segment's number at its first and last byte.
        ld      hl,t_segs
        ld      bc,(t_count)
.write: ld      a,b
        or      c
        jr      z,.written
        ld      a,(hl)
        out     (0FEh),a
        ld      (8000h),a
        ld      (0BFFFh),a
        inc     hl
        dec     bc
        jr      .write
.written:
        ; Read them all back.
        ld      hl,t_segs
        ld      bc,(t_count)
.read:  ld      a,b
        or      c
        jr      z,.readok
        ld      a,(hl)
        out     (0FEh),a
        ld      e,a
        ld      a,(8000h)
        cp      e
        jr      nz,.bad
        ld      a,(0BFFFh)
        cp      e
        jr      nz,.bad
        inc     hl
        dec     bc
        jr      .read
.bad:   ld      a,(8000h)
        ld      b,a
        ld      a,(0BFFFh)
        ld      c,a
        ld      a,(K_REC+KR_SEG64K+2)
        out     (0FEh),a
        ld      a,e
        call    t_fail_seg
.readok:
        ld      a,(K_REC+KR_SEG64K+2)
        out     (0FEh),a                ; page 2 is the test's again
        ld      hl,(t_count)
        k_call  API_CON_DEC16
        ld      hl,t_k6b
        k_call  API_CON_PUTS

; --- step 7: the refusals ------------------------------------------------
        ld      a,7
        ld      (t_step),a
        ld      hl,t_k7
        k_call  API_CON_PUTS
        ld      b,1
        k_call  API_MEM_ALLOC
        ld      a,0E3h
        jp      nc,t_fail               ; exhausted, yet it gave one
        ld      hl,t_ok2
        k_call  API_CON_PUTS
        ld      hl,t_k7b
        k_call  API_CON_PUTS
        ld      a,(K_REC+KR_SEG64K+3)   ; the kernel's own page
        ld      b,1
        k_call  API_MEM_FREE
        ld      a,0E3h
        jp      nc,t_fail
        ld      hl,t_ok2
        k_call  API_CON_PUTS
        ld      hl,t_k7c
        k_call  API_CON_PUTS
        ld      a,(t_segs)              ; the test's first, as owner 2
        ld      b,2
        k_call  API_MEM_FREE
        ld      a,0E3h
        jp      nc,t_fail
        ld      hl,t_ok2
        k_call  API_CON_PUTS
        ld      hl,t_k7d
        k_call  API_CON_PUTS
        ld      b,1
        k_call  API_MEM_FREE_ALL
        k_call  API_MEM_INFO
        ld      hl,(t_free0)
        or      a
        sbc     hl,bc
        ld      a,0E3h
        jp      nz,t_fail               ; not back to the start
        ; The count coming back is not enough: the stack must hold the same
        ; segments it was given. Allocate them all again — no segment twice,
        ; as many as before, and every one of them one that was handed out.
        ld      hl,t_seen
        ld      (hl),0
        ld      de,t_seen+1
        ld      bc,255
        ldir
        ld      hl,0
        ld      (t_count2),hl
.again: ld      b,1
        k_call  API_MEM_ALLOC
        jr      c,.reallocated
        ld      e,a
        ld      d,0
        ld      hl,t_seen
        add     hl,de
        ld      a,(hl)
        or      a
        ld      a,0E5h
        jp      nz,t_fail               ; the same segment handed out twice
        ld      (hl),1
        ld      hl,(t_count2)
        inc     hl
        ld      (t_count2),hl
        jr      .again
.reallocated:
        ld      hl,(t_count2)
        ld      de,(t_count)
        or      a
        sbc     hl,de
        ld      a,0E5h
        jp      nz,t_fail               ; fewer, or more, than went in
        ld      hl,t_segs
        ld      bc,(t_count)
.wasgiven:
        ld      a,b
        or      c
        jr      z,.allback
        ld      a,(hl)
        push    hl
        ld      e,a
        ld      d,0
        ld      hl,t_seen
        add     hl,de
        ld      a,(hl)
        pop     hl
        or      a
        ld      a,0E5h
        jp      z,t_fail                ; one that went in never came back
        inc     hl
        dec     bc
        jr      .wasgiven
.allback:
        ld      b,1
        k_call  API_MEM_FREE_ALL        ; leave it as this step found it
        ld      hl,t_ok
        k_call  API_CON_PUTS

; --- step 8: the cap ------------------------------------------------------
        ld      a,8
        ld      (t_step),a
        ld      hl,t_k8
        k_call  API_CON_PUTS
        ld      a,(K_REC+KR_MEMCAP)
        or      a
        jr      nz,.cap
        ld      hl,t_nocap
        k_call  API_CON_PUTS
        jr      .k9
.cap:   ld      hl,t_k8b
        k_call  API_CON_PUTS
        ld      hl,(t_usable)
        k_call  API_CON_DEC16
        ld      hl,t_k8c
        k_call  API_CON_PUTS
        ld      a,(t_highest)
        call    k_dec8
        ld      hl,t_colon
        k_call  API_CON_PUTS
        ; usable must be the cap, or the count when the cap exceeds it.
        ld      a,(K_REC+KR_MEMCAP)
        ld      e,a
        ld      d,0
        ld      hl,(t_total)
        or      a
        sbc     hl,de                   ; total - cap
        jr      nc,.capfits
        ld      de,(t_total)            ; the cap exceeds the count
.capfits:
        ld      hl,(t_usable)
        or      a
        sbc     hl,de
        ld      a,0E4h
        jp      nz,t_fail               ; usable is neither
        ld      a,(t_highest)
        cp      e
        ld      a,0E4h
        jp      nc,t_fail               ; a segment at or above the limit
        ld      hl,t_ok
        k_call  API_CON_PUTS
.k9:

; --- step 9: a 16K page copy, measured ------------------------------------
        ld      a,9
        ld      (t_step),a
        ld      hl,t_k9
        k_call  API_CON_PUTS
        ld      b,1
        k_call  API_MEM_ALLOC
        ld      (t_src),a
        ld      b,1
        k_call  API_MEM_ALLOC
        ld      (t_dst),a
        ld      a,(t_src)
        out     (0FDh),a                ; page 1: the source
        ld      a,(t_dst)
        out     (0FEh),a                ; page 2: the destination
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      b,64
.ldir:  push    bc
        ld      hl,4000h
        ld      de,8000h
        ld      bc,4000h
        ldir
        pop     bc
        djnz    .ldir
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        call    t_percopy
        ld      hl,t_k9b
        k_call  API_CON_PUTS
        ld      hl,(K_TICKS)
        ld      (t_t0),hl
        ld      b,64
.ldi:   push    bc
        exx
        ld      bc,1024                 ; groups of 16 bytes, in BC'
        exx
        ld      hl,4000h
        ld      de,8000h
        ld      bc,4000h
.ldi16: ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ; ldi decrements bc with every byte; the groups are counted in
        ; BC', which the copy does not touch.
        exx
        dec     bc
        ld      a,b
        or      c
        exx
        jr      nz,.ldi16
        pop     bc
        djnz    .ldi
        ld      hl,(K_TICKS)
        ld      de,(t_t0)
        or      a
        sbc     hl,de
        call    t_percopy
        ld      a,(K_REC+KR_SEG64K+1)
        out     (0FDh),a
        ld      a,(K_REC+KR_SEG64K+2)
        out     (0FEh),a
        ld      b,1
        k_call  API_MEM_FREE_ALL

; --- step 10: verdict ---------------------------------------------------
        ld      hl,t_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
        jp      t_halt

; t_percopy — HL = ticks for 64 copies: print "T ticks/64 = N.NN ms".
t_percopy:
        push    hl
        k_call  API_CON_DEC16
        ld      hl,t_per
        k_call  API_CON_PUTS
        pop     hl
        ld      de,1667                 ; hundredths of a millisecond per tick
        ld      bc,64
        call    k_muldiv
        call    k_hundredths
        ld      hl,t_ms
        k_call  API_CON_PUTS
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

; t_fail_seg — A = segment, B = byte at 8000h, C = byte at BFFFh: code E2.
t_fail_seg:
        push    bc
        push    af
        k_call  API_CON_NEWLINE
        ld      hl,t_sfail
        k_call  API_CON_PUTS
        ld      a,(t_step)
        call    k_dec8
        ld      hl,t_segment
        k_call  API_CON_PUTS
        pop     af
        call    k_dec8
        ld      hl,t_reads
        k_call  API_CON_PUTS
        pop     bc
        push    bc
        ld      a,b
        k_call  API_CON_HEX8
        ld      a,' '
        k_call  API_CON_PUTC
        pop     bc
        ld      a,c
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
        jr      t_halt

t_halt:
        ei
        halt
        jr      t_halt

        include "m6util.asm"

t_k5:       db  "5 m6 ",0
t_k5b:      db  ", Nextor ",0
t_colon:    db  ": ",0
t_expected: db  "expected",10,0
t_ok:       db  "ok",10,0
t_ok2:      db  "ok  ",0
t_k6:       db  "6 ",0
t_k6b:      db  " allocated, all distinct",10,0
t_k7:       db  "7 exhausted: ",0
t_k7b:      db  "kernel segment: ",0
t_k7c:      db  "wrong owner: ",0
t_k7d:      db  "free_all: ",0
t_k8:       db  "8 ",0
t_nocap:    db  "no cap",10,0
t_k8b:      db  "cap ",0
t_k8c:      db  ": highest seen ",0
t_k9:       db  "9 ldir 16K: ",0
t_k9b:      db  "  ldi x16 16K: ",0
t_per:      db  " ticks/64 = ",0
t_ms:       db  " ms at 60 Hz",10,0
t_pass:     db  "PASS",10,0
t_sfail:    db  "FAIL step ",0
t_code:     db  " code ",0
t_segment:  db  " code E2 segment ",0
t_reads:    db  " reads ",0

t_step:     db  0
t_free0:    dw  0
t_usable:   dw  0
t_total:    dw  0
t_count:    dw  0
t_highest:  db  0
t_src:      db  0
t_dst:      db  0
t_t0:       dw  0
t_count2:   dw  0
t_segs:     ds  256
t_seen:     ds  256
        ENT
tblock_end:

        ASSERT $ < 4000h
