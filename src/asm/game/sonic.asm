; =====================================================================
;  sonic.asm - logika Sonica (M3.3): przeklad objfunc_00_sonic (01:48C8) dla stref GHZ
;
;  Nazwy i adresy wg dezasemblacji s1smsdisasm-gm (tylko material referencyjny, kod napisany od nowa).
;  Wywolanie co tick po kamerze, przed obj_motion (w oryginale: run_all_objfuncs -> try_run_objfunc_DE,
;  adres powrotu = return_from_objfunc). Rekord Sonica adresowany absolutnie (sonic_*, game/sms.inc).
;
;  Rejestry Z80 miedzy etapami (kernel/mem.inc): HL = zs_hl (L, H), DE = zs_de (E, D), B = zs_b, C = zs_c.
;  Predkosc X/Y w rejestrach: HL = (sub, lo) = (L, H), B = hi; dodawana wartosc DE = (sub, lo), C = hi.
;
;  Przeniesione: wybor fizyki (4 zestawy), toczenie, bieg/hamowanie/wybieg z limitem predkosci, skok
;  o zmiennej wysokosci, grawitacja z predkoscia graniczna, patrzenie w gore/dol, nuda, animacje i klatka
;  sprite'a, twarde limity predkosci, przyciecie do granic poziomu, bloki specjalne 00 (nic), 02 (koniec
;  rampy), 03 (sprezyna w lewo), od M3.5 01 (kolce: damage_sonic), 04/09 (sprezyny w gore), 08 (woda),
;  0A, zbieranie pierscieni z ukladu (add_A_rings), kill_sonic, iskra pierscienia
;  (zmienne; rysowanie - renderer M3.6), speed shoes, niesmiertelnosc, oslona, tlumienie wejscia.
;  Zaslepki (licznik v_sonic_todo, kod w v_sonic_todo_id): umieranie (M3.7), woda i tonienie, teleport,
;  zakonczenie gry, specjalny etap, pozostale bloki specjalne (0B+, inne strefy - M6). Dzwieki (rst $28/$18) - M5.
;  Test: tools/m3_unit.py --proc SONIC_OBJFUNC (pary RAM z m3_ref.py --wywolania, plik -sonic.m3t).
; =====================================================================

; identyfikatory zaslepek (v_sonic_todo_id)
TODO_DYING   = 1           ; @sonic_is_dying - przelozony w M3.7 (sonic_dying), identyfikator nieuzywany
TODO_WATER   = 2           ; woda: tonienie, babelki, stan pod woda - od M6.8 przelozone (kod zostaje wolny)
TODO_TELEPORT = 3          ; teleport (M6)
TODO_ENDING  = 4           ; zakonczenie gry (M6)
TODO_MUSIC   = 5           ; (nieuzywany od M4.9: licznik muzyki szmaragdu przelozony - sh_emerald_music)
TODO_SPECIAL = 6           ; blok specjalny bez przekladu (kod w v_sonic_todo_spec) - kody 0B+ (M6)
TODO_BUMPER  = 7           ; okragly zderzak etapu specjalnego (M6)
TODO_SPARKLE = 8           ; iskry niesmiertelnosci (losowe pozycje, random_A) - M4

; ---------------------------------------------------------------------
; sonic_objfunc: objfunc_00_sonic (01:48C8). Wejscie/wyjscie: stan w lustrze RAM SMS.
; Niszczy wszystkie rejestry, zs_*, zg_* (obj_tile_ptr), zg_obj = object_list.
; ---------------------------------------------------------------------
sonic_objfunc
	mwa #object_list zg_obj   ; IX = rekord Sonica (obj_tile_ptr)
; --- 01:48C8: flagi poczatku ticku ---
	lda iy_08_lvflag03
	and #$FD                  ; res 1,(iy+8): "byl na ziemi" kasowane...
	sta iy_08_lvflag03
	bit sonic_flags_ix_24
	bpl so_air
	ora #$02                  ; ...i ustawiane, gdy b7 flag (na ziemi) - @fn_set_was_on_ground_bit
	sta iy_08_lvflag03
so_air
	lda iy_07_lvflag02
	ora #$80                  ; set 7,(iy+7)
	sta iy_07_lvflag02
	lda iy_05_lvflag00
	and #$01                  ; bit 0 = Sonic umiera
	beq so_alive
	jmp sonic_dying           ; jp @sonic_is_dying (01:543C) - M3.7
so_alive
	lda sonic_brake_sound_cooldown_timer_ix_22
	beq so_nobrake
	dec sonic_brake_sound_cooldown_timer_ix_22 ; @fn_handle_brake_sound_cooldown_timer
so_nobrake
	lda sonic_flags_ix_24
	and #$DF                  ; res 5,(ix+24): kolizja z mapa wlaczona
	sta sonic_flags_ix_24
	lda iy_06_lvflag01
	and #$40
	beq so_nostun
	lda #$FF                  ; @fn_handle_damage_stun_and_input_suppression: bez wejscia,
	sta g_inputs_player_1     ; flagi bez toczenia (b0) i bez b2
	lda sonic_flags_ix_24
	and #$FA
	sta sonic_flags_ix_24
so_nostun
	lda g_directional_input_suppression_timer
	beq so_nosupp
	jsr sh_enforce_input_suppression ; @fn_enforce_directional_input_suppression
so_nosupp
	lda iy_07_lvflag02
	and #$01                  ; etap specjalny: @fn_forbid_rolling_in_special_stage (set 2 flag)
	beq so_nospst
	lda sonic_flags_ix_24
	ora #$04
	sta sonic_flags_ix_24
so_nospst
	lda iy_08_lvflag03
	and #$01                  ; niesmiertelnosc: @fn_handle_invincibility
	beq so_noinv
	jsr sh_invincibility
so_noinv
	lda sonic_flags_ix_24
	and #$10                  ; pod woda: @fn_handle_air_timer_and_drowning (M6.8)
	beq so_nodrown
	jsr sh_drown
so_nodrown
	lda g_chaos_emerald_music_countdown_timer
	beq so_nomus
	jsr sh_emerald_music      ; @fn_handle_chaos_emerald_music_countdown_timer (01:5285, M4.9)
so_nomus
	lda g_teleport_start_countdown_timer
	beq so_notele
	jmp sh_teleport           ; jp @handle_teleport_start (01:5117, M6.9)
so_notele
	lda iy_08_lvflag03
	and #$40                  ; jp @handle_ending_animation_teleport_in (M6.11: poziom koncowy $12)
	beq so_noend
	jmp sh_tele_in
so_noend
	lda iy_08_lvflag03
	and #$80                  ; call @fn_handle_good_ending_sequence (M6.11)
	beq so_nogood
	jsr sh_good_end           ; C = 1: pop hl oryginalu - reszta fizyki pominieta, dalej @continue_past_basic_movement_physics
	bcc so_nogood
	jmp sa_misc
so_nogood

; --- wybor fizyki (01:4928): 9 B parametrow -> tmp_00..tmp_08, limit predkosci, skok, grawitacja ---
; tmp_00 przyspieszenie, tmp_02 hamowanie, tmp_04 tarcie (wybieg), tmp_06/07 predkosc graniczna spadania
; (tmp_07 = piksele), tmp_08 animacja biegu przy limicie predkosci
	lda sonic_flags_ix_24
	and #$10
	beq so_not_water
	ldx #2*9                  ; @sonic_physics_underwater
	jsr so_copy_physics
	mwa #$0100 g_sonic_x_speed_cap_subpx
	mwa #$FD80 g_sonic_y_jump_velocity
	mwa #$0010 g_sonic_y_gravity_acceleration
	jmp so_physics_selected
so_not_water                    ; @not_underwater_physics
	lda sonic_speed_shoes_ix_21
	bne so_shoes
	lda iy_07_lvflag02
	and #$01
	bne so_spstage
so_normal                       ; @is_normal_physics (tempo muzyki - M5)
	ldx #0*9
	jsr so_copy_physics
	mwa #$0300 g_sonic_x_speed_cap_subpx
	mwa #$FC80 g_sonic_y_jump_velocity
	mwa #$0038 g_sonic_y_gravity_acceleration
	jmp so_physics_selected
so_spstage                      ; @is_special_stage_air_physics: na ziemi - zwykla fizyka
	bit sonic_flags_ix_24
	bmi so_normal
	ldx #1*9
	jsr so_copy_physics
	mwa #$0C00 g_sonic_x_speed_cap_subpx
	mwa #$FC80 g_sonic_y_jump_velocity
	mwa #$0038 g_sonic_y_gravity_acceleration
	jmp so_physics_selected
so_shoes                        ; @is_speed_shoes_physics
	ldx #3*9
	jsr so_copy_physics
	mwa #$0600 g_sonic_x_speed_cap_subpx
	mwa #$FC80 g_sonic_y_jump_velocity
	mwa #$0038 g_sonic_y_gravity_acceleration
	lda g_global_tick_counter
	and #$03
	bne so_physics_selected
	dec sonic_speed_shoes_ix_21 ; @fn_handle_speed_shoes_timer (co 4 ticki)

; --- 01:49D9: toczenie (dol), blok specjalny pod srodkiem Sonica ---
so_physics_selected
	lda g_inputs_player_1
	and #$02                  ; b1 = dol (aktywny zerem)
	bne so_noroll
	jsr sh_try_to_roll
	jmp so_spec
so_noroll
	lda iy_07_lvflag02        ; @fn_clear_extra_rolling_flag_SEMIVESTIGIAL
	and #$FB
	sta iy_07_lvflag02
so_spec
	lda #$0F                  ; rompage_2 = 15 (tablica blokow specjalnych w banku 15)
	sta g_committed_rompage_2
	mwa #$000C zg_bc          ; punkt: srodek Sonica (x + 12, y + 16)
	mwa #$0010 zg_de
	jsr obj_tile_ptr
	bcs so_spec_rom           ; adres ROM - kod specjalny z ROM-u nieznany (patrz motion.asm)
	ldy #0
	lda (zg_ptr),y
	tax
	lda SONIC_SPEC,x          ; kod bloku specjalnego (0F:B9ED + wskaznik + blok)
	cmp #$1C                  ; >= $1C: brak procedury (jr nc @return_from_tile_special)
	bcs so_after_spec
	pha
	lda #$02                  ; przed skokiem do procedury rompage_2 = 2
	sta g_committed_rompage_2
	pla
	jsr sonic_special         ; CODEPTRTAB_sonic_tile_specials[kod]
	jmp so_after_spec
so_spec_rom
	inc v_rom_reads

; --- @return_from_tile_special (01:4A28): upadek pod poziom, nuda, patrzenie ---
so_after_spec
; kill_sonic, gdy sonic_y + $24 > g_level_limit_y1 + $C0 (16 bit bez znaku)
	clc
	lda sonic_y
	adc #$24
	sta zs_t
	lda sonic_y+1
	adc #0
	sta zs_t+1                ; DE = y + $24
	clc
	lda g_level_limit_y1
	adc #$C0
	tax
	lda g_level_limit_y1+1
	adc #0                    ; HL = y1 + $C0 (X, A)
	cmp zs_t+1
	bcc so_kill               ; HL < DE (starszy bajt)
	bne so_nokill
	cpx zs_t
	bcs so_nokill
so_kill
	jsr kill_sonic
so_nokill
; nuda: licznik++ gdy brak wejscia ($FF), predkosc X (sub, lo) = 0 i na ziemi; inaczej 0
	lda #0
	sta zs_t
	sta zs_t+1
	lda g_inputs_player_1
	cmp #$FF
	bne so_notbored
	lda sonic_vel_x_sub
	ora sonic_vel_x
	bne so_notbored
	bit sonic_flags_ix_24
	bpl so_notbored
	clc
	lda g_sonic_bored_anim_countup_timer
	adc #1
	sta zs_t
	lda g_sonic_bored_anim_countup_timer+1
	adc #0
	sta zs_t+1
so_notbored                     ; @sonic_not_bored
	mwa zs_t g_sonic_bored_anim_countup_timer
	lda iy_06_lvflag01
	and #$80                  ; poziom z woda: @fn_set_underwater_state_based_on_water_level (M6.8)
	beq so_nowater
	jsr sh_underwater
so_nowater
	lda #$05                  ; animacja 5 (stanie)
	sta sonic_anim_index_ix_20
	lda g_sonic_bored_anim_countup_timer+1 ; licznik >= $168 -> @fn_handle_sonic_bored_anim
	cmp #>$0168
	bcc so_nobore2
	bne so_bore2
	lda g_sonic_bored_anim_countup_timer
	cmp #<$0168
	bcc so_nobore2
so_bore2
	lda #$0D                  ; animacja 13 (znudzony)
	sta sonic_anim_index_ix_20
so_nobore2
	lda g_inputs_player_1
	cmp #$FE                  ; tylko gora: patrzenie w gore
	bne so_nolookup
	jsr sh_camera_look_up
so_nolookup
	lda g_inputs_player_1
	and #$01                  ; gora niewcisnieta: powrot kamery
	beq so_norestore
	jsr sh_restore_camera_look
so_norestore
	lda sonic_flags_ix_24
	and #$01
	jne sr_rolling            ; jp nz,@sonic_is_rolling
; --- bieg (01:4A89): wymiary 24x32 (po toczeniu 24x24: y -= 8) ---
	lda sonic_height_ix_14
	cmp #$20
	beq so_h32
	sec                       ; sonic_y += $FFF8
	lda sonic_y
	sbc #8
	sta sonic_y
	lda sonic_y+1
	sbc #0
	sta sonic_y+1
so_h32                          ; @skip_adjust_y_pos_after_roll
	lda #$18
	sta sonic_width_ix_13
	lda #$20
	sta sonic_height_ix_14
	jsr so_load_vx            ; HL = Vx (sub, lo), B = hi, C = E = D = 0
	lda g_inputs_player_1
	and #$08                  ; prawo
	jeq sh_right_input
	lda g_inputs_player_1
	and #$04                  ; lewo
	jeq sh_left_input
; bez kierunku: wybieg (tarcie tmp_04 przeciwnie do ruchu), powyzej limitu - zwalnianie tmp_00
	lda zs_hl
	ora zs_hl+1
	ora zs_b
	jeq sx_update             ; stoi - bez zmian
	lda #$01
	sta sonic_anim_index_ix_20
	lda zs_b
	bmi sx_coast_left
; ruch w prawo: DE = -tmp_04, C = $FF
	lda tmp_04
	ldx tmp_04+1
	jsr so_neg_de             ; DE = -(X:A)
	lda #$FF
	sta zs_c
	jsr so_hl_minus_cap       ; HL - limit: C = 0 (6502) gdy HL < limit
	jcc sx_update
	lda tmp_00                ; powyzej limitu: DE = -tmp_00, animacja tmp_08
	ldx tmp_00+1
	jsr so_neg_de
	lda #$FF
	sta zs_c
	lda tmp_00+8
	sta sonic_anim_index_ix_20
	jmp sx_update
sx_coast_left                   ; @consider_coasting_x_speed_cap_moving_left: DE = +tmp_04, C = 0
	mwa tmp_04 zs_de
	lda #0
	sta zs_c
	jsr so_neghl_minus_cap    ; (-HL) - limit
	jcc sx_update
	mwa tmp_00 zs_de
	lda tmp_00+8
	sta sonic_anim_index_ix_20
; --- @update_x_velocity_from_basic_movement (01:4B1B): Vx (HL, B) += (DE, C), bez zmiany znaku ---
sx_update
	lda zs_b
	bmi sx_left
	jsr sx_add                ; A = B + C + przeniesienie (nowy hi), HL = HL + DE
	sta zs_c
	bpl sx_store              ; jp p: dalej >= 0
	lda sonic_vel_x_sub       ; przejscie przez zero: dozwolone tylko ze stania (Vx w RAM = 0)
	ora sonic_vel_x
	ora sonic_vel_x_hi
	beq sx_store
	jmp sx_zero
sx_left                         ; @update_x_velocity_moving_left
	jsr sx_add
	sta zs_c
	bmi sx_store              ; jp m: dalej < 0
sx_zero
	lda #0                    ; zmiana znaku -> Vx = 0
	sta zs_c
	sta zs_hl
	sta zs_hl+1
sx_store                        ; @store_updated_x_velocity
	lda zs_hl
	sta sonic_vel_x_sub
	lda zs_hl+1
	sta sonic_vel_x
	lda zs_c
	sta sonic_vel_x_hi

; --- @update_y_velocity_from_basic_movement (01:4B49): skok, grawitacja ---
sy_update
	lda sonic_vel_y_sub
	sta zs_hl
	lda sonic_vel_y
	sta zs_hl+1
	lda sonic_vel_y_hi
	sta zs_b
	lda #0
	sta zs_c
	sta zs_de
	sta zs_de+1
	bit sonic_flags_ix_24
	bpl sy_nolanding
	mwa sonic_y g_UNUSED_last_sonic_ground_y ; @fn_handle_sonic_landing_SEMIVESTIGIAL
	lda sonic_flags_ix_24
	and #$FB                  ; res 2 (koniec skoku)
	sta sonic_flags_ix_24
sy_nolanding
	lda sonic_flags_ix_24
	and #$01
	jne sr_y_rolling          ; jp nz,@update_y_velocity_for_rolling
	lda g_sonic_jump_countdown_timer
	bne sy_jump_cont          ; skok w toku
	bit sonic_flags_ix_24
	bpl sy_suppress           ; w powietrzu bez skoku
	lda sonic_flags_ix_24
	and #$08                  ; przycisk zwolniony po poprzednim skoku
	bne sy_jump_cont
	lda g_inputs_player_1
	and #$20                  ; b5 = przycisk (aktywny zerem)
	beq sy_suppress           ; trzymany od poprzedniego skoku - bez nowego
sy_jump_cont                    ; @jump_continue_or_await_release
	lda g_inputs_player_1
	and #$20
	bne sy_unsuppress         ; zwolniony
sy_jump_from_roll               ; @continue_jump_processing_from_rolling
	lda g_sonic_jump_countdown_timer
	bne sy_timer_on
	lda #$10                  ; @fn_start_jump_timer: 16 tickow wznoszenia
	sta g_sonic_jump_countdown_timer
	lda #$00                  ; rst $28: skok (01:50A2)
	jsr play_sfx
sy_timer_on
	mwa g_sonic_y_jump_velocity zs_hl ; Vy = skok (hi = $FF), bez grawitacji
	lda #$FF
	sta zs_b
	lda #0
	sta zs_c
	sta zs_de
	sta zs_de+1
	dec g_sonic_jump_countdown_timer
	lda sonic_flags_ix_24
	ora #$04                  ; set 2: w powietrzu po skoku
	sta sonic_flags_ix_24
	jmp sy_no_gravity
sy_suppress                     ; @suppress_jump_button
	lda sonic_flags_ix_24
	and #$F7                  ; res 3
	sta sonic_flags_ix_24
	jmp sy_stop_timer
sy_unsuppress                   ; @unsuppress_jump_button
	lda sonic_flags_ix_24
	ora #$08                  ; set 3
	sta sonic_flags_ix_24
sy_stop_timer
	lda #0
	sta g_sonic_jump_countdown_timer
sy_from_roll                    ; @continue_without_jumping_from_rolling
; grawitacja, gdy Vy lo (H) < tmp_07 (predkosc graniczna) albo Vy ujemne
	lda zs_hl+1
	bmi sy_gravity
	lda tmp_07
	cmp zs_hl+1               ; Z80: cp h / jr z / jr c -> bez grawitacji, gdy tmp_07 <= H
	beq sy_no_gravity
	bcc sy_no_gravity
sy_gravity                      ; @apply_gravity
	mwa g_sonic_y_gravity_acceleration zs_de
	lda #0
	sta zs_c
sy_no_gravity                   ; @continue_without_applying_gravity
	lda iy_06_lvflag01
	and #$01                  ; tryb do gory nogami (VESTIGIAL): DE:C = -(DE:C)
	beq sy_normal_grav
	lda zs_de
	eor #$FF
	clc
	adc #1
	sta zs_de
	lda zs_de+1
	eor #$FF
	adc #0
	sta zs_de+1
	lda zs_c
	eor #$FF
	adc #0
	sta zs_c
sy_normal_grav                  ; @skip_upside_down_gravity_VESTIGIAL
	clc                       ; Vy = (HL + DE, B + C + przeniesienie)
	lda zs_hl
	adc zs_de
	sta sonic_vel_y_sub
	lda zs_hl+1
	adc zs_de+1
	sta sonic_vel_y
	lda zs_b
	adc zs_c
	sta sonic_vel_y_hi
; g_sonic_bounce_vel_y = -(DE:C) (24 bit)
	lda zs_de
	eor #$FF
	clc
	adc #1
	sta g_sonic_bounce_vel_y_sub
	lda zs_de+1
	eor #$FF
	adc #0
	sta g_sonic_bounce_vel_y_sub+1
	lda zs_c
	eor #$FF
	adc #0
	sta g_sonic_bounce_vel_y_sub+2
	lda sonic_vel_y_sub       ; HL = nowe Vy (sub, lo) - pop hl oryginalu
	sta zs_hl
	lda sonic_vel_y
	sta zs_hl+1
	lda sonic_flags_ix_24
	and #$04
	beq sy_noroll_anim
	lda #$09                  ; @fn_set_roll_animation_for_airborne
	sta sonic_anim_index_ix_20
sy_noroll_anim
; |HL| > $0100 i flagi & $85 = 0 -> animacja: w gore $13 (sprezyna), w dol 1
	lda zs_hl+1
	bpl sy_abs
	lda zs_hl
	eor #$FF
	clc
	adc #1
	sta zs_hl
	lda zs_hl+1
	eor #$FF
	adc #0
	sta zs_hl+1
sy_abs                          ; @skip_negating_y_vel_for_absolute_value: $0100 - |HL| bez pozyczki -> pomin
	lda zs_hl+1
	cmp #$01
	bcc sy_ring
	bne sy_fast
	lda zs_hl
	beq sy_ring               ; |HL| = $0100 -> pomin
sy_fast
	lda sonic_flags_ix_24
	and #$85
	bne sy_ring
	lda sonic_vel_y_hi
	bpl sy_walkanim
	lda #$13
	sta sonic_anim_index_ix_20
	jmp sy_ring
sy_walkanim                     ; @select_walking_animation
	lda #$01
	sta sonic_anim_index_ix_20
; --- @continue_maybe_without_setting_animation (01:4C28): pierscienie w ukladzie pod (x + 12, y + 8) ---
sy_ring
	mwa #$000C zg_bc
	mwa #$0008 zg_de
	jsr obj_tile_ptr
	bcs sy_ring_rom
	ldy #0
	lda (zg_ptr),y
	and #$7F
	cmp #$79                  ; bloki $79-$7F (i $F9-$FF): pierscienie
	bcc sa_misc
	jsr sh_collect_ring       ; zg_ptr = bajt ukladu (DE oryginalu)
	jmp sa_misc
sy_ring_rom
	inc v_rom_reads

; --- @continue_past_basic_movement_physics (01:4C39): liczniki, animacja ---
sa_misc
	lda g_directional_input_suppression_timer
	beq sa_nosupp
	dec g_directional_input_suppression_timer ; @fn_decrement_directional_input_suppression_timer
	lda #$11
	sta sonic_anim_index_ix_20
sa_nosupp
	lda iy_06_lvflag01
	and #$40
	beq sa_nostun
	jsr sh_stun_anim          ; @fn_handle_damage_stun_animation_and_deactivation
sa_nostun
	lda iy_08_lvflag03
	and #$04                  ; babel powietrza (woda): @fn_handle_consuming_an_air_bubble (M6.8)
	beq sa_nobubble
	jsr sh_consume_bubble
sa_nobubble
	lda sonic_anim_index_ix_20
	cmp #$0A                  ; hamowanie: @fn_throttled_play_brake_sound_effect
	bne sa_nobrake
	lda sonic_brake_sound_cooldown_timer_ix_22
	bne sa_nobrake
	bit sonic_flags_ix_24
	bpl sa_nobrake
	lda #$03                  ; rst $28: hamowanie (01:51FD), blokada 60 tickow
	jsr play_sfx
	lda #$3C
	sta sonic_brake_sound_cooldown_timer_ix_22
sa_nobrake
; wskaznik animacji = LUT_sonic_anim_ptrs[nr]; zmiana animacji -> pozycja 0
	lda sonic_anim_index_ix_20
	asl
	tax
	lda SONIC_ANIM+[$5965-SONIC_ANIM_SMS],x
	sta sonic_anim_ptr_ix_17
	lda SONIC_ANIM+[$5965-SONIC_ANIM_SMS]+1,x
	sta sonic_anim_ptr_ix_17+1
	lda g_sonic_prev_anim_idx
	cmp sonic_anim_index_ix_20
	beq sa_same
	lda #0                    ; @fn_reset_anim_frame_idx_on_anim_change
	sta sonic_anim_sprite_subindex_ix_19
sa_same
; sekwencja: bajt >= 0 = klatka, ujemny = skok (nastepny bajt = nowa pozycja)
	clc                       ; zg_ptr = adres Atari sekwencji (adres SMS + przesuniecie regionu)
	lda sonic_anim_ptr_ix_17
	adc #<[SONIC_ANIM-SONIC_ANIM_SMS]
	sta zg_ptr
	lda sonic_anim_ptr_ix_17+1
	adc #>[SONIC_ANIM-SONIC_ANIM_SMS]
	sta zg_ptr+1
	ldy sonic_anim_sprite_subindex_ix_19
sa_find                         ; @find_next_anim_frame
	lda (zg_ptr),y
	bpl sa_found
	iny
	lda (zg_ptr),y
	sta sonic_anim_sprite_subindex_ix_19
	tay
	jmp sa_find
sa_found                        ; @found_anim_frame: D = klatka, BC = $4000 (w prawo) / $7000 (w lewo)
	sta zs_de+1
	lda #$40
	sta zs_b
	lda sonic_flags_ix_24
	and #$02
	beq sa_right
	lda #$70
	sta zs_b
sa_right
	lda iy_06_lvflag01
	and #$20                  ; oslona: co drugi tick klatka $18 (@fn_handle_shield_animation)
	beq sa_noshield
	lda g_global_tick_counter
	and #$01
	bne sa_noshield
	lda #$18
	sta zs_de+1
sa_noshield
	lda g_sonic_sprite_index_override
	beq sa_nooverride
	sta zs_de+1               ; @fn_use_left_facing_sonic_sprites: klatka z obiektu, BC = $7000
	lda #$70
	sta zs_b
sa_nooverride
	lda zs_de+1               ; renderer (render/sprites.asm): klatka i kierunek grafiki
	sta v_sonic_fr
	lda zs_b
	sta v_sonic_base
; g_new_sonic_sprite_ptr = BC + klatka * $120 (288 B grafiki 3 bpp na klatke w banku SMS)
	lda zs_de+1
	lsr
	lsr
	lsr                       ; klatka >> 3
	clc
	adc zs_de+1               ; H = klatka + (klatka >> 3)
	clc
	adc zs_b                  ; + B (bez przeniesienia z mlodszego bajtu: (klatka << 5) & $E0 + 0)
	sta g_new_sonic_sprite_ptr+1
	lda zs_de+1
	asl
	asl
	asl
	asl
	asl                       ; L = (klatka << 5) & $E0
	sta g_new_sonic_sprite_ptr
; mapa sprite'ow: normalna / do gory nogami / sprezyna (animacja $13) / brak (override)
	lda #<$591D               ; SPRITEMAP_sonic_normal
	sta zs_hl
	lda #>$591D
	sta zs_hl+1
	lda iy_06_lvflag01
	and #$01
	beq sa_noflip
	lda #<$592B               ; SPRITEMAP_sonic_hflip (VESTIGIAL)
	sta zs_hl
sa_noflip
	lda sonic_anim_index_ix_20
	cmp #$13
	bne sa_nospring
	lda #<$5939               ; SPRITEMAP_sonic_upspring_right
	sta zs_hl
	lda sonic_flags_ix_24
	and #$02
	beq sa_nospring
	lda #<$594B               ; SPRITEMAP_sonic_upspring_left
	sta zs_hl
sa_nospring
	lda g_sonic_sprite_index_override
	beq sa_setmap
	lda #0                    ; @fn_suppress_sprite_rendering
	sta zs_hl
	sta zs_hl+1
sa_setmap
	mwa zs_hl sonic_spritemap_ix_15
; twarde limity: |Vx lo|, |Vy lo| < 16 px/tick (01:4CCB)
	ldx #$10
	lda sonic_vel_x
	bpl sa_capx
	eor #$FF                  ; neg
	clc
	adc #1
	ldx #$F0
sa_capx
	cmp #$10
	bcc sa_nocapx
	stx sonic_vel_x
sa_nocapx
	ldx #$10
	lda sonic_vel_y
	bpl sa_capy
	eor #$FF
	clc
	adc #1
	ldx #$F0
sa_capy
	cmp #$10
	bcc sa_nocapy
	stx sonic_vel_y
sa_nocapy
; gorna krawedz: sonic_y <= $10 (bez znaku) -> $10
	lda sonic_y+1
	bne sa_notop
	lda sonic_y
	cmp #$11
	bcs sa_notop
	lda #$10
	sta sonic_y
sa_notop                        ; @skip_clamp_sonic_y_pos_top
	lda iy_06_lvflag01
	and #$80                  ; babelki (woda): @fn_blow_a_bubble_periodically (01:5224, M6.8) - pod woda (b4) przy mlodszym
	beq sa_nobubble2          ; bajcie g_global_tick_counter = 0 (co 256 tickow) spawn_bubble
	lda sonic_flags_ix_24
	and #$10
	beq sa_nobubble2
	lda g_global_tick_counter ; ld a,(g_global_tick_counter) / and a / call z, spawn_bubble
	bne sa_nobubble2
	jsr sonic_spawn_bubble
sa_nobubble2
	lda iy_08_lvflag03
	and #$01                  ; @fn_handle_invincibility_sparkle_sprite (M4.5)
	beq sa_nosparkle
	jsr sh_inv_sparkle
sa_nosparkle
	lda g_special_stage_round_bumper_cooldown_timer
	beq sa_nobumper
	jsr sh_bumper             ; @fn_handle_round_bumper_throbbing_effect (01:5231, M6.5)
sa_nobumper
	lda g_ring_sparkle_sprite_countdown_timer
	beq sa_noring
	jsr sh_ring_sparkle       ; @fn_handle_ring_sparkle_sprites
sa_noring
; przyciecie X do granic poziomu (pomijane przy b1 iy_06 - koniec poziomu)
	lda iy_06_lvflag01
	and #$02
	jne sa_clamp_done
	clc                       ; DE = limit_x0 + 8
	lda g_level_limit_x0
	adc #8
	sta zs_de
	lda g_level_limit_x0+1
	adc #0
	sta zs_de+1
	lda sonic_x+1             ; sonic_x < DE (bez znaku)?
	cmp zs_de+1
	bcc sa_clamp_left
	bne sa_check_right
	lda sonic_x
	cmp zs_de
	bcs sa_check_right
sa_clamp_left
	mwa zs_de sonic_x
	lda sonic_vel_x_hi
	bpl sa_clamp_done         ; jp p: Vx >= 0 zostaje
	lda #0
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
	jmp sa_clamp_done
sa_check_right                  ; @skip_clamp_sonic_x_pos_left: DE = limit_x1 + $F8
	clc
	lda g_level_limit_x1
	adc #$F8
	sta zs_de
	lda g_level_limit_x1+1
	adc #0
	sta zs_de+1
	clc                       ; HL = sonic_x + $18
	lda sonic_x
	adc #$18
	sta zs_hl
	lda sonic_x+1
	adc #0
	sta zs_hl+1
	cmp zs_de+1               ; HL < DE -> bez przyciecia
	bcc sa_clamp_done
	bne sa_clamp_right
	lda zs_hl
	cmp zs_de
	bcc sa_clamp_done
sa_clamp_right                  ; sonic_x = DE - $18 - 1 (scf / sbc hl,bc)
	clc
	lda zs_de
	sbc #$18                  ; C = 0: odejmuje $18 + 1
	sta sonic_x
	lda zs_de+1
	sbc #0
	sta sonic_x+1
	lda sonic_vel_x_hi
	bmi sa_clamp_done         ; jp m: Vx < 0 zostaje
	ora sonic_vel_x           ; A = hi | lo | ... (or h / or l oryginalu: hi, hi, lo)
	beq sa_clamp_done
	lda #0
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
sa_clamp_done                   ; @continue_past_clamp_sonic_x_pos_right
	lda sonic_flags_ix_24
	sta g_sonic_flags_copy
	lda sonic_anim_index_ix_20
	sta g_sonic_prev_anim_idx
; tempo animacji: bieg (1) i toczenie (9) zaleza od |Vx|, inne - +1 na tick
	ldx #$01                  ; D = 1, C = $30 (bieg)
	ldy #$30
	cmp #$01
	beq sa_speed_anim
	ldx #$06                  ; D = 6, C = $50 (toczenie)
	ldy #$50
	cmp #$09
	beq sa_speed_anim
	inc sonic_anim_sprite_subindex_ix_19
	rts
sa_speed_anim                   ; @handle_x_speed_dependent_anim
	stx zs_de+1
	sty zs_c
	lda sonic_vel_x_sub       ; HL = |Vx (sub, lo)| >> 1
	sta zs_hl
	lda sonic_vel_x
	sta zs_hl+1
	bpl sa_vabs
	lda zs_hl
	eor #$FF
	clc
	adc #1
	sta zs_hl
	lda zs_hl+1
	eor #$FF
	adc #0
	sta zs_hl+1
sa_vabs
	lsr zs_hl+1
	ror zs_hl
	clc                       ; subklatka += L
	lda zs_hl
	adc g_sonic_x_speed_dependent_anim_subframe
	sta g_sonic_x_speed_dependent_anim_subframe
	lda zs_hl+1               ; pozycja += H + D + przeniesienia (dwa adc oryginalu)
	adc zs_de+1
	adc sonic_anim_sprite_subindex_ix_19
	sta sonic_anim_sprite_subindex_ix_19
	cmp zs_c                  ; >= C -> - C
	bcc sa_ret
	sbc zs_c
	sta sonic_anim_sprite_subindex_ix_19
sa_ret
	rts

; =====================================================================
;  @sonic_is_rolling (01:532E): toczenie - wymiary 24x24, sterowanie tylko hamuje/rozpedza
; =====================================================================
sr_rolling
	lda sonic_height_ix_14
	cmp #$18
	beq sr_h24
	clc                       ; sonic_y += 8 (srodek w dol przy zmniejszeniu wysokosci)
	lda sonic_y
	adc #8
	sta sonic_y
	lda sonic_y+1
	adc #0
	sta sonic_y+1
sr_h24                          ; @skip_adjust_y_pos_before_roll
	lda #$18
	sta sonic_width_ix_13
	sta sonic_height_ix_14
	jsr so_load_vx
	lda zs_hl
	ora zs_hl+1
	ora zs_b
	jeq sr_look_down          ; stoi w miejscu
	lda #$09
	sta sonic_anim_index_ix_20
; lewo (bez dolu): w powietrzu przyspiesza w lewo, na ziemi przy ruchu w prawo - koniec toczenia, hamowanie
	lda g_inputs_player_1
	and #$04
	bne sr_not_left
	lda g_inputs_player_1
	and #$02
	beq sr_not_left           ; z dolem - jak bez kierunku
	bit sonic_flags_ix_24
	bpl sr_go_left
	lda zs_b
	bmi sr_not_right
	lda sonic_flags_ix_24
	and #$FE                  ; res 0: koniec toczenia
	sta sonic_flags_ix_24
	jmp sh_right_brake_to_left
sr_go_left                      ; @go_left_in_roll: DE = $FFF0, C = $FF
	mwa #$FFF0 zs_de
	lda #$FF
	sta zs_c
	jmp sx_update
sr_not_left                     ; @dont_go_left_in_roll: prawo (bez dolu)
	lda g_inputs_player_1
	and #$08
	bne sr_not_right
	lda g_inputs_player_1
	and #$02
	beq sr_not_right
	bit sonic_flags_ix_24
	bpl sr_go_right
	lda zs_b
	bpl sr_not_right
	lda sonic_flags_ix_24
	and #$FE
	sta sonic_flags_ix_24
	jmp sh_right_brake_to_left ; (oryginal: ten sam cel co dla lewa)
sr_go_right                     ; @go_right_in_roll: DE = $0010, C = 0
	mwa #$0010 zs_de
	lda #0
	sta zs_c
	jmp sx_update
sr_not_right                    ; @dont_go_right_in_roll: tarcie toczenia +4 / -4 subpiksele
	mwa #$0004 zs_de
	lda #0
	sta zs_c
	lda zs_b
	jmi sx_update
	mwa #$FFFC zs_de
	lda #$FF
	sta zs_c
	jmp sx_update
sr_look_down                    ; @consider_camera_look_down: toczenie w miejscu na ziemi = patrzenie w dol
	bit sonic_flags_ix_24
	bpl sr_skip_look
	lda #$07
	sta sonic_anim_index_ix_20
	lda sonic_flags_ix_24
	and #$FE
	sta sonic_flags_ix_24
	lda g_camera_y_look_up_offset_px+1
	bpl sr_look_dec           ; >= 0 -> od razu w dol
	sec                       ; $FFB0 - DE bez pozyczki (DE <= $FFB0, limit -$50) -> bez zmiany
	lda #$B0
	sbc g_camera_y_look_up_offset_px
	lda #$FF
	sbc g_camera_y_look_up_offset_px+1
	jcs sy_update
sr_look_dec                     ; @looking_up_immediate_look_down: DE--
	lda g_camera_y_look_up_offset_px
	bne sr_ld1
	dec g_camera_y_look_up_offset_px+1
sr_ld1
	dec g_camera_y_look_up_offset_px
	jmp sy_update
sr_skip_look                    ; @skip_camera_look_down: w powietrzu - limit predkosci toczenia
	lda #$09
	sta sonic_anim_index_ix_20
	lda zs_b
	bmi sr_neg
	jsr so_hl_minus_cap
	jmp sr_cmp
sr_neg
	jsr so_neghl_minus_cap
sr_cmp
	jcc sx_update             ; ponizej limitu - DE, C bez zmian (0)
	lda #0
	sta zs_c
	sta zs_de
	sta zs_de+1
	lda #$09
	sta sonic_anim_index_ix_20
	jmp sx_update

; @update_y_velocity_for_rolling (01:5407): skok z toczenia konczy toczenie
sr_y_rolling
	bit sonic_flags_ix_24
	bpl sr_y_suppress
	lda sonic_flags_ix_24
	and #$08
	bne sr_y_cont
	lda g_inputs_player_1
	and #$20
	beq sr_y_suppress
sr_y_cont                       ; @jump_continue_or_await_release_loc2
	lda g_inputs_player_1
	and #$20
	bne sr_y_unsuppress
	lda sonic_flags_ix_24
	and #$FE                  ; res 0
	sta sonic_flags_ix_24
	lda sonic_vel_x_sub
	and #$F8
	sta sonic_vel_x_sub
	jmp sy_jump_from_roll
sr_y_suppress                   ; @suppress_jump_button_loc2
	lda sonic_flags_ix_24
	and #$F7
	sta sonic_flags_ix_24
	jmp sy_from_roll
sr_y_unsuppress
	lda sonic_flags_ix_24
	ora #$08
	sta sonic_flags_ix_24
	jmp sy_from_roll

; =====================================================================
;  Wejscie w prawo / w lewo (01:4F01-01:4FD3)
; =====================================================================
sh_right_input                  ; @handle_right_input
	lda sonic_flags_ix_24
	and #$FD                  ; res 1: twarza w prawo
	sta sonic_flags_ix_24
	lda zs_b
	bmi sh_left_brake_to_right
	mwa tmp_00 zs_de          ; przyspieszenie, C = 0
	lda #0
	sta zs_c
	lda #$01
	sta sonic_anim_index_ix_20
	jsr so_hl_minus_cap       ; HL < limit -> przyspieszaj
	jcc sx_update
	lda #0                    ; >= limit: Vx = limit dokladnie, bez dodawania
	sta zs_b
	sta zs_de
	sta zs_de+1
	sta zs_c
	mwa g_sonic_x_speed_cap_subpx zs_hl
	lda tmp_00+8
	sta sonic_anim_index_ix_20
	jmp sx_update
sh_left_brake_to_right          ; @left_brake_to_right: jedzie w lewo, wcisniete prawo - hamowanie
	lda sonic_flags_ix_24
	ora #$02
	sta sonic_flags_ix_24
	lda #$0A                  ; animacja hamowania
	sta sonic_anim_index_ix_20
	mwa tmp_00+2 zs_de        ; DE = tmp_02 (hamowanie), C = 0
	lda #0
	sta zs_c
	jsr so_neghl_cmp_100      ; C = 1 gdy |HL| >= $0100
	jcs sx_update
	lda sonic_flags_ix_24
	and #$FD
	sta sonic_flags_ix_24
	lda #$01
	sta sonic_anim_index_ix_20
	jmp sx_update

sh_left_input                   ; @handle_left_input
	lda sonic_flags_ix_24
	ora #$02                  ; set 1: twarza w lewo
	sta sonic_flags_ix_24
	lda zs_hl
	ora zs_hl+1
	beq sh_left_go            ; (sub, lo) = 0 -> bez sprawdzania kierunku
	lda zs_b
	bpl sh_right_brake_to_left
sh_left_go                      ; @skip_right_brake_to_left_check: DE = -tmp_00, C = $FF
	lda tmp_00
	ldx tmp_00+1
	jsr so_neg_de
	lda #$FF
	sta zs_c
	lda #$01
	sta sonic_anim_index_ix_20
	jsr so_neghl_minus_cap
	jcc sx_update
	lda #0                    ; >= limit: Vx = -limit, B = $FF
	sta zs_de
	sta zs_de+1
	sta zs_c
	lda g_sonic_x_speed_cap_subpx
	eor #$FF
	clc
	adc #1
	sta zs_hl
	lda g_sonic_x_speed_cap_subpx+1
	eor #$FF
	adc #0
	sta zs_hl+1
	lda #$FF
	sta zs_b
	lda tmp_00+8
	sta sonic_anim_index_ix_20
	jmp sx_update
sh_right_brake_to_left          ; @right_brake_to_left: jedzie w prawo, wcisniete lewo - hamowanie
	lda sonic_flags_ix_24
	and #$FD
	sta sonic_flags_ix_24
	lda #$0A
	sta sonic_anim_index_ix_20
	lda tmp_00+2
	ldx tmp_00+3
	jsr so_neg_de             ; DE = -tmp_02, C = $FF
	lda #$FF
	sta zs_c
	jsr so_hl_cmp_100         ; C = 1 gdy HL >= $0100
	jcs sx_update
	lda sonic_flags_ix_24
	ora #$02
	sta sonic_flags_ix_24
	lda #$01
	sta sonic_anim_index_ix_20
	jmp sx_update

; =====================================================================
;  Procedury pomocnicze
; =====================================================================
; so_copy_physics: X = offset zestawu (0, 9, 18, 27) -> tmp_00..tmp_08 (ldir 9 B; M3.8d: bez petli)
so_copy_physics
	lda SONIC_PHYS,x
	sta tmp_00
	lda SONIC_PHYS+1,x
	sta tmp_00+1
	lda SONIC_PHYS+2,x
	sta tmp_00+2
	lda SONIC_PHYS+3,x
	sta tmp_00+3
	lda SONIC_PHYS+4,x
	sta tmp_00+4
	lda SONIC_PHYS+5,x
	sta tmp_00+5
	lda SONIC_PHYS+6,x
	sta tmp_00+6
	lda SONIC_PHYS+7,x
	sta tmp_00+7
	lda SONIC_PHYS+8,x
	sta tmp_00+8
	txa                       ; X += 9, Y = 9 - jak po petli
	clc
	adc #9
	tax
	ldy #9
	rts

; so_load_vx: HL = Vx (sub, lo), B = Vx hi, C = E = D = 0
so_load_vx
	lda sonic_vel_x_sub
	sta zs_hl
	lda sonic_vel_x
	sta zs_hl+1
	lda sonic_vel_x_hi
	sta zs_b
	lda #0
	sta zs_c
	sta zs_de
	sta zs_de+1
	rts

; so_neg_de: DE = -(X:A) (16 bit, cpl / inc de)
so_neg_de
	eor #$FF
	clc
	adc #1
	sta zs_de
	txa
	eor #$FF
	adc #0
	sta zs_de+1
	rts

; sx_add: HL += DE; A = B + C + przeniesienie (Z80: add hl,de / adc a,c); N wg wyniku
sx_add
	clc
	lda zs_hl
	adc zs_de
	sta zs_hl
	lda zs_hl+1
	adc zs_de+1
	sta zs_hl+1
	lda zs_b
	adc zs_c
	rts

; so_hl_minus_cap: porownanie HL z limitem (16 bit bez znaku): C = 1 gdy HL >= limit
; (Z80: xor a / sbc hl,de / jr c -> przy C = 0 6502 skok "ponizej limitu")
so_hl_minus_cap
	lda zs_hl
	cmp g_sonic_x_speed_cap_subpx
	lda zs_hl+1
	sbc g_sonic_x_speed_cap_subpx+1
	rts

; so_neghl_minus_cap: jak wyzej dla -HL (16 bit)
so_neghl_minus_cap
	lda zs_hl
	eor #$FF
	clc
	adc #1
	sta zs_t
	lda zs_hl+1
	eor #$FF
	adc #0
	sta zs_t+1
	lda zs_t
	cmp g_sonic_x_speed_cap_subpx
	lda zs_t+1
	sbc g_sonic_x_speed_cap_subpx+1
	rts

; so_hl_cmp_100 / so_neghl_cmp_100: C = 1 gdy (HL / -HL) >= $0100
so_hl_cmp_100
	lda zs_hl+1
	cmp #$01
	rts
so_neghl_cmp_100
	lda zs_hl
	eor #$FF
	clc
	adc #1
	lda zs_hl+1
	eor #$FF
	adc #0
	cmp #$01
	rts

; sh_try_to_roll (01:50C1): na ziemi, bez skoku i nie toczy sie -> toczenie; dzwiek, gdy Vx (sub, lo) != 0
sh_try_to_roll
	lda sonic_flags_ix_24
	and #$05
	bne str_ret
	bit sonic_flags_ix_24
	bpl str_ret
	lda sonic_flags_ix_24
	ora #$01
	sta sonic_flags_ix_24
	lda sonic_vel_x_sub       ; ld hl,(sonic_vel_x_sub) / or h - bez dzwieku w miejscu
	ora sonic_vel_x
	beq str_nosfx
	lda #$06                  ; rst $28: toczenie (01:50DB)
	jsr play_sfx
str_nosfx
	lda iy_07_lvflag02
	ora #$04
	sta iy_07_lvflag02
str_ret
	rts

; sh_camera_look_up (01:4EDD): stojac na ziemi, offset kamery do +$2C (z ujemnego od razu +1)
sh_camera_look_up
	lda sonic_vel_x_sub
	ora sonic_vel_x
	bne slu_ret
	bit sonic_flags_ix_24
	bpl slu_ret
	lda #$0C
	sta sonic_anim_index_ix_20
	lda g_camera_y_look_up_offset_px+1
	bmi slu_inc
	lda #$2C                  ; $002C - DE z pozyczka -> DE > $2C -> koniec
	cmp g_camera_y_look_up_offset_px
	lda #0
	sbc g_camera_y_look_up_offset_px+1
	bcc slu_ret
slu_inc
	inc g_camera_y_look_up_offset_px
	bne slu_ret
	inc g_camera_y_look_up_offset_px+1
slu_ret
	rts

; sh_restore_camera_look (01:4FD3): poza toczeniem offset kamery wraca o 1 do zera
sh_restore_camera_look
	lda sonic_flags_ix_24
	and #$01
	bne srl_ret
	lda g_camera_y_look_up_offset_px
	ora g_camera_y_look_up_offset_px+1
	beq srl_ret
	lda g_camera_y_look_up_offset_px+1
	bpl srl_dec
	inc g_camera_y_look_up_offset_px
	bne srl_ret
	inc g_camera_y_look_up_offset_px+1
	rts
srl_dec
	lda g_camera_y_look_up_offset_px
	bne srl_d1
	dec g_camera_y_look_up_offset_px+1
srl_d1
	dec g_camera_y_look_up_offset_px
srl_ret
	rts

; sh_enforce_input_suppression (01:568F): bez kierunkow, Vy lo/hi = 4/0, koniec toczenia i skoku
sh_enforce_input_suppression
	lda g_inputs_player_1
	ora #$0F
	sta g_inputs_player_1
	lda #$04                  ; ld hl,$0004 / ld (sonic_vel_y),hl: lo = 4, hi = 0
	sta sonic_vel_y
	lda #0
	sta sonic_vel_y_hi
	lda sonic_flags_ix_24
	and #$FA
	sta sonic_flags_ix_24
	rts

; ---------------------------------------------------------------------
; M6.8 woda (Labyrinth).
; sh_drown: @fn_handle_air_timer_and_drowning (01:5009) - Sonic pod woda (b4 flag), tylko strefa LAB (g_tile_flags_index = 3), nie LAB3
; (g_level $0B - tam bez tonienia). Licznik pod woda + 1 (16 bit); od $300: cyfra 5 - ((licznik - $300) >> 8) w HUD-zie (g_HUD_FFstr_buf
; = $80 + 2 * cyfra, $FF), pikanie $1A gdy tick & maska[cyfra] = 0 ($01 $07 $0F $1F $3F $7F), co drugi tick (tick b0 = 1) sprite cyfry
; draw_sprite_text do wpisu 20 tablicy (x = sonic_x - kamera + 8, y = sonic_y - kamera - 20; bajty) - g_sprite_count + 1. Przy $900
; (cyfra < 0): utoniecie - res 5 / res 6 iy_06, res 0 / set 3 iy_08 (smierc pod woda), set 0 iy_05 (Sonic umiera), licznik restartu $C0,
; muzyka $0A (rst $18), 4 x spawn_bubble, cyfra 0.
; ---------------------------------------------------------------------
sh_drown
	lda g_tile_flags_index    ; cp $03 / ret nz
	cmp #$03
	jne shd_ret
	lda g_level               ; cp $0B / ret z
	cmp #$0B
	jeq shd_ret
	inc g_sonic_underwater_countup_timer ; inc hl / ld (...),hl
	bne shd_inc
	inc g_sonic_underwater_countup_timer+1
shd_inc
	lda g_sonic_underwater_countup_timer+1 ; hl - $0300 (l bez zmian): h' = h - 3; Z80 ret c = 6502 C = 0
	sec
	sbc #$03
	jcc shd_ret
	sta zs_t                  ; ld a,$05 / sub h / jr nc, @dont_drown_yet
	lda #$05
	sec
	sbc zs_t
	bcs shd_digit
	lda iy_06_lvflag01        ; utoniecie (01:5028): res 5, res 6 iy_06
	and #$9F
	sta iy_06_lvflag01
	lda iy_08_lvflag03        ; res 0 (niesmiertelnosc), set 3 (smierc pod woda) iy_08
	and #$FE
	ora #$08
	sta iy_08_lvflag03
	lda iy_05_lvflag00        ; set 0 iy_05: Sonic umiera
	ora #$01
	sta iy_05_lvflag00
	lda #$C0
	sta g_level_restart_countdown_timer
	lda #$0A                  ; rst $18: muzyka smierci
	jsr play_music
	jsr sonic_spawn_bubble    ; 4 x call spawn_bubble (01:5044)
	jsr sonic_spawn_bubble
	jsr sonic_spawn_bubble
	jsr sonic_spawn_bubble
	lda #0                    ; xor a: cyfra 0
shd_digit                       ; @dont_drown_yet: A = cyfra (e)
	tax
	asl                       ; add a,a / add a,$80
	clc
	adc #$80
	sta g_HUD_FFstr_buf
	lda #$FF
	sta g_HUD_FFstr_buf+1
	lda #0                    ; port: bufor HUD-u zmieniony poza draw_hud - pamiec HUD-u (M4.9a, game/hud.asm) niewazna, nastepny
	sta v_hudk_ok             ; draw_hud zapisze caly napis od nowa (oryginal pisze go co tick)
	lda g_global_tick_counter ; and (hl): maska okresu pikania
	and shd_beep,x
	bne shd_nobeep
	lda #$1A                  ; rst $28: pikanie
	jsr play_sfx
shd_nobeep                      ; @skip_beep_sound
	lda g_global_tick_counter ; rrca / ret nc
	lsr
	bcc shd_ret
	sec                       ; c = (sonic_x - scroll_x) lo + 8
	lda sonic_x
	sbc g_level_scroll_x_pix_lo
	clc
	adc #$08
	pha
	sec                       ; b = (sonic_y - scroll_y) lo + $EC
	lda sonic_y
	sbc g_level_scroll_y_pix_lo
	clc
	adc #$EC
	tay
	pla
	ldx #20*3                 ; ld hl,g_sprite_table_20 / ld de,g_HUD_FFstr_buf / call draw_sprite_text
	jmp dh_text_buf
shd_ret
	rts
shd_beep	dta b($01,$07,$0F,$1F,$3F,$7F)   ; @beep_period_masks_per_air_countdown (01:5097)

; sh_underwater: @fn_set_underwater_state_based_on_water_level (01:50E8) - g_water_level_y - sonic_y: pozyczka (Sonic ponizej linii)
; -> @special_08_underwater (b4 flag = 1, plusk przy wejsciu); inaczej licznik pod woda = 0 i res 4 (ix+24)
sh_underwater
	sec
	lda g_water_level_y
	sbc sonic_y
	lda g_water_level_y+1
	sbc sonic_y+1
	bcs shu_above             ; Z80 jp c = 6502 C = 0
	jmp sp_08
shu_above
	lda #0
	sta g_sonic_underwater_countup_timer
	sta g_sonic_underwater_countup_timer+1
	lda sonic_flags_ix_24
	and #$EF
	sta sonic_flags_ix_24
	rts

; sh_consume_bubble: @fn_handle_consuming_an_air_bubble (01:51DD) - koniec toczenia i skoku (and $FA), animacja $14 (polykanie),
; licznik g_sonic_consume_air_bubble_countdown_timer - 1, przy 0 res 2 iy_08
sh_consume_bubble
	lda sonic_flags_ix_24
	and #$FA
	sta sonic_flags_ix_24
	lda #$14
	sta sonic_anim_index_ix_20
	dec g_sonic_consume_air_bubble_countdown_timer
	bne shc_ret
	lda iy_08_lvflag03
	and #$FB
	sta iy_08_lvflag03
shc_ret
	rts

; sh_emerald_music (@fn_handle_chaos_emerald_music_countdown_timer 01:5285, M4.9): licznik--; po dojsciu do 0 powrot
; muzyki poziomu (rst $18), res 0 iy_00, wait_until_irq_ticked = jedno pelne IRQ w srodku ticku Sonica (ekran:
; tablica sprite'ow wyslana - g_prev_sprite_count, lata kafli; potem odczyt kontrolera i random_A) i przywrocenie
; licznika sprite'ow (ld c,(g_sprite_count) ... ld (g_sprite_count),c); IRQ ustawia iy_00 b0 z powrotem.
; Flaga rekordu "IRQ przed Sonikiem" zostaje bez zmian (IRQ w trakcie Sonica - w referencji liczy sie tylko do
; licznika IRQ kroku). Licznik ustawia szmaragd $06 (GHZ2); w GHZ1 tylko scenariusz poke-monitory-b.
sh_emerald_music
	dec g_chaos_emerald_music_countdown_timer
	bne sem_ret
	lda g_level_music
	jsr play_music
	lda g_sprite_count
	pha
	lda iy_00
	and #$02                  ; upload_sprite_table_IRQ (iy_00 b1): licznik 0 - bez zmian
	beq sem_noup
	lda g_sprite_count
	beq sem_noup
	sta g_prev_sprite_count
	lda #0
	sta g_sprite_count
sem_noup
	jsr irq_tile_patch        ; 00:0162: lata ekranu zgloszona w tym ticku (kwiaty, pierscien)
	lda v_tr_fl
	pha
	jsr irq_extra             ; kontroler -> g_inputs_player_1, licznik IRQ kroku, random_A
	pla
	sta v_tr_fl
	lda iy_00
	ora #$01                  ; set 0,(iy+iy_00) na koncu update_screen
	sta iy_00
	pla
	sta g_sprite_count
sem_ret
	rts

; sh_invincibility (01:4FF5): co 4 ticki licznik--, koniec -> res 0 iy_08 (muzyka - M5)
sh_invincibility
	lda g_global_tick_counter
	and #$03
	bne sinv_ret
	dec g_invincibility_countdown_timer
	bne sinv_ret
	lda iy_08_lvflag03
	and #$FE
	sta iy_08_lvflag03
	lda g_level_music         ; ld a,(g_level_music) / rst $18 - powrot muzyki poziomu
	jmp play_music
sinv_ret
	rts

; sh_stun_anim (01:51BC): po trafieniu - animacja $10, szerokosc $1C; po wyladowaniu koniec ogluszenia
sh_stun_anim
	lda #$1C
	sta sonic_width_ix_13
	lda #$10
	sta sonic_anim_index_ix_20
	lda sonic_vel_y_hi
	bmi sstun_ret
	bit sonic_flags_ix_24
	bpl sstun_ret
	lda iy_06_lvflag01
	and #$BF
	sta iy_06_lvflag01
	lda #0
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
sstun_ret
	rts

; sh_collect_ring (@fn_try_collect_ring_in_ring_tile 01:4DEF): zg_ptr = bajt ukladu z pierscieniami.
; Bity 0/1 numeru bloku = lewy/prawy pierscien; zebrany = bit skasowany (blok zmienia numer - obraz M3.5).
sh_collect_ring
; Sonic co najmniej 16 px pod gorna krawedzia ekranu: (sonic_y - scroll_y) >= $10 (bez znaku)
	sec
	lda sonic_y
	sbc g_level_scroll_y_pix_lo
	tax
	lda sonic_y+1
	sbc g_level_scroll_y_pix_lo+1
	jcc scr_ret
	bne scr_y_ok              ; >= $0100
	cpx #$10
	jcc scr_ret
scr_y_ok
	clc                       ; HL = sonic_x + 12
	lda sonic_x
	adc #$0C
	sta zs_hl
	lda sonic_x+1
	adc #0
	sta zs_hl+1
	lda zs_hl                 ; B = ((L >> 4) & 1) + 1: polowa bloku (16 px) -> bit pierscienia
	lsr
	lsr
	lsr
	lsr
	and #$01
	clc
	adc #1
	sta zs_b
	ldy #0
	lda (zg_ptr),y
	sta zs_c                  ; C = numer bloku
	and zs_b
	beq scr_ret               ; w tej polowie juz bez pierscienia
	lda zs_hl
	and #$F0
	sta zs_hl
	mwa zs_hl g_screen_tile_replace_x
	mwa zs_hl g_ring_sparkle_sprite_x
	lda zs_c
	eor zs_b                  ; usuniecie pierscienia z ukladu
	ldy #0
	sta (zg_ptr),y
	clc                       ; HL = sonic_y + 8, L = (L & $E0) + 8
	lda sonic_y
	adc #8
	sta zs_hl
	lda sonic_y+1
	adc #0
	sta zs_hl+1
	lda zs_hl
	and #$E0
	clc
	adc #$08
	sta zs_hl
	mwa zs_hl g_screen_tile_replace_y
	mwa zs_hl g_ring_sparkle_sprite_y
	lda #$06
	sta g_ring_sparkle_sprite_countdown_timer
	lda #<$595D               ; TILEREPLACE_ring_blanking (adres SMS - dla renderera)
	sta g_screen_tile_replace_data_ptr
	lda #>$595D
	sta g_screen_tile_replace_data_ptr+1
	lda #$01
	jmp add_A_rings
scr_ret
	rts

; ---------------------------------------------------------------------
; sonic_dying: @sonic_is_dying (01:543C) - zamiast logiki ruchu, gdy Sonic umiera (iy_05 b0, kill_sonic).
; Bez kolizji z mapa (b5 flag). W ticku smierci (licznik restartu = $60) predkosc bez zmian. Gdy Sonic jest
; ponizej ekranu (sonic_y > scroll_y + $C0) - jednorazowo (iy_06 b2) zycie -1 i g_sonic_died_at_least_once.
; Inaczej (@dont_deduct_lives): pod woda (iy_08 b3) Vy = $00.80; Vy w gore (bajt lo b7) albo <= $0600
; -> Vy += $30 (DE = $0030, C = 0); Vy > $0600 -> bez zmiany; potem Vx = 0. Galaz oryginalu z bajtem lo Vy
; w $08..$7F (C bez inicjalizacji) jest nieosiagalna: lo >= 8 i b7 = 0 oznacza Vy > $0600.
; Koniec (@skip_sonic_vel_change_on_death): animacja $0B (pod woda $15), wspolna czesc od sa_misc
; (@continue_past_basic_movement_physics 01:4C39).
; ---------------------------------------------------------------------
sonic_dying
	lda sonic_flags_ix_24
	ora #$20                  ; set 5,(ix+24)
	sta sonic_flags_ix_24
	lda g_level_restart_countdown_timer
	cmp #$60
	jeq sd_anim
; HL = scroll_y + $C0 (C1 = przeniesienie z add hl,de); sbc hl,de odejmuje sonic_y i C1
	clc
	lda g_level_scroll_y_pix_lo
	adc #$C0
	sta zs_hl
	lda g_level_scroll_y_pix_lo+1
	adc #0
	sta zs_hl+1
	bcc sd_c0
	clc                       ; C1 = 1: dodatkowa pozyczka
	bcc sd_sub
sd_c0
	sec
sd_sub
	lda zs_hl
	sbc sonic_y
	lda zs_hl+1
	sbc sonic_y+1
	bcs sd_dont               ; bez pozyczki (Z80 nc): Sonic na ekranie -> @dont_deduct_lives
	lda iy_06_lvflag01
	and #$04
	bne sd_dont               ; zycie juz odjete
	lda #1
	sta g_sonic_died_at_least_once
	lda v_inflives            ; trainer: nieskonczone zycia - zycie nie jest odejmowane
	bne sd_keep
	dec g_lives
sd_keep
	lda iy_06_lvflag01
	ora #$04
	sta iy_06_lvflag01
	jmp sd_anim
sd_dont                         ; @dont_deduct_lives
	lda iy_08_lvflag03
	and #$08
	beq sd_vel
	lda #$80                  ; @select_sonic_drowning_y_vel_cap: HL = $0080, A = 0
	sta sonic_vel_y_sub
	lda #0
	sta sonic_vel_y
	sta sonic_vel_y_hi
	jmp sd_zero_vx
sd_vel
	lda sonic_vel_y           ; D (bajt lo Vy) b7 -> @skip_y_vel_cap_when_going_up_on_death
	bmi sd_add30
	cmp #6                    ; $0600 - DE: pozyczka (DE > $0600) -> @apply_sonic_y_vel_cap_on_death
	bcc sd_add30
	bne sd_zero_vx
	lda sonic_vel_y_sub
	bne sd_zero_vx
sd_add30                        ; @dont_cap_sonic_y_vel_on_death: (HL, B) += ($0030, 0)
	clc
	lda sonic_vel_y_sub
	adc #$30
	sta sonic_vel_y_sub
	lda sonic_vel_y
	adc #0
	sta sonic_vel_y
	lda sonic_vel_y_hi
	adc #0
	sta sonic_vel_y_hi
sd_zero_vx                      ; @apply_sonic_y_vel_cap_on_death: Vx = 0
	lda #0
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
sd_anim                         ; @skip_sonic_vel_change_on_death
	lda iy_08_lvflag03
	and #$08
	beq sd_anim_0b
	lda #$15
	bne sd_anim_set
sd_anim_0b
	lda #$0B
sd_anim_set
	sta sonic_anim_index_ix_20
	jmp sa_misc

; sh_inv_sparkle (@fn_handle_invincibility_sparkle_sprite 01:4E8D, M4.5): tmp_00 = sonic_x, tmp_02 = sonic_y,
; tmp_04..07 = bufor iskry (licznik b1: bufor 1 w D2F7, inaczej 0 w D2F3), draw_sprite kafla $96 (licznik b2)
; albo $94 - w porcie zapis dla renderera (v_isp, v_ispx, v_ispy: render/sprites.asm isparkle_obj; tablice
; sprite'ow Sonica rysuje renderer). Co 8 tickow nowe przesuniecia bufora wg b3 licznika: 2 x random_A & 15
; (slowa x, y).
sh_inv_sparkle
	lda sonic_x
	sta tmp_00
	lda sonic_x+1
	sta tmp_00+1
	lda sonic_y
	sta tmp_02
	lda sonic_y+1
	sta tmp_02+1
	ldx #0                    ; rrca x 2: C = b1 licznika
	lda g_global_tick_counter
	and #$02
	beq sis_b0
	ldx #4
sis_b0
	lda g_invincibility_sparkle_position_buffer_0,x ; ldi x 4: tmp_04..07 = bufor
	sta tmp_04
	lda g_invincibility_sparkle_position_buffer_0+1,x
	sta tmp_04+1
	lda g_invincibility_sparkle_position_buffer_0+2,x
	sta tmp_06
	lda g_invincibility_sparkle_position_buffer_0+3,x
	sta tmp_06+1
	ldy #$94                  ; rrca: C = b2 licznika -> kafel $96
	lda g_global_tick_counter
	and #$04
	beq sis_t
	ldy #$96
sis_t
	sty v_isp                 ; draw_sprite: kafel i pozycja (tmp_00 + tmp_04, tmp_02 + tmp_06) dla renderera
	clc
	lda tmp_00
	adc tmp_04
	sta v_ispx
	lda tmp_00+1
	adc tmp_04+1
	sta v_ispx+1
	clc
	lda tmp_02
	adc tmp_06
	sta v_ispy
	lda tmp_02+1
	adc tmp_06+1
	sta v_ispy+1
	lda g_global_tick_counter ; co 8 tickow: nowe przesuniecia (ret nz)
	and #$07
	bne sis_ret
	ldx #0                    ; bit 3,c: bufor 1
	lda g_global_tick_counter
	and #$08
	beq sis_r
	ldx #4
sis_r
	jsr random_A              ; zachowuje X
	and #$0F
	sta g_invincibility_sparkle_position_buffer_0,x
	lda #0
	sta g_invincibility_sparkle_position_buffer_0+1,x
	jsr random_A
	and #$0F
	sta g_invincibility_sparkle_position_buffer_0+2,x
	lda #0
	sta g_invincibility_sparkle_position_buffer_0+3,x
sis_ret
	rts

; sh_ring_sparkle (@fn_handle_ring_sparkle_sprites 01:4E51): licznik--, tmp_00..07 = pozycja i przesuniecia
; iskry (rysowanie draw_sprite - renderer M3.6)
sh_ring_sparkle
	dec g_ring_sparkle_sprite_countdown_timer
	lda g_ring_sparkle_sprite_countdown_timer
	ora #$80
	sta v_spk                 ; renderer: iskra rysowana w tym ticku (draw_sprite), b0-6 = licznik
	mwa g_ring_sparkle_sprite_x tmp_00
	mwa g_ring_sparkle_sprite_y tmp_02
	lda #0
	sta tmp_04
	sta tmp_04+1
	lda #$FE
	sta tmp_06
	lda #$FF
	sta tmp_06+1
	lda g_ring_sparkle_sprite_countdown_timer
	cmp #$03
	bcc srs_ret
	lda #$08                  ; druga iskra (po draw_sprite $B2)
	sta tmp_04
	lda #$02
	sta tmp_06
	lda #0
	sta tmp_06+1
srs_ret
	rts

; =====================================================================
;  Bloki specjalne (CODEPTRTAB_sonic_tile_specials 01:58E5): A = kod 0..$1B
; =====================================================================
sonic_special
	tax
	lda sp_tab_lo,x
	sta zs_t
	lda sp_tab_hi,x
	sta zs_t+1
	txa                       ; A = kod (sp_todo zapamietuje go w v_sonic_todo_spec)
	jmp (zs_t)

; adresy procedur kodow 00..$1B: przelozone kody z tablicy strefy GHZ (00-04, 08-0A), etapu specjalnego (11-16, M6.5), mostu Bridge
; (18-1A, M6.6), Jungle (05 sprezyna w prawo, 06/07 przenosniki, 0C przyspieszenie w wodzie, M6.7) i Labyrinth (0D-10 zjazdy, M6.8);
; Scrap Brain (0B teleport, 1B - M6.9), Sky Base (17 blyskawica SKY1 - M6.10); sp_todo - kod bez przekladu
sp_tab_lo
	dta l(sp_00, sp_01, sp_02, sp_03, sp_04, sp_05, sp_06, sp_07, sp_08, sp_09, sp_0a, sp_0b, sp_0c)
	dta l(sp_0d, sp_0e, sp_0f, sp_10)
	dta l(sp_11, sp_12, sp_13, sp_14, sp_15, sp_16, sp_17, sp_18, sp_19, sp_1a, sp_1b)
sp_tab_hi
	dta h(sp_00, sp_01, sp_02, sp_03, sp_04, sp_05, sp_06, sp_07, sp_08, sp_09, sp_0a, sp_0b, sp_0c)
	dta h(sp_0d, sp_0e, sp_0f, sp_10)
	dta h(sp_11, sp_12, sp_13, sp_14, sp_15, sp_16, sp_17, sp_18, sp_19, sp_1a, sp_1b)

sp_todo                         ; blok specjalny bez przekladu (inne strefy - M6)
	sta v_sonic_todo_spec
	lda #TODO_SPECIAL
	jmp sonic_todo_call

sp_17                           ; M6.10 @special_17 (01:57F6-01:5807, bloki SKY 1E-26, 2A): g_lightning_timer >= $82 (16 bit, and a /
	lda g_lightning_timer+1   ; sbc hl,de / ret c) i Sonic zyje (bit 0,(iy+5) = 0) -> damage_sonic (jp z)
	bne sp17_hit
	lda g_lightning_timer
	cmp #$82
	bcc sp17_ret
sp17_hit
	lda iy_05_lvflag00
	lsr
	bcs sp17_ret
	jmp damage_sonic
sp17_ret
	rts

sp_01                           ; @special_01_spikes (01:54C6): Sonic zyje -> damage_sonic
	lda iy_05_lvflag00
	lsr
	bcs sp01_ret              ; b0 = umiera
	jmp damage_sonic
sp01_ret
	rts

sp_00                           ; @special_00_nothing: poza poziomem z woda b4 flag = 0
	lda iy_06_lvflag01
	bmi sp00_ret
	lda sonic_flags_ix_24
	and #$EF
	sta sonic_flags_ix_24
sp00_ret
	rts

sp_02                           ; @special_02_end_of_ramp_jump: wybicie z konca rampy
	lda sonic_x
	clc
	adc #$0C
	and #$1F
	cmp #$1A                  ; tylko w ostatnich 6 px bloku
	bcc sp02_ret
	lda sonic_flags_ix_24
	lsr                       ; rrca: b0 (toczenie) -> C
	bcs sp02_go
	and #$02                  ; po rrca w b1 jest b2 flag (w powietrzu po skoku) - and $02 oryginalu
	beq sp02_ret
sp02_go                         ; @continue_end_of_ramp_jump: Vx >= $0301 (sub, lo), hi >= 0
	lda sonic_vel_x_hi
	bmi sp02_ret
	lda sonic_vel_x_sub
	cmp #$01
	lda sonic_vel_x
	sbc #$03
	bcc sp02_ret
; Vy = -(Vx (lo, hi) * 2): (ix+10) = 0, (ix+11) = L, (ix+12) = H
	lda sonic_vel_x
	asl
	sta zs_hl
	lda sonic_vel_x_hi
	rol
	sta zs_hl+1
	lda zs_hl
	eor #$FF
	clc
	adc #1
	sta sonic_vel_y
	lda zs_hl+1
	eor #$FF
	adc #0
	sta sonic_vel_y_hi
	lda #0
	sta sonic_vel_y_sub
	lda #$05                  ; rst $28 (01:550B)
	jsr play_sfx
sp02_ret
	rts

sp_03                           ; @special_03_spring_left_8_px_t: sprezyna w lewo (Vx = -8 px/tick)
	lda sonic_x
	clc
	adc #$0C
	and #$1F
	cmp #$10                  ; tylko w prawej polowie bloku
	bcc sp03_ret
	lda #$00
	sta sonic_vel_x_sub
	lda #$F8
	sta sonic_vel_x
	lda #$FF
	sta sonic_vel_x_hi
	lda sonic_flags_ix_24
	ora #$02                  ; twarza w lewo
	sta sonic_flags_ix_24
	lda #$04                  ; rst $28: sprezyna (01:5529)
	jsr play_sfx
sp03_ret
	rts

; @special_05_spring_right_8_px_t (01:5556): sprezyna w prawo w lewej polowie bloku: Vx = +8 px/tick, twarz w prawo, efekt $04
sp_05
	lda sonic_x
	clc
	adc #$0C
	and #$1F
	cmp #$10
	bcs sp05_ret
	lda iy_06_lvflag01
	and #$BF                  ; res 6
	sta iy_06_lvflag01
	lda #0
	sta sonic_vel_x_sub
	sta sonic_vel_x_hi
	lda #$08
	sta sonic_vel_x
	lda sonic_flags_ix_24
	and #$FD                  ; res 1
	sta sonic_flags_ix_24
	lda #$04                  ; rst $28
	jmp play_sfx
sp05_ret
	rts

; @special_06_conveyor_left / 07_conveyor_right (01:5578 / 01:5590): na ziemi (b7 flag) x (24 bit: sub, lo, hi) += $FFFE80 / $000200
sp_06
	bit sonic_flags_ix_24
	bpl sp06_ret
	clc
	lda sonic_x_sub
	adc #$80
	sta sonic_x_sub
	lda sonic_x
	adc #$FE
	sta sonic_x
	lda sonic_x+1
	adc #$FF
	sta sonic_x+1
sp06_ret
	rts
sp_07
	bit sonic_flags_ix_24
	bpl sp06_ret
	clc
	lda sonic_x_sub
	adc #$00
	sta sonic_x_sub
	lda sonic_x
	adc #$02
	sta sonic_x
	lda sonic_x+1
	adc #$00
	sta sonic_x+1
	rts

; @special_0C_underwater_accel_left_8_subpx_t2 (01:565C): Vx (24 bit) += $FFFFF8; przy wejsciu (b4 flag = 0) plusk $12; b4 = 1
sp_0c
	clc
	lda sonic_vel_x_sub
	adc #$F8
	sta sonic_vel_x_sub
	lda sonic_vel_x
	adc #$FF
	sta sonic_vel_x
	lda sonic_vel_x_hi
	adc #$FF
	sta sonic_vel_x_hi
	lda sonic_flags_ix_24
	and #$10
	bne sp0c_in
	lda #$12                  ; rst $28
	jsr play_sfx
sp0c_in
	lda sonic_flags_ix_24
	ora #$10
	sta sonic_flags_ix_24
	rts

; ---------------------------------------------------------------------
; Zjazdy wodne LAB (M6.8): @special_0D_slide_right_5_px_t (01:567C), _0E_slide_right_6_px_t (01:56A6), _0F_slide_left_5_px_t (01:56B6),
; _10_slide_left_6_px_t (01:56C6). Vx: sub = 0 (xor a), ld (sonic_vel_x),hl - lo = 5 / 6 / $FB / $FA, hi = 0 / 0 / $FF / $FF; kierunek
; (b1 flag: 0 = w prawo - res 1, 1 = w lewo - set 1); @set_directional_input_suppression (01:568A): licznik blokady kierunkow = 6,
; dalej @fn_enforce_directional_input_suppression (01:568F = sh_enforce_input_suppression: bez kierunkow, Vy lo/hi = 4/0,
; koniec toczenia i skoku - res 0 / res 2). Bez warunku polozenia w bloku i bez sprawdzania ziemi.
; ---------------------------------------------------------------------
sp_0d
	lda #$05
	bne sp_slide_r            ; zawsze
sp_0e
	lda #$06
sp_slide_r
	ldx #$00                  ; hi = 0
	sta sonic_vel_x
	stx sonic_vel_x_hi
	stx sonic_vel_x_sub
	lda sonic_flags_ix_24
	and #$FD                  ; res 1,(ix+24): twarza w prawo
	jmp sp_slide
sp_0f
	lda #$FB
	bne sp_slide_l            ; zawsze
sp_10
	lda #$FA
sp_slide_l
	ldx #$FF                  ; hi = $FF
	sta sonic_vel_x
	stx sonic_vel_x_hi
	ldx #$00
	stx sonic_vel_x_sub
	lda sonic_flags_ix_24
	ora #$02                  ; set 1,(ix+24): twarza w lewo
sp_slide                        ; @set_directional_input_suppression
	sta sonic_flags_ix_24
	lda #$06
	sta g_directional_input_suppression_timer
	jmp sh_enforce_input_suppression

; @special_04_spring_up_12_px_t (01:552D): sprezyna w gore w prawej polowie bloku; Sonic na ziemi teraz
; (flagi b7), a w poprzednim ticku w powietrzu (g_sonic_flags_copy b7 = 0, czyli wlasnie wyladowal)
; -> Vy = -12 px/tick
sp_04
	lda sonic_x
	clc
	adc #$0C
	and #$1F
	cmp #$10                  ; < $10 -> ret c
	bcc sp04_ret
	bit sonic_flags_ix_24     ; b7 = 0 (w powietrzu) -> ret z
	bpl sp04_ret
	bit g_sonic_flags_copy    ; and $80 / ret nz
	bmi sp04_ret
	jmp sp_spring_up
sp04_ret
	rts

; @special_08_underwater (01:55A8): b4 flag (pod woda) = 1; przy wejsciu (b4 = 0) plusk
sp_08
	lda sonic_flags_ix_24
	and #$10
	bne sp08_in
	lda #$12                  ; rst $28: plusk (01:55AE)
	jsr play_sfx
sp08_in
	lda sonic_flags_ix_24
	ora #$10
	sta sonic_flags_ix_24
	rts

; @special_09_spring_up_12_px_t (01:55B6): jak 04, ale srodek bloku ($08 <= (x + 12) & $1F < $18)
sp_09
	lda sonic_x
	clc
	adc #$0C
	and #$1F
	cmp #$08
	bcc sp09_ret
	cmp #$18
	bcs sp09_ret
	bit sonic_flags_ix_24
	bpl sp09_ret
	bit g_sonic_flags_copy
	bmi sp09_ret
	jmp sp_spring_up
sp09_ret
	rts

; @special_0A_GHZ2_falling_sfx (01:55E2): tylko dzwiek przy spadaniu (Vy hi >= 0)
sp_0a
	bit sonic_vel_y_hi
	bmi sp0a_ret
	lda #$05                  ; rst $28 (01:55E7)
	jmp play_sfx
sp0a_ret
	rts

; ---------------------------------------------------------------------
; Zawalajacy sie most (M6.6, Bridge): kody blokow $18 (obie polowki), $19 (tylko prawa), $1A (tylko lewa). Sonic na ziemi (b7 flag)
; stoi na polowce bloku: lewa ((x + 12) & $1F < $10) albo prawa. Powstaje obiekt $2E (spadajacy element 16 x 8: x = poczatek polowki,
; y = (sonic_y + $10) & $FFE0) i blok ukladu pod stopami zmienia sie: lewa polowka znika - $89 (blok z samej prawej polowki; gdy
; prawej juz nie ma ($8A) - 0), prawa znika - $8A (gdy lewej nie ma ($89) - 0). Brak wolnego slotu - bez zmiany.
; ---------------------------------------------------------------------
sp_18                           ; @special_18_collapsing_bridge_both_sides (01:5808)
	lda sonic_flags_ix_24
	bpl sp18_ret              ; rlca / ret nc: w powietrzu
	jsr sp_bridge_x
	and #$1F
	cmp #$10
	bcs sp_br_right
	jmp sp_br_left
sp18_ret
	rts
sp_19                           ; @special_19_collapsing_bridge_right_only (01:584B)
	jsr sp_bridge_x
	and #$1F
	cmp #$10
	bcc sp18_ret
	jmp sp_br_right
sp_1a                           ; @special_1A_collapsing_bridge_left_only (01:5883)
	jsr sp_bridge_x
	and #$1F
	cmp #$10
	bcs sp18_ret
sp_br_left                      ; @collapsing_bridge_continue_left_side: BC = (x + 12) & $FFE0, DE = (y + $10) & $FFE0
	jsr sp_bridge_x
	and #$E0
	sta zg_bc
	jsr sp_bridge_y
	jsr sp_bridge_spawn
	bcs sp18_ret
	jsr sp_bridge_tile
	bcs sp18_ret
	ldx #0                    ; c = 0; blok $8A (prawej polowki juz nie ma) -> 0, inaczej $89
	cmp #$8A
	beq sp_br_put
	ldx #$89
sp_br_put
	txa
	ldy #0
	sta (zg_ptr),y
	rts
sp_br_right                     ; @collapsing_bridge_continue_right_side: BC = ((x + 12) & $FFE0) + $10
	jsr sp_bridge_x
	and #$E0
	clc
	adc #$10
	sta zg_bc
	jsr sp_bridge_y
	jsr sp_bridge_spawn
	bcs sp18_ret
	jsr sp_bridge_tile
	bcs sp18_ret
	ldx #0                    ; blok $89 (lewej polowki juz nie ma) -> 0, inaczej $8A
	cmp #$89
	beq sp_br_put
	ldx #$8A
	bne sp_br_put             ; zawsze
; sp_bridge_x: zs_hl = sonic_x + 12; zg_bc+1 = starszy bajt; A = mlodszy bajt
sp_bridge_x
	clc
	lda sonic_x
	adc #$0C
	sta zs_hl
	lda sonic_x+1
	adc #0
	sta zs_hl+1
	sta zg_bc+1
	lda zs_hl
	rts
; sp_bridge_y: DE = (sonic_y + $10) & $FFE0
sp_bridge_y
	clc
	lda sonic_y
	adc #$10
	and #$E0
	sta zg_de
	lda sonic_y+1
	adc #0
	sta zg_de+1
	rts
; sp_bridge_spawn: spawn_falling_bridge_piece (01:5893): obiekt $2E w pierwszym wolnym slocie (x = BC, y = DE, predkosc 0, flagi 0);
; C = 1 brak slotu
sp_bridge_spawn
	jsr spawn_object
	bcs sbs_ret
	ldy #OB_TYPE
	lda #$2E
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y            ; +1
	iny
	lda zg_bc
	sta (zg_ptr),y            ; +2, +3: x
	iny
	lda zg_bc+1
	sta (zg_ptr),y
	iny
	lda #0
	sta (zg_ptr),y            ; +4
	iny
	lda zg_de
	sta (zg_ptr),y            ; +5, +6: y
	iny
	lda zg_de+1
	sta (zg_ptr),y
	lda #0
	ldy #7
sbs_z
	sta (zg_ptr),y            ; +7..+12: Vx, Vy = 0
	iny
	cpy #13
	bne sbs_z
	ldy #OB_FLAGS
	sta (zg_ptr),y
	clc
sbs_ret
	rts
; sp_bridge_tile: bajt ukladu pod stopami (x + 12, y + 16) Sonica (obj_tile_ptr dla zg_obj = Sonic): A = numer bloku, zg_ptr = adres;
; C = 1 adres ROM
sp_bridge_tile
	mwa #$000C zg_bc
	mwa #$0010 zg_de
	jsr obj_tile_ptr
	bcs sbtl_ret
	ldy #0
	lda (zg_ptr),y
	clc
sbtl_ret
	rts

; ---------------------------------------------------------------------
; Etap specjalny (M6.5): @special_11_bumper (01:56D6), 12-14 sprezyny (01:5761-5781), 15 belka srodkowa (01:5791),
; 16 koniec belki (01:57CD), @fn_apply_special_stage_bouncies_x_vel (01:5727)
; ---------------------------------------------------------------------
; sh_bumper (01:5231): licznik zderzaka - 1; przy < 6 albo >= $0A zderzak (2 x 4 sprite'y 8x16) w wpisach 0-7 tablicy sprite'ow
; (g_next_avail_vdp_sprite_ptr = poczatek tablicy; licznik i wskaznik potem przywrocone) - w pozycji anim_sprite - przewijanie;
; v_throb = 1: renderer rysuje wpisy 0-7 zamiast Sonica (wpisy 0-5 to w oryginale sprite'y Sonica, nadpisane)
sh_bumper
	dec g_special_stage_round_bumper_cooldown_timer
	lda g_special_stage_round_bumper_cooldown_timer
	cmp #$06
	bcc sbt_show
	cmp #$0A
	bcc sbt_ret               ; ret c
sbt_show
	lda g_sprite_count
	pha
	lda g_next_avail_vdp_sprite_ptr
	pha
	lda g_next_avail_vdp_sprite_ptr+1
	pha
	lda #<SPRTAB_R
	sta g_next_avail_vdp_sprite_ptr
	lda #>SPRTAB_R
	sta g_next_avail_vdp_sprite_ptr+1
	sec                       ; DE = anim_sprite_y - scroll_y, HL = anim_sprite_x - scroll_x
	lda g_special_stage_round_bumper_anim_sprite_y
	sbc g_level_scroll_y_pix_lo
	sta zd_y
	lda g_special_stage_round_bumper_anim_sprite_y+1
	sbc g_level_scroll_y_pix_lo+1
	sta zd_y+1
	sec
	lda g_special_stage_round_bumper_anim_sprite_x
	sbc g_level_scroll_x_pix_lo
	sta zd_x
	lda g_special_stage_round_bumper_anim_sprite_x+1
	sbc g_level_scroll_x_pix_lo+1
	sta zd_x+1
	jsr bumper_draw
	pla
	sta g_next_avail_vdp_sprite_ptr+1
	pla
	sta g_next_avail_vdp_sprite_ptr
	pla
	sta g_sprite_count
	lda #1
	sta v_throb
sbt_ret
	rts

sp_11
	lda g_special_stage_round_bumper_cooldown_timer
	cmp #$08
	bcs sp11_ret              ; ret nc
	jsr sp_bounce_x
	jsr sp_bounce_y
	clc                       ; anim_sprite_x = (sonic_x + $0C) & $FFE0, anim_sprite_y = (sonic_y + $10) & $FFE0
	lda sonic_x
	adc #$0C
	sta zs_t
	lda sonic_x+1
	adc #0
	sta g_special_stage_round_bumper_anim_sprite_x+1
	lda zs_t
	and #$E0
	sta g_special_stage_round_bumper_anim_sprite_x
	clc
	lda sonic_y
	adc #$10
	sta zs_t
	lda sonic_y+1
	adc #0
	sta g_special_stage_round_bumper_anim_sprite_y+1
	lda zs_t
	and #$E0
	sta g_special_stage_round_bumper_anim_sprite_y
	lda #$10
	sta g_special_stage_round_bumper_cooldown_timer
	lda #$07
	jmp play_sfx
sp11_ret
	rts

sp_12                           ; sprezyna w gore 10 px/tick (Vy = $FFF600), efekt $04
	lda #$F6
	bne sp_vy_up
sp_13                           ; 12 px/tick
	lda #$F4
	bne sp_vy_up
sp_14                           ; 14 px/tick
	lda #$F2
sp_vy_up
	sta sonic_vel_y
	lda #$00
	sta sonic_vel_y_sub
	lda #$FF
	sta sonic_vel_y_hi
	lda #$04
	jmp play_sfx

sp_15                           ; belka srodkowa: bez migania palety - Vx = -Vx, wartosc bezwzgledna + 1 px/tick
	lda g_pal_flash_countdown_timer
	bne sp15_ret              ; ret nz
	sec                       ; Vx = 0 - Vx (24 bity)
	lda #0
	sbc sonic_vel_x_sub
	sta sonic_vel_x_sub
	lda #0
	sbc sonic_vel_x
	sta sonic_vel_x
	lda #0
	sbc sonic_vel_x_hi
	sta sonic_vel_x_hi
	bmi sp15_neg              ; jp m: de = $FF00, c = $FF
	clc                       ; de = $0100, c = 0
	lda sonic_vel_x
	adc #$01
	sta sonic_vel_x
	lda sonic_vel_x_hi
	adc #0
	sta sonic_vel_x_hi
	jmp sp_bounce_flash
sp15_neg
	sec
	lda sonic_vel_x
	sbc #$01
	sta sonic_vel_x
	lda sonic_vel_x_hi
	sbc #0
	sta sonic_vel_x_hi
	jmp sp_bounce_flash
sp15_ret
	rts

sp_16                           ; koniec belki: odbicie X (x 1,5) i Y jak zderzak, miganie palety
	jsr sp_bounce_x
	jsr sp_bounce_y
sp_bounce_flash                 ; @continue_from_other_bouncies (01:57BE): miganie koloru $0E na $3F (4 ticki), efekt $07
	lda #$04
	sta g_pal_flash_countdown_timer
	lda #$0E
	sta g_pal_flash_idx
	lda #$3F
	sta g_pal_flash_color_value
	lda #$07
	jmp play_sfx

; sp_bounce_y: Vy = -Vy (24 bity); wynik ujemny (w gore): dodatkowo -$38 (01:56DF-56FF)
sp_bounce_y
	sec
	lda #0
	sbc sonic_vel_y_sub
	sta sonic_vel_y_sub
	lda #0
	sbc sonic_vel_y
	sta sonic_vel_y
	lda #0
	sbc sonic_vel_y_hi
	sta sonic_vel_y_hi
	bpl spby_ret              ; jp p: dol - bez zmiany
	clc
	lda sonic_vel_y_sub
	adc #$C8
	sta sonic_vel_y_sub
	lda sonic_vel_y
	adc #$FF
	sta sonic_vel_y
	lda sonic_vel_y_hi
	adc #$FF
	sta sonic_vel_y_hi
spby_ret
	rts

; sp_bounce_x (01:5727): znak Vx zgodny z polowa bloku ((x + 12) & $1F < $10 = lewa polowa: Vx < 0) - bez odwrocenia,
; inaczej Vx = ~Vx; potem + 1 i Vx = Vx + Vx / 2 (sra: przesuniecie arytmetyczne 24 bitow)
sp_bounce_x
	lda sonic_vel_x_sub
	sta zs_hl
	lda sonic_vel_x
	sta zs_hl+1
	lda sonic_vel_x_hi
	sta zs_c                  ; C
	and #$80
	sta zs_b                  ; B = znak Vx
	lda sonic_x
	clc
	adc #$0C
	and #$1F
	sec
	sbc #$10
	and #$80                  ; $80 = lewa polowa bloku
	cmp zs_b
	beq spbx_noinv
	lda zs_hl
	eor #$FF
	sta zs_hl
	lda zs_hl+1
	eor #$FF
	sta zs_hl+1
	lda zs_c
	eor #$FF
	sta zs_c
spbx_noinv
	inc zs_hl                 ; + 1 (24 bity)
	bne spbx_sh
	inc zs_hl+1
	bne spbx_sh
	inc zs_c
spbx_sh
	lda zs_hl
	sta zs_de
	lda zs_hl+1
	sta zs_de+1
	lda zs_c
	cmp #$80                  ; sra c: C = bit 7
	ror
	sta zs_t
	ror zs_de+1               ; rr d
	ror zs_de                 ; rr e
	clc
	lda zs_hl
	adc zs_de
	sta sonic_vel_x_sub
	lda zs_hl+1
	adc zs_de+1
	sta sonic_vel_x
	lda zs_c
	adc zs_t
	sta sonic_vel_x_hi
	rts

; wspolny koniec sprezyn w gore (04, 09): res 6 iy_06, Vy = $FFF400 (-12 px/tick)
sp_spring_up
	lda iy_06_lvflag01
	and #$BF
	sta iy_06_lvflag01
	lda #$00
	sta sonic_vel_y_sub
	lda #$F4
	sta sonic_vel_y
	lda #$FF
	sta sonic_vel_y_hi
	lda #$04                  ; rst $28: sprezyna (01:5552 / 01:55DE)
	jmp play_sfx

; ---------------------------------------------------------------------
; zaslepki: sonic_todo_call - licznik i dalej (call oryginalu); sonic_todo - licznik i koniec funkcji
; (jp oryginalu do sciezki bez przekladu). A = TODO_*.
; ---------------------------------------------------------------------
sonic_todo_call
	sta v_sonic_todo_id
	inc v_sonic_todo
	rts
sonic_todo
	sta v_sonic_todo_id
	inc v_sonic_todo
	rts

; =====================================================================
;  M6.9 Scrap Brain: teleport (kod bloku 0B + licznik startu) i kod 1B
; =====================================================================

; sp_0b (@special_0B_teleport 01:55EB-01:5642): gdy teleport nie trwa (iy_06 b4 = 0) i Sonic stoi na srodkowej polowie bloku
; ((x + 12) & $1F w [8, $18)): blok Sonica E = (x + 12) >> 5, D = (y + 16) >> 5 (bajty) szukany w 5 wpisach tablicy
; @special_0B_teleport_specs (01:5643: bx, by, cel X, cel Y, poziom). Trafienie: g_teleport_spec_dest_ptr = adres SMS wpisu + 2
; (stan RAM jak w oryginale), g_teleport_start_countdown_timer = $50, SFX $06. Tablica (25 B, bank 1 poza regionem SONIC_ANIM) - kopia.
TELE_SMS = $5643
sp_0b
	lda iy_06_lvflag01        ; bit 4,(iy+6) / ret nz
	and #$10
	bne s0b_ret
	clc                       ; a = (x & $FF) + $0C, & $1F
	lda sonic_x
	adc #$0C
	and #$1F
	cmp #$08                  ; ret c
	bcc s0b_ret
	cmp #$18                  ; ret nc
	bcs s0b_ret
	clc                       ; hl = x + $000C; hl << 3 (add a,a / rl h) -> e = h
	lda sonic_x
	adc #$0C
	sta zs_t
	lda sonic_x+1
	adc #0
	ldx #3
s0b_sx
	asl zs_t
	rol
	dex
	bne s0b_sx
	sta zs_de                 ; E = blok X
	clc                       ; hl = y + $0010; hl << 3 -> d = h
	lda sonic_y
	adc #$10
	sta zs_t
	lda sonic_y+1
	adc #0
	ldx #3
s0b_sy
	asl zs_t
	rol
	dex
	bne s0b_sy
	sta zs_de+1               ; D = blok Y
	ldx #0                    ; @find_teleport_region: b = 5 wpisow po 5 B
s0b_find
	lda tele_specs,x
	cmp zs_de
	bne s0b_next
	lda tele_specs+1,x
	cmp zs_de+1
	bne s0b_next
	txa                       ; inc hl / ld (g_teleport_spec_dest_ptr),hl: adres SMS wpisu + 2
	clc
	adc #<[TELE_SMS+2]
	sta g_teleport_spec_dest_ptr
	lda #>[TELE_SMS+2]
	adc #0
	sta g_teleport_spec_dest_ptr+1
	lda #$50
	sta g_teleport_start_countdown_timer
	lda #$06                  ; rst $28: SFX $06
	jmp play_sfx
s0b_next
	txa                       ; @not_this_teleport_region: nastepny wpis
	clc
	adc #5
	tax
	cpx #25
	bcc s0b_find
s0b_ret
	rts
; @special_0B_teleport_specs (01:5643): $14/$17 (52, 60) -> (52, 47) ten sam poziom; $15 (25, 58) -> (25, 4) ten sam; (14, 58) -> $16;
; (27, 50) -> $17; SKY3 (47, 12) -> $FF (nastepny poziom, iy_0D b2 - M6.10)
tele_specs
	dta b($34, $3C, $34, $2F, $00)
	dta b($19, $3A, $19, $04, $00)
	dta b($0E, $3A, $00, $00, $16)
	dta b($1B, $32, $00, $00, $17)
	dta b($2F, $0C, $00, $00, $FF)

; sp_1b (@special_1B 01:58D0-01:58E4): Sonic na ziemi (ix+24 b7) i powyzej gornej krawedzi kamery (sonic_y < scroll_y, 16 bit)
; -> wejscie gracza $FF (nic nie wcisniete) w tym ticku
sp_1b
	bit sonic_flags_ix_24     ; bit 7,(ix+24) / ret z
	bpl s1b_ret
	sec                       ; hl = sonic_y - scroll_y: bez pozyczki -> ret nc
	lda sonic_y
	sbc g_level_scroll_y_pix_lo
	lda sonic_y+1
	sbc g_level_scroll_y_pix_lo+1
	bcs s1b_ret
	lda #$FF                  ; ld (iy+g_inputs_player_1),$FF
	sta g_inputs_player_1
s1b_ret
	rts

; sh_tele_in (M6.11, @handle_ending_animation_teleport_in 01:5193-01:51B2): poziom koncowy $12 (iy_08 b6 - ustawia kontroler $53) - Sonic
; pojawia sie z animacja $16: Vy = 0 (24 bit), (ix+20) = $16; gdy pozycja w sekwencji (ix+19) >= $12: res 6,(iy+8), set 2,(ix+24) (kula).
; Zawsze dalej @continue_past_basic_movement_physics (sa_misc).
sh_tele_in
	lda #0
	sta sonic_vel_y_sub
	sta sonic_vel_y_sub+1
	sta sonic_vel_y_sub+2
	lda #$16
	sta sonic_anim_index_ix_20
	lda sonic_anim_sprite_subindex_ix_19
	cmp #$12
	bcc sti_ret               ; jp c
	lda iy_08_lvflag03
	and #$BF
	sta iy_08_lvflag03
	lda sonic_flags_ix_24
	ora #$04
	sta sonic_flags_ix_24
sti_ret
	jmp sa_misc

; sh_good_end (M6.11, @fn_handle_good_ending_sequence 01:529C-01:532D; iy_08 b7 - ustawia kontroler $53 przy >= 6 szmaragdach): wejscie $FB
; (w lewo); dopiero przy x < $1B60 wejscie $FF i - gdy Vx (sub, lo) = 0 - Sonic stoi twarza w lewo (set 1,(ix+24)), animacja $18 i reszta
; jego logiki pominieta (pop hl -> C = 1). Pierwszy raz (iy_0D b0 = 0): licznik $50 i szmaragd $54 (spawn_object; brak slotu - tylko C = 1)
; w (x + 2, y + 14), iy_0D b0. Potem licznik w dol do 0 -> iy_0D b1, licznik $8C, animacja $17 do 0 licznika, dalej $19. C = 0: zwykly ret.
sh_good_end
	lda #$FB                  ; ld (iy+g_inputs_player_1),$FB
	sta g_inputs_player_1
	lda sonic_x+1             ; sonic_x - $1B60: nc -> ret
	cmp #$1B
	bcc sge_lt
	bne sge_r0
	lda sonic_x
	cmp #$60
	bcc sge_lt
sge_r0
	clc
	rts
sge_lt
	lda #$FF
	sta g_inputs_player_1
	lda sonic_vel_x_sub       ; ld hl,(sonic_vel_x_sub) / ld a,l / or h / ret nz
	ora sonic_vel_x_sub+1
	bne sge_r0
	lda sonic_flags_ix_24     ; res 1 / pop hl / set 1,(ix+24)
	ora #$02
	sta sonic_flags_ix_24
	lda #$18
	sta sonic_anim_index_ix_20
	lda iy_0D
	lsr                       ; bit 0,(iy+$0D)
	bcs sge_spawned
	lda #$50
	sta g_good_ending_emerald_anim_countdown_timer
	jsr spawn_object
	bcs sge_c1                ; jp c,@continue_past_basic_movement_physics
	ldy #0
	lda #$54                  ; (ix+0) = $54
	sta (zg_ptr),y
	lda #0
	ldy #17
	sta (zg_ptr),y            ; (ix+17) = 0
	ldy #24
	sta (zg_ptr),y            ; (ix+24) = 0
	ldy #1
	sta (zg_ptr),y            ; (ix+1) = 0
	clc
	lda sonic_x
	adc #2
	iny
	sta (zg_ptr),y            ; (ix+2/3) = sonic_x + 2
	lda sonic_x+1
	adc #0
	iny
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y            ; (ix+4) = 0
	clc
	lda sonic_y
	adc #$0E
	iny
	sta (zg_ptr),y            ; (ix+5/6) = sonic_y + $0E
	lda sonic_y+1
	adc #0
	iny
	sta (zg_ptr),y
	lda iy_0D
	ora #$01
	sta iy_0D
sge_c1
	sec
	rts
sge_spawned
	lda iy_0D                 ; bit 1,(iy+$0D)
	and #$02
	bne sge_a0
	dec g_good_ending_emerald_anim_countdown_timer
	bne sge_c1
	lda iy_0D
	ora #$02
	sta iy_0D
	lda #$8C
	sta g_good_ending_emerald_anim_countdown_timer
sge_a0
	lda #$17                  ; @good_ending_emerald_anim_0_already_done
	sta sonic_anim_index_ix_20
	lda g_good_ending_emerald_anim_countdown_timer
	beq sge_a1
	dec g_good_ending_emerald_anim_countdown_timer
	sec
	rts
sge_a1
	lda #$19
	sta sonic_anim_index_ix_20
	sec
	rts

; sh_teleport (@handle_teleport_start 01:5117-01:5192): A = g_teleport_start_countdown_timer (> 0). Licznik - 1:
;  0 -> @do_teleport (koniec funkcji Sonika w tym ticku - ret oryginalu: rts z sonic_objfunc, bo tu sie skacze jmp);
;  < $14 -> res 1,(ix+24), animacja $0E (znikanie); inaczej V = 0 (X i Y, 24 bit), animacja $0F (wirowanie).
;  Oba ostatnie -> @continue_past_basic_movement_physics (01:4C39 = sa_misc).
; @do_teleport: wpis tablicy (g_teleport_spec_dest_ptr - adres SMS w 01:5643): cel X, cel Y, poziom. Poziom 0 -> ten sam: sonic_x =
; X * 32 + 8, sonic_y = Y * 32, subpiksele 0; ujemny ($FF) -> iy_0D b2; inny -> g_next_level_override_target, iy_06 b4; obie ostatnie
; -> g_signpost_tickdown_counter = 1 (przejscie bez wyniku i mapy - game/trans.asm, M6.9 krok 6).
sh_teleport
	sec
	sbc #1
	sta g_teleport_start_countdown_timer
	beq sht_do                ; jr z,@do_teleport
	cmp #$14                  ; jr c,@do_teleport_spin_effect
	bcc sht_spin
	lda #0                    ; xor a / ld l,a / ld h,a: Vx = Vy = 0
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
	sta sonic_vel_y_sub
	sta sonic_vel_y
	sta sonic_vel_y_hi
	lda #$0F                  ; ld (ix+20),$0F
	sta sonic_anim_index_ix_20
	jmp sa_misc
sht_spin
	lda sonic_flags_ix_24     ; res 1,(ix+24)
	and #$FD
	sta sonic_flags_ix_24
	lda #$0E                  ; ld (ix+20),$0E
	sta sonic_anim_index_ix_20
	jmp sa_misc
sht_do
	sec                       ; indeks wpisu w kopii tablicy = adres SMS - TELE_SMS (wskazuje cel X)
	lda g_teleport_spec_dest_ptr
	sbc #<TELE_SMS
	tax
	lda tele_specs,x          ; b = cel X
	sta zs_b
	lda tele_specs+1,x        ; c = cel Y
	sta zs_c
	lda tele_specs+2,x        ; a = poziom; and a
	beq sht_same              ; jr z,@teleport_is_in_same_level
	bmi sht_next              ; jp m,@teleport_advance_to_next_level
	sta g_next_level_override_target
	lda iy_06_lvflag01        ; set 4,(iy+6)
	ora #$10
	sta iy_06_lvflag01
	bne sht_sign              ; zawsze
sht_next
	lda iy_0D                 ; set 2,(iy+$0D)
	ora #$04
	sta iy_0D
sht_sign
	lda #$01                  ; g_signpost_tickdown_counter = 1
	sta g_signpost_tickdown_counter
	rts
sht_same
	lda #0                    ; sonic_x = b << 5 (16 bit) + 8
	sta zs_hl+1
	lda zs_b
	ldx #5
sht_xs
	asl
	rol zs_hl+1
	dex
	bne sht_xs
	clc
	adc #$08
	sta sonic_x
	lda zs_hl+1
	adc #0
	sta sonic_x+1
	lda #0                    ; sonic_y = c << 5 (16 bit)
	sta zs_hl+1
	lda zs_c
	ldx #5
sht_ys
	asl
	rol zs_hl+1
	dex
	bne sht_ys
	sta sonic_y
	lda zs_hl+1
	sta sonic_y+1
	lda #0                    ; xor a: subpiksele X i Y = 0
	sta sonic_x_sub
	sta sonic_y_sub
	rts
