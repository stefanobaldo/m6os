; The filesystem's read side, in the switched part: the path copied in
; from the process and walked component by component through FAT12 and
; FAT16 directories, the open-file table and the descriptors, and the
; syscalls open, close, lseek, stat, readdir, chdir and read. Runs under
; the window and the storage gate, calls the resident through the jump
; table alone, keeps no variable of its own — everything it remembers is
; in ST_VFS of the storage segment — and touches a process's memory only
; through um_in and um_out: page 0 directly, pages 1 and 2 through k_copy,
; page 3 (a program the loader put above the kernel) directly.
;
; The node being walked is (VV_VOL, VV_CLUS): a volume and a cluster, 0
; for the volume's root directory; VOL_NONE as the volume is the /mnt
; node, the synthetic directory that lists the volumes. A lookup ends in
; VR_*: the kind of thing found, and what open, stat, chdir and exec need
; of it.

SG_OFT          equ SG+ST_OFT
SG_FD           equ K_FD                ; the descriptor table is resident

; ---------------------------------------------------------------------
; A process's memory

; um_seg — A = a page 0-2: A = the segment behind it, from the three bytes
; VV_SEGP points at — the process's P_SEG, or exec's new ones. Corrupts
; DE, HL.
um_seg:
        ld      l,a
        ld      h,0
        ld      de,(SG+VV_SEGP)
        add     hl,de
        ld      a,(hl)
        ret

; um_in — BC bytes from user address HL to storage offset DE.
; um_out — BC bytes from storage offset HL to user address DE.
; A range may cross pages; each page's piece goes directly when the page
; is 0 or 3 and through k_copy when it is 1 or 2, which the window and the
; gate have taken. Corrupts everything.
um_in:
        xor     a
        jr      um_copy
um_out:
        ex      de,hl
        ld      a,1
um_copy:
        ld      (SG+VV_DIR),a
        ld      (SG+VV_U),hl
        ld      (SG+VV_S),de
        ld      (SG+VV_N),bc
.piece: ld      bc,(SG+VV_N)
        ld      a,b
        or      c
        ret     z
        ld      hl,(SG+VV_U)
        ld      a,h
        and     3Fh
        ld      d,a
        ld      e,l                     ; de = the offset in its page
        ld      hl,4000h
        or      a
        sbc     hl,de                   ; hl = room to the page's end
        push    hl
        or      a
        sbc     hl,bc
        pop     hl
        jr      c,.room                 ; less room than bytes: the room
        ld      h,b
        ld      l,c
.room:  ld      b,h
        ld      c,l                     ; bc = this piece
        ld      a,(SG+VV_U+1)
        rlca
        rlca
        and     3                       ; the page
        ld      hl,(SG+VV_U)
        ld      de,(SG+VV_S)
        cp      1
        jr      z,.remap
        cp      2
        jr      z,.remap
        set     6,d                     ; the storage side, at 4000h+
        ld      a,(SG+VV_DIR)
        or      a
        jr      z,.ldir                 ; in: user -> storage
        ex      de,hl                   ; out: storage -> user
.ldir:  push    bc
        ldir
        pop     bc
        jr      .adv
.remap: push    bc
        call    um_seg                  ; a = the page's segment
        ld      b,a
        ld      a,(K_REC+KR_SEG64K+2)
        ld      c,a                     ; c = the storage segment
        ld      hl,(SG+VV_U)
        res     7,h
        res     6,h                     ; the offset in the page
        ld      de,(SG+VV_S)
        ld      a,(SG+VV_DIR)
        or      a
        jr      nz,.outr
        ld      ixh,b                   ; in: from the page to storage
        ld      ixl,c
        jr      .kc
.outr:  ld      ixh,c                   ; out: from storage to the page
        ld      ixl,b
        ex      de,hl
.kc:    pop     bc
        push    bc
        k_call  API_K_COPY
        pop     bc
.adv:   ld      hl,(SG+VV_U)
        add     hl,bc
        ld      (SG+VV_U),hl
        ld      hl,(SG+VV_S)
        add     hl,bc
        ld      (SG+VV_S),hl
        ld      hl,(SG+VV_N)
        or      a
        sbc     hl,bc
        ld      (SG+VV_N),hl
        jp      .piece

; um_peek — HL = a user address: A = the byte there. Preserves HL, DE, BC.
um_peek:
        push    hl
        push    de
        push    bc
        ld      de,VV_B
        ld      bc,1
        call    um_in
        pop     bc
        pop     de
        pop     hl
        ld      a,(SG+VV_B)
        ret

; vfs_begin — the user addresses of this syscall are the current process's:
; VV_SEGP -> its P_SEG. Preserves everything but the flags.
vfs_begin:
        push    hl
        push    de
        ld      hl,(K_CUR)
        ld      de,P_SEG
        add     hl,de
        ld      (SG+VV_SEGP),hl
        pop     de
        pop     hl
        ret

; ---------------------------------------------------------------------
; The path

; vfs_getpath — HL = the path's user address: VV_PATH holds it, VV_P at
; its start; CF with E_NAMETOOLONG when no terminator comes within
; PATH_MAX. Corrupts everything.
vfs_getpath:
        call    vfs_begin
        ld      de,VV_PATH
        ld      bc,PATH_MAX
        call    um_in
        ld      hl,SG+VV_PATH
        ld      bc,PATH_MAX
        xor     a
        cpir
        jr      nz,.long
        ld      hl,SG+VV_PATH
        ld      (SG+VV_P),hl
        ret                             ; CF clear from cpir
.long:  ld      a,E_NAMETOOLONG
        scf
        ret

; vfs_lookup — the path in VV_PATH, from the process's directory or from
; / : VR_* describes what it names. CF with E_NOENT (a component that is
; not there, or cannot be a name), E_NOTDIR (a file where a directory is
; needed) or E_IO. After E_NOENT, VR_KIND says what the write side may do
; with it: VK_PARENT when only the last component is missing — VV_VOL and
; VV_CLUS (and VR_VOL, VR_CLUS) are then its directory and VV_NAME its FAT
; name — VK_BADNAME when that component is not a name, VK_NONE otherwise.
; Corrupts everything.
vfs_lookup:
        xor     a
        ld      (SG+VV_HASENT),a
        ld      a,VK_NONE
        ld      (SG+VR_KIND),a
        ld      hl,SG+VV_PATH
        ld      a,(hl)
        cp      '/'
        jr      nz,.rel
        ld      a,(K_BLK_ROOT)
        cp      VOL_NONE
        jp      z,.noent                ; no boot volume: no absolute path
        ld      (SG+VV_VOL),a
        ld      hl,0
        ld      (SG+VV_CLUS),hl
        jr      .loop
.rel:   ld      hl,(K_CUR)
        ld      de,P_CWD
        add     hl,de
        ld      a,(hl)
        ld      (SG+VV_VOL),a
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (SG+VV_CLUS),de
.loop:  ld      hl,(SG+VV_P)
.sl:    ld      a,(hl)
        cp      '/'
        jr      nz,.comp
        inc     hl
        jr      .sl
.comp:  ld      (SG+VV_P),hl
        ld      a,(hl)
        or      a
        jp      z,.end                  ; the path ended on the node
        ld      d,h
        ld      e,l                     ; de = the component
        ld      c,0
.len:   ld      a,(hl)
        or      a
        jr      z,.gotlen
        cp      '/'
        jr      z,.gotlen
        inc     hl
        inc     c
        jr      .len
.gotlen:
        ld      (SG+VV_PN),hl           ; past the component
        ld      a,(SG+VV_VOL)
        cp      VOL_NONE
        jr      z,.atmnt
        ld      hl,(SG+VV_CLUS)
        ld      a,h
        or      l
        jr      nz,.scan                ; a subdirectory: . and .. are entries
        ; At a volume's root, which has no . or .. entry of its own.
        call    .isdot
        jp      z,.next
        call    .isdotdot
        jr      nz,.notdd
        ld      a,(SG+VV_VOL)           ; .. at a root: / on the boot volume,
        ld      hl,K_BLK_ROOT           ; /mnt elsewhere
        cp      (hl)
        jr      z,.next
        ld      a,VOL_NONE
        ld      (SG+VV_VOL),a
        jr      .next
.notdd: ld      a,(SG+VV_VOL)
        ld      hl,K_BLK_ROOT
        cp      (hl)
        jr      nz,.scan
        call    .ismnt                  ; mnt at the boot volume's root
        jr      nz,.scan
        ld      a,VOL_NONE
        ld      (SG+VV_VOL),a
        jr      .next
.scan:  call    name83
        jp      c,.badname              ; not a name: nothing has it
        call    dir_find
        jp      c,.missing
        ; More components: this one must be a directory.
        ld      hl,(SG+VV_PN)
        ld      a,(hl)
        or      a
        jr      z,.entry                ; the last component
        ld      a,(SG+VR_ENT+FE_ATTR)
        and     DA_DIR
        jp      z,.notdir
        ld      hl,(SG+VR_ENT+FE_CLUS)
        ld      (SG+VV_CLUS),hl
        jr      .next
.entry: ld      a,VK_ENTRY
        jp      .result
.atmnt: call    .isdot
        jr      z,.next
        call    .isdotdot
        jr      nz,.letter
        ld      a,(K_BLK_ROOT)
        cp      VOL_NONE
        jp      z,.noent
        ld      (SG+VV_VOL),a
        jr      .next
.letter:
        ld      a,c
        cp      1
        jp      nz,.noent
        ld      a,(de)
        call    lower
        sub     'a'
        jp      c,.noent
        ld      hl,K_BLK_NVOL
        cp      (hl)
        jp      nc,.noent
        ld      (SG+VV_VOL),a           ; VV_CLUS is 0 at /mnt
        xor     a
        ld      (SG+VV_HASENT),a
.next:  ld      hl,(SG+VV_PN)
        ld      (SG+VV_P),hl
        jp      .loop
.end:   ; The node itself.
        ld      a,(SG+VV_VOL)
        cp      VOL_NONE
        ld      a,VK_MNT
        jr      z,.result
        ld      hl,(SG+VV_CLUS)
        ld      a,h
        or      l
        ld      a,VK_ROOT
        jr      z,.result
        ld      a,(SG+VV_HASENT)
        or      a
        ld      a,VK_NODE
        jr      z,.result
        ld      hl,(SG+VR_ENT+FE_CLUS)  ; the entry is this directory's
        ld      de,(SG+VV_CLUS)
        or      a
        sbc     hl,de
        ld      a,VK_NODE
        jr      nz,.result
        ld      a,VK_ENTRY
.result:
        ld      (SG+VR_KIND),a
        ld      hl,(SG+VV_VOL)          ; l = the volume
        ld      a,l
        ld      (SG+VR_VOL),a
        ld      a,(SG+VR_KIND)
        or      a
        jr      nz,.synth
        ld      hl,(SG+VR_ENT+FE_CLUS)
        ld      (SG+VR_CLUS),hl
        ld      a,(SG+VR_ENT+FE_ATTR)
        ld      (SG+VR_ATTR),a
        ld      hl,SG+VR_ENT+FE_SIZE
        ld      de,SG+VR_SIZE
        ld      bc,4
        ldir
        ld      hl,SG+VR_ENT+FE_MTIME
        ld      de,SG+VR_MTIME
        ld      bc,4
        ldir
        or      a
        ret
.synth: ; A directory with no entry: the cluster it is known by, size and
        ; time zero.
        ld      hl,(SG+VV_CLUS)
        ld      (SG+VR_CLUS),hl
        ld      a,DA_DIR
        ld      (SG+VR_ATTR),a
        ld      hl,SG+VR_SIZE
        ld      b,8
.zero:  ld      (hl),0
        inc     hl
        djnz    .zero
        or      a
        ret
.missing:
        cp      E_NOENT
        scf                             ; cp cleared the carry
        ret     nz
        ld      a,VK_PARENT
        jr      .last
.badname:
        ld      a,VK_BADNAME
.last:  ; The last component, or a middle one? Only the last leaves a kind.
        ld      hl,(SG+VV_PN)
        ld      c,(hl)
        inc     c
        dec     c
        jr      nz,.noent
        ld      (SG+VR_KIND),a
        ld      a,(SG+VV_VOL)
        ld      (SG+VR_VOL),a
        ld      hl,(SG+VV_CLUS)
        ld      (SG+VR_CLUS),hl
.noent: ld      a,E_NOENT
        scf
        ret
.notdir:
        ld      a,E_NOTDIR
        scf
        ret
; .isdot, .isdotdot, .ismnt — DE = the component, C = its length: Z if it
; is that word. Preserve DE, C.
.isdot: ld      a,c
        cp      1
        ret     nz
        ld      a,(de)
        cp      '.'
        ret
.isdotdot:
        ld      a,c
        cp      2
        ret     nz
        ld      a,(de)
        cp      '.'
        ret     nz
        inc     de
        ld      a,(de)
        dec     de
        cp      '.'
        ret
.ismnt: ld      a,c
        cp      3
        ret     nz
        push    de
        ld      a,(de)
        call    upper
        cp      'M'
        jr      nz,.no
        inc     de
        ld      a,(de)
        call    upper
        cp      'N'
        jr      nz,.no
        inc     de
        ld      a,(de)
        call    upper
        cp      'T'
.no:    pop     de
        ret

; upper — A = a character: upper case. Preserves the rest.
upper:  cp      'a'
        ret     c
        cp      'z'+1
        ret     nc
        sub     20h
        ret

; name83 — DE = a component, C = its length: VV_NAME = it as a FAT name,
; eleven bytes, upper case, space padded; "." and ".." as FAT stores them.
; CF when it cannot be a name: an empty part, a part too long, a second
; dot, a character FAT forbids. Corrupts everything.
name83:
        ld      hl,SG+VV_NAME
        ld      b,11
.pad:   ld      (hl),' '
        inc     hl
        djnz    .pad
        ld      hl,SG+VV_NAME
        ld      a,c
        or      a
        jr      z,.bad
        ld      a,(de)
        cp      '.'
        jr      nz,.name
        ld      a,c                     ; a leading dot: only . or ..
        cp      1
        jr      z,.dots
        cp      2
        jr      nz,.bad
        inc     de
        ld      a,(de)
        dec     de
        cp      '.'
        jr      nz,.bad
        ld      (hl),'.'
        inc     hl
.dots:  ld      (hl),'.'
        or      a
        ret
.name:  ld      b,8                     ; room in the name part
.nch:   ld      a,(de)
        cp      '.'
        jr      z,.ext
        call    .char
        ret     c
        ld      (hl),a
        inc     hl
        inc     de
        dec     b
        jr      z,.full
        dec     c
        jr      nz,.nch
        or      a                       ; a name alone
        ret
.full:  dec     c
        ret     z                       ; eight characters, no extension
        ld      a,(de)
        cp      '.'
        jr      nz,.bad                 ; a ninth character
.ext:   inc     de                      ; past the dot
        dec     c
        jr      z,.bad                  ; "name.": an empty extension
        ld      hl,SG+VV_NAME+8
        ld      b,3
.ech:   ld      a,(de)
        cp      '.'
        jr      z,.bad                  ; a second dot
        call    .char
        ret     c
        ld      (hl),a
        inc     hl
        inc     de
        dec     c
        jr      z,.ok
        djnz    .ech
        jr      .bad                    ; a fourth character
.ok:    or      a
        ret
.bad:   scf
        ret
; .char — A = a character: upper case, CF if FAT forbids it.
.char:  call    upper
        cp      21h
        jr      c,.no
        push    hl
        push    bc
        ld      hl,.forbidden
        ld      bc,.nforbidden
        cpir
        pop     bc
        pop     hl
        jr      z,.no
        or      a
        ret
.no:    scf
        ret
.forbidden:     db  '"*+,/:;<=>?[\]|'
.nforbidden     equ $-.forbidden

; ---------------------------------------------------------------------
; Directories

; dir_scan_start — the node (VV_VOL, VV_CLUS): the scan's cursor at its
; first sector. CF with E_IO. Corrupts everything.
dir_scan_start:
        ld      hl,(SG+VV_CLUS)
        ld      (SG+VV_SCLUS),hl
        ld      a,(SG+VV_VOL)
        call    fat_mnt
        ld      a,h
        or      l
        jr      nz,.chain
        ld      l,(ix+M_ROOT)           ; the root: a fixed area
        ld      h,(ix+M_ROOT+1)
        ld      (SG+VV_SSEC),hl
        ld      l,(ix+M_ROOT+2)
        ld      h,(ix+M_ROOT+3)
        ld      (SG+VV_SSEC+2),hl
        ld      l,(ix+M_ROOTN)
        ld      h,(ix+M_ROOTN+1)
        ld      (SG+VV_SN),hl
        or      a
        ret
.chain: ld      a,(SG+VV_VOL)
        call    fat_sector
        ret     c
        ld      (SG+VV_SSEC),hl
        ld      (SG+VV_SSEC+2),de
        ld      l,(ix+M_SPC)
        ld      h,0
        ld      (SG+VV_SN),hl
        or      a
        ret

; dir_scan_next — DE:HL = the scan's next sector, the cursor past it; Z
; with CF clear when the directory has no more; CF with the errno.
; Corrupts everything.
dir_scan_next:
        ld      hl,(SG+VV_SN)
        ld      a,h
        or      l
        jr      nz,.have
        ld      hl,(SG+VV_SCLUS)
        ld      a,h
        or      l
        ret     z                       ; the root area is done: Z
        ld      a,(SG+VV_VOL)
        call    fat_next
        ret     c
        ret     z                       ; the chain ended: Z
        ld      (SG+VV_SCLUS),hl
        ld      a,(SG+VV_VOL)
        call    fat_sector
        ret     c
        ld      (SG+VV_SSEC),hl
        ld      (SG+VV_SSEC+2),de
        ld      l,(ix+M_SPC)
        ld      h,0
        ld      (SG+VV_SN),hl
.have:  dec     hl
        ld      (SG+VV_SN),hl
        ld      hl,(SG+VV_SSEC)
        ld      de,(SG+VV_SSEC+2)
        push    hl
        inc     hl
        ld      (SG+VV_SSEC),hl
        ld      a,h
        or      l
        jr      nz,.nc
        inc     de
        ld      (SG+VV_SSEC+2),de
        dec     de
.nc:    pop     hl
        or      1                       ; NZ, CF clear
        ret

; dir_find — the node (VV_VOL, VV_CLUS) and VV_NAME: the entry with that
; name copied to VR_ENT, VR_DSEC/VR_DIDX where it is, VV_HASENT set. The
; scan stops at the first entry whose first byte is FE_END, skips deleted
; entries and every entry with the label bit — a label, or a long-name
; entry. CF with E_NOENT or E_IO. Corrupts everything.
dir_find:
        call    dir_scan_start
        ret     c
.sector:
        call    dir_scan_next
        ret     c
        jp      z,.noent
        ld      (SG+VR_DSEC),hl
        ld      (SG+VR_DSEC+2),de
        ld      a,(SG+VV_VOL)
        k_call  API_BGET
        ret     c
        ld      b,16
        ld      c,0
.entry: ld      a,(hl)
        or      a
        jr      z,.noent                ; FE_END
        cp      FE_FREE
        jr      z,.skip
        push    hl
        ld      de,FE_ATTR
        add     hl,de
        bit     3,(hl)                  ; DA_LABEL: a label or an LFN entry
        pop     hl
        jr      nz,.skip
        push    bc
        push    hl
        ld      de,SG+VV_NAME
        ld      b,11
.cmp:   ld      a,(de)
        cp      (hl)
        jr      nz,.diff
        inc     hl
        inc     de
        djnz    .cmp
        pop     hl
        pop     bc
        ld      a,c
        ld      (SG+VR_DIDX),a
        ld      de,SG+VR_ENT
        ld      bc,FE_SIZEOF
        ldir
        ld      a,1
        ld      (SG+VV_HASENT),a
        or      a
        ret
.diff:  pop     hl
        pop     bc
.skip:  ld      de,FE_SIZEOF
        add     hl,de
        inc     c
        djnz    .entry
        jr      .sector
.noent: ld      a,E_NOENT
        scf
        ret

; fe_name_out — HL -> an eleven-byte FAT name, DE -> thirteen bytes:
; "name.ext" in lower case, 0-terminated. Corrupts AF, BC, DE, HL.
fe_name_out:
        ld      b,8
.name:  ld      a,(hl)
        cp      ' '
        jr      z,.ext
        call    lower
        ld      (de),a
        inc     de
.skip:  inc     hl
        djnz    .name
        jr      .ext2
.ext:   inc     hl
        djnz    .ext
.ext2:  ld      a,(hl)                  ; hl -> the extension
        cp      ' '
        jr      z,.done
        ld      a,'.'
        ld      (de),a
        inc     de
        ld      b,3
.e:     ld      a,(hl)
        cp      ' '
        jr      z,.done
        call    lower
        ld      (de),a
        inc     de
        inc     hl
        djnz    .e
.done:  xor     a
        ld      (de),a
        ret

; lower — A = a character: lower case.
lower:  cp      'A'
        ret     c
        cp      'Z'+1
        ret     nc
        add     a,20h
        ret

; vr_record — VV_REC = the DIRENT_SIZE record for what VR_* describes: the
; entry's name, or the volume's letter for a root, "mnt" for /mnt, "." for
; a directory known by its cluster. Corrupts everything.
vr_record:
        ld      hl,SG+VV_REC
        ld      b,DIRENT_SIZE
.zero:  ld      (hl),0
        inc     hl
        djnz    .zero
        ld      de,SG+VV_REC+DE_NAME
        ld      a,(SG+VR_KIND)
        or      a                       ; VK_ENTRY
        jr      nz,.noname
        ld      hl,SG+VR_ENT+FE_NAME
        call    fe_name_out
        jr      .rest
.noname:
        cp      VK_ROOT
        jr      nz,.notroot
        ld      a,(SG+VR_VOL)
        add     a,'a'
        ld      (de),a
        jr      .rest
.notroot:
        cp      VK_MNT
        jr      nz,.node
        ld      hl,s_mntname
        ld      bc,4
        ldir
        jr      .rest
.node:  ld      a,'.'
        ld      (de),a
.rest:  ld      a,(SG+VR_ATTR)
        ld      (SG+VV_REC+DE_ATTR),a
        ld      hl,SG+VR_SIZE
        ld      de,SG+VV_REC+DE_SIZE
        ld      bc,4
        ldir
        ld      hl,SG+VR_MTIME+2        ; the date word, then the time word
        ld      de,SG+VV_REC+DE_MTIME
        ld      bc,2
        ldir
        ld      hl,SG+VR_MTIME
        ld      bc,2
        ldir
        ret
s_mntname:      db  "mnt",0

; ---------------------------------------------------------------------
; Descriptors and open files

; fd_slot — A = a descriptor: HL -> its byte in the current process's row,
; A = the byte; CF with E_BADF when it is not below NOFILE or the byte is
; FD_NONE. Corrupts DE.
fd_slot:
        cp      NOFILE
        jr      nc,.badf
        ld      e,a
        ld      a,(K_PID)
        add     a,a
        add     a,a
        add     a,a
        add     a,e
        ld      l,a
        ld      h,high K_FD
        ld      a,(hl)
        cp      FD_NONE
        jr      z,.badf
        or      a
        ret
.badf:  ld      a,E_BADF
        scf
        ret

; oft_row — A = an open-file row's index: IY -> the row. Corrupts DE, HL.
oft_row:
        ld      l,a
        ld      h,0
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; * 8
        ld      d,h
        ld      e,l
        add     hl,hl                   ; * 16
        add     hl,de                   ; * 24
        ld      de,SG_OFT
        add     hl,de
        push    hl
        pop     iy
        ret

; fd_row — A = a descriptor: IY -> the open-file row it names; CF with
; E_BADF when it is closed, or names the console or the keyboard.
; Corrupts AF, DE, HL.
fd_row:
        call    fd_slot
        ret     c
        cp      80h
        jr      nc,.badf
        jp      oft_row
.badf:  ld      a,E_BADF
        scf
        ret

; ---------------------------------------------------------------------
; The syscalls

; ks_open — SYS_OPEN: HL = path, A = flags. Out: HL = A = the descriptor.
; O_CREAT makes the file when the last component is missing; O_TRUNC with
; a writable mode empties an existing one; a writable mode takes the one
; writer's place (E_BUSY when any row has the file, E_ACCES on a read-only
; entry), a read-only open fails while a writer has it. Both creation and
; truncation reach the disk, and flush the table, before a descriptor or
; a row is taken.
ks_open:
        ld      (SG+VW_FLAGS),a
        and     ~(3|O_APPEND|O_CREAT|O_TRUNC) & 0FFh
        jp      nz,.inval
        ld      a,(SG+VW_FLAGS)
        and     3
        cp      3
        jp      z,.inval
        ld      (SG+VW_ACC),a
        call    vfs_getpath
        ret     c
        call    vfs_lookup
        jr      nc,.found
        cp      E_NOENT
        scf                             ; cp cleared the carry
        ret     nz
        ld      a,(SG+VW_FLAGS)
        and     O_CREAT
        jp      z,.noent
        ld      a,(SG+VR_KIND)
        cp      VK_BADNAME
        jp      z,.inval
        cp      VK_PARENT
        jp      nz,.noent
        ; Created: an empty file in the directory the lookup stopped at.
        call    wr_stamp
        ld      a,DA_ARCHIVE
        ld      de,0
        call    dir_new_entry
        jp      c,wr_finish
        call    ks_bflush
        ret     c
        jr      .alloc
.found: ld      a,(SG+VR_KIND)
        cp      VK_ENTRY
        jr      nz,.dir
        ld      a,(SG+VR_ATTR)
        and     DA_DIR
        jr      nz,.dir
        ; A file.
        ld      a,(SG+VW_ACC)
        or      a
        jr      z,.reader
        ld      a,(SG+VR_ATTR)
        and     DA_RDONLY
        jp      nz,.acces
        xor     a                       ; any row
        call    vfs_busy
        ret     c
        ld      a,(SG+VW_FLAGS)
        and     O_TRUNC
        jr      z,.alloc
        ld      hl,(SG+VR_CLUS)
        ld      a,(SG+VR_SIZE)
        or      (hl)
        ld      hl,SG+VR_SIZE+1
        or      (hl)
        inc     hl
        or      (hl)
        inc     hl
        or      (hl)
        ld      hl,(SG+VR_CLUS)
        or      h
        or      l
        jr      z,.alloc                ; empty already
        call    wr_truncate
        ret     c
        jr      .alloc
.reader:
        ld      a,1                     ; a writer's row
        call    vfs_busy
        ret     c
        jr      .alloc
.dir:   ld      a,(SG+VW_FLAGS)
        and     3|O_CREAT|O_TRUNC
        jp      nz,.isdir
.alloc: ; A descriptor: the lowest FD_NONE in the row.
        ld      a,(K_PID)
        add     a,a
        add     a,a
        add     a,a
        ld      l,a
        ld      h,high K_FD
        ld      b,NOFILE
        ld      c,0
.fd:    ld      a,(hl)
        cp      FD_NONE
        jr      z,.gotfd
        inc     hl
        inc     c
        djnz    .fd
        ld      a,E_MFILE
        scf
        ret
.gotfd: push    hl                      ; -> the descriptor's byte
        push    bc                      ; c = the descriptor
        ; A row: the first with OF_VOL = VOL_NONE.
        ld      iy,SG_OFT
        ld      b,OFT_N
        ld      c,0
.row:   ld      a,(iy+OF_VOL)
        cp      VOL_NONE
        jr      z,.gotrow
        ld      de,OFT_SIZE
        add     iy,de
        inc     c
        djnz    .row
        pop     bc
        pop     hl
        ld      a,E_NFILE
        scf
        ret
.gotrow:
        ld      a,c
        pop     bc
        pop     hl
        ld      (hl),a                  ; the descriptor names the row
        ld      l,c                     ; l = the descriptor
        ; The row, from the result.
        push    hl
        ld      a,(SG+VR_VOL)
        ld      (iy+OF_VOL),a
        ld      (iy+OF_REFS),1
        ld      (iy+OF_ERRNO),0
        ld      (iy+OF_TAIL),0          ; the chain's end: not known yet
        ld      (iy+OF_TAIL+1),0
        ld      a,(SG+VR_KIND)
        ld      c,0                     ; the flags
        cp      VK_MNT
        jr      nz,.notmnt
        ld      (iy+OF_VOL),0           ; any volume but VOL_NONE
        ld      c,OFF_DIR|OFF_MNT
        jr      .flags
.notmnt:
        ld      a,(SG+VR_ATTR)
        and     DA_DIR
        jr      z,.file
        ld      c,OFF_DIR
        ld      hl,(SG+VR_CLUS)
        ld      a,h
        or      l
        jr      nz,.flags
        ld      c,OFF_DIR|OFF_ROOT      ; cluster 0: the root directory
        jr      .flags
.file:  ld      a,(SG+VW_ACC)
        or      a
        jr      z,.flags
        ld      c,OFF_WR                ; the writer
        ld      a,(SG+VW_FLAGS)
        and     O_APPEND
        jr      z,.flags
        ld      c,OFF_WR|OFF_APPEND
.flags: ld      (iy+OF_FLAGS),c
        ld      hl,(SG+VR_CLUS)
        ld      (iy+OF_FIRST),l
        ld      (iy+OF_FIRST+1),h
        ld      (iy+OF_CLUS),l          ; the cursor: at position 0, the
        ld      (iy+OF_CLUS+1),h        ; first cluster
        push    iy
        pop     de
        ld      hl,OF_SIZE
        add     hl,de
        ex      de,hl
        ld      hl,SG+VR_SIZE
        ld      bc,4
        ldir
        xor     a
        ld      (iy+OF_POS),a
        ld      (iy+OF_POS+1),a
        ld      (iy+OF_POS+2),a
        ld      (iy+OF_POS+3),a
        push    iy
        pop     de
        ld      hl,OF_DSEC
        add     hl,de
        ex      de,hl
        ld      hl,SG+VR_DSEC
        ld      bc,5                    ; VR_DSEC and VR_DIDX
        ldir
        pop     hl
        ld      h,0
        ld      a,l
        or      a                       ; CF clear
        ret
.inval: ld      a,E_INVAL
        scf
        ret
.noent: ld      a,E_NOENT
        scf
        ret
.acces: ld      a,E_ACCES
        scf
        ret
.isdir: ld      a,E_ISDIR
        scf
        ret

; ks_close — SYS_CLOSE: A = fd.
ks_close:
        call    fd_slot
        ret     c
        ld      (hl),FD_NONE
        cp      80h
        jr      nc,.done                ; the console or the keyboard
        call    oft_row
        dec     (iy+OF_REFS)
        jr      nz,.done
        ld      (iy+OF_VOL),VOL_NONE    ; nobody's: the row is free
.done:  xor     a
        ret

; ks_lseek — SYS_LSEEK: A = fd, DE:HL = offset, B = whence. Out: DE:HL =
; the position; E_INVAL for a whence not 0-2 or a negative result.
ks_lseek:
        push    bc
        push    de
        push    hl
        call    fd_row
        pop     hl
        pop     de
        pop     bc
        ret     c
        ld      a,b
        cp      3
        jr      nc,.inval
        or      a
        jr      z,.set
        push    iy
        pop     ix
        ld      c,OF_POS                ; SEEK_CUR
        dec     a
        jr      z,.add
        ld      c,OF_SIZE               ; SEEK_END
.add:   ld      b,0
        add     ix,bc
        ld      c,(ix+0)
        ld      b,(ix+1)
        add     hl,bc
        ld      c,(ix+2)
        ld      b,(ix+3)
        ex      de,hl
        adc     hl,bc
        ex      de,hl
.set:   bit     7,d
        jr      nz,.inval               ; negative
        ld      (iy+OF_POS),l
        ld      (iy+OF_POS+1),h
        ld      (iy+OF_POS+2),e
        ld      (iy+OF_POS+3),d
        ld      (iy+OF_CLUS),low OF_CLUS_NONE   ; the cursor: rebuilt on
        ld      (iy+OF_CLUS+1),high OF_CLUS_NONE ; the next read
        or      a
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; ks_stat — SYS_STAT: HL = path, DE = a DIRENT_SIZE buffer.
ks_stat:
        push    de
        call    vfs_getpath
        jr      c,.err
        call    vfs_lookup
        jr      c,.err
        call    vr_record
        pop     de
        ld      hl,VV_REC
        ld      bc,DIRENT_SIZE
        call    um_out
        xor     a
        ret
.err:   pop     de
        ret

; ks_chdir — SYS_CHDIR: HL = path, a directory: the process's P_CWD.
ks_chdir:
        call    vfs_getpath
        ret     c
        call    vfs_lookup
        ret     c
        ld      a,(SG+VR_ATTR)
        and     DA_DIR
        jr      z,.notdir
        ld      hl,(K_CUR)
        ld      de,P_CWD
        add     hl,de
        ld      a,(SG+VR_KIND)
        cp      VK_MNT
        ld      a,VOL_NONE
        jr      z,.vol
        ld      a,(SG+VR_VOL)
.vol:   ld      (hl),a
        inc     hl
        ld      de,(SG+VR_CLUS)
        ld      (hl),e
        inc     hl
        ld      (hl),d
        xor     a
        ret
.notdir:
        ld      a,E_NOTDIR
        scf
        ret

; ks_readdir — SYS_READDIR: A = fd (a directory), HL = a DIRENT_SIZE
; buffer. Out: HL = 1 with the next entry in the buffer, 0 at the end.
ks_readdir:
        push    hl
        call    vfs_begin
        call    fd_row
        pop     de
        ret     c
        ld      (SG+VV_RBUF),de
        ld      (SG+VV_ROW),iy          ; the row again after every call that
                                        ; may reach the driver: IY does not
                                        ; survive one
        bit     0,(iy+OF_FLAGS)         ; OFF_DIR
        jr      z,.notdir
        bit     2,(iy+OF_FLAGS)         ; OFF_MNT
        jr      nz,.mnt
.next:  call    rd_entry                ; hl -> the entry at OF_POS
        ret     c
        jr      z,.end
        ld      a,(hl)
        or      a
        jr      z,.end                  ; FE_END
        cp      FE_FREE
        jr      z,.skip
        push    hl
        ld      de,FE_ATTR
        add     hl,de
        bit     3,(hl)
        pop     hl
        jr      nz,.skip
        ; A live entry: the record, then past it.
        ld      de,SG+VR_ENT
        ld      bc,FE_SIZEOF
        ldir
        xor     a
        ld      (SG+VR_KIND),a          ; VK_ENTRY
        ld      hl,(SG+VR_ENT+FE_CLUS)
        ld      (SG+VR_CLUS),hl
        ld      a,(SG+VR_ENT+FE_ATTR)
        ld      (SG+VR_ATTR),a
        ld      hl,SG+VR_ENT+FE_SIZE
        ld      de,SG+VR_SIZE
        ld      bc,4
        ldir
        ld      hl,SG+VR_ENT+FE_MTIME
        ld      de,SG+VR_MTIME
        ld      bc,4
        ldir
        call    vr_record
        call    rd_advance
        ret     c
.out:   ld      iy,(SG+VV_ROW)
        ld      hl,VV_REC
        ld      de,(SG+VV_RBUF)
        ld      bc,DIRENT_SIZE
        call    um_out
        ld      hl,1
        or      a
        ret
.skip:  call    rd_advance
        ret     c
        jr      .next
.end:   ld      hl,0
        or      a
        ret
.notdir:
        ld      a,E_NOTDIR
        scf
        ret
.mnt:   ld      a,(iy+OF_POS)
        ld      hl,K_BLK_NVOL
        cp      (hl)
        jr      nc,.end
        ld      (SG+VR_VOL),a
        inc     a
        ld      (iy+OF_POS),a
        ld      a,VK_ROOT
        ld      (SG+VR_KIND),a
        ld      a,DA_DIR
        ld      (SG+VR_ATTR),a
        ld      hl,SG+VR_SIZE
        ld      b,8
.z:     ld      (hl),0
        inc     hl
        djnz    .z
        call    vr_record
        jr      .out

; rd_entry — IY -> a directory's row: HL -> the entry at index OF_POS, in
; its sector's buffer; Z with CF clear when the directory has no sector
; there (the root area or the chain ended); CF with the errno. Corrupts
; everything but IY.
rd_entry:
        ld      a,(iy+OF_VOL)
        call    fat_mnt
        ld      l,(iy+OF_POS)
        ld      h,(iy+OF_POS+1)
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l
        srl     h
        rr      l                       ; hl = the sector index, pos / 16
        bit     1,(iy+OF_FLAGS)         ; OFF_ROOT
        jr      z,.chain
        ld      e,(ix+M_ROOTN)
        ld      d,(ix+M_ROOTN+1)
        push    hl
        or      a
        sbc     hl,de
        pop     hl
        jp      nc,.end                 ; past the root area
        ld      c,(ix+M_ROOT)
        ld      b,(ix+M_ROOT+1)
        add     hl,bc
        ld      c,(ix+M_ROOT+2)
        ld      b,(ix+M_ROOT+3)
        ex      de,hl
        ld      hl,0
        adc     hl,bc
        ex      de,hl                   ; de:hl = the sector
        jr      .sector
.chain: ld      a,(iy+OF_CLUS)
        ld      c,a
        ld      a,(iy+OF_CLUS+1)
        or      c
        jr      nz,.cursor
        ; OF_CLUS_NONE: rebuild from the first cluster.
        ld      a,(ix+M_SPCSH)
        add     a,4
        push    iy
        pop     ix
        call    of_cursor
        ld      iy,(SG+VV_ROW)
        ret     c
        jr      z,.end
        ld      a,(iy+OF_VOL)
        call    fat_mnt
.cursor:
        ld      a,(iy+OF_CLUS)
        ld      c,a
        ld      a,(iy+OF_CLUS+1)
        and     c
        inc     a
        jr      z,.end                  ; OF_CLUS_END
        ld      a,(iy+OF_POS)
        ld      c,a
        ld      a,(iy+OF_POS+1)
        ld      b,a
        srl     b
        rr      c
        srl     b
        rr      c
        srl     b
        rr      c
        srl     b
        rr      c                       ; c = pos / 16, low byte
        ld      a,(ix+M_SPC)
        dec     a
        and     c                       ; the sector's index in the cluster
        push    af
        ld      l,(iy+OF_CLUS)
        ld      h,(iy+OF_CLUS+1)
        ld      a,(iy+OF_VOL)
        call    fat_sector
        jr      c,.pop
        pop     af
        call    add32_a
.sector:
        ld      a,(iy+OF_VOL)
        k_call  API_BGET
        ld      iy,(SG+VV_ROW)
        ret     c
        ld      a,(iy+OF_POS)
        and     0Fh
        add     a,a
        add     a,a
        add     a,a
        add     a,a                     ; (pos & 15) * 16: at most 240
        ld      e,a
        ld      d,0
        sla     e
        rl      d                       ; * 32, in sixteen bits: the ninth
        add     hl,de                   ;   entry of a sector is at 256
        or      1                       ; NZ, CF clear
        ret
.pop:   pop     de
        ret                             ; CF
.end:   xor     a                       ; Z, CF clear
        ret

; rd_advance — IY -> a directory's row: OF_POS one entry on; when the entry
; index leaves its cluster the cursor follows the chain, OF_CLUS_END at its
; end. CF with the errno. Corrupts everything but IY.
rd_advance:
        ld      l,(iy+OF_POS)
        ld      h,(iy+OF_POS+1)
        inc     hl
        ld      (iy+OF_POS),l
        ld      (iy+OF_POS+1),h
        ld      a,h
        or      l
        jr      nz,.nowrap
        inc     (iy+OF_POS+2)
.nowrap:
        bit     1,(iy+OF_FLAGS)         ; OFF_ROOT: no chain
        jr      nz,.done
        ld      a,(iy+OF_VOL)
        call    fat_mnt
        ld      a,(ix+M_SPCSH)
        add     a,4
        ld      b,a
        ld      de,1
.mask:  sla     e                       ; entries per cluster
        rl      d
        djnz    .mask
        dec     de                      ; the mask
        ld      a,h
        and     d
        ld      h,a
        ld      a,l
        and     e
        or      h
        jr      nz,.done                ; still inside the cluster
        ld      l,(iy+OF_CLUS)
        ld      h,(iy+OF_CLUS+1)
        ld      a,(iy+OF_VOL)
        call    fat_next
        ld      iy,(SG+VV_ROW)
        ret     c
        jr      nz,.set
        ld      hl,OF_CLUS_END
.set:   ld      (iy+OF_CLUS),l
        ld      (iy+OF_CLUS+1),h
.done:  or      a
        ret

; add32_a — DE:HL += A. Corrupts AF.
add32_a:
        add     a,l
        ld      l,a
        ret     nc
        inc     h
        ret     nz
        inc     de
        ret

; ks_read — the switched half of SYS_READ: A = the open-file row's index
; (the resident resolved the descriptor), HL = buffer, BC = length. Out:
; HL = bytes read, 0 at the end of the file; E_ISDIR on a directory; an
; error after some bytes were delivered returns them and is owed to the
; next call (OFF_ERR, OF_ERRNO). A whole sector to a 256-byte boundary of
; page 0-2 that does not cross the page goes straight from the driver;
; everything else through the cache and the copy.
ks_read:
        push    hl
        push    bc
        call    vfs_begin
        call    oft_row
        pop     bc
        pop     hl
        ld      (SG+VV_ROW),iy          ; reloaded after every call that may
                                        ; reach the driver, which does not
                                        ; keep IY
        bit     0,(iy+OF_FLAGS)         ; OFF_DIR
        jp      nz,.isdir
        bit     3,(iy+OF_FLAGS)         ; OFF_ERR: the error owed
        jr      z,.fresh
        res     3,(iy+OF_FLAGS)
        ld      a,(iy+OF_ERRNO)
        scf
        ret
.fresh: ld      (SG+VV_RBUF),hl
        ld      hl,0
        ld      (SG+VV_RDONE),hl
        ; n = min(BC, size - pos).
        ld      l,(iy+OF_SIZE)
        ld      h,(iy+OF_SIZE+1)
        ld      e,(iy+OF_POS)
        ld      d,(iy+OF_POS+1)
        or      a
        sbc     hl,de
        ex      de,hl                   ; de = low word of what is left
        ld      l,(iy+OF_SIZE+2)
        ld      h,(iy+OF_SIZE+3)
        push    bc
        ld      c,(iy+OF_POS+2)
        ld      b,(iy+OF_POS+3)
        sbc     hl,bc
        pop     bc
        jp      c,.eof                  ; the position is past the end
        jr      nz,.all                 ; more than 64K left: all of BC
        ex      de,hl                   ; hl = left
        ld      a,h
        or      l
        jp      z,.eof
        push    hl
        or      a
        sbc     hl,bc
        pop     hl
        jr      c,.n                    ; left < BC: left
.all:   ld      h,b
        ld      l,c
.n:     ld      (SG+VV_RLEFT),hl
        ld      a,h
        or      l
        jp      z,.eof
        ; The cursor.
        ld      a,(iy+OF_VOL)
        call    fat_mnt
        ld      a,(iy+OF_CLUS)
        ld      c,a
        ld      a,(iy+OF_CLUS+1)
        or      c
        jr      nz,.cursor
        ld      a,(ix+M_SPCSH)
        add     a,9
        push    iy
        pop     ix
        call    of_cursor
        ld      iy,(SG+VV_ROW)
        jp      c,.err
        jp      z,.eio                  ; the chain ends before the position
.cursor:
        ld      a,(iy+OF_CLUS)
        ld      c,a
        ld      a,(iy+OF_CLUS+1)
        and     c
        inc     a
        jp      z,.eio                  ; OF_CLUS_END, with bytes to read
        ; The running sector: the cluster's first plus (pos >> 9) & (spc -
        ; 1), kept in VV_RSEC and stepped once per sector, so the FAT is
        ; consulted at a cluster change and nowhere else.
        ld      a,(iy+OF_VOL)
        call    fat_mnt                 ; ix -> the mount row again
        ld      a,(ix+M_SPC)
        ld      (SG+VV_RSPC),a
        ld      a,(iy+OF_POS+1)
        ld      c,a
        ld      a,(iy+OF_POS+2)
        rrca                            ; bit 0 into CF
        rr      c                       ; c = (pos >> 9) & FFh
        ld      a,(ix+M_SPC)
        dec     a
        and     c
        ld      (SG+VV_RSIDX),a
        push    af
        ld      l,(iy+OF_CLUS)
        ld      h,(iy+OF_CLUS+1)
        ld      a,(iy+OF_VOL)
        call    fat_sector
        jp      c,.poperr
        pop     af
        call    add32_a
        ld      (SG+VV_RSEC),hl
        ld      (SG+VV_RSEC+2),de
.loop:  ld      hl,(SG+VV_RLEFT)
        ld      a,h
        or      l
        jp      z,.done
        ld      hl,(SG+VV_RSEC)
        ld      de,(SG+VV_RSEC+2)       ; de:hl = the sector
        ; Direct?
        ld      a,(iy+OF_POS)
        or      a
        jr      nz,.copy                ; not at a sector boundary
        ld      a,(iy+OF_POS+1)
        and     1
        jr      nz,.copy
        ld      bc,(SG+VV_RLEFT)
        ld      a,b
        cp      2
        jr      c,.copy                 ; fewer than 512 left
        ld      bc,(SG+VV_RBUF)
        ld      a,c
        or      a
        jr      nz,.copy                ; not on a 256-byte boundary
        ld      a,b
        cp      0C0h
        jr      nc,.copy                ; page 3: not a process page
        and     3Fh
        cp      3Fh
        jr      z,.copy                 ; the sector would cross the page
        ld      c,a                     ; c = the slot
        ld      a,b
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
        ld      b,a                     ; b = the segment
        ld      a,(iy+OF_VOL)
        k_call  API_BREAD_DIRECT
        ld      iy,(SG+VV_ROW)
        jp      c,.err
        ld      bc,512
        jr      .advance
.copy:  ld      a,(iy+OF_VOL)
        k_call  API_BGET
        ld      iy,(SG+VV_ROW)
        jp      c,.err
        ld      a,(iy+OF_POS)
        ld      c,a
        ld      a,(iy+OF_POS+1)
        and     1
        ld      b,a                     ; bc = the offset in the sector
        add     hl,bc
        push    hl
        ld      hl,512
        or      a
        sbc     hl,bc                   ; hl = to the sector's end
        ld      bc,(SG+VV_RLEFT)
        push    hl
        or      a
        sbc     hl,bc
        pop     hl
        jr      c,.piece                ; less to the end than left
        ld      h,b
        ld      l,c
.piece: ld      b,h
        ld      c,l                     ; bc = this piece
        pop     hl                      ; hl = the source, in page 1
        ld      de,-4000h
        add     hl,de                   ; as a storage offset
        ld      de,(SG+VV_RBUF)
        push    bc
        call    um_out
        pop     bc
.advance:
        ; pos += bc, the buffer and the counts with it.
        ld      hl,(SG+VV_RBUF)
        add     hl,bc
        ld      (SG+VV_RBUF),hl
        ld      hl,(SG+VV_RDONE)
        add     hl,bc
        ld      (SG+VV_RDONE),hl
        ld      hl,(SG+VV_RLEFT)
        or      a
        sbc     hl,bc
        ld      (SG+VV_RLEFT),hl
        ld      l,(iy+OF_POS)
        ld      h,(iy+OF_POS+1)
        add     hl,bc
        ld      (iy+OF_POS),l
        ld      (iy+OF_POS+1),h
        jr      nc,.nocarry
        inc     (iy+OF_POS+2)
        jr      nz,.nocarry
        inc     (iy+OF_POS+3)
.nocarry:
        ; A sector completed: the next one, and the next cluster after the
        ; last sector of this one.
        ld      a,l
        or      a
        jp      nz,.loop                ; inside the sector still
        ld      a,h
        and     1
        jp      nz,.loop
        ld      hl,(SG+VV_RSEC)
        inc     hl
        ld      (SG+VV_RSEC),hl
        ld      a,h
        or      l
        jr      nz,.samecl
        ld      hl,(SG+VV_RSEC+2)
        inc     hl
        ld      (SG+VV_RSEC+2),hl
.samecl:
        ld      a,(SG+VV_RSIDX)
        inc     a
        ld      (SG+VV_RSIDX),a
        ld      hl,SG+VV_RSPC
        cp      (hl)
        jp      c,.loop                 ; inside the cluster still
        xor     a
        ld      (SG+VV_RSIDX),a
        ld      l,(iy+OF_CLUS)
        ld      h,(iy+OF_CLUS+1)
        ld      a,(iy+OF_VOL)
        call    fat_next
        ld      iy,(SG+VV_ROW)
        jr      c,.err
        jr      nz,.setclus
        ld      hl,OF_CLUS_END
        ld      (iy+OF_CLUS),l
        ld      (iy+OF_CLUS+1),h
        ld      hl,(SG+VV_RLEFT)
        ld      a,h
        or      l
        jp      z,.done                 ; the chain and the file end together
        jr      .eio
.setclus:
        ld      (iy+OF_CLUS),l
        ld      (iy+OF_CLUS+1),h
        ld      a,(iy+OF_VOL)
        call    fat_sector
        jr      c,.err
        ld      (SG+VV_RSEC),hl
        ld      (SG+VV_RSEC+2),de
        jp      .loop
.done:  ld      hl,(SG+VV_RDONE)
        or      a
        ret
.eof:   ld      hl,0
        or      a
        ret
.poperr:
        pop     de
        jr      .err
.eio:   ld      a,E_IO
.err:   ; A = the errno: returned now if nothing was delivered, else owed.
        ld      hl,(SG+VV_RDONE)
        ld      c,a
        ld      a,h
        or      l
        ld      a,c
        jr      z,.now
        ld      (iy+OF_ERRNO),a
        set     3,(iy+OF_FLAGS)         ; OFF_ERR
        or      a
        ret                             ; hl = the bytes delivered
.now:   scf
        ret
.isdir: ld      a,E_ISDIR
        scf
        ret
