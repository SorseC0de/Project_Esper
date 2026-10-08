"""A stage drawn whole in Aseprite into its imagesets: the layers under the players flattened into
its backdrop, the layers over them into its front, by Tools/aseprite.py.

Usage: import_stage_art.py flight|kanda [...]      (no name: every stage)
"""
import os, subprocess, sys
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
        # Everything under the players but the file's [Dont_Draw] layer, which marks the red car's place and walls.
        "KAndABackdrop": ["Background Sky", "Background Houses", "Ground", "Buildings", "Signs", "Text", "Back Pillar 2",
                          "Back Pillar 1", "Cars", "Extras", "Train Support 3", "Train Support 2", "Train Support 1", "Train Tracks"],
        "KAndAFront": ["Front Pillar 2", "Front Pillar 1"],
    },
    "redcar": {
        "file": "K&A/red_car.aseprite",
        "KAndACarBody": ["Body"],
        "KAndACarWheels": ["Wheels"],
    },
}

def write(name, layers, source):
    folder = os.path.join(CATALOG, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    subprocess.run([sys.executable, ASEPRITE, source, os.path.join(folder, name + ".png")] + layers, check=True)
    contents = os.path.join(folder, "Contents.json")
    if not os.path.exists(contents):
        open(contents, "w").write('{\n  "images": [\n    {\n      "filename": "%s.png",\n      "idiom": "universal",\n      "scale": "1x"\n    }\n  ],\n  "info": {\n    "author": "xcode",\n    "version": 1\n  }\n}\n' % name)
    print(f"{name}: {len(layers)} layers")

def main():
    names = sys.argv[1:] or list(STAGES)
    for stage in names:
        plan = STAGES[stage]
        source = os.path.join(ART, plan["file"])
        for name, layers in plan.items():
            if name != "file":
                write(name, layers, source)

if __name__ == "__main__":
    main()
