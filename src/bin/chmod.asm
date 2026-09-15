; chmod [+-][rhsa]... file... — the FAT attributes of each file by letter:
; r read-only, h hidden, s system, a archive; + sets, - clears, the
; letters after each sign grouped. Every word that begins with + or - is
; an operation, at least one, then the files, at least one. The
; directory bit is the kernel's to keep.
        include "kernel/kernel.inc"
        include "lib/prog.inc"
        m6_prog 1
main:   xor     a
        ld      (setm),a
        ld      (clrm),a
        ld      (nops),a
.ops:   call    arg_peek
        jr      c,usage
        ld      a,(hl)
        cp      '+'
        jr      z,.op
        cp      '-'
        jr      nz,.files
.op:    ld      c,a                     ; c = the sign
        call    arg_next                ; hl -> the word, taken; bc kept
        ld      a,(nops)
        inc     a
        ld      (nops),a
.letter:
        inc     hl
        ld      a,(hl)
        or      a
        jr      z,.ops
        ld      b,DA_RDONLY
        cp      'r'
        jr      z,.bit
        ld      b,DA_HIDDEN
        cp      'h'
        jr      z,.bit
        ld      b,DA_SYSTEM
        cp      's'
        jr      z,.bit
        ld      b,DA_ARCHIVE
        cp      'a'
        jr      nz,usage
.bit:   ld      a,c
        cp      '+'
        ld      a,b
        jr      nz,.clear
        ld      de,setm
        jr      .into
.clear: ld      de,clrm
.into:  ex      de,hl
        or      (hl)
        ld      (hl),a
        ex      de,hl
        jr      .letter
.files: ld      a,(nops)
        or      a
        jr      z,usage
.file:  call    arg_next
        jr      c,.done
        push    hl
        ld      de,ent
        sys     SYS_STAT
        pop     hl
        jr      c,.err
        ld      a,(ent+DE_ATTR)
        ld      de,(setm)               ; e = set, d = clear (adjacent)
        or      e
        ld      e,a
        ld      a,d
        cpl
        and     e
        and     DA_RDONLY|DA_HIDDEN|DA_SYSTEM|DA_ARCHIVE
        push    hl
        sys     SYS_CHMOD
        pop     hl
        jr      nc,.file
.err:   ex      de,hl
        call    err_file
        jr      .file
.done:  ld      a,(lib_status)
        ret
usage:  ld      de,s_usage
        jp      err_usage
s_usage: db     "chmod [+-][rhsa]... file...",0

        include "lib/args.inc"
        include "lib/err.inc"
        m6_bss
        bss     setm,1
        bss     clrm,1
        bss     nops,1
        bss     ent,DIRENT_SIZE
