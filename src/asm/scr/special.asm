; =====================================================================
;  special.asm - M6.5: ekran wyniku etapu specjalnego (handle_level_score_screen dla g_level >= $1C) - kod rezydentny
;  $8000+, wolany z banku 49 (src/scr/ekrany.asm; PORTB = PB_SCR, wiec sa widoczne procedury i dane ekranow). Bank 49 ma
;  tylko haki (jsr / jmp), reszta mieszka tu, bo bank jest zapelniony.
;   bs_rle_w            mapa ekranu wyniku: ARTMAP_05_612E albo (etap specjalny) ARTMAP_05_61E9 (00:1599-00:15A9);
;                       poprawka stalej ladowania (jedno przerwanie mniej, Mesen: m6_ekrany_ref.py --sp)
;   ss_tally_start      00:160C-00:1624: g_special_stages_attempted + 1; przy zebranym etapie (iy_09 b2 = 0): completed + 1
;                       i mnoznik premii za pierscien + 1; punkty za pierscien (scr_pts_d / e): 100 albo mnoznik
;   ss_zero_bonus       00:1660-00:166A: etap specjalny - premia za czas = LUT_zero_time_bonus (0)
;   ss_draw_tally_rest  00:1A4E-00:1AC9: pierscienie ($98, $68), mnoznik ($C0, $68), zycia, kontynuacje ($A8, $80)
; =====================================================================
bs_rle_w
	lda #0
	sta scr_kadj
	lda g_level
	cmp #$1C
	bcs brw_sp
	mwa #scr_rle_w sz_s
	mwa #EKR_RLE_W sz_n
	rts
brw_sp
	lda v_tv                  ; ladowanie ekranu wyniku etapu: PAL o 1 IRQ krocej (16 zamiast 17), NTSC bez zmiany (Mesen)
	sta scr_kadj
	mwa #scr_rle_ws sz_s
	mwa #EKR_RLE_WS sz_n
	rts

ss_tally_start
	lda #1
	sta scr_pts_d
	lda #0
	sta scr_pts_e
	sta scr_kadj              ; poprawka tylko dla ladowania ekranu wyniku (dalsze ekrany: K jak w oryginale)
	lda g_level
	cmp #$1C
	bcc sts_ret
	inc g_special_stages_attempted
	lda iy_09
	and #4
	bne sts_nc                ; koniec czasu: etap nieukonczony
	inc g_special_stages_completed
	inc g_special_stage_ring_bonus_mult_hi
sts_nc
	lda g_special_stage_ring_bonus_mult_hi
	sta scr_pts_d
	lda g_special_stage_ring_bonus_mult_lo
	sta scr_pts_e
sts_ret
	rts

ss_zero_bonus
	lda g_level
	cmp #$1C
	bcc szb_ret
	lda #0
	sta tmp_04
	sta tmp_04+1
	sta tmp_04+2
	sta tmp_04+3
szb_ret
	rts

ss_draw_tally_rest
	mwa #g_rings_BCD sz_s     ; pierscienie w (x $98, y $68)
	lda #1
	jsr scr_bcd_str
	lda #$98
	ldy #$68
	jsr sdt_text
	mwa #g_special_stage_ring_bonus_mult_hi sz_s ; mnoznik (2 B) w ($C0, $68)
	lda #2
	jsr scr_bcd_str
	lda #$C0
	ldy #$68
	jsr sdt_text
	jsr sdt_lives
	mwa #SC_CONT sz_s         ; kontynuacje (1 B) w ($A8, $80) zamiast premii za czas
	lda #1
	jsr scr_bcd_str
	lda #$A8
	ldy #$80
	jmp sdt_text

scr_rle_ws	ins 'ekr_rle_wynik_sp.bin' ; ARTMAP_05_61E9 (ekran wyniku etapu specjalnego)
; M6.8: RLE ekranu wyniku i game over (czyta je kod banku 49 - przeniesione z niego: bank 49 pelny, miejsce na mape 2)
scr_rle_w	ins 'ekr_rle_wynik.bin'  ; ARTMAP_05_612E (M6.2 ekran wyniku)
scr_rle_g	ins 'ekr_rle_go.bin'     ; ARTMAP_05_67FE (M6.3 ekran game over)

; =====================================================================
;  Ekran kontynuacji (M6.5): game over z g_continues > 0 (run_game_over_screen 00:1477-00:14DD) - po 120 ramkach ekranu
;  game over: ikony kontynuacji (draw_repeated_16x16_tile_string z c = $0B, LUT 00:14DE), napis (00:14E6, 00:14F1),
;  odliczanie 9..0 (60 ramek na cyfre, cyfra jako sprite'y w ($8C, $5E), efekt $1A co cyfre); przycisk 1 / 2: punkt
;  kontrolny aktu skasowany, g_continues - 1, 3 zycia, mapa tego samego aktu (stan gry zostaje - boot_cont); po 0 ->
;  reset_game_state (tytul). Wolane z banku 49 (scr_seq_gameover): bc_used_tiles po scr_used_tiles, boot_continue
;  po 120 ramkach. Test: boot_cbtn = numer ramki odliczania z przyciskiem (0 = bez; m6_ekrany_test.py --gameover --cont).
; =====================================================================
bc_used_tiles                   ; kafle ekranu kontynuacji dopisane do scr_used (ladowanie ekranu game over, bank 53)
	lda SC_CONT
	beq bcu_ret
	ldx #5
bcu_l
	ldy bcu_idx,x
	lda scr_used,y
	ora bcu_msk,x
	sta scr_used,y
	dex
	bpl bcu_l
bcu_ret
	rts
bcu_idx	dta b(12, 13, 14, 15, 16, 18)       ; kafle $67-$6E, $77-$7E (napis), $80 $81, $90 $91 (ikony): bajt = kafel >> 3
bcu_msk	dta b($80, $7F, $80, $7F, $03, $03)

boot_continue
	lda SC_CONT
	sta scr_cnt               ; liczba ikon
	lsr
	sta scr_q
	lda #$0B
	sec
	sbc scr_q
	sta g_HUD_FFstr_buf       ; x pierwszej ikony = $0B - n / 2
	sta g_HUD_FFstr_buf+5
	ldx #3
bcn_c
	lda scr_r0+[$14DE-EKR_R0_FROM],x
	sta g_HUD_FFstr_buf+1,x
	lda scr_r0+[$14DE-EKR_R0_FROM]+4,x
	sta g_HUD_FFstr_buf+6,x
	dex
	bpl bcn_c
	lda #0
	sta tmp_00
	jsr sem_l                 ; petla rysowania szmaragdow (bank 49): n ikon 16 x 16 w dwoch wierszach
	mwa #scr_r0+[$14E6-EKR_R0_FROM] sz_m
	jsr scr_print_ff          ; sprtext_game_over_continue_row_0
	mwa #scr_r0+[$14F1-EKR_R0_FROM] sz_m
	jsr scr_print_ff          ; ..._row_1
	lda #9
	sta tmp_08
	lda #0
	sta bc_iter
	sta bc_iter+1
bcn_num
	lda #60
	sta scr_cnt
bcn_w
	jsr scr_wait0             ; wait_until_irq_ticked
	inc bc_iter
	bne bcn_i
	inc bc_iter+1
bcn_i
	lda #0                    ; g_sprite_count = 0, cyfra odliczania od poczatku tablicy sprite'ow
	sta g_sprite_count
	sta g_next_avail_vdp_sprite_ptr
	lda #>SC_SAT_S
	sta g_next_avail_vdp_sprite_ptr+1
	mwa #tmp_08 sz_s
	lda #1
	jsr scr_bcd_str
	lda #$8C
	ldy #$5E
	jsr sdt_text
	lda boot_cbtn             ; test: przycisk w ramce odliczania boot_cbtn
	cmp bc_iter
	bne bcn_in
	lda boot_cbtn+1
	cmp bc_iter+1
	beq bcn_go
bcn_in
	lda g_inputs_player_1
	and #$20                  ; bit 5 = 0: przycisk 1 albo 2
	beq bcn_go
	dec scr_cnt
	bne bcn_w
	lda #$1A
	jsr play_sfx
	lda tmp_08
	beq bcn_end
	dec tmp_08
	jmp bcn_num
bcn_end
	jmp sst_reset             ; odliczanie do 0: koniec gry (carry = 0 -> main@reset_game_state, tytul)
bcn_go                          ; @clear_level_checkpoint_and_continue (00:14CC)
	jsr level_mask
	eor #$FF
	and g_level_has_checkpoint_mask,x
	sta g_level_has_checkpoint_mask,x
	dec SC_CONT
	lda #3                    ; 00:209C: 3 zycia, A = 1 -> main@main_loop (mapa tego samego aktu)
	sta g_lives
	lda #1
	sta boot_cont
	jmp sst_mainloop
