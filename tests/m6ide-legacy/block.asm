; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; m6ide-legacy — the m6ide test block through the legacy adapter: the
; same steps on the Sunrise ROM that carries the cartridge's Nextor
; driver bank (build/m6ide-legacy.rom), asserting what the adapter
; promises and printing the same figures as the native run, which is
; the comparison between the two. See tests/m6ide/block.asm.
        DEFINE  M6IDE_LEGACY
        include "m6ide/block.asm"
