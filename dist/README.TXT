Sonic The Hedgehog (c) Sega 1991

Sonic A8 VBXE v1.0 - a fan-made port for Atari XL/XE by madness77

This port was made by translating Z80 assembly into 6502 with the help of AI, based on the source code
of Disassembly of Sonic The Hedgehog for the Sega Master System by GreaseMonkey.

Original music by Masato Nakamura and Yuzo Koshiro, C64 SID version by Mikkel Hastrup (Encore) / Sonic Team 64.
Converted to POKEY with sid2sapr by Ivo van Poorten.

---

Requirements: Atari XL/XE with VBXE (tested with FX 1.26 core) and at least 320 KB of RAM (RAMBO)

---

sonic-a8-vbxe.xex - 854 755 B
Release in XEX format (XEX loader: for SIO devices like: SDrive-MAX, FujiNet, SIO2PC and Multicarts)
Requires 1088K (Ultimate 1MB) + VBXE.

sonic-atarimax.car - 1 048 592 B
AtariMax 1 MB cartridge, CAR image type 42 (old layout - starts from bank 127)

sonic-atarimax75.car - 1 048 592 B
AtariMax 1 MB cartridge, CAR image type 75 (new hardware - starts from bank 0)

sonic-atarimax.bin - 1 048 576 B
AtariMax 1 MB cartridge, raw ROM image (no CAR header) - for flashing.

sonic-sic512.car - 524 304 B
SIC! 512 KB cartridge, CAR image type 56.

sonic-a8-vbxe.atr - 255 376 B
A single MyDOS DD disk (the whole game, xBIOS) - for SIO devices that support large ATR images...

sonic-ed1.atr - 133 136 B
sonic-ed2.atr - 133 136 B
sonic-ed3.atr - 133 136 B
Set of 3 ED disks (Enhanced Density, DOS 2.5) for a standard 1050 drive. Boot from disk 1; the game asks for disk 2
at Bridge Zone 1 and for disk 3 at Scrap Brain Zone 1.
