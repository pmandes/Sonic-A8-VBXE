; =====================================================================
;  obj/objz_boss.asm - M6.6 Bridge: $48 boss BRI3 (bank obiektow strefy PB_OBJZ, dolaczany z objz.asm). Oryginal (s1smsdisasm-gm, tylko
;  material referencyjny): objfunc_48_BRI3_boss 02:8496, boss_fire_fireball_pallet 02:85D1. Wspolne procedury bossow
;  (boss_generic_update_8hp, kamera) - stuby zc_* do banku 45 (game/objcom.asm).
; ---------------------------------------------------------------------
; Bez kolizji z mapa (set 5), 30 x 28; kamera dojezdza do celu ($03A0, $0300) i zatrzymuje sie. Pierwszy tick (b0 flag = 0): cel
; kamery i granice okna, grafika bossa ART_0C_E508 (zc_bossart3), paleta PAL2_boss, muzyka $0B, trafienia = 0, set 0. Stany (ix+17):
;  0 - pozycja startowa z LUT_BRI3_boss_entrances wg random_A & 1 (x, y: $03D4/$03C0 albo $0444/$03C0), stan 1;
;  1 - wznoszenie (Vy = $FFFF80), gdy y <= $0380: stan 2, licznik (ix+18) = 0;
;  2 - zawis (Vy = 0), 100 ticków ((ix+18) = $64): stan 3 i - gdy trafienia < 8 - salwa trzech kul ognia ($0D) z (x + dx, y + dy)
;      wg strony Sonica (LUT ..._left / _right: dx, dy, potem 3 pary (Vx, Vy)), efekt $01;
;  3 - opadanie (Vy = $000080) do y > $03C0, potem stan 0.
; W kazdym ticku boss_generic_update_8hp (tmp_08 = $00A2: przesuniecie map SPRTAB_boss_generic_fly_out).
; ---------------------------------------------------------------------
objfunc_48_BRI3_boss
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W
	lda #$1E
	sta (zg_obj),y
	iny
	lda #$1C
	sta (zg_obj),y
	jsr zc_mlc                ; move_locked_camera_towards_target
	ldy #OB_SPRITE
	lda #<SPR_BRI3BOSS
	sta (zg_obj),y
	iny
	lda #>SPR_BRI3BOSS
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$01
	jne b3_init_done
	lda #<$03A0               ; set_locked_camera_target: HL = $03A0, DE = $0300
	sta zs_hl
	lda #>$03A0
	sta zs_hl+1
	lda #<$0300
	sta zs_de
	lda #>$0300
	sta zs_de+1
	jsr zc_slc
	jsr zc_bossart3           ; load_art ART_0C_E508 -> $2000
	lda iy_00                 ; signal_load_palettes (00:0333): A = 2 (sprite'y), HL = PAL2_boss
	ora #$08
	sta iy_00
	lda #$02
	sta g_SIG00b3_palettes_present
	lda #<PAL2_BOSS
	sta g_SIG00b3_palette_addr
	lda #>PAL2_BOSS
	sta g_SIG00b3_palette_addr+1
	lda #0
	sta g_boss_hits_taken
	lda #$0B                  ; rst $18
	jsr play_music
	ldy #OB_FLAGS             ; set 0
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
b3_init_done                    ; @already_initialised
	ldy #17
	lda (zg_obj),y
	bne b3_not0
	jsr random_A              ; stan 0: wejscie wg random_A & 1 (4 B na wpis: x, y)
	and #$01
	asl
	asl
	tax
	ldy #OB_X+1
	lda LUT_BOSS_ENTR-OZ_OFF,x
	sta (zg_obj),y
	iny
	lda LUT_BOSS_ENTR+1-OZ_OFF,x
	sta (zg_obj),y
	ldy #OB_Y+1
	lda LUT_BOSS_ENTR+2-OZ_OFF,x
	sta (zg_obj),y
	iny
	lda LUT_BOSS_ENTR+3-OZ_OFF,x
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	jmp b3_generic
b3_not0
	cmp #1
	bne b3_not1
	ldy #OB_VY                ; stan 1: Vy = $FFFF80
	lda #$80
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_Y+1               ; hl = $0380 - y; pozyczka (y > $0380) -> dalej wznoszenie
	sec
	lda #<$0380
	sbc (zg_obj),y
	iny
	lda #>$0380
	sbc (zg_obj),y
	jcc b3_generic
	ldy #17
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	lda #0
	ldy #18
	sta (zg_obj),y
	jmp b3_generic
b3_not1
	cmp #2
	jne b3_state3
	lda #0                    ; stan 2: Vy = 0, (ix+18) + 1 do $64
	ldy #OB_VY
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #18
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$64
	jne b3_generic
	ldy #17                   ; stan 3
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	lda g_boss_hits_taken
	cmp #$08
	jcs b3_generic            ; boss umiera - bez salwy
	sec                       ; hl = sonic_x - x: pozyczka (Sonic na lewo) -> tablica "left", inaczej "right"
	lda sonic_x
	ldy #OB_X+1
	sbc (zg_obj),y
	lda sonic_x+1
	iny
	sbc (zg_obj),y
	bcc b3_left
	lda #<[LUT_BOSS_VELR-OZ_OFF]
	ldx #>[LUT_BOSS_VELR-OZ_OFF]
	bne b3_fire               ; zawsze
b3_left
	lda #<[LUT_BOSS_VELL-OZ_OFF]
	ldx #>[LUT_BOSS_VELL-OZ_OFF]
b3_fire
	sta zg_prof
	stx zg_prof+1
	ldy #0                    ; de = dx, bc = dy: tmp_00 = x + dx, tmp_02 = y + dy
	clc
	ldy #OB_X+1
	lda (zg_obj),y
	ldy #0
	adc (zg_prof),y
	sta tmp_00
	ldy #OB_X+2
	lda (zg_obj),y
	ldy #1
	adc (zg_prof),y
	sta tmp_00+1
	clc
	ldy #OB_Y+1
	lda (zg_obj),y
	ldy #2
	adc (zg_prof),y
	sta tmp_02
	ldy #OB_Y+2
	lda (zg_obj),y
	ldy #3
	adc (zg_prof),y
	sta tmp_02+1
	clc                       ; hl += 4 (pary predkosci kul)
	lda zg_prof
	adc #4
	sta zg_prof
	bcc b3_np
	inc zg_prof+1
b3_np
	lda #3
	sta zg_hl                 ; licznik kul (b)
b3_each                         ; @each_fireball: tmp_04 = Vx, tmp_06 = Vy (po 16 bitow), c = $10
	ldy #0
	lda (zg_prof),y
	sta tmp_04
	iny
	lda (zg_prof),y
	sta tmp_04+1
	iny
	lda (zg_prof),y
	sta tmp_06
	iny
	lda (zg_prof),y
	sta tmp_07
	clc
	lda zg_prof
	adc #4
	sta zg_prof
	bcc b3_np2
	inc zg_prof+1
b3_np2
	lda #$10
	jsr b3_fireball
	dec zg_hl
	bne b3_each
	lda #$01                  ; rst $28
	jsr play_sfx
	jmp b3_generic
b3_state3                       ; stan >= 3: Vy = $000080; $03C0 - y: bez pozyczki (y <= $03C0) -> dalej, inaczej stan 0
	ldy #OB_VY
	lda #$80
	sta (zg_obj),y
	lda #0
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_Y+1
	sec
	lda #<$03C0
	sbc (zg_obj),y
	iny
	lda #>$03C0
	sbc (zg_obj),y
	bcs b3_generic
	lda #0
	ldy #17
	sta (zg_obj),y
b3_generic                      ; @do_generic_boss_update
	lda #<$00A2
	sta tmp_08
	lda #>$00A2
	sta tmp_08+1
	jmp zc_boss8

; b3_fireball (boss_fire_fireball_pallet 02:85D1): A = c ((ix+19) kuli); kula $0D w pierwszym wolnym slocie: x = tmp_00, y = tmp_02,
; (ix+17) = 0, (ix+19) = c, (ix+20..23) = 0, Vx = tmp_04, Vy = tmp_06 (16 bit ze znakiem rozszerzone do 24); brak slotu - nic.
; Zachowuje zg_hl (licznik) i zg_prof.
b3_fireball
	sta zg_a
	jsr spawn_object
	bcs b3f_ret
	ldy #OB_TYPE
	lda #$0D
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y            ; +1
	iny
	lda tmp_00
	sta (zg_ptr),y            ; +2, +3: x
	iny
	lda tmp_00+1
	sta (zg_ptr),y
	iny
	lda #0
	sta (zg_ptr),y            ; +4
	iny
	lda tmp_02
	sta (zg_ptr),y            ; +5, +6: y
	iny
	lda tmp_02+1
	sta (zg_ptr),y
	lda #0
	ldy #17
	sta (zg_ptr),y
	ldy #19
	lda zg_a
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y            ; +20..+23
	iny
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	ldx #0                    ; Vx: rozszerzenie znaku tmp_05 (starszy bajt tmp_04)
	lda tmp_04+1
	bpl b3f_xp
	dex
b3f_xp
	ldy #OB_VX
	lda tmp_04
	sta (zg_ptr),y
	iny
	lda tmp_04+1
	sta (zg_ptr),y
	iny
	txa
	sta (zg_ptr),y
	ldx #0                    ; Vy: tmp_06 / tmp_07
	lda tmp_07
	bpl b3f_yp
	dex
b3f_yp
	ldy #OB_VY
	lda tmp_06
	sta (zg_ptr),y
	iny
	lda tmp_07
	sta (zg_ptr),y
	iny
	txa
	sta (zg_ptr),y
b3f_ret
	rts
