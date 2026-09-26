#!/usr/bin/env python3
"""Recolours PNGs to the nearest colour of `_Graphic Assets/Pixel_Palette.png` (AAP-64), as
the eye judges nearest (CIE Lab), keeping each pixel's alpha. Overwrites them in place.

    ./Tools/recolour_to_palette.py                 every PNG in `_Graphic Assets/Pixel Art`
    ./Tools/recolour_to_palette.py a.png b.png     just those

Sheets all in greys are the tint masks and are left alone. Back the originals up first;
this doesn't.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from pngio import read_png, write_png

ROOT = pathlib.Path(__file__).resolve().parent.parent
PALETTE = ROOT / "_Graphic Assets" / "Pixel_Palette.png"
ART = ROOT / "_Graphic Assets" / "Pixel Art"


def lab(rgb):
    def linear(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (linear(c) for c in rgb)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def palette():
    _, _, pixels = read_png(str(PALETTE))
    colours = []
    for r, g, b, a in pixels:
        if a == 255 and (r, g, b) not in colours:
            colours.append((r, g, b))
    return [(c, lab(c)) for c in colours]


def recolour(path, colours, cache):
    w, h, pixels = read_png(str(path))
    # A sheet all in greys is a mask the game tints in the energy colour, which is itself a
    # palette colour: left as it is.
    if all(r == g == b for r, g, b, a in pixels if a > 0):
        print(f"{path.name}: grey, a tint mask, left alone")
        return False
    out = []
    for r, g, b, a in pixels:
        if a == 0:
            out.append((0, 0, 0, 0))
            continue
        key = (r, g, b)
        if key not in cache:
            L, A, B = lab(key)
            cache[key] = min(colours, key=lambda c: (c[1][0] - L) ** 2 + (c[1][1] - A) ** 2 + (c[1][2] - B) ** 2)[0]
        out.append((*cache[key], a))
    write_png(str(path), w, h, out)
    return True


def main():
    colours = palette()
    assert len(colours) == 64, f"expected AAP-64's 64 colours, found {len(colours)}"
    files = [pathlib.Path(p) for p in sys.argv[1:]] or sorted(ART.glob("*.png"))
    cache = {}
    for path in files:
        recolour(path, colours, cache)
        print(path.name)


if __name__ == "__main__":
    main()
