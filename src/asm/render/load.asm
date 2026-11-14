; =====================================================================
;  load.asm - ladowanie poziomu dla renderera (M2): atlas -> VRAM, uklad/priorytety/palety -> RAM,
;  kulka -> VRAM, XDL-e i szablony list BCB, budowa magazynu blokow blitterem.
;  Dane: banki 33 (atlas) i 35 (poziom) z tools/extract_sms.py (offsety LB_* w level.inc).
; =====================================================================

; load_level_data: kopie z bankow przez okno $4000 (CPU) do VRAM (przez MEMAC A $2000) i RAM.
; Uklad poziomu trafia do LAYOUT_RAM $1000 = lustro SMS $C000 (stride = szerokosc ukladu z naglowka: GHZ1 256, GHZ2 128).
load_level_data
	lda v_pbatlas             ; bank 33 (GHZ) albo 61 (etapy specjalne, M6.5): atlas 256 kafli 8x8, 8 bpp (16 KiB)
	sta PORTB
	lda #MB_ATLAS0            ; VRAM $1A000-$1BFFF
	jsr set_memac
	lda #32                   ; 8 KiB = 32 strony
	sta zp_cnt
	lda #>BANK_WIN
	ldx #>MEMAC_CPU
	jsr copy_pages
	lda #MB_ATLAS1            ; VRAM $1C000-$1DFFF
	jsr set_memac
	lda #32
	sta zp_cnt
	lda #>[BANK_WIN+$2000]
	ldx #>MEMAC_CPU
	jsr copy_pages

	lda v_pblevel             ; bank 35 (GHZ1) albo 55 (GHZ2): dane poziomu
	sta PORTB
	jsr lay_pages             ; uklad 4 KiB -> $1000-$1FFF (M6.9: $15 - 2048 B, wiersze 64-127 zostaja z SBZ2)
	sta zp_cnt
	lda #>[BANK_WIN+LB_LAYOUT]
	ldx #>LAYOUT_RAM
	jsr copy_pages
	jsr lay_tables            ; M6.3: szerokosc i wysokosc ukladu z naglowka, adresy wierszy
	lda #1                    ; priorytety blokow (1 B/blok) -> PRIO_RAM
	sta zp_cnt
	lda #>[BANK_WIN+LB_PRIO]
	ldx #>PRIO_RAM
	jsr copy_pages
	jsr prio_win_init         ; M4.9a: okna kamery z blokiem z priorytetem (PRIOWIN_RAM)
	lda #1                    ; palety RGB (tlo + warianty cyklu) -> PAL_RAM
	sta zp_cnt
	lda #>[BANK_WIN+LB_PALS]
	ldx #>PAL_RAM
	jsr copy_pages
	lda #1                    ; M6.9: slot magazynu dla numeru bloku (LB_BLKMAP) -> BLKMAP_RAM (RAM pod OS; emit_block, prio_part)
	sta zp_cnt
	lda #>[BANK_WIN+LB_BLKMAP]
	ldx #>BLKMAP_RAM
	jsr copy_pages
	lda #MB_LOW               ; kulka testowa 32x32 -> VRAM SPRITE_VRAM ($00400)
	jsr set_memac
	lda #4
	sta zp_cnt
	lda #>[BANK_WIN+LB_BALL]
	ldx #>SPRITE_CPU
	jsr copy_pages
	lda #PB_MAIN
	sta PORTB
	lda #LV_NBLOCKS
	sta v_nblocks
	rts

; ---------------------------------------------------------------------
; lay_tables (M6.3): wymiary ukladu z naglowka poziomu w banku (LB_HDR + 1: szerokosc, + 3: wysokosc, slowa) ->
; v_lvh (wiersze), v_lvhm1, v_lvcols (szerokosc & $FF: 0 = 256) i tablice adresow wierszy LAYROW_LO/HI =
; LAYOUT_RAM + wiersz * szerokosc (256 wierszy, M6.7). Bank poziomu wlaczony.
; ---------------------------------------------------------------------
lay_tables
	lda BANK_WIN+LB_HDR+3
	sta v_lvhl                ; wysokosc & $FF (256 -> 0: petle po wierszach)
	ldx BANK_WIN+LB_HDR+4     ; starszy bajt wysokosci: 1 = 256 wierszy (M6.7: JUN2 16 x 256)
	bne lyt_h256
	sta v_lvh
	sec
	sbc #1
	sta v_lvhm1
	jmp lyt_hd
lyt_h256                        ; 256 wierszy: obciecie numeru wiersza (cmp v_lvh / bcc) i tak daje ten sam wiersz (255)
	lda #$FF
	sta v_lvh
	sta v_lvhm1
lyt_hd
	lda BANK_WIN+LB_HDR+1
	sta v_lvcols
	lda BANK_WIN+LB_HDR+2
	sta zp_t1                 ; szerokosc: starszy bajt
	lda #0
	sta zp_t2                 ; adres wiersza (16 bitow) od LAYOUT_RAM
	lda #>LAYOUT_RAM
	sta zp_t3
	ldx #0
lyt_l
	lda zp_t2
	sta LAYROW_LO,x
	lda zp_t3
	sta LAYROW_HI,x
	clc
	lda zp_t2
	adc v_lvcols
	sta zp_t2
	lda zp_t3
	adc zp_t1
	sta zp_t3
	inx
	bne lyt_l                 ; M6.7: 256 wierszy tablic (uklady do 16 x 256)
	rts

; ---------------------------------------------------------------------
; prio_win_init (M4.9a): PRIOWIN_RAM - bit kolumny c ukladu = 1, gdy w kolumnach c..c+8 (okno pierscienia: 9 blokow
; wokol kamery, v_bx..v_bx+8) jest blok z priorytetem (PRIO_RAM); poza takim oknem renderer nie liczy prostokatow
; priorytetu (render/sprites.asm obj_bcbs). Najpierw PRIOCOL_TMP - bit kolumny z blokiem z priorytetem (16 wierszy
; ukladu), potem okno 9 kolumn (kolumny > 255 nie istnieja). Raz przy ladowaniu poziomu (uklad zmienia sie potem
; tylko o bloki pierscieni, bez priorytetu). W GHZ1 priorytet maja kolumny 110-111 i 150-151 (palmy).
; ---------------------------------------------------------------------
prio_win_init
	ldx #31
	lda #0
pwi_clr
	sta PRIOWIN_RAM,x
	sta PRIOCOL_TMP,x
	dex
	bpl pwi_clr
	sta zp_t2                 ; kolumna c
pwi_col
	lda #0
	sta zp_t0                 ; wiersz ukladu (M6.3: adres wiersza z tablicy, wysokosc v_lvh)
pwi_row
	ldx zp_t0
	lda LAYROW_LO,x
	sta zp_lay
	lda LAYROW_HI,x
	sta zp_lay+1
	ldy zp_t2
	lda (zp_lay),y
	tax
	lda PRIO_RAM,x
	bne pwi_set
	inc zp_t0
	lda zp_t0
	cmp v_lvhl
	bne pwi_row
	beq pwi_next              ; zawsze
pwi_set
	lda zp_t2
	lsr
	lsr
	lsr
	tax
	lda zp_t2
	and #7
	tay
	lda bit_tab,y
	ora PRIOCOL_TMP,x
	sta PRIOCOL_TMP,x
pwi_next
	inc zp_t2
	lda zp_t2
	cmp v_lvcols              ; kolumny 0..szerokosc-1 (256 -> v_lvcols = 0: do zawiniecia)
	bne pwi_col
	lda #0
	sta zp_t2                 ; kolumna c okna
pwi_w
	lda zp_t2
	sta zp_t3                 ; kolumna k = c..c+8
	lda #9
	sta zp_t0
pwi_wk
	lda zp_t3
	lsr
	lsr
	lsr
	tax
	lda zp_t3
	and #7
	tay
	lda PRIOCOL_TMP,x
	and bit_tab,y
	bne pwi_wset
	inc zp_t3
	beq pwi_wnext             ; poza ukladem (c + k > 255)
	dec zp_t0
	bne pwi_wk
	beq pwi_wnext
pwi_wset
	lda zp_t2
	lsr
	lsr
	lsr
	tax
	lda zp_t2
	and #7
	tay
	lda bit_tab,y
	ora PRIOWIN_RAM,x
	sta PRIOWIN_RAM,x
pwi_wnext
	inc zp_t2
	bne pwi_w
	rts

; load_palette: paleta 1 nakladki VBXE: kolory 0-15 = paleta tla SMS (PAL_RAM), 64-66 = kulka
load_palette
	lda v_pblevel             ; M6.5: parametry cyklu palety z naglowka poziomu (LB_HDR + $1B: ramki, + $1C: warianty)
	sta PORTB
	lda BANK_WIN+LB_HDR+$1B
	sta v_cycspd
	lda BANK_WIN+LB_HDR+$1C
	sta v_cyccnt
	jsr water_pal             ; M6.8: paleta podwodna (paleta 2 VBXE) przy poziomie z woda; wraca z PB_MAIN
	ldy #VC_PSEL
	lda #1
	sta (zp_fx),y
	ldy #VC_CSEL
	lda #0
	sta (zp_fx),y
	ldx #0
lp_bg
	lda PAL_RAM,x
	ldy #VC_CR
	sta (zp_fx),y
	lda PAL_RAM+1,x
	iny
	sta (zp_fx),y
	lda PAL_RAM+2,x
	iny
	sta (zp_fx),y
	inx
	inx
	inx
	cpx #48
	bne lp_bg
	ldy #VC_CSEL
	lda #64
	sta (zp_fx),y
	ldx #0
lp_ball
	lda ball_rgb,x
	ldy #VC_CR
	sta (zp_fx),y
	lda ball_rgb+1,x
	iny
	sta (zp_fx),y
	lda ball_rgb+2,x
	iny
	sta (zp_fx),y
	inx
	inx
	inx
	cpx #9
	bne lp_ball
	rts

; =====================================================================
;  init_lists: XDL0/XDL1 do VRAM, oba komplety listy ramki z szablonow (tables.asm), lista budowy
;  magazynu (256 BCB kafel -> blok) i lista przeladowania pierscienia (63 BCB blok -> pierscien).
;  Szablony maja stale pola; w kazdej ramce CPU patchuje tylko adresy/rozmiary.
; =====================================================================
init_lists
	lda #MB_LOW
	jsr set_memac
	mwa #xdl0 zp_src
	mwa #MEMAC_CPU+XDL0_VRAM zp_dst
	ldy #xdl0_end-xdl0
	jsr copy_n
	mwa #xdl1 zp_src
	mwa #MEMAC_CPU+XDL1_VRAM zp_dst
	ldy #xdl1_end-xdl1
	jsr copy_n
	lda #0
	ldy #VC_XDL_ADR0
	sta (zp_fx),y             ; XDL0 ($00000) do pierwszego flipu
	iny
	sta (zp_fx),y
	iny
	sta (zp_fx),y
	lda #MB_RINGART           ; M4.9a: bajt 0 w VRAM - zrodlo pustych BCB slotow sprite'ow (ZERO_VRAM, objspr.asm)
	jsr set_memac
	lda #0
	sta MEMAC_CPU+[ZERO_VRAM-$7E000]
	lda #MB_LOW
	jsr set_memac
; komplet 0 listy ramki (komplet 1 lezy w obszarze listy budowy magazynu - game.asm po build_store)
	ldx #0
	jsr init_list_set
; listy w $1E000: budowa magazynu (256) i przeladowanie pierscienia (63)
	jsr init_build_list
	lda #MB_BUILD
	jsr set_memac
	mwa #RELOAD_CPU zp_dst
	ldx #RELOAD_N
il_reload
	mwa #blk_tpl zp_src
	ldy #BCB_BYTES
	jsr copy_n
	jsr dst_add21
	dex
	bne il_reload
	mwa #RELOAD_CPU+[RELOAD_N-1]*BCB_BYTES+20 zp_dst
	ldy #0
	tya
	sta (zp_dst),y            ; ostatni wpis bez NEXT
	lda #MB_LOW
	jmp set_memac

; ---------------------------------------------------------------------
; init_build_list (M6.9): lista budowy magazynu w $1E000 (256 BCB kafel -> blok z build_tpl; dst lo = (wpis & 3) * 8). Komplet 1 listy
; ramki lezy w tym samym obszarze (po pierwszej budowie), wiec budowa magazynu w trakcie gry (pod-poziom - game/level.asm tele_reload)
; musi najpierw odtworzyc szablony. Na koniec MB_LOW.
; ---------------------------------------------------------------------
init_build_list
	lda #MB_BUILD
	jsr set_memac
	mwa #BUILD_CPU zp_dst
	ldx #0
ibl_l
	mwa #build_tpl zp_src
	ldy #BCB_BYTES
	jsr copy_n
	txa
	and #3
	asl
	asl
	asl
	ldy #6
	sta (zp_dst),y            ; dst lo = tx*8
	jsr dst_add21
	inx
	bne ibl_l
	lda #MB_LOW
	jmp set_memac

; ---------------------------------------------------------------------
; init_list_set: komplet X listy ramki z szablonow (tables.asm) w oknie set_mb: sloty blokow i pierscieni
; (blk_tpl), 4 x widok, sprite'y obiektow (nop_tpl, M4.2), obiekty (ball_tpl - zrodlo i rozmiar patchuje
; obj_emit), priorytet tla (prio_tpl);
; rodzaj BCB slotow blokow = blok (KIND_RAM, M3.8c), slotow sprite'ow = K_NOPA (SKIND_RAM, M4.9a).
; M4.2: komplety w roznych oknach MEMAC, sloty < 256.
; ---------------------------------------------------------------------
init_list_set
	stx zp_t1
	lda set_mb,x
	jsr set_memac
	ldx zp_t1
	lda set_cpu_lo,x
	sta v_lcpu
	lda set_cpu_hi,x
	sta v_lcpu+1
	lda set_kind,x
	sta zp_t2
	ldx #0
ils_slot
	clc
	lda mul21_lo,x
	adc v_lcpu
	sta zp_dst
	lda mul21_hi,x
	adc v_lcpu+1
	sta zp_dst+1
	mwa #blk_tpl zp_src
	cpx #SLOT_VIEW
	bcc ils_put
	mwa #view_tpl zp_src
	cpx #SLOT_SPR
	bcc ils_put
	mwa #nop_tpl zp_src       ; M4.2: obszar sprite'ow obiektow - pusty BCB 1x1 (render/objspr.asm)
	cpx #SLOT_OBJ
	bcc ils_put
	mwa #ball_tpl zp_src
	cpx #SLOT_PRIO
	bcc ils_put
	mwa #prio_tpl zp_src
ils_put
	ldy #BCB_BYTES
	jsr copy_n
	inx
	cpx #N_SLOTS
	bne ils_slot
	ldx zp_t2
	ldy #N_BLK_SLOTS
	lda #K_BLOCK
ils_kind
	sta KIND_RAM,x
	inx
	dey
	bne ils_kind
	ldx zp_t1                 ; M4.9a: rodzaj slotow sprite'ow obiektow = pusty rodziny atlasu (nop_tpl)
	lda set_skind,x
	tax
	ldy #N_SPR_SLOTS
	lda #K_NOPA
ils_skind
	sta SKIND_RAM,x
	inx
	dey
	bne ils_skind
	lda #MB_LOW
	jmp set_memac

; =====================================================================
;  build_store: magazyn wszystkich blokow strefy w VRAM (STORE_VRAM + k*1024, 32x32, stride 32).
;  Partie po 16 blokow = 256 BCB (16 kafli 8x8 na blok), lista w $1E000 wykonywana przez run_list.
;  Kafel t -> blok k: src = ATLAS + t*64 (stride 8), dst = STORE + k*1024 + ty*256 + tx*8.
;  Mapowanie blokow (16 B/blok) czytane z banku poziomu (LB_TILEMAP), 1 strona = 16 blokow.
; =====================================================================
build_store
	lda #0
	sta zp_kb
	lda v_pblevel
	sta PORTB
	mwa #BANK_WIN+LB_TILEMAP zp_src
bs_batch
	lda #MB_BUILD
	jsr set_memac
	mwa #BUILD_CPU zp_bcb
	lda zp_kb
	and #63
	asl
	asl
	sta zp_t0                 ; (k&63)*4
	lda zp_kb
	lsr
	lsr
	lsr
	lsr
	lsr
	lsr
	clc
	adc #4
	sta zp_t1                 ; 4 + k/64
; liczba wpisow w partii: min(16, N-k) * 16
	lda #LV_NBLOCKS
	sec
	sbc zp_kb
	cmp #16
	bcc bs_part
	lda #16
bs_part
	asl
	asl
	asl
	asl
	sta zp_e                  ; 0 = 256 wpisow
	ldx #0
bs_entry
	txa
	tay
	lda (zp_src),y            ; t = mapowanie[(k + e/16)*16 + e%16]
	sta zp_k
	and #3
	lsr
	ror
	ror                       ; (t&3)<<6
	ldy #0
	sta (zp_bcb),y
	lda zp_k
	lsr
	lsr
	clc
	adc #>[ATLAS_VRAM&$FFFF]
	iny
	sta (zp_bcb),y
	txa
	lsr
	lsr
	clc
	adc zp_t0
	ldy #7
	sta (zp_bcb),y
	lda zp_t1
	iny
	sta (zp_bcb),y
	lda #$08
	ldy #20
	sta (zp_bcb),y
	clc
	lda zp_bcb
	adc #BCB_BYTES
	sta zp_bcb
	bcc bs_nc
	inc zp_bcb+1
bs_nc
	inx
	cpx zp_e
	bne bs_entry
; ostatni wpis partii bez NEXT
	sec
	lda zp_bcb
	sbc #1
	sta zp_bcb
	bcs bs_nb
	dec zp_bcb+1
bs_nb
	ldy #0
	lda #0
	sta (zp_bcb),y
	lda #<BUILD_VRAM
	ldx #>[BUILD_VRAM&$FFFF]
	ldy #BUILD_VRAM>>16
	jsr run_list
	inc zp_src+1              ; nastepne 16 blokow mapowania = 1 strona
	lda zp_kb
	clc
	adc #16
	sta zp_kb
	cmp #LV_NBLOCKS
	jcc bs_batch
	lda #PB_MAIN
	sta PORTB
	lda #MB_LOW
	jmp set_memac
