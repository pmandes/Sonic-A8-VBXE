; =====================================================================
;  obj/objz.asm - M6.6 Bridge: bank obiektow strefy PB_OBJZ (bank 11, okno $4000-$7FFF). Kod i dane obiektow z banku 2 ROM-u
;  (SMS $8000-$BFFF, slot 2 petli obiektow): dane pod adresem SMS - OZ_OFF (OZ_SPAN* w objdata.inc), kod w lukach OZ_GAPA4 (Bridge, ten plik)
;  i OZ_GAPA21 (Jungle) - od M6.8 krok 0; dawne miejsca (OZ_GAPA3, OZ_GAPA8) zajely zakresy danych Labyrinth.
;  Wola tylko kod tego banku, kod rezydentny $8000+ (damage_sonic, random_A, play_sfx, spawn_object...) i stuby zc_*
;  (game/objcom.asm: na chwile bank 45 - check_collision_with_sonic, enemy_touched_sonic, put_sonic_y_pos_on_platform...).
;  Wskazniki w rekordach obiektow (mapa sprite'ow +15/16) zostaja wartosciami SMS ($8xxx) - rysowanie (obj_draw) kopiuje mape
;  z tego banku do bufora (objz_mapcopy). Wejscie: objz_call (rezydentne) -> oz_tab wg typu.
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_2D_badnik_spikeses 02:82E6, objfunc_2E_falling_bridge_piece
;  02:83C1, objfunc_48_BRI3_boss 02:8496, objfunc_4E_seesaw 02:866C, objfunc_3B_platform_y_oscillate 02:B50E.
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl (obiekty nie dziela ich z logika Sonica).
; =====================================================================
; adresy SMS danych (zakresy OZ_SPAN* w objdata.inc; tools/extract_sms.py: OBJZ_SPANS)
LUT_SPK_LEFT    = $8374   ; LUT_spikeses_anim_sequence_left (klatka, czas) x 2, $FF
LUT_SPK_RIGHT   = $8379
SPR_SPK         = $837E   ; SPRTAB_spikeses (klatka = 18 B)
SPR_FALLPIECE   = $8481   ; SPRTAB_falling_bridge_piece
OZ_ZEROPATCH    = $848E   ; UNK_0848E: 8 zer (dane lat kafli spadajacego elementu)
LUT_BOSS_ENTR   = $8632   ; LUT_BRI3_boss_entrances
LUT_BOSS_VELL   = $863A   ; LUT_BRI3_boss_pallet_velocities_left
LUT_BOSS_VELR   = $864A
SPR_BRI3BOSS    = $865A   ; SPRTAB_BRI3_boss
LUT_SPR_PLAT    = $8830   ; seesaw: LUT_sprite_platform ($36 $38 $3A $FF)
LUT_SPR_WEIGHT  = $8834   ; LUT_sprite_weight ($3C $3E $FF)
SPR_PLAT_BRI3   = $B5B5   ; SPRTAB_platform_y_oscillate_BRI
SPR_PLAT_SKY    = $B37B   ; SPRTAB_SKY_platform (Sky Base - dane dojda z ta strefa)

; ---------------------------------------------------------------------
; oz_tab: funkcje obiektow banku obiektow strefy wg typu $00-$55 (LUT_object_functions 00:2AF6); oz_stub - typ bez przekladu
; ---------------------------------------------------------------------
oz_tab
	dta a(oz_stub, oz_stub, oz_stub, oz_stub, oz_stub, oz_stub, oz_stub, oz_stub)   ; $00
	dta a(oz_stub, oz_stub, oz_stub, oz_stub, objfunc_0C_platform_fall, oz_stub, oz_stub, oz_stub)   ; $08
	dta a(oz_stub, objfunc_11_newtron, oz_stub, oz_stub, oz_stub, oz_stub, oz_stub, oz_stub)   ; $10
	dta a(oz_stub, oz_stub, oz_stub, oz_stub, oz_stub, objfunc_1D_floor_button, oz_stub, oz_stub)   ; $18 (M6.8 LAB: $1D)
	dta a(objfunc_20_air_bubble, oz_stub, oz_stub, oz_stub, oz_stub, oz_stub, oz_stub, objfunc_27_platform_tall)   ; $20 (M6.8 LAB: $20)
	dta a(objfunc_28_platform_wide, objfunc_29_log, objfunc_2A_rocket_puff, objfunc_2B_JUN3_bomb, objfunc_2C_JUN3_boss, objfunc_2D_spikeses, objfunc_2E_falling_bridge_piece, objfunc_2F_LAB3_rocket)   ; $28 (M6.8 LAB: $2A $2F)
	dta a(oz_stub, oz_stub, oz_stub, oz_stub, oz_stub, objfunc_35_orbinaut, objfunc_36_orbinaut_ball, oz_stub)   ; $30 (M6.8 LAB: $35 $36)
	dta a(oz_stub, oz_stub, oz_stub, objfunc_3B_platform_y_oscillate, objfunc_3C_jaws, objfunc_3D_spike_ball, objfunc_3E_spear, objfunc_3F_gargoyle)   ; $38 (M6.8 LAB: $3C $3D $3E $3F)
	dta a(objfunc_40_waterline, objfunc_41_bubble_spawner, objfunc_42_small_bubble, oz_stub, objfunc_44_burrobot, objfunc_45_float_platform, oz_stub, oz_stub)   ; $40 (M6.8 LAB: $40 $41 $42 $44 $45)
	dta a(objfunc_48_BRI3_boss, objfunc_49_LAB3_boss, oz_stub, oz_stub, oz_stub, oz_stub, objfunc_4E_seesaw, oz_stub)   ; $48 (M6.8 LAB: $49)
	dta a(oz_stub, oz_stub, oz_stub, oz_stub, oz_stub, oz_stub)   ; $50

; oz_stub: typ bez przekladu - jak obj_stub (licznik v_obj_todo, typ w v_obj_todo_id; stan obiektu bez zmian)
oz_stub
	ldy #OB_TYPE
	lda (zg_obj),y
	sta v_obj_todo_id
	inc v_obj_todo
	rts

; ---------------------------------------------------------------------
; oz_dfa (kopia do_framed_animation 01:7C41 z banku 45 - sekwencje i mapy tych obiektow leza w tym banku): zg_bc = sekwencja
; (adres okna), zg_de = baza map (adres SMS). Pary (klatka, czas; $FF - od poczatku) wg indeksu (ix+23) i licznika (ix+22):
; mapa (ix+15/16) = baza + klatka * 18; (ix+22) + 1; gdy czas < (ix+22): (ix+22) = 0, (ix+23) + 2.
; ---------------------------------------------------------------------
oz_dfa
	ldy #23
	lda (zg_obj),y
	tay
odf_find
	lda (zg_bc),y
	cmp #$FF
	bne odf_found
	lda #0                    ; koniec sekwencji: (ix+23) = 0, od poczatku
	ldy #23
	sta (zg_obj),y
	tay
	beq odf_find
odf_found
	sty zg_a                  ; indeks pary (czas pod indeksem + 1)
	ldx #0                    ; mapa = baza + klatka * 18 (16 bit): klatka * 2 + klatka * 16
	stx zg_prof+1
	asl
	rol zg_prof+1
	sta zg_hl                 ; klatka * 2
	ldx zg_prof+1
	stx zg_hl+1
	asl
	rol zg_prof+1
	asl
	rol zg_prof+1
	asl
	rol zg_prof+1             ; klatka * 16
	clc
	adc zg_hl
	sta zg_prof
	lda zg_prof+1
	adc zg_hl+1
	sta zg_prof+1
	clc
	lda zg_prof
	adc zg_de
	ldy #OB_SPRITE
	sta (zg_obj),y
	lda zg_prof+1
	adc zg_de+1
	iny
	sta (zg_obj),y
	ldy #22                   ; inc (ix+22)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	sta zg_off
	ldy zg_a                  ; czas
	iny
	lda (zg_bc),y
	cmp zg_off
	bcs odf_ret               ; ret nc: czas >= (ix+22)
	lda #0
	ldy #22
	sta (zg_obj),y
	iny
	lda (zg_obj),y            ; (ix+23) + 2
	clc
	adc #2
	sta (zg_obj),y
odf_ret
	rts

; ---------------------------------------------------------------------
; objfunc_2D_badnik_spikeses (02:82E6): kolizje z mapa wlaczone. Dwie strefy trafienia: kolce na gorze (16 x 15, przesuniecie
; (8, 4)) - damage_sonic; korpus (20 x 32, przesuniecie (6, 16)) - enemy_touched_sonic (tmp_00 = $0404: wybuch). Vy + $20
; (grawitacja, 24 bit). (ix+17) < $50: Vx = -$40 (subpiksele), animacja w lewo, inaczej Vx = +$40 i animacja w prawo;
; co 8 ticki (ix+17) + 1, od $A0 znowu 0.
; ---------------------------------------------------------------------
objfunc_2D_spikeses
	ldy #OB_W
	lda #$10
	sta (zg_obj),y
	iny
	lda #$0F
	sta (zg_obj),y
	lda #$08                  ; hl = $0408
	sta tmp_06
	lda #$04
	sta tmp_07
	jsr zc_collide
	bcs spk_c1
	jsr damage_sonic
spk_c1
	ldy #OB_W
	lda #$14
	sta (zg_obj),y
	iny
	lda #$20
	sta (zg_obj),y
	lda #$06                  ; hl = $1006
	sta tmp_06
	lda #$10
	sta tmp_07
	jsr zc_collide
	lda #$04                  ; ld hl,$0404 / ld (tmp_00),hl (przed call nc - bez wplywu na C)
	sta tmp_00
	sta tmp_00+1
	bcs spk_c2
	jsr zc_enemy
spk_c2
	ldy #OB_VY                ; Vy += $20 (24 bit)
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
	lda #<SPR_SPK
	sta zg_de
	lda #>SPR_SPK
	sta zg_de+1
	ldy #17
	lda (zg_obj),y
	cmp #$50
	bcc spk_left
	ldy #OB_VX                ; w prawo: Vx = $000040
	lda #$40
	sta (zg_obj),y
	lda #0
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #<[LUT_SPK_RIGHT-OZ_OFF]
	sta zg_bc
	lda #>[LUT_SPK_RIGHT-OZ_OFF]
	sta zg_bc+1
	jsr oz_dfa
	jmp spk_tick
spk_left                        ; @go_left: Vx = $FFFFC0
	ldy #OB_VX
	lda #$C0
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #<[LUT_SPK_LEFT-OZ_OFF]
	sta zg_bc
	lda #>[LUT_SPK_LEFT-OZ_OFF]
	sta zg_bc+1
	jsr oz_dfa
spk_tick                        ; @was_going_right
	lda g_global_tick_counter
	and #$07
	bne spk_ret
	ldy #17
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$A0
	bcc spk_ret
	lda #0
	sta (zg_obj),y
spk_ret
	rts

; ---------------------------------------------------------------------
; objfunc_2E_falling_bridge_piece (02:83C1): spadajacy element mostu 16 x 8 (powstaje w sp_18 / sp_19 / sp_1a, game/sonic.asm).
; Bez kolizji z mapa (set 5). Przed upadkiem (b0 flag = 0): mapa 0; po losowym czasie $01-$20 tickow ((ix+17), b1 = czas ustawiony)
; i gdy lata ekranu jest wolna (g_screen_tile_replace_x_hi b7 = 1) - lata 2 x 2 pustych kafli (x, y + $0E, dane UNK_0848E: zera),
; efekt $20, b0. Po upadku: mapa SPRTAB_falling_bridge_piece, Vy + $20 (24 bit; bajt Vy hi > 3 -> 4), tmp_00 = Vy (16 bit); gdy
; y >= kamera Y + $100 - obiekt usuwany ($FF). Platforma: Sonic (Vy >= 0, przesuniecie (2, 4)) stoi na elemencie (Vy z tmp_00).
; ---------------------------------------------------------------------
objfunc_2E_falling_bridge_piece
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W
	lda #$0E
	sta (zg_obj),y
	iny
	lda #$08
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$01
	jne fbp_fallen
	lda #0                    ; mapa 0 (przed upadkiem nie rysowany), tmp_00 = 0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	sta tmp_00
	sta tmp_00+1
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02
	bne fbp_timer_set
	jsr random_A              ; czas do upadku: ((random & $1F) + 1) tickow
	and #$1F
	clc
	adc #1
	ldy #17
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 1
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
fbp_timer_set                   ; @already_set_random_fall_timer
	ldy #17
	lda (zg_obj),y
	sec
	sbc #1
	sta (zg_obj),y
	jne fbp_plat
	lda #1                    ; czas minal: kolejna proba w nastepnym ticku, gdy lata ekranu zajeta
	sta (zg_obj),y
	lda g_screen_tile_replace_x+1
	and #$80
	jeq fbp_plat
	ldy #OB_X+1               ; lata ekranu: x = (ix+2,3), y = (ix+5,6) + $0E, dane UNK_0848E
	lda (zg_obj),y
	sta g_screen_tile_replace_x
	iny
	lda (zg_obj),y
	sta g_screen_tile_replace_x+1
	ldy #OB_Y+1
	clc
	lda (zg_obj),y
	adc #$0E
	sta g_screen_tile_replace_y
	iny
	lda (zg_obj),y
	adc #0
	sta g_screen_tile_replace_y+1
	lda #<OZ_ZEROPATCH
	sta g_screen_tile_replace_data_ptr
	lda #>OZ_ZEROPATCH
	sta g_screen_tile_replace_data_ptr+1
	ldy #OB_FLAGS             ; set 0
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
	lda #$20                  ; rst $28
	jsr play_sfx
fbp_fallen                      ; @already_fallen
	ldy #OB_SPRITE
	lda #<SPR_FALLPIECE
	sta (zg_obj),y
	iny
	lda #>SPR_FALLPIECE
	sta (zg_obj),y
	ldy #OB_VY                ; Vy (24 bit) += $20; bajt Vy hi (ix+11) > 3 -> 4
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
	sta zg_a                  ; c
	lda zg_hl+1
	cmp #$04
	bcc fbp_vcap
	lda #$04
	sta zg_hl+1
fbp_vcap
	ldy #OB_VY
	lda zg_hl
	sta (zg_obj),y
	sta tmp_00
	iny
	lda zg_hl+1
	sta (zg_obj),y
	sta tmp_00+1
	iny
	lda zg_a
	sta (zg_obj),y
	clc                       ; de = kamera Y + $0100: y < de -> zostaje, inaczej usuniecie
	lda g_level_scroll_y_pix_lo+1
	adc #1
	sta zg_de+1
	lda g_level_scroll_y_pix_lo
	sta zg_de
	ldy #OB_Y+1
	sec
	lda (zg_obj),y
	sbc zg_de
	iny
	lda (zg_obj),y
	sbc zg_de+1
	bcc fbp_plat
	lda #$FF
	ldy #OB_TYPE
	sta (zg_obj),y
	rts
fbp_plat                        ; @do_platform_behaviour
	lda #$02                  ; hl = $0402
	sta tmp_06
	lda #$04
	sta tmp_07
	jsr zc_collide
	bcs fbp_ret
	lda sonic_vel_y_hi
	bmi fbp_ret
	lda tmp_00                ; de = tmp_00, bc = $0010
	sta zg_de
	lda tmp_00+1
	sta zg_de+1
	lda #$10
	sta zg_bc
	lda #0
	sta zg_bc+1
	jmp zc_put
fbp_ret
	rts

	icl 'obj/objz_seesaw.asm'      ; $4E hustawka
	icl 'obj/objz_boss.asm'        ; $48 boss BRI3

; ---------------------------------------------------------------------
; objfunc_3B_platform_y_oscillate (02:B50E): platforma kolebiaca sie w pionie (BRI, SKY). Bez kolizji z mapa (set 5), mapa wg
; g_tile_flags_index (1 = Bridge: SPRTAB_platform_y_oscillate_BRI, inaczej SPRTAB_SKY_platform). Przyspieszenie Y +-$10 (24 bit):
; (ix+17) < tmp_08 ($50) w dol, dalej w gore; Vy ograniczone do +-$01FF (ponad: $0200 / $FE00 - jak oryginal); (ix+17) + 1, od
; $A0 znowu 0. Sonic na platformie (Vy >= 0, rozmiar 30 x 28, przesuniecie (2, 8)) - put_sonic_y_pos_on_platform z Vy platformy.
; ---------------------------------------------------------------------
objfunc_3B_platform_y_oscillate
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #<SPR_PLAT_SKY
	ldx #>SPR_PLAT_SKY
	ldy g_tile_flags_index
	cpy #$01
	bne pyo_map
	lda #<SPR_PLAT_BRI3
	ldx #>SPR_PLAT_BRI3
pyo_map
	ldy #OB_SPRITE
	sta (zg_obj),y
	txa
	iny
	sta (zg_obj),y
	lda #$50
	sta tmp_08
	jsr oz_yosc
	ldy #17
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$A0
	bcc pyo_ret
	lda #0
	sta (zg_obj),y
pyo_ret
	rts

oz_yosc                         ; @fn_do_y_oscillate
	lda #$10                  ; de = $0010 (w dol), c = 0
	sta zg_de
	lda #0
	sta zg_de+1
	tax                       ; X = c
	ldy #17
	lda (zg_obj),y
	cmp tmp_08                ; cp l: (ix+17) < l -> w dol
	bcc yo_acc
	ldx #$FF                  ; dec c
	lda #$F0                  ; de = $FFF0
	sta zg_de
	lda #$FF
	sta zg_de+1
yo_acc                          ; Vy (24 bit) += de, rozszerzenie znaku c
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc zg_de
	sta (zg_obj),y
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta (zg_obj),y
	sta zg_hl+1
	iny
	txa
	adc (zg_obj),y            ; adc a,c: A = (ix+12) + c + przeniesienie
	sta (zg_obj),y
	lda zg_hl+1
	bpl yo_pos
	lda zg_hl                 ; ujemne: hl = -hl (cpl, inc), |Vy| >> 8 >= 2 -> Vy = $FFFE00
	eor #$FF
	clc
	adc #1
	sta zg_hl
	lda zg_hl+1
	eor #$FF
	adc #0
	cmp #$02
	bcc yo_cont
	ldy #OB_VY
	lda #$00
	sta (zg_obj),y
	lda #$FE
	iny
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	jmp yo_cont
yo_pos
	cmp #$02
	bcc yo_cont
	ldy #OB_VY                ; Vy = $000200
	lda #$00
	sta (zg_obj),y
	lda #$02
	iny
	sta (zg_obj),y
	lda #$00
	iny
	sta (zg_obj),y
yo_cont                         ; @continue_after_y_vel_clamp_check
	lda sonic_vel_y_hi
	bmi yo_ret                ; and a / ret m
	ldy #OB_W
	lda #$1E
	sta (zg_obj),y
	iny
	lda #$1C
	sta (zg_obj),y
	lda #$02                  ; hl = $0802
	sta tmp_06
	lda #$08
	sta tmp_07
	jsr zc_collide
	bcs yo_ret
	ldy #OB_VY                ; de = Vy platformy (e, d), bc = $0010
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	lda #$10
	sta zg_bc
	lda #0
	sta zg_bc+1
	jmp zc_put
yo_ret
	rts
