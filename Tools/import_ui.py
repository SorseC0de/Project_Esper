#!/usr/bin/env python3
"""Brings the pieces of the dobo UI pack the game uses into `ProjectEsper/UI`, at half the
pack's size, and recolours the pack's purple to `EsperPalette`'s plum, which the pack
doesn't have. Only what's listed comes in, so the app carries no art it doesn't draw.
The pack is only read. Run from the project root after changing the list.
"""
import pathlib
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pngio import read_png, write_png

PACK = pathlib.Path.home() / "Downloads/Vector_UI_pack_dobo_UI-2/Vector_UI_Pack_dobo_ui"
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "ProjectEsper" / "UI"

# name in the app: (file in the pack, recolour purple to plum)
PIECES = {
    "ui_button_blue": ("Buttons/button_blue.png", False),
    "ui_button_gold": ("Buttons/button_yellow.png", False),
    "ui_button_black": ("Buttons/button_black.png", False),
    "ui_button_plum": ("Buttons/button_purple.png", True),
    "ui_header_blue": ("Headers/header_blue.png", False),
    "ui_card_black": ("Modals/darkModalSimple_dark.png", False),
    "ui_circle_blue": ("Buttons/buttonCircle_blue.png", False),
    "ui_circle_black": ("Buttons/buttonCircle_black.png", False),
    "ui_circle_plum": ("Buttons/buttonCircle_purple.png", True),
    "ui_circle_gold": ("Buttons/buttonCircle_yellow.png", False),
    "ui_plate_black": ("Labels/labelAdvanced_black.png", False),
    "ui_plate_blue": ("Labels/labelAdvanced_blue.png", False),
    "ui_icon_settings": ("Icons/128px/settings_icon_128px.png", False),
}

# The pack's purple ramp, lightest to darkest, and the plum each shade becomes.
PURPLE = [(0xB6, 0x6B, 0xFF), (0x9F, 0x45, 0xF5), (0x8D, 0x36, 0xE0), (0x4D, 0x14, 0xA3)]
PLUM = [(0x82, 0x53, 0x91), (0x6D, 0x41, 0x7D), (0x57, 0x2C, 0x66), (0x3D, 0x1D, 0x52)]


def plum(pixel):
    """The nearest purple shade at the brightness the pixel has it, as the same plum:
    blends toward the black outline stay blends."""
    r, g, b, a = pixel
    if a == 0 or max(r, g, b) < 24:
        return pixel
    best = None
    for index, (pr, pg, pb) in enumerate(PURPLE):
        scale = (r * pr + g * pg + b * pb) / (pr * pr + pg * pg + pb * pb)
        scale = min(max(scale, 0), 1.05)
        error = (r - scale * pr) ** 2 + (g - scale * pg) ** 2 + (b - scale * pb) ** 2
        if best is None or error < best[0]:
            best = (error, index, scale)
    error, index, scale = best
    # Not purple at all (a white glint, a grey): left as it is.
    if error > 2500:
        return pixel
    qr, qg, qb = PLUM[index]
    return (min(int(qr * scale), 255), min(int(qg * scale), 255), min(int(qb * scale), 255), a)


def main():
    OUT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as scratch:
        for name, (source, recolour) in PIECES.items():
            src = PACK / source
            width = int(subprocess.run(["sips", "-g", "pixelWidth", str(src)], capture_output=True, text=True).stdout.split()[-1])
            half = pathlib.Path(scratch) / f"{name}.png"
            subprocess.run(["sips", "--resampleWidth", str(width // 2), str(src), "--out", str(half)], capture_output=True, check=True)
            w, h, pixels = read_png(str(half))
            if recolour:
                pixels = [plum(p) for p in pixels]
            write_png(str(OUT / f"{name}.png"), w, h, pixels)
            print(f"{name}: {w}x{h}")
    wanted = {f"{name}.png" for name in PIECES}
    for stale in OUT.glob("*.png"):
        if stale.name not in wanted:
            stale.unlink()
            print(f"removed {stale.name}")


if __name__ == "__main__":
    main()
