; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; mapper — the mapper support through EXTBIO, with the program's own
; pages: GET_P1 and GET_P2 name them; a pattern written into page 2's
; segment through WR_SEG comes back through RD_SEG and is seen at 8000h;
; PUT_P2 of page 1's segment shows page 1's bytes at 8000h and GET_P2
; answers it; the TPA's segment put back. Then ALL_SEG: a segment, freed
; again with FRE_SEG, or the carry the 128K machine gives with nothing
; free. "mapper ok seg" or "mapper ok noseg", or the step that failed.
        include "dos/progs/dos.inc"
        org     100h
        ld      a,1
        ld      (step),a
        xor     a
        ld      de,0402h
        call    EXTBIO
        or      a
        jp      z,fail                  ; no mapper support
        ld      (tab),hl
        ld      de,3
        ld      (m_all+1),hl
        add     hl,de
        ld      (m_fre+1),hl
        add     hl,de
        ld      (m_rd+1),hl
        add     hl,de
        ld      (m_wr+1),hl
        ld      hl,(tab)
        ld      de,21h
        add     hl,de
        ld      (m_g1+1),hl
        ld      de,3
        add     hl,de
        ld      (m_p2+1),hl
        add     hl,de
        ld      (m_g2+1),hl
        ; 2: the program's own segments
        ld      a,2
        ld      (step),a
        call    m_g1
        ld      (s1),a
        call    m_g2
        ld      (s2),a
        ld      hl,s1                   ; the two must differ
        cp      (hl)
        jp      z,fail
        ; 3: WR_SEG the pattern i at i in page 2's segment, RD_SEG it
        ; back, and see it at 8000h
        ld      a,3
        ld      (step),a
        ld      hl,0
.wr:    ld      a,(s2)
        ld      e,l
        call    m_wr
        inc     l
        jr      nz,.wr
        ld      hl,0
.rd:    ld      a,(s2)
        call    m_rd
        cp      l
        jp      nz,fail
        inc     l
        jr      nz,.rd
        ld      hl,8000h
.see:   ld      a,(hl)
        cp      l
        jp      nz,fail
        inc     l
        jr      nz,.see
        ; 4: page 1's first bytes marked, PUT_P2 of its segment, seen at
        ; 8000h; GET_P2 answers it; the TPA's page 2 back
        ld      a,4
        ld      (step),a
        ld      hl,4000h
        ld      (hl),'m'
        inc     hl
        ld      (hl),'6'
        ld      a,(s1)
        call    m_p2
        ld      hl,8000h
        ld      a,(hl)
        cp      'm'
        jp      nz,fail
        inc     hl
        ld      a,(hl)
        cp      '6'
        jp      nz,fail
        call    m_g2
        ld      hl,s1
        cp      (hl)
        jp      nz,fail
        ld      a,(s2)
        call    m_p2
        ld      hl,8000h
        ld      a,(hl)
        or      a                       ; the pattern's 0 is back
        jp      nz,fail
        ; 5: a segment, if the machine has one to give
        ld      a,5
        ld      (step),a
        xor     a
        ld      b,0
        call    m_all
        jr      c,.noseg
        call    m_fre
        jp      c,fail
        d_puts  s_ok
        d_puts  s_seg
        jp      done
.noseg: d_puts  s_ok
        d_puts  s_noseg
        jp      done
fail:   d_puts  s_fail
        ld      a,(step)
        ld      l,a
        ld      h,0
        call    d_dec16
        d_puts  s_crlf
done:   ld      c,_TERM0
        call    BDOS
m_all:  jp      0
m_fre:  jp      0
m_rd:   jp      0
m_wr:   jp      0
m_g1:   jp      0
m_p2:   jp      0
m_g2:   jp      0
        d_declib
s_ok:   db      "mapper ok $"
s_seg:  db      "seg",13,10,"$"
s_noseg: db     "noseg",13,10,"$"
s_fail: db      "mapper FAIL $"
s_crlf: db      13,10,"$"
step:   db      0
s1:     db      0
s2:     db      0
tab:    dw      0
