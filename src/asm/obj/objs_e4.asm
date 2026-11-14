; =====================================================================
;  objs_e4.asm - M6.4 GHZ3: zwierzeta $24 i $23 (stale G3B_* itd. w objs_e1.asm)
; =====================================================================
; ---------------------------------------------------------------------
; objfunc_24_animal_1 (01:7594): zwierze 1 (skacze w lewo): bez kolizji z mapa nie (res 5), rozmiar $0C x $10. Na ziemi
; (b7): Vy = $FFFD00. Grawitacja $0012 ($0038 w LAB), Vy ograniczone do $0200; Vx = $FFFE00 ($FE80 w LAB),
; animacja wg strefy (GHZ), animal_common.
; ---------------------------------------------------------------------
objfunc_24_animal_1
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$DF                  ; res 5,(ix+24)
	sta (zg_obj),y
	ldy #OB_W
	lda #$0C
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	bpl a1_air                ; bit 7,(ix+24): jr z
	lda #0                    ; na ziemi: Vy = $FFFD00
	ldy #OB_VY
	sta (zg_obj),y
	lda #$FD
	iny
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
a1_air                          ; @was_not_on_floor
	lda #$12                  ; DE = $0012 ($0038 przy g_tile_flags_index = 3)
	sta zs_de
	lda #0
	sta zs_de+1
	lda g_tile_flags_index
	cmp #$03
	bne a1_g
	lda #$38
	sta zs_de
a1_g
	jsr an_vy                 ; Vy += DE, ograniczone do $0200
	lda #$00                  ; HL = $FE00 ($FE80 przy 3)
	sta zs_hl
	lda #$FE
	sta zs_hl+1
	lda g_tile_flags_index
	cmp #$03
	bne a1_vx
	lda #$80
	sta zs_hl
a1_vx
	ldy #OB_VX
	lda zs_hl
	sta (zg_obj),y
	iny
	lda zs_hl+1
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	lda #<ANIM1_GHZ           ; BC = animacja wg strefy: 0 - GHZ, 3 - others, reszta - LAB
	sta zg_bc
	lda #>ANIM1_GHZ
	sta zg_bc+1
	lda g_tile_flags_index
	beq a1_sel
	lda #<ANIM1_LAB
	sta zg_bc
	lda #>ANIM1_LAB
	sta zg_bc+1
	lda g_tile_flags_index
	cmp #$03
	bne a1_sel
	lda #<ANIM1_OTH
	sta zg_bc
	lda #>ANIM1_OTH
	sta zg_bc+1
a1_sel                          ; @sprite_anim_selected
	lda #<SPR_ANIMAL1
	sta zg_de
	lda #>SPR_ANIMAL1
	sta zg_de+1
	jsr do_framed_animation
animal_common
	ldy #OB_X+1               ; HL = x + $10; HL - kamera X; ret nc; inaczej typ $FF
	clc
	lda (zg_obj),y
	adc #$10
	sta zs_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zs_hl+1
	lda zs_hl
	sec
	sbc g_level_scroll_x_pix_lo
	lda zs_hl+1
	sbc g_level_scroll_x_pix_lo+1
	jcs oac_ret                ; ret nc
	ldy #OB_TYPE
	lda #$FF
	sta (zg_obj),y
oac_ret
	rts

; an_vy: (ix+10..12) += DE (16 bit + przeniesienie do bajtu 3); gdy wynik >= 0 i bajt starszy HL >= 2: $000200
; (@skip_y_vel_clamp); zapis do (ix+10..12)
an_vy
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc zs_de
	sta zs_hl
	iny
	lda (zg_obj),y
	adc zs_de+1
	sta zs_hl+1
	iny
	lda (zg_obj),y
	adc #0                    ; adc a,0 z przeniesieniem dodawania 16 bit
	sta zs_c
	bmi anv_st                ; jp m
	lda zs_hl+1
	cmp #$02
	bcc anv_st
	lda #0
	sta zs_hl
	lda #2
	sta zs_hl+1
	lda #0
	sta zs_c
anv_st
	ldy #OB_VY
	lda zs_hl
	sta (zg_obj),y
	iny
	lda zs_hl+1
	sta (zg_obj),y
	iny
	lda zs_c
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_23_animal_0 (01:7699): zwierze 0 (skacze w miejscu i w lewo): res 5, rozmiar $0C x $20, mapa w powietrzu
; (GHZ). Na ziemi (b7): Vy = $000100, Vx = 0, mapa na ziemi; po 8 tickach na ziemi: Vy = $FFFC00 ($FFFE00 poza GHZ).
; Grawitacja $0028, Vy do $0200, Vx = $FFFE80, (ix+17) = 0, animal_common.
; ---------------------------------------------------------------------
objfunc_23_animal_0
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$DF
	sta (zg_obj),y
	ldy #OB_W
	lda #$0C
	sta (zg_obj),y
	iny
	lda #$20
	sta (zg_obj),y
	jsr a0_idx                ; mapa w powietrzu wg strefy (g_tile_flags_index 0 GHZ, 1 BRI, 2 JUN, reszta others)
	lda a0_air_lo,x
	ldy #OB_SPRITE
	sta (zg_obj),y
	lda #>SPR_AN0_AIR
	iny
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	jpl a0_air                ; bit 7,(ix+24): jr z,@was_not_on_ground
	lda #0
	ldy #OB_VY
	sta (zg_obj),y
	lda #1
	iny
	sta (zg_obj),y
	lda #0
	iny
	sta (zg_obj),y
	ldy #OB_VX
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	jsr a0_idx                ; mapa na ziemi wg strefy
	lda a0_gnd_lo,x
	ldy #OB_SPRITE
	sta (zg_obj),y
	lda #>SPR_AN0_GND
	iny
	sta (zg_obj),y
	ldy #17                   ; inc (ix+17); < 8 - ret
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$08
	jcc a0_ret
	lda #$FC                  ; HL = $FFFC ($FFFE przy g_tile_flags_index != 0)
	sta zs_t
	lda g_tile_flags_index
	beq a0_vy
	lda #$FE
	sta zs_t
a0_vy
	lda #0
	ldy #OB_VY
	sta (zg_obj),y
	iny
	lda zs_t
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
a0_air                          ; @was_not_on_ground
	lda #$28
	sta zs_de
	lda #0
	sta zs_de+1
	jsr an_vy
	ldy #OB_VX                ; Vx = $FFFE80
	lda #$80
	sta (zg_obj),y
	iny
	lda #$FE
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	ldy #17
	lda #0
	sta (zg_obj),y
	jmp animal_common
a0_ret
	rts
a0_idx                          ; X = min(g_tile_flags_index, 3)
	ldx g_tile_flags_index
	cpx #4
	bcc a0i_ret
	ldx #3
a0i_ret
	rts
a0_air_lo                       ; SPRITEMAP_animal_0_airborne_GHZ $7760, _BRI $777B, _JUN $7796, _others $77B1
	dta b($60, $7B, $96, $B1)
a0_gnd_lo                       ; SPRITEMAP_animal_0_on_ground_GHZ $7752, _BRI $776D, _JUN $7788, _others $77A3
	dta b($52, $6D, $88, $A3)

