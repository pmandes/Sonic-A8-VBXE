; =====================================================================
;  game.asm - Sonic A8 VBXE: program gry (od M3) wg docs/plan-m3.md
;
;  Punkt wejscia, segmenty INI (banki), petla gry. Moduly:
;   kernel/  przejecie maszyny, VBXE, banki, MEMAC, NMI/VBI, pomiar czasu
;   render/  magazyn blokow, pierscien tla, widok, lista ramki, animowane pierscienie (M3.5), Sonic
;            i sprite'y z grafiki SMS z priorytetem tla (M3.6)
;   game/    logika gry w lustrze RAM SMS ($E000 = SMS $D000): start poziomu, petla poziomu, wejscie,
;            Sonic, ruch i kolizje, kamera, pierscienie, trace w bankach; obraz: kamera gry (M3.4),
;            Sonic z grafiki SMS (M3.6; kulka testowa tylko w trybach kamery testowej M2)
;  Dane poziomu: tools/extract_sms.py (build/assets/<poziom>/, ROM SMS uzytkownika poza repozytorium).
;
;  Budowa:  tools\build.cmd game   (build/game.xex - testy: banki, kod, RUN)
;           tools\build.cmd sonic  (M6 krok 1: build/sonic-a8-vbxe.xex - wydanie, -d:RELEASE: cracktro, kod gry,
;                                   INIT boot_check, banki wspolne i ekranow, INIT scr_boot - ekran tytulowy
;                                   i mapa, banki aktu GHZ1, RUN; 320K RAMBO / U1MB - src/scr/boot.asm)
;  Testy:   python tools\m2_test.py --program game   (renderer: zrzuty VRAM + porownanie z ROM-em)
;           python tools\m3_test.py                  (stan gry vs trace oryginalu z tools\m3_ref.py)
;  Wymagania: jak M2 (U1MB 1088K, VBXE FX 1.26+, loader XEX, bez cartridge'a w $8000-$9FFF).
;  Blad: czerwone tlo GTIA, v_status jak w M1 (1..5).
; =====================================================================
	icl 'atari.inc'
	icl 'level.inc'
	icl 'objdata.inc'         ; M4.0: banki obiektow (tools/extract_sms.py)
	icl 'kernel/vbxe.inc'
	icl 'kernel/mem.inc'
	icl 'render/vram.inc'
	icl 'game/sms.inc'

; =====================================================================
;  Wydanie (RELEASE): cracktro jako pierwszy segment, kod gry (bez zaleznosci od zawartosci bankow), kontrola
;  sprzetu przed ladowaniem bankow (VBXE, 320K)
; =====================================================================
	.ifdef RELEASE
	icl 'boot/crack.asm'      ; cracktro (placeholder) - $2000, INIT
	.if MEDIA=MEDIA_SIO
; M7.4: ATR - kod fazy startu (start_media, ldr_kod, dalszy ciag RESET-u) zaraz za cracktro: ten sam segment pliku XAUTORUN, RAM $2000+
; pod oknem MEMAC A (w grze nietkniety) - nie zajmuje RAM rezydentnej (src/ldr/atr_start.asm)
	org crk_end
	icl 'ldr/atr_start.asm'
	.if atr_start_end>CRK_MB
	.error "ATR: cracktro i atr_start.asm nachodza na bufory muzyki cracktro (CRK_MB)"
	.endif
	.endif
	icl 'game_code.asm'       ; kod gry $8000+ i $4100+
	.if NOSNIK_320=0
	ini boot_check            ; VBXE FX i 16 bankow 320K - inaczej komunikat (src/scr/boot.asm)
	.endif                    ; M7.3: cart / ATR - boot_check wola start_media (bez INIT-ow; XEX buildu cartu = kontener obrazow)
	.endif

; =====================================================================
;  Ladowanie bankow (segmenty INI); OS pozostaje wlaczony
; =====================================================================
	org $0600
ld_save
	lda PORTB
	sta ld_saved
	rts
ld_saved	dta b(PB_DEFAULT)
	ini ld_save

	.ifndef RELEASE
	icl 'lvbanks.inc'         ; banki aktu i stref (M7.1: generuje tools/manifest.py - dawne game_lvbanks.asm)
	.endif

	org $0610
ld_sonic
	lda #PB_LD_SONIC
	sta PORTB
	rts
	ini ld_sonic
	org BANK_WIN
	ins 'bank_sonic.bin'

	org $0610
ld_spr
	lda #PB_LD_SPR
	sta PORTB
	rts
	ini ld_spr
	org BANK_WIN
	ins 'bank_sprites.bin'

	org $0610
ld_music
	lda #PB_LD_MUSIC
	sta PORTB
	rts
	ini ld_music
	org BANK_WIN
	.if NOSNIK_320
	ins 'bank_music.bin',0,SCD_R0-BANK_WIN  ; M7.3: plik ma 16 KB (dane do $3648, dalej zera - tools/pack_cart.py sprawdza); od SCD_R0
	.else                                   ; dane konca z banku 36
	ins 'bank_music.bin'      ; M5: muzyka (tools/pack_music.py, build/assets/music)
	.endif
music_end                       ; M7.3: koniec muzyki (nosnik 320K: od SCD_R0 dane konca z banku 36)

	org $0610
ld_sfx
	lda #PB_LD_SFX
	sta PORTB
	rts
	ini ld_sfx
	org BANK_WIN
	ins 'sfx.bin'             ; M5.4: efekty (tools/pack_sfx.py)
sfx_end
	.if sfx_end > BANK_WIN+$2000
	.error "efekty (sfx.bin) nachodza na dane mapy 2 w banku 43 ($6000, M6.8)"
	.endif

	org $0610
ld_obj
	lda #PB_LD_OBJ
	sta PORTB
	rts
	ini ld_obj
	org BANK_WIN
	ins 'bank_objdata.bin'    ; M4.0: dane obiektow GHZ z banku 1 ROM-u pod adresami SMS (tools/extract_sms.py)
; M4.1: kod obiektow w lukach danych (objdata.inc: OD_GAP*); laduje sie przy wlaczonym banku 45 (stub ld_obj).
; Wola tylko kod banku 45 i rezydentny $8000+ (tools/sprawdz_xex.py sprawdza dane z ROM-u i skoki).
	org OD_GAP0
obj_gap0_start                  ;@BANK45
	icl 'obj/dispatch.asm'
	icl 'obj/common.asm'      ; M4.3: kolizja z Soniciem, wybuch wroga, punkty, animacja klatkowa
	icl 'obj/objs_a.asm'      ; M4.3: Motobug, eksplozja, rozsypane pierscienie
	icl 'obj/objs_b.asm'      ; M4.4: platformy - wahadlo, opadajaca, pozioma
	icl 'obj/objs_c.asm'      ; M4.6a: Crabmeat i kula ognia
	icl 'obj/objs_d.asm'      ; M4.5: monitory, szmaragd
	icl 'obj/objs_e2.asm'     ; M6.4: boss_generic_update_8hp, plomien, spawn_explosion, midtick_irq, art_load_common
obj_gap0_end                    ;@BANK45_END
	.if obj_gap0_end > OD_GAP0_END
	.error "kod obiektow w luce 0 nachodzi na dane z ROM-u"
	.endif

; M6.4: kod GHZ3 w pozostalych lukach danych bank 45 (OD_GAPA2, OD_GAPA0, OD_GAPA1): boss $12 + kamera, kapsula $25,
; zwierzeta $23 / $24 (stale i dane: build/assets/objdata.inc; kod wola tylko bank 45 i rezydentny)
	org OD_GAPA2
obj_e1_start                   ;@BANK45
	icl 'obj/objs_e1.asm'
obj_e1_end                     ;@BANK45_END
	.if obj_e1_end > OD_GAPA2_END
	.error "kod bossa nachodzi na dane z ROM-u (OD_GAPA2)"
	.endif
	org OD_GAPA0
obj_e3_start                   ;@BANK45
	icl 'obj/objs_e3.asm'
obj_e3_end                     ;@BANK45_END
	.if obj_e3_end > OD_GAPA0_END
	.error "kod kapsuly nachodzi na dane z ROM-u (OD_GAPA0)"
	.endif
	org OD_GAPA1
obj_e4_start                   ;@BANK45
	icl 'obj/objs_e4.asm'
obj_e4_end                     ;@BANK45_END
	.if obj_e4_end > OD_GAPA1_END
	.error "kod zwierzat nachodzi na dane z ROM-u (OD_GAPA1)"
	.endif

; M6.6: tablice granic aktywacji (z dispatch.asm) w luce 4
	org OD_GAPA3
obj_tab_start                  ;@BANK45
	icl 'obj/objs_tab.asm'
obj_tab_end                    ;@BANK45_END
	.if obj_tab_end > OD_GAPA3_END
	.error "tablice granic aktywacji nachodza na dane z ROM-u (OD_GAPA3)"
	.endif

; M6.6 Bridge: chopper $26 w luce 16 banku 45 (dane OD_SPAN16: $7DDC-$7E01)
	org OD_GAPA10
obj_g_start                    ;@BANK45
	icl 'obj/objs_g.asm'
obj_g_end                      ;@BANK45_END
	.if obj_g_end > OD_GAPA10_END
	.error "kod chopperow nachodzi na dane z ROM-u (OD_GAPA10)"
	.endif

; M7.2: banki obiektow strefy (11, 2, 30) to obrazy slotu OBJZ / LEVEL2 - na nosniku wypelnia je tylko ldr. sonic-ram.xex (LD_ZONY = 0):
; kod obiektow asemblowany (etykiety: oz_tab, spawn_bubble... - kod rezydentny je wola) bez zapisu do XEX-a (opt o-); obrazy tych bankow
; z tym samym kodem niesie RAMCART - tools/pack_zone.py --ramcart bierze je z build/sonic-ram-src.xex (pierwszy przebieg, LD_ZONY = 1),
; a tools/sprawdz_xex.py sprawdza, ze kod rezydentny obu przebiegow jest identyczny.
	.if LD_ZONY=0
	opt o-
	.endif
; M6.6: bank obiektow strefy (PB_OBJZ, bank 11): dane obiektow banku 2 ROM-u pod adresem SMS - $4000, kod w lukach OZ_GAPA4 i OZ_GAPA21
; M6.8 krok 0: kod Bridge (byl w OZ_GAPA3) i Jungle (byl w OZ_GAPA8) przeniesiony - w tych miejscach leza zakresy danych Labyrinth
; (OZ_SPAN9-22); luki OZ_GAPA3, OZ_GAPA8 i luki za zakresami LAB zostaja na kod obiektow LAB
	org $0610
ld_objz
	lda #PB_LD_OBJZ
	sta PORTB
	rts
	ini ld_objz
	org BANK_WIN
	ins 'bank_objz.bin'       ; tools/extract_sms.py: OBJZ_SPANS
	org OZ_GAPA4
objz_start                     ;@BANKZ
	icl 'obj/objz.asm'
objz_end                       ;@BANKZ_END
	.if objz_end > OZ_GAPA4_END
	.error "kod banku obiektow strefy nachodzi na koniec banku (luka za OZ_SPAN4)"
	.endif
; M6.7: obiekty Jungle ($0C, $11, $27, $28, $29, $2B, $2C); M6.8: w luce za zakresem przycisku $1D (OZ_SPAN21, SMS $A4AB-$B030)
	org OZ_GAPA21
objzj_start                    ;@BANKZ
	icl 'obj/objz_jungle.asm'
objzj_end                      ;@BANKZ_END
; M6.8: obiekty Labyrinth (kod banku 2 ROM-u) w lukach za zakresami danych LAB; reszta luki za Jungle - platforma $45 i gargulec $3F
objzl1_start                   ;@BANKZ
	icl 'obj/objz_lab_platforma.asm'
	icl 'obj/objz_lab_gargulec.asm'
objzl1_end                     ;@BANKZ_END
	.if objzl1_end > OZ_GAPA21_END
	.error "kod obiektow Jungle/LAB nachodzi na dane z ROM-u (luka za OZ_SPAN21)"
	.endif
; boss LAB3 ($49, $2F, $2A) i woda ($40, $41, $42, $20, spawn_bubble) - luka za dymem rakiety (najwieksza)
	org OZ_GAPA20
objzl2_start                   ;@BANKZ
	icl 'obj/objz_lab_boss.asm'
	icl 'obj/objz_lab_woda.asm'
objzl2_end                     ;@BANKZ_END
	.if objzl2_end > OZ_GAPA20_END
	.error "kod obiektow LAB nachodzi na dane z ROM-u (luka za OZ_SPAN20)"
	.endif
; Orbinaut ($35, $36) i Burrobot ($44) - luka za kulami Orbinauta
	org OZ_GAPA22
objzl3_start                   ;@BANKZ
	icl 'obj/objz_lab_orbinaut.asm'
	icl 'obj/objz_lab_burrobot.asm'
objzl3_end                     ;@BANKZ_END
	.if objzl3_end > OZ_GAPA22_END
	.error "kod obiektow LAB nachodzi na dane z ROM-u (luka za OZ_SPAN22)"
	.endif
; wlocznia ($3E) i przycisk ($1D) - luka za tablica spawn_bubble
	org OZ_GAPA17
objzl4_start                   ;@BANKZ
	icl 'obj/objz_lab_wlocznia.asm'
	icl 'obj/objz_lab_przycisk.asm'
objzl4_end                     ;@BANKZ_END
	.if objzl4_end > OZ_GAPA17_END
	.error "kod obiektow LAB nachodzi na dane z ROM-u (luka za OZ_SPAN17)"
	.endif
; kula z kolcami ($3D) i Jaws ($3C) - luka za danymi bossa LAB3
	org OZ_GAPA18
objzl5_start                   ;@BANKZ
	icl 'obj/objz_lab_kula.asm'
	icl 'obj/objz_lab_jaws.asm'
objzl5_end                     ;@BANKZ_END
	.if objzl5_end > OZ_GAPA18_END
	.error "kod obiektow LAB nachodzi na dane z ROM-u (luka za OZ_SPAN18)"
	.endif

; M6.9: drugi bank obiektow strefy (PB_OBJZ2, bank 2 - parzysty, tylko 1088K/U1MB): dane banku 2 ROM-u (OBJZ2_SPANS: Scrap Brain, potem Sky
; Base i etapy $1F-$23) pod adresem SMS - $4000, kod w lukach OZ2_GAP*. oz2_tab pod tym samym adresem co oz_tab banku 11 (OZ_GAPA4 -
; w banku 2 ten adres lezy w luce za scenka SBZ3 OZ2_GAPA13), bo objz_call czyta oz_tab po wlaczeniu banku v_pbobjz
	org $0610
ld_objz2
	lda #PB_LD_OBJZ2
	sta PORTB
	rts
	ini ld_objz2
	org BANK_WIN
	ins 'bank_objz2.bin'      ; tools/extract_sms.py: OBJZ2_SPANS
	org OZ_GAPA4
objz2_start                    ;@BANKZ2
	icl 'obj/objz2.asm'
objz2_end                      ;@BANKZ2_END
	.if oz2_tab <> oz_tab
	.error "oz2_tab (bank 2) musi lezec pod adresem oz_tab (bank 11)"
	.endif
	.if objz2_start < OZ2_GAPA13
	.error "kod banku obiektow strefy 2 zaczyna sie przed luka za OZ2_SPAN13"
	.endif
	.if objz2_end > OZ2_GAPA13_END
	.error "kod banku obiektow strefy 2 nachodzi na dane z ROM-u (luka za OZ2_SPAN13)"
	.endif
; M6.9 kroki 3-4: obiekty Scrap Brain (kod banku 2 ROM-u) w pierwszej luce banku 2 ($4000 - przed danymi SBZ); $599E-$5B74 zostaje na dane
; obiektow etapow specjalnych $21/$4C (M6.11), reszta luk banku na Sky Base (M6.10, docs/plan-m6.md 15.3)
	org OZ2_GAP0
objz2s_start                   ;@BANKZ2
	icl 'obj/objz2_sbz_ogien.asm'
	icl 'obj/objz2_sbz_drzwi.asm'
	icl 'obj/objz2_sbz_przycisk.asm'
	icl 'obj/objz2_sbz_badniki.asm'
	icl 'obj/objz2_sbz_korytarz.asm'
	icl 'obj/objz2_sbz_scenka.asm'
objz2s_end                     ;@BANKZ2_END
	.if objz2s_end > $599E
	.error "kod obiektow SBZ nachodzi na miejsce danych etapow specjalnych ($599E) w banku 2"
	.endif

; M6.10: trzeci bank obiektow strefy (PB_OBJZ3, bank 30 - parzysty, tylko 1088K/U1MB): Sky Base. Dane banku 2 ROM-u (OBJZ3_SPANS: tylko SKY
; i korytarz) pod adresem SMS - $4000, kod SKY w pierwszej luce ($4000 do LUT_corridor_data $5BD9), oz3_tab pod adresem oz_tab (objz_call)
	org $0610
ld_objz3
	lda #PB_LD_OBJZ3
	sta PORTB
	rts
	ini ld_objz3
	org BANK_WIN
	ins 'bank_objz3.bin'      ; tools/extract_sms.py: OBJZ3_SPANS
	org OZ_GAPA4
objz3_start                    ;@BANKZ3
	icl 'obj/objz3.asm'
objz3_end                      ;@BANKZ3_END
	.if oz3_tab <> oz_tab
	.error "oz3_tab (bank 30) musi lezec pod adresem oz_tab (bank 11)"
	.endif
	.if objz3_start < OZ3_GAPA10
	.error "kod banku obiektow strefy 3 zaczyna sie przed luka za OZ3_SPAN10 (dzialo stale)"
	.endif
	.if objz3_end > OZ3_GAPA10_END
	.error "kod banku obiektow strefy 3 nachodzi na dane z ROM-u (luka za OZ3_SPAN10)"
	.endif
	org OZ3_GAP0
objz3s_start                   ;@BANKZ3
	icl 'obj/objz3_sky_dziala.asm'
	icl 'obj/objz3_sky_chmury.asm'
	icl 'obj/objz3_sky_boss.asm'
	icl 'obj/objz3_korytarz.asm'
	icl 'obj/objz3_ss.asm'      ; M6.11: odbijacz $21, flipper $4C (etapy specjalne)
objz3s_end                     ;@BANKZ3_END
	.if objz3s_end > OZ3_GAP0_END
	.error "kod obiektow SKY / etapow nachodzi na dane z ROM-u w banku 30 (dane flippera $599E)"
	.endif
; M6.11: poziom koncowy $12 - kontroler $53, szmaragd $54 (luka za LUT_corridor_data, OZ3_GAPA0)
	org OZ3_GAPA0
objz3k_start                   ;@BANKZ3
	icl 'obj/objz3_koniec.asm'
objz3k_end                     ;@BANKZ3_END
	.if objz3k_end > OZ3_GAPA0_END
	.error "kod konca gry nachodzi na dane z ROM-u w banku 30 (luka za OZ3_SPAN0)"
	.endif
	.if LD_ZONY=0
	opt o+                    ; M7.2: koniec bankow obiektow strefy pomijanych w sonic-ram.xex
	.endif

	org $0610
ld_objart
	lda #PB_LD_OBJART
	sta PORTB
	rts
	ini ld_objart
	org BANK_WIN
	ins 'bank_objart.bin',0,OA_BOSS3+$1000 ; M4.0: ikony monitorow, kafle i paleta tabliczki (8 bpp); M6.6: grafika bossa BRI3 (4 bpp)


	.ifdef RELEASE
; M6 krok 1: bank 49 - kod i dane ekranow przed poziomem (ekran tytulowy, mapa), bank 51 - kafle tla ekranow
	org $0610
ld_scr
	lda #PB_LD_SCR
	sta PORTB
	rts
	ini ld_scr
	icl 'scr/ekrany.asm'      ; org BANK_WIN (tools/extract_ekrany.py: build/assets/ekrany)

	org $0610
ld_scra
	lda #PB_LD_SCRA
	sta PORTB
	rts
	ini ld_scra
	org BANK_WIN
	ins 'bank_ekr_atlasy.bin' ; kafle tla 4 bpp: $4000 tytul, $6000 mapa 1

	org $0610
ld_scrb
	lda #PB_LD_SCRB
	sta PORTB
	rts
	ini ld_scrb
	org BANK_WIN
	ins 'bank_ekr_atlasy2.bin'  ; M6.2: kafle tla ekranu wyniku 4 bpp (ART_09_351F, bank 53 $4000); M6.8: mapa 2 (ART_0C_1801, $6000)

; M6.8: dane mapy 2 (RLE warstw ARTMAP_05_653B / _66AB i pary kafli sprite'ow znacznikow aktow 9-17) w banku 43 pod $2000 (za efektami
; dzwiekowymi sfx.bin < $2000 B) - boot.asm: map2_copy kopiuje je do RAM przed mapa 2
	org $0610
ld_map2
	lda #PB_LD_SFX
	sta PORTB
	rts
	ini ld_map2
	org BANK_WIN+$2000
	ins 'ekr_mapa2.bin'
map2_end                        ; M7.3: koniec danych mapy 2 (nosnik 320K: od SCD_T dane tytulu i mapy 1 z banku 36)

	.if NOSNIK_320
; M7.3: nosnik 320K - bank 36 (parzysty, poza zestawem roboczym 33-63) rozpuszczony w bankach stalych (docs/plan-m7.md 2, "Rewizja mapy";
; adresy SCD_* w kernel/mem.inc, kopie: src/scr/boot.asm scr_data_copy / ko_copy z tablica sdc_pb). Zestaw roboczy zostaje 16/16.
; Bank 43 (efekty + mapa 2): od $3300 dane tytulu i mapy 1 (pary kafli sprite'ow tytulu, RLE tytulu, RLE mapy 1 - 1978 B)
	.if map2_end>SCD_T
	.error "bank 43: brak miejsca na dane banku 36 (map2_end > SCD_T)"
	.endif
; M7.3 (review): muzyka wchodzi przycieta (ins ...,0,SCD_R0-BANK_WIN), wiec music_end zawsze = SCD_R0 - miejsce sprawdza sie na pliku:
; bajty bank_music.bin od SCD_R0 musza byc zerami (tam dane konca z banku 36). .get wczytuje plik do bufora MADS-a (listing wylaczony)
sc_music_dl	= .filesize 'bank_music.bin'
	opt l-
	.get 'bank_music.bin'
	.rept sc_music_dl-[SCD_R0-BANK_WIN]
	.if .get[SCD_R0-BANK_WIN+#]<>0
	.error "bank 41: bank_music.bin ma dane za SCD_R0 - koniec_r0.bin by je nadpisal (przesun SCD_R0 w kernel/mem.inc)"
	.endif
	.endr
	opt l+
	org $0610
ld_sc43
	lda #PB_LD_SFX
	sta PORTB
	rts
	ini ld_sc43
	org SCD_T
	ins 'ekr_spr_tytul.bin'
sc43_t
	org SCD_RT
	ins 'ekr_rle_tytul.bin'
sc43_rt
	org SCD_RM
	ins 'ekr_rle_mapa1a.bin'
	ins 'ekr_rle_mapa1b.bin'
sc43_rm
	.if sc43_t>SCD_RT || sc43_rt>SCD_RM || sc43_rm>SCD_RM+$0300
	.error "bank 43: dane tytulu / mapy 1 przekraczaja strony kopiowane przez scr_data_copy (src/scr/boot.asm)"
	.endif
; Bank 41 (muzyka): od $3700 koniec_r0.bin (721 B, 3 strony -> KO_R0_RAM)
	org $0610
ld_sc41
	lda #PB_LD_MUSIC
	sta PORTB
	rts
	ini ld_sc41
	org SCD_R0
	ins 'koniec_r0.bin'
sc41_r0
	.if sc41_r0>SCD_R0+$0300
	.error "bank 41: koniec_r0.bin przekracza 3 strony ko_copy"
	.endif
	.else
; M6.11: bank 36 - dane tytulu i mapy 1 wyjete z banku 49 (miejsce na kod ekranow konca) i dane ekranow konca; boot.asm (scr_data_copy,
; ko_copy) kopiuje je stronami do RAM: $0000 -> SCR_SPR_T_RAM (4 strony), $0400 -> SCR_RLE_T_RAM (2), $0600 -> SCR_RLE_M_RAM (3),
; $1000 -> KO_RAM = LAYOUT_RAM (15: koniec_ram.bin + koniec_spin.bin), $2000 -> KO_R0_RAM (3)
	org $0610
ld_scrc
	lda #PB_LD_SCRC
	sta PORTB
	rts
	ini ld_scrc
	org BANK_WIN
	ins 'ekr_spr_tytul.bin'
sc36_t
	org BANK_WIN+$0400
	ins 'ekr_rle_tytul.bin'
sc36_rt
	org BANK_WIN+$0600
	ins 'ekr_rle_mapa1a.bin'
	ins 'ekr_rle_mapa1b.bin'
sc36_rm
	org BANK_WIN+$1000
	ins 'koniec_ram.bin'
	ins 'koniec_spin.bin'
sc36_ko
	org BANK_WIN+$2000
	ins 'koniec_r0.bin'
sc36_r0
	.if sc36_t > BANK_WIN+$0400 || sc36_rt > BANK_WIN+$0600 || sc36_rm > BANK_WIN+$0900 || sc36_ko > BANK_WIN+$1F00 || sc36_r0 > BANK_WIN+$2300
	.error "bank 36: dane ekranow przekraczaja strony kopiowane przez scr_data_copy / ko_copy (src/scr/boot.asm)"
	.endif
	.endif                    ; NOSNIK_320 (M7.3)

	org $0610
ld_rest1
	lda ld_saved
	sta PORTB
	rts
	ini ld_rest1
	.if NOSNIK_320=0
	ini scr_boot              ; ekran tytulowy i mapa aktu: maszyna przejeta i oddana loaderowi (src/scr/boot.asm)
	.endif                    ; M7.3: cart / ATR - tytul i mapa po machine_init (start_media -> start -> boot_after_init)
	icl 'lvbanks.inc'         ; dane aktu - wczytywane po mapie (w czerni; M7.1: tools/manifest.py; M7.2: przy LD_ZONY = 0 tylko bank staly 59)
	.if LD_ZONY=0
	icl 'ramcart.inc'         ; M7.2 (sonic-ram.xex): obrazy zx02 slotow w bankach RAMCART 38-62, 0 + katalog (tools/pack_zone.py --ramcart)
	.endif
	.if NOSNIK_320
; M7.3: bank 59 (boss GHZ3, zwierzeta, sprite'y etapow - lvbanks.inc): od $3100 dane ekranow konca z banku 36 (koniec_ram.bin +
; koniec_spin.bin, 3671 B - 15 stron ko_copy -> KO_RAM = LAYOUT_RAM)
; M7.3 (review): bank_boss.bin wchodzi przyciety (lvbanks.inc: ins ...,0,$3100 - nosnik_dl w tools/manifest.py), wiec ld_boss_end zawsze
; = SCD_KO - miejsce sprawdza sie na pliku: bajty od SCD_KO musza byc zerami (listing wylaczony)
	.if ld_boss_end<>SCD_KO
	.error "bank 59: przyciecie bank_boss.bin (nosnik_dl w tools/manifest.py) inne niz SCD_KO"
	.endif
sc_boss_dl	= .filesize 'bank_boss.bin'
	opt l-
	.get 'bank_boss.bin'
	.rept sc_boss_dl-[SCD_KO-BANK_WIN]
	.if .get[SCD_KO-BANK_WIN+#]<>0
	.error "bank 59: bank_boss.bin ma dane za SCD_KO - koniec_ram/spin by je nadpisaly (przesun SCD_KO w kernel/mem.inc)"
	.endif
	.endr
	opt l+
	org $0610
ld_sc59
	lda #PB_LD_BOSS
	sta PORTB
	rts
	ini ld_sc59
	org SCD_KO
	ins 'koniec_ram.bin'
	ins 'koniec_spin.bin'
sc59_ko
	.if sc59_ko>SCD_KO+$0F00
	.error "bank 59: dane konca przekraczaja 15 stron ko_copy"
	.endif
	.endif
	.endif

	org $0610
ld_restore
	lda ld_saved
	sta PORTB
	rts
	ini ld_restore

	.ifndef RELEASE
	icl 'game_code.asm'       ; kod gry za bankami
	.endif

	run start
