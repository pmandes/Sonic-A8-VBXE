; =====================================================================
;  game_code.asm - kod gry (rezydentny $8000+ i $4100+), wlaczany z game.asm: w budowie testowej
;  (build/game.xex) za bankami, w wydaniu (RELEASE, build/sonic-a8-vbxe.xex) przed nimi (M6 krok 1).
; =====================================================================
; =====================================================================
;  Program
; =====================================================================
	org $8000
	.if MEDIA<>MEDIA_XEX
; M7.2: LDR_SPILL - 16 B na koniec strumienia zx02 przy dekompresji pelnego banku w miejscu (strumien konczy sie delta B za $7FFF;
; tools/pack_zone.py: delta <= 16). Tylko nosniki - w XEX nic nie jest ladowane w czasie gry.
ldr_spill_area	.ds LDR_SPILL_N
	.if ldr_spill_area<>LDR_SPILL
	.error "LDR_SPILL musi lezec na poczatku kodu rezydentnego ($8000)"
	.endif
	.endif
start
	.if NOSNIK_320
; M7.3 (review): start takze z RESET-u w grze (OS wylaczony - wektor RAM $FFFC = start, machine_init): NMI gry stop jako pierwszy
; rozkaz, zanim cokolwiek dotknie $A000+ (nmi_handler wola snd_nmi spod okna cartu, a RESET mogl trafic w kopie z wlaczonym cartem),
; POKEY cicho na czas ldr_init (5,5 s), cart wylaczony (ldr_cart_off w obszarze ;@LDR - jedyne miejsce z zapisem do $D5xx).
; Ze start_media - bez skutku (NMI i cart juz wylaczone).
	lda #0
	sta NMIEN
	.endif
	sei
	cld
	ldx #$FF
	txs
	.if NOSNIK_320
	lda #0
	sta AUDC1
	sta AUDC2
	sta AUDC3
	sta AUDC4
	sta AUDCTL
	.if MEDIA=MEDIA_CART
	jsr ldr_cart_off
	.endif
	.endif
	.if MEDIA<>MEDIA_XEX
	jsr ldr_init              ; M7.2: sloty zestawu roboczego puste (src/ldr/ldr.asm) - pierwszy poziom laduje wszystkie obrazy
	.endif
	jsr machine_init
	.ifdef RELEASE
	jmp boot_after_init       ; M6 krok 1: ekrany albo od razu poziom po INIT ekranow (src/scr/boot.asm)
	.endif
	jmp level_boot

; ---------------------------------------------------------------------
; machine_init: przejecie maszyny (OS i przerwania OS wylaczone, wektory w RAM pod OS), zmienne, VBXE, banki,
; MEMAC, dzwiek, NMI VBI gry. Bez ustawiania stosu - M6: wolane takze z INIT XEX-a (src/scr/boot.asm:
; scr_boot), ktory potem oddaje maszyne loaderowi. Blad sprzetu: fail (czerwone tlo, stop).
; ---------------------------------------------------------------------
machine_init
	sei
	cld
	lda #0
	sta NMIEN
	sta NMIRES
	sta IRQEN
	sta DMACTL
	sta GRACTL
	sta COLBK
	lda PBCTL
	and #$FB
	sta PBCTL
	lda #$FF
	sta PORTB
	lda PBCTL
	ora #$04
	sta PBCTL
	lda #PB_MAIN
	sta PORTB
	mwa #nmi_handler $FFFA
	mwa #start $FFFC
	mwa #irq_handler $FFFE

	mwa #vars_start zp_dst    ; M3.8e: zmienne zerowane petla 16-bitowa (wczesniej limit 256 B)
	mwa #vars_end-vars_start zp_cnt
	ldy #0
clr_vars
	tya
	sta (zp_dst),y
	inc zp_dst
	bne clr_v1
	inc zp_dst+1
clr_v1
	lda zp_cnt
	bne clr_v2
	dec zp_cnt+1
clr_v2
	dec zp_cnt
	lda zp_cnt
	ora zp_cnt+1
	bne clr_vars
	lda #$FF
	sta v_ring_art            ; pierscien: kafle strefy do pierwszego update_ring_tiles
	sta v_ring_drawn
	sta v_idle_min
	sta v_idle_min+1
	sta v_free_min
	sta v_free_min+1
	sta v_joy
	lda #1
	sta v_back
	sta v_trig
	sta v_svy
	lda #2
	sta v_svx
	lda #48
	sta v_sx
	lda #40
	sta v_sy
	lda #CAM_SPEED
	sta v_vx
	sta v_vy
	mwa #LV_CAM_X0 v_camx
	mwa #160 v_camy
	lda #LV_CYC_SPEED
	sta v_cyc_timer
	lda #CAM_GAME             ; kamera gry, kulka = Sonic (m2_test.py ustawia 0 w cfg_point - scenariusz M2)
	sta v_cam_mode
	.if MEDIA=MEDIA_XEX         ; M7.2: trace tylko w XEX (nosniki - stub trace_record, src/game/trace.asm wylaczony)
	lda #0                    ; pierwszy bank z tablicy tr_bank_tab (bufor trace'u)
	sta v_tr_bank
	lda #TR_NBANKS            ; M6.9: liczba bankow bufora - test (m3_test) dopisuje w cfg_point banki stref nieuzywanych przez scenariusz
	sta v_tr_nbanks
	mwa #BANK_WIN v_tr_ptr
	mwa #$FFFF v_tr_limit
	.endif

	mwa #262 v_lpf
	mwa #262-248 v_lpf_m248
	lda PAL
	and #$0E
	bne tv_done
	lda #1
	sta v_tv
	mwa #312 v_lpf
	mwa #312-248 v_lpf_m248
tv_done

	jsr detect_fx
	bcc fx_ok
	lda v_fxseen
	beq no_fx
	lda #2
	jmp fail
no_fx
	lda #1
	jmp fail
fx_ok
	lda #0
	ldy #VC_VIDEO
	sta (zp_fx),y
	ldy #VC_BLT_START
	sta (zp_fx),y
	ldy #VC_IRQ
	sta (zp_fx),y
	ldy #VC_MEMAC_B
	sta (zp_fx),y
	ldy #VC_MEMAC_BANK
	sta (zp_fx),y
	ldy #VC_MEMAC_CTL
	sta (zp_fx),y
	jsr wait_frame_vc

	.ifdef RELEASE              ; M7.2: jedna procedura test_banks_n (kernel/hw.asm): A = liczba bankow, X = pierwszy, Y = krok
	lda #TPAM_N                ; M6.6: wydanie - 1088K, 32 banki nieparzyste 1-63 (dawne test_banks32; sonic-ram.xex - tak samo:
	ldx #TPAM_B0               ; banki RAMCART 0, 38-62 parzyste sprawdzil boot_check testem 64 bankow). M7.3: nosnik 320K (cart / ATR) -
	ldy #TPAM_ST               ; 16 bankow 33-63 co 2 (kernel/mem.inc: TPAM_*, asercja TPAM_N <= TB_MAXN)
	.else
	lda #64                   ; testy: 64 banki (bufor trace'u w bankach 0-32, 36-46, 48-63; dawne test_banks)
	ldx #0
	ldy #1
	.if 64>TB_MAXN
	.error "machine_init: test 64 bankow, a save0 / save1 maja TB_MAXN B"
	.endif
	.endif
	jsr test_banks_n
	bcc banks_ok
	lda #3
	jmp fail
banks_ok
	jsr init_memac
	bcc memac_ok
	lda #4
	jmp fail
memac_ok
	.ifdef RELEASE
	lda boot_keepsnd          ; M6.3: game over - muzyka smierci gra dalej (boot_gameover)
	bne md_keepsnd
	.endif
	jsr snd_init              ; M5: POKEY, muzyka wylaczona (sound/music.asm)
md_keepsnd
	lda #NMI_VBI
	sta NMIEN
	rts

; ---------------------------------------------------------------------
; M6.3: poziom (akt) wczytywany przez level_boot: boot_level = g_level (GHZ1 0, GHZ2 1, GHZ3 2). Poza vars - machine_init go
; nie zeruje; ustawiaja go: cracktro (wybor aktu do testow), ekrany po mapie (boot_after_init), boot_score (nastepny
; akt); testy m3_test ustawiaja go w level_boot. lv_select: bank danych poziomu -> v_pblevel (render/load.asm,
; game/level.asm, game/motion.asm, render/rings.asm).
; ---------------------------------------------------------------------
boot_level	dta b(0)
v_nbonus	dta b($1C)           ; M6.11: g_next_bonus_level nowej gry (trainer: pierwszy etap specjalny za wybrana pozycja - scr_boot)
v_inflives	dta b(0)             ; trainer: 1 = nieskonczone zycia (CRK_INF z cracktro, ustawia scr_boot; poza zmiennymi zerowanymi na starcie)
; M6.6-M6.11: banki strefy wg g_level (boot_level): atlas tla, dane poziomu, sprite'y strefy, bank obiektow strefy (kod obiektow z banku 2
; ROM-u: 11 dla BRI-LAB - GHZ ich nie uzywa, 2 Scrap Brain, 30 Sky Base i poziom $12). M7.2: tablice rol obrazow ldr_lvl / ldr_sub (tools/manifest.py
; -> build/assets/ldr_tables.inc, src/ldr/ldr.asm) zamiast zn_* / sub_bank i stalych etapow specjalnych - ldr_need wpisuje v_pb* i v_img:
; XEX 1088K - banki rezydentne (te same wartosci PORTB co wczesniej), nosnik 320K - sloty zestawu roboczego z doczytaniem brakujacych obrazow.
; ZONE_N = akty i $12 (indeks = g_level); boot_level 19-$1B (poza tablica) - zaslepka GHZ1; $12 = bank GHZ1 z kopia bloku $12, sprite'y z banku 39
; (kafle $00-$7F: grafika bossa - level_init, v_art_req 1), obiekty banku 30 (kontroler $53, szmaragd $54).
; M6.5: etapy specjalne $1C-$23 (lv_idx 19-26): poziom - bank 63 albo 32 (etapy pionowe $1F / $23), atlas - 61, sprite'y - kafle i paleta
; z banku 59 (v_special), tablica klatek z 39; obiekty $21 / $4C - bank 30. Blok na poziom (naglowek, czas, wskazniki, lista obiektow: 256 B
; od LB_HDR) kopiowany z kopii w banku poziomu (lvs_stash).
lv_select
	lda #0                    ; M6.10: przednie wpisy sprite'ow bez wody - tylko SKY2 i $12 (sky_stash)
	sta v_front
	sta v_special             ; 0 = akt (etap specjalny: 1 nizej)
	ldy #$FF                  ; pod-poziom: brak
	ldx boot_level
	cpx #$1C
	bcs lvs_sp
	cpx #ZONE_N                 ; poza tablica stref (19-$1B): zaslepka GHZ1
	bcc lvs_ok
	ldx #0
lvs_ok
	lda iy_06_lvflag01        ; M6.9: korytarz / teleport (iy_06 b4, 00:1CF8): bank naglowka g_next_level_override_target ($14-$19;
	and #$10                  ; M6.10: $1A - bank SKY3 i atlas SKY3)
	beq lvs_need
	cpx #SUB_AKT1             ; review M6.9: pod-poziomy tylko z aktu SBZ2 (13) i SKY2 (16) - przy nowej grze lustro RAM SMS (iy_06,
	beq lvs_sub               ; g_next_level_override_target) nie jest jeszcze zainicjowane (game_reset po lv_select; level_boot kasuje
	cpx #SUB_AKT2             ; tez iy_06 b4). SUB_* z manifestu (build/assets/ldr_tables.inc)
	bne lvs_need
lvs_sub
	lda g_next_level_override_target
	sec
	sbc #$14
	cmp #SUB_N                ; 7 pod-poziomow $14-$1A
	bcs lvs_need
	tay                       ; Y = pod-poziom 0-6 (ldr_sub)
lvs_need
	jsr ldr_need              ; X = lv_idx, Y = pod-poziom / $FF: v_pb*, v_img (nosnik: obrazy w slotach)
	jmp sky_stash             ; M6.10: SKY2 / SKY3 / $1A / GHZ1 / $12 - blok na poziom i paleta sprite'ow
lvs_sp
	txa
	sbc #$1C                  ; C = 1 (bcs)
	cmp #8
	bcc lvs_sp1
	lda #2                    ; poza $1C-$23: etap $1E
lvs_sp1
	pha                       ; etap 0-7
	clc
	adc #ZONE_N
	tax                       ; X = lv_idx etapu (19-26)
	inc v_special             ; M6.5: 1 = etap specjalny - grafika i paleta sprite'ow z banku 59 (render/sprites.asm)
	jsr ldr_need              ; Y = $FF: poziom 63 / 32, atlas 61, sprite'y 39, obiekty 30 (nosnik: LEVEL, ATLAS2, -, LEVEL2)
	pla
	tax
	lda v_pblevel
	sta PORTB
	lda lvs_stash,x
	sta zp_src+1
	lda #0
	sta zp_src
	mwa #BANK_WIN+LB_HDR zp_dst
	ldy #0
lvs_cp
	lda (zp_src),y
	sta (zp_dst),y
	iny
	bne lvs_cp
	lda #PB_MAIN
	sta PORTB
	rts

; sky_stash (M6.10): strefa Sky Base. Bank SKY3 niesie dwa bloki na poziom (naglowek, czas, wskazniki palet, lista obiektow: 256 B od
; LB_HDR): SKY3 (LB_STASH3) i pod-poziom $1A (LB_STASH1A, 05:5967 - ta sama grafika i uklad, inna kamera, start i lista obiektow) - wlasciwy
; kopiowany na LB_HDR (jak lvs_stash etapow specjalnych). Bank sprite'ow SKY niesie dwie palety sprite'ow: $1F00 = LVPAL3_SKY (01:643E,
; SKY1/2), $1F30 = LVPAL3_SKY_3 (01:658E, SKY3 i $1A) - wlasciwa kopiowana na LS_PALSPR (load_sprite_data, spr_zone_pal; reszta banku
; wspolna). Inne strefy - bez zmian.
; M7.2: obraz roli wg v_img (identyfikator obrazu: XEX - PORTB banku = dawne porownania z PB_*, nosnik - id obrazu, slot dowolny),
; bank do odczytu z v_pblevel / v_pbzspr (XEX: ta sama wartosc co dawna stala PB_* w danej galezi).
sky_stash
	lda v_img+LR_LEVEL        ; SKY2: chmury $30 w przednich wpisach tablicy sprite'ow (v_front - game/step.asm, render/sprites.asm)
	cmp #LI_LV_SKY2
	bne sks_nf
	inc v_front
sks_nf
	cmp #LI_LV_GHZ1           ; M6.11: obraz GHZ1 - blok na poziom GHZ1 albo poziomu koncowego $12 (szmaragd $54 w przednich wpisach)
	bne sks_ng
	ldy #>[BANK_WIN+LB_STASHG1]
	lda boot_level
	cmp #18
	bne sks_g1
	inc v_front
	ldy #>[BANK_WIN+LB_STASH12]
sks_g1
	lda v_pblevel             ; bank z obrazem GHZ1 (XEX: PB_LEVEL)
	sta PORTB
	sty zp_src+1
	lda #0
	sta zp_src
	mwa #BANK_WIN+LB_HDR zp_dst
	ldy #0
sks_gc
	lda (zp_src),y
	sta (zp_dst),y
	iny
	bne sks_gc
	lda #PB_MAIN
	sta PORTB
	rts
sks_ng
	lda v_img+LR_ZSPR         ; strefa Sky Base (sprite'y SKY)
	cmp #LI_SPR_SKY
	bne sks_ret
	ldx #0                    ; paleta sprite'ow SKY1/2
	lda v_img+LR_LEVEL        ; obraz SKY3 (SKY3 albo $1A)
	cmp #LI_LV_SKY3
	bne sks_pal
	ldx #48                   ; SKY3 i $1A: paleta 6
	ldy #>[BANK_WIN+LB_STASH3]
	lda boot_level            ; $1A: bank SKY3 przy akcie SKY2 (16) - tylko przez pod-poziom (lv_select: iy_06 b4 i cel $1A; korytarz SKY2,
	cmp #16                   ; restart po smierci w $1A)
	bne sks_blk
	ldy #>[BANK_WIN+LB_STASH1A]
sks_blk
	lda v_pblevel             ; bank z obrazem SKY3 (XEX: PB_LEVELK3)
	sta PORTB
	sty zp_src+1
	lda #0
	sta zp_src
	mwa #BANK_WIN+LB_HDR zp_dst
	ldy #0
sks_cp
	lda (zp_src),y
	sta (zp_dst),y
	iny
	bne sks_cp
sks_pal
	lda v_pbzspr              ; bank sprite'ow SKY (XEX: PB_SPRK)
	sta PORTB
	ldy #0
sks_p
	lda BANK_WIN+$1F00,x
	sta BANK_WIN+LS_PALSPR,y
	inx
	iny
	cpy #48
	bne sks_p
	lda #PB_MAIN
	sta PORTB
sks_ret
	rts
; kopie bloku na poziom etapow specjalnych w banku poziomu (tools/pack_special.py), indeks = etap 0-7 ($1C-$23; M7.2: wprost, bez dawnej
; tablicy lvs_map): $1C, $1D, $1E, $20, $21, $22 - bank 63; $1F, $23 - bank 32 (M6.11, etapy pionowe)
lvs_stash	dta b(>[BANK_WIN+$2500], >[BANK_WIN+$3F00], >[BANK_WIN+$3400], >[BANK_WIN+$0800])   ; $1C, $1D, $1E, $1F (bank 32)
		dta b(>[BANK_WIN+$0800], >[BANK_WIN+$0900], >[BANK_WIN+$0A00], >[BANK_WIN+$0900])   ; $20, $21, $22, $23 (bank 32)

; ---------------------------------------------------------------------
; level_boot: start poziomu z danych w bankach - grafika do VRAM, listy, magazyn blokow, stan gry (krok -16),
; petla glowna. M6: takze po ekranach (src/scr/boot.asm: boot_after_init) - XDL-e, palety i VRAM od nowa.
; ---------------------------------------------------------------------
level_boot
	.ifdef RELEASE
	lda boot_next             ; review M6.9: nowa gra (nie nastepny akt i nie kontynuacja po game over - boot_next = 1): lustro RAM SMS
	bne lb_keep               ; jeszcze sprzed game_reset - bez pod-poziomu (iy_06 b4) w lv_select
	.endif
	lda iy_06_lvflag01
	and #$EF
	sta iy_06_lvflag01
lb_keep
	lda #1                    ; review M6.9: uklad w calosci z banku (lay_pages) - start z ekranow, RAM ukladu nadpisany (map2_copy)
	sta v_layfull
	jsr lv_select             ; M6.3: bank danych poziomu wg boot_level
	jsr load_level_data
	jsr load_ring_data        ; M3.5: maski i klatki pierscienia (render/rings.asm)
	jsr load_palette
	jsr load_sprite_data      ; M3.6: klatki Sonica, kafle i paleta sprite'ow (render/sprites.asm)
	jsr hud_clear             ; M3.7c: luki plotna HUD-u = kolor 0 (render/hud.asm, kod pod $4100 - po PB_MAIN)
	lda #1
	sta v_cyc_on
	jsr init_lists            ; XDL-e, komplet 0 listy ramki, listy budowy magazynu i przeladowania
	jsr rchain_init           ; M3.8b: lancuch pierscieni w VRAM (render/rchain.asm)
	jsr snap_time
	jsr build_store
	jsr elapsed_lines
	mwa zp_lo v_store_lines
	ldx #1                    ; M4.2: komplet 1 listy ramki w obszarze listy budowy magazynu - po budowie
	jsr init_list_set
store_built
;##TRACE "M3 tv(1=PAL)=%d" db(v_tv)
;##TRACE "M3 fx_base_hi=$%02X fx_minor=$%02X banks=%d" db(zp_fx+1) db(v_minor) db(v_bankcnt)
;##TRACE "M3 blocks=%d store_build_lines=%d" db(v_nblocks) dw(v_store_lines)
cfg_point                       ; test: v_input_mode, v_trace_on, v_tr_limit, skrypt w banku BANK_SCRIPT
	.ifdef RELEASE
	lda boot_next             ; M6.2: nastepny akt po ekranie wyniku i mapie - stan gry zostaje (load_and_run_level)
	beq cfg_new
	lda #0
	sta boot_next
	jsr level_next
	jmp level_ready
cfg_new
	.endif
	jsr level_start           ; stan gry i poziomu w lustrze RAM SMS = krok -16
level_ready                     ; test: zrzut lustra i ukladu w kroku -16
	lda #0                    ; review M6.9: dalej (restart, pod-poziom) uklad wg lay_pages
	sta v_layfull
;##TRACE "M3 level_start input_mode=%d trace=%d" db(v_input_mode) db(v_trace_on)
	jsr wait_tick
; lista 0: tick 1 i budowa w komplecie 0 (blitter wolny), cel = bufor tylny
	lda #0
	sta v_lbuild
	sta v_lrun
	lda v_back
	sta v_tgt
	jsr game_tick
	jsr build_list

; ---------------------------------------------------------------------
;  Petla glowna z potokiem: lista N (komplet v_lrun) startuje zaraz po VBI, CPU w tym czasie liczy
;  tick N+1 i buduje liste N+1 w drugim komplecie (do drugiego bufora); po zakonczeniu listy N
;  flip_req - VBI przelacza bufory. Opoznienie obrazu: 2 ramki wzgledem wejscia (M2: 1).
; ---------------------------------------------------------------------
main_loop
	jsr idle_until_tick         ; VBI: flip listy N-1
	jsr calc_free
	lda #0
	sta v_reload_now
	jsr snap_time
	jsr rchain_wait           ; M3.8b: lancuch pierscieni (start po poprzedniej liscie) musi sie skonczyc
	ldx v_lrun                ; M4.2: adres VRAM pierwszego slotu listy = baza kompletu + slot * 21
	ldy ls_slot,x
	clc
	lda mul21_lo,y
	adc set_vram_lo,x
	sta zp_tmp
	lda mul21_hi,y
	adc set_vram_mid,x
	sta zp_tmp+1
	lda set_vram_hi,x
	adc #0
	ldy #VC_BL_ADR0+2
	sta (zp_fx),y
	dey
	lda zp_tmp+1
	sta (zp_fx),y
	dey
	lda zp_tmp
	sta (zp_fx),y
	ldy #VC_BLT_START
	lda #1
	sta (zp_fx),y
; tick N+1 i lista N+1 w czasie pracy blittera
	lda v_lrun
	eor #1
	sta v_lbuild
	jsr game_tick
	jsr build_list
list_built                      ; test: lista N+1 zbudowana po ticku N+1 (zrzut ukladu i stanu pierscieni)
	jsr elapsed_lines
	mwa zp_lo v_cpu_last
	jsr max_cpu
	jsr wait_list
	jsr record_blit
	ldx v_lrun
	jsr drawn_params
	jsr xdl_water             ; M6.8: XDL bufora v_back wg wody listy v_lrun (paleta 2 od linii podzialu) - przed flipem
frame_done                      ; lista N zakonczona: bufor v_back kompletny, v_d* = jej parametry (zrzut testow)
	lda v_video_on
	bne video_ok
	lda #VIDEO_ON
	ldy #VC_VIDEO
	sta (zp_fx),y
	sta v_video_on
video_ok
	lda #1
	sta v_flip_req
	jsr sign_tiles            ; M4.8: grafika i paleta tabliczki / strefy w atlasie sprite'ow (render/sprites.asm)
	jsr mon_tiles             ; M4.5: kafle ikon monitorow $5C-$5F (blitter wolny - render/sprites.asm)
	jsr rchain_start          ; M3.8b: zmiana klatki pierscieni w nastepnej liscie -> lancuch teraz
	lda v_lrun
	eor #1
	sta v_lrun
	inc v_renders
	bne renders_ok
	inc v_renders+1
renders_ok
	lda v_renders
	jne main_loop
	jsr stats_point
	jmp main_loop

; tick logiki gry: krok petli poziomu SMS (stan w lustrze RAM), potem kamera renderera (v_camx/v_camy:
; w trybie CAM_GAME = kamera gry, w trybach testowych M2 - kamera testowa) i kulka (w CAM_GAME = Sonic)
game_tick
	lda v_trans
	bne gt_trans
	jsr sms_step
	lda v_lvl_exit            ; M3.7: wyjscie z poziomu w tym kroku -> przejscie (game/trans.asm)
	beq gt_cam
	jsr trans_start
	jmp gt_cam
gt_trans
	jsr trans_step            ; wygaszanie, przerwa, restart poziomu / nowa gra
gt_cam
	jsr update_camera
	jmp update_ball

fail
	sta v_status
;##TRACE "M3 FAIL status=%d" db(v_status)
	lda #0
	sta NMIEN
	lda v_fxseen
	beq fail_gtia
	lda #0
	ldy #VC_VIDEO
	sta (zp_fx),y
	ldy #VC_BLT_START
	sta (zp_fx),y
fail_gtia
	lda #$34
	sta COLBK
fail_loop
	jmp fail_loop

stats_point
;##TRACE "M3 frames=%d renders=%d flips=%d late=%d" dw(v_frame) dw(v_renders) dw(v_flips) db(v_late)
;##TRACE "M3 blit_lines last=%d max=%d cpu_lines last=%d max=%d" dw(v_blit_last) dw(v_blit_max) dw(v_cpu_last) dw(v_cpu_max)
;##TRACE "M3 idle last=%d min=%d blk_blits last=%d max=%d reloads=%d" dw(v_idle_last) dw(v_idle_min) db(v_nblk) db(v_nblk_max) db(v_reloads)
;##TRACE "M3 free_cycles last=%d min=%d wait_iter=%d" dw(v_free_last) dw(v_free_min) dw(v_wait_last)
;##TRACE "M3 cam=(%d,%d) mode=%d" dw(v_camx) dw(v_camy) db(v_cam_mode)
	rts

; kod rezydentny $8000-$BFFF: NMI, przelaczanie bankow PORTB (ladowanie, uklad poziomu, skrypt wejsc,
; trace) i wszystko, co wykonuje sie przy wlaczonym banku pod $4000, oraz zmienne
	icl 'kernel/hw.asm'
	icl 'kernel/time.asm'
	icl 'kernel/nmi.asm'
	.if nmi_handler>=$A000 || irq_handler>=$A000
	.error "NMI / IRQ musza lezec ponizej okna cartridge'a $A000 (M7.3: przerwanie przy wlaczonym carcie)"
	.endif
	icl 'ldr/ldr.asm'         ; M7.2: wybor bankow poziomu (ldr_need, wszystkie buildy), nosniki - ladowanie obrazow (ponizej $A000)
; M7.4: ATR - granica czesci surowej pliku XAUTORUN ($8000 - kod_hi_start: jadro, NMI, ldr z xBIOS-em, komunikaty) i obrazu kodu B51
; (kod_hi_start - code_hi_end, zx02 przez ldr_kod); w innych buildach tylko etykieta. XAUTORUN laduje sie, gdy ekran E: OS-u jest
; jeszcze wlaczony (pod RAMTOP $A0 - BASIC przy starcie - lista wyswietlania w $9C20): czesc surowa musi sie konczyc przed nim.
kod_hi_start
	.if MEDIA=MEDIA_SIO && kod_hi_start>$9C20
	.error "ATR: czesc surowa XAUTORUN (do kod_hi_start) nachodzi na ekran E: OS-u $9C20 (RAMTOP $A0)"
	.endif
	icl 'render/load.asm'
	icl 'render/rings.asm'
	icl 'render/sprites.asm'
	icl 'render/water.asm'      ; M6.8: woda Labyrinth - paleta 2 i podzial XDL
	icl 'game/level.asm'
	icl 'game/input.asm'
	icl 'game/motion.asm'
	icl 'game/objcom.asm'     ; M4.1: procedury wolane przez obiekty i Sonica, objects_tick (bank 45)
	.if MEDIA=MEDIA_XEX
	icl 'game/trace.asm'      ; trace stanu do bankow (tools/m3_test.py, m38_profil.py - build/game.xex)
	.else
; M7.2: nosniki bez trace'u (936 B miejsca na ldr ponizej $A000; bufor trace'u w bankach 1088K i tak nie istnieje na 320K). game/step.asm
; i game/level.asm koncza kroki skokiem jmp trace_record - stub rts; trace_done - etykieta dla narzedzi (zmienne v_tr* zostaja w vars.asm)
trace_record
trace_done
	rts
	.endif
	icl 'sound/music.asm'
	icl 'sound/sfx.asm'
	icl 'render/tables.asm'
	.ifndef RELEASE
	icl 'game/testcam.asm'     ; M7.5: budowa testowa - kamera / kulka testowe M2 w kodzie rezydentnym (miejsce pod oknem)
	.endif
	.ifdef RELEASE
	icl 'scr/boot.asm'        ; M6 krok 1: start wydania - INIT-y XEX-a, ekrany, 320K
	icl 'scr/special.asm'     ; M6.5: ekran wyniku etapu specjalnego (haki z banku 49)
	.endif
	icl 'vars.asm'
code_hi_end

; ---------------------------------------------------------------------
;  M3.8e: kod w RAM glownym $4100-$7FFF (PORTB = PB_MAIN; banki widac tam tylko w procedurach rezydentnych
;  powyzej, ktore wracaja z PB_MAIN). Tu nie moze byc nic, co wykonuje sie albo jest wolane przy wlaczonym
;  banku, ani NMI. $4000-$40FF zostaje (test_banks zapisuje i odtwarza $4000-$4001 RAM glownego).
; ---------------------------------------------------------------------
	org CODE_LO
code_lo_start
	icl 'render/frame.asm'
	icl 'render/fade.asm'
	icl 'render/hud.asm'
	icl 'render/rchain.asm'
	icl 'render/objspr.asm'   ; M4.2: sprite'y obiektow z tablicy sprite'ow SMS
	icl 'render/prio.asm'     ; M7.5: priorytet tla pod NTSC (Z1/Z4/Z5), przednie wpisy sprite'ow
	.ifdef RELEASE
	icl 'game/testcam.asm'     ; M7.5: wydanie - tylko kamera gry (CAM_GAME)
	.endif
	icl 'game/step.asm'
	icl 'game/sonic.asm'
	icl 'game/camera.asm'
	icl 'game/rings.asm'
	icl 'game/death.asm'
	icl 'game/trans.asm'
	icl 'game/hud.asm'
code_lo_end
	.if code_lo_end > $8000
	.error "kod $4100+ przekracza $7FFF"
	.endif
	.if code_hi_end > $C000
	.error "kod rezydentny przekracza $BFFF"
	.endif
	.if (MEDIA=MEDIA_CART || MEDIA=MEDIA_SIO) && code_hi_end > CART_HDR_RAM
	.error "kod rezydentny nachodzi na $BFFC (CART_HDR_RAM - start_media wpisuje tam $FF na wypadek RESET-u)"
	.endif

