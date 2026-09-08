# The harness's half of the console test: on each cue the program leaves in
# the mailbox's fourth byte, check the screen or the video memory, or press
# keys on the matrix with the timing a person would, then clear the cue.
# A cue is acted on only when it is the next one expected, because a
# child process's page 2 shows other bytes at that address while it runs.
set show_screen 1

set CUE      0x8003
set BLINK    0x800
set BLINK_N  240
set expected {5 6 7 8 18 9 10 11 12 13 14 15}
set next     0
set problems {}
set idle_hits 0

# Where the kernel idles, from the resident's export file: a breakpoint
# there counts the times the idle loop halted the CPU.
set exp [open [file join $::env(M6_TEST_DIR) .. .. build kernel.exp] r]
set text [read $exp]
close $exp
if {![regexp {K_IDLE_HALT:\s*EQU\s+0x([0-9A-Fa-f]+)} $text -> hex]} {
    puts stderr "console.tcl: K_IDLE_HALT is not in build/kernel.exp"
    exit 2
}
debug set_bp [expr 0x$hex] {} {incr ::idle_hits}

proc problem {what} {
    lappend ::problems $what
    puts stderr "console.tcl: $what"
}
proc row {n} {
    set rows [split [get_screen] \n]
    return [string trimright [lindex $rows $n]]
}
proc expect_row {n want} {
    set got [row $n]
    if {$got ne $want} { problem "row $n is \"$got\", expected \"$want\"" }
}
proc blink_nonzero {} {
    set n 0
    for {set i 0} {$i < $::BLINK_N} {incr i} {
        if {[debug read VRAM [expr {$::BLINK + $i}]] != 0} { incr n }
    }
    return $n
}
proc ack {} { poke $::CUE 0 }

# The matrix: row and mask of the keys the script presses.
array set key {
    h {3 0x20} e {3 0x04} l {4 0x02} o {4 0x10} m {4 0x04} c {3 0x01}
    a {2 0x40} b {2 0x80} x {5 0x20} y {5 0x40} z {5 0x80} q {4 0x40}
    6 {0 0x40} space {8 0x01} shift {6 0x01} ctrl {6 0x02} caps {6 0x08}
    kp1 {9 0x10} right {8 0x80} ret {7 0x80}
}
proc down {k} { keymatrixdown {*}$::key($k) }
proc up {k}   { keymatrixup   {*}$::key($k) }

# at <seconds> <script>: emulated time from now.
proc at {t script} { after time $t $script }
# tap <key> at <t>: down at t, up 0.07 s later — long enough for a scan
# every third tick to see it.
proc tap {t k} {
    at $t [list down $k]
    at [expr {$t + 0.07}] [list up $k]
}

proc cue {c} {
    switch $c {
        5 {
            if {[blink_nonzero] != 0} { problem "the blink table is not clear after boot" }
            if {![string match "console: m6 writes*" [row 0]]} { problem "row 0 is not the banner: \"[row 0]\"" }
            ack
        }
        6 {
            expect_row 0 "6 controls:"
            expect_row 1 "Zbd     x"
            expect_row 2 [string repeat w 80]
            expect_row 3 "!"
            ack
        }
        7 {
            expect_row 10 ""
            for {set i 1} {$i <= 12} {incr i} {
                expect_row [expr {10 + $i}] [format "L%02d" $i]
            }
            expect_row 23 ""
            ack
        }
        8 {
            expect_row 0 "8 ff"
            for {set i 1} {$i < 24} {incr i} { expect_row $i "" }
            ack
        }
        18 {
            expect_row 0 "N28"
            expect_row 22 "N50"
            expect_row 23 ""
            ack
        }
        9 {
            ack
            set t 0.2
            foreach k {h e l l o space} { tap $t $k; set t [expr {$t + 0.15}] }
            at $t {down shift}
            tap [expr {$t + 0.05}] m
            at [expr {$t + 0.15}] {up shift}
            set t [expr {$t + 0.25}]
            tap $t 6
            set t [expr {$t + 0.15}]
            at $t {down ctrl}
            tap [expr {$t + 0.05}] c
            at [expr {$t + 0.15}] {up ctrl}
            set t [expr {$t + 0.25}]
            foreach k {caps a caps kp1 right ret} { tap $t $k; set t [expr {$t + 0.15}] }
        }
        10 {
            ack
            tap 0.1 a
            tap 0.3 b
            tap 0.5 ret
        }
        11 {
            ack
            at 0.3 {down a}
            at 1.3 {up a}
            tap 1.5 ret
        }
        12 {
            ack
            at 0.1 {keymatrixdown 0 0xFF; keymatrixdown 1 0xFF; keymatrixdown 3 0x0F}
            at 0.2 {keymatrixup 0 0xFF; keymatrixup 1 0xFF; keymatrixup 3 0x0F}
            tap 1.0 ret
        }
        13 {
            ack
            tap 0.3 x
            tap 0.8 y
        }
        14 {
            ack
            at 0.3 {
                set n [blink_nonzero]
                if {$n != 1} { problem "the blink table has $n bytes set while a reader waits, expected 1" }
            }
            tap 0.4 z
        }
        15 {
            ack
            tap 0.5 q
        }
    }
}

proc cue_poll {} {
    if {$::next < [llength $::expected]} {
        set want [lindex $::expected $::next]
        if {[peek $::CUE] == $want} {
            incr ::next
            cue $want
        }
    }
    after time 0.05 cue_poll
}
after time 0.1 cue_poll

proc post_verdict {} {
    if {[blink_nonzero] != 0} { problem "the blink table is not clear at the end" }
    if {$::idle_hits == 0} { problem "the idle loop never halted the CPU" }
    if {$::next != [llength $::expected]} { problem "only $::next of [llength $::expected] cues were seen" }
    if {[llength $::problems]} { return [join $::problems "; "] }
    puts stderr "harness: $::test: every cue answered, the idle loop halted $::idle_hits times"
    return ""
}
