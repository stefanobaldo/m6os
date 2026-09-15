; tail [-n N] [file] — the last N lines, 10 without -n. A file is read
; from its end: lseek(SEEK_END) gives the size, windows of 4 KB are read
; backwards until the Nth LF from the end is found (a LF that ends the
; file ends its last line and starts none), then the file is copied from
; there in 4 KB rounds. Descriptor 0 cannot be sought: it is read into
; the same 4 KB buffer used as a ring, and at its end the last N lines
; the ring holds are written, in one or two pieces.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
BUFSZ   equ     4096
        m6_prog 1
main:   ld      hl,10
        ld      (nlines),hl
        ld      hl,opts
        ld      de,s_usage
        call    arg_opts
        ld      a,(opt_flags)
        bit     0,a
        jr      z,.args
        ld      hl,(opt_val)
        call    str_atoi
        jr      c,usage
        ld      a,(de)
        or      a
        jr      nz,usage
        ld      (nlines),hl
.args:  ld      hl,0
        ld      (name),hl
        call    arg_next
        jp      c,stdin
        ld      (name),hl
        call    arg_peek
        jr      nc,usage                ; one file at most
        ld      hl,(nlines)
        ld      a,h
        or      l
        ret     z                       ; -n 0: nothing
        ld      hl,(name)
        xor     a                       ; O_RDONLY
        sys     SYS_OPEN
        jr      c,.err
        ld      (fd),a
        call    file
        ld      a,(fd)
        sys     SYS_CLOSE
        xor     a
        ret
.err:   ld      de,(name)
        call    err_file
        ld      a,1
        ret
usage:  ld      de,s_usage
        jp      err_usage

; file — the descriptor in fd: the start of the last nlines lines found
; backwards, then everything from there written.
file:   ld      a,(fd)
        ld      hl,0
        ld      de,0
        ld      b,SEEK_END
        sys     SYS_LSEEK
        jp      c,ferr
        ld      (pos),hl
        ld      (pos+2),de
        ld      hl,(nlines)
        ld      (left),hl
        ld      a,1
        ld      (first),a
.win:   ld      hl,(pos)
        ld      de,(pos+2)
        ld      a,h
        or      l
        or      d
        or      e
        jr      z,.seek                 ; the start of the file
        ld      bc,BUFSZ                ; the window: BUFSZ, or what is left
        ld      a,d
        or      e
        jr      nz,.sub
        ld      hl,(pos)
        or      a
        sbc     hl,bc
        jr      nc,.sub
        ld      bc,(pos)
.sub:   ld      (win),bc
        ld      hl,(pos)
        or      a
        sbc     hl,bc
        ld      (pos),hl
        ld      hl,(pos+2)
        ld      de,0
        sbc     hl,de
        ld      (pos+2),hl
        call    seek_pos
        ld      a,(fd)
        ld      hl,buf
        ld      bc,(win)
        sys     SYS_READ
        jp      c,ferr
        ld      b,h
        ld      c,l
        ld      hl,buf
        add     hl,bc                   ; hl -> past the window
        call    scan_back
        jr      nc,.win
        ld      de,buf
        or      a
        sbc     hl,de
        ex      de,hl                   ; de = the offset inside the window
        ld      hl,(pos)
        add     hl,de
        ld      (pos),hl
        jr      nc,.seek
        ld      hl,(pos+2)
        inc     hl
        ld      (pos+2),hl
.seek:  call    seek_pos
.copy:  ld      a,(fd)
        ld      hl,buf
        ld      bc,BUFSZ
        sys     SYS_READ
        jp      c,ferr
        ld      a,h
        or      l
        ret     z
        ld      b,h
        ld      c,l
        ld      hl,buf
        call    write_out
        jr      .copy

; seek_pos — the descriptor in fd to pos.
seek_pos:
        ld      a,(fd)
        ld      hl,(pos)
        ld      de,(pos+2)
        ld      b,SEEK_SET
        sys     SYS_LSEEK
        ret     nc
        jr      ferr

; scan_back — HL -> the byte after the last, BC = how many: scanned
; backwards for LF; the first byte examined in the whole scan, if a LF,
; ends the last line and is not counted; every other LF takes one from
; left. CF with HL -> the first byte of the line when left reaches 0;
; CF clear at the start of the bytes otherwise.
scan_back:
.loop:  ld      a,b
        or      c
        jr      z,.none
        dec     bc
        dec     hl
        ld      e,(hl)
        ld      a,(first)
        or      a
        jr      z,.check
        xor     a
        ld      (first),a
        ld      a,e
        cp      10
        jr      z,.loop
.check: ld      a,e
        cp      10
        jr      nz,.loop
        push    hl
        ld      hl,(left)
        dec     hl
        ld      (left),hl
        ld      a,h
        or      l
        pop     hl
        jr      nz,.loop
        inc     hl
        scf
        ret
.none:  or      a
        ret

; write_out — HL -> bytes, BC = how many, to descriptor 1.
write_out:
        ld      a,b
        or      c
        ret     z
        ld      a,1
        sys     SYS_WRITE
        ret     nc
        ld      de,0
        call    err_file
        ld      a,1
        jp      lib_exit
ferr:   ld      de,(name)
        call    err_file
        ld      a,1
        jp      lib_exit

; stdin — descriptor 0 into the ring: wpos is where the next byte lands,
; full says the ring has wrapped, so the oldest byte is at wpos.
stdin:  ld      hl,(nlines)
        ld      a,h
        or      l
        ret     z
        ld      hl,0
        ld      (wpos),hl
        xor     a
        ld      (full),a
.read:  ld      hl,BUFSZ
        ld      de,(wpos)
        or      a
        sbc     hl,de                   ; hl = the room to the ring's end
        ld      bc,512
        or      a
        sbc     hl,bc
        jr      nc,.chunk               ; at least 512: read 512
        add     hl,bc
        ld      b,h
        ld      c,l                     ; else the room
.chunk: ld      hl,buf
        add     hl,de
        xor     a
        sys     SYS_READ
        jp      c,ferr
        ld      a,h
        or      l
        jr      z,.eof
        ld      de,(wpos)
        add     hl,de
        ld      (wpos),hl
        ld      a,h
        cp      high BUFSZ
        jr      nz,.read
        ld      hl,0
        ld      (wpos),hl
        ld      a,1
        ld      (full),a
        jr      .read
.eof:   ld      hl,(nlines)
        ld      (left),hl
        ld      a,1
        ld      (first),a
        ld      bc,(wpos)
        ld      hl,buf
        add     hl,bc
        call    scan_back               ; the newest piece, buf to wpos
        jr      c,.newest
        ld      a,(full)
        or      a
        jr      z,.frombuf              ; nothing older: from the ring's start
        ld      hl,BUFSZ
        ld      de,(wpos)
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        ld      hl,buf+BUFSZ
        call    scan_back               ; the older piece, wpos to the end
        jr      c,.older
        ld      hl,buf
        ld      de,(wpos)
        add     hl,de                   ; the oldest byte there is
.older: push    hl
        ex      de,hl
        ld      hl,buf+BUFSZ
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        pop     hl
        call    write_out               ; from the start to the ring's end
.frombuf:
        ld      hl,buf
.newest:
        ex      de,hl
        ld      hl,buf
        ld      bc,(wpos)
        add     hl,bc
        or      a
        sbc     hl,de
        ld      b,h
        ld      c,l
        ex      de,hl
        call    write_out               ; from the start (or buf) to wpos
        xor     a
        ret

opts:    db     "n:",0
s_usage: db     "tail [-n N] [file]",0

        include "lib/args.inc"
        include "lib/err.inc"
        include "lib/str.inc"
        m6_bss
        bss     fd,1
        bss     name,2
        bss     nlines,2
        bss     left,2
        bss     first,1
        bss     pos,4
        bss     win,2
        bss     wpos,2
        bss     full,1
        bss_align
        bss     buf,BUFSZ
