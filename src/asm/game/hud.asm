; =====================================================================
;  hud.asm - M3.7c: draw_HUD_sprites (00:2E5A-00:2E93) bez tablicy sprite'ow SMS
;
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): na poczatku draw_HUD_sprites (w rozgrzewce i ticku,
;  przed kamera i obiektami): res 7,(iy+7); tekst zyc (szablon 00:2E55: $A0 $A2 $A4 cyfra $FF, cyfra = $80 +
;  2 * min(zycia, 9)) w (16, 172); draw_HUD_rings (00:2EE6, gdy iy_05 b2): ikona $A6 $A8 w (20, 0) i 2 cyfry BCD
;  w (40, 0); draw_level_timer (00:2F1F, gdy iy_07 b5): minuty, $B0, 2 cyfry sekund w (24, 16) - w etapach
;  specjalnych (g_level >= $1C) w (112, 56). draw_sprite_text (00:35CC): kolejne znaki co 8 px, $FF - koniec.
;  Bufor g_HUD_FFstr_buf zostaje z ostatnim tekstem (stan RAM jak w oryginale - porownanie trace'u).
;  Renderer (render/hud.asm) dostaje migawke v_hud_*: wartosci z chwili rysowania HUD-u - przed logika Sonica,
;  wiec pierscienie i zycia zebrane / stracone w ticku pokaze dopiero nastepny tick (jak oryginal).
; =====================================================================
HUD_RINGS    = 1           ; v_hud_fl: b0 licznik pierscieni, b1 czas, b2 czas w pozycji etapu specjalnego
HUD_TIME     = 2
HUD_SPECIAL  = 4

draw_hud
	lda iy_07_lvflag02
	and #$7F                  ; res 7,(iy+7) (00:2E5A)
	sta iy_07_lvflag02
; M4.9a: pamiec HUD-u - w petli poziomu (krok >= 1) wpisy HUD-u leza zawsze od tego samego miejsca tablicy
; sprite'ow (wskaznik $D03F, licznik 21 z game/step.asm) i nic poza draw_hud ich nie zmienia miedzy tickami
; (obiekty pisza od v_spr_first, iskra za nimi). Gdy zycia, pierscienie, czas, flagi i poczatek tablicy sa jak
; w poprzednim ticku (klucz v_hudk), wpisy, bufor g_HUD_FFstr_buf i migawka v_hud_* juz maja wlasciwa tresc:
; zostaja tylko wskaznik, licznik i v_spr_first (stan RAM identyczny - porownanie trace'u). Rozgrzewka
; (krok <= 0: tablica pisana od wskaznika poprzedniej ramki, czyszczona przy starcie poziomu) uniewaznia pamiec.
	ldx g_next_avail_vdp_sprite_ptr
	lda v_step+1
	bmi dh_nokey
	ora v_step
	beq dh_nokey
	lda v_hudk_ok
	beq dh_key
	lda g_lives
	cmp v_hudk
	bne dh_key
	lda g_rings_BCD
	cmp v_hudk+1
	bne dh_key
	lda iy_05_lvflag00
	and #$04
	cmp v_hudk+2
	bne dh_key
	lda g_time_mins
	cmp v_hudk+3
	bne dh_key
	lda g_time_secs_BCD
	cmp v_hudk+4
	bne dh_key
	lda iy_07_lvflag02
	and #$20
	cmp v_hudk+5
	bne dh_key
	lda g_level
	cmp v_hudk+6
	bne dh_key
	cpx v_hudk+7              ; poczatek wpisow HUD-u (mlodszy bajt wskaznika)
	bne dh_key
	lda g_sprite_count
	cmp v_hudk+8
	bne dh_key
	lda v_hudk_end            ; ten sam HUD: tylko wskaznik, licznik i pierwszy wpis obiektow
	sta g_next_avail_vdp_sprite_ptr
	lda v_hudk_cnt
	sta g_sprite_count
	sta v_spr_first
	rts
dh_nokey
	lda #0                    ; rozgrzewka: pamiec niewazna (zapis klucza pominiety)
	sta v_hudk_ok
	beq dh_full               ; zawsze
dh_key                          ; klucz pamieci = stan przy wejsciu (pamiec wazna po zapisie konca w dh_ret)
	lda g_lives
	sta v_hudk
	lda g_rings_BCD
	sta v_hudk+1
	lda iy_05_lvflag00
	and #$04
	sta v_hudk+2
	lda g_time_mins
	sta v_hudk+3
	lda g_time_secs_BCD
	sta v_hudk+4
	lda iy_07_lvflag02
	and #$20
	sta v_hudk+5
	lda g_level
	sta v_hudk+6
	stx v_hudk+7
	lda g_sprite_count
	sta v_hudk+8
	lda #1
	sta v_hudk_ok
dh_full
	lda #$A0                  ; ldir szablonu zyc (00:2E5E)
	sta g_HUD_FFstr_buf
	lda #$A2
	sta g_HUD_FFstr_buf+1
	lda #$A4
	sta g_HUD_FFstr_buf+2
	lda g_lives
	cmp #9
	bcc dh_lives
	lda #9
dh_lives
	asl                       ; C = 0 (A <= 9)
	adc #$80
	sta g_HUD_FFstr_buf+3
	sta v_hud_l
	lda #$FF
	sta g_HUD_FFstr_buf+4
	lda #0
	sta v_hud_fl
	ldx g_next_avail_vdp_sprite_ptr ; M4.1: sprite'y HUD-u od wskaznika tablicy (draw_sprite_text 00:35CC)
	lda #$10                  ; zycia w (16, 172) (00:2E78)
	ldy #$AC
	jsr dh_text_buf
; pierscienie: draw_HUD_rings (00:2EE6)
	lda iy_05_lvflag00
	and #$04
	beq dh_norings
	lda g_rings_BCD
	sta v_hud_r
	lsr
	lsr
	lsr
	lsr
	asl
	adc #$80
	sta g_HUD_FFstr_buf
	lda g_rings_BCD
	and #$0F
	asl
	adc #$80
	sta g_HUD_FFstr_buf+1
	lda #$FF
	sta g_HUD_FFstr_buf+2
	lda #HUD_RINGS
	sta v_hud_fl
	mwa #dh_ring_icon zg_src  ; ikona pierscienia FFstr_ring (00:2E52) w (20, 0)
	lda #$14
	ldy #0
	jsr dh_text
	lda #$28                  ; 2 cyfry w (40, 0)
	ldy #0
	jsr dh_text_buf
dh_norings
; czas: draw_level_timer (00:2F1F)
	lda iy_07_lvflag02
	and #$20
	beq dh_ret
	lda g_time_mins
	sta v_hud_m
	and #$0F
	asl
	adc #$80
	sta g_HUD_FFstr_buf
	lda #$B0
	sta g_HUD_FFstr_buf+1
	lda g_time_secs_BCD
	sta v_hud_s
	lsr
	lsr
	lsr
	lsr
	asl
	adc #$80
	sta g_HUD_FFstr_buf+2
	lda g_time_secs_BCD
	and #$0F
	asl
	adc #$80
	sta g_HUD_FFstr_buf+3
	lda #$FF
	sta g_HUD_FFstr_buf+4
	lda v_hud_fl
	ora #HUD_TIME
	sta v_hud_fl
	lda g_level
	cmp #$1C
	bcc dh_timenorm
	lda v_hud_fl
	ora #HUD_SPECIAL
	sta v_hud_fl
	lda #$70                  ; etap specjalny: (112, 56) (00:2F55)
	ldy #$38
	bne dh_timetxt
dh_timenorm
	lda #$18                  ; czas w (24, 16) (00:2F4A)
	ldy #$10
dh_timetxt
	jsr dh_text_buf
dh_ret
	stx g_next_avail_vdp_sprite_ptr
	stx v_hudk_end            ; M4.9a: koniec wpisow HUD-u i licznik do pamieci HUD-u
	lda g_sprite_count        ; M4.2: wpisy obiektow od tego indeksu (render/objspr.asm)
	sta v_spr_first
	sta v_hudk_cnt
	rts

; dh_text_buf / dh_text: draw_sprite_text (00:35CC) - napis g_HUD_FFstr_buf / (zg_src) od x = A, y = Y:
; kolejne znaki co 8 px, $FE pomija pozycje, $FF konczy; wpis (x, y, kafel) pod mlodszym bajtem wskaznika X
; (inc l: zawija w stronie $D0 tablicy sprite'ow), g_sprite_count + 1. Zwraca X = nastepny wpis.
dh_text_buf
	pha
	lda #<g_HUD_FFstr_buf
	sta zg_src
	lda #>g_HUD_FFstr_buf
	sta zg_src+1
	pla
dh_text
	sta v_hts_x
	sty v_hts_y
	ldy #0
dht_l
	lda (zg_src),y
	cmp #$FF
	beq dht_ret
	cmp #$FE
	beq dht_skip
	pha
	lda v_hts_x
	sta SPRTAB,x
	inx
	lda v_hts_y
	sta SPRTAB,x
	inx
	pla
	sta SPRTAB,x
	inx
	inc g_sprite_count
dht_skip
	lda v_hts_x
	clc
	adc #8
	sta v_hts_x
	iny
	bne dht_l
dht_ret
	rts

dh_ring_icon	dta b($A6,$A8,$FF)   ; FFstr_ring (00:2E52)
