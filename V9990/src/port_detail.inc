; Preserve original 6062 background detail: a black pixel is emitted only when
; the original three-row mask is entirely foreground. Editable tiles compile a
; CPU one-bit occupancy view solely for this test; no framebuffer is drawn.
; Lowest-priority sprites hold dots so actors still cover them. Slot126 is a
; preloaded single black pixel in both cache pages, never allocated to actors.
detail_points:
    ld ix,detail_table
    ld a,60
    ld (details_left),a
detail_next:
    ; Four bounded occupancy queries leave ample lead for the midpoint while
    ; avoiding a complete register-save/service roundtrip for every dot.
    ld a,(details_left)
    and 3
    call z,$0686
    ld hl,($3F94)
    ld a,(ix+0)
    sub 32
    ld e,a
    ld d,0
    add hl,de
    ex de,hl
    ld hl,($3F96)
    ld a,(ix+1)
    ld c,a
    ld b,0
    add hl,bc
    ld b,h
    ld c,l
    ld a,c
    and 15
    cp 14
    jr nc,detail_slow
    call detail_fast
    jr nz,detail_skip
    jr detail_accept
detail_slow:
    ld a,3
    ld (detail_rows),a
detail_test_row:
    call occupancy_byte
    cpl
    and (ix+2)
    jr nz,detail_skip
    inc bc
    ld a,(detail_rows)
    dec a
    ld (detail_rows),a
    jr nz,detail_test_row
detail_accept:
    ld a,(piece_count)
    cp 125
    jr nc,detail_skip
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    ld de,sat
    add hl,de
    ld a,(ix+1)
    add a,16                ; y+1(detail)-1(SAT)+16(viewport)
    ld (hl),a
    inc hl
    ld (hl),126
    inc hl
    ld a,(ix+3)
    ld (hl),a
    inc hl
    ld (hl),ART_DETAIL_ATTR
    call $068F
    ld hl,piece_count
    inc (hl)
detail_skip:
    ld de,4
    add ix,de
    ld a,(details_left)
    dec a
    ld (details_left),a
    jr nz,detail_next
    ret

; Return eight occupancy bits at world pixel DE, row BC. Main BC/DE preserved.
; Camera alignment is a multiple of four; only 0/4 pixel shifts are needed.
occupancy_byte:
    call occupancy_aligned
    bit 2,e
    ret z
    push bc
    push de
    rlca
    rlca
    rlca
    rlca
    and $F0
    push af
    ex de,hl
    ld de,8
    add hl,de
    ex de,hl
    call occupancy_aligned
    rrca
    rrca
    rrca
    rrca
    and 15
    ld l,a
    pop af
    or l
    pop de
    pop bc
    ret
; Return source byte containing DE. BC/DE preserved, HL/AF scratch.
occupancy_aligned:
    call occupancy_address
    ld a,(hl)
    ret
; Return the occupancy byte address; world BC/DE remain intact.
occupancy_address:
    push bc
    push de
    ld a,c
    and 15
    add a,a
    add a,a
    ld h,a
    ld a,e
    and 31
    rrca
    rrca
    rrca
    and 3
    or h
    push af
    ; Map rows are 64 bytes and X cells are 32 world units. Build the
    ; same address as6005 without destructively shifting/restoring DE.
    ld a,c
    and $F0
    ld l,a
    ld h,b
    add hl,hl
    add hl,hl
    ld a,d
    and 7
    rlca
    rlca
    rlca
    ld b,a
    ld a,e
    rlca
    rlca
    rlca
    and 7
    or b
    ld e,a
    ld d,$A9
    add hl,de
    ld a,(hl)
    ld l,a
    ld h,$CB
    ld a,(hl)
    ld l,a
    ld h,$C8
    ld a,(hl)
    inc h
    ld h,(hl)
    ld l,a
    pop af
    ld e,a
    ld d,0
    add hl,de
    pop de
    pop bc
    ret
; For rows0..13 all three samples belong to the same metatile. AND the
; three rows before combining the two nibbles; no repeated map lookup needed.
; Rows14/15 retain the original cross-metatile path above.
detail_fast:
    call occupancy_address
    push hl
    pop iy
    ld a,(iy+0)
    and (iy+4)
    and (iy+8)
    bit 2,e
    jr z,detail_fast_test
    rlca
    rlca
    rlca
    rlca
    and $F0
    push af
    ld a,e
    and 31
    cp 24
    jr c,detail_adjacent
    ld hl,8
    add hl,de
    ex de,hl
    call occupancy_address
    push hl
    pop iy
    jr detail_right
detail_adjacent:
    inc iy
detail_right:
    ld a,(iy+0)
    and (iy+4)
    and (iy+8)
    rrca
    rrca
    rrca
    rrca
    and 15
    ld l,a
    pop af
    or l
detail_fast_test:
    cpl
    and (ix+2)
    ret
detail_rows: db 0
details_left: db 0
detail_table: incbin "../build/port-detail-points.bin"
