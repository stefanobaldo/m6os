# Files the product test needs that are too large or too regular to
# commit, written by tools/mkdisk.tcl before it imports the staging
# directory: big, 65 536 bytes, what a background cat copies while
# maxgap measures; etc/bench1, sixty one-sector commands of which the
# first and the last print the kernel's tick; etc/bench2, sixty
# three-stage pipelines of which the first and the last end in a stamp.
# Only two lines of each reach the screen, so the measurement holds no
# file write and no scrolling.
set staging $::env(M6_STAGING)
set fh [open [file join $staging big] wb]
puts -nonewline $fh [string repeat [binary format c 0x5A] 65536]
close $fh
file mkdir [file join $staging etc]
set fh [open [file join $staging etc bench1] wb]
puts -nonewline $fh "/t/tick\n[string repeat "true\n" 58]/t/tick\n"
close $fh
set fh [open [file join $staging etc bench2] wb]
puts -nonewline $fh "echo x | cat | /t/stamp\n[string repeat "echo x | cat | /t/drain\n" 58]echo x | cat | /t/stamp\n"
close $fh
