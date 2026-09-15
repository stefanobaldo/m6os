; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; Paths: the pieces cp and mv share when a destination is a directory.
;
;   path_base   HL -> a path: HL -> its last component, the byte after the
;               last '/' (a path ending in '/' gives the empty string).
;               Corrupts AF, DE.
;   path_join   HL -> a directory, DE -> a name: "dir/name" in path_buf,
;               the '/' added unless the directory ends in one; HL ->
;               path_buf with CF clear, or CF with A = ENAMETOOLONG when
;               the result would not fit PATH_MAX with its terminator.
;               Corrupts everything.
;   path_isdir  HL -> a path: stat into path_ent. CF clear and Z when it
;               names a directory, NZ when a file; CF with A = the errno
;               when stat fails. Corrupts everything.
        define PATH_INC

path_base:
        ld      d,h
        ld      e,l
.loop:  ld      a,(hl)
        or      a
        jr      z,.done
        inc     hl
        cp      '/'
        jr      nz,.loop
        ld      d,h
        ld      e,l
        jr      .loop
.done:  ex      de,hl
        ret

path_join:
        push    de
        ld      de,path_buf
        ld      bc,PATH_MAX-1           ; the room, the terminator excluded
        call    .copy
        jr      c,.long1
        dec     de
        ld      a,(de)
        inc     de
        cp      '/'
        jr      z,.name
        ld      a,b
        or      c
        jr      z,.long1
        ld      a,'/'
        ld      (de),a
        inc     de
        dec     bc
.name:  pop     hl
        call    .copy
        jr      c,.long
        xor     a
        ld      (de),a
        ld      hl,path_buf
        ret
.long1: pop     hl
.long:  ld      a,E_NAMETOOLONG
        scf
        ret
; .copy — the string at HL into DE, its 0 not copied, BC = the room: DE
; past the last byte, BC what is left; CF when it did not fit.
.copy:  ld      a,(hl)
        or      a
        ret     z
        ld      a,b
        or      c
        jr      z,.full
        ld      a,(hl)
        ld      (de),a
        inc     hl
        inc     de
        dec     bc
        jr      .copy
.full:  scf
        ret

path_isdir:
        ld      de,path_ent
        sys     SYS_STAT
        ret     c
        ld      a,(path_ent+DE_ATTR)
        and     DA_DIR
        xor     DA_DIR                  ; Z: the bit was set
        ret
