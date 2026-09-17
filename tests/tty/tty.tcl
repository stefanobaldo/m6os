# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the terminal test: on each cue the block leaves in
# the storage segment — three bytes at CUE: the step, its complement, 5Ah,
# so that a child's page 2 showing through the same addresses is never
# mistaken for one — press keys on the matrix with the timing a person
# would, then clear the cue. After the verdict, read the screen for what
# the block cannot see itself: the echo of the typed lines, the test
# shell's report of a killed command, and the two figures the block prints.
set show_screen 1

set CUE      0x8004
set expected {5 6 7 8 9 10 11 12 13 14 15 16 17 18 22 23 24 25 26 27 28 29 30 31 32 33 34}
set next     0
set problems {}

proc problem {what} {
    lappend ::problems $what
    puts stderr "tty.tcl: $what"
}
proc rows {} {
    set out {}
    foreach r [split [get_screen] \n] { lappend out [string trimright $r] }
    return $out
}
proc has_row {want} {
    foreach r [rows] { if {$r eq $want} { return 1 } }
    return 0
}
proc count_rows {want} {
    set n 0
    foreach r [rows] { if {$r eq $want} { incr n } }
    return $n
}
proc ack {} { poke $::CUE 0 }
# expect_screen <want> <msg>: a row must read exactly <want>, checked now —
# the screen scrolls on, so an echo is looked for while it is still there.
proc expect_screen {want msg} { if {![has_row $want]} { problem $msg } }

# The matrix: row and mask of every key the script presses (kbd_map in
# src/kernel/kbd.asm, the international layout).
array set key {
    a {2 0x40} b {2 0x80} c {3 0x01} d {3 0x02} e {3 0x04} g {3 0x10}
    h {3 0x20} i {3 0x40} l {4 0x02} n {4 0x08} o {4 0x10} p {4 0x20}
    q {4 0x40} s {5 0x01} u {5 0x04} x {5 0x20} y {5 0x40} z {5 0x80}
    ctrl {6 0x02} esc {7 0x04} tab {7 0x08} stop {7 0x10} bs {7 0x20}
    ret {7 0x80} home {8 0x02} del {8 0x08} left {8 0x10} up {8 0x20}
    down {8 0x40} right {8 0x80}
}
proc down {k} { keymatrixdown {*}$::key($k) }
proc up {k}   { keymatrixup   {*}$::key($k) }

# at <seconds> <script>: emulated time from now.
proc at {t script} { after time $t $script }
# tap <t> <key>: down at t, up 0.07 s later — long enough for a scan every
# third tick to see it.
proc tap {t k} {
    at $t [list down $k]
    at [expr {$t + 0.07}] [list up $k]
}
# ctap <t> <key>: the key with CTRL held.
proc ctap {t k} {
    at $t {down ctrl}
    tap [expr {$t + 0.05}] $k
    at [expr {$t + 0.15}] {up ctrl}
}
# taps <t> <keys>: the keys 0.15 s apart; returns the time after the last.
proc taps {t keys} {
    foreach k $keys { tap $t $k; set t [expr {$t + 0.15}] }
    return $t
}
# typeline <t> <keys>: the keys, then RET; returns the time after the RET.
proc typeline {t keys} {
    set t [taps $t $keys]
    tap $t ret
    return [expr {$t + 0.15}]
}

# Cue 11's first ^C, at 1.35 s, lands inside bigspin's load: against a
# shell that lowers its guard around spawnv, a ^C from 1.31 to 1.40 s kills
# the shell on both machines, so a shell that survives this one passes for
# the right reason.
proc cue {c} {
    puts stderr "tty.tcl: cue $c at [format %.2f [machine_info time]] s"
    switch $c {
        5  { ack; taps 0.3 {a b bs c} ; ctap 0.95 u ; typeline 1.3 {h e l l o}
             at 2.6 {expect_screen "hello" "the edited line does not read hello on the screen"} }
        6  { ack; typeline 0.3 {x tab y}
             at 1.3 {expect_screen "x       y" "the TAB line does not read x, a stop, y on the screen"} }
        7  { ack; typeline 0.3 {h e l l o} }
        8  { ack; ctap 0.3 d ; typeline 1.0 {z} }
        9  { ack; tap 0.3 esc ; tap 0.5 right ; tap 0.7 x }
        10 { ack; tap 0.3 esc ; tap 0.5 right ; tap 0.7 x ; tap 0.9 ret }
        11 { ack; typeline 0.3 {b i g s p i n} ; ctap 1.35 c ; ctap 2.3 c ; typeline 3.2 {q} }
        12 { ack; ctap 0.4 c }
        13 { ack; ctap 0.4 c }
        14 { ack; ctap 0.4 c }
        15 { ack; ctap 0.4 c }
        16 { ack; ctap 0.4 c }
        17 { ack; ctap 0.4 c }
        18 { ack; typeline 0.3 {i g n} ; ctap 1.3 c ; tap 2.5 a ; tap 2.65 b ; tap 3.0 stop ; typeline 3.6 {q} }
        22 { check_shell_rows ; ack; typeline 0.3 {a b left x}
             at 1.5 {expect_screen "axb" "LEFT then x did not put x between a and b on the screen"} }
        23 { ack; typeline 0.3 {a b c home del}
             at 1.6 {expect_screen "bc" "HOME then DEL did not leave bc on the screen"} }
        24 { ack; typeline 0.3 {a b c left left bs}
             at 1.8 {expect_screen "bc" "LEFT LEFT then BS did not leave bc on the screen"} }
        25 { ack; taps 0.3 {a b c left} ; ctap 0.95 u ; typeline 1.3 {z}
             at 2.0 {expect_screen "z" "^U in the middle then z did not leave z alone on the screen"
                     if {[has_row "abc"]} { problem "^U in the middle left abc on the screen" }} }
        26 { ack; set t [taps 0.3 {tab tab tab tab tab tab tab tab tab tab a b left left left del}]
             at [expr {$t + 0.2}] check_wrap
             tap [expr {$t + 0.4}] ret }
        27 { ack; taps 0.3 {a b left} ; ctap 0.8 l ; typeline 1.2 {x}
             at 1.8 {if {[lindex [rows] 0] ne "axb"} { problem "^L in the middle then x did not leave axb on the first row: \"[lindex [rows] 0]\"" }} }
        28 { ack; typeline 0.3 {a tab b home x}
             at 1.6 {expect_screen "xa      b" "x before a TAB did not shrink the TAB on the screen"} }
        29 { ack; taps 0.3 {a b up} ; typeline 1.5 {c}
             at 2.3 {expect_screen "abc" "the line UP left open did not go on to read abc on the screen"} }
        30 { ack; taps 0.3 {x down} ; typeline 1.2 {y}
             at 2.0 {expect_screen "xy" "the line DOWN left open did not go on to read xy on the screen"} }
        31 { ack; typeline 0.3 {up z}
             at 1.3 {expect_screen "z" "UP in canonical mode was not dropped"} }
        32 { ack; typeline 0.3 {}
             at 0.9 {expect_screen "xyz" "ttyline did not put xyz on the screen"} }
        33 { ack; taps 0.3 {a b up} ; typeline 1.5 {}
             at 2.1 {expect_screen "q" "ttyline over the open line ab did not leave q alone on the screen"} }
        34 { ack; taps 0.3 {a up} ; typeline 1.5 {} }
    }
}

# check_wrap: after DEL took the tenth TAB, ab sits at columns 72-73 of
# the row the line started on and the row below, where ab was, is blank.
proc check_wrap {} {
    set rs [rows]
    set want "[string repeat { } 72]ab"
    set i [lsearch -exact $rs $want]
    if {$i < 0} { problem "after DEL across the wrap, no row reads 72 blanks then ab"; return }
    if {$i == 23} { problem "the wrapped line's first row is the last row: nothing wrapped"; return }
    if {[lindex $rs [expr {$i + 1}]] ne ""} { problem "the row below the wrapped line still reads \"[lindex $rs [expr {$i + 1}]]\"" }
}

proc cue_poll {} {
    if {$::next < [llength $::expected]} {
        set want [lindex $::expected $::next]
        if {[peek $::CUE] == $want && [peek [expr {$::CUE + 1}]] == (255 - $want)
            && [peek [expr {$::CUE + 2}]] == 0x5A} {
            incr ::next
            cue $want
        }
    }
    after time 0.05 cue_poll
}
after time 0.1 cue_poll

# check_shell_rows: the test shell's rows, read at cue 22 — the ^L of cue
# 27 clears the screen, so they are gone by the verdict. The command
# echoed at its prompt, the killed one reported — by the second ^C, the
# first having landed in its load — the survivor reported, two empty
# lines from the two ^Cs nobody took, and nothing typed ahead of them run
# as a command.
proc check_shell_rows {} {
    if {![has_row {$ bigspin}]} { problem "the shell did not echo bigspin at its prompt" }
    if {![has_row {[130]}]} { problem "the shell did not report the command killed by ^C" }
    if {![has_row {[5]}]} { problem "the shell did not report the survivor's status" }
    if {[count_rows "!"] < 2} { problem "fewer than two empty lines reached the shell from the ^Cs nobody took" }
    foreach r [rows] { if {[string first "?" $r] >= 0} { problem "the shell tried to run something it should not have: \"$r\""; break } }
}

proc post_verdict {} {
    if {$::next != [llength $::expected]} { problem "only $::next of [llength $::expected] cues were seen" }
    # The echo of the edited lines was checked while it was on the screen
    # (cues 5, 6 and 22-28), and the test shell's rows at cue 22; by now
    # they have scrolled off or been cleared.
    # The two figures, for the log.
    foreach r [rows] {
        if {[regexp {^16 .*: (\d+) bytes} $r -> v]} {
            puts stderr "harness: $::test: the handler's deepest write on a process's stack during a ^C: $v bytes of 24"
        }
        if {[regexp {^17 .*: (\d+) ticks} $r -> v]} {
            puts stderr "harness: $::test: a ^C during a file read: the process died $v ticks after the press (an emulator's figure: a hint)"
        }
    }
    if {[llength $::problems]} { return [join $::problems "; "] }
    puts stderr "harness: $::test: every cue answered, the screen reads as it should"
    return ""
}
