#!/usr/bin/env python3
"""Splits the Highway Traffic vehicles into bodies and wheels, and the helicopter into its
plain parts and its reds, as vector imagesets in the catalog's Traffic folder.

A wheel is a run of the drawing that starts at a tyre, a circle filled #203547, and runs
through its hub's bolts (#666E70 and #535A5B) to the first shape past them. A vehicle with
no such tyre (the racer, both motorcycles) has no wheels file and idles whole. The
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
HELICOPTER_REDS = ["bc043d", "990037", "7f0135"]
SHAPE = re.compile(r"<(?:path|circle|polygon|rect|ellipse)[^>]*?/>|<(?:path|circle|polygon|rect|ellipse)[^>]*?>\s*</(?:path|circle|polygon|rect|ellipse)>|<g[^>]*>|</g>", re.S)


def pieces(path):
    src = open(path, encoding="iso-8859-1").read()
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
        head, shapes, tail = pieces(path)
        if name == "helicopter":
            split_helicopter(path)
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
