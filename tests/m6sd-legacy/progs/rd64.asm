; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; rd64 — the program the m6sd test spawns: it reads /BIG, 65 536 bytes,
; 4K at a time into a buffer on a 256-byte boundary — whole sectors,
; straight from the driver into this page — and checks one byte in
; every 256 against the file's pattern (byte i = (i ^ (i >> 8)) & 0xFF;
; the test's own step compares every byte the driver moves, and a loop
; over all of them here would be most of the figure the test prints),
; then ends with 0. A byte that differs ends it with 1, a failed call or
; a short file with 2.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      hl,s_file
        ld      a,O_RDONLY
        sys     SYS_OPEN
        jp      c,fail2
        ld      (fd),a
        ld      hl,0
        ld      (pos),hl
loop:   ld      a,(fd)
        ld      hl,buf
        ld      bc,4096
        sys     SYS_READ
        jp      c,fail2
        ld      a,h
        or      l
        jr      z,eof
        ld      bc,4096
        or      a
        sbc     hl,bc
        jp      nz,fail2                ; a short read
        ld      hl,buf
        ld      de,(pos)
.byte:  ld      a,d
        xor     e                       ; (i ^ (i >> 8)) & 0xFF, e = 0
        cp      (hl)
        jp      nz,fail1
        inc     h                       ; the next 256 bytes
        inc     d
        ld      a,d
        and     0Fh
        jr      nz,.byte                ; 4096 bytes: d's low nibble
        ld      (pos),de
        jr      loop
eof:    ld      hl,(pos)
        ld      a,h
        or      l                       ; 65 536 wraps to 0
        jp      nz,fail2
        xor     a
        sys     SYS_EXIT
fail1:  ld      a,1
        sys     SYS_EXIT
fail2:  ld      a,2
        sys     SYS_EXIT

s_file: db      "/BIG",0
fd:     db      0
pos:    dw      0
        align   256                     ; buf on a 256-byte boundary
buf:    ds      4096
