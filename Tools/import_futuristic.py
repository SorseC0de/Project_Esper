#!/usr/bin/env python3
"""Brings every named group of `_Graphic Assets/Vectors/Futuristic_UI.svg` in as the menus' frames and rules.

Each group is the vector with only that group left (the backdrop rectangle goes), turned to
greys as bright as each colour's strongest channel, so the vector's cyan comes out white for
the game to multiply by a colour. It's rendered once small to find where it is, then again
cropped to it at full size, into `ProjectEsper/UI/Futuristic` as `futuristic_<group>.png`.
Run from the project root after the vector changes, or to bring in another group.
"""
import pathlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "_Graphic Assets" / "Vectors" / "Futuristic_UI.svg"
OUT = ROOT / "ProjectEsper" / "UI" / "Futuristic"
RENDERER = ROOT / "Tools" / "render_svg.swift"
# The Variaball logo, standing in for the title's name in a debug build, and its rendered width.
LOGO = ROOT / "_Graphic Assets" / "Vectors" / "Variaball Logo.svg"
LOGO_OUT = ROOT / "ProjectEsper" / "UI" / "variaball_logo.png"
LOGO_WIDTH = 1600
# The finding pass's width, and the whole vector's width the kept pass renders at.
FIND_WIDTH = 2560
FULL_WIDTH = 8192
# Room around each crop, in the finding pass's pixels.
MARGIN = 2

SVG = "http://www.w3.org/2000/svg"
for prefix, uri in {"": SVG, "xlink": "http://www.w3.org/1999/xlink", "serif": "http://www.serif.com/"}.items():
    ET.register_namespace(prefix, uri)


def grey(match):
    colour = match.group(2).lower()
    if len(colour) == 4:
        colour = "#" + "".join(c * 2 for c in colour[1:])
    value = max(int(colour[i:i + 2], 16) for i in (1, 3, 5))
    return f"{match.group(1)}#{value:02x}{value:02x}{value:02x}"


def contains(element, wanted):
    return element.get("id") == wanted or any(contains(child, wanted) for child in element)


def prune(element, wanted):
    """Only the wanted group and the groups holding it."""
    for child in list(element):
        if child.get("id") == wanted:
            continue
        if contains(child, wanted):
            prune(child, wanted)
        else:
            element.remove(child)


def render(renderer, svg, png, width, height):
    out = subprocess.run([str(renderer), str(svg), str(png), str(width), str(height)],
                         capture_output=True, text=True, check=True).stdout.split()
    return list(map(int, out))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = SOURCE.read_text()
    view = [float(n) for n in re.search(r'viewBox="([^"]+)"', source).group(1).split()]
    whole_width, whole_height = view[2], view[3]
    find_height = round(FIND_WIDTH * whole_height / whole_width)
    # Every named group, by its name in the vector (Affinity writes "1" as id "_1").
    groups = [re.sub(r"^_(\d)", r"\1", name) for name in re.findall(r'<g id="([^"]+)"', source)]
    with tempfile.TemporaryDirectory() as scratch:
        scratch = pathlib.Path(scratch)
        renderer = scratch / "render_svg"
        subprocess.run(["swiftc", "-O", str(RENDERER), "-o", str(renderer)], check=True)
        for group in groups:
            wanted = f"_{group}" if group[0].isdigit() else group
            root = ET.fromstring(source)
            prune(root, wanted)
            text = re.sub(r"((?:fill|stroke|stop-color):)(#[0-9a-fA-F]{3,6})\b", grey, ET.tostring(root, encoding="unicode"))
            whole = scratch / f"{group}.svg"
            whole.write_text(text)
            x, y, w, h = render(renderer, whole, scratch / f"{group}_find.png", FIND_WIDTH, find_height)
            # The crop in the vector's units, with its margin, rendered at the full width's density.
            unit = whole_width / FIND_WIDTH
            box = [(x - MARGIN) * unit, (y - MARGIN) * unit, (w + 2 * MARGIN) * unit, (h + 2 * MARGIN) * unit]
            root.set("viewBox", " ".join(f"{n:.2f}" for n in box))
            root.set("width", f"{box[2]:.2f}")
            root.set("height", f"{box[3]:.2f}")
            path = scratch / f"{group}_crop.svg"
            path.write_text(re.sub(r"((?:fill|stroke|stop-color):)(#[0-9a-fA-F]{3,6})\b", grey, ET.tostring(root, encoding="unicode")))
            density = FULL_WIDTH / whole_width
            name = f"futuristic_{group}"
            _, _, pw, ph = render(renderer, path, OUT / f"{name}.png", round(box[2] * density), round(box[3] * density))
            print(f"{name:22s} {pw}x{ph}")
        logo = re.search(r'viewBox="([^"]+)"', LOGO.read_text()).group(1).split()
        _, _, lw, lh = render(renderer, LOGO, LOGO_OUT, LOGO_WIDTH, round(LOGO_WIDTH * float(logo[3]) / float(logo[2])))
        print(f"{LOGO_OUT.stem:22s} {lw}x{lh}")
    wanted = {f"futuristic_{group}.png" for group in groups}
    for stale in OUT.glob("*.png"):
        if stale.name not in wanted:
            stale.unlink()
            print(f"removed {stale.name}")


main()
