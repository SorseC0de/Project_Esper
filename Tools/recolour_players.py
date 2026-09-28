#!/usr/bin/env python3
"""The player sheets onto the twelve AAP-64 colours the figure is drawn in, one per body
part, so every part is the same colour in every sheet. Each pixel goes to its part's
colour by the part keys (within 2 a channel, as the game reads them); the ball's white and
the slash's pinks are left as they are. The GMS2 sheets come out as vertical strips in
`_Graphic Assets/Pixel Art`, which the importer takes over the GMS2 sprite; the GMS2
project isn't touched. Every sheet is copied as it was into `Pixel Art/Player Backup`
first, and a backup is never overwritten, so running this again is safe.

    ./Tools/recolour_players.py
"""
import glob
import importlib.util
import os
import re
import shutil
import sys
from collections import Counter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, os.path.join(ROOT, "Tools"))
from pngio import read_png, write_png  # noqa: E402

STRIPS = os.path.join(ROOT, "_Graphic Assets", "Pixel Art")
BACKUP = os.path.join(STRIPS, "Player Backup")
GMS2_SPRITES = os.path.expanduser("~/GameMakerStudio2/Project Esper/sprites")
ANIMATIONS = os.path.join(ROOT, "EsperSim", "Sources", "EsperSim", "Animation.swift")

# Each part's colour on AAP-64 (the user's indexes, from 0), and the colours the sheets
# painted it in before.
PARTS = {
    "head":       (0x20D6C7, [0x5FCDE4]),
    "torso":      (0xFA6A0A, [0xDF7126, 0xDE7120]),
    "pelvis":     (0xBB7547, [0xC46423, 0xB35B20, 0xC56520]),
    "frontThigh": (0xFFD541, [0xD1CC60]),
    "frontLeg":   (0xFFFC40, [0xFBF236]),
    "frontArm":   (0x59C135, [0x6ABE30]),
    "frontHand":  (0x9CDB43, [0x99E550, 0x9CE652]),
    # The back limbs as they lie, read off the sheets: the darker purple sits by the
    # shoulder and the lighter at the hand; both light reds are the thigh, the dark red the
    # leg and foot.
    "backArm":    (0x793A80, [0x951799, 0x94149C]),
    "backHand":   (0xBC4A9B, [0xAF1AB2, 0xAC18B4, 0xAD54B0]),
    "backThigh":  (0x73172D, [0xCE5050, 0xD95763]),
    "backLeg":    (0xB4202A, [0xAC3232]),
    # The feet, marked afterwards: palette 21 in front, 26 behind.
    "frontFoot":  (0xA6FCDB, []),
    "backFoot":   (0xE86A73, []),
}
KEPT = [0xFFFFFF, 0xF065C4, 0xF9ABFF, 0xFBC2FF, 0xEEA6F5, 0xF098F5, 0xFDD9FF, 0xEDCEF0]


def near(a, b):
    return all(abs(((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)) <= 2 for shift in (16, 8, 0))


def part_colour(rgb):
    """The colour a pixel becomes, or None if it's no part's."""
    for new, old in PARTS.values():
        if near(rgb, new) or any(near(rgb, key) for key in old):
            return new
    return None


def load_yy(path):
    spec = importlib.util.spec_from_file_location("import_sprites", os.path.join(ROOT, "Tools", "import_sprites.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.load_yy(path)


def frames_of(name):
    """(size, frames, strip path or None): a sheet's frames as pixel lists, square."""
    strips = {os.path.splitext(os.path.basename(p))[0].lower(): p for p in glob.glob(os.path.join(STRIPS, "*.png"))}
    if name in strips:
        width, height, pixels = read_png(strips[name])
        return width, [pixels[i * width * width:(i + 1) * width * width] for i in range(height // width)], strips[name]
    folder = os.path.join(GMS2_SPRITES, "spr_" + name)
    sprite = load_yy(glob.glob(os.path.join(folder, "*.yy"))[0])
    frames = []
    size = None
    for frame in sprite["frames"]:
        width, height, pixels = read_png(os.path.join(folder, frame["name"] + ".png"))
        assert width == height, f"{name}: frames not square"
        size = width
        frames.append(pixels)
    return size, frames, None


def main():
    names = re.findall(r'case \w+ = "(player_[a-z_0-9]+)"', open(ANIMATIONS).read())
    os.makedirs(BACKUP, exist_ok=True)
    strange = Counter()
    for name in names:
        size, frames, strip = frames_of(name)
        backup = os.path.join(BACKUP, name + ".png")
        if not os.path.exists(backup):
            if strip:
                shutil.copy2(strip, backup)
            else:
                write_png(backup, size, size * len(frames), [p for frame in frames for p in frame])
        out = []
        for frame in frames:
            for r, g, b, a in frame:
                rgb = r << 16 | g << 8 | b
                colour = part_colour(rgb) if a > 0 else None
                if colour is not None:
                    out.append((colour >> 16, (colour >> 8) & 0xFF, colour & 0xFF, a))
                else:
                    if a > 0 and not any(near(rgb, key) for key in KEPT):
                        strange[(name, "#%06X" % rgb)] += 1
                    out.append((r, g, b, a))
        target = strip or os.path.join(STRIPS, name + ".png")
        write_png(target, size, size * len(frames), out)
        print(f"{name}: {len(frames)} frames of {size}px -> {os.path.relpath(target, ROOT)}")
    for (name, colour), count in sorted(strange.items()):
        print(f"  left as it was, no part's: {name} {colour} x{count}")


if __name__ == "__main__":
    main()
