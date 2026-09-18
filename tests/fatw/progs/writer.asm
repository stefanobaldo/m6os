; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; writer — the fatw test's writing process, three pages, started from the
; volume with spawnv: what it does is in the comment below, as it was
; when it lived inside the test's block.
        include "kernel/kernel.inc"
        include "m6prog.inc"
O_CW        equ O_CREAT|O_WRONLY
; u_writer — three pages. (a) /mnt/d/big.bin on the FAT16 slave: 64K of
; the pattern in four 16K writes from page 1, timed, the driver calls
; counted — 32 data + 2 table + 1 entry per write, plus the table sector's
; first read: 141 — then read back through page 0 and compared. (b)
; /tmp/b4k.bin: the same in 4K writes from page 0, timed. (c)
; /tmp/b1000.bin: the same in 1000-byte writes from an unaligned buffer.
; (d) b4k.bin reopened O_RDWR: 3000 bytes at 30000 inverted, the whole read
; back. Exits with 0, or the number of the check that failed.
U_BUF0      equ 1000h           ; page 0, 256-aligned, 4K
U_BUFU      equ 2001h           ; unaligned, 3000 bytes
U_PAGE1     equ 4000h           ; page 1, 16K
        m6_header 3
start:
        ; (a)
        ld      hl,.big
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,.x1
        ld      (.fd),a
        ld      hl,(K_BLK_CALLS)
        ld      (.calls),hl
        ld      hl,0
        ld      (.t0),hl                ; the ticks of the calls alone
        ld      de,0                    ; the offset of the chunk
.w16:   push    de
        ld      hl,U_PAGE1
        ld      bc,16384
        call    .fill
        pop     de
        push    de
        ld      hl,(K_TICKS)
        push    hl
        ld      a,(.fd)
        ld      hl,U_PAGE1
        ld      bc,16384
        sys     SYS_WRITE
        call    .tick
        pop     de
        jp      c,.x2
        ld      bc,16384
        or      a
        sbc     hl,bc
        jp      nz,.x2
        ex      de,hl
        add     hl,bc
        ex      de,hl
        ld      a,d
        or      e
        jr      nz,.w16                 ; four chunks: wraps to 0
        ld      hl,(.t0)
        push    hl
        m6_puts .s_ticks
        pop     hl
        call    m6_dec16
        m6_puts .s_nl
        ld      hl,(K_BLK_CALLS)
        ld      de,(.calls)
        or      a
        sbc     hl,de
        push    hl
        m6_puts .s_calls
        pop     hl
        push    hl
        call    m6_dec16
        m6_puts .s_nl
        pop     hl
        ld      de,141
        or      a
        sbc     hl,de
        jp      nz,.x3
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      hl,.big
        call    .readback
        jp      nz,.x4
        ; (b)
        ld      hl,.b4k
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,.x5
        ld      (.fd),a
        ld      hl,0
        ld      (.t0),hl
        ld      de,0
.w4k:   push    de
        ld      hl,U_BUF0
        ld      bc,4096
        call    .fill
        pop     de
        push    de
        ld      hl,(K_TICKS)
        push    hl
        ld      a,(.fd)
        ld      hl,U_BUF0
        ld      bc,4096
        sys     SYS_WRITE
        call    .tick
        pop     de
        jp      c,.x5
        ld      bc,4096
        or      a
        sbc     hl,bc
        jp      nz,.x5
        ex      de,hl
        add     hl,bc
        ex      de,hl
        ld      a,d
        or      e
        jr      nz,.w4k
        ld      hl,(.t0)
        push    hl
        m6_puts .s_ticks4
        pop     hl
        call    m6_dec16
        m6_puts .s_nl
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      hl,.b4k
        call    .readback
        jp      nz,.x6
        ; (c)
        ld      hl,.b1000
        ld      a,O_CW
        sys     SYS_OPEN
        jp      c,.x7
        ld      (.fd),a
        ld      hl,0
        ld      (.t0),hl
        ld      de,0
.w1000: push    de
        ld      hl,65536-536            ; the last piece is 536
        or      a
        sbc     hl,de
        ld      bc,1000
        jr      nz,.piece
        ld      bc,536
.piece: ld      (.len),bc
        ld      hl,U_BUFU
        call    .fill
        pop     de
        push    de
        ld      hl,(K_TICKS)
        push    hl
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,(.len)
        sys     SYS_WRITE
        call    .tick
        pop     de
        jp      c,.x7
        ld      bc,(.len)
        or      a
        sbc     hl,bc
        jp      nz,.x7
        ex      de,hl
        add     hl,bc
        ex      de,hl
        ld      a,d
        or      e
        jr      nz,.w1000
        ld      hl,(.t0)
        push    hl
        m6_puts .s_ticks1000
        pop     hl
        call    m6_dec16
        m6_puts .s_nl
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      hl,.b1000
        call    .readback
        jp      nz,.x8
        ; (d)
        ld      hl,.b4k
        ld      a,O_RDWR
        sys     SYS_OPEN
        jp      c,.x9
        ld      (.fd),a
        ld      hl,30000
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,.x9
        ld      hl,U_BUFU
        ld      de,30000
        ld      bc,3000
        call    .fill
        ld      hl,U_BUFU
        ld      bc,3000
.inv:   ld      a,(hl)
        cpl
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,.inv
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,3000
        sys     SYS_WRITE
        jp      c,.x9
        ld      a,(.fd)
        sys     SYS_CLOSE
        ld      a,1
        ld      (.inverted),a
        ld      hl,.b4k
        call    .readback
        jp      nz,.x10
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
; .tick — after a write whose starting ticks are on the stack under the
; return address: .t0 += the ticks it took. Preserves AF (the result) and
; HL.
.tick:  pop     bc                      ; the return address
        pop     de                      ; the ticks before
        push    bc
        push    af
        push    hl
        ld      hl,(K_TICKS)
        or      a
        sbc     hl,de
        ld      de,(.t0)
        add     hl,de
        ld      (.t0),hl
        pop     hl
        pop     af
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
; .readback — HL = a path: the file read whole in 4K pieces into U_BUF0 and
; compared with the pattern (.inverted: bytes 30000..32999 inverted). Z if
; every byte is right and 65536 came; the first wrong offset in .bad.
.readback:
        xor     a
        sys     SYS_OPEN
        jr      c,.rbad
        ld      (.fd),a
        ld      de,0
.rchunk:
        push    de
        ld      a,(.fd)
        ld      hl,U_BUF0
        ld      bc,4096
        sys     SYS_READ
        pop     de
        jr      c,.rbad
        ld      bc,4096
        or      a
        sbc     hl,bc
        jr      nz,.rbad                ; short
        ld      hl,U_BUF0
.rbyte: ld      a,e
        xor     d
        ld      c,a
        ld      a,(.inverted)
        or      a
        jr      z,.plain
        push    hl
        ld      hl,30000
        or      a
        sbc     hl,de
        pop     hl
        jr      z,.flip
        jr      nc,.plain               ; below 30000
        push    hl
        ld      hl,33000
        or      a
        sbc     hl,de
        pop     hl
        jr      z,.plain
        jr      c,.plain                ; at or past 33000
.flip:  ld      a,c
        cpl
        ld      c,a
.plain: ld      a,(hl)
        cp      c
        jr      nz,.rdiff
        inc     hl
        inc     de
        ld      a,l
        or      a
        jr      nz,.rbyte
        ld      a,h
        cp      high (U_BUF0+4096)
        jr      nz,.rbyte
        ld      a,d
        or      e
        jr      nz,.rchunk              ; 16 pieces: wraps to 0
        ld      a,(.fd)
        sys     SYS_CLOSE
        xor     a
        ret
.rdiff: ld      (.bad),de
        m6_puts .s_at
        ld      hl,(.bad)
        call    m6_dec16
        m6_puts .s_nl
.rbad:  ld      a,(.fd)
        sys     SYS_CLOSE
        or      1
        ret
.big:   db      "/mnt/d/big.bin",0
.b4k:   db      "/tmp/b4k.bin",0
.b1000: db      "/tmp/b1000.bin",0
.s_ticks: db    "writer: 64K/16K in ",0
.s_ticks4: db   "writer: 64K/4K in ",0
.s_ticks1000: db "writer: 64K/1000 in ",0
.s_calls: db    "writer: calls ",0
.s_at:  db      "writer: bad byte at ",0
.s_nl:  db      10,0
.fd:    db      0
.t0:    dw      0
.calls: dw      0
.len:   dw      0
.bad:   dw      0
.inverted: db   0
        m6_proglib
