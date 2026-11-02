; Port-only replacement for original loader's restoration and RAM selectors.
; AF00 is the original ENASLT helper, copied into the discovered page-2 RAM.
; Keep that RAM selected while choosing RAM pages 0/1, including cartridge RAM.
    org $C900
    jp restore
    jp ram_page0
    jp ram_page1
restore:
    ld a,($C455)
    and 3
    ld c,0
    call slot_identity
    ld ($CFF5),a
    ld a,($C455)
    rrca
    rrca
    and 3
    ld c,1
    call slot_identity
    ld ($CFF6),a
    ld a,($CFF4)
    ld h,$40
    call $AF00
    ; Page 2 already holds the probed RAM/helper. Restore other primary bits;
    ; do not overwrite an unrelated primary's entire secondary-slot register.
    ld a,($C455)
    and $30
    ld b,a
    ld a,($C453)
    and $CF
    or b
    out ($A8),a
    pop af
    ld ($8000),a
    ret
ram_page0:
    ld a,($CFF5)
    ld h,0
    jp $AF00
ram_page1:
    ld a,($CFF6)
    ld h,$40
    jp $AF00
; A=primary, C=page0/1. Return encoded BIOS slot ID from its own mirror.
slot_identity:
    ld e,a
    ld d,0
    ld hl,$FCC1
    add hl,de
    ld a,(hl)
    and $80
    or e
    ld b,a
    ld hl,$FCC5
    add hl,de
    ld a,c
    or a
    ld a,(hl)
    jr nz,secondary_ready
    rlca
    rlca
secondary_ready:
    and 12
    or b
    ret
