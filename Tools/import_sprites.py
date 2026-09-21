#!/usr/bin/env python3
"""Imports the GMS2 sprite frames into the SpriteKit atlas.

GMS2 keeps each frame as its own PNG beside the sprite's .yy, in the order the .yy lists.
This copies them into Assets.xcassets/Sprites.spriteatlas as one imageset per frame, named
<sprite>_<frame> with the spr_ prefix dropped, and prints the table the sim's Animation
enum has to agree with. Run it again whenever the art changes in GMS2.
"""
import glob
import json
import os
import re
import shutil
import sys

GMS2_PROJECT = os.path.expanduser("~/GameMakerStudio2/Project Esper")
ATLAS = os.path.join(os.path.dirname(__file__), "..", "ProjectEsper", "Assets.xcassets", "Sprites.spriteatlas")

SKIP = {"Sprite22", "Sprite22_1", "sprite1", "sprite2", "sprite2_1",
        "spr_ball_bak", "spr_player_shoot_BAK", "spr_player_mask", "spr_diamond",
        "spr_box", "spr_floor"}


def load_yy(path):
    text = open(path).read()
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text)


def main():
    if os.path.isdir(ATLAS):
        shutil.rmtree(ATLAS)
    os.makedirs(ATLAS)
    json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(ATLAS, "Contents.json"), "w"), indent=2)

    rows = []
    for folder in sorted(glob.glob(os.path.join(GMS2_PROJECT, "sprites", "*"))):
        yy = glob.glob(os.path.join(folder, "*.yy"))
        if not yy:
            continue
        sprite = load_yy(yy[0])
        name = sprite["name"]
        if name in SKIP:
            continue
        short = name[4:] if name.startswith("spr_") else name
        frames = [frame["name"] for frame in sprite["frames"]]
        for index, frame in enumerate(frames):
            imageset = os.path.join(ATLAS, f"{short}_{index}.imageset")
            os.makedirs(imageset)
            png = f"{short}_{index}.png"
            shutil.copy(os.path.join(folder, frame + ".png"), os.path.join(imageset, png))
            json.dump({"images": [{"filename": png, "idiom": "universal", "scale": "1x"}],
                       "info": {"author": "xcode", "version": 1}},
                      open(os.path.join(imageset, "Contents.json"), "w"), indent=2)
        sequence = sprite["sequence"]
        rows.append((short, sprite["width"], sprite["height"], len(frames),
                     sequence["xorigin"], sequence["yorigin"], sequence["playbackSpeed"]))

    print(f"{'sprite':26s} size    frames origin   fps")
    for short, width, height, count, ox, oy, fps in rows:
        print(f"{short:26s} {width}x{height:<4d} {count:3d}   ({ox},{oy})  {fps:g}")
    print(f"\n{sum(row[3] for row in rows)} frames into {ATLAS}")


if __name__ == "__main__":
    sys.exit(main())
