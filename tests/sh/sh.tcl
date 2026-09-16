# m6 — a Unix-like operating system for the MSX
# Copyright (c) 2026 Stefano Baldo
# SPDX-License-Identifier: BSD-3-Clause
#
# The harness's half of the product test. The machine boots M6.COM and
# the kernel runs /etc/rc through the shell; when the script's last line
# shows on the screen, the login shell is up, and this types at it the
# way a person would — a command, a failing one, a cat killed by ^C, and
# exit, after which init starts the shell again — then gives the
# verdict, since the product has no mailbox. After it, the files the
# script wrote are exported from the image and compared with what they
# should hold, and the bench scripts' stamps become the two latency
# figures, hints in the emulator.
set show_screen 1
set problems {}

proc problem {what} {
    lappend ::problems $what
    puts stderr "sh.tcl: $what"
}
proc rows {} {
    # get_screen throws while the VDP is in a graphical mode, which it is
    # while the machine boots.
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

# The matrix: row and mask of every key typed here (kbd_map in
# src/kernel/kbd.asm, the international layout).
array set key {
    a {2 0x40} c {3 0x01} d {3 0x02} e {3 0x04} f {3 0x08} h {3 0x20}
    i {3 0x40} l {4 0x02} o {4 0x10} p {4 0x20} s {5 0x01} t {5 0x02}
    x {5 0x20} y {5 0x40} space {8 0x01} ctrl {6 0x02} ret {7 0x80}
}
proc down {k} { keymatrixdown {*}$::key($k) }
proc up {k}   { keymatrixup   {*}$::key($k) }
proc at {t script} { after time $t $script }
proc tap {t k} {
    at $t [list down $k]
    at [expr {$t + 0.07}] [list up $k]
}
proc ctap {t k} {
    at $t {down ctrl}
    tap [expr {$t + 0.05}] $k
    at [expr {$t + 0.15}] {up ctrl}
}
proc taps {t keys} {
    foreach k $keys { tap $t $k; set t [expr {$t + 0.15}] }
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
        puts stderr "sh.tcl: rc done at [format %.2f [machine_info time]] s"
        # The bench scripts' four stamps, rows holding nothing but a number,
        # read now, before anything scrolls them off.
        foreach r [rows] { if {[string is integer -strict $r]} { lappend ::stamps $r } }
        # The script's own reports: cat's status after the missing file,
        # false's, and the shell's message for a command that is not there.
        if {[count_rows {[1]}] < 2} { problem "fewer than two \[1\] reports from the script" }
        expect_screen "sh: nofile: ENOENT" "no message for the command that is not there"
        type_at_shell
        return
    }
    after time 0.2 wait_rc
}
after time 0.5 wait_rc

proc type_at_shell {} {
    set n1 [count_rows {[1]}]
    set t [typeline 0.5 {e c h o space t y p e d}]
    at [expr {$t + 0.6}] {expect_screen "typed" "echo typed did not print typed"}
    set t [typeline [expr {$t + 0.8}] {f a l s e}]
    at [expr {$t + 0.6}] [list check_false $n1]
    set t [typeline [expr {$t + 0.8}] {c a t}]
    ctap [expr {$t + 0.8}] c
    at [expr {$t + 1.6}] {expect_screen {[130]} "cat killed by ^C was not reported as 130"}
    set t [typeline [expr {$t + 1.8}] {e x i t}]
    at [expr {$t + 1.0}] check_relaunch
}
proc check_false {n1} {
    if {[count_rows {[1]}] <= $n1} { problem "false typed at the prompt was not reported as \[1\]" }
}
proc check_relaunch {} {
    # The row after "/ $ exit" is a fresh prompt: init started the shell again.
    set rs [rows]
    set i [lsearch -exact $rs {/ $ exit}]
    if {$i < 0} {
        problem "exit was not echoed at the prompt"
    } elseif {[lindex $rs [expr {$i + 1}]] ne {/ $}} {
        problem "no fresh prompt after exit: init did not start the shell again"
    }
    if {[llength $::problems]} {
        finish 1 "FAIL: [join $::problems {; }]"
    } else {
        finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
    }
}

# exported <dir> <name>: the exported file's path, whichever case the
# exporter used for the name.
proc exported {dir name} {
    foreach n [list $name [string toupper $name]] {
        if {[file exists [file join $dir $n]]} { return [file join $dir $n] }
    }
    return ""
}
proc slurp {path} {
    set fh [open $path rb]
    set data [read $fh]
    close $fh
    return $data
}

proc post_verdict {} {
    set dir $::env(M6_EXPORT)
    file delete -force $dir
    file mkdir $dir
    diskmanipulator chdir hda t
    if {[catch {diskmanipulator export hda $dir} err]} { return "export of /t failed: $err" }
    diskmanipulator chdir hda /
    # The files against their expected contents.
    set expdir [file join $::env(M6_TEST_DIR) expect]
    foreach f [lsort [glob -directory $expdir -tails *]] {
        set want [slurp [file join $expdir $f]]
        # A file whose expected contents end in .re holds one pattern
        # per line, each matched whole against the line it stands for:
        # the form for a listing whose time is the host clock's.
        set pat [string match *.re $f]
        if {$pat} { set f [file rootname $f] }
        set path [exported $dir $f]
        if {$path eq ""} { return "/t/$f was not written" }
        set got [slurp $path]
        if {!$pat} {
            if {$got ne $want} {
                return "/t/$f holds \"[string map {\n \\n} $got]\", not \"[string map {\n \\n} $want]\""
            }
            continue
        }
        set gl [split [string trimright $got \n] \n]
        set wl [split [string trimright $want \n] \n]
        if {[llength $gl] != [llength $wl]} {
            return "/t/$f has [llength $gl] lines, not [llength $wl]: \"[string map {\n \\n} $got]\""
        }
        foreach g $gl p $wl {
            if {![regexp -- "^(?:$p)\$" $g]} { return "/t/$f line \"$g\" does not match \"$p\"" }
        }
    }
    puts stderr "harness: $::test: [llength [glob -directory $expdir -tails *]] files under /t hold what the script should have written"
    # The copies the background cat and the background cp made.
    foreach c {copy copy2} {
        set path [exported $dir $c]
        if {$path eq ""} { return "/t/$c was not written" }
        set data [slurp $path]
        if {[string length $data] != 65536} { return "/t/$c is [string length $data] bytes, not 65536" }
        if {$data ne [string repeat [binary format c 0x5A] 65536]} { return "/t/$c does not hold big's bytes" }
    }
    # The two latency figures, from the bench scripts' stamps: the first
    # and the last of sixty lines, 59 intervals between them.
    if {[llength $::stamps] != 4} { return "[llength $::stamps] stamps on the screen, not 4" }
    foreach {i label target} {0 "a one-sector command" 50 2 "a three-stage pipeline" 100} {
        set ticks [expr {[lindex $::stamps [expr {$i + 1}]] - [lindex $::stamps $i]}]
        puts stderr [format "harness: %s: %s, sixty in a row: %d ticks, %.1f ms each, a ceiling on the %d ms line (an emulator's figure: a hint)" \
            $::test $label $ticks [expr {$ticks * 1000.0 / 60 / 59}] $target]
    }
    # The gap program prints the largest gap and the first and last tick
    # it read, so a reading that began after the copy had ended shows
    # itself; the two stamps around the cp give the copy's own span.
    foreach {g what} {gap cat} {
        set path [exported $dir $g]
        if {$path eq ""} { return "/t/$g was not written" }
        if {![regexp {gap (\d+) (\d+) (\d+)} [slurp $path] -> gap from to]} { return "/t/$g does not hold a gap" }
        puts stderr [format "harness: %s: the largest gap between two ticks read beside a background %s: %d ticks, %.0f ms beyond the turn, reading from tick %d to %d (an emulator's figure: a hint)" \
            $::test $what $gap [expr {($gap - 2) * 1000.0 / 60}] $from $to]
    }
    foreach t {t1 t2} {
        set path [exported $dir $t]
        if {$path eq ""} { return "/t/$t was not written" }
        set $t [string trim [slurp $path]]
    }
    puts stderr [format "harness: %s: the background cp of 64 KB ran from tick %s to %s, %d ticks, and held the CPU throughout: it has no user code between one syscall and the next for a tick to land in (an emulator's figure: a hint)" \
        $::test $t1 $t2 [expr {$t2 - $t1}]]
    return ""
}
