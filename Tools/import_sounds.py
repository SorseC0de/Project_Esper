#!/usr/bin/env python3
"""Copies every sound in `_Audio/Sound FX` into the app as 16-bit, 44.1 kHz mono PCM WAV,
whatever it was saved as (WAV of any rate, AAC inside a .wav, MP3, M4A), so the app
reads them all the same way. The name keeps its stem, lowercased, with `.wav`. A sound in
the app that's no longer there is removed (the old countdown and basket went that way).

From `_Audio/Vocals` only the files in `VOCALS` come in, each levelled as it's
converted: its loudness while it's sounding (the RMS of its 10 ms stretches above
-40 dBFS) brought to its target, and its peak kept under `PEAK_CEILING`, so the lines
are even with each other and sit under the effects they play with.

Effects named in `LEVELLED_EFFECTS` are levelled the same way, to `EFFECT_LEVEL`, the effects'
middle loudness, so a new one sits with the rest; the ones from before it came in as they are.

Only effects the app plays come in: a file whose name `SoundBoard.Effect` names (a case's raw
value, a bare case, or a layer's file) is copied; the rest stay in `_Audio` unpackaged, and one
already in the app that nothing names any more is taken out.

The originals are only read. Run from the project root after adding or changing one."""
import math
import pathlib
import re
import struct
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "_Audio" / "Sound FX"
VOCALS_SOURCE = ROOT / "_Audio" / "Vocals"
DESTINATION = ROOT / "ProjectEsper" / "Sounds"

# The announcer at -21 dB, just under the swish (-20.5); the crowd behind everything.
ANNOUNCER_LEVEL = -21.0
CROWD_LEVEL = -27.0
PEAK_CEILING = -3.0
# The effects in the app sit around -21 dB while sounding (their median); new ones are brought there.
EFFECT_LEVEL = -21.0
LEVELLED_EFFECTS = {"dunk", "slashclash", "flo_collect", "slide", "flo_max", "boing", "flo_state", "slide2", "flash", "shield", "player_spin"}

# File in Vocals: (name in the app, loudness while sounding in dBFS).
VOCALS = {
    **{f"Announcer_{name}.wav": (f"announcer_{name}", ANNOUNCER_LEVEL) for name in [
        "1", "2", "3", "1-2", "2-2", "3-2",
        "ballout", "ballout2",
        "thatlldoit", "thatlldoit-2", "thatdecidesit",
        "score", "score-2", "score-3", "whatascore",
        "slamdunk", "slamdunk-2", "slamdunk-3", "dunk",
        "watchthewristwork", "watchthewristwork-2",
        "itsathree",
        "winner", "winner-2", "whatawin",
        "stole", "stole2", "stole3", "nabbed", "nabbed2", "nabbed3", "knicked", "knicked2", "knicked3",
        "whatwillyoudo", "whatwilltheydo", "atoughchoice",
    ]},
    "crowd_cheer.wav": ("crowd_cheer", CROWD_LEVEL),
    "crowd_gasp.wav": ("crowd_gasp", CROWD_LEVEL),
}

SUFFIXES = {".wav", ".mp3", ".m4a", ".aif", ".aiff", ".caf", ".ogg"}
# Long backgrounds that come in through Tools/import_ambience.py instead, as AAC.
AMBIENCE = {"thunderstorm.mp3", "thunderstorm.wav"}


def convert(sound, out):
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "1", str(sound), str(out)], check=True)


def read_samples(path):
    data = path.read_bytes()
    index = 12
    while index < len(data):
        chunk, size = data[index:index + 4], struct.unpack("<I", data[index + 4:index + 8])[0]
        if chunk == b"data":
            body = data[index + 8:index + 8 + size]
            count = len(body) // 2
            return [value / 32768 for value in struct.unpack(f"<{count}h", body[:count * 2])]
        index += 8 + size + (size & 1)
    return []


def write_samples(path, samples):
    body = b"".join(struct.pack("<h", int(max(min(s, 1), -1) * 32767)) for s in samples)
    header = b"RIFF" + struct.pack("<I", 36 + len(body)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, 44100, 44100 * 2, 2, 16)
    path.write_bytes(header + b"data" + struct.pack("<I", len(body)) + body)


def level(path, target):
    """The file's loudness while sounding to `target`, its peak no higher than the ceiling."""
    samples = read_samples(path)
    stretch = 441
    active = []
    for start in range(0, len(samples), stretch):
        block = samples[start:start + stretch]
        mean_square = sum(s * s for s in block) / len(block)
        if math.sqrt(mean_square) > 0.01:
            active.append(mean_square)
    if not active:
        return
    loudness = 10 * math.log10(sum(active) / len(active))
    peak = 20 * math.log10(max(abs(s) for s in samples))
    gain = min(target - loudness, PEAK_CEILING - peak)
    scale = 10 ** (gain / 20)
    write_samples(path, [s * scale for s in samples])
    print(f"  levelled {gain:+.1f} dB: {loudness:.1f} -> {loudness + gain:.1f}, peak {peak + gain:.1f}")


def referenced_names():
    """Every file name SoundBoard plays: its Effect cases' raw values and bare names, and its
    layers' files (any quoted name in the file)."""
    source = (ROOT / "ProjectEsper" / "Audio" / "SoundBoard.swift").read_text()
    names = set(re.findall(r'"([A-Za-z0-9_\-]+)"', source))
    enum = source[source.index("enum Effect"):]
    enum = enum[:enum.index("\n    }")]
    for line in re.findall(r"^\s*case ([^\n]+)", enum, re.M):
        for item in line.split(","):
            match = re.match(r"\s*([A-Za-z0-9_]+)\s*(=|$)", item)
            if match and match.group(2) == "":
                names.add(match.group(1))
    return {name.lower() for name in names}


DESTINATION.mkdir(exist_ok=True)
REFERENCED = referenced_names()
wanted = set()
# Two files of one name (boing.ogg and boing.wav): the .wav is the one meant.
sources = {}
for sound in sorted(SOURCE.iterdir()):
    if sound.suffix.lower() not in SUFFIXES or sound.name in AMBIENCE:
        continue
    kept = sources.get(sound.stem.lower())
    if kept is None or sound.suffix.lower() == ".wav":
        sources[sound.stem.lower()] = sound
for sound in sorted(sources.values()):
    if sound.stem.lower() not in REFERENCED:
        print(f"  not played, left out: {sound.name}")
        continue
    out = DESTINATION / (sound.stem.lower() + ".wav")
    wanted.add(out.name)
    convert(sound, out)
    print(f"{sound.name}")
    if out.stem in LEVELLED_EFFECTS:
        level(out, EFFECT_LEVEL)
for file, (name, target) in VOCALS.items():
    sound = VOCALS_SOURCE / file
    if not sound.exists():
        print(f"missing Vocals/{file}")
        continue
    out = DESTINATION / (name + ".wav")
    wanted.add(out.name)
    convert(sound, out)
    print(f"Vocals/{file}")
    level(out, target)
for stale in DESTINATION.glob("*.wav"):
    if stale.name not in wanted:
        stale.unlink()
        print(f"removed {stale.name}")
