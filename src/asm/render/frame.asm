; =====================================================================
;  frame.asm - lista ramki renderera (M2, potok M3.1): doladowanie blokow do pierscienia tla,
;  widok 256x192 z pierscienia do bufora, obiekt (kulka, stencil), bloki z priorytetem nad obiektem.
;  Lista = N_SLOTS slotow BCB kompletu v_lbuild (N_BLK_SLOTS na bloki i pierscienie, 4 widok, kulka,
;  4 priorytet); sloty blokow wypelniane od konca: najpierw BCB pierscieni (render/rings.asm), potem lata
;  i doladowanie blokow - wykonanie od pierwszego uzytego slotu (ls_slot): bloki, pierscienie, widok.
;  Pierscien 512x256 w VRAM $20000 trzyma okno 9x7 blokow 32x32 wokol kamery (blok (c,r) w kolumnie
;  c & 15, wierszu r & 7); kamera przesuwa sie o <= 1 blok na tick, wiec doladowanie = 1 kolumna (7)
;  i/lub 1 wiersz (9) blokow; wiekszy skok -> full_reload (63 bloki osobna lista).
; =====================================================================
; build_list: lista ramki w komplecie v_lbuild dla biezacego stanu (kamera, kulka), cel = bufor v_tgt.
; Zapamietuje parametry listy (ls_*), zeby po jej wykonaniu wiedziec, co narysowano (v_d* w frame_done).
build_list
	jsr water_split           ; M6.8: linia podzialu wody tej listy (v_wk) - stan ticku listy
	ldx v_lbuild
	lda PM_OK,x               ; M7.5 Z1 / Z6 (render/prio.asm): pamiec BCB z poprzedniej listy tego kompletu wazna tylko, gdy ta lista
	sta PM_WAS                ; ja odnowila (sciezka blokowa priorytetu / Sonic z pamieci) - kazda inna sciezka zostawia PM_OK = 0
	lda SM_OK,x
	sta SM_WAS
	lda FM_OK,x               ; M7.5 Z5: seria fo_fast (pola stale sprite'ow przednich w slotach)
	sta FM_WAS
	lda PK_OK,x               ; M7.5 Z5: pola stale BCB blokow priorytetu w slotach
	sta PK_WAS
	lda #0
	sta PM_OK,x
	sta SM_OK,x
	sta FM_OK,x
	sta PK_OK,x
	lda set_kind,x            ; M4.2: komplet = baza adresu, okno MEMAC, baza KIND_RAM
	sta v_sbase
	lda set_cpu_lo,x
	sta v_lcpu
	lda set_cpu_hi,x
	sta v_lcpu+1
	lda set_mb,x
	sta v_mb_list
	jsr set_memac
	jsr build_frame_list
	jsr rchain_apply          ; M3.8b: wpisy lancucha pierscieni dla doladowanych blokow
	lda #MB_LOW               ; M4.2: domyslne okno poza budowa listy
	jsr set_memac
	ldx v_lbuild
	lda v_camx
	sta ls_camx_lo,x
	lda v_camx+1
	sta ls_camx_hi,x
	lda v_camy
	sta ls_camy_lo,x
	lda v_camy+1
	sta ls_camy_hi,x
	lda v_sx
	sta ls_sx,x
	lda v_sy
	sta ls_sy,x
	lda v_nblk
	sta ls_nblk,x
	lda v_tgt
	eor #1
	sta v_tgt                 ; nastepna lista rysuje do drugiego bufora (po flipie tej)
	rts

; drawn_params: parametry listy z kompletu X -> v_d* (stan narysowanej klatki)
drawn_params
	lda ls_camx_lo,x
	sta v_dcamx
	lda ls_camx_hi,x
	sta v_dcamx+1
	lda ls_camy_lo,x
	sta v_dcamy
	lda ls_camy_hi,x
	sta v_dcamy+1
	lda ls_sx,x
	sta v_dsx
	lda ls_sy,x
	sta v_dsy
	lda ls_nblk,x
	sta v_dnblk
	rts

; build_frame_list: lista dla kamery (v_camx, v_camy) i kulki (v_sx, v_sy) w komplecie v_lbuild.
; 1. blok kamery (v_bx, v_by) = kamera / 32; 2. delta wzgledem okna pierscienia (v_rbx, v_rby):
; |d| <= 1 -> BCB doladowania odslonietej kolumny i/lub wiersza, inaczej full_reload; 3. widok, kulka,
; priorytet; 4. zdjecie bitu NEXT z ostatniego BCB (zp_last).
build_frame_list
; blok kamery: v_bx = camx >> 5, v_by = camy >> 5 (16 bit -> 8 bit)
	lda v_camx+1
	sta zp_t0
	lda v_camx
	ldx #5
bfl_sx
	lsr zp_t0
	ror
	dex
	bne bfl_sx
	sta v_bx
	lda v_camy+1
	sta zp_t0
	lda v_camy
	ldx #5
bfl_sy
	lsr zp_t0
	ror
	dex
	bne bfl_sy
	sta v_by

	lda #N_BLK_SLOTS
	sta v_slot                ; sloty blokow wypelniane od konca (next_slot: v_slot--)
	lda #0
	sta v_nring
	sta v_full
	lda #$FF                  ; doladowana kolumna / wiersz ($FF = brak; bx <= 247, wiersz < 255)
	sta v_ld_col
	sta v_ld_row
	lda v_ring_ok
	beq bfl_full              ; pierscien jeszcze pusty (start poziomu) -> pelne przeladowanie
	lda v_bx
	sec
	sbc v_rbx
	sta zp_t2                 ; dx
	clc
	adc #1
	cmp #3
	bcs bfl_full
	lda v_by
	sec
	sbc v_rby
	sta zp_t3                 ; dy
	clc
	adc #1
	cmp #3                    ; dy + 1 w 0..2 <=> |dy| <= 1
	bcs bfl_full
; kolumna: dx > 0 -> nowa kolumna po prawej (bx + 8), dx < 0 -> po lewej (bx); 7 blokow w dol
	lda zp_t2
	beq bfl_rows
	bmi bfl_col_left
	lda v_bx
	clc
	adc #8
	bne bfl_col           ; zawsze (bx <= 247)
bfl_col_left
	lda v_bx
bfl_col
	sta v_ld_col
bfl_rows                        ; wiersz: dy > 0 -> nowy wiersz u dolu (by + 6), dy < 0 -> u gory; 9 blokow
	lda zp_t3
	beq bfl_emit
	bmi bfl_row_up
	lda v_by
	clc
	adc #6
	bne bfl_row
bfl_row_up
	lda v_by
bfl_row
	sta v_ld_row
	jmp bfl_emit
bfl_full
	jsr full_reload
	inc v_full
bfl_emit                        ; od konca slotow: pierscienie (wykonane ostatnie), lata, kolumna, wiersz
	jsr ring_bcbs
	jsr tov_evict             ; M4.7: nakladki (laty kafli) w slotach pierscienia doladowanych w tej liscie
	jsr tile_patch            ; M4.7: lata kafli (kwiaty) - wykonana po doladowaniu blokow
	lda v_full
	bne bfl_ring_done         ; pelne przeladowanie wzielo uklad z lata
	jsr patch_block_m         ; M7.5 Z4: lata pierscienia - bit priorytetu bloku od nowa (render/rings.asm patch_block)
	lda v_ld_col
	cmp #$FF
	beq bfl_e_row
	sta zp_c
	jsr eb_col7               ; M7.5 Z8: 7 blokow kolumny w linii (render/frame.asm eb_col7)
bfl_e_row
	lda v_ld_row
	cmp #$FF
	beq bfl_ring_done
	sta zp_r
	and #7                    ; M7.5 Z4: bit wiersza pierscienia w 9 kolumnach okna od nowa (emit_block ustawia bity blokow
	tax                       ; z priorytetem; blok (ld_col, ld_row) wyczyszczony po kolumnie - wiersz go emituje ponownie)
	lda bit_tab,x
	eor #$FF
	sta zm_t0
	ldx #8
bfl_rclr
	txa
	clc
	adc v_bx
	and #15
	tay
	lda PRIOCOLM,y
	and zm_t0
	sta PRIOCOLM,y
	dex
	bpl bfl_rclr
	jsr eb_row9               ; M7.5 Z8: 9 blokow wiersza w linii
bfl_ring_done                   ; okno pierscienia = blok kamery; v_nblk = liczba blitow blokow (bez pierscieni)
	jsr glass_store           ; M6.10: lata szyby SKY3 do slotu magazynu - emitowana ostatnia = wykonana przed blokami (patch_block)
	lda v_patch_on            ; M3.8c: uklad zmieniony (lata) albo pelne przeladowanie -> hud_prio_near od nowa
	ora v_full
	beq bfl_nokey
	lda #$FF
	sta zh_by
	lda #0                    ; M7.5 Z1: BCB priorytetu z pamieci obu kompletow nieaktualne (render/prio.asm)
	sta PM_WAS
	sta PM_OK
	sta PM_OK+1
bfl_nokey
	lda v_bx
	sta v_rbx
	lda v_by
	sta v_rby
	lda #1
	sta v_ring_ok
	lda #0
	sta v_patch_on            ; lata zuzyta (albo poza oknem - blok doladuje sie z ukladu)
	lda #N_BLK_SLOTS
	sec
	sbc v_slot
	sec
	sbc v_nring
	sta v_nblk
	cmp v_nblk_max
	bcc bfl_nm
	sta v_nblk_max
bfl_nm
	lda v_cam_mode            ; M3.7c: plotno HUD-u (znaki zmienione od ostatniej listy) - tryby gry
	cmp #CAM_FOLLOW
	bcc bfl_nohud
	jsr hud_canvas
bfl_nohud
	ldx v_lbuild
	lda v_slot
	sta ls_slot,x             ; pierwszy slot listy (start blittera)
	jsr view_rects
	ldx #SLOT_VIEW+3          ; ostatni BCB widoku (gdy brak obiektow na ekranie)
	jsr slot_ptr
	ldy #20                   ; kopia + NEXT: lista bez obiektow zdjela NEXT z tego slotu - przywrocic,
	lda #$08                  ; inaczej lancuch konczylby sie na widoku na stale
	sta (zp_bcb),y
	mwa zp_bcb zp_last
	jsr obj_bcbs              ; obiekty i priorytet tla (render/sprites.asm)
; ostatni BCB bez NEXT
	ldy #20
	lda (zp_last),y
	and #$07
	sta (zp_last),y
	rts

; ---------------------------------------------------------------------
; M4.7: laty kafli tla (kwiaty, apply_screen_tilemap_patch 00:38B0) w pierscieniu tla. Lata trwa w slocie
; pierscienia, dopoki blok nie zostanie doladowany (odpowiednik przepisania kolumny / wiersza tablicy nazw VDP
; przy przewijaniu - w porcie z dokladnoscia do bloku 32 px). v_tov: nakladki obecne w pierscieniu (model obrazu
; tools/m2_test.py rysuje je na widoku z ukladu); zalozenie: lata 16x16 w jednym bloku (kwiaty GHZ - pozycje co 32).
; ---------------------------------------------------------------------
; tov_evict: usuwa nakladki ze slotow pierscienia doladowanych w tej liscie: pelne przeladowanie - wszystkie;
; kolumna v_ld_col - slot kolumny (c & 15) w wierszach (by..by+6) & 7; wiersz v_ld_row - slot wiersza (r & 7)
; w kolumnach (bx..bx+8) & 15; lata pierscienia (patch_block, blok w oknie) - jej slot.
tov_evict
	lda v_tov+1               ; M7.5 Z8: bez nakladek (x hi = $FF we wszystkich 8) - nic do usuwania (strefy bez kwiatow: ok. 35 cykli
	and v_tov+9               ; zamiast ok. 200)
	and v_tov+17
	and v_tov+25
	and v_tov+33
	and v_tov+41
	and v_tov+49
	and v_tov+57
	cmp #$FF
	bne tve_go
	rts
tve_go
	ldx #0
tve_l
	lda v_tov+1,x
	cmp #$FF
	jeq tve_n
	lda v_full
	jne tve_del
	jsr tov_block             ; zp_t0 = kolumna bloku, zp_t1 = wiersz bloku nakladki X
	lda v_ld_col
	cmp #$FF
	beq tve_row
	eor zp_t0
	and #15
	bne tve_row
	lda zp_t1                 ; wiersz w oknie (by..by+6) mod 8: (r - by) & 7 != 7
	sec
	sbc v_by
	and #7
	cmp #7
	bne tve_del
tve_row
	lda v_ld_row
	cmp #$FF
	beq tve_pat
	eor zp_t1
	and #7
	bne tve_pat
	lda zp_t0                 ; kolumna (c - bx) & 15 <= 8
	sec
	sbc v_bx
	and #15
	cmp #9
	bcc tve_del
tve_pat
	lda v_patch_on
	beq tve_n
	lda v_patch_c
	sec
	sbc v_bx
	cmp #9
	bcs tve_n                 ; lata pierscienia poza oknem - patch_block jej nie blituje
	lda v_patch_r
	sec
	sbc v_by
	cmp #7
	bcs tve_n
	lda v_patch_c
	eor zp_t0
	and #15
	bne tve_n
	lda v_patch_r
	eor zp_t1
	and #7
	bne tve_n
tve_del
	lda #$FF
	sta v_tov+1,x
tve_n
	txa
	clc
	adc #8
	tax
	cpx #64
	jne tve_l
	rts
tov_block                       ; X = nakladka -> zp_t0 = x >> 5 (8 bitow), zp_t1 = y >> 5
	lda v_tov+1,x
	sta zp_t0
	lda v_tov,x
	asl
	rol zp_t0
	asl
	rol zp_t0
	asl
	rol zp_t0                 ; (hi << 3) | (lo >> 5)
	lda v_tov+3,x
	and #$0F                  ; M6.4: b4-7 = zrodlo kafli (v_tpa)
	sta zp_t1
	lda v_tov+2,x
	asl
	rol zp_t1
	asl
	rol zp_t1
	asl
	rol zp_t1
	rts

; tile_patch: lata v_tp_on (irq_tile_patch) - nakladka v_tov (ta sama pozycja zastapiona, inaczej wolna albo
; kolejna v_tov_n) i 4 BCB kafel 8x8 atlasu tla -> pierscien (blok laty w oknie 9x7 kamery listy).
tile_patch
	lda v_tp_on
	bne tpt_go
	rts
tpt_go
	lda #0
	sta v_tp_on
	lda v_tpx+1               ; blok laty w oknie pierscienia (bx..bx+8, by..by+6)
	sta zp_t0
	lda v_tpx
	asl
	rol zp_t0
	asl
	rol zp_t0
	asl
	rol zp_t0
	lda zp_t0
	sec
	sbc v_bx
	cmp #9
	jcs tpt_ret
	lda v_tpy+1
	sta zp_t1
	lda v_tpy
	asl
	rol zp_t1
	asl
	rol zp_t1
	asl
	rol zp_t1
	lda zp_t1
	sec
	sbc v_by
	cmp #7
	jcs tpt_ret
	ldx #0                    ; nakladka: ta sama pozycja albo pierwsza wolna
	ldy #$FF                  ; Y = pierwsza wolna
tpt_find
	lda v_tov+1,x
	cmp #$FF
	bne tpt_cmp
	cpy #$FF
	bne tpt_fn
	txa
	tay
	jmp tpt_fn
tpt_cmp
	cmp v_tpx+1
	bne tpt_fn
	lda v_tov,x
	cmp v_tpx
	bne tpt_fn
	lda v_tov+2,x
	cmp v_tpy
	bne tpt_fn
	lda v_tov+3,x
	and #$0F
	cmp v_tpy+1
	beq tpt_same
tpt_fn
	txa
	clc
	adc #8
	tax
	cpx #64
	bne tpt_find
	tya                       ; brak tej pozycji: wolna albo kolejna (8 pozycji po kolei)
	tax
	cpx #$FF
	bne tpt_put
	ldx v_tov_n
	txa
	clc
	adc #8
	and #63
	sta v_tov_n
	jmp tpt_put               ; zastapiony wpis ma inna pozycje - bez porownania kafli (tpt_same tylko z tpt_cmp)
tpt_same                       ; M4.9: ta sama pozycja z tymi samymi 4 kaflami co nakladka, ktora wciaz jest w pierscieniu
	lda v_tov+3,x             ; M6.4: i z tym samym zrodlem kafli (atlas tla / sprite'ow)
	lsr
	lsr
	lsr
	lsr
	cmp v_tpa
	bne tpt_put
	lda v_tov+4,x             ; (nakladka znika przy doladowaniu bloku - tov_evict) -> obraz juz ma te kafle: bez 4 BCB
	cmp v_tpt
	bne tpt_put
	lda v_tov+5,x
	cmp v_tpt+1
	bne tpt_put
	lda v_tov+6,x
	cmp v_tpt+2
	bne tpt_put
	lda v_tov+7,x
	cmp v_tpt+3
	jeq tpt_ret
tpt_put
	lda v_tpx
	sta v_tov,x
	lda v_tpx+1
	sta v_tov+1,x
	lda v_tpy
	sta v_tov+2,x
	lda v_tpa                 ; M6.4: b4-7 = zrodlo kafli
	asl
	asl
	asl
	asl
	ora v_tpy+1
	sta v_tov+3,x
	lda v_tpt
	sta v_tov+4,x
	lda v_tpt+1
	sta v_tov+5,x
	lda v_tpt+2
	sta v_tov+6,x
	lda v_tpt+3
	sta v_tov+7,x
	ldx #0                    ; 4 kafle: (x, y), (x + 8, y), (x, y + 8), (x + 8, y + 8)
tpt_k
	stx v_tmp
	jsr next_slot
	lda #K_OTHER              ; slot bloku z innym BCB - nastepny blok zapisze wszystkie pola
	sta KIND_RAM,y
	ldx v_tmp
	lda v_tpa                 ; M6.4: kafel z atlasu sprite'ow (kapsula GHZ3) albo tla
	and bit_tab,x
	bne tpt_sa
	lda v_tpt,x               ; zrodlo: ATLAS + kafel * 64 (krok Y 8)
	lsr
	lsr
	clc
	adc #>[ATLAS_VRAM&$FFFF]
	ldy #1
	sta (zp_bcb),y
	lda #ATLAS_VRAM>>16
	bne tpt_sb
tpt_sa
	lda v_tpt,x               ; zrodlo: SPRATLAS + kafel * 64 (krok Y 8)
	lsr
	lsr
	clc
	adc #>[SPRATLAS_VRAM&$FFFF]
	ldy #1
	sta (zp_bcb),y
	lda #SPRATLAS_VRAM>>16
tpt_sb
	pha
	lda v_tpt,x
	and #3
	lsr
	ror
	ror
	ldy #0
	sta (zp_bcb),y
	ldy #2
	pla
	sta (zp_bcb),y
	lda v_tmp                 ; cel: x + 8 (k & 1), y + 8 (k >> 1) -> pierscien (x mod 512, y mod 256)
	and #1
	asl
	asl
	asl
	clc
	adc v_tpx
	sta zp_t0
	lda v_tpx+1
	adc #0
	and #1
	sta zp_t1                 ; bit 8 x
	lda v_tmp
	and #2
	asl
	asl
	clc
	adc v_tpy
	sta zp_t2                 ; y mod 256
	ldy #6
	lda zp_t0
	sta (zp_bcb),y            ; dst lo = x & $FF
	iny
	lda zp_t2
	asl
	ora zp_t1
	sta (zp_bcb),y            ; dst mid = (y << 1) | x bit 8
	iny
	lda zp_t2
	and #$80
	asl
	rol
	clc
	adc #RING_VRAM>>16
	sta (zp_bcb),y            ; dst hi = pierscien + y bit 7
	iny
	lda #<512
	sta (zp_bcb),y
	iny
	lda #>512
	sta (zp_bcb),y            ; krok Y celu 512
	jsr t8_fix                ; M7.5: pola stale kafla 8x8 wspolne z glass_store (miejsce pod oknem)
	ldx v_tmp
	inx
	cpx #4
	jne tpt_k
tpt_ret
	rts

; t8_fix (M7.5 - wspolne dla tile_patch i glass_store, te same bajty BCB): pola stale BCB kafla 8x8 - krok Y zrodla 8, krok X zrodla
; i celu 1, 8 x 8, maska AND $FF, XOR / kolizje / zoom / wzorzec 0, kopia + NEXT (zrodlo, cel i krok Y celu pisze wolajacy)
t8_fix
	ldy #3
	lda #8
	sta (zp_bcb),y            ; krok Y zrodla 8
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda #1
	sta (zp_bcb),y            ; krok X 1
	ldy #11
	sta (zp_bcb),y            ; krok X celu 1
	iny
	lda #7
	sta (zp_bcb),y            ; szerokosc 8
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda #7
	sta (zp_bcb),y            ; wysokosc 8
	iny
	lda #$FF
	sta (zp_bcb),y            ; maska AND
	lda #0
	iny
	sta (zp_bcb),y            ; XOR
	iny
	sta (zp_bcb),y            ; kolizje
	iny
	sta (zp_bcb),y            ; zoom
	iny
	sta (zp_bcb),y            ; wzorzec
	iny
	lda #$08
	sta (zp_bcb),y            ; kopia + NEXT
	rts

; M7.5: prio_blocks (M6.10 - sciezka blokowa priorytetu: 63 odczyty ukladu i prostokaty bloku przez prio_rect) zastapione przez
; prio_path (render/prio.asm: mapa priorytetu okna PRIOCOLM, BCB blokow wprost, pamiec Z1).

; glass_store (M6.10): lata szyby bossa SKY3 (v_gp_on, game/rings.asm glass_req) - 4 BCB kafli 8x8 atlasu tla (v_gp_t) do slotu magazynu
; v_gp_slot: STORE + slot * 1024 + (ty + k >> 1) * 256 + (tx + k & 1) * 8 (krok Y 32 - jak build_store). Sloty listy od konca, wiec
; wywolywana po wszystkich blokach listy - blitter wykona ja przed nimi (blok laty z patch_block i priorytet maja juz nowe kafle).
glass_store
	lda v_gp_on
	bne gst_go
	rts
gst_go
	lda #0
	sta v_gp_on
	ldx #0
gst_k
	stx v_tmp
	jsr next_slot
	lda #K_OTHER              ; slot z innym BCB - nastepny blok zapisze wszystkie pola
	sta KIND_RAM,y
	ldx v_tmp
	lda v_gp_t,x              ; zrodlo: ATLAS + kafel * 64 (krok Y 8)
	and #3
	lsr
	ror
	ror
	ldy #0
	sta (zp_bcb),y
	lda v_gp_t,x
	lsr
	lsr
	clc
	adc #>[ATLAS_VRAM&$FFFF]
	iny
	sta (zp_bcb),y
	iny
	lda #ATLAS_VRAM>>16
	sta (zp_bcb),y
	lda v_tmp                 ; cel: kolumna kafla (tx + k & 1) * 8
	and #1
	clc
	adc v_gp_tx
	asl
	asl
	asl
	ldy #6
	sta (zp_bcb),y            ; dst lo
	lda v_tmp
	lsr
	clc
	adc v_gp_ty
	sta zp_t0                 ; wiersz kafla (ty + k >> 1) - po 256 B
	lda v_gp_slot
	and #63
	asl
	asl
	clc
	adc zp_t0
	iny
	sta (zp_bcb),y            ; dst mid = (slot & 63) * 4 + wiersz kafla
	lda v_gp_slot
	lsr
	lsr
	lsr
	lsr
	lsr
	lsr
	clc
	adc #STORE_VRAM>>16
	iny
	sta (zp_bcb),y            ; dst hi = STORE >> 16 + slot / 64
	iny
	lda #32
	sta (zp_bcb),y            ; krok Y celu 32
	iny
	lda #0
	sta (zp_bcb),y
	jsr t8_fix                ; M7.5: pola stale kafla 8x8 (wspolne z tile_patch)
	ldx v_tmp
	inx
	cpx #4
	jne gst_k
	rts

next_slot                       ; v_slot-- ; zp_bcb = slot kompletu v_lbuild, Y = indeks KIND_RAM (zachowuje X)
	dec v_slot
	ldy v_slot
	clc
	lda mul21_lo,y
	adc v_lcpu
	sta zp_bcb
	lda mul21_hi,y
	adc v_lcpu+1
	sta zp_bcb+1
	tya
	clc
	adc v_sbase
	tay
	rts

; emit_block_k: emit_block dla slotu listy (Y = indeks slotu z next_slot): pola stale tylko, gdy slot mial
; inny rodzaj BCB (KIND_RAM, M3.8c). Zachowuje X.
emit_block_k
	lda KIND_RAM,y
	cmp #K_BLOCK
	beq emit_block_var
	lda #K_BLOCK
	sta KIND_RAM,y

; emit_block: (zp_bcb) = BCB bloku layout[zp_r][zp_c] -> pierscien (zp_c&15, zp_r&7). Zachowuje X.
; M3.8b: zmiane maski pierscieni slotu dopisuje do kolejki lancucha pierscieni (rchain_apply po liscie).
; Ustawia tez krok zrodla i rozmiar 32x32 (slot mogl byc wczesniej BCB pierscienia 16x16) oraz krok Y celu
; 512 (M3.7c: slot mogl byc BCB znaku HUD-u z krokiem plotna).
; M7.5 Z8 (docs/plan-m7-ntsc.md 2 Z8): czesci zalezne od wiersza (eb_rowp: wiersz ukladu, cel mid / hi, slot pierscienia, bit
; priorytetu) i od kolumny (eb_colp) w osobnych procedurach - doladowanie kolumny / wiersza robia petle eb_col7 / eb_row9 (czesci
; wspolrzednej stalej raz); pelne przeladowanie i lata - jak dawniej oba (emit_block_var). Bajty BCB, KIND_RAM, RCMASK_RAM, kolejka
; lancucha i mapa priorytetu bez zmian.
emit_block
	jsr eb_const
emit_block_var                  ; pola zmienne: zrodlo (numer bloku), cel (slot pierscienia)
	jsr eb_colp
	jsr eb_rowp
eb_core                         ; (zp_bcb) = slot, zp_lay = wiersz ukladu, EB_* = czesci wiersza i kolumny
	ldy zp_c
	lda (zp_lay),y
	sta zp_k                  ; numer bloku (RINGMASK_RAM nizej)
	tay                       ; M6.9: slot magazynu s = BLKMAP_RAM[k] (tozsamosc do 184 blokow strefy; SBZ/SKY - tylko bloki aktu)
	lda PRIO_RAM,y            ; M7.5 Z4: blok z priorytetem -> bit mapy okna (bity wyzerowane przez wolajacego przed doladowaniem;
	beq eb_np                 ; wiersz >= v_lvh - EB_RB = 0, bez priorytetu jak prio_part)
	ldy EB_C15
	lda EB_RB
	ora PRIOCOLM,y
	sta PRIOCOLM,y
	ldy zp_k
eb_np
	lda BLKMAP_RAM,y
	sta zp_ks
	asl
	asl
	ldy #1
	sta (zp_bcb),y            ; src mid = (s<<2)&$FF
	lda zp_ks
	rol
	rol
	rol
	and #3
	clc
	adc #STORE_VRAM>>16
	iny
	sta (zp_bcb),y            ; src hi = 4 + s/64
	lda EB_CL
	ldy #6
	sta (zp_bcb),y            ; dst lo = (c&7)<<5
	lda EB_RM
	ora EB_CB
	iny
	sta (zp_bcb),y            ; dst mid = ((c>>3)&1) | ((r&3)<<6)
	lda EB_RH
	iny
	sta (zp_bcb),y            ; dst hi = 2 + ((r&7)>>2)
; M3.8b: maska pierscieni bloku dla slotu pierscienia tla - zmiana do kolejki lancucha (render/rchain.asm)
	ldy zp_k
	lda RINGMASK_RAM,y
	sta zp_t1
	lda EB_R16
	ora EB_C15
	tay                       ; slot (r & 7) * 16 + (c & 15)
	lda zp_t1
	cmp RCMASK_RAM,y
	beq eb_ret
	sta RCMASK_RAM,y
	tya
	ldy zr_q
	sta RCQ_RAM,y
	inc zr_q
eb_ret
	rts

eb_const                        ; pola stale BCB bloku (src lo 0, krok Y zrodla 32, krok Y celu 512, 32 x 32). Zachowuje X.
	ldy #0
	tya
	sta (zp_bcb),y            ; src lo = 0 (blok k pod STORE + k * 1024; slot mogl miec inny adres - HUD)
	ldy #9
	lda #<512
	sta (zp_bcb),y
	iny
	lda #>512
	sta (zp_bcb),y
	ldy #3
	lda #32
	sta (zp_bcb),y
	ldy #12
	lda #31
	sta (zp_bcb),y
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda #31
	sta (zp_bcb),y
	rts

eb_rowp                         ; Z8: zp_r -> zp_lay (wiersz ukladu; >= v_lvh - ostatni, M6.3), EB_RM, EB_RH, EB_R16, EB_RB. Zachowuje X.
	lda zp_r
	cmp v_lvh
	bcc ebr_in
	lda #0
	sta EB_RB                 ; poza ukladem: bez priorytetu
	lda v_lvhm1
	bcs ebr_lay               ; zawsze (C = 1)
ebr_in
	and #7
	tay
	lda bit_tab,y
	sta EB_RB
	lda zp_r
ebr_lay
	tay
	lda LAYROW_LO,y
	sta zp_lay
	lda LAYROW_HI,y
	sta zp_lay+1
	lda zp_r
	and #3
	lsr
	ror
	ror
	sta EB_RM                 ; (r&3)<<6
	lda zp_r
	and #4
	lsr
	lsr
	clc
	adc #RING_VRAM>>16
	sta EB_RH
	lda zp_r
	and #7
	asl
	asl
	asl
	asl
	sta EB_R16
	rts

eb_colp                         ; Z8: zp_c -> EB_CL, EB_CB, EB_C15. Zachowuje X, Y.
	lda zp_c
	and #7
	lsr
	ror
	ror
	ror
	sta EB_CL                 ; (c&7)<<5
	lda zp_c
	lsr
	lsr
	lsr
	and #1
	sta EB_CB
	lda zp_c
	and #15
	sta EB_C15
	rts

; eb_col7 / eb_row9 (M7.5 Z8, docs/plan-m7-ntsc.md 2 Z8): doladowana kolumna zp_c (wiersze by..by+6) / wiersz zp_r (kolumny bx..bx+8)
; - te same BCB, KIND_RAM, RCMASK_RAM, kolejka lancucha pierscieni i mapa priorytetu co petla next_slot + emit_block_k, ale czesci
; zalezne od kolumny / wiersza raz, czesci drugiej wspolrzednej z tablic (er_* / ec_*), sloty o BCB_BYTES nizej bez mul21, bez jsr na
; blok. Ok. 220 / 190 zamiast ok. 305 / 255 cykli na blok.
eb_col7
	jsr eb_colp               ; EB_CL, EB_CB, EB_C15
	lda #0
	sta zm_t1                 ; bity priorytetu kolumny (PRIOCOLM[c & 15] = zm_t1 na koncu - kolumna od nowa)
	lda v_by
	sta zp_r
	and #7
	sta zm_t0                 ; r & 7
	lda #7
	sta zm_t2                 ; blokow do zrobienia
	jsr next_slot             ; zp_bcb = slot, Y = indeks KIND_RAM
ec7_l
	lda KIND_RAM,y
	cmp #K_BLOCK
	beq ec7_k
	lda #K_BLOCK
	sta KIND_RAM,y
	jsr eb_const
ec7_k
	ldx zm_t0                 ; X = r & 7
	lda zp_r                  ; wiersz ukladu (>= v_lvh - ostatni, bez priorytetu - M6.3)
	cmp v_lvh
	bcs ec7_out
	tay
	lda LAYROW_LO,y
	sta zp_lay
	lda LAYROW_HI,y
	sta zp_lay+1
	ldy zp_c
	lda (zp_lay),y
	sta zp_k
	tay
	lda PRIO_RAM,y
	beq ec7_bm
	lda bit_tab,x
	ora zm_t1
	sta zm_t1
	jmp ec7_bm                ; (Y = k)
ec7_out
	lda v_lvhm1
	tay
	lda LAYROW_LO,y
	sta zp_lay
	lda LAYROW_HI,y
	sta zp_lay+1
	ldy zp_c
	lda (zp_lay),y
	sta zp_k
	tay
ec7_bm
	lda BLKMAP_RAM,y
	sta zp_ks
	asl
	asl
	ldy #1
	sta (zp_bcb),y            ; src mid = (s<<2)&$FF
	lda zp_ks
	rol
	rol
	rol
	and #3
	clc
	adc #STORE_VRAM>>16
	iny
	sta (zp_bcb),y            ; src hi = 4 + s/64
	lda EB_CL
	ldy #6
	sta (zp_bcb),y            ; dst lo = (c&7)<<5
	lda er_rm,x
	ora EB_CB
	iny
	sta (zp_bcb),y            ; dst mid = ((c>>3)&1) | ((r&3)<<6)
	lda er_rh,x
	iny
	sta (zp_bcb),y            ; dst hi = 2 + ((r&7)>>2)
	ldy zp_k                  ; M3.8b: maska pierscieni slotu - zmiana do kolejki lancucha
	lda RINGMASK_RAM,y
	sta zp_t1
	lda er_r16,x
	ora EB_C15
	tay
	lda zp_t1
	cmp RCMASK_RAM,y
	beq ec7_n
	sta RCMASK_RAM,y
	tya
	ldy zr_q
	sta RCQ_RAM,y
	inc zr_q
ec7_n
	dec zm_t2
	beq ec7_end
	inc zp_r
	inx
	txa
	and #7
	sta zm_t0
	dec v_slot                ; nastepny slot (od konca): zp_bcb - BCB_BYTES, Y = indeks KIND_RAM
	sec
	lda zp_bcb
	sbc #BCB_BYTES
	sta zp_bcb
	bcs ec7_nc
	dec zp_bcb+1
ec7_nc
	lda v_slot
	clc
	adc v_sbase
	tay
	jmp ec7_l
ec7_end
	ldx EB_C15
	lda zm_t1
	sta PRIOCOLM,x
	rts

eb_row9                         ; zp_r = wiersz (bit wiersza w PRIOCOLM 9 kolumn okna wyczyszczony przez wolajacego)
	jsr eb_rowp               ; zp_lay, EB_RM, EB_RH, EB_R16, EB_RB
	lda v_bx
	sta zp_c
	lda #9
	sta zm_t2
	jsr next_slot
er9_l
	lda KIND_RAM,y
	cmp #K_BLOCK
	beq er9_k
	lda #K_BLOCK
	sta KIND_RAM,y
	jsr eb_const
er9_k
	lda zp_c
	and #15
	tax                       ; X = c & 15
	ldy zp_c
	lda (zp_lay),y
	sta zp_k
	tay
	lda PRIO_RAM,y
	beq er9_bm
	lda EB_RB                 ; (0 - wiersz poza ukladem)
	ora PRIOCOLM,x
	sta PRIOCOLM,x
er9_bm
	lda BLKMAP_RAM,y
	sta zp_ks
	asl
	asl
	ldy #1
	sta (zp_bcb),y
	lda zp_ks
	rol
	rol
	rol
	and #3
	clc
	adc #STORE_VRAM>>16
	iny
	sta (zp_bcb),y
	lda ec_cl,x
	ldy #6
	sta (zp_bcb),y
	lda EB_RM
	ora ec_cb,x
	iny
	sta (zp_bcb),y
	lda EB_RH
	iny
	sta (zp_bcb),y
	ldy zp_k
	lda RINGMASK_RAM,y
	sta zp_t1
	txa
	ora EB_R16
	tay
	lda zp_t1
	cmp RCMASK_RAM,y
	beq er9_n
	sta RCMASK_RAM,y
	tya
	ldy zr_q
	sta RCQ_RAM,y
	inc zr_q
er9_n
	dec zm_t2
	beq er9_end
	inc zp_c
	dec v_slot
	sec
	lda zp_bcb
	sbc #BCB_BYTES
	sta zp_bcb
	bcs er9_nc
	dec zp_bcb+1
er9_nc
	lda v_slot
	clc
	adc v_sbase
	tay
	jmp er9_l
er9_end
	rts

; tablice Z8: wiersz pierscienia q = r & 7 - (q & 3) << 6, RING >> 16 + (q >> 2), q << 4; kolumna c & 15 - (c & 7) << 5, (c >> 3) & 1
er_rm	dta b($00, $40, $80, $C0, $00, $40, $80, $C0)
er_rh	dta b(RING_VRAM>>16, RING_VRAM>>16, RING_VRAM>>16, RING_VRAM>>16, [RING_VRAM>>16]+1, [RING_VRAM>>16]+1, [RING_VRAM>>16]+1, [RING_VRAM>>16]+1)
er_r16	dta b($00, $10, $20, $30, $40, $50, $60, $70)
ec_cl	dta b($00, $20, $40, $60, $80, $A0, $C0, $E0, $00, $20, $40, $60, $80, $A0, $C0, $E0)
ec_cb	dta b(0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1)

; patch_block_m (M7.5 Z4): patch_block (render/rings.asm) z bitem priorytetu bloku laty od nowa (blok w oknie - ten sam slot
; pierscienia; emit_block ustawi bit, gdy blok ma priorytet)
patch_block_m
	jsr patch_in_window       ; C = 0: zp_c / zp_r = blok laty w oknie 9 x 7
	bcs pbm_ret
	lda zp_r
	and #7
	tax
	lda bit_tab,x
	eor #$FF
	sta zm_t0
	lda zp_c
	and #15
	tax
	lda PRIOCOLM,x
	and zm_t0
	sta PRIOCOLM,x
	jsr next_slot
	jmp emit_block_k
pbm_ret
	rts

; full_reload: cale okno 9x7 blokow wokol (v_bx, v_by) do pierscienia - osobna lista 63 BCB
; w $1F800 (MEMAC MB_BUILD), wykonana od razu (run_list czeka). Start poziomu i skoki kamery > 1 blok.
full_reload
	ldx #15                   ; M7.5 Z4: mapa priorytetu okna od nowa (emit_block ustawia bity blokow z priorytetem)
	lda #0
fr_pcl
	sta PRIOCOLM,x
	dex
	bpl fr_pcl
	jsr wait_blitter          ; potok: biegnaca lista poprzedniej ramki czyta pierscien
	inc v_reload_now
	lda #MB_BUILD
	jsr set_memac
	mwa #RELOAD_CPU zp_bcb
	lda v_by
	sta zp_r
	lda #7
	sta zp_t0
fr_row
	lda v_bx
	sta zp_c
	ldx #9
fr_col
	jsr emit_block
	clc
	lda zp_bcb
	adc #BCB_BYTES
	sta zp_bcb
	bcc fr_nc
	inc zp_bcb+1
fr_nc
	inc zp_c
	dex
	bne fr_col
	inc zp_r
	dec zp_t0
	bne fr_row
	lda #<RELOAD_VRAM
	ldx #>[RELOAD_VRAM&$FFFF]
	ldy #RELOAD_VRAM>>16
	jsr run_list
	inc v_reloads
	lda v_mb_list             ; M4.2: okno kompletu budowanej listy
	jmp set_memac

; ---------------------------------------------------------------------
;  Widok: 1-4 prostokaty z pierscienia (zawijanie x 512, y 256) do bufora tylnego
;  Pozycja widoku w pierscieniu: rx = camx mod 512, ry = camy mod 256. Gdy widok przekracza krawedz
;  pierscienia, dzieli sie na A (rx,ry) w1 x h1, B (0,ry) w2 x h1, C (rx,0) w1 x h2, D (0,0) w2 x h2;
;  nieuzyte prostokaty to kopia 1x1 do bajtu roboczego (stala struktura listy - bez przelaczania NEXT).
; ---------------------------------------------------------------------
view_rects
	ldx v_tgt                 ; bufor, ktory bedzie tylny, gdy lista ruszy
	lda fb_mid,x
	sta v_fbm
	lda fb_hi,x
	sta v_fbh
; M7.5 Z2 (docs/plan-m7-ntsc.md 2): 4 BCB widoku zaleza tylko od (camx mod 512, camy mod 256, bufor) i w grze nikt poza view_rects
; nie pisze slotow SLOT_VIEW.. (NEXT slotu SLOT_VIEW+3 przywraca build_frame_list) - przy kluczu jak w ostatniej liscie kompletu BCB
; juz sa w slotach. Te sloty pisza tez szablony init_list_set i ekrany (scr/) - level_boot i tele_reload wolaja hud_clear -> nt_reset
; tuz przed init_list_set (miedzy nimi nie powstaje zadna lista), a ekrany zawsze poprzedzaja level_boot - pamiec zawsze od nowa.
	ldx v_lbuild
	lda VM_OK,x
	beq vr_new
	lda v_camx
	cmp VM_XL,x
	bne vr_new
	lda v_camx+1
	eor VM_XH,x
	and #1
	bne vr_new
	lda v_camy
	cmp VM_Y,x
	bne vr_new
	lda v_fbm
	cmp VM_FB,x
	bne vr_new
	rts
vr_new
	lda #1
	sta VM_OK,x
	lda v_camx
	sta VM_XL,x
	lda v_camx+1
	sta VM_XH,x
	lda v_camy
	sta VM_Y,x
	lda v_fbm
	sta VM_FB,x
	lda v_camx
	sta v_rx
	lda v_camx+1
	and #1
	sta v_rx+1
	lda v_camy
	sta v_ry
; podzial w poziomie: rx > 256 -> w1 = 512-rx, w2 = rx-256
	lda #0
	sta v_xs
	lda v_rx+1
	beq vr_nox
	lda v_rx
	beq vr_nox
	sta v_w2                  ; w2 = rx_lo
	eor #$FF
	clc
	adc #1
	sta v_w1                  ; w1 = 256 - rx_lo (1..255)
	inc v_xs
vr_nox
; podzial w pionie: ry > 64 -> h1 = 256-ry, h2 = ry-64
	lda #0
	sta v_ys
	lda v_ry
	cmp #65
	bcc vr_noy
	sec
	sbc #64
	sta v_h2
	lda v_ry
	eor #$FF
	clc
	adc #1
	sta v_h1
	inc v_ys
vr_noy
; A: src (rx, ry) -> (0,0), w1 x h1
	ldx #SLOT_VIEW
	jsr slot_ptr
	lda v_rx
	sta zp_t0
	lda v_rx+1
	sta zp_t1
	lda v_ry
	sta zp_t2
	jsr put_ring_src
	ldy #6                    ; M7.5 Z8: cel (0, 0) w linii (= put_fb_dst: x 0, bufor + 0 * 256, bez przeniesienia)
	lda #0
	sta (zp_bcb),y
	iny
	lda v_fbm
	sta (zp_bcb),y
	iny
	lda v_fbh
	sta (zp_bcb),y
	jsr w_first
	jsr h_first
; B: src (0, ry) -> (w1, 0), w2 x h1
	ldx #SLOT_VIEW+1
	jsr slot_ptr
	lda v_xs
	beq vr_b_dummy
	lda #$FE                  ; M7.5 Z8: slot B z prostokatem (nie pusty)
	jsr vr_real
	lda #0
	sta zp_t0
	sta zp_t1
	lda v_ry
	sta zp_t2
	jsr put_ring_src
	ldy #6                    ; M7.5 Z8: cel (w1, 0) w linii (= put_fb_dst)
	lda v_w1
	sta (zp_bcb),y
	iny
	lda v_fbm
	sta (zp_bcb),y
	iny
	lda v_fbh
	sta (zp_bcb),y
	lda v_w2
	jsr put_w
	jsr h_first
	jmp vr_c
vr_b_dummy
	lda #1                    ; M7.5 Z8: pusty BCB tylko przy zmianie stanu slotu
	jsr vr_dum
vr_c
; C: src (rx, 0) -> (0, h1), w1 x h2
	ldx #SLOT_VIEW+2
	jsr slot_ptr
	lda v_ys
	beq vr_c_dummy
	lda #$FD
	jsr vr_real
	lda v_rx
	sta zp_t0
	lda v_rx+1
	sta zp_t1
	lda #0
	sta zp_t2
	jsr put_ring_src
	lda #0
	sta zp_t0
	lda v_h1
	sta zp_t1
	jsr put_fb_dst
	jsr w_first
	lda v_h2
	jsr put_h
	jmp vr_d
vr_c_dummy
	lda #2
	jsr vr_dum
vr_d
; D: src (0,0) -> (w1, h1), w2 x h2
	ldx #SLOT_VIEW+3
	jsr slot_ptr
	lda v_xs
	and v_ys
	beq vr_d_dummy
	lda #$FB
	jsr vr_real
	lda #0
	sta zp_t0
	sta zp_t1
	sta zp_t2
	jsr put_ring_src
	lda v_w1
	sta zp_t0
	lda v_h1
	sta zp_t1
	jsr put_fb_dst
	lda v_w2
	jsr put_w
	lda v_h2
	jmp put_h
vr_d_dummy
	lda #4
	jmp vr_dum

; vr_dum / vr_real (M7.5 Z8, docs/plan-m7-ntsc.md 2 Z8): VM_DM kompletu - bit slotu B / C / D widoku = pusty BCB (put_dummy) juz w slocie
; (sloty widoku pisze tylko view_rects; nt_reset: 0 - szablon view_tpl). A = bit (vr_dum) / maska bez bitu (vr_real). Zachowuje Y.
vr_dum
	ldx v_lbuild
	sta zm_t0
	and VM_DM,x
	bne vrd_ret               ; slot juz pusty - te same bajty
	lda zm_t0
	ora VM_DM,x
	sta VM_DM,x
	jmp put_dummy
vr_real
	ldx v_lbuild
	and VM_DM,x
	sta VM_DM,x
vrd_ret
	rts

w_first                         ; szerokosc pierwszej kolumny: 256 albo w1
	lda v_xs
	beq wf_full
	lda v_w1
	jmp put_w
wf_full
	ldy #12
	lda #255
	sta (zp_bcb),y
	iny
	lda #0
	sta (zp_bcb),y
	rts

h_first
	lda v_ys
	beq hf_full
	lda v_h1
	jmp put_h
hf_full
	lda #192
put_h                           ; A = wysokosc 1..192
	sec
	sbc #1
	ldy #14
	sta (zp_bcb),y
	rts

put_w                           ; A = szerokosc 1..255
	sec
	sbc #1
	ldy #12
	sta (zp_bcb),y
	iny
	lda #0
	sta (zp_bcb),y
	rts

slot_ptr                        ; X = slot kompletu v_lbuild -> zp_bcb (zachowuje X)
	clc
	lda mul21_lo,x
	adc v_lcpu
	sta zp_bcb
	lda mul21_hi,x
	adc v_lcpu+1
	sta zp_bcb+1
	rts

; src = RING + y*512 + x ; zp_t0/zp_t1 = x (9 bit), zp_t2 = y
put_ring_src
	ldy #0
	lda zp_t0
	sta (zp_bcb),y
	lda zp_t2
	asl
	ora zp_t1
	iny
	sta (zp_bcb),y
	lda zp_t2
	and #$80
	asl
	rol                       ; A = bit 7 y
	clc
	adc #RING_VRAM>>16
	iny
	sta (zp_bcb),y
	rts

; dst = FB(v_back) + y*256 + x ; zp_t0 = x, zp_t1 = y
put_fb_dst
	ldy #6
	lda zp_t0
	sta (zp_bcb),y
	lda zp_t1
	clc
	adc v_fbm
	iny
	sta (zp_bcb),y
	lda v_fbh
	adc #0
	iny
	sta (zp_bcb),y
	rts

put_dummy                       ; 1x1 z pierscienia do bajtu roboczego
	ldy #0
	tya
	sta (zp_bcb),y
	iny
	sta (zp_bcb),y
	iny
	lda #RING_VRAM>>16
	sta (zp_bcb),y
	ldy #6
	lda #<SCRATCH_VRAM
	sta (zp_bcb),y
	iny
	lda #>SCRATCH_VRAM
	sta (zp_bcb),y
	iny
	lda #0
	sta (zp_bcb),y
	ldy #12
	sta (zp_bcb),y
	iny
	sta (zp_bcb),y
	iny
	sta (zp_bcb),y
	rts

; ---------------------------------------------------------------------
;  Priorytet SMS: piksele kafla z bitem priorytetu o kolorze != 0 sa nad sprite'ami. Obiekty i czesci
;  blokow z priorytetem (stencil) emituje render/sprites.asm (obj_bcbs, prio_rect); prio_part = jedna
;  czesc bloku: pc_* = kolumny (indeks 0/1): blok, przesuniecie w bloku lx, szerokosc w, x na ekranie;
;  pr_* = wiersze: blok, ly, wysokosc h, y na ekranie (zp_t3 / zp_t2 = indeks kolumny / wiersza).
; ---------------------------------------------------------------------
prio_part
	ldx zp_t2
	lda pr_row,x
	cmp v_lvh
	jcs pp_skip               ; poza poziomem
	tay                       ; M6.3: adres wiersza ukladu z tablicy
	lda LAYROW_LO,y
	sta zp_lay
	lda LAYROW_HI,y
	sta zp_lay+1
	ldx zp_t3
	ldy pc_col,x
	lda (zp_lay),y
	sta zp_k
	tax
	lda PRIO_RAM,x            ; priorytet wg numeru bloku
	jeq pp_skip
	lda BLKMAP_RAM,x          ; M6.9: dalej zp_k = slot magazynu bloku (adres zrodla STORE + s * 1024)
	sta zp_k
	ldx v_pslot
	cpx #N_SLOTS
	bcs pp_skip               ; M4.2: brak slotu
	jsr slot_ptr
	inc v_pslot
; src = STORE + k*1024 + ly*32 + lx
	ldx zp_t2
	lda pr_ly,x
	sta zp_t0
	asl
	asl
	asl
	asl
	asl                       ; (ly&7)<<5
	ldx zp_t3
	ora pc_lx,x
	ldy #0
	sta (zp_bcb),y
	lda zp_t0
	lsr
	lsr
	lsr
	sta zp_t1                 ; ly>>3
	lda zp_k
	asl
	asl
	clc
	adc zp_t1
	iny
	sta (zp_bcb),y
	lda zp_k
	rol
	rol
	rol
	and #3
	clc
	adc #STORE_VRAM>>16
	iny
	sta (zp_bcb),y
	iny                       ; krok Y = 32 i X = 1 (slot mogl wczesniej byc obiektem - render/sprites.asm)
	lda #32
	sta (zp_bcb),y
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda #1
	sta (zp_bcb),y
; dst
	ldx zp_t3
	lda pc_scr,x
	sta zp_t0
	ldx zp_t2
	lda pr_scr,x
	sta zp_t1
	jsr put_fb_dst
	ldx zp_t3
	lda pc_w,x
	jsr put_w
	ldx zp_t2
	lda pr_h,x
	jsr put_h
	ldy #20
	lda #$09
	sta (zp_bcb),y
	mwa zp_bcb zp_last
pp_skip
	rts
