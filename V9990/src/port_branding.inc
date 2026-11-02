; One-shot DiHalt B1/BD8 logo and complete PSG fanfare, identical timing to Spy2.
; Called from the page3 preloader with DI; no BIOS/input can skip the logo.
branding:
    ld a,2
    out ($67),a
    xor a
    out ($67),a
    ld b,6
    ld a,$82
    call reg_write
    ld b,7
    ld a,8
    call reg_write
    ld b,8
    ld a,2
    call reg_write
    ld b,9
    xor a
    call reg_write
    ld b,13
    ld a,$40
    call reg_write
    ld b,15
    xor a
    call reg_write
    call vblank
    ld b,14
    xor a
    call reg_write
    ld a,31
    out ($61),a
    out ($61),a
    out ($61),a
    include "../build/branding-uploads.inc"
    ld hl,branding_music
    ld (branding_pointer),hl
    xor a
    ld (branding_wait),a
    call display_on
branding_visible:
    ld bc,BRANDING_FRAMES
branding_frame:
    call vblank
    call branding_tick
    dec bc
    ld a,b
    or c
    jr nz,branding_frame
    ld e,0
    ld a,8
    call branding_psg
    ld a,9
    call branding_psg
    ld a,10
    call branding_psg
    ld a,7
    ld e,$BF
    call branding_psg
    call display_off
branding_done:
    ret
branding_tick:
    ld a,(branding_wait)
    or a
    jr z,branding_read
    dec a
    ld (branding_wait),a
    ret
branding_read:
    ld hl,(branding_pointer)
branding_next:
    ld a,(hl)
    cp $FF
    ret z
    inc hl
    bit 7,a
    jr nz,branding_delay
    ld e,(hl)
    inc hl
    call branding_psg
    jr branding_next
branding_delay:
    and $7F
    dec a
    ld (branding_wait),a
    ld (branding_pointer),hl
    ret
branding_psg:
    out ($A0),a
    cp 7
    ld a,e
    jr nz,branding_psg_write
    and $3F
    or $80
branding_psg_write:
    out ($A1),a
    ret
branding_pointer: dw 0
branding_wait: db 0
branding_music: incbin "../build/branding-fanfare.bin"
