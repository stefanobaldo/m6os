; The secondary-slot switching stub: the image of the routine at K_SSLOT in
; page 0, position independent. Writing the subslot register at FFFFh
; needs page 3 to show the slot being switched, so for a few instructions
; page 3's RAM — the resident and its stack — is not there; this code runs
; from page 0, uses no stack, and returns only after page 3 is RAM again.
; The resident carries it to copy into every page 0 it builds (K_STUB), and
; the switched image carries it in place, at K_SSLOT of its own segment, so
; that the segment serves as process 0's page 0.
;
; In:  E = primary register value showing the target slot in page 3,
;      B = primary register value to restore, D = complemented mask for the
;      page, H = subslot bits for the page.
; Out: L = the subslot register value written. Corrupts AF.
k_sslot_stub:
        ld      a,e
        out     (0A8h),a                ; page 3 shows the expanded slot
        ld      a,(0FFFFh)
        cpl                             ; the register reads back inverted
        and     d
        or      h
        ld      (0FFFFh),a
        ld      l,a
        ld      a,b
        out     (0A8h),a                ; page 3 is RAM again
        ret
k_sslot_stub_end:
        ASSERT k_sslot_stub_end - k_sslot_stub == K_SSLOT_LEN
