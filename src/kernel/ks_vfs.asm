; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
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

; um_seg — A = a page 0-3: A = the segment behind it, from the three bytes
; VV_SEGP points at — the process's P_SEG, or exec's new ones — or, for
; page 3, the legacy segment the hinge's second stub names: the one
; caller that asks for page 3 is a copy for the legacy process, whose
; page 3 is its own (um_copy). Corrupts DE, HL.
um_seg:
        cp      3
        jr      nz,.page
        ld      a,(K_HINGE2+1)          ; the legacy page-3 segment
        ret
.page:  ld      l,a
        ld      h,0
        ld      de,(SG+VV_SEGP)
        add     hl,de
        ld      a,(hl)
        ret

; um_in — BC bytes from user address HL to storage offset DE.
; um_out — BC bytes from storage offset HL to user address DE.
; A range may cross pages; each page's piece goes directly when the page
; is 3, or 0 with the segment VV_SEGP names actually in it, and through
; k_copy when it is 1 or 2, which the window and the gate have taken, or
; 0 of another process's image. Corrupts everything.
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
        cp      1
        jr      z,.remap
        cp      2
        jr      z,.remap
        or      a
        jr      z,.page0
        ; Page 3: the kernel's, always mapped — unless the caller is the
        ; legacy process, whose page 3 is a segment of its own that the
        ; kernel's has displaced for the length of the call.
        ld      a,(K_DOSPID)
        or      a
        jr      z,.direct
        ld      hl,K_PID
        cp      (hl)
        jr      z,.remap
        jr      .direct
.page0: ; Page 0 is mapped, but is it the page the caller means? An image
        ; loading into fresh segments — a vfork child's exec, a spawnv —
        ; names another process's page 0, and a direct copy would land in
        ; the current one's.
        call    um_seg                  ; a = the segment meant
        ld      hl,K_MAP
        cp      (hl)                    ; the one in page 0 now
        jr      nz,.remap
.direct:
        ld      hl,(SG+VV_U)
        ld      de,(SG+VV_S)
        set     6,d                     ; the storage side, at 4000h+
        ld      a,(SG+VV_DIR)
        or      a
        jr      z,.ldir                 ; in: user -> storage
        ex      de,hl                   ; out: storage -> user
.ldir:  push    bc
        ldir
        pop     bc
        jr      .adv
.remap: ld      a,(SG+VV_U+1)
        rlca
        rlca
        and     3                       ; the page again
        push    bc
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

; um_check — HL = a user address, BC = a length: CF with E_FAULT when the
; range reaches page 3, which is the kernel's — unless the caller is
; process 0, whose own program may lie there, or the legacy process,
; whose page 3 is its own up to the hinge. Every syscall that writes
; into a process's memory calls it first: a wrong buffer must refuse, not
; overwrite the resident. Preserves A, HL, BC, DE.
um_check:
        push    af
        push    hl
        push    de
        ex      de,hl                   ; de = the address
        ld      hl,0C000h               ; the limit: the kernel's page
        ld      a,(K_PID)
        or      a
        jr      z,.ok                   ; process 0: page 3 is its own
        ld      hl,K_DOSPID
        cp      (hl)
        ld      hl,0C000h
        jr      nz,.limit
        ld      hl,K_HINGE              ; the legacy process: up to the hinge
.limit: or      a
        sbc     hl,de                   ; hl = the room before the limit
        jr      c,.efault               ; it starts past it
        or      a
        sbc     hl,bc                   ; minus the length: CF when short
        jr      c,.efault
.ok:    pop     de
        pop     hl
        pop     af
        and     a                       ; CF clear, A as it came
        ret
.efault:
        pop     de
        pop     hl
        pop     af
        ld      a,E_FAULT
        scf
        ret

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
; VV_SEGP -> its P_SEG — or K_MAP for the legacy process, whose crossing
; wrote there what the program has in pages 0-2 now, PUT_Pn's included,
; so that a transfer lands where the DOS says it does. Preserves
; everything but the flags.
vfs_begin:
        push    af
        push    hl
        push    de
        ld      hl,(K_CUR)
        ld      de,P_SEG
        add     hl,de
        ld      a,(K_DOSPID)
        or      a
        jr      z,.set
        ld      de,K_PID
        ld      a,(de)
        ld      de,K_DOSPID
        ex      de,hl
        cp      (hl)
        ex      de,hl
        jr      nz,.set
        ld      hl,K_MAP
.set:   ld      (SG+VV_SEGP),hl
        pop     de
        pop     hl
        pop     af
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
        jp      z,.atmnt
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
        jp      z,.next
        ld      a,VOL_NONE
        ld      (SG+VV_VOL),a
        jp      .next
.notdd: ld      a,(SG+VV_VOL)
        ld      hl,K_BLK_ROOT
        cp      (hl)
        jr      nz,.scan
        call    .ismnt                  ; mnt at the boot volume's root
        jr      nz,.scan
        ld      a,VOL_NONE
        ld      (SG+VV_VOL),a
        jp      .next
.scan:  xor     a
        ld      (SG+VW_GATHER),a
        ld      a,c
        ld      (SG+VL_WANT),a          ; the component's length, for the
        ld      a,1                     ; chains' length filter
        ld      (SG+VL_SHORT),a
        call    name83
        jr      nc,.find
        ld      de,(SG+VV_P)            ; not a short name: a long one?
        ld      a,(SG+VL_WANT)
        ld      c,a
        call    lfn_valid
        jp      c,.badname              ; neither: nothing has it
        xor     a
        ld      (SG+VL_SHORT),a
.find:  ld      a,(SG+VW_CREATE)
        or      a
        jr      z,.look
        ld      hl,(SG+VV_PN)           ; the last component of a creation:
        ld      a,(hl)
        or      a
        jr      nz,.look
        ld      de,(SG+VV_P)            ; ASCII alone is written
        ld      a,(SG+VL_WANT)
        ld      c,a
        call    lfn_ascii
        jp      c,.badname
        call    lfn_prepare             ; what it needs, and the scan gathers
.look:  ld      a,1
        call    lfn_reset               ; a lookup
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
        xor     a
        ld      (SG+VV_NT),a
        ld      (SG+VV_CASE),a
        ld      (SG+VV_MIXED),a
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
        ld      a,FN_LBASE              ; a name alone
        jr      .fold
.full:  dec     c
        jr      nz,.more
        ld      a,FN_LBASE              ; eight characters, no extension
        jr      .fold
.more:  ld      a,(de)
        cp      '.'
        jr      nz,.bad                 ; a ninth character
.ext:   ld      a,FN_LBASE
        call    .fold
        inc     de                      ; past the dot
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
.ok:    ld      a,FN_LEXT
; .fold — A = a part's bit: set in VV_NT when the part had lower case and
; no upper case; VV_CASE cleared for the next part. CF clear.
.fold:  ld      b,a
        ld      a,(SG+VV_CASE)
        cp      3
        jr      nz,.notmixed
        ld      (SG+VV_MIXED),a         ; both cases: only a chain keeps it
.notmixed:
        cp      1
        jr      nz,.nofold
        ld      a,(SG+VV_NT)
        or      b
        ld      (SG+VV_NT),a
.nofold:
        xor     a
        ld      (SG+VV_CASE),a
        ret
.bad:   scf
        ret
; .char — A = a character: upper case, CF if FAT forbids it; its case
; noted in VV_CASE (bit 0 lower, bit 1 upper).
.char:  cp      'a'
        jr      c,.notlow
        cp      'z'+1
        jr      nc,.notlow
        push    hl
        ld      hl,SG+VV_CASE
        set     0,(hl)
        pop     hl
        jr      .up
.notlow:
        cp      'A'
        jr      c,.up
        cp      'Z'+1
        jr      nc,.up
        push    hl
        ld      hl,SG+VV_CASE
        set     1,(hl)
        pop     hl
.up:    call    upper
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

; dir_find — the node (VV_VOL, VV_CLUS) and the component: the entry
; with that name — the long name its chain carries, VL_WANT bytes at
; (VV_P), or with VL_SHORT the short name VV_NAME — copied to VR_ENT,
; VR_DSEC/VR_DIDX where it is, VR_LN and VR_LSEC/VR_LIDX its chain,
; VV_HASENT set. The scan stops at the first entry whose first byte is
; FE_END, skips deleted entries and volume labels, and feeds every
; long-name part to lfn_feed; lfn_reset comes before it. With VW_GATHER
; every entry also goes to lfn_track, for the run of free slots and the
; aliases a creation needs; with VW_EXCL the entry rename is moving is
; no match. CF with E_NOENT or E_IO. Corrupts everything.
dir_find:
        call    dir_scan_start
        ret     c
.sector:
        call    dir_scan_next
        ret     c
        jp      z,.ended
        ld      (SG+VR_DSEC),hl
        ld      (SG+VR_DSEC+2),de
        ld      a,(SG+VV_VOL)
        k_call  API_BGET
        ret     c
        ld      b,16
        ld      c,0
.entry: ld      a,(hl)
        or      a
        jp      z,.end                  ; FE_END
        cp      FE_FREE
        jr      z,.free
        push    hl
        ld      de,FE_ATTR
        add     hl,de
        ld      a,(hl)
        pop     hl
        and     3Fh
        cp      FE_LFN
        jr      z,.lfn                  ; a long-name part: read it
        bit     3,a                     ; DA_LABEL: a volume label
        jr      nz,.skip
        ld      a,1
        call    .track                  ; a live entry: the run breaks, an
        push    bc                      ; alias counts
        push    hl
        call    lfn_close               ; a valid chain behind it?
        jr      z,.short
        call    lfn_cmp                 ; the component, as a long name
        jr      z,.found
.short: ld      a,(SG+VL_SHORT)
        or      a
        jr      z,.diff                 ; the component fits no short name
        pop     hl
        push    hl
        ld      de,SG+VV_NAME
        ld      b,11
.cmp:   ld      a,(de)
        cp      (hl)
        jr      nz,.diff
        inc     hl
        inc     de
        djnz    .cmp
.found: pop     hl
        pop     bc
        ld      a,(SG+VW_EXCL)
        or      a
        jr      z,.take
        push    hl
        ld      hl,(SG+VV_PN)
        ld      a,(hl)
        pop     hl
        or      a
        jr      nz,.take                ; a middle component: no exclusion
        call    .excluded               ; the entry being moved: no match
        jr      z,.skip
.take:  ld      a,c
        ld      (SG+VR_DIDX),a
        ld      de,SG+VR_ENT
        ld      bc,FE_SIZEOF
        ldir
        ld      a,1
        ld      (SG+VV_HASENT),a
        or      a
        ret
.lfn:   ld      a,2
        call    .track
        push    bc
        call    lfn_feed
        pop     bc
        jr      .skip
.free:  xor     a
        call    .track
        jr      .skip
.diff:  pop     hl
        pop     bc
.skip:  ld      de,FE_SIZEOF
        add     hl,de
        inc     c
        dec     b
        jp      nz,.entry
        jp      .sector
.end:   ld      a,(SG+VW_GATHER)
        or      a
        jr      z,.noent
        xor     a
        call    lfn_track_end           ; the run to the end, from here
        jr      .noent
.ended: ld      a,(SG+VW_GATHER)
        or      a
        jr      z,.noent
        ld      a,1
        call    lfn_track_end           ; free slots at the end, if any
.noent: ld      a,E_NOENT
        scf
        ret
; .track — A = an entry's kind: to lfn_track when the scan gathers.
; Preserves HL, BC.
.track: push    af
        ld      a,(SG+VW_GATHER)
        or      a
        jr      z,.notrack
        pop     af
        jp      lfn_track
.notrack:
        pop     af
        ret
; .excluded — Z when the entry at VR_DSEC, index C, on VV_VOL is the one
; VW_OSEC, VW_OIDX and VW_OVOL name. Preserves HL, BC.
.excluded:
        push    hl
        push    bc
        ld      a,(SG+VW_OIDX)
        cp      c
        jr      nz,.other
        ld      hl,SG+VV_VOL
        ld      a,(SG+VW_OVOL)
        cp      (hl)
        jr      nz,.other
        ld      hl,SG+VR_DSEC
        ld      de,SG+VW_OSEC
        ld      b,4
.x:     ld      a,(de)
        cp      (hl)
        jr      nz,.other
        inc     hl
        inc     de
        djnz    .x
.other: pop     bc
        pop     hl
        ret

; fe_name_out — HL -> an eleven-byte FAT name, C = its case bits (FE_NT),
; DE -> thirteen bytes: "name.ext", 0-terminated, each part lower-cased
; when its bit says so; a byte that is no letter passes as it is.
; Corrupts AF, BC, DE, HL.
fe_name_out:
        ld      b,8
.name:  ld      a,(hl)
        cp      ' '
        jr      z,.ext
        bit     3,c                     ; FN_LBASE
        call    nz,lower
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
        bit     4,c                     ; FN_LEXT
        call    nz,lower
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

; vr_record — the record for what VR_* describes, in the two pieces
; um_out hands out: its name in ST_LNAME, 0-terminated — the entry's,
; long when its chain is valid (there already), else short with its case
; bits; the volume's letter for a root, "mnt" for /mnt, "." for a
; directory known by its cluster — BC = its length with the terminator;
; and VV_RECX, the nine bytes from DE_ATTR on: the attribute, the size,
; the FAT date word then the time word. Corrupts everything.
vr_record:
        ld      a,(SG+VR_KIND)
        or      a                       ; VK_ENTRY
        jr      nz,.noname
        ld      a,(SG+VR_LN)
        or      a
        jr      nz,.rest                ; the long name, as its chain reads
        ld      hl,SG+VR_ENT+FE_NAME
        ld      a,(SG+VR_ENT+FE_NT)
        ld      c,a
        ld      de,SG+ST_LNAME
        call    fe_name_out
        jr      .rest
.noname:
        ld      de,SG+ST_LNAME
        cp      VK_ROOT
        jr      nz,.notroot
        ld      a,(SG+VR_VOL)
        add     a,'a'
        ld      (de),a
        inc     de
        xor     a
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
        inc     de
        xor     a
        ld      (de),a
.rest:  ld      a,(SG+VR_ATTR)
        ld      (SG+VV_RECX),a
        ld      hl,SG+VR_SIZE
        ld      de,SG+VV_RECX+1
        ld      bc,4
        ldir
        ld      hl,SG+VR_MTIME+2        ; the date word, then the time word
        ld      bc,2
        ldir
        ld      hl,SG+VR_MTIME
        ld      bc,2
        ldir
        ld      hl,SG+ST_LNAME          ; the name's length, its 0 included
        ld      bc,0
.len:   ld      a,(hl)
        inc     hl
        inc     bc
        or      a
        jr      nz,.len
        ret
s_mntname:      db  "mnt",0

; vr_short — after vr_record: ST_LNAME rewritten in the short form — for
; an entry its 8.3 alias in upper case, else the name vr_record gave —
; 0-terminated and zero-filled to 13 bytes, then the locator: VR_VOL,
; VR_CLUS, VR_DSEC and VR_DIDX (zeros for what has no entry). BC = 21.
; Corrupts everything.
vr_short:
        ld      a,(SG+VR_KIND)
        or      a                       ; VK_ENTRY
        jr      nz,.noent
        ld      hl,SG+VR_ENT+FE_NAME
        ld      c,0                     ; no case bits: as stored
        ld      de,SG+ST_LNAME
        call    fe_name_out
        jr      .pad
.noent: ld      hl,SG+VR_DSEC
        ld      b,5
.zsec:  ld      (hl),0
        inc     hl
        djnz    .zsec
.pad:   ld      hl,SG+ST_LNAME
        ld      b,13
.find:  ld      a,(hl)
        or      a
        jr      z,.fill
        inc     hl
        djnz    .find
        jr      .loc
.fill:  ld      (hl),0
        inc     hl
        djnz    .fill
.loc:   ex      de,hl                   ; de -> ST_LNAME+13
        ld      a,(SG+VR_VOL)
        ld      (de),a
        inc     de
        ld      hl,SG+VR_CLUS
        ld      bc,2
        ldir
        ld      hl,SG+VR_DSEC
        ld      bc,5
        ldir
        ld      bc,13+DL_SIZE
        ret

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
        and     ~(3|O_APPEND|O_CREAT|O_TRUNC|O_SHORT) & 0FFh
        jp      nz,.inval
        ld      a,(SG+VW_FLAGS)
        and     3
        cp      3
        jp      z,.inval
        ld      (SG+VW_ACC),a
        call    vfs_getpath
        ret     c
        ld      a,(SG+VW_FLAGS)
        and     O_CREAT
        ld      (SG+VW_CREATE),a        ; the lookup gathers for a creation
        call    vfs_lookup
        push    af
        xor     a
        ld      (SG+VW_CREATE),a
        pop     af
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
        jr      nz,.short
        ld      c,OFF_DIR|OFF_ROOT      ; cluster 0: the root directory
.short: ld      a,(SG+VW_FLAGS)
        and     O_SHORT
        jr      z,.flags
        set     6,c                     ; OFF_SHORT
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

; ks_stat — SYS_STAT: HL = path, DE = a DIRENT_SIZE buffer. ks_statl —
; SYS_STATL: the same, the record in the short form (DE_LOC).
ks_statl:
        ld      a,1
        jr      st_go
ks_stat:
        xor     a
st_go:  ld      (SG+VV_SHORT),a
        ex      de,hl
        ld      bc,DIRENT_SIZE
        call    um_check                ; the record's buffer
        ex      de,hl
        ret     c
        push    de
        call    vfs_getpath
        jr      c,.err
        call    vfs_lookup
        jr      c,.err
        call    vr_record
        ld      a,(SG+VV_SHORT)
        or      a
        call    nz,vr_short
        pop     de
        push    de
        ld      hl,ST_LNAME             ; the name, bc bytes with its 0
        call    um_out
        pop     de
        inc     d                       ; DE_ATTR: 256 on
        ld      hl,VV_RECX
        ld      bc,9
        call    um_out
        xor     a
        ret
.err:   pop     de
        ret

; ks_chdir — SYS_CHDIR: HL = path, a directory: the process's P_CWD.
ks_chdir:
        ld      a,h
        or      l
        jr      z,.loc
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
.loc:   ; DE -> a locator: the volume, then the cluster, as P_CWD has them.
        call    vfs_begin
        ex      de,hl
        ld      de,VV_T
        ld      bc,LOC_SIZE
        call    um_in
        ld      a,(SG+VV_T)
        cp      VOL_NONE
        jr      z,.locok
        cp      VOL_N
        jr      nc,.inval
.locok: ld      hl,(K_CUR)
        ld      de,P_CWD
        add     hl,de
        ex      de,hl
        ld      hl,SG+VV_T
        ld      bc,LOC_SIZE
        ldir
        xor     a
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; ks_getcwd — SYS_GETCWD: HL = a buffer, BC = its size. Out: HL = the
; length of the path written, 0-terminated: /mnt when the process's
; directory is /mnt, / for the boot volume's root, /mnt/<letter> for
; another volume's, else the directory's canonical name — / and the
; components from the root down, /mnt/<letter> in front when the volume
; is not the boot one. Built from the end of VV_PATH backwards: each
; directory's own .. entry names its parent, and a scan of the parent for
; the entry whose cluster is the directory's gives its name. E_NAMETOOLONG
; when the path or the buffer is too short, E_IO.
ks_getcwd:
        ld      a,b
        and     80h
        ld      (SG+VV_SHORT),a         ; bit 15 of the size: the short form
        res     7,b
        call    um_check
        ret     c
        ld      (SG+VV_RBUF),hl
        ld      (SG+VV_RLEFT),bc
        call    vfs_begin
        ld      hl,SG+VV_PATH+PATH_MAX-1
        ld      (hl),0                  ; the terminator; the path grows down
        ld      (SG+VV_P),hl
        ld      hl,(K_CUR)
        ld      de,P_CWD
        add     hl,de
        ld      a,(hl)
        ld      (SG+VV_VOL),a
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      (SG+VV_CLUS),de
        cp      VOL_NONE
        jr      nz,.walk
        ld      hl,s_slashmnt           ; /mnt itself
        ld      bc,4
        call    .prepend
        jp      .out
.walk:  ld      hl,(SG+VV_CLUS)
        ld      a,h
        or      l
        jp      z,.root                 ; at the volume's root
        ; The directory's .. entry: its first sector, entry 1.
        call    dir_scan_start
        ret     c
        call    dir_scan_next
        ret     c
        jp      z,.io                   ; a directory with no sector
        ld      a,(SG+VV_VOL)
        k_call  API_BGET
        ret     c
        ld      de,FE_SIZEOF+FE_CLUS
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; de = the parent's cluster
        ld      hl,(SG+VV_CLUS)
        ld      (SG+VR_CLUS),hl         ; the cluster to find in the parent
        ld      (SG+VV_CLUS),de
        call    dir_find_clus           ; VR_ENT = this directory's entry
        ret     c
        ld      a,(SG+VV_SHORT)
        or      a
        jr      nz,.alias
        ld      hl,SG+ST_LNAME          ; its long name, when it has one
        ld      a,(SG+VR_LN)
        or      a
        jr      nz,.len
        ld      a,(SG+VR_ENT+FE_NT)
        jr      .name83
.alias: xor     a                       ; the short form: no case bits
.name83:
        ld      c,a
        ld      hl,SG+VR_ENT+FE_NAME
        ld      de,SG+ST_LNAME
        call    fe_name_out             ; "name.ext", 0-terminated
        ld      hl,SG+ST_LNAME
.len:   push    hl
        ld      bc,0
.count: ld      a,(hl)
        or      a
        jr      z,.gotlen
        inc     hl
        inc     bc
        jr      .count
.gotlen:
        pop     hl
        call    .prepend
        ret     c
        ld      hl,s_slash
        ld      bc,1
        call    .prepend
        ret     c
        jp      .walk
.root:  ld      a,(SG+VV_VOL)
        ld      hl,K_BLK_ROOT
        cp      (hl)
        jr      z,.boot
        add     a,'a'
        ld      (SG+ST_LNAME),a         ; /mnt/<letter>
        ld      hl,SG+ST_LNAME
        ld      bc,1
        call    .prepend
        ret     c
        ld      hl,s_slashmnt
        ld      bc,5                    ; "/mnt/"
        call    .prepend
        ret     c
        jr      .out
.boot:  ld      hl,(SG+VV_P)
        ld      de,SG+VV_PATH+PATH_MAX-1
        or      a
        sbc     hl,de
        jr      nz,.out                 ; something was built
        ld      hl,s_slash              ; the root alone: /
        ld      bc,1
        call    .prepend
.out:   ; The result to the caller: length + 1 bytes from VV_P.
        ld      hl,SG+VV_PATH+PATH_MAX-1
        ld      de,(SG+VV_P)
        or      a
        sbc     hl,de                   ; hl = the length
        push    hl
        inc     hl                      ; with the terminator
        ld      de,(SG+VV_RLEFT)
        ex      de,hl
        or      a
        sbc     hl,de                   ; size - (length + 1)
        jr      c,.long
        ld      b,d
        ld      c,e                     ; bc = length + 1
        ld      hl,(SG+VV_P)
        ld      de,-SG
        add     hl,de                   ; the storage offset
        ld      de,(SG+VV_RBUF)
        call    um_out
        pop     hl
        or      a
        ret
.long:  pop     hl
        ld      a,E_NAMETOOLONG
        scf
        ret
.io:    ld      a,E_IO
        scf
        ret
; .prepend — HL -> BC bytes: copied in front of what is built, VV_P moved
; down. CF with E_NAMETOOLONG when VV_PATH is full. Corrupts everything.
.prepend:
        ld      de,(SG+VV_P)
        ex      de,hl
        or      a
        sbc     hl,bc                   ; the new start
        ex      de,hl
        push    de
        push    hl
        ld      hl,SG+VV_PATH
        ex      de,hl
        or      a
        sbc     hl,de                   ; new start - the area's start
        pop     hl
        pop     de
        jr      c,.full
        ld      (SG+VV_P),de
        ldir
        or      a
        ret
.full:  ld      a,E_NAMETOOLONG
        scf
        ret
s_slashmnt:     db  "/mnt/"
s_slash:        db  "/"

; dir_find_clus — the node (VV_VOL, VV_CLUS) and VR_CLUS = a cluster: the
; directory entry in that node whose first cluster it is and whose
; attribute has DA_DIR, copied to VR_ENT, VR_DSEC/VR_DIDX where it is —
; dir_find with the cluster for the name. The cluster is kept in VR_CLUS
; and not in VV_T, which is the FAT walk's own: fat_next writes VV_T+6
; when the scan crosses into the node's second cluster, and a cluster
; kept there was lost for every entry past the first. CF with E_NOENT or
; E_IO. Corrupts everything.
dir_find_clus:
        xor     a
        call    lfn_reset               ; every chain read: the name is
        call    dir_scan_start          ; wanted, not matched
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
        ld      a,(hl)
        and     3Fh
        cp      FE_LFN
        jr      z,.lfn                  ; a long-name part: read it
        bit     3,(hl)                  ; DA_LABEL: a volume label
        jr      nz,.pop
        pop     hl
        push    bc
        call    lfn_close               ; the chain behind it, if any
        pop     bc
        push    hl
        ld      de,FE_ATTR
        add     hl,de
        bit     4,(hl)                  ; DA_DIR
        jr      z,.pop
        ld      de,FE_CLUS-FE_ATTR
        add     hl,de
        ld      a,(SG+VR_CLUS)
        cp      (hl)
        jr      nz,.pop
        inc     hl
        ld      a,(SG+VR_CLUS+1)
        cp      (hl)
        jr      nz,.pop
        pop     hl
        ld      a,c
        ld      (SG+VR_DIDX),a
        ld      de,SG+VR_ENT
        ld      bc,FE_SIZEOF
        ldir
        ld      a,1
        ld      (SG+VV_HASENT),a
        or      a
        ret
.lfn:   pop     hl
        push    bc
        call    lfn_feed
        pop     bc
        jr      .skip
.pop:   pop     hl
.skip:  ld      de,FE_SIZEOF
        add     hl,de
        inc     c
        djnz    .entry
        jr      .sector
.noent: ld      a,E_NOENT
        scf
        ret

; ks_readdir — SYS_READDIR: A = fd (a directory), HL = a DIRENT_SIZE
; buffer. Out: HL = 1 with the next entry in the buffer, 0 at the end.
ks_readdir:
        ld      bc,DIRENT_SIZE
        call    um_check
        ret     c
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
        jp      z,.notdir
        bit     2,(iy+OF_FLAGS)         ; OFF_MNT
        jp      nz,.mnt
        xor     a
        call    lfn_reset               ; every chain read
.next:  call    rd_entry                ; hl -> the entry at OF_POS
        ret     c
        jp      z,.end
        ld      a,(hl)
        or      a
        jp      z,.end                  ; FE_END
        cp      FE_FREE
        jp      z,.skip
        push    hl
        ld      de,FE_ATTR
        add     hl,de
        ld      a,(hl)
        pop     hl
        and     3Fh
        cp      FE_LFN
        jp      z,.lfn                  ; a long-name part: read it
        bit     3,a
        jp      nz,.skip                ; a volume label
        call    lfn_close               ; the chain behind it, if any
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
        ld      a,(iy+OF_VOL)           ; the locator's volume and index;
        ld      (SG+VR_VOL),a           ; rd_entry left the sector
        ld      a,(iy+OF_POS)
        and     0Fh
        ld      (SG+VR_DIDX),a
        call    vr_record
        bit     6,(iy+OF_FLAGS)         ; OFF_SHORT
        call    nz,vr_short
        ld      (SG+VV_RLEFT),bc        ; the name's length: rd_advance
        call    rd_advance              ; keeps no register
        ret     c
.out:   ld      iy,(SG+VV_ROW)
        ld      hl,ST_LNAME             ; the name, bc bytes with its 0;
        ld      de,(SG+VV_RBUF)         ; what follows it is left alone
        ld      bc,(SG+VV_RLEFT)
        call    um_out
        ld      hl,VV_RECX
        ld      de,(SG+VV_RBUF)
        inc     d                       ; DE_ATTR: 256 on
        ld      bc,9
        call    um_out
        ld      hl,1
        or      a
        ret
.lfn:   bit     6,(iy+OF_FLAGS)         ; OFF_SHORT: no chain is read
        jp      nz,.skip
        call    lfn_feed
.skip:  call    rd_advance
        ret     c
        jp      .next
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
        jp      nc,.end
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
        ld      (SG+VV_RLEFT),bc
        jp      .out

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
        ld      (SG+VR_DSEC),hl         ; where a chain starts, if one does
        ld      (SG+VR_DSEC+2),de
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
        call    um_check                ; the buffer, before a byte moves
        ret     c
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

; ---------------------------------------------------------------------
; The volume's parameters

; ks_statfs — SYS_STATFS: A = a volume, HL = a 32-byte buffer, B = 0, or
; 1 to count the volume's free clusters too. Out: the block SF_* in the
; buffer, from the mount and volume rows. E_NODEV for a row not filled,
; E_FAULT, E_IO. The free count walks the whole table through the cache —
; sector by sector for FAT16, cluster by cluster for FAT12 — and costs
; what that costs: ~1.4 s for a 256-sector FAT16 through an SD card.
ks_statfs:
        ld      (SG+VV_SFVOL),a
        ld      a,b
        ld      (SG+VV_SFFLG),a
        ld      bc,SF_SIZE
        call    um_check
        ret     c
        ld      (SG+VV_RBUF),hl
        call    vfs_begin
        ld      a,(SG+VV_SFVOL)
        ld      hl,K_BLK_NVOL
        cp      (hl)
        jp      nc,.nodev
        ; The block, zeroed, in ST_LNAME.
        ld      hl,SG+ST_LNAME
        ld      de,SG+ST_LNAME+1
        ld      bc,SF_SIZE-1
        ld      (hl),0
        ldir
        ld      a,(SG+VV_SFVOL)
        call    fat_mnt                 ; ix -> the mount row
        ld      l,a
        ld      h,0
        ld      e,l
        ld      d,h
        add     hl,hl
        add     hl,de                   ; * 3
        add     hl,hl
        add     hl,hl                   ; * 12
        ld      de,K_VOL
        add     hl,de
        push    hl
        pop     iy                      ; iy -> the volume row
        ld      hl,SG+ST_LNAME
        inc     a
        ld      (hl),a                  ; SF_DRIVE
        inc     hl
        ld      (hl),low 512            ; SF_SECSIZE
        inc     hl
        ld      (hl),high 512
        inc     hl
        ld      a,(ix+M_SPC)
        ld      (hl),a                  ; SF_SPC
        inc     hl
        ld      e,(iy+V_FIRST)
        ld      d,(iy+V_FIRST+1)        ; de = the volume's first sector,
        ld      a,(ix+M_FAT)            ;   its low word
        sub     e
        ld      (hl),a                  ; SF_RESERVED = M_FAT - V_FIRST
        inc     hl
        ld      a,(ix+M_FAT+1)
        sbc     a,d
        ld      (hl),a
        inc     hl
        ld      a,(ix+M_NFATS)
        ld      (hl),a                  ; SF_NFATS
        inc     hl
        ld      a,(ix+M_ROOTN)          ; SF_ROOTENT = sectors * 16
        ld      c,a
        ld      a,(ix+M_ROOTN+1)
        ld      b,a
        sla     c
        rl      b
        sla     c
        rl      b
        sla     c
        rl      b
        sla     c
        rl      b
        ld      (hl),c
        inc     hl
        ld      (hl),b
        inc     hl
        ld      a,(iy+V_COUNT)
        ld      (hl),a                  ; SF_TOTAL, low 16 bits
        inc     hl
        ld      a,(iy+V_COUNT+1)
        ld      (hl),a
        inc     hl
        ld      (hl),0F8h               ; SF_MEDIA
        inc     hl
        ld      a,(ix+M_FATSZ)
        ld      (hl),a                  ; SF_FATSZ, low 8 bits
        inc     hl
        ld      a,(ix+M_ROOT)
        sub     e
        ld      (hl),a                  ; SF_ROOTSEC = M_ROOT - V_FIRST
        inc     hl
        ld      a,(ix+M_ROOT+1)
        sbc     a,d
        ld      (hl),a
        inc     hl
        ld      a,(ix+M_DATA)
        sub     e
        ld      (hl),a                  ; SF_DATASEC = M_DATA - V_FIRST
        inc     hl
        ld      a,(ix+M_DATA+1)
        sbc     a,d
        ld      (hl),a
        inc     hl
        ld      c,(ix+M_NCLUS)
        ld      b,(ix+M_NCLUS+1)
        inc     bc
        ld      (hl),c                  ; SF_MAXCLUS = M_NCLUS + 1
        inc     hl
        ld      (hl),b
        inc     hl
        inc     hl                      ; SF_DIRTY: 0
        ld      a,0FFh
        ld      (hl),a                  ; SF_VOLID: -1
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        inc     hl
        ld      (hl),a
        ld      a,(SG+VV_SFFLG)
        or      a
        jp      z,.out
        ; The free clusters: entries 2 to M_NCLUS+1 of the table.
        ld      a,(SG+VV_SFVOL)
        ld      (SG+VV_T+2),a           ; fat_fsec's, fat_get's volume
        ld      hl,2
        ld      (SG+VV_T),hl            ; the cluster being counted
        bit     0,(ix+M_FLAGS)          ; MF_FAT16
        jr      z,.f12
        xor     a
        ld      (SG+VV_T+6),a           ; the table's sector index
.f16s:  ld      a,(SG+VV_T+6)
        call    fat_fsec                ; hl -> the sector
        ret     c
        ld      a,(SG+VV_T+6)
        or      a
        jr      nz,.f16e
        inc     hl                      ; the first sector: past entries
        inc     hl                      ;   0 and 1
        inc     hl
        inc     hl
.f16e:  ld      a,(SG+VV_T+2)
        call    fat_mnt                 ; ix again: the bget corrupts it
        ld      c,(ix+M_NCLUS)
        ld      b,(ix+M_NCLUS+1)
        inc     bc                      ; bc = the last cluster
.f16n:  ld      de,(SG+VV_T)
        ex      de,hl
        or      a
        sbc     hl,bc
        ex      de,hl
        jr      z,.f16l                 ; the last: count it, then done
        jr      nc,.out                 ; past it
.f16l:  push    af
        ld      a,(hl)
        inc     hl
        or      (hl)
        inc     hl
        jr      nz,.f16u
        ld      de,(SG+ST_LNAME+SF_FREE)
        inc     de
        ld      (SG+ST_LNAME+SF_FREE),de
.f16u:  pop     af
        jr      z,.out                  ; that was the last cluster
        ld      de,(SG+VV_T)
        inc     de
        ld      (SG+VV_T),de
        ld      a,l                     ; the sector's end: 512 bytes from
        or      a                       ;   a 256-aligned buffer
        jr      nz,.f16n
        ld      a,h
        and     1
        jr      nz,.f16n
        ld      hl,SG+VV_T+6
        inc     (hl)
        jr      .f16s
.f12:   ld      hl,(SG+VV_T)
        ld      a,(SG+VV_T+2)
        call    fat_get                 ; hl = the entry; corrupts VV_T
        ret     c
        ld      a,h
        or      l
        jr      nz,.f12n
        ld      de,(SG+ST_LNAME+SF_FREE)
        inc     de
        ld      (SG+ST_LNAME+SF_FREE),de
.f12n:  ld      a,(SG+VV_T+2)
        call    fat_mnt
        ld      c,(ix+M_NCLUS)
        ld      b,(ix+M_NCLUS+1)
        inc     bc
        ld      hl,(SG+VV_T)
        or      a
        sbc     hl,bc
        jr      z,.out                  ; the last cluster was counted
        ld      hl,(SG+VV_T)
        inc     hl
        ld      (SG+VV_T),hl
        jr      .f12
.out:   ld      hl,ST_LNAME
        ld      de,(SG+VV_RBUF)
        ld      bc,SF_SIZE
        call    um_out
        xor     a
        ret
.nodev: ld      a,E_NODEV
        scf
        ret
