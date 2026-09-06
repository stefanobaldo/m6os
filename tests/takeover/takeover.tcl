# The report is the evidence; keep it in the log on a pass too.
set show_screen 1

# After the verdict: the program wrote pattern P2 (byte i = i xor A5h) to
# the sector of M6WRITE.TST with the Nextor kernel gone. Nothing on the
# machine can read the file back; openMSX's own FAT reader can, and that
# is the host's view of the medium.
proc post_verdict {} {
    set dir $::env(M6_EXPORT)
    file delete -force $dir
    file mkdir $dir
    if {[catch {diskmanipulator export hda $dir} err]} {
        return "export from the image failed: $err"
    }
    set f [file join $dir M6WRITE.TST]
    if {![file exists $f]} { return "M6WRITE.TST is not on the volume" }
    set fh [open $f rb]
    set data [read $fh]
    close $fh
    if {[string length $data] != 512} {
        return "M6WRITE.TST is [string length $data] bytes, not 512"
    }
    binary scan $data cu* bytes
    for {set i 0} {$i < 512} {incr i} {
        set want [expr {($i & 0xFF) ^ 0xA5}]
        if {[lindex $bytes $i] != $want} {
            return [format "M6WRITE.TST byte %d is %02X, expected %02X" \
                        $i [lindex $bytes $i] $want]
        }
    }
    puts stderr "harness: $::test: M6WRITE.TST holds the sector written with the kernel out"
    return ""
}
