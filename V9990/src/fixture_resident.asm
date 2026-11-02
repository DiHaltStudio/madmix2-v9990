; Two renderer service-cost fixtures, same real captured scene, stock Z80.
; This is NOT the game port. No game logic/audio, streaming or cache misses.
; All transactions owned by main loop with DI; no long-DI policy for final port.
    include "../build/fixture-config.inc"
    org $C000
entry:
    xor a
    out ($6F),a
    ld a,2
    out ($67),a
    xor a
    out ($67),a
    ld b,6
    if MODE_B1
    ld a,$82
    else
    ld a,5
    endif
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
    ld a,4                 ; P1 sprite base 10000
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
    include "../build/fixture-uploads.inc"
    call vblank
    ld b,14
    xor a
    call reg_write
    ld hl,palette
    ld bc,$C061
    otir
    if MODE_B1
    ld b,18
    ld a,1                 ; display hidden composition page Y=256
    call reg_write
    ld a,$C2               ; bitmap display, cursors disabled, VRAM mode 010
    else
    ld a,$82               ; pattern display and hardware sprites
    endif
    ld b,8
    call reg_write
    ld a,1
    ld ($CFF0),a           ; initialization complete marker
frame:
    call vblank
service_start:
    if MODE_B1
    ld hl,commands
    ld d,COMMAND_COUNT
command_loop:
    call wait_command
    ld a,32
    out ($64),a
    ld bc,$1563            ; write all R32..R52, including BOTH bytes of NY
    otir
    dec d
    jr nz,command_loop
    call wait_command
    else
    ld a,3
    ld de,$FE00
    call set_write
    ld hl,sat
    ld bc,(SPAT_BYTES<<8)+$60
    otir                    ; fixed scene: active entries plus one disabled slot
    endif
service_end:
    ld hl,($CFF2)
    inc hl
    ld ($CFF2),hl
    jp frame
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
palette: incbin "../build/fixture-palette.bin"
    if MODE_B1
commands: incbin "../build/b1-commands.bin"
    else
sat: incbin "../build/p1-sat.bin"
    endif
    assert $ < $CFF0
