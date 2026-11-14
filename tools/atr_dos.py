#!/usr/bin/env python3
"""Odczyt obrazów ATR z systemem plików Atari DOS 2.x / DOS 2.5 (ED) / MyDOS (M7.4, tools/pack_atr.py, tools/m7_nosnik_test.py).

Własny parser (bez narzędzi z pakietu AtariSIO) – kontrola obrazów zbudowanych przez `dir2atr` tak, jak czyta je xBIOS: katalog główny
w sektorach 361–368 (8 sektorów × 8 wpisów po 16 B w pierwszych 128 B sektora), plik = łańcuch sektorów od sektora startowego wpisu.

Format ATR: nagłówek 16 B (`$96 $02`, rozmiar w paragrafach 16 B – młodsze 16 b i bajt 6 starsze, rozmiar sektora), potem sektory;
w obrazach DD (256 B) pierwsze 3 sektory (boot) mają po 128 B.
Sektor danych pliku: ostatnie 3 bajty = łącze – bajt n-3: numer pliku (b7-2, DOS 2) | starsze bity następnego sektora (b1-0),
bajt n-2: młodszy bajt następnego sektora, bajt n-1: liczba bajtów danych w sektorze (SD: do 125, DD: do 253). MyDOS dla dużych dysków
(flaga wpisu b2 = 1) nie trzyma numeru pliku – bajt n-3 to cały starszy bajt numeru sektora.
Wpis katalogu (16 B): flaga (b6 = w użyciu – DOS 2.5 na ED: $03 dla plików mogących leżeć w sektorach > 719, b7 = usunięty, b5 = chroniony, b4 = podkatalog MyDOS, b2 = łącza 16-bitowe MyDOS, b1 = DOS 2,
b0 = otwarty do zapisu), liczba sektorów (2), sektor startowy (2), nazwa 8 + rozszerzenie 3 (spacje).
VTOC (sektor 360): bajt 0 kod DOS-u, 1–2 liczba sektorów użytkowych, 3–4 wolne (DOS 2.5 ED: tylko w sektorach 1–719); DOS 2.5 ED: VTOC2
(sektor 1024) bajty 122–123 = wolne sektory 720–1023 (sprawdzone na obrazach dir2atr -E: suma = 1010 − sektory plików).
"""
from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Wpis:
    indeks: int          # numer wpisu w katalogu (0-63) = numer pliku w łączach DOS 2
    flaga: int
    sektory: int         # liczba sektorów z katalogu
    start: int           # sektor startowy
    nazwa: str           # 'NAZWA.ROZ' (bez spacji)
    nazwa11: bytes       # 11 B jak w katalogu (8 + 3, spacje) - tak szuka xBIOS (OPEN_FILE)


class Atr:
    def __init__(self, dane: bytes):
        magic, par, ssize, parhi = struct.unpack_from("<HHHB", dane, 0)
        if magic != 0x0296:
            raise ValueError("to nie jest obraz ATR (brak $0296)")
        self.ssize = ssize
        self.rozmiar = (par | parhi << 16) * 16
        self.d = dane[16:16 + self.rozmiar]
        if len(self.d) != self.rozmiar:
            raise ValueError("obraz ATR krótszy niż nagłówek")
        if ssize == 128:
            self.n = self.rozmiar // 128
        else:
            self.n = 3 + (self.rozmiar - 3 * 128) // ssize
        self.dane_na_sektor = ssize - 3

    @classmethod
    def z_pliku(cls, p: Path) -> "Atr":
        return cls(Path(p).read_bytes())

    def sektor(self, n: int) -> bytes:
        if not 1 <= n <= self.n:
            raise ValueError(f"sektor {n} poza 1..{self.n}")
        if self.ssize == 128 or n <= 3:
            o = (n - 1) * 128
            return self.d[o:o + 128]
        o = 3 * 128 + (n - 4) * self.ssize
        return self.d[o:o + self.ssize]

    def katalog(self, start: int = 361) -> list[Wpis]:
        w = []
        for k in range(8):
            s = self.sektor(start + k)
            for j in range(8):
                e = s[j * 16:(j + 1) * 16]
                fl = e[0]
                if fl == 0:
                    return w                     # koniec katalogu (DOS 2: pierwszy pusty wpis)
                if fl & 0x80 or not fl & 0x43:
                    continue                     # usunięty / nieużywany (DOS 2.5 ED: plik w sektorach > 719 ma flagę $03, nie $42)
                nazwa = e[5:13].decode("latin-1").rstrip() + ("." + e[13:16].decode("latin-1").rstrip() if e[13:16].strip() else "")
                w.append(Wpis(k * 8 + j, fl, e[1] | e[2] << 8, e[3] | e[4] << 8, nazwa, bytes(e[5:16])))
        return w

    def lancuch(self, w: Wpis) -> list[int]:
        """Sektory pliku w kolejności (kontrola numeru pliku w łączach DOS 2)."""
        sek, wynik = w.start, []
        dl16 = bool(w.flaga & 0x04)
        while sek:
            if sek in wynik or len(wynik) > self.n:
                raise ValueError(f"{w.nazwa}: pętla w łańcuchu sektorów")
            wynik.append(sek)
            s = self.sektor(sek)
            b0, b1, ile = s[-3], s[-2], s[-1]
            if dl16:
                nast = b0 << 8 | b1
            else:
                if b0 >> 2 != w.indeks:
                    raise ValueError(f"{w.nazwa}: sektor {sek} ma numer pliku {b0 >> 2}, wpis {w.indeks}")
                nast = (b0 & 3) << 8 | b1
            if ile > self.dane_na_sektor:
                raise ValueError(f"{w.nazwa}: sektor {sek} - liczba bajtów {ile} > {self.dane_na_sektor}")
            sek = nast
        return wynik

    def plik(self, w: Wpis) -> bytes:
        out = bytearray()
        for sek in self.lancuch(w):
            s = self.sektor(sek)
            out += s[:s[-1]]
        return bytes(out)

    def znajdz(self, nazwa: str) -> Wpis | None:
        return next((w for w in self.katalog() if w.nazwa.upper() == nazwa.upper()), None)

    def vtoc(self) -> dict:
        v = self.sektor(360)
        r = {"dos": v[0], "uzytkowe": v[1] | v[2] << 8, "wolne": v[3] | v[4] << 8}
        if self.ssize == 128 and self.n == 1040 and v[0] == 2:      # DOS 2.5 ED: wolne powyżej 719 w VTOC2
            v2 = self.sektor(1024)
            r["wolne_ed"] = v2[122] | v2[123] << 8          # wolne powyżej 719 (VTOC: bajty 3-4 - tylko sektory 1-719)
            r["wolne"] += r["wolne_ed"]
        return r

    def opis(self) -> str:
        g = {128: "SD", 256: "DD"}.get(self.ssize, f"{self.ssize} B")
        return f"{self.n} sektorów × {self.ssize} B ({g}), {self.rozmiar} B danych"


def nazwa11(nazwa: str) -> bytes:
    """'B01.ZX2' -> b'B01     ZX2' (format nazwy OPEN_FILE xBIOS-a)."""
    n, _, r = nazwa.upper().partition(".")
    return (n.ljust(8) + r.ljust(3)).encode("ascii")


if __name__ == "__main__":
    import sys
    for p in sys.argv[1:]:
        a = Atr.z_pliku(Path(p))
        print(p, a.opis(), a.vtoc())
        for w in a.katalog():
            sek = a.lancuch(w)
            print(f"  {w.indeks:2d} {w.nazwa:12s} flaga ${w.flaga:02X} sektorów {w.sektory:4d} (łańcuch {len(sek)}) start {w.start:4d} "
                  f"koniec {sek[-1] if sek else 0:4d} max {max(sek) if sek else 0:4d} bajtów {len(a.plik(w))}")
