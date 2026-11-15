"""Quick world LAYOUT sketches: flat colours, simple shapes, random geography, so we can iterate on where
things go before painting the real map.
python3 tools/worldmap/layout.py SEED [SEED ...]   -> /tmp/r3d/layout_<seed>.png (+ .json)

Geography is drawn at random per seed (mountains on one side, a river from them to a lake or the map edge,
forest on the wet side, desert on the dry side, badlands between, the city on the river), then every
location in locations.py is placed where its biome fits, roads are laid as a network between them."""
import os, sys, json, math, random
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import locations as LOC

W, H = 1400, 1050
S = W
ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
X, Y = xs / S, ys / S
YMAX = H / S


def noise(seed, scale=4):
    g = np.random.default_rng(seed)
    grid = g.random((int(scale * 0.75) + 3, scale + 3)).astype(np.float32)
    return ndimage.zoom(grid, (H / (grid.shape[0] - 3), W / (grid.shape[1] - 3)), order=3)[:H, :W]


def blob(cx, cy, r, seed, rough=0.45):
    d = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) / r
    return d + rough * (noise(seed, 5) - 0.5) * 2 < 1.0


def line_mask(pts, width):
    im = Image.new("L", (W, H), 0)
    ImageDraw.Draw(im).line([(x * S, y * S) for x, y in pts], fill=255, width=max(1, int(width * S)), joint="curve")
    return np.array(im) > 0


def walk(rng, a, b, n, jitter):
    pts = [a]
    for k in range(1, n):
        t = k / n
        x = a[0] + (b[0] - a[0]) * t + rng.uniform(-jitter, jitter)
        y = a[1] + (b[1] - a[1]) * t + rng.uniform(-jitter, jitter)
        pts.append((x, y))
    pts.append(b)
    out = [pts[0]]                 # smooth
    for i in range(1, len(pts) - 1):
        out.append(((pts[i - 1][0] + 2 * pts[i][0] + pts[i + 1][0]) / 4, (pts[i - 1][1] + 2 * pts[i][1] + pts[i + 1][1]) / 4))
    out.append(pts[-1])
    return out


def side_point(side, t):
    return {"w": (0.0, t * YMAX), "e": (1.0, t * YMAX), "n": (t, 0.0), "s": (t, YMAX)}[side]


OPP = {"w": "e", "e": "w", "n": "s", "s": "n"}


def make(seed):
    rng = random.Random(seed)
    # ---------------------------------------------------------------- geography
    mside = rng.choice("wnes")
    a = side_point(mside, rng.uniform(0.1, 0.3)); b = side_point(mside, rng.uniform(0.7, 0.9))
    inset = rng.uniform(0.07, 0.11)
    def push(p, d):
        return (p[0] + (d if mside == "w" else -d if mside == "e" else 0), p[1] + (d if mside == "n" else -d if mside == "s" else 0))
    range_pts = walk(rng, push(a, inset), push(b, inset), 6, 0.03)
    mountains = line_mask(range_pts, rng.uniform(0.07, 0.1)) | line_mask([push(a, 0.0), push(b, 0.0)], 0.06)
    mountains &= noise(seed + 1, 9) > 0.3
    mountains = ndimage.binary_closing(mountains, iterations=4)
    # river: from the mountains toward the far side, ending in a lake or off the map
    src = range_pts[rng.randint(1, len(range_pts) - 2)]
    src = push(src, 0.03)
    end_side = OPP[mside] if rng.random() < 0.6 else rng.choice([s for s in "wnes" if s != mside])
    lake_end = rng.random() < 0.6
    end = side_point(end_side, rng.uniform(0.25, 0.75))
    if lake_end:
        end = (0.2 + 0.6 * rng.random() if end_side in "ns" else end[0] * 0.75 + 0.125, end[1] * 0.75 + YMAX * 0.125 if end_side in "we" else (0.15 if end_side == "n" else YMAX - 0.15))
    river = walk(rng, src, end, 9, 0.045)
    water = line_mask(river, 0.007)
    lake = None
    if lake_end:
        lake = (end, rng.uniform(0.035, 0.06))
        water |= blob(end[0], end[1], lake[1], seed + 2, 0.3)
    for k in range(rng.randint(1, 3)):
        p = (rng.uniform(0.1, 0.9), rng.uniform(0.08, YMAX - 0.08))
        water |= blob(p[0], p[1], rng.uniform(0.01, 0.02), seed + 10 + k, 0.3)
    # wet side vs dry side: forest near the mountains on one flank, desert on the other
    perp = {"w": ("n", "s"), "e": ("n", "s"), "n": ("w", "e"), "s": ("w", "e")}[mside]
    wet, dry = (perp if rng.random() < 0.5 else perp[::-1])
    def region_center(side, along):
        p = side_point(side, along)
        return (min(max(p[0], 0.18), 0.82), min(max(p[1], 0.15), YMAX - 0.15))
    fc = region_center(wet, rng.uniform(0.3, 0.7)); dc = region_center(dry, rng.uniform(0.3, 0.7))
    forest = blob(fc[0], fc[1], rng.uniform(0.2, 0.28), seed + 3, 0.5) & ~mountains
    desert = blob(dc[0], dc[1], rng.uniform(0.22, 0.3), seed + 4, 0.5) & ~mountains & ~forest
    # badlands where the desert meets the mountains
    bc = min(range_pts, key=lambda p: (p[0] - dc[0]) ** 2 + (p[1] - dc[1]) ** 2)
    bc = (bc[0] * 0.6 + dc[0] * 0.4, bc[1] * 0.6 + dc[1] * 0.4)
    badlands = blob(bc[0], bc[1], 0.07, seed + 5, 0.5) & ~mountains
    desert &= ~badlands
    # salt pan in the desert, hills on the far side
    sp = (dc[0] + rng.uniform(-0.06, 0.06), dc[1] + rng.uniform(-0.05, 0.05))
    salt = blob(sp[0], sp[1], 0.045, seed + 6, 0.4) & desert
    far = side_point(OPP[mside], rng.uniform(0.2, 0.8))
    hc = (far[0] * 0.8 + 0.1, far[1] * 0.8 + YMAX * 0.1)
    hills = blob(hc[0], hc[1], 0.09, seed + 7, 0.5) & ~mountains & ~water
    water &= ~mountains | line_mask(river, 0.007)
    # the city on the river, away from the mountains
    cands = river[len(river) // 2: len(river) - 1]
    city_c = rng.choice(cands)
    city = blob(city_c[0], city_c[1], 0.06, seed + 8, 0.35) & ~water
    suburbs = blob(city_c[0], city_c[1], 0.1, seed + 9, 0.4) & ~city & ~water & ~mountains
    # crater: between the city and the desert
    cr = (city_c[0] * 0.55 + dc[0] * 0.45, city_c[1] * 0.55 + dc[1] * 0.45)
    if math.dist(cr, city_c) < 0.13:     # the crater sits well outside the city
        ang = math.atan2(cr[1] - city_c[1], cr[0] - city_c[0]) if math.dist(cr, city_c) > 1e-3 else rng.uniform(0, 6.28)
        cr = (min(0.92, max(0.08, city_c[0] + math.cos(ang) * 0.15)), min(YMAX - 0.08, max(0.08, city_c[1] + math.sin(ang) * 0.15)))
    for t in range(40):      # and away from the middle, where the start town goes
        if math.hypot(cr[0] - 0.5, cr[1] - YMAX / 2) > 0.2: break
        cr = (cr[0] + (cr[0] - 0.5) * 0.15 + (0.01 if cr[0] >= 0.5 else -0.01), cr[1] + (cr[1] - YMAX / 2) * 0.15)
        cr = (min(0.92, max(0.08, cr[0])), min(YMAX - 0.08, max(0.08, cr[1])))
    farmland = (ndimage.distance_transform_edt(~line_mask(river, 0.004)) / S < 0.07) & ~forest & ~desert & ~mountains & ~city & ~suburbs & ~water & ~badlands

    biome = np.full((H, W), "plains", dtype=object)
    for name, m in (("farmland", farmland), ("hills", hills), ("forest", forest), ("desert", desert), ("badlands", badlands),
                    ("salt", salt), ("suburbs", suburbs), ("ruins", city), ("mountains", mountains), ("water", water)):
        biome[m] = name

    # ---------------------------------------------------------------- place locations
    def biome_at(p):
        x, y = int(p[0] * S), int(p[1] * S)
        if not (0 <= x < W and 0 <= y < H): return "off"
        return biome[y, x]

    river_d = ndimage.distance_transform_edt(~line_mask(river, 0.005)) / S
    lake_d = None
    if lake:
        lm = blob(lake[0][0], lake[0][1], lake[1], seed + 2, 0.3)
        lake_d = ndimage.distance_transform_edt(~lm) / S
    city_d = ndimage.distance_transform_edt(~city) / S
    mtn_d = ndimage.distance_transform_edt(~mountains) / S

    def fits(l, p):
        b = biome_at(p)
        if b in ("water", "off"): return -99
        want = l["biome"]
        x, y = int(p[0] * S), int(p[1] * S)
        sc = 0.0
        if want == b: sc += 3
        if want == "ruins": sc += 3 - city_d[y, x] * 80
        if want in ("suburbs", "industrial"): sc += 2 - abs(city_d[y, x] - 0.03) * 60
        if want == "river": sc += 3 - river_d[y, x] * 120
        if want == "lakeshore": sc += (3 - lake_d[y, x] * 120) if lake_d is not None else (2 - river_d[y, x] * 60)
        if want == "mountains": sc += 2 - mtn_d[y, x] * 40 if b != "mountains" else 2
        if want == "crater": sc += 4 - math.hypot(p[0] - cr[0], p[1] - cr[1]) * 60
        if want == "farmland": sc += 1.5 - river_d[y, x] * 25
        if want == "plains" and b in ("plains", "farmland"): sc += 1.5
        # the start sits near the middle, with its neighbours close by
        if l["id"] == "haven_flats": sc += 4 - math.hypot(p[0] - 0.5, p[1] - YMAX / 2) * 25 - (0 if city_d[y, x] > 0.15 else 6)
        if l["id"] in ("comet_junction", "sawtooth_camp") and "haven_flats" in POS:
            dh = math.dist(p, POS["haven_flats"]); sc += 8 - abs(dh - 0.06) * 120
        if want in ("ruins", "suburbs") and l["type"] not in ("district", "city") and l["id"] != "comet_junction" and city_d[y, x] > 0.05: sc -= 3
        return sc

    POS = {}
    order = sorted(LOC.L, key=lambda l: (-1 if l["id"] == "haven_flats" else {"city": 0, "district": 1, "town": 2, "dungeon": 4}.get(l["type"], 3)))
    for l in order:
        best, bs = None, -1e9
        for t in range(500):
            if l["type"] == "city":
                p = (city_c[0] + rng.uniform(-0.01, 0.01), city_c[1] + rng.uniform(-0.01, 0.01))
            elif l["type"] == "district":
                a_ = rng.uniform(0, 6.28); p = (city_c[0] + math.cos(a_) * rng.uniform(0.035, 0.08), city_c[1] + math.sin(a_) * rng.uniform(0.035, 0.08))
            else:
                p = (rng.uniform(0.03, 0.97), rng.uniform(0.03, YMAX - 0.03))
            md = min([math.hypot(p[0] - q[0], p[1] - q[1]) for q in POS.values()] + [1])
            minsep = 0.022 if l["type"] == "district" else 0.045
            if md < minsep: continue
            sc = fits(l, p) + min(md, 0.12) * 4
            if sc > bs: best, bs = p, sc
        POS[l["id"]] = best or (0.5, 0.375)
    if "the_glow" in POS: POS["the_glow"] = cr

    # ---------------------------------------------------------------- roads
    ids = list(POS)
    hubs = [i for i in ids if next(l for l in LOC.L if l["id"] == i)["type"] in ("city", "town")]
    # interstate: edge to edge through the start town and the city
    st, ct = POS["haven_flats"], POS["halcyon_downtown"]
    dx, dy = ct[0] - st[0], ct[1] - st[1]
    horiz = abs(dx) >= abs(dy)
    if horiz:
        e0 = (0.0, st[1] + rng.uniform(-0.03, 0.03)); e1 = (1.0, ct[1] + rng.uniform(-0.03, 0.03))
        inter = sorted([e0, st, ct, e1], key=lambda p: p[0])
    else:
        e0 = (st[0], 0.0); e1 = (ct[0], YMAX)
        inter = sorted([e0, st, ct, e1], key=lambda p: p[1])
    roads = [("interstate", inter)]
    # highways: minimum spanning tree over hubs
    import itertools
    edges = sorted(((math.dist(POS[a], POS[b]), a, b) for a, b in itertools.combinations(hubs, 2)))
    parent = {h: h for h in hubs}
    def find(h):
        while parent[h] != h: h = parent[h]
        return h
    for d, a_, b_ in edges:
        if find(a_) != find(b_):
            parent[find(a_)] = find(b_)
            roads.append(("highway", [POS[a_], POS[b_]]))
    # every other place: a road or track to its nearest hub
    for i in ids:
        if i in hubs: continue
        l = next(l for l in LOC.L if l["id"] == i)
        h = min(hubs, key=lambda hb: math.dist(POS[hb], POS[i]))
        roads.append(("track" if l["type"] in ("dungeon", "camp") else "road", [POS[i], POS[h]]))
    # rail: city to the mountains (through a tunnel) and on to the edge
    tunnel = POS.get("ironback_tunnel")
    rail = [ct]
    if tunnel: rail.append(tunnel)
    rail.append(side_point(mside, 0.5) if mside in "we" else side_point(mside, 0.5))
    roads.append(("rail", rail))

    # ---------------------------------------------------------------- draw
    COL = {"plains": (176, 164, 118), "farmland": (190, 180, 110), "hills": (150, 140, 100), "forest": (88, 120, 70), "desert": (214, 186, 128),
           "badlands": (178, 104, 70), "salt": (236, 232, 218), "suburbs": (150, 146, 136), "ruins": (110, 106, 100),
           "mountains": (124, 112, 98), "water": (78, 120, 140)}
    rgb = np.zeros((H, W, 3), np.uint8)
    for k, c in COL.items():
        rgb[biome == k] = c
    img = Image.fromarray(rgb)
    d = ImageDraw.Draw(img)
    # simple mountain marks and tree marks
    rr = random.Random(seed)
    for t in range(1400):
        x, y = rr.uniform(0, W), rr.uniform(0, H)
        b = biome[int(y), int(x)]
        if b == "mountains":
            d.polygon([(x - 7, y + 5), (x, y - 7), (x + 7, y + 5)], outline=(80, 70, 60))
        elif b == "forest" and t % 2 == 0:
            d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(60, 92, 50))
    # crater
    d.ellipse(((cr[0] - 0.022) * S, (cr[1] - 0.022) * S, (cr[0] + 0.022) * S, (cr[1] + 0.022) * S), fill=(60, 56, 48), outline=(120, 200, 80), width=3)
    STY = {"interstate": ((60, 40, 30), 5), "highway": ((90, 60, 40), 3), "road": ((110, 84, 60), 2), "track": ((120, 96, 70), 1)}
    for kind in ("track", "road", "highway", "interstate"):
        for k_, pts in roads:
            if k_ != kind: continue
            ppx = [(x * S, y * S) for x, y in pts]
            if kind == "track":
                (x0, y0), (x1, y1) = ppx[0], ppx[-1]
                n = int(math.dist(ppx[0], ppx[-1]) / 8)
                for i in range(0, n, 2):
                    d.line([(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n), (x0 + (x1 - x0) * (i + 1) / n, y0 + (y1 - y0) * (i + 1) / n)], fill=STY[kind][0], width=1)
            else:
                d.line(ppx, fill=STY[kind][0], width=STY[kind][1], joint="curve")
    for k_, pts in roads:
        if k_ == "rail":
            ppx = [(x * S, y * S) for x, y in pts]
            d.line(ppx, fill=(30, 30, 30), width=2)
            for i in range(len(ppx) - 1):
                (x0, y0), (x1, y1) = ppx[i], ppx[i + 1]
                L = math.dist(ppx[i], ppx[i + 1]) or 1
                for t in range(0, int(L), 8):
                    cx_, cy_ = x0 + (x1 - x0) * t / L, y0 + (y1 - y0) * t / L
                    nx_, ny_ = -(y1 - y0) / L * 3, (x1 - x0) / L * 3
                    d.line([(cx_ - nx_, cy_ - ny_), (cx_ + nx_, cy_ + ny_)], fill=(30, 30, 30))
    TC = {"city": (200, 40, 30), "district": (210, 100, 60), "town": (30, 130, 40), "settlement": (50, 150, 70), "camp": (200, 140, 30),
          "landmark": (60, 60, 160), "dungeon": (160, 30, 30)}
    RAD = {"city": 12, "district": 6, "town": 9, "settlement": 6, "camp": 5, "landmark": 5, "dungeon": 5}
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", 13)
    fb = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", 16)
    placed = []
    for l in sorted(LOC.L, key=lambda l: -RAD[l["type"]]):
        x, y = POS[l["id"]][0] * S, POS[l["id"]][1] * S
        r = RAD[l["type"]]
        d.ellipse((x - r, y - r, x + r, y + r), fill=TC[l["type"]], outline=(20, 20, 20), width=2)
        name = l["name"].replace("New Halcyon - ", "Halcyon ")
        ff = fb if l["type"] in ("city", "town") else f
        tw = d.textlength(name, font=ff)
        for (ox, oy) in ((r + 4, -8), (-tw - r - 4, -8), (-tw / 2, r + 2), (-tw / 2, -r - 17)):
            box = (x + ox, y + oy, x + ox + tw, y + oy + 15)
            if all(box[2] < q[0] or box[0] > q[2] or box[3] < q[1] or box[1] > q[3] for q in placed): break
        placed.append(box)
        d.text((box[0] + 1, box[1] + 1), name, font=ff, fill=(255, 250, 235))
        d.text((box[0], box[1]), name, font=ff, fill=(20, 16, 12))
    d.text((20, 16), "Layout %d" % seed, font=ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28), fill=(20, 16, 12))
    out = "/tmp/r3d/layout_%d.png" % seed
    img.save(out)
    json.dump({"seed": seed, "mountains": mside, "positions": POS}, open(out[:-4] + ".json", "w"))
    return out


if __name__ == "__main__":
    os.makedirs("/tmp/r3d", exist_ok=True)
    for a in sys.argv[1:] or ["1"]:
        print(make(int(a)))
