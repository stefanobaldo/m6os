; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; k_init — process 0 as init, when no test program was named: /etc/rc,
; if there is one, run by the shell with the file as its descriptor 0
; and waited for; then a login shell, waited for and started again when
; it exits. Process 0 keeps no pages of its own: spawnv writes the
; child's segments and reads the vector and the descriptor map from
; here, in page 3, which the range checks allow it alone. A shell that
; will not start is reported and the machine halts. Without the switched
; part there is no storage and no shell: the halt of before.
k_init:
        ld      a,(K_KSEG)
        or      a
        jp      z,k_halt
        ld      hl,s_rc
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      c,.login
        ld      (i_fds),a
        ld      hl,s_sh
        ld      de,v_rc
        ld      bc,i_fds
        xor     a
        sys     SYS_SPAWNV
        jr      c,.fail
        push    hl                      ; l = the pid
        ld      a,(i_fds)
        sys     SYS_CLOSE
        pop     hl
        ld      a,l
        ld      b,0
        sys     SYS_WAITPID
.login: ld      hl,s_sh
        ld      de,v_login
        ld      bc,i_inh
        xor     a
        sys     SYS_SPAWNV
        jr      c,.fail
        ld      b,0
        sys     SYS_WAITPID
        jr      .login
.fail:  push    af
        ld      hl,s_initfail
        call    con_puts
        pop     af
        ld      l,a
        ld      h,0
        call    con_dec16
        call    con_newline
        jr      k_halt

s_rc:       db  "/etc/rc",0
s_sh:       db  "/bin/sh",0
s_sh0:      db  "sh",0
s_dashi:    db  "-i",0
s_initfail: db  "init: /bin/sh: error ",0
v_rc:       dw  s_sh0,0
v_login:    dw  s_sh0,s_dashi,0
i_fds:      db  0,0FFh,0FFh             ; /etc/rc, the console, the console
i_inh:      db  0FFh,0FFh,0FFh

; k_halt — nothing left to do.
k_halt:
        ei
        halt
        jr      k_halt
