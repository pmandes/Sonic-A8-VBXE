; =====================================================================
;  obj/common.asm - M4.3: procedury wspolne obiektow (bank 45). Oryginal (s1smsdisasm-gm, tylko material
;  referencyjny): check_collision_with_sonic 00:3956, enemy_touched_sonic 00:35E5, explode_object_IX 00:36BE,
;  add_CHL_points_to_score_in_BCD 00:39D8, do_framed_animation 01:7C41.
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl (robocze obj_motion - wolne w funkcji obiektu,
;  bo ruch idzie po niej). Przeniesienie jako wynik: C jak w Z80 (C = 1 - brak trafienia).
; =====================================================================

; ---------------------------------------------------------------------
; check_collision_with_sonic (00:3956): prostokat obiektu [x + tmp_06, x + szer] x [y + tmp_07, y + wys]
; (tmp_06/07 bajty, (ix+13/14) szerokosc/wysokosc) vs Sonic [sonic_x, sonic_x + sonic_size_x] x [sonic_y,
; sonic_y + sonic_size_y]. Wynik: C = 1 brak trafienia (takze gdy Sonic umiera - iy_05 b0), C = 0 trafienie.
; Kolejnosc porownan i przeniesienia 16 bit jak oryginal (sumy obciete do 16 bit). Niszczy A, Y.
; ---------------------------------------------------------------------
check_collision_with_sonic
	lda iy_05_lvflag00
	lsr
	bcs ccs_ret               ; scf / ret nz: Sonic umiera
	ldy #OB_X+1               ; HL = x + szer; HL < sonic_x -> brak (ret c)
	clc
	lda (zg_obj),y
	ldy #OB_W
	adc (zg_obj),y
	sta zg_hl
	ldy #OB_X+2
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	lda zg_hl
	cmp sonic_x
	lda zg_hl+1
	sbc sonic_x+1
	bcc ccs_miss
	ldy #OB_X+1               ; DE = x + tmp_06; HL = sonic_x + sonic_size_x; HL < DE -> brak
	clc
	lda (zg_obj),y
	adc tmp_06
	sta zg_de
	iny
	lda (zg_obj),y
	adc #0
	sta zg_de+1
	clc
	lda sonic_x
	adc sonic_width_ix_13
	sta zg_hl
	lda sonic_x+1
	adc #0
	sta zg_hl+1
	lda zg_hl
	cmp zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs ccs_y                 ; (wyjscia w srodku procedury - zasieg skokow wzglednych)
ccs_miss
	sec
ccs_ret
	rts
ccs_y
	ldy #OB_Y+1               ; HL = y + wys; HL < sonic_y -> brak
	clc
	lda (zg_obj),y
	ldy #OB_H
	adc (zg_obj),y
	sta zg_hl
	ldy #OB_Y+2
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	lda zg_hl
	cmp sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcc ccs_miss
	ldy #OB_Y+1               ; DE = y + tmp_07; HL = sonic_y + sonic_size_y; HL < DE -> brak, inaczej trafienie
	clc
	lda (zg_obj),y
	adc tmp_07
	sta zg_de
	iny
	lda (zg_obj),y
	adc #0
	sta zg_de+1
	clc
	lda sonic_y
	adc sonic_height_ix_14
	sta zg_hl
	lda sonic_y+1
	adc #0
	sta zg_hl+1
	lda zg_hl
	cmp zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcc ccs_miss
	clc                       ; trafienie
	rts

; ---------------------------------------------------------------------
; enemy_touched_sonic (00:35E5): Sonic umiera (iy_05 b0) - nic; niesmiertelnosc (iy_08 b0), toczenie (flagi b0)
; albo skok / toczenie w powietrzu (b2) - wrog wybucha (explode_object_IX); inaczej damage_sonic (00:35FD).
; ---------------------------------------------------------------------
enemy_touched_sonic
	lda iy_05_lvflag00
	lsr
	bcs ets_ret
	lda iy_08_lvflag03
	lsr
	bcs explode_object_IX
	lda sonic_flags_ix_24
	lsr                       ; rrca: C = b0
	bcs explode_object_IX
	and #$02                  ; po rrca: b1 = b2 flag
	bne explode_object_IX
	jmp damage_sonic
ets_ret
	rts

; ---------------------------------------------------------------------
; explode_object_IX (00:36BE): typ := $0A (eksplozja), x += tmp_00, y += tmp_01 (bajty bez znaku, 16 bit),
; mapa 0, efekt $01, wynik + 100 (add_CHL_points_to_score_in_BCD: DE = $0100, C = 0).
; ---------------------------------------------------------------------
explode_object_IX
	ldy #OB_TYPE
	lda #$0A
	sta (zg_obj),y
	ldy #OB_X+1
	clc
	lda (zg_obj),y
	adc tmp_00
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	ldy #OB_Y+1
	clc
	lda (zg_obj),y
	adc tmp_00+1
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	lda #0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #$01                  ; rst $28: wybuch
	jsr play_sfx
	lda #$00                  ; DE = $0100, C = 0: 100 punktow
	sta zg_de
	lda #$01
	sta zg_de+1
	lda #$00
	sta zg_bc
	jmp add_CHL_points

; ---------------------------------------------------------------------
; add_CHL_points (add_CHL_points_to_score_in_BCD 00:39D8): wynik BCD big endian (D2BA..D2BD) += C:D:E
; (zg_bc, zg_de+1, zg_de): add / adc z daa od najmlodszego bajtu, przeniesienie do D2BA. Gdy bajt D2BB
; (dziesiatki tysiecy) >= g_next_life_bonus_10000s_BCD: premia + 5 (BCD), zycie + 1, efekt $09.
; ---------------------------------------------------------------------
add_CHL_points
	clc
	lda zg_de
	ldx #3
	jsr acp_add               ; D2BD += E
	lda zg_de+1
	ldx #2
	jsr acp_add               ; D2BC += D + C
	lda zg_bc
	ldx #1
	jsr acp_add               ; D2BB += C + C
	sta zg_tab                ; ld c,a
	lda #0
	ldx #0
	jsr acp_add               ; D2BA += 0 + C
	lda zg_tab                ; cp (hl): bajt < premii -> koniec
	cmp g_next_life_bonus_10000s_BCD
	bcc acp_ret
	lda g_next_life_bonus_10000s_BCD
	ldy #5
	clc
	jsr bcd_adc_y
	sta g_next_life_bonus_10000s_BCD
	inc g_lives
	lda #$09                  ; rst $28: dodatkowe zycie
	jmp play_sfx
acp_ret
	rts

acp_add                         ; g_score[X] = A + g_score[X] + C (BCD); wynik w A i w RAM, C = przeniesienie
	ldy g_score_BCD,x
	jsr bcd_adc_y
	sta g_score_BCD,x
	rts

; bcd_adc_y: A = A + Y + C w BCD (poprawne cyfry) - jak adc + daa; C = przeniesienie (bez trybu dziesietnego 6502:
; NMI liczy binarnie). Niszczy Y; zachowuje X.
bcd_adc_y
	sty zg_off
	sta zg_a
	lda #0
	rol                       ; C wejsciowe
	sta zg_hl
	lda zg_a
	and #$0F
	sta zg_hl+1
	lda zg_off
	and #$0F
	clc
	adc zg_hl+1
	adc zg_hl                 ; mlodsza cyfra + C
	ldy #0
	cmp #10
	bcc bay_lo
	sbc #10                   ; C = 1
	iny
bay_lo
	sta zg_hl+1
	sty zg_hl                 ; przeniesienie do starszej cyfry
	lda zg_a
	lsr
	lsr
	lsr
	lsr
	sta zg_a
	lda zg_off
	lsr
	lsr
	lsr
	lsr
	clc
	adc zg_a
	adc zg_hl                 ; starsza cyfra + przeniesienie
	cmp #10
	bcc bay_hi                ; C = 0
	sbc #10                   ; C = 1 (przeniesienie wyjsciowe)
bay_hi
	php
	asl
	asl
	asl
	asl
	ora zg_hl+1
	plp
	rts

; ---------------------------------------------------------------------
; put_sonic_y_pos_on_platform (01:7CC1, M4.4): Sonic stoi na platformie IX. Nic, gdy Sonic ogluszony (iy_06 b6).
; sonic_y = (Y obiektu 24 bit + DE ze znakiem) >> 8 + BC - sonic_size_y (16 bit: ld l,h / ld h,a odrzuca
; subpiksel; subpiksel Sonica bez zmian), Vy Sonica = g_sonic_bounce_vel_y (24 bit), flagi Sonica b7 (na ziemi).
; Wejscie: zg_bc = BC (wysokosc wierzchu, $0010), zg_de = DE (Vy platformy - pozycja po ruchu w tym ticku).
; ---------------------------------------------------------------------
put_sonic_y_pos_on_platform
	lda iy_06_lvflag01
	and #$40
	bne psp_ret               ; bit 6,(iy+6) / ret nz
	ldx #0                    ; A = rozszerzenie znaku D (xor a / bit 7,d / dec a)
	lda zg_de+1
	bpl psp_pos
	dex
psp_pos
	stx zg_a
	ldy #OB_Y                 ; HL = (ix+4, ix+5) + DE; mlodszy wynik odrzucany (ld l,h), liczy sie C
	clc
	lda (zg_obj),y
	adc zg_de
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_hl                 ; L = H
	iny
	lda zg_a
	adc (zg_obj),y            ; adc a,(ix+6)
	sta zg_hl+1               ; H = A
	clc                       ; HL += BC
	lda zg_hl
	adc zg_bc
	sta zg_hl
	lda zg_hl+1
	adc zg_bc+1
	sta zg_hl+1
	sec                       ; HL -= sonic_size_y (xor a / sbc hl,bc: C = 0 przed odejmowaniem)
	lda zg_hl
	sbc sonic_height_ix_14
	sta sonic_y
	lda zg_hl+1
	sbc #0
	sta sonic_y+1
	lda g_sonic_bounce_vel_y_sub ; Vy Sonica = odbicie (sub, lo, hi)
	sta sonic_vel_y_sub
	lda g_sonic_bounce_vel_y_sub+1
	sta sonic_vel_y
	lda g_sonic_bounce_vel_y_sub+2
	sta sonic_vel_y_hi
	lda sonic_flags_ix_24     ; set 7: na ziemi
	ora #$80
	sta sonic_flags_ix_24
psp_ret
	rts

; ---------------------------------------------------------------------
; do_framed_animation (01:7C41): zg_bc = sekwencja (pary klatka, czas; $FF - od poczatku), zg_de = baza map
; sprite'ow (adresy SMS = adresy w banku 45). Indeks pary (ix+23), licznik czasu (ix+22): mapa (ix+15/16) =
; baza + klatka * 18; (ix+22) + 1; gdy czas < (ix+22): (ix+22) = 0, (ix+23) + 2 - klatka trwa czas + 1 tickow.
; (Rejestry po powrocie - BC = klatka * 2, HL = adres czasu - wywolujacy w GHZ nie uzywaja.)
; ---------------------------------------------------------------------
do_framed_animation
	ldy #23
	lda (zg_obj),y
	tay
dfa_find
	lda (zg_bc),y
	cmp #$FF
	bne dfa_found
	lda #0                    ; koniec sekwencji: (ix+23) = 0, od poczatku
	ldy #23
	sta (zg_obj),y
	tay
	beq dfa_find
dfa_found
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
	bcs dfa_ret               ; ret nc: czas >= (ix+22)
	lda #0
	ldy #22
	sta (zg_obj),y
	iny
	lda (zg_obj),y            ; inc (ix+23) x 2
	clc
	adc #2
	sta (zg_obj),y
dfa_ret
	rts
