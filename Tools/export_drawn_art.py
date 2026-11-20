#!/usr/bin/env python3
"""Bakes art the game draws in code into PNGs, by the game's own code: the Breaker Ball
barrier shattering, in every energy colour, and the Tutorial hub's front-facing hoop with its
white net.

The types that build the barrier's tiles and the net's strokes are cut out of the app's sources
by name, compiled with a few stand-ins into a small Mac program, and drawn through Glow.metal's
own cube shader, so the output follows the game whenever either changes.

    ./Tools/export_drawn_art.py [--scale 4]

Writes to `_Graphic Assets/Pixel Art/Assembled/`:
    breaker_barrier_shatter/breaker_barrier_shatter_<colour>.png  frame 1 the standing barrier,
        then the shatter a sim frame at a time; a grid, ten across
    hoop_front/hoop_front.png
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIEW = os.path.join(ROOT, "ProjectEsper", "View")
ART = os.path.join(ROOT, "ProjectEsper", "Art")
ASSETS = os.path.join(ROOT, "ProjectEsper", "Assets.xcassets")
OUT = os.path.join(ROOT, "_Graphic Assets", "Pixel Art", "Assembled")

# (file, declarations cut from it); None takes the whole file.
CUTS = [
    (os.path.join(VIEW, "Cubes.swift"), None),
    (os.path.join(VIEW, "CylinderNet.swift"), None),
    (os.path.join(VIEW, "HoopNet.swift"), ["enum NetTuning"]),
    (os.path.join(VIEW, "BreakerArt.swift"), ["enum BreakerLook", "struct BarrierHit", "enum BarrierLook",
                                              "struct BarrierShatter", "func shatterRandom"]),
    (os.path.join(ART, "PixelPalette.swift"), ["enum PixelPalette"]),
    (os.path.join(VIEW, "Tuning.swift"), ["enum ZoneTuning"]),
    (os.path.join(ART, "PlayerPalette.swift"), ["enum EnergyColour"]),
]
# Look's energy tones, cut into a stand-in Look of only its glow.
LOOK_CUTS = (os.path.join(ART, "PlayerPalette.swift"),
             ["var bright", "func energyTone", "static func lightened", "static func scaled"])

STANDINS = """
import CoreGraphics
import Foundation
import SpriteKit
import simd
typealias RGB = UInt32
enum StageLook { case court, footballField, flightB411; var tiltedHoop: Bool { false } }
enum HoopTuning { static let netReference = CGPoint.zero; static func offset(for look: StageLook) -> CGPoint { .zero } }
enum StockTicker { case mineralHeart }
func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
"""


def cut(source, opener):
    """The declaration starting `opener` at the line's start, its doc comment with it, to its closing brace."""
    match = re.search(r"^[ \t]*" + re.escape(opener) + r"\b", source, re.M)
    if not match:
        sys.exit(f"not found: {opener}")
    start = match.start()
    # Its doc comment and attributes above it.
    lines_before = source[:start].split("\n")[:-1]
    while lines_before and lines_before[-1].lstrip().startswith(("///", "@")):
        lines_before.pop()
    start = len("\n".join(lines_before)) + (1 if lines_before else 0)
    depth = 0
    index = source.index("{", match.start())
    while True:
        char = source[index]
        if source.startswith("//", index):
            index = source.index("\n", index)
            continue
        if char == '"':
            # Skip a string literal (no braces inside count).
            index += 1
            while source[index] != '"':
                index += 2 if source[index] == "\\" else 1
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
        index += 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scale", type=int, default=4, help="output pixels an art pixel")
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory() as folder:
        parts = [STANDINS]
        for path, openers in CUTS:
            source = open(path).read()
            if openers is None:
                parts.append(re.sub(r"^import .*$", "", source, flags=re.M))
            else:
                parts += [cut(source, opener) for opener in openers]
        path, openers = LOOK_CUTS
        source = open(path).read()
        parts.append("struct Look {\n    let glow: RGB\n    static func team(_ glow: RGB, body: RGB) -> Look { Look(glow: glow) }\n"
                     + "\n".join(cut(source, opener) for opener in openers) + "\n}")
        # Only what's cut: anything else a cut type reaches for is a compile error naming it.
        parts.append(open(os.path.join(ROOT, "Tools", "export_drawn_art.swift")).read())
        program = os.path.join(folder, "main.swift")
        open(program, "w").write("\n\n".join(parts))
        binary = os.path.join(folder, "export")
        environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
        result = subprocess.run(["xcrun", "swiftc", "-O", "-swift-version", "5", program, "-o", binary], env=environment,
                                capture_output=True, text=True)
        if result.returncode != 0:
            sys.exit(result.stderr)
        subprocess.run([binary, os.path.join(VIEW, "Glow.metal"), ASSETS, OUT, str(arguments.scale)], check=True)


if __name__ == "__main__":
    main()
