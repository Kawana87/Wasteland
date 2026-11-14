"""Whole-town test map: downtown, a mall, a park and church, suburbs, ruins and wilderness, all from the
builders + scatter + validator, rendered big so it can be inspected tile by tile.
python3 map_scene.py OUT [seed]"""
import sys, os, math, random
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r3d"
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 5
sys.argv = [sys.argv[0], OUT, "none"]          # import scenes without running its scenes
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import kit, props as P, landmarks as LM, scenes as S
from kit import house, STOREY
import bpy
from PIL import Image
from post import fallout_grade

os.makedirs(OUT, exist_ok=True)


def build(rng):
    reset()
    P._MC.clear(); kit._FP.clear(); kit.SOLIDS.clear(); kit.PAVED.clear()
    M = kit.materials()
    LM.GRAF_DIR = os.path.join(OUT, "graf"); os.makedirs(LM.GRAF_DIR, exist_ok=True)
    main = (-6, 20.0, 66, 23.0)          # east-west main street
    avenue = (28.0, -6, 31.0, 54)        # north-south avenue
    lane = (31.0, 36.0, 60.0, 38.5)      # suburb lane, dead end to the east
    roads = [main, avenue, lane]
    asphalt, conc = M["asphalt"], M["conc"]
    # ---- downtown (north-west): storefronts on main street, jail and a bombed block behind
    for (a, b, c, d) in ((-6, 19.2, 28.0, 20.0), (31.0, 19.2, 66, 20.0), (-6, 23.0, 28.0, 23.8), (27.2, -6, 28.0, 19.2), (31.0, -6, 31.8, 19.2)):
        box(a, b, 0.0, c, d, 0.07, conc, bevel=0.02); kit.PAVED.append((a, b, c, d))
    kit.PAVED.extend([main, avenue])
    LM.storefront_row(M, 1.0, 14.2, 6, rng)
    LM.jail(M, 2.0, 3.0, rng)
    LM.ruin_building(M, 19.0, 5.0, 5, 4, rng, "bombed", '#8a4434')
    house(M, 19, 11, [(0, 0, 6, 2, 2)], kit.mat_stucco("ofc", '#b0a48c', '#7a6e5a'), "flat", door=("s", 2, 3.0, "locked"), win_state="broken")
    # ---- north-east: mall + lot, clinic on the corner
    lot_end = LM.mall(M, 36.0, 1.0, rng, lot_rows=1)
    LM.clinic(M, 52.0, 12.6, rng)
    # ---- south-west: park, church, a burnt house, two homes on a dirt trail
    LM.park(M, 2.0, 25.0, 10.0, 7.0, rng)
    LM.church(M, 15.0, 25.0, rng)
    LM.ruin_building(M, 20.5, 34.0, 4, 3, rng, "burnt", '#c88c74')
    doors, blockers = [], []
    for (x, y) in ((3.0, 37.0), (10.0, 39.0)):
        out, bb = S.ranch(M, x, y, rng, "s" if rng.random() < 0.5 else "e"); doors.append(out); blockers.append(bb)
    # ---- south-east: suburb along the lane
    for (x, y, side) in ((33.0, 31.0, "s"), (40.0, 30.5, "s"), (47.5, 31.0, "s"), (34.5, 40.5, "e"), (43.0, 41.0, "e")):
        out, bb = S.ranch(M, x, y, rng, side); doors.append(out); blockers.append(bb)
    return M, roads, doors, blockers, lot_end


def dress(M, roads, doors, blockers, rng):
    main, avenue, lane = roads
    flats = [(s[0] - 0.8, s[1] - 0.8, s[2] + 0.8, s[3] + 0.8) for s in kit.SOLIDS] + [
        (-6, 19.2, 66, 23.8), (27.2, -6, 31.8, 54), (35, 8, 51, 13.5), (2, 25, 12, 32)]
    kit.terrain(-8, -8, 68, 56, kit.mat_terrain(), amp=0.22, scale=0.45, res=2, flat=flats + [lane])
    box(main[0], main[1], 0.0, main[2], main[3], 0.006, M["asphalt"])
    box(avenue[0], avenue[1], 0.0062, avenue[2], avenue[3], 0.0066, M["asphalt"])
    kit.road(*lane, ends=(False, True), z=0.0095)
    for k in range(-6, 66, 6):
        if not (26 < k < 32):
            box(k, 21.47, 0.006, k + 2.5, 21.53, 0.0075, P.MAT("flat:#a89a6a:0.8"))
    # footpaths from every house door to the nearest road edge
    for out in doors:
        if out[0] < 27:          # south-west homes: trail up to main street
            goal = (out[0] + rng.uniform(-1, 1), 23.9)
        else:
            goal = (out[0] + rng.uniform(-1, 1), lane[1] - 0.1 if out[1] < lane[1] else lane[3] + 0.1)
        kit.footpath(kit.plan_path(out, goal, blockers, rng), 0.55, seed=rng.randint(0, 999))
    kit.footpath(kit.plan_path((60.5, 37.2), (63, 46), blockers, rng), 0.55, seed=3)
    # street furniture + wrecks
    for x in (-3, 3, 9, 15, 21, 34, 40, 46, 52, 58):
        P.lamp_post(x, 19.6, 0, rng)
    P.traffic_light(27.6, 19.6, 0, rng); P.traffic_light(31.4, 23.4, 180, rng, fallen=True)
    P.phone_booth(25.5, 19.5, 0, rng); P.hydrant(12.0, 19.5, 0, rng); P.newsbox(6.5, 19.5, 0, rng); P.bench(18, 23.5, 180, rng)
    P.mailbox(37.5, 35.6, 0, rng); P.mailbox(44.0, 35.6, 0, rng); P.mailbox(50.5, 35.6, 0, rng)
    with P.zone(prio=1):
        for k in range(7):
            P.car_wreck(rng.uniform(-4, 64), rng.uniform(20.4, 22.6), rng.choice([0, 180]) + rng.uniform(-10, 10), rng)
        for k in range(3):
            P.car_wreck(rng.uniform(28.4, 30.6), rng.uniform(-4, 52), 90 + rng.uniform(-10, 10), rng)
        P.car_wreck(38.0, 37.2, 175, rng, style="burned")
    LM.barricade_line(28.2, 17.5, 30.8, 17.0, rng)
    LM.random_barricades(-6, -6, 66, 54, 2, rng, roads=[main, avenue])
    P.sandbags(26.5, 24.0, 45, rng); P.dumpster(0.0, 13.6, 0, rng, lid="open"); P.dumpster(26.2, 12.2, 90, rng)
    # raider camp past the dead end
    P.campfire_pit(63.0, 46.5, 0, rng); P.lean_to(64.6, 45.5, 0, rng); P.junk_pile(61.6, 47.4, 0, rng)
    # trees, debris
    with P.zone(prio=1):
        for k in range(40):
            P.tree(rng.uniform(-8, 68), rng.uniform(-8, 56), 0, random.Random(k * 13 + 1), kind=rng.choice(["dead", "dead", "sparse", "scrub", "pine"]))
    P.scatter(-6, 13, 28, 24.5, 6, "city", rng)
    P.scatter(-6, -6, 28, 13, 4, "city", rng)
    P.scatter(31, -6, 66, 24.5, 3.5, "city", rng)
    P.scatter(-8, 24, 28, 56, 4, "suburb", rng)
    P.scatter(31, 24, 68, 56, 4, "suburb", rng)
    P.scatter(-8, -8, 68, 56, 1.2, "wild", rng)


def render(name, cx, cy, W, H, samples=36):
    import validate
    validate.run(name)
    if os.environ.get("DRY"):
        return
    sc = bpy.context.scene
    lights()
    camera(cx, cy, W, H, 0.5)
    sc.cycles.samples = samples
    sc.render.filepath = os.path.join(OUT, name + "_raw.png")
    bpy.ops.render.render(write_still=True)
    fallout_grade(Image.open(sc.render.filepath)).save(os.path.join(OUT, name + ".png"))
    print("scene", name)


rng = random.Random(SEED)
M, roads, doors, blockers, lot_end = build(rng)
dress(M, roads, doors, blockers, rng)
if os.environ.get("CROP"):
    cx, cy, w, h = [float(v) for v in os.environ["CROP"].split(",")]
    render("town_crop", cx, cy, int(w), int(h))
else:
    render("town_map", 30.0, 24.0, 3600, 2000)
