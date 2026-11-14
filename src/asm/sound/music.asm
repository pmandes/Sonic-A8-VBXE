; =====================================================================
;  music.asm - M5.2: muzyka gry (SAP-R z wersji C64, LZSS16) odtwarzana w NMI (docs/plan-m5.md)
;
;  Dekoder LZSS16: adaptacja asm/playlzs16.asm z dmsc/lzss-sap, Copyright (c) 2020 Daniel Serpell,
;  licencja MIT (docs/licencje/LICENSE-DMSC.txt; upstream commit 64d3542163a52899c1f4d3a23185f3f5395b7e92),
;  przez experiments/sonic-atari-blitter-music/music.inc (procedury wolane przez JSR, wlasna strona zerowa,
;  bufory przeniesione, sterownik w VBI). Zmiany w grze: strumien w banku muzyki (BANK_MUSIC, NMI wlacza go na
;  czas ticku i przywraca PORTB), katalog utworow (tools/pack_music.py), utwory konczace sie bez petli,
;  wybor utworu numerem muzyki SMS (rst $18 oryginalu).
;  Kanal 3 POKEY zostaje dla efektow: strumienie AUDF3/AUDC3 i AUDCTL sa we wszystkich utworach stale
;  (pack_music.py to sprawdza), wiec dekoder pisze je tylko przy starcie utworu.
;  Kod i dane rezydentne ($8000+): wolane z NMI, a NMI nie moze wolac kodu spod $4100.
; =====================================================================

; snd_init: POKEY (zegary, bez IRQ), cisza; muzyka wylaczona. Przy starcie programu (NMI wylaczone).
snd_init
	lda #0
	sta mus_state
	sta sfx_on
	sta sfx_prio
	sta AUDCTL
	ldx #7
si_l
	sta AUDF1,x
	dex
	bpl si_l
	lda #3
	sta SKCTL                 ; zegary POKEY, klawiatura bez IRQ
	lda #1
	sta mus_phase
	rts

; snd_music_play: A = numer muzyki SMS ($00-$14, jak rst $18) -> utwor C64 z katalogu banku muzyki; start
; w nastepnym NMI. Wolac z kodu glownego (rezydentne - na chwile wlacza bank muzyki).
snd_music_play
	cmp #MUS_SMS_N
	bcs smp_ret
	tax
	lda #0
	sta mus_state             ; NMI nie dotyka zmiennych w trakcie zmiany
	lda mus_map,x
	sta mus_tune
	sec
	sbc #1                    ; wpis katalogu: BANK_WIN + 1 + (utwor - 1) * 6
	sta zp_tmp
	asl
	adc zp_tmp                ; * 3 (C = 0: utwor <= 16)
	asl                       ; * 6
	tax
	lda PORTB
	pha
	lda #PB_MUSIC
	sta PORTB
	lda BANK_WIN+1,x
	sta mus_start
	lda BANK_WIN+2,x
	sta mus_start+1
	lda BANK_WIN+3,x
	sta mus_frames
	lda BANK_WIN+4,x
	sta mus_frames+1
	lda BANK_WIN+5,x
	and #1
	sta mus_loop
	pla
	sta PORTB
	lda #0
	sta mus_remaining
	sta mus_remaining+1
	sta mus_fading
	jsr mus_quiet
	lda #1
	sta mus_fresh
	sta mus_state             ; na koncu - NMI startuje utwor
smp_ret
	rts

; snd_music_fade: snddrv_fade_out z HL = $0028 (fade_out_and_stop_level 00:20C3): co VBI licznik += $28,
; glosnosc kanalow muzyki - (licznik >> 8); licznik >= $1000 (103 VBI) -> cisza i stop, jak sterownik SMS
snd_music_fade
	lda mus_state
	beq smf_ret
	lda #0
	sta mus_fadeacc
	sta mus_fadeacc+1
	lda #1
	sta mus_fading
smf_ret
	rts

; snd_music_stop: rst $20 oryginalu (snddrv_stop) - muzyka i efekt stoja, kanaly cicho
snd_music_stop
	jsr snd_sfx_stop
	lda #0
	sta mus_state
	sta mus_fading
mus_quiet                       ; AUDC kanalow 1, 2, 4 = 0 (kanal 3 - efekty)
	lda #0
	sta AUDC1
	sta AUDC2
	sta AUDC4
	rts

; snd_nmi: z NMI (rejestry juz zachowane): muzyka, potem efekt (sound/sfx.asm) - kanal 3 i AUDCTL po muzyce
snd_nmi
	jsr mus_nmi
	jmp sfx_tick

; mus_nmi: PAL - ramka muzyki na VBI; NTSC - 5 ramek na 6 VBI (tempo 50 Hz); wyciszanie co VBI
mus_nmi
	lda mus_state
	beq sn_ret
	lda v_tv
	bne sn_play
	lda mus_phase
	clc
	adc #5
	cmp #6
	bcc sn_skip
	sbc #6
	sta mus_phase
sn_play
	lda PORTB                 ; strumien w banku muzyki; NMI mogl przerwac kod z innym bankiem
	pha
	lda #PB_MUSIC
	sta PORTB
	jsr mus_tick
	pla
	sta PORTB
sn_fade
	lda mus_fading            ; wyciszanie co VBI (takze w pominietych VBI NTSC), jak sterownik SMS
	beq sn_ret
	lda mus_state
	beq sn_ret                ; utwor bez petli skonczyl sie w tym ticku
	clc
	lda mus_fadeacc
	adc #$28
	sta mus_fadeacc
	lda mus_fadeacc+1
	adc #0
	sta mus_fadeacc+1
	cmp #$10
	bcc mus_fade_apply
	jmp snd_music_stop        ; licznik >= $1000: cisza
sn_ret
	rts
sn_skip
	sta mus_phase
	jmp sn_fade

; mus_fade_apply: AUDC1/2/4 = ostatnia zdekodowana wartosc z glosnoscia - (licznik >> 8) (min. 0)
mus_fade_apply
	ldx #1
	jsr mfa_ch
	ldx #3
	jsr mfa_ch
	ldx #7
mfa_ch                          ; X = rejestr AUDCn: wartosc z historii strumienia X - strona MUS_BUF + 8 - X
	stx mz_tmp                ; (dekoder idzie od X = 8), ramka cursor - 1, strumien staly - wartosc
	lda #[>MUS_BUF]+8         ; poczatkowa pod 255
	sec
	sbc mz_tmp
	sta mfa_ld+2
	ldy mz_cursor
	dey
	lda mus_mask
	and mfa_bits,x
	beq mfa_ld
	ldy #255
mfa_ld
	lda MUS_BUF,y
	sta mz_chbits
	and #$0F
	sec
	sbc mus_fadeacc+1
	bcs mfa_v
	lda #0
mfa_v
	sta mz_tmp
	lda mz_chbits
	and #$F0
	ora mz_tmp
	sta AUDF1,x
	rts
mfa_bits	dta b(0, $80, 0, $20, 0, 0, 0, $02) ; bit strumienia X w masce kanalow (b0 = AUDCTL ... b7 = AUDC1)

; mus_tick: dokladnie jedna ramka SAP-R. Na starcie (i petli) ramka 0 z wartosci poczatkowych strumienia;
; ostatnia ramka dostaje pelny czas. Utwor bez petli po ostatniej ramce - cisza i koniec.
mus_tick
	lda mus_remaining
	ora mus_remaining+1
	bne mt_frame
	lda mus_fresh
	ora mus_loop
	bne mt_restart
	lda #0                    ; koniec utworu bez petli
	sta mus_state
	jmp mus_quiet
mt_restart
	lda #0
	sta mus_fresh
	jsr mus_reset_decoder
	lda mus_frames
	sta mus_remaining
	lda mus_frames+1
	sta mus_remaining+1
	jmp mt_count
mt_frame
	jsr mus_decode_frame
mt_count
	lda mus_remaining
	bne mt_lo
	dec mus_remaining+1
mt_lo
	dec mus_remaining
	rts

; Carry przechodzi przez mus_get_byte (bit literal / dopasowanie).
mus_get_byte
	lda $FFFF                 ; samomodyfikujacy sie adres strumienia (kod w RAM)
	inc mus_ptr
	bne mgb_ok
	inc mus_ptr+1
mgb_ok
	rts
mus_ptr = mus_get_byte+1

mus_reset_decoder
	lda mus_start             ; bajt 0 strumienia = maska stalych strumieni (pominietych); dalej dane
	sta mus_ptr
	lda mus_start+1
	sta mus_ptr+1
	jsr mus_get_byte
	sta mus_mask
	lda #>MUS_BUF
	sta mrd_store+2           ; operand odtwarzany przy kazdym starcie
	lda #1
	sta mz_bitdata
	ldx #8
	ldy #0
mrd_seed
	jsr mus_get_byte
	sta AUDF1,x
	sty mz_copy,x
	sty mz_pos,x
mrd_store
	sta MUS_BUF+255
	inc mrd_store+2
	dex
	bpl mrd_seed
	sty mz_bufptr
	sty mz_cursor
	rts

mus_decode_frame
	lda #>MUS_BUF
	sta mz_bufptr+1
	lda mus_mask              ; maska strumieni (1 = staly - pominiety)
	sta mz_chbits
	ldx #8
mdf_l
	lsr mz_chbits
	bcs mdf_skip
	lda mz_copy,x
	bne mdf_copy
	lsr mz_bitdata
	bne mdf_bit
	jsr mus_get_byte
	ror
	sta mz_bitdata
mdf_bit
	jsr mus_get_byte
	bcs mdf_store
	sta mz_pos,x
	jsr mus_get_byte
	sta mz_copy,x
mdf_copy
	dec mz_copy,x
	inc mz_pos,x
	ldy mz_pos,x
	lda (mz_bufptr),y
mdf_store
	ldy mz_cursor
	sta AUDF1,x
	sta (mz_bufptr),y
mdf_skip
	inc mz_bufptr+1
	dex
	bpl mdf_l
	inc mz_cursor
	rts

; numer muzyki SMS (song_ptr_table 03:4716) -> utwor C64 (HVSC 1-16); docs/plan-m5.md
MUS_SMS_N = 21
mus_map
	dta b(1, 2, 3, 5, 6, 7)   ; $00-$05: GHZ, Bridge, Jungle, Labyrinth, Scrap Brain, Sky Base
	dta b(8, 16, 9, 11, 12)   ; $06 tytul, $07 mapa, $08 niezniszczalnosc, $09 koniec aktu, $0A smierc
	dta b(13, 13, 13, 14, 1)  ; $0B-$0D boss, $0E napisy, $0F (GHZ)
	dta b(4, 1, 1, 15, 10)    ; $10 etap specjalny, $11-$12 (GHZ), $13 dobre zakonczenie, $14 szmaragd

; stan odtwarzacza (rezydentny - NMI)
mus_state     dta b(0)        ; 0 = cisza, 1 = gra
mus_fresh     dta b(0)        ; 1 = pierwszy tick utworu (start niezaleznie od petli)
mus_loop      dta b(0)
mus_tune      dta b(0)
mus_phase     dta b(1)        ; NTSC: faza 5/6
mus_start     dta a(0)        ; adres strumienia w oknie banku
mus_frames    dta a(0)
mus_remaining dta a(0)
mus_mask      dta b(0)        ; maska stalych strumieni biezacego utworu
mus_fading    dta b(0)        ; 1 = wyciszanie (snd_music_fade)
mus_fadeacc   dta a(0)        ; licznik wyciszania (+$28 co VBI)
