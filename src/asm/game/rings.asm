; =====================================================================
;  rings.asm - pierscienie w petli poziomu (M3.5): animacja kafli pierscienia i lata ekranu po zebraniu
;
;  Gra SMS trzyma grafike pierscienia w kafach VDP $FC-$FF (bloki $79-$7B maja je w polowce 16x16):
;   - update_ring_tile_art_timer_and_index (00:239C): co 10 tickow nastepna z 6 klatek; wskaznik grafiki
;     g_new_ring_tiles_ptr = $7CF0 + LUT_ring_tile_index_map[indeks] * $80 (bank $0B);
;   - update_ring_tiles (00:3879): na poczatku nastepnego ticku, gdy wskaznik sie zmienil, 128 B do VRAM SMS
;     i g_old_ring_tiles_ptr = nowy;
;   - zebranie (sonic.asm sh_collect_ring): bit pierscienia w bajcie ukladu, pozycja w
;     g_screen_tile_replace_x/y; IRQ nastepnej ramki (00:0162) kladzie na ekranie 2x2 puste kafle
;     (apply_screen_tilemap_patch 00:38B0) i ustawia g_screen_tile_replace_x_hi = $FF.
;  Na Atari: numer klatki (v_ring_art) i blok do ponownego blitu (v_patch_*) dla renderera
;  (render/rings.asm). Blok po zebraniu ma w miejscu pierscienia kafel 0 - ten sam obraz co lata SMS.
;  Nazwy i adresy wg dezasemblacji s1smsdisasm-gm (tylko material referencyjny, kod napisany od nowa).
; =====================================================================
RING_ART_SMS = $7CF0       ; adres grafiki pierscienia w banku $0B (klatka k: + k * $80)

; irq_tile_patch: czesc IRQ (00:0162-00:016C) wykonywana na poczatku kazdego kroku (jedno IRQ na krok):
; g_screen_tile_replace_x_hi b7 = 0 -> lata ekranu; potem $FF. Dane TILEREPLACE_ring_blanking ($595D) - zebrany
; pierscien: renderer blituje ponownie blok pod (x, y) (uklad ma juz blok bez pierscienia). M4.7: inne dane - lata
; 2 x 2 kafli (kwiaty) jak apply_screen_tilemap_patch 00:38B0: tylko gdy (x & $F8) - (cam_x & $F8) w 8..255
; i (y & $F8) - (cam_y & $F8) w 0..191 (16 bit); renderer kopiuje kafle z atlasu tla do pierscienia (tile_patch).
TILEREPLACE_RING = $595D   ; TILEREPLACE_ring_blanking (01:595D)
irq_tile_patch
	lda g_screen_tile_replace_x+1
	bmi itp_done
	lda g_screen_tile_replace_data_ptr
	cmp #<TILEREPLACE_RING
	bne itp_tiles
	lda g_screen_tile_replace_data_ptr+1
	cmp #>TILEREPLACE_RING
	bne itp_tiles
	lda g_screen_tile_replace_x+1
	sta zs_t                  ; blok = (x >> 5, y >> 5) (uklad 256 x 16 blokow - 8 bitow)
	lda g_screen_tile_replace_x
	ldx #5
itp_cx
	lsr zs_t
	ror
	dex
	bne itp_cx
	sta v_patch_c
	lda g_screen_tile_replace_y+1
	sta zs_t
	lda g_screen_tile_replace_y
	ldx #5
itp_cy
	lsr zs_t
	ror
	dex
	bne itp_cy
	sta v_patch_r
	lda #1
	sta v_patch_on            ; build_list: blok (v_patch_c, v_patch_r) z ukladu do pierscienia tla
itp_done
	lda #$FF
	sta g_screen_tile_replace_x+1
	rts
itp_tiles                       ; M4.7: apply_screen_tilemap_patch - warunki polozenia na ekranie
	lda g_screen_tile_replace_x ; HL = (x & $F8) - (cam_x & $F8): ret c, ret nz (H), L < 8 -> ret
	and #$F8
	sta zs_t
	lda g_level_scroll_x_pix_lo
	and #$F8
	sta zs_t+1
	sec
	lda zs_t
	sbc zs_t+1
	sta zs_t
	lda g_screen_tile_replace_x+1
	sbc g_level_scroll_x_pix_lo+1
	bcc itp_done
	bne itp_done
	lda zs_t
	cmp #$08
	bcc itp_done
	lda g_screen_tile_replace_y ; (y & $F8) - (cam_y & $F8): ret c, ret nz, L >= $C0 -> ret
	and #$F8
	sta zs_t
	lda g_level_scroll_y_pix_lo
	and #$F8
	sta zs_t+1
	sec
	lda zs_t
	sbc zs_t+1
	sta zs_t
	lda g_screen_tile_replace_y+1
	sbc g_level_scroll_y_pix_lo+1
	bcc itp_done
	bne itp_done
	lda zs_t
	cmp #$C0
	bcs itp_done
	jsr glass_read            ; M6.10: lata szyby bossa SKY3 (render/rings.asm) - do slotu magazynu bloku
	bcs itp_tp
	jsr glass_req
	jmp itp_done
itp_tp
	jsr tp_read               ; kafle z danych (bank 45; render/rings.asm) -> v_tpt; C = 1: dane spoza kwiatow
	bcs itp_done
	lda g_screen_tile_replace_x
	and #$F8
	sta v_tpx
	lda g_screen_tile_replace_x+1
	sta v_tpx+1
	lda g_screen_tile_replace_y
	and #$F8
	sta v_tpy
	lda g_screen_tile_replace_y+1
	sta v_tpy+1
	lda #1
	sta v_tp_on
	jmp itp_done

; glass_req (M6.10): lata szyby (kafle w v_gp_t z glass_read) - kafel (x & $18) >> 3, (y & $18) >> 3 w bloku (x >> 5, y >> 5): slot
; magazynu bloku (BLKMAP_RAM[blok z ukladu]) dostaje 4 kafle atlasu (render/frame.asm glass_store - BCB wykonane przed blokami listy),
; blok wraca do pierscienia jak po zebraniu pierscienia (v_patch_*). Oryginal pisze do tablicy nazw VDP (z priorytetem kafla); przy
; przewinieciu kamery VDP odtwarza szybe z ukladu - w porcie stluczona zostaje (znana roznica, tylko obraz: po 15. lacie kamera sie
; odblokowuje i przy x > 1119 kolumny szyby wychodza z okna - po powrocie oryginal pokazuje cala szybe, port stluczona; review M6.10).
; v_gl_mask: bit (ptr - $BA49) / 12 - lata nalozona (model obrazu).
glass_req
	lda g_screen_tile_replace_x
	and #$18
	lsr
	lsr
	lsr
	sta v_gp_tx
	lda g_screen_tile_replace_y
	and #$18
	lsr
	lsr
	lsr
	sta v_gp_ty
	lda g_screen_tile_replace_x+1
	sta zs_t
	lda g_screen_tile_replace_x
	ldx #5
grq_cx
	lsr zs_t
	ror
	dex
	bne grq_cx
	sta v_patch_c
	lda g_screen_tile_replace_y+1
	sta zs_t
	lda g_screen_tile_replace_y
	ldx #5
grq_cy
	lsr zs_t
	ror
	dex
	bne grq_cy
	sta v_patch_r
	tay
	lda LAYROW_LO,y           ; blok z ukladu -> slot magazynu
	sta zs_t
	lda LAYROW_HI,y
	sta zs_t+1
	ldy v_patch_c
	lda (zs_t),y
	tay
	lda BLKMAP_RAM,y
	sta v_gp_slot
	lda #1
	sta v_patch_on
	sta v_gp_on
	lda g_screen_tile_replace_data_ptr ; k = (ptr - $49) / 12 -> bit w v_gl_mask
	sec
	sbc #$49
	ldx #0
grq_k
	cmp #12
	bcc grq_bit
	sbc #12
	inx
	bne grq_k                 ; zawsze
grq_bit
	txa
	and #7
	tay
	lda bit_tab8,y
	cpx #8
	bcs grq_hi
	ora v_gl_mask
	sta v_gl_mask
	rts
grq_hi
	ora v_gl_mask+1
	sta v_gl_mask+1
	rts
bit_tab8	dta b($01, $02, $04, $08, $10, $20, $40, $80)

; update_ring_tiles (00:3879): nowa klatka grafiki pierscienia, gdy wskaznik nowy != stary;
; renderer dostaje numer klatki v_ring_art = (wskaznik - $7CF0) / $80 (0-5)
update_ring_tiles
	lda g_new_ring_tiles_ptr
	cmp g_old_ring_tiles_ptr
	bne urt_go
	lda g_new_ring_tiles_ptr+1
	cmp g_old_ring_tiles_ptr+1
	beq urt_ret               ; ret z
urt_go
	sec
	lda g_new_ring_tiles_ptr
	sbc #<RING_ART_SMS
	sta zs_t
	lda g_new_ring_tiles_ptr+1
	sbc #>RING_ART_SMS
	asl zs_t                  ; (hi:lo) >> 7 = hi * 2 + b7 lo
	rol
	sta v_ring_art
	lda g_new_ring_tiles_ptr  ; g_old_ring_tiles_ptr = nowy
	sta g_old_ring_tiles_ptr
	lda g_new_ring_tiles_ptr+1
	sta g_old_ring_tiles_ptr+1
urt_ret
	rts

; ring_art_timer: update_ring_tile_art_timer_and_index (00:239C)
; g_new_ring_tiles_ptr = $7CF0 + LUT[indeks] * $80; licznik +1, przy 10 -> 0 i indeks +1 (mod 6)
ring_art_timer
	ldx g_ring_tile_index
	lda SONIC_RINGMAP,x       ; LUT_ring_tile_index_map (00:23F9)
	lsr                       ; HL = A * $80: H = A >> 1, L = b0 << 7 (srl a / rr l)
	sta zs_t
	lda #0
	ror
	clc
	adc #<RING_ART_SMS
	sta g_new_ring_tiles_ptr
	lda zs_t
	adc #>RING_ART_SMS
	sta g_new_ring_tiles_ptr+1
	inc g_ring_tile_subtimer_index
	lda g_ring_tile_subtimer_index
	cmp #10
	bcc rat_ret               ; < 10 -> ret c
	lda #0
	sta g_ring_tile_subtimer_index
	ldx g_ring_tile_index
	inx
	cpx #6
	bcc rat_idx               ; @skip_wrap_tile_index
	ldx #0
rat_idx
	stx g_ring_tile_index
rat_ret
	rts
