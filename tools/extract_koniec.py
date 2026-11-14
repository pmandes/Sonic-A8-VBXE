#!/usr/bin/env python3
"""Ekstrakcja danych ekranow konca gry (M6.11): run_ending_and_credits (00:258B), wynik koncowy, napisy.

Wejscie: ROM SMS (jak tools/extract_sms.py, poza repozytorium; suma SHA-256 sprawdzana).
Wyjscie (build/assets/ekrany/, poza gitem - dane z ROM-u):
  koniec_r0.bin   - bajty banku 0 ROM-u $2825-$2AF5 (721 B): FFstr_chaos_emerald_or_monitor_image (00:2825),
                    PAL3_ending_tally (00:2828), credits_sprite_00..03 i mapy csXX (00:2848-00:2904),
                    credits_text_sequence_script_data (00:2905-00:2AD5), PAL3_credits (00:2AD6). Port czyta je pod
                    adresem SMS + KO_OFS (src/scr/koniec.asm) - jeden blok, bo slowa w danych napisow (wskazniki
                    animacji sprite'ow) to adresy SMS z tego zakresu.
  koniec_spin.bin - LUT_ending_chaos_emerald_spin_animation (00:241D, 366 B: 61 krokow x 3 pary x (dx, dy))
  koniec_ram.bin  - blok do RAM (kopia z banku przed ekranami konca; src/scr/koniec.asm: KO_RAM):
                    RLE map ekranu ARTMAP_05_6830 ($179 B), ARTMAP_05_69A9 ($145 B), ARTMAP_05_6C61 ($189 B),
                    pary kafli sprite'ow A (wynik koncowy: cyfry $80-$92 z ART_09_B92E, szmaragd $5C/$5E z grafiki
                    monitora 05:5400) i B (napisy: 22 pary z ART_09_4B0A) - format jak ekr_spr_*.bin: [kafel
                    parzysty, 64 B (2 kafle 4 bpp, starsza polowka = lewy piksel)] ...
  koniec.inc      - stale MADS (rozmiary, przesuniecia w blokach, liczby par)
  podglad-koniec-*.png - podglad kontrolny (model obrazu VDP z tools/extract_ekrany.py)
Adresy i liczby: docs/plan-m6.md 15.6.2, dezasemblacja s1smsdisasm-gm (tylko material referencyjny).
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
from extract_ekrany import pack4, render, sms_rgb_arr, unpack_tilemap  # noqa: E402

# bank 0 ROM-u (adres SMS = offset w ROM)
R0_FROM, R0_TO = 0x2825, 0x2AF6          # FFstr szmaragdu .. koniec PAL3_credits
FFSTR_EMERALD = 0x2825                   # $5C $5E $FF (draw_sprite_text 00:25FF, 00:2641, 00:265E)
PAL_TALLY = 0x2828                       # PAL3_ending_tally (signal_load_palettes 00:25A6, fade 00:2690)
CREDITS_SPRITES = [0x2848, 0x2857, 0x2869, 0x2872]   # credits_sprite_00..03 (00:26DD-00:26F8)
SCRIPT_FROM, SCRIPT_TO = 0x2905, 0x2AD6  # credits_text_sequence_script_data (00:270F)
PAL_CREDITS = 0x2AD6                     # PAL3_credits (palette_fade_in_banks_01_02 00:2705)
SPIN_FROM, SPIN_TO = 0x241D, 0x258B      # LUT_ending_chaos_emerald_spin_animation (00:260B)
# napisy FF wyniku koncowego (00:1907-00:19B3) sa juz w ekr_rom0.bin (bank 0 $0E72-$1BAC) - tylko do podgladu
FF_FINAL = [0x1907, 0x191C, 0x1931, 0x1946, 0x1953, 0x1960, 0x196D, 0x197E]   # 00:1785-00:17B2
# mapy ekranu (bank 5 w slocie 1: ROM $14000 + adres - $4000), dlugosc RLE z rejestru bc w kodzie
NT_END = (0x14000 + 0x6830 - 0x4000, 0x0179)      # ARTMAP_05_6830 (00:25BC)
NT_GOOD = (0x14000 + 0x69A9 - 0x4000, 0x0145)     # ARTMAP_05_69A9 (00:267D, dobre zakonczenie)
NT_CRED = (0x14000 + 0x6C61 - 0x4000, 0x0189)     # ARTMAP_05_6C61 (00:26C9, napisy)
# grafika (offset w ROM = bank * $4000 + adres w slocie, load_art 00:0405)
ART_MAP1_BG = 0x30000 + 0x0000           # ART_0C_0000 -> VRAM $0000 (00:25A9) = atlas mapy 1 (bank 51 $6000)
ART_MAP2_BG = 0x30000 + 0x1801           # ART_0C_1801 -> VRAM $0000 (00:26AB) = atlas mapy 2 (bank 53 $6000)
ART_TITLE_SPR = 0x24000 + 0x4B0A         # ART_09_4B0A -> VRAM $2000 (00:26B6) - kafle sprite'ow napisow
ART_HUD = 0x24000 + 0xB92E               # ART_09_B92E -> VRAM $3000 (00:2172, start kazdego poziomu): cyfry $80+
ART_EMERALD = 0x14000 + 0x5400 - 0x4000  # 05:5400 - ikona szmaragdu (4 kafle VDP bez kompresji); obiekt $54
                                         # (02:BF53, write_partial_monitor_art 00:0C1D) pisze ja do kafli $5C-$5F
HUD_DIGITS = [0x80 + 2 * d for d in range(10)]   # build_BCD_FFstr (00:1B13), draw_tally_screen_lives (00:1ACA)


def credits_maps(rom: bytes) -> list[int]:
    """Adresy map csXX z list animacji credits_sprite_0N: wpisy [czas, slowo mapy], czas $FF = skok (slowo)."""
    maps = []
    for p in CREDITS_SPRITES:
        seen = set()
        while p not in seen:
            seen.add(p)
            if rom[p] == 0xFF:
                break
            maps.append(struct.unpack_from("<H", rom, p + 1)[0])
            p += 3
    return sorted(set(maps))


def map_tiles(rom: bytes, m: int) -> set[int]:
    """Kafle mapy csXX: x, y, potem do 3 wierszy po 6 B (draw_sprite_string 00:350F)."""
    out = set()
    for r in range(3):
        row = rom[m + 2 + 6 * r: m + 8 + 6 * r]
        if row[0] == 0xFF:
            break
        out |= {t & 0xFE for t in row if t < 0xFE}
    return out


def dss_cs(rom: bytes, m: int) -> list[tuple[int, int, int]]:
    """Wpisy tablicy sprite'ow (y, x, kafel) mapy csXX (draw_credits_sprite 00:2786-00:2790)."""
    x, y = rom[m], rom[m + 1]
    out = []
    for r in range(3):
        row = rom[m + 2 + 6 * r: m + 8 + 6 * r]
        if row[0] == 0xFF:
            break
        for k, t in enumerate(row):
            if t < 0xFE:
                out.append((y + 16 * r, x + 8 * k, t))
    return out


def script_stats(rom: bytes) -> tuple[int, int, int, int, int]:
    """run_credits_text_sequence (00:2795): ramki skryptu, znaki, pozycje ($FE), czekania ($FD), przewiniecia."""
    s = rom[SCRIPT_FROM:SCRIPT_TO]
    i, fr, nch, nfe, nfd, nsc = 2, 0, 0, 0, 0, 0
    while True:
        a = s[i]
        i += 1
        if a == 0xFF:
            break
        if a == 0xFE:
            nfe += 1
            i += 2
        elif a == 0xFC:
            nsc += s[i]
            fr += 12 * s[i]
            i += 1
        elif a == 0xFD:
            nfd += 1
            fr += s[i] | (s[i + 1] << 8)
            i += 2
        else:
            nch += 1
            fr += 8
    if i != len(s):
        raise SystemExit(f"skrypt napisow: koniec po {i} B zamiast {len(s)}")
    return fr, nch, nfe, nfd, nsc


def spr_pairs(pairs: list[int], tiles: dict[int, np.ndarray]) -> bytes:
    out = bytearray()
    for t in pairs:
        out.append(t)
        out += pack4(np.concatenate([tiles[t], tiles[t + 1]]))   # 8x16
    return bytes(out)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rom", default=str(DEFAULT_ROM))
    ap.add_argument("--out", default=str(ROOT / "build" / "assets" / "ekrany"))
    a = ap.parse_args(argv)
    rom = Path(a.rom).read_bytes()
    if hashlib.sha256(rom).hexdigest() != ROM_SHA256:
        print("BLAD: ROM o innej sumie SHA-256 niz oczekiwana", file=sys.stderr)
        return 1
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    # --- kontrola danych banku 0 ---
    if rom[FFSTR_EMERALD:FFSTR_EMERALD + 3] != bytes([0x5C, 0x5E, 0xFF]):
        raise SystemExit("FFstr szmaragdu: inne bajty")
    if struct.unpack_from("<H", rom, 0x15580 + 2 * 0x13)[0] != 0:
        raise SystemExit("naglowek poziomu $13 != 0 (load_and_run_level 00:1D0E nie przejdzie do konca)")
    fr, nch, nfe, nfd, nsc = script_stats(rom)
    if (fr, nch, nfe, nfd, nsc) != (5468, 259, 42, 19, 78):   # plan 15.6.2: 5484 / 261 liczyl x, y startu jako znaki
        raise SystemExit(f"skrypt napisow: {fr} ramek, {nch} znakow, {nfe} pozycji, {nfd} czekan, {nsc} przewiniec")
    r0 = rom[R0_FROM:R0_TO]
    spin = rom[SPIN_FROM:SPIN_TO]
    if len(spin) != 61 * 3 * 2:
        raise SystemExit("LUT obrotu szmaragdow: zly rozmiar")
    cmaps = credits_maps(rom)
    for m in cmaps:
        if not R0_FROM <= m < SCRIPT_FROM:
            raise SystemExit(f"mapa csXX ${m:04X} poza blokiem koniec_r0.bin")

    # --- mapy ekranu ---
    rle = []
    nts = []
    for adr, size in (NT_END, NT_GOOD, NT_CRED):
        nt, at = [0] * 768, [0] * 768
        n = unpack_tilemap(rom, adr, size, 0, nt, at)
        if n != 768:
            raise SystemExit(f"mapa ${adr:05X}: {n} komorek")
        rle.append(rom[adr:adr + size])
        nts.append((nt, at))

    # --- pary kafli sprite'ow ---
    spr = np.zeros((256, 8, 8), np.uint8)          # stan kafli sprite'ow VDP na ekranach konca (port: tylko pary z listy)
    spr[0x80:0xC0] = planar_to_8bpp(decode_hy_art(rom, ART_HUD), 64)
    spr[0x5C:0x60] = planar_to_8bpp(rom[ART_EMERALD:ART_EMERALD + 128], 4)
    pairs_a = sorted(set(HUD_DIGITS) | {0x5C, 0x5E})
    spr_b = np.array(spr)
    spr_b[0x00:0x80] = planar_to_8bpp(decode_hy_art(rom, ART_TITLE_SPR), 128)
    pairs_b = set()
    for m in cmaps:
        pairs_b |= map_tiles(rom, m)
    pairs_b = sorted(pairs_b)
    if len(pairs_b) != 22 or max(pairs_b) >= 0x80 or set(pairs_b) & set(pairs_a):
        raise SystemExit(f"pary napisow: {[hex(t) for t in pairs_b]}")
    blk_a = spr_pairs(pairs_a, {i: spr[i] for i in range(256)})
    blk_b = spr_pairs(pairs_b, {i: spr_b[i] for i in range(256)})

    # --- blok RAM: RLE x 3, pary A, pary B ---
    ram = bytearray()
    ofs = {}
    for name, d in (("RLE_A", rle[0]), ("RLE_B", rle[1]), ("RLE_C", rle[2]), ("SPR_A", blk_a), ("SPR_B", blk_b)):
        ofs[name] = (len(ram), len(d))
        ram += d
    (out / "koniec_r0.bin").write_bytes(r0)
    (out / "koniec_spin.bin").write_bytes(spin)
    (out / "koniec_ram.bin").write_bytes(bytes(ram))
    inc = [
        "; tools/extract_koniec.py - ekrany konca gry M6.11 (dane z ROM-u SMS, build/assets/ekrany)",
        f"KO_R0_FROM = ${R0_FROM:04X}   ; koniec_r0.bin: bajty banku 0 ROM-u od tego adresu SMS (adres portu = SMS + KO_OFS)",
        f"KO_R0_SIZE = {len(r0)}",
        f"KO_SPIN_SIZE = {len(spin)}   ; koniec_spin.bin: LUT_ending_chaos_emerald_spin_animation (00:241D)",
        f"KO_RAM_SIZE = {len(ram)}   ; koniec_ram.bin: blok w RAM (KO_RAM)",
        f"KO_RAM_PAGES = {(len(ram) + 255) // 256}   ; strony 256 B (kopia copy_pages)",
        f"KO_RLE_A_OFS = {ofs['RLE_A'][0]}   ; ARTMAP_05_6830 (00:25BC)",
        f"KO_RLE_A_N = {ofs['RLE_A'][1]}",
        f"KO_RLE_B_OFS = {ofs['RLE_B'][0]}   ; ARTMAP_05_69A9 (00:267D)",
        f"KO_RLE_B_N = {ofs['RLE_B'][1]}",
        f"KO_RLE_C_OFS = {ofs['RLE_C'][0]}   ; ARTMAP_05_6C61 (00:26C9)",
        f"KO_RLE_C_N = {ofs['RLE_C'][1]}",
        f"KO_SPR_A_OFS = {ofs['SPR_A'][0]}   ; pary sprite'ow wyniku koncowego: cyfry $80-$92, szmaragd $5C/$5E",
        f"KO_SPR_A_N = {len(pairs_a)}",
        f"KO_SPR_B_OFS = {ofs['SPR_B'][0]}   ; pary sprite'ow napisow (ART_09_4B0A)",
        f"KO_SPR_B_N = {len(pairs_b)}",
        "",
    ]
    (out / "koniec.inc").write_text("\n".join(inc), encoding="ascii", newline="\n")

    # --- podglady (model VDP z extract_ekrany.render) ---
    bg1 = planar_to_8bpp(decode_hy_art(rom, ART_MAP1_BG), 256)
    bg2 = planar_to_8bpp(decode_hy_art(rom, ART_MAP2_BG), 256)
    pal_t = rom[PAL_TALLY:PAL_TALLY + 32]
    pal_c = rom[PAL_CREDITS:PAL_CREDITS + 32]

    def emer(x, y):
        return [(y, x, 0x5C), (y, x + 8, 0x5E)]
    nt, at = nts[0]
    img = render(nt, at, emer(0x70, 0x60), pal_t, bg1, spr)
    Image.fromarray(sms_rgb_arr(img)).save(out / "podglad-koniec-obraz.png")
    nt, at = list(nts[1][0]), list(nts[1][1])
    for adr in FF_FINAL:                                          # wynik koncowy po napisach (tmp_00 = 0)
        x, y = rom[adr], rom[adr + 1]
        k = 2
        while rom[adr + k] != 0xFF:
            nt[y * 32 + x + k - 2] = rom[adr + k]
            k += 1
    sat = [(0x80, 0x90 + 8 * k, 0x80) for k in range(8)]          # wynik "00000000" (podglad)
    img = render(nt, at, sat, pal_t, bg1, spr)
    Image.fromarray(sms_rgb_arr(img)).save(out / "podglad-koniec-wynik.png")
    nt, at = nts[2]
    sat = []
    for p in CREDITS_SPRITES:                                     # pierwsza klatka kazdej animacji
        sat += dss_cs(rom, struct.unpack_from("<H", rom, p + 1)[0])
    img = render(nt, at, sat, pal_c, bg2, spr_b)
    Image.fromarray(sms_rgb_arr(img)).save(out / "podglad-koniec-napisy.png")
    print(f"koniec: r0 {len(r0)} B, LUT obrotu {len(spin)} B, blok RAM {len(ram)} B (RLE {sum(map(len, rle))} B, "
          f"pary A {len(pairs_a)} ({len(blk_a)} B), pary B {len(pairs_b)} ({len(blk_b)} B)); skrypt {fr} ramek, "
          f"{nch} znakow, {nsc} przewiniec")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
