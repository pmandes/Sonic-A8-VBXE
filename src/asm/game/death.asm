; =====================================================================
;  death.asm - M3.7: czas gry, timery konca poziomu w petli, wyjscie z poziomu (smierc, koniec dema)
;
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): tick_game_time 00:3A03, petla
;  load_and_run_level@main_level_loop 00:1DC4-00:1E04, handle_level_restart_countdown_timer 00:2067,
;  fade_out_and_stop_level 00:20B8, main@run_this_level 00:1CBD (wywolujacy load_and_run_level, kod w A:
;  0 = tytul, 1 = mapa, 2 = ten sam poziom od nowa).
;  Wyjscie z poziomu konczy krok bez rekordu trace'u i bez zwiekszenia licznika tickow (oryginal wychodzi
;  z load_and_run_level przed 00:1E07). Dalszy ciag (wygaszanie, przerwa, restart) - game/trans.asm.
; =====================================================================
EXIT_NONE    = 0           ; v_lvl_exit: kod wyjscia z poziomu + 1 (0 = gra trwa)
EXIT_TITLE   = 1           ; A = 0: koniec dema (licznik restartu) albo game over bez kontynuacji -> tytul (M6)
EXIT_NEXT    = 2           ; A = 1: koniec aktu po tabliczce (update_signpost_timer) -> nastepny poziom (M4: GHZ1
                           ; od nowa bez punktu kontrolnego; ekran wyniku, etap specjalny i GHZ2 - M6)
EXIT_RESTART = 3           ; A = 2: smierc przy zyciach > 0 -> ten sam poziom od nowa
EXIT_TELE    = 4           ; M6.9: A = $FF z @teleport_to_given (00:2020): korytarz $13 / teleport $0B (iy_06 b4) - pod-poziom
                           ; g_next_level_override_target bez wyniku i mapy (game/trans.asm, game/level.asm level_tele)
EXIT_DEMOBTN = 5           ; A = 0 z 00:1E01: przycisk w demie -> tytul (port: gra joystickiem)
EXIT_TONEXT  = 6           ; M6.10: A = $FF z @teleport_to_next (00:201C: iy_0D b2 - teleport $FF w SKY3): g_level + 1, bez wyniku i mapy,
                           ; z 60 ramkami i rst $20 -> poziom koncowy $12 (M6.11; do tego czasu zaslepka: tytul / nowa gra - game/trans.asm)

; ---------------------------------------------------------------------
; tick_game_time (00:3A03): czas gry co tick, gdy Sonic nie umiera. Subsekundy 0..59 binarnie, sekundy
; i minuty BCD (daa). W gore: 10:00 -> kill_sonic (koniec czasu), minuty = 0. W dol (etap specjalny,
; iy_07 b0): ponizej 0:00 -> g_signpost_tickdown_counter = 1, iy_09 b2, minuty = 0.
; Przeniesienie miedzy polami jak w oryginale (ccf po cp): 1 tylko przy przekroczeniu zakresu pola.
; ---------------------------------------------------------------------
tick_game_time
	lda iy_05_lvflag00
	and #$01
	bne tgt_ret
	ldx #0
	lda g_time_subsecs
	clc
	adc #1
	cmp #$3C
	bcc tgt_sub
	lda #0
	ldx #1
tgt_sub
	sta g_time_subsecs
	lda iy_07_lvflag02
	and #$01
	bne tgt_down
; w gore
	lda g_time_secs_BCD
	jsr bcd_add_x
	ldx #0
	cmp #$60
	bcc tgt_us
	lda #0
	ldx #1
tgt_us
	sta g_time_secs_BCD
	lda g_time_mins
	jsr bcd_add_x
	cmp #$10
	bcc tgt_um
	jsr kill_sonic            ; koniec czasu (00:3A30)
	lda #0
tgt_um
	sta g_time_mins
tgt_ret
	rts
; w dol (@time_ticks_downwards)
tgt_down
	lda g_time_secs_BCD
	jsr bcd_sub_x
	ldx #0
	cmp #$60
	bcc tgt_ds
	lda #$59
	ldx #1
tgt_ds
	sta g_time_secs_BCD
	lda g_time_mins
	jsr bcd_sub_x
	cmp #$60
	bcc tgt_dm
	lda #1
	sta g_signpost_tickdown_counter
	lda iy_09
	ora #$04
	sta iy_09
	lda #0
tgt_dm
	sta g_time_mins
	rts

; bcd_add_x / bcd_sub_x: A = A +/- X (X = 0 albo 1) jak adc/sbc a,$00 + daa dla poprawnego BCD
; (wynik poza BCD, np. $99 + 1 -> $A0, i tak lapie porownanie z $60/$10 wywolujacego)
bcd_add_x
	cpx #0
	beq bcd_ret
	clc
	adc #1
	sta v_bcd
	and #$0F
	cmp #$0A
	bne bcd_add_ok
	lda v_bcd
	adc #5                    ; C = 1 po cmp: +6
	rts
bcd_add_ok
	lda v_bcd
bcd_ret
	rts

bcd_sub_x
	cpx #0
	beq bcd_ret
	sec
	sbc #1
	sta v_bcd
	and #$0F
	cmp #$0F
	bne bcd_sub_hi
	lda v_bcd
	sec
	sbc #6
	sta v_bcd
bcd_sub_hi
	lda v_bcd
	cmp #$A0                  ; pozyczka z dziesiatek ($00 - 1): daa odejmuje tez $60 -> $99
	bcc bcd_ret
	sbc #$60
	rts

; ---------------------------------------------------------------------
; level_timers: 00:1DCB-00:1DF4. Licznik tickow parzysty (przed zwiekszeniem): licznik tablicy konca
; poziomu (update_signpost_timer - M4); nieparzysty: licznik restartu po smierci (wyjscie przy 0), blysk
; palety, blyskawice SKY1 (M6); potem konczenie poziomu (iy_06 b1 - M4). C = 1: wyjscie z poziomu
; (v_lvl_exit ustawione).
; ---------------------------------------------------------------------
level_timers
	lda g_global_tick_counter
	and #$01
	bne lt_restart
	lda g_signpost_tickdown_counter
	beq lt_done
	jsr update_signpost_timer ; M4.8 (00:1FA9); C = 1 - koniec aktu
	bcc lt_done
	rts
lt_restart
	lda g_level_restart_countdown_timer
	beq lt_flash
	dec g_level_restart_countdown_timer ; handle_level_restart_countdown_timer (00:2067)
	bne lt_flash
	jmp level_restart_expired
lt_flash                        ; @return_from_restart_timer_nonexpiry
	lda g_pal_flash_countdown_timer
	beq lt_nosky
	jsr handle_palette_flashing ; 00:1F06 (M6.4)
lt_nosky
	lda iy_07_lvflag02
	and #$02
	beq lt_done
	jsr sky1_lightning        ; M6.10: handle_SKY1_lightning_timer (00:1F49)
lt_done                         ; @continue_from_level_ending_timers
	lda iy_06_lvflag01
	and #$02
	beq lt_ret
	jsr handle_level_finishing ; M4.8 (00:1E78)
lt_ret
	clc
	rts

; ---------------------------------------------------------------------
; update_signpost_timer (00:1FA9, M4.8): licznik tablicy konca - 1 (tick parzysty). Przy $88 nagroda wg
; g_current_signpost (LUT_signpost_funcs 00:2023): 1 nic (efekt $0E), 2 zycie (+1, efekt $09), 3 pierscienie (+16),
; 4 etap specjalny (efekt $07, set 0 iy_07); 0 - nic. Przy 0 (@go_to_next_level): wyjscie z poziomu (kod 1) -
; wygaszanie i dalszy ciag w game/trans.asm (oryginal: fade_screen_to_black, res 5 iy_00, ekran wyniku, g_level + 1
; albo etap specjalny - M6). C = 1: wyjscie (v_lvl_exit).
; ---------------------------------------------------------------------
update_signpost_timer
	dec g_signpost_tickdown_counter
	beq ust_next
	lda g_signpost_tickdown_counter
	cmp #$88
	bne ust_ret
	lda g_current_signpost
	cmp #1
	beq ust_nothing
	cmp #2
	beq ust_life
	cmp #3
	beq ust_rings
	cmp #4
	bne ust_ret               ; 0 (ENTRY_RESET w tablicy - or h / ret z) i inne: nic
	lda #$07                  ; signpost_func_bonus_stage: efekt $07, set 0 iy_07
	jsr play_sfx
	lda iy_07_lvflag02
	ora #$01
	sta iy_07_lvflag02
ust_ret
	clc
	rts
ust_nothing                     ; signpost_func_nothing: efekt $0E
	lda #$0E
	jsr play_sfx
	clc
	rts
ust_life                        ; signpost_func_extra_life
	inc g_lives
	lda #$09
	jsr play_sfx
	clc
	rts
ust_rings                       ; signpost_func_10_rings: add_A_rings $10
	lda #$10
	jsr add_A_rings
	clc
	rts
ust_next                        ; @go_to_next_level
	lda iy_0D                 ; M6.10: bit 2,(iy+$0D) (00:1FCC) -> @teleport_to_next: g_level + 1 (00:201C), A = $FF - EXIT_TONEXT
	and #$04                  ; (res 5,(iy+0) jak przy pod-poziomie)
	bne ust_tnext
	lda iy_06_lvflag01        ; M6.9: bit 4,(iy+6) -> @teleport_to_given (00:1FD2): przejscie do pod-poziomu (EXIT_TELE)
	and #$10
	bne ust_tele
	lda #EXIT_NEXT
	sta v_lvl_exit
	sec
	rts
ust_tele
	lda iy_00                 ; res 5,(iy+0) (00:1FC8): w pierwszej klatce pod-poziomu load_scroll_tile_list_buffers nie pisze tmp_00/02
	and #$DF                  ; (krok -15: tmp z draw_HUD_sprites - m69-korytarz-*)
	sta iy_00
	lda #EXIT_TELE
	sta v_lvl_exit
	sec
	rts
ust_tnext
	lda iy_00
	and #$DF
	sta iy_00
	inc g_level
	lda #EXIT_TONEXT
	sta v_lvl_exit
	sec
	rts

; sky1_lightning (M6.10, handle_SKY1_lightning_timer 00:1F49-00:1F9C; wolane co drugi tick przy iy_07 b1 - SKY1): de = g_lightning_timer
; (16 bit). de > $AA -> zestaw palet cyklu 1A i de = 0; de = $82 -> 1C i grzmot (rst $28, SFX $13); de = $64 -> 1B; de = 0 -> 1A
; (pierwszy tick swiezej gry: szybkosc cyklu 2 zamiast 6 z naglowka); inne - bez zmian; potem de + 1. Przy de > $82 przeniesienie z
; sbc $82 - de psuje porownanie z $64 ($64 - de - 1 nie daje 0 dla de $83..$AA) - wynik jak porownanie wprost. Zestaw: sky_palset.
sky1_lightning
	lda g_lightning_timer+1
	bne slt_wrap
	lda g_lightning_timer
	cmp #$AB
	bcs slt_wrap
	cmp #$82
	beq slt_1c
	cmp #$64
	beq slt_1b
	cmp #0
	bne slt_inc
	tax                       ; de = 0: 1A
	beq slt_sel               ; zawsze
slt_wrap
	lda #0
	sta g_lightning_timer
	sta g_lightning_timer+1
	tax
	beq slt_sel               ; zawsze (1A)
slt_1c
	lda #$13                  ; @play_lightning_sound
	jsr play_sfx
	ldx #2
	bne slt_sel               ; zawsze
slt_1b
	ldx #1
slt_sel
	jsr sky_palset            ; @palette_selected (game/level.asm - bank poziomu)
slt_inc
	inc g_lightning_timer     ; @skip_palette_change: inc de
	bne slt_ret
	inc g_lightning_timer+1
slt_ret
	rts

; handle_level_finishing (00:1E78, M4.8): po tabliczce Sonic biegnie w prawo (wejscie $F7) do x >= x0 + $112, potem
; wejscie $FF i Vx = Vy = 0
handle_level_finishing
	lda #$F7
	sta g_inputs_player_1
	clc                       ; DE = g_level_limit_x0 + $0112; xor a / sbc hl,de (sonic_x): pozyczka -> ret
	lda g_level_limit_x0
	adc #$12
	sta zs_t
	lda g_level_limit_x0+1
	adc #$01
	sta zs_t+1
	sec
	lda sonic_x
	sbc zs_t
	lda sonic_x+1
	sbc zs_t+1
	bcc hlf_ret
	lda #$FF
	sta g_inputs_player_1
	lda #0
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
	sta sonic_vel_y_sub
	sta sonic_vel_y
	sta sonic_vel_y_hi
hlf_ret
	rts

; level_restart_expired: handle_level_restart_countdown_timer przy 0 (00:206E). Demo -> fade_out_and_stop_level
; (kod 0). Teleport (iy_0C b4) -> iy_06 b4; woda (iy_06 b7) -> disable_waterline_for_level_end_or_restart.
; Zycia > 0 -> kod 2. Zycia = 0 -> wygaszenie, res 5 iy_00, ekran game over (M6) bez kontynuacji -> kod 0.
level_restart_expired
	lda iy_05_lvflag00
	and #$02
	bne lre_title
	lda iy_0C_old_lvflag01
	and #$10
	beq lre_notele
	lda iy_06_lvflag01
	ora #$10
	sta iy_06_lvflag01
lre_notele
	lda iy_06_lvflag01
	and #$80
	beq lre_nowater
	lda iy_06_lvflag01        ; disable_waterline_for_level_end_or_restart (00:20A4)
	and #$7F
	sta iy_06_lvflag01
	lda #0
	sta g_water_onscreen_y
	sta g_water_level_onscreen_y
lre_nowater
	lda g_lives
	beq lre_gameover
	lda #EXIT_RESTART
	bne lre_exit
lre_gameover
	lda iy_00
	and #$DF                  ; res 5,(iy+0) (00:2092)
	sta iy_00
lre_title
	lda #EXIT_TITLE
lre_exit
	sta v_lvl_exit
	sec
	rts

; handle_palette_flashing (00:1F06): licznik migotania - 1; kolor o indeksie g_pal_flash_idx (b7: paleta sprite'ow)
; w CRAM = kolor migotania (g_pal_flash_color_value) przy nieparzystym liczniku, inaczej kolor palety. Port: stan
; (licznik) i zadanie dla renderera (v_flash_req, v_flash_idx, v_flash_odd - render/sprites.asm).
handle_palette_flashing
	dec g_pal_flash_countdown_timer
	lda g_pal_flash_idx
	sta v_flash_idx
	lda g_pal_flash_countdown_timer
	and #$01
	sta v_flash_odd
	lda #1
	sta v_flash_req
	rts

; demo_button_exit: 00:1DFD - w demie przycisk (b5 wejscia z portu = 0) -> fade_out_and_stop_level (kod 0)
demo_button_exit
	lda #EXIT_DEMOBTN
	sta v_lvl_exit
	sec
	rts
