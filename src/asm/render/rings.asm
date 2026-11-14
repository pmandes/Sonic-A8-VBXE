; =====================================================================
;  rings.asm - pierscienie w rendererze (M3.5): animowana grafika kafli pierscienia w pierscieniu tla
;  i ponowny blit bloku po zebraniu pierscienia.
;
;  Bloki z pierscieniami (GHZ: $79-$7B) maja w magazynie (STORE_VRAM) puste kafle pierscienia - grafika
;  strefy ma pod $FC-$FF kolor 0, jak VRAM SMS przed pierwszym update_ring_tiles. Biezaca klatka (16x16,
;  RINGART_VRAM + klatka * 256) jest kopiowana BCB-ami wprost do pierscienia tla na polowki blokow
;  z RINGMASK_RAM (b0: x 0-15, b1: x 16-31; wiersze 8-23 bloku):
;   - pelne przeladowanie: cale okno 9x7;
;   - inaczej: tylko bloki doladowane w tej liscie (kolumna, wiersz) i blok laty; zmiana klatki
;     (v_ring_art != v_ring_drawn) - reszte okna maluje lancuch pierscieni przed lista (M3.8b, rchain.asm).
;  BCB pierscieni sa wypelniane przed blokami (sloty od konca), wiec wykonuja sie po doladowaniu blokow
;  i przed widokiem. Zebrany pierscien: game/rings.asm irq_tile_patch -> v_patch_* -> ponowny blit bloku
;  (nowy numer bloku ma w tym miejscu kafel 0 = lata SMS 2x2 puste kafle).
; =====================================================================

; load_ring_data: maski pierscieni -> RINGMASK_RAM, klatki (2 piksele/bajt) -> VRAM RINGART_VRAM (8 bpp)
load_ring_data
	lda v_pblevel
	sta PORTB
	lda #1
	sta zp_cnt
	lda #>[BANK_WIN+LB_RINGMASK]
	ldx #>RINGMASK_RAM
	jsr copy_pages
	lda #MB_RINGART
	jsr set_memac
	mwa #BANK_WIN+LB_RINGART zp_src
	mwa #RINGART_CPU zp_dst
	mwa #6*128 zp_cnt         ; 768 B spakowanych
lrd_loop
	ldy #0
	lda (zp_src),y
	pha
	lsr                       ; starsza polowka = lewy piksel
	lsr
	lsr
	lsr
	sta (zp_dst),y
	pla
	and #$0F
	iny
	sta (zp_dst),y
	inc zp_src
	bne lrd_s
	inc zp_src+1
lrd_s
	clc
	lda zp_dst
	adc #2
	sta zp_dst
	bcc lrd_d
	inc zp_dst+1
lrd_d
	lda zp_cnt
	bne lrd_dec
	dec zp_cnt+1
lrd_dec
	dec zp_cnt
	lda zp_cnt
	ora zp_cnt+1
	bne lrd_loop
	lda #MB_LOW
	jsr set_memac
	lda #PB_MAIN
	sta PORTB
	rts

; ring_bcbs: BCB pierscieni dla listy (v_bx, v_by = nowe okno; v_ld_col/v_ld_row - doladowane kolumna
; i wiersz ($FF = brak), v_full = pelne przeladowanie). Przed pierwsza klatka gry (v_ring_art = $FF)
; nic - magazyn ma puste kafle. Koszt (6502): okno 9x7 ok. 1,4 tys. cykli + ok. 150 na BCB.
ring_bcbs
	lda v_ring_art
	cmp #$FF
	jeq rgb_ret
	clc                       ; zrodlo: RINGART_VRAM + klatka * 256 (bajt srodkowy, wspolny dla listy)
	adc #[RINGART_VRAM>>8]&$FF
	sta v_er_src
	lda v_full
	bne rgb_all
	lda v_ring_art            ; M3.8b: zmiana klatki -> caly obraz pierscieni robi lancuch (render/rchain.asm)
	cmp v_ring_drawn          ; przed ta lista; tu tylko bloki doladowane w niej i lata
	beq rgb_inc
	lda v_er_src
	sta zr_art
	lda #1
	sta zr_pend
rgb_inc
	lda v_ld_col              ; doladowana kolumna (7 blokow)
	cmp #$FF
	beq rgb_row
	sta zp_c
	lda v_by
	sta zp_r
	ldx #7
rgb_col_l
	jsr ring_block
	inc zp_r
	dex
	bne rgb_col_l
rgb_row
	lda v_ld_row              ; doladowany wiersz (9 blokow)
	cmp #$FF
	beq rgb_patch
	sta zp_r
	jsr ring_row              ; M3.8c: wiersz ukladu i czesci adresu raz dla 9 blokow
	lda v_bx
	sta zp_c
	lda #9
	sta v_rcnt
rgb_row_l
	ldy zp_c
	lda (zp_lay),y
	tay
	lda RINGMASK_RAM,y
	beq rgb_row_n
	jsr ring_halves
rgb_row_n
	inc zp_c
	dec v_rcnt
	bne rgb_row_l
rgb_patch
	jsr patch_in_window       ; blok laty (moze miec druga polowke z pierscieniem, np. $7B -> $7A)
	bcs rgb_done
	jsr ring_block_pend
	jmp rgb_done
rgb_all                          ; cale okno 9x7: wiersz ukladu raz na wiersz, waska petla po kolumnach
	lda v_by
	sta zp_r
	lda #7
	sta zp_t2
rgb_all_r
	jsr ring_row
	lda v_bx
	sta zp_c
	lda #9
	sta v_rcnt
rgb_all_c
	ldy zp_c
	lda (zp_lay),y
	tax
	lda RINGMASK_RAM,x
	beq rgb_all_n
	jsr ring_halves
rgb_all_n
	inc zp_c
	dec v_rcnt
	bne rgb_all_c
	inc zp_r
	dec zp_t2
	bne rgb_all_r
rgb_done
	lda v_ring_art
	sta v_ring_drawn
rgb_ret
	rts

; patch_in_window: C = 0 i zp_c/zp_r = blok laty, gdy jest lata (v_patch_on) w oknie 9x7; inaczej C = 1
patch_in_window
	lda v_patch_on
	beq piw_no
	lda v_patch_c
	sec
	sbc v_bx
	cmp #9
	bcs piw_no
	lda v_patch_r
	sec
	sbc v_by
	cmp #7
	bcs piw_no
	lda v_patch_c
	sta zp_c
	lda v_patch_r
	sta zp_r
	clc
	rts
piw_no
	sec
	rts

; tp_read (M4.7, M6.4): 2 x 2 kafle laty z danych g_screen_tile_replace_data_ptr (adres SMS w banku 45: dane kwiatow
; UNK_07B5D 01:7B5D-7B84 albo lata kapsuly GHZ3 01:7564-7593; 4 x (numer kafla, atrybut)) -> v_tpt, v_tpa (bit k = kafel
; k z atlasu sprite'ow: atrybut $19 = kafle 256 + n z palety sprite'ow, jak lata kapsuly; atrybut 0 = atlas tla).
; C = 1 (i v_tp_todo + 1): dane spoza kwiatow i kapsuly albo inny atrybut (odbicie, priorytet - M6).
; Priorytet nad sprite'ami (atrybut b4) latam kapsuly nie jest odtwarzany - sprite'y sa rysowane nad nimi.
; glass_read (M6.10): lata szyby bossa SKY3 (LUT_SKY3_boss_glass_crack_tile_anim 02:BA45, 15 x (x, y, 4 slowa kafli); dane laty k =
; $BA49 + 12k w banku PB_OBJZ3 pod adresem - OZ_OFF): slowa $10nn (kafel nn atlasu SKY3, priorytet) albo $0000. Bloki szyby maja
; priorytet (flagi bit 7), a port rysuje priorytet blokami z magazynu - lata trafia do slotu magazynu bloku (game/rings.asm glass_req).
; ---------------------------------------------------------------------
glass_read                      ; M6.10: C = 0 - dane laty szyby bossa SKY3 (opis wyzej), 4 kafle w v_gp_t; C = 1 - inne dane
	lda g_screen_tile_replace_data_ptr+1
	cmp #$BA
	bne gsr_no
	lda g_screen_tile_replace_data_ptr
	cmp #$49
	bcc gsr_no
	cmp #$F2
	bcs gsr_no
	lda v_img+LR_OBJZ         ; M7.2: obraz obiektow strefy = bank 30 (v_img - XEX: = v_pbobjz; nosnik: id, slot OBJZ albo LEVEL2)
	cmp #LI_OBJZ3
	bne gsr_no
	lda g_screen_tile_replace_data_ptr
	sta zp_src
	lda #$BA-$40              ; adres SMS - OZ_OFF
	sta zp_src+1
	lda v_pbobjz              ; bank z obrazem 30 (XEX: PB_OBJZ3)
	sta PORTB
	ldy #6
	ldx #3
gsr_l
	lda (zp_src),y            ; mlodszy bajt slowa = numer kafla (starszy $10 = priorytet albo 0 - kafel 0, pusty; priorytet z bloku)
	sta v_gp_t,x
	dey
	dey
	dex
	bpl gsr_l
	lda #PB_MAIN
	sta PORTB
	clc
	rts
gsr_no
	sec
	rts

tp_read
	lda g_screen_tile_replace_data_ptr+1
	cmp #$84                  ; M6.6: UNK_0848E (spadajacy element mostu $2E, bank obiektow strefy): 8 zer = 4 x (kafel 0, atrybut 0)
	bne tpr_nz
	lda g_screen_tile_replace_data_ptr
	cmp #$8E
	bne tpr_todo
	lda #0
	sta v_tpa
	sta v_tpt
	sta v_tpt+1
	sta v_tpt+2
	sta v_tpt+3
	clc
	rts
tpr_nz
	cmp #$7B
	bne tpr_cap
	lda g_screen_tile_replace_data_ptr
	cmp #<$7B5D
	bcc tpr_todo
	cmp #<$7B85
	bcs tpr_todo
	bcc tpr_go                ; zawsze
tpr_cap
	cmp #$75
	bne tpr_todo
	lda g_screen_tile_replace_data_ptr
	cmp #<$7564
	bcc tpr_todo
	cmp #<$7594
	bcs tpr_todo
tpr_go
	sta zp_src
	lda g_screen_tile_replace_data_ptr+1
	sta zp_src+1
	lda #0
	sta v_tpa
	lda #PB_OBJ
	sta PORTB
	ldy #7
	ldx #3
tpr_l
	lda (zp_src),y            ; atrybut
	beq tpr_a0
	cmp #$19
	bne tpr_attr
	lda v_tpa                 ; $19: kafel sprite'ow (b0), paleta sprite'ow (b3), priorytet (b4 - pominiety)
	ora bit_tab,x
	sta v_tpa
tpr_a0
	dey
	lda (zp_src),y            ; numer kafla
	sta v_tpt,x
	dey
	dex
	bpl tpr_l
	lda #PB_MAIN
	sta PORTB
	clc
	rts
tpr_attr
	lda #PB_MAIN
	sta PORTB
tpr_todo
	inc v_tp_todo
	sec
	rts

; M7.5: patch_block (lata po zebraniu pierscienia - blok spod v_patch_* z ukladu do pierscienia) przeniesione pod okno z bitem mapy
; priorytetu: render/frame.asm patch_block_m.

; ring_row: wiersz okna zp_r -> zp_lay (wiersz ukladu; >= v_lvh jak w emit_block - ostatni wiersz)
; oraz czesci adresu docelowego zalezne od wiersza: v_er_mid = (r & 3) << 6 + $10 (8 linii w dol bloku),
; v_er_hi = bank pierscienia tla + ((r & 4) >> 2). Zachowuje X.
ring_row
	lda zp_r                  ; M6.3: adres wiersza ukladu z tablicy (render/load.asm: lay_tables)
	cmp v_lvh
	bcc rgr_ok
	lda v_lvhm1
rgr_ok
	tay
	lda LAYROW_LO,y
	sta zp_lay
	lda LAYROW_HI,y
	sta zp_lay+1
	lda zp_r
	and #3
	lsr
	ror
	ror                       ; (r&3)<<6
	ora #$10
	sta v_er_mid
	lda zp_r
	and #4
	lsr
	lsr
	clc
	adc #RING_VRAM>>16
	sta v_er_hi
	rts

; ring_block: BCB klatki pierscienia na polowki bloku ukladu (zp_c, zp_r) wg RINGMASK_RAM. Zachowuje X.
ring_block
	jsr ring_row
	ldy zp_c
	lda (zp_lay),y
	tay
	lda RINGMASK_RAM,y
	bne ring_halves
	rts

; ring_block_pend: ring_block dla bloku laty (zp_c, zp_r), gdy w tym samym ticku zebrano pierscien z drugiej polowki
; tego bloku (jego lata czeka na nastepny tick, uklad ma juz bit skasowany): oryginal pokazuje go do swojej laty,
; wiec polowka dochodzi do maski (M6.5: SS1, pierscienie co 16 px zebrane w kolejnych tickach). Zmienia X.
ring_block_pend
	jsr ring_row
	ldy zp_c
	lda (zp_lay),y
	tay
	lda RINGMASK_RAM,y
	tax                       ; X = maska polowek z ukladu
	lda g_screen_tile_replace_x+1
	bmi rbp_do                ; brak oczekujacej laty
	lda g_screen_tile_replace_data_ptr+1
	cmp #>TILEREPLACE_RING
	bne rbp_do
	lda g_screen_tile_replace_data_ptr
	cmp #<TILEREPLACE_RING
	bne rbp_do
	lda g_screen_tile_replace_x ; kolumna bloku = x >> 5 (8 bitow)
	lsr
	lsr
	lsr
	lsr
	lsr
	sta zp_t2
	lda g_screen_tile_replace_x+1
	asl
	asl
	asl
	ora zp_t2
	cmp zp_c
	bne rbp_do
	lda g_screen_tile_replace_y ; wiersz bloku = y >> 5
	lsr
	lsr
	lsr
	lsr
	lsr
	sta zp_t2
	lda g_screen_tile_replace_y+1
	asl
	asl
	asl
	ora zp_t2
	cmp zp_r
	bne rbp_do
	lda g_screen_tile_replace_x ; polowka oczekujacego pierscienia: ((x >> 4) & 1) + 1 (b0 lewa, b1 prawa)
	lsr
	lsr
	lsr
	lsr
	and #1
	tay
	txa
	ora bit_tab,y             ; bit_tab: 1, 2, 4...
	tax
rbp_do
	txa
	beq rbp_ret
	jmp ring_halves
rbp_ret
	rts

; ring_halves: A = maska polowek bloku zp_c (b0 lewa, b1 prawa) -> BCB pierscienia (ring_row ustawione).
; Zachowuje X.
ring_halves
	sta zp_t3
	lsr zp_t3                 ; b0: lewa polowka
	bcc rgh_right
	lda #0
	jsr emit_ring
rgh_right
	lsr zp_t3                 ; b1: prawa polowka
	bcc rgh_ret
	lda #16
	jmp emit_ring
rgh_ret
	rts

; emit_ring: BCB klatka (v_er_src, 16x16, stride 16) -> pierscien tla: blok (zp_c & 15, wiersz z ring_row),
; x + A (0 / 16), y + 8. Pola stale (rozmiar, kroki) tylko, gdy slot mial inny rodzaj BCB (KIND_RAM).
; Zachowuje X.
emit_ring
	sta zp_t1
	jsr next_slot
	inc v_nring
	lda KIND_RAM,y            ; M3.8c: pola stale tylko, gdy slot mial inny rodzaj BCB
	cmp #K_RING
	beq er_var
	lda #K_RING
	sta KIND_RAM,y
	ldy #0
	tya
	sta (zp_bcb),y            ; src lo = 0
	ldy #2
	lda #RINGART_VRAM>>16
	sta (zp_bcb),y
	iny
	lda #16
	sta (zp_bcb),y            ; krok y zrodla
	ldy #9
	lda #<512                 ; krok Y celu (pierscien tla) - slot mogl byc BCB znaku HUD-u (M3.7c)
	sta (zp_bcb),y
	iny
	lda #>512
	sta (zp_bcb),y
	ldy #12
	lda #15
	sta (zp_bcb),y            ; szerokosc 16
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda #15
	sta (zp_bcb),y            ; wysokosc 16
er_var                          ; pola zmienne: klatka, cel
	ldy #1
	lda v_er_src
	sta (zp_bcb),y            ; src mid = RINGART + klatka * 256
	lda zp_c                  ; dst lo = (c & 7) << 5 + polowka
	and #7
	lsr
	ror
	ror
	ror
	ora zp_t1
	ldy #6
	sta (zp_bcb),y
	lda zp_c                  ; dst mid = ((c >> 3) & 1) | v_er_mid
	lsr
	lsr
	lsr
	and #1
	ora v_er_mid
	iny
	sta (zp_bcb),y
	lda v_er_hi
	iny
	sta (zp_bcb),y
	rts
