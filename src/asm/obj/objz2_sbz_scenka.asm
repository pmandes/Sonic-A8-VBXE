; =====================================================================
;  obj/objz2_sbz_scenka.asm - M6.9 Scrap Brain: $22 scenka konca SBZ3 - Robotnik ucieka winda (bank obiektow strefy 2 PB_OBJZ2,
;  bank 2, okno $4000-$7FFF; dolaczany z game.asm w sekcji banku 2).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny):
;   objfunc_22_SCR_boss               02:A7ED - 02:A9B6  -> objfunc_22_sbz3_scene
;   LUT_SCR_boss_anim_running         02:A9B7 - 02:A9BF  (sekwencja biegu: klatki 3, 4, 5, 4; czasy 8, 7, 8, 7; $FF)
;   SPRTAB_SCR_boss_platform          02:A9C0 - 02:A9C6  (mapa platformy windy: $74 $76 $76 $78 $FF $FF / $FF - 4 sprite'y)
;   SPRTAB_robotnik_idling (+ klatki) 02:BAF9 - 02:BB64  (w danych bossa SKY3; klatka 0 = $BAF9 stoi, 3 = $BB2F, 4 = $BB41,
;                                                         5 = $BB53 - bieg)
;  Dane banku 2 ROM-u (OZ2_SPAN13 = $A9B7-$A9C6, OZ2_SPAN14 = $BAF9-$BB64 w objdata.inc; tools/extract_sms.py OBJZ2_SPANS) leza
;  w tym banku pod adresem SMS - OZ_OFF; kod czyta je przez "ETYKIETA-OZ_OFF", a do rekordu (mapa ix+15/16) i do zd_map (zc_dss)
;  trafiaja adresy SMS ($A9C0, $BAF9...) - objz_mapcopy kopiuje mape z tego banku.
;  Wolane: kod tego banku (oz2_dfa = do_framed_animation 01:7C41, obj/objz2.asm), kod rezydentny (play_music = rst $18,
;  play_sfx = rst $28; game/objcom.asm) i stuby zc_* do banku 45 (game/objcom.asm): zc_robotart (load_art ART_0C_EF3F ->
;  robot_load_art, v_art_req = 4), zc_slc (set_locked_camera_target 01:7C8C), zc_dss (draw_sprite_string 00:350F z mapa z banku
;  strefy: zd_map = adres SMS mapy, zd_x / zd_y = pozycja ekranowa).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl; zs_hl / zs_de = wejscie zc_slc (HL / DE); zd_x / zd_y / zd_map
;  = HL / DE / BC draw_sprite_string. Przeniesienie: Z80 C = 1 po sbc (pozyczka) <=> 6502 C = 0.
; =====================================================================
; adresy SMS danych (zakresy OZ2_SPAN13, OZ2_SPAN14)
LUT_SCN_RUN     = $A9B7   ; LUT_SCR_boss_anim_running: (3, 8), (4, 7), (5, 8), (4, 7), $FF - klatka, czas (oz2_dfa: adres okna)
SPR_ROBO_PLAT   = $A9C0   ; SPRTAB_SCR_boss_platform: jeden wiersz $74 $76 $76 $78 (+ $FF $FF pominiete), drugi wiersz od $FF - koniec
SPR_ROBO_IDLE   = $BAF9   ; SPRTAB_robotnik_idling: baza map Robotnika (klatka = 18 B; klatka 0 - stoi)

; ---------------------------------------------------------------------
; objfunc_22_SCR_boss (02:A7ED): scenka konca SBZ3 - nie ma walki ani kapsuly. Obiekt (1152, 640) = Robotnik, 30 x 47
; ((ix+13/14) = $1E/$2F co tick), kolizje z mapa WLACZONE (oryginal nie robi set 5,(ix+24)); platforma windy rysowana osobno
; (draw_sprite_string) w x = $05A0, y ekranu = $02AF - (ix+17) - kamera Y; y Robotnika co tick = $0280 - (ix+17).
; Pierwszy tick (b0 flag = 0): granice x0 = $0340, x1 = $0540, y0 = y1 = kamera Y, cel kamery Y = $0220 (cel X bez zmian),
; load_art ART_0C_EF3F -> kafle sprite'ow $00-$7F (zc_robotart; bez set 1 iy_09 - dekompresja z przerwaniami, jak boss GHZ3),
; paleta PAL2_boss (signal_load_palettes A = 2), muzyka $0B (rst $18), set 0.
; Fazy wg flag (ix+24):
;  b1 = 0 - bieg: x0 = kamera X (lewa granica idzie za kamera), animacja biegu (oz2_dfa); Vx = $000080 (0,5 px/tick), a gdy Sonic
;      nie leci w lewo (b7 Vx lo = 0) i 0 <= x - sonic_x < $40 (16 bit bez znaku) - Vx = (Vx sub Sonica, Vx lo Sonica + 1, 0).
;      x >= $05A0: Vx = 0, Vx Sonica = 0 (24 bit), set 1.
;  b2 = 0 - winda w gore: set_locked_camera_target($0530, $0220), wejscie = $FF (blokada), x = $05A0.00, mapa = stoi,
;      inc (ix+17); przy $C0 set 2.
;  b3 = 0 - winda w dol bez Robotnika: wejscie = $FF, mapa = 0 (niewidoczny), dec (ix+17); przy 0 set 3.
;  b4 = 0 - czeka na Sonica: Sonic w x $0597..$05C0 (bez znaku); przy (ix+17) = 0 dodatkowo y >= $028D (inaczej czeka) i wtedy
;      Vx Sonica = 0. Sonic na platformie: flagi Sonica = $80 (na ziemi), sonic_x = $05A0, wejscie = $FF, sonic_y_sub = 0,
;      sonic_y = $028E - (ix+17), Vy Sonica = g_sonic_bounce_vel_y (24 bit), inc (ix+17); przy $C0: sonic_x = kamera X + 256
;      (inc h), set 4, muzyka $09, g_signpost_tickdown_counter = $A0, set 1 iy_06 (koniec aktu) i RET - w tym ticku bez platformy.
;  b4 = 1 - koniec aktu: (ix+17) > 0 -> dec (platforma zjezdza bez Sonica).
; Wspolny koniec (wszystkie fazy poza ticku konca jazdy): y Robotnika, platforma (zc_dss), SFX $19 gdy (ix+17) & $1F = $0F.
; Pola rekordu: (ix+17) wysokosc windy 0..$C0, (ix+22/23) animacja (oz2_dfa), (ix+24) b0..b4 fazy.
; ---------------------------------------------------------------------
objfunc_22_sbz3_scene
	ldy #OB_W                 ; 02:A7ED: ld (ix+13),$1E / ld (ix+14),$2F
	lda #$1E
	sta (zg_obj),y
	iny
	lda #$2F
	sta (zg_obj),y
	ldy #OB_FLAGS             ; 02:A7F5: bit 0,(ix+24) / jr nz @already_initialised
	lda (zg_obj),y
	and #$01
	jne scn_init_done
	lda #<$0340               ; 02:A7FB: ld hl,$0340 / ld (g_level_limit_x0),hl
	sta g_level_limit_x0
	lda #>$0340
	sta g_level_limit_x0+1
	lda #<$0540               ; 02:A801: ld hl,$0540 / ld (g_level_limit_x1),hl
	sta g_level_limit_x1
	lda #>$0540
	sta g_level_limit_x1+1
	lda g_level_scroll_y_pix_lo ; 02:A807: ld hl,(g_level_scroll_y_pix_lo) / ld (g_level_limit_y0),hl / ld (g_level_limit_y1),hl
	sta g_level_limit_y0
	sta g_level_limit_y1
	lda g_level_scroll_y_pix_lo+1
	sta g_level_limit_y0+1
	sta g_level_limit_y1+1
	lda #<$0220               ; 02:A810: ld hl,$0220 / ld (g_level_camera_lock_towards_y),hl
	sta g_level_camera_lock_towards_y
	lda #>$0220
	sta g_level_camera_lock_towards_y+1
	jsr zc_robotart           ; 02:A816: ld hl,ART_0C_EF3F / ld de,$2000 / ld a,$0C / call load_art (grafika Robotnika i windy,
	                          ; kafle sprite'ow $00-$7F; v_art_req = 4; iy_09 b1 = 0 - IRQ w trakcie; tmp_00..tmp_07 jak po load_art)
	lda iy_00                 ; 02:A821: ld hl,PAL2_boss / ld a,$02 / call signal_load_palettes (00:0333): set 3,(iy+iy_00),
	ora #$08                  ; (g_SIG00b3_palettes_present) = 2 (sprite'y), (g_SIG00b3_palette_addr) = PAL2_boss
	sta iy_00
	lda #$02
	sta g_SIG00b3_palettes_present
	lda #<PAL2_BOSS
	sta g_SIG00b3_palette_addr
	lda #>PAL2_BOSS
	sta g_SIG00b3_palette_addr+1
	lda #$0B                  ; 02:A829: ld a,$0B / rst $18 - muzyka bossa
	jsr play_music
	ldy #OB_FLAGS             ; 02:A82C: set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
scn_init_done                   ; 02:A830 @already_initialised: bit 1,(ix+24) / jr nz @finished_running_to_platform
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02
	jne scn_ph2
	; --- faza 1: bieg Robotnika do windy ---
	lda g_level_scroll_x_pix_lo ; 02:A836: ld hl,(g_level_scroll_x_pix_lo) / ld (g_level_limit_x0),hl - lewa granica = kamera X
	sta g_level_limit_x0
	lda g_level_scroll_x_pix_lo+1
	sta g_level_limit_x0+1
	lda #<SPR_ROBO_IDLE       ; 02:A83C: ld de,SPRTAB_robotnik_idling (baza map - adres SMS)
	sta zg_de
	lda #>SPR_ROBO_IDLE
	sta zg_de+1
	lda #<[LUT_SCN_RUN-OZ_OFF] ; 02:A83F: ld bc,LUT_SCR_boss_anim_running (sekwencja - adres okna)
	sta zg_bc
	lda #>[LUT_SCN_RUN-OZ_OFF]
	sta zg_bc+1
	jsr oz2_dfa               ; 02:A842: call do_framed_animation
	ldy #OB_X+1               ; 02:A845: hl = x (ix+2/3); de = sonic_x; xor a / sbc hl,de - hl = x - sonic_x (16 bit, C = 0)
	sec
	lda (zg_obj),y
	sbc sonic_x
	sta zg_hl
	iny
	lda (zg_obj),y
	sbc sonic_x+1
	sta zg_hl+1
	lda sonic_vel_x_sub       ; 02:A852: ld de,$0040 / xor a / ld bc,(sonic_vel_x_sub): c = Vx sub Sonica, b = Vx lo (piksele)
	sta zg_bc
	lda sonic_vel_x
	sta zg_bc+1
	bmi scn_slow              ; 02:A85A: bit 7,b / jr nz @sonic_is_moving_left
	sec                       ; 02:A85E: sbc hl,de (C = 0 po xor a): hl - $0040; pozyczka (6502 C = 0) <=> x - sonic_x < $40
	lda zg_hl                 ; (bez znaku: Sonic za Robotnikiem dalej niz 63 px albo przed nim - bez pozyczki)
	sbc #<$0040
	lda zg_hl+1
	sbc #>$0040
	bcc scn_vx                ; 02:A860: jr c @sonic_was_moving_right - bc = Vx Sonica (Robotnik o 1 px/tick szybszy)
scn_slow                        ; 02:A862 @sonic_is_moving_left: ld bc,$FF80 (po inc b: Vx = $000080 = 0,5 px/tick)
	lda #<$FF80
	sta zg_bc
	lda #>$FF80
	sta zg_bc+1
scn_vx                          ; 02:A865 @sonic_was_moving_right: inc b (8 bit); (ix+7) = c, (ix+8) = b, (ix+9) = a (= 0 z xor a)
	ldy #OB_VX
	lda zg_bc
	sta (zg_obj),y
	iny
	ldx zg_bc+1
	inx
	txa
	sta (zg_obj),y
	iny
	lda #0
	sta (zg_obj),y
	ldy #OB_X+1               ; 02:A86F: hl = x; ld de,$05A0 / xor a / sbc hl,de / jp c @draw...: x < $05A0 - biegnie dalej
	lda (zg_obj),y
	cmp #<$05A0
	iny
	lda (zg_obj),y
	sbc #>$05A0
	jcc scn_draw
	lda #0                    ; 02:A87E: x >= $05A0 - Robotnik przy windzie: ld l,a / ld h,a (a = 0)
	ldy #OB_VX                ; 02:A880: (ix+7) = (ix+8) = 0 - stoi ((ix+9) = 0 juz wyzej)
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	sta sonic_vel_x_sub       ; 02:A886: ld (sonic_vel_x_sub),hl / ld (sonic_vel_x_hi),a - Vx Sonica = 0 (24 bit)
	sta sonic_vel_x
	sta sonic_vel_x_hi
	ldy #OB_FLAGS             ; 02:A88C: set 1,(ix+24) - koniec biegu
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
	jmp scn_draw              ; 02:A890: jp @draw_platform_and_maybe_play_platform_sound

scn_ph2                         ; 02:A893 @finished_running_to_platform: bit 2,(ix+24) / jr nz @already_rode_platform_up
	lda (zg_obj),y            ; (Y = OB_FLAGS z testu b1)
	and #$04
	jne scn_ph3
	; --- faza 2: Robotnik wjezdza winda w gore ---
	lda #<$0530               ; 02:A899: ld hl,$0530 / ld de,$0220 / call set_locked_camera_target (01:7C8C): cel kamery
	sta zs_hl                 ; ($0530, $0220), granice x0 = x1 = kamera X, y0 = y1 = kamera Y
	lda #>$0530
	sta zs_hl+1
	lda #<$0220
	sta zs_de
	lda #>$0220
	sta zs_de+1
	jsr zc_slc
	lda #$FF                  ; 02:A8A2: ld (iy+g_inputs_player_1),$FF - wejscie zablokowane (nic nie wcisniete)
	sta g_inputs_player_1
	ldy #OB_X                 ; 02:A8A6: ld hl,$05A0 / (ix+1) = 0, (ix+2) = l, (ix+3) = h - x = $05A0.00
	lda #0
	sta (zg_obj),y
	iny
	lda #<$05A0
	sta (zg_obj),y
	iny
	lda #>$05A0
	sta (zg_obj),y
	ldy #OB_SPRITE            ; 02:A8B3: (ix+15/16) = SPRTAB_robotnik_idling (adres SMS) - Robotnik stoi na windzie
	lda #<SPR_ROBO_IDLE
	sta (zg_obj),y
	iny
	lda #>SPR_ROBO_IDLE
	sta (zg_obj),y
	ldy #17                   ; 02:A8BB: inc (ix+17) / ld a,(ix+17) / cp $C0 / jp c @draw...
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$C0
	jcc scn_draw
	ldy #OB_FLAGS             ; 02:A8C6: set 2,(ix+24) - winda na gorze
	lda (zg_obj),y
	ora #$04
	sta (zg_obj),y
	jmp scn_draw              ; 02:A8CA: jp @draw_platform_and_maybe_play_platform_sound

scn_ph3                         ; 02:A8CD @already_rode_platform_up: bit 3,(ix+24) / jr nz @already_lowered_platform_for_sonic
	lda (zg_obj),y            ; (Y = OB_FLAGS)
	and #$08
	jne scn_ph4
	; --- faza 3: pusta winda zjezdza po Sonica ---
	lda #$FF                  ; 02:A8D3: ld (iy+g_inputs_player_1),$FF
	sta g_inputs_player_1
	lda #0                    ; 02:A8D7: xor a / (ix+15) = (ix+16) = 0 - Robotnik zniknal (odjechal)
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #17                   ; 02:A8DE: dec (ix+17) / jp nz @draw...
	lda (zg_obj),y
	sec
	sbc #1
	sta (zg_obj),y
	jne scn_draw
	ldy #OB_FLAGS             ; 02:A8E4: set 3,(ix+24) - winda na dole
	lda (zg_obj),y
	ora #$08
	sta (zg_obj),y
	jmp scn_draw              ; 02:A8E8: jp @draw_platform_and_maybe_play_platform_sound

scn_ph4                         ; 02:A8EB @already_lowered_platform_for_sonic: bit 4,(ix+24) / jr nz @sonic_already_landed_...
	lda (zg_obj),y            ; (Y = OB_FLAGS)
	and #$10
	jne scn_ph5
	; --- faza 4: Sonic na platformie - wjazd w gore ---
	lda #<$0596               ; 02:A8F1: de = sonic_x; ld hl,$0596 / and a / sbc hl,de / jr nc @draw...
	cmp sonic_x               ; bez pozyczki (6502 C = 1): sonic_x <= $0596 - Sonic jeszcze nie na platformie
	lda #>$0596
	sbc sonic_x+1
	jcs scn_draw
	lda #<$05C0               ; 02:A8FD: ld hl,$05C0 / xor a / sbc hl,de / jr c @draw...
	cmp sonic_x               ; pozyczka (6502 C = 0): sonic_x > $05C0 - za platforma
	lda #>$05C0
	sbc sonic_x+1
	jcc scn_draw
	ldy #17                   ; 02:A905: or (ix+17) (a = 0 z xor a) / jr nz @platform_not_at_bottom_yet
	lda (zg_obj),y
	bne scn_notbot
	lda sonic_y               ; 02:A90A: ld hl,(sonic_y) / ld de,$028D / xor a / sbc hl,de / jr c @draw...
	cmp #<$028D               ; pozyczka (6502 C = 0): sonic_y < $028D - Sonic nad platforma (w skoku) - czeka
	lda sonic_y+1
	sbc #>$028D
	jcc scn_draw
	lda #0                    ; 02:A915: ld l,a / ld h,a (a = 0) / ld (sonic_vel_x_sub),hl / ld (sonic_vel_x_hi),a - Vx Sonica = 0
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
scn_notbot                      ; 02:A91D @platform_not_at_bottom_yet
	lda #$80                  ; ld a,$80 / ld (sonic_flags_ix_24),a - Sonic na ziemi (pozostale bity skasowane)
	sta sonic_flags_ix_24
	lda #<$05A0               ; 02:A922: ld hl,$05A0 / ld (sonic_x),hl (subpiksel bez zmian)
	sta sonic_x
	lda #>$05A0
	sta sonic_x+1
	lda #$FF                  ; 02:A928: ld (iy+g_inputs_player_1),$FF
	sta g_inputs_player_1
	ldy #17                   ; 02:A92C: e = (ix+17), d = 0; ld hl,$028E / xor a / sbc hl,de - hl = $028E - (ix+17)
	sec
	lda #<$028E
	sbc (zg_obj),y
	sta zg_hl
	lda #>$028E
	sbc #0
	sta zg_hl+1
	lda #0                    ; 02:A937: ld (sonic_y_sub),a (a = 0) / ld (sonic_y),hl
	sta sonic_y_sub
	lda zg_hl
	sta sonic_y
	lda zg_hl+1
	sta sonic_y+1
	lda g_sonic_bounce_vel_y_sub ; 02:A93D: a = (g_sonic_bounce_vel_y_pix_hi), hl = (g_sonic_bounce_vel_y_sub);
	sta sonic_vel_y_sub       ; ld (sonic_vel_y_sub),hl / ld (sonic_vel_y_hi),a - Vy Sonica = g_sonic_bounce_vel_y (24 bit)
	lda g_sonic_bounce_vel_y_sub+1
	sta sonic_vel_y
	lda g_sonic_bounce_vel_y_sub+2
	sta sonic_vel_y_hi
	ldy #17                   ; 02:A949: inc (ix+17) / ld a,(ix+17) / cp $C0 / jr nz @draw...
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$C0
	jne scn_draw
	lda g_level_scroll_x_pix_lo ; 02:A953: ld hl,(g_level_scroll_x_pix_lo) / inc h / ld (sonic_x),hl - Sonic za prawa krawedz
	sta sonic_x               ; ekranu (kamera X + 256; inc h - 8 bit)
	ldx g_level_scroll_x_pix_lo+1
	inx
	stx sonic_x+1
	ldy #OB_FLAGS             ; 02:A95A: set 4,(ix+24)
	lda (zg_obj),y
	ora #$10
	sta (zg_obj),y
	lda #$09                  ; 02:A95E: ld a,$09 / rst $18 - muzyka konca aktu
	jsr play_music
	lda #$A0                  ; 02:A961: ld a,$A0 / ld (g_signpost_tickdown_counter),a
	sta g_signpost_tickdown_counter
	lda iy_06_lvflag01        ; 02:A966: set 1,(iy+iy_06_lvflag01) - koniec aktu (Sonic idzie w prawo)
	ora #$02
	sta iy_06_lvflag01
	rts                       ; 02:A96A: ret - w tym ticku bez platformy i SFX

scn_ph5                         ; 02:A96B @sonic_already_landed_on_platform_and_level_is_ending: ld a,(ix+17) / and a / jr z
	ldy #17
	lda (zg_obj),y
	beq scn_draw
	sec                       ; 02:A971: dec (ix+17) - winda zjezdza
	sbc #1
	sta (zg_obj),y

scn_draw                        ; 02:A974 @draw_platform_and_maybe_play_platform_sound
	ldy #17                   ; e = (ix+17), d = 0 (d nie zapisywane - sbc #0 nizej)
	lda (zg_obj),y
	sta zg_de
	ldy #OB_Y                 ; 02:A979: ld hl,$0280 / xor a / sbc hl,de; (ix+4) = a (= 0), (ix+5) = l, (ix+6) = h
	lda #0                    ; - y Robotnika = $0280 - (ix+17) (stoi na platformie)
	sta (zg_obj),y
	sec
	lda #<$0280
	sbc zg_de
	iny
	sta (zg_obj),y
	lda #>$0280
	sbc #0
	iny
	sta (zg_obj),y
	sec                       ; 02:A988: ld hl,$02AF / and a / sbc hl,de - hl = $02AF - (ix+17)
	lda #<$02AF
	sbc zg_de
	tax                       ; l
	lda #>$02AF
	sbc #0
	sta zd_y+1                ; h
	sec                       ; 02:A993: ld bc,(g_level_scroll_y_pix_lo) / and a / sbc hl,bc / ex de,hl - de = y ekranowe platformy
	txa
	sbc g_level_scroll_y_pix_lo
	sta zd_y
	lda zd_y+1
	sbc g_level_scroll_y_pix_lo+1
	sta zd_y+1
	sec                       ; 02:A99B: ld hl,$05A0 / ld bc,(g_level_scroll_x_pix_lo) / and a / sbc hl,bc - hl = x ekranowe
	lda #<$05A0
	sbc g_level_scroll_x_pix_lo
	sta zd_x
	lda #>$05A0
	sbc g_level_scroll_x_pix_lo+1
	sta zd_x+1
	lda #<SPR_ROBO_PLAT       ; 02:A9A5: ld bc,SPRTAB_SCR_boss_platform (adres SMS - zc_dss kopiuje mape z tego banku)
	sta zd_map
	lda #>SPR_ROBO_PLAT
	sta zd_map+1
	jsr zc_dss                ; 02:A9A8: call draw_sprite_string (00:350F; tmp_06 = x ekranowe - jak oryginal)
	ldy #17                   ; 02:A9AB: ld a,(ix+17) / and $1F / cp $0F / ret nz
	lda (zg_obj),y
	and #$1F
	cmp #$0F
	bne scn_ret
	lda #$19                  ; 02:A9B3: ld a,$19 / rst $28 - odglos windy (co 32 ticki jazdy) / ret
	jmp play_sfx
scn_ret
	rts
