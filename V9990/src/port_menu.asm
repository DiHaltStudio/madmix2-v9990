; Stage-only driver. No original video routines or BIOS rendering calls.
    org $2B6A
menu:
    di
    ld ($176D),sp
    ld sp,$0FFF
    ld hl,$1800
    ld de,$E800
    ld bc,UI_BYTES
    ldir
    ld a,($CFF7)
    ld ($105D),a           ; hidden opening contact-immunity selection
    ld a,$C3
    ld ($0038),a
    ld hl,$E80C
    ld ($0039),hl
    im 1
    ld a,1
    ld ($03F7),a           ; reader may service the persistent audio IRQ
    call $E818
    ld b,9
    ld a,1
    call $E815
    ei
    call $0683            ; existing V9990 title and continuous stage music
    call $E800
credits_visible:
    ld ix,UI_CREDITS
    call $E806
    call $E824             ; credits complete before display enable
    ld b,150
credits_wait:
    push bc
    call $E80F
    pop bc
    djnz credits_wait
    call $E809            ; STANDARD/HARD, default STANDARD
    di                          ; ui_confirm already blanked on the press
    ld sp,($176D)
    ret
    include "../build/ui-api.inc"
    assert $<$2F1D
