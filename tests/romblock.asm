; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; A disk test's block assembled for the kernel ROM: the block that a
; test's .com carries at tblock (tests/<name>/block.asm, M6_BLOCK),
; assembled here on its own for 0100h of page 0 against the resident
; without the adapter, to build/<name>.block, which src/rom/rom.asm
; takes whole (M6_TEST_BIN) into bank 2 and its boot copies to 0100h.
; The block runs there as process 0, as drvrom's does. M6_ROM is
; defined for the block: what the ROM's boot leaves different from a
; Nextor loader — the record, the volume's root — is written under it.
        DEFINE  M6_ROM
        include "nextor/nextor.inc"
        include "kernel/kernel.inc"
        include "build/kernel-noadapter.exp"
        include "m6test.inc"
        include "m6prog.inc"
        org     0100h
        include M6_BLOCK
        ASSERT  t_entry = 0100h         ; the boot jumps to the block's first byte
        ASSERT  $ <= KB_BASE
