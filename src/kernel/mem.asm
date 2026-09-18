; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; Memory: the segment allocator, and the tables mapper detection builds.
; Detection itself — mem_init, mem_scan_slot — runs once and lives in
; boot.asm; its rules are stated here because the tables are its result.
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

; mem_owner_of — A = segment: A = its owner byte (API2_MEM_OWNER, for the
; switched part's checks). Corrupts DE, HL.
mem_owner_of:
        ld      l,a
        ld      h,0
        ld      de,mem_owner
        add     hl,de
        ld      a,(hl)
        ret

; mem_own — A = segment, B = the new owner: a change of owner with no
; change to the free stack, for a segment that is not on it (the boot-time
; reserved ones the kernel keeps). Preserves BC, DE, HL.
mem_own:
        push    hl
        push    de
        ld      e,a
        ld      d,0
        ld      hl,mem_owner
        add     hl,de
        ld      (hl),b
        pop     de
        pop     hl
        ret

; mem_release — A = a segment reserved at boot: it becomes free and enters
; the stack. Preserves BC, DE, HL.
mem_release:
        push    hl
        push    de
        push    bc
        ld      e,a
        ld      d,0
        ld      hl,mem_owner
        add     hl,de
        ld      (hl),MEM_FREE
        call    mem_push
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

mem_total:      dw 0            ; segments in the primary mapper
mem_usable:     dw 0            ; MIN(total, cap): what the allocator manages
mem_free_n:     dw 0            ; entries on the free stack
mem_maps:       db 0            ; mappers found, then MM_SIZE bytes each
                ds MEM_MAPS_MAX*MM_SIZE
mem_maps_over:  db 0            ; mappers found beyond MEM_MAPS_MAX
mem_owner:      ds 256          ; owner per segment
mem_free_stk:   ds 256          ; free segment numbers
