# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the legacy test. The machine boots M6.COM and the
# kernel runs /etc/rc through the shell, whose programs are raw .COM
# files run through dos; what they print goes to the screen through the
# BIOS, so the checks read rows. When the script's last line shows, this
# types at the login shell — a program that reads a line, ps, a program
# that marks its legacy page 3 and waits for a key, the disk error
# routine, a program given the shell's own page on the 128K machine and
# UP after it — and gives the verdict, since the product has no mailbox.
set show_screen 1
set problems {}
set machine [machine_info config_name]

proc problem {what} {
    lappend ::problems $what
    puts stderr "dos.tcl: $what"
}
proc rows {} {
    if {[catch {get_screen} s]} { return {} }
    set out {}
    foreach r [split $s \n] { lappend out [string trimright $r] }
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
proc expect_screen {want msg} { if {![has_row $want]} { problem $msg } }
# The row after want is next: the two on adjacent rows.
proc expect_next {want next msg} {
    set rs [rows]
    set i [lsearch -exact $rs $want]
    if {$i < 0 || [lindex $rs [expr {$i + 1}]] ne $next} { problem $msg }
}
proc expect_absent {want msg} { if {[has_row $want]} { problem $msg } }
proc count_match {re} {
    set n 0
    foreach r [rows] { if {[regexp $re $r]} { incr n } }
    return $n
}

# The block cache's headers, read from the mapper's RAM: how many buffers
# are lent to an MSX-DOS program's layer (their volume byte is VOL_LENT,
# FEh). The storage segment's number is in the kernel's record at C106h
# (K_REC + KR_SEG64K + 2), read while the kernel's page 3 is in; the
# headers are 22 rows of 8 bytes from 0800h of that segment (ST_HDR).
# The layer's address where a crossing comes back (LEG_T_XSYS, exported
# by the build): a breakpoint there, once, with the legacy page 3 in —
# the kernel's own begins "M6" and the program has cleared those bytes —
# sets the carry and EIO, which is a disk error the emulated disk never
# gives, and the program's error routine is called.
proc leg_sym {name} {
    set fh [open build/leg.exp]
    set v -1
    foreach l [split [read $fh] \n] {
        if {[regexp "^$name: EQU 0x(\[0-9A-Fa-f\]+)" $l -> h]} { set v [expr "0x$h"] }
    }
    close $fh
    if {$v < 0} { problem "build/leg.exp does not define $name" }
    return $v
}
proc disk_error_once {} {
    set ::ibp [debug set_bp [leg_sym LEG_T_XSYS] {[peek 0xC000] != 0x4D} {
        reg F [expr {[reg F] | 1}]
        reg A 5
        debug remove_bp $::ibp
    }]
}
set stseg -1
set LENT 16         ;# buffers the layer's body takes while a program runs
proc lent {} {
    set n 0
    for {set i 0} {$i < 22} {incr i} {
        if {[debug read "Main RAM" [expr {$::stseg * 0x4000 + 0x0800 + $i * 8}]] == 0xFE} { incr n }
    }
    return $n
}

# The matrix: row and mask of every key typed here (kbd_map in
# src/kernel/kbd.asm, the international layout).
array set key {
    a {2 0x40} c {3 0x01} d {3 0x02} e {3 0x04} f {3 0x08} h {3 0x20}
    i {3 0x40} l {4 0x02} m {4 0x04} n {4 0x08} o {4 0x10} p {4 0x20}
    r {4 0x80} s {5 0x01}
    t {5 0x02} w {5 0x10} x {5 0x20} y {5 0x40} 7 {0 0x80} / {2 0x10}
    . {2 0x08} space {8 0x01} ret {7 0x80} arrow {8 0x20}
}
proc down {k} { keymatrixdown {*}$::key($k) }
proc up {k}   { keymatrixup   {*}$::key($k) }
proc at {t script} { after time $t $script }
proc tap {t k} {
    at $t [list down $k]
    at [expr {$t + 0.07}] [list up $k]
}
proc taps {t keys} {
    foreach k $keys {
        tap $t $k
        set t [expr {$t + 0.15}]
    }
    return $t
}
proc typeline {t keys} {
    set t [taps $t $keys]
    tap $t ret
    return [expr {$t + 0.15}]
}

# The script's end: the login shell's prompt is on the screen.
set stamps {}
proc wait_rc {} {
    if {[has_row "rc done"] && [has_row {/ $}]} {
        puts stderr "dos.tcl: rc done at [format %.2f [machine_info time]] s"
        foreach r [rows] { if {[string is integer -strict $r]} { lappend ::stamps $r } }
        set ::stseg [peek 0xC106]
        check_rc
        type_at_shell
        return
    }
    after time 0.2 wait_rc
}
after time 0.5 wait_rc

proc check_rc {} {
    expect_screen "rc start" "rc start not on the screen"
    expect_screen "dosarg ok" "dosenter did not refuse what it must (dosarg)"
    if {[lent] != 0} { problem "[lent] cache buffers still lent after the script's programs ended" }
    expect_screen {[7]} "exit7's _TERM with 7 was not reported as \[7\]"
    expect_screen "jp0" "jp0 did not print before its jp 0"
    expect_screen "ret" "ret did not print before its ret"
    expect_next "ret" "noeol" "ret's line, which ends in CR LF, is not followed at once by the next program's"
    expect_next "noeol" "after noeol" "the line after noeol, which ends in the middle of a line, is not on the row below it"
    expect_screen "wboot twice" "wboot's ret and _TERM did not both reach its WBOOT jump through 0000h"
    expect_screen {[5]} "wboot's _TERM with 5 was not reported as \[5\] after its jp 0"
    # On the 128K machine the segment is the script's shell's, lent: the
    # lines after it run only if its bytes came back.
    expect_screen "mapper ok seg" "the mapper program did not end in mapper ok seg"
    expect_screen "dos: nofile.com: ENOENT" "the shell's .com fallback did not reach dos for a missing file"
    set hellos [count_rows "hello from dos"]
    if {$::machine eq "m6-msx2-128k"} {
        expect_screen "dos: /dos/hello.com: ENOMEM" "the launch beside a live sleep was not refused with ENOMEM on the 128K machine"
        if {$hellos != 2} { problem "hello from dos printed $hellos times, not 2, on the 128K machine" }
    } else {
        expect_absent "dos: /dos/hello.com: ENOMEM" "the launch beside a live sleep was refused on the 4 MB machine"
        if {$hellos != 3} { problem "hello from dos printed $hellos times, not 3, on the 4 MB machine" }
    }
    # The console line's figure, a hint: the row conout 10000: N ticks.
    set found 0
    foreach r [rows] {
        if {[regexp {^conout 10000: (\d+) ticks$} $r -> n]} {
            set found 1
            puts stderr [format "harness: %s: 10 000 _CONOUTs through the BIOS: %d ticks, %.1f ms each (an emulator's figure: a hint)" $::test $n [expr {$n * 1000.0 / 60 / 10000}]]
        }
    }
    if {!$found} { problem "con10k did not print its ticks" }
}

proc type_at_shell {} {
    # A line read by _BUFIN and written back with its length.
    set t [typeline 0.5 {d o s space / d o s / e c h o . c o m}]
    set t [typeline [expr {$t + 1.5}] {t y p e d space l i n e}]
    at [expr {$t + 1.0}] {expect_screen "typed line 10" "the line typed into _BUFIN did not come back with its length"}
    # ps: init, the shell, ps itself, and nothing else — the programs'
    # rows and segments are gone.
    set t [typeline [expr {$t + 1.2}] {p s}]
    at [expr {$t + 1.0}] check_ps
    # The swap: M6 in the legacy page 3 while the program waits, the
    # kernel's own bytes there once the prompt is back.
    set t [typeline [expr {$t + 1.2}] {d o s space / d o s / s w a p . c o m}]
    at [expr {$t + 1.5}] {
        expect_screen "swap: M6 at C000h, press a key" "swap did not print its line"
        if {[peek 0xC000] != 0x4D || [peek 0xC001] != 0x36} {
            problem [format "C000h reads %02X %02X while the program runs, not M6: the legacy page 3 is not in" [peek 0xC000] [peek 0xC001]]
        }
        if {[lent] != $::LENT} { problem "[lent] cache buffers lent while the program runs, not $::LENT" }
    }
    tap [expr {$t + 1.7}] space
    at [expr {$t + 2.7}] {
        if {[peek 0xC000] == 0x4D && [peek 0xC001] == 0x36} {
            problem "C000h still reads M6 after the program ended: the kernel's page 3 is not back"
        }
        if {[lindex [rows] end] ne {} && ![has_row {/ $}]} { problem "no prompt after swap" }
        if {[lent] != 0} { problem "[lent] cache buffers still lent after the program ended" }
    }
    # The disk error routine, in the program's page 2: handed back, then
    # made again.
    set t [typeline [expr {$t + 3.2}] {d o s space / d o s / d e f e r . c o m}]
    at [expr {$t + 1.5}] {
        expect_screen "defer: one, press a key" "defer did not print its first line"
        disk_error_once
    }
    tap [expr {$t + 1.7}] space
    at [expr {$t + 2.7}] {
        expect_screen "defer: two, press a key" "the error was not handed back to defer's _OPEN, or its routine did not run"
        disk_error_once
    }
    tap [expr {$t + 2.9}] space
    at [expr {$t + 4.2}] {
        expect_screen "defer ok" "defer's _OPEN was not made again after its routine asked for it"
    }
    # The login shell's page lent to a program on the 128K machine, and
    # its history there after: UP brings the line back. The spaces the
    # keys above left in the keyboard's buffer come with it.
    set t [typeline [expr {$t + 4.4}] {d o s space / d o s / m a p p e r . c o m}]
    at [expr {$t + 4.0}] {
        set ::before [count_match {^/ \$ +dos /dos/mapper\.com$}]
        if {[count_rows "mapper ok seg"] < 1} { problem "mapper at the login shell did not end in mapper ok seg" }
    }
    tap [expr {$t + 4.1}] arrow
    at [expr {$t + 4.8}] {
        if {[count_match {^/ \$ +dos /dos/mapper\.com$}] != $::before + 1} {
            problem "UP after mapper at the login shell did not bring its line back: the shell's history is lost"
        }
        finish_up
    }
}

proc check_ps {} {
    set rs [rows]
    set i [lsearch -exact $rs "PID PPID ST PG"]
    if {$i < 0} { problem "ps printed no header"; return }
    set body [lrange $rs [expr {$i + 1}] end]
    set n 0
    foreach r $body {
        if {[regexp {^ *\d+ +(\d+|-) +[A-Z] +\d+$} $r]} { incr n } else { break }
    }
    if {$n != 3} { problem "ps shows $n rows, not 3 (init, the shell, ps)" }
    if {[lindex $body $n] ne {/ $}} { problem "no prompt after ps's rows" }
}

proc finish_up {} {
    if {[llength $::stamps] == 2} {
        set ticks [expr {[lindex $::stamps 1] - [lindex $::stamps 0]}]
        puts stderr [format "harness: %s: dos of a 30K program, sixty in a row: %d ticks, %.1f ms each, a ceiling on the 600 ms line (an emulator's figure: a hint)" \
            $::test $ticks [expr {$ticks * 1000.0 / 60 / 58}]]
    } else {
        problem "[llength $::stamps] stamps on the screen, not 2"
    }
    if {[llength $::problems]} {
        finish 1 "FAIL: [join $::problems {; }]"
    } else {
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
    }
}
