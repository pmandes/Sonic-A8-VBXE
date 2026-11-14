; =====================================================================
;  obj/objz3_sky_dziala.asm - M6.10 Sky Base (SKY1): $38 platforma SKY jadaca w prawo, $3A stale dzialo, wspolny pomocnik
;  M6.10: kod w trzecim banku obiektow strefy PB_OBJZ3 (bank 30, tylko Sky Base; obj/objz3.asm) - dane banku 2 ROM-u pod adresem
;  SMS - OZ_OFF jak w PB_OBJZ2 (zakresy OBJZ3_SPANS w tools/extract_sms.py, stale OZ3_* w objdata.inc).
;  sky_shoot_fireball (shoot_straight_fireball) oraz kopie $3B platformy kolyszacej i $35 / $36 Orbinauta z banku 11 (bank
;  obiektow strefy 3 PB_OBJZ3, bank 30, okno $4000-$7FFF; dolaczany z game.asm, tablica oz3_tab w obj/objz3.asm).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny):
;   objfunc_38_SKY_platform_right  02:B297-02:B37A, dane 02:B37B-02:B397 (SPRTAB_SKY_platform 02:B37B - 13 B, wspolna mapa
;     tez dla $3B w SKY; LUT_SKY_platform_right_propeller_sprites 02:B388 - 4 klatki x 2 pary (dy, kafel) = 16 B),
;   objfunc_3A_SKY_fixed_gun       02:B46D-02:B4E5, dane LUT_SKY_fixed_gun_dir_setup 02:B4E6-02:B50D (4 kierunki x 10 B),
;   objfunc_3B_platform_y_oscillate 02:B50E-02:B5B4 (z @fn_do_y_oscillate 02:B53B), dane SPRTAB_platform_y_oscillate_BRI
;     02:B5B5-02:B5C1 (+ SPRTAB_SKY_platform 02:B37B) - KOPIA przekladu z banku 11 (obj/objz.asm, objfunc_3B_platform_y_oscillate),
;   shoot_straight_fireball        02:B5C2-02:B633 (114 B; wola go $3A 02:B4E2 i objfunc_37_SKY2_turning_gun 02:B223),
;   objfunc_35_badnik_orbinaut     02:AE88-02:B030 (z @fn_maybe_jettison_balls 02:AF98 i @fn_jettison_ball 02:AFDB),
;   objfunc_36_badnik_orbinaut_ejected_ball 02:B0F4-02:B16B, dane 02:B031-02:B0F3 (LUT_orbinaut_ball_xy_positions 02:B031 -
;     82 pary (dx, dy) = 164 B, SPRTAB_orbinaut_base_left 02:B0D5, SPRTAB_orbinaut_base_right 02:B0E7) - KOPIA przekladu z banku 11
;     (obj/objz_lab_orbinaut.asm).
;  Dane leza w tym banku pod adresem SMS - OZ_OFF (zakresy SKY w OBJZ3_SPANS, tools/extract_sms.py / objdata.inc).
;  Procedury:
;   objfunc_38_sky_platform_right (02:B297) - funkcja obiektu $38 (platforma na kolysaniu kamery, wiezie Sonica w prawo)
;   objfunc_3A_sky_fixed_gun      (02:B46D) - funkcja obiektu $3A (stale dzialo strzelajace po skosie, kierunek z bloku pod nim)
;   sky_shoot_fireball            (02:B5C2) - shoot_straight_fireball: nowa kula ognia $0D (wejscie dla $3A i $37 - patrz nizej)
;   objfunc_3B_platform_osc2      (02:B50E) - funkcja obiektu $3B (kopia; osc2_yosc = @fn_do_y_oscillate 02:B53B)
;   objfunc_35_orbinaut2          (02:AE88) - funkcja obiektu $35 (kopia; orb2_jettison 02:AF98, orb2_eject 02:AFDB)
;   objfunc_36_orbinaut_ball2     (02:B0F4) - funkcja obiektu $36 (kopia)
;  Obiekty tworzone w locie: $0D (kula ognia; sky_shoot_fireball - funkcja $0D jest w banku 45, objs_c.asm), $36 (kula Orbinauta;
;  orb2_eject - tylko w Labyrinth: g_tile_flags_index = 3, w SKY nigdy).
;  Pola rekordu:
;   $38: (ix+17) faza smigla 0 / 4 / 8 / 12 (+4 co tick, od $10 znowu 0 = indeks bajtu w LUT smigiel; start 0 - wczytanie obiektu
;        load_object_from_level_spec 00:2390 zeruje (ix+7..25), wiec LUT czytana tylko w $B388-$B397), (ix+18..20) y bazowe
;        (24 bit: sub, lo, hi - kopia (ix+4..6) z pierwszego ticku), (ix+24) b0 = zainicjowana, b5 = bez kolizji z mapa (co tick).
;   $3A: (ix+17) kierunek 0..3 (blok ukladu pod (x, y) minus $3C; inny blok - obiekt nic nie robi i sprawdza go w kolejnym ticku),
;        (ix+18) licznik tickow 8 bit (strzal przy (ix+18) & $4F = 0), (ix+24) b0 = zainicjowane, b5.
;   $3B / $35 / $36: jak w banku 11 (opisy przy kopiach nizej).
;  Wola: zc_collide (check_collision_with_sonic 00:3956), zc_enemy (enemy_touched_sonic 00:35E5), zc_dspr (draw_sprite 00:3581),
;  zc_put (put_sonic_y_pos_on_platform 01:7CC1) - stuby do banku 45 (game/objcom.asm); obj_tile_ptr (get_obj_level_tile_ptr_in_ram
;  00:36F9, game/motion.asm), spawn_object (01:7C7B), play_sfx (rst $28), damage_sonic (00:35FD) - kod rezydentny $8000+;
;  v_rom_reads (vars.asm) - licznik odczytow bloku spod adresu ROM SMS.
;  Wskazniki map (ix+15/16) zostaja adresami SMS ($B37B, $B5B5, $B0D5, $B0E7) - obj_draw kopiuje mape z tego banku (objz_mapcopy).
;  Rejestry Z80: IX = zg_obj, HL nowego obiektu (spawn_object) = zg_ptr, BC = zg_bc, DE = zg_de, HL = zg_hl; w $38 zg_hl = indeks
;  bajtu w LUT smigiel (hl - LUT), zg_bc+1 = licznik B petli smigiel; w $3A zg_a = 2 * kierunek (ld e,a przy mnozeniu przez 10).
;
;  sky_shoot_fireball (shoot_straight_fireball 02:B5C2) - wejscie wspolne ($3A tu, $37 obrotowe dzialo z innego pliku):
;   Wejscie: zg_obj = obiekt strzelajacy (IX; czytane tylko (ix+2/3) x i (ix+5/6) y),
;            zg_de  = przesuniecie X kuli wzgledem x strzelajacego (16 bit, DE: zg_de = E, zg_de+1 = D),
;            zg_bc  = przesuniecie Y kuli wzgledem y (16 bit, BC: zg_bc = C, zg_bc+1 = B),
;            tmp_04 / tmp_04+1 = Vx kuli (subpiksel, piksel; bajt (ix+9) = $FF gdy bit 7 tmp_04+1, inaczej 0),
;            tmp_06 / tmp_07   = Vy kuli (subpiksel, piksel; (ix+12) = rozszerzenie znaku tmp_07).
;   Wyjscie: brak wolnego slotu - C = 1, nic nie zmienione (bez SFX; jak ret c 02:B5C9);
;            inaczej zg_ptr = nowy obiekt $0D: (ix+0) = $0D, (ix+1) = 0, (ix+2/3) = x + DE, (ix+4) = 0, (ix+5/6) = y + BC
;            (sumy 16 bit obciete), (ix+17) = 0, (ix+19..23) = 0, Vx (ix+7..9), Vy (ix+10..12) jak wyzej; (ix+13..16), (ix+18),
;            (ix+24), (ix+25) bez zmian (oryginal ich nie czysci); potem efekt $01 (play_sfx). Flagi po strzale nieokreslone
;            (oryginal: po rst $28 - wolajacy robia tylko ret).
;   Zachowuje zg_obj, zg_bc, zg_de, zg_hl, tmp_*. Niszczy A, X, Y, zg_ptr (spawn_object: takze v_dirty_t / v_obj_dirty).
; =====================================================================
; adresy SMS danych (czytane w tym banku pod adresem SMS - OZ_OFF)
SKY_SPR_PLAT     = $B37B  ; SPRTAB_SKY_platform: wiersz 0 = $FE + 5 x $FF (pusty), wiersz 1 = 4 x $36, $FF, $FF, potem $FF (koniec)
SKY_LUT_PROP     = $B388  ; LUT_SKY_platform_right_propeller_sprites: 4 klatki x ((dy, kafel), (dy, kafel)); kafel $FF = bez sprite'a
SKY_LUT_GUN      = $B4E6  ; LUT_SKY_fixed_gun_dir_setup: 4 x (Vx.w, Vy.w, dx.w, dy.w, hi(sonic_x - x), hi(sonic_y - y))
SKY_SPR_PLAT_BRI = $B5B5  ; SPRTAB_platform_y_oscillate_BRI (kopia $3B: tylko gdy g_tile_flags_index = 1 - w Sky Base nieosiagalne)
SKY_ORBXY        = $B031  ; LUT_orbinaut_ball_xy_positions: (dx, dy) kuli wg kata (164 B)
SKY_SPR_ORB_L    = $B0D5  ; SPRTAB_orbinaut_base_left
SKY_SPR_ORB_R    = $B0E7  ; SPRTAB_orbinaut_base_right

; ---------------------------------------------------------------------
; objfunc_38_SKY_platform_right (02:B297): platforma SKY1 (30 x 16) zawieszona na smigle. Bez kolizji z mapa (set 5).
; Pierwszy tick (b0 = 0): (ix+18..20) = (ix+4..6) (y bazowe 24 bit), set 0. Co tick: y (24 bit) = baza + kolysanie
; (g_y_oscillate_sub, g_y_oscillate_pix lo, hi - to samo przesuniecie co kamera SKY). Gdy Vy Sonica >= 0 (bajt hi): (ix+13) = $1E,
; (ix+14) = $10, kolizja z przesunieciem (2, $0A); trafienie -> cele granic kamery y0 = y1 = $0030, put_sonic_y_pos_on_platform
; (BC = $0010, DE = 0), x platformy (24 bit) + $80 i x Sonica (24 bit) + $80 (+0,5 px w prawo). Na koniec 2 sprite'y smigla
; (draw_sprite w (x - 8, y + dy), klatka (ix+17) z LUT; kafel $FF - bez sprite'a, tmp_06 i tak zapisane), mapa
; SPRTAB_SKY_platform, (ix+17) + 4, od $10 -> 0.
; ---------------------------------------------------------------------
objfunc_38_sky_platform_right
	ldy #OB_FLAGS             ; 02:B297: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01                  ; 02:B29B: bit 0,(ix+24) / jr nz @already_initialised
	bne sk38_inited
	ldy #OB_Y                 ; 02:B2A1: (ix+18) = (ix+4) - y bazowe: subpiksel
	lda (zg_obj),y
	ldy #18
	sta (zg_obj),y
	ldy #OB_Y+1               ; 02:B2A7: (ix+19) = (ix+5) - piksel lo
	lda (zg_obj),y
	ldy #19
	sta (zg_obj),y
	ldy #OB_Y+2               ; 02:B2AD: (ix+20) = (ix+6) - piksel hi
	lda (zg_obj),y
	ldy #20
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:B2B3: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
sk38_inited                     ; 02:B2B7 @already_initialised: c = g_y_oscillate_pix_hi, de = (g_y_oscillate_sub, _pix lo),
	ldy #18                   ; hl = (ix+18/19), a = (ix+20); add hl,de / adc a,c -> (ix+4), (ix+5), (ix+6)
	clc
	lda (zg_obj),y
	adc g_y_oscillate_sub
	ldy #OB_Y                 ; 02:B2CA: (ix+4) = l (ldy nie zmienia C)
	sta (zg_obj),y
	ldy #19
	lda (zg_obj),y
	adc g_y_oscillate_pix
	ldy #OB_Y+1               ; 02:B2CD: (ix+5) = h
	sta (zg_obj),y
	ldy #20
	lda (zg_obj),y
	adc g_y_oscillate_pix+1
	ldy #OB_Y+2               ; 02:B2D0: (ix+6) = a
	sta (zg_obj),y
	lda sonic_vel_y_hi        ; 02:B2D3: ld a,(sonic_vel_y_hi) / and a / jp m @skip_put_sonic_on_platform (Sonic leci w gore)
	bmi sk38_draw
	ldy #OB_W                 ; 02:B2DA: (ix+13) = $1E, (ix+14) = $10
	lda #$1E
	sta (zg_obj),y
	iny
	lda #$10
	sta (zg_obj),y
	lda #$02                  ; 02:B2E2: ld hl,$0A02 / ld (tmp_06),hl: tmp_06 = 2, tmp_07 = $0A
	sta tmp_06
	lda #$0A
	sta tmp_07
	jsr zc_collide            ; 02:B2E8: call check_collision_with_sonic / jr c @skip_put_sonic_on_platform
	bcs sk38_draw
	lda #$30                  ; 02:B2ED: g_camera_sonic_bounds_y0_target = $0030
	sta g_camera_sonic_bounds_y0_target
	lda #$00
	sta g_camera_sonic_bounds_y0_target+1
	lda #$30                  ; 02:B2F3: g_camera_sonic_bounds_y1_target = $0030
	sta g_camera_sonic_bounds_y1_target
	lda #$00
	sta g_camera_sonic_bounds_y1_target+1
	lda #$10                  ; 02:B2F9: ld bc,$0010 / ld de,$0000 / call put_sonic_y_pos_on_platform
	sta zg_bc
	lda #$00
	sta zg_bc+1
	sta zg_de
	sta zg_de+1
	jsr zc_put
	ldy #OB_X                 ; 02:B302: hl = (ix+1/2), a = (ix+3); de = $0080; add hl,de / adc a,$00
	clc
	lda (zg_obj),y
	adc #$80
	sta (zg_obj),y            ; 02:B311: (ix+1) = l
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y            ; 02:B314: (ix+2) = h
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y            ; 02:B317: (ix+3) = a
	clc                       ; 02:B31A: hl = (sonic_x_sub), a = (sonic_x_hi); add hl,de / adc a,$00 (de = $0080)
	lda sonic_x_sub
	adc #$80
	sta sonic_x_sub           ; 02:B323: ld (sonic_x_sub),hl
	lda sonic_x
	adc #$00
	sta sonic_x
	lda sonic_x+1
	adc #$00
	sta sonic_x+1             ; 02:B326: ld (sonic_x_hi),a
sk38_draw                       ; 02:B329 @skip_put_sonic_on_platform: tmp_00 = (ix+2/3) = x
	ldy #OB_X+1
	lda (zg_obj),y
	sta tmp_00
	iny
	lda (zg_obj),y
	sta tmp_00+1
	ldy #OB_Y+1               ; 02:B332: tmp_02 = (ix+5/6) = y
	lda (zg_obj),y
	sta tmp_02
	iny
	lda (zg_obj),y
	sta tmp_02+1
	lda #$F8                  ; 02:B33B: ld hl,$FFF8 / ld (tmp_04),hl - smiglo 8 px na lewo od x
	sta tmp_04
	lda #$FF
	sta tmp_04+1
	ldy #17                   ; 02:B341: ld e,(ix+17) / ld d,$00 / ld hl,LUT_SKY_platform_right_propeller_sprites / add hl,de
	lda (zg_obj),y
	sta zg_hl                 ; zg_hl = hl - LUT (indeks bajtu)
	lda #$02                  ; 02:B34A: ld b,$02
	sta zg_bc+1
sk38_prop                       ; 02:B34C @each_propeller_sprite (push bc)
	ldx zg_hl
	lda SKY_LUT_PROP-OZ_OFF,x ; 02:B34D: ld e,(hl) / ld d,$00 / inc hl / ld (tmp_06),de - tmp_06 = dy, tmp_07 = 0
	sta tmp_06
	lda #$00
	sta tmp_07
	lda SKY_LUT_PROP+1-OZ_OFF,x ; 02:B355: ld a,(hl) / inc hl - kafel
	inc zg_hl                 ; hl + 2 (nastepna para)
	inc zg_hl
	cmp #$FF                  ; 02:B357: cp $FF / jr z @skip_drawing_this_propeller_sprite
	beq sk38_skip
	jsr zc_dspr               ; 02:B35C: push hl / call draw_sprite / pop hl (A = kafel; zg_hl i zg_bc zachowane)
sk38_skip                       ; 02:B360 @skip_drawing_this_propeller_sprite: pop bc / djnz @each_propeller_sprite
	dec zg_bc+1
	bne sk38_prop
	ldy #OB_SPRITE            ; 02:B363: (ix+15/16) = SPRTAB_SKY_platform (adres SMS)
	lda #<SKY_SPR_PLAT
	sta (zg_obj),y
	iny
	lda #>SKY_SPR_PLAT
	sta (zg_obj),y
	ldy #17                   ; 02:B36B: ld a,(ix+17) / add a,$04 / ld (ix+17),a / cp $10 / ret c
	lda (zg_obj),y
	clc
	adc #$04
	sta (zg_obj),y
	cmp #$10
	bcc sk38_ret
	lda #$00                  ; 02:B376: (ix+17) = 0
	sta (zg_obj),y
sk38_ret
	rts

; ---------------------------------------------------------------------
; objfunc_3A_SKY_fixed_gun (02:B46D): stale dzialo SKY1 (rysowane kaflami ukladu - bez mapy sprite'ow; (ix+15/16) nie ustawiane).
; Bez kolizji z mapa (set 5). Dopoki b0 = 0: blok ukladu pod (x, y) (get_obj_level_tile_ptr_in_ram z BC = DE = 0) - $3C..$3F ->
; (ix+17) = blok - $3C (kierunek), set 0; inny blok - ret (proba w kolejnym ticku). Adres ROM SMS (port nie ma ROM-u): jak inny
; blok, v_rom_reads + 1 (precedens: drzwi $17, gargulec $3F). Potem co tick inc (ix+18); strzal tylko gdy (ix+18) b6 = 0 (pierwsza
; polowa kazdych 128 tickow) i (ix+18) & $0F = 0 (co 16 tickow): wpis LUT (10 B) wg kierunku -> tmp_04 = Vx, tmp_06 = Vy (zapis
; takze bez strzalu), DE = dx, BC = dy; strzal (shoot_straight_fireball) gdy starszy bajt (sonic_x - x) = bajt 8 wpisu i starszy
; bajt (sonic_y - y) = bajt 9 (16 bit, bez znaku: $FF = Sonic na lewo / w gorze w odleglosci < 256, 0 = na prawo / w dole).
; Kierunki: 0 = w lewo-gore (Vx = Vy = -1,5 px; (0, -8)), 1 = w prawo-gore (+1,5 / -1,5; ($18, -8)), 2 = w lewo-dol (-1,5 / +1,5;
; (0, $10)), 3 = w prawo-dol (+1,5 / +1,5; ($18, $10)).
; ---------------------------------------------------------------------
objfunc_3A_sky_fixed_gun
	ldy #OB_FLAGS             ; 02:B46D: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01                  ; 02:B471: bit 0,(ix+24) / jr nz @already_initialised
	bne sk3a_inited
	lda #$00                  ; 02:B477: ld bc,$0000 / ld e,c / ld d,b - punkt testu (x, y) obiektu
	sta zg_bc
	sta zg_bc+1
	sta zg_de
	sta zg_de+1
	jsr obj_tile_ptr          ; 02:B47C: call get_obj_level_tile_ptr_in_ram; zg_ptr = adres bajtu ukladu, C = 1 - adres ROM SMS
	bcc sk3a_tile
	inc v_rom_reads           ; adres ROM SMS pod obiektem (port nie ma ROM-u): jak blok spoza $3C..$3F (ret nc), licznik v_rom_reads
sk3a_iret
	rts
sk3a_tile
	ldy #0                    ; 02:B47F: ld a,(hl) / sub $3C / cp $04 / ret nc
	lda (zg_ptr),y
	sec
	sbc #$3C
	cmp #$04
	bcs sk3a_iret
	ldy #17                   ; 02:B485: (ix+17) = a (kierunek 0..3)
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:B488: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
sk3a_inited                     ; 02:B48C @already_initialised: inc (ix+18) / ld a,(ix+18)
	ldy #18
	lda (zg_obj),y
	clc
	adc #$01
	sta (zg_obj),y
	tax
	and #$40                  ; 02:B492: bit 6,a / ret nz
	bne sk3a_ret
	txa                       ; 02:B495: and $0F / ret nz
	and #$0F
	bne sk3a_ret
	ldy #17                   ; 02:B498: ld a,(ix+17) / add a,a / ld e,a / add a,a / add a,a / add a,e - e = 10 * kierunek
	lda (zg_obj),y
	asl
	sta zg_a                  ; e = 2 * kierunek
	asl
	asl
	clc
	adc zg_a
	tax                       ; 02:B4A1: ld d,$00 / ld hl,LUT_SKY_fixed_gun_dir_setup / add hl,de - X = indeks wpisu
	lda SKY_LUT_GUN-OZ_OFF,x  ; 02:B4A7: ld e,(hl) / inc hl / ld d,(hl) / inc hl / ld (tmp_04),de - Vx kuli
	sta tmp_04
	lda SKY_LUT_GUN+1-OZ_OFF,x
	sta tmp_04+1
	lda SKY_LUT_GUN+2-OZ_OFF,x ; 02:B4AF: ... ld (tmp_06),de - Vy kuli
	sta tmp_06
	lda SKY_LUT_GUN+3-OZ_OFF,x
	sta tmp_07
	lda SKY_LUT_GUN+4-OZ_OFF,x ; 02:B4B7: ld e,(hl) / inc hl / ld d,(hl) - de = przesuniecie X kuli
	sta zg_de
	lda SKY_LUT_GUN+5-OZ_OFF,x
	sta zg_de+1
	lda SKY_LUT_GUN+6-OZ_OFF,x ; 02:B4BB: ld c,(hl) / inc hl / ld b,(hl) - bc = przesuniecie Y kuli
	sta zg_bc
	lda SKY_LUT_GUN+7-OZ_OFF,x
	sta zg_bc+1
	ldy #OB_X+1               ; 02:B4BF: exx / de = (ix+2/3) / hl = (sonic_x) / and a / sbc hl,de / ld a,h / exx
	sec                       ; (drugi zestaw rejestrow Z80 - DE, BC glownego zestawu zostaja dla strzalu)
	lda sonic_x
	sbc (zg_obj),y
	iny
	lda sonic_x+1
	sbc (zg_obj),y            ; A = starszy bajt (sonic_x - x)
	cmp SKY_LUT_GUN+8-OZ_OFF,x ; 02:B4CE: cp (hl) / ret nz
	bne sk3a_ret
	ldy #OB_Y+1               ; 02:B4D1: inc hl / exx / de = (ix+5/6) / hl = (sonic_y) / and a / sbc hl,de / ld a,h / exx
	sec
	lda sonic_y
	sbc (zg_obj),y
	iny
	lda sonic_y+1
	sbc (zg_obj),y            ; A = starszy bajt (sonic_y - y)
	cmp SKY_LUT_GUN+9-OZ_OFF,x ; 02:B4E0: cp (hl) / ret nz
	bne sk3a_ret
	jmp sky_shoot_fireball    ; 02:B4E2: call shoot_straight_fireball / ret
sk3a_ret
	rts

; ---------------------------------------------------------------------
; shoot_straight_fireball (02:B5C2): kula ognia $0D lecaca prosto z predkoscia tmp_04 / tmp_06 z punktu (x + DE, y + BC) obiektu
; zg_obj; efekt $01. Wejscia / wyjscia - naglowek pliku. Funkcja obiektu $0D (objfunc_0D_fireball) jest w banku 45.
; ---------------------------------------------------------------------
sky_shoot_fireball
	jsr spawn_object          ; 02:B5C2: push bc / push de / call spawn_object / pop de / pop bc / ret c (zg_bc, zg_de zachowane)
	bcs skf_ret
	ldy #OB_TYPE              ; 02:B5E0: xor a / (ix+0) = $0D (push ix / push hl ... pop ix: IX = nowy obiekt = zg_ptr)
	lda #$0D
	sta (zg_ptr),y
	lda #$00                  ; 02:B5E5: (ix+1) = a = 0
	iny
	sta (zg_ptr),y
	ldy #OB_X+1               ; 02:B5CD: hl = (ix+2/3) strzelajacego + de (16 bit) / ex de,hl; 02:B5E8: (ix+2) = e, (ix+3) = d
	clc
	lda (zg_obj),y
	adc zg_de
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta (zg_ptr),y
	lda #$00                  ; 02:B5EE: (ix+4) = 0
	iny
	sta (zg_ptr),y
	ldy #OB_Y+1               ; 02:B5D5: hl = (ix+5/6) + bc / ld c,l / ld b,h; 02:B5F1: (ix+5) = c, (ix+6) = b
	clc
	lda (zg_obj),y
	adc zg_bc
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	adc zg_bc+1
	sta (zg_ptr),y
	lda #$00                  ; 02:B5F7: (ix+17) = 0 ((ix+18) bez zmian)
	ldy #17
	sta (zg_ptr),y
	ldy #19                   ; 02:B5FA-02:B606: (ix+19) .. (ix+23) = 0
skf_clr
	sta (zg_ptr),y
	iny
	cpy #24
	bne skf_clr
	ldx #$00                  ; 02:B609: ld hl,(tmp_04) / bit 7,h / jr z / ld a,$FF - a = rozszerzenie znaku Vx
	ldy #OB_VX                ; 02:B612: (ix+7) = l
	lda tmp_04
	sta (zg_ptr),y
	iny                       ; 02:B615: (ix+8) = h
	lda tmp_04+1
	sta (zg_ptr),y            ; (sta nie zmienia N z lda)
	bpl skf_vxp
	ldx #$FF
skf_vxp                         ; 02:B612 @x_vel_was_positive: (ix+9) = a
	txa
	iny
	sta (zg_ptr),y
	ldx #$00                  ; 02:B61B: xor a / ld hl,(tmp_06) / bit 7,h / jr z / ld a,$FF
	iny                       ; 02:B625: (ix+10) = l
	lda tmp_06
	sta (zg_ptr),y
	iny                       ; 02:B628: (ix+11) = h
	lda tmp_07
	sta (zg_ptr),y
	bpl skf_vyp
	ldx #$FF
skf_vyp                         ; 02:B625 @y_vel_was_positive: (ix+12) = a
	txa
	iny
	sta (zg_ptr),y
	lda #$01                  ; 02:B62E: pop ix / ld a,$01 / rst $28 - efekt strzalu
	jmp play_sfx
skf_ret
	rts

; ---------------------------------------------------------------------
; objfunc_3B_platform_y_oscillate (02:B50E) - KOPIA przekladu z banku 11 (obj/objz.asm: objfunc_3B_platform_y_oscillate, oz_yosc)
; z unikalnymi etykietami (prefiks osc2_), logika identyczna. W banku 11 mapa SKY $B37B wypada na kodzie LAB - tu (bank 2) lezy pod
; nia prawdziwa SPRTAB_SKY_platform (ta sama co dla $38).
; Platforma kolebiaca sie w pionie (BRI, SKY). Bez kolizji z mapa (set 5), mapa wg g_tile_flags_index (1 = Bridge:
; SPRTAB_platform_y_oscillate_BRI $B5B5 - w strefach banku 2 nieosiagalne, inaczej SPRTAB_SKY_platform $B37B). Przyspieszenie Y
; +-$10 (24 bit): (ix+17) < tmp_08 ($50) w dol, dalej w gore; Vy ograniczone do +-$01FF (ponad: $0200 / $FE00 - jak oryginal);
; (ix+17) + 1, od $A0 znowu 0. Sonic na platformie (Vy >= 0, rozmiar 30 x 28, przesuniecie (2, 8)) - put_sonic_y_pos_on_platform
; z Vy platformy.
; ---------------------------------------------------------------------
objfunc_3B_platform_osc2
	ldy #OB_FLAGS             ; 02:B50E: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #<SKY_SPR_PLAT        ; 02:B512: ld hl,SPRTAB_SKY_platform
	ldx #>SKY_SPR_PLAT
	ldy g_tile_flags_index    ; 02:B515: ld a,(g_tile_flags_index) / cp $01 / jr nz @not_BRI
	cpy #$01
	bne osc2_map
	lda #<SKY_SPR_PLAT_BRI    ; 02:B51C: ld hl,SPRTAB_platform_y_oscillate_BRI
	ldx #>SKY_SPR_PLAT_BRI
osc2_map                        ; 02:B51F @not_BRI: (ix+15) = l, (ix+16) = h
	ldy #OB_SPRITE
	sta (zg_obj),y
	txa
	iny
	sta (zg_obj),y
	lda #$50                  ; 02:B525: ld a,$50 / ld (tmp_08),a
	sta tmp_08
	jsr osc2_yosc             ; 02:B52A: call @fn_do_y_oscillate
	ldy #17                   ; 02:B52D: inc (ix+17) / ld a,(ix+17) / cp $A0 / ret c
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$A0
	bcc osc2_ret
	lda #0                    ; 02:B536: (ix+17) = 0
	sta (zg_obj),y
osc2_ret
	rts

osc2_yosc                       ; 02:B53B @fn_do_y_oscillate: l = tmp_08
	lda #$10                  ; 02:B53F: de = $0010 (w dol), c = 0
	sta zg_de
	lda #0
	sta zg_de+1
	tax                       ; X = c
	ldy #17                   ; 02:B544: ld a,(ix+17) / cp l / jr c @accel_was_set_to_down
	lda (zg_obj),y
	cmp tmp_08                ; cp l: (ix+17) < l -> w dol
	bcc osc2_acc
	ldx #$FF                  ; 02:B54A: dec c
	lda #$F0                  ; 02:B54B: de = $FFF0
	sta zg_de
	lda #$FF
	sta zg_de+1
osc2_acc                        ; 02:B54E @accel_was_set_to_down: Vy (24 bit) += de, rozszerzenie znaku c (add hl,de / adc a,c)
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc zg_de
	sta (zg_obj),y            ; 02:B559: (ix+10) = l
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta (zg_obj),y            ; 02:B55C: (ix+11) = h
	sta zg_hl+1
	iny
	txa
	adc (zg_obj),y            ; adc a,c: A = (ix+12) + c + przeniesienie
	sta (zg_obj),y            ; 02:B55F: (ix+12) = a
	lda zg_hl+1               ; 02:B562: ld a,h / and a / jp p @vel_is_positive
	bpl osc2_pos
	lda zg_hl                 ; 02:B567: ujemne: hl = -hl (cpl, inc), |Vy| >> 8 >= 2 -> Vy = $FFFE00
	eor #$FF
	clc
	adc #1
	sta zg_hl
	lda zg_hl+1
	eor #$FF
	adc #0
	cmp #$02                  ; 02:B56E: ld a,h / cp $02 / jr c @continue_after_y_vel_clamp_check
	bcc osc2_cont
	ldy #OB_VY                ; 02:B573: (ix+10) = 0, (ix+11) = $FE, (ix+12) = $FF
	lda #$00
	sta (zg_obj),y
	lda #$FE
	iny
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	jmp osc2_cont             ; 02:B57F: jr @continue_after_y_vel_clamp_check
osc2_pos                        ; 02:B581 @vel_is_positive: cp $02 / jr c
	cmp #$02
	bcc osc2_cont
	ldy #OB_VY                ; 02:B585: Vy = $000200
	lda #$00
	sta (zg_obj),y
	lda #$02
	iny
	sta (zg_obj),y
	lda #$00
	iny
	sta (zg_obj),y
osc2_cont                       ; 02:B591 @continue_after_y_vel_clamp_check
	lda sonic_vel_y_hi
	bmi osc2_yret             ; and a / ret m
	ldy #OB_W                 ; 02:B596: (ix+13) = $1E, (ix+14) = $1C
	lda #$1E
	sta (zg_obj),y
	iny
	lda #$1C
	sta (zg_obj),y
	lda #$02                  ; 02:B59E: hl = $0802 / ld (tmp_06),hl
	sta tmp_06
	lda #$08
	sta tmp_07
	jsr zc_collide            ; 02:B5A4: call check_collision_with_sonic / ret c
	bcs osc2_yret
	ldy #OB_VY                ; 02:B5A8: de = Vy platformy (e, d), bc = $0010
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	lda #$10
	sta zg_bc
	lda #0
	sta zg_bc+1
	jmp zc_put                ; 02:B5B1: call put_sonic_y_pos_on_platform / ret
osc2_yret
	rts

; ---------------------------------------------------------------------
; objfunc_35_badnik_orbinaut (02:AE88) - KOPIA przekladu z banku 11 (obj/objz_lab_orbinaut.asm: objfunc_35_orbinaut, orn_jettison,
; orn_eject) z unikalnymi etykietami (prefiks orb2_), logika identyczna - takze test strefy Labyrinth (g_tile_flags_index = 3) przed
; wyrzutem kul: w SKY kule nigdy nie odlatuja (orb2_jettison konczy na 02:AFA3).
; Pola rekordu $35: (ix+17..20) kat czterech kul (0..$A3, przesuniecie bajtowe pary w LUT = kat & $FE; $FE = kula wyrzucona),
; (ix+21) licznik do wyrzutu (co tick z tick & 7 <> 0 + 1, do $C8), (ix+22) kierunek obrotu (+1 / $FF), (ix+24) b0 = zainicjowany.
; Bez kolizji z mapa (set 5). Rejestry: zg_bc = przesuniecie pola kuli 17..20 w rekordzie (B / HL = ix+17+i), zg_bc+1 = przesuniecie
; bajtowe pary w LUT (nie niszcza go zc_dspr, zc_collide, damage_sonic, spawn_object).
; Korpus z czterema kulami krazacymi wokol (kafel $24, rysowane draw_sprite).
; Pierwszy tick (b0 = 0): katy kul 0, $2A, $52, $7C, set 0. Strona Sonica (x - sonic_x, 16 bit; pozyczka - Sonic na
; prawo): na lewo -> Vx = $FFFFF8, mapa _left, tmp_08 = $FF80 (Vx wyrzuconej kuli), wyrzut kul, (ix+22) = 1;
; na prawo -> Vx = $000008, mapa _right, tmp_08 = $0080, wyrzut kul, (ix+22) = $FF. Korpus 28 x 28, trafienie
; (przesuniecie ($12, $12)) -> enemy_touched_sonic (tmp_00 = $1010). Dla kazdej kuli (kat <> $FE): sprite $24 w
; (x + dx, y + dy) (tmp_00/02 = x, y obiektu, tmp_04 = dx, tmp_06 = dy), kolizja: tmp_06 = dx + 2, (ix+13) = dx + 6,
; tmp_07 = dy + 2, (ix+14) = dy + 6 -> damage_sonic; kat + (ix+22) z zawinieciem ($FF -> $A3, $A4 -> 0).
; Na koniec: tick & 7 <> 0 i (ix+21) < $C8 -> (ix+21) + 1.
; ---------------------------------------------------------------------
objfunc_35_orbinaut2
	ldy #OB_FLAGS             ; 02:AE88: set 5,(ix+24); 02:AE8C: bit 0,(ix+24) / jr nz @already_initialised
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01
	bne orb2_inited
	ldy #17                   ; 02:AE92: (ix+17) = 0, (ix+18) = $2A, (ix+19) = $52, (ix+20) = $7C
	lda #$00
	sta (zg_obj),y
	iny
	lda #$2A
	sta (zg_obj),y
	iny
	lda #$52
	sta (zg_obj),y
	iny
	lda #$7C
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:AEA2: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
orb2_inited                     ; 02:AEA6 @already_initialised: hl = x - sonic_x (and a / sbc hl,de)
	ldy #OB_X+1
	sec
	lda (zg_obj),y
	sbc sonic_x
	iny
	lda (zg_obj),y
	sbc sonic_x+1
	bcc orb2_right            ; 02:AEB3: jr c @sonic_is_on_right (6502: C = 0 = pozyczka)
	ldy #OB_VX                ; 02:AEB5: Sonic na lewo: Vx = $FFFFF8, mapa _left
	lda #$F8
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_SPRITE            ; 02:AEC1: (ix+15/16) = SPRTAB_orbinaut_base_left
	lda #<SKY_SPR_ORB_L
	sta (zg_obj),y
	iny
	lda #>SKY_SPR_ORB_L
	sta (zg_obj),y
	lda #$80                  ; 02:AEC9: ld hl,$FF80 / ld (tmp_08),hl
	sta tmp_08
	lda #$FF
	sta tmp_08+1
	jsr orb2_jettison         ; 02:AECF: call @fn_maybe_jettison_balls
	ldy #22                   ; 02:AED2: (ix+22) = 1
	lda #$01
	sta (zg_obj),y
	jmp orb2_cont             ; 02:AED6: jr @sonic_was_on_the_left
orb2_right                      ; 02:AED8 @sonic_is_on_right: Vx = $000008, mapa _right
	ldy #OB_VX
	lda #$08
	sta (zg_obj),y
	lda #$00
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_SPRITE            ; 02:AEE4: (ix+15/16) = SPRTAB_orbinaut_base_right
	lda #<SKY_SPR_ORB_R
	sta (zg_obj),y
	iny
	lda #>SKY_SPR_ORB_R
	sta (zg_obj),y
	lda #$80                  ; 02:AEEC: ld hl,$0080 / ld (tmp_08),hl
	sta tmp_08
	lda #$00
	sta tmp_08+1
	jsr orb2_jettison         ; 02:AEF2: call @fn_maybe_jettison_balls
	ldy #22                   ; 02:AEF5: (ix+22) = $FF
	lda #$FF
	sta (zg_obj),y
orb2_cont                       ; 02:AEF9 @sonic_was_on_the_left: korpus (ix+13) = (ix+14) = $1C
	ldy #OB_W
	lda #$1C
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #$12                  ; 02:AF01: ld hl,$1212 / ld (tmp_06),hl
	sta tmp_06
	sta tmp_07
	jsr zc_collide            ; 02:AF07: check_collision_with_sonic
	lda #$10                  ; 02:AF0A: ld hl,$1010 / ld (tmp_00),hl (lda/sta nie zmieniaja C)
	sta tmp_00
	sta tmp_00+1
	bcs orb2_nohit            ; 02:AF10: call nc,enemy_touched_sonic
	jsr zc_enemy
orb2_nohit
	ldy #OB_X+1               ; 02:AF13: tmp_00 = x, tmp_02 = y (16 bit; po ewentualnym wybuchu - x, y przesuniete)
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
	lda #17                   ; 02:AF25: push ix / pop hl / hl += $11, b = 4: pola kul (ix+17)..(ix+20)
	sta zg_bc
orb2_ball                       ; 02:AF2E @each_ball_to_spin
	ldy zg_bc                 ; 02:AF30: ld a,(hl) / cp $FE / jr z: kula wyrzucona - bez rysowania i kolizji
	lda (zg_obj),y
	cmp #$FE
	beq orb2_skip
	and #$FE                  ; 02:AF35: e = kat & $FE, hl = LUT + de
	sta zg_bc+1
	tax
	lda SKY_ORBXY-OZ_OFF,x    ; 02:AF3F: ld (tmp_04),de z d = 0: tmp_04 = dx, tmp_05 = 0
	sta tmp_04
	lda SKY_ORBXY+1-OZ_OFF,x  ; 02:AF45: ld (tmp_06),de z d = 0: tmp_06 = dy, tmp_07 = 0
	sta tmp_06
	lda #0
	sta tmp_04+1
	sta tmp_07
	lda #$24                  ; 02:AF4A: draw_sprite kafla $24 w (tmp_00 + tmp_04, tmp_02 + tmp_06)
	jsr zc_dspr
	ldx zg_bc+1               ; 02:AF4F: pop hl: a = dx + 2 -> tmp_06 (sam bajt), (ix+13) = a + 4
	lda SKY_ORBXY-OZ_OFF,x
	clc
	adc #2
	sta tmp_06
	clc
	adc #4
	ldy #OB_W
	sta (zg_obj),y
	lda SKY_ORBXY+1-OZ_OFF,x  ; 02:AF5B: a = dy + 2 -> tmp_07, (ix+14) = a + 4
	clc
	adc #2
	sta tmp_07
	clc
	adc #4
	ldy #OB_H
	sta (zg_obj),y
	jsr zc_collide            ; 02:AF67: check_collision_with_sonic / call nc,damage_sonic
	bcs orb2_skip
	jsr damage_sonic
orb2_skip                       ; 02:AF6D @skip_collision_with_missing_ball: obrot kuli
	ldy zg_bc
	lda (zg_obj),y
	cmp #$FE
	beq orb2_store            ; 02:AF72: jr z @update_and_handle_next_ball ((hl) = $FE bez zmian)
	ldy #22                   ; 02:AF74: add a,(ix+22) (8 bit)
	clc
	adc (zg_obj),y
	cmp #$FF                  ; 02:AF77: cp $FF / jr nz: obrot w strone malejaca - zawiniecie $FF -> $A3
	bne orb2_notff
	lda #$A3
	bne orb2_store            ; zawsze
orb2_notff                      ; 02:AF7F @spin_direction_is_for_moving_left: cp $A4 / jr nz, xor a - zawiniecie $A4 -> 0
	cmp #$A4
	bne orb2_store
	lda #$00
orb2_store                      ; 02:AF84 @update_and_handle_next_ball: ld (hl),a / inc hl / djnz
	ldy zg_bc
	sta (zg_obj),y
	inc zg_bc
	lda zg_bc
	cmp #21
	bne orb2_ball
	lda g_global_tick_counter ; 02:AF88: and $07 / ret z
	and #$07
	beq orb2_ret
	ldy #21                   ; 02:AF8E: ld a,(ix+21) / cp $C8 / ret nc
	lda (zg_obj),y
	cmp #$C8
	bcs orb2_ret
	adc #1                    ; 02:AF94: inc (ix+21) (C = 0 po cmp z wynikiem "mniejsze")
	sta (zg_obj),y
orb2_ret
	rts

; ---------------------------------------------------------------------
; orb2_jettison (@fn_maybe_jettison_balls 02:AF98): tylko gdy (ix+21) = $C8, strefa Labyrinth (g_tile_flags_index = 3)
; i Sonic w pionie w (y - 48, y + $2C] (16 bit): kazda kula o kacie dokladnie $4A -> orb2_eject. tmp_08 = Vx kuli.
; ---------------------------------------------------------------------
orb2_jettison
	ldy #21                   ; 02:AF98: ld a,(ix+21) / cp $C8 / ret nz
	lda (zg_obj),y
	cmp #$C8
	bne orb2_jret
	lda g_tile_flags_index    ; 02:AF9E: cp $03 / ret nz (SKY: zawsze tu koniec)
	cmp #$03
	bne orb2_jret
	ldy #OB_Y+1               ; 02:AFA4: hl = y + $FFD0 (y - 48, 16 bit z zawinieciem), de = sonic_y
	clc
	lda (zg_obj),y
	adc #<$FFD0
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #>$FFD0
	sta zg_hl+1
	sec                       ; 02:AFB2: and a / sbc hl,de / ret nc: y - 48 >= sonic_y (6502 C = 1) -> koniec
	lda zg_hl
	sbc sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcs orb2_jret
	ldy #OB_Y+1               ; 02:AFB6: hl = y + $002C
	clc
	lda (zg_obj),y
	adc #$2C
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	sec                       ; 02:AFC0: sbc hl,de / ret c: y + $2C < sonic_y (6502 C = 0) -> koniec
	lda zg_hl
	sbc sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcc orb2_jret
	lda #17                   ; 02:AFC4: hl = ix + $11, b = 4
	sta zg_bc
orb2_jeach                      ; 02:AFCD @each_ball_to_jettison: ld a,(hl) / cp $4A / call z,@fn_jettison_ball
	ldy zg_bc
	lda (zg_obj),y
	cmp #$4A
	bne orb2_jnext
	jsr orb2_eject
orb2_jnext                      ; 02:AFD7: inc hl / djnz
	inc zg_bc
	lda zg_bc
	cmp #21
	bne orb2_jeach
orb2_jret
	rts

; ---------------------------------------------------------------------
; orb2_eject (@fn_jettison_ball 02:AFDB): kula zg_bc (przesuniecie pola 17..20) := $FE (takze gdy brak wolnego slotu),
; spawn_object; nowy obiekt $36: (ix+1) = 0, x = x + $12, (ix+4) = 0, y = y + $1E, Vx = tmp_08 (16 bit, bajt najwyzszy
; z bitu 7 tmp_09), Vy = 0. Pozostale pola slotu bez zmian (oryginal ich nie czysci).
; ---------------------------------------------------------------------
orb2_eject
	ldy zg_bc                 ; 02:AFDB: ld (hl),$FE
	lda #$FE
	sta (zg_obj),y
	jsr spawn_object          ; 02:AFDD: call spawn_object / ret c: brak wolnego slotu
	bcs orb2_eret
	ldy #OB_TYPE              ; 02:AFF2: (ix+0) = $36, (ix+1) = 0 (a = 0 z xor a)
	lda #$36
	sta (zg_ptr),y
	lda #$00
	iny
	sta (zg_ptr),y
	ldy #OB_X+1               ; 02:AFFA: x = de + $0012 (de = x Orbinauta)
	clc
	lda (zg_obj),y
	adc #$12
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_ptr),y
	lda #$00                  ; 02:B004: (ix+4) = 0
	iny
	sta (zg_ptr),y
	ldy #OB_Y+1               ; 02:B007: y = bc + $001E (bc = y Orbinauta)
	clc
	lda (zg_obj),y
	adc #$1E
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_ptr),y
	ldy #OB_VX                ; 02:B011: Vx = tmp_08 (l, h), (ix+9) = $FF gdy bit 7,h, inaczej 0
	lda tmp_08
	sta (zg_ptr),y
	iny
	lda tmp_08+1
	sta (zg_ptr),y
	ldx #$00
	and #$80
	beq orb2_evxpos           ; 02:B01D: @ball_is_to_move_right
	ldx #$FF
orb2_evxpos
	txa
	iny
	sta (zg_ptr),y
	lda #$00                  ; 02:B024: Vy = 0
	iny
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
orb2_eret
	rts

; ---------------------------------------------------------------------
; objfunc_36_badnik_orbinaut_ejected_ball (02:B0F4) - KOPIA przekladu z banku 11 (objfunc_36_orbinaut_ball), logika identyczna
; (w SKY nie powstaje - zostaje dla porzadku tablicy typow). Wyrzucona kula (bez kolizji z mapa, set 5), ruch tylko z Vx
; nadanej przy wyrzucie (obj_motion). Mapa 0, 4 x 10, trafienie (przesuniecie (2, 6)) -> damage_sonic. tmp_00 = x,
; tmp_02 = y; x poza (kamera X - 16, kamera X + $110] albo y poza (kamera Y - 16, kamera Y + $D0] -> usuniecie
; (typ $FF; tmp_02 nie ustawiane, gdy odpada juz po x); inaczej sprite $24 w (x, y) (tmp_04 = tmp_06 = 0).
; ---------------------------------------------------------------------
objfunc_36_orbinaut_ball2
	ldy #OB_FLAGS             ; 02:B0F4: set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #$00                  ; 02:B0F8: (ix+15/16) = 0: obiekt bez mapy (kula rysowana draw_sprite)
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_W                 ; 02:B100: (ix+13) = 4, (ix+14) = $0A
	lda #$04
	sta (zg_obj),y
	iny
	lda #$0A
	sta (zg_obj),y
	lda #$02                  ; 02:B108: ld hl,$0602 / ld (tmp_06),hl: tmp_06 = 2, tmp_07 = 6
	sta tmp_06
	lda #$06
	sta tmp_07
	jsr zc_collide            ; 02:B10E: check_collision_with_sonic / call nc,damage_sonic
	bcs orb2_bnohit
	jsr damage_sonic
orb2_bnohit
	ldy #OB_X+1               ; 02:B114: tmp_00 = x, de = x (ex de,hl)
	lda (zg_obj),y
	sta tmp_00
	sta zg_de
	iny
	lda (zg_obj),y
	sta tmp_00+1
	sta zg_de+1
	clc                       ; 02:B11E: hl = kamera X + $FFF0 (16 bit z zawinieciem)
	lda g_level_scroll_x_pix_lo
	adc #<$FFF0
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #>$FFF0
	sta zg_hl+1
	sec                       ; 02:B125: and a / sbc hl,de / jr nc: hl >= x (6502 C = 1) -> @destroy_this_object
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs orb2_bdestroy
	clc                       ; 02:B12A: hl = kamera X + $0110
	lda g_level_scroll_x_pix_lo
	adc #<$0110
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #>$0110
	sta zg_hl+1
	sec                       ; 02:B131: jr c: hl < x (6502 C = 0) -> @destroy_this_object
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcc orb2_bdestroy
	ldy #OB_Y+1               ; 02:B136: tmp_02 = y, de = y
	lda (zg_obj),y
	sta tmp_02
	sta zg_de
	iny
	lda (zg_obj),y
	sta tmp_02+1
	sta zg_de+1
	clc                       ; 02:B140: hl = kamera Y + $FFF0
	lda g_level_scroll_y_pix_lo
	adc #<$FFF0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #>$FFF0
	sta zg_hl+1
	sec                       ; 02:B147: jr nc -> @destroy_this_object
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs orb2_bdestroy
	clc                       ; 02:B14C: hl = kamera Y + $00D0
	lda g_level_scroll_y_pix_lo
	adc #<$00D0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #>$00D0
	sta zg_hl+1
	sec                       ; 02:B153: jr c -> @destroy_this_object
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcc orb2_bdestroy
	lda #$00                  ; 02:B158: tmp_04 = tmp_06 = $0000 (po 16 bit)
	sta tmp_04
	sta tmp_04+1
	sta tmp_06
	sta tmp_07
	lda #$24                  ; 02:B161: draw_sprite kafla $24 w (x, y)
	jmp zc_dspr
orb2_bdestroy                   ; 02:B167 @destroy_this_object: (ix+0) = $FF
	lda #$FF
	ldy #OB_TYPE
	sta (zg_obj),y
	rts
