; =====================================================================
;  rchain.asm - M3.8b: staly lancuch BCB pierscieni (przemalowanie pierscieni tla bez skoku CPU)
;
;  Zmiana klatki grafiki pierscienia (co 10 tickow) wymagala BCB na kazda polowke bloku z pierscieniem
;  w oknie 9x7 (skan ukladu i do ok. 40 BCB - do 7,4 tys. cykli w jednej ramce). Tu: w VRAM stoi lancuch
;  2 + 128 BCB (RCHAIN_VRAM): 2 BCB kopiuja biezaca klatke (RINGART + k * 256) do RCUR2 (32x16: klatka
;  dwa razy obok siebie), dalej po jednym wpisie na slot pierscienia tla (16 x 8 blokow; slot s = (r & 7)
;  * 16 + (c & 15)): kopia RCUR2 na polowki bloku z pierscieniem (lewa 16, prawa 16 albo obie 32 px,
;  wiersze 8-23 bloku), a dla bloku bez pierscienia - 1 piksel do SCRATCH_VRAM.
;  - emit_block (render/frame.asm) porownuje maske polowek nowego bloku (RINGMASK_RAM) z RCMASK_RAM
;    i przy zmianie dopisuje slot do kolejki RCQ_RAM; rchain_apply po zbudowaniu listy przepisuje te wpisy
;    (lancuch wtedy nie biegnie - main_loop czeka na niego przed startem listy ramki);
;  - ring_bcbs przy zmianie klatki (bez pelnego przeladowania) zamiast BCB calego okna ustawia zr_pend;
;    rchain_start po zakonczeniu listy N (frame_done) wpisuje klatke do 2 pierwszych BCB i startuje lancuch
;    jako osobna liste blittera - przed lista N+1, ktora doladowuje bloki i maluje ich pierscienie BCB-ami
;    listy (ta sama klatka). Bloki doladowane w liscie N+1 lancuch moze pomalowac wg nowej maski na starej
;    tresci slotu - lista N+1 i tak nadpisuje caly blok przed widokiem.
;  Sloty spoza okna 9x7 dostaja grafike wg maski bloku, ktory w nich lezy - niewidoczne i nadpisywane przy
;  doladowaniu.
; =====================================================================

; rchain_init: lancuch w VRAM (wszystkie wpisy wylaczone), RCMASK_RAM = 0, kolejka pusta
rchain_init
	lda #MB_HUD
	jsr set_memac
	mwa #RCHAIN_CPU zp_dst
	mwa #rc_head zp_src
	ldy #BCB_BYTES
	jsr copy_n
	jsr dst_add21
	mwa #rc_head+BCB_BYTES zp_src
	ldy #BCB_BYTES
	jsr copy_n
	jsr dst_add21
	mwa #rc_off zp_src
	ldx #0
rci_l
	ldy #BCB_BYTES
	jsr copy_n
	jsr dst_add21
	lda #0
	sta RCMASK_RAM,x
	inx
	bpl rci_l                 ; 128 wpisow
	sec                       ; ostatni wpis bez NEXT
	lda zp_dst
	sbc #BCB_BYTES-20
	sta zp_dst
	bcs rci_nb
	dec zp_dst+1
rci_nb
	ldy #0
	lda #$00
	sta (zp_dst),y
	lda #0
	sta zr_q
	sta zr_pend
	sta zr_run
	lda #MB_LOW
	jmp set_memac

; rchain_apply: wpisy lancucha dla slotow z kolejki (maska z RCMASK_RAM). Po budowie listy.
rchain_apply
	lda zr_q
	bne rca_go
	rts
rca_go
	lda #MB_HUD
	jsr set_memac
	ldx #0
rca_l
	lda RCQ_RAM,x
	sta zp_t1                 ; slot s
	sta zp_bcb                ; zp_bcb = RCHAIN_CPU + (2 + s) * 21 = baza + s * 16 + s * 4 + s
	lda #0
	sta zp_bcb+1
	asl zp_bcb
	rol zp_bcb+1
	asl zp_bcb
	rol zp_bcb+1              ; s * 4
	lda zp_bcb
	clc
	adc zp_t1
	sta zp_t2
	lda zp_bcb+1
	adc #0
	sta zp_t3                 ; s * 5
	asl zp_bcb
	rol zp_bcb+1
	asl zp_bcb
	rol zp_bcb+1              ; s * 16
	lda zp_bcb
	clc
	adc zp_t2
	sta zp_bcb
	lda zp_bcb+1
	adc zp_t3
	sta zp_bcb+1              ; s * 21
	lda zp_bcb
	clc
	adc #<[RCHAIN_CPU+2*BCB_BYTES]
	sta zp_bcb
	lda zp_bcb+1
	adc #>[RCHAIN_CPU+2*BCB_BYTES]
	sta zp_bcb+1
	ldy zp_t1
	lda RCMASK_RAM,y
	bne rca_on
	ldy #6                    ; wylaczony: 1 piksel do SCRATCH_VRAM
	lda #<SCRATCH_VRAM
	sta (zp_bcb),y
	iny
	lda #[SCRATCH_VRAM>>8]&$FF
	sta (zp_bcb),y
	iny
	lda #SCRATCH_VRAM>>16
	sta (zp_bcb),y
	lda #0
	ldy #12
	sta (zp_bcb),y
	ldy #14
	sta (zp_bcb),y
	jmp rca_n
rca_on
	tay                       ; Y = maska 1 lewa, 2 prawa, 3 obie
	lda rc_w-1,y
	sta zp_t2                 ; szerokosc - 1
	lda rc_x-1,y
	sta zp_t3                 ; przesuniecie x w bloku
	lda zp_t1                 ; dst lo = (c & 7) << 5 + x
	and #7
	lsr
	ror
	ror
	ror
	ora zp_t3
	ldy #6
	sta (zp_bcb),y
	lda zp_t1                 ; dst mid = ((c >> 3) & 1) | ((r & 3) << 6) | $10 (8 linii w dol bloku)
	and #8
	lsr
	lsr
	lsr
	sta zp_t3
	lda zp_t1
	and #$30                  ; (r & 3) << 4
	asl
	asl
	ora zp_t3
	ora #$10
	iny
	sta (zp_bcb),y
	lda zp_t1                 ; dst hi = bank pierscienia + (r & 4) >> 2
	and #$40
	asl
	asl
	rol                       ; bit 6 -> bit 0
	clc
	adc #RING_VRAM>>16
	iny
	sta (zp_bcb),y
	lda zp_t2
	ldy #12
	sta (zp_bcb),y
	lda #15
	ldy #14
	sta (zp_bcb),y
rca_n
	inx
	cpx zr_q
	jne rca_l
	lda #0
	sta zr_q
	lda #MB_LOW
	jmp set_memac

; rchain_start: po zakonczeniu listy N - gdy lista N+1 zmienia klatke pierscieni: klatka do BCB glowy
; lancucha i start lancucha (bez czekania; main_loop czeka przed startem listy N+1)
rchain_start
	lda zr_pend
	beq rcs_ret
	lda #MB_HUD
	jsr set_memac
	lda zr_art
	sta RCHAIN_CPU+1          ; src mid obu BCB glowy = RINGART + klatka * 256
	sta RCHAIN_CPU+BCB_BYTES+1
	lda #MB_LOW
	jsr set_memac
	ldy #VC_BL_ADR0
	lda #<RCHAIN_VRAM
	sta (zp_fx),y
	iny
	lda #[RCHAIN_VRAM>>8]&$FF
	sta (zp_fx),y
	iny
	lda #RCHAIN_VRAM>>16
	sta (zp_fx),y
	ldy #VC_BLT_START
	lda #1
	sta (zp_fx),y
	sta zr_run
	lda #0
	sta zr_pend
rcs_ret
	rts

; rchain_wait: przed startem listy ramki - koniec lancucha (zwykle juz dawno)
rchain_wait
	lda zr_run
	beq rcw_ret
	jsr wait_blitter
	lda #0
	sta zr_run
rcw_ret
	rts

; glowa: klatka 16x16 (krok 16) -> RCUR2 lewa i prawa polowa (krok 32), kopia + NEXT
rc_head
	dta b(0),b(0),b(RINGART_VRAM>>16), a(16),b(1)
	dta b(<RCUR2_VRAM),b([RCUR2_VRAM>>8]&$FF),b(RCUR2_VRAM>>16), a(32),b(1)
	dta a(15),b(15)
	dta b($FF,$00,$00,$00,$00,$08)
	dta b(0),b(0),b(RINGART_VRAM>>16), a(16),b(1)
	dta b(<[RCUR2_VRAM+16]),b([[RCUR2_VRAM+16]>>8]&$FF),b(RCUR2_VRAM>>16), a(32),b(1)
	dta a(15),b(15)
	dta b($FF,$00,$00,$00,$00,$08)
; wpis wylaczony: RCUR2 -> SCRATCH_VRAM 1x1 (krok celu jak pierscien tla), kopia + NEXT
rc_off
	dta b(<RCUR2_VRAM),b([RCUR2_VRAM>>8]&$FF),b(RCUR2_VRAM>>16), a(32),b(1)
	dta b(<SCRATCH_VRAM),b([SCRATCH_VRAM>>8]&$FF),b(SCRATCH_VRAM>>16), a(512),b(1)
	dta a(0),b(0)
	dta b($FF,$00,$00,$00,$00,$08)
rc_w	dta b(15), b(15), b(31)   ; maska 1, 2, 3: szerokosc - 1
rc_x	dta b(0), b(16), b(0)     ; przesuniecie x w bloku
