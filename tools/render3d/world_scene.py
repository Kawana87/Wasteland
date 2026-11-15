"""Exploration world: the test town plus a highway, a gas station, a roadside hamlet, a farm with fields,
a bombed-out suburb, a squatter shanty and open wilderness. No enemies; it exists to be looked over
for problems. Renders in tiles (one scene build) and stitches them.
python3 world_scene.py OUT [seed] [tiles e.g. 3x2]"""
import sys, os, math, random
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r3d"
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 9
TILES = sys.argv[3] if len(sys.argv) > 3 else "3x2"
sys.argv = [sys.argv[0], OUT, "none"]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import kit, props as P, landmarks as LM, scenes as S
import map_scene as MS
from kit import house
import bpy
from PIL import Image
from post import fallout_grade

BOUNDS = (-8, -8, 122, 94)
os.makedirs(OUT, exist_ok=True)


def zones(M, rng):
    doors, blockers = [], []
    # highway east out of town, gas station, hamlet
    hwy = (66, 20.0, 124, 23.0)
    LM.gas_station(M, 72.0, 11.5, rng, road_y=20.0)
    LM.storefront_row(M, 95.0, 14.2, 3, rng)
    for k in range(-2 + 95, 106):
        pass
    box(94.5, 19.2, 0.0, 107.5, 20.0, 0.07, M["conc"], bevel=0.02); kit.PAVED.append((94.5, 19.2, 107.5, 20.0))
    LM.church(M, 88.0, 5.0, rng)
    for (x, y, side) in ((100.0, 4.0, "s"), (108.0, 5.0, "s"), (113.0, 12.0, "e")):
        out, bb = S.ranch(M, x, y, rng, side); doors.append(out); blockers.append(bb)
    # farm south of the highway down a dirt road
    out, bb = S.ranch(M, 86.0, 60.0, rng, "e"); doors.append(out); blockers.append(bb)
    LM.barn(M, 94.0, 58.0, rng)
    LM.silo(M, 102.5, 61.0, rng); LM.silo(M, 102.5, 64.0, rng)
    # bombed suburb south-west (the avenue runs on into it)
    ruins = [(2, 58, 5, 4, "bombed"), (10, 57, 4, 4, "burnt"), (17, 58, 5, 3, "bombed"), (3, 68, 4, 3, "burnt"), (11, 67, 5, 4, "bombed"), (19, 68, 4, 4, "burnt"),
             (5, 78, 5, 4, "burnt"), (14, 79, 4, 3, "bombed")]
    for (x, y, w, h, st) in ruins:
        LM.ruin_building(M, x, y, w, h, rng, st, rng.choice(['#8a4434', '#c88c74', '#a89c84', '#8a8276']))
    for (x, y) in ((21.0, 78.0),):
        out, bb = S.ranch(M, x, y, rng, "e"); doors.append(out); blockers.append(bb)
    return hwy, doors, blockers


def dress_zones(M, hwy, doors, blockers, rng):
    kit.road(*hwy, ends=(False, True), z=0.006, name="hwy")
    kit.road(28.0, 53.5, 31.0, 90.0, ends=(False, True), z=0.0064, name="ave_far")
    for k in range(68, 120, 6):
        box(k, 21.47, 0.0066, k + 2.5, 21.53, 0.0075, P.MAT("flat:#a89a6a:0.8"))
    # dirt farm road from the highway, footpaths from the doors
    kit.footpath([(85.0, 23.2), (84.0, 34), (86.5, 46), (85.5, 58), (89.0, 61.5)], 1.3, seed=11)
    kit.footpath([(89.0, 61.5), (96.5, 65.5)], 1.0, seed=12)
    for out in doors:
        gy = 23.9 if out[1] < 20 else None
        if gy:
            kit.footpath(kit.plan_path(out, (out[0] + rng.uniform(-1, 1), 19.0), blockers, rng), 0.55, seed=rng.randint(0, 999))
    # fields with rotted fences
    for (x0, y0, x1, y1) in ((70, 66, 83, 86), (88, 70, 103, 87), (106, 66, 119, 84)):
        LM.field(x0, y0, x1, y1, rng)
        with P.zone(prio=2):
            for xx in range(int(x0), int(x1) - 1, 1):
                if rng.random() < 0.7:
                    P.wood_fence(xx, y0 - 0.4, 0, rng, n=1)
    with P.zone(prio=2):
        P.water_tank(98.5, 63.5, 0, rng); P.generator(92.0, 66.0, 0, rng); P.tire_stack(91.0, 57.0, 0, rng)
        P.car_wreck(90.5, 67.0, 30, rng, style="truck")
    # squatter shanty (peaceful): lean-tos round a fire, junk walls
    cx, cy = 47.0, 76.0
    with P.zone(prio=2):
        P.campfire_pit(cx, cy, 0, rng)
        for k in range(6):
            a = k / 6 * 6.283 + rng.uniform(-.2, .2)
            P.lean_to(cx + math.cos(a) * 4.0, cy + math.sin(a) * 3.2, math.degrees(a) + 90, rng)
        for k in range(10):
            a = k / 10 * 6.283
            fn = rng.choice([P.junk_pile, P.tire_stack, P.barrel, P.crate, P.sandbags])
            fn(cx + math.cos(a) * 7.0, cy + math.sin(a) * 5.6, math.degrees(a), rng)
        P.water_tank(cx + 2.5, cy - 1.0, 0, rng); P.workbench(cx - 2.2, cy + 1.6, 0, rng) if hasattr(P, "workbench") else None
    kit.footpath([(31.2, 72.0), (38, 74.5), (cx - 3, cy)], 0.8, seed=21)
    # craters across the bombed suburb
    for k in range(5):
        LM.crater(rng.uniform(0, 26), rng.uniform(55, 88), rng.uniform(1.0, 1.8), rng)
    # highway wrecks, a jackknifed truck, a roadblock
    with P.zone(prio=1):
        for k in range(10):
            P.car_wreck(rng.uniform(68, 120), rng.uniform(20.4, 22.6), rng.choice([0, 180]) + rng.uniform(-14, 14), rng)
        for k in range(3):
            P.car_wreck(rng.uniform(28.4, 30.6), rng.uniform(55, 88), 90 + rng.uniform(-10, 10), rng)
    LM.barricade_line(118.0, 20.2, 118.6, 22.8, rng)
    # wilderness: trees, rock outcrops, scrub everywhere outside the town
    with P.zone(prio=1):
        for k in range(110):
            x, y = rng.uniform(BOUNDS[0], BOUNDS[2]), rng.uniform(BOUNDS[1], BOUNDS[3])
            if -8 < x < 68 and -8 < y < 54: continue
            P.tree(x, y, 0, random.Random(k * 7 + 3), kind=rng.choice(["dead", "dead", "sparse", "scrub", "pine", "pine"]))
        for k in range(14):            # outcrops: a big rock with smaller ones round it
            x, y = rng.uniform(BOUNDS[0], BOUNDS[2]), rng.uniform(BOUNDS[1], BOUNDS[3])
            P.rock(x, y, 0, rng, size=rng.uniform(0.8, 1.3))
            for j in range(rng.randint(2, 5)):
                P.rock(x + rng.uniform(-1.8, 1.8), y + rng.uniform(-1.8, 1.8), 0, rng, size=rng.uniform(0.2, 0.5))
    P.scatter(68, -8, 122, 25, 3.0, "city", rng)
    P.scatter(-8, 54, 32, 94, 6, "city", rng)
    P.scatter(68, -8, 122, 94, 3.5, "suburb", rng)
    P.scatter(-8, 54, 68, 94, 3.0, "suburb", rng)
    P.scatter(68, -8, 122, 94, 1.3, "wild", rng)
    P.scatter(-8, 54, 68, 94, 1.3, "wild", rng)


def render_tiles(name, W, H, cols, rows, samples=24):
    import validate
    validate.run(name)
    if os.environ.get("DRY"):
        return
    sc = bpy.context.scene
    lights()
    cx, cy = (BOUNDS[0] + BOUNDS[2]) / 2, (BOUNDS[1] + BOUNDS[3]) / 2
    camera(cx, cy, W, H, 0.5)
    sc.cycles.samples = samples
    sc.render.use_border = True; sc.render.use_crop_to_border = True
    for j in range(rows):
        for i in range(cols):
            path = os.path.join(OUT, "%s_t%d%d.png" % (name, i, j))
            if os.path.exists(path):
                continue
            sc.render.border_min_x, sc.render.border_max_x = i / cols, (i + 1) / cols
            sc.render.border_min_y, sc.render.border_max_y = 1 - (j + 1) / rows, 1 - j / rows
            sc.render.filepath = path
            bpy.ops.render.render(write_still=True)
            print("tile", i, j, flush=True)
    full = Image.new("RGBA", (W, H))
    for j in range(rows):
        for i in range(cols):
            t = Image.open(os.path.join(OUT, "%s_t%d%d.png" % (name, i, j)))
            full.paste(t, (round(i * W / cols), round(j * H / rows)))
    full.save(os.path.join(OUT, name + "_raw.png"))
    fallout_grade(full).save(os.path.join(OUT, name + ".png"))
    print("scene", name, flush=True)


rng = random.Random(SEED)
M, roads, doors, blockers, lot_end = MS.build(rng)
hwy, d2, b2 = zones(M, rng)
MS.dress(M, roads, doors, blockers, rng, bounds=BOUNDS)
dress_zones(M, hwy, d2, b2 + blockers, rng)
c, r = [int(v) for v in TILES.split("x")]
W = int(((BOUNDS[2] - BOUNDS[0]) + (BOUNDS[3] - BOUNDS[1])) * 32) + 200
H = int(((BOUNDS[2] - BOUNDS[0]) + (BOUNDS[3] - BOUNDS[1])) * 16) + 360
render_tiles("world", W, H, c, r)
