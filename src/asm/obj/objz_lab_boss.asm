; =====================================================================
;  obj/objz_lab_boss.asm - M6.8 Labyrinth: $49 boss LAB3, $2F rakieta bossa, $2A dym rakiety (bank obiektow strefy PB_OBJZ, bank 11).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny):
;   objfunc_49_LAB3_boss              02:9267 - 02:947A  -> objfunc_49_LAB3_boss (+ lb3_vy: pomocnik zapisu Vy)
;   objfunc_2F_LAB3_boss_rocket       02:94A5 - 02:9687  -> objfunc_2F_LAB3_rocket (+ lbr_clamp: 02:956B-02:9589 i 02:95C8-02:95E6)
;   objfunc_2A_LAB3_boss_rocket_puff  02:96A8 - 02:96F4  -> objfunc_2A_rocket_puff
;  Dane banku 2 ROM-u (OZ_SPAN: tools/extract_sms.py OBJZ_SPANS) leza w tym banku pod adresem SMS - OZ_OFF; kod czyta je przez
;  "ETYKIETA-OZ_OFF", a do rekordow obiektow (mapa sprite'ow ix+15/16) trafiaja adresy SMS ($9xxx) - objz_mapcopy kopiuje mape.
;  Wolane: kod tego banku (b3_fireball = boss_fire_fireball_pallet 02:85D1 w obj/objz_boss.asm), kod rezydentny (spawn_object,
;  damage_sonic, play_music, play_sfx) i stuby zc_* do banku 45 (game/objcom.asm): zc_mlc, zc_slc, zc_bossart3, zc_boss8,
;  zc_collide, zc_dspr.
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl, A/C pomocniczo zg_a, zg_off; tmp_00..tmp_08 = zmienne SMS.
;  Zmiennych wody (g_water_level_y, iy_06 b7) te obiekty nie czytaja.
; =====================================================================
; adresy SMS danych (zakresy OZ_SPAN w objdata.inc: $947B-$94A4, $9688-$96A7, $96F5-$96F7)
L3B_ENTR        = $947B   ; LUT_LAB3_boss_entrance_positions_xy: 3 x (x, y) slowa: ($033C,$0360) z dolu, ($02EC,$0260), ($038C,$0260) z gory
L3B_TGTY        = $9487   ; LUT_LAB3_boss_target_y_positions: 3 slowa ($0328, $02B0, $02B0) - y zawisu
L3B_EXITY       = $948D   ; LUT_LAB3_boss_exit_y_positions: 3 slowa ($0360, $0260, $0260) - y konca odjazdu
SPR_L3BOSS      = $9493   ; SPRTAB_LAB3_boss (mapa 18 B, 3 wiersze)
SPR_L3RKT_R     = $9688   ; SPRTAB_LAB3_boss_rocket_right: 2 klatki po 8 B (+0, +8; wiersz 2 zaczyna sie od $FF)
SPR_L3RKT_L     = $9698   ; SPRTAB_LAB3_boss_rocket_left
LUT_L3PUFF      = $96F5   ; LUT_LAB3_boss_rocket_puff_anim_sprites: kafle $1C, $1E, $5E

; ---------------------------------------------------------------------
; objfunc_49_LAB3_boss (02:9267): boss Labyrinth 3 (caly etap pod woda; grafika i palete ma wspolne z bossem BRI3).
; Bez kolizji z mapa (set 5), 32 x 28; kamera dojezdza do celu ($02D0, $0290) = (720, 656) i stoi (zc_mlc co tick).
; Pierwszy tick (b0 flag = 0): cel kamery i granice okna (zc_slc), set 1 iy_09 (load_art bez przerwan - IRQ dopiero po
; dekompresji), grafika ART_0C_E508 (zc_bossart3: v_art_req = 3), paleta PAL2_boss (signal_load_palettes A = 2), trafienia = 0,
; muzyka $0B, set 0.
; (ix+19) = numer pozycji 0..2 (cyklicznie, bez random_A): 0 - z dolu (x $033C, y $0360 -> zawis $0328), 1 i 2 - z gory
; (x $02EC / $038C, y $0260 -> zawis $02B0). Stany (ix+17):
;  0 - pozycja startowa z LUT_LAB3_boss_entrance_positions_xy[(ix+19)], stan 1;
;  1 - wjazd: Vy = $FFFF80 (z dolu, w gore) albo $000080 (z gory, w dol), az y = cel (rownosc 16 bit): stan 2, (ix+18) = 0;
;  2 - zawis: Vy = 0, po $64 tickach stan 3 i strzal: z dolu - 2 kule ognia $0D (b3_fireball, (ix+19) kul = 4) z (x + 4, y - 6)
;      Vx = $FF00 i z (x + $20, y - 6) Vx = $0100, obie Vy = $FF00, efekt $01 (bez sprawdzania trafien!); z gory - gdy
;      trafienia < 8 - rakieta $2F w (x + $0F, y + $22) (tmp_00 / tmp_02 liczone zawsze, przed wyborem);
;  3+ - odjazd: Vy odwrotnie niz w stanie 1, az y = LUT_LAB3_boss_exit_y_positions[(ix+19)]: stan 0, (ix+19) + 1 (od 3 znowu 0).
; Co tick boss_generic_update_8hp (tmp_08 = $00A2: przesuniecie map SPRTAB_boss_generic_fly_out); potem, gdy trafienia < 8 i boss
; wznosi sie (Vy < 0, b7 (ix+12)): draw_sprite kafla 0 / 2 (g_global_tick_counter & 2) w (x + $10, y + $30) - smiglo pod bossem.
; ---------------------------------------------------------------------
objfunc_49_LAB3_boss
	ldy #OB_FLAGS             ; set 5,(ix+24): bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W                 ; (ix+13) = $20, (ix+14) = $1C
	lda #$20
	sta (zg_obj),y
	iny
	lda #$1C
	sta (zg_obj),y
	jsr zc_mlc                ; move_locked_camera_towards_target (01:7CA6)
	ldy #OB_SPRITE            ; (ix+15/16) = SPRTAB_LAB3_boss (adres SMS)
	lda #<SPR_L3BOSS
	sta (zg_obj),y
	iny
	lda #>SPR_L3BOSS
	sta (zg_obj),y
	ldy #OB_FLAGS             ; bit 0,(ix+24) / jr nz @already_initialised
	lda (zg_obj),y
	and #$01
	jne lb3_init_done
	lda #<$02D0               ; set_locked_camera_target (01:7C8C): HL = $02D0, DE = $0290
	sta zs_hl
	lda #>$02D0
	sta zs_hl+1
	lda #<$0290
	sta zs_de
	lda #>$0290
	sta zs_de+1
	jsr zc_slc
	lda iy_09                 ; set 1,(iy+iy_09): load_art bez ei (00:0433) - art_load_common nie robi IRQ w trakcie
	ora #$02                  ; i kasuje ten bit na koncu (00:04F4: res 1); zalegle przerwanie ramki po ei - 1 w PAL, 2 w NTSC (objs_e2.asm)
	sta iy_09
	jsr zc_bossart3           ; load_art ART_0C_E508 -> $2000 (A = $0C): grafika bossa BRI3 (v_art_req = 3)
	lda iy_00                 ; signal_load_palettes (00:0333): A = 2 (sprite'y), HL = PAL2_boss
	ora #$08
	sta iy_00
	lda #$02
	sta g_SIG00b3_palettes_present
	lda #<PAL2_BOSS
	sta g_SIG00b3_palette_addr
	lda #>PAL2_BOSS
	sta g_SIG00b3_palette_addr+1
	lda #0                    ; xor a / ld (g_boss_hits_taken),a
	sta g_boss_hits_taken
	lda #$0B                  ; rst $18: muzyka bossa
	jsr play_music
	ldy #OB_FLAGS             ; set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
lb3_init_done                   ; @already_initialised
	ldy #17                   ; ld a,(ix+17) / and a / jr nz @not_state_00
	lda (zg_obj),y
	bne lb3_not0
	ldy #19                   ; stan 0: hl = LUT_LAB3_boss_entrance_positions_xy + (ix+19) * 4 (add a,a x 2 - 8 bit, jak tu asl)
	lda (zg_obj),y
	asl
	asl
	tax
	ldy #OB_X+1               ; (ix+2), (ix+3) = x
	lda L3B_ENTR-OZ_OFF,x
	sta (zg_obj),y
	iny
	lda L3B_ENTR+1-OZ_OFF,x
	sta (zg_obj),y
	ldy #OB_Y+1               ; (ix+5), (ix+6) = y
	lda L3B_ENTR+2-OZ_OFF,x
	sta (zg_obj),y
	iny
	lda L3B_ENTR+3-OZ_OFF,x
	sta (zg_obj),y
	ldy #17                   ; inc (ix+17): stan 1
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	jmp lb3_common            ; jp @continue_to_common_code

lb3_not0                        ; @not_state_00 (A = (ix+17))
	cmp #1                    ; dec a / jr nz @not_state_01
	jne lb3_not1
	ldy #19                   ; stan 1 - wjazd: ld a,(ix+19) / and a / jr nz @is_exiting_upwards
	lda (zg_obj),y
	bne lb3_s1dn
	lda #$80                  ; (ix+19) = 0 (z dolu): Vy = $FFFF80 (w gore 0,5 px/tick)
	ldx #$FF
	bne lb3_s1v               ; zawsze (X != 0) - jp @was_exiting_downwards
lb3_s1dn                        ; @is_exiting_upwards ((ix+19) = 1, 2 - z gory): Vy = $000080 (w dol)
	lda #$80
	ldx #$00
lb3_s1v
	jsr lb3_vy
	ldy #19                   ; @was_exiting_downwards: hl = LUT_LAB3_boss_target_y_positions[(ix+19)] (indeks * 2, 8 bit)
	lda (zg_obj),y
	asl
	tax
	ldy #OB_Y+1               ; and a / sbc hl,de (de = y) / jp nz: wynik tylko do Z - wystarczy porownanie obu bajtow
	lda L3B_TGTY-OZ_OFF,x
	cmp (zg_obj),y
	jne lb3_common
	iny
	lda L3B_TGTY+1-OZ_OFF,x
	cmp (zg_obj),y
	jne lb3_common
	ldy #17                   ; y = cel: inc (ix+17) (stan 2), (ix+18) = 0
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	lda #0
	iny
	sta (zg_obj),y
	jmp lb3_common

lb3_not1                        ; @not_state_01
	cmp #2                    ; dec a / jp nz @not_state_02
	jne lb3_s3
	lda #0                    ; stan 2 - zawis: xor a / Vy (ix+10, 11, 12) = 0
	tax
	jsr lb3_vy
	ldy #18                   ; inc (ix+18) / cp $64 / jp nz
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$64
	jne lb3_common
	ldy #17                   ; inc (ix+17): stan 3
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	ldy #OB_X+1               ; tmp_00 = x + $000F (16 bit)
	clc
	lda (zg_obj),y
	adc #$0F
	sta tmp_00
	iny
	lda (zg_obj),y
	adc #0
	sta tmp_00+1
	ldy #OB_Y+1               ; tmp_02 = y + $0022
	clc
	lda (zg_obj),y
	adc #$22
	sta tmp_02
	iny
	lda (zg_obj),y
	adc #0
	sta tmp_02+1
	ldy #19                   ; ld a,(ix+19) / and a / jp z @fire_fireball_pallets
	lda (zg_obj),y
	jeq lb3_fire
	lda g_boss_hits_taken     ; z gory: rakieta tylko przy trafieniach < 8 (cp $08 / jp nc)
	cmp #$08
	jcs lb3_common
	jsr spawn_object          ; call spawn_object / jp c: brak wolnego slotu
	jcs lb3_common
	ldy #OB_TYPE              ; rakieta (zg_ptr = nowy slot; oryginal: push ix / push hl / pop ix): (ix+0) = $2F
	lda #$2F
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y            ; +1: subpiksel x = 0
	iny
	lda tmp_00
	sta (zg_ptr),y            ; +2, +3: x = tmp_00
	iny
	lda tmp_00+1
	sta (zg_ptr),y
	iny
	lda #0
	sta (zg_ptr),y            ; +4: subpiksel y = 0
	iny
	lda tmp_02
	sta (zg_ptr),y            ; +5, +6: y = tmp_02
	iny
	lda tmp_02+1
	sta (zg_ptr),y
	lda #0
	iny
lb3_rz
	sta (zg_ptr),y            ; +7..+12: Vx = Vy = 0
	iny
	cpy #13
	bne lb3_rz
	ldy #OB_FLAGS             ; (ix+24) = 0 (pozostale pola slotu bez zmian - spawn_object ich nie czysci, jak oryginal)
	sta (zg_ptr),y
	jmp lb3_common            ; pop ix / jp @continue_to_common_code

lb3_s3                          ; @not_state_02 (stan >= 3) - odjazd: ld a,(ix+19) / and a / jr nz @is_entering_downwards
	ldy #19
	lda (zg_obj),y
	bne lb3_s3up
	lda #$80                  ; (ix+19) = 0: Vy = $000080 (w dol, z powrotem pod ekran)
	ldx #$00
	beq lb3_s3v               ; zawsze (X = 0) - jp @was_entering_upwards
lb3_s3up                        ; @is_entering_downwards ((ix+19) = 1, 2): Vy = $FFFF80 (w gore)
	lda #$80
	ldx #$FF
lb3_s3v
	jsr lb3_vy
	ldy #19                   ; @was_entering_upwards: hl = LUT_LAB3_boss_exit_y_positions[(ix+19)] - y (xor a / sbc hl,de / jr nz)
	lda (zg_obj),y
	asl
	tax
	ldy #OB_Y+1
	lda L3B_EXITY-OZ_OFF,x
	cmp (zg_obj),y
	bne lb3_common
	iny
	lda L3B_EXITY+1-OZ_OFF,x
	cmp (zg_obj),y
	bne lb3_common
	lda #0                    ; ld (ix+17),a (A = 0 z xor a): stan 0
	ldy #17
	sta (zg_obj),y
	ldy #19                   ; inc (ix+19) / cp $03 / jr c: nastepna pozycja, od 3 znowu 0
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$03
	bcc lb3_common
	lda #0
	sta (zg_obj),y
lb3_common                      ; @continue_to_common_code: tmp_08 = $00A2, boss_generic_update_8hp (01:77BE)
	lda #<$00A2
	sta tmp_08
	lda #>$00A2
	sta tmp_08+1
	jsr zc_boss8
	lda g_boss_hits_taken     ; cp $08 / ret nc: boss pokonany - bez smigla
	cmp #$08
	bcs lb3_ret
	ldy #OB_VY+2              ; bit 7,(ix+12) / ret z: smiglo tylko przy wznoszeniu (Vy < 0)
	lda (zg_obj),y
	bpl lb3_ret
	ldy #OB_X+1               ; tmp_00 = x, tmp_02 = y, tmp_04 = $0010, tmp_06 = $0030
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
	lda #<$0010
	sta tmp_04
	lda #>$0010
	sta tmp_04+1
	lda #<$0030
	sta tmp_06
	lda #>$0030
	sta tmp_06+1
	lda g_global_tick_counter ; a = g_global_tick_counter & $02: kafel 0 / 2
	and #$02
	jmp zc_dspr               ; call draw_sprite (00:3581) / ret
lb3_ret
	rts

lb3_fire                        ; @fire_fireball_pallets (02:9432): dwie kule ognia $0D, (ix+19) kul = 4
	ldy #OB_X+1               ; tmp_00 = x + $0004
	clc
	lda (zg_obj),y
	adc #$04
	sta tmp_00
	iny
	lda (zg_obj),y
	adc #0
	sta tmp_00+1
	ldy #OB_Y+1               ; tmp_02 = y + $FFFA (add hl,de 16 bit: y - 6)
	clc
	lda (zg_obj),y
	adc #$FA
	sta tmp_02
	iny
	lda (zg_obj),y
	adc #$FF
	sta tmp_02+1
	lda #<$FF00               ; tmp_04 = $FF00 (Vx = -1 px/tick), tmp_06 = $FF00 (Vy = -1 px/tick)
	sta tmp_04
	sta tmp_06
	lda #>$FF00
	sta tmp_04+1
	sta tmp_06+1
	lda #$04                  ; ld c,$04 / call boss_fire_fireball_pallet (02:85D1)
	jsr b3_fireball
	ldy #OB_X+1               ; tmp_00 = x + $0020 (tmp_02, tmp_06 bez zmian)
	clc
	lda (zg_obj),y
	adc #$20
	sta tmp_00
	iny
	lda (zg_obj),y
	adc #0
	sta tmp_00+1
	lda #<$0100               ; tmp_04 = $0100 (Vx = +1 px/tick)
	sta tmp_04
	lda #>$0100
	sta tmp_04+1
	lda #$04                  ; ld c,$04 / call boss_fire_fireball_pallet
	jsr b3_fireball
	lda #$01                  ; rst $28
	jsr play_sfx
	jmp lb3_common

; lb3_vy: Vy bossa (ix+10, 11, 12) = (A, X, X) - ld (ix+10),$80 / ld (ix+11),hi / ld (ix+12),hi. Niszczy A, Y.
lb3_vy
	ldy #OB_VY
	sta (zg_obj),y
	txa
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_2F_LAB3_boss_rocket (02:94A5): rakieta bossa LAB3 naprowadzana na Sonica. Bez kolizji z mapa (set 5), 8 x 10;
; kolizja z Soniciem (tmp_06 = $0404) - damage_sonic. Flagi (ix+24): b1 - kierunek ustalony, b2 - Sonic na prawo
; (x + 8 < sonic_x + 12 w pierwszym ticku), b0 - rakieta wystartowala.
;  Przed startem (b0 = 0): Vy = $000040 (powolne opadanie), mapa _left / _right wg b2; start, gdy sonic_y < y.
;  Po starcie: poza ekranem (x - 16 < kamera X, x >= kamera X + 256, y - 16 < kamera Y, y > kamera Y + $C0) - (ix+0) = $FF
;  (ale reszta ticku dalej!). Vx (24 bit) += +2 (b2 = 1) / -2 subpiksele; Vy += +2 / +4 (rakieta nad Sonikiem, y + 8 < sonic_y
;  + 16; +4 gdy Vy < 0) albo -2 / -4 (pod: -4 gdy Vy >= 0); obie ograniczone lbr_clamp do |v| <= 1 px/tick. Mapa wg znaku Vx,
;  klatka (+8) wg b3 starszego bajtu licznika (ix+17/18) += |Vx| (16 bit; pola z poprzedniego obiektu slotu - spawn ich nie
;  czysci). Co 16 tickow (g_global_tick_counter & $0F = 0) dym $2A w (x - 7 / x + $0F wg kierunku, y).
; ---------------------------------------------------------------------
objfunc_2F_LAB3_rocket
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W                 ; (ix+13) = $08, (ix+14) = $0A
	lda #$08
	sta (zg_obj),y
	iny
	lda #$0A
	sta (zg_obj),y
	lda #$04                  ; ld hl,$0404 / ld (tmp_06),hl
	sta tmp_06
	sta tmp_06+1
	jsr zc_collide            ; check_collision_with_sonic (00:3956): C = 1 brak trafienia
	bcs lbr_nohit
	jsr damage_sonic          ; call nc,damage_sonic
lbr_nohit
	ldy #OB_FLAGS             ; bit 1,(ix+24) / jr nz @already_initialised
	lda (zg_obj),y
	and #$02
	bne lbr_inited
	lda (zg_obj),y            ; set 1,(ix+24)
	ora #$02
	sta (zg_obj),y
	clc                       ; de = sonic_x + $000C
	lda sonic_x
	adc #$0C
	sta zg_de
	lda sonic_x+1
	adc #0
	sta zg_de+1
	ldy #OB_X+1               ; hl = x + $0008
	clc
	lda (zg_obj),y
	adc #$08
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	sec                       ; and a / sbc hl,de / jr nc: bez pozyczki (6502 C = 1) - Sonic na lewo, b2 = 0
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	bcs lbr_inited
	ldy #OB_FLAGS             ; pozyczka (x + 8 < sonic_x + 12): set 2,(ix+24) - Sonic na prawo
	lda (zg_obj),y
	ora #$04
	sta (zg_obj),y
lbr_inited                      ; @already_initialised: bit 0,(ix+24) / jr nz @rocket_started
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$01
	jne lbr_started
	lda #$40                  ; Vy = $000040
	ldx #0
	ldy #OB_VY
	sta (zg_obj),y
	txa
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_FLAGS             ; hl = SPRTAB_LAB3_boss_rocket_left; bit 2 = 1 -> _right
	lda (zg_obj),y
	and #$04
	beq lbr_mapl
	lda #<SPR_L3RKT_R
	ldx #>SPR_L3RKT_R
	bne lbr_map0              ; zawsze (>SPR_L3RKT_R != 0)
lbr_mapl                        ; @sonic_was_on_the_left
	lda #<SPR_L3RKT_L
	ldx #>SPR_L3RKT_L
lbr_map0
	ldy #OB_SPRITE            ; (ix+15/16) = hl
	sta (zg_obj),y
	txa
	iny
	sta (zg_obj),y
	ldy #OB_Y+1               ; hl = sonic_y - y: and a / sbc hl,de / ret nc (bez pozyczki: 6502 C = 1)
	sec
	lda sonic_y
	sbc (zg_obj),y
	iny
	lda sonic_y+1
	sbc (zg_obj),y
	bcs lbr_ret
	ldy #OB_FLAGS             ; rakieta ponizej Sonica: set 0,(ix+24) - start
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
lbr_ret
	rts

lbr_started                     ; @rocket_started: test wyjscia poza ekran
	ldy #OB_X+1               ; bc = x
	lda (zg_obj),y
	sta zg_bc
	iny
	lda (zg_obj),y
	sta zg_bc+1
	clc                       ; hl = $FFF0 + bc (16 bit: x - 16)
	lda zg_bc
	adc #$F0
	sta zg_hl
	lda zg_bc+1
	adc #$FF
	sta zg_hl+1
	sec                       ; de = kamera X; and a / sbc hl,de / jr c: pozyczka (6502 C = 0) - poza ekranem z lewej
	lda zg_hl
	sbc g_level_scroll_x_pix_lo
	lda zg_hl+1
	sbc g_level_scroll_x_pix_lo+1
	bcc lbr_cull
	ldx g_level_scroll_x_pix_lo+1 ; inc d (8 bit): de = kamera X + $0100
	inx
	stx zg_a
	sec                       ; hl = bc; and a / sbc hl,de / jr nc: bez pozyczki (6502 C = 1) - poza ekranem z prawej
	lda zg_bc
	sbc g_level_scroll_x_pix_lo
	lda zg_bc+1
	sbc zg_a
	bcs lbr_cull
	ldy #OB_Y+1               ; bc = y
	lda (zg_obj),y
	sta zg_bc
	iny
	lda (zg_obj),y
	sta zg_bc+1
	clc                       ; hl = $FFF0 + bc (y - 16)
	lda zg_bc
	adc #$F0
	sta zg_hl
	lda zg_bc+1
	adc #$FF
	sta zg_hl+1
	sec                       ; de = kamera Y; sbc hl,de / jr c - poza ekranem u gory
	lda zg_hl
	sbc g_level_scroll_y_pix_lo
	lda zg_hl+1
	sbc g_level_scroll_y_pix_lo+1
	bcc lbr_cull
	clc                       ; hl = $00C0 + de (kamera Y + $C0)
	lda g_level_scroll_y_pix_lo
	adc #$C0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #0
	sta zg_hl+1
	sec                       ; and a / sbc hl,bc / jr nc @not_off_screen: bez pozyczki (y <= kamera Y + $C0) - na ekranie
	lda zg_hl
	sbc zg_bc
	lda zg_hl+1
	sbc zg_bc+1
	bcs lbr_onscr
lbr_cull                        ; @rocket_off_screen_needs_culling: (ix+0) = $FF - reszta ticku dalej (jak oryginal)
	lda #$FF
	ldy #OB_TYPE
	sta (zg_obj),y
lbr_onscr                       ; @not_off_screen: przyspieszenie X - xor a / hl = $0002 (b2: Sonic na prawo), inaczej a = $FF,
	ldy #OB_FLAGS             ; hl = $FFFE (dec a)
	lda (zg_obj),y
	and #$04
	beq lbr_xl
	lda #$02
	sta zg_hl
	lda #$00
	sta zg_hl+1
	sta zg_a                  ; a (bajt rozszerzenia) = 0
	beq lbr_xadd              ; zawsze
lbr_xl
	lda #$FE
	sta zg_hl
	lda #$FF
	sta zg_hl+1
	sta zg_a                  ; a = $FF
lbr_xadd                        ; @move_right_selected: add hl,de (de = Vx 16 bit) / adc a,(ix+9) / ld c,a
	ldy #OB_VX
	clc
	lda zg_hl
	adc (zg_obj),y
	sta zg_hl
	iny
	lda zg_hl+1
	adc (zg_obj),y
	sta zg_hl+1
	iny
	lda zg_a
	adc (zg_obj),y            ; przeniesienie z add hl,de
	sta zg_a                  ; c
	ldy #OB_VX
	jsr lbr_clamp             ; (ix+7, 8, 9) = l, h, c (po ograniczeniu)
	clc                       ; przyspieszenie Y: de = sonic_y + $0010
	lda sonic_y
	adc #$10
	sta zg_de
	lda sonic_y+1
	adc #0
	sta zg_de+1
	ldy #OB_Y+1               ; hl = y + $0008
	clc
	lda (zg_obj),y
	adc #$08
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	sec                       ; and a / sbc hl,de: przeniesienie Z80 (pozyczka) = 6502 C = 0
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	ldy #OB_VY+2              ; bit 7,(ix+12) nie zmienia przeniesienia - tu: ldy/lda tez nie (C z sbc zostaje)
	bcc lbr_ydn
	lda #$FF                  ; jr nc (y + 8 >= sonic_y + 16, rakieta pod Sonikiem): a = $FF, hl = $FFFE (Vy < 0) / $FFFC
	sta zg_a
	sta zg_hl+1
	lda (zg_obj),y
	bmi lbr_yu2               ; bit 7,(ix+12) / jr nz @skip_y_accel_boost_up
	lda #$FC                  ; ld hl,$FFFC: rakieta leci w dol - mocniej w gore
	bne lbr_yu                ; zawsze
lbr_yu2
	lda #$FE
lbr_yu
	sta zg_hl
	jmp lbr_yadd
lbr_ydn                         ; jr c (rakieta nad Sonikiem): inc a (a = 0), hl = $0002 (Vy >= 0) / $0004 (Vy < 0)
	lda #$00
	sta zg_a
	sta zg_hl+1
	lda (zg_obj),y
	bpl lbr_yd2               ; bit 7,(ix+12) / jr z @y_accel_selected
	lda #$04                  ; ld hl,$0004: rakieta leci w gore - mocniej w dol
	bne lbr_yd                ; zawsze
lbr_yd2
	lda #$02
lbr_yd
	sta zg_hl
lbr_yadd                        ; @y_accel_selected: add hl,de (de = Vy 16 bit) / adc a,(ix+12) / ld c,a
	ldy #OB_VY
	clc
	lda zg_hl
	adc (zg_obj),y
	sta zg_hl
	iny
	lda zg_hl+1
	adc (zg_obj),y
	sta zg_hl+1
	iny
	lda zg_a
	adc (zg_obj),y
	sta zg_a                  ; c
	ldy #OB_VY
	jsr lbr_clamp             ; (ix+10, 11, 12) = l, h, c
	ldy #OB_VX+2              ; mapa: hl = SPRTAB_LAB3_boss_rocket_right; bit 7,(ix+9) (Vx < 0) -> _left
	lda (zg_obj),y
	bmi lbr_sprl
	lda #<SPR_L3RKT_R
	sta zg_bc
	lda #>SPR_L3RKT_R
	sta zg_bc+1
	bne lbr_abs               ; zawsze
lbr_sprl
	lda #<SPR_L3RKT_L
	sta zg_bc
	lda #>SPR_L3RKT_L
	sta zg_bc+1
lbr_abs                         ; @selected_right_sprite: push hl (zg_bc); hl = (ix+7/8), bit 7,h -> hl = -hl (cpl l, cpl h, inc hl)
	ldy #OB_VX
	lda (zg_obj),y
	sta zg_hl
	iny
	lda (zg_obj),y
	sta zg_hl+1
	bpl lbr_absok
	lda zg_hl
	eor #$FF
	clc
	adc #1
	sta zg_hl
	lda zg_hl+1
	eor #$FF
	adc #0
	sta zg_hl+1
lbr_absok                       ; @skip_x_vel_negation_for_abs_val: (ix+17/18) += hl (16 bit)
	ldy #17
	clc
	lda (zg_obj),y
	adc zg_hl
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc zg_hl+1
	sta (zg_obj),y
	and #$08                  ; ld a,h / and $08 / ld e,a / ld d,0 / pop hl / add hl,de: mapa = baza + (h & 8)
	clc
	adc zg_bc
	ldy #OB_SPRITE
	sta (zg_obj),y
	lda zg_bc+1
	adc #0
	iny
	sta (zg_obj),y
	ldy #OB_VX+2              ; dym: hl = x + $FFF9 (Vx >= 0: za rakieta z lewej, x - 7), Vx < 0 - x + $000F
	lda (zg_obj),y
	bmi lbr_pfr
	lda #$F9
	ldx #$FF
	bne lbr_pfx               ; zawsze (X != 0)
lbr_pfr
	lda #$0F
	ldx #$00
lbr_pfx                         ; @selected_left_puff_x_vel: tmp_00 = x + de, tmp_02 = y
	sta zg_de
	stx zg_de+1
	ldy #OB_X+1
	clc
	lda (zg_obj),y
	adc zg_de
	sta tmp_00
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta tmp_00+1
	ldy #OB_Y+1
	lda (zg_obj),y
	sta tmp_02
	iny
	lda (zg_obj),y
	sta tmp_02+1
	lda g_global_tick_counter ; and $0F / ret nz: dym co 16 tickow
	and #$0F
	bne lbr_ret2
	jsr spawn_object          ; ret c: brak wolnego slotu
	bcs lbr_ret2
	ldy #OB_TYPE              ; dym $2A (zg_ptr): x = tmp_00, y = tmp_02, subpiksele 0, (ix+17/18) = 0, Vx = Vy = 0
	lda #$2A
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
	iny
lbr_pz
	sta (zg_ptr),y            ; +7..+12 = 0
	iny
	cpy #13
	bne lbr_pz
	ldy #17
	sta (zg_ptr),y            ; +17, +18 = 0 (flagi (ix+24) dymu bez zmian - oryginal ich nie pisze)
	iny
	sta (zg_ptr),y
lbr_ret2
	rts

; lbr_clamp (02:956B-02:9589 / 02:95C8-02:95E6): ograniczenie predkosci rakiety do |v| <= 1 px/tick i zapis.
; Wejscie: zg_hl = nowe (sub, lo) (HL), zg_a = nowy bajt hi (C), Y = OB_VX albo OB_VY. Oryginal: ld a,h / ld de,$0100 /
; bit 7,c / jr z (dodatnie) / [ujemne: de = -hl (cpl, inc de), a = d, de = $FF00] / and a / jr z (bez zmiany) / ex de,hl.
; Czyli: c >= 0 i h != 0 -> hl = $0100; c < 0 i starszy bajt (-hl) != 0 -> hl = $FF00; c zawsze bez zmian.
; Wyjscie: (ix+Y, Y+1, Y+2) = l, h, c. Niszczy A, Y, zg_off.
lbr_clamp
	sty zg_off
	lda zg_a                  ; bit 7,c
	bmi lbc_neg
	lda zg_hl+1               ; dodatnie: a = h
	beq lbc_st                ; and a / jr z @skip_clamp
	lda #$00                  ; ex de,hl: hl = $0100
	sta zg_hl
	lda #$01
	sta zg_hl+1
	bne lbc_st                ; zawsze
lbc_neg                         ; ujemne: a = starszy bajt (~hl + 1) (16 bit)
	lda zg_hl
	eor #$FF
	clc
	adc #1                    ; przeniesienie tylko przy l = 0
	lda zg_hl+1
	eor #$FF
	adc #0
	beq lbc_st                ; and a / jr z: |v| < 1 px - hl bez zmian
	lda #$00                  ; ex de,hl: hl = $FF00
	sta zg_hl
	lda #$FF
	sta zg_hl+1
lbc_st                          ; @skip_clamp: (ix+n) = l, (ix+n+1) = h, (ix+n+2) = c
	ldy zg_off
	lda zg_hl
	sta (zg_obj),y
	iny
	lda zg_hl+1
	sta (zg_obj),y
	iny
	lda zg_a
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; objfunc_2A_LAB3_boss_rocket_puff (02:96A8): dym za rakieta. Bez kolizji z mapa (set 5), mapa 0 (nie rysowany przez obj_draw);
; jeden sprite: draw_sprite kafla LUT_LAB3_boss_rocket_puff_anim_sprites[(ix+18)] w (x, y) (tmp_04 = tmp_06 = 0). Co 12 tickow
; ((ix+17) do $0C) nastepna klatka (ix+18); po 3 klatkach (36 tickow) obiekt usuwany ($FF).
; ---------------------------------------------------------------------
objfunc_2A_rocket_puff
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	lda #0                    ; xor a / (ix+15) = (ix+16) = 0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	sta tmp_04                ; ld l,a / ld h,a / tmp_04 = tmp_06 = 0
	sta tmp_04+1
	sta tmp_06
	sta tmp_06+1
	ldy #OB_X+1               ; tmp_00 = x, tmp_02 = y
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
	ldy #18                   ; a = LUT_LAB3_boss_rocket_puff_anim_sprites[(ix+18)] (e = (ix+18), d = 0)
	lda (zg_obj),y
	tax
	lda LUT_L3PUFF-OZ_OFF,x
	jsr zc_dspr               ; call draw_sprite (00:3581)
	ldy #17                   ; inc (ix+17) / cp $0C / ret c
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$0C
	bcc lbp_ret
	lda #0                    ; (ix+17) = 0, inc (ix+18) / cp $03 / ret c
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$03
	bcc lbp_ret
	lda #$FF                  ; (ix+0) = $FF: koniec dymu
	ldy #OB_TYPE
	sta (zg_obj),y
lbp_ret
	rts
