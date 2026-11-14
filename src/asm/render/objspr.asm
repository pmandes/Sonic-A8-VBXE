; =====================================================================
;  objspr.asm - M4.2: sprite'y obiektow z tablicy sprite'ow SMS w liscie ramki; M4.9a: rodzaj BCB slotu
;  (SKIND_RAM) i szybka sciezka dla sprite'a w calosci na ekranie.
;
;  Logika (obj/dispatch.asm: draw_sprite_string 00:350F, draw_sprite 00:3581) wpisuje sprite'y obiektow do
;  tablicy SMS w lustrze RAM (wpisy za HUD-em: od v_spr_first do g_sprite_count - 1) i zapamietuje grupy
;  wpisow jednego wywolania (v_grp_s / v_grp_e: mlodsze bajty wskaznika na poczatku i koncu). Renderer:
;   - kazdy wpis (x, y, kafel) = sprite 8x16 z kafli kafel, kafel + 1 (SPRATLAS_VRAM, 128 B ciagiem) na linii
;     y + 1 (VDP; y >= $F0 - czesciowo nad ekranem), x w 0..255 (przyciecie do 256); kafle $B4-$BF (M4.3) -
;     wycinki obrazu biezacej klatki Sonica (rozsypane pierscienie $55);
;   - kolejnosc: nizszy indeks na wierzchu = blit pozniej, wiec od ostatniego wpisu; obszar slotow SLOT_SPR
;     (N_SPR_SLOTS) lezy miedzy widokiem a HUD-em: obiekty pod HUD-em i Sonikiem (wpisy 12-20 i 21+ HUD-u
;     maja nizsze indeksy). Sloty sa kolejne, wiec zp_bcb biegnie po nich (+ BCB_BYTES), bez slot_ptr;
;   - M4.9a: SKIND_RAM[v_sk] = rodzaj BCB w slocie (K_NOPA, K_SPRA, K_SPRC, K_NOPS, K_SPRS - render/vram.inc):
;     pola stale rodziny (krok Y zrodla 8 / 24, krok X, src hi atlasu, krok Y celu 256, maski, stencil + NEXT)
;     pisane tylko przy zmianie rodziny, szerokosc / wysokosc 8x16 tylko przy wejsciu w K_SPRA; sprite w calosci
;     na ekranie (y < 176, x <= 248, kafel z atlasu) pisze 5 bajtow (zrodlo lo / mid, cel) bez clip_rows;
;   - sloty obszaru nieuzyte w tej liscie, a uzyte w poprzedniej liscie tego kompletu, dostaja pusty BCB:
;     zrodlo ZERO_VRAM (bajt 0 - stencil nic nie rysuje), rozmiar 1x1, reszta pol zostaje (lancuch BCB ciagly,
;     rodzina slotu zachowana w K_NOPA / K_NOPS);
;   - priorytet tla: obwiednia kazdej grupy (przycieta do ekranu) w kawalkach <= 32x32 -> or_* (prio_rect);
;     grp_rects wolane po HUD-zie i Soniku (hud_objs zaczyna liste prostokatow od nowa) i tylko wtedy, gdy
;     okno kamery ma blok z priorytetem (PRIOWIN_RAM, render/sprites.asm).
;  obj_sprites wolane w obj_bcbs przed HUD-em (zp_last = ostatni BCB sprite'a, gdy jakis powstal). Niezmiennik:
;  sloty sprite'ow nigdy nie koncza listy (pole sterowania $09 z NEXT nie jest juz przepisywane) - zaraz po nich
;  hud_objs zawsze emituje HUD (zycia), wiec build_frame_list zdejmuje NEXT dalej.
;  Wpisy tylko w petli poziomu (krok >= 1): w rozgrzewce ekran SMS jest wylaczony (00:20CB), a HUD dopisuje sie
;  za wskaznikiem z poprzedniej ramki (indeksy wpisow nie odpowiadaja polozeniu w tablicy).
;  Limitu 8 sprite'ow w linii VDP port nie emuluje (docs/plan-m4.md 3.5).
; =====================================================================
SPRTAB_R     = $D000+SMS_RAM ; g_sprite_table w lustrze
; zalozenia kodu (M4.9a): K_NOPA = 0 (skok beq po lda #K_NOPA); pusty slot rodziny atlasu zostawia src hi
; z ZERO_VRAM, wiec musi byc rowny SPRATLAS_VRAM >> 16; zrodlo atlasu liczone bez bajtu lo i bez przeniesienia do hi
	.if K_NOPA <> 0
	.error "objspr: K_NOPA musi byc 0 (beq osp_nk)"
	.endif
	.if ZERO_VRAM>>16 <> SPRATLAS_VRAM>>16
	.error "objspr: ZERO_VRAM i SPRATLAS_VRAM musza miec ten sam starszy bajt (K_NOPA -> K_SPRA bez zapisu src hi)"
	.endif
	.if [SPRATLAS_VRAM&$FF] <> 0 .or [[SPRATLAS_VRAM>>8]&$FF]+$40 > $FF
	.error "objspr: SPRATLAS_VRAM - bajt lo 0 i kafel * 64 bez przeniesienia do bajtu hi"
	.endif

; M7.5 Z3 (docs/plan-m7-ntsc.md 2 Z3): petla wpisow odchudzona - gorace zmienne w ZP (v_ox, v_tile, v_sy16, v_fbm, v_fbh, v_sk,
; v_sj, v_skend - kernel/mem.inc), slot liczony tylko indeksem SKIND (v_sk; v_sslot usuniety: slot = SLOT_SPR + v_sk - set_skind),
; test wolnego slotu jednym cpy v_skend (Y = v_sk zostaje indeksem SKIND_RAM), spr_next w linii, rodzaj slotu z Y (bez stx/ldx v_sj3).
; Szybka sciezka ok. 160 cykli na wpis (bylo ok. 211). Wynik (bajty BCB w slotach, kolejnosc, rodzaje SKIND, v_spr_used, v_spr_drop)
; bez zmian.
obj_sprites
	ldx v_lbuild
	lda set_skind,x
	sta v_sk                  ; indeks SKIND_RAM slotu SLOT_SPR w komplecie
	clc
	adc #N_SPR_SLOTS
	sta v_skend               ; Z3: v_sk >= v_skend - brak slotu
	ldx #SLOT_SPR
	jsr slot_ptr              ; zp_bcb = slot SLOT_SPR kompletu (dalej + BCB_BYTES na slot)
	lda v_step+1              ; rozgrzewka (krok <= 0): bez sprite'ow obiektow
	jmi osp_nop
	ora v_step
	jeq osp_nop
	lda g_sprite_count
	cmp #65
	bcc osp_n
	lda #64
osp_n
	sta v_tmp                 ; n = min(licznik, 64)
	sec
	sbc v_spr_first
	jeq osp_nop               ; bez wpisow obiektow
	jcc osp_nop
	sta v_sj                  ; liczba wpisow obiektow (do zrobienia)
	lda v_tmp
	asl
	adc v_tmp                 ; 3 n (C = 0 po asl: n <= 64)
	tax
osp_l                           ; X = 3 (j + 1): wpis j, od ostatniego (nizszy indeks na wierzchu = blit pozniej)
	dex
	dex
	dex
	ldy v_sk                  ; Y = indeks SKIND_RAM slotu (Z3: zostaje do testu rodzaju)
	cpy v_skend
	jcs osp_full
	lda SPRTAB_R+1,x          ; y SMS (gora = y + 1)
	cmp #176
	bcs osp_slow              ; y >= 176: dol poza ekranem albo nad ekranem (>= $F0) -> przyciecie
	sta v_sy16
	lda SPRTAB_R,x
	cmp #249
	bcs osp_slow              ; x > 248: przyciety z prawej
	sta v_ox
	lda SPRTAB_R+2,x
	cmp #$B4
	bcc osp_fast
	cmp #$C0
	bcc osp_slow              ; kafle $B4-$BF: wycinek klatki Sonica (spe_sonic)
osp_fast                        ; sprite z atlasu w calosci na ekranie -> K_SPRA (pola stale juz w slocie)
	sta v_tile
	lda SKIND_RAM,y
	cmp #K_SPRA
	bne osp_kind
osp_fv
	lda v_tile                ; src = SPRATLAS + kafel * 64: lo = (kafel & 3) << 6, mid = >SPRATLAS + kafel / 4
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
	adc #>[SPRATLAS_VRAM&$FFFF] ; kafel / 4 < 64: bez przeniesienia (src hi stale)
	iny
	sta (zp_bcb),y
	ldy #6                    ; dst = bufor + (y + 1) * 256 + x
	lda v_ox
	sta (zp_bcb),y
	lda v_sy16
	sec
	adc v_fbm                 ; + y + 1 (C)
	iny
	sta (zp_bcb),y
	lda v_fbh
	adc #0
	iny
	sta (zp_bcb),y
	inc v_sk                  ; Z3: spr_next w linii - nastepny slot (indeks SKIND i zp_bcb + BCB_BYTES)
	lda zp_bcb
	clc
	adc #BCB_BYTES
	sta zp_bcb
	bcc osp_cont
	inc zp_bcb+1
osp_cont
	dec v_sj
	bne osp_l
	beq osp_nop               ; zawsze
osp_kind                        ; slot innego rodzaju -> K_SPRA: pola rodziny atlasu (gdy slot mial rodzine Sonica) i rozmiar 8x16
	stx v_sj3                 ; X = 3 j (spk_atlas: X = indeks SKIND)
	ldx v_sk
	ldy #K_SPRA
	jsr spk_atlas
	ldy #12
	lda #7
	sta (zp_bcb),y            ; szerokosc 8 (bajt hi stale 0)
	ldy #14
	lda #15
	sta (zp_bcb),y            ; wysokosc 16
	ldx v_sj3
	jmp osp_fv
osp_slow                        ; przyciecie albo wycinek klatki Sonica: spr_entry (v_ox, v_sy16 ze znakiem, v_tile)
	lda SPRTAB_R,x
	sta v_ox
	lda SPRTAB_R+2,x
	sta v_tile
	ldy #0
	lda SPRTAB_R+1,x
	sta v_sy16
	cmp #$F0
	bcc osp_y
	dey                       ; y >= $F0: nad ekranem (y - 256)
osp_y
	sty v_sy16+1
	stx v_sj3
	jsr spr_entry
	ldx v_sj3
	jmp osp_cont
osp_full                        ; brak slotow: pozostale (najnizsze) wpisy pominiete
	lda v_sj
	clc
	adc v_spr_drop
	sta v_spr_drop
osp_nop                         ; zp_last = ostatni slot sprite'a; sloty do konca uzytych w poprzedniej liscie -> puste
	ldx v_lbuild
	lda v_sk
	cmp set_skind,x
	beq osp_used              ; bez sprite'ow: zp_last bez zmian (widok)
	sec
	lda zp_bcb
	sbc #BCB_BYTES
	sta zp_last
	lda zp_bcb+1
	sbc #0
	sta zp_last+1
osp_used                        ; M7.5: v_spr_used = koniec uzytych slotow jako indeks SKIND (v_sk) - komplet ma wlasna baze
	lda v_sk
	ldy v_spr_used,x
	sta v_spr_used,x
	sty v_sj                  ; koniec slotow uzytych w poprzedniej liscie kompletu
osp_nl
	ldx v_sk
	cpx v_sj
	bcs osp_ret
	lda SKIND_RAM,x
	cmp #K_SPRS
	beq osp_ns                ; rodzina klatki Sonica -> K_NOPS
	cmp #K_NOPS
	beq osp_nn                ; juz pusty
	cmp #K_NOPA
	beq osp_nn
	lda #K_NOPA               ; K_SPRA / K_SPRC -> K_NOPA
	beq osp_nk                ; zawsze (K_NOPA = 0: Z = 1 po lda - asercja nizej)
osp_ns
	lda #K_NOPS
osp_nk
	sta SKIND_RAM,x
	ldy #0                    ; zrodlo = bajt 0 (stencil nic nie rysuje), rozmiar 1x1; cel zostaje
	lda #<ZERO_VRAM
	sta (zp_bcb),y
	iny
	lda #>[ZERO_VRAM&$FFFF]
	sta (zp_bcb),y
	iny
	lda #ZERO_VRAM>>16
	sta (zp_bcb),y
	lda #0
	ldy #12
	sta (zp_bcb),y
	ldy #14
	sta (zp_bcb),y
osp_nn
	jsr spr_next
	jmp osp_nl
osp_ret
	rts

; spr_next: nastepny slot obszaru sprite'ow (v_sk, zp_bcb += BCB_BYTES). Zachowuje X, Y. M7.5: bez v_sslot (slot z v_sk).
spr_next
	inc v_sk
	clc
	lda zp_bcb
	adc #BCB_BYTES
	sta zp_bcb
	bcc spn_ret
	inc zp_bcb+1
spn_ret
	rts

; spk_atlas: slot v_sk (X) dostaje rodzaj Y z rodziny atlasu; gdy mial rodzine klatki Sonica - pola rodziny
; (src hi, krok Y zrodla 8, krok X 1). Zachowuje X.
spk_atlas
	lda SKIND_RAM,x
	cmp #K_NOPS
	bcc spk_set
	tya
	pha
	ldy #2
	lda #SPRATLAS_VRAM>>16
	sta (zp_bcb),y
	iny
	lda #8
	sta (zp_bcb),y
	ldy #5
	lda #1
	sta (zp_bcb),y
	pla
	tay
spk_set
	tya
	sta SKIND_RAM,x
	rts

; spr_entry: wpis (v_ox = x ekranu 0..255, v_sy16 = y SMS ze znakiem, v_tile) przyciety do ekranu albo wycinek
; klatki Sonica -> BCB w slocie v_sk (gdy widoczny) i nastepny slot; wolny slot sprawdza obj_sprites.
; Kafle $B4-$BF (M4.3): grafika biezacej klatki Sonica - IRQ (update_sonic_3bpp_sprite 00:37E0) laduje ja do
; kafli $B4-$BF, mapa SPRITEMAP_sonic_normal to 3 x 2 sprite'y 8x16. Rozsypane pierscienie $55 w ticku
; z g_sonic_sprite_index_override (klatka $1C/$1D w lewo, Sonic bez mapy) rysuja wycinki tej klatki: sprite
; m = (kafel - $B4) / 2 = kolumna m mod 3, wiersz m div 3 obrazu klatki (SONICFR_RAM, jak sonic_obj).
spr_entry
	lda v_tile
	cmp #$B4
	bcc spe_atlas
	cmp #$C0
	jcc spe_sonic
spe_atlas                       ; sprite z atlasu przyciety -> K_SPRC (szerokosc i wysokosc zmienne)
	lda #16
	jsr clip_rows             ; gora = y + 1, przyciecie do 0..191 (C = 1: poza ekranem)
	bcs spe_ret
	jsr spe_width
	ldx v_sk
	lda SKIND_RAM,x
	cmp #K_SPRC
	beq spe_cv
	ldy #K_SPRC
	jsr spk_atlas
spe_cv                          ; src = SPRATLAS + kafel * 64 + skip * 8 (< $7C800: src hi stale)
	lda v_tile
	lsr
	lsr
	sta zp_t1                 ; kafel / 4
	lda v_skip
	asl
	asl
	asl
	sta zp_t0                 ; skip * 8 (< 128)
	lda v_tile
	and #3
	lsr
	ror
	ror                       ; (kafel & 3) << 6
	clc
	adc zp_t0
	ldy #0
	sta (zp_bcb),y            ; src lo
	lda zp_t1
	adc #>[SPRATLAS_VRAM&$FFFF]
	iny
	sta (zp_bcb),y            ; src mid (+ przeniesienie z lo)
	jsr spe_dst
	jmp spr_next
spe_ret
	rts
spe_width                       ; v_ow = min(8, 256 - x)
	lda #0
	sec
	sbc v_ox
	beq spw_8                 ; x = 0
	cmp #8
	bcc spw_w
spw_8
	lda #8
spw_w
	sta v_ow
	rts
spe_dst                         ; cel (v_ox, v_oy) w buforze, szerokosc v_ow, wysokosc v_oh
	ldy #6
	lda v_ox
	sta (zp_bcb),y
	lda v_oy
	clc
	adc v_fbm
	iny
	sta (zp_bcb),y
	lda v_fbh
	adc #0
	iny
	sta (zp_bcb),y
	ldy #12
	lda v_ow
	sec
	sbc #1
	sta (zp_bcb),y            ; szerokosc - 1 (bajt hi stale 0)
	ldy #14
	lda v_oh
	sec
	sbc #1
	sta (zp_bcb),y            ; wysokosc - 1
	rts
spe_sonic                       ; obraz klatki: SONICFR_RAM[kierunek * 42 + klatka] (mid, hi | $80 = odbicie)
	lda v_sonic_fr
	cmp #LV_SONIC_FR
	jcs spe_todo              ; klatka spoza grafiki Sonica
	lda #16
	jsr clip_rows
	jcs spe_ret
	jsr spe_width
	lda v_sonic_fr
	ldx v_sonic_base
	cpx #$70
	bne spe_sr
	clc                       ; w lewo (cpx ustawil C)
	adc #LV_SONIC_FR
spe_sr
	asl
	tax
	lda SONICFR_RAM,x
	sta v_osrc+1
	lda SONICFR_RAM+1,x
	sta v_tmp
	lda v_tile                ; m = (kafel - $B4) / 2: wiersz (0 / 16 linii) i kolumna (8 px)
	sec
	sbc #$B4
	lsr
	ldx #0
	cmp #3
	bcc spe_r0
	sbc #3
	ldx #16
spe_r0
	asl
	asl
	asl                       ; 8 * kolumna
	ldy #1
	bit v_tmp
	bpl spe_nf
	sta zp_t0                 ; odbicie: od prawej krawedzi kolumny (23 - 8 * kolumna), krok X -1
	lda #23
	sec
	sbc zp_t0
	ldy #$FF
spe_nf
	sty v_ostepx
	sta v_osrc                ; przesuniecie X w obrazie (< 24; obraz ma mlodszy bajt 0)
	txa                       ; linie = wiersz + skip (< 32) -> linie * 24 (< 768)
	clc
	adc v_skip
	asl
	asl
	asl
	sta zp_t1                 ; linie * 8
	asl
	sta zp_t2                 ; linie * 16 (mlodszy)
	lda #0
	rol
	sta zp_t3                 ; linie * 16 (starszy)
	clc
	lda zp_t2
	adc zp_t1
	sta zp_t2
	lda zp_t3
	adc #0
	sta zp_t3                 ; linie * 24
	clc
	lda zp_t2
	adc v_osrc
	sta v_osrc
	lda zp_t3
	adc v_osrc+1
	sta v_osrc+1
	lda v_tmp
	and #$07
	adc #0
	sta v_osrc+2
	ldx v_sk                  ; rodzaj K_SPRS: krok Y zrodla 24 tylko przy zmianie rodziny
	lda SKIND_RAM,x
	cmp #K_SPRS
	beq spe_sv
	cmp #K_NOPS
	beq spe_sk
	ldy #3
	lda #24                   ; krok Y zrodla = szerokosc obrazu klatki
	sta (zp_bcb),y
spe_sk
	lda #K_SPRS
	sta SKIND_RAM,x
spe_sv
	ldy #0
	lda v_osrc
	sta (zp_bcb),y
	iny
	lda v_osrc+1
	sta (zp_bcb),y
	iny
	lda v_osrc+2
	sta (zp_bcb),y
	ldy #5
	lda v_ostepx
	sta (zp_bcb),y
	jsr spe_dst
	jmp spr_next
spe_todo
	inc v_spr_todo
	rts

; grp_rects: obwiednie grup wpisow (v_grp_s/e: mlodsze bajty wskaznika, krok 3) -> prostokaty or_* (<= 32x32)
grp_rects
	ldx #0
gr_l
	cpx v_ngrp
	bcc gr_go
	rts
gr_go
	stx v_gi
	lda #$FF                  ; x0, y0 (gora z +1 VDP, ze znakiem 16 bit), x1, y1 (wylacznie)
	sta v_gx0
	sta v_gy0
	lda #$7F
	sta v_gy0+1
	lda #0
	sta v_gx1
	sta v_gx1+1
	sta v_gy1
	lda #$80
	sta v_gy1+1
	lda v_grp_e,x
	sta v_gend
	lda v_grp_s,x
	tay
gr_e
	cpy v_gend
	jeq gr_box
	lda SPRTAB_R,y            ; x
	cmp v_gx0
	bcs gr_x0
	sta v_gx0
gr_x0
	clc
	adc #8
	sta zp_t0
	lda #0
	adc #0
	sta zp_t1                 ; x + 8 (16 bit)
	cmp v_gx1+1
	bcc gr_x1n
	bne gr_x1
	lda zp_t0
	cmp v_gx1
	bcc gr_x1n
gr_x1
	lda zp_t0
	sta v_gx1
	lda zp_t1
	sta v_gx1+1
gr_x1n
	lda SPRTAB_R+1,y          ; gora = y + 1 (y >= $F0: y + 1 - 256)
	clc
	adc #1
	sta zp_t0
	lda #0
	sta zp_t1
	lda SPRTAB_R+1,y
	cmp #$F0
	bcc gr_yp
	lda #$FF
	sta zp_t1
gr_yp
	lda zp_t1                 ; gora < y0 (ze znakiem)?
	eor #$80
	sta zp_t2
	lda v_gy0+1
	eor #$80
	cmp zp_t2
	bcc gr_y0n
	bne gr_y0
	lda zp_t0
	cmp v_gy0
	bcs gr_y0n
gr_y0
	lda zp_t0
	sta v_gy0
	lda zp_t1
	sta v_gy0+1
gr_y0n
	clc                       ; dol = gora + 16 > y1?
	lda zp_t0
	adc #16
	sta zp_t0
	lda zp_t1
	adc #0
	sta zp_t1
	eor #$80
	sta zp_t2
	lda v_gy1+1
	eor #$80
	cmp zp_t2
	bcc gr_y1
	bne gr_y1n
	lda v_gy1
	cmp zp_t0
	bcs gr_y1n
gr_y1
	lda zp_t0
	sta v_gy1
	lda zp_t1
	sta v_gy1+1
gr_y1n
	iny
	iny
	iny
	jmp gr_e
gr_box                          ; przyciecie: y0 = max(y0, 0), y1 = min(y1, 192), x1 = min(x1, 256)
	ldx v_gi
	lda v_gy0+1
	bpl gr_y0ok
	lda #0
	sta v_gy0
	sta v_gy0+1
gr_y0ok
	lda v_gy1+1
	bmi gr_next               ; caly nad ekranem
	bne gr_y1c
	lda v_gy1
	cmp #192
	bcc gr_y1ok
gr_y1c
	lda #192
	sta v_gy1
gr_y1ok
	lda v_gy0+1
	bne gr_next
	lda v_gy0
	cmp v_gy1
	bcs gr_next               ; pusty
	lda v_gx1+1
	beq gr_x1ok
	lda #0                    ; x1 = 256 -> szerokosc 256 - x0 (8-bitowo: 0 - x0)
	sta v_gx1
gr_x1ok
	jsr gr_split
gr_next
	ldx v_gi
	inx
	jmp gr_l

; gr_split: prostokat (v_gx0..v_gx1 (0 = 256), v_gy0..v_gy1) w kawalkach <= 32x32 -> or_* (do N_RECTS)
gr_split
	lda v_gy0
	sta v_gcy
gs_row
	lda v_gx0
	sta v_gcx
gs_col
	ldx v_nobj
	cpx #N_RECTS
	bcs gs_ret
	lda v_gcx
	sta or_x,x
	lda v_gx1                 ; w = min(x1 - cx, 32) (x1 = 0 oznacza 256)
	sec
	sbc v_gcx
	beq gs_w32
	cmp #32
	bcc gs_w
gs_w32
	lda #32
gs_w
	sta or_w,x
	lda v_gcy
	sta or_y,x
	lda v_gy1
	sec
	sbc v_gcy
	cmp #32
	bcc gs_h
	lda #32
gs_h
	sta or_h,x
	inc v_nobj
	lda or_w,x                ; nastepna kolumna: cx += w, az do x1
	clc
	adc v_gcx
	sta v_gcx
	bcs gs_rown               ; przekroczone 255 (x1 = 256)
	cmp v_gx1
	bne gs_col
gs_rown
	lda or_h,x
	clc
	adc v_gcy
	sta v_gcy
	cmp v_gy1
	bcc gs_row
gs_ret
	rts
