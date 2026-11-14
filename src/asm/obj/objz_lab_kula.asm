; =====================================================================
;  obj/objz_lab_kula.asm - M6.8 Labyrinth: $3D kula z kolcami krazaca po okregu (bank obiektow strefy PB_OBJZ, dolaczany z objz.asm).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_3D_spinning_spike_ball 02:88FB (kod 02:88FB-02:8986),
;  dane 02:8987-02:8AF5 (SPRTAB_spinning_spike_ball, LUT_spinning_spike_ball_xy_positions: 180 par (dx, dy) ze znakiem) - zakres
;  OBJZ_SPANS w tym banku (SMS - OZ_OFF).
;  Procedury:
;   objfunc_3D_spike_ball   (02:88FB) - funkcja obiektu
;  Wolane: zc_collide (check_collision_with_sonic 00:3956), damage_sonic (00:35FD, rezydentne).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl.
; ---------------------------------------------------------------------
; Bez kolizji z mapa (set 5), 8 x 12. Pierwszy tick (b0 flag = 0): srodek okregu (ix+18/19) = x + 8, (ix+20/21) = y + 8, set 0.
; Co tick: pozycja (piksele, bez subpikseli) = srodek + (dx, dy) z tablicy wg kata (ix+17) (0..$B3, 16-bitowy indeks *2;
; dx, dy rozszerzone ze znakiem do 16 bit), trafienie (strefa przesunieta o (4, 2)) - damage_sonic, mapa SPRTAB_spinning_spike_ball,
; kat + 1, od $B4 znowu 0 (pelny obrot = 180 tickow).
; =====================================================================
; adresy SMS danych (zakres OBJZ_SPANS $8987-$8AF5; czytane w tym banku pod adresem SMS - OZ_OFF)
SPR_KB          = $8987   ; SPRTAB_spinning_spike_ball (kafle $60 $62)
LUT_KB_XY       = $898E   ; LUT_spinning_spike_ball_xy_positions: 180 x (dx, dy)

; ---------------------------------------------------------------------
; objfunc_3D_spike_ball (02:88FB): kula z kolcami - patrz opis pliku.
; ---------------------------------------------------------------------
objfunc_3D_spike_ball
	ldy #OB_FLAGS             ; set 5,(ix+24): bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W                 ; (ix+13) = $08, (ix+14) = $0C
	lda #$08
	sta (zg_obj),y
	iny
	lda #$0C
	sta (zg_obj),y
	ldy #OB_FLAGS             ; bit 0,(ix+24) / jr nz,@already_initialised
	lda (zg_obj),y
	and #$01
	bne kb_inited
	ldy #OB_X+1               ; hl = (ix+2,3) + $0008 -> (ix+18,19) (ldy nie zmienia C - przeniesienie z mlodszego bajtu)
	clc
	lda (zg_obj),y
	adc #$08
	ldy #18
	sta (zg_obj),y
	ldy #OB_X+2
	lda (zg_obj),y
	adc #$00
	ldy #19
	sta (zg_obj),y
	ldy #OB_Y+1               ; hl = (ix+5,6) + $0008 -> (ix+20,21)
	clc
	lda (zg_obj),y
	adc #$08
	ldy #20
	sta (zg_obj),y
	ldy #OB_Y+2
	lda (zg_obj),y
	adc #$00
	ldy #21
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
kb_inited                       ; @already_initialised: hl = LUT + (ix+17) * 2 (16 bit: ld h,0 / add hl,hl / add hl,de)
	ldy #17
	lda (zg_obj),y
	asl                       ; add hl,hl: C = bit 7 kata -> starszy bajt
	sta zg_hl
	lda #$00
	rol
	sta zg_hl+1
	clc                       ; + adres tablicy w oknie (SMS - OZ_OFF)
	lda zg_hl
	adc #<[LUT_KB_XY-OZ_OFF]
	sta zg_hl
	lda zg_hl+1
	adc #>[LUT_KB_XY-OZ_OFF]
	sta zg_hl+1
	ldy #0                    ; ld e,(hl) / inc hl / ld c,(hl): e = dx, c = dy
	lda (zg_hl),y
	sta zg_de
	iny
	lda (zg_hl),y
	sta zg_bc
	ldx #$00                  ; ld d,$00 / bit 7,e / jr z / dec d: d = rozszerzenie znaku dx
	lda zg_de
	bpl kb_dxpos
	dex
kb_dxpos                        ; @dx_was_positive
	stx zg_de+1
	ldx #$00                  ; ld b,d (= 0) / bit 7,c / jr z / dec b: b = rozszerzenie znaku dy
	lda zg_bc
	bpl kb_dypos
	dex
kb_dypos                        ; @dy_was_positive
	stx zg_bc+1
	ldy #18                   ; hl = (ix+18,19) + de -> (ix+2,3) (x pikselowe; subpiksel (ix+1) bez zmian)
	clc
	lda (zg_obj),y
	adc zg_de
	ldy #OB_X+1
	sta (zg_obj),y
	ldy #19
	lda (zg_obj),y
	adc zg_de+1
	ldy #OB_X+2
	sta (zg_obj),y
	ldy #20                   ; hl = (ix+20,21) + bc -> (ix+5,6)
	clc
	lda (zg_obj),y
	adc zg_bc
	ldy #OB_Y+1
	sta (zg_obj),y
	ldy #21
	lda (zg_obj),y
	adc zg_bc+1
	ldy #OB_Y+2
	sta (zg_obj),y
	lda #$04                  ; ld hl,$0204 / ld (tmp_06),hl: tmp_06 = $04, tmp_07 = $02
	sta tmp_06
	lda #$02
	sta tmp_07
	jsr zc_collide            ; check_collision_with_sonic: C = 1 brak trafienia
	bcs kb_nohit              ; call nc,damage_sonic
	jsr damage_sonic
kb_nohit
	ldy #OB_SPRITE            ; (ix+15/16) = SPRTAB_spinning_spike_ball (adres SMS)
	lda #<SPR_KB
	sta (zg_obj),y
	iny
	lda #>SPR_KB
	sta (zg_obj),y
	ldy #17                   ; inc (ix+17) / cp $B4 / ret c (Z80 c = 6502 C = 0 po cmp)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$B4
	bcc kb_ret
	lda #$00                  ; (ix+17) = 0
	sta (zg_obj),y
kb_ret
	rts
