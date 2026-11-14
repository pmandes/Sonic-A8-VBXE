; =====================================================================
;  obj/objs_g.asm - M6.6 Bridge: $26 Chopper (bank 45, luka OD_GAP16). Oryginal (s1smsdisasm-gm, tylko material
;  referencyjny): objfunc_26_badnik_chopper 01:7CF6. Dane (sekwencja animacji, mapy sprite'ow) w banku 45 pod
;  adresami SMS (OD_SPAN16, tools/extract_sms.py). IX = zg_obj; tmp_* w lustrze RAM SMS jak oryginal.
; =====================================================================
LUT_CHOP_ANIM   = $7DDC   ; LUT_chopper_anim_sequence: (klatka, czas) x 2, $FF
SPR_CHOP_NORM   = $7DE1   ; SPRITEMAP_chopper_normal (klatka = 18 B)
SPR_CHOP_EMERGE = $7DF7   ; SPRITEMAP_chopper_emerging

; ---------------------------------------------------------------------
; objfunc_26_badnik_chopper (01:7CF6): bez kolizji z mapa (set 5), rozmiar 8 x 12. (ix+20) = licznik ukrycia: > 0 -
; obiekt ukryty (mapa 0), licznik - 1. Skok (b0 flag): pierwszy tick - (ix+18/19) = y - 12 (poziom wody), x + 8,
; Vy = $FFFC00 (-4 px/tick), efekt $12, (ix+17) = 3 (ticki "wynurzania"), set 0; w skoku Vy + $10 (24 bit; Vy > $0400
; i dodatnie -> $0400), gdy y >= (ix+18/19) (opadl do wody): y = (ix+18/19), Vy = 0, ukrycie $1E ticki, res 0.
; Animacja (LUT_chopper_anim_sequence), w ticku wynurzania mapa SPRITEMAP_chopper_emerging; kolizja z Soniciem
; (przesuniecie 4, 2), przy trafieniu enemy_touched_sonic (tmp_00 = 0).
; ---------------------------------------------------------------------
objfunc_26_badnik_chopper
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W
	lda #$08
	sta (zg_obj),y
	iny
	lda #$0C
	sta (zg_obj),y
	ldy #20
	lda (zg_obj),y
	beq chp_visible           ; @not_hidden
	sec                       ; dec (ix+20)
	sbc #1
	sta (zg_obj),y
	lda #0                    ; mapa 0 (nie rysowac)
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	rts
chp_visible
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$01                  ; bit 0,(ix+24)
	bne chp_jumping
	lda (zg_obj),y
	and #$02                  ; bit 1,(ix+24)
	bne chp_init_done
	ldy #OB_Y+1              ; (ix+18/19) = y + $FFF4 (poziom wody)
	sec
	lda (zg_obj),y
	sbc #12
	ldy #18
	sta (zg_obj),y
	ldy #OB_Y+2
	lda (zg_obj),y
	sbc #0
	ldy #19
	sta (zg_obj),y
	ldy #OB_X+1               ; x += 8
	clc
	lda (zg_obj),y
	adc #8
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 1
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
chp_init_done                   ; @already_initialised: Vy = $FFFC00, set 0, efekt $12, wynurzanie 3 ticki
	ldy #OB_VY
	lda #$00
	sta (zg_obj),y
	iny
	lda #$FC
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
	lda #$12                  ; rst $28
	jsr play_sfx
	ldy #17
	lda #$03
	sta (zg_obj),y
	jmp chp_anim
chp_jumping                     ; @already_jumping: Vy += $10 (24 bit), Vy > $0400 -> $0400
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc #$10
	sta zg_de
	iny
	lda (zg_obj),y
	adc #0
	sta zg_de+1
	iny
	lda (zg_obj),y
	adc #0
	sta zg_a                  ; A (bajt wyzszy Vy)
	bmi chp_vstore            ; jp m,@skip_y_vel_clamp (Vy ujemne)
	sec                       ; hl = $0400 - de: pozyczka (de > $0400) -> de = $0400
	lda #$00
	sbc zg_de
	lda #$04
	sbc zg_de+1
	bcs chp_vstore            ; jr nc
	lda #$00
	sta zg_de
	lda #$04
	sta zg_de+1
chp_vstore
	ldy #OB_VY
	lda zg_de
	sta (zg_obj),y
	iny
	lda zg_de+1
	sta (zg_obj),y
	iny
	lda zg_a
	sta (zg_obj),y
	ldy #OB_Y+1               ; hl = y - (ix+18/19); pozyczka (y < poziom wody) -> @dont_hide
	sec
	lda (zg_obj),y
	ldy #18
	sbc (zg_obj),y
	ldy #OB_Y+2
	lda (zg_obj),y
	ldy #19
	sbc (zg_obj),y
	bcc chp_anim
	ldy #18                   ; y = (ix+18/19), Vy = 0, ukrycie $1E ticki, res 0
	lda (zg_obj),y
	ldy #OB_Y+1
	sta (zg_obj),y
	ldy #19
	lda (zg_obj),y
	ldy #OB_Y+2
	sta (zg_obj),y
	lda #0
	ldy #OB_Y                 ; subpiksel y = 0
	sta (zg_obj),y
	ldy #OB_VY
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #20
	lda #$1E
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$FE
	sta (zg_obj),y
chp_anim                        ; @dont_hide
	lda #<SPR_CHOP_NORM
	sta zg_de
	lda #>SPR_CHOP_NORM
	sta zg_de+1
	lda #<LUT_CHOP_ANIM
	sta zg_bc
	lda #>LUT_CHOP_ANIM
	sta zg_bc+1
	jsr do_framed_animation
	ldy #17
	lda (zg_obj),y
	beq chp_coll              ; @not_emerging
	sec                       ; dec (ix+17), mapa wynurzania
	sbc #1
	sta (zg_obj),y
	ldy #OB_SPRITE
	lda #<SPR_CHOP_EMERGE
	sta (zg_obj),y
	iny
	lda #>SPR_CHOP_EMERGE
	sta (zg_obj),y
chp_coll
	lda #$04                  ; hl = $0204: tmp_06 = 4, tmp_07 = 2
	sta tmp_06
	lda #$02
	sta tmp_07
	jsr check_collision_with_sonic
	lda #0                    ; ld hl,0 / ld (tmp_00),hl (przed call nc - bez wplywu na C)
	sta tmp_00
	sta tmp_00+1
	bcs chp_ret
	jmp enemy_touched_sonic
chp_ret
	rts
