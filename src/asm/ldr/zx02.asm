; =====================================================================
;  zx02.asm - M7.2: dekompresor zx02 (wariant 6502 "optim", zx02 v3) dla ldr (src/ldr/ldr.asm)
;
;  Zrodlo: zx02-optim.asm z pakietu zx02 v3 (https://github.com/dmsc/zx02, wydanie z 25.09.2026), licencja MIT -
;  pelny tekst: docs/licencje/zx02-LICENSE.txt. Oryginalny naglowek autora ponizej (bez zmian tresci).
;  Zmiany portu (semantyka bajt w bajt jak oryginal - emulacja rozkaz po rozkazie: tools/pack_test.py Zx02_6502):
;   - ZP = $82 (8 B: offset_hi $82, ZX0_src $83-$84, ZX0_dst $85-$86, bitr $87, pntr $88-$89) = zp_src..zp_cnt jadra
;     (src/kernel/mem.inc) - uzywane tylko w czerni, sekwencyjnie z kopia ldr; NMI ich nie dotyka (nmi.asm: zp_fx, music.asm: mz_*);
;   - etykiety z przedrostkiem zx_ (zamiast anonimowych @ i nazw ogolnych typu exit) - jeden zakres nazw z kodem gry;
;   - blok startowy zx0_ini_block w RAM rezydentnej: ldr_unpack wpisuje adres strumienia (+1/+2) przed kazdym wywolaniem,
;     wynik zawsze od BANK_WIN (okno banku slotu); offset poczatkowy 1 (zx02 bez opcji -o, jak tools/pack_zone.py).
;  Dekompresja w miejscu (M7.1): strumien lezy tak, ze konczy sie delta B ZA koncem wyniku (ldr_fetch_*: BANK_WIN + len_u + delta - len_c);
;  pelny bank wychodzi do 16 B w $8000+ (LDR_SPILL).
;  Czas (autor): 54,9 cykla na bajt wyniku w pliku testowym; pelny bank 16 KB ok. 0,9 M cykli (0,5 s PAL) - pomiar: tools/m7_ldr_unit.py.
; =====================================================================
; De-compressor for ZX02 files
; ----------------------------
;
; Decompress ZX02 data (6502 optimized format), optimized for speed and size
;  132 bytes code, 54.9 cycles/byte in test file.
;
; Compress with:
;    zx02 input.bin output.zx0
;
; (c) 2022 DMSC
; Code under MIT license, see LICENSE file.

ZX0_ZP          = $82
offset_hi       = ZX0_ZP+0
ZX0_src         = ZX0_ZP+1
ZX0_dst         = ZX0_ZP+3
bitr            = ZX0_ZP+5
pntr            = ZX0_ZP+6

            ; Initial values for the de-compressor, the values are copied to
            ; the ZP locations at the initialization:
zx0_ini_block
            dta b($00)                    ; Hi byte of the initial offset-1.
            dta b(0, 0)                   ; Address of data to decompress (ldr_unpack: ld_src).
            dta a(BANK_WIN)               ; Address to place decompressed data (okno banku slotu).
            dta b($80)                    ; Initial value for the bit reservoir. Don't ever change.
            dta b($ff)                    ; Low byte of the initial offset - 1 EOR 255.  The value
                                          ; $FF means an initial offset of 1 byte, this is the
                                          ; default value. See README for the explanation of the
                                          ; '-o' option.

;--------------------------------------------------
; Decompress ZX0 data (6502 optimized format)
;
; Reads data from 'comp_data' and writes the result to 'out_addr', until the
; compressed data ends.

zx02_decomp
              ; Get initialization block
              ldy #7

zx_copy_init  ldx zx0_ini_block-1,y
              stx offset_hi-1,y
              dey
              bne zx_copy_init

; Decode literal: Copy next N bytes from compressed file
;    Elias(length)  byte[1]  byte[2]  ...  byte[N]
zx_decode_literal
              inx
              jsr zx_get_elias

zx_cop0       lda (ZX0_src),y
              inc ZX0_src
              bne zx_c0a
              inc ZX0_src+1
zx_c0a        sta (ZX0_dst),y
              inc ZX0_dst
              bne zx_c0b
              inc ZX0_dst+1
zx_c0b        dex
              bne zx_cop0

              asl bitr
              bcs zx_new_offset

; Copy from last offset (repeat N bytes from last offset)
;    Elias(length)
              inx
              jsr zx_get_elias
zx_copy
              lda ZX0_dst+1
              sbc offset_hi              ; C=0 from get_elias
              sta pntr+1

zx_cop1
              ldy ZX0_dst
              lda (pntr),y
              ldy #0
              sta (ZX0_dst),y
              inc ZX0_dst
              bne zx_c1a
              inc ZX0_dst+1
              inc pntr+1
zx_c1a        dex
              bne zx_cop1

              asl bitr
              bcc zx_decode_literal

; Copy from new offset (repeat N bytes from new offset)
;    Elias(MSB(offset))  LSB(offset)  Elias(length-1)
zx_new_offset
              ; Read elias code for high part of offset
              inx
              jsr zx_get_elias
              beq zx_exit                ; Read a 0, signals the end
              ; Decrease and divide by 2
              dex
              txa
              lsr
              sta offset_hi

              ; Get low part of offset, a literal 7 bits
              lda (ZX0_src),y
              inc ZX0_src
              bne zx_no
              inc ZX0_src+1
zx_no
              ; Divide by 2
              ror
              eor #$ff
              sta pntr

              ; And get the copy length.
              ; Start elias reading with the bit already in carry:
              ldx #1
              jsr zx_elias_skip1

              inx
              bcc zx_copy

; Read an elias-gamma interlaced code.
; ------------------------------------
zx_elias_get  ; Read next data bit to result
              asl bitr
              rol
              tax

zx_get_elias
              ; Get one bit
              asl bitr
              bne zx_elias_skip1

              ; Read new bit from stream
              lda (ZX0_src),y
              inc ZX0_src
              bne zx_ge1
              inc ZX0_src+1
zx_ge1        ;sec   ; not needed, C=1 guaranteed from last bit
              rol
              sta bitr

zx_elias_skip1
              txa
              bcs zx_elias_get
              ; Got ending bit, stop reading
zx_exit
              rts
zx02_end
	.if [zx02_end-zx02_decomp]<>132-7
	.error "zx02: rozmiar kodu rozny od zx02-optim.asm (132 B z blokiem 7 B) - sprawdz przeniesienie"
	.endif
