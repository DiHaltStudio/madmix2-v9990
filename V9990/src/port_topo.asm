; Native Topo animation: original keyframes, four interpolated steps per update.
; ROM-precompiled tile frames; hidden name page filled then published at VBlank.
; No software bitmap rendering, sprite overflow or per-frame palette writes.
    org $88B8
    jp topo_entry
    ds $88D1-$,0
topo_entry:
    di
    call display_off
    ld b,8
    ld a,$42                ; configure hidden P1: sprites disabled, full VRAM
    call reg_write
    ld a,($03F4)
    ld h,$40
    call $0600
    ld a,TOPO_BANK
    ld (bank),a
    ld ($6000),a
    ld hl,$4000
    ld (stream),hl
    ld hl,TOPO_FRAMES
    ld (frames),hl
    xor a
    ld (page),a
    call vblank
    ld b,14
    ld a,192
    call reg_write
    ld hl,palette
    ld bc,$3061
    otir
    ld b,13
    ld a,12
    call reg_write
topo_frame:
    ld hl,(stream)
    ld a,(hl)
    cp $FF
    jr nz,bank_ready
    ld a,(bank)
    inc a
    ld (bank),a
    ld ($6000),a
    ld hl,$4000
bank_ready:
    ld a,(page)
    xor 1
    ld (page),a
    rlca
    rlca
    rlca
    rlca
    add a,$E0
    ld d,a
    ld e,0
    ld (names),de
    ld a,24
    ld (rows),a
row:
    ld de,(names)
    xor a
    out ($64),a
    ld a,e
    out ($63),a
    ld a,d
    out ($63),a
    ld a,7
    out ($63),a
    ld c,32
packet:
    ld a,(hl)
    inc hl
    bit 7,a
    jr nz,repeat
    ld b,a
literal:
    ld a,(hl)
    inc hl
    out ($60),a
    ld a,(hl)
    inc hl
    out ($60),a
    dec c
    djnz literal
    jr packet_done
repeat:
    and $7F
    ld b,a
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
repeat_word:
    ld a,e
    out ($60),a
    ld a,d
    out ($60),a
    dec c
    djnz repeat_word
packet_done:
    ld a,c
    or a
    jr nz,packet
    push hl
    ld hl,(names)
    ld de,128
    add hl,de
    ld (names),hl
    pop hl
    ld a,(rows)
    dec a
    ld (rows),a
    jr nz,row
    ld (stream),hl
topo_enable:
    call display_on
    ld b,21
    xor a
    call reg_write
    ld b,22
    ld a,(page)
    call reg_write
topo_published:
    ld hl,(frames)
    dec hl
    ld (frames),hl
    ld a,h
    or l
    jp nz,topo_frame
    call display_off
    ld b,22
    xor a
    call reg_write
    ld b,14
    ld a,192
    call reg_write
    ld hl,game_palette
    ld bc,$3061
    otir
    ld a,($03F5)
    ld h,$40
    call $0600
topo_done:
    ret
    include "port_display.inc"
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
palette: db 0,0,0,16,14,29
    ds 42,0
game_palette: incbin "../build/title-game-palette.bin"
stream: dw 0
frames: dw 0
names: dw 0
bank: db 0
page: db 0
rows: db 0
    include "../build/topo-config.inc"
    assert $<$A443
