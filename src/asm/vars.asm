; =====================================================================
;  Zmienne
; =====================================================================
vars_start
v_frame      dta a(0)
v_renders    dta a(0)
v_flips      dta a(0)
v_flip_req   dta b(0)
v_back       dta b(0)
v_late       dta b(0)
v_status     dta b(0)
v_fxseen     dta b(0)
v_minor      dta b(0)
v_bankcnt    dta b(0)
v_mainalias  dta b(0)
v_tv         dta b(0)
v_lpf        dta a(0)
v_lpf_m248   dta a(0)
v_video_on   dta b(0)
v_vid_wait   dta b(0)      ; review M6.9: flipy do wlaczenia obrazu przez NMI po przeladowaniu poziomu (game/trans.asm: vid_hold)
v_gp_on      dta b(0)      ; M6.10: lata szyby bossa SKY3 do slotu magazynu w tej liscie (game/rings.asm glass_req -> render/frame.asm glass_store)
v_gp_tx      dta b(0)      ; kolumna / wiersz kafla laty w bloku (0-2; 2 x 2 kafle)
v_gp_ty      dta b(0)
v_gp_slot    dta b(0)      ; slot magazynu bloku (BLKMAP_RAM)
v_gp_t       dta b(0, 0, 0, 0)   ; 4 kafle atlasu tla (lewy gorny, prawy gorny, lewy dolny, prawy dolny)
v_gl_mask    dta a(0)      ; M6.10: bit k = lata szyby k (0-14) nalozona na magazyn (model obrazu tools/m2_test.py; tele_reload zeruje)
v_front      dta b(0)      ; M6.10: 1 = przednie wpisy 0-20 tablicy sprite'ow uzywane bez wody (SKY2 - chmury $30; lv_select: sky_stash)
v_layfull    dta b(0)      ; review M6.9: 1 = lay_pages kopiuje caly uklad z banku (start z level_boot; game/level.asm)
v_cyc_on     dta b(0)
v_cyc_timer  dta b(0)
v_cyc_idx    dta b(0)
v_nmi_cnt    dta b(0)      ; licznik petli palety (tylko NMI)
v_nblocks    dta b(0)
v_pblevel    dta b(0)      ; M6.3: PORTB banku danych poziomu (35 GHZ1, 55 GHZ2; game_code.asm: lv_select)
v_pbatlas    dta b(0)      ; M6.5: PORTB banku atlasu kafli tla (33 GHZ, 61 etapy specjalne, 1 Bridge; lv_select)
v_pbzspr     dta b(0)      ; M6.6: PORTB banku sprite'ow strefy (kafle $2000, paleta $1FB0: 39 GHZ i etapy specjalne, 3 Bridge; lv_select)
v_pbobjz     dta b(0)      ; M6.9: PORTB banku obiektow strefy (11 - BRI/JUN/LAB, 2 - SBZ/SKY; lv_select: ldr_need; objz_call, stuby zc_*; machine_init zeruje)
; M7.2: identyfikator obrazu roli (src/ldr/ldr.asm ldr_need): +LR_LEVEL poziom, +LR_ATLAS atlas, +LR_ZSPR sprite'y strefy, +LR_OBJZ obiekty strefy.
; XEX: = v_pblevel..v_pbobjz (PORTB banku rezydentnego); nosnik: id obrazu (bank slotu dowolny). Porownania z LI_* (build/assets/ldr_tables.inc)
; zastepuja dawne porownania v_pb* ze stalymi PB_* stref (game_code.asm sky_stash, game/level.asm, render/rings.asm).
v_img        :4 dta b(0)
	.if v_pbatlas<>v_pblevel+LR_ATLAS || v_pbzspr<>v_pblevel+LR_ZSPR || v_pbobjz<>v_pblevel+LR_OBJZ
	.error "v_pblevel, v_pbatlas, v_pbzspr, v_pbobjz musza lezec po kolei wg LR_* (ldr_need: sta v_pblevel,x)"
	.endif
v_special    dta b(0)      ; M6.5: 1 = etap specjalny ($1C+): grafika i paleta sprite'ow z banku 59 (render/sprites.asm)
v_cycspd     dta b(10)     ; M6.5: cykl palety tla: ramki na krok i liczba wariantow z naglowka poziomu (load_palette)
v_cyccnt     dta b(3)
v_lvh        dta b(0)      ; M6.3: wysokosc ukladu w blokach (naglowek poziomu; render/load.asm: lay_tables)
v_lvhm1      dta b(0)      ;       wysokosc - 1 (256 wierszy: $FF; v_lvh = $FF)
v_lvhl       dta b(0)      ; M6.7: wysokosc & $FF (256 -> 0) - petle po wierszach (prio_win_init)
v_lvcols     dta b(0)      ;       szerokosc ukladu & $FF (256 -> 0)
v_store_lines dta a(0)
v_blit_last  dta a(0)
v_blit_max   dta a(0)
v_cpu_last   dta a(0)
v_cpu_max    dta a(0)
v_idle_last  dta a(0)
v_idle_min   dta a(0)
v_joy        dta b(0)
v_trig       dta b(0)
v_cam_mode   dta b(0)      ; 0 auto, 1 joystick, 2 stop, 3 za Sonikiem, 4 kamera gry (testcam.asm)
v_camx       dta a(0)
v_camy       dta a(0)
v_vx         dta b(0)
v_vy         dta b(0)
v_sx         dta b(0)
v_sy         dta b(0)
v_svx        dta b(0)
v_svy        dta b(0)
v_bx         dta b(0)
v_by         dta b(0)
v_rbx        dta b(0)
v_rby        dta b(0)
v_ring_ok    dta b(0)
v_reloads    dta b(0)
v_slot       dta b(0)
v_tgt        dta b(0)      ; potok: bufor docelowy budowanej listy
v_lbuild     dta b(0)      ; komplet listy w budowie (0/1)
v_lrun       dta b(0)      ; komplet listy wykonywanej przez blitter
v_sbase      dta b(0)      ; baza KIND_RAM kompletu v_lbuild (0 / N_BLK_SLOTS) - M4.2
v_lcpu       dta a(0)      ; M4.2: adres CPU slotu 0 kompletu v_lbuild (w oknie v_mb_list)
v_mb_list    dta b(0)      ; M4.2: okno MEMAC kompletu v_lbuild (MB_LOW / MB_BUILD)
ls_slot      dta b(0,0)    ; per komplet: pierwszy slot listy i parametry narysowanej klatki
ls_camx_lo   dta b(0,0)
ls_camx_hi   dta b(0,0)
ls_camy_lo   dta b(0,0)
ls_camy_hi   dta b(0,0)
ls_sx        dta b(0,0)
ls_sy        dta b(0,0)
ls_nblk      dta b(0,0)
v_dcamx      dta a(0)      ; narysowana klatka (po zakonczeniu listy; m2_test.py)
v_dcamy      dta a(0)
v_dsx        dta b(0)
v_dsy        dta b(0)
v_dnblk      dta b(0)
v_wait_last  dta a(0)      ; iteracje czekania na liste (17 cykli)
v_free_last  dta a(0)      ; wolne cykle CPU ostatniej ramki
v_free_min   dta a(0)
v_reload_now dta b(0)      ; w tej ramce bylo pelne przeladowanie pierscienia
; gra (game/): zrodlo wejscia, krok petli poziomu, trace
v_input_mode dta b(0)      ; IN_JOY / IN_DEMO / IN_SCRIPT (test ustawia w cfg_point)
v_step       dta a(0)      ; krok petli poziomu SMS: -16 start, -15..0 rozgrzewka, 1.. ticki
v_trace_on   dta b(0)      ; 1 = zapis rekordow trace'u (test ustawia w cfg_point)
v_tr_limit   dta a(0)      ; liczba rekordow do zapisania
v_tr_count   dta a(0)
v_tr_bank    dta b(0)      ; indeks w tablicy bankow trace'u tr_bank_tab (m3_trace.inc)
v_tr_nbanks  dta b(0)      ; M6.9: liczba bankow bufora trace'u (TR_NBANKS + wolne banki stref - m3_test, tools/m3_trace.py banki_trace)
v_tr_ptr     dta a(0)
v_tr_kcnt    dta b(0)      ; M4.0: rekordy do nastepnej klatki kluczowej
v_tr_mask    dta b(0,0,0,0) ; M4.0: maska slotow zapisywanych w rekordzie
v_obj_dirty  dta b(0,0,0,0) ; M4.0: sloty uruchomione / utworzone w kroku (bit s = slot s; zeruje trace_record)
; --- M4.1 obiekty (game/objcom.asm, obj/dispatch.asm, game/level.asm) ---
v_dirty_t    dta b(0)      ; obj_dirty / spawn_object: robocza
v_rnd_l      dta b(0)      ; random_A: robocze (L, H)
v_rnd_h      dta b(0)
v_rng_seed0  dta a(0)      ; ziarno RNG na start gry (game_reset); test ustawia ziarno z kroku -16 referencji
v_obj_filt_on dta b(0)     ; test (--obiekty): 1 = w slotach 1-31 zostaja tylko typy z maski v_obj_filt
v_obj_filt   :32 dta b(0)  ; maska typow (bit t & 7 bajtu t >> 3)
v_mapbuf     :18 dta b(0)  ; M6.6: kopia mapy sprite'ow z banku obiektow strefy (objz_mapcopy)
v_obj_todo   dta b(0)      ; wywolania funkcji obiektow bez przekladu (zaslepka obj_stub)
v_obj_todo_id dta b(0)     ; typ ostatniego z nich
v_hts_x      dta b(0)      ; draw_hud: x znaku w tablicy sprite'ow (draw_sprite_text)
v_hts_y      dta b(0)
v_lo_n       dta b(0)      ; load_object_list: licznik slotow
v_lo_bit     dta b(0)      ; load_object_list: bit typu w masce filtra
v_tf_ptr     dta a(0)      ; adres SMS tablicy flag blokow strefy (PTRLUT_level_tile_flags[g_tile_flags_index])
v_tr_irq     dta b(0)      ; naglowek rekordu biezacego kroku
v_tr_in      dta b(0)
v_tr_int     dta b(0)
v_tr_fl      dta b(0)
v_rom_reads  dta b(0)      ; obj_tile_type: odczyty bloku spod adresu ROM SMS (poza ukladem - typ 0)
v_sonic_todo dta b(0)      ; sonic_objfunc: wejscia w sciezki bez przekladu (zaslepki, game/sonic.asm)
v_sonic_todo_id dta b(0)   ; ostatnia zaslepka (TODO_*)
v_sonic_todo_spec dta b(0) ; ostatni kod bloku specjalnego bez przekladu
; --- M3.7 smierc, czas, restart (game/death.asm, game/trans.asm, render/fade.asm) ---
v_lvl_exit   dta b(0)      ; kod wyjscia z poziomu + 1 (EXIT_*), 0 = gra trwa
v_lvl_todo   dta b(0)      ; ticki z timerami bez przekladu (tablica konca, blysk palety, blyskawice)
v_bcd        dta b(0)      ; tick_game_time: robocza
v_segment    dta b(0)      ; numer startu poziomu (trace: kroki + 100000 * segment)
v_trans      dta b(0)      ; 1 = przejscie po wyjsciu z poziomu
v_trans_cnt  dta b(0)      ; ramki przejscia
v_hide_spr   dta b(0)      ; 1 = bez obiektow w liscie (po wygaszeniu)
v_tbw        dta b(0)      ; M6.5: throb_obj: szerokosc blitu zderzaka
v_throb      dta b(0)      ; M6.5: 1 = w tym kroku zderzak etapu specjalnego (wpisy 0-7 tablicy sprite'ow) zamiast Sonica (sh_bumper)
v_fade_sub   dta b(0)      ; pal_fade: odejmowana wartosc skladowej
v_fade_n     dta b(0)
; --- M3.7c HUD (game/hud.asm: migawka; render/hud.asm: stan plotna) ---
v_hud_fl     dta b(0)      ; b0 pierscienie, b1 czas, b2 pozycja etapu specjalnego
v_hud_l      dta b(0)      ; kafel cyfry zyc
v_hud_r      dta b(0)      ; pierscienie BCD
v_hud_m      dta b(0)      ; minuty
v_hud_s      dta b(0)      ; sekundy BCD
v_hudc_st    dta b(0)      ; 0 = plotno do narysowania w calosci
v_hudc_l     dta b(0)      ; stan plotna (jak v_hud_*)
v_hudc_r     dta b(0)
v_hudc_m     dta b(0)
v_hudc_s     dta b(0)
v_hud_x      dta b(0)      ; robocze
v_hud_col    dta b(0)
v_hud_cv     dta b(0)
v_ring_art   dta b($FF)    ; klatka grafiki pierscienia wgrana przez gre (0-5; $FF = kafle strefy) - game/rings.asm
v_patch_on   dta b(0)      ; 1 = blok (v_patch_c, v_patch_r) do ponownego blitu (lata ekranu po zebraniu)
v_patch_c    dta b(0)
v_patch_r    dta b(0)
v_tp_on      dta b(0)      ; M4.7: lata kafli tla (kwiaty) do nalozenia w tej liscie (irq_tile_patch -> tile_patch)
v_tpx        dta a(0)      ; pozycja laty w poziomie (x & $FFF8, y & $FFF8; 2 x 2 kafle 8x8)
v_tpy        dta a(0)
v_tpt        :4 dta b(0)   ; numery kafli tla: lewy gorny, prawy gorny, lewy dolny, prawy dolny
v_tpa        dta b(0)      ; M6.4: bity 0-3: kafel laty z atlasu sprite'ow (atrybut b0 = kafle 256+: kapsula GHZ3), 0 - atlas tla
v_tp_todo    dta b(0)      ; laty spoza obslugi (inne dane niz kwiaty GHZ, atrybuty != 0) - M6
v_tov        :64 dta b(0)  ; M4.7: nakladki - 8 x (x lo, x hi ($FF = wolne), y lo, y hi (b0-3; b4-7 = v_tpa), 4 kafle): laty w pierscieniu tla
v_tov_n      dta b(0)      ; nastepna pozycja do zastapienia, gdy brak wolnej
v_ring_drawn dta b($FF)    ; renderer: klatka pierscienia narysowana w pierscieniu tla (render/rings.asm)
v_nring      dta b(0)      ; build_frame_list: BCB pierscieni w liscie
v_full       dta b(0)      ; build_frame_list: 1 = pelne przeladowanie okna w tej liscie
v_ld_col     dta b(0)      ; build_frame_list: doladowana kolumna blokow ($FF = brak)
v_ld_row     dta b(0)      ; build_frame_list: doladowany wiersz blokow ($FF = brak)
v_rcnt       dta b(0)      ; render/rings.asm: licznik kolumn okna
v_er_src     dta b(0)      ; render/rings.asm: bajt srodkowy zrodla klatki pierscienia
v_er_mid     dta b(0)      ; render/rings.asm: czesc dst zalezna od wiersza (mid)
v_er_hi      dta b(0)      ; render/rings.asm: bank dst (pierscien tla)
; --- M3.6 obiekty (render/sprites.asm) ---
v_mb         dta b(0)      ; load_sprite_data: biezacy bank MEMAC
v_sonic_fr   dta b(0)      ; sonic.asm: klatka grafiki Sonica (D w objfunc_00_sonic)
v_sonic_base dta b(0)      ; sonic.asm: baza grafiki $40 (w prawo) / $70 (w lewo)
v_spk        dta b(0)      ; sonic.asm: iskra pierscienia w tym ticku (b7) i licznik po zmniejszeniu (b0-6)
v_isp        dta b(0)      ; M4.5: iskra niesmiertelnosci w tym ticku - kafel ($94 / $96) albo 0
v_ispx       dta a(0)      ; pozycja w poziomie (tmp_00 + tmp_04, tmp_02 + tmp_06 przy draw_sprite)
v_ispy       dta a(0)
v_monk       :16 dta b(0)  ; M4.5: ikona monitora k zapisana na pozycji p = licznik & 15 kafli $5C-$5F ($FF - grafika strefy)
v_monk_ap    :16 dta b(0)  ; stan kafli $5C-$5F w atlasie VRAM (mon_tiles)
v_mondirty   dta b(0)      ; 1 = v_monk zmienione od ostatniego mon_tiles
v_sign_req   dta b(0)      ; M4.8: 1 = grafika tabliczki do kafli $00-$7F atlasu sprite'ow (frame_done)
v_fi         dta b(0)      ; M6.8: front_objs - przesuniecie wpisu (3 * numer)
v_water      dta b(0)      ; M6.8: $80 = poziom z woda (naglowek iy_06 b7; render/water.asm)
v_wk         dta b(0,0)    ;       linia podzialu XDL listy (komplet 0 / 1): 0 - caly ekran pod woda, 192 - bez wody
v_wx         dta b(0,0)    ;       ostatnia linia zapisana w XDL bufora 0 / 1 ($FF - do zapisania)
v_flash_req  dta b(0)      ; M6.4: migotanie palety (handle_palette_flashing): 1 = kolor CRAM do zmiany w tej liscie
v_flash_idx  dta b(0)      ;       indeks koloru (b7: paleta sprite'ow)
v_flash_odd  dta b(0)      ;       1 = kolor migotania, 0 = kolor palety
v_late_irq   dta b(0)      ; M6.4: liczba IRQ (irq_extra) do wykonania po obj_run_all w tym ticku (load_art bossa)
v_art_req    dta b(0)      ; M6.4: 1 = grafika bossa GHZ3 (bank 59), 2 = grafika zwierzat i kapsuly do kafli $00-$7F (frame_done)
v_sign_art   dta b(0)      ; 1 = w atlasie grafika tabliczki (model obrazu; restart przywraca strefe)
v_sign_pal   dta b(0)      ; 2 -> 1 -> 0: paleta tabliczki w frame_done po nastepnej liscie
v_pal_which  dta b(0)      ; M6.4: paleta do wgrania po v_sign_pal: 0 - tabliczki (bank 47), 1 - bossa (bank 59)
v_zone_req   dta b(0)      ; 1 = przywrocenie grafiki sprite'ow strefy $00-$7F (restart po tabliczce)
v_irq_in     dta b(0)      ; stan kontrolera ticku (read_input) - IRQ w load_art
v_spr_todo   dta b(0)      ; obiekty bez przekladu w rendererze (mapa do gory nogami, klatka spoza Sonica)
v_oslot      dta b(0)      ; nastepny slot obiektu
v_nobj       dta b(0)      ; obiekty w liscie (prostokaty or_*)
v_oi         dta b(0)
v_oy         dta b(0)      ; prostokat obiektu na ekranie (v_oy, v_ow, v_oh; M7.5: v_ox w ZP - kernel/mem.inc)
v_ow         dta b(0)
v_oh         dta b(0)
v_osrc       dta b(0,0,0)  ; zrodlo obiektu w VRAM
v_ostride    dta b(0)
v_ostepx     dta b(0)
v_fmid       dta b(0)      ; obraz klatki Sonica: bajt srodkowy, starszy (b7 = odbicie)
v_fhi        dta b(0)
v_sx16       dta a(0)      ; pozycja ekranowa (16 bit ze znakiem)
v_c0         dta b(0)      ; pierwsza / ostatnia widoczna kolumna 8 px Sonica
v_c1         dta b(0)
v_skip       dta b(0)      ; clip_rows: pominiete gorne linie
v_hgt        dta b(0)
v_tmp        dta b(0)
v_px         dta a(0)      ; spr16: pozycja w poziomie (M7.5: v_tile, v_sy16 w ZP - kernel/mem.inc)
v_py         dta a(0)
or_x         :N_RECTS dta b(0) ; prostokaty priorytetu tla - N_RECTS
or_y         :N_RECTS dta b(0)
or_w         :N_RECTS dta b(0)
or_h         :N_RECTS dta b(0)
; --- M4.2 sprite'y obiektow (render/objspr.asm) i grupy wpisow (obj/dispatch.asm) ---
v_sj3        dta b(0)      ; M4.9a: indeks wpisu tablicy sprite'ow (3 j) w petli obj_sprites
; M7.5: v_sk, v_sj, v_skend w ZP (kernel/mem.inc); v_sslot usuniety - slot = SLOT_SPR + v_sk - set_skind
v_spr_first  dta b(0)      ; pierwszy wpis obiektow (licznik po HUD-zie, game/hud.asm)
v_hudk       :9 dta b(0)   ; M4.9a: pamiec HUD-u (game/hud.asm): klucz - zycia, pierscienie, iy_05 b2, minuty, sekundy,
v_hudk_ok    dta b(0)      ; iy_07 b5, poziom, poczatek wpisow, licznik; 1 = pamiec wazna; koniec wpisow (wskaznik)
v_hudk_end   dta b(0)      ; i licznik sprite'ow po HUD-zie
v_hudk_cnt   dta b(0)
v_spr_used   dta b(0,0)    ; per komplet: koniec slotow obszaru uzytych w ostatniej liscie
v_spr_drop   dta b(0)      ; wpisy pominiete (brak slotow)
v_ngrp       dta b(0)      ; grupy wpisow w ticku
v_grp_s      :N_GROUPS dta b(0) ; mlodszy bajt wskaznika tablicy sprite'ow na poczatku grupy
v_grp_e      :N_GROUPS dta b(0) ; i na koncu
v_gi         dta b(0)
v_gend       dta b(0)      ; koniec grupy (mlodszy bajt wskaznika)
v_gx0        dta b(0)      ; obwiednia grupy: x0, x1 (16 bit), y0, y1 (16 bit ze znakiem)
v_gx1        dta a(0)
v_gy0        dta a(0)
v_gy1        dta a(0)
v_gcx        dta b(0)
v_gcy        dta b(0)
v_nblk       dta b(0)
v_nblk_max   dta b(0)
; M7.5: v_fbm, v_fbh w ZP (kernel/mem.inc)
v_rx         dta a(0)
v_ry         dta b(0)
v_xs         dta b(0)
v_ys         dta b(0)
v_w1         dta b(0)
v_w2         dta b(0)
v_h1         dta b(0)
v_h2         dta b(0)
v_pslot      dta b(0)
v_npc        dta b(0)
v_npr        dta b(0)
pc_col       dta b(0,0)
pc_lx        dta b(0,0)
pc_w         dta b(0,0)
pc_scr       dta b(0,0)
pr_row       dta b(0,0)
pr_ly        dta b(0,0)
pr_h         dta b(0,0)
pr_scr       dta b(0,0)
main_save0   dta b(0)
main_save1   dta b(0)
; --- M6: paleta ramki ekranow (src/scr/ekrany.asm) wgrywana przez NMI razem z flipem ---
v_pal_req    dta b(0)      ; 1 = przy najblizszym flipie kolory 0-31 palety 1 z v_pal_rgb
v_blank_req  dta b(0)      ; 1 = flip na XDL pustej linii (XDLB_VRAM, obraz VDP wylaczony), bez zmiany v_back
v_pal_rgb    :96 dta b(0)  ; 32 x (R, G, B)
vars_end
; test_banks_n (kernel/hw.asm): 2 bajty kazdego testowanego banku, indeks = numer iteracji. XEX i sonic-ram (1088K): do 64 bankow;
; M7.3 cart / ATR (320K): 16 bankow - 96 B mniej (TB_MAXN w kernel/mem.inc - asercje n <= TB_MAXN w miejscach wywolan)
save0        .ds TB_MAXN
save1        .ds TB_MAXN
