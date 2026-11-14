; =====================================================================
;  sfx.asm - M5.4: efekty dzwiekowe na kanale 3 POKEY (docs/plan-m5.md)
;
;  Dane: tools/pack_sfx.py - stan PSG oryginalu SMS na ramke (tools/m5_sfx_ref.py: sterownik dzwieku SMS
;  w Mesenie, kazdy efekt osobno) przeliczony na AUDF3/AUDC3 (bit 4 AUDC = kanal 3 na 1,79 MHz, AUDCTL b5),
;  w banku BANK_SFX: katalog 7 x N B (adres ramek, liczba ramek, ramka powrotu petli / $FFFF, priorytet),
;  dalej ramki po 2 B. Efekt SMS gra na jednym kanale PSG (ton 2 albo szum), a muzyka z wersji C64 nie
;  uzywa kanalu 3 POKEY - efekt nie wycisza muzyki (w SMS zajmowal kanal muzyki).
;  Priorytet jak snddrv_play_sound (03:4171): nowy efekt gra, gdy nic nie gra albo jego priorytet <= biezacego
;  (1 wazniejszy niz 2). Tick w kazdym VBI (sterownik SMS tez co VBI - w NTSC efekty szybciej, jak w oryginale),
;  po muzyce: zapis kanalu 3 i AUDCTL nadpisuje to, co muzyka wpisala przy starcie utworu.
;  Kod rezydentny (NMI). Wolajacy z kodu gry: game/sonic.asm play_sfx (rst $28).
; =====================================================================

	icl 'sfx_dir.inc'         ; SFX_N (tools/pack_sfx.py)

; snd_sfx_play: A = numer efektu SMS ($00-$22, rst $28). Zachowuje X, Y (przeklad logiki SMS ich uzywa).
snd_sfx_play
	cmp #SFX_N
	bcs ssp_ret0
	sta g_sfx_req_TEST        ; M5.4: zgloszenie w tym ticku - porownanie z referencja (m3_test, $DBFF)
	stx sfx_sx
	sty sfx_sy
	tax                       ; katalog: 7 tablic po SFX_N B (tools/pack_sfx.py), indeks = numer
	lda PORTB
	pha
	lda #PB_SFX
	sta PORTB
	lda BANK_WIN+6*SFX_N,x    ; priorytet: biezacy 0 albo nowy <= biezacy
	ldy sfx_prio
	beq ssp_ok
	cmp sfx_prio
	beq ssp_ok
	bcs ssp_rej
ssp_ok
	ldy #0
	sty sfx_on                ; NMI nie dotyka zmiennych w trakcie zmiany
	sta sfx_prio
	lda BANK_WIN,x
	sta sfx_ptr
	sta sfx_start
	lda BANK_WIN+SFX_N,x
	sta sfx_ptr+1
	sta sfx_start+1
	lda BANK_WIN+2*SFX_N,x
	sta sfx_left
	sta sfx_count
	lda BANK_WIN+3*SFX_N,x
	sta sfx_left+1
	sta sfx_count+1
	lda BANK_WIN+4*SFX_N,x
	sta sfx_loop
	lda BANK_WIN+5*SFX_N,x
	sta sfx_loop+1
	lda #0
	sta AUDC3                 ; jak sterownik SMS: kanal efektu od razu cicho
	lda #1
	sta sfx_on
ssp_rej
	pla
	sta PORTB
	ldx sfx_sx
	ldy sfx_sy
ssp_ret0
	rts

; snd_sfx_stop: koniec efektu (snddrv_stop tez zatrzymuje strumien efektu i zeruje priorytet)
snd_sfx_stop
	lda #0
	sta sfx_on
	sta sfx_prio
	sta AUDC3
	sta AUDCTL
	rts

; sfx_tick: z NMI (snd_nmi, rejestry zachowane) - jedna ramka efektu
sfx_tick
	lda sfx_on
	jeq sft_ret
	lda sfx_left
	ora sfx_left+1
	bne sft_frame
	lda sfx_loop+1            ; koniec ramek: petla albo cisza
	cmp #$FF
	jeq snd_sfx_stop
	lda sfx_loop              ; adres powrotu = start + powrot * 2, ramek = liczba - powrot
	asl
	sta sft_t
	lda sfx_loop+1
	rol
	sta sft_t+1
	clc
	lda sfx_start
	adc sft_t
	sta sfx_ptr
	lda sfx_start+1
	adc sft_t+1
	sta sfx_ptr+1
	lda sfx_count
	sec
	sbc sfx_loop
	sta sfx_left
	lda sfx_count+1
	sbc sfx_loop+1
	sta sfx_left+1
sft_frame
	lda PORTB
	pha
	lda #PB_SFX
	sta PORTB
	lda sfx_ptr
	sta sft_ld+1
	sta sft_ld2+1
	lda sfx_ptr+1
	sta sft_ld+2
	sta sft_ld2+2
	inc sft_ld2+1
	bne sft_ld
	inc sft_ld2+2
sft_ld
	lda $FFFF                 ; AUDF3
	sta AUDF3
sft_ld2
	lda $FFFF                 ; AUDC3 (b4 = zegar 1,79 MHz)
	tax
	and #$EF
	sta AUDC3
	txa
	and #$10
	asl                       ; b4 -> b5 AUDCTL (kanal 3 na 1,79 MHz)
	sta AUDCTL
	pla
	sta PORTB
	clc
	lda sfx_ptr
	adc #2
	sta sfx_ptr
	bcc sft_dec
	inc sfx_ptr+1
sft_dec
	lda sfx_left
	bne sft_lo
	dec sfx_left+1
sft_lo
	dec sfx_left
sft_ret
	rts

; stan efektu (rezydentny - NMI)
sfx_on        dta b(0)
sfx_prio      dta b(0)        ; priorytet biezacego efektu (0 = brak)
sfx_ptr       dta a(0)        ; nastepna ramka (adres w oknie banku)
sfx_start     dta a(0)
sfx_left      dta a(0)        ; ramek do konca przebiegu
sfx_loop      dta a(0)        ; ramka powrotu petli ($FFFF = bez petli)
sfx_count         dta a(0)        ; liczba ramek efektu
sfx_sx        dta b(0)
sfx_sy        dta b(0)
sft_t         dta a(0)
