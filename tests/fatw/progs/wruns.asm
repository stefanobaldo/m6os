; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; wruns — the fatw test's write-run process, three pages (the code in
; page 0, a 16K buffer filling page 1, the stack in page 2): what a run of
; sectors written in one call leaves on the volume and in the cache, on
; the boot volume (4K clusters). The driver calls are counted through
; K_BLK_CALLS around each write alone.
;   (a) /tmp/wr1 and /tmp/wr2 written 4K at a time, alternating, twice
;       each, so that each takes every other cluster; then 16K more to
;       /tmp/wr1 from page 1: four clusters allocated after its tail,
;       contiguous — one data call, the table's two copies, the entry: 4;
;   (b) /tmp/wr1 rewritten from 0, 16K from page 1 with the pattern
;       inverted, over its two fragments and the first two clusters of
;       the stretch — three data calls and the entry: 4 — and read back
;       whole, 24K;
;   (c) 512 bytes read unaligned from /tmp/wr1's start, so that the cache
;       holds its first sector; 4K written direct over it with the plain
;       pattern again; the same 512 read unaligned: the new bytes.
; Both files removed. Exits with 0, or the number of the check that
; failed.
        include "kernel/kernel.inc"
        include "m6prog.inc"
U_P1        equ 4000h           ; page 1, 16K
U_BUFU      equ 2001h           ; unaligned: the copy path
        m6_header 3
start:
        ; (a)
        ld      hl,.wr1
        ld      a,O_CREAT|O_WRONLY
        sys     SYS_OPEN
        jp      c,.x1
        ld      (.fd),a
        ld      hl,.wr2
        ld      a,O_CREAT|O_WRONLY
        sys     SYS_OPEN
        jp      c,.x1
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
        jp      c,.x1
        ld      a,(.fd2)
        ld      hl,U_P1
        ld      bc,4096
        sys     SYS_WRITE
        jp      c,.x1
        pop     de
        ld      hl,4096
        add     hl,de
        ex      de,hl
        ld      a,d
        cp      20h
        jr      nz,.alt                 ; 2 x 4K each
        ld      a,(.fd2)
        sys     SYS_CLOSE
        ld      hl,U_P1
        ld      bc,16384
        ld      de,8192
        call    .fill
        call    .count0
        ld      a,(.fd)
        ld      hl,U_P1
        ld      bc,16384
        sys     SYS_WRITE
        jp      c,.x2
        ld      de,16384
        or      a
        sbc     hl,de
        jp      nz,.x2
        call    .delta
        ld      de,4
        or      a
        sbc     hl,de
        jp      nz,.x2
        ld      a,(.fd)
        sys     SYS_CLOSE
        ; (b)
        ld      hl,.wr1
        ld      a,O_RDWR
        sys     SYS_OPEN
        jp      c,.x3
        ld      (.fd),a
        ld      a,0FFh
        ld      (.mask),a
        ld      hl,U_P1
        ld      bc,16384
        ld      de,0
        call    .fill
        call    .count0
        ld      a,(.fd)
        ld      hl,U_P1
        ld      bc,16384
        sys     SYS_WRITE
        jp      c,.x3
        ld      de,16384
        or      a
        sbc     hl,de
        jp      nz,.x3
        call    .delta
        ld      de,4
        or      a
        sbc     hl,de
        jp      nz,.x3
        ; Read back: 16K inverted, then 8K plain.
        call    .rewind
        ld      a,(.fd)
        ld      hl,U_P1
        ld      bc,16384
        sys     SYS_READ
        jp      c,.x4
        ld      de,16384
        or      a
        sbc     hl,de
        jp      nz,.x4
        ld      hl,U_P1
        ld      bc,16384
        ld      de,0
        call    .verify
        jp      nz,.x4
        xor     a
        ld      (.mask),a
        ld      a,(.fd)
        ld      hl,U_P1
        ld      bc,8192
        sys     SYS_READ
        jp      c,.x4
        ld      de,8192
        or      a
        sbc     hl,de
        jp      nz,.x4
        ld      hl,U_P1
        ld      bc,8192
        ld      de,16384
        call    .verify
        jp      nz,.x4
        ; (c)
        call    .rewind
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,512
        sys     SYS_READ                ; the first sector into the cache
        jp      c,.x5
        ld      de,512
        or      a
        sbc     hl,de
        jp      nz,.x5
        ld      a,0FFh
        ld      (.mask),a
        ld      hl,U_BUFU
        ld      bc,512
        ld      de,0
        call    .verify                 ; still the inverted bytes
        jp      nz,.x5
        call    .rewind
        xor     a
        ld      (.mask),a
        ld      hl,U_P1
        ld      bc,4096
        ld      de,0
        call    .fill
        ld      a,(.fd)
        ld      hl,U_P1
        ld      bc,4096
        sys     SYS_WRITE               ; direct, over the cached sector
        jp      c,.x5
        call    .rewind
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,512
        sys     SYS_READ                ; through the cache again
        jp      c,.x6
        ld      de,512
        or      a
        sbc     hl,de
        jp      nz,.x6
        ld      hl,U_BUFU
        ld      bc,512
        ld      de,0
        call    .verify                 ; the plain bytes, not the cached
        jp      nz,.x6
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      hl,.wr1
        sys     SYS_UNLINK
        jp      c,.x7
        ld      hl,.wr2
        sys     SYS_UNLINK
        jp      c,.x7
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
; .fill — BC bytes at HL with the pattern from offset DE, xor .mask:
; byte i = ((i ^ (i >> 8)) & FFh) ^ mask.
.fill:  ld      a,e
        xor     d
        push    hl
        ld      hl,.mask
        xor     (hl)
        pop     hl
        ld      (hl),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.fill
        ret
; .verify — HL -> BC bytes that came from offset DE: Z if every byte is
; the pattern's, xor .mask.
.verify:
        ld      a,e
        xor     d
        push    hl
        ld      hl,.mask
        xor     (hl)
        pop     hl
        cp      (hl)
        ret     nz
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.verify
        ret
.wr1:   db      "/tmp/wr1",0
.wr2:   db      "/tmp/wr2",0
.fd:    db      0
.fd2:   db      0
.mask:  db      0
.calls: dw      0
        m6_proglib
