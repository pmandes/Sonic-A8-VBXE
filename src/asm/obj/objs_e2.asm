; =====================================================================
;  objs_e2.asm - M6.4 GHZ3: boss_generic_update_8hp, plomien, spawn_explosion, midtick_irq, art_load_common (stale G3B_* itd. w objs_e1.asm)
; =====================================================================
; ---------------------------------------------------------------------
; boss_generic_update_8hp (01:77BE): tmp_08 = przesuniecie map sprite'ow (SPRTAB_boss_generic_fly_out + tmp_08).
; Trafienia < 8: bez migotania palety (g_pal_flash_countdown_timer = 0) kolizja z Soniciem (tmp_06 = $0C08);
; Sonic umiera / nie atakuje -> damage_sonic; atakuje (toczenie b0 albo skok b2) -> Vy = -Vy, Vx = 0, migotanie
; palety ($18, indeks $8F, kolor $3F), efekt $01, trafienia + 1. Dalej mapa (b1 (ix+24): + $12), czas
; do nastepnego wybuchu = $18. Trafienia >= 8 - sekwencja smierci (@handle_death_sequence): 10 wybuchow co $18
; ticki, opadanie, powrot muzyki poziomu i IRQ w srodku ticku, lot w prawo i w gore, po wyjsciu poza ekran -
; usuniecie bossa, odblokowanie kamery i grafika zwierzat / kapsuly (ART_0C_DA28).
; ---------------------------------------------------------------------
boss_generic_update_8hp
	lda g_boss_hits_taken
	cmp #8
	jcs bg_death
	lda g_pal_flash_countdown_timer
	jne bg_skipdmg
	lda #$08                  ; tmp_06 = $0C08
	sta tmp_06
	lda #$0C
	sta tmp_06+1
	jsr check_collision_with_sonic
	jcs bg_ret                ; ret c
	lda iy_05_lvflag00
	lsr
	jcs bg_ret                ; bit 0,iy_05 / ret nz (Sonic umiera)
	lda sonic_flags_ix_24
	lsr                       ; rrca: C = b0
	bcs bg_cause
	and #$02                  ; po rrca: b1 = b2 flagi
	bne bg_cause
	jmp damage_sonic          ; jp z,damage_sonic
bg_cause                        ; @sonic_causes_damage: Vy = -Vy (24 bit: cpl, + 1)
	lda sonic_vel_y_sub
	eor #$FF
	sta zs_hl
	lda sonic_vel_y
	eor #$FF
	sta zs_hl+1
	lda sonic_vel_y_hi
	eor #$FF
	sta zs_t
	clc
	lda zs_hl
	adc #1
	sta sonic_vel_y_sub
	lda zs_hl+1
	adc #0
	sta sonic_vel_y
	lda zs_t
	adc #0
	sta sonic_vel_y_hi
	lda #0
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
	lda #$18
	sta g_pal_flash_countdown_timer
	lda #$8F
	sta g_pal_flash_idx
	lda #$3F
	sta g_pal_flash_color_value
	lda #$01                  ; rst $28
	jsr play_sfx
	inc g_boss_hits_taken
bg_skipdmg                      ; @skip_damage_check_due_to_flashing_anim
	clc                       ; HL = tmp_08 + SPRTAB_boss_generic_fly_out
	lda tmp_08
	adc #<SPR_BOSSOUT
	sta zs_hl
	lda tmp_08+1
	adc #>SPR_BOSSOUT
	sta zs_hl+1
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02                  ; bit 1,(ix+24)
	beq bg_spr1
	clc
	lda zs_hl
	adc #$12
	sta zs_hl
	lda zs_hl+1
	adc #0
	sta zs_hl+1
bg_spr1                         ; @moving_left_sprite_1
	ldy #OB_SPRITE
	lda zs_hl
	sta (zg_obj),y
	iny
	lda zs_hl+1
	sta (zg_obj),y
	lda #$18                  ; g_boss_death_next_explosion_countdown_timer = $18, licznik wybuchow = 0
	sta g_boss_death_next_explosion_countdown_timer
	lda #0
	sta g_boss_death_explosions_done_then_countup_timer
bg_ret
	rts

bg_death                        ; @handle_death_sequence: ruch zatrzymany, mapa wg tmp_08 + $24 ($36 - w prawo)
	lda #0
	ldy #OB_VX
bg_zv
	sta (zg_obj),y
	iny
	cpy #OB_VX+6
	bne bg_zv
	ldx #$24
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02
	beq bg_spr2
	ldx #$36
bg_spr2                         ; @moving_left_sprite_2
	stx zs_t
	clc
	lda tmp_08
	adc zs_t
	sta zs_hl
	lda tmp_08+1
	adc #0
	sta zs_hl+1
	clc
	lda zs_hl
	adc #<SPR_BOSSOUT
	ldy #OB_SPRITE
	sta (zg_obj),y
	lda zs_hl+1
	adc #>SPR_BOSSOUT
	iny
	sta (zg_obj),y
	lda g_boss_death_explosions_done_then_countup_timer
	cmp #$0A
	bcs bg_done10             ; jp nc,@already_done_10_explosions
	dec g_boss_death_next_explosion_countdown_timer
	jne bg_ret                ; ret nz
	lda #$18
	sta g_boss_death_next_explosion_countdown_timer
	inc g_boss_death_explosions_done_then_countup_timer
	jmp spawn_explosion
bg_done10                       ; @already_done_10_explosions
	lda g_boss_death_explosions_done_then_countup_timer
	cmp #$3A
	bcs bg_nodown             ; jr nc,@already_done_downwards_movement
	ldy #4                    ; y (24 bit: +4 sub, +5 lo, +6 hi) += $20
	clc
	lda (zg_obj),y
	adc #$20
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
bg_nodown                       ; @already_done_downwards_movement
	lda g_boss_death_explosions_done_then_countup_timer
	cmp #$5A
	bcs bg_flyout             ; jr nc,@time_to_fly_out
	inc g_boss_death_explosions_done_then_countup_timer
	rts
bg_flyout                       ; @time_to_fly_out (flagi z cmp #$5A)
	bne bg_flying             ; jr nz,@already_restored_music (licznik > $5A)
	lda #$5B
	sta g_boss_death_explosions_done_then_countup_timer
	lda g_level_music         ; powrot muzyki poziomu (rst $18), IRQ w srodku ticku (res 0 iy_00 / wait_until_irq_ticked)
	jsr play_music
	jsr midtick_irq
bg_flying                       ; @already_restored_music: lot w prawo (Vx = $000300) i w gore (Vy = $FFFF60)
	ldy #OB_VX
	lda #$00
	sta (zg_obj),y
	iny
	lda #$03
	sta (zg_obj),y
	iny
	lda #$00
	sta (zg_obj),y
	iny
	lda #$60
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_SPRITE
	lda #<SPR_BOSSOUT
	sta (zg_obj),y
	iny
	lda #>SPR_BOSSOUT
	sta (zg_obj),y
	lda g_level_scroll_x_pix_lo+1 ; HL = x - (cam_x + $0100) (inc d); ret c - boss jeszcze nie poza ekranem
	clc
	adc #1
	sta zs_t
	ldy #OB_X+1
	lda (zg_obj),y
	sec
	sbc g_level_scroll_x_pix_lo
	iny
	lda (zg_obj),y
	sbc zs_t
	jcc bg_ret
	ldy #OB_TYPE              ; usuniecie bossa, odblokowanie kamery i grafika zwierzat (ART_0C_DA28)
	lda #$FF
	sta (zg_obj),y
	lda #0                    ; g_level_limit_x1 = $2000, kamera bez celu X
	sta g_level_limit_x1
	sta g_level_camera_lock_towards_x
	sta g_level_camera_lock_towards_x+1
	lda #$20
	sta g_level_limit_x1+1
	lda iy_00
	ora #$20                  ; set 5,iy_00
	sta iy_00
	lda iy_02
	ora #$01                  ; set 0,iy_02
	and #$FD                  ; res 1,iy_02
	sta iy_02
	lda g_level
	cmp #$0B                  ; poziom $0B (LAB3): set 1,iy_09
	bne bg_nolab
	lda iy_09
	ora #$02
	sta iy_09
bg_nolab
	lda #2                    ; load_art ART_0C_DA28 -> $2000 (zwierzeta i kapsula)
	sta v_art_req
	jmp art_load_common

; ---------------------------------------------------------------------
; boss_render_jet_engine_flame (01:79FA): boss rusza sie poziomo ((ix+7) | (ix+8) != 0), co 2 ticki: draw_sprite kafla
; ($02 / $00 wg b1 licznika + $04, gdy Vx >= 0) w (x + $FFF8 / $0028, y + $10) - plomien za silnikiem.
; ---------------------------------------------------------------------
boss_render_jet_engine_flame
	ldy #OB_VX
	lda (zg_obj),y
	iny
	ora (zg_obj),y
	jeq fl_ret                ; ret z
	lda g_global_tick_counter
	lsr
	jcs fl_ret                ; bit 0,a / ret nz
	lda g_global_tick_counter
	and #$02
	sta zs_t                  ; a
	ldy #OB_X+1               ; tmp_00 = x, tmp_02 = y
	lda (zg_obj),y
	sta tmp_00
	iny
	lda (zg_obj),y
	sta tmp_00+1
	ldy #OB_Y+1
	lda (zg_obj),y
	sta tmp_02
	iny
	lda (zg_obj),y
	sta tmp_02+1
	lda #$F8                  ; hl = $FFF8, de = $0010, c = 4
	sta tmp_04
	lda #$FF
	sta tmp_04+1
	ldx #$04
	ldy #OB_VX+2              ; bit 7,(ix+9)
	lda (zg_obj),y
	bpl fl_left
	lda #$28                  ; Vx < 0 (lot w lewo): hl = $0028, c = 0
	sta tmp_04
	lda #$00
	sta tmp_04+1
	ldx #$00
fl_left                         ; @boss_is_moving_left
	lda #$10                  ; tmp_06 = de = $0010
	sta tmp_06
	lda #0
	sta tmp_06+1
	txa
	clc
	adc zs_t
	jmp draw_sprite
fl_ret
	rts

; ---------------------------------------------------------------------
; spawn_explosion (01:7A3A): spawn_object, typ $0A, pozycja bossa + losowe 0..31 (x, potem y: random_A & $1F),
; (ix+17, 22, 23) = 0, predkosci 0; efekt $01. Brak miejsca (C = 1) - nic.
; ---------------------------------------------------------------------
spawn_explosion
	jsr spawn_object
	jcs sx_ret                ; ret c
	jsr random_A
	and #$1F
	sta tmp_00                ; tmp_00 = losowe x (hi = 0)
	lda #0
	sta tmp_00+1
	jsr random_A
	and #$1F
	sta tmp_02
	lda #0
	sta tmp_02+1
	ldy #OB_X+1               ; DE = x, BC = y bossa (zg_obj)
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
	lda #$0A                  ; slot (zg_ptr): typ $0A, subpiksel x = 0
	ldy #OB_TYPE
	sta (zg_ptr),y
	lda #0
	ldy #1
	sta (zg_ptr),y
	clc
	lda tmp_00
	adc zs_de
	ldy #2
	sta (zg_ptr),y
	lda tmp_00+1
	adc zs_de+1
	iny
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y
	clc
	lda tmp_02
	adc zs_c
	ldy #5
	sta (zg_ptr),y
	lda tmp_02+1
	adc zs_b
	iny
	sta (zg_ptr),y
	lda #0
	ldy #17
	sta (zg_ptr),y
	ldy #22
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	ldy #7
sx_z
	sta (zg_ptr),y            ; +7..+12 = 0
	iny
	cpy #13
	bne sx_z
	lda #$01                  ; rst $28
	jmp play_sfx
sx_ret
	rts

; ---------------------------------------------------------------------
; midtick_irq: IRQ w srodku ticku obiektu (oryginal: res 0 iy_00 / wait_until_irq_ticked ze skutkami @fn_update_screen:
; tablica sprite'ow wyslana - g_prev_sprite_count, lata kafli; potem odczyt kontrolera i random_A) i przywrocenie
; licznika sprite'ow. IRQ ustawia iy_00 b0 z powrotem.
; ---------------------------------------------------------------------
midtick_irq
	lda g_sprite_count
	pha
	lda iy_00
	and #$02                  ; upload_sprite_table_IRQ (iy_00 b1): licznik 0 - bez zmian
	beq mi_noup
	lda g_sprite_count
	beq mi_noup
	sta g_prev_sprite_count
	lda #0
	sta g_sprite_count
mi_noup
	jsr midtick_patch         ; 00:0162: lata ekranu zgloszona w tym ticku (irq_tile_patch lezy w kodzie pod $4100)
	jsr irq_extra             ; kontroler -> g_inputs_player_1, licznik IRQ kroku, random_A
	lda iy_00
	ora #$01                  ; set 0,(iy+iy_00) na koncu update_screen
	sta iy_00
	pla
	sta g_sprite_count
	rts
; ---------------------------------------------------------------------
; art_load_common: wspolna czesc load_art grafiki obiektow (boss, zwierzeta): kafle ikon monitorow $5C-$5F = grafika
; obiektow (v_monk = $FD - ani ikona, ani strefa: bez kopiowania), IRQ w trakcie dekompresji (gdy iy_09 b1 = 0;
; irq_extra), stan tmp_* jak po load_art (tmp_04 = adres grafiki w slocie 1, tmp_06 = + 8, tmp_00 = adres + slowo +4,
; tmp_02 = slowo +6 naglowka; stale z tools/extract_sms.py: BOSS_TMP00/02, CAPS_TMP00/02). v_art_req: 1 - boss, 2 - zwierzeta.
; ---------------------------------------------------------------------
ART_BOSS_SMS = $6EB1      ; ART_09_AEB1 po load_art (slot 1: bank $0B + $2EB1 -> $6EB1)
ART_CAPS_SMS = $5A28      ; ART_0C_DA28 po load_art (bank $0F + $1A28 -> $5A28)
ART_BOSS3_SMS = $6508     ; M6.6: ART_0C_E508 po load_art (bank $0C + $2508 -> $6508 w slocie 1)
ART_ROBO_SMS = $6F3F      ; M6.9: ART_0C_EF3F po load_art (bank $0C + $2F3F -> $6F3F w slocie 1)
art_load_common
	ldx #15
	lda #$FD
alc_mk
	sta v_monk,x
	dex
	bpl alc_mk
	lda #1
	sta v_mondirty
	lda iy_09
	and #$02
	beq alc_ei
	jsr irq_extra             ; M6.8: iy_09 b1 = 1 (boss LAB3 02:928D, zwierzeta w LAB3): dekompresja z wylaczonymi przerwaniami
	lda v_tv                  ; - po ei (00:04F3) jedno zalegle przerwanie ramki (Mesen: m68-lab3-boss, krok 34: 2 IRQ, przed Sonikiem);
	bne alc_tmp               ; NTSC (ramka krotsza): przy grafice bossa (v_art_req = 3) tick dluzszy - jeszcze jedno (m68-lab3-boss-ntsc:
	lda v_art_req             ; 3 IRQ), przy mniejszej grafice zwierzat (2) nie (m68-lab3-boss-smierc-ntsc, krok 571: 2 IRQ)
	cmp #3
	bne alc_tmp
	jsr irq_extra
	jmp alc_tmp
alc_ei
	ldx v_art_req
	lda v_tv                  ; 1 = PAL
	bne alc_pal
	inx                       ; NTSC: wpisy 5-8 tablicy (M6.9: 4 rodzaje grafiki)
	inx
	inx
	inx
alc_pal
	lda art_irq_tab-1,x
	tax
	beq alc_tmp
alc_irq
	jsr irq_extra             ; zachowuje X
	dex
	bne alc_irq
alc_tmp
	lda iy_09                 ; koniec load_art (00:04F4): res 1,(iy+iy_09)
	and #$FD
	sta iy_09
	lda v_art_req
	cmp #1
	jeq alc_boss
	cmp #3
	jeq alc_boss3
	cmp #4
	beq alc_robo
	lda #<[ART_CAPS_SMS+CAPS_TMP00]
	sta tmp_00
	lda #>[ART_CAPS_SMS+CAPS_TMP00]
	sta tmp_00+1
	lda #<CAPS_TMP02
	sta tmp_02
	lda #>CAPS_TMP02
	sta tmp_02+1
	lda #<ART_CAPS_SMS
	sta tmp_04
	lda #>ART_CAPS_SMS
	sta tmp_04+1
	lda #<[ART_CAPS_SMS+8]
	sta tmp_06
	lda #>[ART_CAPS_SMS+8]
	sta tmp_06+1
	rts
alc_robo                        ; M6.9: ART_0C_EF3F (Robotnik)
	lda #<[ART_ROBO_SMS+ROBO_TMP00]
	sta tmp_00
	lda #>[ART_ROBO_SMS+ROBO_TMP00]
	sta tmp_00+1
	lda #<ROBO_TMP02
	sta tmp_02
	lda #>ROBO_TMP02
	sta tmp_02+1
	lda #<ART_ROBO_SMS
	sta tmp_04
	lda #>ART_ROBO_SMS
	sta tmp_04+1
	lda #<[ART_ROBO_SMS+8]
	sta tmp_06
	lda #>[ART_ROBO_SMS+8]
	sta tmp_06+1
	rts
alc_boss3                       ; M6.6: ART_0C_E508 (boss BRI3)
	lda #<[ART_BOSS3_SMS+BOSS3_TMP00]
	sta tmp_00
	lda #>[ART_BOSS3_SMS+BOSS3_TMP00]
	sta tmp_00+1
	lda #<BOSS3_TMP02
	sta tmp_02
	lda #>BOSS3_TMP02
	sta tmp_02+1
	lda #<ART_BOSS3_SMS
	sta tmp_04
	lda #>ART_BOSS3_SMS
	sta tmp_04+1
	lda #<[ART_BOSS3_SMS+8]
	sta tmp_06
	lda #>[ART_BOSS3_SMS+8]
	sta tmp_06+1
	rts
alc_boss
	lda #<[ART_BOSS_SMS+BOSS_TMP00]
	sta tmp_00
	lda #>[ART_BOSS_SMS+BOSS_TMP00]
	sta tmp_00+1
	lda #<BOSS_TMP02
	sta tmp_02
	lda #>BOSS_TMP02
	sta tmp_02+1
	lda #<ART_BOSS_SMS
	sta tmp_04
	lda #>ART_BOSS_SMS
	sta tmp_04+1
	lda #<[ART_BOSS_SMS+8]
	sta tmp_06
	lda #>[ART_BOSS_SMS+8]
	sta tmp_06+1
	rts
art_irq_tab                     ; IRQ w trakcie load_art: [boss, zwierzeta, boss BRI3, Robotnik] PAL, NTSC (z referencji Mesena)
	dta b(ART_BOSS_IRQ, ART_CAPS_IRQ, ART_BOSS3_IRQ, ART_ROBO_IRQ, ART_BOSS_IRQ_N, ART_CAPS_IRQ_N, ART_BOSS3_IRQ_N, ART_ROBO_IRQ_N)
; M6.5: SPRTAB_round_bumper_throbbing (01:526E): okragly zderzak etapu specjalnego, 2 wiersze po 4 sprite'y 8x16
map_bumper_throb
	dta b($00,$02,$04,$06,$FF,$FF,$20,$22,$24,$26,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF)

