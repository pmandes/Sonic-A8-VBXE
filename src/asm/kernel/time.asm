; =====================================================================
;  time.asm - pomiar czasu w liniach ekranu i wolnych cyklach CPU (M1/M2, potok M3.1)
;  Czas = (licznik ramek v_frame z VBI, VCOUNT). VBI zwieksza v_frame w linii 248, nie 0, dlatego
;  pozycje w ramce liczymy wzgledem linii 248 (vc_rel). v_lpf = linie na ramke (312 PAL / 262 NTSC).
; =====================================================================

; snap_time: zapamietuje chwile startu pomiaru (zp_fr0 = v_frame, zp_vc0 = VCOUNT)
snap_time
	lda v_frame
	sta zp_fr0
	lda VCOUNT
	sta zp_vc0
	rts

; vc_rel: A = VCOUNT (linia/2) -> zp_lo = numer linii liczony od linii 248 (VBI) w biezacej "ramce v_frame".
; Linie >= 248 to poczatek ramki v_frame (0..63/13), linie < 248 to jej dalsza czesc (+ lpf - 248).
vc_rel
	asl                       ; VCOUNT liczy co 2 linie
	sta zp_lo
	lda #0
	rol
	sta zp_lo+1               ; zp_lo = linia (9 bitow)
	bne vr_hi                 ; >= 256 -> na pewno >= 248
	lda zp_lo
	cmp #248
	bcs vr_hi
	clc                       ; linia < 248: przed VBI, czyli koniec "ramki" -> + (lpf - 248)
	lda zp_lo
	adc v_lpf_m248
	sta zp_lo
	lda zp_lo+1
	adc v_lpf_m248+1
	sta zp_lo+1
	rts
vr_hi                           ; linia >= 248: tuz po VBI -> linia - 248
	sec
	lda zp_lo
	sbc #248
	sta zp_lo
	lda zp_lo+1
	sbc #0
	sta zp_lo+1
	rts

; elapsed_lines: zp_lo = liczba linii od snap_time (uwzglednia pelne ramki miedzy pomiarami).
; Niszczy A, X, zp_tmp. Nie zmienia zp_fr0/zp_vc0 (mozna mierzyc kilka odcinkow od jednego startu).
elapsed_lines
	lda zp_vc0
	jsr vc_rel
	lda zp_lo
	sta zp_tmp
	lda zp_lo+1
	sta zp_tmp+1
	lda VCOUNT
	jsr vc_rel
	sec
	lda zp_lo
	sbc zp_tmp
	sta zp_lo
	lda zp_lo+1
	sbc zp_tmp+1
	sta zp_lo+1
	lda v_frame               ; + pelne ramki, ktore minely od startu
	sec
	sbc zp_fr0
	beq el_done
	tax
el_add
	clc
	lda zp_lo
	adc v_lpf
	sta zp_lo
	lda zp_lo+1
	adc v_lpf+1
	sta zp_lo+1
	dex
	bne el_add
el_done
	rts

; max_cpu: v_cpu_max = max(v_cpu_max, v_cpu_last) - najdluzszy czas pracy CPU nad ticki i lista
max_cpu
	lda v_cpu_last+1
	cmp v_cpu_max+1
	bcc mc_done
	bne mc_set
	lda v_cpu_last
	cmp v_cpu_max
	bcc mc_done
mc_set
	mwa v_cpu_last v_cpu_max
mc_done
	rts

; record_blit: po zakonczeniu listy: v_blit_last/max = linie od startu listy; v_late++, gdy lista
; przeszla przez VBI (ramka bez flipu - obraz spozniony o ramke)
record_blit
	jsr elapsed_lines
	mwa zp_lo v_blit_last
	lda zp_lo+1
	cmp v_blit_max+1
	bcc rb_nomax
	bne rb_max
	lda zp_lo
	cmp v_blit_max
	bcc rb_nomax
rb_max
	mwa zp_lo v_blit_max
rb_nomax
	lda v_frame
	cmp zp_fr0
	beq rb_done
	inc v_late
rb_done
	rts

; wait_tick: czeka na nastepne VBI (zmiane v_frame)
wait_tick
	lda v_frame
wt_l
	cmp v_frame
	beq wt_l
	rts

; wait_frame_vc: czeka na poczatek ramki wg VCOUNT (bez NMI - przy wylaczonych przerwaniach)
wait_frame_vc
wf_a
	lda VCOUNT
	bne wf_a
wf_b
	lda VCOUNT
	beq wf_b
	rts

; idle_until_tick: petla jalowa do VBI, liczy obiegi (18 cykli kazdy): v_idle_last, v_idle_min.
; W potoku wolany na poczatku petli glownej - to czas od konca listy do VBI.
idle_until_tick
	lda #0
	sta zp_cnt
	sta zp_cnt+1
	lda v_frame
	sta zp_fr0
idle_l
	inc zp_cnt
	bne idle_c
	inc zp_cnt+1
idle_c
	lda v_frame
	cmp zp_fr0
	beq idle_l
	mwa zp_cnt v_idle_last
	lda zp_cnt+1
	cmp v_idle_min+1
	bcc idle_setmin
	bne idle_done
	lda zp_cnt
	cmp v_idle_min
	bcs idle_done
idle_setmin
	mwa zp_cnt v_idle_min
idle_done
	rts

; wait_list: czeka na koniec listy ramki; v_wait_last = iteracje petli (17 cykli) - wolny czas CPU
wait_list
	lda #0
	sta zp_cnt
	sta zp_cnt+1
	ldy #VC_BLT_START
wl_poll
	lda (zp_fx),y
	and #3
	beq wl_done
	inc zp_cnt
	bne wl_poll
	inc zp_cnt+1
	bne wl_poll
	lda #5
	jmp fail
wl_done
	mwa zp_cnt v_wait_last
	rts

; calc_free: v_free_last = v_wait_last*17 + v_idle_last*18 = wolne cykle CPU ramki (czekanie na liste
; i na VBI); v_free_min pomija ramki z pelnym przeladowaniem pierscienia (v_reload_now)
calc_free                       ; M3.8c: (wait + idle) * 17 + idle (ok. 85 cykli zamiast ok. 290)
	clc
	lda v_wait_last
	adc v_idle_last
	tax                       ; s = wait + idle
	lda v_wait_last+1
	adc v_idle_last+1
	tay
	stx zp_tmp
	asl zp_tmp
	rol
	asl zp_tmp
	rol
	asl zp_tmp
	rol
	asl zp_tmp
	rol                       ; A:zp_tmp = s * 16
	sta zp_tmp+1
	txa
	clc
	adc zp_tmp
	sta zp_tmp
	tya
	adc zp_tmp+1
	sta zp_tmp+1              ; s * 17
	clc
	lda zp_tmp
	adc v_idle_last
	sta v_free_last
	lda zp_tmp+1
	adc v_idle_last+1
	sta v_free_last+1
	lda v_reload_now
	bne cf_done
	lda v_free_last+1
	cmp v_free_min+1
	bcc cf_set
	bne cf_done
	lda v_free_last
	cmp v_free_min
	bcs cf_done
cf_set
	mwa v_free_last v_free_min
cf_done
	rts
