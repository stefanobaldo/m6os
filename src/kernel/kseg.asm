; The switched part of the kernel: the cold path, assembled at KS_BASE and
; switched into page 2 — the kernel window — for the length of a call
; (kwin.asm). It is code and constants only: it may be a ROM bank, so it
; never writes to itself and keeps no variable; what it needs to remember
; lives in the resident. It calls the resident through the jump table and
; nothing else, so it depends on the contract, not on the resident's
; layout. Its own jump table is the first thing in it; the order is fixed
; and only grows. At K_INTRPT and K_SSLOT it carries the interrupt vector
; and the subslot stub, so that its segment serves as process 0's page 0
; (sched.asm); the code starts after them.
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"

        org     KS_BASE
        jp      ks_sysconf              ; KS_SYSCONF
        jp      ks_summary              ; KS_SUMMARY
        jp      ks_blk_init             ; KS_BLK_INIT
        jp      ks_cache_init           ; KS_CACHE_INIT
        jp      ks_bget                 ; KS_BGET
        jp      ks_bwrite               ; KS_BWRITE
        jp      ks_bdrop                ; KS_BDROP
        jp      ks_binval               ; KS_BINVAL
        jp      ks_bread_direct         ; KS_BREAD_DIRECT
        jp      ks_bwrite_direct        ; KS_BWRITE_DIRECT
        jp      ks_rtc_read             ; KS_RTC_READ
        block   KS_BASE+K_INTRPT-$
        jp      K_ISR                   ; 0038h of process 0's page 0
        block   KS_BASE+K_SSLOT-$
        include "kernel/sslot.asm"      ; 0040h: the stub, in place
        ASSERT  $ == KS_TABLE2
        jp      ks_read                 ; KS_READ (ks_vfs.asm)
        jp      ks_open                 ; KS_OPEN
        jp      ks_close                ; KS_CLOSE
        jp      ks_lseek                ; KS_LSEEK
        jp      ks_stat                 ; KS_STAT
        jp      ks_readdir              ; KS_READDIR
        jp      ks_chdir                ; KS_CHDIR
        jp      ks_exec                 ; KS_EXEC (ks_exec.asm)

; ks_enosys — an entry whose body does not exist yet.
ks_enosys:
        ld      a,E_NOSYS
        scf
        ret

; ks_sysconf — SYS_SYSCONF: HL = a SC_* name. Out: HL = its value; CF and
; E_INVAL for a name that is not one.
ks_sysconf:
        ld      a,h
        or      a
        jr      nz,.inval
        ld      a,l
        cp      SC_SEGMENTS_FREE+1
        jr      nc,.inval
        or      a
        jr      nz,.mem
        ld      hl,4000h                ; SC_PAGESIZE
        ret                             ; CF clear from or a
.mem:   push    af
        k_call  API_MEM_INFO            ; hl -> the mapper table, bc = free,
        pop     af                      ; de = usable
        cp      SC_SEGMENTS_FREE
        jr      nz,.notfree
        ld      h,b
        ld      l,c
        or      a
        ret
.notfree:
        cp      SC_SEGMENTS_USABLE
        jr      nz,.total
        ex      de,hl
        or      a
        ret
.total: ld      b,(hl)                  ; SC_SEGMENTS: the primary's count
        inc     hl
.find:  ld      a,b
        or      a
        jr      z,.inval                ; no primary: cannot happen past boot
        inc     hl                      ; MM_SLOT
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; de = MM_SEGS
        inc     hl
        ld      a,(hl)                  ; MM_FLAGS
        inc     hl
        and     MMF_PRIMARY
        jr      nz,.found
        dec     b
        jr      .find
.found: ex      de,hl
        or      a
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; ks_summary — the boot summary of the memory: one line per mapper found,
; the primary's free count, the cap when one is in force, and how many
; mappers were found beyond the table. Called by k_main through the window
; once the switched part is loaded.
ks_summary:
        k_call  API_MEM_INFO
        ld      b,(hl)                  ; mappers
        inc     hl
.map:   ld      a,b
        or      a
        jp      z,.over
        push    bc
        push    hl
        ld      hl,s_mapper
        k_call  API_CON_PUTS
        pop     hl
        ld      a,(hl)                  ; MM_SLOT
        push    hl
        ld      c,a
        and     3
        add     a,'0'
        k_call  API_CON_PUTC
        bit     7,c
        jr      z,.segs
        ld      a,'.'
        k_call  API_CON_PUTC
        ld      a,c
        rrca
        rrca
        and     3
        add     a,'0'
        k_call  API_CON_PUTC
.segs:  ld      hl,s_colon
        k_call  API_CON_PUTS
        pop     hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; MM_SEGS
        inc     hl
        push    hl
        ex      de,hl
        k_call  API_CON_DEC16
        ld      hl,s_segments
        k_call  API_CON_PUTS
        pop     hl
        bit     0,(hl)                  ; MMF_PRIMARY
        inc     hl
        push    hl
        jr      z,.notused
        ld      hl,s_primary
        k_call  API_CON_PUTS
        k_call  API_MEM_INFO
        ld      h,b
        ld      l,c                     ; free
        k_call  API_CON_DEC16
        ld      hl,s_free
        k_call  API_CON_PUTS
        ld      a,(K_REC+KR_MEMCAP)
        or      a
        jr      z,.line
        ld      hl,s_usable
        k_call  API_CON_PUTS
        k_call  API_MEM_INFO
        push    de
        ex      de,hl                   ; usable
        k_call  API_CON_DEC16
        ld      hl,s_usable2
        k_call  API_CON_PUTS
        pop     hl
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; usable * 16 = K
        k_call  API_CON_DEC16
        ld      hl,s_usable3
        k_call  API_CON_PUTS
        jr      .line
.notused:
        ld      hl,s_notused
        k_call  API_CON_PUTS
.line:  k_call  API_CON_NEWLINE
        pop     hl
        pop     bc
        dec     b
        jp      .map
.over:  k_call  API_MEM_INFO
        or      a
        ret     z
        push    af
        ld      hl,s_more
        k_call  API_CON_PUTS
        pop     af
        ld      l,a
        ld      h,0
        k_call  API_CON_DEC16
        ld      hl,s_more2
        k_call  API_CON_PUTS
        ret

s_mapper:   db  "mapper ",0
s_colon:    db  ": ",0
s_segments: db  " segments, ",0
s_primary:  db  "primary, ",0
s_free:     db  " free",0
s_usable:   db  " (",0
s_usable2:  db  " usable, mem=",0
s_usable3:  db  ")",0
s_notused:  db  "not used",0
s_more:     db  "and ",0
s_more2:    db  " more, not scanned",10,0

        include "kernel/ks_blk.asm"
        include "kernel/ks_fat.asm"
        include "kernel/ks_vfs.asm"
        include "kernel/ks_exec.asm"

ks_end:
        ASSERT  ks_end <= KS_BASE+4000h
