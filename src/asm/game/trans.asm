; =====================================================================
;  trans.asm - M3.7: przejscie po wyjsciu z poziomu (v_lvl_exit z game/death.asm)
;
;  Oryginal: main@run_this_level (00:1CBD): fade_screen_to_black (00:0A40: 1 ramka, potem 4 kroki
;  palette_fade_to_black co 10 ramek - kazda skladowa 2-bitowa -1), clear_sprite_table, przy fladze
;  umierania 60 ramek przerwy (00:1CCF), load_and_run_level od nowa. Koniec dema i game over: wygaszenie,
;  dalej ekran tytulu; koniec aktu - ekran wyniku (M6.2), game over - ekran game over (M6.3, wydanie).
;  Port: w tych ramkach petla Atari nie wykonuje krokow SMS (sms_step) - lista ramki rysuje zamrozony stan,
;  wygaszanie robi renderer (render/fade.asm). Na koncu:
;   - kod 2 (restart): level_restart - nastepne zycie bez game_reset (zycia, licznik tickow, wynik zostaja);
;   - koniec dema: nowe demo; game over: nowa gra; przycisk w demie: gra joystickiem (wydanie: ekrany, boot.asm).
;  Kazdy nowy start poziomu = nastepny segment trace'u (v_segment, kroki +100000 w tools/m3_trace.py).
; =====================================================================
TR_FADE0  = 2           ; ramka pierwszego kroku wygaszania (po wait_until_irq_ticked)
TR_FSTEP   = 10          ; ramki miedzy krokami
TR_HIDE   = 42          ; po 4 krokach: clear_sprite_table
TR_LAST    = 102         ; + 60 ramek przerwy -> nowy start poziomu
TR_LAST_TELE = 83        ; M6.9: EXIT_TELE - drugie fade_screen_to_black (00:1CBD, 41 ramek) bez 60 ramek przerwy (00:1CC9) -> pod-poziom

trans_start
	lda #1
	sta v_trans
	lda #0
	sta v_trans_cnt
	sta v_cyc_on              ; cykl palety stoi (update_palette_cycle tylko w petli poziomu)
	lda iy_05_lvflag00        ; M5: demo (koniec licznika 00:2072, przycisk 00:1DFD) - fade_out_and_stop_level
	and #$02                  ; (00:20B8): wyciszanie muzyki. Restart i game over (00:208C) - tylko obraz,
	beq ts_ret                ; muzyka smierci gra dalej (ekran game over - M6)
	jmp snd_music_fade
ts_ret
	rts

; trans_step: raz na ramke zamiast sms_step
trans_step
	inc v_trans_cnt
	lda v_trans_cnt
	ldx #1
ts_fade
	cmp ts_fade_tab-1,x
	beq ts_do_fade
	inx
	cpx #5
	bne ts_fade
	cmp #TR_HIDE
	bne ts_nohide
	lda v_lvl_exit            ; M6.8: koniec aktu (00:1FD9) - bit 7,(iy+6) / call nz, disable_waterline_for_level_end_or_restart
	cmp #EXIT_NEXT            ; (00:20A4): res 7 iy_06, g_water_onscreen_y = g_water_level_onscreen_y = 0 (petla czekania na koniec
	bne ts_nowat              ; przerwan linii - w porcie ich nie ma). LAB1/LAB2: flage kasuje juz tabliczka, LAB3 - kapsula.
	lda iy_06_lvflag01
	bpl ts_nowat
	and #$7F
	sta iy_06_lvflag01
	lda #0                    ; paleta zostaje pelna: oryginal (Mesen, l3end klatka 41) pokazuje poziom w palecie podwodnej az do
	sta g_water_onscreen_y    ; wylaczenia obrazu przez ekran wyniku - czerni przed nim nie ma
	sta g_water_level_onscreen_y
ts_nowat
	.ifdef RELEASE
	lda v_lvl_exit            ; M6.2 (wydanie): koniec aktu - po wygaszeniu ekran wyniku (src/scr/boot.asm)
	cmp #EXIT_NEXT
	jeq boot_score
	cmp #EXIT_TONEXT          ; M6.11: @teleport_to_next z poziomu $12 (g_level = $13) - ekrany konca gry (boot_end); z SKY3 - poziom $12
	bne ts_noend              ; (level_tonext na koncu przejscia)
	lda g_level
	cmp #$13
	jcs boot_end
	lda v_lvl_exit
ts_noend
	cmp #EXIT_TITLE           ; M6.3 (wydanie): game over (zycia = 0, nie demo) - po wygaszeniu ekran game over
	bne ts_nogo
	lda iy_05_lvflag00
	and #$02
	jeq boot_gameover
ts_nogo
	.endif
	lda #1
	sta v_hide_spr
	rts
ts_nohide
	ldx v_lvl_exit            ; M6.9: korytarz / teleport - krotsze przejscie (bez przerwy)
	cpx #EXIT_TELE
	bne ts_nolast
	cmp #TR_LAST_TELE
	beq trans_end
	rts
ts_nolast
	cmp #TR_LAST
	beq trans_end
	rts
ts_do_fade
	lda iy_06_lvflag01        ; M6.8: flaga wody (iy_06 b7) - IRQ oryginalu laduje palety wody i cyklu bez wygaszania (00:0184 ->
	bmi tsf_ret               ; 00:019C): przy koncu LAB3 (kapsula nie kasuje flagi) ekran jasny do 00:1FD9; LAB1/LAB2 - flage kasuje
	txa                       ; tabliczka, smierc - 00:20A4 przed wygaszaniem. Poziom wygaszania 1..4
	jmp pal_fade
tsf_ret
	rts

ts_fade_tab
	dta b(TR_FADE0, TR_FADE0+TR_FSTEP, TR_FADE0+2*TR_FSTEP, TR_FADE0+3*TR_FSTEP)

; vid_hold (review M6.9): po przeladowaniu poziomu (restart, pod-poziom, nowa gra) bufor tylny ma jeszcze liste starego stanu, a
; render_level_reset przywraca pelna palete - obraz VBXE wylaczony teraz i wlaczony przez NMI przy drugim flipie (pierwsza lista nowego
; stanu; kernel/nmi.asm). Oryginal wylacza obraz VDP na czas ladowania (load_and_run_level).
vid_hold
	lda #0
	ldy #VC_VIDEO
	sta (zp_fx),y
	lda #2
	sta v_vid_wait
	rts

trans_end
	inc v_segment
	lda v_lvl_exit            ; M6.9: korytarz / teleport (@teleport_to_given): bez rst $20 - muzyka gra dalej (00:1CC9 omija 00:1CDA)
	cmp #EXIT_TELE
	bne te_stop
	jsr level_tele            ; pod-poziom: dane z banku, magazyn blokow, stan (czas i pierscienie zostaja) - game/level.asm
	jmp te_render
te_stop
	jsr snd_music_stop        ; M5: rst $20 przed load_and_run_level (main 00:1CDA)
	lda v_lvl_exit
	cmp #EXIT_NEXT            ; M4.8: koniec aktu - w M4 ten sam poziom od nowa (bez punktu kontrolnego; M6: wynik,
	bne te_nonext             ; nastepny akt). Zycia, wynik i licznik tickow zostaja jak przy restarcie po smierci.
	jsr level_mask
	eor #$FF
	and g_level_has_checkpoint_mask,x
	sta g_level_has_checkpoint_mask,x
	jsr level_restart
	jmp te_render
te_nonext
	cmp #EXIT_RESTART
	bne te_tonext
	jsr level_restart
	jmp te_render
te_tonext
	cmp #EXIT_TONEXT          ; M6.11: @teleport_to_next - poziom koncowy $12 w miejscu; po nim ($13) ekrany konca (wydanie)
	bne te_title
	lda g_level
	cmp #$13
	bcs te_title              ; $13: ekrany konca - M6.11 krok 4 (do tego czasu: tytul / nowa gra)
	jsr level_tonext
	jmp te_render
te_title
	.ifdef RELEASE
	jmp boot_title_warm       ; M6 krok 1 (wydanie): koniec dema, przycisk w demie -> ekran tytulowy (game over:
	.endif                    ; boot_gameover wyzej, M6.3; main@reset_game_state), poziom z pamieci
	cmp #EXIT_DEMOBTN
	bne te_new
	lda #IN_JOY               ; przycisk w demie: tytul (M6) -> od razu gra joystickiem
	sta v_input_mode
te_new
	lda iy_06_lvflag01        ; review M6.9: game over w pod-poziomie - nowa gra od aktu boot_level: bez pod-poziomu, dane aktu od nowa,
	and #$EF                  ; gdy obraz poziomu nie jest obrazem aktu (pod-poziom, atlas $1A)
	sta iy_06_lvflag01
	ldx boot_level
	cpx #ZONE_N
	bcs ten_ok
	txa                       ; M7.2: rola poziom aktu z ldr_lvl[boot_level] (dawniej zn_level) wobec biezacego obrazu poziomu v_img
	asl                       ; (XEX: oba = PORTB banku; wpis aktu bez bitu alt - tez nosnik)
	asl
	tax
	lda ldr_lvl+LR_LEVEL,x
	cmp v_img+LR_LEVEL
	bne ten_rel
	lda v_gl_mask             ; review M6.10: magazyn z latami szyby SKY3 - dane aktu od nowa (jak level_restart)
	ora v_gl_mask+1
	beq ten_ok
ten_rel
	jsr tele_reload
ten_ok
	jsr level_start           ; budowa testowa: koniec dema -> nowe demo; game over -> nowa gra (bez ekranow)
te_render
	jsr vid_hold              ; review M6.9: obraz wylaczony do flipu pierwszej listy nowego stanu (NMI)
	jsr render_level_reset
	lda #0
	sta v_trans
	sta v_lvl_exit
	rts
