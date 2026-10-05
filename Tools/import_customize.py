#!/usr/bin/env python3
"""Brings `_Graphic Assets/Vectors/Customize_Screen.svg` in as the customize screen's layers.

Each layer is the vector with only its named groups left, recoloured, rendered whole by
macOS's own SVG renderer (render_svg.swift) and cropped to what's drawn, into
`ProjectEsper/UI/Customize`. Where each crop sits is written to CustomizeLayout.swift as a
share of the whole screen. Everything but the halos is recoloured to the menus' colours
(MENU); the halos go to greys, light where the vector is bright, for the game to multiply by
a player's energy colour. Run from the project root after the vector changes.
"""
import pathlib
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "_Graphic Assets" / "Vectors" / "Customize_Screen.svg"
OUT = ROOT / "ProjectEsper" / "UI" / "Customize"
LAYOUT = ROOT / "ProjectEsper" / "View" / "CustomizeLayout.swift"
RENDERER = ROOT / "Tools" / "render_svg.swift"
# The whole screen's render, 16:9.
WIDTH, HEIGHT = 2560, 1440

SVG = "http://www.w3.org/2000/svg"
for prefix, uri in {"": SVG, "xlink": "http://www.w3.org/1999/xlink", "serif": "http://www.serif.com/"}.items():
    ET.register_namespace(prefix, uri)

# The vector's colours, each to one of EsperPalette's, lightest to darkest: the cyans and
# blues to purple's ramp, the deep blues to plum's, the near-black to black's.
MENU = {
    "#00ffff": "#b66bff", "#3fa9f5": "#b66bff",          # purple highlight
    "#00bef9": "#9f45f5",                                 # purple light
    "#1e87d6": "#8d36e0", "#357fd3": "#8d36e0", "#307ac3": "#8d36e0",  # purple body
    "#23549a": "#4d14a3",                                 # purple shadow, the menus' ground
    "#354e77": "#6d417d", "#2f5677": "#6d417d",          # plum light
    "#003d79": "#572c66", "#1b1464": "#3d1d52",          # plum body, shadow
    "#1b364d": "#262634", "#041121": "#0b0b12",          # black light, shadow
}

# Taken as they are: the top line in gold's second (the menus' orange), the bottom in blue's
# second (the cyan), RETURN's lettering and frame in blue's first.
TOP_LINE, BOTTOM_LINE, RETURN_CYAN = "#f5bb45", "#45bcf5", "#6bd0ff"
KEPT = {TOP_LINE, BOTTOM_LINE, RETURN_CYAN}
# RETURN's own: its cyan to blue's first, the rest as the menus'.
RETURN = {"#00ffff": RETURN_CYAN}
# The small boxes' fill, the skin's, the arms' and the legs': blue's second (the cyan) in the
# middle out to its last.
SMALL_BOX = {"#307ac3": "#45bcf5", "#23549a": "#1468a3"}
# A box's line, thickened for the cursor: a stroke this wide along it, in the vector's units.
LIT_LINE_WIDTH = 8

# name: (groups kept, recolour, part). A player's groups end in "" for P1 and "1" for P2. A box
# and a display are a fill and a line over it: "fill" keeps the group's first shape, "line" its
# second, "lit" its second thickened. Lines and the display's bar come out white, for the game
# to multiply by a colour.
LAYERS = {
    "customize_ground": (["Bg", "Lines", "Heading"], "menu", None),
    "customize_return": (["Return-Button"], "return", None),
    "customize_start": (["Start-Button"], "menu", None),
    "customize_spin_ccw": (["RotateMeCCW"], "menu", None),
    "customize_spin_cw": (["RotateMeCW"], "menu", None),
}
for player, suffix in ((1, ""), (2, "1")):
    for box, group in (("skin", "Skin"), ("arms", "Arms"), ("legs", "Legs"), ("hood", "HOOD")):
        LAYERS[f"customize_p{player}_{box}"] = ([group + suffix], "menu" if box == "hood" else "small", "fill")
        LAYERS[f"customize_p{player}_{box}_line"] = ([group + suffix], "white", "line")
        LAYERS[f"customize_p{player}_{box}_lit"] = ([group + suffix], "white", "lit")
    LAYERS[f"customize_p{player}_halo"] = ([f"Halo{suffix}"], "energy", None)
    LAYERS[f"customize_p{player}_display"] = ([f"Bottom-Display{suffix}"], "menu", "fill")
    LAYERS[f"customize_p{player}_display_bar"] = ([f"Bottom-Display{suffix}"], "white", "line")
LAYER_IDS = {group for groups, _, _ in LAYERS.values() for group in groups}
DEFINITIONS = {f"{{{SVG}}}{tag}" for tag in ("defs", "linearGradient", "radialGradient")}


def expand(colour):
    colour = colour.lower()
    if len(colour) == 4:
        colour = "#" + "".join(c * 2 for c in colour[1:])
    return colour


def menu(colour):
    colour = expand(colour)
    if colour in KEPT:
        return colour
    if colour not in MENU:
        raise SystemExit(f"{colour} has no menu colour: add it to MENU")
    return MENU[colour]


def grey(colour):
    """As bright as the colour's strongest channel, so the vector's brightest is white."""
    colour = expand(colour)
    value = max(int(colour[i:i + 2], 16) for i in (1, 3, 5))
    return f"#{value:02x}{value:02x}{value:02x}"


def recolour(text, mode):
    change = {"menu": menu, "energy": grey, "white": lambda colour: "#ffffff",
              "small": lambda colour: SMALL_BOX.get(expand(colour)) or menu(colour),
              "return": lambda colour: RETURN.get(expand(colour)) or menu(colour)}[mode]
    return re.sub(r"((?:fill|stroke|stop-color):)(#[0-9a-fA-F]{3,6})\b", lambda m: m.group(1) + change(m.group(2)), text)


def keep_part(root, group, part):
    """A box's or display's fill alone, its line alone, or its line thickened."""
    for element in root.iter(f"{{{SVG}}}g"):
        if element.get("id") != group:
            continue
        shapes = list(element)
        for index, shape in enumerate(shapes):
            if index != (0 if part == "fill" else 1):
                element.remove(shape)
        if part == "lit":
            for path in shapes[1].iter(f"{{{SVG}}}path"):
                path.set("style", path.get("style") + f"stroke:#ffffff;stroke-width:{LIT_LINE_WIDTH};stroke-linejoin:round;")


def colour_lines(root):
    """The lines' top half, over the middle of the screen, and their bottom half, each its own colour."""
    for lines in root.iter(f"{{{SVG}}}g"):
        if lines.get("id") != "Lines":
            continue
        for piece in lines:
            down = float(re.findall(r"[-\d.e]+", piece.get("transform", "matrix(1,0,0,1,0,0)"))[-1])
            colour = TOP_LINE if down < 1080 else BOTTOM_LINE
            for shape in piece.iter():
                if shape.get("style"):
                    shape.set("style", re.sub(r"fill:#[0-9a-fA-F]{3,6}", f"fill:{colour}", shape.get("style")))


def contains(element, keep):
    return element.get("id") in keep or any(contains(child, keep) for child in element)


def prune(element, keep, inside):
    """Only the kept groups, what's in them and what holds them, and the gradients; another
    layer's group goes even inside a kept one."""
    for child in list(element):
        group = child.get("id")
        if inside and group in LAYER_IDS and group not in keep:
            element.remove(child)
        elif inside or group in keep:
            prune(child, keep, True)
        elif contains(child, keep):
            # Holding a kept group, as Start-Button holds the rings: only the kept group stays.
            prune(child, keep, False)
        elif child.tag not in DEFINITIONS:
            element.remove(child)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = SOURCE.read_text()
    frames = {}
    with tempfile.TemporaryDirectory() as scratch:
        renderer = pathlib.Path(scratch) / "render_svg"
        subprocess.run(["swiftc", "-O", str(RENDERER), "-o", str(renderer)], check=True)
        for name, (keep, mode, part) in LAYERS.items():
            tree = ET.ElementTree(ET.fromstring(source))
            prune(tree.getroot(), set(keep), False)
            colour_lines(tree.getroot())
            if part:
                keep_part(tree.getroot(), keep[0], part)
            path = pathlib.Path(scratch) / f"{name}.svg"
            path.write_text(recolour(ET.tostring(tree.getroot(), encoding="unicode"), mode))
            crop = subprocess.run([str(renderer), str(path), str(OUT / f"{name}.png"), str(WIDTH), str(HEIGHT)],
                                  capture_output=True, text=True, check=True).stdout.split()
            x, y, w, h = map(int, crop)
            frames[name] = (x / WIDTH, y / HEIGHT, w / WIDTH, h / HEIGHT)
            print(f"{name:28s} {w}x{h} at ({x}, {y})")
    wanted = {f"{name}.png" for name in LAYERS}
    for stale in OUT.glob("*.png"):
        if stale.name not in wanted:
            stale.unlink()
            print(f"removed {stale.name}")

    lines = [
        "import CoreGraphics",
        "",
        "// Written by Tools/import_customize.py from Customize_Screen.svg; run it again rather than editing.",
        "",
        "/// Where each of the customize screen's layers sits, as a share of the whole 16:9 screen",
        "/// from its top left.",
        "enum CustomizeLayout {",
        f"    static let aspect: CGFloat = {WIDTH} / {HEIGHT}",
        "    static let frames: [String: CGRect] = [",
    ]
    for name, (x, y, w, h) in frames.items():
        lines.append(f"        \"{name}\": CGRect(x: {x:.5f}, y: {y:.5f}, width: {w:.5f}, height: {h:.5f}),")
    lines += ["    ]", "}", ""]
    LAYOUT.write_text("\n".join(lines))


main()
