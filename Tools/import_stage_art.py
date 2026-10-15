"""A stage drawn whole in Aseprite into its imagesets: the layers under the players flattened into
its backdrop, the layers over them into its front, by Tools/aseprite.py.

A dict in place of a list, {"layers": [...], "only": 0xRRGGBB}, is those layers' pixels of the one
colour alone, in white: what the game tints (the Wreck Center's possession colours). "under": True
or False keeps only the ones under or out from under the stage's darkening wash.

A stage's "darken" names its wash layer, Aseprite's Darken blend at the layer's opacity: it's
baked into every picture drawn under it, as Aseprite draws it, since SpriteKit can't darken; and
written alone as `<Stage>Darken`, its coverage, for what the game places under it.

Usage: import_stage_art.py flight|kanda|wreck [...]      (no name: every stage)
"""
import os, shutil, subprocess, sys
ROOT = os.path.join(os.path.dirname(__file__), "..")
ART = os.path.join(ROOT, "_Graphic Assets", "Pixel Art", "Stages")
CATALOG = os.path.join(ROOT, "ProjectEsper", "Assets.xcassets")
ASEPRITE = os.path.join(os.path.dirname(__file__), "aseprite.py")

STAGES = {
    "flight": {
        "file": "Flight/Flight_Map.aseprite",
        "FlightB411Backdrop": ["Tiles", "Back Fade", "Back Chairs", "Bins"],
        "FlightB411Front": ["Front Chairs", "Front Fade"],
    },
    "kanda": {
        "file": "K&A/K&A_Map.aseprite",
        # The sky alone, the clouds drifting over it (`KAndAClouds`, the file beside it, three cells
        # down), then everything else under the players but the file's [Dont_Draw] layers, which
        # mark the red car's and the broken car's places and walls; the broken car its own
        # sprite (`KAndABrokenCar`, the file beside it, three 128 by 32 frames down).
        "KAndASky": ["Background Sky"],
        "KAndAClouds": "K&A/clouds.png",
        "KAndABrokenCar": "K&A/broken_car.png",
        "KAndABackdrop": ["Background Houses", "Ground", "Buildings", "Signs", "Text", "Back Pillar 2",
                          "Back Pillar 1", "Extras", "Train Support 3", "Train Support 2", "Train Support 1", "Train Tracks"],
        "KAndAFront": ["Front Pillar 2", "Front Pillar 1"],
    },
    "wreck": {
        "file": "Wreck Center/Wreck_Center_Map.aseprite",
        # Back to front: the background and the back wall; the back wall's palette 60 alone, the
        # possession colour's; the tiles; their palette 59 alone; the extras. [DO NOT DRAW] marks
        # the court's box (544 by 256 at 16, 80: the stage one tile in from the sides and the
        # bottom) and where the animated tiles go.
        "darken": ("Background Dimmer", "WreckCenterDarken"),
        "WreckCenterBack": ["Background", "Back Wall"],
        "WreckCenterBackLit": {"layers": ["Back Wall"], "only": 0x3D3D3D, "under": False},
        "WreckCenterBackLitDarkened": {"layers": ["Back Wall"], "only": 0x3D3D3D, "under": True},
        "WreckCenterTiles": ["Tiles"],
        "WreckCenterTilesLit": {"layers": ["Tiles"], "only": 0x5D5D5D},
        "WreckCenterExtras": ["Extras", "Extras2"],
    },
    "redcar": {
        "file": "K&A/red_car.aseprite",
        "KAndACarBody": ["Body"],
        "KAndACarWheels": ["Wheels"],
    },
}

def darken(colour, wash, alpha):
    """Aseprite's Darken: each channel the darker of the two, laid over at the wash's opacity."""
    return tuple(int(round(c + (min(w, c) - c) * alpha / 255)) for c, w in zip(colour, wash))

def write(name, layers, source, wash=None):
    """Layers flattened out of the stage's file, or a picture beside it, named by its path, taken as it is;
    with a wash (its pixels), darkened under it, or a lit mask split by it."""
    sys.path.insert(0, os.path.dirname(__file__))
    from pngio import read_png, write_png
    folder = os.path.join(CATALOG, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    if isinstance(layers, str):
        shutil.copyfile(os.path.join(ART, layers), os.path.join(folder, name + ".png"))
        layers = [layers]
    elif isinstance(layers, dict):
        out = os.path.join(folder, name + ".png")
        subprocess.run([sys.executable, ASEPRITE, source, out] + layers["layers"], check=True)
        w, h, px = read_png(out)
        only = layers["only"]
        under = layers.get("under")
        def kept(i):
            return under is None or wash is None or (wash[i][3] > 0) == under
        write_png(out, w, h, [(255, 255, 255, 255) if p[3] and (p[0] << 16 | p[1] << 8 | p[2]) == only and kept(i) else (0, 0, 0, 0)
                              for i, p in enumerate(px)])
        layers = layers["layers"]
    else:
        out = os.path.join(folder, name + ".png")
        subprocess.run([sys.executable, ASEPRITE, source, out] + layers, check=True)
        if wash is not None:
            w, h, px = read_png(out)
            write_png(out, w, h, [darken(p[:3], wash[i][:3], wash[i][3]) + (p[3],) if p[3] and wash[i][3] else p for i, p in enumerate(px)])
    contents = os.path.join(folder, "Contents.json")
    if not os.path.exists(contents):
        open(contents, "w").write('{\n  "images": [\n    {\n      "filename": "%s.png",\n      "idiom": "universal",\n      "scale": "1x"\n    }\n  ],\n  "info": {\n    "author": "xcode",\n    "version": 1\n  }\n}\n' % name)
    print(f"{name}: {len(layers)} layers")

def main():
    names = sys.argv[1:] or list(STAGES)
    for stage in names:
        plan = STAGES[stage]
        source = os.path.join(ART, plan["file"])
        wash = None
        if "darken" in plan:
            layer, name = plan["darken"]
            write(name, [layer], source)
            sys.path.insert(0, os.path.dirname(__file__))
            from pngio import read_png
            # Its own colour at the layer's opacity, as the flattener leaves it.
            wash = read_png(os.path.join(CATALOG, name + ".imageset", name + ".png"))[2]
        for name, layers in plan.items():
            if name not in ("file", "darken"):
                write(name, layers, source, wash)

if __name__ == "__main__":
    main()
