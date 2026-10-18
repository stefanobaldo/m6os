; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; df — every mounted volume, one row each: its name as the boot listing
; prints it (/mnt/a), its size, the space used and the space free, in
; KB, and the filesystem, from statfs with the free count. The count is
; the device's where the volume's driver has the FAT accelerator, else
; a walk of the whole table — about a second and a half for a
; 256-sector FAT16 through an SD card. A volume that answers an error
; other than ENODEV is reported and the rest are listed; the status is
; 1 then.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      hl,s_head
        call    out_puts
        xor     a
.loop:  ld      (vol),a
        ld      hl,sf
        ld      b,1
        sys     SYS_STATFS
        jr      nc,.row
        cp      E_NODEV
        jr      z,.next
        push    af
        ld      a,(vol)
        call    name
        pop     af
        ld      de,s_name
        call    err_file
        jr      .next
.row:   ld      a,(vol)
        call    name
        ld      hl,s_name
        call    out_puts
        ld      hl,(sf+SF_NCLUS32)      ; the size, the free space, in KB
        ld      de,(sf+SF_NCLUS32+2)
        call    kb
        ld      (size),hl
        ld      (size+2),de
        ld      b,9
        call    out_dec32
        ld      hl,(sf+SF_FREE32)
        ld      de,(sf+SF_FREE32+2)
        call    kb
        ld      (free),hl
        ld      (free+2),de
        ld      hl,(size)               ; used = size - free
        ld      de,(free)
        or      a
        sbc     hl,de
        push    hl
        ld      hl,(size+2)
        ld      de,(free+2)
        sbc     hl,de
        ex      de,hl
        pop     hl
        ld      b,9
        call    out_dec32
        ld      hl,(free)
        ld      de,(free+2)
        ld      b,9
        call    out_dec32
        ld      hl,s_fat12
        ld      a,(sf+SF_FS)
        or      a
        jr      z,.fs
        ld      hl,s_fat16
.fs:    call    out_puts
.next:  ld      a,(vol)
        inc     a
        cp      VOL_N
        jp      c,.loop
        ld      a,(lib_status)
        ret

; name — A = a volume: s_name reads /mnt/<its letter>. Corrupts A.
name:   add     a,'a'
        ld      (s_name+5),a
        ret

; kb — DE:HL = clusters: DE:HL = clusters * sectors per cluster / 2,
; the KB they hold. The sectors per cluster are a power of two, 1 to
; 128: one shift right for 1, (log2 - 1) shifts left otherwise.
; Corrupts AF.
kb:     ld      a,(sf+SF_SPC)
        cp      1
        jr      nz,.left
        srl     d
        rr      e
        rr      h
        rr      l
        ret
.left:  srl     a
.more:  cp      2
        ret     c
        add     hl,hl
        rl      e
        rl      d
        srl     a
        jr      .more

s_head: db      "Volume      Size     Used     Free Type",10,0
s_name: db      "/mnt/x",0
s_fat12: db     " FAT12",10,0
s_fat16: db     " FAT16",10,0

        include "lib/out.inc"
        include "lib/err.inc"
        m6_bss
        bss     sf,SF_SIZE
        bss     size,4
        bss     free,4
        bss     vol,1
