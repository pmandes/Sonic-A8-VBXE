; =====================================================================
;  obj/objz_lab_jaws.asm - M6.8 Labyrinth: $3C Jaws (ryba) (bank obiektow strefy PB_OBJZ, dolaczany z objz.asm).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_3C_badnik_jaws 02:8837 (kod 02:8837-02:88B3),
;  dane 02:88B4-02:88FA (LUT_jaws_anim_sequence_right / _left, SPRTAB_jaws) - zakres OBJZ_SPANS w tym banku (SMS - OZ_OFF).
;  Procedury:
;   objfunc_3C_jaws   (02:8837) - funkcja obiektu
;  Wolane: zc_collide (check_collision_with_sonic 00:3956), zc_enemy (enemy_touched_sonic 00:35E5), oz_dfa (kopia do_framed_animation
;  01:7C41, objz.asm), random_A (00:0625, rezydentne), spawn_bubble (02:91EB - ten sam bank, plik objz_lab_woda.asm).
;  Rejestry Z80: IX = zg_obj, BC = zg_bc, DE = zg_de, HL = zg_hl.
; ---------------------------------------------------------------------
; Bez kolizji z mapa (set 5). Kierunek wg licznika (ix+17): < $80 - w prawo (Vx = +$20 subpikseli, 20 x 12, strefa trafienia
; przesunieta o (2, 10), przy wybuchu przesuniecie wybuchu tmp_00 = $0008), >= $80 - w lewo (Vx = -$20, 12 x 12, przesuniecie (2, 2),
; tmp_00 = $0000). Dotkniecie Sonica - enemy_touched_sonic (wybuch albo trafienie Sonica). Animacja 2 klatki po 5 tickow.
; Co 8 tickow (ix+17) + 1 (pelny cykl tam i z powrotem = 256 * 8 tickow) i losowanie: random_A & $1E = 0 -> spawn_bubble (babel $42).
; =====================================================================
; adresy SMS danych (zakres OBJZ_SPANS $88B4-$88FA; czytane w tym banku pod adresem SMS - OZ_OFF)
LUT_JW_RIGHT    = $88B4   ; LUT_jaws_anim_sequence_right: (klatka, czas) = (0, 4), (1, 4), $FF
LUT_JW_LEFT     = $88B9   ; LUT_jaws_anim_sequence_left:  (2, 4), (3, 4), $FF
SPR_JW          = $88BE   ; SPRTAB_jaws (klatka = 18 B; 4 klatki: prawo 0-1, lewo 2-3)

; ---------------------------------------------------------------------
; objfunc_3C_jaws (02:8837): Jaws - patrz opis pliku.
; ---------------------------------------------------------------------
objfunc_3C_jaws
	ldy #OB_FLAGS             ; set 5,(ix+24): bez kolizji z mapa
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #17                   ; ld a,(ix+17) / cp $80 / jr nc,@go_left (Z80 nc = 6502 C = 1 po cmp)
	lda (zg_obj),y
	cmp #$80
	bcs jw_left
	ldy #OB_VX                ; w prawo: Vx = $000020 ((ix+7) = $20, (ix+8) = 0, (ix+9) = 0)
	lda #$20
	sta (zg_obj),y
	lda #$00
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_W                 ; (ix+13) = $14, (ix+14) = $0C: 20 x 12
	lda #$14
	sta (zg_obj),y
	iny
	lda #$0C
	sta (zg_obj),y
	lda #$02                  ; ld hl,$0A02 / ld (tmp_06),hl: tmp_06 = $02 (dx), tmp_07 = $0A (dy)
	sta tmp_06
	lda #$0A
	sta tmp_07
	jsr zc_collide            ; check_collision_with_sonic: C = 1 brak trafienia
	lda #$08                  ; ld hl,$0008 / ld (tmp_00),hl - przed call nc (lda/sta nie zmieniaja C)
	sta tmp_00
	lda #$00
	sta tmp_00+1
	bcs jw_r_nohit            ; call nc,enemy_touched_sonic
	jsr zc_enemy
jw_r_nohit
	lda #<SPR_JW              ; ld de,SPRTAB_jaws (baza map - adres SMS)
	sta zg_de
	lda #>SPR_JW
	sta zg_de+1
	lda #<[LUT_JW_RIGHT-OZ_OFF] ; ld bc,LUT_jaws_anim_sequence_right (sekwencja - adres okna)
	sta zg_bc
	lda #>[LUT_JW_RIGHT-OZ_OFF]
	sta zg_bc+1
	jsr oz_dfa                ; call do_framed_animation
	jmp jw_bubbles            ; jr @handle_random_bubbles

jw_left                         ; @go_left: Vx = $FFFFE0 ((ix+7) = $E0, (ix+8) = $FF, (ix+9) = $FF)
	ldy #OB_VX
	lda #$E0
	sta (zg_obj),y
	lda #$FF
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #OB_W                 ; (ix+13) = $0C, (ix+14) = $0C: 12 x 12
	lda #$0C
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #$02                  ; ld hl,$0202 / ld (tmp_06),hl: tmp_06 = $02, tmp_07 = $02
	sta tmp_06
	sta tmp_07
	jsr zc_collide
	lda #$00                  ; ld hl,$0000 / ld (tmp_00),hl (przed call nc - C bez zmian)
	sta tmp_00
	sta tmp_00+1
	bcs jw_l_nohit            ; call nc,enemy_touched_sonic
	jsr zc_enemy
jw_l_nohit
	lda #<SPR_JW              ; ld de,SPRTAB_jaws
	sta zg_de
	lda #>SPR_JW
	sta zg_de+1
	lda #<[LUT_JW_LEFT-OZ_OFF] ; ld bc,LUT_jaws_anim_sequence_left
	sta zg_bc
	lda #>[LUT_JW_LEFT-OZ_OFF]
	sta zg_bc+1
	jsr oz_dfa                ; call do_framed_animation

jw_bubbles                      ; @handle_random_bubbles
	lda g_global_tick_counter ; ld a,(g_global_tick_counter) / and $07 / ret nz
	and #$07
	bne jw_ret
	ldy #17                   ; inc (ix+17)
	lda (zg_obj),y
	clc
	adc #1
	sta (zg_obj),y
	jsr random_A              ; call random_A (zachowuje X, Y)
	and #$1E                  ; and $1E / call z,spawn_bubble / ret
	bne jw_ret
	; spawn_bubble (02:91EB, objz_lab_woda.asm): wejscie jak w Z80 - IX = zg_obj = rekord Jawsa (spawn_bubble czyta z niego typ
	; (ix+0) = $3C -> babel $42 bez losowania typu, x (ix+2,3) i y (ix+5,6)); A = 0 (wynik and $1E), innych rejestrow nie uzywa.
	; call z + ret -> skok (powrot z spawn_bubble wraca do petli obiektow).
	jmp spawn_bubble
jw_ret
	rts
