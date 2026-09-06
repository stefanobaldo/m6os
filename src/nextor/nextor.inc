; Nextor 2 driver ABI: the addresses a caller outside the Nextor kernel needs
; to find a driver and call it, and the descriptor that names one driver.
; Sources: Nextor 2.1 Driver Development Guide §4.2, §4.3, §4.6 and
; Programmers Reference §3.8, §3.9 (github.com/Konamiman/Nextor, v2.1).

; Page-0 code present in every bank of a Nextor kernel ROM, driver banks
; included, visible at 4000h-40FFh of the kernel's slot in page 1.
NX_K_SIZE       equ 40FEh       ; number of kernel banks = the driver's bank
NX_CUR_BANK     equ 40FFh       ; bank currently visible in page 1
NX_CHGBNK       equ 7FD0h       ; A = bank; makes it visible; corrupts AF

; The driver header and jump table, in the driver bank.
NX_DRV_SIGN     equ 4100h       ; "NEXTOR_DRIVER",0
NX_DRV_FLAGS    equ 410Eh       ; bit 0: device-based
NX_DRV_NAME     equ 4110h       ; 32 characters, space padded
NX_DEV_RW       equ 4160h       ; Cy=0 read/1 write, A dev, B count, C lun,
                                ; HL buffer, DE -> 32-bit sector; A = error
NX_DEV_INFO     equ 4163h
NX_DEV_STATUS   equ 4166h
NX_LUN_INFO     equ 4169h
NX_SIGN_LEN     equ 14          ; "NEXTOR_DRIVER" plus its terminator

; Driver descriptor, NXD_SIZE bytes, filled by nx_find and read by nx_rw.
NXD_SLOT        equ 0           ; slot id in BIOS format, E000SSPP
NXD_BANK        equ 1           ; the driver's bank in the kernel ROM
NXD_DEV         equ 2           ; device index, 1-7
NXD_LUN         equ 3           ; logical unit, 1-7
NXD_SIZE        equ 4

; nx_find results. BDOS error codes are 80h and above; these are below.
NXE_OK          equ 0
NXE_NODEV       equ 1           ; drive is not assigned to a device driver
NXE_NOTNEXTOR   equ 2           ; the driver is an MSX-DOS driver
NXE_NOTDEVICE   equ 3           ; the driver is drive-based
NXE_NOSIGN      equ 4           ; no driver header where _GDLI said

; What the module calls and reads outside itself.
BDOS            equ 0005h
NX_GDRVR        equ 78h         ; _GDRVR: driver information
NX_GDLI         equ 79h         ; _GDLI: drive letter information
NX_E_IDRVR      equ 0B6h        ; .IDRVR: no such driver
ENASLT          equ 0024h       ; BIOS: A = slot, HL = address; DI on return
RAMAD1          equ 0F342h      ; MSX-DOS: RAM slot for page 1
