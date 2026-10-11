; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The pattern volume's layout, shared by the driver block, the test and
; the reader, and read by tests/drvrom/mkvol.py, which writes the volume
; to it: 64 sectors, one FAT of one sector, a root of one sector, one
; sector per cluster; READER in the first PT_RSECS clusters, PATTERN.BIN
; in the PT_PATSECS after it. The driver's bank carries the first PT_K
; sectors and generates the rest.
    IFNDEF PT_LAYOUT
        DEFINE  PT_LAYOUT
PT_SECTORS      equ 64
PT_RSECS        equ 10          ; clusters reserved for READER
PT_K            equ 3+PT_RSECS  ; boot, FAT, root, READER: carried
PT_PATSECS      equ 40          ; PATTERN.BIN, from sector PT_K
    ENDIF
