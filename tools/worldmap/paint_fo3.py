"""Paint the final world map from the hand-laid layout in layout_fo3.py.
python3 tools/worldmap/paint_fo3.py
  -> assets/worldmap/worldmap.png        unlabelled terrain the game draws markers on
  -> assets/worldmap/locations.json      locations (normalised + pixel positions), roads
  -> /tmp/r3d/worldmap_labeled.png       preview with markers and names"""
import os, sys, json, math, random
os.environ.setdefault("WM_N", "2048")
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout_fo3 as LY
import locations as LOC

N = LY.N; S = LY.S; X, Y = LY.X, LY.Y
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "worldmap")
FONT = "/usr/share/fonts/truetype/dejavu/"


def fbm(seed, base, octaves=5, persist=0.55):
    t = np.zeros((N, N), np.float32); a = 1.0; tot = 0
    for o in range(octaves):
        t += a * LY.noise(seed * 31 + o, int(base * 2 ** o)); tot += a; a *= persist
    return t / tot


def soft(m, px):
    return ndimage.gaussian_filter(m.astype(np.float32), px)


def col(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


C = {k: col(v) for k, v in dict(waste="#9a8a62", waste2="#7e7552", dust="#b49c6a", hill="#7a6a4e", peak="#9a8c74",
                                 dead="#58583a", dead2="#3e3e28", farm1="#a8975e", farm2="#7e7a48", farm3="#957050", farm4="#6a6c48",
                                 salt="#e4ddc8", marsh="#6a7a4a", marsh2="#4e6236", canyon="#a0583a", canyon2="#7a3e2a", water="#3c5860", water2="#2a434c",
                                 city="#6c6862", city2="#4c4844", sub="#8a8270", scorch="#2a2620", glow="#86e050").items()}
# --- touch-ups to the layout masks for painting
(lx, ly), lr = LY.LAKE
old_lake = LY.blob(lx, ly, lr, 4, 0.35)
ang = np.arctan2(Y - ly, X - lx)
lake = np.hypot((X - lx) / 1.25, Y - ly) / lr + 0.28 * np.sin(ang * 3 + 1) + 0.5 * (LY.noise(40, 40) - 0.5) < 1
lake |= np.hypot((X - lx + 0.05) / 2.2, Y - ly - 0.004) / 0.012 + 0.6 * (LY.noise(41, 50) - 0.5) < 1   # arm up the creek
lake &= Y < 0.15
LY.water = (LY.water & ~old_lake) | lake
LY.water &= ~LY.island
LY.farms = (LY.blob(0.37, 0.31, 0.085, 42, 0.45) | LY.blob(0.47, 0.27, 0.05, 43, 0.4) | LY.blob(0.36, 0.67, 0.04, 44, 0.5)) & ~LY.deadwood & ~LY.hills & ~LY.water
print("height...", flush=True)
fine = fbm(1, 6)
detail = fbm(2, 40, 3)
hills_s = soft(LY.hills, N * 0.008)
peaks_s = soft(LY.peaks, N * 0.02)
H = 0.12 * fine + 0.02 * detail
ridge = (1 - np.abs(fbm(3, 14, 5) * 2 - 1)) ** 2                   # ridged noise for hill crests
H += hills_s * (0.35 + 0.55 * ridge) + peaks_s * (0.5 + 0.6 * ridge)
canyon_s = soft(LY.canyon, N * 0.006)
H -= canyon_s * (0.15 + 0.25 * ridge)
cx, cy = LY.crater_c; cr = np.hypot(X - cx, Y - cy) / LY.crater_r
H += np.exp(-((cr - 1.0) / 0.18) ** 2) * 0.18 - np.clip(1 - cr, 0, 1) * 0.25
for (x, y, r) in LY.craters:
    d = np.hypot(X - x, Y - y) / r
    H += np.exp(-((d - 1) / 0.25) ** 2) * 0.03 - np.clip(1 - d, 0, 1) * 0.04
water_s = soft(LY.water, N * 0.004)
H -= water_s * 0.12
# hillshade (light from the north-west)
gy, gx = np.gradient(H * N * 0.07)
L = np.array([0.55, 0.55, 0.63]); L /= np.linalg.norm(L)
shade = (gx * L[0] + gy * L[1] + L[2]) / np.sqrt(gx ** 2 + gy ** 2 + 1) / L[2]
shade = np.clip(0.35 + 0.65 * shade, 0.45, 1.3)

print("colour...", flush=True)
mix = fbm(4, 8)
img = C["waste"] * (1 - mix[..., None]) + C["waste2"] * mix[..., None]
dust = np.clip((fbm(5, 5) - 0.55) * 4, 0, 1) * (1 - hills_s)
img = img * (1 - dust[..., None] * 0.6) + C["dust"] * dust[..., None] * 0.6


def lay(mask_f, c):
    global img
    m = np.clip(mask_f, 0, 1)[..., None]
    img = img * (1 - m) + c * m


lay(hills_s * 1.2, C["hill"] * (0.9 + 0.2 * fine[..., None]))
lay(peaks_s * 1.3 * (ridge[..., None] > 0.5).squeeze(), C["peak"])
# farm fields: a patchwork of rotated plots
farm_s = soft(LY.farms, N * 0.004)
cells = np.floor((X * 0.8 + Y * 0.3) * 150) * 131 + np.floor((Y * 0.8 - X * 0.3) * 120) * 17
k = (np.sin(cells) * 43758.5453) % 1
fc = np.where(k[..., None] < 0.3, C["farm1"], np.where(k[..., None] < 0.55, C["farm2"], np.where(k[..., None] < 0.8, C["farm3"], C["farm4"])))
lay(farm_s, fc * (0.92 + 0.08 * detail[..., None]))
marsh_s = soft(LY.marsh, N * 0.006)
lay(marsh_s, C["marsh"] * (1 - mix[..., None] * 0.5) + C["marsh2"] * mix[..., None] * 0.5)
dead_s = soft(LY.deadwood, N * 0.006)
lay(dead_s, C["dead"] * (1 - mix[..., None] * 0.3) + C["dead2"] * mix[..., None] * 0.3)
lay(soft(LY.salt, N * 0.008) * 1.2, C["salt"] * (0.95 + 0.05 * detail[..., None]))
strata = (np.sin(fbm(45, 12, 3) * 60 + X * 30) * 0.5 + 0.5)[..., None]
lay(canyon_s * 1.3, C["canyon"] * strata + C["canyon2"] * (1 - strata))
crat = np.clip(1.15 - cr, 0, 1)
lay(np.clip(crat * 3, 0, 1), C["scorch"] * (0.8 + 0.4 * detail[..., None]))
burn = np.exp(-((cr - 1.6) / 0.7) ** 2) * 0.35
lay(burn, C["scorch"])
sub_s = soft(LY.suburbs, N * 0.003)
lay(sub_s * 0.9, C["sub"])
city_s = soft(LY.city, N * 0.002)
lay(city_s, C["city"] * (0.9 + 0.2 * detail[..., None]))
lay(soft(LY.city_core, N * 0.003) * 0.8, C["city2"])
img = img * shade[..., None]
# water last, unshaded, with a darker channel
deep = soft(LY.water, N * 0.0025)
wc = C["water"] * (1 - deep[..., None] * 0.4) + C["water2"] * deep[..., None] * 0.4
lay(np.clip(water_s * 2.2 - 0.6, 0, 1), wc)
glow = np.clip(1 - cr * 1.4, 0, 1) ** 1.5
img = img + C["glow"] * glow[..., None] * 0.55
grain = (np.random.default_rng(9).random((N, N)).astype(np.float32) - 0.5) * 0.05
img = img * (1 + grain[..., None])
im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
d = ImageDraw.Draw(im, "RGBA")

print("details...", flush=True)
rr = random.Random(11)
sx = N / 1200                                                # scale of hand-tuned pixel sizes
# dead trees
for _ in range(int(5000 * sx * sx)):
    x, y = rr.random(), rr.random()
    i, j = int(y * N), int(x * N)
    if LY.deadwood[i, j] and not LY.water[i, j] and rr.random() < 0.9:
        px, py = x * N, y * N; h = rr.uniform(4, 8) * sx
        d.line((px, py, px, py - h), fill=(40, 36, 26, 220), width=max(1, int(sx)))
        d.line((px, py - h * 0.6, px - h * 0.35, py - h * 0.9), fill=(40, 36, 26, 200), width=1)
        d.line((px, py - h * 0.5, px + h * 0.3, py - h * 0.8), fill=(40, 36, 26, 200), width=1)
# scrub on the open waste
for _ in range(int(9000 * sx * sx)):
    x, y = rr.random(), rr.random()
    i, j = int(y * N), int(x * N)
    if not (LY.water[i, j] or LY.city[i, j] or LY.suburbs[i, j] or LY.salt[i, j] or LY.deadwood[i, j] or LY.marsh[i, j]) and crat[i, j] == 0:
        px, py = x * N, y * N; r = rr.uniform(0.8, 1.8) * sx
        d.ellipse((px - r, py - r, px + r, py + r), fill=(70, 62, 40, 110))
# city blocks: a street grid of buildings, darker and taller in the core
for _ in range(int(26000 * sx * sx)):
    x, y = rr.uniform(0.66, 1), rr.uniform(0.3, 1)
    i, j = int(y * N), int(x * N)
    if (LY.city[i, j] or LY.suburbs[i, j]) and not LY.water[i, j]:
        core = LY.city_core[i, j]; sub = LY.suburbs[i, j] and not LY.city[i, j]
        g = 0.0045 if sub else 0.0055
        bx, by = round(x / g) * g, round(y / g) * g
        w = g * (0.35 if sub else rr.uniform(0.5, 0.75)) * N
        px, py = bx * N, by * N
        c = (int(rr.uniform(150, 190)), int(rr.uniform(140, 170)), 130) if sub else (int(rr.uniform(60, 120)),) * 3
        if core and rr.random() < 0.4:
            d.rectangle((px + w * 0.25, py + w * 0.25, px + w * 1.25, py + w * 1.25), fill=(20, 18, 16, 120))   # shadow of a tower
        d.rectangle((px, py, px + w, py + w), fill=c + (230,))
        if rr.random() < 0.15 and not sub:
            d.ellipse((px - w * 0.3, py - w * 0.3, px + w * 0.5, py + w * 0.5), fill=(40, 36, 32, 160))      # rubble/fire scar
# marsh: pools, paddies and reed tufts
for _ in range(int(2600 * sx * sx)):
    x, y = rr.uniform(0.55, 0.82), rr.uniform(0.82, 1); i, j = min(int(y * N), N - 1), min(int(x * N), N - 1)
    if LY.marsh[i, j] and not LY.water[i, j]:
        px, py = x * N, y * N
        if rr.random() < 0.07:
            r = rr.uniform(2, 5) * sx; d.ellipse((px - r, py - r * 0.6, px + r, py + r * 0.6), fill=(62, 86, 88, 190))
        else:
            for q in range(3): d.line((px + q * sx, py, px + (q - 1) * 2 * sx, py - 4 * sx), fill=(52, 70, 40, 200), width=1)
# dry washes: thin dark meandering beds across the waste
for k in range(14):
    x, y = rr.uniform(0.05, 0.6), rr.uniform(0.3, 0.98); a = rr.uniform(0, 6.28); pts = []
    for t in range(rr.randint(20, 45)):
        a += rr.uniform(-0.5, 0.5); x += math.cos(a) * 0.004; y += math.sin(a) * 0.004; pts.append((x * N, y * N))
    d.line(pts, fill=(64, 54, 36, 110), width=max(1, int(1.5 * sx)), joint="curve")
# hill crest ticks (old survey-map hachures)
for _ in range(int(7000 * sx * sx)):
    x, y = rr.random(), rr.random(); i, j = int(y * N), int(x * N)
    if hills_s[i, j] > 0.5 and ridge[i, j] > 0.45 and not LY.water[i, j]:
        px, py = x * N, y * N; h = (3 + 4 * ridge[i, j]) * sx
        d.line((px - h * 0.6, py + h * 0.3, px, py - h * 0.4, px + h * 0.6, py + h * 0.3), fill=(50, 40, 28, 120), width=1)
# small craters rims
for (x, y, r) in LY.craters:
    d.ellipse(((x - r) * N, (y - r) * N, (x + r) * N, (y + r) * N), outline=(60, 54, 40, 120), width=max(1, int(2 * sx)))
# city arteries: a skewed street grid plus diagonals out to the beltway
for k in range(-30, 31):
    for (dx0, dy0, dx1, dy1) in ((0.02 * k, -0.4, 0.02 * k + 0.08, 0.4), (-0.4, 0.02 * k, 0.4, 0.02 * k - 0.05)):
        cx0, cy0 = 0.82, 0.62
        pts = [(cx0 + dx0 + (dx1 - dx0) * t / 60, cy0 + dy0 + (dy1 - dy0) * t / 60) for t in range(61)]
        run = []
        for (x, y) in pts:
            if 0 <= x < 1 and 0 <= y < 1 and LY.city[int(y * N), int(x * N)] and not LY.water[int(y * N), int(x * N)]:
                run.append((x * N, y * N))
            else:
                if len(run) > 1: d.line(run, fill=(150, 144, 132, 150), width=max(1, int(1.6 * sx)))
                run = []
        if len(run) > 1: d.line(run, fill=(150, 144, 132, 150), width=max(1, int(1.6 * sx)))
# farm buildings / grain elevator near Goldenrod, ranch corrals
for _ in range(int(40 * sx)):
    x, y = rr.random(), rr.random()
    if LY.farms[int(y * N), int(x * N)]:
        d.rectangle((x * N, y * N, x * N + 4 * sx, y * N + 3 * sx), fill=(110, 70, 50, 230))
# dam
d.line((0.64 * N, 0.152 * N, 0.69 * N, 0.152 * N), fill=(200, 196, 182, 255), width=int(7 * sx))
d.line((0.64 * N, 0.152 * N + 4 * sx, 0.69 * N, 0.152 * N + 4 * sx), fill=(90, 86, 80, 255), width=int(2 * sx))

print("roads...", flush=True)
STY = {"interstate": ((44, 34, 26, 255), 7, (200, 180, 136, 255), 3), "highway": ((60, 48, 36, 255), 5, (176, 156, 116, 255), 2),
       "road": ((84, 68, 50, 230), 3, None, 0), "track": ((96, 80, 60, 200), 2, None, 0)}
road_out = []
for kind in ("track", "road", "highway", "interstate"):
    for kk, pts in LY.ROADS:
        if kk != kind: continue
        px_ = [(x * N, y * N) for x, y in pts]
        road_out.append(dict(kind=kind, path=[[round(x / N, 4), round(y / N, 4)] for x, y in px_[::3] + [px_[-1]]]))
        if kind == "track":
            for i in range(0, len(px_) - 1):
                pass
            n = int(math.dist(px_[0], px_[-1]) / (7 * sx))
            for i in range(0, n, 2):
                a = [px_[0][q] + (px_[-1][q] - px_[0][q]) * i / n for q in (0, 1)]
                b = [px_[0][q] + (px_[-1][q] - px_[0][q]) * (i + 1) / n for q in (0, 1)]
                d.line((tuple(a), tuple(b)), fill=STY[kind][0], width=int(STY[kind][1] * sx))
        else:
            d.line(px_, fill=STY[kind][0], width=int(STY[kind][1] * sx), joint="curve")
for kind in ("highway", "interstate"):
    for kk, pts in LY.ROADS:
        if kk == kind:
            px_ = [(x * N, y * N) for x, y in pts]
            # broken centre line: gaps where the road is wrecked
            seg = []
            for i, p in enumerate(px_):
                seg.append(p)
                if len(seg) > 6 and rr.random() < 0.08:
                    d.line(seg, fill=STY[kind][2], width=int(STY[kind][3] * sx), joint="curve"); seg = [p]
                    if rr.random() < 0.5: seg = []
            if len(seg) > 1:
                d.line(seg, fill=STY[kind][2], width=int(STY[kind][3] * sx), joint="curve")
# broken bridge gap on Founders Bridge
bx, by = LY.P["founders_bridge"]
d.ellipse(((bx + 0.012) * N - 6 * sx, (by + 0.004) * N - 6 * sx, (bx + 0.012) * N + 6 * sx, (by + 0.004) * N + 6 * sx), fill=tuple((C["water"] * 255).astype(int)) + (255,))
mp = [(x * N, y * N) for x, y in LY.METRO]
for i in range(0, len(mp) - 1, 2):
    d.line((mp[i], mp[i + 1]), fill=(46, 52, 70, 200), width=int(2 * sx))

print("finish...", flush=True)
# paper: vignette, faint grid, landform names
a = np.array(im).astype(np.float32) / 255
v = np.clip(1 - (np.hypot(X - 0.5, Y - 0.5) / 0.75) ** 3, 0.55, 1)
a *= v[..., None]
im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
d = ImageDraw.Draw(im, "RGBA")
for g in range(1, 16):
    p = g * N / 16
    d.line((p, 0, p, N), fill=(30, 26, 20, 26), width=1); d.line((0, p, N, p), fill=(30, 26, 20, 26), width=1)
tf = ImageFont.truetype(FONT + "DejaVuSerif-BoldItalic.ttf", int(22 * sx))
for (t, x, y, ang) in ((LOC.NAMES["river"], 0.6, 0.665, -62), (LOC.NAMES["lake"], 0.665, 0.065, 0), (LOC.NAMES["hills"], 0.1, 0.23, 0),
                       (LOC.NAMES["woods"], 0.44, 0.105, 0), (LOC.NAMES["city"], 0.82, 0.575, 0), (LOC.NAMES["waste"], 0.33, 0.55, 0), (LOC.NAMES["marsh"], 0.6, 0.985, 0)):
    tw = int(d.textlength(t, font=tf)) + 12
    ti = Image.new("RGBA", (tw, int(34 * sx)), (0, 0, 0, 0)); td = ImageDraw.Draw(ti)
    td.text((7, 5), t, font=tf, fill=(20, 16, 10, 150)); td.text((6, 4), t, font=tf, fill=(236, 222, 184, 170))
    ti = ti.rotate(ang, expand=True, resample=Image.BICUBIC)
    im.alpha_composite(ti, (int(x * N - ti.width / 2), int(y * N - ti.height / 2)))
os.makedirs(OUT, exist_ok=True)
im.convert("RGB").save(os.path.join(OUT, "worldmap.png"), optimize=True)
data = {"region": LOC.REGION, "size": [N, N], "names": LOC.NAMES,
        "locations": [dict(l, px=[round(l["pos"][0] * N), round(l["pos"][1] * N)]) for l in LOC.L], "roads": road_out}
json.dump(data, open(os.path.join(OUT, "locations.json"), "w"), indent=1)

# labelled preview
lab = im.copy(); ld = ImageDraw.Draw(lab)
TC = {"hub": (250, 206, 60), "city": (236, 80, 56), "district": (226, 130, 76), "town": (110, 220, 100), "settlement": (150, 226, 140),
      "camp": (230, 186, 76), "landmark": (232, 214, 130), "dungeon": (226, 88, 80)}
RAD = {"hub": 14, "city": 15, "district": 9, "town": 12, "settlement": 9, "camp": 7, "landmark": 8, "dungeon": 8}
f1 = ImageFont.truetype(FONT + "DejaVuSansCondensed-Bold.ttf", int(16 * sx * 0.85))
f2 = ImageFont.truetype(FONT + "DejaVuSansCondensed-Bold.ttf", int(13 * sx * 0.85))
placed = []
for l in sorted(LOC.L, key=lambda l: -RAD[l["type"]]):
    x, y = l["pos"][0] * N, l["pos"][1] * N; r = RAD[l["type"]] * sx * 0.8; c = TC[l["type"]]
    ld.ellipse((x - r - 2, y - r - 2, x + r + 2, y + r + 2), outline=(16, 12, 8, 255), width=int(2 * sx))
    ld.ellipse((x - r, y - r, x + r, y + r), outline=c + (255,), width=int(2 * sx))
    ld.ellipse((x - 3, y - 3, x + 3, y + 3), fill=c + (255,))
    f = f1 if l["type"] in ("city", "town", "hub") else f2
    name = l["name"].replace("Port Sterling - ", ""); tw = ld.textlength(name, font=f); th = f.size + 2
    for (ox, oy) in ((r + 6, -th / 2), (-tw - r - 6, -th / 2), (-tw / 2, r + 4), (-tw / 2, -r - th - 4), (r + 6, 4), (-tw - r - 6, 4)):
        box = (x + ox, y + oy, x + ox + tw, y + oy + th)
        if box[0] > 2 and box[2] < N - 2 and all(box[2] < q[0] or box[0] > q[2] or box[3] < q[1] or box[1] > q[3] for q in placed): break
    placed.append(box)
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (2, 2)):
        ld.text((box[0] + dx, box[1] + dy), name, font=f, fill=(14, 10, 6, 255))
    ld.text((box[0], box[1]), name, font=f, fill=c + (255,))
ft = ImageFont.truetype(FONT + "DejaVuSerif-Bold.ttf", int(40 * sx * 0.8))
t = LOC.REGION.upper(); tw = ld.textlength(t, font=ft)
ld.text((N - tw - 28, 22), t, font=ft, fill=(14, 10, 6, 255))
ld.text((N - tw - 30, 20), t, font=ft, fill=(232, 214, 170, 255))
os.makedirs("/tmp/r3d", exist_ok=True)
lab.convert("RGB").save("/tmp/r3d/worldmap_labeled.png")
lab.convert("RGB").resize((1200, 1200), Image.LANCZOS).save("/tmp/r3d/worldmap_labeled_small.png")
print("done", N, flush=True)
