; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; Boot-once code: what runs between the loader's jump to K_ENTRY and the
; first process, and never again. It is assembled in place of the pipe
; buffers (K_PIPEBUF, kernel.asm) — 1024 bytes nobody reads or writes
; before the first pipe — and the first pipe_write overwrites it. Nothing
; here may be reached once k_main has jumped on: the routines are k_main
; itself and what it calls once and nothing else calls — the interrupt
; vector, mapper detection and the allocator's tables, the loading of the
; switched part, and the boot failure. The console's and the keyboard's
; set-up stay resident: the exit of an MSX-DOS program runs them again
; (k_dos_check, dos.asm). The scheduler's first row and the release of the
; loader's pages run in the switched part (KS_BOOT, ks_boot.asm). The image
; is copied as a whole by every loader, so no loader knows the overlay
; exists; the block that closes it in kernel.asm fails the build past 1024
; bytes.

; k_main — the boot sequence, once the loader has jumped here with the
; record filled: the interrupt vector, the console — the VDP programmed
; for 80 columns — the keyboard, memory, the switched part of the kernel;
; then, through the window, the process table with the kernel as process
; 0 and the loader's memory released (KS_BOOT), the storage enumerated
; and listed and the cache emptied, the summary of the memory printed.
; Then, if the record names an address, jump there — a program in the
; loader's page 0 or 1, which KS_BOOT kept as process 0's, so it runs as
; process 0 where it lies — else k_init (main.asm). Without a switched
; image there is no scheduler and no storage: the record's address, or
; the halt, with interrupts on so the tick keeps counting.

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
        ld      a,(K_KSEG)
        or      a
        jr      z,.nokseg               ; no switched part: no scheduler,
        kwin_call KS_BOOT               ; no storage, no summary
        kwin_call_s KS_BLK_INIT
        kwin_call_s KS_CACHE_INIT
        ld      a,(K_BLK_ROOT)          ; process 0 starts in /
        ld      (K_PROC+P_CWD),a
        kwin_call KS_SUMMARY
.nokseg:
        ld      hl,(K_REC+KR_TEST)
        ld      a,h
        or      l
        jp      z,k_init
        jp      (hl)

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
        jp      k_halt

s_bootfail: db  "FAIL boot code ",0
s_bootslot: db  " slot ",0

; k_irq_init — install the vector, select S#0, zero the counter. Call with
; interrupts disabled; the caller enables them. Corrupts AF, BC, HL.
k_irq_init:
        ld      a,0C3h
        ld      (K_INTRPT),a
        ld      hl,K_ISR
        ld      (K_INTRPT+1),hl
        ld      a,(K_REC+KR_VDPRD)
        inc     a
        ld      (k_isr_in+1),a          ; the status port, into the IN below
        ld      a,(K_REC+KR_VDPWR)
        inc     a
        ld      c,a
        xor     a
        out     (c),a                   ; R#15 = 0: S#0 is what IN reads
        ld      a,80h+15
        out     (c),a
        ld      hl,0
        ld      (K_TICKS),hl
        ret

MEM_PROBE       equ 8000h+(K_PROBE-K_BASE)  ; the probe address in page 2

; mem_init — scan every slot, find the primary, build the tables.
; Out: Z if ok; NZ with A = 0F8h and C = RAMAD3 when the slot page 3 is in
; was not found to be a mapper. Corrupts everything.
mem_init:
        xor     a
        ld      (mem_maps),a
        ld      (mem_maps_over),a
        ld      c,0                     ; c = primary slot
.pri:   ld      a,c
        add     a,low B_EXPTBL          ; no carry: C1h + 3
        ld      l,a
        ld      h,high B_EXPTBL
        bit     7,(hl)
        jr      z,.plain
        ld      a,c
        or      80h
        ld      e,a                     ; e = the slot id, subslot 0
        ld      b,4
.sub:   ld      a,e
        call    mem_scan_slot
        ld      a,e
        add     a,4                     ; next subslot
        ld      e,a
        djnz    .sub
        jr      .next
.plain: ld      a,c
        call    mem_scan_slot
.next:  inc     c
        ld      a,c
        cp      4
        jr      c,.pri
        ; Page 2 back to RAM, and the segment it held.
        ld      a,(K_REC+KR_RAMAD+2)
        ld      hl,8000h
        call    k_enaslt
        ei
        ld      a,(K_REC+KR_SEG64K+2)
        out     (0FEh),a
        ; The primary: the mapper in page 3's slot.
        ld      a,(K_REC+KR_RAMAD+3)
        ld      c,a
        ld      hl,mem_maps
        ld      b,(hl)
        inc     hl
.find:  ld      a,b
        or      a
        jr      z,.noprimary
        ld      a,(hl)
        cp      c
        jr      z,.primary
        inc     hl
        inc     hl
        inc     hl
        inc     hl
        dec     b
        jr      .find
.noprimary:
        ld      a,0F8h
        or      a                       ; NZ
        ret
.primary:
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)                  ; de = segments
        inc     hl
        ld      (hl),MMF_PRIMARY
        ld      (mem_total),de
        ; The cap.
        ex      de,hl                   ; hl = total
        ld      a,(K_REC+KR_MEMCAP)
        or      a
        jr      z,.capped
        ld      e,a
        ld      d,0                     ; de = cap
        push    hl
        or      a
        sbc     hl,de                   ; total - cap
        pop     hl
        jr      c,.capped               ; total < cap: the cap changes nothing
        ex      de,hl                   ; hl = cap
.capped:
        ld      (mem_usable),hl
        ; The tables: everything reserved, then the usable segments that are
        ; not in use freed, highest first so that the lowest pops first.
        ld      hl,mem_owner
        ld      (hl),MEM_RESERVED
        ld      de,mem_owner+1
        ld      bc,255
        ldir
        ld      hl,0
        ld      (mem_free_n),hl
        ld      hl,(mem_usable)
.fill:  ld      a,h
        or      l
        jr      z,.done
        dec     hl
        ld      a,l                     ; usable <= 256, so this is v
        call    mem_is_live
        jr      z,.fill
        push    hl
        ld      e,a
        ld      d,0
        ld      hl,mem_owner
        add     hl,de
        ld      (hl),MEM_FREE
        call    mem_push
        pop     hl
        jr      .fill
.done:  xor     a                       ; Z
        ret

; mem_is_live — Z if A is one of the four segments in pages 0-3 at boot.
; Preserves A, BC, DE, HL.
mem_is_live:
        push    hl
        push    bc
        ld      hl,K_REC+KR_SEG64K
        ld      b,4
.cmp:   cp      (hl)
        jr      z,.yes
        inc     hl
        djnz    .cmp
        inc     b                       ; NZ, A untouched
.yes:   pop     bc
        pop     hl
        ret

; mem_scan_slot — A = slot id: switch it into page 2, test for a mapper,
; count its segments, record it. The 256 bytes it saves while probing go
; to mem_free_stk, empty until mem_init builds it after the scan: the
; kernel stack need not hold them. Preserves BC, DE; corrupts AF, HL.
mem_scan_slot:
        push    bc
        push    de
        ld      (K_PROBE_SLOT),a
        ld      c,a                     ; c = the slot
        ld      hl,8000h
        call    k_enaslt
        ei
        ld      hl,MEM_PROBE
        ; Presence: AAh in value 1 survives 55h written through value 0.
        ld      a,1
        out     (0FEh),a
        ld      b,(hl)
        ld      (hl),0AAh
        xor     a
        out     (0FEh),a
        ld      d,(hl)
        ld      (hl),55h
        inc     a
        out     (0FEh),a
        ld      e,(hl)
        xor     a
        out     (0FEh),a
        ld      (hl),d
        inc     a
        out     (0FEh),a
        ld      (hl),b
        ld      a,e
        cp      0AAh
        jr      nz,.done
        ; Pass 1: every value's byte saved in the free stack's room — which
        ; mem_init fills only once every slot is scanned — and AAh written.
        ld      b,0
        ld      de,mem_free_stk
.p1:    ld      a,b
        out     (0FEh),a
        ld      a,(hl)
        ld      (de),a
        inc     de
        ld      (hl),0AAh
        inc     b
        jr      nz,.p1
        ; Pass 2: from 0 up, AAh must be there and 55h must stick.
        ld      de,0
        ld      b,0
.p2:    ld      a,b
        out     (0FEh),a
        ld      a,(hl)
        cp      0AAh
        jr      nz,.p2end
        ld      (hl),55h
        ld      a,(hl)
        cp      55h
        jr      nz,.p2end
        inc     de
        inc     b
        jr      nz,.p2
.p2end:                                 ; de = segments
        ; Pass 3: restore from 255 down to 0, so that on a mirroring mapper
        ; the real segment receives its own byte last.
        push    de                      ; the count
        ld      de,mem_free_stk+255
        ld      b,0
.p3:    dec     b
        ld      a,b
        out     (0FEh),a
        ld      a,(de)
        ld      (hl),a
        dec     de
        ld      a,b
        or      a
        jr      nz,.p3
        pop     de
        ; Record it.
        ld      a,(mem_maps)
        cp      MEM_MAPS_MAX
        jr      c,.add
        ld      hl,mem_maps_over
        inc     (hl)
        jr      .done
.add:   inc     a
        ld      (mem_maps),a
        dec     a
        add     a,a
        add     a,a                     ; a = index * MM_SIZE
        ld      hl,mem_maps+1
        add     a,l
        ld      l,a
        jr      nc,.at
        inc     h
.at:    ld      (hl),c
        inc     hl
        ld      (hl),e
        inc     hl
        ld      (hl),d
        inc     hl
        ld      (hl),0
.done:  pop     de
        pop     bc
        ret

; kwin_load — load the switched part from where the record says into a
; segment of the kernel's. Out: Z if done, or if there is none to load
; (K_KSEG stays 0); NZ with A = 0F4h when the source is not in pages 0-1
; or the length is not 1 to 4000h, 0F5h when no segment is free. Corrupts
; everything.
kwin_load:
        ld      hl,(K_REC+KR_KSEG_SRC)
        ld      a,h
        or      l
        ret     z                       ; none: Z
        ld      a,h
        cp      80h
        jr      nc,.bad                 ; not in pages 0-1
        ld      de,(K_REC+KR_KSEG_LEN)
        ld      a,d
        or      e
        jr      z,.bad                  ; empty
        ld      a,d
        cp      40h
        jr      c,.fits
        jr      nz,.bad                 ; above 4000h
        ld      a,e
        or      a
        jr      nz,.bad
.fits:  ld      b,MEM_KERNEL
        call    mem_alloc
        jr      c,.noseg
        ld      (K_KSEG),a
        out     (0FEh),a                ; the new segment into the window
        ld      b,d
        ld      c,e
        ld      de,KS_BASE
        ldir
        ld      a,(k_map+2)
        out     (0FEh),a
        xor     a                       ; Z
        ret
.bad:   ld      a,0F4h
        or      a                       ; NZ
        ret
.noseg: ld      a,0F5h
        or      a
        ret
