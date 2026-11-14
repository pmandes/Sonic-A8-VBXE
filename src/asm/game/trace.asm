; =====================================================================
;  trace.asm - rekord stanu po kazdym kroku petli poziomu do bufora w bankach (format v2, M4.0)
;  Format rekordu, lista pol i bankow: tools/m3_trace.py (PORT_*), tabele generowane do m3_trace.inc.
;  Rekord o zmiennej dlugosci (pole len), w banku od $4000 do $7FFF; gdy do konca banku zostaje mniej
;  niz TR_MAXREC - nastepny bank z tablicy tr_bank_tab (znacznik konca: bajt +6 = 0 zamiast TR_MARK):
;   +0 krok (i16), +2 irq, +3 wejscie, +4 zamiar, +5 flagi, +6 TR_MARK, +7 segment (M3.7), +8 len (u16)
;   blok A: pola PORT_POLA (TR_NA B) roznicowo wzgledem cienia TRSH_A: n, potem n par (indeks, wartosc);
;           w klatce kluczowej n = $FF i caly blok
;   blok B: g_object_ptrs (64 B) tak samo wzgledem cienia TRSH_B
;   maska slotow (4 B, bit s = slot s 1..31) i pelne rekordy zaznaczonych slotow (26 B, rosnaco):
;           slot aktywny (wskaznik != 0), oznaczony w v_obj_dirty (uruchomiony / utworzony w kroku)
;           albo wszystkie w klatce kluczowej
;   tablica sprite'ow: liczba wpisow g_sprite_count (max 64) i wpisy 21..liczba-1 (3 B)
;  Klatka kluczowa: krok -16 (start poziomu / segmentu) i co TR_KEYN rekordow.
;  Zapis tylko gdy v_trace_on (ustawia test z debuggera); po v_tr_limit rekordach albo przy pelnym
;  buforze - trace_done (punkt zrzutu: .writemem $PB'4000 dla kazdego banku z tablicy).
; =====================================================================
; flagi rekordu F_SONIC / F_ROZGRZEWKA / F_DEMO: src/kernel/mem.inc (M7.2 - liczy je game/step.asm takze w buildach bez trace'u)
TR_KEYN     = 64          ; klatka kluczowa co tyle rekordow
TR_RAW       = $FF         ; n bloku: caly blok bez roznic
SPR_TAB21    = $D03F+SMS_RAM ; g_sprite_table_21: pierwszy wpis za Sonikiem (HUD, obiekty)

trace_record
	lda v_trace_on
	jeq tr_rts
	lda v_tr_ptr+1            ; miejsce na najdluzszy rekord przed koncem banku?
	cmp #>[BANK_WIN+$4000-TR_MAXREC]
	bcc tr_room
	jsr tr_bank_end
	inc v_tr_bank
	lda v_tr_bank
	cmp v_tr_nbanks            ; M6.9: liczba bankow bufora (TR_NBANKS + wolne banki stref dopisane przez m3_test)
	bcc tr_newb
	lda #PB_MAIN              ; bufor pelny
	sta PORTB
	lda #0
	sta v_trace_on
	jmp trace_done
tr_newb
	mwa #BANK_WIN v_tr_ptr
tr_room
	ldx v_tr_bank
	lda tr_bank_tab,x
	jsr select_bank
	mwa v_tr_ptr zg_ptr
; klatka kluczowa: krok -16 albo co TR_KEYN rekordow
	lda #0
	sta zt_key
	lda v_step
	cmp #<-16
	bne tr_nk16
	lda v_step+1
	cmp #>-16
	beq tr_key
tr_nk16
	lda v_tr_kcnt
	bne tr_nokey
tr_key
	lda #1
	sta zt_key
	lda #TR_KEYN
	sta v_tr_kcnt
tr_nokey
	dec v_tr_kcnt
; naglowek
	ldy #0
	lda v_step
	sta (zg_ptr),y
	iny
	lda v_step+1
	sta (zg_ptr),y
	iny
	lda v_tr_irq
	sta (zg_ptr),y
	iny
	lda v_tr_in
	sta (zg_ptr),y
	iny
	lda v_tr_int
	sta (zg_ptr),y
	iny
	lda v_tr_fl
	sta (zg_ptr),y
	iny
	lda #TR_MARK
	sta (zg_ptr),y
	iny
	lda v_segment             ; M3.7: numer startu poziomu (zycia / nowej gry) - kroki + 100000 * segment
	sta (zg_ptr),y
	clc
	lda zg_ptr
	adc #TR_HDR
	sta zg_dst
	lda zg_ptr+1
	adc #0
	sta zg_dst+1
	jsr tr_blk_a
	jsr tr_blk_b
	jsr tr_slots
	jsr tr_sprites
; dlugosc rekordu = zg_dst - poczatek
	sec
	lda zg_dst
	sbc zg_ptr
	ldy #8
	sta (zg_ptr),y
	lda zg_dst+1
	sbc zg_ptr+1
	iny
	sta (zg_ptr),y
	mwa zg_dst v_tr_ptr
	lda #0                    ; sloty oznaczone w tym kroku zapisane
	sta v_obj_dirty
	sta v_obj_dirty+1
	sta v_obj_dirty+2
	sta v_obj_dirty+3
	inc v_tr_count
	bne tr_cnt_ok
	inc v_tr_count+1
tr_cnt_ok
	lda v_tr_count
	cmp v_tr_limit
	bne tr_main
	lda v_tr_count+1
	cmp v_tr_limit+1
	bne tr_main
	jsr tr_bank_end           ; znacznik konca za ostatnim rekordem
	lda #PB_MAIN
	sta PORTB
	lda #0
	sta v_trace_on
trace_done                      ; bufor trace'u gotowy (punkt zrzutu testu)
	rts
tr_main
	lda #PB_MAIN
	sta PORTB
tr_rts
	rts

; tr_bank_end: znacznik konca rekordow w biezacym banku: bajt +6 rekordu pod v_tr_ptr = 0, gdy miesci sie
; w banku (v_tr_ptr <= $7FF9). Wlacza bank biezacy (PORTB zostaje na banku).
tr_bank_end
	ldx v_tr_bank
	lda tr_bank_tab,x
	jsr select_bank
	lda v_tr_ptr+1
	cmp #>[BANK_WIN+$4000]
	bcs tbe_done              ; ptr = $8000: bank pelny
	cmp #>[BANK_WIN+$3F00]
	bcc tbe_put
	lda v_tr_ptr
	cmp #$FA
	bcs tbe_done
tbe_put
	mwa v_tr_ptr zg_ptr
	ldy #6
	lda #0
	sta (zg_ptr),y
tbe_done
	rts

; tr_pair: para (X, A) pod zg_dst, zg_dst += 2, zt_n++ (X zachowany, Y zachowany przez zt_y)
tr_pair
	sty zt_y
	ldy #1
	sta (zg_dst),y
	dey
	txa
	sta (zg_dst),y
	clc
	lda zg_dst
	adc #2
	sta zg_dst
	bcc trp_nc
	inc zg_dst+1
trp_nc
	inc zt_n
	ldy zt_y
	rts

; tr_byte: A -> (zg_dst), zg_dst++ (niszczy Y)
tr_byte
	ldy #0
	sta (zg_dst),y
	inc zg_dst
	bne trb_nc
	inc zg_dst+1
trb_nc
	rts

; tr_blk_a: pola PORT_POLA (tablica tr_field_*) wzgledem cienia TRSH_A, indeks plaski X = 0..TR_NA-1
tr_blk_a
	lda zt_key
	bne tra_raw
	mwa zg_dst zt_np          ; miejsce na licznik par
	lda #0
	sta zt_n
	jsr tr_byte
	ldx #0
	stx zt_f
tra_field
	ldy zt_f
	lda tr_field_lo,y
	sta zg_src
	lda tr_field_hi,y
	sta zg_src+1
	lda tr_field_len,y
	sta zt_l
	ldy #0
tra_byte
	lda (zg_src),y
	cmp TRSH_A,x
	beq tra_next
	sta TRSH_A,x
	jsr tr_pair
tra_next
	inx
	iny
	cpy zt_l
	bne tra_byte
	inc zt_f
	lda zt_f
	cmp #TR_NFIELDS
	bne tra_field
	lda zt_n
	ldy #0
	sta (zt_np),y
	rts
; klatka kluczowa: n = $FF i caly blok (cien = blok)
tra_raw
	lda #TR_RAW
	jsr tr_byte
	ldx #0
	stx zt_f
trr_field
	ldy zt_f
	lda tr_field_lo,y
	sta zg_src
	lda tr_field_hi,y
	sta zg_src+1
	lda tr_field_len,y
	sta zt_l
	lda #0
	sta zt_y
trr_byte
	ldy zt_y
	lda (zg_src),y
	sta TRSH_A,x
	jsr tr_byte
	inx
	inc zt_y
	lda zt_y
	cmp zt_l
	bne trr_byte
	inc zt_f
	lda zt_f
	cmp #TR_NFIELDS
	bne trr_field
	rts

; tr_blk_b: g_object_ptrs (64 B) wzgledem cienia TRSH_B
tr_blk_b
	lda zt_key
	bne trb_raw
	mwa zg_dst zt_np
	lda #0
	sta zt_n
	jsr tr_byte
	ldx #0
trb_loop
	lda g_object_ptrs,x
	cmp TRSH_B,x
	beq trb_same
	sta TRSH_B,x
	jsr tr_pair
trb_same
	inx
	cpx #64
	bne trb_loop
	lda zt_n
	ldy #0
	sta (zt_np),y
	rts
trb_raw
	lda #TR_RAW
	jsr tr_byte
	ldx #0
trbr_cp
	lda g_object_ptrs,x
	sta TRSH_B,x
	jsr tr_byte
	inx
	cpx #64
	bne trbr_cp
	rts

; tr_slots: maska slotow 1..31 (v_obj_dirty | wskaznik != 0 | klatka kluczowa) i ich rekordy (26 B)
tr_slots
	ldx #3
trs_m0
	lda v_obj_dirty,x
	ldy zt_key
	beq trs_m0k
	lda #$FF
trs_m0k
	sta v_tr_mask,x
	dex
	bpl trs_m0
	ldx #1                    ; slot
trs_m1
	txa
	asl
	tay
	lda g_object_ptrs,y
	ora g_object_ptrs+1,y
	beq trs_m2
	txa
	lsr
	lsr
	lsr
	tay
	txa
	and #7
	sty zt_y
	tay
	lda bit_tab,y
	ldy zt_y
	ora v_tr_mask,y
	sta v_tr_mask,y
trs_m2
	inx
	cpx #N_OBJECTS
	bne trs_m1
	lda v_tr_mask
	and #$FE                  ; slot 0 (Sonic) jest w polach bloku A
	sta v_tr_mask
	ldx #0
trs_wm
	lda v_tr_mask,x
	jsr tr_byte
	inx
	cpx #4
	bne trs_wm
	mwa #object_list+OBJ_SIZE zg_src
	ldx #1
trs_slot
	txa
	lsr
	lsr
	lsr
	tay
	txa
	and #7
	sty zt_y
	tay
	lda bit_tab,y
	ldy zt_y
	and v_tr_mask,y
	beq trs_skip
	ldy #0
trs_cp
	lda (zg_src),y
	sta (zg_dst),y
	iny
	cpy #OBJ_SIZE
	bne trs_cp
	clc
	lda zg_dst
	adc #OBJ_SIZE
	sta zg_dst
	bcc trs_skip
	inc zg_dst+1
trs_skip
	clc
	lda zg_src
	adc #OBJ_SIZE
	sta zg_src
	bcc trs_nc
	inc zg_src+1
trs_nc
	inx
	cpx #N_OBJECTS
	bne trs_slot
	rts

; tr_sprites: liczba wpisow tablicy sprite'ow (max 64) i wpisy 21..liczba-1
tr_sprites
	lda g_sprite_count
	cmp #65
	bcc trsp_n
	lda #64
trsp_n
	sta zt_l
	jsr tr_byte
	lda zt_l
	sec
	sbc #21
	bcc trsp_done
	beq trsp_done
	sta zt_n
	asl
	adc zt_n                  ; 3 B na wpis (C = 0 po asl, bo liczba <= 43)
	sta zt_n
	ldy #0
trsp_cp
	lda SPR_TAB21,y
	sta (zg_dst),y
	iny
	cpy zt_n
	bne trsp_cp
	clc
	tya
	adc zg_dst
	sta zg_dst
	bcc trsp_done
	inc zg_dst+1
trsp_done
	rts

	icl 'm3_trace.inc'
