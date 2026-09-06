# The test driver, run by openMSX with a test's disk image attached.
#
# The program under test reports through the mailbox, four bytes at MAILBOX
# (defined once here and once in tests/m6test.inc): "M6", then a status
# byte, then a reserved byte. A status is accepted only under the signature,
# so stale RAM can never pass. A5h is pass, 5Ah is fail. The harness never
# writes the mailbox: the TPA is overwritten while Nextor loads its files.
#
# Exit code: 0 pass, 1 fail, 2 no verdict within the real-time deadline.
# Everything printed here goes to stderr; stdout carries what the MSX side
# writes through the debug device (the test program, and C-BIOS's own
# trace lines).
#
# Environment: M6_TEST (the test's name), M6_TEST_DIR (its directory; if it
# holds <name>.tcl, that file is sourced before polling starts), M6_DEADLINE
# (optional, seconds of real time; default 60). A test's .tcl may
# `set show_screen 1` to have the text screen printed on a pass as well as
# on a failure, for a test whose report is worth keeping in the log; and it
# may define a `post_verdict` proc, called after a pass and before exit,
# returning an empty string or the reason the pass is a failure after all —
# for what the program cannot check itself, such as the disk image's
# contents seen from outside the machine.
set MAILBOX  0x8000
set PASS     0xA5
set FAIL     0x5A
# Seconds of real time before giving up; M6_DEADLINE overrides it.
set DEADLINE [expr {[info exists ::env(M6_DEADLINE)] ? $::env(M6_DEADLINE) : 60}]

set test $::env(M6_TEST)
set show_screen 0
set throttle off
set mute on

proc screen {} {
    # get_screen throws while the VDP is in a graphical mode.
    if {[catch {get_screen} s]} { return "(no text screen: $s)" }
    return $s
}

# openMSX's Tcl exit does not unwind the script; callers return after it.
proc finish {code msg} {
    if {$code == 0 && [llength [info procs post_verdict]]} {
        set why [post_verdict]
        if {$why ne ""} {
            set code 1
            set msg "FAIL after the verdict: $why"
        }
    }
    puts stderr "harness: $::test: $msg"
    if {$code != 0 || $::show_screen} { puts stderr [screen] }
    exit $code
}

after realtime $DEADLINE {
    finish 2 "no verdict within $::DEADLINE s of real time"
}

proc poll {} {
    # Page 2 may briefly map another segment while DOS loads; a read that
    # misses the signature is simply retried.
    if {[peek $::MAILBOX] == 0x4D && [peek [expr {$::MAILBOX + 1}]] == 0x36} {
        set status [peek [expr {$::MAILBOX + 2}]]
        if {$status == $::PASS} {
            finish 0 "PASS ([format %.1f [machine_info time]] s emulated)"
            return
        }
        if {$status == $::FAIL} {
            finish 1 "FAIL (status 5Ah)"
            return
        }
    }
    after time 0.1 poll
}

set extra [file join $::env(M6_TEST_DIR) "$test.tcl"]
if {[file exists $extra]} { source $extra }
after time 0.1 poll
