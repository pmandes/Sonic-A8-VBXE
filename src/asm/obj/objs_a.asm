; =====================================================================
;  obj/objs_a.asm - M4.3: obiekty $10 Motobug, $0A eksplozja, $55 rozsypane pierscienie (bank 45).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_10_badnik_motobug 01:6E0C,
;  objfunc_0A_explosion 01:693F, objfunc_55_thrown_ring_on_sonic_damage 01:7B95. Dane (sekwencje, mapy) leza
;  w banku 45 pod adresami SMS (objdata.inc). IX = zg_obj; tmp_* w lustrze RAM SMS jak oryginal.
; =====================================================================
LUT_MOTOBUG_SEQ  = $6E96   ; LUT_motobug_state_sequence (stan na kazde 32 ticki, 0 = od poczatku)
LUT_MOTOBUG_ANIM = $6EB1   ; LUT_motobug_state_anim_ptrs (slowa: sekwencje animacji dla stanow 0..4)
SPR_MOTOBUG      = $6ECB   ; SPRITEMAP_motobug_frames (klatka = 18 B)
LUT_EXPL_SEQ     = $69B7   ; LUT_explosion_state_sequence
SPR_EXPL         = $69BE   ; SPRITEMAP_explosion_frames
PTR_THROWN_RING  = $7C17   ; PTRTAB_thrown_ring_spriteptrs_and_sonicarts: 6 x (mapa, klatka Sonica)

; ---------------------------------------------------------------------
; objfunc_10_badnik_motobug (01:6E0C): kolizje z mapa wlaczone, rozmiar 10 x 16; stan z sekwencji
; (ix+18) - 0 = od poczatku: 1 jazda w lewo (Vx -1), 2 w prawo (Vx +1), inne stoi; (ix+17/18) + 8 (stan co
; 32 ticki); Vy = 2 px/tick; animacja wg stanu; kolizja z Soniciem (przesuniecie 3, 2), tmp_00 = 0 (wybuch
; w miejscu) - enemy_touched_sonic.
; ---------------------------------------------------------------------
objfunc_10_motobug
	ldy #OB_FLAGS             ; res 5,(ix+24)
	lda (zg_obj),y
	and #$DF
	sta (zg_obj),y
	ldy #OB_W
	lda #$0A
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	ldy #18
	lda (zg_obj),y            ; e = (ix+18)
mbg_find
	tax
	clc                       ; tmp_06 = LUT + e (adres SMS - stan gry jak oryginal)
	adc #<LUT_MOTOBUG_SEQ
	sta tmp_06
	lda #>LUT_MOTOBUG_SEQ
	adc #0
	sta tmp_06+1
	lda LUT_MOTOBUG_SEQ,x
	bne mbg_found
	ldy #18                   ; stan 0: (ix+18) = 0, od poczatku (A = 0; ldy zmienia Z - skok bezwarunkowy)
	sta (zg_obj),y
	jmp mbg_find
mbg_found
	sta zg_tab                ; stan (ld a,(hl) z tmp_06 - drugi odczyt nizej, ta sama wartosc)
	cmp #1
	bne mbg_n1
	ldx #$00                  ; Vx = $FF00 (lo, hi), C = $FF: -1 px/tick
	lda #$FF
	ldy #$FF
	bne mbg_vx
mbg_n1
	cmp #2
	bne mbg_n2
	ldx #$00                  ; Vx = $0100, C = 0
	lda #$01
	ldy #$00
	beq mbg_vx
mbg_n2
	ldx #0                    ; Vx = 0
	lda #0
	ldy #0
mbg_vx                          ; (ix+7) = X (L), (ix+8) = A (H), (ix+9) = Y (C)
	sty zg_a
	ldy #OB_VX
	pha
	txa
	sta (zg_obj),y
	iny
	pla
	sta (zg_obj),y
	iny
	lda zg_a
	sta (zg_obj),y
	ldy #17                   ; (ix+17/18) += 8
	clc
	lda (zg_obj),y
	adc #8
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	ldy #OB_VY                ; Vy = $000200
	lda #$00
	sta (zg_obj),y
	iny
	lda #$02
	sta (zg_obj),y
	iny
	lda #$00
	sta (zg_obj),y
	lda zg_tab                ; animacja stanu: LUT_motobug_state_anim_ptrs[stan] (ld hl,(tmp_06) / ld a,(hl))
	asl
	tax
	lda LUT_MOTOBUG_ANIM,x
	sta zg_bc
	lda LUT_MOTOBUG_ANIM+1,x
	sta zg_bc+1
	lda #<SPR_MOTOBUG
	sta zg_de
	lda #>SPR_MOTOBUG
	sta zg_de+1
	jsr do_framed_animation
	lda #$03                  ; tmp_06 = $0203: przesuniecie x 3, y 2
	sta tmp_06
	lda #$02
	sta tmp_06+1
	jsr check_collision_with_sonic
	lda #0                    ; tmp_00 = $0000 (przed call nc - flagi C z kolizji zostaja)
	sta tmp_00
	sta tmp_00+1
	bcs mbg_ret
	jmp enemy_touched_sonic
mbg_ret
	rts

; ---------------------------------------------------------------------
; objfunc_0A_explosion (01:693F): bez kolizji z mapa; pierwszy tick ((ix+21) != $AA): liczniki 0, znacznik
; $AA i odbicie Sonica z gory - gdy iy_00 b5, g_level != $12 i Sonic nie stoi (b7 flag), przy Vy >= 0:
; Vy = ~Vy + (g_sonic_bounce_vel_y + 1 w 16 bitach mlodszych) (24 bit). Potem predkosci 0, animacja
; (3 klatki po 9 tickow), (ix+17) + 1, przy 24 typ $FF.
; ---------------------------------------------------------------------
objfunc_0A_explosion
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #21
	lda (zg_obj),y
	cmp #$AA
	beq ex_main               ; inicjalizacja juz byla (znacznik zostaje w nieczyszczonym slocie!)
	lda #0
	ldy #17
	sta (zg_obj),y
	ldy #22
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #21
	lda #$AA
	sta (zg_obj),y
	lda iy_00
	and #$20
	beq ex_main
	lda g_level
	cmp #$12
	beq ex_main
	lda sonic_flags_ix_24     ; rlca: C = b7 (na ziemi) -> bez odbicia
	bmi ex_main
	lda sonic_vel_y_hi        ; and a / jp m: Vy < 0 -> bez odbicia
	bmi ex_main
	clc                       ; DE = bounce (sub, lo) + 1 (inc de: bez przeniesienia do bajtu hi)
	lda g_sonic_bounce_vel_y_sub
	adc #1
	sta zg_de
	lda g_sonic_bounce_vel_y_sub+1
	adc #0
	sta zg_de+1
	lda sonic_vel_y_sub       ; HL = ~(Vy sub, lo) + DE; A = ~Vy hi + bounce hi + C
	eor #$FF
	clc
	adc zg_de
	sta sonic_vel_y_sub
	lda sonic_vel_y
	eor #$FF
	adc zg_de+1
	sta sonic_vel_y
	lda sonic_vel_y_hi
	eor #$FF
	adc g_sonic_bounce_vel_y_sub+2
	sta sonic_vel_y_hi
ex_main
	lda #0                    ; @skip_sonic_bounce_off_top: Vx = Vy = 0
	ldy #OB_VX
ex_v0
	sta (zg_obj),y
	iny
	cpy #OB_VY+3
	bne ex_v0
	lda #<SPR_EXPL
	sta zg_de
	lda #>SPR_EXPL
	sta zg_de+1
	lda #<LUT_EXPL_SEQ
	sta zg_bc
	lda #>LUT_EXPL_SEQ
	sta zg_bc+1
	jsr do_framed_animation
	ldy #17                   ; inc (ix+17); >= $18 -> koniec
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$18
	bcc ex_ret
	ldy #OB_TYPE
	lda #$FF
	sta (zg_obj),y
ex_ret
	rts

; ---------------------------------------------------------------------
; objfunc_55_thrown_ring_on_sonic_damage (01:7B95): bez kolizji z mapa; nietykalnosc Sonica (iy_09 b0) co tick.
; Tick nieparzysty: mapa i klatka Sonica z PTRTAB[(ix+18)] (pierscienie w kaflach klatki Sonica - Sonic
; tego ticku nie widac: g_sonic_sprite_index_override), parzysty: mapa 0. Vy + $20 (grawitacja); ponizej
; ekranu (y > cam_y + 256) koniec ($FF, iy_09 b0 = 0); inaczej Vx = 0 i co 6 tickow nastepna klatka (0..5).
; ---------------------------------------------------------------------
objfunc_55_thrown_rings
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda iy_09                 ; set 0,(iy+9)
	ora #$01
	sta iy_09
	lda g_global_tick_counter
	and #1
	beq rg_even
	ldy #18                   ; BC = (ix+18) * 3
	lda (zg_obj),y
	sta zg_a
	asl
	clc
	adc zg_a
	tax
	lda PTR_THROWN_RING,x
	ldy #OB_SPRITE
	sta (zg_obj),y
	lda PTR_THROWN_RING+1,x
	iny
	sta (zg_obj),y
	lda PTR_THROWN_RING+2,x
	sta g_sonic_sprite_index_override
	jmp rg_vy
rg_even                         ; @tick_mod_2_is_0: mapa = A (= 0)
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
rg_vy                           ; Vy += $000020
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc #$20
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	clc                       ; HL = cam_y + 256 (inc h); HL < y -> koniec
	lda g_level_scroll_y_pix_lo
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #1
	sta zg_hl+1
	ldy #OB_Y+1
	lda zg_hl
	cmp (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	bcs rg_keep               ; jr nc: cam_y + 256 >= y
	ldy #OB_TYPE
	lda #$FF
	sta (zg_obj),y
	lda iy_09                 ; res 0,(iy+9)
	and #$FE
	sta iy_09
	rts
rg_keep                         ; @skip_despawn_at_bottom_of_screen: Vx = 0 (A = 0 po xor a / sbc)
	lda #0
	ldy #OB_VX
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #17                   ; dec (ix+17); 0 -> 6 tickow, nastepna klatka 0..5
	lda (zg_obj),y
	sec
	sbc #1
	sta (zg_obj),y
	bne rg_ret
	lda #6
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	clc
	adc #1
	cmp #6
	bcc rg_fr
	lda #0
rg_fr
	sta (zg_obj),y
rg_ret
	rts
