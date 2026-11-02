; Combined fixed keyboard and both joystick ports. Original logical E bits retained.
; Q/A/O/P, arrows; SPACE/M and either joystick trigger; H pause remains original.
read_controls:
    push bc
    push de
    push hl
    call $5795                   ; original five key pairs + H
    di
    ld e,a
    in a,($AA)
    and $F0
    or 8
    out ($AA),a
    in a,($A9)
    bit 4,a
    jr nz,no_left
    set 1,e
no_left:
    bit 5,a
    jr nz,no_up
    set 3,e
no_up:
    bit 6,a
    jr nz,no_down
    set 2,e
no_down:
    bit 7,a
    jr nz,no_right
    set 0,e
no_right:
    in a,($AA)
    and $F0
    or 4
    out ($AA),a
    in a,($A9)
    bit 2,a
    jr nz,no_m
    set 4,e
no_m:
    ld c,e
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
    ld l,a
    ld a,15
    out ($A0),a
    ld a,b
    or $40
    out ($A1),a
    ld a,14
    out ($A0),a
    in a,($A2)
    and l
    cpl
    and $3F
    ld l,a
    ld a,15
    out ($A0),a
    ld a,b
    out ($A1),a
    ld a,7
    out ($A0),a
    ld a,d
    out ($A1),a
    ld e,c
    bit 0,l
    jr z,no_joy_up
    set 3,e
no_joy_up:
    bit 1,l
    jr z,no_joy_down
    set 2,e
no_joy_down:
    bit 2,l
    jr z,no_joy_left
    set 1,e
no_joy_left:
    bit 3,l
    jr z,no_joy_right
    set 0,e
no_joy_right:
    ld a,l
    and $30
    jr z,no_joy_fire
    set 4,e
no_joy_fire:
    ld a,e
    pop hl
    pop de
    pop bc
    ld e,a
    ei
    ret
