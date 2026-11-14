; =====================================================================
;  koniec.asm - M6.11: ekrany konca gry (kod w banku 49 = PB_SCR, razem z src/scr/ekrany.asm)
;
;  Przeklad z dezasemblacji (bank 0 ROM-u SMS, tylko material referencyjny):
;   update_signpost_timer@go_to_next_level od 00:1FC7 (res 5, iy_00) i @teleport_to_next (00:201C),
;   main@run_this_level (00:1CBD-00:1CDB: fade_screen_to_black, clear_sprite_table, 60 ramek, rst $20),
;   load_and_run_level (00:1CED-00:1D0E: naglowek poziomu $13 = 0 -> run_ending_and_credits),
;   run_ending_and_credits (00:258B-00:2715) z petla @end_of_credits_infloop (00:2715),
;   wait_BC_frames_while_updating_credits_sprites (00:2718), wait_BC_frames_for_pre_credits_delay (00:2745),
;   draw_credits_sprite (00:275A), run_credits_text_sequence (00:2795-00:2824),
;   handle_level_score_screen dla g_level = $13 -> handle_final_score_screen (00:172F-00:185F),
;   draw_final_bonus_value_for_BC_frames (00:1860-00:1906), draw_tally_screen_lives (00:1ACA, pozycja dla $13),
;   add_CHL_points_to_score_in_BCD (00:39D8), fade_screen_down_to_palette (00:0AAE).
;  Gotowe procedury ekranow (ekrany.asm / boot.asm): scr_init, scr_wait0 (res 0 + wait_until_irq_ticked),
;  scr_wait_keep(_n), scr_fade_to_black (00:0A40), scr_fade_in (palette_fade_in_banks_01_02 00:0B50), bfw_body
;  (palette_fade_up do bieli 00:0B60), scr_signal_pal, scr_print_ff, scr_put_cell, scr_unpack_tilemap, scr_dss
;  (draw_sprite_string), scr_dst / sdt_text (draw_sprite_text), scr_bcd_str (build_BCD_FFstr), scr_bcd_adc /
;  sap_add (BCD), scr_clear_sprite_table, scr_wait60, scr_load_begin / scr_build_bg / scr_prefill,
;  scr_load_sprites, scr_unpack_atlas (rezydentne), scr_skip_a, scr_irqemu, scr_render.
;
;  Model jak inne ekrany: zmienne gry w lustrze RAM SMS, VDP jako model w RAM pod OS (scr_nt, scr_at, scr_sat_*,
;  scr_cram), ladowanie grafiki od razu, a przerwania oryginalu w czasie ladowania (random_A) jako stale KO_K*
;  (do zmierzenia referencja Mesena: tabele ko_kn / ko_kp nizej) z czasem wyrownanym do oryginalu (ko_load_end).
;
;  Dane:
;   - w banku (na koncu pliku): koniec_r0.bin (ROM $2825-$2AF5: FFstr szmaragdu, PAL3_ending_tally, sprite'y
;     napisow, skrypt, PAL3_credits - adres portu = adres SMS + KO_OFS), koniec_spin.bin (LUT 00:241D);
;   - w RAM (KO_RAM, kopia z banku przez kod rezydentny przed wejsciem): koniec_ram.bin - RLE map 6830 / 69A9 /
;     6C61 i pary kafli sprite'ow (A: cyfry $80-$92 i szmaragd $5C/$5E, B: 22 pary napisow z ART_09_4B0A);
;   - napisy FF wyniku koncowego (00:1907-00:19B3) i tablice 20000 / 5000 (00:19AE / 00:19B1) - z ekr_rom0.bin
;     (scr_r0, adres SMS + SR_OFS).
;  Palety ROM-u spoza ekr_rom0.bin (PAL3_ending_tally 00:2828, PAL3_credits 00:2AD6): scr_sms_ptr i scr_fade_in
;  (i ko_fade_down przez scr_sms_ptr) przeliczaja adres SMS przez + SR_OFS, wiec port podaje "adres SMS" = adres portu - SR_OFS (KO_PAL_TALLY_S,
;  KO_PAL_CRED_S; < $C000, czyli traktowany jak ROM - sprawdzone na koncu pliku). Roznica stanu RAM SMS: wartosc
;  g_SIG00b3_palette_addr / g_current_displayed_palette_0/1 / tmp_06 (oryginal: $2828 / $2AD6).
;
;  Dodatek portu (roznica - docs/plan-m6.md 15.10 decyzja 1): w petli @end_of_credits_infloop przycisk 1/2
;  (wcisniety po puszczeniu) konczy ko_seq_end (rts) - kod rezydentny robi zimny start (tytul).
; =====================================================================
	icl 'koniec.inc'          ; build/assets/ekrany (tools/extract_koniec.py)

; --- lustro RAM SMS: nazwy spoza game/sms.inc ---
KO_BONUS     = $D2FF+SMS_RAM   ; (3) g_ending_special_bonus_BCD_big_endian (00:177B): premia specjalna BCD (x 10 000 pkt)
KO_CRED      = $D322+SMS_RAM   ; (12) g_credits_sprites (00:26DA): 4 x [slowo adresu SMS wpisu animacji, licznik]

; --- dane ---
KO_RAM       = LAYOUT_RAM      ; blok koniec_ram.bin w RAM (3305 B; uklad poziomu po poziomie $12 niepotrzebny), za nim koniec_spin.bin
                               ; (bank 36 $1000 -> ko_copy w src/scr/boot.asm)
ko_rle_a     = KO_RAM+KO_RLE_A_OFS ; ARTMAP_05_6830 (obraz konca)
ko_rle_b     = KO_RAM+KO_RLE_B_OFS ; ARTMAP_05_69A9 (obraz po bieli - dobre zakonczenie)
ko_rle_c     = KO_RAM+KO_RLE_C_OFS ; ARTMAP_05_6C61 (napisy)
ko_spr_a     = KO_RAM+KO_SPR_A_OFS ; pary kafli sprite'ow: cyfry $80-$92, szmaragd $5C / $5E
ko_spr_b     = KO_RAM+KO_SPR_B_OFS ; pary kafli sprite'ow napisow (ART_09_4B0A)
ko_spin      = KO_RAM+KO_RAM_SIZE ; LUT_ending_chaos_emerald_spin_animation (00:241D, 366 B)
ko_r0        = KO_R0_RAM       ; bank 0 ROM-u $2825-$2AF5 (bank 36 $2000 -> RAM pod OS $DA00, ko_copy)
KO_OFS       = ko_r0-KO_R0_FROM ; adres portu = adres SMS (bank 0 $2825-$2AF5) + KO_OFS
KO_FFEM      = KO_OFS+$2825    ; FFstr_chaos_emerald_or_monitor_image: $5C $5E $FF
KO_PAL_T     = KO_OFS+$2828    ; PAL3_ending_tally (adres portu)
KO_SCRIPT    = KO_OFS+$2905    ; credits_text_sequence_script_data
KO_PAL_C     = KO_OFS+$2AD6    ; PAL3_credits (adres portu)
KO_PAL_TALLY_S = [KO_PAL_T-SR_OFS]&$FFFF ; "adres SMS" dla scr_signal_pal / scr_sms_ptr (IRQ, ko_fade_down, scr_fade_to_black)
KO_PAL_CRED_S  = [KO_PAL_C-SR_OFS]&$FFFF ; jw. dla scr_fade_in (tmp_06 + SR_OFS = KO_PAL_C)
KO_SR        = scr_r0-EKR_R0_FROM ; = SR_OFS: napisy FF wyniku koncowego w ekr_rom0.bin

; --- zmienne (RAM pod OS, SCRV: wolne $B62-$BFF) ---
ko_bc        = SCRV+$B70       ; (2) licznik ramek (bc) - ko_ff, ko_wcs
ko_cnt       = SCRV+$B72       ; licznik petli (b)
ko_cnt2      = SCRV+$B73       ; licznik par szmaragdow / przewiniec
ko_lp        = SCRV+$B74       ; (2) wskaznik w LUT obrotu szmaragdow (hl)
ko_x         = SCRV+$B76       ; x sprite'a (c)
ko_pc        = SCRV+$B77       ; add_CHL_points: C (bajt D2BB)
ko_pd        = SCRV+$B78       ;                 D (bajt D2BC)
ko_pe        = SCRV+$B79       ;                 E (bajt D2BD)
ko_c         = SCRV+$B7A       ; premia specjalna w budowie (c, 00:1734-00:177A)
ko_dst       = SCRV+$B7B       ; (2) przewijanie: komorka celu poczatku wiersza
ko_r         = SCRV+$B7D       ; przewijanie: licznik wierszy
ko_k         = SCRV+$B7E       ; przewijanie: licznik komorek
ko_rel       = SCRV+$B7F       ; dodatek portu: 1 = przycisk puszczony po koncu skryptu
ko_good      = SCRV+$B80       ; 1 = dobre zakonczenie (szmaragdy >= 6 przy obrazie konca; ko_final zeruje licznik szmaragdow)

; stale ladowania (przerwania oryginalu w czasie ladowania - zmierzone Mesenem: tools/m6_ekrany_test.py --koniec, referencje
; k3end / k3dobry PAL i NTSC; docs/plan-m6.md 15.13): [NTSC] i [PAL], indeks KO_K*
KO_K1        = 0               ; 00:2597 -> 00:25D8: load_art ART_0C_0000 + ARTMAP_05_6830 (obraz wylaczony)
KO_K2        = 1               ; 00:266B (ostatni wait palette_fade_up) -> 00:0AE3: ARTMAP_05_69A9 (obraz bialy)
KO_K3        = 2               ; 00:26A8 (ostatni wait 120 ramek) -> 00:2721: load_art ART_0C_1801, ART_09_4B0A,
                               ; ARTMAP_05_6C61 (obraz wlaczony, paleta czarna)
KO_K3G       = 3               ; jw. po dobrym zakonczeniu: oryginal o 1 IRQ dluzej (m6w-k3dobry-pal: inny stan sterownika muzyki w IRQ -
                               ; ladowanie zaczyna sie po wait w tej samej fazie ramki)
ko_kn	dta b(15, 1, 23, 25)      ; NTSC - m6w-k3end-ntsc (obraz konca w IRQ 159), K2, K3G - m6w-k3dobry-ntsc
ko_kp	dta b(12, 1, 19, 20)      ; PAL  - m6w-k3end-pal (obraz konca w IRQ 156 od wyjscia z $12, napisy) i m6w-k3dobry-pal (K2, K3G)

; =====================================================================
;  ko_seq_end (tablica skokow banku 49: +15): od wyjscia z poziomu $12 (EXIT_TONEXT, g_level = $13 juz po
;  @teleport_to_next w game/death.asm ust_tnext) do konca napisow i petli koncowej.
;  Wejscie: boot_cold = 0, machine_init zrobiony, blok koniec_ram.bin skopiowany do KO_RAM, scr_irq = 0 w ramce
;  wyjscia z poziomu (jak scr_seq_score: pierwsze fade_screen_to_black 00:1FC4 - 41 IRQ - zrobil obraz trans bez
;  random_A). Wyjscie (rts): dodatek portu - przycisk w petli koncowej; dalej zimny start w kodzie rezydentnym.
; =====================================================================
ko_seq_end
	jsr scr_init
	lda #41                   ; fade_screen_to_black (00:1FC4): 41 IRQ - obraz zrobil trans bez random_A
	jsr scr_skip_a
	lda iy_00                 ; res 5, iy_00 (00:1FC8); bit 1 (tablica sprite'ow w IRQ) - z load_and_run_level poziomu $12
	and #$D7                  ; (00:1D1D); bit 3 (paleta czeka) - skasowany przez IRQ wygaszania
	ora #$02
	sta iy_00
	; stan palet po pierwszym wygaszaniu (port go nie prowadzi w grze): bufor tymczasowy czarny (4 kroki -1 z dowolnej
	; palety), wyswietlane palety = bufor (load_palettes_IRQ 00:0566: cur0 = $D3BC, cur1 = $D3CC)
	ldx #31
	lda #0
kn_se_c
	sta SC_TMPPAL,x
	dex
	bpl kn_se_c
	lda #<SC_TMPPAL_S
	sta SC_CURPAL0
	sta g_SIG00b3_palette_addr
	lda #<[SC_TMPPAL_S+16]
	sta SC_CURPAL1
	lda #>SC_TMPPAL_S
	sta SC_CURPAL0+1
	sta SC_CURPAL1+1
	sta g_SIG00b3_palette_addr+1
	lda #3
	sta g_SIG00b3_palettes_present
	; @teleport_to_next (00:201C): g_level + 1 - zrobione w game/death.asm (ust_tnext), A = $FF -> main@run_this_level
	jsr scr_fade_to_black     ; 00:1CBD: 41 IRQ (czern -> czern)
	jsr scr_clear_sprite_table ; 00:1CC0
	jsr scr_wait60            ; @force_level_start_delay (00:1CCF, iy_06 b4 = 0): 60 ramek i rst $20 (00:1CDA)
	; load_and_run_level (00:1CED): level_headers_rel[$13] = 0 -> jp z, run_ending_and_credits (00:1D0E) bez IRQ

; ---------------------------------------------------------------------
; ko_run: run_ending_and_credits (00:258B)
; ---------------------------------------------------------------------
ko_run
	lda #0
	sta ko_good
	lda SC_REG1
	and #$BF                  ; obraz wylaczony (00:258B)
	sta SC_REG1
	jsr scr_wait0             ; 00:2597
	lda #0
	sta g_vdp_scroll_x        ; 00:259B
	sta g_vdp_scroll_y
	lda #3                    ; signal_load_palettes PAL3_ending_tally, tlo i sprite'y (00:25A6)
	ldx #<KO_PAL_TALLY_S
	ldy #>KO_PAL_TALLY_S
	jsr scr_signal_pal
	; load_art ART_0C_0000 -> VRAM $0000 (00:25B1), unpack_art_tilemap_into_vram ARTMAP_05_6830 (bc = $179, tmp_00 = 0)
	; -> $3800 (00:25C9). Port: atlas mapy 1 (bank 51 $6000), pary sprite'ow wyniku (w oryginale kafle sprite'ow zostaja
	; z poziomu $12: cyfry ART_09_B92E pod $3000, szmaragd $5C-$5F od obiektu $54), komorki, czyste tlo.
	jsr scr_load_begin
	lda #1
	jsr scr_unpack_atlas      ; ART_0C_0000 = atlas mapy 1 -> ATLAS_VRAM (kod rezydentny)
	mwa #ko_spr_a sz_s
	lda #KO_SPR_A_N
	jsr scr_load_sprites
	mwa #ko_rle_a sz_s
	mwa #KO_RLE_A_N sz_n
	lda #0
	sta tmp_00                ; 00:25C6
	jsr scr_unpack_tilemap
	lda #0
	sta scr_prio
	jsr scr_build_bg
	jsr scr_prefill
	ldx #KO_K1
	jsr ko_load_end
	lda SC_REG1
	ora #$40                  ; obraz wlaczony (00:25CC)
	sta SC_REG1
	jsr scr_wait0             ; 00:25D8: IRQ - obraz, paleta PAL3_ending_tally
	lda g_chaos_emeralds_collected
	cmp #6                    ; 00:25E6: < 6 -> @skip_good_ending
	jcc ko_nogood
	inc ko_good               ; dobre zakonczenie (stala ladowania napisow KO_K3G)

	; @good_ending_chaos_emeralds_together (00:25ED): 60 ramek - szmaragd (FFstr $5C $5E) w ($70, $60) od wpisu 0
	lda #60
	sta ko_cnt
kn_gt_l
	jsr scr_wait0
	jsr ko_ptr0               ; ld hl, g_sprite_table
	lda #$70
	ldy #$60
	jsr ko_emer
	dec ko_cnt
	bne kn_gt_l
	lda #$13                  ; rst $18: muzyka $13 (00:2608)
	jsr play_music
	; @good_ending_chaos_emeralds_spin_animation (00:2610): 61 krokow po 2 ramki; w kroku 3 pary szmaragdow
	; w ($70 + dx, $60 + dy) i ($70 - dx, $60 - dy), od wpisu 0 tablicy sprite'ow (LUT 00:241D: dx, dy)
	mwa #ko_spin ko_lp
	lda #61
	sta ko_cnt
kn_gs_l
	jsr scr_wait_keep         ; ld c,(g_sprite_count) / wait / ld (g_sprite_count),c (00:2611-00:261B)
	jsr scr_wait0             ; 00:2622
	jsr ko_ptr0               ; 00:2625: ld (g_next_avail_vdp_sprite_ptr), g_sprite_table
	lda #3
	sta ko_cnt2
	lda ko_lp                 ; hl (sz_p: scr_dst go nie zmienia; scr_wait - tak, stad ko_lp miedzy krokami)
	sta sz_p
	lda ko_lp+1
	sta sz_p+1
kn_gs_p                           ; @each_chaos_emerald_pair_spinning (00:262E)
	ldy #0
	lda (sz_p),y              ; c = $70 + dx
	clc
	adc #$70
	sta ko_x
	iny
	lda (sz_p),y              ; b = $60 + dy
	clc
	adc #$60
	tay
	lda ko_x
	jsr ko_emer               ; 00:2641
	ldy #0                    ; pop hl: te same dx, dy (00:2648)
	lda #$70                  ; neg / add $70: c = $70 - dx (00:264A)
	sec
	sbc (sz_p),y
	sta ko_x
	iny
	lda #$60                  ; b = $60 - dy
	sec
	sbc (sz_p),y
	tay
	lda ko_x
	jsr ko_emer               ; 00:265E
	clc                       ; hl + 2
	lda sz_p
	adc #2
	sta sz_p
	bcc kn_gs_n
	inc sz_p+1
kn_gs_n
	dec ko_cnt2
	bne kn_gs_p
	lda sz_p
	sta ko_lp
	lda sz_p+1
	sta ko_lp+1
	dec ko_cnt
	bne kn_gs_l
	jsr bfw_body              ; palette_fade_up LUT_02047_all7F (00:266E): do bieli, 50 IRQ (src/scr/ekrany.asm)
	lda #0
	sta g_sprite_count        ; 00:2671
	; unpack_art_tilemap_into_vram ARTMAP_05_69A9 (bc = $145, tmp_00 = 0) przy obrazie wlaczonym (bialym): przerwania
	; w czasie rozpakowania bez aktualizacji ekranu (iy_00 b0 = 1) - stala KO_K2; port: cale tlo od nowa w nastepnym obrazie
	lda v_frame
	sta scr_t0                ; tempo jak oryginal (ko_load_end)
	mwa #ko_rle_b sz_s
	mwa #KO_RLE_B_N sz_n
	lda #0
	sta tmp_00                ; 00:2687
	jsr scr_unpack_tilemap
	lda #$FF
	sta scr_nd                ; komorki bez listy zmian: przebudowa calego czystego tla (scr_render)
	ldx #KO_K2
	jsr ko_load_end
	jsr ko_fade_down          ; fade_screen_down_to_palette PAL3_ending_tally (00:2690)

ko_nogood                       ; @skip_good_ending (00:2693)
	lda #240                  ; wait_BC_frames_for_pre_credits_delay $F0 (00:2696): tablica sprite'ow bez zmian
	jsr scr_wait_keep_n
	jsr ko_final              ; handle_level_score_screen (00:2699) -> g_level = $13: handle_final_score_screen
	lda #240                  ; 00:269F
	jsr scr_wait_keep_n
	jsr scr_fade_to_black     ; 00:26A2: 41 IRQ (wyswietlane palety -> czern)
	lda #120                  ; 00:26A8
	jsr scr_wait_keep_n
	; load_art ART_0C_1801 -> $0000 (00:26B3), ART_09_4B0A -> $2000 (00:26BE), ARTMAP_05_6C61 (bc = $189) -> $3800
	; (00:26D6) - obraz wlaczony, paleta czarna, IRQ bez aktualizacji ekranu (stala KO_K3)
	jsr scr_load_begin
	lda #3
	jsr scr_unpack_atlas      ; ART_0C_1801 = atlas mapy 2 (bank 53 $6000) -> ATLAS_VRAM
	mwa #ko_spr_b sz_s
	lda #KO_SPR_B_N
	jsr scr_load_sprites      ; 22 pary kafli sprite'ow napisow
	mwa #ko_rle_c sz_s
	mwa #KO_RLE_C_N sz_n
	lda #0
	sta tmp_00                ; 00:26D3
	jsr scr_unpack_tilemap
	lda #0
	sta scr_prio
	jsr scr_build_bg
	jsr scr_prefill
	ldx #KO_K3
	lda ko_good
	beq kn_k3
	ldx #KO_K3G
kn_k3
	jsr ko_load_end
	ldx #0                    ; g_credits_sprites (00:26DA-00:26FB): 4 x [credits_sprite_0N, licznik 0]
	ldy #0
kn_ci_l
	lda kn_c_tab,y
	sta KO_CRED,x
	lda kn_c_tab+1,y
	sta KO_CRED+1,x
	lda #0
	sta KO_CRED+2,x
	inx
	inx
	inx
	iny
	iny
	cpy #8
	bne kn_ci_l
	lda #1                    ; wait_BC_frames_while_updating_credits_sprites bc = 1 (00:26FF)
	ldx #0
	jsr ko_wcs
	ldx #<KO_PAL_CRED_S       ; palette_fade_in_banks_01_02 PAL3_credits (00:2705): 50 IRQ, sprite'y bez animacji
	ldy #>KO_PAL_CRED_S
	jsr scr_fade_in
	lda #$0E                  ; rst $18: muzyka napisow $0E (00:2708)
	jsr play_music
	lda #0
	sta tmp_00                ; 00:270C
	jsr ko_credits            ; run_credits_text_sequence (00:2712)

; ---------------------------------------------------------------------
; @end_of_credits_infloop (00:2715): bez wait_until_irq_ticked - IRQ dalej (iy_00 b0 = 1: bez aktualizacji
; ekranu - tablica sprite'ow i paleta stoja; random_A, wejscie, muzyka). Ostatni znak skryptu zapisany po ostatnim
; IRQ jest widoczny w obrazie po tym IRQ: port buduje ten obraz raz (scr_render), potem tylko emulacja IRQ co VBI.
; Dodatek portu: przycisk 1/2 wcisniety po puszczeniu -> rts (zimny start w kodzie rezydentnym).
; ---------------------------------------------------------------------
ko_end
	jsr scr_render            ; obraz po ostatnim IRQ skryptu (v_flip_req = 1)
kn_en_v
	lda v_flip_req            ; VBI z flipem tego obrazu - potem nastepne IRQ
	bne kn_en_v
	lda #0
	sta ko_rel
kn_en_irq
	jsr scr_irqemu            ; IRQ: bez @fn_update_screen (iy_00 b0 = 1)
	lda g_inputs_player_1
	and #$20                  ; bit 5 = 0: przycisk 1 albo 2
	beq kn_en_btn
	lda #1                    ; puszczony
	sta ko_rel
	bne kn_en_w                 ; zawsze
kn_en_btn
	lda ko_rel
	bne kn_en_ret               ; wcisniety po puszczeniu: koniec (dodatek portu)
kn_en_w
	lda v_frame               ; nastepny VBI (obraz bez zmian - bufor przedni zostaje)
kn_en_f
	cmp v_frame
	beq kn_en_f
	jmp kn_en_irq
kn_en_ret
	rts

; ---------------------------------------------------------------------
; ko_load_end: jak scr_load_end, ale stale konca (ko_kn / ko_kp, indeks X = KO_K*) i bez zapisu boot_ldfr:
; przerwania oryginalu w czasie ladowania (random_A, scr_irq) i czekanie, az minie tyle ramek od scr_t0
; ---------------------------------------------------------------------
ko_load_end
	lda v_tv                  ; 1 = PAL
	beq kn_le_n
	lda ko_kp,x
	jmp kn_le_go
kn_le_n
	lda ko_kn,x
kn_le_go
	sta scr_cnt
	jsr scr_skip_a
kn_le_w
	lda v_frame
	sec
	sbc scr_t0
	cmp scr_cnt
	bcc kn_le_w
	rts

; ko_cnt0: g_sprite_count = 0; ko_ptr0: g_next_avail_vdp_sprite_ptr = g_sprite_table (wpis 0)
ko_cnt0
	lda #0
	sta g_sprite_count
ko_ptr0
	lda #<SC_SAT_S
	sta g_next_avail_vdp_sprite_ptr
	lda #>SC_SAT_S
	sta g_next_avail_vdp_sprite_ptr+1
	rts

; ko_emer: draw_sprite_text FFstr_chaos_emerald_or_monitor_image ($5C $5E) od x = A, y = Y, od wpisu
; g_next_avail_vdp_sprite_ptr (potem nastepny) - 00:25F5-00:2602, 00:263B-00:2644, 00:2658-00:2661
ko_emer
	sta scr_c
	sty scr_y8
	mwa #KO_FFEM sz_m
	ldx g_next_avail_vdp_sprite_ptr
	jsr scr_dst
	stx g_next_avail_vdp_sprite_ptr
	rts

; ---------------------------------------------------------------------
; ko_fade_down: fade_screen_down_to_palette (00:0AAE) do PAL3_ending_tally: bufor tymczasowy = 32 B od
; g_current_displayed_palette_0, sygnal, obraz wlaczony, 1 + 9 IRQ (licznik sprite'ow zachowany), potem 4 kroki:
; skladowa rozna od celu -> - 1 (z bieli zawsze >= celu), sygnal, 10 IRQ (razem 50).
; ---------------------------------------------------------------------
ko_fade_down
	lda #<KO_PAL_TALLY_S      ; ld (tmp_06),hl (00:0AAE)
	sta tmp_06
	lda #>KO_PAL_TALLY_S
	sta tmp_06+1
	lda SC_CURPAL0            ; ldir (cur0) -> bufor (00:0AB1; po bieli cur0 = bufor)
	ldx SC_CURPAL0+1
	jsr scr_sms_ptr
	ldy #0
kn_fd_cp
	lda (sz_s),y
	sta SC_TMPPAL,y
	iny
	cpy #32
	bne kn_fd_cp
	lda #3
	ldx #<SC_TMPPAL_S
	ldy #>SC_TMPPAL_S
	jsr scr_signal_pal        ; 00:0AD1
	lda SC_REG1
	ora #$40
	sta SC_REG1
	jsr scr_wait_keep         ; 00:0AE3
	lda #9                    ; @pre_wait_9_frames (00:0AEB)
	jsr scr_wait_keep_n
	lda #4
	sta scr_fstep
kn_fd_step                        ; @each_fade_step (00:0AFC)
	lda tmp_06                ; ld hl,(tmp_06): adres celu (SMS -> port)
	ldx tmp_06+1
	jsr scr_sms_ptr
	ldy #31
kn_fd_col                         ; @each_color: R (bity 0-1), G (2-3), B (4-5)
	lda (sz_s),y
	and #$03
	sta scr_q
	lda SC_TMPPAL,y
	and #$03
	cmp scr_q
	beq kn_fd_r
	sec
	sbc #1                    ; dec a
kn_fd_r
	sta scr_c
	lda (sz_s),y
	and #$0C
	sta scr_q
	lda SC_TMPPAL,y
	and #$0C
	cmp scr_q
	beq kn_fd_g
	sec
	sbc #4
kn_fd_g
	ora scr_c
	sta scr_c
	lda (sz_s),y
	and #$30
	sta scr_q
	lda SC_TMPPAL,y
	and #$30
	cmp scr_q
	beq kn_fd_b
	sec
	sbc #$10
kn_fd_b
	ora scr_c
	sta SC_TMPPAL,y
	dey
	bpl kn_fd_col
	lda #3
	ldx #<SC_TMPPAL_S
	ldy #>SC_TMPPAL_S
	jsr scr_signal_pal        ; 00:0B38
	lda #10                   ; @mid_wait_10_frames (00:0B3D)
	jsr scr_wait_keep_n
	dec scr_fstep
	bne kn_fd_step
	rts

; =====================================================================
;  ko_final: handle_final_score_screen (00:172F-00:185F) - ekran wyniku koncowego na obrazie konca (bez ladowania
;  grafiki): premia specjalna, napisy FF (kafle atlasu mapy 1, atrybut tmp_00 = 0), liczenie szmaragdow (20 000
;  pkt / 60 ramek), zyc (5000 / 30) i premii (10 000 / 30), efekt $02; dodatkowego zycia nie ma
;  (g_next_life_bonus_10000s_BCD = $FF). Czas: 180 + 60(E+1) + 360 + 30(L+1) + 360 + 30(B+1) + 480 ramek.
; =====================================================================
ko_final
	lda #$FF                  ; 00:172F
	sta g_next_life_bonus_10000s_BCD
	lda #0                    ; c = 0
	sta ko_c
	lda g_chaos_emeralds_collected
	cmp #6
	bcc kn_f_1
	lda #5                    ; wszystkie szmaragdy: + 5 (00:173D)
	sta ko_c
kn_f_1
	lda g_level_lives_collected
	cmp #$12
	bcc kn_f_2
	ldy #$05                  ; zycia ze wszystkich monitorow: + 5 (00:1746)
	jsr kn_f_add
kn_f_2
	lda g_special_stages_attempted
	cmp #8
	bcc kn_f_3
	ldy #$05                  ; 8 etapow specjalnych podjetych: + 5 (00:1752)
	jsr kn_f_add
kn_f_3
	lda g_special_stages_completed
	cmp #8
	bcc kn_f_4
	ldy #$05                  ; 8 ukonczonych: + 5 (00:175E)
	jsr kn_f_add
kn_f_4
	lda g_sonic_died_at_least_once
	bne kn_f_5
	ldy #$10                  ; bez smierci: add a,$0A / daa = + 10 (00:1769)
	jsr kn_f_add
kn_f_5
	lda ko_c
	cmp #$30                  ; komplet (30): + 10 + 10 (00:1773)
	bne kn_f_6
	ldy #$10
	jsr kn_f_add
	ldy #$10
	jsr kn_f_add
kn_f_6
	lda ko_c                  ; g_ending_special_bonus_BCD_big_endian = c, 0, 0 (00:177B)
	sta KO_BONUS
	lda #0
	sta KO_BONUS+1
	sta KO_BONUS+2
	ldx #0                    ; napisy FF 00:1785-00:17B2: ramka naglowka, ramka wyniku, "CHAOS EMERALD"
kn_f_pr
	lda kn_f_strs,x
	sta sz_m
	lda kn_f_strs+1,x
	sta sz_m+1
	txa
	pha
	jsr scr_print_ff
	pla
	tax
	inx
	inx
	cpx #16
	bne kn_f_pr
	lda #0
	sta tmp_08                ; pole 0: szmaragdy (00:17B5)
	jsr ko_ff180              ; 00:17BC
kn_f_em                           ; @each_chaos_emerald (00:17BF)
	lda #60
	ldx #0
	jsr ko_ff
	lda g_chaos_emeralds_collected
	beq kn_f_noem
	dec g_chaos_emeralds_collected
	lda #$02                  ; + 20 000 pkt: C = 2, DE = 0 (00:17CF)
	ldx #$00
	ldy #$00
	jsr ko_addp
	lda #$02                  ; rst $28 (00:17D7)
	jsr play_sfx
	jmp kn_f_em
kn_f_noem                         ; @no_more_chaos_emeralds (00:17DD)
	jsr ko_ff180
	lda #1
	sta tmp_08                ; pole 1: zycia
	mwa #scr_r0+[$198E-EKR_R0_FROM] sz_m ; LUT_final_FFstr_header_str_01_sonic_left (00:17E8)
	jsr scr_print_ff
	jsr ko_ff180
kn_f_lv                           ; @each_life (00:17F4)
	lda #30
	ldx #0
	jsr ko_ff
	lda g_lives
	beq kn_f_nolv
	dec g_lives
	lda #$00                  ; + 5000 pkt: C = 0, DE = $5000 (00:1804)
	ldx #$50
	ldy #$00
	jsr ko_addp
	lda #$02
	jsr play_sfx
	jmp kn_f_lv
kn_f_nolv                         ; @no_more_lives (00:1812)
	jsr ko_ff180
	lda #2
	sta tmp_08                ; pole 2: premia specjalna
	mwa #scr_r0+[$199E-EKR_R0_FROM] sz_m ; LUT_final_FFstr_header_str_02_special_bonus (00:181D)
	jsr scr_print_ff
	mwa #scr_r0+[$197A-EKR_R0_FROM] sz_m ; LUT_final_FFstr_scorebox_row4_remove_x (00:1823)
	jsr scr_print_ff
	jsr ko_ff180
kn_f_sb                           ; @each_special_bonus_10000_points (00:182F)
	lda #30
	ldx #0
	jsr ko_ff
	lda KO_BONUS
	beq kn_f_nosb
	sec                       ; dec a; mlodsza cyfra >= $A -> - 6 (00:183B)
	sbc #1
	sta ko_c
	and #$0F
	cmp #$0A
	bcc kn_f_sbt
	lda ko_c
	sec
	sbc #6
	sta ko_c
kn_f_sbt
	lda ko_c
	sta KO_BONUS
	lda #$01                  ; + 10 000 pkt: C = 1, DE = 0 (00:184B)
	ldx #$00
	ldy #$00
	jsr ko_addp
	lda #$02
	jsr play_sfx
	jmp kn_f_sb
kn_f_nosb                         ; @no_more_special_bonus_points (00:1859)
	lda #<$1E0
	ldx #>$1E0
	jmp ko_ff

; kn_f_add: c = c + Y (BCD: add a,n / daa)
kn_f_add
	lda ko_c
	clc
	jsr scr_bcd_adc
	sta ko_c
	rts

; napisy FF wyniku koncowego (adresy portu w ekr_rom0.bin): LUT_final_FFstr_header_row0..2, scorebox_row2..5,
; header_str_00_chaos_emerald (00:1907, 00:191C, 00:1931, 00:1946, 00:1953, 00:1960, 00:196D, 00:197E)
kn_f_strs	dta a(KO_SR+$1907, KO_SR+$191C, KO_SR+$1931, KO_SR+$1946)
	dta a(KO_SR+$1953, KO_SR+$1960, KO_SR+$196D, KO_SR+$197E)

; ---------------------------------------------------------------------
; ko_addp: add_CHL_points_to_score_in_BCD (00:39D8): wynik BCD (D2BA..D2BD) += C:D:E (A = C, X = D, Y = E);
; bajt D2BB >= g_next_life_bonus_10000s_BCD -> premia + 5, zycie + 1, efekt $09 (na ekranie konca premia = $FF)
; ---------------------------------------------------------------------
ko_addp
	sta ko_pc
	stx ko_pd
	sty ko_pe
	clc
	lda ko_pe
	ldx #3
	jsr sap_add               ; D2BD += E
	lda ko_pd
	ldx #2
	jsr sap_add               ; D2BC += D + C
	lda ko_pc
	ldx #1
	jsr sap_add               ; D2BB += C + C
	sta scr_tmpw              ; ld c,a (jak scr_add100)
	lda #0
	ldx #0
	jsr sap_add               ; D2BA += C
	lda scr_tmpw
	cmp g_next_life_bonus_10000s_BCD
	bcc kn_ap_ret
	lda g_next_life_bonus_10000s_BCD
	ldy #5
	clc
	jsr scr_bcd_adc
	sta g_next_life_bonus_10000s_BCD
	inc g_lives
	lda #$09                  ; rst $28: dodatkowe zycie
	jmp play_sfx
kn_ap_ret
	rts

; ko_ff180: ko_ff dla bc = $B4 (180 ramek)
ko_ff180
	lda #180
	ldx #0

; ---------------------------------------------------------------------
; ko_ff: draw_final_bonus_value_for_BC_frames (00:1860), A/X = liczba ramek (mlodszy / starszy bajt): co ramke
; wait, g_sprite_count = 0, od wpisu 0: wynik (8 cyfr) w ($90, $80); pole tmp_08: 0 - szmaragdy ($90, $60) i "20000"
; ($A0, $60), 1 - zycia ($90, $60) i "5000" ($A0, $60), inne - premia specjalna (3 B) w ($A0, $60)
; ---------------------------------------------------------------------
ko_ff
	sta ko_bc
	stx ko_bc+1
kn_ff_l
	jsr scr_wait0             ; 00:1861
	jsr ko_cnt0               ; g_sprite_count = 0 (00:1868), ld hl, g_sprite_table
	mwa #g_score_BCD sz_s     ; build_BCD_FFstr wynik, 4 B (00:187A)
	lda #4
	jsr scr_bcd_str
	lda #$90
	ldy #$80
	jsr sdt_text
	lda tmp_08
	bne kn_ff_n0
	mwa #g_chaos_emeralds_collected sz_s ; 00:1891
	lda #1
	jsr scr_bcd_str
	lda #$90
	ldy #$60
	jsr sdt_text
	mwa #scr_r0+[$19AE-EKR_R0_FROM] sz_s ; LUT_score_BCD_3byte_20000 (00:18AA)
	jmp kn_ff_3
kn_ff_n0
	cmp #1
	bne kn_ff_n1
	jsr ko_lives              ; draw_tally_screen_lives (00:18C8)
	mwa #scr_r0+[$19B1-EKR_R0_FROM] sz_s ; LUT_score_BCD_3byte__5000 (00:18CB)
	jmp kn_ff_3
kn_ff_n1
	mwa #KO_BONUS sz_s        ; g_ending_special_bonus_BCD_big_endian (00:18E6)
kn_ff_3
	lda #3
	jsr scr_bcd_str
	lda #$A0
	ldy #$60
	jsr sdt_text
	lda ko_bc                 ; dec bc / jp nz (00:1900)
	bne kn_ff_d
	dec ko_bc+1
kn_ff_d
	dec ko_bc
	lda ko_bc
	ora ko_bc+1
	jne kn_ff_l
	rts

; ko_lives: draw_tally_screen_lives (00:1ACA) dla g_level = $13 (00:1AFB): zycia - zawsze 2 cyfry w ($90, $60)
ko_lives
	lda g_lives
	ldx #0
kn_lv_d
	cmp #10
	bcc kn_lv_e
	sbc #10
	inx
	bne kn_lv_d
kn_lv_e
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
	lda #$90
	ldy #$60
	jmp sdt_text

; =====================================================================
;  Napisy
; =====================================================================
; ko_wcs: wait_BC_frames_while_updating_credits_sprites (00:2718), A/X = liczba ramek: co ramke wait,
; g_sprite_count = 0, od wpisu 0 cztery sprite'y napisow (draw_credits_sprite)
ko_wcs
	sta ko_bc
	stx ko_bc+1
kn_wc_l
	jsr scr_wait0             ; 00:2721
	jsr ko_cnt0               ; g_sprite_count = 0 (00:2724), ld hl, g_sprite_table
	ldx #0                    ; hl = g_credits_sprites, 4 rekordy po 3 B
	jsr ko_dcs
	ldx #3
	jsr ko_dcs
	ldx #6
	jsr ko_dcs
	ldx #9
	jsr ko_dcs
	lda ko_bc
	bne kn_wc_d
	dec ko_bc+1
kn_wc_d
	dec ko_bc
	lda ko_bc
	ora ko_bc+1
	bne kn_wc_l
	rts

; ---------------------------------------------------------------------
; ko_dcs: draw_credits_sprite (00:275A), X = rekord g_credits_sprites (0, 3, 6, 9): [slowo adresu SMS wpisu
; animacji, licznik]. Licznik + 1; czas wpisu < licznik -> licznik 0, nastepny wpis (+ 3); czas $FF -> skok pod
; slowo za nim i od nowa. Wpis: [czas, slowo mapy csXX]; mapa: x, y, wiersze draw_sprite_string.
; ---------------------------------------------------------------------
ko_dcs
	lda KO_CRED,x             ; de = wpis (00:275A)
	clc
	adc #<KO_OFS
	sta sz_p
	lda KO_CRED+1,x
	adc #>KO_OFS
	sta sz_p+1
	inc KO_CRED+2,x           ; inc (hl) (00:275E)
	ldy #0
	lda (sz_p),y              ; czas wpisu
	cmp KO_CRED+2,x
	bcs kn_ds_draw              ; czas >= licznik -> rysuj (00:2761)
	lda #0
	sta KO_CRED+2,x           ; 00:2763
	clc                       ; de + 3 -> rekord (00:2765-00:276B)
	lda KO_CRED,x
	adc #3
	sta KO_CRED,x
	bcc kn_ds_n
	inc KO_CRED+1,x
kn_ds_n
	clc
	lda sz_p
	adc #3
	sta sz_p
	bcc kn_ds_m
	inc sz_p+1
kn_ds_m
	lda (sz_p),y              ; Y = 0
	cmp #$FF                  ; 00:276F
	bne kn_ds_draw
	iny                       ; skok: slowo za $FF -> rekord, od nowa (00:2773-00:277C)
	lda (sz_p),y
	sta KO_CRED,x
	iny
	lda (sz_p),y
	sta KO_CRED+1,x
	jmp ko_dcs
kn_ds_draw                        ; @found_sprite_to_draw (00:277E): mapa csXX (adres SMS -> port)
	ldy #1
	lda (sz_p),y
	clc
	adc #<KO_OFS
	sta sz_d
	iny
	lda (sz_p),y
	adc #>KO_OFS
	sta sz_d+1
	ldy #0
	lda (sz_d),y              ; l = x, h = 0
	sta sz_x
	iny
	lda (sz_d),y              ; e = y, d = 0
	sta sz_y
	lda #0
	sta sz_x+1
	sta sz_y+1
	clc                       ; bc = mapa (za x, y)
	lda sz_d
	adc #2
	sta sz_m
	lda sz_d+1
	adc #0
	sta sz_m+1
	txa
	pha
	jsr scr_dss               ; draw_sprite_string (00:2790)
	pla
	tax
	rts

; ---------------------------------------------------------------------
; ko_credits: run_credits_text_sequence (00:2795): x, y -> g_HUD_FFstr_buf, buf[3] = $FF; polecenia: $FF koniec,
; $FE nowa pozycja (x, y), $FD czekanie (slowo ramek), $FC przewiniecie (n razy: 12 ramek, 9 wierszy w gore),
; inne - znak: 8 ramek, print_positioned_FF_string (kafel w (x, y), atrybut tmp_00), x + 1
; ---------------------------------------------------------------------
ko_credits
	lda #<KO_SCRIPT           ; hl = credits_text_sequence_script_data (00:270F)
	sta kn_gb_rd+1
	lda #>KO_SCRIPT
	sta kn_gb_rd+2
kn_cr_pos                         ; 00:2795: ldi x 2, buf[3] = $FF
	jsr ko_getb
	sta g_HUD_FFstr_buf
	jsr ko_getb
	sta g_HUD_FFstr_buf+1
	lda #$FF
	sta g_HUD_FFstr_buf+3
kn_cr_cmd                         ; @read_next_cmd (00:27A0)
	jsr ko_getb
	cmp #$FF
	beq kn_cr_ret
	cmp #$FE
	beq kn_cr_pos
	cmp #$FC
	beq kn_cr_scr
	cmp #$FD
	bne kn_cr_chr
	jsr ko_getb               ; c, b (00:27B1)
	pha
	jsr ko_getb
	tax
	pla
	jsr ko_wcs
	jmp kn_cr_cmd
kn_cr_chr                         ; @cmd_text_char_wait_8_frames (00:27BA)
	sta g_HUD_FFstr_buf+2
	lda #8
	ldx #0
	jsr ko_wcs
	mwa #g_HUD_FFstr_buf sz_m
	jsr scr_print_ff          ; 00:27C7
	inc g_HUD_FFstr_buf       ; x + 1 (00:27CD)
	jmp kn_cr_cmd
kn_cr_scr                         ; @cmd_FC_scroll_up_x_times (00:27D1)
	jsr ko_getb
	sta ko_cnt2               ; b (djnz: 0 = 256)
kn_cs_l
	lda #12                   ; 00:27D5
	ldx #0
	jsr ko_wcs
	jsr ko_scroll
	dec ko_cnt2
	bne kn_cs_l
	jmp kn_cr_cmd
kn_cr_ret
	rts

; ko_getb: ld a,(hl) / inc hl - wskaznik skryptu w adresie instrukcji (kod w RAM banku 49, jak scr_load_sprites)
ko_getb
kn_gb_rd	lda $FFFF
	inc kn_gb_rd+1
	bne kn_gb_r
	inc kn_gb_rd+2
kn_gb_r
	rts

; ko_scroll: 00:27DB-00:281C - kopia VRAM 9 linii po 20 bajtow z $3AE4 do $3AA4 (krok $40): komorki (kafel
; i atrybut) wierszy 11..19 -> 10..18, kolumny 18..27; w modelu przez scr_put_cell (zmienione komorki do listy;
; przepelnienie -> cale tlo od nowa). Wiersz 19 zostaje. tmp_00 (atrybut wydruku) przywrocony.
ko_scroll
	lda tmp_00
	pha
	lda #<[10*32+18]
	sta ko_dst
	lda #>[10*32+18]
	sta ko_dst+1
	lda #9
	sta ko_r
kn_sc_row
	lda ko_dst
	sta scr_cell
	lda ko_dst+1
	sta scr_cell+1
	lda #10
	sta ko_k
kn_sc_c
	clc                       ; zrodlo: komorka + 32 (scr_nt wyrownane do strony)
	lda scr_cell
	adc #32
	sta sz_d
	lda scr_cell+1
	adc #>scr_nt
	sta sz_d+1
	ldy #0
	lda (sz_d),y              ; kafel
	pha
	lda sz_d+1
	clc
	adc #3                    ; scr_at = scr_nt + $300
	sta sz_d+1
	lda (sz_d),y
	sta tmp_00                ; atrybut
	pla
	jsr scr_put_cell          ; komorka scr_cell = kafel A, atrybut tmp_00
	inc scr_cell
	bne kn_sc_n
	inc scr_cell+1
kn_sc_n
	dec ko_k
	bne kn_sc_c
	clc
	lda ko_dst
	adc #32
	sta ko_dst
	bcc kn_sc_r
	inc ko_dst+1
kn_sc_r
	dec ko_r
	bne kn_sc_row
	pla
	sta tmp_00
	rts

; credits_sprite_00..03 (adresy SMS, 00:26DD-00:26F8)
kn_c_tab	dta a($2848, $2857, $2869, $2872)

; Dane z ROM-u SMS (tools/extract_koniec.py, build/assets/ekrany): w banku 36 (src/game.asm), w RAM od ko_copy - ko_r0, ko_spin wyzej

	.if KO_PAL_TALLY_S >= $C000 || KO_PAL_CRED_S >= $C000
	.error "koniec.asm: palety konca - adres dla scr_sms_ptr >= $C000 (dane przed scr_r0 - $0E72?)"
	.endif
	.if KO_RAM+KO_RAM_SIZE+366 > $2000
	.error "koniec.asm: blok koniec_ram.bin + koniec_spin.bin w RAM nachodzi na okno MEMAC $2000"
	.endif
