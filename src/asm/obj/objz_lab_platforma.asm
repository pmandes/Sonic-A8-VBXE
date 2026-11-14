; =====================================================================
;  obj/objz_lab_platforma.asm - M6.8 Labyrinth: $45 platforma wyplywajaca (float-up platform) (bank obiektow strefy PB_OBJZ,
;  dolaczany z objz.asm).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_45_LAB_float_up_platform 02:90C0 (kod 02:90C0-02:91DD),
;  dane 02:91DE-02:91EA (SPRTAB_LAB_float_up_platform) - zakres OBJZ_SPANS w tym banku (SMS - OZ_OFF).
;  Procedury:
;   objfunc_45_float_platform   (02:90C0) - funkcja obiektu
;  Wolane: obj_tile_ptr (get_obj_level_tile_ptr_in_ram 00:36F9, game/motion.asm - rezydentne), zc_collide (check_collision_with_sonic
;  00:3956), zc_put (put_sonic_y_pos_on_platform 01:7CC1).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl, C (bajt Vy hi) = zg_a.
; ---------------------------------------------------------------------
; Bez kolizji z mapa (set 5), 30 x 28, mapa SPRTAB_LAB_float_up_platform. Pierwszy tick (b1 flag = 0): punkt startu (ix+17/18) = x,
; y -= 1, (ix+19/20) = y, set 1. Co tick blok ukladu pod punktem (x + $10, y + $20): typ kolizji (flagi strefy & $3F) = $1E -> Vy = 0
; (platforma oparta o blok); inaczej, gdy platforma ruszona (b0 = 1 - Sonic jej dotknal; set 0 przy kazdej kolizji, 02:91C1): Vy (24 bit) += $FFFFF8 (wyplywanie
; w gore, przyspieszenie 8 subpikseli), gdy Vy < -1 px/tick (bajt pikseli <= $FE: neg h / cp 2) Vy = $FFFF00 (-1 px/tick). Poza oknem wokol kamery
; (x <= kamera X - 32 albo x > kamera X + 256, y <= kamera Y - 32 albo y > kamera Y + $E0; porownania 16 bit bez znaku, sumy obciete
; do 16 bit) - powrot na punkt startu (subpiksele i Vy = 0, res 0). W oknie: Sonic na platformie (trafienie z przesunieciem (2, $0E))
; - set 0; gdy Vy pikselowe Sonica >= 0 albo > -2 - Sonic ustawiany na platformie (put_sonic_y_pos_on_platform, de = Vy, bc = $0010).
; =====================================================================
; adres SMS mapy (zakres OBJZ_SPANS $91DE-$91EA; zapisywany do (ix+15/16) jako adres SMS - kopiuje go objz_mapcopy)
SPR_FUP         = $91DE   ; SPRTAB_LAB_float_up_platform (wiersz 0: $FE + 5 x $FF, wiersz 1: $16 $18 $1A $1C)

; ---------------------------------------------------------------------
; objfunc_45_float_platform (02:90C0): platforma wyplywajaca - patrz opis pliku.
; ---------------------------------------------------------------------
objfunc_45_float_platform
	ldy #OB_FLAGS             ; set 5,(ix+24): bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W                 ; (ix+13) = $1E, (ix+14) = $1C
	lda #$1E
	sta (zg_obj),y
	iny
	lda #$1C
	sta (zg_obj),y
	ldy #OB_SPRITE            ; (ix+15/16) = SPRTAB_LAB_float_up_platform
	lda #<SPR_FUP
	sta (zg_obj),y
	iny
	lda #>SPR_FUP
	sta (zg_obj),y
	ldy #OB_FLAGS             ; bit 1,(ix+24) / jr nz,@already_initialised
	lda (zg_obj),y
	and #$02
	bne fup_inited
	ldy #OB_X+1               ; (ix+17,18) = (ix+2,3): x startu
	lda (zg_obj),y
	ldy #17
	sta (zg_obj),y
	ldy #OB_X+2
	lda (zg_obj),y
	ldy #18
	sta (zg_obj),y
	ldy #OB_Y+1               ; hl = (ix+5,6) + $FFFF (y - 1, 16 bit) -> (ix+5,6) i (ix+19,20)
	sec
	lda (zg_obj),y
	sbc #$01
	sta (zg_obj),y
	ldy #19
	sta (zg_obj),y
	ldy #OB_Y+2               ; (ldy / sta nie zmieniaja C - pozyczka z mlodszego bajtu)
	lda (zg_obj),y
	sbc #$00
	sta (zg_obj),y
	ldy #20
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 1,(ix+24)
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
fup_inited                      ; @already_initialised: ld bc,$0010 / ld de,$0020 / call get_obj_level_tile_ptr_in_ram
	lda #$10
	sta zg_bc
	lda #$00
	sta zg_bc+1
	sta zg_de+1
	lda #$20
	sta zg_de
	jsr obj_tile_ptr          ; zg_ptr = bajt ukladu pod (x + $10, y + $20); C = 1 - adres SMS < $C000 (ROM)
	bcs fup_rom
	ldy #0                    ; ld e,(hl) / ld d,0: numer bloku
	lda (zg_ptr),y
	tax
	lda TILEFLAGS_RAM,x       ; PTRLUT_level_tile_flags[g_tile_flags_index] + blok: flagi bloku strefy / and $3F
	and #$3F
	jmp fup_type
fup_rom                         ; adres ROM SMS: port nie ma ROM-u - typ 0 (jak obj_tile_type: licznik v_rom_reads)
	inc v_rom_reads
	lda #$00
fup_type                        ; ld c,$00 / ld l,c / ld h,c: hl = 0, c = 0 (Vy = 0 przy bloku $1E)
	ldx #$00
	stx zg_hl
	stx zg_hl+1
	stx zg_a
	cmp #$1E                  ; cp $1E / jr z,@set_y_vel_and_continue
	beq fup_setvy
	ldy #OB_FLAGS             ; bit 0,(ix+24) / jr z,@skip_set_y_vel (platforma nie ruszona)
	lda (zg_obj),y
	and #$01
	beq fup_skipvy
	; hl = (ix+10,11), a = (ix+12); add hl,$FFF8 / adc a,$FF: Vy (24 bit) + $FFFFF8 (przeniesienie przez trzy bajty)
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc #$F8
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #$FF
	sta zg_hl+1
	iny
	lda (zg_obj),y
	adc #$FF
	sta zg_a                  ; ld c,a
	lda #$00                  ; ld a,h / neg (0 - h, 8 bit) / cp $02 / jr c (Z80 c = 6502 C = 0 po cmp)
	sec
	sbc zg_hl+1
	cmp #$02
	bcc fup_setvy
	lda #$00                  ; ld hl,$FF00 / ld c,$FF: Vy = $FFFF00 (-1 px/tick)
	sta zg_hl
	lda #$FF
	sta zg_hl+1
	sta zg_a
fup_setvy                       ; @set_y_vel_and_continue: (ix+10) = l, (ix+11) = h, (ix+12) = c
	ldy #OB_VY
	lda zg_hl
	sta (zg_obj),y
	iny
	lda zg_hl+1
	sta (zg_obj),y
	iny
	lda zg_a
	sta (zg_obj),y
fup_skipvy                      ; @skip_set_y_vel: de = x (ix+2,3)
	; hl = kamera X + $FFE0 (16 bit, przeniesienie odrzucone); and a / sbc hl,de / jr nc,@reset_to_spawn_position
	; (Z80 nc = bez pozyczki = 6502 C = 1 po sbc)
	clc
	lda g_level_scroll_x_pix_lo
	adc #$E0
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #$FF
	sta zg_hl+1
	ldy #OB_X+1
	sec
	lda zg_hl
	sbc (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	bcs fup_reset
	; hl = kamera X, inc h (8 bit - kamera X + $100 z zawinieciem); and a / sbc hl,de / jr c,@reset_to_spawn_position
	; (Z80 c = pozyczka = 6502 C = 0)
	ldx g_level_scroll_x_pix_lo+1
	inx
	stx zg_hl+1
	ldy #OB_X+1
	sec
	lda g_level_scroll_x_pix_lo
	sbc (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	bcc fup_reset
	; de = y (ix+5,6); hl = kamera Y + $FFE0; sbc hl,de / jr nc,@reset_to_spawn_position
	clc
	lda g_level_scroll_y_pix_lo
	adc #$E0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #$FF
	sta zg_hl+1
	ldy #OB_Y+1
	sec
	lda zg_hl
	sbc (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	bcs fup_reset
	; hl = kamera Y + $00E0; sbc hl,de / jr nc,@skip_reset (bez pozyczki - w oknie); z pozyczka - dalej do @reset_to_spawn_position
	clc
	lda g_level_scroll_y_pix_lo
	adc #$E0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #$00
	sta zg_hl+1
	ldy #OB_Y+1
	sec
	lda zg_hl
	sbc (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	bcs fup_skipreset

fup_reset                       ; @reset_to_spawn_position: (ix+2,3) = (ix+17,18), (ix+5,6) = (ix+19,20)
	ldy #17
	lda (zg_obj),y
	ldy #OB_X+1
	sta (zg_obj),y
	ldy #18
	lda (zg_obj),y
	ldy #OB_X+2
	sta (zg_obj),y
	ldy #19
	lda (zg_obj),y
	ldy #OB_Y+1
	sta (zg_obj),y
	ldy #20
	lda (zg_obj),y
	ldy #OB_Y+2
	sta (zg_obj),y
	lda #$00                  ; xor a: (ix+1) = (ix+4) = 0 (subpiksele), (ix+10..12) = 0 (Vy)
	ldy #OB_X
	sta (zg_obj),y
	ldy #OB_Y
	sta (zg_obj),y
	ldy #OB_VY
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_FLAGS             ; res 0,(ix+24) / ret
	lda (zg_obj),y
	and #$FE
	sta (zg_obj),y
	rts

fup_skipreset                   ; @skip_reset: ld hl,$0E02 / ld (tmp_06),hl: tmp_06 = $02, tmp_07 = $0E
	lda #$02
	sta tmp_06
	lda #$0E
	sta tmp_07
	jsr zc_collide            ; check_collision_with_sonic / ret c (brak trafienia)
	bcs fup_ret
	ldy #OB_FLAGS             ; set 0,(ix+24): platforma ruszona
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
	lda sonic_vel_y           ; ld a,(sonic_vel_y) (bajt pikselowy lo) / and a / jp p,@put_sonic_on_platform
	bpl fup_put
	eor #$FF                  ; neg / cp $02 / ret nc: |Vy| >= 2 -> bez ustawiania Sonica (Z80 nc = 6502 C = 1)
	clc
	adc #$01
	cmp #$02
	bcs fup_ret
fup_put                         ; @put_sonic_on_platform: ld e,(ix+10) / ld d,(ix+11) / ld bc,$0010
	ldy #OB_VY
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	lda #$10
	sta zg_bc
	lda #$00
	sta zg_bc+1
	jmp zc_put                ; call put_sonic_y_pos_on_platform / ret
fup_ret
	rts
