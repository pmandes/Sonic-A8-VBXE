; =====================================================================
;  nmi.asm - NMI = VBI (linia 248): licznik ramek, joystick, flip buforow, cykl palety wody GHZ
;  Odpowiednik czesci IRQ SMS (irq_start 00:0073: VDP, wejscie) - logika gry nie biegnie w przerwaniu.
;  Rejestry zachowywane na stosie; NMI nie korzysta z okna bankow ani z ZP pomiarow.
; =====================================================================
nmi_handler
	pha
	txa
	pha
	tya
	pha
	lda NMIST
	sta NMIRES                ; potwierdzenie NMI
	and #NMI_VBI
	jeq nmi_exit              ; tylko VBI (DLI wylaczone)
	inc v_frame               ; licznik ramek (16 bit) - podstawa pomiarow i taktu petli
	bne nmi_f
	inc v_frame+1
nmi_f
	lda PORTA                 ; joystick 0 w bitach 0-3 (U D L R, aktywne zerem), joystick 1 w 4-7
	sta v_joy
	lda TRIG0                 ; 0 = fire wcisniety
	sta v_trig
; flip: gdy lista ramki gotowa (v_flip_req) i blitter wolny -> XDL_ADR na XDL bufora tylnego.
; Zapis XDL_ADR w VBI wyprzedza zatrzask VSYNC, wiec od nastepnej ramki widac nowy bufor.
	lda v_flip_req
	beq nmi_cyc
	lda zr_run                ; M3.8b: biegnie lancuch pierscieni (lista ramki juz skonczona) - flip
	bne nmi_flip
	ldy #VC_BLT_START
	lda (zp_fx),y
	and #3                    ; blitter dalej pracuje -> flip w nastepnym VBI (ramka spozniona)
	bne nmi_cyc
nmi_flip
	lda v_blank_req           ; M6: ramka ekranu z wylaczonym obrazem (VDP reg1 bit 6 = 0) - XDL pustej linii
	bne nmi_blank             ; w kolorze ramki (src/scr/ekrany.asm), bufory i v_back bez zmian
	lda v_back
	asl
	asl
	asl
	asl
	asl                       ; XDL bufora v_back pod VRAM v_back * $20 (XDL0 $00000, XDL1 $00020)
	ldy #VC_XDL_ADR0
	sta (zp_fx),y
	lda v_back
	eor #1                    ; wyswietlany bufor staje sie przednim, drugi - tylnym
	sta v_back
	lda v_vid_wait            ; review M6.9: obraz wylaczony po przeladowaniu poziomu (game/trans.asm vid_hold) - wlaczany razem z flipem
	beq nmi_flipd             ; pierwszej listy nowego stanu (drugi flip), od poczatku ramki
	dec v_vid_wait
	bne nmi_flipd
	lda #VIDEO_ON
	ldy #VC_VIDEO
	sta (zp_fx),y
nmi_flipd
	lda #0
	sta v_flip_req
	lda v_pal_req             ; M6: paleta ramki ekranu (src/scr/ekrany.asm) - razem z flipem, kolory 0-31
	beq nmi_flipped           ; palety 1 nakladki z v_pal_rgb (R, G, B)
	ldy #VC_PSEL
	lda #1
	sta (zp_fx),y
	ldy #VC_CSEL
	lda #0
	sta (zp_fx),y
	sta v_pal_req
	ldx #0
nmi_pr
	lda v_pal_rgb,x
	ldy #VC_CR
	sta (zp_fx),y
	lda v_pal_rgb+1,x
	iny
	sta (zp_fx),y
	lda v_pal_rgb+2,x
	iny
	sta (zp_fx),y             ; CB: zapis koloru i CSEL + 1
	inx
	inx
	inx
	cpx #96
	bne nmi_pr
nmi_flipped
	inc v_flips
	bne nmi_cyc
	inc v_flips+1
	jmp nmi_cyc
nmi_blank                       ; M6: XDL pustej linii ($00040, render/vram.inc: XDLB_VRAM)
	lda #XDLB_VRAM&$FF
	ldy #VC_XDL_ADR0
	sta (zp_fx),y
	jmp nmi_flipd
; cykl palety tla (woda GHZ): co v_cycspd ramek nastepny z v_cyccnt wariantow 16 kolorow
; z PAL_RAM (+48 * (1 + indeks)) do palety 1 nakladki VBXE, kolory 0-15
nmi_cyc
	lda v_cyc_on
	jeq nmi_snd
	dec v_cyc_timer
	jne nmi_snd
	lda v_cycspd
	sta v_cyc_timer
	ldx v_cyc_idx
	inx
	cpx v_cyccnt
	bcc nmi_ci
	ldx #0
nmi_ci
	stx v_cyc_idx
	lda cyc_off,x             ; offset wariantu w PAL_RAM
	tax
	ldy #VC_PSEL
	lda #1                    ; paleta 1 (nakladka)
	sta (zp_fx),y
	ldy #VC_CSEL
	lda #0                    ; od koloru 0, auto-inkrementacja po CB
	sta (zp_fx),y
	lda #16
	sta v_nmi_cnt
nmi_pal
	lda PAL_RAM,x             ; R, G, B
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
	dec v_nmi_cnt
	bne nmi_pal
nmi_snd
	jsr snd_nmi               ; M5: ramka muzyki (sound/music.asm)
nmi_exit
	pla
	tay
	pla
	tax
	pla
	rti

; IRQ nieuzywane (POKEY i blitter bez przerwan)
irq_handler
	rti
