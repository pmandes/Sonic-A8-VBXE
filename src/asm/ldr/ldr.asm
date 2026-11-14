; =====================================================================
;  ldr.asm - M7.2: modul ladowania obrazow bankow (docs/plan-m7-ldr.md 4, docs/plan-m7.md M7.2)
;
;  Kod rezydentny za kernel/nmi.asm (game_code.asm), w calosci ponizej $A000 (asercja ldr_end_mark): na carcie (M7.3) okno $A000-$BFFF
;  zaslania kod gry, wiec kod dzialajacy przy wlaczonym carcie (ldr_fetch_cart) i NMI / IRQ musza lezec nizej.
;  Jeden kod wyboru bankow dla wszystkich buildow (decyzja M7.2):
;   - czesc wspolna (XEX i nosniki): tablice rol z tools/manifest.py (build/assets/ldr_tables.inc) i ldr_need - wolane z lv_select
;     (game_code.asm); w XEX wpis tablicy = PORTB banku rezydentnego, wiec ldr_need tylko przepisuje wpisy do v_pb* / v_img
;     (zachowanie jak tablice zn_* z M7.1, bez ladowania; w XEX nie ma nic wiecej z ldr);
;   - czesc nosnika (MEDIA <> MEDIA_XEX): ldr_init, ldr_load, ldr_fetch (zrodlo wg MEDIA), ldr_unpack, zx02, stan slotow ld_slot_img.
;  Zrodla: MEDIA_RAM - ldr_fetch_ram (RAMCART w bankach 1088K, test w Altirze - build/sonic-ram.xex); MEDIA_CART - ldr_fetch_cart (M7.3);
;  MEDIA_SIO - ldr_fetch_sio (M7.4, xBIOS; start z dyskietki, RESET i komunikaty zmiany dyskietki - blok MEDIA_SIO nizej). Plik obrazu (tools/pack_zone.py): naglowek 4 B (len_u 16 b, delta, flagi: b0 = surowe) +
;  strumien zx02 (dmsc v3); dekompresja w miejscu (strumien konczy sie delta B za koncem wyniku - LDR_SPILL).
;  Wolane w czerni (level_boot po mapie, tele_reload: restart z szyba SKY3, pod-poziom, poziom $12) - bez ramek gry; NMI gry dziala
;  w czasie dekompresji (muzyka pod-poziomow gra dalej; NMI zachowuje PORTB i nie uzywa ZP $82-$89), NMIEN = 0 tylko na czas kopii
;  RAMCART z wylaczonym MEMAC (bufor $2000). Bramka budowy: ;@LDR ... ;@LDR_END wokol kodu, ktory na carcie (M7.3) dziala przy
;  wlaczonym carcie - tools/sprawdz_xex.py: skoki z obszaru tylko ponizej $A000 i poza oknem $4000-$7FFF, $D5xx tylko sta abs.
; =====================================================================
	icl 'ldr_tables.inc'      ; build/assets (tools/manifest.py): ZONE_N, SUB_*, LI_*, ldr_lvl, ldr_sub (+ nosnik: ldr_role_pb/slot, ldr_slot_pb)

; ---------------------------------------------------------------------
; ldr_need: obrazy 4 rol poziomu -> v_img (identyfikator obrazu: XEX - PORTB, nosnik - id) i v_pblevel / v_pbatlas / v_pbzspr / v_pbobjz
; (PORTB banku z obrazem; uzywaja ich render/load.asm, render/sprites.asm, game/level.asm, game/objcom.asm...). Odpowiednik czesci
; load_and_run_level oryginalu, ktora wybiera banki poziomu (00:1D15: bank naglowka) - u nas tez doczytanie obrazow nosnika.
; Wejscie: X = lv_idx (0-26: g_level 0-$12 -> 0-18, etapy specjalne $1C-$23 -> 19-26), Y = pod-poziom 0-6 ($14-$1A, lv_select: iy_06 b4
; w akcie SBZ2 / SKY2) albo $FF. Pod-poziom zmienia role poziom (ldr_sub) i atlas (tylko $1A - atlas SKY3).
; XEX: v_pb* = v_img = wpis (bez ladowania). Nosnik: wpis = id | LDR_ALT -> v_pb* = ldr_role_pb[rola * 2 + alt] (slot roli albo staly
; bank 39), v_img = id; obraz rozny od ld_slot_img[slot] -> ldr_load. Rola z id 0 (GHZ: obiekty strefy) - slot bez zmian.
; Niszczy: A, X, Y; nosnik takze zp_src..zp_cnt ($82-$89 - kopia i zx02). Wyjscie nosnika: PORTB = PB_MAIN, gdy cos ladowano
; (ldr_load), inaczej PORTB bez zmian (review M7.2); XEX: PORTB bez zmian.
; ---------------------------------------------------------------------
ldr_need
	sty ld_sub
	txa
	asl
	asl
	tax                       ; X = lv_idx * 4 (wpis roli LR_LEVEL)
	ldy #0
ln_cp
	lda ldr_lvl,x
	sta v_img,y               ; wpis roli (nosnik: z bitem alt - zdejmowany nizej)
	inx
	iny
	cpy #4
	bne ln_cp
	lda ld_sub
	bmi ln_set                ; bez pod-poziomu
	asl
	tax                       ; X = pod-poziom * 2
	lda ldr_sub,x             ; rola poziom: $14 / $17 - bank 14, $15 - bank 16 (nosnik: LEVEL2 - bank SBZ2 zostaje w LEVEL), $16 / $18 /
	sta v_img+LR_LEVEL        ; $19 - bank SBZ2 (inny start - LB_HDRALT), $1A - bank SKY3 (blok LB_STASH1A - sky_stash)
	lda ldr_sub+1,x           ; rola atlas: $1A - atlas SKY3 (grafika tla strefy flag 7; g_level zostaje 16), inne - 0 = atlas aktu
	beq ln_set
	sta v_img+LR_ATLAS
ln_set
	.if MEDIA=MEDIA_XEX
	ldx #LR_OBJZ              ; XEX 1088K: wszystko rezydentne - PORTB banku = wpis
ln_x
	lda v_img,x
	sta v_pblevel,x
	dex
	bpl ln_x
	rts
	.else
	ldx #LR_LEVEL             ; nosnik: rola po roli (poziom, atlas, sprite'y, obiekty)
ln_m
	stx ld_r
	lda v_img,x
	asl                       ; C = LDR_ALT (drugi slot roli)
	txa
	rol                       ; A = rola * 2 + alt
	tay
	lda ldr_role_pb,y
	sta v_pblevel,x           ; PORTB slotu roli (OS off) albo stalego banku 39 (sprite'y GHZ / $12 / etapow)
	lda v_img,x
	and #LDR_ID
	sta v_img,x               ; v_img = id obrazu (porownania z LI_* w kodzie gry: sky_stash, level_restart, lay_pages, glass_read)
	beq ln_nx                 ; rola bez obrazu (GHZ: obiekty strefy - objz_call nieuzywane) - zawartosc slotu bez znaczenia
	ldx ldr_role_slot,y
	bmi ln_nx                 ; $FF: bank staly (wgrany przy starcie) - bez ladowania
	cmp ld_slot_img,x
	beq ln_nx                 ; obraz juz w slocie (np. atlas strefy przy kolejnym akcie, LEVEL SBZ2 po pod-poziomie $14)
	jsr ldr_load              ; A = id, X = slot
ln_nx
	ldx ld_r
	inx
	cpx #LR_OBJZ+1
	bne ln_m
ldr_need_done                   ; test (tools/m6_wybor_test.py --program sonic-ram): sloty po ladowaniu, przed kopiami bloku na poziom
	rts
	.endif

ld_sub	dta b(0)                ; ldr_need: pod-poziom 0-6 albo $FF

	.if MEDIA<>MEDIA_XEX
; ---------------------------------------------------------------------
; ldr_init: stan ldr na starcie gry (start, przed machine_init): sloty puste (ld_slot_img = 0) - pierwszy ldr_need laduje wszystkie
; obrazy poziomu. M7.2 (RAMCART): banki stale i kod laduje XEX.
; M7.3 (nosnik 320K - cart; ATR w M7.4): obrazy stale z nosnika (ldr_const_id / ldr_const_pb z tools/manifest.py: 10 bankow 37-59) do
; swoich bankow. Wolane ze start (start_media -> boot_check -> start): OS wlaczony (PORTB = $FF), sei, NMIEN = 0 - VBI OS-u nie moze
; biec przy przelaczaniu cartu (TRIG3 / GINTLK), a NMI gry jeszcze nie ma (machine_init pozniej). Stad cienie: ld_os = 1 (bit 0 PORTB:
; OS ROM zostaje wlaczony przy wyborze banku - ldr_load_pb i powrot PB_MAIN | 1) i ld_nmien = 0 (ldr_fetch_cart po kopii nie wlacza
; NMI); na koniec wartosci gry (ld_os = 0, ld_nmien = NMI_VBI). Czas: ok. 10 x (kopia + zx02) - pomiar tools/m7_nosnik_test.py.
; ---------------------------------------------------------------------
ldr_init
	lda #0
	ldx #LDR_NSLOT-1
li_l
	sta ld_slot_img,x
	dex
	bpl li_l
	.if NOSNIK_320
	lda #1
	sta ld_os                 ; PORTB z OS wlaczonym (PB_LD_* = PB_* | 1): RAM pod OS jeszcze nieustawiony (wektory $FFFA-$FFFF gry
	lda #0                    ; wpisuje dopiero machine_init) - przy OS ROM wektory sa OS-u (bezpieczne), jak przy ladowaniu XEX-a
	sta ld_nmien              ; NMI wylaczone przez caly ldr_init
	ldx #LDR_NCONST-1
li_c
	stx ld_ci
	lda ldr_const_id,x
	sta ld_id
	lda ldr_const_pb,x        ; PORTB banku stalego (OS off) - ldr_load_pb dodaje ld_os
	jsr ldr_load_pb
ldr_init_img                    ; test (tools/m7_nosnik_test.py): obraz staly ld_id wgrany do banku ld_pb
	ldx ld_ci
	dex
	bpl li_c
	.if MEDIA=MEDIA_SIO
; M7.4: xBIOS na gre (OS wylaczony na zawsze po machine_init): po kazdej operacji xBIOS wpisuje IRQEN = xIRQEN i robi cli - w grze
; IRQ wektor = irq_handler (rti, bez kasowania zrodla), wiec xIRQEN = 0 (zadnych zrodel IRQ POKEY-a); bufor I/O ze strony $0C (faza startu:
; strony 2-3 nalezaly do OS-u - komunikat E: boot_check, VBI) na $03 - RINGMASK_RAM ($0C00) zapisuje dopiero poziom
	lda #0
	sta XB_IRQEN
	ldx #XB_BUF_GRA
	clc
	jsr XBIOS_RELOCATE_BUFFER
	sei
; review M7.4: RESET w grze ma byc zawsze zimnym startem (gra zajmuje strony 2-3 OS-u: RCMASK na COLDST $0244, bufor xBIOS-a $0300).
; OS XL rozpoznaje goracy start po PUPBT1-3 ($033D-$033F = $5C, $93, $25) - przy sektorach 128 B (SD / ED) xBIOS kladzie dane dopiero od
; bufor + $80, wiec PUPBT przezywaly by gre i wynik RESET-u zalezal by od tresci RCMASK; zero w PUPBT1 = zimny start zawsze
	lda #0
	sta PUPBT1
	.endif
	lda #0
	sta ld_os                 ; gra: OS wylaczony (machine_init), PORTB slotow = PB_SL_*
	lda #NMI_VBI
	sta ld_nmien              ; gra: NMI VBI gry po kopii z nosnika
ldr_init_done                   ; test / pomiar: banki stale wgrane (PORTB = $FF - OS on, RAM glowna)
	.endif
	rts

; ---------------------------------------------------------------------
; ldr_load: A = id obrazu, X = slot (0-5, ldr_slot_pb) -> obraz w banku slotu od BANK_WIN, ld_slot_img[slot] = id.
; Slot oznaczony jako pusty do konca dekompresji (przerwane ladowanie - M7.4: blad odczytu, zmiana dyskietki - ponawia sie od nowa).
; Wyjscie: PORTB = PB_MAIN (| ld_os - M7.3: w ldr_init OS wlaczony).
; ldr_load_pb (M7.3): A = PORTB banku (OS off), ld_id = id obrazu - wspolna czesc ladowania (tez banki stale w ldr_init, bez slotu).
; ---------------------------------------------------------------------
ldr_load
	sta ld_id
	stx ld_slot
	lda #0
	sta ld_slot_img,x         ; slot pusty do konca ladowania
	lda ldr_slot_pb,x         ; PORTB slotu (OS off)
	jsr ldr_load_pb
	ldx ld_slot
	lda ld_id
	sta ld_slot_img,x
	rts
ldr_load_pb
	.if NOSNIK_320
	ora ld_os                 ; M7.3: bit 0 = 1 - OS ROM wlaczony w ldr_init (okno $4000 i tak RAM banku: bit 4 = 0, bit 7 = 1 banki 33-63)
	.endif
	sta ld_pb                 ; PORTB banku docelowego
	jsr ldr_fetch             ; plik obrazu: naglowek -> ld_flags, strumien w oknie slotu od ld_src (pozycja w miejscu)
	jsr ldr_unpack            ; zx02: ld_src -> BANK_WIN
ldr_load_ok                     ; pomiar (tools/m7_ldr_unit.py): koniec dekompresji
	lda #PB_MAIN
	.if NOSNIK_320
	ora ld_os                 ; M7.3: ldr_init - RAM glowna pod $4000, OS ROM dalej wlaczony
	.endif
	sta PORTB
	rts

; ---------------------------------------------------------------------
; ldr_unpack: dane surowe (flagi b0 = 1: plik bez kompresji) - ldr_fetch skopiowal je wprost od BANK_WIN (ld_src = BANK_WIN: len_c = len_u,
; delta = 0); inaczej zx02 (src/ldr/zx02.asm) ze strumienia ld_src do BANK_WIN w banku slotu ld_pb. Niszczy A, X, Y, ZP $82-$89.
; ---------------------------------------------------------------------
ldr_unpack
	lda ld_pb
	sta PORTB
	lda ld_flags
	lsr
	bcs lu_raw                ; surowe - gotowe
	lda ld_src
	sta zx0_ini_block+1       ; adres strumienia (pozycja w miejscu); wynik: BANK_WIN (blok startowy zx02)
	lda ld_src+1
	sta zx0_ini_block+2
	.if MEDIA=MEDIA_SIO
	lda ld_dst                ; M7.4: cel wyniku - BANK_WIN (obrazy bankow) albo poczatek obrazu kodu (ldr_load_code: CODE_LO,
	sta zx0_ini_block+3       ; kod_hi_start); cart i RAMCART zawsze BANK_WIN (blok startowy zx02 bez zmian)
	lda ld_dst+1
	sta zx0_ini_block+4
	.endif
	jmp zx02_decomp
lu_raw
	rts

; --- zrodlo danych wg MEDIA: ldr_fetch = ld_id -> strumien w oknie slotu ld_pb od ld_src (BANK_WIN + len_u + delta - len_c), ld_flags ---
	.if MEDIA=MEDIA_RAM
ldr_fetch = ldr_fetch_ram
	.elseif MEDIA=MEDIA_CART
ldr_fetch = ldr_fetch_cart      ; M7.3: AtariMax / SIC! (CART_TYPE) - nizej
	.elseif MEDIA=MEDIA_SIO
ldr_fetch = ldr_fetch_sio       ; M7.4: ATR przez xBIOS (wariant A': $0400-$07FF, bufor $0C00 / $0300) - nizej
	.endif

	.if MEDIA=MEDIA_RAM
; ---------------------------------------------------------------------
; ldr_fetch_ram (MEDIA_RAM, test w Altirze): plik obrazu ld_id z RAMCART - obrazy zx02 ciagiem w bankach rc_pb (jak na carcie SIC!,
; 16 KB/bank; tools/pack_zone.py --ramcart), katalog RC_CAT w pierwszym banku (5 tablic po RC_NID B: indeks banku, adres lo, hi pliku,
; dlugosc lo, hi). Zrodlo i cel dziela okno $4000-$7FFF, wiec kopia przez bufor LDR_BUF ($2000-$3FFF pod MEMAC A): MEMAC wylaczony
; (jak boot_release) i NMI gry zatrzymane (NMIEN = 0) na czas obu kopii; potem MEMAC_CTL jak przed (gra: MEMAC_CTL_V) i NMIEN = NMI_VBI.
; 1. katalog -> zrodlo pliku, dlugosc; 2. plik (naglowek + strumien) -> LDR_BUF (przez granice banku RAMCART); 3. naglowek: len_u, delta,
; flagi; 4. strumien (len_c = dlugosc - 4) -> okno slotu od ld_src = BANK_WIN + len_u + delta - len_c (koniec do LDR_SPILL_N B w $8000+).
; Wolane tylko w grze (NMI gry wlaczone przed i po). Niszczy A, X, Y, zp_src, zp_dst, zp_cnt.
; ---------------------------------------------------------------------
;@LDR
ldr_fetch_ram
	lda #0
	sta NMIEN                 ; NMI gry stop na czas kopii (MEMAC off, banki RAMCART w oknie)
	ldy #VC_MEMAC_CTL
	lda (zp_fx),y
	sta ld_memac              ; MEMAC A (gra: MEMAC_CTL_V - okno VRAM $2000-$3FFF)
	lda #0
	sta (zp_fx),y             ; MEMAC off: $2000-$3FFF = RAM (bufor LDR_BUF)
	lda rc_pb                 ; 1. katalog w pierwszym banku RAMCART
	sta PORTB
	ldx ld_id
	lda RC_CAT,x
	sta ld_rcb                ; indeks banku RAMCART z poczatkiem pliku
	lda RC_CAT+RC_NID,x
	sta zp_src
	lda RC_CAT+2*RC_NID,x
	sta zp_src+1              ; adres pliku w oknie
	lda RC_CAT+3*RC_NID,x
	sta zp_cnt
	sta ld_len
	lda RC_CAT+4*RC_NID,x
	sta zp_cnt+1              ; dlugosc pliku (naglowek 4 B + strumien)
	sta ld_len+1
	ldx ld_rcb
	lda rc_pb,x
	sta PORTB
	mwa #LDR_BUF zp_dst       ; 2. plik -> bufor
	jsr ldr_copy
	lda LDR_BUF+3             ; 3. naglowek: flagi (b0 = surowe)
	sta ld_flags
	clc
	lda LDR_BUF               ; BANK_WIN + len_u + delta
	adc LDR_BUF+2
	sta zp_dst
	lda LDR_BUF+1
	adc #>BANK_WIN
	sta zp_dst+1
	sec                       ; len_c = dlugosc - 4
	lda ld_len
	sbc #4
	sta zp_cnt
	lda ld_len+1
	sbc #0
	sta zp_cnt+1
	sec                       ; - len_c: pozycja w miejscu
	lda zp_dst
	sbc zp_cnt
	sta zp_dst
	sta ld_src
	lda zp_dst+1
	sbc zp_cnt+1
	sta zp_dst+1
	sta ld_src+1
	lda ld_pb                 ; 4. strumien z bufora do okna slotu
	sta PORTB
	mwa #LDR_BUF+4 zp_src     ; (zrodlo < $4000 - ldr_copy nie zmienia banku)
	jsr ldr_copy
	ldy #VC_MEMAC_CTL         ; MEMAC A i NMI gry z powrotem
	lda ld_memac
	sta (zp_fx),y
	lda #NMI_VBI
	sta NMIEN
	rts

; ldr_copy: (zp_src) -> (zp_dst), zp_cnt B (16 bit, > 0), bajt po bajcie; zrodlo przez koniec okna ($7FFF) -> nastepny bank RAMCART
; (ld_rcb + 1) od BANK_WIN. Licznik ujemny (-n, inc do 0): ok. 35 cykli na bajt. Niszczy A, X, Y, zp_src, zp_dst, zp_cnt.
ldr_copy
	sec                       ; zp_cnt = -n
	lda #0
	sbc zp_cnt
	sta zp_cnt
	lda #0
	sbc zp_cnt+1
	sta zp_cnt+1
	ldy #0
lc_l
	lda (zp_src),y
	sta (zp_dst),y
	inc zp_dst
	bne lc_d
	inc zp_dst+1
lc_d
	inc zp_src
	bne lc_n
	inc zp_src+1
	bpl lc_n                  ; zrodlo < $8000 - ten sam bank
	inc ld_rcb                ; koniec banku RAMCART: nastepny od $4000 (plik ciagiem jak na carcie)
	ldx ld_rcb
	lda rc_pb,x
	sta PORTB
	lda #>BANK_WIN
	sta zp_src+1
lc_n
	inc zp_cnt
	bne lc_l
	inc zp_cnt+1
	bne lc_l
	rts
;@LDR_END

; banki RAMCART (OS off) w kolejnosci danych: 38, 40, ..., 62, 0 - ta sama lista co RC_BANKI w tools/pack_zone.py (bez 34 - skrypt
; testow, bez 36 - dane ekranow w sonic-ram.xex jak w XEX); PORTB banku n = (n & 7) << 1 | (n >> 3) << 5 (select_bank)
rc_pb	dta b([[38&7]*2]|[[38>>3]*32], [[40&7]*2]|[[40>>3]*32], [[42&7]*2]|[[42>>3]*32], [[44&7]*2]|[[44>>3]*32])
	dta b([[46&7]*2]|[[46>>3]*32], [[48&7]*2]|[[48>>3]*32], [[50&7]*2]|[[50>>3]*32], [[52&7]*2]|[[52>>3]*32])
	dta b([[54&7]*2]|[[54>>3]*32], [[56&7]*2]|[[56>>3]*32], [[58&7]*2]|[[58>>3]*32], [[60&7]*2]|[[60>>3]*32])
	dta b([[62&7]*2]|[[62>>3]*32], 0)
RC_NBANK	= *-rc_pb
ld_rcb	dta b(0)                ; ldr_fetch_ram: biezacy indeks banku RAMCART
ld_len	dta a(0)                ;   dlugosc pliku obrazu
ld_memac	dta b(0)              ;   MEMAC_CTL sprzed kopii
	.endif

	.if MEDIA=MEDIA_CART
; ---------------------------------------------------------------------
; ldr_fetch_cart (M7.3, MEDIA_CART): plik obrazu ld_id z cartridge'a -> strumien w oknie banku ld_pb (pozycja w miejscu dla zx02).
; Cart (AtariMax 1 MB / SIC! 512 KB - CART_TYPE) widzimy tylko przez okno $A000-$BFFF (bank logiczny 8 KB; SIC!: gorna polowka banku
; 16 KB - okno $8000 nigdy nie jest wlaczane, bo zaslonilo by ten kod, NMI i LDR_SPILL). Uklad cartu (tools/pack_cart.py): bank logiczny
; CART_BOOT = start + katalog CC_* (5 tablic po 64 B: bank poczatku pliku, adres w oknie lo / hi, dlugosc pliku lo / hi), dalej kod
; surowy dla stubu startowego (AtariMax; SIC! - w dolnych polowkach, ktore czyta tylko stub) i pliki obrazow ciagiem przez kolejne
; banki (naglowek 4 B pliku nigdy nie przechodzi przez granice banku).
; Przebieg:
;  1. PORTB = ld_pb (bank docelowy w oknie $4000; PORTB nie wplywa na okno cartu $A000), NMIEN = 0 - nmi_handler wola kod muzyki
;     w $A000+ (snd_nmi), ktory przy wlaczonym carcie zaslania ROM; IRQ i tak wylaczone (gra: IRQEN = 0, sei; ldr_init: sei).
;  2. cart wlaczony na bank startowy: rekord katalogu id -> ld_cb, zp_src (adres w oknie), ld_len (dlugosc pliku).
;  3. bank pliku: naglowek 4 B (len_u, delta, flagi) -> ld_hdr, zp_src += 4 (na granicy $C000 - nastepny bank od $A000).
;  4. len_c = ld_len - 4, cel = BANK_WIN + len_u + delta - len_c (strumien konczy sie delta B za koncem wyniku - dekompresja w miejscu;
;     pelny bank wychodzi do LDR_SPILL_N B w $8000+ - tam RAM: AtariMax nie ma okna $8000, SIC! ma je wylaczone) -> zp_dst, ld_src.
;  5. kopia odcinkami: odcinek = min(reszta, $C000 - zp_src) - strony petla (zp_src),y -> (zp_dst),y (ok. 16 cykli / B), reszta
;     odcinka bajtami; koniec okna -> nastepny bank logiczny od $A000.
;  6. cart wylaczony (AtariMax: zapis pod $D580; SIC!: $40 do $D500 - oba okna off), NMIEN = ld_nmien (gra: NMI_VBI, ldr_init: 0).
; Caly kod przy wlaczonym carcie lezy w obszarze ;@LDR ponizej $A000, dane tylko w ZP i w tym obszarze (bramka tools/sprawdz_xex.py:
; skoki tylko w obrebie obszaru, operandy danych w $A000-$BFFF tylko ze znacznikiem ;@CART - katalog w ROM-ie cartu, $D5xx tylko
; sta abs - odczyt / tryb indeksowany z $D5xx przelacza bank AtariMax, (zp),y tylko przez zp_src / zp_dst). Rejestr AtariMax: bank
; = bity 0-6 ADRESU zapisu - adres operandu sta $D500 podmieniany w kodzie (lfc_bsm), wartosc zapisu bez znaczenia.
; Niszczy A, X, Y, zp_src, zp_dst. Wyjscie: ld_src (strumien), ld_flags (b0 = surowe), PORTB = ld_pb.
; ---------------------------------------------------------------------
;@LDR
ldr_fetch_cart
	lda ld_pb
	sta PORTB                 ; 1. bank docelowy pod $4000 (slot albo bank staly; OS on/off wg ld_os - ldr_load_pb)
	lda #0
	sta NMIEN                 ;    NMI gry stop na czas wlaczonego cartu (kod muzyki NMI w $A000+ zasloniety)
	ldy #CART_BOOT
	jsr lfc_bank              ; 2. cart wlaczony: bank startowy z katalogiem
	ldx ld_id
	lda CC_BANK,x             ;@CART - katalog w ROM-ie cartu (bank logiczny poczatku pliku)
	sta ld_cb
	lda CC_ADRL,x             ;@CART - adres pliku w oknie $A000-$BFFF
	sta zp_src
	lda CC_ADRH,x             ;@CART
	sta zp_src+1
	lda CC_LENL,x             ;@CART - dlugosc pliku (naglowek 4 B + strumien)
	sta ld_len
	lda CC_LENH,x             ;@CART
	sta ld_len+1
	ldy ld_cb
	jsr lfc_bank              ; 3. bank z poczatkiem pliku
	ldy #3
lfc_h
	lda (zp_src),y            ;    naglowek: len_u (2), delta, flagi - nie przechodzi przez $BFFF (tools/pack_cart.py wyrownuje)
	sta ld_hdr,y
	dey
	bpl lfc_h
	clc                       ;    zp_src += 4 (strumien zx02)
	lda zp_src
	adc #4
	sta zp_src
	bcc lfc_h1
	inc zp_src+1
	lda zp_src+1
	cmp #>CART_END
	bne lfc_h1                ;    naglowek konczy bank dokladnie na $BFFF - strumien od nastepnego banku
	inc ld_cb
	ldy ld_cb
	jsr lfc_bank
	lda #>CART_WIN
	sta zp_src+1
lfc_h1
	sec                       ; 4. len_c = dlugosc - 4
	lda ld_len
	sbc #4
	sta ld_len
	lda ld_len+1
	sbc #0
	sta ld_len+1
	clc                       ;    cel = BANK_WIN + len_u + delta - len_c (dane surowe: delta = 0, len_c = len_u -> BANK_WIN)
	lda ld_hdr                ;    len_u lo
	adc ld_hdr+2              ;    + delta
	sta zp_dst
	lda ld_hdr+1              ;    len_u hi
	adc #>BANK_WIN
	sta zp_dst+1
	sec
	lda zp_dst
	sbc ld_len
	sta zp_dst
	sta ld_src                ;    strumien dla ldr_unpack (zx02 w miejscu)
	lda zp_dst+1
	sbc ld_len+1
	sta zp_dst+1
	sta ld_src+1
	lda ld_hdr+3
	sta ld_flags              ;    flagi (b0 = dane surowe)
lfc_seg                         ; 5. odcinek: ld_n = min(ld_len, $C000 - zp_src) - bez przejscia przez koniec okna cartu
	sec
	lda #<CART_END
	sbc zp_src
	sta ld_n
	lda #>CART_END
	sbc zp_src+1
	sta ld_n+1                ;    do konca okna (1..$2000)
	lda ld_len+1
	cmp ld_n+1
	bcc lfc_last              ;    reszta pliku krotsza (starszy bajt)
	bne lfc_cut               ;    dluzsza - odcinek do konca okna
	lda ld_len
	cmp ld_n
	bcs lfc_cut               ;    >= - odcinek do konca okna
lfc_last
	lda ld_len                ;    ostatni odcinek: cala reszta
	sta ld_n
	lda ld_len+1
	sta ld_n+1
lfc_cut
	sec                       ;    ld_len -= ld_n
	lda ld_len
	sbc ld_n
	sta ld_len
	lda ld_len+1
	sbc ld_n+1
	sta ld_len+1
	ldy #0
	ldx ld_n+1                ;    pelne strony odcinka
	beq lfc_r0
lfc_p
	lda (zp_src),y            ;    cart (okno $A000) -> okno banku $4000 (+ LDR_SPILL w $8000)
	sta (zp_dst),y
	iny
	bne lfc_p
	inc zp_src+1
	inc zp_dst+1
	dex
	bne lfc_p
lfc_r0
	ldx ld_n                  ;    reszta odcinka (< 256 B)
	beq lfc_nx
lfc_r
	lda (zp_src),y
	sta (zp_dst),y
	iny
	dex
	bne lfc_r
	tya                       ;    zp_src += Y
	clc
	adc zp_src
	sta zp_src
	bcc lfc_r1
	inc zp_src+1
lfc_r1
	tya                       ;    zp_dst += Y
	clc
	adc zp_dst
	sta zp_dst
	bcc lfc_nx
	inc zp_dst+1
lfc_nx
	lda ld_len
	ora ld_len+1
	beq lfc_end               ;    plik skopiowany
	inc ld_cb                 ;    odcinek doszedl do $C000: nastepny bank logiczny od $A000 (zp_src lo = 0)
	ldy ld_cb
	jsr lfc_bank
	lda #>CART_WIN
	sta zp_src+1
	jmp lfc_seg
lfc_end
	.if CART_TYPE=CART_AM
	sta CART_AM_OFF           ; 6. AtariMax: dostep do $D580 (bit 7 adresu) - cart wylaczony, $A000-$BFFF = RAM (kod gry)
	.else
	lda #CART_SIC_OFF         ; 6. SIC!: bit 6 = 1 (okno $A000 off), bit 5 = 0 (okno $8000 off)
	sta CART_REG
	.endif
	lda ld_nmien
	sta NMIEN                 ;    gra: NMI VBI z powrotem; ldr_init: 0 (VBI OS-u dalej stoi)
	rts

; lfc_bank: Y = bank logiczny 8 KB -> cart wlaczony z tym bankiem w oknie $A000-$BFFF. Zachowuje X, Y; niszczy A.
; AtariMax: zapis pod $D500 + bank (bity 0-6 adresu; dane bez znaczenia) - mlodszy bajt operandu sta podmieniany (sta abs - bez
; odczytu $D5xx). SIC!: bajt rejestru = bank (bity 0-4) | CART_SIC_ON (bit 5 = 0: okno $8000 off, bit 6 = 0: okno $A000 on).
lfc_bank
	.if CART_TYPE=CART_AM
	sty lfc_bsm+1
lfc_bsm	sta CART_REG              ; sta $D5nn (nn = bank) - operand podmieniony wyzej
	.else
	tya
	ora #CART_SIC_ON
	sta CART_REG
	.endif
	rts

; ldr_cart_off (M7.3, review): cart wylaczony - wolane ze start (game_code.asm) na wypadek RESET-u w grze w trakcie kopii z cartu.
; Niszczy A (SIC!).
ldr_cart_off
	.if CART_TYPE=CART_AM
	sta CART_AM_OFF           ; AtariMax: dostep do $D580
	.else
	lda #CART_SIC_OFF         ; SIC!: oba okna wylaczone
	sta CART_REG
	.endif
	rts

; cart_reset (M7.3, review): DOSINI w fazie startu (start_media - OS wlaczony): RESET w cracktro / boot_check / ldr_init -> goracy start
; OS-u (cart wylaczony, TRIG3 = GINTLK = 0; RAM $BFFC = $FF - OS nie widzi cartu w RAM-ie) -> JSR (DOSINI) -> tu: przerwania i DMA stop,
; cart wlaczony z bankiem startowym 0 (AtariMax: sta $D500 - bank = bity 0-6 adresu; SIC!: rejestr $00), zimny start OS-u (COLDSV):
; OS widzi cart (naglowek $BFFA w banku 0), GINTLK = TRIG3 = 1, start gry od nowa (cb_entry -> stub -> start_media). Kod < $A000 - po
; wlaczeniu cartu okno $A000 zaslania RAM. Skok do ROM-u OS-u - znacznik ;@OS (bramka tools/sprawdz_xex.py).
	.if CART_BOOT<>0
	.error "cart_reset: bank startowy musi byc 0 (sta $D500)"
	.endif
cart_reset
	sei
	lda #0
	sta NMIEN
	sta DMACTL
	.if CART_TYPE=CART_AM
	sta CART_REG              ; sta $D500: AtariMax bank 0, cart wlaczony
	.else
	lda #CART_SIC_ON          ; SIC!: bank 0, okno $A000 wlaczone
	sta CART_REG
	.endif
	jmp COLDSV                ;@OS - zimny start OS-u z cartem
;@LDR_END

ld_cb	dta b(0)                ; ldr_fetch_cart: biezacy bank logiczny cartu
ld_len	dta a(0)                ;   pozostala dlugosc (plik, potem strumien)
ld_n	dta a(0)                ;   dlugosc odcinka
ld_hdr	dta b(0,0,0,0)          ;   naglowek pliku: len_u (2), delta, flagi
	.endif

	.if MEDIA=MEDIA_SIO
; =====================================================================
;  M7.4: ATR przez xBIOS (MEDIA_SIO; docs/plan-m7-ldr.md 2-4, docs/plan-m7.md M7.4)
;
;  Czesc SUROWA (XAUTORUN, od $8000 do kod_hi_start - game_code.asm): wszystko, co dziala, zanim z dyskietki przyjda obrazy kodu
;  B50.ZX2 (kod pod oknem $4100+) i B51.ZX2 (reszta kodu rezydentnego od kod_hi_start), a takze w grze: wejscie RESET-u atr_reset,
;  ldr_fetch_sio, komunikat ldr_msg, zmienne CRK_* cracktro i tablice obrazow ldr_img_len* (uzupelnia je tools/pack_atr.py w pliku
;  XAUTORUN - inne dla duzego obrazu DD i zestawu ED). Kod uzywany tylko przy starcie (start_media - RUN pliku XAUTORUN, ldr_kod,
;  dalszy ciag RESET-u) lezy za cracktro w $2000+ (src/ldr/atr_start.asm - RAM pod oknem MEMAC A, w grze nietkniety), nie w RAM
;  rezydentnej (M7.4: zostawal by w niej 34 B wolny). Oryginal SMS niczego nie doczytuje (ROM 256 KB);
;  odpowiednikiem jest load_and_run_level (00:1D15), ktora w czerni wybiera banki poziomu - u nas ldr_need doczytuje ich obrazy.
;  Sekwencja startu z dyskietki: OS -> xBOOT (sektory 1-3, tools/bin/xbios/xboot.obx) -> XBIOS.COM + XBIOS.CFG (relokacja na $0400,
;  bufor $0C00, wewnetrzny SIO) -> XAUTORUN (segmenty: czesc surowa $8000+, cracktro + atr_start.asm $2000+, RUN start_media) -> cracktro -> ldr_kod
;  (obrazy kodu, OS wlaczony) -> start_media_gl (src/scr/boot.asm: trainer, boot_check) -> start -> ldr_init (banki stale) -> gra.
;  Bramka (tools/sprawdz_xex.py, LDR_MEDIA = 3): w obszarze ;@LDR (kod fazy startu) skoki tylko do czesci surowej, do xBIOS-a (;@XBIOS),
;  do cracktro (;@CRK), do ROM-u OS-u (;@OS) albo do kodu z obrazow - wiersz ze znacznikiem ;@KOD (wykonywany dopiero po ldr_kod);
;  operandy danych w obrazie B51 (kod_hi_start-$BFFF) tylko z ;@KOD.
; =====================================================================
;@LDR
; ---------------------------------------------------------------------
; atr_reset: DOSINI - goracy start OS-u po RESET-cie (OS XL / AltirraOS: PORTB z OS ROM, ekran E: pod RAMTOP = $A0 juz zbudowany, strony
; 2-3 OS-u od nowa, $0400-$07FF nietkniete). Czesc rezydentna: przerwania, DMA i nakladka VBXE stop, MEMAC A i B wylaczone (rejestry
; VBXE przezywaja RESET; MEMAC A zaslania RAM $2000-$3FFF, a tam - za cracktro - czeka dalszy ciag atr_reset2: src/ldr/atr_start.asm,
; RAM pod oknem MEMAC nie jest w grze zapisywany). Kod fazy startu lezy za cracktro, nie w RAM rezydentnej (miejsce - M7.4).
; ---------------------------------------------------------------------
atr_reset
	sei
	cld
	lda #0
	sta NMIEN
	sta DMACTL
	sta SDMCTL
	ldx #$FF
	txs
	jsr atr_ini               ; nakladka VBXE, MEMAC A i B, blitter wylaczone (MEMAC A zaslania RAM $2000-$3FFF z atr_reset2)
	jmp atr_reset2            ;@CRK - src/ldr/atr_start.asm (RAM za cracktro)

; ---------------------------------------------------------------------
; atr_ini (review M7.4): segment INIT pliku XAUTORUN - xBIOS wola go po wgraniu czesci surowej $8000+, PRZED segmentem $2000 (cracktro,
; atr_start.asm) - i poczatek atr_reset. Rejestry VBXE przezywaja RESET: po zimnym starcie z gry nakladka VBXE dalej pokazuje
; ostatnia klatke gry (menu cracktro ANTIC-a niewidoczne - wyglada na zawieszenie), a okno MEMAC A ($2000-$3FFF) przekierowuje zapisy
; xBIOS-a do VRAM-u - cracktro wgrane w VRAM, a atr_reset2 wykonuje sie potem z kopii RAM z pierwszego startu. Tu, jak w stubie cartu
; (src/boot/cartboot.asm): nakladka (VIDEO_CONTROL), MEMAC B, MEMAC A (MEMAC_CTL) i blitter (BLT_START) = 0 dla VBXE pod $D640 i $D740.
; Niszczy A, Y.
; ---------------------------------------------------------------------
atr_ini
	jsr ldr_vbxe_off
	lda #0
	ldy #VC_MEMAC_B
	jsr lvo_w
	ldy #VC_MEMAC_CTL
	jsr lvo_w
	ldy #VC_BLT_START
	jmp lvo_w

; ---------------------------------------------------------------------
; ldr_fetch_sio: plik obrazu ld_id z dyskietki (xBIOS) -> strumien w oknie banku ld_pb (albo w RAM kodu - ld_dst) na pozycji w miejscu.
; Plik 'Bnn     ZX2' (nn = id dziesietnie): naglowek 4 B (len_u, delta, flagi - ten sam co cart / RAMCART, tools/pack_zone.py) + strumien
; zx02 o dlugosci len_c z tablicy ldr_img_len* (system plikow DOS 2 nie zna dokladnej dlugosci pliku, a pozycja w miejscu jej wymaga).
;  1. PORTB = ld_pb; w grze (ld_os = 0) kanaly POKEY-a cicho (NMI muzyki stoi na czas I/O - inaczej ostatnie dzwieki brzmialy by przez
;     caly odczyt), NMIEN = 0 (xBIOS odpytuje SIO na kanalach 3-4 POKEY-a; NMI gry pisze POKEY-a - ryzyko 6 z plan-m7.md 9.1);
;  2. OPEN_FILE (brak - C = 1: zla dyskietka albo blad katalogu), SET_LENGTH 4 + LOAD_DATA naglowka (C = 1 - blad);
;  3. cel = ld_dst + len_u + delta - len_c (strumien konczy sie delta B za koncem wyniku; dane surowe: delta = 0, len_c = len_u);
;  4. SET_LENGTH len_c + LOAD_DATA na cel; sukces = wskaznik pliku xNOTE = 4 + len_c (C z LOAD_DATA nie odroznia bledu od konca pliku);
;  5. blad: najpierw (bez komunikatu) powrot z Ultra Speed do predkosci standardowej i ponowienie od OPEN_FILE (lfs_slow); potem
;     komunikat: brak pliku -> "INSERT DISK n" (n w bitach 6-7 ldr_img_lenh[id] - dyskietka z najnizszym bitem maski dyskietek
;     obrazu, tools/pack_atr.py), blad odczytu -> "DISK ERROR"; FIRE -> od OPEN_FILE;
;  6. sei (xBIOS konczy z I = 0), w grze POKEY muzyki z powrotem (mus_regs_restore), NMIEN = ld_nmien.
; Wyjscie: ld_src (strumien), ld_flags; PORTB = ld_pb. Niszczy A, X, Y.
; ---------------------------------------------------------------------
ldr_fetch_sio
	lda ld_id                 ; nazwa: 'B' + id dziesietnie (2 cyfry)
	ldx #'0'
lfs_10
	cmp #10
	bcc lfs_jd
	sbc #10                   ; C = 1
	inx
	bne lfs_10                ; zawsze
lfs_jd
	ora #'0'
	sta ld_fname+2
	stx ld_fname+1
lfs_open
	lda ld_pb
	sta PORTB                 ; 1. bank docelowy pod $4000 (OS wg ld_os - ldr_load_pb)
	lda #0
	sta NMIEN
	ldx ld_os
	bne lfs_os1
	sta AUDC1                 ;    gra: cisza na czas odczytu (mus_regs_restore przywraca kanaly)
	sta AUDC2
	sta AUDC3
	sta AUDC4
lfs_os1
	ldy #<ld_fname            ; 2. plik
	ldx #>ld_fname
	jsr XBIOS_OPEN_FILE       ;@XBIOS
	sei
	jcs lfs_nofile
	ldy #4
	ldx #0
	jsr XBIOS_SET_LENGTH      ;@XBIOS
	ldy #<ld_hdr
	ldx #>ld_hdr
	jsr XBIOS_LOAD_DATA       ;@XBIOS - naglowek: len_u, delta, flagi
	sei
	jcs lfs_err
	ldx ld_id                 ; 3. len_c z tablicy (tools/pack_atr.py; starszy bajt: bity 0-5, bity 6-7 - numer dyskietki)
	lda ldr_img_lenl,x
	sta ld_len
	lda ldr_img_lenh,x
	and #$3F
	sta ld_len+1
	clc
	lda ld_dst
	adc ld_hdr                ;    + len_u
	sta ld_src
	lda ld_dst+1
	adc ld_hdr+1
	sta ld_src+1
	clc
	lda ld_src
	adc ld_hdr+2              ;    + delta
	sta ld_src
	bcc lfs_d1
	inc ld_src+1
lfs_d1
	sec
	lda ld_src
	sbc ld_len                ;    - len_c
	sta ld_src
	lda ld_src+1
	sbc ld_len+1
	sta ld_src+1
; review M7.4: kontrola spojnosci - dyskietki z roznych wydan (len_u / delta z naglowka pliku, len_c z tablicy na D1): strumien musi lezec
; w [ld_dst, ld_lim) - inaczej LOAD_DATA nadpisal by strone zerowa, stos, xBIOS albo kod; numer wydania w bitach 1-7 flag pliku =
; ldr_build (tools/pack_atr.py). Niezgodnosc -> "DISK ERROR".
	lda ld_src                ;    ld_src >= ld_dst
	cmp ld_dst
	lda ld_src+1
	sbc ld_dst+1
	jcc lfs_err
	sec                       ;    ld_lim - ld_src >= len_c
	lda ld_lim
	sbc ld_src
	tax
	lda ld_lim+1
	sbc ld_src+1
	jcc lfs_err
	cmp ld_len+1
	jcc lfs_err
	bne lfs_d2
	cpx ld_len
	jcc lfs_err
lfs_d2
	lda ld_hdr+3
	and #$FE
	cmp ldr_build             ;    wydanie pliku = wydanie XAUTORUN
	jne lfs_err
	ldy ld_len                ; 4. strumien na pozycje w miejscu
	ldx ld_len+1
	jsr XBIOS_SET_LENGTH      ;@XBIOS
	ldy ld_src
	ldx ld_src+1
	jsr XBIOS_LOAD_DATA       ;@XBIOS
	sei
	clc
	lda ld_len                ;    xNOTE = 4 + len_c (3 B; przeniesienie liczone przed porownaniami)
	adc #4
	tax
	lda ld_len+1
	adc #0
	cmp XB_NOTE+1
	bne lfs_err
	cpx XB_NOTE
	bne lfs_err
	lda XB_NOTE+2
	bne lfs_err
	lda ld_hdr+3
	sta ld_flags              ;    flagi (b0 = dane surowe)
	lda #0
	sta ld_proba              ;    proba na predkosci standardowej udana (jesli byla) - Ultra wylaczone na stale
	lda ld_os                 ; 6. gra: POKEY muzyki (xBIOS zostawil AUDCTL / AUDF3-4 / SKCTL w stanie SIO)
	bne lfs_os2
	jsr mus_regs_restore      ;@KOD - tylko w grze (ld_os = 0): zmienne muzyki z obrazu B51
lfs_os2
	lda ld_nmien
	sta NMIEN                 ;    gra: NMI VBI (zx02 dziala z muzyka); ldr_init / ldr_kod: 0
	rts
lfs_nofile                      ; 5. brak pliku
	jsr lfs_slow
	jcc lfs_open              ;    byla Ultra Speed - ponow na standardowej
	ldx ld_id
	lda ldr_img_lenh,x        ;    bity 6-7: dyskietka z plikiem - 1 (zestaw ED: najnizsza z maski, tools/pack_atr.py)
	rol
	rol
	rol
	and #3
	clc
	adc #$11                  ;    kod wewnetrzny ANTIC-a cyfry '1'..'4'
	sta lm_ins_n              ;    cyfra w tekscie "INSERT DISK n"
	ldx #lm_ins-lm_txt
	jmp lfs_msg
lfs_err                         ;    blad odczytu
	jsr lfs_slow
	jcc lfs_open
	ldx #lm_err-lm_txt
lfs_msg
	jsr ldr_msg
	jmp lfs_open

; lfs_slow: po bledzie przy Ultra Speed - proba na predkosci standardowej: xSPEED = ld_xspd, ld_proba = 1, C = 0 (ponowienie od
; OPEN_FILE bez komunikatu). Udane ponowienie (ldr_fetch_sio zeruje ld_proba) zostawia predkosc standardowa do konca gry (naped zglosil
; Ultra Speed, a transmisja zawiodla). Juz standardowa - C = 1 (komunikat); review M7.4: jesli to byla proba (ld_proba = 1), blad nie
; zalezal od predkosci (zwykle brak pliku przy zmianie dyskietki zestawu ED) - xSPEED z powrotem = xHSPEED, zeby jedna prosba o dyskietke
; nie wylaczala Ultra Speed na stale.
lfs_slow
	lda XB_SPEED
	cmp ld_xspd
	beq lfs_s1                ; rowne: predkosc standardowa
	lda ld_xspd
	sta XB_SPEED
	lda #1
	sta ld_proba
	clc
	rts
lfs_s1
	lda ld_proba
	beq lfs_s2
	lda XB_HSPEED             ; proba nic nie dala - Ultra z powrotem (ld_proba = 1 tylko po Ultra, wiec xHSPEED <> $FF)
	sta XB_SPEED
	lda #0
	sta ld_proba
lfs_s2
	sec
	rts

; ---------------------------------------------------------------------
; ldr_msg: komunikat w czerni (docs/plan-m7-ldr.md 3.4) - X = przesuniecie tekstu w lm_txt; ekran: ldr_napis.
; Czekanie: puszczenie FIRE (TRIG0), potem wcisniecie FIRE albo START (CONSOL b0) i puszczenie; test - hak ldr_btn <> 0 (debugger:
; eb ldr_btn 1 w punkcie ldr_msg_wait) zamiast przycisku. Na koniec: w grze DMA i tlo jak w grze (0); w fazie startu (ld_os = 1)
; z powrotem napis "LOADING" (review M7.4). PORTB = ld_pb.
; ldr_napis: X = przesuniecie tekstu - ekran bez czekania: ANTIC tryb 2, font OS-u z ROM-u (PORTB = ld_pb | 1 - $C000-$CFFF i
; $D800-$FFFF to ROM, RAM pod nim nietkniety; NMI i IRQ wylaczone, wiec wektory ROM-u nie graja roli), display lista i wiersz tekstu
; w LAYOUT_RAM ($1000-$1067: uklad poziomu i tak wczytuje sie po ldr_need od nowa), nakladka VBXE wylaczona fizycznie (v_video_on bez
; zmian - review M7.4: w grze obraz VBXE jest juz wylaczony przez bai_level albo tele_reload, a wlacza go frame_done / NMI po vid_hold;
; zerowanie v_video_on w tele_reload wlaczalo obraz o 1-2 klatki za wczesnie). "LOADING" w fazie startu (atr_start.asm, przez caly
; ldr_kod i ldr_init - na stock 1050 ok. 85 s): DMA zostaje wlaczone do machine_init.
; ---------------------------------------------------------------------
ldr_msg
	jsr ldr_napis
	jmp ldr_msg_wait
ldr_napis
	lda ld_pb
	ora #1
	sta PORTB                 ; OS ROM: font $E000 (okno $4000 - bank docelowy bez zmian)
	lda #0
	sta DMACTL
	ldy #39
lm_cl
	sta LDR_MSG_TXT,y         ; wiersz: spacje (kod wewnetrzny 0)
	dey
	bpl lm_cl
	ldy #0
lm_cp
	lda lm_txt,x              ; tekst (kody wewnetrzne, koniec $FF) od kolumny 7
	bmi lm_dl
	sta LDR_MSG_TXT+7,y
	inx
	iny
	bne lm_cp                 ; zawsze
lm_dl
	ldy #lm_dl_n-1
lm_dc
	lda lm_dl_tab,y
	sta LDR_MSG_DL,y
	dey
	bpl lm_dc
	jsr ldr_vbxe_off
	lda #<LDR_MSG_DL
	sta DLISTL
	lda #>LDR_MSG_DL
	sta DLISTH
	lda #$E0
	sta CHBASE                ; font OS ROM
	lda #2
	sta CHACTL
	lda #$0E
	sta COLPF1                ; jasnosc liter
	lda #0
	sta COLPF2                ; tlo wiersza
	sta COLBK
lm_vb
	lda VCOUNT                ; DMA od poczatku ramki (ANTIC zaczyna display liste od LDR_MSG_DL)
	bne lm_vb
	lda #$22
	sta DMACTL                ; zwykle pole, DMA display listy
	rts
ldr_msg_wait                    ; test (tools/m7_nosnik_test.py): bp - zrzut ekranu, eb ldr_btn 1, zmiana dyskietki
	lda ldr_btn
	bne lm_go
	lda TRIG0                 ; najpierw puszczenie FIRE (wcisniety przy wejsciu - np. z gry)
	beq ldr_msg_wait
lm_pr
	lda ldr_btn
	bne lm_go
	lda TRIG0
	beq lm_rel
	lda CONSOL
	lsr                       ; b0 = 0: START wcisniety
	bcs lm_pr
lm_rel
	lda ldr_btn
	bne lm_go
	lda TRIG0                 ; puszczenie FIRE i START (przycisk nie przechodzi do gry)
	beq lm_rel
	lda CONSOL
	lsr
	bcc lm_rel
lm_go
	lda #0
	sta ldr_btn
	ldx ld_os
	beq lm_g2
	ldx #lm_load-lm_txt       ; faza startu: z powrotem "LOADING"
	jsr ldr_napis
	jmp lm_g3
lm_g2
	sta DMACTL                ; gra: ekran jak przed komunikatem (A = 0)
	sta COLBK
lm_g3
	lda ld_pb
	sta PORTB
	rts

; ldr_vbxe_off: nakladka VBXE wylaczona (VIDEO_CONTROL = 0) dla VBXE pod $D640 i $D740 (rdzen FX: CORE_REVISION = $10 - jak stub
; cartu; zp_fx w fazie startu nie jest jeszcze ustawione). lvo_w: A -> rejestr Y obu VBXE. Niszczy A, Y.
ldr_vbxe_off
	lda #0
	ldy #VC_VIDEO
lvo_w
	pha
	lda $D600+VC_CORE_REV
	cmp #$10
	bne lvo_7
	pla
	pha
	sta $D600,y
lvo_7
	lda $D700+VC_CORE_REV
	cmp #$10
	bne lvo_x
	pla
	pha
	sta $D700,y
lvo_x
	pla
	rts

; teksty komunikatow (kody wewnetrzne ANTIC-a - d'', koniec $FF) i display lista (96 pustych linii, wiersz trybu 2, JVB)
lm_txt
lm_ins	dta d'INSERT DISK '
lm_ins_n	dta d'1',d' - PRESS FIRE',$FF
lm_err	dta d'DISK ERROR - PRESS FIRE',$FF
lm_load	dta d'        LOADING...',$FF
lm_dl_tab	dta b($70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$70,$42),a(LDR_MSG_TXT),b($41),a(LDR_MSG_DL)
lm_dl_n	= *-lm_dl_tab
;@LDR_END

; ---------------------------------------------------------------------
; mus_regs_restore (gra, po I/O xBIOS-a - ldr_fetch_sio): SIO zostawia w POKEY-u AUDCTL ($28 - kanaly 3+4 zlaczone na 1,79 MHz), AUDF3/4
; (dzielnik transmisji), SKCTL; dekoder muzyki (sound/music.asm) pisze tylko strumienie zmienne w biezacym utworze, wiec stale strumienie
; (np. AUDCTL, kanal 3) zostal by zle do konca utworu. Tu: SKCTL = 3 (jak snd_init) i 9 rejestrow AUDF1..AUDCTL z historii dekodera
; (MUS_BUF: strona strumienia X = >MUS_BUF + 8 - X; ostatnia ramka - pozycja mz_cursor - 1, strumien staly - pozycja 255 jak w
; mus_reset_decoder); bez muzyki - cisza (0). Efekt (kanal 3, AUDCTL b5) odtwarza nastepny sfx_tick, wyciszanie - mus_fade_apply w NMI.
; Wolane przy NMIEN = 0 (zmienne mus_* / mz_* bez wyscigu z NMI). Niszczy A, X, Y.
; ---------------------------------------------------------------------
mus_regs_restore
	lda #3
	sta SKCTL
	ldx #8
	lda mus_state
	bne mrr_l
mrr_z
	sta AUDF1,x               ; A = 0: AUDF1..AUDC4, AUDCTL = 0
	dex
	bpl mrr_z
	rts
mrr_l
	txa
	eor #$FF                  ; -X - 1
	clc
	adc #[>MUS_BUF]+9         ; >MUS_BUF + 8 - X
	sta mrr_ld+2
	ldy mz_cursor
	dey                       ; ostatnia zdekodowana ramka
	lda mus_mask
	and mrr_bit,x
	beq mrr_ld
	ldy #255                  ; strumien staly: wartosc poczatkowa
mrr_ld
	lda MUS_BUF,y             ; (operand podmieniany)
	sta AUDF1,x
	dex
	bpl mrr_l
	rts
mrr_bit	dta b(0, $80, $40, $20, $10, $08, $04, $02, $01) ; bit strumienia X w masce stalych (b0 = AUDCTL, X = 8 ... b7 = AUDC1, X = 1)

; --- stan i tablice czesci surowej ATR ---
; CRK_* - wynik cracktro (src/kernel/mem.inc: w XEX i carcie strona 6 $0680, tu nalezy ona do xBIOS-a); kolejnosc jak $0680-$0683
CRK_SEL	dta b(0)                ; 0 = normalny start, inaczej g_level + 1 (trainer)
CRK_INF	dta b(0)                ; 1 = nieskonczone zycia
CRK_ACT	dta b(0)                ; akt przed wybranym etapem specjalnym
CRK_NB	dta b(0)                ; pierwszy etap specjalny za pozycja
; tablice obrazow (indeks = id; tools/pack_atr.py wpisuje je w czesc surowa pliku XAUTORUN): dlugosc strumienia zx02 len_c - mlodszy
; bajt i starszy w bitach 0-5 (obraz < 16 KB), w bitach 6-7 starszego numer dyskietki z plikiem - 1, o ktora prosi komunikat (duzy obraz
; DD: 0; zestaw ED: najnizszy bit maski dyskietek obrazu - raport build/atr/raport.md; maski 1 B nie trzymamy - 52 B mniej)
ldr_img_lenl	:LDR_ATR_N dta b(0)
ldr_img_lenh	:LDR_ATR_N dta b(0)
ld_fname	dta c'B00     ZX2'     ; nazwa pliku dla OPEN_FILE (8 + 3, ATASCII)
ld_hdr	dta b(0,0,0,0)          ; naglowek pliku: len_u (2), delta, flagi
ld_len	dta a(0)                ; len_c (dlugosc strumienia)
ld_dst	dta a(BANK_WIN)         ; adres wyniku zx02 (ldr_unpack): BANK_WIN, przy obrazach kodu - CODE_LO / kod_hi_start
ld_xspd	dta b(XB_STD)           ; xSPEED standardowy (z xBIOS-a przy starcie) - powrot z Ultra Speed po bledzie
ld_proba	dta b(0)              ; 1 = ponowienie na predkosci standardowej po bledzie przy Ultra (lfs_slow)
ld_lim	dta a(BANK_WIN+$4000+LDR_SPILL_N) ; granica konca strumienia (okno banku + LDR_SPILL; ldr_load_code: B51 - CART_HDR_RAM)
ldr_build	dta b(0)              ; numer wydania (bity 1-7 flag plikow Bnn.ZX2) - tools/pack_atr.py
ldr_btn	dta b(0)                ; test: <> 0 = "FIRE" w komunikacie (ldr_msg)
atr_kod	dta b(0)                ; 1 = obrazy kodu wgrane (atr_reset: przeladowanie zamiast zimnego startu)
	.endif

	icl 'ldr/zx02.asm'        ; dekompresor (dmsc, MIT) - ZP $82-$89

; --- stan ldr (poza zmiennymi zerowanymi przez machine_init: przechodzi przez boot_score / boot_gameover / boot_title_warm) ---
ld_slot_img	:LDR_NSLOT dta b(0)  ; id obrazu w slocie (0 = pusty / niepewny); kolejnosc slotow jak ldr_slot_pb
ld_r	dta b(0)                ; ldr_need: biezaca rola
ld_id	dta b(0)                ; ldr_load: id ladowanego obrazu
ld_slot	dta b(0)                ;   slot
ld_pb	dta b(0)                ;   PORTB slotu
ld_flags	dta b(0)              ;   flagi z naglowka pliku (b0 = surowe)
ld_src	dta a(0)                ;   strumien w oknie slotu (pozycja w miejscu)
	.if NOSNIK_320
ld_os	dta b(0)                ; M7.3: 1 = OS ROM wlaczony (ldr_init przy starcie) - bit 0 PORTB w ldr_load_pb
ld_nmien	dta b(NMI_VBI)        ; M7.3: NMIEN po kopii z nosnika (ldr_init: 0, gra: NMI_VBI)
ld_ci	dta b(0)                ; M7.3: ldr_init - indeks obrazu stalego
	.endif
	.endif
ldr_end_mark
	.if ldr_end_mark>$A000
	.error "ldr musi lezec ponizej okna cartridge'a $A000 (docs/plan-m7-ldr.md 1.3)"
	.endif
