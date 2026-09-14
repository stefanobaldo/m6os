; bigspin — loops forever in user space, like spin, but 14 KB long: what
; the shell is still loading when the first ^C of step 11 lands.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:  jr      start
        ds      14000,0
