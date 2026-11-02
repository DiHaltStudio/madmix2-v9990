; One-shot loaded over the expired title helper in page-zero RAM.
; Cooperative VBlank presentation: the IRQ keeps exclusive ownership of sound.
; Completed hidden VRAM SATs are independent from the next-frame back SAT.
    include "../build/smooth-api.inc"
    include "../build/gameplay-config.inc"
FRAME_TICKS equ 6
    org $0680
    jp reset
    jp reset
    jp service
    jp begin_frame
    jp prepare
    jp mark_piece
    jp commit
    jp pose_anchor
    jp finish_steps
    jp actor_insert
    jp actor_append
    jp actor_store
    jp actor_shift
    jp actor_draw
    jp logic_step
    jp wait_gate
    jp life_reset
    jp player_component
    jp wait_frame
    jp pattern_lookup
    jp terrain_aliases
    jp world_steps
    jp world_step_loop
    jp sat_hidden
    jp occupancy_pointers
    jp cork_move
finish_steps:
    call service
    ld a,(active)
    or a
    jr nz,finish_steps
    ret
reset:
    call $E018
    ld a,($105F)
    or a
    ld a,32
    jr z,reset_limit
    ld a,64
reset_limit:
    ld (actor_delta_limit),a
    ld (history_dx_limit+1),a
    ld (history_dy_limit+1),a
    add a,a
    inc a
    ld (history_dx_span+1),a
    ld (history_dy_span+1),a
    ld b,10
    ld a,128                ; later raster checkpoint avoids an idle half-frame wait
    call reg_write
    ld b,11
    xor a
    call reg_write
    xor a
    ld (active),a
    ld (valid),a
    ld (queue_drawing),a
    ld (actor_component),a
    ld ($C282),a
    ld (clock_valid),a
    ld ($C280),a
    ld ($C281),a
    ld a,125
    ld (composed_count),a
    ld (composed_full_count),a
    ld hl,0
    ld (generation),hl
    ld hl,$D000
    ld de,$D001
    ld bc,$07FF
    ld (hl),0
    ldir
    ld hl,$B800
    ld de,$B801
    ld bc,1535
    ld (hl),$FF
    ldir
    ld hl,$CA00
    ld de,$CA01
    ld bc,255
    ld (hl),$FF
    ldir
    ld hl,$C400
    ld de,$C401
    ld bc,1023
    ld (hl),$FF
    ldir
    ret
; Called with all caller registers live; DE/BC are original camera coordinates.
begin_frame:
    push af
    push bc
    push de
    push hl
    xor a
    ld ($BE7F),a            ; lowest possible unused retained-pattern slot
    ld ($C281),a
    ld hl,(generation)
    inc hl
    ld (generation),hl
    call $E015
    ld hl,($3F94)
    ld de,(previous_x)
    call delta
    ld (pending_x),a
    ld hl,($3F96)
    ld de,(previous_y)
    call delta
    ld (pending_y),a
    ld a,(valid)
    or a
    jr nz,keep_delta
    xor a
    ld (pending_x),a
    ld (pending_y),a
keep_delta:
    ld hl,($3F94)
    ld (previous_x),hl
    ld hl,($3F96)
    ld (previous_y),hl
    ld a,1
    ld (valid),a
    pop hl
    pop de
    pop bc
    pop af
    ret
; Continuous camera movement up to32 pixels fits the padded half-step view.
delta:
    or a
    sbc hl,de
    ld de,32
    add hl,de
    ld a,h
    or a
    jr nz,delta_cut
    ld a,l
    cp 65
    jr nc,delta_cut
    sub 32
    ret
delta_cut:
    xor a
    ld (valid),a
    ret
 ; A=pose ID. Only player-draw components are camera anchored. Floor-trap
; poses48/49 are world entities and use their own interpolated screen motion.
pose_anchor:
    push af
    ld a,($C280)
    or a
    jr nz,save_anchor
    ld a,(queue_drawing)
    add a,a
save_anchor:
    ld ($C281),a
    pop af
    ret
mark_piece:
    push af
    push hl
    ld a,(piece_count)
    ld l,a
    ld h,$C2
    ld a,($C281)
    ld (hl),a
    inc h
    ld a,(pose_dx)
    ld (hl),a
    set 7,l
    ld a,(pose_dy)
    ld (hl),a
    pop hl
    pop af
    ret
; No visible writes here: snapshot completed back-frame metadata and SAT.
prepare:
    xor a
    ld (active),a
    ; Both upload buffers are complete before the next logic step. Compose
    ; straight from the finished back SAT; a second RAM snapshot is redundant.
    ld hl,($3F94)
    ld (front_world_x),hl
    ld hl,($3F96)
    ld (front_world_y),hl
    ld a,(piece_count)
    ld (front_count),a
    ld a,(sprite_page)
    ld (front_page),a
    ld hl,(scroll_x)
    ld (front_x),hl
    ld hl,(scroll_y)
    ld (front_y),hl
    call stage_full_sat    ; direct full SAT does not need temporary offsets
    ld a,(pending_x)
    call half
    ld (offset_x),a
    ld a,(pending_y)
    call half
    ld (offset_y),a
    ld a,1
    ld (phase),a
    jp $E02A                ; compose midpoint directly into hidden VRAM
half:
    ; Signed rounding away from zero; exact for regular even camera deltas.
    bit 7,a
    jr nz,half_negative
    inc a
half_negative:
    sra a
    ret
; Called by present() in VBlank after the prepared frame has replaced the old one.
commit:
    call $E027              ; publish completed name window within VBlank
    ld a,2
    out ($66),a
    ld a,FRAME_TICKS/2
    ld (raster_remaining),a
    ld a,(audio_clock)
    ld (published_tick),a
    ld a,1
    ld (clock_valid),a
    ld (active),a
    ld a,(front_page)
    add a,a
    add a,12
    ld b,25
    call reg_write
    call publish
commit_done:
    ret
; Safe checkpoints occur only BETWEEN VRAM transactions; all registers preserved.
service:
    push af
    ld a,(active)
    or a
    jr z,service_return
    ; Count real display frames. Once due, keep doing useful work until VR
    ; instead of blocking from line128 to blank. Only vertical IRQ owns audio;
    ; its handler leaves separately polled line flags intact.
    ld a,(raster_remaining)
    or a
    jr z,service_due
    in a,($66)
    and 2
    jr z,service_return
    out ($66),a
    push hl
    ld hl,raster_remaining
    dec (hl)
    pop hl
    jr nz,service_return
service_due:
    in a,($65)
    and $40
    jr z,service_return
    ; Save the complete caller context only when a publication is due.
    ; Empty polls are frequent inside map, movement and actor loops.
    push bc
    push de
    push hl
    push ix
    push iy
final_step:
    xor a
    ld (active),a
    ld (phase),a
    ld (offset_x),a
    ld (offset_y),a
service_publish:
    call publish
service_pop:
    pop iy
    pop ix
    pop hl
    pop de
    pop bc
service_return:
    pop af
    ret
; The fixed HUD is untouched. Actor coordinates receive exactly the inverse
; of camera fine scroll; protagonist entries never receive either offset.
publish:
    ld a,(offset_y)
    ld e,a
    add a,a
    sbc a,a
    ld d,a
    ld hl,(front_y)
    or a
    sbc hl,de
    ld a,l
    ld b,21
    call reg_write
    ld a,h
    and 1
    ld b,22
    call reg_write
    ld a,(offset_x)
    ld e,a
    add a,a
    sbc a,a
    ld d,a
    ld hl,(front_x)
    or a
    sbc hl,de
    ld a,l
    and 7
    ld b,23
    call reg_write
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    ld a,l
    and 63
    ld b,24
    call reg_write
    call $E02D              ; GPU copies the retained SAT, no CPU upload in blank

publish_done:
    ret
; Full phase has no interpolation. Reverse the finished back SAT straight into
; hidden3FA00, avoiding a separate RAM construction and subsequent upload.
stage_full_sat:
    ld a,3
    ld de,$FA00
    call set_write
    ld a,(front_count)
    or a
    jr z,stage_full_tail
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    ld de,$C000-4
    add hl,de
    ld c,$60
    ld de,-8
stage_full_entry:
    outi
    outi
    outi
    outi
    add hl,de
    dec a
    jr nz,stage_full_entry
stage_full_tail:
    ld a,(front_count)
    ld b,a
    ld a,(composed_full_count)
    sub b
    jr c,stage_full_extra
    call nz,stage_full_hide
stage_full_extra:
    ; Retire the three unused hardware slots too when the staged range is full.
    ld a,(composed_full_count)
    cp 125
    jr z,stage_full_three
    ld a,(front_count)
    cp 125
    jr nz,stage_full_done
stage_full_three:
    ld a,3
    call stage_full_hide
stage_full_done:
    ld a,(front_count)
    ld (composed_full_count),a
    ret
stage_full_hide:
    ld b,a
stage_full_hidden:
    xor a
    out ($60),a
    out ($60),a
    out ($60),a
    ld a,$10
    out ($60),a
    djnz stage_full_hidden
    ret
; Reverse the midpoint SAT directly into hidden3F800. Per-entry interpolation
; reads the completed back SAT and stable flags/deltas, never a future frame.
compose_sat:
    ld a,3
    ld de,$F800
    call set_write
    ld a,(front_count)
    or a
    jp z,publish_hidden
    ld e,a
    ld d,0
    ld hl,$C200-1
    add hl,de
    push hl
    pop iy
    ld hl,0
    add hl,de
    add hl,hl
    add hl,hl
    ld de,$C000-4
    add hl,de
    push hl
    pop ix
compose_intermediate:
    ; IX indexes flags; IY straddles X/Y deltas at offsets -64/+64.
    ; HL walks the SAT without four costly indexed loads per component.
    push ix
    pop hl
    push iy
    pop ix
    push hl
    ld de,$140
    push ix
    pop hl
    add hl,de
    push hl
    pop iy
    pop hl
    ld a,(offset_y)
    ld (compose_camera_y+1),a
    ld a,(offset_x)
    ld (compose_camera_x+1),a
    ld a,(front_count)
    ld b,a
    ld de,-8
publish_actor:
    ; Classify once per piece, then write the four bytes without repeating
    ; the same class tests for X and Y. DE is free after pointer setup.
    ld a,(ix+0)
    or a
    jr z,compose_camera_actor
    cp 2
    jr z,compose_moving_actor
    jr compose_anchor_actor
compose_camera_actor:
    ld a,(hl)
compose_camera_y:
    add a,0
    out ($60),a
    inc hl
    ld a,(hl)
    out ($60),a
    inc hl
    ld a,(hl)
compose_camera_x:
    add a,0
    out ($60),a
    inc hl
    ld a,(hl)
    out ($60),a
    inc hl
    jr compose_record_done
compose_moving_actor:
    ld a,(hl)
    add a,(iy+64)
    out ($60),a
    inc hl
    ld a,(hl)
    out ($60),a
    inc hl
    ld a,(hl)
    add a,(iy-64)
    out ($60),a
    inc hl
    ld a,(hl)
    out ($60),a
    inc hl
    jr compose_record_done
compose_anchor_actor:
    ld a,(hl)
    out ($60),a
    inc hl
    ld a,(hl)
    out ($60),a
    inc hl
    ld a,(hl)
    out ($60),a
    inc hl
    ld a,(hl)
    out ($60),a
    inc hl
compose_record_done:
    add hl,de
    dec ix
    dec iy
    djnz publish_actor
publish_hidden:
    ld a,(front_count)
    ld b,a
    ld a,(composed_count)
    sub b
    jr c,compose_extra
    call nz,stage_full_hide
compose_extra:
    ld a,(composed_count)
    cp 125
    jr z,compose_three
    ld a,(front_count)
    cp 125
    jr nz,compose_done
compose_three:
    ld a,3
    call stage_full_hide
compose_done:
    ld a,(front_count)
    ld (composed_count),a
    ret
phase: db 1
composed_count: db 125
active: db 0
valid: db 0
previous_x: dw 0
previous_y: dw 0
pending_x: db 0
pending_y: db 0
front_world_x: dw 0
front_world_y: dw 0
front_x: dw 0
front_y: dw 0
front_page: db 0
front_count: db 0
published_tick: db 0
offset_x: db 0
offset_y: db 0
queue_drawing: db 0
actor_component: db 0
pose_dx: db 0
pose_dy: db 0
generation: dw 0
history_key: dw 0
history_x: db 0
history_y: db 0
history_probes: db 0
queue_dx: db 0
queue_dy: db 0

; Original depth records move during sorting. Mirror precisely that LDDR into
; D800..DCB8, holding two screen-motion bytes per four-byte component.
actor_shift:
    call service
    push bc
    push de
    push hl
    push de
    ld de,$D800-$DCB9
    add hl,de
    ex de,hl
    pop hl
    push de
    ld de,$D800-$DCB9
    add hl,de
    pop de
    ex de,hl
    lddr
    pop hl
    pop de
    pop bc
    call service            ; bound the two independent queue transfers
    lddr                   ; replay patched ED B8 E1
    pop hl
    jp $64B2
actor_insert:
    call service
    push af
    xor a
    ld (actor_component),a
    pop af
    ld hl,$3FB8
    jp $6474
actor_append:
    call service
    push af
    ld a,(actor_component)
    inc a
    ld (actor_component),a
    pop af
    ld hl,($64C8)
    jp $64BA
; Preserve the original queue writer's inputs. History is indexed by entity IX
; plus component ordinal, never by painter order or sprite pose number.
actor_store:
    call service
    push iy
    push af
    push bc
    push de
    push hl
    call actor_history
    pop hl
    push hl
    ld de,$D800-$DCB9
    add hl,de
    ld a,(queue_dx)
    ld (hl),a
    inc hl
    ld a,(queue_dy)
    ld (hl),a
    pop hl
    pop de
    pop bc
    pop af
    pop iy
    ld (hl),c
    inc hl
    ld (hl),e
    jp $64BF
; Hashed eight-byte record: IX tag(2), component, X, Y, generation(2), occupied.
; Collisions probe another slot; missed frames/teleports use camera-only motion.
actor_history:
    push ix
    pop hl
    and 127
    cp 48
    jr z,history_hazard
    cp 49
    jr nz,history_identity
history_hazard:
    ld hl,$E7F0              ; dedicated identity, never alias the last actor IX
history_identity:
    ld (history_key),hl
    ld a,e
    and $FC
    ld (history_x),a
    ld a,d
    ld (history_y),a
    ld a,(pending_x)
    neg
    ld (queue_dx),a
    ld a,(pending_y)
    neg
    ld (queue_dy),a
    ld a,(actor_component)
    ld b,a
    add a,a
    add a,a
    add a,a
    add a,b
    add a,a
    add a,a
    add a,b                ; 37*component
    add a,l
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,$D000
    add hl,de
    push hl
    pop iy
    xor a                  ; decrementing zero bounds probing to256 records
    ld (history_probes),a
history_lookup:
    ld a,(iy+7)
    or a
    jr z,history_save
    ld hl,(history_key)
    ld a,(iy+0)
    cp l
    jr nz,history_next
    ld a,(iy+1)
    cp h
    jr nz,history_next
    ld a,(actor_component)
    cp (iy+2)
    jr nz,history_next
    ld hl,(generation)
    dec hl
    ld a,(iy+5)
    cp l
    jr nz,history_save
    ld a,(iy+6)
    cp h
    jr nz,history_save
    ld a,(history_x)
    sub (iy+3)
    ld b,a
history_dx_limit:
    add a,ACTOR_DELTA_LIMIT
history_dx_span:
    cp 2*ACTOR_DELTA_LIMIT+1
    jr nc,history_save
    ld a,(history_y)
    sub (iy+4)
    ld c,a
history_dy_limit:
    add a,ACTOR_DELTA_LIMIT
history_dy_span:
    cp 2*ACTOR_DELTA_LIMIT+1
    jr nc,history_save
    ld a,b
    ld (queue_dx),a
    ld a,c
    ld (queue_dy),a
history_save:
    ld hl,(history_key)
    ld (iy+0),l
    ld (iy+1),h
    ld a,(actor_component)
    ld (iy+2),a
    ld a,(history_x)
    ld (iy+3),a
    ld a,(history_y)
    ld (iy+4),a
    ld hl,(generation)
    ld (iy+5),l
    ld (iy+6),h
    ld (iy+7),1
    ret
history_next:
    ld a,(history_probes)
    and 7
    call z,service
    push iy
    pop hl
    ld de,8
    add hl,de
    res 3,h                ; wrap D800 back to D000 within the history table
    push hl
    pop iy
    ld hl,history_probes
    dec (hl)
    ret z                  ; full table: camera-only fallback, no identity alias
    jp history_lookup
; Called instead of the depth group's CALL NZ,55A1. HL points at its pose byte.
actor_draw:
    push af
    push bc
    push de
    push hl
    ld de,$D800-$DCB9-3
    add hl,de
    ld a,(hl)
    call half
    neg
    ld (pose_dx),a
    inc hl
    ld a,(hl)
    call half
    neg
    ld (pose_dy),a
    ld a,1
    ld (queue_drawing),a
    pop hl
    pop de
    pop bc
    pop af
    call $55A1
    xor a
    ld (queue_drawing),a
    ret
; Every simulation step is rendered. The display deadline, not catch-up
; execution, paces gameplay; no animation phase may be discarded.
logic_step:
    call service
    jp $38E4
wait_frame:
    ld a,(clock_valid)
    or a
    jp z,vblank
wait_frame_loop:
    ld a,(published_tick)
    ld b,a
    ld a,(audio_clock)
    sub b
    cp FRAME_TICKS-1
    jr c,wait_frame_loop
    ; Start at a fresh blank. Merely being inside blank does not leave enough
    ; time for names plus SAT when preparation finishes close to its end.
    jp vblank
; Original press/release gate, also used for H pause. Rebase after a wait so
; time spent paused/at READY never becomes an overdue burst of simulation.
wait_gate:
    call display_on         ; complete STAGE/READY; do not blank on READY/pause exit
    call $580E
    call $5800
    push af
    xor a
    ld (clock_valid),a
    ld ($C282),a
    pop af
    ret
life_reset:
    call reset
    jp $4220
; Death animation can jump directly into the player's body loop, bypassing
; draw_player. Keep these components anchored too, preserving the caller flag.
player_component:
    push bc
    ld b,a
    ld a,($C280)
    push af
    ld a,1
    ld ($C280),a
    ld a,b
    call $55A1
    pop af
    ld ($C280),a
    pop bc
    ret
 ; Retained atlas mapping: B800/BA00 (512 entries), BC00/BD00 tags,
; BE00 current-frame usage. Eviction never overwrites a slot already referenced
; by the back SAT. The other sprite page remains untouched and visible.
pattern_lookup:
    ld a,(command)
    rrca
    rrca
    rrca
    rrca
    and 15
    ld e,a
    ld a,(command+2)
    and $F0
    or e
    ld l,a
    ld a,(sprite_page)
    add a,a
    add a,$B8
    ld d,a
    ld a,(command+3)
    and 1
    add a,d
    ld h,a
    ld (atlas_mapping),hl
    ld a,(hl)
    cp 125
    jr nc,pattern_allocate
    ld (pattern_slot),a
    ld l,a
    ld h,$BE
    ld (hl),1
    or a
    ret
pattern_allocate:
    ld a,($BE7F)
    ld l,a
    ld h,$BE
pattern_find:
    ld a,(hl)
    or a
    jr z,pattern_free
    inc l
    jr pattern_find
pattern_free:
    ld (hl),1
    ld a,l
    ld (pattern_slot),a
    inc a
    ld ($BE7F),a            ; all lower slots stay used until the next frame
    dec a
    add a,a
    ld l,a
    ld a,(sprite_page)
    add a,$BC
    ld h,a
    push hl
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,d
    cp $FF
    jr z,pattern_empty
    ld a,(sprite_page)
    add a,a
    add a,$B8
    add a,d
    ld h,a
    ld l,e
    ld (hl),$FF
pattern_empty:
    pop de
    ld hl,(atlas_mapping)
    ld a,l
    ld (de),a
    inc de
    ld a,(sprite_page)
    add a,a
    add a,$B8
    ld b,a
    ld a,h
    sub b
    ld (de),a
    ld a,(pattern_slot)
    ld (hl),a
    scf
    ret
atlas_mapping: dw 0
 ; Page-private animated terrain patterns. Name tables retain logical IDs;
; changing CB00 aliases therefore costs one GPU copy per alias, not one name
; rewrite per occurrence. The immutable master is at physical 72000.
terrain_aliases:
    call occupancy_pointers
    ld iy,$CA00
    ld a,(sprite_page)
    or a
    jr z,terrain_alias_page
    ld iy,$CA80
terrain_alias_page:
    xor a
    ld (terrain_family),a
    ld a,($67C7)
    cp $80
    jr nz,terrain_alias_start
    ld a,56
    ld (terrain_family),a
terrain_alias_start:
    ld hl,64
    ld (command+8),hl
    ld hl,8
    ld (command+10),hl
    xor a
    ld (terrain_index),a
terrain_alias_next:
    ld a,(terrain_index)
    ld l,a
    ld h,$CB
    ld a,(hl)
    ld hl,terrain_family
    add a,(hl)
    cp (iy+0)
    jr z,terrain_alias_done
    call service
    ld (iy+0),a
    push af
    call wait_command
    pop af
    call terrain_coordinate
    ld (command),hl
    ld l,e
    ld h,0
    ld de,1600             ; (72000-40000)/128, plane-B master
    add hl,de
    ld (command+2),hl
    ld a,(terrain_index)
    ld hl,terrain_family
    add a,(hl)
    call terrain_coordinate
    ld (command+4),hl
    ld a,(sprite_page)
    ld h,a
    ld l,e
    ld (command+6),hl
    ld hl,$FF00             ; P1: terrain aliases belong only to upper bank B
    ld (command+14),hl
    ld a,32
    out ($64),a
    ld hl,command
    ld bc,$1563
    otir
terrain_alias_done:
    inc iy
    ld a,(terrain_index)
    inc a
    ld (terrain_index),a
    cp 56
    jr nz,terrain_alias_next
    call wait_command
    ld hl,16
    ld (command+8),hl
    ld (command+10),hl
    ret
; A=metatile number. HL=horizontal pixel, E=vertical offset within bank.
terrain_coordinate:
    push af
    and 3
    rrca
    rrca
    ld l,a
    ld h,2                  ; P1 command X bit9 selects plane B
    pop af
    and $FC
    add a,a
    ld e,a
    ret
 ; Scale only at the three call sites: the original internal DJNZ target
; at 3A4C must remain intact. Tail jump preserves each caller's return address
; and every original per-unit collision/exit check.
world_steps:
    push af
    ld a,(cork_moving)
    or a
    jr z,world_steps_normal
    pop af
    ld c,1                  ; cork wrapper already scaled total unit budget
    jp $3A4B                ; retain original per-unit map collision checks
world_steps_normal:
    pop af
    call service            ; also bound multi-iteration rolling-ball movement
    push af
    ld a,($105F)
    or a
    jr z,world_steps_stationary
    pop af
    push af
    or a
    jr z,world_steps_stationary
    sla c
world_steps_stationary:
    pop af
    jp $3A4B
; Cork movement from original5272 only. In A=stream iterations, IX=cork,
; DE/BC=world coordinates. Return original coordinate convention and record.
; Expand the same STANDARD/HARD budget into one-unit moves, stopping at an
; exact open enemy exit before another iteration can step past it. Original
;51FC starts the insertion stream on its next update; timer/height stay owned
; by that state machine. Other objects never take this path.
cork_move:
    push af
    ld a,($52AC)
    or a
    jr nz,cork_original
    pop af
    add a,a                 ; original object iteration moves two world units
    ld l,a
    ld a,($105F)
    or a
    ld a,l
    jr z,cork_budget
    add a,a                 ; HARD retains its existing doubled speed
cork_budget:
    or a
    ret z
    ld (cork_units),a
    ld a,1
    ld (cork_moving),a
cork_unit:
    call service            ; bounded presentation checkpoint between units
    ld a,1
    call $4D69              ; direction/bounce/collision and record writes
    ld hl,($3F33)
    or a
    sbc hl,de
    jr nz,cork_second
    ld hl,($3F35)
    or a
    sbc hl,bc
    jr z,cork_done
cork_second:
    ld hl,($3F39)
    ld a,h                  ; original second exit is optional (Y high=0)
    or a
    jr z,cork_continue
    ld hl,($3F37)
    or a
    sbc hl,de
    jr nz,cork_continue
    ld hl,($3F39)
    or a
    sbc hl,bc
    jr z,cork_done
cork_continue:
    ld hl,cork_units
    dec (hl)
    jr nz,cork_unit
cork_done:
    xor a
    ld (cork_moving),a
    ret
cork_original:
    pop af
    jp $4D69                ; global insertion timer preserves old behavior
cork_moving: db 0
cork_units: db 0
 ; Once the exit mask is zero, the remaining budget cannot move the actor.
; The original checks are read-only. Finish without repeating them on the same
; blocked intersection, preserving AF and the BC/DE/HL return contract.
world_step_loop:
    ; AND H at3A70 already supplies Z; POP HL/BC preserve those flags.
    jr z,world_step_finish
    djnz world_step_continue
world_step_finish:
    ld c,l
    jp $3A76
world_step_continue:
    jp $3A4C
sat_hidden:
    xor a
    ld (hardware_count),a
    ret
 ; Tile remaps atCB00 remain dynamic. Cache only alias*64+family_base,
; eliminating repeated shifts/base arithmetic for every occupancy query.
occupancy_pointers:
    push af
    push bc
    push de
    push hl
    ld hl,($67C6)
    ld de,(occupancy_base)
    or a
    sbc hl,de
    jr z,occupancy_pointers_done
    ld hl,($67C6)
    ld (occupancy_base),hl
    ld de,$C800
    ld bc,64
occupancy_pointer:
    ld a,l
    ld (de),a
    inc d
    ld a,h
    ld (de),a
    dec d
    add hl,bc
    inc e
    jr nz,occupancy_pointer
occupancy_pointers_done:
    pop hl
    pop de
    pop bc
    pop af
    ret
occupancy_base: dw 0
actor_delta_limit: db 64
terrain_family: db 0
terrain_index: db 0
composed_full_count: db 125
hardware_count: db 125
raster_remaining: db 0
clock_valid: db 0
    assert $<$0E80
    ds $0E80-$,0
