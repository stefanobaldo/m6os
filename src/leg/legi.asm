; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The legacy layer's entry: what runs once, when dosenter crosses into
; the layer, before the program is entered — the DOS page 0, the copy of
; the BIOS area patched, the program read into its pages, the mapper
; variables, the drives and the current directory (legf_init), the two
; FCBs from the tail. Included by leg.asm at the end of the body's image,
; where its bytes are an overlay: once it has run, the record and the
; environment store (leg_rec, leg_env) lie over it. Nothing here may be
; written into before the entry is over — the record alone, which
; legf_init fills last of all, lies over leg_entry, which has run by
; then.

; leg_entry — the first crossing, from dosenter through the second stub
; and leg_ret (leg.asm), which has marked the layer started, taken the
; stack under the BDOS entry and mapped the body: interrupts disabled,
; the legacy page 3 in, the launcher's page 0 still in page 0 with the
; tail at 0080h. The DOS page 0 (DOS2-PIS §2.3) written around
; the kernel's subslot stub at 0040h; EXTBIO and HOKVLD in this copy of
; the BIOS area; the mapper variable table filled through the kernel; the
; program read from its file into the three pages through the kernel —
; over the launcher, which is gone from here; the two FCBs from the tail;
; the stack where MSX-DOS puts it with 0000h under it so that a ret ends
; the program; and into the program with interrupts enabled.
leg_entry:
        ; The DOS page 0: 0000h-003Fh and 0051h-007Fh cleared, the stub at
        ; 0040h and the tail at 0080h kept, then the entries.
        ld      hl,0
        ld      (hl),0
        ld      de,1
        ld      bc,K_INTRPT+3-1
        ldir
        ld      hl,K_SSLOT+K_SSLOT_LEN
        ld      (hl),0
        ld      de,K_SSLOT+K_SSLOT_LEN+1
        ld      bc,0080h-(K_SSLOT+K_SSLOT_LEN)-1
        ldir
        ld      a,0C3h
        ld      (0000h),a               ; jp WBOOT
        ld      hl,LEG_BIOS+3
        ld      (0001h),hl
        ld      a,(leg_drive)
        ld      (0004h),a
        ld      a,0C3h
        ld      (0005h),a               ; jp the BDOS
        ld      hl,LEG_BDOS
        ld      (0006h),hl
        ld      a,0C3h
        ld      (000Ch),a
        ld      hl,leg_rdslt
        ld      (000Dh),hl
        ld      a,0C3h
        ld      (0014h),a
        ld      hl,leg_wrslt
        ld      (0015h),hl
        ld      a,0C3h
        ld      (001Ch),a
        ld      hl,leg_calslt
        ld      (001Dh),hl
        ld      a,0C3h
        ld      (0024h),a
        ld      hl,leg_enaslt
        ld      (0025h),hl
        ld      a,0C3h
        ld      (0030h),a
        ld      hl,leg_callf
        ld      (0031h),hl
        ld      a,0FFh
        ld      (0037h),a               ; COMMAND2's mark, set before it
                                        ; enters a program: PARAMETERS and
                                        ; PROGRAM are there to be read
        ld      a,0C3h
        ld      (K_INTRPT),a            ; jp the trampoline: the second stub
        ld      hl,leg_isr              ; has set the operand already
        ld      (K_INTRPT+1),hl
        ; The keyboard matrix as it is now into OLDKEY and NEWKEY of this
        ; copy, so that the BIOS's scanner sees no key already held as a
        ; new press — the RET that launched the program is still down.
        ld      hl,B_OLDKEY
        ld      de,B_NEWKEY
        ld      b,11
        ld      c,0
.row:   in      a,(PPI_C)
        and     0F0h
        or      c
        out     (PPI_C),a
        in      a,(PPI_B)
        ld      (hl),a
        ld      (de),a
        inc     hl
        inc     de
        inc     c
        djnz    .row
        ; EXTBIO and HOKVLD, in this copy of the BIOS area.
        ld      a,0C3h
        ld      (B_FCALL),a
        ld      hl,leg_extbio
        ld      (B_FCALL+1),hl
        ld      hl,0
        ld      (B_FCALL+3),hl
        ld      hl,B_HOKVLD
        set     0,(hl)
        ; The program, into its pages through the kernel, page piece by
        ; page piece — read takes a buffer in one page. The launcher's
        ; page 0 is overwritten from P0_PROG, and never returned to.
        ; leg_inb is 1 here: the kernel is told the program's page 2, not
        ; the body's, because that is where the third piece goes.
        ld      hl,(leg_size)
        ld      (leg_left),hl
        ld      hl,P0_PROG
        ld      (leg_addr),hl
.load:  ld      hl,(leg_left)
        ld      a,h
        or      l
        jr      z,.loaded
        ld      hl,(leg_addr)
        ld      a,h
        and     3Fh
        ld      d,a
        ld      e,l                     ; de = the offset in its page
        ld      hl,4000h
        or      a
        sbc     hl,de                   ; hl = the room to the page's end
        ld      de,(leg_left)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jr      c,.room                 ; less room than is left: the room
        ex      de,hl                   ; else what is left
.room:  ld      b,h
        ld      c,l                     ; bc = the piece
        ld      hl,(leg_addr)
        ld      a,(leg_fd)
        leg_sys SYS_READ                ; hl = bytes read
        jr      c,.readfail
        ld      a,h
        or      l
        jr      z,.readfail             ; the end before the size
        ld      b,h
        ld      c,l
        ld      hl,(leg_addr)
        add     hl,bc
        ld      (leg_addr),hl
        ld      hl,(leg_left)
        or      a
        sbc     hl,bc
        ld      (leg_left),hl
        jr      .load
.readfail:
        ld      a,D_INTER
        jp      leg_term
.loaded:
        ld      a,3                     ; from here a crossing's buffers
        ld      (leg_inb),a             ; are the body's own
        ld      a,(leg_fd)
        leg_sys SYS_CLOSE
        ld      a,(B_RAMAD0+3)
        ld      (leg_mapvar+0),a        ; the primary mapper's slot
        ld      hl,SC_SEGMENTS
        leg_sys SYS_SYSCONF
        ld      a,h
        or      a
        jr      z,.total
        ld      l,255                   ; 256 segments: the byte says 255
.total: ld      a,l
        ld      (leg_mapvar+1),a
        call    ll_init                 ; A = 1: the parent's page to lend
        push    af
        ld      hl,SC_SEGMENTS_FREE
        leg_sys SYS_SYSCONF
        pop     af
        add     a,l                     ; counted free: an ALL_SEG gets it
        jr      nc,.free
        ld      a,255
.free:  ld      l,a
        ld      (leg_mapvar+2),a
        ld      a,(leg_mapvar+1)
        sub     l
        sub     4
        jr      nc,.sys
        xor     a
.sys:   ld      (leg_mapvar+3),a        ; the system's: the rest
        ld      a,4
        ld      (leg_mapvar+4),a        ; the user's: the TPA's four
        call    legf_init
        call    leg_fcbs
        jp      e_seed                  ; the environment store, over code
                                        ; that has run, and the tail

; legf_init — the drives and the current directory, from the kernel:
; every volume mounted is a drive; the shell's directory is the current
; drive's, or the drive's root when the shell was at /mnt.
legf_init:
        ld      hl,leg_hand
        ld      de,leg_hand+1
        ld      bc,LEG_NHAND*3-1
        ld      (hl),HD_FREE
        ldir
        ld      hl,leg_hand0
        ld      de,leg_hand
        ld      bc,5*3
        ldir
        xor     a
        ld      (leg_level),a
        ld      (leg_llen),a
        ld      (leg_xback),a
        ld      (leg_xwr),a
        ld      (leg_login),a
        ld      (leg_wpath),a
        ld      (leg_vfy),a
        ld      (leg_chk),a
        ld      (leg_defer),a
        ld      (leg_defer+1),a
        ld      hl,leg_wpath
        ld      (leg_wpos),hl
        ld      hl,0080h
        ld      (leg_dta),hl
        ld      hl,leg_dcwd
        ld      de,leg_dcwd+1
        ld      bc,15
        ld      (hl),0
        ldir
        ld      hl,leg_assign
        ld      b,8
        ld      a,1
.id:    ld      (hl),a
        inc     hl
        inc     a
        djnz    .id
        ; the login vector: a volume in every row statfs answers for
        ld      c,0
.vol:   ld      a,c
        ld      hl,leg_sf
        ld      b,0
        push    bc
        leg_sys SYS_STATFS
        pop     bc
        jr      c,.novol
        ld      b,c
        inc     b
        ld      a,1
.sh:    dec     b
        jr      z,.set
        add     a,a
        jr      .sh
.set:   ld      hl,leg_login
        or      (hl)
        ld      (hl),a
.novol: inc     c
        ld      a,c
        cp      8
        jr      c,.vol
        ; the current drive and its directory
        ld      a,(leg_drive)
        ld      (leg_curp),a
        ld      hl,s_dot
        ld      de,leg_rec
        leg_sys SYS_STATL
        jr      c,.root
        ld      a,(leg_rec+DE_NAME+DE_LOC+DL_VOL)
        ld      hl,leg_drive
        cp      (hl)
        jr      nz,.root
        ld      a,(hl)
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,leg_dcwd
        add     hl,de
        ld      de,(leg_rec+DE_NAME+DE_LOC+DL_CLUS)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ret
.root:  jp      leg_leave               ; the drive's root
leg_hand0:
        db      HD_CON,HF_NOWR|HF_INH|HF_ASCII,0
        db      HD_CON,HF_NORD|HF_INH|HF_ASCII,0
        db      HD_CON,HF_INH|HF_ASCII,0
        db      HD_NUL,HF_INH|HF_ASCII,0
        db      HD_NUL,HF_INH|HF_ASCII,0

; leg_fcbs — the two unopened FCBs at 005Ch and 006Ch from the first two
; words of the tail at 0080h: a drive letter and a colon, then up to
; eight characters, a dot, up to three; * fills the rest of its part
; with ?. Corrupts everything.
leg_fcbs:
        ld      hl,0081h
        ld      de,005Ch
        call    .one
        ld      de,006Ch
.one:   ld      a,(hl)
        or      a
        ret     z
        cp      ' '
        jr      nz,.word
        inc     hl
        jr      .one
.word:  xor     a
        ld      (de),a                  ; the drive: default
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      ':'
        jr      nz,.name
        ld      a,(hl)
        and     0DFh
        sub     'A'-1
        ld      (de),a
        inc     hl
        inc     hl
.name:  inc     de
        ld      b,8
        call    .part
        ld      a,(hl)
        cp      '.'
        jr      nz,.ext
        inc     hl
.ext:   ld      b,3
        call    .part
.skip:  ld      a,(hl)                  ; past the rest of the word
        or      a
        ret     z
        cp      ' '
        ret     z
        cp      '.'
        jr      z,.dot
        inc     hl
        jr      .skip
.dot:   inc     hl
        jr      .skip
.part:  ld      a,(hl)
        or      a
        jr      z,.pad
        cp      ' '
        jr      z,.pad
        cp      '.'
        jr      z,.pad
        cp      '*'
        jr      z,.star
        inc     hl
        cp      'a'
        jr      c,.store
        cp      'z'+1
        jr      nc,.store
        sub     20h
.store: ld      (de),a
        inc     de
        djnz    .part
        ; the part is full: skip what is left of it
.more:  ld      a,(hl)
        or      a
        ret     z
        cp      ' '
        ret     z
        cp      '.'
        ret     z
        inc     hl
        jr      .more
.star:  inc     hl
.starq: ld      a,'?'
        ld      (de),a
        inc     de
        djnz    .starq
        jr      .more
.pad:   ld      a,' '
        ld      (de),a
        inc     de
        djnz    .pad
        ret

; ll_init — the segment the program's parent could lend it (legl.asm):
; the parent's page 0, when the parent is a process of its own — not
; process 0, whose pages are the kernel's — alive, and shares no page
; with the program, as a vfork parent would. Whether it is blocked in
; wait is asked when the segment is taken: at the entry the shell may
; not have reached its waitpid yet. Out: A = 1 when there is one, 0
; otherwise; ll_st, ll_seg and ll_ppid set.
ll_init:
        xor     a
        ld      (ll_st),a               ; LL_NONE
        leg_sys SYS_GETPID
        ld      a,l
        ld      hl,leg_path2
        leg_sys SYS_PROCINFO
        jr      c,.none
        ld      a,(leg_path2+P_PPID)
        ld      (ll_ppid),a
        cp      PP_NONE
        jr      z,.none
        ld      hl,leg_path2
        leg_sys SYS_PROCINFO
        jr      c,.none
        ld      a,(leg_path2+P_NPAGES)
        or      a
        jr      z,.none                 ; process 0
        ld      a,(leg_path2+P_STATE)
        cp      PS_ZOMBIE
        jr      z,.none                 ; its segments are free already
        ld      a,(leg_path2+P_SEG)
        ld      hl,leg_segs
        ld      b,3
.own:   cp      (hl)
        jr      z,.none                 ; one of the program's pages
        inc     hl
        djnz    .own
        ld      (ll_seg),a
        ld      a,LL_HOME
        ld      (ll_st),a
        ld      a,1
        ret
.none:  xor     a
        ret
