; =====================================================================
;  obj/objs_c.asm - M4.6a: $08 Crabmeat i $0D kula ognia (bank 45).
;  Oryginal (s1smsdisasm-gm, tylko material referencyjny): objfunc_08_badnik_crabmeat 01:65EE,
;  objfunc_0D_fireball_pallet 01:6AC1, init_fireball_object 02:AC96. Dane (sekwencje, mapy, kafle kuli)
;  leza w banku 45 pod adresami SMS (objdata.inc). IX = zg_obj; tmp_* w lustrze RAM SMS jak oryginal.
; =====================================================================
LUT_CRAB_SEQ     = $66C5   ; LUT_crabmeat_state_sequence (stan na kazde 32 ticki, 0 = od poczatku)
LUT_CRAB_ANIM    = $66E0   ; LUT_crabmeat_state_anim_ptrs (slowa: sekwencje animacji dla stanow 0..4)
SPR_CRAB         = $66F9   ; SPRITEMAP_crabmeat_frames (klatka = 18 B)
LUT_FIREBALL     = $6B70   ; LUT_fireball_main: kafle $06 / $08 (co drugi tick)
LUT_FIREBALL_BL  = $6B72   ; LUT_fireball_BRI3_LAB3: kafle $34 / $36 (g_level 5 i $0B)

; ---------------------------------------------------------------------
; objfunc_08_badnik_crabmeat (01:65EE): kolizje z mapa wlaczone (b5 nie ustawiany), rozmiar 16 x 31. Stan
; z sekwencji (ix+18) - 0 = od poczatku: 1 Vx = +$28 (subpiksele), 2 Vx = -$28, 3 Vx = 0, 4 strzal, gdy
; (ix+17) = $20 (raz na 32 ticki stanu; Vx bez zmian): dwie kule ognia (spawn_object + init_fireball_object:
; (x, y) z Vx -1 i (x + 14, y) z Vx +1, obie Vy -4), efekt $0A po drugiej. (ix+17/18) + 8, Vy + $20
; (grawitacja), animacja stanu, kolizja z Soniciem (przesuniecie 4, 10), tmp_00 = $0804 (wybuch).
; Pulapka: w ticku strzalu tmp_06 = $FFFC (Vy kuli) zamiast wskaznika stanu - ld a,(tmp_06) czyta lustro
; RAM $DFFC = $80 (cien rejestru mapera, staly w GHZ), add a,a = 0 -> animacja chodzenia (indeks 0).
; ---------------------------------------------------------------------
objfunc_08_crabmeat
	ldy #OB_W
	lda #$10
	sta (zg_obj),y
	iny
	lda #$1F
	sta (zg_obj),y
	ldy #18
	lda (zg_obj),y            ; e = (ix+18)
crb_find
	tax
	clc                       ; tmp_06 = LUT + e (adres SMS - stan gry jak oryginal)
	adc #<LUT_CRAB_SEQ
	sta tmp_06
	lda #>LUT_CRAB_SEQ
	adc #0
	sta tmp_06+1
	lda LUT_CRAB_SEQ,x
	bne crb_found
	ldy #18                   ; stan 0: (ix+18) = 0, od poczatku (A = 0; ldy zmienia Z - skok bezwarunkowy)
	sta (zg_obj),y
	jmp crb_find
crb_found
	sta zg_tab                ; stan (do animacji: ld a,(tmp_06))
	cmp #1
	bne crb_n1
	lda #$28                  ; Vx = $000028
	ldx #$00
	ldy #$00
	beq crb_vx
crb_n1
	cmp #2
	bne crb_n2
	lda #$D8                  ; Vx = $FFFFD8
	ldx #$FF
	ldy #$FF
	bne crb_vx
crb_n2
	cmp #3
	bne crb_fire
	lda #0                    ; Vx = 0
	tax
	tay
crb_vx                          ; (ix+7) = A (L), (ix+8) = X (H), (ix+9) = Y (C)
	sty zg_a
	ldy #OB_VX
	sta (zg_obj),y
	iny
	txa
	sta (zg_obj),y
	iny
	lda zg_a
	sta (zg_obj),y
	jmp crb_cont
crb_fire                        ; @not_state_03: stan 4 - strzal tylko przy (ix+17) = $20
	ldy #17
	lda (zg_obj),y
	cmp #$20
	jne crb_cont
	lda #$FF                  ; tmp_04 = $FFFF (Vx kuli), tmp_06 = $FFFC (Vy kuli)
	sta tmp_04
	sta tmp_04+1
	lda #$FC
	sta tmp_06
	lda #$FF
	sta tmp_06+1
	jsr spawn_object
	bcs crb_fdone             ; jp c: brak slotu
	lda #0                    ; DE = 0, BC = 0
	sta zg_de
	sta zg_de+1
	sta zg_bc
	sta zg_bc+1
	jsr init_fireball_object
	lda #$01                  ; tmp_04 = $0001, tmp_06 = $FFFC
	sta tmp_04
	lda #0
	sta tmp_04+1
	lda #$FC
	sta tmp_06
	lda #$FF
	sta tmp_06+1
	jsr spawn_object
	bcs crb_fdone             ; jr c
	lda #$0E                  ; DE = $000E, BC = 0
	sta zg_de
	lda #0
	sta zg_de+1
	sta zg_bc
	sta zg_bc+1
	jsr init_fireball_object
	lda #$0A                  ; rst $28: strzal
	jsr play_sfx
crb_fdone
	lda #$80                  ; ld a,(tmp_06) z tmp_06 = $FFFC: lustro RAM $DFFC = $80
	sta zg_tab
crb_cont                        ; @continue: (ix+17/18) += 8
	ldy #17
	clc
	lda (zg_obj),y
	adc #8
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	ldy #OB_VY                ; Vy += $000020 (add hl,de / adc a,d)
	clc
	lda (zg_obj),y
	adc #$20
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	lda zg_tab                ; animacja: LUT_crabmeat_state_anim_ptrs[(stan * 2) & $FF] (add a,a / ld e,a)
	asl
	tax
	lda LUT_CRAB_ANIM,x
	sta zg_bc
	lda LUT_CRAB_ANIM+1,x
	sta zg_bc+1
	lda #<SPR_CRAB
	sta zg_de
	lda #>SPR_CRAB
	sta zg_de+1
	jsr do_framed_animation
	lda #$04                  ; tmp_06 = $0A04: przesuniecie x 4, y 10
	sta tmp_06
	lda #$0A
	sta tmp_07
	jsr check_collision_with_sonic
	lda #$04                  ; tmp_00 = $0804 (przed call nc - flagi C z kolizji zostaja)
	sta tmp_00
	lda #$08
	sta tmp_00+1
	bcs crb_ret
	jmp enemy_touched_sonic
crb_ret
	rts

; ---------------------------------------------------------------------
; init_fireball_object (02:AC96): kula ognia w slocie zg_ptr (wynik spawn_object; slot nieczyszczony - pola
; +13..+16, +18, +24, +25 zostaja): typ $0D, X = X obiektu IX + DE, Y = Y obiektu IX + BC (subpiksele 0),
; Vx = (0, tmp_04, tmp_05), Vy = (0, tmp_06, tmp_07), +17 = 0, grawitacja +19/+20 = $0024, +21..+23 = 0.
; Wejscie: zg_de = DE, zg_bc = BC (niszczone). IX bez zmian (push ix / pop ix).
; ---------------------------------------------------------------------
init_fireball_object
	ldy #OB_X+1               ; DE = X + DE
	clc
	lda (zg_obj),y
	adc zg_de
	sta zg_de
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta zg_de+1
	ldy #OB_Y+1               ; BC = Y + BC
	clc
	lda (zg_obj),y
	adc zg_bc
	sta zg_bc
	iny
	lda (zg_obj),y
	adc zg_bc+1
	sta zg_bc+1
	ldy #OB_TYPE
	lda #$0D
	sta (zg_ptr),y
	iny                       ; +1 subpiksel X = 0
	lda #0
	sta (zg_ptr),y
	iny
	lda zg_de
	sta (zg_ptr),y
	iny
	lda zg_de+1
	sta (zg_ptr),y
	iny                       ; +4 subpiksel Y = 0
	lda #0
	sta (zg_ptr),y
	iny
	lda zg_bc
	sta (zg_ptr),y
	iny
	lda zg_bc+1
	sta (zg_ptr),y
	iny                       ; +7 Vx sub = 0, +8/+9 = tmp_04
	lda #0
	sta (zg_ptr),y
	iny
	lda tmp_04
	sta (zg_ptr),y
	iny
	lda tmp_04+1
	sta (zg_ptr),y
	iny                       ; +10 Vy sub = 0, +11/+12 = tmp_06
	lda #0
	sta (zg_ptr),y
	iny
	lda tmp_06
	sta (zg_ptr),y
	iny
	lda tmp_06+1
	sta (zg_ptr),y
	lda #0
	ldy #17
	sta (zg_ptr),y
	ldy #20                   ; +20..+23 = 0
ifb_z
	sta (zg_ptr),y
	iny
	cpy #24
	bne ifb_z
	ldy #19                   ; grawitacja kuli
	lda #$24
	sta (zg_ptr),y
	rts

; ---------------------------------------------------------------------
; objfunc_0D_fireball_pallet (01:6AC1): bez kolizji z mapa, rozmiar 2 x 2; kolizja z Soniciem (przesuniecie 3, 3)
; -> damage_sonic. Vy += (ix+19/20) (grawitacja $24). Rysowanie przed ruchem (draw_sprite w pozycji obiektu:
; tmp_00 = X, tmp_02 = Y, tmp_04 = tmp_06 = 0, mapa 0) kaflem $06 / $08 co drugi tick ($34 / $36 w BRI3/LAB3).
; Koniec ($FF), gdy x - 8 < cam_x, x > cam_x + 256, y + 16 < cam_y albo y > cam_y + 192 (16 bit).
; ---------------------------------------------------------------------
objfunc_0D_fireball
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	ldy #OB_W
	lda #$02
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda #$03                  ; tmp_06 = $0303
	sta tmp_06
	sta tmp_07
	jsr check_collision_with_sonic
	bcs fbl_nohit
	jsr damage_sonic          ; call nc, damage_sonic
fbl_nohit
	ldy #19                   ; Vy += (ix+19/20), przeniesienie do (ix+12)
	lda (zg_obj),y
	sta zg_de
	iny
	lda (zg_obj),y
	sta zg_de+1
	ldy #OB_VY
	clc
	lda (zg_obj),y
	adc zg_de
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc zg_de+1
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	ldy #OB_X+1               ; tmp_00 = X, tmp_02 = Y, tmp_04 = tmp_06 = 0, mapa 0
	lda (zg_obj),y
	sta tmp_00
	iny
	lda (zg_obj),y
	sta tmp_00+1
	ldy #OB_Y+1
	lda (zg_obj),y
	sta tmp_02
	iny
	lda (zg_obj),y
	sta tmp_02+1
	lda #0
	sta tmp_04
	sta tmp_04+1
	sta tmp_06
	sta tmp_06+1
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	lda g_global_tick_counter ; kafel: LUT[tick & 1]
	and #$01
	tax
	lda g_level
	cmp #$05
	beq fbl_bl
	cmp #$0B
	beq fbl_bl
	lda LUT_FIREBALL,x
	jmp fbl_draw
fbl_bl                          ; @sprites_not_BRI3_nor_LAB3 (nazwa w dezasemblacji odwrotna)
	lda LUT_FIREBALL_BL,x
fbl_draw
	jsr draw_sprite
	ldy #OB_X+1               ; HL = X - 8 (add $FFF8); HL < cam_x -> koniec
	sec
	lda (zg_obj),y
	sbc #8
	sta zg_hl
	iny
	lda (zg_obj),y
	sbc #0
	sta zg_hl+1
	lda zg_hl
	cmp g_level_scroll_x_pix_lo
	lda zg_hl+1
	sbc g_level_scroll_x_pix_lo+1
	bcc fbl_kill
	ldx g_level_scroll_x_pix_lo+1 ; HL = cam_x + 256 (inc d) - X (sbc z C = 0 z poprzedniego) < 0 -> koniec
	inx
	stx zg_a
	ldy #OB_X+1
	lda g_level_scroll_x_pix_lo
	cmp (zg_obj),y
	iny
	lda zg_a
	sbc (zg_obj),y
	bcc fbl_kill
	ldy #OB_Y+1               ; HL = Y + 16; HL < cam_y -> koniec
	clc
	lda (zg_obj),y
	adc #16
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	lda zg_hl
	cmp g_level_scroll_y_pix_lo
	lda zg_hl+1
	sbc g_level_scroll_y_pix_lo+1
	bcc fbl_kill
	clc                       ; HL = cam_y + $C0; HL >= Y -> zostaje (ret nc)
	lda g_level_scroll_y_pix_lo
	adc #$C0
	sta zg_hl
	lda g_level_scroll_y_pix_lo+1
	adc #0
	sta zg_hl+1
	ldy #OB_Y+1
	lda zg_hl
	cmp (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	bcs fbl_ret
fbl_kill                        ; @destroy_fireball_because_offscreen
	ldy #OB_TYPE
	lda #$FF
	sta (zg_obj),y
fbl_ret
	rts

; =====================================================================
;  M4.6b: objfunc_0E_badnik_buzz_bomber (01:6B74). Dane: LUT_buzz_bomber_state_sequence 01:6CD7,
;  LUT_buzz_bomber_state_anim_ptrs 01:6CE2, SPRITEMAP_buzz_bomber_frames 01:6CF9 (bank 45 pod adresami SMS).
; =====================================================================
LUT_BUZZ_SEQ     = $6CD7   ; stan na kazde 32 ticki: 1 lot w lewo, 2 postoj, 3 strzal, 0 = od poczatku
LUT_BUZZ_ANIM    = $6CE2   ; sekwencje animacji dla stanow 0..3 (slowa)
SPR_BUZZ         = $6CF9   ; mapy klatek (18 B)

; ---------------------------------------------------------------------
; objfunc_0E_badnik_buzz_bomber (01:6B74): bez kolizji z mapa (set 5). Inicjalizacja ((ix+24) b0 = 0): (ix+20/21)
; = x startowe, mapa 0, (ix+18) = 0, Vx = 0; czeka, az x > cam_x + 256 (add hl,bc / sbc hl,de - przeniesienie
; dodawania wchodzi do odejmowania, pulapka 2), potem set 0. Rozmiar 20 x 32. Gdy 0 <= x - sonic_x < $40
; i (ix+18) < 5: (ix+18) = 5 (postoj i strzal). Stan z sekwencji (ix+18) (tmp_06 = adres SMS pozycji):
; 1 - Vx = -2 px/tick, a gdy x + $30 < cam_x: mapa 0, x = startowe, res 0, koniec; 2 - Vx = 0; 3 - przy
; (ix+17) = $20 kula ognia (spawn_object: typ $0D, x, y + $20, Vx = $FFFF00, Vy = $000180, pola +17, +19..+23 = 0,
; reszta slotu zostaje - pulapka 5), efekt $0A, Vx = 0. (ix+17/18) += 8 (stan co 32 ticki), animacja stanu
; (do_framed_animation), kolizja z Soniciem (tmp_06 = $1000) -> enemy_touched_sonic (tmp_00 = $1004).
; ---------------------------------------------------------------------
objfunc_0E_buzz_bomber
	ldy #OB_FLAGS             ; set 5,(ix+24)
	lda (zg_obj),y
	ora #$20
	sta (zg_obj),y
	and #$01                  ; bit 0,(ix+24)
	jne bzb_ready
	ldy #OB_X+1               ; (ix+20/21) = x
	lda (zg_obj),y
	ldy #20
	sta (zg_obj),y
	ldy #OB_X+2
	lda (zg_obj),y
	ldy #21
	sta (zg_obj),y
	lda #0                    ; mapa 0, (ix+18) = 0, Vx = 0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #18
	sta (zg_obj),y
	ldy #OB_VX
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	clc                       ; HL = cam_x + $0100 (add hl,bc: C = przeniesienie)
	lda g_level_scroll_x_pix_lo
	adc #$00
	sta zg_hl
	lda g_level_scroll_x_pix_lo+1
	adc #$01
	sta zg_hl+1
	lda #0                    ; sbc hl,de z przeniesieniem z dodawania: C 6502 = odwrotnosc C Z80
	rol
	eor #$01
	lsr
	ldy #OB_X+1
	lda zg_hl
	sbc (zg_obj),y
	iny
	lda zg_hl+1
	sbc (zg_obj),y
	jcs bzb_ret               ; ret nc: x <= cam_x + 256 - czeka
	ldy #OB_FLAGS             ; set 0,(ix+24)
	lda (zg_obj),y
	ora #$01
	sta (zg_obj),y
bzb_ready                       ; @already_initialised
	ldy #OB_W
	lda #$14
	sta (zg_obj),y
	iny
	lda #$20
	sta (zg_obj),y
	ldy #OB_X+1               ; HL = x - sonic_x (and a / sbc hl,de)
	sec
	lda (zg_obj),y
	sbc sonic_x
	sta zg_hl
	iny
	lda (zg_obj),y
	sbc sonic_x+1
	sta zg_hl+1
	bcc bzb_nr                ; jr c
	lda zg_hl                 ; sbc hl,$0040 (C Z80 = 0 po poprzednim: C 6502 = 1)
	sbc #$40
	lda zg_hl+1
	sbc #$00
	bcs bzb_nr                ; jr nc: >= $40
	ldy #18
	lda (zg_obj),y
	cmp #$05
	bcs bzb_nr
	lda #$05
	sta (zg_obj),y
bzb_nr                          ; @not_ready_to_fire
	ldy #18
	lda (zg_obj),y
bzb_find
	tax
	clc                       ; tmp_06 = LUT + e (adres SMS)
	adc #<LUT_BUZZ_SEQ
	sta tmp_06
	lda #>LUT_BUZZ_SEQ
	adc #0
	sta tmp_06+1
	lda LUT_BUZZ_SEQ,x
	bne bzb_found
	ldy #18                   ; stan 0: (ix+18) = 0, od poczatku
	sta (zg_obj),y
	jmp bzb_find
bzb_found
	sta zg_tab                ; stan (ld hl,(tmp_06) / ld a,(hl) w @continue - ta sama wartosc)
	cmp #1
	bne bzb_n1
	ldy #OB_X+1               ; HL = x + $30; xor a / sbc hl,de (cam_x): pozyczka -> za lewa krawedzia
	clc
	lda (zg_obj),y
	adc #$30
	sta zg_hl
	iny
	lda (zg_obj),y
	adc #0
	sta zg_hl+1
	sec
	lda zg_hl
	sbc g_level_scroll_x_pix_lo
	lda zg_hl+1
	sbc g_level_scroll_x_pix_lo+1
	bcs bzb_fly               ; jr nc
	lda #0                    ; mapa 0 (A = 0 po xor a), x = startowe, res 0
	ldy #OB_SPRITE
	sta (zg_obj),y
	iny
	sta (zg_obj),y
	ldy #20
	lda (zg_obj),y
	ldy #OB_X+1
	sta (zg_obj),y
	ldy #21
	lda (zg_obj),y
	ldy #OB_X+2
	sta (zg_obj),y
	ldy #OB_FLAGS
	lda (zg_obj),y
	and #$FE
	sta (zg_obj),y
bzb_ret
	rts
bzb_fly                         ; @was_not_off_left_side: Vx = $FFFE00
	lda #$00
	ldx #$FE
	ldy #$FF
	jmp bzb_vx
bzb_n1
	cmp #2
	beq bzb_vx0               ; stan 2: Vx = 0
	ldy #17                   ; stan 3: strzal przy (ix+17) = $20
	lda (zg_obj),y
	cmp #$20
	bne bzb_cont
	jsr spawn_object
	bcs bzb_cont              ; jp c: brak slotu
	ldy #OB_TYPE              ; kula ognia (IX = nowy slot; pola +13..+16, +18, +24, +25 zostaja)
	lda #$0D
	sta (zg_ptr),y
	lda #0
	iny
	sta (zg_ptr),y            ; (ix+1) = 0
	ldy #OB_X+1
	lda (zg_obj),y
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	sta (zg_ptr),y
	lda #0
	ldy #OB_Y
	sta (zg_ptr),y            ; (ix+4) = 0
	iny
	clc                       ; y = y wroga + $20
	lda (zg_obj),y
	adc #$20
	sta (zg_ptr),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_ptr),y
	lda #0
	ldy #17
	sta (zg_ptr),y
	ldy #19
bzb_z
	sta (zg_ptr),y            ; (ix+19)..(ix+23) = 0
	iny
	cpy #24
	bne bzb_z
	ldy #OB_VX                ; Vx = $FFFF00, Vy = $000180
	sta (zg_ptr),y
	iny
	lda #$FF
	sta (zg_ptr),y
	iny
	sta (zg_ptr),y
	iny
	lda #$80
	sta (zg_ptr),y
	iny
	lda #$01
	sta (zg_ptr),y
	iny
	lda #$00
	sta (zg_ptr),y
	lda #$0A                  ; rst $28: strzal
	jsr play_sfx
bzb_vx0
	lda #0
	tax
	tay
bzb_vx                          ; @update_vel_x_and_continue: (ix+7) = A (L), (ix+8) = X (H), (ix+9) = Y (C)
	sty zg_a
	ldy #OB_VX
	sta (zg_obj),y
	iny
	txa
	sta (zg_obj),y
	iny
	lda zg_a
	sta (zg_obj),y
bzb_cont                        ; @continue: (ix+17/18) += 8
	ldy #17
	clc
	lda (zg_obj),y
	adc #8
	sta (zg_obj),y
	iny
	lda (zg_obj),y
	adc #0
	sta (zg_obj),y
	lda zg_tab                ; animacja stanu
	asl
	tax
	lda LUT_BUZZ_ANIM,x
	sta zg_bc
	lda LUT_BUZZ_ANIM+1,x
	sta zg_bc+1
	lda #<SPR_BUZZ
	sta zg_de
	lda #>SPR_BUZZ
	sta zg_de+1
	jsr do_framed_animation
	lda #$00                  ; tmp_06 = $1000
	sta tmp_06
	lda #$10
	sta tmp_06+1
	jsr check_collision_with_sonic
	lda #$04                  ; tmp_00 = $1004 (lda / sta nie zmieniaja C)
	sta tmp_00
	lda #$10
	sta tmp_00+1
	bcs bzb_end               ; call nc, enemy_touched_sonic
	jmp enemy_touched_sonic
bzb_end
	rts
