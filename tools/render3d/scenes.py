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
    import validate
    validate.run(name)
    if os.environ.get("DRY"):
        return
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
    "living": {"north": [P.couch, P.side_table, P.bookshelf, P.lamp, P.radio], "west": [P.tv, P.armchair, P.bookshelf], "mid": [P.coffee_table, P.rug]},
    "kitchen": {"north": [P.counter, P.stove, P.fridge, P.counter], "west": [P.pantry_shelf, P.counter], "mid": [P.table]},
    "bedroom": {"north": [P.bed, P.nightstand, P.dresser], "west": [P.wardrobe, P.coat_rack, P.dresser], "mid": [P.rug]},
    "bath": {"north": [P.bathtub, P.toilet], "west": [P.sink_stand], "mid": []},
    "office": {"north": [P.filing_cabinet, P.terminal, P.filing_cabinet, P.bookshelf], "west": [P.locker_row, P.filing_cabinet], "mid": [P.table]},
    "storage": {"north": [P.cardboard_boxes, P.crate, P.footlocker, P.cardboard_boxes], "west": [P.barrel, P.ammo_crate], "mid": [P.cardboard_boxes]},
    "squat": {"north": [P.mattress, P.junk_pile, P.cardboard_boxes], "west": [P.mattress], "mid": [P.campfire_pit]},
    # small rooms: things that fit against one wall and leave the floor free
    "pantry": {"north": [P.pantry_shelf, P.pantry_shelf], "west": [P.crate, P.barrel], "mid": []},
    "closet": {"north": [P.coat_rack, P.cardboard_boxes], "west": [P.footlocker], "mid": []},
    "washroom": {"north": [P.toilet, P.sink_stand], "west": [], "mid": []},
}
SMALL = ["pantry", "closet", "washroom", "storage"]
# footprint: (width along the wall, depth out from the wall, tall?)
DIM = {P.couch: (1.6, 0.55, False), P.side_table: (0.5, 0.5, False), P.bookshelf: (1.05, 0.35, True), P.lamp: (0.4, 0.4, True),
       P.radio: (0.45, 0.3, False), P.tv: (0.95, 0.5, False), P.armchair: (0.7, 0.65, False), P.counter: (1.2, 0.6, False),
       P.stove: (0.6, 0.6, False), P.fridge: (0.62, 0.62, True), P.pantry_shelf: (0.85, 0.35, True), P.bed: (1.4, 1.95, False),
       P.nightstand: (0.45, 0.4, False), P.dresser: (0.95, 0.45, False), P.wardrobe: (0.95, 0.6, True), P.coat_rack: (0.4, 0.4, True),
       P.bathtub: (0.85, 1.75, False), P.toilet: (0.5, 0.55, False), P.sink_stand: (0.55, 0.5, True), P.filing_cabinet: (0.48, 0.62, True),
       P.terminal: (1.05, 0.62, False), P.locker_row: (1.3, 0.5, True), P.cardboard_boxes: (0.5, 0.5, False), P.crate: (0.65, 0.65, False),
       P.footlocker: (0.75, 0.42, False), P.barrel: (0.6, 0.6, False), P.ammo_crate: (0.7, 0.42, False), P.mattress: (0.95, 1.9, False),
       P.junk_pile: (1.3, 1.0, False)}


FIXED = {P.couch: {"w": 1.5}, P.bookshelf: {"w": 1.0}, P.counter: {"w": 1.2}, P.locker_row: {"n": 3}, P.bed: {"size": 1.4}}


def _hit(r, rects):
    return any(r[0] < q[2] and q[0] < r[2] and r[1] < q[3] and q[1] < r[3] for q in rects)


def furnish_room(*a, **k):
    with P.zone("int"):
        return _furnish_room(*a, **k)


def _furnish_room(x0, y0, x1, y1, kind, rng, keepout=(), windows=()):
    """Places items along the north and west walls, never in front of a doorway, nothing tall in front
    of a window, and leaves floor space: how full a room gets varies per room."""
    w, h = x1 - x0, y1 - y0
    if min(w, h) <= 2 and w * h <= 6 and kind not in SMALL:
        kind = rng.choice(["pantry", "closet", "washroom", "storage"])
    rec = ROOMS[kind]
    fill = rng.uniform(0.45, 0.9)
    budget = max(1 if kind in SMALL else 3, int(round(w * h * 0.45 * fill)))
    placed = []
    def try_place(fn, wall, pos):
        nonlocal budget
        if budget <= 0:
            return False
        ww, dd, tall = DIM.get(fn, (0.75, 0.5, False))
        if wall == "n":
            r = (pos - ww / 2, y0 + 0.12, pos + ww / 2, y0 + 0.12 + dd)
        else:
            r = (x0 + 0.12, pos - ww / 2, x0 + 0.12 + dd, pos + ww / 2)
        if r[0] < x0 + 0.1 or r[2] > x1 - 0.1 or r[1] < y0 + 0.1 or r[3] > y1 - 0.1:
            return False
        if _hit(r, keepout) or _hit(r, placed) or (tall and _hit(r, windows)):
            return False
        cx, cy = (r[0] + r[2]) / 2, (r[1] + r[3]) / 2
        fn(cx, cy, 0 if wall == "n" else -90, random.Random(rng.random()), **FIXED.get(fn, {}))
        placed.append(r)
        budget -= 1
        return True
    for wall, items, lo, hi in (("n", rec["north"], x0, x1), ("w", rec["west"], y0 + 0.8, y1)):
        pos = lo + 0.2
        for fn in items:
            if rng.random() > 0.55 + fill * 0.45:
                continue
            ww = DIM.get(fn, (0.75, 0.5, False))[0]
            for shift in (0.0, 0.3, 0.6, 1.0):        # slide along the wall to dodge doors and windows
                if try_place(fn, wall, pos + ww / 2 + shift):
                    pos += ww + shift + rng.uniform(0.05, 0.25)
                    break
    if w >= 3 and h >= 3 and budget > 0:
        mx, my = (x0 + x1) / 2 + 0.3, (y0 + y1) / 2 + 0.3
        for fn in rec["mid"]:
            r = (mx - 0.6, my - 0.5, mx + 0.6, my + 0.5)
            if _hit(r, keepout) or _hit(r, placed):
                continue
            fn(mx, my, rng.uniform(-10, 10), random.Random(rng.random()))
            placed.append(r)
            if fn == P.table:
                for (a, b, rr) in ((-0.7, 0, -90), (0.7, 0, 90), (0, -0.55, 0)):
                    if rng.random() < 0.7:
                        P.chair(mx + a, my + b, rr + rng.uniform(-20, 20), random.Random(rng.random()), style="wood")
    P.litter((x0 + x1) / 2, (y0 + y1) / 2, 0, rng, n=rng.randint(1, 5), r=min(w, h) * 0.35)


def cutaway_house(M, ox, oy, parts, rooms, wall_out, wall_in, floor_mat, rng, doors=()):
    """Interior view: north/west walls full height, south/east walls cut to knee-ish height."""
    keep, wins = [], []
    def door_zone(axis_h, fixed, center, inside_sign_both=True):
        if axis_h:
            keep.append((center - 0.65, fixed - 1.1, center + 0.65, fixed + 1.1))
        else:
            keep.append((fixed - 1.1, center - 0.65, fixed + 1.1, center + 0.65))
    cells = set()
    for (px, py, w, h) in parts:
        for y in range(py, py + h):
            for x in range(px, px + w):
                cells.add((ox + x, oy + y))
    runs = outer_runs(cells)
    # divider walls between parts (computed first so windows can avoid them)
    dividers = []
    for i, (px, py, w, h) in enumerate(parts):
        for (qx, qy, qw, qh) in parts[i + 1:]:
            if px + w == qx and not (qy >= py + h or qy + qh <= py):
                y0, y1 = max(py, qy), min(py + h, qy + qh)
                dividers.append(((ox + qx, oy + y0), (ox + qx, oy + y1), False))
            if py + h == qy and not (qx >= px + w or qx + qw <= px):
                x0, x1 = max(px, qx), min(px + w, qx + qw)
                dividers.append(((ox + x0, oy + qy), (ox + x1, oy + qy), True))
    juncs = [p for (a, b, sd) in runs for p in (a, b)] + [p for (a, b, h) in dividers for p in (a, b)]
    for (a, b, side) in runs:
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
                    door_zone(horiz, fixed, lo + t)
        t = 1.0
        while full and t < L - 0.6:
            if all(abs(t - o[0] - 0.42) > 1.0 for o in openings) and kit.window_ok(a, b, t, juncs) and rng.random() < 0.8:
                openings.append((t - 0.38, t + 0.38, 0.85, 1.65, "win"))
            t += rng.uniform(1.5, 2.2)
        wm = wall_in if full else (wall_out if not isinstance(wall_out, dict) else wall_out[horiz])
        wall_run(M, a, b, STOREY if full else CUT, wm, openings, cap=True, frames=full)
        for (t0, t1, z0, z1, k) in openings:
            if k == "win":
                if horiz: wins.append((lo + t0 - 0.1, fixed - 0.8, lo + t1 + 0.1, fixed + 0.8))
                else: wins.append((fixed - 0.8, lo + t0 - 0.1, fixed + 0.8, lo + t1 + 0.1))
        if full:
            for (t0, t1, z0, z1, k) in openings:
                if k == "win":
                    window(M, a, b, t0, t1, z0, z1, DIR[side], rng.choice(["glass", "broken", "boarded"]))
    for (x, y) in cells:
        box(x, y, 0, x + 1, y + 1, 0.03, floor_mat)
    # room dividers between parts, with a doorway
    for (a, b, horiz) in dividers:
        L = abs(b[0] - a[0]) if horiz else abs(b[1] - a[1])
        wall_run(M, a, b, STOREY, wall_in, [(L / 2 - 0.42, L / 2 + 0.42, 0, 1.6, "door")])
        if horiz:
            door_zone(True, a[1], (a[0] + b[0]) / 2)
        else:
            door_zone(False, a[0], (a[1] + b[1]) / 2)
    for (px, py, w, h), kind in zip(parts, rooms):
        furnish_room(ox + px, oy + py, ox + px + w, oy + py + h, kind, rng, keep, wins)


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
    P.roof_units(2, 0, 10, 5, 4.05, rng); P.roof_units(18, 0, 26, 5, 2.05, rng); P.roof_units(2, 13, 8, 17, 2.05, rng)
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


# ------------------------------------------------------------------ suburb: roads fading into dirt + footpaths
SIDING = ["siding_seafoam", "siding_cream", "siding_salmon", "siding_blue", "siding_mint"]


def ranch(M, ox, oy, rng, door_side="s"):
    fp = rng.choice([[(0, 0, 4, 3, 1)], [(0, 0, 5, 3, 1), (0, 3, 2, 2, 1)], [(0, 0, 5, 3, 1), (3, 3, 2, 2, 1)], [(0, 0, 4, 2, 1), (1, 2, 2, 2, 1)]])
    w = max(p[0] + p[2] for p in fp); h = max(p[1] + p[3] for p in fp)
    main = fp[0]
    if door_side == "s":
        # door on the main part's south edge, where nothing is attached
        free = [t + 0.5 for t in range(main[0], main[0] + main[2]) if not any(q is not main and q[0] <= t < q[0] + q[2] and q[1] == main[1] + main[3] for q in fp)]
        dx = rng.choice(free) if free else main[0] + 1.5
        door = ("s", main[1] + main[3], dx, rng.choice(["open", "closed", "locked"]))
        out = (ox + dx, oy + main[1] + main[3] + 0.4)
    else:
        dy = main[1] + main[3] / 2
        door = ("e", main[0] + main[2], dy, rng.choice(["open", "closed", "locked"]))
        out = (ox + main[0] + main[2] + 0.4, oy + dy)
    house(M, ox, oy, fp, M[rng.choice(SIDING)], rng.choice(["gable", "gable", "hip"]), rng.choice(["sh_brown", "sh_slate", "sh_red", "sh_green"]),
          door=door, shutters=rng.choice([None, M["frame"], M["trim"]]), chimney=(rng.uniform(0.5, w - 0.5), 0.5) if rng.random() < 0.5 else None,
          win_state=rng.choice(["glass", "broken", "boarded"]))
    return out, (ox - 0.2, oy - 0.2, ox + w + 0.2, oy + h + 0.2)


def scene_suburb():
    reset()
    P._MC.clear(); kit._FP.clear(); kit.SOLIDS.clear()
    M = kit.materials()
    rng = random.Random(31)
    main_road = (-14, 8.0, 22, 10.4)           # runs east and crumbles into the dirt (dead end)
    side_road = (4.0, -12, 6.2, 8.0)          # joins from the north
    kit.terrain(-16, -14, 40, 28, kit.mat_terrain(), amp=0.25, scale=0.5, flat=[main_road, side_road])
    kit.road(*main_road, ends=(False, True))
    kit.road(*side_road, ends=(False, False), z=0.0095)
    lots = [(-8, 2.5, "s"), (-1, 1.5, "s"), (8.5, 2.0, "s"), (14, 2.5, "s"), (-6, 12.5, "n"), (10, 13.0, "n")]
    blockers, doors = [], []
    for (x, y, side) in lots:
        if side == "s":
            out, bb = ranch(M, x, y, rng, "s")
        else:
            out, bb = ranch(M, x, y, rng, "e")
        blockers.append(bb); doors.append((out, side))
    # footpaths: every door to the nearest road edge, a short-cut between neighbours, a trail into the wild
    for (out, side) in doors:
        gy = main_road[1] - 0.1 if out[1] < main_road[1] else main_road[3] + 0.1
        goal = (out[0] + rng.uniform(-1.0, 1.0), gy)
        kit.footpath(kit.plan_path(out, goal, blockers, rng), 0.55, seed=rng.randint(0, 999))
    kit.footpath(kit.plan_path(doors[1][0], (doors[2][0][0], doors[2][0][1] + 0.5), blockers, rng), 0.5, seed=5)
    kit.footpath(kit.plan_path((22.5, 9.2), (30, 3.5), blockers, rng), 0.55, seed=6)     # beyond the dead end, a trail to a camp
    P.campfire_pit(30.5, 3.0, 0, rng); P.lean_to(32.0, 2.0, 0, rng); P.junk_pile(29.0, 2.0, 0, rng)
    import landmarks as LM
    LM.ruin_building(M, 19.5, 12.5, 4, 3, rng, "burnt", '#c88c74')
    P.car_wreck(-3.5, 9.4, 172, rng, style="sedan"); P.car_wreck(17.5, 9.0, 14, rng, style="burned")
    P.mailbox(-6.5, 7.6, 0, rng); P.mailbox(1.5, 7.6, 0, rng); P.mailbox(11, 7.6, 0, rng)
    P.wood_fence(-9.0, 7.2, 0, rng, n=4); P.chainlink(13, 7.4, 0, rng, n=3, wire=False)
    for k in range(9):
        P.tree(rng.uniform(-14, 34), rng.uniform(-10, 20), 0, random.Random(k * 11), kind=rng.choice(["dead", "dead", "sparse"]))
    P.scatter(-14, -10, 34, 22, 4, "suburb", rng, avoid=blockers + [main_road, side_road])
    render("scene_suburb_roads_paths", 8.0, 6.5, W=1280, H=720)


def scene_city2():
    reset()
    P._MC.clear(); kit._FP.clear(); kit.SOLIDS.clear()
    M = kit.materials()
    import landmarks as LM
    LM.GRAF_DIR = os.path.join(OUT, "graf"); os.makedirs(LM.GRAF_DIR, exist_ok=True)
    rng = random.Random(12)
    asphalt, conc = M["asphalt"], M["conc"]
    box(-25, -25, -0.1, 50, 50, 0.0, M["dirt"])
    main = (-25, 9.0, 50, 12.0)        # east-west main street
    cross = (16.0, -25, 19.0, 50)      # north-south avenue
    box(main[0], main[1], 0.0, main[2], main[3], 0.006, asphalt)
    box(cross[0], cross[1], 0.0062, cross[2], cross[3], 0.0066, asphalt)
    for (a, b, c, d) in ((-25, 8.2, 16.0, 9.0), (19.0, 8.2, 50, 9.0), (-25, 12.0, 16.0, 12.8), (19.0, 12.0, 50, 12.8),
                         (15.2, -25, 16.0, 8.2), (19.0, -25, 19.8, 8.2), (15.2, 12.8, 16.0, 50), (19.0, 12.8, 19.8, 50)):
        box(a, b, 0.0, c, d, 0.07, conc, bevel=0.02)
    for k in range(-25, 50, 6):   # dashed centre line, faded
        box(k, 10.47, 0.006, k + 2.5, 10.53, 0.0075, P.MAT("flat:#a89a6a:0.8"))
    # north side: storefront row along main street, jail behind barbed wire to the north-east
    LM.storefront_row(M, -6, 3.2, 5, rng)
    LM.jail(M, 21.5, 1.0, rng)
    # south side: clinic and church on the west, mall with its lot on the east, park between
    LM.clinic(M, -8, 13.6, rng)
    LM.park(M, 3.0, 13.4, 11.0, 8.0, rng)
    LM.mall(M, 21.0, 13.6, rng, lot_rows=1)
    LM.church(M, -14.5, 13.8, rng)
    # graffiti on the big walls
    LM.graffiti_on(LM.GRAF_DIR, 22.0, 1.0 + 5 + 0.14, 6.0, rng, "s", n=2, zmax=1.8)          # jail
    LM.graffiti_on(LM.GRAF_DIR, 1.0 + 21.0, 13.6 + 7 + 0.14, 12.0, rng, "s", n=3, zmax=1.9)   # mall
    LM.graffiti_on(LM.GRAF_DIR, 8.8, 2.6 + 5 + 0.14, 4.6, rng, "s", n=1)                      # office block
    # warehouse lot fenced off with barbed wire
    house(M, -16, -4, [(0, 0, 7, 5, 1)], {True: M["brick"], False: M["brick_y"]}, "flat", door=("s", 5, 3.0, "barred"), win_state="boarded")
    LM.barbed_fence(M, -16.8, -4.8, -8.0, 2.6, gate=("e", 3.0), rng=rng)
    # fill the blocks behind the main street
    house(M, 8.6, 2.6, [(0, 0, 5, 5, 2)], M["stucco"], "flat", door=("s", 5, 2.5, "locked"), win_state="broken")
    LM.ruin_building(M, -3.5, -5.5, 5, 4, rng, "bombed", '#8a4434')
    house(M, 3.5, -5.0, [(0, 0, 4, 3, 1), (0, 3, 2, 2, 1)], M["siding_cream"], "gable", "sh_slate", door=("s", 3, 3.0, "barred"))
    LM.ruin_building(M, 9.5, -4.5, 4, 5, rng, "burnt", '#a89c84', storeys=2)
    P.scatter(-9, -8, 15, 2.5, 6, "city", rng, avoid=[(-3.7, -5.7, 1.7, -1.3), (3.3, -5.2, 7.7, 0.2), (9.3, -4.7, 13.7, 0.7), (-16.9, -4.9, -7.9, 2.7)])
    # barricades: a checkpoint across the avenue, one across main street, a sandbag nest at the corner
    LM.barricade_line(16.2, 6.5, 18.8, 6.0, rng)
    LM.barricade_line(-2.0, 9.2, -1.5, 11.8, rng)
    LM.random_barricades(-25, -25, 50, 50, 2, rng, roads=[main, cross])
    P.sandbags(15.0, 13.4, 45, rng); P.sandbags(20.0, 7.6, 0, rng)
    # street life of a dead city
    P.car_wreck(6, 10.0, 6, rng); P.car_wreck(11, 11.2, 186, rng, style="burned"); P.car_wreck(17.5, 26.5, 92, rng, style="truck")
    P.car_wreck(26, 10.3, 178, rng); P.dumpster(-7.0, 2.4, 0, rng, lid="open"); P.dumpster(14.2, 6.6, 90, rng)
    for x in (-4, 2, 8, 13, 23, 30):
        P.lamp_post(x, 8.5, 0, rng)
    P.traffic_light(15.6, 8.5, 0, rng); P.traffic_light(19.4, 12.4, 180, rng, fallen=True)
    P.phone_booth(13.6, 8.0, 0, rng); P.newsbox(4.5, 8.4, 0, rng); P.hydrant(0.5, 8.4, 0, rng); P.bench(9, 12.4, 180, rng)
    P.scatter(-25, 7.4, 50, 13.4, 5, "city", rng)
    P.scatter(13.6, -10, 21.6, 30, 5, "city", rng)
    P.scatter(-14, -2, 15, 3.0, 7, "city", rng)
    P.scatter(-14, 13.0, 3.0, 22, 6, "city", rng, avoid=[(-8.2, 13.4, -0.8, 19.5), (-14.6, 13.6, -10.0, 20.0)])
    render("scene_city_landmarks", 10.0, 10.5, W=1600, H=900, samples=56)


MAT_LINE = None

if WHICH in ("all", "suburb"):
    scene_suburb()
if WHICH in ("all", "city2"):
    MAT_LINE = None
    scene_city2()
if WHICH in ("all", "interiors"):
    scene_interiors()
if WHICH in ("all", "city"):
    scene_city()
if WHICH in ("all", "outskirts"):
    scene_outskirts()
