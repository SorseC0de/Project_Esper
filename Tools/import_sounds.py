#!/usr/bin/env python3
"""Copies every sound in `_Sound FX` into the app as 16-bit PCM WAV, whatever it was
saved as (one arrives as AAC inside a .wav), so the app reads them all the same way.
The originals are only read. Run from the project root after adding or changing one."""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "_Sound FX"
DESTINATION = ROOT / "ProjectEsper" / "Sounds"

DESTINATION.mkdir(exist_ok=True)
wanted = set()
for sound in sorted(SOURCE.glob("*.wav")):
    out = DESTINATION / sound.name
    wanted.add(out.name)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", str(sound), str(out)], check=True)
    print(f"{sound.name}")
for stale in DESTINATION.glob("*.wav"):
    if stale.name not in wanted:
        stale.unlink()
        print(f"removed {stale.name}")
