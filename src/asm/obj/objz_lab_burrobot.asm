; =====================================================================
;  obj/objz_lab_burrobot.asm - M6.8 Labyrinth: $44 Burrobot (LAB2; bank obiektow strefy PB_OBJZ, bank 11).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_44_badnik_burrobot 02:8F6D-02:9044,
;  dane LUT_burrobot_anim_sequence_walk_right 02:9045, _walk_left 02:904A, _jump_right 02:904F, _jump_left 02:9054,
;  SPRTAB_badnik_burrobot 02:9059 (6 klatek po 18 B; zakres OBJZ_SPANS 02:9045-02:90BF).
;  Procedury:
;   objfunc_44_burrobot  (02:8F6D) - funkcja obiektu $44
;  Animacja: oz_dfa (kopia do_framed_animation 01:7C41 w tym banku - sekwencje i mapy leza tutaj).
;  Pola rekordu: (ix+22/23) licznik i indeks animacji (oz_dfa), (ix+24) b0 = w skoku, b1 = zwrocony w lewo,
;  b7 = na ziemi (z obj_motion poprzedniego ticku). Kolizje z mapa wlaczone (bez set 5).
;  Wola: zc_collide, zc_enemy (stuby do banku 45), oz_dfa (ten bank). Bez obiektow tworzonych w locie.
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl; C (Vy hi) = zg_a.
; =====================================================================
LUT_BRB_WALKR   = $9045   ; LUT_burrobot_anim_sequence_walk_right (0, 4, 1, 4, $FF)
LUT_BRB_WALKL   = $904A   ; LUT_burrobot_anim_sequence_walk_left (2, 4, 3, 4, $FF)
LUT_BRB_JUMPR   = $904F   ; LUT_burrobot_anim_sequence_jump_right (4, 4, 4, 4, $FF)
LUT_BRB_JUMPL   = $9054   ; LUT_burrobot_anim_sequence_jump_left (5, 4, 5, 4, $FF)
SPR_BRB         = $9059   ; SPRTAB_badnik_burrobot (klatka = 18 B)

; ---------------------------------------------------------------------
; objfunc_44_badnik_burrobot (02:8F6D): 12 x 32, trafienie Sonica (przesuniecie (2, 2)) -> enemy_touched_sonic
; (tmp_00 = $0800: wybuch przesuniety o (0, 8)). Grawitacja: Vy (24 bit) + $10; gdy wynik nieujemny i bajt pikseli
; Vy (ix+11) >= 4 -> Vy = $000300. Na ziemi / w marszu (b0 = 0): Sonic w (x - 48, x + 48] w poziomie (16 bit)
; -> skok (set 0, Vy = $FFFD80); potem kierunek wg strony Sonica: x >= sonic_x -> w lewo (Vx = $FFFFC0, animacja
; marszu w lewo, set 1), inaczej w prawo (Vx = $000040, marsz w prawo, res 1). W skoku (b0 = 1): Vx bez zmian,
; animacja skoku wg b1; po wyladowaniu (b7 = 1) res 0.
; ---------------------------------------------------------------------
objfunc_44_burrobot
	ldy #OB_W                 ; (ix+13) = $0C, (ix+14) = $20
	lda #$0C
	sta (zg_obj),y
	iny
	lda #$20
	sta (zg_obj),y
	lda #$02                  ; ld hl,$0202 / ld (tmp_06),hl
	sta tmp_06
	sta tmp_07
	jsr zc_collide            ; check_collision_with_sonic
	lda #$00                  ; ld hl,$0800 / ld (tmp_00),hl: tmp_00 = $00, tmp_01 = $08 (lda/sta nie zmieniaja C)
	sta tmp_00
	lda #$08
	sta tmp_00+1
	bcs brb_nohit             ; call nc,enemy_touched_sonic
	jsr zc_enemy
brb_nohit
	ldy #OB_VY                ; hl = (ix+10/11) + $0010, a = (ix+12) + przeniesienie (adc a,$00), c = a
	clc
	lda (zg_obj),y
	adc #$10
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	iny
	lda (zg_obj),y
	adc #0
	sta zg_a                  ; ld c,a (flagi z adc: S = bit 7 wyniku)
	bmi brb_vsel              ; jp m @selected_y_vel: Vy ujemne - bez ograniczenia
	lda zg_hl+1               ; ld a,h / cp $04 / jr c: h < 4 -> bez ograniczenia
	cmp #$04
	bcc brb_vsel
	lda #$00                  ; hl = $0300, c = 0
	sta zg_hl
	sta zg_a
	lda #$03
	sta zg_hl+1
brb_vsel                        ; @selected_y_vel: (ix+10) = l, (ix+11) = h, (ix+12) = c
	ldy #OB_VY
	lda zg_hl
	sta (zg_obj),y
	iny
	lda zg_hl+1
	sta (zg_obj),y
	iny
	lda zg_a
	sta (zg_obj),y
	ldy #OB_FLAGS             ; bit 0,(ix+24) / jp nz @currently_jumping
	lda (zg_obj),y
	and #$01
	jne brb_jump
	ldy #OB_X+1               ; hl = x + $FFD0 (x - 48, 16 bit z zawinieciem), de = sonic_x
	clc
	lda (zg_obj),y
	adc #<$FFD0
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #>$FFD0
	sta zg_hl+1
	sec                       ; and a / sbc hl,de / jr nc: x - 48 >= sonic_x (bez pozyczki; 6502 C = 1) -> bez skoku
	lda zg_hl
	sbc sonic_x
	lda zg_hl+1
	sbc sonic_x+1
	bcs brb_nojump
	ldy #OB_X+1               ; hl = x + $0030
	clc
	lda (zg_obj),y
	adc #$30
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	sec                       ; sbc hl,de / jr c: x + 48 < sonic_x (pozyczka; 6502 C = 0) -> bez skoku
	lda zg_hl
	sbc sonic_x
	lda zg_hl+1
	sbc sonic_x+1
	bcc brb_nojump
	ldy #OB_FLAGS             ; skok: set 0,(ix+24), Vy = $FFFD80
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
	ldy #OB_VY
	lda #$80
	sta (zg_obj),y
	lda #$FD
	iny
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
brb_nojump                      ; @selected_x_vel_no_jump: x - sonic_x (16 bit): pozyczka -> Sonic na prawo
	ldy #OB_X+1
	sec
	lda (zg_obj),y
	sbc sonic_x
	iny
	lda (zg_obj),y
	sbc sonic_x+1
	bcc brb_right             ; jr c @sonic_was_to_the_right (6502: C = 0 = pozyczka)
	ldy #OB_VX                ; Sonic na lewo (albo rowno): Vx = $FFFFC0, marsz w lewo, set 1
	lda #$C0
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #<[LUT_BRB_WALKL-OZ_OFF]
	sta zg_bc
	lda #>[LUT_BRB_WALKL-OZ_OFF]
	sta zg_bc+1
	jsr brb_anim
	ldy #OB_FLAGS             ; set 1,(ix+24)
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
	rts
brb_right                       ; @sonic_was_to_the_right: Vx = $000040, marsz w prawo, res 1
	ldy #OB_VX
	lda #$40
	sta (zg_obj),y
	lda #$00
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #<[LUT_BRB_WALKR-OZ_OFF]
	sta zg_bc
	lda #>[LUT_BRB_WALKR-OZ_OFF]
	sta zg_bc+1
	jsr brb_anim
	ldy #OB_FLAGS             ; res 1,(ix+24)
	lda (zg_obj),y
	and #$FD
	sta (zg_obj),y
	rts
brb_jump                        ; @currently_jumping: bc = skok w lewo; bit 1,(ix+24) = 0 -> skok w prawo
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02
	bne brb_jl
	lda #<[LUT_BRB_JUMPR-OZ_OFF]
	ldx #>[LUT_BRB_JUMPR-OZ_OFF]
	bne brb_jset              ; zawsze (starszy bajt adresu okna <> 0)
brb_jl                          ; @jumping_to_the_left
	lda #<[LUT_BRB_JUMPL-OZ_OFF]
	ldx #>[LUT_BRB_JUMPL-OZ_OFF]
brb_jset
	sta zg_bc
	stx zg_bc+1
	jsr brb_anim
	ldy #OB_FLAGS             ; bit 7,(ix+24) / ret z: w powietrzu - dalej skok
	lda (zg_obj),y
	bpl brb_ret
	and #$FE                  ; na ziemi: res 0,(ix+24)
	sta (zg_obj),y
brb_ret
	rts

; brb_anim: de = SPRTAB_badnik_burrobot (adres SMS), call do_framed_animation (oz_dfa) z sekwencja zg_bc (adres okna)
brb_anim
	lda #<SPR_BRB
	sta zg_de
	lda #>SPR_BRB
	sta zg_de+1
	jmp oz_dfa
