#!/usr/bin/env python3
"""M6.5: banki etapow specjalnych po Green Hill ($1C, $1D) z wynikow extract_sms.py --level sp1 / sp2.

Bank 63 (PB_LEVELSP): dane poziomu w formacie banku poziomu (LB_*). Etapy $1C i $1D maja ten sam uklad 64 x 64, bloki,
palety i flagi - roznia sie tylko blokiem na poziom (LB_HDR..LB_OBJLIST: naglowek, czas, wskazniki, lista obiektow:
256 B od $2400). Bank niesie obie wersje bloku: $2500 (miejsce dema, nieuzywanego w etapach) = $1C, $3F00 = $1D;
lv_select (game_code.asm) kopiuje wybrany blok na $2400 przed wczytaniem poziomu. Obszar kulki testowej (LB_BALL = $2000,
1 KiB, ladowany do VRAM SPRITE_VRAM) niesie obraz okraglego zderzaka 32 x 32 (8 bpp: 16 + kolor, 0 = przezroczysty) -
render/sprites.asm: throb_obj.
Bank 61 (PB_ATLASSP): atlas kafli tla etapow specjalnych (256 kafli 8x8, 8 bpp; ten sam format co bank 33).
Wyjscie: build/assets/special/bank_level.bin, bank_atlas.bin.

Uzycie:  python tools/pack_special.py   (po extract_sms.py --level sp1, sp2 i sp3)
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
A = ROOT / "build" / "assets"
BLOCK = (0x2400, 0x2500)          # blok na poziom: LB_HDR .. LB_OBJLIST + 192 B
STASH = {0: 0x2500, 1: 0x3F00, 2: 0x3400,     # kopie bloku dla $1C, $1D, $1E (LB_DEMO, koniec banku, wolna strona $3400)
         3: 0x0800, 4: 0x0900, 5: 0x0A00}     # M6.11: $20, $21, $22 (tilemapa 128 blokow konczy sie na $07FF, $0800-$0BFF wolne)
BUMPER_TILES = [0x00, 0x02, 0x04, 0x06, 0x20, 0x22, 0x24, 0x26]   # SPRTAB_round_bumper_throbbing (01:526E): 2 x 4 sprite'y 8x16


def main() -> int:
    b1 = bytearray((A / "sp1" / "bank_level.bin").read_bytes())
    b2 = (A / "sp2" / "bank_level.bin").read_bytes()
    b3 = (A / "sp3" / "bank_level.bin").read_bytes()
    bx = [(A / n / "bank_level.bin").read_bytes() for n in ("sp5", "sp6", "sp7")]   # M6.11: etapy $20-$22
    at1 = (A / "sp1" / "bank_atlas.bin").read_bytes()
    at2 = (A / "sp2" / "bank_atlas.bin").read_bytes()
    at3 = (A / "sp3" / "bank_atlas.bin").read_bytes()
    if at1 != at2 or at1 != at3:
        print("BLAD: atlasy sp1, sp2 i sp3 sie roznia", file=sys.stderr)
        return 1
    # poza blokiem na poziom i kulka testowa bank musi byc wspolny (ta sama strefa)
    diff = [i for i in range(0x4000) if (b1[i] != b2[i] or b1[i] != b3[i] or any(b1[i] != b[i] for b in bx))
            and not (BLOCK[0] <= i < BLOCK[1])]   # (przed zapisem obrazu zderzaka i kopii bloku)
    if diff:
        print(f"BLAD: banki sp1 i sp2 roznia sie poza blokiem na poziom (pierwszy offset ${diff[0]:04X}, {len(diff)} B)",
              file=sys.stderr)
        return 1
    blocks = [bytes(b1[BLOCK[0]:BLOCK[1]]), bytes(b2[BLOCK[0]:BLOCK[1]]), bytes(b3[BLOCK[0]:BLOCK[1]])] + \
             [bytes(b[BLOCK[0]:BLOCK[1]]) for b in bx]
    # obraz zderzaka: sprite j = kolumna j & 3, wiersz j >> 2, kafle (t, t + 1) jeden nad drugim (kafle sprite'ow etapu z level.npz)
    tiles = np.load(A / "sp1" / "level.npz")["spr_tiles"]
    img = np.zeros((32, 32), np.uint8)
    for j, t in enumerate(BUMPER_TILES):
        col, row = j & 3, j >> 2
        spr = np.concatenate([tiles[t], tiles[t + 1]], axis=0)          # 16 x 8
        img[16 * row:16 * row + 16, 8 * col:8 * col + 8] = np.where(spr != 0, spr + 16, 0)
    b1[0x2000:0x2400] = img.tobytes()
    for k, blk in enumerate(blocks):
        if any(b1[STASH[k]:STASH[k] + 256]) and k > 0:        # review M6.6: kopia bloku nie moze nadpisac danych banku (np. profili kolizji LB_PHYS)
            print(f"BLAD: strona kopii bloku ${STASH[k]:04X} nie jest pusta", file=sys.stderr)
            return 1
        b1[STASH[k]:STASH[k] + 256] = blk
    b1[BLOCK[0]:BLOCK[1]] = blocks[0]                  # domyslnie $1C
    out = A / "special"
    out.mkdir(parents=True, exist_ok=True)
    (out / "bank_level.bin").write_bytes(bytes(b1))
    (out / "bank_atlas.bin").write_bytes(at1)
    # M6.11: bank 32 - etapy pionowe $1F / $23 (uklad 16 x 256, ta sama strefa flag i atlas co $1C): wspolny bank, bloki na poziom $1F w
    # $0800, $23 w $0900 (domyslnie $1F); lv_select kopiuje wlasciwy na $2400. Obraz zderzaka jak w banku 63 (LB_BALL)
    p4 = bytearray((A / "sp4" / "bank_level.bin").read_bytes())
    p8 = (A / "sp8" / "bank_level.bin").read_bytes()
    if (A / "sp4" / "bank_atlas.bin").read_bytes() != at1:
        print("BLAD: atlas etapu $1F rozny od atlasu etapow $1C-$1E", file=sys.stderr)
        return 1
    d2 = [i for i in range(0x4000) if p4[i] != p8[i] and not (BLOCK[0] <= i < BLOCK[1])]
    if d2:
        print(f"BLAD: banki sp4 i sp8 roznia sie poza blokiem na poziom (${d2[0]:04X}, {len(d2)} B)", file=sys.stderr)
        return 1
    p4[0x2000:0x2400] = b1[0x2000:0x2400]
    for adr, src in ((0x0800, p4), (0x0900, p8)):
        if any(p4[adr:adr + 256]):
            print(f"BLAD: strona kopii bloku ${adr:04X} banku 32 nie jest pusta", file=sys.stderr)
            return 1
    blk4, blk8 = bytes(p4[BLOCK[0]:BLOCK[1]]), bytes(p8[BLOCK[0]:BLOCK[1]])
    p4[0x0800:0x0900] = blk4
    p4[0x0900:0x0A00] = blk8
    (A / "special2").mkdir(parents=True, exist_ok=True)
    (A / "special2" / "bank_level.bin").write_bytes(bytes(p4))
    print(f"etapy pionowe $1F/$23: bank 32 (bloki na poziom w $0800/$0900) -> {A / 'special2'}")
    print(f"etapy specjalne: bank poziomu (bloki na poziom $1C/$1D/$1E w $2500/$3F00/$3400, $20/$21/$22 w $0800/$0900/$0A00, domyslnie $2400; "
          f"obraz zderzaka w $2000) i atlas -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
