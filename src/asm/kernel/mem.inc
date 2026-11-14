; =====================================================================
;  mem.inc - mapa pamieci CPU gry (docs/plan-m3.md 3.2)
;   $0080-$009F ZP kernela i renderera   $00A0-$00FF ZP gry
;   $0B00-$0FFF klatki Sonica, maski pierscieni, palety, priorytety i flagi blokow
;   $1000-$1FFF uklad poziomu (= SMS $C000-$CFFF)
;   $2000-$3FFF MEMAC A (VRAM)            $4000-$7FFF okno bankow 1088K
;   $8000-$BFFF kod i dane rezydentne     $E000-$EFFF lustro RAM SMS $D000-$DFFF (game/sms.inc)
;   $FFFA-$FFFF wektory (RAM pod OS)
; =====================================================================

; --- banki 1088K (nieparzyste >= 32: bit1 = 1 BASIC off, bit7 = 1 self-test off) ---
PB_LD_ATLAS  = $83         ; bank 33, OS on (ladowanie)
PB_LD_LEVEL  = $87         ; bank 35, OS on
PB_ATLAS     = $82         ; bank 33, OS off
PB_LEVEL     = $86         ; bank 35, OS off
PB_LD_SONIC  = $8B         ; bank 37, OS on: klatki Sonica w prawo (M3.6, tylko przy starcie - potem trace)
PB_SONIC     = $8A
PB_LD_SPR    = $8F         ; bank 39, OS on: klatki w lewo, tablica klatek, kafle sprite'ow (M3.6)
PB_SPR       = $8E
PB_LD_MUSIC  = $A3         ; bank 41, OS on: muzyka (M5, tools/pack_music.py); NMI czyta strumien z banku
PB_MUSIC     = $A2
PB_LD_SFX    = $A7         ; bank 43, OS on: efekty (M5.4, tools/pack_sfx.py); NMI czyta ramki z banku
PB_SFX       = $A6
PB_LD_OBJ    = $AB         ; bank 45, OS on: kod i dane obiektow (M4; dane z banku 1 ROM-u pod adresami SMS,
PB_OBJ       = $AA         ; tools/extract_sms.py: bank_objdata.bin, objdata.inc)
PB_LD_OBJART = $AF         ; bank 47, OS on: grafika obiektow - ikony monitorow, tabliczka (bank_objart.bin)
PB_OBJART    = $AE
OA_MONZONE   = $2900       ; M4.5: bank 47 - kopia kafli $5C-$5F grafiki strefy (8 bpp, 256 B; load_sprite_data)
PB_LD_SCR    = $C3         ; M6: bank 49, OS on: kod i dane ekranow przed poziomem (src/scr/ekrany.asm - ekran
PB_SCR       = $C2         ; tytulowy, mapa; dane z tools/extract_ekrany.py)
PB_LD_SCRA   = $C7         ; M6: bank 51, OS on: kafle tla ekranow 4 bpp ($4000 tytul, $6000 mapa 1)
PB_SCRA      = $C6
PB_LD_SCRB   = $CB         ; M6.2: bank 53, OS on: kafle tla ekranu wyniku 4 bpp ($4000; wspolne z game over)
PB_SCRB      = $CA
PB_LD_LEVEL2 = $CF         ; M6.3: bank 55, OS on: dane poziomu GHZ2 (tools/extract_sms.py --level ghz2; ten sam uklad
PB_LEVEL2    = $CE         ; banku co bank 35 - LB_*), wybor banku poziomu: v_pblevel (game_code.asm: lv_select)
PB_LD_LEVEL3 = $E3         ; M6.4: bank 57, OS on: dane poziomu GHZ3 (tools/extract_sms.py --level ghz3)
PB_LEVEL3    = $E2
PB_LD_BOSS   = $E7         ; M6.4: bank 59, OS on: grafika bossa GHZ3 i zwierzat 4 bpp, paleta bossa (tools/extract_sms.py: bank_boss.bin)
PB_BOSS      = $E6
PB_LD_ATLASSP = $EB        ; M6.5: bank 61, OS on: atlas kafli tla etapow specjalnych (8 bpp; tools/pack_special.py)
PB_ATLASSP   = $EA
PB_LD_SCRC   = $89         ; M6.11: bank 36, OS on (tylko wydanie): dane tytulu i mapy 1 (pary sprite'ow tytulu, RLE) oraz ekranow konca
PB_SCRC      = $88         ; (koniec_ram.bin, koniec_spin.bin, koniec_r0.bin) - kopiowane do RAM przed uzyciem (src/scr/boot.asm scr_data_copy)
PB_LD_LEVELSP2 = $81       ; M6.11: bank 32, OS on: etapy specjalne pionowe $1F / $23 (uklad 16 x 256; bloki na poziom $0800 / $0900)
PB_LEVELSP2  = $80
PB_LD_LEVELSP = $EF        ; M6.5: bank 63, OS on: dane poziomu etapow specjalnych $1C, $1D (ten sam uklad LB_*; bloki na poziom: $2000, $2100)
PB_LEVELSP   = $EE
PB_MAIN      = $FE
; M6.6: strefa Bridge (BRI1-3, g_level 3-5) - banki 1, 3, 5, 7, 9 (nieparzyste < 32: bit 1 = 1 BASIC wylaczony, bit 7 = 0 wybiera bank tylko na 1088K;
; XEX wymaga 1088K: boot_check/test_banks_n). Wybor banku strefy: tablice rol ldr_lvl (src/ldr/ldr.asm, M7.2) -> v_pbatlas, v_pblevel, v_pbzspr, v_pbobjz.
PB_LD_ATLASB = $03         ; bank 1, OS on: atlas kafli tla Bridge (tools/extract_sms.py --level bri1; 8 bpp)
PB_ATLASB    = $02
PB_LD_SPRB   = $07         ; bank 3, OS on: bank_sprites Bridge (kafle sprite'ow strefy $2000, paleta $1FB0 - jak bank 39; klatki Sonica zostaja w banku 39)
PB_SPRB      = $06
PB_LD_LEVELB1 = $0B        ; bank 5, OS on: dane poziomu BRI1
PB_LEVELB1   = $0A
PB_LD_LEVELB2 = $0F        ; bank 7, OS on: dane poziomu BRI2
PB_LEVELB2   = $0E
PB_LD_LEVELB3 = $23        ; bank 9, OS on: dane poziomu BRI3
PB_LEVELB3   = $22
; M6.7: strefa Jungle (JUN1-3, g_level 6-8) - banki 13 (atlas), 15 (sprite'y strefy), 17 / 19 / 21 (poziomy JUN1-3); tylko 1088K
PB_LD_ATLASJ = $2B         ; bank 13, OS on: atlas kafli tla Jungle
PB_ATLASJ    = $2A
PB_LD_SPRJ   = $2F         ; bank 15, OS on: kafle i paleta sprite'ow strefy Jungle
PB_SPRJ      = $2E
PB_LD_LEVELJ1 = $43        ; bank 17, OS on: dane poziomu JUN1
PB_LEVELJ1   = $42
PB_LD_LEVELJ2 = $47        ; bank 19, OS on: dane poziomu JUN2 (uklad pionowy 16 x 256)
PB_LEVELJ2   = $46
PB_LD_LEVELJ3 = $4B        ; bank 21, OS on: dane poziomu JUN3
PB_LEVELJ3   = $4A
; M6.8: strefa Labyrinth (LAB1-3, g_level 9-11) - banki 23 (atlas), 25 (sprite'y strefy), 27 / 29 / 31 (poziomy LAB1-3); tylko 1088K.
; Po LAB pasmo nieparzyste 1-31 jest pelne (docs/plan-m6.md 13.4)
PB_LD_ATLASL = $4F         ; bank 23, OS on: atlas kafli tla Labyrinth
PB_ATLASL    = $4E
PB_LD_SPRL   = $63         ; bank 25, OS on: kafle i paleta sprite'ow strefy Labyrinth (ART_09_83B6)
PB_SPRL      = $62
PB_LD_LEVELL1 = $67        ; bank 27, OS on: dane poziomu LAB1
PB_LEVELL1   = $66
PB_LD_LEVELL2 = $6B        ; bank 29, OS on: dane poziomu LAB2
PB_LEVELL2   = $6A
PB_LD_LEVELL3 = $6F        ; bank 31, OS on: dane poziomu LAB3 (arena bossa, caly poziom pod woda)
PB_LEVELL3   = $6E
PB_LD_OBJZ   = $27        ; bank 11, OS on: bank obiektow strefy (src/obj/objz.asm; dane z banku 2 ROM-u pod adresem SMS - $4000, kod w lukach)
PB_OBJZ      = $26
; M6.9: banki parzyste 2-16 (pasmo nieparzyste 1-31 pelne) - Scrap Brain i drugi bank obiektow strefy. Bit 1 PORTB = 0: na U1MB (1088K)
; bez wplywu na ROM BASIC-a przy bicie 4 = 0 (docs/u1mb-pamiec.md); inne rozszerzenia 1088K - nieobslugiwane (docs/plan-m6.md 14, decyzja 2)
PB_LD_OBJZ2  = $05        ; bank 2, OS on: drugi bank obiektow strefy (src/obj/objz2.asm; SBZ, SKY, poziom $12, etapy $1F-$23)
PB_OBJZ2     = $04
; M6.9: strefa Scrap Brain (SBZ1-3, g_level 12-14, pod-poziomy SBZ2 $14, $15) - banki 4 (atlas), 6 (sprite'y strefy), 8 / 10 / 12 (SBZ1-3),
; 14 ($14 - tez $17), 16 ($15); $16, $18, $19 = bank SBZ2 z innym startem (docs/plan-m6.md 14.1.2)
PB_LD_ATLASS = $09        ; bank 4, OS on: atlas kafli tla Scrap Brain (0C:884B)
PB_ATLASS    = $08
PB_LD_SPRS   = $0D        ; bank 6, OS on: kafle i paleta sprite'ow strefy Scrap Brain (09:8F75; Robotnik ART_0C_EF3F - krok 7)
PB_SPRS      = $0C
PB_LD_LEVELS1 = $21       ; bank 8, OS on: dane poziomu SBZ1
PB_LEVELS1   = $20
PB_LD_LEVELS2 = $25       ; bank 10, OS on: dane poziomu SBZ2 (128 x 32)
PB_LEVELS2   = $24
PB_LD_LEVELS3 = $29       ; bank 12, OS on: dane poziomu SBZ3
PB_LEVELS3   = $28
PB_LD_LEVELS4 = $2D       ; bank 14, OS on: dane pod-poziomu $14 (64 x 64; tabliczka konca SBZ2, szmaragd)
PB_LEVELS4   = $2C
PB_LD_LEVELS5 = $41       ; bank 16, OS on: dane pod-poziomu $15 (32 x 128; wiersze 64-127 z ukladu SBZ2)
PB_LEVELS5   = $40
; M6.10: strefa Sky Base (SKY1-3, g_level 15-17, pod-poziom $1A) - banki parzyste 18 (atlas SKY1/2, 0C:9CEE), 20 (atlas SKY3, 0C:B3B5),
; 22 (sprite'y strefy 09:99E0 + Robotnik; palety sprite'ow SKY1/2 i SKY3 - lv_select: sky_stash), 24 / 26 / 28 (SKY1-3; $1A = blok na
; poziom w banku SKY3; docs/plan-m6.md 15.8)
PB_LD_ATLASK = $45        ; bank 18, OS on: atlas kafli tla SKY1 i SKY2 (strefa flag 5, 224 bloki)
PB_ATLASK    = $44
PB_LD_ATLASK3 = $49       ; bank 20, OS on: atlas kafli tla SKY3 i $1A (strefa flag 7, 104 bloki)
PB_ATLASK3   = $48
PB_LD_SPRK   = $4D        ; bank 22, OS on: kafle i paleta sprite'ow strefy Sky Base (09:99E0; Robotnik ART_0C_EF3F - zappery $46)
PB_SPRK      = $4C
PB_LD_LEVELK1 = $61       ; bank 24, OS on: dane poziomu SKY1 (128 x 32; palety blyskawic LB_LIGHT1B / LB_LIGHT1C)
PB_LEVELK1   = $60
PB_LD_LEVELK2 = $65       ; bank 26, OS on: dane poziomu SKY2 (64 x 64)
PB_LEVELK2   = $64
PB_LD_OBJZ3  = $6D        ; bank 30, OS on: trzeci bank obiektow strefy (src/obj/objz3.asm; Sky Base - dane banku 2 ROM-u SKY, kod w jednej luce)
PB_OBJZ3     = $6C
PB_LD_LEVELK3 = $69       ; bank 28, OS on: dane poziomu SKY3 (64 x 64, arena bossa) i pod-poziomu $1A (kopie bloku LB_STASH3 / LB_STASH1A)
PB_LEVELK3   = $68
; --- M7.2: nosnik danych (stala budowy MEDIA, -d:MEDIA=n w tools/build.cmd; docs/plan-m7.md 2, docs/plan-m7-ldr.md 1.3) ---
; XEX 1088K trzyma wszystkie banki rezydentnie (ldr_need tylko wybiera banki, bez ladowania); nosniki 320K doczytuja obrazy bankow
; do 6 slotow zestawu roboczego (src/ldr/ldr.asm). Ten sam kod gry we wszystkich buildach - roznice tylko w .if MEDIA.
MEDIA_XEX    = 0           ; build/game.xex, build/sonic-a8-vbxe.xex: wszystko rezydentne (1088K)
MEDIA_CART   = 1           ; M7.3: AtariMax 1 MB / SIC! 512 KB (ldr_fetch_cart)
MEDIA_RAM    = 2           ; M7.2: RAMCART - obrazy zx02 w wolnych bankach 1088K (build/sonic-ram.xex, test w Altirze; ldr_fetch_ram)
MEDIA_SIO    = 3           ; M7.4: ATR przez xBIOS (ldr_fetch_sio)
	.ifndef MEDIA
MEDIA = MEDIA_XEX
	.endif
LDR_MEDIA    = MEDIA       ; kopia w .lab (stale -d: MADS-a nie trafiaja do pliku etykiet) - tools/sprawdz_xex.py rozpoznaje build nosnika
	.if MEDIA<>MEDIA_XEX
	.ifndef RELEASE
	.error "MEDIA <> MEDIA_XEX tylko w buildzie wydania (-d:RELEASE=1)"
	.endif
	.endif
; M7.3: nosnik 320K (cart, ATR - minimum sprzetowe RAMBO 320K, zestaw roboczy 16 bankow 33-63): banki stale wgrywa ldr_init z nosnika
; (OS wlaczony), bank 36 (ekrany) rozpuszczony w bankach stalych 41 / 43 / 59, start liniowy start_media (src/scr/boot.asm) zamiast
; INIT-ow XEX-a (boot_save / boot_restore / boot_release i ekrany w INIT wyciete), test pamieci 16 bankow. RAMCART (sonic-ram.xex,
; MEDIA_RAM) zostaje przy XEX-owym starcie i banku 36 - wymaga 1088K i tak.
	.if MEDIA=MEDIA_CART || MEDIA=MEDIA_SIO
NOSNIK_320   = 1
	.else
NOSNIK_320   = 0
	.endif
; --- M7.3: cartridge (MEDIA_CART; docs/m7-nosniki.md 5.1-5.5, docs/plan-m7.md M7.3) ---
; Typ (stala budowy -d:CART_TYPE=n, tools/build.cmd cart): dwa obrazy, dwa przebiegi MADS-a (kod obiektow w bankach 2/11/30/45/49 wola
; adresy kodu rezydentnego TEGO buildu, a ldr_fetch_cart ma inna dlugosc dla kazdego typu).
CART_AM      = 0           ; AtariMax 1 MB (8 Mbit): 128 bankow 8 KB w oknie $A000-$BFFF; bank = bity 0-6 ADRESU dostepu do $D500-$D57F,
                           ; $D580-$D5FF wylacza cart; CAR 42 (stary - po wlaczeniu bank 127) i 75 (nowy - bank 0): start w obu bankach
CART_SIC     = 1           ; SIC! 512 KB: 32 banki 16 KB, rejestr bajtowy $D500 (bity 0-4 bank, bit 5 = 1 wlacza okno $8000-$9FFF z dolna
                           ; polowka banku, bit 6 = 1 WYLACZA okno $A000-$BFFF z gorna polowka); CAR 56. Gra czyta tylko gorne polowki
                           ; (okno $A000): okno $8000 zaslonilo by ldr i NMI ($8000-$9FFF) i LDR_SPILL - patrz plan-m7.md "Wykonanie M7.3"
	.if MEDIA=MEDIA_CART
	.ifndef CART_TYPE
CART_TYPE = CART_AM
	.endif
LDR_CART_TYPE = CART_TYPE  ; kopia w .lab (tools/pack_cart.py, sprawdz_xex.py)
	.if CART_TYPE<>CART_AM && CART_TYPE<>CART_SIC
	.error "CART_TYPE: 0 (AtariMax) albo 1 (SIC!)"
	.endif
	.endif
CART_REG     = $D500       ; rejestr cartu: tylko sta abs (odczyt i tryby indeksowane z $D5xx przelaczaja bank AtariMax - HRM 8.2)
CART_AM_OFF  = $D580       ; AtariMax: zapis pod ten adres wylacza cart (okno $A000-$BFFF = RAM / BASIC)
CART_SIC_ON  = $00         ; SIC!: bank (bity 0-4) | CART_SIC_ON - okno $A000 wlaczone, okno $8000 wylaczone (stan po wlaczeniu zasilania)
CART_SIC_OFF = $40         ; SIC!: oba okna wylaczone
CART_WIN     = $A000       ; okno cartu uzywane przez gre i stub startowy (8 KB = bank logiczny; SIC!: gorna polowka banku 16 KB)
CART_HDR_RAM = $BFFC       ; M7.3 (review): RAM pod naglowkiem cartu - start_media wpisuje $FF (goracy start OS-u po RESET-cie nie widzi
                           ; w RAM-ie "cartu"); kod rezydentny konczy sie przed nim (asercja w game_code.asm)
CART_END     = $C000
CART_BOOT    = 0           ; bank logiczny startu i katalogu (AtariMax: identyczna kopia w banku 127 - CAR 42 startuje z 127)
; katalog obrazow w banku startowym (tools/pack_cart.py; ten sam uklad co katalog RAMCART RC_CAT - 5 tablic po CC_NID B indeksowanych
; id obrazu): bank logiczny poczatku pliku, adres pliku w oknie $A000 (lo, hi), dlugosc pliku (lo, hi; plik = naglowek 4 B + strumien zx02).
; Naglowek katalogu 16 B od $A000: 'SP', wersja formatu, 'A8', wersja gry 1.0, CART_TYPE, ... (opis: tools/pack_cart.py)
CC_HDR       = CART_WIN
CC_NID       = 64
CC_BANK      = CART_WIN+$10
CC_ADRL      = CC_BANK+CC_NID
CC_ADRH      = CC_ADRL+CC_NID
CC_LENL      = CC_ADRH+CC_NID
CC_LENH      = CC_LENL+CC_NID
CC_END       = CC_LENH+CC_NID
; --- M7.4: ATR przez xBIOS (MEDIA_SIO; docs/plan-m7-ldr.md 2-3, docs/plan-m7.md M7.4) ---
; xBIOS 4.3 (XXL, tools/bin/xbios/xbios.com, nota docs/licencje/xbios-NOTA.md) relokowany przez XBIOS.CFG (tools/pack_atr.py) na strone $04:
; biblioteka $0400-$07FF (wariant A'), bufor I/O 1 strona: $0C00 w fazie startu (cracktro, komunikat E: boot_check - OS uzywa stron 2-3),
; $0300 w grze (RELOCATE_BUFFER w ldr_init przed machine_init). Modul I/O = wewnetrzny SIO xBIOS-a (slowo I/O w XBIOS.CFG = 0): bez ROM-u
; OS-u i bez przerwan, xBIOS nie uzywa strony zerowej (test rozpoznawczy M7.4: $00-$FF i $2000-$3FFF nietkniete przez LOAD_DATA).
; API (strona xxl.atari.pl/xbios): wektory skokow od poczatku biblioteki; blad - C = 1. Pomiar M7.4: LOAD_DATA do konca pliku konczy sie
; C = 1 takze bez bledu (koniec pliku), wiec ldr ustawia SET_LENGTH = dlugosc i sprawdza wskaznik pliku xNOTE (= 4 + len_c).
; xBIOS po kazdym wywolaniu zostawia I = 0 (cli) i IRQEN = xIRQEN, AUDCTL / AUDF3-4 / SKCTL w stanie SIO.
XBIOS        = $0400       ; strona biblioteki (XBIOS.CFG: bajt 12 = >XBIOS)
XB_BUF_START = $0C         ; strona bufora I/O przy starcie (XBIOS.CFG: bajt 13)
XB_BUF_GRA   = $03         ; strona bufora I/O w grze (RELOCATE_BUFFER w ldr_init)
XBIOS_OPEN_FILE = XBIOS+$09        ; Y/X = adres nazwy 11 B (8 + 3, spacje): C = 1 - brak pliku (albo blad odczytu katalogu)
XBIOS_LOAD_DATA = XBIOS+$0C        ; Y/X = adres celu: dane od wskaznika pliku, SET_LENGTH B (domyslnie do konca pliku)
XBIOS_SET_LENGTH = XBIOS+$1E       ; Y/X = liczba bajtow nastepnego LOAD_DATA
XBIOS_RELOCATE_BUFFER = XBIOS+$39  ; X = strona bufora, C = 0 - bez kopii zawartosci
XB_SPEED     = XBIOS+$3E6  ; xSPEED: dzielnik POKEY transmisji (standard $28 = 19200 bodow)
XB_HSPEED    = XBIOS+$3E7  ; xHSPEED: dzielnik Ultra Speed odczytany z napedu (komenda $3F) albo $FF - naped bez Ultra Speed
XB_IRQEN     = XBIOS+$3E8  ; xIRQEN: IRQEN wpisywany przez xBIOS po operacji (gra: 0 - OS wylaczony, irq_handler = rti)
XB_NOTE      = XBIOS+$3F5  ; xNOTE: wskaznik pliku (3 B) - po LOAD_DATA = liczba przeczytanych bajtow od poczatku pliku
XB_STD       = $28         ; xSPEED standardowy (19200 bodow) - powrot po bledzie transmisji Ultra Speed
PUPBT1       = $033D       ; review M7.4: OS XL - pierwszy z bajtow PUPBT1-3 ($5C, $93, $25 = goracy start po RESET-cie); ldr_init zeruje
XB_RETRY     = XBIOS+$2DA  ; review M7.4: operand LDA #$40 - licznik ponowien komendy SIO (xBIOS 4.3, $06D9 po relokacji); NIE zmieniany:
                           ; stock 1050 (Altirra, dokladne taktowanie) potrzebowal 20 szybkich ponowien zwyklego OPEN_FILE (src/ldr/atr_start.asm)
; tablice obrazow ATR w czesci surowej ldr (uzupelnia tools/pack_atr.py w pliku XAUTORUN): id 0..LDR_NIMG-1 = obrazy manifestu,
; LDR_ID_KODLO / LDR_ID_KODHI = obrazy kodu (pod oknem $4100+ i rezydentny od kod_hi_start) - pliki Bnn.ZX2 jak obrazy bankow
LDR_NIMG     = 50          ; obrazy manifestu: id 1..49 (tools/pack_atr.py sprawdza najwyzsze id < LDR_NIMG)
LDR_ID_KODLO = LDR_NIMG    ; B50.ZX2: kod $4100-(code_lo_end-1)
LDR_ID_KODHI = LDR_NIMG+1  ; B51.ZX2: kod kod_hi_start-(code_hi_end-1)
LDR_ATR_N    = LDR_NIMG+2  ; dlugosc tablic ldr_img_disk / ldr_img_lenl / ldr_img_lenh
; komunikat zmiany dyskietki / bledu odczytu (ldr_msg): ANTIC tryb 2, font OS-u w ROM-ie ($E000 - PORTB bit 0 = 1 na czas komunikatu),
; display lista i wiersz tekstu w LAYOUT_RAM (poziom i tak laduje uklad od nowa po ldr_need: level_boot, tele_reload)
LDR_MSG_DL   = LAYOUT_RAM  ; display lista (18 B)
LDR_MSG_TXT  = LAYOUT_RAM+$40 ; wiersz tekstu (40 B, kody wewnetrzne ANTIC-a)
; test_banks_n (kernel/hw.asm): save0 / save1 maja TB_MAXN B (indeks = numer iteracji testu); parametry testu pamieci wydania
; (machine_init, boot_check) wg nosnika - asercje n <= TB_MAXN w miejscach wywolan
	.if MEDIA=MEDIA_XEX || MEDIA=MEDIA_RAM
TB_MAXN      = 64          ; XEX testowy: 64 banki 0-63; wydanie i RAMCART: dodatkowo 64 w boot_check
	.else
TB_MAXN      = 16          ; nosnik 320K: tylko zestaw roboczy - 96 B mniej
	.endif
	.if NOSNIK_320
TPAM_N        = 16          ; zestaw roboczy 320K: 16 bankow nieparzystych 33-63 (bit 1 PORTB = 1 - BASIC wylaczony; RAMBO 320K i 1088K)
TPAM_B0       = 33
TPAM_ST       = 2
	.else
TPAM_N        = 32          ; 1088K (wydanie XEX, RAMCART): 32 banki nieparzyste 1-63 (na RAMBO 320K banki 1-31 = aliasy 33-63 -> blad)
TPAM_B0       = 1
TPAM_ST       = 2
	.endif
	.if TPAM_N>TB_MAXN
	.error "test_banks_n: TPAM_N > TB_MAXN (save0 / save1)"
	.endif
; LD_ZONY = 1: XEX laduje wprost banki stref, aktow i obiektow strefy (build/assets/lvbanks.inc, banki 11/2/30 w src/game.asm) - XEX 1088K
; i pierwszy przebieg budowy sonic-ram (-d:RC_SRC=1: build/sonic-ram-src.xex - zrodlo obrazow RAMCART z kodem obiektow tego buildu).
; LD_ZONY = 0: sloty zestawu roboczego wypelnia wylacznie ldr (sonic-ram.xex: tylko obrazy RAMCART - build/pakiety/ramcart.inc).
; M7.3: cart - XEX buildu cartu (build/sonic-cart-am.xex, -sic.xex) to tylko kontener obrazow i kodu dla tools/pack_cart.py (nie do
; uruchamiania): LD_ZONY = 1, wszystkie obrazy (stale i slotow) z tego samego przebiegu co kod rezydentny.
; M7.4: ATR - tak samo jak cart: build/sonic-atr.xex to kontener kodu i obrazow dla tools/pack_atr.py (jeden przebieg MADS-a).
	.if MEDIA=MEDIA_XEX || MEDIA=MEDIA_CART || MEDIA=MEDIA_SIO
LD_ZONY = 1
	.else
	.ifdef RC_SRC
LD_ZONY = 1
	.else
LD_ZONY = 0
	.endif
	.endif
; sloty zestawu roboczego 320K (banki nieparzyste 33-63, OS off; docs/plan-m7.md 1.3) - wartosci = dzisiejsze PB_ATLAS / PB_LEVEL / PB_LEVEL2 /
; PB_LEVEL3 / PB_ATLASSP / PB_LEVELSP (w XEX te banki trzymaja GHZ i etapy specjalne). tools/manifest.py sprawdza zgodnosc z SLOTY.
PB_SL_ATLAS  = $82         ; bank 33: atlas tla strefy
PB_SL_LEVEL  = $86         ; bank 35: dane aktu (poziomu)
PB_SL_ZSPR   = $CE         ; bank 55: sprite'y strefy (+ Robotnik); GHZ, $12 i etapy - staly bank 39 (PB_SPR)
PB_SL_OBJZ   = $E2         ; bank 57: bank obiektow strefy (obraz banku 11, 2 albo 30)
PB_SL_LEVEL2 = $EA         ; bank 61: drugi bank poziomu (pod-poziomy SBZ2 $14/$15/$17) albo obiekty etapow specjalnych (obraz banku 30)
PB_SL_ATLAS2 = $EE         ; bank 63: atlas etapow specjalnych
; dekompresja w miejscu (M7.1): strumien zx02 konczy sie delta B ZA koncem wyniku - pelny bank 16 KB wychodzi do 16 B poza okno $7FFF, w kod
; rezydentny: LDR_SPILL = $8000-$800F (tylko MEDIA <> XEX; start za nim - game_code.asm). Bramka w tools/pack_zone.py (LDR_SPILL = 16).
LDR_SPILL    = $8000
LDR_SPILL_N  = 16
; role obrazow poziomu (tablice ldr_lvl / ldr_sub - build/assets/ldr_tables.inc; kolejnosc = zmienne v_pblevel, v_pbatlas, v_pbzspr, v_pbobjz
; i v_img w src/vars.asm)
LR_LEVEL     = 0           ; dane poziomu (slot LEVEL, alt: LEVEL2)
LR_ATLAS     = 1           ; atlas tla (ATLAS, alt: ATLAS2)
LR_ZSPR      = 2           ; sprite'y strefy (ZSPR, alt: staly bank 39)
LR_OBJZ      = 3           ; obiekty strefy (OBJZ, alt: LEVEL2)
	.if MEDIA<>MEDIA_SIO
CRK_SEL      = $0680       ; M6.3/M6.11: trainer w cracktro: 0 = normalny start (tytul, mapa), inaczej g_level + 1 - poziom od razu
                           ; bez tytulu i mapy (strona 6 nie jest ladowana przez zaden segment XEX; czyta scr_boot)
CRK_ACT      = $0682       ; M6.11: trainer - akt przed wybranym etapem specjalnym (boot_actlevel; inaczej 0)
CRK_NB       = $0683       ; M6.11: trainer - pierwszy etap specjalny za wybrana pozycja (g_next_bonus_level przez v_nbonus; $1C, ..., $24)
CRK_INF      = $0681       ; trainer w cracktro: 1 = nieskonczone zycia (czyta scr_boot -> v_inflives), 0 = normalnie
	.endif                    ; M7.4: ATR - strona 6 nalezy do xBIOS-a ($0400-$07FF): CRK_* to zmienne w czesci surowej ldr (src/ldr/ldr.asm)
BANK_WIN     = $4000
CODE_LO      = $4100       ; M3.8e: kod gry w RAM glownym pod oknem bankow (PB_MAIN), game.asm
; banki wybierane select_bank (bit 4 = 0, OS off; na U1MB bity 1/6/7 nie przelaczaja wtedy ROM-ow)
BANK_SCRIPT  = 34          ; skrypt wejsc trybu testowego (1 B/tick), wgrywany z debuggera: x:$88000
; M7.2: RAMCART (MEDIA_RAM, build/sonic-ram.xex) - obrazy zx02 ciagiem w wolnych bankach 1088K jak na carcie SIC! (16 KB/bank), w kolejnosci
; 38, 40, ..., 62, 0 (bez 34 - skrypt testow; tools/pack_zone.py RC_BANKI - ta sama lista); katalog w pierwszym banku od $4000 (5 tablic
; po 64 B indeksowanych id obrazu: indeks banku RAMCART, adres lo, adres hi, dlugosc pliku lo, hi). Bufor kopii: $2000 (MEMAC wylaczony).
RC_CAT       = BANK_WIN    ; katalog RAMCART (bank rc_pb[0])
RC_NID       = 64          ; dlugosc tablicy katalogu (id obrazu 1..63)
LDR_BUF      = $2000       ; bufor kopii strumienia RAMCART (pod oknem MEMAC A - RAM tylko przy MEMAC_CTL = 0)
LDR_BUF_N    = $2000       ; 8 KB: najdluzszy plik obrazu slotu 5,6 KB (tools/pack_zone.py sprawdza)
; bufor trace'u (M4.0, format v2): banki z tablicy tr_bank_tab (m3_trace.inc z tools/m3_trace.py: 0-32, 36-46
; parzyste, 48-63 - bez bankow danych ladowanych z XEX 33-47 nieparzystych i skryptu 34)

; --- RAM ---
; M7.4: RCMASK_RAM / RCQ_RAM przeniesione z $0700 / $0780 na strone 2 we WSZYSTKICH buildach (jedna mapa pamieci): na ATR $0400-$07FF
; zajmuje xBIOS (docs/plan-m7-ldr.md 2.3, wariant A'). Strona 2 (cienie OS-u) jest wolna, bo pisze je tylko rchain_init / emit_block
; w poziomie - po machine_init (OS wylaczony na zawsze); INIT-y XEX-a i faza startu nosnikow (OS wlaczony) nie uruchamiaja poziomu.
RCMASK_RAM   = $0200       ; 128 B: maska polowek z pierscieniem bloku w slocie pierscienia tla (M3.8b, rchain.asm)
RCQ_RAM      = $0280       ; 64 B: kolejka slotow do przepisania w lancuchu pierscieni (do $02BF)
KIND_RAM     = $0900       ; 2 * N_BLK_SLOTS (128 B): rodzaj BCB w slocie blokow listy (K_*, M3.8c) - pola stale tylko przy zmianie
SKIND_RAM    = $0980       ; 2 * N_SPR_SLOTS (80 B): rodzaj BCB slotu sprite'a obiektu (K_NOPA.., M4.9a, render/objspr.asm)
PRIOWIN_RAM  = $0A30       ; 32 B: bit kolumny c ukladu = okno c..c+8 ma blok z priorytetem (M4.9a, render/load.asm)
PRIOCOL_TMP  = $0A50       ; 32 B: robocze prio_win_init (bit kolumny z priorytetem)
demo_inputs  = $0800       ; 256 B: kopia ARRAY_demo_inputs (00:1BC6) i nastepnych bajtow ROM (M3.8: z $8000+)
WATERPAL_RAM = $0A70       ; M6.8: 96 B - paleta podwodna (32 x RGB) z banku poziomu (render/water.asm)
SPRPAL_RAM   = $0A00       ; 48 B: paleta sprite'ow (RGB) - kopia do wygaszania i przywracania (M3.7)
SONICFR_RAM  = $0B00       ; 84 x 2 B: obraz klatki Sonica w VRAM (mid, hi | $80 = odbicie); kierunek*42+klatka - M3.6
RINGMASK_RAM = $0C00       ; 256 B: polowki bloku z pierscieniem (b0 lewa, b1 prawa) - M3.5
PAL_RAM      = $0D00       ; 4 x 48 B: paleta tla + 3 palety cyklu (RGB)
PRIO_RAM     = $0E00       ; 256 B: 1 = blok nad obiektami
TILEFLAGS_RAM = $0F00      ; 256 B: flagi blokow strefy (bity 0-5 typ kolizji, bit 7 priorytet) - M3.2
LAYOUT_RAM   = $1000       ; uklad poziomu 4 KiB (SMS $C000-$CFFF): GHZ1 256 x 16 (wiersz = strona), GHZ2 128 x 32 (M6.3)
LAYROW_LO    = $FD00       ; M6.3: mlodszy bajt adresu wiersza ukladu (render/load.asm: lay_tables); M6.7: 256 wierszy (uklad pionowy 16 x 256 - JUN2), RAM pod OS (bylo $0A70 x 64)
LAYROW_HI    = $FE00       ; 256 x starszy bajt adresu wiersza (LAYOUT_RAM + wiersz * szerokosc); $0A70-$0AEF wolne
PHYS_RAM     = $C000       ; 4 KiB tablic kolizji (RAM pod OS, kopia z banku poziomu LB_PHYS) - M3.2
SONIC_RAM    = $F000       ; 1 KiB danych Sonica (RAM pod OS, kopia z LB_SONIC) - M3.3
MUS_BUF      = $F400       ; 9 x 256 B: historia strumieni dekodera muzyki (RAM pod OS, NMI) - M5.2
SONIC_PHYS   = SONIC_RAM+$000 ; 4 x 9 B parametrow fizyki (01:4DCB main, special stage, pod woda, speed shoes)
SONIC_SPEC   = SONIC_RAM+$040 ; 256 B: kod bloku specjalnego dla numeru bloku (bank 15 0F:B9ED)
SONIC_ANIM   = SONIC_RAM+$140 ; region ROM 01:591D-01:5B08 (mapy sprite'ow, LUT_sonic_anim_ptrs, animacje)
SONIC_ANIM_SMS = $591D        ; adres SMS poczatku regionu: Atari = adres SMS + (SONIC_ANIM - $591D)
SONIC_RINGMAP = SONIC_RAM+$3F0 ; 6 B LUT_ring_tile_index_map (00:23F9) - M3.5
MIRROR_RAM   = $E000       ; lustro RAM SMS $D000-$DFFF (4 KiB)
TRSH_A       = $D800       ; M4.0: cien bloku A trace'u (pola PORT_POLA, TR_NA <= 254 B; RAM pod OS, tylko test)
TRSH_B       = $D900       ; M4.0: cien bloku B trace'u (g_object_ptrs, 64 B)
BLKMAP_RAM   = $DD00       ; M6.9: 256 B - slot magazynu blokow VRAM dla numeru bloku (kopia LB_BLKMAP z banku poziomu; RAM pod OS,
                           ; za RLE mapy 2 $DA00-$DCFF - src/scr/boot.asm)
; M6.11 (wydanie): dane ekranow z banku 36 w RAM pod OS uzywanym przez gre tylko w poziomie (ekrany dzialaja z OS off - jak SCRV; takze w INIT
; XEX-a, gdy RAM glowny $0700-$1FFF nalezy do DOS-u). Kopiowane przed kazdym wejsciem do ekranow (src/scr/boot.asm scr_data_copy):
SCR_SPR_T_RAM = $F000      ; pary kafli sprite'ow tytulu (ekr_spr_tytul.bin, 975 B) - SONIC_RAM (poziom kopiuje go od nowa)
SCR_RLE_T_RAM = $D800      ; RLE tytulu (ekr_rle_tytul.bin, 302 B) - cien trace'u TRSH_A/B (tylko budowa testowa)
SCR_RLE_M_RAM = $DD00      ; RLE mapy 1, warstwy A i B (701 B, do $DFBC) - BLKMAP_RAM (poziom kopiuje go od nowa)
KO_R0_RAM    = $DA00       ; ekrany konca: koniec_r0.bin (721 B) - MAP2_RLE (mapa 2 w czasie konca nie wystepuje); adres > SR_OFS: palety
                           ; konca przez scr_sms_ptr jako "ROM" (src/scr/koniec.asm)
; M7.3: nosnik 320K (NOSNIK_320) - bank 36 (parzysty, poza zestawem 320K) rozpuszczony w wolnych koncach bankow stalych (docs/plan-m7.md 2,
; "Rewizja mapy"; src/game.asm - asercje miejsca, src/scr/boot.asm - scr_data_copy / ko_copy z tablica bankow sdc_pb). Adresy w oknie:
SCD_T        = BANK_WIN+$3300 ; bank 43 (PB_SFX, za ekr_mapa2.bin): ekr_spr_tytul.bin -> SCR_SPR_T_RAM (4 strony)
SCD_RT       = BANK_WIN+$3700 ; bank 43: ekr_rle_tytul.bin -> SCR_RLE_T_RAM (2 strony)
SCD_RM       = BANK_WIN+$3900 ; bank 43: ekr_rle_mapa1a.bin + ekr_rle_mapa1b.bin -> SCR_RLE_M_RAM (3 strony, do $7BFF)
SCD_KO       = BANK_WIN+$3100 ; bank 59 (PB_BOSS, za bank_boss.bin): koniec_ram.bin + koniec_spin.bin -> KO_RAM = LAYOUT_RAM (15 stron)
SCD_R0       = BANK_WIN+$3700 ; bank 41 (PB_MUSIC, za bank_music.bin): koniec_r0.bin -> KO_R0_RAM (3 strony)

; --- tablice kolizji w PHYS_RAM (tools/extract_sms.py: phys_tables), indeks = flagi bloku & $3F (0..63) ---
FACT_VHSLIDE = PHYS_RAM+$000 ; LUT_vertical_hslide_factors (00:3F90): poslizg Vx po kolizji pionowej (zbocza)
FACT_HVSLIDE = PHYS_RAM+$040 ; LUT_horizontal_vslide_factors_VESTIGIAL (00:3FBF): Vy po kolizji poziomej
FACT_YMAG    = PHYS_RAM+$080 ; LUT_y_magnet_factors (00:3FF0, od 16. pozycji bajty banku 1): "magnes" Y
PUSH_LO      = PHYS_RAM+$100 ; 4 x 64 mlodszych bajtow adresow profili (32 B) LUT_phys_tileflags_push_*
PUSH_HI      = PHYS_RAM+$200 ; 4 x 64 starszych bajtow
PUSH_RIGHT   = 0           ; offset tablicy push_right (01:4020) w PUSH_LO/HI
PUSH_LEFT    = 64          ; push_left  (01:411E)
PUSH_DOWN    = 128         ; push_down  (01:41EC)
PUSH_UP      = 192         ; push_up    (01:448A)

; --- strona zerowa kernela i renderera ---
zp_fx        = $80         ; (2) strona rejestrow VBXE
zp_src       = $82         ; (2)
zp_dst       = $84         ; (2)
zp_tmp       = $86         ; (2)
zp_cnt       = $88         ; (2)
zp_lo        = $8A         ; (2) wynik pomiaru
zp_fr0       = $8C
zp_vc0       = $8D
zp_bcb       = $8E         ; (2) wskaznik BCB (CPU, przez MEMAC)
zp_lay       = $90         ; (2) wskaznik wiersza ukladu
zp_c         = $92         ; kolumna bloku
zp_r         = $93         ; wiersz bloku
zp_k         = $94         ; numer bloku
zp_last      = $95         ; (2) ostatni BCB listy ramki
zp_e         = $97         ; licznik wpisow
zp_kb        = $98         ; pierwszy blok partii
zp_t0        = $99
zp_t1        = $9A
zp_t2        = $9B
zp_t3        = $9C
zp_ks        = $9D         ; M6.9: slot magazynu blokow (BLKMAP_RAM[zp_k]) - render/frame.asm emit_block

; --- strona zerowa gry ($A0-$FF: "rejestry" Z80 i temp gry od M3.2) ---
zg_ptr       = $A0         ; (2) wskaznik ogolny gry
zg_src       = $A2         ; (2)
zg_dst       = $A4         ; (2)
; "rejestry" Z80 dla przekladu logiki obiektow (game/motion.asm): IX = adres rekordu obiektu w lustrze
zg_obj       = $A6         ; (2) IX: rekord obiektu (np. object_list = $E3FC)
zg_bc        = $A8         ; (2) BC: przesuniecie X punktu testu kolizji (C, B)
zg_de        = $AA         ; (2) DE: przesuniecie Y punktu testu kolizji (E, D)
zg_hl        = $AC         ; (2) HL: wynik posredni (krawedz obiektu)
zg_tab       = $AE         ; offset tablicy profili PUSH_* (0/64/128/192)
zg_off       = $AF         ; wartosc z profilu kolizji (przesuniecie w bloku, ze znakiem)
zg_prof      = $B0         ; (2) adres profilu kolizji (32 B)
zg_a         = $B2         ; temp (wspolczynnik poslizgu, numer wiersza bloku)
; rejestry Z80 logiki Sonica (game/sonic.asm): HL, DE, B, C miedzy etapami objfunc_00_sonic
zs_hl        = $B4         ; (2) HL (zs_hl = L, zs_hl+1 = H)
zs_de        = $B6         ; (2) DE (zs_de = E, zs_de+1 = D)
zs_b         = $B8         ; B
zs_c         = $B9         ; C
zs_t         = $BA         ; (2) temp
; lancuch pierscieni (M3.8b, render/rchain.asm)
zr_q         = $BC         ; dlugosc kolejki RCQ_RAM
zr_pend      = $BD         ; 1 = lancuch do startu po zakonczeniu biezacej listy (zmiana klatki)
zr_art       = $BE         ; bajt srodkowy zrodla klatki (RINGART + k * 256)
zr_run       = $BF         ; 1 = lancuch biegnie (start listy ramki i flip w NMI to uwzgledniaja)
; pamiec wyniku hud_prio_near (M3.8c, render/hud.asm): okno bloku (bx, by) i wynik; zh_by = $FF - brak
zh_bx        = $C0
zh_by        = $C1
zh_res       = $C2
; pamiec BCB HUD-u w komplecie listy (M3.8d, render/hud.asm): [komplet 0, komplet 1]
zh_sig       = $C3         ; (2) $80 | v_hud_fl & 7 obiektow zapisanych w slotach (0 = brak)
zh_fbm       = $C5         ; (2) bufor obrazu (v_fbm) tych BCB
zh_n         = $C7         ; (2) liczba slotow HUD-u
zh_lastlo    = $C9         ; (2) ostatni BCB HUD-u (zp_last)
zh_lasthi    = $CB         ; (2)
; dekoder muzyki LZSS16 (M5.2, sound/music.asm): $D0-$E6
mz_copy      = $D0         ; (9) licznik kopiowania z historii na strumien
mz_pos       = $D9         ; (9) pozycja w historii strumienia
mz_bufptr    = $E2         ; (2) wskaznik strony historii
mz_cursor    = $E4         ; pozycja zapisu w historii (ramka mod 256)
mz_chbits    = $E5         ; maska pominietych strumieni (robocza)
mz_bitdata   = $E6         ; bity literal / dopasowanie
mz_tmp       = $E7         ; robocza NMI (wyciszanie)
; flagi rekordu trace'u jak w trace referencji (v_tr_fl - game/step.asm; zapis: game/trace.asm, w buildach nosnikow bez trace'u - M7.2)
F_SONIC      = 1
F_ROZGRZEWKA = 4
F_DEMO       = 8
; zapis trace'u (M4.0, game/trace.asm): $E8-$EE
zt_key       = $E8         ; 1 = klatka kluczowa (bloki w calosci, wszystkie sloty)
zt_n         = $E9         ; liczba par bloku / dlugosc wpisow sprite'ow
zt_np        = $EA         ; (2) miejsce licznika par w rekordzie
zt_f         = $EC         ; numer pola PORT_POLA
zt_l         = $ED         ; dlugosc pola
zt_y         = $EE         ; zachowany Y
; obiekty (M4.1, obj/dispatch.asm w banku 45): $F6-$FA; robocze aktywacji i rysowania na zs_* - rejestry
; Sonica sa wolne, bo Sonic dziala po obiektach
zo_vec       = $F6         ; (2) wektor funkcji obiektu (obj_call)
zo_i         = $F8         ; slot w petli dyspozytora (funkcje obiektow go nie zmieniaja)
zd_cx        = $F9         ; (2) draw_sprite_string: x biezacego sprite'a w wierszu
zo_b         = zs_hl       ; (2) aktywacja: adres granic typu (OD_BOUNDS + 8 * typ)
zo_h         = zs_de       ; (2) aktywacja: HL (porownania 16 bit)
zo_n         = zs_b        ; aktywacja: licznik slotow grupy
zo_pi        = zs_c        ; aktywacja: indeks w g_object_ptrs
zd_x         = zs_hl       ; (2) rysowanie: x ekranowe (obiekt - kamera, 16 bit)
zd_y         = zs_de       ; (2) rysowanie: y ekranowe
zd_r         = zs_b        ; rysowanie: licznik wierszy mapy
zd_map       = zs_t        ; (2) rysowanie: mapa sprite'ow (adres SMS = adres w banku 45)

; =====================================================================
; M7.5 (docs/plan-m7-ntsc.md, krok K1): renderer pod NTSC - nowe struktury jako stale adresow (vars.asm jest rezydentny
; i zerowany w machine_init; tu pamieci podreczne z jawnym resetem nt_reset - render/prio.asm, wolany z hud_clear przed
; kazdym init_list_set: level_boot, tele_reload). Zakresy sprawdzone na nowo po M7.2-M7.4 (asercje nizej):
;  - ZP $EF-$F5, $FB-$FF: wolne w grze (trace $E8-$EE, obiekty $F6-$FA); FP OS-u (CIX $F2, INBUFF $F3, FLPTR $FC - atari.inc)
;    nieuzywane (gra z OS off; faza startu nosnikow z OS on nie wola FP; xBIOS nie uzywa ZP - test M7.4); zx02 / cartboot
;    $80-$89; zmienne goracej sciezki sa robocze (ustawiane w kazdej liscie przed uzyciem), wiec zawartosc z fazy startu nie szkodzi
;  - RAM niska $09D0-$09FF (za SKIND_RAM) i $0AD0-$0AFF (za WATERPAL_RAM): w grze nieuzywane; na ATR xBIOS $0400-$07FF, bufor
;    I/O $0300 (gra) / $0C00 (start), komunikat $1000-$1067 - poza zakresami; INIT-y XEX-a (DOS w $0700-$1FFF) dzialaja przed poziomem
;  - RAM pod OS $DE00-$DFFF: ekrany pisza tam RLE mapy 1 (SCR_RLE_M_RAM $DD00-$DFBC) tylko poza poziomem - tu wylacznie dane
;    robocze listy (odtwarzane w kazdej liscie) i pamieci podreczne z resetem przy starcie poziomu; OS wlaczony (faza startu) widzi
;    tam ROM, gra pisze tylko przy PB_MAIN (OS off)
; =====================================================================
; --- ZP (Z3): gorace zmienne sciezki sprite'ow obiektow (wczesniej vars.asm - rezydent krotszy, dostep o 1 cykl tanszy) ---
v_ox         = $EF         ; x ekranu obiektu / wpisu tablicy sprite'ow (render/sprites.asm, objspr.asm, hud.asm)
v_tile       = $F0         ; kafel sprite'a 8x16
v_sy16       = $F1         ; (2) y ekranu wpisu (16 bit ze znakiem; obj_sprites: y SMS, gora = y + 1)
v_fbm        = $F3         ; bufor obrazu listy: bajt srodkowy i starszy (view_rects z v_tgt)
v_fbh        = $F4
v_sk         = $F5         ; indeks SKIND_RAM biezacego slotu sprite'a (baza kompletu set_skind + slot - SLOT_SPR)
v_skend      = $FB         ; Z3: koniec obszaru slotow sprite'ow kompletu (set_skind + N_SPR_SLOTS) - test wolnego slotu jednym cpy
v_sj         = $FC         ; obj_sprites: liczba wpisow do zrobienia / koniec slotow uzytych w poprzedniej liscie (indeks SKIND)
zm_t0        = $FD         ; M7.5: robocze prio_path / front_* / sonic_obj_m (render/prio.asm)
zm_t1        = $FE
zm_t2        = $FF
	.if v_ox<>$EF || v_skend<>$FB || zm_t2<>$FF || zd_cx+2<>$FB || zt_y+1<>v_ox
	.error "M7.5: ZP $EF-$F5 i $FB-$FF musza lezec miedzy trace'em (zt_y $EE) a obiektami (zo_vec $F6-zd_cx $FA)"
	.endif
; --- RAM niska $09D0-$09FF: klucze pamieci podrecznych Z1 / Z2 (na komplet listy 0 / 1) i mapa priorytetu okna (Z4) ---
NT_RAM       = $09D0
PM_OK        = NT_RAM+$00  ; (2) Z1: 1 = lista tego kompletu wziela sciezke blokowa priorytetu i jej BCB sa w slotach (klucz ponizej)
PM_CXL       = NT_RAM+$02  ; (2) klucz: kamera listy (v_camx, v_camy - rowniez sciezki obwiedni: "kamera stoi" w regule wyboru)
PM_CXH       = NT_RAM+$04  ; (2)
PM_CYL       = NT_RAM+$06  ; (2)
PM_CYH       = NT_RAM+$08  ; (2)
PM_OS        = NT_RAM+$0A  ; (2) pierwszy slot priorytetu (v_oslot)
PM_FB        = NT_RAM+$0C  ; (2) bufor obrazu (v_fbm)
PM_LL        = NT_RAM+$0E  ; (2) wynik: ostatni BCB priorytetu (zp_last); PM_LH = 0 - zadnego BCB (adresy slotow >= $2000)
PM_LH        = NT_RAM+$10  ; (2)
PM_WAS       = NT_RAM+$12  ; robocze listy: PM_OK kompletu z poprzedniej listy (build_list kopiuje i zeruje PM_OK,x)
VM_OK        = NT_RAM+$13  ; (2) Z2: 1 = 4 BCB widoku w slotach SLOT_VIEW.. kompletu odpowiadaja kluczowi
VM_XL        = NT_RAM+$15  ; (2) klucz: v_camx (lo), v_camx+1 & 1, v_camy (lo) - pozycja w pierscieniu 512 x 256 - i v_fbm
VM_XH        = NT_RAM+$17  ; (2)
VM_Y         = NT_RAM+$19  ; (2)
VM_FB        = NT_RAM+$1B  ; (2)
SM_WAS       = NT_RAM+$1D  ; robocze listy: SM_OK kompletu z poprzedniej listy (Z6)
VM_DM        = NT_RAM+$1E  ; (2) Z8: bity 0-2 = sloty B / C / D widoku kompletu maja pusty BCB (put_dummy)
PRIOCOLM     = NT_RAM+$20  ; (16) Z4: bit (r & 7) bajtu (c & 15) = blok w slocie pierscienia (c & 15, r & 7) ma priorytet (PRIO_RAM; wiersz
                           ; >= v_lvh - 0); pisze emit_block (kazdy blok ladowany do pierscienia: kolumna, wiersz, pelne przeladowanie, lata)
NT_RAM_END   = NT_RAM+$30
	.if NT_RAM_END>$0A00 || PRIOCOLM+16>NT_RAM_END || VM_DM+2>PRIOCOLM   ; SKIND_RAM + 2 * N_SPR_SLOTS <= NT_RAM - render/prio.asm
	.error "M7.5: RAM $09D0-$09FF (za SKIND_RAM, przed SPRPAL_RAM $0A00)"
	.endif
; --- RAM niska $0AD0-$0AFF: Z6 pamiec BCB Sonica (na komplet) ---
NT2_RAM      = $0AD0
SM_OK        = NT2_RAM+$00 ; (2) Z6: 1 = slot SM_OS kompletu ma BCB Sonica dla klucza (poprzednia lista kompletu)
SM_FR        = NT2_RAM+$02 ; (2) klucz: v_sonic_fr
SM_BASE      = NT2_RAM+$04 ; (2) v_sonic_base
SM_XL        = NT2_RAM+$06 ; (2) sonic_x - v_camx (16 bit)
SM_XH        = NT2_RAM+$08 ; (2)
SM_YL        = NT2_RAM+$0A ; (2) sonic_y - v_camy (16 bit)
SM_YH        = NT2_RAM+$0C ; (2)
SM_OS        = NT2_RAM+$0E ; (2) slot (v_oslot)
SM_FB        = NT2_RAM+$10 ; (2) v_fbm
SM_RX        = NT2_RAM+$12 ; (2) wynik: prostokat priorytetu Sonica (or_*: x, y, w, h)
SM_RY        = NT2_RAM+$14 ; (2)
SM_RW        = NT2_RAM+$16 ; (2)
SM_RH        = NT2_RAM+$18 ; (2)
FM_OK        = NT2_RAM+$1A ; (2) Z5: 1 = lista kompletu zapisala w slotach FM_OS..FM_OS+FM_N-1 sprite'y przednie fo_fast (pola stale
                           ; 8x16 z atlasu juz w slotach - nastepna lista kompletu pisze tylko zrodlo i cel)
FM_OS        = NT2_RAM+$1C ; (2) pierwszy slot serii
FM_N         = NT2_RAM+$1E ; (2) dlugosc serii
FM_WAS       = NT2_RAM+$20 ; robocze listy: FM_OK kompletu z poprzedniej listy (build_list)
FM_ON        = NT2_RAM+$21 ; robocze front_objs_f: 1 = seria zbierana (fo_slow ja zamyka)
FM_CS        = NT2_RAM+$22 ; robocze: pierwszy slot serii tej listy ($FF - jeszcze brak)
FM_CE        = NT2_RAM+$23 ; robocze: koniec serii tej listy (v_oslot przy zamknieciu)
FM_LO        = NT2_RAM+$24 ; robocze: sloty FM_LO..FM_HI-1 maja pola stale (seria poprzedniej listy kompletu; puste - FM_LO = FM_HI)
FM_HI        = NT2_RAM+$25
PK_OK        = NT2_RAM+$26 ; (2) Z5 (sciezka blokowa): 1 = lista kompletu zostawila BCB blokow w slotach PK_OS..PK_OS+PK_N-1 (pola stale:
                           ; kroki zrodla 32 / 1, szerokosc hi 0 - nastepna lista ich nie pisze; niezalezne od ukladu, inaczej niz PM_OK)
PK_OS        = NT2_RAM+$28 ; (2)
PK_N         = NT2_RAM+$2A ; (2)
PK_WAS       = NT2_RAM+$2C ; robocze listy: PK_OK kompletu z poprzedniej listy (build_list)
PK_LIM       = NT2_RAM+$2D ; robocze prio_path: BCB o numerze < PK_LIM - pola stale juz sa
NT2_RAM_END  = NT2_RAM+$2E
	.if WATERPAL_RAM+96>NT2_RAM || NT2_RAM_END>SONICFR_RAM
	.error "M7.5: RAM $0AD0-$0AFF (za WATERPAL_RAM, przed SONICFR_RAM $0B00)"
	.endif
; --- RAM pod OS $DE00-$DEFF: dane robocze sciezki blokowej priorytetu (prio_path - odtwarzane w kazdej liscie) ---
NT3_RAM      = $DE00
PB_M         = NT3_RAM+$00 ; (9) maska wierszy pierscienia z priorytetem kolumny c okna (PRIOCOLM & wiersze okna)
PB_RY        = NT3_RAM+$10 ; (7) wiersz okna r: y ekranu (przyciete do 0..191)
PB_RH        = NT3_RAM+$18 ; (7) wysokosc czesci bloku na ekranie (0 - wiersz poza ekranem)
PB_RLY       = NT3_RAM+$20 ; (7) (pierwsza widoczna linia bloku & 7) << 5 (bajt mlodszy zrodla; gora przycieta)
PB_RB        = NT3_RAM+$28 ; (7) bit wiersza pierscienia (by + r) & 7
PB_RSM       = NT3_RAM+$30 ; (7) pierwsza widoczna linia bloku >> 3 (bajt srodkowy zrodla)
; Z8 (render/frame.asm emit_block): czesci BCB bloku pierscienia zalezne od wiersza (eb_rowp) i kolumny (eb_colp) - raz na wiersz /
; kolumne przy doladowaniu (zamiast na kazdy blok)
EB_RM        = NT3_RAM+$38 ; (r & 3) << 6 - bajt srodkowy celu (wiersz)
EB_RH        = NT3_RAM+$39 ; RING_VRAM >> 16 + ((r & 4) >> 2) - bajt starszy celu
EB_R16       = NT3_RAM+$3A ; (r & 7) << 4 - slot pierscienia (RCMASK_RAM)
EB_RB        = NT3_RAM+$3B ; bit (r & 7) mapy priorytetu; 0 - wiersz poza ukladem (>= v_lvh)
EB_CL        = NT3_RAM+$3C ; (c & 7) << 5 - bajt mlodszy celu (kolumna)
EB_CB        = NT3_RAM+$3D ; (c >> 3) & 1 - bit kolumny w bajcie srodkowym celu
EB_C15       = NT3_RAM+$3E ; c & 15 - kolumna pierscienia
PB_KBY       = NT3_RAM+$3F ; klucz tablic PB_R* (render/prio.asm pp_rows): by & 7
PB_KLY       = NT3_RAM+$40 ; camy & 31 ($FF - niewazny: nt_reset)
SK46_KYL     = NT3_RAM+$41 ; M7.5: zapper SKY3 (obj/objz3_sky_boss.asm sk46_xpre): tmp_06 - scroll_y (16 bit) - y par raz na tick
SK46_KYH     = NT3_RAM+$42
NT3_RAM_END  = NT3_RAM+$43
	.if BLKMAP_RAM+$100>NT3_RAM || NT3_RAM_END>$DF00 || SCR_RLE_M_RAM<>$DD00
	.error "M7.5: RAM pod OS $DE00-$DEFF (za BLKMAP_RAM; RLE mapy 1 ekranow tylko poza poziomem)"
	.endif
