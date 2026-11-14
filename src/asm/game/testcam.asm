; =====================================================================
;  testcam.asm - kamera renderera i kulka testowa z M2: tryb gry (CAM_GAME, domyslny od M3.4 - kamera
;  z game/camera.asm) i tryby testowe M2 (auto: przekatna 12 px/tick, joystick 4/12 px, 2 = stop,
;  3 = za Sonikiem) dla scenariuszy tools/m2_test.py. Kulka tylko w trybach 0-2 (od M3.6 Sonic z grafiki SMS).
; =====================================================================
BALL_SIZE    = 32          ; kulka testowa 32x32 (atrapa obiektu)
MAX_SX       = 256-BALL_SIZE
MAX_SY       = 192-BALL_SIZE
CAM_SPEED    = 12          ; px/tick: tryb auto i joystick z fire (= maks. predkosc kamery SMS w tescie M2)
CAM_SLOW     = 4           ; px/tick: joystick bez fire

; =====================================================================
;  Kamera i kulka
; =====================================================================
; update_camera: v_cam_mode 0 = auto (przekatna v_vx/v_vy z odbiciem od granic poziomu), przejscie
; w 1 = joystick przy pierwszym ruchu drazka, 2 = stop (ustawiane z debuggera w testach),
; 3 = za Sonikiem (kamera testowa M3.3), 4 = kamera gry (M3.4); w obu Sonic z grafiki SMS (M3.6).
CAM_FOLLOW   = 3
CAM_GAME     = 4
	.ifdef RELEASE
; M7.5: wydanie (sonic-a8-vbxe.xex, cart, ATR) - v_cam_mode = CAM_GAME zawsze (machine_init; tryby testowe 0-3 ustawia tylko tools/m2_test.py
; w game.xex): update_camera = kamera gry (uc_game nizej), update_ball w CAM_GAME i tak wraca od razu. Zachowanie identyczne, ok. 490 B
; mniej pod oknem (miejsce dla M7.5). Budowa testowa - pelna wersja w kodzie rezydentnym (game_code.asm).
update_camera
	lda g_level_scroll_x_pix_lo
	sta v_camx
	lda g_level_scroll_x_pix_lo+1
	sta v_camx+1
	lda g_level_scroll_y_pix_lo
	sta v_camy
	lda g_level_scroll_y_pix_lo+1
	sta v_camy+1
update_ball
	rts
	.else
update_camera
	lda v_cam_mode
	cmp #CAM_GAME
	jeq uc_game
	cmp #CAM_FOLLOW
	jeq uc_follow
	lda v_cam_mode
	bne uc_mode
	lda v_joy
	and #$0F
	cmp #$0F                  ; drazek w spoczynku -> dalej auto
	beq uc_auto
	lda #1
	sta v_cam_mode
uc_mode
	cmp #1
	jeq uc_manual
	rts                       ; 2 = stop
uc_auto                         ; camx += vx (8 bit ze znakiem rozszerzonym do 16)
	lda v_camx
	clc
	adc v_vx
	sta v_camx
	lda v_vx
	and #$80
	beq uc_ax_pos
	lda #$FF                  ; rozszerzenie znaku; C z dodawania mlodszego bajtu zachowane
uc_ax_pos
	adc v_camx+1
	sta v_camx+1
	jsr clamp_x
	bcc uc_ay
	lda v_vx
	eor #$FF
	clc
	adc #1
	sta v_vx
uc_ay
	lda v_camy
	clc
	adc v_vy
	sta v_camy
	lda v_vy
	and #$80
	beq uc_ay_pos
	lda #$FF
uc_ay_pos
	adc v_camy+1
	sta v_camy+1
	jsr clamp_y
	bcc uc_done
	lda v_vy
	eor #$FF
	clc
	adc #1
	sta v_vy
uc_done
	rts

; tryb 4: kamera gry = g_level_scroll_x/y_pix (adjust_camera, przycieta przez gre do g_level_limit_* -
; w GHZ1 rowne granicom renderera LV_CAM_*; ruch <= 8 px/tick, skok tylko przy blokadzie kamery)
uc_game
	lda g_level_scroll_x_pix_lo
	sta v_camx
	lda g_level_scroll_x_pix_lo+1
	sta v_camx+1
	lda g_level_scroll_y_pix_lo
	sta v_camy
	lda g_level_scroll_y_pix_lo+1
	sta v_camy+1
	rts

; tryb 3: Sonic na srodku widoku (x + 12 = 128, y + 16 = 96), przyciecie do granic poziomu;
; Sonic porusza sie <= 16 px/tick, wiec kamera nie skacze o wiecej niz blok (bez pelnego przeladowania)
uc_follow
	sec
	lda sonic_x
	sbc #116
	sta v_camx
	lda sonic_x+1
	sbc #0
	sta v_camx+1
	sec
	lda sonic_y
	sbc #80
	sta v_camy
	lda sonic_y+1
	sbc #0
	sta v_camy+1
	jsr clamp_x
	jmp clamp_y

uc_manual                       ; joystick: krok CAM_SLOW, z fire CAM_SPEED; potem przyciecie do granic poziomu
	ldx #CAM_SLOW
	lda v_trig
	bne uc_spd
	ldx #CAM_SPEED
uc_spd
	stx zp_t0
	lda v_joy
	and #1
	bne uc_m_down
	sec
	lda v_camy
	sbc zp_t0
	sta v_camy
	lda v_camy+1
	sbc #0
	sta v_camy+1
uc_m_down
	lda v_joy
	and #2
	bne uc_m_left
	clc
	lda v_camy
	adc zp_t0
	sta v_camy
	lda v_camy+1
	adc #0
	sta v_camy+1
uc_m_left
	lda v_joy
	and #4
	bne uc_m_right
	sec
	lda v_camx
	sbc zp_t0
	sta v_camx
	lda v_camx+1
	sbc #0
	sta v_camx+1
uc_m_right
	lda v_joy
	and #8
	bne uc_m_clamp
	clc
	lda v_camx
	adc zp_t0
	sta v_camx
	lda v_camx+1
	adc #0
	sta v_camx+1
uc_m_clamp
	jsr clamp_x
	jmp clamp_y

; clamp_x / clamp_y: przyciecie kamery do granic poziomu z naglowka (LV_CAM_X0..X1, Y0..Y1).
; C=1 gdy przycieto (granica). Wartosci ujemne (bit 15) traktowane jak < min.
clamp_x
	lda v_camx+1
	bmi cx_lo
	cmp #>LV_CAM_X0
	bcc cx_lo
	bne cx_hi_chk
	lda v_camx
	cmp #<LV_CAM_X0
	bcc cx_lo
	beq cx_lo
cx_hi_chk
	lda v_camx+1
	cmp #>LV_CAM_X1
	bcc cx_ok
	bne cx_hi
	lda v_camx
	cmp #<LV_CAM_X1
	bcc cx_ok
cx_hi
	mwa #LV_CAM_X1 v_camx
	sec
	rts
cx_lo
	mwa #LV_CAM_X0 v_camx
	sec
	rts
cx_ok
	clc
	rts

clamp_y
	lda v_camy+1
	bmi cy_lo
	cmp #>LV_CAM_Y0
	bcc cy_lo
	bne cy_hi_chk
	lda v_camy
	cmp #<LV_CAM_Y0
	bcc cy_lo
	beq cy_lo
cy_hi_chk
	lda v_camy+1
	cmp #>LV_CAM_Y1
	bcc cy_ok
	bne cy_hi
	lda v_camy
	cmp #<LV_CAM_Y1
	bcc cy_ok
cy_hi
	mwa #LV_CAM_Y1 v_camy
	sec
	rts
cy_lo
	mwa #LV_CAM_Y0 v_camy
	sec
	rts
cy_ok
	clc
	rts

; update_ball: kulka odbija sie od krawedzi ekranu (0..MAX_SX, 0..MAX_SY) z predkoscia v_svx/v_svy;
; tylko tryby kamery testowej 0-2 (w trybach 3-4 renderer rysuje Sonica z grafiki SMS - render/sprites.asm)
update_ball
	lda v_cam_mode
	cmp #CAM_FOLLOW
	bcc ub_bounce
	rts
ub_bounce
	lda v_sx
	clc
	adc v_svx
	sta v_sx
	beq ub_bx
	cmp #MAX_SX
	bcc ub_y
ub_bx
	lda v_svx
	beq ub_y
	eor #$FF
	clc
	adc #1
	sta v_svx
ub_y
	lda v_sy
	clc
	adc v_svy
	sta v_sy
	beq ub_by
	cmp #MAX_SY
	bcc ub_done
ub_by
	lda v_svy
	beq ub_done
	eor #$FF
	clc
	adc #1
	sta v_svy
ub_done
	rts
	.endif
