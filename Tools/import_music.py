#!/usr/bin/env python3
"""Brings tracks from `_Audio/Music` into the app as lossless ALAC, so a loop meets its start
without the gap an AAC encoder's padding leaves: the music `LoopedTrack.music` plays.

The originals are only read. Run from the project root after changing one. Needs ffmpeg (Ogg Vorbis)."""
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "_Audio" / "Music"
DESTINATION = ROOT / "ProjectEsper" / "Music"

# Source file: name in the app.
MUSIC = {"Wreck.ogg": "wreck"}

DESTINATION.mkdir(exist_ok=True)
for file, name in MUSIC.items():
    out = DESTINATION / (name + ".caf")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(SOURCE / file), "-map_metadata", "-1",
                    "-c:a", "alac", "-sample_fmt", "s16p", str(out)], check=True)
    print(f"{file} -> {out.name}")
