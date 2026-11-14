; =====================================================================
;  obj/objz_jungle.asm - M6.7 Jungle: obiekty $0C, $11, $27, $28, $29, $2B, $2C (bank obiektow strefy PB_OBJZ, dolaczany z objz.asm).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_0C_platform_fall_on_touch 01:6A47, objfunc_11_badnik_newtron 01:6F08,
;  objfunc_27_platform_downwards_tall 01:7E02, objfunc_28_platform_downwards_wide 01:7E9B, objfunc_29_log 01:7EE6 (+ log_obj_continue 02:8003),
;  objfunc_2C_JUN3_boss 02:8053, objfunc_2B_JUN3_boss_bomb 02:8218. Dane map w banku 45 (OD_SPAN: newtron, platformy $27/$28) pod adresami
;  SMS < $8000 (obj_draw czyta je z banku 45), dane banku 2 ROM-u - w tym banku (OZ_SPAN*).
; =====================================================================
SPR_PLAT_GHZ_Z  = $6911   ; SPRITEMAP_platform_GHZ (bank 45, OD_SPAN4)
SPR_PLAT_JUN_Z  = $6923   ; SPRITEMAP_platform_JUN
SPR_NEWTRON     = $6FED   ; SPRITEMAP_newtron (bank 45, OD_SPAN17)
SPR_PLDOWN_TALL = $7E89   ; SPRITEMAP_platform_downwards_tall (bank 45, OD_SPAN18)
SPR_PLDOWN_WIDE = $7ED9   ; SPRITEMAP_platform_downwards_wide (bank 45, OD_SPAN19)
LUT_LOG_OFFS    = $8019   ; OFFSTAB_log_frame_offsets (bank 2 -> OBJZ)
SPR_LOG         = $8022   ; SPRITEMAP_log
SPR_JBOSS_L     = $81F4   ; SPRTAB_JUN3_boss_facing_left
SPR_JBOSS_R     = $8206   ; SPRTAB_JUN3_boss_facing_right
LUT_BOMB_NORM   = $82C1   ; LUT_JUN3_boss_bomb_anim_sequence_normal
LUT_BOMB_EXPL   = $82C6   ; LUT_JUN3_boss_bomb_anim_sequence_explosion
SPR_JBOMB       = $82CD   ; SPRTAB_JUN3_boss_bomb
SPR_BALLHOG_BOMB = $A3BB  ; SPRTAB_ballhog_bomb (eksplozja bomby: klatki 1-3)

; ---------------------------------------------------------------------
; objfunc_0C_platform_fall_on_touch (01:6A47): platforma spadajaca po dotknieciu (bez kolizji z mapa). (ix+22) = 1 po stanieciu Sonica;
; (ix+23) += (ix+22); od $18 Vy (24 bit) += $0040. Sonic (Vy >= 0, 26 x 16, przesuniecie (6, 8)) stoi na niej. Mapa wg strefy (GHZ / reszta:
; JUN); usuwana ponizej ekranu (y > kamera Y + $C0; przy rownosci zostaje - 01:6AB9 sbc hl,de / ret nc).
; ---------------------------------------------------------------------
objfunc_0C_platform_fall
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #22
	lda (zg_obj),y
	iny
	clc
	adc (zg_obj),y
	sta (zg_obj),y
	cmp #$18
	bcc pf_nofall
	ldy #OB_VY                ; Vy += $0040 (24 bit)
	clc
	lda (zg_obj),y
	adc #$40
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
pf_nofall                       ; @pre_fall_delay_was_not_expired
	ldy #OB_W
	lda #$1A
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	lda sonic_vel_y_hi
	bmi pf_nopos              ; jp m
	lda #$06                  ; hl = $0806
	sta tmp_06
	lda #$08
	sta tmp_07
	jsr zc_collide
	bcs pf_nopos
	lda #1                    ; (ix+22) = 1
	ldy #22
	sta (zg_obj),y
	ldy #OB_VY                ; de = Vy platformy, bc = $0010
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	lda #$10
	sta zg_bc
	lda #0
	sta zg_bc+1
	jsr zc_put
pf_nopos                        ; @sonic_was_not_positioned_correctly
	lda #<SPR_PLAT_GHZ_Z
	ldx #>SPR_PLAT_GHZ_Z
	ldy g_tile_flags_index
	beq pf_map
	lda #<SPR_PLAT_JUN_Z
	ldx #>SPR_PLAT_JUN_Z
pf_map
	ldy #OB_SPRITE
	sta (zg_obj),y
	txa
	iny
	sta (zg_obj),y
	clc                       ; hl = kamera Y + $C0 - y: bez pozyczki -> zostaje; z pozyczka -> usuniecie
	lda g_level_scroll_y_pix_lo
	adc #$C0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #0
	sta zg_hl+1
	ldy #OB_Y+1
	sec
	lda zg_hl
	sbc (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	bcs pf_ret
	lda #$FF
	ldy #OB_TYPE
	sta (zg_obj),y
pf_ret
	rts

; ---------------------------------------------------------------------
; objfunc_11_badnik_newtron (01:6F08): bez kolizji z mapa, 12 x 20. Stany (ix+17): 0 i 2 - czekanie 60 tickow ((ix+23) do $3C; mapa
; co drugi tick, potem 0) i stan + 1; 1 - (ix+23) do $64: strzal (kula ognia $0D z (x, y + 6), Vx = -2 px/tick, efekt $0A), do $78
; stan 2, (ix+23) = 0; 3 - mapa 0, (ix+23) + 1, przy zawinieciu stan 0. Kolizja z Soniciem (przesuniecie 2, 2), tmp_00 = 0 - enemy_touched_sonic.
; ---------------------------------------------------------------------
objfunc_11_newtron
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W
	lda #$0C
	sta (zg_obj),y
	iny
	lda #$14
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	cmp #$02
	beq nt_s02
	tax                       ; and a / jr nz
	bne nt_not0
nt_s02                          ; @state_02 (i stan 0): mapa co drugi tick
	lda g_global_tick_counter
	and #$01
	beq nt_m0
	lda #0
	sta zg_bc
	sta zg_bc+1
	beq nt_mset               ; zawsze
nt_m0
	lda #<SPR_NEWTRON
	sta zg_bc
	lda #>SPR_NEWTRON
	sta zg_bc+1
nt_mset
	ldy #23
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$3C
	jcc nt_cont
	lda #0
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	jmp nt_cont
nt_not0
	cmp #$01
	jne nt_not1
	ldy #23
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$64
	bne nt_nospawn
	jsr spawn_object
	bcs nt_spawnfail
	ldy #OB_X+1               ; kula ognia: x = x newtrona, y = y + 6, Vx = $FFFE00
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	ldy #OB_Y+1
	clc
	lda (zg_obj),y
	adc #6
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	lda #0
	ldy #OB_TYPE
	lda #$0D
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y            ; +1
	iny
	lda zg_de
	sta (zg_ptr),y            ; +2, +3: x
	iny
	lda zg_de+1
	sta (zg_ptr),y
	iny
	lda #0
	sta (zg_ptr),y            ; +4
	iny
	lda zg_hl
	sta (zg_ptr),y            ; +5, +6: y + 6
	iny
	lda zg_hl+1
	sta (zg_ptr),y
	lda #0
	ldy #17
	sta (zg_ptr),y            ; +17, +19..+23 = 0
	ldy #19
nt_zl
	sta (zg_ptr),y
	iny
	cpy #24
	bne nt_zl
	ldy #OB_VX                ; Vx = $FFFE00 (0, $FE, $FF), Vy = 0
	sta (zg_ptr),y
	iny
	lda #$FE
	sta (zg_ptr),y
	iny
	lda #$FF
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	lda #$0A                  ; rst $28
	jsr play_sfx
	lda #$0A                  ; A po rst $28 - efekt dzwiekowy zostawia mniej niz $78 (cp $78: pozyczka)
	jmp nt_nospawn2
nt_spawnfail
	lda #0                    ; spawn_object bez miejsca: A = typ ostatniego slotu (< $78)
	jmp nt_nospawn2
nt_nospawn
	ldy #23
	lda (zg_obj),y
nt_nospawn2                     ; @dont_spawn_fireball: bc = mapa newtrona; A >= $78 -> (ix+23) = 0, stan + 1
	pha
	lda #<SPR_NEWTRON
	sta zg_bc
	lda #>SPR_NEWTRON
	sta zg_bc+1
	pla
	cmp #$78
	bcc nt_cont
	lda #0
	ldy #23
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	jmp nt_cont
nt_not1
	cmp #$03
	bne nt_cont
	lda #0                    ; stan 3: mapa 0, (ix+23) + 1, po zawinieciu stan 0
	sta zg_bc
	sta zg_bc+1
	ldy #23
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	bne nt_cont
	ldy #17
	lda zg_bc                 ; (ix+17) = c = 0
	sta (zg_obj),y
nt_cont                         ; @continue: mapa = bc
	ldy #OB_SPRITE
	lda zg_bc
	sta (zg_obj),y
	iny
	lda zg_bc+1
	sta (zg_obj),y
	lda #$02                  ; hl = $0202
	sta tmp_06
	sta tmp_07
	jsr zc_collide
	lda #0
	sta tmp_00
	sta tmp_00+1
	bcs nt_ret
	jmp zc_enemy
nt_ret
	rts

; ---------------------------------------------------------------------
; objfunc_27_platform_downwards_tall (01:7E02) i objfunc_28_platform_downwards_wide (01:7E9B), wspolna platform_downwards_common (01:7E3C):
; platforma zjezdza (Vy = $80 subpikseli = 0,5 px/tick, 01:7E3C), Sonic (Vy >= 0, przesuniecie (6, 8)) stoi na niej (bez znacznika w rekordzie); co 4 ticki (ix+17) + 1, gdy
; >= (ix+20) ($C0 / $C6): (ix+17) = 0, y = poczatkowe y ((ix+18/19)). Cele okna Sonica x: $30 / $58. Pierwszy tick: (ix+18/19) = y, (ix+20), set 0.
; ---------------------------------------------------------------------
objfunc_27_platform_tall
	ldx #$C0
	stx zg_a
	lda #<SPR_PLDOWN_TALL
	sta zg_hl
	lda #>SPR_PLDOWN_TALL
	sta zg_hl+1
	lda #$0C
	jmp pd_start
objfunc_28_platform_wide
	ldx #$C6
	stx zg_a
	lda #<SPR_PLDOWN_WIDE
	sta zg_hl
	lda #>SPR_PLDOWN_WIDE
	sta zg_hl+1
	lda #$1A
pd_start
	pha
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #$30                  ; g_camera_sonic_bounds_x0_target = $0030, x1_target = $0058
	sta g_camera_sonic_bounds_x0_target
	lda #0
	sta g_camera_sonic_bounds_x0_target+1
	lda #$58
	sta g_camera_sonic_bounds_x1_target
	lda #0
	sta g_camera_sonic_bounds_x1_target+1
	pla
	ldy #OB_W
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	ldy #OB_SPRITE
	lda zg_hl
	sta (zg_obj),y
	iny
	lda zg_hl+1
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$01
	bne pd_common
	ldy #OB_Y+1               ; (ix+18/19) = y, (ix+20) = limit, set 0
	lda (zg_obj),y
	ldy #18
	sta (zg_obj),y
	ldy #OB_Y+2
	lda (zg_obj),y
	ldy #19
	sta (zg_obj),y
	lda zg_a
	ldy #20
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
pd_common                       ; platform_downwards_common: Vy = $000080
	ldy #OB_VY
	lda #$80
	sta (zg_obj),y
	lda #0
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda sonic_vel_y_hi
	bmi pd_nocoll
	lda #$06                  ; hl = $0806
	sta tmp_06
	lda #$08
	sta tmp_07
	jsr zc_collide
	bcs pd_nocoll
	; uwaga: bez zapisu (ix+22) - oryginal (01:7E57-01:7E62) od razu wola put_sonic_y_pos_on_platform; (ix+22) = 1
	; ustawia tylko platforma $0C (objfunc_0C 01:6A47) - tu bylby to bajt rozny od Mesena w slocie (m67-platformy-dol)
	ldy #OB_VY                ; de = Vy platformy ($0080), bc = $0010
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	lda #$10
	sta zg_bc
	lda #0
	sta zg_bc+1
	jsr zc_put
pd_nocoll                       ; @not_collided_with_sonic
	lda g_global_tick_counter
	and #$03
	bne pd_ret
	ldy #17
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	ldy #20
	cmp (zg_obj),y
	bcc pd_ret
	lda #0                    ; (ix+17) = 0, (ix+4) = 0, y = (ix+18/19)
	ldy #17
	sta (zg_obj),y
	ldy #OB_Y
	sta (zg_obj),y
	ldy #18
	lda (zg_obj),y
	ldy #OB_Y+1
	sta (zg_obj),y
	ldy #19
	lda (zg_obj),y
	ldy #OB_Y+2
	sta (zg_obj),y
pd_ret
	rts

; ---------------------------------------------------------------------
; objfunc_29_log (01:7EE6): kloda na wodzie (bez kolizji z mapa, 10 x 16). Pierwszy tick: y -= $18, set 0. Kolysanie: Vy = +$40 subpikseli,
; po (ix+17) >= $14 Vy = -$40. Sonic (Vy >= 0, przesuniecie (6, 8)) stoi na kloddzie i ja obraca: Vx Sonica != 0 - klodka przesuwa sie i Sonic
; razem z nia (x += Vx / 2, chyba ze przed nim jest sciana: typ kolizji bloku <> 0), animacja obrotu ((ix+18/19) += |Vx|, 9 klatek, mapy
; SPRITEMAP_log wg OFFSTAB_log_frame_offsets). (ix+17) + 1 do $28.
; ---------------------------------------------------------------------
objfunc_29_log
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W
	lda #$0A
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$01
	bne lg_init
	ldy #OB_Y+1               ; y += $FFE8
	sec
	lda (zg_obj),y
	sbc #$18
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	sbc #0
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
lg_init                         ; @already_initialised: Vy = $000040 albo $FFFFC0
	ldy #OB_VY
	lda #$40
	sta (zg_obj),y
	lda #0
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	cmp #$14
	bcc lg_down
	ldy #OB_VY
	lda #$C0
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
lg_down                         ; @bobbing_was_downwards
	lda sonic_vel_y_hi
	jmi lg_cont
	lda #$06                  ; hl = $0806
	sta tmp_06
	lda #$08
	sta tmp_07
	jsr zc_collide
	jcs lg_cont
	ldy #OB_VY                ; de = Vy kloda, bc = $0010
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	lda #$10
	sta zg_bc
	lda #0
	sta zg_bc+1
	jsr zc_put
	lda sonic_vel_x_sub       ; hl = (sonic_vel_x_sub, sonic_vel_x); or: 0 -> Sonic nie biegnie
	ora sonic_vel_x
	jeq lg_notrun
	lda #$12                  ; bc = $0012 (w prawo) albo $FFFE (w lewo) - przesuniecie testu bloku przed klodka
	sta zg_bc
	lda #0
	sta zg_bc+1
	lda sonic_vel_x
	bpl lg_runright
	lda #$FE
	sta zg_bc
	lda #$FF
	sta zg_bc+1
lg_runright
	lda #0                    ; de = 0
	sta zg_de
	sta zg_de+1
	jsr obj_tile_ptr          ; get_obj_level_tile_ptr_in_ram: blok przed klodka (x + bc, y)
	bcs lg_wall0              ; adres ROM - typ 0
	ldy #0
	lda (zg_ptr),y
	tax
	lda TILEFLAGS_RAM,x
	and #$3F
	jmp lg_tf
lg_wall0
	lda #0
lg_tf
	bne lg_blocked            ; typ kolizji <> 0 -> bez przesuniecia (a = 0, e = d = 0)
lg_notrun                       ; @x_vel_sonic_was_not_running (i nie biegnie): przesuniecie = (Vx sonica / 2, ze znakiem), 24 bit
	lda sonic_vel_x_sub
	sta zg_a                  ; a = sub
	lda sonic_vel_x
	sta zg_de                 ; e = lo
	lda sonic_vel_x_hi
	sta zg_de+1               ; d = hi (hi i lo bajt Vx: 'ld de,(sonic_vel_x)' = (lo, hi))
	cmp #$80                  ; sra d
	ror zg_de+1
	ror zg_de                 ; rr e
	ror zg_a                  ; rra
	jmp lg_move
lg_blocked
	lda #0
	sta zg_a
	sta zg_de
	sta zg_de+1
lg_move                         ; @did_not_hit_non_00_tileflag: x (24 bit) += de (a = sub), Sonic: x = nowe x - 4
	clc
	ldy #OB_X
	lda zg_a
	adc (zg_obj),y            ; (ix+1) + sub
	sta zg_a
	iny
	lda (zg_obj),y
	adc zg_de
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_hl+1
	lda zg_a
	ldy #OB_X
	sta (zg_obj),y
	lda zg_hl
	iny
	sta (zg_obj),y
	lda zg_hl+1
	iny
	sta (zg_obj),y
	lda zg_a
	sta sonic_x_sub
	sec                       ; sonic_x = x - 4
	lda zg_hl
	sbc #4
	sta sonic_x
	lda zg_hl+1
	sbc #0
	sta sonic_x+1
	lda sonic_vel_x_sub       ; de = |Vx Sonica| (16 bit: sub, lo)
	sta zg_de
	lda sonic_vel_x
	sta zg_de+1
	lda zg_de+1               ; bit 7,d: D = bajt pikselowy Vx (sonic_vel_x)
	bpl lg_pos
	sec                       ; neg de
	lda #0
	sbc zg_de
	sta zg_de
	lda #0
	sbc zg_de+1
	sta zg_de+1
lg_pos                          ; @anim_sonic_was_not_running: (ix+18/19) += de; (ix+19) >= 9 -> - 9
	ldy #18
	clc
	lda (zg_obj),y
	adc zg_de
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_hl+1
	cmp #$09
	bcc lg_nowrap
	sec
	sbc #$09
	sta zg_hl+1
lg_nowrap
	ldy #18
	lda zg_hl
	sta (zg_obj),y
	iny
	lda zg_hl+1
	sta (zg_obj),y
	tax
	lda LUT_LOG_OFFS-OZ_OFF,x ; mapa = SPRITEMAP_log + offset klatki
	clc
	adc #<SPR_LOG
	ldy #OB_SPRITE
	sta (zg_obj),y
	lda #>SPR_LOG
	adc #0
	iny
	sta (zg_obj),y
	jmp lg_spr
lg_cont                         ; log_obj_continue (02:8003): mapa = SPRITEMAP_log (klatka 0)
	ldy #OB_SPRITE
	lda #<SPR_LOG
	sta (zg_obj),y
	iny
	lda #>SPR_LOG
	sta (zg_obj),y
lg_spr                          ; @sprite_was_set: (ix+17) + 1, od $28 znowu 0
	ldy #17
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$28
	bcc lg_ret
	lda #0
	sta (zg_obj),y
lg_ret
	rts

; ---------------------------------------------------------------------
; objfunc_2C_JUN3_boss (02:8053): boss JUN3 - wchodzi z gory, lata w poziomie miedzy x $021C i $02AA, zrzuca bomby. Wlaczenie: Sonic na ziemi
; i y < $E0 (sprawdzane co tick, az do spelnienia; 02:8065-02:8073): grafika bossa (zc_bossart1: ART_09_AEB1), paleta, muzyka $0B, trafienia 0, granice poziomu = kamera, cel kamery
; ($01F0, $0048). Stany: (ix+17) b0 = wejscie zakonczone, b1 = kierunek; (ix+18) = licznik ruchu pionowego ($67 -> 0): w gore / zawis / w dol, bomba
; przy $34. Co tick boss_generic_update_8hp (tmp_08 = $005A) i plomien silnika.
; ---------------------------------------------------------------------
objfunc_2C_JUN3_boss
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W
	lda #$20
	sta (zg_obj),y
	iny
	lda #$1C
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$01
	jne jb_inited
	sec                       ; sonic_y - $E0: bez pozyczki -> koniec (jeszcze za nisko)
	lda sonic_y
	sbc #$E0
	lda sonic_y+1
	sbc #0
	jcs jb_ret
	lda sonic_flags_ix_24
	jpl jb_ret                ; rlca / ret nc: Sonic w powietrzu
	jsr zc_bossart1           ; load_art ART_09_AEB1 -> $2000 (kafle sprite'ow $00-$7F)
	lda iy_00                 ; signal_load_palettes (00:0333): A = 2 (sprite'y), HL = PAL2_boss
	ora #$08
	sta iy_00
	lda #$02
	sta g_SIG00b3_palettes_present
	lda #<PAL2_BOSS
	sta g_SIG00b3_palette_addr
	lda #>PAL2_BOSS
	sta g_SIG00b3_palette_addr+1
	lda #$0B                  ; rst $18
	jsr play_music
	lda #0
	sta g_boss_hits_taken
	lda g_level_scroll_x_pix_lo ; granice poziomu x0 = x1 = kamera X, y0 = y1 = kamera Y
	sta g_level_limit_x0
	sta g_level_limit_x1
	lda g_level_scroll_x_pix_lo+1
	sta g_level_limit_x0+1
	sta g_level_limit_x1+1
	lda g_level_scroll_y_pix_lo
	sta g_level_limit_y0
	sta g_level_limit_y1
	lda g_level_scroll_y_pix_lo+1
	sta g_level_limit_y0+1
	sta g_level_limit_y1+1
	lda #<$01F0               ; cel kamery ($01F0, $0048)
	sta g_level_camera_lock_towards_x
	lda #>$01F0
	sta g_level_camera_lock_towards_x+1
	lda #<$0048
	sta g_level_camera_lock_towards_y
	lda #>$0048
	sta g_level_camera_lock_towards_y+1
	ldy #OB_FLAGS             ; set 0
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
jb_inited
	jsr zc_mlc                ; move_locked_camera_towards_target
	ldy #17
	lda (zg_obj),y
	and #$01
	bne jb_entered
	lda #<SPR_JBOSS_L         ; wejscie: mapa w lewo, Vy = $80 subpikseli w dol do y = $58
	ldx #>SPR_JBOSS_L
	jsr jb_setmap
	ldy #OB_VY
	lda #$80
	sta (zg_obj),y
	lda #0
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_Y+1
	sec
	lda (zg_obj),y
	sbc #$58
	iny
	lda (zg_obj),y
	sbc #0
	jcc jb_ret                ; ret c: jeszcze wchodzi
	lda #0                    ; Vy = 0, set 0,(ix+17)
	ldy #OB_VY
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
jb_entered                      ; @finished_move_down_entry_animation
	ldy #18
	lda (zg_obj),y
	jne jb_vert
	ldy #OB_X+1               ; hl = x
	lda (zg_obj),y
	sta zg_hl
	iny
	lda (zg_obj),y
	sta zg_hl+1
	ldy #17
	lda (zg_obj),y
	and #$02
	bne jb_right
	lda #<SPR_JBOSS_L         ; w lewo: mapa L, res 1,(ix+24), Vx = $FFFF00, gdy x >= $021C: dalej, inaczej (ix+18) = $67
	ldx #>SPR_JBOSS_L
	jsr jb_setmap
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$FD
	sta (zg_obj),y
	lda #0
	ldy #OB_VX
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	sec
	lda zg_hl
	sbc #<$021C
	lda zg_hl+1
	sbc #>$021C
	jcs jb_common             ; jp nc
	lda #$67
	ldy #18
	sta (zg_obj),y
	jmp jb_common
jb_right                        ; @moving_right
	lda #<SPR_JBOSS_R
	ldx #>SPR_JBOSS_R
	jsr jb_setmap
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
	lda #0
	ldy #OB_VX
	sta (zg_obj),y
	lda #$01
	iny
	sta (zg_obj),y
	lda #0
	iny
	sta (zg_obj),y
	sec
	lda zg_hl
	sbc #<$02AA
	lda zg_hl+1
	sbc #>$02AA
	jcc jb_common             ; jp c
	lda #$67
	ldy #18
	sta (zg_obj),y
	jmp jb_common
jb_vert                         ; @moving_vertically: Vx = 0, hl = Vy (1 w dol, $FFFF w gore, 0 zawis)
	lda #0
	ldy #OB_VX
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #18
	lda (zg_obj),y
	sec
	sbc #1
	sta (zg_obj),y
	beq jb_vz                 ; jr z @y_vel_will_be_0
	cmp #$40
	bcs jb_down               ; >= $40: hl = 1
	cmp #$28
	bcc jb_up                 ; < $28: hl = $FFFF
	cmp #$34
	beq jb_bomb
jb_vz
	lda #0
	sta zg_hl
	sta zg_hl+1
	jmp jb_setvy
jb_down
	lda #1
	sta zg_hl
	lda #0
	sta zg_hl+1
	jmp jb_setvy
jb_up
	lda #$FF
	sta zg_hl
	sta zg_hl+1
jb_setvy                        ; @set_y_vel: Vy = (0, l, h)
	ldy #OB_VY
	lda #0
	sta (zg_obj),y
	iny
	lda zg_hl
	sta (zg_obj),y
	iny
	lda zg_hl+1
	sta (zg_obj),y
	jmp jb_common
jb_bomb                         ; @drop_bomb: kierunek (b1) odwrocony; bomba, gdy trafienia < 8
	ldy #17
	lda (zg_obj),y
	eor #$02
	sta (zg_obj),y
	lda g_boss_hits_taken
	cmp #$08
	bcs jb_common
	jsr spawn_object
	jcs jb_ret                ; ret c (bez aktualizacji bossa)
	ldy #OB_X+1               ; de = x, bc = y bossa
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	ldy #OB_Y+1
	lda (zg_obj),y
	sta zg_bc
	iny
	lda (zg_obj),y
	sta zg_bc+1
	ldy #OB_TYPE              ; bomba $2B: x = x + $0B, y = y + $30, predkosci 0
	lda #$2B
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y
	clc
	lda zg_de
	adc #$0B
	iny
	sta (zg_ptr),y
	lda zg_de+1
	adc #0
	iny
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y            ; +4
	clc
	lda zg_bc
	adc #$30
	iny
	sta (zg_ptr),y
	lda zg_bc+1
	adc #0
	iny
	sta (zg_ptr),y
	lda #0
	ldy #OB_VX
jb_zv
	sta (zg_ptr),y            ; Vx, Vy = 0 (+7..+12)
	iny
	cpy #13
	bne jb_zv
	lda #0
	ldy #17
	sta (zg_ptr),y
	ldy #22
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	jsr random_A              ; (ix+18) = (random_A & $3F) + $64
	and #$3F
	clc
	adc #$64
	ldy #18
	sta (zg_ptr),y
jb_common                       ; @continue_to_common_code
	lda #<$005A
	sta tmp_08
	lda #>$005A
	sta tmp_08+1
	jsr zc_boss8
	jmp zc_flame              ; boss_render_jet_engine_flame
jb_ret
	rts
jb_setmap                       ; (ix+15/16) = A (lo), X (hi)
	ldy #OB_SPRITE
	sta (zg_obj),y
	txa
	iny
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_2B_JUN3_boss_bomb (02:8218): bomba bossa JUN3 (bez b5: kolizje z mapa wlaczone), 12 x 16, damage_sonic przy kolizji (przesuniecie 2, 2).
; Vx (24 bit) wygasa o 2 subpiksele ku zeru, Vy + $20 (do $0300). (ix+17) += tick & 1: < (ix+18) - animacja bomby; = (ix+18) - wybuch
; (efekt $01 raz - w nieparzystym ticku rownosci, w parzystym ret z; Vx = 0, Vy dalej rosnie), potem animacja eksplozji (ballhog);
; gdy (ix+17) > (ix+18) + $12 - usuniecie (02:82B8: cp / ret nc).
; ---------------------------------------------------------------------
objfunc_2B_JUN3_bomb
	ldy #OB_FLAGS             ; res 5
	lda (zg_obj),y
	and #$DF
	sta (zg_obj),y
	ldy #OB_W
	lda #$0C
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	lda #$02                  ; hl = $0202
	sta tmp_06
	sta tmp_07
	jsr zc_collide
	bcs jbm_c1
	jsr damage_sonic
jbm_c1
	ldy #OB_VX+2              ; Vx (24 bit) += $0002 gdy ujemne (bit 7 bajtu 9), inaczej += $FFFE
	lda (zg_obj),y
	ldx #0
	stx zg_a                  ; c
	ldx #$02
	stx zg_de
	ldx #0
	stx zg_de+1
	and #$80
	bne jbm_xpos              ; jp m: Vx ujemne -> + 2
	lda #$FF
	sta zg_a                  ; dec c
	lda #$FE
	sta zg_de
	lda #$FF
	sta zg_de+1
jbm_xpos
	ldy #OB_VX
	clc
	lda (zg_obj),y
	adc zg_de
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc zg_a
	sta (zg_obj),y
	ldy #OB_VY                ; Vy += $0020, bajt wyzszy (ix+11) >= 3 -> $0300
	clc
	lda (zg_obj),y
	adc #$20
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	iny
	lda (zg_obj),y
	adc #0
	sta zg_a
	lda zg_hl+1
	cmp #$03
	bcc jbm_vst
	lda #0
	sta zg_hl
	lda #3
	sta zg_hl+1
	lda #0
	sta zg_a
jbm_vst
	ldy #OB_VY
	lda zg_hl
	sta (zg_obj),y
	iny
	lda zg_hl+1
	sta (zg_obj),y
	iny
	lda zg_a
	sta (zg_obj),y
	lda g_global_tick_counter ; (ix+17) += tick & 1
	and #$01
	ldy #17
	clc
	adc (zg_obj),y
	sta (zg_obj),y
	ldy #18
	cmp (zg_obj),y
	bcs jbm_expl              ; jr nc: (ix+17) >= (ix+18)
	lda #<[LUT_BOMB_NORM-OZ_OFF]
	sta zg_bc
	lda #>[LUT_BOMB_NORM-OZ_OFF]
	sta zg_bc+1
	lda #<SPR_JBOMB
	sta zg_de
	lda #>SPR_JBOMB
	sta zg_de+1
	jmp oz_dfa
jbm_expl                        ; @handle_explosion (flagi z cp: Z = rowne)
	bne jbm_nosfx             ; jr nz @skip_explosion_sound_effect
	lda g_global_tick_counter
	and #$01
	beq jbm_ret               ; ret z
	lda #0                    ; (ix+22) = 0
	ldy #22
	sta (zg_obj),y
	lda #$01                  ; rst $28
	jsr play_sfx
jbm_nosfx
	lda #0                    ; Vx = 0
	ldy #OB_VX
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #<[LUT_BOMB_EXPL-OZ_OFF]
	sta zg_bc
	lda #>[LUT_BOMB_EXPL-OZ_OFF]
	sta zg_bc+1
	lda #<SPR_BALLHOG_BOMB
	sta zg_de
	lda #>SPR_BALLHOG_BOMB
	sta zg_de+1
	jsr oz_dfa
	ldy #18                   ; a = (ix+18) + $12; cp (ix+17): (ix+18) + $12 >= (ix+17) -> ret nc; inaczej typ $FF
	lda (zg_obj),y
	clc
	adc #$12
	ldy #17
	cmp (zg_obj),y
	bcs jbm_ret               ; ret nc
	lda #$FF
	ldy #OB_TYPE
	sta (zg_obj),y
jbm_ret
	rts
