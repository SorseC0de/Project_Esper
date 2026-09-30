#!/usr/bin/env python3
"""Brings the long background sounds in `_Sound FX` into the app as AAC, cut to their
loop length with a fade in and a fade out, so they loop without a seam: the stage's
ambience, played low under everything (`Ambience.swift`).

The originals are only read. Run from the project root after changing one."""
import pathlib
import struct
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "_Sound FX"
DESTINATION = ROOT / "ProjectEsper" / "Sounds"

# Source file: (name in the app, seconds kept, seconds of fade at each end).
AMBIENCE = {"thunderstorm.mp3": ("thunderstorm", 300, 4)}

for file, (name, seconds, fade) in AMBIENCE.items():
    with tempfile.TemporaryDirectory() as scratch:
        full = pathlib.Path(scratch) / "full.wav"
        cut = pathlib.Path(scratch) / "cut.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "2", str(SOURCE / file), str(full)], check=True)
        data = full.read_bytes()
        index = 12
        while data[index:index + 4] != b"data":
            index += 8 + struct.unpack("<I", data[index + 4:index + 8])[0]
        frames = min(struct.unpack("<I", data[index + 4:index + 8])[0] // 4, seconds * 44100)
        samples = list(struct.unpack(f"<{frames * 2}h", data[index + 8:index + 8 + frames * 4]))
        ramp = fade * 44100
        for frame in range(frames):
            gain = min(frame / ramp, (frames - 1 - frame) / ramp, 1)
            samples[frame * 2] = int(samples[frame * 2] * gain)
            samples[frame * 2 + 1] = int(samples[frame * 2 + 1] * gain)
        body = struct.pack(f"<{frames * 2}h", *samples)
        header = b"RIFF" + struct.pack("<I", 36 + len(body)) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 2, 44100, 44100 * 4, 4, 16)
        cut.write_bytes(header + b"data" + struct.pack("<I", len(body)) + body)
        out = DESTINATION / (name + ".m4a")
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "128000", str(cut), str(out)], check=True)
        print(f"{file} -> {out.name}: {frames / 44100:.0f} s")
