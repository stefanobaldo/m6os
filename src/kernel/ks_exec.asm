; exec, in the switched part: the file found and checked, the argument
; block gathered, the segments chosen, the image loaded sector by sector
; — straight from the driver where a whole sector lands inside a page,
; through the cache and the copy where it crosses one or is the last —
; and the resident's exec_finish (proc.asm) called to build the frame and
; enter the new image. Every check that can fail runs before the first
; sector is written, so a refused exec returns to a caller whose image is
; intact; an I/O error while a reused image is being overwritten ends the
; process, because there is nothing left to return to.

; ks_exec — SYS_EXEC: HL = path, DE = argv (0 = an empty vector). Does not
; return on success. E_PERM from process 0; E_NOENT, E_NOTDIR, E_ISDIR;
; E_NOEXEC without the header, or when the image, the block and the frame
; do not fit the pages asked for; E_2BIG above ARGV_MAX bytes of block;
; E_NOMEM; E_IO.
ks_exec:
        ld      a,(K_PID)
        or      a
        jp      z,.perm
        ld      (SG+VX_ARGV),de
        call    vfs_getpath
        ret     c
        call    vfs_lookup
        ret     c
        ld      a,(SG+VR_ATTR)
        and     DA_DIR
        jp      nz,.isdir
        ; The size: below 64K, at least the header.
        ld      hl,(SG+VR_SIZE+2)
        ld      a,h
        or      l
        jp      nz,.noexec
        ld      hl,(SG+VR_SIZE)
        ld      (SG+VX_SIZE),hl
        ld      de,XH_SIZE
        or      a
        sbc     hl,de
        jp      c,.noexec
        ; The header, in the file's first sector.
        ld      hl,(SG+VR_CLUS)
        ld      a,(SG+VR_VOL)
        call    fat_sector
        ret     c
        ld      a,(SG+VR_VOL)
        k_call  API_BGET
        ret     c
        inc     hl
        inc     hl
        ld      a,(hl)                  ; XH_SIGN
        cp      'm'
        jp      nz,.noexec
        inc     hl
        ld      a,(hl)
        cp      '6'
        jp      nz,.noexec
        inc     hl
        ld      a,(hl)                  ; XH_PAGES
        or      a
        jp      z,.noexec
        cp      4
        jp      nc,.noexec
        ld      (SG+VX_PAGES),a
        inc     hl
        ld      a,(hl)                  ; XH_FLAGS
        or      a
        jp      nz,.noexec
        ; The argument block.
        call    ex_args
        ret     c
        ; P0_PROG + size + block + frame <= pages * 4000h.
        ld      a,(SG+VX_PAGES)
        rrca
        rrca                            ; pages * 40h
        ld      h,a
        ld      l,0
        ld      de,(SG+VX_BLEN)
        or      a
        sbc     hl,de
        ld      de,P0_FRAME+P0_PROG
        sbc     hl,de
        jp      c,.noexec
        ld      de,(SG+VX_SIZE)
        sbc     hl,de
        jp      c,.noexec
        ; The segments.
        call    ex_segs
        ret     c
        ; The image. From here a reused image is being destroyed.
        call    ex_load
        jr      c,.loadfail
        k_call  API_EXEC_FINISH         ; never returns
.loadfail:
        ld      c,a
        ld      a,(SG+VX_FRESH)
        or      a
        ld      a,c
        jr      nz,.freefresh
        call    K_SYS+3*SYS_EXIT        ; the errno as the status; no return
.freefresh:
        push    af
        call    ex_free_new
        pop     af
        ret
.perm:  ld      a,E_PERM
        scf
        ret
.isdir: ld      a,E_ISDIR
        scf
        ret
.noexec:
        ld      a,E_NOEXEC
        scf
        ret

; ex_args — the caller's vector (VX_ARGV; 0 = none) serialised into
; ST_ARGV: argc + 1 words — each string's offset into the block, then 0 —
; followed by the strings. VX_ARGC and VX_BLEN set. CF with E_2BIG past
; ARGV_MAX. Corrupts everything.
ex_args:
        xor     a
        ld      (SG+VX_ARGC),a
        ld      hl,(SG+VX_ARGV)
        ld      a,h
        or      l
        jr      z,.count                ; none: argc = 0
        ; Count the pointers.
.cnt:   ld      de,VV_T
        ld      bc,2
        push    hl
        call    um_in
        pop     hl
        ld      de,(SG+VV_T)
        ld      a,d
        or      e
        jr      z,.count
        ld      a,(SG+VX_ARGC)
        inc     a
        ld      (SG+VX_ARGC),a
        cp      ARGV_MAX/2              ; the table alone would overflow
        jp      nc,.big
        inc     hl
        inc     hl
        jr      .cnt
.count: ld      a,(SG+VX_ARGC)
        inc     a
        add     a,a                     ; (argc + 1) * 2: where the strings begin
        ld      l,a
        ld      h,0
        ld      (SG+VX_BP),hl
        ; Each string, its offset into its table slot.
        ld      hl,(SG+VX_ARGV)
        ld      (SG+VV_T+2),hl          ; the vector's cursor
        ld      hl,SG+ST_ARGV
        ld      (SG+VV_T+4),hl          ; the table's cursor
        ld      a,(SG+VX_ARGC)
.str:   or      a
        jr      z,.end
        push    af
        ld      hl,(SG+VV_T+2)
        ld      de,VV_T
        ld      bc,2
        call    um_in
        ld      hl,(SG+VV_T+2)
        inc     hl
        inc     hl
        ld      (SG+VV_T+2),hl
        ld      hl,(SG+VX_BP)           ; the string's offset
        ld      de,(SG+VV_T+4)
        ex      de,hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (SG+VV_T+4),hl
        ld      hl,(SG+VV_T)            ; the string, in the caller
.byte:  call    um_peek
        push    af
        ld      de,(SG+VX_BP)
        ld      a,d
        or      a
        jr      nz,.bigpop              ; the 257th byte
        push    hl
        ld      hl,SG+ST_ARGV
        add     hl,de
        pop     de
        ex      de,hl                   ; hl = the caller's, de = the block's
        pop     af
        ld      (de),a
        inc     de
        ld      (SG+VX_BP),de           ; (offset + SG + ST_ARGV) - SG - ST_ARGV
        push    hl
        ld      hl,(SG+VX_BP)
        ld      de,-(SG+ST_ARGV)
        add     hl,de
        ld      (SG+VX_BP),hl
        pop     hl
        or      a
        jr      z,.strdone
        inc     hl
        jr      .byte
.strdone:
        pop     af
        dec     a
        jr      .str
.end:   ld      hl,(SG+VV_T+4)
        ld      (hl),0                  ; the table's terminator
        inc     hl
        ld      (hl),0
        ld      hl,(SG+VX_BP)
        ld      (SG+VX_BLEN),hl
        or      a
        ret
.bigpop:
        pop     af
        pop     af
.big:   ld      a,E_2BIG
        scf
        ret

; ex_segs — VX_SEG: the segments the image loads into. A vfork child —
; its parent is in PS_VFORK, which it is exactly while this child runs —
; gets VX_PAGES fresh ones (VX_FRESH = 1); a process on its own pages keeps
; them, taking more or marking the surplus. CF with E_NOMEM, nothing kept.
; Corrupts everything.
ex_segs:
        xor     a
        ld      (SG+VX_NEW),a
        ld      (SG+VX_FRESH),a
        ld      hl,(K_CUR)
        ld      de,P_NPAGES
        add     hl,de
        ld      a,(hl)
        ld      (SG+VX_OLDN),a
        inc     hl                      ; P_SEG
        ld      de,SG+VX_SEG
        ld      bc,3
        ldir
        ld      hl,(K_CUR)
        ld      de,P_PPID
        add     hl,de
        ld      a,(hl)
        cp      PP_NONE
        jr      z,.own
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        ld      de,K_PROC
        add     hl,de                   ; the parent's row
        ld      a,(hl)
        cp      PS_VFORK
        jr      nz,.own
        ; Fresh: every page a new segment.
        ld      a,1
        ld      (SG+VX_FRESH),a
        xor     a
        ld      (SG+VX_OLDN),a          ; nothing of the child's to keep
.own:   ld      a,(SG+VX_PAGES)
        ld      hl,SG+VX_OLDN
        sub     (hl)
        ret     c                       ; fewer pages: the surplus is freed
        ret     z                       ; the same pages
        ld      b,a                     ; b = segments to allocate
        ld      a,(hl)
        ld      hl,SG+VX_SEG
        add     a,l
        ld      l,a                     ; hl -> the first slot to fill
.alloc: push    bc
        push    hl
        ld      a,(K_PID)
        ld      b,a
        k_call  API_MEM_ALLOC
        pop     hl
        pop     bc
        jr      c,.nomem
        ld      (hl),a
        inc     hl
        ld      a,(SG+VX_NEW)
        inc     a
        ld      (SG+VX_NEW),a
        djnz    .alloc
        or      a
        ret
.nomem: call    ex_free_new
        ld      a,E_NOMEM
        scf
        ret

; ex_free_new — the VX_NEW segments this exec allocated, from VX_OLDN on,
; back to the allocator. Corrupts everything.
ex_free_new:
        ld      a,(SG+VX_NEW)
        or      a
        ret     z
        ld      b,a
        ld      a,(SG+VX_OLDN)
        ld      hl,SG+VX_SEG
        add     a,l
        ld      l,a
.free:  push    bc
        push    hl
        ld      a,(hl)
        ld      c,a
        ld      a,(K_PID)
        ld      b,a
        ld      a,c
        k_call  API_MEM_FREE
        pop     hl
        pop     bc
        inc     hl
        djnz    .free
        xor     a
        ld      (SG+VX_NEW),a
        ret

; ex_load — the file into the VX_SEG segments from P0_PROG: a whole sector
; that fits inside its page straight from the driver, the rest through the
; cache and the copy. CF with the errno. Corrupts everything.
ex_load:
        ld      hl,SG+VX_SEG
        ld      (SG+VV_SEGP),hl         ; um_out writes the new pages
        ld      hl,(SG+VX_SIZE)
        ld      (SG+VX_LEFT),hl
        ld      hl,P0_PROG
        ld      (SG+VX_ADDR),hl
        ld      hl,(SG+VR_CLUS)
        ld      (SG+VX_CLUS),hl
        xor     a
        ld      (SG+VX_SIDX),a
        ld      a,(SG+VR_VOL)
        call    fat_sector
        ret     c
        ld      (SG+VX_SEC),hl
        ld      (SG+VX_SEC+2),de
.sector:
        ld      hl,(SG+VX_LEFT)
        ld      a,h
        or      l
        jp      z,.done
        ld      hl,(SG+VX_SEC)
        ld      de,(SG+VX_SEC+2)        ; de:hl = the sector
        ; Whole, and inside its page?
        ld      bc,(SG+VX_LEFT)
        ld      a,b
        cp      2
        jr      c,.copy                 ; the last, partial
        ld      a,(SG+VX_ADDR+1)
        and     3Fh
        cp      3Fh
        jr      z,.copy                 ; crosses the page
        ld      c,a                     ; the slot
        ld      a,(SG+VX_ADDR+1)
        rlca
        rlca
        and     3
        push    hl
        push    de
        push    bc
        call    um_seg
        pop     bc
        pop     de
        pop     hl
        ld      b,a
        ld      a,(SG+VR_VOL)
        k_call  API_BREAD_DIRECT
        ret     c
        ld      bc,512
        jr      .advance
.copy:  ld      a,(SG+VR_VOL)
        k_call  API_BGET
        ret     c
        ld      de,-4000h
        add     hl,de                   ; the buffer as a storage offset
        ld      bc,(SG+VX_LEFT)
        ld      a,b
        cp      2
        jr      c,.piece
        ld      bc,512
.piece: ld      de,(SG+VX_ADDR)
        push    bc
        call    um_out
        pop     bc
.advance:
        ld      hl,(SG+VX_ADDR)
        add     hl,bc
        ld      (SG+VX_ADDR),hl
        ld      hl,(SG+VX_LEFT)
        or      a
        sbc     hl,bc
        ld      (SG+VX_LEFT),hl
        ; The next sector of the cluster, or the next cluster.
        ld      hl,(SG+VX_SEC)
        inc     hl
        ld      (SG+VX_SEC),hl
        ld      a,h
        or      l
        jr      nz,.samecl
        ld      hl,(SG+VX_SEC+2)
        inc     hl
        ld      (SG+VX_SEC+2),hl
.samecl:
        ld      a,(SG+VR_VOL)
        call    fat_mnt
        ld      a,(SG+VX_SIDX)
        inc     a
        cp      (ix+M_SPC)
        jr      c,.same
        ld      hl,(SG+VX_CLUS)
        ld      a,(SG+VR_VOL)
        call    fat_next
        ret     c
        jr      nz,.next
        ld      hl,(SG+VX_LEFT)         ; the chain ended: with bytes left,
        ld      a,h                     ; the size lied
        or      l
        jr      z,.done
        ld      a,E_IO
        scf
        ret
.next:  ld      (SG+VX_CLUS),hl
        ld      a,(SG+VR_VOL)
        call    fat_sector
        ret     c
        ld      (SG+VX_SEC),hl
        ld      (SG+VX_SEC+2),de
        xor     a
.same:  ld      (SG+VX_SIDX),a
        jp      .sector
.done:  or      a
        ret
