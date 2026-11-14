#!/usr/bin/env python3
"""Format trace'u M3 (stan gry SMS po każdym kroku pętli poziomu) i skryptu wejść – wspólny dla referencji i portu.

Trace (.m3t, little endian):
  nagłówek 64 B: "M3TR", u16 wersja (1), u16 rozmiar nagłówka (64), u16 rozmiar rekordu, u16 baza RAM ($C000),
                 u16 długość RAM ($2000), u16 flagi (bit 0 = demo, bit 1 = PAL, bit 2 = bez obiektów: sloty 1–31
                 puste od załadowania poziomu, bit 3 = filtr typów obiektów M4), 16 B źródło (ASCII), 32 B rezerwy
  rekord (16 B + RAM):
    i32 krok     -16 = stan po załadowaniu poziomu, -15..0 = po klatkach rozgrzewki, 1.. = po tickach pętli
    u16 irq      przerwania od poprzedniego rekordu (1 = bez opóźnienia, 2+ = tick dłuższy niż ramka)
    u8  wejście  g_inputs_player_1 przy wejściu do objfunc_00_sonic w tym kroku
    u8  zamiar   g_inputs_player_1 po obsłudze dema (load_and_run_level@skip_demo_playback), $FF w rozgrzewce
    u8  flagi    bit 0 = Sonic uruchomiony, bit 1 = IRQ między zamiarem a Sonikiem (wejście z portu),
                 bit 2 = krok rozgrzewki, bit 3 = tryb demo
    7 B rezerwy
    RAM $C000–$DFFF (8 KiB: układ poziomu $C000–$CFFF, zmienne gry $D000–$DFFF)

Skrypt wejść (.m3in, tekst): wiersze `<liczba ticków> <wejście>`, `#` = komentarz. Wejście: `-` (nic),
złożenie liter U D L R 1 2 (góra, dół, lewo, prawo, przycisk 1, przycisk 2) albo `$XX` (bajt wprost).
Bajt jak g_inputs_player_1 po IRQ: bity aktywne zerem, b0 U, b1 D, b2 L, b3 R, b4 = 1, b5 = 1 lub 2
(IRQ gry zeruje b5 przy wciśniętym 1), b6–b7 = 1. Wiersze obejmują kolejne ticki od 1.

Nazwy pól RAM pochodzą z tabeli niżej, a pozostałe – opcjonalnie z adnotacji lokalnej dezasemblacji
(assets/ref/s1smsdisasm-gm/annot/sonic1.cfg, tylko odczyt; plik nie jest częścią repozytorium).
"""
from __future__ import annotations

import re
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
ANNOT = ROOT / "assets" / "ref" / "s1smsdisasm-gm" / "annot" / "sonic1.cfg"

MAGIC = b"M3TR"
VERSION = 1
HEADER_SIZE = 64
RAM_BASE = 0xC000
RAM_LEN = 0x2000
REC_DTYPE = np.dtype([("krok", "<i4"), ("irq", "<u2"), ("wejscie", "u1"), ("zamiar", "u1"), ("flagi", "u1"),
                      ("rez", "u1", (7,)), ("ram", "u1", (RAM_LEN,))])
REC_SIZE = REC_DTYPE.itemsize

F_SONIC, F_IRQ_PRZED_SONIKIEM, F_ROZGRZEWKA, F_DEMO = 1, 2, 4, 8
# pliki wywołań (<nazwa>-rfo.m3t, m3_ref.py --wywolania): pary rekordów RAM przed/po wywołaniu procedury,
# bajty rezerwy 0-1 = IX (adres SMS rekordu obiektu)
F_PRZED, F_PO = 0x10, 0x20
H_DEMO, H_PAL, H_BEZ_OBIEKTOW = 1, 2, 4
H_FILTR = 8                     # M4: --obiekty - w slotach 1-31 zostały tylko wybrane typy (reszta $FF)

SONIC = 0xD3FC                  # object_list – rekord Sonica (26 B)
SONIC_POLA = ["typ", "x.sub", "x.lo", "x.hi", "y.sub", "y.lo", "y.hi", "vx.sub", "vx.lo", "vx.hi",
              "vy.sub", "vy.lo", "vy.hi", "szer", "wys", "sprite.lo", "sprite.hi", "anim.lo", "anim.hi",
              "anim.klatka", "anim.indeks", "speed_shoes", "dzwiek_ham", "+23", "flagi", "+25"]

# grupy porównania: nazwa -> lista zakresów adresów SMS [od, do)
GRUPY = {
    "sonic": [(SONIC, SONIC + 26)],
    "kamera": [(0xD257, 0xD25F)],          # g_level_scroll_tile_x/y, g_level_scroll_x_*, g_level_scroll_y_*
    "pierscienie": [(0xD2AA, 0xD2AB)],     # g_rings_BCD
    # M3.5: animacja kafli pierścienia, łata ekranu po zebraniu (bajt x_hi = $FF po IRQ), licznik
    "pierscienie_m35": [(0xD293, 0xD299), (0xD2AA, 0xD2B1)],
    "flagi": [(0xD200, 0xD20E)],           # iy_00..iy_0D (w tym g_inputs_player_1)
    "tmp": [(0xD20E, 0xD218)],             # tmp_00..tmp_09
    "uklad": [(0xC000, 0xD000)],           # g_level_layout
    "zmienne": [(0xD000, 0xE000)],
    "ram": [(0xC000, 0xE000)],
    # stan zmieniany co przerwanie (nie co tick) i kopie dla VDP – do pomijania przy porównaniu z portem
    "rng": [(0xD2D7, 0xD2D9)],             # g_random_seed (random_A w każdym IRQ)
    "dzwiek": [(0xDC00, 0xDD10)],          # RAM sterownika dźwięku (snddrv_update w IRQ)
    "vdp": [(0xD000, 0xD0C0), (0xD100, 0xD200)],   # g_sprite_table, tablice przewijania kafli VDP
    "stos": [(0xDF00, 0xE000)],            # stos Z80 (IRQ w środku ticku zostawia tam inne rejestry)
}

WLASNE_NAZWY = {SONIC + i: f"sonic.{n}" for i, n in enumerate(SONIC_POLA)}

# --- trace z portu (src/game/trace.asm, format v2 od M4.0): rekordy o zmiennej długości w bankach Atari
# z listy PORT_BANKI (kolejno), w banku od $4000; gdy do końca banku zostaje < PORT_MAXREC, następny bank
# (bajt +6 = 0 zamiast znacznika = koniec rekordów w banku):
#   nagłówek 10 B: i16 krok, u8 irq, u8 wejście, u8 zamiar, u8 flagi, u8 znacznik $A5, u8 segment, u16 długość
#   blok A (pola PORT_POLA, PORT_NA B) i blok B (g_object_ptrs, 64 B): u8 n, potem n par (indeks, wartość) –
#     zmienione bajty względem poprzedniego rekordu; n = $FF – cały blok (klatka kluczowa)
#   u32 maska slotów (bit s = slot s, 1..31) i 26 B każdego zaznaczonego slotu (rosnąco); slot niezaznaczony
#     ma stan z poprzedniego rekordu (port zaznacza sloty aktywne, uruchomione i utworzone w kroku)
#   u8 liczba wpisów tablicy sprite'ów (g_sprite_count, max 64), wpisy 21..liczba-1 po 3 B
# Klatka kluczowa (bloki w całości, wszystkie sloty): krok -16 każdego segmentu i co 64 rekordy.
PORT_HDR = 10
PORT_ZNACZNIK = 0xA5
PORT_MAXREC = 0x600              # najdłuższy możliwy rekord (z zapasem) - miejsce sprawdzane przed zapisem
PORT_RAW = 0xFF
SEG_KROK = 100000                # M3.7: kroki segmentu k (k-ty start poziomu) = krok + k * SEG_KROK (jak m3_ref.lua)
PORT_POLA = [(0xD200, 14),      # iy_00..iy_0D (w tym g_sprite_count $D20A)
             (0xD216, 2),       # tmp_08..tmp_09 (grupa start)
             (0xD2D2, 1),       # M5: g_current_music (rst $18)
             (0xD2FC, 1),       # M5: g_level_music
             (0xDBFF, 1),       # M5.4: efekt zgłoszony w ticku (rst $28; referencja: m3_ref.lua, port: play_sfx)
             (0xD223, 2),       # g_global_tick_counter
             (0xD246, 1),       # g_lives
             (0xD257, 8),       # kamera: kafel x/y, scroll x/y (sub, lo, hi)
             (0xD25F, 16),      # g_camera_sonic_bounds_*
             (0xD26F, 4),       # g_displayed_level_scroll_*
             (0xD273, 12),      # granice poziomu, blokady kamery
             (0xD287, 1),       # g_level_restart_countdown_timer
             (0xD2BE, 5),       # M3.7c: g_HUD_FFstr_buf (ostatni tekst HUD-u; cyklu palety $D2A4 port nie liczy)
             (0xD283, 1),       # M3.7: g_sonic_died_at_least_once
             (0xD293, 6),       # M3.5: g_new/old_ring_tiles_ptr, g_ring_tile_index, g_ring_tile_subtimer_index
             (0xD2AA, 7),       # g_rings_BCD, M3.5: g_screen_tile_replace_x/y, _data_ptr (łata ekranu)
             (0xD2B5, 4),       # g_demo_next_input_relptr, g_camera_y_look_up_offset_px
             (0xD2CE, 3),       # czas
             (SONIC, 26),       # rekord Sonica
             # M4.0: stan zmieniany przez obiekty
             (0xD20E, 8),       # tmp_00..tmp_07 (aktywacja zostawia w tmp_00..05 granice ostatniego typu)
             (0xD23C, 2),       # g_next_avail_vdp_sprite_ptr
             (0xD27F, 4),       # szmaragdy, życia z monitorów, etapy specjalne (próby, ukończone)
             (0xD284, 3),       # kontynuacje, mnożnik premii etapu specjalnego
             (0xD288, 7),       # tabliczka (g_current_signpost, odliczanie), teleport, muzyka szmaragdu,
                                # tłumienie kierunków, nieśmiertelność, skok
             (0xD2B1, 4),       # błysk palety (licznik, indeks, kolor), M4.1: g_prev_sprite_count (IRQ)
             (0xD2BA, 4),       # wynik BCD (big endian)
             (0xD2D7, 2),       # g_random_seed
             (0xD2DE, 1),       # g_frontmost_sprite_table_offs
             (0xD2E6, 3),       # g_sonic_bounce_vel_y (sub, lo, hi)
             (0xD2F2, 1),       # g_object_count
             (0xD2F3, 8),       # pozycje iskier nieśmiertelności
             (0xD2FD, 1),       # g_next_life_bonus_10000s_BCD
             (0xD302, 1),       # g_sonic_sprite_index_override
             (0xD305, 24),      # maski poziomów: życie (D305), szmaragd (D30B), punkt kontrolny (D311), przycisk (D317)
             (0xD31D, 5),       # iskra pierścienia (x, y, licznik)
             (0xD32E, 6),       # g_per_level_checkpoint_positions: GHZ1-3
             # M6.8: woda (Labyrinth)
             (0xD29B, 2),       # g_sonic_underwater_countup_timer
             (0xD2DB, 3),       # g_water_level_onscreen_y, g_water_level_y
             (0xD2FB, 1),       # g_sonic_consume_air_bubble_countdown_timer
             # M6.9: teleporty i pod-poziomy (Scrap Brain)
             (0xD2D3, 1),       # g_next_level_override_target
             (0xD2D5, 2),       # g_teleport_spec_dest_ptr
             # M6.10: Sky Base
             (0xD2E9, 2),       # g_lightning_timer (SKY1; palety cyklu $D2A4 port liczy w NMI - poza porownaniem)
             (0xD2FE, 1),       # M6.11: g_good_ending_emerald_anim_countdown_timer (Sonic przy szmaragdzie $54)
             (0xD000, 36)]      # review M6.10: przednie wpisy 0-11 tablicy sprite'ow (chmury SKY2 - m3_test porownaj_przednie)
PORT_NA = sum(n for _, n in PORT_POLA)
PORT_PTRS = (0xD37C, 64)         # blok B: g_object_ptrs
SLOTY = 0xD416                   # object_list_past_sonic: sloty 1..31 (31 x 26 B)
SPRITE_TAB = 0xD000              # g_sprite_table: 64 x 3 B (x, y, kafel)
SPRITE_LICZNIK = 0xD20A          # g_sprite_count
# banki trace'u (indeks w tablicy = kolejność): bez banków danych z XEX (33-47 nieparzyste) i skryptu (34)
BANKI_BRIDGE = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32)   # M6.11: 32 = etapy pionowe $1F/$23; M6.10: 18-28 parzyste = Sky Base, 30 = trzeci bank obiektow strefy (PB_OBJZ3); M6.9: 2 = drugi bank obiektow strefy (PB_OBJZ2), 4-16 parzyste = Scrap Brain (bufor trace'u: 26 bankow); M6.6: atlas, sprite'y strefy, poziomy BRI1-3 (src/kernel/mem.inc PB_*B*) i bank obiektow strefy (11, PB_OBJZ) - nie dla trace'u; M6.7: Jungle 13-21; M6.8: Labyrinth 23-31
# M6.9: banki danych stref (XEX laduje wszystkie); test w strefie innej niz dana moze je nadpisac buforem trace'u (banki_trace)
BANKI_STREF = {"bri": (1, 3, 5, 7, 9, 11), "jun": (13, 15, 17, 19, 21, 11), "lab": (23, 25, 27, 29, 31, 11),
               "sbz": (2, 4, 6, 8, 10, 12, 14, 16), "sky": (18, 20, 22, 24, 26, 28, 30), "ss48": (32, 30),
               "koniec": (30,)}         # review M6.11: poziom $12 - kontroler $53 i szmaragd $54 w banku 30
TR_BANKMAX = 56                 # wpisy tr_bank_tab w porcie (PORT_BANKI + wolne banki stref)
# bank 36 - w wydaniu dane tytulu, mapy 1 i konca gry (M6.11); trace dziala tylko w budowie testowej (game.xex - bez banku 36)
PORT_BANKI = [b for b in range(0, 33) if b not in BANKI_BRIDGE] + [36, 38, 40, 42, 44, 46] + [b for b in range(48, 64) if b not in (55, 57, 59, 61, 63)]   # 55, 57 = poziomy GHZ2, GHZ3, 59 = grafika bossa, 61, 63 = etapy specjalne (M6.3-M6.5)


def strefa_poziomu(poziom: int) -> str | None:
    """M6.9: strefa z bankami danych dla g_level / naglowka (None - GHZ i etapy specjalne: banki wspolne)."""
    if 3 <= poziom <= 5:
        return "bri"
    if 6 <= poziom <= 8:
        return "jun"
    if 9 <= poziom <= 11:
        return "lab"
    if 12 <= poziom <= 14 or poziom in (0x14, 0x15, 0x16, 0x17, 0x18, 0x19):
        return "sbz"
    if 15 <= poziom <= 17 or poziom == 0x1A:     # M6.10: Sky Base i pod-poziom $1A
        return "sky"
    if poziom in (0x1F, 0x23):                   # M6.11: etapy pionowe (bank 32, obiekty w banku 30)
        return "ss48"
    if 0x1C <= poziom <= 0x22:                   # M6.11: etapy $1C-$22 - obiekty ($21) w banku 30
        return "ss48"
    if poziom == 0x12:                           # review M6.11: poziom koncowy (dane GHZ1 z XEX, obiekty w banku 30)
        return "koniec"
    return None


def banki_trace(poziom: int) -> list[int]:
    """M6.9: banki bufora trace'u testu na poziomie poziom: PORT_BANKI + banki stref, ktorych ten poziom nie uzywa (dane z XEX
    nadpisywane w tescie - scenariusze m3 nie zmieniaja strefy; przejscia miedzy strefami sprawdzaja testy ekranow)."""
    wlasne = set(BANKI_STREF.get(strefa_poziomu(poziom), ()))
    wolne = sorted({b for s in BANKI_STREF.values() for b in s} - wlasne)
    out = PORT_BANKI + wolne
    return out[:TR_BANKMAX]


def atari_adr(sms: int) -> int:
    """Adres SMS -> adres w porcie: układ $C000-$CFFF -> $1000-$1FFF, RAM $D000-$DFFF -> lustro $E000-$EFFF."""
    if 0xC000 <= sms < 0xD000:
        return sms - 0xB000
    if 0xD000 <= sms < 0xE000:
        return sms + 0x1000
    raise ValueError(f"adres SMS ${sms:04X} poza RAM-em gry")


def poke_atdbg(L: dict[str, int], pokes: list[str], czesc: int | None = None) -> list[str]:
    """Wymuszenia stanu w porcie jak m3_ref.py --poke ('krok:ADR=WART,...', adresy SMS hex): punkt TICK_GO
    (src/game/step.asm, po odczycie wejścia w kroku v_step) - linie skryptu debuggera Altirry. czesc: tylko przy
    boot_part == czesc (M6.5: poziom i etap specjalny w jednym przebiegu ekranów, wydanie)."""
    out = []
    warunek = f' and db(${L["BOOT_PART"]:04X})={czesc}' if czesc is not None else ""
    for opis in pokes:
        krok, _, zapisy = opis.partition(":")
        seg, _, krok = krok.rpartition("/")    # M6.9: 'S/K:...' - tylko w segmencie S (od 1): v_segment = S - 1
        w_seg = f' and db(${L["V_SEGMENT"]:04X})={int(seg) - 1}' if seg else ""
        eb = []
        maska = [0, 0, 0, 0]     # M4.3: wymuszony slot obiektu 1-31 oznaczony w v_obj_dirty (trace v2 zapisze go
        for z in zapisy.split(","):  # w tym kroku; w TICK_GO, przed funkcjami obiektów, maska kroku jest jeszcze 0)
            adr, _, w = z.partition("=")
            eb.append(f"eb ${atari_adr(int(adr, 16)):04X} ${int(w, 16) & 0xFF:02X}")
            s = (int(adr, 16) - SONIC) // 26
            if SLOTY <= int(adr, 16) < SLOTY + 31 * 26 and "V_OBJ_DIRTY" in L:
                maska[s >> 3] |= 1 << (s & 7)
        eb += [f"eb ${L['V_OBJ_DIRTY'] + i:04X} ${m:02X}" for i, m in enumerate(maska) if m]
        out.append(f'bx "pc=${L["TICK_GO"]:04X} and dw(${L["V_STEP"]:04X})=${int(krok) & 0xFFFF:X}{warunek}{w_seg}" '
                   f'"{"; ".join(eb)}; g"')
    return out


def portb_banku(n: int) -> int:
    """PORTB banku n jak select_bank (src/kernel/hw.asm): bity 1-3 = n & 7, bity 5-7 = n >> 3, OS off.
    Debugger Altirry adresuje bank jako $PB'4000 (x: ma inne mapowanie: bank 36 = x:$74000)."""
    return (n & 7) << 1 | (n & 0x38) << 2
GRUPY["port"] = [(a, a + n) for a, n in PORT_POLA]
# M4.0: sloty obiektów 1-31 i wskaźniki aktywnych obiektów
GRUPY["sloty"] = [(SLOTY, SLOTY + 31 * 26)]
GRUPY["wskazniki"] = [(PORT_PTRS[0], PORT_PTRS[0] + PORT_PTRS[1])]
# stan ustawiany przez start poziomu w porcie (game_reset + level_init) - porównanie w kroku -16
GRUPY["start"] = [(0xD202, 0xD20E), (0xD216, 0xD218), (0xD223, 0xD225), (0xD22B, 0xD22D), (0xD22F, 0xD230),
                  (0xD238, 0xD23C), (0xD23E, 0xD240), (0xD246, 0xD249), (0xD24F, 0xD253), (0xD257, 0xD27F),
                  (0xD27F, 0xD287), (0xD287, 0xD2AC), (0xD2B5, 0xD2B9), (0xD2BA, 0xD2BE), (0xD2CE, 0xD2D1),
                  (0xD2D4, 0xD2D5), (0xD2DC, 0xD2DE), (0xD2F2, 0xD2F3), (0xD2FD, 0xD2FE), (0xD354, 0xD3BC),
                  (SONIC, SONIC + 26), (0xC000, 0xD000)]


class Trace:
    """Trace .m3t wczytany przez numpy.memmap; `rek` – tablica rekordów, `ram(k)` – RAM SMS kroku k."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        head = self.path.read_bytes()[:HEADER_SIZE]
        magic, ver, hsize, rsize, base, length, flags, src = struct.unpack("<4sHHHHHH16s", head[:32])
        if magic != MAGIC or ver != VERSION or hsize != HEADER_SIZE or rsize != REC_SIZE:
            raise ValueError(f"{self.path}: nieobsługiwany nagłówek trace'u ({magic!r} v{ver}, rekord {rsize} B)")
        if base != RAM_BASE or length != RAM_LEN:
            raise ValueError(f"{self.path}: RAM {base:04X}+{length:X}, oczekiwano {RAM_BASE:04X}+{RAM_LEN:X}")
        self.flagi = flags
        self.zrodlo = src.rstrip(b"\0").decode("ascii", "replace")
        n = (self.path.stat().st_size - HEADER_SIZE) // REC_SIZE
        self.rek = np.memmap(self.path, REC_DTYPE, "r", HEADER_SIZE, (n,))
        self.kroki = self.rek["krok"]
        self._idx = {int(k): i for i, k in enumerate(self.kroki)}

    def __len__(self) -> int:
        return len(self.rek)

    def indeks(self, krok: int) -> int | None:
        return self._idx.get(krok)

    def ram(self, i: int) -> np.ndarray:
        return self.rek["ram"][i]

    def ix(self, i: int) -> int:
        """Adres SMS rekordu obiektu (tylko pliki wywołań)."""
        r = self.rek["rez"][i]
        return int(r[0]) | int(r[1]) << 8


def zapisz_naglowek(f, flagi: int, zrodlo: str) -> None:
    f.write(struct.pack("<4sHHHHHH16s", MAGIC, VERSION, HEADER_SIZE, REC_SIZE, RAM_BASE, RAM_LEN, flagi,
                        zrodlo.encode("ascii")[:16]) + bytes(32))


def bajt_wejscia(tekst: str) -> int:
    t = tekst.strip().upper()
    if t.startswith("$"):
        return int(t[1:], 16) & 0xFF
    v = 0xFF
    if t == "-":
        return v
    bity = {"U": 0x01, "D": 0x02, "L": 0x04, "R": 0x08, "1": 0x30, "2": 0x20}
    for c in t:
        if c not in bity:
            raise ValueError(f"nieznany znak wejścia {c!r} w {tekst!r}")
        v &= ~bity[c] & 0xFF
    return v


def wczytaj_skrypt(path: str | Path) -> list[int]:
    """Skrypt wejść -> lista bajtów g_inputs_player_1 dla ticków 1, 2, …"""
    wynik: list[int] = []
    for nr, wiersz in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        wiersz = wiersz.split("#", 1)[0].strip()
        if not wiersz:
            continue
        czesci = wiersz.split()
        if len(czesci) != 2 or not czesci[0].isdigit():
            raise ValueError(f"{path}:{nr}: oczekiwano `<liczba ticków> <wejście>`")
        wynik += [bajt_wejscia(czesci[1])] * int(czesci[0])
    return wynik


def opis_wejscia(v: int) -> str:
    s = "".join(c for c, b in (("U", 0x01), ("D", 0x02), ("L", 0x04), ("R", 0x08)) if not v & b)
    if not v & 0x10:
        s += "1"
    elif not v & 0x20:
        s += "2"
    return s or "-"


_etykiety: dict[int, tuple[str, int]] | None = None


def etykiety() -> dict[int, tuple[str, int]]:
    """Adres -> (nazwa, rozmiar) z adnotacji dezasemblacji (jeśli jest lokalnie), uzupełnione o własne nazwy."""
    global _etykiety
    if _etykiety is None:
        _etykiety = {}
        if ANNOT.is_file():
            rx = re.compile(r"^\s*(label|arraylabel)\s+F0:([0-9A-F]{4})\s+(byte|word)\s+(?:(\d+)\s+)?(\S+)", re.I)
            for wiersz in ANNOT.read_text(encoding="utf-8", errors="replace").splitlines():
                m = rx.match(wiersz)
                if m:
                    rozmiar = (2 if m[3].lower() == "word" else 1) * int(m[4] or 1)
                    _etykiety[int(m[2], 16)] = (m[5], rozmiar)
    return _etykiety


def nazwa(adres: int) -> str:
    if adres in WLASNE_NAZWY:
        return WLASNE_NAZWY[adres]
    et = etykiety()
    for a in range(adres, max(adres - 4096, 0xC000) - 1, -1):
        if a in et:
            n, r = et[a]
            if adres < a + r:
                return n if a == adres else f"{n}+{adres - a}"
            break
    return f"${adres:04X}"


def sonic(ram: np.ndarray) -> dict[str, float]:
    """Pozycja (px) i prędkość (px/tick) Sonica z rekordu object_list (24 bity: sub, lo, hi)."""
    r = ram[SONIC - RAM_BASE:SONIC - RAM_BASE + 26].astype(int)

    def u24(i: int) -> int:
        return r[i] | r[i + 1] << 8 | r[i + 2] << 16

    def s24(i: int) -> int:
        v = u24(i)
        return v - (1 << 24) if v & 0x800000 else v

    return {"x": u24(1) / 256, "y": u24(4) / 256, "vx": s24(7) / 256, "vy": s24(10) / 256, "flagi": int(r[24])}


def kamera(ram: np.ndarray) -> tuple[int, int]:
    o = 0xD25A - RAM_BASE
    return int(ram[o]) | int(ram[o + 1]) << 8, int(ram[o + 3]) | int(ram[o + 4]) << 8


def zapisz_inc(path: str | Path) -> None:
    """Tabele trace'u portu dla MADS (src/game/trace.asm): pola bloku A (adresy w lustrze RAM SMS, game/sms.inc),
    banki bufora, stałe formatu."""
    if PORT_NA > 254:
        raise ValueError(f"blok A ma {PORT_NA} B (najwyżej 254: licznik par i $FF = cały blok)")
    adr = ", ".join(f"${a:04X}+SMS_RAM" for a, _ in PORT_POLA)
    txt = (f"; wygenerowane przez tools/m3_trace.py --inc - nie edytowac (format: tools/m3_trace.py, PORT_*)\n"
           f"TR_HDR       = {PORT_HDR}\nTR_MARK      = ${PORT_ZNACZNIK:02X}\nTR_MAXREC    = ${PORT_MAXREC:04X}\n"
           f"TR_NFIELDS   = {len(PORT_POLA)}\nTR_NA        = {PORT_NA}\nTR_NBANKS    = {len(PORT_BANKI)}\n"
           f"tr_field_lo  dta l({adr})\ntr_field_hi  dta h({adr})\n"
           f"tr_field_len dta b({', '.join(str(n) for _, n in PORT_POLA)})\n"
           f"tr_bank_tab  dta b({', '.join(str(b) for b in PORT_BANKI + [0] * (TR_BANKMAX - len(PORT_BANKI)))})   ; M6.9: zapas na wolne banki stref\n")
    Path(path).write_text(txt, encoding="ascii")


def rekordy_portu(banki: list[bytes]) -> list[tuple[int, bytes]]:
    """Zrzuty banków trace'u (w kolejności PORT_BANKI) -> lista (krok z segmentem, surowy rekord) do pierwszego
    rekordu niepoprawnego albo nieciągłego (koniec trace'u)."""
    wynik = []
    oczekiwany = None
    seg0 = None
    for nb, bank in enumerate(banki):
        p = 0
        pierwszy = True
        while p + PORT_HDR <= len(bank):
            r = bank[p:p + PORT_HDR]
            if r[6] != PORT_ZNACZNIK:
                break                                 # koniec rekordów w banku
            krok_lok = struct.unpack_from("<h", r)[0]
            dl = struct.unpack_from("<H", r, 8)[0]
            # M3.7: bajt 7 = segment (start poziomu: kolejne życie / nowa gra) -> krok + SEG_KROK * segment
            nowy_seg = seg0 is not None and r[7] == seg0 + 1 and krok_lok == -16
            if (oczekiwany is not None and krok_lok != oczekiwany and not nowy_seg) or dl < PORT_HDR \
                    or p + dl > len(bank):
                return wynik
            seg0 = r[7]
            oczekiwany = krok_lok + 1
            wynik.append((krok_lok + SEG_KROK * r[7], bank[p:p + dl]))
            p += dl
            pierwszy = False
        if pierwszy:
            break                                     # bank bez rekordów: koniec trace'u
    return wynik


def _blok(r: bytes, p: int, stan: bytearray) -> int:
    """Blok różnicowy (A albo B) od pozycji p rekordu: aktualizuje stan, zwraca pozycję za blokiem."""
    n = r[p]
    p += 1
    if n == PORT_RAW:
        stan[:] = r[p:p + len(stan)]
        return p + len(stan)
    for i in range(n):
        stan[r[p + 2 * i]] = r[p + 2 * i + 1]
    return p + 2 * n


def z_portu(banki: list[bytes], wyjscie: str | Path, flagi: int, zrodlo: str = "atari-game",
            lustro: bytes | None = None, uklad: bytes | None = None) -> int:
    """Zrzuty banków trace'u portu (format v2) -> .m3t. RAM rekordu: pola PORT_POLA, g_object_ptrs, sloty 1-31
    (niezapisane w rekordzie - stan z poprzedniego), wpisy 21..liczba-1 tablicy sprite'ów; reszta 0.
    Opcjonalnie pełne zrzuty lustra ($D000-$DFFF) i układu ($C000-$CFFF) z chwili kroku -16 w pierwszym rekordzie."""
    stan_a = bytearray(PORT_NA)
    stan_b = bytearray(PORT_PTRS[1])
    sloty = bytearray(31 * 26)
    rek = []
    for krok, r in rekordy_portu(banki):
        p = _blok(r, PORT_HDR, stan_a)
        p = _blok(r, p, stan_b)
        maska = struct.unpack_from("<I", r, p)[0]
        p += 4
        for s in range(1, 32):
            if maska >> s & 1:
                sloty[(s - 1) * 26:s * 26] = r[p:p + 26]
                p += 26
        nspr = r[p]
        p += 1
        wpisy = r[p:p + max(0, nspr - 21) * 3]
        p += len(wpisy)
        if p != len(r):
            raise ValueError(f"trace portu: krok {krok} - długość rekordu {len(r)}, odczytano {p}")
        ram = bytearray(RAM_LEN)
        if not rek and krok == -16:
            if uklad is not None:
                ram[0:0x1000] = uklad[:0x1000]
            if lustro is not None:
                ram[0x1000:0x2000] = lustro[:0x1000]
        q = 0
        for a, n in PORT_POLA:
            ram[a - RAM_BASE:a - RAM_BASE + n] = stan_a[q:q + n]
            q += n
        a, n = PORT_PTRS
        ram[a - RAM_BASE:a - RAM_BASE + n] = stan_b
        ram[SLOTY - RAM_BASE:SLOTY - RAM_BASE + len(sloty)] = sloty
        o = SPRITE_TAB + 21 * 3 - RAM_BASE
        ram[o:o + len(wpisy)] = wpisy
        rek.append(struct.pack("<iHBBB", krok, r[2], r[3], r[4], r[5]) + bytes(7) + bytes(ram))
    with open(wyjscie, "wb") as f:
        zapisz_naglowek(f, flagi, zrodlo)
        f.write(b"".join(rek))
    return len(rek)


if __name__ == "__main__":
    import argparse
    import sys
    ap = argparse.ArgumentParser(description="Format trace'u M3: generacja tabeli pól portu dla MADS")
    ap.add_argument("--inc", required=True, help="plik wyjściowy .inc (np. build/assets/m3_trace.inc)")
    a = ap.parse_args()
    zapisz_inc(a.inc)
    print(f"OK: {a.inc}")
    sys.exit(0)
