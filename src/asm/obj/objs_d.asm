; =====================================================================
;  obj/objs_d.asm - M4.5: monitory $01 pierscienie, $02 buty, $03 zycie, $04 oslona, $05 niesmiertelnosc,
;  $51 punkt kontrolny, $52 kontynuacja, $06 szmaragd (bank 45).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_01_monitor_rings 01:5B09 (z
;  monitor_common_destroy_after_hit 01:5B29 i monitor_common_main 01:5B34), objfunc_02 01:5BD9, objfunc_03 01:5C05,
;  objfunc_04 01:5CD7, objfunc_05 01:5CFF, objfunc_51 01:5D2F, objfunc_52 01:5D80, reposition_monitor_on_init 01:5DA8,
;  handle_sonic_monitor_collision 01:5DEB, objfunc_06_chaos_emerald 01:5EA2, write_partial_monitor_art 00:0C1D.
;  IX = zg_obj; tmp_* w lustrze RAM SMS jak oryginal. Przeniesienie jako wynik: C jak w Z80.
; =====================================================================
SPR_MON_NOISE    = $5BBF   ; SPRITEMAP_monitor_noise: $54 $56 $58 / $AA $AC $AE (ramka z szumem)
SPR_MON_SURR     = $5BCC   ; SPRITEMAP_monitor_unnoisy_surrounds: ramka bez srodka (ikona - draw_sprite $5C/$5E)
SPR_MON_IMAGE    = $5F10   ; SPRITEMAP_monitor_image: $5C $5E (szmaragd)

; ---------------------------------------------------------------------
; mon_head: wspolny poczatek monitorow - rozmiar 20 x 24 ((ix+13/14)), reposition_monitor_on_init, kolizja.
; mon_coll: tmp_06 = $0003, check_collision_with_sonic; trafienie -> handle_sonic_monitor_collision.
; Wynik: C = 1 - bez trafienia albo Sonic odepchniety / stoi na monitorze / uderzyl od dolu (monitor zostaje),
; C = 0 - monitor rozbity (explode_object_IX: typ $0A).
; ---------------------------------------------------------------------
mon_head
	jsr mon_size
mon_coll
	lda #$03                  ; ld hl,$0003 / ld (tmp_06),hl
	sta tmp_06
	lda #$00
	sta tmp_06+1
	jsr check_collision_with_sonic
	bcs mnh_ret               ; jr c: bez trafienia
	jmp handle_sonic_monitor_collision
mnh_ret
	rts
mon_size                        ; (ix+13) = $14, (ix+14) = $18, reposition_monitor_on_init
	ldy #OB_W
	lda #$14
	sta (zg_obj),y
	iny
	lda #$18
	sta (zg_obj),y
	jmp reposition_monitor_on_init

; ---------------------------------------------------------------------
; objfunc_01_monitor_rings (01:5B09): rozbity -> +10 pierscieni (add_A_rings $10 - licznik w BCD), mapa 0.
; ---------------------------------------------------------------------
objfunc_01_monitor_rings
	jsr mon_head
	bcs mn01_art
mn01_hit                        ; @on_hit (01:5B24) - takze monitor zycia z (ix+24) b2 (LAB1)
	lda #$10
	jsr add_A_rings
mon_destroy                     ; monitor_common_destroy_after_hit (01:5B29): mapa 0
	lda #0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	rts
mn01_art                        ; monitor_common_set_art_and_go_to_main: ikona 0 (MONART + $00)
	lda #0

; ---------------------------------------------------------------------
; monitor_common_main (01:5B34): A = ikona k (HL = MONART + k * $80 w oryginale). write_partial_monitor_art;
; mapa = ramka z szumem; w tickach (licznik & 7) < 5 ramka bez srodka i ikona: dwa sprite'y draw_sprite $5C
; w (x + 4, y) i $5E w (x + 12, y), gdzie x = piksele (X + Vx), y = piksele (Y + Vy) albo Y, gdy na ziemi
; ((ix+24) b7) - rysowanie przed ruchem (pulapka 7). Monitor uderzony od dolu ((ix+24) b1): Vy += $40.
; ---------------------------------------------------------------------
mon_main
	jsr write_partial_monitor_art
	ldy #OB_SPRITE
	lda #<SPR_MON_NOISE
	sta (zg_obj),y
	iny
	lda #>SPR_MON_NOISE
	sta (zg_obj),y
	lda g_global_tick_counter
	and #$07
	cmp #$05
	jcs mnm_ret               ; ret nc
	ldy #OB_SPRITE
	lda #<SPR_MON_SURR
	sta (zg_obj),y
	iny
	lda #>SPR_MON_SURR
	sta (zg_obj),y
	ldy #OB_X                 ; ld l,(ix+1) / ld h,(ix+2) / ld a,(ix+3) / add hl,de (Vx) / adc a,(ix+9)
	clc
	lda (zg_obj),y
	ldy #OB_VX
	adc (zg_obj),y            ; subpiksel (tylko przeniesienie)
	ldy #OB_X+1
	lda (zg_obj),y
	ldy #OB_VX+1
	adc (zg_obj),y
	sta tmp_00                ; ld l,h / ld h,a / ld (tmp_00),hl
	ldy #OB_X+2
	lda (zg_obj),y
	ldy #OB_VX+2
	adc (zg_obj),y
	sta tmp_00+1
	ldy #OB_FLAGS
	lda (zg_obj),y
	bmi mnm_ground            ; bit 7,(ix+24): na ziemi - bez Vy
	ldy #OB_Y
	clc
	lda (zg_obj),y
	ldy #OB_VY
	adc (zg_obj),y
	ldy #OB_Y+1
	lda (zg_obj),y
	ldy #OB_VY+1
	adc (zg_obj),y
	sta tmp_02
	ldy #OB_Y+2
	lda (zg_obj),y
	ldy #OB_VY+2
	adc (zg_obj),y
	sta tmp_02+1
	jmp mnm_draw
mnm_ground
	ldy #OB_Y+1
	lda (zg_obj),y
	sta tmp_02
	iny
	lda (zg_obj),y
	sta tmp_02+1
mnm_draw
	lda #$04                  ; tmp_04 = $0004, tmp_06 = 0
	sta tmp_04
	lda #0
	sta tmp_04+1
	sta tmp_06
	sta tmp_06+1
	lda #$5C
	jsr draw_sprite
	lda #$0C                  ; tmp_04 = $000C
	sta tmp_04
	lda #0
	sta tmp_04+1
	lda #$5E
	jsr draw_sprite
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$02
	beq mnm_ret               ; bit 1,(ix+24): uderzony od dolu - grawitacja $40
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc #$40
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
mnm_ret
	rts

; ---------------------------------------------------------------------
; objfunc_02_monitor_speed_shoes (01:5BD9): rozbity -> licznik butow Sonica $F0, efekt $02; ikona 1.
; ---------------------------------------------------------------------
objfunc_02_monitor_shoes
	jsr mon_head
	bcs mn02_art
	lda #$F0
	sta sonic_speed_shoes_ix_21
	lda #$02                  ; rst $28
	jsr play_sfx
	jmp mon_destroy
mn02_art
	lda #1
	jmp mon_main

; ---------------------------------------------------------------------
; objfunc_03_monitor_life (01:5C05): zycie juz zebrane w tym poziomie (g_level_lives_collected_mask) -> typ $FF
; i mapa 0. Rozbity: (ix+24) b2 (monitor pierscieni LAB1) -> jak pierscienie; inaczej zycie + 1, bit maski,
; mapa 0, efekt $09, g_level_lives_collected + 1 (poziomy < $1C). Bez trafienia: dziwactwa poziomow (BRI2
; kolysanie, LAB1 ukryty monitor pierscieni, SCR1 tasma, SKY3 ukryty), ikona 2 (LAB1 ukryty: ikona 0).
; ---------------------------------------------------------------------
objfunc_03_monitor_life
	jsr mon_size
	jsr level_mask            ; calc_level_offset_HL_and_mask_C: X = bajt maski, A = bit
	and g_level_lives_collected_mask,x
	beq mn03_new
	ldy #OB_TYPE              ; @life_not_consumed_yet nie: typ $FF, mapa 0
	lda #$FF
	sta (zg_obj),y
	jmp mon_destroy
mn03_new
	jsr mon_coll
	bcs mn03_kl
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$04
	jne mn01_hit              ; bit 2,(ix+24): monitor pierscieni (LAB1)
	inc g_lives
	jsr level_mask
	ora g_level_lives_collected_mask,x
	sta g_level_lives_collected_mask,x
	lda #0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #$09                  ; rst $28: zycie
	jsr play_sfx
	lda g_level
	cmp #$1C
	bcs mn03_ret              ; ret nc
	inc g_level_lives_collected
mn03_ret
	rts
mn03_kl                         ; @check_level_specific_kludges (01:5C5A)
	lda g_level
	cmp #$04
	beq mn03_bri2
	cmp #$09
	beq mn03_lab1
	cmp #$0C
	beq mn03_scr1
	cmp #$11
	beq mn03_sky3
mn03_main                       ; @continue_into_common_main: ikona 2
	lda #2
	jmp mon_main
mn03_bri2                       ; BRI2: kolysanie - Vy = +$40 / -$40 (gdy (ix+19) >= $3C), (ix+19) 0..$4F -> $28
	ldy #19
	lda (zg_obj),y
	cmp #$3C
	bcc mn03_bdn              ; jr c: w dol
	lda #$C0                  ; DE = $FFC0, C = $FF
	ldx #$FF
	bne mn03_bv
mn03_bdn
	lda #$40                  ; DE = $0040, C = 0
	ldx #$00
mn03_bv
	ldy #OB_VY
	sta (zg_obj),y
	iny
	txa                       ; (ix+11) = D, (ix+12) = C (oba = X)
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #19
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y            ; inc (ix+19)
	cmp #$50
	bcc mn03_main
	lda #$28
	sta (zg_obj),y
	bne mn03_main             ; zawsze
mn03_lab1                       ; LAB1: set 2 (ix+24); przycisk niewlaczony -> ikona 0 (pierscienie), inaczej
	ldy #OB_FLAGS             ; res 2 i ikona zycia
	lda (zg_obj),y
	ora #$04
	sta (zg_obj),y
	jsr level_mask
	and g_level_button_toggled_on_mask,x
	bne mn03_lon
	lda #0                    ; ld hl,$5180 / jp z,monitor_common_main
	jmp mon_main
mn03_lon
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$FB
	sta (zg_obj),y
	jmp mn03_main
mn03_scr1                       ; SCR1: set 1 (ix+24), Vx = $000080 (tasma)
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
	ldy #OB_VX
	lda #$80
	sta (zg_obj),y
	iny
	lda #0
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	jmp mn03_main
mn03_sky3                       ; SKY3: monitor tylko przy g_level_lives_collected >= $11, inaczej typ $FF
	lda g_level_lives_collected
	cmp #$11
	bcs mn03_main
	ldy #OB_TYPE
	lda #$FF
	sta (zg_obj),y
	jmp mn03_main

; ---------------------------------------------------------------------
; objfunc_04_monitor_shield (01:5CD7): rozbity -> oslona (set 5 iy_06); ikona 3.
; ---------------------------------------------------------------------
objfunc_04_monitor_shield
	jsr mon_head
	bcs mn04_art
	lda iy_06_lvflag01
	ora #$20
	sta iy_06_lvflag01
	jmp mon_destroy
mn04_art
	lda #3
	jmp mon_main

; ---------------------------------------------------------------------
; objfunc_05_monitor_invincibility (01:5CFF): rozbity -> set 0 iy_08, g_invincibility_countdown_timer = $F0,
; muzyka $08 (rst $18); ikona 4.
; ---------------------------------------------------------------------
objfunc_05_monitor_invinc
	jsr mon_head
	bcs mn05_art
	lda iy_08_lvflag03
	ora #$01
	sta iy_08_lvflag03
	lda #$F0
	sta g_invincibility_countdown_timer
	lda #$08                  ; rst $18
	jsr play_music
	jmp mon_destroy
mn05_art
	lda #4
	jmp mon_main

; ---------------------------------------------------------------------
; objfunc_51_monitor_checkpoint (01:5D2F): rozbity -> bit poziomu w g_level_has_checkpoint_mask,
; g_per_level_checkpoint_positions[poziom] = (x >> 5, (y >> 5) - 1) - mlodsze bajty (HL << 3, bajt H); ikona 6.
; ---------------------------------------------------------------------
objfunc_51_monitor_checkpoint
	jsr mon_head
	bcs mn51_art
	jsr level_mask
	ora g_level_has_checkpoint_mask,x
	sta g_level_has_checkpoint_mask,x
	lda g_level               ; DE = g_per_level_checkpoint_positions + 2 * g_level
	asl
	tax                       ; poziom < 128
	ldy #OB_X+1
	lda (zg_obj),y
	sta zg_a
	iny
	lda (zg_obj),y
	jsr mn51_h                ; A = bajt H z (HL << 3)
	sta g_per_level_checkpoint_positions,x
	ldy #OB_Y+1
	lda (zg_obj),y
	sta zg_a
	iny
	lda (zg_obj),y
	jsr mn51_h
	sec
	sbc #1                    ; dec a
	sta g_per_level_checkpoint_positions+1,x
	jmp mon_destroy
mn51_h                          ; A = H, zg_a = L -> A = (H << 3 | L >> 5) & $FF
	asl zg_a
	rol
	asl zg_a
	rol
	asl zg_a
	rol
	rts
mn51_art
	lda #6
	jmp mon_main

; ---------------------------------------------------------------------
; objfunc_52_monitor_continue (01:5D80): rozbity -> set 3 iy_09; ikona 7 (nie w GHZ).
; ---------------------------------------------------------------------
objfunc_52_monitor_continue
	jsr mon_head
	bcs mn52_art
	lda iy_09
	ora #$08
	sta iy_09
	jmp mon_destroy
mn52_art
	lda #7
	jmp mon_main

; ---------------------------------------------------------------------
; reposition_monitor_on_init (01:5DA8): raz ((ix+24) b0): w GHZ (g_tile_flags_index = 0) blok pod (x, y)
; = $AB -> x += $16, y += $12, inaczej x += 4 (y bez zmian); set 0 (ix+24). Blok spod adresu ROM (wiersz
; >= $40 - port nie ma ROM-u) traktowany jak inny niz $AB (v_rom_reads + 1).
; ---------------------------------------------------------------------
reposition_monitor_on_init
	ldy #OB_FLAGS
	lda (zg_obj),y
	lsr
	bcs rmo_ret               ; ret nz
	lda g_tile_flags_index
	bne rmo_def
	lda #0                    ; BC = DE = 0: get_obj_level_tile_ptr_in_ram
	sta zg_bc
	sta zg_bc+1
	sta zg_de
	sta zg_de+1
	jsr obj_tile_ptr
	bcs rmo_rom
	ldy #0
	lda (zg_ptr),y
	cmp #$AB
	bne rmo_def
	lda #$16                  ; DE = $0016 (x), BC = $0012 (y)
	ldx #$12
	bne rmo_add
rmo_rom
	inc v_rom_reads
rmo_def
	lda #$04                  ; DE = $0004, BC = 0
	ldx #$00
rmo_add
	ldy #OB_X+1
	clc
	adc (zg_obj),y
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	txa
	ldy #OB_Y+1
	clc
	adc (zg_obj),y
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	ldy #OB_FLAGS             ; set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
rmo_ret
	rts

; ---------------------------------------------------------------------
; handle_sonic_monitor_collision (01:5DEB): tmp_00 = $0804 (przesuniecie wybuchu). Wynik: C = 1 monitor
; zostaje, C = 0 rozbity (explode_object_IX).
;  - Sonic toczy sie (flagi b0) -> rozbity;
;  - x Sonica poza [mon_x - 18, mon_x + 16] (16 bit, porownania z pozyczka jak Z80) -> z boku: Sonic na
;    mon_x - 21 (gdy mon_x + 10 >= sonic_x + 12) albo mon_x + 21, subpiksel x i Vx Sonica = 0;
;  - w skoku (flagi b2): Vy Sonica < 0 -> uderzenie od dolu: Vy monitora = $FFFE80, Vy Sonica = $000400,
;    licznik skoku 0, (ix+24) b1 (grawitacja monitora); Vy >= 0 -> rozbity;
;  - inaczej Sonic stoi na monitorze: sonic_y = mon_y - wysokosc Sonica, licznik skoku 0, Vy = odbicie
;    (g_sonic_bounce_vel_y), flagi b7.
; ---------------------------------------------------------------------
handle_sonic_monitor_collision
	lda #$04                  ; ld hl,$0804 / ld (tmp_00),hl
	sta tmp_00
	lda #$08
	sta tmp_00+1
	lda sonic_flags_ix_24
	and #$01
	bne hmc_explode
	ldy #OB_X+1               ; HL = mon_x + $FFEE; and a / sbc hl,de (sonic_x): bez pozyczki -> z boku
	clc
	lda (zg_obj),y
	adc #$EE
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #$FF
	sta zg_hl+1
	sec
	lda zg_hl
	sbc sonic_x
	lda zg_hl+1
	sbc sonic_x+1
	jcs hmc_side              ; jr nc
	ldy #OB_X+1               ; HL = mon_x + $10; sbc hl,de: pozyczka -> z boku
	clc
	lda (zg_obj),y
	adc #$10
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	sec
	lda zg_hl
	sbc sonic_x
	lda zg_hl+1
	sbc sonic_x+1
	jcc hmc_side              ; jr c
	lda sonic_flags_ix_24
	and #$04
	bne hmc_jump
	ldy #OB_Y+1               ; xor a / sbc hl,bc: sonic_y = mon_y - wysokosc Sonica
	sec
	lda (zg_obj),y
	sbc sonic_height_ix_14
	sta sonic_y
	iny
	lda (zg_obj),y
	sbc #0
	sta sonic_y+1
	lda #0
	sta g_sonic_jump_countdown_timer
	lda g_sonic_bounce_vel_y_sub ; Vy Sonica = odbicie (sub, lo, hi)
	sta sonic_vel_y_sub
	lda g_sonic_bounce_vel_y_sub+1
	sta sonic_vel_y
	lda g_sonic_bounce_vel_y_sub+2
	sta sonic_vel_y_hi
	lda sonic_flags_ix_24     ; set 7: na ziemi
	ora #$80
	sta sonic_flags_ix_24
	sec
	rts
hmc_jump                        ; @sonic_is_jumping
	lda sonic_vel_y_hi
	bmi hmc_bump              ; jp m
hmc_explode                     ; @explode_and_destroy_monitor: and a -> C = 0
	jsr explode_object_IX
	clc
	rts
hmc_bump                        ; @bumped_from_below
	ldy #OB_VY
	lda #$80
	sta (zg_obj),y
	iny
	lda #$FE
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
	lda #$00                  ; ld hl,$0400 / ld (sonic_vel_y_sub),hl / xor a / ld (sonic_vel_y_hi),a
	sta sonic_vel_y_sub
	lda #$04
	sta sonic_vel_y
	lda #0
	sta sonic_vel_y_hi
	sta g_sonic_jump_countdown_timer
	ldy #OB_FLAGS             ; set 1,(ix+24)
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
	sec
	rts
hmc_side                        ; @sonic_hit_from_x_side: DE = sonic_x + 12, HL = mon_x + 10
	clc
	lda sonic_x
	adc #$0C
	sta zg_de
	lda sonic_x+1
	adc #0
	sta zg_de+1
	ldy #OB_X+1
	clc
	lda (zg_obj),y
	adc #$0A
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	sec                       ; and a / sbc hl,de: bez pozyczki -> Sonic z lewej (BC = $FFEB)
	lda zg_hl
	sbc zg_de
	lda zg_hl+1
	sbc zg_de+1
	lda #$EB
	ldx #$FF
	bcs hmc_left
	lda #$15                  ; BC = $0015
	ldx #$00
hmc_left                        ; @sonic_is_on_left: sonic_x = mon_x + BC
	ldy #OB_X+1
	clc
	adc (zg_obj),y
	sta sonic_x
	iny
	txa
	adc (zg_obj),y
	sta sonic_x+1
	lda #0
	sta sonic_x_sub
	sta sonic_vel_x_sub
	sta sonic_vel_x
	sta sonic_vel_x_hi
	sec
	rts

; ---------------------------------------------------------------------
; objfunc_06_chaos_emerald (01:5EA2, GHZ2 - test py65): zebrany w tym poziomie (g_level_has_emerald_mask)
; -> typ $FF. Rozmiar 12 x 17, reposition_monitor_on_init, mapa 0; kolizja (tmp_06 = $0202): bit maski,
; szmaragdy + 1, licznik muzyki $FE, muzyka $14, typ $FF. Inaczej co drugi tick mapa $5C $5E, Vy += $20,
; ikona 5 (write_partial_monitor_art).
; ---------------------------------------------------------------------
objfunc_06_chaos_emerald
	jsr level_mask
	and g_level_has_emerald_mask,x
	bne em_destroy
	ldy #OB_W
	lda #$0C
	sta (zg_obj),y
	iny
	lda #$11
	sta (zg_obj),y
	jsr reposition_monitor_on_init
	lda #0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #$02                  ; ld hl,$0202 / ld (tmp_06),hl
	sta tmp_06
	sta tmp_06+1
	jsr check_collision_with_sonic
	bcs em_wait
	jsr level_mask
	ora g_level_has_emerald_mask,x
	sta g_level_has_emerald_mask,x
	inc g_chaos_emeralds_collected
	lda #$FE
	sta g_chaos_emerald_music_countdown_timer
	lda #$14                  ; rst $18
	jsr play_music
em_destroy                      ; @destroy_already_collected
	ldy #OB_TYPE
	lda #$FF
	sta (zg_obj),y
	rts
em_wait                         ; @dont_collect_yet: rrca / jr c - tick nieparzysty bez mapy
	lda g_global_tick_counter
	lsr
	bcs em_skip
	ldy #OB_SPRITE
	lda #<SPR_MON_IMAGE
	sta (zg_obj),y
	iny
	lda #>SPR_MON_IMAGE
	sta (zg_obj),y
em_skip                         ; Vy += $20
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc #$20
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	lda #5                    ; ld hl,$5400
	jmp write_partial_monitor_art

; ---------------------------------------------------------------------
; write_partial_monitor_art (00:0C1D): A = ikona k (MONART 05:5180 + k * $80). Oryginal wysyla co tick 8 B
; (2 wiersze kafla) ikony pod VRAM $2B80 + (licznik & 15) * 8 - kafle $5C-$5F, cala ikona w 16 tickow; dwa
; monitory naraz mieszaja ikony (wygrywa ostatni zapis). Port: pozycja p = licznik & 15 -> v_monk[p] = k;
; renderer (render/sprites.asm mon_tiles, w frame_done - blitter wolny) kopiuje 16 B 8 bpp (2 wiersze kafla)
; ikony k z banku 47 do kafli $5C-$5F atlasu sprite'ow. Stan RAM SMS bez zmian (rompage_1 przywracany).
; ---------------------------------------------------------------------
write_partial_monitor_art
	pha
	lda g_global_tick_counter
	and #$0F
	tax
	pla
	sta v_monk,x
	lda #1
	sta v_mondirty
	rts

; =====================================================================
;  M4.7: objfunc_50_flower_raiser (01:7AED) - kwiaty: lata kafli tla 2 x 2 (bez sprite'a). Dane w banku 45 pod
;  adresami SMS: UNK_07B5D (5 x 8 B: 2 x 2 kafle - numer, atrybut) i UNK_07B85 (4 stany: dane gornej i dolnej
;  polowy, czas w tickach parzystych, 0).
; =====================================================================
FLW_DATA         = $7B5D   ; UNK_07B5D
FLW_SEQ          = $7B85   ; UNK_07B85

; ---------------------------------------------------------------------
; objfunc_50_flower_raiser (01:7AED): bez kolizji z mapa (set 5); inicjalizacja (ix+17) = $32, (ix+18) = 0.
; Co tick zgloszenie laty (g_screen_tile_replace_x/y/data_ptr - IRQ nastepnego ticku, apply_screen_tilemap_patch
; 00:38B0): x, y obiektu (tick nieparzysty: y + 16, dolna polowa), dane = UNK_07B5D + 8 * UNK_07B85[4 stan +
; polowa]. W tickach parzystych licznik (ix+17) - 1; przy 0 czas nastepnego stanu z UNK_07B85[4 stan + 2],
; stan (ix+18) + 1 mod 4. Jedna lata na tick - wygrywa ostatni zapis (pozniejszy slot, potem Sonic).
; ---------------------------------------------------------------------
objfunc_50_flower
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01
	bne flw_go
	ldy #17
	lda #$32
	sta (zg_obj),y
	iny
	lda #$00
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
flw_go                          ; @already_initialised
	ldy #OB_X+1               ; g_screen_tile_replace_x = x
	lda (zg_obj),y
	sta g_screen_tile_replace_x
	iny
	lda (zg_obj),y
	sta g_screen_tile_replace_x+1
	ldx #0                    ; BC = 0 (polowa)
	ldy #OB_Y+1
	lda (zg_obj),y
	sta zg_hl
	iny
	lda (zg_obj),y
	sta zg_hl+1
	lda g_global_tick_counter ; rrca / jr nc: tick nieparzysty -> y + 16, BC = 1
	lsr
	bcc flw_y
	clc
	lda zg_hl
	adc #$10
	sta zg_hl
	lda zg_hl+1
	adc #0
	sta zg_hl+1
	ldx #1
flw_y
	lda zg_hl
	sta g_screen_tile_replace_y
	lda zg_hl+1
	sta g_screen_tile_replace_y+1
	ldy #18                   ; e = 4 * (ix+18)
	lda (zg_obj),y
	asl
	asl
	sta zg_a
	txa                       ; UNK_07B85 + e + BC
	clc
	adc zg_a
	tax
	lda FLW_SEQ,x
	asl
	asl
	asl                       ; 8 * numer danych
	clc
	adc #<FLW_DATA
	sta g_screen_tile_replace_data_ptr
	lda #>FLW_DATA
	adc #0
	sta g_screen_tile_replace_data_ptr+1
	lda g_global_tick_counter ; ret c (tick nieparzysty)
	lsr
	bcs flw_ret
	ldy #17                   ; dec (ix+17) / ret nz
	lda (zg_obj),y
	sec
	sbc #1
	sta (zg_obj),y
	bne flw_ret
	ldx zg_a                  ; (ix+17) = UNK_07B85[e + 2]
	lda FLW_SEQ+2,x
	sta (zg_obj),y
	iny                       ; inc (ix+18), przy 4 -> 0
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	cmp #$04
	bcc flw_ret
	lda #$00
	sta (zg_obj),y
flw_ret
	rts

; =====================================================================
;  M4.8: objfunc_07_signpost (01:5F17) - tabliczka konca aktu. Dane w banku 45 pod adresami SMS (OD_SPAN2):
;  animacje signpost_anim_* (01:6157-01:61DB), SPRITEMAP_signpost (01:61DC, klatka 18 B), PAL2_signpost (01:626C).
; =====================================================================
SGN_ANIM_SPIN    = $6157   ; signpost_anim_spinning
SGN_ANIM_STATIC  = $6171   ; signpost_anim_unspun_static
SGN_ANIM_LIFE    = $6174   ; signpost_anim_got_life
SGN_ANIM_NOTHING = $618E   ; signpost_anim_got_nothing
SGN_ANIM_SPECIAL = $61A8   ; signpost_anim_got_special_stage
SGN_ANIM_RINGS   = $61C2   ; signpost_anim_got_rings
SPR_SIGNPOST     = $61DC   ; SPRITEMAP_signpost
PAL2_SIGNPOST    = $626C   ; PAL2_signpost (adres SMS - g_SIG00b3_palette_addr)
ART_SIGN_SMS     = $4294   ; ART_09_4294 w slocie 1 po load_art (tmp_04)
SIGN_IRQ         = 7       ; IRQ w trakcie load_art grafiki tabliczki (z referencji - docs/plan-m4.md M4.8)

; ---------------------------------------------------------------------
; objfunc_07_signpost (01:5F17): rozmiar 24 x 48. Pierwszy tick ((ix+17) b0 = 0): res 7 iy_06 (woda), res 3 iy_05,
; load_art grafiki tabliczki pod kafle sprite'ow $00-$7F (sgn_load_art), signal_load_palettes (paleta sprite'ow
; PAL2_signpost), set 0. Co tick: granice poziomu x0 = cam_x, x1 = x - $70, cele okna Sonica y $80 / $88.
; Odbicie: Sonic wyladowal (flagi b7 0 -> 1, poprzedni stan w (ix+19)), tabliczka na ziemi, |sonic_x - x| < $64
; -> Vy = $FFFE00. Grawitacja $1A. Stany (ix+17): b1 obrot, b2 koniec obrotu (czeka na ziemie: muzyka $09,
; efekt $0C, b3, g_signpost_tickdown_counter = $A0, set 1 iy_06 - Sonic biegnie w prawo), b3 wynik. Dotkniecie
; (tmp_06 = $0A0A, tabliczka nie w gore, bez obrotu): predkosc obrotu (ix+20/21) = 2 * min(|Vx Sonica|, $300),
; (ix+18) = 0, b1, res 3 iy_06 (czas stoi), efekt $0B. Wynik (b3) wg pierscieni i poziomu -> g_current_signpost
; (1 nic, 2 zycie, 3 pierscienie, 4 etap specjalny) i animacja. Klatka mapy = SPRITEMAP_signpost + 18 * numer
; z animacji ((ix+18), $FF = skok do bajtu za nim). Obrot: (ix+22/23) += predkosc, (ix+18) += predkosc hi
; + przeniesienie mlodszego (push af / pop af - pulapka 2), mod $18; Vy -= predkosc >> 5 (chyba ze Vy <= -4),
; predkosc - $10; koniec obrotu (y < 8 albo predkosc < $10): Vy = 0, b1 -> b2, (ix+18) = 0.
; ---------------------------------------------------------------------
objfunc_07_signpost
	ldy #OB_W
	lda #$18
	sta (zg_obj),y
	iny
	lda #$30
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	lsr
	bcs sgn_loaded            ; bit 0,(ix+17)
	lda iy_06_lvflag01
	and #$7F
	sta iy_06_lvflag01
	lda iy_05_lvflag00
	and #$F7
	sta iy_05_lvflag00
	jsr sgn_load_art
	lda iy_00                 ; signal_load_palettes (00:0333): A = 2 (sprite'y), HL = PAL2_signpost
	ora #$08
	sta iy_00
	lda #$02
	sta g_SIG00b3_palettes_present
	lda #<PAL2_SIGNPOST
	sta g_SIG00b3_palette_addr
	lda #>PAL2_SIGNPOST
	sta g_SIG00b3_palette_addr+1
	ldy #17
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
sgn_loaded                      ; @art_already_loaded
	lda g_level_scroll_x_pix_lo
	sta g_level_limit_x0
	lda g_level_scroll_x_pix_lo+1
	sta g_level_limit_x0+1
	ldy #OB_X+1               ; g_level_limit_x1 = x + $FF90
	clc
	lda (zg_obj),y
	adc #$90
	sta g_level_limit_x1
	iny
	lda (zg_obj),y
	adc #$FF
	sta g_level_limit_x1+1
	lda #$80
	sta g_camera_sonic_bounds_y0_target
	lda #$88
	sta g_camera_sonic_bounds_y1_target
	lda #0
	sta g_camera_sonic_bounds_y0_target+1
	sta g_camera_sonic_bounds_y1_target+1
	ldy #19                   ; c = (ix+19); (ix+19) = flagi Sonica & $80
	lda (zg_obj),y
	sta zg_a
	lda sonic_flags_ix_24
	and #$80
	sta (zg_obj),y
	beq sgn_nob
	cmp zg_a
	beq sgn_nob
	ldy #OB_FLAGS
	lda (zg_obj),y
	bpl sgn_nob               ; bit 7,(ix+24): tabliczka na ziemi
	ldy #OB_X+1               ; HL = |sonic_x - x| (and a / sbc hl,de; cpl / inc hl)
	sec
	lda sonic_x
	sbc (zg_obj),y
	sta zg_hl
	iny
	lda sonic_x+1
	sbc (zg_obj),y
	sta zg_hl+1
	bpl sgn_dpos
	lda zg_hl
	eor #$FF
	clc
	adc #1
	sta zg_hl
	lda zg_hl+1
	eor #$FF
	adc #0
	sta zg_hl+1
sgn_dpos
	sec                       ; and a / sbc hl,$0064: bez pozyczki -> bez odbicia
	lda zg_hl
	sbc #$64
	lda zg_hl+1
	sbc #0
	bcs sgn_nob
	ldy #OB_VY                ; Vy = $FFFE00
	lda #$00
	sta (zg_obj),y
	iny
	lda #$FE
	sta (zg_obj),y
	iny
	lda #$FF
	sta (zg_obj),y
sgn_nob                         ; @dont_bounce: Vy += $1A
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc #$1A
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	and #$08
	jne sgn_decide            ; bit 3: wynik
	lda (zg_obj),y
	and #$04
	beq sgn_touch             ; bit 2 = 0: @check_sonic_touching
	ldy #OB_FLAGS
	lda (zg_obj),y
	jpl sgn_decide            ; koniec obrotu, w powietrzu
	lda #$09                  ; rst $18: muzyka konca aktu
	jsr play_music
	lda #$0C                  ; rst $28
	jsr play_sfx
	ldy #17                   ; res 2, set 3
	lda (zg_obj),y
	and #$FB
	ora #$08
	sta (zg_obj),y
	lda #$A0
	sta g_signpost_tickdown_counter
	lda iy_06_lvflag01        ; set 1,(iy+6): konczenie poziomu (handle_level_finishing)
	ora #$02
	sta iy_06_lvflag01
	jmp sgn_decide
sgn_touch                       ; @check_sonic_touching
	lda #$0A                  ; tmp_06 = $0A0A
	sta tmp_06
	sta tmp_06+1
	jsr check_collision_with_sonic
	jcs sgn_decide
	ldy #OB_VY+2              ; bit 7,(ix+12): tabliczka w gore
	lda (zg_obj),y
	jmi sgn_decide
	ldy #17
	lda (zg_obj),y
	and #$02
	jne sgn_decide
	lda sonic_vel_x_sub       ; DE = (sonic_vel_x_sub, sonic_vel_x) - bez znaku po |.|
	sta zg_de
	lda sonic_vel_x
	sta zg_de+1
	bpl sgn_vpos
	lda zg_de
	eor #$FF
	clc
	adc #1
	sta zg_de
	lda zg_de+1
	eor #$FF
	adc #0
	sta zg_de+1
sgn_vpos
	sec                       ; $0300 - DE: pozyczka -> DE = $0300
	lda #$00
	sbc zg_de
	lda #$03
	sbc zg_de+1
	bcs sgn_vok
	lda #$00
	sta zg_de
	lda #$03
	sta zg_de+1
sgn_vok
	lda zg_de                 ; ex de,hl / add hl,hl -> (ix+20/21)
	asl
	ldy #20
	sta (zg_obj),y
	lda zg_de+1
	rol
	iny
	sta (zg_obj),y
	lda #0
	ldy #18
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	ora #$02
	sta (zg_obj),y
	lda iy_06_lvflag01        ; res 3,(iy+6): czas gry stoi
	and #$F7
	sta iy_06_lvflag01
	lda #$0B                  ; rst $28
	jsr play_sfx
sgn_decide                      ; @decide
	lda #<SGN_ANIM_SPIN
	ldx #>SGN_ANIM_SPIN
	ldy #17
	pha
	lda (zg_obj),y
	and #$06                  ; bit 1 albo bit 2: obrot
	tay
	pla
	cpy #0
	jne sgn_anim
	lda #<SGN_ANIM_STATIC
	ldx #>SGN_ANIM_STATIC
	ldy #17
	pha
	lda (zg_obj),y
	and #$08
	tay
	pla
	cpy #0
	jeq sgn_anim
	lda g_level               ; wynik
	cmp #$0C
	bcc sgn_mb
	cmp #$1C
	bcc sgn_nb                ; (A = poziom - jak oryginal)
	lda #<SGN_ANIM_NOTHING
	ldx #>SGN_ANIM_NOTHING
	ldy #$01
	jmp sgn_show
sgn_mb                          ; @decide_maybe_bonus
	lda g_rings_BCD
	cmp #$50
	bcc sgn_nb
	lda #<SGN_ANIM_SPECIAL
	ldx #>SGN_ANIM_SPECIAL
	ldy #$04
	jmp sgn_show
sgn_nb                          ; @decide_not_bonus (A = pierscienie albo poziom)
	cmp #$40
	beq sgn_ml
	and #$0F
	bne sgn_ml
	lda #<SGN_ANIM_RINGS
	ldx #>SGN_ANIM_RINGS
	ldy #$03
	jmp sgn_show
sgn_ml                          ; @decide_maybe_life: dziesiatki pierscieni = (poziom & 3) + 1 -> zycie
	lda g_rings_BCD
	lsr
	lsr
	lsr
	lsr
	sta zg_a
	lda g_level
	and #$03
	clc
	adc #$01
	cmp zg_a
	bne sgn_nothing
	lda #<SGN_ANIM_LIFE
	ldx #>SGN_ANIM_LIFE
	ldy #$02
	bne sgn_show              ; zawsze
sgn_nothing
	lda #<SGN_ANIM_NOTHING
	ldx #>SGN_ANIM_NOTHING
	ldy #$01
sgn_show                        ; @show_signpost_in_C
	sty g_current_signpost
sgn_anim                        ; @update_signpost_animation: DE = animacja (A, X)
	sta zg_de
	stx zg_de+1
sgn_al
	ldy #18
	lda (zg_obj),y
	clc
	adc zg_de
	sta zg_hl
	lda zg_de+1
	adc #0
	sta zg_hl+1
	ldy #0
	lda (zg_hl),y
	cmp #$FF
	bne sgn_ach
	iny                       ; (ix+18) = bajt za $FF
	lda (zg_hl),y
	ldy #18
	sta (zg_obj),y
	jmp sgn_al
sgn_ach                         ; @animation_chosen: mapa = SPRITEMAP_signpost + 18 * A (A <= 6)
	asl
	sta zg_a
	asl
	asl
	asl
	clc
	adc zg_a
	clc
	adc #<SPR_SIGNPOST
	ldy #OB_SPRITE
	sta (zg_obj),y
	lda #>SPR_SIGNPOST
	adc #0
	iny
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	and #$02
	bne sgn_spin
	ldy #18                   ; inc (ix+18)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	rts
sgn_spin                        ; @spinning_stopping
	ldy #20                   ; (ix+22) += (ix+20): C1
	lda (zg_obj),y
	ldy #22
	clc
	adc (zg_obj),y
	sta (zg_obj),y
	php                       ; push af (A = (ix+21), F z C1)
	ldy #21
	lda (zg_obj),y
	sta zg_a
	ldy #23                   ; (ix+23) = (ix+21) + (ix+23) + C1
	adc (zg_obj),y
	sta (zg_obj),y
	plp                       ; pop af: C1
	lda zg_a
	ldy #18                   ; A = (ix+21) + (ix+18) + C1
	adc (zg_obj),y
	cmp #$18
	bcc sgn_inw
	lda #0
sgn_inw
	sta (zg_obj),y
	ldy #OB_VY+2              ; and a / jp p
	lda (zg_obj),y
	bpl sgn_ypos
	sec                       ; $FC00 - Vy (16 bit): bez pozyczki -> ret nc
	lda #$00
	ldy #OB_VY
	sbc (zg_obj),y
	lda #$FC
	iny
	sbc (zg_obj),y
	bcs sgn_ret
sgn_ypos                        ; @y_vel_was_positive: Vy -= predkosc >> 5
	ldy #20
	lda (zg_obj),y
	sta zg_bc
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_bc+1
	ldx #5
sgn_sh
	lsr
	ror zg_de
	dex
	bne sgn_sh
	sta zg_de+1
	ldy #OB_VY
	sec
	lda (zg_obj),y
	sbc zg_de
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	sbc zg_de+1
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	sbc #0
	sta (zg_obj),y
	ldy #OB_Y+1               ; y - 8: pozyczka -> @clamp_y_against_top
	sec
	lda (zg_obj),y
	sbc #$08
	iny
	lda (zg_obj),y
	sbc #0
	bcc sgn_clamp
	sec                       ; predkosc - $10 -> (ix+20/21); ret nc
	lda zg_bc
	sbc #$10
	ldy #20
	sta (zg_obj),y
	lda zg_bc+1
	sbc #0
	iny
	sta (zg_obj),y
	bcs sgn_ret
sgn_clamp                       ; @clamp_y_against_top: Vy = 0, b1 -> b2, (ix+18) = 0
	lda #0
	ldy #OB_VY
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #18
	sta (zg_obj),y
	ldy #17
	lda (zg_obj),y
	and #$FD
	ora #$04
	sta (zg_obj),y
sgn_ret
	rts

; ---------------------------------------------------------------------
; sgn_load_art: load_art (00:0405) grafiki tabliczki ART_09_4294 pod kafle sprite'ow $00-$7F (VRAM SMS $2000).
; Port: renderer kopiuje 8 KiB grafiki 8 bpp z banku 47 do atlasu sprite'ow (v_sign_req - render/sprites.asm
; sign_tiles, w frame_done); kafle ikon monitorow $5C-$5F = grafika tabliczki (v_monk = $FE). Stan RAM jak
; oryginal: tmp_00 = $4294 + slowo +4 naglowka grafiki, tmp_02 = slowo +6, tmp_04 = $4294, tmp_06 = $429C
; (SIGN_TMP00/02 z tools/extract_sms.py); rompage przywrocone. Dekompresja trwa kilka ramek z wlaczonymi
; przerwaniami (gdy iy_09 b1 = 0): SIGN_IRQ przerwan w trakcie (iy_00 b0 ustawiony - bez aktualizacji ekranu):
; odczyt kontrolera do g_inputs_player_1 i random_A (irq_extra, game/objcom.asm).
; ---------------------------------------------------------------------
sgn_load_art
	lda #1
	sta v_sign_req
	ldx #15
	lda #$FE
sla_mk
	sta v_monk,x
	dex
	bpl sla_mk
	lda #1
	sta v_mondirty
	lda iy_09
	and #$02
	bne sla_tmp
	ldx #SIGN_IRQ
	beq sla_tmp
sla_irq
	jsr irq_extra             ; zachowuje X
	dex
	bne sla_irq
sla_tmp
	lda #<[ART_SIGN_SMS+SIGN_TMP00]
	sta tmp_00
	lda #>[ART_SIGN_SMS+SIGN_TMP00]
	sta tmp_00+1
	lda #<SIGN_TMP02
	sta tmp_02
	lda #>SIGN_TMP02
	sta tmp_02+1
	lda #<ART_SIGN_SMS
	sta tmp_04
	lda #>ART_SIGN_SMS
	sta tmp_04+1
	lda #<[ART_SIGN_SMS+8]
	sta tmp_06
	lda #>[ART_SIGN_SMS+8]
	sta tmp_06+1
	rts

; ---------------------------------------------------------------------
; objfunc_4B_throw_sonic_into_a_pit_GHZ2 (01:7AA7, GHZ2 - test py65): bez kolizji z mapa, rozmiar 64 x 64,
; tmp_06 = 0. Sonic dotyka, nie jest ogluszony (iy_06 b6) i stoi na ziemi (flagi b7): Vy = $FFFB00, Vx = $000300,
; flagi res 1 (w prawo), set 6 iy_06 (ogluszenie - bez sterowania), wejscie $FF, efekt $11.
; ---------------------------------------------------------------------
objfunc_4B_pit
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W
	lda #$40
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #0                    ; tmp_06 = $0000
	sta tmp_06
	sta tmp_06+1
	jsr check_collision_with_sonic
	bcs pit_ret               ; ret c
	bit iy_06_lvflag01        ; bit 6: ret nz
	bvs pit_ret
	lda sonic_flags_ix_24
	bpl pit_ret               ; and $80 / ret z
	lda #0                    ; Vy = $FFFB00
	sta sonic_vel_y_sub
	lda #$FB
	sta sonic_vel_y
	lda #$FF
	sta sonic_vel_y_hi
	lda #0                    ; Vx = $000300
	sta sonic_vel_x_sub
	lda #$03
	sta sonic_vel_x
	lda #$00
	sta sonic_vel_x_hi
	lda sonic_flags_ix_24     ; res 1: w prawo
	and #$FD
	sta sonic_flags_ix_24
	lda iy_06_lvflag01
	ora #$40
	sta iy_06_lvflag01
	lda #$FF
	sta g_inputs_player_1
	lda #$11                  ; rst $28
	jmp play_sfx
pit_ret
	rts
