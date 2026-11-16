"""Concept renders of the Sable Wastes settlements, one scene per location, built from the render kit.
Each recipe follows the location's spot on the world map (lake shore, canyon, marsh, salt flat, river,
plains...) and its role in docs/world-locations.md, so the renders double as layout plans for the maps.
Also defines the three water purifier tiers (purifier_t1/t2/t3) that the water towns use.
python3 village_scene.py OUT [ids...|all|purifiers]"""
import sys, os, math, random
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r3d/villages"
WHICH = sys.argv[2:] or ["all"]
sys.argv = [sys.argv[0], OUT, "none"]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from lib import *
import kit, props as P, landmarks as LM, scenes as S
from kit import house
import bpy
from PIL import Image, ImageDraw, ImageFont
from post import fallout_grade

os.makedirs(OUT, exist_ok=True)
SCALE_PX = 30.0                       # render scale (px per world unit along the screen); the game uses ~34
MAT = P.MAT
W_, H_ = 34, 26                       # scene size in tiles


# ------------------------------------------------------------------ water purifiers (three tiers)
@P.prop
def purifier_t1(x, y, rng):
    """Tier 1 — solar still: a sloped glass lid over a black tray, a collection gutter, a rain barrel, a jug."""
    wood, glass = MAT("wood:#6a4a30:#4a3220"), MAT("flat:#9ab8c0:0.08")
    B = P.B
    B(x - 0.55, y - 0.35, 0, x + 0.55, y + 0.35, 0.25, wood)
    B(x - 0.5, y - 0.3, 0.25, x + 0.5, y + 0.3, 0.27, MAT("flat:#141414:0.6"))
    for k in range(5):                                         # stepped glass lid (reads as a slope)
        z = 0.3 + k * 0.05
        B(x - 0.5, y - 0.3 + k * 0.12, z, x + 0.5, y - 0.18 + k * 0.12, z + 0.02, glass)
    B(x - 0.56, y + 0.3, 0.2, x + 0.56, y + 0.38, 0.26, MAT("metal:#8a8a80"))      # gutter
    cyl(x + 0.75, y + 0.2, 0.0, 0.55, 0.2, MAT("paint:#3e6a8a:0.5"), 14)
    cyl(x + 0.75, y - 0.25, 0.0, 0.25, 0.09, MAT("flat:#c8c0a0:0.4"), 10)


@P.prop
def purifier_t2(x, y, rng):
    """Tier 2 — gravity sand filter tower: a raised tank on a timber frame feeding two stacked filter drums
    (gravel, sand, charcoal), a spigot over a trough, a hand pump on the intake."""
    wood = MAT("wood:#6a4a30:#4a3220")
    for (a, b) in ((-0.5, -0.5), (0.5, -0.5), (-0.5, 0.5), (0.5, 0.5)):
        P.B(x + a - 0.05, y + b - 0.05, 0, x + a + 0.05, y + b + 0.05, 1.7, wood)
    P.B(x - 0.6, y - 0.6, 1.6, x + 0.6, y + 0.6, 1.7, wood)
    cyl(x, y, 1.7, 2.45, 0.55, MAT("paint:#5a6a6a:0.6"), 20)
    cyl(x, y, 2.45, 2.5, 0.57, MAT("metal:#8a8a80"), 20)
    for (zz, col) in ((0.15, "#7a6a50"), (0.75, "#8a7a5a")):            # filter drums under the tank
        cyl(x + 0.95, y, zz, zz + 0.55, 0.3, MAT("paint:%s:0.5" % col), 16)
    cyl(x + 0.5, y, 1.25, 1.65, 0.035, MAT("metal:#7a7a70"), 8)
    P.B(x + 0.5, y - 0.03, 1.25, x + 0.95, y + 0.03, 1.31, MAT("metal:#7a7a70"))
    P.B(x + 0.85, y + 0.35, 0, x + 1.65, y + 0.75, 0.25, wood)                   # trough
    P.B(x + 0.9, y + 0.4, 0.2, x + 1.6, y + 0.7, 0.23, MAT("flat:#3a6070:0.1"))
    P.B(x - 0.95, y - 0.1, 0, x - 0.75, y + 0.1, 0.8, MAT("metal:#5a5a54"))   # hand pump
    P.B(x - 0.95, y - 0.02, 0.75, x - 0.55, y + 0.02, 0.8, MAT("metal:#5a5a54"))


@P.prop
def purifier_t3(x, y, rng):
    """Tier 3 — powered treatment plant: concrete pad, two storage tanks, a pressure filter vessel, an
    electric pump, a UV/boiler cabinet with status lights, pipework between them all, a generator."""
    conc, steel = MAT("conc:#9a968a"), MAT("metal:#9a9a90")
    P.B(x - 1.6, y - 1.1, 0, x + 1.6, y + 1.1, 0.12, conc)
    for (dx, dy) in ((-0.9, -0.45), (-0.9, 0.55)):
        cyl(x + dx, y + dy, 0.12, 1.75, 0.42, MAT("paint:#c8c4b4:0.4"), 24)
        cyl(x + dx, y + dy, 1.75, 1.85, 0.3, steel, 20)
    cyl(x + 0.25, y - 0.3, 0.12, 1.3, 0.28, MAT("paint:#3e6a8a:0.3"), 20)          # pressure filter
    sphere(x + 0.25, y - 0.3, 1.3, 0.28, MAT("paint:#3e6a8a:0.3"), scale=(1, 1, 0.5))
    P.B(x + 0.85, y - 0.75, 0.12, x + 1.45, y - 0.15, 0.6, MAT("paint:#4e7a5a:0.3"))     # pump
    P.B(x + 0.7, y + 0.2, 0.12, x + 1.45, y + 0.85, 1.25, MAT("paint:#8a8a80:0.3"))     # UV / boiler cabinet
    for k, c in enumerate(("#40e060", "#e0c040", "#40e060")):
        sphere(x + 0.9 + k * 0.17, y + 0.86, 1.05, 0.035, MAT("glow:" + c))
    for (a, b) in (((-0.5, -0.45), (0.0, -0.45)), ((-0.5, 0.55), (0.25, 0.55)), ((0.5, -0.3), (0.85, -0.45))):
        x0, y0 = x + min(a[0], b[0]), y + min(a[1], b[1])
        x1, y1 = x + max(a[0], b[0]), y + max(a[1], b[1])
        P.B(x0, y0 - 0.04, 0.5, x1 + 0.02, y1 + 0.04, 0.58, steel)
    P.B(x + 0.25 - 0.04, y - 0.3, 0.5, x + 0.25 + 0.04, y + 0.55, 0.58, steel)
    P.generator(x - 1.25, y + 1.4, 0, rng)


# ------------------------------------------------------------------ helpers
def ground(flats=(), amp=0.18):
    kit.terrain(-26, -26, W_ + 26, H_ + 26, kit.mat_terrain(), amp=amp, scale=0.45, res=1, flat=list(flats))


WATER = []
def water(x0, y0, x1, y1, deep="#2a4650"):
    x0 = -26 if x0 <= -16 else x0; y0 = -26 if y0 <= -16 else y0
    x1 = W_ + 26 if x1 >= W_ + 16 else x1; y1 = H_ + 26 if y1 >= H_ + 16 else y1
    WATER.append((x0 - 0.5, y0 - 0.5, x1 + 0.5, y1 + 0.5))
    box(x0, y0, -0.05, x1, y1, 0.01, MAT("flat:%s:0.06" % deep))
    kit.patch(x0 - 0.8, y0 - 0.8, x1 + 0.8, y1 + 0.8, [(0.3, '#4a4234'), (0.7, '#5e5442')], z=0.003)


def tint(x0, y0, x1, y1, stops):
    kit.patch(x0, y0, x1, y1, stops, z=0.005)


def shack(x, y, rng, w=None, d=None, col=None, z0=0.0):
    w = w or rng.uniform(1.4, 2.4); d = d or rng.uniform(1.2, 2.0)
    col = col or rng.choice(["#7a6a56", "#8a5a3e", "#6e7a74", "#9a8a6a", "#5e6458"])
    box(x, y, z0, x + w, y + d, z0 + 1.15, MAT("paint:%s:0.6" % col))
    box(x - 0.1, y - 0.1, z0 + 1.15, x + w + 0.1, y + d + 0.1, z0 + 1.25, MAT("metal:#7a7468"))
    box(x + w * 0.4, y + d - 0.02, z0, x + w * 0.4 + 0.45, y + d + 0.02, z0 + 0.9, MAT("flat:#2a2018:0.9"))


def stilts(x, y, w, d, h):
    for (a, b) in ((0, 0), (w, 0), (0, d), (w, d), (w / 2, d / 2)):
        box(x + a - 0.06, y + b - 0.06, -0.1, x + a + 0.06, y + b + 0.06, h, MAT("wood:#4a3622:#3a2a1a"))


def trees(n, rng, kinds=("dead", "sparse", "scrub"), avoid=(), area=None):
    x0, y0, x1, y1 = area or (-15, -15, W_ + 15, H_ + 15)
    with P.zone(prio=1):
        for k in range(n * 3):
            x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
            if any(a <= x <= c and b <= y <= d for (a, b, c, d) in list(avoid) + WATER): continue
            P.tree(x, y, 0, random.Random(k * 13 + 1), kind=rng.choice(kinds))


def desert(n, rng, avoid=()):
    with P.zone(prio=1):
        for k in range(n * 3):
            x, y = rng.uniform(-15, W_ + 15), rng.uniform(-15, H_ + 15)
            if any(a <= x <= c and b <= y <= d for (a, b, c, d) in list(avoid) + WATER): continue
            rng.choice([P.deadbush, P.cactus, P.joshua_tree, P.rock, P.tumbleweed])(x, y, rng.uniform(0, 360), rng)


def cliff(x0, y0, x1, y1, h, rng, col=("#a0583a", "#7a3e2a"), step=2.6):
    """A rock mass built from jittered columns, so its top and edges are ragged."""
    m = MAT("rock:%s:%s" % col)
    x = x0
    while x < x1:
        y = y0
        while y < y1:
            hh = h * rng.uniform(0.85, 1.05)
            box(x, y, -0.1, min(x + step, x1) + rng.uniform(0, 0.6), min(y + step, y1) + rng.uniform(0, 0.6), hh, m)
            if rng.random() < 0.5:                             # a lower ledge or a boulder on top
                box(x + rng.uniform(0, 1), y + rng.uniform(0, 1), hh, x + rng.uniform(1.2, 2.2), y + rng.uniform(1.2, 2.2), hh + rng.uniform(0.2, 0.6), m)
            y += step
        x += step


def render(name, title):
    sc = bpy.context.scene
    if name != "purifiers":
        P.scatter(-24, -24, W_ + 24, H_ + 24, 0.5, "wild", random.Random(7), avoid=[(-1, -1, W_ + 1, H_ + 1)] + WATER)
    lights()
    lib.PX_PER_UNIT = SCALE_PX
    cx, cy = W_ / 2, H_ / 2
    Wpx = int((W_ + H_) * SCALE_PX * 0.72) + 80
    Hpx = int((W_ + H_) * SCALE_PX * 0.36) + 160
    camera(cx, cy, Wpx, Hpx, 0.6)
    sc.cycles.samples = 20
    sc.render.filepath = os.path.join(OUT, name + "_raw.png")
    bpy.ops.render.render(write_still=True)
    im = fallout_grade(Image.open(sc.render.filepath)).convert("RGB")
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 26)
    d.text((22, 18), title, font=f, fill=(20, 16, 10)); d.text((20, 16), title, font=f, fill=(240, 226, 190))
    im.save(os.path.join(OUT, name + ".png"))
    os.remove(sc.render.filepath)
    print("scene", name, flush=True)


def start(seed):
    reset()
    WATER.clear()
    P._MC.clear(); kit._FP.clear(); kit.SOLIDS.clear(); kit.PAVED.clear()
    M = kit.materials()
    LM.GRAF_DIR = os.path.join(OUT, "graf"); os.makedirs(LM.GRAF_DIR, exist_ok=True)
    return M, random.Random(seed)


# ------------------------------------------------------------------ recipes
def clearwater(M, rng):
    """Lake Winona's marina: the lake fills the west, piers run out into it, rows of stills and filter towers
    on the shore, a powered plant by the cisterns, homes up the slope to the east."""
    ground(flats=[(-16, -16, 12, H_ + 16)])
    water(-16, -16, 11, H_ + 16)
    for k in range(5):                                         # piers with boathouses
        y = 2 + k * 4.6
        box(4.0, y, 0.1, 11.6, y + 0.8, 0.22, MAT("wood:#6a4a30:#4a3220"))
        stilts(4.0, y, 7.6, 0.8, 0.12)
        if k % 2 == 0: shack(4.5, y - 1.6, rng, 2.0, 1.4, z0=0.22); stilts(4.5, y - 1.6, 2.0, 1.4, 0.22)
    with P.zone(prio=2):
        for k in range(10):                                    # tier 1 stills in rows on the shore
            purifier_t1(13.0 + (k % 5) * 1.8, 2.0 + (k // 5) * 1.6, 0, rng)
        for k in range(4):
            purifier_t2(13.5 + k * 2.6, 7.0, 0, rng)
        purifier_t3(15.5, 12.5, 0, rng)
        for k in range(5):
            P.water_tank(19.0 + (k % 3) * 1.4, 11.0 + (k // 3) * 1.6, 0, rng)
    for (x, y) in ((22, 2.5), (28.5, 2.5), (21, 17), (28, 17)):
        S.ranch(M, x, y, rng, "s")
    kit.footpath([(12.5, 13), (20, 14.5), (33, 14)], 1.2, seed=3)
    trees(20, rng, avoid=[(-16, -16, 33, 24)])


def redwall(M, rng):
    """Houses carved into both walls of Scorch Canyon: two red rock masses with a gorge between, homes on
    the ledges, rope bridges across, a cargo lift, gardens on the gorge floor by the spring."""
    ground(flats=[(-16, 9, W_ + 16, 15)], amp=0.1)
    tint(-16, 9, W_ + 16, 15, [(0.3, '#7a5a40'), (0.7, '#8a6a48')])
    cliff(-16, -16, W_ + 16, 7.0, 3.4, rng)
    cliff(-16, 16.5, W_ + 16, H_ + 16, 1.5, rng)                # the near wall kept low so the gorge shows
    for k in range(7):                                         # cliff dwellings cut into the far wall, two rows
        x = 1 + k * 4.6
        for (zz, dx) in ((0.0, 0.0), (1.7, 2.0)):
            box(x + dx, 7.0, zz, x + dx + 2.0, 8.6, zz + 1.3, MAT("paint:#b07a5a:0.4"))
            box(x + dx + 0.7, 8.58, zz, x + dx + 1.2, 8.62, zz + 0.95, MAT("flat:#1a1410:0.9"))
            box(x + dx - 0.1, 8.6, zz + 1.3, x + dx + 2.1, 9.0, zz + 1.38, MAT("wood:#6a4a30:#4a3220"))     # balcony walk
        box(x + 1.0, 16.6, 0.0, x + 2.8, 17.6, 1.4, MAT("paint:#a0705a:0.4"))
    for x in (6.5, 17.0, 27.5):                                # rope bridges
        box(x, 8.6, 1.5, x + 0.6, 16.5, 1.56, MAT("wood:#6a4a30:#4a3220"))
    box(12.0, 8.5, 0, 12.8, 9.3, 3.8, MAT("wood:#4e3622:#3a2a1a"))   # lift tower
    box(11.9, 8.4, 3.8, 12.9, 9.4, 3.95, MAT("metal:#7a7468"))
    LM.field(14, 10.2, 22, 13.8, rng, crop="stubble")
    with P.zone(prio=2):
        purifier_t2(24.0, 12.0, 0, rng)
        P.water_tank(9.0, 12.5, 0, rng)


def greenmarsh(M, rng):
    """Stilt houses and boardwalks over the river marsh: pools everywhere, paddies, fish ponds, bog."""
    ground(amp=0.06)
    tint(-16, -16, W_ + 16, H_ + 16, [(0.3, '#4e6236'), (0.7, '#6a7a4a')])
    for k in range(26):
        x, y = rng.uniform(-3, W_), rng.uniform(-3, H_)
        w, d = rng.uniform(1.0, 3.5), rng.uniform(0.8, 2.6)
        box(x, y, -0.05, x + w, y + d, 0.02, MAT("flat:#2e4a48:0.06"))
    water(W_ - 4, -16, W_ + 16, H_ + 16)                           # the river on the east
    for (x0, y0) in ((2, 15), (6, 15), (2, 19), (6, 19)):          # flooded paddies
        box(x0, y0, -0.02, x0 + 3.5, y0 + 3.5, 0.03, MAT("flat:#4a6a4a:0.15"))
        LM.field(x0 + 0.3, y0 + 0.3, x0 + 3.2, y0 + 3.2, rng, crop="stubble")
    for (x, y) in ((12, 4), (16, 3), (20, 5), (13, 9), (18, 10), (23, 9), (15, 15), (21, 16), (25, 14)):
        shack(x, y, rng, 2.2, 1.8, z0=0.6); stilts(x, y, 2.2, 1.8, 0.6)
    box(11, 6.8, 0.5, 27, 7.4, 0.58, MAT("wood:#6a4a30:#4a3220"))   # boardwalks
    box(14.4, 6.8, 0.5, 15.0, 17.0, 0.58, MAT("wood:#6a4a30:#4a3220"))
    box(20.4, 6.8, 0.5, 21.0, 17.0, 0.58, MAT("wood:#6a4a30:#4a3220"))
    with P.zone(prio=2):
        purifier_t1(8.0, 4.0, 0, rng); purifier_t1(8.0, 6.0, 0, rng); purifier_t2(9.5, 10.0, 0, rng)
    trees(30, rng, kinds=("dead", "sparse"), avoid=[(8, 0, 30, 20)])


def atomic_plaza(M, rng):
    """The mall town: the mall itself, its parking lot walled with stacked cars, market stalls in the lot."""
    ground(flats=[(-16, -16, W_ + 16, H_ + 16)], amp=0.05)
    LM.mall(M, 6.0, 2.0, rng, lot_rows=1, road_y=22.0, entry_x=16.0)
    kit.road(-16, 22.0, W_ + 16, 25.0, z=0.006, name="hwy")
    with P.zone(prio=2):
        for k in range(36):                                    # car wall round the lot
            a = k / 36 * 6.283
            P.car_wreck(13 + math.cos(a) * 12.5, 12 + math.sin(a) * 9.5, math.degrees(a) + 90, rng)
        for k in range(8):
            P.lean_to(6 + (k % 4) * 3.4, 15.0 + (k // 4) * 2.6, 0, rng)
            P.crate(7.4 + (k % 4) * 3.4, 15.9 + (k // 4) * 2.6, 0, rng)


def iron_gate(M, rng):
    """The prison town: the old penitentiary with its walls and towers, the yard farmed, a gate on the road."""
    ground(flats=[(2, 2, 30, 24)], amp=0.15)
    LM.jail(M, 10.0, 6.0, rng)
    conc = MAT("conc:#9a968a")
    for (a, b, c, d) in ((3, 3, 29, 3.4), (3, 22.6, 29, 23), (3, 3, 3.4, 23), (28.6, 3, 29, 23)):
        box(a, b, 0, c, d, 2.4, conc)
    for (x, y) in ((3, 3), (29, 3), (3, 23), (29, 23)):
        box(x - 0.6, y - 0.6, 0, x + 0.6, y + 0.6, 3.6, conc); box(x - 0.8, y - 0.8, 3.6, x + 0.8, y + 0.8, 3.9, MAT("metal:#6a6a64"))
    for (x0, y0) in ((5, 14), (11, 14), (5, 18.5)):
        LM.field(x0, y0, x0 + 5, y0 + 3.5, rng, crop="furrow")
    box(15, 22.5, 0, 17.5, 23.1, 2.0, MAT("metal:#5a5a54"))
    kit.road(15.2, 23, 17.3, H_ + 16, z=0.006, name="gate_road")
    with P.zone(prio=2):
        for k in range(2): S.ranch(M, 17.5 + k * 6.0, 15.5, rng, "s")


def victory_stadium(M, rng):
    """A town in the bleachers: the stadium bowl in tiers, half collapsed, shacks in the stands, a market and
    a fighting ring on the field, floodlight towers."""
    ground(flats=[(-16, -16, W_ + 16, H_ + 16)], amp=0.05)
    cx, cy = 17, 13
    conc = MAT("conc:#a8a498")
    for tier in range(4):
        rx, ry = 9.5 + tier * 1.3, 6.5 + tier * 1.1
        for k in range(48):
            a = k / 48 * 6.283
            if 0.3 < a < 1.2 and tier > 1: continue            # collapsed section
            x, y = cx + math.cos(a) * rx, cy + math.sin(a) * ry
            box(x - 0.75, y - 0.75, 0, x + 0.75, y + 0.75, 0.6 + tier * 0.6, conc)
    tint(cx - 8, cy - 5.5, cx + 8, cy + 5.5, [(0.3, '#5e6a3e'), (0.7, '#6e7a48')])
    box(cx - 1.6, cy - 1.6, 0, cx + 1.6, cy + 1.6, 0.25, MAT("flat:#7a6a50:0.9"))
    for (a, b) in ((-1.6, -1.6), (1.6, -1.6), (-1.6, 1.6), (1.6, 1.6)):
        box(cx + a - 0.05, cy + b - 0.05, 0.25, cx + a + 0.05, cy + b + 0.05, 1.0, MAT("metal:#8a8a80"))
    with P.zone(prio=2):
        for k in range(10):
            a = rng.uniform(0, 6.283)
            P.lean_to(cx + math.cos(a) * 5.5, cy + math.sin(a) * 3.6, math.degrees(a) + 90, rng)
        for k in range(14):
            a = k / 14 * 6.283
            shack(cx + math.cos(a) * 13.5 - 1, cy + math.sin(a) * 10 - 1, rng, 1.6, 1.4, z0=2.4)
    for (x, y) in ((cx - 13, cy - 10), (cx + 13, cy - 10), (cx - 13, cy + 10), (cx + 13, cy + 10)):
        box(x - 0.15, y - 0.15, 0, x + 0.15, y + 0.15, 5.5, MAT("metal:#7a7a70")); box(x - 0.6, y - 0.3, 5.5, x + 0.6, y + 0.3, 6.0, MAT("glow:#fff0c0"))


def ridgeback_dam(M, rng):
    """Engineers living in the dam: the reservoir behind (north), the concrete wall, the turbine hall below,
    the river running on south, power lines off along the bank."""
    ground(flats=[(-16, -16, W_ + 16, 9), (13, 9, 21, H_ + 16)], amp=0.25)
    water(-16, -16, W_ + 16, 8.6)
    water(13.5, 13, 20.5, H_ + 16)
    conc = MAT("conc:#b0aca0")
    box(-16, 8.6, -0.3, W_ + 16, 10.4, 3.0, conc)                  # the dam wall
    box(-16, 8.4, 3.0, W_ + 16, 10.6, 3.2, MAT("conc:#c0bcb0"))
    LM._flat_box_building(M, 12.0, 10.8, 10, 3, kit.mat_stucco("turb", '#a8a498', '#7a766a'), storeys=2)
    for k in range(4):
        box(13.6 + k * 1.8, 13.8, 0, 14.6 + k * 1.8, 14.4, 0.6, MAT("flat:#e0eef0:0.05"))   # spillway foam
    with P.zone(prio=2):
        for k in range(6):
            P.lamp_post(2 + k * 5.5, 12.0, 0, rng)
        for (x, y) in ((24, 15), (28, 18), (6, 15), (3, 19)):
            shack(x, y, rng)
        P.generator(23, 11.5, 0, rng); P.generator(25, 11.5, 0, rng)
    trees(16, rng, kinds=("pine", "dead"), avoid=[(-16, -16, W_ + 16, 14), (12, 0, 22, 30)])


def bonewhite_flats(M, rng):
    """Salt harvesters in the hangars of a rocket-car test track on the dry lake bed."""
    ground(flats=[(-16, -16, W_ + 16, H_ + 16)], amp=0.03)
    tint(-16, -16, W_ + 16, H_ + 16, [(0.3, '#d8d0bc'), (0.7, '#ece6d6')])
    for k in range(5):                                         # quonset-like hangars
        x = 3 + k * 5.5
        for j in range(8):
            a = j / 7 * math.pi
            box(x + 1.8 - math.cos(a) * 1.8 - 0.25, 2, 0, x + 1.8 - math.cos(a) * 1.8 + 0.25, 6.5, math.sin(a) * 1.8 + 0.2, MAT("metal:#9a9488"))
    kit.road(-16, 9.5, W_ + 16, 11.5, z=0.006, name="track")
    for k in range(6):                                         # salt pans and heaps
        x = 4 + k * 4.5
        box(x, 15, -0.02, x + 3, 18, 0.03, MAT("flat:#c8c0aa:0.5"))
        sphere(x + 1.5, 20.5, 0, 0.7, MAT("flat:#f0ece0:0.8"), scale=(1, 1, 0.6))
    with P.zone(prio=2):
        P.car_wreck(8, 10.5, 0, rng); P.car_wreck(19, 10.4, 180, rng); P.car_wreck(26, 7.5, 30, rng, style="truck")
        for k in range(6): P.barrel(30, 3 + k * 0.7, 0, rng)


def rimtown(M, rng):
    """Ghoul glassworkers on the rim of the Hollow Sun: the crater's edge, shacks round it, glass piles."""
    ground(amp=0.2)
    LM.crater(10, 13, 0, rng, r=9.0)
    tint(2, 5, 18, 21, [(0.3, '#2c2c24'), (0.7, '#3a3a30')])
    for k in range(12):                                        # glowing glass shards in the crater
        sphere(rng.uniform(6, 14), rng.uniform(9, 17), 0.05, rng.uniform(0.12, 0.3), MAT("glow:#86e050"), scale=(1, 1, 0.4))
    for k in range(10):
        a = -0.9 + k * 0.32
        shack(10 + math.cos(a) * 12.5, 13 + math.sin(a) * 11 - 0.8, rng)
    with P.zone(prio=2):
        for k in range(6):
            P.junk_pile(22 + rng.uniform(-2, 8), rng.uniform(2, 24), 0, rng)
        for k in range(5):
            P.campfire_pit(24 + (k % 3) * 3, 6 + (k // 3) * 9, 0, rng)
    desert(30, rng, avoid=[(0, 2, 33, 25)])


def fort_steadfast(M, rng):
    """The army base: perimeter wall with a gate, barracks rows, a motor pool, the parade ground and flag."""
    ground(flats=[(2, 2, 30, 24)], amp=0.12)
    conc = MAT("conc:#8e8a7e")
    for (a, b, c, d) in ((2, 2, 30, 2.4), (2, 2, 2.4, 24), (29.6, 2, 30, 24), (2, 23.6, 14, 24), (18, 23.6, 30, 24)):
        box(a, b, 0, c, d, 1.6, conc)
    for r in range(3):
        for k in range(3):
            LM._flat_box_building(M, 4 + k * 5.0, 4 + r * 4.5, 4, 2, kit.mat_stucco("bk%d%d" % (r, k), '#8a8e72', '#6a6e52'))
    tint(19, 5, 28, 13, [(0.3, '#6e6a5a'), (0.7, '#7e7a68')])
    box(23.4, 8.9, 0, 23.6, 9.1, 4.0, MAT("metal:#8a8a80")); box(23.6, 8.95, 3.2, 24.6, 9.05, 3.9, MAT("paint:#3e5a8a:0.2"))
    with P.zone(prio=2):
        for k in range(4): P.car_wreck(20 + k * 2.2, 16.5, 90, rng, style="truck")
        for k in range(10): P.sandbags(14.5 + (k % 5) * 0.9, 22.5 - (k // 5) * 0.6, 0, rng)
    desert(25, rng, avoid=[(1, 1, 31, 25)])


def goldenrod(M, rng):
    """The breadbasket: a grain elevator (a cluster of silos), barns, fields all round, a market street."""
    ground(flats=[(-16, 11, W_ + 16, 14)], amp=0.12)
    kit.road(-16, 11.5, W_ + 16, 13.5, z=0.006, name="main")
    for k in range(4): LM.silo(M, 3.0 + (k % 2) * 2.4, 3.0 + (k // 2) * 2.4, rng)
    LM.barn(M, 8.5, 2.5, rng)
    LM.storefront_row(M, 14.0, 7.2, 3, rng)
    for (x, y) in ((25, 4), (14, 16), (21, 16.5)):
        S.ranch(M, x, y, rng, "s")
    for (x0, y0, x1, y1) in ((0, 15, 11, 25), (27, 15, 35, 25), (26, -3, 35, 9)):
        LM.field(x0, y0, x1, y1, rng)
    with P.zone(prio=2):
        P.water_tank(12, 3.5, 0, rng); purifier_t2(12, 8.5, 0, rng)
        for k in range(6): P.wood_fence(-0.5 + k, 14.6, 0, rng, n=1)


def splinter_creek(M, rng):
    """The lumber town on the creek: a sawmill with a water wheel, log piles, cabins, dead pines all round."""
    ground(flats=[(-16, 12, W_ + 16, 15)], amp=0.25)
    water(-16, 12.5, W_ + 16, 14.5)
    LM.barn(M, 10.0, 8.0, rng)
    cyl(13.6, 12.8, 0.6, 0.9, 1.4, MAT("wood:#5a4028:#3a2a1a"), 18).rotation_euler = (math.radians(90), 0, 0)
    for k in range(5):
        for j in range(3 - k // 2):
            cyl(17 + k * 0.5, 9.5, 0.2 + j * 0.35, 0.2 + j * 0.35, 0.17, MAT("wood:#7a5636:#5a4028"), 10)
    for k in range(6):
        o = cyl(17.0 + k * 0.45, 8.0, 0.18, 0.18, 0.16, MAT("wood:#86603c:#5e4228"), 10)
    for (x, y) in ((3, 3), (22, 3), (27, 7), (4, 17.5), (12, 18), (22, 18)):
        shack(x, y, rng, col=rng.choice(["#6a4a30", "#7a5636"]))
    box(8, 12.3, 0.25, 9.2, 14.7, 0.35, MAT("wood:#6a4a30:#4a3220"))
    trees(70, rng, kinds=("pine", "dead", "dead"), avoid=[(2, 2, 30, 22)])


def copperhead(M, rng):
    """The company mining town in the southern hills: a timber headframe over the shaft, ore carts, the
    company store and saloon on one street, miners' shacks up the slope."""
    ground(flats=[(-16, 14, W_ + 16, 17)], amp=0.45)
    kit.road(-16, 14.5, W_ + 16, 16.5, z=0.006, name="main")
    wood = MAT("wood:#4e3622:#3a2a1a")
    for (a, b) in ((0, 0), (2, 0), (0, 2), (2, 2)):
        box(6 + a - 0.1, 5 + b - 0.1, 0, 6 + a + 0.1, 5 + b + 0.1, 5.0, wood)
    box(5.8, 4.8, 5.0, 8.2, 7.2, 5.3, wood)
    cyl(7, 6, 5.3, 5.9, 0.6, MAT("metal:#6a5a48"), 16)
    LM.storefront_row(M, 12.0, 10.4, 4, rng)
    for k in range(8):
        shack(2 + (k % 4) * 6.5, 18.5 + (k // 4) * 3.2, rng)
    with P.zone(prio=2):
        for k in range(4): P.crate(9 + k * 0.9, 7.2, 0, rng)
        P.junk_pile(4, 9, 0, rng); P.tire_stack(10, 4, 0, rng)
    desert(30, rng, avoid=[(1, 2, 33, 25)])


def wellspring(M, rng):
    """The plain crossroads town round its deep well: two roads cross, a saloon and a store, a gas station."""
    ground(flats=[(-16, 11, W_ + 16, 14), (15, -16, 18, H_ + 16)], amp=0.12)
    kit.road(-16, 11.5, W_ + 16, 13.5, z=0.006, name="ew")
    kit.road(15.5, -16, 17.5, H_ + 16, z=0.0064, name="ns")
    cyl(20.5, 16.5, 0, 0.7, 0.8, MAT("rock:#8a8272:#6e685c"), 16)
    box(19.8, 16.4, 0.7, 21.2, 16.6, 2.0, MAT("wood:#4e3622:#3a2a1a"))
    LM.storefront_row(M, 1.0, 7.2, 3, rng)
    LM.gas_station(M, 20.0, 3.0, rng, road_y=11.5)
    for (x, y) in ((2, 16.5), (8.5, 17), (23, 17), (29, 17)):
        S.ranch(M, x, y, rng, "s")
    with P.zone(prio=2):
        purifier_t2(22.5, 15.0, 0, rng)
    desert(30, rng, avoid=[(0, 0, 33, 24)])


def sterling_waterfront(M, rng):
    """River traders: warehouses on the quay, a fortified market on a beached ferry, rusting barges."""
    ground(flats=[(-16, 15, W_ + 16, H_ + 16)], amp=0.05)
    water(-16, 17, W_ + 16, H_ + 16)
    box(-16, 15.5, 0, W_ + 16, 17, 0.25, MAT("conc:#8a867a"))
    for k in range(4):
        LM._flat_box_building(M, 1 + k * 8, 3, 6, 4, kit.mat_stucco("wh%d" % k, '#8a7a66', '#6a5a48'))
    hull = MAT("paint:#7a4a3a:0.7")
    box(6, 17.5, -0.2, 20, 22, 1.4, hull); box(9, 18.5, 1.4, 17, 21, 2.8, MAT("paint:#c8c0a8:0.5"))
    for k in range(2):
        box(23 + k * 6, 19, -0.2, 28 + k * 6, 22, 0.6, MAT("paint:#5a4a3a:0.8"))
    with P.zone(prio=2):
        for k in range(10): P.crate(2 + k * 2.8, 13.5, 0, rng)
        for k in range(6): P.lean_to(8 + k * 2.2, 15.9, 0, rng)


def maple_grove(M, rng):
    """Endless cul-de-sacs of picked-over houses."""
    ground(flats=[(-16, 11, W_ + 16, 14), (15, 0, 18, 11)], amp=0.06)
    kit.road(-16, 11.5, W_ + 16, 13.5, z=0.006, name="st")
    kit.road(15.5, 1, 17.5, 11.5, ends=(True, False), z=0.0064, name="cds")
    for (x, y, side) in ((2, 6, "s"), (8, 6, "s"), (19, 6, "s"), (25, 6, "s"), (10, 0, "e"), (19.5, 0.5, "s"),
                         (2, 16, "s"), (8, 16.5, "s"), (14, 16, "s"), (20, 16.5, "s"), (26, 16, "s")):
        S.ranch(M, x, y, rng, side)
    with P.zone(prio=2):
        for k in range(6): P.car_wreck(rng.uniform(0, 32), rng.uniform(11.8, 13.2), rng.choice([0, 180]), rng)
    P.scatter(-16, -16, W_ + 16, H_ + 16, 3.0, "suburb", rng)


def ferrymans_landing(M, rng):
    """A trading post on stilts where the ferries cross the Sable."""
    ground(flats=[(-16, 8, W_ + 16, 18)], amp=0.15)
    water(-16, 9, W_ + 16, 17)
    box(10, 10.5, 0.8, 20, 15.5, 0.9, MAT("wood:#6a4a30:#4a3220")); stilts(10, 10.5, 10, 5, 0.8)
    shack(11, 11, rng, 4, 3, z0=0.9); shack(16, 11.5, rng, 3, 2.5, z0=0.9)
    box(22, 12, 0.0, 26, 14, 0.25, MAT("wood:#7a5636:#5a4028"))           # the ferry raft
    box(-16, 12.95, 1.2, W_ + 16, 13.05, 1.25, MAT("flat:#5a4a3a:0.9"))      # ferry rope
    with P.zone(prio=2):
        for k in range(5): P.crate(4 + k, 6.5, 0, rng)
        P.lean_to(5, 4, 0, rng); P.lean_to(26, 20, 180, rng)
    trees(20, rng, kinds=("dead", "scrub"), avoid=[(-16, 7, W_ + 16, 19)])


def big_wheel_stop(M, rng):
    """Caravans park their wagons by the old diesel pumps: the highway, a gas station, a diner, wagons."""
    ground(flats=[(-16, 14, W_ + 16, 17)], amp=0.06)
    kit.road(-16, 14.5, W_ + 16, 16.5, z=0.006, name="hwy")
    LM.gas_station(M, 4.0, 6.0, rng, road_y=14.5)
    LM.storefront_row(M, 16.0, 9.2, 2, rng)
    with P.zone(prio=2):
        for k in range(5): P.car_wreck(17 + k * 3, 20.5, 90, rng, style="truck")
        for k in range(3): P.campfire_pit(19 + k * 4, 23.5, 0, rng)
    desert(30, rng, avoid=[(0, 3, 33, 25)])


def double_bar_ranch(M, rng):
    """A cattle ranch on the open range: the house, a barn, corrals of rail fence, a windmill tank."""
    ground(amp=0.12)
    S.ranch(M, 4, 4, rng, "s")
    LM.barn(M, 14, 3, rng)
    with P.zone(prio=2):
        for k in range(12):
            P.wood_fence(14 + k, 12, 0, rng, n=1); P.wood_fence(14 + k, 20, 0, rng, n=1)
        P.water_tank(10, 12, 0, rng)
    LM.field(2, 14, 11, 22, rng, crop="stubble")
    desert(25, rng, avoid=[(1, 1, 28, 23)])


def our_lady_mission(M, rng):
    """Nuns running a clinic in an adobe mission: the church, a walled courtyard, the clinic, gardens."""
    ground(flats=[(3, 3, 29, 23)], amp=0.12)
    LM.church(M, 6.0, 4.0, rng)
    LM.clinic(M, 18.0, 5.0, rng)
    adobe = MAT("conc:#c8a888")
    for (a, b, c, d) in ((3, 3, 29, 3.4), (3, 22.6, 14, 23), (18, 22.6, 29, 23), (3, 3, 3.4, 23), (28.6, 3, 29, 23)):
        box(a, b, 0, c, d, 1.4, adobe)
    LM.field(6, 15, 13, 21, rng, crop="furrow")
    with P.zone(prio=2):
        purifier_t1(20, 17, 0, rng); purifier_t1(22.5, 17, 0, rng)
        for k in range(4): P.bench(16 + k * 2.2, 13.5, 0, rng)
    desert(25, rng, avoid=[(2, 2, 30, 24)])


def gus_salvage(M, rng):
    """Gus's junkyard: stacked wrecks, scrap piles, a crane, a chain-link fence and his shack."""
    ground(flats=[(2, 2, 30, 24)], amp=0.06)
    shack(14, 3, rng, 3, 2.2)
    with P.zone(prio=2):
        for k in range(22): P.car_wreck(rng.uniform(4, 28), rng.uniform(8, 22), rng.uniform(0, 360), rng)
        for k in range(8): P.junk_pile(rng.uniform(4, 28), rng.uniform(4, 22), 0, rng)
        for k in range(26): P.chainlink(3 + k, 2.5, 0, rng, n=1)
    box(25, 4, 0, 25.4, 4.4, 4.5, MAT("paint:#c8a040:0.6")); box(22, 4.05, 4.3, 28, 4.35, 4.6, MAT("paint:#c8a040:0.6"))
    desert(20, rng, avoid=[(1, 1, 31, 25)])


def bluebird_lodge(M, rng):
    """A neon-signed motel on the interstate: an L of rooms round a lot, the office, the big sign."""
    ground(flats=[(-16, 15, W_ + 16, 18), (4, 4, 28, 15)], amp=0.06)
    kit.road(-16, 15.5, W_ + 16, 17.5, z=0.006, name="hwy")
    LM.storefront_row(M, 5.0, 3.0, 5, rng)
    LM.storefront_row(M, 22.0, 7.2, 1, rng)
    with P.zone(prio=2):
        P.billboard(26, 13.5, 0, rng)
        for k in range(4): P.car_wreck(7 + k * 4, 11.5, 90, rng)
    desert(25, rng, avoid=[(3, 2, 30, 19)])


def patchwork(M, rng):
    """The starting town: scrap shacks and gardens bolted together round an old motor court on the interstate."""
    ground(flats=[(-16, 15, W_ + 16, 18), (6, 3, 26, 15)], amp=0.1)
    kit.road(-16, 15.5, W_ + 16, 17.5, z=0.006, name="hwy")
    LM.storefront_row(M, 8.0, 3.0, 4, rng)
    for k in range(9):
        shack(2 + (k % 5) * 6.2, 19.5 + (k // 5) * 3.4, rng)
    for (x0, y0) in ((2, 6), (26, 6)):
        LM.field(x0, y0, x0 + 5, y0 + 5, rng, crop="furrow")
    with P.zone(prio=2):
        P.water_tank(23, 4, 0, rng); purifier_t1(23, 10, 0, rng)
        for k in range(8): rng.choice([P.junk_pile, P.tire_stack, P.barrel, P.crate])(rng.uniform(8, 26), rng.uniform(10, 14), 0, rng)
        P.campfire_pit(16, 12, 0, rng)
    desert(20, rng, avoid=[(0, 2, 33, 26)])


def sunbeam_commune(M, rng):
    """A hilltop commune that worships the bomb's light: a big painted sun on the ground, tents in a ring,
    gardens, a wooden sun-tower."""
    ground(amp=0.35)
    tint(10, 6, 24, 20, [(0.3, '#c8a040'), (0.7, '#d8b050')])
    for k in range(12):
        a = k / 12 * 6.283
        box(17 + math.cos(a) * 5.5 - 0.15, 13 + math.sin(a) * 5.5 - 0.15, 0, 17 + math.cos(a) * 5.5 + 0.15, 13 + math.sin(a) * 5.5 + 0.15, 0.08, MAT("paint:#e0c050:0.2"))
    box(16.6, 12.6, 0, 17.4, 13.4, 4.5, MAT("wood:#6a4a30:#4a3220"))
    sphere(17, 13, 4.9, 0.6, MAT("glow:#ffd860"))
    with P.zone(prio=2):
        for k in range(10):
            a = k / 10 * 6.283 + 0.3
            P.lean_to(17 + math.cos(a) * 9.5, 13 + math.sin(a) * 8, math.degrees(a) + 90, rng)
        P.campfire_pit(17, 17, 0, rng); purifier_t1(25, 4, 0, rng)
    for (x0, y0) in ((2, 3), (27, 18)):
        LM.field(x0, y0, x0 + 5, y0 + 4, rng, crop="furrow")
    trees(25, rng, kinds=("dead", "scrub"), avoid=[(4, 2, 30, 24)])


def hangmans_gap(M, rng):
    """Where the interstate leaves the valley between rock walls: a toll barricade, shacks, a gallows sign."""
    ground(flats=[(-16, 11, W_ + 16, 15)], amp=0.2)
    kit.road(-16, 11.5, W_ + 16, 14.5, z=0.006, name="hwy")
    cliff(-16, -16, W_ + 16, 7.5, 3.0, rng, col=("#7a6a58", "#5a4e42"))
    cliff(-16, 18.5, W_ + 16, H_ + 16, 1.8, rng, col=("#7a6a58", "#5a4e42"))
    LM.barricade_line(16.0, 11.3, 16.6, 14.7, rng)
    box(18.5, 9.8, 0, 18.7, 10.0, 3.0, MAT("wood:#4e3622:#3a2a1a")); box(18.5, 9.8, 3.0, 20.0, 10.0, 3.2, MAT("wood:#4e3622:#3a2a1a"))
    for (x, y) in ((8, 8.5), (12, 8.3), (22, 8.6), (26, 16), (9, 16)):
        shack(x, y, rng)
    with P.zone(prio=2):
        for k in range(6): P.car_wreck(rng.uniform(2, 14), rng.uniform(11.8, 14.2), rng.choice([0, 180]), rng)
        for k in range(8): P.sandbags(15.2, 11.2 + k * 0.45, 90, rng)


def lookout_station_3(M, rng):
    """Rangers' fire tower and cabin in the dead woods."""
    ground(amp=0.3)
    wood = MAT("wood:#4e3622:#3a2a1a")
    for (a, b) in ((0, 0), (2, 0), (0, 2), (2, 2)):
        box(15 + a - 0.1, 11 + b - 0.1, 0, 15 + a + 0.1, 11 + b + 0.1, 6.0, wood)
    box(14.6, 10.6, 6.0, 17.4, 13.4, 7.6, MAT("paint:#6a7a5a:0.4")); box(14.4, 10.4, 7.6, 17.6, 13.6, 7.8, MAT("metal:#7a7468"))
    S.ranch(M, 20, 14, rng, "s")
    with P.zone(prio=2):
        P.water_tank(13, 15, 0, rng); P.generator(12, 13, 0, rng); P.campfire_pit(18.5, 17.5, 0, rng)
    trees(90, rng, kinds=("dead", "dead", "pine"), avoid=[(11, 9, 26, 20)])


RECIPES = {
    "sunbeam_commune": (sunbeam_commune, "Sunbeam Commune"), "hangmans_gap": (hangmans_gap, "Hangman's Gap"),
    "lookout_station_3": (lookout_station_3, "Lookout Station 3"),
    "clearwater": (clearwater, "Clearwater"), "redwall": (redwall, "Redwall"), "greenmarsh": (greenmarsh, "Greenmarsh"),
    "atomic_plaza": (atomic_plaza, "Atomic Plaza"), "iron_gate_pen": (iron_gate, "Iron Gate"),
    "victory_stadium": (victory_stadium, "Victory Stadium"), "ridgeback_dam": (ridgeback_dam, "Ridgeback Dam"),
    "bonewhite_flats": (bonewhite_flats, "Bonewhite Flats"), "rimtown": (rimtown, "Rimtown"),
    "fort_steadfast": (fort_steadfast, "Fort Steadfast"), "patchwork": (patchwork, "Patchwork"),
    "goldenrod": (goldenrod, "Goldenrod"), "splinter_creek": (splinter_creek, "Splinter Creek"),
    "copperhead": (copperhead, "Copperhead"), "wellspring": (wellspring, "Wellspring"),
    "sterling_waterfront": (sterling_waterfront, "Sterling Waterfront"), "maple_grove": (maple_grove, "Maple Grove"),
    "ferrymans_landing": (ferrymans_landing, "Ferryman's Landing"), "big_wheel_stop": (big_wheel_stop, "Big Wheel Truck Stop"),
    "double_bar_ranch": (double_bar_ranch, "Double-Bar Ranch"), "our_lady_mission": (our_lady_mission, "Our Lady of the Sands Mission"),
    "gus_salvage": (gus_salvage, "Gus's Salvage"), "bluebird_lodge": (bluebird_lodge, "Bluebird Motor Lodge"),
}


def purifier_sheet():
    global W_, H_
    W_, H_ = 9, 7
    M, rng = start(1)
    kit.terrain(-1, -1, 10, 9, kit.mat_terrain(), amp=0.0)
    purifier_t1(1.5, 5.6, 0, rng); purifier_t2(4.4, 3.6, 0, rng); purifier_t3(7.4, 1.6, 0, rng)
    old = globals()["SCALE_PX"]; globals()["SCALE_PX"] = 70.0
    render("purifiers", "Purifiers: T1 still · T2 filter tower · T3 plant")
    globals()["SCALE_PX"] = old
    W_, H_ = 34, 26


def purifier_sprites():
    """Game sprites (same camera and scale as every other prop) for the three purifier tiers."""
    import port_common as PC
    reset(); lights()
    rng = random.Random(3)
    for name, fn, w, h, ay in (("purifier_t1", purifier_t1, 72, 56, 40), ("purifier_t2", purifier_t2, 112, 150, 120), ("purifier_t3", purifier_t3, 168, 140, 100)):
        obs = fn(0, 0, 0, rng)
        PC.sprite(name, w, h, w // 2, ay, samples=24, bright=1.1, outline=True)
        PC.set_anchor(name, w // 2, ay)
        PC.clear(obs)
        print("sprite", name, flush=True)


if __name__ == "__main__":
    ids = [i for w_ in WHICH for i in (list(RECIPES) if w_ == "all" else [w_])]
    for i, k in enumerate(ids):
        if k == "purifiers":
            purifier_sheet(); continue
        if k == "sprites":
            purifier_sprites(); continue
        if os.path.exists(os.path.join(OUT, k + ".png")) and os.environ.get("SKIP"):
            continue
        fn, title = RECIPES[k]
        M, rng = start(100 + i)
        try:
            fn(M, rng)
            render(k, title)
        except Exception as e:
            import traceback; traceback.print_exc()
            print("FAILED", k, e, flush=True)
