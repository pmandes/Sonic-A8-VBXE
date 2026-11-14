; =====================================================================
;  crack.asm - cracktro: PLACEHOLDER (M6 krok 1). Pierwszy segment XEX-a wydania (build/sonic-a8-vbxe.xex), ladowany
;  przed reszta gry; docelowo male intro < 8 KB w $2000-$3FFF (obszar okna MEMAC A gry - po powrocie z INIT
;  nikt go nie potrzebuje). INIT przy wlaczonym OS: ekran ANTIC (tytul, "THIS GAME IS NOT FOR SALE"),
;  dalej SPACJA albo FIRE; czeka na puszczenie (ekran tytulowy gry reaguje na wcisniety przycisk, nie na
;  zbocze), ANTIC bez obrazu (SDMCTL = 0, czarne tlo), powrot do loadera.
;  Test (tools/m6_ekrany_test.py): crk_auto <> 0 - powrot od razu.
;  M6.4: jedna linia wyboru "Start with: Green Hill Zone N" (M6.6: dalej Special Stage 1/2 i Bridge Zone 1-3) (strzalki lewo / prawo albo joystick lewo / prawo, z zawinieciem;
;  klawisze: '+' i '<' = lewo, '*' i '>' = prawo - z Ctrl lub bez, czyli strzalki Atari i klawisze PC w Altirze).
;  Trainer (po M6.6): dwie linie - 1. "Infinite lives: NO / YES" (lewo / prawo przelacza), 2. poziom startowy; aktywna linia
;  (gora / dol: joystick, '-' i '=' z Ctrl lub bez = strzalki Atari) ma podswietlone tlo i pulsujaca jasnosc liter (DLI zmienia COLPF1 / COLPF2
;  w tych liniach; reszta ekranu bez zmian). Wynik: CRK_SEL (poziom) i CRK_INF (1 = nieskonczone zycia; src/kernel/mem.inc).
;  Pozycja 0 (Green Hill Zone 1) = normalny start (tytul, mapa, akt 1); dalsze pozycje = start od razu w danym akcie
;  (bez tytulu i mapy). Wynik w CRK_SEL (0 = normalny start, k = pozycja k + 1; src/kernel/mem.inc), czyta go scr_boot
;  (src/scr/boot.asm). SPACJA / FIRE - start z wybrana pozycja. Nowe pozycje: dopisac wpis do tablicy menu (crk_m*, crk_mlo/hi).
;  M6.11: pozycje w kolejnosci gry (akty i etapy specjalne przeplatane, na koncu poziom koncowy $12 - "Ending"); wynik: CRK_SEL =
;  g_level + 1 (0 = normalny start), CRK_ACT = akt przed etapem specjalnym (po etapie gra idzie do nastepnego aktu), CRK_NB = pierwszy
;  etap specjalny za pozycja (g_next_bonus_level; $24 - wszystkie za nami) - crk_pick. Test (crk_auto): CRK_SEL ustawiony z debuggera,
;  CRK_ACT / CRK_NB z tablicy (crk_autosel).
;  Uklad (po M7.5): od gornej krawedzi pola obrazu "SONIC THE HEDGEHOG" (tryb 7), pod nim mniejsze "(c) SEGA 1991", nizej "Sonic A8 VBXE
;  v1.0 - A fan-made port for ATARI XL/XE + VBXE" (dwie linie - 54 znaki nie mieszcza sie w 40) i "by madness77", "THIS GAME IS NOT FOR
;  SALE" blyska lekko w rytm skoku scrollu (DLI A / B: jasnosc 14 w ramce uderzenia o podloze, potem do 10), odstep, pomoc ze strzalkami
;  ATASCII, maly odstep i dwie wysrodkowane linie wyboru (zycia, poziom) skladane w buforach crk_lb (crk_show / crk_line).
;  Scroll (po M7.5): na dole ekranu poziomy scroll tekstu (lorem ipsum, na razie) - plynny (HSCROL, 1 color clock = 2 piksele na ramke),
;  zapetlony, w kroju z projektu UltimateCart (robinhedwards/UltimateCart, Source/AtariBootROM/sdcart.fnt - font 128 znakow w kolejnosci
;  kodow ekranowych jak font OS, caly cracktro uzywa go zamiast fontu OS: CHBAS). Linia scrollu podskakuje w calosci (nie literki - cala
;  linia) na wysokosc 3 swoich wysokosci (24 linie obrazu), odbijajac sie od podloza bez postoju: display lista ma zmienna liczbe pustych
;  linii nad i pod linia scrollu (suma 24), a odroczone VBI (crk_irq) co ramke przesuwa HSCROL / wskaznik LMS i przebudowuje ten ogon
;  display listy (crk_tail). Scroll ma czarne tlo (biale litery - w trybie 2 odcien liter = odcien tla).
;  Muzyka (po M7.5): zaszyty, skompresowany (LZSS16, 1896 B) utwor z SKY1 - Scrap Brain Zone z wersji C64
;  (naglowek SKY1 w ROM-ie SMS: muzyka $04 = Scrap Brain; motyw Sky Base gra tylko SKY2) (ten sam format i dekoder co muzyka gry,
;  src/sound/music.asm; zrodlo strumienia: tools/pack_crk_music.py -> src/boot/crk_music.lz16). Gra od razu po starcie cracktro, zapetlona,
;  z tego samego odroczonego VBI co scroll (crk_irq -> crk_mus_tick; NTSC: 5 ramek muzyki na 6 VBI, tempo 50 Hz); na wyjsciu cisza.
;  Bufory historii dekodera ($3A00-$3FFF, 6 stron) leza poza obrazem XEX-a (pamiec nieobjeta plikiem) - nad kodem cracktro i atr_start.
; =====================================================================
	org $2000
crk_main
	lda crk_auto
	jne crk_autosel
	lda #0
	sta CRK_SEL
	sta CRK_INF
	sta crk_idx
	sta crk_lives
	lda #1
	sta crk_row               ; aktywna linia: poziom (gora = nieskonczone zycia)
	lda #$0F
	sta crk_stl               ; joystick: stan poprzedni = nic nie wcisniete
	lda #<crk_sgap
	sta crk_pp                ; scroll: wskaznik LMS na przerwe przed kopia poczatku tekstu (start: pol ekranu pustego)
	lda #>crk_sgap
	sta crk_pp+1
	lda #3
	sta crk_hs                ; scroll: HSCROL 3 (potem 2,1,0 i krok o znak)
	lda #0
	sta crk_bi                ; skok: poczatek tabeli
	lda crk_bnc
	sta crk_u                 ; skok: liczba pustych linii nad linia scrollu
	jsr crk_tail              ; ogon display listy (musi byc gotowy, zanim ANTIC zacznie ja czytac)
	jsr crk_show
	jsr crk_pulse
	lda SDLSTL                ; display lista E: OS-u - wraca na koniec (komunikat boot_check przez E:)
	sta crk_osdl
	lda SDLSTH
	sta crk_osdl+1
	lda VDSLST                ; wektor DLI OS-u - wraca na koniec
	sta crk_osvd
	lda VDSLST+1
	sta crk_osvd+1
	lda #0
	sta SDMCTL                ; zmiana display listy przy wylaczonym DMA (cien - od nastepnego VBI)
	jsr crk_vbi
	lda #<crk_dl
	sta SDLSTL
	lda #>crk_dl
	sta SDLSTH
	lda #$00
	sta COLOR4                ; tlo
	sta COLOR2                ; tlo trybu 2
	lda #$0E
	sta COLOR1                ; jasnosc znakow trybu 2
	lda #$86
	sta COLOR0                ; tryb 7: znaki koloru 0 (niebieski; gradient - DLI T)
	lda #CRK_SEGA
	sta COLOR3                ; tryb 4: "(c) SEGA 1991" w kolorze 3 (ciemnoniebieski)
	lda #>crk_font
	sta CHBAS                 ; font z UltimateCart (wyrownany do 1K) zamiast fontu OS
	lda #<crk_dlit            ; pierwsze DLI ramki: gradient tytulu
	sta VDSLST
	lda #>crk_dlit
	sta VDSLST+1
	lda #$22
	sta SDMCTL                ; normalne pole gry, DL DMA
	lda #$C0
	sta NMIEN                 ; DLI (aktywna linia) + VBI OS-u
	lda #$FF
	sta CH
	jsr crk_mus_init          ; muzyka: stan poczatkowy (pierwszy tick w VBI zaczyna utwor od ramki 0)
	lda VVBLKD                ; odroczone VBI OS-u (zwykle XITVBV) - wraca na koniec
	sta crk_ovb
	lda VVBLKD+1
	sta crk_ovb+1
	lda #1
	sta CRITIC                ; CRITIC <> 0: OS pomija VBI etap 2 (VVBLKD) - dwa zapisy wektora bez ryzyka polowicznego adresu
	lda #<crk_irq
	sta VVBLKD
	lda #>crk_irq
	sta VVBLKD+1
	lda #0
	sta CRITIC
	lda #1
	sta crk_hk                ; wektor zmieniony - crk_off ma go przywrocic
crk_wait
	jsr crk_pulse
	lda STRIG0                ; FIRE (0 = wcisniety)
	jeq crk_go
	lda STICK0
	and #$0F                  ; bit 0 = gora, 1 = dol, 2 = lewo, 3 = prawo (0 = wcisniety)
	cmp crk_stl
	beq crk_key               ; bez zmiany - zbocze tylko raz
	sta crk_stl
	cmp #$0B
	beq crk_left
	cmp #$07
	beq crk_right
	cmp #$0E
	beq crk_up
	cmp #$0D
	beq crk_down
crk_key
	lda CH
	cmp #$FF
	beq crk_wait
	ldx #$FF
	stx CH
	and #$3F                  ; bez shift i ctrl
	cmp #$21                  ; SPACJA
	beq crk_go
	cmp #$06                  ; '+' (strzalka w lewo = Ctrl+'+')
	beq crk_left
	cmp #$36                  ; '<'
	beq crk_left
	cmp #$07                  ; '*' (strzalka w prawo = Ctrl+'*')
	beq crk_right
	cmp #$37                  ; '>'
	beq crk_right
	cmp #$0E                  ; '-' (strzalka w gore = Ctrl+'-')
	beq crk_up
	cmp #$0F                  ; '=' (strzalka w dol = Ctrl+'=')
	bne crk_wait
crk_down
	lda #1
	bne crk_row_set           ; zawsze
crk_up
	lda #0
crk_row_set
	sta crk_row
	jmp crk_wait
crk_right
	lda crk_row
	bne cr_lvl
	beq crk_tog               ; linia zyc: lewo i prawo przelaczaja
cr_lvl
	ldx crk_idx
	inx
	cpx #CRK_N
	bcc crk_set
	ldx #0
	beq crk_set               ; zawsze
crk_left
	lda crk_row
	bne cl_lvl
crk_tog
	lda crk_lives
	eor #1
	sta crk_lives
	jsr crk_show
	jmp crk_wait
cl_lvl
	ldx crk_idx
	dex
	bpl crk_set
	ldx #CRK_N-1
crk_set
	stx crk_idx
	jsr crk_show
	jmp crk_wait
crk_go
	ldx crk_idx               ; M6.11: pozycja -> CRK_SEL (0 = normalny start, inaczej g_level + 1), CRK_ACT, CRK_NB
	jsr crk_pick
	lda crk_lives
	sta CRK_INF
	lda #$FF
	sta CH
crk_rel                         ; puszczenie: FIRE i klawisz
	lda STRIG0
	beq crk_rel
	lda SKSTAT
	and #4                    ; bit 2 = 0: klawisz wcisniety
	beq crk_rel
	.if NOSNIK_320=0
	lda crk_osdl
	sta SDLSTL
	lda crk_osdl+1
	sta SDLSTH
	.endif                    ; M7.3 (review): nosnik 320K - display lista E: OS-u (pod RAMTOP = $A0: $9C20) jest juz nadpisana kodem gry
	                          ; (stub startowy cartu): przywrocenie SDLSTL przy SDMCTL = $22 dalo by VBI OS-u szanse wlaczenia DMA ze
	                          ; smieciowej DL (odczyt $D5xx = wlaczenie AtariMax) zanim crk_off wyzeruje SDMCTL. Zostaje DL cracktro (DMA
	                          ; i tak wylaczone w crk_off); E: odbudowuje dopiero bc_fail (CLOSE / OPEN).
	lda #$40
	sta NMIEN                 ; bez DLI (OS: tylko VBI), wektor DLI OS-u
	lda crk_osvd
	sta VDSLST
	lda crk_osvd+1
	sta VDSLST+1
crk_off
	lda crk_hk
	beq co_nohk               ; sciezka testowa (crk_auto): wektor nie byl zmieniany
	lda #1
	sta CRITIC                ; jak przy instalacji: bez VBI etap 2 w trakcie zapisu wektora
	lda crk_ovb
	sta VVBLKD
	lda crk_ovb+1
	sta VVBLKD+1
	lda #0
	sta CRITIC
	sta crk_hk
	sta AUDC1                 ; cisza: glosnosc 0 na kanalach 1-4 i AUDCTL domyslny (dalej gra / loader)
	sta AUDC2
	sta AUDC3
	sta AUDC4
	sta AUDCTL
co_nohk
	lda #0
	sta HSCROL                ; bez przesuniecia poziomego dla dalszych ekranow
	lda #$E0
	sta CHBAS                 ; font OS (kod fontu cracktro zostanie nadpisany przez gre)
	lda #0
	sta SDMCTL                ; dalej czern do konca ladowania
	sta COLOR4
	jsr crk_vbi
	rts

; crk_autosel (M6.11, test - crk_auto <> 0): CRK_SEL ustawiony z debuggera (g_level + 1; 0 = normalny start) - CRK_ACT i CRK_NB jak
; dla pozycji menu z tym poziomem (crk_pick; CRK_SEL zostaje - takze 1 = GHZ1 od razu); poziomu spoza menu: CRK_ACT = 0, CRK_NB = $1C
crk_autosel
	lda CRK_SEL
	beq cas_none
	sec
	sbc #1
	ldx #CRK_N-1
cas_l
	cmp crk_lv,x
	beq cas_hit
	dex
	bpl cas_l
cas_none
	lda #0
	sta CRK_ACT
	lda #$1C
	sta CRK_NB
	jmp crk_off
cas_hit
	lda CRK_SEL
	pha
	jsr crk_pick
	pla
	sta CRK_SEL
	jmp crk_off

; crk_pick (M6.11): X = pozycja menu -> CRK_SEL (pozycja 0: 0, inaczej g_level + 1 z crk_lv), CRK_ACT (etap specjalny: g_level pozycji
; przed nim, inaczej 0), CRK_NB (g_level pierwszego etapu specjalnego za pozycja X; brak - $24). Zachowuje X.
crk_pick
	stx crk_t
	lda #0
	sta CRK_ACT
	cpx #0
	beq cs_sel
	lda crk_lv,x
	cmp #$1C
	bcc cs_nact
	lda crk_lv-1,x            ; etap specjalny: akt przed nim w kolejnosci gry
	sta CRK_ACT
cs_nact
	lda crk_lv,x
	clc
	adc #1
cs_sel
	sta CRK_SEL
cs_nb
	inx
	cpx #CRK_N
	bcs cs_none
	lda crk_lv,x
	cmp #$1C
	bcc cs_nb
	bcs cs_nbw                ; zawsze
cs_none
	lda #$24                  ; wszystkie etapy specjalne za pozycja
cs_nbw
	sta CRK_NB
	ldx crk_t
	rts

crk_vbi                         ; czeka na VBI OS-u (RTCLOK+2)
	lda RTCLOK+2
cv_l
	cmp RTCLOK+2
	beq cv_l
	rts

; crk_show: linie wyboru skladane w buforach (crk_lb - zycia "< Infinite lives: NO/YES >", crk_lb + 40 - poziom "< Start with: nazwa >"),
; wysrodkowane. Zapis zaraz po VBI: ANTIC rysuje jeszcze gore ekranu, linie wyboru (od linii 142) beda gotowe - bez rwania obrazu.
crk_show
	jsr crk_vbi
	ldx crk_lives
	lda crk_ilo,x
	sta crk_lnm
	lda crk_ihi,x
	sta crk_lnm+1
	lda #<crk_pinf
	ldy #>crk_pinf
	ldx #0                    ; bufor linii zyc
	jsr crk_line
	ldx crk_idx
	lda crk_mlo,x
	sta crk_lnm
	lda crk_mhi,x
	sta crk_lnm+1
	lda #<crk_pstw
	ldy #>crk_pstw
	ldx #40                   ; bufor linii poziomu
				; dalej crk_line

; crk_line: bufor linii od crk_lb + X (X = 0 / 40) = wysrodkowany tekst: prefiks (A = lo, Y = hi; konczy go $FF) + nazwa (crk_lnm;
; konczy ja $FF) + " >". Najpierw 40 spacji, sklad od lewej, potem przesuniecie w prawo o (40 - dlugosc) / 2. Niszczy A, X, Y, crk_zs.
crk_line
	sta crk_zs
	sty crk_zs+1
	stx crk_lx                ; poczatek bufora
	ldy #40
	lda #0                    ; spacja = kod ekranowy 0
cl_clr
	sta crk_lb,x
	inx
	dey
	bne cl_clr
	ldx crk_lx                ; X = miejsce zapisu
	jsr cl_copy               ; prefiks
	lda crk_lnm
	sta crk_zs
	lda crk_lnm+1
	sta crk_zs+1
	jsr cl_copy               ; nazwa
	inx                       ; spacja (bufor juz wyczyszczony)
	lda #$1E                  ; '>' (kod ekranowy)
	sta crk_lb,x
	inx                       ; X = koniec tekstu
	txa
	sec
	sbc crk_lx
	sta crk_ln                ; n = dlugosc tekstu
	lda #40
	sec
	sbc crk_ln
	lsr                       ; s = (40 - n) / 2
	beq cl_x                  ; tekst na cala szerokosc - bez przesuniecia
	clc
	adc #<crk_lb
	sta cl_dst+1              ; operand zapisu = crk_lb + s (samomodyfikacja - kod w RAM)
	lda #>crk_lb
	adc #0
	sta cl_dst+2
	ldy crk_ln
cl_mv                           ; od konca: znak i -> i + s, potem i = spacja (pozycje < s zostaja spacjami, reszte nadpisze dalsza kopia)
	dex
	lda crk_lb,x
cl_dst
	sta crk_lb,x
	lda #0
	sta crk_lb,x
	dey
	bne cl_mv
cl_x
	rts

; cl_copy: tekst spod (crk_zs) do bajtu $FF -> crk_lb,x (X rosnie)
cl_copy
	ldy #0
cc_l
	lda (crk_zs),y
	cmp #$FF
	beq cc_x
	sta crk_lb,x
	inx
	iny
	bne cc_l
cc_x
	rts

; crk_pulse: kolory linii wyboru dla DLI (dwa przerwania: przed linia zyc i na linii tla pod nia): aktywna linia - tlo ciemnopomaranczowe
; i litery o jasnosci z tablicy crk_pt (faza = RTCLOK+2 / 4, okres 64 ramek), nieaktywna - tlo czarne i litery szare
crk_pulse
	lda RTCLOK+2
	lsr
	lsr
	and #$0F
	tax
	lda crk_pt,x
	ora #$10                  ; odcien 1 (zloty / pomaranczowy) - kolor liter: odcien tla + jasnosc COLPF1
	sta crk_tmp
	lda #$08                  ; nieaktywna: szare litery, czarne tlo
	ldx #$00
	ldy crk_row
	bne cp_row1
	sta crk_c1b               ; aktywna linia 0 (zycia)
	stx crk_c2b
	lda crk_tmp
	sta crk_c1a
	lda #$12
	sta crk_c2a
	rts
cp_row1
	sta crk_c1a               ; aktywna linia 1 (poziom)
	stx crk_c2a
	lda crk_tmp
	sta crk_c1b
	lda #$12
	sta crk_c2b
	rts

; DLI T (na ostatniej pustej linii nad tytulem): gradient "SONIC THE HEDGEHOG" - przed kazda z 16 linii trybu 7 nowy COLPF0
; z crk_grad (WSYNC: zapis w poziomym wygaszeniu, od pierwszej linii tytulu). Zajmuje CPU na czas tytulu (16 linii, ok. 1800 cykli) -
; petla glowna cracktro tylko czeka na klawisz. Po tytule COLPF0 zostaje ostatni (nic nizej go nie uzywa; VBI odtwarza cien).
crk_dlit
	pha
	txa
	pha
	ldx #0
ct_l
	lda crk_grad,x
	sta WSYNC
	sta COLPF0
	inx
	cpx #16
	bne ct_l
	lda #<crk_dlia
	sta VDSLST
	lda #>crk_dlia
	sta VDSLST+1
	pla
	tax
	pla
	rti
; gradient tytulu: odcien 8 (niebieski), od jasnego u gory do ciemnego u dolu (GTIA: 8 poziomow jasnosci - po 2 linie na poziom;
; linie 0-1 i 14-15 to puste wiersze fontu)
crk_grad	dta b($8E,$8E,$8E,$8C,$8C,$8A,$8A,$88,$88,$86,$86,$84,$84,$82,$82,$82)
; DLI A (na pustej linii nad "THIS GAME IS NOT FOR SALE"): jasnosc napisu crk_fl (blysk - crk_irq); DLI B (na koncu tego napisu):
; z powrotem biale litery dla dalszych linii. Kolejnosc w ramce: T, A, B, 1, 2, 3 (VDSLST przestawia kazde DLI na nastepne).
crk_dlia
	pha
	lda crk_fl
	sta WSYNC
	sta COLPF1
	lda #<crk_dlib
	sta VDSLST
	lda #>crk_dlib
	sta VDSLST+1
	pla
	rti
crk_dlib
	pha
	lda #$0E
	sta WSYNC
	sta COLPF1
	lda #<crk_dli1
	sta VDSLST
	lda #>crk_dli1
	sta VDSLST+1
	pla
	rti
; DLI 1 (na koncu pustych linii przed linia zyc): kolory linii zyc (z liniami tla nad i pod); DLI 2 (na linii tla pod linia zyc):
; kolory linii poziomu
crk_dli1
	pha
	lda crk_c1a
	sta WSYNC
	sta COLPF1
	lda crk_c2a
	sta COLPF2
	lda #<crk_dli2
	sta VDSLST
	lda #>crk_dli2
	sta VDSLST+1
	pla
	rti
crk_dli2
	pha
	lda crk_c1b
	sta WSYNC
	sta COLPF1
	lda crk_c2b
	sta COLPF2
	lda #<crk_dli3
	sta VDSLST
	lda #>crk_dli3
	sta VDSLST+1
	pla
	rti
; DLI 3 (na pustej linii zaraz pod linia wyboru): kolor scrollu (CRK_SCOL: biale litery na czarnym tle); potem znowu DLI T
crk_dli3
	pha
	lda #CRK_SCOL
	sta WSYNC
	sta COLPF1
	lda #$00                  ; tryb 2: odcien liter = odcien COLPF2, jasnosc = COLPF1; tlo = COLPF2 - czarne tlo (odcien 0, jasnosc 0)
	                          ; wymusza biale / szare litery (kolorowe litery wymagaly by odcienia w COLPF2 = niebieskawe tlo)
	sta COLPF2
	lda #<crk_dlit
	sta VDSLST
	lda #>crk_dlit
	sta VDSLST+1
	pla
	rti

crk_pt	dta b($06,$06,$08,$08,$0A,$0A,$0C,$0C,$0E,$0E,$0C,$0C,$0A,$0A,$08,$08)
crk_auto	dta b(0)
crk_idx		dta b(0)
crk_t		dta b(0)             ; M6.11: crk_pick - zachowana pozycja
crk_lives		dta b(0)
crk_row		dta b(1)
crk_stl		dta b($0F)
crk_c1a		dta b($08)
crk_c2a		dta b($00)
crk_c1b		dta b($08)
crk_c2b		dta b($00)
crk_osdl	dta a(0)
crk_osvd	dta a(0)
crk_tmp		dta b(0)
crk_fl		dta b($0A)           ; jasnosc "THIS GAME IS NOT FOR SALE" (DLI A; crk_irq)
crk_lnm		dta a(0)             ; crk_line: adres nazwy
crk_lx		dta b(0)             ; crk_line: poczatek bufora (0 / 40)
crk_ln		dta b(0)             ; crk_line: dlugosc tekstu
crk_zs	= $E2                   ; ZP (2): crk_line - zrodlo tekstu (kod glowny; VBI uzywa tylko crk_mzp $E0-$E1)

crk_l1	dta d' SONIC THE HEDGEHOG '
; "(c) SEGA 1991" w trybie 4 (40 znakow, 8 linii - ten sam rozmiar co tryb 2): ciemnoniebieski na czarnym. W trybie 2 odcien liter
; = odcien tla, wiec kolor wymaga trybu wielokolorowego; glify $40-$48 w foncie (crk_f4), kod $C0 + n: bit 7 -> piksele 11 w kolorze COLPF3
; (COLOR3 = CRK_SEGA). Rozdzielczosc pozioma o polowe mniejsza niz w trybie 2 (piksel = 2 piksele hires).
crk_l2	dta b($00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$C0,$C1,$C2,$00,$C3,$C4,$C5,$C6,$00,$C7,$C8,$C8,$C7,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00)   ; '             (c) SEGA 1991              '
crk_l3	dta d'  Sonic A8 VBXE v1.0 - A fan-made port  '   ; pelny napis (54 znaki) w dwoch liniach
crk_l4	dta d'         for ATARI XL/XE + VBXE         '   ; 
crk_l5	dta d'              by madness77              '   ; 
crk_l6	dta d'       THIS GAME IS NOT FOR SALE        '   ; blysk: DLI A / B
crk_l7	dta d' ',b($5C),b($5D),d' SELECT  ',b($5E),b($5F),d' CHANGE  SPACE/FIRE START '   ; $5C $5D / $5E $5F = strzalki ATASCII gora, dol / lewo, prawo (kody ekranowe)
crk_l8
	.if crk_l2-crk_l1<>20 .or crk_l3-crk_l2<>40 .or crk_l4-crk_l3<>40 .or crk_l5-crk_l4<>40 .or crk_l6-crk_l5<>40 .or crk_l7-crk_l6<>40 .or crk_l8-crk_l7<>40
	.error "napisy cracktro: 20 / 40 znakow"
	.endif
crk_lb	:80 dta b(0)             ; bufory linii wyboru: zycia (+0), poziom (+40) - crk_line
; czesci linii wyboru (kody ekranowe, koniec $FF): "< Infinite lives: " + NO / YES + " >", "< Start with: " + nazwa + " >"
crk_pinf	dta d'< Infinite lives: ',b($FF)
crk_pstw	dta d'< Start with: ',b($FF)
crk_i0	dta d'NO',b($FF)
crk_i1	dta d'YES',b($FF)
crk_ilo	dta l(crk_i0,crk_i1)
crk_ihi	dta h(crk_i0,crk_i1)
; menu: pozycja 0 = normalny start, dalej start od razu w akcie (CRK_SEL = g_level + 1 - crk_pick)
crk_m0	dta d'Green Hill Zone 1',b($FF)
crk_m1	dta d'Special Stage 1',b($FF)
crk_m2	dta d'Green Hill Zone 2',b($FF)
crk_m3	dta d'Special Stage 2',b($FF)
crk_m4	dta d'Green Hill Zone 3',b($FF)
crk_m5	dta d'Bridge Zone 1',b($FF)
crk_m6	dta d'Special Stage 3',b($FF)
crk_m7	dta d'Bridge Zone 2',b($FF)
crk_m8	dta d'Special Stage 4',b($FF)
crk_m9	dta d'Bridge Zone 3',b($FF)
crk_m10	dta d'Jungle Zone 1',b($FF)
crk_m11	dta d'Special Stage 5',b($FF)
crk_m12	dta d'Jungle Zone 2',b($FF)
crk_m13	dta d'Special Stage 6',b($FF)
crk_m14	dta d'Jungle Zone 3',b($FF)
crk_m15	dta d'Labyrinth Zone 1',b($FF)
crk_m16	dta d'Special Stage 7',b($FF)
crk_m17	dta d'Labyrinth Zone 2',b($FF)
crk_m18	dta d'Special Stage 8',b($FF)
crk_m19	dta d'Labyrinth Zone 3',b($FF)
crk_m20	dta d'Scrap Brain Zone 1',b($FF)
crk_m21	dta d'Scrap Brain Zone 2',b($FF)
crk_m22	dta d'Scrap Brain Zone 3',b($FF)
crk_m23	dta d'Sky Base Zone 1',b($FF)
crk_m24	dta d'Sky Base Zone 2',b($FF)
crk_m25	dta d'Sky Base Zone 3',b($FF)
crk_m26	dta d'Ending',b($FF)
CRK_N	= 27
; M6.11: g_level pozycji menu (kolejnosc gry; pozycja 0 = normalny start) - crk_pick
crk_lv	dta b($00, $1C, $01, $1D, $02, $03, $1E, $04, $1F, $05, $06, $20, $07, $21, $08, $09, $22, $0A, $23, $0B, $0C, $0D, $0E, $0F, $10, $11, $12)
crk_mlo	dta l(crk_m0,crk_m1,crk_m2,crk_m3,crk_m4,crk_m5,crk_m6,crk_m7,crk_m8,crk_m9,crk_m10,crk_m11,crk_m12,crk_m13,crk_m14,crk_m15,crk_m16,crk_m17,crk_m18,crk_m19,crk_m20,crk_m21,crk_m22,crk_m23,crk_m24,crk_m25,crk_m26)
crk_mhi	dta h(crk_m0,crk_m1,crk_m2,crk_m3,crk_m4,crk_m5,crk_m6,crk_m7,crk_m8,crk_m9,crk_m10,crk_m11,crk_m12,crk_m13,crk_m14,crk_m15,crk_m16,crk_m17,crk_m18,crk_m19,crk_m20,crk_m21,crk_m22,crk_m23,crk_m24,crk_m25,crk_m26)

; ---------------------------------------------------------------------
;  Scroll: odroczone VBI (CRITIC = 0, wektor VVBLKD): co ramke muzyka, 1 krok scrollu (HSCROL 3,2,1,0, potem wskaznik LMS + 1 znak =
;  4 color clocki = 8 pikseli, czyli kazdy krok to 1 color clock = 2 piksele), krok tabeli skoku i przebudowa ogona display listy.
;  Wyjscie przez XITVBV (przywraca rejestry).
; ---------------------------------------------------------------------
crk_irq
	jsr crk_mus_tick          ; muzyka: najpierw (stala faza w ramce), potem scroll i skok
	dec crk_hs
	bpl ci_hs                 ; HSCROL nadal 2..0 - wskaznik bez zmiany
	lda #3
	sta crk_hs                ; nowy znak: HSCROL 3 + LMS o 1 znak dalej = przesuniecie o 1 color clock w lewo
	inc crk_pp
	bne ci_nc
	inc crk_pp+1
ci_nc
	lda crk_pp
	cmp #<crk_stail
	bne ci_hs
	lda crk_pp+1
	cmp #>crk_stail
	bne ci_hs
	lda #<crk_scr             ; koniec kopii poczatku: okno w crk_stail = okno w crk_scr - zapetlenie bez skoku
	sta crk_pp
	lda #>crk_scr
	sta crk_pp+1
ci_hs
	lda crk_hs
	sta HSCROL
	lda #$0E                  ; blysk "THIS GAME IS NOT FOR SALE" w rytm skoku: indeks 0 = uderzenie o podloze -> jasnosc 14,
	sec                       ; potem -1 na ramke (parzyste jasnosci) do 10
	sbc crk_bi
	bcc cf_lo                 ; indeks > 14
	cmp #$0A
	bcs cf_ok
cf_lo
	lda #$0A
cf_ok
	and #$0E
	sta crk_fl
	ldx crk_bi                ; skok: liczba pustych linii nad linia scrollu z tabeli (0 = szczyt skoku, 24 = ziemia)
	lda crk_bnc,x
	sta crk_u
	inx
	cpx #CRK_BN
	bcc ci_b
	ldx #0
ci_b
	stx crk_bi
	jsr crk_tail
	jmp XITVBV

; crk_tail: ogon display listy pod linia wyboru (crk_dlt): $80 (1 pusta linia z DLI 3), crk_u pustych linii, linia scrollu
; (tryb 2 + LMS + HSCROL = $52, adres crk_pp), 24 - crk_u pustych linii, JVB do crk_dl. Niszczy A, X, Y.
crk_tail
	ldx #0
	lda #$80                  ; 1 pusta linia z DLI (kolor scrollu)
	sta crk_dlt,x
	inx
	lda crk_u
	jsr crk_blank
	lda #$52                  ; tryb 2 + LMS ($40) + przewijanie poziome ($10)
	sta crk_dlt,x
	lda crk_pp
	sta crk_dlt+1,x
	lda crk_pp+1
	sta crk_dlt+2,x
	inx
	inx
	inx
	lda #CRK_BH
	sec
	sbc crk_u
	jsr crk_blank
	lda #$41                  ; JVB: powrot na poczatek display listy po VBI
	sta crk_dlt,x
	lda #<crk_dl
	sta crk_dlt+1,x
	lda #>crk_dl
	sta crk_dlt+2,x
	rts

; crk_blank: A = liczba pustych linii 0-24 -> instrukcje pustych linii w crk_dlt od indeksu X (po 8 linii: $70, reszta 1-8: (n-1) * 16)
crk_blank
	tay
	beq cb_x                  ; 0 linii - nic
cb_l
	cpy #9
	bcc cb_r                  ; zostalo 1-8
	lda #$70                  ; 8 pustych linii
	sta crk_dlt,x
	inx
	tya
	sec
	sbc #8
	tay
	bne cb_l                  ; zawsze (reszta >= 1)
cb_r
	dey                       ; 0-7
	tya
	asl
	asl
	asl
	asl                       ; (n - 1) * 16 = puste n linii
	sta crk_dlt,x
	inx
cb_x
	rts

; Skok: CRK_BH = 24 linie = 3 wysokosci linii scrollu; tabela = liczba pustych linii NAD linia (24 - wysokosc skoku). Pilka odbijajaca
; sie od podloza: parabola (rzut: h = 4 H x (1 - x), x = t / 30) przez 30 ramek, w ramce 0 linia dotyka ziemi (24) i od razu leci w
; gore - bez postoju na ziemi; cala linia skacze, litery sa na sztywno.
CRK_BH	= 24
CRK_BN	= 30
CRK_SEGA	= $84                 ; "(c) SEGA 1991": ciemnoniebieski (odcien 8, jasnosc 4)
CRK_SCOL	= $0E                 ; jasnosc liter scrollu (14 = biale) na czarnym tle
crk_bnc
	dta b(24,21,18,15,13,11,9,7,5,4,3,2,1,0,0)
	dta b(0,0,0,1,2,3,4,5,7,9,11,13,15,18,21)

; Tekst scrollu (648 znakow, angielski) + 20 spacji (przerwa pol ekranu) + kopia pierwszych 48 znakow tekstu (crk_stail).
; Zapetlenie: wskaznik z crk_stail wraca na crk_scr - okno 48 znakow (szerokosc ANTIC-a przy HSCROL) jest w obu miejscach takie samo,
; wiec szwu nie widac. Start od przerwy (crk_sgap): na poczatku pol ekranu pustego, potem tekst wjezdza z prawej.
crk_scr
	dta d'Welcome SillyVenture 2026! I present to you a port of Sonic The Hedgehog for the Atari 8-bit. VBXE and at leas'
	dta d't 320 KB of RAMBO RAM are required. This port was made by translating Z80 assembly into 6502 with the help of '
	dta d'AI, based on the source code of Disassembly of Sonic The Hedgehog for the Sega Master System by GreaseMonkey. '
	dta d'Original music by Masato Nakamura and Yuzo Koshiro, C64 SID version by Mikkel Hastrup (Encore) / Sonic Team 64'
	dta d'. Converted to POKEY with sid2sapr by Ivo van Poorten. Disk loading by xBIOS by XXL. Greetings to all the folk'
	dta d's from atarionline.pl, atari.area and AtariAge, and to everyone attending and watching this party!'
crk_sgap
	:20 dta d' '
crk_stail
	dta d'Welcome SillyVenture 2026! I present to you a po'
	.if crk_stail-crk_scr<48
	.error "tekst scrollu krotszy niz okno 48 znakow"
	.endif

crk_pp	dta a(0)                ; scroll: wskaznik LMS (okno 48 znakow w crk_scr ... crk_stail + 47)
crk_hs	dta b(3)                ; scroll: HSCROL 3..0
crk_bi	dta b(0)                ; skok: indeks w crk_bnc
crk_u	dta b(24)               ; skok: liczba pustych linii nad linia scrollu
crk_ovb	dta a(0)                ; odroczone VBI OS-u - wraca na koniec
crk_hk	dta b(0)                ; 1 = VVBLKD zmieniony przez cracktro

; ---------------------------------------------------------------------
;  Muzyka: dekoder LZSS16 (adaptacja asm/playlzs16.asm z dmsc/lzss-sap, Copyright (c) 2020 Daniel Serpell, licencja MIT -
;  docs/licencje/LICENSE-DMSC.txt; ta sama logika co mus_decode_frame w src/sound/music.asm, ale zmienne absolutne, jedna ZP
;  na wskaznik bufora, bufory stron wg tablicy crk_mpg, utwor zawsze zapetlony).
;  Strumien x (0 = AUDF1 ... 7 = AUDC4, 8 = AUDCTL; zapis do AUDF1 + x) ma bufor historii 256 B (strona crk_mpg,x); strumienie
;  stale (maska) nie sa dekodowane. Kazdy utwor gry ma stale AUDF3 / AUDC3 / AUDCTL (x = 4, 5, 8 - kanal 3 dla efektow; sprawdzaja to
;  tools/pack_music.py i tools/pack_crk_music.py), wiec te strumienie nie maja wlasnych buforow: dziela strone z x = 0. Jedyny ich zapis
;  to wartosc poczatkowa w komorce 255 na starcie (x = 8, 5, 4 przed x = 0) - nadpisuje ja potem wartosc poczatkowa x = 0. 6 stron.
; ---------------------------------------------------------------------
CRK_MB	= $3A00                 ; bufory historii: $3A00-$3FFF (pamiec poza obrazem XEX-a; asercje miejsca nizej i w src/game.asm)
CRK_MFR	= 3065                  ; liczba ramek utworu (tools/pack_crk_music.py)
crk_mzp	= $E0                   ; ZP: wskaznik bufora historii (2 B; faza startu - wolne)

; crk_mus_init: NTSC (PAL: bity 1-3 rejestru PAL = 0 - muzyka co VBI), faza, licznik ramek = 0 (pierwszy tick = start utworu)
crk_mus_init
	lda PAL
	and #$0E
	sta crk_mntsc             ; 0 = PAL
	lda #1
	sta crk_mph               ; faza 5/6 jak w grze (mus_phase)
	lda #0
	sta crk_mrem
	sta crk_mrem+1
	sta crk_mzp               ; wskaznik bufora: mlodszy bajt zawsze 0 (strona z crk_mpg)
	rts

; crk_mus_tick: z VBI - jedna ramka SAP-R (PAL: co VBI; NTSC: 5 na 6 VBI). Licznik 0: start / zapetlenie (ramka 0 z wartosci poczatkowych).
crk_mus_tick
	lda crk_mntsc
	beq cm_play
	lda crk_mph
	clc
	adc #5
	cmp #6
	bcc cm_skip               ; w tym VBI bez ramki muzyki
	sbc #6                    ; (C = 1)
	sta crk_mph
cm_play
	lda crk_mrem
	ora crk_mrem+1
	bne cm_frame
	jsr crk_mus_reset         ; koniec utworu / pierwszy tick: od poczatku
	lda #<CRK_MFR
	sta crk_mrem
	lda #>CRK_MFR
	sta crk_mrem+1
	jmp cm_cnt
cm_frame
	jsr crk_mus_dec
cm_cnt
	lda crk_mrem
	bne cm_lo
	dec crk_mrem+1
cm_lo
	dec crk_mrem
	rts
cm_skip
	sta crk_mph
	rts

; crk_mus_get: nastepny bajt strumienia (samomodyfikujacy sie adres - kod w RAM); Carry (bit literalu / dopasowania) zachowany
crk_mus_get
	lda $FFFF
	inc crk_mptr
	bne cg_ok
	inc crk_mptr+1
cg_ok
	rts
crk_mptr = crk_mus_get+1

; crk_mus_reset: strumien od poczatku; bajt 0 = maska stalych strumieni, dalej wartosci poczatkowe x = 8 ... 0 (do rejestrow POKEY i
; do ostatniej komorki bufora - ramka -1)
crk_mus_reset
	lda #<crk_song
	sta crk_mptr
	lda #>crk_song
	sta crk_mptr+1
	jsr crk_mus_get
	sta crk_mmask
	lda #1
	sta crk_mbd               ; zapas bitow: przy pierwszym uzyciu pobierze bajt
	ldx #8
cr_seed
	jsr crk_mus_get
	sta AUDF1,x
	pha
	lda crk_mpg,x
	sta crk_mzp+1
	ldy #255
	pla
	sta (crk_mzp),y           ; wartosc poczatkowa = ostatnia komorka bufora (ramka -1)
	lda #0
	sta crk_mcopy,x           ; brak kopii w toku
	sta crk_mpos,x
	dex
	bpl cr_seed
	lda #0
	sta crk_mcur
	rts

; crk_mus_dec: jedna ramka - dla kazdego niestalego strumienia x = 8 ... 0: literal albo kopia z bufora historii (przesuniecie 8 bitow)
crk_mus_dec
	lda crk_mmask
	sta crk_mchb
	ldx #8
cd_l
	lsr crk_mchb
	bcs cd_skip               ; strumien staly
	lda crk_mpg,x
	sta crk_mzp+1
	lda crk_mcopy,x
	bne cd_copy               ; trwa kopiowanie
	lsr crk_mbd
	bne cd_bit
	jsr crk_mus_get           ; nowy bajt bitow (bit 0 = pierwszy flag, reszta po przesunieciu)
	ror
	sta crk_mbd
cd_bit
	jsr crk_mus_get
	bcs cd_store              ; C = 1: literal (bajt = wartosc)
	sta crk_mpos,x            ; C = 0: dopasowanie - przesuniecie i dlugosc
	jsr crk_mus_get
	sta crk_mcopy,x
cd_copy
	dec crk_mcopy,x
	inc crk_mpos,x
	ldy crk_mpos,x
	lda (crk_mzp),y
cd_store
	ldy crk_mcur
	sta AUDF1,x
	sta (crk_mzp),y
cd_skip
	dex
	bpl cd_l
	inc crk_mcur
	rts

; strony buforow historii wg strumienia x: 0-3 -> $3F-$3C, 6-7 -> $3B-$3A; stale 4, 5, 8 (AUDF3, AUDC3, AUDCTL) -> strona x = 0
crk_mpg	dta b([>CRK_MB]+5, [>CRK_MB]+4, [>CRK_MB]+3, [>CRK_MB]+2, [>CRK_MB]+5, [>CRK_MB]+5, [>CRK_MB]+1, >CRK_MB, [>CRK_MB]+5)

crk_mntsc	dta b(0)            ; 0 = PAL
crk_mph	dta b(1)                ; NTSC: faza 5/6
crk_mrem	dta a(0)            ; pozostale ramki utworu (0 = start)
crk_mmask	dta b(0)            ; maska stalych strumieni
crk_mbd	dta b(1)                ; bity flag LZSS (jak mz_bitdata)
crk_mchb	dta b(0)            ; robocza: maska w petli
crk_mcur	dta b(0)            ; kursor bufora historii (ramka mod 256)
crk_mcopy	:9 dta b(0)         ; pozostala dlugosc kopii strumienia x
crk_mpos	:9 dta b(0)         ; pozycja odczytu w buforze strumienia x

; Utwor: Scrap Brain Zone - muzyka SKY1 (Yuzo Koshiro, wersja C64 V1.2, 2021 - docs/m5-muzyka.md), LZSS16 - tools/pack_crk_music.py
crk_song
	ins 'crk_music.lz16'

; Display lista tuz przed fontem (wyrownanym do 1 KB): kod konczy sie przed granica fontu, wiec lista lezy w jednym bloku 1 KB
; (licznik adresu display listy ANTIC-a ma 10 bitow - granicy 1 KB nie przekracza; asercja nizej).
; display lista (192 linie pola obrazu po 24 pustych - jak ekran OS-u): tytul od gornej krawedzi pola, napisy, linie wyboru, ogon
; zmienny (crk_dlt, crk_tail: 1 linia z DLI 3 + U pustych + scroll 8 + 24 - U pustych = 33 linie) konczy sie na dole pola.
; Linie: 16 + 2 + 8 + 16 + 8 + 8 + 4 + 8 + 16 + 8 + 16 + 8 + 5 + (1 + 8 + 1) + 2 + (1 + 8 + 1) + 14 + 33 = 192.
crk_dl
	dta $70,$70,$F0           ; 24 puste linie (nad polem obrazu), na ostatniej DLI T (gradient tytulu)
	dta $47,a(crk_l1)         ; SONIC THE HEDGEHOG (tryb 7: 16 linii, 20 znakow)
	dta $10                   ; 2 puste
	dta $44,a(crk_l2)         ; (c) SEGA 1991 (tryb 4: 40 znakow, 8 linii, kolor COLPF3 - ciemnoniebieski)
	dta $70,$70               ; 16 pustych
	dta $42,a(crk_l3)         ; Sonic A8 VBXE v1.0 - A fan-made port
	dta $42,a(crk_l4)         ; for ATARI XL/XE + VBXE
	dta $30                   ; 4 puste
	dta $42,a(crk_l5)         ; by madness77
	dta $70,$F0               ; 16 pustych, na ostatniej DLI A (jasnosc napisu nizej)
	dta $C2,a(crk_l6)         ; THIS GAME IS NOT FOR SALE, DLI B na koncu (biale litery dalej)
	dta $70,$70               ; 16 pustych
	dta $42,a(crk_l7)         ; pomoc: strzalki ATASCII
	dta $C0                   ; 5 pustych, DLI 1 (kolory linii zyc)
; Linie wyboru: nad i pod kazda 1 linia trybu F (hires, 40 bajtow zer crk_zero - w foncie): pusta linia
; display listy ma kolor COLBK, a linia trybu F z zerami - COLPF2 na szerokosci pola, czyli tlo podswietlenia o 1 linie wyzsze
; i nizsze niz sam tekst (8 + 2 linie).
	dta $4F,a(crk_zero)       ; 1 linia tla zyc (nad tekstem)
crk_dl4
	dta $42,a(crk_lb)         ; linia zyc (bufor)
	dta $CF,a(crk_zero)       ; 1 linia tla zyc (pod tekstem), DLI 2 na niej (kolory linii poziomu od nastepnej linii)
	dta $10                   ; 2 puste
	dta $4F,a(crk_zero)       ; 1 linia tla poziomu (nad tekstem)
crk_dl5
	dta $42,a(crk_lb+40)      ; linia poziomu (bufor)
	dta $4F,a(crk_zero)       ; 1 linia tla poziomu (pod tekstem)
	dta $70,$50               ; 14 pustych - ogon ze scrollem do dolu pola
crk_dlt                         ; ogon: najdluzszy wariant 13 B (1 + 3 + 3 + 3 + 3), zapas do 16
	dta $41,a(crk_dl)
	:13 dta b(0)
crk_dlend
	.if crk_dl/$400 <> [crk_dlend-1]/$400
	.error "display lista cracktro przekracza granice 1 KB (licznik ANTIC-a jej nie przekracza)"
	.endif

; Font z UltimateCart (sdcart.fnt, 1K, wyrownany do 1K dla CHBASE; kolejnosc kodow ekranowych jak w foncie OS)
	.align $400
crk_font
	ins 'sdcart.fnt',0,$200   ; znaki $00-$3F (spacja, interpunkcja, cyfry, wielkie litery)
; $40-$48: glify trybu 4 dla "(c) SEGA 1991" (w foncie OS / UltimateCart: znaki graficzne ATASCII - w cracktro nieuzywane). 4 piksele
; na wiersz (para bitow = piksel szerokosci 2 pikseli hires), 11 = kolor 3 (kod znaku z bitem 7 -> COLPF3, nie COLPF2). Przeliczone
; z glifow trybu 2 (wiersz przesuniety o 1 w lewo, para bitow -> piksel), nawiasy rysowane recznie.
crk_f4
	dta b($00,$30,$C0,$C0,$C0,$C0,$30,$00)   ; $40 '(': .... .#.. #... #... #... #... .#.. ....
	dta b($00,$00,$FC,$C0,$C0,$C0,$FC,$00)   ; $41 'c': .... .... ###. #... #... #... ###. ....
	dta b($00,$C0,$30,$30,$30,$30,$C0,$00)   ; $42 ')': .... #... .#.. .#.. .#.. .#.. #... ....
	dta b($00,$FC,$C0,$FC,$0C,$0C,$FC,$00)   ; $43 'S': .... ###. #... ###. ..#. ..#. ###. ....
	dta b($00,$FC,$C0,$FC,$C0,$C0,$FC,$00)   ; $44 'E': .... ###. #... ###. #... #... ###. ....
	dta b($00,$FC,$C0,$C0,$FC,$CC,$FC,$00)   ; $45 'G': .... ###. #... #... ###. #.#. ###. ....
	dta b($00,$FC,$CC,$CC,$FC,$CC,$CC,$00)   ; $46 'A': .... ###. #.#. #.#. ###. #.#. #.#. ....
	dta b($00,$F0,$F0,$30,$30,$30,$FC,$00)   ; $47 '1': .... ##.. ##.. .#.. .#.. .#.. ###. ....
	dta b($00,$FC,$CC,$FC,$0C,$0C,$0C,$00)   ; $48 '9': .... ###. #.#. ###. ..#. ..#. ..#. ....
crk_f4end
crk_zero                        ; $49-$4D: 40 bajtow zer - dane linii tla trybu F przy selektorach (znaki graficzne - w cracktro nieuzywane)
	:40 dta b(0)
crk_zend
	ins 'sdcart.fnt',crk_zend-crk_font    ; reszta fontu ($4E-$7F: strzalki $5C-$5F, male litery)
crk_end
	.if crk_f4<>crk_font+$200 .or crk_end<>crk_font+$400
	.error "font cracktro: glify trybu 4 od $40, razem 1 KB"
	.endif
	.if crk_end > CRK_MB
	.error "cracktro nachodzi na bufory muzyki (CRK_MB-$3FFF)"
	.endif
	ini crk_main
