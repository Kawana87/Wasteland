"""Render the world map in Blender: real terrain (height mesh), buildings, landmarks and sun shadows, from straight
overhead. Uses the hand-laid layout (layout_fo3.py) and the locations (locations.py).
python3 tools/worldmap/render_map3d.py [--res 2048] [--samples 24]
  -> assets/worldmap/worldmap.png        clean map for the game (no labels)
  -> assets/worldmap/locations.json      locations, pixel positions, roads
  -> /tmp/r3d/worldmap3d_labeled.png     preview with markers and names"""
import os, sys, json, math, random, time, argparse
ap = argparse.ArgumentParser(); ap.add_argument("--res", type=int, default=2048); ap.add_argument("--samples", type=int, default=24)
ap.add_argument("--prep-only", action="store_true")
ap.add_argument("--crop", default="", help="x0,y0,x1,y1 in 0..1 (image space): render only that part, to /tmp/r3d/crop3d.png")
A = ap.parse_args()
os.environ["WM_N"] = str(A.res)
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout_fo3 as LY
import locations as LOC

T0 = time.time()
def log(*a): print("[%5.1fs]" % (time.time() - T0), *a, flush=True)

N = LY.N; X, Y = LY.X, LY.Y
W = 100.0                      # map width in Blender units
ZS = 6.0                       # height scale (Blender units per unit of H)
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "worldmap")
TMP = "/tmp/wm"; os.makedirs(TMP, exist_ok=True); os.makedirs("/tmp/r3d", exist_ok=True)
FONT = "/usr/share/fonts/truetype/dejavu/"
rr = random.Random(5)
P = LY.P


def fbm(seed, base, octaves=6, persist=0.5):
    t = np.zeros((N, N), np.float32); a = 1.0; tot = 0
    for o in range(octaves):
        sc = int(base * 2 ** o)
        if sc > N // 3:
            if o: break
            sc = N // 3
        t += a * LY.noise(seed * 31 + o, sc); tot += a; a *= persist
    return t / tot


def soft(m, px):
    return ndimage.gaussian_filter(m.astype(np.float32), px)


def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)


def line_mask(pts, w):
    im = Image.new("L", (N, N), 0)
    ImageDraw.Draw(im).line([(x * N, y * N) for x, y in pts], fill=255, width=max(1, int(round(w * N))), joint="curve")
    return np.array(im) > 0


def to_world(x, y):
    return (x - 0.5) * W, (0.5 - y) * W


# ======================================================================= masks (touched up from the layout)
log("masks")
(lx, ly), lr = LY.LAKE
old_lake = LY.blob(lx, ly, lr, 4, 0.35)
ang = np.arctan2(Y - ly, X - lx)
lake = np.hypot((X - lx) / 1.25, Y - ly) / lr + 0.28 * np.sin(ang * 3 + 1) + 0.5 * (LY.noise(40, 40) - 0.5) < 1
lake |= np.hypot((X - lx + 0.05) / 2.2, Y - ly - 0.004) / 0.012 + 0.6 * (LY.noise(41, 50) - 0.5) < 1
lake &= Y < 0.15
water = ((LY.water & ~old_lake) | lake) & ~LY.island
farms = (LY.blob(0.37, 0.31, 0.085, 42, 0.45) | LY.blob(0.47, 0.27, 0.05, 43, 0.4) | LY.blob(0.36, 0.67, 0.04, 44, 0.5)) & ~LY.deadwood & ~LY.hills & ~water
def natural(mask, seed, px=0.012, amp=0.9, base=40):
    """Break a smooth layout blob into a ragged, natural outline."""
    # warp the outline at a large scale (so it stops being round), then fray it at a fine scale
    wx_, wy_ = fbm(seed + 1, 4, 4), fbm(seed + 2, 4, 4)
    wx_ = (wx_ - wx_.mean()) / wx_.std() * 0.025 * amp; wy_ = (wy_ - wy_.mean()) / wy_.std() * 0.025 * amp
    m = ndimage.map_coordinates(soft(mask, N * px), [np.clip((Y + wy_) * N, 0, N - 1), np.clip((X + wx_) * N, 0, N - 1)], order=1)
    n = fbm(seed, base, 5); n = (n - n.mean()) / (n.std() + 1e-6) * 0.18
    near = soft(mask, N * px * 3) > 0.03                  # fraying only near the outline, never fresh patches far away
    return ((m + amp * n) > 0.5) & near
marsh = natural(LY.marsh, 80, 0.012, 1.6, 22)
RW = {"interstate": 0.0042, "highway": 0.003, "road": 0.0018, "track": 0.0011}
road_m = {k: np.zeros((N, N), bool) for k in RW}
for kind, pts in LY.ROADS:
    road_m[kind] |= line_mask(pts, RW[kind])
roads_all = road_m["interstate"] | road_m["highway"] | road_m["road"]
# The city is a density field, not a blob: a dense core stretched along the river, older districts and
# suburbs around it, and ribbons of sprawl reaching out along the highways, fading out into the waste.
ryx = np.array(LY.RIVER); ry_order = np.argsort(ryx[:, 1])
river_x = np.interp(Y, ryx[ry_order, 1], ryx[ry_order, 0])
east = sstep(-0.004, 0.012, X - river_x)                       # east bank only
dfast = ndimage.distance_transform_edt(~(road_m["interstate"] | road_m["highway"])) / N
u, v = X - 0.805, Y - 0.625
uu, vv = u * 0.97 + v * 0.24, v * 0.97 - u * 0.24              # long axis leans with the river
D = 1.15 * np.exp(-((uu / 0.065) ** 2 + (vv / 0.12) ** 2))
for (x, y, r, a) in ((0.89, 0.42, 0.06, 0.55), (0.845, 0.88, 0.055, 0.5), (0.72, 0.76, 0.035, 0.45), (0.93, 0.62, 0.04, 0.45),
                     (0.76, 0.47, 0.035, 0.4), (0.95, 0.78, 0.03, 0.35)):
    D += a * np.exp(-(np.hypot(X - x, (Y - y) * 1.2) / r) ** 2)
D += 0.4 * np.exp(-dfast / 0.007) * np.exp(-(np.hypot(X - 0.82, Y - 0.62) / 0.22) ** 2)
D *= 0.6 + 0.8 * fbm(81, 10, 5)
D *= east * (1 - soft(water, 2))
core = D > 0.85
city = D > 0.42
sub = (D > 0.17) & ~city
deadwood = natural(LY.deadwood, 84, 0.015, 1.0, 30) & ~water
_e = np.exp(-(np.hypot((X - 0.115) / 1.6, Y - 0.6) / 0.03) ** 2) + 0.6 * np.exp(-(np.hypot(X - 0.15, Y - 0.625) / 0.02) ** 2)
_f = fbm(85, 14, 5); _f = (_f - _f.mean()) / _f.std()
saltm = _e * (1 + 0.5 * _f) > 0.22
farms = natural(farms, 87, 0.01, 0.6, 30)
LY.deadwood, LY.salt = deadwood, saltm
dw = ndimage.distance_transform_edt(~water) / N            # distance to water, map units

# ======================================================================= height
log("height")
warpx, warpy = (fbm(50, 4, 4) - 0.5) * 0.06, (fbm(51, 4, 4) - 0.5) * 0.06
def warped(seed, base, octaves=6, ridged=False):
    f = fbm(seed, base, octaves)
    f = ndimage.map_coordinates(f, [np.clip((Y + warpy) * N, 0, N - 1), np.clip((X + warpx) * N, 0, N - 1)], order=1)
    return (1 - np.abs(f * 2 - 1)) ** 2 if ridged else f
base = 0.05 * warped(1, 3) + 0.012 * fbm(2, 24, 4) + 0.004 * fbm(3, 96, 3)
ridged = warped(4, 6, 7, True)
hm = soft(LY.hills, N * 0.012)
pk = soft(LY.peaks, N * 0.02)
H = base + 0.05 + hm * (0.06 + 0.32 * ridged) + pk * (0.1 + 0.3 * ridged)
# rolling badland ridges in the open waste
H += (0.035 * warped(5, 10, 6, True) + 0.05 * warped(6, 3, 4)) * (1 - hm)
# arroyos: dry washes that wander down toward the river
wash = np.zeros((N, N), bool); wash_pts = []
for k in range(16):
    x, y = rr.uniform(0.03, 0.6), rr.uniform(0.2, 0.98); pts = [(x, y)]; hd = rr.uniform(-0.6, 0.6)
    for t in range(rr.randint(25, 70)):
        hd += rr.uniform(-0.45, 0.45); hd = max(-1.2, min(1.2, hd))
        x += math.cos(hd) * 0.004; y += math.sin(hd) * 0.004 * 0.8
        if not (0 < x < 1 and 0 < y < 1) or water[int(y * N), int(x * N)]: break
        pts.append((x, y))
    if len(pts) > 6:
        wash |= line_mask(pts, 0.0012 if k % 3 else 0.002); wash_pts.append(pts)
        for b in range(2):             # tributaries
            bx, by = pts[rr.randrange(len(pts))]; hb = rr.uniform(-3, 0); tp = [(bx, by)]
            for t in range(rr.randint(6, 18)):
                hb += rr.uniform(-0.4, 0.4); bx -= math.cos(hb) * 0.004; by -= math.sin(hb) * 0.004; tp.append((bx, by))
            wash |= line_mask(tp, 0.0011)
wash &= ~(D > 0.12)
dwash = ndimage.distance_transform_edt(~wash) / N
H -= 0.014 * sstep(0.006, 0.0, dwash)
# the river valley
H -= 0.05 * np.exp(-dw / 0.06)
# canyon: a raised plateau cut by a winding gorge with stepped walls
def meander(pts, amp, seed):
    q = random.Random(seed); out = []
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        n = max(2, int(math.dist(pts[i], pts[i + 1]) / 0.004))
        for k in range(n):
            t = k / n; out.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
    out.append(pts[-1])
    ph = [q.uniform(0, 6.28) for _ in range(3)]
    res = []
    for i, (x, y) in enumerate(out):        # sideways wiggle at a few wavelengths, like an entrenched meander
        a, b = out[max(0, i - 1)], out[min(len(out) - 1, i + 1)]
        nx, ny = -(b[1] - a[1]), b[0] - a[0]; ln = math.hypot(nx, ny) + 1e-9
        w = amp * (math.sin(i * 0.22 + ph[0]) + 0.45 * math.sin(i * 0.55 + ph[1]) + 0.15 * math.sin(i * 1.3 + ph[2]))
        res.append((x + nx / ln * w, y + ny / ln * w))
    return res
CAN = meander([(0.08, 0.69), (0.12, 0.745), (0.17, 0.8), (0.2, 0.84), (0.215, 0.875), (0.25, 0.92), (0.3, 0.955), (0.36, 1.0)], 0.0035, 61)
gm = line_mask(CAN, 0.004); branches = []
q_ = random.Random(62)
for f in np.linspace(0.08, 0.92, 9):              # side canyons, each with its own little branches (dendritic)
    p0 = CAN[int(f * (len(CAN) - 1))]; side = q_.choice((-1, 1)); a0 = q_.uniform(0.9, 1.6) * side
    p1 = (p0[0] + math.cos(a0 - 0.8) * q_.uniform(0.03, 0.06), p0[1] + math.sin(a0 - 0.8) * q_.uniform(0.03, 0.06))
    br = meander([p0, p1], 0.004, int(f * 1000)); branches.append(br); gm |= line_mask(br, 0.0026)
    for g in range(2):
        pp = br[q_.randrange(len(br) // 3, len(br))]; a1 = a0 + q_.uniform(-1.2, 1.2)
        tw = meander([pp, (pp[0] + math.cos(a1) * 0.022, pp[1] + math.sin(a1) * 0.022)], 0.003, q_.randrange(9999))
        gm |= line_mask(tw, 0.0016)
dc = ndimage.distance_transform_edt(~gm) / N
can_area = sstep(0.07, 0.03, dc + 0.04 * (fbm(86, 14, 5) - 0.5))      # the plateau the gorges are cut into
canm = can_area > 0.5
gorge = sstep(0.02, 0.005, dc + 0.005 * (fbm(62, 40, 4) - 0.5))
# plateau: a flat-ish caprock with a ragged escarpment edge (not a dome)
cap = sstep(0.35, 0.7, can_area + 0.3 * (fbm(98, 30, 5) - 0.5))
H_wall_base = ndimage.gaussian_filter(H, N * 0.03)
H = H * (1 - cap) + (H_wall_base + 0.075 + 0.01 * fbm(99, 40, 3)) * cap
# gorge: walls stepped down to a smooth floor that falls steadily along the canyon
floor = ndimage.gaussian_filter(H_wall_base, N * 0.03) - 0.025
prof = gorge * np.clip(can_area * 2, 0, 1)
step = prof
H = H * (1 - step) + floor * step
rills = warped(103, 18, 5, True)                       # fine erosion rills over the caprock
H -= 0.012 * sstep(0.55, 0.95, rills) * cap
# mesas and buttes
def mesa(x, y, r, hgt, seed):
    global H
    f_ = fbm(seed, 12, 4); d = np.hypot(X - x, (Y - y) * 1.4) / r + 0.5 * (f_ - f_.mean()) / f_.std()
    H += hgt * sstep(1.0, 0.82, d)
mesa(*P["buzzard_mesa"], 0.032, 0.1, 63)

# craters
cx, cy = LY.crater_c
cang = np.arctan2(Y - cy, X - cx)
_cn = fbm(88, 8, 4); cr = np.hypot(X - cx, Y - cy) / LY.crater_r * (1 + 0.12 * (_cn - _cn.mean()) / _cn.std())
H += np.exp(-((cr - 1.0) / 0.16) ** 2) * 0.07 + np.exp(-((cr - 1.35) / 0.4) ** 2) * 0.015 - sstep(1.0, 0.1, cr) * 0.12
for (x, y, r) in LY.craters:
    d = np.hypot(X - x, Y - y) / r
    H += np.exp(-((d - 1) / 0.3) ** 2) * 0.008 - sstep(1.0, 0.0, d) * 0.012
# hydraulic erosion: thousands of simulated raindrops carve gullies and drop fans (strongest in hills and canyon)
log("erosion")
import erosion
E = min(N, 1024)
sc_ = ZS * E / W
hs0 = ndimage.zoom(H, E / N, order=1).astype(np.float64) * sc_
emask = np.clip(0.35 + 0.65 * hm + 1.0 * ndimage.zoom(can_area, 1, order=0) * 0 , 0, 1)
emask = np.clip(0.35 + 0.65 * hm + can_area + pk, 0, 1) * (1 - sstep(0.08, 0.2, D)) * (1 - soft(water, 3))
em = ndimage.zoom(emask, E / N, order=1).astype(np.float64)
hs = erosion.erode(hs0.copy(), em, int(700000 * (E / 1024) ** 2), 7)
delta = ndimage.zoom((hs - hs0) / sc_, N / E, order=1)[:N, :N].astype(np.float32)
edge_fade = sstep(0.0, 0.02, np.minimum(np.minimum(X, 1 - X), np.minimum(Y, 1 - Y)))
delta *= edge_fade
H += delta
erode_d = delta
# flats: salt pan, farms, city, marsh are flattened
def flatten(mask, level=None, px=6):
    global H
    m = soft(mask, px)
    tgt = ndimage.gaussian_filter(H, N * 0.02) if level is None else level
    H = H * (1 - m) + tgt * m
flatten(LY.salt)
m_ = sstep(0.1, 0.45, D); H = H * (1 - m_) + ndimage.gaussian_filter(H, N * 0.02) * m_
flatten(farms, px=8)
flatten(marsh, level=0.012, px=10)
# banks down to the water, and water channels carved below the water plane
WL = 0.0
bank = sstep(0.0, 0.012, dw)
H = WL + 0.004 + (H - WL - 0.004) * bank
H = np.maximum(H, WL + 0.004)        # dry land always stays above the water plane
H[water] = WL - 0.02
pf = fbm(64, 180, 2)
pools = marsh & (pf > np.quantile(pf[marsh], 0.82)) & (soft(marsh, 6) > 0.7)
H[pools] = WL - 0.01
water_all = water | pools

# roads: flatten their beds
log("roads")
Hs = ndimage.gaussian_filter(H, N * 0.003)
rm = soft(roads_all & ~water, 2)
H = H * (1 - rm) + Hs * rm
H = np.maximum(H, np.where(water_all, -1, WL + 0.002)) if False else H

# ======================================================================= albedo
log("albedo")
def col(h):
    h = h.lstrip("#"); return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255
gy, gx = np.gradient(H * ZS * N / W)
slope = np.hypot(gx, gy)
m1, m2, m3 = fbm(70, 5), fbm(71, 20, 4), fbm(72, 80, 3)
alb = col("#9a8a70") * (1 - m1[..., None]) + col("#857a64") * m1[..., None]                    # dusty soil
alb = alb * (1 - sstep(0.55, 0.75, m2)[..., None] * 0.5) + col("#b29a72") * sstep(0.55, 0.75, m2)[..., None] * 0.5   # pale sand drifts
alb = alb * (1 - sstep(0.6, 0.8, fbm(73, 12, 4))[..., None] * 0.45) + col("#8e6a50") * sstep(0.6, 0.8, fbm(73, 12, 4))[..., None] * 0.45  # rusty patches
alb *= (0.9 + 0.2 * m3[..., None])
def lay(mask, c, a=1.0):
    global alb
    m = (np.clip(mask, 0, 1) * a)[..., None]; alb = alb * (1 - m) + c * m
sage = sstep(0.58, 0.75, fbm(79, 30, 4)) * (1 - hm)
lay(sage, col("#7e8062") * (0.85 + 0.3 * m3[..., None]), 0.55)
lay(sstep(0.003, 0.0, dwash), col("#a89878") * (0.9 + 0.2 * m3[..., None]), 0.25)
lay(sstep(-0.002, -0.012, erode_d), col("#6a5a48"), 0.45)      # gullies
lay(sstep(0.002, 0.01, erode_d), col("#b8a684"), 0.4)          # alluvial fans
rock = sstep(0.35, 0.9, slope)
lay(rock, col("#6e5e4c") * (0.85 + 0.3 * m2[..., None]), 0.85)
lay(hm * sstep(0.5, 0.8, ridged), col("#9a8c78"), 0.4)                                   # pale ridge crests
lay(pk * sstep(0.6, 0.9, ridged), col("#b0a492"), 0.5)
# canyon: red sandstone bands
bands = (np.sin(H * 260 + fbm(74, 8, 3) * 4) * 0.5 + 0.5)[..., None]
wall = sstep(0.25, 0.7, slope)[..., None]           # strata only show on the steep walls
bands = bands * wall + 0.6 * (1 - wall)
_cf = fbm(101, 16, 5); _cf = (_cf - _cf.mean()) / _cf.std()
can_col = (col("#a8805e") * bands + col("#80584a") * (1 - bands)) * (0.88 + 0.12 * _cf[..., None]) * (0.9 + 0.2 * m3[..., None])
can_col = can_col * (1 - sstep(0.6, 0.8, m2)[..., None] * 0.4) + col("#b8a080") * sstep(0.6, 0.8, m2)[..., None] * 0.4   # sand drifts on the caprock
can_a = np.clip(sstep(0.25, 0.7, can_area + 0.25 * (fbm(95, 20, 5) - 0.5)) * (0.45 + 0.25 * _cf), 0, 0.7) + 0.15 * wall[..., 0] * (can_area > 0.2)
lay(np.clip(can_a, 0, 1), can_col)
lay(gorge * can_area * 2, col("#6e5240"), 0.4)
lay(sstep(0.6, 0.95, rills) * cap, col("#6a4c3a"), 0.45)
lay(sstep(0.0015, 0.0, dc) * np.clip(can_area * 2, 0, 1), col("#9e8a6a"), 0.35)      # dry streambed on the floor
lay(sstep(0.024, 0.016, dc) * (1 - gorge) * can_area, col("#c4ae8e"), 0.35)     # pale rims
# mesa tops and sides red too
mesa_m = np.zeros((N, N), np.float32)
lay(soft(natural(np.hypot(X - P["buzzard_mesa"][0], Y - P["buzzard_mesa"][1]) < 0.028, 92, 0.004, 0.6, 60), 3), col("#8e6650") * (0.9 + 0.2 * bands), 0.7)
# dead woods: grey-brown ground with olive litter
dws = soft(LY.deadwood & ~water, 8)
lay(dws, col("#6c6450") * (1 - m2[..., None] * 0.4) + col("#5a5e40") * m2[..., None] * 0.4, 0.9)
# farms: plots in muted drought colours, a few still green
fx, fy = X * 0.96 + Y * 0.28, Y * 0.96 - X * 0.28
cell = np.floor(fx * 130) * 7919 + np.floor(fy * 100) * 104729
k = (np.sin(cell) * 43758.5453) % 1
plots = [col(c) for c in ("#a29470", "#8a845e", "#977c60", "#78805a", "#ae9e7a", "#7c6e54")]
fcol = np.zeros_like(alb)
for i, c in enumerate(plots):
    fcol[(k >= i / 6) & (k < (i + 1) / 6)] = c
rows = (np.sin(fx * N * 1.6) * 0.5 + 0.5)[..., None]
fcol *= 0.9 + 0.1 * rows
fcol = fcol * 0.45 + alb * 0.55                               # dusty: plots sit in the same soil
edge = ((fx * 130) % 1 < 0.06) | ((fy * 100) % 1 < 0.06)
fcol[edge] *= 0.8
_, inv = np.unique(cell, return_inverse=True); inv = inv.reshape(cell.shape)
frac = ndimage.mean(farms.astype(np.float32), labels=inv, index=np.arange(inv.max() + 1))
keep = (frac[inv] + 0.25 * (k - 0.5)) > 0.5
lay(soft(keep, 1), fcol)
piv = np.zeros((N, N), np.float32); pc = np.zeros_like(alb)
for q in range(60):
    x, y = rr.uniform(0.25, 0.55), rr.uniform(0.18, 0.72)
    if not farms[int(y * N), int(x * N)] or rr.random() < 0.3: continue
    r_ = rr.uniform(0.006, 0.011); dd = np.hypot(X - x, Y - y) / r_
    m = sstep(1.0, 0.96, dd)
    if rr.random() < 0.6: m *= (np.arctan2(Y - y, X - x) % 6.283 > rr.uniform(0, 2.5))      # part-planted pivots
    c = col(rr.choice(("#6e7c4e", "#7e8a56", "#9a8c62", "#8a7a5a")))
    piv = np.maximum(piv, m); pc[m > 0.5] = c * (0.95 + 0.05 * np.sin(dd[m > 0.5] * 60))[..., None]
lay(piv, pc)
# marsh
ms = soft(marsh, 6)
lay(ms * 0.9, col("#56663a") * (1 - m2[..., None]) + col("#6e7c44") * m2[..., None] * 1.0)
reed = sstep(0.5, 0.65, fbm(75, 160, 2))
lay(ms * reed, col("#4a5632"), 0.6)
# salt pan with crack polygons
ss = soft(LY.salt, 2.5)
lay(soft(LY.salt, 14) * 0.7, col("#b8aa8e"))          # mud fringe around the playa
cells = np.floor(X * 400 + 0.5 * LY.noise(76, 80)) * 31 + np.floor(Y * 400 + 0.5 * LY.noise(77, 80)) * 57
crack = ndimage.morphological_gradient(cells, size=2) > 0
saltc = col("#dcd4c2") * (0.9 + 0.1 * m3[..., None]) * (0.94 + 0.06 * fbm(100, 20, 3)[..., None])
saltc[crack] *= 0.86
lay(np.clip(ss * 1.4 - 0.2, 0, 1) * 0.9, saltc)
# crater: scorched black glass, faint green
rays = ndimage.gaussian_filter((np.sin(cang * 17 + 4 * LY.noise(89, 10)) * 0.5 + 0.5) ** 2, N * 0.002)
lay(sstep(2.6, 1.0, cr) * rays, col("#5a4e3e"), 0.45)
lay(sstep(1.6, 0.9, cr), col("#6a5e4c"), 0.4)
lay(np.exp(-((cr - 1.0) / 0.12) ** 2), col("#b0a088"), 0.6)
lay(sstep(0.95, 0.7, cr), col("#6e665a") * (0.8 + 0.4 * m3[..., None]))
lay(sstep(0.45, 0.15, cr), col("#34382c"), 0.7)
lay(sstep(0.7, 0.2, cr) * sstep(0.45, 0.6, fbm(93, 60, 3)), col("#3e4a30"), 0.6)
# city ground and suburbs
lay(sstep(0.15, 0.4, D) * (0.5 + 0.3 * m2), col("#948a78") * (0.85 + 0.3 * m2[..., None]))         # outskirts: packed dirt, lots
lay(sstep(0.35, 0.6, D), col("#5e5c58") * (0.9 + 0.2 * m3[..., None]))                              # paved city
lay(sstep(0.4, 0.6, D) * (fbm(91, 30, 3) > 0.68), col("#6a6a50"), 0.7)                              # dead parks
SA = (fbm(96, 3, 2) - 0.5) * 2.5                         # street-grid angle drifts from district to district
vS = (-X * np.sin(SA) + Y * np.cos(SA)) * W; uS = (X * np.cos(SA) + Y * np.sin(SA)) * W
streets = ((np.abs((vS / 0.42) % 1 - 0.5) > 0.42) | (np.abs((uS / 1.6) % 1 - 0.5) > 0.47)) & (D > 0.1)
lay(streets * sstep(0.1, 0.25, D), col("#55524c"), 0.8)
ind = sstep(0.62, 0.72, fbm(94, 8, 3)) * sstep(0.25, 0.45, D) * (1 - sstep(0.8, 1.0, D))           # industrial: pale concrete yards
lay(ind, col("#8a8478"), 0.6)
# water bed (seen through shallow water) and wet banks
lay(soft(water_all, 2), col("#2c3a36"))
lay(np.exp(-dw / 0.004) * (1 - water_all), col("#5c5442"), 0.5)
# roads
asph = {"interstate": col("#3e3c3a"), "highway": col("#4a4642"), "road": col("#625848"), "track": col("#7a6a52")}
for kind in ("track", "road", "highway", "interstate"):
    m = road_m[kind] & ~water
    a = 0.75 if kind == "track" else 1.0
    lay(m.astype(np.float32) * (0.85 + 0.15 * m3), asph[kind] * (0.9 + 0.2 * m3[..., None]), a)
cracks = (roads_all & (fbm(78, 200, 2) > 0.66))
lay(cracks, col("#6a6052"), 0.6)
# metro line (rails)
rail = line_mask(LY.METRO, 0.0012) & ~water
lay(rail, col("#3a3430"))
glow = ndimage.gaussian_filter(sstep(0.3, 0.0, np.hypot(X - cx, Y - cy) / LY.crater_r), N * 0.003) * 0.04
alb = np.clip(alb, 0, 1)

# ======================================================================= geometry: buildings, trees, landmarks
log("geometry")
GV, GF, GC = [], [], []          # vertex arrays, face arrays (quads as 4-tuples), per-vertex colours
nv = [0]

def Hat(x, y):
    i = min(max(int(y * N), 0), N - 1); j = min(max(int(x * N), 0), N - 1)
    return max(H[i, j], WL) * ZS

def add(v, f, c):
    GV.append(v); GF.append(np.asarray(f) + nv[0]); GC.append(np.tile(np.asarray(c, np.float32) ** 2.2, (len(v), 1))); nv[0] += len(v)   # colours: sRGB-ish -> linear

def box(x, y, w, d, h, c, rot=0.0, z0=None, wx=None):
    """x, y in map units (0..1); w, d, h in Blender units; rot radians."""
    X0, Y0 = to_world(x, y) if wx is None else wx
    z = Hat(x, y) - 0.02 if z0 is None else z0
    cs, sn = math.cos(rot), math.sin(rot)
    pts = []
    for (u, v) in ((-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)):
        pts.append((X0 + u * cs - v * sn, Y0 + u * sn + v * cs))
    vv = np.array([(px, py, z) for px, py in pts] + [(px, py, z + h) for px, py in pts], np.float32)
    add(vv, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], c)

def cyl(x, y, r, h, c, seg=20, open_top=False, r_top=None, z0=None):
    X0, Y0 = to_world(x, y); z = Hat(x, y) - 0.02 if z0 is None else z0
    rt = r if r_top is None else r_top
    a = np.linspace(0, 2 * np.pi, seg, endpoint=False)
    bot = np.stack([X0 + r * np.cos(a), Y0 + r * np.sin(a), np.full(seg, z)], 1)
    top = np.stack([X0 + rt * np.cos(a), Y0 + rt * np.sin(a), np.full(seg, z + h)], 1)
    vv = np.concatenate([bot, top]).astype(np.float32)
    f = [(i, (i + 1) % seg, seg + (i + 1) % seg, seg + i) for i in range(seg)]
    add(vv, f, c)
    if open_top:     # inner wall so the inside of the tower shades dark
        inner = np.concatenate([bot * [1, 1, 1], top]).astype(np.float32)
        inner[:, 0] = X0 + (inner[:, 0] - X0) * 0.9; inner[:, 1] = Y0 + (inner[:, 1] - Y0) * 0.9
        add(inner, [(seg + i, seg + (i + 1) % seg, (i + 1) % seg, i) for i in range(seg)], np.array(c) * 0.5)
        add(np.concatenate([top, inner[seg:]]), [(i, (i + 1) % seg, seg + (i + 1) % seg, seg + i) for i in range(seg)], c)
    else:
        add(top.astype(np.float32), [tuple(range(seg))], c)

ROOFS = [(0.26, 0.25, 0.24), (0.36, 0.34, 0.31), (0.44, 0.41, 0.37), (0.4, 0.3, 0.24), (0.3, 0.27, 0.23), (0.5, 0.47, 0.42), (0.34, 0.36, 0.34)]
def grey(lo, hi):
    c = rr.choice(ROOFS); k_ = rr.uniform(0.85, 1.15) * (lo + hi) / 0.76; return tuple(min(1, v * k_) for v in c)

U = 1 / W                                   # one Blender unit in map units
# --- city: skewed street grid, towers in the core
log("city")
rot = math.radians(8); cs, sn = math.cos(rot), math.sin(rot)
blk = 0.85                                   # block pitch (Blender units)
for gi in range(-40, 41):
    for gj in range(-40, 41):
        bxw, byw = 32 + (gi * cs - gj * sn) * blk, -12 + (gi * sn + gj * cs) * blk      # around the city centre
        x, y = bxw / W + 0.5, 0.5 - byw / W
        if not (0 < x < 1 and 0 < y < 1): continue
        i, j = int(y * N), int(x * N)
        dv = D[i, j]
        if dv < 0.3 or roads_all[i, j] or rr.random() > sstep(0.3, 0.55, dv): continue
        incore = core[i, j]
        dist = math.hypot(x - 0.8, y - 0.62)
        for q in range(rr.choice((1, 2, 2, 4))):
            ox, oy = rr.uniform(-0.2, 0.2), rr.uniform(-0.2, 0.2)
            w, d = rr.uniform(0.22, 0.6), rr.uniform(0.22, 0.6)
            if incore:
                h = rr.uniform(0.3, 1.0) * (2.4 if rr.random() < 0.25 else 1.0) * max(0.4, 1 - dist / 0.09)
            else:
                h = rr.uniform(0.08, 0.3) * (0.6 + dv)
            if rr.random() < 0.18: h *= rr.uniform(0.15, 0.4)       # bombed down
            if rr.random() < 0.14: continue                          # gone: rubble lot
            box(x + (ox * cs - oy * sn) * U, y - (ox * sn + oy * cs) * U, w, d, h + 0.05, grey(0.3, 0.46), rot)
# suburbs: little houses along curving lanes
log("suburbs")
seen = set()
for _ in range(30000):
    x, y = rr.uniform(0.62, 1), rr.uniform(0.25, 1)
    i, j = int(y * N), int(x * N)
    a_ = SA[i, j]; u_ = (x * math.cos(a_) + y * math.sin(a_)) * W; v_ = (-x * math.sin(a_) + y * math.cos(a_)) * W
    v_ = round(v_ / 0.42) * 0.42 + rr.choice((-0.11, 0.11)); u_ = round(u_ / 0.2) * 0.2
    if abs((u_ / 1.6) % 1 - 0.5) > 0.42 or (round(u_, 2), round(v_, 2)) in seen: continue
    seen.add((round(u_, 2), round(v_, 2)))
    x, y = (u_ * math.cos(a_) - v_ * math.sin(a_)) / W, (u_ * math.sin(a_) + v_ * math.cos(a_)) / W
    if not (0 < x < 1 and 0 < y < 1): continue
    i, j = int(y * N), int(x * N)
    if not roads_all[i, j] and not water[i, j] and rr.random() < sstep(0.08, 0.3, D[i, j]) * (1 - sstep(0.45, 0.6, D[i, j])):
        box(x, y, 0.14, 0.11, 0.07, grey(0.3, 0.46), -a_)
# dead trees: thin snags whose shadows streak the ground
log("trees")
for _ in range(16000):
    x, y = rr.random(), rr.random()
    i, j = int(y * N), int(x * N)
    if LY.deadwood[i, j] and not water[i, j] and not roads_all[i, j]:
        box(x, y, 0.035, 0.035, rr.uniform(0.15, 0.32), (0.22, 0.19, 0.15), rr.uniform(0, 3))
        if rr.random() < 0.3:
            box(x, y, 0.12, 0.12, 0.05, (0.3, 0.3, 0.2), z0=Hat(x, y) + rr.uniform(0.08, 0.16))
for _ in range(2500):                         # scattered scrub and snags elsewhere
    x, y = rr.random(), rr.random(); i, j = int(y * N), int(x * N)
    if not (water[i, j] or city[i, j] or sub[i, j] or LY.salt[i, j] or roads_all[i, j]) and cr[i, j] > 1.4:
        box(x, y, 0.05, 0.05, rr.uniform(0.04, 0.1), (0.3, 0.27, 0.2))

# --- towns: a cluster of buildings around each settlement, kept off water and roads
log("towns")
COUNT = dict(hub=70, city=0, district=0, town=45, settlement=14, camp=9, landmark=4, dungeon=4)
SPREAD = dict(hub=0.016, town=0.012, settlement=0.006, camp=0.005, landmark=0.004, dungeon=0.004)
SPECIAL = {"atomic_plaza", "iron_gate_pen", "victory_stadium", "ridgeback_dam", "bright_hope_plant", "blackrock_refinery",
           "sterling_airfield", "union_railyard", "starwatch", "moonbeam_drivein", "redwall", "greenmarsh", "clearwater",
           "bonewhite_flats", "rimtown", "fort_steadfast", "launch_site_zulu", "hollow_sun", "buzzard_mesa"}
clear = np.zeros((N, N), np.float32)
for l in LOC.L:
    if l["id"] in SPECIAL or l["type"] in ("city", "district"): continue
    x0, y0 = l["pos"]; sp = SPREAD[l["type"]]
    yy, xx = int(y0 * N), int(x0 * N); rad = int(sp * N * 1.4)
    clear[max(0, yy - rad):yy + rad, max(0, xx - rad):xx + rad] = 1
    for q in range(COUNT[l["type"]]):
        x, y = x0 + rr.gauss(0, sp), y0 + rr.gauss(0, sp)
        i, j = int(y * N), int(x * N)
        if not (0 <= i < N and 0 <= j < N) or water[i, j] or roads_all[i, j]: continue
        sh = rr.random()
        c = (rr.uniform(0.36, 0.48), rr.uniform(0.3, 0.4), rr.uniform(0.24, 0.32)) if sh < 0.5 else grey(0.3, 0.46)
        box(x, y, rr.uniform(0.12, 0.32), rr.uniform(0.1, 0.24), rr.uniform(0.06, 0.16), c, rr.choice((0, 0.1, 1.57, rr.uniform(0, 3))))

# --- landmarks
log("landmarks")
def wpos(id_): return P[id_]
def ring_boxes(x, y, rx, ry, n, w, h, c, miss=0.0):
    for k in range(n):
        if rr.random() < miss: continue
        a = 2 * math.pi * k / n
        box(x + rx * math.cos(a) * U, y + ry * math.sin(a) * U, w, 0.25, h, c, -a + math.pi / 2)
x, y = wpos("victory_stadium")
ring_boxes(x, y, 0.9, 0.65, 44, 0.16, 0.35, (0.62, 0.6, 0.56), 0.12)
ring_boxes(x, y, 0.72, 0.5, 36, 0.14, 0.2, (0.55, 0.52, 0.48), 0.1)
for _ in range(30):
    box(x + rr.uniform(-0.4, 0.4) * U, y + rr.uniform(-0.25, 0.25) * U, 0.08, 0.08, 0.05, (0.6, 0.5, 0.35))
x, y = wpos("atomic_plaza")
box(x, y, 2.2, 1.3, 0.22, (0.66, 0.62, 0.56))
box(x - 0.9 * U, y, 0.7, 1.0, 0.32, (0.58, 0.54, 0.5))
box(x + 0.9 * U, y + 0.3 * U, 0.6, 0.7, 0.28, (0.6, 0.56, 0.52))
for k in range(70):                                 # stacked-car wall around the lot
    a = 2 * math.pi * k / 70
    box(x + 1.8 * math.cos(a) * U, y + 1.3 * math.sin(a) * U, 0.14, 0.08, 0.06, (rr.uniform(.3, .6), rr.uniform(.2, .4), .2), -a)
yy, xx, rad = int(y * N), int(x * N), int(1.7 * U * N)
clear[yy - rad:yy + rad, xx - rad:xx + rad] = 2
x, y = wpos("iron_gate_pen")
for (dx, dy, w, d) in ((0, -1.0, 2.0, 0.08), (0, 1.0, 2.0, 0.08), (-1.0, 0, 0.08, 2.0), (1.0, 0, 0.08, 2.0)):
    box(x + dx * U, y + dy * U, w, d, 0.16, (0.6, 0.58, 0.54))
for (dx, dy) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
    box(x + dx * U, y + dy * U, 0.16, 0.16, 0.34, (0.5, 0.48, 0.45))
for k in range(3):
    box(x + (-0.5 + k * 0.5) * U, y - 0.35 * U, 0.26, 0.9, 0.2, (0.62, 0.6, 0.55))
box(x, y + 0.5 * U, 0.8, 0.3, 0.14, (0.55, 0.52, 0.48))
x, y = wpos("ridgeback_dam")
X0, Y0 = to_world(0.665, 0.152)
box(0.665, 0.152, 5.2, 0.45, 0.5, (0.72, 0.7, 0.66), z0=WL * ZS - 0.1)
box(0.665, 0.152, 1.0, 0.7, 0.28, (0.6, 0.58, 0.55), z0=WL * ZS + 0.3)
for (dx, dy) in ((-0.4, 0.6), (0.4, 0.6), (0, 1.0)):
    box(x + dx * U, y + dy * U, 0.3, 0.2, 0.1, (0.55, 0.5, 0.4))
for (dx, dy) in ((0, 0), (0.75, 0.15)):
    xx_, yy_ = wpos("bright_hope_plant")
    cyl(xx_ + dx * U, yy_ + dy * U, 0.38, 0.85, (0.72, 0.7, 0.66), 28, True, 0.28)
xx_, yy_ = wpos("bright_hope_plant")
box(xx_ - 0.4 * U, yy_ + 0.55 * U, 0.6, 0.4, 0.3, (0.58, 0.56, 0.52)); cyl(xx_ + 0.2 * U, yy_ + 0.6 * U, 0.22, 0.35, (0.6, 0.58, 0.55))
x, y = wpos("blackrock_refinery")
for k in range(9):
    cyl(x + rr.uniform(-0.6, 0.6) * U, y + rr.uniform(-0.4, 0.4) * U, rr.uniform(0.1, 0.22), 0.12, (0.5, 0.46, 0.4))
for k in range(3):
    cyl(x + (0.7 + 0.12 * k) * U, y - 0.3 * U, 0.04, 0.6, (0.3, 0.26, 0.22), 8)
x, y = wpos("sterling_airfield")
for k in range(3):
    box(x - 0.8 * U + k * 0.5 * U, y - 0.9 * U, 0.4, 0.3, 0.14, (0.55, 0.55, 0.5))
for k in range(4):                               # wrecked bombers (cross shapes)
    px_, py_ = x + rr.uniform(-0.6, 0.6) * U, y + rr.uniform(-0.3, 0.5) * U; a = rr.uniform(0, 3)
    box(px_, py_, 0.5, 0.07, 0.05, (0.66, 0.66, 0.64), a); box(px_, py_, 0.08, 0.6, 0.04, (0.66, 0.66, 0.64), a)
x, y = wpos("union_railyard")
for r_ in range(6):
    for k in range(10):
        if rr.random() < 0.7:
            box(x + (-1.0 + k * 0.22) * U, y + (-0.5 + r_ * 0.2) * U, 0.19, 0.08, 0.08, (rr.uniform(.35, .55), rr.uniform(.25, .4), .2))
x, y = wpos("starwatch")
cyl(x, y, 0.2, 0.12, (0.7, 0.7, 0.68), 24); cyl(x, y, 0.2, 0.12, (0.78, 0.78, 0.76), 24, r_top=0.03, z0=Hat(x, y) + 0.1)
x, y = wpos("moonbeam_drivein")
box(x, y - 0.5 * U, 0.9, 0.05, 0.35, (0.75, 0.74, 0.7))
for k in range(25):
    box(x + rr.uniform(-0.5, 0.5) * U, y + rr.uniform(-0.2, 0.5) * U, 0.1, 0.05, 0.04, (rr.uniform(.3, .6), rr.uniform(.2, .4), .2), rr.uniform(-.3, .3))
x, y = wpos("goldenrod")
for k in range(5):
    cyl(x + (0.35 + 0.1 * k) * U, y - 0.4 * U, 0.06, 0.45, (0.72, 0.7, 0.64), 14)
# Clearwater: marina piers, cisterns and filter towers on the lake shore
x, y = wpos("clearwater")
for k in range(6):
    box(x - (0.9 + 0.05 * k) * U, y + (-0.6 + k * 0.22) * U, 0.9, 0.05, 0.04, (0.5, 0.4, 0.3), z0=WL * ZS + 0.02)
for k in range(12):
    cyl(x + rr.uniform(-0.3, 0.7) * U, y + rr.uniform(-0.7, 0.6) * U, rr.uniform(0.07, 0.13), rr.uniform(0.1, 0.3), (0.62, 0.66, 0.68), 14)
for k in range(40):
    box(x + rr.uniform(-0.2, 0.9) * U, y + rr.uniform(-0.9, 0.9) * U, 0.18, 0.12, 0.08, (rr.uniform(.5, .62), .48, .4), rr.uniform(0, 3))
for k in range(30):                                   # rows of solar stills (dark glass)
    box(x + (0.3 + (k % 6) * 0.12) * U, y + (0.75 + (k // 6) * 0.08) * U, 0.1, 0.05, 0.02, (0.15, 0.18, 0.22))
# Greenmarsh: stilt houses over the marsh, boardwalks
x, y = wpos("greenmarsh")
for k in range(70):
    px_, py_ = x + rr.gauss(0, 0.012), y + rr.gauss(0, 0.008)
    box(px_, py_, 0.14, 0.12, 0.06, (0.55, 0.45, 0.32), rr.uniform(0, 3), z0=WL * ZS + 0.06)
    box(px_, py_, 0.03, 0.03, 0.08, (0.3, 0.25, 0.2), z0=WL * ZS - 0.02)
for k in range(8):
    a = rr.uniform(0, 6.28); box(x + 0.6 * math.cos(a) * U, y + 0.6 * math.sin(a) * U, 1.2, 0.04, 0.02, (0.5, 0.4, 0.3), a, z0=WL * ZS + 0.05)
# Redwall: houses lining both canyon walls, rope bridges across the gorge
for t in range(len(CAN) // 6, len(CAN) * 5 // 6, 2):
    (ax_, ay_), (bx_, by_) = CAN[t], CAN[t + 1]
    nx, ny = -(by_ - ay_), (bx_ - ax_); ln = math.hypot(nx, ny) + 1e-9; nx, ny = nx / ln, ny / ln
    for side in (-1, 1):
        if rr.random() < 0.8:
            off = rr.uniform(0.012, 0.018) * side
            box(ax_ + nx * off, ay_ + ny * off, 0.14, 0.12, 0.08, (0.6, 0.42, 0.3), math.atan2(-ny, nx))
    if t % 10 == 0:
        box(ax_, ay_, 0.04, 2.6, 0.02, (0.4, 0.3, 0.22), math.atan2(-(by_ - ay_), bx_ - ax_), z0=Hat(ax_ + nx * 0.015, ay_ + ny * 0.015) - 0.03)
# Rimtown: shacks around the crater rim
cx_, cy_ = LY.crater_c
for k in range(60):
    a = rr.uniform(-0.4, 1.9); rad_ = LY.crater_r * rr.uniform(1.05, 1.3)
    box(cx_ + rad_ * math.cos(a), cy_ - rad_ * math.sin(a), 0.14, 0.11, 0.07, (0.45, 0.42, 0.36), rr.uniform(0, 3))
# Bonewhite Flats: hangars along the salt
x, y = wpos("bonewhite_flats")
for k in range(5):
    cyl(x + (0.3 + k * 0.28) * U, y - 0.4 * U, 0.12, 0.6, (0.7, 0.68, 0.64), 12) if False else box(x + (0.3 + k * 0.3) * U, y - 0.4 * U, 0.24, 0.5, 0.12, (0.7, 0.68, 0.64))
for k in range(20):
    box(x + rr.uniform(-0.3, 1.5) * U, y + rr.uniform(-0.8, 0.3) * U, 0.14, 0.1, 0.06, (0.62, 0.56, 0.46), rr.uniform(0, 3))
# Fort Steadfast: walls, barracks rows
x, y = wpos("fort_steadfast")
for (dx, dy, w, d) in ((0, -1.1, 2.6, 0.06), (0, 1.1, 2.6, 0.06), (-1.3, 0, 0.06, 2.2), (1.3, 0, 0.06, 2.2)):
    box(x + dx * U, y + dy * U, w, d, 0.1, (0.55, 0.52, 0.45))
for r_ in range(4):
    for k in range(5):
        box(x + (-0.9 + k * 0.4) * U, y + (-0.7 + r_ * 0.4) * U, 0.3, 0.12, 0.08, (0.48, 0.5, 0.4))
x, y = wpos("launch_site_zulu")
for (dx, dy) in ((-0.3, 0), (0.3, 0.1), (0, -0.3)):
    cyl(x + dx * U, y + dy * U, 0.1, 0.03, (0.4, 0.4, 0.38), 16)
box(x + 0.5 * U, y + 0.4 * U, 0.3, 0.2, 0.08, (0.5, 0.5, 0.46))
x, y = wpos("buzzard_mesa")
for k in range(25):
    box(x + rr.gauss(0, 0.006), y + rr.gauss(0, 0.006), 0.14, 0.1, 0.06, (0.4, 0.32, 0.26), rr.uniform(0, 3))
# bridges: decks over the water wherever a road crosses it (Founders Bridge keeps its fallen span)
log("bridges")
fb = P["founders_bridge"]
for kind, pts in LY.ROADS:
    if kind == "track": continue
    run = []
    for (x, y) in pts + [(9, 9)]:
        i, j = int(y * N), int(x * N)
        wet = 0 <= i < N and 0 <= j < N and water[i, j]
        if wet:
            run.append((x, y))
        elif run:
            a, b = run[0], run[-1]
            ext = 0.006
            dx, dy = b[0] - a[0], b[1] - a[1]; ln = math.hypot(dx, dy) + 1e-9
            a = (a[0] - dx / ln * ext, a[1] - dy / ln * ext); b = (b[0] + dx / ln * ext, b[1] + dy / ln * ext)
            mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            L = math.hypot(b[0] - a[0], b[1] - a[1]) * W
            ww = RW[kind] * W * 1.4
            angw = math.atan2(-(b[1] - a[1]), b[0] - a[0])
            zt = WL * ZS + 0.12
            if math.hypot(mx - fb[0], my - fb[1]) < 0.04:
                for s in (-1, 1):             # two stubs with a gap in the middle
                    box(mx + s * (b[0] - a[0]) * 0.32, my + s * (b[1] - a[1]) * 0.32, L * 0.36, ww, 0.06, (0.55, 0.53, 0.5), angw, z0=zt)
            else:
                box(mx, my, L, ww, 0.06, (0.5, 0.48, 0.45), angw, z0=zt)
            run = []

# cleared dirt around towns and the mall's parking lot
lay(soft(clear == 1, 6) * 0.6, col("#8a7860"))
lot = soft(clear == 2, 2)
lay(lot, col("#4a4844"))
# ======================================================================= write textures
log("write textures")
Image.fromarray((alb * 255).astype(np.uint8)).save(TMP + "/albedo.png")
hb = ndimage.gaussian_filter(H, 0.6)
Image.fromarray(np.clip(glow * 255, 0, 255).astype(np.uint8)).save(TMP + "/glow.png")
Image.fromarray(np.clip(water_all * 255, 0, 255).astype(np.uint8)).save(TMP + "/water.png")
np.save(TMP + "/height.npy", H.astype(np.float32))
json.dump([dict(kind=k, path=[[round(x, 4), round(y, 4)] for x, y in pts[::3] + [pts[-1]]]) for k, pts in LY.ROADS], open(TMP + "/roads.json", "w"))
geo_v = np.concatenate(GV); geo_c = np.concatenate(GC)
log("buildings: %d verts, colour range %.3f..%.3f nan %d, z %.2f..%.2f" % (len(geo_v), geo_c.min(), geo_c.max(), np.isnan(geo_c).sum(), geo_v[:,2].min(), geo_v[:,2].max()))
faces_flat = np.concatenate([np.asarray(a).ravel() for a in GF]); faces_len = np.concatenate([np.full(len(a), np.asarray(a).shape[1]) for a in GF])
np.savez(TMP + "/geo.npz", v=geo_v, c=geo_c, f=faces_flat, n=faces_len)
if A.prep_only:
    sys.exit(0)
del GV, GF, GC, alb, geo_v, geo_c
args = [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "render_map3d_blender.py"), "--res", str(N), "--samples", str(A.samples)]
if A.crop: args += ["--crop", A.crop]
log("handing over to Blender")
sys.stdout.flush(); os.execv(sys.executable, args)          # replace this process, so its memory is freed


