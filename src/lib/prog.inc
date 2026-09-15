; m6 — a Unix-like operating system for the MSX
; Copyright (c) 2026 Stefano Baldo
; SPDX-License-Identifier: BSD-3-Clause
;
; The library a program in a file is built with. Include kernel/kernel.inc,
; then this file, then write the program; include the lib/*.inc files the
; program uses after its code, and end with m6_bss and the program's own
; buffers. Each include is a subject — out.inc the buffered output, in.inc
; the buffered input, err.inc the messages, args.inc the arguments and
; options, str.inc the string routines, path.inc the last component of a
; path and the join of a directory and a name — and a program pays only
; for the ones it includes.
;
;   m6_prog pages   the header the kernel checks (jr start, "m6", the
;                   pages the program wants, a zero) and start:, which
;                   keeps argc and argv, initialises the library and calls
;                   main with BC = argc and HL = argv; the A main returns
;                   is the exit status
;   m6_bss          after the code and the includes: lib_exit, lib_init and
;                   the library's buffers, placed past the image; then the
;                   program's own, with
;   bss name,size   name = the next free address past the image
;   bss_align       the next bss on a 256-byte boundary
;
; A buffer is never a ds in the file: sjasmplus writes a ds into the raw
; image, and a program of 300 bytes of code with a 4K buffer would load
; nine sectors instead of one. The kernel checks that the file, the
; argument block and its frame fit the page, and nothing checks the
; memory a program uses past its file; so every bss asserts that the
; buffers end below 3EE8h — the top of a one-page process holds the
; 256-byte argument block and the kernel's 24-byte frame.
;
; lib_exit (A = status) flushes the output buffer, when there is one, and
; exits; lib_status is 1 once err_file has reported something, so a
; program that ends with `ld a,(lib_status)` exits 1 if any file failed.

    macro m6_prog Q1
        org     P0_PROG
        jr      start
        db      "m6"
        db      Q1
        db      0
start:  ld      (lib_argc),bc
        ld      (lib_argv),hl
        push    bc
        push    hl
        call    lib_init
        pop     hl
        pop     bc
        call    main
        jp      lib_exit
    endm

    macro bss Q1,Q2
Q1      equ     __bss
__bss   =       __bss+Q2
        assert  __bss <= 3EE8h
    endm

    macro bss_align
__bss   =       (__bss+255) & 0FF00h
    endm

    macro m6_bss
lib_exit:
      ifdef OUT_INC
        push    af
        call    out_flush
        pop     af
      endif
        sys     SYS_EXIT
lib_init:
        xor     a
        ld      (lib_status),a
      ifdef OUT_INC
        ld      hl,out_buf
        ld      (out_ptr),hl
      endif
      ifdef ARGS_INC
        ld      hl,1
        ld      (arg_i),hl
        xor     a
        ld      (opt_flags),a
      endif
      ifdef LINE_INC
        xor     a
        ld      (in_err),a
        ld      (in_cut),a
      endif
        ret
      ifndef ERR_INC
; No err.inc: a write error ends the program with 1, silently.
err_out:
        ld      a,1
        sys     SYS_EXIT
      endif
__bss   =       $
        bss     lib_argc,2
        bss     lib_argv,2
        bss     lib_status,1
      ifdef ARGS_INC
        bss     arg_i,2
        bss     opt_flags,1
        bss     opt_val,2
        bss     opt_ltr,2
        bss     opt_use,2
      endif
      ifdef IN_INC
        bss     in_fd,1
        bss     in_ptr,2
        bss     in_end,2
      endif
      ifdef LINE_INC
        bss     in_err,1
        bss     in_cut,1
      endif
      ifdef OUT_INC
        bss     out_ptr,2
        bss     out_num,12
        bss_align
        bss     out_buf,512
      endif
      ifdef IN_INC
        bss_align
        bss     in_buf,512
      endif
      ifdef PATH_INC
        bss     path_buf,PATH_MAX
        bss     path_ent,DIRENT_SIZE
      endif
    endm
