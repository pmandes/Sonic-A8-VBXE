; =====================================================================
;  obj/objz2.asm - M6.9: drugi bank obiektow strefy PB_OBJZ2 (bank 2, okno $4000-$7FFF) - kod obiektow z banku 2 ROM-u dla Scrap Brain,
;  Sky Base, poziomu koncowego $12 i etapow specjalnych $1F-$23 (docs/plan-m6.md 14.6, 15.3). Uklad jak PB_OBJZ (obj/objz.asm): dane
;  banku 2 ROM-u pod adresem SMS - OZ_OFF (OZ2_SPAN* w objdata.inc, tools/extract_sms.py: OBJZ2_SPANS), kod w lukach OZ2_GAP*.
;  Wejscie: objz_call (game/objcom.asm) wlacza bank v_pbobjz (lv_select: ldr_need) i czyta funkcje z oz_tab - dlatego oz2_tab lezy pod
;  tym samym adresem co oz_tab w banku 11 (asercja w game.asm). Wola tylko kod tego banku, kod rezydentny $8000+ i stuby zc_*
;  (bank 45 na czas wywolania, potem znowu v_pbobjz).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl.
; =====================================================================

; ---------------------------------------------------------------------
; oz2_tab: funkcje obiektow banku 2 wg typu $00-$55 (LUT_object_functions 00:2AF6); oz2_stub - typ bez przekladu (obiekty SBZ - kroki 3-7)
; ---------------------------------------------------------------------
oz2_tab
	dta a(oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub)   ; $00
	dta a(oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub)   ; $08
	dta a(oz2_stub, oz2_stub, oz2_stub, objfunc_13_corridor, objfunc_14_flamer_right, objfunc_15_flamer_left, objfunc_16_ceiling_flamer, objfunc_17_door_left)   ; $10 (M6.9 SBZ: $14-$17)
	dta a(objfunc_18_door_right, objfunc_19_door_both, objfunc_1A_zapper, objfunc_1B_ballhog, objfunc_1C_ballhog_bomb, objfunc_1D_floor_button2, objfunc_1E_door_button, objfunc_1F_caterkiller)   ; $18 (SBZ: $18-$1F)
	dta a(oz2_stub, oz2_stub, objfunc_22_sbz3_scene, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub)   ; $20 (M6.9: $22 scenka SBZ3)
	dta a(oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub)   ; $28
	dta a(oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub)   ; $30
	dta a(oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub)   ; $38
	dta a(oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub)   ; $40
	dta a(oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub)   ; $48
	dta a(oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub, oz2_stub)   ; $50

; oz2_stub: typ bez przekladu - jak oz_stub w banku 11 (licznik v_obj_todo, typ w v_obj_todo_id; stan obiektu bez zmian)
oz2_stub
	ldy #OB_TYPE
	lda (zg_obj),y
	sta v_obj_todo_id
	inc v_obj_todo
	rts

; ---------------------------------------------------------------------
; oz2_dfa (kopia oz_dfa banku 11 = do_framed_animation 01:7C41 - sekwencje i mapy obiektow tego banku leza tutaj): zg_bc = sekwencja
; (adres okna), zg_de = baza map (adres SMS). Pary (klatka, czas; $FF - od poczatku) wg indeksu (ix+23) i licznika (ix+22):
; mapa (ix+15/16) = baza + klatka * 18; (ix+22) + 1; gdy czas < (ix+22): (ix+22) = 0, (ix+23) + 2. zg_bc i zg_de bez zmian.
; ---------------------------------------------------------------------
oz2_dfa
	ldy #23
	lda (zg_obj),y
	tay
od2_find
	lda (zg_bc),y
	cmp #$FF
	bne od2_found
	lda #0                    ; koniec sekwencji: (ix+23) = 0, od poczatku
	ldy #23
	sta (zg_obj),y
	tay
	beq od2_find
od2_found
	sty zg_a                  ; indeks pary (czas pod indeksem + 1)
	ldx #0                    ; mapa = baza + klatka * 18 (16 bit): klatka * 2 + klatka * 16
	stx zg_prof+1
	asl
	rol zg_prof+1
	sta zg_hl                 ; klatka * 2
	ldx zg_prof+1
	stx zg_hl+1
	asl
	rol zg_prof+1
	asl
	rol zg_prof+1
	asl
	rol zg_prof+1             ; klatka * 16
	clc
	adc zg_hl
	sta zg_prof
	lda zg_prof+1
	adc zg_hl+1
	sta zg_prof+1
	clc
	lda zg_prof
	adc zg_de
	ldy #OB_SPRITE
	sta (zg_obj),y
	lda zg_prof+1
	adc zg_de+1
	iny
	sta (zg_obj),y
	ldy #22                   ; inc (ix+22)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	sta zg_off
	ldy zg_a                  ; czas
	iny
	lda (zg_bc),y
	cmp zg_off
	bcs od2_ret               ; ret nc: czas >= (ix+22)
	lda #0
	ldy #22
	sta (zg_obj),y
	iny
	lda (zg_obj),y            ; (ix+23) + 2
	clc
	adc #2
	sta (zg_obj),y
od2_ret
	rts
