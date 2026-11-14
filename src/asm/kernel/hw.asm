; =====================================================================
;  hw.asm - sprzet: VBXE (detekcja, MEMAC, blitter), banki rozszerzonej RAM 1088K, kopie pamieci
;  Pochodzenie: M1/M2 (docs/m1-runtime.md, docs/vbxe-rejestry.md, docs/u1mb-pamiec.md).
;  Rejestry VBXE adresowane posrednio: (zp_fx),y, gdzie zp_fx = $D600 albo $D700, Y = offset VC_*.
; =====================================================================

; ---------------------------------------------------------------------
; detect_fx: szuka VBXE FX pod $D640, potem $D740.
; Wyjscie: C = 0 -> znaleziony, zp_fx = strona rejestrow ($D600/$D700), v_minor = MINOR_REVISION;
;          C = 1 -> brak; v_fxseen = 1, gdy cos odpowiedzialo CORE_REVISION = $10 (zla wersja minor).
; ---------------------------------------------------------------------
detect_fx
	lda #0
	sta zp_fx                 ; strona rejestrow: najpierw $D600 (VBXE pod $D640)
	lda #$D6
	sta zp_fx+1
	jsr probe_fx
	bcc detect_fx_done        ; znaleziony pod $D640
	inc zp_fx+1               ; druga mozliwosc: $D700 (VBXE pod $D740)
	jsr probe_fx
detect_fx_done
	rts

; probe_fx: CORE_REVISION ($40) = $10 (FX) i MINOR_REVISION ($41, bez bitu 7) = $26 albo $27 -> C = 0
probe_fx
	ldy #VC_CORE_REV
	lda (zp_fx),y
	cmp #$10                  ; $10 = rdzen FX (GTIA emulation core ma inna wartosc)
	bne probe_bad
	lda #1
	sta v_fxseen              ; cos z rdzeniem FX jest - do rozroznienia statusu 1/2
	iny
	lda (zp_fx),y             ; MINOR_REVISION
	and #$7F                  ; bit 7 = rdzen RAMBO/inne - pomijamy
	sta v_minor
	cmp #$26                  ; FX 1.26
	beq probe_good
	cmp #$27                  ; FX 1.27
	bne probe_bad
probe_good
	clc
	rts
probe_bad
	sec
	rts

; ---------------------------------------------------------------------
; select_bank: A = numer banku 0..63 -> PORTB (schemat 1088K: bity 1-3 = n & 7, bity 5-7 = n >> 3).
; Bit 0 = 0 (OS ROM wylaczony - RAM pod OS dostepny), bit 4 = 0 (CPU widzi bank pod $4000-$7FFF).
; Na U1MB w 1088K bity 1/6/7 nie przelaczaja wtedy BASIC/GAME/self-test (tylko zapis z bitem 4 = 1).
; Debugger Altirry adresuje ten bank jako $PB'4000 (tools/m3_trace.portb_banku).
; Niszczy: A, zp_tmp, zp_tmp+1. Zachowuje: X, Y.
; ---------------------------------------------------------------------
select_bank
	sta zp_tmp
	and #7
	asl                       ; (n & 7) << 1 -> bity 1-3
	sta zp_tmp+1
	lda zp_tmp
	and #$38
	asl
	asl                       ; (n & $38) << 2 -> bity 5-7
	ora zp_tmp+1
	sta PORTB
	rts

; ---------------------------------------------------------------------
; test_banks_n (M7.2; dawne test_banks - 64 banki - i test_banks32 z src/scr/boot.asm - 32 nieparzyste): sprawdza n niezaleznych bankow
; pod $4000: A = n (1..TB_MAXN), X = pierwszy bank, Y = krok (bank i = X + i * Y). Wywolania: XEX testowy 64, 0, 1 (wymaganie 1088K -
; bufor trace'u); wydanie 32, 1, 2 (banki nieparzyste 1-63: bit PORTB 1 = 1 - BASIC wylaczony takze na RAMBO 320K, gdzie banki 1-31 sa
; aliasami 33-63 i test liczy 16 zgodnych) i w boot_check dodatkowo 64, 0, 1; M7.3 cart / ATR: 16, 33, 2 (zestaw roboczy 320K).
; Fazy jak dawniej: 1. zapamietanie 2 bajtow kazdego banku (save0 / save1 indeksowane numerem iteracji) i RAM glownej, 2. bank i: bajty
; bank, ~bank, 3. liczba zgodnych bankow (v_bankcnt - brak aliasow miedzy bankami), 4. czy RAM glowna (PB_MAIN) zachowala znacznik
; $A5/$5A (v_mainalias - alias banku na RAM glowna), 5. odtworzenie zawartosci. Wyjscie: C = 0 -> n bankow i brak aliasu.
; Przerwania wylaczone (select_bank wylacza OS ROM). Niszczy A, X, Y, zp_tmp.
; ---------------------------------------------------------------------
test_banks_n
	sta tbn_n
	stx tbn_b0
	sty tbn_st
	lda #0
	sta v_bankcnt
	sta v_mainalias
	lda #PB_MAIN
	sta PORTB                 ; RAM glowna pod $4000
	lda BANK_WIN
	sta main_save0
	lda BANK_WIN+1
	sta main_save1
	ldy #0                    ; faza: 0 zachowanie, 1 zapis, 2 sprawdzenie, 3 odtworzenie
tbn_faza
	sty tbn_f
	lda tbn_b0
	sta tbn_b                 ; bank biezacy
	ldx #0                    ; iteracja (indeks save0 / save1)
tbn_l
	lda tbn_b
	jsr select_bank           ; X, Y zachowane
	ldy tbn_f
	beq tbn_save
	dey
	beq tbn_write
	dey
	beq tbn_check
	lda save0,x               ; 3: odtworzenie
	sta BANK_WIN
	lda save1,x
	sta BANK_WIN+1
	jmp tbn_nx
tbn_save                        ; 0: zachowanie bajtow testowych
	lda BANK_WIN
	sta save0,x
	lda BANK_WIN+1
	sta save1,x
	jmp tbn_nx
tbn_write                       ; 1: bank n - bajty n, ~n
	lda tbn_b
	sta BANK_WIN
	eor #$FF
	sta BANK_WIN+1
	jmp tbn_nx
tbn_check                       ; 2: bank zachowal swoje wartosci
	lda tbn_b
	cmp BANK_WIN
	bne tbn_nx
	eor #$FF
	cmp BANK_WIN+1
	bne tbn_nx
	inc v_bankcnt
tbn_nx
	clc
	lda tbn_b
	adc tbn_st
	sta tbn_b
	inx
	cpx tbn_n
	bne tbn_l
	lda #PB_MAIN              ; po fazie: RAM glowna pod $4000
	sta PORTB
	ldy tbn_f
	bne tbn_f1
	lda #$A5                  ; po zachowaniu: znacznik w RAM glownej (wykrycie aliasu bankow na RAM glowna)
	sta BANK_WIN
	lda #$5A
	sta BANK_WIN+1
tbn_f1
	cpy #2
	bne tbn_f2
	lda BANK_WIN              ; po sprawdzeniu: czy RAM glowna dalej ma znacznik $A5/$5A
	cmp #$A5
	bne tbn_alias
	lda BANK_WIN+1
	cmp #$5A
	beq tbn_f2
tbn_alias
	inc v_mainalias
tbn_f2
	iny
	cpy #4
	jne tbn_faza
	lda main_save0            ; 5. RAM glowna
	sta BANK_WIN
	lda main_save1
	sta BANK_WIN+1
	lda v_mainalias
	bne tbn_bad
	lda v_bankcnt
	cmp tbn_n
	bne tbn_bad
	clc
	rts
tbn_bad
	sec
	rts
tbn_n	dta b(0)                ; liczba bankow
tbn_b0	dta b(0)                ; pierwszy bank
tbn_st	dta b(0)                ; krok
tbn_b	dta b(0)                ; bank biezacy
tbn_f	dta b(0)                ; faza 0-3

; ---------------------------------------------------------------------
; init_memac: MEMAC A = okno 8 KiB VRAM pod $2000 dla CPU (MEMAC_CTL_V), test zapisu/odczytu
; w dwoch bankach okna ($00000 i $02000 VRAM). Wyjscie: C = 0 -> dziala, okno ustawione na MB_LOW.
; ---------------------------------------------------------------------
init_memac
	ldy #VC_MEMAC_CTL
	lda #MEMAC_CTL_V          ; baza $2000, dostep CPU, 8 KiB
	sta (zp_fx),y
	cmp (zp_fx),y             ; rejestr musi sie odczytac
	bne memac_bad
	ldy #VC_MEMAC_BANK
	lda #MB_LOW               ; VRAM $00000-$01FFF
	sta (zp_fx),y
	cmp (zp_fx),y
	bne memac_bad
	lda #$55                  ; $55 do VRAM $00000
	sta MEMAC_CPU
	lda #MB_LOW+2             ; okno na VRAM $02000 (jednostka MEMAC_BANK_SEL = 4 KiB)
	sta (zp_fx),y
	lda #$AA                  ; $AA do VRAM $02000
	sta MEMAC_CPU
	lda #MB_LOW
	sta (zp_fx),y
	lda MEMAC_CPU             ; z powrotem $00000: musi byc $55
	cmp #$55
	bne memac_bad
	lda #MB_LOW+2
	sta (zp_fx),y
	lda MEMAC_CPU             ; $02000: musi byc $AA
	cmp #$AA
	bne memac_bad
	lda #MB_LOW
	sta (zp_fx),y
	clc
	rts
memac_bad                       ; wylaczenie MEMAC, zeby nie przeslanial RAM pod $2000
	lda #0
	ldy #VC_MEMAC_BANK
	sta (zp_fx),y
	ldy #VC_MEMAC_CTL
	sta (zp_fx),y
	sec
	rts

; set_memac: A = MEMAC_BANK_SEL (okno 8 KiB pod $2000: wartosci parzyste, $80 + VRAM/4 KiB). Niszczy Y.
set_memac
	ldy #VC_MEMAC_BANK
	sta (zp_fx),y
	rts

; ---------------------------------------------------------------------
; copy_pages: kopia calych stron (samomodyfikujace sie adresy).
; Wejscie: A = strona zrodla, X = strona celu, zp_cnt = liczba stron (1..255). Niszczy A, X, zp_cnt.
; ---------------------------------------------------------------------
copy_pages
	sta cp_rd+2               ; starszy bajt adresu w lda $FF00,x
	stx cp_wr+2               ; starszy bajt adresu w sta $FF00,x
	ldx #0
cp_rd	lda $FF00,x
cp_wr	sta $FF00,x
	inx
	bne cp_rd
	inc cp_rd+2               ; nastepna strona
	inc cp_wr+2
	dec zp_cnt
	bne cp_rd
	rts

; copy_n: (zp_src) -> (zp_dst), Y bajtow (1..255), od konca. Zachowuje X.
copy_n
	dey
cn_l	lda (zp_src),y
	sta (zp_dst),y
	dey
	cpy #$FF                  ; az do indeksu 0 wlacznie
	bne cn_l
	rts

; dst_add21: zp_dst += BCB_BYTES (nastepny BCB listy)
dst_add21
	clc
	lda zp_dst
	adc #BCB_BYTES
	sta zp_dst
	bcc da_ok
	inc zp_dst+1
da_ok	rts

; =====================================================================
;  Blitter: run_list (start listy BCB i czekanie), wait_blitter (czekanie z limitem)
; =====================================================================

; run_list: A/X/Y = adres listy BCB w VRAM (lo/mid/hi) -> BL_ADR0-2, start, czekanie na koniec.
run_list
	sty zp_tmp
	ldy #VC_BL_ADR0
	sta (zp_fx),y
	iny
	txa
	sta (zp_fx),y             ; BL_ADR1
	iny
	lda zp_tmp
	sta (zp_fx),y             ; BL_ADR2
	ldy #VC_BLT_START
	lda #1                    ; start blittera od BCB pod BL_ADR
	sta (zp_fx),y
	jmp wait_blitter

; wait_blitter: czeka, az BLITTER_BUSY (bity 0-1 rejestru $53) = 0. Limit ok. 65536 obiegow
; (zp_cnt x X), po nim status 5 (fail). Niszczy A, X, Y, zp_cnt.
wait_blitter
	ldx #0
	stx zp_cnt
	ldy #VC_BLT_START
wb_poll
	lda (zp_fx),y
	and #3                    ; bit 0 = busy, bit 1 = oczekuje na start
	beq wb_done
	dex
	bne wb_poll
	dec zp_cnt
	bne wb_poll
	lda #5                    ; blitter nie konczy listy
	jmp fail
wb_done
	rts
