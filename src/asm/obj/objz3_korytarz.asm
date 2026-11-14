; =====================================================================
;  obj/objz3_korytarz.asm - M6.9 Scrap Brain: $13 korytarz zmiany poziomu (bank obiektow strefy 2, PB_OBJZ2).
;  M6.10: KOPIA objz2_sbz_korytarz.asm dla banku PB_OBJZ3 (bank 30, Sky Base: SKY2 (640, 480) -> $1A) - etykiety co3_, logika identyczna;
;  LUT_corridor_data 02:9BD9 w banku 30 pod tym samym adresem (OBJZ3_SPANS). Zmiany w obu plikach naraz.
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_13_corridor3 02:9B75-02:9BD8, dane LUT_corridor_data
;  02:9BD9-02:9BE7 (5 wpisow: blok X, blok Y, naglowek poziomu; zakres OBJZ2_SPANS 02:9BD9).
;  Procedury:
;   objfunc_13_corridor3 (02:9B75) - funkcja obiektu $13
;  Niewidoczny obiekt bez kolizji z mapa (set 5,(ix+24)), pole 30 x 96 (ix+13/14). Przy kolizji z Sonikiem (check_collision_with_sonic,
;  przesuniecie (0, 0)) szuka wlasnego bloku (x >> 5, y >> 5 - bajty) w LUT_corridor_data: SBZ2 (125, 26) -> $15, (125, 1) -> $14,
;  $14 (1, 60) -> $18, $15 (1, 2) -> $19, SKY2 (20, 15) -> $1A. Trafienie: g_next_level_override_target = poziom,
;  g_signpost_tickdown_counter = 1, set 4,(iy+6) - przejscie bez wyniku i mapy (game/trans.asm EXIT_TELE). Zawsze mapa sprite'ow = 0.
;  Wola: zc_collide (stub do banku 45).
;  Rejestry Z80: IX = zg_obj, DE = zg_de (E = blok X, D = blok Y), HL = zg_hl.
; =====================================================================
LUT_CORRIDOR3    = $9BD9   ; LUT_corridor_data (5 x 3 B)

objfunc_13_corridor3
	ldy #OB_FLAGS             ; set 5,(ix+24): bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W                 ; ld (ix+13),$1E / ld (ix+14),$60
	lda #$1E
	sta (zg_obj),y
	iny
	lda #$60
	sta (zg_obj),y
	lda #0                    ; ld hl,$0000 / ld (tmp_06),hl
	sta tmp_06
	sta tmp_07
	jsr zc_collide            ; check_collision_with_sonic: C = 1 - brak trafienia
	bcs co3_fin               ; jr c,@finish_tick
	ldy #OB_X+1               ; hl = x (ix+2/3); hl << 3 -> e = h (blok X)
	lda (zg_obj),y
	sta zg_hl
	iny
	lda (zg_obj),y
	ldx #3
co3_xs
	asl zg_hl
	rol
	dex
	bne co3_xs
	sta zg_de                 ; E
	ldy #OB_Y+1               ; hl = y (ix+5/6); hl << 3 -> d = h (blok Y)
	lda (zg_obj),y
	sta zg_hl
	iny
	lda (zg_obj),y
	ldx #3
co3_ys
	asl zg_hl
	rol
	dex
	bne co3_ys
	sta zg_de+1               ; D
	ldx #0                    ; ld hl,LUT_corridor_data / ld b,$05
co3_each                        ; @each_corridor_candidate
	lda LUT_CORRIDOR3-OZ_OFF,x
	cmp zg_de
	bne co3_next
	lda LUT_CORRIDOR3-OZ_OFF+1,x
	cmp zg_de+1
	bne co3_next
	lda LUT_CORRIDOR3-OZ_OFF+2,x ; ld (g_next_level_override_target),a
	sta g_next_level_override_target
	lda #$01                  ; ld (g_signpost_tickdown_counter),a
	sta g_signpost_tickdown_counter
	lda iy_06_lvflag01        ; set 4,(iy+6)
	ora #$10
	sta iy_06_lvflag01
	jmp co3_fin
co3_next                        ; @not_this_corridor: nastepny wpis (3 B)
	inx
	inx
	inx
	cpx #15
	bcc co3_each
co3_fin                         ; @finish_tick: (ix+15/16) = 0 - obiekt niewidoczny
	lda #0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	rts
