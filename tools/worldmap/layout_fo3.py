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

N = 1200
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
crater_c, crater_r = (0.3, 0.8), 0.04
craters = [(R.uniform(0.05, 0.62), R.uniform(0.05, 0.95), R.uniform(0.006, 0.014)) for _ in range(26)]

# ---------------------------------------------------------------- places (hand-placed, x/y in 0..1)
P = dict(
    haven_flats=(0.42, 0.5), comet_junction=(0.475, 0.465), sawtooth_camp=(0.45, 0.585), shelter_17=(0.3, 0.505),
    starlight_drivein=(0.52, 0.565), tumbleweed_stop=(0.52, 0.39), rustys_junkyard=(0.36, 0.41), cottonwood_motel=(0.24, 0.57),
    sundial_ranch=(0.33, 0.66), starliner_wreck=(0.27, 0.4),
    halcyon_downtown=(0.8, 0.62), halcyon_docks=(0.71, 0.705), halcyon_heights=(0.89, 0.42), halcyon_general=(0.86, 0.69),
    halcyon_stadium=(0.76, 0.545), big_sky_mall=(0.94, 0.5), halcyon_railyard=(0.87, 0.81), halcyon_airfield=(0.93, 0.91),
    kettle_point=(0.66, 0.86), kettle_bridge=(0.635, 0.54), copper_kettle=(0.59, 0.37), black_gulch=(0.57, 0.76),
    millbrook=(0.4, 0.24), cedar_falls=(0.25, 0.075), ranger_station=(0.47, 0.06), paradise_lake=(0.54, 0.18), fire_lookout=(0.35, 0.14),
    blackwood_pen=(0.56, 0.28), radio_kbsn=(0.47, 0.32), st_agnes=(0.31, 0.3), lakeview=(0.75, 0.1), hollister_dam=(0.66, 0.175),
    harmony_ridge=(0.82, 0.22), helios_labs=(0.94, 0.28),
    mount_vigil=(0.065, 0.09), little_eden=(0.14, 0.17), ironback_tunnel=(0.1, 0.3), whitestone_quarry=(0.19, 0.36), gallows_pass=(0.04, 0.47),
    bright_flats=(0.12, 0.6), prospect=(0.17, 0.74), silver_vein=(0.07, 0.83), red_canyon=(0.21, 0.86), the_glow=(0.3, 0.8),
    dustwater=(0.43, 0.76), thunder_mesa=(0.51, 0.9), fort_liberty=(0.36, 0.93), silo_delta9=(0.15, 0.95),
)
assert set(P) == {l["id"] for l in LOC.L}, set(l["id"] for l in LOC.L) ^ set(P)

# ---------------------------------------------------------------- roads
ROADS = [
    # beltway around the city
    ("interstate", densify([(0.7, 0.44), (0.82, 0.4), (0.95, 0.47), (0.97, 0.62), (0.93, 0.78), (0.82, 0.84), (0.72, 0.8), (0.69, 0.62), (0.7, 0.44)], 0.01)),
    # radial highways into the city from the wasteland
    ("interstate", densify([(0.0, 0.48), P["gallows_pass"], P["cottonwood_motel"], P["shelter_17"], P["haven_flats"], P["comet_junction"], P["kettle_bridge"], (0.69, 0.56)], 0.01, 0.004, 21)),
    ("highway", densify([(0.0, 0.3), P["ironback_tunnel"], P["whitestone_quarry"], P["starliner_wreck"], P["rustys_junkyard"], P["tumbleweed_stop"], P["copper_kettle"], (0.62, 0.4), (0.7, 0.44)], 0.01, 0.004, 22)),
    ("highway", densify([(0.44, 0.0), P["ranger_station"], P["fire_lookout"], P["millbrook"], P["radio_kbsn"], P["tumbleweed_stop"]], 0.01, 0.004, 23)),
    ("highway", densify([P["haven_flats"], P["sawtooth_camp"], P["dustwater"], P["thunder_mesa"], (0.55, 1.0)], 0.01, 0.004, 24)),
    ("highway", densify([(0.72, 0.8), P["kettle_point"], P["black_gulch"], P["dustwater"], P["the_glow"], P["prospect"], P["bright_flats"], (0.0, 0.62)], 0.01, 0.004, 25)),
    ("highway", densify([(0.82, 0.4), P["harmony_ridge"], P["lakeview"], (0.8, 0.0)], 0.01, 0.004, 26)),
    ("highway", densify([(0.95, 0.47), P["big_sky_mall"], (1.0, 0.5)], 0.01)),
    ("road", densify([P["millbrook"], P["st_agnes"], P["whitestone_quarry"]], 0.01, 0.004, 27)),
    ("road", densify([P["millbrook"], P["paradise_lake"], P["hollister_dam"], P["lakeview"]], 0.01, 0.004, 28)),
    ("road", densify([P["cedar_falls"], P["little_eden"], P["mount_vigil"]], 0.01, 0.004, 29)),
    ("road", densify([P["cedar_falls"], P["fire_lookout"]], 0.01, 0.004, 30)),
    ("road", densify([P["fort_liberty"], P["sundial_ranch"], P["cottonwood_motel"]], 0.01, 0.004, 31)),
    ("road", densify([P["fort_liberty"], P["silo_delta9"]], 0.01, 0.004, 32)),
    ("road", densify([P["prospect"], P["red_canyon"], P["silver_vein"]], 0.01, 0.004, 33)),
    ("road", densify([P["blackwood_pen"], P["radio_kbsn"]], 0.01, 0.004, 34)),
    ("road", densify([P["helios_labs"], P["halcyon_heights"]], 0.01, 0.004, 35)),
    ("road", densify([P["halcyon_airfield"], (0.93, 0.78)], 0.01)),
    ("track", [P["haven_flats"], P["starlight_drivein"]]),
    ("track", [P["shelter_17"], P["starliner_wreck"]]),
    ("track", [P["gallows_pass"], P["bright_flats"]]),
    ("track", [P["sundial_ranch"], P["the_glow"]]),
]
METRO = densify([(0.5, 0.47), (0.56, 0.5), P["kettle_bridge"], (0.74, 0.6), P["halcyon_downtown"], (0.86, 0.66), (0.9, 0.75), P["halcyon_railyard"]], 0.01)


def draw(out):
    COL = dict(waste=(150, 142, 118), waste2=(132, 126, 104), hills=(118, 110, 90), peaks=(98, 90, 76), water=(64, 92, 104),
               city=(104, 102, 98), core=(78, 76, 74), suburbs=(130, 126, 116), dead=(102, 106, 78), farms=(160, 150, 100),
               salt=(214, 208, 190), canyon=(150, 96, 70))
    img = np.zeros((N, N, 3), np.float32)
    base = np.array(COL["waste"], np.float32) * (1 - n1[..., None] * 0.6) + np.array(COL["waste2"], np.float32) * n1[..., None] * 0.6
    img[:] = base
    for k, m in (("farms", farms), ("dead", deadwood), ("salt", salt), ("canyon", canyon), ("hills", hills), ("peaks", peaks),
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
    TC = {"city": (200, 40, 30), "district": (210, 100, 60), "town": (30, 130, 40), "settlement": (50, 150, 70), "camp": (200, 140, 30),
          "landmark": (60, 60, 160), "dungeon": (160, 30, 30)}
    RAD = {"city": 12, "district": 7, "town": 9, "settlement": 6, "camp": 5, "landmark": 5, "dungeon": 5}
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", 13)
    fb = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", 16)
    placed = []
    for l in sorted(LOC.L, key=lambda l: -RAD[l["type"]]):
        x, y = P[l["id"]][0] * S, P[l["id"]][1] * S
        r = RAD[l["type"]]
        d.ellipse((x - r, y - r, x + r, y + r), fill=TC[l["type"]], outline=(20, 20, 20), width=2)
        name = l["name"].replace("New Halcyon - ", "Halcyon ")
        ff = fb if l["type"] in ("city", "town") else f
        tw = d.textlength(name, font=ff)
        for (ox, oy) in ((r + 4, -8), (-tw - r - 4, -8), (-tw / 2, r + 2), (-tw / 2, -r - 17), (r + 4, 4), (-tw - r - 4, 4)):
            box = (x + ox, y + oy, x + ox + tw, y + oy + 15)
            if box[0] > 2 and box[2] < N - 2 and all(box[2] < q[0] or box[0] > q[2] or box[3] < q[1] or box[1] > q[3] for q in placed): break
        placed.append(box)
        for dx, dy in ((1, 1), (-1, 0), (1, 0), (0, -1)):
            d.text((box[0] + dx, box[1] + dy), name, font=ff, fill=(240, 234, 214))
        d.text((box[0], box[1]), name, font=ff, fill=(20, 16, 12))
    tf = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-BoldItalic.ttf", 20)
    for (t, x, y) in (("Kettle River", 0.585, 0.46), ("Lake Mercy", 0.665, 0.1), ("Iron Hills", 0.09, 0.22), ("Pinewood (dead)", 0.44, 0.11),
                      ("NEW HALCYON", 0.8, 0.58), ("The Wasteland", 0.32, 0.55)):
        tw = d.textlength(t, font=tf)
        d.text((x * S - tw / 2 + 1, y * S + 1), t, font=tf, fill=(240, 234, 214)); d.text((x * S - tw / 2, y * S), t, font=tf, fill=(50, 40, 30))
    im.save(out)
    json.dump({"layout": "fo3", "positions": P}, open(out[:-4] + ".json", "w"))


if __name__ == "__main__":
    os.makedirs("/tmp/r3d", exist_ok=True)
    draw("/tmp/r3d/layout_fo3.png")
    print("ok")
