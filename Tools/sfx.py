#!/usr/bin/env python3
"""A bfxr-style sound maker. Each sound in `Tools/sfx.json` is one or more voices mixed:
an oscillator (square with a duty, saw, triangle, sine or noise), an envelope (attack,
sustain, punch, decay), a pitch that slides and wobbles and can jump (arpeggio), and
low- and high-pass filters; then, for the whole sound, an optional flanger. Written as 16-bit 44.1 kHz mono WAV into `_Sound FX`, where
`Tools/import_sounds.py` takes it into the app like any other.

    ./Tools/sfx.py            every sound in the file
    ./Tools/sfx.py parry_a    just the ones named
"""
import json
import math
import pathlib
import random
import struct
import sys
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent
RECIPES = ROOT / "Tools" / "sfx.json"
OUT = ROOT / "_Sound FX"
RATE = 44100

VOICE_DEFAULTS = {
    "wave": "square",       # square, saw, triangle, sine, noise
    "frequency": 440.0,     # Hz at the start
    "slide": 0.0,           # octaves a second, up positive
    "slide_accel": 0.0,     # octaves a second, a second
    "vibrato_depth": 0.0,   # share of the pitch
    "vibrato_speed": 0.0,   # Hz
    "arpeggio": 1.0,        # pitch multiplier once `arpeggio_at` is reached
    "arpeggio_at": 0.0,     # seconds; 0 for none
    "duty": 0.5,            # square only
    "duty_sweep": 0.0,      # change a second
    "attack": 0.0,          # seconds
    "sustain": 0.05,        # seconds at full
    "punch": 0.0,           # extra at the start of the sustain, falling to none
    "decay": 0.2,           # seconds
    "decay_curve": 1.0,     # 1 straight, higher falls away faster
    "lowpass": 0.0,         # cutoff Hz; 0 for none
    "lowpass_sweep": 0.0,   # octaves a second
    "resonance": 0.0,       # 0 to 0.9
    "highpass": 0.0,        # cutoff Hz; 0 for none
    "volume": 1.0,
    "delay": 0.0,           # seconds before the voice starts
    "seed": 1,              # the noise's
}


def render_voice(settings):
    v = dict(VOICE_DEFAULTS, **settings)
    length = v["attack"] + v["sustain"] + v["decay"]
    count = int((length + v["delay"]) * RATE)
    out = [0.0] * count
    noise = random.Random(v["seed"])
    phase = 0.0
    duty = v["duty"]
    lp_state = lp_band = 0.0
    hp_previous_in = hp_previous_out = 0.0
    noise_value = noise.uniform(-1, 1)
    start = int(v["delay"] * RATE)
    for index in range(start, count):
        t = (index - start) / RATE
        # Pitch: the slide, its acceleration, the vibrato, the arpeggio's jump.
        octaves = v["slide"] * t + 0.5 * v["slide_accel"] * t * t
        frequency = v["frequency"] * (2 ** octaves)
        if v["vibrato_depth"]:
            frequency *= 1 + v["vibrato_depth"] * math.sin(2 * math.pi * v["vibrato_speed"] * t)
        if v["arpeggio_at"] and t >= v["arpeggio_at"]:
            frequency *= v["arpeggio"]
        frequency = max(frequency, 1.0)
        previous = phase
        phase = (phase + frequency / RATE) % 1.0
        wrapped = phase < previous
        wave_name = v["wave"]
        if wave_name == "square":
            duty = min(max(v["duty"] + v["duty_sweep"] * t, 0.02), 0.98)
            sample = 1.0 if phase < duty else -1.0
        elif wave_name == "saw":
            sample = 2 * phase - 1
        elif wave_name == "triangle":
            sample = 4 * abs(phase - 0.5) - 1
        elif wave_name == "sine":
            sample = math.sin(2 * math.pi * phase)
        else:
            # Noise: a new value each cycle, so the pitch sets its grain.
            if wrapped:
                noise_value = noise.uniform(-1, 1)
            sample = noise_value
        # Filters: a resonant low-pass (state variable), then a one-pole high-pass.
        if v["lowpass"]:
            cutoff = min(v["lowpass"] * (2 ** (v["lowpass_sweep"] * t)), RATE / 2.2)
            f = 2 * math.sin(math.pi * cutoff / RATE)
            q = 1 - min(v["resonance"], 0.9)
            lp_state += f * lp_band
            high = sample - lp_state - q * lp_band
            lp_band += f * high
            sample = lp_state
        if v["highpass"]:
            rc = 1 / (2 * math.pi * v["highpass"])
            alpha = rc / (rc + 1 / RATE)
            filtered = alpha * (hp_previous_out + sample - hp_previous_in)
            hp_previous_in, hp_previous_out = sample, filtered
            sample = filtered
        # The envelope.
        if t < v["attack"]:
            level = t / v["attack"]
        elif t < v["attack"] + v["sustain"]:
            into = (t - v["attack"]) / max(v["sustain"], 1e-6)
            level = 1 + v["punch"] * (1 - into)
        else:
            into = (t - v["attack"] - v["sustain"]) / max(v["decay"], 1e-6)
            level = max(1 - into, 0) ** v["decay_curve"]
        out[index] = sample * level * v["volume"]
    return out


FLANGER_DEFAULTS = {
    "offset": 2.0,      # milliseconds of delay at the start
    "sweep": 10.0,      # milliseconds a second the delay grows by, shrinking if negative
    "depth": 0.0,       # milliseconds the delay also wobbles by
    "rate": 0.0,        # Hz of that wobble
    "feedback": 0.4,    # share of the delayed signal fed back in, 0 to 0.9
    "mix": 0.6,         # share of the delayed copy in the output
}


def flange(samples, settings):
    """The sound mixed with a copy of itself on a short, moving delay, fed back: the jet
    whoosh of a comb filter sliding through the harmonics."""
    f = dict(FLANGER_DEFAULTS, **settings)
    tail = int(0.03 * RATE)
    source = samples + [0.0] * tail
    line = [0.0] * len(source)
    out = []
    for index, sample in enumerate(source):
        t = index / RATE
        delay_ms = f["offset"] + f["sweep"] * t + f["depth"] * math.sin(2 * math.pi * f["rate"] * t)
        delay = max(delay_ms, 0.05) / 1000 * RATE
        back = index - delay
        if back >= 1:
            low = int(back)
            share = back - low
            delayed = line[low] * (1 - share) + line[low + 1] * share if low + 1 < index else line[low]
        else:
            delayed = 0.0
        line[index] = sample + delayed * min(f["feedback"], 0.9)
        out.append(sample * (1 - f["mix"] / 2) + delayed * f["mix"])
    return out


def render(recipe):
    voices = [render_voice(voice) for voice in recipe["voices"]]
    length = max(len(voice) for voice in voices)
    mixed = [0.0] * length
    for voice in voices:
        for index, sample in enumerate(voice):
            mixed[index] += sample
    if "flanger" in recipe:
        mixed = flange(mixed, recipe["flanger"])
    # Levelled to the recipe's peak off the loudest 0.5% but one, so a lone spike (the
    # flanger's feedback throws them) can't leave the rest quiet; what's over is rounded
    # off softly rather than clipped.
    ordered = sorted(abs(sample) for sample in mixed)
    near_peak = max(ordered[int(len(ordered) * 0.995)], 1e-9)
    gain = recipe.get("peak", 0.8) / near_peak
    ceiling = 0.95
    return [ceiling * math.tanh(sample * gain / ceiling) for sample in mixed]


def write(name, samples):
    OUT.mkdir(exist_ok=True)
    path = OUT / f"{name}.wav"
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(min(s, 1), -1) * 32767)) for s in samples))
    return path


def main():
    recipes = json.loads(RECIPES.read_text())
    wanted = sys.argv[1:] or [name for name in recipes if not name.startswith("_")]
    for name in wanted:
        path = write(name, render(recipes[name]))
        print(f"{path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
