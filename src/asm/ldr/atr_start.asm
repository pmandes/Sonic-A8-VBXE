; =====================================================================
;  atr_start.asm - M7.4: kod fazy startu z dyskietki ATR (MEDIA_SIO; docs/plan-m7-ldr.md 2.3, 4.9, docs/plan-m7.md M7.4)
;
;  Lezy w RAM $2000+ zaraz za cracktro (src/game.asm: org crk_end) i jedzie tym samym segmentem pliku XAUTORUN (tools/pack_atr.py).
;  Wykonywany tylko przy starcie (start_media - RUN pliku XAUTORUN) i po RESET-cie (atr_reset2 - z czesci rezydentnej atr_reset w
;  src/ldr/ldr.asm), wiec nie zajmuje RAM rezydentnej $8000-$BFFF (w niej po ldr_fetch_sio i komunikatach zostawalo 34 B). Okno MEMAC A
;  ($2000-$3FFF) w grze pokazuje VRAM, a RAM pod nim nie jest zapisywany (nosnik 320K: nikt nie wylacza MEMAC poza RESET-em) - kod
;  przezywa cala gre; atr_reset wylacza MEMAC przed skokiem tutaj.
;  Oryginal SMS: brak odpowiednika (start z ROM-u); odpowiada temu INIT boot_check i ladowanie segmentow XEX-a wydania.
;  Bramka (tools/sprawdz_xex.py, LDR_MEDIA = 3): obszar ;@LDR jak czesc rezydentna fazy startu - skoki do czesci surowej $8000-kod_hi_start,
;  do cracktro i tego pliku, xBIOS-a (;@XBIOS), ROM-u OS-u (;@OS), kodu z obrazow tylko ze znacznikiem ;@KOD.
; =====================================================================
;@LDR
; ---------------------------------------------------------------------
; start_media (ATR): RUN pliku XAUTORUN - xBIOS (LOAD_BINARY_FILE) wgral czesc surowa i cracktro. OS wlaczony, VBI i IRQ klawiatury
; OS-u jak w XBIOS.CFG (NMIEN = $40, IRQEN = $C0), PORTB z XBIOS.CFG ($FF) z bitem 1 (BASIC) z chwili startu. Kolejnosc:
;  1. BASIC wylaczony (PORTB bit 1 = 1, BASICF = 1 - RESET go nie wlaczy): obraz kodu B51 siega $Bxxx (pod ROM-em BASIC-a);
;  2. RAMTOP = RAMSIZ = $A0 jak przy carcie: goracy start OS-u po RESET-cie i komunikat E: boot_check stawiaja ekran pod RAMTOP - przy
;     $C0 w $BC20-$BFFF nadpisal by RAM $BFFC (zero = OS widzi "cart" w RAM-ie), przy $A0 zostaje w $9C20-$9FFF (kod z obrazu B51 -
;     atr_reset i tak go wgrywa od nowa);
;  3. RESET: COLDST = 0 (goracy start), BOOT bit 0 = 1 (OS wola DOSINI - xBOOT nie wraca do OS-u, wiec OS mogl tego nie ustawic),
;     DOSINI = atr_reset; CRK_* = 0 (tryb testow crk_auto nie pisze CRK_INF - jak w carcie);
;  4. Ultra Speed: xBIOS odczytuje dzielnik napedu (xHSPEED, komenda $3F), ale transmituje z xSPEED (pomiar M7.4: Happy 1050 1,2 KB/s
;     -> 2,1 KB/s po xSPEED := xHSPEED); standard zapamietany w ld_xspd - po bledzie ldr_fetch_sio wraca do niego (lfs_slow);
;  5. cracktro (VBI i klawiatura OS-u) -> CRK_*; 6. atr_kod_load: NMI i DMA stop, "LOADING", obrazy kodu (ldr_kod), start_media_gl.
; Review M7.4: RAM $BFFC = $FF od razu po wylaczeniu BASIC-a (start bez BASIC-a - OPTION, U1MB, XEGS: RAMTOP $C0, ekran E: w $BC40-$BFFF,
; RAM $BFFC = 0 - RESET w cracktro / w ldr_kod: OS uznal by RAM za cart i skoczyl przez $BFFE); cart obecny (TRIG3 = 1 - zewnetrzny cart
; albo SDX w U1MB) zaslania $A000-$BFFF, a obraz B51 musi tam wejsc - komunikat przez E: i stop. Liczba ponowien komend SIO xBIOS-a
; (64, XB_RETRY w kernel/mem.inc) zostaje: pomiar na stock 1050 z dokladnym taktowaniem - zwykly OPEN_FILE po dlugim odczycie potrzebowal
; 20 szybkich ponowien (ok. 80 ms), przy 8 start z zestawu ED konczyl sie "INSERT DISK 1"; 64 x ok. 0,55 s (brak odpowiedzi napedu:
; otwarta klapka, brak dyskietki) = do ok. 35 s przed komunikatem - akceptowane.
; ---------------------------------------------------------------------
start_media
	sei
	cld
	ldx #$FF
	txs
	lda PORTB
	ora #2                    ; 1. BASIC wylaczony (xBIOS przepisuje bit 1 PORTB z chwili startu - "nie wylacza BASIC-a")
	sta PORTB
	lda #1
	sta BASICF
	lda TRIG3                 ;    cart w gniezdzie albo SDX w U1MB (TRIG3 = 1): $A000-$BFFF zasloniete - B51 nie wejdzie
	beq sm_bezcartu
	ldx #0                    ;    PUT CHARS na IOCB 0 (E: otwarty przez OS przy starcie) i stop
	lda #$0B
	sta ICCOM
	lda #<sm_cart_txt
	sta ICBAL
	lda #>sm_cart_txt
	sta ICBAH
	lda #<[sm_cart_end-sm_cart_txt]
	sta ICBLL
	lda #0
	sta ICBLH
	lda #$22
	sta SDMCTL
	lda #$40
	sta NMIEN
	cli
	jsr CIOV                  ;@OS
sm_stop
	jmp sm_stop
sm_cart_txt	dta $9B,c'SONIC A8 VBXE: DISABLE THE CARTRIDGE',$9B,c'/ SDX (U1MB: SDX OFF) AND BOOT AGAIN.',$9B
sm_cart_end
sm_bezcartu
	lda #$FF                  ;    (dopiero bez cartu - zapis pod $Bxxx nie trafi w rejestry cartu)
	sta CART_HDR_RAM          ;@KOD - RAM $BFFC <> 0 (pod nim nie ma jeszcze kodu - obraz B51 konczy sie przed $BFFC, tools/pack_atr.py)
	lda #$A0                  ; 2. RAMTOP / RAMSIZ jak z cartem (ekran E: OS-u w $9C20-$9FFF)
	sta RAMTOP
	sta RAMSIZ
	lda #0                    ; 3. RESET: goracy start z DOSINI = atr_reset
	sta COLDST
	sta atr_kod               ;    obrazy kodu jeszcze nie wgrane - RESET = zimny start (ponowny boot z dyskietki)
	sta CRK_SEL
	sta CRK_INF
	sta CRK_ACT
	sta CRK_NB
	lda #<atr_reset
	sta DOSINI
	lda #>atr_reset
	sta DOSINI+1
	lda BOOT
	ora #1
	sta BOOT
	lda XB_SPEED              ; 4. Ultra Speed, gdy naped go zglosil (xHSPEED <> $FF)
	sta ld_xspd
	lda #0
	sta ld_proba
	lda XB_HSPEED
	cmp #$FF
	beq sm_std
	sta XB_SPEED
sm_std
	lda #$40                  ; 5. cracktro: VBI OS-u (cienie, zegar) i IRQ klawiatury
	sta NMIEN
	cli
	jsr crk_main              ;@CRK - cracktro $2000 (segment XAUTORUN): CRK_SEL / CRK_INF / CRK_ACT / CRK_NB
atr_kod_load                    ; 6. (takze RESET po wgraniu kodu - atr_reset2)
	sei
	lda #0
	sta NMIEN                 ; VBI OS-u stop do konca ladowania (ldr_init: NMI wylaczone, ld_nmien = 0)
	sta DMACTL                ; czern (cracktro zostawia SDMCTL = 0; VBI juz nie przepisze cienia)
	sta SDMCTL
	lda #1                    ; review M7.4: "LOADING" (ldr_napis, font OS-u) przez ldr_kod i ldr_init - na stock 1050 ok. 85 s; DMA
	sta ld_os                 ; wylaczy dopiero machine_init. ld_os = 1 (OS) i ld_pb = RAM glowna z OS-em: komunikaty ldr_msg wracaja
	lda #PB_MAIN|1            ; potem do "LOADING"
	sta ld_pb
	ldx #lm_load-lm_txt
	jsr ldr_napis
	jsr ldr_kod               ; B50 -> $4100+, B51 -> kod_hi_start+ (przez xBIOS, OS wlaczony)
atr_kod_done                    ; test / pomiar (tools/m7_nosnik_test.py): kod gry w RAM
	lda #1
	sta atr_kod               ; od teraz RESET = przeladowanie kodu i bankow stalych (atr_reset2)
	jmp start_media_gl        ;@KOD - src/scr/boot.asm (obraz B51): trainer (scr_boot), boot_check, start

; ---------------------------------------------------------------------
; atr_reset2: dalszy ciag atr_reset (src/ldr/ldr.asm: NMI, DMA, nakladka VBXE i MEMAC juz wylaczone, stos od nowa). Przed wgraniem kodu
; (cracktro, ldr_kod - atr_kod = 0) albo bez xBIOS-a ($0400 <> 'xB') - zimny start = ponowny boot z dyskietki 1. Potem: bufor xBIOS-a
; z powrotem na $0C00 (strona 3 nalezy znow do OS-u), trainer bez wyboru poziomu (CRK_INF zostaje) i atr_kod_load: kod z dyskietki
; od nowa (ekran E: goracego startu w $9C20-$9FFF nadpisal czesc obrazu B51), boot_check, start, ldr_init - tytul.
; Zestaw ED: kod i banki stale sa tylko na dyskietce 1 - przy innej w napedzie komunikat "INSERT DISK 1".
; ---------------------------------------------------------------------
atr_reset2
	lda XBIOS
	cmp #'x'
	bne ar_cold
	lda XBIOS+1
	cmp #'B'
	bne ar_cold
	lda atr_kod
	beq ar_cold
	lda #0
	sta CRK_SEL               ; tytul, nie poziom z trainera; nieskonczone zycia (CRK_INF) zostaja
	sta CRK_ACT
	sta CRK_NB
	ldx #XB_BUF_START
	clc
	jsr XBIOS_RELOCATE_BUFFER ;@XBIOS - bufor $0C00, bez kopii
	jmp atr_kod_load
ar_cold
	jmp COLDSV                ;@OS - zimny start: boot z dyskietki od nowa

; ---------------------------------------------------------------------
; ldr_kod: obrazy kodu z dyskietki przy starcie (OS wlaczony - ld_os = 1, NMI wylaczone - ld_nmien = 0): B50 (kod pod oknem banku
; CODE_LO+, okno $4000 = RAM glowna: PB_MAIN | 1) i B51 (kod_hi_start-code_hi_end: wynik zx02 zaczyna sie za czescia surowa -
; dzialajacy ldr nie jest nadpisywany; strumien w miejscu konczy sie najwyzej delta B za code_hi_end - tools/pack_atr.py: < $C000).
; ldr_load_code: A = id, X/Y = adres wyniku (lo/hi) - ld_dst na czas ladowania, potem BANK_WIN.
; ---------------------------------------------------------------------
ldr_kod
	lda #1
	sta ld_os
	lda #0
	sta ld_nmien
	lda #LDR_ID_KODLO
	ldx #<CODE_LO
	ldy #>CODE_LO
	jsr ldr_load_code
	lda #<CART_HDR_RAM        ; B51: strumien w miejscu konczy sie przed RAM $BFFC (granica kontroli w ldr_fetch_sio)
	sta ld_lim
	lda #>CART_HDR_RAM
	sta ld_lim+1
	lda #LDR_ID_KODHI
	ldx #<kod_hi_start
	ldy #>kod_hi_start
ldr_load_code
	sta ld_id
	stx ld_dst
	sty ld_dst+1
	lda #PB_MAIN              ; okno $4000 = RAM glowna (ldr_load_pb dodaje bit 0 OS-u: $FF)
	jsr ldr_load_pb
	lda #<BANK_WIN
	sta ld_dst
	lda #>BANK_WIN
	sta ld_dst+1
	lda #<[BANK_WIN+$4000+LDR_SPILL_N] ; granica dla obrazow bankow (B50 tez: koniec okna + LDR_SPILL)
	sta ld_lim
	lda #>[BANK_WIN+$4000+LDR_SPILL_N]
	sta ld_lim+1
	rts
;@LDR_END
atr_start_end
