; =====================================================================
;  water.asm - M6.8: woda Labyrinth na VBXE - paleta 2 nakladki (podwodna) i podzial obrazu w XDL.
;
;  Oryginal: irq_start (00:007A-00:00A9) przy fladze iy_06 b7 i g_water_level_onscreen_y ($D2DB) w 1..$FE ustawia przerwanie linii
;  VDP; line_irq (00:01F2-00:0245) laduje palete PAL2_lv_lab_under_water (00:024B; LAB3 z iy_07 b4: _3 00:026B) w trakcie linii
;  $D2DB + 14 (Mesen 2: wiersz mieszany $D2DB + 14, 32 kolory w ok. 4 liniach - docs/plan-m6.md 13.12); nad linia paleta strefy
;  z cyklem i PAL2_lv_lab_above_water (00:01D6). $D2DB = $FF: caly ekran pod woda (paleta podwodna w VBlank, 00:01C4); $D2DB = 0
;  albo iy_06 b7 = 0: bez wody.
;  Port: paleta 2 nakladki = 32 kolory podwodne (load_palette: z banku poziomu LB_WATERPAL do WATERPAL_RAM i VBXE), XDL (render/
;  tables.asm): drugi wpis obrazu z paleta 2 od linii k = $D2DB + WATER_OFS. k liczy water_split przy budowie listy (stan ticku
;  listy), xdl_water patchuje XDL bufora narysowanej listy przed flipem (game_code.asm, przed frame_done).
; =====================================================================
WATER_OFS    = 15          ; pierwsza linia z paleta podwodna = $D2DB + 15 (srodek pasa przejscia 14..18 w Mesenie)

; ---------------------------------------------------------------------
; water_split: przy budowie listy v_lbuild - linia podzialu k do v_wk[v_lbuild]: 192 = bez wody (poziom bez wody, iy_06 b7 = 0
; - tabliczka, koniec aktu - albo $D2DB = 0), 0 = caly ekran pod woda ($D2DB = $FF), inaczej min($D2DB + WATER_OFS, 192).
; ---------------------------------------------------------------------
water_split
	lda #192
	ldx v_water
	beq ws_set
	bit iy_06_lvflag01
	bpl ws_set
	ldx g_water_level_onscreen_y
	beq ws_set
	lda #0
	cpx #$FF
	beq ws_set
	txa
	clc
	adc #WATER_OFS
	bcs ws_192
	cmp #192
	bcc ws_set
ws_192
	lda #192
ws_set
	ldx v_lbuild
	sta v_wk,x
	rts

; ---------------------------------------------------------------------
; xdl_water: XDL bufora v_back (lista v_lrun narysowana, flip w nastepnym VBI) wg v_wk[v_lrun] - tylko przy zmianie wzgledem
; ostatniego zapisu do XDL tego bufora (v_wx). Pierwszy wpis obrazu n1 = min(max(k, 1), 191) linii (paleta 2 tylko przy k = 0),
; drugi 192 - n1 linii od adresu bufor + n1 * 256 (paleta 2 przy k < 192). Okno MEMAC MB_LOW (XDL0 $00000, XDL1 $00020).
; ---------------------------------------------------------------------
xdl_water
	ldx v_lrun
	lda v_wk,x
	ldy v_back
	cmp v_wx,y
	beq xw_ret
	sta v_wx,y
	sta zp_t0                 ; k
	lda #MB_LOW
	jsr set_memac             ; (niszczy Y)
	ldy v_back
	ldx xw_off,y              ; X = przesuniecie XDL bufora (0 / $20)
	lda zp_t0                 ; n1 = min(max(k, 1), 191)
	bne xw_n1a
	lda #1
xw_n1a
	cmp #192
	bcc xw_n1b
	lda #191
xw_n1b
	sta zp_t1
	sec
	sbc #1
	sta MEMAC_CPU+XDL_N1,x
	lda #191                  ; n2 - 1 = 192 - n1 - 1
	sec
	sbc zp_t1
	sta MEMAC_CPU+XDL_N2,x
	clc                       ; adres drugiego wpisu: bufor + n1 * 256
	lda xw_mid,y
	adc zp_t1
	sta MEMAC_CPU+XDL_A2M,x
	lda xw_hi,y
	adc #0
	sta MEMAC_CPU+XDL_A2H,x
	lda #$10                  ; misc pierwszego wpisu: paleta 1, przy k = 0 paleta 2
	ldy zp_t0
	bne xw_m1
	lda #$20
xw_m1
	sta MEMAC_CPU+XDL_M1,x
	lda #$20                  ; misc drugiego wpisu: paleta 2, przy k = 192 paleta 1
	cpy #192
	bcc xw_m2
	lda #$10
xw_m2
	sta MEMAC_CPU+XDL_M2,x
xw_ret
	rts
xw_off	dta b(<XDL0_VRAM, <XDL1_VRAM)
xw_mid	dta b(>[FB0_VRAM&$FFFF], >[FB1_VRAM&$FFFF])
xw_hi	dta b(FB0_VRAM>>16, FB1_VRAM>>16)

; ---------------------------------------------------------------------
; water_pal: przy starcie poziomu (load_palette, bank poziomu wlaczony): v_water = flaga wody naglowka (iy_06 b7, LB_HDR + $21);
; poziom z woda - 32 kolory podwodne LB_WATERPAL -> WATERPAL_RAM i paleta 2 nakladki VBXE (kolory 0-31). v_wx = $FF (XDL obu
; buforow do zapisania w pierwszej klatce). Wraca z PB_MAIN.
; ---------------------------------------------------------------------
water_pal
	lda #$FF
	sta v_wx
	sta v_wx+1
	lda BANK_WIN+LB_HDR+$21
	and #$80
	sta v_water
	beq wp_main
	ldx #95
wp_cp
	lda BANK_WIN+LB_WATERPAL,x
	sta WATERPAL_RAM,x
	dex
	bpl wp_cp
	lda #PB_MAIN
	sta PORTB
	lda #0                    ; pelna paleta (bez wygaszania)
	sta v_fade_sub
; water_pal2: paleta 2 nakladki = WATERPAL_RAM z odjeciem v_fade_sub (pal_fade, render/fade.asm)
water_pal2
	ldy #VC_PSEL
	lda #2
	sta (zp_fx),y
	ldy #VC_CSEL
	lda #0
	sta (zp_fx),y
	ldx #0
wp2_l
	lda WATERPAL_RAM,x
	jsr fade_c
	ldy #VC_CR
	sta (zp_fx),y
	lda WATERPAL_RAM+1,x
	jsr fade_c
	iny
	sta (zp_fx),y
	lda WATERPAL_RAM+2,x
	jsr fade_c
	iny
	sta (zp_fx),y             ; CB: zapis koloru i CSEL + 1
	inx
	inx
	inx
	cpx #96
	bne wp2_l
	rts
wp_main
	lda #PB_MAIN
	sta PORTB
	rts
