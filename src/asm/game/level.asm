; =====================================================================
;  level.asm - start gry i poziomu w lustrze RAM SMS (game/sms.inc)
;  Dane z banku poziomu (tools/extract_sms.py: LB_HDR, LB_TIME, LB_PALPTR, LB_CYCPTR, LB_OBJCNT, LB_DEMO).
; =====================================================================
HDR_COPY     = $28         ; load_and_init_level_from_header kopiuje $28 B naglowka (ldir)
HDR_START    = 13          ; pozycja startowa Sonica w naglowku (bloki x, y)
IN_JOY       = 0           ; zrodla wejscia (v_input_mode)
IN_DEMO      = 1
IN_SCRIPT    = 2
RNG_RESTART  = 129         ; M4.1: przerwania (random_A) przejscia: miedzy ostatnim rekordem zycia a krokiem -16
                           ; nastepnego 130 (referencja smierc-kolce, smierc-upadek), w tym IRQ ticku wyjscia
                           ; (bez rekordu), ktory port liczy w sms_step
RNG_TELE     = 110         ; M6.9: przerwania przejscia EXIT_TELE (korytarz / teleport): jak RNG_RESTART bez 60 ramek przerwy, z drugim
                           ; wygaszeniem (41) - wstepnie 129 - 60 + 41; pomiar: referencje m69-korytarz-* (Mesen)

; game_reset: stan gry jak po main@reset_game_state (00:1C4E): lustro RAM wyzerowane, 3 zycia, poziom 0
; (GHZ1), licznik tickow 0. Tryb demo ustawia bit 1 iy_05_lvflag00 (jak run_title_screen bez przycisku).
game_reset
	mwa #MIRROR_RAM zg_ptr
	ldx #16
	lda #0
	tay
gr_clr
	sta (zg_ptr),y
	iny
	bne gr_clr
	inc zg_ptr+1
	dex
	bne gr_clr
	lda #3
	sta g_lives
	lda boot_level            ; M6.3: poziom startowy (0 = GHZ1; wybor w cracktro / test GHZ2) - oryginal: xor a
	sta g_level
	lda #5
	sta g_next_life_bonus_10000s_BCD
	lda v_nbonus              ; $1C (M6.11: trainer - pierwszy etap specjalny za wybrana pozycja; jednorazowo - review M6.11: kolejna
	sta g_next_bonus_level    ; nowa gra po game over / demie / zimnym starcie znowu od $1C, jak w oryginale)
	lda #$1C
	sta v_nbonus
	lda #<$D006               ; M4.1: wskaznik tablicy sprite'ow po ekranach przed poziomem (referencja: $D006
	sta g_next_avail_vdp_sprite_ptr ; w kroku -16 pierwszego startu - demo, gra, GHZ2; ekrany M6)
	lda #>$D006
	sta g_next_avail_vdp_sprite_ptr+1
	lda v_rng_seed0           ; M4.1: ziarno RNG (oryginal: zalezne od dlugosci ekranu tytulowego; test
	sta g_random_seed         ; ustawia je z kroku -16 referencji)
	lda v_rng_seed0+1
	sta g_random_seed+1
	lda #$FF                  ; IRQ co ramke wpisuje port bez wcisniec
	sta g_inputs_player_1
	sta g_screen_tile_replace_x+1 ; i konczy late ekranu (00:016C: x_hi = $FF - brak laty)
	sta g_current_music       ; M5: nic nie gra
	sta g_sfx_req_TEST        ; M5.4: bez zgloszenia efektu (krok -16 jak referencja) - w oryginale wczesniej ekran tytulowy ($06) albo mapa ($07),
	                          ; ekrany M6; muzyka poziomu startuje w level_init (rozna od biezacej)
	lda boot_level            ; M6.11: poziom koncowy $12 - naglowek bez muzyki ($FF: gra dalej biezaca) - g_current_music zostaje z mapy ($07;
	cmp #18                   ; rst $20 przed poziomem jej nie kasuje - referencja m611-koniec-*). Po SKY3 (level_tonext) - utwor z SKY3
	bne gr_mus
	lda #$07
	sta g_current_music
gr_mus
	lda v_input_mode
	cmp #IN_DEMO
	bne gr_done
	lda #2
	sta iy_05_lvflag00
gr_done
	rts

; level_restart: main@run_this_level -> load_and_run_level po smierci (kod 2): bez game_reset - zycia, licznik
; tickow, wynik, g_sonic_died_at_least_once, granice okna kamery i stare flagi zostaja jak w oryginale
; (porownanie startu segmentow w referencji: docs/m3-gracz.md M3.7). Krok -16 nastepnego segmentu.
level_restart
	lda v_gl_mask             ; M6.10: magazyn z latami szyby SKY3 (oryginal rysuje ekran od nowa z ukladu) - dane poziomu od nowa
	ora v_gl_mask+1
	beq lr_noglass
	jsr tele_reload
lr_noglass
	ldx #RNG_RESTART          ; M4.1: random_A w kazdym IRQ przejscia (wygaszanie, przerwa, ladowanie poziomu)
	lda g_level
	cmp #18                   ; M6.9: SBZ1-3 (12-14) z tablicy (m69-restart-sbz1..3); M6.10: SKY1-3 (15-17; m610-restart-sky1..3)
	bcs lr_rng
	tay
	lda v_img+LR_LEVEL        ; M6.10: restart w $1A (bank SKY3 przy akcie SKY2) - jak SKY3 (te same dane; m610-restart-1a: 129)
	cmp #LI_LV_SKY3           ; M7.2: obraz poziomu (v_img - XEX: = v_pblevel, nosnik: id) zamiast stalej banku PB_LEVELK3
	bne lr_dy
	ldy #17
lr_dy
	txa
	sec
	sbc lr_dec,y              ; M6.3: GHZ2 laduje sie o 1 IRQ krocej (PAL 128 = 41 + 60 + 27; plan-m6.md), M6.4: GHZ3 o 2 (PAL 127 = 41 + 60 + 26),
	tax                       ; M6.6: BRI1, BRI2 jak GHZ2, BRI3 jak GHZ3; M6.8 (m68-restart-lab1..3): LAB1 jak GHZ1, LAB2 o 1 IRQ
	jmp lr_rng                ; dluzej ($FF = -1), LAB3 o 2 krocej
lr_dec	dta b(0, 1, 2, 1, 1, 2, 0, 1, 2, 0, $FF, 2)
	dta b(1, 0, 0)            ; M6.9: SBZ1 o 1 IRQ krocej (jak GHZ2), SBZ2 i SBZ3 jak GHZ1
	dta b(1, 2, 1)            ; M6.10: SKY1 jak GHZ2, SKY2 o 2 IRQ krocej (m610-restart-sky1/2: 129, 128), SKY3 i $1A jak GHZ2 (129)
lr_rng
	lda v_img+LR_LEVEL        ; M6.9: restart w pod-poziomie $15 (RLE ukladu 2048 B) - o 1 IRQ krocej (m69-restart-15: 129)
	cmp #LI_LV_SBZ2B          ; M7.2: obraz $15 (dawniej PB_LEVELS5)
	bne lr_reg
	dex
lr_reg
	lda v_tv                  ; review M6.9: NTSC - ladowanie poziomu trwa o 5 IRQ dluzej (smierc-czas-ntsc, m69-restart-sbz2-ntsc,
	bne lr_rnd                ; m69-restart-14-ntsc: 135 / 130 random_A miedzy segmentami; jak K_LLOAD PAL 28 / NTSC 33)
	txa
	clc
	adc #5
	tax
lr_rnd
	jsr random_A
	dex
	bne lr_rnd
level_next                      ; M6.2 (wydanie): nastepny akt po ekranie wyniku i mapie - jak restart, ale ziarno
	jsr level_init            ; z ekranow (src/scr/boot.asm: boot_score, cfg_point)
	mwa #-16 v_step
	jsr read_input            ; IRQ w przerwie miedzy zyciami czyta port (skrypt przed krokiem 1: $FF)
	lda #0
	sta v_tr_irq
	jsr step_record_defaults
	jmp trace_record

; level_init: load_and_init_level_from_header (00:20CB) dla poziomu bez teleportu, checkpointu i wody
; (GHZ) oraz dalsza czesc load_and_run_level (00:1D15-00:1D3D) - tylko stan RAM. Grafika i palety VDP
; (load_art, signal_load_palettes, draw_initial_screen_tiles) robi renderer, muzyka - M5.
; Swiat zakresu M3: sloty obiektow 1-31 puste (jak referencja m3_ref.py --bez-obiektow).
level_init
	lda #0                    ; M6.4: zadania renderera i pozne IRQ z poprzedniego poziomu (boss, miganie palety)
	sta v_art_req
	sta v_flash_req
	sta v_late_irq
	lda boot_level            ; M6.11: poziom koncowy $12 - sprite'y z naglowka 09:AEB1 = grafika bossa GHZ3 (zadanie grafiki 1: kafle
	cmp #18                   ; $00-$7F, paleta PAL2_boss - kontroler $53 ustawia ja w pierwszym ticku; oryginal laduje grafike przy starcie)
	bne li_no12
	lda #1
	sta v_art_req
li_no12
	ldx #15                   ; M4.5: kafle ikon monitorow $5C-$5F - grafika strefy (oryginal laduje ja przy
	lda #$FF                  ; kazdym starcie poziomu); renderer odtworzy je w mon_tiles
li_monk
	sta v_monk,x
	dex
	bpl li_monk
	lda #1
	sta v_mondirty
	lda v_sign_art            ; M4.8: po tabliczce grafika i paleta sprite'ow strefy (oryginal laduje je przy starcie)
	ora v_sign_req
	beq li_nosign
	lda #0
	sta v_sign_req
	sta v_sign_pal
	lda #1
	sta v_zone_req
	jsr spr_zone_pal          ; SPRPAL_RAM z banku 39 (pal_fade w render_level_reset)
li_nosign
	jsr phys_init             ; tablice kolizji (flagi blokow, profile) - game/motion.asm
	lda v_pblevel             ; M6.3: bank poziomu (GHZ1 35, GHZ2 55, GHZ3 57)
	sta PORTB
	jsr lay_pages             ; uklad z banku (M3.7: przy restarcie pierscienie wracaja; oryginal rozpakowuje go z ROM-u przy
	sta zp_cnt                ; kazdym load_and_init_level_from_header); M6.9: $15 - tylko 2048 B (8 stron)
	lda #>[BANK_WIN+LB_LAYOUT]
	ldx #>LAYOUT_RAM
	jsr copy_pages
	lda v_pblevel             ; M6.3: bank poziomu (GHZ1 35, GHZ2 55, GHZ3 57)
	sta PORTB
	jsr hdr_src               ; M6.9: zg_ptr = kopia naglowka w banku (LB_HDR albo pod-poziom $16-$19 - LB_HDRALT)
	ldy #HDR_COPY-1
li_hdr
	lda (zg_ptr),y
	sta g_level_header_copy,y
	dey
	bpl li_hdr
	ldx #0
li_demo
	lda BANK_WIN+LB_DEMO,x    ; ARRAY_demo_inputs (00:1BC6) i nastepne bajty ROM
	sta demo_inputs,x
	inx
	bne li_demo
	lda BANK_WIN+LB_PALPTR    ; signal_load_palettes: adres palety, A = 3
	sta g_SIG00b3_palette_addr
	lda BANK_WIN+LB_PALPTR+1
	sta g_SIG00b3_palette_addr+1
	lda BANK_WIN+LB_CYCPTR    ; LUT_PAL1_cycles[naglowek+$1D]
	sta g_palette_cycle_baseptr
	lda BANK_WIN+LB_CYCPTR+1
	sta g_palette_cycle_baseptr+1
	lda BANK_WIN+LB_TFPTR     ; M4.1: adres SMS tablicy flag blokow (tmp_02 w load_scroll_tile_list_buffers)
	sta v_tf_ptr
	lda BANK_WIN+LB_TFPTR+1
	sta v_tf_ptr+1
	lda BANK_WIN+LB_OBJCNT    ; load_object_list: liczba obiektow listy poziomu
	sta g_object_count
	lda iy_06_lvflag01        ; M6.9 (00:2146): korytarz / teleport (iy_06 b4) - Sonic zywy: czas zostaje (@skip_set_init_time_after_teleport);
	and #$10                  ; po smierci w pod-poziomie (restart: iy_0C b4 -> iy_06 b4): czas z 00:2402 (LUT_bonus_stage_time_limits = LB_TIME_CP)
	beq li_time
	lda iy_05_lvflag00
	lsr
	bcc li_notime
	ldx #2
li_ttp
	lda BANK_WIN+LB_TIME_CP,x
	sta g_time_mins,x
	dex
	bpl li_ttp
	bmi li_notime             ; zawsze
li_time
	lda BANK_WIN+LB_TIME
	sta g_time_mins
	lda BANK_WIN+LB_TIME+1
	sta g_time_mins+1
	lda BANK_WIN+LB_TIME+2
	sta g_time_mins+2
li_notime
	lda #PB_MAIN
	sta PORTB

	lda iy_05_lvflag00
	sta iy_0B_old_lvflag00_UNUSED
	lda iy_06_lvflag01
	sta iy_0C_old_lvflag01
	lda #$FF
	sta g_screen_tile_replace_x
	lda #0
	sta g_vdp_scroll_x
	sta g_vdp_scroll_y
	sta g_level_camera_lock_towards_x
	sta g_level_camera_lock_towards_x+1
	sta g_level_camera_lock_towards_y
	sta g_level_camera_lock_towards_y+1
	sta g_camera_y_look_up_offset_px
	sta g_camera_y_look_up_offset_px+1
	sta g_water_irq_line_state
	sta g_water_onscreen_y
	ldx #$1C
li_zero                         ; $1D B od g_level_restart_countdown_timer
	sta g_level_restart_countdown_timer,x
	dex
	bpl li_zero
; M6.8 (00:2117-00:213A): poziom wody g_water_level_y = $0800 (bez wody); LAB1 / LAB2 (g_level 9, 10) z punktem kontrolnym (bit
; g_level_has_checkpoint_mask czytany tu, przed skasowaniem w 00:219D) i LAB3 (11) zawsze: cala woda - g_water_level_onscreen_y = $FF,
; poziom $0020. g_water_level_onscreen_y lezy poza wypelnieniem $1D B - w innych przypadkach zostaje z poprzedniego poziomu (jak oryginal).
	jsr level_mask            ; calc_level_offset_HL_and_mask_C: X = bajt maski, A = bit (C)
	and g_level_has_checkpoint_mask,x ; ld a,(de) / and c (uzyte tylko dla g_level 9 / 10)
	tay
	lda g_level
	cmp #9                    ; cp $09 / jr c, @not_water_level_index
	bcc li_nowater
	cmp #$0B                  ; cp $0B / jr z, @is_fully_underwater_level_index / jr nc, @not_water_level_index
	beq li_fullwater
	bcs li_nowater
	tya                       ; and c / jr z
	beq li_nowater
li_fullwater                    ; @is_fully_underwater_level_index
	lda #$FF
	sta g_water_level_onscreen_y
	lda #$20                  ; hl = $0020
	ldx #$00
	beq li_water              ; zawsze
li_nowater                      ; hl = $0800
	lda #$00
	ldx #$08
li_water                        ; @not_water_level_index: ld (g_water_level_y),hl
	sta g_water_level_y
	stx g_water_level_y+1
	lda #$FE
	sta g_y_oscillate_baseline_target
	lda #$FF
	sta g_y_oscillate_baseline_target+1
	lda iy_06_lvflag01        ; M6.9: korytarz / teleport z zywym Sonikiem - pierscienie zostaja (00:2150 omija 00:2155)
	and #$10
	beq li_rz
	lda iy_05_lvflag00
	lsr
	bcc li_norz
li_rz
	lda #0
	sta g_rings_BCD           ; @init_time_after_teleport (czas z LUT_normal_stage_start_time wyzej)
li_norz

	lda g_level_header_copy
	sta g_tile_flags_index
	ldx #3
li_wh
	lda g_level_header_copy+1,x
	sta g_level_width,x       ; g_level_width, g_level_height
	dex
	bpl li_wh
	ldx #7
li_lim
	lda g_level_header_copy+5,x
	sta g_level_limit_x0,x
	dex
	bpl li_lim
; M4.1 (00:219D): bit poziomu w g_level_has_checkpoint_mask -> start od punktu kontrolnego (jednorazowo: bit
; kasowany), czas z 00:2402 (LB_TIME_CP), tmp_08 = g_per_level_checkpoint_positions + 2 * g_level;
; inaczej (@checkpoint_not_set) tmp_08 = adres SMS pozycji startowej w kopii naglowka
	jsr level_mask
	and g_level_has_checkpoint_mask,x
	beq li_nocp
	eor #$FF                  ; cpl / and (de): bit kasowany
	and g_level_has_checkpoint_mask,x
	sta g_level_has_checkpoint_mask,x
	lda v_pblevel             ; M6.3: bank poziomu (GHZ1 35, GHZ2 55, GHZ3 57)
	sta PORTB
	ldx #2
li_cpt
	lda BANK_WIN+LB_TIME_CP,x
	sta g_time_mins,x
	dex
	bpl li_cpt
	lda #PB_MAIN
	sta PORTB
	lda g_level
	asl
	clc
	adc #<$D32E               ; g_per_level_checkpoint_positions
	sta tmp_08
	lda #>$D32E
	adc #0
	sta tmp_08+1
	jmp li_start
li_nocp
	lda #<[$D354+HDR_START]
	sta tmp_08
	lda #>[$D354+HDR_START]
	sta tmp_08+1
li_start
	lda tmp_08                ; zg_src = pozycja startowa (bloki x, y) w lustrze
	sta zg_src
	lda tmp_08+1
	clc
	adc #>SMS_RAM
	sta zg_src+1
; kamera: kafel = start - 3 (nie mniej niz 0), piksele = kafel * 32
	ldy #0
	lda (zg_src),y
	jsr start_tile
	sta g_level_scroll_tile_x
	jsr tile_px
	sta g_level_scroll_x_pix_lo
	sta g_displayed_level_scroll_x_pix_lo
	stx g_level_scroll_x_pix_lo+1
	stx g_displayed_level_scroll_x_pix_lo+1
	ldy #1
	lda (zg_src),y
	jsr start_tile
	sta g_level_scroll_tile_y
	jsr tile_px
	sta g_level_scroll_y_pix_lo
	sta g_displayed_level_scroll_y_pix_lo
	stx g_level_scroll_y_pix_lo+1
	stx g_displayed_level_scroll_y_pix_lo+1
	lda g_level_header_copy+$13 ; g_level_tilemap_ptr = offset mapowania + $4000
	sta g_level_tilemap_ptr
	lda g_level_header_copy+$14
	clc
	adc #$40
	sta g_level_tilemap_ptr+1
	lda #3
	sta g_SIG00b3_palettes_present
	lda g_level_header_copy+$1B ; cykl palety: licznik x2, indeks 0, liczba krokow
	sta g_palette_cycle_tick_remain
	sta g_palette_cycle_tick_remain+1
	lda #0
	sta g_palette_cycle_tick_remain+2
	lda g_level_header_copy+$1C
	sta g_palette_cycle_tick_remain+3
	jsr load_object_list      ; M4.1 (00:22E8)
	lda #0                    ; M4.1: tablica sprite'ow po ekranach przed poziomem / przejsciu (clear_sprite_table):
	sta g_sprite_count        ; licznik 0, poprzedni 64 (wskaznik zostaje - po restarcie z ostatniego ticku)
	lda #64
	sta g_prev_sprite_count
; flagi poziomu z naglowka (bit demo zachowany)
	lda iy_05_lvflag00
	and #2
	ora g_level_header_copy+$20
	sta iy_05_lvflag00
	lda g_level_header_copy+$21
	sta iy_06_lvflag01
	lda g_level_header_copy+$22
	sta iy_07_lvflag02
	lda g_level_header_copy+$23
	sta iy_08_lvflag03
	lda g_level_header_copy+$24 ; muzyka poziomu (00:2306-00:2314): ta sama gra dalej, bit 7 = bez muzyki
	cmp g_current_music
	beq li_samemus
	tax
	bmi li_samemus
	sta g_level_music
	jsr play_music            ; rst $18 (game/sonic.asm -> sound/music.asm)
li_samemus
	ldx #63
	lda #0
li_optr
	sta g_object_ptrs,x
	dex
	bpl li_optr
	lda iy_0C_old_lvflag01
	and #$20
	ora iy_06_lvflag01
	sta iy_06_lvflag01
; load_and_run_level po naglowku (00:1D15-00:1D3D); autoscroll (iy_05 bit 3) - na koncu
	lda iy_02
	ora #3
	sta iy_02
	lda iy_00
	ora #3                    ; bit 1 z 00:1D1D, bit 0 = IRQ po wait_until_irq_ticked
	and #$BF
	sta iy_00
	lda iy_06_lvflag01
	ora #$08
	and #$BF
	sta iy_06_lvflag01
	lda iy_07_lvflag02
	and #$F7
	sta iy_07_lvflag02
	lda iy_09
	and #$FE
	sta iy_09
	lda iy_08_lvflag03
	and #$FE
	sta iy_08_lvflag03
	lda iy_05_lvflag00        ; 00:1D39: autoscroll w prawo (b3; BRI2) - set_right_autoscroll_start_pos (00:1ED8):
	and #$08                  ; granice poziomu x0 = x1 = kamera X
	beq li_noas
	lda g_level_scroll_x_pix_lo
	sta g_level_limit_x0
	sta g_level_limit_x1
	lda g_level_scroll_x_pix_lo+1
	sta g_level_limit_x0+1
	sta g_level_limit_x1+1
li_noas
	rts

; ---------------------------------------------------------------------
; load_object_list (00:232B): Sonic (typ 0) z pozycji startowej (tmp_08), potem lista poziomu z banku poziomu
; (LB_OBJLIST: N = obiekty z Sonikiem, N-1 trojek typ, X/32, Y/32), g_object_count = N; sloty N..31 dostaja
; tylko typ $FF (reszta bajtow zostaje). Test (--obiekty, v_obj_filt_on): w slotach 1-31 zostaja tylko typy
; z maski v_obj_filt, pozostale typ $FF - jak m3_ref.lua.
; ---------------------------------------------------------------------
load_object_list
	mwa #object_list zg_dst
	lda tmp_08                ; Sonic: pozycja (tmp_08) w lustrze
	sta zg_src
	lda tmp_08+1
	clc
	adc #>SMS_RAM
	sta zg_src+1
	lda #0
	jsr lo_spec
	lda v_pblevel             ; M6.3: bank poziomu (GHZ1 35, GHZ2 55, GHZ3 57)
	sta PORTB
	mwa #BANK_WIN+LB_OBJLIST zg_src
	ldy #0
	lda (zg_src),y
	sta g_object_count
	sec
	sbc #1
	sta v_lo_n
	inc zg_src
lol_list
	ldy #0
	lda (zg_src),y            ; typ
	inc zg_src
	bne lol_s
	inc zg_src+1
lol_s
	jsr lo_spec
	dec v_lo_n
	bne lol_list
	lda #PB_MAIN
	sta PORTB
	lda #N_OBJECTS
	sec
	sbc g_object_count
	beq lol_filt
	sta v_lo_n
lol_ff
	ldy #OB_TYPE
	lda #$FF
	sta (zg_dst),y
	clc
	lda zg_dst
	adc #OBJ_SIZE
	sta zg_dst
	bcc lol_ffn
	inc zg_dst+1
lol_ffn
	dec v_lo_n
	bne lol_ff
lol_filt
	lda v_obj_filt_on
	beq lol_ret
	mwa #object_list+OBJ_SIZE zg_dst
	ldx #N_OBJECTS-1
lol_f
	ldy #OB_TYPE
	lda (zg_dst),y
	pha
	and #7
	tay
	lda bit_tab,y
	sta v_lo_bit
	pla
	lsr
	lsr
	lsr
	tay
	lda v_obj_filt,y
	and v_lo_bit
	bne lol_keep
	ldy #OB_TYPE
	lda #$FF
	sta (zg_dst),y
lol_keep
	clc
	lda zg_dst
	adc #OBJ_SIZE
	sta zg_dst
	bcc lol_fn
	inc zg_dst+1
lol_fn
	dex
	bne lol_f
lol_ret
	rts

; lo_spec: load_object_from_level_spec (00:235E) - A = typ, (zg_src) = X/32, Y/32 -> rekord (zg_dst): X, Y
; = bajt * 32 (subpiksele 0), bajty +7..+25 = 0; zg_src += 2, zg_dst += 26
lo_spec
	ldy #OB_TYPE
	sta (zg_dst),y
	ldy #0
	lda (zg_src),y
	jsr tile_px
	ldy #OB_X+1
	sta (zg_dst),y
	iny
	txa
	sta (zg_dst),y
	ldy #1
	lda (zg_src),y
	jsr tile_px
	ldy #OB_Y+1
	sta (zg_dst),y
	iny
	txa
	sta (zg_dst),y
	lda #0
	ldy #OB_X
	sta (zg_dst),y
	ldy #OB_Y
	sta (zg_dst),y
	ldy #7
los_z
	sta (zg_dst),y
	iny
	cpy #OBJ_SIZE
	bne los_z
	clc
	lda zg_src
	adc #2
	sta zg_src
	bcc los_s
	inc zg_src+1
los_s
	clc
	lda zg_dst
	adc #OBJ_SIZE
	sta zg_dst
	bcc los_d
	inc zg_dst+1
los_d
	rts

start_tile                      ; A = max(A - 3, 0)
	sec
	sbc #3
	bcs st_ok
	lda #0
st_ok
	rts

tile_px                         ; A = kafel/blok -> A = lo(A*32), X = hi(A*32)
	pha
	lsr
	lsr
	lsr
	tax
	pla
	and #7
	asl
	asl
	asl
	asl
	asl
	rts

; =====================================================================
;  M6.9 Scrap Brain: pod-poziomy SBZ2 ($14-$19) - korytarz $13 i teleport $0B (iy_06 b4, g_next_level_override_target)
; =====================================================================

; sky_palset (M6.10, @palette_selected 00:1F80-00:1F94): zestaw palet cyklu blyskawic SKY1 X (0 = 1A, 1 = 1B, 2 = 1C). Lustro RAM SMS
; jak oryginal (g_palette_cycle_tick_remain = 2, szybkosc 2, indeks 0, liczba 4, g_palette_cycle_baseptr = LVCYCPAL1_SKY_1A/1B/1C
; 01:645E/649E/64DE - LUT_SKY1_lightning_* 00:1F9D) i model portu: 4 palety (192 B RGB) z banku SKY1 (LB_PALS + 48 / LB_LIGHT1B /
; LB_LIGHT1C - tools/extract_sms.py) do PAL_RAM + 48, v_cyc_timer = v_cycspd = 2, v_cyccnt = 4, v_cyc_idx = 0 (update_palette_cycle
; 00:23C9 = nmi_cyc, kernel/nmi.asm); cykl w NMI wstrzymany na czas kopii.
sky_palset
	lda #2
	sta g_palette_cycle_tick_remain
	sta g_palette_cycle_tick_remain+1
	lda #0
	sta g_palette_cycle_tick_remain+2
	lda #4
	sta g_palette_cycle_tick_remain+3
	lda spl_lo,x
	sta g_palette_cycle_baseptr
	lda #$64
	sta g_palette_cycle_baseptr+1
	lda spl_src_lo,x
	sta zp_src
	lda spl_src_hi,x
	sta zp_src+1
	lda v_cyc_on
	pha
	lda #0
	sta v_cyc_on
	lda v_pblevel
	sta PORTB
	ldy #0
spl_cp
	lda (zp_src),y
	sta PAL_RAM+48,y
	iny
	cpy #192
	bne spl_cp
	lda #PB_MAIN
	sta PORTB
	lda #2
	sta v_cycspd
	sta v_cyc_timer
	lda #4
	sta v_cyccnt
	lda #0
	sta v_cyc_idx
	pla
	sta v_cyc_on
	rts
spl_lo		dta b($5E, $9E, $DE)                ; LVCYCPAL1_SKY_1A / 1B / 1C (01:645E / 01:649E / 01:64DE)
spl_src_lo	dta l(BANK_WIN+LB_PALS+48, BANK_WIN+LB_LIGHT1B, BANK_WIN+LB_LIGHT1C)
spl_src_hi	dta h(BANK_WIN+LB_PALS+48, BANK_WIN+LB_LIGHT1B, BANK_WIN+LB_LIGHT1C)

; lay_pages: liczba stron ukladu do skopiowania z banku: $15 (obraz LI_LV_SBZ2B - XEX bank 16 PB_LEVELS5, 32 x 128) - 8 (RLE oryginalu
; daje 2048 B, wiersze 64-127 zostaja w RAM z ukladu SBZ2 - load_level_layout 00:20CB nie nadpisuje $C800-$CFFF), inne - 16
lay_pages
	lda v_layfull             ; review M6.9: start z level_boot (kontynuacja po game over, testy) - caly uklad z banku ($15: wiersze 64-127
	bne lp_16                 ; = SBZ2 z tools/extract_sms.py; RAM ukladu nadpisaly ekrany - map2_copy)
	lda v_img+LR_LEVEL        ; M7.2: obraz poziomu (v_img) zamiast banku
	cmp #LI_LV_SBZ2B
	bne lp_16
	lda #8
	rts
lp_16
	lda #16
	rts

; hdr_src: zg_ptr = kopia naglowka (HDR_COPY B) w banku poziomu: zwykle LB_HDR; przy iy_06 b4 i g_next_level_override_target $16-$19
; (naglowek SBZ2 albo $14 z innym startem i bajtami za naglowkiem) - LB_HDRALT + $40 * k (tools/extract_sms.py: $16, $18, $19 w banku
; SBZ2, $17 w banku $14)
hdr_src
	mwa #BANK_WIN+LB_HDR zg_ptr
	lda iy_06_lvflag01
	and #$10
	beq hs_ret
	lda g_next_level_override_target
	sec
	sbc #$16
	cmp #4
	bcs hs_ret
	tax
	lda hs_off,x
	sta zg_ptr
	lda #>[BANK_WIN+LB_HDRALT]
	sta zg_ptr+1
hs_ret
	rts
hs_off	dta b(0, 0, $40, $80)     ; $16 (bank SBZ2), $17 (bank $14), $18, $19 (bank SBZ2)
tele_rng	dta b(RNG_TELE+2, RNG_TELE+1, RNG_TELE+2, RNG_TELE+2, RNG_TELE+2, RNG_TELE+2)   ; $14-$19: 113 IRQ, $15 (RLE 2048 B) 112 (m69-korytarz-*, m69-teleport-*)
		dta b(RNG_TELE+1)         ; M6.10: $1A (m610-korytarz-sky2: 112)

; level_tonext (M6.11): koniec przejscia EXIT_TONEXT (@teleport_to_next 00:201C: g_level + 1 w ust_next, potem main@run_this_level - 60 ramek
; i rst $20, load_and_run_level z naglowkiem g_level) - poziom koncowy $12 po teleporcie z SKY3. random_A w kazdym IRQ przejscia (RNG_TONEXT -
; pomiar Mesena, NTSC + 5 jak restart), dane strefy g_level (inna niz SKY: atlas, uklad, palety, magazyn, sprite'y) i stan jak level_next.
RNG_TONEXT   = 170         ; M6.11: m611-koniec-przejscie 171 / -ntsc 176 random_A od ostatniego rekordu SKY3 (restart + 41: drugie wygaszanie
                           ; main@run_this_level - pierwsze 00:1FC4 robi trans bez random_A, jak przy wyniku)
level_tonext
	ldx #RNG_TONEXT
	lda v_tv
	bne lto_r
	txa
	clc
	adc #5
	tax
lto_r
	jsr random_A
	dex
	bne lto_r
	lda g_level
	sta boot_level
	jsr tele_reload           ; lv_select (strefa boot_level), dane poziomu, palety, magazyn, listy
	jsr load_sprite_data      ; klatki Sonika i sprite'y strefy (render/sprites.asm)
	jmp level_next

; level_tele: koniec przejscia EXIT_TELE (game/trans.asm) - oryginal: @teleport_to_given (00:2020) -> main@run_this_level (00:1CBD:
; drugie fade_screen_to_black, clear_sprite_table, bez 60 ramek i rst $20 przy iy_06 b4) -> load_and_run_level z naglowkiem
; g_next_level_override_target (00:1CF8). random_A w kazdym IRQ przejscia (RNG_TELE - pomiar Mesena), dane pod-poziomu z banku
; (tele_reload) i stan jak level_next: level_init z iy_06 b4 - czas i pierscienie zostaja (00:2146), krok -16.
level_tele
	ldx #RNG_TELE             ; M6.9: przerwania przejscia wg pod-poziomu (ladowanie ukladu i grafiki trwa roznie): m69-korytarz-gora ($14)
	lda g_next_level_override_target ; 113 IRQ od ostatniego rekordu, -dol ($15) 112; $16-$19 - tak jak naglowki tych samych ukladow
	sec
	sbc #$14
	cmp #7                    ; M6.10: $1A (koniec SKY2)
	bcs lte_reg
	tay
	ldx tele_rng,y
lte_reg
	lda v_tv                  ; review M6.9: NTSC - o 6 IRQ dluzej (m69-korytarz-gora-ntsc 119 / 113, -dol-ntsc 118 / 112)
	bne lte_rng
	txa
	clc
	adc #6
	tax
lte_rng
	jsr random_A
	dex
	bne lte_rng
	jsr tele_reload
	jmp level_next

; tele_reload: dane pod-poziomu w czerni (ekran wygaszony): blitter wolny, obraz VBXE wylaczony (wlacza NMI przy drugim flipie - vid_hold), bank
; naglowka (lv_select: iy_06 b4), atlas, uklad, priorytety, palety, mapowanie blokow, pierscienie, magazyn blokow (sloty wg nowej tilemapy)
; i oba komplety listy ramki, lancuch pierscieni i pamiec HUD-u od nowa - jak level_boot (render/load.asm: komplet 1 listy ramki lezy w obszarze
; listy budowy magazynu). Sprite'y strefy i klatki Sonica bez zmian (ta sama strefa).
tele_reload
	jsr wait_blitter
	lda #0                    ; obraz wylaczony na czas ladowania; wlacza go NMI razem z flipem pierwszej listy pod-poziomu (review M6.9:
	ldy #VC_VIDEO             ; game/trans.asm vid_hold - bez klatki starego poziomu w pelnej palecie)
	sta (zp_fx),y
	jsr lv_select
	jsr load_level_data
	jsr load_ring_data
	jsr load_palette
	jsr spr_zone_pal          ; M6.10: paleta sprite'ow pod-poziomu -> SPRPAL_RAM (SKY2 -> $1A: LVPAL3_SKY_3; SBZ - ta sama), rozjasnienie z kopii
	jsr hud_clear             ; jak level_boot: pamiec HUD-u (zh_sig, zh_by) i plotno - komplety list ramki powstaja od nowa
	lda #0                    ; plotno HUD-u wyczyszczone - narysowac w calosci (v_hudc_st), pamiec HUD-u logiki od nowa (v_hudk_ok)
	sta v_hudc_st
	sta v_hudk_ok
	jsr init_lists            ; XDL-e, komplet 0 listy ramki, lista budowy magazynu (szablony - obszar kompletu 1) i przeladowania
	jsr rchain_init           ; lancuch pierscieni i maski slotow (RCMASK_RAM) - inaczej resztki poprzedniego ukladu (smugi pierscieni)
	jsr build_store
	lda #0                    ; M6.10: magazyn bez lat szyby SKY3
	sta v_gl_mask
	sta v_gl_mask+1
	ldx #1
	jmp init_list_set
