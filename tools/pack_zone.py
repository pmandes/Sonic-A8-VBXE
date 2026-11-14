#!/usr/bin/env python3
"""Obrazy nośnika (M7.1, docs/plan-m7.md §1.2): obrazy banków z build/sonic-a8-vbxe.xex -> pliki zx02 wg build/assets/manifest.json.

Obrazy banków powstają z XEX-a wydania tak jak u loadera (tools/sprawdz_xex.py: stub INI `lda #PB; sta PORTB` pod $0610 wybiera bank,
segmenty w oknie $4000-$7FFF trafiają do niego) - plik niesie więc dokładnie to, co XEX 1088K trzyma w banku, razem z kodem
obiektów w lukach danych (banki 11, 2, 30, 45) i kodem ekranów (bank 49). Zakres obrazu: od strony pierwszego do ostatniego bajtu
zapisanego przez XEX (luki - zera; gra ich nie czyta). Kod gry (RAM główna: rezydentny $8000+ i pod oknem $4100+) - dwa obrazy kodu.

Jednostką nośnika jest **obraz banku** (docs/plan-m7-ldr.md §4.1): ldr_need porównuje obrazy w slotach z potrzebami poziomu
(manifest: potrzeby), „pakiety” strefa/akt z manifestu to tylko grupy do raportu i podziału na dyskietki. Ten sam plik obrazu idzie
na cart (AtariMax / SIC!: strumień w obrazie cartu, katalog w banku boot - M7.3) i na ATR (plik Bnn.ZX2 - M7.4).

Format pliku obrazu (little endian):
  +0 długość rozpakowana len_u (16 b)  +2 delta zx02 (8 b)  +3 flagi (bit 0 = dane surowe, bez kompresji)  +4 strumień zx02
  (zx02 v3 dmsc, opcje domyślne - offset początkowy 1, jak src/ldr/zx02.asm z M7.2) albo dane surowe.
Dekompresja **w miejscu** (bez bufora): strumień ładowany tak, żeby kończył się `delta` B ZA końcem wyniku - start = cel + len_u +
delta - len_c; wynik od celu (tools/pack_test.py sprawdza to emulacją 6502). Pełny bank 16 KB wychodzi więc delta B (<= LDR_SPILL)
poza okno, w $8000+ - obszar roboczy LDR_SPILL kodu rezydentnego (M7.2); bramka: wyjście poza okno <= LDR_SPILL.

Wyjście: build/pakiety/Bnn.ZX2 (nn = bank w XEX 1088K), KOD80.ZX2 / KOD41.ZX2 (kod rezydentny / pod oknem), CRK.ZX2 (cracktro -
tylko pomiar), build/pakiety/katalog.json, build/pakiety/raport.md (rozmiary, współczynniki wg rodzaju danych, zajętość cartu
AtariMax / SIC!, ATR i dyskietek ED). Cache kompresji: build/pakiety/cache (klucz SHA-256 danych i zx02.exe).
Plik KOD80.ZX2 obejmuje dziś cały kod rezydentny od $8000 - w M7.4 podział etykietą za ldr (dekompresja w miejscu nie może nadpisać ldr).

M7.2 - RAMCART (--ramcart XEX): źródło testowe ldr w Altirze (MEDIA_RAM, build/sonic-ram.xex) - obrazy doczytywane przez ldr (manifest:
ldr.ladowane - sloty, bez obrazów stałych i banku 36) w formacie pliku jak wyżej, ciągiem jak na carcie SIC! (16 KB/bank) w wolnych bankach
1088K RC_BANKI (38, 40, ..., 62, 0; = rc_pb w src/ldr/ldr.asm), katalog na początku pierwszego banku (5 tablic po 64 B indeksowanych id
obrazu: indeks banku RAMCART, adres pliku lo / hi w oknie, długość pliku lo / hi). Obrazy z XEX-a pierwszego przebiegu sonic-ram
(build/sonic-ram-src.xex, LD_ZONY = 1 - banki stref i obiektów jak XEX 1088K): kod obiektów w bankach 11 / 2 / 30 odwołuje się do kodu
rezydentnego TEGO buildu (inny niż w sonic-a8-vbxe.xex: bez trace'u, z ldr). Wyjście: build/pakiety/ramcart/RCnn.BIN (dane banku nn),
build/pakiety/ramcart.inc (segmenty XEX: stub INI -> PORTB, ins - src/game.asm przy LD_ZONY = 0), build/pakiety/ramcart.json (katalog).

Użycie:  python tools/pack_zone.py [--xex build/sonic-a8-vbxe.xex]   (po tools/build.cmd sonic; kod 0 = zapisane)
         python tools/pack_zone.py --ramcart build/sonic-ram-src.xex   (tools/build.cmd sonic-ram)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import sprawdz_xex as sx  # noqa: E402

BUILD = ROOT / "build"
OUT = BUILD / "pakiety"
CACHE = OUT / "cache"
ZX02 = ROOT / "tools" / "bin" / "zx02.exe"
NAGLOWEK = 4                           # len_u, delta, flagi
LDR_SPILL = 16                         # B za oknem $7FFF (w $8000+) na koniec strumienia przy dekompresji w miejscu pełnego banku

# nośniki (docs/m7-nosniki.md §5-6, plan-m7-ldr.md §3.1): AtariMax 1 MB = 128 banków po 8 KB, SIC! 512 KB = 32 po 16 KB;
# ED w DOS 2.5 = 1010 wolnych sektorów po 125 B danych (3 B łącza), DD (256 B) w DOS 2 / MyDOS - 253 B danych na sektor
CART_BANK = 8192
CART_BANKI = 128
SIC_BANK = 16384
SIC_BANKI = 32
ED_SEKTORY = 1010
ED_DANE = 125
DD_DANE = 253

# M7.2 RAMCART (src/kernel/mem.inc RC_*, src/ldr/ldr.asm rc_pb / ldr_fetch_ram)
RC_BANKI = [38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 0]   # kolejność danych - ta sama lista co rc_pb (bez 34 - skrypt testów, 36 - ekrany)
RC_NID = 64                                                          # długość każdej z 5 tablic katalogu (id obrazu 1..63)
RC_KAT = 5 * RC_NID                                                  # katalog na początku pierwszego banku ($4000)
LDR_BUF_N = 0x2000                                                   # bufor kopii ldr_fetch_ram ($2000-$3FFF): maks. długość pliku
RAMCART = OUT / "ramcart"


def pb_banku(n: int, os_on: bool = False) -> int:
    """PORTB banku 1088K n (jak select_bank: bity 1-3 = n & 7, bity 5-7 = n >> 3, bit 4 = 0); os_on - bit 0 = 1 (ładowanie XEX-a)."""
    return ((n & 7) << 1) | ((n >> 3) << 5) | (1 if os_on else 0)


def obrazy_z_xex(xex: bytes) -> tuple[dict[int, tuple[bytearray, bytearray]], tuple[bytearray, bytearray]]:
    """Banki 1088K i RAM główna po załadowaniu XEX-a: bank -> (dane 16 KB, maska zapisanych bajtów); RAM główna (64 KB, maska)."""
    banki: dict[int, tuple[bytearray, bytearray]] = {}
    ram = (bytearray(0x10000), bytearray(0x10000))
    portb = 0xFF
    for a, dane in sx.segmenty(xex):
        bank = sx.bank_portb(portb)
        for i, v in enumerate(dane):
            adr = a + i
            if bank is not None and 0x4000 <= adr < 0x8000:
                d, m = banki.setdefault(bank, (bytearray(0x4000), bytearray(0x4000)))
                d[adr - 0x4000] = v
                m[adr - 0x4000] = 1
            else:
                ram[0][adr] = v
                ram[1][adr] = 1
        if a == 0x02E2 and len(dane) >= 2:                     # INI: stub ustawiający PORTB (jak sprawdz_xex.banki_z_xex)
            ini, = struct.unpack_from("<H", dane)
            kod = ram[0][ini:ini + 6]
            if kod[0] == 0xA9 and kod[2] == 0x8D and kod[3:5] == bytes((sx.PORTB & 0xFF, sx.PORTB >> 8)):
                portb = kod[1]
            elif kod[0] == 0xAD and kod[3] == 0x8D:
                portb = 0xFF
    return banki, ram


def zakres(maska: bytearray) -> tuple[int, int]:
    """Zakres obrazu: od strony pierwszego zapisanego bajtu do ostatniego zapisanego (włącznie)."""
    idx = [i for i, v in enumerate(maska) if v]
    return idx[0] & ~0xFF, idx[-1] + 1


def etykiety(lab: Path) -> dict[str, int]:
    w = {}
    for linia in lab.read_text(encoding="utf-8", errors="replace").splitlines():
        p = linia.split()
        if len(p) >= 3 and re.fullmatch(r"[0-9A-Fa-f]{4}", p[1]):
            w[p[2].upper()] = int(p[1], 16)
    return w


def obrazy_nosnika(man: dict, banki: dict, ram: tuple, lab: dict) -> dict[str, tuple[bytes, int, str]]:
    """klucz -> (dane, adres celu, plik): obrazy banków manifestu, kod gry (2 obrazy RAM głównej), cracktro (pomiar)."""
    w: dict[str, tuple[bytes, int, str]] = {}
    for n, o in man["obrazy"].items():
        d, m = banki[o["bank"]]
        lo, hi = zakres(m)
        w[n] = (bytes(d[lo:hi]), 0x4000 + lo, f"B{o['bank']:02d}.ZX2")
    w["kod_hi"] = (bytes(ram[0][0x8000:lab["CODE_HI_END"]]), 0x8000, "KOD80.ZX2")
    w["kod_lo"] = (bytes(ram[0][lab["CODE_LO_START"]:lab["CODE_LO_END"]]), lab["CODE_LO_START"], "KOD41.ZX2")
    crk = [i for i in range(0x2000, 0x4000) if ram[1][i]]
    if crk:
        w["cracktro"] = (bytes(ram[0][0x2000:crk[-1] + 1]), 0x2000, "CRK.ZX2")
    return w


_ZX02_ID = hashlib.sha256(ZX02.read_bytes()).hexdigest()[:16] if ZX02.is_file() else "brak"   # cache nieważny po wymianie kompresora


def zx02(dane: bytes) -> tuple[bytes, int]:
    """Kompresja zx02 (cache wg SHA-256 danych i pliku zx02.exe); zwraca (strumień, delta dekompresji w miejscu)."""
    h = hashlib.sha256(dane + _ZX02_ID.encode()).hexdigest()
    plik = CACHE / f"{h}.zx2"
    meta = CACHE / f"{h}.delta"
    if plik.is_file() and meta.is_file():
        return plik.read_bytes(), int(meta.read_text())
    src = CACHE / f"{h}.bin"
    src.write_bytes(dane)
    r = subprocess.run([str(ZX02), "-f", str(src), str(plik)], capture_output=True, text=True)
    src.unlink()
    m = re.search(r"delta (\d+)", r.stdout + r.stderr)
    if r.returncode or not plik.is_file() or not m:
        raise RuntimeError(f"zx02: błąd kompresji ({r.returncode}): {r.stdout} {r.stderr}")
    meta.write_text(m.group(1))
    return plik.read_bytes(), int(m.group(1))


def plik_obrazu(dane: bytes, z: bytes, delta: int) -> tuple[bytes, bool]:
    """Plik obrazu: nagłówek 4 B + strumień zx02 albo dane surowe (gdy kompresja nie zmniejsza)."""
    surowe = len(z) >= len(dane)
    return struct.pack("<HBB", len(dane), 0 if surowe else delta, 1 if surowe else 0) + (dane if surowe else z), surowe


def obrazy_ldr(man: dict, banki: dict) -> dict[str, bytes]:
    """Obrazy doczytywane przez ldr (manifest ldr.ladowane) z banków XEX-a: nazwa -> dane od $4000 do ostatniego zapisanego bajtu."""
    w = {}
    for n in man["ldr"]["ladowane"]:
        o = man["obrazy"][n]
        if o["bank"] not in banki:
            raise ValueError(f"XEX nie ładuje obrazu {n} (bank {o['bank']})")
        d, m = banki[o["bank"]]
        lo, hi = zakres(m)
        if lo != 0:
            raise ValueError(f"obraz {n}: początek ${0x4000 + lo:04X} - ldr rozpakowuje zawsze od $4000")
        w[n] = bytes(d[lo:hi])
    return w


def ramcart(src: Path) -> int:
    """M7.2: banki RAMCART z obrazów ldr XEX-a src (pierwszy przebieg sonic-ram) - pliki RCnn.BIN, ramcart.inc, ramcart.json."""
    man = json.loads((BUILD / "assets" / "manifest.json").read_text(encoding="utf-8"))
    banki, _ = obrazy_z_xex(src.read_bytes())
    try:
        obr = obrazy_ldr(man, banki)
    except ValueError as e:
        print("BŁĄD:", e, file=sys.stderr)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    RAMCART.mkdir(parents=True, exist_ok=True)
    jedne = {d: None for d in obr.values()}
    with ThreadPoolExecutor(8) as ex:
        z_danych = dict(zip(jedne, ex.map(zx02, jedne)))
    bledy = []
    pliki: dict[str, tuple[bytes, int, int, bool]] = {}
    for n, dane in obr.items():
        z, delta = z_danych[dane]
        bajty, surowe = plik_obrazu(dane, z, delta)
        poza = 0x4000 + len(dane) + (0 if surowe else delta) - 0x8000
        if poza > LDR_SPILL:
            bledy.append(f"{n}: dekompresja w miejscu wychodzi {poza} B poza $7FFF (LDR_SPILL = {LDR_SPILL})")
        if len(bajty) > LDR_BUF_N:
            bledy.append(f"{n}: plik {len(bajty)} B > bufor ldr_fetch_ram {LDR_BUF_N} B")
        pliki[n] = (bajty, len(dane), 0 if surowe else delta, surowe)
    # układ: katalog, potem pliki w kolejności id (jak na carcie: jeden ciąg danych przez kolejne banki 16 KB)
    flat = bytearray(RC_KAT)
    katalog = []
    for n in sorted(pliki, key=lambda x: man["obrazy"][x]["id"]):
        i = man["obrazy"][n]["id"]
        bajty, len_u, delta, surowe = pliki[n]
        poz = len(flat)
        b, adr = poz // 0x4000, 0x4000 + poz % 0x4000
        flat[i] = b
        flat[RC_NID + i], flat[2 * RC_NID + i] = adr & 0xFF, adr >> 8
        flat[3 * RC_NID + i], flat[4 * RC_NID + i] = len(bajty) & 0xFF, len(bajty) >> 8
        katalog.append({"obraz": n, "id": i, "bank_xex": man["obrazy"][n]["bank"], "rc_indeks": b, "rc_bank": RC_BANKI[b] if b < len(RC_BANKI) else None,
                        "adres": adr, "dlugosc": len(bajty), "len_u": len_u, "len_c": len(bajty) - NAGLOWEK, "delta": delta, "surowe": surowe})
        flat += bajty
    nb = math.ceil(len(flat) / 0x4000)
    if nb > len(RC_BANKI):
        bledy.append(f"RAMCART {len(flat)} B > {len(RC_BANKI)} banków po 16 KB")
    for b in bledy:
        print("BŁĄD:", b, file=sys.stderr)
    if bledy:
        return 1
    for p in RAMCART.glob("RC*.BIN"):
        p.unlink()
    L = ["; build/pakiety/ramcart.inc - generowane przez tools/pack_zone.py --ramcart (M7.2) - nie edytowac recznie",
         f"; RAMCART (MEDIA_RAM, build/sonic-ram.xex): {len(pliki)} obrazow zx02 slotow ({len(flat) - RC_KAT} B) + katalog {RC_KAT} B ciagiem",
         f"; w bankach {', '.join(str(x) for x in RC_BANKI[:nb])} (kolejnosc = rc_pb w src/ldr/ldr.asm); zrodlo obrazow: {src.name}.",
         "; Segment banku: stub INI pod $0610 wybiera bank (OS on), dane w oknie $4000 - jak lvbanks.inc.",
         f"RC_NUSED\t= {nb}",
         "\t.if RC_NUSED>RC_NBANK",
         "\t.error \"RAMCART: wiecej bankow niz w rc_pb (src/ldr/ldr.asm)\"",
         "\t.endif"]
    for k in range(nb):
        bank = RC_BANKI[k]
        (RAMCART / f"RC{bank:02d}.BIN").write_bytes(bytes(flat[k * 0x4000:(k + 1) * 0x4000]))
        L += ["", "\torg $0610", f"ld_rc{bank:02d}", f"\tlda #${pb_banku(bank, True):02X}\t\t; bank {bank}, OS on", "\tsta PORTB", "\trts",
              f"\tini ld_rc{bank:02d}", "\torg BANK_WIN", f"\tins 'ramcart/RC{bank:02d}.BIN'" + ("\t; katalog RC_CAT + obrazy" if k == 0 else "")]
    tekst = "\n".join(L) + "\n"
    p = OUT / "ramcart.inc"
    if not p.is_file() or p.read_text(encoding="ascii") != tekst:
        p.write_text(tekst, encoding="ascii", newline="\n")
    (OUT / "ramcart.json").write_text(json.dumps({"zrodlo": src.name, "banki": RC_BANKI[:nb], "bajty": len(flat), "katalog": katalog},
                                                 ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"RAMCART: {len(pliki)} obrazów, {len(flat)} B (z katalogiem {RC_KAT} B) w {nb}/{len(RC_BANKI)} bankach "
          f"({', '.join(str(x) for x in RC_BANKI[:nb])}); najdłuższy plik {max(len(v[0]) for v in pliki.values())} B "
          f"(bufor {LDR_BUF_N}); max delta {max(v[2] for v in pliki.values())} -> build/pakiety/ramcart.inc")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--xex", type=Path, default=BUILD / "sonic-a8-vbxe.xex")
    ap.add_argument("--ramcart", type=Path, help="M7.2: banki RAMCART z obrazów ldr podanego XEX-a (build/sonic-ram-src.xex)")
    a = ap.parse_args(argv)
    if a.ramcart:
        return ramcart(a.ramcart)
    man = json.loads((BUILD / "assets" / "manifest.json").read_text(encoding="utf-8"))
    banki, ram = obrazy_z_xex(a.xex.read_bytes())
    lab = etykiety(a.xex.with_suffix(".lab"))
    brak = [f"{n} (bank {o['bank']})" for n, o in man["obrazy"].items() if o["bank"] not in banki]
    if brak:
        print("BŁĄD: XEX nie ładuje obrazów manifestu: " + ", ".join(brak), file=sys.stderr)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    obr = obrazy_nosnika(man, banki, ram, lab)
    jedne = {d: None for d, _, _ in obr.values()}          # identyczne obrazy kompresowane raz (wątki nie piszą tego samego pliku cache)
    with ThreadPoolExecutor(8) as ex:
        z_danych = dict(zip(jedne, ex.map(zx02, jedne)))
    wyniki = {k: z_danych[d] for k, (d, _, _) in obr.items()}
    katalog = []
    bledy = []
    for k, (dane, cel, nazwa) in obr.items():
        z, delta = wyniki[k]
        bajty, surowe = plik_obrazu(dane, z, delta)
        (OUT / nazwa).write_bytes(bajty)
        okno = 0x8000 if 0x4000 <= cel < 0x8000 else 0xC000 if cel >= 0x8000 else None
        poza = cel + len(dane) + (0 if surowe else delta) - okno if okno else 0
        if poza > LDR_SPILL:
            bledy.append(f"{k}: dekompresja w miejscu wychodzi {poza} B poza ${okno - 1:04X} (LDR_SPILL = {LDR_SPILL})")
        o = man["obrazy"].get(k)
        katalog.append({"klucz": k, "plik": nazwa, "id": o["id"] if o else None, "bank_xex": o["bank"] if o else None,
                        "slot": o["slot"] if o else None, "bank_nosnika": o["bank_nosnika"] if o else None,
                        "alt_slot": man.get("alt_slot", {}).get(k), "cel": cel,
                        "len_u": len(dane), "len_c": len(bajty) - NAGLOWEK, "delta": 0 if surowe else delta, "surowe": surowe,
                        "dlugosc": len(bajty), "poza_oknem": max(poza, 0)})
    znane = {k["plik"] for k in katalog}
    for p in OUT.iterdir():                               # stare pliki spoza katalogu (także formaty sprzed zmiany)
        if p.is_file() and p.suffix.upper() in (".ZX2", ".ZON", ".ACT", ".PAK", ".KOD") and p.name not in znane:
            p.unlink()
    (OUT / "katalog.json").write_text(json.dumps(katalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    raport(man, katalog)
    for b in bledy:
        print("BŁĄD:", b, file=sys.stderr)
    return 1 if bledy else 0


def raport(man: dict, katalog: list[dict]) -> None:
    obr = man["obrazy"]
    po = {k["klucz"]: k for k in katalog}

    def rodzaj(k: str) -> str:
        if k.startswith("kod"):
            return "kod gry"
        if k == "cracktro":
            return "cracktro"
        if k == "scrc":
            return "ekrany (bank 36)"
        if obr[k]["slot"] is None:
            return "banki stałe"
        return {"ATLAS": "atlasy tła", "ATLAS2": "atlasy tła", "ZSPR": "sprite'y stref", "OBJZ": "obiekty stref",
                "LEVEL": "dane poziomów", "LEVEL2": "dane poziomów"}[obr[k]["slot"]]

    gra = [k for k in katalog if k["klucz"] != "cracktro"]
    suma = sum(k["dlugosc"] for k in gra)
    crk = po["cracktro"]["dlugosc"] if "cracktro" in po else 0
    # cart: kod i cracktro surowo (stub kopiuje bez dekompresji - plan-m7-ldr.md §4.9), obrazy banków skompresowane ciągiem
    cart_dane = sum(k["dlugosc"] for k in gra if not k["klucz"].startswith("kod"))
    cart_kod = sum(k["len_u"] for k in katalog if k["klucz"].startswith("kod") or k["klucz"] == "cracktro")
    n_am = 2 + math.ceil(cart_kod / CART_BANK) + math.ceil(cart_dane / CART_BANK)
    n_sic = 1 + math.ceil(cart_kod / SIC_BANK) + math.ceil(cart_dane / SIC_BANK)
    sek = {k["plik"]: math.ceil(k["dlugosc"] / ED_DANE) for k in gra}
    L = ["# Raport obrazów nośnika (M7.1, tools/pack_zone.py)", "",
         "Źródło: `build/sonic-a8-vbxe.xex`; kompresja zx02 v3 (dmsc), opcje domyślne; plik = nagłówek 4 B + strumień "
         "(format: `tools/pack_zone.py`). Dekompresja w miejscu: strumień kończy się `delta` B za końcem wyniku.", "",
         "## Obrazy", "", "| Plik | Obraz | Bank XEX → nośnik | Cel | len_u | Plik B | % | delta | poza oknem | sektory ED |",
         "|---|---|---|---|---:|---:|---:|---:|---:|---:|"]
    for k in katalog:
        bn = f"{k['bank_xex']} → {k['bank_nosnika']} ({k['slot'] or ('tylko XEX - M7.3: w bankach 41/43/59' if obr.get(k['klucz'], {}).get('tylko_xex') else 'stały')}" + (f"; alt {k['alt_slot']}" if k.get("alt_slot") else "") + ")" \
            if k["bank_xex"] is not None else "RAM"
        L.append(f"| {k['plik']} | {k['klucz']} | {bn} | ${k['cel']:04X} | {k['len_u']} | {k['dlugosc']} | "
                 f"{k['dlugosc'] / k['len_u'] * 100:.1f} | {k['delta']} | {k['poza_oknem']} | {math.ceil(k['dlugosc'] / ED_DANE)} |")
    L += ["", "## Wg rodzaju danych", "", "| Rodzaj | Obrazy | Surowe B | Pliki B | % |", "|---|---:|---:|---:|---:|"]
    grupy: dict[str, list[dict]] = {}
    for k in katalog:
        grupy.setdefault(rodzaj(k["klucz"]), []).append(k)
    for g, kl in grupy.items():
        s = sum(k["len_u"] for k in kl)
        z = sum(k["dlugosc"] for k in kl)
        L.append(f"| {g} | {len(kl)} | {s} | {z} | {z / s * 100:.1f} |")
    s = sum(k["len_u"] for k in katalog)
    z = sum(k["dlugosc"] for k in katalog)
    L.append(f"| **razem** | {len(katalog)} | {s} | {z} | {z / s * 100:.1f} |")
    L += ["", "## Grupy z manifestu (pakiety strefa / akt / wspólny – do podziału na dyskietki)", "",
          "| Grupa | Obrazy | Pliki B | sektory ED |", "|---|---|---:|---:|"]
    for p in man["pakiety"]:
        kl = [po[n] for n in p["obrazy"]]
        L.append(f"| {p['nazwa']} | {', '.join(k['plik'] for k in kl)} | {sum(k['dlugosc'] for k in kl)} | "
                 f"{sum(math.ceil(k['dlugosc'] / ED_DANE) for k in kl)} |")
    naj = max(gra, key=lambda k: k["len_c"])
    L += ["", f"Największy strumień: {naj['plik']} ({naj['klucz']}) – {naj['len_c']} B; max delta {max(k['delta'] for k in gra)} B; "
          f"max wyjście poza okno {max(k['poza_oknem'] for k in gra)} B (LDR_SPILL = {LDR_SPILL})."]
    L += ["", "## Zajętość nośników (szacunek M7.1; układ ostateczny – M7.3/M7.4)", "",
          f"- **Obrazy gry razem** (z kodem, bez cracktro): {suma} B ({suma / 1024:.1f} KB); cracktro: {crk} B.",
          f"- **AtariMax 1 MB** (8 KB): 2 banki boot (0 i 127) + kod i cracktro surowo {cart_kod} B ({math.ceil(cart_kod / CART_BANK)} banki) + "
          f"obrazy banków {cart_dane} B ciągiem ({math.ceil(cart_dane / CART_BANK)}) → **{n_am}/{CART_BANKI}**.",
          f"- **SIC! 512 KB** (16 KB): 1 bank boot + kod {math.ceil(cart_kod / SIC_BANK)} + obrazy {math.ceil(cart_dane / SIC_BANK)} → "
          f"**{n_sic}/{SIC_BANKI}**.",
          f"- **ATR DD** (DOS 2 / MyDOS, {DD_DANE} B danych na sektor): {sum(math.ceil(k['dlugosc'] / DD_DANE) for k in gra)} sektorów "
          f"(+ plik startowy i xBIOS – M7.4).",
          f"- **ED** (DOS 2.5, {ED_SEKTORY} wolnych sektorów × {ED_DANE} B): {sum(sek.values())} sektorów = "
          f"{sum(sek.values()) / ED_SEKTORY:.2f} dyskietki bez duplikatów (podział z kopiami GHZ/SS na każdej – M7.4, "
          f"`docs/plan-m7-ldr.md` §3.3)."]
    (OUT / "raport.md").write_text("\n".join(L) + "\n", encoding="utf-8", newline="\n")
    print(f"obrazy nośnika: {len(katalog)} plików, gra {suma} B ({suma / 1024:.1f} KB) z kodem; AtariMax "
          f"{n_am}/{CART_BANKI}, SIC! {n_sic}/{SIC_BANKI} (kod surowo), "
          f"ED {sum(sek.values())}/{ED_SEKTORY} sektorów ({sum(sek.values()) / ED_SEKTORY:.2f} dyskietki bez duplikatów); "
          f"raport: build/pakiety/raport.md")


if __name__ == "__main__":
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main(sys.argv[1:]))
