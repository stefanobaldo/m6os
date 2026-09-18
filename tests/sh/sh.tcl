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
    a {2 0x40} b {2 0x80} c {3 0x01} d {3 0x02} e {3 0x04} f {3 0x08}
    h {3 0x20} i {3 0x40} l {4 0x02} m {4 0x04} n {4 0x08} o {4 0x10}
    p {4 0x20} q {4 0x40} r {4 0x80} s {5 0x01} t {5 0x02} w {5 0x10}
    x {5 0x20} y {5 0x40} 0 {0 0x01} 6 {0 0x40} 7 {0 0x80} - {1 0x04}
    \\ {1 0x10} / {2 0x10} space {8 0x01} home {8 0x02} shift {6 0x01}
    ctrl {6 0x02} ret {7 0x80} up {8 0x20} down {8 0x40} left {8 0x10}
    u {5 0x04} z {5 0x80} 1 {0 0x02} 2 {0 0x04} 3 {0 0x08} 4 {0 0x10}
    5 {0 0x20} 8 {1 0x01} 9 {1 0x02} . {2 0x08}
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
proc stap {t k} {
    at $t {down shift}
    tap [expr {$t + 0.05}] $k
    at [expr {$t + 0.15}] {up shift}
}
# amp in a key list is &, SHIFT and 7 on the international layout; bar
# is |, SHIFT and backslash.
proc taps {t keys} {
    foreach k $keys {
        if {$k eq "amp"} {
            stap $t 7
        } elseif {$k eq "bar"} {
            stap $t \\
        } else {
            tap $t $k
        }
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
    # A ^C that lands while the foreground process is inside the kernel,
    # with another process runnable: spew is in the console's write nearly
    # always, spin makes the ring two, and the ^C reaches spew at the
    # write's return — or never, if giving the CPU up there lost it.
    set t [typeline [expr {$t + 1.8}] {/ t / s p i n space 6 0 0 space amp space / t / s p e w space 6 0 0}]
    ctap [expr {$t + 0.5}] c
    at [expr {$t + 2.0}] check_spew
    # SHIFT+HOME, the CLS key, at an empty prompt: the prompt alone on the
    # first row. ^L halfway through a line: the prompt and the line so far
    # there, and RET still runs the whole line.
    stap [expr {$t + 2.2}] home
    at [expr {$t + 2.8}] {check_top {/ $} "SHIFT+HOME at the prompt"}
    set t [taps [expr {$t + 3.0}] {e c h o space h i}]
    ctap $t l
    at [expr {$t + 0.6}] {check_top {/ $ echo hi} "^L halfway through a line"}
    set t [typeline [expr {$t + 0.8}] {}]
    at [expr {$t + 0.6}] {
        if {[lrange [rows] 0 2] ne {{/ $ echo hi} hi {/ $}}} {
            problem "the line redrawn by ^L did not run as echo hi"
        }
    }
    # clear: the screen holds nothing but a fresh prompt on its first row.
    set t [typeline [expr {$t + 0.8}] {c l e a r}]
    at [expr {$t + 0.6}] {check_top {/ $} "clear"}
    at [expr {$t + 0.8}] history_start
}

# The history: UP and DOWN at the prompt bring earlier lines back, on
# the prompt's row, where the line is then edited and run. Every check
# reads the last prompt row on the screen.
proc last_prompt {} {
    set rs [rows]
    for {set i 23} {$i >= 0} {incr i -1} {
        if {[string match {/ $*} [lindex $rs $i]]} { return [lindex $rs $i] }
    }
    return ""
}
proc check_prompt {want what} {
    if {[last_prompt] ne $want} { problem "$what: the prompt row reads \"[last_prompt]\", not \"$want\"" }
}
proc history_start {} {
    set t [typeline 0 {e c h o space o n e}]
    set t [typeline [expr {$t + 0.5}] {e c h o space t w o}]
    # UP brings the last line back; RET runs it: two now printed twice.
    tap [expr {$t + 0.5}] up
    at [expr {$t + 0.8}] {check_prompt {/ $ echo two} "UP after echo two"}
    tap [expr {$t + 1.0}] ret
    at [expr {$t + 1.5}] {if {[count_rows two] != 2} { problem "the line UP brought back did not run as echo two" }}
    # UP UP is the line before; DOWN forward again; DOWN past the newest
    # is the empty line, and RET on it runs nothing.
    tap [expr {$t + 1.7}] up
    tap [expr {$t + 1.9}] up
    at [expr {$t + 2.2}] {check_prompt {/ $ echo one} "UP UP"}
    tap [expr {$t + 2.4}] down
    at [expr {$t + 2.7}] {check_prompt {/ $ echo two} "DOWN after UP UP"}
    tap [expr {$t + 2.9}] down
    at [expr {$t + 3.2}] {check_prompt {/ $} "DOWN past the newest line"}
    tap [expr {$t + 3.4}] ret
    # The same line twice is stored once: UP UP after two more echo two
    # is still echo one. ^U empties the line brought back; RET runs nothing.
    set t [typeline [expr {$t + 3.8}] {e c h o space t w o}]
    set t [typeline [expr {$t + 0.5}] {e c h o space t w o}]
    tap [expr {$t + 0.5}] up
    tap [expr {$t + 0.7}] up
    at [expr {$t + 1.0}] {check_prompt {/ $ echo one} "UP UP after echo two twice"}
    ctap [expr {$t + 1.2}] u
    at [expr {$t + 1.6}] {check_prompt {/ $} "^U on the line brought back"}
    tap [expr {$t + 1.8}] ret
    # A line brought back is edited in place: LEFT three times, x, RET
    # runs echo xtwo, and UP then shows the line as it ran.
    tap [expr {$t + 2.2}] up
    set t [taps [expr {$t + 2.5}] {left left left x}]
    at [expr {$t + 0.3}] {check_prompt {/ $ echo xtwo} "x inserted in the line brought back"}
    tap [expr {$t + 0.5}] ret
    at [expr {$t + 1.0}] {expect_screen xtwo "the edited line did not run as echo xtwo"}
    tap [expr {$t + 1.2}] up
    at [expr {$t + 1.5}] {check_prompt {/ $ echo xtwo} "UP after the edited line ran"}
    ctap [expr {$t + 1.7}] u
    tap [expr {$t + 2.1}] ret
    at [expr {$t + 2.5}] history_ring
}
# Sixteen lines are kept: after echo 1 to echo 17, sixteen UPs reach
# echo 2 and one more stays there; RET runs it. Then a command reading
# the keyboard in the middle of the session sees UP dropped: cat > /t/up
# with UP, z, RET, ^D leaves z alone in the file (post_verdict reads it).
proc history_ring {} {
    set t 0
    foreach n {1 2 3 4 5 6 7 8 9} { set t [typeline $t [list e c h o space $n]] }
    foreach n {10 11 12 13 14 15 16 17} {
        set t [typeline $t [list e c h o space [string index $n 0] [string index $n 1]]]
    }
    for {set i 0} {$i < 16} {incr i} { tap [expr {$t + 0.3 + $i * 0.15}] up }
    set t [expr {$t + 0.3 + 16 * 0.15}]
    at [expr {$t + 0.3}] {check_prompt {/ $ echo 2} "sixteen UPs after seventeen lines"}
    tap [expr {$t + 0.5}] up
    at [expr {$t + 0.8}] {check_prompt {/ $ echo 2} "one more UP at the oldest line"}
    tap [expr {$t + 1.0}] ret
    set t [taps [expr {$t + 1.5}] {c a t space}]
    stap $t .
    set t [typeline [expr {$t + 0.3}] {space / t / u p}]
    tap [expr {$t + 0.5}] up
    tap [expr {$t + 0.7}] z
    tap [expr {$t + 0.9}] ret
    ctap [expr {$t + 1.2}] d
    at [expr {$t + 1.8}] more_start
}

# more: first a file whose rows wrap — 100 columns take two rows, 80
# columns two as well, the second blank, ten TABs reach column 80 and
# wrap — so the stop falls after a, and q ends it there. Then ls -l /bin
# through it: the 27 commands stop after the 23rd, tee, with the prompt
# on the last row; RET shows one more, tr; SPACE the last three and the
# shell's prompt. A second run ends at the first stop with q: the
# prompt's row holds the shell's prompt, and nothing is reported, the
# pipeline's status being more's.
set more_cmd {l s space - l space / b i n space bar space m o r e}
proc more_start {} {
    typeline 0 {m o r e space / r o w s}
    wait_for {[lindex [rows] 23] eq "--More--"} more_rows "more did not stop on a file of 24 rows"
}
proc more_rows {} {
    set rs [rows]
    set want [list [string repeat w 80] [string repeat w 20] [string repeat v 80] {} {} x a]
    if {[lrange $rs 16 22] ne $want} { problem "more did not stop after the 23rd row of /rows: [lrange $rs 16 22]" }
    tap 0.3 q
    wait_for {[lindex [rows] 23] eq {/ $}} more_ls "q at more's prompt did not end it on /rows"
}
proc more_ls {} {
    set rs [rows]
    if {[lsearch -exact $rs a] < 0 || [lsearch -exact $rs b] >= 0 || [lsearch -exact $rs "--More--"] >= 0} {
        problem "q at more's prompt did not end /rows at a, its prompt erased: [lrange $rs 18 23]"
    }
    typeline 0 $::more_cmd
    wait_for {[lindex [rows] 23] eq "--More--"} more_page "more did not stop with --More-- on the last row"
}
proc more_page {} {
    set rs [rows]
    if {![string match -nocase "* cat" [lindex $rs 0]] || ![string match -nocase "* tail" [lindex $rs 22]]} {
        problem "more's first screenful is not cat to tail: \"[lindex $rs 0]\" to \"[lindex $rs 22]\""
    }
    tap 0.3 ret
    wait_for {[string match -nocase "* tee" [lindex [rows] 22]] && [lindex [rows] 23] eq "--More--"} more_line \
        "RET at more's prompt did not show one more line, tee"
}
proc more_line {} {
    tap 0.3 space
    wait_for {[lindex [rows] 23] eq {/ $}} more_end "SPACE at more's prompt did not run to the end"
}
proc more_end {} {
    set rs [rows]
    if {[more_names $rs 4] ne {tr true uniq wc}} {
        problem "more's last screenful does not end tr true uniq wc: [more_names $rs 4]"
    }
    if {[lsearch -exact $rs "--More--"] >= 0} { problem "more's prompt was left on the screen" }
    typeline 0.3 $::more_cmd
    wait_for {[lindex [rows] 23] eq "--More--"} more_quit "more did not stop the second time"
}
proc more_quit {} {
    tap 0.3 q
    wait_for {[lindex [rows] 23] eq {/ $}} more_done "q at more's prompt did not end it"
}
proc more_done {} {
    set rs [rows]
    if {[more_names $rs 1] ne {tail}} { problem "q at more's prompt left [more_names $rs 1] last, not tail" }
    if {[lsearch -exact $rs "--More--"] >= 0} { problem "q left more's prompt on the screen" }
    set t [typeline 0.3 {e x i t}]
    at [expr {$t + 1.0}] check_relaunch
}
# more_names <rows> <n>: the names on the last n rows of ls -l, in lower
# case — a background job's report may stand between them and the prompt.
proc more_names {rs n} {
    set names {}
    foreach r $rs {
        if {[regexp {^[-d][-r][-h][-s][-a] +\d+ \S+ \S+ (\S+)$} $r -> name]} {
            lappend names [string tolower $name]
        }
    }
    return [lrange $names end-[expr {$n - 1}] end]
}
# wait_for <cond> <then> <what>: then, once cond holds, polled every 0.2 s
# for 20 s; past that the problem is recorded and then runs anyway.
proc wait_for {cond then what {left 100}} {
    if {[uplevel #0 [list expr $cond]]} { after time 0.3 $then; return }
    if {$left == 0} { problem $what; after time 0.3 $then; return }
    after time 0.2 [list wait_for $cond $then $what [expr {$left - 1}]]
}
proc check_spew {} {
    # spew's rows of dots have scrolled everything before them away; the
    # shell's report of its death is a row of its own after the last one.
    set rs [rows]
    set last -1
    for {set i 0} {$i < [llength $rs]} {incr i} {
        if {[string match {....*} [lindex $rs $i]]} { set last $i }
    }
    if {$last < 0} { problem "spew printed nothing"; return }
    if {[lsearch -exact [lrange $rs $last end] {[130]}] < 0} {
        problem "spew killed by ^C beside a running spin was not reported as 130"
    }
}
# check_top <want> <what>: a cleared screen, want on its first row and
# every other row blank.
proc check_top {want what} {
    set rs [rows]
    if {[lindex $rs 0] ne $want} { problem "$what did not leave \"$want\" alone on the first row"; return }
    foreach r [lrange $rs 1 end] {
        if {$r ne ""} { problem "$what left \"$r\" on the screen"; return }
    }
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
    # The copies the background cat, the background cp and tee made.
    foreach c {copy copy2 copy3} {
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
    # The gap program's line was matched above (r35.re wants its ok); its
    # figures are the response delay beside a cp and the copy's span with
    # the reader taking a turn per syscall; the two stamps around the
    # second cp give a copy's span alone.
    set path [exported $dir r35]
    if {![regexp {gap (\d+) span (\d+)} [slurp $path] -> gap span]} { return "/t/r35 does not hold a gap" }
    puts stderr [format "harness: %s: the largest gap between two ticks read beside a cp of 64 KB: %d ticks, %.0f ms beyond the turn, the copy taking %d ticks with the reader beside it (an emulator's figure: a hint)" \
        $::test $gap [expr {($gap - 2) * 1000.0 / 60}] $span]
    foreach t {t1 t2} {
        set path [exported $dir $t]
        if {$path eq ""} { return "/t/$t was not written" }
        set $t [string trim [slurp $path]]
    }
    puts stderr [format "harness: %s: a cp of 64 KB alone ran from tick %s to %s, %d ticks (an emulator's figure: a hint)" \
        $::test $t1 $t2 [expr {$t2 - $t1}]]
    # sleep 1 between two stamps: 60 ticks, plus the two spawns.
    foreach t {s1 s2} {
        set path [exported $dir $t]
        if {$path eq ""} { return "/t/$t was not written" }
        set $t [string trim [slurp $path]]
    }
    set ticks [expr {$s2 - $s1}]
    if {$ticks < 60 || $ticks >= 90} { return "sleep 1 ran from tick $s1 to $s2, $ticks ticks, not 60 to 89" }
    puts stderr [format "harness: %s: sleep 1 between two stamps: %d ticks" $::test $ticks]
    return ""
}
