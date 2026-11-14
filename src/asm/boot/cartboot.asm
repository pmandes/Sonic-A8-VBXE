; =====================================================================
;  cartboot.asm - M7.3: bank startowy cartridge'a (AtariMax 1 MB / SIC! 512 KB) - docs/plan-m7.md M7.3, docs/plan-m7-ldr.md 4.9,
;  docs/m7-nosniki.md 5.1-5.5.
;
;  Budowa (tools/build.cmd cart): osobna asemblacja dla kazdego typu cartu (-d:CART_TYPE=0 AtariMax, 1 SIC!) do XEX-a z trzema
;  segmentami (build/cartboot-am.xex, build/cartboot-sic.xex + .lab / .lst); tools/pack_cart.py sklada z nich bank startowy 8 KB:
;   - $A000-$A14F: naglowek katalogu 'SP' (16 B) i katalog obrazow CC_* (5 tablic po 64 B) - pisze pack_cart.py (kernel/mem.inc CC_*);
;   - $A150-: napis dla ludzi (nazwa gry, wersja, typ cartu) - ten plik;
;   - CB_ROMSTUB ($A200-$A2FF): obraz stubu startowego - segment $0600 tego pliku, z tablica blokow kodu cb_tab uzupelniona przez
;     pack_cart.py (adresy z build/cartboot-*.lab);
;   - CB_ROMCODE ($A300-): kod wejscia z ROM-u (kopia stubu do $0600 i skok);
;   - $BFFA-$BFFF: naglowek cartu OS-u XL: start = cb_entry, $BFFC = 0 (cart obecny), $BFFD = $04 (start po inicjalizacji OS-u,
;     bez bootu dyskietki, nie diagnostyczny), init = cb_init (rts).
;  AtariMax: ten sam bank w banku 0 i 127 (CAR 42 startuje z banku 127, CAR 75 / nowy sprzet z banku 0); SIC!: gorna polowka banku 0
;  (po wlaczeniu rejestr = $00: bank 0, okno $A000 wlaczone, $8000 wylaczone).
;
;  Start (OS XL po zimnym starcie -> jmp ($BFFA)):
;   1. cb_entry (ROM): sei, NMIEN = 0 (VBI OS-u nie moze biec przy przelaczaniu cartu - porownuje TRIG3 z GINTLK i przy roznicy
;      zawiesza system), kopia 256 B stubu do $0600, jmp $0600 - przelaczanie bankow zaslania kod w oknie $A000.
;   2. stub ($0600): stos, PORTB = $FF (OS ROM, BASIC wylaczony - inaczej po wylaczeniu cartu w $A000 pojawilby sie BASIC; BASICF = 1),
;      VBXE: nakladka i MEMAC wylaczone (po RESET-ie w trakcie gry okno MEMAC $2000 przeslanialo by RAM cracktro), kod surowy z cartu
;      (strumien od banku cb_t_bank, czesci od pelnych stron; AtariMax - okno $A000, SIC! - dolne polowki w oknie $8000): czesc 1 =
;      kod rezydentny $8000+ przez bufor $4000 (okno cartu zaslania cel: kopia do $4000, cart off, przeniesienie $4000 -> $8000,
;      cart on), czesc 2 = kod pod oknem $4100+, czesc 3 =
;      cracktro $2000+; cart wylaczony, GINTLK = TRIG3 (= 0: cartu nie ma - VBI OS-u w cracktro nie zawiesi systemu), jmp start_media
;      (src/scr/boot.asm: cracktro, trainer, boot_check, ldr_init - banki stale z cartu, machine_init, tytul / poziom).
;  Rejestr cartu tylko zapisem sta abs (odczyt i tryby indeksowane $D5xx przelaczaja bank AtariMax - HRM 8.2).
;  Strona zerowa stubu: $80-$86 (BASIC / FP nie dzialaja; OS uzywa $00-$7F), przerwania wylaczone przez caly stub.
; =====================================================================
	icl 'atari.inc'
	icl 'kernel/vbxe.inc'
	icl 'kernel/mem.inc'          ; CART_*, CC_*, CODE_LO, BANK_WIN (MEDIA = MEDIA_CART z linii polecen)

	.if MEDIA<>MEDIA_CART
	.error "cartboot.asm: budowa tylko z -d:MEDIA=1 -d:CART_TYPE=n (tools/build.cmd cart)"
	.endif

CB_RAM      = $0600          ; stub startowy w RAM (strona 6: wolna dla programu; po starcie gry - CRK_* cracktro od $0680)
CB_ROMSTUB  = $A200          ; obraz stubu w banku startowym (pack_cart.py kopiuje tu segment $0600)
CB_ROMCODE     = $A300          ; kod wejscia z ROM-u
CB_ROMTEXT      = $A150          ; napis
VBXE0        = $D600          ; strony rejestrow VBXE ($D640 albo $D740 - jak detect_fx w kernel/hw.asm)
VBXE1        = $D700

; strona zerowa stubu (tylko w czasie startu - OS bez VBI, BASIC nie dziala)
cs_src       = $80            ; (2) zrodlo w oknie cartu $A000-$BFFF
cs_dst       = $82            ; (2) cel w RAM
cs_bank      = $84            ; biezacy bank logiczny 8 KB
cs_mv        = $85            ; (2) przeniesienie bufora $4000 -> $8000
cs_rem       = $87            ; reszta czesci (< 256 B)

; okno strumienia kodu surowego (tools/pack_cart.py): AtariMax - banki logiczne od 1 w oknie $A000-$BFFF; SIC! - DOLNE polowki bankow
; 16 KB od banku 0 w oknie $8000-$9FFF (bit 5 rejestru = 1). Gra czyta SIC! tylko przez okno $A000 (gorne polowki - obrazy), bo okno
; $8000 zaslania kod rezydentny; stub dziala z $0600 i pisze tylko do $2000-$7FFF, wiec dolne polowki moze czytac - 32 KB kodu nie
; zajmuje gornych polowek (SIC! 512 KB: obrazy 27/32 gornych polowek zamiast 31/32).
	.if CART_TYPE=CART_AM
CS_WIN       = CART_WIN
CS_END       = CART_END
CS_BIT        = 0
	.else
CS_WIN       = $8000
CS_END       = $A000
CS_BIT        = $20            ; bit 5: okno $8000 wlaczone (dolna polowka banku); bit 6 = 0 - okno $A000 tez (bez znaczenia)
	.endif

; =====================================================================
;  Stub startowy ($0600, <= 256 B) - wykonywany z RAM, bo kopia przelacza banki cartu
; =====================================================================
	org CB_RAM
cb_stub
	ldx #$FF
	txs                       ; stos od nowa - do OS-u nie wracamy
	lda #$FF                  ; PORTB: b0 = 1 OS ROM, b1 = 1 BASIC wylaczony (po wylaczeniu cartu $A000-$BFFF = RAM), b4 = 1 RAM
	sta PORTB                 ; glowna pod $4000, b7 = 1 self-test wylaczony
	lda #1
	sta BASICF                ; OS: BASIC wylaczony (cien bitu 1 PORTB dla RESET-u)
	lda VBXE0+VC_CORE_REV     ; VBXE pod $D640: nakladka (VIDEO_CONTROL) i okna MEMAC A / B wylaczone - rejestry VBXE przezywaja
	cmp #$10                  ; RESET, a okno MEMAC A $2000-$3FFF przeslanialo by RAM cracktro
	bne cs_v7
	lda #0
	sta VBXE0+VC_VIDEO
	sta VBXE0+VC_MEMAC_B
	sta VBXE0+VC_MEMAC_CTL
cs_v7
	lda VBXE1+VC_CORE_REV     ; to samo dla VBXE pod $D740
	cmp #$10
	bne cs_v0
	lda #0
	sta VBXE1+VC_VIDEO
	sta VBXE1+VC_MEMAC_B
	sta VBXE1+VC_MEMAC_CTL
cs_v0
	lda cb_t_bank             ; strumien kodu surowego: od poczatku banku cb_t_bank (pack_cart.py)
	sta cs_bank
	lda #<CS_WIN
	sta cs_src
	lda #>CS_WIN
	sta cs_src+1
	jsr cs_on
	ldx #0
	jsr cs_part               ; 1. kod rezydentny $8000-(CODE_HI_END-1) -> bufor $4000 (<= 16 KB)
	jsr cs_off                ;    cart wylaczony: $8000-$BFFF = RAM
	lda #<BANK_WIN            ;    przeniesienie bufora $4000 -> $8000 (cb_t_mv pelnych stron - do $BFFF najwyzej)
	sta cs_mv
	sta cs_dst
	lda #>BANK_WIN
	sta cs_mv+1
	lda #$80
	sta cs_dst+1
	ldx cb_t_mv
	ldy #0
cs_m
	lda (cs_mv),y
	sta (cs_dst),y
	iny
	bne cs_m
	inc cs_mv+1
	inc cs_dst+1
	dex
	bne cs_m
	jsr cs_on                 ;    cart z powrotem (ten sam bank i miejsce strumienia)
	ldx #1
	jsr cs_part               ; 2. kod pod oknem bankow -> $4100 (nadpisuje bufor)
	ldx #2
	jsr cs_part               ; 3. cracktro -> $2000
	jsr cs_off                ; cart wylaczony: TRIG3 = 0
	lda TRIG3
	sta GINTLK                ; uzgodnienie blokady cartu - VBI OS-u (cracktro, boot_check) nie zawiesi systemu
	jmp (cb_t_run)            ; start_media (src/scr/boot.asm)

; cs_part: czesc X strumienia (cb_t_np[x] pelnych stron + cb_t_nr[x] B) -> RAM od strony cb_t_dst[x]. Strumien zaczyna kazda czesc od
; pelnej strony (pack_cart.py wyrownuje), wiec strona zrodla nigdy nie przechodzi przez koniec okna $BFFF.
cs_part
	lda #0
	sta cs_dst
	lda cb_t_dst,x
	sta cs_dst+1
	lda cb_t_nr,x
	sta cs_rem
	ldy #0
	lda cb_t_np,x
	tax                       ; X = pelne strony
	beq cs_rm
cs_pg
	lda (cs_src),y
	sta (cs_dst),y
	iny
	bne cs_pg
	inc cs_dst+1
	jsr cs_next
	dex
	bne cs_pg
cs_rm
	ldx cs_rem                ; reszta czesci (< 256 B)
	beq cs_ret
cs_rl
	lda (cs_src),y
	sta (cs_dst),y
	iny
	dex
	bne cs_rl
	jsr cs_next               ; nastepna czesc od nastepnej strony strumienia
cs_ret
	rts

; cs_next: nastepna strona strumienia; koniec okna (CS_END) -> nastepny bank od poczatku okna. Zachowuje X, Y.
cs_next
	inc cs_src+1
	lda cs_src+1
	cmp #>CS_END
	bne cs_nr
	lda #>CS_WIN
	sta cs_src+1
	inc cs_bank
	jmp cs_on
cs_nr
	rts

; cs_on: cart wlaczony z bankiem cs_bank w oknie strumienia (CS_WIN); cs_off: cart wylaczony. Zachowuja X, Y.
cs_on
	lda cs_bank
	.if CART_TYPE=CART_AM
	sta cs_osm+1              ; AtariMax: bank = bity 0-6 adresu zapisu - podmieniony mlodszy bajt operandu (sta abs, bez odczytu)
cs_osm	sta CART_REG
	.else
	ora #CS_BIT                ; SIC!: bank (bity 0-4), b5 = 1 okno $8000 (dolna polowka - strumien kodu), b6 = 0 okno $A000
	sta CART_REG
	.endif
	rts
cs_off
	.if CART_TYPE=CART_AM
	sta CART_AM_OFF           ; AtariMax: dostep do $D580 - cart wylaczony
	.else
	lda #CART_SIC_OFF         ; SIC!: oba okna wylaczone
	sta CART_REG
	.endif
	rts

; tablica blokow kodu surowego - wypelnia tools/pack_cart.py (adresy etykiet z build/cartboot-*.lab); czesci: 0 kod rezydentny (do bufora
; $4000), 1 kod pod oknem ($4100), 2 cracktro ($2000)
cb_tab
cb_t_bank	dta b(0)              ; bank poczatku strumienia (od CS_WIN): AtariMax - logiczny 1, SIC! - 0 (dolna polowka)
cb_t_np	dta b(0, 0, 0)          ; pelne strony czesci 0-2
cb_t_nr	dta b(0, 0, 0)          ; reszta czesci (B)
cb_t_dst	dta b($40, $41, $20)  ; strona celu czesci (pack_cart.py nadpisuje z etykiet buildu gry)
cb_t_mv	dta b(0)                ; strony przenoszone $4000 -> $8000 (czesc 0)
cb_t_run	dta a(0)              ; start_media
cb_stub_end
	.if cb_stub_end>CB_RAM+$100
	.error "stub startowy cartu > 256 B"
	.endif                    ; (CRK_* $0680-$0683 moga lezec na stubie - cracktro pisze je dopiero po skoku do start_media)

; =====================================================================
;  Bank startowy w oknie $A000-$BFFF (ROM)
; =====================================================================
	org CB_ROMTEXT
	.if CART_TYPE=CART_AM
	dta c'SONIC A8 VBXE v1.0 - AtariMax 1MB (CAR 42/75)',0
	.else
	dta c'SONIC A8 VBXE v1.0 - SIC! 512KB (CAR 56)',0
	.endif
	dta c'VBXE FX 1.26+, 320K RAM. Not for sale.',0
cb_text_end
	.if cb_text_end>CB_ROMSTUB
	.error "napis banku startowego nachodzi na obraz stubu"
	.endif

	org CB_ROMCODE
; cb_entry: start z OS-u (jmp ($BFFA)) - cart widoczny w oknie $A000 (AtariMax: bank 127 albo 0; SIC!: bank 0)
cb_entry
	sei
	lda #0
	sta NMIEN                 ; VBI / DLI OS-u stop (TRIG3 / GINTLK - przelaczanie cartu)
	sta DMACTL                ; ANTIC bez DMA: przy carcie RAMTOP = $A0, wiec ekran i display lista E: OS-u leza w $9C20-$9FFF - stub
	sta SDMCTL                ; nadpisze je kodem gry, a DMA ze smieciowej DL moglo by czytac $D5xx (przelaczenie banku AtariMax,
	cld                       ; HRM 8.2). Cien SDMCTL = 0 - VBI OS-u (od start_media) nie wlaczy DMA; cracktro ustawia wlasna DL.
	ldx #0
ce_l
	lda CB_ROMSTUB,x         ; obraz stubu (256 B) -> $0600
	sta CB_RAM,x
	inx
	bne ce_l
	jmp CB_RAM
; cb_init: wektor init cartu ($BFFE) - OS wola go jsr-em w czasie inicjalizacji; nic do zrobienia
cb_init
	rts

	org $BFFA
	dta a(cb_entry)           ; $BFFA: start (OS skacze tu po inicjalizacji - $BFFD bit 2)
	dta b(0)                  ; $BFFC = 0: cartridge obecny
	dta b($04)                ; $BFFD: b2 = 1 start po init, b0 = 0 bez bootu dyskietki, b7 = 0 nie diagnostyczny
	dta a(cb_init)            ; $BFFE: init
