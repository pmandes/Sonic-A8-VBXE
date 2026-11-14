#!/usr/bin/env python3
"""Obrazy dyskietek ATR (M7.4, docs/plan-m7.md M7.4, docs/plan-m7-ldr.md §2-§3): jeden duży obraz MyDOS DD i zestaw ED dla stockowego 1050.

Wejście (tools/build.cmd atr):
  build/sonic-atr.xex + .lab   - build ATR (MADS: -d:MEDIA=3) = kontener jak w carcie: kod rezydentny $8000+ (część surowa do kod_hi_start i
                                 reszta), kod pod oknem $4100+, cracktro + src/ldr/atr_start.asm $2000+, obrazy banków stałych (z danymi
                                 rozpuszczonego banku 36) i slotów (LD_ZONY = 1); nie do uruchamiania
  build/assets/manifest.json   - obrazy nośnika (stałe nosnik.stale - ldr_init, doczytywane ldr.ladowane - ldr_need), potrzeby poziomów,
                                 kolejność gry (crk_lv), pod-poziomy, etapy specjalne
  tools/bin/xbios/             - xbios.com (bajt w bajt), xboot.obx (sektory startowe) - XXL, nota docs/licencje/xbios-NOTA.md
  tools/bin/dir2atr.exe        - AtariSIO 0.30-221009 (GPL-2, docs/licencje/dir2atr-NOTA.md)

Pliki na dyskietce (system plików DOS 2 / MyDOS - czyta je xBIOS):
  XBIOS.COM   xBIOS 4.3 (instalator relokuje bibliotekę 1 KB na stronę z XBIOS.CFG)
  XBIOS.CFG   konfiguracja (generowana tu): $43, 'XAUTORUN   ', strona xBIOS $04, strona bufora $0C, INITAD $02E2, RUNAD $02E0, moduł I/O
              $0000 (wewnętrzny SIO - bez ROM-u OS-u), relokator $0000, PORTB $FF, NMIEN $40, IRQEN $C0 (+ komentarz, xBIOS go nie czyta)
  XAUTORUN    plik binarny Atari: segment $8000-(kod_hi_start-1) (część surowa: jądro, NMI, ldr z ldr_fetch_sio i komunikatami; tablice
              ldr_img_len* i ldr_build uzupełnione tutaj), INIT atr_ini (review M7.4: nakładka VBXE i MEMAC wyłączone przed segmentem $2000 -
              po RESET-cie w grze okno MEMAC A przekierowało by go do VRAM-u), segment $2000- (cracktro + atr_start.asm), RUN start_media
  Bnn.ZX2     obraz banku / kodu: nagłówek 4 B (len_u, delta, flagi) + strumień zx02 (ten sam format co cart i RAMCART - tools/pack_zone.py;
              review M7.4: bity 1-7 flag = numer wydania, ten sam w ldr_build - kontrola zestawu dyskietek z jednego wydania);
              nn = id obrazu dziesiętnie (manifest: 1..49; B50 = kod pod oknem $4100+, B51 = kod rezydentny od kod_hi_start)
  DISKn.ID    0 B - numer dyskietki dla ludzi (gra go nie czyta)

Tablice gry w XAUTORUN (src/ldr/ldr.asm): ldr_img_lenl / ldr_img_lenh [id] = len_c (długość strumienia - DOS 2 nie zna dokładnej długości
pliku, a ldr_fetch_sio potrzebuje jej na pozycję "w miejscu" i kontrolę xNOTE); bity 6-7 ldr_img_lenh = numer dyskietki - 1, o którą prosi
komunikat "INSERT DISK n" (najniższy bit maski dyskietek obrazu; duży obraz: 0).

Wyjścia:
  build/sonic-a8-vbxe.atr             dir2atr -d -m -B xboot.obx (MyDOS DD, rozmiar automatyczny) - cała gra, bez zmiany dyskietki
  build/sonic-ed1.atr, -ed2, -ed3...  dir2atr -E [-B xboot.obx dla D1] (DOS 2.5 ED, 1040 sektorów; 1010 użytkowych po 125 B) - podział:
                                      D1 = system + kod + banki stałe + rdzeń R; dalej strefy w kolejności gry (crk_lv), strefa z pod-poziomami
                                      w całości, rdzeń R = obrazy GHZ + etapów specjalnych + poziomu $12 na KAŻDEJ dyskietce (game over i etapy
                                      specjalne bez zmiany dyskietki) - docs/plan-m7-ldr.md §3.3; flagi plików DOS 2.5 $03 (pliki mogące leżeć
                                      w sektorach > 719) zamienione na $42 - xBOOT z flagą $03 nie startuje XBIOS.COM (test rozpoznawczy M7.4)
  build/atr/raport.md, katalog.json   pliki, sektory, wolne sektory, wpisy katalogu, maski dyskietek

Kontrole: obrazy od $4000; dekompresja w miejscu wychodzi <= LDR_SPILL B za $7FFF (banki, kod pod oknem) i nie dalej niż $BFFB (kod
rezydentny - RAM $BFFC zostaje $FF); len_c < 16 KB; id < LDR_NIMG; RAM kontenera tylko w częściach kodu (+ stuby INI $0600, wektory $02E0); każdy obraz ATR
przeczytany własnym parserem DOS 2 / MyDOS (tools/atr_dos.py), każdy plik Bnn.ZX2 rozpakowany emulacją 6502 w miejscu (tools/pack_test.py)
= obraz kontenera / kod z RAM kontenera; XAUTORUN = część surowa z tablicami i cracktro; wpisy katalogu <= 64; zestaw ED: każda strefa
na jednej dyskietce, rdzeń na każdej, kod i banki stałe na D1.

Użycie:  python tools/pack_atr.py [--bez-emulacji]   (kod 0 = zapisane)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import struct
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import atr_dos  # noqa: E402
import pack_zone as pz  # noqa: E402
import sprawdz_xex as sx  # noqa: E402

BUILD = ROOT / "build"
OUT = BUILD / "atr"
D2A = ROOT / "tools" / "bin" / "dir2atr.exe"
XB = ROOT / "tools" / "bin" / "xbios"
ED_SEKTORY = 1010                   # DOS 2.5 ED: sektory użytkowe (1040 - boot 3 - VTOC/katalog 9 - 720 - VTOC2 ...; VTOC obrazu dir2atr -E)
ED_DANE = 125                       # bajty danych w sektorze 128 B (3 B łącza)
KATALOG_MAX = 64                    # wpisy katalogu DOS 2 / MyDOS (xBOOT: 64/128)
XBIOS_STRONA, BUF_STRONA = 0x04, 0x0C


def seg(adr: int, dane: bytes) -> bytes:
    return struct.pack("<HH", adr, adr + len(dane) - 1) + dane


def sektory_ed(n: int) -> int:
    return math.ceil(n / ED_DANE)


def _sprawdz_jeden(arg: tuple[str, bytes, bytes, int]) -> str | None:
    """Proces roboczy: plik Bnn.ZX2 przeczytany z ATR-a, rozpakowany emulacją 6502 w miejscu od adresu cel = wzór (None = zgodny)."""
    import pack_test
    n, plik, wzor, cel = arg
    len_u, delta, flagi = struct.unpack_from("<HBB", plik)
    z = plik[pz.NAGLOWEK:]
    if len_u != len(wzor):
        return f"{n}: len_u {len_u} != {len(wzor)}"
    if flagi & 1:
        return None if z == wzor else f"{n}: dane surowe różne"
    try:
        got = pack_test.dekompresja_6502(z, cel, len_u, delta, True)
    except (ValueError, IndexError) as e:
        return f"{n}: {e}"
    return None if got == wzor else f"{n}: rozpakowany obraz różny"


def strefy_poziomow(man: dict) -> dict[int, str]:
    """g_level / cel pod-poziomu / etap -> nazwa strefy (podział ED: strefa w całości na jednej dyskietce)."""
    nazwy = ["GHZ", "BRI", "JUN", "LAB", "SBZ", "SKY"]
    w: dict[int, str] = {}
    for s in man["strefy"]:
        g = s["g_level"]
        w[g] = nazwy[g // 3] if g < 18 else "KON"               # $12 = 18: poziom końcowy (obrazy GHZ1 + obiekty 30 - rdzeń)
    for p in man["pod"]:
        w[p["cel"]] = w[p["akt"]]                              # $14-$19 -> SBZ (akt 13), $1A -> SKY (akt 16)
    for e in man["specjalne"]:
        w[e["etap"]] = "SS"
    return w


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--bez-emulacji", action="store_true", help="bez kontroli dekompresji emulacją 6502 (szybciej)")
    a = ap.parse_args(argv)
    xex = BUILD / "sonic-atr.xex"
    L = pz.etykiety(xex.with_suffix(".lab"))
    bledy: list[str] = []
    if L.get("LDR_MEDIA") != 3:
        print(f"BŁĄD: {xex.name}: LDR_MEDIA {L.get('LDR_MEDIA')} (oczekiwano 3 - build ATR)", file=sys.stderr)
        return 1
    man = json.loads((BUILD / "assets" / "manifest.json").read_text(encoding="utf-8"))
    banki, (ram, maska) = pz.obrazy_z_xex(xex.read_bytes())
    NIMG, ID_LO, ID_HI, NTAB = L["LDR_NIMG"], L["LDR_ID_KODLO"], L["LDR_ID_KODHI"], L["LDR_ATR_N"]

    # --- obrazy banków (stałe + doczytywane) z kontenera ---
    nazwy = list(dict.fromkeys(man["nosnik"]["stale"] + man["ldr"]["ladowane"]))
    nazwy.sort(key=lambda n: man["obrazy"][n]["id"])
    obr: dict[str, bytes] = {}
    cel: dict[str, int] = {}
    ident: dict[str, int] = {}
    for n in nazwy:
        o = man["obrazy"][n]
        if not 0 < o["id"] < NIMG:
            bledy.append(f"id obrazu {n} = {o['id']} poza 1..{NIMG - 1} (LDR_NIMG w src/kernel/mem.inc)")
            continue
        if o["bank"] not in banki:
            bledy.append(f"kontener nie ładuje obrazu {n} (bank {o['bank']})")
            continue
        d, m = banki[o["bank"]]
        lo, hi = pz.zakres(m)
        if lo:
            bledy.append(f"obraz {n}: początek ${0x4000 + lo:04X} - ldr rozpakowuje od $4000")
        obr[n], cel[n], ident[n] = bytes(d[:hi]), 0x4000, o["id"]
        if o.get("nosnik_dl") and o.get("plik"):
            plik = (BUILD / "assets" / o["plik"]).read_bytes()
            if any(plik[o["nosnik_dl"]:]):
                bledy.append(f"{o['plik']}: niezerowe bajty za ${o['nosnik_dl']:04X} (tam na nośniku dane banku 36)")
    obce = sorted(set(banki) - {man["obrazy"][n]["bank"] for n in nazwy})
    if obce:
        bledy.append(f"kontener ładuje banki spoza obrazów nośnika: {obce}")

    # --- kod: część surowa (XAUTORUN), obrazy kodu B50 / B51, cracktro + atr_start ---
    khs, hi_end, lo_st, lo_end = L["KOD_HI_START"], L["CODE_HI_END"], L["CODE_LO_START"], L["CODE_LO_END"]
    crk = [i for i in range(0x2000, 0x4000) if maska[i]]
    crk_end = crk[-1] + 1 if crk else 0x2000
    if crk_end != L["ATR_START_END"]:
        bledy.append(f"segment $2000: koniec ${crk_end:04X}, atr_start_end ${L['ATR_START_END']:04X}")
    czesci = [(0x8000, khs), (khs, hi_end), (lo_st, lo_end), (0x2000, crk_end)]
    poza = [x for x in range(0x10000) if maska[x] and not (0x02E0 <= x < 0x02E6 or 0x0600 <= x < 0x0700
                                                            or any(s <= x < e for s, e in czesci))]
    if poza:
        bledy.append(f"RAM kontenera poza częściami kodu: {len(poza)} B, np. ${poza[0]:04X}")
    obr["kod_lo"], cel["kod_lo"], ident["kod_lo"] = bytes(ram[lo_st:lo_end]), lo_st, ID_LO
    obr["kod_hi"], cel["kod_hi"], ident["kod_hi"] = bytes(ram[khs:hi_end]), khs, ID_HI
    surowa = bytearray(ram[0x8000:khs])
    crk_dane = bytes(ram[0x2000:crk_end])

    # --- pliki obrazów (zx02, cache pack_zone) ---
    pz.CACHE.mkdir(parents=True, exist_ok=True)
    jedne = list(dict.fromkeys(obr.values()))
    with ThreadPoolExecutor(8) as ex:
        z_danych = dict(zip(jedne, ex.map(pz.zx02, jedne)))
    pliki: dict[str, bytes] = {}                                    # nazwa obrazu -> plik (nagłówek + strumień)
    info: dict[str, dict] = {}
    # review M7.4: numer wydania - bity 1-7 bajtu flag każdego pliku Bnn.ZX2 i ldr_build w XAUTORUN (ldr_fetch_sio: niezgodny = "DISK ERROR";
    # dyskietki zestawu z różnych wydań). Skrót SHA-256 części surowej, cracktro i wszystkich obrazów (bez zera - pliki sprzed M7.4 mają 0)
    h = hashlib.sha256(bytes(surowa) + crk_dane + b"".join(obr[n] for n in sorted(obr)))
    wydanie = h.digest()[0] & 0xFE or 0x02
    for n, dane in obr.items():
        z, delta = z_danych[dane]
        bajty, surowe = pz.plik_obrazu(dane, z, delta)
        bajty = bajty[:3] + bytes([bajty[3] | wydanie]) + bajty[4:]  # flagi: b0 = surowe (ldr_unpack), b1-7 = wydanie
        len_c = len(bajty) - pz.NAGLOWEK
        d_ = 0 if surowe else delta
        koniec = cel[n] + len(dane) + d_                             # strumień w miejscu kończy się delta B za końcem wyniku
        limit = L["CART_HDR_RAM"] if n == "kod_hi" else 0x8000 + pz.LDR_SPILL   # B51: RAM $BFFC = $FF zostaje (RESET w ldr_kod)
        if koniec > limit:
            bledy.append(f"{n}: strumień w miejscu kończy się na ${koniec:04X} (limit ${limit:04X})")
        if len_c >= 0x4000:
            bledy.append(f"{n}: len_c {len_c} >= 16 KB (6 bitów starszego bajtu w ldr_img_lenh)")
        pliki[n] = bajty
        info[n] = {"id": ident[n], "len_u": len(dane), "len_c": len_c, "delta": d_, "surowe": surowe, "cel": cel[n], "koniec": koniec}
    nazwa_pliku = {n: f"B{ident[n]:02d}.ZX2" for n in obr}

    # --- podział zestawu ED (docs/plan-m7-ldr.md §3.3) ---
    stref = strefy_poziomow(man)
    obrazy_strefy: dict[str, set[str]] = {}
    for k, potr in man["potrzeby"].items():
        obrazy_strefy.setdefault(stref[int(k, 16)], set()).update(potr.values())
    stale = set(man["nosnik"]["stale"])
    rdzen = set().union(*(obrazy_strefy[s] for s in ("GHZ", "SS", "KON"))) - stale
    cfg = (bytes([0x43]) + b"XAUTORUN   " + bytes([XBIOS_STRONA, BUF_STRONA, 0xE2, 0x02, 0xE0, 0x02, 0, 0, 0, 0, 0xFF, 0x40, 0xC0])
           + b" SONIC A8 VBXE v1.0: xBIOS $0400, bufor $0C00, wewnetrzny SIO (tools/pack_atr.py)")
    xbios_com = (XB / "xbios.com").read_bytes()
    systemowe = {"XBIOS.COM": len(xbios_com), "XBIOS.CFG": len(cfg), "XAUTORUN": 0}   # XAUTORUN - długość niżej (ta sama w obu wariantach)
    rozm = {nazwa_pliku[n]: len(b) for n, b in pliki.items()}

    def xautorun(dyski: dict[str, int]) -> bytes:
        s = bytearray(surowa)
        for n, i in info.items():
            idx = i["id"]
            if not 0 < idx < NTAB:
                raise ValueError(f"{n}: id {idx} poza tablicą ldr_img_len* ({NTAB})")
            s[L["LDR_IMG_LENL"] - 0x8000 + idx] = i["len_c"] & 0xFF
            s[L["LDR_IMG_LENH"] - 0x8000 + idx] = (i["len_c"] >> 8) | (dyski.get(n, 0) << 6)
        s[L["LDR_BUILD"] - 0x8000] = wydanie
        # review M7.4: INIT atr_ini po części surowej, przed segmentem $2000 - nakładka VBXE i MEMAC wyłączone (po RESET-cie w grze)
        return (b"\xff\xff" + seg(0x8000, bytes(s)) + seg(0x02E2, struct.pack("<H", L["ATR_INI"])) + seg(0x2000, crk_dane)
                + seg(0x02E0, struct.pack("<H", L["START_MEDIA"])))

    systemowe["XAUTORUN"] = len(xautorun({}))

    def sekt(pl: set[str]) -> int:
        return sum(sektory_ed(rozm.get(p, systemowe.get(p, 0))) for p in pl)

    obr_strefy_pl = {s: {nazwa_pliku[n] for n in v - stale} for s, v in obrazy_strefy.items()}
    rdzen_pl = {nazwa_pliku[n] for n in rdzen}
    d1 = set(systemowe) | {nazwa_pliku[n] for n in stale} | {nazwa_pliku["kod_lo"], nazwa_pliku["kod_hi"]} | rdzen_pl | {"DISK1.ID"}
    dyskietki = [d1]
    kolejnosc_stref: list[str] = []
    for g in man["kolejnosc"]:
        s = stref[g]
        if s not in kolejnosc_stref:
            kolejnosc_stref.append(s)
    przydzial: dict[str, int] = {}
    for s in kolejnosc_stref:
        if s in ("GHZ", "SS", "KON"):
            przydzial[s] = -1                                       # rdzeń - na każdej dyskietce
            continue
        nowe = obr_strefy_pl[s] - dyskietki[-1]
        if sekt(dyskietki[-1] | nowe) <= ED_SEKTORY and len(dyskietki[-1] | nowe) <= KATALOG_MAX:
            dyskietki[-1] |= nowe
        else:
            dyskietki.append(rdzen_pl | obr_strefy_pl[s] | {f"DISK{len(dyskietki) + 1}.ID"})
            if sekt(dyskietki[-1]) > ED_SEKTORY:
                bledy.append(f"strefa {s}: rdzeń + strefa = {sekt(dyskietki[-1])} sektorów > {ED_SEKTORY}")
        przydzial[s] = len(dyskietki) - 1
    if len(dyskietki) > 4:
        bledy.append(f"zestaw ED: {len(dyskietki)} dyskietek > 4 (2 bity numeru dyskietki w ldr_img_lenh)")
    maska_ed: dict[str, int] = {}
    for n in info:
        m = sum(1 << k for k, d in enumerate(dyskietki) if nazwa_pliku[n] in d)
        if not m:
            bledy.append(f"{n}: obraz nie trafił na żadną dyskietkę ED")
        maska_ed[n] = m
    if bledy:
        for b in bledy:
            print("BŁĄD:", b, file=sys.stderr)
        return 1
    dysk_ed = {n: (m & -m).bit_length() - 1 for n, m in maska_ed.items()}   # najniższy bit maski -> numer - 1

    # --- katalogi plików i obrazy ATR ---
    OUT.mkdir(parents=True, exist_ok=True)
    tresc_wsp = {**{nazwa_pliku[n]: b for n, b in pliki.items()}, "XBIOS.COM": xbios_com, "XBIOS.CFG": cfg}
    warianty = [("sonic-a8-vbxe.atr", "dd", ["-d", "-m", "-B", str(XB / "xboot.obx")],
                 {**tresc_wsp, "XAUTORUN": xautorun({})})]
    xa_ed = xautorun(dysk_ed)
    for k, d in enumerate(dyskietki):
        opcje = ["-E"] + (["-B", str(XB / "xboot.obx")] if k == 0 else [])
        tresc = {p: (b"" if p.endswith(".ID") else xa_ed if p == "XAUTORUN" else tresc_wsp[p]) for p in d}
        warianty.append((f"sonic-ed{k + 1}.atr", f"ed{k + 1}", opcje, tresc))
    for stary in BUILD.glob("sonic-ed*.atr"):                       # stare dyskietki zestawu (np. po zmianie liczby)
        stary.unlink()
    wyniki = []
    for plik_atr, kat, opcje, tresc in warianty:
        dk = OUT / kat
        if dk.exists():
            shutil.rmtree(dk)
        dk.mkdir(parents=True)
        for p, b in tresc.items():
            (dk / p).write_bytes(b)
        cel_atr = BUILD / plik_atr
        if cel_atr.exists():
            cel_atr.unlink()
        r = subprocess.run([str(D2A)] + opcje + [str(cel_atr), str(dk)], capture_output=True, text=True)
        if r.returncode or not cel_atr.is_file():
            print(f"BŁĄD: dir2atr {plik_atr}: {r.returncode} {r.stdout[-400:]} {r.stderr[-400:]}", file=sys.stderr)
            return 1
        if kat.startswith("ed"):                                    # DOS 2.5: flaga $03 -> $42 (xBOOT nie czyta plików z $03)
            raw = bytearray(cel_atr.read_bytes())
            zm = 0
            for s in range(361, 369):
                off = 16 + (s - 1) * 128
                for j in range(8):
                    if raw[off + j * 16] == 0x03:
                        raw[off + j * 16] = 0x42
                        zm += 1
            cel_atr.write_bytes(bytes(raw))
        else:
            zm = 0
        wyniki.append((plik_atr, kat, tresc, zm))

    # --- kontrola odczytu: parser DOS 2 / MyDOS, XAUTORUN, dekompresja 6502 w miejscu ---
    zle: list[str] = []
    zadania = []
    raport_dysk = []
    for plik_atr, kat, tresc, zm in wyniki:
        at = atr_dos.Atr.z_pliku(BUILD / plik_atr)
        kt = at.katalog()
        if len(kt) != len(tresc) or len(kt) > KATALOG_MAX:
            zle.append(f"{plik_atr}: {len(kt)} wpisów katalogu, plików {len(tresc)}")
        for w in kt:
            if w.nazwa not in tresc:
                zle.append(f"{plik_atr}: obcy plik {w.nazwa}")
                continue
            b = at.plik(w)
            if b != tresc[w.nazwa]:
                zle.append(f"{plik_atr}: {w.nazwa} różny od źródła")
            if w.flaga not in (0x42, 0x46):
                zle.append(f"{plik_atr}: {w.nazwa} flaga ${w.flaga:02X} (xBOOT / xBIOS: $42 albo $46)")
        for p, b in tresc.items():
            if at.znajdz(p) is None:
                zle.append(f"{plik_atr}: brak {p}")
        xa = at.plik(at.znajdz("XAUTORUN")) if at.znajdz("XAUTORUN") else b""
        segs = list(sx.segmenty(xa)) if xa else []
        if xa and ([s for s, _ in segs] != [0x8000, 0x02E2, 0x2000, 0x02E0] or bytes(segs[2][1]) != crk_dane
                   or bytes(segs[1][1]) != struct.pack("<H", L["ATR_INI"])):
            zle.append(f"{plik_atr}: XAUTORUN - segmenty {[hex(s) for s, _ in segs]}")
        elif xa:
            tab = bytes(segs[0][1])
            for n, i in info.items():
                lo = tab[L["LDR_IMG_LENL"] - 0x8000 + i["id"]]
                hi = tab[L["LDR_IMG_LENH"] - 0x8000 + i["id"]]
                dysk = (hi >> 6) + 1
                if lo | (hi & 0x3F) << 8 != i["len_c"]:
                    zle.append(f"{plik_atr}: ldr_img_len {n} różne od pliku")
                if (kat == "dd" and dysk != 1) or (kat != "dd" and not (maska_ed[n] >> (dysk - 1)) & 1):
                    zle.append(f"{plik_atr}: {n} - komunikat prosiłby o dyskietkę {dysk}, a pliku na niej nie ma")
            spr = bytearray(tab)
            for idx in range(NTAB):
                spr[L["LDR_IMG_LENL"] - 0x8000 + idx] = surowa[L["LDR_IMG_LENL"] - 0x8000 + idx]
                spr[L["LDR_IMG_LENH"] - 0x8000 + idx] = surowa[L["LDR_IMG_LENH"] - 0x8000 + idx]
            if tab[L["LDR_BUILD"] - 0x8000] != wydanie:
                zle.append(f"{plik_atr}: ldr_build ${tab[L['LDR_BUILD'] - 0x8000]:02X} != wydanie ${wydanie:02X}")
            spr[L["LDR_BUILD"] - 0x8000] = surowa[L["LDR_BUILD"] - 0x8000]
            if bytes(spr) != bytes(surowa) or segs[3][1] != struct.pack("<H", L["START_MEDIA"]):
                zle.append(f"{plik_atr}: XAUTORUN - część surowa / RUN różne od kontenera")
        for n in info:
            w = at.znajdz(nazwa_pliku[n])
            if w is not None:
                b = at.plik(w)
                if b[3] & 0xFE != wydanie:
                    zle.append(f"{plik_atr}: {nazwa_pliku[n]} - wydanie w flagach ${b[3] & 0xFE:02X} != ${wydanie:02X}")
                zadania.append((f"{plik_atr}:{nazwa_pliku[n]} ({n})", b, obr[n], cel[n]))
        v = at.vtoc()
        uzyte = sum(len(at.lancuch(w)) for w in kt)
        raport_dysk.append({"atr": plik_atr, "opis": at.opis(), "plikow": len(kt), "sektory_plikow": uzyte, "wolne": v["wolne"],
                            "uzytkowe": v["uzytkowe"], "bajty": (BUILD / plik_atr).stat().st_size, "flagi_03_na_42": zm})
    if not a.bez_emulacji:
        with ProcessPoolExecutor() as ex:
            zle += [w for w in ex.map(_sprawdz_jeden, zadania, chunksize=4) if w]
    if zle:
        for b in zle:
            print("BŁĄD:", b, file=sys.stderr)
        return 1

    # --- raport ---
    katalog = {"obrazy": {n: {**info[n], "plik": nazwa_pliku[n], "maska_ed": maska_ed[n], "dysk_ed": dysk_ed[n] + 1} for n in info},
               "dyskietki_ed": [sorted(d) for d in dyskietki], "przydzial_stref": {s: (k + 1 if k >= 0 else "wszystkie") for s, k in przydzial.items()},
               "atr": raport_dysk, "xautorun": systemowe["XAUTORUN"], "rdzen": sorted(rdzen), "wydanie": wydanie}
    (OUT / "katalog.json").write_text(json.dumps(katalog, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    R = ["# Obrazy ATR (M7.4, tools/pack_atr.py)", "",
         f"Źródło: `build/{xex.name}` (+ `.lab`), xBIOS `tools/bin/xbios/` (XBIOS.CFG: strona `$04`, bufor `$0C`, wewnętrzny SIO), "
         "`tools/bin/dir2atr.exe`.", "",
         f"- część surowa XAUTORUN `$8000-${khs - 1:04X}` ({khs - 0x8000} B), cracktro + atr_start `$2000-${crk_end - 1:04X}` "
         f"({crk_end - 0x2000} B), plik XAUTORUN {systemowe['XAUTORUN']} B",
         f"- kod z obrazów: B{ID_LO:02d} `${lo_st:04X}-${lo_end - 1:04X}` ({lo_end - lo_st} B -> {info['kod_lo']['len_c']} B), "
         f"B{ID_HI:02d} `${khs:04X}-${hi_end - 1:04X}` ({hi_end - khs} B -> {info['kod_hi']['len_c']} B, strumień do "
         f"${info['kod_hi']['koniec'] - 1:04X})",
         f"- obrazy banków: {len(info) - 2} ({sum(i['len_c'] + 4 for n, i in info.items() if not n.startswith('kod'))} B z nagłówkami); "
         f"numer wydania (bity 1-7 flag plików, ldr_build) ${wydanie:02X}",
         f"- rdzeń R (na każdej dyskietce ED): {', '.join(sorted(rdzen))} - {sekt(rdzen_pl)} sektorów ED", "",
         "| obraz ATR | format | plików | sektory plików | wolne sektory | bajty pliku | flagi $03→$42 |", "|---|---|---:|---:|---:|---:|---:|"]
    for d in raport_dysk:
        R.append(f"| `build/{d['atr']}` | {d['opis']} | {d['plikow']} | {d['sektory_plikow']} | {d['wolne']} | {d['bajty']} | {d['flagi_03_na_42']} |")
    R += ["", "Przydział stref (zestaw ED, kolejność gry): " + ", ".join(f"{s} → {'wszystkie' if k < 0 else f'D{k + 1}'}" for s, k in przydzial.items()), "",
          "| id | obraz | plik | len_u | len_c | delta | maska ED | prośba o dyskietkę |", "|---:|---|---|---:|---:|---:|---|---:|"]
    for n in sorted(info, key=lambda x: info[x]["id"]):
        i = info[n]
        R.append(f"| {i['id']} | {n} | {nazwa_pliku[n]} | {i['len_u']} | {i['len_c']} | {i['delta']} | {maska_ed[n]:03b} | {dysk_ed[n] + 1} |")
    (OUT / "raport.md").write_text("\n".join(R) + "\n", encoding="utf-8", newline="\n")
    print(f"ATR: build/sonic-a8-vbxe.atr ({raport_dysk[0]['opis']}, wolne {raport_dysk[0]['wolne']}), zestaw ED {len(dyskietki)} × 1040 "
          f"(wolne: {', '.join(str(d['wolne']) for d in raport_dysk[1:])} sektorów; strefy: "
          + ", ".join(f"{s}→{'R' if k < 0 else k + 1}" for s, k in przydzial.items())
          + f"); kontrola: {len(zadania)} plików Bnn.ZX2 przeczytanych z ATR-ów"
          + ("" if a.bez_emulacji else " i rozpakowanych emulacją 6502 w miejscu") + " = obrazy kontenera, XAUTORUN = część surowa + cracktro")
    return 0


if __name__ == "__main__":
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main(sys.argv[1:]))
