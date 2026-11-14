#!/usr/bin/env python3
"""Kontrola build/game.xex po asemblacji (M4.0): zawartość banków ładowanych z XEX.

Segmenty XEX są odtwarzane jak loader: stub INI (`lda #PB; sta PORTB; rts` pod $0610) wybiera bank 1088K, segmenty
w oknie $4000-$7FFF trafiają wtedy do tego banku. Sprawdzane:
  - bank 45 (kod i dane obiektów): zakresy danych z banku 1 ROM-u pod adresami SMS i granice aktywacji
    (tools/extract_sms.py: OBJ_SPANS, OBJ_BOUNDS_ATARI) = obraz build/assets/bank_objdata.bin - kod obiektów
    nie może ich nadpisać;
  - bank 47 (grafika obiektów) = build/assets/bank_objart.bin (część ładowana);
  - M4.1: skoki jsr/jmp z kodu banku 45 (listing build/game.lst, znaczniki ;@BANK45; M4.9a: dekoder tools/lst6502.py,
    także jmp z pseudo-rozkazów jne/jcs) prowadzą tylko do kodu banku 45 albo do kodu rezydentnego $8000+;
  - M7.1: banki XEX-a = obrazy manifestu (build/assets/manifest.json), zestaw roboczy 320K (stałe + sloty) <= 16.
  - M7.3: build cartu (LDR_MEDIA = 1, build/sonic-cart-*.xex - kontener dla tools/pack_cart.py): bramka ;@LDR rozszerzona (skoki tylko
    w obszarze, `jmp (ind)`, dane spod cartu tylko ze znacznikiem ;@CART, (zp),y tylko zp_fx / zp_src / zp_dst), $D5xx w całym kodzie
    tylko sta abs w ;@LDR, banki kontenera = obrazy nośnika (bez banku 36), banki 2 / 11 / 30 / 45 / 47 jak w XEX.
  - M7.4: build ATR (LDR_MEDIA = 3, build/sonic-atr.xex - kontener dla tools/pack_atr.py): kontener jak cart, bramka ;@LDR fazy startu
    (skoki_ldr_atr: przed wgraniem obrazów kodu tylko część surowa, cracktro, xBIOS, ROM; reszta ze znacznikiem ;@KOD), $D5xx - nigdzie.
  - M7.2: bramka ;@LDR (kod ldr przy włączonym źródle - cart w M7.3): jsr/jmp tylko poniżej $A000 i poza oknem $4000-$7FFF, $D5xx tylko
    `sta abs`; build nośnika (etykieta LDR_MEDIA <> 0 w .lab, np. build/sonic-ram.xex): XEX nie ładuje slotów ani banków stref, banki
    obiektów strefy sprawdzane w XEX-ie pierwszego przebiegu (build/sonic-ram-src.xex), kod rezydentny obu przebiegów identyczny,
    RAMCART: każdy obraz z katalogu rozpakowany emulacją 6502 zx02 (w miejscu, tools/pack_test.py) = obraz z pierwszego przebiegu.

Użycie: python tools/sprawdz_xex.py [build/game.xex]   (kod wyjścia 0 = zgodne)
"""
from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import extract_sms as ex  # noqa: E402
import lst6502  # noqa: E402

PORTB = 0xD301
MAX_BANKOW = 64            # M6.6: sufit XEX = 1088K (U1MB / RAMBO 1088K), docs/m7-nosniki.md


def bank_portb(p: int) -> int | None:
    """Numer banku 1088K z wartości PORTB (bit 4 = 0: okno CPU na bank), None dla RAM głównej."""
    if p & 0x10:
        return None
    return ((p >> 1) & 7) | ((p >> 5) << 3)


def segmenty(xex: bytes):
    p = 0
    while p < len(xex):
        a, = struct.unpack_from("<H", xex, p)
        if a == 0xFFFF:
            p += 2
            continue
        a, e = struct.unpack_from("<HH", xex, p)
        p += 4
        yield a, xex[p:p + e - a + 1]
        p += e - a + 1


NAKLADANIA: dict[int, int] = {}                   # M6.6: bank -> liczba bajtów zapisanych przez więcej niż jeden segment (błąd budowy)


def banki_z_xex(xex: bytes) -> dict[int, bytearray]:
    pamiec = bytearray(0x10000)                    # RAM główna (stuby INI)
    banki: dict[int, bytearray] = {}
    zajete: dict[int, bytearray] = {}
    NAKLADANIA.clear()
    portb = 0xFF
    for a, dane in segmenty(xex):
        bank = bank_portb(portb)
        for i, v in enumerate(dane):
            adr = a + i
            if bank is not None and 0x4000 <= adr < 0x8000:
                banki.setdefault(bank, bytearray(0x4000))[adr - 0x4000] = v
                z = zajete.setdefault(bank, bytearray(0x4000))
                if z[adr - 0x4000]:
                    NAKLADANIA[bank] = NAKLADANIA.get(bank, 0) + 1
                z[adr - 0x4000] = 1
            else:
                pamiec[adr] = v
        if a == 0x02E2 and len(dane) >= 2:           # INI: stub ustawiający PORTB
            ini, = struct.unpack_from("<H", dane)
            kod = pamiec[ini:ini + 6]
            if kod[0] == 0xA9 and kod[2] == 0x8D and kod[3:5] == bytes((PORTB & 0xFF, PORTB >> 8)):
                portb = kod[1]
            elif kod[0] == 0xAD and kod[3] == 0x8D:  # ld_restore: lda ld_saved; sta PORTB
                portb = 0xFF
    return banki


def skoki_banku45(lst: Path, obszar: str = "b45") -> list[str]:
    """Skoki jsr/jmp z kodu banku 45 (listing MADS między znacznikami ;@BANK45 i ;@BANK45_END; obszar "bz" - bank obiektów
    strefy, znaczniki ;@BANKZ) poza ten kod: przy włączonym banku obiektów widać tylko kod banku i kod rezydentny $8000+
    (kod pod $4100 jest zasłonięty). M4.9a: rozkazy dekodowane przez tools/lst6502.py - także jmp ukryte w pseudo-rozkazach
    MADS (jne, jcs...)."""
    w = lst6502.wczytaj(lst)
    instr = lst6502.poczatki(w, obszar)
    return [f"${a:04X} -> ${cel:04X}" for a, op, cel in lst6502.skoki(w, obszar)
            if op in (lst6502.OPK_JMP, lst6502.OPK_JSR) and cel < 0x8000 and cel not in instr]


def _indeksowany_abs(op: int) -> bool:
    """Tryb abs,X / abs,Y (oficjalne rozkazy 6502: niskie 5 bitów $19, $1C, $1D, $1E; także ldx abs,Y $BE i ldy abs,X $BC)."""
    return (op & 0x1F) in (0x19, 0x1C, 0x1D, 0x1E)


def _posredni_zp(op: int) -> bool:
    """Tryb (zp),Y albo (zp,X)."""
    return (op & 0x1F) in (0x11, 0x01)


def skoki_ldr(lst: Path, zp_dozwolone: set[int] | None = None) -> tuple[int, list[str]]:
    """M7.2: obszar ;@LDR ... ;@LDR_END (kod ldr działający przy włączonym źródle danych - na carcie okno $A000-$BFFF zasłania kod gry,
    a okno $4000-$7FFF trzyma bank źródła / slotu): jsr/jmp (także z pseudo-rozkazów) tylko do celów < $A000 poza $4000-$7FFF; dostęp do
    $D500-$D5FF (rejestr cartu) tylko `sta abs` - odczyty i tryby indeksowane mogą przełączyć bank cartu.
    M7.3 (review M7.2, ryzyko 3): skoki i gałęzie tylko na początki rozkazów TEGO obszaru (kod poza nim nie jest sprawdzany); `jmp (ind)`
    zabronione; operandy danych (abs, abs,X/Y) w $A000-$BFFF tylko w wierszu ze znacznikiem `;@CART` (zamierzony odczyt ROM-u cartu -
    katalog; inaczej odczyt zmiennej gry spod cartu); abs,X/Y z bazą $D400-$D5FF (przejście strony w $D5xx); (zp),Y / (zp,X) tylko przez
    wskaźniki zp_dozwolone (zp_fx, zp_src, zp_dst - nie wskazują $D5xx). Wynik: (liczba rozkazów, błędy)."""
    w = lst6502.wczytaj(lst)
    r = lst6502.rozkazy(w, "ldr")
    starty = {a for a, op, _, _ in r if op is not None}
    zrodla = {a: zr for a, _, zr, _ in r}
    # M7.3 (review): wyjątek - skok do ROM-u OS-u ($C000+) w wierszu ze znacznikiem ;@OS (cart_reset: jmp COLDSV po włączeniu cartu)
    zle = [f"${a:04X} -> ${cel:04X} (cel poza obszarem ;@LDR)" for a, op, cel in lst6502.skoki(w, "ldr")
           if not (cel >= 0xC000 and op in (lst6502.OPK_JMP, lst6502.OPK_JSR) and ";@OS" in zrodla.get(a, ""))
           and (cel not in starty or cel >= 0xA000 or 0x4000 <= cel < 0x8000)]
    for a, op, zr, b in r:
        if op is None:
            continue
        if op == lst6502.OPK_JMP_IND:
            zle.append(f"${a:04X}: jmp (ind) w obszarze ;@LDR ({zr})")
        if len(b) == 3 and lst6502.dl_rozkazu(op) == 3 and op not in (lst6502.OPK_JMP, lst6502.OPK_JSR):
            adr = b[1] | b[2] << 8
            if 0xD500 <= adr <= 0xD5FF and op != 0x8D:
                zle.append(f"${a:04X}: dostęp do ${adr:04X} inny niż sta abs ({zr})")
            if _indeksowany_abs(op) and 0xD400 <= adr <= 0xD5FF:
                zle.append(f"${a:04X}: abs,X/Y z bazą ${adr:04X} - przejście strony w $D5xx ({zr})")
            if 0xA000 <= adr < 0xC000 and ";@CART" not in zr:
                zle.append(f"${a:04X}: operand ${adr:04X} pod oknem cartu bez znacznika ;@CART ({zr})")
        if zp_dozwolone is not None and _posredni_zp(op) and len(b) == 2 and b[1] not in zp_dozwolone:
            zle.append(f"${a:04X}: ({b[1]:02X}),y / (zp,x) przez wskaźnik spoza {sorted(zp_dozwolone)} ({zr})")
    # wiersze obcięte ('+'): w obszarze tylko pseudo-rozkazy mwa (lda / sta) - bez skoków; skoki() dekoduje widoczne bajty wiersza
    return len(r), zle


def skoki_ldr_atr(lst: Path, lab: dict[str, int]) -> tuple[int, list[str]]:
    """M7.4: build ATR (LDR_MEDIA = 3) - obszar ;@LDR = kod fazy startu, wykonywany ZANIM z dyskietki przyjdą obrazy kodu B50 ($4100+) i
    B51 (kod_hi_start-code_hi_end): część rezydentna w src/ldr/ldr.asm (atr_reset, ldr_fetch_sio, ldr_msg) i src/ldr/atr_start.asm
    (za cracktro). Skoki (jsr / jmp / gałęzie, także pseudo-rozkazy) tylko do: części surowej $8000-(kod_hi_start-1), cracktro i
    atr_start ($2000-(atr_start_end-1)), xBIOS-a $0400-$07FF (wiersz ze znacznikiem ;@XBIOS), ROM-u OS-u $C000+ (;@OS) albo dowolnie
    w wierszu ze znacznikiem ;@KOD (wykonywany dopiero po wgraniu kodu); operandy danych w obrazie B51 (kod_hi_start-$BFFF) i w kodzie pod
    oknem ($4000-$7FFF) tylko z ;@KOD; `jmp (ind)` zabronione; $D500-$D5FF - żadnego dostępu (bez cartu). Wynik: (liczba rozkazów, błędy)."""
    w = lst6502.wczytaj(lst)
    r = lst6502.rozkazy(w, "ldr")
    zrodla = {a: zr for a, _, zr, _ in r}
    khs, crk_end = lab["KOD_HI_START"], lab["ATR_START_END"]
    zle = []
    for a, op, c in lst6502.skoki(w, "ldr"):
        zr = zrodla.get(a, "")
        if ";@KOD" in zr or 0x8000 <= c < khs or 0x2000 <= c < crk_end:
            continue
        if 0x0400 <= c < 0x0800 and ";@XBIOS" in zr:
            continue
        if c >= 0xC000 and ";@OS" in zr:
            continue
        zle.append(f"${a:04X} -> ${c:04X} (cel poza częścią surową / cracktro / xBIOS bez znacznika)")
    for a, op, zr, b in r:
        if op is None:
            continue
        if op == lst6502.OPK_JMP_IND:
            zle.append(f"${a:04X}: jmp (ind) w obszarze ;@LDR ({zr})")
        if len(b) == 3 and lst6502.dl_rozkazu(op) == 3 and op not in (lst6502.OPK_JMP, lst6502.OPK_JSR):
            adr = b[1] | b[2] << 8
            if 0xD500 <= adr <= 0xD5FF or (_indeksowany_abs(op) and 0xD400 <= adr <= 0xD5FF):
                zle.append(f"${a:04X}: dostęp do ${adr:04X} - ATR bez cartu ({zr})")
            if (khs <= adr < 0xC000 or 0x4000 <= adr < 0x8000) and ";@KOD" not in zr:
                zle.append(f"${a:04X}: operand ${adr:04X} w obrazie kodu (przed ldr_kod nie istnieje) bez znacznika ;@KOD ({zr})")
    return len(r), zle


def osiagalnosc_atr(lst: Path, lab: dict[str, int]) -> tuple[int, list[str]]:
    """Review M7.4 (pkt 10): cała część surowa ATR [$8000, kod_hi_start) i segment $2000 (cracktro + atr_start.asm) - analiza przepływu
    od wszystkich rozkazów obszarów ;@LDR (kod fazy startu, zanim przyjdą obrazy B50 / B51): śledzone jsr / jmp / gałęzie (także
    pseudo-rozkazy jcc...) przez kod spoza ;@LDR (np. ldr_load_pb, ldr_unpack, zx02, cracktro). Każdy osiągnięty rozkaz: skok do obrazów
    kodu ([kod_hi_start, $C000) i [$4000, $8000)) albo dane spod nich - tylko w wierszu ze znacznikiem ;@KOD (biała lista: wykonywane
    dopiero po wgraniu kodu, np. mus_regs_restore tylko przy ld_os = 0), xBIOS $0400-$07FF - ;@XBIOS, ROM $C000+ - ;@OS; `jmp (ind)`
    zabronione; cel skoku musi być początkiem rozkazu. Wynik: (liczba osiągniętych rozkazów, błędy)."""
    w = lst6502.wczytaj(lst)
    khs, crk_end = lab["KOD_HI_START"], lab["ATR_START_END"]
    rozk: dict[int, tuple[int | None, str, list[int]]] = {}
    for obszar in (None, "ldr"):
        for a, op, zr, b in lst6502.rozkazy(w, obszar):
            if 0x8000 <= a < khs or 0x2000 <= a < crk_end:
                rozk.setdefault(a, (op, zr, b))
    # pierwszy wiersz segmentu XEX ma w listingu przedrostek "FFFF> adres-koniec>" (lst6502.RX_LST go nie czyta) - np. crk_main $2000
    rx_seg = re.compile(r"^\s*\d+\s+FFFF>\s+([0-9A-F]{4})-[0-9A-F]{4}>\s+((?:[0-9A-F]{2}[ \t])+)\s*\+?\s*(.*)$")
    for linia in lst.read_text(encoding="ascii", errors="replace").splitlines():
        m = rx_seg.match(linia)
        if m:
            a = int(m[1], 16)
            if (0x8000 <= a < khs or 0x2000 <= a < crk_end) and not lst6502.RX_DANE.match(m[3].strip()):
                b = [int(x, 16) for x in m[2].split()]
                rozk.setdefault(a, (b[0], m[3].strip(), b[:lst6502.dl_rozkazu(b[0])]))
    surowe = lambda c: 0x8000 <= c < khs or 0x2000 <= c < crk_end   # noqa: E731
    kod = lambda c: khs <= c < 0xC000 or 0x4000 <= c < 0x8000        # noqa: E731
    start = [a for a, op, _, _ in lst6502.rozkazy(w, "ldr") if op is not None]
    zle: list[str] = []
    odw: set[int] = set()
    kolejka = list(start)
    while kolejka:
        a = kolejka.pop()
        while a not in odw:
            if a not in rozk:
                zle.append(f"${a:04X}: osiągnięty adres nie jest początkiem rozkazu części surowej")
                break
            odw.add(a)
            op, zr, b = rozk[a]
            if op is None:                       # bajt niepokazany (pseudo-rozkaz mwa) - dalej
                a += 1
                continue
            dl = lst6502.dl_rozkazu(op)
            nast = a + dl
            c = lst6502.cel(a, b) if len(b) == dl else None
            klucz = ";@KOD" in zr
            if op == lst6502.OPK_JMP_IND:
                zle.append(f"${a:04X}: jmp (ind) w kodzie fazy startu ({zr})")
                break
            if c is not None and (op in (lst6502.OPK_JMP, lst6502.OPK_JSR) or op in lst6502.OPK_GALEZIE):
                if klucz:
                    pass                         # ;@KOD - celu nie śledzimy (wykonywany po wgraniu kodu)
                elif surowe(c):
                    kolejka.append(c)
                elif 0x0400 <= c < 0x0800 and ";@XBIOS" in zr:
                    pass
                elif c >= 0xC000 and ";@OS" in zr:
                    pass
                else:
                    zle.append(f"${a:04X} -> ${c:04X}: skok z kodu fazy startu poza część surową bez znacznika ({zr})")
                if op == lst6502.OPK_JMP:
                    break
            elif len(b) == 3 and dl == 3:        # operand danych abs / abs,X/Y
                adr = b[1] | b[2] << 8
                if kod(adr) and not klucz:
                    zle.append(f"${a:04X}: dane ${adr:04X} z obrazu kodu w fazie startu bez ;@KOD ({zr})")
            if op in (0x60, 0x40, 0x00):          # rts, rti, brk
                break
            a = nast
    return len(odw), zle


def bramka_d5xx(lst: Path) -> tuple[int, list[str]]:
    """M7.3: cały listing buildu cartu (kod rezydentny, pod oknem, banki 45 / 11 / 2 / 30 / 49): każdy dostęp do $D500-$D5FF przy
    wyłączonym carcie WŁĄCZA AtariMax (bank = bity 0-6 adresu) i zasłania kod $A000-$BFFF - dozwolone tylko `sta abs` w obszarze ;@LDR.
    Zabronione: abs / abs,X/Y z adresem $D5xx poza tym, abs,X/Y z bazą $D400-$D5FF (przejście strony - rzeczywisty odczyt w $D5xx).
    (zp),Y nie da się sprawdzić statycznie - wskaźniki gry: VBXE $D6xx/$D7xx, RAM. Wynik: (liczba rozkazów, błędy)."""
    w = lst6502.wczytaj(lst)
    zle, n = [], 0
    for obszar in (None, "lo", "b45", "bz", "bz2", "bz3", "ldr"):
        for a, op, zr, b in lst6502.rozkazy(w, obszar):
            if op is None or len(b) != 3 or lst6502.dl_rozkazu(op) != 3 or op in (lst6502.OPK_JMP, lst6502.OPK_JSR):
                continue
            n += 1
            adr = b[1] | b[2] << 8
            if 0xD500 <= adr <= 0xD5FF and not (obszar == "ldr" and op == 0x8D):
                zle.append(f"${a:04X} ({obszar or 'rezydentny'}): dostęp do ${adr:04X} ({zr})")
            elif _indeksowany_abs(op) and 0xD400 <= adr <= 0xD5FF:
                zle.append(f"${a:04X} ({obszar or 'rezydentny'}): abs,X/Y z bazą ${adr:04X} ({zr})")
    return n, zle


def lab_etykiety(lab: Path) -> dict[str, int]:
    w = {}
    if lab.is_file():
        for linia in lab.read_text(encoding="ascii", errors="replace").splitlines():
            p = linia.split()
            if len(p) >= 3 and len(p[1]) == 4:
                try:
                    w[p[2].upper()] = int(p[1], 16)
                except ValueError:
                    pass
    return w


def ram_z_xex(xex: bytes) -> tuple[bytearray, bytearray]:
    """RAM główna po załadowaniu XEX-a (64 KB) i maska zapisanych bajtów (segmenty poza oknem banków przy wybranym banku)."""
    import pack_zone          # noqa: E402 (pack_zone importuje ten moduł)
    _, ram = pack_zone.obrazy_z_xex(xex)
    return ram


def bramka_nosnika(xex: Path, banki: dict[int, bytearray]) -> int:
    """M7.2: build nośnika z RAMCART (MEDIA_RAM): pierwszy przebieg (…-src.xex) = źródło obrazów - kod rezydentny identyczny, banki
    obiektów strefy z danymi ROM-u; XEX nie ładuje slotów ani obrazów doczytywanych; RAMCART rozpakowany = obrazy pierwszego przebiegu."""
    import pack_test          # noqa: E402
    import pack_zone          # noqa: E402
    wynik = 0
    src = xex.with_name(xex.stem + "-src.xex")
    if not src.is_file():
        print(f"BŁĄD: brak {src.name} (pierwszy przebieg tools/build.cmd sonic-ram)", file=sys.stderr)
        return 1
    man = json.loads((ROOT / "build" / "assets" / "manifest.json").read_text(encoding="utf-8"))
    xb, sb = xex.read_bytes(), src.read_bytes()
    (r1, m1), (r2, m2) = ram_z_xex(sb), ram_z_xex(xb)
    # kod i dane w RAM głównej poza stubami INI ($0600-$06FF): cracktro $2000+, kod $4100+ i $8000+
    roz = [a for a in range(0x0700, 0x10000) if m1[a] != m2[a] or (m1[a] and r1[a] != r2[a])]
    print(f"kod rezydentny przebiegów 1 ({src.name}) i 2: " + ("IDENTYCZNY" if not roz else
          f"RÓŻNY w {len(roz)} B, np. " + ", ".join(f"${a:04X}" for a in roz[:8])))
    wynik |= 1 if roz else 0
    b_src = banki_z_xex(sb)
    for b, plik, spans, nazwa in ((11, "bank_objz.bin", ex.OBJZ_SPANS, "obiekty strefy"), (2, "bank_objz2.bin", ex.OBJZ2_SPANS, "obiekty strefy 2"),
                                  (30, "bank_objz3.bin", ex.OBJZ3_SPANS, "obiekty strefy 3")):
        dane = (ROOT / "build" / "assets" / plik).read_bytes()
        bb = b_src.get(b)
        zle = [f"${a:04X}" for a, n, _ in spans if bb is None or bb[a - 0x8000:a - 0x8000 + n] != dane[a - 0x8000:a - 0x8000 + n]]
        print(f"bank {b} ({src.name}): {len(spans)} zakresów danych ({nazwa}) " + ("ZGODNE" if not zle else f"RÓŻNE: {', '.join(zle)}"))
        wynik |= 1 if zle else 0
    # sloty i obrazy doczytywane przez ldr: nie z XEX-a
    lad = {man["obrazy"][n]["bank"] for n in man["ldr"]["ladowane"]}
    zle = sorted((set(man["sloty"].values()) | lad) & set(banki))
    print("XEX nośnika: sloty i obrazy ldr " + ("nieładowane (tylko ldr)" if not zle else f"ŁADOWANE z XEX: {zle}"))
    wynik |= 1 if zle else 0
    # RAMCART: katalog w pierwszym banku, pliki ciągiem przez banki RC_BANKI; obraz = rozpakowanie w miejscu (emulacja 6502)
    rc = [b for b in pack_zone.RC_BANKI if b in banki]
    ciag = b"".join(bytes(banki[b]) for b in rc)
    banki_src, _ = pack_zone.obrazy_z_xex(sb)
    wzory = pack_zone.obrazy_ldr(man, banki_src)
    zle = []
    for n in man["ldr"]["ladowane"]:
        i = man["obrazy"][n]["id"]
        kb = ciag[i]
        adr = ciag[pack_zone.RC_NID + i] | ciag[2 * pack_zone.RC_NID + i] << 8
        dl = ciag[3 * pack_zone.RC_NID + i] | ciag[4 * pack_zone.RC_NID + i] << 8
        poz = kb * 0x4000 + adr - 0x4000
        plik = ciag[poz:poz + dl]
        len_u, delta, flagi = struct.unpack_from("<HBB", plik)
        z = plik[pack_zone.NAGLOWEK:]
        try:
            got = z if flagi & 1 else pack_test.dekompresja_6502(z, 0x4000, len_u, delta, True)
        except (ValueError, IndexError) as e:
            zle.append(f"{n}: {e}")
            continue
        if got != wzory[n]:
            zle.append(f"{n} (id {i})")
    print(f"RAMCART (banki {', '.join(str(b) for b in rc)}): {len(man['ldr']['ladowane'])} obrazów rozpakowanych w miejscu (6502) = obrazy "
          f"{src.name}: " + ("ZGODNE" if not zle else "RÓŻNE: " + "; ".join(zle)))
    wynik |= 1 if zle else 0
    # budżet: banki stałe + bank 36 (ekrany, jak XEX) + RAMCART; zestaw roboczy 320K z manifestu
    stale = {o["bank"] for o in man["obrazy"].values() if o["staly"]} | {36}
    obce = sorted(set(banki) - stale - set(pack_zone.RC_BANKI))
    print(f"budżet banków XEX nośnika: {len(banki)}/{MAX_BANKOW} (stałe + bank 36: {len(stale & set(banki))}, RAMCART: {len(rc)})"
          + ("" if not obce else f" – BŁĄD: banki spoza stałych i RAMCART {obce}"))
    wynik |= 1 if obce or len(banki) > MAX_BANKOW else 0
    return wynik


def main(argv: list[str]) -> int:
    xex = Path(argv[0]) if argv else ROOT / "build" / "game.xex"
    banki = banki_z_xex(xex.read_bytes())
    wynik = 0
    lst = xex.with_suffix(".lst")
    lab = lab_etykiety(xex.with_suffix(".lab"))
    media = lab.get("LDR_MEDIA", 0)
    if lst.is_file():
        zp = {lab[k] for k in ("ZP_FX", "ZP_SRC", "ZP_DST") if k in lab}   # M7.3: wskaźniki (zp),y dozwolone w obszarze ;@LDR
        if media == 3:                       # M7.4: ATR - obszar ;@LDR = kod fazy startu przed wgraniem obrazów kodu
            n, zle = skoki_ldr_atr(lst, lab)
            print(f"obszar ;@LDR (ATR, faza startu): {n} rozkazów, " + (
                "skoki tylko do części surowej / cracktro / xBIOS (;@XBIOS) / ROM (;@OS) / ;@KOD, dane z obrazu kodu tylko ;@KOD, bez $D5xx"
                if not zle else "BŁĘDY: " + "; ".join(zle)))
            wynik |= 1 if zle else 0
            n2, zle = osiagalnosc_atr(lst, lab)   # review M7.4: przepływ z ;@LDR przez całą część surową i segment $2000
            print(f"część surowa ATR: {n2} rozkazów osiągalnych z fazy startu - " + (
                "bez skoków i danych w obrazach kodu (poza ;@KOD)" if not zle else "BŁĘDY: " + "; ".join(zle[:12])))
        else:
            n, zle = skoki_ldr(lst, zp)
            print("obszar ;@LDR: " + ("brak (XEX - kod ldr bez źródła danych)" if n == 0 else
                                     f"{n} rozkazów, " + ("skoki tylko w obszarze (< $A000, poza oknem banków), $D5xx tylko sta abs, dane spod "
                                                          "cartu tylko ;@CART, (zp),y tylko zp_fx / zp_src / zp_dst" if not zle else
                                                          "BŁĘDY: " + "; ".join(zle))))
        wynik |= 1 if zle else 0
        if media and n == 0:
            print("BŁĄD: build nośnika bez obszaru ;@LDR (src/ldr/ldr.asm)", file=sys.stderr)
            wynik = 1
        if media in (1, 3):                  # M7.3: cart - żaden dostęp do $D5xx poza sta abs w ;@LDR (włączyłby AtariMax w czasie gry);
            n, zle = bramka_d5xx(lst)        # M7.4: ATR - to samo na całym listingu (w ;@LDR $D5xx i tak zabronione - skoki_ldr_atr)
            print(f"$D5xx w całym kodzie ({n} rozkazów z adresem abs): " + ("tylko sta abs w ;@LDR" if not zle else "BŁĘDY: " + "; ".join(zle)))
            wynik |= 1 if zle else 0
        zle = skoki_banku45(lst)
        print("bank 45: skoki z kodu obiektów " + ("tylko do banku 45 i $8000+" if not zle else
              "POZA bank 45 i kod rezydentny: " + "; ".join(zle)))
        wynik |= 1 if zle else 0
        zle = skoki_banku45(lst, "bz")
        print("bank 11 (obiekty strefy): skoki z kodu " + ("tylko do banku 11 i $8000+" if not zle else
              "POZA bank 11 i kod rezydentny: " + "; ".join(zle)))
        wynik |= 1 if zle else 0
        zle = skoki_banku45(lst, "bz2")
        print("bank 2 (obiekty strefy 2): skoki z kodu " + ("tylko do banku 2 i $8000+" if not zle else
              "POZA bank 2 i kod rezydentny: " + "; ".join(zle)))
        wynik |= 1 if zle else 0
        zle = skoki_banku45(lst, "bz3")
        print("bank 30 (obiekty strefy 3): skoki z kodu " + ("tylko do banku 30 i $8000+" if not zle else
              "POZA bank 30 i kod rezydentny: " + "; ".join(zle)))
        wynik |= 1 if zle else 0
    obj = (ROOT / "build" / "assets" / "bank_objdata.bin").read_bytes()
    b45 = banki.get(45)
    if b45 is None:
        print("BŁĄD: XEX nie ładuje banku 45")
        return 1
    zakresy = [(a, n) for a, n, _ in ex.OBJ_SPANS] + [(ex.OBJ_BOUNDS_ATARI, 8 * ex.OBJ_BOUNDS_UNIQ)]
    zle = [f"${a:04X}" for a, n in zakresy if b45[a - 0x4000:a - 0x4000 + n] != obj[a - 0x4000:a - 0x4000 + n]]
    print(f"bank 45: {len(zakresy)} zakresów danych obiektów " + ("ZGODNE" if not zle else f"RÓŻNE: {', '.join(zle)}"))
    wynik |= 1 if zle else 0
    if media == 2:
        # M7.2: build nośnika - banki 11 / 2 / 30 (obrazy slotów) w XEX-ie pierwszego przebiegu, RAMCART, budżet; dalej tylko bank 47
        nakl = {b: n for b, n in NAKLADANIA.items() if b != 45}  # przed bramka_nosnika (banki_z_xex pierwszego przebiegu zeruje NAKLADANIA)
        wynik |= bramka_nosnika(xex, banki)
        art = (ROOT / "build" / "assets" / "bank_objart.bin").read_bytes()
        n = ex.OBJART_BOSS3 + 0x1000
        ok = banki.get(47) is not None and banki[47][:n] == art[:n]
        print(f"bank 47: grafika obiektów ({n} B) " + ("ZGODNA" if ok else "RÓŻNA / brak"))
        wynik |= 0 if ok else 1
        print("banki z XEX: " + ", ".join(str(b) for b in sorted(banki)))
        if nakl:
            print("BŁĄD: nakładanie się segmentów w bankach: " + ", ".join(f"{b} ({n} B)" for b, n in sorted(nakl.items())), file=sys.stderr)
            wynik = 1
        wynik |= bramka_manifestu(set(), wydanie=False)          # tylko zestaw roboczy 320K z manifestu
        return wynik
    objz = (ROOT / "build" / "assets" / "bank_objz.bin").read_bytes()
    b11 = banki.get(11)
    if b11 is None:
        print("BŁĄD: XEX nie ładuje banku 11 (obiekty strefy)")
        return 1
    zle = [f"${a:04X}" for a, n, _ in ex.OBJZ_SPANS
           if b11[a - 0x8000:a - 0x8000 + n] != objz[a - 0x8000:a - 0x8000 + n]]
    print(f"bank 11: {len(ex.OBJZ_SPANS)} zakresów danych obiektów strefy " + ("ZGODNE" if not zle else f"RÓŻNE: {', '.join(zle)}"))
    wynik |= 1 if zle else 0
    objz2 = (ROOT / "build" / "assets" / "bank_objz2.bin").read_bytes()     # M6.9: drugi bank obiektow strefy (PB_OBJZ2)
    b2 = banki.get(2)
    if b2 is None:
        print("BŁĄD: XEX nie ładuje banku 2 (obiekty strefy 2)")
        return 1
    zle = [f"${a:04X}" for a, n, _ in ex.OBJZ2_SPANS
           if b2[a - 0x8000:a - 0x8000 + n] != objz2[a - 0x8000:a - 0x8000 + n]]
    print(f"bank 2: {len(ex.OBJZ2_SPANS)} zakresów danych obiektów strefy 2 " + ("ZGODNE" if not zle else f"RÓŻNE: {', '.join(zle)}"))
    wynik |= 1 if zle else 0
    objz3 = (ROOT / "build" / "assets" / "bank_objz3.bin").read_bytes()     # M6.10: trzeci bank obiektow strefy (PB_OBJZ3, Sky Base)
    b30 = banki.get(30)
    if b30 is None:
        print("BŁĄD: XEX nie ładuje banku 30 (obiekty strefy 3)")
        return 1
    zle = [f"${a:04X}" for a, n, _ in ex.OBJZ3_SPANS
           if b30[a - 0x8000:a - 0x8000 + n] != objz3[a - 0x8000:a - 0x8000 + n]]
    print(f"bank 30: {len(ex.OBJZ3_SPANS)} zakresów danych obiektów strefy 3 " + ("ZGODNE" if not zle else f"RÓŻNE: {', '.join(zle)}"))
    wynik |= 1 if zle else 0
    art = (ROOT / "build" / "assets" / "bank_objart.bin").read_bytes()
    n = ex.OBJART_BOSS3 + 0x1000
    b47 = banki.get(47)
    ok = b47 is not None and b47[:n] == art[:n]
    print(f"bank 47: grafika obiektów ({n} B) " + ("ZGODNA" if ok else "RÓŻNA / brak"))
    wynik |= 0 if ok else 1
    print("banki z XEX: " + ", ".join(str(b) for b in sorted(banki)))
    # M6.6: sufit XEX = 1088K (64 banki po 16 KB; docs/m7-nosniki.md) - bramka budzetu
    zle_b = [b for b in banki if not 0 <= b < MAX_BANKOW]
    # dwa segmenty INI do tego samego obszaru banku: późniejszy nadpisuje wcześniejszy. Banki 45 i 11 są warstwowe z założenia (obraz danych
    # z ROM-u z lukami, kod obiektów w lukach) - jego zakresy sprawdza kontrola wyżej
    nakl = {b: n for b, n in NAKLADANIA.items() if b not in (2, 11, 30, 45)}   # M6.10: 30 = PB_OBJZ3 (kod w lukach obrazu danych)
    if nakl:
        print("BŁĄD: nakładanie się segmentów w bankach: " + ", ".join(f"{b} ({n} B)" for b, n in sorted(nakl.items())), file=sys.stderr)
        wynik = 1
    print(f"budzet banków XEX: {len(banki)}/{MAX_BANKOW}" + (" – PRZEKROCZONY" if zle_b or len(banki) > MAX_BANKOW else ""))
    if zle_b or len(banki) > MAX_BANKOW:
        print(f"BŁĄD: banki poza 0-{MAX_BANKOW - 1}: {sorted(zle_b)}", file=sys.stderr)
        wynik = 1
    if media in (1, 3):                      # M7.3: kontener buildu cartu (M7.4: i ATR) - dokładnie obrazy nośnika (bez banku 36 - rozpuszczony w 41/43/59)
        man = json.loads((ROOT / "build" / "assets" / "manifest.json").read_text(encoding="utf-8"))
        nos = {man["obrazy"][n]["bank"] for n in man["nosnik"]["stale"] + man["ldr"]["ladowane"]}
        zle_n = sorted(set(banki) ^ nos)
        print(f"kontener {'cartu' if media == 1 else 'ATR'}: banki = obrazy nośnika ({len(nos)}: {len(man['nosnik']['stale'])} stałych + doczytywane)"
              + ("" if not zle_n else f" – BŁĄD: różnica {zle_n}"))
        wynik |= 1 if zle_n else 0
        return wynik | bramka_manifestu(set(banki), wydanie=False)
    wynik |= bramka_manifestu(set(banki), wydanie=49 in banki)   # wydanie = XEX z bankiem ekranów 49 (review M7.1: nie po nazwie pliku)
    return wynik


def bramka_manifestu(banki: set[int], wydanie: bool) -> int:
    """M7.1: każdy bank XEX-a ma obraz w manifeście (tools/manifest.py -> build/assets/manifest.json) - inaczej nośniki 320K go nie dostaną;
    zestaw roboczy 320K (obrazy stałe + sloty, docs/plan-m7.md §1.3) <= 16 banków nieparzystych 33-63."""
    p = ROOT / "build" / "assets" / "manifest.json"
    if not p.is_file():
        print("BŁĄD: brak build/assets/manifest.json (tools/manifest.py)", file=sys.stderr)
        return 1
    man = json.loads(p.read_text(encoding="utf-8"))
    w_man = {o["bank"] for o in man["obrazy"].values()}
    wynik = 0
    bez = sorted(banki - w_man)
    if bez:
        print(f"BŁĄD: banki XEX bez obrazu w manifeście: {bez}", file=sys.stderr)
        wynik = 1
    if wydanie and w_man - banki:
        print(f"BŁĄD: obrazy manifestu nieładowane przez XEX wydania: {sorted(w_man - banki)}", file=sys.stderr)
        wynik = 1
    stale = {o["bank"] for o in man["obrazy"].values() if o["staly"]}         # M7.3: bez obrazów tylko-XEX (bank 36)
    zestaw = stale | set(man["sloty"].values())
    ok = len(zestaw) <= 16 and len(zestaw) == len(stale) + len(man["sloty"]) and all(33 <= b <= 63 and b & 1 for b in zestaw)
    print(f"zestaw roboczy 320K (manifest): {len(zestaw)}/16 ({len(stale)} stałych + {len(man['sloty'])} slotów)"
          + ("" if ok else " – BŁĄD"))
    return wynik | (0 if ok else 1)


if __name__ == "__main__":
    for s in (sys.stdout, sys.stderr):
        try:
            s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main(sys.argv[1:]))
