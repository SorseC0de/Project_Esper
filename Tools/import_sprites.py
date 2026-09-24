#!/usr/bin/env python3
"""Imports the player and effect sprites into the SpriteKit atlas.

Two sources. GMS2 keeps each frame as its own PNG beside the sprite's .yy, in the order
the .yy lists. Newer sheets come as vertical strips in `_Graphic Assets`, one square
frame under another, and a strip overrides the GMS2 sprite of the same name; the effect
sheets (esper_spark, lightning, esper_charge) are strips too, grayscale, toned per player
in the app. A strip in REDUCE was rendered big and is boxed down by its factor. Both go
into Assets.xcassets/Sprites.spriteatlas as one imageset per frame, named
<sprite>_<frame> with the spr_ prefix dropped, and the tool prints the table the sim's
Animation enum has to agree with. It also writes BallLandmarks.swift into the sim: where
the ball (the sheets' pure white) sits in each player frame, so the rules can know where
a dribble is. The ball itself lives at the catalog's root, outside the atlas, and is left
alone. The sheets' white is the ball only on the sheets in BALL_SHEETS, and there only
where it's the biggest blob of white in the frame and at least BALL_MIN_PIXELS; the rest
of the white is energy, the skid's puffs, a release's streaks, the slide's speed lines,
which the app draws in the team colour. The sim's Animation.holdsBall and SpriteLibrary
apply the same rule. Run it again whenever the art changes.
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
STRIPS = os.path.join(os.path.dirname(__file__), "..", "_Graphic Assets", "Pixel Art")
ATLAS = os.path.join(os.path.dirname(__file__), "..", "ProjectEsper", "Assets.xcassets", "Sprites.spriteatlas")
LANDMARKS = os.path.join(os.path.dirname(__file__), "..", "EsperSim", "Sources", "EsperSim", "BallLandmarks.swift")
EFFECT_SHEETS = os.path.join(os.path.dirname(__file__), "..", "ProjectEsper", "Art", "EffectSheets.swift")
FEET_FROM_BOTTOM_BY_SIZE = {48: 8, 64: 16}
STRIP_FPS = 15
BALL_MIN_PIXELS = 12
# Strips rendered at a multiple of their playing size, boxed down by this factor. The
# charge is a 512px soft render whose swirl fills the middle 150.
REDUCE = {"esper_charge": 4, "flashspark": 4}
# Strips whose frames aren't square: their frame height, after any reduction. The
# flash's 256x144 frames come down to 64x36.
FRAME_HEIGHT = {"flashspark": 36}
BALL_SHEETS = {"player_dribble_idle", "player_dribble_walk", "player_dribble_run", "player_air_ball",
               "player_wall_land_ball", "player_shoot", "player_shoot_air", "player_throw_forward",
               "player_catch", "player_catch_air", "player_skid_ball", "player_taunt", "player_dunk"}

SKIP = {"Sprite22", "Sprite22_1", "sprite1", "sprite2", "sprite2_1",
        "spr_ball", "spr_ball_bak", "spr_player_shoot_BAK", "spr_player_mask", "spr_diamond",
        "spr_box", "spr_floor"}


def load_yy(path):
    text = open(path).read()
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text)


def read_png(path):
    """Pixels of a PNG as rows of bytes, with the colour type and bytes per pixel. An
    indexed PNG comes back expanded to RGBA (colour type 6), whatever its bit depth."""
    data = open(path, "rb").read()
    pos, idat, width, height, ctype, depth = 8, b"", 0, 0, 0, 8
    palette, transparency = b"", b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind, chunk = data[pos + 4:pos + 8], data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, ctype = struct.unpack(">IIBB", chunk[:10])
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"PLTE":
            palette = chunk
        elif kind == b"tRNS":
            transparency = chunk
    raw = zlib.decompress(idat)
    channels = {6: 4, 2: 3, 0: 1, 4: 2, 3: 1}[ctype]
    bpp = max(channels * depth // 8, 1)
    stride = (width * channels * depth + 7) // 8
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
    if ctype != 3:
        return width, height, ctype, bpp, rows
    # Indexed: look each index up, with tRNS giving the alphas it lists.
    expanded = []
    for line in rows:
        out = bytearray(width * 4)
        for x in range(width):
            if depth == 8:
                index = line[x]
            else:
                per_byte = 8 // depth
                index = (line[x // per_byte] >> (8 - depth * (x % per_byte + 1))) & ((1 << depth) - 1)
            out[x * 4:x * 4 + 3] = palette[index * 3:index * 3 + 3]
            out[x * 4 + 3] = transparency[index] if index < len(transparency) else 255
        expanded.append(bytes(out))
    return width, height, 6, 4, expanded


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


def box_down(width, height, bpp, rows, factor):
    """RGBA rows averaged over factor-by-factor boxes, the colour weighted by alpha."""
    out_width, out_height = width // factor, height // factor
    out = []
    for oy in range(out_height):
        line = bytearray(out_width * 4)
        source = rows[oy * factor:(oy + 1) * factor]
        for ox in range(out_width):
            r = g = b = a = 0
            for row in source:
                for x in range(ox * factor, (ox + 1) * factor):
                    px = row[x * bpp:x * bpp + bpp]
                    alpha = px[3] if bpp == 4 else 255
                    r += px[0] * alpha
                    g += px[1] * alpha
                    b += px[2] * alpha
                    a += alpha
            if a:
                line[ox * 4:ox * 4 + 4] = bytes((r // a, g // a, b // a, a // (factor * factor)))
        out.append(bytes(line))
    return out_width, out_height, out


def ball_centre(width, height, bpp, rows, feet_from_bottom):
    """The ball's centre in art pixels from the feet, or None: the biggest 8-connected blob
    of white, if it's at least BALL_MIN_PIXELS."""
    white = []
    for y, row in enumerate(rows):
        for x in range(width):
            px = row[x * bpp:x * bpp + bpp]
            if bpp == 4 and px[3] < 128:
                continue
            if px[0] == 255 and px[1] == 255 and px[2] == 255:
                white.append((x, y))
    remaining, blobs = set(white), []
    for start in white:
        if start not in remaining:
            continue
        remaining.discard(start)
        stack, blob = [start], []
        while stack:
            x, y = stack.pop()
            blob.append((x, y))
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    neighbour = (x + dx, y + dy)
                    if neighbour in remaining:
                        remaining.discard(neighbour)
                        stack.append(neighbour)
        blobs.append(blob)
    if not blobs:
        return None
    ball = max(blobs, key=len)
    if len(ball) < BALL_MIN_PIXELS:
        return None
    sx = sum(x + 0.5 for x, _ in ball) / len(ball)
    sy = sum(y + 0.5 for _, y in ball) / len(ball)
    return (sx - width / 2, height - sy - feet_from_bottom)


def sheet_facts(short, width, height, bpp, rows):
    """How an effect sheet's frames are placed and painted: their count, whether the art
    sits on the cell's bottom edge, on the player's feet line, or centred (the anchor's y
    as a share of the cell), and whether it's grey, to be toned in the energy colour."""
    # Measured on the sheet as delivered: FRAME_HEIGHT is after any reduction, so scale it back up.
    cell = FRAME_HEIGHT[short] * REDUCE.get(short, 1) if short in FRAME_HEIGHT else width
    count = max(1, height // cell)
    bottoms, grey = [], True
    for frame in range(count):
        # Only pixels with alpha count; a sheet without an alpha channel is all art.
        def painted(y, x):
            return bpp < 4 or rows[y][x * bpp + 3] > 0
        ys = [y for y in range(frame * cell, min((frame + 1) * cell, height)) if any(painted(y, x) for x in range(0, width))]
        if ys:
            bottoms.append((frame + 1) * cell - 1 - max(ys))
        for y in range(frame * cell, min((frame + 1) * cell, height), 3):
            for x in range(0, width, 3):
                if not painted(y, x):
                    continue
                p = rows[y][x * bpp:(x + 1) * bpp]
                if not (p[0] == p[1] == p[2]):
                    grey = False
    # Where the art sits, by the frame in the middle of the sorted gaps, so a burst that
    # touches the edge in one frame still reads as centred.
    typical = sorted(bottoms)[len(bottoms) // 2] if bottoms else 0
    feet = FEET_FROM_BOTTOM_BY_SIZE.get(width, 8)
    if typical <= 1:
        anchor = 0.0
    elif abs(typical - feet) <= 1:
        anchor = feet / cell
    else:
        anchor = 0.5
    return {"frames": count, "anchor": anchor, "grey": grey}


def write_effect_sheets(effects):
    """EffectSheets.swift: what the app needs to know about each effect strip."""
    lines = ["import CoreGraphics", "",
             "/// The effect strips as the importer measured them: frames a sheet, where its art sits",
             "/// in the cell (0 on the bottom edge, the feet line's share, or 0.5 centred), and which",
             "/// are grey, to be toned in the player's energy colour. Generated by",
             "/// Tools/import_sprites.py; don't edit.",
             "enum EffectSheets {",
             "    static let frames: [String: Int] = ["]
    for name in sorted(effects):
        lines.append(f"        \"{name}\": {effects[name]['frames']},")
    lines += ["    ]", "", "    static let anchorY: [String: CGFloat] = ["]
    for name in sorted(effects):
        lines.append(f"        \"{name}\": {effects[name]['anchor']:.4f},")
    lines += ["    ]", "", "    static let toned: Set<String> = ["]
    for name in sorted(effects):
        if effects[name]["grey"]:
            lines.append(f"        \"{name}\",")
    lines += ["    ]", "}", ""]
    with open(EFFECT_SHEETS, "w") as out:
        out.write("\n".join(lines))


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
            if short in BALL_SHEETS:
                width, height, _, bpp, rows = read_png(source)
                centre = ball_centre(width, height, bpp, rows, FEET_FROM_BOTTOM_BY_SIZE.get(height, 8))
                if centre:
                    landmarks.append((f"{short}_{index}", centre))
        sequence = sprite["sequence"]
        table[short] = (sprite["width"], sprite["height"], len(frames),
                        sequence["xorigin"], sequence["yorigin"], sequence["playbackSpeed"])

    effects = {}
    for strip in sorted(glob.glob(os.path.join(STRIPS, "*.png"))):
        # Exports arrive in whatever case the tool gave them; the atlas is lower case.
        short = os.path.splitext(os.path.basename(strip))[0].lower()
        if " " in short:
            print(f"skipped {short!r}: not a sheet name")
            continue
        width, height, ctype, bpp, rows = read_png(strip)
        if not short.startswith("player_"):
            effects[short] = sheet_facts(short, width, height, bpp, rows)
        if short in REDUCE:
            width, height, rows = box_down(width, height, bpp, rows, REDUCE[short])
            ctype, bpp = 6, 4
        size = width
        tall = FRAME_HEIGHT.get(short, size)
        count = height // tall
        feet = FEET_FROM_BOTTOM_BY_SIZE.get(size, 8)
        landmarks = [mark for mark in landmarks if not mark[0].startswith(short + "_")]
        for index in range(count):
            frame_rows = rows[index * tall:(index + 1) * tall]
            write_imageset(short, index, png_writer=lambda path, r=frame_rows: write_png(path, size, tall, ctype, r))
            if short in BALL_SHEETS:
                centre = ball_centre(size, tall, bpp, frame_rows, feet)
                if centre:
                    landmarks.append((f"{short}_{index}", centre))
        table[short] = (size, tall, count, size // 2, tall - feet, STRIP_FPS)
        print(f"strip  {short}: {count} frames of {size}x{tall}px")

    write_effect_sheets(effects)
    print(f"\n{'sprite':26s} size    frames origin   fps  ball")
    for short in sorted(table):
        width, height, count, ox, oy, fps = table[short]
        print(f"{short:26s} {width}x{height:<4d} {count:3d}   ({ox},{oy})  {fps:<4g} {'ball' if short in BALL_SHEETS else ''}")
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
