    org $C000
entry:
    call branding
    xor a
    ld ($CFF7),a
    call opening_show
    xor a
    out ($6F),a
    ld a,2
    out ($67),a
    xor a
    out ($67),a
    ld b,6
    ld a,5
    call reg_write
    ld b,7
    ld a,8
    call reg_write
    ld b,8
    ld a,2                 ; restore real-chip 512 KiB mode BEFORE VRAM writes
    call reg_write
    ld b,9
    xor a
    call reg_write
    ld b,13
    xor a
    call reg_write
    ld b,25
    ld a,12                ; visible sprite table 30000
    call reg_write
    xor a
    ld de,0
    call set_write
    ld h,8
clear_bank:
    ld de,0
clear_loop:
    xor a
    out ($60),a
    dec de
    ld a,d
    or e
    jr nz,clear_loop
    dec h
    jr nz,clear_bank
    include "../build/port-uploads.inc"
    call vblank
    ld b,14
    xor a
    call reg_write
    ld hl,palette
    ld bc,$C061
    otir
    xor a
    ld ($6000),a
    ret
wait_command:
    in a,($65)
    and 1
    jr nz,wait_command
    ret
vblank:
    in a,($65)
    and $40
    jr nz,vblank
vb_start:
    in a,($65)
    and $40
    jr z,vb_start
    ret
reg_write:
    push af
    ld a,b
    or $80
    out ($64),a
    pop af
    out ($63),a
    ret
set_write:
    push af
    xor a
    out ($64),a
    ld a,e
    out ($63),a
    ld a,d
    out ($63),a
    pop af
    out ($63),a
    ret
upload:
    ld c,$60
upload_byte:
    ld a,(hl)
    out (c),a
    inc hl
    dec de
    ld a,d
    or e
    jr nz,upload_byte
    ret
    include "port_display.inc"
palette: incbin "../build/port-palette.bin"
    include "../src/port_branding.inc"
    include "../src/port_opening.inc"
    assert $<$CF00
