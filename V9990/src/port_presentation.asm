; Temporary low-RAM presentation helpers, preserved across original overlays.
    org $0680
    jp opening_wait
    jp title_show
opening_wait:
    ret                         ; opening already shown before the P1 preload
; CTRL, SPACE, RETURN or joystick1 fire. Debounce release/press/release.
; No BIOS/IRQ dependency; PSG I/O configuration is restored on each poll.
control:
    call read_control
    jr z,control
control_press:
    call read_control
    jr nz,control_press
    call display_off            ; accepted press: blank BEFORE release polling
control_release:
    call read_control
    jr z,control_release
    ret
read_control:
    in a,($AA)
    and $F0
    or 6
    out ($AA),a
    in a,($A9)
    and 2                       ; CTRL: row6 bit1
    ret z
    in a,($AA)
    and $F0
    or 8
    out ($AA),a
    in a,($A9)
    and 1                       ; SPACE: row8 bit0
    ret z
    in a,($AA)
    and $F0
    or 7
    out ($AA),a
    in a,($A9)
    and $80                     ; RETURN: row7 bit7
    ret z
    in a,($AA)
    and $F0
    or 4
    out ($AA),a
    in a,($A9)
    and 4
    ret z
read_fire:
    ld a,7
    out ($A0),a
    in a,($A2)
    ld d,a
    and $3F
    or $80
    out ($A1),a
    ld a,15
    out ($A0),a
    in a,($A2)
    ld b,a
    and $BF
    out ($A1),a
    ld a,14
    out ($A0),a
    in a,($A2)
    ld c,a
    ld a,15
    out ($A0),a
    ld a,b
    or $40
    out ($A1),a
    ld a,14
    out ($A0),a
    in a,($A2)
    and c
    ld e,a
    ld a,15
    out ($A0),a
    ld a,b
    out ($A1),a
    ld a,7
    out ($A0),a
    ld a,d
    out ($A1),a
    ld a,e
    and $30
    cp $30
    jr nz,presentation_pressed
    or 1
    ret
presentation_pressed:
    xor a
    ret
title_show:
    di
    ld hl,title_names
    ld de,$E000
    ld a,24
name_row:
    push af
    xor a
    out ($64),a
    ld a,e
    out ($63),a
    ld a,d
    out ($63),a
    ld a,7
    out ($63),a
    ld bc,$4060
    otir
    ex de,hl
    ld bc,128
    add hl,bc
    ex de,hl
    pop af
    dec a
    jr nz,name_row
    call show_common
    ei
    ret
show_common:
    di
    call vblank
    ld b,14
    ld a,192
    call reg_write
    ld hl,title_palette
    ld bc,$3061
    otir
    ld b,13
    ld a,12
    call reg_write
    ei                          ; audio must keep ticking during the next blank wait
    call display_on
    call title_control
    di
    call vblank
    ld b,14
    ld a,192
    call reg_write
    ld hl,game_palette
    ld bc,$3061
    otir
    ret
 ; Keep the stage IRQ music running while waiting, but serialize PSG port
; selection/read/restore against that IRQ. Preloader control remains DI-only.
title_control:
    call title_read
    jr z,title_control
title_press:
    call title_read
    jr nz,title_press
    call display_off            ; accepted press: blank BEFORE release polling
title_release:
    call title_read
    jr z,title_release
    ret
title_read:
    di
    call read_control
    ei
    ret
reg_write:
    push af
    ld a,b
    or $80
    out ($64),a
    pop af
    out ($63),a
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
    include "port_display.inc"
title_palette: incbin "../build/title-palette.bin"
game_palette: incbin "../build/title-game-palette.bin"
title_names: incbin "../build/title-names.bin"
    assert $<=$0E80
    ds $0E80-$,0
