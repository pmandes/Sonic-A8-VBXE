; =====================================================================
;  boot.asm - M6 krok 1: start gry wydania (RELEASE, build/sonic-a8-vbxe.xex) - kod rezydentny $8000+
;
;  XEX segmentowy (src/game.asm, .ifdef RELEASE): cracktro (src/boot/crack.asm, INIT) -> kod gry -> INIT
;  boot_check (VBXE i 320K, komunikat przez E: OS-u) -> banki wspolne i ekranow -> INIT scr_boot (ekran
;  tytulowy, mapa, wygaszanie - maszyna przejeta i oddana loaderowi) -> banki aktu (GHZ1: 33 atlas, 35 poziom)
;  -> RUN start: poziom. Dane aktu wczytuja sie w czerni po mapie - tam, gdzie oryginal laduje poziom
;  (main@run_this_level: 60 ramek przerwy, load_and_run_level); ziarno RNG ze stalych liczb IRQ.
;  Powrot z poziomu: koniec dema i przycisk w demie - boot_title_warm (ekrany i poziom z pamieci); game over -
;  boot_gameover (ekran game over, potem tak samo); koniec aktu - boot_score (ekran wyniku, mapa, nastepny akt).
;  Zmienne boot_* leza poza vars (start ich nie zeruje) - przechodza z INIT do RUN.
; =====================================================================
boot_cold    dta b(1)      ; 1 = pierwszy start (RAM SMS jak po resecie, K_BOOT przerwan przed tytulem)
boot_done    dta b(0)      ; 1 = ekrany zrobione w INIT (RUN: od razu poziom)
boot_tbtn    dta a(0)      ; test: przycisk przed iteracja N petli tytulu (0 = brak; tools/m6_ekrany_test.py)
boot_mbtn    dta a(0)      ; test: przycisk przed iteracja N petli mapy
scr_irq      dta a(0)      ; licznik przerwan SMS od wlaczenia (= irqs referencji Mesena; ramka scr_render)
boot_seed    dta a(0)      ; ziarno RNG na krok -16 (g_random_seed po K_LLOAD)
boot_demo    dta b(0)      ; 1 = demo (iy_05_lvflag00 bit 1 po ekranach)
	.if NOSNIK_320=0            ; M7.3: nosnik 320K (cart, ATR) nie oddaje maszyny loaderowi - bez kopii strony zerowej (129 B)
boot_portb   dta b(0)      ; PORTB loadera (INIT)
boot_zp      :128 dta b(0) ; strona zerowa $80-$FF loadera / DOS-u
	.endif
boot_ldfr    dta b(0,0,0,0,0) ; pomiar: ramki ladowania ekranu tytulowego, mapy, -, wyniku, game over (scr_load_end, indeks K_*)
boot_part    dta b(1)      ; 1 = ekrany przed pierwszym poziomem, 2 = od konca aktu, 3 = od game over (test: klatki ekranow)
boot_next    dta b(0)      ; M6.2: 1 = start nastepnego aktu (level_next - stan gry zostaje), cfg_point
boot_keepsnd dta b(0)      ; M6.3: 1 = machine_init nie wywoluje snd_init (muzyka smierci gra dalej na ekranie game over)
boot_cont   dta b(0)       ; M6.5: 1 = kontynuacja po game over (boot_continue): nastepny start poziomu z zachowanym stanem gry (level_next)
boot_cbtn   dta a(0)       ; test: przycisk w ramce odliczania ekranu kontynuacji (0 = brak; tools/m6_ekrany_test.py --gameover --cont)
bc_iter     dta a(0)       ; licznik ramek odliczania ekranu kontynuacji
boot_actlevel dta b(0)     ; M6.5: g_level aktu, po ktorym gra weszla w etap specjalny (oryginal: push af przed load_and_run_level, 00:1FFC)

; --- trampoliny do banku 49 (src/scr/ekrany.asm: tablica skokow pod BANK_WIN) ---
scr_call_title                  ; tytul, mapa, wygaszanie
	jsr scr_data_copy         ; M6.11: dane tytulu i mapy 1 z banku 36 do RAM pod OS
	lda #PB_SCR
	sta PORTB
	jsr BANK_WIN
	lda #PB_MAIN
	sta PORTB
	rts
scr_call_wait60                 ; 60 ramek przerwy, rst $20
	lda #PB_SCR
	sta PORTB
	jsr BANK_WIN+3
	lda #PB_MAIN
	sta PORTB
	rts
scr_call_skip                   ; A przerwan bez ramek
	ldx #PB_SCR
	stx PORTB
	jsr BANK_WIN+6
	lda #PB_MAIN
	sta PORTB
	rts
scr_call_score                  ; M6.2: ekran wyniku, mapa nastepnego aktu, wygaszanie
	jsr scr_data_copy
	lda #PB_SCR
	sta PORTB
	jsr BANK_WIN+9
	lda #PB_MAIN
	sta PORTB
	rts
scr_call_gameover               ; M6.3: wygaszenie i ekran game over
	jsr scr_data_copy
	lda #PB_SCR
	sta PORTB
	jsr BANK_WIN+12
	lda #PB_MAIN
	sta PORTB
	rts
scr_call_end                    ; M6.11: ekrany konca gry (ko_seq_end)
	lda #PB_SCR
	sta PORTB
	jsr BANK_WIN+15
	lda #PB_MAIN
	sta PORTB
	rts

; ---------------------------------------------------------------------
; scr_data_copy / ko_copy (M6.11): kopie stronami (copy_pages) z banku 36 do RAM. scr_data_copy - dane tytulu i mapy 1 (wpisy 0-2:
; pary kafli sprite'ow tytulu -> SCR_SPR_T_RAM, RLE tytulu -> SCR_RLE_T_RAM, RLE mapy 1 -> SCR_RLE_M_RAM: RAM pod OS, ktory gra zajmuje w
; poziomie - przed kazdym wejsciem do ekranow); ko_copy - dodatkowo dane ekranow konca (wpisy 3-4: koniec_ram.bin + koniec_spin.bin ->
; KO_RAM = LAYOUT_RAM, koniec_r0.bin -> KO_R0_RAM). Na koniec PB_MAIN.
; ---------------------------------------------------------------------
; M7.3: nosnik 320K (NOSNIK_320) - bank 36 rozpuszczony w bankach stalych (src/game.asm, SCD_* w kernel/mem.inc): bank zrodla z tablicy
; sdc_pb (43 - tytul i mapa 1, 59 - koniec_ram/spin, 41 - koniec_r0), strony zrodla sdc_s z adresow SCD_*; XEX bez zmian (stala PB_SCRC).
ko_copy
	ldy #4
	dta b($2C)                ; bit abs - pomija ldy #2
scr_data_copy
	ldy #2
sdc_l
	.if NOSNIK_320
	lda sdc_pb,y              ; bank staly z danymi wpisu Y
	.else
	lda #PB_SCRC
	.endif
	sta PORTB
	lda sdc_n,y
	sta zp_cnt
	lda sdc_s,y
	ldx sdc_d,y
	jsr copy_pages            ; Y bez zmian
	dey
	bpl sdc_l
	lda #PB_MAIN
	sta PORTB
	rts
sdc_n	dta b(4, 2, 3, 15, 3)                                       ; liczba stron
	.if NOSNIK_320
sdc_s	dta b(>SCD_T, >SCD_RT, >SCD_RM, >SCD_KO, >SCD_R0)
sdc_pb	dta b(PB_SFX, PB_SFX, PB_SFX, PB_BOSS, PB_MUSIC)             ; bank 43, 43, 43, 59, 41
	.else
sdc_s	dta b(>BANK_WIN, >[BANK_WIN+$0400], >[BANK_WIN+$0600], >[BANK_WIN+$1000], >[BANK_WIN+$2000])
	.endif
sdc_d	dta b(>SCR_SPR_T_RAM, >SCR_RLE_T_RAM, >SCR_RLE_M_RAM, >LAYOUT_RAM, >KO_R0_RAM)

; ---------------------------------------------------------------------
; scr_unpack_atlas: A = 0 - tytul (bank 51 $4000), 1 - mapa 1 ($6000), 2 - wynik (bank 53 $4000; M6.2), 3 - mapa 2 (bank 53 $6000; M6.8):
; 8 KiB kafli 4 bpp (starsza polowka =
; lewy piksel) -> atlas 8 bpp w VRAM ATLAS_VRAM ($1A000-$1DFFF, dwa okna MEMAC po 8 KiB). Wolane z banku 49:
; na koniec PORTB = PB_SCR. Samomodyfikujace sie adresy (jak copy_pages).
; ---------------------------------------------------------------------
scr_unpack_atlas
	tax
	lda sua_page,x
	sta sua_rd+2
	lda sua_pb,x
	sta PORTB
	lda #MB_ATLAS0
	sta zp_t0                 ; okno MEMAC
	lda #2
	sta zp_t1                 ; 2 okna
sua_win
	lda zp_t0
	jsr set_memac
	lda #>MEMAC_CPU
	sta sua_w1+2
	sta sua_w2+2
	lda #16                   ; 16 stron zrodla = 32 strony celu (8 KiB okna)
	sta zp_t2
	ldy #0
	ldx #0
sua_l
sua_rd	lda $FF00,y
	sta zp_t3
	lsr
	lsr
	lsr
	lsr
sua_w1	sta $FF00,x
	inx
	lda zp_t3
	and #$0F
sua_w2	sta $FF00,x
	inx
	bne sua_nx
	inc sua_w1+2              ; nastepna strona celu (co 128 bajtow zrodla)
	inc sua_w2+2
sua_nx
	iny
	bne sua_l
	inc sua_rd+2              ; nastepna strona zrodla
	dec zp_t2
	bne sua_l
	inc zp_t0                 ; nastepne okno 8 KiB (MEMAC_BANK w jednostkach 4 KiB)
	inc zp_t0
	dec zp_t1
	bne sua_win
	lda #PB_SCR
	sta PORTB
	rts
sua_page	dta b(>BANK_WIN, >[BANK_WIN+$2000], >BANK_WIN, >[BANK_WIN+$2000]) ; strona zrodla: tytul, mapa 1, wynik, mapa 2
sua_pb	dta b(PB_SCRA, PB_SCRA, PB_SCRB, PB_SCRB)                   ; bank zrodla

; ---------------------------------------------------------------------
; map2_copy (M6.8): dane mapy 2 z banku 43 ($6000, ekr_mapa2.bin) do RAM przed ekranami konca aktu (boot_score): pary kafli sprite'ow
; -> MAP2_SPR (LAYOUT_RAM - uklad poziomu po akcie niepotrzebny), RLE warstw A i B -> MAP2_RLE ($DA00, RAM pod OS - w wydaniu wolne).
; Bank 49 czyta je stamtad (scr/ekrany.asm: scr_run_world_map, mapa 2 dla g_level 9-17). Na koniec PB_MAIN.
; ---------------------------------------------------------------------
MAP2_SPR     = LAYOUT_RAM
MAP2_RLE     = $DA00
map2_copy
	lda #PB_SFX
	sta PORTB
	lda #16                   ; pary kafli sprite'ow (ekr_mapa2.bin od 0, dopelnione do 4 KiB) -> MAP2_SPR
	sta zp_cnt
	lda #>[BANK_WIN+$2000]
	ldx #>MAP2_SPR
	jsr copy_pages
	lda #3                    ; RLE warstw A i B (od $1000, 707 B) -> MAP2_RLE
	sta zp_cnt
	lda #>[BANK_WIN+$3000]
	ldx #>MAP2_RLE
	jsr copy_pages
	lda #PB_MAIN
	sta PORTB
	rts

; ---------------------------------------------------------------------
; scr_unpack_used (M6.2): jak scr_unpack_atlas, ale tylko kafle z bitem w scr_used (SCRV+$F80, RAM pod OS): kafel t
; (32 B 4 bpp pod zrodlo + t * 32) -> ATLAS_VRAM + t * 64 (okno MB_ATLAS0 dla t < 128, MB_ATLAS1). Ekran wyniku
; uzywa ok. 110 z 256 kafli - ladowanie w czasie oryginalu (K_WLOAD). Na koniec PORTB = PB_SCR.
; ---------------------------------------------------------------------
scr_unpack_used
	tax
	lda sua_page,x
	sta zp_t2                 ; strona zrodla kafla 0
	lda sua_pb,x
	sta PORTB
	lda #0
	sta zp_t3                 ; kafel t
suu_l
	lda zp_t3
	lsr
	lsr
	lsr
	tax
	lda zp_t3
	and #7
	tay
	lda scr_used,x
	and bit_tab,y
	beq suu_n
	lda zp_t3                 ; okno: t < 128 -> $1A000, inaczej $1C000
	asl
	lda #MB_ATLAS0
	bcc suu_w
	lda #MB_ATLAS1
suu_w
	jsr set_memac
	lda zp_t3                 ; cel: $2000 + (t & 127) * 64
	and #$7F
	lsr
	lsr
	clc
	adc #>MEMAC_CPU
	sta suu_w1+2
	sta suu_w2+2
	lda zp_t3
	and #3
	lsr
	ror
	ror                       ; (t & 3) << 6
	sta suu_w1+1
	sta suu_w2+1
	lda zp_t3                 ; zrodlo: strona + t >> 3, przesuniecie (t & 7) * 32
	lsr
	lsr
	lsr
	clc
	adc zp_t2
	sta suu_rd+2
	lda zp_t3
	and #7
	asl
	asl
	asl
	asl
	asl
	sta suu_rd+1
	ldy #0
	ldx #0
suu_b
suu_rd	lda $FFFF,y
	pha
	lsr
	lsr
	lsr
	lsr
suu_w1	sta $FFFF,x
	inx
	pla
	and #$0F
suu_w2	sta $FFFF,x
	inx
	iny
	cpy #32
	bne suu_b
suu_n
	inc zp_t3
	bne suu_l
	lda #PB_SCR
	sta PORTB
	rts

	.if NOSNIK_320
; ---------------------------------------------------------------------
; boot_check (M7.3, nosnik 320K - cart / ATR): wolany z start_media po cracktro (OS wlaczony, nic nie wraca do loadera). VBXE FX 1.26+
; i zestaw roboczy 320K: 16 bankow nieparzystych 33-63 (test_banks_n TPAM_N, TPAM_B0, TPAM_ST - RAMBO 320K / 576K / 1088K, U1MB). Brak -
; komunikat przez E: i stop. Wyjscie (sukces): sei, NMIEN = 0 (VBI OS-u stoi - ldr_init przelacza cart, docs/m7-nosniki.md 5.1 TRIG3 /
; GINTLK), PORTB = $FF (OS ROM wlaczony, BASIC wylaczony, RAM glowna pod $4000 - test_banks_n konczy z PB_MAIN = OS off).
; Strona zerowa $80-$FF nie jest odtwarzana (boot_zp wyciete - poza OS-em nikt jej nie czyta: CIO / E: uzywa $00-$7F).
; ---------------------------------------------------------------------
boot_check
	sei
	lda #0
	sta NMIEN
	jsr detect_fx
	bcs bc_fail
	lda #TPAM_N                ; 16 bankow 33-63 co 2 (kernel/mem.inc; asercja TPAM_N <= TB_MAXN)
	ldx #TPAM_B0
	ldy #TPAM_ST
	jsr test_banks_n
	bcs bc_fail
	lda #$FF                  ; OS ROM z powrotem (select_bank / PB_MAIN wylaczaly) - ldr_init laduje banki stale przy OS on
	sta PORTB
	rts
bc_fail
	lda #$FF                  ; OS ROM wlaczony (test bankow mogl go wylaczyc), VBI OS-u, IRQ - E: dziala; cart wylaczony od stubu
	sta PORTB                 ; startowego (GINTLK = TRIG3), wiec VBI OS-u nie zawiesi systemu
	lda #$40
	sta NMIEN
	cli
	ldx #0                    ; E: od nowa: ekran i display lista OS-u (pod RAMTOP = $A0 z carta, $9C20-$9FFF) zostaly nadpisane kodem
	lda #$0C                  ; gry przez stub startowy (DMA bylo wylaczone) - CLOSE i OPEN #0 "E:" buduje je na nowo (nadpisuje kod
	sta ICCOM                 ; $9Cxx - po bledzie juz niepotrzebny; ta procedura i komunikat leza w $Bxxx)
	jsr CIOV
	ldx #0
	lda #$03                  ; OPEN
	sta ICCOM
	lda #<bc_edev
	sta ICBAL
	lda #>bc_edev
	sta ICBAH
	lda #$0C                  ; zapis i odczyt (jak E: OS-u)
	sta ICAX1
	lda #0
	sta ICAX2
	jsr CIOV
	lda #$22                  ; obraz ANTIC (cracktro zostawia SDMCTL = 0)
	sta SDMCTL
	ldx #0                    ; PUT CHARS na IOCB 0 (E:)
	lda #$0B
	sta ICCOM
	lda #<bc_msg
	sta ICBAL
	lda #>bc_msg
	sta ICBAH
	lda #<[bc_msg_end-bc_msg]
	sta ICBLL
	lda #0
	sta ICBLH
	jsr CIOV
bc_stop
	jmp bc_stop
bc_msg	dta $9B,c'SONIC A8 VBXE NEEDS VBXE FX 1.26/1.27',$9B,c'AND 320K RAM (RAMBO 320K+ / U1MB).',$9B
bc_msg_end
bc_edev	dta c'E:',$9B
	.else
; ---------------------------------------------------------------------
; boot_check: INIT za kodem gry, przed bankami (OS wlaczony): VBXE FX 1.26+ i 1088K (U1MB / RAMBO 1088K: 32 banki nieparzyste
; 1-63; M6.6: XEX wymaga 1088K, dane stref w bankach 1-31). Brak - komunikat przez E: i stop. Przerwania wylaczone na czas testu bankow (OS ROM
; wylaczany w select_bank); strona zerowa $80-$FF i PORTB odtworzone.
; ---------------------------------------------------------------------
boot_check
	php
	sei
	jsr boot_save
	lda #0
	sta NMIEN
	jsr detect_fx
	bcs bc_fail
	lda #TPAM_N                ; M7.2: test_banks_n (kernel/hw.asm) - 32 banki nieparzyste 1-63 (dawne test_banks32: bit 1 PORTB = 1, bez
	ldx #TPAM_B0               ; ryzyka BASIC-a na 320K, gdzie banki 1-31 sa aliasami 33-63 - 16 zgodnych); M7.3: TPAM_* z kernel/mem.inc
	ldy #TPAM_ST
	jsr test_banks_n
	bcs bc_fail
	lda #64                   ; review M6.9: wydanie laduje tez banki parzyste 2-28 (SBZ, SKY) - 64 rozlaczne banki. Po 32 nieparzystych
	ldx #0                    ; maszyna to 1088K (bit 1 wybiera bank, BASIC nieruszany przy bicie 4 = 0 - docs/u1mb-pamiec.md), test bezpieczny.
	ldy #1                    ; M7.2: sonic-ram.xex tak samo (RAMCART w bankach 0, 38-62 parzystych)
	.if 64>TB_MAXN
	.error "boot_check: test 64 bankow, a save0 / save1 maja TB_MAXN B"
	.endif
	jsr test_banks_n
	bcs bc_fail
	jsr boot_restore
	lda #$40
	sta NMIEN
	plp
	rts
bc_fail
	jsr boot_restore
	lda #$40
	sta NMIEN
	plp
	lda #$22                  ; obraz ANTIC (cracktro zostawia SDMCTL = 0)
	sta SDMCTL
	ldx #0                    ; PUT CHARS na IOCB 0 (E:)
	lda #$0B
	sta ICCOM
	lda #<bc_msg
	sta ICBAL
	lda #>bc_msg
	sta ICBAH
	lda #<[bc_msg_end-bc_msg]
	sta ICBLL
	lda #0
	sta ICBLH
	jsr CIOV
bc_stop
	jmp bc_stop
bc_msg	dta $9B,c'SONIC A8 VBXE NEEDS VBXE FX 1.26/1.27',$9B,c'AND 1088K RAM (U1MB / RAMBO 1088K).',$9B
bc_msg_end

; (M7.2: test_banks32 zastapiony przez test_banks_n w kernel/hw.asm - wywolania wyzej i w machine_init)

; boot_save / boot_restore: strona zerowa $80-$FF i PORTB loadera
boot_save
	ldx #$7F
bs_l
	lda $80,x
	sta boot_zp,x
	dex
	bpl bs_l
	lda PORTB
	sta boot_portb
	rts
boot_restore
	lda boot_portb
	sta PORTB
	ldx #$7F
br_l
	lda boot_zp,x
	sta $80,x
	dex
	bpl br_l
	rts
	.endif                    ; NOSNIK_320 (M7.3: boot_check nosnika wyzej)

; ---------------------------------------------------------------------
; scr_boot: INIT po bankach wspolnych i ekranow: przejecie maszyny (machine_init, bez stosu), ekran tytulowy
; i mapa aktu do konca wygaszania (bank 49), potem przerwa 60 ramek i load_and_run_level jako stale IRQ
; (dane aktu czyta loader w czerni), ziarno i tryb na start poziomu; oddanie maszyny loaderowi.
; ---------------------------------------------------------------------
scr_boot
	lda CRK_INF               ; trainer (cracktro): nieskonczone zycia - 1 tylko dla wartosci 1
	and #1
	sta v_inflives
	lda CRK_SEL               ; M6.3/M6.11: trainer w cracktro - g_level + 1, poziom od razu (bez tytulu i mapy); 0 = normalny start
	beq sb_screens
	cmp #$25
	bcs sb_screens
	sec
	sbc #1
	pha
	lda CRK_ACT               ; M6.11: etap specjalny - akt przed nim (boot_score_tail: po etapie nastepny akt)
	sta boot_actlevel
	lda CRK_NB                ; M6.11: nastepny etap specjalny z nagrody tabliczki (game_reset: g_next_bonus_level)
	sta v_nbonus
	pla
	sta boot_level            ; g_level startu (0-17 akty, $12 poziom koncowy, $1C-$23 etapy specjalne); ziarno 0, joystick
	lda #0
	sta boot_seed
	sta boot_seed+1
	sta boot_demo
	lda #1
	sta boot_done
	rts
sb_screens
	.if NOSNIK_320
	rts                       ; M7.3: nosnik 320K - tylko trainer; tytul i mapa po machine_init (start -> boot_after_init, boot_done = 0:
	                          ; scr_call_title, boot_after_title - 60 ramek przerwy, K_LLOAD - jak powrot z dema), akt z nosnika w level_boot
	.else
	php
	sei
	jsr boot_save
	jsr machine_init
	jsr scr_call_title
	lda #0
	sta boot_cold
	lda #60                   ; main@force_level_start_delay (00:1CCF) - IRQ bez obrazu
	jsr scr_call_skip
	jsr boot_k_lload          ; load_and_run_level do kroku -16
	jsr boot_seed_save
	lda #1
	sta boot_done
	jsr boot_release
	plp
	rts
	.endif

; boot_k_lload: K_LLOAD (GHZ1) albo K_LLOAD2 (GHZ2, g_level = 1) przerwan (stala regionu z k_tab banku 49: NTSC, K_REG + K PAL)
boot_k_lload
	lda #PB_SCR
	sta PORTB
	ldx #K_LLOAD
	lda #0                    ; M6.8: przerwania ponad stala k_tab (bkl_add)
	sta bkl_ex
	lda g_level               ; M6.3/M6.4: GHZ2 laduje sie o 1 IRQ krocej, GHZ3 o 2; M6.6: BRI1, BRI2 jak GHZ2, BRI3 jak GHZ3
	cmp #18                   ; (irqs_to_level referencji m66-bri*: 549, 549, 548 = GHZ2, GHZ2, GHZ3; m67-jun*: 550, 549, 548 = GHZ1, GHZ2, GHZ3;
	bcs bkl_l2                ; m68-lab*: 549, 551, 548 = GHZ2, GHZ1 + 1, GHZ3 - LAB2 o 1 dluzej niz GHZ1: bkl_add; NTSC: j3end/l1end-ntsc zgodne)
	tay
	lda bkl_add,y             ; M6.9: dodatek PAL; NTSC - osobna tablica (SBZ2: PAL 28 / NTSC 32 - para spoza k_tab)
	ldx v_tv
	bne bkl_pal
	lda bkl_addn,y
bkl_pal
	sta bkl_ex
	ldx bkl_tab,y
	bne bkl_l2                ; zawsze (K_LLOAD..K_LLOAD3 > 0)
bkl_tab	dta b(K_LLOAD, K_LLOAD2, K_LLOAD3, K_LLOAD2, K_LLOAD2, K_LLOAD3, K_LLOAD, K_LLOAD2, K_LLOAD3, K_LLOAD2, K_LLOAD, K_LLOAD3)
	dta b(K_LLOAD2, K_LLOAD2, K_LLOAD)   ; M6.9: SBZ1 jak GHZ2, SBZ2 jak GHZ2 + 1 na PAL, SBZ3 jak GHZ1 (przejscia l3end, s1end, s2end)
	dta b(K_LLOAD2, K_LLOAD3, K_LLOAD)   ; M6.10: SKY1 jak GHZ2, SKY2 jak GHZ3, SKY3 jak GHZ1 - 1 na PAL (s3end, k1end, k2end: 87 / 86 / 87 IRQ;
                                     ; k2end-ntsc zgodny z K_LLOAD)
bkl_add	dta b(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0)   ; M6.8: dodatkowe przerwania ladowania aktu (LAB2: +1; k_tab w pelnym banku 49) - PAL
	dta b(0, 1, 0)
	dta b(0, 0, $FF)          ; M6.10: SKY1-3 (SKY3: PAL -1 wzgledem K_LLOAD)
bkl_addn	dta b(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0)   ; M6.9: to samo dla NTSC (SBZ2 bez dodatku: 32 = K_LLOAD2)
	dta b(0, 0, 0)
	dta b(0, 0, 0)            ; M6.10: SKY1-3
bkl_ex	dta b(0)
bkl_l2
	lda v_tv
	beq bkl_n
	txa
	clc
	adc #K_REG
	tax
bkl_n
	lda k_tab,x
	clc
	adc bkl_ex
	jsr scr_skip_a
	lda #PB_MAIN
	sta PORTB
	rts

; boot_seed_save: ziarno RNG i tryb demo na start poziomu (RAM SMS po ekranach)
boot_seed_save
	lda g_level               ; M6.3: akt wczytywany po ekranach (level_boot: lv_select, game_reset)
	sta boot_level
	lda g_random_seed
	sta boot_seed
	lda g_random_seed+1
	sta boot_seed+1
	lda iy_05_lvflag00
	lsr
	and #1
	sta boot_demo
	rts

	.if NOSNIK_320
	.if MEDIA=MEDIA_CART
; ---------------------------------------------------------------------
; start_media (M7.3; docs/plan-m7-ldr.md 4.9): start gry z nosnika 320K - wejscie ze stubu startowego cartu (src/boot/cartboot.asm,
; $0600) po skopiowaniu kodu: OS wlaczony (PORTB = $FF: BASIC wylaczony, BASICF = 1), sei, NMIEN = 0, cart wylaczony i GINTLK = TRIG3
; (VBI OS-u nie zawiesi systemu). Kolejnosc jak w XEX wydania, bez INIT-ow: cracktro (VBI i klawiatura OS-u) -> trainer (scr_boot:
; CRK_* -> boot_level...; punkt testow bp scr_boot jak w XEX) -> boot_check (VBXE, 16 bankow 33-63; blad - komunikat E: i stop) -> start
; (ldr_init: banki stale z nosnika przy OS on, machine_init, boot_after_init: tytul i mapa albo od razu poziom z trainera; akt z nosnika
; laduje ldr_need w level_boot). Nic nie wraca do OS-u - stad wyciete boot_save / boot_restore / boot_release i ekrany w INIT.
; M7.4: ATR - start_media lezy za cracktro (src/ldr/atr_start.asm: BASIC off, RAMTOP, RESET, cracktro, obrazy kodu z dyskietki), tu
; wspolny dalszy ciag start_media_gl.
; ---------------------------------------------------------------------
start_media
	cld
	ldx #$FF
	txs
	lda #0                    ; CRK_* ($0680-$0683) leza na stubie startowym ($0600-$06E4: jmp (cb_t_run)) - zerowane jak niezaladowana
	sta CRK_SEL               ; strona 6 w XEX-ie: cracktro w normalnym trybie i tak je pisze, ale w trybie testow (crk_auto) zostawia
	sta CRK_INF               ; CRK_INF bez zmian (bajt stubu = nieskonczone zycia - wykryte testem game over na SIC!)
	sta CRK_ACT
	sta CRK_NB
; RESET w fazie startu (OS wlaczony: cracktro, boot_check, ldr_init - cart wylaczony, TRIG3 = GINTLK = 0): OS robi goracy start i szuka
; cartu w RAM pod $A000 (wolne za kodem rezydentnym - asercja w game_code.asm) - $BFFC <> 0: "brak cartu"; potem JSR (DOSINI), bo BOOT
; bit 0 = 1: cart_reset (src/ldr/ldr.asm) wlacza cart z bankiem 0 i skacze do zimnego startu OS-u - gra startuje od nowa z cartu.
	lda #$FF
	sta CART_HDR_RAM          ; RAM $BFFC (pod oknem cartu)
	lda #<cart_reset
	sta DOSINI
	lda #>cart_reset
	sta DOSINI+1
	lda BOOT
	ora #1                    ; "dysk zaladowany" - OS wola DOSINI przy goracym starcie
	sta BOOT
	lda #$40                  ; VBI OS-u (zegar RTCLOK, cienie STRIG0 / STICK0 / kolory) i IRQ klawiatury dla cracktro
	sta NMIEN
	cli                       ; etap 2 VBI OS-u (cienie) dziala tylko przy I = 0 przerwanego kodu
	jsr crk_main              ; cracktro $2000 (stub skopiowal je z cartu): wybor trainera -> CRK_SEL / CRK_INF / CRK_ACT / CRK_NB
	.endif                    ; MEDIA_CART
start_media_gl                  ; M7.4: ATR - wejscie z src/ldr/atr_start.asm (start_media / atr_reset2) po wgraniu obrazow kodu (OS wlaczony,
	                          ; sei, NMIEN = 0); cart - dalszy ciag start_media (te same bajty co w M7.3)
	jsr scr_boot              ; trainer: CRK_* -> v_inflives, boot_level, boot_actlevel, v_nbonus, boot_done (1 = poziom od razu)
	jsr boot_check            ; VBXE + 320K; wraca z sei, NMIEN = 0, PORTB = $FF
	jmp start                 ; game_code.asm: stos, ldr_init (banki stale), machine_init, boot_after_init
	.else
; boot_release: oddanie maszyny loaderowi - NMI gry stop, POKEY cicho, nakladka VBXE i MEMAC wylaczone
; (czern; $2000-$3FFF znow RAM), ANTIC bez obrazu (cienie OS: SDMCTL = 0, COLOR4 = 0), PORTB i strona zerowa
; loadera, IRQ klawiatury (POKMSK), NMI VBI OS-u.
boot_release
	lda #0
	sta NMIEN
	jsr snd_music_stop
	lda #0
	sta AUDCTL
	sta AUDC3
	ldy #VC_VIDEO
	sta (zp_fx),y
	ldy #VC_MEMAC_CTL
	sta (zp_fx),y
	sta SDMCTL
	sta COLOR4
	jsr boot_restore
	lda #3
	sta SKCTL
	lda POKMSK
	sta IRQEN
	lda #$40
	sta NMIEN
	rts
	.endif                    ; NOSNIK_320 (M7.3: start_media zamiast boot_release)

; ---------------------------------------------------------------------
; boot_after_init: start z RUN (po machine_init). Po INIT ekranow - od razu poziom; inaczej (XEX bez INIT
; ekranow, powrot z poziomu) ekrany z pamieci: tytul, mapa, wygaszanie, 60 ramek przerwy, K_LLOAD.
; Na koniec ziarno (v_rng_seed0) i tryb wejscia (demo / joystick) dla game_reset, dalej level_boot.
; ---------------------------------------------------------------------
boot_after_init
	lda boot_done
	bne bai_level
	jsr scr_call_title
boot_after_title                ; M6.3: wejscie po ekranie tytulowym i mapie (game over: scr_seq_gameover robi je sam)
	lda #0
	sta boot_cold
	jsr scr_call_wait60
	jsr boot_k_lload
	jsr boot_seed_save
bai_level
	lda #0
	sta boot_done
	sta v_blank_req           ; flip gry na bufory (nie XDL pustej linii ekranow), paleta gry z level_boot
	sta v_pal_req
	sta v_video_on            ; obraz VBXE wylaczony do pierwszej ramki gry (frame_done), jak po machine_init:
	ldy #VC_VIDEO             ; level_boot wgrywa palete i XDL0 przy ostatnim obrazie ekranu w buforze
	sta (zp_fx),y
	lda #1
	sta v_back
	lda boot_seed
	sta v_rng_seed0
	lda boot_seed+1
	sta v_rng_seed0+1
	lda #IN_JOY
	ldx boot_demo
	beq bai_mode
	lda #IN_DEMO
bai_mode
	sta v_input_mode
	jmp level_boot

; ---------------------------------------------------------------------
; boot_score (M6.2): koniec aktu (EXIT_NEXT) po wygaszeniu w game/trans.asm - przejecie od nowa (stos, machine_init),
; ekran wyniku, mapa nastepnego aktu i wygaszanie (bank 49), 60 ramek przerwy, K_LLOAD; potem zaslepka do kroku
; GHZ2: znowu GHZ1 (g_level = 0, punkt kontrolny GHZ1 skasowany) z zachowanym stanem gry (level_next: zycia,
; wynik, szmaragdy, licznik tickow - jak load_and_run_level po akcie). scr_irq = 0 w ramce wyjscia z poziomu.
; ---------------------------------------------------------------------
boot_score
	ldx #$FF
	txs
	jsr machine_init
	jsr map2_copy             ; M6.8: dane mapy 2 do RAM (uklad poziomu juz niepotrzebny) - mapa nastepnego aktu moze byc mapa 2
	lda #0
	sta boot_cold
	sta boot_done
	sta boot_demo
	sta scr_irq
	sta scr_irq+1
	lda #2
	ldx g_level               ; M6.5: koniec etapu specjalnego ($1C+) = czesc 4 referencji (ekran wyniku etapu, mapa, akt)
	cpx #$1C
	bcc bs_prt
	lda #4
bs_prt
	sta boot_part
	jsr scr_call_score
	lda iy_07_lvflag02        ; M6.5: scr_seq_score zwraca tu przed mapa tylko przy nagrodzie tabliczki (iy_07 b0 = 1, g_level < $1A)
	lsr
	bcs bs_bonus
bs_mapdone                      ; test (tools/m6_ekrany_test.py): stan po wygaszeniu mapy nastepnego aktu
	jsr scr_call_wait60
	lda g_level               ; M6.3-M6.8: GHZ2, GHZ3, BRI1-3, JUN1-3, LAB1-3 (g_level = 1-11) wczytywane naprawde; SBZ1 (12) i dalej - zaslepka: GHZ1
	                          ; (M6.8: mapa 2 przed LAB1-3 i SBZ1 - scr_run_world_map, dane: map2_copy)
	cmp #ZONE_N               ; (punkt kontrolny GHZ1 skasowany; zycia, wynik i szmaragdy zostaja)
	bcc bs_real
	lda #0
	sta g_level
	jsr level_mask
	eor #$FF
	and g_level_has_checkpoint_mask,x
	sta g_level_has_checkpoint_mask,x
bs_real
	jsr boot_k_lload
	lda g_level
	sta boot_level
	lda #1
	sta boot_next
	jmp bai_level

; ---------------------------------------------------------------------
; bs_bonus (M6.5): nagroda tabliczki "etap specjalny" (>= 50 pierscieni) - update_signpost_timer@go_to_next_level 00:1FED:
; po ekranie wyniku aktu palette_fade_up (do bieli, 50 IRQ), g_level aktu zapamietany, g_level = g_next_bonus_level
; (potem + 1), od razu load_and_run_level etapu (bez mapy i 60 ramek przerwy). Stan gry zostaje (level_next).
; ---------------------------------------------------------------------
bs_bonus
	lda g_level
	sta boot_actlevel
	jsr scr_call_white
	lda g_next_bonus_level
	sta g_level
	inc g_next_bonus_level
	jsr boot_k_lload          ; load_and_run_level do kroku -16 (etapy specjalne: stala jak GHZ1)
	lda g_level
	sta boot_level
	lda #1
	sta boot_next
	jmp bai_level

; boot_score_tail (M6.5): koniec scr_seq_score (bank 49 wolany z PB_SCR): po ekranie wyniku. Etap specjalny ($1A+): iy_07 b0
; kasowany, g_level = g_level aktu (boot_actlevel, pop af 00:200A), potem g_level + 1 i mapa nastepnego aktu; nagroda tabliczki
; przy g_level < $1A i iy_07 b0 = 1: powrot do boot_score (bs_bonus). Inaczej g_level + 1 i mapa.
boot_score_tail
	lda g_level
	cmp #$1A
	bcs bst_was
	lda iy_07_lvflag02
	lsr
	bcc bst_next
	rts                       ; nagroda tabliczki: etap specjalny (bs_bonus)
bst_was
	lda iy_07_lvflag02
	and #$FE
	sta iy_07_lvflag02
	lda boot_actlevel
	sta g_level
bst_next
	inc g_level
	jmp sst_mainloop

; scr_call_white (M6.5): palette_fade_up (00:0B60) wyswietlanej palety do bieli - bfw_body w banku 49 (M6.11: przeniesione z kodu
; rezydentnego - miejsce na ekrany konca; wola je tez src/scr/koniec.asm)
scr_call_white
	lda #PB_SCR
	sta PORTB
	jsr bfw_body
	lda #PB_MAIN
	sta PORTB
	rts

; ---------------------------------------------------------------------
; boot_gameover (M6.3): game over (zycia = 0) po wygaszeniu w game/trans.asm - przejecie od nowa (stos,
; machine_init bez snd_init: muzyka smierci gra dalej jak w oryginale, w ktorym nic jej nie zatrzymuje do
; run_title_screen), wygaszanie i ekran game over (bank 49), dalej od razu main@reset_game_state: ekran tytulowy
; i mapa (ta sama procedura banku 49), potem 60 ramek, K_LLOAD i poziom (boot_after_title). scr_irq = 0 w ramce wyjscia z poziomu (referencja: irq_g_gfade).
; ---------------------------------------------------------------------
boot_gameover
	ldx #$FF
	txs
	lda #1
	sta boot_keepsnd
	jsr machine_init
	jsr map2_copy             ; M6.8: kontynuacja w LAB i dalej -> mapa 2 (dane w RAM jak w boot_score)
	lda #0
	sta boot_keepsnd
	sta boot_cold
	sta boot_done
	sta boot_demo
	sta scr_irq
	sta scr_irq+1
	lda #3
	sta boot_part
	jsr scr_call_gameover     ; game over, dalej bez przerwy: tytul, mapa, wygaszanie (main@reset_game_state 00:1C4E)
	lda boot_cont             ; M6.5: kontynuacja - mapa tego samego aktu zrobiona w scr_call_gameover, stan gry zostaje
	beq bgo_new
	lda #0
	sta boot_cont
	lda #1
	sta boot_next
bgo_new
	jmp boot_after_title

; boot_end (M6.11): po poziomie $12 (EXIT_TONEXT, g_level = $13 - game/trans.asm po wygaszeniu): przejecie od nowa (stos, machine_init),
; dane konca do RAM (ko_copy), ekrany konca (bank 49: ko_seq_end - drugie wygaszanie, 60 ramek, obraz konca, dobre zakonczenie przy 6
; szmaragdach, wynik koncowy, napisy, petla koncowa). scr_irq = 0 w ramce wyjscia z poziomu (jak boot_score). Dodatek portu: przycisk
; w petli koncowej - zimny start (RAM SMS jak po resecie, K_BOOT przerwan przed ekranem tytulowym).
; ---------------------------------------------------------------------
boot_end
	ldx #$FF
	txs
	jsr machine_init
	jsr ko_copy
	lda #0
	sta boot_cold
	sta boot_done
	sta boot_demo
	sta scr_irq
	sta scr_irq+1
	lda #5                    ; test (tools/m6_ekrany_test.py): czesc 5 = koniec gry
	sta boot_part
	jsr scr_call_end
	jsr snd_music_stop        ; review M6.11: muzyka napisow nie gra dalej w czasie ladowania tytulu (oryginal po resecie - cisza)
	lda #1                    ; zimny start: tytul jak po wlaczeniu (RAM SMS od nowa), nowa gra od GHZ1 (boot_seed_save: boot_level = g_level
	sta boot_cold             ; po tytule; v_nbonus jednorazowy - game_reset); nieskonczone zycia z trainera zostaja
	sta boot_part             ; test: znowu czesc 1 (ekrany przed pierwszym poziomem)
	jmp boot_after_init

; boot_title_warm: koniec dema, przycisk w demie -> main@reset_game_state (ekran tytulowy) bez
; ladowania z nosnika (game/trans.asm). TODO M6: stala IRQ od konca dema do run_title_screen (referencja).
boot_title_warm
	ldx #$FF
	txs
	jsr machine_init
	lda #0
	sta boot_done
	sta boot_cold
	jmp boot_after_init
