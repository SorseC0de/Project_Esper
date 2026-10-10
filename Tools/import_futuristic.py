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
# bar4, the loading bar: its frame and slot outlines without the vector's fills, uncropped, and
# its sixteen slots' insides, as shares of that frame, written to FuturisticMeter.swift.
METER = "bar4"
METER_LAYOUT = ROOT / "ProjectEsper" / "View" / "FuturisticMeter.swift"
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


def render(renderer, svg, png, width, height, whole=False):
    out = subprocess.run([str(renderer), str(svg), str(png), str(width), str(height)] + (["whole"] if whole else []),
                         capture_output=True, text=True, check=True).stdout.split()
    return list(map(int, out))


def numbers(path):
    values = [float(n) for n in re.findall(r"-?\d+\.?\d*", path.get("d"))]
    return list(zip(values[0::2], values[1::2]))


def bounds(path):
    xs, ys = zip(*numbers(path))
    return min(xs), min(ys), max(xs), max(ys)


def meter_pieces(group):
    """bar4's slot outlines, left to right, and the fills the vector puts in some of them."""
    outlines, fills = [], []
    for path in group:
        d = path.get("d") or ""
        left, top, right, bottom = bounds(path)
        if "C" in d and d.count("Z") == 2 and 25 < bottom - top < 46 and right - left < 80:
            outlines.append(path)
        elif "C" not in d and d.count("Z") == 1 and 20 < bottom - top < 41 and right - left < 75:
            fills.append(path)
    outlines.sort(key=lambda path: bounds(path)[0])
    if len(outlines) != 16:
        raise SystemExit(f"{METER} has {len(outlines)} slot outlines, not 16")
    return outlines, fills


def meter_slots(outlines, fills):
    """Each slot's inside: the vector's fill where it has one; else a slanted slot's as the
    first slanted fill moved along, and the right end's triangle inset from its outline as the
    left end's fill is from its own."""
    def corners(path):
        return [(float(x), float(y)) for x, y in re.findall(r"[ML](-?[\d.]+),(-?[\d.]+)", path.get("d"))]

    def inside(outline):
        left, top, right, bottom = bounds(outline)
        for fill in fills:
            fl, ft, fr, fb = bounds(fill)
            if left <= (fl + fr) / 2 <= right and top <= (ft + fb) / 2 <= bottom:
                return fill
        return None

    slanted = [outline for outline in outlines if bounds(outline)[2] - bounds(outline)[0] > 60]
    first = next(outline for outline in slanted if inside(outline) is not None)
    first_fill = corners(inside(first))
    end = outlines[0]
    ring = bounds(inside(end))[0] - bounds(end)[0]
    slots = []
    for outline in outlines:
        fill = inside(outline)
        if fill is not None:
            slots.append(corners(fill)[:-1] if corners(fill)[0] == corners(fill)[-1] else corners(fill))
        elif outline in slanted:
            dx = bounds(outline)[0] - bounds(first)[0]
            points = [(x + dx, y) for x, y in first_fill]
            slots.append(points[:-1] if points[0] == points[-1] else points)
        else:
            left, top, right, bottom = bounds(outline)
            edge = min(x + y for x, y in numbers(outline)) + ring * 2 ** 0.5
            inner_right, inner_bottom = right - ring, bottom - ring
            slots.append([(edge - inner_bottom, inner_bottom), (inner_right, edge - inner_right), (inner_right, inner_bottom)])
    return slots


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = SOURCE.read_text()
    view = [float(n) for n in re.search(r'viewBox="([^"]+)"', source).group(1).split()]
    whole_width, whole_height = view[2], view[3]
    find_height = round(FIND_WIDTH * whole_height / whole_width)
    # Every named group, by its name in the vector (Affinity writes "1" as id "_1").
    groups = [re.sub(r"^_(\d)", r"\1", name) for name in re.findall(r'<g id="([^"]+)"', source)]
    boxes = {}
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
            boxes[group] = box
            root.set("viewBox", " ".join(f"{n:.2f}" for n in box))
            root.set("width", f"{box[2]:.2f}")
            root.set("height", f"{box[3]:.2f}")
            path = scratch / f"{group}_crop.svg"
            path.write_text(re.sub(r"((?:fill|stroke|stop-color):)(#[0-9a-fA-F]{3,6})\b", grey, ET.tostring(root, encoding="unicode")))
            density = FULL_WIDTH / whole_width
            name = f"futuristic_{group}"
            _, _, pw, ph = render(renderer, path, OUT / f"{name}.png", round(box[2] * density), round(box[3] * density))
            print(f"{name:22s} {pw}x{ph}")
        meter(renderer, source, boxes[METER], FULL_WIDTH / whole_width, scratch)
        logo = re.search(r'viewBox="([^"]+)"', LOGO.read_text()).group(1).split()
        _, _, lw, lh = render(renderer, LOGO, LOGO_OUT, LOGO_WIDTH, round(LOGO_WIDTH * float(logo[3]) / float(logo[2])))
        print(f"{LOGO_OUT.stem:22s} {lw}x{lh}")
    wanted = {f"futuristic_{group}.png" for group in groups} | {f"futuristic_{METER}_frame.png"}
    for stale in OUT.glob("*.png"):
        if stale.name not in wanted:
            stale.unlink()
            print(f"removed {stale.name}")


def meter(renderer, source, box, density, scratch):
    """bar4's frame without the vector's fills, over the same box as its own render, uncropped,
    and its slots' insides as shares of it."""
    root = ET.fromstring(source)
    prune(root, METER)
    scale = float(re.search(r'<g transform="matrix\(([-\d.]+)', source).group(1))
    group = next(element for element in root.iter() if element.get("id") == METER)
    outlines, fills = meter_pieces(group)
    slots = meter_slots(outlines, fills)
    for fill in fills:
        group.remove(fill)
    root.set("viewBox", " ".join(f"{n:.2f}" for n in box))
    root.set("width", f"{box[2]:.2f}")
    root.set("height", f"{box[3]:.2f}")
    path = scratch / f"{METER}_frame.svg"
    path.write_text(re.sub(r"((?:fill|stroke|stop-color):)(#[0-9a-fA-F]{3,6})\b", grey, ET.tostring(root, encoding="unicode")))
    name = f"futuristic_{METER}_frame"
    _, _, pw, ph = render(renderer, path, OUT / f"{name}.png", round(box[2] * density), round(box[3] * density), whole=True)
    print(f"{name:22s} {pw}x{ph}")
    lines = [
        "import CoreGraphics",
        "",
        "// Written by Tools/import_futuristic.py from Futuristic_UI.svg; run it again rather than editing.",
        "",
        f"/// {METER}'s sixteen slots, left to right, each the inside of its outline, as shares of",
        f"/// `futuristic_{METER}_frame` from its top left.",
        "enum FuturisticMeter {",
        "    static let slots: [[CGPoint]] = [",
    ]
    for slot in slots:
        corners = ", ".join(f"CGPoint(x: {(x * scale - box[0]) / box[2]:.5f}, y: {(y * scale - box[1]) / box[3]:.5f})" for x, y in slot)
        lines.append(f"        [{corners}],")
    lines += ["    ]", "}", ""]
    METER_LAYOUT.write_text("\n".join(lines))


main()
