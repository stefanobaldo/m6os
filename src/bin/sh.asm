; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; sh [-i] — the shell: commands read from descriptor 0 to its end, one
; line at a time; with -i, a prompt before each — the current directory
; and "$ " — the terminal put in canonical mode first, and the jobs that
; ended reported. A line is words separated by blanks, with '...' and
; "..." taken as they are, and # ending it; | joins commands into a
; pipeline of at most four; <, >, >> and 2> take the next word as a
; file; ; separates lists; a trailing & runs the list in the background
; and prints its pid. A word with * or ? is matched against the names in
; its directory, in the order they are stored; one matching nothing is
; kept as written. A name without / is /bin/name. cd [dir] and exit [n]
; are the shell's own. A foreground list's status, when not 0, is
; printed as [N] — 128 + the signal for a command a signal ended. In -i
; mode the shell ignores SIGINT and the commands it starts take it by
; default, so ^C ends the command and the prompt comes back; without -i
; the shell takes SIGINT and a ^C ends the script.
;
; In -i mode the shell keeps the last HIST lines it ran, in memory, and
; UP and DOWN at the prompt bring them back: the terminal is put in
; recall mode before each prompt, so an arrow ends the read with its
; byte alone on the line, the shell picks the line it names and puts it
; in place with ttyline, and reads on — the line is edited like any
; other and stored as it ran. A line of no words, or the same as the
; last one stored, is not stored. The terminal goes back to canonical
; before the line's commands run, so a command reading the keyboard
; sees the arrows dropped as always.
        include "kernel/kernel.inc"
        include "lib/prog.inc"

NTOK    equ     40                      ; tokens in a line
NARG    equ     32                      ; words in a command, the 0 included
NSTAGE  equ     4                       ; stages in a pipeline
LINE    equ     ARGV_MAX                ; the line, its 0 included: a longer
                                        ; one could never run
XBUF    equ     ARGV_MAX                ; expansions of one command
HIST    equ     16                      ; lines kept, each a slot of TTY_LINE:
                                        ; the terminal's line is at most that

T_END   equ     0                       ; the tokens
T_WORD  equ     1
T_PIPE  equ     2
T_SEMI  equ     3
T_AMP   equ     4
T_IN    equ     5
T_OUT   equ     6
T_APP   equ     7
T_ERR   equ     8
T_QUOTE equ     80h                     ; a word that had quotes: no glob

        m6_prog 1
main:   xor     a
        ld      (interactive),a
        ld      a,b
        or      c
        jr      z,.noargs
        dec     bc
        ld      a,b
        or      c
        jr      z,.noargs
        inc     hl
        inc     hl
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ld      hl,s_dashi
        call    str_cmp
        jr      nz,.noargs
        ld      a,1
        ld      (interactive),a
        xor     a
        ld      (hist_n),a              ; nothing kept yet
        ld      (hist_w),a
        ld      a,SIGINT
        ld      b,SIG_IGN
        sys     SYS_SIGNAL
.noargs:
        xor     a
        call    in_open
.line:  ld      a,(interactive)
        or      a
        jr      z,.read
        call    reap
        ld      a,TTY_RECALL
        sys     SYS_TTYMODE
        xor     a
        ld      (hist_i),a              ; at the line being typed
        ld      hl,cwd
        ld      bc,LINE
        sys     SYS_GETCWD
        ld      hl,cwd
        jr      nc,.prompt
        ld      hl,s_q
.prompt:
        call    out_puts
        ld      hl,s_prompt
        call    out_puts
        call    out_flush
.read:  ld      de,line
        ld      bc,LINE
        call    in_line
        jr      c,.eof
        ld      a,(interactive)
        or      a
        jr      z,.whole
        ld      a,b                     ; a line of one byte that is an
        or      a                       ; arrow: the history, not a command
        jr      nz,.whole
        ld      a,c
        dec     a
        jr      nz,.whole
        ld      a,(line)
        cp      1Eh                     ; UP
        jr      z,.up
        cp      1Fh                     ; DOWN
        jr      z,.down
.whole: ld      a,(in_cut)
        or      a
        jr      z,.run
        ld      de,s_long
        call    err_msg
        jr      .line
.run:   call    hist_save               ; the line as typed, before tokenize
        call    tokenize                ; cuts it up
        jr      c,.line
        call    hist_keep
        call    run
        jr      .line
.eof:   xor     a
        ret
; UP: one line further back, unless at the oldest; DOWN: one nearer,
; the line being typed — empty — at 0. Either puts the slot's line in
; the terminal's with ttyline and reads on, the prompt still there.
.up:    ld      a,(hist_i)
        ld      hl,hist_n
        cp      (hl)
        jr      nc,.read                ; at the oldest: nothing
        inc     a
        ld      (hist_i),a
        jr      .recall
.down:  ld      a,(hist_i)
        or      a
        jr      z,.read                 ; at the line being typed: nothing
        dec     a
        ld      (hist_i),a
        jr      z,.blank
.recall:
        ld      a,(hist_w)
        ld      hl,hist_i
        sub     (hl)
        call    hist_slot               ; hl -> the line, hist_i back
        call    str_len                 ; bc = its length
        sys     SYS_TTYLINE
        jr      .read
.blank: ld      bc,0
        sys     SYS_TTYLINE             ; hl: nothing read from it
        jr      .read

; hist_slot — A = a slot number, any: HL -> its line, HIST slots round.
; Corrupts AF, DE.
hist_slot:
        and     HIST-1
        ld      l,0
        srl     a
        rr      l
        ld      h,a                     ; hl = a * 128
        ld      de,hist
        add     hl,de
        ret

; hist_save — the line as typed into the slot the next line goes to, in
; -i mode: tokenize cuts the line up in place, so before it. Corrupts
; everything.
hist_save:
        ld      a,(interactive)
        or      a
        ret     z
        ld      a,(hist_w)
        call    hist_slot
        ex      de,hl
        ld      hl,line
        jp      str_copy                ; at most TTY_LINE-1 bytes and its 0

; hist_keep — after tokenize: the slot hist_save filled becomes the
; newest line, unless the line had no word or is the newest one again.
; Corrupts everything.
hist_keep:
        ld      a,(interactive)
        or      a
        ret     z
        ld      a,(tok_kind)
        or      a                       ; T_END first: no word
        ret     z
        ld      a,(hist_n)
        or      a
        jr      z,.new
        ld      a,(hist_w)
        dec     a
        call    hist_slot               ; the newest
        push    hl
        ld      a,(hist_w)
        call    hist_slot               ; the candidate
        pop     de
        call    str_cmp
        ret     z                       ; the same again: dropped
.new:   ld      a,(hist_w)
        inc     a
        and     HIST-1
        ld      (hist_w),a
        ld      a,(hist_n)
        cp      HIST
        ret     z
        inc     a
        ld      (hist_n),a
        ret

; --- the tokens ----------------------------------------------------------
; tokenize — the line cut into tokens in place: tok_kind and tok_ptr,
; ntok of them, the last T_END. CF set and a message when the line has
; too many.
tokenize:
        xor     a
        ld      (ntok),a
        ld      hl,line
.skip:  ld      a,(hl)
        or      a
        jp      z,.end
        cp      '#'
        jp      z,.end
        cp      ' '
        jr      z,.blank
        cp      9
        jr      z,.blank
        cp      '|'
        ld      c,T_PIPE
        jr      z,.one
        cp      ';'
        ld      c,T_SEMI
        jr      z,.one
        cp      '&'
        ld      c,T_AMP
        jr      z,.one
        cp      '<'
        ld      c,T_IN
        jr      z,.one
        cp      '>'
        jr      z,.out
        cp      '2'
        jr      nz,.word
        inc     hl
        ld      a,(hl)
        dec     hl
        cp      '>'
        jr      nz,.word
        inc     hl
        ld      c,T_ERR
        jr      .one
.out:   inc     hl
        ld      a,(hl)
        dec     hl
        ld      c,T_OUT
        cp      '>'
        jr      nz,.one
        inc     hl
        ld      c,T_APP
.one:   inc     hl
.add1:  push    hl
        ld      hl,0
        ld      a,c
        call    tok_add
        pop     hl
        jp      c,.full
        jp      .skip
.blank: inc     hl
        jr      .skip
.word:  ld      d,h
        ld      e,l                     ; de = where the word is written
        push    hl                      ; its start
        ld      b,T_WORD
.char:  ld      a,(hl)
        or      a
        jr      z,.wend
        cp      ' '
        jr      z,.wend
        cp      9
        jr      z,.wend
        cp      '|'
        jr      z,.wend
        cp      ';'
        jr      z,.wend
        cp      '&'
        jr      z,.wend
        cp      '<'
        jr      z,.wend
        cp      '>'
        jr      z,.wend
        cp      '"'
        jr      z,.quote
        cp      27h
        jr      z,.quote
        ld      (de),a
        inc     de
        inc     hl
        jr      .char
.quote: ld      c,a                     ; the quote to look for
        ld      b,T_WORD|T_QUOTE
        inc     hl
.inq:   ld      a,(hl)
        or      a
        jr      z,.wend                 ; unterminated: the line's end
        cp      c
        jr      z,.unq
        ld      (de),a
        inc     de
        inc     hl
        jr      .inq
.unq:   inc     hl
        jr      .char
.wend:  ld      c,a                     ; what ended the word
        xor     a
        ld      (de),a
        ld      a,c
        or      a
        jr      z,.last
        inc     hl                      ; past the terminator, if not the 0
.last:  ex      (sp),hl                 ; hl = the word, (sp) = after it
        ld      a,b
        push    bc
        call    tok_add
        pop     bc
        pop     hl
        jr      c,.full
        ld      a,c                     ; the terminator, dispatched: the
        or      a                       ; word's 0 now sits where it was
        jr      z,.end
        cp      ' '
        jp      z,.skip
        cp      9
        jp      z,.skip
        ld      c,T_PIPE
        cp      '|'
        jr      z,.add1
        ld      c,T_SEMI
        cp      ';'
        jp      z,.add1
        ld      c,T_AMP
        cp      '&'
        jp      z,.add1
        ld      c,T_IN
        cp      '<'
        jp      z,.add1
        ld      c,T_OUT                 ; '>', or '>>' with the next
        ld      a,(hl)
        cp      '>'
        jp      nz,.add1
        inc     hl
        ld      c,T_APP
        jp      .add1
.end:   xor     a                       ; T_END
        ld      hl,0
        call    tok_add
        ret     nc
.full:  ld      de,s_words
        call    err_msg
        scf
        ret

; tok_add — A = the kind, HL = the word: appended. CF when full.
tok_add:
        push    hl
        ld      hl,ntok
        ld      c,(hl)
        ld      b,0
        ld      l,c
        ld      h,b
        ld      de,tok_kind
        add     hl,de
        ld      (hl),a
        ld      hl,tok_ptr
        add     hl,bc
        add     hl,bc
        pop     de
        ld      (hl),e
        inc     hl
        ld      (hl),d
        ld      a,c
        inc     a
        ld      (ntok),a
        cp      NTOK
        ccf                             ; CF when a = NTOK
        ret

; tok_get — the token at tok_i: A = its kind, HL = its word; tok_i
; advanced.
tok_get:
        ld      a,(tok_i)
        ld      c,a
        ld      b,0
        inc     a
        ld      (tok_i),a
        ld      hl,tok_kind
        add     hl,bc
        ld      a,(hl)
        ld      hl,tok_ptr
        add     hl,bc
        add     hl,bc
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        ret

; --- the lists ------------------------------------------------------------
; run — every list of the line. The terminal back in canonical mode
; first: the commands see the arrows dropped, as every program does.
run:    xor     a
        sys     SYS_TTYMODE
        xor     a
        ld      (tok_i),a
run_list:
        ; Background? The list's end, looked ahead: & or not.
        ld      a,(tok_i)
        ld      c,a
        ld      b,0
        ld      hl,tok_kind
        add     hl,bc
        xor     a
        ld      (bg),a
.look:  ld      a,(hl)
        and     7Fh
        or      a
        jr      z,.looked               ; T_END
        cp      T_SEMI
        jr      z,.looked
        cp      T_AMP
        jr      nz,.next
        ld      a,1
        ld      (bg),a
        jr      .looked
.next:  inc     hl
        jr      .look
.looked:
        xor     a
        ld      (nstage),a
        ld      a,0FFh
        ld      (prev_r),a
        call    stage_begin
.tok:   call    tok_get
        ld      c,a
        and     7Fh
        jr      z,.end                  ; T_END
        cp      T_SEMI
        jr      z,.semi
        cp      T_AMP
        jr      z,.semi
        cp      T_PIPE
        jr      z,.pipe
        cp      T_WORD
        jr      z,.word
        ; a redirection: the next token must be a word
        ld      (rkind),a
        call    tok_get
        and     7Fh
        cp      T_WORD
        jr      nz,.syntax
        ld      a,(rkind)
        cp      T_IN
        jr      z,.rin
        cp      T_ERR
        jr      z,.rerr
        ld      (r_out),hl
        ld      a,(rkind)
        cp      T_APP
        ld      a,0
        jr      nz,.app
        inc     a
.app:   ld      (r_app),a
        jr      .tok
.rin:   ld      (r_in),hl
        jr      .tok
.rerr:  ld      (r_err),hl
        jr      .tok
.word:  ld      a,c
        call    add_word
        jr      c,.abort
        jr      .tok
.pipe:  ld      a,(argc_s)
        or      a
        jr      z,.syntax
        ld      a,(nstage)
        cp      NSTAGE-1
        jr      c,.more
        ld      de,s_stages
        call    err_msg
        jr      .abort
.more:  xor     a                       ; not the last
        call    spawn_stage
        jr      .tok
.semi:  call    finish
        jp      run_list
.end:   call    finish
        ret
.syntax:
        ld      de,s_syntax
        call    err_msg
.abort: ; the line is dropped: the stages already running get their EOF
        ld      a,(prev_r)
        cp      0FFh
        jr      z,.waitall
        sys     SYS_CLOSE
.waitall:
        xor     a
        ld      (bg),a
        call    wait_list
        scf
        ret

; finish — the list's last stage, then the wait.
finish: ld      a,(argc_s)
        or      a
        jr      nz,.spawn
        ld      a,(nstage)
        or      a
        ret     z                       ; an empty list
        ld      de,s_syntax             ; "a |" with nothing after
        call    err_msg
        jp      wait_list
.spawn: ld      a,1                     ; the last
        call    spawn_stage
        jp      wait_list

; stage_begin — a fresh command: no words, no redirections, the
; expansion area empty.
stage_begin:
        xor     a
        ld      (argc_s),a
        ld      hl,0
        ld      (r_in),hl
        ld      (r_out),hl
        ld      (r_err),hl
        ld      (r_app),a
        ld      hl,xbuf
        ld      (xptr),hl
        ret

; --- the words ------------------------------------------------------------
; add_word — A = the kind, HL = the word: into argv, expanded when it
; holds * or ? and was not quoted. CF when the command is full.
add_word:
        bit     7,a
        jr      nz,argv_add
        push    hl
.scan:  ld      a,(hl)
        or      a
        jr      z,.plain
        cp      '*'
        jr      z,.glob
        cp      '?'
        jr      z,.glob
        inc     hl
        jr      .scan
.plain: pop     hl
        jr      argv_add
.glob:  pop     hl
        jr      glob

; argv_add — HL = a word: the next slot of argv. CF and a message when
; the command is full.
argv_add:
        ld      a,(argc_s)
        cp      NARG-1
        jr      nc,.full
        ld      c,a
        ld      b,0
        inc     a
        ld      (argc_s),a
        push    hl
        ld      hl,argv
        add     hl,bc
        add     hl,bc
        pop     de
        ld      (hl),e
        inc     hl
        ld      (hl),d
        or      a
        ret
.full:  ld      de,s_args
        call    err_msg
        scf
        ret

; glob — HL = a word with * or ?: every name in its directory that
; matches, in the directory's order, each as a word; the word itself
; when nothing does or the directory does not open. CF when the
; expansions overflow.
glob:   ld      (gword),hl
        ld      d,h
        ld      e,l
        ld      bc,0                    ; bc = the last '/' (0: none)
.slash: ld      a,(de)
        or      a
        jr      z,.split
        cp      '/'
        jr      nz,.nexts
        ld      b,d
        ld      c,e
.nexts: inc     de
        jr      .slash
.split: ld      a,b
        or      c
        jr      nz,.dir
        ld      (gpat),hl               ; no '/': the pattern is the word,
        ld      hl,s_dot                ; the directory is .
        ld      (gpre),bc               ; nothing before a name
        jr      .open
.dir:   inc     bc
        ld      (gpat),bc               ; the pattern after the '/'
        dec     bc
        push    bc
        ld      de,path                 ; the directory part, 0-terminated
.copy:  ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        push    hl
        or      a
        sbc     hl,bc
        pop     hl
        jr      c,.copy
        jr      z,.copy                 ; up to the '/' inclusive
        xor     a
        ld      (de),a
        pop     bc
        inc     bc
        ld      hl,(gword)
        push    hl
        ; the prefix is the word up to and including the '/': its length
        push    bc
        pop     hl
        pop     de
        or      a
        sbc     hl,de                   ; hl = the prefix's length
        ld      (gpre),hl
        ld      hl,path
        ld      a,(path+1)
        or      a
        jr      nz,.open
        ld      a,(path)
        cp      '/'
        jr      nz,.open                ; "/" alone stays "/"
.open:  xor     a
        sys     SYS_OPEN
        jr      c,.literal
        ld      (gfd),a
        xor     a
        ld      (gmatched),a
.entry: ld      a,(gfd)
        ld      hl,dirent
        sys     SYS_READDIR
        jr      c,.close
        ld      a,h
        or      l
        jr      z,.close
        ld      hl,dirent+DE_NAME
        ld      a,(hl)
        cp      '.'
        jr      nz,.try
        ld      de,(gpat)
        ld      a,(de)
        cp      '.'
        jr      nz,.entry               ; a name with a dot first needs one
.try:   ld      de,(gpat)
        call    match
        or      a
        jr      z,.entry
        ; a match: the prefix, the name, a 0, into the expansion area
        ld      de,(xptr)
        ld      hl,(gword)
        ld      bc,(gpre)
        ld      a,b
        or      c
        jr      z,.name
        call    xput
        jr      c,.over
.name:  ld      hl,dirent+DE_NAME
        call    str_len
        inc     bc                      ; the 0 with it
        call    xput
        jr      c,.over
        ld      hl,(xptr)
        ld      (xptr),de
        call    argv_add
        jr      c,.over
        ld      hl,gmatched
        inc     (hl)
        jr      .entry
.over:  ld      a,(gfd)
        sys     SYS_CLOSE
        scf
        ret
.close: ld      a,(gfd)
        sys     SYS_CLOSE
        ld      a,(gmatched)
        or      a
        ret     nz
.literal:
        ld      hl,(gword)
        jp      argv_add

; xput — BC bytes from HL appended at DE in the expansion area; DE
; advanced. CF and a message when they do not fit.
xput:   push    hl
        ld      hl,xbuf+XBUF
        or      a
        sbc     hl,de                   ; the room
        or      a
        sbc     hl,bc
        pop     hl
        jr      c,.over
        ldir
        or      a
        ret
.over:  ld      de,s_args
        call    err_msg
        scf
        ret

; match — DE -> a pattern, HL -> a name: A = 1 when the name matches, 0
; otherwise; * any run, ? one byte, letters without regard to case.
match:  ld      ix,0                    ; the pattern after the last *
.loop:  ld      a,(de)
        cp      '*'
        jr      nz,.notstar
        inc     de
        push    de
        pop     ix
        push    hl
        pop     iy                      ; the name where the * began
        jr      .loop
.notstar:
        or      a
        jr      nz,.more
        ld      a,(hl)
        or      a
        jr      z,.yes                  ; both ended
        jr      .back
.more:  ld      c,a
        ld      a,(hl)
        or      a
        jr      z,.no                   ; the name ended first
        ld      b,a
        ld      a,c
        cp      '?'
        jr      z,.step
        call    lower
        ld      c,a
        ld      a,b
        call    lower
        cp      c
        jr      z,.step
.back:  push    ix
        pop     bc
        ld      a,b
        or      c
        jr      z,.no                   ; no * to stretch
        ld      a,(iy+0)
        or      a
        jr      z,.no                   ; nothing left for it
        inc     iy
        push    iy
        pop     hl
        push    ix
        pop     de
        jr      .loop
.step:  inc     de
        inc     hl
        jr      .loop
.yes:   ld      a,1
        ret
.no:    xor     a
        ret

; lower — A in lower case.
lower:  cp      'A'
        ret     c
        cp      'Z'+1
        ret     nc
        or      20h
        ret

; --- the commands ---------------------------------------------------------
; spawn_stage — A = 1 for the list's last command: argv closed, the
; pipe made, the descriptors chosen, the child started, the shell's
; copies closed.
spawn_stage:
        ld      (is_last),a
        ld      a,(argc_s)
        ld      c,a
        ld      b,0
        ld      hl,argv
        add     hl,bc
        add     hl,bc
        ld      (hl),0
        inc     hl
        ld      (hl),0
        ; cd and exit, alone
        ld      a,(is_last)
        or      a
        jr      z,.child
        ld      a,(nstage)
        or      a
        jr      nz,.child
        ld      hl,(argv)
        ld      de,s_cd
        push    hl
        call    str_cmp
        pop     hl
        jp      z,do_cd
        ld      de,s_exit
        call    str_cmp
        jp      z,do_exit
.child: xor     a
        ld      (dosretry),a
        ld      a,0FFh
        ld      (o_in),a
        ld      (o_out),a
        ld      (o_err),a
        ld      (pipe_w),a
        ld      (fdmap),a
        ld      (fdmap+1),a
        ld      (fdmap+2),a
        ld      a,(is_last)
        or      a
        jr      nz,.in
        sys     SYS_PIPE
        jr      nc,.piped
        ld      de,s_pipe
        call    err_file
        jp      .failed
.piped: ld      a,h
        ld      (pipe_w),a
        ld      (fdmap+1),a
        ld      a,l
        ld      (next_r),a
.in:    ld      a,(prev_r)
        cp      0FFh
        jr      z,.rin
        ld      (fdmap),a
        jr      .out
.rin:   ld      hl,(r_in)
        ld      a,h
        or      l
        jr      z,.out
        push    hl
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        pop     de
        jp      c,.openfail
        ld      (o_in),a
        ld      (fdmap),a
.out:   ld      a,(is_last)
        or      a
        jr      z,.err
        ld      hl,(r_out)
        ld      a,h
        or      l
        jr      z,.err
        push    hl
        ld      a,(r_app)
        or      a
        ld      a,O_WRONLY|O_CREAT|O_TRUNC
        jr      z,.oflags
        ld      a,O_WRONLY|O_CREAT|O_APPEND
.oflags:
        sys     SYS_OPEN
        pop     de
        jp      c,.openfail
        ld      (o_out),a
        ld      (fdmap+1),a
.err:   ld      hl,(r_err)
        ld      a,h
        or      l
        jr      z,.path
        push    hl
        ld      a,O_WRONLY|O_CREAT|O_TRUNC
        sys     SYS_OPEN
        pop     de
        jp      c,.openfail
        ld      (o_err),a
        ld      (fdmap+2),a
.path:  ld      hl,(argv)
        push    hl
.hasslash:
        ld      a,(hl)
        or      a
        jr      z,.bin
        cp      '/'
        jr      z,.asis
        inc     hl
        jr      .hasslash
.bin:   ld      hl,s_bin
        ld      de,path
        call    str_copy
        pop     hl
        call    str_copy
        ld      hl,path
        jr      .spawn
.asis:  pop     hl
.spawn: ld      de,argv
        ld      bc,fdmap
        ld      a,(bg)
        or      a
        jr      nz,.bgspawn
        ld      a,SIGIGN_INT            ; a foreground child takes ^C
        sys     SYS_SPAWNV
        jr      .spawned
.bgspawn:
        push    hl
        ld      a,SIGINT                ; a background child ignores it,
        ld      b,SIG_IGN               ; inheriting what the shell sets
        sys     SYS_SIGNAL
        ld      a,l
        ld      (sigwas),a
        pop     hl
        ld      de,argv
        ld      bc,fdmap
        xor     a
        sys     SYS_SPAWNV
        push    af
        push    hl
        ld      a,SIGINT
        ld      hl,sigwas
        ld      b,(hl)
        sys     SYS_SIGNAL
        pop     hl
        pop     af
.spawned:
        jr      nc,.ok
        ; A .com program? ENOEXEC or ENOENT for a word ending in .com,
        ; not yet retried: the same command through /bin/dos.
        cp      E_NOEXEC
        jr      z,.dotcom
        cp      E_NOENT
        jr      nz,.nodos
.dotcom:
        push    af
        ld      a,(dosretry)
        or      a
        jr      nz,.nodospop
        ld      hl,(argv)
        call    str_len                 ; bc = the word's length
        ld      a,b
        or      a
        jr      nz,.suffix
        ld      a,c
        cp      4
        jr      c,.nodospop
.suffix:
        add     hl,bc
        dec     hl                      ; the last byte
        ld      de,s_com+3
        ld      b,4
.cmp:   ld      a,(hl)
        or      20h                     ; a letter lower-cased; . unchanged
        ex      de,hl
        cp      (hl)
        ex      de,hl
        jr      nz,.nodospop
        dec     hl
        dec     de
        djnz    .cmp
        pop     af
        ld      a,1
        ld      (dosretry),a
        ; argv one word up: argv[0] becomes dos, the word its argument.
        ld      a,(argc_s)
        ld      l,a
        ld      h,0
        add     hl,hl
        ld      de,argv+1
        add     hl,de                   ; hl -> the terminator's high byte
        ld      d,h
        ld      e,l
        inc     de
        inc     de
        ld      a,(argc_s)
        inc     a
        add     a,a
        ld      c,a
        ld      b,0                     ; bc = (argc + 1) words
        lddr
        ld      hl,s_dos
        ld      (argv),hl
        ld      hl,argc_s
        inc     (hl)
        ld      hl,s_bindos
        jp      .spawn
.nodospop:
        pop     af
.nodos: ld      de,(argv)
        call    err_file
.failed:
        xor     a                       ; no child
        ld      l,a
.ok:    ld      a,l                     ; the pid
        ld      hl,nstage
        ld      c,(hl)
        inc     (hl)
        ld      b,0
        ld      hl,pids
        add     hl,bc
        ld      (hl),a
        ; the shell's copies, closed
        ld      a,(o_in)
        call    close_if
        ld      a,(o_out)
        call    close_if
        ld      a,(o_err)
        call    close_if
        ld      a,(pipe_w)
        call    close_if
        ld      a,(prev_r)
        call    close_if
        ld      a,0FFh
        ld      hl,is_last
        bit     0,(hl)
        jr      nz,.last
        ld      a,(next_r)
.last:  ld      (prev_r),a
        jp      stage_begin
.openfail:
        call    err_file
        ; nothing spawned for this stage: its pipe closed, its input
        ; passed on so the next stage sees an end of file
        ld      a,(pipe_w)
        call    close_if
        ld      a,(o_in)
        call    close_if
        ld      a,(o_out)
        call    close_if
        ld      hl,nstage
        ld      c,(hl)
        inc     (hl)
        ld      b,0
        ld      hl,pids
        add     hl,bc
        ld      (hl),0
        ld      a,(prev_r)
        call    close_if
        jr      .last

; close_if — A = a descriptor, or FFh for none: closed.
close_if:
        cp      0FFh
        ret     z
        sys     SYS_CLOSE
        ret

; wait_list — a foreground list waited for, its last command's status
; printed when not 0; a background list's pid printed.
wait_list:
        ld      a,(nstage)
        or      a
        ret     z
        dec     a
        ld      c,a
        ld      b,0
        ld      hl,pids
        add     hl,bc
        ld      a,(hl)                  ; the last command's pid
        ld      (lastpid),a
        ld      a,(bg)
        or      a
        jr      z,.fg
        ld      a,(lastpid)
        or      a
        ret     z
        ld      l,a
        ld      h,0
        call    put_bracketed
        ld      a,10
        call    out_putc
        jp      out_flush
.fg:    ld      a,(lastpid)
        or      a
        jr      z,.others
        ld      b,0
        sys     SYS_WAITPID
        jr      c,.others
        ld      a,l
        ld      (status),a
.others:
        ld      a,(nstage)
        dec     a
        ld      b,a
        ld      hl,pids
.each:  ld      a,b
        or      a
        jr      z,.report
        push    bc
        push    hl
        ld      a,(hl)
        or      a
        jr      z,.skip
        ld      b,0
        sys     SYS_WAITPID
.skip:  pop     hl
        pop     bc
        inc     hl
        dec     b
        jr      .each
.report:
        ld      a,(lastpid)
        or      a
        ret     z
        ld      a,(status)
        or      a
        ret     z
        ld      l,a
        ld      h,0
        call    put_bracketed
        ld      a,10
        call    out_putc
        jp      out_flush

; reap — every background job that ended, reported as [pid] status.
reap:   xor     a
        ld      b,WNOHANG
        sys     SYS_WAITPID
        ret     c                       ; no child at all
        ld      a,h
        or      l
        ret     z                       ; none ended
        push    hl
        ld      l,h
        ld      h,0
        call    put_bracketed
        pop     hl
        ld      a,' '
        call    out_putc
        ld      h,0
        ld      b,0
        call    out_dec16
        ld      a,10
        call    out_putc
        jr      reap

; put_bracketed — HL in decimal between brackets.
put_bracketed:
        ld      a,'['
        call    out_putc
        ld      b,0
        call    out_dec16
        ld      a,']'
        jp      out_putc

; do_cd — cd [dir]: the directory, / without one.
do_cd:  ld      hl,(argv+2)
        ld      a,h
        or      l
        jr      nz,.go
        ld      hl,s_root
.go:    push    hl
        sys     SYS_CHDIR
        pop     de
        ret     nc
        jp      err_file

; do_exit — exit [n].
do_exit:
        ld      hl,(argv+2)
        ld      a,h
        or      l
        jr      z,.zero
        call    str_atoi
        ld      a,l
        jp      lib_exit
.zero:  xor     a
        jp      lib_exit

s_dashi:  db    "-i",0
s_prompt: db    " $ ",0
s_q:      db    "?",0
s_dot:    db    ".",0
s_root:   db    "/",0
s_dos:      db  "dos",0
s_bindos:   db  "/bin/dos",0
s_com:      db  ".com",0
s_bin:    db    "/bin/",0
s_cd:     db    "cd",0
s_exit:   db    "exit",0
s_pipe:   db    "pipe",0
s_long:   db    "line too long",0
s_words:  db    "too many words",0
s_args:   db    "too many arguments",0
s_stages: db    "too many stages",0
s_syntax: db    "syntax error",0

        include "lib/out.inc"
        include "lib/in.inc"
        include "lib/line.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     interactive,1
        bss     hist_n,1
        bss     hist_w,1
        bss     hist_i,1
        bss     ntok,1
        bss     tok_i,1
        bss     argc_s,1
        bss     nstage,1
        bss     bg,1
        bss     is_last,1
        bss     dosretry,1
        bss     rkind,1
        bss     prev_r,1
        bss     next_r,1
        bss     pipe_w,1
        bss     o_in,1
        bss     o_out,1
        bss     o_err,1
        bss     r_app,1
        bss     sigwas,1
        bss     lastpid,1
        bss     status,1
        bss     gfd,1
        bss     gmatched,1
        bss     r_in,2
        bss     r_out,2
        bss     r_err,2
        bss     xptr,2
        bss     gword,2
        bss     gpat,2
        bss     gpre,2
        bss     fdmap,3
        bss     pids,NSTAGE
        bss     tok_kind,NTOK
        bss     tok_ptr,NTOK*2
        bss     argv,NARG*2
        bss     line,LINE
        bss     cwd,LINE
        bss     path,LINE+8
        bss     dirent,DIRENT_SIZE
        bss     xbuf,XBUF
        bss     hist,HIST*TTY_LINE
