#!/usr/bin/env python3
"""Ekstrakcja ekranów przed poziomem (M6): ekran tytułowy i mapa 1 (strefy GHZ, BRI, JUN) z ROM-u SMS.

Wejście: ROM SMS (jak tools/extract_sms.py, poza repozytorium).
Wyjście (build/assets/ekrany/, poza gitem – dane z ROM-u):
  bank_ekr_atlasy2.bin – bank 53 (M6.2): $0000 kafle tła ekranu wyniku 4 bpp (ART_09_351F, wspólne z game over),
                       $2000 wolne
  ekr_rle_wynik.bin  – RLE mapy ekranu wyniku (ARTMAP_05_612E, 187 B)
  ekr_rle_wynik_sp.bin – RLE mapy ekranu wyniku etapu specjalnego (M6.5, ARTMAP_05_61E9, 149 B; w kodzie rezydentnym: src/scr/special.asm)
  ekr_rle_go.bin     – RLE mapy ekranu game over (M6.3, ARTMAP_05_67FE, 50 B); tło = to samo co wyniku (bank 53)
  podglad-gameover.png, model-gameover.npy – model obrazu ekranu game over (kontrola wizualna)
  bank_ekr_atlasy.bin – bank 51: kafle tła 4 bpp (2 piksele na bajt, starsza połówka = lewy): $0000 tytuł
                       (ART_09_2000, 256 kafli x 32 B), $2000 mapa 1 (ART_0C_0000) – razem 16 KiB; port rozpakowuje
                       je do atlasu 8 bpp w VRAM (kafel t pod t*64)
  ekr_rom0.bin       – bajty banku 0 ROM-u $0E72-$1400 (palety map i tytułu, LUT_level_map_info, mapy sprite'ów
                       znaczników aktów, LUT_level_titles i napisy stref, napisy PRESS BUTTON, LUT animacji dłoni,
                       mapy sprite'ów dłoni) – port czyta je pod adresem SMS (src/scr: SCR_R0 + adres - $0E72)
  ekr_rle_tytul.bin  – bajty RLE mapy ekranu tytułu (ARTMAP_05_6000, 302 B) – port rozpakowuje je przekładem
  ekr_rle_mapa1a.bin   unpack_art_tilemap_into_vram (00:0501); mapa 1: warstwa ARTMAP_05_627E (atrybut $10)
  ekr_rle_mapa1b.bin   i ARTMAP_05_63F6 (atrybut $00, $FF = komórka pominięta)
  ekr_spr_tytul.bin  – pary kafli sprite'ów 8x16 tytułu: [kafel parzysty, 64 B (2 kafle 4 bpp)] ...
  ekr_spr_mapa1.bin  – jw. dla mapy 1: znaczniki aktów (mapy sprite'ów z level_map_XX_chunks) i cyfry żyć
                       (ART_09_B92E pod kaflami $80+)
  ekrany.inc         – stałe MADS (liczby par, rozmiary)
  podglad-*.png      – podgląd kontrolny (model obrazu VDP)
Formaty i adresy: docs/plan-m6.md (krok 1), dezasemblacja s1smsdisasm-gm (tylko materiał referencyjny).
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
sys.path.insert(0, str(ROOT / "tools"))
from extract_sms import DEFAULT_ROM, ROM_SHA256, decode_hy_art, planar_to_8bpp  # noqa: E402

# grafika (offset w ROM = bank * $4000 + adres w slocie, load_art 00:0405)
ART_TITLE_BG = 0x24000 + 0x2000     # ART_09_2000 -> VRAM $0000 (kafle tła tytułu)
ART_TITLE_SPR = 0x24000 + 0x4B0A    # ART_09_4B0A -> VRAM $2000 (kafle sprite'ów tytułu)
ART_MAP1_BG = 0x30000 + 0x0000      # ART_0C_0000 -> VRAM $0000 (mapa 1)
ART_MAP1_SPR = 0x24000 + 0x526B     # ART_09_526B -> VRAM $2000 (sprite'y mapy 1)
ART_HUD = 0x24000 + 0xB92E          # ART_09_B92E -> VRAM $3000 (kafle sprite'ów $80+: cyfry żyć)
ART_MAP2_BG = 0x30000 + 0x1801      # M6.8: ART_0C_1801 -> VRAM $0000 (mapa 2, @load_second_map 00:0CEB)
ART_MAP2_SPR = 0x24000 + 0x5942     # ART_09_5942 -> VRAM $2000 (sprite'y mapy 2)
# mapy ekranu (bank 5 w slocie 1: ROM $14000 + adres - $4000), długość RLE z rejestru bc w kodzie
NT_TITLE = (0x14000 + 0x6000 - 0x4000, 0x012E, 0x00)       # ARTMAP_05_6000 (run_title_screen 00:12B4)
NT_MAP1 = [(0x14000 + 0x627E - 0x4000, 0x0178, 0x10),       # ARTMAP_05_627E (run_world_map 00:0CB2)
           (0x14000 + 0x63F6 - 0x4000, 0x0145, 0x00)]       # ARTMAP_05_63F6 (00:0CC3)
NT_MAP2 = [(0x14000 + 0x653B - 0x4000, 0x0170, 0x10),       # M6.8: ARTMAP_05_653B (00:0D14)
           (0x14000 + 0x66AB - 0x4000, 0x0153, 0x00)]       # ARTMAP_05_66AB (00:0D25)
ROM0_FROM, ROM0_TO = 0x0E72, 0x1BAD   # bank 0: mapsprite_robotnik_* (M6.4) .. koniec PAL3_score_tally (M6.2: tablice premii
                                      # 00:151C, emblemat szmaragdu 00:1711, LUT_zero_time_bonus 00:1A14, kafle aktu
                                      # 00:1B51, przesunięcia 00:1B69, paleta wyniku 00:1B8D)
ART_SCORE_BG = 0x24000 + 0x351F     # ART_09_351F -> VRAM $0000 (tło ekranu wyniku i game over; przez granicę banków 9/10)
NT_SCORE = (0x14000 + 0x612E - 0x4000, 0x00BB, 0x00)       # ARTMAP_05_612E (handle_level_score_screen 00:1593)
NT_SCORE_SP = (0x14000 + 0x61E9 - 0x4000, 0x0095, 0x00)    # ARTMAP_05_61E9: ekran wyniku etapu specjalnego (00:15A3, M6.5)
NT_GO = (0x14000 + 0x67FE - 0x4000, 0x0032, 0x00)          # ARTMAP_05_67FE (run_game_over_screen 00:1424)
PAL_GO = 0x14FC                     # PAL3_game_over (00:143C)
PAL_SCORE = 0x1B8D                  # PAL3_score_tally
PAL_TITLE = 0x13E1                  # PAL3_title_screen (32 B: tło, sprite'y)
PAL_MAP1 = 0x0F0E                   # PAL3_world_map_0
LUT_LEVEL_MAP_INFO = 0x0F4E         # 3 B na poziom: słowo level_map_XX_chunks, bajt akcji mapy
SPRTAB_HAND = [0x13BD, 0x13CF]      # SPRTAB_title_screen_sonic_hand_1/_2 (3 wiersze x 6 B)
MAP1_LEVELS = range(0, 9)           # mapa 1: poziomy 0-8 (GHZ, BRI, JUN; run_world_map 00:0C66)
MAP2_LEVELS = range(9, 18)          # M6.8: mapa 2: poziomy 9-17 (LAB, SBZ, SKY; tmp_08 = 2)
PAL_MAP2 = 0x0F2E                   # PAL3_world_map_1 (00:0D36)
ROBOTNIK_MAPS = [0x1129, 0x113B, 0x114D, 0x115F, 0x1183]   # map_SPRTAB_robotnik_left_1/_2, right_1/_2, front (M6.4: akcje mapy)
HUD_DIGITS = [0x80 + 2 * d for d in range(10)]   # render_world_map_sprites: kafel $80 + 2 * cyfra (draw_sprite_text)


def unpack_tilemap(rom: bytes, addr: int, size: int, attr: int, nt: list, at: list) -> int:
    """unpack_art_tilemap_into_vram (00:0501): RLE map ekranu do komórek nazw VDP od $3800 (32 x 24).
    Bajt różny od poprzedniego = kafel (zapis kafla i atrybutu tmp_00); bajt równy poprzedniemu = znacznik serii,
    następny bajt = liczba dodatkowych kopii (0 = 256), po serii poprzedni od nowa (dopełnienie bieżącego);
    $FF = komórka pominięta (także w serii). Zwraca liczbę komórek (zapisanych i pominiętych)."""
    i, end, cell = addr, addr + size, 0
    prev = (~rom[i]) & 0xFF
    while i < end:
        v = rom[i]
        if v != prev:
            if v != 0xFF:
                nt[cell], at[cell] = v, attr
            cell += 1
            prev = v
            i += 1
            continue
        i += 1                                      # znacznik serii (v == prev)
        if i >= end:
            break
        n = rom[i] or 256
        for _ in range(n):
            if v != 0xFF:
                nt[cell], at[cell] = v, attr
            cell += 1
        i += 1
        if i < end:
            prev = (~rom[i]) & 0xFF
    return cell


def tiles8(rom: bytes, addr: int, n: int) -> np.ndarray:
    return planar_to_8bpp(decode_hy_art(rom, addr), n)


def sprite_tiles_of_map(rom0: bytes, sms_addr: int) -> set[int]:
    """Kafle (parzyste, 8x16) mapy sprite'ów draw_sprite_string 00:350F: do 3 wierszy po 6 B, $FF na początku
    wiersza kończy mapę, $FE/$FF w kolumnie - brak sprite'a."""
    out = set()
    for r in range(3):
        row = rom0[sms_addr - ROM0_FROM + 6 * r: sms_addr - ROM0_FROM + 6 * r + 6]
        if row[0] == 0xFF:
            break
        out |= {t & 0xFE for t in row if t < 0xFE}
    return out


def map1_marker_maps(rom0: bytes, levels=MAP1_LEVELS) -> list[int]:
    """Adresy map sprite'ów znaczników aktów mapy 1 (level_map_XX_chunks: słowo mapy, x, y, czas; czas 0 = skok);
    M6.8: levels = MAP2_LEVELS - mapa 2."""
    maps = []
    for lv in levels:
        p = struct.unpack_from("<H", rom0, LUT_LEVEL_MAP_INFO + 3 * lv - ROM0_FROM)[0]
        seen = set()
        while p not in seen:
            seen.add(p)
            m, x, y, t = struct.unpack_from("<HBBB", rom0, p - ROM0_FROM)
            if t == 0:
                p = m
                continue
            maps.append(m)
            p += 5
    return sorted(set(maps))


def pack4(a: np.ndarray) -> bytes:
    """Obraz 8 bpp (wartości 0..15) -> 2 piksele na bajt (starsza połówka = lewy piksel)."""
    a = a.reshape(-1).astype(np.uint8)
    return ((a[0::2] << 4) | a[1::2]).astype(np.uint8).tobytes()


def spr_pairs(pairs: list[int], tiles: dict[int, np.ndarray]) -> bytes:
    """Pary kafli 8x16: bajt kafla parzystego + 64 B (2 kafle 4 bpp); port dodaje 16 do kolorów != 0."""
    out = bytearray()
    for t in sorted(pairs):
        out.append(t)
        out += pack4(np.concatenate([tiles[t], tiles[t + 1]]))   # 8x16
    return bytes(out)


def sms_rgb_arr(c: np.ndarray) -> np.ndarray:
    return np.stack([(c & 3) * 85, ((c >> 2) & 3) * 85, ((c >> 4) & 3) * 85], axis=-1).astype(np.uint8)


# ---------------------------------------------------------------------------------------------------------------
# model obrazu VDP (kontrola danych z Mesenem; tools/m6_ekrany_test.py porównuje port wprost z Mesenem)
# ---------------------------------------------------------------------------------------------------------------
def render(nt: list[int], at: list[int], sat: list[tuple[int, int, int]], cram: bytes, bg: np.ndarray,
           spr: np.ndarray, display: bool = True, reg7: int = 0) -> np.ndarray:
    """Obraz 192x256 kolorów SMS: tło z komórek (kafel, atrybut: bit 3 paleta sprite'ów, bit 4 priorytet),
    sprite'y 8x16 (Y + 1, kafel & $FE, pierwszy na liście wygrywa, kolor 0 przezroczysty), priorytet tła
    nad sprite'ami dla koloru tła != 0, lewa kolumna 8 px (reg0 bit 5) i wyłączony obraz w kolorze ramki."""
    border = cram[16 + (reg7 & 15)]
    if not display:
        return np.full((192, 256), border, np.uint8)
    pix = np.zeros((192, 256), np.uint8)
    pal_bg = np.zeros((192, 256), np.uint8)
    prio = np.zeros((192, 256), bool)
    for c in range(768):
        r, k = divmod(c, 32)
        t = bg[nt[c]]
        pix[8 * r:8 * r + 8, 8 * k:8 * k + 8] = t
        pal_bg[8 * r:8 * r + 8, 8 * k:8 * k + 8] = 16 if at[c] & 8 else 0
        prio[8 * r:8 * r + 8, 8 * k:8 * k + 8] = bool(at[c] & 0x10)
    img = np.frombuffer(bytes(cram), np.uint8)[pix + pal_bg]
    done = np.zeros((192, 256), bool)
    for (y, x, t) in sat:
        if y == 0xD0:
            break
        top = (y + 1) & 0xFF
        sp = np.concatenate([spr[t & 0xFE], spr[(t & 0xFE) | 1]])
        for dy in range(16):
            yy = (top + dy) & 0xFF
            if yy >= 192:
                continue
            for dx in range(8):
                xx = x + dx
                if xx >= 256 or done[yy, xx]:
                    continue
                p = sp[dy, dx]
                if p == 0:
                    continue
                done[yy, xx] = True
                if prio[yy, xx] and pix[yy, xx] != 0:
                    continue
                img[yy, xx] = cram[16 + p]
    img[:, :8] = border
    return img


def dss(rom0: bytes, sms_map: int, x: int, y: int) -> list[tuple[int, int, int]]:
    """draw_sprite_string (00:350F) dla mapy w banku 0 (bez odcinania - ekrany mieszczą się w 0..255)."""
    out = []
    for r in range(3):
        row = rom0[sms_map - ROM0_FROM + 6 * r: sms_map - ROM0_FROM + 6 * r + 6]
        if row[0] == 0xFF:
            break
        for k, t in enumerate(row):
            if t < 0xFE:
                out.append((y + 16 * r, x + 8 * k, t))
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rom", default=str(DEFAULT_ROM))
    ap.add_argument("--out", default=str(ROOT / "build" / "assets" / "ekrany"))
    ap.add_argument("--wynik", default=None,
                    help="M6.2: npz referencji z ekranem wyniku (m6_ekrany_ref.py --skrypt) - model obrazu wyniku")
    ap.add_argument("--kontrola", default=None,
                    help="npz referencji Mesena (tools/m6_ekrany_ref.py) - porównanie modelu obrazu z klatkami")
    a = ap.parse_args(argv)
    rom = Path(a.rom).read_bytes()
    if hashlib.sha256(rom).hexdigest() != ROM_SHA256:
        print("BŁĄD: ROM o innej sumie SHA-256 niż oczekiwana", file=sys.stderr)
        return 1
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    rom0 = rom[ROM0_FROM:ROM0_TO]
    t_bg = tiles8(rom, ART_TITLE_BG, 256)
    t_spr = tiles8(rom, ART_TITLE_SPR, 128)
    m_bg = tiles8(rom, ART_MAP1_BG, 256)
    m_spr = np.zeros((256, 8, 8), np.uint8)
    m_spr[:128] = tiles8(rom, ART_MAP1_SPR, 128)
    m_spr[128:192] = tiles8(rom, ART_HUD, 64)
    t_spr256 = np.zeros((256, 8, 8), np.uint8)
    t_spr256[:128] = t_spr

    # mapy ekranu
    nt_t, at_t = [0] * 768, [0] * 768
    n = unpack_tilemap(rom, *NT_TITLE[:2], NT_TITLE[2], nt_t, at_t)
    if n != 768:
        raise SystemExit(f"mapa tytułu: {n} komórek")
    nt_m, at_m = [0] * 768, [0] * 768
    for (adr, size, attr) in NT_MAP1:
        n = unpack_tilemap(rom, adr, size, attr, nt_m, at_m)
        if n != 768:
            raise SystemExit(f"mapa 1 (${adr:05X}): {n} komórek")

    # kafle sprite'ów: dłoń tytułu, znaczniki aktów mapy 1, cyfry żyć
    p_t = set()
    for m in SPRTAB_HAND:
        p_t |= sprite_tiles_of_map(rom0, m)
    p_m = set(HUD_DIGITS)
    marker_maps = map1_marker_maps(rom0)
    for m in marker_maps + ROBOTNIK_MAPS:
        p_m |= sprite_tiles_of_map(rom0, m)

    s_bg = tiles8(rom, ART_SCORE_BG, 256)
    # M6.8: mapa 2 - atlas tla ART_0C_1801 w banku 53 pod $2000 (okno $6000), mapy ekranu i pary kafli sprite'ow (znaczniki aktow 9-17
    # z ART_09_5942, cyfry zyc) w ekr_mapa2.bin (bank 43 pod $2000; boot.asm kopiuje do RAM przed mapa)
    m2_bg = tiles8(rom, ART_MAP2_BG, 256)
    (out / "bank_ekr_atlasy2.bin").write_bytes(pack4(s_bg) + pack4(m2_bg))   # bank 53: $4000 wynik, $6000 mapa 2
    m2_spr = np.zeros((256, 8, 8), np.uint8)
    m2_spr[:128] = tiles8(rom, ART_MAP2_SPR, 128)
    m2_spr[128:192] = tiles8(rom, ART_HUD, 64)
    p_m2 = set(HUD_DIGITS)
    for m in map1_marker_maps(rom0, MAP2_LEVELS):
        p_m2 |= sprite_tiles_of_map(rom0, m)
    spr_m2 = spr_pairs(sorted(p_m2), {i: m2_spr[i] for i in range(256)})
    rle_m2 = [rom[a:a + n] for a, n, _ in NT_MAP2]
    nt_m2, at_m2 = [0] * 768, [0] * 768
    for (adr, size, attr) in NT_MAP2:
        n = unpack_tilemap(rom, adr, size, attr, nt_m2, at_m2)
        if n != 768:
            raise SystemExit(f"mapa 2 (${adr:05X}): {n} komórek")
    if len(spr_m2) > 0x1000 or len(rle_m2[0]) + len(rle_m2[1]) > 0x300:
        raise SystemExit("mapa 2: pary sprite'ow > 4 KiB albo RLE > 768 B (map2_copy w src/scr/boot.asm)")
    # uklad: pary kafli od 0 (dopelnione do 4 KiB - kopia stronami do LAYOUT_RAM), RLE warstwy A i B od $1000 (3 strony do $DA00)
    (out / "ekr_mapa2.bin").write_bytes(spr_m2 + bytes(0x1000 - len(spr_m2)) + rle_m2[0] + rle_m2[1])
    (out / "ekr_rle_wynik.bin").write_bytes(rom[NT_SCORE[0]:NT_SCORE[0] + NT_SCORE[1]])
    (out / "ekr_rle_wynik_sp.bin").write_bytes(rom[NT_SCORE_SP[0]:NT_SCORE_SP[0] + NT_SCORE_SP[1]])
    (out / "ekr_rle_go.bin").write_bytes(rom[NT_GO[0]:NT_GO[0] + NT_GO[1]])
    atlasy = pack4(t_bg) + pack4(m_bg)
    if len(atlasy) != 0x4000:
        raise SystemExit("atlasy tła: zły rozmiar")
    (out / "bank_ekr_atlasy.bin").write_bytes(atlasy)
    (out / "ekr_rom0.bin").write_bytes(rom0)
    (out / "ekr_rle_tytul.bin").write_bytes(rom[NT_TITLE[0]:NT_TITLE[0] + NT_TITLE[1]])
    (out / "ekr_rle_mapa1a.bin").write_bytes(rom[NT_MAP1[0][0]:NT_MAP1[0][0] + NT_MAP1[0][1]])
    (out / "ekr_rle_mapa1b.bin").write_bytes(rom[NT_MAP1[1][0]:NT_MAP1[1][0] + NT_MAP1[1][1]])
    spr_t = spr_pairs(sorted(p_t), {i: t_spr256[i] for i in range(256)})
    spr_m = spr_pairs(sorted(p_m), {i: m_spr[i] for i in range(256)})
    (out / "ekr_spr_tytul.bin").write_bytes(spr_t)
    (out / "ekr_spr_mapa1.bin").write_bytes(spr_m)
    inc = [
        "; tools/extract_ekrany.py - ekrany przed poziomem (dane z ROM-u SMS, build/assets/ekrany)",
        f"EKR_R0_FROM = ${ROM0_FROM:04X}   ; ekr_rom0.bin: bajty banku 0 ROM-u od tego adresu SMS",
        f"EKR_R0_SIZE = {len(rom0)}",
        f"EKR_RLE_T = {NT_TITLE[1]}   ; dlugosc RLE mapy tytulu (bc w run_title_screen 00:12BA)",
        f"EKR_RLE_MA = {NT_MAP1[0][1]}   ; dlugosc RLE warstwy A mapy 1 (00:0CB5)",
        f"EKR_RLE_MB = {NT_MAP1[1][1]}   ; dlugosc RLE warstwy B mapy 1 (00:0CC6)",
        f"EKR_RLE_W = {NT_SCORE[1]}   ; dlugosc RLE mapy ekranu wyniku (bc w handle_level_score_screen 00:1596)",
        f"EKR_RLE_WS = {NT_SCORE_SP[1]}   ; dlugosc RLE mapy ekranu wyniku etapu specjalnego (bc w 00:15A6)",
        f"EKR_RLE_G = {NT_GO[1]}   ; dlugosc RLE mapy ekranu game over (bc w run_game_over_screen 00:1427)",
        f"EKR_SPR_T_N = {len(p_t)}   ; pary kafli 8x16 tytulu (ekr_spr_tytul.bin: kafel + 64 B 4 bpp)",
        f"EKR_SPR_M_N = {len(p_m)}   ; pary kafli 8x16 mapy 1 (ekr_spr_mapa1.bin)",
        f"EKR_SPR_T_SIZE = {len(spr_t)}",
        f"EKR_SPR_M_SIZE = {len(spr_m)}",
        f"EKR_RLE_M2A = {NT_MAP2[0][1]}   ; M6.8: RLE warstwy A mapy 2 (00:0D17) - ekr_mapa2.bin od $1000",
        f"EKR_RLE_M2B = {NT_MAP2[1][1]}   ; RLE warstwy B mapy 2 (00:0D28) - za warstwa A",
        f"EKR_SPR_M2_N = {len(p_m2)}   ; pary kafli 8x16 mapy 2 - ekr_mapa2.bin od 0",
        f"EKR_SPR_M2_SIZE = {len(spr_m2)}",
        f"EKR_MAPA2_SIZE = {0x1000 + len(rle_m2[0]) + len(rle_m2[1])}",
        "",
    ]
    (out / "ekrany.inc").write_text("\n".join(inc), encoding="ascii")

    # podglądy: tytuł (napis widoczny, dłoń 1) i mapa 1 (GHZ1: napis strefy, życia 3, znacznik)
    nt_t2 = list(nt_t)
    s = rom0[0x1352 - ROM0_FROM: 0x1362 - ROM0_FROM]              # sprtext_show_press_button: x, y, kafle..., $FF
    for k, v in enumerate(s[2:]):
        if v == 0xFF:
            break
        nt_t2[s[1] * 32 + s[0] + k] = v
    sat_t = dss(rom0, SPRTAB_HAND[0], 0x80, 0x18)
    img_t = render(nt_t2, at_t, sat_t, rom0[PAL_TITLE - ROM0_FROM:PAL_TITLE - ROM0_FROM + 32], t_bg, t_spr256)
    Image.fromarray(sms_rgb_arr(img_t)).save(out / "podglad-tytul.png")
    nt_m2, at_m2 = list(nt_m), list(at_m)
    s = rom0[0x122D - ROM0_FROM: 0x123C - ROM0_FROM]              # level_title_font0_GHZ
    for k, v in enumerate(s[2:]):
        if v == 0xFF:
            break
        nt_m2[s[1] * 32 + s[0] + k], at_m2[s[1] * 32 + s[0] + k] = v, 0x10
    lives = [(0xA7, 0x28 + 8 * k, t) for k, t in enumerate([0x80, 0x86])]   # 3 zycia: "03"
    mk = struct.unpack_from("<H", rom0, LUT_LEVEL_MAP_INFO - ROM0_FROM)[0]
    m0, mx, my, _ = struct.unpack_from("<HBBB", rom0, mk - ROM0_FROM)
    sat_m = lives + dss(rom0, m0, mx, my)
    img_m = render(nt_m2, at_m2, sat_m, rom0[PAL_MAP1 - ROM0_FROM:PAL_MAP1 - ROM0_FROM + 32], m_bg, m_spr)
    Image.fromarray(sms_rgb_arr(img_m)).save(out / "podglad-mapa1.png")
    cram2 = rom[PAL_MAP2:PAL_MAP2 + 32]                           # M6.8: podglad mapy 2 (tlo, bez sprite'ow)
    Image.fromarray(sms_rgb_arr(render(nt_m2, at_m2, [(0xD0, 0, 0)], cram2, m2_bg, m2_spr))).save(out / "podglad-mapa2.png")
    print(f"ekrany: tytuł 256 kafli tła, {len(p_t)} par sprite'ów ({len(spr_t)} B); mapa 1 256 kafli tła, "
          f"{len(p_m)} par sprite'ów ({len(spr_m)} B, znaczniki {len(marker_maps)}); ROM bank 0 {len(rom0)} B")

    nt_w, at_w = [0] * 768, [0] * 768
    n = unpack_tilemap(rom, NT_SCORE[0], NT_SCORE[1], 0, nt_w, at_w)
    if n != 768:
        raise SystemExit(f"mapa wyniku: {n} komórek")
    # M6.3: ekran game over (bez kontynuacji) - model obrazu: tło ART_09_351F, mapa ARTMAP_05_67FE, paleta 00:14FC
    nt_g, at_g = [0] * 768, [0] * 768
    n = unpack_tilemap(rom, NT_GO[0], NT_GO[1], NT_GO[2], nt_g, at_g)
    if n != 768:
        raise SystemExit(f"mapa game over: {n} komórek")
    img_g = render(nt_g, at_g, [], rom0[PAL_GO - ROM0_FROM:PAL_GO - ROM0_FROM + 32], s_bg, np.zeros((256, 8, 8), np.uint8))
    Image.fromarray(sms_rgb_arr(img_g)).save(out / "podglad-gameover.png")
    np.save(out / "model-gameover.npy", img_g)
    print(f"game over: {len(set(nt_g))} różnych kafli w mapie, RLE {NT_GO[1]} B")
    if a.wynik:
        import json
        d = np.load(a.wynik)
        meta = json.loads(Path(a.wynik).with_suffix(".json").read_text(encoding="utf-8"))
        ram = dict(kv.split(":") for kv in meta["ram_w_score"].split(","))
        lvl, lives, rings = int(ram["level"]), int(ram["lives"]), int(ram["rings"], 16)
        mins, secs = int(ram["time"][:2], 16), int(ram["time"][2:], 16)
        nt, at = list(nt_w), list(at_w)
        off = rom0[0x1B69 - ROM0_FROM + lvl]                      # numer aktu: 4 wiersze po 2 kafle od (x=$15, y=5)
        for r in range(4):
            k = (5 + r) * 32 + 0x15
            nt[k], nt[k + 1] = rom0[0x1B51 - ROM0_FROM + off + 2 * r], rom0[0x1B51 - ROM0_FROM + off + 2 * r + 1]
        ub = rom0[0x153E - ROM0_FROM:0x154E - ROM0_FROM]           # premia za czas: pierwszy próg <= czas
        bonus = [0, 0, 0, 0]
        for i in range(8):
            if (mins, secs) >= (ub[2 * i], ub[2 * i + 1]):
                ptr = struct.unpack_from("<H", rom0, 0x154E - ROM0_FROM + 2 * i)[0]
                bonus = list(rom0[ptr - ROM0_FROM:ptr - ROM0_FROM + 4])
                break

        def bcd_str(bs):                                          # build_BCD_FFstr 00:1B13
            out, lead = [], True
            for b in bs:
                for nib in (b >> 4, b & 15):
                    if lead and nib == 0:
                        out.append(0xFE)
                    else:
                        lead = False
                        out.append(0x80 + 2 * nib)
            if lead:
                out[-1] = 0x80
            return out

        def text(x, y, s):                                        # draw_sprite_text 00:35CC
            o = []
            for c in s:
                if c != 0xFE:
                    o.append((y, x, c))
                x += 8
            return o
        sat = text(0x88, 0x50, bcd_str([0, 0, 0, 0])) + text(0x98, 0x80, bcd_str([rings]))
        sat += text(0xC0, 0x80, bcd_str(list(rom0[0x151C - ROM0_FROM:0x151E - ROM0_FROM])))
        sat += text(0x38, 0x9F, [0x80 + 2 * (lives // 10), 0x80 + 2 * (lives % 10)])
        sat += text(0x88, 0x68, bcd_str(bonus))
        spr = np.zeros((256, 8, 8), np.uint8)
        spr[128:192] = tiles8(rom, ART_HUD, 64)
        cram = rom0[PAL_SCORE - ROM0_FROM:PAL_SCORE - ROM0_FROM + 32]
        img_w = render(nt, at, sat, cram, s_bg, spr)
        Image.fromarray(sms_rgb_arr(img_w)).save(out / "podglad-wynik.png")
        it1 = meta["irq_w_score_it1"]
        idx = [i for i in range(len(d["irqs"])) if d["irqs"][i] == it1 + 1 and d["czesc"][i] == 2]
        if not idx:
            raise SystemExit("brak klatki referencji po 1. iteracji pokazu wyniku")
        dw = int((d["klatki"][idx[0]] != img_w).sum())
        print(f"kontrola ekranu wyniku (IRQ {it1 + 1}): różnych pikseli {dw}")
        if dw:
            Image.fromarray(sms_rgb_arr(d["klatki"][idx[0]])).save(out / "mesen-wynik.png")
            return 4
    if a.kontrola:
        d = np.load(a.kontrola)
        k, ti, mi = d["klatki"], d["tytul_it"], d["mapa_it"]
        it = np.nonzero(ti == 2)[0][0]                            # tytuł: napis (iteracja 2), dłoń 1 (iteracja 1)
        dt = int((k[it] != img_t).sum())
        print(f"kontrola tytułu (rekord {it}, iteracja 2): różnych pikseli {dt}")
        # mapa: rekord iteracji 2 (sprite'y z iteracji 1: życia + znacznik GHZ1 widoczny 30 ramek)
        im = np.nonzero((mi == 2) & (d["faza"] == 6))[0][0]
        dm = int((k[im] != img_m).sum())
        print(f"kontrola mapy 1 (rekord {im}, iteracja 2): różnych pikseli {dm}")
        if dt or dm:
            Image.fromarray(sms_rgb_arr(k[it])).save(out / "mesen-tytul.png")
            Image.fromarray(sms_rgb_arr(k[im])).save(out / "mesen-mapa1.png")
            return 4
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
