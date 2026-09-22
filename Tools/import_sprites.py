#!/usr/bin/env python3
"""Imports the player and effect sprites into the SpriteKit atlas.

Two sources. GMS2 keeps each frame as its own PNG beside the sprite's .yy, in the order
the .yy lists. Newer sheets come as vertical strips in `_Graphic Assets`, one square
frame under another, and a strip overrides the GMS2 sprite of the same name. Both go
into Assets.xcassets/Sprites.spriteatlas as one imageset per frame, named
<sprite>_<frame> with the spr_ prefix dropped, and the tool prints the table the sim's
Animation enum has to agree with. It also writes BallLandmarks.swift into the sim: where
the ball (the sheets' pure white) sits in each player frame, so the rules can know where
a dribble is. The ball itself lives at the catalog's root, outside the atlas, and is left
alone. Run it again whenever the art changes.
"""
import glob
import json
import os
import re
import shutil
import struct
import sys
import zlib

GMS2_PROJECT = os.path.expanduser("~/GameMakerStudio2/Project Esper")
STRIPS = os.path.join(os.path.dirname(__file__), "..", "_Graphic Assets")
ATLAS = os.path.join(os.path.dirname(__file__), "..", "ProjectEsper", "Assets.xcassets", "Sprites.spriteatlas")
LANDMARKS = os.path.join(os.path.dirname(__file__), "..", "EsperSim", "Sources", "EsperSim", "BallLandmarks.swift")
FEET_FROM_BOTTOM_BY_SIZE = {48: 8, 64: 16}
STRIP_FPS = 15

SKIP = {"Sprite22", "Sprite22_1", "sprite1", "sprite2", "sprite2_1",
        "spr_ball", "spr_ball_bak", "spr_player_shoot_BAK", "spr_player_mask", "spr_diamond",
        "spr_box", "spr_floor"}


def load_yy(path):
    text = open(path).read()
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text)


def read_png(path):
    """Pixels of an 8-bit PNG as rows of bytes, with the colour type and bytes per pixel."""
    data = open(path, "rb").read()
    pos, idat, width, height, ctype = 8, b"", 0, 0, 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind, chunk = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, _, ctype = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
    raw = zlib.decompress(idat)
    bpp = {6: 4, 2: 3, 0: 1, 4: 2}[ctype]
    stride = width * bpp
    rows, prev, p = [], bytearray(stride), 0
    for _ in range(height):
        filt, line = raw[p], bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if filt == 1: line[i] = (line[i] + a) & 255
            elif filt == 2: line[i] = (line[i] + b) & 255
            elif filt == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif filt == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
        rows.append(bytes(line))
        prev = line
    return width, height, ctype, bpp, rows


def write_png(path, width, height, ctype, rows):
    """An 8-bit PNG of `rows`, unfiltered."""
    raw = b"".join(b"\0" + row for row in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, ctype, 0, 0, 0)))
        out.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        out.write(chunk(b"IEND", b""))


def ball_centre(width, height, bpp, rows, feet_from_bottom):
    """The white pixels' centre in art pixels from the feet, or None."""
    sx = sy = n = 0
    for y, row in enumerate(rows):
        for x in range(width):
            px = row[x * bpp:x * bpp + bpp]
            if bpp == 4 and px[3] < 128:
                continue
            if px[0] == 255 and px[1] == 255 and px[2] == 255:
                sx += x + 0.5
                sy += y + 0.5
                n += 1
    if n == 0:
        return None
    return (sx / n - width / 2, height - sy / n - feet_from_bottom)


def write_imageset(short, index, png_source=None, png_writer=None):
    """One imageset for a frame, from a file to copy or a writer that makes the PNG."""
    imageset = os.path.join(ATLAS, f"{short}_{index}.imageset")
    if os.path.isdir(imageset):
        shutil.rmtree(imageset)
    os.makedirs(imageset)
    png = f"{short}_{index}.png"
    if png_source:
        shutil.copy(png_source, os.path.join(imageset, png))
    else:
        png_writer(os.path.join(imageset, png))
    json.dump({"images": [{"filename": png, "idiom": "universal", "scale": "1x"}],
               "info": {"author": "xcode", "version": 1}},
              open(os.path.join(imageset, "Contents.json"), "w"), indent=2)


def main():
    landmarks = []
    # The atlas's own Contents.json is kept as Xcode last wrote it.
    contents_path = os.path.join(ATLAS, "Contents.json")
    contents = open(contents_path).read() if os.path.exists(contents_path) else None
    if os.path.isdir(ATLAS):
        shutil.rmtree(ATLAS)
    os.makedirs(ATLAS)
    if contents is None:
        json.dump({"info": {"author": "xcode", "version": 1}}, open(contents_path, "w"), indent=2)
    else:
        open(contents_path, "w").write(contents)

    # sprite -> (width, height, frames, xorigin, yorigin, fps); a strip replaces a GMS2 entry.
    table = {}
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
            source = os.path.join(folder, frame + ".png")
            write_imageset(short, index, png_source=source)
            if short.startswith("player_"):
                width, height, _, bpp, rows = read_png(source)
                centre = ball_centre(width, height, bpp, rows, FEET_FROM_BOTTOM_BY_SIZE.get(height, 8))
                if centre:
                    landmarks.append((f"{short}_{index}", centre))
        sequence = sprite["sequence"]
        table[short] = (sprite["width"], sprite["height"], len(frames),
                        sequence["xorigin"], sequence["yorigin"], sequence["playbackSpeed"])

    for strip in sorted(glob.glob(os.path.join(STRIPS, "*.png"))):
        short = os.path.splitext(os.path.basename(strip))[0]
        width, height, ctype, bpp, rows = read_png(strip)
        size = width
        count = height // size
        feet = FEET_FROM_BOTTOM_BY_SIZE.get(size, 8)
        landmarks = [mark for mark in landmarks if not mark[0].startswith(short + "_")]
        for index in range(count):
            frame_rows = rows[index * size:(index + 1) * size]
            write_imageset(short, index, png_writer=lambda path, r=frame_rows: write_png(path, size, size, ctype, r))
            if short.startswith("player_"):
                centre = ball_centre(size, size, bpp, frame_rows, feet)
                if centre:
                    landmarks.append((f"{short}_{index}", centre))
        table[short] = (size, size, count, size // 2, size - feet, STRIP_FPS)
        print(f"strip  {short}: {count} frames of {size}px")

    print(f"\n{'sprite':26s} size    frames origin   fps")
    for short in sorted(table):
        width, height, count, ox, oy, fps = table[short]
        print(f"{short:26s} {width}x{height:<4d} {count:3d}   ({ox},{oy})  {fps:g}")
    print(f"\n{sum(row[2] for row in table.values())} frames into {ATLAS}")

    landmarks.sort()
    with open(LANDMARKS, "w") as out:
        out.write("// Generated by Tools/import_sprites.py. Don't edit; run the tool.\n\n")
        out.write("/// Where the ball sits in each player frame that has one: art pixels from the feet,\n")
        out.write("/// facing right. From the sheets' pure white.\n")
        out.write("public enum BallLandmarks {\n")
        out.write("    public static let table: [String: Vec2] = [\n")
        for key, (x, y) in landmarks:
            out.write(f'        "{key}": Vec2(x: {x:.2f}, y: {y:.2f}),\n')
        out.write("    ]\n\n")
        out.write("    public static func offset(_ frame: AnimationFrame) -> Vec2? {\n")
        out.write('        table["\\(frame.animation.rawValue)_\\(frame.frame)"]\n')
        out.write("    }\n}\n")
    print(f"{len(landmarks)} ball landmarks into {LANDMARKS}")


if __name__ == "__main__":
    sys.exit(main())
