; =====================================================================
;  step.asm - krok petli poziomu SMS (raz na ramke): rozgrzewka load_and_run_level@each_level_warmup_frame
;  (00:1D42, kroki -15..0) i tick load_and_run_level@main_level_loop (00:1DAE, kroki 1..).
;  Ksiegowosc petli (wejscie, demo, licznik tickow, granice kamery), draw_HUD_sprites: kamera (M3.4,
;  cam_tick) i Sonic (M3.3: sonic_objfunc + obj_motion), potem update_active_scroll_pos_and_ptrs
;  (scroll_update); pierscienie (M3.5: lata ekranu z IRQ, animacja kafli - game/rings.asm); obiekty, czas
;  i paleta - kolejne kroki. Po kazdym kroku rekord trace'u.
; =====================================================================

; level_start: stan po zaladowaniu poziomu = krok -16 (pierwszy rekord trace'u)
level_start
	jsr game_reset
	jsr level_init
	mwa #-16 v_step
	lda #0
	sta v_tr_irq
	jsr step_record_defaults
	jmp trace_record

sms_step
	lda #$FF                  ; M5.4: zgloszenie efektu w tym ticku (test - jak Lua referencji po rekordzie)
	sta g_sfx_req_TEST
	lda v_step                ; M6.8: licznik krokow nasycony na $7FFF - bez przekrecenia na ujemne (= rozgrzewka: wejscie $FF,
	cmp #$FF                  ; bez licznika sprite'ow 21) po 32768 krokach w jednym akcie (ok. 9:06 czasu gry, przed koncem
	bne ss_incok              ; czasu 10:00); oryginal ma rozgrzewke jako osobna petle 16 klatek (00:1D42), bez licznika
	lda v_step+1
	cmp #$7F
	beq ss_inc
ss_incok
	inc v_step
	bne ss_inc
	inc v_step+1
ss_inc
	lda #1
	sta v_tr_irq              ; jedno przerwanie (ramka) na krok
	jsr step_record_defaults
	lda v_step+1
	bmi ss_warmup
	ora v_step
	beq ss_warmup             ; krok 0 = ostatnia klatka rozgrzewki
	jmp ss_tick

; rozgrzewka (00:1D42): IRQ ramki, wejscie $FF, licznik tickow, kafle pierscienia, granice kamery dla Sonica
ss_warmup
	lda v_tr_fl
	ora #F_ROZGRZEWKA
	sta v_tr_fl
	jsr irq_tile_patch        ; IRQ (wait_until_irq_ticked): lata ekranu po zebraniu pierscienia
	jsr irq_sprites_rng       ; M4.1: IRQ - tablica sprite'ow wyslana (licznik 0), random_A
	lda #$FF
	sta g_inputs_player_1
	jsr inc_tick_counter
	jsr ss_ring_tiles         ; 00:1D5D: update_ring_tiles (iy_05 b2)
	mwa #$0060 g_camera_sonic_bounds_x0
	mwa #$0060 g_camera_sonic_bounds_y0
	mwa #$0088 g_camera_sonic_bounds_x1
	mwa #$0070 g_camera_sonic_bounds_y1
	jsr ring_art_timer        ; 00:1D7C: update_ring_tile_art_timer_and_index (zawsze)
	lda g_inputs_player_1
	sta v_tr_in               ; Sonic (draw_HUD_sprites) widzi $FF
	jsr level_frame           ; draw_HUD_sprites (00:1D8F) i update_active_scroll_pos_and_ptrs (00:1D92)
	lda iy_00
	ora #$20
	sta iy_00
	lda v_step
	ora v_step+1
	bne ss_rec
	lda iy_05_lvflag00        ; po rozgrzewce (00:1D9F): demo od poczatku tablicy
	and #2
	beq ss_rec
	lda #0
	sta g_demo_next_input_relptr
	sta g_demo_next_input_relptr+1
	sta g_sprite_count
ss_rec
	jmp trace_record

; tick (00:1DAE): IRQ czyta port -> wejscie i kladzie late ekranu; kafle pierscienia; czas gry (M3.7);
; timery konca poziomu i licznik restartu (M3.7: wyjscie z poziomu konczy krok bez rekordu); w demie
; wyjscie przyciskiem albo update_demo_inputs; licznik tickow; animacja pierscienia
ss_tick
	jsr irq_tile_patch
	jsr irq_sprites_rng       ; M4.1
	jsr read_input
tick_go                         ; test: wymuszenie stanu w kroku v_step (jak m3_ref.py --poke na 00:1DB5)
	jsr ss_ring_tiles         ; 00:1DBD: update_ring_tiles (iy_05 b2)
	lda iy_06_lvflag01        ; 00:1DC4: tick_game_time (iy_06 b3)
	and #$08
	beq ss_notime
	jsr tick_game_time
ss_notime
	jsr level_timers          ; 00:1DCB-00:1DF4
	bcs ss_exit
	lda iy_05_lvflag00
	and #2
	beq ss_nodemo
	lda g_inputs_player_1     ; 00:1DFD: przycisk w demie (b5 portu = 0) -> fade_out_and_stop_level
	and #$20
	bne ss_demo_go
	jsr demo_button_exit
ss_exit
	rts                       ; wyjscie z poziomu: bez licznika tickow, rysowania i rekordu (game/trans.asm)
ss_demo_go
	jsr update_demo_inputs
ss_nodemo
	lda g_inputs_player_1
	sta v_tr_int              ; load_and_run_level@skip_demo_playback (00:1E07)
	jsr inc_tick_counter
	lda iy_05_lvflag00        ; 00:1E0E: autoscroll w prawo (b3; BRI2)
	and #$08
	beq ss_noas
	jsr advance_right_autoscroll
ss_noas
	lda iy_05_lvflag00        ; 00:1E15: autoscroll w gore (b4, VESTIGIAL)
	and #$10
	beq ss_noup
	jsr advance_bottom_up_autoscroll
ss_noup
	lda iy_05_lvflag00        ; 00:1E1C: zapadka w gore (b7): dolna granica = kamera Y
	bpl ss_noscroll
	jsr apply_bottom_up_scroll_ratchet
ss_noscroll
	lda iy_05_lvflag00        ; 00:1E26: update_ring_tile_art_timer_and_index (iy_05 b2 = pierscienie)
	and #$04
	beq ss_noart
	jsr ring_art_timer
ss_noart
	lda v_throb               ; M6.5: zderzak etapu specjalnego (sh_bumper) tylko w tym kroku; oryginal zeruje Y wpisow 0-20
	bne ss_throb              ; na poczatku ticku ($E0) - po zderzaku wpisy 0-7 znowu poza ekranem (Mesen: m65-ss2-bieg)
	lda v_water               ; M6.8: poziom z woda (flaga naglowka; iy_06 b7 kasuje tabliczka, a linia wody pisze dalej) - przednie
	ora v_front               ; wpisy 0-11 ($40, $20) i 20 (cyfra) od nowa z Y = $E0 (00:1E3E-00:1E4E: wpisy 0-20); M6.10: SKY2 - chmury $30
	beq ss_nothrob            ; (wpisy 0-11); inne poziomy ich nie uzywaja
	ldx #20*3+1               ; Y wpisu 20
	lda #$E0
	bne ss_thr                ; zawsze
ss_throb
	ldx #22
	lda #$E0
ss_thr
	sta SPRTAB_R,x
	dex
	dex
	dex
	bpl ss_thr
ss_nothrob
	lda #0                    ; M4.1 (00:1E2D-00:1E3B): bez nadpisania sprite'a Sonica, licznik sprite'ow 21,
	sta v_throb
	sta g_sonic_sprite_index_override ; wskaznik na wpis 21 (wpisy 0-20 z Y = $E0 - renderer ich nie uzywa,
	sta g_frontmost_sprite_table_offs ; test porownuje wpisy od 21)
	lda #21
	sta g_sprite_count
	lda #<$D03F
	sta g_next_avail_vdp_sprite_ptr
	lda #>$D03F
	sta g_next_avail_vdp_sprite_ptr+1
	lda g_inputs_player_1
	sta v_tr_in               ; wejscie widziane przez Sonica
	jsr level_frame           ; draw_HUD_sprites (00:1E60) i update_active_scroll_pos_and_ptrs (00:1E63)
	jmp trace_record

; advance_right_autoscroll (00:1EE2): co drugi tick (g_global_tick_counter b0 = 1; po inc_tick_counter) lewa i prawa granica
; poziomu x + 1 - kamera (bez sledzenia Sonica przy iy_05 b3, game/camera.asm) jedzie 0,5 px na tick
advance_right_autoscroll
	lda g_global_tick_counter
	lsr
	bcc ara_ret
	inc g_level_limit_x0
	bne ara_x
	inc g_level_limit_x0+1
ara_x
	lda g_level_limit_x0
	sta g_level_limit_x1
	lda g_level_limit_x0+1
	sta g_level_limit_x1+1
ara_ret
	rts

; advance_bottom_up_autoscroll_VESTIGIAL (00:1EF2): co drugi tick dolna granica y1 - 1
advance_bottom_up_autoscroll
	lda g_global_tick_counter
	lsr
	bcc abu_ret
	lda g_level_limit_y1
	bne abu_d
	dec g_level_limit_y1+1
abu_d
	dec g_level_limit_y1
abu_ret
	rts

; apply_bottom_up_scroll_ratchet (00:1EFF): dolna granica y1 = kamera Y
apply_bottom_up_scroll_ratchet
	lda g_level_scroll_y_pix_lo
	sta g_level_limit_y1
	lda g_level_scroll_y_pix_lo+1
	sta g_level_limit_y1+1
	rts

; level_frame: draw_HUD_sprites bez HUD-u (sprite'y HUD-u - renderer): kamera (cele granic, adjust_camera,
; zerowanie celow), obiekty (Sonic); potem update_active_scroll_pos_and_ptrs
; (load_scroll_tile_list_buffers - renderer Atari ma wlasne przeladowanie tla)
level_frame
	jsr draw_hud              ; M3.7c: draw_HUD_sprites 00:2E5A-00:2E93 (res 7 iy_07, tekst i sprite'y HUD-u)
	jsr cam_tick
	jsr objects_tick          ; M4.1: aktywacja (00:2EDF) i obiekty 1..31 (00:2EE2) - bank 45, game/objcom.asm
	lda g_inputs_player_1     ; M4.5: wejscie widziane przez Sonica - po obiektach (damage_sonic od wroga
	sta v_tr_in               ; ustawia $FF przed funkcja Sonica; trace oryginalu zapisuje je tak samo)
	jsr sonic_tick
	jsr scroll_update
; M4.1: load_scroll_tile_list_buffers (00:06BD, po update_active_scroll_pos_and_ptrs) - listy kafli VDP buduje
; renderer Atari po swojemu, ale w RAM gry zostaje: przy iy_00 b5 tmp_02 = tablica flag blokow strefy, przy
; iy_02 b0 tmp_00 = ((scroll_x [+ 8, gdy w lewo - iy_00 b6]) & $1F) >> 3, przy iy_02 b1 tmp_00 =
; ((scroll_y & $1F) >> 1) & $FC (tmp_01 = 0)
	lda iy_00
	and #$20
	beq lf_ret
	lda v_tf_ptr
	sta tmp_02
	lda v_tf_ptr+1
	sta tmp_02+1
	lda iy_02
	lsr
	bcc lf_noh
	bit iy_00
	lda g_vdp_scroll_x
	bvc lf_r
	clc
	adc #8
lf_r
	and #$1F
	lsr
	lsr
	lsr
	sta tmp_00
	lda #0
	sta tmp_00+1
lf_noh
	lda iy_02
	and #$02
	beq lf_ret
	lda g_vdp_scroll_y
	and #$1F
	lsr
	and #$FC
	sta tmp_00
	lda #0
	sta tmp_00+1
lf_ret
	rts

; sonic_tick: run_all_objfuncs dla Sonica (00:32AB): objfunc_00_sonic, potem return_from_objfunc (ruch
; i kolizje z mapa). Rysowanie Sonica (wpisy 12+ tablicy sprite'ow, licznik i wskaznik przywracane) robi
; renderer z rekordu Sonica (M3.6); z draw_sprite_string zostaje w RAM tylko tmp_06 = x ekranowe (00:350F),
; gdy mapa Sonica != 0.
sonic_tick
	lda object_list+OB_TYPE   ; M6.11: petla obiektow (00:32C8: typ $FF - ret z) - slot Sonika z typem $FF (poziom koncowy $12: kontroler $53
	cmp #$FF                  ; ukrywa Sonika do jego pojawienia sie) - bez funkcji Sonika, ruchu i flagi rekordu
	bne st_go
	rts
st_go
	lda g_sprite_count        ; M6.8: push af (00:32AB) - licznik sprite'ow przywracany po Soniku (00:32C4): cyfra tonienia
	pha                       ; (draw_sprite_text do wpisu 20, game/sonic.asm sh_drown) nie zmienia licznika po ticku
	jsr sonic_objfunc
	mwa #object_list zg_obj
	jsr obj_motion
	lda sonic_spritemap_ix_15
	ora sonic_spritemap_ix_15+1
	beq st_nodraw
	sec
	lda sonic_x
	sbc g_level_scroll_x_pix_lo
	sta tmp_06
	lda sonic_x+1
	sbc g_level_scroll_x_pix_lo+1
	sta tmp_06+1
st_nodraw
	pla                       ; pop af / ld (iy+g_sprite_count),a
	sta g_sprite_count
	lda v_tr_fl
	ora #F_SONIC              ; flaga rekordu: Sonic uruchomiony (jak trace referencji)
	sta v_tr_fl
	rts

; irq_sprites_rng: czesc IRQ (00:0073) zmieniajaca stan gry poza lata ekranu: upload_sprite_table_IRQ
; (00:033E, gdy iy_00 b1): g_prev_sprite_count = licznik, licznik = 0 (licznik 0 - bez zmian); random_A (00:00D8)
; w kazdym przerwaniu - port: raz na krok (krok = jedno IRQ)
irq_sprites_rng
	lda #0                    ; M4.2: grupy wpisow obiektow (renderer) od nowa w kazdej ramce
	sta v_ngrp
	lda iy_00
	and #$02
	beq isr_rng
	lda g_sprite_count
	beq isr_rng
	sta g_prev_sprite_count
	lda #0
	sta g_sprite_count
isr_rng
	jmp random_A

; ss_ring_tiles: update_ring_tiles, gdy poziom ma pierscienie (iy_05 b2; 00:1D5D, 00:1DBD)
ss_ring_tiles
	lda iy_05_lvflag00
	and #$04
	beq srt_ret
	jmp update_ring_tiles
srt_ret
	rts

inc_tick_counter
	inc g_global_tick_counter
	bne itc_done
	inc g_global_tick_counter+1
itc_done
	rts

step_record_defaults
	lda #0
	sta v_spk                 ; renderer: iskra pierscienia tylko, gdy narysuje ja ten tick
	sta v_isp                 ; M4.5: iskra niesmiertelnosci jw.
	lda #$FF
	sta v_tr_in
	sta v_tr_int
	lda #0
	sta v_tr_fl
	lda iy_05_lvflag00
	and #2
	beq srd_done
	lda #F_DEMO
	sta v_tr_fl
srd_done
	rts
