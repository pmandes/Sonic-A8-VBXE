; =====================================================================
;  obj/dispatch.asm - M4.1: aktywacja obiektow, dyspozytor slotow 1..31, powrot z funkcji obiektu (ruch,
;  kolizje z mapa, rysowanie do tablicy sprite'ow SMS). Kod w banku 45 (PB_OBJ, okno $4000-$7FFF) w lukach
;  miedzy danymi obiektow z banku 1 ROM-u, ktore leza tam pod adresami SMS (objdata.inc, docs/plan-m4.md).
;  Wola tylko kod banku 45 i rezydentny ($8000+): obj_motion, obj_dirty (kontrola: tools/sprawdz_xex.py).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): update_some_objfunc_activation_statuses 00:31E6,
;  run_all_objfuncs 00:329B, try_run_objfunc_DE 00:32C8, return_from_objfunc 00:32E2-00:350E,
;  draw_sprite_string 00:350F, draw_sprite 00:3581.
;  Rejestry Z80: IX = zg_obj (rekord w lustrze RAM SMS), reszta na stronie zerowej (kernel/mem.inc).
; =====================================================================
SPRTAB       = $D000+SMS_RAM ; g_sprite_table: 64 x (x, y, kafel); wskaznik g_next_avail_vdp_sprite_ptr = $D0xx

; ---------------------------------------------------------------------
; obj_activate: update_some_objfunc_activation_statuses (00:31E6). Grupa g = licznik tickow & 7 sprawdza
; sloty 4g..4g+3 (takze slot 0 - Sonic). Typ >= $56 (w tym $FF) -> wskaznik 0, tmp bez zmian. Inaczej
; granice typu (8 B od OD_BOUNDS: slowa L, R, T, B): oryginal kopiuje tmp_00..05 = R, T, B (ldi x 6), a ldi
; zmniejsza BC (= L) o 6, wiec lewa granica to L - 6. Aktywny, gdy max(cam_x - (L - 6), 0) < x <= cam_x + R
; i max(cam_y - T, 0) < y <= cam_y + B (x, y = piksele (ix+2,3), (ix+5,6); 16 bit bez znaku, sumy
; obciete do 16 bit). Wskaznik aktywnego = adres SMS rekordu, nieaktywnego = 0.
; M4.9a: adres granic z tablic oa_blo/oa_bhi; porownania czytaja R, T, B wprost z granic, a tmp_00..05
; dostaje na koncu granice ostatniego slotu grupy z typem < $56 - ten sam stan koncowy co ldi przy kazdym
; takim slocie (tmp_00..05 porownuje test trace'u).
; ---------------------------------------------------------------------
obj_activate
	lda g_global_tick_counter
	and #7
	tax
	lda oa_ix_lo,x
	sta zg_obj
	lda oa_ix_hi,x
	sta zg_obj+1
	txa
	asl
	asl
	asl
	sta zo_pi                 ; 8 g = indeks wskaznika slotu 4 g w g_object_ptrs
	lda #4
	sta zo_n
	lda #0
	sta zo_b+1                ; brak slotu z typem < $56 w grupie (tmp bez zmian)
oa_slot
	ldy #OB_TYPE
	lda (zg_obj),y
	cmp #$56
	jcs oa_off                ; @obj_type_id_was_too_high
	tax                       ; adres granic: OD_BOUNDS + 8 * typ (tablice)
	lda oa_blo,x
	sta zo_b
	lda oa_bhi,x
	sta zo_b+1
	ldy #0                    ; BC = L - 6 (dekrementy ldi)
	sec
	lda (zo_b),y
	sbc #6
	sta zo_h
	iny
	lda (zo_b),y
	sbc #0
	sta zo_h+1
	sec                       ; xor a / sbc hl,bc: HL = cam_x - BC
	lda g_level_scroll_x_pix_lo
	sbc zo_h
	sta zo_h
	lda g_level_scroll_x_pix_lo+1
	sbc zo_h+1
	sta zo_h+1
	bcs oa_x0                 ; jr nc: bez pozyczki
	lda #0                    ; @skip_camera_left_clamp: HL = 0
	sta zo_h
	sta zo_h+1
oa_x0
	ldy #OB_X+1               ; sbc hl,de (x): HL >= x (bez pozyczki) -> nieaktywny (jp nc)
	sec
	lda zo_h
	sbc (zg_obj),y
	iny
	lda zo_h+1
	sbc (zg_obj),y
	bcs oa_off
	ldy #2                    ; HL = R + cam_x (16 bit); R = slowo +2 granic (tmp_00 oryginalu)
	clc
	lda (zo_b),y
	adc g_level_scroll_x_pix_lo
	sta zo_h
	iny
	lda (zo_b),y
	adc g_level_scroll_x_pix_lo+1
	sta zo_h+1
	ldy #OB_X+1               ; xor a / sbc hl,de: HL < x (pozyczka) -> nieaktywny (jp c)
	sec
	lda zo_h
	sbc (zg_obj),y
	iny
	lda zo_h+1
	sbc (zg_obj),y
	bcc oa_off
	ldy #4                    ; HL = cam_y - T; T = slowo +4 granic (tmp_02 oryginalu)
	sec
	lda g_level_scroll_y_pix_lo
	sbc (zo_b),y
	sta zo_h
	iny
	lda g_level_scroll_y_pix_lo+1
	sbc (zo_b),y
	sta zo_h+1
	bcs oa_y0
	lda #0                    ; @skip_camera_top_clamp
	sta zo_h
	sta zo_h+1
oa_y0
	ldy #OB_Y+1               ; HL >= y -> nieaktywny
	sec
	lda zo_h
	sbc (zg_obj),y
	iny
	lda zo_h+1
	sbc (zg_obj),y
	bcs oa_off
	ldy #6                    ; HL = B + cam_y; B = slowo +6 granic (tmp_04 oryginalu)
	clc
	lda (zo_b),y
	adc g_level_scroll_y_pix_lo
	sta zo_h
	iny
	lda (zo_b),y
	adc g_level_scroll_y_pix_lo+1
	sta zo_h+1
	ldy #OB_Y+1               ; HL < y -> nieaktywny
	sec
	lda zo_h
	sbc (zg_obj),y
	iny
	lda zo_h+1
	sbc (zg_obj),y
	bcc oa_off
	ldx zo_pi                 ; aktywny: wskaznik = adres SMS rekordu (lustro - $1000)
	lda zg_obj
	sta g_object_ptrs,x
	lda zg_obj+1
	sec
	sbc #>SMS_RAM
	sta g_object_ptrs+1,x
	bne oa_next               ; zawsze (starszy bajt adresu SMS rekordu $D4..$D7)
oa_off
	ldx zo_pi                 ; @disable_object: wskaznik 0 (C = 0)
	lda #0
	sta g_object_ptrs,x
	sta g_object_ptrs+1,x
oa_next
	inc zo_pi
	inc zo_pi
	clc
	lda zg_obj
	adc #OBJ_SIZE
	sta zg_obj
	bcc oa_nc
	inc zg_obj+1
oa_nc
	dec zo_n
	jne oa_slot
	lda zo_b+1                ; tmp_00..05 = R, T, B ostatniego slotu grupy z typem < $56 (ldi x 6 oryginalu)
	beq oa_ret
	ldy #2
oa_tmp
	lda (zo_b),y
	sta tmp_00-2,y
	iny
	cpy #8
	bne oa_tmp
oa_ret
	rts

oa_ix_lo	dta l(object_list, object_list+104, object_list+208, object_list+312, object_list+416, object_list+520, object_list+624, object_list+728)
oa_ix_hi	dta h(object_list, object_list+104, object_list+208, object_list+312, object_list+416, object_list+520, object_list+624, object_list+728)

; ---------------------------------------------------------------------
; obj_run_all: run_all_objfuncs (00:329B) dla slotow 1..31 - wskaznik != 0 -> try_run_objfunc_DE (00:32C8):
; typ $FF -> nic, inaczej funkcja typu (obj_call), potem return_from_objfunc (obj_return). Sonic (slot 0)
; w game/step.asm po powrocie z banku. Slot uruchomiony -> v_obj_dirty (trace testu).
; ---------------------------------------------------------------------
obj_run_all                     ; M4.9a: petla po indeksie wskaznika X = 2 * slot (zo_i = 2 * slot na czas funkcji)
	ldx #2
ora_slot
	lda g_object_ptrs+1,x
	tay
	ora g_object_ptrs,x
	beq ora_next
	stx zo_i
	tya
	clc
	adc #>SMS_RAM             ; adres SMS rekordu -> lustro
	sta zg_obj+1
	lda g_object_ptrs,x
	sta zg_obj
	ldy #OB_TYPE
	lda (zg_obj),y
	cmp #$FF
	beq ora_next
	txa
	lsr                       ; slot = indeks / 2
	jsr obj_dirty
	ldy #OB_TYPE
	lda (zg_obj),y
	jsr obj_call
	jsr obj_return
	ldx zo_i
ora_next
	inx
	inx
	cpx #2*N_OBJECTS
	bne ora_slot
	rts

; obj_run: sama funkcja obiektu ze slotu zg_obj (wejscie testu py65 OBJ_RUN: pary -obj z referencji, jp (hl)
; 00:32E1 -> 00:32E2; bez ruchu i rysowania z obj_return)
obj_run
	ldy #OB_TYPE
	lda (zg_obj),y
; obj_call: skok do funkcji obiektu typu A przez obj_fn_tab (LUT_object_functions 00:2AF6); typ spoza
; tablicy - zaslepka. Funkcja konczy sie rts (adres powrotu = return_from_objfunc jak push de / jp (hl)).
obj_call
	cmp #OD_NTYPES
	bcs obj_stub
	asl
	tax
	lda obj_fn_tab,x
	sta zo_vec
	lda obj_fn_tab+1,x
	sta zo_vec+1
	jmp (zo_vec)

; obj_stub: typ bez przekladu - licznik v_obj_todo, typ w v_obj_todo_id (stan obiektu bez zmian)
obj_stub
	ldy #OB_TYPE
	lda (zg_obj),y
	sta v_obj_todo_id
	inc v_obj_todo
	rts

; ---------------------------------------------------------------------
; obj_return: return_from_objfunc (00:32E2): ruch i kolizje z mapa (obj_motion, M3.2), potem (00:34E6)
; pozycja ekranowa y = (ix+5,6) - cam_y, x = (ix+2,3) - cam_x i draw_sprite_string, gdy mapa (ix+15,16) != 0.
; ---------------------------------------------------------------------
obj_return
	jsr obj_motion
obj_draw                        ; 00:34E6 (test py65 OBJ_DRAW: pary -rys z referencji)
	ldy #OB_SPRITE
	lda (zg_obj),y
	sta zd_map
	iny
	lda (zg_obj),y
	sta zd_map+1
	ora zd_map
	beq or_ret
	lda zd_map+1              ; M6.6: mapa z banku 2 ROM-u (adres SMS >= $8000) - w banku obiektow strefy: kopia do bufora
	bpl or_mapok
	jsr objz_mapcopy
or_mapok
	ldy #OB_Y+1
	sec
	lda (zg_obj),y
	sbc g_level_scroll_y_pix_lo
	sta zd_y
	iny
	lda (zg_obj),y
	sbc g_level_scroll_y_pix_lo+1
	sta zd_y+1
	ldy #OB_X+1
	sec
	lda (zg_obj),y
	sbc g_level_scroll_x_pix_lo
	sta zd_x
	iny
	lda (zg_obj),y
	sbc g_level_scroll_x_pix_lo+1
	sta zd_x+1
	jmp draw_sprite_string
or_ret
	rts

; ---------------------------------------------------------------------
; draw_sprite_string (00:350F): mapa zd_map (adres SMS = adres w banku 45) w pozycji ekranowej (zd_x, zd_y).
; tmp_06 = x. Do 3 wierszy po 6 bajtow (wiersze co 16 px, kolumny co 8 px); $FF na poczatku wiersza konczy.
; Wiersz: y w -16..-1 (hi $FF, lo >= $F0) albo 0..191 rysowany; y < -16 albo >= 256 pominiety; 192..255
; konczy mape. Sprite: kafel < $FE i x w 0..255 -> wpis (x, y, kafel) pod g_next_avail_vdp_sprite_ptr
; (inc e: mlodszy bajt zawija w stronie $D0), g_sprite_count + 1.
; ---------------------------------------------------------------------
draw_sprite_string
	lda g_next_avail_vdp_sprite_ptr ; M4.2: grupa wpisow tego wywolania (priorytet tla w rendererze)
	pha
	jsr dss_body
	pla
	jmp grp_add
dss_body
	lda zd_x
	sta tmp_06                ; ld (tmp_06),hl
	lda zd_x+1
	sta tmp_06+1
	lda #3
	sta zd_r
dss_row
	ldy #0
	lda (zd_map),y
	cmp #$FF
	jeq dss_ret               ; ret z: koniec mapy
	lda zd_y+1
	cmp #$FF
	bne dss_left
	lda zd_y
	cmp #$F0
	bcc dss_skip              ; y < -16: @move_to_next_row
	bcs dss_draw
dss_left                        ; @consider_left_side_culling: hi != 0 -> pominiety, lo >= $C0 -> koniec
	ora #0
	bne dss_skip
	lda zd_y
	cmp #$C0
	jcs dss_ret
dss_draw
	lda tmp_06                ; x wiersza od nowa (ld hl,(tmp_06))
	sta zd_cx
	lda tmp_06+1
	sta zd_cx+1
	ldx g_next_avail_vdp_sprite_ptr
	ldy #0
	lda zd_cx+1
	bne dss_spr               ; M4.9a: x hi != 0 - petla ogolna (kolumny poza 0..255 pomijane)
	lda zd_cx
	cmp #216
	bcs dss_spr               ; x > 215: ktoras kolumna przekroczy 255 - petla ogolna
dss_fast                        ; wiersz w calosci w 0..255: bez testu starszego bajtu x (A = x kolumny)
	sta zd_cx
	lda (zd_map),y
	cmp #$FE
	bcs dss_fcull             ; $FE / $FF: kolumna pominieta
	sta SPRTAB+2,x            ; wpis (x, y, kafel)
	lda zd_cx
	sta SPRTAB,x
	lda zd_y
	sta SPRTAB+1,x
	inx
	inx
	inx
	inc g_sprite_count
dss_fcull
	lda zd_cx
	clc
	adc #8
	iny
	cpy #6
	bne dss_fast
	beq dss_rowend            ; zawsze
dss_spr
	lda zd_cx+1
	bne dss_cull              ; x poza 0..255
	lda (zd_map),y
	cmp #$FE
	bcs dss_cull              ; $FE / $FF: kolumna pominieta
	sta SPRTAB+2,x            ; wpis (x, y, kafel)
	lda zd_cx
	sta SPRTAB,x
	lda zd_y
	sta SPRTAB+1,x
	inx
	inx
	inx
	inc g_sprite_count
dss_cull
	clc
	lda zd_cx
	adc #8
	sta zd_cx
	bcc dss_cx
	inc zd_cx+1
dss_cx
	iny
	cpy #6
	bne dss_spr
dss_rowend
	stx g_next_avail_vdp_sprite_ptr
dss_skip                        ; nastepny wiersz: mapa + 6, y + 16
	clc
	lda zd_map
	adc #6
	sta zd_map
	bcc dss_m
	inc zd_map+1
dss_m
	clc
	lda zd_y
	adc #16
	sta zd_y
	bcc dss_y
	inc zd_y+1
dss_y
	dec zd_r
	jne dss_row
dss_ret
	rts

; ---------------------------------------------------------------------
; draw_sprite (00:3581): jeden sprite kafla A w (tmp_00 + tmp_04 - cam_x, tmp_02 + tmp_06 - cam_y):
; x poza 0..255 -> nic; y: hi $FF i lo < $F0 -> nic, hi $FF i lo >= $F0 -> rysowany, hi != 0 -> nic,
; lo >= $C0 -> nic. Wpis pod g_next_avail_vdp_sprite_ptr (inc c), g_sprite_count + 1.
; ---------------------------------------------------------------------
draw_sprite
	sta zd_r                  ; kafel (ld c,a)
; M7.5 Z7 (docs/plan-m7-ntsc.md 2 Z7, decyzja docs/plan-m7.md M7.5): bez pha / jsr ds1_body / pla / jmp grp_add - grupa wpisu (renderer,
; priorytet tla) dopisywana w linii (stary wskaznik = nowy - 3 mod 256, jak grp_add). Wynik identyczny: wpis tablicy sprite'ow, licznik,
; wskaznik, grupy (v_grp_s / v_grp_e / v_ngrp), zd_x / zd_y / zd_r (tez przy odrzuceniu), Y zachowany, X jak dawniej (odrzucenie - bez
; zmian, wpis - v_ngrp). Ok. 35 cykli mniej na wywolanie (arena SKY3: 26 wywolan w ticku luku zappera).
; Kontrakt wyjscia: A i flagi N / Z / C nieokreslone (inne niz przed M7.5) - zaden wolajacy ich nie czyta (review M7.5: 4 jsr, 1 skok
; ogonowy, 21 zc_dspr; tak samo przeklady w linii sk46_pair (bank 30) i wln_put (bank 11)); nowy wolajacy nie moze na nich polegac.
ds1_body
	clc                       ; y
	lda tmp_02
	adc tmp_06
	sta zd_y
	lda tmp_02+1
	adc tmp_06+1
	sta zd_y+1
	sec
	lda zd_y
	sbc g_level_scroll_y_pix_lo
	sta zd_y
	lda zd_y+1
	sbc g_level_scroll_y_pix_lo+1
	sta zd_y+1
	clc                       ; x
	lda tmp_00
	adc tmp_04
	sta zd_x
	lda tmp_00+1
	adc tmp_04+1
	sta zd_x+1
	sec
	lda zd_x
	sbc g_level_scroll_x_pix_lo
	sta zd_x
	lda zd_x+1
	sbc g_level_scroll_x_pix_lo+1
	bne ds1_ret               ; x hi != 0
	lda zd_y+1
	beq ds1_y0
	cmp #$FF
	bne ds1_ret               ; y hi != 0 i != $FF
	lda zd_y
	cmp #$F0
	bcc ds1_ret               ; y < -16
	bcs ds1_put
ds1_y0
	lda zd_y
	cmp #$C0
	bcs ds1_ret
ds1_put
	ldx g_next_avail_vdp_sprite_ptr
	lda zd_x
	sta SPRTAB,x
	inx
	lda zd_y
	sta SPRTAB,x
	inx
	lda zd_r
	sta SPRTAB,x
	inx
	stx g_next_avail_vdp_sprite_ptr
	inc g_sprite_count
	ldx v_ngrp                ; grp_add w linii (wpis dodany - grupa niepusta)
	cpx #N_GROUPS
	bcs ds1_ret
	lda g_next_avail_vdp_sprite_ptr
	sta v_grp_e,x
	sec
	sbc #3
	sta v_grp_s,x
	inc v_ngrp
ds1_ret
	rts

; grp_add: M4.2 - grupa wpisow tablicy sprite'ow od mlodszego bajtu wskaznika A do biezacego (v_grp_s/e,
; render/objspr.asm: obwiednia -> priorytet tla); bez wpisow albo bez miejsca - nic. Stan gry bez zmian.
grp_add
	cmp g_next_avail_vdp_sprite_ptr
	beq ga_ret
	ldx v_ngrp
	cpx #N_GROUPS
	bcs ga_ret
	sta v_grp_s,x
	lda g_next_avail_vdp_sprite_ptr
	sta v_grp_e,x
	inc v_ngrp
ga_ret
	rts

; ---------------------------------------------------------------------
; obj_fn_tab: funkcje obiektow wg typu $00-$55 (LUT_object_functions 00:2AF6); obj_stub - typ bez przekladu
; ($00 Sonic - poza dyspozytorem)
; ---------------------------------------------------------------------
obj_fn_tab
	dta a(obj_stub, objfunc_01_monitor_rings, objfunc_02_monitor_shoes, objfunc_03_monitor_life)   ; $00
	dta a(objfunc_04_monitor_shield, objfunc_05_monitor_invinc, objfunc_06_chaos_emerald, objfunc_07_signpost) ; $04
	dta a(objfunc_08_crabmeat, objfunc_09_platform_swing, objfunc_0A_explosion, objfunc_0B_platform_semilowering) ; $08
	dta a(objz_call, objfunc_0D_fireball, objfunc_0E_buzz_bomber, objfunc_0F_platform_horizontal)         ; $0C (M6.7: $0C w banku obiektow strefy)
	dta a(objfunc_10_motobug, objz_call, objfunc_12_boss, objz_call, objz_call, objz_call, objz_call, objz_call)   ; $10 (M6.4: $12 boss; M6.9: $13-$17 SBZ)
	dta a(objz_call, objz_call, objz_call, objz_call, objz_call, objz_call, objz_call, objz_call)   ; $18 (M6.8: $1D przycisk; M6.9: $18-$1F SBZ - bank v_pbobjz)
	dta a(objz_call, objz_call, objz_call, objfunc_23_animal_0, objfunc_24_animal_1, objfunc_25_capsule, objfunc_26_badnik_chopper, objz_call)   ; $20 (M6.4: $23-$25; M6.6: $26; M6.7: $27; M6.8: $20 babel; M6.9: $22 scenka SBZ3)
	dta a(objz_call, objz_call, objz_call, objz_call, objz_call, objz_call, objz_call, objz_call)   ; $28 (M6.6: $2D, $2E; M6.7: $28, $29, $2B, $2C; M6.8: $2A, $2F w banku obiektow strefy)
	dta a(objz_call, objz_call, objz_call, objz_call, objz_call, objz_call, objz_call, objz_call)   ; $30 (M6.8: $35, $36 Orbinaut; M6.10: $30-$37 SKY)
	dta a(objz_call, objz_call, objz_call, objz_call, objz_call, objz_call, objz_call, objz_call)   ; $38 (M6.6: $3B; M6.8: $3C-$3F; M6.10: $38-$3A SKY)
	dta a(objz_call, objz_call, objz_call, obj_stub, objz_call, objz_call, objz_call, objz_call)   ; $40 (M6.8: $40-$42 woda, $44 Burrobot, $45 platforma; M6.10: $46, $47 SKY3)
	dta a(objz_call, objz_call, objz_call, objfunc_4B_pit, objz_call, obj_stub, objz_call, obj_stub)   ; $48 (M6.6: $48 boss BRI3, $4E hustawka; M6.8: $49 boss LAB3; M6.10: $4A boss SKY3; M6.11: $4C flipper)
	dta a(objfunc_50_flower, objfunc_51_monitor_checkpoint, objfunc_52_monitor_continue, objz_call, objz_call, objfunc_55_thrown_rings) ; $50 (M6.11: $53, $54 koniec gry)
