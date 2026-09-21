; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; Shared by the legacy layer (leg.asm) and its launcher (bin/dos.asm),
; which carries the layer's messages: the MSX-DOS 2 error codes the
; layer returns (DOS2-PIS §6).
D_STOP          equ 9Fh         ; Ctrl-STOP pressed
D_CTRLC         equ 9Eh         ; Ctrl-C pressed
D_ABORT         equ 9Dh         ; Disk operation aborted
D_IBDOS         equ 0DCh        ; Invalid MSX-DOS call
D_ISBFN         equ 0B8h        ; Invalid sub-function number
D_IPARM         equ 8Bh         ; Invalid parameter
D_INTER         equ 0DFh        ; Internal error
D_NORAM         equ 0DEh        ; Not enough memory
D_IDRV          equ 0DBh        ; Invalid drive
D_IFNM          equ 0DAh        ; Invalid filename
D_IPATH         equ 0D9h        ; Invalid pathname
D_PLONG         equ 0D8h        ; Pathname too long
D_NOFIL         equ 0D7h        ; File not found
D_NODIR         equ 0D6h        ; Directory not found
D_DRFUL         equ 0D5h        ; Root directory full
D_DKFUL         equ 0D4h        ; Disk full
D_DUPF          equ 0D3h        ; Duplicate filename
D_DIRE          equ 0D2h        ; Invalid directory move
D_FILRO         equ 0D1h        ; Read only file
D_DIRNE         equ 0D0h        ; Directory not empty
D_IATTR         equ 0CFh        ; Invalid attributes
D_DOT           equ 0CEh        ; Invalid . or .. operation
D_SYSX          equ 0CDh        ; System file exists
D_DIRX          equ 0CCh        ; Directory exists
D_FILEX         equ 0CBh        ; File exists
D_FOPEN         equ 0CAh        ; File already in use
D_EOF           equ 0C7h        ; End of file
D_ACCV          equ 0C6h        ; File access violation
D_IPROC         equ 0C5h        ; Invalid process id
D_NHAND         equ 0C4h        ; No spare file handles
D_IHAND         equ 0C3h        ; Invalid file handle
D_IDEV          equ 0C1h        ; Invalid device operation
D_IENV          equ 0C0h        ; Invalid environment string
D_ELONG         equ 0BFh        ; Environment string too long
D_HDEAD         equ 0BAh        ; File handle has been deleted
D_DISK          equ 0FDh        ; Disk error
D_WPROT         equ 0F8h        ; Write protected disk

; /bin/dos carries the layer's messages for _EXPLAIN, behind an index of
; (code, offset) triples that ends in 0, the offsets from the file's
; start, at LEG_MSGIX of the file — inside the header's jump.
LEG_MSGIX       equ 6
