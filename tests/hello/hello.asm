; hello — the trivial m6 binary loaded through Nextor: an MSX-DOS 2 .COM that
; reports a pass through the mailbox, says hello through the debug device,
; and returns to the command interpreter.
        include "m6test.inc"

        org     100h

        m6_verdict M6_PASS
        m6_dbg_puts message
        ret

message:
        db      "hello from m6",10,0
