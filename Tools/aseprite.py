"""Reading an .aseprite file without Aseprite: the layers, and the frame flattened to RGBA.

Usage: aseprite.py file.aseprite            lists the layers (visible, opacity, blend, cel sizes)
       aseprite.py file.aseprite out.png [layer ...]   flattens the first frame; named layers only, if given
       aseprite.py --frames file.aseprite out.png [layer ...]   every frame flattened (named layers only, if
                                                given), one under the next, in a strip
Visible layers only, in their stacking order; normal blending with each layer's and cel's opacity;
32-bit RGBA, 16-bit grayscale and indexed (8-bit, index 0 clear) pixels; compressed, raw and linked cels.
"""
import struct, sys, zlib
sys.path.insert(0, __import__("os").path.dirname(__file__))
from pngio import write_png

def read(path, want=0):
    data = open(path, "rb").read()
    size, magic, frames, w, h, depth, flags, _, _, _, transparent, ncolors = struct.unpack("<IHHHHHIHIIB3xH", data[:34])
    assert magic == 0xA5E0, "not an aseprite file"
    pos = 128
    layers, palette, cels = [], [(0, 0, 0, 255)] * 256, {}
    new_palette = False
    for frame in range(frames):
        fsize, fmagic, old_chunks, _, new_chunks = struct.unpack("<IHHH2xI", data[pos:pos+16])
        assert fmagic == 0xF1FA
        chunks = new_chunks or old_chunks
        p = pos + 16
        for _ in range(chunks):
            csize, ctype = struct.unpack("<IH", data[p:p+6]); body = data[p+6:p+csize]; p += csize
            if ctype == 0x2004:
                lflags, ltype, child, _, _, blend, opacity = struct.unpack("<HHHHHHB", body[:13])
                nlen = struct.unpack("<H", body[16:18])[0]; name = body[18:18+nlen].decode("utf-8", "replace")
                layers.append(dict(name=name, visible=bool(lflags & 1), group=ltype == 1, child=child, blend=blend, opacity=opacity, ref=bool(lflags & 64)))
            elif ctype == 0x2005 and frame <= want:
                layer, x, y, opacity, kind, zindex = struct.unpack("<HhhBHh", body[:11])
                cel = dict(layer=layer, x=x, y=y, opacity=opacity, kind=kind)
                if kind in (0, 2):
                    cw, ch = struct.unpack("<HH", body[16:20]); px = body[20:]
                    if kind == 2: px = zlib.decompress(px)
                    cel.update(w=cw, h=ch, px=px)
                elif kind == 1:
                    cel["link"] = struct.unpack("<H", body[16:18])[0]
                cels[(frame, layer)] = cel
            elif ctype == 0x2019:
                new_palette = True
                n, first, last = struct.unpack("<III", body[:12]); q = 20
                for i in range(first, last + 1):
                    eflags, r, g, b, a = struct.unpack("<HBBBB", body[q:q+6]); q += 6
                    if eflags & 1: q += 2 + struct.unpack("<H", body[q:q+2])[0]
                    palette[i] = (r, g, b, a)
            elif ctype in (0x0004, 0x0011) and frame == 0 and not new_palette:
                # The old palette chunks, only without the new one: 0x0004 in 8-bit colours,
                # 0x0011 in 6-bit.
                shift = 2 if ctype == 0x0011 else 0
                n = struct.unpack("<H", body[:2])[0]; q = 2
                for _ in range(n):
                    skip, count = struct.unpack("<BB", body[q:q+2]); q += 2
                    for i in range(skip, skip + (count or 256)):
                        if i < 256: palette[i] = (body[q] << shift, body[q+1] << shift, body[q+2] << shift, 255)
                        q += 3
        pos += fsize
    # The wanted frame's cels, a linked one standing for the cel it links to in its own frame.
    wanted = []
    for (frame, layer), cel in cels.items():
        if frame != want: continue
        if cel["kind"] == 1: cel = dict(cels.get((cel["link"], layer), cel), layer=layer)
        wanted.append(cel)
    return dict(w=w, h=h, depth=depth, transparent=transparent, layers=layers, cels=wanted, palette=palette, frames=frames)

def visible(layers, index):
    """A layer shows when it and every group over it do."""
    depth = layers[index]["child"]
    for i in range(index, -1, -1):
        if layers[i]["child"] <= depth:
            if not layers[i]["visible"]: return False
            depth = layers[i]["child"] - 1
            if depth < 0: return True
    return True

def flatten(doc, only=None):
    w, h = doc["w"], doc["h"]; out = bytearray(w * h * 4)
    cels = {c["layer"]: c for c in doc["cels"]}
    for index, layer in enumerate(doc["layers"]):
        if layer["group"] or layer["ref"] or not visible(doc["layers"], index): continue
        if only and layer["name"] not in only: continue
        cel = cels.get(index)
        if cel is None: continue
        if cel["kind"] == 1: cel = cels.get(cel["link"], cel)
        if "px" not in cel: continue
        px, cw, ch = cel["px"], cel["w"], cel["h"]
        la = layer["opacity"] * cel["opacity"] / 255 / 255
        for row in range(ch):
            y = cel["y"] + row
            if not 0 <= y < h: continue
            for col in range(cw):
                x = cel["x"] + col
                if not 0 <= x < w: continue
                i = row * cw + col
                if doc["depth"] == 32: r, g, b, a = px[i*4:i*4+4]
                elif doc["depth"] == 16: r = g = b = px[i*2]; a = px[i*2+1]
                else:
                    idx = px[i]
                    if idx == doc["transparent"]: continue
                    r, g, b, a = doc["palette"][idx]
                a = a * la
                if a <= 0: continue
                o = (y * w + x) * 4; da = out[o+3] / 255; sa = a / 255
                oa = sa + da * (1 - sa)
                for k, s in enumerate((r, g, b)):
                    out[o+k] = int(round((s * sa + out[o+k] * da * (1 - sa)) / oa)) if oa else 0
                out[o+3] = int(round(oa * 255))
    return bytes(out)

if __name__ == "__main__":
    if sys.argv[1] == "--frames":
        count = read(sys.argv[2])["frames"]
        strip = []
        for frame in range(count):
            doc = read(sys.argv[2], frame)
            px = flatten(doc, sys.argv[4:] or None)
            strip += [tuple(px[i:i+4]) for i in range(0, len(px), 4)]
        write_png(sys.argv[3], doc["w"], doc["h"] * count, strip)
        sys.exit()
    doc = read(sys.argv[1])
    if len(sys.argv) < 3:
        print(f"{doc['w']}x{doc['h']} {doc['depth']}bpp")
        cels = {c["layer"]: c for c in doc["cels"]}
        for i, l in enumerate(doc["layers"]):
            cel = cels.get(i); size = f"cel {cel.get('w','?')}x{cel.get('h','?')} at {cel['x']},{cel['y']}" if cel else "no cel"
            print(f"{'  ' * l['child']}{'[group] ' if l['group'] else ''}{l['name']!r} {'shown' if visible(doc['layers'], i) else 'HIDDEN'} opacity {l['opacity']} blend {l['blend']}{' reference' if l['ref'] else ''}  {size}")
    else:
        px = flatten(doc, sys.argv[3:] or None)
        write_png(sys.argv[2], doc["w"], doc["h"], [tuple(px[i:i+4]) for i in range(0, len(px), 4)])
