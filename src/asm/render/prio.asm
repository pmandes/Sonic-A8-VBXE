; =====================================================================
;  prio.asm - M7.5 (docs/plan-m7-ntsc.md 2): priorytet tla i przednie wpisy sprite'ow pod NTSC. Kod pod oknem (CODE_LO) -
;  cala budowa listy (build_list -> obj_bcbs) biegnie przy PORTB = PB_MAIN; kod rezydentny $8000-$BFFF nie rosnie (obj_bcbs
;  zmienia tylko cele jsr, prio_rect skrocony o szybki test).
;
;  Z4 - mapa priorytetu okna (PRIOCOLM, kernel/mem.inc): bit (r & 7) bajtu (c & 15) = blok w slocie (c & 15, r & 7) pierscienia
;  tla ma priorytet. Pierscien trzyma okno 9 x 7 blokow kamery, a kazdy blok trafia do niego przez emit_block (render/frame.asm:
;  doladowana kolumna / wiersz, pelne przeladowanie, lata patch_block_m) - tam bit jest ustawiany (PRIO_RAM[k], wiersz < v_lvh),
;  a kolumna / wiersz / cale okno zerowane przed doladowaniem. Mapa = pamiec podreczna odczytow LAYOUT_RAM + PRIO_RAM dla okna
;  (zamiast 63 odczytow ukladu w prio_blocks co ramke): uklad w poziomie zmieniaja tylko pierscienie (bloki z pierscieniem i bez
;  maja ten sam priorytet - sprawdzone dla wszystkich stref) i most BRI (bloki ukladu $88 / $89 / $8A / 0 - kody specjalne
;  $18-$1A w game/sonic.asm sp_18; zaden nie ma priorytetu - sprawdzone na danych BRI1-3, review M7.5 docs/plan-m7.md 12.1); kazda
;  inna zmiana ukladu idzie przez pelne przeladowanie (restart, pod-poziom). Bity kolumn spoza okna i wiersza pierscienia (by + 7)
;  & 7 sa nieaktualne - czytajacy je maskuja (pp_scan) albo tylko zawezaja test (prq_map: falszywy "tak" konczy sie dokladnym
;  prq_full / prio_part z ukladu - wynik ten sam).
;
;  Z1 + Z4 + Z5 - sciezka blokowa (prio_path, zamiast prio_blocks M6.10): bloki z priorytetem w oknie emitowane wprost (jeden BCB
;  na widoczna czesc bloku: magazyn -> bufor, stencil - te same pola, ktore dawal prio_rect / prio_part dla prostokata bloku),
;  bez prostokatow or_* i prio_rect. Kolejnosc BCB: kolumnami okna (w M6.10 wierszami) - bloki sie nie nakladaja, obraz ten sam.
;  Pamiec Z1: przy kamerze, slocie startowym (v_oslot) i buforze jak w poprzedniej liscie tego kompletu, ktora tez wziela
;  sciezke blokowa (PM_WAS), BCB priorytetu wciaz leza w slotach v_oslot.. (piszacy te sloty: obiekty < v_oslot, prio_part
;  i prio_path; inna sciezka w posredniej liscie kompletu zeruje PM_OK - build_list) - wtedy tylko zp_last z pamieci.
;  Uniewaznienie: zmiana ukladu (build_frame_list: v_patch_on | v_full - oba komplety), nt_reset (hud_clear przed init_list_set).
;  Regula wyboru sciezki (Z4, zamiast v_ngrp >= 8 i <= 14 blokow; n = bloki z priorytetem w oknie): kamera jak w poprzedniej
;  liscie kompletu - blokowa (pamiec Z1; bez pamieci przy n <= PRB_STAT); inaczej blokowa, gdy n <= PRB_FEW + PRB_KG * v_ngrp
;  (koszt blokow wobec obwiedni grup - stale nizej); w pozostalych - obwiednie
;  grup (grp_rects, prio_rect z szybkim testem prq_map). Obie sciezki daja ten sam obraz (piksele blokow z priorytetem nad kazdym
;  sprite'em; poza sprite'ami blok z magazynu = ten sam blok w pierscieniu: bloki z priorytetem nie maja pierscieni ani lat
;  kwiatow / kapsuly GHZ - sprawdzone na danych stref; szyba SKY3 trafia do magazynu i pierscienia przez patch_block).
;
;  Z5 - przednie wpisy tablicy sprite'ow (front_digit_f / front_objs_f: linia wody LAB, cyfra tonienia, chmury SKY2): wpis 8x16
;  w calosci na ekranie -> BCB wprost (pola jak s16_clip + obj_emit, prostokat or_* jak obj_emit), reszta jak dawniej (s16_clip).
;  (Plan Z5 przewidywal OKIND_RAM - rodzaj BCB slotu obiektu, by pisac 5 zamiast 13 pol; odrzucone: wymagaloby wpisu w
;  rezydentnym obj_emit, a zysk ponad zapis 13 pol wprost to ok. 60 cykli na wpis.)
; =====================================================================
	.if SKIND_RAM+2*N_SPR_SLOTS>NT_RAM
	.error "M7.5: NT_RAM ($09D0) nachodzi na SKIND_RAM"
	.endif
	.if SLOT_PRIO+63>N_SLOTS
	.error "M7.5: prio_path zaklada miejsce na 63 BCB blokow okna za obiektami (bez testu slotu)"
	.endif

; Z4 - regula wyboru sciezki (koszt: blok ok. 230 cykli + 300 na ramke; obwiednie: grupa ok. 600 (grp_rects + gr_split) + prostokat
; 100-400 (prio_rect: szybki test / czesci) - rownowaga przy n ~ 3,7 * grupy + 1): blokowa, gdy n <= PRB_FEW + PRB_KG * v_ngrp; przy
; kamerze jak w poprzedniej liscie kompletu - blokowa, gdy n <= max(PRB_STAT, ten prog) (koszt CPU raz, potem pamiec Z1 ok. 60 cykli;
; BCB blokow blitter wykonuje w kazdej ramce - review M7.5: profile NTSC przed / po w JUN1-3, BRI2, GHZ2 bez wzrostu listy blittera
; ponad budzet, docs/plan-m7.md 12.1). pp_scan liczy bloki tylko do progu - wiecej = obwiednie (wybor ten sam, bez pelnego liczenia).
PRB_FEW      = 3
PRB_KG       = 3
PRB_STAT     = 16

; ---------------------------------------------------------------------
; nt_reset: pamieci podreczne M7.5 od nowa (klucze Z1 / Z2 / Z6, mapa priorytetu). Wolane z hud_clear (render/hud.asm) - level_boot
; i tele_reload wolaja hud_clear przed init_lists / init_list_set obu kompletow (szablony BCB nadpisuja sloty).
; ---------------------------------------------------------------------
nt_reset
	lda #0
	ldx #NT_RAM_END-NT_RAM-1
ntr_l
	sta NT_RAM,x
	dex
	bpl ntr_l
	ldx #NT2_RAM_END-NT2_RAM-1
ntr_l2
	sta NT2_RAM,x
	dex
	bpl ntr_l2
	ldx #6                    ; pp_rows: wiersze 1-6 - pierwsza linia bloku 0, wiersze 1-5 - wysokosc 32 (stale)
ntr_r
	sta PB_RLY,x
	sta PB_RSM,x
	dex
	bne ntr_r
	lda #31
	ldx #5
ntr_h
	sta PB_RH,x
	dex
	bne ntr_h
	lda #$FF                  ; klucze pp_rows niewazne (ly <= 31, by & 7 <= 7)
	sta PB_KLY
	sta PB_KBY
	rts

; ---------------------------------------------------------------------
; prio_path (Z1 / Z4 / Z5): wolane z obj_bcbs (render/sprites.asm), gdy okno kamery ma blok z priorytetem (PRIOWIN_RAM), po
; wszystkich obiektach (v_oslot = pierwszy wolny slot). C = 0: priorytet gotowy (sciezka blokowa - obj_bcbs konczy); C = 1:
; obwiednie grup (obj_bcbs: grp_rects, prio_rect dla or_*). Niszczy A, X, Y, zp_t0-zp_t3, zp_c, zp_lay, zp_ks, zm_t0-zm_t2.
; ---------------------------------------------------------------------
prio_path
	ldx v_lbuild
	lda v_camx                ; kamera jak w poprzedniej liscie kompletu?
	cmp PM_CXL,x
	bne pp_mov
	lda v_camx+1
	cmp PM_CXH,x
	bne pp_mov
	lda v_camy
	cmp PM_CYL,x
	bne pp_mov
	lda v_camy+1
	cmp PM_CYH,x
	bne pp_mov
	lda PM_WAS                ; Z1: tamta lista wziela sciezke blokowa i uklad sie nie zmienil
	beq pp_emit
	lda v_oslot               ; ... z tym samym pierwszym slotem i buforem obrazu
	cmp PM_OS,x
	bne pp_emit
	lda v_fbm
	cmp PM_FB,x
	bne pp_emit
	lda PM_LH,x               ; trafienie: BCB blokow wciaz w slotach od v_oslot - tylko koniec listy
	beq pp_hit0               ; (PM_LH = 0: zadnego BCB - zp_last zostaje ostatnim obiektem)
	sta zp_last+1
	lda PM_LL,x
	sta zp_last
pp_hit0
	lda #1
	sta PM_OK,x
	sta PK_OK,x               ; BCB (i ich pola stale) zostaja w slotach
	clc
	rts
pp_emit                         ; kamera stoi, pamieci brak: blokowa, gdy n <= max(PRB_STAT, prog) (koszt raz), inaczej obwiednie
	lda #PRB_STAT
	bne pp_thr                ; (zawsze)
pp_mov                          ; kamera sie ruszyla: klucz na nastepna liste kompletu, blokowa, gdy n <= prog
	lda v_camx
	sta PM_CXL,x
	lda v_camx+1
	sta PM_CXH,x
	lda v_camy
	sta PM_CYL,x
	lda v_camy+1
	sta PM_CYH,x
	lda #0                    ; bez minimum progu
pp_thr                          ; A = minimum progu; prog = max(A, PRB_FEW + PRB_KG * grupy), 255 przy bardzo wielu grupach
	sta zm_t1
	lda v_ngrp
	cmp #[256-PRB_FEW]/PRB_KG
	bcs pp_all                ; bardzo wiele grup - zawsze blokowa
	.if PRB_KG<>3
	.error "prio_path: prog liczony jako 3 * v_ngrp"
	.endif
	asl
	adc v_ngrp                ; C = 0 (v_ngrp < 85)
	adc #PRB_FEW              ; C = 0 (prog <= 3 + 3 * 83)
	cmp zm_t1
	bcs pp_scn
	lda zm_t1                 ; prog ponizej minimum (kamera stoi: PRB_STAT)
	bcc pp_scn                ; (zawsze - C = 0)
pp_all
	lda #255
pp_scn
	jsr pp_scan               ; C = 0: n <= prog (takze 0 - sciezka blokowa bez BCB; obwiednie tez nic by nie dodaly)
	bcc pp_emit0
	rts                       ; C = 1: obwiednie grup (PM_OK kompletu zostaje 0 - build_list)
pp_emit0
	lda #0
	sta zm_t2                 ; liczba BCB (0 - zp_last bez zmian)
	sta PK_LIM
	ldx v_lbuild              ; pola stale BCB bloku w slotach v_oslot..+PK_N-1: sciezka blokowa poprzedniej listy kompletu (PK_WAS)
	lda PK_WAS                ; od tego samego slotu (zmiana ukladu nie szkodzi - pola stale nie zaleza od ukladu)
	beq ppk_0
	lda PK_OS,x
	cmp v_oslot
	bne ppk_0
	lda PK_N,x
	sta PK_LIM
ppk_0
	ldx v_oslot
	jsr slot_ptr              ; zp_bcb = pierwszy slot priorytetu (dalej + BCB_BYTES)
	jsr pp_rows               ; wiersze okna: y, wysokosc, przesuniecie w bloku, bit pierscienia
	lda v_camx
	and #31
	sta zp_t3                 ; lx = camx & 31 (kolumny ekranu jak prio_blocks / prio_rect)
	ldx #0                    ; X = kolumna okna c (0..8)
pp_col
	lda PB_M,x
	jeq pp_cn
	sta zm_t0                 ; wiersze pierscienia z priorytetem tej kolumny
	stx zm_t1
	txa                       ; kolumna ukladu
	clc
	adc v_bx
	sta zp_c
	txa                       ; x = 32 c - lx (c = 8: 256 - lx), szerokosc 32, od kolumny 0 bloku
	asl
	asl
	asl
	asl
	asl
	sec
	sbc zp_t3
	sta zp_t0
	lda #31
	sta zp_t1                 ; szerokosc - 1
	lda #0
	sta zp_t2                 ; pierwsza kolumna bloku
	cpx #0
	bne pp_c1
	sta zp_t0                 ; c = 0: x = 0, w = 32 - lx, od kolumny lx bloku
	lda zp_t3
	sta zp_t2
	eor #31
	sta zp_t1                 ; 31 - lx
pp_c1
	cpx #8
	bne pp_c9
	lda zp_t3                 ; c = 8: w = lx (0 - blok poza ekranem)
	jeq pp_cdone
	sbc #1                    ; C = 1 (cpx: rowne)
	sta zp_t1
pp_c9
	ldx #0                    ; X = wiersz okna r (0..6)
pp_row
	lda PB_RB,x
	and zm_t0
	jeq pp_rn
	eor zm_t0
	sta zm_t0                 ; bit wiersza zuzyty (pusta maska - koniec kolumny)
	lda PB_RH,x
	jmi pp_rz                 ; $FF: wiersz poza ekranem (dolny przy camy & 31 = 0)
; BCB czesci bloku (zp_c, by + r): src = STORE + s * 1024 + ly * 32 + lx (s = BLKMAP_RAM[k]), cel = bufor (x, y), stencil + NEXT
	txa
	clc
	adc v_by
	tay
	lda LAYROW_LO,y
	sta zp_lay
	lda LAYROW_HI,y
	sta zp_lay+1
	ldy zp_c
	lda (zp_lay),y
	tay
	lda BLKMAP_RAM,y
	sta zp_ks                 ; slot magazynu bloku
	ldy #0
	lda PB_RLY,x              ; (ly & 7) << 5 | lx
	ora zp_t2
	sta (zp_bcb),y
	lda zp_ks
	asl
	asl
	clc
	adc PB_RSM,x              ; (s << 2) & $FF + ly >> 3
	iny
	sta (zp_bcb),y
	lda zp_ks                 ; C = 0 (bez przeniesienia: mlodsze 2 bity zerowe, ly >> 3 <= 3)
	rol
	rol
	rol
	and #3
	clc
	adc #STORE_VRAM>>16       ; STORE >> 16 + s / 64
	iny
	sta (zp_bcb),y
	lda zm_t2
	cmp PK_LIM
	bcc pp_kn                 ; slot z polami stalymi bloku (poprzednia lista kompletu)
	ldy #3
	lda #32
	sta (zp_bcb),y            ; krok Y zrodla 32 (slot mogl byc obiektem)
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda #1
	sta (zp_bcb),y            ; krok X 1
	ldy #13
	lda #0
	sta (zp_bcb),y            ; szerokosc hi
pp_kn
	ldy #6
	lda zp_t0
	sta (zp_bcb),y            ; cel lo = x
	iny
	lda PB_RY,x
	clc
	adc v_fbm
	sta (zp_bcb),y            ; cel = bufor + y * 256
	iny
	lda v_fbh
	adc #0
	sta (zp_bcb),y
	ldy #12
	lda zp_t1
	sta (zp_bcb),y            ; szerokosc - 1
	ldy #14
	lda PB_RH,x
	sta (zp_bcb),y            ; wysokosc - 1
	ldy #20
	lda #$09
	sta (zp_bcb),y            ; stencil + NEXT (ostatni BCB listy - build_frame_list zdejmuje NEXT)
	lda zp_bcb
	sta zp_last
	clc
	adc #BCB_BYTES
	sta zp_bcb
	lda zp_bcb+1
	sta zp_last+1
	adc #0
	sta zp_bcb+1
	inc zm_t2
pp_rz
	lda zm_t0
	beq pp_cdone
pp_rn
	inx
	cpx #7
	jne pp_row
pp_cdone
	ldx zm_t1
pp_cn
	inx
	cpx #9
	jne pp_col
	ldx v_lbuild              ; zapis pamieci Z1 (klucz kamery juz zgodny - pp_mov albo trafienie kamery)
	lda v_oslot
	sta PM_OS,x
	sta PK_OS,x               ; pola stale bloku w slotach PK_OS..+PK_N-1 (nastepna lista kompletu)
	lda zm_t2
	sta PK_N,x
	lda #1
	sta PK_OK,x
	lda v_fbm
	sta PM_FB,x
	lda #0
	ldy zm_t2
	beq pp_st0
	lda zp_last
	sta PM_LL,x
	lda zp_last+1
pp_st0
	sta PM_LH,x
	lda #1
	sta PM_OK,x
	clc
	rts

; pp_scan: A = prog L. PB_M[c] = PRIOCOLM[(bx + c) & 15] & wiersze okna (c = 0..8) i C = 0, gdy blokow z priorytetem w oknie
; najwyzej L; C = 1 - wiecej niz L (liczenie przerwane, PB_M niepelne - czyta je tylko sciezka blokowa, pp_emit0). Review M7.5:
; pelne liczenie (ok. 1500 cykli przy n = 63) szlo co ramke kamery w ruchu, takze gdy wybor i tak dawal obwiednie (JUN3 NTSC).
pp_scan
	sta zm_t1
	inc zm_t1                 ; licznik L + 1 - n: zero = n > L (L = 255 -> 0: nigdy, n <= 63)
	lda v_by
	clc
	adc #7
	and #7
	tax
	lda bit_tab,x
	eor #$FF
	sta zm_t0                 ; 7 wierszy pierscienia okna (bez (by + 7) & 7 - poza oknem, bity nieaktualne)
	lda v_bx
	clc
	adc #8
	and #15
	tay                       ; Y = kolumna pierscienia (bx + c) & 15 - od c = 8 w dol z zawinieciem
	ldx #8
pps_l
	lda PRIOCOLM,y
	and zm_t0
	sta PB_M,x
	beq pps_n
pps_b                           ; n += liczba bitow (m &= m - 1)
	dec zm_t1
	beq pps_x                 ; n > L - dalej nie liczyc
	sta zm_t2
	sec
	sbc #1
	and zm_t2
	bne pps_b
pps_n
	dey
	bpl pps_w
	ldy #15
pps_w
	dex
	bpl pps_l
	clc                       ; n <= L
	rts
pps_x
	sec
	rts

; pp_rows: wiersze okna r = 0..6 (ly = camy & 31; jak prio_blocks / prio_rect): PB_RY = y ekranu, PB_RH = wysokosc - 1 ($FF - poza
; ekranem), PB_RLY = (ly0 & 7) << 5 i PB_RSM = ly0 >> 3 (ly0 - pierwsza widoczna linia bloku: wiersz 0 = ly, inne 0), PB_RB = bit
; wiersza pierscienia (by + r) & 7. PB_RB zalezy tylko od by & 7 (PB_KBY), reszta od ly (PB_KLY) - liczone tylko przy zmianie klucza
; (kamera w poziomie / postoj: ok. 25 cykli zamiast ok. 280).
pp_rows
	lda v_by                  ; PB_RB - tylko przy zmianie by & 7
	and #7
	cmp PB_KBY
	beq ppr_rbok
	sta PB_KBY
	tay
	ldx #0
ppr_b
	lda pq_bit16,y            ; bit (by + r) & 7
	sta PB_RB,x
	iny
	inx
	cpx #7
	bne ppr_b
ppr_rbok
	lda v_camy                ; PB_RY, PB_RH, PB_RLY, PB_RSM - tylko przy zmianie ly
	and #31
	sta zp_t3                 ; ly
	cmp PB_KLY
	bne ppr_new
	rts
ppr_new
	sta PB_KLY
	lda #32                   ; r = 1..6: y = 32 r - ly, h = 32, od linii 0 bloku
	sec
	sbc zp_t3
	ldx #1
ppr_y                           ; (PB_RH = 31 wierszy 1-5, PB_RLY / PB_RSM = 0 wierszy 1-6 - stale z nt_reset)
	sta PB_RY,x
	clc
	adc #32
	inx
	cpx #7
	bne ppr_y
	lda #0                    ; r = 0: y = 0, h = 32 - ly, od linii ly bloku
	sta PB_RY
	lda zp_t3
	eor #31
	sta PB_RH                 ; 31 - ly
	lda zp_t3
	and #7
	lsr
	ror
	ror
	ror                       ; (ly & 7) << 5
	sta PB_RLY
	lda zp_t3
	lsr
	lsr
	lsr
	sta PB_RSM                ; ly >> 3
	lda zp_t3                 ; r = 6: y = 192 - ly, h = ly (0 - poza ekranem: $FF)
	sec
	sbc #1
	sta PB_RH+6
	rts
pq_bit16	dta b($01, $02, $04, $08, $10, $20, $40, $80, $01, $02, $04, $08, $10, $20)

; ---------------------------------------------------------------------
; prq_map (Z4): szybki test prio_rect (render/sprites.asm) z mapy PRIOCOLM zamiast 2 x prq_row (odczyty ukladu): bloki 2 x 2 od
; bloku lewego gornego rogu prostokata (v_ox, v_oy). Wyjscie: Z = 1 - zaden nie ma priorytetu. Bloki spoza okna (kolumna bx + 9,
; wiersz by + 7) maja w mapie bity nieaktualne - falszywe "tak" konczy sie w prq_full dokladnym prio_part z ukladu (bez BCB),
; falszywego "nie" nie ma (bloki pod prostokatem leza w oknie). Niszczy A, X, zm_t0.
; ---------------------------------------------------------------------
prq_map
	lda v_camx                ; kolumna: (ox + (camx & 31)) >> 5 (9 bit), + bx
	and #31
	clc
	adc v_ox
	ror
	lsr
	lsr
	lsr
	lsr
	clc
	adc v_bx
	and #15
	tax
	lda PRIOCOLM,x
	sta zm_t0
	inx
	txa
	and #15
	tax
	lda PRIOCOLM,x
	ora zm_t0
	sta zm_t0                 ; wiersze pierscienia z priorytetem w 2 kolumnach
	lda v_camy                ; wiersz: (oy + (camy & 31)) >> 5 + by (oy <= 191: bez przeniesienia)
	and #31
	clc
	adc v_oy
	lsr
	lsr
	lsr
	lsr
	lsr
	clc
	adc v_by
	and #7
	tax
	lda zm_t0
	and pqm_rows,x            ; wiersze (r & 7) i (r + 1) & 7
	rts
pqm_rows	dta b($03, $06, $0C, $18, $30, $60, $C0, $81)

; ---------------------------------------------------------------------
; front_digit_f / front_objs_f (Z5): jak front_digit / front_objs M6.8 (przednie wpisy tablicy SMS przy wodzie albo chmurach SKY2:
; wpis 20 przed Sonikiem, wpisy 11..0 po nim), wpis z y < 176 (w pionie w calosci; x dowolne - przyciecie z prawej jak s16_clip) -
; BCB wprost (fo_fast). Oryginal: VDP dostaje cala tablice od wpisu 0 (g_sprite_count startuje od $15, 00:1E34; upload_sprite_table_IRQ
; 00:033E-00:0359), linia wody $40 (02:8DCF: wpisy 0-7), duze bable $20 (02:9715: od g_frontmost_sprite_table_offs) i cyfra tonienia
; (01:508D: wpis 20) pisza tam z przywroceniem licznika i wskaznika; nizszy indeks na wierzchu. Wpisy czyszczone co tick (Y = $E0,
; game/step.asm) i inne z y 191..$EF koncza w fo_slow bez s16_clip (fo_sr), y >= $F0 (czesciowo nad ekranem) - fo_slow -> s16_clip.
	.if SLOT_OBJ+N_OBJ_SLOTS>255
	.error "front_objs_f: FM_CS = $FF oznacza brak serii - slot obiektu musi byc < $FF"
	.endif
; ---------------------------------------------------------------------
front_digit_f                   ; fo_tick w linii: poziom z woda (M6.10: albo SKY2 - chmury $30, v_front) i licznik sprite'ow >= 21
	lda v_water
	ora v_front
	beq fo_ret
	lda g_sprite_count
	cmp #21
	bcc fo_ret
	ldx #20*3
	jmp fo_one
front_objs_f
	lda v_water
	ora v_front
	beq fo_ret
	lda g_sprite_count
	cmp #21
	bcc fo_ret
	lda #1                    ; seria fo_fast tej listy (pola stale w slotach - nastepna lista kompletu)
	sta FM_ON
	lda #$FF
	sta FM_CS
	ldx v_lbuild              ; sloty z polami stalymi: seria poprzedniej listy kompletu
	lda FM_OS,x
	sta FM_LO
	ldy FM_WAS
	beq fof_e                 ; brak - pusty zakres
	clc
	adc FM_N,x
fof_e
	sta FM_HI
	ldx #11*3
fof_l
	stx v_fi
	jsr fo_one
	lda v_fi
	sec
	sbc #3
	tax
	bcs fof_l
	lda FM_ON                 ; seria do konca bez zapisu s16_clip - koniec = v_oslot
	beq fof_z
	lda v_oslot
	sta FM_CE
fof_z
	ldx v_lbuild              ; zapis serii (FM_OK kompletu = 0 z build_list, gdy brak)
	lda FM_CS
	cmp #$FF                  ; $FF - seria sie nie zaczela (sloty siegaja $80/$81 - nie bit 7, review M7.5)
	beq fof_end
	sta FM_OS,x
	lda FM_CE
	sec
	sbc FM_CS
	sta FM_N,x
	lda #1
	sta FM_OK,x
fof_end
	lda #0
	sta FM_ON
fo_ret
	rts
fo_one                          ; X = 3 * numer wpisu
	lda SPRTAB_R+1,x          ; y (8 bit; >= $F0 - linie nad ekranem)
	cmp #176
	jcs fo_slow               ; y >= 176: przyciecie albo poza ekranem (wpisy czyszczone Y = $E0)
	sta zm_t0
	lda SPRTAB_R,x
	sta v_ox
	cmp #249                  ; x 249..255: przyciety z prawej - szerokosc 256 - x (jak s16_clip), inaczej 8
	lda #7
	bcc fo_w
	lda v_ox
	eor #$FF                  ; 255 - x = szerokosc - 1
fo_w
	sta zm_t1
	lda SPRTAB_R+2,x
	sta v_tile
; Z5 fo_fast: wynik jak s16_clip (gora = y + 1 w 1..176, skip 0, wysokosc 16, szerokosc min(8, 256 - x), src = SPRATLAS + kafel * 64)
; + obj_emit
	ldx v_oslot
	cpx #SLOT_OBJ+N_OBJ_SLOTS
	bcs fo_ret                ; brak slotu (jak obj_emit)
	clc                       ; zp_bcb = slot v_oslot = zp_last + BCB_BYTES (zamiast slot_ptr): w trybie gry po hud_objs zp_last = slot
	lda zp_last               ; v_oslot - 1 - ustawia go kazdy emiter obiektu (obj_emit, fo_fast, pamiec HUD-u zh_last = ostatni slot HUD-u,
	adc #BCB_BYTES            ; sonic_obj_m), a HUD zawsze emituje co najmniej zycia; sloty obiektow sa kolejne
	sta zp_bcb
	lda zp_last+1
	adc #0
	sta zp_bcb+1
	inc v_oslot
	ldy #0
	lda v_tile                ; src lo = (kafel & 3) << 6
	and #3
	lsr
	ror
	ror
	sta (zp_bcb),y
	iny
	lda v_tile                ; src mid = >SPRATLAS + kafel / 4 (bez przeniesienia - asercja w objspr.asm)
	lsr
	lsr
	clc
	adc #>[SPRATLAS_VRAM&$FFFF]
	sta (zp_bcb),y
	ldy #6
	lda v_ox
	sta (zp_bcb),y            ; cel = bufor + (y + 1) * 256 + x
	iny
	lda zm_t0
	sec
	adc v_fbm
	sta (zp_bcb),y
	iny
	lda v_fbh
	adc #0
	sta (zp_bcb),y
	ldy #12
	lda zm_t1
	sta (zp_bcb),y            ; szerokosc - 1 (8 albo przyciety z prawej)
	ldy #20
	lda #$09
	sta (zp_bcb),y            ; stencil + NEXT - zawsze (slot serii mogl byc koncem poprzedniej listy: NEXT zdjety)
; pola stale (src hi, kroki zrodla, wysokosc 16): pomijane, gdy slot nalezal do serii fo_fast poprzedniej listy
; tego kompletu (FM_WAS; nikt inny nie pisze tego slotu: obiekty tej listy - sloty < v_oslot, priorytet - za obiektami)
	lda FM_ON
	beq fo_const              ; front_digit_f / seria zamknieta: pola stale pisane
	ldy FM_CS                 ; pierwszy slot serii tej listy (FM_CS = $FF - jeszcze brak; Y wolny - fo_const / fo_rect laduja)
	iny
	bne fo_cs
	stx FM_CS
fo_cs
	cpx FM_LO
	bcc fo_const
	cpx FM_HI
	bcc fo_rect               ; slot w serii poprzedniej listy kompletu - pola stale juz sa
fo_const
	ldy #2
	lda #SPRATLAS_VRAM>>16
	sta (zp_bcb),y
	iny
	lda #8
	sta (zp_bcb),y            ; krok Y zrodla 8
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda #1
	sta (zp_bcb),y            ; krok X 1
	ldy #13
	lda #0
	sta (zp_bcb),y
	iny
	lda #15
	sta (zp_bcb),y            ; wysokosc 16
fo_rect
	lda zp_bcb
	sta zp_last
	lda zp_bcb+1
	sta zp_last+1
	ldx v_nobj                ; prostokat dla priorytetu tla (jak obj_emit)
	lda v_ox
	sta or_x,x
	ldy zm_t0
	iny
	tya
	sta or_y,x
	lda zm_t1
	clc
	adc #1
	sta or_w,x
	lda #16
	sta or_h,x
	inc v_nobj
	rts
fo_slow                         ; jak front_objs M6.8: pozycja z tablicy (y >= $F0 - nad ekranem), s16_clip (render/sprites.asm)
	lda SPRTAB_R+1,x
	cmp #$F0
	bcs fo_sl                 ; nad ekranem (czesciowo widoczny)
	cmp #191                  ; y 191..$EF (m.in. wpisy czyszczone $E0): gora >= 192 - s16_clip nic by nie dodal (clip_rows C = 1)
	bcs fo_sr
fo_sl
	ldy FM_ON                 ; zapis s16_clip -> obj_emit po poczatku serii fo_fast: seria tej listy zamknieta (slot innego rodzaju)
	beq fo_sl2                ; na v_oslot; przed pierwszym fo_fast seria jeszcze sie nie zaczela - zostaje otwarta
	ldy FM_CS                 ; $FF (iny -> 0) - seria tej listy jeszcze sie nie zaczela
	iny
	beq fo_sl2
	ldy v_oslot
	sty FM_CE
	ldy #0
	sty FM_ON
fo_sl2
	sta v_sy16
	lda #0
	ldy SPRTAB_R+1,x
	cpy #$F0
	bcc fo_y
	lda #$FF
fo_y
	sta v_sy16+1
	lda SPRTAB_R,x
	sta v_ox
	lda SPRTAB_R+2,x
	sta v_tile
	jmp s16_clip
fo_sr
	rts

; ---------------------------------------------------------------------
; sonic_obj_m (Z6, docs/plan-m7-ntsc.md 2 Z6): sonic_obj (render/sprites.asm) z pamiecia BCB na komplet listy. BCB Sonica zalezy
; tylko od klatki (v_sonic_fr, v_sonic_base -> SONICFR_RAM), pozycji ekranowej (sonic_x - camx, sonic_y - camy), slotu (v_oslot)
; i bufora (v_fbm); przy kluczu jak w poprzedniej liscie tego kompletu (SM_WAS - tamta lista narysowala Sonika tym kluczem; inna
; sciezka zostawia SM_OK = 0, build_list) BCB juz jest w slocie: tylko v_oslot + 1, zp_last, prostokat priorytetu z pamieci i bajt sterowania $09 (BCB mogl byc koncem
; tamtej listy - build_frame_list zdejmuje NEXT z ostatniego).
; Bez pamieci: slot Sonika z typem $FF, mapa 0, mapa $592B (v_spr_todo), klatka spoza grafiki (v_spr_todo) i Sonic poza ekranem.
; Zmienne robocze sonic_obj (v_ox, v_osrc...) po trafieniu nie sa ustawiane - kolejne emitery (upspring, iskry, front) licza swoje.
; ---------------------------------------------------------------------
sonic_obj_m
	lda object_list+OB_TYPE   ; przypadki szczegolne - zwykle sonic_obj
	cmp #$FF
	jeq sonic_obj
	lda sonic_spritemap_ix_15
	ora sonic_spritemap_ix_15+1
	jeq sonic_obj
	lda sonic_spritemap_ix_15
	cmp #<$592B
	jeq sonic_obj
	lda v_sonic_fr
	cmp #LV_SONIC_FR
	jcs sonic_obj
	ldx v_lbuild
	sec                       ; klucz: pozycja ekranowa (16 bit)
	lda sonic_x
	sbc v_camx
	sta zm_t0
	lda sonic_x+1
	sbc v_camx+1
	sta zm_t1
	sec
	lda sonic_y
	sbc v_camy
	sta zm_t2
	lda sonic_y+1
	sbc v_camy+1
	tay                       ; Y = (sonic_y - camy) hi
	lda SM_WAS
	beq som_new
	lda v_sonic_fr
	cmp SM_FR,x
	bne som_new
	lda zm_t0
	cmp SM_XL,x
	bne som_new
	lda zm_t2
	cmp SM_YL,x
	bne som_new
	lda zm_t1
	cmp SM_XH,x
	bne som_new
	tya
	cmp SM_YH,x
	bne som_new
	lda v_sonic_base
	cmp SM_BASE,x
	bne som_new
	lda v_oslot
	cmp SM_OS,x
	bne som_new
	lda v_fbm
	cmp SM_FB,x
	bne som_new
	ldx v_oslot               ; trafienie: BCB Sonika z poprzedniej listy kompletu w slocie v_oslot
	jsr slot_ptr
	inc v_oslot
	ldy #20                   ; BCB mogl byc koncem tamtej listy (NEXT zdjety przez build_frame_list) - stencil + NEXT jak obj_emit
	lda #$09
	sta (zp_bcb),y
	lda zp_bcb
	sta zp_last
	lda zp_bcb+1
	sta zp_last+1
	ldx v_lbuild
	ldy v_nobj                ; prostokat dla priorytetu tla (jak obj_emit)
	lda SM_RX,x
	sta or_x,y
	lda SM_RY,x
	sta or_y,y
	lda SM_RW,x
	sta or_w,y
	lda SM_RH,x
	sta or_h,y
	inc v_nobj
	lda #1
	sta SM_OK,x
	rts
som_new                         ; klucz do pamieci kompletu, potem sonic_obj
	lda v_sonic_fr
	sta SM_FR,x
	lda v_sonic_base
	sta SM_BASE,x
	lda zm_t0
	sta SM_XL,x
	lda zm_t1
	sta SM_XH,x
	lda zm_t2
	sta SM_YL,x
	tya
	sta SM_YH,x
	lda v_oslot
	sta SM_OS,x
	lda v_fbm
	sta SM_FB,x
	jsr sonic_obj
	ldx v_lbuild
	lda v_oslot
	cmp SM_OS,x
	beq som_ret               ; nic nie narysowal (poza ekranem) - pamieci brak (SM_OK = 0)
	ldy v_nobj                ; prostokat obj_emit (or_*[v_nobj - 1])
	dey
	lda or_x,y
	sta SM_RX,x
	lda or_y,y
	sta SM_RY,x
	lda or_w,y
	sta SM_RW,x
	lda or_h,y
	sta SM_RH,x
	lda #1
	sta SM_OK,x
som_ret
	rts
