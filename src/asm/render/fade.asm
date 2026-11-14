; =====================================================================
;  fade.asm - M3.7: wygaszanie palet przy wyjsciu z poziomu i przywracanie przy nowym starcie
;
;  Oryginal: palette_fade_to_black (00:0A90) - kazda skladowa koloru SMS (2 bity) -1, nie mniej niz 0;
;  fade_screen_to_black robi 4 kroki (czern). Kolory w VBXE = skladowa SMS * 85 (tools/extract_sms.py),
;  wiec krok n = skladowa - 85 * n (nie mniej niz 0) daje te same poziomy.
;  Paleta 1 nakladki: 0-15 tlo (biezacy wariant cyklu z PAL_RAM), 16-31 sprite'y (SPRPAL_RAM).
; =====================================================================

; pal_fade: A = poziom 0..4 (0 = pelna paleta). Cykl palety (NMI) musi byc wylaczony (v_cyc_on = 0).
pal_fade
	tax
	lda fade_sub,x
	sta v_fade_sub
	ldy #VC_PSEL
	lda #1
	sta (zp_fx),y
	ldy #VC_CSEL
	lda #0
	sta (zp_fx),y
	ldx v_cyc_idx
	lda cyc_off,x             ; wyswietlany wariant cyklu tla
	tax
	lda #16
	sta v_fade_n
pf_bg
	lda PAL_RAM,x
	jsr fade_c
	ldy #VC_CR
	sta (zp_fx),y
	lda PAL_RAM+1,x
	jsr fade_c
	iny
	sta (zp_fx),y
	lda PAL_RAM+2,x
	jsr fade_c
	iny
	sta (zp_fx),y             ; CB: zapis koloru i CSEL + 1
	inx
	inx
	inx
	dec v_fade_n
	bne pf_bg
	ldx #0                    ; CSEL = 16: paleta sprite'ow
pf_spr
	lda SPRPAL_RAM,x
	jsr fade_c
	ldy #VC_CR
	sta (zp_fx),y
	lda SPRPAL_RAM+1,x
	jsr fade_c
	iny
	sta (zp_fx),y
	lda SPRPAL_RAM+2,x
	jsr fade_c
	iny
	sta (zp_fx),y
	inx
	inx
	inx
	cpx #48
	bne pf_spr
	lda v_water               ; M6.8: poziom z woda - paleta 2 (podwodna) tez wygaszana / przywracana
	beq pfw_ret
	jmp water_pal2
pfw_ret
	rts

fade_c                          ; A = max(A - v_fade_sub, 0)
	sec
	sbc v_fade_sub
	bcs fc_ret
	lda #0
fc_ret
	rts

fade_sub	dta b(0, 85, 170, 255, 255)

; render_level_reset: stan renderera dla nowego startu poziomu (restart po smierci, nowa gra): pelne
; przeladowanie pierscienia tla (uklad przywrocony z banku - pierscienie wracaja), grafika pierscienia
; strefy, bez laty i iskry, sprite'y widoczne, paleta pelna, cykl palety od wariantu 0.
render_level_reset
	lda #0
	sta v_ring_ok
	sta v_patch_on
	sta v_hide_spr
	sta v_spk
	sta v_isp
	sta v_tp_on
	ldx #56                   ; M4.7: bez nakladek kafli (pierscien tla - pelne przeladowanie przy starcie)
	lda #$FF
rlr_tov
	sta v_tov+1,x
	dex
	dex
	dex
	dex
	dex
	dex
	dex
	dex
	bpl rlr_tov
	lda #0
	sta v_cyc_idx
	lda #$FF
	sta v_ring_art
	sta v_ring_drawn
	lda #0
	jsr pal_fade
	lda v_cycspd
	sta v_cyc_timer
	lda #1
	sta v_cyc_on
	rts
