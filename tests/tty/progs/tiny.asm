; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; tiny — exits at its first instruction, with status 0: what the latency
; step spawns sixty times.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:  ret
