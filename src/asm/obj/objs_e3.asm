; =====================================================================
;  objs_e3.asm - M6.4 GHZ3: kapsula zwierzat $25 (stale G3B_* itd. w objs_e1.asm)
; =====================================================================
; ---------------------------------------------------------------------
; objfunc_25_animal_capsule (01:732C): bez kolizji z mapa (set 5), rozmiar $1C x $40. Pierwszy tick (b0): y += $10.
; Lata kafli (BG, jak kwiaty): dane CAP_PATCH (nienaruszona) albo CAP_PATCHB (b1) + $0C w nieparzystych tickach:
; g_screen_tile_replace_x/y = pozycja obiektu + przesuniecia z danych, wskaznik danych kafli. Mapa sprite'ow
; (miganie wg bitu 4 licznika), granice okna: x0 = kamera X, x1 = x - $70. Sonic na kapsule ((tmp_06 = $0002) i
; Vy >= 0): z boku odsuniety o (x + $FFEA albo x + $1D), Vx = 0; z gory (Sonic nad jej gora): ustawiony na profilu
; CAP_PROFILE[(sonic_x + $0C) & $1F], odbicie Vy; profil = 3 (srodek - przycisk): mapa normalna, set 1 iy_06
; (Sonic stoi), potem co $14 tickow wybuch (8 razy, (ix+18)), a potem 12 zwierzat co 16 tickow (po pierwszym:
; g_signpost_tickdown_counter = $A0, muzyka $09, b1 (ix+24) - kapsula pusta, res 5 iy_00).
; ---------------------------------------------------------------------
objfunc_25_capsule
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$20                  ; set 5,(ix+24)
	sta (zg_obj),y
	and #$01                  ; bit 0,(ix+24)
	bne cp_ready
	ldy #OB_Y+1               ; y += $0010
	clc
	lda (zg_obj),y
	adc #$10
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
cp_ready                        ; @already_initialised
	ldy #OB_W
	lda #$1C
	sta (zg_obj),y
	iny
	lda #$40
	sta (zg_obj),y
	lda #<CAP_PATCH
	sta zg_ptr
	lda #>CAP_PATCH
	sta zg_ptr+1
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02                  ; bit 1,(ix+24): kapsula uszkodzona
	beq cp_intact
	lda #<CAP_PATCHB
	sta zg_ptr
	lda #>CAP_PATCHB
	sta zg_ptr+1
cp_intact
	lda g_global_tick_counter
	lsr                       ; rrca: C = b0
	bcc cp_even
	clc
	lda zg_ptr
	adc #$0C
	sta zg_ptr
	bcc cp_even
	inc zg_ptr+1
cp_even                         ; @tick_mod_2_was_not_0
	ldy #0                    ; BC = slowo (przesuniecie x), HL += 2
	lda (zg_ptr),y
	sta zs_c
	iny
	lda (zg_ptr),y
	sta zs_b
	jsr cp_ptr2
	ldy #OB_X+1               ; g_screen_tile_replace_x = x + BC
	clc
	lda (zg_obj),y
	adc zs_c
	sta g_screen_tile_replace_x
	iny
	lda (zg_obj),y
	adc zs_b
	sta g_screen_tile_replace_x+1
	ldy #0                    ; BC = slowo (przesuniecie y), HL += 2; g_screen_tile_replace_data_ptr = HL
	lda (zg_ptr),y
	sta zs_c
	iny
	lda (zg_ptr),y
	sta zs_b
	jsr cp_ptr2
	lda zg_ptr
	sta g_screen_tile_replace_data_ptr
	lda zg_ptr+1
	sta g_screen_tile_replace_data_ptr+1
	ldy #OB_Y+1               ; g_screen_tile_replace_y = y + BC
	clc
	lda (zg_obj),y
	adc zs_c
	sta g_screen_tile_replace_y
	iny
	lda (zg_obj),y
	adc zs_b
	sta g_screen_tile_replace_y+1
	lda #<SPR_CAPBLINK
	sta zs_hl
	lda #>SPR_CAPBLINK
	sta zs_hl+1
	lda g_global_tick_counter
	and #$10
	beq cp_blink
	lda #<SPR_CAPPRESS
	sta zs_hl
	lda #>SPR_CAPPRESS
	sta zs_hl+1
cp_blink                        ; @tick_mod_32_was_below_16
	ldy #OB_SPRITE
	lda zs_hl
	sta (zg_obj),y
	iny
	lda zs_hl+1
	sta (zg_obj),y
	lda g_level_scroll_x_pix_lo ; g_level_limit_x0 = kamera X
	sta g_level_limit_x0
	lda g_level_scroll_x_pix_lo+1
	sta g_level_limit_x0+1
	ldy #OB_X+1               ; g_level_limit_x1 = x + $FF90
	clc
	lda (zg_obj),y
	adc #$90
	sta g_level_limit_x1
	iny
	lda (zg_obj),y
	adc #$FF
	sta g_level_limit_x1+1
	lda #$02                  ; tmp_06 = $0002
	sta tmp_06
	lda #0
	sta tmp_06+1
	jsr check_collision_with_sonic
	jcs cp_notpos             ; jp c,@sonic_was_not_positioned_correctly
	lda sonic_vel_y_hi
	jmi cp_notpos             ; and a / jp m
	ldy #OB_Y+1               ; DE = y kapsuly; HL = sonic_y - y; jr c,@sonic_y_is_below
	lda (zg_obj),y
	sta zs_de
	iny
	lda (zg_obj),y
	sta zs_de+1
	lda sonic_y
	sec
	sbc zs_de
	lda sonic_y+1
	sbc zs_de+1
	bcc cp_above              ; Sonic nad gora kapsuly
	ldy #OB_X+1               ; z boku: HL = x + $10, de = $FFEA; HL - sonic_x; jr nc -> de zostaje
	clc
	lda (zg_obj),y
	adc #$10
	sta zs_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zs_hl+1
	lda #$EA
	sta zs_de
	lda #$FF
	sta zs_de+1
	lda zs_hl
	sec
	sbc sonic_x
	lda zs_hl+1
	sbc sonic_x+1
	bcs cp_xright             ; jr nc,@sonic_x_was_to_the_right
	lda #$1D
	sta zs_de
	lda #0
	sta zs_de+1
cp_xright
	ldy #OB_X+1               ; sonic_x = x + de
	clc
	lda (zg_obj),y
	adc zs_de
	sta sonic_x
	iny
	lda (zg_obj),y
	adc zs_de+1
	sta sonic_x+1
	jmp cp_stopx
cp_above                        ; @sonic_y_is_below: Sonic nad gora kapsuly
	clc                       ; BC = HL = sonic_x + $0C
	lda sonic_x
	adc #$0C
	sta zs_c
	sta zs_hl
	lda sonic_x+1
	adc #0
	sta zs_b
	sta zs_hl+1
	ldy #OB_X+1               ; DE = x; HL - DE; ret c
	lda (zg_obj),y
	sta zs_de
	iny
	lda (zg_obj),y
	sta zs_de+1
	lda zs_hl
	sec
	sbc zs_de
	lda zs_hl+1
	sbc zs_de+1
	jcc cp_ret                ; ret c
	clc                       ; HL = x + $20; HL - BC; ret c
	lda zs_de
	adc #$20
	sta zs_hl
	lda zs_de+1
	adc #0
	sta zs_hl+1
	lda zs_hl
	sec
	sbc zs_c
	lda zs_hl+1
	sbc zs_b
	jcc cp_ret
	lda zs_c                  ; C = (sonic_x + $0C) & $1F, B = 0: C = profil[C]
	and #$1F
	tax
	lda CAP_PROFILE,x
	sta zs_c
	lda #0
	sta zs_b
	ldy #OB_Y+1               ; sonic_y = y + $FFE0 + C
	sec
	lda (zg_obj),y
	sbc #$20
	sta zs_hl
	iny
	lda (zg_obj),y
	sbc #0
	sta zs_hl+1
	clc
	lda zs_hl
	adc zs_c
	sta sonic_y
	lda zs_hl+1
	adc #0
	sta sonic_y+1
	lda g_sonic_bounce_vel_y_sub+2 ; a = pix_hi, HL = sub / lo
	pha
	lda g_sonic_bounce_vel_y_sub
	sta sonic_vel_y_sub
	lda g_sonic_bounce_vel_y_sub+1
	sta sonic_vel_y
	pla
	sta sonic_vel_y_hi
	lda sonic_flags_ix_24
	ora #$80                  ; set 7,(hl)
	sta sonic_flags_ix_24
	lda zs_c
	cmp #$03
	jne cp_ret                ; ret nz
	ldy #OB_SPRITE
	lda #<SPR_CAPNORM
	sta (zg_obj),y
	iny
	lda #>SPR_CAPNORM
	sta (zg_obj),y
	lda iy_06_lvflag01
	and #$02                  ; bit 1,iy_06
	jne cp_spawn
	lda iy_06_lvflag01
	ora #$02
	sta iy_06_lvflag01
cp_stopx                        ; @stop_sonic_x_vel
	lda #0
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
cp_notpos                       ; @sonic_was_not_positioned_correctly
	lda iy_06_lvflag01
	and #$02
	jeq cp_ret                ; ret z
cp_spawn                        ; @spawn_8_explosions
	ldy #18
	lda (zg_obj),y
	cmp #$08
	jcs cp_animals            ; jr nc,@spawn_12_animals
	ldy #17                   ; inc (ix+17)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$14
	jcc cp_ret                ; ret c
	lda #0
	sta (zg_obj),y
	jsr spawn_explosion
	ldy #18                   ; inc (ix+18)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
cp_ret
	rts
cp_animals                      ; @spawn_12_animals
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02                  ; bit 1,(ix+24)
	bne cp_broken
	lda #$A0                  ; g_signpost_tickdown_counter = $A0 (koniec poziomu), muzyka $09 (rst $18)
	sta g_signpost_tickdown_counter
	lda #$09
	jsr play_music
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
cp_broken                       ; @capsule_already_visibly_broken
	lda #0                    ; mapa 0, res 5 iy_00
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda iy_00
	and #$DF
	sta iy_00
	lda g_global_tick_counter
	and #$0F
	jne cp_ret                ; ret nz
	jsr random_A
	and #$01
	clc
	adc #$23                  ; typ $23 / $24
	jsr cp_animal
	ldy #22                   ; inc (ix+22)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$0C
	jcc cp_ret                ; ret c
	ldy #OB_TYPE              ; po 12 zwierzetach kapsula znika
	lda #$FF
	sta (zg_obj),y
	rts

; cp_ptr2: zg_ptr += 2 (inc hl x 2)
cp_ptr2
	clc
	lda zg_ptr
	adc #2
	sta zg_ptr
	bcc cpp_ret
	inc zg_ptr+1
cpp_ret
	rts

; ---------------------------------------------------------------------
; cp_animal (@animal_spawning_subroutine 01:74B6): A = typ ($23 / $24) -> tmp_08; spawn_object; zwierze w pozycji
; kapsuly + (8, $1A), (ix+1, 22, 23) = 0, Vx / Vy: (ix+10) = random_A, (ix+11) = -(2 + (random_A & 1)), (ix+12) = $FF.
; Brak miejsca (C = 1) - nic.
; ---------------------------------------------------------------------
cp_animal
	sta tmp_08
	jsr spawn_object
	jcs ca_ret                ; ret c
	ldy #OB_X+1               ; DE = x, BC = y kapsuly
	lda (zg_obj),y
	sta zs_de
	iny
	lda (zg_obj),y
	sta zs_de+1
	ldy #OB_Y+1
	lda (zg_obj),y
	sta zs_c
	iny
	lda (zg_obj),y
	sta zs_b
	lda tmp_08
	ldy #OB_TYPE
	sta (zg_ptr),y
	lda #0
	ldy #22
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	ldy #1
	sta (zg_ptr),y
	clc                       ; x = DE + 8
	lda zs_de
	adc #8
	ldy #2
	sta (zg_ptr),y
	lda zs_de+1
	adc #0
	iny
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y
	clc                       ; y = BC + $1A
	lda zs_c
	adc #$1A
	ldy #5
	sta (zg_ptr),y
	lda zs_b
	adc #0
	iny
	sta (zg_ptr),y
	jsr random_A
	ldy #10
	sta (zg_ptr),y
	jsr random_A
	and #$01
	clc
	adc #2
	eor #$FF                  ; neg
	clc
	adc #1
	ldy #11
	sta (zg_ptr),y
	lda #$FF
	iny
	sta (zg_ptr),y
ca_ret
	rts

