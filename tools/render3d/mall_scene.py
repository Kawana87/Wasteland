"""Mall look-test: a rundown shopping mall from outside (parking lot, carts, loading dock) and a cut-away
of its interior (shops, concourse, food court, department store, grocery).
python3 mall_scene.py OUT [ext|int|all]"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from lib import _nodes, _coord, _mix, _noise, _ramp, _bump, grime, grit, cracks, _hex
import kit, props as P, landmarks as LM
from kit import wall_run, window, STOREY, WALL_T
import bpy
from PIL import Image
from post import fallout_grade

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r3d"
WHICH = sys.argv[2] if len(sys.argv) > 2 else "all"
os.makedirs(OUT, exist_ok=True)
MAT = P.MAT


def render(name, cx, cy, W=1600, H=900, cz=0.5, samples=56):
    import validate
    validate.run(name)
    if os.environ.get("DRY"):
        return
    sc = bpy.context.scene
    lights()
    camera(cx, cy, W, H, cz)
    sc.cycles.samples = samples
    sc.render.filepath = os.path.join(OUT, name + "_raw.png")
    bpy.ops.render.render(write_still=True)
    fallout_grade(Image.open(sc.render.filepath)).save(os.path.join(OUT, name + ".png"))
    print("scene", name)


def fresh():
    reset()
    P._MC.clear(); kit._FP.clear(); kit.SOLIDS.clear(); kit.PAVED.clear()
    return kit.materials()


def mat_tile(name, a='#c8bea8', b='#8a7e6a', scale=2.0):
    """Grimy checkerboard floor tile: faded, stained, a few cracked."""
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    ch = nt.nodes.new("ShaderNodeTexChecker")
    ch.inputs["Scale"].default_value = scale
    ch.inputs["Color1"].default_value = _hex(a); ch.inputs["Color2"].default_value = _hex(b)
    nt.links.new(co, ch.inputs["Vector"])
    c = grime(nt, ch.outputs[0], co, 0.75, False)
    c, crk = cracks(nt, c, co, 1.4, 0.006)
    nt.links.new(grit(nt, c, co, 0.4, 90.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.55
    return m


def wall(M, a, b, h, mat, openings=(), cap=True, frames=False):
    """wall_run that also registers the wall as a solid, so the validator removes anything poking through it.
    Door gaps register too: props never block a doorway."""
    wall_run(M, a, b, h, mat, openings, cap=cap, frames=frames)
    t = WALL_T / 2 + 0.03
    kit.solid(min(a[0], b[0]) - t, min(a[1], b[1]) - t, max(a[0], b[0]) + t, max(a[1], b[1]) + t, max(h, 1.2), "wall")
    # doorways: keep a 1-tile clear zone on both sides so nothing blocks the threshold
    horiz = abs(a[1] - b[1]) < 1e-6
    lo = min(a[0], b[0]) if horiz else min(a[1], b[1])
    for (t0, t1, z0, z1, kind) in openings:
        if kind == "door":
            if horiz:
                kit.solid(lo + t0, a[1] - 0.8, lo + t1, a[1] + 0.8, 2.0, "doorway")
            else:
                kit.solid(a[0] - 0.8, lo + t0, a[0] + 0.8, lo + t1, 2.0, "doorway")


# ================================================================== exterior
def scene_ext():
    M = fresh()
    rng = random.Random(77)
    LM.GRAF_DIR = os.path.join(OUT, "graf"); os.makedirs(LM.GRAF_DIR, exist_ok=True)
    lot = (-3.0, 10.6, 29.0, 24.2)
    road = (-14, 25.0, 42, 27.8)
    kit.terrain(-14, -10, 42, 34, kit.mat_terrain(), amp=0.18, scale=0.5, flat=[(-3.5, -3, 29.5, 24.6), road])
    kit.road(*road)
    # ---------------------------------------------------------- the building: main block + taller anchor store
    wallm = kit.mat_stucco("mall_w", '#c8b898', '#8a7a60')
    band = kit.mat_stucco("mall_b", '#a89878', '#6a5a44')
    ops = [(7.8, 10.2, 0.0, 2.1, "door")]
    for (a, b) in ((0.6, 3.6), (4.2, 7.2), (10.8, 13.8), (14.4, 17.4)):
        ops.append((a, b, 0.25, 1.9, "win"))
    H = LM._flat_box_building(M, 0, 0, 18, 9, wallm, 2, ops, [])
    for (t0, t1, z0, z1, kind) in ops:
        LM.shop_window(M, 0, 9, t0, t1, z0, z1, rng, state="broken" if kind == "door" else rng.choice(["broken", "glass", "boarded", "broken"]))
    box(0.02, 9.06, 2.35, 17.98, 9.16, 2.55, band)                                   # belt course
    # entrance: canopy on four columns, sign band with letter blocks
    canopy = MAT("paint:#d8d0b8:0.4")
    box(6.6, 9.0, 2.5, 11.4, 11.0, 2.66, canopy)
    for px in (6.8, 11.2):
        cyl(px, 10.8, 0, 2.5, 0.1, canopy, 12)
    box(5.5, 9.12, 2.9, 12.5, 9.24, 3.8, MAT("paint:#b84a3a:0.55"))
    for k in range(6):
        if k != 3:   # one letter fell off
            box(5.9 + k * 1.1, 9.24, 3.05, 6.7 + k * 1.1, 9.26, 3.65, MAT("flat:#e8e0c8:0.6"))
    box(8.3, 10.6, 0.0, 9.1, 11.2, 0.02, MAT("flat:#2a2622:1.0"))                      # dark mat of dirt at the doors
    # anchor department store, taller, its own sign; loading dock on the east face
    anc = kit.mat_concrete("anc_w", '#b8b0a0')
    dock_ops = [(1.5, 3.5, 0.6, 2.6, "door"), (4.5, 6.5, 0.6, 2.6, "door")]
    HA = LM._flat_box_building(M, 18, -2, 7, 11, anc, 2.6, [(2.2, 4.8, 0.0, 2.2, "door")], dock_ops)
    LM.shop_window(M, 18, 9, 2.25, 4.75, 0.0, 2.15, rng, state="boarded")
    box(18.4, 9.12, 3.6, 24.6, 9.24, 4.7, MAT("paint:#3a5a8a:0.5"))
    for k in range(4):
        box(18.9 + k * 1.45, 9.24, 3.8, 19.9 + k * 1.45, 9.26, 4.5, MAT("flat:#e8e0c8:0.6"))
    shutter = MAT("metal:#8a8e88")
    for (t0, t1, z0, z1, k) in dock_ops:                     # roll-up doors, one jammed half open
        top = z1 if t0 < 3 else z0 + 0.9
        box(25.0 - 0.08, -2 + t0, top - 0.02 if top < z1 else z0, 25.0 + 0.02, -2 + t1, z1, shutter)
        if top < z1:
            box(25.0 - 0.2, -2 + t0, z0, 25.0 - 0.18, -2 + t1, top, M["black"])
        for kk in range(int((z1 - (top if top < z1 else z0)) / 0.12)):
            zz = (top if top < z1 else z0) + kk * 0.12
            box(25.02, -2 + t0, zz, 25.04, -2 + t1, zz + 0.02, MAT("metal:#6a6e68"))
    dock = kit.mat_concrete("dock", '#8a8478')
    box(25.0, -1.0, 0, 26.6, 6.0, 0.6, dock)
    kit.solid(25.0, -1.0, 26.6, 6.0, 0.6, "dock")
    for yy in (-0.6, 2.0, 5.0):
        box(26.6, yy - 0.15, 0.15, 26.75, yy + 0.15, 0.55, MAT("flat:#1e1c1a:0.9"))   # rubber bumpers
    # roof: skylight strip on the main block, AC units on the back half, one on the anchor
    glassm = MAT("flat:#3a4a50:0.2"); fr = MAT("metal:#6a6a64")
    for k in range(4):
        sx = 2.0 + k * 4.0
        box(sx, 2.0, H + 0.06, sx + 2.4, 3.6, H + 0.3, fr)
        kit.mesh([(sx + .05, 2.05, H + 0.3), (sx + 2.35, 2.05, H + 0.3), (sx + 2.35, 3.55, H + 0.3), (sx + .05, 3.55, H + 0.3), (sx + 1.2, 2.8, H + 0.8)],
                 [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], glassm if k != 2 else M["black"], "skylight")
    P.roof_units(0, 4.6, 18, 9, H + 0.06, rng)
    P.roof_units(18, -2, 25, 9, HA + 0.06, rng, n=1)
    LM.graffiti_on(LM.GRAF_DIR, 0.4, 9 + WALL_T + 0.06, 5.5, rng, "s", n=1, zmax=2.0)
    LM.graffiti_on(LM.GRAF_DIR, 12.6, 9 + WALL_T + 0.06, 5.0, rng, "s", n=1, zmax=2.0)
    # ---------------------------------------------------------- sidewalk + parking lot
    conc = M["conc"]
    box(-1.0, 9.0, 0.0, 26.0, 10.6, 0.08, conc, bevel=0.02)
    box(lot[0], lot[1], 0.0, lot[2], lot[3], 0.008, M["asphalt"])
    paint = MAT("flat:#c8c0a0:0.85"); yellow = MAT("flat:#c8a84a:0.85")
    rows = [(11.4, 13.6), (15.8, 18.0), (18.6, 20.8)]          # bay rows (y0, y1); island between the two back rows
    bays_x = [i * 1.25 for i in range(-1, 22)]
    for (y0, y1) in rows:
        for bx in bays_x:
            if rng.random() < 0.82:                                     # faded: some lines gone
                box(bx, y0, 0.008, bx + 0.05, y1 - rng.uniform(0, 0.8), 0.0095, paint)
    box(-2.5, 18.2, 0.0, 27.5, 18.4, 0.15, conc)                         # island curb with planters
    for k in range(12):                                               # arrows / handicap paint, faded
        if rng.random() < 0.4:
            box(bays_x[k * 2] + 0.3, 14.4, 0.008, bays_x[k * 2] + 0.9, 14.6, 0.0095, yellow)
    with P.zone(prio=2):
        for (px, py) in ((2.0, 18.3), (11.5, 18.3), (21.0, 18.3)):
            P.lamp_post(px, py, 0, rng)
        P.planter(6.5, 18.3, 0, rng, r=0.7); P.planter(16.5, 18.3, 0, rng, r=0.7, tree_kind="sparse")
        P.planter(3.0, 10.0, 0, rng, r=0.5, tree_kind="scrub"); P.planter(15.0, 10.0, 0, rng, r=0.5, tree_kind="scrub")
        P.cart_corral(9.0, 15.0, 90, rng, n=2); P.cart_corral(19.5, 14.8, 90, rng, n=0)
        P.pylon_sign(-1.5, 23.4, 0, rng)
        P.bus_stop(13.0, 24.6, 0, rng)
        P.trash_can(5.0, 10.0, 0, rng, tipped=False); P.trash_can(13.0, 10.1, 0, rng, tipped=True)
        P.bench(1.5, 9.9, 0, rng); P.vending(17.2, 9.9, 0, rng)
        # loading dock: truck backed in, dumpsters, pallets
        P.car_wreck(28.6, 1.0, 0, rng, style="truck")
        P.dumpster(27.0, 7.4, 90, rng, lid="open"); P.dumpster(27.0, 9.6, 80, rng)
        P.pallet(26.0, 6.8, 15, rng); P.pallet(25.8, -1.8, 0, rng); P.crate(26.2, -1.6, 0, rng)
        # raiders squatting in the far corner of the lot behind a ring of barriers
        P.campfire_pit(25.5, 21.8, 0, rng); P.lean_to(27.3, 22.3, 90, rng); P.junk_pile(23.5, 23.2, 0, rng)
        P.jersey(22.6, 21.2, 80, rng); P.sandbags(24.6, 20.6, 0, rng); P.barricade(27.8, 20.4, 0, rng)
        P.skeleton(10.2, 12.0, 30, rng); P.skeleton(3.6, 21.6, 160, rng)
        # entrance barricade at the lot mouth
        P.jersey(4.0, 23.6, 5, rng); P.jersey(6.2, 23.8, -8, rng); P.barricade(8.5, 23.6, 0, rng)
    # random: wrecks parked crooked in bays, stray carts, a few tipped
    with P.zone(prio=1):
        for k in range(8):
            (y0, y1) = rng.choice(rows)
            bx = rng.choice(bays_x[1:-1]) + 0.62
            P.car_wreck(bx, (y0 + y1) / 2, 90 + rng.uniform(-12, 12), rng)
        for k in range(14):
            P.shopping_cart(rng.uniform(-2, 27), rng.uniform(10.8, 24), rng.uniform(0, 360), rng)
        for k in range(4):                                             # a cart train abandoned by the doors
            P.shopping_cart(5.6 + k * 0.62, 11.0, 0, rng)
        for k in range(12):
            P.pothole(rng.uniform(-2.5, 28.5), rng.uniform(11, 24), 0, rng)
        for k in range(10):
            P.stain(rng.uniform(-2.5, 28.5), rng.uniform(11, 24), 0, rng)
        for k in range(14):
            P.weeds_line(rng.choice(bays_x) + 0.02, rng.uniform(12, 20), 0, rng, L=rng.uniform(0.8, 2.0), axis="y")
        for k in range(6):
            P.tumbleweed(rng.uniform(-3, 29), rng.uniform(10, 25), 0, rng)
        for k in range(5):
            P.tree(rng.uniform(-12, 40), rng.uniform(-9, 33), 0, random.Random(k * 7), kind=rng.choice(["dead", "scrub"]))
    P.litter(9, 11.5, 0, rng, n=26, r=4); P.litter(20, 16, 0, rng, n=20, r=5); P.litter(26.5, 8.0, 0, rng, n=14, r=1.6)
    P.scatter(-3, 10.6, 29, 24.2, 2.5, "city", rng)
    P.scatter(-14, -10, 42, 34, 2.2, "wild", rng, avoid=[(-3.5, -3, 29.5, 24.6), road])
    render("mall_exterior", 12.5, 11.5)


# ================================================================== interior (cut-away)
def scene_int():
    M = fresh()
    rng = random.Random(88)
    CUT = 0.85
    HI = STOREY * 1.5
    W, D = 20, 12
    box(-6, -6, -0.1, 30, 22, 0.0, M["dirt"])
    tile = mat_tile("mall_tile"); lino = mat_tile("store_lino", '#a8a090', '#9a9282', 4.0); groc = mat_tile("groc_tile", '#c8c4b4', '#7a8a7a', 3.0)
    inner = kit.mat_stucco("mall_in", '#c8bca4', '#8a7e66')
    outer = kit.mat_stucco("mall_w", '#c8b898', '#8a7a60')
    # floors
    box(0, 0, 0, W, D, 0.03, lino)
    box(0, 4, 0.031, W, 7.6, 0.032, tile)
    box(12, 7.6, 0.031, W, D, 0.032, groc)
    # shell: north + west full height, south + east cut (entrance on the south, service door east)
    wall(M, (0, 0), (W, 0), HI, inner)
    wall(M, (0, 0), (0, D), HI, inner)
    wall(M, (0, D), (W, D), CUT, outer, [(8.6, 11.4, 0, 2.2, "door")])
    wall(M, (W, 0), (W, D), CUT, outer, [(9.0, 10.0, 0, 1.6, "door")])
    # north shops: full-height party walls, low shopfronts so you can look in
    shops = [("cloth", 0, 5), ("diner", 5, 10), ("radio", 10, 15), ("toys", 15, 20)]
    cols = ["#b03a26", "#3e7a6a", "#c8a040", "#3a5a8a"]
    for i, (kind, x0, x1) in enumerate(shops):
        if x0 > 0:
            wall(M, (x0, 0), (x0, 4), HI, inner)
        door_t = (3.2, 2.6, 1.0, 0.4)[i]
        wall(M, (x0, 4), (x1, 4), CUT * 0.6, inner, [(door_t, door_t + 1.4, 0, 2.2, "door")])
        # shop sign on the back wall + grime
        box(x0 + 0.8, 0.06, 2.2, x1 - 0.8, 0.12, 2.7, MAT("paint:%s:0.5" % cols[i]))
        box(x0 + 1.1, 0.12, 2.32, x1 - 1.3, 0.13, 2.58, MAT("flat:#e8e0c8:0.6"))
    # south: department store (west) and grocery (east), low partitions with wide openings
    wall(M, (0, 7.6), (12, 7.6), CUT, inner, [(3.0, 6.0, 0, 2.2, "door")])
    wall(M, (12, 7.6), (W, 7.6), CUT, inner, [(2.0, 4.0, 0, 2.2, "door")])
    wall(M, (12, 7.6), (12, D), CUT, inner, [(1.4, 2.6, 0, 2.2, "door")])
    rub = [M["conc"], MAT("conc:#8a8478"), inner]
    # ---------------------------------------------------------- furnishing (all hand-placed, validator checks clashes)
    with P.zone(prio=2):
        # clothing shop
        P.clothing_rack(1.4, 1.2, 0, rng, kind="rail"); P.clothing_rack(3.6, 2.6, 0, rng, kind="round")
        P.mannequin(4.3, 0.6, 0, rng, fallen=False); P.mannequin(0.8, 2.3, 0, rng, fallen=True)
        P.counter(2.0, 3.3, 0, rng, w=1.2)
        # diner: booths along the back, counter with stools, jukebox
        P.booth(6.0, 0.9, 0, rng); P.booth(8.0, 0.9, 0, rng)
        P.counter(8.4, 2.6, 0, rng, w=1.6); P.jukebox(9.5, 0.5, 0, rng)
        # radio / electronics
        P.bookshelf(11.0, 0.35, 0, rng, w=1.0); P.tv(12.6, 0.5, 0, rng); P.radio(13.4, 0.5, 0, rng)
        P.counter(12.5, 3.0, 0, rng, w=1.4); P.terminal(14.2, 2.0, -90, rng)
        P.cardboard_boxes(10.6, 3.2, 0, rng)
        # toy store: looted shelves
        P.gondola(18.1, 1.2, 0, rng, w=2.0, stock=0.25); P.gondola(18.1, 2.7, 0, rng, w=2.0, stock=0.1)
        # concourse: dry fountain in the middle, planters, benches, kiosk, food court to the east
        P.planter(1.7, 6.7, 0, rng, r=0.6); P.planter(12.4, 5.6, 0, rng, r=0.6, tree_kind="sparse")
        P.bench(4.6, 4.6, 0, rng); P.bench(10.8, 7.0, 180, rng)
        P.kiosk(5.4, 6.6, 0, rng)
        P.vending(0.45, 4.6, -90, rng); P.trash_can(7.2, 4.9, 0, rng, tipped=True)
        for (fx, fy) in ((15.6, 5.0), (17.8, 5.0), (16.7, 6.4), (18.9, 6.4)):
            _food_table(fx, fy, 0, rng)
        # department store
        P.clothing_rack(1.4, 9.2, 0, rng, kind="round"); P.clothing_rack(3.4, 9.0, 0, rng, kind="rail")
        P.clothing_rack(1.6, 11.0, 0, rng, kind="rail"); P.clothing_rack(5.6, 10.6, 0, rng, kind="round")
        P.mannequin(7.0, 8.4, 0, rng, fallen=False); P.mannequin(7.6, 8.5, 0, rng, fallen=False); P.mannequin(4.2, 10.3, 0, rng, fallen=True)
        P.checkout(9.6, 9.6, 0, rng); P.checkout(9.6, 11.0, 0, rng)
        P.cardboard_boxes(11.3, 8.3, 0, rng)
        # grocery: aisles of gondolas, checkout, a fridge wall
        for k, gy in enumerate((9.4, 10.9)):
            P.gondola(16.6, gy, 0, rng, w=3.4, stock=rng.uniform(0.15, 0.6))
        P.fridge(19.45, 10.6, 90, rng); P.fridge(19.45, 11.4, 90, rng)
        P.checkout(13.6, 11.3, 0, rng)
        # fallen ceiling + raider leftovers
        P.rubble_pile(9.8, 5.9, 0, rng, size=1.2, mats=rub); P.rubble_pile(14.5, 9.6, 0, rng, size=0.8, mats=rub)
        P.skeleton(11.2, 4.7, 60, rng); P.campfire_pit(3.0, 7.0, 0, rng)
        P.mattress(6.3, 2.6, 0, rng)
    with P.zone(prio=1):
        for k in range(5):
            P.shopping_cart(rng.uniform(12.5, 19.5), rng.uniform(7.9, 11.8), rng.uniform(0, 360), rng)
        for k in range(3):
            P.shopping_cart(rng.uniform(1, 18), rng.uniform(4.2, 7.4), rng.uniform(0, 360), rng)
        for k in range(14):                                     # ceiling tiles that came down
            cx, cy = rng.uniform(0.5, 19.5), rng.uniform(0.5, 11.5)
            P.stain(cx, cy, 0, rng, col=rng.choice(["#4a4236", "#5a5040"]), r=rng.uniform(0.3, 0.6))
        for k in range(10):
            P.cardboard_boxes(rng.uniform(0.5, 19.5), rng.uniform(0.5, 11.5), rng.uniform(0, 360), rng)
    _ceiling_tiles(rng, 40, W, D)
    P.litter(8, 6, 0, rng, n=40, r=6); P.litter(16, 10, 0, rng, n=25, r=3.5); P.litter(3, 10, 0, rng, n=18, r=3)
    # outside the cut-away: the lot edge so it reads as the same mall
    box(-1, D, 0, W + 1, D + 1.6, 0.08, M["conc"], bevel=0.02)
    box(-2, D + 1.6, 0, W + 2, D + 5, 0.008, M["asphalt"])
    with P.zone(prio=1):
        P.shopping_cart(6.0, D + 0.8, 10, rng); P.car_wreck(15.0, D + 3.4, 92, rng); P.shopping_cart(3.0, D + 3.0, 200, rng)
    render("mall_interior", 10.0, 6.6, W=1600, H=900, cz=0.4)


@P.prop
def _food_table(x, y, rng):
    """Food court table with its chairs: one group, so chairs tucked under the table are not 'clashes'."""
    P.table(x, y, 0, rng, shape="round")
    for k in range(4):
        if rng.random() < 0.75:
            a = k * 90 + rng.uniform(-20, 20)
            r = 0.62
            P.chair(x + math.cos(math.radians(a)) * r, y + math.sin(math.radians(a)) * r, -a + 90 + rng.uniform(-30, 30), random.Random(rng.random()), style="diner")


def _ceiling_tiles(rng, n, W, D):
    """Fallen ceiling panels: thin slabs lying around, some leaning."""
    m = MAT("flat:#c8c0a8:0.9")
    for k in range(n):
        cx, cy = rng.uniform(0.3, W - 0.3), rng.uniform(0.3, D - 0.3)
        o = box(cx - .28, cy - .28, 0.033, cx + .28, cy + .28, 0.05, m)
        o.rotation_euler = (rng.uniform(-.25, .25), rng.uniform(-.25, .25), rng.uniform(0, 3.14))
        o.location.z += 0.04


if WHICH in ("all", "ext"):
    scene_ext()
if WHICH in ("all", "int"):
    scene_int()
