# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The m6sd harness, for the same block run through the adapter: the
# probe's figures printed, nothing required of them, on the resident
# with the adapter.
set ::probe_strict 0
set ::probe_lst build/kernel.lst
source [file join $::env(M6_TEST_DIR) .. m6sd m6sd.tcl]
