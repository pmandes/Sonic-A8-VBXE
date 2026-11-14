; =====================================================================
;  obj/objz2_sbz_drzwi.asm - M6.9 Scrap Brain: drzwi $17 / $18 / $19 / $1E (bank obiektow strefy 2 PB_OBJZ2, bank 2, dolaczany
;  z objz2.asm).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny):
;   objfunc_17_SCR_door_open_on_left 02:9DFA-02:9E7D, wspolne door_common_epilogue 02:9E7E, door_opening 02:9EB4, door_closing 02:9EC4,
;   door_common_prep 02:9ED4-02:9F2A; dane SPRTAB_SCR_door_open_on_left 02:9F2B-02:9F61 (OZ2_SPAN4);
;   objfunc_18_SCR_door_open_on_right 02:9F62-02:9FED, dane SPRTAB_SCR_door_open_on_right 02:9FEE-02:A024 (OZ2_SPAN5);
;   objfunc_19_SCR_door_open_on_both_sides 02:A025-02:A0B0, dane SPRTAB_SCR_door_open_on_both_sides 02:A0B1-02:A0E7 (OZ2_SPAN6);
;   objfunc_1E_SCR_door_from_button 02:A4AB-02:A519, dane SPRTAB_SCR_door_from_button 02:A51A-02:A550 (OZ2_SPAN11).
;  Procedury:
;   objfunc_17_door_left    (02:9DFA) - funkcja obiektu $17 (drzwi otwierane z lewej)
;   objfunc_18_door_right   (02:9F62) - funkcja obiektu $18 (drzwi otwierane z prawej)
;   objfunc_19_door_both    (02:A025) - funkcja obiektu $19 (drzwi otwierane z obu stron)
;   objfunc_1E_door_button  (02:A4AB) - funkcja obiektu $1E (drzwi sterowane przyciskiem $1D)
;   dr_start   - wspolny poczatek 4 drzwi: set 5,(ix+24), door_common_prep, pchniecie Sonica (02:9DFA-02:9E30 i odpowiedniki)
;   dr_prep    (02:9ED4) - door_common_prep
;   dr_window  - okno Sonika (02:9E33-02:9E7A i odpowiedniki w $18/$19) -> dr_open / dr_close
;   dr_open    (02:9EB4) - door_opening
;   dr_close   (02:9EC4) - door_closing
;   dr_epi     (02:9E7E) - door_common_epilogue
;  Wolane: obj_tile_ptr (get_obj_level_tile_ptr_in_ram 00:36F9, game/motion.asm - rezydentne), level_mask (calc_level_offset_HL_and_mask_C
;  00:0C02, game/objcom.asm - rezydentne), play_sfx (rst $28, rezydentne), zc_collide (check_collision_with_sonic 00:3956 - stub do banku 45).
;  Mapy sprite'ow: do (ix+15/16) trafiaja adresy SMS ($9F2B... - kopiuje je objz_mapcopy z tego banku); kod nie czyta danych banku.
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl; C (bajt przesuniecia / maska) = zg_a.
; ---------------------------------------------------------------------
; Pola rekordu: (ix+17) stan otwarcia 0..$30 (0 = zamkniete, $30 = otwarte; $1E: krok 2), (ix+18/19) Y bazowe (y z pierwszego ticku),
; (ix+24) b0 = zainicjowane, b1 = blok nad drzwiami <> $A3 (x + 4 zamiast x + $14; w $1E odwraca warunek przycisku), b5 = bez kolizji
; z mapa (ustawiane co tick).
; Co tick: szerokosc 4, wysokosc (3 - ((ix+17) >> 4 & 3)) * 16 (48 / 32 / 16 / 0 - drzwi chowaja sie w gore). Pierwszy tick
; (b0 = 0): blok ukladu nad drzwiami (x, y - 16) = $A3 -> x += $14, inaczej x += 4 i set 1; (ix+18/19) = y; set 0.
; Przy (ix+17) < $28 drzwi sa twarde: trafienie Sonica (przesuniecie (5, 0)) -> sonic_x = x + 5 (Sonic leci w lewo, Vx hi < 0)
; albo x - 20 (w prawo / stoi), Vx Sonika = 0 (24 bit).
; $17/$18/$19: Sonic w oknie (lewa granica x + L < sonic_x <= x + P, y - 32 < sonic_y <= y + $50; sumy 16 bit obciete, porownania
; bez znaku; y = biezace (ix+5/6), czyli juz podniesione o (ix+17) & $0F) -> otwieranie (+1 do $30; SFX $19 przy starcie z 0), poza
; oknem -> zamykanie (-1 do 0; SFX $19 przy zejsciu z $30 na $2F). L/P: $17 = -$38 / 0, $18 = -$10 / +$24, $19 = -$38 / +$24.
; $1E: otwieranie (+2 dopoki < $30) gdy bit przycisku poziomu (g_level_button_toggled_on_mask, bit g_level) XOR b1 = 1, inaczej
; zamykanie (-2 dopoki <> 0); bez SFX. Uwaga (wiernie): przy nieparzystym (ix+17) zamykanie z 1 daje $FF (przy starcie od 0 i
; krokach 2 nie wystepuje).
; Epilog: y = (ix+18/19) - ((ix+17) & $0F) (16 bit), mapa = SPRTAB + 18 * ((ix+17) >> 4 & 3). Klatka 3 (otwarte) zaczyna sie
; bajtem $FF (koniec zakresu danych) - draw_sprite_string konczy na nim, wiec 17 dalszych bajtow kopii mapy (kod portu) nie jest czytane.
; =====================================================================
; adresy SMS map sprite'ow (zapisywane do (ix+15/16); zakresy OBJZ2_SPANS, w tym banku pod SMS - OZ_OFF)
SPR_DR7         = $9F2B   ; SPRTAB_SCR_door_open_on_left (4 klatki po 18 B; kafle $0A / $3E / $0A, ostatnia klatka = $FF)
SPR_DR8         = $9FEE   ; SPRTAB_SCR_door_open_on_right ($36 / $3E / $36)
SPR_DR9         = $A0B1   ; SPRTAB_SCR_door_open_on_both_sides ($38 / $3E / $38)
SPR_DRB         = $A51A   ; SPRTAB_SCR_door_from_button ($3E / $38 / $3E)

; ---------------------------------------------------------------------
; objfunc_17_SCR_door_open_on_left (02:9DFA): okno x - $38 < sonic_x <= x (prawa granica bez dodawania: ld l,(ix+2) / ld h,(ix+3),
; 02:9E46 - tu x + 0, wynik ten sam).
; ---------------------------------------------------------------------
objfunc_17_door_left
	jsr dr_start              ; 02:9DFA-02:9E30: set 5,(ix+24) / call door_common_prep / pchniecie Sonica
	lda #<$FFC8               ; 02:9E39: ld de,$FFC8 - lewa granica x - $38
	sta zg_bc
	lda #>$FFC8
	sta zg_bc+1
	lda #$00                  ; 02:9E46: prawa granica x (+ 0)
	sta zg_de
	sta zg_de+1
	jsr dr_window             ; 02:9E33-02:9E78: call door_opening / door_closing wg okna
	lda #<SPR_DR7             ; 02:9E7B: ld de,SPRTAB_SCR_door_open_on_left
	ldx #>SPR_DR7
	jmp dr_epi                ; door_common_epilogue (02:9E7E - w oryginale kod bezposrednio dalej)

; ---------------------------------------------------------------------
; objfunc_18_SCR_door_open_on_right (02:9F62): okno x - $10 < sonic_x <= x + $24.
; ---------------------------------------------------------------------
objfunc_18_door_right
	jsr dr_start              ; 02:9F62-02:9F99: set 5,(ix+24) / call door_common_prep / pchniecie Sonica
	lda #<$FFF0               ; 02:9FA2: ld de,$FFF0 - lewa granica x - $10
	sta zg_bc
	lda #>$FFF0
	sta zg_bc+1
	lda #$24                  ; 02:9FB5: ld bc,$0024 - prawa granica x + $24
	sta zg_de
	lda #$00
	sta zg_de+1
	jsr dr_window             ; 02:9F9C-02:9FE5
	lda #<SPR_DR8             ; 02:9FE8: ld de,SPRTAB_SCR_door_open_on_right / jp door_common_epilogue
	ldx #>SPR_DR8
	jmp dr_epi

; ---------------------------------------------------------------------
; objfunc_19_SCR_door_open_on_both_sides (02:A025): okno x - $38 < sonic_x <= x + $24.
; ---------------------------------------------------------------------
objfunc_19_door_both
	jsr dr_start              ; 02:A025-02:A05C: set 5,(ix+24) / call door_common_prep / pchniecie Sonica
	lda #<$FFC8               ; 02:A065: ld de,$FFC8 - lewa granica x - $38
	sta zg_bc
	lda #>$FFC8
	sta zg_bc+1
	lda #$24                  ; 02:A078: ld bc,$0024 - prawa granica x + $24
	sta zg_de
	lda #$00
	sta zg_de+1
	jsr dr_window             ; 02:A05F-02:A0A8
	lda #<SPR_DR9             ; 02:A0AB: ld de,SPRTAB_SCR_door_open_on_both_sides / jp door_common_epilogue
	ldx #>SPR_DR9
	jmp dr_epi

; ---------------------------------------------------------------------
; objfunc_1E_SCR_door_from_button (02:A4AB): otwieranie / zamykanie o 2 wg bitu przycisku poziomu (patrz opis pliku).
; ---------------------------------------------------------------------
objfunc_1E_door_button
	jsr dr_start              ; 02:A4AB-02:A4E2: set 5,(ix+24) / call door_common_prep / pchniecie Sonica
	; 02:A4E5: ld hl,g_level_button_toggled_on_mask / call calc_level_offset_HL_and_mask_C:
	; level_mask: X = g_level >> 3 (bajt maski), A = 1 << (g_level & 7) (C)
	jsr level_mask
	sta zg_a                  ; c = bit poziomu
	ldy #OB_FLAGS             ; 02:A4EB: bit 1,(ix+24) / jr z,@detect_if_closing
	lda (zg_obj),y
	and #$02
	beq drb_det
	lda g_level_button_toggled_on_mask,x ; 02:A4F1: b1 = 1 (blok nad drzwiami <> $A3): ld a,(hl) / and c / jr nz,@door_is_closing
	and zg_a
	bne drb_close             ; bit przycisku ustawiony -> zamykanie
	beq drb_open              ; jr @door_is_opening (zawsze)
drb_det                         ; @detect_if_closing (02:A4F7): b1 = 0 (blok $A3): ld a,(hl) / and c / jr z,@door_is_closing
	lda g_level_button_toggled_on_mask,x
	and zg_a
	beq drb_close             ; bit przycisku skasowany -> zamykanie
drb_open                        ; @door_is_opening (02:A4FB): ld a,(ix+17) / cp $30 / jr nc,@continue_to_epilogue
	ldy #17
	lda (zg_obj),y
	cmp #$30
	bcs drb_epi
	adc #$02                  ; inc a / inc a (C = 0 po cmp; wynik < $32 - bez przeniesienia) / ld (ix+17),a
	sta (zg_obj),y
	bcc drb_epi               ; jr @continue_to_epilogue (zawsze: C = 0)
drb_close                       ; @door_is_closing (02:A509): ld a,(ix+17) / and a / jr z,@continue_to_epilogue
	ldy #17
	lda (zg_obj),y
	beq drb_epi
	sec                       ; dec a / dec a / ld (ix+17),a (z 1 -> $FF - jak w oryginale)
	sbc #$02
	sta (zg_obj),y
drb_epi                         ; @continue_to_epilogue (02:A514): ld de,SPRTAB_SCR_door_from_button / jp door_common_epilogue
	lda #<SPR_DRB
	ldx #>SPR_DRB
	jmp dr_epi

; ---------------------------------------------------------------------
; dr_start: wspolny poczatek drzwi $17/$18/$19/$1E (02:9DFA-02:9E30, 02:9F62-02:9F99, 02:A025-02:A05C, 02:A4AB-02:A4E2):
; set 5,(ix+24), call door_common_prep; przy (ix+17) < $28 i trafieniu Sonica (tmp_06 = $0005) pchniecie Sonica:
; sonic_x = x + 5 (Vx hi Sonika < 0) albo x + $FFEC (x - 20), Vx Sonika = 0. W $17 zerowanie Vx przez ld (sonic_vel_x_sub),hl
; (hl = 0: $D403/$D404) i ld (sonic_vel_x_hi),a - wynik ten sam co trzy zapisy bajtow w $18/$19/$1E.
; Niszczy A, X, Y, zg_bc, zg_de, zg_hl, zg_a, zg_ptr.
; ---------------------------------------------------------------------
dr_start
	ldy #OB_FLAGS             ; set 5,(ix+24): bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	jsr dr_prep               ; call door_common_prep
	ldy #17                   ; ld a,(ix+17) / cp $28 / jr nc,@skip_collision_with_sonic (drzwi uchylone - przechodnie)
	lda (zg_obj),y
	cmp #$28
	bcs dr_sret
	lda #$05                  ; ld hl,$0005 / ld (tmp_06),hl: tmp_06 = $05, tmp_07 = $00
	sta tmp_06
	lda #$00
	sta tmp_07
	jsr zc_collide            ; call check_collision_with_sonic: C = 1 brak trafienia
	bcs dr_sret               ; jr c,@skip_collision_with_sonic
	lda sonic_vel_x_hi        ; ld de,$0005 / ld a,(sonic_vel_x_hi) / and a / jp m,@sonic_was_going_left
	bmi dr_sleft
	lda #<$FFEC               ; ld de,$FFEC: Sonic w prawo (albo stoi) - zostaje 20 px na lewo od drzwi
	ldx #>$FFEC
	bne dr_sadd               ; zawsze (X = $FF)
dr_sleft                        ; Sonic w lewo: de = $0005 - zostaje na prawo od drzwi
	lda #$05
	ldx #$00
dr_sadd                         ; @sonic_was_going_left: hl = (ix+2,3) + de / ld (sonic_x),hl
	ldy #OB_X+1
	clc
	adc (zg_obj),y
	sta sonic_x
	txa                       ; (txa / iny nie zmieniaja C)
	iny
	adc (zg_obj),y
	sta sonic_x+1
	lda #$00                  ; xor a: Vx Sonika = 0 (sub, lo, hi)
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
dr_sret                         ; @skip_collision_with_sonic
	rts

; ---------------------------------------------------------------------
; dr_prep: door_common_prep (02:9ED4) - szerokosc / wysokosc wg stanu otwarcia; raz (b0 = 0): blok nad drzwiami, przesuniecie x,
; Y bazowe. Niszczy A, Y, zg_bc, zg_de, zg_hl, zg_a, zg_ptr.
; ---------------------------------------------------------------------
dr_prep
	ldy #OB_W                 ; ld (ix+13),$04
	lda #$04
	sta (zg_obj),y
	ldy #17                   ; ld a,(ix+17) / srl a x4 / and $03 / ld e,a
	lda (zg_obj),y
	lsr
	lsr
	lsr
	lsr
	and #$03
	eor #$03                  ; ld a,$03 / sub e (dla e = 0..3: 3 - e = 3 xor e)
	asl                       ; add a,a x4: * 16
	asl
	asl
	asl
	ldy #OB_H                 ; ld (ix+14),a
	sta (zg_obj),y
	ldy #OB_FLAGS             ; bit 0,(ix+24) / ret nz
	lda (zg_obj),y
	and #$01
	bne dr_pret
	lda #$00                  ; ld bc,$0000 / ld de,$FFF0 / call get_obj_level_tile_ptr_in_ram: blok ukladu pod (x, y - 16)
	sta zg_bc
	sta zg_bc+1
	lda #$F0
	sta zg_de
	lda #$FF
	sta zg_de+1
	jsr obj_tile_ptr          ; zg_ptr = adres bajtu ukladu; C = 1 - adres SMS < $C000 (ROM)
	bcs dr_prom
	ldy #0                    ; ld de,$0014 / ld a,(hl) / cp $A3 / jr z,@tile_was_not_A3
	lda (zg_ptr),y
	cmp #$A3
	bne dr_pnot
	lda #$14                  ; blok $A3: de = $0014, b1 bez zmian (etykieta @tile_was_not_A3 w dezasemblacji odwrocona)
	bne dr_padd               ; zawsze
dr_prom                         ; adres ROM SMS (port nie ma ROM-u): jak blok inny niz $A3, v_rom_reads + 1 (precedens:
	inc v_rom_reads           ; reposition_monitor_on_init, gargulec $3F)
dr_pnot                         ; blok <> $A3: ld de,$0004 / set 1,(ix+24)
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
	lda #$04
dr_padd                         ; @tile_was_not_A3: (ix+2,3) += de (d = 0)
	ldy #OB_X+1
	clc
	adc (zg_obj),y
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #$00
	sta (zg_obj),y
	ldy #OB_Y+1               ; ld a,(ix+5) / ld (ix+18),a / ld a,(ix+6) / ld (ix+19),a: Y bazowe
	lda (zg_obj),y
	ldy #18
	sta (zg_obj),y
	ldy #OB_Y+2
	lda (zg_obj),y
	ldy #19
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
dr_pret
	rts

; ---------------------------------------------------------------------
; dr_window: okno Sonika drzwi $17/$18/$19 (02:9E33-02:9E78, 02:9F9C-02:9FE5, 02:A05F-02:A0A8). Wejscie: zg_bc = przesuniecie lewej
; granicy (16 bit), zg_de = prawej. Sonic w oknie -> door_opening (dr_open), inaczej door_closing (dr_close).
; Porownania 16 bit bez znaku jak sbc hl,de (Z80 nc = bez pozyczki = 6502 C = 1); sumy z przeniesieniem odrzuconym (xor a / and a
; przed sbc kasuje C). Niszczy A, Y, zg_hl.
; ---------------------------------------------------------------------
dr_window
	ldy #OB_X+1               ; ld l,(ix+2) / ld h,(ix+3) / ld de,L / add hl,de
	clc
	lda (zg_obj),y
	adc zg_bc
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_bc+1
	sta zg_hl+1
	sec                       ; ld de,(sonic_x) / xor a / sbc hl,de / jr nc,@door_is_closing: x + L >= sonic_x -> zamykanie
	lda zg_hl
	sbc sonic_x
	lda zg_hl+1
	sbc sonic_x+1
	bcs dr_close
	ldy #OB_X+1               ; ld l,(ix+2) / ld h,(ix+3) [/ ld bc,P / add hl,bc]
	clc
	lda (zg_obj),y
	adc zg_de
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_hl+1
	sec                       ; and a / sbc hl,de / jr c,@door_is_closing: x + P < sonic_x -> zamykanie
	lda zg_hl
	sbc sonic_x
	lda zg_hl+1
	sbc sonic_x+1
	bcc dr_close
	ldy #OB_Y+1               ; ld l,(ix+5) / ld h,(ix+6) / ld de,$FFE0 / add hl,de: y - 32
	clc
	lda (zg_obj),y
	adc #<$FFE0
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #>$FFE0
	sta zg_hl+1
	sec                       ; ld de,(sonic_y) / xor a / sbc hl,de / jr nc,@door_is_closing: y - 32 >= sonic_y -> zamykanie
	lda zg_hl
	sbc sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcs dr_close
	ldy #OB_Y+1               ; ld l,(ix+5) / ld h,(ix+6) / ld bc,$0050 / add hl,bc: y + $50
	clc
	lda (zg_obj),y
	adc #$50
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #$00
	sta zg_hl+1
	sec                       ; and a / sbc hl,de / jr c,@door_is_closing: y + $50 < sonic_y -> zamykanie
	lda zg_hl
	sbc sonic_y
	lda zg_hl+1
	sbc sonic_y+1
	bcc dr_close
	; Sonic w oknie: call door_opening - dalej dr_open

; ---------------------------------------------------------------------
; dr_open: door_opening (02:9EB4) - (ix+17) + 1 dopoki < $30; przy starcie z 0 SFX $19. Niszczy A, Y.
; ---------------------------------------------------------------------
dr_open
	ldy #17                   ; ld a,(ix+17) / cp $30 / ret nc
	lda (zg_obj),y
	cmp #$30
	bcs dr_oret
	adc #$01                  ; inc a (C = 0 po cmp) / ld (ix+17),a
	sta (zg_obj),y
	cmp #$01                  ; dec a / ret nz: stara wartosc <> 0 (nowa <> 1) -> bez dzwieku
	bne dr_oret
	lda #$19                  ; ld a,$19 / rst $28: drzwi ruszaja
	jmp play_sfx
dr_oret
	rts

; ---------------------------------------------------------------------
; dr_close: door_closing (02:9EC4) - (ix+17) - 1 dopoki <> 0; przy zejsciu z $30 na $2F SFX $19. Niszczy A, Y.
; ---------------------------------------------------------------------
dr_close
	ldy #17                   ; ld a,(ix+17) / and a / ret z
	lda (zg_obj),y
	beq dr_cret
	sec                       ; dec a / ld (ix+17),a
	sbc #$01
	sta (zg_obj),y
	cmp #$2F                  ; cp $2F / ret nz
	bne dr_cret
	lda #$19                  ; ld a,$19 / rst $28: drzwi ruszaja (z pelnego otwarcia)
	jmp play_sfx
dr_cret
	rts

; ---------------------------------------------------------------------
; dr_epi: door_common_epilogue (02:9E7E). Wejscie: A/X = adres SMS SPRTAB drzwi (de). y = (ix+18/19) - ((ix+17) & $0F) (16 bit),
; (ix+15/16) = SPRTAB + 18 * (((ix+17) >> 4) & 3). Niszczy A, Y, zg_de, zg_a.
; ---------------------------------------------------------------------
dr_epi
	sta zg_de                 ; de = SPRTAB
	stx zg_de+1
	ldy #17                   ; ld a,(ix+17) / and $0F / ld c,a / ld b,$00
	lda (zg_obj),y
	and #$0F
	sta zg_a
	ldy #18                   ; ld l,(ix+18) / ld h,(ix+19) / and a / sbc hl,bc
	sec
	lda (zg_obj),y
	sbc zg_a
	ldy #OB_Y+1               ; ld (ix+5),l (ldy nie zmienia C - pozyczka do starszego bajtu)
	sta (zg_obj),y
	ldy #19
	lda (zg_obj),y
	sbc #$00
	ldy #OB_Y+2               ; ld (ix+6),h
	sta (zg_obj),y
	ldy #17                   ; ld a,(ix+17) / srl a x4 / and $03: klatka 0..3
	lda (zg_obj),y
	lsr
	lsr
	lsr
	lsr
	and #$03
	asl                       ; add a,a / ld c,a: 2 * klatka
	sta zg_a
	asl                       ; add a,a x3: 16 * klatka
	asl
	asl
	clc                       ; add a,c: 18 * klatka (<= 54) / ld c,a / ld b,$00
	adc zg_a
	clc                       ; ex de,hl / add hl,bc / ld (ix+15),l / ld (ix+16),h
	adc zg_de
	ldy #OB_SPRITE
	sta (zg_obj),y
	lda zg_de+1
	adc #$00
	iny
	sta (zg_obj),y
	rts
