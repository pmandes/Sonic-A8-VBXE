#!/usr/bin/env python3
"""Checks that the Sega Master System ROM needed by the build is present (called by tools/build.cmd).

The ROM is not part of this repository. Put your own dump of Sonic The Hedgehog (SMS, USA/Europe/Brazil)
into assets/rom/sms/ - any *.sms file name works, the file is recognised by its SHA-256.
Exit code 0 = ROM found, 1 = ROM missing or wrong version, 2 = missing Python packages.
"""
from __future__ import annotations

import hashlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import extract_sms  # noqa: E402
except ImportError as e:
    print(f"ERROR: missing Python package ({e.name}). Install the requirements: python -m pip install -r requirements.txt",
          file=sys.stderr)
    sys.exit(2)


def main() -> int:
    rom = extract_sms.DEFAULT_ROM
    sha = extract_sms.ROM_SHA256
    if rom.is_file() and hashlib.sha256(rom.read_bytes()).hexdigest() == sha:
        print(f"ROM OK: {rom.name}")
        return 0
    katalog = extract_sms.ROM_DIR
    print("ERROR: Sega Master System ROM of Sonic The Hedgehog not found.", file=sys.stderr)
    print(f"  Put your own ROM dump (*.sms, any file name) into: {katalog}", file=sys.stderr)
    print("  Expected ROM: Sonic The Hedgehog (USA, Europe, Brazil), 262 144 bytes", file=sys.stderr)
    print(f"  Expected SHA-256: {sha}", file=sys.stderr)
    inne = sorted(katalog.glob("*.sms")) if katalog.is_dir() else []
    for p in inne:
        print(f"  {p.name}: SHA-256 {hashlib.sha256(p.read_bytes()).hexdigest()} - wrong ROM version", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
