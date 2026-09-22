; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; mapper — the mapper support through EXTBIO, with the program's own
; pages: GET_P1 and GET_P2 name them; a pattern written into page 2's
; segment through WR_SEG comes back through RD_SEG and is seen at 8000h;
; PUT_P2 of page 1's segment shows page 1's bytes at 8000h and GET_P2
; answers it; the TPA's segment put back. Then ALL_SEG: a segment —
; asked for by slot, as a program that keeps a table of its segments
; asks, so the slot must come back in B for ENASLT to take — filled
; whole and read back, freed with FRE_SEG, and asked for again, which
; must answer the same one; IX and IY, which a program keeps its own
; things in, as they went, with a segment or without. EXTBIO must count
; one free first: on the 128K machine it is the shell's page, lent for
; the run, and the script goes on after this program only if the
; shell's bytes came back. "mapper ok seg", "mapper ok noseg" when a
; machine gives none, or the step that failed.
        include "dos/progs/dos.inc"
        org     100h
        ld      a,1
        ld      (step),a
        xor     a
        ld      de,0402h
        call    EXTBIO
        or      a
        jp      z,fail                  ; no mapper support
        ld      a,c
        or      a
        jp      z,fail                  ; no segment counted free
        ld      (tab),hl
        ld      a,b
        ld      (slot),a                ; the mapper's slot
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
        ; 5: a segment, if the machine has one to give: by the mapper's
        ; slot "or any other" (20h), which answers the slot in B; IX and
        ; IY come back as they went, whatever the answer
        ld      a,5
        ld      (step),a
        ld      ix,1234h
        ld      iy,5678h
        ld      a,(slot)
        and     8Fh
        or      20h
        ld      b,a
        xor     a
        call    m_all
        push    af
        call    regs
        pop     af
        jp      c,.noseg
        ld      (seg),a
        ld      a,6
        ld      (step),a
        ld      a,(slot)
        cp      b
        jp      nz,fail                 ; B is not the mapper's slot
        ; 10: all 16K of it the program's: a pattern written through
        ; page 2 and read back, the TPA's page 2 put back
        ld      a,10
        ld      (step),a
        ld      a,(seg)
        call    m_p2
        ld      hl,8000h
.fill:  ld      a,h
        xor     l
        ld      (hl),a
        inc     hl
        bit     6,h
        jr      z,.fill                 ; to C000h
        ld      hl,8000h
.chk:   ld      a,h
        xor     l
        cp      (hl)
        jp      nz,fail
        inc     hl
        bit     6,h
        jr      z,.chk
        ld      a,(s2)
        call    m_p2
        ld      a,7
        ld      (step),a
        ld      a,(seg)
        call    m_fre
        jp      c,fail
        call    regs
        ; 8: asked of the primary mapper with B = 0, B comes back 0
        ld      a,8
        ld      (step),a
        xor     a
        ld      b,a
        call    m_all
        jp      c,fail
        ld      c,a
        ld      a,b
        or      a
        jp      nz,fail
        ; 11: the segment step 7 freed, answered again
        ld      a,11
        ld      (step),a
        ld      a,(seg)
        cp      c
        jp      nz,fail
        call    m_fre
        jp      c,fail
        d_puts  s_ok
        d_puts  s_seg
        jp      done
.noseg: d_puts  s_ok
        d_puts  s_noseg
        jp      done
; regs — IX and IY must still be what step 5 put there.
regs:   push    ix
        pop     hl
        ld      de,1234h
        or      a
        sbc     hl,de
        jr      nz,.bad
        push    iy
        pop     hl
        ld      de,5678h
        or      a
        sbc     hl,de
        ret     z
.bad:   pop     hl                      ; not back to the step
        ld      a,9
        ld      (step),a
        jp      fail
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
slot:   db      0
seg:    db      0
tab:    dw      0
