; Resident VGM-derived effects. Fixed runs replace original note/envelope work.
; CE00..CFFF is retired line-cache RAM. Data occupies checked original audio
; ranges9E26..A200/A310..A776; shadow, mute flag and request queue stay intact.
; Only channel A is borrowed. Tick/queue execute with IRQs disabled.
    org $CE00
    jp sfx_tick
    jp sfx_start
    jp sfx_reset
sfx_start:
    push af
    push de
    or a
    jr nz,sfx_start_done    ; original request table contains only channel A
    ld a,d
    or e
    jr z,sfx_start_reset
    ld ix,sfx_table
    ld b,15
sfx_find:
    ld a,(ix+0)
    cp e
    jr nz,sfx_find_next
    ld a,(ix+1)
    cp d
    jr z,sfx_found
sfx_find_next:
    ld a,5
    add a,ixl
    ld ixl,a
    jr nc,sfx_find_advance
    inc ixh
sfx_find_advance:
    djnz sfx_find
sfx_start_reset:
    call sfx_reset
    jr sfx_start_done
sfx_found:
    ld ($A303),de          ; retain original nonzero active-stream contract
    ld l,(ix+2)
    ld h,(ix+3)
    ld (sfx_ptr),hl
    ld a,(ix+4)
    ld (sfx_narrow),a
    xor a
    ld (sfx_left),a
sfx_start_done:
    pop de
    pop af
    ret
sfx_reset:
    ld hl,0
    ld ($A303),hl
    xor a
    ld (sfx_left),a
    ret
sfx_tick:
    push af
    ld hl,($A303)
    ld a,h
    or l
    jr z,sfx_mix
    ld a,(sfx_narrow)
    or a
    jr nz,sfx_note_tick
    ld a,(sfx_left)
    or a
    jr nz,sfx_hold
    ld hl,(sfx_ptr)
sfx_read:
    ld a,(hl)
    inc hl
    or a
    jr nz,sfx_row
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,d
    or e
    jr z,sfx_ended
    ex de,hl              ; pool seam or VGM loop, bounded by compiler
    jr sfx_read
sfx_row:
    ld (sfx_left),a
    ld a,(hl)
    inc hl
    ld ($A2F6),a
    ld a,(hl)
    inc hl
    ld b,a
    and 15
    ld ($A2F7),a
    ld a,b
    rrca
    rrca
    rrca
    rrca
    and 15
    ld ($A2FE),a
    ld a,(hl)
    inc hl
    ld ($A2FC),a
    ld a,(hl)
    inc hl
sfx_row_mixer:
    ld ($A2FD),a
    ld (sfx_ptr),hl
    ld a,(sfx_left)
sfx_hold:
    dec a
    ld (sfx_left),a
sfx_mix:
    call $A201            ; retained detour -> native music/SFX mixer
    pop af
    ret
sfx_ended:
    call sfx_reset
    jr sfx_mix
 ; Effect13 is a longer repeating channel-A phrase. VGM compilation deduplicates
; identical tone/volume runs; a token selects a fixed tone and literal volume
; profile. No original note arithmetic, modulation interpreter or ROM access.
sfx_note_tick:
    ld a,(sfx_left)
    or a
    jr nz,sfx_note_hold
    ld hl,(sfx_ptr)
sfx_note_read:
    ld a,(hl)
    inc hl
    or a
    jr nz,sfx_note_load
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,d
    or e
    jr z,sfx_ended
    ex de,hl
    jr sfx_note_read
sfx_note_load:
    ld (sfx_ptr),hl
    dec a
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    ld de,sfx_note_table
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld ($A2F6),de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl
    ld a,(hl)
    inc hl
    ld (sfx_left),a
    ld (sfx_volume_ptr),hl
    ld a,8
    ld ($A2FD),a
sfx_note_hold:
    ld hl,(sfx_volume_ptr)
    ld a,(hl)
    inc hl
    ld (sfx_volume_ptr),hl
    ld ($A2FE),a
    ld a,(sfx_left)
    dec a
    ld (sfx_left),a
    jr sfx_mix
sfx_volume_ptr: dw 0
sfx_ptr: dw 0
sfx_left: db 0
sfx_narrow: db 0
sfx_table:
    include "../build/sfx-table.inc"
    assert $<=$D000
    ds $D000-$,0
