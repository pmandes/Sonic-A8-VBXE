; =====================================================================
;  hud.asm - M3.7c: HUD (zycia, pierscienie, czas) w liscie ramki
;
;  Napisy HUD-u (game/hud.asm: migawka v_hud_*) sa skladane na plotnach w VRAM ze sprite'ow 8x16 SMS
;  (kafle n, n+1 w SPRATLAS_VRAM = 128 B ciagle): BCB kopii znaku w slotach blokow listy (od konca,
;  wykonywane przed widokiem i obiektami), tylko dla znakow, ktore sie zmienily (v_hudc_* = stan plotna).
;  Plotna: zycia 32x16 (HUD_LIVES_VRAM) i wspolne 36x32 pierscieni i czasu (HUD_TOP_VRAM, krok 64) - uklad
;  jak na ekranie od (20, 1): ikona (0, 0), cyfry (20, 0), czas (4, 16); luki (kolor 0 = przezroczysty) zeruje
;  hud_clear przy starcie - znaki ich nie dotykaja. (BCB wypelnienia z maska AND = 0 nie: emit_block
;  i emit_ring nie ustawiaja maski, wiec slot po nim zerowalby bloki tla.) Co ramke 2 obiekty stencil (obj_emit): zycia i plotno pierscieni z czasem
;  (osobno, gdy widac tylko jedno z nich albo czas stoi w pozycji etapu specjalnego) - przed Sonikiem (SMS:
;  wpisy HUD-u 21+ ponizej Sonica 12-20), z priorytetem tla jak inne obiekty. VDP rysuje sprite o linie
;  nizej: y ekranu = y tekstu + 1.
;  Priorytet tla nad HUD-em (prostokaty or_* na rzeczywiste napisy) tylko, gdy blok z priorytetem lezy
;  w kolumnach bx..bx+2 i wierszach by..by+1 / by+5..by+6 okna (wszystkie bloki, ktore moga byc pod HUD-em
;  przy dowolnym camx & 31, camy & 31) - inaczej prio_rect nic by nie dodal, a kosztuje ok. 550 cykli.
; =====================================================================

; hud_clear: plotna HUD-u (HUD_VRAM .. koniec plotna pierscieni i czasu) zerami przez okno MEMAC - raz
; przy starcie (load_sprite_data)
hud_clear
	jsr nt_reset              ; M7.5: pamieci podreczne renderera NTSC (render/prio.asm) - przed init_list_set obu kompletow
	lda #$FF                  ; brak pamietanego wyniku hud_prio_near
	sta zh_by
	lda #0                    ; brak pamieci BCB HUD-u (M3.8d)
	sta zh_sig
	sta zh_sig+1
	lda #MB_HUD
	jsr set_memac
	mwa #MEMAC_CPU+[HUD_VRAM&$1FFF] zp_dst
	ldx #>[HUD_TOP_VRAM+32*HUD_TOP_STR-HUD_VRAM] ; strony
	lda #0
	tay
hcl_l
	sta (zp_dst),y
	iny
	bne hcl_l
	inc zp_dst+1
	dex
	bne hcl_l
	lda #MB_LOW
	jmp set_memac

; hud_canvas: BCB plotna dla listy v_lbuild (wolane po blokach i pierscieniach, przed widokiem)
hud_canvas
	lda v_hudc_st
	bne hc_dyn
	lda #1                    ; hc_char zeruje przy braku slotu: plotno w calosci w nastepnej liscie
	sta v_hudc_st
	lda #$A0                  ; czesci stale: zycia $A0 $A2 $A4, ikona $A6 $A8, dwukropek czasu $B0
	ldx #0
	jsr hc_lives
	lda #$A2
	ldx #1
	jsr hc_lives
	lda #$A4
	ldx #2
	jsr hc_lives
	lda #$A6
	ldx #0
	jsr hc_icon
	lda #$A8
	ldx #1
	jsr hc_icon
	lda #$B0
	ldx #1
	jsr hc_time
	lda #$FF                  ; wymuszenie wszystkich cyfr
	sta v_hudc_l
	sta v_hudc_r
	sta v_hudc_m
	sta v_hudc_s
	jmp hc_dyn
hc_dyn
	lda v_hud_l               ; cyfra zyc (kolumna 3)
	cmp v_hudc_l
	beq hc_r
	sta v_hudc_l
	ldx #3
	jsr hc_lives
hc_r
	lda v_hud_r               ; pierscienie BCD: 2 cyfry
	cmp v_hudc_r
	beq hc_m
	eor v_hudc_r
	sta v_hud_x               ; zmienione polbajty
	lda v_hud_r
	sta v_hudc_r
	lda v_hud_x
	and #$F0
	beq hc_r1
	lda v_hudc_r
	jsr hc_hi_tile
	ldx #0
	jsr hc_rdig
hc_r1
	lda v_hud_x
	and #$0F
	beq hc_m
	lda v_hudc_r
	jsr hc_lo_tile
	ldx #1
	jsr hc_rdig
hc_m
	lda v_hud_m               ; minuty (kolumna 0)
	cmp v_hudc_m
	beq hc_s
	sta v_hudc_m
	jsr hc_lo_tile
	ldx #0
	jsr hc_time
hc_s
	lda v_hud_s               ; sekundy BCD (kolumny 2, 3)
	cmp v_hudc_s
	beq hc_ret
	eor v_hudc_s
	sta v_hud_x
	lda v_hud_s
	sta v_hudc_s
	lda v_hud_x
	and #$F0
	beq hc_s1
	lda v_hudc_s
	jsr hc_hi_tile
	ldx #2
	jsr hc_time
hc_s1
	lda v_hud_x
	and #$0F
	beq hc_ret
	lda v_hudc_s
	jsr hc_lo_tile
	ldx #3
	jmp hc_time
hc_ret
	rts

hc_hi_tile                      ; A = BCD -> kafel cyfry starszej ($80 + 2 * d)
	lsr
	lsr
	lsr
	lsr
hc_lo_tile2
	asl
	adc #$80                  ; C = 0 (d <= 15)
	rts
hc_lo_tile                      ; A = BCD -> kafel cyfry mlodszej
	and #$0F
	jmp hc_lo_tile2

; hc_*: A = kafel, X = kolumna (znak 8 px) -> BCB kopii znaku 8x16 na plotno
hc_lives
	ldy #0
	beq hc_char
hc_icon
	ldy #1
	bne hc_char
hc_rdig
	ldy #2
	bne hc_char
hc_time
	ldy #3
hc_char
	sta v_tile
	stx v_hud_col
	sty v_hud_cv
	lda v_slot                ; brak slotu: plotno odrysowane w calosci w nastepnej liscie
	bne hc_slot
	lda #0
	sta v_hudc_st
	rts
hc_slot
	jsr next_slot             ; zp_bcb = slot (od konca slotow blokow); wszystkie pola - slot mogl byc
	lda #K_OTHER              ; blokiem albo pierscieniem (KIND_RAM: nastepny blok / pierscien w tym
	sta KIND_RAM,y            ; slocie zapisze wszystkie pola)
	ldy #BCB_BYTES-1
hc_tpl
	lda hud_tpl,y
	sta (zp_bcb),y
	dey
	bpl hc_tpl
	lda v_tile                ; zrodlo = SPRATLAS + kafel * 64 (krok Y 8)
	and #3
	lsr
	ror
	ror
	ldy #0
	sta (zp_bcb),y
	lda v_tile
	lsr
	lsr
	clc
	adc #>[SPRATLAS_VRAM&$FFFF]
	iny
	sta (zp_bcb),y
	ldx v_hud_cv              ; cel = napis + kolumna * 8 (krok Y = krok plotna)
	lda v_hud_col
	asl
	asl
	asl
	clc
	adc hud_cv_lo,x
	ldy #6
	sta (zp_bcb),y
	lda hud_cv_mid,x
	adc #0
	iny
	sta (zp_bcb),y
	lda hud_cv_str,x
	ldy #9
	sta (zp_bcb),y
	rts

; szablon BCB znaku: SPRATLAS (krok 8) -> plotno (krok Y patchowany), 8x16, kopia + NEXT
hud_tpl
	dta b(0),b(0),b(SPRATLAS_VRAM>>16), a(8),b(1)
	dta b(0),b(0),b(HUD_VRAM>>16), a(32),b(1)
	dta a(7),b(15)
	dta b($FF,$00,$00,$00,$00,$08)
; napisy na plotnach: 0 zycia, 1 ikona pierscienia, 2 cyfry pierscieni, 3 czas
hud_cv_lo	dta b(<HUD_LIVES_VRAM), b(<HUD_TOP_VRAM), b(<[HUD_TOP_VRAM+20]), b(<HUD_TIME_VRAM)
hud_cv_mid	dta b([HUD_LIVES_VRAM>>8]&$FF), b([HUD_TOP_VRAM>>8]&$FF), b([[HUD_TOP_VRAM+20]>>8]&$FF)
	dta b([HUD_TIME_VRAM>>8]&$FF)
hud_cv_str	dta b(32), b(HUD_TOP_STR), b(HUD_TOP_STR), b(HUD_TOP_STR)

; ---------------------------------------------------------------------
; hud_objs: obiekty HUD-u (stencil z plotna) - wolane w obj_bcbs przed Sonikiem (sloty od SLOT_OBJ zawsze
; wolne). Prostokaty or_* obiektow HUD-u zastepuje prostokatami napisow albo niczym (ho_prio).
; ---------------------------------------------------------------------
HOB_LIVES    = 0           ; obiekty: tablice ho_*
HOB_TOP      = 1
HOB_RINGS    = 2
HOB_TIME     = 3
HOB_TIMESP   = 4

hud_objs
; M3.8d: HUD stoi w pierwszych slotach obiektow; komplet listy i bufor obrazu zmieniaja sie razem, wiec BCB
; z poprzedniej listy tego kompletu sa aktualne, gdy zgadza sie zestaw obiektow (v_hud_fl) i bufor.
	ldx v_lbuild
	lda v_hud_fl
	and #HUD_RINGS|HUD_TIME|HUD_SPECIAL
	ora #$80
	cmp zh_sig,x
	bne ho_new
	lda v_fbm
	cmp zh_fbm,x
	bne ho_new
	lda v_oslot
	clc
	adc zh_n,x
	sta v_oslot
	lda zh_lastlo,x
	sta zp_last
	lda zh_lasthi,x
	sta zp_last+1
	ldy #20                   ; ostatni BCB HUD-u mogl byc koncem listy (bez NEXT) - stencil + NEXT
	lda #$09
	sta (zp_last),y
	jmp ho_prio
ho_new
	ldx #HOB_LIVES
	jsr ho_obj
	lda v_hud_fl
	and #HUD_RINGS|HUD_TIME|HUD_SPECIAL
	cmp #HUD_RINGS|HUD_TIME
	bne ho_sep
	ldx #HOB_TOP               ; pierscienie i czas jednym obiektem
	jsr ho_obj
	jmp ho_store
ho_sep
	lda v_hud_fl
	and #HUD_RINGS
	beq ho_time
	ldx #HOB_RINGS
	jsr ho_obj
ho_time
	lda v_hud_fl
	and #HUD_TIME
	beq ho_store
	ldx #HOB_TIME
	lda v_hud_fl
	and #HUD_SPECIAL
	beq ho_t
	ldx #HOB_TIMESP
ho_t
	jsr ho_obj
ho_store                        ; pamiec BCB HUD-u tego kompletu
	ldx v_lbuild
	lda v_hud_fl
	and #HUD_RINGS|HUD_TIME|HUD_SPECIAL
	ora #$80
	sta zh_sig,x
	lda v_fbm
	sta zh_fbm,x
	lda v_oslot
	sec
	sbc #SLOT_OBJ
	sta zh_n,x
	lda zp_last
	sta zh_lastlo,x
	lda zp_last+1
	sta zh_lasthi,x
ho_prio                         ; prostokaty priorytetu: napisy HUD-u (do 32x32) albo nic
	lda #0
	sta v_nobj
	lda v_hud_fl
	and #HUD_SPECIAL
	bne ho_pr                 ; czas w srodku ekranu (etap specjalny): zawsze
	jsr hud_prio_near
	bcc ho_ret
ho_pr
	ldx #HOB_LIVES
	jsr ho_rect
	lda v_hud_fl
	and #HUD_RINGS
	beq ho_pt
	ldx #HR_ICON
	jsr ho_rect
	ldx #HR_RDIG
	jsr ho_rect
ho_pt
	lda v_hud_fl
	and #HUD_TIME
	beq ho_ret
	ldx #HOB_TIME
	lda v_hud_fl
	and #HUD_SPECIAL
	beq ho_rect
	ldx #HOB_TIMESP
ho_rect                         ; X = prostokat (ho_x/ho_y/ho_w, wysokosc 16) -> or_*[v_nobj]
	ldy v_nobj
	lda ho_x,x
	sta or_x,y
	lda ho_y,x
	sta or_y,y
	lda ho_w,x
	sta or_w,y
	lda #16
	sta or_h,y
	inc v_nobj
ho_ret
	rts

ho_obj                          ; X = obiekt HUD-u -> obj_emit
	lda ho_x,x
	sta v_ox
	lda ho_y,x
	sta v_oy
	lda ho_w,x
	sta v_ow
	lda ho_h,x
	sta v_oh
	lda ho_lo,x
	sta v_osrc
	lda ho_mid,x
	sta v_osrc+1
	lda ho_str,x
	sta v_ostride
	lda #HUD_VRAM>>16
	sta v_osrc+2
	lda #1
	sta v_ostepx
	jmp obj_emit

; hud_prio_near: C = 1, gdy w blokach mogacych lezec pod HUD-em jest blok z priorytetem (PRIO_RAM).
; M3.8c: wynik pamietany dla okna (zh_bx, zh_by); build_frame_list kasuje go po lacie i pelnym przeladowaniu.
hud_prio_near
	lda v_by
	cmp zh_by
	bne hpn_calc
	lda v_bx
	cmp zh_bx
	bne hpn_calc
	lda zh_res                ; b0 = C
	lsr
	rts
hpn_calc
	lda v_bx
	sta zh_bx
	lda v_by
	sta zh_by
	jsr hpn_scan
	lda #0
	rol
	sta zh_res
	lsr
	rts
hpn_scan                        ; M7.5 Z4: z mapy priorytetu okna (render/prio.asm PRIOCOLM) zamiast 12 odczytow ukladu (hp_row): kolumny
	lda v_bx                  ; bx..bx+2, wiersze by, by + 1, by + 5, by + 6 - wszystkie w oknie, bity dokladne (wiersz >= v_lvh = 0
	and #15                   ; jak prio_part). C = 1 - jest blok z priorytetem.
	tax
	lda PRIOCOLM,x
	sta zm_t0
	inx
	txa
	and #15
	tax
	lda PRIOCOLM,x
	ora zm_t0
	sta zm_t0
	inx
	txa
	and #15
	tax
	lda PRIOCOLM,x
	ora zm_t0
	sta zm_t0
	lda v_by
	and #7
	tax
	lda zm_t0
	and hpn_rows,x
	cmp #1
	rts
; wiersze pierscienia (by, by + 1, by + 5, by + 6) & 7 dla by & 7 = 0..7
hpn_rows	dta b($63, $C6, $8D, $1B, $36, $6C, $D8, $B1)

; obiekty HOB_* (x, y ekranu z +1 VDP; zrodlo w banku HUD_VRAM>>16) i prostokaty HR_* (tylko x, y, w)
HR_ICON      = 5
HR_RDIG      = 6
ho_x	dta b(16), b(20), b(20), b(24), b(112), b(20), b(40)
ho_y	dta b(172+1), b(0+1), b(0+1), b(16+1), b(56+1), b(0+1), b(0+1)
ho_w	dta b(32), b(36), b(36), b(32), b(32), b(16), b(16)
ho_h	dta b(16), b(32), b(16), b(16), b(16)
ho_lo	dta b(<HUD_LIVES_VRAM), b(<HUD_TOP_VRAM), b(<HUD_TOP_VRAM), b(<HUD_TIME_VRAM), b(<HUD_TIME_VRAM)
ho_mid	dta b([HUD_LIVES_VRAM>>8]&$FF), b([HUD_TOP_VRAM>>8]&$FF), b([HUD_TOP_VRAM>>8]&$FF)
	dta b([HUD_TIME_VRAM>>8]&$FF), b([HUD_TIME_VRAM>>8]&$FF)
ho_str	dta b(32), b(HUD_TOP_STR), b(HUD_TOP_STR), b(HUD_TOP_STR), b(HUD_TOP_STR)
