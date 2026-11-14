; =====================================================================
;  obj/objz3.asm - M6.10: trzeci bank obiektow strefy PB_OBJZ3 (bank 30, okno $4000-$7FFF) - kod obiektow z banku 2 ROM-u dla Sky Base
;  (potem poziom koncowy $12 i etapy $1F-$23 - M6.11; docs/plan-m6.md 15.3, 15.10). W PB_OBJZ2 kod SKY (ok. 5,4 KB) rozpadlby sie na
;  kilkanascie luk miedzy danymi SBZ i SKY; tu leza tylko dane SKY (OZ3_SPAN* w objdata.inc, tools/extract_sms.py: OBJZ3_SPANS) i kod
;  w jednej luce. Uklad jak PB_OBJZ2 (obj/objz2.asm): dane banku 2 ROM-u pod adresem SMS - OZ_OFF, oz3_tab pod adresem oz_tab (asercja
;  w game.asm), bo objz_call (game/objcom.asm) czyta oz_tab po wlaczeniu banku v_pbobjz (lv_select: ldr_need). Wola tylko kod tego banku,
;  kod rezydentny $8000+ i stuby zc_* (bank 45 na czas wywolania, potem znowu v_pbobjz).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl.
; =====================================================================

; ---------------------------------------------------------------------
; oz3_tab: funkcje obiektow banku 30 wg typu $00-$55 (LUT_object_functions 00:2AF6); oz3_stub - typ bez przekladu. Obiekty SKY1-3
; (docs/plan-m6.md 15.3): $13 korytarz (kopia), $30-$3B, $46, $47, $4A; kopie $35/$36 Orbinaut i $3B platforma z banku 11
; ---------------------------------------------------------------------
oz3_tab
	dta a(oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub)   ; $00
	dta a(oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub)   ; $08
	dta a(oz3_stub, oz3_stub, oz3_stub, objfunc_13_corridor3, oz3_stub, oz3_stub, oz3_stub, oz3_stub)   ; $10 ($13 korytarz SKY2 -> $1A)
	dta a(oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub)   ; $18
	dta a(oz3_stub, objfunc_21_ss_bouncer, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub)   ; $20 (M6.11: $21 odbijacz etapow)
	dta a(oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub)   ; $28
	dta a(objfunc_30_cloud, objfunc_31_sky2_propeller, objfunc_32_bomb, objfunc_33_sky2_cannon, objfunc_34_cannon_shell, objfunc_35_orbinaut2, objfunc_36_orbinaut_ball2, objfunc_37_turning_gun)   ; $30
	dta a(objfunc_38_sky_platform_right, objfunc_39_spike_wall, objfunc_3A_sky_fixed_gun, objfunc_3B_platform_osc2, oz3_stub, oz3_stub, oz3_stub, oz3_stub)   ; $38
	dta a(oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, oz3_stub, objfunc_46_sky3_zappers, objfunc_47_sky3_eball)   ; $40 ($46, $47 arena SKY3)
	dta a(oz3_stub, oz3_stub, objfunc_4A_sky3_boss, oz3_stub, objfunc_4C_flipper, oz3_stub, oz3_stub, oz3_stub)   ; $48 ($4A boss SKY3; M6.11: $4C flipper)
	dta a(oz3_stub, oz3_stub, oz3_stub, objfunc_53_end_ctrl, objfunc_54_end_emerald, oz3_stub)   ; $50 (M6.11: $53, $54 poziom koncowy $12)

; oz3_stub: typ bez przekladu - jak oz_stub w banku 11 (licznik v_obj_todo, typ w v_obj_todo_id; stan obiektu bez zmian)
oz3_stub
	ldy #OB_TYPE
	lda (zg_obj),y
	sta v_obj_todo_id
	inc v_obj_todo
	rts

; ---------------------------------------------------------------------
; oz3_dfa (kopia oz_dfa banku 11 i oz2_dfa banku 2 = do_framed_animation 01:7C41 - sekwencje i mapy obiektow tego banku leza tutaj): zg_bc = sekwencja
; (adres okna), zg_de = baza map (adres SMS). Pary (klatka, czas; $FF - od poczatku) wg indeksu (ix+23) i licznika (ix+22):
; mapa (ix+15/16) = baza + klatka * 18; (ix+22) + 1; gdy czas < (ix+22): (ix+22) = 0, (ix+23) + 2. zg_bc i zg_de bez zmian.
; ---------------------------------------------------------------------
oz3_dfa
	ldy #23
	lda (zg_obj),y
	tay
od3_find
	lda (zg_bc),y
	cmp #$FF
	bne od3_found
	lda #0                    ; koniec sekwencji: (ix+23) = 0, od poczatku
	ldy #23
	sta (zg_obj),y
	tay
	beq od3_find
od3_found
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
	bcs od3_ret               ; ret nc: czas >= (ix+22)
	lda #0
	ldy #22
	sta (zg_obj),y
	iny
	lda (zg_obj),y            ; (ix+23) + 2
	clc
	adc #2
	sta (zg_obj),y
od3_ret
	rts
