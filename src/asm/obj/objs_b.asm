; =====================================================================
;  obj/objs_b.asm - M4.4: platformy $09 wahadlo, $0B opadajaca, $0F pozioma (bank 45).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_09_platform_swing 01:673C,
;  objfunc_0B_platform_semilowering 01:69E9, objfunc_0F_platform_horizontal 01:6D65. Dane (tablica wahadla,
;  mapy platform) leza w banku 45 pod adresami SMS (objdata.inc). IX = zg_obj; tmp_* w lustrze RAM SMS.
;  Wspolne: bez kolizji z mapa (b5), rozmiar 26 x 16, kolizja z Soniciem tylko przy jego Vy >= 0 (od dolu
;  platforma jest przenikalna), przesuniecie testu tmp_06 = $0806, Sonic stawiany przez
;  put_sonic_y_pos_on_platform (common.asm) - w tym samym ticku, bo Sonic dziala po obiektach.
; =====================================================================
LUT_SWING_XY     = $682F   ; LUT_swing_xy_table: 113 par (dx, dy) bajtow ze znakiem, indeks (ix+17) = 0..$E0 co 2
SPR_PLAT_GHZ     = $6911   ; SPRITEMAP_platform_GHZ (wiersz 0 pusty: FE FF - 16 px odstepu, wiersz 1: 18 1A 18 1A)
SPR_PLAT_JUN     = $6923   ; SPRITEMAP_platform_JUN
SPR_PLAT_BRI     = $6931   ; SPRITEMAP_platform_BRI

; plat_cam_targets: cele granic okna Sonica (x0 $20, x1 $48, y0 $30, y1 $30) - platformy $09 i $0F co tick,
; gdy sa aktywne (kamera uzyje ich w nastepnym ticku; draw_HUD_sprites zeruje cele po kamerze)
plat_cam_targets
	lda #$20
	sta g_camera_sonic_bounds_x0_target
	lda #$48
	sta g_camera_sonic_bounds_x1_target
	lda #$30
	sta g_camera_sonic_bounds_y0_target
	sta g_camera_sonic_bounds_y1_target
	lda #0
	sta g_camera_sonic_bounds_x0_target+1
	sta g_camera_sonic_bounds_x1_target+1
	sta g_camera_sonic_bounds_y0_target+1
	sta g_camera_sonic_bounds_y1_target+1
	rts

; plat_hit: kolizja platformy z Soniciem (wspolny wstep $09/$0B/$0F): Vy Sonica < 0 -> C = 1 (brak); inaczej
; tmp_06 = $06, tmp_07 = $08 i check_collision_with_sonic (C = 1 brak trafienia)
plat_hit
	lda sonic_vel_y_hi
	bmi phit_no               ; and a / jp m
	lda #$06                  ; ld hl,$0806 / ld (tmp_06),hl
	sta tmp_06
	lda #$08
	sta tmp_07
	jmp check_collision_with_sonic
phit_no
	sec
	rts

; plat_put: BC = $0010, DE = A (0 albo $80 - mlodszy bajt Vy platformy, D = 0), put_sonic_y_pos_on_platform
plat_put
	sta zg_de
	lda #$10
	sta zg_bc
	lda #0
	sta zg_bc+1
	sta zg_de+1
	jmp put_sonic_y_pos_on_platform

; ---------------------------------------------------------------------
; objfunc_09_platform_swing (01:673C): cele kamery; pierwszy tick (b0 flag = 0): srodek wahadla (ix+18/19) = X,
; (ix+20/21) = Y, indeks (ix+17) = $E0, b0 i b1 (indeks maleje). Co tick: X = srodek X + dx[indeks],
; Y = srodek Y + dy[indeks] (bajty ze znakiem), tmp_00 = nowe X - stare X; Sonic na platformie: sonic_x +=
; tmp_00 i put_sonic (BC $10, DE 0). Mapa GHZ (g_tile_flags_index = 0) albo JUN. Indeks + 2 do $E0 (wtedy b1)
; albo - 2 do 0 (wtedy b1 = 0).
; ---------------------------------------------------------------------
objfunc_09_platform_swing
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	jsr plat_cam_targets
	ldy #OB_FLAGS
	lda (zg_obj),y
	lsr                       ; bit 0,(ix+24)
	bcs psw_init
	ldy #OB_X+1               ; srodek = pozycja (piksele)
	lda (zg_obj),y
	ldy #18
	sta (zg_obj),y
	ldy #OB_X+2
	lda (zg_obj),y
	ldy #19
	sta (zg_obj),y
	ldy #OB_Y+1
	lda (zg_obj),y
	ldy #20
	sta (zg_obj),y
	ldy #OB_Y+2
	lda (zg_obj),y
	ldy #21
	sta (zg_obj),y
	ldy #17
	lda #$E0
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 0 / set 1
	lda (zg_obj),y
	ora #$03
	sta (zg_obj),y
psw_init                        ; @already_initialised
	ldy #OB_W
	lda #$1A
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	ldy #OB_X+1               ; tmp_00 = stare X
	lda (zg_obj),y
	sta tmp_00
	iny
	lda (zg_obj),y
	sta tmp_00+1
	ldy #17                   ; BC = LUT + (ix+17)
	lda (zg_obj),y
	tax
	lda LUT_SWING_XY,x        ; dx (jp p / dec d: rozszerzenie znaku)
	sta zg_de
	and #$80
	beq psw_dxp
	lda #$FF
psw_dxp
	sta zg_de+1
	ldy #18                   ; X = srodek X + dx
	clc
	lda (zg_obj),y
	adc zg_de
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_hl+1
	ldy #OB_X+1
	lda zg_hl
	sta (zg_obj),y
	iny
	lda zg_hl+1
	sta (zg_obj),y
	sec                       ; tmp_00 = X - stare X (and a / sbc hl,de)
	lda zg_hl
	sbc tmp_00
	sta tmp_00
	lda zg_hl+1
	sbc tmp_00+1
	sta tmp_00+1
	lda LUT_SWING_XY+1,x      ; dy (inc bc)
	sta zg_de
	and #$80
	beq psw_dyp
	lda #$FF
psw_dyp
	sta zg_de+1
	ldy #20                   ; Y = srodek Y + dy
	clc
	lda (zg_obj),y
	adc zg_de
	ldy #OB_Y+1
	sta (zg_obj),y
	ldy #21
	lda (zg_obj),y
	adc zg_de+1
	ldy #OB_Y+2
	sta (zg_obj),y
	jsr plat_hit
	bcs psw_map               ; @skip_sonic_collision
	clc                       ; sonic_x += tmp_00
	lda sonic_x
	adc tmp_00
	sta sonic_x
	lda sonic_x+1
	adc tmp_00+1
	sta sonic_x+1
	lda #0                    ; BC = $0010, DE = 0
	jsr plat_put
psw_map
	lda #<SPR_PLAT_GHZ
	ldx #>SPR_PLAT_GHZ
	ldy g_tile_flags_index
	beq psw_ghz
	lda #<SPR_PLAT_JUN
	ldx #>SPR_PLAT_JUN
psw_ghz
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	txa
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02
	bne psw_dec               ; bit 1: indeks maleje
	ldy #17                   ; indeks + 2; >= $E0 -> set 1
	lda (zg_obj),y
	clc
	adc #2
	sta (zg_obj),y
	cmp #$E0
	bcc psw_ret
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
	rts
psw_dec                         ; @is_decrementing_swing_index: indeks - 2; 0 -> res 1
	ldy #17
	lda (zg_obj),y
	sec
	sbc #2
	sta (zg_obj),y
	bne psw_ret
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$FD
	sta (zg_obj),y
psw_ret
	rts

; ---------------------------------------------------------------------
; objfunc_0B_platform_semilowering (01:69E9): mapa GHZ; Sonic na platformie: Vy = $000080 gdy (Y & 31) < 16
; (opada do polowy bloku), inaczej 0, i put_sonic (BC $10, DE = Vy); bez Sonica: Vy = $FFFFC0 gdy (Y & 31) != 0
; (wraca w gore do granicy bloku), inaczej 0. Ruch robi obj_motion (bez kolizji z mapa).
; ---------------------------------------------------------------------
objfunc_0B_platform_semilowering
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W
	lda #$1A
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	iny                       ; (ix+15/16) = SPRITEMAP_platform_GHZ
	lda #<SPR_PLAT_GHZ
	sta (zg_obj),y
	iny
	lda #>SPR_PLAT_GHZ
	sta (zg_obj),y
	jsr plat_hit
	bcs psl_off               ; @not_collided_with_sonic
	ldx #0                    ; DE = 0; (ix+5) & $1F < $10 -> E = $80
	ldy #OB_Y+1
	lda (zg_obj),y
	and #$1F
	cmp #$10
	bcs psl_bot               ; @platform_was_not_at_bottom
	ldx #$80
psl_bot
	txa                       ; Vy = (E, D = 0, 0)
	ldy #OB_VY
	sta (zg_obj),y
	iny
	lda #0
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	txa
	jmp plat_put
psl_off
	ldy #OB_Y+1               ; (ix+5) & $1F = 0 -> Vy = 0, inaczej HL = $FFC0, C = $FF
	lda (zg_obj),y
	and #$1F
	beq psl_v                 ; @platform_was_at_top
	lda #$FF
psl_v
	sta zg_a                  ; bajty starsze 0 / $FF
	and #$C0                  ; mlodszy 0 / $C0
	ldy #OB_VY
	sta (zg_obj),y
	iny
	lda zg_a
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_0F_platform_horizontal (01:6D65): cele kamery (poza g_level 7 - JUN2); Sonic na platformie: put_sonic
; (BC $10, DE 0), C = 1. Licznik (ix+18/19) + 1; >= $A0 -> 0 i (ix+20) + 1 (zmiana kierunku). X += DE (+1 gdy
; (ix+20) b0 = 0, inaczej -1); z Sonikiem na platformie takze sonic_x += DE. Mapa GHZ / BRI / JUN wg
; g_tile_flags_index (0 / 1 / inne).
; ---------------------------------------------------------------------
objfunc_0F_platform_horizontal
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda g_level
	cmp #$07
	beq phz_nocam             ; @level_was_JUN2_dont_break_the_camera
	jsr plat_cam_targets
phz_nocam
	ldy #OB_W
	lda #$1A
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	lda #0                    ; C = 0 (Sonic nie na platformie)
	sta zg_tab
	jsr plat_hit
	bcs phz_cnt               ; @sonic_was_not_positioned_correctly
	lda #0                    ; BC = $0010, DE = 0
	jsr plat_put
	lda #1
	sta zg_tab
phz_cnt                         ; licznik (ix+18/19) + 1; HL - $A0 >= 0 -> licznik 0, inc (ix+20)
	ldy #18
	clc
	lda (zg_obj),y
	adc #1
	sta (zg_obj),y
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	bne phz_wrap              ; HL >= $100
	lda zg_hl
	cmp #$A0
	bcc phz_dir               ; @skip_carry_time_counter
phz_wrap
	lda #0                    ; (ix+18/19) = 0 (A = 0 z xor a), inc (ix+20)
	ldy #18
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
phz_dir                         ; DE = +1, a gdy (ix+20) b0: -1
	ldy #20
	lda (zg_obj),y
	lsr
	lda #$01
	ldx #$00
	bcc phz_pos
	lda #$FF
	ldx #$FF
phz_pos
	sta zg_de
	stx zg_de+1
	ldy #OB_X+1               ; X += DE
	clc
	lda (zg_obj),y
	adc zg_de
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta (zg_obj),y
	lda zg_tab                ; Sonic na platformie: sonic_x += DE
	beq phz_map
	clc
	lda sonic_x
	adc zg_de
	sta sonic_x
	lda sonic_x+1
	adc zg_de+1
	sta sonic_x+1
phz_map                         ; @level_art_selected
	lda #<SPR_PLAT_GHZ
	ldx #>SPR_PLAT_GHZ
	ldy g_tile_flags_index
	beq phz_set
	lda #<SPR_PLAT_BRI
	ldx #>SPR_PLAT_BRI
	dey
	beq phz_set
	lda #<SPR_PLAT_JUN
	ldx #>SPR_PLAT_JUN
phz_set
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	txa
	sta (zg_obj),y
	rts
