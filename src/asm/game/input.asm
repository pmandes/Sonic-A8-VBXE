; =====================================================================
;  input.asm - wejscie gracza: joystick 0, skrypt testowy (bank BANK_SCRIPT) albo demo z ROM-u
; =====================================================================

; read_input: bajt wejscia ticku v_step -> g_inputs_player_1; odpowiednik poll_player_1_inputs (00:05A7)
; w IRQ: port $DC | $C0, przycisk 1 zeruje tez b5 (@fn_pretend_button_2_pressed 00:00F2).
; Joystick Atari: PORTA b0-b3 = U D L R (aktywne zerem, jak SMS), TRIG0 = 0 -> przycisk 1.
read_input
	lda v_input_mode
	cmp #IN_SCRIPT
	beq ri_script
	lda v_joy
	ora #$F0
	ldx v_trig
	bne ri_set
	and #$CF
ri_set
	sta g_inputs_player_1
	sta v_irq_in              ; M4.8: stan kontrolera ticku (IRQ w load_art - game/objcom.asm irq_extra)
	rts
; skrypt: bajt ticku n pod BANK_WIN + n - 1 (do 16384 tickow; dalej $FF)
ri_script
	lda v_step+1
	cmp #$40
	bcs ri_none
	lda #BANK_SCRIPT
	jsr select_bank
	sec
	lda v_step
	sbc #1
	sta zg_src
	lda v_step+1
	sbc #0
	ora #>BANK_WIN
	sta zg_src+1
	ldy #0
	lda (zg_src),y
	tax
	lda #PB_MAIN
	sta PORTB
	stx g_inputs_player_1
	stx v_irq_in
	rts
ri_none
	lda #$FF
	sta g_inputs_player_1
	sta v_irq_in
	rts

; update_demo_inputs (00:1BAD): wejscie z ARRAY_demo_inputs[relptr], relptr++ gdy (licznik tickow & $1F) = 0.
; Gra indeksuje 16-bitowo; tu tablica 256 B (demo konczy sie przed 131. bajtem).
update_demo_inputs
	ldx g_demo_next_input_relptr
	lda demo_inputs,x
	sta g_inputs_player_1
	lda g_global_tick_counter
	and #$1F
	bne udi_done
	inc g_demo_next_input_relptr
	bne udi_done
	inc g_demo_next_input_relptr+1
udi_done
	rts
