"""Reading and writing PNGs without an image library: 8-bit, non-interlaced, any colour type in, RGBA out."""
import zlib, struct
def read_png(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, plte, trns = 8, b"", None, None
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos+8]); body = data[pos+8:pos+8+length]; pos += 12 + length
        if kind == b"IHDR": w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT": idat += body
        elif kind == b"PLTE": plte = [tuple(body[i:i+3]) for i in range(0, len(body), 3)]
        elif kind == b"tRNS": trns = body
    assert depth == 8 and interlace == 0, (depth, interlace)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat); stride = w * channels; rows = []; prev = bytearray(stride); i = 0
    for _ in range(h):
        f = raw[i]; line = bytearray(raw[i+1:i+1+stride]); i += 1 + stride
        for x in range(stride):
            a = line[x-channels] if x >= channels else 0; b = prev[x]; c = prev[x-channels] if x >= channels else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line); prev = line
    px = []
    for line in rows:
        for x in range(w):
            v = line[x*channels:(x+1)*channels]
            if ctype == 6: px.append(tuple(v))
            elif ctype == 2: px.append((v[0], v[1], v[2], 255))
            elif ctype == 3: r, g, b = plte[v[0]]; px.append((r, g, b, trns[v[0]] if trns and v[0] < len(trns) else 255))
            elif ctype == 4: px.append((v[0], v[0], v[0], v[1]))
            else: px.append((v[0], v[0], v[0], 255))
    return w, h, px


def write_png(path, w, h, pixels):
    """Pixels as (r, g, b, a) rows top to bottom, written as 8-bit RGBA."""
    raw = bytearray()
    for y in range(h):
        raw += b"\x00"
        for x in range(w):
            raw += bytes(pixels[y * w + x])
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                  + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
