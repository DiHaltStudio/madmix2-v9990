; Port-only relocation of the original ENASLT helper to surviving low RAM.
; Reviewed disassembly: routine contracts and classified data retain original bytes.
; UNKNOWN marks unresolved bytes; unobserved coherent utilities are identified explicitly.
; Original load image: no cartridge patches. See load-sequence.md.
    org $0600
; -----------------------------------------------------------------------------
; ROUTINE relocated_enable_slot ($AF00)
; StoredC458, executedAF00. InA=slot ID (bit7 expanded, bits3..2 secondary,bits1..0 primary),H
; selects page. Computes masks throughAF20; primary-only mergesA8, expanded path changesFFFF
; andBIOS mirrorFCC5 viaAF0D. Main registers/flags change. Must execute in RAMpage2 while
; probingpage0.
L_AF00:    call 00620h
L_AF03:    jp m,0060Dh
L_AF06:    in a,(0A8h)
L_AF08:    and c
L_AF09:    or b
L_AF0A:    out (0A8h),a
L_AF0C:    ret
; -----------------------------------------------------------------------------
; ROUTINE expanded_slot_selection ($AF0D)
; Internal expanded branch: savesHL, callsAF44 to write secondary selection,
; updatesFCC5[primary], restores page selector and retriesAF00 with primary-onlyID. AF/BC/DE/HL
; scratch; primary register restored around accessingFFFF.
L_AF0D:    push hl
L_AF0E:    call 00644h
L_AF11:    ld c,a
L_AF12:    ld b,00h
L_AF14:    ld a,l
L_AF15:    and h
L_AF16:    or d
L_AF17:    ld hl,0FCC5h
L_AF1A:    add hl,bc
L_AF1B:    ld (hl),a
L_AF1C:    pop hl
L_AF1D:    ld a,c
L_AF1E:    jr 00600h
; -----------------------------------------------------------------------------
; ROUTINE derive_slot_masks ($AF20)
; InA=encoded slot,H=page selector. OutE=page mask,C=complement,B=selected primary
; bits,D=primary repeated across allpage fields. RestoresA andsetsflags fromAND A (sign selects
; expanded path). AF/BC/DE changed; HL unchanged.
L_AF20:    push af
L_AF21:    ld a,h
L_AF22:    rlca
L_AF23:    rlca
L_AF24:    and 03h
L_AF26:    ld e,a
L_AF27:    ld a,0C0h
L_AF29:    rlca
L_AF2A:    rlca
L_AF2B:    dec e
L_AF2C:    jp p,00629h
L_AF2F:    ld e,a
L_AF30:    cpl
L_AF31:    ld c,a
L_AF32:    pop af
L_AF33:    push af
L_AF34:    and 03h
L_AF36:    inc a
L_AF37:    ld b,a
L_AF38:    ld a,0ABh
L_AF3A:    add a,55h
L_AF3C:    djnz 0063Ah
L_AF3E:    ld d,a
L_AF3F:    and e
L_AF40:    ld b,a
L_AF41:    pop af
L_AF42:    and a
L_AF43:    ret
; -----------------------------------------------------------------------------
; ROUTINE write_secondary_slot ($AF44)
; InA=expanded ID,E=page mask,D=repeated primary field. Temporarily maps target primary into
; page3 to accessFFFF, merges desired secondary page bits, restoresA8.
; OutA=primaryID,H=complement mask,L=old secondary,D=newbits. AF/BC/DE/HL change; no stack use
; while page3 is temporarily changed except savedAF already pushed before switch.
L_AF44:    push af
L_AF45:    ld a,d
L_AF46:    and 0C0h
L_AF48:    ld c,a
L_AF49:    pop af
L_AF4A:    push af
L_AF4B:    ld d,a
L_AF4C:    in a,(0A8h)
L_AF4E:    ld b,a
L_AF4F:    and 3Fh
L_AF51:    or c
L_AF52:    out (0A8h),a
L_AF54:    ld a,d
L_AF55:    rrca
L_AF56:    rrca
L_AF57:    and 03h
L_AF59:    ld d,a
L_AF5A:    ld a,0ABh
L_AF5C:    add a,55h
L_AF5E:    dec d
L_AF5F:    jp p,0065Ch
L_AF62:    and e
L_AF63:    ld d,a
L_AF64:    ld a,e
L_AF65:    cpl
L_AF66:    ld h,a
L_AF67:    ld a,(0FFFFh)
L_AF6A:    cpl
L_AF6B:    ld l,a
L_AF6C:    and h
L_AF6D:    or d
L_AF6E:    ld (0FFFFh),a
L_AF71:    ld a,b
L_AF72:    out (0A8h),a
L_AF74:    pop af
L_AF75:    and 03h
L_AF77:    ret
