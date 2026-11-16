"""Preview sheet for the buildable pieces: the palette (every piece, both rotations) and a sample base laid out
on the tile grid the way the game places them.  python3 tools/render3d/build_preview.py -> /tmp/r3d/build_palette.png"""
import os, json, random
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPR = os.path.join(ROOT, "assets", "sprites")
AN = json.load(open(os.path.join(ROOT, "assets", "anchors.json")))
AN.update(json.load(open(os.path.join(ROOT, "assets", "rendered_anchors.json"))))
FONT = "/usr/share/fonts/truetype/dejavu/"
TIERS = ("scrap", "wood", "stone", "concrete")
PIECES = ("wall", "window", "doorway", "door", "half", "gate")
S = 3                                            # display scale (nearest neighbour, keeps the pixels crisp)


def spr(name):
    return Image.open(os.path.join(SPR, name + ".png")).convert("RGBA")


def iso(x, y, ox, oy):
    return ox + (x - y) * 24, oy + (x + y) * 12


def palette():
    f1 = ImageFont.truetype(FONT + "DejaVuSans-Bold.ttf", 13)
    f2 = ImageFont.truetype(FONT + "DejaVuSans.ttf", 11)
    cw, ch = 64, 66
    rows = [(t, PIECES) for t in TIERS] + [("fence", ("wall", "gate"))]
    W, Hh = 96 + cw * 12 + 70, 40 + ch * len(rows)
    im = Image.new("RGBA", (W, Hh), (34, 30, 26, 255)); d = ImageDraw.Draw(im)
    for j, p in enumerate(PIECES):
        d.text((96 + j * cw * 2 + cw, 12), p, font=f1, fill=(232, 220, 190), anchor="mm")
    d.text((96 + cw * 12 + 35, 12), "floor", font=f1, fill=(232, 220, 190), anchor="mm")
    for i, (t, ps) in enumerate(rows):
        y0 = 30 + i * ch
        d.text((10, y0 + ch / 2), t, font=f1, fill=(232, 220, 190), anchor="lm")
        for p in ps:
            j = PIECES.index(p)
            for k, ax in enumerate("xy"):
                s = spr("bw_%s_%s_%s" % (t, p, ax))
                x = 96 + j * cw * 2 + k * cw + (cw - 28) // 2
                im.alpha_composite(s, (x, y0))
        if t != "fence":
            im.alpha_composite(spr("bf_" + t), (96 + cw * 12 + 11, y0 + 20))
    d.text((W - 10, Hh - 8), "each piece: x-axis | y-axis rotation", font=f2, fill=(160, 150, 130), anchor="rb")
    return im


def sample_base():
    cols, rws = 12, 11
    ox, oy = 12 * 24 + 40, 60
    W, Hh = (cols + rws) * 24 + 80, (cols + rws) * 12 + 140
    im = Image.new("RGBA", (W, Hh), (0, 0, 0, 0))
    rng = random.Random(3)
    d = ImageDraw.Draw(im)
    for y in range(rws):                                              # ground: dusty tiles with a faint grid
        for x in range(cols):
            a, b, c, e = iso(x, y, ox, oy), iso(x + 1, y, ox, oy), iso(x + 1, y + 1, ox, oy), iso(x, y + 1, ox, oy)
            g = rng.randint(-6, 6)
            d.polygon([a, b, c, e], fill=(150 + g, 128 + g, 96 + g, 255), outline=(128, 108, 80, 255))
    floors, walls, props = {}, [], []
    def room(x0, y0, w, h, tier, doors=(), windows=(), floor=True):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                if floor: floors[(x, y)] = tier
        for x in range(x0, x0 + w):
            for (yy, side) in ((y0, "n"), (y0 + h, "s")):
                k = (x, yy, "x")
                walls.append((k, tier, "door" if k in doors else "window" if k in windows else "wall"))
        for y in range(y0, y0 + h):
            for xx in (x0, x0 + w):
                k = (xx, y, "y")
                walls.append((k, tier, "door" if k in doors else "window" if k in windows else "wall"))
    room(2, 2, 3, 3, "concrete", doors={(3, 5, "x")}, windows={(5, 3, "y"), (2, 3, "y")})       # stronghold
    room(5, 2, 3, 2, "wood", doors={(6, 4, "x")}, windows={(7, 2, "x")})                        # bunkhouse
    room(2, 6, 2, 2, "scrap", doors={(4, 7, "y")})                                              # storage shed
    walls[:] = [w for w in walls if not (w[0] == (5, 2, "y") and w[1] == "wood") and not (w[0] == (5, 3, "y") and w[1] == "wood")]
    # stone perimeter on the north and west, fence and a gate on the south and east
    for x in range(1, 10):
        walls.append(((x, 1, "x"), "stone", "wall" if x != 6 else "window"))
    for y in range(1, 9):
        walls.append(((1, y, "y"), "stone", "wall" if y not in (4,) else "window"))
    for x in range(1, 10):
        walls.append(((x, 9, "x"), "fence", "gate" if x == 5 else "wall"))
    for y in range(1, 9):
        walls.append(((10, y, "y"), "fence", "wall"))
    walls.append(((10, 8, "y"), "fence", "wall"))
    for (x, y) in ((6, 6), (7, 6), (8, 6)):                                    # sandbag-height barricade
        walls.append(((x, y, "x"), "concrete", "half"))
    for (x, y) in ((6, 6), (6, 7)):
        floors[(x, y)] = "stone" if (x, y) == (6, 7) else floors.get((x, y), None) or "stone"
    for k in list(floors):
        if floors[k] is None: del floors[k]
    props += [("campfire0", 7.5, 7.6), ("workbench", 6.5, 2.5), ("barrel", 3.5, 7.5), ("crate", 2.5, 6.5), ("tent", 8.3, 4.7)]
    for (x, y), t in sorted(floors.items(), key=lambda kv: kv[0][0] + kv[0][1]):
        s = spr("bf_" + t); a = AN["bf_" + t]; px, py = iso(x, y, ox, oy)
        im.alpha_composite(s, (int(px - a[0]), int(py - a[1])))
    # ghost: the piece being placed, tinted green, plus its tile edge highlighted
    gk = (8, 6, "y")
    items = [((k[0] + k[1] + 0.5), "w", k, t, p) for (k, t, p) in walls] + [((x + y), "p", (n, x, y), None, None) for (n, x, y) in props]
    items.append((gk[0] + gk[1] + 0.5, "g", gk, "wood", "wall"))
    for dep, kind, k, t, p in sorted(items, key=lambda it: it[0]):
        if kind == "p":
            n, x, y = k; s = spr(n); a = AN[n]; px, py = iso(x, y, ox, oy)
            im.alpha_composite(s, (int(px - a[0]), int(py - a[1]))); continue
        name = "bw_%s_%s_%s" % (t, p, k[2]); s = spr(name); a = AN[name]
        px, py = iso(k[0], k[1], ox, oy)
        if kind == "g":
            r, g, b, al = s.split()
            s = Image.merge("RGBA", (r.point(lambda v: v // 3), g.point(lambda v: min(255, v // 2 + 140)), b.point(lambda v: v // 3), al.point(lambda v: v * 6 // 10)))
            e0, e1 = iso(k[0], k[1], ox, oy), iso(k[0], k[1] + 1, ox, oy)
            ImageDraw.Draw(im).line([e0, e1], fill=(90, 255, 120, 255), width=3)
        im.alpha_composite(s, (int(px - a[0]), int(py - a[1])))
    return im.crop(im.getbbox())


def main():
    pal = palette()
    base = sample_base()
    pal2 = pal.resize((pal.width * 2, pal.height * 2), Image.NEAREST)
    base2 = base.resize((base.width * 2, base.height * 2), Image.NEAREST)
    W = max(pal2.width, base2.width) + 40
    f = ImageFont.truetype(FONT + "DejaVuSans-Bold.ttf", 30)
    out = Image.new("RGB", (W, pal2.height + base2.height + 160), (28, 24, 20))
    d = ImageDraw.Draw(out)
    d.text((20, 16), "Build palette", font=f, fill=(240, 226, 190))
    out.paste(pal2, (20, 60), pal2)
    y = 60 + pal2.height + 30
    d.text((20, y), "Sample base (green = piece being placed)", font=f, fill=(240, 226, 190))
    out.paste(base2, ((W - base2.width) // 2, y + 44), base2)
    os.makedirs("/tmp/r3d", exist_ok=True)
    out.save("/tmp/r3d/build_palette.png")
    print(out.size)


if __name__ == "__main__":
    main()
