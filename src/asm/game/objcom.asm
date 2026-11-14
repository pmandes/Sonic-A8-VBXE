; =====================================================================
;  objcom.asm - M4.1: procedury gry wolane przez obiekty (bank 45) i przez Sonica - kod rezydentny $8000+
;  (przy wlaczonym banku obiektow kod pod $4100 jest niewidoczny). Przeniesione z game/sonic.asm bez zmian:
;  play_music / play_sfx (rst $18 / rst $28), add_A_rings (00:39AC), kill_sonic (00:3618), damage_sonic
;  (00:35FD) z make_sonic_throw_his_rings i make_sonic_stunned_after_hit, spawn_object (01:7C7B).
;  Nowe: random_A (00:0625), level_mask (calc_level_offset_HL_and_mask_C 00:0C02), objects_tick (wlacza
;  bank obiektow na czas aktywacji i funkcji obiektow 1..31).
; =====================================================================

; play_music (rst $18 -> di_call_s1_b03_4012_a_DI 00:02D7): A = utwor -> g_current_music; odtwarzanie
; (M5.2): sound/music.asm - rezydentne, na chwile wlacza bank muzyki
play_music
	sta g_current_music
	jmp snd_music_play

; play_sfx (rst $28 -> play_sound_effect_a_DI 00:02FE): A = efekt (M5.4, sound/sfx.asm); zachowuje X, Y
play_sfx
	jmp snd_sfx_play

; add_A_rings (00:39AC): g_rings_BCD += A (BCD); przy 100 -> 0 i zycie; dzwiek $09 (zycie) albo $02
add_A_rings
	clc
	adc g_rings_BCD
	sta zs_c
	and #$0F
	cmp #$0A
	bcc aar_bcd
	lda zs_c
	clc
	adc #$06                  ; korekta BCD cyfry jednosci
	sta zs_c
aar_bcd
	lda zs_c
	cmp #$A0
	bcc aar_store
	sbc #$A0                  ; C = 1 po cmp
	sta g_rings_BCD
	inc g_lives
	lda #$09                  ; rst $28: dodatkowe zycie (00:39CD)
	jmp play_sfx
aar_store
	sta g_rings_BCD
	lda #$02                  ; rst $28: pierscien (00:39D4)
	jmp play_sfx

; kill_sonic (00:3618): smierc - flaga, odbicie w gore, licznik restartu (muzyka - M5)
kill_sonic
	lda iy_05_lvflag00
	ora #$01
	sta iy_05_lvflag00
	lda sonic_flags_ix_24
	ora #$80
	sta sonic_flags_ix_24
	lda #0
	sta sonic_vel_y_sub
	lda #$FA                  ; Vy = $FFFA (lo, hi) = -6 px/tick
	sta sonic_vel_y
	lda #$FF
	sta sonic_vel_y_hi
	lda #$60
	sta g_level_restart_countdown_timer
	lda iy_06_lvflag01
	and #$9F                  ; res 6, res 5
	sta iy_06_lvflag01
	lda iy_08_lvflag03
	and #$FE
	sta iy_08_lvflag03
	lda #$0A                  ; rst $18: muzyka smierci
	jmp play_music

; ---------------------------------------------------------------------
; damage_sonic (00:35FD): trafienie (kolce, M4: wrogowie). Bez skutku w nieśmiertelności po trafieniu
; (iy_09 b0), w ogluszeniu (iy_06 b6) i przy iy_08 b0. Z oslona (iy_06 b5) - tylko ogluszenie; bez
; pierscieni - kill_sonic; z pierscieniami - licznik 0, obiekt $55 (rozsypane pierscienie - jego funkcja
; w M4) i ogluszenie.
; ---------------------------------------------------------------------
damage_sonic
	lda iy_09
	lsr
	bcs ds_ret
	bit iy_06_lvflag01
	bvs ds_ret
	lda iy_08_lvflag03
	lsr
	bcs ds_ret
	lda iy_06_lvflag01
	and #$20                  ; oslona -> make_sonic_stunned_after_hit
	bne ds_stunned
	lda g_rings_BCD
	bne ds_throw
	jmp kill_sonic
ds_ret
	rts
ds_throw                        ; make_sonic_throw_his_rings (00:3644)
	lda #0
	sta g_rings_BCD
	jsr spawn_object
	bcs ds_stunned            ; brak wolnego slotu
	ldy #OB_TYPE
	lda #$55                  ; obiekt rozsypanych pierscieni
	sta (zg_ptr),y
	ldy #17
	lda #$06
	sta (zg_ptr),y
	iny
	lda #$00
	sta (zg_ptr),y
	ldy #OB_X+1               ; (ix+2, ix+3) = sonic_x
	lda sonic_x
	sta (zg_ptr),y
	iny
	lda sonic_x+1
	sta (zg_ptr),y
	ldy #OB_Y+1               ; (ix+5, ix+6) = sonic_y
	lda sonic_y
	sta (zg_ptr),y
	iny
	lda sonic_y+1
	sta (zg_ptr),y
	ldy #OB_VY                ; Vy = $FFFC00 (-4 px/tick)
	lda #$00
	sta (zg_ptr),y
	iny
	lda #$FC
	sta (zg_ptr),y
	iny
	lda #$FF
	sta (zg_ptr),y
ds_stunned                      ; make_sonic_stunned_after_hit (00:367E)
	ldx sonic_flags_ix_24
	txa
	and #$10                  ; pod woda (b4): Vy = $FFFE00, inaczej $FFFC00
	beq ds_vy_land
	lda #$FE
	bne ds_vy
ds_vy_land
	lda #$FC
ds_vy
	sta sonic_vel_y
	lda #$FF
	sta sonic_vel_y_hi
	lda #0
	sta sonic_vel_y_sub
	txa                       ; X = flagi
	and #$02
	beq ds_right              ; @sonic_is_facing_right
	txa
	ora #$12                  ; twarza w lewo: or $12 (b1 i b4), Vx = +2
	sta sonic_flags_ix_24
	lda #$02
	ldx #$00
	beq ds_vx
ds_right
	txa
	and #$FD                  ; res 1, Vx = -2
	sta sonic_flags_ix_24
	lda #$FE
	ldx #$FF
ds_vx                           ; @sonic_was_facing_left: Vx = (0, A, X)
	sta sonic_vel_x
	stx sonic_vel_x_hi
	lda #0
	sta sonic_vel_x_sub
	lda iy_06_lvflag01
	and #$DF                  ; res 5 (oslona zuzyta)
	ora #$40                  ; set 6 (ogluszenie)
	sta iy_06_lvflag01
	lda #$FF
	sta g_inputs_player_1
	lda #$11                  ; rst $28: trafienie (00:36BA)
	jmp play_sfx

; spawn_object (01:7C7B): pierwszy wolny slot (typ $FF) w object_list za Sonikiem (31 slotow).
; Wyjscie: C = 0 i zg_ptr = rekord w lustrze, C = 1 brak miejsca (scf). Niszczy A, X, Y.
; M4.1: znaleziony slot oznaczony w v_obj_dirty (trace testu zapisze go w tym kroku; oryginal nie czysci slotu).
spawn_object
	lda #<[object_list+OBJ_SIZE]
	sta zg_ptr
	lda #>[object_list+OBJ_SIZE]
	sta zg_ptr+1
	ldx #N_OBJECTS-1
spo_l
	ldy #OB_TYPE
	lda (zg_ptr),y
	cmp #$FF
	beq spo_found             ; C = 1 po cmp rownym - zerowane nizej
	clc
	lda zg_ptr
	adc #OBJ_SIZE
	sta zg_ptr
	bcc spo_nc
	inc zg_ptr+1
spo_nc
	dex
	bne spo_l
	sec
	rts
spo_found
	stx v_dirty_t             ; slot = 32 - X (X = 31 dla slotu 1)
	lda #N_OBJECTS
	sec
	sbc v_dirty_t
	jsr obj_dirty
	clc
	rts

; obj_dirty: slot A (0..31) w masce v_obj_dirty - trace testu zapisze go w tym kroku (game/trace.asm).
; Niszczy A, X; zachowuje Y.
obj_dirty
	sta v_dirty_t
	and #7
	tax
	lda bit_tab,x
	pha
	lda v_dirty_t
	lsr
	lsr
	lsr
	tax
	pla
	ora v_obj_dirty,x
	sta v_obj_dirty,x
	rts

; random_A (00:0625): ziarno g_random_seed (16 bit): HL = 3 * ziarno, A = L + H (bez przeniesienia), H = A,
; L = A + L, ziarno = HL + $54; wynik A = H. Wolane z logiki (obiekty) i raz na krok w miejscu IRQ (00:00D8,
; game/step.asm). Zachowuje X, Y (oryginal: HL, DE).
random_A
	lda g_random_seed
	asl
	sta v_rnd_l
	lda g_random_seed+1
	rol                       ; 2 * ziarno
	sta v_rnd_h
	clc
	lda v_rnd_l
	adc g_random_seed
	sta v_rnd_l               ; L
	lda v_rnd_h
	adc g_random_seed+1       ; A = H (3 * ziarno)
	clc
	adc v_rnd_l               ; add a,h: A = L + H
	sta v_rnd_h               ; ld h,a
	clc
	adc v_rnd_l               ; add a,l: L = A + L
	clc
	adc #$54                  ; add hl,$0054
	sta g_random_seed
	lda v_rnd_h
	adc #0
	sta g_random_seed+1       ; A = H
	rts

; level_mask: calc_level_offset_HL_and_mask_C (00:0C02) - bajt maski poziomu X = g_level >> 3 (przesuniecie od
; poczatku maski, np. g_level_has_checkpoint_mask), A = bit 1 << (g_level & 7). Zachowuje Y.
level_mask
	lda g_level
	and #7
	tax
	lda bit_tab,x
	pha
	lda g_level
	lsr
	lsr
	lsr
	tax
	pla
	rts

bit_tab	dta b($01,$02,$04,$08,$10,$20,$40,$80)

; objects_tick: update_some_objfunc_activation_statuses (00:2EDF) i run_all_objfuncs dla slotow 1..31
; (00:32A0-00:32A9) z wlaczonym bankiem obiektow (bank 45: kod w lukach danych z ROM-u, obj/dispatch.asm);
; Sonic (slot 0) potem w game/step.asm (sonic_tick) przy PB_MAIN. NMI zachowuje i przywraca PORTB.
objects_tick
	lda #PB_OBJ
	sta PORTB
	jsr obj_activate
	jsr obj_run_all
	lda v_late_irq            ; M6.4: IRQ load_art poza funkcja obiektu (po jej powrocie): boss GHZ3 - 1
	beq ot_nolate
	dec v_late_irq
	jsr irq_extra
ot_nolate
	lda #PB_MAIN
	sta PORTB
	rts

; ---------------------------------------------------------------------
; M6.6: bank obiektow strefy (PB_OBJZ, src/obj/objz.asm) - kod obiektow z banku 2 ROM-u. Okno $4000-$7FFF jest jedno, wiec
; przelaczenie musi isc z kodu rezydentnego.
; objz_call: wpis obj_fn_tab typow z banku 2 ($2D, $2E, $3B, $48, $4E...): obj_call robi jmp (zo_vec) tutaj, a powrot (rts) idzie do
; petli obiektow. Funkcja z oz_tab wg typu (wlaczony bank v_pbobjz - M6.9: PB_OBJZ dla BRI/JUN/LAB, PB_OBJZ2 od SBZ; oz_tab w obu
; bankach pod tym samym adresem), potem z powrotem PB_OBJ.
objz_call
	ldy #OB_TYPE
	lda (zg_obj),y
	asl
	tax
	lda v_pbobjz
	sta PORTB
	lda oz_tab,x
	sta zo_vec
	lda oz_tab+1,x
	sta zo_vec+1
	jsr oz_ind
	lda #PB_OBJ
	sta PORTB
	rts
oz_ind
	jmp (zo_vec)

; stuby do procedur banku 45 (bank obiektow strefy nie widzi banku 45): bank 45 na czas wywolania, potem v_pbobjz; przeniesienie
; (wynik check_collision_with_sonic: C = 1 brak trafienia) zachowane
zc_collide
	lda #PB_OBJ
	sta PORTB
	jsr check_collision_with_sonic
	php
	lda v_pbobjz
	sta PORTB
	plp
	rts
zc_enemy
	lda #PB_OBJ
	sta PORTB
	jsr enemy_touched_sonic
	lda v_pbobjz
	sta PORTB
	rts
zc_mlc                          ; move_locked_camera_towards_target
	lda #PB_OBJ
	sta PORTB
	jsr move_locked_camera_towards_target
	lda v_pbobjz
	sta PORTB
	rts
zc_slc                          ; set_locked_camera_target (zs_hl = cel X, zs_de = cel Y)
	lda #PB_OBJ
	sta PORTB
	jsr set_locked_camera_target
	lda v_pbobjz
	sta PORTB
	rts
zc_boss8                        ; boss_generic_update_8hp (tmp_08 = przesuniecie map)
	lda #PB_OBJ
	sta PORTB
	jsr boss_generic_update_8hp
	lda v_pbobjz
	sta PORTB
	rts
zc_bossart1                     ; boss_load_art (grafika bossa GHZ3 / JUN3: ART_09_AEB1)
	lda #PB_OBJ
	sta PORTB
	jsr boss_load_art
	lda v_pbobjz
	sta PORTB
	rts
zc_flame                        ; boss_render_jet_engine_flame
	lda #PB_OBJ
	sta PORTB
	jsr boss_render_jet_engine_flame
	lda v_pbobjz
	sta PORTB
	rts
zc_bossart3                     ; boss3_load_art (grafika bossa BRI3)
	lda #PB_OBJ
	sta PORTB
	jsr boss3_load_art
	lda v_pbobjz
	sta PORTB
	rts
zc_robotart                     ; M6.9: robot_load_art (grafika Robotnika ART_0C_EF3F - scenka SBZ3, zappery SKY3)
	lda #PB_OBJ
	sta PORTB
	jsr robot_load_art
	lda v_pbobjz
	sta PORTB
	rts
zc_dss                          ; M6.9: draw_sprite_string z mapa z banku strefy: zd_map = adres SMS mapy (>= $8000, bank v_pbobjz pod SMS - OZ_OFF),
	jsr objz_mapcopy          ; zd_x / zd_y = pozycja ekranowa (16 bit); 18 B mapy do v_mapbuf (konczy przy PB_OBJ, zd_map = v_mapbuf)
	jsr draw_sprite_string    ; jak w banku 45 (tmp_06 = zd_x, wpisy tablicy, licznik, grupa)
	lda v_pbobjz
	sta PORTB
	rts
zc_initfb                       ; M6.10: init_fireball_object (02:AC96 -> obj/objs_c.asm; Bomb $32 SKY2): zg_obj = zrodlo, zg_ptr = slot
	lda #PB_OBJ               ; z spawn_object, zg_de / zg_bc = przesuniecia X / Y, tmp_04 / tmp_06 = Vx / Vy (slowa: piksel lo, hi)
	sta PORTB
	jsr init_fireball_object
	lda v_pbobjz
	sta PORTB
	rts
zc_explosion                    ; M6.11: spawn_explosion (01:7A3A -> obj/objs_e2.asm; kontroler konca $53): zg_obj = zrodlo
	lda #PB_OBJ
	sta PORTB
	jsr spawn_explosion
	lda v_pbobjz
	sta PORTB
	rts
zc_monart                       ; M6.11: write_partial_monitor_art (obj/objs_d.asm; szmaragd konca $54): A = numer ikony
	pha
	lda #PB_OBJ
	sta PORTB
	pla
	jsr write_partial_monitor_art
	lda v_pbobjz
	sta PORTB
	rts
zc_dspr                         ; draw_sprite (A = kafel)
	pha
	lda #PB_OBJ
	sta PORTB
	pla
	jsr draw_sprite
	lda v_pbobjz
	sta PORTB
	rts
zc_put
	lda #PB_OBJ
	sta PORTB
	jsr put_sonic_y_pos_on_platform
	lda v_pbobjz
	sta PORTB
	rts

; sonic_spawn_bubble (M6.8): spawn_bubble (02:91EB, bank obiektow strefy - obj/objz_lab_woda.asm) z kodu Sonika (PB_MAIN, game/sonic.asm:
; babel co 256 tickow pod woda 01:522D, 4 bable przy utonieciu 01:5044). IX = rekord Sonika (object_list): typ 0 -> babel $42, pozycja
; z x, y Sonika. zg_obj zachowany (petla obiektow), potem znowu PB_MAIN.
sonic_spawn_bubble
	lda zg_obj
	pha
	lda zg_obj+1
	pha
	lda #<object_list
	sta zg_obj
	lda #>object_list
	sta zg_obj+1
	lda v_pbobjz              ; review M6.9: spawn_bubble jest tylko w banku 11 (woda tylko w Labyrinth - tam v_pbobjz = obraz banku 11;
	sta PORTB                 ; M7.2: zamiast stalej PB_OBJZ - na nosniku obraz 11 w slocie OBJZ)
	jsr spawn_bubble
	lda #PB_MAIN
	sta PORTB
	pla
	sta zg_obj+1
	pla
	sta zg_obj
	rts

; objz_mapcopy: obj_draw (bank 45) - mapa sprite'ow o adresie SMS >= $8000 (zd_map) lezy w banku obiektow strefy (adres okna = SMS - $4000):
; 18 B do bufora v_mapbuf, zd_map wskazuje bufor
objz_mapcopy
	lda zd_map
	sta zg_ptr
	lda zd_map+1
	sec
	sbc #>OZ_OFF
	sta zg_ptr+1
	lda v_pbobjz
	sta PORTB
	ldy #17
ozm_l
	lda (zg_ptr),y
	sta v_mapbuf,y
	dey
	bpl ozm_l
	lda #PB_OBJ
	sta PORTB
	lda #<v_mapbuf
	sta zd_map
	lda #>v_mapbuf
	sta zd_map+1
	rts

; bumper_draw (M6.5): draw_sprite_string (bank 45) dla zderzaka etapu specjalnego: zd_x, zd_y = pozycja ekranowa;
; mapa map_bumper_throb. Wolane z game/sonic.asm (sh_bumper, PB_MAIN).
bumper_draw
	lda #<map_bumper_throb
	sta zd_map
	lda #>map_bumper_throb
	sta zd_map+1
	lda #PB_OBJ
	sta PORTB
	jsr draw_sprite_string
	lda #PB_MAIN
	sta PORTB
	rts

; ---------------------------------------------------------------------
; midtick_patch (M6.4): irq_tile_patch (kod pod $4100) wolany z kodu banku obiektow: na chwile PB_MAIN (zrodlo skoku -
; kod rezydentny), potem z powrotem bank obiektow.
midtick_patch
	lda #PB_MAIN
	sta PORTB
	jsr irq_tile_patch
	lda #PB_OBJ
	sta PORTB
	rts

; irq_extra (M4.8): IRQ w trakcie dlugiej procedury z wlaczonymi przerwaniami (load_art tabliczki), gdy iy_00 b0
; jest ustawiony (bez @fn_update_screen - bez sprite'ow, palety i laty): poll_player_1_inputs -> g_inputs_player_1
; = stan kontrolera w tym ticku (v_irq_in z read_input; przycisk 1 = takze 2 jak @fn_pretend_button_2_pressed),
; random_A (00:00D8), licznik IRQ kroku (trace). Zachowuje X, Y.
; ---------------------------------------------------------------------
irq_extra
	lda v_irq_in
	sta g_inputs_player_1
	inc v_tr_irq
	lda v_step+1              ; krok >= 1: flaga rekordu "IRQ przed Sonikiem" (F_IRQ_PRZED_SONIKIEM = 2, jak referencja)
	bmi ixt_rng
	ora v_step
	beq ixt_rng
	lda v_tr_fl
	ora #$02
	sta v_tr_fl
ixt_rng
	jmp random_A
