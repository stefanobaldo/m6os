; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; drvrom — the driver contract, exercised against the pattern block in the
; test ROM's driver bank (tests/drvrom/pattern.asm). This is a kernel-side
; block the ROM carries in bank 2 after the boot image and its boot copies
; to 0100h of page 0's segment, naming it in the record (KR_TEST): it runs
; as process 0 where it lies, with the resident's jump table and the
; syscalls, the switched image in page 1 and the storage segment in page
; 2, where the mailbox is. The report is on screen, the verdict in the
; mailbox. Steps: the record the ROM's boot wrote; init, info and status
; through the block layer; the volume the enumeration mounted; transfers
; of 1, 8 and 32 sectors compared with the pattern; the refusals the
; kernel makes before the driver, and an errno the driver is told to
; return; a write and its checksum; what the driver saw of the last call;
; the handler's invariant — a 32-sector transfer with a second process
; runnable and ticks landing inside it, nothing switched, nothing moved;
; and a program from the volume reading the pattern file while the
; harness presses ^C into its driver call: it dies at the call's return,
; of the signal, with no transfer left open and page 1 RAM again.
; Included by src/rom/rom.asm, which has nextor.inc and kernel.inc in
; already, inside a DISP for 0100h.
        include "m6test.inc"
        include "drvrom/layout.inc"

T_SIG           equ 8000h+ST_TESTS+0100h ; a signature byte in page 2
T_PARAMS        equ 8000h+ST_INFO       ; a query's parameters, in page 2

tb_start:                               ; SP is the kernel's, at K_END
; --- step 1: the record -----------------------------------------------
        ld      a,1
        call    t_begin
        ld      a,(K_REC+KR_NDRV)
        cp      1
        jp      nz,t_fail
        ld      a,(K_REC+KR_DRVS+KD_KIND)
        cp      KD_M6
        jp      nz,t_fail
        ld      a,(K_REC+KR_DRVS+KD_BANK)
        cp      7
        jp      nz,t_fail
        ld      hl,(K_REC+KR_WALL)
        ld      de,0F380h-64
        or      a
        sbc     hl,de
        jp      nz,t_fail
        call    t_ok

; --- step 2: init, info, status ----------------------------------------
        ld      a,2
        call    t_begin
        xor     a                       ; driver 0
        ld      d,BQ_INIT
        k_call  API_BLK_QUERY
        call    t_page2
        jp      c,t_fail
        cp      1
        jp      nz,t_fail
        xor     a
        ld      b,1
        ld      d,BQ_INFO
        ld      hl,T_PARAMS
        k_call  API_BLK_QUERY
        call    t_page2
        jp      c,t_fail
        ld      a,(T_PARAMS+DI_FLAGS)
        cp      DIF_RO
        jp      nz,t_fail
        ld      hl,(T_PARAMS+DI_COUNT)
        ld      de,PT_SECTORS
        or      a
        sbc     hl,de
        jp      nz,t_fail
        ld      hl,(T_PARAMS+DI_COUNT+2)
        ld      a,h
        or      l
        jp      nz,t_fail
        ld      hl,T_PARAMS+DI_IDENT
        ld      a,(hl)
        cp      7Fh
        jp      nz,t_fail
        inc     hl
        ld      a,(hl)
        dec     a
        jp      nz,t_fail
        inc     hl
        ld      a,(hl)
        dec     a
        jp      nz,t_fail
        ld      hl,T_PARAMS+DI_NAME
        ld      de,ts_name
        ld      b,19
.name:  ld      a,(de)
        cp      (hl)
        jp      nz,t_fail
        inc     hl
        inc     de
        djnz    .name
        xor     a
        ld      b,2                     ; no second device
        ld      d,BQ_INFO
        ld      hl,T_PARAMS
        k_call  API_BLK_QUERY
        call    t_page2
        jp      nc,t_fail
        cp      E_NXIO
        jp      nz,t_fail
        xor     a
        ld      b,1
        ld      d,BQ_STATUS
        k_call  API_BLK_QUERY
        call    t_page2
        jp      c,t_fail
        cp      DS_SAME
        jp      nz,t_fail
        call    t_ok

; --- step 3: the volume --------------------------------------------------
        ld      a,3
        call    t_begin
        ld      a,(K_BLK_NVOL)
        cp      1
        jp      nz,t_fail
        ld      a,(K_BLK_ROOT)
        or      a
        jp      nz,t_fail
        ld      ix,K_VOL
        ld      a,(ix+V_DRV)
        or      a
        jp      nz,t_fail
        ld      a,(ix+V_DEV)
        dec     a
        jp      nz,t_fail
        ld      a,(ix+V_COUNT)
        cp      PT_SECTORS
        jp      nz,t_fail
        ld      a,(ix+V_COUNT+1)
        or      (ix+V_FIRST)
        or      (ix+V_FIRST+1)
        jp      nz,t_fail
        call    t_ok

; --- step 4: transfers of 1, 8 and 32 sectors ----------------------------
        ld      a,4
        call    t_begin
        ld      b,MEM_KERNEL
        k_call  API_MEM_ALLOC
        jp      c,t_fail
        ld      (t_seg),a
        ld      a,1
        ld      hl,PT_K
        call    t_read
        jp      c,t_fail
        ld      a,8
        ld      hl,PT_K+1
        call    t_read
        jp      c,t_fail
        ld      a,32
        ld      hl,PT_K
        call    t_read
        jp      c,t_fail
        call    t_ok

; --- step 5: refused before the driver -----------------------------------
        ld      a,5
        call    t_begin
        call    t_calls
        ld      (t_ncalls),hl
        ld      a,(t_seg)
        ld      b,a
        ld      c,2                     ; slot 2 + 64 > 64
        ld      hl,0
        ld      de,0
        ld      a,31<<3                 ; volume 0, 32 sectors
        or      a
        k_call  API_BLK_RW
        call    t_page2
        jp      nc,t_fail
        cp      E_INVAL
        jp      nz,t_fail
        ld      a,(t_seg)
        ld      b,a
        ld      c,0
        ld      hl,PT_SECTORS-31        ; 33 + 32 > 64
        ld      de,0
        ld      a,31<<3
        or      a
        k_call  API_BLK_RW
        call    t_page2
        jp      nc,t_fail
        cp      E_IO
        jp      nz,t_fail
        call    t_calls
        ld      de,(t_ncalls)
        or      a
        sbc     hl,de
        jp      nz,t_fail               ; the driver saw neither
        call    t_ok

; --- step 6: an errno the driver returns ---------------------------------
        ld      a,6
        call    t_begin
        ld      a,E_NXIO
        ld      (T_PARAMS),a
        ld      a,42h
        ld      (T_PARAMS+1),a
        ld      e,80h
        call    t_query
        jp      c,t_fail
        ld      a,(t_seg)
        ld      b,a
        ld      c,0
        ld      hl,PT_K
        ld      de,0
        xor     a                       ; volume 0, one sector
        k_call  API_BLK_RW
        call    t_page2
        jp      nc,t_fail
        cp      E_NXIO
        jp      nz,t_fail
        ld      a,(K_BLK_LASTERR)
        cp      42h
        jp      nz,t_fail
        ld      a,1                     ; and the next call is whole again
        ld      hl,PT_K
        call    t_read
        jp      c,t_fail
        call    t_ok

; --- step 7: a write, its checksum, and the read-only volume --------------
        ld      a,7
        call    t_begin
        ld      a,(t_seg)
        out     (0FEh),a                ; the segment into page 2
        ld      hl,8000h
        ld      bc,512
        ld      de,0                    ; the sum
        ld      a,1
.fill:  ld      (hl),a
        add     a,e
        ld      e,a
        jr      nc,.nc
        inc     d
.nc:    ld      a,(hl)
        add     a,3
        inc     hl
        dec     bc
        push    af
        ld      a,b
        or      c
        jr      z,.filled
        pop     af
        jr      .fill
.filled:
        pop     af
        ld      (t_sum),de
        call    t_page2
        ld      a,1                     ; device 1, driver 0, one sector
        ld      ixh,0
        ld      ixl,1
        ld      hl,PT_SECTORS-1
        ld      de,0
        ld      bc,(t_seg)
        ld      b,c
        ld      c,0
        scf                             ; write
        k_call  API_BLK_DEV_RW
        call    t_page2
        jp      c,t_fail
        ld      e,86h
        call    t_query
        jp      c,t_fail
        ld      de,(t_sum)
        or      a
        sbc     hl,de
        jp      nz,t_fail
        ld      a,(t_seg)
        ld      b,a
        ld      c,0
        ld      hl,PT_K
        ld      de,0
        xor     a
        scf                             ; a write into the pattern
        k_call  API_BLK_RW
        call    t_page2
        jp      nc,t_fail
        cp      E_ROFS
        jp      nz,t_fail
        call    t_ok

; --- step 8: what the driver saw of the last transfer ---------------------
        ld      a,8
        call    t_begin
        ld      a,32
        ld      hl,PT_K
        call    t_read
        jp      c,t_fail
        ld      e,83h
        call    t_query
        jp      c,t_fail
        ld      a,(T_PARAMS)
        cp      32
        jp      nz,t_fail
        ld      a,(T_PARAMS+1)
        or      a
        jp      nz,t_fail
        ld      a,(T_PARAMS+2)
        ld      hl,t_seg
        cp      (hl)
        jp      nz,t_fail
        call    t_ok

; --- step 9: the invariant: ticks inside a transfer, nothing switched -----
        ld      a,9
        call    t_begin
        ld      hl,u_spin
        ld      bc,u_spin_end-u_spin
        ld      a,1
        k_call  API_SPAWN
        jp      c,t_fail
        ld      (t_spid),a
        ld      a,(K_NRUN)
        cp      2
        jp      c,t_fail
        ld      a,5Ah                   ; the signatures and the maps
        ld      (t_sig0),a
        ld      (T_SIG),a
        ld      hl,K_MAP
        ld      de,t_map
        ld      bc,3
        ldir
        ld      a,(K_KSEG)
        ld      (t_kseg),a
        ld      a,(K_PAGE1)
        ld      (t_page1),a
        ld      a,32
        ld      hl,PT_K
        call    t_read
        jp      c,t_fail
        ld      e,82h                   ; ticks inside it
        call    t_query
        jp      c,t_fail
        ld      (t_ticks),hl
        ld      a,h
        or      a
        jr      nz,.ticked
        ld      a,l
        cp      2
        jp      c,t_fail
.ticked:
        ld      a,(t_sig0)
        cp      5Ah
        jp      nz,t_fail
        ld      a,(T_SIG)
        cp      5Ah
        jp      nz,t_fail
        ld      hl,K_MAP
        ld      de,t_map
        ld      b,3
.map:   ld      a,(de)
        cp      (hl)
        jp      nz,t_fail
        inc     hl
        inc     de
        djnz    .map
        ld      a,(K_KSEG)
        ld      hl,t_kseg
        cp      (hl)
        jp      nz,t_fail
        ld      a,(K_PAGE1)
        ld      hl,t_page1
        cp      (hl)
        jp      nz,t_fail
        ld      a,(t_spid)
        ld      b,SIGTERM
        sys     SYS_KILL
        jp      c,t_fail
        ld      a,(t_spid)
        ld      b,0
        sys     SYS_WAITPID
        jp      c,t_fail
        ld      a,l
        cp      128+SIGTERM
        jp      nz,t_fail
        call    t_ok
        ld      hl,ts_ticks
        k_call  API_CON_PUTS
        ld      hl,(t_ticks)
        k_call  API_CON_DEC16
        ld      hl,ts_ticks2
        k_call  API_CON_PUTS

; --- step 10: a program reading the file, ^C into its driver call ---------
        ld      a,10
        call    t_begin
        ld      hl,ts_reader
        k_call  API_CON_PUTS            ; the harness presses ^C after this
        call    t_calls
        ld      (t_ncalls),hl
        ld      a,2                     ; every transfer spins two ticks
        ld      (T_PARAMS),a
        ld      e,85h
        call    t_query
        jp      c,t_fail
        ld      hl,p_reader
        ld      de,0
        ld      bc,t_fds
        xor     a
        sys     SYS_SPAWNV
        jp      c,t_fail
        ld      (t_spid),a
        ld      a,(t_spid)
        ld      b,0
        sys     SYS_WAITPID
        jp      c,t_fail
        ld      a,l
        cp      128+SIGINT
        jp      nz,t_fail_status
        ld      a,(K_BLK_LASTERR)
        or      a
        jp      nz,t_fail
        ld      a,(4000h+K_INTRPT)      ; page 1 is process 0's again: the
                                        ; switched image's segment, whose
                                        ; 0038h holds jp K_ISR
        cp      0C3h
        ld      a,0E2h
        jp      nz,t_fail
        ld      hl,(4000h+K_INTRPT+1)
        ld      de,K_ISR
        or      a
        sbc     hl,de
        ld      a,0E2h
        jp      nz,t_fail
        ld      e,87h                   ; no transfer left open
        call    t_query
        jp      c,t_fail
        ld      a,l
        or      a
        ld      a,0E3h
        jp      nz,t_fail
        xor     a                       ; spin no more
        ld      (T_PARAMS),a
        ld      e,85h
        call    t_query
        jp      c,t_fail
        call    t_calls
        ld      de,(t_ncalls)
        or      a
        sbc     hl,de
        jp      z,t_fail                ; it did read
        call    t_ok
        k_call  API_CON_NEWLINE
        ld      hl,ts_pass
        k_call  API_CON_PUTS
        m6_verdict M6_PASS
t_halt: ei
        halt
        jr      t_halt

; t_read — A = sectors 1-32, HL = the first: through blk_rw into the
; test's segment from slot 0, every byte compared with the pattern. CF
; when the call failed or a byte differs. Corrupts everything.
t_read:
        ld      (t_rn),a
        ld      (t_rsec),hl
        dec     a
        add     a,a
        add     a,a
        add     a,a                     ; (count - 1) << 3, volume 0
        ld      de,0
        ld      bc,(t_seg)
        ld      b,c
        ld      c,0
        or      a                       ; read
        k_call  API_BLK_RW
        call    t_page2
        ret     c
        ld      a,(t_seg)
        out     (0FEh),a                ; the segment into page 2
        ld      hl,8000h
        ld      a,(t_rsec)
        ld      c,a                     ; c = the sector
.sector:
        ld      a,c
        ld      d,a
        add     a,a
        add     a,a
        add     a,a
        sub     d                       ; 7 n
        ld      d,a
        ld      e,0
.lo:    ld      a,d
        add     a,e
        cp      (hl)
        jr      nz,.bad
        inc     hl
        inc     e
        jr      nz,.lo
.hi:    ld      a,d
        add     a,e
        xor     55h
        cp      (hl)
        jr      nz,.bad
        inc     hl
        inc     e
        jr      nz,.hi
        inc     c
        ld      a,(t_rn)
        dec     a
        ld      (t_rn),a
        jr      nz,.sector
        call    t_page2
        or      a
        ret
.bad:   call    t_page2
        ld      a,0E1h                  ; the code: a byte differs
        scf
        ret

; t_query — E = the number: the pattern block's query, its parameters at
; T_PARAMS. HL = its answer; CF as it says. Corrupts everything.
t_query:
        xor     a
        ld      b,1
        ld      d,BQ_QUERY
        ld      hl,T_PARAMS
        k_call  API_BLK_QUERY
        jp      t_page2

; t_calls — HL = the block's transfer count. Corrupts everything.
t_calls:
        ld      e,81h
        jr      t_query

; t_page2 — the test's page 2 back: the block layer leaves the window
; there. Preserves AF, HL.
t_page2:
        push    af
        ld      a,(K_MAP+2)
        out     (0FEh),a
        pop     af
        ret

; t_begin — A = the step: recorded, its number printed.
t_begin:
        ld      (t_step),a
        k_call  API_CON_NEWLINE
        ld      a,(t_step)
        call    k_dec8
        ld      a,' '
        k_call  API_CON_PUTC
        ret
t_ok:   ld      hl,ts_ok
        k_call  API_CON_PUTS
        ret

; t_fail — A = a code; t_fail_status — A = a status: the line, the verdict.
t_fail_status:
        ld      hl,ts_status
        k_call  API_CON_PUTS
        ld      a,(t_spid)
        jr      t_fail1
t_fail:
        push    af
        ld      hl,ts_fail
        k_call  API_CON_PUTS
        pop     af
t_fail1:
        push    af
        ld      a,(t_step)
        call    k_dec8
        ld      hl,ts_code
        k_call  API_CON_PUTS
        pop     af
        k_call  API_CON_HEX8
        k_call  API_CON_NEWLINE
        m6_verdict M6_FAIL
        jp      t_halt

        include "m6util.asm"

; u_spin — a one-page process that runs forever: what makes K_NRUN 2.
u_spin:                                 ; relative jumps only: no DISP
        jr      .start
        db      "m6",1,0
.start: jr      .start
u_spin_end:

ts_name:     db  "pattern test device"
ts_ok:       db  "ok",0
ts_ticks:    db  ", ",0
ts_ticks2:   db  " ticks inside",0
ts_reader:   db  "reader",10,0
ts_fail:     db  10,"FAIL step ",0
ts_status:   db  10,"FAIL status step ",0
ts_code:     db  " code ",0
ts_pass:     db  "PASS",10,0
p_reader:   db  "/READER",0
t_fds:      db  0FFh,0FFh,0FFh
t_step:     db  0
t_seg:      db  0
t_rn:       db  0
t_rsec:     dw  0
t_ncalls:   dw  0
t_sum:      dw  0
t_spid:     db  0
t_sig0:     db  0
t_map:      ds  3
t_kseg:     db  0
t_page1:    db  0
t_ticks:    dw  0
tb_end:
