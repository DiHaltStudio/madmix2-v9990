; Native P1 integration, Z80 only. Original gameplay remains at 37E3..B72B.
; Reclaims original software sprite bytes 1100..3764; no old blitter may run.
; Scratch B800..BE7C, C000..CAFF, CB40..DCB8 and CE00..CFFF.
; Original CB00 remap and DCB9 depth queue remain intact.
; IRQ owns PSG and flag acknowledgement; main thread owns V9990 drawing transactions.
    include "../build/port-music.inc"
    include "../build/port-art-config.inc"
    include "../build/smooth-config.inc"
    org $1100
    jp initialize
    jp background
    jp draw_pose
    jp present
    jp clear_ui
    jp text_records
    jp start_patterns
    jp hud_colors
    jp lives
    jp load_map
    jp music_start
    jp music_stop
    jp audio_tick
    jp music_mix
    jp detail_points
    jp read_controls
    jp startup_gate
    jp stage_ready
    jp draw_player

; Initialize renderer state after final tape-compatible game load. No return.
initialize:
    di
    ld sp,$0FFF
    call $E821            ; bounded helper reads keep persistent audio ticking
    call $CE06              ; original A303 is data, not an initialized SFX cursor
    ld a,$FF
    ld ($A7DD),a            ; no stale effect request at the first native IRQ
    ei
    call $0680
    xor a
    ld (scene),a
    ld (piece_count),a
    ld (audio_clock),a
    ld ($F3DB),a
    ld (startup_done),a
    call clear_ui            ; foreground stays black until first frame publication
    call clear_background    ; retire title/Topo names in both background pages
    call $E01B              ; UI canvas shared page0: restore the detail pixel
    ld b,13
    ld a,ART_PLANE_PALETTES
    call reg_write
    ld b,27
    xor a                    ; A foreground / B background
    call reg_write
    ld b,25
    ld a,12                  ; visible sprites at VRAM 30000
    call reg_write
    xor a
    out ($6F),a
    di
    jp $37E3

 ; Called instead of the original tail JP at 43C4, after STAGE n is drawn.
stage_ready:
    call $06AD               ; reveal STAGE and wait for its accepted press
    jp display_off           ; blank NOW, before map/frame preparation

 ; The V9990 difficulty menu already accepted fire at cold boot. Reopen the
; native selector after GAME OVER; never draw the retired original start text.
startup_gate:
    ld a,(startup_done)
    or a
    jr nz,retry_gate
    inc a
    ld (startup_done),a
    jr select_start_family
retry_gate:
    call $E01E
select_start_family:
    ; New game/checkpoint and descriptor family must agree after GAME OVER.
    ; The edited map loader uses an absolute stage ID, so a retained family
    ; from the previous game would mix its actors/start with the new map.
    ld a,($3E89)
    cp 3
    ld a,0
    jr c,start_family_ready
    ld a,($3E89)
    cp 6
    ld a,1
    jr c,start_family_ready
    inc a
start_family_ready:
    ; Only the three resource pointers change. Keep the original timing and
    ; restart-counter bytes67C8..67CA selected by the original start routine.
    ld hl,$66F6
    or a
    jr z,start_family_copy
    cp 1
    ld hl,$66FF
    jr z,start_family_copy
    ld hl,$6708
start_family_copy:
    ld de,$67C2
    ld bc,6
    ldir
    jp $3819
startup_done: db 0

; Player draw components are camera-anchored; world actors move with the floor.
draw_player:
    ld a,1
    ld ($C280),a
    call $3B59
    xor a
    ld ($C280),a
    ret

; Main-thread register write. IRQ only acknowledges flags through port66. AF/B clobbered.
    include "port_display.inc"
reg_write:
    push af
    ld a,b
    or $80
    out ($64),a
    pop af
    out ($63),a
    ret
; A:DE=19-bit VRAM write address. HL/BC preserved.
set_write:
    push af
    xor a
    out ($64),a
    ld a,e
    out ($63),a
    ld a,d
    out ($63),a
    pop af
    out ($63),a
    ret
; A:DE=19-bit VRAM read address. HL/BC preserved.
set_read:
    push af
    ld a,3
    out ($64),a
    ld a,e
    out ($63),a
    ld a,d
    out ($63),a
    pop af
    out ($63),a
    ret
wait_command:
    in a,($65)
    and 1
    jr nz,wait_command
    ret
vblank:
    in a,($65)
    and $40
    jr nz,vblank
vb_start:
    in a,($65)
    and $40
    jr z,vb_start
    ret

; Replace map decompression with the edited TMX bank, same original RAM layout.
; Called once per stage. Destroys AF/BC/DE/HL, as original does.
load_map:
    ld a,($3E8A)
    add a,a
    add a,a
    add a,a
    add a,a
    ld d,a
    ld e,0
    ld a,2
    call set_read
    ld hl,$A900
    ld de,3584
map_read:
    in a,($60)
    ld (hl),a
    inc hl
    dec de
    ld a,d
    or e
    jr nz,map_read
    ret

; Clear the foreground to opaque black; all sprites remain masked. Names are
; 64 columns, 64 rows, two bytes/name. No palette writes during gameplay.
clear_ui:
    call display_off
    call $0683              ; discard interpolation across status/death/stage screens
    ld a,$C8
    out ($64),a
    in a,($63)
    and $BF                 ; configure native sprite enable while hidden
    out ($63),a
    xor a
    ld (scene),a
    ld (overlay_dirty),a
    call hide_sprites
    ld a,7
    ld de,$C000
    call set_write
    ld de,4096
clear_name:
    ld a,1
    out ($60),a
    xor a
    out ($60),a
    dec de
    ld a,d
    or e
    jr nz,clear_name
    ret
 ; Reserved pattern1023 at47FE0 stays zero while name staging uses50000/52000.
; Clear BOTH 4 KiB B name pages before game display; do not erase art patterns.
clear_background:
    ld a,7
    ld de,$E000
    call set_write
    ld de,4096
clear_background_name:
    ld a,$FF
    out ($60),a
    ld a,3
    out ($60),a
    dec de
    ld a,d
    or e
    jr nz,clear_background_name
    ret

start_patterns:
    ei
    jp clear_ui
hud_colors:
    ret

; Make the 192x144 viewport transparent in A; retain opaque marker and margins.
; Called only on transition from menu/status screen to gameplay.
open_viewport:
    call display_off        ; keep hidden until complete READY reaches fire gate
    ld hl,hud_names
    ld de,$C000
    ld a,24
    ld (hud_rows),a
hud_row:
    ld a,7
    call set_write
    ld bc,$4060
    otir
    ex de,hl
    ld bc,128
    add hl,bc
    ex de,hl
    ld a,(hud_rows)
    dec a
    ld (hud_rows),a
    jr nz,hud_row
    ld a,1
    ld (scene),a
    xor a
    ld (overlay_dirty),a
    ret

; Original camera calculation is a game-side effect and MUST remain.
; Retain a circular 16x16-metatile cache in each 512x256 plane-B page.
; Compare the padded 9x12 window and upload only newly exposed/modified IDs.
; CB00 aliases remain original animation authority, map RAM remains collisions.
background:
    call $0686              ; service the currently visible frame
    call $4261
    call $0689              ; collect logical camera delta
    ld hl,-32
    add hl,de
    ex de,hl
    ld hl,-16
    add hl,bc
    ld b,h
    ld c,l
    ; Physical names form a 512x256 torus on each hidden plane-B page.
    ; Full world coordinates remain authoritative for the collision map.
    ld a,e
    ld (scroll_x),a
    ld a,d
    and 1
    ld (scroll_x+1),a
    ld (scroll_y),bc
    call $6005
    ld (map_row),hl
    xor a
    ld (piece_count),a
    ld a,(sprite_page)
    xor 1
    ld (sprite_page),a
    ld hl,$BE00
    ld de,$BE01
    ld bc,124
    ld (hl),0
    ldir
    ld a,(overlay_dirty)
    or a
    call nz,erase_overlay
    xor a
    ld (cache_family),a
    ld hl,0
    ld a,($67C7)
    cp $80
    jr nz,family_ready
    ld hl,448
    ld a,56
    ld (cache_family),a
family_ready:
    ld a,(sprite_page)
    or a
    jr z,family_bank_ready
    ld de,1024
    add hl,de
family_bank_ready:
    ld (family_base),hl
    call $06BC              ; animate only the hidden terrain-pattern bank
    ld a,(scroll_y)
    and $F0
    ld l,a
    rrca
    rrca
    rrca
    rrca
    ld d,a
    ld a,(scroll_y+1)
    and 1
    rlca
    rlca
    rlca
    rlca
    or d
    ld d,a
    ld a,(scroll_x+1)
    and 1
    ld b,a
    ld a,(scroll_x)
    rlca
    rlca
    rlca
    and 7
    ld e,a
    ld a,b
    add a,a
    add a,a
    add a,a
    or e
    or l
    ld l,a                  ; cache index: row*16+column
    and 15
    add a,a
    add a,a
    add a,a
    ld e,a                  ; name-table byte column
    ld a,(sprite_page)
    or a
    jr z,ring_page_ready
    set 5,d
ring_page_ready:
    ld (name_row),de
    ld a,(scroll_y+1)
    and 1
    ld b,a
    ld a,(sprite_page)
    add a,a
    add a,$C4
    or b
    ld h,a
    push hl
    pop iy                  ; C400/C600: 512 effective tile IDs per512-line page
    ld a,12
    ld (rows_left),a
bg_row:
    call $0686
    ld hl,(map_row)
    ld de,(name_row)
    ld a,(cache_family)
    ld c,a
    ld b,9
bg_cell:
    ; One bounded nine-cell row fits between cooperative checkpoints. Polling
    ; for every cached cell consumed several milliseconds of the frame budget.
    ld a,(hl)
    cp 56
    jr c,tile_valid
    xor a
tile_valid:
    add a,c
    cp (iy+0)
    jr z,bg_cell_done
    ld (iy+0),a
    push bc
    push hl
    push de
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld a,(sprite_page)
    add a,a
    add a,a
    or h
    ld h,a
    ld a,5
    call set_write
    call tile_names
    ld a,e
    xor 128
    ld e,a
    ld a,5
    call set_write
    call tile_names
    pop de
    pop hl
    pop bc
bg_cell_done:
    inc iyl
    ld a,iyl
    and 15
    jr nz,bg_cache_next
    ld a,iyl
    sub 16
    ld iyl,a
bg_cache_next:
    ld a,l
    inc a
    xor l
    and 63
    xor l
    ld l,a
    ld a,e
    add a,8
    and 127
    ld e,a
    djnz bg_cell
    ld hl,(name_row)
    ld a,h
    inc a
    xor h
    and 31
    xor h
    ld h,a
    ld (name_row),hl
    push iy
    pop hl
    ld a,l
    sub 9
    and 15
    ld b,a
    ld a,l
    and $F0
    ld l,a
    ld de,16
    add hl,de
    ld a,h
    and 1
    ld c,a
    ld a,(sprite_page)
    add a,a
    add a,$C4
    or c
    ld h,a
    ld a,l
    or b
    ld l,a
    push hl
    pop iy
    ld hl,(map_row)
    ld de,64
    add hl,de
    ld (map_row),hl
    ld hl,rows_left
    dec (hl)
    jp nz,bg_row
    ret
; Four contiguous 8x8 names, unrolled to shorten changed-cell writes.
tile_names:
    ld a,l
    out ($60),a
    ld a,h
    out ($60),a
    inc hl
    ld a,l
    out ($60),a
    ld a,h
    out ($60),a
    inc hl
    ld a,l
    out ($60),a
    ld a,h
    out ($60),a
    inc hl
    ld a,l
    out ($60),a
    ld a,h
    out ($60),a
    inc hl

    ret
cache_family: db 0
name_cell: dw 0

; A=original pose (bit 7 mirror), D=Y modulo 256, E=X. All main regs scratch.
; Append pieces in original painter order; publication reverses SAT priority.
; Pieces are copied from the permanent atlas to active slots with full LMMM
; packets. HUD plane masks partial intersections; don't discard edge pixels.
draw_pose:
    call $0686
    cp $FF
    ret z
    ld (pose_id),a
    ld a,d
    cp 144                  ; original64EF marks consumed queue entries with Y=144
    ret z                   ; reject before anchoring/interpolation can reveal them
    ld a,(pose_id)
    call $0695              ; anchor player and its attached effect components
    ld a,d
    cp 160                  ; retain one extra band for interpolated edge reveal
    jr c,pose_visible
    cp 208
    ret c
pose_visible:
    ld a,e
    and $FC
    ld (pose_x),a
    ld a,d
    add a,16
    ld (pose_y),a
    ld a,(pose_id)
    ld l,a
    ld h,0
    bit 7,a
    jr z,pose_index
    res 7,l
    ld bc,105
    bit 2,e
    jr nz,mirror_index
    ld bc,210
mirror_index:
    add hl,bc
pose_index:
    add hl,hl
    ld bc,pose_offsets
    add hl,bc
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld hl,pose_data
    add hl,de
    ld a,(hl)
    inc hl
    ld (pose_left),a
    or a
    ret z
piece_loop:
    call $0686
    ld a,(piece_count)
    cp 125
    ret nc
    push hl
    pop hl
    ld a,(pose_x)
    add a,(hl)
    ld (piece_x),a
    inc hl
    ld a,(pose_y)
    add a,(hl)
    dec a
    ld (piece_y),a
    inc hl
    ld de,command
    ld bc,4
    ldir
    ld a,(hl)              ; precompiled per-pose palette, no pixel conversion
    ld (piece_attr),a
    inc hl
    push hl
    call $06B9             ; retain atlas patterns by identity, not painter slot
    jr nc,piece_staged
    call wait_command
    ; Destination slot is a 16x16 grid at physical 30000 (Y=1536).
    ld a,(pattern_slot)
    and 15
    add a,a
    add a,a
    add a,a
    add a,a
    ld (command+4),a
    xor a
    ld (command+5),a
    ld a,(pattern_slot)
    and $F0
    ld (command+6),a
    ld a,(sprite_page)
    add a,6                 ; Y=1536 or 1792: physical 30000 or 38000
    ld (command+7),a
    ld hl,$00FF             ; P1: sprite cache belongs only to lower bank A
    ld (command+14),hl
    ld a,32
    out ($64),a
    ld hl,command
    ld bc,$1563
    otir
piece_staged:
    ; SAT staging keeps the same slot number until reversed for publication.
    ld a,(piece_count)
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    ld de,sat
    add hl,de
    ld a,(piece_y)
    ld (hl),a
    inc hl
    ld a,(pattern_slot)
    ld (hl),a
    inc hl
    ld a,(piece_x)
    ld (hl),a
    inc hl
    ld a,(piece_attr)        ; bank from editable pose metadata, priority bit5
    ld (hl),a
    call $068F              ; tag this piece as world or camera-anchored
    ld hl,piece_count
    inc (hl)
    pop hl
    ld a,(pose_left)
    dec a
    ld (pose_left),a
    jp nz,piece_loop
    ret

; Publish attributes and scroll after copies complete. Full 125-entry SAT is
; emitted so death/pose changes cannot leave stale hardware sprites visible.
present:
    call wait_command
    ei
    call $0698              ; complete previous visual steps before reusing front RAM
    call $068C              ; prepare both SAT phases before their deadlines
    call $06B6              ; returns on the exact full-frame VBlank deadline
    call stage_palette
    call $0692              ; publish current logical frame and start its visual steps
present_done:
    ; Reveal the viewport only AFTER completed background page, scroll and SAT
    ; have been published. background() runs earlier against the hidden page.
    ld a,(scene)
    or a
    jp z,open_viewport
    ret
hide_sprites:
    ld a,3
    ld de,$FE00
    call set_write
    ld b,125
hide_sprite_loop:
    xor a
    out ($60),a
    out ($60),a
    out ($60),a
    ld a,$10
    out ($60),a
    djnz hide_sprite_loop
    jp $06C5

; IX=[xcell,ycell,attribute,string...] records. Last char bit7, FF terminator.
; Draw foreground glyph names, including score/status; opaque glyph background
; masks hardware sprites. Retains original record format and IX advancement.
text_records:
    ld a,1
    ld (overlay_dirty),a
    ld a,(ix+0)
    cp $FF
    ret z
    ld e,a
    ld d,0
    sla e
    ld l,(ix+1)
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,de
    ld de,$C000
    add hl,de
    ex de,hl
    ld a,7
    call set_write
    ld a,(ix+2)
    and $38
    srl a
    srl a
    bit 0,(ix+2)
    jr z,text_style
    ld a,16
text_style:
    ld l,a
    ld h,0
    ld bc,font_styles
    add hl,bc
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld (text_base),de
    inc ix
    inc ix
    inc ix
text_char:
    ld a,(ix+0)
    inc ix
    ld c,a
    and $7F
    sub 32
    ld l,a
    ld h,0
    ld de,(text_base)
    add hl,de
    ld a,l
    out ($60),a
    ld a,h
    out ($60),a
    bit 7,c
    jr z,text_char
    jr text_records

; Draw original editable life icons: 3x3 cells, four slots, fixed foreground.
lives:
    ld ix,$67A4
    call text_records
    ld de,$CA9A              ; row21 column13
    ld a,3
    ld (hud_rows),a
clear_life_row:
    ld a,7
    call set_write
    ld b,15
clear_life_cell:
    ld a,1
    out ($60),a
    xor a
    out ($60),a
    djnz clear_life_cell
    ex de,hl
    ld bc,128
    add hl,bc
    ex de,hl
    ld a,(hud_rows)
    dec a
    ld (hud_rows),a
    jr nz,clear_life_row
    ld a,($3E78)
    cp 5
    jr c,life_count_ok
    ld a,4
life_count_ok:
    or a
    ret z
    ld (life_count),a
    ld de,$CA9A
life_icon:
    push de
    ld hl,life_names
    ld a,3
    ld (hud_rows),a
life_row:
    ld a,7
    call set_write
    ld bc,$0660
    otir
    ex de,hl
    ld bc,128
    add hl,bc
    ex de,hl
    ld a,(hud_rows)
    dec a
    ld (hud_rows),a
    jr nz,life_row
    pop hl
    ld de,8
    add hl,de
    ex de,hl
    ld a,(life_count)
    dec a
    ld (life_count),a
    jr nz,life_icon
    ret

; Original stage color translated into palette-0 opaque background/foreground.
; Caller has JUST entered VBlank. Six bytes fit before SAT/scroll publication.
stage_palette:
    if ART_STAGE_ORIGINAL = 0
    ret
    endif
    ld a,($3E8F)
    ld b,a
    ld a,(last_color)
    cp b
    ret z
    ld a,b
    ld (last_color),a
    call $62C2
    ld c,a
    and 15
    call color_address
    ld b,14
    ld a,ART_STAGE_PALETTE  ; terrain palette entry1, R component
    call reg_write
    ld a,(hl)
    out ($61),a
    inc hl
    ld a,(hl)
    out ($61),a
    inc hl
    ld a,(hl)
    out ($61),a
    ld a,c
    rrca
    rrca
    rrca
    rrca
    and 15
    call color_address
    ld a,(hl)
    out ($61),a
    inc hl
    ld a,(hl)
    out ($61),a
    inc hl
    ld a,(hl)
    out ($61),a
    ret
color_address:
    ld l,a
    add a,a
    add a,l
    ld l,a
    ld h,0
    ld de,tms_palette
    add hl,de
    ret
; Original software compositor overwrites READY/OK text on the next frame.
; Foreground is independent in P1, so explicitly reopen its transparent window.
erase_overlay:
    ld de,$C108
    ld h,18
erase_window_row:
    ld a,7
    call set_write
    xor a
    ld b,48
erase_window_byte:
    out ($60),a
    djnz erase_window_byte
    ex de,hl
    ld bc,128
    add hl,bc
    ex de,hl
    dec h
    jr nz,erase_window_row
    xor a
    ld (overlay_dirty),a
    ret
overlay_dirty: db 0
hud_rows: db 0
life_count: db 0
last_color: db $FF
text_base: dw 2
font_styles: dw 2,98,194,290,386,482,578,674,770
tms_palette: incbin "../build/port-tms-palette.bin"

    include "port_detail.inc"
    include "port_audio.inc"

sprite_page: db 0
scene: db 0
piece_count: db 0
piece_attr: db 0
pose_id: db 0
pose_x: db 0
pose_y: db 0
pose_left: db 0
piece_x: db 0
piece_y: db 0
pattern_slot: db 0
scroll_x: dw 0
scroll_y: dw 0
map_row: dw 0
map_cell: dw 0
name_row: dw 0
family_base: dw 0
subrow: db 0
rows_left: db 0
cols_left: db 0
command: dw 0,0,0,0,16,16
    db 0,$0C,$FF,0,0,0,0,0,$40
    include "../src/port_controls.inc"
pose_offsets: incbin "../build/port-pose-offsets.bin"
pose_data: incbin "../build/port-pose-data.bin"
hud_names: incbin "../build/port-hud-names.bin"
life_names: incbin "../build/port-life-names.bin"
    assert $<$3765
sat equ $C000
