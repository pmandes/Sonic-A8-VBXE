#!/usr/bin/env python3
"""Obraz cartridge'a (M7.3, docs/plan-m7.md M7.3): AtariMax 1 MB (CAR 42 i 75, surowy .bin) i SIC! 512 KB (CAR 56) z buildu cartu.

Wejście (tools/build.cmd cart, osobno dla każdego typu - kod obiektów w bankach 2/11/30/45/49 woła kod rezydentny TEGO buildu):
  build/sonic-cart-<typ>.xex + .lab   - XEX buildu cartu (MADS: -d:MEDIA=1 -d:CART_TYPE=n) = kontener: kod rezydentny $8000+, kod pod oknem
                                        $4100+, cracktro $2000+, obrazy banków stałych (z danymi rozpuszczonego banku 36) i slotów (LD_ZONY = 1);
                                        nie do uruchamiania (bez INIT-ów)
  build/cartboot-<typ>.xex + .lab     - bank startowy (src/boot/cartboot.asm): napis, kod wejścia z ROM-u, nagłówek $BFFA, stub $0600
  build/assets/manifest.json          - obrazy nośnika: stałe (nosnik.stale - ldr_init) i doczytywane (ldr.ladowane - ldr_need)

Układ cartu - banki LOGICZNE po 8 KB widziane w oknie $A000-$BFFF (AtariMax: bank = bank sprzętowy 0-127; SIC!: bank logiczny L = górna
połówka banku 16 KB nr L - gra nie włącza okna $8000, bo zasłoniłoby ldr / NMI / LDR_SPILL w $8000-$9FFF; dolne połówki banków 0.. niosą
strumień kodu surowego - czyta go tylko stub przez okno $8000 (bit 5 rejestru), reszta dolnych połówek pusta, $FF):
  bank 0 (AtariMax: także 127 - CAR 42 startuje z 127, CAR 75 z 0) - bank startowy:
    $A000  nagłówek 16 B: 'SP', wersja formatu 1, 'A8', wersja gry 1, 0 (Sonic A8 VBXE v1.0), CART_TYPE (0 AtariMax, 1 SIC!), liczba obrazów,
           najwyższe id, liczba użytych banków logicznych (z bankiem startowym), bank strumienia kodu, 4 B rezerwy (0)
    $A010  katalog CC_* (src/kernel/mem.inc): 5 tablic po 64 B indeksowanych id obrazu 1..63 - bank logiczny początku pliku, adres pliku
           w oknie lo, hi ($A000-$BFFF), długość pliku lo, hi (0 = brak obrazu); ten sam układ co katalog RAMCART (M7.2)
    $A150  napis, $A200 obraz stubu startowego (256 B, tablica cb_tab uzupełniona tu), $A300 kod wejścia, $BFFA nagłówek cartu OS-u
  bank 1..  (AtariMax; SIC!: dolne połówki od banku 0) strumień kodu surowego (stub kopiuje go bez dekompresji): kod rezydentny $8000-(CODE_HI_END-1), kod pod oknem CODE_LO_START-
            (CODE_LO_END-1), cracktro $2000-; każda część od pełnej strony (stub kopiuje stronami)
  dalej     pliki obrazów w kolejności id ciągiem przez kolejne banki: nagłówek 4 B (len_u 16 b, delta, flagi: b0 = surowe) + strumień
            zx02 (tools/pack_zone.py - ten sam plik co na ATR i w RAMCART); nagłówek nigdy nie przechodzi przez granicę banku
            (ldr_fetch_cart czyta go 4 odczytami (zp),y) - wtedy dopełnienie $FF do końca banku.
Pliki: build/sonic-atarimax.car (CAR 42), build/sonic-atarimax75.car (CAR 75), build/sonic-atarimax.bin (1 MB bez nagłówka - flashery,
UltimateCart; Altirra: /cartmapper), build/sonic-sic512.car (CAR 56). Nagłówek CAR: 'CART', typ (BE32), suma bajtów ROM-u (BE32), 4 B zer.
Raport: build/cart/raport-<typ>.md, katalog: build/cart/katalog-<typ>.json.

Bramki: banki n/128 (AtariMax, bank 127 = kopia startowego) i n/32 (SIC!), LDR_SPILL (dekompresja w miejscu wychodzi <= 16 B za $7FFF),
obrazy od $4000 (ldr rozpakowuje zawsze od BANK_WIN), kontener bez banku 36 i bez banków spoza obrazów nośnika, końcówki plików
music / boss za nosnik_dl = zera (tam dane banku 36), RAM główna kontenera tylko w częściach kodu (+ stuby INI $0600 i wektory $02E0),
stub <= 256 B, nagłówek $BFFA-$BFFF, kontrola odczytu: każdy obraz odczytany z gotowego obrazu ROM-u przez katalog jak ldr_fetch_cart
i rozpakowany emulacją 6502 zx02 w miejscu (tools/pack_test.py) = obraz z kontenera; strumień kodu = RAM kontenera.

Użycie:  python tools/pack_cart.py --typ am|sic   (kod 0 = zapisane)
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import pack_zone as pz  # noqa: E402
import sprawdz_xex as sx  # noqa: E402

BUILD = ROOT / "build"
OUT = BUILD / "cart"
BANK = 0x2000                       # bank logiczny = okno $A000-$BFFF
WIN = 0xA000
CC_NID = 64                         # src/kernel/mem.inc: CC_NID, katalog od CC_BANK = $A010
TYPY = {  # typ -> (CART_TYPE, banki logiczne, opis, wyjścia (plik, typ CAR | None = surowy .bin))
    "am": (0, 128, "AtariMax 1 MB (8 Mbit)", [("sonic-atarimax.car", 42), ("sonic-atarimax75.car", 75), ("sonic-atarimax.bin", None)]),
    "sic": (1, 32, "SIC! 512 KB", [("sonic-sic512.car", 56)]),
}
FILL = 0xFF                         # wolne miejsce: stan skasowanego flasha


def segmenty_xex(p: Path) -> list[tuple[int, bytes]]:
    return [(a, bytes(d)) for a, d in sx.segmenty(p.read_bytes())]


def _sprawdz_jeden(arg: tuple[str, bytes, bytes]) -> str | None:
    """Proces roboczy: plik obrazu (nagłówek + strumień) rozpakowany emulacją 6502 w miejscu = obraz (None = zgodny)."""
    import pack_test
    n, plik, wzor = arg
    len_u, delta, flagi = struct.unpack_from("<HBB", plik)
    z = plik[pz.NAGLOWEK:]
    if flagi & 1:
        return None if z == wzor else f"{n}: dane surowe różne"
    try:
        got = pack_test.dekompresja_6502(z, 0x4000, len_u, delta, True)
    except (ValueError, IndexError) as e:
        return f"{n}: {e}"
    return None if got == wzor else f"{n}: rozpakowany obraz różny"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--typ", choices=sorted(TYPY), required=True)
    ap.add_argument("--bez-emulacji", action="store_true", help="bez kontroli dekompresji emulacją 6502 (szybciej)")
    a = ap.parse_args(argv)
    ct, nbank, opis_typu, wyjscia = TYPY[a.typ]
    xex = BUILD / f"sonic-cart-{a.typ}.xex"
    boot = BUILD / f"cartboot-{a.typ}.xex"
    bledy: list[str] = []
    L = pz.etykiety(xex.with_suffix(".lab"))
    LB = pz.etykiety(boot.with_suffix(".lab"))
    if L.get("LDR_MEDIA") != 1 or L.get("LDR_CART_TYPE") != ct:
        print(f"BŁĄD: {xex.name}: LDR_MEDIA {L.get('LDR_MEDIA')}, LDR_CART_TYPE {L.get('LDR_CART_TYPE')} (oczekiwano 1, {ct})", file=sys.stderr)
        return 1
    man = json.loads((BUILD / "assets" / "manifest.json").read_text(encoding="utf-8"))
    banki, (ram, maska) = pz.obrazy_z_xex(xex.read_bytes())

    # --- obrazy nośnika: stałe + doczytywane, z kontenera (od $4000 do ostatniego zapisanego bajtu) ---
    nazwy = list(dict.fromkeys(man["nosnik"]["stale"] + man["ldr"]["ladowane"]))
    nazwy.sort(key=lambda n: man["obrazy"][n]["id"])
    obr: dict[str, bytes] = {}
    for n in nazwy:
        o = man["obrazy"][n]
        if o["bank"] not in banki:
            bledy.append(f"kontener nie ładuje obrazu {n} (bank {o['bank']})")
            continue
        d, m = banki[o["bank"]]
        lo, hi = pz.zakres(m)
        if lo:
            bledy.append(f"obraz {n}: początek ${0x4000 + lo:04X} - ldr rozpakowuje od $4000")
        obr[n] = bytes(d[:hi])
        if o.get("nosnik_dl") and o.get("plik"):       # końcówka pliku zastąpiona danymi banku 36 - w pliku muszą tam być zera
            plik = (BUILD / "assets" / o["plik"]).read_bytes()
            if any(plik[o["nosnik_dl"]:]):
                bledy.append(f"{o['plik']}: niezerowe bajty za ${o['nosnik_dl']:04X} (tam na nośniku dane banku 36)")
    wlasne = {man["obrazy"][n]["bank"] for n in nazwy}
    obce = sorted(set(banki) - wlasne)
    if obce:
        bledy.append(f"kontener ładuje banki spoza obrazów nośnika: {obce} (bank 36 ma być rozpuszczony - NOSNIK_320)")

    # --- kod surowy: 3 części (stub: cb_tab) ---
    hi_end, lo_st, lo_end = L["CODE_HI_END"], L["CODE_LO_START"], L["CODE_LO_END"]
    crk = [i for i in range(0x2000, 0x4000) if maska[i]]
    if not crk:
        bledy.append("kontener bez cracktro $2000")
        crk = [0x2000]
    czesci = [(0x8000, hi_end, 0x40), (lo_st, lo_end, lo_st >> 8), (0x2000, crk[-1] + 1, 0x20)]
    if lo_st & 0xFF or hi_end > 0xC000 or hi_end - 0x8000 > 0x4000:
        bledy.append(f"kod: CODE_LO_START ${lo_st:04X} nie od strony albo CODE_HI_END ${hi_end:04X} > $C000")
    poza = [x for x in range(0x10000) if maska[x] and not (0x02E0 <= x < 0x02E6 or 0x0600 <= x < 0x0700
                                                            or any(s <= x < e for s, e, _ in czesci))]
    if poza:
        bledy.append(f"RAM kontenera poza częściami kodu: {len(poza)} B, np. ${poza[0]:04X} (stub by ich nie skopiował)")
    strumien = bytearray()
    tab_np, tab_nr = [], []
    for s, e, _ in czesci:
        dane = bytes(ram[s:e])
        tab_np.append(len(dane) >> 8)
        tab_nr.append(len(dane) & 0xFF)
        strumien += dane + bytes([FILL]) * ((-len(dane)) % 256)     # każda część od pełnej strony

    # --- pliki obrazów (zx02, cache pack_zone) ---
    pz.CACHE.mkdir(parents=True, exist_ok=True)
    jedne = list(dict.fromkeys(obr.values()))
    with ThreadPoolExecutor(8) as ex:
        z_danych = dict(zip(jedne, ex.map(pz.zx02, jedne)))
    pliki: dict[str, bytes] = {}
    info: dict[str, dict] = {}
    for n, dane in obr.items():
        z, delta = z_danych[dane]
        bajty, surowe = pz.plik_obrazu(dane, z, delta)
        poza_okno = 0x4000 + len(dane) + (0 if surowe else delta) - 0x8000
        if poza_okno > pz.LDR_SPILL:
            bledy.append(f"{n}: dekompresja w miejscu wychodzi {poza_okno} B za $7FFF (LDR_SPILL = {pz.LDR_SPILL})")
        pliki[n] = bajty
        info[n] = {"len_u": len(dane), "len_c": len(bajty) - pz.NAGLOWEK, "delta": 0 if surowe else delta, "surowe": surowe}

    # --- układ logiczny: bank 0 startowy, od banku 1 strumień kodu (AtariMax; SIC!: kod w dolnych połówkach banków 0.. - czyta je tylko
    # stub przez okno $8000), dalej pliki ---
    sic = ct == 1
    flat = bytearray() if sic else bytearray(strumien)
    n_kod = math.ceil(len(strumien) / BANK)
    if sic and n_kod > nbank:
        bledy.append(f"SIC!: kod surowy {len(strumien)} B > dolne połówki {nbank} banków")
    kat: dict[str, tuple[int, int, int]] = {}                       # nazwa -> (bank, adres w oknie, długość)
    for n in nazwy:
        if n not in pliki:
            continue
        off = len(flat) % BANK
        if off > BANK - pz.NAGLOWEK:                               # nagłówek 4 B nie przez granicę banku
            flat += bytes([FILL]) * (BANK - off)
        poz = len(flat)
        kat[n] = (1 + poz // BANK, WIN + poz % BANK, len(pliki[n]))
        flat += pliki[n]
    n_dane = math.ceil(len(flat) / BANK)
    uzyte = 1 + n_dane                                              # z bankiem startowym (SIC!: górne połówki)
    limit = nbank - 1 if ct == 0 else nbank                         # AtariMax: bank 127 = kopia startowego
    if uzyte > limit:
        bledy.append(f"cart: {uzyte} banków logicznych > {limit} ({opis_typu})")
    if bledy:
        for b in bledy:
            print("BŁĄD:", b, file=sys.stderr)
        return 1

    # --- bank startowy ---
    bb = bytearray([FILL]) * BANK
    seg = segmenty_xex(boot)
    stub = next((d for s, d in seg if s == 0x0600), None)
    if stub is None or len(stub) > 256:
        print("BŁĄD: stub $0600 w cartboot brak albo > 256 B", file=sys.stderr)
        return 1
    stub = bytearray(stub)
    o = LB["CB_TAB"] - 0x0600
    stub[o] = 0 if sic else 1                                       # cb_t_bank: strumień kodu od banku 1 (SIC!: dolna połówka banku 0)
    stub[o + 1:o + 4] = bytes(tab_np)
    stub[o + 4:o + 7] = bytes(tab_nr)
    stub[o + 7:o + 10] = bytes(d for _, _, d in czesci)
    stub[o + 10] = math.ceil((hi_end - 0x8000) / 256)               # strony bufora $4000 -> $8000
    stub[o + 11:o + 13] = struct.pack("<H", L["START_MEDIA"])
    if LB["CB_T_RUN"] - 0x0600 != o + 11 or LB["CB_STUB_END"] - 0x0600 != o + 13:
        print("BŁĄD: układ cb_tab w cartboot.asm inny niż w pack_cart.py", file=sys.stderr)
        return 1
    for s, d in seg:
        if s == 0x0600:
            continue
        if not (WIN <= s and s + len(d) <= WIN + BANK):
            print(f"BŁĄD: segment cartboot ${s:04X} poza oknem $A000-$BFFF", file=sys.stderr)
            return 1
        bb[s - WIN:s - WIN + len(d)] = d
    rs = LB["CB_ROMSTUB"] - WIN
    if rs + len(stub) > LB["CB_ROMCODE"] - WIN or LB["CB_ROMTEXT"] < L["CC_END"]:
        print("BŁĄD: stub / napis w banku startowym nachodzą na kod wejścia / katalog", file=sys.stderr)
        return 1
    bb[rs:rs + len(stub)] = stub
    cat = bytearray(5 * CC_NID)
    for n, (b, adr, dl) in kat.items():
        i = man["obrazy"][n]["id"]
        if not 0 < i < CC_NID:                                      # katalog: CC_NID wpisów na tablicę (src/kernel/mem.inc)
            print(f"BŁĄD: id obrazu {n} = {i} poza 1..{CC_NID - 1} (katalog cartu CC_*)", file=sys.stderr)
            return 1
        cat[i], cat[CC_NID + i], cat[2 * CC_NID + i], cat[3 * CC_NID + i], cat[4 * CC_NID + i] = b, adr & 0xFF, adr >> 8, dl & 0xFF, dl >> 8
    bb[L["CC_BANK"] - WIN:L["CC_BANK"] - WIN + len(cat)] = cat
    bb[0:16] = b"SP" + bytes([1]) + b"A8" + bytes([1, 0, ct, len(kat), max(man["obrazy"][n]["id"] for n in kat), uzyte,
                                                        0 if sic else 1, 0, 0, 0, 0])   # bank kodu (SIC!: dolna połówka 0)
    if bb[0x1FFC] != 0 or bb[0x1FFD] != 0x04 or not (WIN <= struct.unpack_from("<H", bb, 0x1FFA)[0] < WIN + BANK):
        print("BŁĄD: nagłówek cartu $BFFA-$BFFF", file=sys.stderr)
        return 1

    # --- obraz fizyczny ---
    logiczne = [bytes(bb)] + [bytes(flat[k * BANK:(k + 1) * BANK]).ljust(BANK, bytes([FILL])) for k in range(n_dane)]
    if ct == 0:
        rom = bytearray([FILL]) * (nbank * BANK)
        for k, d in enumerate(logiczne):
            rom[k * BANK:(k + 1) * BANK] = d
        rom[(nbank - 1) * BANK:] = bb                               # bank 127 = startowy (CAR 42)

        def bank_rom(k: int) -> bytes:
            return bytes(rom[k * BANK:(k + 1) * BANK])


        def kod_rom(k: int) -> bytes:
            return bank_rom(k)
    else:
        rom = bytearray([FILL]) * (nbank * 2 * BANK)
        for k, d in enumerate(logiczne):
            rom[k * 2 * BANK + BANK:(k + 1) * 2 * BANK] = d         # górna połówka banku 16 KB (okno $A000)
        for k in range(n_kod):                                      # dolne połówki (okno $8000): strumień kodu dla stubu
            kaw = bytes(strumien[k * BANK:(k + 1) * BANK])
            rom[k * 2 * BANK:k * 2 * BANK + len(kaw)] = kaw

        def bank_rom(k: int) -> bytes:
            return bytes(rom[k * 2 * BANK + BANK:(k + 1) * 2 * BANK])

        def kod_rom(k: int) -> bytes:
            return bytes(rom[k * 2 * BANK:k * 2 * BANK + BANK])

    # --- kontrola odczytu z gotowego ROM-u: katalog jak ldr_fetch_cart, strumień kodu jak stub ---
    b0 = bank_rom(0)

    def czytaj(bank: int, adr: int, n: int, zrodlo=bank_rom) -> bytes:
        w = bytearray()
        while len(w) < n:
            k = min(n - len(w), WIN + BANK - adr)
            w += zrodlo(bank)[adr - WIN:adr - WIN + k]
            bank, adr = bank + 1, WIN
        return bytes(w)
    zle = []
    zadania = []
    for n in kat:
        i = man["obrazy"][n]["id"]
        cb = L["CC_BANK"] - WIN
        bank, adr, dl = b0[cb + i], b0[cb + CC_NID + i] | b0[cb + 2 * CC_NID + i] << 8, b0[cb + 3 * CC_NID + i] | b0[cb + 4 * CC_NID + i] << 8
        if (adr - WIN) % BANK > BANK - pz.NAGLOWEK:
            zle.append(f"{n}: nagłówek przez granicę banku")
        zadania.append((n, czytaj(bank, adr, dl), obr[n]))
    if ct == 0 and bank_rom(0) != bank_rom(nbank - 1):
        zle.append("bank 0 != bank 127")
    poz = 0
    for (s, e, _), np_, nr in zip(czesci, tab_np, tab_nr):
        dl = np_ * 256 + nr
        if czytaj((0 if sic else 1) + poz // BANK, WIN + poz % BANK, dl, kod_rom) != bytes(ram[s:e]):
            zle.append(f"strumień kodu ${s:04X}-${e - 1:04X} różny od RAM kontenera")
        poz += dl + (-dl) % 256
    if not a.bez_emulacji:
        with ProcessPoolExecutor() as ex:
            zle += [w for w in ex.map(_sprawdz_jeden, zadania, chunksize=2) if w]
    else:
        zle += [f"{n}: plik w ROM-ie różny" for (n, got, _) in zadania if got != pliki[n]]
    if zle:
        for b in zle:
            print("BŁĄD:", b, file=sys.stderr)
        return 1

    # --- zapis ---
    OUT.mkdir(parents=True, exist_ok=True)
    suma = sum(rom) & 0xFFFFFFFF
    for plik, typ in wyjscia:
        dane = bytes(rom) if typ is None else b"CART" + struct.pack(">II", typ, suma) + bytes(4) + bytes(rom)
        (BUILD / plik).write_bytes(dane)
    kod_b = len(strumien)
    dane_b = sum(len(p) for p in pliki.values())
    katalog = {"typ": a.typ, "cart_type": ct, "opis": opis_typu, "banki_logiczne": uzyte, "banki_max": limit, "suma_car": suma,
               "kod": [{"od": s, "do": e, "bajty": e - s, "strona_celu": d} for s, e, d in czesci],
               "obrazy": [{"obraz": n, "id": man["obrazy"][n]["id"], "bank_xex": man["obrazy"][n]["bank"], "staly": man["obrazy"][n]["staly"],
                           "bank": b, "adres": adr, "dlugosc": dl, **info[n]} for n, (b, adr, dl) in kat.items()]}
    (OUT / f"katalog-{a.typ}.json").write_text(json.dumps(katalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    stale = [n for n in kat if man["obrazy"][n]["staly"]]
    R = [f"# Cartridge {opis_typu} (M7.3, tools/pack_cart.py)", "",
         f"Źródło: `build/{xex.name}` (+ `.lab`), bank startowy `build/{boot.name}`; pliki: " + ", ".join(f"`build/{p}`" for p, _ in wyjscia) + ".", "",
         (f"- banki 8 KB: **{uzyte + 1}/{nbank}** ({uzyte} logicznych: startowy 0 + kod surowy i obrazy {n_dane}; bank 127 = kopia banku 0 - "
          f"CAR 42)" if not sic else
          f"- SIC!: górne połówki (okno $A000 - gra): **{uzyte}/{nbank}** (startowa 1 + obrazy {n_dane}); dolne połówki (okno $8000 - tylko "
          f"stub): kod surowy {n_kod}/{nbank}"),
         f"- kod surowy: {kod_b} B (rezydentny {hi_end - 0x8000}, pod oknem {lo_end - lo_st}, cracktro {crk[-1] + 1 - 0x2000}; części od pełnych stron)",
         f"- obrazy: {len(kat)} plików ({len(stale)} stałych + {len(kat) - len(stale)} doczytywanych), {dane_b} B ({dane_b / 1024:.1f} KB) "
         f"z nagłówkami; wolne w ostatnim banku {(-len(flat)) % BANK} B; wolne banki {limit - uzyte}",
         f"- suma CAR ${suma:08X}", "", "| id | obraz | bank XEX | stały | bank | adres | plik B | len_u | delta |", "|---:|---|---:|---|---:|---|---:|---:|---:|"]
    for n, (b, adr, dl) in kat.items():
        R.append(f"| {man['obrazy'][n]['id']} | {n} | {man['obrazy'][n]['bank']} | {'tak' if man['obrazy'][n]['staly'] else ''} | {b} | "
                 f"${adr:04X} | {dl} | {info[n]['len_u']} | {info[n]['delta']} |")
    (OUT / f"raport-{a.typ}.md").write_text("\n".join(R) + "\n", encoding="utf-8", newline="\n")
    print(f"{opis_typu}: " + (f"{uzyte}/{nbank} górnych połówek (okno $A000), kod surowy w dolnych {n_kod}/{nbank}" if sic else
                              f"{uzyte + 1}/{nbank} banków 8 KB ({uzyte} + kopia startowego w 127)")
          + f" (kod surowy {kod_b} B, {len(kat)} obrazów {dane_b} B), "
          f"suma ${suma:08X}; kontrola: {len(kat)} obrazów odczytanych z ROM-u przez katalog"
          + ("" if a.bez_emulacji else " i rozpakowanych emulacją 6502 w miejscu") + " = obrazy kontenera, strumień kodu = RAM kontenera -> "
          + ", ".join(f"build/{p}" for p, _ in wyjscia))
    return 0


if __name__ == "__main__":
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main(sys.argv[1:]))
