; =====================================================================
;  motion.asm - ruch obiektu i kolizje z mapa poziomu (M3.2)
;
;  Przeklad return_from_objfunc (00:32E2-00:34E5) i get_obj_level_tile_ptr_in_ram (00:36F9) z gry SMS
;  (nazwy i adresy wg dezasemblacji s1smsdisasm-gm - tylko material referencyjny, kod napisany od nowa).
;  W oryginale procedura jest adresem powrotu kazdej funkcji obiektu (try_run_objfunc_DE wklada go na
;  stos), wiec wykonuje sie po logice obiektu: najpierw ruch, potem kolizja pozioma, potem pionowa.
;  Czesc od 00:34E6 (pozycja ekranowa, draw_sprite_string) nalezy do renderera (M3.6).
;
;  Rejestry Z80 -> strona zerowa (kernel/mem.inc): IX = zg_obj (adres rekordu w lustrze RAM SMS),
;  BC = zg_bc, DE = zg_de, HL = zg_hl. Pola rekordu: OB_* (game/sms.inc). Stan w RAM po wyjsciu
;  (rekord obiektu, tmp_02/tmp_03, tmp_06) jest identyczny z oryginalem - test: tools/m3_unit.py.
;
;  Kolizja z mapa w skrocie:
;   - punkt testu: srodek boku obiektu w kierunku ruchu (poziomo: x + 0 albo x + szerokosc, y + wys/2;
;     pionowo: x + szer/2, y + 0 albo y + wysokosc);
;   - blok pod punktem -> flagi bloku & $3F = typ kolizji (0 = przepuszcza);
;   - profil typu (32 B dla kierunku pchniecia): dla wspolrzednej punktu w osi prostopadlej (mod 32)
;     przesuniecie krawedzi powierzchni w bloku (ze znakiem) albo $80 = brak powierzchni;
;   - gdy punkt wszedl za powierzchnie: pozycja = poczatek bloku + przesuniecie - przesuniecie punktu,
;     predkosc w tej osi = 0, do predkosci w drugiej osi dodany "poslizg" typu (zbocza), flaga kolizji.
;  Flagi Z80 -> 6502: "cp" Z80 ustawia C przy A < arg, 6502 "cmp" przy A >= arg - warunki odwrocone
;  w komentarzach przy kazdym porownaniu.
; =====================================================================

; ---------------------------------------------------------------------
; obj_motion: return_from_objfunc 00:32E2-00:34E5
; Wejscie: zg_obj = rekord obiektu (lustro RAM SMS). Wyjscie: X, Y, Vx, Vy, OB_FLAGS (b6, b7),
; tmp_02/tmp_03 = przesuniecie ostatniego punktu testu, tmp_06 = typ kolizji ostatniego bloku.
; Niszczy: A, X, Y, zg_bc, zg_de, zg_hl, zg_tab, zg_off, zg_prof, zg_a, zg_ptr.
; ---------------------------------------------------------------------
obj_motion
; --- X += Vx (24 bit; Z80: add hl,de na sub/lo, adc a,c na hi - ten sam wynik) ---
	clc
	ldy #OB_VX
	lda (zg_obj),y
	ldy #OB_X
	adc (zg_obj),y            ; subpiksel
	sta (zg_obj),y
	ldy #OB_VX+1
	lda (zg_obj),y
	ldy #OB_X+1
	adc (zg_obj),y            ; piksel lo (+ przeniesienie)
	sta (zg_obj),y
	ldy #OB_VX+2
	lda (zg_obj),y
	ldy #OB_X+2
	adc (zg_obj),y            ; piksel hi
	sta (zg_obj),y
; --- Y += Vy (00:32FF) ---
	clc
	ldy #OB_VY
	lda (zg_obj),y
	ldy #OB_Y
	adc (zg_obj),y
	sta (zg_obj),y
	ldy #OB_VY+1
	lda (zg_obj),y
	ldy #OB_Y+1
	adc (zg_obj),y
	sta (zg_obj),y
	ldy #OB_VY+2
	lda (zg_obj),y
	ldy #OB_Y+2
	adc (zg_obj),y
	sta (zg_obj),y
; bit 5,(ix+24): obiekt bez kolizji z mapa (np. Sonic po smierci) -> koniec (00:331C)
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$20
	jne om_done

; =====================================================================
;  Kolizja pozioma (00:3323-00:33F5)
; =====================================================================
; DE = (0, wysokosc / 2): punkt testu na srodku boku (srl e)
	ldy #OB_H
	lda (zg_obj),y
	lsr
	sta zg_de
	lda #0
	sta zg_de+1
; bit 7,(ix+8): znak Vx sprawdzany na bajcie pikseli lo (dla |Vx| < 128 px/tick = znak predkosci).
; Vx >= 0 (b7 = 0): punkt na prawym boku (C = szerokosc), profil push_left (pchniecie w lewo);
; Vx < 0  (b7 = 1): punkt na lewym boku (C = 0), profil push_right.
; Nazwy etykiet oryginalu (@obj_is_moving_right_table) sa odwrotne do tej logiki - liczy sie kod.
	ldy #OB_VX+1
	lda (zg_obj),y
	bmi om_h_neg
	ldy #OB_W
	lda (zg_obj),y            ; C = szerokosc
	ldx #PUSH_LEFT
	bne om_h_tab              ; zawsze (PUSH_LEFT <> 0)
om_h_neg
	lda #0                    ; C = 0
	ldx #PUSH_RIGHT
om_h_tab
	sta zg_bc                 ; BC = (0, C) - przesuniecie X punktu testu
	sta tmp_02                ; ld (tmp_02),bc: tmp_02 = C, tmp_03 = B = 0
	lda #0
	sta zg_bc+1
	sta tmp_02+1
	stx zg_tab
	ldy #OB_FLAGS             ; res 6,(ix+24): kasowanie flagi kolizji poziomej
	lda (zg_obj),y
	and #$BF
	sta (zg_obj),y
	jsr obj_tile_type         ; A = tmp_06 = typ kolizji bloku pod (x + C, y + wys/2)
	jeq om_h_skip             ; typ 0 = blok przepuszcza (jp z,@skip_horizontal_clamping)
	jsr obj_profile           ; zg_prof = profil[zg_tab][tmp_06]
; przesuniecie powierzchni dla wiersza punktu: profil[(y lo + wys/2) & 31] (00:3378)
	ldy #OB_Y+1
	lda (zg_obj),y
	clc
	adc zg_de                 ; E = wys/2 (DE nie zmienione przez obj_tile_type)
	and #$1F
	tay
	lda (zg_prof),y
	cmp #$80                  ; $80 = w tym wierszu bloku brak powierzchni
	jeq om_h_skip
	sta zg_off                ; E = przesuniecie (ze znakiem), D = rozszerzenie znaku przy uzyciu
; HL = X (piksele) + BC = wspolrzedna X punktu testu (00:338D)
	ldy #OB_X+1
	clc
	lda (zg_obj),y
	adc zg_bc
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_bc+1
	sta zg_hl+1
; bit 7,(ix+9): kierunek wg znaku Vx (bajt hi). Porownanie (x punktu & 31) z przesunieciem:
	ldy #OB_VX+2
	lda (zg_obj),y
	bmi om_h_left
; Vx >= 0: przesuniecie ujemne -> zawsze kolizja; inaczej kolizja, gdy (x & 31) >= przesuniecie
; (Z80: cp e / jr nc - brak pozyczki; 6502: cmp / bcs - ten sam warunek A >= E)
	lda zg_off
	bmi om_h_apply            ; and a / jp m
	lda zg_hl
	and #$1F
	cmp zg_off
	bcs om_h_apply
	jmp om_h_skip
om_h_left                       ; @compare_left_movement_clamp
; Vx < 0: przesuniecie ujemne -> kolizja; inaczej kolizja, gdy (x & 31) < przesuniecie
; (Z80: cp e / jr nc skip - pomin przy A >= E; 6502: bcs om_h_skip)
	lda zg_off
	bmi om_h_apply
	lda zg_hl
	and #$1F
	cmp zg_off
	bcs om_h_skip
om_h_apply                      ; @apply_horizontal_clamping (00:33B5)
	ldy #OB_FLAGS             ; set 6,(ix+24): kolizja pozioma
	lda (zg_obj),y
	ora #$40
	sta (zg_obj),y
; X = (HL & $FFE0) + przesuniecie (ze znakiem) - BC; subpiksel X bez zmian
	ldx #0                    ; X rejestr = rozszerzenie znaku przesuniecia (D)
	lda zg_off
	bpl om_h_dpos
	dex
om_h_dpos
	lda zg_hl
	and #$E0                  ; ld a,l / and $E0: poczatek bloku 32 px (tylko mlodszy bajt)
	clc
	adc zg_off                ; add hl,de
	sta zg_hl
	txa
	adc zg_hl+1
	sta zg_hl+1
	sec                       ; and a / sbc hl,bc (Z80 C=0 = brak pozyczki; 6502 sec)
	lda zg_hl
	sbc zg_bc
	ldy #OB_X+1
	sta (zg_obj),y
	lda zg_hl+1
	sbc zg_bc+1
	iny
	sta (zg_obj),y
; Vx = 0; Vy += sext(LUT_horizontal_vslide_factors[typ]) na bajcie subpikseli (00:33C7)
	ldx tmp_06
	lda FACT_HVSLIDE,x
	sta zg_a                  ; C = wspolczynnik
	lda #0
	ldy #OB_VX
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldx #0                    ; A i B oryginalu = rozszerzenie znaku wspolczynnika
	lda zg_a
	bpl om_hv_pos
	dex
om_hv_pos
	clc                       ; Vy(sub,lo) += BC, Vy hi += A + przeniesienie
	ldy #OB_VY
	lda (zg_obj),y
	adc zg_a
	sta (zg_obj),y
	iny
	txa
	adc (zg_obj),y
	sta (zg_obj),y
	iny
	txa
	adc (zg_obj),y
	sta (zg_obj),y
om_h_skip                       ; @skip_horizontal_clamping (00:33F6)

; =====================================================================
;  Kolizja pionowa (00:33F6-00:34E5)
; =====================================================================
; BC = (0, szerokosc / 2): punkt testu na srodku dolnego/gornego boku (srl c)
	ldy #OB_W
	lda (zg_obj),y
	lsr
	sta zg_bc
	lda #0
	sta zg_bc+1
	sta zg_de+1
; bit 7,(ix+11): znak Vy na bajcie pikseli lo. Vy >= 0 (spadanie): E = wysokosc (dolny bok), profil
; push_up (pchniecie w gore); Vy < 0 (wznoszenie): E = 0 (gorny bok), profil push_down.
	ldy #OB_VY+1
	lda (zg_obj),y
	bmi om_v_up
	ldy #OB_H
	lda (zg_obj),y            ; E = wysokosc
	ldx #PUSH_UP
	bne om_v_tab              ; zawsze (PUSH_UP <> 0)
om_v_up
	lda #0                    ; E = 0
	ldx #PUSH_DOWN
om_v_tab
	sta zg_de                 ; DE = (0, E) - przesuniecie Y punktu testu
	sta tmp_02                ; ld (tmp_02),de: tmp_02 = E, tmp_03 = D = 0
	lda #0
	sta tmp_02+1
	stx zg_tab
	ldy #OB_FLAGS             ; res 7,(ix+24): kasowanie flagi "na ziemi"
	lda (zg_obj),y
	and #$7F
	sta (zg_obj),y
	jsr obj_tile_type         ; A = tmp_06 = typ kolizji bloku pod (x + szer/2, y + E)
	jeq om_done               ; typ 0 -> @skip_vertical_and_all_clamping
	jsr obj_profile
; przesuniecie dla kolumny punktu: profil[(x lo + szer/2) & 31] (00:3450)
	ldy #OB_X+1
	lda (zg_obj),y
	clc
	adc zg_bc                 ; C = szer/2
	and #$1F
	tay
	lda (zg_prof),y
	cmp #$80
	jeq om_done               ; brak powierzchni w tej kolumnie bloku
	sta zg_off                ; C = przesuniecie, B = rozszerzenie znaku
; HL = Y (piksele) + DE = wspolrzedna Y punktu testu (00:3465)
	ldy #OB_Y+1
	clc
	lda (zg_obj),y
	adc zg_de
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_hl+1
; bit 7,(ix+12): kierunek wg znaku Vy (bajt hi). Porownanie (y punktu & 31) + magnes[typ] z przesunieciem.
; "Magnes" (LUT_y_magnet_factors) przyciaga obiekt do powierzchni z kilku pikseli (zbocza przy biegu).
	ldy #OB_VY+2
	lda (zg_obj),y
	bmi om_v_upcmp
; Vy >= 0: przesuniecie ujemne -> kolizja; inaczej pomin, gdy (y & 31) + magnes < przesuniecie
; (Z80: cp c / jr c skip; 6502: cmp / bcc - ten sam warunek A < C); przy kolizji b7 = na ziemi
	lda zg_off
	bmi om_v_apply
	lda zg_hl
	and #$1F
	ldx tmp_06
	clc
	adc FACT_YMAG,x           ; add a,(hl) - dodawanie 8-bitowe
	cmp zg_off
	bcc om_done
	ldy #OB_FLAGS             ; set 7,(ix+24): obiekt stoi na powierzchni
	lda (zg_obj),y
	ora #$80
	sta (zg_obj),y
	jmp om_v_apply
om_v_upcmp                      ; @compare_up_movement_clamp
; Vy < 0: przesuniecie ujemne -> kolizja; inaczej pomin, gdy (y & 31) + magnes >= przesuniecie
; (Z80: cp c / jr nc skip; 6502: bcs om_done); flagi "na ziemi" nie ustawia (uderzenie w sufit)
	lda zg_off
	bmi om_v_apply
	lda zg_hl
	and #$1F
	ldx tmp_06
	clc
	adc FACT_YMAG,x
	cmp zg_off
	bcs om_done
om_v_apply                      ; @apply_vertical_clamping (00:34A9)
; Y = (HL & $FFE0) + przesuniecie (ze znakiem) - DE; subpiksel Y bez zmian
	ldx #0
	lda zg_off
	bpl om_v_dpos
	dex
om_v_dpos
	lda zg_hl
	and #$E0
	clc
	adc zg_off                ; add hl,bc
	sta zg_hl
	txa
	adc zg_hl+1
	sta zg_hl+1
	sec                       ; and a / sbc hl,de
	lda zg_hl
	sbc zg_de
	ldy #OB_Y+1
	sta (zg_obj),y
	lda zg_hl+1
	sbc zg_de+1
	iny
	sta (zg_obj),y
; Vy = 0; Vx += sext(LUT_vertical_hslide_factors[typ]) na bajcie subpikseli - zjazd po zboczu (00:34B7)
	ldx tmp_06
	lda FACT_VHSLIDE,x
	sta zg_a
	lda #0
	ldy #OB_VY
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldx #0
	lda zg_a
	bpl om_vh_pos
	dex
om_vh_pos
	clc                       ; Vx(sub,lo) += BC, Vx hi += A + przeniesienie
	ldy #OB_VX
	lda (zg_obj),y
	adc zg_a
	sta (zg_obj),y
	iny
	txa
	adc (zg_obj),y
	sta (zg_obj),y
	iny
	txa
	adc (zg_obj),y
	sta (zg_obj),y
om_done                         ; @skip_vertical_and_all_clamping (00:34E6) - dalej renderer
	rts

; ---------------------------------------------------------------------
; obj_profile: zg_prof = adres profilu kolizji (32 B) z tablicy zg_tab dla typu tmp_06.
; Oryginal: HL = LUT_phys_tileflags_push_*[tmp_06 * 2] (wskaznik w banku 1; tu przeniesiony na PHYS_RAM).
; ---------------------------------------------------------------------
obj_profile
	lda zg_tab
	clc
	adc tmp_06                ; tablica (0/64/128/192) + typ (0..63) -> indeks 0..255
	tax
	lda PUSH_LO,x
	sta zg_prof
	lda PUSH_HI,x
	sta zg_prof+1
	rts

; ---------------------------------------------------------------------
; obj_tile_type: typ kolizji bloku pod punktem (x + BC, y + DE) obiektu zg_obj.
; get_obj_level_tile_ptr_in_ram (00:36F9, wariant szerokosci 256 - @width_256 00:37B3) i odczyt flag
; z tablicy strefy (00:334C-00:3361): tmp_06 = flagi[blok] & $3F.
; Adres SMS bloku = $C000 + wiersz * 256 + kolumna (16 bit, z zawinieciem), wiersz = ((y + DE) >> 5)
; & $FF, kolumna = ((x + BC) >> 5) & $FF. Poza ukladem (wiersze >= 16) gra czyta RAM zmiennych
; ($D000-$DFFF) i jego lustro ($E000-$FFFF = $C000-$DFFF) - tu te same bajty lustra RAM SMS.
; Adres < $C000 (wiersz >= $40, np. obiekt nad gorna krawedzia) wskazuje ROM - tablic ROM nie mamy,
; wiec typ = 0 i licznik v_rom_reads (w GHZ1 nie wystepuje w oknie testow).
; Wyjscie: A = tmp_06 (Z = 1, gdy 0). Zachowuje zg_bc, zg_de. Niszczy X, Y, zg_hl, zg_a, zg_ptr.
; ---------------------------------------------------------------------
obj_tile_type
	jsr obj_tile_ptr
	bcs ott_rom
	ldy #0
	lda (zg_ptr),y            ; numer bloku (bajt ukladu albo zmiennej SMS)
	tax
	lda TILEFLAGS_RAM,x       ; flagi bloku strefy (tablica PTRLUT_level_tile_flags[g_tile_flags_index])
	and #$3F
	sta tmp_06
	rts
ott_rom
	inc v_rom_reads
	lda #0
	sta tmp_06
	rts

; ---------------------------------------------------------------------
; obj_tile_ptr: get_obj_level_tile_ptr_in_ram (00:36F9, @width_256 00:37B3 i @width_128 00:370F; M6.3 - inne
; szerokosci 64/32/16: M6) - zg_ptr = adres Atari bajtu ukladu
; (albo zmiennej SMS) pod punktem (x + BC, y + DE) obiektu zg_obj. C = 1: adres SMS < $C000 (ROM, patrz
; obj_tile_type) - zg_ptr nieustawiony. Zachowuje zg_bc, zg_de. Niszczy A, Y, zg_hl, zg_a.
; ---------------------------------------------------------------------
obj_tile_ptr
	lda g_level_width         ; 00:36F9: szerokosc ukladu (mlodszy bajt; 256 -> 0)
	cmp #$80
	jeq otp_w128
	cmp #$40                  ; M6.5: etapy specjalne (64 x 64)
	jeq otp_w64
	cmp #$10                  ; M6.7: uklad pionowy 16 x 256 (JUN2)
	jeq otp_w16
	cmp #$20                  ; M6.9: pod-poziom $15 (32 x 128)
	jeq otp_w32
; wiersz = (Y + DE) >> 5 (mlodsze 8 bitow): Z80 rlca/rl h x3 na L, H
	ldy #OB_Y+1
	clc
	lda (zg_obj),y
	adc zg_de
	sta zg_hl                 ; L
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_a                  ; H
	lda zg_hl
	asl
	rol zg_a
	asl
	rol zg_a
	asl
	rol zg_a                  ; zg_a = (H << 3) | (L >> 5) = wiersz
; kolumna = (X + BC) >> 5 (mlodsze 8 bitow)
	ldy #OB_X+1
	clc
	lda (zg_obj),y
	adc zg_bc
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_bc+1
	sta zg_hl+1
	lda zg_hl
	asl
	rol zg_hl+1
	asl
	rol zg_hl+1
	asl
	rol zg_hl+1               ; zg_hl+1 = kolumna
	lda zg_hl+1
	sta zg_ptr                ; mlodszy bajt adresu = kolumna
; starszy bajt adresu SMS = $C0 + wiersz (8 bit); mapowanie na pamiec Atari
otp_map                         ; zg_ptr = mlodszy bajt adresu SMS, zg_a = (adres - $C000) >> 8
	lda zg_a
	cmp #$40
	bcs otp_rom               ; $C0 + wiersz >= $100: adres SMS < $C000 - ROM (patrz opis obj_tile_type)
	and #$1F                  ; lustro: $E000-$FFFF = $C000-$DFFF
	cmp #$10
	bcs otp_vars
	adc #>LAYOUT_RAM          ; $C0-$CF -> $10-$1F (C = 0 po cmp)
	bne otp_ptr               ; zawsze
otp_vars
	adc #>[MIRROR_RAM-$1000]-1 ; $D0-$DF -> $E0-$EF (C = 1 po cmp: +$CF+1)
otp_ptr
	sta zg_ptr+1
	clc
	rts
otp_rom
	sec
	rts

; @width_128 (00:370F): adres = $C000 + H' * 256 + E + kolumna (16 bit, z przeniesieniem), H' = (Y16 << 2) >> 8
; (rl h x2 na H z L), E = (L << 2) & $80, L/H = Y + DE; kolumna = ((X + BC) >> 5) & $FF jak w 256. Wiersz r = (Y >> 5):
; H' = r >> 1, E = (r & 1) << 7 - uklad 128 x 32, stride 128.
otp_w128
	ldy #OB_Y+1
	clc
	lda (zg_obj),y
	adc zg_de
	sta zg_hl                 ; L
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_a                  ; H
	lda zg_hl
	asl
	rol zg_a
	asl
	rol zg_a                  ; zg_a = H' (add a,a / rl h x2)
	and #$80
	sta zg_ptr                ; E = (L << 2) & $80
otp_wcol                        ; kolumna: ((X + BC) >> 5) & $FF (wspolna czesc @width_128 i @width_64)
	ldy #OB_X+1
	clc
	lda (zg_obj),y
	adc zg_bc
	sta zg_hl
	iny
	lda (zg_obj),y
	adc zg_bc+1
	sta zg_hl+1
	lda zg_hl
	asl
	rol zg_hl+1
	asl
	rol zg_hl+1
	asl
	rol zg_hl+1               ; zg_hl+1 = kolumna
	lda zg_hl+1
	clc
	adc zg_ptr                ; HL = kolumna + DE (D = H', E)
	sta zg_ptr
	lda zg_a
	adc #0
	sta zg_a                  ; (adres - $C000) >> 8 (ld de, $C000 / add hl, de: wspolna czesc z @width_256)
	jmp otp_map

; @width_64 (00:373B): H' = (Y16 << 1) >> 8 (rl h z add a,a), E = (L << 1) & $C0 - uklad 64 x 64, wiersz r = (Y >> 5):
; H' = r >> 2, E = (r & 3) << 6, stride 64.
otp_w64
	ldy #OB_Y+1
	clc
	lda (zg_obj),y
	adc zg_de
	sta zg_hl                 ; L
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_a                  ; H
	lda zg_hl
	asl
	rol zg_a                  ; zg_a = H' (add a,a / rl h)
	and #$C0
	sta zg_ptr                ; E = (L << 1) & $C0
	jmp otp_wcol

; @width_32 (00:3764, M6.9): DE = (Y16 + DE) & $FFE0 (L & $E0, H bez zmian) - uklad 32 x 128 ($15), wiersz r = (Y >> 5):
; H' = r >> 3, E = (r & 7) << 5, stride 32. Kolumna jak w pozostalych (otp_wcol).
otp_w32
	ldy #OB_Y+1
	clc
	lda (zg_obj),y
	adc zg_de
	and #$E0                  ; and nie zmienia C - przeniesienie do starszego bajtu
	sta zg_ptr                ; E = L & $E0
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_a                  ; H' = H
	jmp otp_wcol

; @width_16 (00:378A): H' = Y16 >> 9 (srl h), E = ((Y16 >> 1) & $F0) - uklad 16 x 256, wiersz r = (Y >> 5): H' = r >> 4,
; E = (r & 15) << 4, stride 16.
otp_w16
	ldy #OB_Y+1
	clc
	lda (zg_obj),y
	adc zg_de
	sta zg_hl                 ; L
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_a                  ; H
	lsr zg_a                  ; srl h
	lda zg_hl
	ror                       ; rra
	and #$F0
	sta zg_ptr
	jmp otp_wcol

; ---------------------------------------------------------------------
; phys_init: tablice kolizji z banku poziomu: flagi blokow -> TILEFLAGS_RAM ($0F00),
; obraz tablic (wspolczynniki, wskazniki, profile) -> PHYS_RAM ($C000, RAM pod OS). Z level_init.
; ---------------------------------------------------------------------
phys_init
	lda v_pblevel             ; M6.3: bank poziomu (GHZ1 35, GHZ2 55)
	sta PORTB
	lda #1
	sta zp_cnt
	lda #>[BANK_WIN+LB_TILEFLAGS]
	ldx #>TILEFLAGS_RAM
	jsr copy_pages
	lda #16
	sta zp_cnt
	lda #>[BANK_WIN+LB_PHYS]
	ldx #>PHYS_RAM
	jsr copy_pages
	lda #4                    ; dane Sonica (fizyka, bloki specjalne, animacje) -> SONIC_RAM $F000 (M3.3)
	sta zp_cnt
	lda #>[BANK_WIN+LB_SONIC]
	ldx #>SONIC_RAM
	jsr copy_pages
	lda #PB_MAIN
	sta PORTB
	rts
