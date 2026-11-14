; =====================================================================
;  sms.inc - lustro RAM gry SMS w pamieci Atari (docs/plan-m3.md 3.2)
;
;  SMS $D000-$DFFF (zmienne, object_list, stos) -> Atari $E000-$EFFF (RAM pod OS, przesuniecie +$1000);
;  SMS $C000-$CFFF (uklad poziomu, stride 256)   -> Atari $1000-$1FFF (LAYOUT_RAM).
;  Ten sam uklad bajtow co w grze: stan porownywalny bajt w bajt z referencja (tools/m3_diff.py).
;  Nazwy i adresy wg dezasemblacji s1smsdisasm-gm (tylko material referencyjny).
; =====================================================================
SMS_RAM      = $E000-$D000          ; przesuniecie lustra zmiennych
SMS_LAYOUT   = LAYOUT_RAM-$C000      ; przesuniecie lustra ukladu

iy_00                             = $D200+SMS_RAM
iy_02                             = $D202+SMS_RAM
g_inputs_player_1                 = $D203+SMS_RAM   ; b0 U b1 D b2 L b3 R b4 1 b5 1|2, aktywne zerem
iy_05_lvflag00                    = $D205+SMS_RAM   ; bit 1 = demo
iy_06_lvflag01                    = $D206+SMS_RAM
iy_07_lvflag02                    = $D207+SMS_RAM
iy_08_lvflag03                    = $D208+SMS_RAM
iy_09                             = $D209+SMS_RAM
g_sprite_count                    = $D20A+SMS_RAM
iy_0B_old_lvflag00_UNUSED         = $D20B+SMS_RAM
iy_0C_old_lvflag01                = $D20C+SMS_RAM
tmp_00                            = $D20E+SMS_RAM   ; tmp_00..tmp_09: pamiec robocza procedur gry
tmp_02                            = $D210+SMS_RAM   ; (2) return_from_objfunc: przesuniecie punktu testu
tmp_06                            = $D214+SMS_RAM   ; return_from_objfunc: typ kolizji bloku (flagi & $3F)
tmp_08                            = $D216+SMS_RAM
g_global_tick_counter             = $D223+SMS_RAM   ; (2)
g_SIG00b3_palette_addr            = $D22B+SMS_RAM   ; (2)
g_SIG00b3_palettes_present        = $D22F+SMS_RAM
g_level_width                     = $D238+SMS_RAM   ; (2)
g_level_height                    = $D23A+SMS_RAM   ; (2)
g_level                           = $D23E+SMS_RAM
g_next_bonus_level                = $D23F+SMS_RAM
g_lives                           = $D246+SMS_RAM
g_water_irq_line_state            = $D247+SMS_RAM
g_water_onscreen_y                = $D248+SMS_RAM
g_level_tilemap_ptr               = $D24F+SMS_RAM   ; (2)
g_vdp_scroll_x                    = $D251+SMS_RAM
g_vdp_scroll_y                    = $D252+SMS_RAM
g_level_scroll_tile_x             = $D257+SMS_RAM
g_level_scroll_tile_y             = $D258+SMS_RAM
g_level_scroll_x_sub              = $D259+SMS_RAM   ; kamera X: subpiksel (+1 lo, +2 hi)
g_level_scroll_x_pix_lo           = $D25A+SMS_RAM   ; (2) lewa krawedz widoku w pikselach poziomu
g_level_scroll_y_sub              = $D25C+SMS_RAM   ; kamera Y: subpiksel (kolysanie)
g_level_scroll_y_pix_lo           = $D25D+SMS_RAM   ; (2) gorna krawedz widoku
g_camera_sonic_bounds_x0          = $D25F+SMS_RAM   ; (2)
g_camera_sonic_bounds_x1          = $D261+SMS_RAM   ; (2)
g_camera_sonic_bounds_y0          = $D263+SMS_RAM   ; (2)
g_camera_sonic_bounds_y1          = $D265+SMS_RAM   ; (2)
g_camera_sonic_bounds_x0_target   = $D267+SMS_RAM   ; (2) cele granic okna Sonica (0 = domyslny, M3.4)
g_camera_sonic_bounds_x1_target   = $D269+SMS_RAM   ; (2)
g_camera_sonic_bounds_y0_target   = $D26B+SMS_RAM   ; (2)
g_camera_sonic_bounds_y1_target   = $D26D+SMS_RAM   ; (2)
g_displayed_level_scroll_x_pix_lo = $D26F+SMS_RAM   ; (2)
g_displayed_level_scroll_y_pix_lo = $D271+SMS_RAM   ; (2)
g_level_limit_x0                  = $D273+SMS_RAM   ; (8) x0, x1, y0, y1
g_level_limit_y0                  = $D277+SMS_RAM   ; (2)
g_level_camera_lock_towards_x     = $D27B+SMS_RAM   ; (2)
g_level_camera_lock_towards_y     = $D27D+SMS_RAM   ; (2)
g_level_restart_countdown_timer   = $D287+SMS_RAM
g_new_ring_tiles_ptr              = $D293+SMS_RAM   ; (2) grafika pierscienia do wgrania (adres SMS w banku $0B)
g_old_ring_tiles_ptr              = $D295+SMS_RAM   ; (2) grafika wgrana
g_ring_tile_index                 = $D297+SMS_RAM   ; indeks animacji pierscienia 0-5
g_ring_tile_subtimer_index        = $D298+SMS_RAM   ; licznik tickow do nastepnej klatki (0-9)
g_sonic_underwater_countup_timer  = $D29B+SMS_RAM   ; (2) M6.8: ticki Sonika pod woda (tonienie od $300, smierc przy $900)
g_y_oscillate_baseline_current    = $D29D+SMS_RAM   ; (2) kolysanie kamery Y: predkosc (sub, lo)
g_y_oscillate_baseline_target     = $D29F+SMS_RAM   ; (2) przyrost predkosci (+-2)
g_y_oscillate_sub                 = $D2A1+SMS_RAM   ; przesuniecie kolysania: subpiksel
g_y_oscillate_pix                 = $D2A2+SMS_RAM   ; (2) piksele lo, hi
g_palette_cycle_tick_remain       = $D2A4+SMS_RAM   ; (4) + g_palette_cycle_baseptr
g_palette_cycle_baseptr           = $D2A8+SMS_RAM   ; (2)
g_good_ending_emerald_anim_countdown_timer = $D2FE+SMS_RAM   ; M6.11: licznik animacji Sonika przy szmaragdzie $54 (dobre zakonczenie, 01:52C1)
g_lightning_timer                 = $D2E9+SMS_RAM   ; M6.10: (2) licznik blyskawic SKY1 0..$AA (handle_SKY1_lightning_timer 00:1F49; nie zerowany przy starcie)
g_rings_BCD                       = $D2AA+SMS_RAM
g_screen_tile_replace_x           = $D2AB+SMS_RAM   ; (2) lata ekranu po zebraniu pierscienia (hi b7 = 1: brak)
g_demo_next_input_relptr          = $D2B5+SMS_RAM   ; (2)
g_camera_y_look_up_offset_px      = $D2B7+SMS_RAM   ; (2)
g_time_mins                       = $D2CE+SMS_RAM   ; (3)
g_tile_flags_index                = $D2D4+SMS_RAM
g_next_level_override_target      = $D2D3+SMS_RAM   ; M6.9: naglowek poziomu do zaladowania przy iy_06 b4 (korytarz $13, teleport $0B)
g_teleport_spec_dest_ptr          = $D2D5+SMS_RAM   ; M6.9: (2) adres SMS wpisu tablicy teleportow 01:5643 + 2 (cel X, cel Y, poziom)
iy_0D                             = $D20D+SMS_RAM   ; M6.9: b2 = przejscie do nastepnego g_level bez wyniku i mapy (teleport $FF - SKY3)
g_water_level_y                   = $D2DC+SMS_RAM   ; (2)
g_object_count                    = $D2F2+SMS_RAM
g_next_life_bonus_10000s_BCD      = $D2FD+SMS_RAM
g_level_header_copy               = $D354+SMS_RAM   ; ($28)
g_object_ptrs                     = $D37C+SMS_RAM   ; (64)
object_list                       = $D3FC+SMS_RAM   ; 32 sloty x 26 B, slot 0 = Sonic

OBJ_SIZE     = 26
N_OBJECTS    = 32

; pola rekordu obiektu (26 B, offset od IX); pozycje i predkosci 24-bitowe: subpiksel, piksel lo, piksel hi
OB_TYPE      = 0           ; typ obiektu (indeks LUT_object_functions), $FF = slot pusty
OB_X         = 1           ; X: +1 subpiksel, +2 lo, +3 hi
OB_Y         = 4           ; Y: +4 subpiksel, +5 lo, +6 hi
OB_VX        = 7           ; Vx: +7 sub, +8 lo, +9 hi (ze znakiem)
OB_VY        = 10          ; Vy: +10 sub, +11 lo, +12 hi (ze znakiem)
OB_W         = 13          ; szerokosc (px) - punkt testu kolizji poziomej / pionowej
OB_H         = 14          ; wysokosc (px)
OB_SPRITE    = 15          ; (2) sprite string (0 = nie rysowac)
OB_FLAGS     = 24          ; b7 na ziemi, b6 kolizja pozioma, b5 bez kolizji z mapa, b4 pod woda

; rekord Sonica (object_list, slot 0) - adresowanie absolutne (plan-m3 3.4); nazwy wg dezasemblacji
sonic_x_sub                       = $D3FD+SMS_RAM
sonic_x                           = $D3FE+SMS_RAM   ; (2) piksele lo, hi
sonic_y_sub                       = $D400+SMS_RAM
sonic_y                           = $D401+SMS_RAM   ; (2)
sonic_vel_x_sub                   = $D403+SMS_RAM
sonic_vel_x                       = $D404+SMS_RAM   ; piksele lo
sonic_vel_x_hi                    = $D405+SMS_RAM
sonic_vel_y_sub                   = $D406+SMS_RAM
sonic_vel_y                       = $D407+SMS_RAM
sonic_vel_y_hi                    = $D408+SMS_RAM
sonic_width_ix_13                 = $D409+SMS_RAM
sonic_height_ix_14                = $D40A+SMS_RAM
sonic_spritemap_ix_15             = $D40B+SMS_RAM   ; (2) adres SMS mapy sprite'ow (0 = nie rysowac)
sonic_anim_ptr_ix_17              = $D40D+SMS_RAM   ; (2) adres SMS sekwencji animacji
sonic_anim_sprite_subindex_ix_19  = $D40F+SMS_RAM   ; pozycja w sekwencji animacji
sonic_anim_index_ix_20            = $D410+SMS_RAM   ; numer animacji (LUT_sonic_anim_ptrs)
sonic_speed_shoes_ix_21           = $D411+SMS_RAM   ; licznik speed shoes (0 = brak)
sonic_brake_sound_cooldown_timer_ix_22 = $D412+SMS_RAM
sonic_flags_ix_24                 = $D414+SMS_RAM   ; b0 toczenie, b1 w lewo, b2 w powietrzu po skoku/toczeniu,
                                                    ; b3 przycisk skoku zwolniony, b4 pod woda, b5 bez kolizji,
                                                    ; b6 kolizja pozioma, b7 na ziemi

; zmienne logiki Sonica (M3.3)
g_next_avail_vdp_sprite_ptr       = $D23C+SMS_RAM   ; (2) renderer SMS (draw_sprite)
g_sonic_x_speed_cap_subpx         = $D240+SMS_RAM   ; (2) limit predkosci X (sub, lo)
g_sonic_y_jump_velocity           = $D242+SMS_RAM   ; (2) predkosc skoku (sub, lo; hi = $FF)
g_sonic_y_gravity_acceleration    = $D244+SMS_RAM   ; (2) grawitacja (sub, lo)
g_level_limit_x1                  = $D275+SMS_RAM   ; (2)
g_level_limit_y1                  = $D279+SMS_RAM   ; (2)
g_teleport_start_countdown_timer  = $D28A+SMS_RAM
g_chaos_emerald_music_countdown_timer = $D28B+SMS_RAM
g_directional_input_suppression_timer = $D28C+SMS_RAM
g_invincibility_countdown_timer   = $D28D+SMS_RAM
g_sonic_jump_countdown_timer      = $D28E+SMS_RAM
g_new_sonic_sprite_ptr            = $D28F+SMS_RAM   ; (2) adres grafiki klatki Sonica (bank 8+ SMS)
g_sonic_bored_anim_countup_timer  = $D299+SMS_RAM   ; (2)
g_screen_tile_replace_y           = $D2AD+SMS_RAM   ; (2)
g_screen_tile_replace_data_ptr    = $D2AF+SMS_RAM   ; (2)
g_sonic_flags_copy                = $D2B9+SMS_RAM
g_UNUSED_last_sonic_ground_y      = $D2D9+SMS_RAM   ; (2)
g_sonic_prev_anim_idx             = $D2DF+SMS_RAM
g_sonic_x_speed_dependent_anim_subframe = $D2E0+SMS_RAM
g_special_stages_attempted        = $D281+SMS_RAM   ; M6.5
g_special_stages_completed        = $D282+SMS_RAM
g_special_stage_ring_bonus_mult_hi = $D285+SMS_RAM ; mnoznik premii za pierscien (binarnie; hi do D, lo do E w add_CHL_points)
g_special_stage_ring_bonus_mult_lo = $D286+SMS_RAM
g_special_stage_round_bumper_cooldown_timer = $D2E1+SMS_RAM
g_special_stage_round_bumper_anim_sprite_x = $D2E2+SMS_RAM   ; M6.5 (2 B)
g_special_stage_round_bumper_anim_sprite_y = $D2E4+SMS_RAM   ; (2 B)
g_sonic_bounce_vel_y_sub          = $D2E6+SMS_RAM   ; (3) sub, lo, hi
g_sonic_sprite_index_override     = $D302+SMS_RAM
g_ring_sparkle_sprite_x           = $D31D+SMS_RAM   ; (2)
g_ring_sparkle_sprite_y           = $D31F+SMS_RAM   ; (2)
g_ring_sparkle_sprite_countdown_timer = $D321+SMS_RAM
g_committed_rompage_2             = $D236+SMS_RAM   ; kopia rompage_2 (bank slotu 2) w RAM
g_current_music                   = $D2D2+SMS_RAM   ; numer grajacego utworu (rst $18)
g_sonic_consume_air_bubble_countdown_timer = $D2FB+SMS_RAM ; M6.8: ticki polykania babla (iy_08 b2)
g_level_music                     = $D2FC+SMS_RAM   ; utwor poziomu
g_sfx_req_TEST                    = $DBFF+SMS_RAM   ; M5.4 (tylko port i referencja testow): efekt zgloszony w ticku
                                                    ; ($FF brak); $DBxx oryginal nie uzywa - referencja wpisuje go w Lua
tmp_04                            = $D212+SMS_RAM
tmp_07                            = $D215+SMS_RAM
; M3.7: smierc, czas gry, restart poziomu, HUD
g_sonic_died_at_least_once        = $D283+SMS_RAM
g_signpost_tickdown_counter       = $D289+SMS_RAM   ; tablica konca poziomu / koniec czasu w etapie specjalnym
g_pal_flash_countdown_timer       = $D2B1+SMS_RAM
g_pal_flash_idx                   = $D2B2+SMS_RAM   ; M6.4: indeks koloru migotania (b7: paleta sprite'ow)
g_pal_flash_color_value           = $D2B3+SMS_RAM   ; kolor migotania (--BBGGRR)
g_boss_hits_taken                 = $D2EC+SMS_RAM   ; M6.4: trafienia bossa
g_boss_death_next_explosion_countdown_timer = $D2ED+SMS_RAM ; licznik do nastepnego wybuchu bossa
g_boss_death_explosions_done_then_countup_timer = $D2EE+SMS_RAM ; wybuchy bossa, potem licznik do lotu
g_HUD_FFstr_buf                   = $D2BE+SMS_RAM   ; (5) tekst HUD-u (kafle, $FF = koniec)
g_time_secs_BCD                   = $D2CF+SMS_RAM
g_time_subsecs                    = $D2D0+SMS_RAM   ; 0-59 (binarnie)
g_water_level_onscreen_y          = $D2DB+SMS_RAM
; M4.1: obiekty
g_prev_sprite_count               = $D2B4+SMS_RAM   ; licznik sprite'ow wyslanych w poprzednim IRQ
g_random_seed                     = $D2D7+SMS_RAM   ; (2) ziarno random_A (00:0625)
g_score_BCD                       = $D2BA+SMS_RAM   ; (4) wynik BCD big endian (D2BA najstarszy)
g_frontmost_sprite_table_offs     = $D2DE+SMS_RAM
g_level_has_checkpoint_mask       = $D311+SMS_RAM   ; (6) bit poziomu: start od punktu kontrolnego
; M4.5: monitory, szmaragd, iskry niesmiertelnosci
g_chaos_emeralds_collected        = $D27F+SMS_RAM   ; liczba szmaragdow
g_level_lives_collected           = $D280+SMS_RAM   ; zycia z monitorow (poziomy < $1C)
g_current_signpost                = $D288+SMS_RAM   ; M4.8: nagroda tabliczki (1 nic, 2 zycie, 3 pierscienie, 4 etap specjalny)
g_invincibility_sparkle_position_buffer_0 = $D2F3+SMS_RAM ; (4) przesuniecie x, y iskry (slowa)
g_invincibility_sparkle_position_buffer_1 = $D2F7+SMS_RAM ; (4)
g_level_lives_collected_mask      = $D305+SMS_RAM   ; (6) bit poziomu: monitor zycia zebrany
g_level_has_emerald_mask          = $D30B+SMS_RAM   ; (6) bit poziomu: szmaragd zebrany
g_level_button_toggled_on_mask    = $D317+SMS_RAM   ; (6) bit poziomu: przycisk wlaczony (LAB1)
g_per_level_checkpoint_positions  = $D32E+SMS_RAM   ; (2 * poziom) pozycja startu od punktu kontrolnego (bloki)
