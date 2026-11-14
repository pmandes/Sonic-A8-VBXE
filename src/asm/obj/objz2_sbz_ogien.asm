; =====================================================================
;  obj/objz2_sbz_ogien.asm - M6.9 Scrap Brain: $14 / $15 miotacze ognia, $16 plomien z sufitu, $1A zapper (bank obiektow
;  strefy 2 PB_OBJZ2, bank 2, okno $4000-$7FFF; dolaczany z objz2.asm).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny):
;   objfunc_14_SCR_flamer_firing_right 02:9BE8-02:9C68 (z @common_entry 02:9BFC), dane SPRTAB_SCR_flame_right 02:9C69-02:9C6F,
;   objfunc_15_SCR_flamer_firing_left  02:9C70-02:9C86 (skok do @common_entry $14), dane SPRTAB_SCR_flame_left 02:9C87-02:9C8D,
;   objfunc_16_SCR_ceiling_flamer      02:9C8E-02:9D49, dane 02:9D4A-02:9DF9 (PTRLUT_ceiling_flame_sprite_sequences 16 slow,
;     LUT_ceiling_flame_collision_heights 16 B, LUT_ceiling_flame_sprites_25 / _1B / _1F / _22 po 32 B),
;   objfunc_1A_SCR_zapper              02:A0E8-02:A166, dane 02:A167-02:A1A9 (LUT_zapper_anim_zapping, LUT_zapper_anim_warning,
;     SPRTAB_SCR_zapper - 3 klatki po 18 B + 1 B).
;  Dane leza w tym banku pod adresem SMS - OZ_OFF (zakresy OZ2_SPAN1, OZ2_SPAN2, OZ2_SPAN3, OZ2_SPAN7 w objdata.inc).
;  Procedury:
;   objfunc_14_flamer_right   (02:9BE8) - funkcja obiektu $14 (kula ognia z rury w prawo)
;   objfunc_15_flamer_left    (02:9C70) - funkcja obiektu $15 (w lewo; wspolna reszta fl1_common = @common_entry 02:9BFC)
;   objfunc_16_ceiling_flamer (02:9C8E) - funkcja obiektu $16 (plomien bijacy z sufitu)
;   objfunc_1A_zapper         (02:A0E8) - funkcja obiektu $1A (luk elektryczny)
;  Pola rekordu:
;   $14/$15: (ix+17/18) x startowe (lo, hi), (ix+19) licznik cyklu 0..$EF, (ix+24) b0 = zainicjowany, b5 = bez kolizji z mapa.
;   $16:     (ix+17) faza 0..$FF (start z random_A), (ix+24) b0 = zainicjowany, b5.
;   $1A:     (ix+17) licznik cyklu 0..$9F, (ix+22/23) licznik / indeks animacji (oz2_dfa), (ix+24) b0 = zainicjowany, b5.
;  Wola: zc_collide (check_collision_with_sonic 00:3956), zc_dspr (draw_sprite 00:3581) - stuby do banku 45 (game/objcom.asm);
;  damage_sonic (00:35FD), random_A (00:0625), play_sfx (rst $28) - kod rezydentny $8000+ (game/objcom.asm); oz2_dfa (kopia
;  do_framed_animation 01:7C41 w tym banku: zg_bc = sekwencja - adres okna, zg_de = baza map - adres SMS).
;  Bez obiektow tworzonych w locie. Wskazniki map (ix+15/16) zostaja adresami SMS ($9xxx / $Axxx) - obj_draw kopiuje mape
;  z tego banku (objz_mapcopy).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl; zg_a - indeks bajtu w tablicy par (plomien z sufitu).
; =====================================================================
; adresy SMS danych (czytane w tym banku pod adresem SMS - OZ_OFF)
SPR_FLM_R       = $9C69   ; SPRTAB_SCR_flame_right: $0C, $0E, $FF x 5 (mapa 1 wiersza, 2 kafle; wiersz 2 od $9C6F = $FF - koniec)
SPR_FLM_L       = $9C87   ; SPRTAB_SCR_flame_left:  $2C, $2E, $FF x 5
PTR_CFL         = $9D4A   ; PTRLUT_ceiling_flame_sprite_sequences: 16 slow (adresy SMS); 7 x ENTRY_RESET (= $0000, brak plomienia),
                          ; potem _1B, _1F, _22, _25, _25, _25, _22, _1F, _1B (tablice par po 32 B: $9D7A, $9D9A, $9DBA, $9DDA)
LUT_CFL_H       = $9D6A   ; LUT_ceiling_flame_collision_heights: 7 x $00, $1B, $1F, $22, $25, $25, $25, $22, $1F, $1B
LUT_ZAP_Z       = $A167   ; LUT_zapper_anim_zapping: (0, 1), (1, 1), (2, 1), $FF - klatka, czas
LUT_ZAP_W       = $A16E   ; LUT_zapper_anim_warning: (2, 1), (3, 1), $FF
SPR_ZAP         = $A173   ; SPRTAB_SCR_zapper (klatka = 18 B; klatka 3 = $A1A9 - bajt $FF na poczatku wiersza = pusta mapa)

; ---------------------------------------------------------------------
; objfunc_14_SCR_flamer_firing_right (02:9BE8) / objfunc_15_SCR_flamer_firing_left (02:9C70): kula ognia wylatujaca z rury.
; Co tick (przed wspolna czescia): Vx = $000180 (+1,5 px/tick; $15: $FFFE80) i mapa SPRTAB_SCR_flame_right ($15: _left).
; @common_entry (02:9BFC): set 5 (bez kolizji z mapa); pierwszy tick (b0 = 0): (ix+17/18) = x (bajty pikseli (ix+2/3)), efekt $18,
; set 0. Potem pole 6 x 8; licznik (ix+19) < $64 - trafienie Sonica (przesuniecie (0, 4)) -> damage_sonic. Licznik + 1:
; < $64 - koniec (kula leci); $64..$EF - niewidoczna i stoi (mapa 0, Vx = 0); = $F0 - powrot: (ix+1) = 0 (subpiksel x),
; licznik 0, x = (ix+17/18), efekt $18 (kula leci od nowa w nastepnym ticku).
; ---------------------------------------------------------------------
objfunc_14_flamer_right
	ldy #OB_VX                ; 02:9BE8: ld (ix+7),$80 / ld (ix+8),$01 / ld (ix+9),$00 - Vx = $000180
	lda #$80
	sta (zg_obj),y
	iny
	lda #$01
	sta (zg_obj),y
	iny
	lda #$00
	sta (zg_obj),y
	ldy #OB_SPRITE            ; 02:9BF4: (ix+15/16) = SPRTAB_SCR_flame_right (adres SMS)
	lda #<SPR_FLM_R
	sta (zg_obj),y
	iny
	lda #>SPR_FLM_R
	sta (zg_obj),y
	; dalej wprost do @common_entry

fl1_common                      ; @common_entry (02:9BFC)
	ldy #OB_FLAGS             ; set 5,(ix+24): bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01                  ; 02:9C00: bit 0,(ix+24) / jr nz @already_initialised
	bne fl1_inited
	ldy #OB_X+1               ; 02:9C06: (ix+17) = (ix+2), (ix+18) = (ix+3) - x startowe (bez subpiksela)
	lda (zg_obj),y
	ldy #17
	sta (zg_obj),y
	ldy #OB_X+2
	lda (zg_obj),y
	ldy #18
	sta (zg_obj),y
	lda #$18                  ; 02:9C12: ld a,$18 / rst $28 - efekt wylotu ognia (play_sfx zachowuje X, Y; A zmienione)
	jsr play_sfx
	ldy #OB_FLAGS             ; 02:9C15: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
fl1_inited                      ; @already_initialised (02:9C19)
	ldy #OB_W                 ; (ix+13) = $06, (ix+14) = $08
	lda #$06
	sta (zg_obj),y
	iny
	lda #$08
	sta (zg_obj),y
	ldy #19                   ; 02:9C21: ld a,(ix+19) / cp $64 / jr nc @is_immaterial (6502: C = 1 gdy a >= $64)
	lda (zg_obj),y
	cmp #$64
	bcs fl1_immat
	lda #$00                  ; 02:9C28: ld hl,$0400 / ld (tmp_06),hl - tmp_06 = $00 (przesuniecie x), tmp_07 = $04 (y)
	sta tmp_06
	lda #$04
	sta tmp_07
	jsr zc_collide            ; 02:9C2E: call check_collision_with_sonic (C = 1 - brak trafienia)
	bcs fl1_immat             ; 02:9C31: call nc,damage_sonic
	jsr damage_sonic
fl1_immat                       ; @is_immaterial (02:9C34): inc (ix+19) / ld a,(ix+19)
	ldy #19
	lda (zg_obj),y
	clc
	adc #$01                  ; 8 bit z zawinieciem jak inc (ix+19)
	sta (zg_obj),y
	cmp #$64                  ; 02:9C3A: cp $64 / ret c - kula jeszcze leci
	bcc fl1_ret
	cmp #$F0                  ; 02:9C3D: cp $F0 / jr c @reset_x_pos_and_be_invisible ($64..$EF)
	bcc fl1_hide
	lda #$00                  ; 02:9C41: xor a / ld (ix+1),a / ld (ix+19),a - subpiksel x = 0, licznik = 0
	ldy #OB_X
	sta (zg_obj),y
	ldy #19
	sta (zg_obj),y
	ldy #17                   ; 02:9C48: (ix+2) = (ix+17), (ix+3) = (ix+18) - x startowe
	lda (zg_obj),y
	ldy #OB_X+1
	sta (zg_obj),y
	ldy #18
	lda (zg_obj),y
	ldy #OB_X+2
	sta (zg_obj),y
	lda #$18                  ; 02:9C54: ld a,$18 / rst $28 / ret
	jmp play_sfx
fl1_hide                        ; @reset_x_pos_and_be_invisible (02:9C58): mapa 0, Vx = 0 (kula niewidoczna, stoi)
	lda #$00
	ldy #OB_SPRITE            ; (ix+15) = (ix+16) = 0
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_VX                ; (ix+7) = (ix+8) = (ix+9) = 0
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
fl1_ret
	rts

; objfunc_15_SCR_flamer_firing_left (02:9C70): Vx = $FFFE80 (-1,5 px/tick), mapa SPRTAB_SCR_flame_left, jp @common_entry
objfunc_15_flamer_left
	ldy #OB_VX                ; 02:9C70: ld (ix+7),$80 / ld (ix+8),$FE / ld (ix+9),$FF
	lda #$80
	sta (zg_obj),y
	iny
	lda #$FE
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	ldy #OB_SPRITE            ; 02:9C7C: (ix+15/16) = SPRTAB_SCR_flame_left (adres SMS)
	lda #<SPR_FLM_L
	sta (zg_obj),y
	iny
	lda #>SPR_FLM_L
	sta (zg_obj),y
	jmp fl1_common            ; 02:9C84: jp objfunc_14_SCR_flamer_firing_right@common_entry

; ---------------------------------------------------------------------
; objfunc_16_SCR_ceiling_flamer (02:9C8E): plomien bijacy z sufitu. Set 5 (bez kolizji z mapa). Pierwszy tick (b0 = 0):
; x += $000C, y += $0012 (16 bit, bajty pikseli), faza (ix+17) = random_A (jedno wywolanie - stan ziarna jak oryginal), set 0.
; Co tick: tmp_00 = x, tmp_02 = y, tmp_04 = 0; indeks = faza >> 4 (0..15): (ix+14) = LUT_ceiling_flame_collision_heights[indeks],
; (ix+13) = 6; wskaznik = PTRLUT[indeks] (adres SMS; ENTRY_RESET = $0000 dla indeksow 0..6 - bez plomienia, bez kolizji).
; Z plomieniem: wpis 8 B = tablica + (faza & 3) * 8 ((faza * 8) & $1F), 4 pary (kafel, dy) -> draw_sprite w (x, y + dy)
; (tmp_06 = dy, tmp_07 = 0); wysokosc <> 0 -> trafienie Sonica (przesuniecie (2, 2)) -> damage_sonic. Na koniec faza + 1
; (8 bit), mapa (ix+15/16) = 0 (obiekt rysuje sam), faza = $70 (poczatek plomienia) -> efekt $17.
; ---------------------------------------------------------------------
objfunc_16_ceiling_flamer
	ldy #OB_FLAGS             ; 02:9C8E: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01                  ; 02:9C92: bit 0,(ix+24) / jr nz @already_initialised
	bne fl6_inited
	ldy #OB_X+1               ; 02:9C98: hl = (ix+2/3) + $000C -> (ix+2/3)
	clc
	lda (zg_obj),y
	adc #$0C
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y
	ldy #OB_Y+1               ; 02:9CA8: hl = (ix+5/6) + $0012 -> (ix+5/6)
	clc
	lda (zg_obj),y
	adc #$12
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y
	jsr random_A              ; 02:9CB8: call random_A / ld (ix+17),a - losowa faza startowa
	ldy #17
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:9CBE: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
fl6_inited                      ; @already_initialised (02:9CC2): tmp_00 = x, tmp_02 = y, tmp_04 = $0000 (pozycja dla draw_sprite)
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
	lda #$00
	sta tmp_04
	sta tmp_04+1
	ldy #17                   ; 02:9CDA: a = (ix+17) >> 4 (srl x 4) -> c (bc = indeks 0..15)
	lda (zg_obj),y
	lsr
	lsr
	lsr
	lsr
	tax                       ; X = indeks (c); e = 2 * indeks liczone nizej
	lda LUT_CFL_H-OZ_OFF,x    ; 02:9CEC: ld a,(LUT_ceiling_flame_collision_heights + bc) / ld (ix+14),a
	ldy #OB_H
	sta (zg_obj),y
	ldy #OB_W                 ; 02:9CF4: ld (ix+13),$06
	lda #$06
	sta (zg_obj),y
	txa                       ; 02:9CE8: add a,a / ld e,a - przesuniecie slowa w PTRLUT (0..30)
	asl
	tax
	lda PTR_CFL-OZ_OFF,x      ; 02:9CF8: hl = (PTRLUT + de) - adres SMS tablicy par (albo $0000)
	sta zg_hl
	lda PTR_CFL+1-OZ_OFF,x
	sta zg_hl+1
	ora zg_hl                 ; 02:9D00: ld a,l / or h / jr z @skip_sonic_collision_check - ENTRY_RESET: bez plomienia
	beq fl6_skip
	lda zg_hl+1               ; adres SMS -> adres okna tego banku (dane pod SMS - OZ_OFF; mlodszy bajt bez zmian)
	sec
	sbc #>OZ_OFF
	sta zg_hl+1
	ldy #17                   ; 02:9D03: a = ((ix+17) * 8) & $1F (add a,a x 3 - 8 bit) = (faza & 3) * 8 -> e; hl += de
	lda (zg_obj),y            ; (6502: e jako indeks Y w (zg_hl),y; e + 8 <= 32, tablice nie przekraczaja strony - wynik
	asl                       ; ten sam co 16-bitowe add hl,de)
	asl
	asl
	and #$1F
	sta zg_a                  ; zg_a = indeks biezacego bajtu (hl)
	lda #$04                  ; 02:9D0F: ld b,$04 - 4 sprite'y (licznik B w zg_bc+1; draw_sprite niszczy tylko zs_*, X, A)
	sta zg_bc+1
fl6_each                        ; @each_flame_sprite (02:9D11)
	ldy zg_a
	lda (zg_hl),y             ; ld a,(hl) / inc hl - kafel
	tax
	iny
	lda (zg_hl),y             ; ld e,(hl) / inc hl - przesuniecie y
	iny
	sty zg_a
	sta tmp_06                ; 02:9D16: ld d,$00 / ld (tmp_06),de - tmp_06 = dy, tmp_07 = 0
	lda #$00
	sta tmp_07
	txa                       ; 02:9D1D: call draw_sprite (A = kafel) w (tmp_00 + tmp_04, tmp_02 + tmp_06); push/pop hl, bc -
	jsr zc_dspr               ; wskaznik w zg_hl / zg_a, licznik w zg_bc+1 zostaja
	dec zg_bc+1               ; 02:9D22: djnz @each_flame_sprite
	bne fl6_each
	ldy #OB_H                 ; 02:9D24: ld a,(ix+14) / and a / jr z @skip_sonic_collision_check
	lda (zg_obj),y
	beq fl6_skip
	lda #$02                  ; 02:9D2A: ld hl,$0202 / ld (tmp_06),hl - przesuniecie (2, 2)
	sta tmp_06
	sta tmp_07
	jsr zc_collide            ; 02:9D30: call check_collision_with_sonic
	bcs fl6_skip              ; 02:9D33: call nc,damage_sonic
	jsr damage_sonic
fl6_skip                        ; @skip_sonic_collision_check (02:9D36): inc (ix+17) (8 bit z zawinieciem)
	ldy #17
	lda (zg_obj),y
	clc
	adc #$01
	sta (zg_obj),y
	tax                       ; X = nowa faza (ld a,(ix+17) ponizej)
	lda #$00                  ; 02:9D39: xor a / ld (ix+15),a / ld (ix+16),a - mapa 0 (sprite'y rysowane wyzej)
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	cpx #$70                  ; 02:9D40: ld a,(ix+17) / cp $70 / ret nz
	bne fl6_ret
	lda #$17                  ; 02:9D46: ld a,$17 / rst $28 / ret - efekt plomienia
	jmp play_sfx
fl6_ret
	rts

; ---------------------------------------------------------------------
; objfunc_1A_SCR_zapper (02:A0E8): luk elektryczny. Set 5 (bez kolizji z mapa), pole $30 x $10. Pierwszy tick (b0 = 0):
; x += $0018, y += $0010 (16 bit, bajty pikseli), set 0. Licznik cyklu (ix+17): < $46 - nic (mapa 0); $46..$63 - ostrzezenie
; (animacja LUT_zapper_anim_warning); $64..$9F - wyladowanie: przy $64 efekt $13, trafienie Sonica (przesuniecie (0, 0)) ->
; damage_sonic, animacja LUT_zapper_anim_zapping. Na koniec licznik + 1 (8 bit), od $A0 znowu 0.
; ---------------------------------------------------------------------
objfunc_1A_zapper
	ldy #OB_FLAGS             ; 02:A0E8: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W                 ; 02:A0EC: ld (ix+13),$30 / ld (ix+14),$10
	lda #$30
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:A0F4: bit 0,(ix+24) / jr nz @already_initialised
	lda (zg_obj),y
	and #$01
	bne zap_inited
	ldy #OB_X+1               ; 02:A0FA: hl = (ix+2/3) + $0018 -> (ix+2/3)
	clc
	lda (zg_obj),y
	adc #$18
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y
	ldy #OB_Y+1               ; 02:A10A: hl = (ix+5/6) + $0010 -> (ix+5/6)
	clc
	lda (zg_obj),y
	adc #$10
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:A11A: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
zap_inited                      ; @already_initialised (02:A11E): ld a,(ix+17) / cp $64 / jr c @dont_damage_sonic
	ldy #17
	lda (zg_obj),y
	cmp #$64
	bcc zap_safe
	bne zap_nosfx             ; 02:A125: jr nz @skip_sound_effect - efekt tylko przy liczniku = $64
	lda #$13                  ; 02:A127: ld a,$13 / rst $28 - wyladowanie
	jsr play_sfx
zap_nosfx                       ; @skip_sound_effect (02:A12A): ld hl,$0000 / ld (tmp_06),hl - przesuniecie (0, 0)
	lda #$00
	sta tmp_06
	sta tmp_07
	jsr zc_collide            ; 02:A130: call check_collision_with_sonic
	bcs zap_nohit             ; 02:A133: call nc,damage_sonic
	jsr damage_sonic
zap_nohit                       ; 02:A136: de = SPRTAB_SCR_zapper, bc = LUT_zapper_anim_zapping / call do_framed_animation
	lda #<[LUT_ZAP_Z-OZ_OFF]
	sta zg_bc
	lda #>[LUT_ZAP_Z-OZ_OFF]
	sta zg_bc+1
	jsr zap_anim
	jmp zap_timer             ; 02:A13F: jp @update_timer_and_return
zap_safe                        ; @dont_damage_sonic (02:A142): A = (ix+17) < $64; cp $46 / jr nc @show_warning_flash
	cmp #$46
	bcs zap_warn
	lda #$00                  ; 02:A146: xor a / ld (ix+15),a / ld (ix+16),a - mapa 0 (luk wylaczony)
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	jmp zap_timer             ; 02:A14D: jp @update_timer_and_return
zap_warn                        ; @show_warning_flash (02:A150): de = SPRTAB_SCR_zapper, bc = LUT_zapper_anim_warning
	lda #<[LUT_ZAP_W-OZ_OFF]
	sta zg_bc
	lda #>[LUT_ZAP_W-OZ_OFF]
	sta zg_bc+1
	jsr zap_anim              ; 02:A156: call do_framed_animation
zap_timer                       ; @update_timer_and_return (02:A159): inc (ix+17) / ld a,(ix+17) / cp $A0 / ret c
	ldy #17
	lda (zg_obj),y
	clc
	adc #$01                  ; 8 bit z zawinieciem jak inc (ix+17)
	sta (zg_obj),y
	cmp #$A0
	bcc zap_ret
	lda #$00                  ; 02:A162: ld (ix+17),$00 / ret
	sta (zg_obj),y
zap_ret
	rts

; zap_anim: de = SPRTAB_SCR_zapper (adres SMS), call do_framed_animation (oz2_dfa) z sekwencja zg_bc (adres okna)
zap_anim
	lda #<SPR_ZAP
	sta zg_de
	lda #>SPR_ZAP
	sta zg_de+1
	jmp oz2_dfa
