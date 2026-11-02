; Movement, fixed floor-trap projection, swept contacts and IRQ dispatch.
; Survives in unused page-3 RAM below the shared UI.
    include "../build/contacts-api.inc"
    org $E000
    jp player_move
    jp player_effects
    jp actor_entry
    jp object_entry
    jp swept_overlap
    jp swept_near
    jp game_irq
    jp contact_frame
    jp contact_reset
    jp restore_detail
    jp retry_menu
    jp hazard_start
    jp hazard_coords
    jp publish_names
    jp stage_sat
    jp publish_sat
    jp push_roller
    jp ball_near
    jp enemy_death
    jp runner_overlap
enemy_death:
    ld a,($105D)
    or a
    ret nz
    jp $53D2              ; only ghost/Dracula/Franky contact sites enter here
player_move:
    ld (player_start_x),de
    ld (player_start_y),hl
    ld hl,(GENERATION)
    inc hl
    ld (trace_generation),hl
    ; Save caller's world Y while selecting the trace loop.
    ld hl,(player_start_y)
    push af
    push hl
    ld hl,player_trace_loop
    ld ($3A74),hl
    ld hl,trace
    ld (trace_write),hl
    xor a
    ld (trace_count),a
    pop hl
    pop af
    ; HARD doubles ordinary movement, while the accelerator has the same
    ; eight-unit maximum as NORMAL. Other actors keep their common x2 wrapper.
    push af
    ld a,($105F)
    or a
    jr z,player_units_ready
    ld a,c
    add a,a
    cp 9
    jr c,player_units_store
    ld a,8
player_units_store:
    ld c,a
player_units_ready:
    pop af
    call $3A4B
    push af
    push hl
    ld hl,$06C2
    ld ($3A74),hl
    pop hl
    pop af
    ret
player_trace_loop:
    push af
    call record_step
    pop af
    jp $06C2
record_step:
    ld a,(trace_count)
    cp 16
    ret nc
    inc a
    ld (trace_count),a
    push bc
    push de
    push hl
    ld hl,(trace_write)
    pop bc
    pop de
    ld (hl),e
    inc hl
    ld (hl),d
    inc hl
    ld (hl),c
    inc hl
    ld (hl),b
    inc hl
    ld (trace_write),hl
    ld h,b
    ld l,c
    pop bc
    ret
; Original dispatch reads alternate DE/BC. Replay centres and cell crossings,
; then the endpoint, preserving the original endpoint bank for the caller.
player_effects:
    exx
    ld (player_end_x),de
    ld (player_end_y),bc
    ld (player_end_hl),hl
    exx
    ld hl,(player_start_x)
    ld a,l
    and $F0
    ld (last_cell_x),a
    ld a,h
    ld (last_cell_x+1),a
    ld hl,(player_start_y)
    ld a,l
    and $F0
    ld (last_cell_y),a
    ld a,h
    ld (last_cell_y+1),a
    ld hl,trace
    ld (scan_ptr),hl
    ld a,(trace_count)
    ld (scan_left),a
    xor a
    ld (endpoint_seen),a
cell_scan:
    ld a,(scan_left)
    or a
    jr z,cell_endpoint
    dec a
    ld (scan_left),a
    ld hl,(scan_ptr)
    ld e,(hl)
    inc hl
    ld d,(hl)
    inc hl
    ld c,(hl)
    inc hl
    ld b,(hl)
    inc hl
    ld (scan_ptr),hl
    ld a,e
    and 15
    cp 8
    jr nz,cell_crossing
    ld a,c
    and 15
    cp 8
    jr z,cell_process
cell_crossing:
    ld hl,(last_cell_x)
    ld a,e
    and $F0
    cp l
    jr nz,cell_process
    ld a,d
    cp h
    jr nz,cell_process
    ld hl,(last_cell_y)
    ld a,c
    and $F0
    cp l
    jr nz,cell_process
    ld a,b
    cp h
    jr z,cell_scan
cell_process:
    ld a,e
    and $F0
    ld (last_cell_x),a
    ld a,d
    ld (last_cell_x+1),a
    ld a,c
    and $F0
    ld (last_cell_y),a
    ld a,b
    ld (last_cell_y+1),a
    ld hl,(player_end_x)
    or a
    sbc hl,de
    jr nz,cell_dispatch
    ld hl,(player_end_y)
    or a
    sbc hl,bc
    jr nz,cell_dispatch
    ld a,1
    ld (endpoint_seen),a
cell_dispatch:
    push de
    push bc
    exx
    pop bc
    pop de
    exx
    call $3E08
    jr cell_scan
cell_endpoint:
    ld a,(endpoint_seen)
    or a
    jr nz,cell_restore
    exx
    ld de,(player_end_x)
    ld bc,(player_end_y)
    exx
    call $3E08
cell_restore:
    exx
    ld de,(player_end_x)
    ld bc,(player_end_y)
    ld hl,(player_end_hl)
    exx
    ret
actor_entry:
    call actor_origin
    and a
    ret z
    ld l,c                  ; displaced third byte of the checked entry patch
    jp $4DE8
object_entry:
    call actor_origin
    push af
    ld a,(actor_budget)
    add a,a
    ld (actor_budget),a
    pop af
    and a
    ret z
    ld l,c                  ; displaced third byte of the checked entry patch
    jp $4D6C
actor_origin:
    call $0686              ; safe point before an actor update, outside GPU packets
    push af
    ld (actor_budget),a
    ld a,($105F)
    or a
    jr z,actor_origin_mode
    ld a,(actor_budget)
    add a,a
    ld (actor_budget),a
actor_origin_mode:
    ld (actor_start_x),de
    ld (actor_start_y),bc
    ld (actor_id),ix
    pop af
    ret
original_overlap:
    ld hl,($3E93)
    jp $4F47
original_near:
    ld a,($3F93)
    jp $4EA2
swept_overlap:
    call $0686
    call original_overlap
    ret c
    ; Most ordinary moves cannot cross the whole damage box between endpoints.
    ; Reject by the conservative combined budget before resolving actor identity.
    ld a,(player_budget)
    ld hl,actor_budget
    add a,(hl)
    cp 9
    jp c,sweep_no
    push de
    push ix
    pop hl
    ld de,(actor_id)
    or a
    sbc hl,de
    pop de
    ld a,(player_budget)
    jr nz,overlap_budget
    ld hl,actor_budget
    add a,(hl)
overlap_budget:
    cp 9
    jp c,sweep_no

    ld a,($3FB9)
    cp 4
    jr nz,overlap_actor_flags
    ; The intentional contact that launches a stationary ball must not become
    ; a swept hit while that same ball moves away. Keep endpoint hits above,
    ; and normal swept damage for balls already rolling or other identities.
    push de
    push ix
    pop hl
    ld de,(pushed_ball_id)
    or a
    sbc hl,de
    pop de
    jp z,sweep_no
    jr overlap_active
overlap_actor_flags:
    ld a,(ix+5)
    or (ix+7)
    jp nz,sweep_no
overlap_active:
    ld a,3
    ld (sweep_y_bias+1),a
    ld (sweep_y_point_bias+1),a
    ld a,7
    ld (x_bias),a
    ld a,15                 ; original carry propagation: X offsets -7..+7
    ld (x_size),a
    ld a,11                 ; original Y offsets -3..+7
    ld (y_size),a
    xor a
    ld (near_mode),a
    jp sweep
swept_near:
    call $0686
    call original_near
    ret c
    ld a,(player_budget)
    cp 5
    jp c,sweep_no
    ld a,($3F93)
    neg
    cp 8
    jp nc,sweep_no
    ld a,3
    ld (sweep_y_bias+1),a
    ld (sweep_y_point_bias+1),a
    ld a,4
    ld (x_bias),a
    ld a,8
    ld (x_size),a
    ld (y_size),a
    ld a,1
    ld (near_mode),a
    jr sweep
; The fleeing accelerator is a pickup, not a damaging actor. Its visible
; intermediate positions need contact checks even at ordinary small budgets.
; Keep its original arming/jump/expiry rules and use a symmetric seven-unit
; pickup radius; do not change the asymmetric enemy/ball damage rectangle.
runner_overlap:
    call $0686
    call original_overlap
    ret c
    ld a,($509C)
    or a
    ret z
    ld a,7
    ld (sweep_y_bias+1),a
    ld (sweep_y_point_bias+1),a
    ld (x_bias),a
    ld a,15
    ld (x_size),a
    ld (y_size),a
    xor a
    ld (near_mode),a
    jp sweep
ball_near:
    call swept_near
    ret nc
    ld (pushed_ball_id),ix
    ret
sweep:
    push bc
    push de
    ld (object_x),de
    ld (object_y),bc
    ld hl,(object_x)
    ld de,($3E93)
    or a
    sbc hl,de
    call relative_byte
    jp c,sweep_restore_no
    ld (new_x),a
    ld hl,(object_y)
    ld de,($3E95)
    or a
    sbc hl,de
    call relative_byte
    jp c,sweep_restore_no
    ld (new_y),a
    ld de,(object_x)
    ld bc,(object_y)
    ld a,(near_mode)
    or a
    jr nz,sweep_origin_ready
    push ix
    pop hl
    ld de,(actor_id)
    or a
    sbc hl,de
    ld de,(object_x)
    jr nz,sweep_origin_ready
    ld de,(actor_start_x)
    ld bc,(actor_start_y)
sweep_origin_ready:
    ex de,hl
    ld de,(player_start_x)
    or a
    sbc hl,de
    call relative_byte
    jp c,sweep_restore_no
    ld (old_x),a
    ld h,b
    ld l,c
    ld de,(player_start_y)
    or a
    sbc hl,de
    call relative_byte
    jp c,sweep_restore_no
    ld (old_y),a
    call sweep_core
    jr c,sweep_restore
    xor a
sweep_restore:
    pop de
    pop bc
    ret
sweep_restore_no:
    pop de
    pop bc
sweep_no:
    xor a
    ret
; Sign-extended byte guard rejects distant actors and teleports, not hitboxes.
relative_byte:
    ld a,l
    rlca
    sbc a,a
    cp h
    ld a,l
    ret z
    scf
    ret
sweep_core:
    ld a,(old_x)
    ld b,a
    ld a,(new_x)
    ld c,a
    ld a,(x_bias)
    ld d,a
    ld a,(x_size)
    ld e,a
    call broad_axis
    ret nc
    ld a,(old_y)
    ld b,a
    ld a,(new_y)
    ld c,a
sweep_y_bias:
    ld d,3
    ld a,(y_size)
    ld e,a
    call broad_axis
    ret nc
    ld a,(old_x)
    ld c,a
    ld a,(new_x)
    call axis_delta
    jp c,sweep_core_no
    ld (dx),a
    ld a,b
    ld (step_x),a
    ld a,(old_y)
    ld c,a
    ld a,(new_y)
    call axis_delta
    jp c,sweep_core_no
    ld (dy),a
    ld a,b
    ld (step_y),a
    ld a,(dx)
    ld b,a
    ld a,(dy)
    cp b
    jr nc,sweep_n
    ld a,b
sweep_n:
    ld (span),a
    ld b,a
    inc b
    xor a
    ld (err_x),a
    ld (err_y),a
sweep_point:
    ld a,(x_bias)
    ld c,a
    ld a,(old_x)
    add a,c
    ld c,a
    ld a,(x_size)
    cp c
    jr z,sweep_next
    jr c,sweep_next
    ld a,(old_y)
sweep_y_point_bias:
    add a,3
    ld c,a
    ld a,(y_size)
    cp c
    jr z,sweep_next
    jr c,sweep_next
    ld a,(old_y)
    or a
    ld a,0
    jr z,sweep_hit
    jp m,sweep_hit
    inc a
sweep_hit:
    scf
    ret
sweep_next:
    djnz sweep_advance
    xor a
    ret
sweep_advance:
    ld a,(span)
    ld c,a
    ld a,(dx)
    ld hl,err_x
    add a,(hl)
    cp c
    jr c,sweep_x_error
    sub c
    ld (hl),a
    ld a,(step_x)
    ld hl,old_x
    add a,(hl)
    ld (hl),a
    jr sweep_y
sweep_x_error:
    ld (hl),a
sweep_y:
    ld a,(dy)
    ld hl,err_y
    add a,(hl)
    cp c
    jr c,sweep_y_error
    sub c
    ld (hl),a
    ld a,(step_y)
    ld hl,old_y
    add a,(hl)
    ld (hl),a
    jr sweep_point
sweep_y_error:
    ld (hl),a
    jr sweep_point
sweep_core_no:
    xor a
    ret
; B=old,C=new signed bytes; D=bias,E=width. Carry means possible slab crossing.
broad_axis:
    ld a,b
    xor $80
    ld b,a
    ld a,c
    xor $80
    ld c,a
    ld a,128
    sub d
    cp b
    jr c,broad_upper
    jr z,broad_upper
    cp c
    jr c,broad_upper
    jr z,broad_upper
    or a
    ret
broad_upper:
    add a,e
    cp b
    jr c,broad_new_upper
    jr z,broad_new_upper
    scf
    ret
broad_new_upper:
    cp c
    jr c,broad_reject
    jr z,broad_reject
    scf
    ret
broad_reject:
    or a
    ret
; A=new,C=old. Return abs delta,A and sign B. Carry rejects >64 unit jumps.
axis_delta:
    ld l,a
    rlca
    sbc a,a
    ld h,a
    ld a,c
    ld e,a
    rlca
    sbc a,a
    ld d,a
    or a
    sbc hl,de
    ld b,1
    bit 7,h
    jr z,axis_positive
    ld a,h
    cp $FF
    jr nz,axis_invalid
    ld a,l
    neg
    ld b,$FF
    jr axis_check
axis_positive:
    ld a,h
    or a
    jr nz,axis_invalid
    ld a,l
axis_check:
    cp 65
    ccf
    ret
axis_invalid:
    scf
    ret
game_irq:
    push af
    in a,($66)
    and 1
    jr nz,game_audio_irq
    in a,($99)
    pop af
    ei
    ret
game_audio_irq:
    out ($66),a
    push hl
    ld hl,$105E
    inc (hl)
    pop hl
    in a,($99)
    jp $5572
contact_frame:
    ld hl,0
    ld (actor_id),hl
    ld (pushed_ball_id),hl
    ld hl,(trace_generation)
    ld de,(GENERATION)
    or a
    sbc hl,de
    jr z,contact_budget
    ld hl,($3E93)
    ld (player_start_x),hl
    ld hl,($3E95)
    ld (player_start_y),hl
    xor a
    ld (trace_count),a
contact_budget:
    ld hl,(player_start_x)
    ld de,($3E93)
    or a
    sbc hl,de
    call small_abs
    ld b,a
    ld hl,(player_start_y)
    ld de,($3E95)
    or a
    sbc hl,de
    call small_abs
    cp b
    jr nc,contact_budget_store
    ld a,b
contact_budget_store:
    ld (player_budget),a
    ret
small_abs:
    ld a,l
    bit 7,h
    ret z
    neg
    ret
contact_reset:
    ld hl,$FFFF
    ld (trace_generation),hl
    ld hl,$06C2
    ld ($3A74),hl
    xor a
    ld (trace_count),a
    ld hl,0
    ld (pushed_ball_id),hl
    ret
restore_detail:
    call wait_command
    ld hl,224
    ld (command),hl
    ld (command+4),hl
    ld hl,1904
    ld (command+2),hl
    ld hl,1648
    ld (command+6),hl
    ld hl,16
    ld (command+8),hl
    ld (command+10),hl
    ld hl,$00FF             ; P1 detail sprite pattern: lower bank A only
    ld (command+14),hl
    ld a,32
    out ($64),a
    ld hl,command
    ld bc,$1563
    otir
    jp wait_command
retry_menu:
    call $E800
    call $E809
    call restore_detail
    jp clear_ui             ; already hidden by menu confirmation
; Replay the actual two-unit player positions before the original exact-contact
; roller handler. Four/eight-unit endpoints otherwise skip its zero/-4 tests.
; Preserve the caller's final player/reference coordinates and combine adjacency
; only at that endpoint; retain any push animation raised along the path.
push_roller:
    ld a,(trace_count)
    cp 3
    jp c,$4C0F
    ; Most rollers are far away. A trace travels at most eight units, and
    ; the furthest original contact offset is six: reject beyond fourteen.
    ld hl,($3E93)
    ld e,(ix+0)
    ld d,(ix+1)
    or a
    sbc hl,de
    ld de,14
    add hl,de
    ld a,h
    or a
    jp nz,$4C0F
    ld a,l
    cp 29
    jp nc,$4C0F
    ld hl,(trace_generation)
    ld de,(GENERATION)
    or a
    sbc hl,de
    jp nz,$4C0F
    ld hl,($3E93)
    push hl
    ld hl,($3E95)
    push hl
    ld hl,($4C9F)
    push hl
    ld hl,($4CA1)
    push hl
    ld a,($3FA8)
    push af
    ld hl,trace+4
    ld (scan_ptr),hl
    ld a,(trace_count)
    srl a
    ld (scan_left),a
roller_step:
    pop af
    push af
    ld ($3FA8),a
    ld hl,(scan_ptr)
    ld de,$3E93
    ld bc,4
    ldir
    ld de,4
    add hl,de
    ld (scan_ptr),hl
    ld hl,($3E93)
    ld bc,-4
    add hl,bc
    ld ($4C9F),hl
    ld hl,($3E95)
    add hl,bc
    ld ($4CA1),hl
    call $4C0F
    ld hl,scan_left
    dec (hl)
    jr nz,roller_step
    pop af
    ld ($3FA8),a
    pop hl
    ld ($4CA1),hl
    pop hl
    ld ($4C9F),hl
    pop hl
    ld ($3E95),hl
    pop hl
    ld ($3E93),hl
    jp $4C0F
; 412B receives the actual crossed-cell world coordinates, not the player's
; previous/final position. Retain this origin for the whole effect.
hazard_start:
    ld a,($3FAC)
    or a
    jr nz,hazard_started
    ld (hazard_x),de
    ld (hazard_y),bc
hazard_started:
    ld a,($3F93)             ; displaced original instruction
    jp $412E
hazard_coords:
    ld de,(hazard_x)
    ld bc,(hazard_y)
    xor a                    ; original projection uses floor height zero
    ret
 ; Plane B always wraps at512 lines. Each hidden512x512 name image lives
; at50000/52000, outside the display table at7E000. Publish the padded9x12
; metatile window as at most four wrapped LMMM rectangles, never a half-page.
publish_names:
    call publish_name_window
publish_names_done:
    ret
publish_name_window:
    ld hl,$FF00             ; P1 name-table copies must not alter lower bank A
    ld (name_command+14),hl
    ld a,$40
    ld (name_command+20),a
    ; Cover exactly the two visible camera positions, rounded to8x8 names.
    ; The prepared metatile margin is wider; copying it wastes blank time.
    ld hl,(scroll_x)
    ld de,32
    add hl,de
    ld a,(SCROLL_HALF_X)
    bit 7,a
    jr nz,name_x_min_ready
    ld e,a
    ld d,0
    or a
    sbc hl,de
name_x_min_ready:
    ld a,l
    and 7
    ld c,a
    ld a,(SCROLL_HALF_X)
    or a
    jp p,name_x_span
    neg
name_x_span:
    add a,c
    add a,199                ; ceil((192+abs(halfX)+fineX)/8)*4 GPU pixels
    and $F8
    rrca
    ld (name_total_width),a
    srl h
    rr l
    ld a,l
    and $FC
    ld (name_x),a
    neg
    jr z,name_full_width
    ld b,a
    ld a,(name_total_width)
    cp b
    jr c,name_width_ready
    ld a,b
    jr name_width_ready
name_full_width:
    ld a,(name_total_width)
name_width_ready:
    ld (name_w1),a
    ld b,a
    ld a,(name_total_width)
    sub b
    ld (name_w2),a
    ld hl,(scroll_y)
    ld de,16
    add hl,de
    ld a,(SCROLL_HALF_Y)
    bit 7,a
    jr nz,name_y_min_ready
    ld e,a
    ld d,0
    or a
    sbc hl,de
name_y_min_ready:
    ld a,l
    and 7
    ld c,a
    ld a,(SCROLL_HALF_Y)
    or a
    jp p,name_y_span
    neg
name_y_span:
    add a,c
    add a,151                ; ceil((144+abs(halfY)+fineY)/8) name rows
    rrca
    rrca
    rrca
    and 31
    ld (name_total_height),a
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    ld a,l
    and 63
    ld (name_y),a
    ld b,a
    ld a,64
    sub b
    ld b,a
    ld a,(name_total_height)
    cp b
    jr c,name_height_ready
    ld a,b
name_height_ready:
    ld (name_height),a
    ld b,a
    ld a,(name_total_height)
    sub b
    ld (name_h2),a
    ld a,(sprite_page)
    rrca
    rrca
    ld l,a
    ld h,2
    ld (name_source),hl
    call name_rectangles
    ld a,(name_h2)
    or a
    ret z
    ld (name_height),a
    xor a
    ld (name_y),a
name_rectangles:
    ld a,(name_x)
    ld (name_current_x),a
    ld a,(name_w1)
    ld (name_width),a
    call name_rectangle
    ld a,(name_w2)
    or a
    ret z
    ld (name_width),a
    xor a
    ld (name_current_x),a
name_rectangle:
    call wait_command
    ld a,(name_current_x)
    ld l,a
    ld h,2                  ; P1 command X bit9 selects plane B
    ld (name_command),hl
    ld (name_command+4),hl
    ld hl,(name_source)
    ld a,(name_y)
    add a,l
    ld l,a
    ld (name_command+2),hl
    ld a,(name_y)
    ld l,a
    ld h,0
    ld de,1984              ; active name table at7E000
    add hl,de
    ld (name_command+6),hl
    ld a,(name_width)
    ld l,a
    ld h,0
    ld (name_command+8),hl
    ld a,(name_height)
    ld l,a
    ld h,0
    ld (name_command+10),hl
issue_name_copy:
    ld a,32
    out ($64),a
    ld hl,name_command
    ld bc,$1563
    otir
    jp wait_command
; Fixed resident ABI: build the midpoint directly into its hidden VRAM SAT.
stage_sat:
    jp STAGE_MID_SAT
publish_sat:
    call publish_sat_window
publish_sat_done:
    ret
publish_sat_window:
    call wait_command
    ld a,(GPU_FRONT_COUNT)
    ld e,a
    ld a,(GPU_HARDWARE_COUNT)
    cp e
    jr nc,sat_copy_count_ready
    ld a,e
sat_copy_count_ready:
    ld c,a
    ld a,e
    ld (GPU_HARDWARE_COUNT),a
    ld a,c
    or a
    ret z
    ; BMLL uses interleaved Bx addresses. Copy only the lower bank (SAT):
    ; mask00FF preserves the paired upper-bank background-name bytes.
    ld l,c
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,h
    ld (name_command+10),a
    xor a
    ld (name_command+11),a
    ld (name_command+9),a
    ld a,l
    ld (name_command+8),a
    ld hl,0
    ld (name_command),hl
    ld (name_command+4),hl
    ld hl,$07F4             ; full staging3FA00 -> interleaved7F400
    ld a,(SCROLL_PHASE)
    or a
    jr z,sat_copy_source
    ld l,$F0               ; midpoint3F800 -> interleaved7F000
sat_copy_source:
    ld (name_command+2),hl
    ld hl,$07FC             ; physical SAT3FE00 -> interleaved7FC00
    ld (name_command+6),hl
    ld hl,$00FF
    ld (name_command+14),hl
    ld a,$A0
    ld (name_command+20),a
    jp issue_name_copy

name_x: db 0
name_y: db 0
name_w1: db 0
name_w2: db 0
name_height: db 0
name_h2: db 0
name_current_x: db 0
name_width: db 0
name_total_width: db 0
name_total_height: db 0
name_source: dw 0
name_command: dw 512,512,512,1984,144,24
    db 0,$0C,0,$FF,0,0,0,0,$40
hazard_x: dw 0
hazard_y: dw 0
player_start_x: dw 0
player_start_y: dw 0
player_end_x: dw 0
player_end_y: dw 0
player_end_hl: dw 0
trace_generation: dw $FFFF
trace_write: dw trace
trace_count: db 0
scan_ptr: dw trace
scan_left: db 0
endpoint_seen: db 0
last_cell_x: dw 0
last_cell_y: dw 0
player_budget: db 0
actor_budget: db 0
actor_id: dw 0
pushed_ball_id: dw 0
actor_start_x: dw 0
actor_start_y: dw 0
object_x: dw 0
object_y: dw 0
near_mode: db 0
old_x: db 0
old_y: db 0
new_x: db 0
new_y: db 0
x_bias: db 7
x_size: db 15
y_size: db 11
dx: db 0
dy: db 0
step_x: db 0
step_y: db 0
span: db 0
err_x: db 0
err_y: db 0
trace: ds 64,0
    assert $<=$E800
    ds $E800-$,0
