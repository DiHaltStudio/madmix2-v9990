; ASCII16 bank 0. All game images retain original RAM addresses.
    org $4000
    db "AB"
    dw boot
    dw 0,0,0
    ds 6,0
; ROUTINE cartridge_boot ($4010)
; BIOS cartridge entry with page 1 ROM visible and writable page 3 RAM.
; Selects SCREEN 0 through BIOS CHGMOD, silences keyboard click before/after BIOS,
; copies the one-shot trampoline and original loader to their RAM addresses.
; Patches only original reader entry C52D..C52F to JP C700; the loader later
; relocates that patch to 015C. Jumps C350 with interrupts disabled, never returns.
; Main registers/BIOS work area change. Keep the complete expanded-slot ID
; for bridge/audio; primary, subslot and MFR fixtures verify those paths.
boot:
    di
    ; Distinct mapper pages before RAM probing, preserving the current page-3
    ; segment (BIOS work area and stack). Plain MSX1 RAM ignores these ports.
    in a,($FF)
    out ($FF),a
    xor 1
    out ($FE),a
    xor 3
    out ($FD),a
    xor 1
    out ($FC),a
    xor a
    ld ($F3DB),a
    ld a,15                 ; readable white text on blue, on the MSX output
    ld ($F3E9),a
    ld a,4
    ld ($F3EA),a
    ld ($F3EB),a
    ld a,40
    ld ($F3AE),a             ; SCREEN0 width
    xor a
    call $005F
    call $00C3              ; clear text screen and home cursor before detection
    di
    xor a
    ld ($F3DB),a
    ; Save cartridge slot identity while BIOS still selects it in page 1.
    in a,($A8)
    rrca
    rrca
    and 3
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
    ld a,(hl)
    and 12
    or b
    ld ($CFF4),a
    call probe_and_preload
    ld hl,presentation_bytes
    ld de,$DA00
    ld bc,presentation_end-presentation_bytes
    ldir
    ld hl,trampoline_bytes
    ld de,$C700
    ld bc,trampoline_end-trampoline_bytes
    ldir
    ld hl,loader_bytes
    ld de,$C350
    ld bc,714
    ldir
    ; C52D is relocated to 015C by the original loader. Replace only its entry.
    ld a,$C3
    ld ($C52D),a
    ld hl,$C700
    ld ($C52E),hl
    ld hl,restore_code
    ld de,$C900
    ld bc,restore_end-restore_code
    ldir
    ld a,$C3
    ld ($C406),a
    ld hl,$C900
    ld ($C407),hl
    ld a,$C9
    ld ($C39A),a             ; page2 stays in the probed RAM
    ld a,$C3
    ld ($C390),a
    ld ($C395),a
    ld hl,$C903
    ld ($C391),hl
    ld hl,$C906
    ld ($C396),hl
    jp $C350
; Probe on BIOS screen; preload with a RAM routine while bank 0 is hidden.
probe_and_preload:
    ld hl,boot_credits
    call print_message
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
    jr nz,no_board
    ld a,$45
    out ($63),a
    in a,($63)
    cp $45
    jr nz,no_board
    ld hl,found
    call print_message
    ei
    ld b,60
probe_hold:
    halt
    djnz probe_hold
    di
    ld hl,preload
    ld de,$C000
    ld bc,preload_end-preload
    ldir
    call $C000
    ret
no_board:
    ld hl,missing
    call print_message
no_board_wait:
    ei
    halt
    jr no_board_wait
print_message:
    ld a,(hl)
    or a
    ret z
    inc hl
    push hl
    call $00A2
    pop hl
    jr print_message
boot_credits: db "Topo Soft 1990",13,10,"V9990 DiHalt Studio 2026",13,10,0
found: db "V9990 found!",13,10,0
missing: db "V9990 NOT found!",13,10,0
preload: incbin "../build/port_preload.bin"
preload_end:
presentation_bytes: incbin "../build/port_presentation.bin"
presentation_end:
restore_code: incbin "../build/port_restore.bin"
restore_end:
; Embedded binaries must be assembled first; these are ROM data, not fallthrough.
trampoline_bytes:
    incbin "../build/port_trampoline.bin"
trampoline_end:
loader_bytes:
    incbin "../../MSX/build/loader.bin"
    ds $8000-$,$FF
