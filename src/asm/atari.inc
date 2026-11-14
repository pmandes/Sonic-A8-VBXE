; =====================================================================
;  atari.inc  -  kanoniczne nazwy rejestrow i zmiennych OS Atari XL/XE
;  Nazwy zgodne z "Mapping the Atari" / OS Manual. Dolaczaj przez:
;      icl 'atari.inc'
;  Plik zawiera wylacznie stale (nie generuje kodu), wiec mozna go
;  dolaczyc w dowolnym miejscu zrodla. Dolaczaj tylko raz.
; =====================================================================

; ---------------------------------------------------------------------
;  STRONA ZEROWA - zmienne OS (tylko te, ktore sa przydatne w ASM)
; ---------------------------------------------------------------------
LNFLG    = $00      ; XL: flaga LNBUG (na 400/800: LINZBS)
CASINI   = $02      ; wektor init kasety (2 bajty)
RAMLO    = $04      ; wskaznik testu RAM (2 bajty)
TRAMSZ   = $06      ; flaga: obecny cartridge (na XL: "1" gdy cart)
WARMST   = $08      ; 0 = zimny start, $FF = cieply
BOOT     = $09      ; flaga udanego bootu
DOSVEC   = $0A      ; wektor "DUP" / procesora poleceniowego DOS
DOSINI   = $0C      ; wektor init DOS (wywolywany przy RESET)
APPMHI   = $0E      ; gorny adres uzyty przez aplikacje (chroni ekran OS)
POKMSK   = $10      ; cien IRQEN (maska przerwan IRQ)
BRKKEY   = $11      ; 0 = wcisnieto BREAK
RTCLOK   = $12      ; zegar ramek, 3 bajty, $14 = najmlodszy (rosnie co VBI)
BUFADR   = $15      ; adres bufora SIO (2 bajty)
CRITIC   = $42      ; <>0 = sekcja krytyczna (OS pomija VBI etap 2 i VVBLKD)
FMSZPG   = $43      ; 7 bajtow strony zerowej DOS ($43-$49)
ATRACT   = $4D      ; licznik trybu attract; zerowac w VBI aby kolory nie plywaly
DRKMSK   = $4E      ; maska ciemnosci attract
COLRSH   = $4F      ; przesuniecie kolorow attract
LMARGN   = $52      ; lewy margines edytora E:
RMARGN   = $53      ; prawy margines edytora E:
ROWCRS   = $54      ; wiersz kursora
COLCRS   = $55      ; kolumna kursora (2 bajty)
DINDEX   = $57      ; numer trybu graficznego OS
SAVMSC   = $58      ; adres pamieci ekranu OS (2 bajty)
OLDCHR   = $5D      ; znak pod kursorem
PALNTS   = $62      ; XL: 0 = NTSC, 1 = PAL (ustawiane przez OS)
RAMTOP   = $6A      ; gorna strona RAM widziana przez OS (np. $C0 = 48K)
FR0      = $D4      ; rejestr FP 0 (6 bajtow) - wolny, jesli nie uzywasz FP
FR1      = $E0      ; rejestr FP 1 (6 bajtow)
FR2      = $E6      ; rejestr FP 2
CIX      = $F2      ; indeks bufora FP
INBUFF   = $F3      ; wskaznik bufora ASCII FP
FLPTR    = $FC      ; wskaznik FP
; Obszar $80-$D3 jest wolny dla programu w ASM (BASIC wylaczony).
; Obszar $D4-$FF jest wolny, jesli nie wolasz procedur FP OS.
; RMT player domyslnie zajmuje $CB-$DD (19 bajtow) - patrz rmtplayr.a65.

; ---------------------------------------------------------------------
;  STRONA 2 - wektory przerwan, cienie rejestrow (shadow registers)
; ---------------------------------------------------------------------
VDSLST   = $0200    ; wektor DLI (NMI z ANTIC-a)
VPRCED   = $0202    ; wektor IRQ: PIA proceed
VINTER   = $0204    ; wektor IRQ: PIA interrupt
VBREAK   = $0206    ; wektor IRQ: rozkaz BRK
VKEYBD   = $0208    ; wektor IRQ: klawiatura
VSERIN   = $020A    ; wektor IRQ: serial input ready
VSEROR   = $020C    ; wektor IRQ: serial output needed
VSEROC   = $020E    ; wektor IRQ: serial output complete
VTIMR1   = $0210    ; wektor IRQ: POKEY timer 1
VTIMR2   = $0212    ; wektor IRQ: POKEY timer 2
VTIMR4   = $0214    ; wektor IRQ: POKEY timer 4
VIMIRQ   = $0216    ; glowny wektor IRQ (OS przekazuje tu wszystkie IRQ)
CDTMV1   = $0218    ; timer programowy 1 (2 bajty, dekrementowany w VBI etap 1)
CDTMV2   = $021A    ; timer programowy 2
CDTMV3   = $021C    ; timer programowy 3 (etap 2)
CDTMV4   = $021E    ; timer programowy 4
CDTMV5   = $0220    ; timer programowy 5
VVBLKI   = $0222    ; wektor VBI natychmiastowy (immediate, przed etapem 1)
VVBLKD   = $0224    ; wektor VBI odroczony (deferred, po etapie 2)
CDTMA1   = $0226    ; adres procedury timera 1
CDTMA2   = $0228    ; adres procedury timera 2
CDTMF3   = $022A    ; flaga timera 3
SRTIMR   = $022B    ; timer autorepeat klawiatury
CDTMF4   = $022C    ; flaga timera 4
CDTMF5   = $022E    ; flaga timera 5
SDMCTL   = $022F    ; cien DMACTL
SDLSTL   = $0230    ; cien DLISTL (adres display listy, mlodszy bajt)
SDLSTH   = $0231    ; cien DLISTH
SSKCTL   = $0232    ; cien SKCTL
LPENH    = $0234    ; pioro swietlne: pozycja pozioma
LPENV    = $0235    ; pioro swietlne: pozycja pionowa
BRKKY    = $0236    ; wektor BREAK (XL)
VPIRQ    = $0238    ; wektor IRQ PBI (XL)
CDEVIC   = $023A    ; SIO: urzadzenie
CCOMND   = $023B    ; SIO: komenda
COLDST   = $0244    ; <>0 = RESET spowoduje zimny start
DSKTIM   = $0246    ; timeout formatowania dysku
PDVMSK   = $0247    ; maska urzadzen PBI (XL)
SHPDVS   = $0248    ; wybor PBI (cien $D1FF)
PDIMSK   = $0249    ; maska IRQ PBI
GPRIOR   = $026F    ; cien PRIOR
PADDL0   = $0270    ; cienie paddle 0-7 ($0270-$0277)
PADDL1   = $0271
STICK0   = $0278    ; cien joysticka 0 (bity: 0 gora,1 dol,2 lewo,3 prawo; 0 = wcisniety)
STICK1   = $0279
STICK2   = $027A
STICK3   = $027B
PTRIG0   = $027C    ; cienie przyciskow paddle 0-7 ($027C-$0283)
STRIG0   = $0284    ; cien przycisku joysticka 0 (0 = wcisniety)
STRIG1   = $0285
STRIG2   = $0286
STRIG3   = $0287
TXTROW   = $0290    ; wiersz kursora okna tekstowego
TXTCOL   = $0291    ; kolumna kursora okna tekstowego
TXTMSC   = $0294    ; adres pamieci okna tekstowego
SHFLOK   = $02BE    ; stan Shift/Caps ($00 mala, $40 duze, $80 CTRL)
BOTSCR   = $02BF    ; liczba wierszy okna tekstowego (24 lub 4)
PCOLR0   = $02C0    ; cien COLPM0 (kolor gracza 0)
PCOLR1   = $02C1
PCOLR2   = $02C2
PCOLR3   = $02C3
COLOR0   = $02C4    ; cien COLPF0
COLOR1   = $02C5    ; cien COLPF1
COLOR2   = $02C6    ; cien COLPF2
COLOR3   = $02C7    ; cien COLPF3
COLOR4   = $02C8    ; cien COLBK (tlo / ramka)
RUNADR   = $02C9    ; XL: adres startu z bootu
KRPDEL   = $02D9    ; opoznienie autorepeat klawiatury (XL)
KEYREP   = $02DA    ; szybkosc autorepeat (XL)
NOCLIK   = $02DB    ; <>0 = brak klikniecia klawiszy (XL)
HELPFG   = $02DC    ; flaga klawisza HELP (XL)
DMASAV   = $02DD    ; zapamietany DMACTL (XL)
RUNAD    = $02E0    ; wektor RUN loadera binarnego (segment $2E0/$2E1)
INITAD   = $02E2    ; wektor INIT loadera binarnego (segment $2E2/$2E3)
RAMSIZ   = $02E4    ; rozmiar RAM w stronach (np. $C0)
MEMTOP   = $02E5    ; gorna granica wolnej pamieci (2 bajty)
MEMLO    = $02E7    ; dolna granica wolnej pamieci (2 bajty, ustawia DOS)
DVSTAT   = $02EA    ; status urzadzenia (4 bajty)
CRSINH   = $02F0    ; <>0 = kursor niewidoczny
KEYDEL   = $02F1    ; licznik debounce klawiatury
CH1      = $02F2    ; poprzedni kod klawisza
CHACT    = $02F3    ; cien CHACTL
CHBAS    = $02F4    ; cien CHBASE (starszy bajt adresu fontu, $E0 = font OS)
ATACHR   = $02FB    ; ostatni znak ATASCII / kolor rysowania
CH       = $02FC    ; ostatni klawisz (kod klawiatury); $FF = brak; wpisz $FF aby skasowac
FILDAT   = $02FD    ; kolor wypelnienia
DSPFLG   = $02FE    ; <>0 = wyswietlaj znaki sterujace
SSFLAG   = $02FF    ; <>0 = ekran zatrzymany (Ctrl+1)

; ---------------------------------------------------------------------
;  STRONA 3 - SIO/DCB, HATABS, IOCB
; ---------------------------------------------------------------------
DDEVIC   = $0300    ; DCB: urzadzenie SIO (np. $31 = dysk)
DUNIT    = $0301    ; DCB: numer jednostki
DCOMND   = $0302    ; DCB: komenda ($52 read, $57 write, $50 put, $53 status)
DSTATS   = $0303    ; DCB: kierunek/status ($40 = odczyt, $80 = zapis)
DBUFLO   = $0304    ; DCB: adres bufora
DBUFHI   = $0305
DTIMLO   = $0306    ; DCB: timeout w sekundach
DBYTLO   = $0308    ; DCB: liczba bajtow
DBYTHI   = $0309
DAUX1    = $030A    ; DCB: aux1 (np. numer sektora, mlodszy)
DAUX2    = $030B    ; DCB: aux2
HATABS   = $031A    ; tablica handlerow (3 bajty/wpis: nazwa, adres)
IOCB0    = $0340    ; IOCB 0..7 co 16 bajtow ($0340-$03BF)
ICHID    = $0340    ; +0  indeks handlera ($FF = wolny)
ICDNO    = $0341    ; +1  numer urzadzenia
ICCOM    = $0342    ; +2  komenda ($03 open, $05 getrec, $07 getchr, $09 putrec, $0B putchr, $0C close)
ICSTA    = $0343    ; +3  status
ICBAL    = $0344    ; +4  adres bufora
ICBAH    = $0345    ; +5
ICPTL    = $0346    ; +6  adres put-byte (uzywany przez BASIC)
ICPTH    = $0347    ; +7
ICBLL    = $0348    ; +8  dlugosc bufora
ICBLH    = $0349    ; +9
ICAX1    = $034A    ; +10 aux1 (open: $04 read, $08 write, $0C update, $10 tekst w gr.)
ICAX2    = $034B    ; +11 aux2 (open S:: numer trybu graficznego)
ICAX3    = $034C
ICAX4    = $034D
ICAX5    = $034E
ICAX6    = $034F
PRNBUF   = $03C0    ; bufor drukarki (40 bajtow)
BASICF   = $03F8    ; XL: 0 = BASIC wlaczony, 1 = wylaczony (zgodnie z PORTB bit 1)
GINTLV   = $03FA    ; (stara nazwa w tym pliku; w OS XL: GINTLK)
GINTLK   = $03FA    ; XL: blokada cartu - kopia TRIG3 z zimnego startu; VBI OS-u porownuje ja z TRIG3 i przy roznicy zawiesza
                    ; system (wyjecie / wylaczenie cartu przy pracujacym VBI). M7.3: po wylaczeniu cartu GINTLK = TRIG3
CASBUF   = $03FD    ; bufor kasety ($03FD-$047F)
; $0480-$057D  wolne, gdy BASIC nie dziala (BASIC/FP: LBUFF $0580-$05FF)
; $0600-$06FF  "strona szosta" - klasyczny wolny obszar
; $0700-       DOS (DOS 2.5 do ok. $1CFC); bez DOS wolne od $0700

; ---------------------------------------------------------------------
;  TABLICA SKOKOW OS (jedyne bezpieczne punkty wejscia do ROM-u)
; ---------------------------------------------------------------------
DISKIV   = $E450    ; init interfejsu dysku
DSKINV   = $E453    ; interfejs dysku (uzywa DCB)
CIOV     = $E456    ; CIO (X = numer IOCB * 16)
SIOV     = $E459    ; SIO (uzywa DCB)
SETVBV   = $E45C    ; ustaw wektor VBI/timer: A = 6 immediate / 7 deferred, X = hi, Y = lo
SYSVBV   = $E45F    ; wejscie systemowego VBI etap 1 (skocz tu z VVBLKI)
XITVBV   = $E462    ; wyjscie z VBI (skocz tu z VVBLKD; przywraca rejestry, RTI)
SIOINV   = $E465    ; init SIO
SENDEV   = $E468    ; send enable
INTINV   = $E46B    ; init handlera przerwan
CIOINV   = $E46E    ; init CIO
BLKBDV   = $E471    ; "blackboard" (self test / memo pad)
WARMSV   = $E474    ; cieply start
COLDSV   = $E477    ; zimny start
RBLOKV   = $E47A    ; odczyt bloku kasety
CSOPIV   = $E47D    ; open kasety do odczytu
PUPDIV   = $E480    ; XL: power-up display
SLFTSV   = $E483    ; XL: self test
PHENTV   = $E486    ; XL: PBI handler entry
PHUNLV   = $E489    ; XL: PBI handler unlink
PHINIV   = $E48C    ; XL: PBI handler init
GPDVV    = $E48F    ; XL: generic parallel device vector
OSFONT   = $E000    ; font OS (1K, 128 znakow x 8 bajtow), CHBAS = $E0
OSFONT2  = $CC00    ; XL: font miedzynarodowy

; ---------------------------------------------------------------------
;  GTIA  $D000-$D01F   (zapis / odczyt maja rozne znaczenie!)
; ---------------------------------------------------------------------
; zapis
HPOSP0   = $D000    ; pozycja pozioma gracza 0 (color clock; $30 = lewa krawedz normal PF)
HPOSP1   = $D001
HPOSP2   = $D002
HPOSP3   = $D003
HPOSM0   = $D004    ; pozycje pociskow 0-3
HPOSM1   = $D005
HPOSM2   = $D006
HPOSM3   = $D007
SIZEP0   = $D008    ; szerokosc gracza: 0 = 1x, 1 = 2x, 3 = 4x
SIZEP1   = $D009
SIZEP2   = $D00A
SIZEP3   = $D00B
SIZEM    = $D00C    ; szerokosci pociskow (2 bity na pocisk)
GRAFP0   = $D00D    ; dane graficzne gracza 0 (gdy PM DMA wylaczone)
GRAFP1   = $D00E
GRAFP2   = $D00F
GRAFP3   = $D010
GRAFM    = $D011    ; dane graficzne pociskow
COLPM0   = $D012    ; kolor gracza/pocisku 0
COLPM1   = $D013
COLPM2   = $D014
COLPM3   = $D015
COLPF0   = $D016    ; kolor playfield 0
COLPF1   = $D017    ; kolor playfield 1 (w trybie tekstowym: jasnosc liter)
COLPF2   = $D018    ; kolor playfield 2 (w trybie tekstowym: tlo liter)
COLPF3   = $D019    ; kolor playfield 3
COLBK    = $D01A    ; kolor tla / ramki
PRIOR    = $D01B    ; priorytety, 5. gracz, multicolor, tryby GTIA
VDELAY   = $D01C    ; opoznienie pionowe PMG (double-line)
GRACTL   = $D01D    ; bit0 pociski, bit1 gracze, bit2 latch triggerow
HITCLR   = $D01E    ; zapis kasuje rejestry kolizji
CONSOL   = $D01F    ; zapis: glosnik/bity; odczyt: START(bit0) SELECT(bit1) OPTION(bit2), 0 = wcisniety
; odczyt
M0PF     = $D000    ; kolizje pocisk 0 - playfield
M1PF     = $D001
M2PF     = $D002
M3PF     = $D003
P0PF     = $D004    ; kolizje gracz 0 - playfield
P1PF     = $D005
P2PF     = $D006
P3PF     = $D007
M0PL     = $D008    ; kolizje pocisk 0 - gracze
M1PL     = $D009
M2PL     = $D00A
M3PL     = $D00B
P0PL     = $D00C    ; kolizje gracz 0 - gracze
P1PL     = $D00D
P2PL     = $D00E
P3PL     = $D00F
TRIG0    = $D010    ; przycisk joysticka 0 (0 = wcisniety)
TRIG1    = $D011
TRIG2    = $D012    ; XL/XE: 0 gdy cart w slocie? (na 800: joystick 2)
TRIG3    = $D013    ; XL/XE: 1 = cartridge obecny
PAL      = $D014    ; bity 1-3 = 0 -> PAL, = 1 -> NTSC  (lda PAL / and #$0E / beq jest_pal)

; ---------------------------------------------------------------------
;  POKEY  $D200-$D20F  (stereo: drugi POKEY pod $D210-$D21F)
; ---------------------------------------------------------------------
; zapis
AUDF1    = $D200    ; dzielnik czestotliwosci kanalu 1
AUDC1    = $D201    ; sterowanie kanalu 1: bity 7-5 znieksztalcenie, bit4 volume-only, bity 3-0 glosnosc
AUDF2    = $D202
AUDC2    = $D203
AUDF3    = $D204
AUDC3    = $D205
AUDF4    = $D206
AUDC4    = $D207
AUDCTL   = $D208    ; zegary, laczenie kanalow 16-bit, filtry, poly 9/17
STIMER   = $D209    ; zapis: restart timerow
SKREST   = $D20A    ; zapis: reset bitow statusu SKSTAT
POTGO    = $D20B    ; zapis: start odczytu paddle
SEROUT   = $D20D    ; zapis: bajt do wyslania (SIO)
IRQEN    = $D20E    ; zapis: maska IRQ (cien: POKMSK)
SKCTL    = $D20F    ; zapis: $03 = normalna praca klawiatury
; odczyt
POT0     = $D200    ; paddle 0-7
POT1     = $D201
ALLPOT   = $D208    ; ktore paddle skonczyly odczyt
KBCODE   = $D209    ; kod ostatniego klawisza
RANDOM   = $D20A    ; generator losowy (8 bitow z poly 17)
SERIN    = $D20D    ; odebrany bajt (SIO)
IRQST    = $D20E    ; status IRQ (0 = zgloszone)
SKSTAT   = $D20F    ; status: bit2 klawisz wcisniety (0), bit3 shift, bit7 serial

; ---------------------------------------------------------------------
;  PIA  $D300-$D303
; ---------------------------------------------------------------------
PORTA    = $D300    ; joysticki 0/1 (dolny/gorny nibble), 0 = wcisniety
PORTB    = $D301    ; XL/XE: bankowanie pamieci i ROM (patrz PB_* ponizej)
PACTL    = $D302    ; sterowanie portu A (bit2 = 1: dostep do danych; silnik magnetofonu bit3)
PBCTL    = $D303    ; sterowanie portu B (bit2 = 1: dostep do danych)

; ---------------------------------------------------------------------
;  ANTIC  $D400-$D40F
; ---------------------------------------------------------------------
DMACTL   = $D400    ; DMA: szerokosc PF, PM DMA, rozdz. PM, DL DMA (cien SDMCTL)
CHACTL   = $D401    ; bit0 blank inverse, bit1 inverse video, bit2 odbicie pionowe znakow
DLISTL   = $D402    ; adres display listy (cien SDLSTL/SDLSTH)
DLISTH   = $D403
HSCROL   = $D404    ; przesuniecie poziome 0-15 color clockow (uzywa 4 bity)
VSCROL   = $D405    ; przesuniecie pionowe 0-15 linii
PMBASE   = $D407    ; starszy bajt adresu pamieci PMG (wyrownanie 2K single / 1K double)
CHBASE   = $D409    ; starszy bajt adresu fontu (wyrownanie 1K; tryby 6/7: 512 B)
WSYNC    = $D40A    ; zapis: zatrzymaj CPU do konca biezacej linii (horizontal blank)
VCOUNT   = $D40B    ; odczyt: numer linii / 2 (PAL 0-155, NTSC 0-130)
PENH     = $D40C    ; pioro swietlne poziomo
PENV     = $D40D    ; pioro swietlne pionowo
NMIEN    = $D40E    ; bit7 DLI, bit6 VBI, bit5 RESET
NMIRES   = $D40F    ; zapis: kasuj status NMI
NMIST    = $D40F    ; odczyt: bit7 DLI, bit6 VBI, bit5 RESET

; ---------------------------------------------------------------------
;  Inne
; ---------------------------------------------------------------------
CARTCTL  = $D500    ; obszar sterowania cartridge ($D500-$D5FF, zalezny od typu)
PDVS     = $D1FF    ; PBI: wybor urzadzenia (XL)
SELFTEST = $5000    ; self-test ROM ($5000-$57FF) gdy PORTB bit7 = 0
BASICROM = $A000    ; BASIC / cart 8K ($A000-$BFFF)
CARTROM  = $8000    ; cart 16K ($8000-$BFFF)
BANKWIN  = $4000    ; okno bankow rozszerzonej pamieci ($4000-$7FFF)

; ---------------------------------------------------------------------
;  BITY I STALE
; ---------------------------------------------------------------------
; DMACTL / SDMCTL
DMA_PF_OFF     = $00
DMA_PF_NARROW  = $01    ; 32 bajty (256 px w hi-res)
DMA_PF_NORMAL  = $02    ; 40 bajtow (320 px)
DMA_PF_WIDE    = $03    ; 48 bajtow (384 px, czesc poza widocznym ekranem)
DMA_MISSILES   = $04    ; DMA pociskow
DMA_PLAYERS    = $08    ; DMA graczy
DMA_PM_SINGLE  = $10    ; PMG w rozdzielczosci pojedynczej linii (0 = double-line)
DMA_DLIST      = $20    ; DMA display listy (bez tego ekran jest czarny)
DMA_STD        = DMA_PF_NORMAL|DMA_DLIST                       ; $22
DMA_STD_PMG    = DMA_STD|DMA_PLAYERS|DMA_MISSILES|DMA_PM_SINGLE ; $3E

; GRACTL
GR_MISSILES    = $01
GR_PLAYERS     = $02
GR_TRIGLATCH   = $04

; NMIEN
NMI_DLI        = $80
NMI_VBI        = $40
NMI_RESET      = $20

; PRIOR / GPRIOR
PRI_PM_PF      = $01    ; gracze przed calym playfieldem
PRI_PM01_PF_PM23 = $02  ; P0,P1 > PF > P2,P3
PRI_PF_PM      = $04    ; playfield przed graczami
PRI_PF01_PM_PF23 = $08  ; PF0,PF1 > PM > PF2,PF3
PRI_FIFTH      = $10    ; pociski jako 5. gracz (kolor COLPF3)
PRI_MULTICOLOR = $20    ; nakladanie P0|P1 i P2|P3 daje OR kolorow
GTIA_MODE9     = $40    ; 16 jasnosci jednego koloru (na trybie F)
GTIA_MODE10    = $80    ; 9 kolorow z rejestrow
GTIA_MODE11    = $C0    ; 16 odcieni jednej jasnosci

; PORTB (XL/XE): 1 = wlaczone dla bitow ROM, 0 = wlaczone dla self-test
PB_OSROM       = $01    ; 1 = OS ROM widoczny, 0 = RAM pod $C000-$FFFF (bez $D000-$D7FF)
PB_BASIC_OFF   = $02    ; 1 = BASIC wylaczony ($A000-$BFFF to RAM)
PB_BANK_MASK   = $0C    ; 130XE: bity 2-3 = numer banku (0-3)
PB_CPU_MAIN    = $10    ; 130XE: 1 = CPU widzi glowna RAM w $4000-$7FFF, 0 = bank
PB_ANTIC_MAIN  = $20    ; 130XE: 1 = ANTIC widzi glowna RAM, 0 = bank
PB_SELFTEST_OFF = $80   ; 1 = self-test wylaczony (normalnie zawsze 1)
PB_DEFAULT     = $FF    ; stan po starcie: OS on, BASIC off, banki off, self-test off
PB_BASIC_ON    = $FD

; AUDCTL
AUD_15KHZ      = $01    ; zegar 15.7 kHz zamiast 64 kHz
AUD_HPF2       = $02    ; filtr gornoprzepustowy kanal 2 taktowany 4
AUD_HPF1       = $04    ; filtr gornoprzepustowy kanal 1 taktowany 3
AUD_JOIN34     = $08    ; kanaly 3+4 jako 16-bit
AUD_JOIN12     = $10    ; kanaly 1+2 jako 16-bit
AUD_CH3_179    = $20    ; kanal 3 taktowany 1.79 MHz
AUD_CH1_179    = $40    ; kanal 1 taktowany 1.79 MHz
AUD_POLY9      = $80    ; poly 9 zamiast poly 17

; AUDCx znieksztalcenia (bity 7-5)
AUDC_PURE      = $A0    ; czysty ton
AUDC_NOISE     = $80    ; szum poly 17/9
AUDC_VOLONLY   = $10    ; volume-only (sample'e)

; IRQEN / IRQST
IRQ_TIMER1     = $01
IRQ_TIMER2     = $02
IRQ_TIMER4     = $04
IRQ_SEROUT_DONE = $08
IRQ_SEROUT_NEED = $10
IRQ_SERIN_READY = $20
IRQ_KEY        = $40
IRQ_BREAK      = $80

; Display list
DL_BLANK1      = $00    ; 1 pusta linia; $10 = 2, $20 = 3 ... $70 = 8
DL_BLANK2      = $10
DL_BLANK3      = $20
DL_BLANK4      = $30
DL_BLANK5      = $40
DL_BLANK6      = $50
DL_BLANK7      = $60
DL_BLANK8      = $70
DL_JMP         = $01    ; skok (3 bajty) - uzyj, gdy DL przekracza granice 1K
DL_JVB         = $41    ; skok + czekaj na VBLANK (koniec DL)
DL_HSCROL      = $10    ; linia z przewijaniem poziomym
DL_VSCROL      = $20    ; linia z przewijaniem pionowym
DL_LMS         = $40    ; Load Memory Scan: po bajcie trybu 2 bajty adresu
DL_DLI         = $80    ; DLI na ostatniej linii skanowania tego wiersza
; tryby ANTIC (dolne 4 bity)
DL_MODE2       = $02    ; tekst 40x8, 2 kolory (OS gr.0)
DL_MODE3       = $03    ; tekst 40x10 (descendery)
DL_MODE4       = $04    ; tekst 40x8, 4-5 kolorow (2 bity/piksel)
DL_MODE5       = $05    ; jak 4, podwojna wysokosc
DL_MODE6       = $06    ; tekst 20x8, 5 kolorow (OS gr.1)
DL_MODE7       = $07    ; tekst 20x16 (OS gr.2)
DL_MODE8       = $08    ; bitmapa 40x8 px, 4 kolory (OS gr.3)
DL_MODE9       = $09    ; bitmapa 80x4, 2 kolory (OS gr.4)
DL_MODEA       = $0A    ; bitmapa 80x4, 4 kolory (OS gr.5)
DL_MODEB       = $0B    ; bitmapa 160x2, 2 kolory (OS gr.6)
DL_MODEC       = $0C    ; bitmapa 160x1, 2 kolory
DL_MODED       = $0D    ; bitmapa 160x2, 4 kolory (OS gr.7)
DL_MODEE       = $0E    ; bitmapa 160x1, 4 kolory (OS gr.15 / 7+)
DL_MODEF       = $0F    ; bitmapa 320x1, 2 kolory (OS gr.8) / baza trybow GTIA

; SETVBV
VBI_IMMEDIATE  = 6
VBI_DEFERRED   = 7

; CIO komendy
CIO_OPEN       = $03
CIO_GETREC     = $05
CIO_GETCHR     = $07
CIO_PUTREC     = $09
CIO_PUTCHR     = $0B
CIO_CLOSE      = $0C
CIO_STATUS     = $0D
CIO_SPECIAL    = $0E
CIO_READ       = $04    ; ICAX1
CIO_WRITE      = $08    ; ICAX1
CIO_EOF        = $88    ; kod bledu: koniec pliku

; SIO / DCB
SIO_READ       = $52    ; 'R'
SIO_WRITE      = $57    ; 'W'
SIO_PUT        = $50    ; 'P'
SIO_STATUS     = $53    ; 'S'
SIO_DIR_READ   = $40
SIO_DIR_WRITE  = $80
SIO_DISK       = $31

; Kody klawiszy (KBCODE / CH), wybrane
KEY_SPACE      = $21
KEY_RETURN     = $0C
KEY_ESC        = $1C
KEY_NONE       = $FF
