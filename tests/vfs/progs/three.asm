; three — a three-page program: on the base machine, with three one-page
; processes alive, the segments are not there and exec answers ENOMEM;
; where they are, it runs and exits with 3.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 3
start:
        ld      a,3
        sys     SYS_EXIT
