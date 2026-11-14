; =====================================================================
;  obj/objz3_sky_boss.asm - M6.10 Sky Base: boss SKY3 - $4A Robotnik za szyba, $46 zappery pionowe, $47 kula elektryczna
;  M6.10: kod w trzecim banku obiektow strefy PB_OBJZ3 (bank 30, tylko Sky Base; obj/objz3.asm) - dane banku 2 ROM-u pod adresem
;  SMS - OZ_OFF jak w PB_OBJZ2 (zakresy OBJZ3_SPANS w tools/extract_sms.py, stale OZ3_* w objdata.inc).
;  (bank obiektow strefy 3 PB_OBJZ3, bank 30, okno $4000-$7FFF; dolaczany z game.asm w sekcji banku 30).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny):
;   objfunc_4A_SKY3_boss                  02:B634 - 02:BA1A  -> objfunc_4A_sky3_boss (+ sk4a_damage = @fn_update_damage 02:B7E6,
;                                                               sk4a_anim = @fn_update_main_anim 02:B99F, sk4a_ball =
;                                                               @fn_spawn_electric_ball_at_fixed_pos 02:B9D5)
;   UNUSED_0BA1B                          02:BA1B             (samo ret - pominiete)
;   LUT_robotnik_main_anim                02:BA1C - 02:BA27   3 x (dx, dy, mapa): (0, 0, $BAF9) stoi, (0, 2, $BB0B), (0, 7, $BB0B) - kucniecie
;   LUT_robotnik_running_anim             02:BA28 - 02:BA30   (3, 8), (4, 7), (5, 8), (4, 7), $FF - klatki biegu (baza $BAF9)
;   SKY3_boss_spritespec_button_up        02:BA31 - 02:BA3A   tmp_00..tmp_07 ($0430, $01A0, 0, 0) + kafle $20 $22
;   SKY3_boss_spritespec_button_pressed   02:BA3B - 02:BA44   jw. + kafle $24 $26
;   LUT_SKY3_boss_glass_crack_tile_anim   02:BA45 - 02:BAF8   15 x 12 B: x, y (slowa), 4 slowa nazw VDP (lata 2 x 2 kafle)
;   SPRTAB_robotnik_idling (+ klatki 1-6) 02:BAF9 - 02:BB76   (wspolne ze scenka SBZ3 $22 - OZ3_SPAN14 $BAF9-$BB64)
;   SPRTAB_SKY3_boss_teleporting          02:BB77 - 02:BB83
;   objfunc_46_SKY3_vertical_zappers      02:BB84 - 02:BCC6  -> objfunc_46_sky3_zappers (+ sk46_pair = @fn_draw_sprite_pair 02:BCA5)
;   LUT_SKY3_vertical_zapper_vzap_sprites 02:BCC7 - 02:BCDC   (kafle par luku: $36 $38 / $56 $58 na przemian, 22 B)
;   LUT_SKY3_vertical_zapper_track_ball_sprites 02:BCDD - 02:BCDE (kafle kul torow $40 $42)
;   objfunc_47_SKY3_electric_ball         02:BCDF - 02:BDC6  -> objfunc_47_sky3_eball
;   LUT_SKY3_electric_ball_anim           02:BDC7 - 02:BDCD   (0, 1), (1, 1), (2, 1), $FF
;   SPRTAB_SKY3_electric_ball             02:BDCE - 02:BDF8   (klatki co 18 B: $BDCE, $BDE0, $BDF2)
;  Dane banku 2 ROM-u leza w tym banku pod adresem SMS - OZ_OFF (zakresy OZ3_SPAN* w objdata.inc; tools/extract_sms.py OBJZ3_SPANS -
;  dla SKY3: $BA1C-$BB83, $BCC7-$BCDE, $BDC7-$BDF8 - tools/extract_sms.py OBJZ3_SPANS); kod czyta je przez
;  "ETYKIETA-OZ_OFF", a do rekordow (mapa ix+15/16) i do g_screen_tile_replace_data_ptr trafiaja adresy SMS ($BAF9, $BA49...) -
;  mapy kopiuje objz_mapcopy z banku v_pbobjz, dane laty szyby czyta glass_read z tego banku (render/rings.asm; opis przy sk4a_run).
;  Wolane: kod tego banku (oz3_dfa = do_framed_animation 01:7C41, obj/objz3.asm), kod rezydentny $8000+ (spawn_object 01:7C7B,
;  damage_sonic 00:35FD, play_music = rst $18, play_sfx = rst $28 - game/objcom.asm; obj_tile_ptr = get_obj_level_tile_ptr_in_ram
;  00:36F9 - game/motion.asm) i stuby zc_* do banku 45 (game/objcom.asm): zc_mlc (move_locked_camera_towards_target 01:7CA6),
;  zc_slc (set_locked_camera_target 01:7C8C: zs_hl = cel X, zs_de = cel Y), zc_dspr (draw_sprite 00:3581: A = kafel, tmp_00/02 =
;  x/y, tmp_04/06 = przesuniecia), zc_collide (check_collision_with_sonic 00:3956: C = 1 brak trafienia), zc_robotart (load_art
;  ART_0C_EF3F -> robot_load_art, v_art_req = 4).
;  Flagi bloku przed Robotnikiem (02:B8CD: ld hl,LVTILEFLAGS_SKY_3 00:3F28 - tablica czytana WPROST, bez g_tile_flags_index): w porcie
;  TILEFLAGS_RAM (kernel/mem.inc, 256 B od PTRLUT_level_tile_flags[g_tile_flags_index]) - w SKY3 g_tile_flags_index = 7, wiec to
;  ta sama tablica (LB_TILEFLAGS = 256 B od 00:3F28, takze bajty za 104 blokami strefy).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl, A/C pomocniczo zg_a, zg_off; tmp_00..tmp_07 = zmienne SMS.
;  Przeniesienie: Z80 C = 1 po sbc (pozyczka) <=> 6502 C = 0. draw_sprite (bank 45) niszczy A, X, zd_x/zd_y/zd_r (= zs_hl, zs_de,
;  zs_b) - zg_* i tmp_* zostaja.
; =====================================================================
; adresy SMS danych (bank 2 ROM-u; w tym banku pod adresem - OZ_OFF)
SK4A_MAIN_ANIM  = $BA1C   ; LUT_robotnik_main_anim: 3 x 4 B (dx, dy, mapa slowo)
SK4A_RUN_ANIM   = $BA28   ; LUT_robotnik_running_anim: pary (klatka, czas), $FF
SK4A_BTN_UP     = $BA31   ; SKY3_boss_spritespec_button_up (10 B: 8 B tmp_00..tmp_07, 2 kafle)
SK4A_BTN_DN     = $BA3B   ; SKY3_boss_spritespec_button_pressed (= SK4A_BTN_UP + 10)
SK4A_GLASS      = $BA45   ; LUT_SKY3_boss_glass_crack_tile_anim: 15 x 12 B
SK4A_SPR_IDLE   = $BAF9   ; SPRTAB_robotnik_idling (= SPR_ROBO_IDLE scenki SBZ3): baza map Robotnika, klatka = 18 B
SK4A_SPR_JUMP   = $BB1D   ; SPRTAB_SKY3_boss_jumping (skok / opadanie)
SK4A_SPR_TELE   = $BB77   ; SPRTAB_SKY3_boss_teleporting (sam wiersz 2: kafle $44 $46 w x + 8, y + 16)
SK46_VZAP       = $BCC7   ; LUT_SKY3_vertical_zapper_vzap_sprites (22 B)
SK46_BALLS      = $BCDD   ; LUT_SKY3_vertical_zapper_track_ball_sprites ($40, $42)
SK47_ANIM       = $BDC7   ; LUT_SKY3_electric_ball_anim
SK47_SPR        = $BDCE   ; SPRTAB_SKY3_electric_ball (klatki 0-2)

; ---------------------------------------------------------------------
; objfunc_4A_SKY3_boss (02:B634): Robotnik w szklanej kabinie (obiekt (1056, 352)), 30 x 47 ((ix+13/14) co tick); co tick set 5
; (bez kolizji z mapa; w ucieczce res 5 - Robotnik biegnie po podlodze).
; Walka ((ix+24) b2 = 0): co tick zc_mlc i sk4a_damage (trafienie bez kolizji z bossem: Sonic w kuli albo skoku i sonic_x >= $0410).
;  Pierwszy tick (b0 = 0): cel kamery ($0350, $0120) (zc_slc: granice x0 = x1 = kamera X, y0 = y1 = kamera Y), x + 8 i y + $10
;  (zapamietane jako baza w (ix+17/18), (ix+19/20)), trafienia = 0, muzyka $0D, set 4 iy_08 (walka - czytaja $46 i $47), set 0.
;  Stan (ix+21): 0 - animacja jalowa (sk4a_anim co tick), co 8 tickow (ix+22) + 1 (do $28 = 40 krokow), w tym (ix+23) 0/1 na przemian
;     (gdy (ix+22) < $1C, potem 0); 1 - start skoku: Vy = $FFFE40, x = baza + 4, mapa skoku; 2 - lot: Vy + $0E (24 bit, maks. $0200
;     gdy dodatnia), az y - 1 >= baza y: y = baza, Vy = 0, (ix+22) = 0; 3 - przycisk: x = baza, w pierwszym ticku ((ix+22) = 0) kula
;     $47 (sk4a_ball), (ix+23) = 2 (kucniecie), set 1 (przycisk wcisniety), 18 tickow, potem res 1 i stan 0.
;  Zawsze: przycisk (2 x draw_sprite: kafle $20 $22 / $24 $26 wg b1) w ($0430, $01A0), x + 8 drugi. Trafienia >= 12: (ix+17) = 0
;  (licznik laty szyby), (ix+22) = (ix+23) = 0, set 2, res 4 iy_08, muzyka $04, SFX $21.
; Ucieczka (b2 = 1, sk4a_run): patrz opis przy sk4a_run.
; Pola rekordu: (ix+17/18) baza x (w ucieczce: (ix+17) licznik laty 0..15, potem $05E0), (ix+19/20) baza y, (ix+21) stan,
; (ix+22/23) liczniki animacji, (ix+24) b0 init, b1 przycisk, b2 ucieczka, b3 teleport, b5 bez kolizji z mapa, b7 na ziemi.
; ---------------------------------------------------------------------
objfunc_4A_sky3_boss
	ldy #OB_W                 ; 02:B634: ld (ix+13),$1E / ld (ix+14),$2F - 30 x 47
	lda #$1E
	sta (zg_obj),y
	iny
	lda #$2F
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:B63C: set 5,(ix+24) - bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$04                  ; 02:B640: bit 2,(ix+24) / jp nz @start_robotnik_running_away
	jne sk4a_run
	jsr zc_mlc                ; 02:B647: call move_locked_camera_towards_target
	jsr sk4a_damage           ; 02:B64A: call @fn_update_damage
	ldy #OB_FLAGS             ; 02:B64D: bit 0,(ix+24) / jr nz @already_initialised
	lda (zg_obj),y
	and #$01
	jne sk4a_inited
	lda #<$0350               ; 02:B653: ld hl,$0350 / ld de,$0120 / call set_locked_camera_target
	sta zs_hl
	lda #>$0350
	sta zs_hl+1
	lda #<$0120
	sta zs_de
	lda #>$0120
	sta zs_de+1
	jsr zc_slc
	ldy #OB_X+1               ; 02:B65C: hl = x + $0008; (ix+2/3) = hl, (ix+17/18) = hl - baza x
	clc
	lda (zg_obj),y
	adc #<$0008
	sta (zg_obj),y
	ldy #17
	sta (zg_obj),y
	ldy #OB_X+2               ; (ldy / sta nie zmieniaja C - przeniesienie z mlodszego bajtu)
	lda (zg_obj),y
	adc #>$0008
	sta (zg_obj),y
	ldy #18
	sta (zg_obj),y
	ldy #OB_Y+1               ; 02:B672: hl = y + $0010; (ix+5/6) = hl, (ix+19/20) = hl - baza y
	clc
	lda (zg_obj),y
	adc #<$0010
	sta (zg_obj),y
	ldy #19
	sta (zg_obj),y
	ldy #OB_Y+2
	lda (zg_obj),y
	adc #>$0010
	sta (zg_obj),y
	ldy #20
	sta (zg_obj),y
	lda #0                    ; 02:B688: xor a / ld (g_boss_hits_taken),a
	sta g_boss_hits_taken
	lda #$0D                  ; 02:B68C: ld a,$0D / rst $18 - muzyka bossa
	jsr play_music
	lda iy_08_lvflag03        ; 02:B68F: set 4,(iy+iy_08_lvflag03) - walka z bossem SKY3 (czytaja $46, $47)
	ora #$10
	sta iy_08_lvflag03
	ldy #OB_FLAGS             ; 02:B693: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y

sk4a_inited                     ; 02:B697 @already_initialised: ld a,(ix+21) / and a / jp nz @not_state_00
	ldy #21
	lda (zg_obj),y
	jne sk4a_not0
	; --- stan 0: Robotnik stoi (animacja jalowa) ---
	jsr sk4a_anim             ; 02:B69E: call @fn_update_main_anim
	lda g_global_tick_counter ; 02:B6A1: and $07 / jp nz @continue_after_state_execution - krok co 8 tickow
	and #$07
	jne sk4a_cont
	ldy #22                   ; 02:B6A9: ld a,(ix+22) / cp $1C / jr nc @s00_skip_to_ix23_00
	lda (zg_obj),y
	cmp #$1C
	bcs sk4a_s0z
	iny                       ; 02:B6B0: inc (ix+23) / ld a,(ix+23) / cp $02 / jp c @s00_skip_setting_ix23_00
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$02
	bcc sk4a_s0k
sk4a_s0z                        ; 02:B6BB @s00_skip_to_ix23_00: ld (ix+23),$00 - (ix+23) = 0, 1, 0, 1... (od $1C stale 0)
	lda #0
	ldy #23
	sta (zg_obj),y
sk4a_s0k                        ; 02:B6BF @s00_skip_setting_ix23_00: inc (ix+22) / cp $28 / jp c @continue...
	ldy #22
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$28
	jcc sk4a_cont
	lda #0                    ; 02:B6CA: ld (ix+22),$00 / inc (ix+21) - stan 1
	sta (zg_obj),y
	ldy #21
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	jmp sk4a_cont             ; 02:B6D1: jp @continue_after_state_execution

sk4a_not0                       ; 02:B6D4 @not_state_00 (A = stan >= 1): dec a / jr nz @not_state_01_robotnik_jump_start
	cmp #1
	bne sk4a_not1
	; --- stan 1: start skoku ---
	ldy #OB_VY                ; 02:B6D7: (ix+10) = $40, (ix+11) = $FE, (ix+12) = $FF - Vy = -1,75 px/tick
	lda #$40
	sta (zg_obj),y
	iny
	lda #$FE
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	ldy #21                   ; 02:B6E3: inc (ix+21) - stan 2
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	lda #$04                  ; 02:B6E6: hl = (ix+17/18) + $0004 -> (ix+2/3) - x = baza + 4
	jsr sk4a_setx
	jsr sk4a_mapjump          ; 02:B6F6: (ix+15/16) = SPRTAB_SKY3_boss_jumping
	jmp sk4a_cont             ; 02:B6FE: jp @continue_after_state_execution

sk4a_not1                       ; 02:B701 @not_state_01_robotnik_jump_start: dec a / jp nz @not_state_02
	cmp #2
	bne sk4a_not2
	; --- stan 2: lot / opadanie do bazy ---
	jsr sk4a_grav             ; 02:B705-02:B726: Vy + $00000E, ograniczenie do $0200 przy dodatniej, zapis (ix+10..12)
	jsr sk4a_mapjump          ; 02:B729: (ix+15/16) = SPRTAB_SKY3_boss_jumping
	ldy #OB_Y+1               ; 02:B731: hl = y - 1 (dec hl, 16 bit)
	sec
	lda (zg_obj),y
	sbc #1
	sta zg_hl
	iny
	lda (zg_obj),y
	sbc #0
	sta zg_hl+1
	ldy #19                   ; 02:B738: de = baza y (ix+19/20); and a / sbc hl,de / jr c @continue... - y - 1 < baza: jeszcze w gorze
	lda zg_hl
	cmp (zg_obj),y
	ldy #20
	lda zg_hl+1
	sbc (zg_obj),y
	jcc sk4a_cont
	ldy #19                   ; 02:B743: (ix+5/6) = de - y = baza (subpiksel (ix+4) bez zmian)
	lda (zg_obj),y
	ldy #OB_Y+1
	sta (zg_obj),y
	ldy #20
	lda (zg_obj),y
	ldy #OB_Y+2
	sta (zg_obj),y
	lda #0                    ; 02:B749: xor a / (ix+22) = 0, Vy (ix+10..12) = 0
	ldy #22
	sta (zg_obj),y
	ldy #OB_VY
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #21                   ; 02:B756: inc (ix+21) - stan 3
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	jmp sk4a_cont             ; 02:B759: jp @continue_after_state_execution

sk4a_not2                       ; 02:B75C @not_state_02: dec a / jp nz @continue... (stan >= 4 - nic)
	cmp #3
	bne sk4a_cont
	; --- stan 3: wcisniecie przycisku ---
	lda #0                    ; 02:B760: (ix+2/3) = (ix+17/18) - x = baza
	jsr sk4a_setx
	ldy #22                   ; 02:B76C: ld a,(ix+22) / and a / call z,@fn_spawn_electric_ball_at_fixed_pos
	lda (zg_obj),y
	bne sk4a_s3nb
	jsr sk4a_ball
sk4a_s3nb
	lda #$02                  ; 02:B773: ld (ix+23),$02 - kucniecie (wpis 2 LUT_robotnik_main_anim)
	ldy #23
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:B777: set 1,(ix+24) - przycisk wcisniety
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
	jsr sk4a_anim             ; 02:B77B: call @fn_update_main_anim
	ldy #22                   ; 02:B77E: inc (ix+22) / cp $12 / jr c @continue...
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$12
	bcc sk4a_cont
	ldy #OB_FLAGS             ; 02:B788: res 1,(ix+24)
	lda (zg_obj),y
	and #$FD
	sta (zg_obj),y
	lda #0                    ; 02:B78C: xor a / (ix+21) = (ix+22) = 0 - stan 0
	ldy #21
	sta (zg_obj),y
	iny
	sta (zg_obj),y

sk4a_cont                       ; 02:B793 @continue_after_state_execution: przycisk - hl = button_up, b1 -> button_pressed
	ldx #0
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02
	beq sk4a_bup
	ldx #SK4A_BTN_DN-SK4A_BTN_UP
sk4a_bup                        ; 02:B79F @big_button_not_currently_pressed: ld de,tmp_00 / ldi x 8 - tmp_00..tmp_07 z danych
	stx zg_off                ; (zg_off - poczatek specyfikacji; draw_sprite go nie zmienia)
	ldy #0
sk4a_bcp
	lda SK4A_BTN_UP-OZ_OFF,x
	sta tmp_00,y              ; tmp_00 = x $0430, tmp_02 = y $01A0, tmp_04 = tmp_06 = 0
	inx
	iny
	cpy #8
	bne sk4a_bcp
	ldx zg_off                ; 02:B7B2: ld a,(hl) / inc hl / push hl / call draw_sprite - lewa polowka przycisku (kafel $20 / $24)
	lda SK4A_BTN_UP+8-OZ_OFF,x
	jsr zc_dspr
	clc                       ; 02:B7B8: ld hl,(tmp_04) / ld de,$0008 / add hl,de / ld (tmp_04),hl
	lda tmp_04
	adc #<$0008
	sta tmp_04
	lda tmp_04+1
	adc #>$0008
	sta tmp_04+1
	ldx zg_off                ; 02:B7C2: pop hl / ld a,(hl) / call draw_sprite - prawa polowka (kafel $22 / $26)
	lda SK4A_BTN_UP+9-OZ_OFF,x
	jsr zc_dspr
	lda g_boss_hits_taken     ; 02:B7C7: ld a,(g_boss_hits_taken) / cp $0C / ret c
	cmp #$0C
	bcc sk4a_ret
	lda #0                    ; 02:B7CD: xor a / (ix+17) = (ix+22) = (ix+23) = 0
	ldy #17
	sta (zg_obj),y
	ldy #22
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:B7D7: set 2,(ix+24) - ucieczka
	lda (zg_obj),y
	ora #$04
	sta (zg_obj),y
	lda iy_08_lvflag03        ; 02:B7DB: res 4,(iy+iy_08_lvflag03) - koniec walki ($46 bez luku, $47 znika)
	and #$EF
	sta iy_08_lvflag03
	lda #$04                  ; 02:B7DF: ld a,$04 / rst $18 - muzyka poziomu (Scrap Brain)
	jsr play_music
	lda #$21                  ; 02:B7E2: ld a,$21 / rst $28 / ret
	jmp play_sfx
sk4a_ret
	rts

; ---------------------------------------------------------------------
; sk4a_damage = @fn_update_damage (02:B7E6): bez migania palety (g_pal_flash_countdown_timer = 0), Sonic zywy (iy_05 b0 = 0),
; Sonic w kuli (flagi b0) albo w powietrzu po skoku (b2) i sonic_x >= $0410 (16 bit bez znaku; nie ma testu kolizji z bossem):
; Vx Sonica = $FFFD00 (-3 px/tick), miganie palety: licznik $18, indeks $0C (kolor 12 palety tla), kolor $3F; SFX $01; trafienia + 1.
; Niszczy A.
; ---------------------------------------------------------------------
sk4a_damage
	lda g_pal_flash_countdown_timer ; 02:B7E6: ld a,(g_pal_flash_countdown_timer) / and a / ret nz
	bne sk4a_dret
	lda iy_05_lvflag00        ; 02:B7EB: bit 0,(iy+iy_05_lvflag00) / ret nz - Sonic umiera
	lsr
	bcs sk4a_dret
	lda sonic_flags_ix_24     ; 02:B7F0: rrca / jr c @sonic_is_rolling_to_damage_us (b0 - kula)
	lsr
	bcs sk4a_droll
	and #$02                  ; 02:B7F6: and $02 / ret z (po rrca b1 = b2 flag: w powietrzu po skoku)
	beq sk4a_dret
sk4a_droll                       ; 02:B7F9 @sonic_is_rolling_to_damage_us: hl = sonic_x - $0410 (and a / sbc) / ret c
	lda sonic_x
	cmp #<$0410
	lda sonic_x+1
	sbc #>$0410
	bcc sk4a_dret
	lda #$00                  ; 02:B803: ld hl,$FD00 / ld a,$FF / (sonic_vel_x_sub) = hl, (sonic_vel_x_hi) = a - Vx = $FFFD00
	sta sonic_vel_x_sub
	lda #$FD
	sta sonic_vel_x
	lda #$FF
	sta sonic_vel_x_hi
	lda #$18                  ; 02:B80E: g_pal_flash_countdown_timer = $18, g_pal_flash_idx = $0C, g_pal_flash_color_value = $3F
	sta g_pal_flash_countdown_timer
	lda #$0C
	sta g_pal_flash_idx
	lda #$3F
	sta g_pal_flash_color_value
	lda #$01                  ; 02:B819: ld a,$01 / rst $28 - odglos trafienia
	jsr play_sfx
	inc g_boss_hits_taken     ; 02:B81C: ld hl,g_boss_hits_taken / inc (hl) / ret
sk4a_dret
	rts

; ---------------------------------------------------------------------
; sk4a_run = @start_robotnik_running_away (02:B821): Robotnik pokonany ((ix+24) b2 = 1). b3 = 1 -> sk4a_exit (teleport).
;  res 5 (kolizje z mapa wlaczone). Pekanie szyby: (ix+17) = k < 15 -> lata k z LUT_SKY3_boss_glass_crack_tile_anim (12 B: x, y,
;  4 slowa nazw VDP) - g_screen_tile_replace_x = x, _y = y, _data_ptr = $BA45 + 12k + 4 (adres SMS, bank 2) - IRQ nastepnej ramki
;  (00:0162 -> apply_screen_tilemap_patch 00:38B0) kladzie 2 x 2 kafle w (x & $F8, y & $F8); k + 1; po 15. lacie: set 5 iy_00
;  (kamera znow sie przewija), res 1 iy_02, g_level_limit_x1 = $0550 (jak boss_generic 01:78FF).
;  PORT: irq_tile_patch -> glass_read / glass_req (render/rings.asm, game/rings.asm) - lata do slotu magazynu bloku (render/frame.asm
;  glass_store, priorytet blokow z magazynu); format danych:
;  dane szyby: wskaznik $BA49 + 12k (k = 0..14, ostatni $BAF1..$BAF8), 8 B w PB_OBJZ3 pod wskaznik - OZ_OFF; slowa $10nn (kafel nn
;  atlasu tla SKY3, b4 = priorytet nad sprite'ami, paleta tla, bez odbic) albo $0000 (kafel 0 - pusty, bez priorytetu).
;  Ruch: x > $05E0 -> Vx = 0; inaczej Vx = (Vx sub Sonica, Vx lo Sonica + 1, 0), gdy Sonic nie leci w lewo (b7 Vx lo = 0)
;  i 0 <= x - sonic_x < $40 (16 bit bez znaku), w pozostalych przypadkach Vx = $000080 (0,5 px/tick).
;  Skok 1: (ix+23) = 6, (ix+22) = 1 (para (4, 7) animacji biegu - po oz3_dfa z poprzedniego ticku) i na ziemi -> Vy = $FFFF00.
;  Skok 2: blok pod (x + $36, y + $17) ma flagi & $3F != 0 (LVTILEFLAGS_SKY_3 = TILEFLAGS_RAM) i na ziemi -> Vy = $FFFD80.
;  Teleporter: blok pod (x + 8, y) = $49 i na ziemi -> (ix+22) = (ix+23) = 0, Vx = 0, baza = ($05E0, $0160), cel kamery ($0550,
;  $0120) (zc_slc), set 3, sk4a_exit w tym samym ticku. Inaczej: grawitacja (sk4a_grav), animacja biegu (oz3_dfa: sekwencja
;  LUT_robotnik_running_anim, baza SPRTAB_robotnik_idling - klatki 3, 4, 5 = $BB2F, $BB41, $BB53).
; ---------------------------------------------------------------------
sk4a_run
	lda (zg_obj),y            ; 02:B821: bit 3,(ix+24) / jp nz @suppress_inputs_and_let_robotnik_exit (Y = OB_FLAGS)
	and #$08
	jne sk4a_exit
	lda (zg_obj),y            ; 02:B828: res 5,(ix+24) - Robotnik biegnie po podlodze (kolizje z mapa)
	and #$DF
	sta (zg_obj),y
	ldy #17                   ; 02:B82C: ld a,(ix+17) / cp $0F / jr nc @skip_end_of_glass_crack_anim
	lda (zg_obj),y
	cmp #$0F
	jcs sk4a_noglass
	asl                       ; 02:B833: add a,a / add a,a / ld e,a / add a,a / add a,e - a = 12 * k (8 bit, k <= 14)
	asl
	sta zg_a                  ; e = 4k
	asl
	clc
	adc zg_a
	tax                       ; X = 12k (hl = LUT + de)
	lda SK4A_GLASS-OZ_OFF,x   ; 02:B83F: de = (hl) / ld (g_screen_tile_replace_x),de - x laty
	sta g_screen_tile_replace_x
	lda SK4A_GLASS+1-OZ_OFF,x
	sta g_screen_tile_replace_x+1
	lda SK4A_GLASS+2-OZ_OFF,x ; 02:B847: de = (hl + 2) / ld (g_screen_tile_replace_y),de - y laty
	sta g_screen_tile_replace_y
	lda SK4A_GLASS+3-OZ_OFF,x
	sta g_screen_tile_replace_y+1
	txa                       ; 02:B84F: ld (g_screen_tile_replace_data_ptr),hl - hl = $BA45 + 12k + 4 (adres SMS - jak oryginal)
	clc
	adc #<[SK4A_GLASS+4]
	sta g_screen_tile_replace_data_ptr
	lda #>[SK4A_GLASS+4]
	adc #0
	sta g_screen_tile_replace_data_ptr+1
	ldy #17                   ; 02:B852: inc (ix+17) / ld a,(ix+17) / cp $0F / jr nz @skip_end_of_glass_crack_anim
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$0F
	bne sk4a_noglass
	lda iy_00                 ; 02:B85C: set 5,(iy+iy_00) - kamera znow sie przesuwa
	ora #$20
	sta iy_00
	lda iy_02                 ; 02:B860: res 1,(iy+iy_02)
	and #$FD
	sta iy_02
	lda #<$0550               ; 02:B864: ld hl,$0550 / ld (g_level_limit_x1),hl
	sta g_level_limit_x1
	lda #>$0550
	sta g_level_limit_x1+1
sk4a_noglass                    ; 02:B86A @skip_end_of_glass_crack_anim: hl = $05E0 - x (xor a / sbc hl,de) / jr nc @x_not_at_teleporter
	ldy #OB_X+1
	sec
	lda #<$05E0
	sbc (zg_obj),y
	iny
	lda #>$05E0
	sbc (zg_obj),y
	bcs sk4a_nottp
	lda #0                    ; 02:B878: x > $05E0: ld c,a / ld b,a (a = 0) / jp @set_x_vel_and_continue - Vx = 0 (bez inc b)
	sta zg_bc
	sta zg_bc+1
	beq sk4a_setvx            ; zawsze
sk4a_nottp                      ; 02:B87D @x_not_at_teleporter: ex de,hl / de = sonic_x / xor a / sbc hl,de - hl = x - sonic_x
	ldy #OB_X+1
	sec
	lda (zg_obj),y
	sbc sonic_x
	sta zg_hl
	iny
	lda (zg_obj),y
	sbc sonic_x+1
	sta zg_hl+1
	lda sonic_vel_x_sub       ; 02:B885: ld de,$0040 / xor a / ld bc,(sonic_vel_x_sub): c = Vx sub Sonica, b = Vx lo (piksele)
	sta zg_bc
	lda sonic_vel_x
	sta zg_bc+1
	bmi sk4a_far              ; 02:B88D: bit 7,b / jr nz @sonic_x_vel_is_negative
	sec                       ; 02:B891: sbc hl,de (C = 0 po xor a): pozyczka (6502 C = 0) <=> x - sonic_x < $40 (bez znaku)
	lda zg_hl
	sbc #<$0040
	lda zg_hl+1
	sbc #>$0040
	bcc sk4a_close            ; 02:B893: jr c @sonic_is_close_to_me - bc = Vx Sonica
sk4a_far                        ; 02:B895 @sonic_x_vel_is_negative: ld bc,$FF80 (po inc b: Vx = $000080)
	lda #<$FF80
	sta zg_bc
	lda #>$FF80
	sta zg_bc+1
sk4a_close                      ; 02:B898 @sonic_is_close_to_me: inc b (8 bit)
	inc zg_bc+1
sk4a_setvx                      ; 02:B899 @set_x_vel_and_continue: (ix+7) = c, (ix+8) = b, (ix+9) = a (= 0 w obu drogach)
	ldy #OB_VX
	lda zg_bc
	sta (zg_obj),y
	iny
	lda zg_bc+1
	sta (zg_obj),y
	iny
	lda #0
	sta (zg_obj),y
	ldy #23                   ; 02:B8A2: ld a,(ix+23) / cp $06 / jr nz @dont_jump_type_1
	lda (zg_obj),y
	cmp #$06
	bne sk4a_nj1
	dey                       ; 02:B8A9: ld a,(ix+22) / dec a / jr nz @dont_jump_type_1
	lda (zg_obj),y
	cmp #$01
	bne sk4a_nj1
	ldy #OB_FLAGS             ; 02:B8AF: bit 7,(ix+24) / jr z @dont_jump_type_1 - tylko na ziemi
	lda (zg_obj),y
	bpl sk4a_nj1
	ldy #OB_VY                ; 02:B8B5: (ix+10) = $00, (ix+11) = $FF, (ix+12) = $FF - Vy = -1 px/tick (podskok w biegu)
	lda #$00
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	iny
	sta (zg_obj),y
sk4a_nj1                        ; 02:B8C1 @dont_jump_type_1: ld de,$0017 / ld bc,$0036 / call get_obj_level_tile_ptr_in_ram
	lda #<$0036
	sta zg_bc
	lda #>$0036
	sta zg_bc+1
	lda #<$0017
	sta zg_de
	lda #>$0017
	sta zg_de+1
	jsr obj_tile_ptr          ; zg_ptr = bajt ukladu pod (x + $36, y + $17); C = 1 - adres SMS < $C000 (ROM)
	bcs sk4a_j2rom
	ldy #0                    ; 02:B8CA: ld e,(hl) / ld d,$00 / ld hl,LVTILEFLAGS_SKY_3 / add hl,de / ld a,(hl) / and $3F
	lda (zg_ptr),y
	tax
	lda TILEFLAGS_RAM,x       ; flagi bloku strefy 7 (TILEFLAGS_RAM = 00:3F28 w SKY3 - patrz naglowek)
	and #$3F
	jmp sk4a_j2t
sk4a_j2rom                      ; adres ROM SMS (port nie ma ROM-u): typ 0 - bez skoku, v_rom_reads + 1 (jak obj_tile_type)
	inc v_rom_reads
	lda #0
sk4a_j2t                        ; 02:B8D4: and a / jr z @dont_jump_type_2
	beq sk4a_nj2
	ldy #OB_FLAGS             ; 02:B8D7: bit 7,(ix+24) / jr z @dont_jump_type_2
	lda (zg_obj),y
	bpl sk4a_nj2
	ldy #OB_VY                ; 02:B8DD: (ix+10) = $80, (ix+11) = $FD, (ix+12) = $FF - Vy = -2,5 px/tick (przeszkoda przed nim)
	lda #$80
	sta (zg_obj),y
	iny
	lda #$FD
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
sk4a_nj2                        ; 02:B8E9 @dont_jump_type_2: ld de,$0000 / ld bc,$0008 / call get_obj_level_tile_ptr_in_ram
	lda #<$0008
	sta zg_bc
	lda #>$0008
	sta zg_bc+1
	lda #0
	sta zg_de
	sta zg_de+1
	jsr obj_tile_ptr          ; zg_ptr = bajt ukladu pod (x + 8, y)
	bcs sk4a_tprom
	ldy #0                    ; 02:B8F2: ld a,(hl) / cp $49 / jr nz @dont_lock_inputs_for_teleport_cutscene
	lda (zg_ptr),y
	cmp #$49
	bne sk4a_notp
	ldy #OB_FLAGS             ; 02:B8F7: bit 7,(ix+24) / jr z @dont_lock... - na ziemi
	lda (zg_obj),y
	bpl sk4a_notp
	lda #0                    ; 02:B8FD: xor a / (ix+22) = (ix+23) = 0, Vx (ix+7..9) = 0
	ldy #22
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_VX
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #17                   ; 02:B90D: (ix+17/18) = $05E0, (ix+19/20) = $0160 - baza teleportu
	lda #$E0
	sta (zg_obj),y
	iny
	lda #$05
	sta (zg_obj),y
	iny
	lda #$60
	sta (zg_obj),y
	iny
	lda #$01
	sta (zg_obj),y
	lda #<$0550               ; 02:B91D: ld hl,$0550 / ld de,$0120 / call set_locked_camera_target
	sta zs_hl
	lda #>$0550
	sta zs_hl+1
	lda #<$0120
	sta zs_de
	lda #>$0120
	sta zs_de+1
	jsr zc_slc
	ldy #OB_FLAGS             ; 02:B926: set 3,(ix+24) / jp @suppress_inputs_and_let_robotnik_exit
	lda (zg_obj),y
	ora #$08
	sta (zg_obj),y
	jmp sk4a_exit
sk4a_tprom                      ; adres ROM SMS: jak blok inny niz $49, v_rom_reads + 1
	inc v_rom_reads
sk4a_notp                       ; 02:B92D @dont_lock_inputs_for_teleport_cutscene: grawitacja (Vy + $0E, maks. $0200)
	jsr sk4a_grav
	lda #<[SK4A_RUN_ANIM-OZ_OFF] ; 02:B951: ld bc,LUT_robotnik_running_anim (sekwencja - adres okna) / ld de,SPRTAB_robotnik_idling
	sta zg_bc                 ; (baza map - adres SMS) / call do_framed_animation / ret
	lda #>[SK4A_RUN_ANIM-OZ_OFF]
	sta zg_bc+1
	lda #<SK4A_SPR_IDLE
	sta zg_de
	lda #>SK4A_SPR_IDLE
	sta zg_de+1
	jmp oz3_dfa

; ---------------------------------------------------------------------
; sk4a_exit = @suppress_inputs_and_let_robotnik_exit (02:B95B): wejscie = $FF (blokada), sk4a_anim (pozycja = ($05E0, $0160) + wpis
; (ix+23) 0/1 - stoi). (ix+22) < $30: co 8 tickow (ix+23) = ((ix+23) + 1) & 1 i (ix+22) + 1; od (ix+22) >= $2C (stara wartosc)
; mapa SPRTAB_SKY3_boss_teleporting. (ix+22) >= $30: mapa 0 (niewidoczny), (ix+22) + 1 co tick, przy $70 obiekt usuniety ($FF).
; ---------------------------------------------------------------------
sk4a_exit
	lda #$FF                  ; 02:B95B: ld (iy+g_inputs_player_1),$FF
	sta g_inputs_player_1
	jsr sk4a_anim             ; 02:B95F: call @fn_update_main_anim
	ldy #22                   ; 02:B962: ld a,(ix+22) / cp $30 / jr nc @teleported_waiting_to_despawn
	lda (zg_obj),y
	cmp #$30
	bcs sk4a_gone
	sta zg_a                  ; 02:B969: ld c,a - stara wartosc (ix+22)
	lda g_global_tick_counter ; 02:B96A: and $07 / jr nz @ticks_not_divisible_by_8
	and #$07
	bne sk4a_x8
	iny                       ; 02:B971: (ix+23) = ((ix+23) + 1) & 1 - migotanie stoi / kucniecie
	lda (zg_obj),y
	clc
	adc #1
	and #$01
	sta (zg_obj),y
	dey                       ; 02:B97A: inc (ix+22)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
sk4a_x8                         ; 02:B97D @ticks_not_divisible_by_8: ld a,c / cp $2C / ret c
	lda zg_a
	cmp #$2C
	bcc sk4a_xret
	ldy #OB_SPRITE            ; 02:B981: (ix+15/16) = SPRTAB_SKY3_boss_teleporting / ret
	lda #<SK4A_SPR_TELE
	sta (zg_obj),y
	iny
	lda #>SK4A_SPR_TELE
	sta (zg_obj),y
sk4a_xret
	rts
sk4a_gone                       ; 02:B98A @teleported_waiting_to_despawn: xor a / (ix+15/16) = 0 - Robotnik zniknal
	lda #0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #22                   ; 02:B991: inc (ix+22) / cp $70 / ret c
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$70
	bcc sk4a_xret
	lda #$FF                  ; 02:B99A: ld (ix+0),$FF / ret - koniec obiektu
	ldy #OB_TYPE
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; sk4a_anim = @fn_update_main_anim (02:B99F): wpis (ix+23) LUT_robotnik_main_anim (indeks * 4, 8 bit): c = dx, e = dy, mapa ->
; (ix+15/16); x (ix+2/3) = (ix+17/18) + c, y (ix+5/6) = (ix+19/20) + e (b = d = 0). Niszczy A, X, Y, zg_bc, zg_de.
; ---------------------------------------------------------------------
sk4a_anim
	ldy #23                   ; 02:B99F: ld hl,LUT_robotnik_main_anim / ld a,(ix+23) / add a,a / add a,a / ld e,a / add hl,de
	lda (zg_obj),y
	asl
	asl
	tax
	lda SK4A_MAIN_ANIM-OZ_OFF,x ; 02:B9AC: ld c,(hl) - dx
	sta zg_bc
	lda SK4A_MAIN_ANIM+1-OZ_OFF,x ; ld e,(hl) - dy
	sta zg_de
	ldy #OB_SPRITE            ; 02:B9B0: hl = slowo (hl + 2) / (ix+15/16) = hl - mapa (adres SMS)
	lda SK4A_MAIN_ANIM+2-OZ_OFF,x
	sta (zg_obj),y
	iny
	lda SK4A_MAIN_ANIM+3-OZ_OFF,x
	sta (zg_obj),y
	lda zg_bc                 ; 02:B9BA: hl = (ix+17/18) + bc -> (ix+2/3)
	jsr sk4a_setx
	ldy #19                   ; 02:B9C7: hl = (ix+19/20) + de -> (ix+5/6)
	clc
	lda (zg_obj),y
	adc zg_de
	ldy #OB_Y+1
	sta (zg_obj),y
	ldy #20
	lda (zg_obj),y
	adc #0
	ldy #OB_Y+2
	sta (zg_obj),y
	rts

; sk4a_setx: x (ix+2/3) = baza x (ix+17/18) + A (8 bit bez znaku, add hl,bc / add hl,de z b = d = 0). Niszczy A, Y.
sk4a_setx
	ldy #17
	clc
	adc (zg_obj),y
	ldy #OB_X+1
	sta (zg_obj),y
	ldy #18
	lda (zg_obj),y
	adc #0
	ldy #OB_X+2
	sta (zg_obj),y
	rts

; sk4a_mapjump: (ix+15/16) = SPRTAB_SKY3_boss_jumping (02:B6F6, 02:B729). Niszczy A, Y.
sk4a_mapjump
	ldy #OB_SPRITE
	lda #<SK4A_SPR_JUMP
	sta (zg_obj),y
	iny
	lda #>SK4A_SPR_JUMP
	sta (zg_obj),y
	rts

; sk4a_grav (02:B705-02:B726 i 02:B92D-02:B94E, dwie jednakowe kopie w oryginale): hl = (ix+10/11), a = (ix+12); add hl,$000E /
; adc a,$00 / ld c,a; jp m (a < 0 - bez ograniczenia); h >= 2 -> hl = $0200 (c bez zmian); (ix+10) = l, (ix+11) = h, (ix+12) = c.
; Niszczy A, Y, zg_hl, zg_a.
sk4a_grav
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc #$0E
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	iny
	lda (zg_obj),y
	adc #0
	sta zg_a                  ; c (N z adc - jp m)
	bmi sk4a_gst
	lda zg_hl+1               ; ld a,h / cp $02 / jr c - h < 2: bez ograniczenia
	cmp #$02
	bcc sk4a_gst
	lda #<$0200               ; ld hl,$0200 - maks. 2 px/tick w dol
	sta zg_hl
	lda #>$0200
	sta zg_hl+1
sk4a_gst
	ldy #OB_VY
	lda zg_hl
	sta (zg_obj),y
	iny
	lda zg_hl+1
	sta (zg_obj),y
	iny
	lda zg_a
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; sk4a_ball = @fn_spawn_electric_ball_at_fixed_pos (02:B9D5): gdy nie ma kuli (iy_08 b5 = 0) i jest wolny slot (spawn_object):
; obiekt $47 w ($0420.00, $012F.00), (ix+17) = 0 (ladowanie), (ix+24) = 0, Vx = Vy = 0. Pozostale pola slotu (13..16, 18..23, 25)
; bez zmian - spawn_object ich nie czysci (jak oryginal; (ix+22/23) kuli to liczniki jej animacji).
; ---------------------------------------------------------------------
sk4a_ball
	lda iy_08_lvflag03        ; 02:B9D5: bit 5,(iy+iy_08_lvflag03) / ret nz - kula juz jest
	and #$20
	bne sk4a_bret
	jsr spawn_object          ; 02:B9DA: call spawn_object / ret c - brak wolnego slotu
	bcs sk4a_bret
	ldy #OB_TYPE              ; 02:B9DE: push ix / push hl / pop ix (zg_ptr = nowy slot); xor a / (ix+0) = $47, (ix+1) = 0
	lda #$47
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y
	iny                       ; 02:B9EB: ld hl,$0420 / (ix+2/3) = hl, (ix+4) = 0
	lda #<$0420
	sta (zg_ptr),y
	iny
	lda #>$0420
	sta (zg_ptr),y
	iny
	lda #0
	sta (zg_ptr),y
	iny                       ; 02:B9F7: ld hl,$012F / (ix+5/6) = hl
	lda #<$012F
	sta (zg_ptr),y
	iny
	lda #>$012F
	sta (zg_ptr),y
	lda #0                    ; 02:BA00: (ix+17) = 0, (ix+24) = 0, (ix+7..12) = 0 (a = 0)
	ldy #17
	sta (zg_ptr),y
	ldy #OB_FLAGS
	sta (zg_ptr),y
	ldy #OB_VX
sk4a_bz
	sta (zg_ptr),y
	iny
	cpy #OB_VY+3
	bne sk4a_bz
sk4a_bret                        ; 02:BA18: pop ix / ret
	rts

; ---------------------------------------------------------------------
; objfunc_46_SKY3_vertical_zappers (02:BB84): dwie kule torow zappera (y $011A i $01D2, x = $0390 + (ix+17), kafle $40 $42 co 8 px)
; i pionowy luk elektryczny miedzy nimi. Co tick set 5 (bez kolizji z mapa), cel granicy kamery y0 = $0008.
; Pierwszy tick (b0 = 0): load_art ART_0C_EF3F -> kafle sprite'ow $00-$7F (zc_robotart: grafika Robotnika, przycisku, zapperow
; i kuli; v_art_req = 4, IRQ w trakcie - bez set 1 iy_09, jak scenka SBZ3), (ix+18) = 1, set 0.
; Bez walki (iy_08 b4 = 0) - same kule torow. W walce przy b1 (luk) tylko w parzystym ticku (nieparzysty - ret): 10 par sprite'ow
; luku (kafle z LUT_SKY3_vertical_zapper_vzap_sprites + (tick & 2)) od y $0130 co 16 px (z kulami torow do 24 draw_sprite na tick),
; Sonic w pasie $0390 + (ix+17) - $0E <= sonic_x <= $0390 + (ix+17) + $0C (16 bit) i zywy -> damage_sonic.
; Faza 1 (trafienia < 6): bez luku (ix+17) + 1 co tick; od $80 w parzystym ticku set 1; z lukiem (ix+17) - 1 (co drugi tick),
;  SFX $13 co 16 tickow, przy 0 res 1. Faza 2 (>= 6): co tick (b1 = 1 - co drugi) zapper w strone Sonica (sonic_x wzgledem x
;  OBIEKTU (ix+2/3), nie zappera): (ix+17) + 1 do $80 albo - 1 do 0; res 1; luk (set 1), gdy tick & $40 = 0 i trafienia != 6
;  (SFX $13, gdy tick & $1F = 0).
; ---------------------------------------------------------------------
objfunc_46_sky3_zappers
	ldy #OB_FLAGS             ; 02:BB84: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #<$0008               ; 02:BB88: ld hl,$0008 / ld (g_camera_sonic_bounds_y0_target),hl
	sta g_camera_sonic_bounds_y0_target
	lda #>$0008
	sta g_camera_sonic_bounds_y0_target+1
	lda (zg_obj),y            ; 02:BB8E: bit 0,(ix+24) / jr nz @already_initialised (Y = OB_FLAGS)
	and #$01
	bne sk46_inited
	jsr zc_robotart           ; 02:BB94: ld hl,ART_0C_EF3F / ld de,$2000 / ld a,$0C / call load_art (kafle sprite'ow $00-$7F;
	                          ; tmp_00..tmp_07 po load_art bez znaczenia - nizej wszystkie ustawiane od nowa)
	lda #$01                  ; 02:BB9F: ld (ix+18),$01
	ldy #18
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:BBA3: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
sk46_inited                     ; 02:BBA7 @already_initialised: tmp_00 = $0390, tmp_04 = (ix+17) (h = 0), tmp_06 = 0 (ld l,h)
	lda #<$0390
	sta tmp_00
	lda #>$0390
	sta tmp_00+1
	ldy #17
	lda (zg_obj),y
	sta tmp_04
	lda #0
	sta tmp_04+1
	sta tmp_06
	sta tmp_06+1
	lda #<$011A               ; 02:BBB9: ld de,$011A / ld hl,LUT_SKY3_vertical_zapper_track_ball_sprites / call @fn_draw_sprite_pair
	sta zg_de
	lda #>$011A
	sta zg_de+1
	lda #<[SK46_BALLS-OZ_OFF]
	sta zg_hl
	lda #>[SK46_BALLS-OZ_OFF]
	sta zg_hl+1
	jsr sk46_xpre             ; M7.5: x ekranu obu sprite'ow pary raz na tick (tmp_00, tmp_04 stale dla wszystkich par)
	jsr sk46_pair             ; gorna kula toru
	ldy #17                   ; 02:BBC2: ld e,(ix+17) / ld d,$00 / ld (tmp_04),de
	lda (zg_obj),y
	sta tmp_04
	lda #0
	sta tmp_04+1
	lda #<$01D2               ; 02:BBCB: ld de,$01D2 / ld hl,LUT_..._track_ball_sprites / call @fn_draw_sprite_pair
	sta zg_de
	lda #>$01D2
	sta zg_de+1
	lda #<[SK46_BALLS-OZ_OFF]
	sta zg_hl
	lda #>[SK46_BALLS-OZ_OFF]
	sta zg_hl+1
	jsr sk46_pair             ; dolna kula toru
	lda zg_de                 ; M7.5: tmp_02 = y ostatniej pary (sk46_pair go nie pisze - wartosc koncowa jak w oryginale)
	sta tmp_02
	lda zg_de+1
	sta tmp_02+1
	lda iy_08_lvflag03        ; 02:BBD4: bit 4,(iy+iy_08_lvflag03) / ret z - poza walka nic wiecej
	and #$10
	jeq sk46_ret
	ldy #OB_FLAGS             ; 02:BBD9: bit 1,(ix+24) / jr z @end_vzap_logic
	lda (zg_obj),y
	and #$02
	jeq sk46_end
	lda g_global_tick_counter ; 02:BBDF: ld a,(g_global_tick_counter) / bit 0,a / ret nz - luk tylko w parzystym ticku
	lsr
	jcs sk46_ret
	lda g_global_tick_counter ; 02:BBE5: and $02 / ld e,a / ld d,$00 / ld hl,LUT_SKY3_vertical_zapper_vzap_sprites / add hl,de
	and #$02
	clc
	adc #<[SK46_VZAP-OZ_OFF]
	sta zg_hl
	lda #>[SK46_VZAP-OZ_OFF]
	adc #0
	sta zg_hl+1
	lda #$0A                  ; 02:BBEE: ld b,$0A / ld de,$0130 - 10 par od y $0130
	sta zg_bc+1
	lda #<$0130
	sta zg_de
	lda #>$0130
	sta zg_de+1
sk46_vz                         ; 02:BBF3 @each_vzap_sprite_pair: push bc / push de / call @fn_draw_sprite_pair / pop de
	jsr sk46_pair             ; (hl + 2 po parze - nastepne kafle; de, b zachowane)
	clc                       ; 02:BBF9: push hl / ld hl,$0010 / add hl,de / ex de,hl / pop hl - de + 16
	lda zg_de
	adc #$10
	sta zg_de
	bcc sk46_vzd
	inc zg_de+1
sk46_vzd
	dec zg_bc+1               ; 02:BC00: pop bc / djnz @each_vzap_sprite_pair
	bne sk46_vz
	sec                       ; M7.5: tmp_02 = y ostatniej pary luku (zg_de - 16)
	lda zg_de
	sbc #$10
	sta tmp_02
	lda zg_de+1
	sbc #0
	sta tmp_02+1
	ldy #17                   ; 02:BC03: ld hl,$0390 / ld c,(ix+17) / ld b,$00 / add hl,bc / ld c,l / ld b,h - bc = x zappera
	clc
	lda #<$0390
	adc (zg_obj),y
	sta zg_bc
	lda #>$0390
	adc #0
	sta zg_bc+1
	clc                       ; 02:BC0E: ld hl,$000C / add hl,bc - hl = bc + 12
	lda zg_bc
	adc #<$000C
	sta zg_hl
	lda zg_bc+1
	adc #>$000C
	sta zg_hl+1
	lda zg_hl                 ; 02:BC12: ld de,(sonic_x) / and a / sbc hl,de / jr c @end_vzap_logic - Sonic za prawa krawedzia luku
	cmp sonic_x
	lda zg_hl+1
	sbc sonic_x+1
	bcc sk46_end
	clc                       ; 02:BC1B: ld hl,$000E / add hl,de - hl = sonic_x + 14
	lda sonic_x
	adc #<$000E
	sta zg_hl
	lda sonic_x+1
	adc #>$000E
	sta zg_hl+1
	lda zg_hl                 ; 02:BC1F: and a / sbc hl,bc / jr c @end_vzap_logic - Sonic przed lewa krawedzia luku
	cmp zg_bc
	lda zg_hl+1
	sbc zg_bc+1
	bcc sk46_end
	lda iy_05_lvflag00        ; 02:BC24: bit 0,(iy+iy_05_lvflag00) / call z,damage_sonic - Sonic w luku
	lsr
	bcs sk46_end
	jsr damage_sonic

sk46_end                        ; 02:BC2B @end_vzap_logic: ld a,(g_boss_hits_taken) / cp $06 / jr nc @start_part_2_logic
	lda g_boss_hits_taken
	cmp #$06
	bcs sk46_p2
	ldy #OB_FLAGS             ; 02:BC32: bit 1,(ix+24) / jr nz @pt1_do_vzap
	lda (zg_obj),y
	and #$02
	bne sk46_p1zap
	ldy #17                   ; 02:BC38: ld a,(ix+17) / inc a / ld (ix+17),a / cp $80 / ret c - zapper jedzie w prawo
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$80
	bcc sk46_ret
	lda g_global_tick_counter ; 02:BC42: ld c,a / and $01 / ret nz - set 1 tylko w parzystym ticku ((ix+17) = $80 albo $81)
	and #$01
	bne sk46_ret
	ldy #OB_FLAGS             ; 02:BC49: set 1,(ix+24) / ret - luk wlaczony
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
sk46_ret
	rts
sk46_p1zap                      ; 02:BC4E @pt1_do_vzap: ld a,(g_global_tick_counter) / and $0F / jr nz
	lda g_global_tick_counter
	and #$0F
	bne sk46_p1s
	lda #$13                  ; 02:BC55: ld a,$13 / rst $28 - trzask wyladowania
	jsr play_sfx
sk46_p1s                        ; 02:BC58 @pt1_already_playing_zap_sound: dec (ix+17) / ret nz - zapper wraca w lewo z lukiem
	ldy #17
	lda (zg_obj),y
	sec
	sbc #1
	sta (zg_obj),y
	bne sk46_ret
	lda #$00                  ; 02:BC5C: ld (ix+17),$00 / res 1,(ix+24) / ret
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$FD
	sta (zg_obj),y
	rts

sk46_p2                         ; 02:BC65 @start_part_2_logic: hl = sonic_x - x obiektu (ix+2/3) / and a / sbc hl,de / jr nc
	ldy #OB_X+1
	lda sonic_x
	cmp (zg_obj),y
	iny
	lda sonic_x+1
	sbc (zg_obj),y
	bcs sk46_p2r
	ldy #17                   ; 02:BC73: Sonic na lewo: ld a,(ix+17) / and a / jr z / dec (ix+17)
	lda (zg_obj),y
	beq sk46_p2m
	sec
	sbc #1
	sta (zg_obj),y
	jmp sk46_p2m              ; 02:BC7C: jr @pt2_after_maybe_updating_pos
sk46_p2r                        ; 02:BC7E @pt2_sonic_is_to_the_right: ld a,(ix+17) / cp $80 / jr nc / inc (ix+17)
	ldy #17
	lda (zg_obj),y
	cmp #$80
	bcs sk46_p2m
	adc #1                    ; C = 0 po cmp < $80
	sta (zg_obj),y
sk46_p2m                        ; 02:BC88 @pt2_after_maybe_updating_pos: res 1,(ix+24)
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$FD
	sta (zg_obj),y
	lda g_global_tick_counter ; 02:BC8C: ld c,a / and $40 / ret nz - luk tylko w pierwszej polowce kazdych 128 tickow
	sta zg_a
	and #$40
	bne sk46_ret
	lda g_boss_hits_taken     ; 02:BC93: cp $06 / ret z - dokladnie 6 trafien: bez luku
	cmp #$06
	beq sk46_ret
	lda (zg_obj),y            ; 02:BC99: set 1,(ix+24) (Y = OB_FLAGS)
	ora #$02
	sta (zg_obj),y
	lda zg_a                  ; 02:BC9D: ld a,c / and $1F / ret nz
	and #$1F
	bne sk46_ret
	lda #$13                  ; 02:BCA1: ld a,$13 / rst $28 / ret
	jmp play_sfx

; ---------------------------------------------------------------------
; sk46_pair = @fn_draw_sprite_pair (02:BCA5): tmp_02 = zg_de (y), kafel (zg_hl) w (tmp_00 + tmp_04, y + tmp_06), kafel (zg_hl + 1)
; o 8 px w prawo (tmp_04 + 8 na czas rysowania, potem z powrotem). Wejscie: zg_hl = adres okna kafli, zg_de = y. Wyjscie: zg_hl + 2;
; zg_de, zg_bc bez zmian (oryginal: push/pop wokol draw_sprite). Niszczy A, X, Y, zg_off.
; M7.5 (docs/plan-m7.md M7.5 - implementacja zappera przy stanie identycznym z Mesenem; plan-m7-ntsc.md 1.4): oba draw_sprite pary
; w linii, bez zc_dspr (przelaczanie PORTB na bank 45) i bez push/pop tmp_04 - x obu sprite'ow liczy raz sk46_xpre (zm_t0 / zm_t1 /
; zm_t2), y raz na pare. Wynik jak 2 x draw_sprite (obj/dispatch.asm): wpisy tablicy sprite'ow, licznik, wskaznik (inc e - zawijanie
; w stronie), grupa na wpis (v_grp_s / v_grp_e / v_ngrp), tmp_04 bez zmian, zg_off = drugi kafel, zd_y / zd_x / zd_r jak po drugim
; draw_sprite; tmp_02 = y ostatniej pary ustawia wolajacy (po dolnej kuli toru i po luku - posrednich wartosci nikt nie czyta), y = zg_de
; + (tmp_06 - scroll_y) z sk46_xpre. Ok. 245 zamiast ok. 665 cykli na pare (12 par w ticku luku). A i flagi na wyjsciu nieokreslone
; (jak draw_sprite po M7.5 - obj/dispatch.asm, kontrakt wyjscia).
; ---------------------------------------------------------------------
sk46_pair
	clc                       ; 02:BCA5: ld (tmp_02),de - M7.5: tmp_02 = y pary ustawiane raz po ostatniej parze (wywolujacy; posrednich
	lda zg_de                 ; wartosci nikt nie czyta); y = tmp_02 + tmp_06 - scroll_y = zg_de + (tmp_06 - scroll_y z sk46_xpre)
	adc SK46_KYL
	sta zd_y
	lda zg_de+1
	adc SK46_KYH
	sta zd_y+1
	ldy #1                    ; 02:BCB0: drugi kafel -> zg_off (i zd_r - kafel ostatniego draw_sprite)
	lda (zg_hl),y
	sta zg_off
	sta zd_r
	lda zd_y+1                ; y jak draw_sprite: hi $FF i lo >= $F0 albo hi 0 i lo < $C0 - widoczny
	beq sk46_y0
	cmp #$FF
	bne sk46_pdone
	lda zd_y
	cmp #$F0
	bcc sk46_pdone
	bcs sk46_pvis
sk46_y0
	lda zd_y
	cmp #$C0
	bcs sk46_pdone
sk46_pvis
	lda zm_t2                 ; pierwszy sprite (x0): b0 - x hi = 0
	lsr
	bcc sk46_pb
	ldx g_next_avail_vdp_sprite_ptr ; wpis (x, y, kafel) jak ds1_put
	lda zm_t0
	sta SPRTAB,x
	inx
	lda zd_y
	sta SPRTAB,x
	inx
	ldy #0
	lda (zg_hl),y
	sta SPRTAB,x
	inx
	stx g_next_avail_vdp_sprite_ptr
	inc g_sprite_count
	ldx v_ngrp                ; grupa wpisu (jak grp_add)
	cpx #N_GROUPS
	bcs sk46_pb
	lda g_next_avail_vdp_sprite_ptr
	sta v_grp_e,x
	sec
	sbc #3
	sta v_grp_s,x
	inc v_ngrp
sk46_pb
	lda zm_t2                 ; drugi sprite (x0 + 8): b1
	and #$02
	beq sk46_pdone
	ldx g_next_avail_vdp_sprite_ptr
	lda zm_t1
	sta SPRTAB,x
	inx
	lda zd_y
	sta SPRTAB,x
	inx
	lda zg_off
	sta SPRTAB,x
	inx
	stx g_next_avail_vdp_sprite_ptr
	inc g_sprite_count
	ldx v_ngrp
	cpx #N_GROUPS
	bcs sk46_pdone
	lda g_next_avail_vdp_sprite_ptr
	sta v_grp_e,x
	sec
	sbc #3
	sta v_grp_s,x
	inc v_ngrp
sk46_pdone
	clc                       ; 02:BCC5: pop hl / ret - hl = adres za para
	lda zg_hl
	adc #2
	sta zg_hl
	bcc sk46_pret
	inc zg_hl+1
sk46_pret
	rts

; sk46_xpre (M7.5): x ekranu sprite'ow pary - zm_t0 = (tmp_00 + tmp_04 - scroll_x) lo, zm_t1 = (tmp_00 + tmp_04 + 8 - scroll_x) lo,
; zm_t2 b0 / b1 = starszy bajt 0 (sprite widoczny w x, jak test draw_sprite); zd_x = zm_t1, zd_x+1 = starszy bajt sumy tmp_00 + tmp_04 + 8
; (jak po draw_sprite drugiego sprite'a). Wolane po ustawieniu tmp_00, tmp_04 (stale do konca rysowania w ticku).
sk46_xpre
	sec                       ; K_y = tmp_06 - scroll_y (stale w ticku: tmp_06 = 0 ustawione w sk46_inited, scroll_y)
	lda tmp_06
	sbc g_level_scroll_y_pix_lo
	sta SK46_KYL
	lda tmp_06+1
	sbc g_level_scroll_y_pix_lo+1
	sta SK46_KYH
	clc
	lda tmp_00
	adc tmp_04
	sta zm_t0
	lda tmp_00+1
	adc tmp_04+1
	sta zm_t1                 ; suma hi (robocze)
	clc
	lda zm_t0
	adc #8
	sta zd_x
	lda zm_t1
	adc #0
	sta zd_x+1                ; suma drugiego sprite'a hi (zostaje - jak draw_sprite)
	lda #0
	sta zm_t2
	sec
	lda zm_t0
	sbc g_level_scroll_x_pix_lo
	sta zm_t0
	lda zm_t1
	sbc g_level_scroll_x_pix_lo+1
	bne sk46_x1
	inc zm_t2                 ; b0: pierwszy widoczny
sk46_x1
	sec
	lda zd_x
	sbc g_level_scroll_x_pix_lo
	sta zm_t1
	sta zd_x
	lda zd_x+1
	sbc g_level_scroll_x_pix_lo+1
	bne sk46_xr
	lda zm_t2
	ora #$02                  ; b1: drugi widoczny
	sta zm_t2
sk46_xr
	rts

; ---------------------------------------------------------------------
; objfunc_47_SKY3_electric_ball (02:BCDF): kula elektryczna z przycisku bossa. Co tick set 5 (bez kolizji z mapa), set 5 iy_08
; (kula istnieje); kolizja z Soniciem (tmp_06/07 = $02/$02, (ix+13/14) z poprzedniego obiektu slotu) - damage_sonic (gdy zywy)
; i usuniecie. Ladowanie: (ix+17) + 1 do $C8 (200 tickow w ($0420, $012F)). Potem naprowadzanie: poza ekranem (x <= kamera X - 12,
; x > kamera X + 256 (inc h), y <= kamera Y - 12, kamera Y + y >= $10000 - patrz nizej) usuniecie; Vx + 12 / + 24 sub w strone
; Sonica (24 przy ruchu w przeciwna strone), Vy + 10 / + 5 (5 przy ruchu w przeciwna strone) - bez ograniczenia predkosci.
; Zawsze potem animacja (oz3_dfa: LUT_SKY3_electric_ball_anim, baza SPRTAB_SKY3_electric_ball - klatki co 2 ticki) i usuniecie,
; gdy walka sie skonczyla (iy_08 b4 = 0). Usuniecie: (ix+0) = $FF, res 5 iy_08.
; ---------------------------------------------------------------------
objfunc_47_sky3_eball
	ldy #OB_FLAGS             ; 02:BCDF: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda iy_08_lvflag03        ; 02:BCE3: set 5,(iy+iy_08_lvflag03) - kula istnieje (jedna naraz)
	ora #$20
	sta iy_08_lvflag03
	lda #$02                  ; 02:BCE7: ld hl,$0202 / ld (tmp_06),hl
	sta tmp_06
	sta tmp_06+1
	jsr zc_collide            ; 02:BCED: call check_collision_with_sonic / jr c @did_not_collide_with_sonic
	bcs sk47_nohit
	lda iy_05_lvflag00        ; 02:BCF2: bit 0,(iy+iy_05_lvflag00) / call z,damage_sonic / jp @destroy_this_object
	lsr
	bcs sk47_kill
	jsr damage_sonic
sk47_kill
	jmp sk47_destroy
sk47_nohit                      ; 02:BCFC @did_not_collide_with_sonic: ld a,(ix+17) / cp $C8 / jp c @state_charging_up
	ldy #17
	lda (zg_obj),y
	cmp #$C8
	jcc sk47_charge
	ldy #OB_X+1               ; 02:BD04: e,d = x (de)
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	clc                       ; 02:BD0A: hl = kamera X + $FFF4 (16 bit)
	lda g_level_scroll_x_pix_lo
	adc #$F4
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #$FF
	sta zg_hl+1
	lda zg_hl                 ; 02:BD11: and a / sbc hl,de / jp nc @destroy - bez pozyczki (6502 C = 1): x <= kamera X - 12
	cmp zg_de
	lda zg_hl+1
	sbc zg_de+1
	jcs sk47_destroy
	ldx g_level_scroll_x_pix_lo+1 ; 02:BD17: ld hl,(g_level_scroll_x_pix_lo) / inc h (8 bit) / and a / sbc hl,de / jp c @destroy
	inx
	stx zg_a
	lda g_level_scroll_x_pix_lo
	cmp zg_de
	lda zg_a
	sbc zg_de+1
	jcc sk47_destroy          ; pozyczka: kamera X + 256 < x - za prawa krawedzia
	lda sonic_x               ; 02:BD21: hl = sonic_x / and a / sbc hl,de - C (pozyczka) = Sonic na lewo
	cmp zg_de
	lda sonic_x+1
	sbc zg_de+1
	ldy #OB_VX+2              ; 02:BD27: l,h,a = Vx (ldy / lda nie zmieniaja C); jr nc @sonic_is_to_the_right
	lda (zg_obj),y            ; (N = znak Vx - bit 7,a)
	bcs sk47_xr
	bmi sk47_xl1              ; 02:BD32: Sonic na lewo: ld c,$FF / ld de,$FFF4 / bit 7,a / jr nz - juz leci w lewo: -12
	lda #$E8                  ; 02:BD3B: ld de,$FFE8 - leci w prawo: -24 (szybszy zawrot)
	bne sk47_xl2              ; zawsze
sk47_xl1
	lda #$F4
sk47_xl2
	sta zg_de
	lda #$FF
	sta zg_de+1
	sta zg_a                  ; c = $FF
	bne sk47_xadd             ; zawsze
sk47_xr                         ; 02:BD40 @sonic_is_to_the_right: ld c,$00 / ld de,$000C / bit 7,a / jr z - juz w prawo: +12
	bpl sk47_xr1
	lda #$18                  ; 02:BD49: ld de,$0018 - leci w lewo: +24
	bne sk47_xr2              ; zawsze
sk47_xr1
	lda #$0C
sk47_xr2
	sta zg_de
	lda #0
	sta zg_de+1
	sta zg_a                  ; c = 0
sk47_xadd                       ; 02:BD4C @x_vel_selected: add hl,de / adc a,c - Vx (24 bit) += (c, d, e); (ix+7..9) = l, h, a
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
	ldy #OB_Y+1               ; 02:BD57: e,d = y (de)
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	clc                       ; 02:BD5D: hl = kamera Y + $FFF4 / and a / sbc hl,de / jr nc @destroy - y <= kamera Y - 12
	lda g_level_scroll_y_pix_lo
	adc #$F4
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #$FF
	sta zg_hl+1
	lda zg_hl
	cmp zg_de
	lda zg_hl+1
	sbc zg_de+1
	jcs sk47_destroy
	clc                       ; 02:BD69: ld hl,(g_level_scroll_y_pix_lo) / ld bc,$00C0 / add hl,de / and a / sbc hl,de / jr c
	lda g_level_scroll_y_pix_lo ; @destroy - BLAD oryginalu: bc ($00C0) nie jest uzyty, hl = kamera Y + y - y; pozyczka tylko,
	adc zg_de                 ; gdy kamera Y + y przekracza $FFFF (add hl,de z przeniesieniem) - w praktyce nigdy. Dolnej krawedzi
	lda g_level_scroll_y_pix_lo+1 ; ekranu oryginal nie sprawdza (bc pozniej i tak nadpisane: c w obu drogach, b = 0 bez uzycia)
	adc zg_de+1
	jcs sk47_destroy
	lda sonic_y               ; 02:BD75: hl = sonic_y / and a / sbc hl,de - C (pozyczka) = Sonic nad kula
	cmp zg_de
	lda sonic_y+1
	sbc zg_de+1
	ldy #OB_VY+2              ; 02:BD7B: l,h,a = Vy; jr nc @sonic_is_below
	lda (zg_obj),y
	bcs sk47_yb
	bmi sk47_ya1              ; 02:BD86: Sonic wyzej: ld c,$FF / ld de,$FFF6 / bit 7,a / jr nz - juz w gore: -10
	lda #$FB                  ; 02:BD8F: ld de,$FFFB - leci w dol: -5
	bne sk47_ya2              ; zawsze
sk47_ya1
	lda #$F6
sk47_ya2
	sta zg_de
	lda #$FF
	sta zg_de+1
	sta zg_a                  ; c = $FF
	bne sk47_yadd             ; zawsze
sk47_yb                         ; 02:BD94 @sonic_is_below: ld de,$000A / ld c,$00 / bit 7,a / jr z - juz w dol: +10
	bpl sk47_yb1
	lda #$05                  ; 02:BD9D: ld de,$0005 - leci w gore: +5
	bne sk47_yb2              ; zawsze
sk47_yb1
	lda #$0A
sk47_yb2
	sta zg_de
	lda #0
	sta zg_de+1
	sta zg_a                  ; c = 0
sk47_yadd                       ; 02:BDA0 @y_vel_selected: add hl,de / adc a,c; (ix+10..12) = l, h, a / jr @do_anim_and_maybe_destroy
	ldy #OB_VY
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
	jmp sk47_doanim
sk47_charge                     ; 02:BDAD @state_charging_up: inc (ix+17) - kula laduje sie na miejscu (A = (ix+17) < $C8)
	clc
	adc #1
	sta (zg_obj),y
sk47_doanim                     ; 02:BDB0 @do_anim_and_maybe_destroy: ld bc,LUT_SKY3_electric_ball_anim / ld de,SPRTAB_SKY3_electric_ball
	lda #<[SK47_ANIM-OZ_OFF]  ; (sekwencja - adres okna, baza map - adres SMS) / call do_framed_animation
	sta zg_bc
	lda #>[SK47_ANIM-OZ_OFF]
	sta zg_bc+1
	lda #<SK47_SPR
	sta zg_de
	lda #>SK47_SPR
	sta zg_de+1
	jsr oz3_dfa
	lda iy_08_lvflag03        ; 02:BDB9: bit 4,(iy+iy_08_lvflag03) / ret nz - walka trwa
	and #$10
	bne sk47_ret
sk47_destroy                    ; 02:BDBE @destroy_this_object: ld (ix+0),$FF / res 5,(iy+iy_08_lvflag03) / ret
	lda #$FF
	ldy #OB_TYPE
	sta (zg_obj),y
	lda iy_08_lvflag03
	and #$DF
	sta iy_08_lvflag03
sk47_ret
	rts
