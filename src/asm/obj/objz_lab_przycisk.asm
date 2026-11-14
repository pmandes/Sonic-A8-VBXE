; =====================================================================
;  obj/objz_lab_przycisk.asm - M6.8 Labyrinth (i Scrap Brain): $1D przycisk w podlodze (bank obiektow strefy PB_OBJZ, dolaczany z objz.asm).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_1D_floorbutton 02:A3F8 (kod 02:A3F8-02:A48A),
;  dane 02:A48B-02:A4AA (SPRTAB_floorbutton_SCR_down / _SCR_up / _LAB_down / _LAB_up) - zakres OBJZ_SPANS w tym banku (SMS - OZ_OFF).
;  Procedury:
;   objfunc_1D_floor_button   (02:A3F8) - funkcja obiektu (calosc, takze mapy Scrap Brain - obiekt wspolny SCR / LAB)
;  Wolane: zc_collide (check_collision_with_sonic 00:3956), zc_put (put_sonic_y_pos_on_platform 01:7CC1), level_mask
;  (calc_level_offset_HL_and_mask_C 00:0C02, rezydentne), play_sfx (rst $28).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl.
; ---------------------------------------------------------------------
; Kolizje z mapa wlaczone (bez set 5), 10 x 17. Pierwszy tick (b0 flag = 0): x += 8, set 0. Sonic na przycisku (trafienie z
; przesunieciem (1, 0) i Vy Sonica >= 0): mapa "wcisniety" (SCR, albo LAB przy g_tile_flags_index = 3), Sonic stoi na przycisku
; (put_sonic_y_pos_on_platform: bc = $0006, de = 0); przy pierwszym ticku wcisniecia (b1 flag = 0): set 1, bit poziomu w
; g_level_button_toggled_on_mask odwrocony (xor), efekt $1A. Bez Sonica: res 1, mapa "zwolniony". Zawsze Vy = $000200 (przycisk
; dociskany do podlogi ruchem z kolizja z mapa).
; =====================================================================
; adresy SMS map (zakres OBJZ_SPANS $A48B-$A4AA; zapisywane do (ix+15/16) jako adresy SMS - kopiuje je objz_mapcopy)
SPR_FBT_SCR_DN  = $A48B   ; SPRTAB_floorbutton_SCR_down (kafle $1A $1C)
SPR_FBT_SCR_UP  = $A493   ; SPRTAB_floorbutton_SCR_up   ($3A $3C)
SPR_FBT_LAB_DN  = $A49B   ; SPRTAB_floorbutton_LAB_down ($38 $3A)
SPR_FBT_LAB_UP  = $A4A3   ; SPRTAB_floorbutton_LAB_up   ($34 $36)

; ---------------------------------------------------------------------
; objfunc_1D_floor_button (02:A3F8): przycisk w podlodze - patrz opis pliku.
; ---------------------------------------------------------------------
objfunc_1D_floor_button
	ldy #OB_W                 ; (ix+13) = $0A, (ix+14) = $11
	lda #$0A
	sta (zg_obj),y
	iny
	lda #$11
	sta (zg_obj),y
	ldy #OB_FLAGS             ; bit 0,(ix+24) / jr nz,@already_initialised
	lda (zg_obj),y
	and #$01
	bne fbt_inited
	ldy #OB_X+1               ; (ix+2,3) += $0008
	clc
	lda (zg_obj),y
	adc #$08
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
fbt_inited                      ; @already_initialised
	lda #$01                  ; ld hl,$0001 / ld (tmp_06),hl: tmp_06 = $01, tmp_07 = $00
	sta tmp_06
	lda #$00
	sta tmp_07
	jsr zc_collide            ; check_collision_with_sonic: C = 1 brak trafienia
	bcs fbt_up                ; jr c,@button_is_up
	lda sonic_vel_y_hi        ; ld a,(sonic_vel_y_hi) / and a / jp m,@button_is_up (Sonic leci w gore)
	bmi fbt_up
	ldy #OB_SPRITE            ; (ix+15/16) = SPRTAB_floorbutton_SCR_down
	lda #<SPR_FBT_SCR_DN
	sta (zg_obj),y
	iny
	lda #>SPR_FBT_SCR_DN
	sta (zg_obj),y
	lda g_tile_flags_index    ; cp $03 / jr nz,@down_not_LAB
	cmp #$03
	bne fbt_down_nolab
	ldy #OB_SPRITE            ; Labyrinth: (ix+15/16) = SPRTAB_floorbutton_LAB_down
	lda #<SPR_FBT_LAB_DN
	sta (zg_obj),y
	iny
	lda #>SPR_FBT_LAB_DN
	sta (zg_obj),y
fbt_down_nolab                  ; @down_not_LAB: ld bc,$0006 / ld de,$0000 / call put_sonic_y_pos_on_platform
	lda #$06
	sta zg_bc
	lda #$00
	sta zg_bc+1
	sta zg_de
	sta zg_de+1
	jsr zc_put
	ldy #OB_FLAGS             ; bit 1,(ix+24) / jr nz,@common_epilogue (juz wcisniety w poprzednim ticku)
	lda (zg_obj),y
	and #$02
	bne fbt_epilogue
	lda (zg_obj),y            ; set 1,(ix+24)
	ora #$02
	sta (zg_obj),y
	; ld hl,g_level_button_toggled_on_mask / call calc_level_offset_HL_and_mask_C / ld a,(hl) / xor c / ld (hl),a:
	; level_mask: X = g_level >> 3 (przesuniecie bajtu w masce), A = 1 << (g_level & 7)
	jsr level_mask
	eor g_level_button_toggled_on_mask,x
	sta g_level_button_toggled_on_mask,x
	lda #$1A                  ; ld a,$1A / rst $28
	jsr play_sfx
	jmp fbt_epilogue          ; jr @common_epilogue

fbt_up                          ; @button_is_up: res 1,(ix+24)
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$FD
	sta (zg_obj),y
	ldy #OB_SPRITE            ; (ix+15/16) = SPRTAB_floorbutton_SCR_up
	lda #<SPR_FBT_SCR_UP
	sta (zg_obj),y
	iny
	lda #>SPR_FBT_SCR_UP
	sta (zg_obj),y
	lda g_tile_flags_index    ; cp $03 / jr nz,@common_epilogue
	cmp #$03
	bne fbt_epilogue
	ldy #OB_SPRITE            ; Labyrinth: (ix+15/16) = SPRTAB_floorbutton_LAB_up
	lda #<SPR_FBT_LAB_UP
	sta (zg_obj),y
	iny
	lda #>SPR_FBT_LAB_UP
	sta (zg_obj),y

fbt_epilogue                    ; @common_epilogue: Vy = $000200 ((ix+10) = 0, (ix+11) = $02, (ix+12) = 0)
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
