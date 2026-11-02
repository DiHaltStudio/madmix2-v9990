; One persistent VGM cursor from title/menu through loader and every stage.
; UI IRQ and native game IRQ call the same bounded tick; no state migration.
shared_music_start:
    ld a,(shared_music_active)
    or a
    ret nz
    ld a,MUSIC_BANK
    ld (shared_music_bank),a
    ld hl,$4000
    ld (shared_music_ptr),hl
    ld a,1
    ld (shared_music_active),a
    ret
shared_music_stop:
    xor a
    ld (shared_music_active),a
    ld hl,shared_music_shadow
    ld b,11
shared_silence:
    ld (hl),a
    inc hl
    djnz shared_silence
    ld a,$BF
    ld (shared_music_shadow+7),a
    ret
shared_music_tick:
    ld a,(shared_music_active)
    or a
    ret z
    call shared_select_rom
    ld a,(shared_music_bank)
    ld ($6000),a
    ld hl,(shared_music_ptr)
shared_event:
    call shared_read
    cp $80
    jr z,shared_done
    cp $FF
    jr z,shared_loop
    ld e,a
    ld d,0
    push hl
    ld hl,shared_music_shadow
    add hl,de
    ex de,hl
    pop hl
    call shared_read
    ld (de),a
    jr shared_event
shared_loop:
    ld a,MUSIC_LOOP_BANK
    ld (shared_music_bank),a
    ld ($6000),a
    ld hl,MUSIC_LOOP_PTR
    jr shared_event
shared_done:
    ld (shared_music_ptr),hl
    jp shared_select_ram
shared_read:
    ld a,(hl)
    inc hl
    bit 7,h
    ret z
    push af
    ld hl,$4000
    ld a,(shared_music_bank)
    inc a
    ld (shared_music_bank),a
    ld ($6000),a
    pop af
    ret
shared_select_rom:
    ld a,($03F4)
    bit 7,a
    jr z,shared_primary_rom
    ld h,$40
    jp $0600
shared_primary_rom:
    ld a,($03F0)
    jr shared_primary
shared_select_ram:
    ld a,($03F5)
    bit 7,a
    jr z,shared_primary_ram
    ld h,$40
    jp $0600
shared_primary_ram:
    ld a,($03F2)
shared_primary:
    and 12
    ld b,a
    in a,($A8)
    and $F3
    or b
    out ($A8),a
    ret
shared_psg:
    ld hl,shared_music_shadow
    xor a
    ld d,11
shared_psg_byte:
    out ($A0),a
    ld c,a
    ld a,(hl)
    out ($A1),a
    ld a,c
    inc a
    inc hl
    dec d
    jr nz,shared_psg_byte
    ret
; The final overlay no longer holds an obsolete stage IRQ/code dependency.
; Read128 bytes with DI, restore RAM, copy/permit IRQ, then select the helper
; bank again. Audio may change the mapper only between complete ROM reads.
shared_load_helpers:
    ld hl,$4000
    ld (shared_copy_source),hl
    ld ix,shared_copy_table
shared_copy_segment:
    ld e,(ix+0)
    ld d,(ix+1)
    ld (shared_copy_dest),de
    ld a,(ix+2)
    or a
    ret z
    ld (shared_copy_left),a
shared_copy_chunk:
    di
    call shared_select_rom
    ld a,SMOOTH_BANK
    ld ($6000),a
    ld hl,(shared_copy_source)
    ld de,$0500
    ld bc,128
    ldir
    ld (shared_copy_source),hl
    call shared_select_ram
    ld hl,$0500
    ld de,(shared_copy_dest)
    ld bc,128
    ei
    ldir
    ld (shared_copy_dest),de
    ld hl,shared_copy_left
    dec (hl)
    jr nz,shared_copy_chunk
    ld bc,3
    add ix,bc
    jr shared_copy_segment
shared_copy_table: dw $0680
    db 16
    dw $E000
    db 16
    dw $CE00
    db 4
    dw 0
    db 0
shared_copy_source: dw 0
shared_copy_dest: dw 0
shared_copy_left: db 0
shared_music_active: db 0
shared_music_bank: db MUSIC_BANK
shared_music_ptr: dw $4000
shared_music_shadow: db 0,0,0,0,0,0,0,$BF,0,0,0
