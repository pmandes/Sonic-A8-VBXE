# Credits

## Original game

**Sonic The Hedgehog** (Sega Master System) © SEGA 1991. Sonic The Hedgehog, its characters, graphics, music and sound
effects are the property of SEGA. This port is a non-commercial fan project, not affiliated with or endorsed by SEGA.

## Port

- **Sonic A8 VBXE** – Atari XL/XE + VBXE port by **madness77**. The Z80 game code was translated into 6502
  assembly with the help of AI.
- Reference: **Disassembly of Sonic The Hedgehog for the Sega Master System** by **GreaseMonkey** (used as a reference
  for the original game code; not included in this repository).

## Music and sound

| What | Who |
|---|---|
| Compositions | Masato Nakamura, Yuzo Koshiro |
| C64 SID arrangement | Encore (Mikkel Hastrup) – "Sonic the Hedgehog V1.2", Mr. SID, 2021 ([CSDb 212523](https://csdb.dk/release/?id=212523)) |
| SID → POKEY (SAP-R) conversion | `sid2sapr` / saprtools by Ivo van Poorten – BSD 2-Clause ([licenses/sid2sapr-BSD-2-Clause.txt](licenses/sid2sapr-BSD-2-Clause.txt)) |
| LZSS SAP-R compressor and player format | `lzss-sap` by Daniel Serpell (DMSC) – MIT ([licenses/LICENSE-DMSC.txt](licenses/LICENSE-DMSC.txt)) |
| Sound effects | Converted at build time from the original Master System sound effects |

The music in `music/` is the result of the SID → SAP-R conversion (POKEY register dumps); the SID file itself is not
part of this repository.

## Tools and third-party files included in this repository

| File | Author | License / terms |
|---|---|---|
| `tools/bin/mads.exe` – MADS 2.1.8 assembler | Tomasz Biela (Tebe/Mad Team), [github.com/tebe6502/Mad-Assembler](https://github.com/tebe6502/Mad-Assembler) | MIT – [licenses/MADS-LICENSE.txt](licenses/MADS-LICENSE.txt) |
| `tools/bin/zx02.exe` – zx02 compressor | Daniel Serpell (DMSC), based on ZX0 by Einar Saukas | MIT – [licenses/zx02-LICENSE.txt](licenses/zx02-LICENSE.txt), BSD 3-Clause – [licenses/zx02-LICENSE.zx0.txt](licenses/zx02-LICENSE.zx0.txt) |
| `tools/bin/dir2atr.exe` – ATR image builder (AtariSIO 0.30-221009) | Matthias Reichl, [horus.com/~hias/atari](https://www.horus.com/~hias/atari/) | GPL-2.0 – [licenses/dir2atr-GPL-2.txt](licenses/dir2atr-GPL-2.txt); complete source of the same version: `tools/bin/src/atarisio-221009.tar.gz` |
| `tools/bin/xbios/` – xBIOS / xBOOT | XXL, [xxl.atari.pl/xbios](https://xxl.atari.pl/xbios/) | All rights reserved by the author; included unmodified |
| `src/data/sdcart.fnt` – cracktro font | Robin Edwards, [UltimateCart](https://github.com/robinhedwards/UltimateCart) | Public domain |
| `src/data/crk_music.lz16` – cracktro music | see Music above | as above |

The port's own code calls `dir2atr` and the other tools as separate programs; it does not contain or link their code.
