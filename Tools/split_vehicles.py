#!/usr/bin/env python3
"""Splits the Highway Traffic vehicles into bodies and wheels, and the helicopter into its
plain parts and its reds, as vector imagesets in the catalog's Traffic folder.

A wheel is a group of its own at the drawing's top level that starts at a tyre (#203547, or
the motorcycles' #3F4F51), as the artist grouped them; in a drawing with none, a run that
starts at a tyre, a circle filled #203547, and runs through its hub's bolts (#666E70
and #535A5B) to the first shape past them. A vehicle with neither idles whole. An export
whose every shape sits in the same `matrix(s,0,0,s,0,0)` (Affinity's DPI scale) has the
scale taken off and its viewBox divided by it, so it's the size the others are. The
helicopter's three reds each go to their own file, to be toned in the rim's owner's energy.
Run it again whenever the art changes.
"""
import glob
import json
import os
import re
import shutil

SOURCE = os.path.join(os.path.dirname(__file__), "..", "_Graphic Assets", "Vectors", "Stages", "Traffic")
FOLDER = os.path.join(os.path.dirname(__file__), "..", "ProjectEsper", "Assets.xcassets", "Traffic")
BOLTS = {"666e70", "535a5b"}
TYRES = {"203547", "3f4f51"}
HELICOPTER_REDS = ["bc043d", "990037", "7f0135"]
SHAPE = re.compile(r"<(?:path|circle|polygon|rect|ellipse)[^>]*?/>|<(?:path|circle|polygon|rect|ellipse)[^>]*?>\s*</(?:path|circle|polygon|rect|ellipse)>|<g[^>]*>|</g>", re.S)


def unscaled(src):
    """Affinity's DPI wrapper taken off: every group's matrix(s,0,0,s,0,0) dropped and the
    viewBox divided by s."""
    scales = set(re.findall(r'transform="matrix\(([\d.]+),0,0,\1,0,0\)"', src))
    if len(scales) != 1:
        return src
    scale = float(scales.pop())
    src = re.sub(r'\s*transform="matrix\([\d.]+,0,0,[\d.]+,0,0\)"', "", src)
    def divide(match):
        values = [float(v) / scale for v in match.group(1).split()]
        # The scale is rounded in the export: a value within a hair of whole is whole.
        values = [round(v) if abs(v - round(v)) < 0.01 else v for v in values]
        return 'viewBox="' + " ".join(f"{v:g}" for v in values) + '"'
    return re.sub(r'viewBox="([^"]*)"', divide, src, count=1)


def top_groups(body):
    """The drawing's top-level groups that carry no transform, as the artist grouped them."""
    found, depth, start = [], 0, None
    for match in re.finditer(r"<g[^>]*>|</g>", body):
        tag = match.group(0)
        if tag.startswith("<g"):
            if depth == 0 and "transform" not in tag:
                start = match.start()
            depth += 1
        else:
            depth -= 1
            if depth == 0 and start is not None:
                found.append((start, match.end()))
                start = None
    return found


def pieces(path):
    src = unscaled(open(path, encoding="iso-8859-1").read())
    head_end = src.index(">", src.index("<svg")) + 1
    end = src.rindex("</svg>")
    return src[:head_end], SHAPE.findall(src[head_end:end]), src[end:]


def fill(piece):
    m = re.search(r"fill:#([0-9A-Fa-f]{6})", piece)
    return m.group(1).lower() if m else None


def imageset(name, head, parts, tail):
    folder = os.path.join(FOLDER, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    open(os.path.join(folder, name + ".svg"), "w").write(head + "\n".join(parts) + tail)
    json.dump({"images": [{"filename": name + ".svg", "idiom": "universal"}],
               "info": {"author": "xcode", "version": 1},
               "properties": {"preserves-vector-representation": True}},
              open(os.path.join(folder, "Contents.json"), "w"), indent=2)


def split_helicopter(path):
    """The helicopter by its groups: the top rotor (`propeller`) and the tail rotor
    (`spin_me`) each their own, the rest apart, and within each the three reds apart from
    the plain parts, so the reds can be toned and the rotors moved."""
    import copy
    import xml.etree.ElementTree as ElementTree
    ElementTree.register_namespace("", "http://www.w3.org/2000/svg")
    ElementTree.register_namespace("serif", "http://www.serif.com/")
    ElementTree.register_namespace("xlink", "http://www.w3.org/1999/xlink")
    tree = ElementTree.parse(path)
    serif = "{http://www.serif.com/}id"

    def group_of(parents):
        for element in parents:
            name = element.get("id") or element.get(serif)
            if name in ("propeller", "spin_me"):
                return name
        return "hull"

    def keep(tree, part, red):
        kept = copy.deepcopy(tree)
        def walk(element, parents):
            for child in list(element):
                if len(child) or child.tag.endswith("}g"):
                    walk(child, parents + [child])
                    continue
                colour = (re.search(r"fill:#([0-9A-Fa-f]{6})", child.get("style", "")) or [None, ""])[1].lower()
                matches = group_of(parents) == part and ((colour == red) if red else colour not in HELICOPTER_REDS)
                if not matches:
                    element.remove(child)
        walk(kept.getroot(), [])
        return kept

    for part in ("hull", "propeller", "spin_me"):
        for index, red in enumerate([None] + HELICOPTER_REDS):
            layer = keep(tree, part, red)
            name = f"helicopter_{part}_" + ("plain" if red is None else f"red{index - 1}")
            folder = os.path.join(FOLDER, name + ".imageset")
            os.makedirs(folder, exist_ok=True)
            layer.write(os.path.join(folder, name + ".svg"), encoding="UTF-8", xml_declaration=True)
            json.dump({"images": [{"filename": name + ".svg", "idiom": "universal"}],
                       "info": {"author": "xcode", "version": 1},
                       "properties": {"preserves-vector-representation": True}},
                      open(os.path.join(folder, "Contents.json"), "w"), indent=2)
    print("helicopter: hull, top rotor and tail rotor, each plain and three reds")


def main():
    if os.path.isdir(FOLDER):
        shutil.rmtree(FOLDER)
    os.makedirs(FOLDER)
    json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(FOLDER, "Contents.json"), "w"), indent=2)
    for path in sorted(glob.glob(os.path.join(SOURCE, "*.svg"))):
        name = os.path.splitext(os.path.basename(path))[0]
        if name == "helicopter":
            split_helicopter(path)
            continue
        head, shapes, tail = pieces(path)
        # Wheels grouped by the artist in an Affinity export: each top-level group that starts
        # at a tyre, found before the DPI scale comes off (its groups are the ones without it).
        raw = open(path, encoding="iso-8859-1").read()
        inner = raw[raw.index(">", raw.index("<svg")) + 1:raw.rindex("</svg>")]
        grouped = [inner[a:b] for a, b in top_groups(inner)] if "matrix(" in raw else []
        grouped = [g for g in grouped if fill(g) in TYRES]
        if grouped:
            body_src = inner
            for g in grouped:
                body_src = body_src.replace(g, "")
            strip = lambda piece: re.sub(r'\s*transform="matrix\([\d.]+,0,0,[\d.]+,0,0\)"', "", piece)
            imageset(f"vehicle_{name}_body", head, [strip(body_src)], tail)
            imageset(f"vehicle_{name}_wheels", head, [strip(g) for g in grouped], tail)
            print(f"{name}: {len(grouped)} wheels apart, as grouped")
            continue
        wheel, body = [], []
        in_wheel, seen_bolt = False, False
        for p in shapes:
            colour = fill(p)
            if not in_wheel and p.startswith("<circle") and colour == "203547":
                in_wheel, seen_bolt = True, False
            if in_wheel:
                if colour in BOLTS:
                    seen_bolt = True
                elif seen_bolt:
                    in_wheel = False
            grouping = p.startswith("<g") or p.startswith("</g")
            (wheel if in_wheel and not grouping else body).append(p)
        imageset(f"vehicle_{name}_body", head, body, tail)
        if wheel:
            imageset(f"vehicle_{name}_wheels", head, wheel, tail)
        print(f"{name}: {'wheels apart' if wheel else 'whole'}")


main()
