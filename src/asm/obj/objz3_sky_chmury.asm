; =====================================================================
;  obj/objz3_sky_chmury.asm - M6.10 Sky Base (SKY2): $30 chmura, $31 smiglo, $32 Bomb (badnik), $33 armata, $34 pocisk armaty,
;  M6.10: kod w trzecim banku obiektow strefy PB_OBJZ3 (bank 30, tylko Sky Base; obj/objz3.asm) - dane banku 2 ROM-u pod adresem
;  SMS - OZ_OFF jak w PB_OBJZ2 (zakresy OBJZ3_SPANS w tools/extract_sms.py, stale OZ3_* w objdata.inc).
;  $37 obrotowe dzialo, $39 sciana kolcow (bank obiektow strefy 3 PB_OBJZ3, bank 30, okno $4000-$7FFF; kod w luce banku 30).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny):
;   objfunc_30_moving_cloud          02:A9C7-02:AA62, dane SPRTAB_moving_cloud 02:AA63-02:AA69 (7 B)
;   objfunc_31_SKY2_propeller        02:AA6A-02:AB00, dane PTRTAB_SKY2_propeller_sprites_xyn 02:AB01 (4 slowa - adresy SMS),
;                                    LUT_SKY2_propeller_sprites_00..03 02:AB09-02:AB20 (po 6 B: 2 x (dx, dy, kafel))
;   objfunc_32_badnik_bomb           02:AB21-02:AC95, dane 02:ACF1-02:AD6B (sekwencje animacji 02:ACF1-02:AD0A,
;                                    SPRTAB_badnik_bomb_normal 02:AD0B - 4 klatki po 18 B, SPRTAB_badnik_bomb_exploding 02:AD53);
;                                    init_fireball_object 02:AC96-02:ACF0 - w porcie w banku 45 (obj/objs_c.asm), tu przez stub zc_initfb
;   objfunc_33_SKY2_cannon           02:AD6C-02:ADFC, dane LUT_SKY2_cannon_shot_puff 02:ADFD-02:AE03, SPRTAB_SKY2_cannon_shot_puff
;                                    02:AE04-02:AE34 (3 klatki po 18 B, ostatnia konczy sie na 02:AE34)
;   objfunc_34_SKY2_cannon_shell     02:AE35-02:AE80, dane SPRTAB_SKY2_cannon_shell 02:AE81-02:AE87
;   objfunc_37_SKY2_turning_gun      02:B16C-02:B226, dane LUT_SKY2_turning_gun_sprite_info 02:B227-02:B266 (8 kierunkow x 2 x
;                                    (dx, dy, kafel, 0)), LUT_SKY2_turning_gun_bullet_directions 02:B267-02:B296 (8 x (Vx, Vy, dx, dy))
;   objfunc_39_SKY2_spike_wall_right 02:B398-02:B45A, dane SPRTAB_SKY2_spike_wall_right 02:B45B-02:B46C (3 wiersze po 6 B)
;  Dane banku 2 ROM-u leza w tym banku pod adresem SMS - OZ_OFF (zakresy dla OBJZ3_SPANS: $AA63-$AA69, $AB01-$AB20, $ACF1-$AD6B,
;  $ADFD-$AE34, $AE81-$AE87, $B227-$B296, $B45B-$B46C); kod czyta je przez "ETYKIETA-OZ_OFF", a do rekordu (mapa ix+15/16), do
;  zd_map (zc_dss) i do zg_de (baza map oz3_dfa) trafiaja adresy SMS ($Axxx / $Bxxx) - objz_mapcopy kopiuje mape z tego banku.
;  Procedury (wejscia z oz3_tab, obj/objz3.asm):
;   objfunc_30_cloud          (02:A9C7) - $30 chmura (rysowana w przednich wpisach tablicy sprite'ow, plynie w lewo)
;   objfunc_31_sky2_propeller (02:AA6A) - $31 smiglo (2 sprite'y draw_sprite, kolizja -> damage_sonic)
;   objfunc_32_bomb           (02:AB21) - $32 Bomb (chodzi, zapalnik przy Sonicu, 4 kule ognia $0D)
;   objfunc_33_sky2_cannon    (02:AD6C) - $33 armata (co 256 tickow pocisk $34, dym)
;   objfunc_34_cannon_shell   (02:AE35) - $34 pocisk armaty (leci w prawo, znika za prawa krawedzia)
;   objfunc_37_turning_gun    (02:B16C) - $37 obrotowe dzialo (8 kierunkow, strzal co 26 tickow - sky_shoot_fireball)
;   objfunc_39_spike_wall     (02:B398) - $39 sciana kolcow (jedzie w prawo, gdy Sonic na jej wysokosci)
;  Obiekty tworzone w locie: $0D kule ognia (Bomb - spawn_object + zc_initfb; dzialo - sky_shoot_fireball), $34 (armata).
;  Wola: kod tego banku - oz3_dfa (do_framed_animation 01:7C41, obj/objz3.asm: zg_bc = sekwencja - adres okna, zg_de = baza map -
;  adres SMS), sky_shoot_fireball (shoot_straight_fireball 02:B5C2, obj/objz3_sky_dziala.asm); kod rezydentny $8000+ (game/objcom.asm):
;  damage_sonic (00:35FD), spawn_object (01:7C7B: zg_ptr = nowy slot, C = 1 brak), random_A (00:0625), play_sfx (rst $28); stuby do
;  banku 45 (game/objcom.asm): zc_collide (check_collision_with_sonic 00:3956, C = 1 - brak trafienia), zc_dspr (draw_sprite 00:3581,
;  A = kafel, tmp_00..tmp_07), zc_dss (draw_sprite_string 00:350F: zd_map = adres SMS mapy, zd_x / zd_y = pozycja ekranowa),
;  zc_initfb (init_fireball_object 02:AC96 -> obj/objs_c.asm: zg_ptr = slot kuli, zg_obj = obiekt zrodlowy, zg_de / zg_bc = DE / BC).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl, HL nowego obiektu (spawn_object) = zg_ptr; zg_off / zg_a - indeksy
;  i liczniki petli (draw_sprite ich nie zmienia: uzywa zd_*, X). Przeniesienie: Z80 C = 1 po sbc (pozyczka) <=> 6502 C = 0.
;  Pola rekordu:
;   $30: tylko pozycja / Vx (mapa 0 - rysuje sama funkcja); y rysowane = y + kolysanie kamery (g_y_oscillate_*).
;   $31: (ix+17) klatka smigla 0/2/4/6 (indeks slowa PTRTAB), (ix+24) b0 = zainicjowany (x + 15, y - 6), b5.
;   $32: (ix+17) licznik stanu (+1 co 64 ticki globalne: 0..$45 chodzenie, $64.. wybuch), (ix+22/23) animacja (oz3_dfa); bez set 5.
;   $33: (ix+17) licznik cyklu (start random_A, +1 co tick; strzal przy $64), (ix+18) czas dymu ($18..0), (ix+22/23) animacja dymu, b0.
;   $34: brak pol wlasnych (Vx staly co tick).
;   $37: (ix+17) kierunek 0..7 (start random_A & 7, +1 co 64 ticki), (ix+18) licznik strzalu 0..$19, b0.
;   $39: (ix+17/18) x startowe (piksele lo, hi), b0.
; =====================================================================
; adresy SMS danych (czytane w tym banku pod adresem SMS - OZ_OFF)
SK30_SPRTAB     = $D000   ; g_sprite_table (adres SMS - wartosc wskaznika g_next_avail_vdp_sprite_ptr; wpis = 3 B: x, y, kafel)
SK30_SPR        = $AA63   ; SPRTAB_moving_cloud: $40 $42 $44 $46 $FF $FF (jeden wiersz, 4 kafle), drugi wiersz od $AA69 = $FF - koniec
SK31_PTR        = $AB01   ; PTRTAB_SKY2_propeller_sprites_xyn: slowa $AB09, $AB0F, $AB15, $AB1B (adresy SMS klatek po 6 B)
SK32_SEQ_LW     = $ACF1   ; LUT_badnik_bomb_anim_left_walking: (0, $20), (1, $20), $FF - klatka, czas
SK32_SEQ_LS     = $ACF6   ; LUT_badnik_bomb_anim_left_standing: (1, $20), $FF
SK32_SEQ_RW     = $ACF9   ; LUT_badnik_bomb_anim_right_walking: (2, $20), (3, $20), $FF
SK32_SEQ_RS     = $ACFE   ; LUT_badnik_bomb_anim_right_standing: (3, $20), $FF
SK32_SEQ_FL     = $AD01   ; LUT_badnik_bomb_anim_exploding_flashing: (1, 2), (4, 2), $FF (dalsze (3, 2), (5, 2), $FF - nieosiagalne)
SK32_SPR_N      = $AD0B   ; SPRTAB_badnik_bomb_normal: baza map (klatka = 18 B; klatki 0..3 = $AD0B, $AD1D, $AD2F, $AD41, 4 = $AD53)
SK32_SPR_X      = $AD53   ; SPRTAB_badnik_bomb_exploding: $12 $14 (wiersz 1), wiersz 2 od $AD59 = $FF - koniec
SK33_SEQ        = $ADFD   ; LUT_SKY2_cannon_shot_puff: (0, 8), (1, 8), (2, 8), $FF
SK33_SPR        = $AE04   ; SPRTAB_SKY2_cannon_shot_puff: 3 klatki ($AE04, $AE16, $AE28): wiersz 1 = $FE (pusty), wiersz 2 = 2 kafle
SK34_SPR        = $AE81   ; SPRTAB_SKY2_cannon_shell: $02 $04 (wiersz 1), wiersz 2 od $AE87 = $FF - koniec
SK37_SPR        = $B227   ; LUT_SKY2_turning_gun_sprite_info: kierunek * 8: 2 x (dx, dy - bajty ze znakiem, kafel - $FF = brak, 0)
SK37_DIR        = $B267   ; LUT_SKY2_turning_gun_bullet_directions: kierunek * 6: Vx, Vy (slowa: subpiksel, piksel lo), dx, dy (bajty ze znakiem)
SK39_SPR        = $B45B   ; SPRTAB_SKY2_spike_wall_right: 3 wiersze $16 $18 (kolce w pionie)

; ---------------------------------------------------------------------
; objfunc_30_moving_cloud (02:A9C7): chmura SKY2 (6 sztuk na poziomie, granice aktywacji +-2048 px - zawsze aktywne). Bez kolizji
; z mapa (set 5), bez kolizji z Soniciem, mapa (ix+15/16) = 0 - obj_draw nic nie rysuje. Rysowanie w PRZEDNICH wpisach tablicy
; sprite'ow (00:1E3E zeruje Y wpisow 0-20 na poczatku ticku): licznik sprite'ow i wskaznik zachowane na stosie (push af / push hl);
; gdy g_frontmost_sprite_table_offs < $24 (najwyzej 3 chmury po 4 wpisy = $0C B): wskaznik = g_sprite_table + offs, mapa
; SPRTAB_moving_cloud (draw_sprite_string) w (x - scroll_x, y + kolysanie - scroll_y), offs + $0C. Potem licznik i wskaznik
; odtworzone (wpisy chmury nie licza sie do g_sprite_count). y rysowane = ((ix+4..6) + (g_y_oscillate_sub, _pix, _pix_hi)) >> 8
; (24 bit, jak platforma $38). Za lewa krawedzia (x < scroll_x - 32, 16 bit - przy scroll_x < 32 granica zawija i warunek jest zawsze
; spelniony): x = scroll_x + $01B4 + 2 * random_A (0..$1FE). Co tick Vx = $FFFD00 (-3 px/tick), mapa = 0.
; ---------------------------------------------------------------------
objfunc_30_cloud
	ldy #OB_FLAGS             ; 02:A9C7: set 5,(ix+24) - bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda g_sprite_count        ; 02:A9CB: ld a,(iy+g_sprite_count) / ld hl,(g_next_avail_vdp_sprite_ptr) / push af / push hl
	pha
	lda g_next_avail_vdp_sprite_ptr
	pha
	lda g_next_avail_vdp_sprite_ptr+1
	pha
	lda g_frontmost_sprite_table_offs ; 02:A9D3: ld a,(g_frontmost_sprite_table_offs) / cp $24 / jr nc,@skip_drawing_cloud
	cmp #$24                  ; (6502: C = 1 gdy offs >= $24 - przednie wpisy 0..11 zajete)
	jcs sk30_nodraw
	clc                       ; 02:A9DA: ld e,a / ld d,$00 / ld hl,g_sprite_table / add hl,de / ld (g_next_avail_vdp_sprite_ptr),hl
	adc #<SK30_SPRTAB
	sta g_next_avail_vdp_sprite_ptr
	lda #>SK30_SPRTAB
	adc #0
	sta g_next_avail_vdp_sprite_ptr+1
	clc                       ; 02:A9E4: c = (g_y_oscillate_pix_hi), de = (g_y_oscillate_sub) (e = sub $D2A1, d = piksel lo $D2A2);
	ldy #OB_Y                 ; 02:A9EC: l = (ix+4), h = (ix+5), a = (ix+6) / add hl,de / adc a,c - y (24 bit) + kolysanie
	lda (zg_obj),y
	adc g_y_oscillate_sub     ; l (subpiksel) - tylko przeniesienie
	iny
	lda (zg_obj),y
	adc g_y_oscillate_pix
	sta zg_hl                 ; 02:A9F7: ld l,h
	iny
	lda (zg_obj),y
	adc g_y_oscillate_pix+1   ; g_y_oscillate_pix_hi ($D2A3)
	sta zg_hl+1               ; 02:A9F8: ld h,a - hl = y w pikselach (16 bit)
	sec                       ; 02:A9F9: ld bc,(g_level_scroll_y_pix_lo) / and a / sbc hl,bc / ex de,hl - de = y ekranowe
	lda zg_hl
	sbc g_level_scroll_y_pix_lo
	sta zd_y
	lda zg_hl+1
	sbc g_level_scroll_y_pix_lo+1
	sta zd_y+1
	sec                       ; 02:AA01: l = (ix+2), h = (ix+3); ld bc,(g_level_scroll_x_pix_lo) / and a / sbc hl,bc - x ekranowe
	ldy #OB_X+1
	lda (zg_obj),y
	sbc g_level_scroll_x_pix_lo
	sta zd_x
	iny
	lda (zg_obj),y
	sbc g_level_scroll_x_pix_lo+1
	sta zd_x+1
	lda #<SK30_SPR            ; 02:AA0E: ld bc,SPRTAB_moving_cloud / call draw_sprite_string (zc_dss: mapa z tego banku; tmp_06 = x
	sta zd_map                ; ekranowe - jak oryginal; wpisy od g_sprite_table + offs, g_sprite_count + liczba sprite'ow)
	lda #>SK30_SPR
	sta zd_map+1
	jsr zc_dss
	lda g_frontmost_sprite_table_offs ; 02:AA14: ld a,(g_frontmost_sprite_table_offs) / add a,$0C / ld (...),a - 4 wpisy dalej
	clc
	adc #$0C
	sta g_frontmost_sprite_table_offs
sk30_nodraw                     ; 02:AA1C @skip_drawing_cloud: pop hl / pop af / ld (g_next_avail_vdp_sprite_ptr),hl / ld (iy+g_sprite_count),a
	pla
	sta g_next_avail_vdp_sprite_ptr+1
	pla
	sta g_next_avail_vdp_sprite_ptr
	pla
	sta g_sprite_count
	clc                       ; 02:AA24: ld hl,(g_level_scroll_x_pix_lo) / ld de,$FFE0 / add hl,de / ex de,hl - de = scroll_x - 32
	lda g_level_scroll_x_pix_lo ; (16 bit z zawinieciem)
	adc #<$FFE0
	sta zg_de
	lda g_level_scroll_x_pix_lo+1
	adc #>$FFE0
	sta zg_de+1
	ldy #OB_X+1               ; 02:AA2C: l = (ix+2), h = (ix+3) / and a / sbc hl,de / jr nc,@skip_setting_new_position
	lda (zg_obj),y            ; (6502: C = 1 - bez pozyczki, x >= scroll_x - 32 - chmura zostaje)
	cmp zg_de
	iny
	lda (zg_obj),y
	sbc zg_de+1
	bcs sk30_keep
	jsr random_A              ; 02:AA37: call random_A / ld b,$00 / add a,a / ld c,a / rl b - bc = 2 * random_A (9 bit)
	asl
	sta zg_bc
	lda #0
	rol
	sta zg_bc+1
	clc                       ; 02:AA40: ld hl,(g_level_scroll_x_pix_lo) / ld de,$01B4 / add hl,de - hl = scroll_x + $01B4
	lda g_level_scroll_x_pix_lo
	adc #<$01B4
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #>$01B4
	sta zg_hl+1
	clc                       ; 02:AA47: add hl,bc / ld (ix+2),l / ld (ix+3),h - nowe x za prawa krawedzia (subpiksel bez zmian)
	lda zg_hl
	adc zg_bc
	ldy #OB_X+1
	sta (zg_obj),y
	lda zg_hl+1
	adc zg_bc+1
	iny
	sta (zg_obj),y
sk30_keep                       ; 02:AA4E @skip_setting_new_position: (ix+7) = 0, (ix+8) = $FD, (ix+9) = $FF - Vx = $FFFD00 (-3 px/tick)
	ldy #OB_VX
	lda #$00
	sta (zg_obj),y
	iny
	lda #$FD
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	lda #$00                  ; 02:AA5A: (ix+15) = (ix+16) = 0 - bez mapy (obj_draw nie rysuje) / ret
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_31_SKY2_propeller (02:AA6A): smiglo SKY2 (jedno na poziomie, (224, 608)). Bez kolizji z mapa (set 5), rozmiar 5 x $14 co tick.
; Pierwszy tick (b0 = 0): x (ix+2/3) + $000F, y (ix+5/6) + $FFFA (- 6), set 0. Co tick: tmp_00 = x, tmp_02 = y; klatka = slowo
; PTRTAB_SKY2_propeller_sprites_xyn[(ix+17)] (adres SMS 6 B: 2 x (dx, dy, kafel)); dla kazdego sprite'a tmp_04 = dx, tmp_06 = dy
; (bez znaku, starszy bajt 0 - zapisywane takze dla pominietego sprite'a), kafel < $80 -> draw_sprite (kafel $FF - pominiety, klatka 3).
; Kolizja (przesuniecie (2, 2): tmp_06 = $0202) -> damage_sonic. Mapa 0; (ix+17) + 2, od 8 -> 0 (4 klatki co tick).
; ---------------------------------------------------------------------
objfunc_31_sky2_propeller
	ldy #OB_FLAGS             ; 02:AA6A: set 5,(ix+24) - bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W                 ; 02:AA6E: ld (ix+13),$05 / ld (ix+14),$14
	lda #$05
	sta (zg_obj),y
	iny
	lda #$14
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:AA76: bit 0,(ix+24) / jr nz,@already_initialised
	lda (zg_obj),y
	and #$01
	bne sk31_inited
	ldy #OB_X+1               ; 02:AA7C: hl = (ix+2/3) + $000F / ld (ix+2),l / ld (ix+3),h
	clc
	lda (zg_obj),y
	adc #<$000F
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #>$000F
	sta (zg_obj),y
	ldy #OB_Y+1               ; 02:AA8C: hl = (ix+5/6) + $FFFA / ld (ix+5),l / ld (ix+6),h - y - 6 (16 bit)
	clc
	lda (zg_obj),y
	adc #<$FFFA
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #>$FFFA
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:AA9C: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
sk31_inited                     ; 02:AAA0 @already_initialised: tmp_00 = (ix+2/3) = x, tmp_02 = (ix+5/6) = y
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
	ldy #17                   ; 02:AAB2: ld e,(ix+17) / ld d,$00 / ld hl,PTRTAB_SKY2_propeller_sprites_xyn / add hl,de
	lda (zg_obj),y
	tax
	lda SK31_PTR-OZ_OFF,x     ; 02:AABB: ld e,(hl) / inc hl / ld d,(hl) - de = adres SMS klatki
	sta zg_de
	lda SK31_PTR+1-OZ_OFF,x
	sec                       ; adres SMS -> adres okna tego banku (- OZ_OFF); czytane przez (zg_de),y
	sbc #>OZ_OFF
	sta zg_de+1
	lda #0                    ; 02:AABE: ld b,$02 - dwa sprite'y; zg_off = indeks bajtu klatki (0, potem 3; inc de w oryginale)
	sta zg_off
sk31_each                       ; 02:AAC0 @each_sprite (push bc)
	ldy zg_off
	lda (zg_de),y             ; 02:AAC1: ld a,(de) / ld l,a / ld h,$00 / ld (tmp_04),hl - dx (bez znaku)
	sta tmp_04
	lda #$00
	sta tmp_04+1
	iny                       ; 02:AAC8: inc de / ld a,(de) / ld l,a / ld (tmp_06),hl - dy (h = 0)
	lda (zg_de),y
	sta tmp_06
	lda #$00
	sta tmp_06+1
	iny                       ; 02:AACE: inc de / ld a,(de) / inc de - kafel
	lda (zg_de),y
	iny
	sty zg_off
	ora #$00                  ; 02:AAD1: and a / jp m,@skip_drawing_sprite - kafel >= $80 ($FF) - bez sprite'a
	bmi sk31_skip
	jsr zc_dspr               ; 02:AAD5: push de / call draw_sprite / pop de (zg_de, zg_off - zachowane)
sk31_skip                       ; 02:AADA @skip_drawing_sprite: pop bc / djnz @each_sprite
	lda zg_off
	cmp #6
	bne sk31_each
	lda #$02                  ; 02:AADD: ld hl,$0202 / ld (tmp_06),hl - przesuniecie kolizji (2, 2)
	sta tmp_06
	sta tmp_06+1
	jsr zc_collide            ; 02:AAE3: call check_collision_with_sonic / call nc,damage_sonic
	bcs sk31_nohit
	jsr damage_sonic
sk31_nohit
	lda #$00                  ; 02:AAE9: (ix+15) = (ix+16) = 0 - bez mapy
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #17                   ; 02:AAF1: ld a,(ix+17) / inc a / inc a / cp $08 / ld (ix+17),a / ret c / ld (ix+17),$00
	lda (zg_obj),y
	clc
	adc #$02                  ; (8 bit z zawinieciem jak inc a)
	cmp #$08
	bcc sk31_st
	lda #$00
sk31_st
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_32_badnik_bomb (02:AB21): Bomb - rozmiar $0C x $10, kolizje z mapa WLACZONE (oryginal nie robi set 5), grawitacja Vy =
; $000080 co tick (poza tickiem wybuchu). Zapalnik: (ix+17) < $64 i sonic_x w [x - 56, x + 44) (16 bit, x - 56 zawija) -> (ix+17) = $64.
; Stan wg (ix+17) (licznik + 1 co 64 ticki globalne, tick & $3F = 0; przy $46 -> 0):
;   < $1E: w lewo, Vx = $FFFFF8, animacja chodzenia w lewo;  $1E..$22: stoi (Vx = 0), animacja stania w lewo;
;   $23..$40: w prawo, Vx = $000008, chodzenie w prawo;      $41..$63: stoi, stanie w prawo;
;   $64, $65: Vx = 0, miganie (sekwencja exploding_flashing);  >= $66: Vx = 0, mapa SPRTAB_badnik_bomb_exploding;
;   = $67: 4 kule ognia $0D (spawn_object + init_fireball_object; brak slotu - przerwanie i bez grawitacji w tym ticku, bomba zostaje
;          i probuje znowu w kolejnym ticku): (x, y) Vx -2 / Vy -4; (x + 8, y) Vx +3 / Vy -4; (x, y + 8) Vx -2 / Vy -2;
;          (x + 8, y + 8) Vx +3 / Vy -2 (tmp_04 / tmp_06 = slowa: piksel lo, hi - init_fireball_object pisze (ix+7) = 0,
;          (ix+8/9) = tmp_04, (ix+10) = 0, (ix+11/12) = tmp_06); po czwartej: bomba usunieta ((ix+0) = $FF), efekt $1B,
;          bez grawitacji (Vy bez zmian).
; Na koniec (zawsze, takze po usunieciu): kolizja (2, 2) -> damage_sonic; licznik stanu.
; ---------------------------------------------------------------------
objfunc_32_bomb
	ldy #OB_W                 ; 02:AB21: ld (ix+13),$0C / ld (ix+14),$10
	lda #$0C
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	ldy #17                   ; 02:AB29: ld a,(ix+17) / cp $64 / jr nc,@dont_start_exploding (zapalnik juz dziala)
	lda (zg_obj),y
	cmp #$64
	bcs sk32_nostart
	clc                       ; 02:AB30: l = (ix+2), h = (ix+3) / ld de,$FFC8 / add hl,de / ex de,hl - de = x - 56 (16 bit)
	ldy #OB_X+1
	lda (zg_obj),y
	adc #<$FFC8
	sta zg_de
	iny
	lda (zg_obj),y
	adc #>$FFC8
	sta zg_de+1
	lda sonic_x               ; 02:AB3B: ld hl,(sonic_x) / and a / sbc hl,de / jr c,@dont_start_exploding
	cmp zg_de                 ; (pozyczka = 6502 C = 0: sonic_x < x - 56)
	lda sonic_x+1
	sbc zg_de+1
	bcc sk32_nostart
	clc                       ; 02:AB43: l = (ix+2), h = (ix+3) / ld de,$002C / add hl,de / ex de,hl - de = x + 44
	ldy #OB_X+1
	lda (zg_obj),y
	adc #<$002C
	sta zg_de
	iny
	lda (zg_obj),y
	adc #>$002C
	sta zg_de+1
	lda sonic_x               ; 02:AB4E: ld hl,(sonic_x) / and a / sbc hl,de / jr nc,@dont_start_exploding
	cmp zg_de                 ; (bez pozyczki = 6502 C = 1: sonic_x >= x + 44)
	lda sonic_x+1
	sbc zg_de+1
	bcs sk32_nostart
	lda #$64                  ; 02:AB56: ld (ix+17),$64 - zapalnik
	ldy #17
	sta (zg_obj),y
sk32_nostart                    ; 02:AB5A @dont_start_exploding: ld a,(ix+17) / cp $1E / jr nc,@skip_left_walking
	ldy #17
	lda (zg_obj),y
	cmp #$1E
	bcs sk32_nlw
	lda #$F8                  ; 02:AB61: (ix+7) = $F8, (ix+8) = $FF, (ix+9) = $FF - Vx = $FFFFF8
	ldx #$FF
	jsr sk32_setvx
	lda #<[SK32_SEQ_LW-OZ_OFF] ; 02:AB6D: ld de,SPRTAB_badnik_bomb_normal / ld bc,LUT_badnik_bomb_anim_left_walking
	ldx #>[SK32_SEQ_LW-OZ_OFF]
	jsr sk32_anim             ; 02:AB73: call do_framed_animation
	jmp sk32_grav             ; 02:AB76: jp @finish_with_gravity
sk32_nlw                        ; 02:AB79 @skip_left_walking: ld a,(ix+17) / cp $64 / jp c,@skip_explosion_flashing (A = (ix+17))
	cmp #$64
	jcc sk32_nflash
	lda #$00                  ; 02:AB81: (ix+7) = (ix+8) = (ix+9) = 0 - stoi
	tax
	jsr sk32_setvx
	ldy #17                   ; 02:AB8D: cp $66 / jr nc,@do_explosion_final (a = (ix+17) bez zmian)
	lda (zg_obj),y
	cmp #$66
	bcs sk32_final
	lda #<[SK32_SEQ_FL-OZ_OFF] ; 02:AB91: ld de,SPRTAB_badnik_bomb_normal / ld bc,LUT_badnik_bomb_anim_exploding_flashing
	ldx #>[SK32_SEQ_FL-OZ_OFF]
	jsr sk32_anim             ; 02:AB97: call do_framed_animation
	jmp sk32_grav             ; 02:AB9A: jp @finish_with_gravity
sk32_final                      ; 02:AB9D @do_explosion_final: (ix+15/16) = SPRTAB_badnik_bomb_exploding (adres SMS)
	ldy #OB_SPRITE
	lda #<SK32_SPR_X
	sta (zg_obj),y
	iny
	lda #>SK32_SPR_X
	sta (zg_obj),y
	ldy #17                   ; 02:ABA5: cp $67 / jp nz,@finish_with_gravity (a = (ix+17))
	lda (zg_obj),y
	cmp #$67
	jne sk32_grav
	; --- kula 1: Vx -2, Vy -4, przesuniecie (0, 0) ---
	lda #<$FFFE               ; 02:ABAA: ld hl,$FFFE / ld (tmp_04),hl
	sta tmp_04
	lda #>$FFFE
	sta tmp_04+1
	lda #<$FFFC               ; 02:ABB0: ld hl,$FFFC / ld (tmp_06),hl
	sta tmp_06
	lda #>$FFFC
	sta tmp_06+1
	jsr spawn_object          ; 02:ABB6: call spawn_object / jp c,@finish_without_gravity
	jcs sk32_nograv
	lda #$00                  ; 02:ABBC: ld de,$0000 / ld c,e / ld b,d - DE = 0, BC = 0
	sta zg_de
	sta zg_de+1
	sta zg_bc
	sta zg_bc+1
	jsr zc_initfb             ; 02:ABC1: call init_fireball_object (bank 45)
	; --- kula 2: Vx +3, Vy -4, przesuniecie (8, 0) ---
	lda #<$0003               ; 02:ABC4: ld hl,$0003 / ld (tmp_04),hl
	sta tmp_04
	lda #>$0003
	sta tmp_04+1
	lda #<$FFFC               ; 02:ABCA: ld hl,$FFFC / ld (tmp_06),hl
	sta tmp_06
	lda #>$FFFC
	sta tmp_06+1
	jsr spawn_object          ; 02:ABD0: call spawn_object / jp c,@finish_without_gravity
	jcs sk32_nograv
	lda #$08                  ; 02:ABD6: ld de,$0008 / ld bc,$0000
	sta zg_de
	lda #$00
	sta zg_de+1
	sta zg_bc
	sta zg_bc+1
	jsr zc_initfb             ; 02:ABDC: call init_fireball_object
	; --- kula 3: Vx -2, Vy -2, przesuniecie (0, 8) ---
	lda #<$FFFE               ; 02:ABDF: ld hl,$FFFE / ld (tmp_04),hl
	sta tmp_04
	lda #>$FFFE
	sta tmp_04+1
	lda #<$FFFE               ; 02:ABE5: ld hl,$FFFE / ld (tmp_06),hl
	sta tmp_06
	lda #>$FFFE
	sta tmp_06+1
	jsr spawn_object          ; 02:ABEB: call spawn_object / jp c,@finish_without_gravity
	jcs sk32_nograv
	lda #$00                  ; 02:ABF1: ld de,$0000 / ld bc,$0008
	sta zg_de
	sta zg_de+1
	sta zg_bc+1
	lda #$08
	sta zg_bc
	jsr zc_initfb             ; 02:ABF7: call init_fireball_object
	; --- kula 4: Vx +3, Vy -2, przesuniecie (8, 8) ---
	lda #<$0003               ; 02:ABFA: ld hl,$0003 / ld (tmp_04),hl
	sta tmp_04
	lda #>$0003
	sta tmp_04+1
	lda #<$FFFE               ; 02:AC00: ld hl,$FFFE / ld (tmp_06),hl
	sta tmp_06
	lda #>$FFFE
	sta tmp_06+1
	jsr spawn_object          ; 02:AC06: call spawn_object / jp c,@finish_without_gravity
	jcs sk32_nograv
	lda #$08                  ; 02:AC0C: ld de,$0008 / ld bc,$0008
	sta zg_de
	sta zg_bc
	lda #$00
	sta zg_de+1
	sta zg_bc+1
	jsr zc_initfb             ; 02:AC12: call init_fireball_object
	lda #$FF                  ; 02:AC15: ld (ix+0),$FF - bomba usunieta
	ldy #OB_TYPE
	sta (zg_obj),y
	lda #$1B                  ; 02:AC19: ld a,$1B / rst $28 - efekt wybuchu
	jsr play_sfx
	jmp sk32_nograv           ; 02:AC1C: jr @finish_without_gravity
sk32_nflash                     ; 02:AC1E @skip_explosion_flashing: cp $23 / jr nc,@do_right (A = (ix+17) w $1E..$63)
	cmp #$23
	bcs sk32_right
	lda #$00                  ; 02:AC22: xor a / (ix+7) = (ix+8) = (ix+9) = 0
	tax
	jsr sk32_setvx
	lda #<[SK32_SEQ_LS-OZ_OFF] ; 02:AC2C: ld de,SPRTAB_badnik_bomb_normal / ld bc,LUT_badnik_bomb_anim_left_standing
	ldx #>[SK32_SEQ_LS-OZ_OFF]
	jsr sk32_anim             ; 02:AC32: call do_framed_animation
	jmp sk32_grav             ; 02:AC35: jr @finish_with_gravity
sk32_right                      ; 02:AC37 @do_right: ld a,(ix+17) / cp $41 / jr nc,@do_right_standing
	ldy #17
	lda (zg_obj),y
	cmp #$41
	bcs sk32_rstand
	lda #$08                  ; 02:AC3E: (ix+7) = $08, (ix+8) = (ix+9) = 0 - Vx = $000008
	ldx #$00
	jsr sk32_setvx
	lda #<[SK32_SEQ_RW-OZ_OFF] ; 02:AC4A: ld de,SPRTAB_badnik_bomb_normal / ld bc,LUT_badnik_bomb_anim_right_walking
	ldx #>[SK32_SEQ_RW-OZ_OFF]
	jsr sk32_anim             ; 02:AC50: call do_framed_animation
	jmp sk32_grav             ; 02:AC53: jr @finish_with_gravity
sk32_rstand                     ; 02:AC55 @do_right_standing: (ix+7) = (ix+8) = (ix+9) = 0
	lda #$00
	tax
	jsr sk32_setvx
	lda #<[SK32_SEQ_RS-OZ_OFF] ; 02:AC61: ld de,SPRTAB_badnik_bomb_normal / ld bc,LUT_badnik_bomb_anim_right_standing
	ldx #>[SK32_SEQ_RS-OZ_OFF]
	jsr sk32_anim             ; 02:AC67: call do_framed_animation (dalej wprost @finish_with_gravity)
sk32_grav                       ; 02:AC6A @finish_with_gravity: (ix+10) = $80, (ix+11) = (ix+12) = 0 - Vy = $000080
	ldy #OB_VY
	lda #$80
	sta (zg_obj),y
	iny
	lda #$00
	sta (zg_obj),y
	iny
	sta (zg_obj),y
sk32_nograv                     ; 02:AC76 @finish_without_gravity: ld hl,$0202 / ld (tmp_06),hl
	lda #$02
	sta tmp_06
	sta tmp_06+1
	jsr zc_collide            ; 02:AC7C: call check_collision_with_sonic / call nc,damage_sonic
	bcs sk32_nohit
	jsr damage_sonic
sk32_nohit
	lda g_global_tick_counter ; 02:AC82: ld a,(g_global_tick_counter) / and $3F / ret nz
	and #$3F
	bne sk32_ret
	ldy #17                   ; 02:AC88: inc (ix+17) / ld a,(ix+17) / cp $46 / ret nz / ld (ix+17),$00
	lda (zg_obj),y
	clc
	adc #$01
	sta (zg_obj),y
	cmp #$46
	bne sk32_ret
	lda #$00
	sta (zg_obj),y
sk32_ret
	rts

; sk32_setvx: Vx Bomb - (ix+7) = A (subpiksel), (ix+8) = (ix+9) = X (piksel lo, hi). Niszczy A, Y.
sk32_setvx
	ldy #OB_VX
	sta (zg_obj),y
	txa
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	rts

; sk32_anim: A/X = sekwencja (adres okna) -> zg_bc, zg_de = SPRTAB_badnik_bomb_normal (adres SMS), call do_framed_animation (oz3_dfa)
sk32_anim
	sta zg_bc
	stx zg_bc+1
	lda #<SK32_SPR_N
	sta zg_de
	lda #>SK32_SPR_N
	sta zg_de+1
	jmp oz3_dfa

; ---------------------------------------------------------------------
; objfunc_33_SKY2_cannon (02:AD6C): armata SKY2 (2 na poziomie). Bez kolizji z mapa (set 5), bez kolizji z Soniciem. Pierwszy tick
; (b0 = 0): x (ix+2/3) + $FFFC (- 4), (ix+17) = random_A (faza strzalu), set 0. (ix+17) = $64 -> spawn_object: pocisk $34 w
; (x + 4, y + $10) ((ix+1) = (ix+4) = 0; reszta pol slotu bez zmian - oryginal ich nie czysci), efekt $1C, (ix+18) = $18 (dym),
; (ix+22) = (ix+23) = 0. (ix+18) > 0: animacja dymu (oz3_dfa), (ix+18) - 1; inaczej mapa 0. Zawsze (ix+17) + 1 (8 bit - strzal
; co 256 tickow; brak slotu - bez pocisku i bez dymu).
; ---------------------------------------------------------------------
objfunc_33_sky2_cannon
	ldy #OB_FLAGS             ; 02:AD6C: set 5,(ix+24) - bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01                  ; 02:AD70: bit 0,(ix+24) / jr nz,@already_initialised
	bne sk33_inited
	ldy #OB_X+1               ; 02:AD76: hl = (ix+2/3) + $FFFC / ld (ix+2),l / ld (ix+3),h - x - 4 (16 bit)
	clc
	lda (zg_obj),y
	adc #<$FFFC
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #>$FFFC
	sta (zg_obj),y
	jsr random_A              ; 02:AD86: call random_A / ld (ix+17),a - faza strzalu
	ldy #17
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:AD8C: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
sk33_inited                     ; 02:AD90 @already_initialised: ld a,(ix+17) / cp $64 / jr nz,@skip_spawn_cannon_shell
	ldy #17
	lda (zg_obj),y
	cmp #$64
	bne sk33_noshot
	jsr spawn_object          ; 02:AD97: call spawn_object / jr c,@skip_spawn_cannon_shell (zg_ptr = nowy slot)
	bcs sk33_noshot
	ldy #OB_TYPE              ; 02:ADAD: push ix / de = x, bc = y armaty / push hl / pop ix / xor a / (ix+0) = $34, (ix+1) = a = 0
	lda #$34
	sta (zg_ptr),y
	iny
	lda #$00
	sta (zg_ptr),y
	ldy #OB_X+1               ; 02:ADB5: ld hl,$0004 / add hl,de / (ix+2) = l, (ix+3) = h - x pocisku = x armaty + 4
	clc
	lda (zg_obj),y
	adc #<$0004
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	adc #>$0004
	sta (zg_ptr),y
	iny                       ; 02:ADBF: (ix+4) = a = 0
	lda #$00
	sta (zg_ptr),y
	ldy #OB_Y+1               ; 02:ADC2: ld hl,$0010 / add hl,bc / (ix+5) = l, (ix+6) = h - y pocisku = y armaty + 16
	clc
	lda (zg_obj),y
	adc #<$0010
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	adc #>$0010
	sta (zg_ptr),y
	lda #$1C                  ; 02:ADCC: pop ix / ld a,$1C / rst $28 - efekt strzalu
	jsr play_sfx
	ldy #18                   ; 02:ADD1: ld (ix+18),$18 - czas dymu
	lda #$18
	sta (zg_obj),y
	lda #$00                  ; 02:ADD5: (ix+22) = (ix+23) = 0 - animacja dymu od poczatku
	ldy #22
	sta (zg_obj),y
	iny
	sta (zg_obj),y
sk33_noshot                     ; 02:ADDD @skip_spawn_cannon_shell: ld a,(ix+18) / and a / jr z,@skip_draw_cannon_shot_puff
	ldy #18
	lda (zg_obj),y
	beq sk33_nopuff
	lda #<SK33_SPR            ; 02:ADE3: ld de,SPRTAB_SKY2_cannon_shot_puff (baza map - adres SMS)
	sta zg_de
	lda #>SK33_SPR
	sta zg_de+1
	lda #<[SK33_SEQ-OZ_OFF]   ; 02:ADE6: ld bc,LUT_SKY2_cannon_shot_puff (sekwencja - adres okna)
	sta zg_bc
	lda #>[SK33_SEQ-OZ_OFF]
	sta zg_bc+1
	jsr oz3_dfa               ; 02:ADE9: call do_framed_animation
	ldy #18                   ; 02:ADEC: dec (ix+18)
	lda (zg_obj),y
	sec
	sbc #$01
	sta (zg_obj),y
	jmp sk33_inc              ; 02:ADEF: inc (ix+17) / ret
sk33_nopuff                     ; 02:ADF3 @skip_draw_cannon_shot_puff: (ix+15) = a (= 0), (ix+16) = a - bez mapy
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
sk33_inc                        ; 02:ADF9: inc (ix+17) / ret (8 bit)
	ldy #17
	lda (zg_obj),y
	clc
	adc #$01
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_34_SKY2_cannon_shell (02:AE35): pocisk armaty - bez kolizji z mapa (set 5), rozmiar $0C x $0C. x > scroll_x + $0110
; (16 bit) -> usuniety ((ix+0) = $FF; reszta funkcji wykonuje sie dalej w tym ticku). Kolizja (2, 2) -> damage_sonic. Co tick
; Vx = $000280 (+2,5 px/tick), Vy = 0, mapa SPRTAB_SKY2_cannon_shell.
; ---------------------------------------------------------------------
objfunc_34_cannon_shell
	ldy #OB_FLAGS             ; 02:AE35: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W                 ; 02:AE39: ld (ix+13),$0C / ld (ix+14),$0C
	lda #$0C
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	clc                       ; 02:AE41: ld hl,(g_level_scroll_x_pix_lo) / ld de,$0110 / add hl,de - hl = scroll_x + $0110 (16 bit)
	lda g_level_scroll_x_pix_lo
	adc #<$0110
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #>$0110
	sta zg_hl+1
	ldy #OB_X+1               ; 02:AE48: e = (ix+2), d = (ix+3) / and a / sbc hl,de / jr nc,@skip_despawn_right_of_screen
	lda zg_hl                 ; (6502: C = 1 - bez pozyczki, x <= scroll_x + $0110 - zostaje)
	cmp (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	bcs sk34_keep
	lda #$FF                  ; 02:AE53: ld (ix+0),$FF - pocisk za prawa krawedzia ekranu
	ldy #OB_TYPE
	sta (zg_obj),y
sk34_keep                       ; 02:AE57 @skip_despawn_right_of_screen: ld hl,$0202 / ld (tmp_06),hl
	lda #$02
	sta tmp_06
	sta tmp_06+1
	jsr zc_collide            ; 02:AE5D: call check_collision_with_sonic / call nc,damage_sonic
	bcs sk34_nohit
	jsr damage_sonic
sk34_nohit
	ldy #OB_VX                ; 02:AE63: xor a / (ix+7) = $80, (ix+8) = $02, (ix+9) = a - Vx = $000280
	lda #$80
	sta (zg_obj),y
	iny
	lda #$02
	sta (zg_obj),y
	iny
	lda #$00
	sta (zg_obj),y
	iny                       ; 02:AE6F: (ix+10) = (ix+11) = (ix+12) = 0 - Vy = 0
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_SPRITE            ; 02:AE78: (ix+15/16) = SPRTAB_SKY2_cannon_shell (adres SMS) / ret
	lda #<SK34_SPR
	sta (zg_obj),y
	iny
	lda #>SK34_SPR
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_37_SKY2_turning_gun (02:B16C): obrotowe dzialo (3 na poziomie). Bez kolizji z mapa (set 5), bez kolizji z Soniciem, mapa 0.
; Pierwszy tick (b0 = 0): (ix+17) = random_A & 7 (kierunek), set 0. Co tick: tmp_00 = x, tmp_02 = y; 2 sprite'y z
; LUT_SKY2_turning_gun_sprite_info[(ix+17) * 8] (tmp_04 = dx, tmp_06 = dy - bajty ze znakiem rozszerzone do slowa, zapisywane takze
; dla pominietego sprite'a; kafel $FF - pominiety). tick & $3F = 0: (ix+17) = ((ix+17) + 1) & 7. (ix+18) + 1; przy $1A: (ix+18) = 0
; i strzal w biezacym (juz obroconym) kierunku: wpis LUT_SKY2_turning_gun_bullet_directions[(ix+17) * 6]: tmp_04 = Vx, tmp_06 = Vy
; (slowa: subpiksel, piksel lo - shoot_straight_fireball pisze (ix+7) = lo, (ix+8) = hi, (ix+9) = znak; np. kierunek 0: Vy = $FE00 =
; -2 px/tick), DE = dx, BC = dy (bajty ze znakiem) -> shoot_straight_fireball (sky_shoot_fireball: kula $0D, efekt $01).
; ---------------------------------------------------------------------
objfunc_37_turning_gun
	ldy #OB_FLAGS             ; 02:B16C: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01                  ; 02:B170: bit 0,(ix+24) / jr nz,@already_initialised
	bne sk37_inited
	jsr random_A              ; 02:B176: call random_A / and $07 / ld (ix+17),a - kierunek startowy
	and #$07
	ldy #17
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:B17E: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
sk37_inited                     ; 02:B182 @already_initialised: (ix+15) = (ix+16) = 0 - bez mapy
	lda #$00
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_X+1               ; 02:B18A: tmp_00 = (ix+2/3) = x, tmp_02 = (ix+5/6) = y
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
	ldy #17                   ; 02:B19C: ld a,(ix+17) / add a,a x 3 / ld e,a / ld d,$00 / ld hl,LUT_..._sprite_info / add hl,de
	lda (zg_obj),y            ; (kierunek * 8, 8 bit; zg_off = indeks bajtu w tablicy - wskaznik hl; najwyzej $F8 + 7 - bez przeniesienia)
	asl
	asl
	asl
	sta zg_off
	lda #$02                  ; 02:B1A9: ld b,$02 - dwa sprite'y (zg_a = licznik)
	sta zg_a
sk37_each                       ; 02:B1AB @each_sprite_maybe (push bc)
	ldx zg_off
	lda SK37_SPR-OZ_OFF,x     ; 02:B1AC: ld d,$00 / ld e,(hl) / bit 7,e / jr z / ld d,$FF / ld (tmp_04),de - dx ze znakiem
	sta tmp_04
	and #$80
	beq sk37_dxp
	lda #$FF
sk37_dxp                        ; @sprite_dx_was_positive
	sta tmp_04+1
	lda SK37_SPR+1-OZ_OFF,x   ; 02:B1B9: inc hl / ld d,$00 / ld e,(hl) / bit 7,e / ... / ld (tmp_06),de - dy ze znakiem
	sta tmp_06
	and #$80
	beq sk37_dyp
	lda #$FF
sk37_dyp                        ; @sprite_dy_was_positive
	sta tmp_06+1
	lda zg_off                ; 02:B1C7: inc hl / ld a,(hl) / inc hl / inc hl - nastepny sprite 4 B dalej
	clc
	adc #$04
	sta zg_off
	lda SK37_SPR+2-OZ_OFF,x   ; kafel (X = indeks poczatku wpisu)
	cmp #$FF                  ; 02:B1CB: cp $FF / jr z,@skip_this_sprite
	beq sk37_skip
	jsr zc_dspr               ; 02:B1CF: push hl / call draw_sprite / pop hl (zg_off, zg_a zachowane)
sk37_skip                       ; 02:B1D4 @skip_this_sprite: pop bc / djnz @each_sprite_maybe
	dec zg_a
	bne sk37_each
	lda g_global_tick_counter ; 02:B1D7: ld a,(g_global_tick_counter) / and $3F / jr nz,@skip_turning_gun_to_next_direction
	and #$3F
	bne sk37_norot
	ldy #17                   ; 02:B1DE: ld a,(ix+17) / inc a / and $07 / ld (ix+17),a - obrot co 64 ticki
	lda (zg_obj),y
	clc
	adc #$01
	and #$07
	sta (zg_obj),y
sk37_norot                      ; 02:B1E7 @skip_turning_gun_to_next_direction: inc (ix+18) / ld a,(ix+18) / cp $1A / ret nz
	ldy #18
	lda (zg_obj),y
	clc
	adc #$01
	sta (zg_obj),y
	cmp #$1A
	bne sk37_ret
	lda #$00                  ; 02:B1F0: ld (ix+18),$00
	sta (zg_obj),y
	ldy #17                   ; 02:B1F4: ld a,(ix+17) / add a,a / ld e,a / add a,a / add a,e / ld e,a / ld d,$00 - e = kierunek * 6 (8 bit)
	lda (zg_obj),y
	asl
	sta zg_a                  ; e = 2a
	asl
	clc
	adc zg_a                  ; 4a + 2a
	tax                       ; 02:B1FE: ld hl,LUT_SKY2_turning_gun_bullet_directions / add hl,de (X = e; kierunek <= 7 -> e + 5 < $100)
	lda SK37_DIR-OZ_OFF,x     ; 02:B202: ld e,(hl) / inc hl / ld d,(hl) / inc hl / ld (tmp_04),de - Vx kuli
	sta tmp_04
	lda SK37_DIR+1-OZ_OFF,x
	sta tmp_04+1
	lda SK37_DIR+2-OZ_OFF,x   ; 02:B20A: ld e,(hl) / inc hl / ld d,(hl) / ld (tmp_06),de - Vy kuli
	sta tmp_06
	lda SK37_DIR+3-OZ_OFF,x
	sta tmp_06+1
	lda SK37_DIR+4-OZ_OFF,x   ; 02:B211: inc hl / ld e,(hl) / ld d,$00 / bit 7,e / jr z / dec d - DE = dx (ze znakiem)
	sta zg_de
	and #$80
	beq sk37_sdxp
	lda #$FF
sk37_sdxp                       ; @shot_dx_was_positive
	sta zg_de+1
	lda SK37_DIR+5-OZ_OFF,x   ; 02:B21A: inc hl / ld c,(hl) / ld b,$00 / bit 7,c / jr z / dec b - BC = dy (ze znakiem)
	sta zg_bc
	and #$80
	beq sk37_sdyp
	lda #$FF
sk37_sdyp                       ; @shot_dy_was_positive
	sta zg_bc+1
	jmp sky_shoot_fireball    ; 02:B223: call shoot_straight_fireball / ret (zg_obj = dzialo, zg_de / zg_bc = DE / BC, tmp_04 / tmp_06)
sk37_ret
	rts

; ---------------------------------------------------------------------
; objfunc_39_SKY2_spike_wall_right (02:B398): sciana kolcow (jedna, (64, 224)). Bez kolizji z mapa (set 5). Pierwszy tick (b0 = 0):
; (ix+17/18) = x startowe (piksele lo, hi), set 0. Co tick: rozmiar $0C x $2E, mapa SPRTAB_SKY2_spike_wall_right (3 wiersze),
; kolizja (2, 2) -> damage_sonic; 2 dodatkowe sprite'y nad mapa: tmp_00 = x zaokraglone ((ix+1..3) + $80) >> 8, tmp_02 = y,
; (tmp_04, tmp_06) = (0, -16) kafel $16, (8, -16) kafel $18. Vx = 0; dalej tylko przy x < $0580 (16 bit): y + $40 < scroll_y
; (sciana nad kamera) -> x = x startowe (subpiksel bez zmian); Sonic w pasie y - 32 < sonic_y <= y + 44 (16 bit, y - 32 zawija)
; -> Vx = $000080 (+0,5 px/tick).
; ---------------------------------------------------------------------
objfunc_39_spike_wall
	ldy #OB_FLAGS             ; 02:B398: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01                  ; 02:B39C: bit 0,(ix+24) / jr nz,@already_initialised
	bne sk39_inited
	ldy #OB_X+1               ; 02:B3A2: l = (ix+2), h = (ix+3) / ld (ix+17),l / ld (ix+18),h - x startowe
	lda (zg_obj),y
	ldy #17
	sta (zg_obj),y
	ldy #OB_X+2
	lda (zg_obj),y
	ldy #18
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:B3AE: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
sk39_inited                     ; 02:B3B2 @already_initialised: ld (ix+13),$0C / ld (ix+14),$2E
	ldy #OB_W
	lda #$0C
	sta (zg_obj),y
	iny
	lda #$2E
	sta (zg_obj),y
	iny                       ; 02:B3BA: (ix+15/16) = SPRTAB_SKY2_spike_wall_right (adres SMS)
	lda #<SK39_SPR
	sta (zg_obj),y
	iny
	lda #>SK39_SPR
	sta (zg_obj),y
	lda #$02                  ; 02:B3C2: ld hl,$0202 / ld (tmp_06),hl
	sta tmp_06
	sta tmp_06+1
	jsr zc_collide            ; 02:B3C8: call check_collision_with_sonic / call nc,damage_sonic
	bcs sk39_nohit
	jsr damage_sonic
sk39_nohit
	clc                       ; 02:B3CE: l = (ix+1), h = (ix+2), a = (ix+3) / ld de,$0080 / add hl,de / adc a,$00 / ld l,h / ld h,a
	ldy #OB_X
	lda (zg_obj),y
	adc #$80                  ; subpiksel - tylko przeniesienie
	iny
	lda (zg_obj),y
	adc #$00
	sta tmp_00                ; 02:B3DF: ld (tmp_00),hl - x zaokraglone do piksela
	iny
	lda (zg_obj),y
	adc #$00
	sta tmp_00+1
	ldy #OB_Y+1               ; 02:B3E2: tmp_02 = (ix+5/6) = y
	lda (zg_obj),y
	sta tmp_02
	iny
	lda (zg_obj),y
	sta tmp_02+1
	lda #$00                  ; 02:B3EB: ld hl,$0000 / ld (tmp_04),hl
	sta tmp_04
	sta tmp_04+1
	lda #<$FFF0               ; 02:B3F1: ld hl,$FFF0 / ld (tmp_06),hl - 16 px nad obiektem
	sta tmp_06
	lda #>$FFF0
	sta tmp_06+1
	lda #$16                  ; 02:B3F7: ld a,$16 / call draw_sprite
	jsr zc_dspr
	lda #<$0008               ; 02:B3FC: ld hl,$0008 / ld (tmp_04),hl
	sta tmp_04
	lda #>$0008
	sta tmp_04+1
	lda #$18                  ; 02:B402: ld a,$18 / call draw_sprite
	jsr zc_dspr
	lda #$00                  ; 02:B410: xor a / (ix+7) = (ix+8) = (ix+9) = 0 - Vx = 0
	ldy #OB_VX
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_X+1               ; 02:B407: l = (ix+2), h = (ix+3) / ld de,$0580 / ... / sbc hl,de / ret nc (C = 0 po xor a)
	lda (zg_obj),y            ; (6502: C = 1 - bez pozyczki, x >= $0580 - koniec)
	cmp #<$0580
	iny
	lda (zg_obj),y
	sbc #>$0580
	bcs sk39_ret
	clc                       ; 02:B41D: c = (ix+5), b = (ix+6) / ld hl,$0040 / add hl,bc - hl = y + $40 (16 bit)
	ldy #OB_Y+1
	lda (zg_obj),y
	adc #<$0040
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #>$0040
	sta zg_hl+1
	lda zg_hl                 ; 02:B427: ld de,(g_level_scroll_y_pix_lo) / and a / sbc hl,de / jr nc,@skip_position_reset_when_above_camera
	cmp g_level_scroll_y_pix_lo ; (6502: C = 1 - bez pozyczki, y + $40 >= scroll_y)
	lda zg_hl+1
	sbc g_level_scroll_y_pix_lo+1
	bcs sk39_noreset
	ldy #17                   ; 02:B430: (ix+2) = (ix+17), (ix+3) = (ix+18) - powrot na start (sciana nad kamera)
	lda (zg_obj),y
	ldy #OB_X+1
	sta (zg_obj),y
	ldy #18
	lda (zg_obj),y
	ldy #OB_X+2
	sta (zg_obj),y
sk39_noreset                    ; 02:B43C @skip_position_reset_when_above_camera: de = sonic_y; ld hl,$FFE0 / add hl,bc - hl = y - 32
	clc
	ldy #OB_Y+1
	lda (zg_obj),y
	adc #<$FFE0
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #>$FFE0
	sta zg_hl+1
	lda zg_hl                 ; 02:B444: xor a / sbc hl,de / ret nc (6502: C = 1 - bez pozyczki, y - 32 >= sonic_y - Sonic wyzej)
	cmp sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcs sk39_ret
	clc                       ; 02:B448: ld hl,$002C / add hl,bc - hl = y + 44
	ldy #OB_Y+1
	lda (zg_obj),y
	adc #<$002C
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #>$002C
	sta zg_hl+1
	lda zg_hl                 ; 02:B44C: xor a / sbc hl,de / ret c (6502: C = 0 - pozyczka, y + 44 < sonic_y - Sonic nizej)
	cmp sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcc sk39_ret
	ldy #OB_VX                ; 02:B450: (ix+7) = $80, (ix+8) = a (= 0), (ix+9) = a - Vx = $000080 (+0,5 px/tick) / ret
	lda #$80
	sta (zg_obj),y
	iny
	lda #$00
	sta (zg_obj),y
	iny
	sta (zg_obj),y
sk39_ret
	rts
