; =====================================================================
;  obj/objz_seesaw.asm - M6.6 Bridge: $4E huśtawka (bank obiektow strefy PB_OBJZ, dolaczany z objz.asm). Oryginal (s1smsdisasm-gm,
;  tylko material referencyjny): objfunc_4E_seesaw 02:866C.
; ---------------------------------------------------------------------
; Dwa pomosty (kazdy 3 kafle) i ciezarek (2 kafle) rysowane jako pojedyncze sprite'y (draw_sprite, kafle z LUT_sprite_platform /
; LUT_sprite_weight), Sonic stoi na jednym z pomostow. (ix+17) = wysokosc lewego pomostu (0..$1C; prawy = $1C - (ix+17)),
; (ix+18/19) = predkosc ciezarka (16 bit ze znakiem), (ix+20/21/22) = pozycja ciezarka (24 bit; (ix+21/22) - y wzgledem pomostu).
; Pierwszy tick: (ix+17) = $1C, x -= 16, set 0. Co tick: pozycja += predkosc, predkosc += $38; dopoki predkosc >= 0 i pozycja >= 0:
; wysokosc pomostu 0 -> stan poczatkowy (reset_seesaw_state); gdy Sonic stal na lewym pomoscie (b1 flag): Vy Sonica = odbicie albo
; odbicie - predkosc; wysokosc = $1C - bajt posredni pozycji (przy 0 efekt $04 i reset). Kolizje: lewy pomost 20 x ((ix+17) + 8)
; z przesunieciem (2, (ix+17) + 4), prawy 60 x (($1C - (ix+17)) + 8) z przesunieciem ($2A, ($1C - (ix+17)) + 4); Sonic spadajacy
; na pomost (Vy >= 0) jest na nim ustawiany i odbijany (wejscie na lewy: predkosc ciezarka = -Vy Sonica, wysokosc += Vy pikselowe).
; ---------------------------------------------------------------------
objfunc_4E_seesaw
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01                  ; bit 0,(ix+24)
	bne ss_init
	ldy #17                   ; (ix+17) = $1C, x -= 16, set 0
	lda #$1C
	sta (zg_obj),y
	ldy #OB_X+1
	sec
	lda (zg_obj),y
	sbc #$10
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	sbc #0
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
ss_init                         ; @already_initialised: pozycja (24 bit) += predkosc (16 bit ze znakiem)
	ldy #18
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	ldx #0                    ; c = rozszerzenie znaku
	lda zg_de+1
	bpl ss_pos
	dex
ss_pos
	ldy #20
	clc
	lda (zg_obj),y
	adc zg_de
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta (zg_obj),y
	sta zg_bc                 ; c = bajt posredni pozycji
	iny
	txa
	adc (zg_obj),y
	sta (zg_obj),y
	sta zg_bc+1               ; b = bajt najwyzszy pozycji
	clc                       ; predkosc += $38
	lda zg_de
	adc #$38
	sta zg_hl
	ldy #18
	sta (zg_obj),y
	lda zg_de+1
	adc #0
	sta zg_hl+1
	iny
	sta (zg_obj),y
	lda zg_hl+1
	bmi ss_draw               ; bit 7,h / jr nz: predkosc ujemna
	lda zg_bc+1
	bmi ss_draw               ; rlca / jr c: pozycja ujemna
	ldy #17
	lda (zg_obj),y
	beq ss_reset              ; wysokosc pomostu 0 -> stan poczatkowy
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02                  ; bit 1,(ix+24): Sonic na lewym pomoscie w poprzednim ticku
	beq ss_cont
	lda zg_hl
	ora zg_hl+1
	bne ss_vnz
	jsr ss_bounce             ; predkosc = 0: Vy Sonica = odbicie
	jmp ss_cont
ss_vnz                          ; predkosc <> 0: Vy Sonica = odbicie - predkosc (16 bit), bajt najwyzszy $FF
	sec
	lda g_sonic_bounce_vel_y_sub
	sbc zg_hl
	sta sonic_vel_y_sub
	lda g_sonic_bounce_vel_y_sub+1
	sbc zg_hl+1
	sta sonic_vel_y
	lda #$FF
	sta sonic_vel_y_hi
ss_cont                         ; @continue_after_weight_applied: (ix+17) = $1C - c
	ldy #17
	sec
	lda #$1C
	sbc zg_bc
	sta (zg_obj),y
	beq ss_maybe              ; jr z
	bcs ss_draw               ; jr nc (bez pozyczki)
ss_maybe
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02
	beq ss_reset
	lda #$04                  ; rst $28
	jsr play_sfx
ss_reset                        ; @reset_seesaw_state
	lda #0
	ldy #17
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	lda #$1C
	sta (zg_obj),y
	iny
	lda #0
	sta (zg_obj),y
ss_draw                         ; @do_sprite_drawing: tmp_00/02 = pozycja obiektu, tmp_04 = przesuniecie x, tmp_06 = przesuniecie y
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
	lda #0
	sta tmp_04
	sta tmp_04+1
	ldy #17
	lda (zg_obj),y
	clc
	adc #$10
	sta tmp_06
	lda #0
	sta tmp_06+1
	lda #<[LUT_SPR_PLAT-OZ_OFF]
	ldx #>[LUT_SPR_PLAT-OZ_OFF]
	jsr ss_row
	lda #$28                  ; prawy pomost: x + $28, y + ($1C - (ix+17)) + $10
	sta tmp_04
	ldy #17
	sec
	lda #$1C
	sbc (zg_obj),y
	clc
	adc #$10
	sta tmp_06
	lda #0
	sta tmp_06+1
	lda #<[LUT_SPR_PLAT-OZ_OFF]
	ldx #>[LUT_SPR_PLAT-OZ_OFF]
	jsr ss_row
	lda #$2C                  ; ciezarek: x + $2C, y + (ix+21/22)
	sta tmp_04
	ldy #21
	lda (zg_obj),y
	sta tmp_06
	iny
	lda (zg_obj),y
	sta tmp_06+1
	lda #<[LUT_SPR_WEIGHT-OZ_OFF]
	ldx #>[LUT_SPR_WEIGHT-OZ_OFF]
	jsr ss_row
	ldy #OB_FLAGS             ; res 1,(ix+24)
	lda (zg_obj),y
	and #$FD
	sta (zg_obj),y
	ldy #OB_W                 ; lewy pomost: 20 x ((ix+17) + 8), przesuniecie (2, (ix+17) + 4)
	lda #$14
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	clc
	adc #$08
	ldy #OB_H
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	clc
	adc #$04
	sta tmp_07
	lda #$02
	sta tmp_06
	jsr zc_collide
	bcc ss_left               ; jr nc: kolizja z lewym pomostem
	lda sonic_vel_y_hi
	bmi ss_ret                ; ret m
	ldy #OB_W                 ; prawy pomost: 60 x (($1C - (ix+17)) + 8), przesuniecie ($2A, ($1C - (ix+17)) + 4)
	lda #$3C
	sta (zg_obj),y
	lda #$2A
	sta tmp_06
	ldy #17
	sec
	lda #$1C
	sbc (zg_obj),y
	sta zg_a
	clc
	adc #$08
	ldy #OB_H
	sta (zg_obj),y
	lda zg_a
	clc
	adc #$04
	sta tmp_07
	jsr zc_collide
	bcc ss_right              ; jr nc
ss_ret
	rts
ss_left                         ; @handle_left_platform_sonic_collision
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
	lda sonic_vel_y_hi
	bmi ss_ret
	ldy #17
	lda (zg_obj),y
	cmp #$1C
	beq ss_right
	sec                       ; predkosc ciezarka = -(Vy Sonica: sub, piksele) (16 bit)
	lda #0
	sbc sonic_vel_y_sub
	ldy #18
	sta (zg_obj),y
	lda #0
	sbc sonic_vel_y
	iny
	sta (zg_obj),y
	ldy #17                   ; wysokosc += Vy pikselowe Sonica, najwyzej $1C
	lda sonic_vel_y
	clc
	adc (zg_obj),y
	sta (zg_obj),y
	cmp #$1C
	bcc ss_pos_sonic
	lda #$1C
	sta (zg_obj),y
ss_right                        ; @handle_right_platform_sonic_collision: Vy Sonica = odbicie
	jsr ss_bounce
ss_pos_sonic                    ; @skip_bounce_off_platform: sonic_y = y + $10 + (tmp_07 - 4) - sonic_size_y, na ziemi
	ldy #OB_Y+1
	clc
	lda (zg_obj),y
	adc #$10
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	lda tmp_07
	sec
	sbc #$04
	clc
	adc zg_hl
	sta zg_hl
	bcc ss_nc
	inc zg_hl+1
ss_nc
	sec
	lda zg_hl
	sbc sonic_height_ix_14
	sta sonic_y
	lda zg_hl+1
	sbc #0
	sta sonic_y+1
	lda sonic_flags_ix_24
	ora #$80
	sta sonic_flags_ix_24
	rts
; ss_bounce: Vy Sonica (24 bit) = g_sonic_bounce_vel_y
ss_bounce
	lda g_sonic_bounce_vel_y_sub
	sta sonic_vel_y_sub
	lda g_sonic_bounce_vel_y_sub+1
	sta sonic_vel_y
	lda g_sonic_bounce_vel_y_sub+2
	sta sonic_vel_y_hi
	rts
; ss_row: @fn_draw_sprite_string: lista kafli pod adresem okna A (lo), X (hi), bajt $80+ konczy; kazdy kafel to draw_sprite
; (x = tmp_00 + tmp_04, y = tmp_02 + tmp_06), potem tmp_04 + 8
ss_row
	sta zg_prof
	stx zg_prof+1
	ldy #0
ssr_l
	sty zg_a
	lda (zg_prof),y
	bmi ssr_ret               ; and a / ret m
	jsr zc_dspr
	clc
	lda tmp_04
	adc #8
	sta tmp_04
	bcc ssr_c
	inc tmp_04+1
ssr_c
	ldy zg_a
	iny
	bne ssr_l                 ; zawsze
ssr_ret
	rts
