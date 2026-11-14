#!/usr/bin/env python3
"""M5.4: efekty dźwiękowe - stan PSG oryginału SMS na ramkę (tools/m5_sfx_ref.py) -> kanał 3 POKEY.

Użycie: python tools/pack_sfx.py [--out build/assets/music] [--raport]

Wejście: tools/data/sfx_ref_pal.json (stan PSG efektów nagrany z oryginału SMS w emulatorze),
priorytety i kanały efektów z tablicy sound_effect_ptr_table (ROM 03:4740). Wyjście (z ROM-u - tylko build/,
ignorowane przez git): sfx.bin (do banku efektów) i sfx_dir.inc.

Przeliczenie ramki (efekt gra na jednym kanale PSG: ton 2 albo szum):
  - tłumienie PSG a (2 dB na stopień, 15 = cisza) -> głośność POKEY round(15 * 10^(-a/10)), cisza -> AUDC 0;
  - ton: f = 3 546 893 / (32 * okres) (zegar SMS PAL); f >= 3412 Hz - kanał 3 na 1,79 MHz (AUDCTL b5):
    AUDF = 1 773 447 / (2f) - 4; niżej zegar 64 kHz (1 773 447 / 28): AUDF = 63 337 / (2f) - 1; poniżej 124 Hz
    oktawę wyżej (4 efekty spoza GHZ1: $19, $1C, $1D, $21); AUDC $A0 | głośność (czysty ton);
  - szum (zawsze biały, szybkość 0/1/2 = zegar / 512 / 1024 / 2048): AUDC $80 | głośność (poly17),
    AUDF = 63 337 / f_przesuwu - 1 (4, 8, 17);
  - ramka = 2 B: AUDF3, AUDC3 z bitem 4 (w AUDC nieużywany „tylko głośność”) jako znacznikiem zegara 1,79 MHz.
Efekty grające w pętli (nagranie doszło do limitu ramek: $0B, $0D, $0E) - najkrótszy okres na końcu
nagrania: zapis do końca pierwszego okresu i punkt powrotu.

Obraz (adresy w oknie banku $4000, plik dołączany za danymi muzyki - wspólny bank):
  +0  7 tablic po N B (indeks = numer efektu): adres pierwszej ramki lo, hi; liczba ramek lo, hi; ramka powrotu
      pętli lo, hi ($FFFF = bez pętli); priorytet (1 ważniejszy, 2 zwykły - jak sterownik SMS)
  dalej ramki
"""
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import extract_sms  # noqa: E402

CLK_SMS = 3546893
CLK_POKEY = 1773447
BASE64 = CLK_POKEY / 28
N_SFX = 0x23
LIMIT = 1500        # maks. ramek nagrania efektu (m5_sfx_ref.py --max) - efekty w pętli dochodzą do limitu
VOL = [round(15 * 10 ** (-a / 10)) for a in range(15)] + [0]     # 2 dB = 10^(-2/20) amplitudy na stopień


def tablica_rom() -> list[tuple[int, int]]:
    rom = extract_sms.DEFAULT_ROM.read_bytes()
    baza = 3 * 0x4000 + (0x4740 - 0x4000)
    wyn = []
    for i in range(N_SFX):
        e = rom[baza + 4 * i:baza + 4 * i + 4]
        ptr = e[0] | e[1] << 8
        wyn.append((e[2], rom[3 * 0x4000 + ptr - 0x4000]))          # priorytet, kanał PSG
    return wyn


def ramka_pokey(f: list[int], kanal: int) -> tuple[int, int]:
    if kanal == 3:
        tl = f[7]
        if tl == 15:
            return 0, 0
        szybkosc = f[6] & 3
        assert szybkosc < 3 and f[6] & 4, f"szum {f[6]} poza obsługiwanym zakresem"
        przesuw = CLK_SMS / 16 / (16 << szybkosc)
        audf = max(0, min(255, round(BASE64 / przesuw - 1)))
        return audf, 0x80 | VOL[tl]
    tl = f[5]
    if tl == 15:
        return 0, 0
    hz = CLK_SMS / (32 * f[4])
    if hz >= CLK_POKEY / (2 * (255 + 4)):
        return max(0, min(255, round(CLK_POKEY / (2 * hz) - 4))), 0xA0 | 0x10 | VOL[tl]
    while hz < BASE64 / 512:
        hz *= 2
    return max(0, min(255, round(BASE64 / (2 * hz) - 1))), 0xA0 | VOL[tl]


def petla(r: list[tuple[int, int]], limit: int) -> tuple[int, int] | None:
    """(początek, okres) najkrótszej pętli na końcu nagrania, które doszło do limitu ramek."""
    if len(r) < limit:
        return None
    najlepsza = None
    for p in range(1, len(r) // 3):
        s = len(r) - p
        while s > 0 and r[s - 1] == r[s - 1 + p]:       # okresowość od końca nagrania wstecz
            s -= 1
        if len(r) - s < 3 * p:                           # co najmniej 3 okresy
            continue
        if najlepsza is None or s < najlepsza[0]:        # najwcześniejszy początek (najwięcej nagrania)
            najlepsza = (s, p)
    if najlepsza is None:
        raise ValueError("nagranie doszło do limitu, ale nie znaleziono pętli")
    return najlepsza


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="M5.4: efekty SMS -> kanał 3 POKEY")
    ap.add_argument("--out", default=str(ROOT / "build" / "assets" / "music"))
    ap.add_argument("--baza", type=lambda x: int(x, 0), default=0x4000, help="adres pliku w oknie banku")
    ap.add_argument("--raport", action="store_true")
    a = ap.parse_args(argv)
    ref = ROOT / "tools" / "data" / "sfx_ref_pal.json"
    if not ref.is_file():
        print(f"ERROR: missing {ref}", file=sys.stderr)
        return 1
    dane = json.loads(ref.read_text(encoding="utf-8"))
    limit = LIMIT
    tab = tablica_rom()
    kol: list[list[int]] = [[] for _ in range(7)]
    strumien = bytearray()
    naglowek = 7 * N_SFX
    for n in range(N_SFX):
        prio, kanal = tab[n]
        ramki = [ramka_pokey(f, kanal) for f in dane[str(n)]]
        lp = petla(ramki, limit)
        if lp:
            s, p = lp
            ramki = ramki[:s + p]
            powrot = s
        else:
            while ramki and ramki[-1][1] == 0:         # cisza na końcu - odtwarzacz wycisza sam
                ramki.pop()
            powrot = 0xFFFF
        adr = a.baza + naglowek + len(strumien)
        n_r = len(ramki)
        for t, v in enumerate((adr & 0xFF, adr >> 8, n_r & 0xFF, n_r >> 8, powrot & 0xFF, powrot >> 8, prio)):
            kol[t].append(v)
        for audf, audc in ramki:
            strumien += bytes([audf, audc])
        if a.raport:
            print(f"SFX ${n:02X}: kanał PSG {kanal}, priorytet {prio}, ramek {len(ramki):3d}"
                  + (f", pętla od {powrot} (okres {len(ramki) - powrot})" if powrot != 0xFFFF else ""))
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    obraz = bytes(sum(kol, [])) + bytes(strumien)
    (out / "sfx.bin").write_bytes(obraz)
    (out / "sfx_dir.inc").write_text(
        "; sfx_dir.inc - generowany przez tools/pack_sfx.py; nie edytowac\n"
        f"SFX_N = {N_SFX}\nSFX_BYTES = {len(obraz)}\n", encoding="ascii")
    print(f"efekty: {N_SFX}, {len(obraz)} B -> {out / 'sfx.bin'}")
    return 0


if __name__ == "__main__":
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main(sys.argv[1:]))
