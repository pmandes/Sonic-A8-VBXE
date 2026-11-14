; =====================================================================
;  sprites.asm - obiekty w liscie ramki (M3.6): Sonic z grafiki SMS, sprite'y 8x16 (sprezyna, iskra
;  pierscienia), kulka testowa M2 (tryby kamery 0-2) i priorytet tla nad nimi.
;
;  Oryginal (s1smsdisasm-gm): return_from_objfunc 00:34E6 - pozycja ekranowa = obiekt - przewijanie,
;  draw_sprite_string 00:350F (mapa: do 3 wierszy po 6 sprite'ow 8x16, $FF konczy wiersz/mape, $FE pusty):
;   - wiersz pomijany, gdy y < -16; konczy rysowanie, gdy y >= 192 (y = 16 bit);
;   - sprite pomijany w calosci, gdy x poza 0..255 (odcinanie co 8 px, nie przycinanie);
;  draw_sprite 00:3581 (pojedynczy sprite, te same reguly). VDP rysuje sprite o linie nizej (Y + 1),
;  wiec Sonic ze stanem (x, y) stoi na ekranie w (x - scroll_x, y - scroll_y + 1).
;  Sonic: mapa SPRITEMAP_sonic_normal = 3 x 2 sprite'y z kafli $B4-$BF, ktore IRQ (00:37E0) wypelnia grafika
;  klatki g_new_sonic_sprite_ptr. Tu: gotowy obraz klatki 24x32 w VRAM (SONIC_VRAM) i jeden blit - kolumny
;  odciete co 8 px, wiersze przyciete do ekranu (rownowazne regulom wierszy). Klatki "w lewo" bedace lustrem
;  prawych: obraz prawy czytany od prawej krawedzi (krok X zrodla = -1).
;  Kolejnosc (priorytet SMS: wczesniejszy sprite na wierzchu): iskra (rysowana w funkcji Sonica) nad
;  Sonikiem - tu blity w kolejnosci Sonic, sprezyna, iskra; potem bloki z priorytetem tla nad wszystkimi.
; =====================================================================

; ---------------------------------------------------------------------
; load_sprite_data: banki 37/39 -> VRAM: obrazy klatek Sonica (42 w prawo, LV_SONIC_OWN w lewo), kafle
; sprite'ow (256 x 8x8) - ciagiem od SONIC_VRAM (2 piksele/bajt, piksel != 0 -> +16: paleta sprite'ow VBXE
; 16-31); tablica klatek -> SONICFR_RAM; paleta sprite'ow SMS -> kolory 16-31 palety 1 nakladki.
; ---------------------------------------------------------------------
load_sprite_data
	lda #MB_SONIC
	sta v_mb
	jsr set_memac
	mwa #MEMAC_CPU+[SONIC_VRAM&$1FFF] zp_dst
	lda #PB_SONIC             ; bank 37: klatki w prawo
	sta PORTB
	mwa #BANK_WIN zp_src
	mwa #LV_SONIC_FR*384 zp_cnt
	jsr unpack_spr
	lda #PB_SPR               ; bank 39: klatki w lewo (dalej w VRAM), potem kafle sprite'ow = SPRATLAS_VRAM
	sta PORTB
	mwa #BANK_WIN zp_src
	mwa #LV_SONIC_OWN*384 zp_cnt
	jsr unpack_spr
	lda v_pbzspr              ; M6.6: kafle sprite'ow strefy z banku strefy (GHZ: 39, Bridge: 3; M7.2: ldr_need - src/ldr/ldr.asm)
	sta PORTB
	mwa #BANK_WIN+LS_SPRTILES zp_src
	mwa #256*32 zp_cnt
	jsr unpack_spr
	lda v_special             ; M6.5: etap specjalny - kafle $00-$7F z banku 59
	beq lsd_nosp
	jsr spr_special_tiles
lsd_nosp
	lda #PB_SPR               ; (spr_special_tiles zmienia PORTB)
	sta PORTB
	lda #1                    ; tablica klatek (168 B) -> SONICFR_RAM
	sta zp_cnt
	lda #>[BANK_WIN+LS_FRTAB]
	ldx #>SONICFR_RAM
	jsr copy_pages
	lda v_pbzspr              ; M6.6: paleta sprite'ow strefy (bank strefy, LS_PALSPR)
	sta PORTB
	ldy #VC_PSEL              ; paleta sprite'ow -> kolory 16-31 palety 1
	lda #1
	sta (zp_fx),y
	ldy #VC_CSEL
	lda #16
	sta (zp_fx),y
	ldx #0
lsd_pal
	lda BANK_WIN+LS_PALSPR,x
	sta SPRPAL_RAM,x          ; kopia do wygaszania (M3.7: bank 39 nadpisuje potem bufor trace'u)
	ldy #VC_CR
	sta (zp_fx),y
	lda BANK_WIN+LS_PALSPR+1,x
	sta SPRPAL_RAM+1,x
	iny
	sta (zp_fx),y
	lda BANK_WIN+LS_PALSPR+2,x
	sta SPRPAL_RAM+2,x
	iny
	sta (zp_fx),y
	inx
	inx
	inx
	cpx #48
	bne lsd_pal
	lda v_special             ; M6.5: paleta sprite'ow etapu specjalnego (bank 59 $2030) -> SPRPAL_RAM i kolory 16-31
	beq lsd_nosp2
	jsr spr_zone_pal
	jsr spr_pal_out
lsd_nosp2
	lda #MB_SPRMON            ; M4.5: kafle $5C-$5F grafiki strefy -> bank 47 (OA_MONZONE): mon_tiles odtwarza je
	jsr set_memac             ; przy starcie poziomu (oryginal laduje grafike strefy na nowo)
	lda #PB_OBJART
	sta PORTB
	ldx #0
lsd_mz
	lda MONTILES_CPU,x
	sta BANK_WIN+OA_MONZONE,x
	inx
	bne lsd_mz
	ldx #15                   ; kafle w atlasie i stan logiki: grafika strefy
	lda #$FF
lsd_mk
	sta v_monk,x
	sta v_monk_ap,x
	dex
	bpl lsd_mk
	lda #MB_LOW
	jsr set_memac
	lda #PB_MAIN
	sta PORTB
	rts

; ---------------------------------------------------------------------
; sign_tiles (M4.8): w frame_done (blitter wolny) - v_sign_req: 8 KiB grafiki tabliczki (bank 47 OA_SIGN, 8 bpp)
; pod kafle $00-$7F atlasu sprite'ow (load_art 00:0405 w objfunc_07_signpost; okna MEMAC $78000 i $7A000),
; kafle $5C-$5F = tabliczka (v_monk_ap = $FE), paleta po nastepnej liscie (v_sign_pal: obraz tej listy
; z nowa grafika pokazuje sie po flipie). v_zone_req: grafika sprite'ow strefy $00-$7F z banku 39 (restart po
; tabliczce; paleta - level_init / pal_fade). Kopia trwa kilka ramek - oryginal tez traci tu ramki (load_art).
; ---------------------------------------------------------------------
sign_tiles
	jsr flash_apply           ; M6.4: migotanie palety (handle_palette_flashing)
	lda v_art_req             ; M6.4: grafika bossa / zwierzat
	jne art_tiles
	lda v_sign_req
	beq stl_zone
	lda #0
	sta v_sign_req
	sta v_pal_which           ; paleta tabliczki
	lda #PB_OBJART
	sta PORTB
	lda #MB_SPRMON            ; VRAM $78800-$79FFF (6 KiB) <- bank 47 OA_SIGN
	jsr set_memac
	lda #24
	sta zp_cnt
	lda #>[BANK_WIN+OA_SIGN]
	ldx #>[MEMAC_CPU+[SPRATLAS_VRAM-$78000]]
	jsr copy_pages
	lda #MB_SPRMON+2          ; VRAM $7A000-$7A7FF (2 KiB)
	jsr set_memac
	lda #8
	sta zp_cnt
	lda #>[BANK_WIN+OA_SIGN+$1800]
	ldx #>MEMAC_CPU
	jsr copy_pages
	lda #PB_MAIN
	sta PORTB
	lda #MB_LOW
	jsr set_memac
	ldx #15                   ; kafle $5C-$5F w atlasie = tabliczka
	lda #$FE
stl_ap
	sta v_monk_ap,x
	dex
	bpl stl_ap
	lda #1
	sta v_sign_art
	lda #2
	sta v_sign_pal
	rts
stl_zone
	lda v_zone_req
	beq stl_pal
	lda #0
	sta v_zone_req
	sta v_sign_art
	lda v_special             ; M6.5: etap specjalny - kafle $00-$7F z banku 59
	beq stl_nsp
	jsr spr_special_tiles
	jmp stl_zdone
stl_nsp
	lda #MB_SPRMON            ; unpack_spr: 4 KiB spakowanych (kafle $00-$7F) od VRAM $78800 (okno przesuwa sie)
	sta v_mb
	jsr set_memac
	mwa #MEMAC_CPU+[SPRATLAS_VRAM-$78000] zp_dst
	lda v_pbzspr              ; M6.6: grafika sprite'ow strefy $00-$7F (restart po tabliczce)
	sta PORTB
	mwa #BANK_WIN+LS_SPRTILES zp_src
	mwa #128*32 zp_cnt
	jsr unpack_spr
stl_zdone
	lda #PB_MAIN
	sta PORTB
	lda #MB_LOW
	jsr set_memac
	ldx #15                   ; kafle $5C-$5F w atlasie = grafika strefy
	lda #$FF
stl_zp
	sta v_monk_ap,x
	dex
	bpl stl_zp
	lda #1
	sta v_mondirty
	rts
stl_pal
	lda v_sign_pal
	beq stl_ret
	dec v_sign_pal
	bne stl_ret
	lda v_pal_which
	bne stl_pboss
	lda #PB_OBJART            ; paleta tabliczki -> SPRPAL_RAM (wygaszanie) i kolory 16-31 palety 1
	sta PORTB
	ldx #47
stl_pc
	lda BANK_WIN+OA_SIGNPAL,x
	sta SPRPAL_RAM,x
	dex
	bpl stl_pc
	jmp stl_pdone
stl_pboss                       ; M6.4: paleta bossa (PAL2_boss, bank 59 $2000)
	lda #PB_BOSS
	sta PORTB
	ldx #47
stl_pb
	lda BANK_WIN+$2000,x
	sta SPRPAL_RAM,x
	dex
	bpl stl_pb
stl_pdone
	lda #PB_MAIN
	sta PORTB
spr_pal_out                     ; SPRPAL_RAM -> kolory 16-31 palety 1 (cykl palety tla w NMI wstrzymany na czas zapisu)
	lda v_cyc_on
	pha
	lda #0
	sta v_cyc_on
	ldy #VC_PSEL
	lda #1
	sta (zp_fx),y
	ldy #VC_CSEL
	lda #16
	sta (zp_fx),y
	ldx #0
stp_l
	ldy #VC_CR
	lda SPRPAL_RAM,x
	sta (zp_fx),y
	iny
	lda SPRPAL_RAM+1,x
	sta (zp_fx),y
	iny
	lda SPRPAL_RAM+2,x
	sta (zp_fx),y
	inx
	inx
	inx
	cpx #48
	bne stp_l
	pla
	sta v_cyc_on
stl_ret
	rts

; ---------------------------------------------------------------------
; art_tiles (M6.4): v_art_req = 1 - grafika bossa GHZ3 (ART_09_AEB1, bank 59 $0000), 2 - zwierzat i kapsuly
; (ART_0C_DA28, bank 59 $1000): 4 KiB spakowanych 4 bpp -> kafle $00-$7F atlasu sprite'ow (jak grafika strefy);
; kafle ikon monitorow $5C-$5F = ta grafika (v_monk_ap = $FD); boss - paleta PAL2_boss po nastepnej liscie
; (v_pal_which = 1). v_sign_art = 1: po restarcie poziomu grafika i paleta strefy wracaja (level_init).
; ---------------------------------------------------------------------
art_tiles
	ldx v_art_req
	lda #0
	sta v_art_req
	lda art_sa-1,x
	sta v_sign_art            ; 2 - boss (takze BRI3), 3 - zwierzeta (1 - tabliczka)
	lda art_src_hi-1,x
	sta zp_src+1
	lda #0
	sta zp_src
	lda art_src_pb-1,x
	bne ats_pb
	lda v_pbzspr              ; M6.9: 0 = bank sprite'ow strefy (Robotnik ART_0C_EF3F pod $0000 - SBZ, SKY)
ats_pb
	pha
	lda #MB_SPRMON
	sta v_mb
	jsr set_memac
	mwa #MEMAC_CPU+[SPRATLAS_VRAM-$78000] zp_dst
	pla
	sta PORTB
	mwa #128*32 zp_cnt
	jsr unpack_spr
	lda #PB_MAIN
	sta PORTB
	lda #MB_LOW
	jsr set_memac
	ldx #15                   ; kafle $5C-$5F w atlasie = grafika bossa / zwierzat
	lda #$FD
atl_ap
	sta v_monk_ap,x
	dex
	bpl atl_ap
	lda v_sign_art
	cmp #2
	bne atl_ret
	lda #1                    ; boss: paleta PAL2_boss
	sta v_pal_which
	lda #2
	sta v_sign_pal
atl_ret
	rts
art_sa
	dta b(2, 3, 2, 2)
art_src_hi
	dta b(>BANK_WIN, >[BANK_WIN+$1000], >[BANK_WIN+OA_BOSS3], >BANK_WIN)
art_src_pb                      ; M6.6: zadanie 3 - grafika bossa BRI3 z banku 47 (OA_BOSS3); M6.9: 4 - Robotnik (0 = v_pbzspr, $0000)
	dta b(PB_BOSS, PB_BOSS, PB_OBJART, 0)

; ---------------------------------------------------------------------
; flash_apply (M6.4): handle_palette_flashing (00:1F06) - kolor CRAM o indeksie v_flash_idx (b7 = paleta sprite'ow:
; kolory 16-31) = kolor migotania g_pal_flash_color_value (--BBGGRR) przy v_flash_odd = 1, inaczej kolor palety
; (SPRPAL_RAM / PAL_RAM, wariant 0). Cykl palety tla w NMI wstrzymany na czas zapisu (jak spr_pal_out).
; ---------------------------------------------------------------------
flash_apply
	lda v_flash_req
	jeq fla_ret
	lda #0
	sta v_flash_req
	lda v_flash_idx
	and #$7F
	sta zp_t0                 ; indeks 0..15
	asl
	clc
	adc zp_t0
	tax                       ; 3 * indeks
	lda v_flash_idx
	bmi fla_spr
	lda PAL_RAM,x
	sta zp_t1
	lda PAL_RAM+1,x
	sta zp_t2
	lda PAL_RAM+2,x
	sta zp_t3
	lda zp_t0
	jmp fla_col
fla_spr
	lda SPRPAL_RAM,x
	sta zp_t1
	lda SPRPAL_RAM+1,x
	sta zp_t2
	lda SPRPAL_RAM+2,x
	sta zp_t3
	lda zp_t0
	clc
	adc #16
fla_col
	sta zp_lay                ; numer koloru CRAM (zp_lay wolny poza budowa listy)
	lda v_flash_odd
	beq fla_wr
	lda g_pal_flash_color_value ; kolor migotania SMS --BBGGRR -> RGB (skladowa * 85)
	and #3
	tax
	lda fl_c85,x
	sta zp_t1
	lda g_pal_flash_color_value
	lsr
	lsr
	and #3
	tax
	lda fl_c85,x
	sta zp_t2
	lda g_pal_flash_color_value
	lsr
	lsr
	lsr
	lsr
	and #3
	tax
	lda fl_c85,x
	sta zp_t3
fla_wr
	lda v_cyc_on
	pha
	lda #0
	sta v_cyc_on
	ldy #VC_PSEL
	lda #1
	sta (zp_fx),y
	ldy #VC_CSEL
	lda zp_lay
	sta (zp_fx),y
	ldy #VC_CR
	lda zp_t1
	sta (zp_fx),y
	iny
	lda zp_t2
	sta (zp_fx),y
	iny
	lda zp_t3
	sta (zp_fx),y
	lda v_water               ; M6.8: poziom z woda - ten sam kolor palety 2 (podwodnej): migotanie albo kolor z WATERPAL_RAM
	beq fla_nw                ; (oryginal pisze CRAM po zaladowaniu palety w IRQ - miganie widac tez pod woda). Roznica: w fazie bez
	                          ; migniecia oryginal (00:1F21) wpisuje kolor z g_current_displayed_palette (nad woda), widoczny pod woda
	                          ; do nastepnego VBlank (czesc klatki) - port od razu kolor podwodny (docs/plan-m6.md 13.15)
	ldy #VC_PSEL
	lda #2
	sta (zp_fx),y
	ldy #VC_CSEL
	lda zp_lay
	sta (zp_fx),y
	lda v_flash_odd
	bne fla_w2
	lda zp_lay                ; kolor palety podwodnej: WATERPAL_RAM + 3 * numer
	asl
	clc
	adc zp_lay
	tax
	lda WATERPAL_RAM,x
	sta zp_t1
	lda WATERPAL_RAM+1,x
	sta zp_t2
	lda WATERPAL_RAM+2,x
	sta zp_t3
fla_w2
	ldy #VC_CR
	lda zp_t1
	sta (zp_fx),y
	iny
	lda zp_t2
	sta (zp_fx),y
	iny
	lda zp_t3
	sta (zp_fx),y
fla_nw
	pla
	sta v_cyc_on
fla_ret
	rts
fl_c85	dta b(0, 85, 170, 255)

; spr_zone_pal (M4.8): paleta sprite'ow strefy (bank strefy v_pbzspr, LS_PALSPR) -> SPRPAL_RAM (restart po tabliczce)
spr_zone_pal
	lda v_special             ; M6.5: etap specjalny - paleta z banku 59 ($2030)
	bne szp_sp
	lda v_pbzspr              ; M6.6: bank strefy
	sta PORTB
	ldx #47
szp_l
	lda BANK_WIN+LS_PALSPR,x
	sta SPRPAL_RAM,x
	dex
	bpl szp_l
	lda #PB_MAIN
	sta PORTB
	rts
szp_sp
	lda #PB_BOSS
	sta PORTB
	ldx #47
szp_s
	lda BANK_WIN+$2030,x
	sta SPRPAL_RAM,x
	dex
	bpl szp_s
	lda #PB_MAIN
	sta PORTB
	rts

; spr_special_tiles (M6.5): kafle sprite'ow etapow specjalnych (ART_09_A511, 128 kafli 4 bpp, bank 59 $2100) pod kafle
; $00-$7F atlasu sprite'ow (jak art_tiles); na koncu PORTB = PB_MAIN, MEMAC = MB_LOW.
spr_special_tiles
	lda #MB_SPRMON
	sta v_mb
	jsr set_memac
	mwa #MEMAC_CPU+[SPRATLAS_VRAM-$78000] zp_dst
	lda #PB_BOSS
	sta PORTB
	mwa #BANK_WIN+$2100 zp_src
	mwa #128*32 zp_cnt
	jsr unpack_spr
	lda #PB_MAIN
	sta PORTB
	lda #MB_LOW
	jmp set_memac

; ---------------------------------------------------------------------
; mon_tiles (M4.5): kafle $5C-$5F atlasu sprite'ow wg v_monk (write_partial_monitor_art 00:0C1D - obj/objs_d.asm).
; Wolane w frame_done: lista N skonczona, N+1 jeszcze nie ruszyla - blitter nie czyta atlasu. Pozycja p (0..15)
; = 16 B (2 wiersze kafla 8 bpp) pod MONTILES + 16 p: ikona k z banku 47 (OA_ICONS + 256 k + 16 p) albo
; grafika strefy (OA_MONZONE + 16 p) dla k = $FF. Kopiowane tylko pozycje rozne od v_monk_ap.
; ---------------------------------------------------------------------
mon_tiles
	lda v_mondirty
	bne mtl_go
	rts
mtl_go
	lda #0
	sta v_mondirty
	lda #MB_SPRMON
	jsr set_memac
	lda #PB_OBJART
	sta PORTB
	lda #>MONTILES_CPU
	sta zp_dst+1
	ldx #15
mtl_l
	lda v_monk,x
	cmp v_monk_ap,x
	beq mtl_n
	sta v_monk_ap,x
	cmp #$FD                  ; $FD: grafike zalozyl art_tiles - bez kopiowania
	beq mtl_n
	cmp #$FE
	bcc mtl_ik
	beq mtl_sg
	lda #[OA_MONZONE>>8]-[OA_ICONS>>8] ; $FF: grafika strefy
	bne mtl_ik
mtl_sg
	lda #[[OA_SIGN+$5C*64]>>8]-[OA_ICONS>>8] ; $FE: grafika tabliczki (M4.8)
mtl_ik
	clc
	adc #>[BANK_WIN+OA_ICONS]
	sta zp_src+1
	txa
	asl
	asl
	asl
	asl
	sta zp_src
	sta zp_dst
	ldy #15
mtl_c
	lda (zp_src),y
	sta (zp_dst),y
	dey
	bpl mtl_c
mtl_n
	dex
	bpl mtl_l
	lda #PB_MAIN
	sta PORTB
	lda #MB_LOW
	jmp set_memac

; unpack_spr: zp_cnt (16 bit) bajtow spakowanych spod zp_src -> 2 * zp_cnt pikseli od zp_dst (okno MEMAC
; $2000-$3FFF, bank v_mb; po $3FFF nastepne okno 8 KiB). Piksel != 0 -> +16. zp_cnt = 0 - nic.
unpack_spr
	lda zp_cnt
	ora zp_cnt+1
	beq us_ret
	ldy #0
	lda (zp_src),y
	tax
	lsr                       ; starsza polowka = lewy piksel
	lsr
	lsr
	lsr
	beq us_l0
	ora #$10
us_l0
	sta (zp_dst),y
	txa
	and #$0F
	beq us_r0
	ora #$10
us_r0
	iny
	sta (zp_dst),y
	inc zp_src
	bne us_s
	inc zp_src+1
us_s
	clc
	lda zp_dst
	adc #2
	sta zp_dst
	bcc us_d
	inc zp_dst+1
	lda zp_dst+1
	cmp #>[MEMAC_CPU+$2000]
	bne us_d
	lda #>MEMAC_CPU           ; koniec okna 8 KiB: nastepny bank MEMAC (VRAM + $2000)
	sta zp_dst+1
	inc v_mb
	inc v_mb
	lda v_mb
	jsr set_memac
us_d
	lda zp_cnt
	bne us_dec
	dec zp_cnt+1
us_dec
	dec zp_cnt
	jmp unpack_spr
us_ret
	rts

; ---------------------------------------------------------------------
; obj_bcbs: BCB obiektow (sloty SLOT_OBJ..) i priorytetu tla (SLOT_PRIO..) dla listy v_lbuild.
; Tryby kamery 0-2 (testy M2): kulka 32x32 w (v_sx, v_sy); 3-4: Sonic, sprezyna, iskra.
; zp_last = ostatni uzyty BCB (view_rects ustawia go na widok, gdy nie ma obiektow).
; ---------------------------------------------------------------------
obj_bcbs
	lda #SLOT_OBJ
	sta v_oslot
	lda #0
	sta v_nobj
	lda v_cam_mode
	cmp #CAM_FOLLOW
	bcs ob_game
	lda #0                    ; kulka w slocie HUD-u - pamiec BCB HUD-u niewazna (M3.8d)
	sta zh_sig
	sta zh_sig+1
	jsr ball_obj
	jmp ob_prio
ob_game
	lda v_hide_spr            ; M3.7: po wygaszeniu (clear_sprite_table) bez obiektow
	bne ob_prio
	jsr obj_sprites           ; M4.2: sprite'y obiektow (obszar SLOT_SPR - pod HUD-em i Sonikiem, render/objspr.asm)
	jsr hud_objs              ; M3.7c: HUD pod Sonikiem (render/hud.asm)
	lda v_throb               ; M6.5: zderzak etapu specjalnego w tym kroku - wpisy 0-7 tablicy (sh_bumper) zamiast Sonica
	beq ob_sonic
	jsr throb_obj
	jmp ob_afters
ob_sonic
	jsr front_digit_f         ; M6.8: woda - wpis 20 (cyfra tonienia) nad HUD-em i obiektami, pod Sonikiem (M7.5 Z5: render/prio.asm)
	jsr sonic_obj_m           ; M7.5 Z6: sonic_obj z pamiecia BCB (render/prio.asm)
ob_afters
	jsr upspring_objs
	jsr sparkle_objs
	jsr isparkle_obj          ; M4.5: iskra niesmiertelnosci (wczesniej w tablicy SMS - na wierzchu)
	jsr front_objs_f          ; M6.8: woda - przednie wpisy 0-11 tablicy SMS (linia wody, duze bable) na samym wierzchu (M7.5 Z5)
; M4.9a: okno blokow kamery (kolumny v_bx..v_bx+8) bez bloku z priorytetem (PRIOWIN_RAM, render/load.asm) ->
; zaden prostokat nie trafi na priorytet: bez grp_rects i prio_rect (GHZ1: priorytet tylko w kolumnach 110-111,
; 150-151). Prostokaty HUD-u (ho_prio) powstaja tylko przy priorytecie w oknie (hud_prio_near), wiec tez odpadaja.
	lda v_bx
	lsr
	lsr
	lsr
	tax
	lda v_bx
	and #7
	tay
	lda PRIOWIN_RAM,x
	and bit_tab,y
	beq ob_ret
	jsr prio_path             ; M7.5 Z1/Z4/Z5 (render/prio.asm; zamiast M6.10 v_ngrp >= 8 -> prio_blocks): C = 0 - priorytet calymi
	bcc ob_ret                ; blokami okna gotowy (BCB wprost albo z pamieci); C = 1 - obwiednie grup
ob_rects
	jsr grp_rects             ; M4.2: prostokaty priorytetu grup sprite'ow obiektow (po HUD-zie)
ob_prio                         ; priorytet tla nad kazdym prostokatem obiektu - sloty zaraz za ostatnim
	lda v_oslot               ; obiektem (lancuch BCB bez luk: nieuzyty slot ze starym NEXT wykonalby sie)
	sta v_pslot
	ldx #0
ob_prio_l
	cpx v_nobj
	beq ob_ret
	stx v_oi
	lda or_x,x
	sta v_ox
	lda or_y,x
	sta v_oy
	lda or_w,x
	sta v_ow
	lda or_h,x
	sta v_oh
	jsr prio_rect
	ldx v_oi
	inx
	bne ob_prio_l
ob_ret
	rts

; ball_obj: kulka testowa M2 (zawsze w calosci na ekranie): src SPRITE_VRAM 32x32
ball_obj
	lda #<SPRITE_VRAM
	sta v_osrc
	lda #>SPRITE_VRAM
	sta v_osrc+1
	lda #SPRITE_VRAM>>16
	sta v_osrc+2
	lda #BALL_SIZE
	sta v_ostride
	sta v_ow
	sta v_oh
	lda #1
	sta v_ostepx
	lda v_sx
	sta v_ox
	lda v_sy
	sta v_oy
	jmp obj_emit

; ---------------------------------------------------------------------
; sonic_obj: Sonic (wiersze 0-1 mapy) jako jeden blit z obrazu klatki
; ---------------------------------------------------------------------
sonic_obj
	lda object_list+OB_TYPE   ; M6.11: slot Sonika z typem $FF (poziom koncowy $12) - nie rysowac
	cmp #$FF
	beq so_ret0
	lda sonic_spritemap_ix_15
	ora sonic_spritemap_ix_15+1
	bne so_map
so_ret0
	rts                       ; mapa 0: nie rysowac (@fn_suppress_sprite_rendering)
so_map
	lda sonic_spritemap_ix_15
	cmp #<$592B               ; SPRITEMAP_sonic_hflip (do gory nogami, VESTIGIAL) - nie w grze
	bne so_frame
	inc v_spr_todo
so_frame                        ; pozycja tablicy klatek: kierunek * 42 + klatka
	lda v_sonic_fr
	cmp #LV_SONIC_FR
	bcc so_fr_ok
	inc v_spr_todo            ; klatka spoza grafiki Sonica (obiekty - M4)
	rts
so_fr_ok
	ldx v_sonic_base
	cpx #$70
	bne so_fr_r
	clc
	adc #LV_SONIC_FR
so_fr_r
	asl
	tax
	lda SONICFR_RAM,x
	sta v_fmid
	lda SONICFR_RAM+1,x
	sta v_fhi                 ; b7 = odbicie
; X = sonic_x - camx (16 bit), Y = sonic_y - camy (16 bit)
	sec
	lda sonic_x
	sbc v_camx
	sta v_sx16
	lda sonic_x+1
	sbc v_camx+1
	sta v_sx16+1
	sec
	lda sonic_y
	sbc v_camy
	sta v_sy16
	lda sonic_y+1
	sbc v_camy+1
	sta v_sy16+1
; kolumny 0-2 (x + 8c w 0..255): pierwsza c0, ostatnia c1
	lda #$FF
	sta v_c0
	ldx #0
	lda v_sx16
	sta zp_t0
	lda v_sx16+1
	sta zp_t1
so_col
	lda zp_t1
	bne so_col_n
	lda v_c0
	bpl so_col_has
	stx v_c0
	lda zp_t0
	sta v_ox                  ; x ekranu pierwszej widocznej kolumny
so_col_has
	stx v_c1
so_col_n
	clc
	lda zp_t0
	adc #8
	sta zp_t0
	bcc so_col_nc
	inc zp_t1
so_col_nc
	inx
	cpx #3
	bne so_col
	lda v_c0
	bpl so_cols
	rts                       ; zadna kolumna na ekranie
so_cols
	lda v_c1                  ; w = 8 * (c1 - c0 + 1), przyciete do 256 - x
	sec
	sbc v_c0
	asl
	asl
	asl
	clc
	adc #8
	sta v_ow
	lda v_ox
	clc
	adc v_ow
	bcc so_w_ok
	beq so_w_ok               ; x + w = 256 dokladnie
	lda #0
	sec
	sbc v_ox
	sta v_ow                  ; 256 - x
so_w_ok
; wiersze: gora = Y + 1 (VDP), wysokosc 32, przyciecie do 0..191
	lda #32
	jsr clip_rows
	bcs so_none
; zrodlo: obraz + skip * 24 + kolumna (8 * c0 albo przy odbiciu 23 - 8 * c0, krok -1)
	lda v_c0
	asl
	asl
	asl
	sta zp_t0                 ; 8 * c0
	ldx #1
	lda v_fhi
	bpl so_noflip
	lda #23
	sec
	sbc zp_t0
	sta zp_t0
	ldx #$FF
so_noflip
	stx v_ostepx
	lda #24
	sta v_ostride
	lda v_skip                ; skip * 24 = skip * 16 + skip * 8 (skip < 32: wynik < 768)
	sta zp_t1
	lda #0
	sta zp_t2
	ldx #3
so_s8
	asl zp_t1
	rol zp_t2
	dex
	bne so_s8                 ; zp_t2:zp_t1 = skip * 8
	lda zp_t1
	sta zp_t3
	lda zp_t2
	sta v_tmp
	asl zp_t1
	rol zp_t2                 ; skip * 16
	clc
	lda zp_t1
	adc zp_t3
	sta zp_t1
	lda zp_t2
	adc v_tmp
	sta zp_t2                 ; skip * 24
	clc
	lda zp_t1
	adc zp_t0
	sta v_osrc                ; obraz ma lo = 0
	lda zp_t2
	adc v_fmid
	sta v_osrc+1
	lda v_fhi
	and #$07
	adc #0
	sta v_osrc+2
	jmp obj_emit
so_none
	rts

; clip_rows: A = wysokosc obiektu (16 / 32), gora = v_sy16 + 1 (16 bit ze znakiem). Wynik: C = 1 gdy poza
; ekranem; inaczej v_oy = max(gora, 0), v_skip = pominiete gorne linie, v_oh = widoczna wysokosc.
clip_rows
	sta v_hgt
	clc
	lda v_sy16
	adc #1
	sta zp_t0
	lda v_sy16+1
	adc #0
	sta zp_t1                 ; gora (16 bit)
	bmi cr_neg
	bne cr_out                ; >= 256
	lda zp_t0
	cmp #192
	bcs cr_out
	sta v_oy
	lda #0
	sta v_skip
	lda #192                  ; h = min(wys, 192 - gora)
	sec
	sbc zp_t0
	cmp v_hgt
	bcc cr_h
	lda v_hgt
cr_h
	sta v_oh
	clc
	rts
cr_neg                          ; gora < 0: skip = -gora, h = wys - skip (> 0)
	cmp #$FF
	bne cr_out                ; gora <= -256
	lda #0
	sec
	sbc zp_t0
	cmp v_hgt
	bcs cr_out                ; -gora >= wys: caly nad ekranem
	sta v_skip
	lda v_hgt
	sec
	sbc v_skip
	sta v_oh
	lda #0
	sta v_oy
	clc
	rts
cr_out
	sec
	rts

; ---------------------------------------------------------------------
; upspring_objs: trzeci wiersz map SPRITEMAP_sonic_upspring_right ($98 $9A od x + 0) / _left ($FE $9C $9E:
; od x + 8) na y + 32 (animacja $13 - wybicie w gore)
; ---------------------------------------------------------------------
upspring_objs
	lda sonic_spritemap_ix_15+1
	cmp #>$5939
	bne uo_ret
	lda sonic_spritemap_ix_15
	cmp #<$5939
	beq uo_right
	cmp #<$594B
	beq uo_left
uo_ret
	rts
uo_right
	lda #0
	ldx #$98
	jsr uo_spr
	lda #8
	ldx #$9A
	jmp uo_spr
uo_left
	lda #8
	ldx #$9C
	jsr uo_spr
	lda #16
	ldx #$9E
uo_spr                          ; A = przesuniecie x, X = kafel; pozycja = Sonic + (A, 32)
	stx v_tile
	clc
	adc sonic_x
	sta v_px
	lda sonic_x+1
	adc #0
	sta v_px+1
	clc
	lda sonic_y
	adc #32
	sta v_py
	lda sonic_y+1
	adc #0
	sta v_py+1
	jmp spr16

; ---------------------------------------------------------------------
; sparkle_objs: iskra pierscienia (@fn_handle_ring_sparkle_sprites 01:4E51), gdy rysowana w tym ticku
; (v_spk b7; b0-6 = licznik po zmniejszeniu): licznik >= 3 -> $B2 w (x, y - 2) i $5A w (x + 8, y + 2),
; inaczej $5A w (x, y - 2)
; ---------------------------------------------------------------------
sparkle_objs
	lda v_spk
	bmi sk_go
	rts
sk_go
	and #$7F
	cmp #3
	bcc sk_one
	lda #$5A                  ; druga (pod spodem) najpierw - $B2 wczesniej w tablicy SMS = na wierzchu
	ldx #8
	ldy #2
	jsr sk_spr
	lda #$B2
	ldx #0
	ldy #$FE
	jmp sk_spr
sk_one
	lda #$5A
	ldx #0
	ldy #$FE
sk_spr                          ; A = kafel, X = dx (0..8), Y = dy (ze znakiem)
	sta v_tile
	stx zp_t0
	sty zp_t1
	clc
	lda g_ring_sparkle_sprite_x
	adc zp_t0
	sta v_px
	lda g_ring_sparkle_sprite_x+1
	adc #0
	sta v_px+1
	ldx #0
	lda zp_t1
	bpl sk_dy
	dex                       ; rozszerzenie znaku dy
sk_dy
	clc
	adc g_ring_sparkle_sprite_y
	sta v_py
	txa
	adc g_ring_sparkle_sprite_y+1
	sta v_py+1
	jmp spr16

; isparkle_obj (M4.5): iskra niesmiertelnosci (@fn_handle_invincibility_sparkle_sprite 01:4E8D - draw_sprite
; w funkcji Sonica przed iskra pierscienia): v_isp = kafel ($94 / $96) albo 0, pozycja v_ispx / v_ispy (sonic.asm)
; throb_obj (M6.5): okragly zderzak etapu specjalnego (game/sonic.asm: sh_bumper): mapa SPRTAB_round_bumper_throbbing =
; 2 wiersze x 4 sprite'y 8x16 od pozycji anim_sprite (x, y) poziomu; w oryginale wpisy 0-7 tablicy (na wierzchu, zamiast
; sprite'ow Sonica). Port: gotowy obraz 32 x 32 (tools/pack_special.py) w VRAM w miejscu kulki testowej (SPRITE_VRAM, 8 bpp:
; 16 + kolor, 0 = przezroczysty) i dwa BCB (po jednym na wiersz sprite'ow). Odcinanie jak draw_sprite_string: kolumna sprite'a
; poza x 0..255 pominieta w calosci (co 8 px), wiersz przycinany do ekranu (clip_rows), prawa krawedz przyciana do 256.
; ---------------------------------------------------------------------
throb_obj
	sec                       ; x ekranu kolumny 0 (16 bit ze znakiem)
	lda g_special_stage_round_bumper_anim_sprite_x
	sbc v_camx
	sta zp_t0
	lda g_special_stage_round_bumper_anim_sprite_x+1
	sbc v_camx+1
	sta zp_t1
	lda #$FF
	sta v_c0                  ; pierwsza widoczna kolumna (bit 7 = brak)
	ldx #0
thr_col
	lda zp_t1
	bne thr_cn                 ; kolumna poza 0..255
	lda v_c0
	bpl thr_has
	stx v_c0
	lda zp_t0
	sta v_px                  ; x ekranu pierwszej widocznej kolumny
thr_has
	stx v_c1
thr_cn
	clc
	lda zp_t0
	adc #8
	sta zp_t0
	bcc thr_nc
	inc zp_t1
thr_nc
	inx
	cpx #4
	bne thr_col
	lda v_c0
	jmi thr_ret               ; zadna kolumna nie jest widoczna
	lda v_c1                  ; szerokosc = 8 * (c1 - c0 + 1), najwyzej do prawej krawedzi ekranu (256 - x)
	sec
	sbc v_c0
	clc
	adc #1
	asl
	asl
	asl
	sta v_tbw
	lda #0
	sec
	sbc v_px
	beq thr_wok                ; x = 0: 256
	cmp v_tbw
	bcs thr_wok
	sta v_tbw
thr_wok
	ldx #1                    ; wiersz 1 (dolny) i 0
thr_row
	stx zp_t2
	lda #0
	cpx #0
	beq thr_r0
	lda #16
thr_r0
	clc
	adc g_special_stage_round_bumper_anim_sprite_y
	sta v_sy16
	lda g_special_stage_round_bumper_anim_sprite_y+1
	adc #0
	sta v_sy16+1
	sec                       ; y ekranu wiersza (16 bit ze znakiem)
	lda v_sy16
	sbc v_camy
	sta v_sy16
	lda v_sy16+1
	sbc v_camy+1
	sta v_sy16+1
	lda #16
	jsr clip_rows             ; C = 1: poza ekranem; v_oy, v_skip, v_oh
	bcs thr_next
	lda v_px
	sta v_ox
	lda v_tbw
	sta v_ow
	lda #32
	sta v_ostride
	lda #1
	sta v_ostepx
	lda v_skip                ; zrodlo = SPRITE_VRAM + wiersz * 512 + skip * 32 + 8 * c0
	and #7
	asl
	asl
	asl
	asl
	asl
	sta zp_t3
	lda v_c0
	asl
	asl
	asl
	clc
	adc zp_t3
	clc
	adc #<SPRITE_VRAM
	sta v_osrc
	lda v_skip
	lsr
	lsr
	lsr
	sta zp_t3
	lda zp_t2
	asl
	clc
	adc zp_t3
	clc
	adc #>[SPRITE_VRAM&$FFFF]
	sta v_osrc+1
	lda #SPRITE_VRAM>>16
	sta v_osrc+2
	jsr obj_emit
thr_next
	ldx zp_t2
	dex
	jpl thr_row
thr_ret
	rts

isparkle_obj
	lda v_isp
	bne isk_go
	rts
isk_go
	sta v_tile
	lda v_ispx
	sta v_px
	lda v_ispx+1
	sta v_px+1
	lda v_ispy
	sta v_py
	lda v_ispy+1
	sta v_py+1
	jmp spr16

; ---------------------------------------------------------------------
; M7.5: front_objs / front_digit (M6.8 - przednie wpisy tablicy sprite'ow SMS przy wodzie / chmurach SKY2) przeniesione pod okno:
; render/prio.asm front_objs_f / front_digit_f (Z5: wpis w calosci na ekranie - BCB wprost, inne - s16_clip nizej).
; ---------------------------------------------------------------------

; spr16: sprite 8x16 v_tile (kafle v_tile, v_tile+1) w pozycji poziomu (v_px, v_py) wg draw_sprite:
; x ekranu poza 0..255 -> brak; y < -16 albo >= 192 -> brak; VDP: Y + 1, przyciecie do ekranu.
spr16
	sec
	lda v_px
	sbc v_camx
	sta v_ox
	lda v_px+1
	sbc v_camx+1
	bne s16_ret               ; x poza 0..255
	sec
	lda v_py
	sbc v_camy
	sta v_sy16
	lda v_py+1
	sbc v_camy+1
	sta v_sy16+1
s16_clip                        ; M6.8: wejscie z gotowa pozycja ekranowa (v_ox, v_sy16) - front_objs (M7.5: render/prio.asm fo_slow)
	lda #16
	jsr clip_rows
	bcs s16_ret
	lda #0                    ; w = min(8, 256 - x)
	sec
	sbc v_ox
	beq s16_w8                ; x = 0: 256 - 0 = 0 (mod 256) -> 8
	cmp #8
	bcc s16_w
s16_w8
	lda #8
s16_w
	sta v_ow
	lda #8
	sta v_ostride
	lda #1
	sta v_ostepx
	lda v_tile                ; src = SPRATLAS + kafel * 64 + skip * 8
	lsr
	lsr                       ; kafel * 64: hi = kafel >> 2, lo = (kafel & 3) << 6
	sta zp_t1
	lda v_tile
	and #3
	lsr
	ror
	ror
	sta zp_t0
	lda v_skip
	asl
	asl
	asl                       ; skip * 8 (< 128)
	clc
	adc zp_t0
	sta zp_t0
	lda zp_t1
	adc #0
	sta zp_t1
	clc
	lda zp_t0
	adc #<SPRATLAS_VRAM
	sta v_osrc
	lda zp_t1
	adc #>[SPRATLAS_VRAM&$FFFF]
	sta v_osrc+1
	lda #SPRATLAS_VRAM>>16
	adc #0
	sta v_osrc+2
	jmp obj_emit
s16_ret
	rts

; ---------------------------------------------------------------------
; obj_emit: BCB obiektu w slocie v_oslot (stencil, kolor 0 przezroczysty): zrodlo v_osrc (krok Y v_ostride,
; krok X v_ostepx), cel = bufor (v_ox, v_oy), rozmiar v_ow x v_oh; prostokat do priorytetu (or_*).
; ---------------------------------------------------------------------
obj_emit
	ldx v_oslot
	cpx #SLOT_OBJ+N_OBJ_SLOTS
	bcs oe_ret                ; brak slotu
	jsr slot_ptr
	inc v_oslot
	ldy #0
	lda v_osrc
	sta (zp_bcb),y
	iny
	lda v_osrc+1
	sta (zp_bcb),y
	iny
	lda v_osrc+2
	sta (zp_bcb),y
	iny
	lda v_ostride
	sta (zp_bcb),y            ; krok Y zrodla (< 256)
	iny
	lda #0
	sta (zp_bcb),y
	iny
	lda v_ostepx
	sta (zp_bcb),y            ; krok X zrodla (1 albo -1)
	lda v_ox
	sta zp_t0
	lda v_oy
	sta zp_t1
	jsr put_fb_dst
	lda v_ow
	jsr put_w
	lda v_oh
	jsr put_h
	ldy #20
	lda #$09                  ; stencil + NEXT
	sta (zp_bcb),y
	mwa zp_bcb zp_last
	ldx v_nobj                ; prostokat dla priorytetu tla
	lda v_ox
	sta or_x,x
	lda v_oy
	sta or_y,x
	lda v_ow
	sta or_w,x
	lda v_oh
	sta or_h,x
	inc v_nobj
oe_ret
	rts

; ---------------------------------------------------------------------
; prio_rect: bloki z priorytetem (PRIO_RAM) nad prostokatem ekranu (v_ox, v_oy, v_ow, v_oh; w, h <= 32):
; czesci blokow ukladu, ktore go przecinaja (do 2 x 2), ponownie ze stencil (piksele kafla != 0 nad
; obiektem). pc_* / pr_*: kolumny / wiersze czesci (blok, przesuniecie w bloku, rozmiar, pozycja ekranu).
; ---------------------------------------------------------------------
prio_rect
; M3.8d: szybki test - zaden z blokow 2 x 2 od bloku lewego gornego rogu nie ma priorytetu -> nic do zrobienia (nadzbior blokow
; pod prostokatem <= 32 x 32). M7.5 Z4: z mapy priorytetu okna (render/prio.asm prq_map) zamiast odczytow ukladu (prq_row).
	jsr prq_map
	bne prq_full
	rts
prq_full
	lda v_camx                ; kolumny: X = ox + (camx & 31)
	and #31
	clc
	adc v_ox
	sta zp_t0
	lda #0
	adc #0
	sta zp_t1                 ; X moze przekroczyc 255
	lda zp_t0
	and #31
	sta pc_lx
	lsr zp_t1
	ror zp_t0
	lsr zp_t0
	lsr zp_t0
	lsr zp_t0
	lsr zp_t0
	lda zp_t0                 ; X >> 5
	clc
	adc v_bx
	sta pc_col
	lda v_ox
	sta pc_scr
	lda #32                   ; pierwsza czesc: min(w, 32 - lx)
	sec
	sbc pc_lx
	cmp v_ow
	bcc pr_x2
	lda v_ow
	sta pc_w
	lda #1
	sta v_npc
	bne pr_y
pr_x2
	sta pc_w
	lda pc_col
	clc
	adc #1
	sta pc_col+1
	lda #0
	sta pc_lx+1
	lda v_ow
	sec
	sbc pc_w
	sta pc_w+1
	lda v_ox
	clc
	adc pc_w
	sta pc_scr+1
	lda #2
	sta v_npc
pr_y                            ; wiersze: Y = oy + (camy & 31) (< 256)
	lda v_camy
	and #31
	clc
	adc v_oy
	sta zp_t0
	and #31
	sta pr_ly
	lda zp_t0
	lsr
	lsr
	lsr
	lsr
	lsr
	clc
	adc v_by
	sta pr_row
	lda v_oy
	sta pr_scr
	lda #32
	sec
	sbc pr_ly
	cmp v_oh
	bcc pr_y2
	lda v_oh
	sta pr_h
	lda #1
	sta v_npr
	bne pr_loop
pr_y2
	sta pr_h
	lda pr_row
	clc
	adc #1
	sta pr_row+1
	lda #0
	sta pr_ly+1
	lda v_oh
	sec
	sbc pr_h
	sta pr_h+1
	lda v_oy
	clc
	adc pr_h
	sta pr_scr+1
	lda #2
	sta v_npr
pr_loop
	lda #0
	sta zp_t2                 ; indeks wiersza
pr_row_l
	lda #0
	sta zp_t3                 ; indeks kolumny
pr_col_l
	jsr prio_part
	inc zp_t3
	lda zp_t3
	cmp v_npc
	bne pr_col_l
	inc zp_t2
	lda zp_t2
	cmp v_npr
	bne pr_row_l
	rts
