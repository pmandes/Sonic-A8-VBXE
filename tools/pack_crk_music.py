#!/usr/bin/env python3
"""Muzyka cracktro: utwor SKY1 - Scrap Brain Zone (utwor 6 z wersji C64, wariant mono-buzzy; naglowek SKY1 w ROM-ie: muzyka $04) -> LZSS16 -> src/boot/crk_music.lz16.

Uzycie:  python tools/pack_crk_music.py [--utwor 7]

Ten sam kompresor i ten sam format strumienia co muzyka gry (tools/pack_music.py: LZSS16 z dmsc/lzss-sap, MIT): bajt 0 = maska
stalych strumieni, 9 wartosci poczatkowych, dalej dane. Plik jest zrodlem cracktro (src/boot/crack.asm, `ins`), liczba ramek
(CRK_MFR) jest tam stala - skrypt ja wypisuje i sprawdza dekoderem kontrolnym (lzss16_dekoduj) oraz zgodnoscia ze strumieniem
w build/assets/music/bank_music.bin, jesli ten istnieje. Cracktro odtwarza tylko utwor ze stalym kanalem 3 i AUDCTL (jak gra).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pack_music as pm  # noqa: E402

CEL = pm.ROOT / "src" / "data" / "crk_music.lz16"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--utwor", type=int, default=6, help="numer utworu HVSC (6 = Scrap Brain Zone - muzyka SKY1)")
    a = ap.parse_args()
    utwory = json.loads((pm.MUZYKA / "subtunes.json").read_text(encoding="utf-8"))
    u = next(x for x in utwory if x["subtune"] == a.utwor)
    raw = pm.czytaj_sapr(pm.MUZYKA / f"{u['stem']}.sapr")
    n = len(raw) // 9
    fr = np.frombuffer(raw, np.uint8).reshape(n, 9)
    for r, nazwa in ((4, "AUDF3"), (5, "AUDC3"), (8, "AUDCTL")):
        assert np.all(fr[:, r] == fr[0, r]), f"{nazwa} zmienia sie w utworze"
    comp = pm.lzss16_kompresuj(raw)
    # dekoder cracktro: stale strumienie x = 8, 5, 4 (bity maski 0, 3, 4) dziela strone bufora z x = 0 (crk_mpg w src/boot/crack.asm)
    assert comp[0] & 0x19 == 0x19, f"maska {comp[0]:#07b}: AUDF3 / AUDC3 / AUDCTL musza byc stale"
    assert pm.lzss16_dekoduj(comp, n) == raw, "dekoder kontrolny rozny od SAP-R"
    bank = pm.ROOT / "build" / "assets" / "music" / "bank_music.bin"
    if bank.is_file():                                   # ten sam strumien co w banku muzyki gry
        b = bank.read_bytes()
        e = b[1 + 6 * (a.utwor - 1):7 + 6 * (a.utwor - 1)]
        adr = e[0] | e[1] << 8
        assert b[adr - pm.BANK_WIN:adr - pm.BANK_WIN + len(comp)] == comp, "inny niz w banku muzyki"
    CEL.write_bytes(comp)
    print(f"{u['title']}: {n} ramek, {len(comp)} B -> {CEL}  (CRK_MFR = {n}, maska stalych strumieni {comp[0]:#07b})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
