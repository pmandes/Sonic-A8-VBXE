; =====================================================================
;  obj/objz2_sbz_przycisk.asm - M6.9 Scrap Brain: $1D przycisk w podlodze - kopia obj/objz_lab_przycisk.asm (bank 11, PB_OBJZ) dla banku
;  obiektow strefy 2 (PB_OBJZ2, bank 2, dolaczany z objz2.asm). Logika identyczna z kopia w banku 11, inne etykiety (fb2_*, SPR_FB2_*).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_1D_floorbutton 02:A3F8 (kod 02:A3F8-02:A48A),
;  dane 02:A48B-02:A4AA (SPRTAB_floorbutton_SCR_down / _SCR_up / _LAB_down / _LAB_up) - w tym banku zakres OZ2_SPAN10 (SMS - OZ_OFF),
;  ten sam adres SMS co w banku 11 (OZ_SPAN21).
;  Procedury:
;   objfunc_1D_floor_button2  (02:A3F8) - funkcja obiektu (calosc, takze mapy Labyrinth - obiekt wspolny SCR / LAB)
;  Wolane: zc_collide (check_collision_with_sonic 00:3956), zc_put (put_sonic_y_pos_on_platform 01:7CC1) - stuby do banku 45,
;  level_mask (calc_level_offset_HL_and_mask_C 00:0C02, rezydentne), play_sfx (rst $28, rezydentne).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl.
; ---------------------------------------------------------------------
; Kolizje z mapa wlaczone (bez set 5), 10 x 17. Pierwszy tick (b0 flag = 0): x += 8, set 0. Sonic na przycisku (trafienie z
; przesunieciem (1, 0) i Vy Sonica >= 0): mapa "wcisniety" (SCR, albo LAB przy g_tile_flags_index = 3), Sonic stoi na przycisku
; (put_sonic_y_pos_on_platform: bc = $0006, de = 0); przy pierwszym ticku wcisniecia (b1 flag = 0): set 1, bit poziomu w
; g_level_button_toggled_on_mask odwrocony (xor), efekt $1A. Bez Sonica: res 1, mapa "zwolniony". Zawsze Vy = $000200 (przycisk
; dociskany do podlogi ruchem z kolizja z mapa).
; =====================================================================
; adresy SMS map (zakres OZ2_SPAN10 $A48B-$A4AA; zapisywane do (ix+15/16) jako adresy SMS - kopiuje je objz_mapcopy z banku v_pbobjz)
SPR_FB2_SCR_DN  = $A48B   ; SPRTAB_floorbutton_SCR_down (kafle $1A $1C)
SPR_FB2_SCR_UP  = $A493   ; SPRTAB_floorbutton_SCR_up   ($3A $3C)
SPR_FB2_LAB_DN  = $A49B   ; SPRTAB_floorbutton_LAB_down ($38 $3A)
SPR_FB2_LAB_UP  = $A4A3   ; SPRTAB_floorbutton_LAB_up   ($34 $36)

; ---------------------------------------------------------------------
; objfunc_1D_floor_button2 (02:A3F8): przycisk w podlodze - patrz opis pliku.
; ---------------------------------------------------------------------
objfunc_1D_floor_button2
	ldy #OB_W                 ; 02:A3F8: (ix+13) = $0A, (ix+14) = $11
	lda #$0A
	sta (zg_obj),y
	iny
	lda #$11
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:A400: bit 0,(ix+24) / jr nz,@already_initialised
	lda (zg_obj),y
	and #$01
	bne fb2_inited
	ldy #OB_X+1               ; 02:A406: (ix+2,3) += $0008
	clc
	lda (zg_obj),y
	adc #$08
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:A416: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
fb2_inited                      ; @already_initialised (02:A41A)
	lda #$01                  ; ld hl,$0001 / ld (tmp_06),hl: tmp_06 = $01, tmp_07 = $00
	sta tmp_06
	lda #$00
	sta tmp_07
	jsr zc_collide            ; 02:A420: check_collision_with_sonic: C = 1 brak trafienia
	bcs fb2_up                ; jr c,@button_is_up
	lda sonic_vel_y_hi        ; 02:A425: ld a,(sonic_vel_y_hi) / and a / jp m,@button_is_up (Sonic leci w gore)
	bmi fb2_up
	ldy #OB_SPRITE            ; 02:A42C: (ix+15/16) = SPRTAB_floorbutton_SCR_down
	lda #<SPR_FB2_SCR_DN
	sta (zg_obj),y
	iny
	lda #>SPR_FB2_SCR_DN
	sta (zg_obj),y
	lda g_tile_flags_index    ; 02:A434: cp $03 / jr nz,@down_not_LAB
	cmp #$03
	bne fb2_down_nolab
	ldy #OB_SPRITE            ; 02:A43B: Labyrinth: (ix+15/16) = SPRTAB_floorbutton_LAB_down
	lda #<SPR_FB2_LAB_DN
	sta (zg_obj),y
	iny
	lda #>SPR_FB2_LAB_DN
	sta (zg_obj),y
fb2_down_nolab                  ; @down_not_LAB (02:A443): ld bc,$0006 / ld de,$0000 / call put_sonic_y_pos_on_platform
	lda #$06
	sta zg_bc
	lda #$00
	sta zg_bc+1
	sta zg_de
	sta zg_de+1
	jsr zc_put
	ldy #OB_FLAGS             ; 02:A44C: bit 1,(ix+24) / jr nz,@common_epilogue (juz wcisniety w poprzednim ticku)
	lda (zg_obj),y
	and #$02
	bne fb2_epilogue
	lda (zg_obj),y            ; 02:A452: set 1,(ix+24)
	ora #$02
	sta (zg_obj),y
	; 02:A456: ld hl,g_level_button_toggled_on_mask / call calc_level_offset_HL_and_mask_C / ld a,(hl) / xor c / ld (hl),a:
	; level_mask: X = g_level >> 3 (przesuniecie bajtu w masce), A = 1 << (g_level & 7)
	jsr level_mask
	eor g_level_button_toggled_on_mask,x
	sta g_level_button_toggled_on_mask,x
	lda #$1A                  ; 02:A45F: ld a,$1A / rst $28
	jsr play_sfx
	jmp fb2_epilogue          ; jr @common_epilogue

fb2_up                          ; @button_is_up (02:A464): res 1,(ix+24)
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$FD
	sta (zg_obj),y
	ldy #OB_SPRITE            ; 02:A468: (ix+15/16) = SPRTAB_floorbutton_SCR_up
	lda #<SPR_FB2_SCR_UP
	sta (zg_obj),y
	iny
	lda #>SPR_FB2_SCR_UP
	sta (zg_obj),y
	lda g_tile_flags_index    ; 02:A470: cp $03 / jr nz,@common_epilogue
	cmp #$03
	bne fb2_epilogue
	ldy #OB_SPRITE            ; 02:A477: Labyrinth: (ix+15/16) = SPRTAB_floorbutton_LAB_up
	lda #<SPR_FB2_LAB_UP
	sta (zg_obj),y
	iny
	lda #>SPR_FB2_LAB_UP
	sta (zg_obj),y

fb2_epilogue                    ; @common_epilogue (02:A47F): Vy = $000200 ((ix+10) = 0, (ix+11) = $02, (ix+12) = 0)
	ldy #OB_VY
	lda #$00
	sta (zg_obj),y
	iny
	lda #$02
	sta (zg_obj),y
	iny
	lda #$00
	sta (zg_obj),y
	rts
