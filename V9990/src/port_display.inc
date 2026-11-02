; Display transitions only: preserve every R#8 bit except DISP (bit7).
; AF clobbered; other registers and IFF preserved. Main thread owns register
; selection: audio IRQs acknowledge flags/PSG only, never select V9990 registers.
; C8 locks BOTH read and write auto-increment while reading/modifying R#8.
; Poll actual vertical retrace, not the audio counter, immediately before I/O.
display_off:
    call display_vblank
    ld a,$C8
    out ($64),a
    in a,($63)
    and $7F
    out ($63),a
    ret
display_on:
    call display_vblank
    ld a,$C8
    out ($64),a
    in a,($63)
    or $80
    out ($63),a
    ret
display_vblank:
    in a,($65)
    and $40
    jr nz,display_vblank
display_blank_start:
    in a,($65)
    and $40
    jr z,display_blank_start
    ret
