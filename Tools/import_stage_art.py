"""A stage drawn whole in Aseprite into its imagesets: the layers under the players flattened into
its backdrop, the layers over them into its front, by Tools/aseprite.py.

A dict in place of a list, {"layers": [...], "only": 0xRRGGBB}, is those layers' pixels of the one
colour alone (or of any of a list of them), in white: what the game tints (the Wreck Center's
possession colours). "under": True or False keeps only the ones under or out from under the
stage's darkening wash. {"layers": [...], "except": [0xRRGGBB, ...]} is those layers but the pixels
of those colours. {"layers": [one], "cel": True} is that layer cut to its cel's rows, the
canvas's whole width, for a picture laid again beside itself (Anozira's sliding layers: Aseprite
trims a cel to what's drawn in it, which would leave a seam). {"frames": True} is every
frame of the stage's file, one under the next (its "layers" alone, if given).

A stage's "darken" names its wash layer, Aseprite's Darken blend at the layer's opacity: it's
baked into every picture drawn under it, as Aseprite draws it, since SpriteKit can't darken; and
written alone as `<Stage>Darken`, its coverage, for what the game places under it (no name: not kept).
{"layers": [...], "over": [...]} is those layers, then the "over" ones laid on them out of the wash's reach.

Usage: import_stage_art.py flight|kanda|wreck|tutorial|longball|hoopfront|redcar|anozira|anozira_car|anozira_truck|balltruck|anozira_pothole|anozira_hub|anozira_phoenix|anozira_flag|anozira_billboard [...]
       (no name: every stage)
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
    "tutorial": {
        # The Wreck Center's map again, the back wall left out (hidden in the file), one rim; an
        # opening at each end for the door (`Door.png`, 16 frames of 32 by 64 down the strip).
        "file": "Tutorial/Tutorial_Map.aseprite",
        "darken": ("Background Dimmer", "TutorialDarken"),
        "TutorialBack": ["Background"],
        "TutorialTiles": ["Tiles"],
        "TutorialTilesLit": {"layers": ["Tiles"], "only": 0x5D5D5D},
        "TutorialExtras": ["Extras", "Extras2"],
        "TutorialDoor": "Tutorial/Door.png",
    },
    "longball": {
        # The stands under the shadow (Darken, its layer), then the display strips over it; the field
        # and the goalposts the game draws (their layers hidden), and the lights over this (`LongballArt`).
        "file": "Longball Stadium/LongballStadium_Map.aseprite",
        "darken": ("Shadow [Do Not Draw]", None),
        "LongballStadiumBackdrop": {"layers": ["Background", "Tiles"], "over": ["Displays"]},
        "LongballStadiumLight": "Longball Stadium/Stadium Light.png",
        "LongballDownMarker": "Longball Stadium/DownMarker.png",
    },
    "hoopfront": {
        # The front-facing hoop, 48 by 48, on the Tutorial hub's back wall: its board, the rim's
        # back (under the ball) and its front (over it).
        "file": "Hoop_front.aseprite",
        "HoopFrontBoard": ["backboard"],
        "HoopFrontBackRim": ["back rim"],
        "HoopFrontFrontRim": ["front rim"],
    },
    "redcar": {
        "file": "K&A/red_car.aseprite",
        "KAndACarBody": ["Body"],
        "KAndACarWheels": ["Wheels"],
    },
    "anozira": {
        # The whole file, 512 by 352, the stage its [DO NOT DRAW] box: 512 by 256 at 0, 80. The
        # background and sky stand still; the mountains, rocks, sand, foreground and road each cut
        # to their rows, laid again beside themselves and slid left (`AnoziraArt`). The sky's two
        # warm colours alone in white, for the rain to turn (palette 37 and 34).
        "file": "Anozira/Anozira.aseprite",
        "AnoziraBackground": ["Background", "Sky"],
        "AnoziraSkyOrange": {"layers": ["Background", "Sky"], "only": 0xE07438},
        "AnoziraSkyYellow": {"layers": ["Background", "Sky"], "only": 0xFFC825},
        "AnoziraMountains": {"layers": ["Mountains"], "cel": True},
        "AnoziraRocks": {"layers": ["Rocks"], "cel": True},
        "AnoziraSand": {"layers": ["Sand"], "cel": True},
        "AnoziraForeground": {"layers": ["Foreground"], "cel": True},
        "AnoziraRoad": {"layers": ["Road"], "cel": True},
    },
    "anozira_car": {
        "file": "Anozira/Car_v4.aseprite",
        "AnoziraCarBody": ["Body"],
        # The body for the holder's colour, but its grey-blue frame along the bottom, which stays as painted.
        "AnoziraCarTint": {"layers": ["Body"], "except": [0x424C6E, 0x657392, 0x92A1B9]},
        "AnoziraCarWheels": ["Wheels"],
    },
    "anozira_truck": {
        # 128 by 176, each part the whole canvas so they lay over each other; the head and tail
        # lights, the body's palette 3 and 4 (used nowhere else on it), each alone in white, for the
        # holder's two colours, or grey.
        "file": "Anozira/Truck.aseprite",
        "AnoziraTruckBody": ["Body"],
        "AnoziraTruckWheels": ["Wheels"],
        "AnoziraTruckBar": ["Hoop Bar"],
        "AnoziraTruckLightsLight": {"layers": ["Body"], "only": 0xE69C69},
        "AnoziraTruckLightsDark": {"layers": ["Body"], "only": 0xBF6F4A},
    },
    "balltruck": {
        # The ball truck, any stage's that has one (Anozira's for now): 160 by 80, each part the whole
        # canvas so they lay over each other, back to front: the far wheels, the cargo door (shown
        # open once the ball's let out), the cargo, the near wheels, the body.
        "file": "Anozira/BallTruck.aseprite",
        "BallTruckWheelsBack": ["Wheels Back"],
        "BallTruckDoor": ["Cargo Door"],
        "BallTruckCargo": ["Cargo"],
        "BallTruckWheelsFront": ["Wheels Front"],
        "BallTruckBody": ["Body"],
    },
    "anozira_pothole": {
        "file": "Anozira/pothole.aseprite",
        "AnoziraPothole": ["Layer 1"],
    },
    "anozira_hub": {
        # Over the near wheels of the car and the trucks, turning: any vehicle's.
        "file": "Anozira/Car_v4.aseprite",
        "WheelHub": "Anozira/wheel_hub.png",
    },
    "anozira_phoenix": {
        # 48 by 32, six frames down each strip: the tail's ring's back, under the ball; the bird; the
        # ring's front, over the ball.
        "file": "Anozira/Phoenix.aseprite",
        "AnoziraPhoenixRing": {"frames": True, "layers": ["Hoop"]},
        "AnoziraPhoenix": {"frames": True, "layers": ["Phoenix"]},
        "AnoziraPhoenixFront": {"frames": True, "layers": ["Front Rim"]},
    },
    "anozira_flag": {
        "file": "Anozira/flag.aseprite",
        "AnoziraFlag": {"frames": True},
    },
    "anozira_billboard": {
        # The roadside billboard, its 126 by 62 face blank, and the five ads for it.
        "file": "Anozira/Billboard.png",
        "AnoziraBillboard": "Anozira/Billboard.png",
        "AnoziraAd1": "Anozira/ad1.png",
        "AnoziraAd2": "Anozira/ad2.png",
        "AnoziraAd3": "Anozira/ad3.png",
        "AnoziraAd4": "Anozira/ad4.png",
        "AnoziraAd5": "Anozira/ad5.png",
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
    elif isinstance(layers, dict) and layers.get("frames"):
        out = os.path.join(folder, name + ".png")
        subprocess.run([sys.executable, ASEPRITE, "--frames", source, out] + layers.get("layers", []), check=True)
        layers = ["every frame"]
    elif isinstance(layers, dict) and layers.get("except"):
        out = os.path.join(folder, name + ".png")
        subprocess.run([sys.executable, ASEPRITE, source, out] + layers["layers"], check=True)
        w, h, px = read_png(out)
        cut = layers["except"]
        write_png(out, w, h, [(0, 0, 0, 0) if p[3] and (p[0] << 16 | p[1] << 8 | p[2]) in cut else p for p in px])
        layers = layers["layers"]
    elif isinstance(layers, dict) and layers.get("cel"):
        out = os.path.join(folder, name + ".png")
        subprocess.run([sys.executable, ASEPRITE, source, out] + layers["layers"], check=True)
        import aseprite
        doc = aseprite.read(source)
        index = next(i for i, l in enumerate(doc["layers"]) if l["name"] == layers["layers"][0])
        cel = next(c for c in doc["cels"] if c["layer"] == index)
        w, h, px = read_png(out)
        # Its rows within the canvas (a cel can run off it), the canvas's whole width.
        left, top = 0, max(cel["y"], 0)
        cw, ch = w, min(cel["y"] + cel["h"], h) - top
        write_png(out, cw, ch, [px[(top + row) * w + left + col] for row in range(ch) for col in range(cw)])
        print(f"{name}: its cel {cw} by {ch} at {left}, {top}")
        layers = layers["layers"]
    elif isinstance(layers, dict) and layers.get("over"):
        out = os.path.join(folder, name + ".png")
        subprocess.run([sys.executable, ASEPRITE, source, out] + layers["layers"], check=True)
        w, h, px = read_png(out)
        if wash is not None:
            px = [darken(p[:3], wash[i][:3], wash[i][3]) + (p[3],) if p[3] and wash[i][3] else p for i, p in enumerate(px)]
        subprocess.run([sys.executable, ASEPRITE, source, out] + layers["over"], check=True)
        top = read_png(out)[2]
        def lay(under, over):
            a = over[3] / 255
            if a == 0: return under
            alpha = over[3] + under[3] * (1 - a)
            return tuple(int(round((o * over[3] + u * under[3] * (1 - a)) / alpha)) for o, u in zip(over[:3], under[:3])) + (int(round(alpha)),)
        write_png(out, w, h, [lay(u, o) for u, o in zip(px, top)])
        layers = layers["layers"] + layers["over"]
    elif isinstance(layers, dict):
        out = os.path.join(folder, name + ".png")
        subprocess.run([sys.executable, ASEPRITE, source, out] + layers["layers"], check=True)
        w, h, px = read_png(out)
        only = layers["only"] if isinstance(layers["only"], list) else [layers["only"]]
        under = layers.get("under")
        def kept(i):
            return under is None or wash is None or (wash[i][3] > 0) == under
        write_png(out, w, h, [(255, 255, 255, 255) if p[3] and (p[0] << 16 | p[1] << 8 | p[2]) in only and kept(i) else (0, 0, 0, 0)
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
            sys.path.insert(0, os.path.dirname(__file__))
            from pngio import read_png
            # Its own colour at the layer's opacity, as the flattener leaves it.
            if name:
                write(name, [layer], source)
                wash = read_png(os.path.join(CATALOG, name + ".imageset", name + ".png"))[2]
            else:
                import tempfile
                out = os.path.join(tempfile.mkdtemp(), "wash.png")
                subprocess.run([sys.executable, ASEPRITE, source, out, layer], check=True)
                wash = read_png(out)[2]
        for name, layers in plan.items():
            if name not in ("file", "darken"):
                write(name, layers, source, wash)

if __name__ == "__main__":
    main()
