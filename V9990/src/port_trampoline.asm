; One-time relocation after the original loader has selected RAM in page 0.
; Opening expands graphics across page 3 and destroys the original C350 loader.
; Keep the resident tape substitute below the stage image and below its stack.
    org $C700
; ROUTINE cartridge_relocate_reader ($C700)
; First intercepted reader call: IX=destination, DE=count, original slot setup
; completed and page 0 writable. Copies bridge to 0300 and slot choices from
; C453..C456 to 03F0..03F3. Repoints the existing JP operand at 015D to 0300.
; Preserves BC/DE/HL and IX, then tail-jumps to bridge with the original caller's
; return address still on stack. Inherits DI from the original loader.
; Opening overwrites this C700 code later; it must execute exactly once.
    push hl
    push bc
    push de
    ld hl,$DA00
    ld de,$0680
    ld bc,$0800
    ldir
    ld hl,bridge_bytes
    ld de,$0300
    ld bc,bridge_end-bridge_bytes
    ldir
    xor a
    ld ($03F7),a
    ld hl,$C453
    ld de,$03F0
    ld bc,4
    ldir
    ld hl,slot_helper
    ld de,$0600
    ld bc,slot_helper_end-slot_helper
    ldir
    ld a,($CFF4)
    ld ($03F4),a
    ld a,($CFF6)
    ld ($03F5),a
    ld hl,$0300
    ld ($015D),hl
    pop de
    pop bc
    pop hl
    jp $0300
bridge_bytes:
    incbin "../build/port_bridge.bin"
bridge_end:

slot_helper: incbin "../build/port_slots.bin"
slot_helper_end:
    assert $<$C900
