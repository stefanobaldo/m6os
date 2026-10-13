; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; m6sd-legacy — the m6sd test block through the legacy adapter: the
; same steps on the SD Mapper ROM that carries the cartridge's Nextor
; driver bank (build/m6sd-legacy.rom), asserting what the adapter
; promises and printing the same figures as the native run, which is
; the comparison between the two. See tests/m6sd/block.asm.
        DEFINE  M6SD_LEGACY
        include "m6sd/block.asm"
