"""Hand-laid world layout in the spirit of Fallout 3's Capital Wasteland: a square map, the river curving
down the east side, the dense ruined city on its east bank, highways converging on the city, and small
places scattered evenly across barren hilly wasteland.
python3 tools/worldmap/layout_fo3.py  -> /tmp/r3d/layout_fo3.png (+ .json)"""
import os, sys, json, math, random
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import locations as LOC

N = int(os.environ.get("WM_N", 1200))   # paint_fo3.py renders the same layout larger
S = N
ys, xs = np.mgrid[0:N, 0:N].astype(np.float32)
X, Y = xs / S, ys / S
R = random.Random(3)


def noise(seed, scale):
    g = np.random.default_rng(seed)
    grid = g.random((scale + 3, scale + 3)).astype(np.float32)
    return ndimage.zoom(grid, (N / scale, N / scale), order=3)[:N, :N]


def smooth(pts, it=2):
    for _ in range(it):
        pts = [pts[0]] + [((pts[i - 1][0] + 2 * pts[i][0] + pts[i + 1][0]) / 4, (pts[i - 1][1] + 2 * pts[i][1] + pts[i + 1][1]) / 4)
                          for i in range(1, len(pts) - 1)] + [pts[-1]]
    return pts


def densify(pts, step=0.01, amp=0.0, seed=0):
    rr = random.Random(seed); out = []
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        n = max(1, int(math.dist(pts[i], pts[i + 1]) / step))
        for k in range(n):
            t = k / n
            out.append((x0 + (x1 - x0) * t + rr.uniform(-amp, amp), y0 + (y1 - y0) * t + rr.uniform(-amp, amp)))
    out.append(pts[-1])
    return smooth(out, 3)


def mask_line(pts, w):
    im = Image.new("L", (N, N), 0)
    ImageDraw.Draw(im).line([(x * S, y * S) for x, y in pts], fill=255, width=max(1, int(w * S)), joint="curve")
    return np.array(im) > 0


def blob(cx, cy, r, seed, rough=0.4):
    return np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) / r + rough * (noise(seed, 6) - 0.5) * 2 < 1


# ---------------------------------------------------------------- geography (hand-laid)
RIVER = densify([(0.64, 0.0), (0.655, 0.08), (0.66, 0.16), (0.63, 0.24), (0.6, 0.33), (0.61, 0.42), (0.635, 0.5),
                 (0.66, 0.58), (0.675, 0.66), (0.69, 0.74), (0.72, 0.82), (0.76, 0.9), (0.8, 1.0)], 0.008, 0.012, 1)
TRIB = densify([(1.0, 0.7), (0.92, 0.73), (0.84, 0.76), (0.76, 0.77), (0.7, 0.77)], 0.008, 0.01, 2)       # eastern branch
CREEK = densify([(0.18, 0.0), (0.24, 0.07), (0.34, 0.1), (0.46, 0.12), (0.56, 0.13), (0.655, 0.12)], 0.008, 0.01, 3)
LAKE = ((0.665, 0.115), 0.042)
water = mask_line(RIVER, 0.018) | mask_line(TRIB, 0.011) | mask_line(CREEK, 0.005) | blob(LAKE[0][0], LAKE[0][1], LAKE[1], 4, 0.35)
water |= blob(0.6, 0.62, 0.012, 5, 0.3) & False
island = blob(0.69, 0.765, 0.013, 6, 0.3)          # an island where the branches meet
water &= ~island
n1 = noise(7, 5); n2 = noise(8, 14)
hills = ((np.clip(1 - np.hypot(X - 0.12, Y - 0.2) / 0.28, 0, 1) + np.clip(1 - np.hypot(X - 0.12, Y - 0.82) / 0.2, 0, 1)
          + 0.6 * np.clip(1 - np.hypot(X - 0.86, Y - 0.22) / 0.16, 0, 1)) * (0.6 + 0.8 * n2)) > 0.55
peaks = blob(0.07, 0.11, 0.07, 9, 0.4)
city = blob(0.82, 0.62, 0.16, 10, 0.25) & (X > 0.66)
city_core = blob(0.8, 0.62, 0.075, 11, 0.25) & city
suburbs = (blob(0.89, 0.42, 0.1, 12, 0.4) | blob(0.84, 0.88, 0.09, 13, 0.4)) & ~city & (X > 0.68)
deadwood = blob(0.44, 0.13, 0.12, 14, 0.5) & ~water
farms = blob(0.4, 0.24, 0.07, 15, 0.4) & ~deadwood
salt = blob(0.12, 0.6, 0.05, 16, 0.4)
canyon = blob(0.21, 0.84, 0.06, 17, 0.45)
marsh = (blob(0.66, 0.94, 0.075, 18, 0.5) | blob(0.73, 0.98, 0.05, 19, 0.5)) & (X < 0.79)   # river wetlands south of the city
crater_c, crater_r = (0.3, 0.8), 0.04
craters = [(R.uniform(0.05, 0.62), R.uniform(0.05, 0.95), R.uniform(0.006, 0.014)) for _ in range(26)]

# ---------------------------------------------------------------- places (hand-placed, x/y in 0..1)
P = {l["id"]: l["pos"] for l in LOC.L}   # hand-placed positions live in locations.py
assert set(P) == {l["id"] for l in LOC.L}, set(l["id"] for l in LOC.L) ^ set(P)

# ---------------------------------------------------------------- roads
ROADS = [
    # beltway around the city
    ("interstate", densify([(0.7, 0.44), (0.82, 0.4), (0.95, 0.47), (0.97, 0.62), (0.93, 0.78), (0.82, 0.84), (0.72, 0.8), (0.69, 0.62), (0.7, 0.44)], 0.01)),
    # radial highways into the city from the wasteland
    ("interstate", densify([(0.0, 0.48), P["hangmans_gap"], P["bluebird_lodge"], P["bunker_echo"], P["patchwork"], P["starlite_crossing"], P["founders_bridge"], (0.69, 0.56)], 0.01, 0.004, 21)),
    ("highway", densify([(0.0, 0.3), P["devils_throat"], P["granite_bowl"], P["silver_comet_wreck"], P["gus_salvage"], P["big_wheel_stop"], P["ferrymans_landing"], (0.62, 0.4), (0.7, 0.44)], 0.01, 0.004, 22)),
    ("highway", densify([(0.44, 0.0), P["lookout_station_3"], P["owls_perch"], P["goldenrod"], P["radio_kzap"], P["big_wheel_stop"]], 0.01, 0.004, 23)),
    ("highway", densify([P["patchwork"], P["rattlebone_camp"], P["wellspring"], P["buzzard_mesa"], (0.55, 1.0)], 0.01, 0.004, 24)),
    ("highway", densify([(0.72, 0.8), P["bright_hope_plant"], P["blackrock_refinery"], P["wellspring"], P["rimtown"], P["copperhead"], P["bonewhite_flats"], (0.0, 0.62)], 0.01, 0.004, 25)),
    ("highway", densify([(0.82, 0.4), P["sunbeam_commune"], P["clearwater"], (0.8, 0.0)], 0.01, 0.004, 26)),
    ("highway", densify([(0.95, 0.47), P["atomic_plaza"], (1.0, 0.5)], 0.01)),
    ("road", densify([P["goldenrod"], P["our_lady_mission"], P["granite_bowl"]], 0.01, 0.004, 27)),
    ("road", densify([P["goldenrod"], P["camp_whispering_pines"], P["ridgeback_dam"], P["clearwater"]], 0.01, 0.004, 28)),
    ("road", densify([P["splinter_creek"], P["hushwood"], P["starwatch"]], 0.01, 0.004, 29)),
    ("road", densify([P["splinter_creek"], P["owls_perch"]], 0.01, 0.004, 30)),
    ("road", densify([P["fort_steadfast"], P["double_bar_ranch"], P["bluebird_lodge"]], 0.01, 0.004, 31)),
    ("road", densify([P["fort_steadfast"], P["launch_site_zulu"]], 0.01, 0.004, 32)),
    ("road", densify([P["copperhead"], P["redwall"], P["deep_seven"]], 0.01, 0.004, 33)),
    ("road", densify([P["iron_gate_pen"], P["radio_kzap"]], 0.01, 0.004, 34)),
    ("road", densify([P["prometheus_research"], P["maple_grove"]], 0.01, 0.004, 35)),
    ("road", densify([P["sterling_airfield"], (0.93, 0.78)], 0.01)),
    ("track", [P["patchwork"], P["moonbeam_drivein"]]),
    ("track", [P["bunker_echo"], P["silver_comet_wreck"]]),
    ("track", [P["hangmans_gap"], P["bonewhite_flats"]]),
    ("track", [P["double_bar_ranch"], P["rimtown"]]),
    ("track", [P["rimtown"], P["hollow_sun"]]),
    ("road", densify([P["bright_hope_plant"], P["greenmarsh"], P["buzzard_mesa"]], 0.01, 0.004, 36)),
    ("road", densify([P["greenmarsh"], (0.64, 1.0)], 0.01, 0.004, 37)),
]
METRO = densify([(0.5, 0.47), (0.56, 0.5), P["founders_bridge"], (0.74, 0.6), P["sterling_downtown"], (0.86, 0.66), (0.9, 0.75), P["union_railyard"]], 0.01)


def draw(out):
    COL = dict(marsh=(96, 120, 84), waste=(150, 142, 118), waste2=(132, 126, 104), hills=(118, 110, 90), peaks=(98, 90, 76), water=(64, 92, 104),
               city=(104, 102, 98), core=(78, 76, 74), suburbs=(130, 126, 116), dead=(102, 106, 78), farms=(160, 150, 100),
               salt=(214, 208, 190), canyon=(150, 96, 70))
    img = np.zeros((N, N, 3), np.float32)
    base = np.array(COL["waste"], np.float32) * (1 - n1[..., None] * 0.6) + np.array(COL["waste2"], np.float32) * n1[..., None] * 0.6
    img[:] = base
    for k, m in (("farms", farms), ("dead", deadwood), ("salt", salt), ("canyon", canyon), ("marsh", marsh), ("hills", hills), ("peaks", peaks),
                 ("suburbs", suburbs), ("city", city), ("core", city_core), ("water", water)):
        img[m] = COL[k]
    im = Image.fromarray(img.astype(np.uint8))
    d = ImageDraw.Draw(im)
    rr = random.Random(4)
    for t in range(2600):           # texture marks: hill ticks, dead trees, city blocks
        x, y = rr.uniform(0, N), rr.uniform(0, N)
        xi, yi = int(x), int(y)
        if hills[yi, xi] or peaks[yi, xi]:
            d.arc((x - 7, y - 4, x + 7, y + 6), 200, 340, fill=(84, 78, 64), width=2)
        elif deadwood[yi, xi] and t % 2 == 0:
            d.line((x, y, x, y - 6), fill=(70, 66, 52)); d.line((x - 3, y - 4, x, y - 3), fill=(70, 66, 52))
        elif city[yi, xi] and not water[yi, xi]:
            s_ = rr.choice([4, 5, 6])
            d.rectangle((x, y, x + s_, y + s_), fill=(64, 62, 60) if city_core[yi, xi] else (88, 86, 82))
        elif suburbs[yi, xi] and t % 2:
            d.rectangle((x, y, x + 3, y + 3), fill=(104, 100, 92))
    cx, cy = crater_c
    d.ellipse(((cx - crater_r) * S, (cy - crater_r) * S, (cx + crater_r) * S, (cy + crater_r) * S), fill=(62, 58, 50), outline=(120, 190, 90), width=3)
    for (x, y, r) in craters:
        d.ellipse(((x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S), outline=(110, 104, 86), width=2)
    # dam
    d.line(((0.64) * S, 0.156 * S, 0.69 * S, 0.156 * S), fill=(210, 204, 190), width=6)
    STY = {"interstate": ((52, 40, 30), 6, (190, 172, 130), 3), "highway": ((70, 56, 42), 4, (170, 150, 112), 2),
           "road": ((96, 78, 58), 2, None, 0), "track": ((110, 92, 70), 1, None, 0)}
    for kind in ("track", "road", "highway", "interstate"):
        for k, pts in ROADS:
            if k != kind: continue
            px_ = [(x * S, y * S) for x, y in pts]
            if kind == "track":
                n = int(math.dist(px_[0], px_[-1]) / 7)
                for i in range(0, n, 2):
                    a = (px_[0][0] + (px_[-1][0] - px_[0][0]) * i / n, px_[0][1] + (px_[-1][1] - px_[0][1]) * i / n)
                    b = (px_[0][0] + (px_[-1][0] - px_[0][0]) * (i + 1) / n, px_[0][1] + (px_[-1][1] - px_[0][1]) * (i + 1) / n)
                    d.line((a, b), fill=STY[kind][0], width=1)
            else:
                d.line(px_, fill=STY[kind][0], width=STY[kind][1], joint="curve")
    for kind in ("highway", "interstate"):
        for k, pts in ROADS:
            if k == kind:
                d.line([(x * S, y * S) for x, y in pts], fill=STY[kind][2], width=STY[kind][3], joint="curve")
    # metro line (dashed dark blue)
    mp = [(x * S, y * S) for x, y in METRO]
    for i in range(0, len(mp) - 1, 2):
        d.line((mp[i], mp[i + 1]), fill=(40, 50, 90), width=3)
    TC = {"hub": (240, 200, 40), "city": (200, 40, 30), "district": (210, 100, 60), "town": (30, 130, 40), "settlement": (50, 150, 70), "camp": (200, 140, 30),
          "landmark": (60, 60, 160), "dungeon": (160, 30, 30)}
    RAD = {"hub": 11, "city": 12, "district": 7, "town": 9, "settlement": 6, "camp": 5, "landmark": 5, "dungeon": 5}
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", 13)
    fb = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", 16)
    placed = []
    for l in sorted(LOC.L, key=lambda l: -RAD[l["type"]]):
        x, y = P[l["id"]][0] * S, P[l["id"]][1] * S
        r = RAD[l["type"]]
        d.ellipse((x - r, y - r, x + r, y + r), fill=TC[l["type"]], outline=(20, 20, 20), width=2)
        name = l["name"].replace("Port Sterling - ", "")
        ff = fb if l["type"] in ("city", "town", "hub") else f
        tw = d.textlength(name, font=ff)
        for (ox, oy) in ((r + 4, -8), (-tw - r - 4, -8), (-tw / 2, r + 2), (-tw / 2, -r - 17), (r + 4, 4), (-tw - r - 4, 4)):
            box = (x + ox, y + oy, x + ox + tw, y + oy + 15)
            if box[0] > 2 and box[2] < N - 2 and all(box[2] < q[0] or box[0] > q[2] or box[3] < q[1] or box[1] > q[3] for q in placed): break
        placed.append(box)
        for dx, dy in ((1, 1), (-1, 0), (1, 0), (0, -1)):
            d.text((box[0] + dx, box[1] + dy), name, font=ff, fill=(240, 234, 214))
        d.text((box[0], box[1]), name, font=ff, fill=(20, 16, 12))
    tf = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-BoldItalic.ttf", 20)
    for (t, x, y) in ((LOC.NAMES["river"], 0.6, 0.665), (LOC.NAMES["lake"], 0.665, 0.1), (LOC.NAMES["hills"], 0.09, 0.22), (LOC.NAMES["woods"], 0.44, 0.11),
                      (LOC.NAMES["city"], 0.8, 0.58), (LOC.NAMES["waste"], 0.32, 0.55)):
        tw = d.textlength(t, font=tf)
        d.text((x * S - tw / 2 + 1, y * S + 1), t, font=tf, fill=(240, 234, 214)); d.text((x * S - tw / 2, y * S), t, font=tf, fill=(50, 40, 30))
    im.save(out)
    json.dump({"layout": "fo3", "positions": P}, open(out[:-4] + ".json", "w"))


if __name__ == "__main__":
    os.makedirs("/tmp/r3d", exist_ok=True)
    draw("/tmp/r3d/layout_fo3.png")
    print("ok")
