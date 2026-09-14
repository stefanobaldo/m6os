; spin — loops forever in user space: what ^C kills at the shell's prompt.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:  jr      start
