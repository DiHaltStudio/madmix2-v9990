; Diagnostic ASCII16 boot. Z80, primary-slot HB-10P fixture only.
; Keeps BIOS mapped; all bank-switching code is copied to page 3 RAM.
    org $4000
    db "AB"
    dw boot
    dw 0,0,0
    ds 6,0
boot:
    di
    ld sp,$F380
    xor a
    ld ($F3DB),a
    call $005F
    xor a
    ld ($F3DB),a
    ld a,2
    out ($67),a
    xor a
    out ($67),a
    ld a,$C6
    out ($64),a
    ld a,5
    out ($63),a
    in a,($63)
    cp 5
    jr nz,missing
    ld a,$45
    out ($63),a
    in a,($63)
    cp $45
    jr nz,missing
    ld hl,found
    call print
    ei
    ld b,60
hold:
    halt
    djnz hold
    di
    ld hl,resident
    ld de,$C000
    ld bc,resident_end-resident
    ldir
    jp $C000
missing:
    ld hl,not_found
    call print
idle:
    ei
    halt
    jr idle
print:
    ld a,(hl)
    or a
    ret z
    inc hl
    push hl
    call $00A2
    pop hl
    jr print
found: db "V9990 found!",13,10,"Mad Mix 2 - renderer evaluation",13,10,0
not_found: db "V9990 NOT found!",13,10,0
resident:
    incbin "../build/fixture-resident.bin"
resident_end:
    ds $8000-$,$FF
