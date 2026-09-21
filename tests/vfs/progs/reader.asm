; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; reader — the vfs test's reading process, three pages, started from the
; volume with spawnv: what it does is in the comment below, as it was
; when it lived inside the test's block.
        include "kernel/kernel.inc"
        include "m6prog.inc"
; u_reader — three pages: /data/big.bin read whole through 4K reads into a
; 256-aligned buffer in page 0 (the direct path; the driver calls counted
; on the second pass, which the harness times), 4K into page 2 (the direct
; path through a page the window takes), 4K into an unaligned buffer (the
; copy path), pieces of 1, 3, 511, 513, 1000 and 3000 bytes (across a
; cluster), then seeks: near the end, to the end, past it, negative, back,
; relative. Every byte against the pattern. Exits with 0, or the number of
; the check that failed.
U_BUF0      equ 1000h           ; page 0, 256-aligned
U_BUF2      equ 8000h           ; page 2
U_BUFU      equ 1001h           ; unaligned
        m6_header 3
start:
        ld      hl,.path
        xor     a
        sys     SYS_OPEN
        jp      c,.x1
        ld      (.fd),a
        ; Pass 1: the whole file, 4K at a time, verified.
        call    .whole
        jp      nz,.x2
        ; Pass 2: rewind, and the sixteen reads alone, timed, the driver
        ; calls counted: 128 sectors, 128 calls, the FAT already cached.
        ; Nothing is verified here — pass 1 did — so the ticks are the
        ; reads' and not the compare's.
        call    .rewind
        ld      hl,(K_BLK_CALLS)
        ld      (.calls),hl
        ld      hl,(K_TICKS)
        ld      (.t0),hl
        ld      b,16
.timed: push    bc
        ld      a,(.fd)
        ld      hl,U_BUF0
        ld      bc,4096
        sys     SYS_READ
        pop     bc
        jp      c,.x2
        ld      de,4096
        or      a
        sbc     hl,de
        jp      nz,.x2
        djnz    .timed
        ld      hl,(K_TICKS)
        ld      de,(.t0)
        or      a
        sbc     hl,de
        push    hl
        m6_puts .s_ticks
        pop     hl
        call    m6_dec16
        m6_puts .s_ticks2
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
        ld      de,128
        or      a
        sbc     hl,de
        jp      nz,.x4
        ; Pass 3: 4K into page 2.
        call    .rewind
        ld      a,(.fd)
        ld      hl,U_BUF2
        ld      bc,4096
        sys     SYS_READ
        jp      c,.x5
        ld      hl,U_BUF2
        ld      bc,4096
        ld      de,0
        call    .verify
        jp      nz,.x5
        ; Pass 4: 4K into an unaligned buffer.
        call    .rewind
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,4096
        sys     SYS_READ
        jp      c,.x6
        ld      hl,U_BUFU
        ld      bc,4096
        ld      de,0
        call    .verify
        jp      nz,.x6
        ; Pass 5: odd pieces, across a cluster.
        call    .rewind
        ld      hl,0
        ld      (.off),hl
        ld      hl,.sizes
        ld      (.szp),hl               ; the cursor in memory: a syscall
.odd:   ld      hl,(.szp)               ; keeps no register but the result
        ld      c,(hl)
        inc     hl
        ld      b,(hl)
        inc     hl
        ld      (.szp),hl
        ld      a,b
        or      c
        jr      z,.odddone
        push    bc
        ld      a,(.fd)
        ld      hl,U_BUFU
        sys     SYS_READ
        pop     bc
        jp      c,.x7
        or      a
        sbc     hl,bc
        jp      nz,.x8                  ; a short read
        push    bc
        ld      hl,U_BUFU
        ld      de,(.off)
        call    .verify
        pop     bc
        jp      nz,.x7
        ld      hl,(.off)
        add     hl,bc
        ld      (.off),hl
        jr      .odd
.odddone:
        ; Pass 6: seeks.
        ld      a,(.fd)
        ld      hl,65536-100
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,.x9
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,200
        sys     SYS_READ
        jp      c,.x9
        ld      de,100
        or      a
        sbc     hl,de
        jp      nz,.x9                  ; 100 left, not 200
        ld      hl,U_BUFU
        ld      bc,100
        ld      de,65536-100
        call    .verify
        jp      nz,.x9
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,100
        sys     SYS_READ
        jp      c,.x9
        ld      a,h
        or      l
        jp      nz,.x9                  ; the end: 0
        ld      a,(.fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_END
        sys     SYS_LSEEK
        jp      c,.x12
        ld      a,h
        or      l
        jp      nz,.x12                 ; 65536 = 0001:0000
        ld      a,e
        dec     a
        or      d
        jp      nz,.x12
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,100
        sys     SYS_READ
        jp      c,.x12
        ld      a,h
        or      l
        jp      nz,.x12
        ld      a,(.fd)
        ld      hl,70000 & 0FFFFh
        ld      de,70000 >> 16
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,.x9
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,100
        sys     SYS_READ
        jp      c,.x9
        ld      a,h
        or      l
        jp      nz,.x9                  ; past the end: 0
        ld      a,(.fd)
        ld      hl,0FFFFh
        ld      de,0FFFFh
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      nc,.x10
        cp      E_INVAL
        jp      nz,.x10
        ld      a,(.fd)
        ld      hl,12345
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        jp      c,.x11
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,1000
        sys     SYS_READ
        jp      c,.x11
        ld      hl,U_BUFU
        ld      bc,1000
        ld      de,12345
        call    .verify
        jp      nz,.x11
        ld      a,(.fd)
        ld      hl,-100
        ld      de,-1
        ld      b,SEEK_CUR
        sys     SYS_LSEEK
        jp      c,.x11
        ld      de,13245
        or      a
        sbc     hl,de
        jp      nz,.x11
        ld      a,(.fd)
        ld      hl,U_BUFU
        ld      bc,100
        sys     SYS_READ
        jp      c,.x11
        ld      hl,U_BUFU
        ld      bc,100
        ld      de,13245
        call    .verify
        jp      nz,.x11
        ld      a,(.fd)
        sys     SYS_CLOSE
        jp      c,.x13
        xor     a
        sys     SYS_EXIT
.x1:    ld      a,1
        sys     SYS_EXIT
.x2:    m6_puts .s_at
        ld      hl,(.off)
        call    m6_dec16
        m6_puts .s_got
        ld      hl,(.cnt)
        call    m6_dec16
        m6_puts .s_byte
        ld      hl,(.bad)
        call    m6_dec16
        m6_puts .s_is
        ld      a,(.badb)
        ld      l,a
        ld      h,0
        call    m6_dec16
        m6_puts .s_nl
        ld      a,2
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
; .whole — the file from its position, 4K at a time into U_BUF0, verified:
; Z if every byte was right and 65536 were read.
.whole: ld      hl,0
        ld      (.off),hl
.chunk: ld      a,(.fd)
        ld      hl,U_BUF0
        ld      bc,4096
        sys     SYS_READ
        jr      c,.wbad
        ld      (.cnt),hl
        ld      de,4096
        or      a
        sbc     hl,de
        jr      nz,.wbad                ; short
        ld      hl,U_BUF0
        ld      bc,4096
        ld      de,(.off)
        call    .verify
        ret     nz
        ld      hl,(.off)
        ld      de,4096
        add     hl,de
        ld      (.off),hl
        jr      nc,.chunk               ; 16 chunks: wraps to 0 at the end
        xor     a
        ret
.wbad:  or      1
        ret
; .rewind — the position to 0.
.rewind:
        ld      a,(.fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        ret
; .verify — HL -> BC bytes that came from offset DE of the file: Z if
; every byte is (offset ^ (offset >> 8)) & FFh; else NZ with .bad = the
; offset and .badb = the byte found.
.verify:
        ld      a,e
        xor     d
        cp      (hl)
        jr      z,.same
        ld      (.bad),de
        ld      a,(hl)
        ld      (.badb),a
        or      1
        ret
.same:
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.verify
        ret
.path:  db      "/data/big.bin",0
.s_ticks: db    "reader: 64K in ",0
.s_ticks2: db   " ticks",10,0
.s_calls: db    "reader: calls ",0
.s_nl:  db      10,0
.s_at:  db      "reader: chunk at ",0
.s_got: db      " got ",0
.s_byte: db     " bad byte at ",0
.s_is:  db      " is ",0
.sizes: dw      1,3,511,513,1000,3000,0
.fd:    db      0
.off:   dw      0
.szp:   dw      0
.cnt:   dw      0
.bad:   dw      0
.badb:  db      0
.t0:    dw      0
.calls: dw      0
        m6_proglib
