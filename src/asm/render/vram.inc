; --- mapa VRAM ---
XDL0_VRAM    = $00000
XDL1_VRAM    = $00020
SPRITE_VRAM  = $00400      ; kulka 32x32
LIST_VRAM    = $00800      ; komplet 0 listy ramki, N_SLOTS BCB (M6.8: 250 BCB = 5250 B, do $01C81), okno MB_LOW
LIST2_VRAM   = $1E000      ; komplet 1 (potok: lista N biegnie, CPU buduje N+1 w drugim) - M4.2: w obszarze listy
                           ; budowy magazynu (uzywanej tylko przy budowie magazynu, przed init_list_set 1), do
                           ; $1F481 (M6.8), okno MB_BUILD; lista przeladowania $1F800 zostaje
SCRATCH_VRAM = $003F0      ; cel pustych prostokatow widoku (1 bajt; za XDL-ami, przed kulka $00400)
XDLB_VRAM    = $00040      ; M6: XDL ekranu z wylaczonym obrazem - 192 linie z jednej linii BLANKL_VRAM (krok 0)
BLANKL_VRAM  = $00100      ; M6: linia 256 B w kolorze ramki (16) dla XDLB (src/scr/ekrany.asm)
FB0_VRAM     = $02000      ; 256x192, stride 256
FB1_VRAM     = $0E000
ATLAS_VRAM   = $1A000      ; 256 kafli x 64 B (stride 8)
BUILD_VRAM   = $1E000      ; lista budowy magazynu: 256 BCB
RELOAD_VRAM  = $1F800      ; lista przeladowania pierscienia: 63 BCB
RING_VRAM    = $20000      ; 512x256, stride 512
STORE_VRAM   = $40000      ; blok k: STORE + k*1024 (32x32, stride 32)
SONIC_VRAM   = $6E000      ; obrazy klatek Sonica 24x32 (stride 24, $300 B): 42 w prawo + nielustrzane w lewo (M3.6)
SPRATLAS_VRAM = $78800     ; kafle sprite'ow SMS 8x8 (stride 8): sprite 8x16 n = kafle n, n+1 = 128 B ciagle (M3.6)
RINGART_VRAM = $7F000      ; 6 klatek pierscienia 16x16 (stride 16): klatka k pod + k*256 (M3.5)
HUD_VRAM     = $7C800      ; M3.7c: plotna HUD-u (napisy ze sprite'ow 8x16, render/hud.asm)
HUD_LIVES_VRAM = $7C800    ; zycia 32x16 (krok 32)
HUD_TOP_VRAM = $7CA00      ; pierscienie i czas 36x32 (krok HUD_TOP_STR, do $7D1FF): ikona (0, 0), cyfry (20, 0)
HUD_TOP_STR  = 64
HUD_TIME_VRAM = HUD_TOP_VRAM+16*HUD_TOP_STR+4 ; czas M:SS 32x16 w plotnie pierscieni: (4, 16)
RCHAIN_VRAM  = $7D200      ; M3.8b: lancuch pierscieni - 2 + 128 BCB (2730 B, do $7DCA9), render/rchain.asm
RCUR2_VRAM   = $7DE00      ; biezaca klatka pierscienia 2 x obok siebie, 32x16 (krok 32, do $7DFFF)
ZERO_VRAM    = $7EFF0      ; M4.9a: bajt 0 (zerowany w init_lists) - zrodlo pustego BCB 1x1 slotu sprite'a (stencil:
                           ; piksel 0 nic nie rysuje); $7E000-$7E1FF zostaja na kopie kafli ikon monitorow (M4.5)

MEMAC_CPU    = $2000
MEMAC_CTL_V  = $29         ; baza $2000, CPU, 8 KiB
MB_LOW       = $80         ; VRAM $00000-$01FFF
MB_ATLAS0    = $9A         ; VRAM $1A000
MB_ATLAS1    = $9C         ; VRAM $1C000
MB_BUILD     = $9E         ; VRAM $1E000-$1FFFF
MB_RINGART   = $FE         ; VRAM $7E000-$7FFFF
MB_HUD       = $FC         ; VRAM $7C000-$7DFFF (plotna HUD-u)
MB_SPRMON    = $F8         ; M4.5: VRAM $78000-$79FFF - kafle $5C-$5F atlasu sprite'ow (ikony monitorow)
MONTILES_CPU = MEMAC_CPU+[SPRATLAS_VRAM+$5C*64-$78000] ; okno MB_SPRMON: kafle $5C-$5F (256 B)
MB_SONIC     = $EE         ; VRAM $6E000 - poczatek obrazow Sonica (rozpakowanie przesuwa okno co 8 KiB)
RINGART_CPU  = MEMAC_CPU+[RINGART_VRAM-$7E000]
LIST_CPU     = MEMAC_CPU+LIST_VRAM                ; okno MB_LOW
LIST2_CPU    = MEMAC_CPU+[LIST2_VRAM-BUILD_VRAM]  ; okno MB_BUILD
SPRITE_CPU   = MEMAC_CPU+SPRITE_VRAM
BUILD_CPU    = MEMAC_CPU
RELOAD_CPU   = MEMAC_CPU+[RELOAD_VRAM-BUILD_VRAM]
RCHAIN_CPU   = MEMAC_CPU+[RCHAIN_VRAM-$7C000] ; okno MB_HUD

; BCB (blitter control block) VBXE, 21 B: +0 src (3), +3 krok y src (2), +5 krok x src (1), +6 dst (3),
; +9 krok y dst (2), +11 krok x dst (1), +12 szerokosc-1 (2), +14 wysokosc-1 (1), +15 maska AND, +16 XOR,
; +17 maska kolizji, +18 zoom, +19 wzorzec, +20 sterowanie (bity 0-2 tryb: 0 kopia, 1 stencil - kolor 0
; przezroczysty; bit 3 NEXT = kolejny BCB po tym)
BCB_BYTES    = 21
N_BLK_SLOTS  = 64          ; doladowanie (do 16 blokow) + lata (1) + polowki z pierscieniem (do 47)
SLOT_VIEW    = N_BLK_SLOTS
SLOT_SPR     = SLOT_VIEW+4 ; M4.2: sprite'y 8x16 obiektow z tablicy sprite'ow SMS (wpisy za HUD-em) - staly obszar
N_SPR_SLOTS  = 40          ; pod HUD-em i Sonikiem; nieuzyte sloty = BCB pusty 1x1 (lancuch BCB jest ciagly)
N_OBJ_SLOTS  = 22          ; M6.8: + 13 przednich wpisow tablicy SMS przy wodzie (render/sprites.asm front_objs); obiekty: kulka testowa albo Sonic (24x32), 2 sprite'y sprezyny, 2 iskry pierscienia, iskra niesmiertelnosci (M4.5),
                           ; do 3 x HUD (M3.7c: zycia, pierscienie z czasem albo osobno) - HUD zawsze od SLOT_OBJ
N_RECTS      = 30          ; prostokaty priorytetu tla (or_*): Sonic, HUD - do 4 napisow; M4.2: obiekty (obwiednia
                           ; wpisow jednego wywolania draw_sprite_string / draw_sprite, kawalki <= 32x32)
SLOT_OBJ     = SLOT_SPR+N_SPR_SLOTS ; obiekty od SLOT_OBJ, zaraz za nimi czesci blokow z priorytetem
SLOT_PRIO    = SLOT_OBJ+N_OBJ_SLOTS ; szablon prio_tpl od tego slotu (pola stale i tak ustawia prio_part)
N_SLOTS      = SLOT_PRIO+4*N_RECTS ; M6.8: 250 BCB = 5250 B na komplet (indeks slotu < 256)
	.if N_SLOTS > 256
	.error "N_SLOTS > 256 (indeks slotu w bajcie)"
	.endif
	.if LIST_VRAM+N_SLOTS*BCB_BYTES > FB0_VRAM
	.error "komplet 0 listy ramki nachodzi na FB0"
	.endif
	.if LIST2_VRAM+N_SLOTS*BCB_BYTES > RELOAD_VRAM
	.error "komplet 1 listy ramki nachodzi na liste przeladowania"
	.endif
N_GROUPS     = 32          ; M4.2: grupy wpisow tablicy sprite'ow (wywolania rysowania obiektow) w ticku; M6.10: 24 -> 32 (zappery $46 SKY3 - do 24 draw_sprite w ticku)
RELOAD_N     = 63          ; 9 kolumn x 7 wierszy
K_OTHER      = 0           ; KIND_RAM: rodzaj BCB w slocie (M3.8c) - inny (znak HUD-u)
K_BLOCK      = 1           ; blok 32x32 magazyn -> pierscien (emit_block)
K_RING       = 2           ; polowka pierscienia 16x16 (emit_ring)
; M4.9a: rodzaj BCB slotu sprite'a obiektu (SKIND_RAM, render/objspr.asm). Rodzina atlasu (0-2): krok Y zrodla 8,
; krok X 1, src hi = SPRATLAS_VRAM >> 16; rodzina klatki Sonica (3-4): krok Y 24, krok X i src hi zmienne.
; Pusty = zrodlo ZERO_VRAM, 1x1 (szerokosc i wysokosc 0), reszta pol jak sprite rodziny.
K_NOPA       = 0           ; pusty, rodzina atlasu (stan poczatkowy: nop_tpl)
K_SPRA       = 1           ; sprite z atlasu w calosci na ekranie (8x16: szerokosc 7, wysokosc 15 stale)
K_SPRC       = 2           ; sprite z atlasu przyciety (szerokosc, wysokosc zmienne)
K_NOPS       = 3           ; pusty, rodzina klatki Sonica
K_SPRS       = 4           ; wycinek klatki Sonica (kafle $B4-$BF)
