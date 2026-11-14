; =====================================================================
;  obj/objz2_sbz_badniki.asm - M6.9 Scrap Brain: badniki $1B Ballhog, $1C bomba Ballhoga, $1F Caterkiller (bank obiektow
;  strefy 2 PB_OBJZ2, bank 2, okno $4000-$7FFF; dolaczany z objz2.asm).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny):
;   objfunc_1B_badnik_ballhog      02:A1AA-02:A2D1, dane 02:A2D2-02:A33B (LUT_ballhog_anim_hopping 02:A2D2,
;     LUT_ballhog_anim_attack 02:A2D7, SPRTAB_ballhog_left 02:A2DA, SPRTAB_ballhog_right 02:A30B - po 3 klatki po 18 B;
;     klatka 2 lewej mapy zachodzi na prawa, ale jej 3. wiersz zaczyna sie od $FF (02:A30A) - koniec mapy),
;   objfunc_1C_badnik_ballhog_bomb 02:A33C-02:A3B0, dane 02:A3B1-02:A3F7 (LUT_ballhog_bomb_anim_normal 02:A3B1,
;     LUT_ballhog_bomb_anim_explosion 02:A3B4, SPRTAB_ballhog_bomb 02:A3BB - 4 klatki; ta sama mapa lezy tez w banku 11
;     dla bomby JUN3 $2B - obj/objz_jungle.asm, SPR_BALLHOG_BOMB),
;   objfunc_1F_badnik_caterkiller  02:A551-02:A6B8 (z lokalnymi @fn_draw_sprite_out_of_line 02:A688 i
;     @fn_draw_sprite_in_line 02:A6A2), dane 02:A6B9-02:A7EC (LUT_caterkiller_x_delta_going_left 02:A6B9 - 22 slowa,
;     LUT_caterkiller_y_out_of_line_double_delta 02:A6E5 - 22 slowa, LUT_caterkiller_x_offsets_going_left 02:A711 - 4 x 22 B,
;     LUT_caterkiller_x_delta_going_right 02:A769 - 22 slowa, LUT_caterkiller_x_offsets_going_right 02:A795 - 4 x 22 B).
;  Dane leza w tym banku pod adresem SMS - OZ_OFF (zakresy OZ2_SPAN8, OZ2_SPAN9, OZ2_SPAN12 w objdata.inc).
;  Procedury:
;   objfunc_1B_ballhog       (02:A1AA) - funkcja obiektu $1B (Ballhog: skacze w miejscu, co 256 tickow rzuca bombe)
;   bh_anim                  (02:A1E7 / 02:A25D) - wybor sekwencji (skoki / atak) wg (ix+17) i do_framed_animation
;   bh_spawn                 (02:A200 / 02:A276) - przy (ix+17) = $ED nowy obiekt $1C, potem inc (ix+17)
;   objfunc_1C_ballhog_bomb  (02:A33C) - funkcja obiektu $1C (bomba: odbija sie od podloza, potem wybucha)
;   objfunc_1F_caterkiller   (02:A551) - funkcja obiektu $1F (gasienica: 4 czlony rysowane draw_sprite)
;   cat_out / cat_in         (02:A688 / 02:A6A2) - jeden czlon poza linia / w linii (draw_sprite)
;  Obiekty tworzone w locie: $1C (bomba; spawn_object w bh_spawn).
;  Pola rekordu:
;   $1B: (ix+17) licznik 0..$FF (mod 256: od $EB animacja ataku, przy $ED bomba), (ix+22/23) licznik / indeks animacji
;        (oz2_dfa); Vy = $000100 co tick (przyciaga do podloza; kolizje z mapa wlaczone - bez set 5).
;   $1C: (ix+17) czas zycia 0..$A4 (od $82 wybuch, przy $A5 usuniecie), (ix+22/23) animacja, (ix+24) b7 = na ziemi (z obj_motion
;        poprzedniego ticku) -> odbicie Vy = $FFFD00; res 5 co tick (kolizje z mapa wlaczone).
;   $1F: X 24 bit (ix+1..3) przesuwany wprost (bez Vx), (ix+17) faza kroku 0..$15 (+ 1 co drugi tick), (ix+18/19) akumulator
;        przesuniecia Y czlonow "poza linia" (subpiksel, piksel), (ix+20) = rozszerzenie znaku (ix+19), (ix+21) licznik krokow
;        0..$13 do zawrotu, (ix+24) b1 = ruch w prawo; (ix+11) = 1 co tick (Vy +1 px - przyciaga do podloza).
;  Wola: zc_collide (check_collision_with_sonic 00:3956), zc_enemy (enemy_touched_sonic 00:35E5), zc_dspr (draw_sprite 00:3581) -
;  stuby do banku 45 (game/objcom.asm); damage_sonic (00:35FD), spawn_object (01:7C7B), play_sfx (rst $28) - kod rezydentny
;  $8000+ (game/objcom.asm); oz2_dfa (kopia do_framed_animation 01:7C41 w tym banku: zg_bc = sekwencja - adres okna,
;  zg_de = baza map - adres SMS). Wskazniki map (ix+15/16) zostaja adresami SMS ($Axxx) - obj_draw kopiuje mape z tego banku
;  (objz_mapcopy).
;  Rejestry Z80: IX = zg_obj, HL nowego obiektu (spawn_object) = zg_ptr, BC = zg_bc, DE = zg_de, HL = zg_hl.
;  Caterkiller: zg_de = e (indeks slowa w tablicach dX / dY), zg_bc = indeks bajtu offsetu X czlonu (wskaznik hl w oryginale)
;  - zc_dspr go nie niszczy (draw_sprite uzywa zd_* i X).
; =====================================================================
; adresy SMS danych (czytane w tym banku pod adresem SMS - OZ_OFF)
LUT_BH_HOP      = $A2D2   ; LUT_ballhog_anim_hopping: (0, $1C), (1, 6), $FF - klatka, czas
LUT_BH_ATK      = $A2D7   ; LUT_ballhog_anim_attack: (2, $18), $FF
SPR_BH_L        = $A2DA   ; SPRTAB_ballhog_left (klatka = 18 B)
SPR_BH_R        = $A30B   ; SPRTAB_ballhog_right
LUT_BHB_NORM    = $A3B1   ; LUT_ballhog_bomb_anim_normal: (0, 8), $FF
LUT_BHB_EXPL    = $A3B4   ; LUT_ballhog_bomb_anim_explosion: (1, $0C), (2, $0C), (3, $0C), $FF
SPR_BHB         = $A3BB   ; SPRTAB_ballhog_bomb (= SPR_BALLHOG_BOMB banku 11; klatka 3 = $A3F1, jej 2. wiersz od $A3F7 = $FF)
LUT_CAT_DXL     = $A6B9   ; LUT_caterkiller_x_delta_going_left: dX (slowo ze znakiem, subpiksele) wg fazy (ix+17)
LUT_CAT_DY      = $A6E5   ; LUT_caterkiller_y_out_of_line_double_delta: przyrost akumulatora Y (ix+18/19) wg fazy
LUT_CAT_XOFFL   = $A711   ; LUT_caterkiller_x_offsets_going_left: 4 tablice po 22 B (offset X czlonu 0..3 wg fazy)
LUT_CAT_DXR     = $A769   ; LUT_caterkiller_x_delta_going_right
LUT_CAT_XOFFR   = $A795   ; LUT_caterkiller_x_offsets_going_right (= LUT_CAT_XOFFL + $84; indeks 8 bit: $84 + 3 * $16 + $15 < $100)

; ---------------------------------------------------------------------
; objfunc_1B_badnik_ballhog (02:A1AA): 10 x 32, trafienie Sonica (przesuniecie (3, 8)) -> enemy_touched_sonic (tmp_00 = $0E00:
; wybuch przesuniety o (0, $0E)). Vy = $000100. Strona Sonica: sonic_x + 12 >= x + 10 (16 bit) -> na prawo (mapa _right, bomba
; Vx = $000100), inaczej na lewo (mapa _left, bomba Vx = $FFFF00). Animacja: (ix+17) < $EB - skoki, >= $EB - atak (przy rownosci
; (ix+22) = 0; indeks (ix+23) bez zerowania - jak oryginal). (ix+17) = $ED -> bomba $1C w (x, y + 6), Vy bomby = $000100.
; Na koniec inc (ix+17) (8 bit, zawiniecie $FF -> 0).
; Uwaga (oryginal): przejscie na sekwencje ataku z indeksem (ix+23) = 4 (skok w drugiej parze skonczony dokladnie w ticku $EA)
; czyta bajty za LUT_ballhog_anim_attack (02:A2DB = $42, czas $FF) - mapa $A2DA + $42 * 18 = $A77E (dane Caterkillera, ten sam
; bank, OZ2_SPAN12); oz2_dfa odtwarza to samo.
; ---------------------------------------------------------------------
objfunc_1B_ballhog
	ldy #OB_W                 ; 02:A1AA: (ix+13) = $0A, (ix+14) = $20
	lda #$0A
	sta (zg_obj),y
	iny
	lda #$20
	sta (zg_obj),y
	lda #$03                  ; 02:A1B2: ld hl,$0803 / ld (tmp_06),hl: tmp_06 = 3, tmp_07 = 8
	sta tmp_06
	lda #$08
	sta tmp_07
	jsr zc_collide            ; 02:A1B8: call check_collision_with_sonic
	lda #$00                  ; 02:A1BB: ld hl,$0E00 / ld (tmp_00),hl: tmp_00 = 0, tmp_01 = $0E (lda/sta nie zmieniaja C)
	sta tmp_00
	lda #$0E
	sta tmp_00+1
	bcs bh_nohit              ; 02:A1C1: call nc,enemy_touched_sonic
	jsr zc_enemy
bh_nohit
	ldy #OB_VY                ; 02:A1C4: (ix+10) = 0, (ix+11) = 1, (ix+12) = 0 - Vy = $000100
	lda #$00
	sta (zg_obj),y
	iny
	lda #$01
	sta (zg_obj),y
	iny
	lda #$00
	sta (zg_obj),y
	ldy #OB_X+1               ; 02:A1D0: de = x + $000A (16 bit)
	clc
	lda (zg_obj),y
	adc #$0A
	sta zg_de
	iny
	lda (zg_obj),y
	adc #$00
	sta zg_de+1
	clc                       ; 02:A1DB: hl = sonic_x + $000C (16 bit)
	lda sonic_x
	adc #$0C
	sta zg_hl
	lda sonic_x+1
	adc #$00
	sta zg_hl+1
	sec                       ; 02:A1E2: and a / sbc hl,de / jr nc @sonic_is_on_right (6502: C = 1 = bez pozyczki)
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs bh_right
	lda #<SPR_BH_L            ; 02:A1FA: de = SPRTAB_ballhog_left, sekwencja wg (ix+17), call do_framed_animation
	sta zg_de
	lda #>SPR_BH_L
	sta zg_de+1
	jsr bh_anim
	lda #$FF                  ; bomba w lewo: (ix+8) = $FF, (ix+9) = $FF (Vx = $FFFF00)
	bne bh_spawn              ; zawsze
bh_right                        ; 02:A25D @sonic_is_on_right
	lda #<SPR_BH_R            ; 02:A270: de = SPRTAB_ballhog_right
	sta zg_de
	lda #>SPR_BH_R
	sta zg_de+1
	jsr bh_anim
	lda #$01                  ; bomba w prawo: (ix+8) = $01, (ix+9) = 0 (Vx = $000100)
	; dalej bh_spawn

; bh_spawn (02:A200 / 02:A276): A = (ix+8) bomby (piksel Vx; (ix+9) = $FF gdy bit 7, inaczej 0). (ix+17) = $ED -> spawn_object;
; nowy obiekt: (ix+0) = $1C, (ix+1) = 0, (ix+2/3) = x Ballhoga, (ix+4) = 0, (ix+5/6) = y + 6 (16 bit), (ix+17) = (ix+22) =
; (ix+23) = 0, Vx = (0, A, znak), Vy = $000100. Pozostale pola slotu bez zmian (oryginal ich nie czysci). Brak miejsca -
; bez bomby. Potem @inc_timer_and_return (02:A2CE): inc (ix+17) Ballhoga.
bh_spawn
	pha                       ; Vx bomby (spawn_object niszczy A, X, Y)
	ldy #17                   ; 02:A200: ld a,(ix+17) / cp $ED / jp nz @inc_timer_and_return
	lda (zg_obj),y
	cmp #$ED
	bne bh_pinc
	jsr spawn_object          ; 02:A208: call spawn_object / jp c @inc_timer_and_return
	bcs bh_pinc
	ldy #OB_TYPE              ; 02:A220: (ix+0) = $1C, (ix+1) = a = 0 (xor a)
	lda #$1C
	sta (zg_ptr),y
	lda #$00
	iny
	sta (zg_ptr),y
	ldy #OB_X+1               ; 02:A227: (ix+2) = e, (ix+3) = d (de = x Ballhoga)
	lda (zg_obj),y
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	sta (zg_ptr),y
	lda #$00                  ; 02:A231: (ix+4) = 0
	iny
	sta (zg_ptr),y
	ldy #OB_Y+1               ; 02:A22D: hl = bc + $0006 (bc = y Ballhoga); (ix+5) = l, (ix+6) = h
	clc
	lda (zg_obj),y
	adc #$06
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_ptr),y
	lda #$00                  ; 02:A23A: (ix+17) = (ix+22) = (ix+23) = 0
	ldy #17
	sta (zg_ptr),y
	ldy #22
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	ldy #OB_VX                ; 02:A243: (ix+7) = 0
	sta (zg_ptr),y
	pla                       ; 02:A246 / 02:A2BB: (ix+8) = $FF (w lewo) albo $01 (w prawo)
	iny
	sta (zg_ptr),y
	and #$80                  ; 02:A24A / 02:A2BF: (ix+9) = $FF (w lewo) albo 0 (w prawo)
	beq bh_vxhi
	lda #$FF
bh_vxhi
	iny
	sta (zg_ptr),y
	lda #$00                  ; 02:A24E: (ix+10) = 0, (ix+11) = 1, (ix+12) = 0 - Vy bomby = $000100
	iny
	sta (zg_ptr),y
	lda #$01
	iny
	sta (zg_ptr),y
	lda #$00
	iny
	sta (zg_ptr),y
	jmp bh_inc                ; 02:A258: pop ix / jp @inc_timer_and_return
bh_pinc
	pla                       ; bez bomby: zdjecie Vx ze stosu
bh_inc                          ; 02:A2CE @inc_timer_and_return: inc (ix+17) (8 bit)
	ldy #17
	lda (zg_obj),y
	clc
	adc #$01
	sta (zg_obj),y
	rts

; bh_anim (02:A1E7 / 02:A25D): zg_de = baza map (adres SMS). bc = skoki; (ix+17) >= $EB -> bc = atak, przy (ix+17) = $EB najpierw
; (ix+22) = 0 (cp $EB / jr c / jr nz). call do_framed_animation (oz2_dfa).
bh_anim
	ldy #17                   ; ld a,(ix+17) / cp $EB / jr c @..._selected_hopping_anim
	lda (zg_obj),y
	cmp #$EB
	bcc bh_hop
	bne bh_atk                ; jr nz @..._already_reset_attack_anim
	lda #$00                  ; (ix+17) = $EB: (ix+22) = 0
	ldy #22
	sta (zg_obj),y
bh_atk                          ; bc = LUT_ballhog_anim_attack
	lda #<[LUT_BH_ATK-OZ_OFF]
	ldx #>[LUT_BH_ATK-OZ_OFF]
	bne bh_aset               ; zawsze (starszy bajt adresu okna <> 0)
bh_hop                          ; bc = LUT_ballhog_anim_hopping
	lda #<[LUT_BH_HOP-OZ_OFF]
	ldx #>[LUT_BH_HOP-OZ_OFF]
bh_aset
	sta zg_bc
	stx zg_bc+1
	jmp oz2_dfa               ; call do_framed_animation

; ---------------------------------------------------------------------
; objfunc_1C_badnik_ballhog_bomb (02:A33C): bomba Ballhoga 10 x 15 (res 5: kolizje z mapa wlaczone), trafienie Sonica (przesuniecie
; (1, 1)) -> damage_sonic. Na ziemi (b7 flag z obj_motion poprzedniego ticku) odbicie: Vy = $FFFD00. Grawitacja: Vy (24 bit) + $1F.
; (ix+17) < $82 - animacja bomby; >= $82 - animacja wybuchu (przy $82: (ix+22) = 0 i efekt $01; indeks (ix+23) bez zerowania -
; jak oryginal, wiec przy (ix+23) = 2 wybuch zaczyna od klatki 2). inc (ix+17); od $A5 usuniecie (typ $FF).
; ---------------------------------------------------------------------
objfunc_1C_ballhog_bomb
	ldy #OB_FLAGS             ; 02:A33C: res 5,(ix+24)
	lda (zg_obj),y
	and #$DF
	sta (zg_obj),y
	ldy #OB_W                 ; 02:A340: (ix+13) = $0A, (ix+14) = $0F
	lda #$0A
	sta (zg_obj),y
	iny
	lda #$0F
	sta (zg_obj),y
	lda #$01                  ; 02:A348: ld hl,$0101 / ld (tmp_06),hl
	sta tmp_06
	sta tmp_07
	jsr zc_collide            ; 02:A34E: call check_collision_with_sonic / call nc,damage_sonic
	bcs bhb_nohit
	jsr damage_sonic
bhb_nohit
	ldy #OB_FLAGS             ; 02:A354: bit 7,(ix+24) / jr z @skip_bounce_off_ground
	lda (zg_obj),y
	bpl bhb_air
	ldy #OB_VY                ; 02:A35A: odbicie - (ix+10) = 0, (ix+11) = $FD, (ix+12) = $FF (Vy = $FFFD00)
	lda #$00
	sta (zg_obj),y
	iny
	lda #$FD
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
bhb_air                         ; 02:A366 @skip_bounce_off_ground: hl = Vy + $001F, a = (ix+12) + przeniesienie (adc a,$00)
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc #$1F
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y
	ldy #17                   ; 02:A37E: ld a,(ix+17) / cp $82 / jr nc @explode
	lda (zg_obj),y
	cmp #$82
	bcs bhb_expl
	lda #<[LUT_BHB_NORM-OZ_OFF] ; 02:A385: bc = LUT_ballhog_bomb_anim_normal, de = SPRTAB_ballhog_bomb, call do_framed_animation
	ldx #>[LUT_BHB_NORM-OZ_OFF]
	jsr bhb_anim
	jmp bhb_inc               ; 02:A38E: jp @inc_timer_and_maybe_destroy
bhb_expl                        ; 02:A391 @explode (flagi z cp $82: Z = rowne)
	bne bhb_nosfx             ; jr nz @skip_sound_effect_and_anim_reset
	lda #$00                  ; 02:A393: (ix+22) = 0
	ldy #22
	sta (zg_obj),y
	lda #$01                  ; 02:A397: ld a,$01 / rst $28 - efekt wybuchu
	jsr play_sfx
bhb_nosfx                       ; 02:A39A @skip_sound_effect_and_anim_reset: bc = LUT_ballhog_bomb_anim_explosion
	lda #<[LUT_BHB_EXPL-OZ_OFF]
	ldx #>[LUT_BHB_EXPL-OZ_OFF]
	jsr bhb_anim
bhb_inc                         ; 02:A3A3 @inc_timer_and_maybe_destroy: inc (ix+17) / cp $A5 / ret c
	ldy #17
	lda (zg_obj),y
	clc
	adc #$01
	sta (zg_obj),y
	cmp #$A5
	bcc bhb_ret
	lda #$FF                  ; 02:A3AC: (ix+0) = $FF - usuniecie
	ldy #OB_TYPE
	sta (zg_obj),y
bhb_ret
	rts

; bhb_anim: A/X = sekwencja (adres okna) -> zg_bc, de = SPRTAB_ballhog_bomb (adres SMS), call do_framed_animation (oz2_dfa)
bhb_anim
	sta zg_bc
	stx zg_bc+1
	lda #<SPR_BHB
	sta zg_de
	lda #>SPR_BHB
	sta zg_de+1
	jmp oz2_dfa

; ---------------------------------------------------------------------
; objfunc_1F_badnik_caterkiller (02:A551): gasienica z 4 czlonow (kafle: w lewo glowa $24 + 3 x $26, w prawo glowa $2A + 3 x $28),
; bez mapy sprite'ow (ix+15/16 nie ustawiane - zostaja 0 z wczytania obiektu), rysowana draw_sprite. Kolizje z mapa wlaczone.
; Co drugi tick (tick & 1 = 0): X (24 bit, ix+1..3) += dX[faza] (slowo ze znakiem; tablica wg b1 flag), akumulator (ix+18/19) +=
; dY[faza], (ix+20) = znak (ix+19). Co tick: tmp_00 = x, tmp_02 = y; 4 czlony: offset X z tablicy (4 x 22 B, kolejne czlony co $16),
; czlony 0 i 2 "poza linia" (tmp_06 = (ix+19/20)), 1 i 3 w linii (tmp_06 = 0). Kolizje (wysokosc $10):
;  w lewo:  glowa (ix+13) = 6, (2, 8) -> enemy_touched_sonic (tmp_00 = 0); bez trafienia - cialo (ix+13) = $16, (6, 8) -> damage_sonic;
;  w prawo: cialo (ix+13) = $10, (1, 4) -> damage_sonic; bez trafienia - glowa (ix+13) = $16, ($10, 4) -> enemy_touched_sonic
;           (tmp_00 = 0; przy trafieniu ciala tmp_00 zostaje = x - jak oryginal).
; Na koniec (ix+11) = 1; w parzystym ticku faza (ix+17) + 1, przy $16 -> 0 i (ix+21) + 1, przy $14 -> 0 i zawrot (b1 flag xor).
; ---------------------------------------------------------------------
objfunc_1F_caterkiller
	ldy #OB_W                 ; 02:A551: (ix+13) = 6, (ix+14) = $10
	lda #$06
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	lda g_global_tick_counter ; 02:A559: and $01 / jr nz @tick_mod_2_was_not_0 - ruch tylko w parzystym ticku
	and #$01
	jne cat_draw
	ldy #17                   ; 02:A56C: ld e,(ix+17) / sla e / ld d,$00 - e = faza * 2 ((ix+17) < $16 - bez przeniesienia)
	lda (zg_obj),y
	asl
	sta zg_de
	tax
	ldy #OB_FLAGS             ; 02:A560: hl = dX w lewo; bit 1,(ix+24) = 1 -> dX w prawo
	lda (zg_obj),y
	and #$02
	bne cat_dxr
	lda LUT_CAT_DXL-OZ_OFF,x  ; 02:A573: add hl,de / ld c,(hl) / inc hl / ld b,(hl) - bc = dX
	sta zg_bc
	lda LUT_CAT_DXL+1-OZ_OFF,x
	jmp cat_dxset
cat_dxr                         ; LUT_caterkiller_x_delta_going_right
	lda LUT_CAT_DXR-OZ_OFF,x
	sta zg_bc
	lda LUT_CAT_DXR+1-OZ_OFF,x
cat_dxset
	sta zg_bc+1
	ldy #OB_X                 ; 02:A577: hl = (ix+1/2), a = (ix+3); add hl,bc
	clc
	lda (zg_obj),y
	adc zg_bc
	sta (zg_obj),y            ; 02:A58B: (ix+1) = l
	iny
	lda (zg_obj),y
	adc zg_bc+1
	sta (zg_obj),y            ; (ix+2) = h
	iny
	ldx #$00                  ; 02:A581: bit 7,b -> adc a,$FF, inaczej adc a,$00 (ldx/lda/bpl nie zmieniaja C)
	lda zg_bc+1
	bpl cat_dxpos
	ldx #$FF
cat_dxpos
	txa
	adc (zg_obj),y
	sta (zg_obj),y            ; (ix+3) = a
	ldx zg_de                 ; 02:A594: hl = LUT_caterkiller_y_out_of_line_double_delta + de; de = slowo (to samo e)
	ldy #18                   ; 02:A59B: hl = (ix+18/19) + de (16 bit); (ix+18) = l, (ix+19) = h
	clc
	lda (zg_obj),y
	adc LUT_CAT_DY-OZ_OFF,x
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc LUT_CAT_DY+1-OZ_OFF,x
	sta (zg_obj),y
	iny
	and #$80                  ; 02:A5A8: c = $FF gdy bit 7,h, inaczej 0; (ix+20) = c
	beq cat_dypos
	lda #$FF
cat_dypos
	sta (zg_obj),y
cat_draw                        ; 02:A5B3 @tick_mod_2_was_not_0: tmp_00 = (ix+2/3) = x, tmp_02 = (ix+5/6) = y
	ldy #OB_X+1
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
	ldy #17                   ; ld e,(ix+17) / ld d,$00 / add hl,de: zg_bc = indeks offsetu czlonu 0 (od LUT_CAT_XOFFL)
	lda (zg_obj),y
	sta zg_bc
	ldy #OB_FLAGS             ; 02:A5C5: bit 1,(ix+24) / jr nz @sprite_drawing_goes_right
	lda (zg_obj),y
	and #$02
	jne cat_right
	lda #$24                  ; 02:A5D4: glowa $24 poza linia
	jsr cat_out
	lda #$26                  ; 02:A5D9: czlon $26 w linii
	jsr cat_in
	lda #$26                  ; 02:A5DE: czlon $26 poza linia
	jsr cat_out
	lda #$26                  ; 02:A5E3: czlon $26 w linii
	jsr cat_in
	ldy #OB_W                 ; 02:A5E8: glowa (z lewej): (ix+13) = 6; ld hl,$0802 / ld (tmp_06),hl - tmp_06 = 2, tmp_07 = 8
	lda #$06
	sta (zg_obj),y
	lda #$02
	sta tmp_06
	lda #$08
	sta tmp_07
	jsr zc_collide            ; 02:A5F2: call check_collision_with_sonic
	lda #$00                  ; 02:A5F5: ld hl,$0000 / ld (tmp_00),hl (przed jr c; lda/sta nie zmieniaja C)
	sta tmp_00
	sta tmp_00+1
	bcs cat_lbody             ; jr c @left_sonic_did_not_touch_damageable_box
	jsr zc_enemy              ; 02:A5FD: call enemy_touched_sonic / jr @update_indices_on_active_tick
	jmp cat_upd
cat_lbody                       ; 02:A602 @left_sonic_did_not_touch_damageable_box: cialo (ix+13) = $16; tmp_06 = 6, tmp_07 = 8
	ldy #OB_W
	lda #$16
	sta (zg_obj),y
	lda #$06
	sta tmp_06
	lda #$08
	sta tmp_07
	jsr zc_collide            ; 02:A60C: call check_collision_with_sonic / call nc,damage_sonic
	bcs cat_upd
	jsr damage_sonic
	jmp cat_upd               ; 02:A612: jr @update_indices_on_active_tick
cat_right                       ; 02:A614 @sprite_drawing_goes_right: LUT_caterkiller_x_offsets_going_right = LUT_CAT_XOFFL + $84
	lda zg_bc
	clc
	adc #LUT_CAT_XOFFR-LUT_CAT_XOFFL
	sta zg_bc
	lda #$2A                  ; 02:A61D: glowa $2A poza linia
	jsr cat_out
	lda #$28                  ; 02:A622: czlon $28 w linii
	jsr cat_in
	lda #$28                  ; 02:A627: czlon $28 poza linia
	jsr cat_out
	lda #$28                  ; 02:A62C: czlon $28 w linii
	jsr cat_in
	ldy #OB_W                 ; 02:A631: cialo: (ix+13) = $10; ld hl,$0401 / ld (tmp_06),hl - tmp_06 = 1, tmp_07 = 4
	lda #$10
	sta (zg_obj),y
	lda #$01
	sta tmp_06
	lda #$04
	sta tmp_07
	jsr zc_collide            ; 02:A63B: call check_collision_with_sonic / jr c @right_sonic_did_not_touch_damageable_box
	bcs cat_rhead
	jsr damage_sonic          ; 02:A640: call damage_sonic / jr @update_indices_on_active_tick (tmp_00 zostaje = x)
	jmp cat_upd
cat_rhead                       ; 02:A645 @right_sonic_did_not_touch_damageable_box: glowa (z prawej) (ix+13) = $16; tmp_06 = $10, tmp_07 = 4
	ldy #OB_W
	lda #$16
	sta (zg_obj),y
	lda #$10
	sta tmp_06
	lda #$04
	sta tmp_07
	jsr zc_collide            ; 02:A64F: call check_collision_with_sonic
	lda #$00                  ; 02:A652: ld hl,$0000 / ld (tmp_00),hl (przed call nc)
	sta tmp_00
	sta tmp_00+1
	bcs cat_upd               ; 02:A658: call nc,enemy_touched_sonic
	jsr zc_enemy
cat_upd                         ; 02:A65B @update_indices_on_active_tick: (ix+11) = 1
	ldy #OB_VY+1
	lda #$01
	sta (zg_obj),y
	lda g_global_tick_counter ; 02:A65F: and $01 / ret nz
	and #$01
	bne cat_ret
	ldy #17                   ; 02:A665: inc (ix+17) / cp $16 / ret c
	lda (zg_obj),y
	clc
	adc #$01
	sta (zg_obj),y
	cmp #$16
	bcc cat_ret
	lda #$00                  ; 02:A66E: (ix+17) = 0; inc (ix+21) / cp $14 / ret c
	sta (zg_obj),y
	ldy #21
	lda (zg_obj),y
	clc
	adc #$01
	sta (zg_obj),y
	cmp #$14
	bcc cat_ret
	lda #$00                  ; 02:A67B: (ix+21) = 0; (ix+24) xor $02 - zawrot
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	eor #$02
	sta (zg_obj),y
cat_ret
	rts

; cat_out (@fn_draw_sprite_out_of_line 02:A688): A = kafel; tmp_04 = offset X z tablicy (zg_bc; d = 0), tmp_06 = (ix+19), tmp_07 =
; (ix+20) - czlon podniesiony / opuszczony o akumulator Y; call draw_sprite; zg_bc + $16 (nastepny czlon - nastepna tablica 22 B).
cat_out
	pha                       ; push hl (kafel w A)
	ldx zg_bc                 ; ld e,(hl) / ld d,$00 / ld (tmp_04),de
	lda LUT_CAT_XOFFL-OZ_OFF,x
	sta tmp_04
	lda #$00
	sta tmp_04+1
	ldy #19                   ; ld l,(ix+19) / ld h,(ix+20) / ld (tmp_06),hl
	lda (zg_obj),y
	sta tmp_06
	iny
	lda (zg_obj),y
	sta tmp_07
	jmp cat_spr

; cat_in (@fn_draw_sprite_in_line 02:A6A2): jak cat_out, ale tmp_06 = $0000 (czlon w linii)
cat_in
	pha
	ldx zg_bc                 ; ld e,(hl) / ld d,$00 / ld (tmp_04),de
	lda LUT_CAT_XOFFL-OZ_OFF,x
	sta tmp_04
	lda #$00
	sta tmp_04+1
	sta tmp_06                ; ld hl,$0000 / ld (tmp_06),hl
	sta tmp_07
cat_spr
	pla
	jsr zc_dspr               ; call draw_sprite (A = kafel; zg_bc zachowany)
	lda zg_bc                 ; pop hl / ld de,$0016 / add hl,de
	clc
	adc #$16
	sta zg_bc
	rts
