; tsh — the test shell, the shape of the shell to come: it ignores SIGINT,
; puts the terminal in canonical mode and prints "$ " before every line,
; and runs each line as /bin/<name> in the foreground — asking spawnv for
; a child that takes SIGINT by default, so that a ^C kills the command
; while the shell, whose guard never comes down, reads on — then waits and
; prints "[status]". An empty line prints "!" (what a ^C nobody took turns
; into); a name that does not run prints "?"; "q" exits 9; an end of file
; exits 8.
        include "kernel/kernel.inc"
        include "m6prog.inc"
        m6_header 1
start:
        ld      a,SIGINT
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
.loop:  xor     a
        sys     SYS_TTYMODE             ; canonical before every prompt
        m6_puts prompt
        xor     a
        ld      hl,line
        ld      bc,60
        sys     SYS_READ
        jp      c,.err
        ld      a,h
        or      l
        jp      z,.eof
        ld      de,line
        add     hl,de
        dec     hl
        ld      a,(hl)
        cp      10
        jr      z,.cut
        inc     hl
.cut:   ld      (hl),0                  ; the LF off, the name terminated
        ld      a,(line)
        or      a
        jr      z,.empty
        cp      'q'
        jr      nz,.run
        ld      a,(line+1)
        or      a
        jr      nz,.run
        ld      a,9
        sys     SYS_EXIT
.empty: m6_puts bang
        jp      .loop
.run:   ld      hl,line
        ld      de,path+5
.cp:    ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        or      a
        jr      nz,.cp
        ld      hl,path
        ld      de,argv
        ld      bc,m_inh
        ld      a,SIGIGN_INT            ; the child takes ^C; the shell keeps
        sys     SYS_SPAWNV              ; ignoring it throughout the load
        jp      c,.what
        ld      b,0
        sys     SYS_WAITPID
        jp      c,.what
        push    hl
        m6_puts lbr
        pop     hl
        ld      h,0
        call    m6_dec16
        m6_puts rbr
        jp      .loop
.what:  m6_puts qmark
        jp      .loop
.eof:   ld      a,8
        sys     SYS_EXIT
.err:   ld      a,1
        sys     SYS_EXIT
        m6_proglib
prompt: db      "$ ",0
bang:   db      "!",10,0
qmark:  db      "?",10,0
lbr:    db      "[",0
rbr:    db      "]",10,0
m_inh:  db      0FFh,0FFh,0FFh
argv:   dw      line,0
path:   db      "/bin/"
        ds      60
line:   ds      64
