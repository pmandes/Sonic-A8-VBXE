#!/usr/bin/env python3
"""Listing MADS (build/game.lst) jako dane (M4.9a): wiersze z adresem i bajtami, obszary kodu, które dzielą adresy
$4000-$7FFF (kod obiektów w banku 45 między znacznikami `;@BANK45` i `;@BANK45_END`, kod gry pod $4100 między
etykietami `code_lo_start` i `code_lo_end`), początki rozkazów - także w wierszach pseudo-rozkazów MADS (`mwa`,
`jne`, `jcs`...: kilka rozkazów w jednym wierszu, bajty obcięte znakiem `+` po szóstym), etykiety zdefiniowane
w obszarze (nazwa w kolumnie 32 listingu po rozwinięciu tabulatorów) i cele skoków. Wspólne dla tools/m38_profil.py
(tracepointy poza kolizjami adresów), tools/sprawdz_xex.py (skoki z banku 45) i tools/m3_unit.py (profil wg etykiet).

Użycie jako skrypt: python tools/lst6502.py [build/game.lst] - podsumowanie obszarów i etykiety leżące na początkach
rozkazów drugiego obszaru (kandydaci na kolizje tracepointów).
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LST = ROOT / "build" / "game.lst"

# wiersz listingu MADS: numer, adres (pierwszy w segmencie z "-koniec>"), bajty, źródło
RX_LST = re.compile(r"^\s*\d+\s+([0-9A-F]{4})(?:-[0-9A-F]{4}>)?\s+((?:[0-9A-F]{2}[ \t])+)\s*(.*)$")
RX_ETYK = re.compile(r"^\s*\d+\s+([0-9A-F]{4})(?:-[0-9A-F]{4}>)?")
KOL_ZRODLA = 32                          # kolumna źródła po rozwinięciu tabulatorów (etykieta zaczyna się tutaj)
# wiersz danych (bajty nie są rozkazami: tablice dta, ins, .by...; z opcjonalną etykietą i powtórzeniem :N)
RX_DANE = re.compile(r"^(?:[A-Za-z_?@][\w?@]*\s+)?(?::\w+\s+)?(?:dta|ins|\.by|\.he|\.sb|\.cb|\.wo|\.fl|\.dc)\b", re.I)
OBSZARY = ("b45", "lo")
# M7.2/M7.3: znacznik obszaru ldr - na POCZĄTKU źródła wiersza bez bajtów (po numerze wiersza), dalej może być komentarz (review M7.2:
# wcześniej tylko jako ostatnie słowo wiersza - ";@LDR - opis" był pomijany); opisy znaczników w komentarzach (";  ... ;@LDR ...") nie
# zaczynają się od niego, więc nie przełączają obszaru
RX_LDR = re.compile(r"^\s*\d+\s+;@LDR(_END)?\b")

# długości rozkazów 6502 (oficjalne; nielegalne traktowane wg wzorca bitów)
_DL1 = {0x00, 0x08, 0x18, 0x28, 0x38, 0x40, 0x48, 0x58, 0x60, 0x68, 0x78, 0x88, 0x8A, 0x98, 0x9A, 0xA8, 0xAA,
        0xB8, 0xBA, 0xC8, 0xCA, 0xD8, 0xE8, 0xEA, 0xF8, 0x0A, 0x2A, 0x4A, 0x6A}
OPK_GALEZIE = {0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0}
OPK_JMP = 0x4C
OPK_JMP_IND = 0x6C
OPK_JSR = 0x20
MNEMONIKI_SKOKOW = {"bpl", "bmi", "bvc", "bvs", "bcc", "bcs", "bne", "beq", "jmp", "jsr",
                    "jne", "jeq", "jcc", "jcs", "jpl", "jmi", "jvc", "jvs"}


def dl_rozkazu(op: int) -> int:
    if op == OPK_JSR:
        return 3
    if op in _DL1:
        return 1
    if (op & 0x0F) in (0x0C, 0x0D, 0x0E) or (op & 0x1F) == 0x19:
        return 3
    return 2


@dataclass
class Wiersz:
    nr: int                      # numer wiersza pliku listingu (od 1)
    adr: int
    bajty: list[int]             # bajty pokazane w listingu (do 6)
    obciety: bool                # '+' - dalsze bajty rozkazów nie są pokazane
    zrodlo: str                  # tekst źródła (bez wiodących tabulatorów)
    obszar: str | None           # "b45", "bz", "bz2", "bz3", "lo", "ldr" (M7.2) albo None
    etykieta: str | None         # etykieta zdefiniowana w tym wierszu (wielkimi literami)


def wczytaj(lst: Path = LST) -> list[Wiersz]:
    """Wiersze listingu z adresem (z bajtami albo sama etykieta) i przypisanym obszarem."""
    out: list[Wiersz] = []
    obszar: str | None = None
    for nr, linia in enumerate(lst.read_text(encoding="ascii", errors="replace").splitlines(), 1):
        # M7.2: znaczniki ;@LDR / ;@LDR_END - kod ldr dzialajacy przy wlaczonym zrodle (cart - M7.3; RAMCART: banki zrodla w oknie);
        # tylko jako ostatnie slowo wiersza (opisy znacznikow w komentarzach nie przelaczaja obszaru)
        m_ldr = RX_LDR.search(linia)
        if ";@BANK45_END" in linia or ";@BANKZ_END" in linia or ";@BANKZ2_END" in linia or ";@BANKZ3_END" in linia \
                or (m_ldr and m_ldr[1]):
            obszar = None
            continue
        if m_ldr:
            obszar = "ldr"
            continue
        if ";@BANKZ2" in linia:                      # M6.9: drugi bank obiektow strefy (PB_OBJZ2, bank 2)
            obszar = "bz2"
            continue
        if ";@BANKZ3" in linia:                      # M6.10: trzeci bank obiektow strefy (PB_OBJZ3, bank 30 - Sky Base)
            obszar = "bz3"
            continue
        if ";@BANKZ" in linia:                       # M6.6: bank obiektow strefy (PB_OBJZ)
            obszar = "bz"
            continue
        if ";@BANK45" in linia:
            obszar = "b45"
            continue
        roz = linia.expandtabs(8)
        etyk = None
        if len(roz) > KOL_ZRODLA and (roz[KOL_ZRODLA].isalpha() or roz[KOL_ZRODLA] in "_?@") \
                and roz[KOL_ZRODLA - 1] == " " and RX_ETYK.match(linia):
            m = re.match(r"[A-Za-z_?@][\w?@]*", roz[KOL_ZRODLA:])
            if m:
                etyk = m.group().upper()
        if etyk == "CODE_LO_START":
            obszar = "lo"
        m = RX_LST.match(linia)
        if m:
            zr = m[3]
            obc = zr.lstrip().startswith("+")
            if obc:
                zr = zr.lstrip()[1:]
            out.append(Wiersz(nr, int(m[1], 16), [int(b, 16) for b in m[2].split()], obc, zr.strip(), obszar, etyk))
        elif etyk is not None:
            me = RX_ETYK.match(linia)
            out.append(Wiersz(nr, int(me[1], 16), [], False, "", obszar, etyk))
        if etyk == "CODE_LO_END":
            obszar = None
    if not any(w.obszar == "b45" for w in out) or not any(w.obszar == "lo" for w in out):
        sys.exit(f"BŁĄD: {lst}: brak obszaru ;@BANK45 albo code_lo_start w listingu")
    return out


def rozkazy(wiersze: list[Wiersz], obszar: str) -> list[tuple[int, int | None, str, list[int]]]:
    """(adres, opcode | None gdy bajt niepokazany, źródło, bajty rozkazu) - wszystkie początki rozkazów obszaru
    w kolejności listingu (bez wierszy danych: dta, ins... - ich bajtów CPU nie wykonuje). Wiersz obcięty ('+'):
    adresy od końca pokazanych bajtów do adresu następnego wiersza z bajtami liczone zachowawczo jako możliwe
    początki (opcode None, bajty puste)."""
    out: list[tuple[int, int | None, str, list[int]]] = []
    z_bajtami = [w for w in wiersze if w.obszar == obszar and w.bajty and not RX_DANE.match(w.zrodlo)]
    for j, w in enumerate(z_bajtami):
        p = 0
        while p < len(w.bajty):
            dl = dl_rozkazu(w.bajty[p])
            out.append((w.adr + p, w.bajty[p], w.zrodlo, w.bajty[p:p + dl]))
            p += dl
        if w.obciety:
            nast = z_bajtami[j + 1].adr if j + 1 < len(z_bajtami) else w.adr + p
            if w.adr + p < nast <= w.adr + 24:
                out.extend((a, None, w.zrodlo, []) for a in range(w.adr + p, nast))
    return out


def poczatki(wiersze: list[Wiersz], obszar: str) -> set[int]:
    return {a for a, _, _, _ in rozkazy(wiersze, obszar)}


def etykiety(wiersze: list[Wiersz], obszar: str) -> set[str]:
    """Nazwy etykiet (wielkimi literami) zdefiniowanych w obszarze."""
    return {w.etykieta for w in wiersze if w.obszar == obszar and w.etykieta}


def cel(adr: int, bajty: list[int]) -> int | None:
    """Cel rozkazu skoku pod adresem adr (gałąź względna, jmp abs, jsr); None dla innych."""
    if not bajty:
        return None
    op = bajty[0]
    if op in OPK_GALEZIE and len(bajty) >= 2:
        off = bajty[1] - 256 if bajty[1] >= 128 else bajty[1]
        return (adr + 2 + off) & 0xFFFF
    if op in (OPK_JMP, OPK_JSR) and len(bajty) >= 3:
        return bajty[1] | bajty[2] << 8
    return None


def skoki(wiersze: list[Wiersz], obszar: str) -> list[tuple[int, int, int]]:
    """(adres rozkazu, opcode, cel) dla gałęzi, jmp i jsr w wierszach obszaru, których źródło zaczyna się
    mnemonikiem skoku (także pseudo-rozkazy jne/jcs...: rozkazy dekodowane z bajtów wiersza)."""
    out: list[tuple[int, int, int]] = []
    for w in wiersze:
        if w.obszar != obszar or not w.bajty:
            continue
        mnem = w.zrodlo.split()[0].lower() if w.zrodlo else ""
        if mnem not in MNEMONIKI_SKOKOW:
            continue
        p = 0
        while p < len(w.bajty):
            op = w.bajty[p]
            c = cel(w.adr + p, w.bajty[p:p + dl_rozkazu(op)])
            if c is not None:
                out.append((w.adr + p, op, c))
            p += dl_rozkazu(op)
    return out


def cele_skokow(wiersze: list[Wiersz], obszar: str) -> set[int]:
    return {c for _, _, c in skoki(wiersze, obszar)}


def main(argv: list[str]) -> int:
    w = wczytaj(Path(argv[0]) if argv else LST)
    for o in OBSZARY:
        r = rozkazy(w, o)
        print(f"obszar {o}: {len(r)} rozkazów ${min(a for a, *_ in r):04X}-${max(a for a, *_ in r):04X}, "
              f"etykiet {len(etykiety(w, o))}, skoków {len(skoki(w, o))}")
    for o, inny in (("b45", "lo"), ("lo", "b45")):
        obce = poczatki(w, inny)
        kol = sorted((x.adr, x.etykieta) for x in w if x.obszar == o and x.etykieta and x.adr in obce)
        print(f"etykiety obszaru {o} na początkach rozkazów obszaru {inny}: {len(kol)}")
        for a, n in kol:
            print(f"  ${a:04X} {n}")
    return 0


if __name__ == "__main__":
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main(sys.argv[1:]))
