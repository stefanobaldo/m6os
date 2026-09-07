; Memory: mapper detection and the segment allocator.
;
; Detection writes and reads memory, never the mapper registers, whose
; read-back is not defined by the hardware. Every slot is tried through
; page 2 — the window the MSX-DOS 2 kernel has scanned every slot through
; at every boot for thirty years, so no slot sees a write it has not seen
; before. The byte probed is at offset K_PROBE-K_BASE in the segment: when
; the segment under test is the one in page 3, the write lands on K_PROBE
; and on nothing the kernel is executing; every other segment's byte is
; saved and restored. Interrupts stay enabled: the interrupt handler
; touches neither page 2 nor the mapper.
;
; A mapper's size is the first register value that fails: a mirror fails
; because its alias already reads the second pattern, open bus fails on the
; read. The count is a word, because 256 is a legitimate answer.
;
; The allocator manages the primary mapper — the one page 3 lives in — with
; a stack of free segment numbers (alloc is a pop, free is a push) and an
; owner byte per segment, so that a process's segments can be returned as
; a whole and a segment is never freed by someone who does not own it. A
; segment that does not exist, lies above the boot-time cap, or was in use
; when the kernel started is MEM_RESERVED and never enters the stack.

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
; count its segments, record it. Preserves BC, DE; corrupts AF, HL.
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
        ; Pass 1: every value's byte saved on the stack, AAh written.
        ld      b,0
.p1:    ld      a,b
        out     (0FEh),a
        ld      a,(hl)
        push    af
        inc     sp                      ; keep A only
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
        ld      b,0
.p3:    dec     b
        ld      a,b
        out     (0FEh),a
        dec     sp
        pop     af
        ld      (hl),a
        ld      a,b
        or      a
        jr      nz,.p3
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

; mem_push — A = segment: onto the free stack. Corrupts DE, HL.
mem_push:
        ld      hl,(mem_free_n)
        ld      de,mem_free_stk
        add     hl,de
        ld      (hl),a
        ld      hl,(mem_free_n)
        inc     hl
        ld      (mem_free_n),hl
        ret

; mem_alloc — B = owner (01h-FDh a process, MEM_KERNEL the kernel).
; Out: CF clear and A = the segment, now owned by B; CF set if none is
; free. Preserves BC, DE, HL.
mem_alloc:
        push    hl
        push    de
        ld      hl,(mem_free_n)
        ld      a,h
        or      l
        scf
        jr      z,.out
        dec     hl
        ld      (mem_free_n),hl
        ld      de,mem_free_stk
        add     hl,de
        ld      a,(hl)
        ld      e,a
        ld      d,0
        ld      hl,mem_owner
        add     hl,de
        ld      (hl),b
        or      a                       ; CF clear, A = the segment
.out:   pop     de
        pop     hl
        ret

; mem_free — A = segment, B = its owner. Out: CF clear if freed; CF set if
; the segment is not owned by B — never free what is not yours, never
; twice. Preserves BC, DE, HL.
mem_free:
        push    hl
        push    de
        push    af
        ld      a,b
        or      a
        scf
        jr      z,.refuse               ; nobody owns anything
        inc     a
        scf
        jr      z,.refuse               ; MEM_RESERVED is not an owner
        pop     af
        push    af
        ld      e,a
        ld      d,0
        ld      hl,mem_owner
        add     hl,de
        ld      a,(hl)
        cp      b
        scf
        jr      nz,.refuse
        ld      (hl),MEM_FREE
        ld      a,e
        call    mem_push
        pop     af
        or      a                       ; CF clear
        jr      .out
.refuse:
        pop     af
        scf
.out:   pop     de
        pop     hl
        ret

; mem_free_all — B = owner: free every segment it owns. Out: A = how many.
; Refuses (A = 0) MEM_FREE and MEM_RESERVED as owners. Preserves BC, DE, HL.
mem_free_all:
        push    hl
        push    de
        push    bc
        ld      c,0                     ; c = freed
        ld      a,b
        or      a
        jr      z,.out
        inc     a
        jr      z,.out
        ld      hl,mem_owner
        ld      e,0                     ; e = segment
.scan:  ld      a,(hl)
        cp      b
        jr      nz,.next
        ld      (hl),MEM_FREE
        push    hl
        push    de                      ; mem_push corrupts DE; E is the segment
        ld      a,e
        call    mem_push
        pop     de
        pop     hl
        inc     c
.next:  inc     hl
        inc     e
        jr      nz,.scan
.out:   ld      a,c
        pop     bc
        pop     de
        pop     hl
        ret

; mem_info — HL -> the mapper table (count, then MM_SIZE bytes per mapper),
; BC = free segments, DE = usable segments (the count or the cap),
; A = mappers found beyond the table.
mem_info:
        ld      hl,mem_maps
        ld      bc,(mem_free_n)
        ld      de,(mem_usable)
        ld      a,(mem_maps_over)
        ret

; mem_summary — one line per mapper on the console.
mem_summary:
        ld      hl,mem_maps
        ld      b,(hl)
        inc     hl
.map:   ld      a,b
        or      a
        jp      z,.over
        push    bc
        push    hl
        ld      hl,s_mapper
        call    con_puts
        pop     hl
        ld      a,(hl)                  ; slot
        push    hl
        ld      c,a
        and     3
        add     a,'0'
        call    con_putc
        bit     7,c
        jr      z,.segs
        ld      a,'.'
        call    con_putc
        ld      a,c
        rrca
        rrca
        and     3
        add     a,'0'
        call    con_putc
.segs:  ld      hl,s_colon
        call    con_puts
        pop     hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        inc     hl
        push    hl
        ex      de,hl
        call    con_dec16
        ld      hl,s_segments
        call    con_puts
        pop     hl
        bit     0,(hl)                  ; MMF_PRIMARY
        inc     hl
        push    hl
        jr      z,.notused
        ld      hl,s_primary
        call    con_puts
        ld      hl,(mem_free_n)
        call    con_dec16
        ld      hl,s_free
        call    con_puts
        ld      a,(K_REC+KR_MEMCAP)
        or      a
        jr      z,.line
        ld      hl,s_usable
        call    con_puts
        ld      hl,(mem_usable)
        call    con_dec16
        ld      hl,s_usable2
        call    con_puts
        ld      hl,(mem_usable)
        add     hl,hl
        add     hl,hl
        add     hl,hl
        add     hl,hl                   ; usable * 16 = K
        call    con_dec16
        ld      hl,s_usable3
        call    con_puts
        jr      .line
.notused:
        ld      hl,s_notused
        call    con_puts
.line:  call    con_newline
        pop     hl
        pop     bc
        dec     b
        jp      .map
.over:  ld      a,(mem_maps_over)
        or      a
        ret     z
        push    af
        ld      hl,s_more
        call    con_puts
        pop     af
        call    con_dec8
        ld      hl,s_more2
        call    con_puts
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

mem_total:      dw 0            ; segments in the primary mapper
mem_usable:     dw 0            ; MIN(total, cap): what the allocator manages
mem_free_n:     dw 0            ; entries on the free stack
mem_maps:       db 0            ; mappers found, then MM_SIZE bytes each
                ds MEM_MAPS_MAX*MM_SIZE
mem_maps_over:  db 0            ; mappers found beyond MEM_MAPS_MAX
mem_owner:      ds 256          ; owner per segment
mem_free_stk:   ds 256          ; free segment numbers
