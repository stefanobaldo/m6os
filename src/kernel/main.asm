; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; k_main — the boot sequence, once the loader has jumped here with the
; record filled: the interrupt vector, the console — the VDP programmed
; for 80 columns — the keyboard, memory, the switched
; part of the kernel, the process table with the kernel as process 0, the
; loader's memory released, the storage enumerated and listed and the
; cache emptied, the summary of the memory printed from the switched
; part. Then, if the record names an address, jump there — a
; program in the loader's page 1, which sched_release_boot kept as
; process 0's, so it runs as process 0 where it lies — else halt with
; interrupts on, so the tick keeps counting for anyone watching it.

k_main:
        call    k_irq_init
        ei
        call    con_init
        call    kbd_init
        ld      hl,K_REC+KR_SEG64K      ; what is in each page now
        ld      de,k_map
        ld      bc,4
        ldir
        call    mem_init
        jp      nz,k_boot_fail
        call    kwin_load
        jp      nz,k_boot_fail
        call    sched_init
        call    sched_release_boot
        ld      a,(K_KSEG)
        or      a
        jr      z,.nosummary            ; no switched part: no summary,
        kwin_call_s KS_BLK_INIT         ; no storage
        kwin_call_s KS_CACHE_INIT
        ld      a,(K_BLK_ROOT)          ; process 0 starts in /
        ld      (K_PROC+P_CWD),a
        kwin_call KS_SUMMARY
.nosummary:
        ld      hl,(K_REC+KR_TEST)
        ld      a,h
        or      l
        jr      z,k_init
        jp      (hl)

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

; k_boot_fail — A = code; C = the slot the code is about, for F8.
k_boot_fail:
        push    bc
        push    af
        ld      hl,s_bootfail
        call    con_puts
        pop     af
        push    af
        call    con_hex8
        pop     af
        pop     bc
        cp      0F8h
        jr      nz,.nl
        ld      hl,s_bootslot
        call    con_puts
        ld      a,c
        call    con_hex8
.nl:    call    con_newline
        m6_verdict M6_FAIL
        jr      k_halt

s_bootfail: db  "FAIL boot code ",0
s_bootslot: db  " slot ",0
