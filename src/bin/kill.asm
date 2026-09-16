; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; kill [-sig] pid... — the signal to each process: -2, -9, -13, -15, or
; -INT, -KILL, -PIPE, -TERM; SIGTERM without one. A pid the kernel
; refuses is reported — kill: 7: ESRCH — and the next follows.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   ld      a,SIGTERM
        ld      (sig),a
        call    arg_peek
        jr      c,usage
        ld      a,(hl)
        cp      '-'
        jr      nz,.pids
        call    arg_next
        inc     hl
        ld      a,(hl)
        cp      '0'
        jr      c,.name
        cp      '9'+1
        jr      nc,.name
        call    str_atoi
        jr      c,usage
        ld      a,(de)
        or      a
        jr      nz,usage
        ld      a,h
        or      a
        jr      nz,usage
        ld      a,l
        jr      .set
.name:  ld      (word),hl
        ld      de,s_sigs
.try:   ld      a,(de)
        or      a
        jr      z,usage                 ; the table's end: no such name
        ld      (sig),a
        inc     de
        ld      hl,(word)
        call    str_cmp                 ; de left after the name's 0
        jr      z,.pids
        jr      .try
.set:   ld      (sig),a
.pids:  call    arg_peek
        jr      c,usage                 ; no pid at all
.each:  call    arg_next
        jr      c,.done
        ld      (name),hl
        call    str_atoi
        jr      c,.bad
        ld      a,(de)
        or      a
        jr      nz,.bad
        ld      a,h
        or      a
        jr      nz,.bad
        ld      a,(sig)
        ld      b,a
        ld      a,l
        sys     SYS_KILL
        jr      nc,.each
.err:   ld      de,(name)
        call    err_file
        jr      .each
.bad:   ld      a,E_INVAL
        jr      .err
.done:  ld      a,(lib_status)
        ret
usage:  ld      de,s_usage
        jp      err_usage

s_sigs:  db     SIGINT,"INT",0
         db     SIGKILL,"KILL",0
         db     SIGPIPE,"PIPE",0
         db     SIGTERM,"TERM",0
         db     0
s_usage: db     "kill [-sig] pid...",0

        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     sig,1
        bss     word,2
        bss     name,2
