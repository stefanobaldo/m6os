; The keyboard: the matrix scanned from the interrupt handler, a queue of
; events, and read on file descriptor 0.
;
; The matrix has KBD_ROWS rows of eight keys behind the PPI: port C's
; low nibble selects a row, port B reads it, a 0 bit is a key held down.
; kbd_tick, called by the handler after the tick is counted, scans every
; third tick — or every tick while a process is blocked in read, when the
; latency of a key is what somebody is waiting for — and compares each row
; with the last scan. A key going down is an event: its number (row * 8 +
; bit) and the modifier row as it reads at that moment, two bytes into a
; ring of KBD_RING_N events; a full ring drops the event. Modifiers alone
; make no event — but CAPS toggles its state and its LED on the spot. A
; key still down after 30 ticks repeats every 5, until any key goes up;
; the clock runs on every tick and the scan queues the repeat when it is
; due, so the rate is the same in both scanning regimes.
;
; When an event has been queued and a process is blocked in read, every
; such process is woken — its row into the ring of runnable rows — before
; the handler decides whether to switch, so that a reader runs on the very
; tick its key arrived if the interrupted code was in user space. The
; handler runs with interrupts disabled, so its walk of the table is
; atomic; every other ring maintenance point disables them for the call.
;
; read blocks until the queue holds an event, then translates events
; through the keymap until the buffer is full or the queue empty; an event
; that translates to nothing — a dead key, an F-key — is consumed and
; skipped. Two readers blocked at once are both woken; whoever runs first
; drains the queue and the other blocks again.

KBD_REP_DELAY   equ 30          ; ticks before the first repeat
KBD_REP_RATE    equ 5           ; ticks between repeats
KBD_MODROW      equ 6           ; the row of SHIFT, CTRL, GRAPH, CAPS, CODE
KBD_CAPS_BIT    equ 3

; kbd_init — the LED off, the scan's baseline "nothing pressed".
kbd_init:
        in      a,(PPI_C)
        set     6,a
        out     (PPI_C),a
        ret

; kbd_tick — from the handler, once per tick: the repeat's clock, the
; period, then the scan. Corrupts AF, HL; preserves everything else.
kbd_tick:
        ld      a,(kbd_held)
        inc     a
        jr      z,.period               ; FFh: nothing held
        ld      hl,kbd_rep
        dec     (hl)
        jr      nz,.period
        ld      (hl),KBD_REP_RATE
        ld      a,1
        ld      (kbd_repdue),a          ; the next scan queues it
.period:
        ld      hl,kbd_period
        dec     (hl)
        jr      z,.scan
        ld      a,(k_kbwait)
        or      a
        ret     z                       ; nobody waiting: every third tick
.scan:  ld      (hl),3
        push    bc
        push    de
        xor     a
        ld      (kbd_event),a
        ld      hl,kbd_last
        ld      d,0                     ; d = the row
.row:   in      a,(PPI_C)
        and     0F0h
        or      d
        out     (PPI_C),a
        in      a,(PPI_B)
        ld      e,a                     ; e = the row now
        xor     (hl)
        jr      z,.next                 ; nothing changed
        ld      b,a                     ; b = the bits that changed
        ld      a,(hl)
        ld      (hl),e
        and     b                       ; were 1, are 0: pressed
        ld      c,a
        ld      a,b
        and     e                       ; were 0, are 1: released
        jr      z,.pressed
        ld      a,0FFh                  ; any release ends the repeat
        ld      (kbd_held),a
.pressed:
        ld      a,c
        or      a
        call    nz,kbd_presses
.next:  inc     hl
        inc     d
        ld      a,d
        cp      KBD_ROWS
        jr      c,.row
        ; The repeat, when its clock has run out and the key is still down.
        ld      hl,kbd_repdue
        ld      a,(hl)
        or      a
        jr      z,.wake
        ld      (hl),0
        ld      a,(kbd_held)
        cp      0FFh
        jr      z,.wake
        ld      e,a
        call    kbd_queue
.wake:  ld      a,(kbd_event)
        or      a
        jr      z,.out
        ld      a,(k_kbwait)
        or      a
        call    nz,kbd_wake
.out:   pop     de
        pop     bc
        ret

; kbd_presses — A = the bits pressed in row D: one event per bit. Preserves
; D, HL; corrupts AF, BC, E.
kbd_presses:
        push    hl
        ld      c,a
        ld      b,0                     ; b = the bit
.bit:   srl     c
        jr      nc,.skip
        push    bc
        ld      a,d
        add     a,a
        add     a,a
        add     a,a
        or      b
        ld      e,a                     ; e = the key's number
        call    kbd_key
        pop     bc
.skip:  inc     b
        ld      a,c
        or      a
        jr      nz,.bit
        pop     hl
        ret

; kbd_key — E = a key going down. A modifier is not an event, except that
; CAPS toggles; anything else is queued and starts the repeat's clock.
; Preserves D; corrupts AF, BC, E, HL.
kbd_key:
        ld      a,e
        cp      KBD_MODROW*8
        jr      c,.key
        cp      KBD_MODROW*8+8
        jr      nc,.key
        cp      KBD_MODROW*8+KBD_CAPS_BIT
        ret     nz                      ; SHIFT, CTRL, GRAPH, CODE, F1-F3
        ld      hl,kbd_caps
        ld      a,(hl)
        xor     1
        ld      (hl),a
        in      a,(PPI_C)
        set     6,a                     ; the LED: 0 lights it
        bit     0,(hl)
        jr      z,.led
        res     6,a
.led:   out     (PPI_C),a
        ret
.key:   ld      (kbd_held),a
        ld      a,KBD_REP_DELAY
        ld      (kbd_rep),a
        xor     a
        ld      (kbd_repdue),a
        ; falls into kbd_queue

; kbd_queue — E = a key: into the ring with the modifier row as it reads
; now, unless the ring is full. Preserves D; corrupts AF, BC, E, HL.
kbd_queue:
        ld      a,(kbd_count)
        cp      KBD_RING_N
        ret     nc                      ; full: dropped
        ld      hl,kbd_count
        inc     (hl)
        in      a,(PPI_C)
        and     0F0h
        or      KBD_MODROW
        out     (PPI_C),a
        in      a,(PPI_B)
        ld      c,a                     ; c = the modifiers, 0 = down
        ld      a,(kbd_head)
        add     a,a
        ld      l,a
        ld      h,0
        ld      a,c
        ld      bc,kbd_ring
        add     hl,bc
        ld      (hl),e
        inc     hl
        ld      (hl),a
        ld      a,(kbd_head)
        inc     a
        and     KBD_RING_N-1
        ld      (kbd_head),a
        ld      a,1
        ld      (kbd_event),a
        ret

; kbd_wake — every row blocked in read becomes runnable. From the handler,
; interrupts disabled. Corrupts AF, BC, DE, HL.
kbd_wake:
        xor     a
        ld      (k_kbwait),a
        ld      hl,K_PROC
        ld      b,NPROC
.row:   ld      a,(hl)
        cp      PS_KBD
        jr      nz,.next
        ld      (hl),PS_RUN
        push    bc
        push    hl
        call    sched_link              ; hl = the row
        pop     hl
        pop     bc
.next:  ld      a,l
        add     a,P_SIZE
        ld      l,a
        djnz    .row
        ret

; kbd_pop — the oldest event out of the ring and through the keymap: A =
; the byte, CF clear; or CF set when the event makes no byte. The ring
; must not be empty. Preserves BC, DE, HL.
kbd_pop:
        push    hl
        push    de
        push    bc
        ld      a,(kbd_tail)
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      bc,kbd_ring
        add     hl,bc
        ld      e,(hl)                  ; e = the key
        inc     hl
        ld      c,(hl)                  ; c = the modifiers
        ld      a,(kbd_tail)
        inc     a
        and     KBD_RING_N-1
        ld      (kbd_tail),a
        ld      hl,kbd_count
        dec     (hl)                    ; one instruction: safe against the
                                        ; handler's inc
        ; The keymap: plain or shifted.
        ld      hl,kbd_map
        ld      d,0
        add     hl,de
        add     hl,de
        bit     0,c                     ; SHIFT
        jr      nz,.plain
        inc     hl
.plain: ld      a,(hl)
        or      a
        jr      z,.none
        ; A letter: CAPS inverts its case, CTRL makes it a control.
        ld      d,a
        or      20h
        cp      'a'
        jr      c,.byte
        cp      'z'+1
        jr      nc,.byte
        ld      a,(kbd_caps)
        or      a
        jr      z,.ctrl
        ld      a,d
        xor     20h
        ld      d,a
.ctrl:  bit     1,c
        jr      nz,.byte
        ld      a,d
        and     1Fh
        ld      d,a
.byte:  ld      a,d
        or      a                       ; CF clear
        jr      .out
.none:  scf
.out:   pop     bc
        pop     de
        pop     hl
        ret

; sys_read — SYS_READ: A = fd (0), HL = buffer, BC = length. Out: HL =
; bytes read, 1 to BC; CF and E_BADF for another fd, E_INVAL for a length
; of 0. Blocks while the queue is empty. Runs on the process's stack.
sys_read:
        or      a
        jr      nz,.badf
        ld      a,b
        or      c
        jr      z,.inval
        ld      (rd_buf),hl
        ld      (rd_len),bc
.again: ld      a,(kbd_count)
        or      a
        jr      nz,.have
        ; Block: the cursor on, the row out of the ring — then a last look
        ; at the queue with interrupts off, so that a key arriving between
        ; the look above and the sleep is not slept through.
        ld      a,(con_shown)
        or      a
        jr      nz,.shown
        inc     a
        ld      (con_shown),a
        ld      a,(con_row)
        ld      hl,con_col
        ld      c,(hl)
        call    vdp_cursor_on
.shown: di
        ld      a,(kbd_count)
        or      a
        jr      nz,.woken
        ld      hl,(k_cur)
        ld      (hl),PS_KBD
        ld      hl,k_kbwait
        inc     (hl)
        call    sched_unlink
        ld      hl,.again               ; resume at the top
        push    hl
        push    af
        push    hl
        jp      sched_save_block        ; its ei is the load's
.woken: ei
.have:  ld      hl,(rd_buf)
        ld      bc,(rd_len)
        ld      de,0                    ; de = bytes delivered
.next:  ld      a,(kbd_count)
        or      a
        jr      z,.end
        call    kbd_pop
        jr      c,.next                 ; nothing from that one
        ld      (hl),a
        inc     hl
        inc     de
        dec     bc
        ld      a,b
        or      c
        jr      nz,.next
.end:   ld      a,d
        or      e
        jr      z,.again                ; every event was silent: sleep on
        ld      a,(con_shown)
        or      a
        jr      z,.ret
        xor     a
        ld      (con_shown),a
        push    de
        ld      a,(con_row)
        ld      hl,con_col
        ld      c,(hl)
        call    vdp_cursor_off
        pop     de
.ret:   ex      de,hl
        or      a                       ; CF clear
        ret
.badf:  ld      a,E_BADF
        scf
        ret
.inval: ld      a,E_INVAL
        scf
        ret

; The keymap: the international layout, two bytes per key in matrix
; order — plain, then with SHIFT. 0 is no byte. The special keys carry
; the one-byte codes the BIOS gives them.
kbd_map:
        db      '0',')','1','!','2','@','3','#','4','$','5','%','6','^','7','&'   ; row 0
        db      '8','*','9','(','-','_','=','+','\',"|",'[','{',']','}',';',':'   ; row 1
        db      "'",'"','`','~',',','<','.','>','/','?',0,0,'a','A','b','B'       ; row 2
        db      'c','C','d','D','e','E','f','F','g','G','h','H','i','I','j','J'   ; row 3
        db      'k','K','l','L','m','M','n','N','o','O','p','P','q','Q','r','R'   ; row 4
        db      's','S','t','T','u','U','v','V','w','W','x','X','y','Y','z','Z'   ; row 5
        db      0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0                                   ; row 6: modifiers, F1-F3
        db      0,0,0,0,1Bh,1Bh,09h,09h,03h,03h,08h,08h,18h,18h,0Dh,0Dh           ; row 7: F4 F5 ESC TAB STOP BS SELECT RET
        db      20h,20h,0Bh,0Ch,12h,12h,7Fh,7Fh,1Dh,1Dh,1Eh,1Eh,1Fh,1Fh,1Ch,1Ch   ; row 8: SPACE HOME INS DEL LEFT UP DOWN RIGHT
        db      '*','*','+','+','/','/','0','0','1','1','2','2','3','3','4','4'   ; row 9: the keypad
        db      '5','5','6','6','7','7','8','8','9','9','-','-',',',',','.','.'   ; row 10
        ASSERT  $-kbd_map == KBD_ROWS*8*2

kbd_last:       db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh
kbd_ring:       ds KBD_RING_N*2
kbd_head:       db 0            ; the next event goes here
kbd_tail:       db 0            ; the oldest event is here
kbd_count:      db 0            ; events in the ring
kbd_period:     db 3            ; ticks to the next scan
kbd_held:       db 0FFh         ; the key repeating, or FFh
kbd_rep:        db 0            ; ticks to its next repeat
kbd_repdue:     db 0            ; the clock ran out: repeat at the next scan
kbd_caps:       db 0            ; CAPS LOCK is on
kbd_event:      db 0            ; an event was queued this scan
k_kbwait:       db 0            ; processes blocked in read
rd_buf:         dw 0            ; read: the buffer
rd_len:         dw 0            ;   its length
