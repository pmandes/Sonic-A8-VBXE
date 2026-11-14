; =====================================================================
;  obj/objz_lab_woda.asm - M6.8 Labyrinth: woda - obiekty $40 linia wody, $41 zrodlo babli, $42 maly babel, $20 duzy babel powietrza
;  i spawn_bubble (bank obiektow strefy PB_OBJZ). Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_40_waterline 02:8D48,
;  objfunc_41_air_bubble_spawner 02:8E56, objfunc_42_small_bubble 02:8ECA, spawn_bubble 02:91EB, objfunc_20_air_bubble 02:96F8.
;  Dane banku 2 ROM-u w tym banku pod adresem SMS - OZ_OFF (OZ_SPAN13, 14, 17).
;  Przednie wpisy tablicy sprite'ow: linia wody rysuje 8 sprite'ow od wpisu 0 (g_next_avail_vdp_sprite_ptr chwilowo = g_sprite_table,
;  licznik i wskaznik odtworzone), duzy babel - od g_frontmost_sprite_table_offs (do 12 wpisow); wpisy 0-20 maja Y = $E0 na poczatku
;  ticku (game/step.asm, 00:1E3E), renderer rysuje wpisy 0-11 nad Sonikiem i wpis 20 pod nim (render/sprites.asm: front_objs).
;  spawn_bubble wola tez kod Sonika (tonienie, babel co 256 tickow pod woda) - przez stub sonic_spawn_bubble (game/objcom.asm).
; =====================================================================
LUT_WL_XPOS     = $8E16   ; LUT_waterline_onscreen_x_positions (32 B: 4 grupy po 4 wg tick & 3)
LUT_WL_VY       = $8E36   ; LUT_waterline_y_vel_steps (32 B: kroki Vy falowania, ze znakiem)
LUT_ABS_ANIM    = $8EB6   ; LUT_air_bubble_spawner_anim_xy (6 par dx, dy)
LUT_ABS_CHANCE  = $8EC2   ; LUT_air_bubble_spawner_initial_chance (8 B: b0 = utworz babel)
LUT_SPB_TYPE    = $9257   ; spawn_bubble@LUT_bubble_type_select (16 B: $42 / $20)
SMS_SPRTAB      = $D000   ; g_sprite_table (wartosc wskaznika g_next_avail_vdp_sprite_ptr - adres SMS)

; ---------------------------------------------------------------------
; objfunc_40_waterline (02:8D48): bez kolizji z mapa (set 5). Falowanie: Y (24 bit, ix+4..6) += krok (ix+17) z LUT_waterline_y_vel_steps
; (ze znakiem); co 16 tickow (ix+17) + 1 (do $20 -> 0). g_water_level_y = Y (piksele). d = Y - scroll_y: pozyczka (linia nad
; ekranem) albo d <= 12 -> g_water_level_onscreen_y = $FF (caly ekran pod woda), d > $B4 -> 0 (linia pod ekranem), inaczej d.
; Dla d w 1..$FE: 8 sprite'ow powierzchni (kafle $00 i $02 parami co 8 px) w wierszu d + 9 ekranu, x = LUT[tick & 3][k] + (tick & $0F)
; (bajt), od wpisu 0 tablicy sprite'ow (draw_sprite z tmp_00/02 = kamera).
; ---------------------------------------------------------------------
objfunc_40_waterline
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #17                   ; e = LUT_waterline_y_vel_steps[(ix+17)]; d = a = 0, przy b7 e: dec a / dec d -> $FF
	lda (zg_obj),y
	tax
	lda LUT_WL_VY-OZ_OFF,x
	sta zg_de
	ldx #0
	ora #0
	bpl wln_pos               ; bit 7,e / jr z
	dex
wln_pos                         ; @y_vel_step_was_positive: X = d = a
	stx zg_de+1
	clc                       ; add hl,de (hl = (ix+4), (ix+5)); adc a,(ix+6)
	ldy #OB_Y
	lda (zg_obj),y
	adc zg_de
	sta (zg_obj),y            ; (ix+4) = l
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta (zg_obj),y            ; (ix+5) = h
	sta zg_hl                 ; ld l,h
	iny
	txa                       ; a = d
	adc (zg_obj),y
	sta (zg_obj),y            ; (ix+6) = a
	sta zg_hl+1               ; ld h,(ix+6): hl = Y w pikselach
	lda g_global_tick_counter ; and $0F / jr nz
	and #$0F
	bne wln_nostep
	ldy #17                   ; inc (ix+17); >= $20 -> 0
	lda (zg_obj),y
	clc
	adc #1
	cmp #$20
	bcc wln_st
	lda #0
wln_st
	sta (zg_obj),y
wln_nostep                      ; @end_of_y_vel_step_timer_update
	lda zg_hl                 ; ld (g_water_level_y),hl
	sta g_water_level_y
	lda zg_hl+1
	sta g_water_level_y+1
	sec                       ; and a / sbc hl,de (de = scroll_y): pozyczka -> a = $FF
	lda zg_hl
	sbc g_level_scroll_y_pix_lo
	sta zg_de                 ; ex de,hl: de = Y - scroll_y
	lda zg_hl+1
	sbc g_level_scroll_y_pix_lo+1
	sta zg_de+1
	bcc wln_ff                ; Z80 jr c (pozyczka) = 6502 C = 0
	sec                       ; ld hl,$000C / sbc hl,de (C = 0 po sbc bez pozyczki): bez pozyczki (d <= 12) -> $FF
	lda #$0C
	sbc zg_de
	lda #0
	sbc zg_de+1
	bcs wln_ff                ; Z80 jr nc = 6502 C = 1
	sec                       ; ld hl,$00B4 / xor a / sbc hl,de: pozyczka (d > $B4) -> a = 0
	lda #$B4
	sbc zg_de
	lda #0
	sbc zg_de+1
	bcc wln_zero
	lda zg_de                 ; ld a,e
	jmp wln_set
wln_zero
	lda #0
	beq wln_set               ; zawsze
wln_ff
	lda #$FF
wln_set                         ; @set_onscreen_line_irq_water_level_y
	sta g_water_level_onscreen_y
	cmp #0                    ; and a / ret z
	jeq wln_ret
	cmp #$FF                  ; ret z
	jeq wln_ret
	clc                       ; tmp_06 = a + 9 (h = 0)
	adc #$09
	sta tmp_06
	lda #0
	sta tmp_06+1
	lda g_level_scroll_x_pix_lo ; tmp_00 = scroll_x, tmp_02 = scroll_y
	sta tmp_00
	lda g_level_scroll_x_pix_lo+1
	sta tmp_00+1
	lda g_level_scroll_y_pix_lo
	sta tmp_02
	lda g_level_scroll_y_pix_lo+1
	sta tmp_02+1
	lda g_sprite_count        ; push af (licznik sprite'ow) / push hl (wskaznik)
	pha
	lda g_next_avail_vdp_sprite_ptr
	pha
	lda g_next_avail_vdp_sprite_ptr+1
	pha
	lda #<SMS_SPRTAB          ; g_next_avail_vdp_sprite_ptr = g_sprite_table (wpis 0)
	sta g_next_avail_vdp_sprite_ptr
	lda #>SMS_SPRTAB
	sta g_next_avail_vdp_sprite_ptr+1
	lda g_global_tick_counter ; c = (tick & 3) * 4: hl = LUT_waterline_onscreen_x_positions + c
	and #$03
	asl
	asl
	sta zg_off
	lda #4                    ; b = 4
	sta zg_a
	jsr wln_pre               ; M7.5: y ekranu i przesuniecie x raz (tmp_00, tmp_02, tmp_06 stale w petli)
wln_each                        ; @each_onscreen_sprite
	ldx zg_off
	lda LUT_WL_XPOS-OZ_OFF,x  ; c = (hl), inc hl
	sta zg_bc
	inc zg_off
	lda g_global_tick_counter ; tmp_04 = ((tick & $0F) + c) & $FF (ld h,$00)
	and #$0F
	clc
	adc zg_bc
	sta tmp_04
	lda #0
	sta tmp_04+1
	lda #$00                  ; draw_sprite kafel $00 (M7.5: w linii - wln_put)
	jsr wln_put
	clc                       ; tmp_04 += 8 (16 bit: add hl,de)
	lda tmp_04
	adc #8
	sta tmp_04
	lda tmp_04+1
	adc #0
	sta tmp_04+1
	lda #$02                  ; draw_sprite kafel $02
	jsr wln_put
	dec zg_a                  ; djnz
	bne wln_each
	jsr wln_post              ; M7.5: zd_x / zd_x+1 / zd_r jak po ostatnim draw_sprite
	pla                       ; pop hl / pop af: wskaznik i licznik sprite'ow jak przed linia wody
	sta g_next_avail_vdp_sprite_ptr+1
	pla
	sta g_next_avail_vdp_sprite_ptr
	pla
	sta g_sprite_count
wln_ret
	rts

; ---------------------------------------------------------------------
; M7.5 (docs/plan-m7-ntsc.md - LAB1 woda NTSC; jak sk46_pair zappera SKY3 - implementacja przy wyniku identycznym): 8 x draw_sprite
; linii wody w linii, bez zc_dspr (przelaczanie PORTB na bank 45). Wynik jak draw_sprite (obj/dispatch.asm): y = tmp_02 + tmp_06 -
; scroll_y (raz: stale w petli), x = tmp_00 + tmp_04 - scroll_x (16 bit; tmp_00 - scroll_x raz), te same testy widocznosci, wpis pod
; g_next_avail_vdp_sprite_ptr (inc - zawijanie w stronie), g_sprite_count + 1, grupa na wpis (v_grp_s / v_grp_e / v_ngrp); zd_y / zd_x /
; zd_r po petli jak po ostatnim draw_sprite (wln_post). Ok. 110 zamiast ok. 215 cykli na sprite.
; ---------------------------------------------------------------------
wln_pre                         ; zd_y = y ekranu (draw_sprite), zm_t2 = 1 - y widoczny; zm_t0 / zm_t1 = tmp_00 - scroll_x (16 bit)
	clc
	lda tmp_02
	adc tmp_06
	sta zd_y
	lda tmp_02+1
	adc tmp_06+1
	sta zd_y+1
	sec
	lda zd_y
	sbc g_level_scroll_y_pix_lo
	sta zd_y
	lda zd_y+1
	sbc g_level_scroll_y_pix_lo+1
	sta zd_y+1
	ldx #0                    ; y jak draw_sprite: hi $FF i lo >= $F0 albo hi 0 i lo < $C0
	ora #0
	beq wlp_y0
	cmp #$FF
	bne wlp_y
	lda zd_y
	cmp #$F0
	bcc wlp_y
	bcs wlp_v
wlp_y0
	lda zd_y
	cmp #$C0
	bcs wlp_y
wlp_v
	inx
wlp_y
	stx zm_t2
	sec
	lda tmp_00
	sbc g_level_scroll_x_pix_lo
	sta zm_t0
	lda tmp_00+1
	sbc g_level_scroll_x_pix_lo+1
	sta zm_t1
	rts
wln_put                         ; A = kafel: draw_sprite w (tmp_00 + tmp_04 - scroll_x, y z wln_pre); A i flagi na wyjsciu nieokreslone
	sta zd_r
	clc
	lda tmp_04
	adc zm_t0
	tax                       ; x ekranu lo
	lda tmp_04+1
	adc zm_t1
	bne wlu_ret               ; x hi != 0
	lda zm_t2
	beq wlu_ret               ; y poza ekranem
	txa
	ldx g_next_avail_vdp_sprite_ptr
	sta SPRTAB,x
	inx
	lda zd_y
	sta SPRTAB,x
	inx
	lda zd_r
	sta SPRTAB,x
	inx
	stx g_next_avail_vdp_sprite_ptr
	inc g_sprite_count
	ldx v_ngrp                ; grupa wpisu (jak grp_add)
	cpx #N_GROUPS
	bcs wlu_ret
	lda g_next_avail_vdp_sprite_ptr
	sta v_grp_e,x
	sec
	sbc #3
	sta v_grp_s,x
	inc v_ngrp
wlu_ret
	rts
wln_post                        ; zd_x = (tmp_00 + tmp_04 - scroll_x) lo, zd_x+1 = (tmp_00 + tmp_04) hi - jak po ostatnim draw_sprite
	clc
	lda tmp_00
	adc tmp_04
	sta zd_x
	lda tmp_00+1
	adc tmp_04+1
	sta zd_x+1
	sec
	lda zd_x
	sbc g_level_scroll_x_pix_lo
	sta zd_x
	rts

; ---------------------------------------------------------------------
; objfunc_41_air_bubble_spawner (02:8E56): bez kolizji z mapa. Gdy (ix+18) & $7F = 0: random_A & 7 -> b0 tablicy szans = spawn_bubble
; (ze zrodla: 75% duzy babel $20, 25% maly $42). Sprite $0C w (x + dx, y + dy) z LUT_air_bubble_spawner_anim_xy[(ix+17)],
; (ix+18) + 1, co 8 tickow (ix+17) + 1 (do 6 -> 0).
; ---------------------------------------------------------------------
objfunc_41_bubble_spawner
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #18                   ; ld a,(ix+18) / and $7F / jr nz
	lda (zg_obj),y
	and #$7F
	bne abs_skip
	jsr random_A
	and #$07
	tax
	lda LUT_ABS_CHANCE-OZ_OFF,x
	lsr                       ; bit 0,(hl) -> C
	bcc abs_skip              ; call nz, spawn_bubble
	jsr spawn_bubble
abs_skip                        ; @skip_attempt_spawn_air_bubble: tmp_00 = x, tmp_02 = y
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
	ldy #17                   ; para (dx, dy) = LUT[(ix+17) * 2]; tmp_04 = dx, tmp_06 = dy (d = 0)
	lda (zg_obj),y
	asl
	tax
	lda LUT_ABS_ANIM-OZ_OFF,x
	sta tmp_04
	lda LUT_ABS_ANIM+1-OZ_OFF,x
	sta tmp_06
	lda #0
	sta tmp_04+1
	sta tmp_06+1
	lda #$0C                  ; draw_sprite kafel $0C
	jsr zc_dspr
	ldy #18                   ; inc (ix+18)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	lda g_global_tick_counter ; and $07 / ret nz
	and #$07
	bne abs_ret
	ldy #17                   ; inc (ix+17); >= 6 -> 0
	lda (zg_obj),y
	clc
	adc #1
	cmp #$06
	bcc abs_st
	lda #0
abs_st
	sta (zg_obj),y
abs_ret
	rts

; ---------------------------------------------------------------------
; smb_check_x / smb_check_y: wspolne testy malego i duzego babla (02:8F0E-02:8F55 = 02:9819-02:9860). Usuniecie (typ $FF):
; X (zg_de = x): x <= max(scroll_x - 8, 0) albo x > scroll_x + $100; Y (de = (ix+5..6)): y <= g_water_level_y (babel nad woda),
; y <= scroll_y - 16 (16 bit - zawija przy scroll_y < 16) albo y > scroll_y + $C0. Wyjscie: C = 1 - usuniety (typ $FF, dalszych
; testow nie ma - jp @destroy_this_object), C = 0 - zostaje. tmp_* bez zmian.
; ---------------------------------------------------------------------
smb_check_x
	sec                       ; hl = scroll_x - 8 (xor a / sbc hl,bc): pozyczka -> hl = 0 (ld l,a / ld h,a)
	lda g_level_scroll_x_pix_lo
	sbc #$08
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	sbc #0
	sta zg_hl+1
	bcs smb_nclamp            ; Z80 jr nc = 6502 C = 1
	lda #0
	sta zg_hl
	sta zg_hl+1
smb_nclamp                      ; @dont_clamp_x_left_side_check: and a / sbc hl,de - bez pozyczki (hl >= x) -> usun
	sec
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs smb_kill
	clc                       ; hl = scroll_x + $100 (add hl,bc); and a / sbc hl,de: pozyczka (x > hl) -> usun
	lda g_level_scroll_x_pix_lo+1
	adc #1
	sta zg_hl+1
	sec
	lda g_level_scroll_x_pix_lo
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcc smb_kill
	clc
	rts
smb_check_y
	ldy #OB_Y+1               ; de = y
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	sec                       ; hl = g_water_level_y; and a / sbc hl,de: bez pozyczki (y <= poziom wody) -> usun
	lda g_water_level_y
	sbc zg_de
	lda g_water_level_y+1
	sbc zg_de+1
	bcs smb_kill
	clc                       ; hl = scroll_y + $FFF0 (16 bit); sbc hl,de: bez pozyczki -> usun
	lda g_level_scroll_y_pix_lo
	adc #$F0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #$FF
	sta zg_hl+1
	sec
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs smb_kill
	clc                       ; hl = scroll_y + $C0; sbc hl,de: bez pozyczki (y <= hl) -> zostaje, inaczej usun
	lda g_level_scroll_y_pix_lo
	adc #$C0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #0
	sta zg_hl+1
	sec
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs smb_keep
smb_kill                        ; @destroy_this_object: ld (ix+0),$FF
	lda #$FF
	ldy #OB_TYPE
	sta (zg_obj),y
	sec
	rts
smb_keep                        ; @dont_destroy_this_object
	clc
	rts

; smb_vx: losowy kierunek X babla (02:8EDC = 02:97F6): random_A & $3F < $20 -> Vx = $000020, inaczej $FFFFE0 ((ix+7) = c,
; (ix+8) = b, (ix+9) = d)
smb_vx
	jsr random_A
	and #$3F
	cmp #$20
	bcc smb_right             ; jr c, @selected_move_right
	lda #$E0
	ldx #$FF
	bne smb_setvx             ; zawsze
smb_right
	lda #$20
	ldx #$00
smb_setvx                       ; A = c, X = b = d
	ldy #OB_VX
	sta (zg_obj),y
	txa
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_42_small_bubble (02:8ECA): bez kolizji z mapa, bez mapy sprite'ow (ix+15/16 = 0). Co 16 tickow obiektu ((ix+17) & $0F = 0)
; losowy kierunek X (+-$20 subpikseli); Vy = $FFFFA0. tmp_00 = x przed testem X, tmp_02 = y dopiero po tescie X (przy usunieciu w tescie
; X tmp_02 zostaje z poprzedniego uzycia - jak w oryginale). Sprite $0C rysowany takze po usunieciu, (ix+17) + 1.
; ---------------------------------------------------------------------
objfunc_42_small_bubble
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #0                    ; (ix+15) = (ix+16) = 0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #17                   ; ld a,(ix+17) / and $0F / jr nz
	lda (zg_obj),y
	and #$0F
	bne smb_same
	jsr smb_vx
smb_same                        ; @move_same_x_dir_as_last_time: Vy = $FFFFA0
	ldy #OB_VY
	lda #$A0
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_X+1               ; tmp_00 = x; ex de,hl: de = x
	lda (zg_obj),y
	sta tmp_00
	sta zg_de
	iny
	lda (zg_obj),y
	sta tmp_00+1
	sta zg_de+1
	jsr smb_check_x
	bcs smb_draw
	ldy #OB_Y+1               ; tmp_02 = y (02:8F2C)
	lda (zg_obj),y
	sta tmp_02
	iny
	lda (zg_obj),y
	sta tmp_02+1
	jsr smb_check_y
smb_draw                        ; @dont_destroy_this_object: tmp_04 = tmp_06 = 0, draw_sprite $0C
	lda #0
	sta tmp_04
	sta tmp_04+1
	sta tmp_06
	sta tmp_06+1
	lda #$0C
	jsr zc_dspr
	ldy #17                   ; inc (ix+17)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_20_air_bubble (02:96F8): duzy babel powietrza. Bez kolizji z mapa, bez mapy (ix+15/16 = 0). Rysowanie do przednich wpisow
; tablicy sprite'ow: gdy g_frontmost_sprite_table_offs < $24 - od wpisu offs / 3 (wskaznik i licznik sprite'ow odtworzone): (ix+18) w
; 1..7 (babel wlasnie zebrany, maleje) - maly sprite $0C w (x + 4, y), inaczej kafle $40 i $42 (x, x + 8); offs + 6. Rozmiar 10 x 12.
; Zebrany ((ix+18) > 0): Vy = 0, Vx = 0 (c = b = d = 0), (ix+18) - 1, przy 0 usuniety. Niezebrany: kolizja z Sonikiem (tmp_06 = $0206),
; y - 8 < sonic_y <= y + 6 (16 bit) -> Vy Sonika = 0, licznik skoku = 0, licznik pod woda = 0, set 2 iy_08 (Sonic polyka babel),
; g_sonic_consume_air_bubble_countdown_timer = $20, (ix+18) = $10, efekt $22. Potem Vy = $FFFF98, co 16 tickow obiektu losowy kierunek X,
; testy usuniecia jak maly babel (bez zapisu tmp), (ix+17) + 1.
; ---------------------------------------------------------------------
objfunc_20_air_bubble
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #0                    ; (ix+15) = (ix+16) = 0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda g_sprite_count        ; push af (licznik) / push hl (wskaznik)
	pha
	lda g_next_avail_vdp_sprite_ptr
	pha
	lda g_next_avail_vdp_sprite_ptr+1
	pha
	lda g_frontmost_sprite_table_offs ; cp $24 / jr nc, @skip_drawing_air_bubble
	cmp #$24
	jcs bbl_nodraw
	clc                       ; g_next_avail_vdp_sprite_ptr = g_sprite_table + offs
	adc #<SMS_SPRTAB
	sta g_next_avail_vdp_sprite_ptr
	lda #>SMS_SPRTAB
	adc #0
	sta g_next_avail_vdp_sprite_ptr+1
	ldy #OB_X+1               ; tmp_00 = x, tmp_02 = y, tmp_04 = tmp_06 = 0
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
	lda #0
	sta tmp_04
	sta tmp_04+1
	sta tmp_06
	sta tmp_06+1
	ldy #18                   ; (ix+18) = 0 albo >= 8 -> duzy (2 sprite'y), inaczej maly
	lda (zg_obj),y
	beq bbl_big
	cmp #$08
	bcs bbl_big
	lda #$04                  ; tmp_04 = 4, kafel $0C
	sta tmp_04
	lda #$0C
	bne bbl_small             ; zawsze
bbl_big                         ; @draw_big_bubble_sprites: $40, tmp_04 + 8, $42
	lda #$40
	jsr zc_dspr
	clc
	lda tmp_04
	adc #8
	sta tmp_04
	lda tmp_04+1
	adc #0
	sta tmp_04+1
	lda #$42
bbl_small                       ; @draw_small_bubble_sprite
	jsr zc_dspr
	lda g_frontmost_sprite_table_offs ; offs + 6
	clc
	adc #$06
	sta g_frontmost_sprite_table_offs
bbl_nodraw                      ; @skip_drawing_air_bubble: pop hl / pop af
	pla
	sta g_next_avail_vdp_sprite_ptr+1
	pla
	sta g_next_avail_vdp_sprite_ptr
	pla
	sta g_sprite_count
	ldy #OB_W                 ; (ix+13) = $0A, (ix+14) = $0C
	lda #$0A
	sta (zg_obj),y
	iny
	lda #$0C
	sta (zg_obj),y
	ldy #18                   ; zebrany?
	lda (zg_obj),y
	beq bbl_notcol
	lda #0                    ; c = b = d = 0; Vy = 0
	ldy #OB_VY
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #18                   ; dec (ix+18); jp nz, @set_x_vel
	lda (zg_obj),y
	sec
	sbc #1
	sta (zg_obj),y
	bne bbl_vx0
	lda #$FF                  ; ld (ix+0),$FF
	ldy #OB_TYPE
	sta (zg_obj),y
bbl_vx0                         ; @set_x_vel z c = b = d = 0
	lda #0
	tax
	jsr smb_setvx
	jmp bbl_tests
bbl_notcol                      ; @not_collected_yet: kolizja z Sonikiem (tmp_06 = $0206)
	lda #$06
	sta tmp_06
	lda #$02
	sta tmp_06+1
	jsr zc_collide
	jcs bbl_cont              ; jr c: brak kolizji
	clc                       ; hl = y + $FFF8 (add hl,de); and a / sbc hl,bc (bc = sonic_y): bez pozyczki -> dalej (nie zebrany)
	ldy #OB_Y+1
	lda (zg_obj),y
	adc #$F8
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #$FF
	sta zg_hl+1
	sec
	lda zg_hl
	sbc sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcs bbl_cont
	clc                       ; hl = y + 6; sbc hl,bc: pozyczka (y + 6 < sonic_y) -> dalej
	ldy #OB_Y+1
	lda (zg_obj),y
	adc #$06
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	sec
	lda zg_hl
	sbc sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcc bbl_cont
	ldy #18                   ; ld a,(ix+18) / and a / jr nz (tu zawsze 0)
	lda (zg_obj),y
	bne bbl_cont
	lda #0                    ; Vy Sonika (24 bit) = 0, licznik skoku = 0, licznik pod woda = 0
	sta sonic_vel_y_sub
	sta sonic_vel_y
	sta sonic_vel_y_hi
	sta g_sonic_jump_countdown_timer
	sta g_sonic_underwater_countup_timer
	sta g_sonic_underwater_countup_timer+1
	lda iy_08_lvflag03        ; set 2,(iy+8): Sonic polyka babel
	ora #$04
	sta iy_08_lvflag03
	lda #$20
	sta g_sonic_consume_air_bubble_countdown_timer
	lda #$10                  ; (ix+18) = $10
	ldy #18
	sta (zg_obj),y
	lda #$22                  ; rst $28: efekt $22
	jsr play_sfx
bbl_cont                        ; @continue_from_non_collection: Vy = $FFFF98
	ldy #OB_VY
	lda #$98
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #17                   ; co 16 tickow obiektu losowy kierunek X
	lda (zg_obj),y
	and #$0F
	bne bbl_tests
	jsr smb_vx
bbl_tests                       ; @move_same_x_dir_as_last_time: de = x, testy usuniecia (bez zapisu tmp)
	ldy #OB_X+1
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	jsr smb_check_x
	bcs bbl_inc
	jsr smb_check_y
bbl_inc                         ; @dont_destroy_this_object: inc (ix+17)
	ldy #17
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; spawn_bubble (02:91EB): nowy babel w pierwszym wolnym slocie (spawn_object; brak - nic). Typ $42 (maly); ze zrodla babli ($41) typ
; z tablicy LUT_bubble_type_select[random_A & $0F] (75% $20). Pozycja: x = x obiektu wolajacego (ix+2..3) + (random_A & $0F),
; (ix+4) = 0, y = y obiektu (ix+5..6) + (random_A & $0F); (ix+1) = 0, (ix+17) = (ix+18) = (ix+24) = 0, Vx = 0 (ix+7..9). Reszta pol slotu
; zostaje (oryginal ich nie czysci). Wejscie: zg_obj = obiekt wolajacy (Sonic przez sonic_spawn_bubble, zrodlo $41, Jaws $3C).
; Konczy sie rts (Jaws wola ja przez jmp).
; ---------------------------------------------------------------------
spawn_bubble
	jsr spawn_object          ; zg_ptr = nowy slot; C = 1 - brak (ret c)
	bcc spb_ok
	rts
spb_ok
	lda #$42                  ; c = $42
	sta zg_bc
	ldy #OB_TYPE              ; ld a,(ix+0) / cp $41
	lda (zg_obj),y
	cmp #$41
	bne spb_n41
	jsr random_A              ; push hl ... pop hl (random_A nie zmienia zg_ptr)
	and #$0F
	tax
	lda LUT_SPB_TYPE-OZ_OFF,x
	sta zg_bc
spb_n41                         ; @not_type_41: de = x, bc = y obiektu wolajacego (y w zg_hl - c typu zajmuje zg_bc)
	ldy #OB_X+1
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	ldy #OB_Y+1
	lda (zg_obj),y
	sta zg_hl
	iny
	lda (zg_obj),y
	sta zg_hl+1
	ldy #OB_TYPE              ; push ix / push hl / pop ix: (ix+0) = typ, (ix+1) = 0
	lda zg_bc
	sta (zg_ptr),y
	iny
	lda #0
	sta (zg_ptr),y
	jsr random_A              ; x = (random_A & $0F) + de
	and #$0F
	clc
	adc zg_de
	ldy #OB_X+1
	sta (zg_ptr),y
	lda zg_de+1
	adc #0
	iny
	sta (zg_ptr),y
	lda #0                    ; (ix+4) = 0
	iny
	sta (zg_ptr),y
	jsr random_A              ; y = (random_A & $0F) + bc
	and #$0F
	clc
	adc zg_hl
	ldy #OB_Y+1
	sta (zg_ptr),y
	lda zg_hl+1
	adc #0
	iny
	sta (zg_ptr),y
	lda #0                    ; (ix+17) = (ix+18) = (ix+24) = 0, (ix+7..9) = 0
	ldy #17
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	ldy #OB_FLAGS
	sta (zg_ptr),y
	ldy #OB_VX
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	rts
