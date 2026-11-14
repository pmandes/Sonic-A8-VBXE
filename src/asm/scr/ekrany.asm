; =====================================================================
;  ekrany.asm - M6 krok 1: ekran tytulowy i mapa przed aktem (kod w banku 49 = PB_SCR, pod $4000)
;
;  Przeklad z dezasemblacji (bank 0 ROM-u SMS): main@reset_game_state (00:1C4E) .. main@run_this_level
;  (00:1CBD-00:1CC0), run_title_screen (00:1287), run_world_map (00:0C52, mapa 1 - poziomy 0-8),
;  render_world_map_sprites (00:0E86), palette_fade_in_banks_01_02 (00:0B50), fade_screen_to_black (00:0A40),
;  palette_fade_to_black (00:0A90), print_positioned_FF_string (00:05AF), unpack_art_tilemap_into_vram
;  (00:0501), clear_sprite_table (00:05E2), draw_sprite_string (00:350F), draw_sprite_text (00:35CC),
;  signal_load_palettes (00:0333), load_palettes_IRQ (00:0566), upload_sprite_table_IRQ (00:033E) i czesc
;  przerwania (irq_start 00:0073: @fn_update_screen, random_A, poll_player_1_inputs).
;
;  Model: zmienne gry w lustrze RAM SMS ($E000 = SMS $D000, game/sms.inc) - jak w oryginale; VDP jako model
;  w RAM pod OS (SCRV = PHYS_RAM: scr_nt/scr_at - komorki nazw, scr_sat_* - tablica sprite'ow, scr_cram -
;  paleta, scr_disp - obraz wlaczony). wait_until_irq_ticked = scr_wait: obraz ramki ze stanu VDP po
;  ostatnim IRQ i zapisow komorek w tym odcinku kodu (jak VDP: tablica sprite'ow i paleta wchodza w IRQ,
;  komorki od razu), potem VBI (flip tej ramki) i emulacja IRQ (scr_irqemu). Referencja Mesena: rekord
;  z licznikiem przerwan n = obraz po IRQ n, czyli ramka zbudowana w scr_wait przy scr_irq = n.
;  Ladowanie grafiki (load_art, mapy kafli) port robi od razu; przerwania, ktore oryginal liczy w tym czasie
;  (random_A w kazdym IRQ), sa stalymi z referencji (k_tab: tools/m6_ekrany_ref.py, docs/plan-m6.md), a czas
;  ladowania jest wyrownany do oryginalu (scr_load_end czeka do tylu ramek, ile IRQ).
;
;  Obraz: bufory FB0/FB1 i XDL-e gry; czyste tlo 256x192 w VRAM SCR_CLEAN (z atlasu kafli 8 bpp w ATLAS_VRAM);
;  oba bufory dostaja tlo przy ladowaniu (scr_prefill), potem co ramke lista blittera (SCR_LIST_VRAM) tylko:
;  zmienione komorki -> czyste tlo, w buforze tylnym prostokaty sprite'ow sprzed 2 ramek i zmienione komorki
;  <- czyste tlo, sprite'y 8x16 (stencil, od ostatniego do pierwszego - pierwszy na wierzchu), komorki
;  z priorytetem nad sprite'ami (stencil z czystego tla: kolor tla 0 nie zaslania), lewa kolumna 8 px w kolorze
;  ramki (reg0 bit 5, reg7 = 0: kolor 16). Wylaczony obraz: XDL pustej linii w kolorze ramki (v_blank_req,
;  bufory bez zmian). Paleta 1 nakladki: 0-15 tlo, 16-31 sprite'y - NMI wgrywa ja razem z flipem (v_pal_req,
;  kernel/nmi.asm). Pelna kopia tla co ramke (150 linii blittera) nie miescila sie w ramce NTSC.
;  Pomijane (nieuzywane na tych ekranach): limit 8 sprite'ow w linii, przewijanie, kafle tla z palety
;  sprite'ow (atrybut bit 3), akcje mapy (Robotnik przed poziomami 2, 5, 8 - CODEPTRLUT_initial_map_actions),
;  mapa 2 (poziomy 9-17).
;
;  Kod banku 49 wola tylko kod rezydentny $8000+ (pod $4100 jest wtedy bank). Zmienne SCRV zyja tylko na
;  ekranach (phys_init laduje tam tablice kolizji przy starcie poziomu). W czasie ekranow z INIT XEX-a (loader
;  i DOS pracuja miedzy segmentami) kod nie dotyka $0700-$1FFF ani strony zerowej $00-$7F.
; =====================================================================
	icl 'ekrany.inc'          ; build/assets/ekrany (tools/extract_ekrany.py)

; --- lustro RAM SMS: nazwy spoza game/sms.inc ---
SC_REG1      = $D219+SMS_RAM   ; g_saved_vdp_reg_01 (bit 6 = obraz wlaczony)
SC_CURPAL0   = $D230+SMS_RAM   ; (2) g_current_displayed_palette_0 (adres SMS)
SC_CURPAL1   = $D232+SMS_RAM   ; (2) g_current_displayed_palette_1
SC_TMPPAL    = $D3BC+SMS_RAM   ; 32 B g_temporary_palette_buffer
SC_TMPPAL_S  = $D3BC           ; jw. - adres SMS (signal_load_palettes)
SC_IY0D      = $D20D+SMS_RAM   ; iy_0D
SC_TMP01     = $D20F+SMS_RAM   ; tmp_01
SC_TMP05     = $D213+SMS_RAM   ; tmp_05 (starszy bajt tmp_04)
SC_SAT_S     = $D000           ; g_sprite_table (adres SMS)
SC_HUDBUF_S  = $D2BE           ; g_HUD_FFstr_buf (adres SMS)
SC_CONT      = $D284+SMS_RAM   ; g_continues
SC_SCRREP_HI = $D2AC+SMS_RAM   ; g_screen_tile_replace_x_hi (@fn_update_screen wpisuje $FF)

; --- adresy SMS danych banku 0 (ekr_rom0.bin pod scr_r0; adres portu = adres SMS + SR_OFS) ---
SR_PAL_MAP1  = $0F0E           ; PAL3_world_map_0
SR_PAL_MAP2  = $0F2E           ; M6.8: PAL3_world_map_1 (mapa 2)
SR_ROB_L     = $0E72           ; mapsprite_robotnik_left / _right / _front (M6.4: akcje mapy)
SR_ROB_R     = $0E7A
SR_ROB_F     = $0E82
SR_MAPINFO   = $0F4E           ; LUT_level_map_info (3 B na poziom: slowo level_map_XX_chunks, akcja)
SR_TITLES    = $1209           ; LUT_level_titles (slowa)
SR_PRESS_ON  = $1352           ; sprtext_show_press_button
SR_PRESS_OFF = $1362           ; sprtext_hide_press_button
SR_HAND_LUT  = $1372           ; LUT_title_screen_sonic_hand_anim (slowo mapy sprite'ow, czas)
SR_PAL_TITLE = $13E1           ; PAL3_title_screen
SR_OFS       = scr_r0-EKR_R0_FROM

; --- VRAM ekranow ---
SCR_CLEAN    = RING_VRAM       ; $20000: czyste tlo 256x192, stride 256 (pierscien tla gry - przed poziomem wolny)
SCR_LIST_VRAM = LIST_VRAM      ; $00800: lista ramki (okno MB_LOW)
SCR_LIST_CPU = MEMAC_CPU+SCR_LIST_VRAM
SCR_BORDER   = 16              ; kolor ramki: paleta sprite'ow, kolor reg7 = 0 (TBL_reset_vdp_regs 00:0311)

; --- zmienne ekranow (RAM pod OS) ---
SCRV         = PHYS_RAM
scr_nt       = SCRV+$000       ; 768 B: kafel komorki nazw (32 x 24)
scr_at       = SCRV+$300       ; 768 B: atrybut komorki (starszy bajt wpisu VDP: bit 4 = priorytet)
scr_mark     = SCRV+$600       ; 768 B: 1 = komorka priorytetu juz w liscie tej ramki
scr_sat_y    = SCRV+$900       ; 64 B: model tablicy sprite'ow VDP ($3F00: Y)
scr_sat_x    = SCRV+$940       ; 64 B: X ($3F80 parzyste)
scr_sat_t    = SCRV+$980       ; 64 B: kafel ($3F80 nieparzyste)
scr_cram     = SCRV+$9C0       ; 32 B: CRAM (kolory SMS --BBGGRR)
scr_dlo      = SCRV+$A00       ; 64 B: komorki zmienione od ostatniego obrazu (mlodszy bajt indeksu)
scr_dhi      = SCRV+$A40       ; 64 B: (starszy bajt)
scr_mlo      = SCRV+$A80       ; 64 B: komorki z priorytetem pod sprite'ami w tej ramce
scr_mhi      = SCRV+$AC0
scr_b        = SCRV+$B00       ; 21 B: BCB w budowie (scr_emit)
scr_disp     = SCRV+$B20       ; $40 = obraz wlaczony (VDP reg1 bit 6 z ostatniego @fn_update_screen)
scr_nd       = SCRV+$B21       ; liczba komorek w scr_dlo/hi; $FF = przebudowa calego tla
scr_nm       = SCRV+$B22       ; liczba komorek w scr_mlo/hi
scr_cchg     = SCRV+$B23       ; 1 = CRAM zmieniona od ostatniego obrazu (paleta do NMI)
scr_prio     = SCRV+$B24       ; 1 = ekran ma komorki z priorytetem (mapa)
scr_t0       = SCRV+$B25       ; v_frame na poczatku ladowania (tempo jak oryginal)
scr_titer    = SCRV+$B26       ; (2) iteracja petli tytulu (test: przycisk boot_tbtn)
scr_miter    = SCRV+$B28       ; (2) iteracja petli mapy (boot_mbtn)
scr_phase    = SCRV+$B2A       ; 1 = petla tytulu, 2 = petla mapy, 0 = inne (wymuszony przycisk testu)
scr_bc       = SCRV+$B2B       ; (2) licznik petli mapy (bc 00:0D85)
scr_cnt      = SCRV+$B2D       ; licznik (b)
scr_res      = SCRV+$B2E       ; wynik run_title_screen / run_world_map: 1 = przycisk (scf), 0 = koniec czasu
scr_last     = SCRV+$B2F       ; (2) ostatni BCB listy (bit NEXT kasowany w scr_list_run)
scr_e        = SCRV+$B31       ; rejestr E dekodera map (00:0501) / licznik serii
scr_d        = SCRV+$B32       ; rejestr D (bajt serii)
scr_nvis     = SCRV+$B33       ; liczba wpisow tablicy sprite'ow przed znacznikiem $D0
scr_top      = SCRV+$B34       ; sprite: linia gorna na ekranie
scr_skip     = SCRV+$B35       ;         pominiete linie u gory (zawiniecie Y)
scr_h        = SCRV+$B36       ;         wysokosc
scr_w        = SCRV+$B37       ;         szerokosc
scr_x        = SCRV+$B38       ;         x
scr_c        = SCRV+$B39       ; draw_sprite_text: x (c)
scr_y8       = SCRV+$B3A       ;         y (b)
scr_r        = SCRV+$B3B       ; draw_sprite_string: licznik wierszy
scr_q        = SCRV+$B3C       ; dzielenie / cyfry zyc
scr_kidx     = SCRV+$B3D       ; indeks tablicy stalych regionu (0 NTSC, K_REG = 8 PAL)
scr_i        = SCRV+$B3E       ; indeks wpisu tablicy sprite'ow
scr_fstep    = SCRV+$B3F       ; krok rozjasniania / wygaszania (b)
scr_cell     = SCRV+$B40       ; (2) indeks komorki
scr_c0       = SCRV+$B42       ; prostokat sprite'a w komorkach: kolumny c0..c1, wiersze row0..row1
scr_c1       = SCRV+$B43
scr_row0     = SCRV+$B44
scr_row1     = SCRV+$B45
scr_rr       = SCRV+$B46
scr_cc       = SCRV+$B47
scr_tmpw     = SCRV+$B48       ; (2)
scr_full     = SCRV+$B4A       ; (2) 1 = bufor 0/1 do pelnej kopii czystego tla (start, przepelnienie listy komorek)
scr_rn       = SCRV+$B4C       ; (2) liczba prostokatow sprite'ow narysowanych ostatnio w buforze 0/1
scr_pn       = SCRV+$B4E       ; (2) liczba komorek zmienionych od ostatniego obrazu bufora 0/1
scr_rc       = SCRV+$B50       ; scr_restore: licznik
scr_sflt     = SCRV+$B52       ; scr_load_sprites: 1 = tylko pary z scr_need
scr_bn       = SCRV+$B53       ; scr_bcd_str: licznik bajtow (scr_cnt prowadzi petle czekania wyniku)
scr_ax       = SCRV+$B56       ; (2) M6.4 akcje mapy (Robotnik): x
scr_ay       = SCRV+$B58       ; (2)                              y
scr_ab       = SCRV+$B5A       ;                                  licznik ramek (b)
scr_amap     = SCRV+$B5B       ; (2)                              tabela mapsprite_robotnik_* (adres portu)
scr_aact     = SCRV+$B5D       ;                                  bajt akcji poziomu (scr_need_map)
scr_pts_d    = SCRV+$B5E       ; M6.5: punkty za pierscien przy liczeniu wyniku: bajt setek (D: 1 = 100; etap specjalny: mnoznik)
scr_pts_e    = SCRV+$B5F       ;                                  bajt jednosci (E)
scr_mapi     = SCRV+$B61       ; M6.8: mapa przed aktem: 0 - mapa 1 (poziomy 0-8), 1 - mapa 2 (9-17)
scr_kadj     = SCRV+$B60       ; M6.5: poprawka stalej ladowania (scr_load_end): przerwania mniej (ekran wyniku etapu specjalnego)
scr_need     = SCRV+$F00       ; 128 B: 1 = para kafli sprite'ow (kafel >> 1) potrzebna (mapa)
scr_used     = SCRV+$F80       ; 32 B: bit kafla tla uzytego w komorkach (scr_unpack_used, kod rezydentny)
scr_ri       = SCRV+$B51       ; scr_restore: indeks listy
scr_rx       = SCRV+$C00       ; 2 x 64 B: prostokaty sprite'ow w buforze 0/1 (x, linia, szerokosc-1, wysokosc-1)
scr_ry       = SCRV+$C80
scr_rw       = SCRV+$D00
scr_rh       = SCRV+$D80
scr_plo      = SCRV+$E00       ; 2 x 64 B: komorki zmienione dla bufora 0/1 (indeks: mlodszy / starszy bajt)
scr_phi      = SCRV+$E80

; --- strona zerowa (logika gry stoi na ekranach: rejestry Z80 gry wolne) ---
sz_p         = zg_ptr          ; (2) wskaznik ogolny
sz_s         = zg_src          ; (2) zrodlo (dane RLE, pary kafli, paleta)
sz_d         = zg_dst          ; (2) cel
sz_x         = zg_obj          ; (2) draw_sprite_string: x (hl)
sz_y         = zg_bc           ; (2)                     y (de)
sz_m         = zg_de           ; (2) mapa sprite'ow / napis (adres portu)
sz_n         = zg_hl           ; (2) licznik (bc)

	org BANK_WIN
scr_bank_start
; tablica skokow (kod rezydentny: scr/boot.asm, scr_call_*)
	jmp scr_seq_title         ; +0: main@reset_game_state .. main@run_this_level przed przerwa (tytul, mapa, wygaszanie)
	jmp scr_wait60            ; +3: 60 ramek przerwy (main@force_level_start_delay 00:1CCF) i rst $20
	jmp scr_skip_a            ; +6: A przerwan bez ramek (random_A) - stale ladowania
	jmp scr_seq_score         ; +9: M6.2 koniec aktu: ekran wyniku, mapa nastepnego aktu, wygaszanie
	jmp scr_seq_gameover      ; +12: M6.3 game over (zycia = 0): wygaszenie i ekran game over
	jmp ko_seq_end            ; +15: M6.11 koniec gry: po poziomie $12 ekrany konca, wynik koncowy, napisy (src/scr/koniec.asm)

; stale regionu: przerwania liczone przez oryginal w czasie ladowania (Mesen, tools/m6_ekrany_ref.py)
; [NTSC, PAL] x [K_BOOT, K_TLOAD, K_MLOAD, K_LLOAD, K_WLOAD, K_GLOAD, K_LLOAD2, K_LLOAD3]
;  K_BOOT  - od wlaczenia zasilania do run_title_screen (00:1287)
;  K_TLOAD - load_art x 2 i mapa kafli tytulu (miedzy pierwszym wait a wait iteracji 1)
;  K_MLOAD - ladowanie mapy 1 (miedzy pierwszym wait run_world_map a rozjasnianiem)
;  K_LLOAD - load_and_run_level do kroku -16 (00:1CED-00:1D15): GHZ1 PAL 28 / NTSC 33 (GHZ2: 27 / 32 - przy
;            kroku GHZ2 stala zalezna od poziomu)
;  K_WLOAD - M6.2 ladowanie ekranu wyniku (miedzy wait 00:1572 a wait iteracji 1 00:1685)
;  K_GLOAD - M6.3 ladowanie ekranu game over (miedzy wait 00:140D a wait iteracji 1 00:1453)
k_tab	dta b(2, 23, 28, 33, 20, 17, 32, 31)  ; NTSC
	dta b(1, 19, 23, 28, 17, 14, 27, 26)  ; PAL
K_BOOT  = 0
K_TLOAD = 1
K_MLOAD = 2
K_LLOAD = 3
K_WLOAD = 4
K_GLOAD = 5
K_LLOAD2 = 6                  ; M6.3: load_and_run_level GHZ2 (g_level = 1) do kroku -16 (plan-m6.md: PAL 27 / NTSC 32)
K_LLOAD3 = 7                  ; M6.4: load_and_run_level GHZ3 (g_level = 2): PAL 26 / NTSC 31 (Mesen, m6_ekrany_ref.py --poziom 2)
K_REG   = 8                   ; stalych na region (scr_kidx = 0 NTSC, 8 PAL; boot.asm: boot_k_lload)

; =====================================================================
;  scr_seq_title: main (00:1C4E-00:1CC0) bez ladowania poziomu: stan gry, ekran tytulowy, mapa aktu, przy
;  demie z przyciskiem na mapie od nowa; na koncu fade_screen_to_black i clear_sprite_table (00:1CBD-00:1CC0).
;  Wejscie: boot_cold = 1 - pierwszy start (RAM SMS wyzerowany jak reset_init 00:028B, ziarno 0, K_BOOT
;  przerwan przed tytulem), 0 - powrot z poziomu (koniec dema, game over). Wyjscie: iy_05_lvflag00 bit 1 = demo;
;  dalej kod rezydentny: przerwa 60 ramek (scr_wait60) albo oddanie maszyny loaderowi, K_LLOAD, start poziomu.
; =====================================================================
scr_seq_title
	jsr scr_init
sst_reset                       ; main@reset_game_state (00:1C4E)
	lda #3
	sta g_lives
	lda #5
	sta g_next_life_bonus_10000s_BCD
	lda #$1C
	sta g_next_bonus_level
	lda #0
	sta g_level
	sta g_global_tick_counter ; tylko mlodszy bajt (ld (g_global_tick_counter),a)
	sta SC_IY0D
	ldx #7
sst_c1
	sta g_chaos_emeralds_collected,x ; 8 B od $D27F
	dex
	bpl sst_c1
	ldx #13
sst_c2
	sta iy_00,x               ; iy_00..iy_0D
	dex
	bpl sst_c2
	ldx #3
sst_c3
	sta g_score_BCD,x         ; 4 B od $D2BA
	dex
	bpl sst_c3
	ldx #23
sst_c4
	sta g_level_lives_collected_mask,x ; 24 B od $D305
	dex
	bpl sst_c4
	lda iy_02
	and #$FC                  ; res 0 / res 1, iy_02
	sta iy_02
	jsr scr_clear_sprite_table
	jsr scr_run_title         ; A = 1: przycisk, 0: koniec animacji
	tax
	lda iy_05_lvflag00
	and #$FD                  ; res 1, iy_05_lvflag00 (00:1C95)
	cpx #0
	bne sst_ml
	ora #2                    ; set 1: demo GHZ1 (00:1C9B)
sst_ml
	sta iy_05_lvflag00
sst_mainloop
	lda g_level               ; main@main_loop (00:1C9F): g_level >= $13 -> reset_game_state (koniec gry)
	cmp #$13
	jcs sst_reset
	lda iy_02
	and #$FC
	sta iy_02
	jsr scr_clear_sprite_table
	jsr scr_run_world_map     ; A = 1: przycisk
	tax
	lda iy_05_lvflag00
	and #2
	beq sst_run               ; bez dema -> poziom (00:1CB8)
	cpx #0
	jne sst_reset             ; demo i przycisk na mapie -> reset_game_state (tytul, 00:1CBA)
sst_run                         ; main@run_this_level (00:1CBD)
	jsr scr_fade_to_black
	jmp scr_clear_sprite_table

; ---------------------------------------------------------------------
; scr_wait60: main@force_level_start_delay (00:1CCF): 60 x wait_until_irq_ticked, rst $20 (00:1CDA)
; ---------------------------------------------------------------------
scr_wait60
	lda #60
	sta scr_cnt
sw6_l
	jsr scr_wait0
	dec scr_cnt
	bne sw6_l
	jmp snd_music_stop

; ---------------------------------------------------------------------
; scr_skip_a: A przerwan bez obrazu (oryginal laduje grafike albo poziom): random_A i licznik scr_irq
; (wejscie i dzwiek tych IRQ nie maja skutku). Zachowuje X.
; ---------------------------------------------------------------------
scr_skip_a
	tay
	beq ssa_ret
ssa_l
	jsr random_A
	inc scr_irq
	bne ssa_n
	inc scr_irq+1
ssa_n
	dey
	bne ssa_l
ssa_ret
	rts

; scr_skip_k: X = indeks stalej (K_*) -> scr_skip_a
scr_skip_k
	txa
	clc
	adc scr_kidx
	tax
	lda k_tab,x
	jmp scr_skip_a

; =====================================================================
;  scr_init: wejscie w ekrany - model VDP, XDL-e gry, oba bufory w kolorze ramki, paleta czarna, obraz VBXE
;  wlaczony; przy pierwszym starcie RAM SMS wyzerowany i K_BOOT przerwan (reset_init 00:028B, main 00:1C49).
; =====================================================================
scr_init
	lda #0
	sta v_cyc_on              ; cykl palety wody gry stoi (NMI)
	sta scr_kadj              ; M6.5: bez poprawki stalych ladowania (ustawia ja bs_rle_w dla ekranu wyniku etapu specjalnego)
	sta v_flip_req
	sta v_pal_req
	sta scr_nd
	sta scr_nm
	sta scr_prio
	sta scr_phase
	sta scr_disp
	sta scr_sflt
	ldx #K_REG                ; stale regionu: v_tv = 1 -> PAL
	lda v_tv
	bne si_pal
	ldx #0
si_pal
	stx scr_kidx
	ldx #0
	txa
si_m
	sta scr_mark,x            ; komorki priorytetu nieoznaczone
	sta scr_mark+$100,x
	sta scr_mark+$200,x
	inx
	bne si_m
	ldx #63                   ; model tablicy sprite'ow: Y = $E0 (reset_init 00:02C2: $3F00-$3F3F)
si_sat
	lda #$E0
	sta scr_sat_y,x
	lda #0
	sta scr_sat_x,x
	sta scr_sat_t,x
	dex
	bpl si_sat
	ldx #31
	lda #0
si_cr
	sta scr_cram,x            ; CRAM czarna
	dex
	bpl si_cr
	lda #1
	sta scr_cchg
	lda boot_cold
	beq si_warm
	mwa #MIRROR_RAM sz_p      ; reset_init (00:029F): RAM SMS $C000-$DFEF = 0 (lustro $E000-$EFEF; uklad
	ldx #16                   ; $C000-$CFFF port trzyma w LAYOUT_RAM - laduje go start poziomu)
	lda #0
	tay
si_z
	sta (sz_p),y
	iny
	bne si_z
	inc sz_p+1
	dex
	bne si_z
	lda #$A2                  ; TBL_reset_vdp_regs (00:0311): reg1 = $A2 (obraz wylaczony, sprite'y 8x16)
	sta SC_REG1
	lda #0
	sta scr_irq
	sta scr_irq+1
	ldx #K_BOOT               ; przerwania od wlaczenia do run_title_screen
	jsr scr_skip_k
si_warm
	; XDL-e gry (render/tables.asm) i XDL pustej linii (obraz VDP wylaczony: linia BLANKL w kolorze ramki,
	; krok 0) - na start wyswietlany XDLB; rysowanie do bufora 1 (v_back), oba bufory do wypelnienia tlem
	lda #MB_LOW
	jsr set_memac
	mwa #xdl0 zp_src
	mwa #MEMAC_CPU+XDL0_VRAM zp_dst
	ldy #xdl0_end-xdl0
	jsr copy_n
	mwa #xdl1 zp_src
	mwa #MEMAC_CPU+XDL1_VRAM zp_dst
	ldy #xdl1_end-xdl1
	jsr copy_n
	mwa #scr_xdlb zp_src
	mwa #MEMAC_CPU+XDLB_VRAM zp_dst
	ldy #scr_xdlb_end-scr_xdlb
	jsr copy_n
	ldx #0
	lda #SCR_BORDER
si_bl
	sta MEMAC_CPU+BLANKL_VRAM,x
	inx
	bne si_bl
	lda #1
	sta v_back
	sta v_blank_req           ; ramki do pierwszego obrazu: XDLB
	sta scr_full
	sta scr_full+1
	lda #0
	sta scr_rn
	sta scr_rn+1
	sta scr_pn
	sta scr_pn+1
	lda #XDLB_VRAM&$FF
	ldy #VC_XDL_ADR0
	sta (zp_fx),y
	lda #0
	iny
	sta (zp_fx),y
	iny
	sta (zp_fx),y
	jsr scr_pal_rgb           ; paleta (czarna) od razu, bez flipu
	lda #0
	sta v_pal_req
	jsr scr_pal_now
	lda #VIDEO_ON
	ldy #VC_VIDEO
	sta (zp_fx),y
	sta v_video_on
	rts

; XDL ekranu z wylaczonym obrazem: jak XDL gry (tables.asm), ale 192 linie z jednej linii BLANKL_VRAM (krok 0)
scr_xdlb
	dta a($0024),b(23)
	dta a($0872),b(191)
	dta a(BLANKL_VRAM&$FFFF),b(BLANKL_VRAM>>16),a(0)
	dta b($10),b($FF)
	dta a($8024),b(23)
scr_xdlb_end

; =====================================================================
;  run_title_screen (00:1287). Wyjscie: A = 1 - przycisk (scf), 0 - koniec animacji dloni (demo).
; =====================================================================
scr_run_title
	lda #0
	sta scr_phase
	sta scr_titer
	sta scr_titer+1
	lda SC_REG1
	and #$BF                  ; obraz wylaczony (00:128A)
	sta SC_REG1
	jsr scr_wait0
	; load_art ART_09_2000 -> VRAM $0000, ART_09_4B0A -> $2000; unpack_art_tilemap_into_vram ARTMAP_05_6000
	; (bc = $012E, tmp_00 = 0) -> $3800. Port: atlas 8 bpp, kafle sprite'ow, komorki, czyste tlo.
	jsr scr_load_begin
	lda #0
	jsr scr_unpack_atlas      ; bank 51 $4000 -> ATLAS_VRAM (kod rezydentny)
	mwa #scr_spr_t sz_s
	lda #EKR_SPR_T_N
	jsr scr_load_sprites
	mwa #scr_rle_t sz_s
	mwa #EKR_RLE_T sz_n
	lda #0
	sta tmp_00
	jsr scr_unpack_tilemap
	lda #0
	sta scr_prio
	jsr scr_build_bg
	jsr scr_prefill           ; oba bufory z tlem tytulu (pokazany XDL pustej linii)
	ldx #K_TLOAD
	jsr scr_load_end
	lda #0
	sta g_vdp_scroll_x
	sta g_vdp_scroll_y
	lda #3                    ; signal_load_palettes (00:0333): PAL3_title_screen, tlo i sprite'y
	ldx #<SR_PAL_TITLE
	ldy #>SR_PAL_TITLE
	jsr scr_signal_pal
	lda iy_00
	ora #2                    ; set 1, iy_00: tablica sprite'ow w IRQ
	sta iy_00
	lda #$06                  ; rst $18: muzyka tytulu
	jsr play_music
	lda #0
	sta tmp_08
	lda #1
	sta SC_TMP01
	mwa #SR_HAND_LUT tmp_02
	lda #1
	sta scr_phase             ; test: przycisk w petli tytulu
srt_loop                        ; @mainloop (00:12EA)
	lda SC_REG1
	ora #$40
	sta SC_REG1
	jsr scr_wait0
	inc scr_titer             ; iteracja (00:12F9)
	bne srt_i
	inc scr_titer+1
srt_i
	ldx tmp_08                ; licznik napisu 0..99
	inx
	cpx #$64
	bcc srt_w
	ldx #0
srt_w
	stx tmp_08
	cpx #$40                  ; < $40: napis PRESS BUTTON
	bcs srt_hide
	mwa #SR_PRESS_ON+SR_OFS sz_m
	jmp srt_pr
srt_hide
	mwa #SR_PRESS_OFF+SR_OFS sz_m
srt_pr
	lda #0
	sta tmp_00
	jsr scr_print_ff
	dec SC_TMP01              ; czas klatki dloni
	bne srt_draw
	lda tmp_02                ; nastepny wpis LUT: slowo mapy, bajt czasu (0 = koniec)
	clc
	adc #<SR_OFS
	sta sz_p
	lda tmp_02+1
	adc #>SR_OFS
	sta sz_p+1
	ldy #2
	lda (sz_p),y
	beq srt_end               ; and a / jr z, @stop_music_and_return (C = 0)
	sta SC_TMP01
	dey
	lda (sz_p),y
	sta tmp_04+1
	dey
	lda (sz_p),y
	sta tmp_04
	clc
	lda tmp_02
	adc #3
	sta tmp_02
	bcc srt_draw
	inc tmp_02+1
srt_draw                        ; @next_sonic_hand_animation_frame
	lda #<SC_SAT_S
	sta g_next_avail_vdp_sprite_ptr
	lda #>SC_SAT_S
	sta g_next_avail_vdp_sprite_ptr+1
	mwa #$0080 sz_x           ; draw_sprite_string: hl = x $80, de = y $18, bc = (tmp_04)
	mwa #$0018 sz_y
	lda tmp_04
	clc
	adc #<SR_OFS
	sta sz_m
	lda tmp_04+1
	adc #>SR_OFS
	sta sz_m+1
	jsr scr_dss
	lda g_inputs_player_1
	and #$20                  ; bit 5 = 0: przycisk 1 albo 2
	jne srt_loop
	lda #0
	sta scr_phase
	jsr snd_music_stop        ; rst $20
	lda #1                    ; scf
	rts
srt_end
	lda #0
	sta scr_phase
	jsr snd_music_stop
	lda #0
	rts

; =====================================================================
;  run_world_map (00:0C52) - mapa 1 (g_level 0-8), M6.8: mapa 2 (9-17, @load_second_map 00:0CDC: ART_0C_1801, ART_09_5942,
;  ARTMAP_05_653B / _66AB, PAL3_world_map_1 - dane w RAM: boot.asm map2_copy). Wyjscie: A = 1 - przycisk (scf), 0 - koniec czasu.
;  tmp_08 = $FF na wejsciu: grafika i rozjasnianie zawsze od nowa (galaz @map_already_loaded nieosiagalna).
; =====================================================================
scr_run_world_map
	lda #0
	sta scr_phase
	sta g_vdp_scroll_x
	sta g_vdp_scroll_y
	lda #$FF
	sta tmp_08
	lda g_level
	cmp #$12
	bcc srm_go
	lda #0                    ; ret nc: bez mapy (etapy specjalne, koniec gry)
	rts
srm_go
	ldx #0                    ; mapa 1 (poziomy < 9, tmp_08 = 1), M6.8: mapa 2 (9-17, tmp_08 = 2: @load_second_map 00:0CDC)
	cmp #9
	bcc srm_m1
	inx
srm_m1
	stx scr_mapi
	inx
	stx tmp_08
	lda SC_REG1
	and #$BF
	sta SC_REG1
	jsr scr_wait0
	; mapa 1: load_art ART_0C_0000 -> $0000, ART_09_526B -> $2000, ART_09_B92E -> $3000; mapy ARTMAP_05_627E (atrybut $10)
	; i ARTMAP_05_63F6 (atrybut $00); mapa 2: ART_0C_1801, ART_09_5942, ART_09_B92E, ARTMAP_05_653B / _66AB (tablice srm_*)
	jsr scr_load_begin
	ldx scr_mapi
	lda srm_atl,x
	jsr scr_unpack_atlas      ; mapa 1: bank 51 $6000, mapa 2: bank 53 $6000 -> ATLAS_VRAM
	jsr scr_need_map          ; tylko znacznik biezacego aktu i cyfry
	lda #1
	sta scr_sflt
	ldx scr_mapi
	lda srm_spl,x
	sta sz_s
	lda srm_sph,x
	sta sz_s+1
	lda srm_spn,x
	jsr scr_load_sprites
	lda #0
	sta scr_sflt
	ldx scr_mapi
	lda srm_ral,x
	sta sz_s
	lda srm_rah,x
	sta sz_s+1
	lda srm_ranl,x
	sta sz_n
	lda srm_ranh,x
	sta sz_n+1
	lda #$10
	sta tmp_00
	jsr scr_unpack_tilemap
	ldx scr_mapi
	lda srm_rbl,x
	sta sz_s
	lda srm_rbh,x
	sta sz_s+1
	lda srm_rbnl,x
	sta sz_n
	lda srm_rbnh,x
	sta sz_n+1
	lda #$00
	sta tmp_00
	jsr scr_unpack_tilemap
	lda #1
	sta scr_prio
	jsr scr_build_bg
	jsr scr_prefill
	ldx #K_MLOAD              ; M6.8: mapa 2 - ta sama stala co mapa 1 (j3end-pal i j3end-ntsc zgodne z Mesenem)
	jsr scr_load_end
	ldx scr_mapi              ; palette_fade_in_banks_01_02 (00:0B50): PAL3_world_map_0 / _1
	lda srm_pal,x
	ldy srm_palh,x
	tax
	jsr scr_fade_in
	lda #$07                  ; @play_map_jingle: rst $18 muzyka mapy
	jsr play_music
	jsr scr_render_map_sprites ; @map_already_loaded (00:0D3F)
	lda g_level               ; napis strefy: LUT_level_titles[g_level], tmp_00 = $10 (priorytet)
	asl
	clc
	adc #<[SR_TITLES+SR_OFS]
	sta sz_p
	lda #>[SR_TITLES+SR_OFS]
	adc #0
	sta sz_p+1
	ldy #0
	lda (sz_p),y
	clc
	adc #<SR_OFS
	sta sz_m
	iny
	lda (sz_p),y
	adc #>SR_OFS
	sta sz_m+1
	lda #$10
	sta tmp_00
	jsr scr_print_ff
	lda g_level               ; LUT_level_map_info[g_level]: tmp_02 = level_map_XX_chunks
	sta scr_q
	asl
	clc
	adc scr_q                 ; * 3
	clc
	adc #<[SR_MAPINFO+SR_OFS]
	sta sz_p
	lda #>[SR_MAPINFO+SR_OFS]
	adc #0
	sta sz_p+1
	ldy #0
	lda (sz_p),y
	sta tmp_02
	iny
	lda (sz_p),y
	sta tmp_02+1
	iny
	lda (sz_p),y              ; bajt akcji (Robotnik przed poziomami 2, 5, 8: CODEPTRLUT_initial_map_actions), 0 - brak
	beq srm_ret_act
	jmp scr_map_action        ; M6.4
srm_ret_act                     ; @return_from_map_action (00:0D80)
	lda #1
	sta tmp_00
	mwa #$012C scr_bc         ; 300 ramek
	lda #0
	sta scr_miter
	sta scr_miter+1
	lda #2
	sta scr_phase             ; test: przycisk w petli mapy
srm_loop                        ; @loop_waiting_for_final_button_1_2_press
	jsr scr_render_map_sprites
	inc scr_miter             ; iteracja (00:0D8C)
	bne srm_i
	inc scr_miter+1
srm_i
	dec tmp_00
	bne srm_draw              ; @overlay_sprite_timer_not_expired_yet
	lda tmp_02                ; @find_overlay_sprite_to_draw: wpis (slowo mapy, x, y, czas); czas 0 = skok
	sta sz_p
	lda tmp_02+1
	sta sz_p+1
srm_find
	clc
	lda sz_p
	adc #<SR_OFS
	sta sz_d
	lda sz_p+1
	adc #>SR_OFS
	sta sz_d+1
	ldy #4
	lda (sz_d),y
	bne srm_found
	ldy #0                    ; ex de,hl: skok pod adres ze slowa
	lda (sz_d),y
	sta sz_p
	iny
	lda (sz_d),y
	sta sz_p+1
	jmp srm_find
srm_found
	sta tmp_00                ; czas
	ldy #0
	lda (sz_d),y
	sta tmp_04                ; mapa sprite'ow (de)
	iny
	lda (sz_d),y
	sta tmp_04+1
	iny
	lda (sz_d),y
	sta tmp_06                ; tmp_06 = bc: x (c), y (b)
	iny
	lda (sz_d),y
	sta tmp_06+1
	clc
	lda sz_p
	adc #5
	sta tmp_02
	lda sz_p+1
	adc #0
	sta tmp_02+1
srm_draw
	lda tmp_06                ; push tmp_06; draw_sprite_string (hl = x, de = y); pop -> tmp_06
	sta scr_tmpw
	sta sz_x
	lda tmp_06+1
	sta scr_tmpw+1
	sta sz_y
	lda #0
	sta sz_x+1
	sta sz_y+1
	lda tmp_04
	clc
	adc #<SR_OFS
	sta sz_m
	lda tmp_04+1
	adc #>SR_OFS
	sta sz_m+1
	jsr scr_dss
	lda scr_tmpw
	sta tmp_06
	lda scr_tmpw+1
	sta tmp_06+1
	lda scr_bc                ; dec bc; ret z
	bne srm_bc
	dec scr_bc+1
srm_bc
	dec scr_bc
	lda scr_bc
	ora scr_bc+1
	beq srm_timeout
	lda g_inputs_player_1
	and #$20
	jne srm_loop
	lda #0
	sta scr_phase
	lda #1                    ; scf
	rts
srm_timeout
	lda #0
	sta scr_phase
	rts

; ---------------------------------------------------------------------
; M6.4: akcje mapy (run_world_map 00:0D71-00:0D7F, CODEPTRLUT_initial_map_actions 00:1201: 1, 2, 3, 1): przed poziomami
; 2, 5 i 8 (bajt akcji w LUT_level_map_info) Robotnik leci po mapie - w kazdej ramce render_world_map_sprites, przerwanie
; przy dowolnym wejsciu (g_inputs_player_1 != $FF -> @return_from_map_action), draw_current_world_map_sprite (animacja
; mapsprite_robotnik_*), potem zwykla petla mapy (srm_ret_act). Wejscie: A = bajt akcji.
; ---------------------------------------------------------------------
scr_map_action
	sec
	sbc #1
	asl
	tax
	lda sma_tab,x
	sta sz_p
	lda sma_tab+1,x
	sta sz_p+1
	jmp (sz_p)
sma_tab	dta a(sma_01, sma_02, sma_03, sma_01)

sma_01                          ; @map_action_01 (00:0DD9): w lewo ze 256 ramek od x = $DC, y = $3C; potem w prawo 128 ramek
	jsr sma_zero
	lda #$DC
	sta scr_ax
	lda #$3C
	sta scr_ay
	lda #0
	sta scr_ax+1
	sta scr_ay+1
	sta scr_ab                ; b = 0: 256 iteracji
	mwa #SR_ROB_L+SR_OFS scr_amap
sma1_l1
	jsr sma_step
	jne srm_ret_act
	lda scr_ax                ; dec hl
	bne sma1_x
	dec scr_ax+1
sma1_x
	dec scr_ax
	dec scr_ab
	bne sma1_l1
	jsr sma_zero
	lda #$D8                  ; x = $FFD8, y = $0058, b = $80
	sta scr_ax
	lda #$FF
	sta scr_ax+1
	lda #$58
	sta scr_ay
	lda #0
	sta scr_ay+1
	lda #$80
	sta scr_ab
	mwa #SR_ROB_R+SR_OFS scr_amap
sma1_l2
	jsr sma_step
	jne srm_ret_act
	inc scr_ax                ; inc hl
	bne sma1_i
	inc scr_ax+1
sma1_i
	dec scr_ab
	bne sma1_l2
	jmp srm_ret_act

sma_02                          ; @map_action_02 (00:0E24): w gore do miejsca od y = $C0 (x = $80), 120 ramek
	jsr sma_zero
	lda #$80
	sta scr_ax
	lda #$C0
	sta scr_ay
	lda #0
	sta scr_ax+1
	sta scr_ay+1
	lda #$78
	sta scr_ab
	mwa #SR_ROB_F+SR_OFS scr_amap
sma2_l
	jsr sma_step
	jne srm_ret_act
	lda scr_ay                ; dec de
	bne sma2_y
	dec scr_ay+1
sma2_y
	dec scr_ay
	dec scr_ab
	bne sma2_l
	jmp srm_ret_act

sma_03                          ; @map_action_03 (00:0E4B): w dol na miejsce od y = 0 (x = $78), 48 ramek
	jsr sma_zero
	lda #$78
	sta scr_ax
	lda #0
	sta scr_ax+1
	sta scr_ay
	sta scr_ay+1
	lda #$30
	sta scr_ab
	mwa #SR_ROB_F+SR_OFS scr_amap
sma3_l
	jsr sma_step
	jne srm_ret_act
	inc scr_ay                ; inc de
	bne sma3_y
	inc scr_ay+1
sma3_y
	dec scr_ab
	bne sma3_l
	jmp srm_ret_act

sma_zero                        ; ld hl,0 / ld (tmp_00),hl: tmp_00 = tmp_01 = 0
	lda #0
	sta tmp_00
	sta tmp_00+1
	rts

; sma_step: render_world_map_sprites, odczyt wejscia, rysowanie Robotnika; wyjscie: Z = 1 - dalej, Z = 0 - wejscie != $FF
; (zachowane B = scr_ab przez push bc / pop bc - w porcie licznik w zmiennej)
sma_step
	jsr scr_render_map_sprites
	lda g_inputs_player_1
	cmp #$FF
	bne sms_ret
	jsr scr_dcms
	lda #0                    ; Z = 1
sms_ret
	rts

; scr_dcms: draw_current_world_map_sprite (00:0EDD): scr_amap = tabela wpisow 4 B (slowo mapy, czas, nastepny numer),
; wpis nr (tmp_01); czas wpisu <= tmp_00 -> tmp_01 = nastepny, tmp_00 = 0 (rysowana jeszcze stara mapa); draw_sprite_string
; (x = scr_ax, y = scr_ay); tmp_00 + 1.
scr_dcms
	lda tmp_00+1
	asl
	asl
	clc
	adc scr_amap
	sta sz_p
	lda scr_amap+1
	adc #0
	sta sz_p+1
	ldy #0
	lda (sz_p),y
	clc
	adc #<SR_OFS              ; adres mapy (SMS) -> port
	sta sz_m
	iny
	lda (sz_p),y
	adc #>SR_OFS
	sta sz_m+1
	iny
	lda tmp_00
	cmp (sz_p),y
	bcc dcm_draw              ; czas jeszcze nie minal
	iny
	lda (sz_p),y
	sta tmp_00+1
	lda #0
	sta tmp_00
dcm_draw
	lda scr_ax
	sta sz_x
	lda scr_ax+1
	sta sz_x+1
	lda scr_ay
	sta sz_y
	lda scr_ay+1
	sta sz_y+1
	jsr scr_dss
	inc tmp_00
	rts

; ---------------------------------------------------------------------
; render_world_map_sprites (00:0E86): wait_until_irq_ticked, g_sprite_count = 0, zycia: dwie cyfry
; (draw_sprite_text, kafel $80 + 2 * cyfra) w (40, 167); g_next_avail_vdp_sprite_ptr za nimi. tmp_00 zachowane.
; ---------------------------------------------------------------------
scr_render_map_sprites
	lda tmp_00
	pha
	lda tmp_00+1
	pha
	jsr scr_wait0
	lda #0
	sta g_sprite_count
	lda g_lives               ; UNK_0060F (dzielenie przez 10), mul_hl_by_c, reszta
	ldx #0
srs_div
	cmp #10
	bcc srs_dd
	sbc #10
	inx
	bne srs_div
srs_dd
	sta scr_q                 ; reszta
	txa
	asl
	clc
	adc #$80
	sta g_HUD_FFstr_buf
	lda scr_q
	asl
	clc
	adc #$80
	sta g_HUD_FFstr_buf+1
	lda #$FF
	sta g_HUD_FFstr_buf+2
	lda #$A7                  ; b = y
	sta scr_y8
	lda #$28                  ; c = x
	sta scr_c
	mwa #g_HUD_FFstr_buf sz_m
	ldx #0                    ; hl = g_sprite_table
	jsr scr_dst
	stx g_next_avail_vdp_sprite_ptr
	lda #>SC_SAT_S
	sta g_next_avail_vdp_sprite_ptr+1
	pla
	sta tmp_00+1
	pla
	sta tmp_00
	rts

; =====================================================================
;  M6.2: koniec aktu - update_signpost_timer@go_to_next_level (00:1FC4-00:2014) od 00:1FC7 (wygaszanie zrobil
;  port: game/trans.asm) i main (00:1CE2 -> @main_loop 00:1C9F): ekran wyniku, g_level + 1, mapa nastepnego aktu,
;  wygaszanie. Etap specjalny (iy_07 bit 0 z nagrody tabliczki, 00:1FED) pominiety - decyzja 22.10.2026: flaga
;  skasowana, g_next_bonus_level bez zmian, od razu mapa (opisana roznica). Teleporty (iy_0D b2, iy_06 b4) - M6.
;  Wejscie: boot_cold = 0, scr_irq = 0 w ramce wyjscia z poziomu (referencja: irq_w_aend).
; =====================================================================
scr_seq_score
	jsr scr_init
	lda #41                   ; fade_screen_to_black (00:1FC4): 41 IRQ - obraz zrobil trans bez random_A
	jsr scr_skip_a
	lda iy_00
	and #$DF                  ; res 5, iy_00 (00:1FC8)
	sta iy_00
	jsr snd_music_stop        ; rst $20 (00:1FD8)
	jsr scr_clear_sprite_table ; 00:1FE0
	jsr scr_score_screen      ; handle_level_score_screen (00:155E)
	jmp boot_score_tail       ; M6.5: 00:1FE6-00:2014 (src/scr/boot.asm): etap specjalny albo g_level + 1, A = 1 -> main@main_loop

; =====================================================================
;  M6.3: game over (zycia = 0) - handle_level_restart_countdown_timer od 00:208C (wygaszanie zrobil port:
;  game/trans.asm) i run_game_over_screen (00:1401-00:1476, wariant bez kontynuacji: g_continues = 0).
;  Dalej od razu main@reset_game_state (sst_reset): ekran tytulowy, mapa, wygaszanie jak scr_seq_title (kod
;  rezydentny: boot_gameover -> boot_after_title). Wariant z kontynuacja
;  (g_continues > 0: ikony, odliczanie 9..0, 00:1477-00:14DD) - M6 (kontynuacje daje etap specjalny, ktorego
;  port jeszcze nie ma). Wejscie: boot_cold = 0, scr_irq = 0 w ramce wyjscia z poziomu (referencja: irq_g_gfade).
; =====================================================================
scr_seq_gameover
	jsr scr_init
	lda #41                   ; fade_screen_to_black (00:208C): 41 IRQ - obraz zrobil trans bez random_A
	jsr scr_skip_a
	jsr scr_clear_sprite_table ; 00:208F
	lda iy_00
	and #$DF                  ; res 5, iy_00 (00:2092)
	sta iy_00
	; run_game_over_screen (00:1401): obraz wylaczony, 1 IRQ; load_art ART_09_351F -> $0000 (to samo tlo co ekran
	; wyniku, bank 53) i ARTMAP_05_67FE (bc = $32, tmp_00 = 0) -> $3800; paleta PAL3_game_over (00:14FC)
	lda SC_REG1
	and #$BF
	sta SC_REG1
	jsr scr_wait0
	jsr scr_load_begin
	mwa #scr_rle_g sz_s
	mwa #EKR_RLE_G sz_n
	lda #0
	sta tmp_00
	jsr scr_unpack_tilemap
	jsr scr_used_tiles        ; tylko kafle uzyte w komorkach (jak ekran wyniku)
	jsr bc_used_tiles         ; + kafle ekranu kontynuacji (g_continues > 0)
	lda #2
	jsr scr_unpack_used
	lda #0
	sta scr_prio
	jsr scr_build_bg
	jsr scr_prefill
	ldx #K_GLOAD
	jsr scr_load_end
	lda #0
	sta g_vdp_scroll_x
	sta g_vdp_scroll_y
	lda #3
	ldx #<$14FC
	ldy #>$14FC
	jsr scr_signal_pal
	lda #120                  ; @wait_for_120_frames (00:1445): obraz wlaczony
	sta scr_cnt
sgo_w1
	lda SC_REG1
	ora #$40
	sta SC_REG1
	jsr scr_wait0
	dec scr_cnt
	bne sgo_w1
	lda SC_CONT               ; @player_has_continues (00:1458): ekran kontynuacji (kod rezydentny src/scr/special.asm)
	beq sgo_nocont
	jmp boot_continue
sgo_nocont
	lda #180                  ; @wait_for_button_1_2_or_180_frame_timeout (00:1461): bc = $B4, koniec przy 0 albo
	sta scr_cnt               ; przycisku (bit 5 wejscia = 0) po odliczeniu; przyciskow nie sprawdza przed 1. wait
sgo_w2
	jsr scr_wait0
	dec scr_cnt
	beq sgo_ret
	lda g_inputs_player_1
	and #$20
	bne sgo_w2
sgo_ret                         ; and a / ret z carry = 0 -> A = 0 -> main@reset_game_state (00:1C4E): ekran tytulowy
	jmp sst_reset             ; bez scr_init - ostatnia ramka game over zostaje na ekranie do wylaczenia obrazu

; ---------------------------------------------------------------------
; handle_level_score_screen (00:155E-00:16D8): ekran "SONIC HAS PASSED" - tlo ART_09_351F, mapa ARTMAP_05_612E,
; cyfry ART_09_B92E (sprite'y $80+), numer aktu (4 wiersze z LUT_level_tally_act_art_tiles), szmaragdy, paleta
; PAL3_score_tally; premia za czas (LUT_time_bonus_upper_bounds) do tmp_04..07; 120 ramek pokazu, liczenie
; (pierscienie -1 i premia -100, wynik +100 co ramke, efekt $02 co 4. raz wg tmp_08), do 180 ramek albo przycisk.
; Etapy specjalne (g_level >= $1C: ARTMAP_05_61E9, kontynuacje, mnoznik) i ekran koncowy (g_level = $13) - M6.
; ---------------------------------------------------------------------
scr_score_screen
	lda g_level
	cmp #$13
	bne sss_go
	rts                       ; handle_final_score_screen (00:172F) - M6
sss_go
	lda SC_REG1
	and #$BF                  ; obraz wylaczony (00:1566)
	sta SC_REG1
	jsr scr_wait0
	; load_art ART_09_B92E -> $3000, ART_09_351F -> $0000; unpack_art_tilemap_into_vram ARTMAP_05_612E (bc = $BB,
	; tmp_00 = 0). Port: kafle cyfr, komorki, szmaragdy i numer aktu, atlas 8 bpp tylko z kafli uzytych w komorkach
	; (bank 53; ekran nie dopisuje potem napisow), czyste tlo.
	jsr scr_load_begin
	jsr scr_need_digits       ; tylko cyfry $80-$93 (pary z danych mapy 1)
	lda #1
	sta scr_sflt
	mwa #scr_spr_m sz_s
	lda #EKR_SPR_M_N
	jsr scr_load_sprites
	lda #0
	sta scr_sflt
	jsr bs_rle_w              ; M6.5 (src/scr/special.asm): ARTMAP_05_612E albo (etap specjalny) ARTMAP_05_61E9 -> sz_s, sz_n
	lda #0
	sta tmp_00
	jsr scr_unpack_tilemap
	lda g_chaos_emeralds_collected ; draw_repeated_16x16_tile_string (00:16D9): szmaragdy, gdy > 0
	beq sss_noem
	jsr scr_emeralds
sss_noem
	lda g_level               ; numer aktu (00:15BF): 4 wiersze po 2 kafle od (x = $15, y = 5)
	cmp #$1C
	bcs sss_noact
	lda #$15
	sta g_HUD_FFstr_buf
	lda #$04
	sta g_HUD_FFstr_buf+1
	ldx g_level
	lda scr_r0+[$1B69-EKR_R0_FROM],x ; LUT_level_tally_act_art_offset
	tax
	lda #4
	sta scr_cnt
sss_act
	inc g_HUD_FFstr_buf+1     ; y + 1
	lda scr_r0+[$1B51-EKR_R0_FROM],x ; LUT_level_tally_act_art_tiles (ldi x 2)
	sta g_HUD_FFstr_buf+2
	lda scr_r0+[$1B51-EKR_R0_FROM]+1,x
	sta g_HUD_FFstr_buf+3
	lda #$FF
	sta g_HUD_FFstr_buf+4
	txa
	pha
	mwa #g_HUD_FFstr_buf sz_m
	jsr scr_print_ff
	pla
	tax
	inx
	inx
	dec scr_cnt
	bne sss_act
sss_noact
	jsr scr_used_tiles        ; zbior kafli komorek (scr_used)
	lda #2
	jsr scr_unpack_used       ; bank 53 $4000: uzyte kafle -> ATLAS_VRAM (kod rezydentny)
	lda #0
	sta scr_prio
	jsr scr_build_bg
	jsr scr_prefill
	ldx #K_WLOAD
	jsr scr_load_end          ; (etap specjalny: scr_kadj = 1 - o jedno przerwanie mniej)
	lda #0                    ; @skip_drawing_act_number_art (00:15FD)
	sta g_vdp_scroll_x
	sta g_vdp_scroll_y
	lda #3                    ; PAL3_score_tally (00:1604)
	ldx #<$1B8D
	ldy #>$1B8D
	jsr scr_signal_pal
	jsr ss_tally_start        ; etapy specjalne (00:160C-00:1624, M6.5): liczniki, mnoznik; punkty za pierscien (scr_pts_d / e)
	lda iy_09                 ; bit 2: cancel_bonuses_for_score_tally (00:1719)
	and #4
	beq sss_nocb
	lda #0
	sta g_rings_BCD
	lda iy_09
	and #$F3                  ; res 3, res 2
	sta iy_09
sss_nocb
	lda iy_09                 ; bit 3: special_stage_continue_was_collected_by_end (00:1726)
	and #8
	beq sss_nocont
	inc SC_CONT
	lda iy_09
	and #$F7
	sta iy_09
sss_nocont
	ldx #0                    ; premia za czas (00:1633): pierwszy prog (min, s BCD) <= czas
sss_tb
	lda g_time_mins
	cmp scr_r0+[$153E-EKR_R0_FROM],x
	bne sss_tbm
	lda g_time_secs_BCD
	cmp scr_r0+[$153E-EKR_R0_FROM]+1,x
	bcs sss_tbsel
	bcc sss_tbn
sss_tbm
	bcs sss_tbsel             ; minuty wieksze
sss_tbn
	inx
	inx
	cpx #16
	bne sss_tb
	ldx #<$151E               ; time_bonus_nothing
	ldy #>$151E
	jmp sss_tbset
sss_tbsel
	ldy scr_r0+[$154E-EKR_R0_FROM]+1,x ; LUT_time_bonus_scores[i] (adres SMS)
	lda scr_r0+[$154E-EKR_R0_FROM],x
	tax
sss_tbset                       ; tmp_04..07 = 4 B premii (big endian; etap specjalny: LUT_zero_time_bonus - M6)
	txa
	clc
	adc #<SR_OFS
	sta sz_s
	tya
	adc #>SR_OFS
	sta sz_s+1
	ldy #3
sss_tbc
	lda (sz_s),y
	sta tmp_04,y
	dey
	bpl sss_tbc
	jsr ss_zero_bonus         ; etap specjalny: LUT_zero_time_bonus (00:1667, M6.5)
	lda iy_00
	ora #2                    ; set 1, iy_00: tablica sprite'ow w IRQ (00:1672)
	sta iy_00
	lda #120                  ; @wait_before_counting: 120 ramek
	sta scr_cnt
sss_w1
	lda SC_REG1
	ora #$40
	sta SC_REG1
	jsr scr_wait0
	jsr scr_draw_tally
	dec scr_cnt
	bne sss_w1
sss_cnt                         ; @loop_count_score_bonuses_down (00:168E)
	jsr scr_wait0
	jsr scr_draw_tally
	jsr scr_rings_down        ; score_tally_count_rings_down (00:19B4)
	lda g_level
	cmp #$1C
	bcs sss_notb
	jsr scr_bonus_down        ; transfer_100_bonus_to_score (00:19DF)
sss_notb
	inc tmp_08
	lda tmp_08
	and #3
	bne sss_nosnd
	lda #$02                  ; rst $28: dzwiek liczenia
	jsr play_sfx
sss_nosnd
	lda g_rings_BCD
	ora tmp_04
	ora tmp_04+1
	ora tmp_04+2
	ora tmp_04+3
	bne sss_cnt
	lda #180                  ; @wait_at_end_for_180_frames_or_button_1_2
	sta scr_cnt
sss_w2
	jsr scr_wait0
	jsr scr_draw_tally
	lda g_inputs_player_1
	and #$20
	beq sss_ret               ; przycisk 1 albo 2
	dec scr_cnt
	bne sss_w2
sss_ret
	rts

; scr_used_tiles: scr_used (32 B, bit kafla t: bajt t >> 3, bit t & 7) = kafle 768 komorek nazw
scr_used_tiles
	ldx #31
	lda #0
sut2_c
	sta scr_used,x
	dex
	bpl sut2_c
	mwa #scr_nt sz_p          ; 3 strony komorek (768)
	ldy #0
sut2_l
	lda (sz_p),y
	sta scr_q
	lsr
	lsr
	lsr
	sta scr_c                 ; bajt
	lda scr_q
	and #7
	tax
	lda bit_tab,x             ; 1 << (t & 7) (render/load.asm)
	ldx scr_c
	ora scr_used,x
	sta scr_used,x
	iny
	bne sut2_l
	inc sz_p+1
	lda sz_p+1
	cmp #>[scr_nt+$300]
	bne sut2_l
	rts

; scr_need_digits: scr_need = tylko pary cyfr $80-$92 (draw_sprite_text cyfr wyniku i zyc)
scr_need_digits
	ldx #127
	lda #0
sdg_c
	sta scr_need,x
	dex
	bpl sdg_c
	lda #1
	ldx #$80/2
sdg_d
	sta scr_need,x
	inx
	cpx #[$80+20]/2
	bne sdg_d
	rts

; scr_emeralds: draw_repeated_16x16_tile_string (00:16D9) z LUT_chaos_emerald_icon_16x16text (00:1711), C = $10:
; x = $10 - n / 2, dwa napisy (y $14 i $15, kafle $AD $AE / $BD $BE), n razy, x + 2; atrybut 0
scr_emeralds
	sta scr_cnt
	lsr
	sta scr_q
	lda #$10
	sec
	sbc scr_q
	sta g_HUD_FFstr_buf       ; x
	sta g_HUD_FFstr_buf+5
	ldx #3
sem_c
	lda scr_r0+[$1711-EKR_R0_FROM],x
	sta g_HUD_FFstr_buf+1,x
	lda scr_r0+[$1711-EKR_R0_FROM]+4,x
	sta g_HUD_FFstr_buf+6,x
	dex
	bpl sem_c
	lda #0
	sta tmp_00
sem_l
	mwa #g_HUD_FFstr_buf sz_m
	jsr scr_print_ff
	mwa #g_HUD_FFstr_buf+5 sz_m
	jsr scr_print_ff
	inc g_HUD_FFstr_buf
	inc g_HUD_FFstr_buf
	inc g_HUD_FFstr_buf+5
	inc g_HUD_FFstr_buf+5
	dec scr_cnt
	bne sem_l
	rts

; ---------------------------------------------------------------------
; draw_score_tally_screen (00:1A18): g_sprite_count = 0, od wpisu 0: wynik (8 cyfr) w ($88, $50), pierscienie
; ($98, $80), premia za pierscien "100" (LUT_normal_stage_ring_bonus 00:151C) w ($C0, $80), zycia ($38, $9F),
; premia za czas (tmp_04..07) w ($88, $68). Etap specjalny (inne pozycje, mnoznik, kontynuacje) - M6.
; ---------------------------------------------------------------------
scr_draw_tally
	lda #0
	sta g_sprite_count
	sta g_next_avail_vdp_sprite_ptr ; ld hl,g_sprite_table / ld (g_next_avail_vdp_sprite_ptr),hl
	lda #>SC_SAT_S
	sta g_next_avail_vdp_sprite_ptr+1
	mwa #g_score_BCD sz_s     ; wynik
	lda #4
	jsr scr_bcd_str
	lda #$88
	ldy #$50
	jsr sdt_text
	lda g_level               ; etap specjalny: reszta ekranu w kodzie rezydentnym (src/scr/special.asm)
	cmp #$1C
	bcc sdt_n
	jmp ss_draw_tally_rest
sdt_n
	mwa #g_rings_BCD sz_s     ; pierscienie
	lda #1
	jsr scr_bcd_str
	lda #$98
	ldy #$80
	jsr sdt_text
	mwa #scr_r0+[$151C-EKR_R0_FROM] sz_s ; "100"
	lda #2
	jsr scr_bcd_str
	lda #$C0
	ldy #$80
	jsr sdt_text
	jsr sdt_lives
	mwa #tmp_04 sz_s          ; premia za czas
	lda #4
	jsr scr_bcd_str
	lda #$88
	ldy #$68
	jmp sdt_text
sdt_lives                       ; draw_tally_screen_lives (00:1ACA): zawsze 2 cyfry
	lda g_lives
	ldx #0
sdt_div
	cmp #10
	bcc sdt_dd
	sbc #10
	inx
	bne sdt_div
sdt_dd
	sta scr_q
	txa
	asl
	clc
	adc #$80
	sta g_HUD_FFstr_buf
	lda scr_q
	asl
	clc
	adc #$80
	sta g_HUD_FFstr_buf+1
	lda #$FF
	sta g_HUD_FFstr_buf+2
	lda #$38
	ldy #$9F
	jmp sdt_text
; sdt_text: draw_sprite_text g_HUD_FFstr_buf od x = A, y = Y, od wpisu g_next_avail_vdp_sprite_ptr (potem nastepny)
sdt_text
	sta scr_c
	sty scr_y8
	mwa #g_HUD_FFstr_buf sz_m
	ldx g_next_avail_vdp_sprite_ptr
	jsr scr_dst
	stx g_next_avail_vdp_sprite_ptr
	rts

; ---------------------------------------------------------------------
; build_BCD_FFstr (00:1B13): A bajtow BCD od (sz_s) -> g_HUD_FFstr_buf (licznik scr_bn; niszczy X, Y): kafel $80 + 2 * cyfra, zera wiodace
; $FE (puste pole), same zera -> ostatnia cyfra "0"; $FF na koncu
; ---------------------------------------------------------------------
scr_bcd_str
	sta scr_bn
	ldy #0                    ; zrodlo
	ldx #0                    ; cel
sbs_lead
	lda (sz_s),y
	and #$F0
	bne sbs_tens
	lda #$FE
	sta g_HUD_FFstr_buf,x
	inx
	lda (sz_s),y
	and #$0F
	bne sbs_ones
	lda #$FE
	sta g_HUD_FFstr_buf,x
	inx
	iny
	dec scr_bn
	bne sbs_lead
	lda #$FF                  ; same zera: ostatnie pole "0"
	sta g_HUD_FFstr_buf,x
	lda #$80
	sta g_HUD_FFstr_buf-1,x
	rts
sbs_tens
	lda (sz_s),y
	lsr
	lsr
	lsr
	lsr
	asl
	clc
	adc #$80
	sta g_HUD_FFstr_buf,x
	inx
sbs_ones
	lda (sz_s),y
	and #$0F
	asl
	clc
	adc #$80
	sta g_HUD_FFstr_buf,x
	inx
	iny
	dec scr_bn
	bne sbs_tens
	lda #$FF
	sta g_HUD_FFstr_buf,x
	rts

; ---------------------------------------------------------------------
; score_tally_count_rings_down (00:19B4): pierscienie > 0 -> -1 (BCD: mlodsza cyfra $F -> $9), wynik + 100
; ---------------------------------------------------------------------
scr_rings_down
	lda g_rings_BCD
	beq srd_ret
	sec
	sbc #1
	sta scr_q                 ; c
	and #$0F
	cmp #$0A
	bcc srd_ok
	lda scr_q
	sec
	sbc #6
	sta scr_q
srd_ok
	lda scr_q
	sta g_rings_BCD
	jmp scr_add100            ; DE = $0100, C = 0 (etap specjalny: mnoznik - M6)
srd_ret
	rts

; ---------------------------------------------------------------------
; transfer_100_bonus_to_score (00:19DF): premia tmp_04..07 = 0 -> nic; inaczej tmp_06, tmp_05, tmp_04 - 1 z
; pozyczka (scf, sbc 0; mlodsza cyfra >= $A -> -6; bajt >= $A0 -> -$60; pozyczka dalej = bajt sie zawinal),
; wynik + 100
; ---------------------------------------------------------------------
scr_bonus_down
	lda tmp_04
	ora tmp_04+1
	ora tmp_04+2
	ora tmp_04+3
	beq sbd_ret
	ldx #2                    ; tmp_06 (tmp_04 + 2), tmp_05, tmp_04
	lda #1
	sta scr_q                 ; pozyczka (scf)
sbd_b
	lda tmp_04,x
	sec
	sbc scr_q                 ; sbc a,0 z pozyczka
	sta scr_c
	and #$0F
	cmp #$0A
	bcc sbd_t
	lda scr_c
	sec
	sbc #6
	sta scr_c
sbd_t
	lda scr_c
	ldy #0                    ; pozyczka do starszego bajtu: tylko gdy bajt >= $A0 (zawiniety, sub $60 / ccf)
	cmp #$A0
	bcc sbd_s
	sbc #$60
	ldy #1
sbd_s
	sta tmp_04,x
	sty scr_q
	dex
	bpl sbd_b
	jmp scr_add100
sbd_ret
	rts

; ---------------------------------------------------------------------
; add_CHL_points_to_score_in_BCD (00:39D8) dla DE = $0100, C = 0: wynik BCD big endian (D2BA..D2BD) += 100;
; bajt D2BB >= g_next_life_bonus_10000s_BCD -> premia + 5 (BCD), zycie + 1, efekt $09. Arytmetyka BCD jak
; obj/common.asm (bez trybu dziesietnego 6502 - NMI liczy binarnie).
; ---------------------------------------------------------------------
scr_add100
	clc
	lda scr_pts_e
	ldx #3
	jsr sap_add               ; D2BD += E = 0 (etap specjalny: mlodszy bajt mnoznika)
	lda scr_pts_d
	ldx #2
	jsr sap_add               ; D2BC += D = 1 (etap specjalny: mnoznik; + C)
	lda #$00
	ldx #1
	jsr sap_add               ; D2BB += C = 0 (+ C)
	sta scr_tmpw              ; ld c,a
	lda #0
	ldx #0
	jsr sap_add               ; D2BA += 0 + C
	lda scr_tmpw
	cmp g_next_life_bonus_10000s_BCD
	bcc sap_ret
	lda g_next_life_bonus_10000s_BCD
	ldy #5
	clc
	jsr scr_bcd_adc
	sta g_next_life_bonus_10000s_BCD
	inc g_lives
	lda #$09                  ; rst $28: dodatkowe zycie
	jmp play_sfx
sap_ret
	rts
sap_add                         ; g_score[X] = A + g_score[X] + C (BCD)
	ldy g_score_BCD,x
	jsr scr_bcd_adc
	sta g_score_BCD,x
	rts
; scr_bcd_adc: A = A + Y + C w BCD (jak adc + daa dla poprawnych cyfr), C = przeniesienie. Niszczy Y.
scr_bcd_adc
	sty zg_off
	sta zg_a
	lda #0
	rol
	sta zg_hl
	lda zg_a
	and #$0F
	sta zg_hl+1
	lda zg_off
	and #$0F
	clc
	adc zg_hl+1
	adc zg_hl
	ldy #0
	cmp #10
	bcc sba_lo
	sbc #10
	iny
sba_lo
	sta zg_hl+1
	sty zg_hl
	lda zg_a
	lsr
	lsr
	lsr
	lsr
	sta zg_a
	lda zg_off
	lsr
	lsr
	lsr
	lsr
	clc
	adc zg_a
	adc zg_hl
	cmp #10
	bcc sba_hi
	sbc #10                   ; C = 1 (przeniesienie wyjsciowe)
sba_hi
	php
	asl
	asl
	asl
	asl
	ora zg_hl+1
	plp
	rts

; =====================================================================
;  Palety: signal_load_palettes, rozjasnianie mapy, wygaszanie przed poziomem
; =====================================================================
; scr_signal_pal: signal_load_palettes (00:0333) - A = palety (bit 0 tlo, bit 1 sprite'y), X/Y = adres SMS
scr_signal_pal
	sta g_SIG00b3_palettes_present
	stx g_SIG00b3_palette_addr
	sty g_SIG00b3_palette_addr+1
	lda iy_00
	ora #8                    ; set 3, iy_00: paleta w nastepnym IRQ
	sta iy_00
	rts

; scr_wait_keep: ld a,(g_sprite_count); res 0; wait; ld (g_sprite_count),a - ta sama tablica sprite'ow
; wysylana w kazdym IRQ (petle czekania rozjasniania i wygaszania)
scr_wait_keep
	lda g_sprite_count
	pha
	jsr scr_wait0
	pla
	sta g_sprite_count
	rts

; scr_wait_keep_n: A razy scr_wait_keep
scr_wait_keep_n
	sta scr_cnt
swk_l
	jsr scr_wait_keep
	dec scr_cnt
	bne swk_l
	rts

; ---------------------------------------------------------------------
; palette_fade_in_banks_01_02 (00:0B50): X/Y = adres SMS palety docelowej (32 B). Bufor palety tymczasowej
; czarny, wyslany z obrazem wlaczonym (1 IRQ), 9 IRQ, potem 4 kroki: kazda skladowa 2-bitowa + 1 w strone
; celu, wyslanie, 10 IRQ (razem 50 przerwan).
; ---------------------------------------------------------------------
scr_fade_in
	stx tmp_06
	sty tmp_06+1
	ldx #31
	lda #0
sfi_c
	sta SC_TMPPAL,x
	dex
	bpl sfi_c
	lda #3                    ; _palette_fade_up_common (00:0B6E)
	ldx #<SC_TMPPAL_S
	ldy #>SC_TMPPAL_S
	jsr scr_signal_pal
	lda SC_REG1
	ora #$40
	sta SC_REG1
	jsr scr_wait_keep
	lda #9
	jsr scr_wait_keep_n
	lda #4
	sta scr_fstep
sfi_step
	lda tmp_06
	clc
	adc #<SR_OFS
	sta sz_s
	lda tmp_06+1
	adc #>SR_OFS
	sta sz_s+1
	ldy #31
sfi_col                         ; skladowa < celu -> + 1 (R: bity 0-1, G: 2-3, B: 4-5)
	lda (sz_s),y
	and #$03
	sta scr_q
	lda SC_TMPPAL,y
	and #$03
	cmp scr_q
	bcs sfi_r
	adc #1
sfi_r
	sta scr_c
	lda (sz_s),y
	and #$0C
	sta scr_q
	lda SC_TMPPAL,y
	and #$0C
	cmp scr_q
	bcs sfi_g
	adc #4
sfi_g
	ora scr_c
	sta scr_c
	lda (sz_s),y
	and #$30
	sta scr_q
	lda SC_TMPPAL,y
	and #$30
	cmp scr_q
	bcs sfi_b
	adc #$10
sfi_b
	ora scr_c
	sta SC_TMPPAL,y
	dey
	bpl sfi_col
	lda #3
	ldx #<SC_TMPPAL_S
	ldy #>SC_TMPPAL_S
	jsr scr_signal_pal
	lda #10
	jsr scr_wait_keep_n
	dec scr_fstep
	bne sfi_step
	rts

; ---------------------------------------------------------------------
; fade_screen_to_black (00:0A40): 1 IRQ, potem 4 kroki: palette_fade_to_black (00:0A90) wyswietlanych palet
; (g_current_displayed_palette_0 / _1, 16 + 16 kolorow) do bufora tymczasowego - kazda skladowa - 1, nie
; mniej niz 0 - wyslanie, 10 IRQ (razem 41). Sprite'y z ostatniej ramki zostaja (licznik zachowany).
; ---------------------------------------------------------------------
scr_fade_to_black
	jsr scr_wait_keep
	lda #4
	sta scr_fstep
sfb_step
	lda SC_CURPAL0            ; palette_fade_to_black: (cur0) -> tmp[0..15]
	ldx SC_CURPAL0+1
	ldy #0
	jsr sfb_part
	lda SC_CURPAL1            ; (cur1) -> tmp[16..31]
	ldx SC_CURPAL1+1
	ldy #16
	jsr sfb_part
	lda #3
	ldx #<SC_TMPPAL_S
	ldy #>SC_TMPPAL_S
	jsr scr_signal_pal
	lda #10
	jsr scr_wait_keep_n
	dec scr_fstep
	bne sfb_step
	rts
; sfb_part: A/X = adres SMS 16 kolorow zrodla, Y = pierwszy kolor bufora tymczasowego
sfb_part
	sty scr_i
	jsr scr_sms_ptr           ; sz_s = adres portu
	lda #16
	sta scr_cnt
	ldy #0
sfb_c
	lda (sz_s),y
	and #$03
	beq sfb_r
	sec
	sbc #1
sfb_r
	sta scr_c
	lda (sz_s),y
	and #$0C
	beq sfb_g
	sec
	sbc #4
sfb_g
	ora scr_c
	sta scr_c
	lda (sz_s),y
	and #$30
	beq sfb_b
	sec
	sbc #$10
sfb_b
	ora scr_c
	ldx scr_i
	sta SC_TMPPAL,x
	inc scr_i
	iny
	dec scr_cnt
	bne sfb_c
	rts

; scr_sms_ptr: A/X = adres SMS (lo/hi) -> sz_s = adres portu: RAM SMS ($C000+) w lustrze (+ SMS_RAM),
; ROM banku 0 w ekr_rom0.bin (+ SR_OFS)
scr_sms_ptr
	cpx #$C0
	bcc ssp_rom
	sta sz_s
	txa
	clc
	adc #>SMS_RAM
	sta sz_s+1
	rts
ssp_rom
	clc
	adc #<SR_OFS
	sta sz_s
	txa
	adc #>SR_OFS
	sta sz_s+1
	rts

; =====================================================================
;  Tablica sprite'ow i napisy (logika - RAM SMS i model komorek)
; =====================================================================
; clear_sprite_table (00:05E2): wpisy x = y = $E0 (kafel jak wpis 0), g_sprite_count = $40, poprzedni 0
scr_clear_sprite_table
	lda #$E0
	sta SPRTAB
	sta SPRTAB+1
	ldx #0
sct_l                           ; ldir od wpisu 0 do wpisu 1 (wzor 3 B), $BD bajtow
	lda SPRTAB,x
	sta SPRTAB+3,x
	inx
	cpx #$BD
	bne sct_l
	lda #$40
	sta g_sprite_count
	lda #0
	sta g_prev_sprite_count
	rts

; ---------------------------------------------------------------------
; draw_sprite_string (00:350F): mapa sz_m (adres portu) w (sz_x, sz_y) - do 3 wierszy po 6 B (co 16 px,
; kolumny co 8 px); $FF na poczatku wiersza konczy. Wiersz: y hi = $FF i lo >= $F0 - rysowany, lo < $F0 -
; pominiety; y hi != 0 - pominiety, lo >= $C0 - koniec mapy. Kolumna: kafel >= $FE albo x hi != 0 -
; pominieta. Wpis (x, y, kafel) pod g_next_avail_vdp_sprite_ptr (inc l), g_sprite_count + 1; tmp_06 = x.
; ---------------------------------------------------------------------
scr_dss
	lda sz_x
	sta tmp_06
	lda sz_x+1
	sta tmp_06+1
	lda #3
	sta scr_r
dss2_row
	ldy #0
	lda (sz_m),y
	cmp #$FF
	jeq dss2_ret
	lda sz_y+1
	cmp #$FF
	bne dss2_left
	lda sz_y
	cmp #$F0
	bcc dss2_skip
	bcs dss2_draw
dss2_left
	ora #0
	bne dss2_skip
	lda sz_y
	cmp #$C0
	jcs dss2_ret
dss2_draw
	lda tmp_06
	sta sz_d
	lda tmp_06+1
	sta sz_d+1
	ldx g_next_avail_vdp_sprite_ptr
	ldy #0
dss2_col
	lda sz_d+1
	bne dss2_cull
	lda (sz_m),y
	cmp #$FE
	bcs dss2_cull
	sta SPRTAB+2,x
	lda sz_d
	sta SPRTAB,x
	lda sz_y
	sta SPRTAB+1,x
	inx
	inx
	inx
	inc g_sprite_count
dss2_cull
	clc
	lda sz_d
	adc #8
	sta sz_d
	bcc dss2_cx
	inc sz_d+1
dss2_cx
	iny
	cpy #6
	bne dss2_col
	stx g_next_avail_vdp_sprite_ptr
dss2_skip
	clc
	lda sz_m
	adc #6
	sta sz_m
	bcc dss2_m
	inc sz_m+1
dss2_m
	clc
	lda sz_y
	adc #16
	sta sz_y
	bcc dss2_y
	inc sz_y+1
dss2_y
	dec scr_r
	jne dss2_row
dss2_ret
	rts

; ---------------------------------------------------------------------
; draw_sprite_text (00:35CC): napis sz_m (kafle, $FE - pusta pozycja, $FF - koniec) od x = scr_c, y = scr_y8;
; wpisy od X (mlodszy bajt adresu w tablicy sprite'ow, inc l). Wyjscie: X = nastepny wpis.
; ---------------------------------------------------------------------
scr_dst
	ldy #0
dst_l
	lda (sz_m),y
	cmp #$FF
	beq dst_ret
	cmp #$FE
	beq dst_skip
	sta SPRTAB+2,x
	lda scr_c
	sta SPRTAB,x
	lda scr_y8
	sta SPRTAB+1,x
	inx
	inx
	inx
	inc g_sprite_count
dst_skip
	iny
	lda scr_c
	clc
	adc #8
	sta scr_c
	jmp dst_l
dst_ret
	rts

; ---------------------------------------------------------------------
; print_positioned_FF_string (00:05AF): napis sz_m: x, y, kafle..., $FF; atrybut tmp_00. Komorka y*32 + x
; (VDP $3800 + 2 * komorka), kolejne komorki w prawo. Zmienione komorki do listy scr_dlo/hi (scr_render).
; ---------------------------------------------------------------------
scr_print_ff
	ldy #1
	lda (sz_m),y              ; y
	lsr
	lsr
	lsr
	sta scr_cell+1            ; y >> 3
	lda (sz_m),y
	asl
	asl
	asl
	asl
	asl                       ; (y << 5) & $FF
	dey
	clc
	adc (sz_m),y              ; + x
	sta scr_cell
	bcc spf_c
	inc scr_cell+1
spf_c
	ldy #2
spf_l
	lda (sz_m),y
	cmp #$FF
	beq spf_ret
	jsr scr_put_cell          ; A = kafel, atrybut tmp_00, komorka scr_cell
	inc scr_cell
	bne spf_n
	inc scr_cell+1
spf_n
	iny
	bne spf_l
spf_ret
	rts

; scr_put_cell: komorka scr_cell = kafel A, atrybut tmp_00; zmiana -> lista komorek (przepelnienie: cale tlo).
; Komorki poza 0..767 (VRAM za tablica nazw) pomijane. Zachowuje Y.
scr_put_cell
	sta scr_d
	lda scr_cell+1
	cmp #3
	bcs spc_ret
	clc
	adc #>scr_nt
	sta sz_p+1
	lda scr_cell
	sta sz_p
	sty scr_q
	ldy #0
	lda scr_d
	cmp (sz_p),y
	bne spc_chg
	lda sz_p+1
	clc
	adc #3                    ; scr_at = scr_nt + $300
	sta sz_p+1
	lda tmp_00
	cmp (sz_p),y
	beq spc_done
	sta (sz_p),y
	jmp spc_add
spc_chg
	sta (sz_p),y
	lda sz_p+1
	clc
	adc #3
	sta sz_p+1
	lda tmp_00
	sta (sz_p),y
spc_add
	ldx scr_nd
	cpx #$FF
	beq spc_done
	cpx #64
	bcs spc_full
	lda scr_cell
	sta scr_dlo,x
	lda scr_cell+1
	sta scr_dhi,x
	inc scr_nd
	jmp spc_done
spc_full
	lda #$FF                  ; za duzo zmian - przebudowa calego tla
	sta scr_nd
spc_done
	ldy scr_q
spc_ret
	rts

; ---------------------------------------------------------------------
; unpack_art_tilemap_into_vram (00:0501): dane RLE sz_s, sz_n bajtow (bc), atrybut tmp_00 -> komorki od 0.
; Bajt rozny od poprzedniego (E) = kafel; rowny = znacznik serii: nastepny bajt = liczba dodatkowych kopii
; (0 = 256), po serii E = dopelnienie nastepnego bajtu; $FF = komorka pominieta (pojedynczo i w serii).
; Komorki nie trafiaja do listy zmian (po mapie przebudowa calego tla - scr_build_bg).
; ---------------------------------------------------------------------
scr_unpack_tilemap
	lda #0
	sta scr_cell
	sta scr_cell+1
sut_new                         ; ----: e = ~(hl)
	ldy #0
	lda (sz_s),y
	eor #$FF
	sta scr_e
sut_next                        ; ---
	ldy #0
	lda (sz_s),y
	cmp scr_e
	beq sut_rep
	sta scr_e                 ; ld e,a (takze dla $FF: +++)
	cmp #$FF
	beq sut_one_skip
	jsr sut_put
	jmp sut_one_adv
sut_one_skip
	jsr sut_inc
sut_one_adv
	jsr sut_adv
	bne sut_next
	rts
sut_rep                         ; +: d = a, hl++, bc--, e = licznik
	sta scr_d
	jsr sut_adv
	beq sut_ret
	ldy #0
	lda (sz_s),y
	sta scr_e
sut_run
	lda scr_d
	cmp #$FF
	beq sut_rskip
	jsr sut_put
	jmp sut_rn
sut_rskip
	jsr sut_inc
sut_rn
	dec scr_e
	bne sut_run
	jsr sut_adv               ; --: hl++, bc--, != 0 -> ----
	bne sut_new
sut_ret
	rts
sut_put                         ; kafel A + atrybut w komorce, komorka + 1
	ldx scr_cell+1
	cpx #3
	bcs sut_inc
	pha
	txa
	clc
	adc #>scr_nt
	sta sz_p+1
	lda scr_cell
	sta sz_p
	pla
	ldy #0
	sta (sz_p),y
	lda sz_p+1
	clc
	adc #3
	sta sz_p+1
	lda tmp_00
	sta (sz_p),y
sut_inc
	inc scr_cell
	bne sut_i
	inc scr_cell+1
sut_i
	rts
sut_adv                         ; hl++, bc--; Z = 1 gdy bc = 0
	inc sz_s
	bne sut_a1
	inc sz_s+1
sut_a1
	lda sz_n
	bne sut_a2
	dec sz_n+1
sut_a2
	dec sz_n
	lda sz_n
	ora sz_n+1
	rts

; =====================================================================
;  Przerwanie (irq_start 00:0073) i oczekiwanie (wait_until_irq_ticked 00:031C)
; =====================================================================
; scr_wait0: res 0, iy_00 + wait_until_irq_ticked
scr_wait0
	lda iy_00
	and #$FE
	sta iy_00
; scr_wait: obraz ramki ze stanu VDP (po ostatnim IRQ) i komorek, VBI (flip), IRQ
scr_wait
	lda iy_00
	lsr
	bcs sw_ret                ; bit 0 ustawiony - wait_until_irq_ticked wraca od razu
	jsr scr_render            ; lista gotowa, v_flip_req = 1
sw_vbi
	lda v_flip_req            ; VBI z flipem tej ramki (NMI: XDL bufora, paleta) - dopiero wtedy IRQ; nastepny
	bne sw_vbi                ; obraz rysuje juz do drugiego bufora
	jmp scr_irqemu
sw_ret
	rts

; ---------------------------------------------------------------------
; scr_irqemu: @fn_update_screen (00:00F7) gdy iy_00 bit 0 = 0: obraz wl./wyl. (reg1 bit 6), tablica sprite'ow
; (iy_00 bit 1), paleta (iy_00 bit 5 = 0: @fn_update_palette 00:0174 po tablicy sprite'ow), x_hi laty = $FF,
; iy_00 bit 0 = 1. Zawsze: random_A (00:00D8), poll_player_1_inputs (00:05A7) z @fn_pretend_button_2_pressed.
; ---------------------------------------------------------------------
scr_irqemu
	lda iy_00
	lsr
	bcs si2_noupd
	lda SC_REG1
	and #$40
	sta scr_disp
	lda iy_00
	and #2
	beq si2_nosat
	jsr scr_upload_sat
si2_nosat
	lda iy_00
	and #$20
	bne si2_nopal
	jsr scr_update_palette
si2_nopal
	lda #$FF
	sta SC_SCRREP_HI
	lda iy_00
	ora #1
	sta iy_00
si2_noupd
	jsr random_A
	jsr scr_poll
	inc scr_irq
	bne si2_ret
	inc scr_irq+1
si2_ret
	rts

; ---------------------------------------------------------------------
; upload_sprite_table_IRQ (00:033E): Y wpisow 0..count-1 z tablicy, Y = $E0 dla count..prev-1; przy count = 0
; koniec (prev bez zmian); X i kafel wpisow 0..count-1, prev = count, count = 0. Licznik ograniczony do 64.
; ---------------------------------------------------------------------
scr_upload_sat
	lda g_sprite_count
	cmp #65
	bcc sus_n
	lda #64
sus_n
	sta scr_q                 ; count
	ldx #0
	ldy #0
sus_y
	cpx scr_q
	beq sus_h
	lda SPRTAB+1,y
	sta scr_sat_y,x
	iny
	iny
	iny
	inx
	bne sus_y
sus_h
	lda g_prev_sprite_count
	cmp #65
	bcc sus_hp
	lda #64
sus_hp
	sta scr_c                 ; prev
sus_hl
	cpx scr_c
	bcs sus_xt
	lda #$E0
	sta scr_sat_y,x
	inx
	bne sus_hl
sus_xt
	lda scr_q
	beq sus_ret
	ldx #0
	ldy #0
sus_x
	lda SPRTAB,y
	sta scr_sat_x,x
	lda SPRTAB+2,y
	sta scr_sat_t,x
	iny
	iny
	iny
	inx
	cpx scr_q
	bne sus_x
	lda g_sprite_count
	sta g_prev_sprite_count
	lda #0
	sta g_sprite_count
sus_ret
	rts

; ---------------------------------------------------------------------
; @fn_update_palette (00:0174): iy_00 bit 3 -> load_palettes_IRQ (00:0566): A = g_SIG00b3_palettes_present,
; HL = g_SIG00b3_palette_addr; bit 0: CRAM 0-15 z (HL), cur0 = HL, HL + 16; bit 1: cur1 = HL, CRAM 16-31
; z (HL) (bez bitu 0: CRAM 17-31 z HL + 1); res 3, iy_00.
; ---------------------------------------------------------------------
scr_update_palette
	lda iy_00
	and #8
	jeq sup_ret
	lda g_SIG00b3_palette_addr
	ldx g_SIG00b3_palette_addr+1
	sta scr_tmpw
	stx scr_tmpw+1
	jsr scr_sms_ptr
	lda g_SIG00b3_palettes_present
	lsr
	bcc sup_no0
	lda scr_tmpw
	sta SC_CURPAL0
	lda scr_tmpw+1
	sta SC_CURPAL0+1
	ldy #15
sup_c0
	lda (sz_s),y
	sta scr_cram,y
	dey
	bpl sup_c0
	clc                       ; HL + 16
	lda sz_s
	adc #16
	sta sz_s
	bcc sup_h1
	inc sz_s+1
sup_h1
	clc
	lda scr_tmpw
	adc #16
	sta scr_tmpw
	bcc sup_no0
	inc scr_tmpw+1
sup_no0
	lda g_SIG00b3_palettes_present
	and #2
	beq sup_done
	lda scr_tmpw
	sta SC_CURPAL1
	lda scr_tmpw+1
	sta SC_CURPAL1+1
	lda g_SIG00b3_palettes_present
	lsr
	bcc sup_15
	ldy #15
sup_c1
	lda (sz_s),y
	sta scr_cram+16,y
	dey
	bpl sup_c1
	bmi sup_done
sup_15                          ; tylko sprite'y: kolory 17-31 z HL + 1 (kolor 16 bez zmian)
	ldy #15
sup_c2
	lda (sz_s),y
	sta scr_cram+16,y
	dey
	bne sup_c2
sup_done
	lda #1
	sta scr_cchg
	lda iy_00
	and #$F7
	sta iy_00
sup_ret
	rts

; ---------------------------------------------------------------------
; scr_poll: poll_player_1_inputs (00:05A7) - port $DC | $C0: bity 0-3 joystick (U D L R, aktywne zerem - jak
; PORTA Atari), bit 4 przycisk 1 = fire (TRIG0), bit 5 przycisk 2 = 1; przycisk 1 kasuje tez bit 5 (00:00F2).
; Test: wymuszony przycisk przed iteracja boot_tbtn petli tytulu / boot_mbtn petli mapy (0 = brak).
; ---------------------------------------------------------------------
scr_poll
	ldx scr_phase             ; wymuszony przycisk testu: (iteracja petli + 1) == boot_tbtn / boot_mbtn
	beq spo_port
	cpx #1
	bne spo_m
	clc
	lda scr_titer
	adc #1
	sta scr_tmpw
	lda scr_titer+1
	adc #0
	sta scr_tmpw+1
	lda boot_tbtn
	ldx boot_tbtn+1
	jmp spo_cmp
spo_m
	clc
	lda scr_miter
	adc #1
	sta scr_tmpw
	lda scr_miter+1
	adc #0
	sta scr_tmpw+1
	lda boot_mbtn
	ldx boot_mbtn+1
spo_cmp
	cmp scr_tmpw              ; 0 = brak (iteracja + 1 >= 1)
	bne spo_port
	cpx scr_tmpw+1
	bne spo_port
	lda #$CF                  ; przycisk 1 (i 2)
	bne spo_set
spo_port
	lda v_joy
	ora #$F0
	ldx v_trig
	bne spo_set
	and #$EF                  ; fire -> przycisk 1
spo_set
	sta g_inputs_player_1
	and #$10
	bne spo_ret
	lda g_inputs_player_1
	and #$DF                  ; @fn_pretend_button_2_pressed
	sta g_inputs_player_1
spo_ret
	rts

; =====================================================================
;  Ladowanie grafiki ekranu (port): tempo jak oryginal
; =====================================================================
; scr_load_begin: poczatek ladowania - po IRQ z wylaczonym obrazem: od nastepnego VBI XDL pustej linii (jak
; oryginal: ramki w kolorze ramki), bufory wolne do wypelnienia nowym tlem
scr_load_begin
	lda v_frame
	sta scr_t0
	lda #1
	sta v_blank_req
	sta v_flip_req
slb_w
	lda v_flip_req
	bne slb_w
	rts

; scr_prefill: czyste tlo -> oba bufory (pelne kopie przy XDL pustej linii), listy prostokatow i komorek puste
scr_prefill
	lda #MB_LOW
	jsr set_memac
	mwa #SCR_LIST_CPU zp_bcb
	lda v_back
	pha
	lda #0
	sta v_back
	jsr scr_bcb_view
	jsr scr_emit
	lda #1
	sta v_back
	jsr scr_bcb_view
	jsr scr_emit
	pla
	sta v_back
	jsr scr_list_run
	lda #0
	sta scr_full
	sta scr_full+1
	sta scr_rn
	sta scr_rn+1
	sta scr_pn
	sta scr_pn+1
	rts

; scr_load_end: X = stala K_* - przerwania oryginalu w czasie ladowania (random_A) i czekanie, az minie tyle
; ramek od scr_load_begin (gdy port zaladowal szybciej; wolniej - czas dluzszy, logika ta sama); ramki
; ladowania portu do boot_ldfr (pomiar: tytul, mapa)
scr_load_end
	lda v_frame
	sec
	sbc scr_t0
	sta boot_ldfr-1,x
	txa
	clc
	adc scr_kidx
	tax
	lda k_tab,x
	sec
	sbc scr_kadj              ; M6.5: poprawka stalej (ekran wyniku etapu specjalnego)
	sta scr_cnt
	jsr scr_skip_a
sle_w
	lda v_frame
	sec
	sbc scr_t0
	cmp scr_cnt
	bcc sle_w
	rts

; ---------------------------------------------------------------------
; scr_load_sprites: A = liczba par, sz_s = pary (kafel parzysty, 64 B: 2 kafle 4 bpp, starsza polowka = lewy
; piksel) -> atlas sprite'ow SMS w VRAM (SPRATLAS_VRAM + kafel * 64, 8 bpp; kolor != 0 + 16). scr_sflt = 1:
; tylko pary oznaczone w scr_need (kafel >> 1) - mapa: znacznik biezacego aktu i cyfry (scr_need_map).
; Adresy zrodla i celu samomodyfikujace sie (kod w RAM banku 49).
; ---------------------------------------------------------------------
scr_load_sprites
	sta scr_cnt
sls_pair
	ldy #0
	lda (sz_s),y              ; kafel t: VRAM $78800 + t * 64
	sta scr_q
	inc sz_s
	bne sls_s
	inc sz_s+1
sls_s
	lda scr_sflt
	beq sls_go
	lda scr_q
	lsr
	tax
	lda scr_need,x
	jeq sls_next              ; para niepotrzebna w tym akcie
sls_go
	lda scr_q
	lsr
	lsr
	clc
	adc #$88                  ; srodkowy bajt ($88 + t >> 2; t <= 255 bez przeniesienia)
	sta scr_d
	lsr
	lsr
	lsr
	lsr
	ora #$70                  ; VRAM >> 12 = $70 | mid >> 4
	and #$FE
	ora #$80                  ; okno MEMAC 8 KiB
	jsr set_memac
	lda scr_q
	and #3
	lsr
	ror
	ror                       ; (t & 3) << 6
	sta sls_w1+1
	sta sls_w2+1
	lda scr_d
	and #$1F
	clc
	adc #>MEMAC_CPU
	sta sls_w1+2
	sta sls_w2+2
	lda sz_s
	sta sls_rd+1
	lda sz_s+1
	sta sls_rd+2
	ldy #0                    ; bajt zrodla
	ldx #0                    ; piksel celu (2 na bajt)
sls_b
sls_rd	lda $FFFF,y
	pha
	lsr
	lsr
	lsr
	lsr
	beq sls_b0
	ora #$10
sls_b0
sls_w1	sta $FFFF,x
	inx
	pla
	and #$0F
	beq sls_b1
	ora #$10
sls_b1
sls_w2	sta $FFFF,x
	inx
	iny
	cpy #64
	bne sls_b
sls_next
	clc
	lda sz_s
	adc #64
	sta sz_s
	bcc sls_n
	inc sz_s+1
sls_n
	dec scr_cnt
	jne sls_pair
	rts

; ---------------------------------------------------------------------
; scr_need_map: scr_need = pary kafli sprite'ow mapy dla g_level: mapy sprite'ow wpisow level_map_XX_chunks
; (LUT_level_map_info, wpisy 5 B do skoku - czas 0) i cyfry zyc ($80 + 2 * cyfra, render_world_map_sprites)
; ---------------------------------------------------------------------
scr_need_map
	ldx #127
	lda #0
snm_c
	sta scr_need,x
	dex
	bpl snm_c
	lda #1
	ldx #$80/2
snm_d
	sta scr_need,x            ; cyfry: pary $80-$92
	inx
	cpx #[$80+20]/2
	bne snm_d
	lda g_level               ; LUT_level_map_info[g_level] -> adres SMS listy wpisow
	sta scr_q
	asl
	clc
	adc scr_q
	clc
	adc #<[SR_MAPINFO+SR_OFS]
	sta sz_p
	lda #>[SR_MAPINFO+SR_OFS]
	adc #0
	sta sz_p+1
	ldy #0
	lda (sz_p),y
	sta scr_tmpw
	iny
	lda (sz_p),y
	sta scr_tmpw+1
	iny
	lda (sz_p),y
	sta scr_aact              ; M6.4: bajt akcji mapy (Robotnik)
snm_e                           ; wpis: slowo mapy, x, y, czas (0 = koniec listy - skok)
	clc
	lda scr_tmpw
	adc #<SR_OFS
	sta sz_p
	lda scr_tmpw+1
	adc #>SR_OFS
	sta sz_p+1
	ldy #4
	lda (sz_p),y
	beq snm_ret
	ldy #0
	lda (sz_p),y              ; mapa sprite'ow (adres SMS) -> port
	clc
	adc #<SR_OFS
	sta sz_m
	iny
	lda (sz_p),y
	adc #>SR_OFS
	sta sz_m+1
	jsr snm_one
	clc
	lda scr_tmpw
	adc #5
	sta scr_tmpw
	bcc snm_e
	inc scr_tmpw+1
	bcs snm_e                 ; zawsze (C = 1 po przeniesieniu)
snm_ret
	lda scr_aact              ; M6.4: akcja mapy - kafle map sprite'ow Robotnika
	beq snm_end
	ldx #8
snm_rb
	lda snm_rmaps,x
	clc
	adc #<SR_OFS
	sta sz_m
	lda snm_rmaps+1,x
	adc #>SR_OFS
	sta sz_m+1
	stx scr_i
	jsr snm_one
	ldx scr_i
	dex
	dex
	bpl snm_rb
snm_end
	rts
snm_rmaps dta a($1129, $113B, $114D, $115F, $1183) ; map_SPRTAB_robotnik_* (adresy SMS)

; snm_one: sz_m = mapa sprite'ow (port) -> scr_need pary kafli: 3 wiersze po 6 B; $FF na poczatku wiersza konczy,
; kafle >= $FE pomijane
snm_one
	ldy #0
snm_r
	lda (sz_m),y
	cmp #$FF
	beq snm_ro
	ldx #6
snm_k
	lda (sz_m),y
	cmp #$FE
	bcs snm_s
	lsr
	sty scr_q
	tay
	lda #1
	sta scr_need,y
	ldy scr_q
snm_s
	iny
	dex
	bne snm_k
	cpy #18
	bcc snm_r
snm_ro
	rts

; =====================================================================
;  Obraz ramki: lista blittera z modelu VDP
; =====================================================================
; scr_render: obraz ramki ze stanu VDP. Bufory trzymaja tlo (jak pierscien tla gry): co ramke tylko
; 1. komorki zmienione od ostatniego obrazu -> czyste tlo (atlas) i do list obu buforow,
; 2. obraz wylaczony: flip na XDL pustej linii (kolor ramki), bufory bez zmian;
; 3. bufor tylny: prostokaty sprite'ow narysowanych w nim 2 ramki temu i jego zmienione komorki <- czyste tlo
;    (albo cala kopia, gdy lista sie przepelnila), sprite'y (prostokaty do listy bufora), komorki priorytetu,
;    lewa kolumna 8 px (reg0 bit 5) w kolorze ramki;
; start listy, czekanie; paleta do NMI (v_pal_req), v_flip_req = 1.
scr_render
	lda scr_nd
	cmp #$FF
	bne sr_cells
	jsr scr_build_bg          ; przepelnienie listy komorek: cale czyste tlo od nowa (wlasne listy)
	lda #1
	sta scr_full              ; i oba bufory pelna kopia
	sta scr_full+1
sr_cells
	lda #MB_LOW
	jsr set_memac
	mwa #SCR_LIST_CPU zp_bcb
	lda #0
	sta scr_last+1            ; 0 = lista pusta (scr_emit wpisuje adres ostatniego BCB)
	ldx #0
sr_c
	cpx scr_nd
	beq sr_view
	lda scr_dlo,x
	sta scr_cell
	lda scr_dhi,x
	sta scr_cell+1
	stx scr_i
	jsr scr_ecell
	ldx #0                    ; komorka do list obu buforow (przepelnienie: pelna kopia bufora)
	jsr scr_pend_add
	ldx #1
	jsr scr_pend_add
	ldx scr_i
	inx
	bne sr_c
sr_view
	lda #0
	sta scr_nd
	lda scr_disp
	bne sr_on
	lda #1                    ; obraz wylaczony: XDL pustej linii
	sta v_blank_req
	jmp sr_go
sr_on
	lda #0
	sta v_blank_req
	ldx v_back
	lda scr_full,x
	beq sr_part
	jsr scr_bcb_view          ; cale czyste tlo -> bufor
	jsr scr_emit
	ldx v_back
	lda #0
	sta scr_full,x
	beq sr_spr                ; zawsze
sr_part
	jsr scr_restore           ; prostokaty sprite'ow i zmienione komorki tego bufora <- czyste tlo
sr_spr
	ldx v_back
	lda #0
	sta scr_rn,x
	sta scr_pn,x
	jsr scr_sprites
	lda #0                    ; lewa kolumna 8 px (reg0 bit 5): kolor ramki
	jsr sb_defaults
	jsr sb_fb_dst
	lda #7
	sta scr_b+12
	lda #191
	sta scr_b+14
	lda #0
	sta scr_b+15              ; AND 0, XOR = kolor
	lda #SCR_BORDER
	sta scr_b+16
	jsr scr_emit
sr_go
	lda scr_last+1
	beq sr_nolist             ; nic do narysowania (obraz wylaczony, bez zmian komorek)
	jsr scr_list_run
sr_nolist
	lda scr_cchg
	beq sr_flip
	lda #0
	sta scr_cchg
	jsr scr_pal_rgb
	lda #1
	sta v_pal_req
sr_flip
scr_frame_done                  ; test (tools/m6_ekrany_test.py): bufor v_back = obraz po IRQ scr_irq, paleta scr_cram
	lda #1
	sta v_flip_req
	rts

; scr_pend_add: komorka scr_cell do listy zmienionych komorek bufora X (przepelnienie: pelna kopia bufora)
scr_pend_add
	lda scr_full,x
	bne spa_ret
	lda scr_pn,x
	cmp #64
	bcs spa_full
	stx scr_q
	txa
	asl
	asl
	asl
	asl
	asl
	asl                       ; bufor * 64
	clc
	adc scr_pn,x
	tay
	lda scr_cell
	sta scr_plo,y
	lda scr_cell+1
	sta scr_phi,y
	ldx scr_q
	inc scr_pn,x
spa_ret
	rts
spa_full
	lda #1
	sta scr_full,x
	rts

; scr_restore: bufor tylny <- czyste tlo w prostokatach sprite'ow narysowanych w nim ostatnio (2 ramki temu)
; i w komorkach zmienionych od tamtej pory (kopia; kolejne komorki w jednym wierszu - jeden BCB). Zmienne
; scr_rc / scr_ri: scr_cnt i scr_i zyja w petlach czekania (scr_wait_keep_n, scr_wait60), ktore woluja scr_render.
scr_restore
	ldx v_back
	lda scr_rn,x
	sta scr_rc
	txa
	asl
	asl
	asl
	asl
	asl
	asl
	sta scr_ri
srt2_l
	lda scr_rc
	beq srt2_cells
	lda #0
	jsr sb_defaults
	jsr sb_fb_dst             ; zrodlo czyste tlo, cel bufor tylny, kroki 256
	ldy scr_ri
	lda scr_rx,y
	sta scr_b
	sta scr_b+6
	lda scr_ry,y
	sta scr_b+1               ; czyste tlo: srodkowy bajt = linia
	clc
	adc scr_b+7
	sta scr_b+7
	lda scr_b+8
	adc #0
	sta scr_b+8
	lda scr_rw,y
	sta scr_b+12
	lda scr_rh,y
	sta scr_b+14
	jsr scr_emit
	inc scr_ri
	dec scr_rc
	jmp srt2_l
srt2_cells
	ldx v_back
	lda scr_pn,x
	sta scr_rc
	txa
	asl
	asl
	asl
	asl
	asl
	asl
	sta scr_ri
srt2_c
	lda scr_rc
	beq srt2_ret
	ldy scr_ri
	lda scr_plo,y
	sta scr_cell
	lda scr_phi,y
	sta scr_cell+1
	lda #0                    ; kopia
	jsr scr_bcb_cb
srt2_run                        ; nastepna komorka listy = ta + 1 w tym samym wierszu -> szerszy BCB
	lda scr_rc
	cmp #2
	bcc srt2_emit
	ldy scr_ri
	lda scr_plo+1,y
	sec
	sbc scr_plo,y
	cmp #1
	bne srt2_emit
	lda scr_phi+1,y
	cmp scr_phi,y
	bne srt2_emit
	lda scr_plo+1,y
	and #31
	beq srt2_emit             ; nowy wiersz
	lda scr_b+12
	clc
	adc #8
	sta scr_b+12
	inc scr_ri
	dec scr_rc
	jmp srt2_run
srt2_emit
	jsr scr_emit
	inc scr_ri
	dec scr_rc
	jmp srt2_c
srt2_ret
	rts

; scr_sprites: wpisy modelu tablicy sprite'ow do znacznika Y = $D0 (tryb 192 linii), od ostatniego do pierwszego
; (pierwszy na wierzchu): BCB stencil 8x16 z atlasu sprite'ow, przyciecie do 0..191 / 0..255 (Y + 1, zawiniecie
; przy Y + 1 >= 241); na mapie komorki z priorytetem pod sprite'em - stencil z czystego tla na koncu.
scr_sprites
	ldx #0
ss_term
	lda scr_sat_y,x
	cmp #$D0
	beq ss_tf
	inx
	cpx #64
	bne ss_term
ss_tf
	stx scr_nvis
	lda #0
	sta scr_nm
ss_l
	ldx scr_nvis
	jeq ss_prio
	dex
	stx scr_nvis
	lda scr_sat_y,x
	clc
	adc #1
	cmp #192
	bcc ss_in
	cmp #241
	bcc ss_l                  ; 192..240: niewidoczny
	eor #$FF                  ; zawiniecie: pominiete linie = 256 - top
	clc
	adc #1
	sta scr_skip
	lda #16
	sec
	sbc scr_skip
	sta scr_h
	lda #0
	sta scr_top
	jmp ss_x
ss_in
	sta scr_top
	lda #0
	sta scr_skip
	lda #192
	sec
	sbc scr_top
	cmp #16
	bcc ss_hh
	lda #16
ss_hh
	sta scr_h
ss_x
	lda scr_sat_x,x
	sta scr_x
	lda #0
	sec
	sbc scr_x                 ; 256 - x (x = 0 -> 0: pelne 8)
	beq ss_w8
	cmp #8
	bcc ss_ww
ss_w8
	lda #8
ss_ww
	sta scr_w
	lda scr_sat_t,x           ; zrodlo: $78800 + (kafel & $FE) * 64 + skip * 8
	and #$FE
	sta scr_q
	lsr
	lsr
	clc
	adc #$88
	sta scr_b+1
	lda scr_q
	and #2
	lsr
	ror
	ror
	sta scr_b
	lda scr_skip
	asl
	asl
	asl
	clc
	adc scr_b
	sta scr_b
	bcc ss_s1
	inc scr_b+1
ss_s1
	ldx v_back                ; cel: bufor tylny + top * 256 + x
	lda fb_mid,x
	clc
	adc scr_top
	sta scr_b+7
	lda fb_hi,x
	adc #0
	sta scr_b+8
	ldx scr_w
	dex
	stx scr_b+12
	ldx scr_h
	dex
	stx scr_b+14
	jsr scr_espr              ; BCB wprost do listy
	ldx v_back                ; prostokat do listy bufora (scr_restore 2 ramki pozniej)
	txa
	asl
	asl
	asl
	asl
	asl
	asl
	clc
	adc scr_rn,x
	tay
	lda scr_rn,x
	beq ss_rnew
	dey                       ; poprzedni prostokat: ta sama linia i wysokosc, zaczyna sie tuz za tym -> laczenie
	lda scr_ry,y
	cmp scr_top
	bne ss_rno
	lda scr_rh,y
	cmp scr_b+14
	bne ss_rno
	lda scr_x
	clc
	adc scr_w
	cmp scr_rx,y
	bne ss_rno
	lda scr_x
	sta scr_rx,y
	lda scr_rw,y
	clc
	adc scr_w
	sta scr_rw,y              ; szerokosc - 1 + szerokosc nowego
	jmp ss_rdone
ss_rno
	iny
ss_rnew
	inc scr_rn,x
	lda scr_x
	sta scr_rx,y
	lda scr_top
	sta scr_ry,y
	lda scr_b+12
	sta scr_rw,y              ; szerokosc - 1
	lda scr_b+14
	sta scr_rh,y              ; wysokosc - 1
ss_rdone
	lda scr_prio
	jeq ss_l
	jsr scr_mark_prio         ; komorki z priorytetem pod tym sprite'em
	jmp ss_l
ss_prio                         ; komorki z priorytetem: stencil czyste tlo -> bufor
; M6.4: sasiednie komorki jednego wiersza (znaczniki scr_mark) = jeden BCB (czyste tlo i bufor maja krok wiersza 256,
; wiec szerszy prostokat daje te same piksele); akcja Robotnika na mapie przechodzi przez wiele komorek z priorytetem.
; scr_mark lezy na granicy strony (SCRV + $600): mlodszy bajt adresu = mlodszy bajt komorki, kolumna = bity 0-4.
	ldx #0
ss_pl
	cpx scr_nm
	beq ss_pret
	stx scr_i
	lda scr_mlo,x
	sta scr_cell
	sta sz_p
	lda scr_mhi,x
	sta scr_cell+1
	clc
	adc #>scr_mark
	sta sz_p+1
	ldy #0
	lda (sz_p),y
	beq ss_pn                 ; komorka zdjeta juz w serii
	lda sz_p
	and #31
	beq ss_pgo                ; kolumna 0 - poczatek serii
	dec sz_p
	lda (sz_p),y              ; sasiad z lewej ze znacznikiem: seria wystartuje od niego (jest na liscie, jeszcze nie zdjety)
	tax
	inc sz_p
	txa
	bne ss_pn
ss_pgo
	ldx #$FF                  ; X = liczba komorek serii - 1
ss_prun
	tya
	sta (sz_p),y              ; znacznik zdjety
	inx
	lda sz_p
	and #31
	cmp #31
	beq ss_pemit              ; ostatnia kolumna
	inc sz_p
	lda (sz_p),y
	bne ss_prun
ss_pemit
	txa
	asl
	asl
	asl
	ora #7                    ; szerokosc - 1 = 8 * n - 1
	pha
	jsr scr_bcb_pcell         ; komorka poczatkowa scr_cell
	pla
	sta scr_b+12
	jsr scr_emit
ss_pn
	ldx scr_i
	inx
	bne ss_pl
ss_pret
	rts

; scr_mark_prio: komorki w kolumnach x>>3 .. (x+w-1)>>3 i wierszach top>>3 .. (top+h-1)>>3 z atrybutem bit 4
; -> scr_mlo/hi (raz na ramke: scr_mark)
scr_mark_prio
	lda scr_x
	lsr
	lsr
	lsr
	sta scr_c0
	lda scr_x
	clc
	adc scr_w
	sec
	sbc #1
	lsr
	lsr
	lsr
	sta scr_c1
	lda scr_top
	lsr
	lsr
	lsr
	sta scr_row0
	lda scr_top
	clc
	adc scr_h
	sec
	sbc #1
	lsr
	lsr
	lsr
	sta scr_row1
	lda scr_row0
	sta scr_rr
smk_r                           ; wiersz rr: wskazniki sz_p = scr_at + rr * 32, zp_tmp = scr_mark + rr * 32, Y = kolumna
	lda scr_rr
	lsr
	lsr
	lsr
	sta scr_cell+1
	clc
	adc #>scr_at
	sta sz_p+1
	lda scr_cell+1
	clc
	adc #>scr_mark
	sta zp_tmp+1
	lda scr_rr
	asl
	asl
	asl
	asl
	asl
	sta scr_cell              ; mlodszy bajt komorki wiersza (kolumna w bitach 0-4 - Y)
	sta sz_p
	sta zp_tmp
	ldy scr_c0
smk_c
	lda (sz_p),y
	and #$10
	beq smk_n
	lda (zp_tmp),y
	bne smk_n
	ldx scr_nm
	cpx #64
	bcs smk_n                 ; lista pelna (64 komorki) - komorka bez znacznika
	lda #1
	sta (zp_tmp),y
	tya
	ora scr_cell
	sta scr_mlo,x
	lda scr_cell+1
	sta scr_mhi,x
	inc scr_nm
smk_n
	cpy scr_c1
	beq smk_nr
	iny
	bne smk_c                 ; zawsze (kolumna <= 31)
smk_nr
	lda scr_rr
	cmp scr_row1
	beq smk_ret
	inc scr_rr
	jmp smk_r
smk_ret
	rts

; ---------------------------------------------------------------------
; scr_build_bg: cale czyste tlo z modelu komorek: 768 BCB kafel atlasu -> komorka, partie po wierszu (32 BCB).
; Wiersz 0 - pelne BCB (szablony 32 slotow listy); wiersze 1-23 - w slotach tylko zrodlo (kafel) i srodkowy
; bajt celu (wiersz * 8): pozostale pola, NEXT i koniec listy (scr_last) zostaja z wiersza 0.
; ---------------------------------------------------------------------
scr_build_bg
	lda #0
	sta scr_nd
	sta scr_cell
	sta scr_cell+1
	lda #MB_LOW
	jsr set_memac
	mwa #SCR_LIST_CPU zp_bcb
	lda #32
	sta scr_i
sbb_c0
	jsr scr_ecell
	inc scr_cell
	dec scr_i
	bne sbb_c0
	jsr scr_list_run
	mwa #scr_nt+32 sz_p       ; kafel komorki 32 (wiersz 1)
	lda #8
	sta scr_q                 ; wiersz * 8 (srodkowy bajt celu w czystym tle)
sbb_row
	mwa #SCR_LIST_CPU zp_bcb
	lda #32
	sta scr_i
sbb_c
	ldy #0
	lda (sz_p),y              ; kafel t: zrodlo ATLAS_VRAM + t * 64
	pha
	and #3
	lsr
	ror
	ror
	sta (zp_bcb),y            ; +0: (t & 3) << 6
	pla
	lsr
	lsr
	clc
	adc #[ATLAS_VRAM>>8]&$FF
	iny
	sta (zp_bcb),y            ; +1
	lda scr_q
	ldy #7
	sta (zp_bcb),y            ; +7: wiersz * 8
	inc sz_p
	bne sbb_p
	inc sz_p+1
sbb_p
	clc
	lda zp_bcb
	adc #BCB_BYTES
	sta zp_bcb
	bcc sbb_b
	inc zp_bcb+1
sbb_b
	dec scr_i
	bne sbb_c
	jsr scr_list_run
	lda scr_q
	clc
	adc #8
	sta scr_q
	cmp #192
	bne sbb_row
	rts

; ---------------------------------------------------------------------
; BCB (scr_b): +0 zrodlo (3), +3 krok Y zrodla (2), +5 krok X zrodla, +6 cel (3), +9 krok Y celu (2),
; +11 krok X celu, +12 szerokosc-1 (2), +14 wysokosc-1, +15 AND, +16 XOR, +17 kolizje, +18 zoom, +19 wzorzec,
; +20 sterowanie (tryb: 0 kopia, 1 stencil; bit 3 NEXT - ustawia scr_emit)
; ---------------------------------------------------------------------
; sb_defaults: A = tryb; kroki X 1, AND $FF, XOR/kolizje/zoom/wzorzec 0, szerokosc hi 0
sb_defaults
	sta scr_b+20
	lda #1
	sta scr_b+5
	sta scr_b+11
	lda #$FF
	sta scr_b+15
	lda #0
	sta scr_b+13
	sta scr_b+16
	sta scr_b+17
	sta scr_b+18
	sta scr_b+19
	rts

; sb_fb_dst: cel = bufor tylny (v_back), x = 0, krok Y 256; zrodlo = czyste tlo, krok 256
sb_fb_dst
	ldx v_back
	lda #0
	sta scr_b+6
	lda fb_mid,x
	sta scr_b+7
	lda fb_hi,x
	sta scr_b+8
	lda #0
	sta scr_b+9
	sta scr_b+3
	sta scr_b
	lda #1
	sta scr_b+10
	sta scr_b+4
	lda #[SCR_CLEAN>>8]&$FF
	sta scr_b+1
	lda #SCR_CLEAN>>16
	sta scr_b+2
	rts

; scr_bcb_view: czyste tlo -> bufor tylny 256x192 (kopia)
scr_bcb_view
	lda #0
	jsr sb_defaults
	jsr sb_fb_dst
	lda #255
	sta scr_b+12
	lda #191
	sta scr_b+14
	rts

; sbc_cell_xy: scr_b+6 = kolumna * 8, scr_b+7 = wiersz * 8 (komorka scr_cell: wiersz = cell >> 5)
sbc_cell_xy
	lda scr_cell
	and #31
	asl
	asl
	asl
	sta scr_b+6
	lda scr_cell+1            ; wiersz = (cell >> 5): hi * 8 + lo >> 5
	asl
	asl
	asl
	sta scr_q
	lda scr_cell
	lsr
	lsr
	lsr
	lsr
	lsr
	ora scr_q
	asl
	asl
	asl                       ; wiersz * 8 (linie / 256 B)
	sta scr_b+7
	rts

; scr_bcb_pcell: komorka scr_cell czystego tla -> ta sama komorka bufora tylnego, stencil (priorytet tla);
; scr_bcb_cb: jw. z trybem A (0 = kopia: zmieniona komorka w buforze)
scr_bcb_pcell
	lda #1
scr_bcb_cb
	jsr sb_defaults
	jsr sbc_cell_xy
	lda scr_b+6
	sta scr_b
	lda scr_b+7
	sta scr_b+1
	lda #SCR_CLEAN>>16
	sta scr_b+2
	lda #0
	sta scr_b+3
	sta scr_b+9
	lda #1
	sta scr_b+4
	sta scr_b+10
	ldx v_back
	lda scr_b+7
	clc
	adc fb_mid,x
	sta scr_b+7
	lda fb_hi,x
	adc #0
	sta scr_b+8
	lda #7
	sta scr_b+12
	sta scr_b+14
	rts

; scr_ecell: BCB komorki scr_cell wprost do listy: kafel atlasu (ATLAS_VRAM + kafel * 64, krok 8) -> czyste tlo
; (wiersz * 2048 + kolumna * 8, krok 256), kopia 8x8, NEXT
scr_ecell
	jsr sbc_cell_xy           ; scr_b+6 = kolumna * 8, scr_b+7 = wiersz * 8
	lda scr_cell
	sta sz_p
	lda scr_cell+1
	clc
	adc #>scr_nt
	sta sz_p+1
	ldy #0
	lda (sz_p),y              ; kafel t
	tax
	and #3
	lsr
	ror
	ror
	sta (zp_bcb),y            ; +0: (t & 3) << 6
	iny
	txa
	lsr
	lsr
	clc
	adc #[ATLAS_VRAM>>8]&$FF
	sta (zp_bcb),y            ; +1
	iny
	lda #ATLAS_VRAM>>16
	sta (zp_bcb),y            ; +2
	iny
	lda #8
	sta (zp_bcb),y            ; +3: krok Y zrodla 8
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda #1
	sta (zp_bcb),y            ; +5: krok X
	iny
	lda scr_b+6
	sta (zp_bcb),y            ; +6
	iny
	lda scr_b+7
	sta (zp_bcb),y            ; +7
	iny
	lda #SCR_CLEAN>>16
	sta (zp_bcb),y            ; +8
	iny
	lda #0
	sta (zp_bcb),y            ; +9: krok Y celu 256
	iny
	lda #1
	sta (zp_bcb),y
	iny
	sta (zp_bcb),y            ; +11: krok X
	iny
	lda #7
	sta (zp_bcb),y            ; +12: szerokosc - 1
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda #7
	sta (zp_bcb),y            ; +14: wysokosc - 1
	iny
	lda #$FF
	sta (zp_bcb),y            ; +15: AND
	iny
	lda #0
	sta (zp_bcb),y            ; +16..+19: XOR, kolizje, zoom, wzorzec
	iny
	sta (zp_bcb),y
	iny
	sta (zp_bcb),y
	iny
	sta (zp_bcb),y
	iny
	lda #8
	sta (zp_bcb),y            ; +20: kopia, NEXT
	jmp scr_eadv

; scr_espr: BCB sprite'a wprost do listy: zrodlo scr_b+0/1 (SPRATLAS_VRAM >> 16), krok 8; cel scr_x / scr_b+7 /
; scr_b+8, krok 256; szerokosc-1 scr_b+12, wysokosc-1 scr_b+14; stencil, NEXT
scr_espr
	ldy #0
	lda scr_b
	sta (zp_bcb),y
	iny
	lda scr_b+1
	sta (zp_bcb),y
	iny
	lda #SPRATLAS_VRAM>>16
	sta (zp_bcb),y
	iny
	lda #8
	sta (zp_bcb),y            ; +3: krok Y zrodla 8
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda #1
	sta (zp_bcb),y            ; +5
	iny
	lda scr_x
	sta (zp_bcb),y            ; +6
	iny
	lda scr_b+7
	sta (zp_bcb),y
	iny
	lda scr_b+8
	sta (zp_bcb),y            ; +8
	iny
	lda #0
	sta (zp_bcb),y            ; +9: krok Y celu 256
	iny
	lda #1
	sta (zp_bcb),y
	iny
	sta (zp_bcb),y            ; +11
	iny
	lda scr_b+12
	sta (zp_bcb),y            ; +12
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda scr_b+14
	sta (zp_bcb),y            ; +14
	iny
	lda #$FF
	sta (zp_bcb),y            ; +15
	iny
	lda #0
	sta (zp_bcb),y
	iny
	sta (zp_bcb),y
	iny
	sta (zp_bcb),y
	iny
	sta (zp_bcb),y            ; +19
	iny
	lda #9
	sta (zp_bcb),y            ; +20: stencil, NEXT
; scr_eadv: scr_last = ten BCB, zp_bcb += 21
scr_eadv
	lda zp_bcb
	sta scr_last
	lda zp_bcb+1
	sta scr_last+1
	clc
	lda zp_bcb
	adc #BCB_BYTES
	sta zp_bcb
	bcc sea_r
	inc zp_bcb+1
sea_r
scr_lim                         ; lista nie wychodzi poza okno MEMAC ($3FFF): przy przepelnieniu ostatni slot od nowa
	lda zp_bcb+1
	cmp #>[MEMAC_CPU+$2000-BCB_BYTES]
	bcc slm_r
	bne slm_b
	lda zp_bcb
	cmp #<[MEMAC_CPU+$2000-BCB_BYTES]
	bcc slm_r
	beq slm_r
slm_b
	lda scr_last
	sta zp_bcb
	lda scr_last+1
	sta zp_bcb+1
slm_r
	rts

; scr_emit: scr_b (21 B) z bitem NEXT pod (zp_bcb); zp_bcb += 21; scr_last = ten BCB (petla rozwinieta)
scr_emit
	lda zp_bcb
	sta scr_last
	lda zp_bcb+1
	sta scr_last+1
	ldy #0
	.rept 20
	lda scr_b+#
	sta (zp_bcb),y
	iny
	.endr
	lda scr_b+20
	ora #8
	sta (zp_bcb),y
	clc
	lda zp_bcb
	adc #BCB_BYTES
	sta zp_bcb
	bcc se_r
	inc zp_bcb+1
se_r
	jmp scr_lim

; scr_list_run: ostatni BCB bez NEXT, start listy SCR_LIST_VRAM, czekanie na koniec pracy blittera
scr_list_run
	lda scr_last
	sta zp_tmp
	lda scr_last+1
	sta zp_tmp+1
	ldy #20
	lda (zp_tmp),y
	and #$F7
	sta (zp_tmp),y
	ldy #VC_BL_ADR0
	lda #SCR_LIST_VRAM&$FF
	sta (zp_fx),y
	iny
	lda #[SCR_LIST_VRAM>>8]&$FF
	sta (zp_fx),y
	iny
	lda #SCR_LIST_VRAM>>16
	sta (zp_fx),y
	ldy #VC_BLT_START
	lda #1
	sta (zp_fx),y
slr_w
	lda (zp_fx),y
	and #3
	bne slr_w
	rts

; scr_pal_rgb: CRAM (kolory SMS --BBGGRR) -> v_pal_rgb (skladowa * 85, jak tools/extract_sms.py sms_rgb)
scr_pal_rgb
	ldx #0
	ldy #0
spr_l
	lda scr_cram,x
	and #3
	sty scr_q
	tay
	lda c85,y
	ldy scr_q
	sta v_pal_rgb,y
	lda scr_cram,x
	lsr
	lsr
	and #3
	tay
	lda c85,y
	ldy scr_q
	sta v_pal_rgb+1,y
	lda scr_cram,x
	lsr
	lsr
	lsr
	lsr
	and #3
	tay
	lda c85,y
	ldy scr_q
	sta v_pal_rgb+2,y
	iny
	iny
	iny
	inx
	cpx #32
	bne spr_l
	rts
c85	dta b(0, 85, 170, 255)

; scr_pal_now: v_pal_rgb -> paleta 1 nakladki od razu (kolory 0-31)
scr_pal_now
	ldy #VC_PSEL
	lda #1
	sta (zp_fx),y
	ldy #VC_CSEL
	lda #0
	sta (zp_fx),y
	ldx #0
spn_l
	lda v_pal_rgb,x
	ldy #VC_CR
	sta (zp_fx),y
	lda v_pal_rgb+1,x
	iny
	sta (zp_fx),y
	lda v_pal_rgb+2,x
	iny
	sta (zp_fx),y
	inx
	inx
	inx
	cpx #96
	bne spn_l
	rts

; =====================================================================
;  Dane z ROM-u SMS (tools/extract_ekrany.py, build/assets/ekrany)
; =====================================================================
; bfw_body (M6.5; M6.11 - przeniesione z kodu rezydentnego boot.asm): palette_fade_up do bieli - scr_call_white (boot.asm, bs_bonus)
; i dobre zakonczenie (koniec.asm)
bfw_body                        ; (00:0B60-00:0C01) bufor palety = wyswietlana (model scr_cram), sygnal, obraz wlaczony,
	ldx #31                   ; 1 + 9 IRQ, potem 4 kroki: kazda skladowa 2-bitowa < 3 -> + 1, sygnal, 10 IRQ (razem 50)
bfw_c
	lda scr_cram,x
	sta SC_TMPPAL,x
	dex
	bpl bfw_c
	lda #3
	ldx #<SC_TMPPAL_S
	ldy #>SC_TMPPAL_S
	jsr scr_signal_pal
	lda SC_REG1
	ora #$40
	sta SC_REG1
	jsr scr_wait_keep
	lda #9
	jsr scr_wait_keep_n
	lda #4
	sta scr_fstep
bfw_step
	ldy #31
bfw_col
	lda SC_TMPPAL,y
	eor #$3F                  ; bity 1 wartosci 3 (biel): skladowa rozna od 3 -> bit jej pary
	sta scr_c
	lsr
	ora scr_c
	and #$15                  ; 1 na mlodszym bicie kazdej pary, gdy skladowa < 3
	clc
	adc SC_TMPPAL,y
	sta SC_TMPPAL,y
	dey
	bpl bfw_col
	lda #3
	ldx #<SC_TMPPAL_S
	ldy #>SC_TMPPAL_S
	jsr scr_signal_pal
	lda #10
	jsr scr_wait_keep_n
	dec scr_fstep
	bne bfw_step
	rts

	icl 'scr/koniec.asm'      ; M6.11: ekrany konca gry (kod; dane w banku 36 -> RAM: ko_copy)

scr_r0       ins 'ekr_rom0.bin'      ; bank 0 ROM-u $0F0E-$1BAC (adres SMS + SR_OFS)
; M6.11: RLE tytulu i mapy 1 oraz pary kafli sprite'ow tytulu - w banku 36 (miejsce na kod ekranow konca), w RAM pod OS od
; scr_data_copy (src/scr/boot.asm: trampoliny scr_call_title / _score / _gameover, przed kazdym wejsciem do ekranow)
scr_rle_t    = SCR_RLE_T_RAM      ; ARTMAP_05_6000
scr_rle_ma   = SCR_RLE_M_RAM      ; ARTMAP_05_627E
scr_rle_mb   = SCR_RLE_M_RAM+EKR_RLE_MA ; ARTMAP_05_63F6
; (M6.8: scr_rle_w i scr_rle_g - RLE ekranu wyniku i game over - przeniesione do kodu rezydentnego, src/scr/special.asm)
; M6.8: parametry mapy 1 / mapy 2 dla scr_run_world_map (indeks scr_mapi): atlas tla (scr_unpack_atlas), pary kafli sprite'ow
; (adres, liczba), RLE warstw A ($10) i B ($00) (adres, dlugosc), paleta (adres portu danych banku 0). Mapa 2 - dane w RAM (map2_copy).
srm_atl	dta b(1, 3)
srm_spl	dta b(<scr_spr_m, <MAP2_SPR)
srm_sph	dta b(>scr_spr_m, >MAP2_SPR)
srm_spn	dta b(EKR_SPR_M_N, EKR_SPR_M2_N)
srm_ral	dta b(<scr_rle_ma, <MAP2_RLE)
srm_rah	dta b(>scr_rle_ma, >MAP2_RLE)
srm_ranl	dta b(<EKR_RLE_MA, <EKR_RLE_M2A)
srm_ranh	dta b(>EKR_RLE_MA, >EKR_RLE_M2A)
srm_rbl	dta b(<scr_rle_mb, <[MAP2_RLE+EKR_RLE_M2A])
srm_rbh	dta b(>scr_rle_mb, >[MAP2_RLE+EKR_RLE_M2A])
srm_rbnl	dta b(<EKR_RLE_MB, <EKR_RLE_M2B)
srm_rbnh	dta b(>EKR_RLE_MB, >EKR_RLE_M2B)
srm_pal	dta b(<SR_PAL_MAP1, <SR_PAL_MAP2)        ; adres SMS (scr_fade_in przelicza na adres portu)
srm_palh	dta b(>SR_PAL_MAP1, >SR_PAL_MAP2)
scr_spr_t    = SCR_SPR_T_RAM      ; pary kafli sprite'ow tytulu (4 bpp) - bank 36 -> RAM pod OS (M6.11)
scr_spr_m    ins 'ekr_spr_mapa1.bin' ; pary kafli sprite'ow mapy 1 i cyfr zyc
scr_bank_end
	.if scr_bank_end > $8000
	.error "bank 49 (ekrany) przekracza $7FFF"
	.endif
