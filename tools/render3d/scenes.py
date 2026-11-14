"""Look-test scenes built from the prop library:
  interiors : three cut-away houses with different layouts, each furnished from random room recipes
  city      : a downtown corner with heavy debris — dumpsters, trash, wrecks, barricades
  outskirts : natural terrain with varied trees, rocks and scrub, a ranch house, a shack and light debris
python3 scenes.py OUT [interiors|city|outskirts|all]"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import kit, props as P
from kit import house, outer_runs, wall_run, window, DIR, STOREY
import bpy
from PIL import Image
from post import fallout_grade

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r3d"
WHICH = sys.argv[2] if len(sys.argv) > 2 else "all"
os.makedirs(OUT, exist_ok=True)
CUT = 0.85


def render(name, cx, cy, W=1152, H=648, cz=0.5, samples=64):
    sc = bpy.context.scene
    lights()
    camera(cx, cy, W, H, cz)
    sc.cycles.samples = samples
    sc.render.filepath = os.path.join(OUT, name + "_raw.png")
    bpy.ops.render.render(write_still=True)
    fallout_grade(Image.open(sc.render.filepath)).save(os.path.join(OUT, name + ".png"))
    print("scene", name)


# ------------------------------------------------------------------ furnishing recipes
# Items are built facing +y. Along the north wall: rot 0. Along the west wall: rot -90 (faces +x).
ROOMS = {
    "living": {"north": [P.couch, P.bookshelf, P.lamp, P.radio], "west": [P.tv, P.armchair, P.bookshelf], "mid": [P.coffee_table, P.rug]},
    "kitchen": {"north": [P.counter, P.stove, P.fridge, P.counter], "west": [P.counter, P.fridge], "mid": [P.table]},
    "bedroom": {"north": [P.bed, P.dresser, P.lamp], "west": [P.wardrobe, P.dresser], "mid": [P.rug]},
    "bath": {"north": [P.bathtub, P.toilet], "west": [P.sink_stand], "mid": []},
    "office": {"north": [P.filing_cabinet, P.terminal, P.filing_cabinet, P.bookshelf], "west": [P.locker_row, P.filing_cabinet], "mid": [P.table]},
    "storage": {"north": [P.cardboard_boxes, P.crate, P.footlocker, P.cardboard_boxes], "west": [P.barrel, P.ammo_crate], "mid": [P.cardboard_boxes]},
    "squat": {"north": [P.mattress, P.junk_pile, P.cardboard_boxes], "west": [P.mattress], "mid": [P.campfire_pit]},
}
FOOT = {P.couch: 0.55, P.bookshelf: 0.35, P.lamp: 0.4, P.radio: 0.3, P.tv: 0.5, P.armchair: 0.65, P.counter: 0.6, P.stove: 0.6,
        P.fridge: 0.6, P.bed: 1.95, P.dresser: 0.45, P.wardrobe: 0.6, P.bathtub: 1.75, P.toilet: 0.55, P.sink_stand: 0.5,
        P.filing_cabinet: 0.6, P.terminal: 0.6, P.locker_row: 0.5, P.cardboard_boxes: 0.5, P.crate: 0.6, P.footlocker: 0.4,
        P.barrel: 0.6, P.ammo_crate: 0.4, P.mattress: 1.9, P.junk_pile: 1.0}
WIDTH = {P.couch: 1.6, P.bed: 1.4, P.bathtub: 0.85, P.counter: 1.2, P.locker_row: 1.4, P.bookshelf: 1.05, P.mattress: 0.95, P.junk_pile: 1.3,
         P.terminal: 1.05, P.dresser: 0.95, P.wardrobe: 0.95, P.tv: 0.95}


def furnish_room(x0, y0, x1, y1, kind, rng, door_cells=()):
    rec = ROOMS[kind]
    # along the north wall, left to right
    x = x0 + 0.25
    for fn in rec["north"]:
        w = WIDTH.get(fn, 0.75)
        if x + w > x1 - 0.2: break
        if rng.random() < 0.85:
            d = FOOT.get(fn, 0.5)
            fn(x + w / 2, y0 + 0.13 + d / 2, 0, random.Random(rng.random()))
        x += w + rng.uniform(0.05, 0.3)
    y = y0 + 1.3
    for fn in rec["west"]:
        w = WIDTH.get(fn, 0.75)
        if y + w > y1 - 0.2: break
        if rng.random() < 0.8:
            d = FOOT.get(fn, 0.5)
            fn(x0 + 0.13 + d / 2, y + w / 2, -90, random.Random(rng.random()))
        y += w + rng.uniform(0.05, 0.3)
    if (x1 - x0) >= 3 and (y1 - y0) >= 2.5:
        mx, my = (x0 + x1) / 2 + 0.3, (y0 + y1) / 2 + 0.3
        for fn in rec["mid"]:
            fn(mx, my, rng.uniform(-10, 10), random.Random(rng.random()))
            if fn == P.table:
                for (a, b, r) in ((-0.7, 0, -90), (0.7, 0, 90), (0, -0.55, 0)):
                    if rng.random() < 0.75:
                        P.chair(mx + a, my + b, r + rng.uniform(-20, 20), random.Random(rng.random()), style="wood")
    P.litter((x0 + x1) / 2, (y0 + y1) / 2, 0, rng, n=rng.randint(3, 9), r=min(x1 - x0, y1 - y0) * 0.4)


def cutaway_house(M, ox, oy, parts, rooms, wall_out, wall_in, floor_mat, rng, doors=()):
    """Interior view: north/west walls full height, south/east walls cut to knee-ish height."""
    cells = set()
    for (px, py, w, h) in parts:
        for y in range(py, py + h):
            for x in range(px, px + w):
                cells.add((ox + x, oy + y))
    for (a, b, side) in outer_runs(cells):
        full = side in ("n", "w")
        horiz = side in ("n", "s")
        L = abs(b[0] - a[0]) if horiz else abs(b[1] - a[1])
        lo = min(a[0], b[0]) if horiz else min(a[1], b[1])
        fixed = a[1] if horiz else a[0]
        openings = []
        for (ds, dfix, dpos) in doors:
            if ds == side and abs(dfix + (oy if horiz else ox) - fixed) < .01:
                t = dpos + (ox if horiz else oy) - lo
                if 0.5 < t < L - 0.5:
                    openings.append((t - 0.42, t + 0.42, 0.0, 1.6, "door"))
        t = 1.0
        while full and t < L - 0.6:
            if all(abs(t - o[0] - 0.42) > 1.0 for o in openings) and rng.random() < 0.7:
                openings.append((t - 0.38, t + 0.38, 0.85, 1.65, "win"))
            t += rng.uniform(1.5, 2.2)
        wm = wall_in if full else (wall_out if not isinstance(wall_out, dict) else wall_out[horiz])
        wall_run(M, a, b, STOREY if full else CUT, wm, openings, cap=True, frames=full)
        if full:
            for (t0, t1, z0, z1, k) in openings:
                if k == "win":
                    window(M, a, b, t0, t1, z0, z1, DIR[side], rng.choice(["glass", "broken", "boarded"]))
    for (x, y) in cells:
        box(x, y, 0, x + 1, y + 1, 0.03, floor_mat)
    # room dividers between parts, with a doorway
    for i, (px, py, w, h) in enumerate(parts):
        for (qx, qy, qw, qh) in parts[i + 1:]:
            if px + w == qx and not (qy >= py + h or qy + qh <= py):
                y0, y1 = max(py, qy), min(py + h, qy + qh)
                wall_run(M, (ox + qx, oy + y0), (ox + qx, oy + y1), STOREY, wall_in, [((y1 - y0) / 2 - 0.42, (y1 - y0) / 2 + 0.42, 0, 1.6, "door")])
            if py + h == qy and not (qx >= px + w or qx + qw <= px):
                x0, x1 = max(px, qx), min(px + w, qx + qw)
                wall_run(M, (ox + x0, oy + qy), (ox + x1, oy + qy), STOREY, wall_in, [((x1 - x0) / 2 - 0.42, (x1 - x0) / 2 + 0.42, 0, 1.6, "door")])
    for (px, py, w, h), kind in zip(parts, rooms):
        furnish_room(ox + px, oy + py, ox + px + w, oy + py + h, kind, rng)


def scene_interiors():
    reset()
    P._MC.clear()
    M = kit.materials()
    rng = random.Random(21)
    kit.terrain(-16, -14, 40, 30, kit.mat_terrain(), amp=0.1, flat=[(-1, -1, 26, 16)])
    planks = [kit.mat_planks("pl1", '#5a4030', '#4a3424'), kit.mat_planks("pl2", '#7a5a3a', '#6a4a2e')]
    checker = kit.mat_flat("lino", '#a8b8a0', 0.6)
    # 1: L-shaped bungalow — living + kitchen + bedroom
    cutaway_house(M, 0, 0, [(0, 0, 5, 4), (5, 0, 3, 4), (0, 4, 3, 3)], ["living", "kitchen", "bedroom"],
                  M["siding_seafoam"], kit.mat_stucco("in1", '#a89a80', '#6a5e4a'), planks[0], rng, doors=[("s", 4, 1.5), ("e", 8, 2.5)])
    # 2: T-shaped office / storage block
    cutaway_house(M, 10, -1, [(0, 0, 6, 3), (1, 3, 4, 3)], ["office", "storage"],
                  {True: M["brick"], False: M["brick_y"]}, kit.mat_stucco("in2", '#9a9282', '#5e584e'), planks[1], rng, doors=[("s", 6, 3.0)])
    # 3: small house turned squat: bedroom + bath, half-collapsed
    cutaway_house(M, 18, 2, [(0, 0, 4, 3), (4, 0, 2, 3), (0, 3, 3, 3)], ["squat", "bath", "bedroom"],
                  M["siding_salmon"], kit.mat_stucco("in3", '#b0a48a', '#76684e'), planks[0], rng, doors=[("s", 6, 1.5)])
    P.rubble_pile(23.5, 7.2, 0, rng, size=1.0)
    P.trash_bags(8.8, 7.5, 0, rng)
    P.barrel(17, 6.5, 0, rng)
    P.car_wreck(13, 10.5, 15, rng, style="sedan")
    P.scatter(-6, 7.5, 30, 18, 6, "suburb", rng)
    P.scatter(-6, -6, 30, -1.2, 5, "suburb", rng)
    render("scene_interiors", 12.5, 5.0)


def scene_city():
    reset()
    P._MC.clear()
    M = kit.materials()
    rng = random.Random(5)
    asphalt, conc = M["asphalt"], M["conc"]
    box(-20, -20, -0.1, 40, 40, 0.0, M["dirt"])
    box(-20, 8.0, 0.0, 40, 11.0, 0.006, asphalt)          # east-west street
    box(13.0, -20, 0.0062, 16.0, 40, 0.0066, asphalt)     # north-south street (thin, sits on top: no overlap)
    for (a, b, c, d) in ((-20, 7.2, 13.0, 8.0), (16.0, 7.2, 40, 8.0), (-20, 11.0, 13.0, 11.8), (16.0, 11.0, 40, 11.8),
                         (12.2, -20, 13.0, 7.2), (16.0, -20, 16.8, 7.2), (12.2, 11.8, 13.0, 40), (16.0, 11.8, 16.8, 40)):
        box(a, b, 0.0, c, d, 0.07, conc, bevel=0.02)
    box(-20, -20, 0.0, 12.2, 7.2, 0.01, kit.mat_concrete("lot", '#6e6a60'))   # concrete lots
    box(16.8, -20, 0.0, 40, 7.2, 0.01, kit.mat_concrete("lot2", '#6e6a60'))
    # closed buildings: brick shop with flat roof, two-storey office, burned-out store
    house(M, 2, 0, [(0, 0, 8, 5, 2)], {True: M["brick"], False: M["brick_y"]}, "flat", door=("s", 5, 3.0, "locked"), win_state="boarded")
    house(M, 18, 0, [(0, 0, 5, 5, 1), (5, 0, 3, 3, 1)], M["stucco"], "flat", door=("s", 5, 2.0, "boarded"), win_state="broken")
    house(M, 2, 13, [(0, 0, 6, 4, 1)], M["stucco"], "flat", door=("e", 6, 2.0, "broken"), ruined=False, win_state="broken")
    # alley clutter between the shop and the road
    P.dumpster(10.9, 3.0, 90, rng, lid="open")
    P.dumpster(10.9, 5.2, 90, rng, lid="half")
    P.trash_bags(11.3, 6.4, 0, rng, n=6)
    P.trash_can(1.2, 6.5, 0, rng); P.trash_can(1.6, 6.8, 0, rng, tipped=True)
    P.cardboard_boxes(11.5, 1.2, 0, rng); P.pallet(10.8, 0.4, 20, rng)
    P.litter(6, 7.5, 0, rng, n=18, r=3.5); P.litter(20, 7.6, 0, rng, n=14, r=3.0); P.litter(14.5, 9.5, 0, rng, n=20, r=3)
    P.litter(14.5, 2.0, 0, rng, n=10, r=2); P.litter(5, 12.2, 0, rng, n=12, r=3)
    # street furniture
    P.lamp_post(12.5, 7.4, 0, rng); P.lamp_post(16.4, 11.4, 180, rng)
    P.traffic_light(16.4, 7.4, 0, rng, fallen=False); P.traffic_light(12.6, 12.4, 0, rng, fallen=True)
    P.hydrant(8.5, 7.6, 0, rng); P.newsbox(4.0, 7.6, 0, rng); P.phone_booth(17.6, 7.6 - 0.6, 0, rng)
    P.parking_meter(6.5, 7.5, 0, rng); P.parking_meter(9.5, 7.5, 0, rng)
    P.bench(23, 7.6, 0, rng); P.street_sign(12.6, 6.8, 0, rng); P.mailbox(19.5, 11.5, 0, rng)
    # wrecks and roadblock
    P.car_wreck(5.5, 9.3, 8, rng, style="sedan"); P.car_wreck(14.4, 4.0, 95, rng, style="burned")
    P.car_wreck(21.5, 9.7, 175, rng, style="truck"); P.car_wreck(14.8, 15.5, 80, rng, style="sedan")
    P.jersey(10.0, 10.2, 70, rng); P.barricade(18.5, 10.3, 0, rng); P.sandbags(13.6, 12.6, 0, rng)
    P.shopping_cart(9.0, 12.4, 30, rng); P.skeleton(16.9, 13.2, 40, rng)
    P.rubble_pile(9.5, 14.5, 0, rng, size=1.3); P.rubble_pile(24.5, 4.0, 0, rng, size=0.9)
    P.tire_stack(17.6, 3.2, 0, rng); P.barrel(17.3, 1.5, 0, rng, kind="toxic"); P.barrel(17.9, 1.8, 0, rng)
    P.chainlink(17.0, 12.6, 0, rng, n=3)
    P.roof_clutter(6, 2.5, 0, rng, z=4.05); P.roof_clutter(21, 2.0, 0, rng, z=2.05); P.roof_clutter(5, 15, 0, rng, z=2.05)
    houses = [(1.8, -0.2, 10.2, 5.2), (17.8, -0.2, 26.2, 5.2), (1.8, 12.8, 8.2, 17.2)]
    # heavy downtown debris: on lots, sidewalks and in the street
    P.scatter(-4, -4, 12.2, 7.2, 9, "city", rng, avoid=houses + [(10.0, 1.8, 12.0, 6.0)])
    P.scatter(16.8, -4, 30, 7.2, 8, "city", rng, avoid=houses)
    P.scatter(-4, 7.2, 30, 11.8, 4, "city", rng)
    P.scatter(-4, 11.8, 12.2, 20, 8, "city", rng, avoid=houses)
    P.scatter(16.8, 11.8, 30, 20, 6, "city", rng, avoid=[(16.8, 12.4, 20.5, 12.8)])
    P.scatter(13.0, -4, 16.0, 20, 4, "city", rng)
    render("scene_city", 13.0, 8.0)


def scene_outskirts():
    reset()
    P._MC.clear()
    M = kit.materials()
    rng = random.Random(9)
    kit.terrain(-12, -12, 36, 30, kit.mat_terrain(), amp=0.35, scale=0.45, flat=[(1, 1, 8, 6), (15, 2, 19, 5), (-12, 8.0, 36, 9.6)])
    dirt_road = kit.mat_ground("track", '#6e5e48', '#5a4c3a', '#7e6e56')
    box(-12, 8.0, -0.03, 36, 9.6, 0.005, dirt_road)
    house(M, 1, 1, [(0, 0, 5, 3, 1), (0, 3, 2, 2, 1)], M["siding_cream"], "gable", "sh_brown",
          door=("s", 3, 3.5, "closed"), shutters=M["frame"], chimney=(1.0, 0.6), porch=(2.0, 3.0, 5.0, 4.0))
    house(M, 15, 2, [(0, 0, 3, 2, 1)], {True: M["tin"], False: M["tin_y"]}, "shed", door=("e", 3, 1.0, "locked"))
    P.wood_fence(0.5, 6.6, 0, rng, n=6)
    P.mailbox(6.8, 7.6, 0, rng); P.car_wreck(9.5, 6.5, 30, rng, style="truck")
    P.campfire_pit(19.6, 6.0, 0, rng); P.lean_to(21.5, 5.2, 0, rng); P.junk_pile(13.6, 5.5, 0, rng)
    P.water_tank(19.5, 1.2, 0, rng); P.barrel(14.6, 1.6, 0, rng)
    trees = [(-2, 2, "dead"), (8.5, 1.5, "sparse"), (11, 3, "dead"), (-1, 11, "sparse"), (4, 12, "dead"), (9, 12.5, "scrub"),
             (13, 11, "dead"), (17, 13, "sparse"), (21, 11, "dead"), (24, 3, "dead"), (-4, 6, "scrub"), (6, -1.5, "dead")]
    for (x, y, k) in trees:
        P.tree(x, y, 0, random.Random(x * 31 + y), kind=k)
    P.joshua_tree(23, 14, 0, rng); P.joshua_tree(1.5, 14.5, 0, rng); P.cactus(26, 8, 0, rng)
    for k in range(14):
        P.rock(rng.uniform(-6, 28), rng.uniform(-4, 18), 0, rng)
    for k in range(16):
        x, y = rng.uniform(-6, 28), rng.uniform(-4, 18)
        if 0.5 < x < 8.5 and 0.5 < y < 6.5: continue
        rng.choice([P.shrub, P.deadbush, P.deadbush])(x, y, 0, rng)
    P.scatter(-8, -6, 30, 20, 5, "wild", rng, avoid=[(0.5, 0.5, 8.5, 6.8), (14.5, 1.5, 18.5, 4.5), (-12, 8.0, 36, 9.6)])
    P.scatter(-8, 7.6, 30, 10.0, 3, "suburb", rng)
    for k in range(3):
        P.tumbleweed(rng.uniform(0, 25), rng.uniform(9.8, 14), 0, rng)
    P.pebbles(10, 9, 0, rng, n=12, r=2); P.skeleton(25, 9.8, 120, rng); P.tire_stack(12.5, 7.4, 0, rng, n=1)
    render("scene_outskirts", 11.0, 7.0)


if WHICH in ("all", "interiors"):
    scene_interiors()
if WHICH in ("all", "city"):
    scene_city()
if WHICH in ("all", "outskirts"):
    scene_outskirts()
