#!/usr/bin/env python3
"""M5: muzyka gry - SAP-R (wersja C64, music/) -> LZSS16 -> obraz banku 1088K.

Użycie:
  python tools/pack_music.py [--wariant mono-buzzy] [--out build/assets/music] [--sprawdz]

Kompresor: port do Pythona `tools/lzss.c` z dmsc/lzss-sap (Daniel Serpell, MIT, commit
64d3542163a52899c1f4d3a23185f3f5395b7e92) w trybie `-6`
(przesunięcie 8 bitów, długość 8 bitów, minimalne dopasowanie 1, format 0) i bez normalizacji AUDC (jak
`prepare_music.py`: wartości rejestrów SAP-R zachowane dokładnie). Zgodność z programem w C sprawdzana w repo
deweloperskim (wzorzec Green Hill Zone).
Dekoder kontrolny (`lzss16_dekoduj`) odtwarza logikę music.inc (music_reset_decoder / music_decode_frame).

Obraz banku (`bank_music.bin`, do 16 KiB, adres okna $4000):
  +0      liczba utworów N
  +1      N x 6 B: adres strumienia (2, adres CPU w oknie banku), liczba ramek (2), flagi (1: b0 = pętla), 0
  dalej   strumienie LZSS16
Plik `music_dir.inc` (MADS): MUS_N, MUS_<NR>_FRAMES. Utwory: numery 1-16 jak w HVSC (subtunes.json).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
MUZYKA = ROOT / "music"
BANK_WIN = 0x4000
BANK_SIZE = 0x4000

# -6: 8 bitów przesunięcia, 8 bitów długości, min. dopasowanie 1; format 0 (pierwszy literał, pozycje od max)
BITS_MOFF, BITS_MLEN, MIN_MLEN = 8, 8, 1
MAX_MLEN = MIN_MLEN + (1 << BITS_MLEN) - 1        # 256
MAX_OFF = 1 << BITS_MOFF                          # 256
BITS_LITERAL = 1 + 8
BITS_MATCH = 1 + BITS_MOFF + BITS_MLEN            # 17

# utwory zapętlane (motywy stref, tytuł, etap specjalny, niezniszczalność, boss); reszta to dżingle / napisy
PETLA = {1, 2, 3, 4, 5, 6, 7, 8, 9, 13}


def czytaj_sapr(p: Path) -> bytes:
    b = p.read_bytes()
    i = b.index(b"\r\n\r\n") + 4
    naglowek = b[:i].decode("ascii")
    assert "TYPE R\r\n" in naglowek and "STEREO" not in naglowek, p
    dane = b[i:]
    assert dane and len(dane) % 9 == 0, p
    return dane


class Bity:
    """Zapis bitów i bajtów jak struct bf w lzss.c (bajt bitów rezerwowany przy pierwszym bicie grupy)."""

    def __init__(self) -> None:
        self.buf = bytearray()
        self.bpos = -1
        self.bnum = 0

    def bit(self, b: int) -> None:
        if self.bpos < 0:
            self.bpos = len(self.buf)
            self.bnum = 0
            self.buf.append(0)
        if b:
            self.buf[self.bpos] |= 1 << self.bnum
        self.bnum += 1
        if self.bnum == 8:
            self.bpos = -1
            self.bnum = 0

    def bajt(self, v: int) -> None:
        self.buf.append(v & 0xFF)

    def flush(self) -> None:
        self.bpos = -1
        self.bnum = 0


class Lzop:
    """Optymalny podział strumienia (lzop_backfill): bity od pozycji, najlepsza długość i przesunięcie."""

    def __init__(self, data: np.ndarray):
        self.data = data
        self.size = len(data)
        self.bits = np.zeros(self.size, np.int64)
        self.mlen = np.zeros(self.size, np.int64)
        self.mpos = np.zeros(self.size, np.int64)

    def backfill(self, last_literal: bool) -> None:
        size = self.size
        if not size:
            return
        last_bits = 0
        if last_literal:
            self.mlen[size - 1] = 0
            self.bits[size - 1] = BITS_LITERAL
            last_bits = BITS_LITERAL
            if size == 1:
                return
            size -= 1
        self.mlen[size - 1] = 0
        self.bits[size - 1] = BITS_LITERAL + last_bits
        d = self.data.astype(np.int16)
        offs = np.arange(1, MAX_OFF + 1)                 # przesunięcie = pos - i
        # L[off] = długość wspólnego prefiksu data[pos:] i data[pos-off:] (bez limitu) - liczona od końca:
        # L_pos[off] = data[pos-off] == data[pos] ? 1 + L_{pos+1}[off] : 0
        L = np.zeros(MAX_OFF, np.int64)
        for pos in range(self.size - 1, -1, -1):
            src = pos - offs
            ok = src >= 0
            eq = np.zeros(MAX_OFF, bool)
            eq[ok] = d[src[ok]] == d[pos]
            L = np.where(eq, L + 1, 0)
            if pos > size - 2:
                continue
            mx = min(MAX_MLEN, size - pos)               # match(): mxlen = min(max_mlen, size - pos)
            Lc = np.minimum(L, mx)
            ml = int(Lc.max())
            # pierwsze i (najmniejsze, czyli największe przesunięcie) z największą długością
            mp = int(offs[np.nonzero(Lc == ml)[0][-1]]) if ml > 0 else 0
            best = int(self.bits[pos + 1]) + BITS_LITERAL
            self.bits[pos] = best
            self.mlen[pos] = 0
            self.mpos[pos] = mp
            if ml >= MIN_MLEN:
                ls = np.arange(ml, MIN_MLEN - 1, -1)          # kolejność jak pętla w C: od ml w dół
                b = np.empty(len(ls), np.int64)
                wew = pos + ls < size
                b[wew] = self.bits[pos + ls[wew]] + BITS_MATCH
                b[~wew] = BITS_MATCH + last_bits              # pos + l == size (dłuższych nie ma: mx)
                # pierwsza wartość ściśle mniejsza od bieżącego najlepszego w tej kolejności = minimum,
                # przy remisie pierwsza (największa długość)
                k = int(np.argmin(b))
                if b[k] < best:
                    self.bits[pos] = int(b[k])
                    self.mlen[pos] = int(ls[k])
                    self.mpos[pos] = mp
        # rozmiar przywrócony (last_literal) - self.size nie był zmieniany

    def last_is_match(self) -> bool:
        last = False
        pos = 1
        while pos < self.size:
            m = int(self.mlen[pos])
            if m < MIN_MLEN:
                last = False
                pos += 1
            else:
                pos += m
                last = True
        return last


def lzss16_kompresuj(raw: bytes, normalizuj: bool = False) -> bytes:
    """Kompresja ramek SAP-R (9 B na ramkę) - wynik zgodny z `lzss -6` (format 0)."""
    sz = len(raw) // 9
    fr = np.frombuffer(raw, np.uint8).reshape(sz, 9).copy()
    if normalizuj:                                       # domyślna normalizacja AUDC programu w C
        for i in range(1, 9, 2):
            c = fr[:, i].astype(np.int32)
            vol, dist = c & 0x0F, c & 0xF0
            c = np.where(vol == 0, 0, np.where(dist & 0x10, c & 0x1F, np.where(dist & 0x20, c & 0xBF, c)))
            fr[:, i] = c
    data = [fr[:, i] for i in range(9)]
    b = Bity()
    skip = [False] * 9
    for i in range(8, -1, -1):
        stala = bool(np.all(data[i] == data[i][0]))
        if i != 0 and stala:
            b.bit(1)
            skip[i] = True
        elif i:
            b.bit(0)
    b.flush()
    for i in range(8, -1, -1):
        b.bajt(int(data[i][0]))                          # format 0: wartości początkowe wszystkich strumieni
    b.flush()
    lz: list[Lzop | None] = [None] * 9
    for i in range(9):
        if not skip[i]:
            lz[i] = Lzop(data[i])
            lz[i].backfill(False)
    zle = all(lz[i].last_is_match() for i in range(9) if not skip[i])
    if zle:                                              # wszystkie kończą się dopasowaniem: strumień 0 literałem
        lz[0].backfill(True)
        assert not lz[0].last_is_match()
    lpos = [-1] * 9
    for pos in range(1, sz):
        for i in range(8, -1, -1):
            if skip[i]:
                continue
            z = lz[i]
            if pos <= lpos[i]:
                continue
            ml = int(z.mlen[pos])
            if ml < MIN_MLEN:
                b.bit(1)
                b.bajt(int(z.data[pos]))
                lpos[i] = pos
            else:
                code_pos = (pos - int(z.mpos[pos]) - 2) & (MAX_OFF - 1)
                code_len = ml - MIN_MLEN
                b.bit(0)
                mb = ((code_len + 1) << BITS_MOFF) + code_pos
                b.bajt(mb & 0xFF)
                b.bajt(mb >> 8)
                lpos[i] = pos + ml - 1
    b.flush()
    return bytes(b.buf)


def lzss16_dekoduj(comp: bytes, n: int) -> bytes:
    """Dekoder kontrolny - jak music_reset_decoder / music_decode_frame (music.inc); n ramek."""
    p = 0

    def bajt() -> int:
        nonlocal p
        v = comp[p]
        p += 1
        return v

    kanaly = bajt()
    buf = [[0] * 256 for _ in range(9)]
    copy = [0] * 9
    posn = [0] * 9
    rej = [0] * 9
    for x in range(8, -1, -1):
        rej[x] = bajt()
        buf[x][255] = rej[x]
    bit_data = 1
    kursor = 0
    out = bytearray(bytes(rej))
    for _ in range(n - 1):
        bity = kanaly
        for x in range(8, -1, -1):
            skip = bity & 1
            bity >>= 1
            if skip:
                continue
            if copy[x] == 0:
                c = bit_data & 1
                bit_data >>= 1
                if bit_data == 0:
                    v = bajt()
                    c = v & 1
                    bit_data = (v >> 1) | 0x80
                v = bajt()
                if c:
                    wart = v
                else:
                    posn[x] = v
                    copy[x] = bajt()
                    copy[x] = (copy[x] - 1) & 0xFF
                    posn[x] = (posn[x] + 1) & 0xFF
                    wart = buf[x][posn[x]]
            else:
                copy[x] = (copy[x] - 1) & 0xFF
                posn[x] = (posn[x] + 1) & 0xFF
                wart = buf[x][posn[x]]
            rej[x] = wart
            buf[x][kursor] = wart
        kursor = (kursor + 1) & 0xFF
        out += bytes(rej)
    return bytes(out)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="M5: SAP-R -> LZSS16 -> bank muzyki")
    ap.add_argument("--wariant", default="mono-buzzy", help="nazwa wariantu SAP-R (music/: mono-buzzy)")
    ap.add_argument("--out", default=str(ROOT / "build" / "assets" / "music"))
    ap.add_argument("--sprawdz", action="store_true", help="dekoder kontrolny dla wszystkich utworów")
    a = ap.parse_args(argv)


    utwory = json.loads((MUZYKA / "subtunes.json").read_text(encoding="utf-8"))
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    # pamiec podreczna: te same wejscia (SAP-R wariantu, ten skrypt) -> bank aktualny, bez kompresji
    h = hashlib.sha256(Path(__file__).read_bytes())
    for u in utwory:
        h.update((MUZYKA / f"{u['stem']}.sapr").read_bytes())
    zrodla = h.hexdigest()
    info_p = out / "music-info.json"
    if not a.sprawdz and (out / "bank_music.bin").is_file() and (out / "music_dir.inc").is_file()             and info_p.is_file() and json.loads(info_p.read_text(encoding="utf-8")).get("zrodla") == zrodla:
        print(f"bank muzyki aktualny: {out / 'bank_music.bin'}")
        return 0
    naglowek = 1 + 6 * len(utwory)
    bank = bytearray(naglowek)
    bank[0] = len(utwory)
    inc = [f"; music_dir.inc - generowany przez tools/pack_music.py ({a.wariant}); nie edytowac",
           f"MUS_N = {len(utwory)}"]
    raport = []
    for k, u in enumerate(utwory):
        nr = u["subtune"]
        sapr = MUZYKA / f"{u['stem']}.sapr"
        raw = czytaj_sapr(sapr)
        n = len(raw) // 9
        assert n == u["frames"], (sapr, n)
        fr = np.frombuffer(raw, np.uint8).reshape(n, 9)
        for r, nazwa in ((4, "AUDF3"), (5, "AUDC3"), (8, "AUDCTL")):
            if not np.all(fr[:, r] == fr[0, r]):           # kanal 3 i AUDCTL - efekty (sound/music.asm)
                print(f"BŁĄD: {sapr.name}: {nazwa} zmienia się w utworze - kanał 3 nie jest wolny", file=sys.stderr)
                return 1
        comp = lzss16_kompresuj(raw)
        if a.sprawdz:
            dek = lzss16_dekoduj(comp, n)
            if dek != raw:
                r = next(i for i in range(len(raw)) if dek[i] != raw[i])
                print(f"BŁĄD: {sapr.name}: dekoder różny od SAP-R od bajtu {r} (ramka {r // 9})", file=sys.stderr)
                return 1
        adr = BANK_WIN + len(bank)
        e = 1 + 6 * k
        bank[e:e + 6] = bytes([adr & 0xFF, adr >> 8, n & 0xFF, n >> 8, 1 if nr in PETLA else 0, 0])
        bank += comp
        inc.append(f"MUS_{nr:02d}_FRAMES = {n:5d}  ; {u['title']}")
        raport.append((nr, u["title"], n, len(raw), len(comp)))
        print(f"{nr:2d} {u['title']:<24} ramek {n:5d}  {len(raw):6d} B -> {len(comp):5d} B"
              + ("  (dekoder OK)" if a.sprawdz else ""))
    if len(bank) > BANK_SIZE:
        print(f"BŁĄD: bank muzyki {len(bank)} B > 16 KiB", file=sys.stderr)
        return 1
    bank += bytes(BANK_SIZE - len(bank))
    (out / "bank_music.bin").write_bytes(bank)
    (out / "music_dir.inc").write_text("\n".join(inc) + "\n", encoding="ascii")
    zajete = naglowek + sum(r[4] for r in raport)
    info = {"wariant": a.wariant, "utwory": len(raport), "bajty_strumieni": sum(r[4] for r in raport),
            "zajete_w_banku": zajete, "sha256_banku": hashlib.sha256(bank).hexdigest(), "zrodla": zrodla}
    (out / "music-info.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    print(f"bank muzyki: {zajete} B z {BANK_SIZE} -> {out / 'bank_music.bin'}")
    return 0


if __name__ == "__main__":
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main(sys.argv[1:]))
