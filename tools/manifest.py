#!/usr/bin/env python3
"""Manifest stref i banków (M7.1, docs/plan-m7.md §1.1): jedno źródło prawdy o tym, który obraz banku 16 KB należy do którego
poziomu (g_level) – dla XEX 1088K (generowane tablice zn_* i segmenty banków aktu) i dla nośników 320K (pakiety zx02 cartu i ATR:
tools/pack_zone.py, sloty zestawu roboczego §1.3).

Wyjścia (build/assets/, katalog w ścieżkach include MADS-a):
  ldr_tables.inc – M7.2 (src/ldr/ldr.asm): ZONE_N, SUB_*, stałe LI_* (identyfikator obrazu: XEX - stała PORTB banku rezydentnego, nośnik -
                   id 1..63), tablice ról poziomu ldr_lvl[27][4] i pod-poziomów ldr_sub[7][2] (wpis: XEX - PORTB, nośnik - id | LDR_ALT),
                   ldr_role_pb / ldr_role_slot / ldr_slot_pb (nośnik) - zastępuje zn_tables.inc i zn_sub.inc z M7.1
  lvbanks.inc    – segmenty XEX banków aktu (dawne src/game_lvbanks.asm; src/game.asm – na początku XEX-a testowego, w wydaniu po mapie)
  manifest.json  – obrazy banków (z id), role poziomów (ldr), potrzeby poziomów (obraz -> slot nośnika, wyprowadzane z ról), pakiety,
                   kolejność gry (tools/pack_zone.py, sprawdz_xex.py)
Tablice XEX dają dokładnie dzisiejsze wartości PORTB (zn_* z M7.1 i stałe lvs_sp z lv_select) - zachowanie XEX bez zmian.

Role (M7.2, docs/plan-m7-ldr.md §4.2, review M7.1 R1): dla każdego poziomu 4 role - poziom, atlas, sprite'y strefy, obiekty strefy
(kolejność = zmienne v_pblevel, v_pbatlas, v_pbzspr, v_pbobjz) -> (obraz, slot). Rola ma dwa sloty (alt 0 / alt 1): poziom LEVEL / LEVEL2,
atlas ATLAS / ATLAS2, sprite'y ZSPR / stały bank 39, obiekty OBJZ / LEVEL2. Indeks poziomu lv_idx: g_level 0-$12 -> 0-18, etap
$1C-$23 -> 19-26 (lv_select). Pod-poziomy $14-$1A (iy_06 b4 w SBZ2 / SKY2) - tablica ldr_sub: rola poziom (zawsze) i atlas (0 = z aktu).

Kontrola: każda stała PB_* / PB_LD_* z src/kernel/mem.inc użyta w manifeście musi wskazywać bank manifestu (PB_LD = PB | 1, OS on),
PB_SL_* - bank slotu z SLOTY; w każdym poziomie role w różnych slotach, obraz tylko w swoim slocie albo ALT_SLOT.

Użycie:  python tools/manifest.py   (po extract_sms.py / pack_special.py; kod 0 = zapisane)
"""
from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
A = ROOT / "build" / "assets"
MEM_INC = ROOT / "src" / "asm" / "kernel" / "mem.inc"

# --- sloty zestawu roboczego 320K (docs/plan-m7.md §1.3): banki nieparzyste 33-63, bity 1 i 7 PORTB = 1 ---
SLOTY = {"ATLAS": 33, "LEVEL": 35, "ZSPR": 55, "OBJZ": 57, "LEVEL2": 61, "ATLAS2": 63}
ALT_SLOT = {"objz3": "LEVEL2"}     # drugi dozwolony slot obrazu (bit „alt” w tablicy poziomów ldr - M7.2): obiekty etapów specjalnych
ZESTAW_MAX = 16                    # 320K RAMBO: 16 banków 33-63


@dataclass(frozen=True)
class Obraz:
    """Obraz banku 16 KB: bank w XEX 1088K, stała PORTB (OS off) z mem.inc, plik w build/assets (None = obraz składany przez MADS:
    dane z ROM-u + kod obiektów w lukach, ekrany) i slot nośnika 320K: None = obraz stały (grupa COMMON, wgrywany raz przy starcie
    do tego samego banku 37-59), inaczej nazwa slotu z SLOTY - obraz doczytywany tam, gdy potrzebuje go poziom (stały slot obrazu:
    ldr zna miejsce bez tablicy potrzeb; pod-poziomy SBZ2 $14/$15 w LEVEL2, żeby bank SBZ2 zostawał w LEVEL na $16/$18/$19)."""
    bank: int
    pb: str
    plik: str | None
    slot: str | None
    opis: str
    tylko_xex: bool = False        # M7.3: obraz tylko w XEX 1088K - na nośniku 320K jego dane leżą w bankach stałych (bank 36, NOSNIK_SKLAD)
    nosnik_dl: int | None = None   # M7.3: na nośniku 320K z pliku tylko pierwsze n B (dalej dane banku 36; reszta pliku = zera - pack_cart.py)

    @property
    def staly(self) -> bool:
        """Obraz stały nośnika 320K (wgrywany raz przy starcie - ldr_init, tablica ldr_const)."""
        return self.slot is None and not self.tylko_xex


# Wszystkie banki XEX wydania (49/64 po M6.11). Kolejność bez znaczenia - kolejność segmentów XEX: LVBANKS niżej.
OBRAZY: dict[str, Obraz] = {
    # stałe (w obu buildach z src/game.asm; na nośniku pakiet wspólny, te same banki 37-59)
    "sonic":     Obraz(37, "PB_SONIC",  "ghz1/bank_sonic.bin",   None, "klatki Sonica w prawo"),
    "spr":       Obraz(39, "PB_SPR",    "ghz1/bank_sprites.bin", None, "klatki w lewo, tablica klatek, sprite'y GHZ"),
    "music":     Obraz(41, "PB_MUSIC",  "music/bank_music.bin",  None, "muzyka (LZSS16)", nosnik_dl=0x3700),
    "sfx":       Obraz(43, "PB_SFX",    None,                    None, "efekty + dane mapy 2 ($6000)"),
    "obj":       Obraz(45, "PB_OBJ",    None,                    None, "kod i dane obiektów banku 1 ROM-u"),
    "objart":    Obraz(47, "PB_OBJART", None,                    None, "grafika obiektów, boss BRI3/LAB3"),
    "scr":       Obraz(49, "PB_SCR",    None,                    None, "kod i dane ekranów (wydanie)"),
    "scra":      Obraz(51, "PB_SCRA",   "ekrany/bank_ekr_atlasy.bin",  None, "kafle tytułu i mapy 1"),
    "scrb":      Obraz(53, "PB_SCRB",   "ekrany/bank_ekr_atlasy2.bin", None, "kafle wyniku i mapy 2"),
    "boss":      Obraz(59, "PB_BOSS",   "bank_boss.bin",         None, "boss GHZ3, zwierzęta, sprite'y etapów specjalnych",
                       nosnik_dl=0x3100),
    # M6.11: bank 36 (parzysty - poza zestawem 320K): dane tytułu/mapy 1 i końca gry. M7.3: tylko XEX 1088K (i RAMCART) - na nośniku 320K
    # rozpuszczony w bankach stałych 43 / 59 / 41 (NOSNIK_SKLAD; src/game.asm .if NOSNIK_320), zestaw roboczy 16/16 bez niego
    "scrc":      Obraz(36, "PB_SCRC",   None,                    None,    "dane tytułu, mapy 1 i ekranów końca (wydanie)", tylko_xex=True),
    # banki obiektów strefy (kod w lukach danych banku 2 ROM-u)
    "objz":      Obraz(11, "PB_OBJZ",   None,                    "OBJZ",  "obiekty strefy BRI/JUN/LAB"),
    "objz2":     Obraz(2,  "PB_OBJZ2",  None,                    "OBJZ",  "obiekty strefy SBZ"),
    "objz3":     Obraz(30, "PB_OBJZ3",  None,                    "OBJZ",  "obiekty strefy SKY, $12, etapów specjalnych"),
    # Green Hill
    "atlas_ghz": Obraz(33, "PB_ATLAS",   "ghz1/bank_atlas.bin",  "ATLAS",  "atlas GHZ"),
    "lv_ghz1":   Obraz(35, "PB_LEVEL",   "ghz1/bank_level.bin",  "LEVEL",  "GHZ1 (+ blok $12)"),
    "lv_ghz2":   Obraz(55, "PB_LEVEL2",  "ghz2/bank_level.bin",  "LEVEL",  "GHZ2"),
    "lv_ghz3":   Obraz(57, "PB_LEVEL3",  "ghz3/bank_level.bin",  "LEVEL",  "GHZ3"),
    # etapy specjalne
    "atlas_sp":  Obraz(61, "PB_ATLASSP",  "special/bank_atlas.bin",  "ATLAS2", "atlas etapów specjalnych"),
    "lv_sp":     Obraz(63, "PB_LEVELSP",  "special/bank_level.bin",  "LEVEL", "etapy $1C-$1E, $20-$22"),
    "lv_sp2":    Obraz(32, "PB_LEVELSP2", "special2/bank_level.bin", "LEVEL", "etapy pionowe $1F, $23"),
    # Bridge
    "atlas_bri": Obraz(1,  "PB_ATLASB",  "bri1/bank_atlas.bin",   "ATLAS", "atlas Bridge"),
    "spr_bri":   Obraz(3,  "PB_SPRB",    "bri1/bank_sprites.bin", "ZSPR", "sprite'y Bridge"),
    "lv_bri1":   Obraz(5,  "PB_LEVELB1", "bri1/bank_level.bin",   "LEVEL", "BRI1"),
    "lv_bri2":   Obraz(7,  "PB_LEVELB2", "bri2/bank_level.bin",   "LEVEL", "BRI2"),
    "lv_bri3":   Obraz(9,  "PB_LEVELB3", "bri3/bank_level.bin",   "LEVEL", "BRI3"),
    # Jungle
    "atlas_jun": Obraz(13, "PB_ATLASJ",  "jun1/bank_atlas.bin",   "ATLAS", "atlas Jungle"),
    "spr_jun":   Obraz(15, "PB_SPRJ",    "jun1/bank_sprites.bin", "ZSPR", "sprite'y Jungle"),
    "lv_jun1":   Obraz(17, "PB_LEVELJ1", "jun1/bank_level.bin",   "LEVEL", "JUN1"),
    "lv_jun2":   Obraz(19, "PB_LEVELJ2", "jun2/bank_level.bin",   "LEVEL", "JUN2 (pionowy)"),
    "lv_jun3":   Obraz(21, "PB_LEVELJ3", "jun3/bank_level.bin",   "LEVEL", "JUN3"),
    # Labyrinth
    "atlas_lab": Obraz(23, "PB_ATLASL",  "lab1/bank_atlas.bin",   "ATLAS", "atlas Labyrinth"),
    "spr_lab":   Obraz(25, "PB_SPRL",    "lab1/bank_sprites.bin", "ZSPR", "sprite'y Labyrinth"),
    "lv_lab1":   Obraz(27, "PB_LEVELL1", "lab1/bank_level.bin",   "LEVEL", "LAB1"),
    "lv_lab2":   Obraz(29, "PB_LEVELL2", "lab2/bank_level.bin",   "LEVEL", "LAB2"),
    "lv_lab3":   Obraz(31, "PB_LEVELL3", "lab3/bank_level.bin",   "LEVEL", "LAB3"),
    # Scrap Brain
    "atlas_sbz": Obraz(4,  "PB_ATLASS",  "sbz1/bank_atlas.bin",   "ATLAS", "atlas Scrap Brain"),
    "spr_sbz":   Obraz(6,  "PB_SPRS",    "sbz1/bank_sprites.bin", "ZSPR", "sprite'y Scrap Brain"),
    "lv_sbz1":   Obraz(8,  "PB_LEVELS1", "sbz1/bank_level.bin",   "LEVEL", "SBZ1"),
    "lv_sbz2":   Obraz(10, "PB_LEVELS2", "sbz2/bank_level.bin",   "LEVEL", "SBZ2 (+ $16, $18, $19)"),
    "lv_sbz3":   Obraz(12, "PB_LEVELS3", "sbz3/bank_level.bin",   "LEVEL", "SBZ3"),
    "lv_sbz2a":  Obraz(14, "PB_LEVELS4", "sbz2a/bank_level.bin",  "LEVEL2", "pod-poziom $14 (+ $17)"),
    "lv_sbz2b":  Obraz(16, "PB_LEVELS5", "sbz2b/bank_level.bin",  "LEVEL2", "pod-poziom $15"),
    # Sky Base
    "atlas_sky": Obraz(18, "PB_ATLASK",  "sky1/bank_atlas.bin",   "ATLAS", "atlas SKY1/2"),
    "atlas_sky3": Obraz(20, "PB_ATLASK3", "sky3/bank_atlas.bin",  "ATLAS", "atlas SKY3 i $1A"),
    "spr_sky":   Obraz(22, "PB_SPRK",    "sky1/bank_sprites.bin", "ZSPR", "sprite'y Sky Base"),
    "lv_sky1":   Obraz(24, "PB_LEVELK1", "sky1/bank_level.bin",   "LEVEL", "SKY1"),
    "lv_sky2":   Obraz(26, "PB_LEVELK2", "sky2/bank_level.bin",   "LEVEL", "SKY2"),
    "lv_sky3":   Obraz(28, "PB_LEVELK3", "sky3/bank_level.bin",   "LEVEL", "SKY3 (+ blok $1A)"),
}

# M7.3: skład obrazów stałych nośnika 320K inny niż w XEX 1088K - dane banku 36 ("scrc", tylko XEX) w wolnych końcach banków stałych
# (adresy SCD_* w src/kernel/mem.inc, segmenty w src/game.asm pod .if NOSNIK_320, kopie: src/scr/boot.asm scr_data_copy / ko_copy).
# Obrazy nośnika powstają z XEX-a buildu nośnika (build/sonic-cart-*.xex - tools/pack_cart.py), więc mają te dane; tu tylko opis.
NOSNIK_SKLAD = {
    "sfx":   ["$3300 ekr_spr_tytul.bin (pary kafli sprite'ow tytulu)", "$3700 ekr_rle_tytul.bin", "$3900 ekr_rle_mapa1a.bin + ekr_rle_mapa1b.bin"],
    "music": ["$3700 koniec_r0.bin (ekrany konca)"],
    "boss":  ["$3100 koniec_ram.bin + koniec_spin.bin (ekrany konca)"],
}

# --- poziomy: g_level -> obrazy (M7.2: tablica ról ldr_lvl - dawne zn_atlas, zn_level, zn_spr, zn_objz; ZONE_N = 19 wpisów 0-18) ---
STREFY = [  # (g_level, nazwa, atlas, poziom, sprite'y strefy, obiekty strefy)
    (0x00, "GHZ1", "atlas_ghz", "lv_ghz1", "spr", "objz"), (0x01, "GHZ2", "atlas_ghz", "lv_ghz2", "spr", "objz"),
    (0x02, "GHZ3", "atlas_ghz", "lv_ghz3", "spr", "objz"),
    (0x03, "BRI1", "atlas_bri", "lv_bri1", "spr_bri", "objz"), (0x04, "BRI2", "atlas_bri", "lv_bri2", "spr_bri", "objz"),
    (0x05, "BRI3", "atlas_bri", "lv_bri3", "spr_bri", "objz"),
    (0x06, "JUN1", "atlas_jun", "lv_jun1", "spr_jun", "objz"), (0x07, "JUN2", "atlas_jun", "lv_jun2", "spr_jun", "objz"),
    (0x08, "JUN3", "atlas_jun", "lv_jun3", "spr_jun", "objz"),
    (0x09, "LAB1", "atlas_lab", "lv_lab1", "spr_lab", "objz"), (0x0A, "LAB2", "atlas_lab", "lv_lab2", "spr_lab", "objz"),
    (0x0B, "LAB3", "atlas_lab", "lv_lab3", "spr_lab", "objz"),
    (0x0C, "SBZ1", "atlas_sbz", "lv_sbz1", "spr_sbz", "objz2"), (0x0D, "SBZ2", "atlas_sbz", "lv_sbz2", "spr_sbz", "objz2"),
    (0x0E, "SBZ3", "atlas_sbz", "lv_sbz3", "spr_sbz", "objz2"),
    (0x0F, "SKY1", "atlas_sky", "lv_sky1", "spr_sky", "objz3"), (0x10, "SKY2", "atlas_sky", "lv_sky2", "spr_sky", "objz3"),
    (0x11, "SKY3", "atlas_sky3", "lv_sky3", "spr_sky", "objz3"),
    (0x12, "KONIEC", "atlas_ghz", "lv_ghz1", "spr", "objz3"),      # M6.11: poziom końcowy $12 (bank GHZ1 z kopią bloku $12)
]
# GHZ nie używa banku obiektów strefy (zn_objz = PB_OBJZ tylko dla jednolitości) - na nośniku bez potrzeby ładowania
BEZ_OBJZ = {0x00, 0x01, 0x02}

# pod-poziomy (lv_select: iy_06 b4, g_next_level_override_target $14-$1A -> ldr_sub); atlas / sprite'y / obiekty - z aktu (SBZ2, SKY2)
POD = [  # (cel, nazwa, poziom, atlas zamiast atlasu aktu albo None)
    (0x14, "SBZ2 $14", "lv_sbz2a", None), (0x15, "SBZ2 $15", "lv_sbz2b", None), (0x16, "SBZ2 $16", "lv_sbz2", None),
    (0x17, "SBZ2 $17", "lv_sbz2a", None), (0x18, "SBZ2 $18", "lv_sbz2", None), (0x19, "SBZ2 $19", "lv_sbz2", None),
    (0x1A, "SKY2 $1A", "lv_sky3", "atlas_sky3"),
]
POD_AKT = {0x14: 0x0D, 0x15: 0x0D, 0x16: 0x0D, 0x17: 0x0D, 0x18: 0x0D, 0x19: 0x0D, 0x1A: 0x10}

# etapy specjalne $1C-$23 (lv_select: lvs_sp) - atlas 61, sprite'y z banku 39/59, obiekty banku 30, poziom 63 albo 32 (pionowe).
# Obiekty etapów (bank 30) na nośniku w slocie LEVEL2 (docs/plan-m7-ldr.md §4.6): w GHZ-LAB LEVEL2 jest wolny, bank 11 zostaje w OBJZ -
# powrót z etapu bez ładowania obiektów strefy (ok. 60 KB ładowania mniej w całej grze); SKY i $12 - bank 30 w OBJZ jak zwykle
SPECJALNE = [(0x1C, "lv_sp"), (0x1D, "lv_sp"), (0x1E, "lv_sp"), (0x1F, "lv_sp2"),
             (0x20, "lv_sp"), (0x21, "lv_sp"), (0x22, "lv_sp"), (0x23, "lv_sp2")]

# kolejność gry (trainer CRK_SEL w kolejności rzeczywistej - M6.11; etap specjalny po aktach 1 i 2 każdej strefy przy 50 pierścieniach)
KOLEJNOSC = [0x00, 0x1C, 0x01, 0x1D, 0x02, 0x03, 0x1E, 0x04, 0x1F, 0x05, 0x06, 0x20, 0x07, 0x21, 0x08,
             0x09, 0x22, 0x0A, 0x23, 0x0B, 0x0C, 0x0D, 0x14, 0x15, 0x0E, 0x0F, 0x10, 0x1A, 0x11, 0x12]

# --- segmenty XEX banków aktu (lvbanks.inc = dawne src/game_lvbanks.asm): kolejność i komentarze jak przed M7.1 ---
LVBANKS = [
    ("; banki aktu (GHZ1-GHZ3): 33 atlas kafli tla, 35 / 55 / 57 dane poziomu, 59 grafika bossa i etapow specjalnych", None),
    (None, "atlas_ghz"), (None, "lv_ghz1"),
    ("; M6.3: bank 55 - dane poziomu GHZ2 (ten sam uklad co bank 35; atlas, klatki Sonica i sprite'y strefy wspolne z GHZ1)", None),
    (None, "lv_ghz2"),
    ("; M6.4: bank 57 - dane poziomu GHZ3 (boss, kapsula)", None), (None, "lv_ghz3"),
    ("; M6.4: bank 59 - grafika bossa GHZ3 ($0000), zwierzat i kapsuly ($1000) 4 bpp, paleta bossa RGB ($2000)", None), (None, "boss"),
    ("; M6.5: bank 61 - atlas kafli tla etapow specjalnych (8 bpp, 256 kafli), bank 63 - dane poziomu etapow specjalnych $1C, $1D\n"
     "; (ten sam uklad LB_*; tools/pack_special.py). Grafika sprite'ow etapow specjalnych i paleta: bank 59 ($2100, $2030).", None),
    (None, "atlas_sp"), (None, "lv_sp"),
    ("; M6.11: etapy specjalne pionowe $1F / $23 (16 x 256, flipper $4C) - bank 32 (tools/pack_special.py: special2/bank_level.bin)", None),
    (None, "lv_sp2"),
    ("; M6.6: strefa Bridge (BRI1-3): bank 1 - atlas kafli tla, bank 3 - kafle i paleta sprite'ow strefy (uklad jak bank 39; klatki Sonica\n"
     "; zostaja w banku 39), banki 5, 7, 9 - dane poziomu BRI1-3 (tools/extract_sms.py --level bri1..bri3). Banki 1-31: tylko 1088K.", None),
    (None, "atlas_bri"), (None, "spr_bri"), (None, "lv_bri1"), (None, "lv_bri2"), (None, "lv_bri3"),
    ("; M6.7: strefa Jungle (JUN1-3): bank 13 - atlas, bank 15 - kafle i paleta sprite'ow strefy, banki 17, 19, 21 - dane poziomu JUN1-3", None),
    (None, "atlas_jun"), (None, "spr_jun"), (None, "lv_jun1"), (None, "lv_jun2"), (None, "lv_jun3"),
    ("; M6.8: strefa Labyrinth (LAB1-3): bank 23 - atlas, bank 25 - kafle i paleta sprite'ow strefy (ART_09_83B6), banki 27, 29, 31 - LAB1-3", None),
    (None, "atlas_lab"), (None, "spr_lab"), (None, "lv_lab1"), (None, "lv_lab2"), (None, "lv_lab3"),
    ("; M6.9: strefa Scrap Brain (SBZ1-3 i pod-poziomy SBZ2 $14, $15) - banki parzyste: 4 atlas, 6 kafle i paleta sprite'ow strefy (09:8F75),\n"
     "; 8 / 10 / 12 SBZ1-3, 14 = $14, 16 = $15", None),
    (None, "atlas_sbz"), (None, "spr_sbz"), (None, "lv_sbz1"), (None, "lv_sbz2"), (None, "lv_sbz3"), (None, "lv_sbz2a"), (None, "lv_sbz2b"),
    ("; M6.10: strefa Sky Base (SKY1-3, pod-poziom $1A w banku SKY3) - banki parzyste: 18 atlas SKY1/2, 20 atlas SKY3, 22 kafle i palety\n"
     "; sprite'ow strefy (09:99E0 + Robotnik), 24 / 26 / 28 SKY1-3", None),
    (None, "atlas_sky"), (None, "atlas_sky3"), (None, "spr_sky"), (None, "lv_sky1"), (None, "lv_sky2"), (None, "lv_sky3"),
]

# --- pakiety nośnika (docs/plan-m7.md §1.2; typ: 0 strefa, 1 akt, 2 wspólny). Obraz -> slot wg potrzeb poziomu (POTRZEBY niżej) ---
PAKIETY = [  # (nazwa 8.3 bez rozszerzenia, typ, obrazy)
    ("COMMON", 2, ["sonic", "spr", "music", "sfx", "obj", "objart", "scr", "scra", "scrb", "boss"]),
    ("SCRC", 2, ["scrc"]),
    ("GHZ", 0, ["atlas_ghz"]), ("SS", 0, ["atlas_sp"]),
    ("BRI", 0, ["atlas_bri", "spr_bri"]), ("JUN", 0, ["atlas_jun", "spr_jun"]), ("LAB", 0, ["atlas_lab", "spr_lab"]),
    ("SBZ", 0, ["atlas_sbz", "spr_sbz"]), ("SKY", 0, ["atlas_sky", "spr_sky"]), ("SKY3ATL", 0, ["atlas_sky3"]),
    ("OBJZ", 0, ["objz"]), ("OBJZ2", 0, ["objz2"]), ("OBJZ3", 0, ["objz3"]),
] + [(n.removeprefix("lv_").upper(), 1, [n]) for n in OBRAZY if n.startswith("lv_")]


# --- M7.2: role obrazów poziomu dla ldr (docs/plan-m7-ldr.md §4.2-4.3; review M7.1 R1) ---
ROLE = ("poziom", "atlas", "zspr", "objz")          # = LR_LEVEL, LR_ATLAS, LR_ZSPR, LR_OBJZ (src/kernel/mem.inc), v_pblevel.. (src/vars.asm)
ROLA_SLOT = {"poziom": ("LEVEL", "LEVEL2"), "atlas": ("ATLAS", "ATLAS2"), "zspr": ("ZSPR", None), "objz": ("OBJZ", "LEVEL2")}
ROLA_STALY = {"zspr": "spr"}                        # alt 1 roli bez drugiego slotu = obraz stały (bank 39: GHZ, $12, etapy specjalne)
LDR_ALT = 0x80                                      # bit alt we wpisie tablicy ról (nośnik); id obrazu w bitach 0-5
ID: dict[str, int] = {n: i + 1 for i, n in enumerate(OBRAZY)}   # id obrazu 1..63 (0 = brak obrazu / rola nieużywana); kolejność OBRAZY


def _wpis(rola: str, n: str | None, slot: str | None = None) -> tuple[str, str | None, int] | None:
    """(obraz, slot nośnika, alt) dla roli; slot domyślnie = slot obrazu (stały: None). Błąd, gdy obraz nie pasuje do slotów roli."""
    if n is None:
        return None
    o = OBRAZY[n]
    s = o.slot if slot is None else slot
    if s is not None and s != o.slot and ALT_SLOT.get(n) != s:
        raise ValueError(f"rola {rola}: obraz {n} w slocie {s} (dozwolone {o.slot} / {ALT_SLOT.get(n)})")
    sloty = ROLA_SLOT[rola]
    if s is None:
        if ROLA_STALY.get(rola) != n:
            raise ValueError(f"rola {rola}: obraz stały {n} bez wpisu w ROLA_STALY")
        return n, None, 1
    if s not in sloty:
        raise ValueError(f"rola {rola}: slot {s} spoza {sloty}")
    return n, s, sloty.index(s)


def ldr_poziomy() -> list[tuple[str, dict[str, tuple[str, str | None, int] | None]]]:
    """lv_idx 0..26 -> (nazwa, {rola: (obraz, slot, alt) | None}). Akty i $12 z STREFY (GHZ bez obiektów strefy: rola pusta na nośniku),
    etapy specjalne $1C-$23: atlas etapów (ATLAS2), sprite'y = stały bank 39, obiekty = bank 30 w LEVEL2 (ALT_SLOT, §4.6)."""
    w = []
    for g, nz, atlas, lv, spr, objz in STREFY:
        w.append((nz, {"poziom": _wpis("poziom", lv), "atlas": _wpis("atlas", atlas), "zspr": _wpis("zspr", spr),
                       "objz": None if g in BEZ_OBJZ else _wpis("objz", objz)}))
    for e, lv in SPECJALNE:
        w.append((f"${e:02X}", {"poziom": _wpis("poziom", lv), "atlas": _wpis("atlas", "atlas_sp"), "zspr": _wpis("zspr", "spr"),
                                "objz": _wpis("objz", "objz3", ALT_SLOT["objz3"])}))
    return w


def ldr_pod() -> list[tuple[str, dict[str, tuple[str, str | None, int] | None]]]:
    """Pod-poziomy $14-$1A -> (nazwa, {poziom: wpis, atlas: wpis | None (= atlas aktu)}). $14/$15/$17 - LEVEL2 (bank SBZ2 zostaje w LEVEL
    na $16/$18/$19 bez ładowania), $1A - bank SKY3 w LEVEL i atlas SKY3 (SKY3 potem bez ładowania)."""
    return [(nz, {"poziom": _wpis("poziom", lv), "atlas": _wpis("atlas", at) if at else None}) for _, nz, lv, at in POD]


def potrzeby() -> dict[int, dict[str, str]]:
    """g_level / cel pod-poziomu / etap -> {slot: obraz} na nośniku 320K (obrazy stałe pominięte - są zawsze). M7.2: wyprowadzane z ról
    (ldr_poziomy, ldr_pod); pod-poziom = role aktu z podmienionym poziomem (i atlasem $1A)."""
    def sl(role: dict) -> dict[str, str]:
        return {w[1]: w[0] for w in role.values() if w is not None and w[1] is not None}
    poz = ldr_poziomy()
    w: dict[int, dict[str, str]] = {}
    for i, (g, *_r) in enumerate(STREFY):
        w[g] = sl(poz[i][1])
    for k, (e, _) in enumerate(SPECJALNE):
        w[e] = sl(poz[len(STREFY) + k][1])
    for (cel, *_r), (_, rp) in zip(POD, ldr_pod()):
        role = dict(poz[POD_AKT[cel]][1])
        role["poziom"] = rp["poziom"]
        if rp["atlas"]:
            role["atlas"] = rp["atlas"]
        w[cel] = sl(role)
    return w


def ldr_ladowane() -> list[str]:
    """Obrazy, które ldr_need doczytuje do slotów (role ze slotem) - zawartość RAMCART / cartu / dyskietek poza obrazami stałymi."""
    n = {w[0] for _, r in ldr_poziomy() + ldr_pod() for w in r.values() if w is not None and w[1] is not None}
    return [x for x in OBRAZY if x in n]


def pb_z_mem_inc() -> dict[str, int]:
    w = {}
    for m in re.finditer(r"^(PB_\w+)\s*=\s*\$([0-9A-Fa-f]{2})", MEM_INC.read_text(encoding="utf-8", errors="replace"), re.M):
        w[m.group(1)] = int(m.group(2), 16)
    return w


def bank_portb(p: int) -> int | None:
    """Numer banku 1088K z PORTB (jak tools/sprawdz_xex.py): bit 4 = 0 - okno CPU na bank."""
    if p & 0x10:
        return None
    return ((p >> 1) & 7) | ((p >> 5) << 3)


def kontrola(pb: dict[str, int]) -> list[str]:
    bledy = []
    banki: dict[int, str] = {}
    for n, o in OBRAZY.items():
        if o.bank in banki:
            bledy.append(f"bank {o.bank} dwa razy: {banki[o.bank]}, {n}")
        banki[o.bank] = n
        ld = "PB_LD_" + o.pb[3:]
        for s in (o.pb, ld):
            if s not in pb:
                bledy.append(f"{n}: brak {s} w mem.inc")
        if o.pb in pb and bank_portb(pb[o.pb]) != o.bank:
            bledy.append(f"{n}: {o.pb} = ${pb[o.pb]:02X} -> bank {bank_portb(pb[o.pb])}, manifest {o.bank}")
        if o.pb in pb and ld in pb and pb[ld] != pb[o.pb] | 1:
            bledy.append(f"{n}: {ld} = ${pb[ld]:02X} != {o.pb} | 1")
    # pliki sprawdzane tylko dla obrazów z LVBANKS (ins w lvbanks.inc); pozostałe (np. ekrany - extract_ekrany.py tylko w celu sonic)
    # sprawdza MADS w swoim celu - review M7.1: cel game nie może wymagać plików wydania
    for _, n in LVBANKS:
        if n is None:
            continue
        if n not in OBRAZY:
            bledy.append(f"LVBANKS: nieznany obraz {n}")
        elif OBRAZY[n].plik is None:
            bledy.append(f"LVBANKS: {n} bez pliku")
        elif not (A / OBRAZY[n].plik).is_file():
            bledy.append(f"{n}: brak pliku build/assets/{OBRAZY[n].plik}")
    # nazwy obrazów w tablicach poziomów (zamiast KeyError) i ciągłość numeracji (review M7.1: zn_* i sub_bank indeksowane g_level / celem)
    for _, nz, *obr in STREFY:
        for n in obr:
            if n not in OBRAZY:
                bledy.append(f"STREFY {nz}: nieznany obraz {n}")
    for _, nz, lv, at in POD:
        for n in (lv, at):
            if n is not None and n not in OBRAZY:
                bledy.append(f"POD {nz}: nieznany obraz {n}")
    for e, lv in SPECJALNE:
        if lv not in OBRAZY:
            bledy.append(f"SPECJALNE ${e:02X}: nieznany obraz {lv}")
    if [s[0] for s in STREFY] != list(range(len(STREFY))):
        bledy.append("STREFY: g_level nie jest ciągły od 0 (zn_* indeksowane g_level)")
    if [p[0] for p in POD] != list(range(0x14, 0x14 + len(POD))):
        bledy.append("POD: cele nie są ciągłe od $14 (sub_bank indeksowany celem - $14)")
    if [e for e, _ in SPECJALNE] != list(range(0x1C, 0x1C + len(SPECJALNE))):
        bledy.append("SPECJALNE: etapy nie są ciągłe od $1C")
    for n, slot in ALT_SLOT.items():
        if n not in OBRAZY or slot not in SLOTY:
            bledy.append(f"ALT_SLOT: {n} -> {slot} (nieznany obraz albo slot)")
    # M7.3 (review): punkt cięcia plików na nośniku 320K (nosnik_dl) = adres danych banku 36 w src/kernel/mem.inc (SCD_R0 - muzyka, SCD_KO -
    # boss); zera za punktem cięcia sprawdza MADS (.get w src/game.asm) i tools/pack_cart.py
    scd = {m.group(1): int(m.group(2), 16) for m in re.finditer(r"^(SCD_\w+)\s*=\s*BANK_WIN\+\$([0-9A-Fa-f]{4})", MEM_INC.read_text(
        encoding="utf-8", errors="replace"), re.M)}
    for n, s in (("music", "SCD_R0"), ("boss", "SCD_KO")):
        if OBRAZY[n].nosnik_dl != scd.get(s):
            bledy.append(f"{n}: nosnik_dl ${OBRAZY[n].nosnik_dl or 0:04X} != {s} ${scd.get(s, 0):04X} (src/kernel/mem.inc)")
    if bledy:
        return bledy
    if len({n for n, _, _ in PAKIETY}) != len(PAKIETY):
        bledy.append("powtórzone nazwy pakietów")
    w_pak = [o for _, _, obr in PAKIETY for o in obr]
    for n in OBRAZY:
        if w_pak.count(n) != 1:
            bledy.append(f"obraz {n} w {w_pak.count(n)} pakietach (ma być 1)")
    # zestaw roboczy 320K: stałe + sloty <= 16, stałe w pasmie 33-63 nieparzystym i poza slotami
    stale = sorted(o.bank for o in OBRAZY.values() if o.staly)
    zestaw = set(stale) | set(SLOTY.values())
    if len(zestaw) > ZESTAW_MAX or len(stale) + len(SLOTY) != len(zestaw):
        bledy.append(f"zestaw roboczy {len(zestaw)}/{ZESTAW_MAX} (stałe {stale} kolidują ze slotami?)")
    for b in zestaw:
        if not (33 <= b <= 63 and b & 1):
            bledy.append(f"bank zestawu roboczego {b} poza 33-63 nieparzystymi")
    for o in OBRAZY.values():
        if o.slot is not None and o.slot not in SLOTY:
            bledy.append(f"bank {o.bank}: nieznany slot {o.slot}")
    # M7.2: tablice ról ldr - wpisy pasują do slotów ról, w poziomie każda rola w innym slocie, id <= 63, PB_SL_* = banki SLOTY
    try:
        poz, pod = ldr_poziomy(), ldr_pod()
    except ValueError as e:
        return bledy + [f"role ldr: {e}"]
    if len(poz) != len(STREFY) + len(SPECJALNE):
        bledy.append("role ldr: liczba wierszy != STREFY + SPECJALNE")
    for nz, r in poz:
        uzyte = [w[1] for w in r.values() if w is not None and w[1] is not None]
        if len(uzyte) != len(set(uzyte)):
            bledy.append(f"role ldr {nz}: dwie role w jednym slocie {uzyte}")
    for (cel, *_r), (nz, rp) in zip(POD, pod):
        role = dict(poz[POD_AKT[cel]][1])
        role.update({k: v for k, v in rp.items() if v is not None})
        uzyte = [w[1] for w in role.values() if w is not None and w[1] is not None]
        if len(uzyte) != len(set(uzyte)):
            bledy.append(f"role ldr {nz}: dwie role w jednym slocie {uzyte}")
    if max(ID.values()) > 63:
        bledy.append(f"id obrazów do {max(ID.values())} > 63 (6 bitów wpisu ldr_lvl)")
    for s, b in SLOTY.items():
        if f"PB_SL_{s}" not in pb:
            bledy.append(f"brak PB_SL_{s} w mem.inc")
        elif bank_portb(pb[f"PB_SL_{s}"]) != b:
            bledy.append(f"PB_SL_{s} = ${pb[f'PB_SL_{s}']:02X} -> bank {bank_portb(pb[f'PB_SL_{s}'])}, SLOTY {b}")
    for g, p in potrzeby().items():
        for slot, n in p.items():
            if OBRAZY[n].slot != slot and ALT_SLOT.get(n) != slot:
                bledy.append(f"poziom ${g:02X}: obraz {n} (slot {OBRAZY[n].slot}) w slocie {slot}")
    return bledy


def pb(n: str) -> str:
    return OBRAZY[n].pb


def li(n: str) -> str:
    """Stała identyfikatora obrazu w ldr_tables.inc (XEX: = PB_* banku, nośnik: = id)."""
    return "LI_" + n.upper()


def ldr_tables() -> str:
    """build/assets/ldr_tables.inc (M7.2, src/ldr/ldr.asm): stałe i tablice ról dla ldr_need - wariant XEX (PORTB banków rezydentnych, wartości
    jak zn_* / sub_bank / stałe lvs_sp z M7.1) i nośnika (id | LDR_ALT, tablice slotów) w jednym pliku pod .if MEDIA."""
    akty = sorted(set(POD_AKT.values()))
    if len(akty) != 2:
        raise ValueError("lv_select obsługuje 2 akty z pod-poziomami (SUB_AKT1/2) - zmień kod gry razem z manifestem")
    poz, pod = ldr_poziomy(), ldr_pod()
    sl_idx = {s: i for i, s in enumerate(SLOTY)}
    L = ["; build/assets/ldr_tables.inc - generowane przez tools/manifest.py (M7.2) - nie edytowac recznie",
         "; Tablice rol obrazow poziomu dla ldr_need (src/ldr/ldr.asm, docs/plan-m7-ldr.md 4.2). Role: LR_LEVEL, LR_ATLAS, LR_ZSPR, LR_OBJZ",
         "; (src/kernel/mem.inc; kolejnosc zmiennych v_pblevel, v_pbatlas, v_pbzspr, v_pbobjz). Indeks poziomu lv_idx: g_level 0-$12 -> 0-18,",
         "; etap specjalny $1C-$23 -> 19-26 (lv_select). XEX 1088K: wpis = PORTB banku rezydentnego (ldr_need tylko przepisuje - wartosci jak",
         "; tablice zn_* i stale lv_select z M6/M7.1); nosnik: wpis = id obrazu (b0-5) | LDR_ALT (b7: drugi slot roli), 0 = rola bez obrazu.",
         f"ZONE_N\t\t= {len(STREFY)}\t\t; akty i poziom $12 (lv_idx = g_level); boot_level 19-$1B - zaslepka GHZ1 (lv_select)",
         f"LDR_NLV\t\t= {len(poz)}\t\t; wiersze ldr_lvl",
         f"SUB_N\t\t= {len(POD)}\t\t; liczba pod-poziomow ($14..)",
         f"SUB_AKT1\t= {akty[0]}\t\t; akty z pod-poziomami (SBZ2, SKY2) - lv_select",
         f"SUB_AKT2\t= {akty[1]}",
         f"LDR_ALT\t\t= ${LDR_ALT:02X}\t\t; bit drugiego slotu roli (nosnik)",
         "LDR_ID\t\t= $3F\t\t; maska id obrazu",
         f"LDR_NSLOT\t= {len(SLOTY)}\t\t; sloty zestawu roboczego: " + ", ".join(f"{i} {s} (bank {b})" for i, (s, b) in enumerate(SLOTY.items())),
         "\t.if MEDIA=MEDIA_XEX",
         "; identyfikator obrazu = PORTB banku (OS off): v_img = v_pb* - porownania z LI_* w kodzie gry = dawne porownania z PB_*"]
    for n, o in OBRAZY.items():
        L.append(f"{li(n)}\t= {o.pb}\t; bank {o.bank}: {ascii_pl(o.opis)}")
    L += ["; ldr_lvl[lv_idx][rola]: poziom, atlas, sprite'y strefy, obiekty strefy (GHZ: PB_OBJZ dla jednolitosci - GHZ nie uzywa objz_call)",
          "ldr_lvl"]
    for i, (nz, r) in enumerate(poz):
        nazwy = [r[x][0] if r[x] is not None else STREFY[i][5] for x in ROLE]   # None tylko objz GHZ: obraz z STREFY (jak zn_objz)
        L.append(f"\tdta b({', '.join(pb(n) for n in nazwy)})\t; {i:2d} {nz}")
    L += ["; ldr_sub[pod-poziom][rola poziom, rola atlas (0 = atlas aktu)]: $14-$1A", "ldr_sub"]
    for (cel, *_r), (nz, rp) in zip(POD, pod):
        at = pb(rp["atlas"][0]) if rp["atlas"] else "0"
        L.append(f"\tdta b({pb(rp['poziom'][0])}, {at})\t; ${cel:02X} {nz}")
    L += ["\t.else",
          "; identyfikator obrazu = id (1..63): katalog RAMCART / cartu (M7.3), plik Bnn.ZX2 na ATR (M7.4) - nn = id dziesietnie (tools/pack_atr.py; B50 / B51 - obrazy kodu)"]
    for n, o in OBRAZY.items():
        L.append(f"{li(n)}\t= {ID[n]}\t; bank XEX {o.bank}, slot {o.slot or 'staly'}")

    def w(x) -> str:
        if x is None:
            return "0"
        return li(x[0]) + ("|LDR_ALT" if x[2] else "")
    L += ["; ldr_lvl[lv_idx][rola] = id | LDR_ALT (alt: LEVEL2 / ATLAS2 / staly bank 39 / LEVEL2), 0 = rola bez obrazu", "ldr_lvl"]
    for i, (nz, r) in enumerate(poz):
        L.append(f"\tdta b({', '.join(w(r[x]) for x in ROLE)})\t; {i:2d} {nz}")
    L += ["; ldr_sub[pod-poziom][rola poziom, rola atlas (0 = atlas aktu)]", "ldr_sub"]
    for (cel, *_r), (nz, rp) in zip(POD, pod):
        L.append(f"\tdta b({w(rp['poziom'])}, {w(rp['atlas'])})\t; ${cel:02X} {nz}")
    # rola * 2 + alt -> PORTB (OS off) i slot (0..5, $FF = bank stały - bez ładowania)
    rpb, rsl = [], []
    for x in ROLE:
        for s in ROLA_SLOT[x]:
            if s is None:
                rpb.append(pb(ROLA_STALY[x]))
                rsl.append("$FF")
            else:
                rpb.append(f"PB_SL_{s}")
                rsl.append(str(sl_idx[s]))
    L += ["; rola * 2 + alt -> PORTB slotu (OS off) / indeks slotu ($FF = bank staly, bez ladowania)",
          f"ldr_role_pb\tdta b({', '.join(rpb)})",
          f"ldr_role_slot\tdta b({', '.join(rsl)})",
          "; slot -> PORTB (OS off)",
          f"ldr_slot_pb\tdta b({', '.join(f'PB_SL_{s}' for s in SLOTY)})"]
    stale = [n for n, o in OBRAZY.items() if o.staly]
    L += ["\t.if NOSNIK_320",
          "; M7.3: obrazy stale nosnika 320K wgrywane raz przez ldr_init (cart / ATR; OS wlaczony - ldr_init dodaje bit 0 PORTB):",
          "; id obrazu i PORTB banku (OS off). Bank 36 (scrc) - tylko XEX: jego dane w bankach 43 / 59 / 41 (NOSNIK_SKLAD w tools/manifest.py)",
          f"LDR_NCONST\t= {len(stale)}",
          f"ldr_const_id\tdta b({', '.join(li(n) for n in stale)})",
          f"ldr_const_pb\tdta b({', '.join(pb(n) for n in stale)})",
          "\t.endif",
          "\t.endif",
          "\t.if [ldr_sub-ldr_lvl]<>LDR_NLV*4",
          "\t.error \"ldr_lvl: zla liczba wpisow\"",
          "\t.endif"]
    return "\n".join(L) + "\n"


def lvbanks() -> str:
    linie = ["; =====================================================================",
             ";  build/assets/lvbanks.inc - generowane przez tools/manifest.py (M7.1; dawne src/game_lvbanks.asm) - nie edytowac recznie",
             ";  Banki aktu i stref ladowane z XEX 1088K: stub INI pod $0610 wybiera bank (PB_LD_*, OS on), segment w oknie $4000-$7FFF.",
             ";  Budowa testowa: na poczatku XEX-a; wydanie (RELEASE): po INIT ekranow - dane aktu czyta loader po mapie",
             ";  (tam, gdzie oryginal laduje poziom: main@run_this_level, load_and_run_level).",
             "; ====================================================================="]
    for kom, n in LVBANKS:
        if kom:
            if linie[-1]:
                linie.append("")
            linie.extend(kom.split("\n"))
            continue
        o = OBRAZY[n]
        ld = "PB_LD_" + o.pb[3:]
        etyk = "ld_" + o.pb[3:].lower()
        ins = [f"\tins '{o.plik}'\t; bank {o.bank}: {ascii_pl(o.opis)}"]
        if o.nosnik_dl:              # M7.3: na nośniku 320K tylko początek pliku - dalej dane banku 36 (src/game.asm, SCD_*)
            ins = ["\t.if NOSNIK_320", f"\tins '{o.plik}',0,${o.nosnik_dl:04X}\t; M7.3: nosnik 320K - od ${o.nosnik_dl:04X} dane banku 36",
                   "\t.else"] + ins + ["\t.endif"]
        seg = ["\torg $0610", etyk, f"\tlda #{ld}", "\tsta PORTB", "\trts", f"\tini {etyk}", "\torg BANK_WIN"] + ins + \
              [f"{etyk}_end\t\t\t; M7.3: koniec danych w oknie (asercje miejsca - src/game.asm)"]
        if o.staly:
            linie += seg + [""]
        else:            # M7.2: obraz slotu - na nośniku (LD_ZONY = 0, sonic-ram.xex) wgrywa go tylko ldr
            linie += ["\t.if LD_ZONY"] + seg + ["\t.endif", ""]
    return "\n".join(linie) + "\n"


def ascii_pl(t: str) -> str:
    """Komentarze w .inc po ASCII (zasada projektu): polskie litery bez ogonków."""
    return t.translate(str.maketrans("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ„”–", "acelnoszzACELNOSZZ\"\"-"))


def manifest_json() -> dict:
    return {
        "wersja": 1,
        "sloty": SLOTY,
        "alt_slot": ALT_SLOT,
        "obrazy": {n: {"bank": o.bank, "pb": o.pb, "id": ID[n], "plik": o.plik, "slot": o.slot, "bank_nosnika": SLOTY[o.slot] if o.slot else o.bank,
                       "staly": o.staly, "tylko_xex": o.tylko_xex, "nosnik_dl": o.nosnik_dl, "opis": o.opis} for n, o in OBRAZY.items()},
        # M7.3: zestaw obrazów nośnika 320K (cart, ATR): stałe (ldr_init, kolejność = ldr_const) + doczytywane (ldr.ladowane); bez obrazów
        # tylko-XEX (bank 36), skład stałych z dodatkami z banku 36
        "nosnik": {"stale": [n for n, o in OBRAZY.items() if o.staly], "tylko_xex": [n for n, o in OBRAZY.items() if o.tylko_xex],
                   "sklad": NOSNIK_SKLAD},
        # M7.2: role ldr (lv_idx -> rola -> obraz, slot, alt), pod-poziomy, obrazy doczytywane przez ldr (RAMCART / cart / ATR)
        "ldr": {"role": list(ROLE), "rola_slot": {r: list(s) for r, s in ROLA_SLOT.items()},
                "poziomy": [{"lv_idx": i, "nazwa": nz, "role": {x: (None if r[x] is None else {"obraz": r[x][0], "slot": r[x][1], "alt": r[x][2]})
                                                                for x in ROLE}} for i, (nz, r) in enumerate(ldr_poziomy())],
                "pod": [{"cel": p[0], "nazwa": nz, "role": {x: (None if r[x] is None else {"obraz": r[x][0], "slot": r[x][1], "alt": r[x][2]})
                                                            for x in ("poziom", "atlas")}} for p, (nz, r) in zip(POD, ldr_pod())],
                "ladowane": ldr_ladowane()},
        "strefy": [{"g_level": g, "nazwa": nz, "atlas": a, "poziom": l, "zspr": s, "objz": z} for g, nz, a, l, s, z in STREFY],
        "pod": [{"cel": c, "nazwa": nz, "poziom": l, "atlas": a, "akt": POD_AKT[c]} for c, nz, l, a in POD],
        "specjalne": [{"etap": e, "poziom": l} for e, l in SPECJALNE],
        "potrzeby": {f"{g:02X}": p for g, p in sorted(potrzeby().items())},
        "kolejnosc": KOLEJNOSC,
        "pakiety": [{"nazwa": n, "typ": t, "obrazy": o} for n, t, o in PAKIETY],
    }


def zapisz(p: Path, tekst: str) -> None:
    """Zapis tylko przy zmianie (MADS i make widzą stary czas modyfikacji), LF. Pliki .inc - tylko ASCII."""
    if p.suffix == ".inc" and not tekst.isascii():
        raise ValueError(f"{p.name}: znaki spoza ASCII")
    if p.is_file() and p.read_text(encoding="utf-8") == tekst:
        return
    p.write_text(tekst, encoding="utf-8", newline="\n")


def main() -> int:
    bledy = kontrola(pb_z_mem_inc())
    if bledy:
        for b in bledy:
            print("BŁĄD manifestu:", b, file=sys.stderr)
        return 1
    A.mkdir(parents=True, exist_ok=True)
    zapisz(A / "ldr_tables.inc", ldr_tables())
    for stary in ("zn_tables.inc", "zn_sub.inc"):          # M7.1 - zastąpione przez ldr_tables.inc (M7.2); stare pliki nie mogą zostać w ścieżce
        (A / stary).unlink(missing_ok=True)
    zapisz(A / "lvbanks.inc", lvbanks())
    zapisz(A / "manifest.json", json.dumps(manifest_json(), ensure_ascii=False, indent=1) + "\n")
    stale = sum(1 for o in OBRAZY.values() if o.staly)
    print(f"manifest: {len(OBRAZY)} obrazów banków, {len(STREFY)} stref + {len(POD)} pod-poziomów + {len(SPECJALNE)} etapów, "
          f"{len(PAKIETY)} pakietów; zestaw roboczy 320K {stale + len(SLOTY)}/{ZESTAW_MAX} ({stale} stałych + {len(SLOTY)} slotów); "
          f"ldr: {len(ldr_poziomy())} poziomów x {len(ROLE)} role, {len(ldr_ladowane())} obrazów doczytywanych")
    return 0


if __name__ == "__main__":
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main())
