; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The index of the layer's messages (bin/dos.asm): a code and where its
; message is in the file, ending in 0. Inside the header's jump, at
; LEG_MSGIX of the file.
leg_msgix:
        db      D_STOP
        dw      m_stop-P0_PROG
        db      D_CTRLC
        dw      m_ctrlc-P0_PROG
        db      D_ABORT
        dw      m_abort-P0_PROG
        db      D_IBDOS
        dw      m_ibdos-P0_PROG
        db      D_ISBFN
        dw      m_isbfn-P0_PROG
        db      D_IPARM
        dw      m_iparm-P0_PROG
        db      D_INTER
        dw      m_inter-P0_PROG
        db      D_NORAM
        dw      m_noram-P0_PROG
        db      D_IDRV
        dw      m_idrv-P0_PROG
        db      D_IFNM
        dw      m_ifnm-P0_PROG
        db      D_IPATH
        dw      m_ipath-P0_PROG
        db      D_PLONG
        dw      m_plong-P0_PROG
        db      D_NOFIL
        dw      m_nofil-P0_PROG
        db      D_NODIR
        dw      m_nodir-P0_PROG
        db      D_DRFUL
        dw      m_drful-P0_PROG
        db      D_DKFUL
        dw      m_dkful-P0_PROG
        db      D_DUPF
        dw      m_dupf-P0_PROG
        db      D_DIRE
        dw      m_dire-P0_PROG
        db      D_FILRO
        dw      m_filro-P0_PROG
        db      D_DIRNE
        dw      m_dirne-P0_PROG
        db      D_IATTR
        dw      m_iattr-P0_PROG
        db      D_DOT
        dw      m_dot-P0_PROG
        db      D_SYSX
        dw      m_sysx-P0_PROG
        db      D_DIRX
        dw      m_dirx-P0_PROG
        db      D_FILEX
        dw      m_filex-P0_PROG
        db      D_FOPEN
        dw      m_fopen-P0_PROG
        db      D_EOF
        dw      m_eof-P0_PROG
        db      D_ACCV
        dw      m_accv-P0_PROG
        db      D_IPROC
        dw      m_iproc-P0_PROG
        db      D_NHAND
        dw      m_nhand-P0_PROG
        db      D_IHAND
        dw      m_ihand-P0_PROG
        db      D_IDEV
        dw      m_idev-P0_PROG
        db      D_IENV
        dw      m_ienv-P0_PROG
        db      D_ELONG
        dw      m_elong-P0_PROG
        db      D_HDEAD
        dw      m_hdead-P0_PROG
        db      D_DISK
        dw      m_disk-P0_PROG
        db      D_WPROT
        dw      m_wprot-P0_PROG
        db      0
