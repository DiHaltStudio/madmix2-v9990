; Shared V9990-only UI, copied from the stage overlay to surviving page-3 RAM.
    include "../build/port-art-config.inc"
    include "../build/port-music.inc"
    include "../build/smooth-config.inc"
    org $E800
    jp ui_init
    jp ui_clear
    jp ui_draw
    jp ui_choose
    jp ui_irq
    jp ui_vblank
    jp ui_input
    jp ui_reg
    jp shared_music_start
    jp shared_music_stop
    jp shared_music_tick
    jp shared_load_helpers
    jp ui_show
    jp display_off             ; E827, survives menu/game overlays
ui_init:
    call display_off
    ld a,$C8
    out ($64),a
    in a,($63)
    or $40                     ; configure UI sprite disable while hidden
    out ($63),a
    ei
    ld b,13
    ld a,ART_PLANE_PALETTES
    call ui_reg
    ld b,27
    xor a
    call ui_reg
    xor a
    out ($64),a
    out ($63),a
    ld a,$C0
    out ($63),a
    ld a,7
    out ($63),a
    ld hl,6144
    ld c,24
ui_name_row:
    ld b,32
ui_canvas_names:
    ld a,l
    out ($60),a
    ld a,h
    out ($60),a
    inc hl
    djnz ui_canvas_names
    ld b,32
    call ui_black_names
    dec c
    jr nz,ui_name_row
    ld c,8
ui_bottom_names:
    ld b,64
    call ui_black_names
    dec c
    jr nz,ui_bottom_names
    call ui_clear
    ei
    ret
ui_show:
    call ui_wait
    jp display_on
ui_black_names:
    ld a,1
    out ($60),a
    xor a
    out ($60),a
    djnz ui_black_names
    ret
ui_clear:
    ld ix,ui_clear_packets
    jp ui_draw
; Seven-byte copy descriptors: SX, SY(word), DX, DY offset, NX(0=256), NY.
ui_draw:
    ld a,(ix+0)
    cp $FF
    jr z,ui_wait
    call ui_wait
    ld a,(ix+0)
    ld (ui_command),a
    ld a,(ix+1)
    ld (ui_command+2),a
    ld a,(ix+2)
    ld (ui_command+3),a
    ld a,(ix+3)
    ld (ui_command+4),a
    ld a,(ix+4)
    ld (ui_command+6),a
    ld a,(ix+5)
    ld (ui_command+8),a
    or a
    ld a,0
    jr nz,ui_width
    inc a
ui_width:
    ld (ui_command+9),a
    ld a,(ix+6)
    ld (ui_command+10),a
    ld a,32
    out ($64),a
    ld hl,ui_command
    ld bc,$1563
    otir
    ld de,7
    add ix,de
    jr ui_draw
ui_wait:
    in a,($65)
    and 1
    jr nz,ui_wait
    ret
ui_choose:
    call display_off
    xor a
    ld ($105F),a
    ld (ui_last),a
    call ui_redraw
ui_release:
    call ui_input
    and $10
    jr nz,ui_release
    call ui_show             ; complete menu, released fire, inputs ready
ui_menu_visible:
ui_menu_loop:
    call ui_vblank
    call ui_input
    bit 4,e
    jr nz,ui_confirm
    and 15
    ld b,a
    ld a,(ui_last)
    cpl
    and b
    ld c,a
    ld a,b
    ld (ui_last),a
    ld a,c
    or a
    jr z,ui_menu_loop
    and $0A
    ld a,0
    jr nz,ui_select
    inc a
ui_select:
    ld b,a
    ld a,($105F)
    cp b
    jr z,ui_menu_loop
    ld a,b
    ld ($105F),a
    call ui_redraw
    jr ui_menu_loop
ui_confirm:
    call display_off            ; accepted fire: blank before waiting for release
ui_confirm_release:
    call ui_input
    and $10
    jr nz,ui_confirm_release
    ret
ui_redraw:
    call ui_clear
    ld a,($105F)
    or a
    ld ix,ui_normal
    jr z,ui_menu_draw
    ld ix,ui_hard
ui_menu_draw:
    jp ui_draw
; Only V9990 vertical flags tick music. Original MSX IRQ: acknowledge and return.
ui_irq:
    push af
    in a,($66)
    and 1
    jr nz,ui_audio_irq
    in a,($99)
    pop af
    ei
    ret
ui_audio_irq:
    out ($66),a
    push hl
    ld hl,ui_ticks
    inc (hl)
    pop hl
    in a,($99)
    push bc
    push de
    push hl
    push ix
    push iy
    exx
    ex af,af'
    push af
    push bc
    push de
    push hl
    call shared_music_tick
    call shared_psg
    pop hl
    pop de
    pop bc
    pop af
    ex af,af'
    exx
    pop iy
    pop ix
    pop hl
    pop de
    pop bc
    pop af
    ei
    ret
ui_vblank:
    ld a,(ui_ticks)
    ld b,a
ui_frame_wait:
    ld a,(ui_ticks)
    cp b
    jr z,ui_frame_wait
    ret
    include "port_display.inc"
ui_reg:
    push af
    ld a,b
    or $80
    out ($64),a
    pop af
    out ($63),a
    ret
    include "port_ui_input.inc"
ui_command: dw 0,0,0,1536,8,8
    db 0,$0C,$FF,0,0,0,0,0,$40 ; P1 UI canvas is lower bank A only
ui_ticks equ $105E
ui_last: db 0
ui_clear_packets:
    db 0
    dw 1440
    db 0,0,0,96,0
    dw 1440
    db 0,96,0,96,$FF
ui_credits:
    include "../build/ui-credits.inc"
ui_normal:
    include "../build/ui-normal.inc"
ui_hard:
    include "../build/ui-hard.inc"
    include "port_shared_music.inc"
    assert $<=$F000
