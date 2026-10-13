# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The interrupts-off probe, sourced by m6ide.tcl: how long interrupts
# stay disabled around a driver call. The kernel's own stretches are
# measured live — breakpoints at the di of k_enaslt when it is called
# from blk_drv_call, at blk_drv_call's two ei, and at the handler's
# entry and its ei — each stretch the emulated time between a di and
# the ei that ends it, the longest kept. The driver block's own di are
# counted in the listing instead of watched: the ROM's listing between
# the driver's file markers, every F3 opcode. The figures are printed
# at the verdict; with ::probe_strict set the verdict requires no di
# in the block — the 100 us rule docs/drivers.md gives a block, met by
# having none — and the kernel's stretch around a call under a
# millisecond, a bound a sector copied with interrupts off (2.6 ms)
# cannot pass: the kernel's own figure, ~210 us for the slot and bank
# switches on either side of the call, is a hint, as is the handler's,
# printed beside it. ::probe_lst names the resident's listing
# (kernel-noadapter.lst for the native ROM, kernel.lst for the legacy
# one).
set ::probe_kmax 0.0
set ::probe_imax 0.0
set ::probe_t_di ""
set ::probe_t_isr ""
set ::probe_calls 0

proc probe_read {path} {
    set fh [open $path r]
    set text [read $fh]
    close $fh
    return [split $text \n]
}

# The resident's addresses from its listing.
set lines [probe_read [file join $::env(M6_TEST_DIR) .. .. $::probe_lst]]
set enaslt_di ""
set drv_lo ""
set drv_hi ""
set drv_ei {}
set isr ""
set isr_ei ""
set state ""
foreach line $lines {
    if {[regexp {^\s*\d+\+*\s*([0-9A-F]{4})\s+k_enaslt:} $line -> a]} { set state enaslt; continue }
    if {[regexp {^\s*\d+\+*\s*([0-9A-F]{4})\s+blk_drv_call:} $line -> a]} { set drv_lo 0x$a; set state drv; continue }
    if {[regexp {^\s*\d+\+*\s*([0-9A-F]{4})\s+\S.*\sblk_jp:} $line -> a]} { set drv_hi 0x$a; set state ""; continue }
    if {[regexp {^\s*\d+\+*\s*([0-9A-F]{4})\s+k_isr:} $line -> a]} { set isr 0x$a; set state isr; continue }
    switch $state {
        enaslt { if {[regexp {^\s*\d+\+*\s*([0-9A-F]{4})\s+F3\s} $line -> a]} { set enaslt_di 0x$a; set state "" } }
        drv    { if {[regexp {^\s*\d+\+*\s*([0-9A-F]{4})\s+FB\s} $line -> a]} { lappend drv_ei 0x$a } }
        isr    { if {[regexp {^\s*\d+\+*\s*([0-9A-F]{4})\s+FB\s} $line -> a]} { set isr_ei 0x$a; set state "" } }
    }
}
if {$enaslt_di eq "" || $drv_lo eq "" || $drv_hi eq "" || [llength $drv_ei] != 2 || $isr eq "" || $isr_ei eq ""} {
    puts stderr "di.tcl: the listing $::probe_lst did not give every address (k_enaslt di $enaslt_di, blk_drv_call $drv_lo-$drv_hi, ei $drv_ei, k_isr $isr, ei $isr_ei)"
    exit 2
}

# The block's di, from the ROM's listing: every F3 between the markers
# of the driver's files (::probe_files; m6ide.asm alone by default — a
# driver made of a port and a core names both; a file included from an
# included file lists its lines with `++`).
if {![info exists ::probe_files]} { set ::probe_files {m6ide.asm} }
set ::probe_block_di 0
set inblock 0
foreach line [probe_read [file join $::env(M6_TEST_DIR) .. .. build "$::env(M6_TEST).lst"]] {
    foreach f $::probe_files {
        if {[string match "# file opened: $f" $line]} { set inblock 1 }
        if {[string match "# file closed: $f" $line]} { set inblock 0 }
    }
    if {$inblock && [regexp {^\s*\d+\+*\s*[0-9A-F]{4}\s+F3\s} $line]} { incr ::probe_block_di }
}

proc probe_di {} {
    set ret [peek16 [reg SP]]
    if {$ret >= $::drv_lo && $ret < $::drv_hi} {
        set ::probe_t_di [machine_info time]
        incr ::probe_calls
    }
}
proc probe_ei {} {
    if {$::probe_t_di ne ""} {
        set d [expr {([machine_info time] - $::probe_t_di) * 1e6}]
        if {$d > $::probe_kmax} { set ::probe_kmax $d }
        set ::probe_t_di ""
    }
}
proc probe_isr {} { set ::probe_t_isr [machine_info time] }
proc probe_isr_ei {} {
    if {$::probe_t_isr ne ""} {
        set d [expr {([machine_info time] - $::probe_t_isr) * 1e6}]
        if {$d > $::probe_imax} { set ::probe_imax $d }
        set ::probe_t_isr ""
    }
}
set ::drv_lo $drv_lo
set ::drv_hi $drv_hi
debug set_bp $enaslt_di {} {probe_di}
foreach a $drv_ei { debug set_bp $a {} {probe_ei} }
debug set_bp $isr {} {probe_isr}
debug set_bp $isr_ei {} {probe_isr_ei}

# What the probe found, for post_verdict: a failure string, or "".
proc probe_report {} {
    puts stderr "harness: $::test: interrupts off at most [format %.1f $::probe_kmax] us around a driver call, in the kernel ($::probe_calls calls), and [format %.1f $::probe_imax] us in the handler (hints); the driver block has $::probe_block_di di"
    if {!$::probe_strict} { return "" }
    if {$::probe_block_di != 0} { return "the driver block has $::probe_block_di di" }
    if {$::probe_kmax > 1000.0} { return "interrupts off [format %.1f $::probe_kmax] us around a driver call: a transfer under di" }
    return ""
}
