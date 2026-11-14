; =====================================================================
;  obj/objz_lab_orbinaut.asm - M6.8 Labyrinth: $35 Orbinaut i $36 wyrzucona kula (bank obiektow strefy PB_OBJZ, bank 11).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_35_badnik_orbinaut 02:AE88-02:B030 (z lokalnymi
;  @fn_maybe_jettison_balls 02:AF98 i @fn_jettison_ball 02:AFDB), objfunc_36_badnik_orbinaut_ejected_ball 02:B0F4-02:B16B;
;  dane LUT_orbinaut_ball_xy_positions 02:B031 (82 pary (dx, dy) = 164 B), SPRTAB_orbinaut_base_left 02:B0D5,
;  SPRTAB_orbinaut_base_right 02:B0E7 (zakres OBJZ_SPANS 02:B031-02:B0F3). Dalej (02:B16C) jest objfunc_37 ze Sky Base - nie tu.
;  Procedury:
;   objfunc_35_orbinaut       (02:AE88) - funkcja obiektu $35
;   orn_jettison              (02:AF98, @fn_maybe_jettison_balls) - wyrzut kul przy Sonicu
;   orn_eject                 (02:AFDB, @fn_jettison_ball) - jedna kula -> nowy obiekt $36
;   objfunc_36_orbinaut_ball  (02:B0F4) - funkcja obiektu $36 (wyrzucona kula)
;  Obiekty tworzone w locie: $36 (wyrzucona kula; spawn_object w orn_eject).
;  Pola rekordu $35: (ix+17..20) kat czterech kul (0..$A3, przesuniecie bajtowe pary w LUT = kat & $FE; $FE = kula wyrzucona),
;  (ix+21) licznik do wyrzutu (co tick z tick & 7 <> 0 + 1, do $C8), (ix+22) kierunek obrotu (+1 / $FF),
;  (ix+24) b0 = zainicjowany. Bez kolizji z mapa (set 5).
;  Wola: zc_collide, zc_enemy, zc_dspr (stuby do banku 45), damage_sonic, spawn_object (rezydentne).
;  Rejestry Z80: IX = zg_obj, HL nowego obiektu = zg_ptr; licznik petli kul (B / HL = ix+17+i) - zg_bc (przesuniecie pola
;  kuli 17..20 w rekordzie), zg_bc+1 = przesuniecie bajtowe pary w LUT (nie niszcza go zc_dspr, zc_collide, damage_sonic, spawn_object).
; =====================================================================
LUT_ORBXY       = $B031   ; LUT_orbinaut_ball_xy_positions: (dx, dy) kuli wg kata (164 B)
SPR_ORB_L       = $B0D5   ; SPRTAB_orbinaut_base_left
SPR_ORB_R       = $B0E7   ; SPRTAB_orbinaut_base_right

; ---------------------------------------------------------------------
; objfunc_35_badnik_orbinaut (02:AE88): korpus z czterema kulami krazacymi wokol (kafel $24, rysowane draw_sprite).
; Pierwszy tick (b0 = 0): katy kul 0, $2A, $52, $7C, set 0. Strona Sonica (x - sonic_x, 16 bit; pozyczka - Sonic na
; prawo): na lewo -> Vx = $FFFFF8, mapa _left, tmp_08 = $FF80 (Vx wyrzuconej kuli), wyrzut kul, (ix+22) = 1;
; na prawo -> Vx = $000008, mapa _right, tmp_08 = $0080, wyrzut kul, (ix+22) = $FF. Korpus 28 x 28, trafienie
; (przesuniecie ($12, $12)) -> enemy_touched_sonic (tmp_00 = $1010). Dla kazdej kuli (kat <> $FE): sprite $24 w
; (x + dx, y + dy) (tmp_00/02 = x, y obiektu, tmp_04 = dx, tmp_06 = dy), kolizja: tmp_06 = dx + 2, (ix+13) = dx + 6,
; tmp_07 = dy + 2, (ix+14) = dy + 6 -> damage_sonic; kat + (ix+22) z zawinieciem ($FF -> $A3, $A4 -> 0).
; Na koniec: tick & 7 <> 0 i (ix+21) < $C8 -> (ix+21) + 1.
; ---------------------------------------------------------------------
objfunc_35_orbinaut
	ldy #OB_FLAGS             ; set 5,(ix+24); bit 0,(ix+24) / jr nz @already_initialised
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01
	bne orn_inited
	ldy #17                   ; (ix+17) = 0, (ix+18) = $2A, (ix+19) = $52, (ix+20) = $7C
	lda #$00
	sta (zg_obj),y
	iny
	lda #$2A
	sta (zg_obj),y
	iny
	lda #$52
	sta (zg_obj),y
	iny
	lda #$7C
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
orn_inited                      ; @already_initialised: hl = x - sonic_x (and a / sbc hl,de)
	ldy #OB_X+1
	sec
	lda (zg_obj),y
	sbc sonic_x
	iny
	lda (zg_obj),y
	sbc sonic_x+1
	bcc orn_right             ; jr c @sonic_is_on_right (6502: C = 0 = pozyczka)
	ldy #OB_VX                ; Sonic na lewo: Vx = $FFFFF8, mapa _left
	lda #$F8
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_SPRITE
	lda #<SPR_ORB_L
	sta (zg_obj),y
	iny
	lda #>SPR_ORB_L
	sta (zg_obj),y
	lda #$80                  ; ld hl,$FF80 / ld (tmp_08),hl
	sta tmp_08
	lda #$FF
	sta tmp_08+1
	jsr orn_jettison          ; call @fn_maybe_jettison_balls
	ldy #22                   ; (ix+22) = 1
	lda #$01
	sta (zg_obj),y
	jmp orn_cont              ; jr @sonic_was_on_the_left
orn_right                       ; @sonic_is_on_right: Vx = $000008, mapa _right
	ldy #OB_VX
	lda #$08
	sta (zg_obj),y
	lda #$00
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_SPRITE
	lda #<SPR_ORB_R
	sta (zg_obj),y
	iny
	lda #>SPR_ORB_R
	sta (zg_obj),y
	lda #$80                  ; ld hl,$0080 / ld (tmp_08),hl
	sta tmp_08
	lda #$00
	sta tmp_08+1
	jsr orn_jettison          ; call @fn_maybe_jettison_balls
	ldy #22                   ; (ix+22) = $FF
	lda #$FF
	sta (zg_obj),y
orn_cont                        ; @sonic_was_on_the_left: korpus (ix+13) = (ix+14) = $1C
	ldy #OB_W
	lda #$1C
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #$12                  ; ld hl,$1212 / ld (tmp_06),hl
	sta tmp_06
	sta tmp_07
	jsr zc_collide            ; check_collision_with_sonic
	lda #$10                  ; ld hl,$1010 / ld (tmp_00),hl (lda/sta nie zmieniaja C)
	sta tmp_00
	sta tmp_00+1
	bcs orn_nohit             ; call nc,enemy_touched_sonic
	jsr zc_enemy
orn_nohit
	ldy #OB_X+1               ; tmp_00 = x, tmp_02 = y (16 bit; po ewentualnym wybuchu - x, y przesuniete)
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
	lda #17                   ; push ix / pop hl / hl += $11, b = 4: pola kul (ix+17)..(ix+20)
	sta zg_bc
orn_ball                        ; @each_ball_to_spin
	ldy zg_bc                 ; ld a,(hl) / cp $FE / jr z: kula wyrzucona - bez rysowania i kolizji
	lda (zg_obj),y
	cmp #$FE
	beq orn_skip
	and #$FE                  ; e = kat & $FE, hl = LUT + de
	sta zg_bc+1
	tax
	lda LUT_ORBXY-OZ_OFF,x    ; ld (tmp_04),de z d = 0: tmp_04 = dx, tmp_05 = 0
	sta tmp_04
	lda LUT_ORBXY+1-OZ_OFF,x  ; ld (tmp_06),de z d = 0: tmp_06 = dy, tmp_07 = 0
	sta tmp_06
	lda #0
	sta tmp_04+1
	sta tmp_07
	lda #$24                  ; draw_sprite kafla $24 w (tmp_00 + tmp_04, tmp_02 + tmp_06)
	jsr zc_dspr
	ldx zg_bc+1               ; pop hl: a = dx + 2 -> tmp_06 (sam bajt), (ix+13) = a + 4
	lda LUT_ORBXY-OZ_OFF,x
	clc
	adc #2
	sta tmp_06
	clc
	adc #4
	ldy #OB_W
	sta (zg_obj),y
	lda LUT_ORBXY+1-OZ_OFF,x  ; a = dy + 2 -> tmp_07, (ix+14) = a + 4
	clc
	adc #2
	sta tmp_07
	clc
	adc #4
	ldy #OB_H
	sta (zg_obj),y
	jsr zc_collide            ; check_collision_with_sonic / call nc,damage_sonic
	bcs orn_skip
	jsr damage_sonic
orn_skip                        ; @skip_collision_with_missing_ball: obrot kuli
	ldy zg_bc
	lda (zg_obj),y
	cmp #$FE
	beq orn_store             ; jr z @update_and_handle_next_ball ((hl) = $FE bez zmian)
	ldy #22                   ; add a,(ix+22) (8 bit)
	clc
	adc (zg_obj),y
	cmp #$FF                  ; cp $FF / jr nz: obrot w strone malejaca - zawiniecie $FF -> $A3
	bne orn_notff
	lda #$A3
	bne orn_store             ; zawsze
orn_notff                       ; @spin_direction_is_for_moving_left: cp $A4 / jr nz, xor a - zawiniecie $A4 -> 0
	cmp #$A4
	bne orn_store
	lda #$00
orn_store                       ; @update_and_handle_next_ball: ld (hl),a / inc hl / djnz
	ldy zg_bc
	sta (zg_obj),y
	inc zg_bc
	lda zg_bc
	cmp #21
	bne orn_ball
	lda g_global_tick_counter ; and $07 / ret z
	and #$07
	beq orn_ret
	ldy #21                   ; ld a,(ix+21) / cp $C8 / ret nc
	lda (zg_obj),y
	cmp #$C8
	bcs orn_ret
	adc #1                    ; inc (ix+21) (C = 0 po cmp z wynikiem "mniejsze")
	sta (zg_obj),y
orn_ret
	rts

; ---------------------------------------------------------------------
; orn_jettison (@fn_maybe_jettison_balls 02:AF98): tylko gdy (ix+21) = $C8, strefa Labyrinth (g_tile_flags_index = 3)
; i Sonic w pionie w (y - 48, y + $2C] (16 bit): kazda kula o kacie dokladnie $4A -> orn_eject. tmp_08 = Vx kuli.
; ---------------------------------------------------------------------
orn_jettison
	ldy #21                   ; ld a,(ix+21) / cp $C8 / ret nz
	lda (zg_obj),y
	cmp #$C8
	bne orj_ret
	lda g_tile_flags_index    ; cp $03 / ret nz
	cmp #$03
	bne orj_ret
	ldy #OB_Y+1               ; hl = y + $FFD0 (y - 48, 16 bit z zawinieciem), de = sonic_y
	clc
	lda (zg_obj),y
	adc #<$FFD0
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #>$FFD0
	sta zg_hl+1
	sec                       ; and a / sbc hl,de / ret nc: y - 48 >= sonic_y (6502 C = 1) -> koniec
	lda zg_hl
	sbc sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcs orj_ret
	ldy #OB_Y+1               ; hl = y + $002C
	clc
	lda (zg_obj),y
	adc #$2C
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	sec                       ; sbc hl,de / ret c: y + $2C < sonic_y (6502 C = 0) -> koniec
	lda zg_hl
	sbc sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcc orj_ret
	lda #17                   ; hl = ix + $11, b = 4
	sta zg_bc
orj_each                        ; @each_ball_to_jettison: ld a,(hl) / cp $4A / call z,@fn_jettison_ball
	ldy zg_bc
	lda (zg_obj),y
	cmp #$4A
	bne orj_next
	jsr orn_eject
orj_next
	inc zg_bc
	lda zg_bc
	cmp #21
	bne orj_each
orj_ret
	rts

; ---------------------------------------------------------------------
; orn_eject (@fn_jettison_ball 02:AFDB): kula zg_bc (przesuniecie pola 17..20) := $FE (takze gdy brak wolnego slotu),
; spawn_object; nowy obiekt $36: (ix+1) = 0, x = x + $12, (ix+4) = 0, y = y + $1E, Vx = tmp_08 (16 bit, bajt najwyzszy
; z bitu 7 tmp_09), Vy = 0. Pozostale pola slotu bez zmian (oryginal ich nie czysci).
; ---------------------------------------------------------------------
orn_eject
	ldy zg_bc                 ; ld (hl),$FE
	lda #$FE
	sta (zg_obj),y
	jsr spawn_object          ; ret c: brak wolnego slotu
	bcs ore_ret
	ldy #OB_TYPE              ; (ix+0) = $36, (ix+1) = 0 (a = 0 z xor a)
	lda #$36
	sta (zg_ptr),y
	lda #$00
	iny
	sta (zg_ptr),y
	ldy #OB_X+1               ; x = de + $0012 (de = x Orbinauta)
	clc
	lda (zg_obj),y
	adc #$12
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_ptr),y
	lda #$00                  ; (ix+4) = 0
	iny
	sta (zg_ptr),y
	ldy #OB_Y+1               ; y = bc + $001E (bc = y Orbinauta)
	clc
	lda (zg_obj),y
	adc #$1E
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_ptr),y
	ldy #OB_VX                ; Vx = tmp_08 (l, h), (ix+9) = $FF gdy bit 7,h, inaczej 0
	lda tmp_08
	sta (zg_ptr),y
	iny
	lda tmp_08+1
	sta (zg_ptr),y
	ldx #$00
	and #$80
	beq ore_vxpos             ; @ball_is_to_move_right
	ldx #$FF
ore_vxpos
	txa
	iny
	sta (zg_ptr),y
	lda #$00                  ; Vy = 0
	iny
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
ore_ret
	rts

; ---------------------------------------------------------------------
; objfunc_36_badnik_orbinaut_ejected_ball (02:B0F4): wyrzucona kula (bez kolizji z mapa, set 5), ruch tylko z Vx
; nadanej przy wyrzucie (obj_motion). Mapa 0, 4 x 10, trafienie (przesuniecie (2, 6)) -> damage_sonic. tmp_00 = x,
; tmp_02 = y; x poza (kamera X - 16, kamera X + $110] albo y poza (kamera Y - 16, kamera Y + $D0] -> usuniecie
; (typ $FF; tmp_02 nie ustawiane, gdy odpada juz po x); inaczej sprite $24 w (x, y) (tmp_04 = tmp_06 = 0).
; ---------------------------------------------------------------------
objfunc_36_orbinaut_ball
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #$00                  ; (ix+15/16) = 0: obiekt bez mapy (kula rysowana draw_sprite)
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_W                 ; (ix+13) = 4, (ix+14) = $0A
	lda #$04
	sta (zg_obj),y
	iny
	lda #$0A
	sta (zg_obj),y
	lda #$02                  ; ld hl,$0602 / ld (tmp_06),hl: tmp_06 = 2, tmp_07 = 6
	sta tmp_06
	lda #$06
	sta tmp_07
	jsr zc_collide            ; check_collision_with_sonic / call nc,damage_sonic
	bcs onb_nohit
	jsr damage_sonic
onb_nohit
	ldy #OB_X+1               ; tmp_00 = x, de = x (ex de,hl)
	lda (zg_obj),y
	sta tmp_00
	sta zg_de
	iny
	lda (zg_obj),y
	sta tmp_00+1
	sta zg_de+1
	clc                       ; hl = kamera X + $FFF0 (16 bit z zawinieciem)
	lda g_level_scroll_x_pix_lo
	adc #<$FFF0
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #>$FFF0
	sta zg_hl+1
	sec                       ; and a / sbc hl,de / jr nc: hl >= x (6502 C = 1) -> @destroy_this_object
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs onb_destroy
	clc                       ; hl = kamera X + $0110
	lda g_level_scroll_x_pix_lo
	adc #<$0110
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #>$0110
	sta zg_hl+1
	sec                       ; jr c: hl < x (6502 C = 0) -> @destroy_this_object
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcc onb_destroy
	ldy #OB_Y+1               ; tmp_02 = y, de = y
	lda (zg_obj),y
	sta tmp_02
	sta zg_de
	iny
	lda (zg_obj),y
	sta tmp_02+1
	sta zg_de+1
	clc                       ; hl = kamera Y + $FFF0
	lda g_level_scroll_y_pix_lo
	adc #<$FFF0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #>$FFF0
	sta zg_hl+1
	sec                       ; jr nc -> @destroy_this_object
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs onb_destroy
	clc                       ; hl = kamera Y + $00D0
	lda g_level_scroll_y_pix_lo
	adc #<$00D0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #>$00D0
	sta zg_hl+1
	sec                       ; jr c -> @destroy_this_object
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcc onb_destroy
	lda #$00                  ; tmp_04 = tmp_06 = $0000 (po 16 bit)
	sta tmp_04
	sta tmp_04+1
	sta tmp_06
	sta tmp_07
	lda #$24                  ; draw_sprite kafla $24 w (x, y)
	jmp zc_dspr
onb_destroy                     ; @destroy_this_object: (ix+0) = $FF
	lda #$FF
	ldy #OB_TYPE
	sta (zg_obj),y
	rts
