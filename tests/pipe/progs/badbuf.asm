; badbuf — asks the kernel to read into page 3, where the kernel is, on a
; file, on a pipe, with procinfo and on the keyboard in both of the
; terminal's modes, and expects EFAULT each time — before a key is waited
; for; exits 0, or 1 to 5 naming the call that did not refuse.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      hl,p_file
        xor     a
        sys     SYS_OPEN
        jr      c,.e1
        ld      hl,0BFF0h               ; 16 bytes before page 3, 100 asked
        ld      bc,100
        sys     SYS_READ
        jr      nc,.e1
        cp      E_FAULT
        jr      nz,.e1
        sys     SYS_PIPE
        jr      c,.e2
        ld      a,l
        ld      hl,0C000h
        ld      bc,1
        sys     SYS_READ
        jr      nc,.e2
        cp      E_FAULT
        jr      nz,.e2
        xor     a
        ld      hl,0BFF0h
        sys     SYS_PROCINFO
        jr      nc,.e3
        cp      E_FAULT
        jr      nz,.e3
        xor     a                       ; the keyboard, canonical
        ld      hl,0BFF0h
        ld      bc,100
        sys     SYS_READ
        jr      nc,.e4
        cp      E_FAULT
        jr      nz,.e4
        ld      a,TTY_RAW               ; and raw
        sys     SYS_TTYMODE
        xor     a
        ld      hl,0C000h
        ld      bc,1
        sys     SYS_READ
        push    af
        ld      a,TTY_CANON
        sys     SYS_TTYMODE
        pop     af
        jr      nc,.e5
        cp      E_FAULT
        jr      nz,.e5
        xor     a
        sys     SYS_EXIT
.e1:    ld      a,1
        sys     SYS_EXIT
.e2:    ld      a,2
        sys     SYS_EXIT
.e3:    ld      a,3
        sys     SYS_EXIT
.e4:    ld      a,4
        sys     SYS_EXIT
.e5:    ld      a,5
        sys     SYS_EXIT
p_file: db      "/notm6.bin",0
