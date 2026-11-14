; =====================================================================
;  obj/objz_lab_gargulec.asm - M6.8 Labyrinth: $3F kula ognia gargulca (bank obiektow strefy PB_OBJZ, bank 11).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_3F_fireball_gargoyle 02:8C16-02:8D38,
;  dane SPRTAB_gargoyle_fireball_left 02:8D39, SPRTAB_gargoyle_fireball_right 02:8D41 (zakres OBJZ_SPANS 02:8D39-02:8D47).
;  Procedury:
;   objfunc_3F_gargoyle  (02:8C16) - funkcja obiektu $3F
;  Gargulec jest czescia grafiki tla (kafle poziomu); obiekt $3F to sama kula ognia - jeden obiekt, bez tworzenia
;  innych obiektow w locie. Kula po wylocie poza ekran albo po uderzeniu w sciane / podloge wraca na pozycje startowa
;  i czeka 150 tickow ($96) niewidoczna, potem leci znowu (efekt $18 w chwili wylotu).
;  Pola rekordu: (ix+17) licznik czekania, (ix+18/19) x startowe, (ix+20/21) y startowe, (ix+24) b0 = zainicjowany,
;  b1 = leci w prawo (blok pod punktem startu <> $52), b6/b7 = kolizja z mapa (z obj_motion poprzedniego ticku).
;  Wola: obj_tile_ptr, play_sfx, damage_sonic (rezydentne), zc_collide (stub do banku 45).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl.
; =====================================================================
SPR_GARG_L      = $8D39   ; SPRTAB_gargoyle_fireball_left (1 kafel $2E)
SPR_GARG_R      = $8D41   ; SPRTAB_gargoyle_fireball_right (1 kafel $30)

; ---------------------------------------------------------------------
; objfunc_3F_fireball_gargoyle (02:8C16): kula ognia gargulca. Kolizje z mapa wlaczone (res 5), 4 x 10.
; Pierwszy tick (b0 = 0): x += $0A, y += 8 (16 bit, subpiksele bez zmian), (ix+18/19) = x, (ix+20/21) = y,
; (ix+17) = $96, set 0; blok ukladu pod (x, y) (get_obj_level_tile_ptr_in_ram, BC = DE = 0) <> $52 -> set 1 (w prawo).
; Licznik (ix+17) <> 0: - 1; gdy dalej <> 0 (i przy kazdym ticku czekania) mapa 0 i Vx = 0 (@ensure_spriteless_and_unmoving);
; gdy wlasnie doszedl do 0 - efekt $18 i lot. Lot (licznik 0): Vx = -1 px/tick ($FFFF00, mapa _left) albo +1 ($000100,
; mapa _right), Vy = 0; kolizja z mapa w poprzednim ticku (b6 albo b7) -> powrot; trafienie Sonica (przesuniecie (2, 4))
; - damage_sonic; x poza (kamera X - 16, kamera X + $110] albo y poza (kamera Y - 16, kamera Y + $D0] -> powrot
; (@reset_fireball: x, y = startowe, (ix+17) = $96, mapa 0, Vx = 0).
; ---------------------------------------------------------------------
objfunc_3F_gargoyle
	ldy #OB_FLAGS             ; res 5,(ix+24): kolizje z mapa wlaczone
	lda (zg_obj),y
	and #$DF
	sta (zg_obj),y
	ldy #OB_W                 ; (ix+13) = 4, (ix+14) = $0A
	lda #$04
	sta (zg_obj),y
	iny
	lda #$0A
	sta (zg_obj),y
	ldy #OB_FLAGS             ; bit 0,(ix+24) / jr nz @already_initialised
	lda (zg_obj),y
	and #$01
	jne grg_inited
	ldy #OB_X+1               ; hl = x + $000A -> (ix+2/3) i (ix+18/19) (C z adc mlodszego bajtu przez ldy/sta)
	clc
	lda (zg_obj),y
	adc #$0A
	sta (zg_obj),y
	ldy #18
	sta (zg_obj),y
	ldy #OB_X+2
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	ldy #19
	sta (zg_obj),y
	ldy #OB_Y+1               ; hl = y + $0008 -> (ix+5/6) i (ix+20/21)
	clc
	lda (zg_obj),y
	adc #$08
	sta (zg_obj),y
	ldy #20
	sta (zg_obj),y
	ldy #OB_Y+2
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	ldy #21
	sta (zg_obj),y
	ldy #17                   ; (ix+17) = $96
	lda #$96
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
	lda #0                    ; bc = de = 0: get_obj_level_tile_ptr_in_ram - blok pod (x, y)
	sta zg_bc
	sta zg_bc+1
	sta zg_de
	sta zg_de+1
	jsr obj_tile_ptr
	bcs grg_rom
	ldy #0                    ; ld a,(hl) / cp $52 / jr z @already_initialised: blok $52 - kula leci w lewo
	lda (zg_ptr),y
	cmp #$52
	beq grg_inited
	bne grg_setr              ; zawsze
grg_rom                         ; adres SMS < $C000 (ROM - port go nie ma): jak blok inny niz $52 (v_rom_reads + 1,
	inc v_rom_reads           ; precedens: reposition_monitor_on_init); punkt startu kuli lezy zawsze w ukladzie
grg_setr
	ldy #OB_FLAGS             ; set 1,(ix+24): w prawo
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
grg_inited                      ; @already_initialised
	ldy #17                   ; ld a,(ix+17) / and a / jr z @timer_expired
	lda (zg_obj),y
	beq grg_expired
	sec                       ; dec (ix+17) / jr z @timer_just_expired_now
	sbc #1
	sta (zg_obj),y
	beq grg_justexp
grg_hide                        ; @ensure_spriteless_and_unmoving: mapa 0, Vx = 0 (Vy bez zmian)
	lda #0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_VX
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	rts
grg_justexp                     ; @timer_just_expired_now: rst $28 z A = $18 (dalej xor a - A po efekcie bez znaczenia)
	lda #$18
	jsr play_sfx
grg_expired                     ; @timer_expired: bit 1,(ix+24) / jr nz @is_facing_right
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02
	bne grg_right
	ldy #OB_VX                ; w lewo: Vx = $FFFF00, mapa SPRTAB_gargoyle_fireball_left
	lda #$00
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #<SPR_GARG_L
	ldx #>SPR_GARG_L
	bne grg_dir               ; zawsze (starszy bajt $8D)
grg_right                       ; @is_facing_right: Vx = $000100 (a = 0), mapa SPRTAB_gargoyle_fireball_right
	ldy #OB_VX
	lda #$00
	sta (zg_obj),y
	lda #$01
	iny
	sta (zg_obj),y
	lda #$00
	iny
	sta (zg_obj),y
	lda #<SPR_GARG_R
	ldx #>SPR_GARG_R
grg_dir                         ; @sprtab_and_dir_selected: (ix+15/16) = mapa, Vy = 0
	ldy #OB_SPRITE
	sta (zg_obj),y
	txa
	iny
	sta (zg_obj),y
	lda #0
	ldy #OB_VY
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_FLAGS             ; bit 6,(ix+24) / jr nz, bit 7,(ix+24) / jr nz -> @reset_fireball
	lda (zg_obj),y
	and #$C0
	jne grg_reset
	lda #$02                  ; ld hl,$0402 / ld (tmp_06),hl: tmp_06 = 2, tmp_07 = 4
	sta tmp_06
	lda #$04
	sta tmp_07
	jsr zc_collide            ; check_collision_with_sonic / call nc,damage_sonic
	bcs grg_nohit
	jsr damage_sonic
grg_nohit
	ldy #OB_X+1               ; de = x (16 bit)
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	clc                       ; hl = kamera X + $FFF0 (16 bit z zawinieciem)
	lda g_level_scroll_x_pix_lo
	adc #<$FFF0
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #>$FFF0
	sta zg_hl+1
	sec                       ; and a / sbc hl,de / jr nc: hl >= x (bez pozyczki; 6502 C = 1) -> @reset_fireball
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs grg_reset
	clc                       ; hl = kamera X + $0110
	lda g_level_scroll_x_pix_lo
	adc #<$0110
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #>$0110
	sta zg_hl+1
	sec                       ; sbc hl,de / jr c: hl < x (pozyczka; 6502 C = 0) -> @reset_fireball
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcc grg_reset
	ldy #OB_Y+1               ; de = y (16 bit)
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	clc                       ; hl = kamera Y + $FFF0
	lda g_level_scroll_y_pix_lo
	adc #<$FFF0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #>$FFF0
	sta zg_hl+1
	sec                       ; jr nc -> @reset_fireball
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs grg_reset
	clc                       ; hl = kamera Y + $00D0
	lda g_level_scroll_y_pix_lo
	adc #<$00D0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #>$00D0
	sta zg_hl+1
	sec                       ; jr c -> @reset_fireball, inaczej ret (kula leci dalej)
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcc grg_reset
	rts
grg_reset                       ; @reset_fireball: x = (ix+18/19), y = (ix+20/21), (ix+17) = $96, dalej mapa 0 i Vx = 0
	ldy #18
	lda (zg_obj),y
	ldy #OB_X+1
	sta (zg_obj),y
	ldy #19
	lda (zg_obj),y
	ldy #OB_X+2
	sta (zg_obj),y
	ldy #20
	lda (zg_obj),y
	ldy #OB_Y+1
	sta (zg_obj),y
	ldy #21
	lda (zg_obj),y
	ldy #OB_Y+2
	sta (zg_obj),y
	ldy #17
	lda #$96
	sta (zg_obj),y
	jmp grg_hide              ; jp @ensure_spriteless_and_unmoving
