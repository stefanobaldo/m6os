; The resident kernel image and its contract with whatever loads it.
;
; The image is assembled at K_BASE (src/kernel/kernel.asm, build/kernel.bin)
; and copied there by a loader that has already filled the capture record
; (K_REC) from the environment it is leaving. The header at K_BASE — entry
; points, the jump table and the record — is the only thing a loader or a
; program needs to know about the image's insides.

K_BASE          equ 0C000h
K_ENTRY         equ K_BASE+0    ; JP k_main: the loader jumps here last
K_ISR           equ K_BASE+3    ; JP k_isr: the target of page 0's 0038h
K_TICKS         equ K_BASE+6    ; dw: ticks counted since k_irq_init
K_END           equ K_BASE+8    ; dw: first address after the image; also
                                ;     the top of the resident's stack, and
                                ;     where a loader puts a program's block
K_STUB          equ K_BASE+10   ; dw: address of the subslot stub image,
                                ;     K_SSLOT_LEN bytes, to copy to K_SSLOT
K_PROBE         equ K_BASE+12   ; db: reserved for memory detection — the
                                ;     byte it writes when the segment under
                                ;     test is the one in page 3
K_PROBE_SLOT    equ K_BASE+13   ; db: reserved — the slot being probed
K_API           equ K_BASE+16   ; K_API_N entries of JP, 3 bytes each: what
                                ;     a program calls in the resident; the
                                ;     order is fixed and only grows
K_API_N         equ 8
K_REC           equ K_API+3*K_API_N     ; the capture record, KREC_SIZE bytes

; The jump table's entries. Contracts are the routines' own (con.asm,
; abi2.asm, slot.asm).
API_CON_PUTS    equ 0           ; HL -> 0-terminated string
API_CON_PUTC    equ 1           ; A = character; 10 is a newline
API_CON_NEWLINE equ 2
API_CON_HEX8    equ 3           ; A
API_CON_HEX16   equ 4           ; HL
API_CON_DEC16   equ 5           ; HL, no leading zeros
API_NX_RW       equ 6           ; IX -> descriptor, Cy, B, HL, DE -> sector
API_K_ENASLT    equ 7           ; A = slot, HL = address; DI on return

; k_call n — call the resident through the jump table.
    macro k_call n
        call    K_API+3*n
    endm

; The capture record: what the resident needs to know about the machine,
; gathered by the loader while the previous system is still there. Every
; field is one byte unless noted. KR_CSRY is read last, just before the
; takeover, so that the resident's output continues under the loader's.
KR_RAMAD        equ 0           ; 4: RAM slot of each page (RAMAD0-3)
KR_SEG64K       equ 4           ; 4: mapper segment in each page
KR_CODESEG      equ 8           ; the previous kernel's code segment
KR_DATASEG      equ 9           ; the previous kernel's data segment
KR_MAPSLOT      equ 10          ; slot of the primary mapper (report only)
KR_MAPTOTAL     equ 11          ; its segment count as reported (report only)
KR_WALL         equ 12          ; 2: first page-3 address the resident must
                                ;    not touch (driver work areas start here)
KR_DOSHIM       equ 14          ; 2: top of the previous kernel's resident code
KR_TIMISAVE     equ 16          ; 5: H.TIMI as it was before that kernel
KR_FCALSAVE     equ 21          ; 5: FCALL as it was before that kernel
KR_VDPRD        equ 26          ; VDP read port (data; status is +1)
KR_VDPWR        equ 27          ; VDP write port (data; control is +1)
KR_NAMBAS       equ 28          ; 2: name table of the inherited text screen
KR_COLS         equ 30          ; characters per line in use
KR_STRIDE       equ 31          ; name-table bytes per row (40 or 80)
KR_ROWS         equ 32          ; rows on screen
KR_CSRY         equ 33          ; cursor row the previous system left, 1-based
KR_DRV          equ 34          ; 4: Nextor driver descriptor (NXD_*)
KR_FIRST        equ 38          ; 4: first device sector of the boot partition
KR_TARGET       equ 42          ; 4: device sector the test writes
KR_TPRE         equ 46          ; 2: ticks for 600 driver reads, pre-takeover
KR_TPRECMP      equ 48          ; 2: the same loop without the call, pre-takeover
KR_KSLOTS       equ 50          ; 4: the Nextor kernel slots found (report only)
KR_TEST         equ 54          ; 2: where k_main jumps after boot; 0 = halt
KR_MEMCAP       equ 56          ; usable segments of the primary mapper;
                                ; 0 = no cap (256 is therefore written as 0)
KREC_SIZE       equ 57

; Page 0. Every page 0 the kernel runs with carries these two things and
; nothing else is required of it: the interrupt entry, and the secondary
; slot switching stub, which must execute outside page 3 because writing
; FFFFh needs page 3 to show the slot being switched. MSX-DOS keeps its
; copy of the same code at 003Bh-005Ah for the same reason.
K_INTRPT        equ 0038h       ; JP K_ISR
K_SSLOT         equ 0040h       ; the stub, K_SSLOT_LEN bytes
K_SSLOT_LEN     equ 17

; BIOS entry points and work-area variables the kernel calls, reads or
; preserves. The BIOS system area F380h-FFFFh lies above the wall and is
; never written by the resident; these are the addresses it depends on.
B_RDSLT         equ 000Ch       ; A = slot, HL = address -> A; DI on return
B_CALSLT        equ 001Ch       ; IY(h) = slot, IX = address
B_INITXT        equ 006Ch       ; SCREEN 0 with LINL40 columns
B_LINL40        equ 0F3AEh      ; columns SCREEN 0 is initialised with
B_LINLEN        equ 0F3B0h      ; columns in use
B_CRTCNT        equ 0F3B1h      ; rows on screen
B_TXTNAM        equ 0F3B3h      ; SCREEN 0 name table
B_CSRY          equ 0F3DCh      ; cursor row, 1-based
B_JIFFY         equ 0FC9Eh      ; BIOS tick counter, dead after the takeover
B_SCRMOD        equ 0FCAFh      ; current screen mode
B_EXPTBL        equ 0FCC1h      ; per primary slot: 80h if expanded
B_SLTTBL        equ 0FCC5h      ; per primary slot: its subslot register
B_SLTWRK        equ 0FD09h      ; 8 bytes per slot: work-area pointer or data
B_HTIMI         equ 0FD9Fh      ; timer interrupt hook, 5 bytes
B_FCALL         equ 0FFCAh      ; extended BIOS hook, 5 bytes

; Scaffolding shared by the tests and the resident: the tests' buffers, in
; page 2 as DEV_RW demands (page 1 is switched away during a call).
; MAILBOX is 8000h-8003h (tests/m6test.inc).
KT_SCRATCH      equ 8100h       ; 64: _GDLI / _GDRVR blocks
KT_BUF_A        equ 8200h       ; 512: the reference sector, read via Nextor
KT_BUF_B        equ 8400h       ; 512: what the driver returns
KT_BUF_C        equ 8600h       ; 512: patterns
KT_LSTACK       equ 9000h       ; the loader's stack top (page 2: the DOS
                                ; stack sits under DOSHIM and is overwritten)
