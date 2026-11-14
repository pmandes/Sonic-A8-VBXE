; =====================================================================
;  obj/objz3_koniec.asm - M6.11 poziom koncowy $12: $53 kontroler konca (Robotnik w Eggmobilu, Sonic spada z gory, wybuchy),
;  $54 szmaragd dobrego konca (ikona szmaragdu leci w gore, potem przejscie do $13)
;  M6.11: kod w trzecim banku obiektow strefy PB_OBJZ3 (bank 30; obj/objz3.asm) - dane banku 2 ROM-u pod adresem
;  SMS - OZ_OFF jak w PB_OBJZ2 (zakresy OBJZ3_SPANS w tools/extract_sms.py, stale OZ3_* w objdata.inc).
;  (bank obiektow strefy 3 PB_OBJZ3, bank 30, okno $4000-$7FFF; dolaczany z game.asm w sekcji banku 30).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny):
;   objfunc_53_end_controller_start       02:BDF9 - 02:BF20  -> objfunc_53_end_ctrl
;   SPRTAB_end_controller_start_flying    02:BF21 - 02:BF32   (18 B: 3 wiersze Eggmobilu, kafle $2A-$32 / $4A-$52 / $6A-$72)
;   SPRTAB_end_controller_start_exploding 02:BF33 - 02:BF4B   (18 B mapy: wiersz 1 z twarza $34 $36 $38; za nia 7 B $5C $5E $FF...
;                                                              02:BF45-02:BF4B - draw_sprite_string ich nie czyta (3 wiersze))
;   objfunc_54_end_controller_good_ending_chaos_emeralds 02:BF4C - 02:BFF0 -> objfunc_54_end_emerald
;   SPRTAB_end_chaos_emerald              02:BFF1 - 02:BFF7   (7 B: $5C $5E $FF $FF $FF $FF, wiersz 2 = $FF - koniec)
;   BANK02_JUNK_END_BFF8                  02:BFF8 - 02:BFFF   (smieci - pominiete)
;  Dane banku 2 ROM-u leza w tym banku pod adresem SMS - OZ_OFF (dla OBJZ3_SPANS: $BF21-$BF4B (43 B; czytane $BF21-$BF44) i
;  $BFF1-$BFF7 (7 B)); kod ich nie czyta wprost - do rekordu (mapa ix+15/16) i do zd_map (zc_dss) trafiaja adresy SMS ($BF21,
;  $BF33, $BFF1), mapy kopiuje objz_mapcopy z banku v_pbobjz (game/objcom.asm).
;  Wolane: kod rezydentny $8000+ (play_sfx = rst $28 - game/objcom.asm) i stuby zc_* do banku 45 (game/objcom.asm):
;   zc_collide   (check_collision_with_sonic 00:3956: tmp_06/07 = przesuniecia, (ix+13/14) = rozmiar; C = 1 brak trafienia),
;   zc_flame     (boss_render_jet_engine_flame 01:79FA -> obj/objs_e2.asm: plomien silnika Eggmobilu co 2 ticki, draw_sprite),
;   zc_explosion (spawn_explosion 01:7A3A -> obj/objs_e2.asm; stub w game/objcom.asm, opis nizej),
;   zc_monart    (write_partial_monitor_art 00:0C1D -> obj/objs_d.asm; stub w game/objcom.asm, opis nizej),
;   zc_dss       (draw_sprite_string 00:350F z mapa z banku strefy: zd_map = adres SMS mapy, zd_x / zd_y = pozycja ekranowa).
;  Stuby (game/objcom.asm, wzor jak zc_flame / zc_dspr):
;   zc_explosion: lda #PB_OBJ / sta PORTB / jsr spawn_explosion / lda v_pbobjz / sta PORTB / rts. Wejscie: zg_obj = obiekt zrodlowy
;     (x = (ix+2/3), y = (ix+5/6)). Skutki (jak 01:7A3A): spawn_object (zg_ptr = slot; brak slotu - nic), random_A x 2 (x + 0..31,
;     potem y + 0..31), nowy obiekt $0A (wybuch): (ix+1) = 0, x, (ix+4) = 0, y, (ix+17) = (ix+22) = (ix+23) = 0, Vx = Vy = 0;
;     tmp_00 = dx, tmp_02 = dy (slowa), SFX $01. Niszczy A, X, Y, zg_ptr, zs_de, zs_b, zs_c; zg_obj bez zmian. Wyniku (C) nie ma.
;   zc_monart: pha / lda #PB_OBJ / sta PORTB / pla / jsr write_partial_monitor_art / lda v_pbobjz / sta PORTB / rts. Wejscie:
;     A = ikona k (MONART 05:5180 + k * $80; HL = $5400 -> k = 5 - szmaragd, jak objfunc_06 w objs_d.asm). Skutek: v_monk[tick & 15]
;     = k, v_mondirty = 1 (renderer kopiuje 2 wiersze ikony do kafli $5C-$5F atlasu sprite'ow); RAM SMS bez zmian. Niszczy A, X.
;  Rejestry Z80: IX = zg_obj, HL = zg_hl (pomocniczo); zd_x / zd_y / zd_map = HL / DE / BC draw_sprite_string (zc_dss).
;  Przeniesienie: Z80 C = 1 po sbc (pozyczka) <=> 6502 C = 0.
; =====================================================================
; adresy SMS danych (bank 2 ROM-u; w tym banku pod adresem - OZ_OFF)
OK53_SPR_FLY    = $BF21   ; SPRTAB_end_controller_start_flying (Eggmobil leci)
OK53_SPR_EXP    = $BF33   ; SPRTAB_end_controller_start_exploding (Eggmobil trafiony - wybucha)
OK54_SPR        = $BFF1   ; SPRTAB_end_chaos_emerald: jeden wiersz $5C $5E (ikona szmaragdu z kafli monitora), wiersz 2 = $FF
OK54_SPRTAB     = $D000   ; g_sprite_table (adres SMS - wartosc wskaznika g_next_avail_vdp_sprite_ptr; wpis = 3 B: x, y, kafel)
OK54_ICON       = 5       ; write_partial_monitor_art HL = $5400 -> ikona k = ($5400 - $5180) / $80 = 5 (szmaragd)

; ---------------------------------------------------------------------
; objfunc_53_end_controller_start (02:BDF9): obiekt poziomu $12 (6720, 288). Co tick set 5 (bez kolizji z mapa) i wejscie = $FF.
; Pierwszy tick ((ix+24) b1 = 0): paleta sprite'ow PAL2_boss (signal_load_palettes A = 2), slot Sonika object_list = $FF (Sonic
;  nie istnieje - petla obiektow go pomija), sonic_y = 0, (ix+18) = $FF, set 6 iy_07 (kamera nie idzie za Sonikiem), set 1.
; Co parzysty tick (ix+18) != 0 -> (ix+18) - 1; przy 0 (po 255 parzystych tickach = 510 tickow) Sonic pojawia sie: sonic_x = x + $3C,
;  sonic_y = y - $40 (subpiksele bez zmian), object_list = 0 (typ Sonika), set 6 iy_08 (Sonic sie wteleportowuje), SFX $06.
; Zawsze: rozmiar $20 x $1C, Vx = $000100 (+1 px/tick w prawo), Vy = 0; przy iy_07 b6: kamera X + 1, gdy scroll_x + $40 < x
;  (16 bit bez znaku); mapa = SPRTAB_end_controller_start_flying.
; Bez trafienia ((ix+24) b0 = 0): kolizja z Sonikiem (tmp_06 = $08, tmp_07 = $10) -> Vy Sonica = -Vy (24 bit), res 6 iy_07
;  (kamera znow za Sonikiem), set 0, (ix+17) = 1, SFX $01.
; Potem plomien silnika (zc_flame - co parzysty tick, Vx != 0). Po trafieniu (b0 = 1): Vy = $000040 (opada 0,25 px/tick), mapa
;  wybuchu; (ix+17) - 1, przy 0: spawn_explosion (zc_explosion), (ix+17) = $18 (wybuch co 24 ticki), (ix+19) + 1; od 10 wybuchow
;  (kazdy kolejny tez): szmaragdy >= 6 -> set 7 iy_08 (dobre zakonczenie - logika Sonika 01:529C), inaczej gdy licznik tabliczki
;  = 0: g_signpost_tickdown_counter = $20, set 2 iy_0D (przejscie do g_level + 1 bez wyniku i mapy).
; Pola rekordu: (ix+17) licznik wybuchu, (ix+18) licznik pojawienia sie Sonika ($FF..0), (ix+19) liczba wybuchow,
;  (ix+24) b0 = trafiony, b1 = zainicjowany, b5 = bez kolizji z mapa.
; ---------------------------------------------------------------------
objfunc_53_end_ctrl
	ldy #OB_FLAGS             ; 02:BDF9: set 5,(ix+24) - bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #$FF                  ; 02:BDFD: ld (iy+g_inputs_player_1),$FF - wejscie zablokowane (co tick, takze po pojawieniu sie Sonika)
	sta g_inputs_player_1
	lda (zg_obj),y            ; 02:BE01: bit 1,(ix+24) / jr nz @already_initialised (Y = OB_FLAGS)
	and #$02
	bne ok53_inited
	lda iy_00                 ; 02:BE07: ld hl,PAL2_boss / ld a,$02 / call signal_load_palettes (00:0333): set 3,(iy+iy_00),
	ora #$08                  ; (g_SIG00b3_palettes_present) = 2 (sprite'y), (g_SIG00b3_palette_addr) = PAL2_boss
	sta iy_00                 ; (port: kolory wgrywa renderer - render/sprites.asm art_tiles: v_pal_which = 1, v_sign_pal = 2)
	lda #$02
	sta g_SIG00b3_palettes_present
	lda #<PAL2_BOSS
	sta g_SIG00b3_palette_addr
	lda #>PAL2_BOSS
	sta g_SIG00b3_palette_addr+1
	lda #$FF                  ; 02:BE0F: ld a,$FF / ld (object_list),a - slot 0 (Sonic) pusty: run_all_objfuncs go pomija
	sta object_list
	lda #0                    ; 02:BE14: ld hl,$0000 / ld (sonic_y),hl - Sonic "nad" poziomem (sonic_y_sub bez zmian)
	sta sonic_y
	sta sonic_y+1
	lda #$FF                  ; 02:BE1A: ld (ix+18),$FF - licznik do pojawienia sie Sonika (255 parzystych tickow)
	ldy #18
	sta (zg_obj),y
	lda iy_07_lvflag02        ; 02:BE1E: set 6,(iy+iy_07_lvflag02) - kamera zatrzymana (adjust_camera_for_when_sonic_is_alive
	ora #$40                  ; 00:2F66 ret nz; port: game/camera.asm) - przesuwa ja ten obiekt nizej
	sta iy_07_lvflag02
	ldy #OB_FLAGS             ; 02:BE22: set 1,(ix+24) - zainicjowany
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y

ok53_inited                     ; 02:BE26 @already_initialised: ld a,(g_global_tick_counter) / rrca / jr c @skip_sonic_spawn_in
	lda g_global_tick_counter ; (tick nieparzysty - bez odliczania)
	lsr
	bcs ok53_nospawn
	ldy #18                   ; 02:BE2C: ld a,(ix+18) / and a / jr z @skip_sonic_spawn_in - Sonic juz jest
	lda (zg_obj),y
	beq ok53_nospawn
	sec                       ; 02:BE32: dec (ix+18) / jr nz @skip_sonic_spawn_in
	sbc #1
	sta (zg_obj),y
	bne ok53_nospawn
	; --- Sonic pojawia sie nad Robotnikiem ---
	ldy #OB_X+1               ; 02:BE37: hl = x (ix+2/3) + $003C / ld (sonic_x),hl (16 bit; subpiksel sonic_x bez zmian)
	clc
	lda (zg_obj),y
	adc #<$003C
	sta sonic_x
	iny
	lda (zg_obj),y
	adc #>$003C
	sta sonic_x+1
	ldy #OB_Y+1               ; 02:BE44: hl = y (ix+5/6) + $FFC0 (- 64) / ld (sonic_y),hl
	clc
	lda (zg_obj),y
	adc #<$FFC0
	sta sonic_y
	iny
	lda (zg_obj),y
	adc #>$FFC0
	sta sonic_y+1
	lda #0                    ; 02:BE51: xor a / ld (object_list),a - typ Sonika 0 (Sonic znowu dziala)
	sta object_list
	lda iy_08_lvflag03        ; 02:BE55: set 6,(iy+iy_08_lvflag03) - wteleportowanie (@handle_ending_animation_teleport_in 01:5193)
	ora #$40
	sta iy_08_lvflag03
	lda #$06                  ; 02:BE59: ld a,$06 / rst $28 - odglos pojawienia sie
	jsr play_sfx

ok53_nospawn                    ; 02:BE5C @skip_sonic_spawn_in: (ix+13) = $20, (ix+14) = $1C - rozmiar 32 x 28
	ldy #OB_W
	lda #$20
	sta (zg_obj),y
	iny
	lda #$1C
	sta (zg_obj),y
	ldy #OB_VX                ; 02:BE64: xor a / (ix+7) = a, (ix+8) = $01, (ix+9) = a - Vx = $000100 (+1 px/tick)
	lda #0
	sta (zg_obj),y
	iny
	lda #$01
	sta (zg_obj),y
	iny
	lda #0
	sta (zg_obj),y
	iny                       ; 02:BE6F: (ix+10) = (ix+11) = (ix+12) = a (= 0) - Vy = 0 (Y = OB_VY)
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda iy_07_lvflag02        ; 02:BE78: bit 6,(iy+iy_07_lvflag02) / jr z @skip_level_x_scroll - kamera juz za Sonikiem
	and #$40
	beq ok53_noscroll
	clc                       ; 02:BE7E: ld de,(g_level_scroll_x_pix_lo) / ld hl,$0040 / add hl,de - hl = scroll_x + 64 (16 bit)
	lda g_level_scroll_x_pix_lo
	adc #<$0040
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #>$0040
	sta zg_hl+1
	ldy #OB_X+1               ; 02:BE86: bc = x (ix+2/3) / and a / sbc hl,bc / jr nc @skip_level_x_scroll
	lda zg_hl                 ; (bez pozyczki - 6502 C = 1: scroll_x + 64 >= x - kamera stoi)
	cmp (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	bcs ok53_noscroll
	inc g_level_scroll_x_pix_lo ; 02:BE91: inc de / ld (g_level_scroll_x_pix_lo),de - kamera + 1 px (16 bit) za Robotnikiem
	bne ok53_noscroll
	inc g_level_scroll_x_pix_lo+1
ok53_noscroll                   ; 02:BE96 @skip_level_x_scroll: (ix+15/16) = SPRTAB_end_controller_start_flying (adres SMS)
	ldy #OB_SPRITE
	lda #<OK53_SPR_FLY
	sta (zg_obj),y
	iny
	lda #>OK53_SPR_FLY
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:BE9E: bit 0,(ix+24) / jr nz @did_not_get_hit_by_sonic - juz trafiony
	lda (zg_obj),y
	and #$01
	bne ok53_nohit
	lda #$08                  ; 02:BEA4: ld hl,$1008 / ld (tmp_06),hl - tmp_06 = $08 (x), tmp_07 = $10 (y)
	sta tmp_06
	lda #$10
	sta tmp_07
	jsr zc_collide            ; 02:BEAA: call check_collision_with_sonic / jr c @did_not_get_hit_by_sonic
	bcs ok53_nohit
	clc                       ; 02:BEAF: ld de,$0001 / hl = (sonic_vel_y_sub), a = (sonic_vel_y_hi); cpl l, h, a / add hl,de /
	lda sonic_vel_y_sub       ; adc a,$00 - Vy Sonica = -Vy (24 bit: dopelnienie + 1) - Sonic odbija sie od Eggmobilu
	eor #$FF
	adc #<$0001
	sta sonic_vel_y_sub       ; 02:BEC2: ld (sonic_vel_y_sub),hl / ld (sonic_vel_y_hi),a
	lda sonic_vel_y
	eor #$FF
	adc #>$0001
	sta sonic_vel_y
	lda sonic_vel_y_hi
	eor #$FF
	adc #$00
	sta sonic_vel_y_hi
	lda iy_07_lvflag02        ; 02:BEC8: res 6,(iy+iy_07_lvflag02) - kamera znow za Sonikiem
	and #$BF
	sta iy_07_lvflag02
	ldy #OB_FLAGS             ; 02:BECC: set 0,(ix+24) - trafiony
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
	ldy #17                   ; 02:BED0: ld (ix+17),$01 - pierwszy wybuch jeszcze w tym ticku
	lda #$01
	sta (zg_obj),y
	lda #$01                  ; 02:BED4: ld a,$01 / rst $28 - odglos trafienia
	jsr play_sfx

ok53_nohit                      ; 02:BED7 @did_not_get_hit_by_sonic: call boss_render_jet_engine_flame (Vx = +1 px - plomien
	jsr zc_flame              ; z lewej strony: kafel 4 + (tick & 2) w (x - 8, y + 16), co parzysty tick)
	ldy #OB_FLAGS             ; 02:BEDA: bit 0,(ix+24) / ret z - bez trafienia koniec
	lda (zg_obj),y
	and #$01
	beq ok53_ret
	ldy #OB_VY                ; 02:BEDF: xor a / (ix+10) = $40, (ix+11) = a, (ix+12) = a - Vy = $000040 (opada 0,25 px/tick)
	lda #$40
	sta (zg_obj),y
	iny
	lda #0
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_SPRITE            ; 02:BEEA: (ix+15/16) = SPRTAB_end_controller_start_exploding (adres SMS)
	lda #<OK53_SPR_EXP
	sta (zg_obj),y
	iny
	lda #>OK53_SPR_EXP
	sta (zg_obj),y
	ldy #17                   ; 02:BEF2: dec (ix+17) / ret nz
	lda (zg_obj),y
	sec
	sbc #1
	sta (zg_obj),y
	bne ok53_ret
	jsr zc_explosion          ; 02:BEF6: call spawn_explosion (obiekt $0A w (x + 0..31, y + 0..31), random_A x 2, SFX $01)
	ldy #17                   ; 02:BEF9: ld (ix+17),$18 - nastepny wybuch za 24 ticki
	lda #$18
	sta (zg_obj),y
	ldy #19                   ; 02:BEFD: inc (ix+19) / ld a,(ix+19) / cp $0A / ret c
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$0A
	bcc ok53_ret
	lda g_chaos_emeralds_collected ; 02:BF06: ld a,(g_chaos_emeralds_collected) / cp $06 / jr c @no_good_ending_for_you
	cmp #$06
	bcc ok53_bad
	lda iy_08_lvflag03        ; 02:BF0D: set 7,(iy+iy_08_lvflag03) / ret - dobre zakonczenie (Sonic idzie w lewo, tworzy $54)
	ora #$80
	sta iy_08_lvflag03
	rts
ok53_bad                        ; 02:BF12 @no_good_ending_for_you: ld a,(g_signpost_tickdown_counter) / and a / ret nz
	lda g_signpost_tickdown_counter
	bne ok53_ret
	lda #$20                  ; 02:BF17: ld a,$20 / ld (g_signpost_tickdown_counter),a - 32 ticki parzyste (64 ticki)
	sta g_signpost_tickdown_counter
	lda iy_0D                 ; 02:BF1C: set 2,(iy+iy_0D) / ret - @teleport_to_next: g_level + 1 ($13) bez wyniku i mapy
	ora #$04
	sta iy_0D
ok53_ret
	rts

; ---------------------------------------------------------------------
; objfunc_54_end_controller_good_ending_chaos_emeralds (02:BF4C): szmaragd tworzony przez Sonika w dobrym zakonczeniu
; (@fn_handle_good_ending_sequence 01:529C: w (x + 2, y + 14) Sonika). Co tick set 5 i write_partial_monitor_art $5400 (ikona
; szmaragdu -> kafle sprite'ow $5C-$5F, 2 wiersze kafla na tick - zc_monart). Mapa rekordu zawsze 0 (obj_draw nic nie rysuje).
; Faza 1 ((ix+24) b0 = 0): mapa = 0, Vx = 0, (ix+17) + 1; przy $50 (80 tickow): set 0, (ix+17) = $64. Bez rysowania.
; Faza 2 (b0 = 1): (ix+17) != 0 -> (ix+17) - 1 (100 tickow w miejscu, Vy bez zmian); (ix+17) = 0 -> Vy = $FFFF80 (-0,5 px/tick).
;  W nieparzystym ticku draw_sprite_string SPRTAB_end_chaos_emerald od POCZATKU tablicy sprite'ow (wskaznik = g_sprite_table,
;  licznik i wskaznik zachowane - wpisy nie licza sie do g_sprite_count; przednie wpisy jak chmura $30) w (x - scroll_x, y - scroll_y).
;  Potem co tick fazy 2 (faza 1 konczy sie wczesniej ret): y + $20 < scroll_y (16 bit bez znaku) -> licznik tabliczki = 1,
;  set 2 iy_0D (przejscie do g_level + 1 = $13 - zakonczenie i napisy).
; Pola rekordu: (ix+17) licznik faz, (ix+24) b0 = faza 2, b5 = bez kolizji z mapa.
; ---------------------------------------------------------------------
objfunc_54_end_emerald
	ldy #OB_FLAGS             ; 02:BF4C: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #OK54_ICON            ; 02:BF50: ld hl,$5400 / call write_partial_monitor_art (A = ikona 5; zg_obj, Y bez zmian)
	jsr zc_monart
	ldy #OB_FLAGS             ; 02:BF56: bit 0,(ix+24) / jr nz @already_initialised
	lda (zg_obj),y
	and #$01
	bne ok54_inited
	lda #0                    ; 02:BF5C: xor a / (ix+15) = (ix+16) = a - bez mapy
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_VX                ; 02:BF63: (ix+7) = (ix+8) = (ix+9) = a - Vx = 0
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #17                   ; 02:BF6C: inc (ix+17) / ld a,(ix+17) / cp $50 / ret c
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$50
	bcc ok54_ret
	ldy #OB_FLAGS             ; 02:BF75: set 0,(ix+24) - faza 2
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
	ldy #17                   ; 02:BF79: ld (ix+17),$64 / ret
	lda #$64
	sta (zg_obj),y
ok54_ret
	rts

ok54_inited                     ; 02:BF7E @already_initialised: ld a,(ix+17) / and a / jr z @fly_up
	ldy #17
	lda (zg_obj),y
	beq ok54_fly
	sec                       ; 02:BF84: dec (ix+17) / jr @skip_flying_up - jeszcze wisi
	sbc #1
	sta (zg_obj),y
	jmp ok54_flown
ok54_fly                        ; 02:BF89 @fly_up: (ix+10) = $80, (ix+11) = $FF, (ix+12) = $FF - Vy = $FFFF80 (-0,5 px/tick)
	ldy #OB_VY
	lda #$80
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	iny
	sta (zg_obj),y
ok54_flown                      ; 02:BF95 @skip_flying_up: (ld hl,SPRTAB_end_chaos_emerald - hl i tak nadpisany, bez skutku)
	lda g_global_tick_counter ; 02:BF98: ld a,(g_global_tick_counter) / rrca / jr nc @skip_sprite_draw_on_odd_tick
	lsr                       ; (wbrew nazwie: tick PARZYSTY - bez rysowania; rysowany w nieparzystym)
	bcc ok54_nodraw
	lda g_sprite_count        ; 02:BF9E: ld a,(iy+g_sprite_count) / ld hl,(g_next_avail_vdp_sprite_ptr) / push af / push hl
	pha
	lda g_next_avail_vdp_sprite_ptr
	pha
	lda g_next_avail_vdp_sprite_ptr+1
	pha
	lda #<OK54_SPRTAB         ; 02:BFA6: ld hl,g_sprite_table / ld (g_next_avail_vdp_sprite_ptr),hl - od wpisu 0 (przednie wpisy)
	sta g_next_avail_vdp_sprite_ptr
	lda #>OK54_SPRTAB
	sta g_next_avail_vdp_sprite_ptr+1
	ldy #OB_Y+1               ; 02:BFAC: hl = y (ix+5/6) / ld de,(g_level_scroll_y_pix_lo) / and a / sbc hl,de / ex de,hl
	sec                       ; - de = y ekranowe
	lda (zg_obj),y
	sbc g_level_scroll_y_pix_lo
	sta zd_y
	iny
	lda (zg_obj),y
	sbc g_level_scroll_y_pix_lo+1
	sta zd_y+1
	ldy #OB_X+1               ; 02:BFBA: hl = x (ix+2/3) / ld bc,(g_level_scroll_x_pix_lo) / and a / sbc hl,bc - x ekranowe
	sec
	lda (zg_obj),y
	sbc g_level_scroll_x_pix_lo
	sta zd_x
	iny
	lda (zg_obj),y
	sbc g_level_scroll_x_pix_lo+1
	sta zd_x+1
	lda #<OK54_SPR            ; 02:BFC7: ld bc,SPRTAB_end_chaos_emerald / call draw_sprite_string (zc_dss: mapa z tego banku;
	sta zd_map                ; tmp_06 = x ekranowe - jak oryginal; 2 wpisy od g_sprite_table, g_sprite_count + 2)
	lda #>OK54_SPR
	sta zd_map+1
	jsr zc_dss
	pla                       ; 02:BFCD: pop hl / pop af / ld (g_next_avail_vdp_sprite_ptr),hl / ld (iy+g_sprite_count),a
	sta g_next_avail_vdp_sprite_ptr+1
	pla
	sta g_next_avail_vdp_sprite_ptr
	pla
	sta g_sprite_count
ok54_nodraw                     ; 02:BFD5 @skip_sprite_draw_on_odd_tick: hl = y + $0020 / ld de,(g_level_scroll_y_pix_lo) /
	ldy #OB_Y+1               ; and a / sbc hl,de / ret nc - szmaragd jeszcze nie wylecial nad ekran
	clc
	lda (zg_obj),y
	adc #<$0020
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #>$0020
	sta zg_hl+1
	lda zg_hl                 ; (bez pozyczki - 6502 C = 1: y + 32 >= scroll_y)
	cmp g_level_scroll_y_pix_lo
	lda zg_hl+1
	sbc g_level_scroll_y_pix_lo+1
	bcs ok54_ret2
	lda #$01                  ; 02:BFE7: ld a,$01 / ld (g_signpost_tickdown_counter),a
	sta g_signpost_tickdown_counter
	lda iy_0D                 ; 02:BFEC: set 2,(iy+iy_0D) / ret - przejscie do $13 (zakonczenie)
	ora #$04
	sta iy_0D
ok54_ret2
	rts
