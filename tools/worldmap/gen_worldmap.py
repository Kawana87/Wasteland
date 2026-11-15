"""Render the Sundown Basin world map (Fallout 2 style painted terrain) and export location data.

python3 tools/worldmap/gen_worldmap.py
  -> assets/worldmap/worldmap.png        clean map for the game (markers drawn by the game)
  -> assets/worldmap/locations.json      locations (pixel + normalised positions), routes
  -> /tmp/r3d/worldmap_labeled.png       preview with markers and names
"""
import os, sys, json, math, random
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import locations as LOC

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "worldmap")
W, H = 1600, 1200
S = W                       # normalised unit -> pixels
rng = np.random.default_rng(7)
R = random.Random(7)

ys, xs = np.mgrid[0:H, 0:W].astype(np.float32)
X, Y = xs / S, ys / S       # normalised coords (y up to 0.75)


def fbm(scale, octaves=6, persist=0.5, seed=0):
    g = np.random.default_rng(seed)
    out = np.zeros((H, W), np.float32); amp = 1.0; tot = 0.0
    for o in range(octaves):
        n = max(2, int(scale * 2 ** o))
        grid = g.random((int(n * 0.75) + 3, n + 3)).astype(np.float32)
        z = ndimage.zoom(grid, (H / (grid.shape[0] - 3), W / (grid.shape[1] - 3)), order=3)[:H, :W]
        out += z * amp; tot += amp; amp *= persist
    return out / tot


def poly_dist(pts, step=0.002):
    """Distance field (normalised units) to a polyline."""
    mask = np.ones((H, W), bool)
    im = Image.new("L", (W, H), 0); d = ImageDraw.Draw(im)
    d.line([(x * S, y * S) for x, y in pts], fill=255, width=2)
    return ndimage.distance_transform_edt(np.array(im) == 0).astype(np.float32) / S


def meander(pts, amp=0.012, seed=5, step=0.004):
    """Densify a polyline and add sinuous bends so rivers wander like real ones."""
    rr = np.random.default_rng(seed)
    out = []
    ph = rr.uniform(0, 6.28)
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        L = math.hypot(x1 - x0, y1 - y0); n = max(2, int(L / step))
        nx_, ny_ = -(y1 - y0) / L, (x1 - x0) / L
        for k in range(n):
            t = k / n
            ph += step * rr.uniform(40, 90)
            o = amp * (math.sin(ph) + 0.4 * math.sin(ph * 2.3 + 1))
            out.append((x0 + (x1 - x0) * t + nx_ * o, y0 + (y1 - y0) * t + ny_ * o))
    out.append(pts[-1])
    return out


def gauss(cx, cy, r):
    return np.exp(-(((X - cx) ** 2 + (Y - cy) ** 2) / (r * r)))


def ellipse(cx, cy, rx, ry):
    return ((X - cx) / rx) ** 2 + ((Y - cy) / ry) ** 2


print("terrain...", flush=True)
n1 = fbm(3, 7, 0.52, 1)
n2 = fbm(8, 5, 0.55, 2)
ridge = ndimage.gaussian_filter(1 - np.abs(2 * fbm(6, 6, 0.55, 3) - 1), 2.5)
# ---------------------------------------------------------------- height
h = 0.32 + 0.05 * (n1 - 0.5) + 0.015 * (n2 - 0.5)
mtn = np.exp(-((X - 0.11 + 0.04 * (n2 - 0.5)) / 0.085) ** 2) * (0.35 + 0.65 * ridge)
h += 0.55 * mtn
h += 0.16 * gauss(0.88, 0.25, 0.09) * (0.6 + 0.4 * ridge)              # eastern hills
h += 0.07 * gauss(0.31, 0.36, 0.05) * (0.5 + 0.5 * ridge)              # shelter hills
h += 0.05 * gauss(0.215, 0.39, 0.04)
h += 0.06 * np.clip((Y - 0.05) / 0.2, 0, 1) * np.clip((0.3 - Y) / 0.1, 0, 1) * (fbm(7, 5, 0.5, 4) - 0.5)   # rolling forest hills
# desert mesas: terraced plateaus
desert = np.clip((Y - 0.52) / 0.08, 0, 1) * np.clip((0.82 - X) / 0.06, 0, 1) * np.clip((X - 0.18) / 0.06, 0, 1)
mesa_n = fbm(6, 4, 0.5, 9)
mesas = np.clip((mesa_n - 0.58) * 9, 0, 1)
h += desert * mesas * 0.14
# river valley + lake
RIV = meander(LOC.RIVER + [LOC.LAKE["center"]], 0.009, 5)
RIV_OUT = meander(LOC.RIVER_OUT, 0.006, 6)
rd = poly_dist(RIV)
rd_out = poly_dist(RIV_OUT)
rdist = np.minimum(rd, rd_out)
h -= 0.12 * ndimage.gaussian_filter(np.exp(-(rdist / 0.04) ** 2), 14)
lk = ellipse(LOC.LAKE["center"][0], LOC.LAKE["center"][1], LOC.LAKE["rx"], LOC.LAKE["ry"]) + 1.1 * (fbm(18, 4, 0.55, 21) - 0.5)
lk = np.minimum(lk, ellipse(LOC.LAKE["center"][0] - 0.03, LOC.LAKE["center"][1] - 0.025, 0.022, 0.014) + 0.8 * (n2 - 0.5))
# canyon in the south-west badlands
cd = poly_dist([(0.19, 0.57), (0.23, 0.6), (0.26, 0.64), (0.29, 0.7), (0.31, 0.75)])
h -= 0.12 * np.exp(-(cd / 0.012) ** 2) * (1 + 0.5 * n2)
# crater bowl with a raised rim
cr = np.sqrt((X - LOC.CRATER["center"][0]) ** 2 + (Y - LOC.CRATER["center"][1]) ** 2) / LOC.CRATER["r"]
h += -0.12 * np.exp(-cr ** 2 * 1.5) + 0.06 * np.exp(-((cr - 1.15) / 0.25) ** 2)

# ---------------------------------------------------------------- water
water = (rdist < 0.0035 + 0.0035 * np.clip((X - 0.2) / 0.5, 0, 1)) | (lk < 1.0)
for (c, r) in LOC.LAKES_SMALL:
    water |= (ellipse(c[0], c[1], r * 1.3, r) + 1.2 * (fbm(24, 3, 0.5, 30) - 0.5)) < 1.0

# ---------------------------------------------------------------- biomes (weights)
farm_pre = np.exp(-(rdist / 0.07) ** 2) * np.clip((X - 0.28) / 0.05, 0, 1) * np.clip((0.62 - X) / 0.05, 0, 1) * np.clip((0.45 - Y) / 0.05, 0, 1)
moist = np.clip(1.15 - Y / 0.45, 0, 1) * 0.7 + 0.5 * np.exp(-(rdist / 0.05) ** 2) + 0.25 * (n1 - 0.5)
forest = np.clip((moist - 0.5) * 5, 0, 1) * np.clip((0.3 - Y) / 0.05, 0, 1) * np.clip(1 - farm_pre * 1.5, 0, 1)
forest = np.maximum(forest, np.clip((mtn - 0.25) * 3, 0, 1) * np.clip((0.4 - Y) / 0.1, 0, 1) * 0.8)
forest *= np.clip((fbm(14, 4, 0.5, 11) - 0.3) * 4, 0, 1)
clumps = np.clip((fbm(60, 2, 0.5, 15) - 0.45) * 6, 0, 1)
forest = np.clip(forest * (0.75 + 0.5 * clumps), 0, 1)
sand = np.clip((Y - 0.5) / 0.1, 0, 1) * np.clip(1 - mtn * 2.5, 0, 1)
bad = np.clip(1 - np.sqrt((X - 0.23) ** 2 + (Y - 0.6) ** 2) / 0.09, 0, 1) ** 0.7
salt = np.clip(1 - ellipse(LOC.SALT["center"][0], LOC.SALT["center"][1], LOC.SALT["rx"], LOC.SALT["ry"]) - 1.4 * (fbm(16, 5, 0.6, 22) - 0.5), 0, 1)
salt = np.clip(salt * 4, 0, 1) * (0.85 + 0.15 * fbm(60, 2, 0.5, 23))
farm = np.exp(-(rdist / 0.07) ** 2) * np.clip((X - 0.28) / 0.05, 0, 1) * np.clip((0.62 - X) / 0.05, 0, 1) * np.clip((0.45 - Y) / 0.05, 0, 1)
farm = np.clip(farm * 1.6, 0, 1)


def col(hexs):
    h_ = hexs.lstrip('#')
    return np.array([int(h_[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


C = {k: col(v) for k, v in dict(plains="#8e8458", plains2="#7a7a4a", forest="#4e6234", forest2="#34452a", sand="#c2a46c",
                                 sand2="#b08c58", rock="#6a5a46", peak="#8a7c66", bad="#9a5a3a", salt="#e2dcc8", farm1="#a89a5a",
                                 farm2="#8a8a48", farm3="#9a7a4a", water="#3e5a5e", water2="#2e4a52", ruin="#6e6a62", ruin2="#4e4a46",
                                 scorch="#2e2a24", glow="#7adf4a").items()}

print("colour...", flush=True)
img = np.zeros((H, W, 3), np.float32)
pl = C["plains"] * (1 - n2[..., None]) + C["plains2"] * n2[..., None]
img[:] = pl
fv = fbm(30, 3, 0.5, 12)[..., None]
img = img * (1 - forest[..., None]) + (C["forest"] * (1 - fv) + C["forest2"] * fv) * forest[..., None]
sv = fbm(10, 4, 0.5, 13)[..., None]
img = img * (1 - sand[..., None]) + (C["sand"] * (1 - sv) + C["sand2"] * sv) * sand[..., None]
img = img * (1 - bad[..., None]) + C["bad"] * bad[..., None]
# fields: patchwork of rectangles near the river
fi = Image.new("RGB", (W, H), tuple(int(v * 255) for v in C["farm2"])); fd = ImageDraw.Draw(fi)
for k in range(9000):
    x, y = R.uniform(0, W), R.uniform(0, H)
    w_, h_ = R.uniform(8, 26), R.uniform(6, 20)
    c = R.choice([C["farm1"], C["farm2"], C["farm3"], C["plains"]])
    fd.rectangle((x, y, x + w_, y + h_), fill=tuple(int(v * 255) for v in c))
fields = np.array(fi).astype(np.float32) / 255
fields = fields * (0.85 + 0.3 * fbm(40, 2, 0.5, 16)[..., None])
img = img * (1 - farm[..., None] * 0.85) + fields * farm[..., None] * 0.85
img = img * (1 - salt[..., None]) + C["salt"] * salt[..., None]
# mountains: rock by height, pale peaks
rock = np.clip((h - 0.48) * 6, 0, 1)
img = img * (1 - rock[..., None]) + (C["rock"] * (1 - ridge[..., None]) + C["peak"] * ridge[..., None]) * rock[..., None]
peak = np.clip((h - 0.78) * 6, 0, 1) * 0.6
img = img * (1 - peak[..., None]) + C["peak"] * peak[..., None]
# crater: scorched with a sickly glow at the bottom
sc = np.clip(1.6 - cr, 0, 1)
img = img * (1 - sc[..., None] * 0.85) + C["scorch"] * sc[..., None] * 0.85
gl = np.exp(-cr ** 2 * 4)
img = img * (1 - gl[..., None] * 0.7) + C["glow"] * gl[..., None] * 0.7

# ---------------------------------------------------------------- hillshade
hs = ndimage.gaussian_filter(h, 1.2) + 0.012 * (fbm(50, 3, 0.5, 17) - 0.5)
gy, gx = np.gradient(hs * 520)
nx, ny, nz = -gx, -gy, np.ones_like(h)
ln = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
light = np.array([-0.6, -0.6, 0.55]); light /= np.linalg.norm(light)
shade = (nx * light[0] + ny * light[1] + nz * light[2]) / ln
shade = np.clip(shade, 0, 1)
flat_shade = (light[2] / 1.0)
img *= np.clip(0.3 + 0.75 * shade / flat_shade, 0.4, 1.18)[..., None]

# ---------------------------------------------------------------- water on top (flat, with banks)
wv = fbm(20, 3, 0.5, 14)[..., None]
img[water] = (C["water"] * (1 - wv) + C["water2"] * wv)[water]
bank = ndimage.binary_dilation(water, iterations=2) & ~water
img[bank] = img[bank] * 0.7 + np.array([0.35, 0.3, 0.22]) * 0.3

# ---------------------------------------------------------------- ruins: city blocks + suburbs
def urban(cx, cy, r, dense):
    m = np.clip(1 - np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) / r - 0.3 * (n2 - 0.5), 0, 1)
    m = np.clip(m * (3 if dense else 2), 0, 1) * (~water)
    ui = Image.new("RGB", (W, H), (0, 0, 0)); ud = ImageDraw.Draw(ui)
    step = 9 if dense else 7
    x0, x1 = int((cx - r) * S), int((cx + r) * S); y0, y1 = int((cy - r) * S), int((cy + r) * S)
    for gy_ in range(y0, y1, step):
        for gx_ in range(x0, x1, step):
            if R.random() < (0.85 if dense else 0.55):
                c = R.choice([C["ruin"], C["ruin2"], C["ruin"] * 1.15]) if dense else R.choice([C["ruin"] * 1.2, C["farm3"], C["ruin"]])
                s_ = step - (2 if dense else 3)
                ud.rectangle((gx_, gy_, gx_ + s_, gy_ + s_), fill=tuple(int(min(1, v) * 255) for v in c))
    u = np.array(ui).astype(np.float32) / 255
    has = (u.sum(-1) > 0)[..., None]
    base = img * 0.55 + C["ruin2"] * 0.45
    return np.where(has, u * (0.6 + 0.5 * shade[..., None]), base), m


cm, mm = urban(LOC.CITY["center"][0], LOC.CITY["center"][1], LOC.CITY["r"], True)
img = img * (1 - mm[..., None]) + cm * mm[..., None]
for (c, r) in LOC.SUBURBS + [((0.495, 0.452), 0.016), ((0.44, 0.445), 0.012), ((0.4, 0.29), 0.014), ((0.255, 0.155), 0.012),
                              ((0.205, 0.545), 0.013), ((0.505, 0.618), 0.013), ((0.79, 0.598), 0.012), ((0.305, 0.675), 0.016)]:
    sm, smm = urban(c[0], c[1], r, False)
    img = img * (1 - smm[..., None]) + sm * smm[..., None]

base_img = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))

# ---------------------------------------------------------------- routes
print("routes...", flush=True)
POS = {l["id"]: l["pos"] for l in LOC.L}


def pts_of(seq):
    out = []
    for p in seq:
        p = POS[p] if isinstance(p, str) else p
        out.append(p)
    return out


def wobble(pts, amt, seed):
    rr = random.Random(seed)
    out = []
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        n = max(2, int(math.hypot(x1 - x0, y1 - y0) / 0.012))
        for k in range(n):
            t = k / n
            j = math.sin(t * math.pi) * amt
            out.append(((x0 + (x1 - x0) * t + rr.uniform(-j, j)) * S, (y0 + (y1 - y0) * t + rr.uniform(-j, j)) * S))
    out.append((pts[-1][0] * S, pts[-1][1] * S))
    # smooth
    sm = [out[0]] + [((out[i - 1][0] + out[i][0] * 2 + out[i + 1][0]) / 4, (out[i - 1][1] + out[i][1] * 2 + out[i + 1][1]) / 4)
                     for i in range(1, len(out) - 1)] + [out[-1]]
    return sm


rt = base_img.convert("RGBA")
over = Image.new("RGBA", (W, H), (0, 0, 0, 0)); od = ImageDraw.Draw(over)
STY = {"interstate": ((40, 34, 28, 255), 6, (196, 176, 130, 255), 3, 0.002),
       "highway": ((50, 42, 32, 230), 4, (176, 152, 108, 255), 2, 0.004),
       "road": ((60, 50, 38, 200), 3, (150, 128, 92, 255), 1, 0.006),
       "track": (None, 0, (92, 76, 56, 200), 2, 0.008)}
route_paths = []
for i, (kind, seq) in enumerate(LOC.ROUTES):
    p = wobble(pts_of(seq), STY.get(kind, (0, 0, 0, 0, 0.003))[4] if kind != "rail" else 0.002, i)
    route_paths.append((kind, p))
for layer in ("track", "road", "highway", "interstate"):
    for kind, p in route_paths:
        if kind != layer: continue
        oc, ow, fc, fw, _ = STY[kind]
        if kind == "track":
            for k in range(0, len(p) - 1, 2):
                od.line([p[k], p[k + 1]], fill=fc, width=fw)
        else:
            od.line(p, fill=oc, width=ow, joint="curve")
for layer in ("road", "highway", "interstate"):
    for kind, p in route_paths:
        if kind == layer:
            od.line(p, fill=STY[kind][2], width=STY[kind][3], joint="curve")
for kind, p in route_paths:
    if kind != "rail": continue
    od.line(p, fill=(30, 26, 22, 255), width=2)
    for k in range(0, len(p) - 1):
        (x0, y0), (x1, y1) = p[k], p[k + 1]
        L_ = math.hypot(x1 - x0, y1 - y0)
        if L_ < 1e-3: continue
        nx_, ny_ = -(y1 - y0) / L_ * 3, (x1 - x0) / L_ * 3
        for t in np.arange(0, L_, 6):
            cx_, cy_ = x0 + (x1 - x0) * t / L_, y0 + (y1 - y0) * t / L_
            od.line([(cx_ - nx_, cy_ - ny_), (cx_ + nx_, cy_ + ny_)], fill=(30, 26, 22, 255), width=1)
# dam wall across the lake outlet
dx, dy = LOC.L[[l["id"] for l in LOC.L].index("hollister_dam")]["pos"]
od.line([((dx - 0.018) * S, (dy - 0.004) * S), ((dx + 0.012) * S, (dy - 0.012) * S)], fill=(200, 194, 180, 255), width=6)
rt.alpha_composite(over)

# ---------------------------------------------------------------- paper finish: grain, vignette, faint grid
arr = np.array(rt.convert("RGB")).astype(np.float32) / 255
grain = rng.normal(0, 0.035, (H, W, 1)).astype(np.float32)
arr = arr + grain
vig = np.clip(1.15 - 0.55 * (((X - 0.5) / 0.6) ** 2 + ((Y - 0.375) / 0.45) ** 2), 0.55, 1.0)[..., None]
arr *= vig
sep = np.array([1.04, 0.98, 0.86], np.float32)
arr = arr * 0.82 + (arr.mean(-1, keepdims=True) * sep) * 0.18
for gx_ in range(0, W, 50):
    arr[:, gx_] *= 0.9
for gy_ in range(0, H, 50):
    arr[gy_, :] *= 0.9
final = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
# painted landform names (part of the base map, like Fallout 2's): faded italic serif
fd2 = ImageDraw.Draw(final, "RGBA")
fi_ = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-BoldItalic.ttf"
for (text, x, y, size, ang) in LOC.FEATURES:
    f_ = ImageFont.truetype(fi_, size)
    tw_ = fd2.textlength(text, font=f_)
    t_im = Image.new("RGBA", (int(tw_) + 10, size + 14), (0, 0, 0, 0))
    td = ImageDraw.Draw(t_im)
    td.text((5, 3), text, font=f_, fill=(30, 24, 16, 150))
    td.text((4, 2), text, font=f_, fill=(236, 220, 180, 120))
    t_im = t_im.rotate(ang, expand=True, resample=Image.BICUBIC)
    final.paste(t_im, (int(x * S - t_im.width / 2), int(y * S - t_im.height / 2)), t_im)
os.makedirs(OUT, exist_ok=True)
final.save(os.path.join(OUT, "worldmap.png"))

# ---------------------------------------------------------------- data
data = {"region": LOC.REGION, "size": [W, H], "grid": 50,
        "locations": [dict(l, px=[round(l["pos"][0] * S), round(l["pos"][1] * S)]) for l in LOC.L],
        "routes": [{"kind": k, "path": [[round(x), round(y)] for x, y in p]} for k, p in route_paths]}
json.dump(data, open(os.path.join(OUT, "locations.json"), "w"), indent=1)

# ---------------------------------------------------------------- labelled preview
lab = final.convert("RGBA")
ld = ImageDraw.Draw(lab)
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", 15)
fsmall = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", 12)
ftitle = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 40)
TC = {"city": (230, 70, 50), "district": (220, 120, 70), "town": (90, 210, 90), "settlement": (130, 220, 130),
      "camp": (220, 180, 70), "landmark": (230, 210, 120), "dungeon": (220, 80, 80)}
RAD = {"city": 14, "district": 8, "town": 11, "settlement": 8, "camp": 6, "landmark": 7, "dungeon": 7}
placed = []
for l in sorted(LOC.L, key=lambda l: -RAD[l["type"]]):
    x, y = l["pos"][0] * S, l["pos"][1] * S
    r = RAD[l["type"]]
    c = TC[l["type"]]
    ld.ellipse((x - r - 2, y - r - 2, x + r + 2, y + r + 2), outline=(20, 16, 12, 255), width=2)
    ld.ellipse((x - r, y - r, x + r, y + r), outline=c + (255,), width=2)
    ld.ellipse((x - 2, y - 2, x + 2, y + 2), fill=c + (255,))
    f = font if l["type"] in ("city", "town") else fsmall
    name = l["name"]
    tw = ld.textlength(name, font=f)
    # pick a label spot that doesn't overlap earlier labels
    for (ox, oy) in ((r + 5, -8), (-tw - r - 5, -8), (-tw / 2, r + 3), (-tw / 2, -r - 18), (r + 5, 6), (-tw - r - 5, 6)):
        box = (x + ox, y + oy, x + ox + tw, y + oy + 15)
        if all(box[2] < b[0] or box[0] > b[2] or box[3] < b[1] or box[1] > b[3] for b in placed):
            break
    placed.append(box)
    for dx_, dy_ in ((-1, 0), (1, 0), (0, -1), (0, 1), (1, 1)):
        ld.text((box[0] + dx_, box[1] + dy_), name, font=f, fill=(16, 12, 8, 255))
    ld.text((box[0], box[1]), name, font=f, fill=c + (255,))
title = LOC.REGION.upper()
tw = ld.textlength(title, font=ftitle)
ld.text((W - tw - 30 + 2, 22 + 2), title, font=ftitle, fill=(16, 12, 8, 255))
ld.text((W - tw - 30, 22), title, font=ftitle, fill=(226, 196, 120, 255))
# legend
lg = [("City", "city"), ("District", "district"), ("Town", "town"), ("Settlement", "settlement"), ("Camp", "camp"), ("Landmark", "landmark"), ("Dungeon", "dungeon")]
ld.rectangle((20, H - 40 - 22 * len(lg) - 70, 220, H - 20), fill=(20, 16, 12, 200))
yy = H - 30 - 22 * len(lg) - 70
for name, t in lg:
    ld.ellipse((34, yy + 3, 46, yy + 15), outline=TC[t] + (255,), width=2)
    ld.text((56, yy), name, font=fsmall, fill=(220, 210, 180, 255)); yy += 22
for name, cc, wd in (("Interstate", (196, 176, 130), 3), ("Highway / road", (176, 152, 108), 2)):
    ld.line((30, yy + 8, 50, yy + 8), fill=cc + (255,), width=wd + 2); ld.text((56, yy), name, font=fsmall, fill=(220, 210, 180, 255)); yy += 20
ld.line((30, yy + 8, 50, yy + 8), fill=(30, 26, 22, 255), width=2)
for t in range(30, 52, 6): ld.line((t, yy + 5, t, yy + 11), fill=(30, 26, 22, 255))
ld.text((56, yy), "Railway", font=fsmall, fill=(220, 210, 180, 255))
os.makedirs("/tmp/r3d", exist_ok=True)
lab.convert("RGB").save("/tmp/r3d/worldmap_labeled.png")
print("done", len(LOC.L), "locations", flush=True)
