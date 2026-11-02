; Experimental ASCII16 tape substitute, resident in page 0 after the original RAM mapping.
; Entry matches original reader: IX=destination, DE=length; five sequential calls.
; Saved original loader slot selections switch page 1 to cartridge/RAM.
; Copy through a page-0 buffer so code and stack survive either mapping.
; No original PSG, graphics, input or game routines are patched.
    org $0300
; ROUTINE cartridge_read_payload ($0300)
; In IX=RAM destination, DE=nonzero byte count, page 0/3 writable RAM, stack
; outside page 1. Consumes the next of five banks [1,2,3,4,6], no bounds check.
; Copies through 0500..05FF while alternating page 1 ROM/RAM mappings.
; Out IX=end destination, DE=0, A=0, carry=1; BC/HL preserved, interrupts DI.
; Other flags follow XOR A/SCF. Owns 0300..03F3 and mutable bookkeeping below.
; Non-reentrant: neither another load nor an IRQ may use the shared buffer.
bridge:
    di
    push bc
    push hl
    ld (remaining),de
    ld (destination),ix
    ld hl,(next_bank)
    ld a,(hl)
    inc hl
    ld (next_bank),hl
    ld (bank),a
    ld hl,$4000
    ld (source),hl
; Transfer at most 256 bytes. Payload starts at a bank boundary, so full chunks
; cannot straddle 8000; a partial final chunk ends this load immediately.
copy_chunk:
    ld hl,(remaining)
    ld bc,256
    ld a,h
    or a
    jr nz,size_ready
    ld c,l
    ld b,0
size_ready:
    ld (count),bc
    or a
    sbc hl,bc
    ld (remaining),hl
    call select_rom
    ld a,(bank)
    ld ($6000),a
    ld hl,(source)
    ld de,$0500
    ld bc,(count)
    ldir
    ; Advancing source to 8000 means the next chunk belongs to the next bank.
    bit 7,h
    jr z,source_ready
    ld hl,$4000
    ld a,(bank)
    inc a
    ld (bank),a
source_ready:
    ld (source),hl
    call select_ram
    ld hl,$0500
    ld de,(destination)
    ld bc,(count)
    ldir
    ld (destination),de
    ld a,($03F7)
    or a
    jr z,copy_no_audio
    ei
    nop                   ; permit pending IRQ with page1 RAM fully restored
    di
copy_no_audio:
    ld hl,(remaining)
    ld a,h
    or l
    jr nz,copy_chunk
    ld ix,(destination)
    ld de,0
    pop hl
    pop bc
    xor a
    scf
    ret
; Sequential tape-load schedule; not a stage number. All nine levels are in the
; final game image, so no further cartridge reads occur at stage transitions.
next_bank: dw banks
banks: db 1,2,3,4,6
bank: db 0
source: dw 0
destination: dw 0
remaining: dw 0
count: dw 0

; ROUTINE select_page1_rom
; No inputs. Selects saved cartridge page-1 slot bits from 03F0/03F1; tail-enters
; select_page1. AF/B/HL clobbered, C/DE unchanged. Must be called with DI.
select_rom:
    ld a,($03F4)
    ld h,$40
    jp $0600
select_ram:
    ld a,($03F5)
    ld h,$40
    jp $0600
    ds $03F0-$,0
slot_selections:
    ds 4,0
