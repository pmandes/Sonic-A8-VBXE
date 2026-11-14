; =====================================================================
;  obj/objz_lab_wlocznia.asm - M6.8 Labyrinth: $3E wysuwana wlocznia (giant spear) (bank obiektow strefy PB_OBJZ, dolaczany z objz.asm).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_3E_giant_spear 02:8AF6 (kod 02:8AF6-02:8BBB),
;  dane 02:8BBC-02:8C15 (LUT_inc_00_through_07, LUT_dec_07_through_00, LUT_stay_at_00, LUT_stay_at_08,
;  LUT_giant_spear_anim_frames_n_y) - zakres OBJZ_SPANS w tym banku (SMS - OZ_OFF).
;  Procedury:
;   objfunc_3E_spear   (02:8AF6) - funkcja obiektu
;  Wolane: zc_dspr (draw_sprite 00:3581), zc_collide (check_collision_with_sonic 00:3956), damage_sonic (00:35FD), play_sfx (rst $28) -
;  rezydentne / stuby z game/objcom.asm.
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl.
; ---------------------------------------------------------------------
; Bez kolizji z mapa (set 5). Pierwszy tick (b0 flag = 0): x += 12, set 0. Faza z licznika tickow (bity 7-6 g_global_tick_counter,
; okres 256 tickow): 0 - chowanie (klatki 0..7 w tickach 0..7 fazy, potem 8), 1 - schowana (klatka 8), 2 - wysuwanie (7..0, potem 0;
; efekt $1D na poczatku), 3 - wysunieta (klatka 0) - LUT_giant_spear_anim_frames_n_y 02:8BCE: klatka 0 = wlocznia wysunieta, 8 = schowana. Klatka = wpis 8 B tablicy LUT_giant_spear_anim_frames_n_y: 3 pary (kafel, przesuniecie y; kafel >= $80 -
; nie rysowany) rysowane draw_sprite w (x, y + dy) (tmp_00 = x, tmp_02 = y, tmp_04 = 0, tmp_06 = dy), potem (dy kolizji, wysokosc):
; mapa (ix+15/16) = 0 (rysuje sam obiekt), strefa trafienia 1 x wysokosc z przesunieciem (4, dy kolizji) - damage_sonic.
; Efekt $1D, gdy mlodszy bajt licznika tickow = $80 (poczatek fazy 2).
; =====================================================================
; adresy SMS danych (zakres OBJZ_SPANS $8BBC-$8C15; czytane w tym banku pod adresem SMS - OZ_OFF)
LUT_GSP_INC     = $8BBC   ; LUT_inc_00_through_07: 0, 1, ..., 7
LUT_GSP_DEC     = $8BC4   ; LUT_dec_07_through_00: 7, 6, ..., 0
LUT_GSP_STAY0   = $8BCC   ; LUT_stay_at_00: 0
LUT_GSP_STAY8   = $8BCD   ; LUT_stay_at_08: 8
LUT_GSP_FRAMES  = $8BCE   ; LUT_giant_spear_anim_frames_n_y: 9 x 8 B

; ---------------------------------------------------------------------
; objfunc_3E_spear (02:8AF6): wlocznia - patrz opis pliku.
; ---------------------------------------------------------------------
objfunc_3E_spear
	ldy #OB_FLAGS             ; set 5,(ix+24): bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01                  ; bit 0,(ix+24) / jr nz,@already_initialised
	bne gsp_inited
	ldy #OB_X+1               ; (ix+2,3) += $000C
	clc
	lda (zg_obj),y
	adc #$0C
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
gsp_inited                      ; @already_initialised: tmp_00 = x, tmp_02 = y, tmp_04 = 0 (pozycja dla draw_sprite)
	ldy #OB_X+1
	lda (zg_obj),y
	sta tmp_00
	iny
	lda (zg_obj),y
	sta tmp_00+1
	ldy #OB_Y+1
	lda (zg_obj),y
	sta tmp_02
	iny
	lda (zg_obj),y
	sta tmp_02+1
	lda #$00
	sta tmp_04
	sta tmp_04+1
	; faza: ld a,(g_global_tick_counter) / rlca / rlca / and $03 = bity 7-6 licznika (6502: asl -> C = b7, rol -> b0 = b7,
	; rol -> b1 = b7, b0 = b6)
	lda g_global_tick_counter
	asl
	rol
	rol
	and #$03
	bne gsp_not0              ; jr nz,@not_state_00
	lda g_global_tick_counter ; faza 0: e = tick & $3F; e < 8 -> LUT_inc_00_through_07[e], inaczej LUT_stay_at_08 (e = 0)
	and #$3F
	cmp #$08                  ; cp $08 / jr c (Z80 c = 6502 C = 0)
	bcs gsp_stay8
	tax
	lda LUT_GSP_INC-OZ_OFF,x  ; ld a,(hl) z hl = LUT + e
	jmp gsp_frame
gsp_not0                        ; @not_state_00
	cmp #$01
	bne gsp_not1              ; jr nz,@not_state_01
gsp_stay8                       ; faza 1 (i faza 0 po 8 tickach): LUT_stay_at_08, e = 0
	lda LUT_GSP_STAY8-OZ_OFF
	jmp gsp_frame
gsp_not1                        ; @not_state_01
	cmp #$02
	bne gsp_stay0             ; jr nz,@not_state_02
	lda g_global_tick_counter ; faza 2: e = tick & $3F; e < 8 -> LUT_dec_07_through_00[e], inaczej LUT_stay_at_00
	and #$3F
	cmp #$08
	bcs gsp_stay0
	tax
	lda LUT_GSP_DEC-OZ_OFF,x
	jmp gsp_frame
gsp_stay0                       ; @not_state_02 (faza 3; faza 2 po 8 tickach): LUT_stay_at_00, e = 0
	lda LUT_GSP_STAY0-OZ_OFF
gsp_frame                       ; @continue_after_states: hl = LUT_giant_spear_anim_frames_n_y + klatka * 8 (add a,a x 3: 8 bit,
	asl                       ; klatka <= 8 - bez przepelnienia; d = 0)
	asl
	asl
	clc
	adc #<[LUT_GSP_FRAMES-OZ_OFF]
	sta zg_hl
	lda #>[LUT_GSP_FRAMES-OZ_OFF]
	adc #$00
	sta zg_hl+1
	lda #$03                  ; ld b,$03: 3 sprite'y (licznik w zg_bc+1 = B; draw_sprite niszczy tylko zs_*, X)
	sta zg_bc+1
	lda #$00                  ; indeks bajtu we wpisie klatki (hl - poczatek wpisu)
	sta zg_a
gsp_each                        ; @each_potential_sprite
	ldy zg_a
	lda (zg_hl),y             ; ld a,(hl) / inc hl: kafel
	tax
	iny
	lda (zg_hl),y             ; ld e,(hl) / inc hl: przesuniecie y
	iny
	sty zg_a
	cpx #$80                  ; and a / jp m,@dont_draw_this_sprite (bit 7 kafla; 6502 cpx #$80 / bcs)
	bcs gsp_skip
	sta tmp_06                ; ld d,$00 / ld (tmp_06),de: tmp_06 = e, tmp_07 = 0
	lda #$00
	sta tmp_06+1
	txa                       ; call draw_sprite (A = kafel; push/pop hl - wskaznik w zg_hl/zg_a zostaje)
	jsr zc_dspr
gsp_skip                        ; @dont_draw_this_sprite: pop bc / djnz
	dec zg_bc+1
	bne gsp_each
	lda #$00                  ; ld (ix+15),b / ld (ix+16),b: b = 0 po djnz - mapa 0 (bez rysowania mapy)
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy zg_a                  ; hl = wpis + 6: ld d,(hl) / ld e,$04 / ld (tmp_06),de: tmp_06 = $04, tmp_07 = dy kolizji
	lda (zg_hl),y
	tax
	lda #$04
	sta tmp_06
	stx tmp_07
	iny                       ; inc hl / ld a,(hl): wysokosc strefy
	lda (zg_hl),y
	tax
	ldy #OB_W                 ; (ix+13) = $01, (ix+14) = a
	lda #$01
	sta (zg_obj),y
	iny
	txa
	sta (zg_obj),y
	jsr zc_collide            ; check_collision_with_sonic: C = 1 brak trafienia
	bcs gsp_nohit             ; call nc,damage_sonic
	jsr damage_sonic
gsp_nohit
	lda g_global_tick_counter ; ld a,(g_global_tick_counter) / cp $80 / ret nz (mlodszy bajt)
	cmp #$80
	bne gsp_ret
	lda #$1D                  ; ld a,$1D / rst $28 / ret
	jmp play_sfx
gsp_ret
	rts
