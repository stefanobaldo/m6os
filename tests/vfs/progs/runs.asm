; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; runs — the vfs test's run process, three pages (the code in page 0, a
; 16K buffer filling page 1, the stack in page 2): the direct path's runs
; bounded by the page, the file and the chain, and what a run that fails
; leaves. Every driver call is counted through K_BLK_CALLS after a first
; read has cached the table.
;   (a) /data/big.bin, 4K into 3E00h: one sector to the page's end, then
;       seven in page 1 — 2 calls;
;   (b) 16K into 4000h: the page's 32 sectors, one call;
;   (c) 2560 then 3072 bytes into 4000h: a run ending inside a cluster
;       and the next starting there — one call each;
;   (d) /frag1 and /frag2 written 4K at a time, alternating, so that each
;       takes every other cluster: /frag1 read whole into 4000h in 4
;       calls, one per fragment; both removed;
;   (e) /mnt/c/badlink.bin, whose third link no chain may hold: 8K asked,
;       4K delivered, E_IO owed to the next read;
;   (f) /mnt/c/farr.bin, whose second cluster lies past the partition's
;       end: 4K asked, 2K delivered and E_IO owed; reopened at 2048, E_IO
;       at once with nothing delivered;
;   (g) /mnt/c/far.bin, 512 bytes long, in the last cluster inside the
;       partition: 2560 bytes written at 512 allocate the cluster past
;       the end and fail whole — E_IO, nothing written, the size 512 —
;       then 512 written at 512 land in the file's own cluster, read
;       back, and the size is 1024.
; Exits with 0, or the number of the check that failed.
        include "kernel/kernel.inc"
        include "m6prog.inc"
U_B3E       equ 3E00h           ; page 0's last 256-byte slot, into page 1
U_P1        equ 4000h           ; page 1, 16K
U_BUFU      equ 2001h           ; unaligned: the copy path
        m6_header 3
start:
        ; (a)
        ld      hl,.big
        xor     a
        sys     SYS_OPEN
        jp      c,.x1
        ld      (.fd),a
        ld      hl,U_P1
        ld      bc,4096
        call    .read                   ; the table cached
        jp      c,.x1
        call    .rewind
        call    .count0
        ld      hl,U_B3E
        ld      bc,4096
        call    .read
        jp      c,.x2
        ld      de,4096
        or      a
        sbc     hl,de
        jp      nz,.x2
        call    .delta
        ld      de,2
        or      a
        sbc     hl,de
        jp      nz,.x2
        ld      hl,U_B3E
        ld      bc,4096
        ld      de,0
        call    .verify
        jp      nz,.x2
        ; (b)
        call    .rewind
        call    .count0
        ld      hl,U_P1
        ld      bc,16384
        call    .read
        jp      c,.x3
        ld      de,16384
        or      a
        sbc     hl,de
        jp      nz,.x3
        call    .delta
        ld      de,1
        or      a
        sbc     hl,de
        jp      nz,.x3
        ld      hl,U_P1
        ld      bc,16384
        ld      de,0
        call    .verify
        jp      nz,.x3
        ; (c)
        call    .rewind
        call    .count0
        ld      hl,U_P1
        ld      bc,2560
        call    .read
        jp      c,.x4
        ld      de,2560
        or      a
        sbc     hl,de
        jp      nz,.x4
        call    .delta
        ld      de,1
        or      a
        sbc     hl,de
        jp      nz,.x4
        ld      hl,U_P1
        ld      bc,2560
        ld      de,0
        call    .verify
        jp      nz,.x4
        call    .count0
        ld      hl,U_P1
        ld      bc,3072
        call    .read
        jp      c,.x4
        ld      de,3072
        or      a
        sbc     hl,de
        jp      nz,.x4
        call    .delta
        ld      de,1
        or      a
        sbc     hl,de
        jp      nz,.x4
        ld      hl,U_P1
        ld      bc,3072
        ld      de,2560
        call    .verify
        jp      nz,.x4
        ld      a,(.fd)
        sys     SYS_CLOSE
        ; (d) the two files, 4K each in turn, four times.
        ld      hl,.frag1
        ld      a,O_CREAT|O_WRONLY
        sys     SYS_OPEN
        jp      c,.x5
        ld      (.fd),a
        ld      hl,.frag2
        ld      a,O_CREAT|O_WRONLY
        sys     SYS_OPEN
        jp      c,.x5
        ld      (.fd2),a
        ld      de,0
.alt:   push    de
        ld      hl,U_P1
        ld      bc,4096
        call    .fill
        ld      a,(.fd)
        ld      hl,U_P1
        ld      bc,4096
        sys     SYS_WRITE
        jp      c,.x5
        ld      a,(.fd2)
        ld      hl,U_P1
        ld      bc,4096
        sys     SYS_WRITE
        jp      c,.x5
        pop     de
        ld      hl,4096
        add     hl,de
        ex      de,hl
        ld      a,d
        cp      40h
        jr      nz,.alt                 ; 4 x 4K
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      a,(.fd2)
        sys     SYS_CLOSE
        ld      hl,.frag1
        xor     a
        sys     SYS_OPEN
        jp      c,.x6
        ld      (.fd),a
        call    .count0
        ld      hl,U_P1
        ld      bc,16384
        call    .read
        jp      c,.x6
        ld      de,16384
        or      a
        sbc     hl,de
        jp      nz,.x6
        call    .delta
        ld      de,4
        or      a
        sbc     hl,de
        jp      nz,.x6
        ld      hl,U_P1
        ld      bc,16384
        ld      de,0
        call    .verify
        jp      nz,.x7
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      hl,.frag1
        sys     SYS_UNLINK
        jp      c,.x7
        ld      hl,.frag2
        sys     SYS_UNLINK
        jp      c,.x7
        ; (e)
        ld      hl,.badlink
        xor     a
        sys     SYS_OPEN
        jp      c,.x8
        ld      (.fd),a
        ld      hl,U_P1
        ld      bc,8192
        call    .read
        jp      c,.x8
        ld      de,4096
        or      a
        sbc     hl,de
        jp      nz,.x8
        ld      hl,U_P1
        ld      bc,8192
        call    .read
        jp      nc,.x8
        cp      E_IO
        jp      nz,.x8
        ld      a,(.fd)
        sys     SYS_CLOSE
        ; (f)
        ld      hl,.farr
        xor     a
        sys     SYS_OPEN
        jp      c,.x9
        ld      (.fd),a
        ld      hl,U_P1
        ld      bc,4096
        call    .read
        jp      c,.x9
        ld      de,2048
        or      a
        sbc     hl,de
        jp      nz,.x9
        ld      hl,U_P1
        ld      bc,4096
        call    .read
        jp      nc,.x9
        cp      E_IO
        jp      nz,.x9
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      hl,.farr
        xor     a
        sys     SYS_OPEN
        jp      c,.x9
        ld      (.fd),a
        ld      hl,2048
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,.x9
        ld      hl,U_P1
        ld      bc,4096
        call    .read
        jp      nc,.x9
        cp      E_IO
        jp      nz,.x9
        ld      a,(.fd)
        sys     SYS_CLOSE
        ; (g)
        ld      hl,.far
        ld      a,O_RDWR
        sys     SYS_OPEN
        jp      c,.x10
        ld      (.fd),a
        ld      hl,512
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,.x10
        ld      hl,U_P1
        ld      bc,2560
        ld      de,512
        call    .fill
        ld      a,(.fd)
        ld      hl,U_P1
        ld      bc,2560
        sys     SYS_WRITE
        jp      nc,.x10                 ; must fail, whole
        cp      E_IO
        jp      nz,.x10
        ld      a,(.fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_END
        sys     SYS_LSEEK
        jp      c,.x10
        ld      a,d
        or      e
        jp      nz,.x10
        ld      de,512
        or      a
        sbc     hl,de
        jp      nz,.x10                 ; the size still 512
        ld      hl,512
        ld      de,0
        ld      b,SEEK_SET
        ld      a,(.fd)
        sys     SYS_LSEEK
        jp      c,.x11
        ld      a,(.fd)
        ld      hl,U_P1
        ld      bc,512
        sys     SYS_WRITE
        jp      c,.x11
        ld      de,512
        or      a
        sbc     hl,de
        jp      nz,.x11
        ld      hl,512
        ld      de,0
        ld      b,SEEK_SET
        ld      a,(.fd)
        sys     SYS_LSEEK
        jp      c,.x12
        ld      hl,U_P1+1000h
        ld      bc,512
        call    .read
        jp      c,.x12
        ld      de,512
        or      a
        sbc     hl,de
        jp      nz,.x12
        ld      hl,U_P1+1000h
        ld      bc,512
        ld      de,512
        call    .verify
        jp      nz,.x12
        ld      a,(.fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_END
        sys     SYS_LSEEK
        jp      c,.x13
        ld      a,d
        or      e
        jp      nz,.x13
        ld      de,1024
        or      a
        sbc     hl,de
        jp      nz,.x13
        ld      a,(.fd)
        sys     SYS_CLOSE
        xor     a
        sys     SYS_EXIT
.x1:    ld      a,1
        sys     SYS_EXIT
.x2:    ld      a,2
        sys     SYS_EXIT
.x3:    ld      a,3
        sys     SYS_EXIT
.x4:    ld      a,4
        sys     SYS_EXIT
.x5:    ld      a,5
        sys     SYS_EXIT
.x6:    ld      a,6
        sys     SYS_EXIT
.x7:    ld      a,7
        sys     SYS_EXIT
.x8:    ld      a,8
        sys     SYS_EXIT
.x9:    ld      a,9
        sys     SYS_EXIT
.x10:   ld      a,10
        sys     SYS_EXIT
.x11:   ld      a,11
        sys     SYS_EXIT
.x12:   ld      a,12
        sys     SYS_EXIT
.x13:   ld      a,13
        sys     SYS_EXIT
; .read — HL = buffer, BC = length: read on .fd. Out as SYS_READ.
.read:  ld      a,(.fd)
        sys     SYS_READ
        ret
; .rewind — .fd's position to 0.
.rewind:
        ld      a,(.fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        ret
; .count0 / .delta — the driver calls since .count0, in HL.
.count0:
        ld      hl,(K_BLK_CALLS)
        ld      (.calls),hl
        ret
.delta: ld      hl,(K_BLK_CALLS)
        ld      de,(.calls)
        or      a
        sbc     hl,de
        ret
; .fill — BC bytes at HL with the pattern from offset DE: byte i =
; (i ^ (i >> 8)) & FFh.
.fill:  ld      a,e
        xor     d
        ld      (hl),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.fill
        ret
; .verify — HL -> BC bytes that came from offset DE: Z if every byte is
; the pattern's.
.verify:
        ld      a,e
        xor     d
        cp      (hl)
        ret     nz
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.verify
        ret
.big:   db      "/data/big.bin",0
.frag1: db      "/frag1",0
.frag2: db      "/frag2",0
.badlink: db    "/mnt/c/badlink.bin",0
.farr:  db      "/mnt/c/farr.bin",0
.far:   db      "/mnt/c/far.bin",0
.fd:    db      0
.fd2:   db      0
.calls: dw      0
        m6_proglib
