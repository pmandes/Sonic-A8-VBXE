#!/usr/bin/env python3
"""Test obrazów nośnika (M7.1): każdy plik obrazu z build/pakiety (tools/pack_zone.py) rozpakowany i porównany bajt w bajt z obrazem
banku (albo kodu w RAM głównej) odtworzonym z build/sonic-a8-vbxe.xex jak loader XEX-a - 0 różnic = nośnik niesie dokładnie to, co XEX 1088K.

Dekompresja trzema sposobami:
  - emulacja kodu 6502 dekompresora zx02-optim.asm (dmsc v3, 132 B; ten sam co src/ldr/zx02.asm z M7.2) na 64 KB pamięci, rozkaz po
    rozkazie (rejestry A/X/C, rezerwuar bitów, wskaźnik pntr liczony jak `sbc offset_hi` + `(pntr),y`):
      a) strumień osobno ($A000 - jak okno cartu albo bufor; dla kodu $8000+ - $0400), wynik od adresu celu;
      b) **w miejscu**: strumień kończy się `delta` B ZA końcem wyniku (start = cel + len_u + delta - len_c) - ładowanie wprost do okna
         banku (ATR: LOAD_DATA, cart: kopia z okna cartu) bez bufora 8 KB; pełny bank wychodzi delta B w $8000+ (LDR_SPILL, M7.2);
  - dekoder wg semantyki dzx02.c (C, referencja formatu).
Sprawdzane też: nagłówek 4 B (len_u, delta, flagi) i zgodność z katalogiem (build/pakiety/katalog.json).

Użycie:  python tools/pack_test.py [--xex build/sonic-a8-vbxe.xex] [--procesy n]   (kod 0 = wszystkie zgodne)
"""
from __future__ import annotations

import argparse
import json
import struct
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import pack_zone as pz  # noqa: E402

BUILD = ROOT / "build"


class Zx02_6502:
    """Emulacja zx02-optim.asm (v3) na pamięci 64 KB. ZP: offset_hi, ZX0_src (2), ZX0_dst (2), bitr, pntr (2) - wartości startowe
    jak zx0_ini_block: offset_hi = 0, bitr = $80, pntr = $FF (offset początkowy 1)."""

    def __init__(self, mem: bytearray, src: int, dst: int, limit: int = 0x10000):
        self.m = mem
        self.src = src
        self.dst = dst
        self.koniec = dst + limit        # straż: zły strumień nie kończy się markerem - przerwanie zamiast pętli bez końca
        self.offset_hi = 0
        self.bitr = 0x80
        self.pntr = 0xFF                 # mlodszy bajt; starszy liczony przy kopiowaniu (sta pntr+1)
        self.c = 0
        self.x = 0

    def _asl_bitr(self) -> int:
        self.c = self.bitr >> 7
        self.bitr = (self.bitr << 1) & 0xFF
        return self.bitr

    def _rd_src(self) -> int:            # lda (ZX0_src),y (y = 0); inc ZX0_src
        v = self.m[self.src]
        self.src = (self.src + 1) & 0xFFFF
        return v

    def _wr_dst(self, v: int) -> None:   # sta (ZX0_dst),y (y = 0); inc ZX0_dst
        if self.dst >= self.koniec:
            raise ValueError(f"wynik przekracza ${self.koniec:04X} (brak końca strumienia)")
        self.m[self.dst] = v
        self.dst = (self.dst + 1) & 0xFFFF

    def _get_elias(self, a: int) -> int:
        """get_elias z X = a; wynik w X (= A), C = 0."""
        while True:
            if self._asl_bitr() == 0:      # asl bitr; bne elias_skip1
                v = self._rd_src()         # lda (ZX0_src),y; rol @; sta bitr
                nc = v >> 7
                self.bitr = ((v << 1) | self.c) & 0xFF
                self.c = nc
            # elias_skip1: txa; bcs elias_get
            if not self.c:
                return a
            self._asl_bitr()               # elias_get: asl bitr; rol @; tax
            a = ((a << 1) | self.c) & 0xFF

    def _copy(self, n: int) -> None:
        """dzx0s_copy: pntr+1 = dst_hi - offset_hi - 1 (C = 0); kopiowanie (pntr),y z y = dst_lo; inc pntr+1 przy przejściu strony dst."""
        hi = ((self.dst >> 8) - self.offset_hi - 1) & 0xFF
        for _ in range(n):
            adr = ((hi << 8) + self.pntr + (self.dst & 0xFF)) & 0xFFFF
            v = self.m[adr]
            lo_przed = self.dst & 0xFF
            self._wr_dst(v)
            if lo_przed == 0xFF:
                hi = (hi + 1) & 0xFF

    def run(self) -> None:
        while True:
            # decode_literal: inx; jsr get_elias
            self.x = self._get_elias((self.x + 1) & 0xFF)
            for _ in range(self.x or 256):
                self._wr_dst(self._rd_src())
            self.x = 0
            self._asl_bitr()                       # asl bitr; bcs dzx0s_new_offset
            if not self.c:
                self.x = self._get_elias(1)        # inx; jsr get_elias (powtorzony offset)
                self._copy(self.x or 256)
                self.x = 0
                self._asl_bitr()                   # asl bitr; bcc decode_literal
                if not self.c:
                    continue
            while True:                            # dzx0s_new_offset
                self.x = self._get_elias(1)
                if self.x == 0:                    # beq exit - koniec strumienia
                    return
                a = (self.x - 1) & 0xFF            # dex; txa; lsr @; sta offset_hi
                self.c = a & 1
                self.offset_hi = a >> 1
                v = self._rd_src()                 # lda (ZX0_src),y; ror @; eor #$ff; sta pntr
                nc = v & 1
                v = (v >> 1) | (self.c << 7)
                self.c = nc
                self.pntr = v ^ 0xFF
                # ldx #1; jsr elias_skip1 (bit w C); inx; bcc dzx0s_copy
                a = 1
                if self.c:
                    self._asl_bitr()
                    a = self._get_elias(((a << 1) | self.c) & 0xFF)
                self.x = (a + 1) & 0xFF
                self._copy(self.x or 256)
                self.x = 0
                self._asl_bitr()
                if not self.c:
                    break


def dzx02_c(src: bytes) -> bytes:
    """Dekoder wg semantyki dzx02.c (zx02 v3: elias zakończony bitem 0, offset początkowy 1, bez -b/-s/-1)."""
    st = {"bitr": 0x80, "extra": 0, "i": 0}
    out = bytearray()

    def byte() -> int:
        v = src[st["i"]]
        st["i"] += 1
        return v

    def bit() -> int:
        if st["extra"]:
            b = st["extra"] & 1
            st["extra"] = 0
            return b
        if st["bitr"] == 0x80:
            c = byte()
            st["bitr"] = ((c << 1) | 1) & 0xFF
            return c >> 7
        b = st["bitr"] >> 7
        st["bitr"] = (st["bitr"] << 1) & 0xFF
        return b

    def elias() -> int:
        r = 1
        for _ in range(9):
            if bit() == 0:
                return r
            r = (r << 1) | bit()
        raise ValueError("zły kod Eliasa")

    offset = 0
    stan = 0
    while True:
        if stan == 0:
            for _ in range(elias()):
                out.append(byte())
            stan = 2 if bit() else 1
            continue
        if stan == 2:
            msb = elias()
            if (msb & 0xFF) == 0:
                return bytes(out)
            o = byte()
            st["extra"] = 2 | (o & 1)
            offset = ((msb - 1) << 7) | (o >> 1)
            n = elias() + 1
        else:
            n = elias()
        if n > 0x100:
            n &= 0xFF
        p = len(out) - offset - 1
        for k in range(n):
            out.append(out[p + k])
        stan = 2 if bit() else 0


def dekompresja_6502(z: bytes, dst: int, raw_len: int, delta: int, w_miejscu: bool) -> bytes:
    mem = bytearray(0x10000)
    if w_miejscu:
        src = dst + raw_len + delta - len(z)               # koniec strumienia = koniec wyniku + delta (warunek zx02)
    else:
        src = 0x0400 if dst <= 0xA000 < dst + raw_len else 0xA000
    mem[src:src + len(z)] = z
    d = Zx02_6502(mem, src, dst, raw_len)
    d.run()
    if d.dst != dst + raw_len:
        raise ValueError(f"długość wyniku {d.dst - dst} zamiast {raw_len}")
    return bytes(mem[dst:dst + raw_len])


_W: dict = {}                                        # dane procesu roboczego (_init): manifest, obrazy z XEX, etykiety


def _init(xex: str) -> None:
    man = json.loads((BUILD / "assets" / "manifest.json").read_text(encoding="utf-8"))
    banki, ram = pz.obrazy_z_xex(Path(xex).read_bytes())
    _W["obr"] = pz.obrazy_nosnika(man, banki, ram, pz.etykiety(Path(xex).with_suffix(".lab")))


def sprawdz_obraz(k: dict) -> list[str]:
    """Plik obrazu z katalogu: nagłówek i trzy dekompresje vs obraz z XEX-a. Wynik: lista błędów."""
    klucz = k["klucz"]
    wzor, cel, plik = _W["obr"][klucz]
    b = (pz.OUT / k["plik"]).read_bytes()
    len_u, delta, flagi = struct.unpack_from("<HBB", b)
    z = b[pz.NAGLOWEK:]
    bl = []
    if plik != k["plik"] or cel != k["cel"] or len_u != len(wzor) or len_u != k["len_u"] or delta != k["delta"] or len(z) != k["len_c"]:
        return [f"{klucz}: nagłówek / katalog"]
    if flagi & 1:
        return [] if z == wzor else [f"{klucz}: dane surowe różne od obrazu"]
    for nazwa, f in (("6502", lambda: dekompresja_6502(z, cel, len_u, delta, False)),
                     ("6502 w miejscu", lambda: dekompresja_6502(z, cel, len_u, delta, True)),
                     ("C", lambda: dzx02_c(z))):
        try:
            wynik = f()
        except (ValueError, IndexError) as e:
            bl.append(f"{klucz}: dekompresja {nazwa}: {e}")
            continue
        if wynik != wzor:
            roz = next((j for j in range(min(len(wynik), len(wzor))) if wynik[j] != wzor[j]), min(len(wynik), len(wzor)))
            bl.append(f"{klucz}: {nazwa} różny od obrazu od ${cel + roz:04X} (dł. {len(wynik)}/{len(wzor)})")
    return bl


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--xex", type=Path, default=BUILD / "sonic-a8-vbxe.xex")
    ap.add_argument("--procesy", type=int, default=0, help="liczba procesów (0 = liczba rdzeni)")
    a = ap.parse_args(argv)
    katalog = json.loads((pz.OUT / "katalog.json").read_text(encoding="utf-8"))
    zad = sorted(katalog, key=lambda k: -k["len_u"])     # najdłuższe najpierw - równe obciążenie procesów
    with ProcessPoolExecutor(a.procesy or None, initializer=_init, initargs=(str(a.xex),)) as ex:
        wyniki = dict(zip((k["plik"] for k in zad), ex.map(sprawdz_obraz, zad)))
    zle = 0
    for k in katalog:
        bl = wyniki[k["plik"]]
        print(f"{k['plik']:10s} {k['klucz']:11s} {k['dlugosc']:6d} B: " + ("OK" if not bl else "BŁĘDY: " + "; ".join(bl)))
        zle += 1 if bl else 0
    print(f"WYNIK: {len(katalog)} obrazów – " + ("0 różnic (6502, 6502 w miejscu, C)" if not zle else f"BŁĘDY w {zle} obrazach"))
    return 1 if zle else 0


if __name__ == "__main__":
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main(sys.argv[1:]))
