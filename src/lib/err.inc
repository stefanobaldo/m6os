; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; Messages on descriptor 2, unbuffered, in the one form every program
; uses: the program's name — argv[0], the word the shell was given — a
; colon, what failed, a colon, the errno's name.
;
;   err_file    DE -> a name (0: none), A = the errno: "name: file: ENOENT";
;               lib_status = 1, so the program's exit says something failed
;   err_msg     DE -> a message: "name: message"; lib_status = 1
;   err_usage   DE -> the synopsis: "name: usage: synopsis"; exits with 2
;   err_name    A = an errno: HL -> its name, "?" for one not in the table
;   err_puts    HL -> a 0-terminated string, written to descriptor 2
; All corrupt everything.
        define ERR_INC

err_file:
        push    af
        push    de
        call    err_head
        pop     hl
        ld      a,h
        or      l
        jr      z,.noname
        call    err_puts
        ld      hl,err_colon
        call    err_puts
.noname:
        pop     af
        call    err_name
        call    err_puts
        jr      err_end

err_msg:
        push    de
        call    err_head
        pop     hl
        call    err_puts
err_end:
        ld      hl,err_nl
        call    err_puts
        ld      a,1
        ld      (lib_status),a
        ret

err_usage:
        push    de
        call    err_head
        ld      hl,err_use
        call    err_puts
        pop     hl
        call    err_puts
        ld      hl,err_nl
        call    err_puts
        ld      a,2
        jp      lib_exit

; err_out — the output buffer could not be written: A = the errno.
err_out:
        push    af
        call    err_head
        ld      hl,err_write
        call    err_puts
        pop     af
        call    err_name
        call    err_puts
        ld      hl,err_nl
        call    err_puts
        ld      a,1
        sys     SYS_EXIT

err_head:
        ld      hl,(lib_argc)
        ld      a,h
        or      l
        jr      z,.noargv
        ld      hl,(lib_argv)
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        ex      de,hl
        jr      .name
.noargv:
        ld      hl,err_q
.name:  call    err_puts
        ld      hl,err_colon
        jp      err_puts

err_puts:
        push    hl
        ld      bc,0
.len:   ld      a,(hl)
        or      a
        jr      z,.write
        inc     hl
        inc     bc
        jr      .len
.write: pop     hl
        ld      a,2
        sys     SYS_WRITE
        ret

err_name:
        ld      hl,err_tab
.next:  ld      b,(hl)
        inc     hl
        cp      b
        ret     z
        inc     b
        dec     b
        ret     z                       ; the table's end: "?"
.skip:  ld      c,(hl)
        inc     hl
        inc     c
        dec     c
        jr      nz,.skip
        jr      .next

err_colon:  db  ": ",0
err_nl:     db  10,0
err_q:      db  "?",0
err_use:    db  "usage: ",0
err_write:  db  "write: ",0
err_tab:
        db      E_PERM,"EPERM",0
        db      E_NOENT,"ENOENT",0
        db      E_SRCH,"ESRCH",0
        db      E_INTR,"EINTR",0
        db      E_IO,"EIO",0
        db      E_NXIO,"ENXIO",0
        db      E_2BIG,"E2BIG",0
        db      E_NOEXEC,"ENOEXEC",0
        db      E_BADF,"EBADF",0
        db      E_CHILD,"ECHILD",0
        db      E_AGAIN,"EAGAIN",0
        db      E_NOMEM,"ENOMEM",0
        db      E_ACCES,"EACCES",0
        db      E_FAULT,"EFAULT",0
        db      E_BUSY,"EBUSY",0
        db      E_EXIST,"EEXIST",0
        db      E_XDEV,"EXDEV",0
        db      E_NODEV,"ENODEV",0
        db      E_NOTDIR,"ENOTDIR",0
        db      E_ISDIR,"EISDIR",0
        db      E_INVAL,"EINVAL",0
        db      E_NFILE,"ENFILE",0
        db      E_MFILE,"EMFILE",0
        db      E_NOSPC,"ENOSPC",0
        db      E_ROFS,"EROFS",0
        db      E_PIPE,"EPIPE",0
        db      E_NOSYS,"ENOSYS",0
        db      E_NOTEMPTY,"ENOTEMPTY",0
        db      E_NAMETOOLONG,"ENAMETOOLONG",0
        db      0,"?",0
