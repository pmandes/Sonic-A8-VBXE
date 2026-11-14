; =====================================================================
;  camera.asm - kamera gry (M3.4): przeklad fragmentu draw_HUD_sprites 00:2E96-00:2EDC (cele granic,
;  adjust_camera_for_when_sonic_is_alive 00:2F66, zerowanie celow) i update_active_scroll_pos_and_ptrs
;  (00:063E). Stan w lustrze RAM SMS (game/sms.inc); renderer bierze g_level_scroll_x/y_pix (testcam.asm,
;  tryb CAM_GAME).
;
;  Nazwy i adresy wg dezasemblacji s1smsdisasm-gm (tylko material referencyjny, kod napisany od nowa).
;  Rejestry Z80 (kernel/mem.inc): HL = zs_hl (L, H), BC = zg_bc (C, B), temp zs_t. Kamera liczona przed
;  obiektami (Sonic), wiec rejestry Sonica sa wolne.
;
;  Kamera SMS: g_level_scroll_x/y_pix = lewy gorny rog widoku 256x192 w pikselach poziomu. Sonic ma
;  w widoku "okno" g_camera_sonic_bounds_x0..x1 / y0..y1 (wzgledem kamery); gdy z niego wychodzi, kamera
;  przesuwa sie o roznice, najwyzej 8 px/tick, potem przyciecie do g_level_limit_* (granice poziomu,
;  przesuwane po 1 px w strone blokady g_level_camera_lock_towards_x/y). Granice okna zmierzaja po 1 px
;  na tick do celow (domyslne co tick; obiekty moga podac wlasne - M4).
;  Flagi iy_05_lvflag00: b0 Sonic nie zyje (kamera stoi), b3 autoscroll w prawo, b4 bez przewijania w dol,
;  b5 krok 1 px (VESTIGIAL), b6 kolysanie Y (smoothly_adjust_y_oscillation_offset), b7 zapadka w gore;
;  iy_07_lvflag02 b6 = kamera zatrzymana. GHZ1 uzywa tylko b0 - reszta sprawdzona wymuszeniem stanu
;  (tools/m3_ref.py --zestaw m34). Ruch kamery przez autoscroll/zapadke w petli (00:1E0E-00:1E20) - M6.
;  Test: tools/m3_unit.py --proc CAM_TICK / --proc SCROLL_UPDATE (pary RAM z m3_ref.py --wywolania).
; =====================================================================

; ---------------------------------------------------------------------
; cam_tick: draw_HUD_sprites 00:2E96-00:2EDC (po HUD-zie, przed update_some_objfunc_activation_statuses
; i obiektami). Niszczy A, X, Y, zs_hl, zs_t, zg_bc.
; ---------------------------------------------------------------------
cam_tick
; cele granic kamery: 0 -> wartosc domyslna (store_DE_in_HL_minus_1 00:311A); niezerowy cel ustawil
; obiekt w poprzednim ticku (M4)
	ldx #0
	lda #$60                  ; x0 = $0060
	jsr ct_default
	ldx #2
	lda #$88                  ; x1 = $0088
	jsr ct_default
	ldx #4
	lda #$60                  ; y0 = $0060
	jsr ct_default
	ldx #6
	lda #$70                  ; y1 = $0070
	bit iy_05_lvflag00        ; b6 kolysanie kamery Y -> $0080 (@y_camera_is_not_oscillating)
	bvc ct_y1
	lda #$80
ct_y1
	jsr ct_default
	lda iy_05_lvflag00
	lsr                       ; b0 -> C: Sonic nie zyje - kamera bez zmian (00:2EC9)
	bcs ct_clear
	jsr adjust_camera
ct_clear                        ; 00:2ED0: wszystkie cele = 0 (domyslne odtworzy nastepny tick; M3.8d: bez petli)
	lda #0
	sta g_camera_sonic_bounds_x0_target
	sta g_camera_sonic_bounds_x0_target+1
	sta g_camera_sonic_bounds_x0_target+2
	sta g_camera_sonic_bounds_x0_target+3
	sta g_camera_sonic_bounds_x0_target+4
	sta g_camera_sonic_bounds_x0_target+5
	sta g_camera_sonic_bounds_x0_target+6
	sta g_camera_sonic_bounds_x0_target+7
	ldx #$FF                  ; X jak po petli (dex do -1)
	rts

; ct_default: cel (offset X od g_camera_sonic_bounds_x0_target) = $00nn (nn = A) gdy oba bajty = 0
; (bajt starszy jest wtedy juz 0)
ct_default
	ldy g_camera_sonic_bounds_x0_target,x
	bne ctd_ret
	ldy g_camera_sonic_bounds_x0_target+1,x
	bne ctd_ret
	sta g_camera_sonic_bounds_x0_target,x
ctd_ret
	rts

; ---------------------------------------------------------------------
; adjust_camera: adjust_camera_for_when_sonic_is_alive (00:2F66-00:3119)
; ---------------------------------------------------------------------
adjust_camera
	bit iy_07_lvflag02        ; b6: kamera zatrzymana (ustawia obiekt banku 2, 02:BE1E) -> ret nz
	bvc ac_go
	rts
ac_go
; blokady kamery: granice poziomu po 1 px w strone celu (move_camera_towards_locked_x/y)
	lda g_level_camera_lock_towards_x
	ora g_level_camera_lock_towards_x+1
	beq ac_nolockx
	ldx #0                    ; granice x0/x1
	ldy #0                    ; g_level_camera_lock_towards_x
	jsr cam_lock
ac_nolockx
	lda g_level_camera_lock_towards_y
	ora g_level_camera_lock_towards_y+1
	beq ac_nolocky
	ldx #4                    ; granice y0/y1
	ldy #2                    ; g_level_camera_lock_towards_y
	jsr cam_lock
ac_nolocky
; okno Sonica: kazda granica o 1 w strone celu (00:2F7B-00:2FBB, inc_or_dec_DE_towards_delta_HL 00:315E)
	ldx #0
ac_bounds
	jsr cam_bound_step
	inx
	inx
	cpx #8
	bne ac_bounds

; --- przewijanie X (00:2FBF) ---
; HL = scroll_x + x0 - sonic_x; bez pozyczki: Sonic na lewo od lewej granicy okna -> kamera w lewo o HL
	clc
	lda g_level_scroll_x_pix_lo
	adc g_camera_sonic_bounds_x0
	sta zs_hl
	lda g_level_scroll_x_pix_lo+1
	adc g_camera_sonic_bounds_x0+1
	sta zs_hl+1
	sec                       ; and a / sbc hl,de (przeniesienie z add hl,bc pominiete)
	lda zs_hl
	sbc sonic_x
	sta zs_hl
	lda zs_hl+1
	sbc sonic_x+1
	sta zs_hl+1
	bcc ac_x_right            ; pozyczka (Z80 C=1): jr c @skip_x_scroll_left
	jsr cam_cap8              ; @cap_x_scroll_left_speed_to_8
	lda iy_05_lvflag00
	and #$08                  ; b3 autoscroll: Sonic nie przewija -> @continue_after_main_x_scroll
	bne ac_x_clamp
	lda iy_05_lvflag00
	and #$20                  ; b5: krok 1 px (@set_x_right_speed_cap_to_1_VESTIGIAL)
	beq ac_x_left_go
	jsr cam_hl_1
ac_x_left_go                    ; scroll_x -= HL; pozyczka (wyjscie ponizej 0) -> bez zmiany
	sec
	lda g_level_scroll_x_pix_lo
	sbc zs_hl
	tax
	lda g_level_scroll_x_pix_lo+1
	sbc zs_hl+1
	bcc ac_x_clamp
	stx g_level_scroll_x_pix_lo
	sta g_level_scroll_x_pix_lo+1
	jmp ac_x_clamp

ac_x_right                      ; @skip_x_scroll_left: HL = scroll_x + x1 - sonic_x
	clc
	lda g_level_scroll_x_pix_lo
	adc g_camera_sonic_bounds_x1
	sta zs_hl
	lda g_level_scroll_x_pix_lo+1
	adc g_camera_sonic_bounds_x1+1
	sta zs_hl+1
	sec
	lda zs_hl
	sbc sonic_x
	sta zs_hl
	lda zs_hl+1
	sbc sonic_x+1
	sta zs_hl+1
	bcs ac_x_clamp            ; bez pozyczki (jr nc): Sonic w oknie
	jsr cam_neg_hl            ; HL = sonic_x - (scroll_x + x1) > 0 (cpl / inc hl)
	jsr cam_cap8              ; @cap_x_scroll_right_speed_to_8
	lda iy_05_lvflag00
	and #$08                  ; b3 autoscroll
	bne ac_x_clamp
	lda iy_05_lvflag00
	and #$20                  ; b5: krok 1 px (@set_x_left_speed_cap_to_1_VESTIGIAL)
	beq ac_x_right_go
	jsr cam_hl_1
ac_x_right_go                   ; scroll_x += HL; przeniesienie (> $FFFF) -> bez zmiany
	clc
	lda g_level_scroll_x_pix_lo
	adc zs_hl
	tax
	lda g_level_scroll_x_pix_lo+1
	adc zs_hl+1
	bcs ac_x_clamp
	stx g_level_scroll_x_pix_lo
	sta g_level_scroll_x_pix_lo+1

ac_x_clamp                      ; @continue_after_main_x_scroll: przyciecie do granic poziomu
	lda g_level_scroll_x_pix_lo
	cmp g_level_limit_x0
	lda g_level_scroll_x_pix_lo+1
	sbc g_level_limit_x0+1
	bcs ac_x_chk1             ; scroll_x >= x0 (jr nc @skip_clamp_camera_to_x0)
	lda g_level_limit_x0      ; scroll_x < x0 -> x0, bez sprawdzania x1 (jr @skip_clamp_camera_to_x1)
	sta g_level_scroll_x_pix_lo
	lda g_level_limit_x0+1
	sta g_level_scroll_x_pix_lo+1
	jmp ac_y
ac_x_chk1                       ; @skip_clamp_camera_to_x0: scroll_x >= x1 -> x1
	lda g_level_scroll_x_pix_lo
	cmp g_level_limit_x1
	lda g_level_scroll_x_pix_lo+1
	sbc g_level_limit_x1+1
	bcc ac_y
	lda g_level_limit_x1
	sta g_level_scroll_x_pix_lo
	lda g_level_limit_x1+1
	sta g_level_scroll_x_pix_lo+1

; --- przewijanie Y (00:3055) ---
ac_y
	bit iy_05_lvflag00        ; b6: kolysanie kamery (smoothly_adjust_y_oscillation_offset)
	bvc ac_y_noosc
	jsr cam_oscillate
ac_y_noosc                      ; BC = gorna granica okna: y0, b6 -> $0020 (00:31CF), b7 -> $0070 (00:31D3)
	lda g_camera_sonic_bounds_y0
	sta zg_bc
	lda g_camera_sonic_bounds_y0+1
	sta zg_bc+1
	bit iy_05_lvflag00
	bvc ac_y_b7
	lda #$20                  ; set_y0_bound_for_camera_oscillation
	sta zg_bc
	lda #0
	sta zg_bc+1
ac_y_b7
	bit iy_05_lvflag00
	bpl ac_y_add
	lda #$70                  ; set_y0_bound_for_up_ratchet
	sta zg_bc
	lda #0
	sta zg_bc+1
ac_y_add                        ; HL = scroll_y + BC (+ offset patrzenia gdy b7 = 0)
	clc
	lda g_level_scroll_y_pix_lo
	adc zg_bc
	sta zs_hl
	lda g_level_scroll_y_pix_lo+1
	adc zg_bc+1
	sta zs_hl+1
	bit iy_05_lvflag00
	bmi ac_y_sub
	jsr cam_look_offset       ; set_y0_bound_for_things_other_than_up_ratchet
ac_y_sub                        ; HL -= sonic_y; bez pozyczki: Sonic nad gorna granica -> kamera w gore
	sec
	lda zs_hl
	sbc sonic_y
	sta zs_hl
	lda zs_hl+1
	sbc sonic_y+1
	sta zs_hl+1
	bcc ac_y_down             ; jr c @skip_y_scroll_up
	jsr cam_cap_y             ; @cap_y_scroll_up_speed
	bit iy_05_lvflag00
	bpl ac_y_up_go            ; b7 = 0 (@dont_clamp_y_up_for_ratchet)
	lsr zs_hl+1               ; zapadka: HL / 2 (srl h / rr l), bez iy_08 b1 -> 0
	ror zs_hl
	lda iy_08_lvflag03
	and #$02
	bne ac_y_up_go
	lda #0
	sta zs_hl
	sta zs_hl+1
ac_y_up_go                      ; scroll_y -= HL; pozyczka -> bez zmiany
	sec
	lda g_level_scroll_y_pix_lo
	sbc zs_hl
	tax
	lda g_level_scroll_y_pix_lo+1
	sbc zs_hl+1
	bcc ac_y_clamp
	stx g_level_scroll_y_pix_lo
	sta g_level_scroll_y_pix_lo+1
	jmp ac_y_clamp

ac_y_down                       ; @skip_y_scroll_up: HL = scroll_y + y1 (+ offset) - sonic_y
	clc
	lda g_level_scroll_y_pix_lo
	adc g_camera_sonic_bounds_y1
	sta zs_hl
	lda g_level_scroll_y_pix_lo+1
	adc g_camera_sonic_bounds_y1+1
	sta zs_hl+1
	bit iy_05_lvflag00
	bmi ac_y_dsub
	jsr cam_look_offset
ac_y_dsub
	sec
	lda zs_hl
	sbc sonic_y
	sta zs_hl
	lda zs_hl+1
	sbc sonic_y+1
	sta zs_hl+1
	bcs ac_y_clamp            ; jr nc @skip_y_scroll_down: Sonic w oknie
	jsr cam_neg_hl            ; HL = sonic_y - (scroll_y + y1)
	jsr cam_cap_y             ; @cap_y_scroll_down_speed
	lda iy_05_lvflag00
	and #$10                  ; b4: bez przewijania w dol
	bne ac_y_clamp
	clc                       ; scroll_y += HL; przeniesienie -> bez zmiany
	lda g_level_scroll_y_pix_lo
	adc zs_hl
	tax
	lda g_level_scroll_y_pix_lo+1
	adc zs_hl+1
	bcs ac_y_clamp
	stx g_level_scroll_y_pix_lo
	sta g_level_scroll_y_pix_lo+1

ac_y_clamp                      ; @skip_y_scroll_down: przyciecie do y0, potem zawsze sprawdzenie y1
	lda g_level_scroll_y_pix_lo
	cmp g_level_limit_y0
	lda g_level_scroll_y_pix_lo+1
	sbc g_level_limit_y0+1
	bcs ac_y_chk1
	lda g_level_limit_y0
	sta g_level_scroll_y_pix_lo
	lda g_level_limit_y0+1
	sta g_level_scroll_y_pix_lo+1
ac_y_chk1                       ; @skip_clamp_camera_to_y0: scroll_y >= y1 -> y1
	lda g_level_scroll_y_pix_lo
	cmp g_level_limit_y1
	lda g_level_scroll_y_pix_lo+1
	sbc g_level_limit_y1+1
	bcc ac_ret
	lda g_level_limit_y1
	sta g_level_scroll_y_pix_lo
	lda g_level_limit_y1+1
	sta g_level_scroll_y_pix_lo+1
ac_ret
	rts

; --- pomocnicze adjust_camera ---

; cam_cap8: HL > 8 -> 8 (H != 0 albo L >= 9; @cap_x_scroll_*_speed_to_8)
cam_cap8
	lda zs_hl+1
	bne cc8_cap
	lda zs_hl
	cmp #9
	bcc cc8_ret               ; L < 9 (jr c @dont_cap)
cc8_cap
	lda #8
	sta zs_hl
	lda #0
	sta zs_hl+1
cc8_ret
	rts

; cam_cap_y: C = 9 (b6 przy H = 0: 8, clamp_y_delta_to_8 00:311F); H != 0 albo L >= C -> HL = C - 1
cam_cap_y
	ldx #9
	lda zs_hl+1
	bne ccy_cap               ; jr nz @cap_y_scroll_*_speed (C = 9 -> 8)
	bit iy_05_lvflag00
	bvc ccy_cmp
	ldx #8
ccy_cmp
	stx zs_t
	lda zs_hl
	cmp zs_t
	bcc ccy_ret               ; L < C (jr c @dont_cap)
ccy_cap
	dex                       ; dec c / ld l,c / ld h,0
	stx zs_hl
	lda #0
	sta zs_hl+1
ccy_ret
	rts

; cam_neg_hl: HL = -HL (cpl l / cpl h / inc hl)
cam_neg_hl
	sec
	lda #0
	sbc zs_hl
	sta zs_hl
	lda #0
	sbc zs_hl+1
	sta zs_hl+1
	rts

; cam_hl_1: HL = 1 (iy_05 b5, VESTIGIAL)
cam_hl_1
	lda #1
	sta zs_hl
	lda #0
	sta zs_hl+1
	rts

; cam_look_offset: set_y0_bound_for_things_other_than_up_ratchet (00:31DB): b6 = 0 -> HL += offset
; patrzenia w gore/dol (g_camera_y_look_up_offset_px, ustawia logika Sonica)
cam_look_offset
	bit iy_05_lvflag00
	bvs clo_ret               ; ret nz
	clc
	lda zs_hl
	adc g_camera_y_look_up_offset_px
	sta zs_hl
	lda zs_hl+1
	adc g_camera_y_look_up_offset_px+1
	sta zs_hl+1
clo_ret
	rts

; cam_bound_step: granica okna (offset X od g_camera_sonic_bounds_x0) o 1 w strone celu (+8):
; HL = cel - granica; 0 -> bez zmiany, pozyczka (cel < granica) -> dec de, inaczej inc de
cam_bound_step
	sec
	lda g_camera_sonic_bounds_x0_target,x
	sbc g_camera_sonic_bounds_x0,x
	sta zs_t
	lda g_camera_sonic_bounds_x0_target+1,x
	sbc g_camera_sonic_bounds_x0+1,x
	bcc cbs_dec               ; @choose_dec
	ora zs_t
	beq cbs_ret               ; call nz - rowne
	inc g_camera_sonic_bounds_x0,x
	bne cbs_ret
	inc g_camera_sonic_bounds_x0+1,x
cbs_ret
	rts
cbs_dec
	lda g_camera_sonic_bounds_x0,x
	bne cbs_dec_lo
	dec g_camera_sonic_bounds_x0+1,x
cbs_dec_lo
	dec g_camera_sonic_bounds_x0,x
	rts

; cam_lock: move_camera_towards_locked_x (00:3140) / _y (00:3122). X = offset granic poziomu
; (0 = x0/x1, 4 = y0/y1), Y = offset blokady (0 = x, 2 = y). HL = blokada - granica 0:
; 0 -> ret z; pozyczka -> granica 0 - 1, inaczej + 1; granica 1 = granica 0 (kamera zablokowana)
cam_lock
	sec
	lda g_level_camera_lock_towards_x,y
	sbc g_level_limit_x0,x
	sta zs_t
	lda g_level_camera_lock_towards_x+1,y
	sbc g_level_limit_x0+1,x
	bcc cl_dec                ; @target_is_left_of_lock / @target_is_above_lock
	ora zs_t
	beq cl_ret
	inc g_level_limit_x0,x
	bne cl_store
	inc g_level_limit_x0+1,x
	jmp cl_store
cl_dec
	lda g_level_limit_x0,x
	bne cl_dec_lo
	dec g_level_limit_x0+1,x
cl_dec_lo
	dec g_level_limit_x0,x
cl_store
	lda g_level_limit_x0,x
	sta g_level_limit_x0+2,x
	lda g_level_limit_x0+1,x
	sta g_level_limit_x0+3,x
cl_ret
	rts

; cam_oscillate: smoothly_adjust_y_oscillation_offset (00:3164) - kolysanie kamery Y (iy_05 b6):
; predkosc HL = baseline_current + baseline_target, |H| >= 2 -> +-$0200; dodana (24 bity ze znakiem)
; do scroll_y i do g_y_oscillate; przy |oscylacji| >= 32 px cel predkosci zmienia znak
cam_oscillate
	clc
	lda g_y_oscillate_baseline_current
	adc g_y_oscillate_baseline_target
	sta zs_hl
	lda g_y_oscillate_baseline_current+1
	adc g_y_oscillate_baseline_target+1
	sta zs_hl+1
	bpl co_pos                ; jp p (znak H)
	eor #$FF                  ; neg
	clc
	adc #1
	cmp #2
	bcc co_keep               ; |H| < 2 (jr c): HL bez zmian
	lda #$00                  ; HL = BC = $FE00
	sta zs_hl
	lda #$FE
	sta zs_hl+1
	bne co_keep
co_pos
	cmp #2
	bcc co_keep
	lda #$00                  ; HL = BC = $0200
	sta zs_hl
	lda #$02
	sta zs_hl+1
co_keep
	lda zs_hl
	sta g_y_oscillate_baseline_current
	lda zs_hl+1
	sta g_y_oscillate_baseline_current+1
	ldx #0                    ; E = znak B (rozszerzenie do 24 bitow)
	lda zs_hl+1
	bpl co_e
	ldx #$FF
co_e
	stx zs_t
	clc                       ; (g_level_scroll_y_sub, pix_lo, pix_hi) += (C, B, E)
	lda g_level_scroll_y_sub
	adc zs_hl
	sta g_level_scroll_y_sub
	lda g_level_scroll_y_pix_lo
	adc zs_hl+1
	sta g_level_scroll_y_pix_lo
	lda g_level_scroll_y_pix_lo+1
	adc zs_t
	sta g_level_scroll_y_pix_lo+1
	clc                       ; (g_y_oscillate_sub, pix, pix_hi) += (C, B, E)
	lda g_y_oscillate_sub
	adc zs_hl
	sta g_y_oscillate_sub
	lda g_y_oscillate_pix
	adc zs_hl+1
	sta g_y_oscillate_pix
	lda g_y_oscillate_pix+1
	adc zs_t
	sta g_y_oscillate_pix+1
	lda g_y_oscillate_pix+1   ; HL = g_y_oscillate_pix
	bpl co_chk20
	lda g_y_oscillate_pix     ; ujemne: HL - $FFE0, bez pozyczki -> co_chk20
	cmp #$E0
	lda g_y_oscillate_pix+1
	sbc #$FF
	bcs co_chk20
	lda #$02                  ; ponizej -32: cel = +2
	sta g_y_oscillate_baseline_target
	lda #$00
	sta g_y_oscillate_baseline_target+1
	rts
co_chk20                        ; @abs_y_delta_was_not_less_than_0020: HL - $20, pozyczka -> ret c
	lda g_y_oscillate_pix
	cmp #$20
	lda g_y_oscillate_pix+1
	sbc #0
	bcc co_ret
	lda #$FE                  ; cel = -2 ($FFFE)
	sta g_y_oscillate_baseline_target
	lda #$FF
	sta g_y_oscillate_baseline_target+1
co_ret
	rts

; ---------------------------------------------------------------------
; scroll_update: update_active_scroll_pos_and_ptrs (00:063E) - po obiektach, przed
; load_scroll_tile_list_buffers. Przewijanie VDP (g_vdp_scroll_x/y) o zmiane kamery od ostatniej
; wyswietlonej pozycji, kierunek w iy_00 (b6 w lewo, b7 w gore), numer kafla kamery (scroll / 8,
; mlodsze 8 bitow) i wyswietlona pozycja. Renderer Atari z rejestrow VDP nie korzysta - stan dla
; zgodnosci z oryginalem (kolejne procedury SMS czytaja kafle i kierunek). Niszczy A, X, zs_t.
; ---------------------------------------------------------------------
scroll_update
	sec                       ; L = (scroll_x - displayed_x) lo, pozyczka -> kamera w lewo
	lda g_level_scroll_x_pix_lo
	sbc g_displayed_level_scroll_x_pix_lo
	tax
	lda g_level_scroll_x_pix_lo+1
	sbc g_displayed_level_scroll_x_pix_lo+1
	lda iy_00                 ; (lda/and/ora nie zmieniaja C)
	and #$BF                  ; res 6 (w prawo)
	bcs su_xr
	ora #$40                  ; set 6 (@camera_is_moving_left)
su_xr
	sta iy_00
	txa                       ; C = vdp_scroll_x + L (8 bitow)
	clc
	adc g_vdp_scroll_x
	sta g_vdp_scroll_x
	sec                       ; L = (scroll_y - displayed_y) lo
	lda g_level_scroll_y_pix_lo
	sbc g_displayed_level_scroll_y_pix_lo
	tax
	lda g_level_scroll_y_pix_lo+1
	sbc g_displayed_level_scroll_y_pix_lo+1
	bcc su_up                 ; jr c @camera_is_moving_up
	txa                       ; w dol: A = L + B; >= $E0 (poza tablica nazw 224 linii) -> + $20
	clc
	adc g_vdp_scroll_y
	cmp #$E0
	bcc su_yd                 ; @down_skip_y_scroll_discontinuity
su_ywrap_d
	clc
	adc #$20
su_yd
	sta g_vdp_scroll_y
	lda iy_00
	and #$7F                  ; res 7
	sta iy_00
	jmp su_tiles
su_up                           ; w gore: A = L + B; >= $E0 -> - $20
	txa
	clc
	adc g_vdp_scroll_y
	cmp #$E0
	bcc su_yu                 ; @up_skip_y_scroll_discontinuity
su_ywrap_u
	sbc #$20                  ; C = 1 z cmp
su_yu
	sta g_vdp_scroll_y
	lda iy_00
	ora #$80                  ; set 7
	sta iy_00
su_tiles                        ; kafel = starszy bajt (scroll * 8) = (scroll >> 5) & $FF (3 x sla l / rl h)
	lda g_level_scroll_x_pix_lo
	sta zs_t
	lda g_level_scroll_x_pix_lo+1
	asl zs_t
	rol
	asl zs_t
	rol
	asl zs_t
	rol
	sta g_level_scroll_tile_x
	lda g_level_scroll_y_pix_lo
	sta zs_t
	lda g_level_scroll_y_pix_lo+1
	asl zs_t
	rol
	asl zs_t
	rol
	asl zs_t
	rol
	sta g_level_scroll_tile_y
	lda g_level_scroll_x_pix_lo   ; wyswietlona pozycja = biezaca
	sta g_displayed_level_scroll_x_pix_lo
	lda g_level_scroll_x_pix_lo+1
	sta g_displayed_level_scroll_x_pix_lo+1
	lda g_level_scroll_y_pix_lo
	sta g_displayed_level_scroll_y_pix_lo
	lda g_level_scroll_y_pix_lo+1
	sta g_displayed_level_scroll_y_pix_lo+1
	rts
