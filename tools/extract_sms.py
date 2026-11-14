#!/usr/bin/env python3
"""Ekstrakcja zasobów poziomu z ROM-u Sonic the Hedgehog (SMS) dla portu Sonic A8 VBXE.

Wejście: ROM SMS (SHA-256 6ad73896…a2458b, domyślnie assets/rom/sms/*.sms – poza repozytorium).
Wyjście (build/assets/<nazwa>/):
  level.png        – podgląd całego poziomu (indeksy palety tła), do kontroli wzrokowej
  level_prio.png   – podgląd: bloki z priorytetem nad obiektami zaznaczone
  bank_atlas.bin   – 16 KiB: 256 kafli 8x8, 8 bpp (bajt = indeks koloru 0..15), kafel t pod t*64
  bank_level.bin   – 16 KiB: mapowanie bloków, flagi priorytetu, palety, układ (stride 256), kulka testowa
  level.inc        – stałe MADS (wymiary, granice kamery, liczba bloków, adresy w banku)
  level.npz        – dane dla testów porównawczych (tools/m2_compare.py)

Formaty ustalone na podstawie kodu Z80 gry (dezasemblacja s1smsdisasm-gm użyta wyłącznie jako materiał
referencyjny, bez kopiowania kodu) i zweryfikowane renderem całego poziomu – opis w docs/sms-formaty.md.
"""
from __future__ import annotations

import argparse
import hashlib
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ROM_SHA256 = "6ad738965ece231427ee046b9905cfee470d5c01220afdd934da4673e4a2458b"
ROM_DIR = ROOT / "assets" / "rom" / "sms"


def _znajdz_rom() -> Path:
    """Pierwszy *.sms w assets/rom/sms o oczekiwanym SHA-256 (dowolna nazwa pliku); brak - nazwa domyślna."""
    for p in sorted(ROM_DIR.glob("*.sms")) if ROM_DIR.is_dir() else []:
        if hashlib.sha256(p.read_bytes()).hexdigest() == ROM_SHA256:
            return p
    return ROM_DIR / "Sonic The Hedgehog (USA, Europe, Brazil) (En).sms"


DEFAULT_ROM = _znajdz_rom()

HEADER_TABLE = 0x15580          # 05:5580 – słowa: offset nagłówka względem tej tablicy
HEADER_SIZE = 37
TILEFLAGS_PTRS = 0x3A65         # 00:3A65 – 8 wskaźników (bank 0) na tablice flag bloków
PAL3_PTRS = 0x627C              # 01:627C – 8 wskaźników na palety startowe (tło + sprite'y)
WATER_PAL = 0x024B              # 00:024B PAL2_lv_lab_under_water (32 B) - M6.8
WATER_PAL3 = 0x026B             # 00:026B PAL2_lv_lab_3_under_water (LAB3: iy_07 b4)
PALCYC_PTRS = 0x628C            # 01:628C – 9 wskaźników na palety cykliczne tła (LUT_PAL1_cycles; indeks = nagłówek +$1D, 00:22B4)
SKY1_LIGHTNING = (0x649E, 0x64DE)   # M6.10: 01:649E / 01:64DE LVCYCPAL1_SKY_1B / _1C - zestawy palet cyklu błyskawic SKY1 (00:1F49)
SKY_STASH = (0x3F00, 0x0F00)    # M6.10: bank SKY3 - kopie bloku na poziom (LB_HDR..+$FF): SKY3, pod-poziom $1A (game_code.asm lv_select)

LEVELS = {"ghz1": 0, "ghz2": 1, "ghz3": 2, "bri1": 3, "bri2": 4, "bri3": 5, "sp1": 0x1C, "sp2": 0x1D, "sp3": 0x1E, "jun1": 6, "jun2": 7, "jun3": 8,
          "sp5": 0x20, "sp6": 0x21, "sp7": 0x22,   # M6.11: etapy specjalne 5-7 (uklad, bloki i atlas jak $1C-$1E - kopie bloku w banku 63)
          "sp4": 0x1F, "sp8": 0x23,                # M6.11: etapy 4 i 8 (pionowe 16 x 256, flipper $4C) - bank 32
          "lab1": 9, "lab2": 10, "lab3": 11,   # M6.6: Bridge = g_level 3-5; M6.7: Jungle 6-8; M6.8: Labyrinth 9-11
          "sbz1": 12, "sbz2": 13, "sbz3": 14, "sbz2a": 0x14, "sbz2b": 0x15,   # M6.9: Scrap Brain 12-14 i pod-poziomy SBZ2 $14, $15 (docs/plan-m6.md 14.1)
          "sky1": 15, "sky2": 16, "sky3": 17}   # M6.10: Sky Base 15-17 (pod-poziom $1A = kopia bloku w banku SKY3; docs/plan-m6.md 15.1)

# stan startowy poziomu dla M3 (load_and_init_level_from_header 00:20CB, update_demo_inputs 00:1BAD)
HEADER_COPY = 0x28              # tyle bajtów nagłówka kopiuje gra do g_level_header_copy (ldir $28)
STAGE_START_TIME = 0x23FF       # 00:23FF LUT_normal_stage_start_time (3 B: min, s, ramki)
CHECKPOINT_TIME = 0x2402        # 00:2402 LUT_bonus_stage_time_limits: czas startu od punktu kontrolnego (00:21AE)
BONUS_TIME = 0x2405             # 00:2405 LUT_bonus_stage_time_limits_offs_01: czas etapu specjalnego, 3 B (min, s, ramki) na poziom od $1C
DEMO_INPUTS = 0x1BC6            # 00:1BC6 ARRAY_demo_inputs (131 B; kopiujemy 256 B jak indeksuje gra)

# ruch i kolizje obiektów (M3.2, return_from_objfunc 00:32E2): adresy CPU SMS przy rompage_1 = 1, rompage_2 = 2
# (jak w pętli poziomu przed draw_HUD_sprites); indeks tablic = flagi bloku & $3F (0..63), więc bierzemy po 64
# pozycje - gra czyta też poza 47 zdefiniowanymi (np. magnes Y wychodzi z banku 0 na początek banku 1)
LUT_VERTICAL_HSLIDE = 0x3F90    # 00:3F90 LUT_vertical_hslide_factors
LUT_HORIZONTAL_VSLIDE = 0x3FBF  # 00:3FBF LUT_horizontal_vslide_factors_VESTIGIAL
LUT_Y_MAGNET = 0x3FF0           # 00:3FF0 LUT_y_magnet_factors
LUT_PUSH = [0x4020, 0x411E, 0x41EC, 0x448A]   # 01:LUT_phys_tileflags_push_right/left/down/up (wskaźniki)
PHYS_ATARI = 0xC000             # obraz tablic w RAM pod OS (src/kernel/mem.inc: PHYS_RAM)
PHYS_PROFILES = 0x300           # profile 32 B od PHYS_ATARI + $300

# logika Sonica (M3.3, objfunc_00_sonic 01:48C8): obraz 1 KiB dla RAM pod OS $F000 (src/kernel/mem.inc: SONIC_RAM)
SONIC_PHYSICS = 0x4DCB          # 01:4DCB @sonic_physics_main/_special_stage_airborne/_underwater/_speed_shoes (4 x 9 B)
SONIC_SPECIALS = 0xB9ED         # 0F:B9ED tablica wskaźników (względnych) tablic bloków specjalnych stref (bank 15)
SONIC_ANIM_FROM = 0x591D        # 01:591D SPRITEMAP_sonic_*, LUT_sonic_anim_ptrs (01:5965), sekwencje animacji
SONIC_ANIM_TO = 0x5B09          # 01:5B09 objfunc_01_monitor_rings (koniec danych Sonica)
LUT_RING_MAP = 0x23F9           # 00:23F9 LUT_ring_tile_index_map (6 B: indeks animacji -> klatka grafiki)
RING_ART = 0x7CF0               # 0B:7CF0 grafika pierścienia: 6 klatek x 4 kafle ($FC-$FF) x 32 B (rompage_1 = $0B)
RING_ART_BANK = 0x0B
# M3.6 grafika Sonica: g_new_sonic_sprite_ptr = $4000 (w prawo) / $7000 (w lewo) + klatka * $120 przy bankach
# 8/9 w slotach 1/2 (IRQ 00:012D) - ciągły ROM od $20000; update_sonic_3bpp_sprite (00:37E0) wgrywa 12 kafli
# 3 bpp (3 B na wiersz, 4. bitplan = 0) do kafli sprite'ów $B4-$BF; mapa SPRITEMAP_sonic_normal 3x2 sprite'y 8x16
SONIC_ART_RIGHT = 0x20000
SONIC_ART_LEFT = 0x23000
SONIC_FRAME_BYTES = 0x120
SONIC_FRAMES = 42               # $4000 + 42 * $120 < $7000 (animacje używają klatek 0-38, osłona $18)
SPR_COMMON_ART = 0x24000 + 0xB92E   # ART_09_B92E: wspólne kafle sprite'ów (HUD, iskra, ...) -> VRAM $3000 (kafle $80+),
                                    # load_and_init_level_from_header 00:2172, przed grafiką sprite'ów z nagłówka

# M4.0 obiekty GHZ (docs/plan-m4.md). Bank 1 ROM-u jest w pętli poziomu w slocie 1 ($4000-$7FFF), a bank 45 Atari
# w oknie $4000-$7FFF - dane obiektów leżą w banku 45 pod tymi samymi adresami co w ROM-ie, więc adresy SMS
# zapisywane przez obiekty w RAM (mapa sprite'ów +15/+16, wskaźniki sekwencji) działają w porcie bez tłumaczenia;
# kod 6502 obiektów wypełnia luki między zakresami (OD_* w objdata.inc). Zakresy: (adres SMS, długość, zawartość)
OBJ_SPANS = [
    (0x5BBF, 0x5BD9 - 0x5BBF, "SPRITEMAP_monitor_noise, SPRITEMAP_monitor_unnoisy_surrounds"),
    (0x5F10, 0x5F17 - 0x5F10, "SPRITEMAP_monitor_image (szmaragd $06)"),
    (0x6157, 0x627C - 0x6157, "tabliczka $07: signpost_anim_* (6), SPRITEMAP_signpost, PAL2_signpost (01:626C)"),
    (0x66C5, 0x673C - 0x66C5, "Crabmeat $08: LUT_crabmeat_state_sequence, _state_anim_ptrs, crabmeat_anim_*, "
                              "SPRITEMAP_crabmeat_frames"),
    (0x682F, 0x693F - 0x682F, "wahadło $09: LUT_swing_xy_table; SPRITEMAP_platform_GHZ/JUN/BRI ($09, $0B, $0F)"),
    (0x69B7, 0x69E9 - 0x69B7, "eksplozja $0A: LUT_explosion_state_sequence, SPRITEMAP_explosion_frames"),
    (0x6B70, 0x6B74 - 0x6B70, "kula ognia $0D: LUT_fireball_main, LUT_fireball_BRI3_LAB3 (kafle)"),
    (0x6CD7, 0x6D65 - 0x6CD7, "Buzz Bomber $0E: sekwencja stanów, wskaźniki animacji, animacje, "
                              "SPRITEMAP_buzz_bomber_frames"),
    (0x6E96, 0x6F08 - 0x6E96, "Motobug $10: sekwencja stanów, wskaźniki animacji, animacje, SPRITEMAP_motobug_frames"),
    (0x7B5D, 0x7B95 - 0x7B5D, "kwiaty $50: dane łaty kafli (01:7B5D, 01:7B85)"),
    (0x7C17, 0x7C41 - 0x7C17, "rozsypane pierścienie $55: PTRTAB_thrown_ring_spriteptrs_and_sonicarts, "
                              "SPRITEMAP_thrown_ring_*"),
    # M6.4 GHZ3: boss $12, kapsuła $25, zwierzęta $24 / $23
    (0x7261, 0x732C - 0x7261, "boss GHZ3 $12: LUT_GHZ3boss_* (prędkości Y, sekwencje, kierunki), SPRTAB_GHZ3boss_facing_*, "
                              "PAL2_boss (01:731C)"),
    (0x750E, 0x7594 - 0x750E, "kapsuła zwierząt $25: profil górnej krawędzi, SPRITEMAP_animal_capsule_*, dane łat kafli"),
    (0x7629, 0x7699 - 0x7629, "zwierzę $24: animal_1_anim_*, SPRITEMAP_animal_1"),
    (0x7752, 0x77BE - 0x7752, "zwierzę $23: SPRITEMAP_animal_0_*"),
    (0x7922, 0x79FA - 0x7922, "boss: SPRTAB_boss_generic_fly_out"),
    # M6.6 Bridge: Chopper $26 (kod w banku 45, luka 16)
    (0x7DDC, 0x7E02 - 0x7DDC, "Chopper $26: LUT_chopper_anim_sequence, SPRITEMAP_chopper_normal / _emerging"),
    # M6.7 Jungle: mapy sprite'ow obiektow z banku 1 (kod w banku obiektow strefy, mapy czyta obj_draw z banku 45)
    (0x6FED, 0x700C - 0x6FED, "Newtron $11: SPRITEMAP_newtron"),
    (0x7E89, 0x7E9B - 0x7E89, "platforma $27: SPRITEMAP_platform_downwards_tall"),
    (0x7ED9, 0x7EE6 - 0x7ED9, "platforma $28: SPRITEMAP_platform_downwards_wide"),
]
# M6.6 Bridge: obiekty $2D, $2E, $3B, $48, $4E leza w banku 2 ROM-u (SMS $8000-$BFFF; slot 2 w petli obiektow). Port trzyma
# je w banku obiektow strefy PB_OBJZ (bank 11, okno $4000-$7FFF): dane pod adresem SMS - $4000, kod w lukach (OZ_GAP*).
# Wskazniki w rekordach obiektow zostaja wartosciami SMS ($8000+), wiec obraz slotow jest bajt w bajt jak w oryginale.
OBJZ_OFF = 0x4000
STORE_SLOTS = 184               # M6.9: sloty magazynu blokow w VRAM ($40000 + s * 1 KB do SONIC_VRAM $6E000; render/vram.inc)
OBJZ_SPANS = [
    (0x8374, 0x83C1 - 0x8374, "Spikeses $2D: LUT_spikeses_anim_sequence_left / _right, SPRTAB_spikeses"),
    (0x8481, 0x8496 - 0x8481, "spadajacy element mostu $2E: SPRTAB_falling_bridge_piece, UNK_0848E (dane lat kafli: 8 zer)"),
    (0x8632, 0x866C - 0x8632, "boss BRI3 $48: LUT_BRI3_boss_entrances, _pallet_velocities_left / _right, SPRTAB_BRI3_boss"),
    (0x8830, 0x8837 - 0x8830, "huśtawka $4E: LUT_sprite_platform, LUT_sprite_weight"),
    (0xB5B5, 0xB5C2 - 0xB5B5, "platforma $3B: SPRTAB_platform_y_oscillate_BRI"),
    # M6.7 Jungle
    (0x8019, 0x8053 - 0x8019, "klada $29: OFFSTAB_log_frame_offsets, SPRITEMAP_log (3 klatki)"),
    (0x81F4, 0x8218 - 0x81F4, "boss JUN3 $2C: SPRTAB_JUN3_boss_facing_left / _right"),
    (0x82C1, 0x82E6 - 0x82C1, "bomba JUN3 $2B: sekwencje animacji, SPRTAB_JUN3_boss_bomb"),
    (0xA3BB, 0xA3F8 - 0xA3BB, "bomba JUN3 $2B: SPRTAB_ballhog_bomb (klatki eksplozji)"),
    # M6.8 Labyrinth (krok 0: tylko dane; kod obiektow w lukach banku 11 - kroki 3, 5-7). Kod Bridge i Jungle przeniesiony do luk
    # OZ_GAPA4 i OZ_GAPA21, bo stal na miejscu tych zakresow (wskazniki map ix+15/16 czyta objz_mapcopy pod adresem SMS - $4000)
    (0x88B4, 0x88FB - 0x88B4, "Jaws $3C: LUT_jaws_anim_sequence_right / _left, SPRTAB_jaws"),
    (0x8987, 0x8AF6 - 0x8987, "kula z kolcami $3D: SPRTAB_spinning_spike_ball, LUT_spinning_spike_ball_xy_positions (180 par)"),
    (0x8BBC, 0x8C16 - 0x8BBC, "włócznia $3E: LUT_inc_00_through_07, _dec_07_through_00, _stay_at_00 / _08, "
                              "LUT_giant_spear_anim_frames_n_y"),
    (0x8D39, 0x8D48 - 0x8D39, "gargulec $3F: SPRTAB_gargoyle_fireball_left / _right"),
    (0x8E16, 0x8E56 - 0x8E16, "linia wody $40: LUT_waterline_onscreen_x_positions, LUT_waterline_y_vel_steps"),
    (0x8EB6, 0x8ECA - 0x8EB6, "źródło bąbli $41: LUT_air_bubble_spawner_anim_xy, _initial_chance"),
    (0x9045, 0x90C0 - 0x9045, "Burrobot $44: LUT_burrobot_anim_sequence_walk / _jump (4), SPRTAB_badnik_burrobot"),
    (0x91DE, 0x91EB - 0x91DE, "platforma wypływająca $45: SPRTAB_LAB_float_up_platform"),
    (0x9257, 0x9267 - 0x9257, "spawn_bubble: LUT_bubble_type_select"),
    (0x947B, 0x94A5 - 0x947B, "boss LAB3 $49: LUT_LAB3_boss_entrance_positions_xy, _target_y_ / _exit_y_positions, SPRTAB_LAB3_boss"),
    (0x9688, 0x96A8 - 0x9688, "rakieta bossa LAB3 $2F: SPRTAB_LAB3_boss_rocket_right / _left"),
    (0x96F5, 0x96F8 - 0x96F5, "dym rakiety $2A: LUT_LAB3_boss_rocket_puff_anim_sprites"),
    (0xA48B, 0xA4AB - 0xA48B, "przycisk $1D: SPRTAB_floorbutton_SCR_down / _up, SPRTAB_floorbutton_LAB_down / _up"),
    (0xB031, 0xB0F4 - 0xB031, "Orbinaut $35: LUT_orbinaut_ball_xy_positions (164 B), SPRTAB_orbinaut_base_left / _right"),
]
# M6.9: drugi bank obiektow strefy PB_OBJZ2 (bank 2, wspolny dla Scrap Brain, Sky Base, poziomu $12 i etapow $1F-$23 - docs/plan-m6.md
# 14.6, 15.3): dane banku 2 ROM-u, ktore w banku 11 wypadaja na kodzie BRI/JUN/LAB. Ten sam uklad co PB_OBJZ (adres okna = SMS - $4000),
# kod w lukach OZ2_GAP*; oz_tab pod tym samym adresem co w banku 11 (objz_call czyta go po wlaczeniu v_pbobjz).
OBJZ2_SPANS = [
    (0x9BD9, 0x9BE8 - 0x9BD9, "korytarz $13: LUT_corridor_data (5 x bx, by, poziom)"),
    (0x9C69, 0x9C70 - 0x9C69, "miotacz ognia w prawo $14: SPRTAB_SCR_flamer_right"),
    (0x9C87, 0x9C8E - 0x9C87, "miotacz ognia w lewo $15: SPRTAB_SCR_flamer_left"),
    (0x9D4A, 0x9DFA - 0x9D4A, "plomien z sufitu $16: PTRLUT_ceiling_flamer (16 slow - adresy SMS), wysokosci, pary kafel/dy"),
    (0x9F2B, 0x9F62 - 0x9F2B, "drzwi z lewej $17: SPRTAB_SCR_door_open_on_left"),
    (0x9FEE, 0xA025 - 0x9FEE, "drzwi z prawej $18: SPRTAB_SCR_door_open_on_right"),
    (0xA0B1, 0xA0E8 - 0xA0B1, "drzwi obustronne $19: SPRTAB_SCR_door_open_on_both_sides"),
    (0xA167, 0xA1AA - 0xA167, "zapper $1A: sekwencje animacji, SPRTAB_SCR_zapper"),
    (0xA2D2, 0xA33C - 0xA2D2, "Ballhog $1B: sekwencje animacji, SPRTAB_badnik_ballhog"),
    (0xA3B1, 0xA3F8 - 0xA3B1, "bomba Ballhoga $1C: sekwencja, SPRTAB_ballhog_bomb (w banku 11 kopia dla bomby JUN3)"),
    (0xA48B, 0xA4AB - 0xA48B, "przycisk $1D: SPRTAB_floorbutton_SCR / _LAB (kopia z banku 11)"),
    (0xA51A, 0xA551 - 0xA51A, "drzwi z przycisku $1E: SPRTAB_SCR_door_from_button"),
    (0xA6B9, 0xA7ED - 0xA6B9, "Caterkiller $1F: tablice dX lewo / prawo, Y, offsety X, mapy"),
    (0xA9B7, 0xA9C7 - 0xA9B7, "scenka SBZ3 $22: sekwencje animacji Robotnika"),
    (0xBAF9, 0xBB65 - 0xBAF9, "mapy Robotnika (SBZ3 $22 i boss SKY3 $4A)"),
]
# M6.10: trzeci bank obiektow strefy PB_OBJZ3 (bank 30, Sky Base; potem poziom $12 i etapy $1F-$23 - docs/plan-m6.md 15.3): w banku 2 kod SKY
# (ok. 5,4 KB) rozpadlby sie na kilkanascie luk miedzy danymi SBZ i SKY. Tu tylko dane SKY (i korytarza $13) - kod SKY w luce
# $4000-$5BD9 (do LUT_corridor_data), dalej M6.11. Uklad jak PB_OBJZ2.
OBJZ3_SPANS = [
    (0x9BD9, 0x9BE8 - 0x9BD9, "korytarz $13 (kopia kodu z banku 2): LUT_corridor_data (SKY2 -> $1A)"),
    (0xAA63, 0xAA6A - 0xAA63, "chmura $30: SPRTAB_moving_cloud"),
    (0xAB01, 0xAB21 - 0xAB01, "smiglo SKY2 $31: PTRTAB_SKY2_propeller_sprites_xyn i klatki"),
    (0xACF1, 0xAD6C - 0xACF1, "Bomb $32: sekwencje animacji, SPRTAB_badnik_bomb_normal / _exploding"),
    (0xADFD, 0xAE35 - 0xADFD, "armata SKY2 $33: LUT_SKY2_cannon_shot_puff, SPRTAB_SKY2_cannon_shot_puff"),
    (0xAE81, 0xAE88 - 0xAE81, "pocisk armaty $34: SPRTAB_SKY2_cannon_shell"),
    (0xB031, 0xB0F4 - 0xB031, "Orbinaut $35 (kopia z banku 11): LUT_orbinaut_ball_xy_positions, SPRTAB_orbinaut_base_left / _right"),
    (0xB227, 0xB297 - 0xB227, "obrotowe dzialo $37: LUT_SKY2_turning_gun_sprite_info, _bullet_directions"),
    (0xB37B, 0xB398 - 0xB37B, "platforma SKY $38 / $3B: SPRTAB_SKY_platform, LUT_SKY_platform_right_propeller_sprites"),
    (0xB45B, 0xB46D - 0xB45B, "sciana kolcow $39: SPRTAB_SKY2_spike_wall_right"),
    (0xB4E6, 0xB50E - 0xB4E6, "stale dzialo $3A: LUT_SKY_fixed_gun_dir_setup"),
    (0xBA1C, 0xBB84 - 0xBA1C, "boss SKY3 $4A: animacje, przycisk, LUT_SKY3_boss_glass_crack_tile_anim, mapy Robotnika (= scenka SBZ3)"),
    (0xBCC7, 0xBCDF - 0xBCC7, "zappery SKY3 $46: LUT_SKY3_vertical_zapper_vzap_sprites, _track_ball_sprites"),
    (0xBDC7, 0xBDF9 - 0xBDC7, "kula elektryczna $47: LUT_SKY3_electric_ball_anim, SPRTAB_SKY3_electric_ball"),
    # review M6.10: Bomb $32 - do_framed_animation (01:7C41) nie zeruje (ix+22/23) przy zmianie sekwencji, a sekwencje leza jedna za druga:
    # przejscie chodzenie -> stanie przy indeksie 4 czyta klatke $20 ($ACFA), kaskada dalej klatke $0A - mapy $AD0B + klatka * 18
    (0xAF4B, 0x12, "Bomb $32: mapa klatki $20 (bajty kodu 02:AF4B - oryginal rysuje z nich sprite'y)"),
    (0xADBF, 0x12, "Bomb $32: mapa klatki $0A"),
    # M6.11: obiekty etapow specjalnych $1C-$23 (flipper $4C, odbijacz $21) i poziomu koncowego $12 (kontroler $53, szmaragd $54)
    (0x999E, 0x9AAF - 0x999E, "flipper $4C: LUT_flipper_y_offsets_00..02, LUT_flipper_y_vel_additions_01/02, SPRTAB_flipper_00..02"),
    (0x9B6E, 0x9B75 - 0x9B6E, "odbijacz SS $21: SPRTAB_special_stage_bouncer"),
    (0xBF21, 0xBF4C - 0xBF21, "kontroler konca $53: SPRTAB_end_controller_start_flying / _exploding"),
    (0xBFF1, 0xBFF8 - 0xBFF1, "szmaragd konca $54: SPRTAB_end_chaos_emerald"),
]
OBJ_BOUNDS = 0x2BA2             # 00:2BA2 LUT_object_offscreen_activation_bounds: 86 typów x 8 B (słowa L, R, T, B)
OBJ_TYPES = 86                  # LUT_object_functions 00:2AF6 - typy $00-$55 (aktywacja: typ >= $56 -> wskaźnik 0)
OBJ_FUNCS = 0x2AF6              # 00:2AF6 LUT_object_functions (86 słów; $4D i $4F = ENTRY_RESET)
OBJ_BOUNDS_ATARI = 0x700C       # granice aktywacji w banku 45: M6.7 - tylko unikalne wiersze po 8 B (OBJ_BOUNDS_UNIQ), adres wiersza typu w oa_blo/oa_bhi (objbounds.inc)
OBJ_BOUNDS_UNIQ = 40            # liczba unikalnych wierszy granic ze 86 typow (kontrola w bounds_unique)
MONART = 0x15180                # 05:5180 ikony monitorów: 8 x 128 B (4 kafle 4 bpp: $5C $5D lewa kolumna, $5E $5F
                                # prawa), write_partial_monitor_art 00:0C1D wysyła po 8 B na tick pod VRAM $2B80
MONART_N = 8
SIGNPOST_ART = 0x28294          # ART_09_4294 (HY): grafika tabliczki pod kafle sprite'ów $00-$7F (load_art 01:5F2E…)
SIGNPOST_PAL = 0x626C           # 01:626C PAL2_signpost (16 B, paleta sprite'ów)
BOSS_ART = 0x24000 + 0xAEB1      # ART_09_AEB1 (HY): grafika bossa GHZ3 pod kafle sprite'ów $00-$7F (objfunc_12 01:7031)
CAPS_ART = 0x30000 + 0xDA28      # ART_0C_DA28 (HY): zwierzęta i kapsuła (boss_generic_update_8hp 01:7916)
ROBO_ART = 0x30000 + 0xEF3F      # M6.9: ART_0C_EF3F (HY): Robotnik (scenka SBZ3 $22 02:A816, zappery SKY3 $46) - bank sprite'ow strefy $0000 (4 bpp)
BOSS3_ART = 0x30000 + 0xE508     # ART_0C_E508 (HY): grafika bossa BRI3 (objfunc_48 02:8496) - M6.6; w banku 47 pod OBJART_BOSS3 (4 bpp, jak bank 59)
BOSS_PAL = 0x731C                # 01:731C PAL2_boss (16 B, paleta sprite'ów)
SS_ART = 0x24000 + 0xA511        # ART_09_A511 (HY): kafle sprite'ów etapów specjalnych ($1C-$23, nagłówek: bank 9 + $A511)
SS_PAL_IDX = 7                   # indeks palety etapów specjalnych w PAL3_PTRS (paleta tła 16 + sprite'ów 16 kolorów)
OBJART_ICONS = 0x0000           # bank 47: ikony 8 x 4 kafle x 64 B (8 bpp, kolor + 16, 0 = przezroczysty)
OBJART_SIGN = 0x0800            # bank 47: kafle tabliczki 8 bpp (kolor + 16), do 128 x 64 B
OBJART_SIGNPAL = 0x2800         # bank 47: paleta tabliczki RGB 16 x 3 B
OBJART_BOSS3 = 0x3000           # bank 47: grafika bossa BRI3 (ART_0C_E508, 128 kafli 4 bpp, 2 piksele/bajt; M6.6)


def draw_reads(rom: bytes, addr: int) -> list[int]:
    """Adresy bajtów mapy sprite'ów czytanych przez draw_sprite_string (00:350F) dla mapy pod addr: do 3 wierszy
    po 6 bajtów, $FF na początku wiersza kończy (wiersze pominięte przy odcinaniu też przesuwają wskaźnik o 6)."""
    out = []
    for r in range(3):
        a = addr + 6 * r
        out.append(a)
        if sms_read(rom, a, 1)[0] == 0xFF:
            break
        out += range(a + 1, a + 6)
    return out


def bounds_unique(rom: bytes) -> tuple[list[bytes], list[int]]:
    """Granice aktywacji (86 typow x 8 B: slowa L, R, T, B) bez powtorzen: (unikalne wiersze w kolejnosci pierwszego uzycia,
    indeks wiersza dla kazdego typu). M6.7: 40 wierszy = 320 B zamiast 688 B."""
    b = rom[OBJ_BOUNDS:OBJ_BOUNDS + 8 * OBJ_TYPES]
    wiersze: list[bytes] = []
    idx = []
    for t in range(OBJ_TYPES):
        r = b[8 * t:8 * t + 8]
        if r not in wiersze:
            wiersze.append(r)
        idx.append(wiersze.index(r))
    if len(wiersze) != OBJ_BOUNDS_UNIQ:
        raise SystemExit(f"granice aktywacji: {len(wiersze)} unikalnych wierszy (oczekiwano {OBJ_BOUNDS_UNIQ})")
    return wiersze, idx


def bounds_inc(rom: bytes) -> str:
    """Tablice adresow wierszy granic aktywacji wg typu (oa_blo / oa_bhi: obj/objs_tab.asm)."""
    idx = bounds_unique(rom)[1]
    adr = [OBJ_BOUNDS_ATARI + 8 * i for i in idx]
    return ("; wygenerowane przez tools/extract_sms.py - nie edytowac (adresy granic aktywacji typow $00-$55 w banku 45)\n"
            "oa_blo\n\tdta l(" + ",".join(f"${a:04X}" for a in adr) + ")\n"
            "oa_bhi\n\tdta h(" + ",".join(f"${a:04X}" for a in adr) + ")\n")


def objects_bank(rom: bytes) -> tuple[bytes, list[str]]:
    """Obraz banku 45 (16 KiB, okno $4000): zakresy danych banku 1 pod adresami SMS i granice aktywacji pod
    OBJ_BOUNDS_ATARI; kontrola: zgodność z ROM-em, odczyty map sprite'ów z sekwencji animacji w zakresach."""
    img = bytearray(0x4000)
    zajete = []
    for a, n, _ in OBJ_SPANS:
        img[a - 0x4000:a - 0x4000 + n] = sms_read(rom, a, n)
        zajete.append((a, a + n))
    b = b"".join(bounds_unique(rom)[0])
    img[OBJ_BOUNDS_ATARI - 0x4000:OBJ_BOUNDS_ATARI - 0x4000 + len(b)] = b
    zajete.append((OBJ_BOUNDS_ATARI, OBJ_BOUNDS_ATARI + len(b)))
    zajete.sort()
    for (a0, a1), (b0, _) in zip(zajete, zajete[1:]):
        if a1 > b0:
            raise SystemExit(f"bank obiektów: zakresy ${a0:04X} i ${b0:04X} nachodzą na siebie")
    if zajete[-1][1] > 0x8000:
        raise SystemExit("bank obiektów: dane poza $7FFF")

    def w_zakresie(adr: int) -> bool:
        return any(a <= adr < e for a, e in zajete)

    raport = []
    # dekoder kontrolny: mapy sprite'ów osiągalne z sekwencji animacji (para klatka, czas do $FF; mapa = baza +
    # klatka * 18, do_framed_animation 01:7C41) i mapy stałe - każdy bajt czytany przez draw_sprite_string w zakresie
    animacje = {  # baza map, tablica wskaźników sekwencji (adres, liczba), sekwencje pojedyncze
        "Crabmeat": (0x66F9, (0x66E0, 5), []),
        "Buzz Bomber": (0x6CF9, (0x6CE2, 4), []),
        "Motobug": (0x6ECB, (0x6EB1, 5), []),
        "eksplozja": (0x69BE, None, [0x69B7]),
        "Chopper": (0x7DE1, None, [0x7DDC]),
    }
    mapy = {0x5BBF, 0x5BCC, 0x5F10, 0x6911, 0x6923, 0x6931, 0x7C29, 0x7C31, 0x7C39, 0x7DF7,
            # M6.4: boss GHZ3 (kierunki, lot po śmierci), kapsuła, zwierzęta (GHZ)
            0x72F8, 0x730A, 0x752E, 0x7540, 0x7552, 0x7752, 0x7760, 0x776D, 0x777B, 0x7788, 0x7796, 0x77A3, 0x77B1,
            0x6FED, 0x7E89, 0x7ED9}   # M6.7: Newtron, platformy $27 / $28
    mapy |= {0x7922 + 18 * k for k in range(12)} | {0x7638 + 18 * k for k in range(6)}
    for nazwa, (baza, tab, sekw) in animacje.items():
        adresy = list(sekw)
        if tab:
            adresy += list(struct.unpack_from(f"<{tab[1]}H", sms_read(rom, tab[0], 2 * tab[1])))
        for s in adresy:
            i = 0
            while sms_read(rom, s + i, 1)[0] != 0xFF:
                mapy.add(baza + 18 * sms_read(rom, s + i, 1)[0])
                i += 2
    # tabliczka: sekwencje signpost_anim_* - klatka na każdy tick do $FF (za nim indeks powrotu), mapa =
    # SPRITEMAP_signpost + klatka * 18 (01:6096-01:60B6)
    for s in (0x6157, 0x6171, 0x6174, 0x618E, 0x61A8, 0x61C2):
        i = 0
        while sms_read(rom, s + i, 1)[0] != 0xFF:
            mapy.add(0x61DC + 18 * sms_read(rom, s + i, 1)[0])
            i += 1
    zle = [m for m in sorted(mapy) for r in draw_reads(rom, m) if not w_zakresie(r)]
    if zle:
        raise SystemExit("bank obiektów: mapy sprite'ów czytane poza zakresami: "
                         + ", ".join(f"${m:04X}" for m in sorted(set(zle))))
    for a, n, opis in OBJ_SPANS:
        if img[a - 0x4000:a - 0x4000 + n] != rom[0x4000 + (a & 0x3FFF):0x4000 + (a & 0x3FFF) + n]:
            raise SystemExit(f"bank obiektów: zakres ${a:04X} różny od ROM-u")
    funcs = struct.unpack_from(f"<{OBJ_TYPES}H", rom, OBJ_FUNCS)
    puste = [f"${t:02X}" for t, f in enumerate(funcs) if f == 0]
    raport.append(f"bank obiektów: {len(OBJ_SPANS)} zakresów z banku 1 ({sum(n for _, n, _ in OBJ_SPANS)} B), "
                  f"granice aktywacji {len(b)} B pod ${OBJ_BOUNDS_ATARI:04X}; mapy sprite'ów sprawdzone: {len(mapy)}; "
                  f"typy bez funkcji (ENTRY_RESET): {', '.join(puste)}")
    return bytes(img), raport


def objz2_bank(rom: bytes, spans: list | None = None, nr: int = 2) -> tuple[bytes, list[str]]:
    """M6.9: obraz drugiego banku obiektow strefy PB_OBJZ2 (zakresy OBJZ2_SPANS, ten sam uklad co PB_OBJZ). Kontrola: zakresy w oknie
    banku 2 ROM-u, bez nakladania, zgodne z ROM-em (mapy sprite'ow sprawdzane przy obiektach - kroki 3-7 M6.9). M6.10: spans / nr - trzeci
    bank PB_OBJZ3 (OBJZ3_SPANS)."""
    spans = OBJZ2_SPANS if spans is None else spans
    img = bytearray(0x4000)
    zajete = []
    for a, n, _ in spans:
        if not (0x8000 <= a and a + n <= 0xC000):
            raise SystemExit(f"bank obiektów strefy {nr}: zakres ${a:04X} poza oknem banku 2 ROM-u")
        img[a - 0x8000:a - 0x8000 + n] = sms_read(rom, a, n)
        zajete.append((a, a + n))
    zajete.sort()
    for (a0, a1), (b0, _) in zip(zajete, zajete[1:]):
        if a1 > b0:
            raise SystemExit(f"bank obiektów strefy {nr}: zakresy ${a0:04X} i ${b0:04X} nachodzą na siebie")
    return bytes(img), [f"bank obiektów strefy {nr}: {len(spans)} zakresów z banku 2 ({sum(n for _, n, _ in spans)} B)"]


def objz_bank(rom: bytes) -> tuple[bytes, list[str]]:
    """Obraz banku obiektow strefy PB_OBJZ (16 KiB, okno $4000): zakresy danych banku 2 ROM-u pod adresem SMS - $4000.
    Kontrola: zakresy nie nachodza, sa zgodne z ROM-em, a mapy sprite'ow osiagalne z sekwencji i mapy stale leza w zakresach."""
    img = bytearray(0x4000)
    zajete = []
    for a, n, _ in OBJZ_SPANS:
        if not (0x8000 <= a and a + n <= 0xC000):
            raise SystemExit(f"bank obiektów strefy: zakres ${a:04X} poza oknem banku 2 ROM-u")
        img[a - 0x8000:a - 0x8000 + n] = sms_read(rom, a, n)   # obraz banku: przesuniecie = adres okna - $4000 = adres SMS - $8000
        zajete.append((a, a + n))
    zajete.sort()
    for (a0, a1), (b0, _) in zip(zajete, zajete[1:]):
        if a1 > b0:
            raise SystemExit(f"bank obiektów strefy: zakresy ${a0:04X} i ${b0:04X} nachodzą na siebie")

    def w_zakresie(adr: int) -> bool:
        return any(a <= adr < e for a, e in zajete)

    # Spikeses: baza map $837E, sekwencje left $8374 / right $8379 (para klatka, czas do $FF; mapa = baza + klatka * 18)
    mapy = {0x8481, 0x865A, 0xB5B5, 0x81F4, 0x8206, 0x82CD, 0x82DF, 0xA3BB, 0xA3CD, 0xA3DF, 0xA3F1, 0x8022, 0x8034, 0x8046}
    for s in (0x8374, 0x8379):
        i = 0
        while sms_read(rom, s + i, 1)[0] != 0xFF:
            mapy.add(0x837E + 18 * sms_read(rom, s + i, 1)[0])
            i += 2
    zle = [m for m in sorted(mapy) for r in draw_reads(rom, m) if not w_zakresie(r)]
    if zle:
        raise SystemExit("bank obiektów strefy: mapy sprite'ów czytane poza zakresami: "
                         + ", ".join(f"${m:04X}" for m in sorted(set(zle))))
    for a, n, _ in OBJZ_SPANS:
        if img[a - 0x8000:a - 0x8000 + n] != sms_read(rom, a, n):
            raise SystemExit(f"bank obiektów strefy: zakres ${a:04X} różny od ROM-u")
    return bytes(img), [f"bank obiektów strefy: {len(OBJZ_SPANS)} zakresów z banku 2 ({sum(n for _, n, _ in OBJZ_SPANS)} B), "
                        f"mapy sprite'ów sprawdzone: {len(mapy)}"]


def objart_bank(rom: bytes) -> tuple[bytes, int, list[str]]:
    """Obraz banku 47: ikony monitorów i grafika tabliczki w 8 bpp (kolor + 16 - paleta sprite'ów VBXE, 0 bez
    zmian), paleta tabliczki RGB. Zwraca też liczbę kafli tabliczki."""
    img = bytearray(0x4000)
    ikony = planar_to_8bpp(rom[MONART:MONART + 128 * MONART_N], 4 * MONART_N)
    ikony = np.where(ikony != 0, ikony + 16, 0).astype(np.uint8)
    img[OBJART_ICONS:OBJART_ICONS + ikony.size] = ikony.tobytes()
    vdp = decode_hy_art(rom, SIGNPOST_ART)
    n = min(len(vdp) // 32, 128)
    kafle = planar_to_8bpp(vdp, n)
    kafle = np.where(kafle != 0, kafle + 16, 0).astype(np.uint8)
    img[OBJART_SIGN:OBJART_SIGN + kafle.size] = kafle.tobytes()
    for c, v in enumerate(sms_read(rom, SIGNPOST_PAL, 16)):
        img[OBJART_SIGNPAL + 3 * c:OBJART_SIGNPAL + 3 * c + 3] = bytes(sms_rgb(v))
    # dekoder kontrolny: z obrazu z powrotem do 4 bpp VDP (bitplany) = ROM
    def do_vdp(px: np.ndarray) -> bytes:
        v = np.where(px != 0, px - 16, 0).astype(np.uint8)
        planes = [((v >> b) & 1) for b in range(4)]                     # [t, y, x]
        rows = np.stack([np.packbits(p, axis=-1)[..., 0] for p in planes], axis=-1)   # [t, y, 4]
        return rows.astype(np.uint8).tobytes()
    if do_vdp(np.frombuffer(img, np.uint8)[OBJART_ICONS:OBJART_ICONS + 64 * 4 * MONART_N].reshape(-1, 8, 8)) \
            != rom[MONART:MONART + 128 * MONART_N]:
        raise SystemExit("bank grafiki obiektów: ikony monitorów różne od ROM-u")
    if do_vdp(np.frombuffer(img, np.uint8)[OBJART_SIGN:OBJART_SIGN + 64 * n].reshape(-1, 8, 8)) != vdp[:32 * n]:
        raise SystemExit("bank grafiki obiektów: kafle tabliczki różne od dekodowanych z ROM-u")
    boss3 = planar_to_8bpp(decode_hy_art(rom, BOSS3_ART), 128)
    img[OBJART_BOSS3:OBJART_BOSS3 + 0x1000] = pack4(boss3)
    return bytes(img), n, [f"bank grafiki obiektów: {MONART_N} ikon monitorów (05:5180), tabliczka {n} kafli "
                           f"(ART_09_4294, {len(vdp) // 32} w HY), paleta 01:626C"]


def boss_bank(rom: bytes) -> tuple[bytes, np.ndarray, np.ndarray, bytes]:
    """M6.4: obraz banku 59 (16 KiB): +$0000 grafika bossa GHZ3 (ART_09_AEB1, 128 kafli sprite'ów 4 bpp, 2 piksele/bajt),
    +$1000 grafika zwierząt i kapsuły (ART_0C_DA28, 128 kafli), +$2000 paleta bossa (PAL2_boss RGB 16 x 3 B);
    M6.5: +$2030 paleta sprite'ów etapów specjalnych (RGB 16 x 3 B), +$2100 kafle sprite'ów etapów specjalnych
    (ART_09_A511, 128 kafli 4 bpp); zwraca też kafle 8 bpp (model obrazu testów) i paletę SMS."""
    boss = planar_to_8bpp(decode_hy_art(rom, BOSS_ART), 128)
    caps = planar_to_8bpp(decode_hy_art(rom, CAPS_ART), 128)
    img = bytearray(0x4000)
    img[0x0000:0x1000] = pack4(boss)
    img[0x1000:0x2000] = pack4(caps)
    pal = sms_read(rom, BOSS_PAL, 16)
    for c, v in enumerate(pal):
        img[0x2000 + 3 * c:0x2000 + 3 * c + 3] = bytes(sms_rgb(v))
    ss = planar_to_8bpp(decode_hy_art(rom, SS_ART), 128)
    img[0x2100:0x3100] = pack4(ss)
    ss_pal_ptr = struct.unpack_from("<8H", rom, PAL3_PTRS)[SS_PAL_IDX]
    for c, v in enumerate(rom[ss_pal_ptr + 16: ss_pal_ptr + 32]):
        img[0x2030 + 3 * c:0x2030 + 3 * c + 3] = bytes(sms_rgb(v))
    return bytes(img), boss, caps, pal


PL_ASCII = str.maketrans("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ", "acelnoszzACELNOSZZ")


SIGN_ART = SIGNPOST_ART           # ART_09_4294: nagłówek grafiki tabliczki (load_art 00:0405 traktuje $4294 jak
                                  # przesunięcie od banku 9 - dane w banku 10 pod $0294)


def objdata_inc(n_sign: int, rom: bytes) -> str:
    """Stałe MADS banków obiektów: zakresy danych w banku 45 (OD_SPAN_k_*), luki na kod, granice aktywacji;
    M4.8: słowa nagłówka grafiki tabliczki, które load_art zostawia w tmp_00 (+ adres) i tmp_02."""
    out = ["; wygenerowane przez tools/extract_sms.py - nie edytowac (bank 45: dane obiektow pod adresami SMS,",
           "; bank 47: grafika obiektow; docs/plan-m4.md)",
           f"OD_BOUNDS     = ${OBJ_BOUNDS_ATARI:04X}       ; LUT_object_offscreen_activation_bounds (00:2BA2): "
           f"{OBJ_BOUNDS_UNIQ} unikalnych wierszy, {8 * OBJ_BOUNDS_UNIQ} B",
           f"OD_NTYPES     = {OBJ_TYPES}"]
    for k, (a, n, opis) in enumerate(OBJ_SPANS):
        out.append(f"OD_SPAN{k}     = ${a:04X}       ; ..${a + n - 1:04X} {opis.translate(PL_ASCII)}")
    zajete = sorted([(a, a + n) for a, n, _ in OBJ_SPANS] + [(OBJ_BOUNDS_ATARI, OBJ_BOUNDS_ATARI + 8 * OBJ_BOUNDS_UNIQ)])
    luki, p = [], 0x4000
    for a, e in zajete:
        if a > p:
            luki.append((p, a))
        p = e
    if p < 0x8000:
        luki.append((p, 0x8000))
    out.append("; luki na kod obiektow (poczatek, koniec + 1)")
    for k, (a, e) in enumerate(luki):
        out.append(f"OD_GAP{k}      = ${a:04X}\nOD_GAP{k}_END  = ${e:04X}       ; {e - a} B")
    # M6.7: luki nazwane wg zakresu danych, po ktorym leza (OD_GAPA<k> = luka zaczynajaca sie na koncu OD_SPAN<k>) - numeracja pozycyjna
    # OD_GAP<n> przesuwa sie przy kazdym nowym zakresie, nazwy wg zakresow sa stabilne (nowe zakresy dopisywac na koncu OBJ_SPANS)
    out.append("; luki wg poprzedzajacego zakresu danych (stale nazwy)")
    for k, (a0, n0, _) in enumerate(OBJ_SPANS):
        for (a, e) in luki:
            if a == a0 + n0:
                out.append(f"OD_GAPA{k}      = ${a:04X}\nOD_GAPA{k}_END  = ${e:04X}       ; {e - a} B")
    # M6.6: bank obiektow strefy PB_OBJZ - adresy SMS zakresow (OZ_SPANk) i luki na kod w oknie (OZ_GAPk = adres okna)
    out.append(f"OZ_OFF        = ${OBJZ_OFF:04X}       ; adres okna banku obiektow strefy = adres SMS - OZ_OFF")
    for k, (a, n, opis) in enumerate(OBJZ_SPANS):
        out.append(f"OZ_SPAN{k}     = ${a:04X}       ; ..${a + n - 1:04X} {opis.translate(PL_ASCII)}")
    zz = sorted((a - OBJZ_OFF, a - OBJZ_OFF + n) for a, n, _ in OBJZ_SPANS)
    luki, p = [], 0x4000
    for a, e in zz:
        if a > p:
            luki.append((p, a))
        p = e
    if p < 0x8000:
        luki.append((p, 0x8000))
    out.append("; luki na kod obiektow strefy (poczatek, koniec + 1 - adresy okna)")
    for k, (a, e) in enumerate(luki):
        out.append(f"OZ_GAP{k}      = ${a:04X}\nOZ_GAP{k}_END  = ${e:04X}       ; {e - a} B")
    out.append("; luki wg poprzedzajacego zakresu danych (stale nazwy; nowe zakresy dopisywac na koncu OBJZ_SPANS)")
    for k, (a0, n0, _) in enumerate(OBJZ_SPANS):
        for (a, e) in luki:
            if a == a0 - OBJZ_OFF + n0:
                out.append(f"OZ_GAPA{k}      = ${a:04X}\nOZ_GAPA{k}_END  = ${e:04X}       ; {e - a} B")
    # M6.9: drugi bank obiektow strefy PB_OBJZ2 - zakresy (OZ2_SPANk) i luki (OZ2_GAPk, OZ2_GAPAk wg poprzedzajacego zakresu)
    for k, (a, n, opis) in enumerate(OBJZ2_SPANS):
        out.append(f"OZ2_SPAN{k}    = ${a:04X}       ; ..${a + n - 1:04X} {opis.translate(PL_ASCII)}")
    zz = sorted((a - OBJZ_OFF, a - OBJZ_OFF + n) for a, n, _ in OBJZ2_SPANS)
    luki, p = [], 0x4000
    for a, e in zz:
        if a > p:
            luki.append((p, a))
        p = e
    if p < 0x8000:
        luki.append((p, 0x8000))
    out.append("; luki na kod banku obiektow strefy 2 (poczatek, koniec + 1 - adresy okna)")
    for k, (a, e) in enumerate(luki):
        out.append(f"OZ2_GAP{k}     = ${a:04X}\nOZ2_GAP{k}_END = ${e:04X}       ; {e - a} B")
    for k, (a0, n0, _) in enumerate(OBJZ2_SPANS):
        for (a, e) in luki:
            if a == a0 - OBJZ_OFF + n0:
                out.append(f"OZ2_GAPA{k}     = ${a:04X}\nOZ2_GAPA{k}_END = ${e:04X}       ; {e - a} B")
    # M6.10: trzeci bank obiektow strefy PB_OBJZ3 (Sky Base) - zakresy (OZ3_SPANk) i luki (OZ3_GAPk, OZ3_GAPAk)
    for k, (a, n, opis) in enumerate(OBJZ3_SPANS):
        out.append(f"OZ3_SPAN{k}    = ${a:04X}       ; ..${a + n - 1:04X} {opis.translate(PL_ASCII)}")
    zz = sorted((a - OBJZ_OFF, a - OBJZ_OFF + n) for a, n, _ in OBJZ3_SPANS)
    luki, p = [], 0x4000
    for a, e in zz:
        if a > p:
            luki.append((p, a))
        p = e
    if p < 0x8000:
        luki.append((p, 0x8000))
    out.append("; luki na kod banku obiektow strefy 3 (poczatek, koniec + 1 - adresy okna)")
    for k, (a, e) in enumerate(luki):
        out.append(f"OZ3_GAP{k}     = ${a:04X}\nOZ3_GAP{k}_END = ${e:04X}       ; {e - a} B")
    for k, (a0, n0, _) in enumerate(OBJZ3_SPANS):
        for (a, e) in luki:
            if a == a0 - OBJZ_OFF + n0:
                out.append(f"OZ3_GAPA{k}     = ${a:04X}\nOZ3_GAPA{k}_END = ${e:04X}       ; {e - a} B")
    out += [f"OA_ICONS      = ${OBJART_ICONS:04X}       ; bank 47: ikony monitorow 8 x 256 B (kafle $5C-$5F, 8 bpp)",
            f"OA_SIGN       = ${OBJART_SIGN:04X}       ; bank 47: kafle tabliczki 8 bpp",
            f"OA_SIGN_N     = {n_sign}",
            f"OA_SIGNPAL    = ${OBJART_SIGNPAL:04X}       ; bank 47: paleta tabliczki RGB",
            f"SIGN_TMP00    = ${rom[SIGN_ART + 4] | rom[SIGN_ART + 5] << 8:04X}       ; ART_09_4294 slowo +4 (tmp_00 = $4294 + to)",
            f"SIGN_TMP02    = ${rom[SIGN_ART + 6] | rom[SIGN_ART + 7] << 8:04X}       ; ART_09_4294 slowo +6 (tmp_02)",
            f"BOSS_TMP00    = ${rom[BOSS_ART + 4] | rom[BOSS_ART + 5] << 8:04X}       ; ART_09_AEB1 slowo +4 (M6.4)",
            f"BOSS_TMP02    = ${rom[BOSS_ART + 6] | rom[BOSS_ART + 7] << 8:04X}       ; ART_09_AEB1 slowo +6",
            f"CAPS_TMP00    = ${rom[CAPS_ART + 4] | rom[CAPS_ART + 5] << 8:04X}       ; ART_0C_DA28 slowo +4",
            f"CAPS_TMP02    = ${rom[CAPS_ART + 6] | rom[CAPS_ART + 7] << 8:04X}       ; ART_0C_DA28 slowo +6",
            f"OA_BOSS3      = ${OBJART_BOSS3:04X}       ; bank 47: grafika bossa BRI3 (4 bpp)",
            f"BOSS3_TMP00   = ${rom[BOSS3_ART + 4] | rom[BOSS3_ART + 5] << 8:04X}       ; ART_0C_E508 slowo +4 (M6.6)",
            f"BOSS3_TMP02   = ${rom[BOSS3_ART + 6] | rom[BOSS3_ART + 7] << 8:04X}       ; ART_0C_E508 slowo +6",
            f"ROBO_TMP00    = ${rom[ROBO_ART + 4] | rom[ROBO_ART + 5] << 8:04X}       ; ART_0C_EF3F slowo +4 (M6.9: Robotnik)",
            f"ROBO_TMP02    = ${rom[ROBO_ART + 6] | rom[ROBO_ART + 7] << 8:04X}       ; ART_0C_EF3F slowo +6"]
    return "\n".join(out) + "\n"


def sonic_tables(rom: bytes, flags_idx: int) -> bytes:
    """Obraz 1 KiB: +$000 parametry fizyki (4 x 9 B), +$040 kody bloków specjalnych strefy (256 B, kod < $1C
    = indeks CODEPTRTAB_sonic_tile_specials), +$140 region animacji/map sprite'ów 01:591D-01:5B08 (adresy SMS
    w danych zostają - port tłumaczy je: SONIC_ANIM + (adres - $591D))."""
    img = bytearray(0x400)
    img[0x000:0x024] = sms_read(rom, SONIC_PHYSICS, 36)
    p = struct.unpack("<H", sms_read(rom, SONIC_SPECIALS + 2 * flags_idx, 2, rompage_2=15))[0]
    img[0x040:0x140] = sms_read(rom, (p + SONIC_SPECIALS) & 0xFFFF, 256, rompage_2=15)
    img[0x140:0x140 + SONIC_ANIM_TO - SONIC_ANIM_FROM] = sms_read(rom, SONIC_ANIM_FROM, SONIC_ANIM_TO - SONIC_ANIM_FROM)
    img[0x3F0:0x3F6] = sms_read(rom, LUT_RING_MAP, 6)       # M3.5: update_ring_tile_art_timer_and_index
    return bytes(img)


def ring_frames(rom: bytes) -> np.ndarray:
    """6 klatek grafiki pierścienia [6, 16, 16] (indeksy 0..15): kafle $FC $FD nad $FE $FF (bloki pierścieni)."""
    t = planar_to_8bpp(sms_read(rom, RING_ART, 6 * 128, rompage_1=RING_ART_BANK), 24).reshape(6, 2, 2, 8, 8)
    return t.transpose(0, 1, 3, 2, 4).reshape(6, 16, 16)


def sonic_frame(rom: bytes, base: int, d: int) -> np.ndarray:
    """Klatka Sonica [32, 24] (indeksy palety sprite'ów 0..7, 0 = przezroczysty): kafel t (0..11) = sprite 8x16
    nr t // 2 w mapie ($B4 + 2 * (3 * wiersz + kolumna)), górna (t parzyste) lub dolna połowa."""
    t = planar_to_8bpp(sms_3bpp_to_4bpp(rom[base + d * SONIC_FRAME_BYTES: base + (d + 1) * SONIC_FRAME_BYTES]), 12)
    img = np.zeros((32, 24), np.uint8)
    for k in range(12):
        h, c, part = k // 6, (k % 6) // 2, k % 2
        img[h * 16 + part * 8: h * 16 + part * 8 + 8, c * 8: c * 8 + 8] = t[k]
    return img


def sms_3bpp_to_4bpp(raw: bytes) -> bytes:
    """Wiersze kafli 3 bpp (3 bitplany) -> format VDP 4 bpp (czwarty bitplan 0) jak update_sonic_3bpp_sprite."""
    return b"".join(raw[i:i + 3] + b"\0" for i in range(0, len(raw), 3))


def sonic_art(rom: bytes) -> tuple[np.ndarray, np.ndarray, list[int], list[tuple[int, int]]]:
    """(klatki w prawo [42,32,24], w lewo [42,32,24], numery klatek 'w lewo' niebędących lustrem prawych,
    tablica 84 pozycji (kierunek * 42 + klatka) -> (numer obrazu w VRAM, odbicie))."""
    right = np.stack([sonic_frame(rom, SONIC_ART_RIGHT, d) for d in range(SONIC_FRAMES)])
    left = np.stack([sonic_frame(rom, SONIC_ART_LEFT, d) for d in range(SONIC_FRAMES)])
    own = [d for d in range(SONIC_FRAMES) if not np.array_equal(left[d], right[d][:, ::-1])]
    table = [(d, 0) for d in range(SONIC_FRAMES)]
    table += [((SONIC_FRAMES + own.index(d)), 0) if d in own else (d, 1) for d in range(SONIC_FRAMES)]
    return right, left, own, table


def pack4(a: np.ndarray) -> bytes:
    """Obraz 8 bpp (wartości 0..15) -> 2 piksele na bajt (starsza połówka = lewy piksel)."""
    a = a.reshape(-1)
    return ((a[0::2] << 4) | a[1::2]).astype(np.uint8).tobytes()


def sms_read(rom: bytes, addr: int, n: int, rompage_1: int = 1, rompage_2: int = 2) -> bytes:
    """Odczyt n bajtów spod adresu CPU SMS (model mappera Sega: slot 0 = bank 0, slot 1/2 = rompage_1/2).
    Adresy RAM ($C000+) nie są stałe - zwraca None dla bajtów spoza ROM-u (obsługuje wywołujący)."""
    out = bytearray()
    for a in range(addr, addr + n):
        a &= 0xFFFF
        if a < 0x4000:
            out.append(rom[a])
        elif a < 0x8000:
            out.append(rom[rompage_1 * 0x4000 + (a & 0x3FFF)])
        elif a < 0xC000:
            out.append(rom[rompage_2 * 0x4000 + (a & 0x3FFF)])
        else:
            raise ValueError(f"adres RAM SMS ${a:04X} w tablicy ROM")
    return bytes(out)


def phys_tables(rom: bytes) -> tuple[bytes, dict]:
    """Obraz 4 KiB dla PHYS_ATARI: współczynniki (3 x 64 B), wskaźniki profili lo/hi (4 tablice x 64,
    przeniesione na adresy Atari) i profile (32 B każdy, unikalne). Wskaźnik do RAM SMS (śmieci poza
    zakresem tablicy) -> profil 'brak kolizji' ($80 x 32)."""
    img = bytearray(0x1000)
    img[0x000:0x040] = sms_read(rom, LUT_VERTICAL_HSLIDE, 64)
    img[0x040:0x080] = sms_read(rom, LUT_HORIZONTAL_VSLIDE, 64)
    img[0x080:0x0C0] = sms_read(rom, LUT_Y_MAGNET, 64)
    profile: dict[int, int] = {}            # adres SMS -> numer profilu w obrazie
    profile_ram = 0
    for t, base in enumerate(LUT_PUSH):
        ptrs = struct.unpack("<64H", sms_read(rom, base, 128))
        for i, p in enumerate(ptrs):
            if p >= 0xC000:                 # wskaźnik do RAM SMS (tylko poza 47 pozycjami) -> brak kolizji
                p = -1
                profile_ram += 1
            if p not in profile:
                profile[p] = len(profile)
            atari = PHYS_ATARI + PHYS_PROFILES + 32 * profile[p]
            img[0x100 + t * 64 + i] = atari & 0xFF
            img[0x200 + t * 64 + i] = atari >> 8
    for p, k in profile.items():
        o = PHYS_PROFILES + 32 * k
        if o + 32 > len(img):
            raise SystemExit("profile kolizji nie mieszczą się w 4 KiB")
        img[o:o + 32] = b"\x80" * 32 if p < 0 else sms_read(rom, p, 32)
    return bytes(img), {"profile": len(profile), "wskazniki_do_ram": profile_ram}


def sms_rgb(v: int) -> tuple[int, int, int]:
    """Kolor SMS --BBGGRR (2 bity na składową) -> RGB 8 bit."""
    return ((v & 3) * 85, ((v >> 2) & 3) * 85, ((v >> 4) & 3) * 85)


def decode_hy_art(rom: bytes, addr: int) -> bytes:
    """Grafika skompresowana „HY”: nagłówek (magic $5948, ptr offsetów, ptr wierszy, liczba wierszy),
    bitmapa (1 bit na wiersz kafla: 0 = kolejny literał, 1 = odwołanie do wcześniejszego wiersza),
    tablica offsetów (1 bajt; >= $F0 = offset 12-bitowy w 2 bajtach), wiersze po 4 bajty (4 bitplany).
    Zwraca dane VDP: 4 bajty na wiersz, 32 bajty na kafel."""
    magic, offs_ptr, rows_ptr, row_count = struct.unpack_from("<4H", rom, addr)
    if magic != 0x5948:
        raise ValueError(f"brak sygnatury HY pod {addr:#x}")
    if row_count % 8 or offs_ptr != 8 + row_count // 8 or rows_ptr <= offs_ptr:
        raise ValueError("niespójny nagłówek HY")
    bitmask = rom[addr + 8: addr + offs_ptr]
    offsets = rom[addr + offs_ptr: addr + rows_ptr]
    rows_base = addr + rows_ptr
    out = bytearray()
    oi = ri = 0
    for b in bitmask:
        for i in range(8):
            if not (b >> i) & 1:
                use = ri
                ri += 4
            else:
                use = offsets[oi]
                oi += 1
                if use >= 0xF0:
                    use = ((use - 0xF0) << 8) | offsets[oi]
                    oi += 1
                use *= 4
            out += rom[rows_base + use: rows_base + use + 4]
    if oi != len(offsets):
        raise ValueError("nadmiarowe offsety HY")
    return bytes(out)


def planar_to_8bpp(vdp: bytes, tiles: int) -> np.ndarray:
    """Kafle VDP (4 bitplany na wiersz) -> tablica [tiles, 8, 8] indeksów 0..15."""
    arr = np.frombuffer(vdp[: tiles * 32], dtype=np.uint8).reshape(tiles, 8, 4)
    bits = np.unpackbits(arr[..., None], axis=-1)            # [t, y, plane, 8] MSB = lewy piksel
    planes = bits.astype(np.uint8)
    return (planes[:, :, 0] | (planes[:, :, 1] << 1) | (planes[:, :, 2] << 2) | (planes[:, :, 3] << 3))


def decode_layout(rom: bytes, addr: int, size: int, total: int = 4096) -> bytes:
    """RLE układu: bajt różny od poprzedniego literału = literał; powtórzony bajt = znacznik serii,
    następny bajt to liczba dodatkowych kopii (0 = 256), po serii „poprzedni” jest kasowany."""
    out = bytearray()
    prev = -1
    i = addr
    end = addr + size
    while i < end:
        v = rom[i]
        i += 1
        if v != prev:
            out.append(v)
            prev = v
        else:
            n = rom[i] or 256
            i += 1
            out += bytes([v]) * n
            prev = -1
    if len(out) != total:
        raise ValueError(f"układ: {len(out)} B zamiast {total} (zużyto {i - addr} z {size})")
    return bytes(out)


def ball32() -> np.ndarray:
    px = np.zeros((32, 32), dtype=np.uint8)
    for y in range(32):
        for x in range(32):
            dx, dy = x - 15.5, y - 15.5
            d2 = dx * dx + dy * dy
            if d2 > 15.5 * 15.5:
                v = 0
            elif d2 > 13.0 * 13.0:
                v = 65
            elif (x - 11) ** 2 + (y - 10) ** 2 <= 16:
                v = 66
            else:
                v = 64
            px[y, x] = v
    return px


BALL_RGB = {64: (255, 208, 32), 65: (224, 112, 16), 66: (255, 255, 208)}


def level_block(rom: bytes, lv: int) -> bytes:
    """Blok na poziom (256 B od LB_HDR = $2400): kopia nagłówka, czas startu, wskaźniki palet (adresy SMS), liczba obiektów,
    czas od punktu kontrolnego, adres flag bloków, lista obiektów. M6.10: osobna funkcja - bank SKY3 niesie bloki SKY3 i $1A."""
    blk = bytearray(256)
    rel = struct.unpack_from("<H", rom, HEADER_TABLE + 2 * lv)[0]
    h = HEADER_TABLE + rel
    hdr = rom[h: h + HEADER_SIZE]
    tf_ptrs = struct.unpack_from("<8H", rom, TILEFLAGS_PTRS)
    obj_rel = struct.unpack_from("<H", hdr, 0x1E)[0]
    pal_ptr = struct.unpack_from("<H", rom, PAL3_PTRS + 2 * hdr[0x1A])[0]
    cyc_ptr = struct.unpack_from("<H", rom, PALCYC_PTRS + 2 * hdr[0x1D])[0]
    blk[0x00: HEADER_COPY] = rom[h: h + HEADER_COPY]
    blk[0x28: 0x2B] = rom[STAGE_START_TIME: STAGE_START_TIME + 3]
    if lv >= 0x1C:                                                # M6.5: etap specjalny - czas w dół z tablicy (00:2159)
        t0 = BONUS_TIME + 3 * (lv - 0x1C)
        blk[0x28: 0x2B] = rom[t0: t0 + 3]
    struct.pack_into("<HH", blk, 0x2B, pal_ptr, cyc_ptr)
    blk[0x2F] = rom[HEADER_TABLE + obj_rel]
    # M4.1: czas startu od punktu kontrolnego (00:21AE: LUT_bonus_stage_time_limits 00:2402, 3 B) i lista obiektów
    # poziomu (load_object_list 00:232B: N = obiekty z Sonikiem, potem N-1 trójek typ, X/32, Y/32)
    blk[0x30: 0x33] = rom[CHECKPOINT_TIME: CHECKPOINT_TIME + 3]
    # M4.1: PTRLUT_level_tile_flags[indeks] - load_scroll_tile_list_buffers (00:06E3) zostawia go w tmp_02
    struct.pack_into("<H", blk, 0x34, tf_ptrs[hdr[0]])
    n_obj = rom[HEADER_TABLE + obj_rel]
    if n_obj > 32:
        raise SystemExit(f"lista obiektów: {n_obj} > 32 slotów")
    lista = rom[HEADER_TABLE + obj_rel: HEADER_TABLE + obj_rel + 1 + 3 * (n_obj - 1)]
    blk[0x40: 0x40 + len(lista)] = lista
    return bytes(blk)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rom", default=str(DEFAULT_ROM))
    ap.add_argument("--level", default="ghz1", choices=sorted(LEVELS))
    ap.add_argument("--out", default=None)
    a = ap.parse_args(argv)

    rom = Path(a.rom).read_bytes()
    if hashlib.sha256(rom).hexdigest() != ROM_SHA256:
        print("BŁĄD: ROM o innej sumie SHA-256 niż oczekiwana", file=sys.stderr)
        return 1
    lv = LEVELS[a.level]
    out = Path(a.out) if a.out else ROOT / "build" / "assets" / a.level
    out.mkdir(parents=True, exist_ok=True)

    # --- nagłówek poziomu ---
    rel = struct.unpack_from("<H", rom, HEADER_TABLE + 2 * lv)[0]
    h = HEADER_TABLE + rel
    hdr = rom[h: h + HEADER_SIZE]
    flags_idx = hdr[0]
    width, height, x0, x1, y0, y1 = struct.unpack_from("<6H", hdr, 1)
    start_bx, start_by = hdr[13], hdr[14]
    lay_rel, lay_size, tmap_rel, art_rel = struct.unpack_from("<4H", hdr, 15)
    pal_idx, cyc_speed, cyc_count, cyc_start = hdr[0x1A], hdr[0x1B], hdr[0x1C], hdr[0x1D]
    if width * height != 4096:
        raise SystemExit("nieobsługiwany rozmiar układu")

    # --- tablice flag bloków: długość = liczba bloków strefy ---
    tf_ptrs = struct.unpack_from("<8H", rom, TILEFLAGS_PTRS)
    tf_sorted = sorted(set(tf_ptrs))
    tf_addr = tf_ptrs[flags_idx]
    tf_next = next((p for p in tf_sorted if p > tf_addr), LUT_VERTICAL_HSLIDE)   # M6.10: strefa 7 (SKY3) - ostatnia, 104 bloki do 00:3F90
    n_blocks = tf_next - tf_addr
    tileflags = rom[tf_addr: tf_addr + n_blocks]
    prio = bytes(1 if f & 0x80 else 0 for f in tileflags)

    # --- dane ---
    if lv == 0x15:
        # M6.9: pod-poziom $15 (32 x 128) - RLE daje 2048 B; wiersze 64-127 to w oryginale resztki ukladu SBZ2 w RAM ($C800-$CFFF nie jest
        # nadpisywany, load_level_layout 00:20CB). Obraz banku: dopelnienie ukladem SBZ2 (przejscie z SBZ2 kopiuje tylko 2048 B - krok 6)
        rel2 = struct.unpack_from("<H", rom, HEADER_TABLE + 2 * 13)[0]
        lay2_rel, lay2_size = struct.unpack_from("<2H", rom, HEADER_TABLE + rel2 + 15)
        layout = decode_layout(rom, 0x14000 + lay_rel, lay_size, total=2048) + decode_layout(rom, 0x14000 + lay2_rel, lay2_size)[2048:]
    else:
        layout = decode_layout(rom, 0x14000 + lay_rel, lay_size)
    # M6.11: etapy 4 i 8 ($1F, $23) maja ten sam strumien RLE co JUN2 (05:4A62, 2267 B): etap zajmuje wiersze 0-87 (podloga w wierszu 80),
    # dalej uklad JUN2 (m.in. bloki 129-131 strefy JUN - poza 128 blokami strefy etapow: slot magazynu 0, flagi z nastepnej tablicy jak w
    # oryginale). Sonic nie wychodzi pod podloge; uklad caly jak w RAM SMS ($C000 - porownanie trace'u w kroku -16)
    lay = np.frombuffer(layout, dtype=np.uint8).reshape(height, width)
    zasieg = lay[:88] if lv in (0x1F, 0x23) else lay                # M6.11: etapy 4 i 8 - sprawdzane tylko wiersze etapu (0-87)
    if int(zasieg.max()) >= n_blocks:
        raise SystemExit(f"układ używa bloku {zasieg.max()} >= {n_blocks}")
    tilemap = rom[0x10000 + tmap_rel: 0x10000 + tmap_rel + 16 * n_blocks]
    vdp = decode_hy_art(rom, 0x30000 + art_rel)
    n_tiles = len(vdp) // 32
    tiles = planar_to_8bpp(vdp, min(n_tiles, 256))

    pal3_addr = struct.unpack_from("<8H", rom, PAL3_PTRS)[pal_idx]
    cyc_addr = struct.unpack_from("<9H", rom, PALCYC_PTRS)[cyc_start]   # M6.10: wpis +$1D (00:22B4), nie +$1A - inne tylko w SKY2
    pal_bg = rom[pal3_addr: pal3_addr + 16]
    pal_cyc = [rom[cyc_addr + 16 * i: cyc_addr + 16 * (i + 1)] for i in range(cyc_count)]

    # --- render bloków i poziomu ---
    tm = np.frombuffer(tilemap, dtype=np.uint8).reshape(n_blocks, 4, 4)
    blocks = np.zeros((n_blocks, 32, 32), dtype=np.uint8)
    for k in range(n_blocks):
        for ty in range(4):
            for tx in range(4):
                blocks[k, ty * 8: ty * 8 + 8, tx * 8: tx * 8 + 8] = tiles[tm[k, ty, tx]]
    lay_r = np.where(lay < n_blocks, lay, 0)                       # M6.11: podglad - bloki spoza strefy (etapy 4 i 8, wiersze >= 88) puste
    level = blocks[lay_r].transpose(0, 2, 1, 3).reshape(height * 32, width * 32)
    prio_mask = np.frombuffer(prio, np.uint8).astype(bool)[lay_r].repeat(32, 0).repeat(32, 1)

    rgb = np.array([sms_rgb(v) for v in pal_bg], dtype=np.uint8)
    Image.fromarray(rgb[level]).save(out / "level.png")
    prev = rgb[level].copy()
    prev[prio_mask & (level != 0)] = (prev[prio_mask & (level != 0)] // 2) + np.array([127, 0, 0], np.uint8)
    Image.fromarray(prev).save(out / "level_prio.png")

    # --- banki ---
    atlas = np.zeros(16384, dtype=np.uint8)
    atlas[: tiles.size] = tiles.reshape(-1)
    (out / "bank_atlas.bin").write_bytes(atlas.tobytes())

    bank = bytearray(16384)
    n_tm = min(len(tilemap), 0x0C00)                              # M6.10: SKY 224 bloki - nie nadpisywać LB_PRIO / LB_PALS
    bank[0x0000: n_tm] = tilemap[: n_tm]                          # mapowanie bloków (16 B/blok; M6.9: niżej przepisane wg slotów magazynu)
    bank[0x0C00: 0x0C00 + n_blocks] = prio                        # 1 = blok nad obiektami
    pal_spr = rom[pal3_addr + 16: pal3_addr + 32]                  # paleta sprite'ów SMS (kolory 16-31)
    pals = [pal_bg] + pal_cyc
    for i, p in enumerate(pals):                                  # palety RGB 16 x 3 B
        for c, v in enumerate(p):
            bank[0x0D00 + i * 48 + c * 3: 0x0D00 + i * 48 + c * 3 + 3] = bytes(sms_rgb(v))
    bank[0x1000: 0x2000] = layout                                 # układ, stride 256
    ball = ball32()
    bank[0x2000: 0x2400] = ball.tobytes()                         # kulka testowa 32x32
    # stan startowy M3: kopia nagłówka, czas startu, wskaźniki palet (wartości adresów SMS), liczba obiektów, lista obiektów
    # (blok na poziom LB_HDR..+$FF - level_block; M6.10: SKY3 i pod-poziom $1A w jednym banku, kopie bloku w SKY_STASH)
    bank[0x2400: 0x2500] = level_block(rom, lv)
    bank[0x2500: 0x2600] = rom[DEMO_INPUTS: DEMO_INPUTS + 256]   # demo + następne bajty ROM
    if lv == 15:
        # M6.10: zestawy palet cyklu błyskawic SKY1 (handle_SKY1_lightning_timer 00:1F49: 1A = paleta z nagłówka, 1B, 1C) jak LB_PALS + 48:
        # 4 palety x 16 kolorów RGB = 192 B; 1B w miejscu dema ($2500 - demo tylko w GHZ1), 1C na końcu banku ($3F00 - SKY1 bez wody)
        for adr, gdzie in zip(SKY1_LIGHTNING, (0x2500, 0x3F00)):
            bank[gdzie: gdzie + 0x100] = bytes(0x100)
            for i in range(cyc_count):
                for c, v in enumerate(rom[adr + 16 * i: adr + 16 * (i + 1)]):
                    bank[gdzie + i * 48 + c * 3: gdzie + i * 48 + c * 3 + 3] = bytes(sms_rgb(v))
    # M3.2: flagi bloków strefy (256 B od początku tablicy: gra indeksuje numerem bloku 0..255) i tablice kolizji
    bank[0x2600: 0x2700] = rom[tf_addr: tf_addr + 256]
    phys, phys_info = phys_tables(rom)
    bank[0x2700: 0x3700] = phys
    # M3.3: logika Sonica - parametry fizyki, bloki specjalne strefy, animacje
    bank[0x3700: 0x3B00] = sonic_tables(rom, flags_idx)
    # M3.5: klatki grafiki pierścienia (2 piksele na bajt, starsza połówka = lewy) - load.asm rozpakowuje do VRAM
    rings = ring_frames(rom)
    bank[0x3B00: 0x3E00] = ((rings[:, :, 0::2] << 4) | rings[:, :, 1::2]).astype(np.uint8).tobytes()
    # maska pierścieni bloku: b0 = kafle $FC $FD / $FE $FF w kolumnach 0-1 wierszy 1-2 (lewa połówka 16x16),
    # b1 = w kolumnach 2-3 (prawa) - pozycje, w które zebranie pierścienia (bit numeru bloku) wpisuje kafel 0
    ring_mask = np.zeros(256, np.uint8)
    for k in range(n_blocks):
        for bit, c in ((1, 0), (2, 2)):
            if [int(tm[k, r, c + i]) for r in (1, 2) for i in (0, 1)] == [0xFC, 0xFD, 0xFE, 0xFF]:
                ring_mask[k] |= bit
    bank[0x3E00: 0x3F00] = ring_mask.tobytes()
    # M6.9 krok 1: magazyn blokow w VRAM ma STORE_SLOTS slotow (STORE_VRAM + s * 1 KB do SONIC_VRAM, render/vram.inc). Strefy do 184 blokow
    # (GHZ-LAB) - slot = numer bloku (tozsamosc). Wieksze (SBZ 187, SKY 224) - sloty tylko dla blokow ukladu tego aktu i ich wariantow po
    # zebraniu pierscieni (sh_collect_ring kasuje bit 0/1 numeru bloku), w kolejnosci numerow. Tilemapa w banku w kolejnosci slotow
    # (build_store bez zmian), LB_BLKMAP ($0E00, 256 B) = slot bloku (render/frame.asm: emit_block, prio_part przez BLKMAP_RAM).
    if n_blocks <= STORE_SLOTS:
        blkslot = list(range(n_blocks))
    else:
        uzyte = {int(k) for k in np.unique(lay)}
        for k in list(uzyte):
            # review M6.9: zbieranie pierscienia (01:4C31-01:4E23) w kazdym bloku z (k & $7F) >= $79 kasuje bit 0/1 numeru bloku
            # (polowka wg x Sonica) - niezaleznie od grafiki pierscienia w bloku
            m = k & 3 if (k & 0x7F) >= 0x79 else 0
            uzyte |= {k & ~s for s in (1, 2, 3) if s & m == s}
        blkslot = sorted(uzyte)
        if len(blkslot) > STORE_SLOTS:
            raise SystemExit(f"akt używa {len(blkslot)} bloków (z wariantami pierścieni) > {STORE_SLOTS} slotów magazynu")
    blkmap = bytearray(256)
    for s, k in enumerate(blkslot):
        blkmap[k] = s
    bank[0x0000: 0x0C00] = bytes(0x0C00)
    bank[0x0000: 16 * len(blkslot)] = b"".join(tilemap[16 * k: 16 * k + 16] for k in blkslot)
    bank[0x0E00: 0x0F00] = bytes(blkmap)
    # M6.8: paleta podwodna (32 kolory: tlo + sprite'y, RGB) - irq_start: PAL2_lv_lab_under_water (00:024B), przy fladze iy_07 b4
    # (naglowek +$22; LAB3) PAL2_lv_lab_3_under_water (00:026B); poziomy bez flagi wody (iy_06 b7, naglowek +$21) - zera
    if hdr[0x21] & 0x80:
        wp = WATER_PAL3 if hdr[0x22] & 0x10 else WATER_PAL
        for c, v in enumerate(rom[wp: wp + 32]):
            bank[0x3F00 + 3 * c: 0x3F00 + 3 * c + 3] = bytes(sms_rgb(v))
    # M6.9: pod-poziomy SBZ2 z naglowkiem innym niz bank ($16, $18, $19 - uklad SBZ2; $17 - uklad $14): kopie HEADER_COPY B naglowka (start
    # i bajty za naglowkiem) pod LB_HDRALT + $40 * k (game/level.asm hdr_src: k = 0 $16 / $17, 1 $18, 2 $19); SBZ bez wody - $3F00 wolne
    alt = {13: (0x16, 0x18, 0x19), 0x14: (0x17,)}.get(lv, ())
    for k, n in enumerate(alt):
        rel_n = struct.unpack_from("<H", rom, HEADER_TABLE + 2 * n)[0]
        bank[0x3F00 + 0x40 * k: 0x3F00 + 0x40 * k + HEADER_COPY] = rom[HEADER_TABLE + rel_n: HEADER_TABLE + rel_n + HEADER_COPY]
    if lv == 0:
        # M6.11: poziom koncowy $12 (05:5639) = uklad, bloki i grafika GHZ1, inna kamera, start i lista obiektow ($53) - bank GHZ1 niesie
        # oba bloki na poziom: GHZ1 w $0F00, $12 w $3F00 (GHZ1 bez wody); lv_select (blk_stash) kopiuje wlasciwy na LB_HDR
        bank[0x0F00:0x1000] = level_block(rom, 0)
        bank[0x3F00:0x4000] = level_block(rom, 0x12)
    if lv == 17:
        # M6.10: pod-poziom $1A (05:5967, koniec SKY2) = układ, bloki, palety i flagi SKY3, inna kamera, start i lista obiektów (sama tabliczka).
        # Bank SKY3 niesie oba bloki na poziom; lv_select kopiuje właściwy na LB_HDR (iy_06 b4 i g_next_level_override_target $1A - $1A)
        for n, gdzie in zip((17, 0x1A), SKY_STASH):
            bank[gdzie: gdzie + 0x100] = level_block(rom, n)
    (out / "bank_level.bin").write_bytes(bytes(bank))

    # --- M3.6: grafika sprite'ów (bank 37: klatki Sonica w prawo; bank 39: nielustrzane w lewo, kafle sprite'ów
    # strefy, tablica klatek) - 2 piksele na bajt, load.asm rozpakowuje do VRAM z przesunięciem palety +16 ---
    right, left, own, ftable = sonic_art(rom)
    spr_bank, spr_ptr = hdr[23], struct.unpack_from("<H", hdr, 24)[0]
    spr_tiles = np.zeros((256, 8, 8), np.uint8)              # kafle sprite'ów VDP (VRAM $2000 = kafel 0)
    com_vdp = decode_hy_art(rom, SPR_COMMON_ART)                # najpierw wspólne pod kafel $80 (00:2175)
    n_com = min(len(com_vdp) // 32, 128)
    spr_tiles[128:128 + n_com] = planar_to_8bpp(com_vdp, n_com)
    spr_vdp = decode_hy_art(rom, spr_bank * 0x4000 + spr_ptr)  # potem z nagłówka pod kafel 0 (00:226B)
    n_spr = min(len(spr_vdp) // 32, 256)
    spr_tiles[:n_spr] = planar_to_8bpp(spr_vdp, n_spr)
    bank_s1 = bytearray(16384)
    bank_s1[0: SONIC_FRAMES * 384] = pack4(right)
    (out / "bank_sonic.bin").write_bytes(bytes(bank_s1))
    bank_s2 = bytearray(16384)
    bank_s2[0: len(own) * 384] = pack4(left[own]) if own else b""
    if len(own) * 384 > 0x1F00:
        raise SystemExit("klatki Sonica w lewo nie mieszczą się w banku")
    for i, (k, flip) in enumerate(ftable):                        # VRAM obrazu k: SONIC_VRAM + k * $300 ($6E000)
        adr = 0x6E000 + k * 0x300
        bank_s2[0x1F00 + 2 * i] = (adr >> 8) & 0xFF
        bank_s2[0x1F00 + 2 * i + 1] = (adr >> 16) | (0x80 if flip else 0)
    for c, v in enumerate(pal_spr):                               # paleta sprite'ów RGB (kolory VBXE 16-31)
        bank_s2[0x1FB0 + c * 3: 0x1FB0 + c * 3 + 3] = bytes(sms_rgb(v))
    if a.level.startswith("sky"):
        # M6.10: bank sprite'ów strefy SKY wspólny dla SKY1-3 - obie palety sprite'ów: $1F00 LVPAL3_SKY (paleta 5), $1F30 LVPAL3_SKY_3
        # (paleta 6); lv_select (sky_stash) kopiuje właściwą na $1FB0. Tablica klatek ($1F00) w bankach stref nieużywana (klatki: bank 39)
        bank_s2[0x1F00: 0x1FB0] = bytes(0xB0)
        for k, pi in enumerate((5, 6)):
            pa = struct.unpack_from("<8H", rom, PAL3_PTRS)[pi]
            for c, v in enumerate(rom[pa + 16: pa + 32]):
                bank_s2[0x1F00 + 48 * k + c * 3: 0x1F00 + 48 * k + c * 3 + 3] = bytes(sms_rgb(v))
    bank_s2[0x2000: 0x4000] = pack4(spr_tiles)
    robo_tiles = planar_to_8bpp(decode_hy_art(rom, ROBO_ART), 128)
    if a.level.startswith(("sbz", "sky")):  # M6.9: Robotnik (zadanie grafiki 4 - render/sprites.asm art_tiles: bank v_pbzspr, $0000); M6.10: zappery $46 SKY3
        bank_s2[0x0000: 0x1000] = pack4(robo_tiles)
    (out / "bank_sprites.bin").write_bytes(bytes(bank_s2))

    inc = f"""; wygenerowane przez tools/extract_sms.py --level {a.level} - nie edytowac
LV_WIDTH      = {width}
LV_HEIGHT     = {height}
LV_CAM_X0     = {x0}
LV_CAM_X1     = {x1}
LV_CAM_Y0     = {y0}
LV_CAM_Y1     = {y1}
LV_START_BX   = {start_bx}
LV_START_BY   = {start_by}
LV_NBLOCKS    = {n_blocks}
LV_NTILES     = {min(n_tiles, 256)}
LV_CYC_SPEED  = {cyc_speed}
LV_CYC_COUNT  = {cyc_count}
LV_CYC_START  = {cyc_start}
LB_TILEMAP    = $0000
LB_PRIO       = $0C00
LB_PALS       = $0D00
LB_LAYOUT     = $1000
LB_BALL       = $2000
LB_HDR        = $2400       ; {HEADER_COPY} B naglowka (g_level_header_copy)
LB_TIME       = $2428       ; 3 B LUT_normal_stage_start_time
LB_PALPTR     = $242B       ; adres SMS palety startowej (g_SIG00b3_palette_addr)
LB_CYCPTR     = $242D       ; adres SMS palet cyklu (g_palette_cycle_baseptr)
LB_OBJCNT     = $242F       ; liczba obiektow listy poziomu (g_object_count)
LB_TIME_CP    = $2430       ; 3 B czasu startu od punktu kontrolnego (00:2402)
LB_TFPTR      = $2434       ; adres SMS tablicy flag blokow strefy (PTRLUT_level_tile_flags 00:3A65)
LB_OBJLIST    = $2440       ; lista obiektow poziomu: N, potem N-1 trojek (typ, X/32, Y/32)
LB_DEMO       = $2500       ; 256 B od ARRAY_demo_inputs
LB_TILEFLAGS  = $2600       ; 256 B flag blokow strefy (bity 0-5 typ kolizji, bit 7 priorytet)
LB_PHYS       = $2700       ; 4 KiB tablic kolizji dla PHYS_RAM $C000 (wspolczynniki, wskazniki, profile)
LB_SONIC      = $3700       ; 1 KiB danych Sonica dla SONIC_RAM $F000 (fizyka, bloki specjalne, animacje)
LB_RINGART    = $3B00       ; 6 klatek pierscienia 16x16 (2 piksele/bajt, 128 B/klatke)
LB_RINGMASK   = $3E00       ; 256 B: polowki z pierscieniem w bloku (b0 lewa, b1 prawa; wiersze 8-23)
LB_BLKMAP     = $0E00       ; M6.9: 256 B - slot magazynu blokow dla numeru bloku (tozsamosc do 184 blokow strefy)
LB_HDRALT     = $3F00       ; M6.9: kopie naglowkow pod-poziomow $16-$19 (po $40 B; SBZ2 i $14 - bez wody, paleta podwodna nieuzywana)
LB_LIGHT1B    = $2500       ; M6.10: SKY1 - zestaw palet cyklu blyskawic 1B (4 x 48 B RGB jak LB_PALS + 48)
LB_LIGHT1C    = $3F00       ; M6.10: SKY1 - zestaw 1C
LB_STASH3     = $3F00       ; M6.10: bank SKY3 - kopia bloku na poziom SKY3 (256 B od LB_HDR)
LB_STASH1A    = $0F00       ; M6.10: bank SKY3 - kopia bloku na poziom pod-poziomu $1A
LB_STASHG1    = $0F00       ; M6.11: bank GHZ1 - kopia bloku na poziom GHZ1
LB_STASH12    = $3F00       ; M6.11: bank GHZ1 - kopia bloku na poziom poziomu koncowego $12
LV_NSLOTS     = {len(blkslot)}
LB_WATERPAL   = $3F00       ; M6.8: 32 x RGB palety podwodnej (zera, gdy poziom bez wody)
LV_SONIC_FR   = {SONIC_FRAMES}          ; klatek Sonica w prawo (bank_sonic.bin, 384 B/klatke)
LV_SONIC_OWN  = {len(own)}          ; klatek w lewo niebedacych lustrem prawych (bank_sprites.bin od $0000)
LS_FRTAB      = $1F00       ; bank_sprites.bin: 84 x (mid, hi | $80 = odbicie) adresu obrazu klatki w VRAM
LS_PALSPR     = $1FB0       ; bank_sprites.bin: paleta sprite'ow SMS (16 x RGB) -> kolory VBXE 16-31
LS_SPRTILES   = $2000       ; bank_sprites.bin: 256 kafli sprite'ow strefy 8x8 (32 B/kafel)
"""
    (out / "level.inc").write_text(inc, encoding="ascii")

    # --- M4.0: banki obiektów (wspólne dla poziomów: build/assets) - bank 45 dane, bank 47 grafika ---
    obj_img, raport = objects_bank(rom)
    art_img, n_sign, r2 = objart_bank(rom)
    (out.parent / "bank_objdata.bin").write_bytes(obj_img)
    objz_img, raport_z = objz_bank(rom)
    (out.parent / "bank_objz.bin").write_bytes(objz_img)
    objz2_img, raport_z2 = objz2_bank(rom)
    (out.parent / "bank_objz2.bin").write_bytes(objz2_img)
    raport_z += raport_z2
    objz3_img, raport_z3 = objz2_bank(rom, OBJZ3_SPANS, 3)        # M6.10: PB_OBJZ3 (Sky Base)
    (out.parent / "bank_objz3.bin").write_bytes(objz3_img)
    raport_z += raport_z3
    raport += raport_z
    (out.parent / "bank_objart.bin").write_bytes(art_img)
    boss_img, boss_tiles, caps_tiles, boss_pal = boss_bank(rom)
    (out.parent / "bank_boss.bin").write_bytes(boss_img)
    (out.parent / "objdata.inc").write_text(objdata_inc(n_sign, rom), encoding="ascii")
    (out.parent / "objbounds.inc").write_text(bounds_inc(rom), encoding="ascii")
    boss3_tiles = planar_to_8bpp(decode_hy_art(rom, BOSS3_ART), 128)
    np.savez_compressed(out / "level.npz", boss_tiles=boss3_tiles if a.level in ("bri3", "lab3") else robo_tiles if a.level.startswith(("sbz", "sky")) else boss_tiles,   # model obrazu: grafika bossa strefy
                        # (M6.8: boss LAB3 ma grafike bossa BRI3 - ART_0C_E508, objfunc_49 02:9267)
                        caps_tiles=caps_tiles, boss3_tiles=boss3_tiles,
                        pal_boss=np.frombuffer(boss_pal, np.uint8),
                        level=level, prio_mask=prio_mask, ball=ball,
                        pal_bg=np.frombuffer(pal_bg, np.uint8), layout=lay, prio=np.frombuffer(prio, np.uint8),
                        blocks=blocks, tilemap=tm, tiles=tiles, ring_frames=rings, ring_mask=ring_mask,
                        blkslot=np.array(blkslot, np.uint8),   # M6.9: numer bloku w slocie magazynu
                        sonic_r=right, sonic_l=left, spr_tiles=spr_tiles, pal_spr=np.frombuffer(pal_spr, np.uint8),
                        sonic_region=np.frombuffer(sms_read(rom, SONIC_ANIM_FROM, SONIC_ANIM_TO - SONIC_ANIM_FROM),
                                                   np.uint8))

    print(f"poziom {a.level}: nagłówek @{h:#x}, {width}x{height} bloków, kamera x {x0}..{x1} y {y0}..{y1}, "
          f"start ({start_bx},{start_by})")
    print(f"bloki: {n_blocks} (flagi @{tf_addr:#x}, priorytet: {sum(prio)}), kafle: {n_tiles}, "
          f"układ: {lay_size} B -> 4096 B, użyte bloki: {len(np.unique(lay))}")
    print(f"paleta tła @{pal3_addr:#x}, cykl @{cyc_addr:#x} x{cyc_count} co {cyc_speed} ramek")
    print(f"kolizje: {phys_info['profile']} profili 32 B, wskaźników poza ROM: {phys_info['wskazniki_do_ram']}, "
          f"typy kolizji w strefie: {sorted(set(f & 0x3F for f in tileflags))}")
    zone_ring = np.block([[tiles[0xFC], tiles[0xFD]], [tiles[0xFE], tiles[0xFF]]]) if len(tiles) == 256 else None
    same = [k for k in range(6) if zone_ring is not None and np.array_equal(zone_ring, rings[k])]
    print(f"pierścień: 6 klatek z 0B:{RING_ART:04X}, kafle $FC-$FF grafiki strefy = klatka {same or 'żadna'}, "
          f"bloki z pierścieniami: {[int(k) for k in np.flatnonzero(ring_mask)]}")
    print(f"Sonic: {SONIC_FRAMES} klatek w prawo, w lewo własnych {len(own)} {own} (reszta = lustro), "
          f"sprite'y: {n_spr} kafli strefy z {spr_bank:02X}:{spr_ptr:04X}, {n_com} wspólnych od $80")
    for r in raport + r2:
        print(r)
    print(f"OK: {out}")
    return 0


if __name__ == "__main__":
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main(sys.argv[1:]))
