; =====================================================================
;  tables.asm - dane stale renderera: adresy buforow, offsety palet cyklu, tablice slotow list,
;  XDL-e i szablony BCB (pola stale; zmienne pola patchuje CPU w frame.asm)
; =====================================================================
fb_mid	dta b([FB0_VRAM>>8]&$FF), b([FB1_VRAM>>8]&$FF)   ; bajt srodkowy adresu bufora 0/1
fb_hi	dta b(FB0_VRAM>>16), b(FB1_VRAM>>16)              ; bajt starszy (bit 16+)
	.if [[FB0_VRAM>>8]&$FF]=[[FB1_VRAM>>8]&$FF]
	.error "M7.5: klucze pamieci VM / PM / SM / zh_* rozpoznaja bufor po v_fbm - fb_mid obu buforow musi byc rozny"
	.endif
cyc_off	dta b(48), b(96), b(144), b(192)                 ; PAL_RAM: warianty cyklu wody (po 48 B RGB)
ball_rgb dta b(255,208,32), b(224,112,16), b(255,255,208) ; kolory 64-66 kulki testowej

; sloty listy ramki (M4.2): adres slotu = baza kompletu + slot * BCB_BYTES (slot 0..N_SLOTS-1 < 256);
; komplety w roznych oknach MEMAC (set_mb), rodzaj BCB (KIND_RAM) tylko dla slotow blokow: baza set_kind
mul21_lo
	.rept N_SLOTS
	dta b([#*BCB_BYTES]&$FF)
	.endr
mul21_hi
	.rept N_SLOTS
	dta b([#*BCB_BYTES]>>8)
	.endr
set_cpu_lo	dta b(<LIST_CPU), b(<LIST2_CPU)
set_cpu_hi	dta b(>LIST_CPU), b(>LIST2_CPU)
set_vram_lo	dta b(LIST_VRAM&$FF), b(LIST2_VRAM&$FF)
set_vram_mid	dta b([LIST_VRAM>>8]&$FF), b([LIST2_VRAM>>8]&$FF)
set_vram_hi	dta b(LIST_VRAM>>16), b(LIST2_VRAM>>16)
set_mb	dta b(MB_LOW), b(MB_BUILD)
set_kind	dta b(0), b(N_BLK_SLOTS)
set_skind	dta b(0), b(N_SPR_SLOTS)   ; M4.9a: baza SKIND_RAM kompletu (sloty sprite'ow obiektow)

; XDL bufora 0 i 1 (docs/vbxe-rejestry.md): 24 linie bez nakladki (OVOFF|RPTL), obraz 192 linie SR 256 px w dwoch wpisach
; (GMON|MAPOFF|RPTL|OVADR + ATT: adres i stride 256 bufora, misc $10 = paleta 1 nakladki, $20 = paleta 2; szerokosc narrow;
; priorytet $FF), 24 linie bez nakladki i END. M6.8: drugi wpis obrazu = woda Labyrinth (paleta 2 - podwodna) od linii podzialu
; (render/water.asm: xdl_water patchuje XDL_N1, XDL_M1, XDL_N2, XDL_A2M, XDL_A2H, XDL_M2 przed flipem); bez wody 191 + 1 linii
; z paleta 1 (obraz jak jeden wpis). Adres drugiego wpisu = bufor + n1 * 256.
XDL_N1  = 5                     ; liczba linii pierwszego wpisu obrazu - 1
XDL_M1  = 11                    ; misc pierwszego wpisu (paleta)
XDL_N2  = 15                    ; liczba linii drugiego wpisu - 1
XDL_A2M = 17                    ; adres VRAM drugiego wpisu: bajt srodkowy i starszy
XDL_A2H = 18
XDL_M2  = 21                    ; misc drugiego wpisu
xdl0
	dta a($0024),b(23)
	dta a($0872),b(190)
	dta a(FB0_VRAM&$FFFF),b(FB0_VRAM>>16),a(256)
	dta b($10),b($FF)
	dta a($0872),b(0)
	dta a([FB0_VRAM+191*256]&$FFFF),b([FB0_VRAM+191*256]>>16),a(256)
	dta b($10),b($FF)
	dta a($8024),b(23)
xdl0_end
xdl1
	dta a($0024),b(23)
	dta a($0872),b(190)
	dta a(FB1_VRAM&$FFFF),b(FB1_VRAM>>16),a(256)
	dta b($10),b($FF)
	dta a($0872),b(0)
	dta a([FB1_VRAM+191*256]&$FFFF),b([FB1_VRAM+191*256]>>16),a(256)
	dta b($10),b($FF)
	dta a($8024),b(23)
xdl1_end
	.if xdl0_end-xdl0 > 32 .or xdl1_end-xdl1 > 32
	.error "XDL bufora dluzszy niz 32 B (XDL1_VRAM = XDL0_VRAM + $20)"
	.endif

; blok magazyn -> pierscien: src stride 32, dst stride 512, 32x32, kopia, NEXT
blk_tpl
	dta b(0),b(0),b(STORE_VRAM>>16), a(32),b(1)
	dta b(0),b(0),b(RING_VRAM>>16), a(512),b(1)
	dta a(31),b(31)
	dta b($FF,$00,$00,$00,$00,$08)
; widok: pierscien (stride 512) -> bufor (stride 256)
view_tpl
	dta b(0),b(0),b(RING_VRAM>>16), a(512),b(1)
	dta b(0),b(0),b(0), a(256),b(1)
	dta a(255),b(191)
	dta b($FF,$00,$00,$00,$00,$08)
; kulka (stencil)
ball_tpl
	dta a(SPRITE_VRAM&$FFFF),b(SPRITE_VRAM>>16), a(BALL_SIZE),b(1)
	dta b(0),b(0),b(0), a(256),b(1)
	dta a(BALL_SIZE-1),b(BALL_SIZE-1)
	dta b($FF,$00,$00,$00,$00,$09)
; priorytet: magazyn (stride 32) -> bufor (stride 256), stencil
prio_tpl
	dta b(0),b(0),b(STORE_VRAM>>16), a(32),b(1)
	dta b(0),b(0),b(0), a(256),b(1)
	dta a(0),b(0)
	dta b($FF,$00,$00,$00,$00,$09)
; budowa magazynu: atlas (stride 8) -> blok (stride 32), 8x8
build_tpl
	dta b(0),b(0),b(ATLAS_VRAM>>16), a(8),b(1)
	dta b(0),b(0),b(STORE_VRAM>>16), a(32),b(1)
	dta a(7),b(7)
	dta b($FF,$00,$00,$00,$00,$08)

; M4.2 pusty BCB 1x1 slotu sprite'a obiektu (render/objspr.asm): M4.9a - stan K_NOPA rodziny atlasu: zrodlo ZERO_VRAM
; (bajt 0, stencil nic nie rysuje), krok Y zrodla 8, krok X 1, cel SCRATCH (krok 256 jak bufor obrazu), stencil + NEXT;
; sprite tej rodziny pisze w slocie tylko pola zmienne (zrodlo lo/mid, cel, rozmiar)
nop_tpl
	dta b(<ZERO_VRAM),b([ZERO_VRAM>>8]&$FF),b(ZERO_VRAM>>16), a(8),b(1)
	dta b(<SCRATCH_VRAM),b([SCRATCH_VRAM>>8]&$FF),b(SCRATCH_VRAM>>16), a(256),b(1)
	dta a(0),b(0)
	dta b($FF,$00,$00,$00,$00,$09)
