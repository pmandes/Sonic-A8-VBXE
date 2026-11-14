; =====================================================================
;  obj/objz3_ss.asm - M6.11 etapy specjalne $1F-$23: $21 odbijacz (etapy 5-8), $4C flipper (etapy 4 i 8 - przycisk 2)
;  M6.11: kod w trzecim banku obiektow strefy PB_OBJZ3 (bank 30; obj/objz3.asm) - dane banku 2 ROM-u pod adresem
;  SMS - OZ_OFF jak w PB_OBJZ2 (zakresy OBJZ3_SPANS w tools/extract_sms.py, stale OZ3_* w objdata.inc).
;  (bank obiektow strefy 3 PB_OBJZ3, bank 30, okno $4000-$7FFF; dolaczany z game.asm w sekcji banku 30).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny):
;   objfunc_4C_flipper                  02:9866 - 02:999D  -> objfunc_4C_flipper (+ ss4c_kick = wspolny koniec ksztaltow 0 i 2)
;   (@UNUSED_0993F                      02:993F - 02:995D   nieosiagalne - pominiete)
;   LUT_flipper_y_offsets_00..02        02:999E - 02:99FD   3 x 32 B: przesuniecie y Sonika (ze znakiem) wg (sonic_x + 12) & 31
;   LUT_flipper_y_vel_additions_01      02:99FE - 02:9A3D   32 slowa: dodatek do Vx Sonica (starszy bajt $FF) - ksztalt 1
;   LUT_flipper_y_vel_additions_02      02:9A3E - 02:9A7D   32 slowa: dodatek do -Vy - 1 (starszy bajt $FF) - ksztalt 1
;   SPRTAB_flipper_00                   02:9A7E - 02:9A8F   (18 B: wiersz 1 = $FE - pusty, wiersz 2 = $38 $3A $3C $3E, wiersz 3 = $FF)
;   SPRTAB_flipper_01                   02:9A90 - 02:9AA1   (18 B: $48 $4A $4C $4E / $68 $6A $6C $6E, wiersz 3 = $FF)
;   SPRTAB_flipper_02                   02:9AA2 - 02:9AAE   (13 B: $FE $12 $14 $16 / $FE $32 $34 $36, wiersz 3 = $FF)
;   compute_flipper_y_offset            02:9AAF - 02:9AFA  -> ss4c_yofs
;   objfunc_21_special_stage_bouncer    02:9AFB - 02:9B6D  -> objfunc_21_ss_bouncer
;   SPRTAB_special_stage_bouncer        02:9B6E - 02:9B74   (7 B: $08 $0A $28 $2A $FF $FF, wiersz 2 = $FF - koniec)
;  Dane banku 2 ROM-u leza w tym banku pod adresem SMS - OZ_OFF (dla OBJZ3_SPANS: $999E-$9AAE (273 B) i $9B6E-$9B74 (7 B));
;  kod czyta tablice przez "ETYKIETA-OZ_OFF", a do rekordu (mapa ix+15/16) trafiaja adresy SMS ($9A7E, $9A90, $9AA2, $9B6E) -
;  mapy kopiuje objz_mapcopy z banku v_pbobjz (game/objcom.asm).
;  Wolane: kod rezydentny $8000+ (play_sfx = rst $28 - game/objcom.asm) i stub zc_collide do banku 45 (game/objcom.asm:
;  check_collision_with_sonic 00:3956: tmp_06/07 = przesuniecia, (ix+13/14) = rozmiar; C = 1 brak trafienia; niszczy A, Y,
;  zg_hl, zg_de).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl, A pomocniczo zg_a. Przeniesienie: Z80 C = 1 po sbc (pozyczka)
;  <=> 6502 C = 0; wynik compute_flipper_y_offset (C Z80) - tu C 6502 o tym samym znaczeniu (1 = Sonic na flipperze).
; =====================================================================
; adresy SMS danych (bank 2 ROM-u; w tym banku pod adresem - OZ_OFF)
SS4C_YOFS0      = $999E   ; LUT_flipper_y_offsets_00 (ksztalt 0 - schowany); _01 = +$20, _02 = +$40 (indeks ss4c_yofs w X)
SS4C_VXADD      = $99FE   ; LUT_flipper_y_vel_additions_01: slowa (sub, lo) dodawane do Vx Sonica (hi + $FF)
SS4C_VYADD      = $9A3E   ; LUT_flipper_y_vel_additions_02: slowa (sub, lo) dodawane do dopelnienia Vy Sonica (hi + $FF)
SS4C_SPR0       = $9A7E   ; SPRTAB_flipper_00 (flipper schowany, (ix+17) = 0)
SS4C_SPR1       = $9A90   ; SPRTAB_flipper_01 (w ruchu, (ix+17) = 1..3)
SS4C_SPR2       = $9AA2   ; SPRTAB_flipper_02 (wysuniety, (ix+17) = 4..5)
SS21_SPR        = $9B6E   ; SPRTAB_special_stage_bouncer (4 kafle w jednym wierszu)

; ---------------------------------------------------------------------
; objfunc_4C_flipper (02:9866): flipper etapow $1F / $23 ((288, 576), (320, 1248)). Co tick set 5 (bez kolizji z mapa), mapa
; SPRTAB_flipper_00. Przycisk 2 wcisniety (g_inputs_player_1 b5 = 0): (ix+18) = (ix+17) (stan sprzed ticku), (ix+17) + 1 do 5;
; puszczony: (ix+17) - 1 do 0 ((ix+18) bez zmian). Rozmiar zawsze $1E x $16; wg (ix+17):
;  0    - mapa _00, kolizja tmp_06/07 = $0C/$14; Sonic na flipperze (ss4c_yofs, tablica _00) -> Vy = g_sonic_bounce_vel_y,
;         Vx + $FFFFFC (24 bit) - ss4c_kick.
;  1..3 - mapa _01, kolizja $0F/$08; Sonic na flipperze (tablica _01) i flipper sie wysuwa ((ix+18) < (ix+17)): Vx + ($FF, slowo
;         LUT_flipper_y_vel_additions_01[i]), Vy = (dopelnienie Vy) + ($FF, slowo LUT_flipper_y_vel_additions_02[i]), i = (sonic_x
;         + 12) & 31 - wyrzut w gore i w lewo zalezny od miejsca uderzenia.
;  4..5 - mapa _02, kolizja $1A/$02; Sonic na flipperze (tablica _02) -> Vy = g_sonic_bounce_vel_y, Vx + $00001A - ss4c_kick.
; ss4c_yofs (compute_flipper_y_offset) ustawia przy okazji sonic_y na profil flippera albo odbija szybko spadajacego Sonika
; (patrz nizej) - wtedy wynik C = 0 i bez dalszych zmian.
; Pola rekordu: (ix+17) wysuniecie 0..5, (ix+18) wysuniecie z poprzedniego ticku z przyciskiem, (ix+24) b5.
; ---------------------------------------------------------------------
objfunc_4C_flipper
	ldy #OB_FLAGS             ; 02:9866: set 5,(ix+24) - bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_SPRITE            ; 02:986A: (ix+15/16) = SPRTAB_flipper_00 (adres SMS)
	lda #<SS4C_SPR0
	sta (zg_obj),y
	iny
	lda #>SS4C_SPR0
	sta (zg_obj),y
	lda g_inputs_player_1     ; 02:9872: bit 5,(iy+g_inputs_player_1) / jr nz @retract_flipper (aktywne zerem: 1 = puszczony)
	and #$20
	bne ss4c_retr
	ldy #17                   ; 02:9878: ld a,(ix+17) / ld (ix+18),a - wysuniecie sprzed ticku
	lda (zg_obj),y
	iny
	sta (zg_obj),y
	dey                       ; 02:987E: ld a,(ix+17) / cp $05 / jr nc @done_flipper_extension_update
	lda (zg_obj),y
	cmp #$05
	bcs ss4c_done
	adc #1                    ; 02:9885: inc (ix+17) / jp @done... (C = 0 po cmp < 5)
	sta (zg_obj),y
	jmp ss4c_done
ss4c_retr                       ; 02:988B @retract_flipper: ld a,(ix+17) / and a / jr z / dec (ix+17)
	ldy #17
	lda (zg_obj),y
	beq ss4c_done
	sec
	sbc #1
	sta (zg_obj),y

ss4c_done                       ; 02:9894 @done_flipper_extension_update: ld a,(ix+17) / cp $01 / jr nc @flipper_not_00
	ldy #17
	lda (zg_obj),y
	cmp #$01
	bcs ss4c_n00
	; --- ksztalt 0: flipper schowany ---
	lda #$0C                  ; 02:989B: ld hl,$140C / ld (tmp_06),hl - tmp_06 = $0C, tmp_07 = $14
	sta tmp_06
	lda #$14
	sta tmp_07
	jsr ss4c_size             ; 02:98A1: (ix+13) = $1E, (ix+14) = $16
	jsr zc_collide            ; 02:98A9: call check_collision_with_sonic / ret c
	bcs ss4c_ret
	ldx #SS4C_YOFS0-SS4C_YOFS0 ; 02:98AD: ld bc,LUT_flipper_y_offsets_00 / call compute_flipper_y_offset / ret nc
	jsr ss4c_yofs
	bcc ss4c_ret
	lda #<$FFFC               ; 02:98B4-02:98D2: Vy = g_sonic_bounce_vel_y, Vx + $FFFFFC (ld de,$FFFC / add hl,de / adc a,$FF)
	ldx #>$FFFC
	jmp ss4c_kick
ss4c_ret
	rts

ss4c_n00                        ; 02:98D3 @flipper_not_00: cp $04 / jp nc @flipper_not_01
	cmp #$04
	jcs ss4c_n01
	; --- ksztalt 1: flipper w ruchu (1..3) ---
	ldy #OB_SPRITE            ; 02:98D8: (ix+15/16) = SPRTAB_flipper_01
	lda #<SS4C_SPR1
	sta (zg_obj),y
	iny
	lda #>SS4C_SPR1
	sta (zg_obj),y
	lda #$0F                  ; 02:98E0: ld hl,$080F / ld (tmp_06),hl - tmp_06 = $0F, tmp_07 = $08
	sta tmp_06
	lda #$08
	sta tmp_07
	jsr ss4c_size             ; 02:98E6: (ix+13) = $1E, (ix+14) = $16
	jsr zc_collide            ; 02:98EE: call check_collision_with_sonic / ret c
	bcs ss4c_ret
	ldx #SS4C_YOFS0+$20-SS4C_YOFS0 ; 02:98F2: ld bc,LUT_flipper_y_offsets_01 / call compute_flipper_y_offset / ret nc
	jsr ss4c_yofs
	bcc ss4c_ret
	ldy #18                   ; 02:98F9: ld a,(ix+18) / cp (ix+17) / ret nc - tylko gdy flipper sie wysuwa (przycisk wcisniety)
	lda (zg_obj),y
	ldy #17
	cmp (zg_obj),y
	bcs ss4c_ret
	lda sonic_x               ; 02:9900: ld a,(sonic_x) / add a,$0C / and $1F / add a,a / ld c,a / ld b,$00 - bc = 2 * indeks
	clc
	adc #$0C
	and #$1F
	asl
	tax
	clc                       ; 02:990B: de = LUT_flipper_y_vel_additions_01[bc] / hl = (sonic_vel_x_sub), a = (sonic_vel_x_hi) /
	lda sonic_vel_x_sub       ; add hl,de / adc a,$FF - Vx (24 bit) + ($FF, d, e)
	adc SS4C_VXADD-OZ_OFF,x
	sta sonic_vel_x_sub       ; 02:991B: ld (sonic_vel_x_sub),hl / ld (sonic_vel_x_hi),a
	lda sonic_vel_x
	adc SS4C_VXADD+1-OZ_OFF,x
	sta sonic_vel_x
	lda sonic_vel_x_hi
	adc #$FF
	sta sonic_vel_x_hi
	clc                       ; 02:9921: de = LUT_flipper_y_vel_additions_02[bc] / hl = (sonic_vel_y_sub), a = (sonic_vel_y_hi);
	lda sonic_vel_y_sub       ; cpl l, h, a (dopelnienie = -Vy - 1) / add hl,de / adc a,$FF (eor nie zmienia C)
	eor #$FF
	adc SS4C_VYADD-OZ_OFF,x
	sta sonic_vel_y_sub       ; 02:9938: ld (sonic_vel_y_sub),hl / ld (sonic_vel_y_hi),a / ret
	lda sonic_vel_y
	eor #$FF
	adc SS4C_VYADD+1-OZ_OFF,x
	sta sonic_vel_y
	lda sonic_vel_y_hi
	eor #$FF
	adc #$FF
	sta sonic_vel_y_hi
	rts

ss4c_n01                        ; 02:995E @flipper_not_01: ksztalt 2 - flipper wysuniety (4..5)
	ldy #OB_SPRITE            ; (ix+15/16) = SPRTAB_flipper_02
	lda #<SS4C_SPR2
	sta (zg_obj),y
	iny
	lda #>SS4C_SPR2
	sta (zg_obj),y
	lda #$1A                  ; 02:9966: ld hl,$021A / ld (tmp_06),hl - tmp_06 = $1A, tmp_07 = $02
	sta tmp_06
	lda #$02
	sta tmp_07
	jsr ss4c_size             ; 02:996C: (ix+13) = $1E, (ix+14) = $16
	jsr zc_collide            ; 02:9974: call check_collision_with_sonic / ret c
	jcs ss4c_ret
	ldx #SS4C_YOFS0+$40-SS4C_YOFS0 ; 02:9978: ld bc,LUT_flipper_y_offsets_02 / call compute_flipper_y_offset / ret nc
	jsr ss4c_yofs
	jcc ss4c_ret
	lda #<$001A               ; 02:997F-02:999D: Vy = g_sonic_bounce_vel_y, Vx + $00001A (ld de,$001A / add hl,de / adc a,$00)
	ldx #>$001A
	; (dalej ss4c_kick)

; ss4c_kick (02:98B4-02:98D2 i 02:997F-02:999D - dwie kopie w oryginale): Vy Sonica = g_sonic_bounce_vel_y (a = pix_hi, hl = sub,
; lo), Vx Sonica (24 bit) + (X, X, A): A = e, X = d i zarazem stala adc a,n ($FFFC -> $FF, $001A -> $00). Niszczy A, zg_de.
ss4c_kick
	sta zg_de                 ; e
	stx zg_de+1               ; d (= n)
	lda g_sonic_bounce_vel_y_sub ; ld a,(g_sonic_bounce_vel_y_pix_hi) / ld hl,(g_sonic_bounce_vel_y_sub) /
	sta sonic_vel_y_sub       ; ld (sonic_vel_y_sub),hl / ld (sonic_vel_y_hi),a
	lda g_sonic_bounce_vel_y_sub+1
	sta sonic_vel_y
	lda g_sonic_bounce_vel_y_sub+2
	sta sonic_vel_y_hi
	clc                       ; ld hl,(sonic_vel_x_sub) / ld a,(sonic_vel_x_hi) / add hl,de / adc a,n
	lda sonic_vel_x_sub
	adc zg_de
	sta sonic_vel_x_sub       ; ld (sonic_vel_x_sub),hl / ld (sonic_vel_x_hi),a / ret
	lda sonic_vel_x
	adc zg_de+1
	sta sonic_vel_x
	lda sonic_vel_x_hi
	adc zg_de+1
	sta sonic_vel_x_hi
	rts

; ss4c_size: (ix+13) = $1E, (ix+14) = $16 - rozmiar flippera (02:98A1, 02:98E6, 02:996C; jednakowy we wszystkich ksztaltach).
; Niszczy A, Y.
ss4c_size
	ldy #OB_W
	lda #$1E
	sta (zg_obj),y
	iny
	lda #$16
	sta (zg_obj),y
	rts

; ---------------------------------------------------------------------
; ss4c_yofs = compute_flipper_y_offset (02:9AAF): X = przesuniecie tablicy od LUT_flipper_y_offsets_00 ($00 / $20 / $40 - oryginal:
; bc = adres tablicy). Sonic leci w gore (Vy hi < 0) -> C = 0, bez zmian. Inaczej sonic_y = y flippera (ix+5/6) + tablica[(sonic_x
; + 12) & 31] (bajt ze znakiem, 16 bit; subpiksel bez zmian); sonic_vel_y (piksel lo) < 3 -> C = 1 (Sonic lezy na flipperze -
; wolajacy zmienia predkosci); >= 3 -> Vy = -Vy / 2 (24 bit: dopelnienie + 1, potem sra a / rr h / rr l - zaokraglenie w dol)
; i C = 0 (male odbicie). Niszczy A, X, Y, zg_a, zg_bc, zg_hl.
; ---------------------------------------------------------------------
ss4c_yofs
	lda sonic_vel_y_hi        ; 02:9AAF: ld a,(sonic_vel_y_hi) / and a / ret m - and a: C = 0
	bpl ss4c_ydn
	clc
	rts
ss4c_ydn
	stx zg_a                  ; bc = poczatek tablicy (przesuniecie)
	lda sonic_x               ; 02:9AB4: ld a,(sonic_x) / add a,$0C / and $1F / ld l,a / ld h,$00 / add hl,bc
	clc
	adc #$0C
	and #$1F
	clc
	adc zg_a
	tax
	lda SS4C_YOFS0-OZ_OFF,x   ; 02:9ABF: ld b,$00 / ld c,(hl) / bit 7,c / jr z @y_offset_was_positive / dec b
	sta zg_bc                 ; c (N z lda - znak przesuniecia)
	bpl ss4c_ypos
	lda #$FF                  ; b = $FF
	bne ss4c_yhi              ; zawsze
ss4c_ypos
	lda #$00                  ; b = $00
ss4c_yhi
	sta zg_bc+1
	ldy #OB_Y+1               ; 02:9AC7: hl = (ix+5/6) / add hl,bc / ld (sonic_y),hl - Sonic na profilu flippera
	clc
	lda (zg_obj),y
	adc zg_bc
	sta sonic_y
	iny
	lda (zg_obj),y
	adc zg_bc+1
	sta sonic_y+1
	lda sonic_vel_y           ; 02:9AD1: ld a,(sonic_vel_y) / cp $03 / jr nc @bounce_sonic_up_slightly
	cmp #$03
	bcs ss4c_ybnc
	sec                       ; 02:9AD8: scf / ret - C = 1
	rts
ss4c_ybnc                       ; 02:9ADA @bounce_sonic_up_slightly: ld de,$0001 / hl = (sonic_vel_y_sub), a = (sonic_vel_y_hi) /
	clc                       ; cpl l, h, a / add hl,de / adc a,$00 - (hl, a) = -Vy (24 bit)
	lda sonic_vel_y_sub
	eor #$FF
	adc #<$0001
	sta zg_hl
	lda sonic_vel_y
	eor #$FF
	adc #>$0001
	sta zg_hl+1
	lda sonic_vel_y_hi
	eor #$FF
	adc #$00
	cmp #$80                  ; 02:9AED: sra a - C = bit 7 (znak), ror: bit 7 bez zmian, C = bit 0
	ror
	ror zg_hl+1               ; 02:9AEF: rr h
	ror zg_hl                 ; 02:9AF1: rr l
	tax                       ; a
	lda zg_hl                 ; 02:9AF3: ld (sonic_vel_y_sub),hl / ld (sonic_vel_y_hi),a
	sta sonic_vel_y_sub
	lda zg_hl+1
	sta sonic_vel_y
	stx sonic_vel_y_hi
	clc                       ; 02:9AF9: and a / ret - C = 0
	rts

; ---------------------------------------------------------------------
; objfunc_21_special_stage_bouncer (02:9AFB): odbijacz etapow $20-$23. Co tick set 5, rozmiar $1C x $06, mapa
; SPRTAB_special_stage_bouncer. Ruch poziomy: (ix+18) < $60 -> Vx = $FFFF00 (-1 px/tick), >= $60 -> Vx = $000100 (+1 px/tick)
; (wbrew nazwie etykiety oryginalu "@selected_moving_left" - to ruch w prawo); (ix+18) + 1, od $C0 -> 0 (okres 192 tickow).
; (ix+17) != 0 -> (ix+17) - 1 (przerwa po odbiciu). (ix+17) = 0: kolizja (tmp_06/07 = $02/$06) -> Vy Sonica = (dopelnienie Vy +
; g_sonic_bounce_vel_y) + 1 (24 bit, = g_sonic_bounce_vel_y - Vy), (ix+17) = 8, SFX $07.
; Pola rekordu: (ix+17) przerwa 0..8, (ix+18) faza ruchu 0..$BF, (ix+24) b5.
; ---------------------------------------------------------------------
objfunc_21_ss_bouncer
	ldy #OB_FLAGS             ; 02:9AFB: set 5,(ix+24) - bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W                 ; 02:9AFF: ld (ix+13),$1C / ld (ix+14),$06 - 28 x 6
	lda #$1C
	sta (zg_obj),y
	iny
	lda #$06
	sta (zg_obj),y
	ldy #OB_SPRITE            ; 02:9B07: (ix+15/16) = SPRTAB_special_stage_bouncer (adres SMS)
	lda #<SS21_SPR
	sta (zg_obj),y
	iny
	lda #>SS21_SPR
	sta (zg_obj),y
	ldx #<$0001               ; 02:9B0F: ld hl,$0001 (l w X, h w zg_hl+1)
	lda #>$0001
	sta zg_hl+1
	ldy #18                   ; 02:9B12: ld a,(ix+18) / cp $60 / jr nc @selected_moving_left
	lda (zg_obj),y
	sta zg_a                  ; a
	cmp #$60
	bcs ss21_vx
	ldx #<$FFFF               ; 02:9B19: ld hl,$FFFF - Vx = -1 px/tick
	lda #>$FFFF
	sta zg_hl+1
ss21_vx                         ; 02:9B1C @selected_moving_left: (ix+7) = $00, (ix+8) = l, (ix+9) = h
	ldy #OB_VX
	lda #$00
	sta (zg_obj),y
	iny
	txa
	sta (zg_obj),y
	iny
	lda zg_hl+1
	sta (zg_obj),y
	ldx zg_a                  ; 02:9B26: inc a / cp $C0 / jr c @skip_wrap... / xor a
	inx
	cpx #$C0
	bcc ss21_nowrap
	ldx #0
ss21_nowrap                     ; 02:9B2C @skip_wrap_x_vel_sequence_counter: ld (ix+18),a
	txa
	ldy #18
	sta (zg_obj),y
	ldy #17                   ; 02:9B2F: ld a,(ix+17) / and a / jr nz @handle_hit_cooldown_counter
	lda (zg_obj),y
	bne ss21_cool
	lda #$02                  ; 02:9B35: ld hl,$0602 / ld (tmp_06),hl - tmp_06 = $02, tmp_07 = $06
	sta tmp_06
	lda #$06
	sta tmp_07
	jsr zc_collide            ; 02:9B3B: call check_collision_with_sonic / ret c
	bcs ss21_ret
	clc                       ; 02:9B3F: c = bounce pix_hi, de = bounce (sub, lo); hl = (sonic_vel_y_sub), a = (sonic_vel_y_hi);
	lda sonic_vel_y_sub       ; cpl l, h, a / add hl,de / adc a,c - (dopelnienie Vy) + g_sonic_bounce_vel_y (24 bit)
	eor #$FF
	adc g_sonic_bounce_vel_y_sub
	sta zg_hl
	lda sonic_vel_y
	eor #$FF
	adc g_sonic_bounce_vel_y_sub+1
	sta zg_hl+1
	lda sonic_vel_y_hi
	eor #$FF
	adc g_sonic_bounce_vel_y_sub+2
	tax                       ; a
	clc                       ; 02:9B56: ld de,$0001 / add hl,de / adc a,$00 - + 1
	lda zg_hl
	adc #<$0001
	sta sonic_vel_y_sub       ; 02:9B5C: ld (sonic_vel_y_sub),hl / ld (sonic_vel_y_hi),a
	lda zg_hl+1
	adc #>$0001
	sta sonic_vel_y
	txa
	adc #$00
	sta sonic_vel_y_hi
	ldy #17                   ; 02:9B62: ld (ix+17),$08 - przerwa 8 tickow
	lda #$08
	sta (zg_obj),y
	lda #$07                  ; 02:9B66: ld a,$07 / rst $28 / ret - odglos odbicia
	jmp play_sfx
ss21_cool                       ; 02:9B6A @handle_hit_cooldown_counter: dec (ix+17) / ret
	sec
	sbc #1
	sta (zg_obj),y
ss21_ret
	rts
