#!/usr/bin/env python3
"""Copies every sound in `_Sound FX` into the app as 16-bit, 44.1 kHz mono PCM WAV,
whatever it was saved as (WAV of any rate, AAC inside a .wav, MP3, M4A), so the app
reads them all the same way. The name keeps its stem, lowercased, with `.wav`.
The originals are only read. Run from the project root after adding or changing one."""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "_Sound FX"
DESTINATION = ROOT / "ProjectEsper" / "Sounds"

DESTINATION.mkdir(exist_ok=True)
wanted = set()
for sound in sorted(SOURCE.iterdir()):
    if sound.suffix.lower() not in {".wav", ".mp3", ".m4a", ".aif", ".aiff", ".caf"}:
        continue
    out = DESTINATION / (sound.stem.lower() + ".wav")
    wanted.add(out.name)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "1", str(sound), str(out)], check=True)
    print(f"{sound.name}")
for stale in DESTINATION.glob("*.wav"):
    if stale.name not in wanted:
        stale.unlink()
        print(f"removed {stale.name}")
