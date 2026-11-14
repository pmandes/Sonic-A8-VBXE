; =====================================================================
;  objs_e1.asm - M6.4: GHZ3 - boss $12 (objfunc_12_GHZ_boss 01:700C), wspolne procedury bossow
;  (boss_generic_update_8hp 01:77BE, boss_render_jet_engine_flame 01:79FA, spawn_explosion 01:7A3A,
;  set_locked_camera_target 01:7C8C, move_locked_camera_towards_target 01:7CA6), kapsula zwierzat $25
;  (objfunc_25_animal_capsule 01:732C) i zwierzeta $24 / $23 (objfunc_24_animal_1 01:7594, objfunc_23_animal_0
;  01:7699). Oryginal (s1smsdisasm-gm, tylko material referencyjny). Dane pod adresami SMS w banku 45
;  (OD_SPAN11..15, tools/extract_sms.py), kod w lukach danych (build: src/game.asm).
;  Rejestry Z80: IX = zg_obj; HL/DE/BC robocze: zs_hl / zs_de / zs_c (obiekty nie dziela ich z logika Sonica
;  w jednym wywolaniu); wskaznik na dane (HL) - zg_ptr. Przeniesienie: Z80 C = 1 po sbc (pozyczka) <=> 6502 C = 0.
; =====================================================================
G3B_YVEL    = $7261   ; LUT_GHZ3boss_y_velocities (64 B)
G3B_SEQ1    = $72A1   ; LUT_GHZ3boss_seq_01_fly_high_left
G3B_SEQ2    = $72A4   ; seq_02_fly_high_right
G3B_SEQ3    = $72A7   ; seq_03_lowering_on_left
G3B_SEQ5    = $72AA   ; seq_05_lowering_on_right
G3B_SEQ9    = $72AD   ; seq_09_rise_up_off_screen
G3B_SEQZR   = $72B0   ; seq_wait_then_zip_low_towards_right
G3B_SEQZL   = $72BC   ; seq_wait_then_zip_low_towards_left
G3B_DIR     = $72C8   ; LUT_GHZ3boss_spr_dir_tab
G3B_FACEL   = $72F8   ; SPRTAB_GHZ3boss_facing_left
G3B_FACER   = $730A   ; SPRTAB_GHZ3boss_facing_right
PAL2_BOSS   = $731C   ; PAL2_boss
SPR_BOSSOUT = $7922   ; SPRTAB_boss_generic_fly_out
CAP_PROFILE = $750E   ; animal_capsule_UNK_0750E: profil gornej krawedzi (32 B)
SPR_CAPBLINK = $752E  ; SPRITEMAP_animal_capsule_blink
SPR_CAPNORM = $7540   ; SPRITEMAP_animal_capsule_normal
SPR_CAPPRESS = $7552  ; SPRITEMAP_animal_capsule_pressed
CAP_PATCH   = $7564   ; animal_capsule_UNK_07564 (lata kafli nienaruszonej kapsuly: 2 x 12 B)
CAP_PATCHB  = $757C   ; animal_capsule_UNK_0757C (kapsula uszkodzona)
ANIM1_GHZ   = $7629   ; animal_1_anim_GHZ
ANIM1_LAB   = $762E
ANIM1_OTH   = $7633
SPR_ANIMAL1 = $7638   ; SPRITEMAP_animal_1
SPR_AN0_GND = $7752   ; SPRITEMAP_animal_0_on_ground_GHZ
SPR_AN0_AIR = $7760   ; SPRITEMAP_animal_0_airborne_GHZ
BOSS_MUSIC  = $0B
ART_BOSS_IRQ = 6      ; IRQ w trakcie load_art grafiki bossa w funkcji obiektu (py65: 6 random_A); krok 273 ma 8 IRQ
                      ; (z tickiem), 7. IRQ - po powrocie z funkcji (v_late_irq)
ART_CAPS_IRQ = 6      ; IRQ w trakcie load_art grafiki zwierzat (referencja m64-boss-smierc, krok 887: 7 IRQ w kroku = 6 dodatkowych)
ART_BOSS_IRQ_N = 7    ; NTSC (referencja m64-boss-smierc-ntsc, M6.5): krok 273 ma 9 IRQ (PAL 8), krok 887 - 9 IRQ (PAL 7)
ART_CAPS_IRQ_N = 8
ART_BOSS3_IRQ = 6     ; M6.6: IRQ w trakcie load_art grafiki bossa BRI3 (do potwierdzenia referencja Mesena - m66-bri3-boss)
ART_BOSS3_IRQ_N = 7
ART_ROBO_IRQ = 6      ; M6.9: IRQ w trakcie load_art grafiki Robotnika ART_0C_EF3F (scenka SBZ3 $22, zappery SKY3 $46) - pomiar m69-sbz3-scenka
ART_ROBO_IRQ_N = 7

; ---------------------------------------------------------------------
; set_locked_camera_target (01:7C8C): zs_hl = cel X, zs_de = cel Y kamery; granice x0 = x1 = kamera X, y0 = y1 = kamera Y.
; ---------------------------------------------------------------------
set_locked_camera_target
	lda zs_hl
	sta g_level_camera_lock_towards_x
	lda zs_hl+1
	sta g_level_camera_lock_towards_x+1
	lda zs_de
	sta g_level_camera_lock_towards_y
	lda zs_de+1
	sta g_level_camera_lock_towards_y+1
	lda g_level_scroll_x_pix_lo
	sta g_level_limit_x0
	sta g_level_limit_x1
	lda g_level_scroll_x_pix_lo+1
	sta g_level_limit_x0+1
	sta g_level_limit_x1+1
	lda g_level_scroll_y_pix_lo
	sta g_level_limit_y0
	sta g_level_limit_y1
	lda g_level_scroll_y_pix_lo+1
	sta g_level_limit_y0+1
	sta g_level_limit_y1+1
	rts

; ---------------------------------------------------------------------
; move_locked_camera_towards_target (01:7CA6): kamera w celu (X i Y rowne) -> res 5 iy_00 (kamera przestaje sie
; zmieniac - ekran bez przewijania), inaczej nic.
; ---------------------------------------------------------------------
move_locked_camera_towards_target
	lda g_level_camera_lock_towards_x
	cmp g_level_scroll_x_pix_lo
	bne mlc_ret
	lda g_level_camera_lock_towards_x+1
	cmp g_level_scroll_x_pix_lo+1
	bne mlc_ret
	lda g_level_camera_lock_towards_y
	cmp g_level_scroll_y_pix_lo
	bne mlc_ret
	lda g_level_camera_lock_towards_y+1
	cmp g_level_scroll_y_pix_lo+1
	bne mlc_ret
	lda iy_00
	and #$DF
	sta iy_00
mlc_ret
	rts

; ---------------------------------------------------------------------
; objfunc_12_GHZ_boss (01:700C): bez kolizji z mapa (set 5), rozmiar $20 x $1C. Pierwszy tick ((ix+17) b0 = 0):
; y -= 8, load_art grafiki bossa (boss_load_art), paleta PAL2_boss (signal_load_palettes A = 2), muzyka $0B,
; trafienia = 0, (ix+18) = 0, sekwencja seq_01 (lot w lewo wysoko), cel kamery ($0760, $00E8) i granice okna;
; set 0. Co tick: kamera -> cel; (ix+19) & $3F indeksuje LUT_GHZ3boss_y_velocities (Vy, rozszerzenie znaku w
; (ix+11/12)); stan z sekwencji ((ix+20/21) + (ix+18), 0 = skok do bajtu za nim) wybiera Vx (HL, C) i kolejna
; sekwencje; mapa wg kierunku (LUT_GHZ3boss_spr_dir_tab[stan]: (ix+24) b1), boss_generic_update_8hp (tmp_08 =
; $0012: przesuniecie map), plomien silnika; (ix+19) + 1, co 16 tickow (ix+18) + 1.
; ---------------------------------------------------------------------
objfunc_12_boss
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W
	lda #$20
	sta (zg_obj),y
	iny
	lda #$1C
	sta (zg_obj),y
	jsr move_locked_camera_towards_target
	ldy #17
	lda (zg_obj),y
	and #$01                  ; bit 0,(ix+17)
	jne bs_init_done
	ldy #OB_Y+1               ; y += $FFF8
	sec
	lda (zg_obj),y
	sbc #8
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	sbc #0
	sta (zg_obj),y
	jsr boss_load_art         ; load_art ART_09_AEB1 -> $2000 (kafle sprite'ow $00-$7F)
	lda iy_00                 ; signal_load_palettes (00:0333): A = 2 (sprite'y), HL = PAL2_boss
	ora #$08
	sta iy_00
	lda #$02
	sta g_SIG00b3_palettes_present
	lda #<PAL2_BOSS
	sta g_SIG00b3_palette_addr
	lda #>PAL2_BOSS
	sta g_SIG00b3_palette_addr+1
	lda #BOSS_MUSIC           ; rst $18
	jsr play_music
	lda #0
	sta g_boss_hits_taken
	ldy #18
	sta (zg_obj),y
	ldy #20
	lda #<G3B_SEQ1
	sta (zg_obj),y
	iny
	lda #>G3B_SEQ1
	sta (zg_obj),y
	lda #<$0760               ; set_locked_camera_target: HL = $0760, DE = $00E8
	sta zs_hl
	lda #>$0760
	sta zs_hl+1
	lda #<$00E8
	sta zs_de
	lda #>$00E8
	sta zs_de+1
	jsr set_locked_camera_target
	ldy #17
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
bs_init_done                    ; @already_initialised
	ldy #19
	lda (zg_obj),y
	and #$3F
	tax
	ldy #OB_VY
	lda G3B_YVEL,x
	sta (zg_obj),y            ; (ix+10) = Vy (sub)
	bmi bs_yneg
	lda #0
	beq bs_ystore
bs_yneg
	lda #$FF
bs_ystore
	iny
	sta (zg_obj),y            ; (ix+11), (ix+12) = rozszerzenie znaku
	iny
	sta (zg_obj),y
bs_find                         ; @find_next_state
	ldy #18
	lda (zg_obj),y
	sta zs_t                  ; e = (ix+18)
	ldy #20
	clc
	lda (zg_obj),y
	adc zs_t
	sta zg_ptr
	sta tmp_06                ; (tmp_06) = HL = (ix+20/21) + e
	iny
	lda (zg_obj),y
	adc #0
	sta zg_ptr+1
	sta tmp_06+1
	ldy #0
	lda (zg_ptr),y
	bne bs_found
	iny                       ; bajt zero: nastepny bajt = nowy (ix+18)
	lda (zg_ptr),y
	ldy #18
	sta (zg_obj),y
	jmp bs_find
bs_found                        ; @found_state
	sec
	sbc #1
	asl
	tax
	lda bs_tab,x
	sta zo_vec
	lda bs_tab+1,x
	sta zo_vec+1
	jmp (zo_vec)

bs_tab  ; CODEPTRTAB_GHZ3boss_states (01:724B): stany 1-11 (10 = ENTRY_RESET - nieosiagalny)
	dta a(bs_st1, bs_st2, bs_st3, bs_st4, bs_st5, bs_st6, bs_st7, bs_st8, bs_st9, bs_st7, bs_st7)

bs_st1                          ; @state_01_fly_high_left
	clc                       ; HL = limit_x0 + 6; HL - x
	lda g_level_limit_x0
	adc #6
	sta zg_hl
	lda g_level_limit_x0+1
	adc #0
	sta zg_hl+1
	ldy #OB_X+1
	lda zg_hl
	sec
	sbc (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	lda #$FF                  ; c = $FF, hl = $FF00 (ld nie zmienia flag)
	sta zs_c
	lda #0
	sta zs_hl
	lda #$FF
	sta zs_hl+1
	bcc bs_jcont1             ; jp c,@continue (pozyczka)
	ldy #18
	lda #0
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	and #$02                  ; bit 1,(ix+17)
	bne bs_lowleft
	ldy #20
	lda #<G3B_SEQ2
	sta (zg_obj),y
	iny
	lda #>G3B_SEQ2
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
bs_jcont1
	jmp bs_cont
bs_lowleft                      ; @do_lowering_on_left
	ldy #20
	lda #<G3B_SEQ3
	sta (zg_obj),y
	iny
	lda #>G3B_SEQ3
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	and #$FD
	sta (zg_obj),y
	jmp bs_cont

bs_st2                          ; @state_02_fly_high_right
	clc                       ; HL = limit_x0 + $E0; HL - x
	lda g_level_limit_x0
	adc #$E0
	sta zg_hl
	lda g_level_limit_x0+1
	adc #0
	sta zg_hl+1
	ldy #OB_X+1
	lda zg_hl
	sec
	sbc (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	lda #0                    ; c = 0, hl = $0100
	sta zs_c
	sta zs_hl
	lda #1
	sta zs_hl+1
	bcs bs_jcont2             ; jp nc,@continue
	ldy #18
	lda #0
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	and #$04                  ; bit 2,(ix+17)
	bne bs_lowright
	ldy #20
	lda #<G3B_SEQ1
	sta (zg_obj),y
	iny
	lda #>G3B_SEQ1
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	ora #$04
	sta (zg_obj),y
bs_jcont2
	jmp bs_cont
bs_lowright                     ; @do_lowering_on_right
	ldy #20
	lda #<G3B_SEQ5
	sta (zg_obj),y
	iny
	lda #>G3B_SEQ5
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	and #$FB
	sta (zg_obj),y
	jmp bs_cont

bs_st3                          ; @state_03_lowering_on_left: Vy = $000060; w dol do y = kamera Y + $74
	jsr bs_lower
	bcs bs_jcont3
	ldy #20
	lda #<G3B_SEQZR
	sta (zg_obj),y
	iny
	lda #>G3B_SEQZR
	sta (zg_obj),y
bs_jcont3
	jmp bs_cont

bs_st5                          ; @state_05_lowering_on_right
	jsr bs_lower
	bcs bs_jcont5
	ldy #20
	lda #<G3B_SEQZL
	sta (zg_obj),y
	iny
	lda #>G3B_SEQZL
	sta (zg_obj),y
bs_jcont5
	jmp bs_cont

; bs_lower: (ix+10..12) = $000060, HL = scroll_y + $74 - y, c = 0, hl = 0 (Vx = 0); C = 1 (6502) - jeszcze nie na dole
; (jp nc,@continue); C = 0: (ix+18) = 0, wywolujacy zmienia sekwencje
bs_lower
	ldy #OB_VY
	lda #$60
	sta (zg_obj),y
	lda #0
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	clc
	lda g_level_scroll_y_pix_lo
	adc #$74
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #0
	sta zg_hl+1
	ldy #OB_Y+1
	lda zg_hl                 ; xor a / sbc hl,de: bez pozyczki z wejscia
	sec
	sbc (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	lda #0                    ; c = a = 0, hl = 0 (ld nie zmieniaja flag)
	sta zs_c
	sta zs_hl
	sta zs_hl+1
	bcs bl_ret                ; jp nc,@continue: C = 1 (6502) = bez pozyczki Z80 -> wracamy do wywolujacego z C = 1
	ldy #18
	lda #0
	sta (zg_obj),y
	clc
bl_ret
	rts

bs_st4                          ; @state_04_zip_low_towards_right
	lda #0
	sta zs_c
	sta zs_hl
	lda #4
	sta zs_hl+1
	jmp bs_cont

bs_st6                          ; @state_06_zip_low_towards_left
	lda #$FF
	sta zs_c
	lda #0
	sta zs_hl
	lda #$FC
	sta zs_hl+1
	jmp bs_cont

bs_st7                          ; @state_07_0B_wait_before_zip
	lda #0
	sta zs_c
	sta zs_hl
	sta zs_hl+1
	jmp bs_cont

bs_st8                          ; @state_08_stop_now_and_start_rising
	lda #0
	sta zs_c
	sta zs_hl
	sta zs_hl+1
	ldy #20
	lda #<G3B_SEQ9
	sta (zg_obj),y
	iny
	lda #>G3B_SEQ9
	sta (zg_obj),y
	lda #0
	ldy #18
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	jmp bs_cont

bs_st9                          ; @state_09_rise_up_off_screen: Vy = $FFFF00, w gore do y = kamera Y + $1A
	ldy #OB_VY
	lda #0
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	clc
	lda g_level_scroll_y_pix_lo
	adc #$1A
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #0
	sta zg_hl+1
	ldy #OB_Y+1
	lda zg_hl
	sec
	sbc (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	lda #0                    ; c = a = 0, hl = 0
	sta zs_c
	sta zs_hl
	sta zs_hl+1
	bcc bs_jcont9             ; jp c,@continue
	ldy #OB_X+1               ; HL = x - limit_x0
	lda (zg_obj),y
	sec
	sbc g_level_limit_x0
	iny
	lda (zg_obj),y
	sbc g_level_limit_x0+1
	lda #0                    ; c = a, hl = 0 (flagi z sbc zachowane)
	sta zs_c
	sta zs_hl
	sta zs_hl+1
	bcc bs_next_right         ; jr c,@next_fly_dir_go_right
	ldy #20
	lda #<G3B_SEQ1
	sta (zg_obj),y
	iny
	lda #>G3B_SEQ1
	sta (zg_obj),y
	lda #0
	ldy #18
	sta (zg_obj),y
	jmp bs_cont
bs_next_right                   ; @next_fly_dir_go_right
	ldy #20
	lda #<G3B_SEQ2
	sta (zg_obj),y
	iny
	lda #>G3B_SEQ2
	sta (zg_obj),y
	lda #0
	ldy #18
	sta (zg_obj),y
bs_jcont9
	jmp bs_cont

bs_cont                         ; @continue
	ldy #7
	lda zs_hl
	sta (zg_obj),y
	iny
	lda zs_hl+1
	sta (zg_obj),y
	iny
	lda zs_c
	sta (zg_obj),y
	lda tmp_06                ; HL = (tmp_06): e = bajt stanu
	sta zg_ptr
	lda tmp_06+1
	sta zg_ptr+1
	ldy #0
	lda (zg_ptr),y
	tax
	lda G3B_DIR,x
	sta zs_t                  ; e = kierunek (0 w lewo, 2 w prawo)
	lda #<G3B_FACEL
	sta zs_de
	lda #>G3B_FACEL
	sta zs_de+1
	lda zs_t
	beq bs_left
	lda #<G3B_FACER
	sta zs_de
	lda #>G3B_FACER
	sta zs_de+1
bs_left                         ; @was_facing_left
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$FD
	ora zs_t
	sta (zg_obj),y
	ldy #OB_SPRITE
	lda zs_de
	sta (zg_obj),y
	iny
	lda zs_de+1
	sta (zg_obj),y
	lda #$12                  ; tmp_08 = $0012
	sta tmp_08
	lda #0
	sta tmp_08+1
	jsr boss_generic_update_8hp
	jsr boss_render_jet_engine_flame
	ldy #19                   ; inc (ix+19)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	and #$0F
	jne bs_ret
	ldy #18                   ; co 16 tickow inc (ix+18)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
bs_ret
	rts

; robot_load_art (M6.9): jak boss_load_art, grafika Robotnika ART_0C_EF3F (scenka SBZ3 $22; v_art_req = 4: bank sprite'ow strefy $0000)
robot_load_art
	lda #4
	sta v_art_req
	lda iy_09
	and #$02
	bne brl_go
	lda #1
	sta v_late_irq
brl_go
	jmp art_load_common

; boss3_load_art (M6.6): jak boss_load_art, grafika ART_0C_E508 (boss BRI3, v_art_req = 3: bank 47 OA_BOSS3)
boss3_load_art
	lda #3
	sta v_art_req
	lda iy_09
	and #$02
	bne bl3_go
	lda #1
	sta v_late_irq
bl3_go
	jmp art_load_common

; ---------------------------------------------------------------------
; boss_load_art: load_art (00:0405) grafiki ART_09_AEB1 pod kafle sprite'ow $00-$7F - port: zadanie dla renderera
; (v_art_req = 1: kafle bossa z banku 59 i paleta PAL2_boss po nastepnej liscie), IRQ w trakcie dekompresji
; (irq_extra), stan tmp_* jak oryginal.
; ---------------------------------------------------------------------
boss_load_art
	lda #1
	sta v_art_req
	lda iy_09                 ; iy_09 b1 = 1: load_art bez IRQ (bez ei)
	and #$02
	bne bla_go
	lda #1
	sta v_late_irq            ; 1 IRQ po powrocie z funkcji obiektu (objects_tick)
bla_go
	jmp art_load_common

