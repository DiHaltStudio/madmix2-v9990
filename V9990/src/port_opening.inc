; One-shot B3/BD8 opening, 512x424 interlaced, after the complete DiHalt logo.
; Runs in page3 with DI and page1 ROM banking, before game VRAM is installed.
opening_show:
    ld a,2
    out ($67),a
    xor a
    out ($67),a
    ld b,8
    ld a,2                      ; real V9990: 512 KiB addressing before uploads
    call reg_write
    ld b,6
    ld a,$96                    ; B3, 512-wide BD8
    call reg_write
    ld b,7
    ld a,$0E                    ; PAL, interlace and even/odd fields: 424 lines
    call reg_write
    ld b,9
    xor a
    call reg_write
    ld b,13
    ld a,$40                    ; fixed GGGRRRBB colours
    call reg_write
    ld b,15
    xor a
    call reg_write
    call vblank
    ld b,14
    xor a
    call reg_write
    xor a
    out ($61),a
    out ($61),a
    out ($61),a
    include "../build/opening-uploads.inc"
    call display_on
opening_visible:
    call control                ; blanks on press, then waits for release
opening_done:
    ret
    include "../build/opening-control.inc"
; Sample while the dismissing key/fire is held, before release debounce.
; F1 alone or F1+CTRL/RETURN/M does not enable the contact-only immunity.
opening_secret:
    in a,($AA)
    and $F0
    or 6
    out ($AA),a
    in a,($A9)
    and $20                 ; F1, row6 bit5
    ret nz
    in a,($AA)
    and $F0
    or 8
    out ($AA),a
    in a,($A9)
    and 1
    jr z,opening_secret_on
    ; Reuse the existing safe PSG poll, skipping its keyboard half.
    call read_fire
    ret nz
opening_secret_on:
    ld a,1
    ld ($CFF7),a
    ret
