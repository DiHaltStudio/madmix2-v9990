; VGM-derived events: register/value pairs, 80=tick boundary, FF=loop.
; IRQ executes from page 0; only its short event read maps ROM into page 1.
; VGM-derived effects use channel A; their bounded resident run player owns it.
; Main render thread never switches cartridge banks, audio never touches V9990.
music_start:
    call music_stop       ; explicit V toggle/test restart only; stage calls removed
    di
    call $E818
    ei
    ret
music_stop:
    di
    call $E81B
    call $CE06
    call music_mix
    ei
    ret
; Both phases advance exactly the same persistent cursor; effects stay resident.
audio_tick:
    ld hl,audio_clock
    inc (hl)
    call $E81E
    jp $9E23

; Same slot selection contract as the validated stock-machine bridge.
; DI required. Preserve full expanded-slot IDs; actual MFR fixtures cover
; internal subslot1 ROM with subslot2 RAM, including turboR Z80.
music_select_rom:
    ld a,($03F4)
    bit 7,a
    jr z,music_primary_rom
    ld h,$40
    jp $0600
music_primary_rom:
    ld a,($03F0)
    jr music_primary
music_select_ram:
    ld a,($03F5)
    bit 7,a
    jr z,music_primary_ram
    ld h,$40
    jp $0600
music_primary_ram:
    ld a,($03F2)
music_primary:
    and 12
    ld b,a
    in a,($A8)
    and $F3
    or b
    out ($A8),a
    ret

; Merge resident channel-A effect over VGM music. SFX active when current
; stream pointer is nonzero; inactive A immediately restores recorded music.
; Own 11-byte output buffer, no writeback into effect player's private shadow.
music_mix:
    ld hl,music_shadow
    ld de,mixed_shadow
    ld bc,11
    ldir
    ld hl,($A303)
    ld a,h
    or l
    jr z,mix_commit
    ld hl,($A2F6)
    ld (mixed_shadow),hl
    ld a,($A2FE)
    ld (mixed_shadow+8),a
    ld a,($A2FD)
    and 9
    ld b,a
    ld a,(music_shadow+7)
    and $F6
    or b
    ld (mixed_shadow+7),a
    bit 3,b
    jr nz,mix_commit
    ld a,($A2FC)
    ld (mixed_shadow+6),a
mix_commit:
    ld hl,mixed_shadow
    xor a
    ld d,11
psg_write:
    out ($A0),a
    ld c,a
    ld a,(hl)
    out ($A1),a
    ld a,c
    inc a
    inc hl
    dec d
    jr nz,psg_write
    ret
    include "../build/ui-audio-api.inc"
audio_clock: db 0
mixed_shadow: ds 11,0
