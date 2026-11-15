"""City landmarks for the pre-rendered art: storefront rows, a jail / police station behind barbed wire,
a mall with its parking lot, a park, a clinic and a church. Plus barbed-wire perimeter fences and
random street barricades. Built from kit + props; names are generic."""
import math, random
import bpy
import fast as FAST
from lib import box, cyl, sphere, g2b, rot_z, mat_flat
import kit
from kit import wall_run, window, house, DIR, STOREY, mesh, R
import props as P
from props import MAT, B


GRAF_DIR = None      # set by the scene: where generated graffiti textures go


# ------------------------------------------------------------------ fences and barricades
def barbed_fence(M, x0, y0, x1, y1, gate=None, rng=None):
    """Chain-link fence around a rectangle with coiled razor wire on top. gate: (side, pos) gap."""
    rng = rng or random.Random()
    post = MAT("metal:#7a7a74")
    meshm = MAT("flat:#8a8a84:0.4")
    wire = MAT("metal:#5a5a54")
    sides = [("n", (x0, y0), (x1, y0)), ("s", (x0, y1), (x1, y1)), ("w", (x0, y0), (x0, y1)), ("e", (x1, y0), (x1, y1))]
    for side, a, b in sides:
        horiz = side in ("n", "s")
        L = abs(b[0] - a[0]) if horiz else abs(b[1] - a[1])
        n = max(1, int(round(L)))
        for k in range(n + 1):
            t = L * k / n
            px, py = (a[0] + t, a[1]) if horiz else (a[0], a[1] + t)
            cyl(px, py, 0, 1.75, 0.03, post, 6)
            o = B(px - .015, py - .015, 1.7, px + .015, py + .015, 1.95, post)
        for k in range(n):
            t0, t1 = L * k / n, L * (k + 1) / n
            mid = (t0 + t1) / 2
            if gate and gate[0] == side and abs(mid - gate[1]) < 0.9:
                continue
            if rng.random() < 0.1:
                continue      # cut / fallen section
            sag = rng.uniform(0, 0.12)
            if horiz:
                B(a[0] + t0, a[1] - .005, 0.05, a[0] + t1, a[1] + .005, 1.65 - sag, meshm)
            else:
                B(a[0] - .005, a[1] + t0, 0.05, a[0] + .005, a[1] + t1, 1.65 - sag, meshm)
            # razor-wire coil: a row of loops along the top
            loops = int((t1 - t0) / 0.18)
            for j in range(loops):
                tt = t0 + (j + 0.5) * (t1 - t0) / loops
                px, py = (a[0] + tt, a[1]) if horiz else (a[0], a[1] + tt)
                o = FAST.primitive_torus_add(major_radius=0.13, minor_radius=0.006, major_segments=10, minor_segments=3,
                                             location=g2b(px, py, 1.95), rotation=(math.radians(90), 0, 0 if not horiz else math.radians(90)))
                o.rotation_euler = (math.radians(90), math.radians(rng.uniform(-15, 15)), math.radians(90) if horiz else 0)
                o.data.materials.append(wire)


def barricade_line(x0, y0, x1, y1, rng):
    """A street barricade between two points made of whatever was at hand."""
    L = math.hypot(x1 - x0, y1 - y0)
    ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
    t = 0.3
    while t < L - 0.3:
        px, py = x0 + (x1 - x0) * t / L, y0 + (y1 - y0) * t / L
        kind = rng.random()
        if kind < 0.3:
            P.jersey(px, py, ang, rng); t += 1.9
        elif kind < 0.55:
            P.sandbags(px, py, ang, rng); t += 1.6
        elif kind < 0.7:
            P.barricade(px, py, ang, rng); t += 1.6
        elif kind < 0.82:
            P.car_wreck(px, py, ang + rng.uniform(-15, 15), rng, style=rng.choice(["burned", "sedan"])); t += 2.9
        else:
            for k in range(2):
                P.barrel(px + rng.uniform(-.3, .3), py + rng.uniform(-.3, .3), 0, rng)
            P.tire_stack(px + .5, py, 0, rng); t += 1.3


def random_barricades(x0, y0, x1, y1, n, rng, roads=()):
    """Throw a few barricades across the given road rectangles."""
    for k in range(n):
        if not roads: break
        (a0, b0, a1, b1) = rng.choice(roads)
        if (a1 - a0) > (b1 - b0):
            x = rng.uniform(a0 + 2, a1 - 2)
            barricade_line(x + rng.uniform(-.3, .3), b0 + 0.2, x + rng.uniform(-.3, .3), b1 - 0.2, rng)
        else:
            y = rng.uniform(b0 + 2, b1 - 2)
            barricade_line(a0 + 0.2, y + rng.uniform(-.3, .3), a1 - 0.2, y + rng.uniform(-.3, .3), rng)


# ------------------------------------------------------------------ buildings
def _flat_box_building(M, x0, y0, w, h, wall, storeys=1, openings_s=(), openings_e=(), parapet=True, roof_mat=None):
    """Closed building with custom openings on the visible south/east faces (n/w get plain walls)."""
    x1, y1 = x0 + w, y0 + h
    H = STOREY * storeys
    wm = wall if not isinstance(wall, dict) else wall
    gw = (lambda horiz: wall[horiz]) if isinstance(wall, dict) else (lambda horiz: wall)
    wall_run(M, (x0, y0), (x1, y0), H, gw(True), [], cap=False)
    wall_run(M, (x0, y0), (x0, y1), H, gw(False), [], cap=False)
    wall_run(M, (x0, y1), (x1, y1), H, gw(True), list(openings_s), cap=False)
    wall_run(M, (x1, y0), (x1, y1), H, gw(False), list(openings_e), cap=False)
    box(x0 - 0.12, y0 - 0.12, H - 0.02, x1 + 0.12, y1 + 0.12, H + 0.06, roof_mat or M["conc"])
    kit.solid(x0, y0, x1, y1, H + 0.3)
    if parapet:
        for (a, b, c, d) in ((x0 - .14, y0 - .14, x1 + .14, y0 + .02), (x0 - .14, y1 - .02, x1 + .14, y1 + .14),
                             (x0 - .14, y0 - .14, x0 + .02, y1 + .14), (x1 - .02, y0 - .14, x1 + .14, y1 + .14)):
            box(a, b, H, c, d, H + 0.28, gw(True) if (d - b) < 0.5 else gw(False))
    return H


def shop_window(M, x0, y, t0, t1, z0, z1, rng, state=None):
    """Big display window on a south wall at y (game), with mullions; broken, boarded or intact."""
    state = state or rng.choice(["glass", "broken", "broken", "boarded"])
    n = max(2, int((t1 - t0) / 0.7))
    for i in range(n):
        s0 = t0 + (t1 - t0) * i / n + 0.02
        s1 = t0 + (t1 - t0) * (i + 1) / n - 0.02
        if state == "glass" or (state == "broken" and rng.random() < 0.35):
            box(x0 + s0, y - 0.01, z0, x0 + s1, y + 0.01, z1, M["glass"])
        else:
            box(x0 + s0, y - 0.06, z0, x0 + s1, y - 0.05, z1, M["black"])
        box(x0 + s1, y - .03, z0, x0 + s1 + 0.04, y + .03, z1, M["frame"])
    if state == "boarded":
        kit.board_up(lambda p0, p1, za, zb: box(x0 + p0, y + 0.13, za, x0 + p1, y + 0.15, zb, M["board"]), t0, t1, z0, z1, 'Y')
    box(x0 + t0 - 0.06, y - 0.15, z0 - 0.08, x0 + t1 + 0.06, y + 0.15, z0, M["trim"])        # sill


def awning(x0, x1, y, z, col, rng):
    """Striped fabric awning sloping out from a south wall, sometimes torn."""
    stripes = int((x1 - x0) / 0.3)
    for k in range(stripes):
        a = x0 + k * (x1 - x0) / stripes
        b = x0 + (k + 1) * (x1 - x0) / stripes
        if rng.random() < 0.08:
            continue
        mcol = col if k % 2 == 0 else "#d8d0bc"
        mesh([(a, y, z), (b, y, z), (b, y + 0.85, z - 0.45), (a, y + 0.85, z - 0.45)], [(0, 1, 2, 3)], MAT("fab:%s" % mcol), "awning", solidify=0.02)
    B(x0, y + 0.82, z - 0.62, x1, y + 0.86, z - 0.42, MAT("fab:%s" % col))


def sign_board(x0, x1, y, z, col, rng):
    """Painted sign panel above a storefront (no lettering), with a few faded stripes."""
    B(x0, y + 0.12, z, x1, y + 0.18, z + 0.42, MAT("paint:%s:0.5" % col))
    for k in range(rng.randint(1, 3)):
        a = x0 + rng.uniform(0.1, (x1 - x0) * 0.5)
        B(a, y + 0.18, z + 0.1 + k * 0.1, a + rng.uniform(0.3, (x1 - x0) * 0.45), y + 0.19, z + 0.16 + k * 0.1, MAT("flat:#e0d8c0:0.6"))


def storefront_row(M, x0, y0, n, rng):
    """A row of joined storefronts along a street (street is to the south)."""
    x = x0
    walls = [M["brick"], M["stucco"], kit.mat_stucco("sf_a", '#b8a482', '#7a6a50'), kit.mat_stucco("sf_b", '#8a9a8a', '#5a6a5a')]
    cols = ["#b03a26", "#3e7a6a", "#c8a040", "#3a5a8a", "#7a4a6a"]
    for k in range(n):
        w = rng.choice([3, 3, 4])
        h = rng.choice([4, 5])
        st = 2 if rng.random() < 0.35 else 1
        wall = rng.choice(walls)
        wd = {True: M["brick"], False: M["brick_y"]} if wall is M["brick"] else wall
        door_t = rng.uniform(0.6, w - 1.0)
        win = (0.3, w - 0.3)
        ops = [(door_t - 0.42, door_t + 0.42, 0.0, 1.6, "door")]
        if door_t - 0.5 > 0.6:
            ops.append((0.25, door_t - 0.55, 0.35, 1.6, "win"))
        if w - 0.25 - (door_t + 0.55) > 0.4:
            ops.append((door_t + 0.55, w - 0.25, 0.35, 1.6, "win"))
        if st == 2:
            for t in (0.9, w - 0.9):
                ops.append((t - 0.35, t + 0.35, STOREY + 0.8, STOREY + 1.6, "win"))
        H = _flat_box_building(M, x, y0, w, h, wd, st, ops)
        for (t0, t1, z0, z1, kind) in ops:
            if kind == "win" and z0 < 1:
                shop_window(M, x, y0 + h, t0, t1, z0, z1, rng)
            elif kind == "win":
                window(M, (x, y0 + h), (x + w, y0 + h), t0, t1, z0 - STOREY, z1 - STOREY, (0, 1), rng.choice(["glass", "broken", "boarded"]), zbase=STOREY)
            else:
                kit.door(M, (x, y0 + h), (x + w, y0 + h), t0, t1, (0, 1), rng.choice(["open", "closed", "locked", "boarded", "broken"]))
        if rng.random() < 0.75:
            awning(x + 0.1, x + w - 0.1, y0 + h + 0.12, 1.95, rng.choice(cols), rng)
        sign_board(x + 0.2, x + w - 0.2, y0 + h, 2.0 if st == 1 else 2.0, rng.choice(cols), rng)
        if rng.random() < 0.5:
            P.roof_units(x, y0, x + w, y0 + h, H + 0.06, rng, n=1)
        if GRAF_DIR and rng.random() < 0.7:
            graffiti_on(GRAF_DIR, x + 0.1, y0 + h + kit.WALL_T + 0.03, w - 0.2, rng, "s", zmax=1.7)
        x += w


def jail(M, x0, y0, rng):
    """Two-storey concrete police station / jail with barred windows, a fenced yard and a guard tower."""
    w, h = 8, 5
    conc = kit.mat_concrete("jail_c", '#8a8a80')
    ops_s = [(3.6, 4.4, 0.0, 1.6, "door")]
    for t in (1.2, 2.6, 5.4, 6.8):
        ops_s.append((t - 0.3, t + 0.3, 0.9, 1.6, "win"))
        ops_s.append((t - 0.3, t + 0.3, STOREY + 0.9, STOREY + 1.6, "win"))
    ops_e = []
    for t in (1.0, 2.5, 4.0):
        ops_e.append((t - 0.3, t + 0.3, STOREY + 0.9, STOREY + 1.6, "win"))
    H = _flat_box_building(M, x0, y0, w, h, conc, 2, ops_s, ops_e)
    bars = MAT("metal:#3a3a38")
    for (t0, t1, z0, z1, kind) in ops_s:
        if kind == "win":
            box(x0 + t0, y0 + h - 0.06, z0, x0 + t1, y0 + h - 0.05, z1, M["black"])
            for k in range(5):
                bx = x0 + t0 + (t1 - t0) * (k + 0.5) / 5
                box(bx - 0.012, y0 + h + 0.0, z0, bx + 0.012, y0 + h + 0.03, z1, bars)
    for (t0, t1, z0, z1, kind) in ops_e:
        box(x0 + w + 0.05, y0 + t0, z0, x0 + w + 0.06, y0 + t1, z1, M["black"])
        for k in range(5):
            by = y0 + t0 + (t1 - t0) * (k + 0.5) / 5
            box(x0 + w, by - 0.012, z0, x0 + w + 0.03, by + 0.012, z1, bars)
    kit.door(M, (x0, y0 + h), (x0 + w, y0 + h), 3.6, 4.4, (0, 1), "locked", paint=MAT("paint:#4a5a6a:0.4"))
    # entrance canopy + light blue sign band
    box(x0 + 3.0, y0 + h, 2.0, x0 + 5.0, y0 + h + 1.0, 2.1, conc)
    for px in (x0 + 3.1, x0 + 4.9):
        cyl(px, y0 + h + 0.9, 0, 2.0, 0.05, conc, 8)
    box(x0 + 1.0, y0 + h + 0.12, 3.75, x0 + 7.0, y0 + h + 0.18, 3.95, MAT("paint:#3a5a8a:0.4"))
    # fenced exercise yard to the east + guard tower
    barbed_fence(M, x0 + w + 0.6, y0 - 0.5, x0 + w + 5.6, y0 + h + 2.0, gate=("s", 1.5), rng=rng)
    tx, ty = x0 + w + 5.1, y0 - 0.0
    for (a, b) in ((-.5, -.5), (.5, -.5), (-.5, .5), (.5, .5)):
        cyl(tx + a, ty + b, 0, 3.0, 0.06, MAT("wood:#5a4030:#4a3424"), 6)
    box(tx - .7, ty - .7, 3.0, tx + .7, ty + .7, 3.1, MAT("wood:#6a5034:#5a4028"))
    for (a0, b0, a1, b1) in ((-.7, .62, .7, .7), (.62, -.7, .7, .7)):
        box(tx + a0, ty + b0, 3.1, tx + a1, ty + b1, 3.6, MAT("wood:#6a5034:#5a4028"))
    kit.mesh([(tx - .85, ty - .85, 4.2), (tx + .85, ty - .85, 4.2), (tx + .85, ty + .85, 4.2), (tx - .85, ty + .85, 4.2), (tx, ty, 4.6)],
             [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], M["tin"], "towerroof", solidify=0.03)
    for (a, b) in ((-.65, -.65), (.65, -.65), (-.65, .65), (.65, .65)):
        cyl(tx + a, ty + b, 3.1, 4.2, 0.03, MAT("wood:#5a4030:#4a3424"), 6)
    P.sandbags(x0 + 2.0, y0 + h + 1.6, 0, rng)
    P.sandbags(x0 + 6.0, y0 + h + 1.6, 0, rng)


# real-world sizing for lots, in tiles (a car wreck is ~2.7 x 1.1)
BAY_W, BAY_D, AISLE, FIRE_LANE = 1.6, 3.1, 4.2, 3.4


def parking_lot(M, x0, y0, x1, rng, pairs=1, road_y=None, entry_x=None, wrecks=None):
    """Parking lot south of a building front at y0. Rows run along x:
       fire lane | (bays facing north, bays facing south, aisle) x pairs
    Every bay is reachable from an aisle; the last aisle connects to the road at road_y by a driveway.
    Returns (lot far edge y, driveway rect or None)."""
    ys = [y0, y0 + FIRE_LANE]
    rows = []
    y = y0 + FIRE_LANE
    for p in range(pairs):
        rows.append((y, y + BAY_D, "n")); y += BAY_D
        rows.append((y, y + BAY_D, "s")); y += BAY_D
        y += AISLE
    y1 = y
    kit.road(x0, y0, x1, y1, z=0.007, name="lot", lot=True)
    paint = MAT("flat:#c8c0a0:0.85")
    nb = int((x1 - x0 - 1.0) / BAY_W)
    bx0 = x0 + (x1 - x0 - nb * BAY_W) / 2
    bays = []
    for (r0, r1, face) in rows:
        for k in range(nb + 1):
            if rng.random() < 0.85:                     # faded paint, some lines gone
                xx = bx0 + k * BAY_W
                box(xx - 0.025, r0 + 0.15, 0.007, xx + 0.025, r1 - 0.1, 0.0085, paint)
        bays += [(bx0 + (k + 0.5) * BAY_W, (r0 + r1) / 2) for k in range(nb)]
    for p in range(pairs):                               # divider between back-to-back rows + light poles
        yd = rows[2 * p][1]
        box(bx0, yd - 0.03, 0.007, bx0 + nb * BAY_W, yd + 0.03, 0.0085, paint)
        with P.zone(prio=2):
            for k in range(0, nb + 1, 5):
                P.lamp_post(bx0 + k * BAY_W, yd, 0, rng)
    drive = None
    if road_y is not None:
        ex = entry_x if entry_x is not None else (x0 + x1) / 2
        drive = (ex - 2.2, y1 - 0.6, ex + 2.2, road_y + 0.4)
        kit.road(*drive, z=0.0072, name="drive")
    with P.zone(prio=1):
        for (bx, by) in rng.sample(bays, min(len(bays), wrecks if wrecks is not None else max(2, len(bays) // 6))):
            P.car_wreck(bx + rng.uniform(-0.1, 0.1), by, 90 + rng.uniform(-6, 6), rng)
        for k in range(rng.randint(3, 7)):
            P.shopping_cart(rng.uniform(x0, x1), rng.uniform(y0, y1), rng.uniform(0, 360), rng)
    P.litter((x0 + x1) / 2, (y0 + y1) / 2, 0, rng, n=30, r=(x1 - x0) / 2.5)
    return y1, drive


def mall(M, x0, y0, rng, lot_rows=1, road_y=None, entry_x=None):
    """Big flat-roofed mall: a long glass-fronted facade, entrance canopy, parking lot in front."""
    w, h = 14, 7
    wall = kit.mat_stucco("mall_w", '#c8b898', '#8a7a60')
    ops = [(6.2, 7.8, 0.0, 1.9, "door")]
    for (a, b) in ((0.6, 5.6), (8.4, 13.4)):
        ops.append((a, b, 0.25, 1.75, "win"))
    H = _flat_box_building(M, x0, y0, w, h, wall, 2, ops, [(2.0, 5.0, 0.25, 1.75, "win")])
    for (t0, t1, z0, z1, kind) in ops:
        if kind == "win":
            shop_window(M, x0, y0 + h, t0, t1, z0, z1, rng, state=rng.choice(["broken", "glass", "boarded"]))
    shop_window(M, x0, y0 + h, 6.25, 7.75, 0.0, 1.85, rng, state="broken")
    # east facade window band
    for k in range(4):
        box(x0 + w + 0.05, y0 + 2.0 + k * 0.75 + 0.02, 0.25, x0 + w + 0.06, y0 + 2.0 + (k + 1) * 0.75 - 0.02, 1.75,
            M["glass"] if rng.random() < 0.5 else M["black"])
    # canopy over the entrance on two pillars + a big sign band across the top
    box(x0 + 5.0, y0 + h, 2.2, x0 + 9.0, y0 + h + 1.6, 2.32, MAT("paint:#d8d0b8:0.4"))
    for px in (x0 + 5.2, x0 + 8.8):
        cyl(px, y0 + h + 1.45, 0, 2.2, 0.08, MAT("paint:#d8d0b8:0.4"), 10)
    box(x0 + 3.0, y0 + h + 0.12, 2.8, x0 + 11.0, y0 + h + 0.2, 3.7, MAT("paint:#b84a3a:0.55"))
    for k in range(5):
        box(x0 + 3.6 + k * 1.5, y0 + h + 0.2, 3.0, x0 + 4.6 + k * 1.5, y0 + h + 0.21, 3.5, MAT("flat:#e8e0c8:0.6"))
    P.roof_units(x0, y0, x0 + w, y0 + h, H + 0.06, rng)
    lot_y0 = y0 + h + 1.8
    box(x0 - 0.5, y0 + h, 0.0, x0 + w + 0.5, lot_y0, 0.07, M["conc"], bevel=0.02)      # front walk
    kit.PAVED.append((x0 - 0.5, y0 + h, x0 + w + 0.5, lot_y0))
    lot_y1, drive = parking_lot(M, x0 - 1, lot_y0, x0 + w + 1, rng, pairs=lot_rows, road_y=road_y, entry_x=entry_x)
    return lot_y1


def park(M, x0, y0, w, h, rng):
    """Overgrown city park. Every park is assembled differently: path layout, centrepiece and corner
    features are drawn at random, so no two read as the same copy-pasted block."""
    kit.patch(x0, y0, x0 + w, y0 + h, rng.choice([[(0.3, '#5a5a34'), (0.5, '#6e6e3e'), (0.7, '#7e7a4e')],
                                                  [(0.3, '#62603a'), (0.5, '#747046'), (0.7, '#8a8256')],
                                                  [(0.3, '#545a36'), (0.5, '#666c40'), (0.7, '#78784c')]]))
    cx, cy = x0 + w * rng.uniform(0.4, 0.6), y0 + h * rng.uniform(0.4, 0.6)
    layout = rng.choice(["cross", "diag", "curve", "loop"])
    sd = rng.randint(0, 999)
    if layout == "cross":
        kit.footpath([(x0, cy), (cx, cy + rng.uniform(-.3, .3)), (x0 + w, cy + rng.uniform(-.5, .5))], width=0.9, z=0.016, seed=sd)
        kit.footpath([(cx + rng.uniform(-.5, .5), y0), (cx, cy), (cx + rng.uniform(-.5, .5), y0 + h)], width=0.9, z=0.017, seed=sd + 1)
    elif layout == "diag":
        kit.footpath([(x0, y0), (cx, cy), (x0 + w, y0 + h)], width=0.8, z=0.016, seed=sd)
        kit.footpath([(x0 + w, y0), (cx, cy), (x0, y0 + h)], width=0.8, z=0.017, seed=sd + 1)
    elif layout == "curve":
        kit.footpath([(x0, y0 + h * 0.8), (x0 + w * 0.3, cy + 1.2), (cx, cy), (x0 + w * 0.7, cy - 1.0), (x0 + w, y0 + h * 0.2)], width=0.9, z=0.016, seed=sd)
    else:
        r = min(w, h) * 0.32
        pts = [(cx + math.cos(t / 8 * 6.283) * r * 1.3, cy + math.sin(t / 8 * 6.283) * r) for t in range(9)]
        kit.footpath(pts, width=0.8, z=0.016, seed=sd)
        kit.footpath([(cx, y0 + h), (cx, cy + r)], width=0.8, z=0.017, seed=sd + 1)
    conc = kit.mat_concrete("fount%d" % sd, rng.choice(['#9a968a', '#8a8478', '#a8a090']))
    centre = rng.choice(["fountain", "fountain", "statue", "tree", "gazebo"])
    if centre == "fountain":
        r = rng.uniform(0.8, 1.2)
        cyl(cx, cy, 0.0, 0.4, r, conc, 24)
        cyl(cx, cy, 0.25, 0.42, r - 0.12, MAT("flat:#3a3428:1.0"), 24)
        if rng.random() < 0.7:
            cyl(cx, cy, 0.4, 1.2, 0.12, conc, 10); cyl(cx, cy, 1.2, 1.3, 0.4, conc, 16)
    elif centre == "statue":
        _statue(cx, cy, conc, rng)
    elif centre == "tree":
        with P.zone(prio=2):
            P.tree(cx, cy, 0, random.Random(rng.random()), kind="dead")
        cyl(cx, cy, 0, 0.25, 0.9, conc, 20)
    else:
        _gazebo(cx, cy, rng)
    corners = [(x0 + 1.8, y0 + 1.8), (x0 + w - 2.2, y0 + 1.6), (x0 + 1.8, y0 + h - 2.0), (x0 + w - 1.9, y0 + h - 2.0)]
    rng.shuffle(corners)
    feats = rng.sample(["statue", "swings", "slide", "picnic", "picnic", "none", "planter"], 4)
    m = MAT("paint:%s:0.6" % rng.choice(["#c84a2a", "#3e6a8a", "#c8a040", "#5a8a4a"]))
    for (fx, fy), f in zip(corners, feats):
        if f == "statue" and centre != "statue":
            _statue(fx, fy, conc, rng)
        elif f == "swings":
            _swings(fx, fy, m, rng)
        elif f == "slide":
            _slide(fx, fy, m)
        elif f == "picnic":
            with P.zone(prio=2):
                P.table(fx, fy, rng.uniform(0, 90), rng)
                P.bench(fx, fy + 0.75, 0, rng)
        elif f == "planter":
            with P.zone(prio=2):
                P.planter(fx, fy, 0, rng, r=0.6)
    with P.zone(prio=1):
        for k in range(rng.randint(2, 4)):
            P.bench(cx + rng.uniform(-3, 3), cy + rng.uniform(-2.5, 2.5), rng.choice([0, 90, 180, 270]), rng)
        for k in range(rng.randint(3, 8)):
            P.tree(x0 + rng.uniform(0.5, w - 0.5), y0 + rng.uniform(0.5, h - 0.5), 0, random.Random(rng.random()), kind=rng.choice(["dead", "sparse", "sparse", "pine"]))
        for k in range(rng.randint(1, 3)):
            P.trash_can(x0 + rng.uniform(0.5, w - 0.5), y0 + rng.uniform(0.5, h - 0.5), 0, rng)
    P.scatter(x0, y0, x0 + w, y0 + h, rng.uniform(5, 10), "wild", rng, avoid=[(cx - 1.4, cy - 1.4, cx + 1.4, cy + 1.4)])
    # fence on a random side or two, with gaps where it rotted away
    for side in rng.sample(["s", "n", "e", "w"], rng.randint(0, 2)):
        n = int((w if side in "ns" else h) / 0.9) - 1
        if side == "s": P.wood_fence(x0, y0 + h, 0, rng, n=n)
        elif side == "n": P.wood_fence(x0, y0, 0, rng, n=n)
        elif side == "e": P.wood_fence(x0 + w, y0, 90, rng, n=n)
        else: P.wood_fence(x0, y0, 90, rng, n=n)


def _statue(sx, sy, conc, rng):
    z = rng.uniform(0.8, 1.2)
    box(sx - .45, sy - .45, 0, sx + .45, sy + .45, z, conc)
    bronze = MAT("paint:%s:0.3" % rng.choice(["#5a6a4a", "#4a5a50", "#6a6a58"]))
    if rng.random() < 0.75:
        body, head, wr = kit.humanoid(bronze, rng.uniform(0.9, 1.1))
        body.location += g2b(sx, sy, z)
        sphere(sx, sy, z + 1.14, 0.1, bronze)
    else:            # toppled: just the boots left on the plinth, the rest lying in the grass
        body, head, wr = kit.humanoid(bronze, 1.0)
        body.location += g2b(sx + 0.8, sy + 0.3, 0.15)
        body.rotation_euler.y = math.radians(88)


def _swings(px, py, m, rng):
    for s in (-1, 1):
        for d in (-1, 1):
            o = cyl(px + s * 1.0, py + d * 0.35, 0, 2.0, 0.035, m, 6)
            o.rotation_euler.x = math.radians(-12 * d)
    cyl(px, py, 1.95, 1.99, 0.04, m, 6, rot=(0, math.radians(90), 0)).scale = (1, 1, 50)
    for s in (-0.5, 0.5):
        if rng.random() < 0.8:
            for c in (-0.12, 0.12):
                B(px + s + c - .005, py - .005, 0.45, px + s + c + .005, py + .005, 1.95, MAT("metal:#8a8a84"))
            B(px + s - .15, py - .08, 0.42, px + s + .15, py + .08, 0.46, MAT("wood:#6a5034:#5a4028"))


def _slide(sx2, sy2, m):
    for k in range(6):
        B(sx2 - .3, sy2 + 0.6 + k * 0.08, 0.2 + k * 0.25, sx2 + .3, sy2 + 0.66 + k * 0.08, 0.24 + k * 0.25, m)
    mesh([(sx2 - .3, sy2 + 0.5, 1.5), (sx2 + .3, sy2 + 0.5, 1.5), (sx2 + .3, sy2 - 1.2, 0.1), (sx2 - .3, sy2 - 1.2, 0.1)], [(0, 1, 2, 3)], MAT("metal:#a8a8a0"), "slide", solidify=0.03)


def _gazebo(cx, cy, rng):
    wd = MAT("paint:%s:0.5" % rng.choice(["#d8d0bc", "#a8b0a0", "#c8b898"]))
    r = 1.3
    cyl(cx, cy, 0, 0.18, r + 0.1, MAT("wood:#6a5034:#5a4028"), 8)
    for k in range(8):
        a = k / 8 * 6.283
        if rng.random() < 0.9:
            cyl(cx + math.cos(a) * r, cy + math.sin(a) * r, 0.18, 2.0, 0.05, wd, 6)
    pts = [(cx + math.cos(k / 8 * 6.283) * (r + 0.25), cy + math.sin(k / 8 * 6.283) * (r + 0.25), 2.0) for k in range(8)] + [(cx, cy, 2.7)]
    mesh(pts, [(k, (k + 1) % 8, 8) for k in range(8)], MAT("paint:#7a3a2a:0.6"), "gazebo_roof", solidify=0.04)


def clinic(M, x0, y0, rng):
    """Single-storey clinic: white stucco, green cross panel, ambulance bay awning."""
    wall = kit.mat_stucco("clinic_w", '#d0ccbe', '#8a8676')
    ops = [(2.6, 3.4, 0.0, 1.6, "door")]
    for t in (0.9, 4.6, 5.8):
        ops.append((t - 0.38, t + 0.38, 0.85, 1.65, "win"))
    H = _flat_box_building(M, x0, y0, 7, 4, wall, 1, ops, [(1.5 - 0.38, 1.5 + 0.38, 0.85, 1.65, "win")])
    for (t0, t1, z0, z1, kind) in ops:
        if kind == "win":
            window(M, (x0, y0 + 4), (x0 + 7, y0 + 4), t0, t1, z0, z1, (0, 1), rng.choice(["broken", "boarded", "glass"]))
        else:
            kit.door(M, (x0, y0 + 4), (x0 + 7, y0 + 4), t0, t1, (0, 1), "barred" if False else "boarded")
    window(M, (x0 + 7, y0), (x0 + 7, y0 + 4), 1.12, 1.88, 0.85, 1.65, (1, 0), "broken")
    gcross = MAT("paint:#3e8a4a:0.35")
    box(x0 + 2.7, y0 + 4.12, 1.85, x0 + 3.3, y0 + 4.16, 2.25, MAT("paint:#e0dcd0:0.3"))
    box(x0 + 2.92, y0 + 4.16, 1.9, x0 + 3.08, y0 + 4.18, 2.2, gcross)
    box(x0 + 2.85, y0 + 4.16, 1.97, x0 + 3.15, y0 + 4.18, 2.13, gcross)
    box(x0 + 4.2, y0 + 4.0, 1.9, x0 + 6.8, y0 + 5.4, 1.98, MAT("paint:#d8d0b8:0.4"))
    for px in (x0 + 4.3, x0 + 6.7):
        cyl(px, y0 + 5.3, 0, 1.9, 0.04, MAT("metal:#8a8a84"), 6)
    P.car_wreck(x0 + 5.5, y0 + 5.8, 0, rng, style="truck")


def church(M, x0, y0, rng):
    """Small chapel with a steep roof and a bell tower."""
    wall = kit.mat_stucco("church_w", '#c8bca4', '#8a7e66')
    house(M, x0, y0, [(0, 0, 3, 6, 1)], wall, "gable", "sh_slate", door=("s", 6, 1.5, rng.choice(["closed", "open", "boarded"])))
    tx, ty = x0 + 3.65, y0 + 4.8
    box(tx - .55, ty - .55, 0, tx + .55, ty + .55, 4.2, wall)
    for (t0, t1) in ((-.2, .2),):
        box(tx + t0, ty + .55, 3.2, tx + t1, ty + .56, 3.8, M["black"])
        box(tx + .55, ty + t0, 3.2, tx + .56, ty + t1, 3.8, M["black"])
    kit.mesh([(tx - .65, ty - .65, 4.2), (tx + .65, ty - .65, 4.2), (tx + .65, ty + .65, 4.2), (tx - .65, ty + .65, 4.2), (tx, ty, 5.6)],
             [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], M["sh_slate_x"], "spire", solidify=0.04)
    box(tx - .03, ty - .03, 5.55, tx + .03, ty + .03, 6.0, MAT("metal:#7a7a74"))
    box(tx - .15, ty - .03, 5.8, tx + .15, ty + .03, 5.85, MAT("metal:#7a7a74"))
    kit.door(M, (tx - .55, ty + .55), (tx + .55, ty + .55), 0.15, 0.95, (0, 1), "open")


# ------------------------------------------------------------------ burnt-out and bombed ruins
def mat_burnt(name, base='#8a8276', soot=0.65):
    """Wall material blackened by fire: soot blooms, heaviest near the top and around openings."""
    from lib import _nodes, _coord, _noise, _ramp, _mix, _bump, grit
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    n = _noise(nt, co, 3.0, 8.0, 0.7).outputs[0]
    n2 = _noise(nt, co, 30.0, 6.0, 0.7).outputs[0]
    col = _ramp(nt, n2, [(0.3, '#4a4440'), (0.55, base), (0.8, '#a8a090')])
    sootf = _ramp(nt, n, [(1 - soot - 0.1, '#000000'), (1 - soot + 0.15, '#ffffff')])
    col = _mix(nt, col, '#1a1714', sootf)
    nt.links.new(grit(nt, col, co, 0.45, 80.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.98
    _bump(nt, bs, n2, 0.8, 0.02)
    return m


def ruin_building(M, x0, y0, w, h, rng, style="burnt", base='#8a8276', storeys=1):
    """Gutted shell: jagged broken walls (one corner left standing tall), no roof or a slab caved in,
    charred beams and rubble inside. 'bombed' adds a crater, blast debris thrown outward and scorch."""
    wall = mat_burnt("burnt%d" % rng.randint(0, 99999), base, 0.5 if style == "burnt" else 0.35)
    H = STOREY * storeys
    tall_corner = rng.choice([(x0, y0), (x0 + w, y0), (x0, y0 + h)])
    runs = [((x0, y0), (x0 + w, y0), True), ((x0, y0 + h), (x0 + w, y0 + h), True), ((x0, y0), (x0, y0 + h), False), ((x0 + w, y0), (x0 + w, y0 + h), False)]
    t_ = kit.WALL_T
    kit.solid(x0, y0, x0 + w, y0 + h, H, "ruin")
    _z = P.zone("int"); _z.__enter__()      # the ruin's own rubble and scorch belong inside it
    for (a, b, horiz) in runs:
        L = abs(b[0] - a[0]) if horiz else abs(b[1] - a[1])
        n = int(L / 0.25)
        hcur = rng.uniform(0.3, H)
        for k in range(n):
            s0, s1 = k * L / n, (k + 1) * L / n
            px, py = (a[0] + s0, a[1]) if horiz else (a[0], a[1] + s0)
            dc = math.hypot(px - tall_corner[0], py - tall_corner[1])
            target = H * (1.0 if dc < 1.2 else rng.uniform(0.05, 0.75))
            hcur = max(0.08, min(H, hcur + (target - hcur) * 0.35 + rng.uniform(-0.25, 0.25)))
            if style == "bombed" and rng.random() < 0.12:
                continue          # blown-out gap
            if horiz:
                o = box(a[0] + s0 - (t_ if k == 0 else 0), a[1] - t_, 0, a[0] + s1 + (t_ if k == n - 1 else 0), a[1] + t_, hcur, wall)
            else:
                o = box(a[0] - t_, a[1] + s0 + (t_ if k == 0 else 0), 0, a[0] + t_, a[1] + s1 - (t_ if k == n - 1 else 0), hcur, wall)
            # broken top edge: a small tilted chunk
            if rng.random() < 0.35:
                c = box(px - 0.08, py - 0.08, hcur, px + 0.08, py + 0.08, hcur + 0.08, wall)
                c.rotation_euler = (rng.uniform(-.5, .5), rng.uniform(-.5, .5), rng.uniform(0, 3))
    # floor, charred
    box(x0, y0, 0, x0 + w, y0 + h, 0.03, MAT("flat:#2a2420:1.0"))
    # collapsed roof slab leaning into the shell, charred beams
    if style == "burnt" or rng.random() < 0.5:
        sx, sy = x0 + w * rng.uniform(0.3, 0.6), y0 + h * rng.uniform(0.3, 0.6)
        mesh([(sx - 1.4, sy - 1.0, 0.2), (sx + 1.4, sy - 1.0, 0.2), (sx + 1.2, sy + 1.0, H * 0.7), (sx - 1.2, sy + 1.0, H * 0.7)],
             [(0, 1, 2, 3)], MAT("conc:#5a5650"), "slab", solidify=0.1)
    char = MAT("flat:#1a1614:0.95")
    for k in range(rng.randint(4, 9)):
        # charred beam: endpoints chosen inside the shell, so it can never poke out through a wall
        m_ = 0.3
        ax, ay = x0 + rng.uniform(m_, w - m_), y0 + rng.uniform(m_, h - m_)
        bx, by = x0 + rng.uniform(m_, w - m_), y0 + rng.uniform(m_, h - m_)
        L = math.hypot(bx - ax, by - ay)
        if L < 0.6: continue
        za, zb = rng.uniform(0.05, 0.3), rng.uniform(0.05, min(H * 0.8, 1.2))
        mx, my = (ax + bx) / 2, (ay + by) / 2
        o = box(mx - L / 2, my - 0.06, (za + zb) / 2 - 0.06, mx + L / 2, my + 0.06, (za + zb) / 2 + 0.06, char)
        o.rotation_euler = (0, -math.atan2(zb - za, L), -math.atan2(by - ay, bx - ax))
    for k in range(rng.randint(2, 4)):
        P.rubble_pile(x0 + rng.uniform(0.6, w - 0.6), y0 + rng.uniform(0.6, h - 0.6), 0, rng, size=rng.uniform(0.7, 1.4),
                      mats=[wall, MAT("conc:#6a6660"), char])
    # scorch around the building
    for k in range(rng.randint(4, 8)):
        P.stain(x0 + rng.uniform(-1, w + 1), y0 + rng.uniform(-1, h + 1), 0, rng, col="#1e1a16", r=rng.uniform(0.5, 1.0))
    _z.__exit__()
    if style == "bombed":
        cx, cy = x0 + w * rng.uniform(0.6, 1.1), y0 + h + rng.uniform(0.6, 1.6)
        crater(cx, cy, rng.uniform(1.0, 1.5), rng)
        for k in range(16):    # debris thrown outward
            a = rng.uniform(0, 6.28); d = rng.uniform(1.5, 4.5)
            s = rng.uniform(0.06, 0.18)
            o = box(cx + math.cos(a) * d - s, cy + math.sin(a) * d - s, 0, cx + math.cos(a) * d + s, cy + math.sin(a) * d + s, s * 1.2,
                    rng.choice([wall, MAT("conc:#7a7466")]), bevel=0.01)
            o.rotation_euler = (rng.uniform(-.5, .5), rng.uniform(-.5, .5), rng.uniform(0, 6))


def crater(cx, cy, r, rng):
    """Shallow blast crater: dark scorched bowl ringed with thrown-up dirt and rubble."""
    import bmesh as _bm
    bm = _bm.new()
    rings, segs = 6, 24
    vs = []
    for i in range(rings + 1):
        rr = r * (i / rings) * 1.6
        z = -0.25 * max(0.0, 1 - (i / rings * 1.6) ** 2) if i / rings * 1.6 < 1 else 0.12 * math.exp(-((i / rings * 1.6 - 1.15) ** 2) * 10)
        ring = []
        for j in range(segs):
            a = j / segs * 6.283
            jit = rng.uniform(0.9, 1.1)
            ring.append(bm.verts.new(g2b(cx + math.cos(a) * rr * jit, cy + math.sin(a) * rr * jit, z + 0.01)))
        vs.append(ring)
    for i in range(rings):
        for j in range(segs):
            bm.faces.new((vs[i][j], vs[i][(j + 1) % segs], vs[i + 1][(j + 1) % segs], vs[i + 1][j]))
    me = bpy.data.meshes.new("crater"); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("crater", me); bpy.context.scene.collection.objects.link(ob); __import__('lib').REG.append(ob)
    me.materials.append(MAT("rock:#3a332c:#221e1a"))
    for p in me.polygons: p.use_smooth = True
    for k in range(10):
        a = rng.uniform(0, 6.28)
        P.rubble_pile(cx + math.cos(a) * r * 1.3, cy + math.sin(a) * r * 1.3, 0, rng, size=0.35)


def graffiti_on(out_dir, x0, y_face, w, rng, facing="s", n=None, zmax=1.6):
    """Spray a few graffiti decals along a wall face starting at x0 (or y0 for east faces)."""
    import graffiti
    for k in range(n or rng.randint(1, 2)):
        gw = rng.uniform(1.4, 2.2)
        gx = x0 + rng.uniform(0, max(0.01, w - gw))
        gz = rng.uniform(0.15, zmax - gw * 0.5)
        if facing == "s":
            graffiti.place(out_dir, gx, y_face, gz, gw, gw * 0.5, "s", rng.randint(0, 400), offset=0.05)
        else:
            graffiti.place(out_dir, y_face, gx, gz, gw, gw * 0.5, "e", rng.randint(0, 400), offset=0.05)


# ------------------------------------------------------------------ roadside + rural
def gas_station(M, x0, y0, rng, road_y=None):
    """Atomic-age filling station: small kiosk, canopy over two pump islands, tall sign, apron to the road."""
    wall = kit.mat_stucco("gas_w%d" % rng.randint(0, 999), '#d8d0bc', '#8a8270')
    ops = [(1.1, 1.9, 0.0, 1.6, "door"), (2.3, 3.7, 0.4, 1.6, "win")]
    H = _flat_box_building(M, x0, y0, 4, 3, wall, 1, ops, [])
    shop_window(M, x0, y0 + 3, 2.3, 3.7, 0.4, 1.6, rng)
    kit.door(M, (x0, y0 + 3), (x0 + 4, y0 + 3), 1.1, 1.9, (0, 1), rng.choice(["open", "broken", "closed"]))
    apron_y1 = road_y + 0.3 if road_y is not None else y0 + 10
    kit.road(x0 - 2, y0 + 3.0, x0 + 11, apron_y1, z=0.0071, name="apron", lot=True)
    col = rng.choice(["#b84a3a", "#3a6a9a", "#c8a040"])
    cx0, cy0, cx1, cy1 = x0 + 4.8, y0 + 3.8, x0 + 10.4, y0 + 7.4
    box(cx0, cy0, 2.4, cx1, cy1, 2.62, MAT("paint:#e0d8c8:0.4"))
    box(cx0 - 0.02, cy1 - 0.02, 2.4, cx1 + 0.02, cy1 + 0.02, 2.62, MAT("paint:%s:0.5" % col))
    for (px, py) in ((cx0 + 0.6, cy0 + 0.6), (cx1 - 0.6, cy0 + 0.6), (cx0 + 0.6, cy1 - 0.6), (cx1 - 0.6, cy1 - 0.6)):
        box(px - 0.1, py - 0.1, 0, px + 0.1, py + 0.1, 2.4, MAT("paint:#d8d0bc:0.4"))
    kit.solid(cx0 + 0.4, cy0 + 0.4, cx0 + 0.8, cy0 + 0.8, 2.4, "post"); kit.solid(cx1 - 0.8, cy1 - 0.8, cx1 - 0.4, cy1 - 0.4, 2.4, "post")
    for iy in (cy0 + 1.3, cy1 - 1.3):
        box(cx0 + 1.2, iy - 0.3, 0, cx1 - 1.2, iy + 0.3, 0.15, M["conc"])
        for px in (cx0 + 1.8, cx1 - 1.8):
            if rng.random() < 0.85:
                box(px - 0.2, iy - 0.15, 0.15, px + 0.2, iy + 0.15, 1.15, MAT("paint:%s:0.5" % col), bevel=0.02)
                box(px - 0.16, iy + 0.15, 0.7, px + 0.16, iy + 0.16, 1.0, MAT("flat:#d8d0b8:0.5"))
            else:
                o = box(px - 0.2, iy - 0.15, 0.0, px + 0.2, iy + 0.15, 1.0, MAT("paint:%s:0.5" % col), bevel=0.02)
                o.rotation_euler.x = math.radians(80); o.location.z = 0.2
        kit.solid(cx0 + 1.2, iy - 0.3, cx1 - 1.2, iy + 0.3, 1.2, "island")
    sx, sy = x0 + 11.6, y0 + 8.5
    box(sx - 0.1, sy - 0.1, 0, sx + 0.1, sy + 0.1, 4.0, MAT("metal:#6a6a64"))
    cyl(sx, sy, 4.0, 4.25, 0.9, MAT("paint:%s:0.5" % col), 24, rot=(math.radians(90), 0, 0))
    kit.solid(sx - 0.15, sy - 0.15, sx + 0.15, sy + 0.15, 4.0, "post")
    with P.zone(prio=2):
        P.tire_stack(x0 - 0.6, y0 + 0.6, 0, rng); P.barrel(x0 + 4.5, y0 + 0.4, 0, rng); P.vending(x0 + 4.4, y0 + 2.4, -90, rng)
    with P.zone(prio=1):
        P.car_wreck(cx0 + 2.8, cy0 + 2.2, rng.uniform(-6, 6), rng)


def barn(M, x0, y0, rng):
    """Big red gambrel-ish barn (tall gable), hay loft door, open front."""
    red = kit.mat_planks("barn%d" % rng.randint(0, 999), rng.choice(['#8a3a2a', '#7a4a3a', '#6a5a4a']), '#5a2a1e')
    house(M, x0, y0, [(0, 0, 5, 7, 2)], red, "gable", rng.choice(["sh_slate", "sh_brown"]), door=("s", 7, 2.5, "open"), win_state="boarded")
    box(x0 + 2.0, y0 + 7 + 0.07, 2.4, x0 + 3.0, y0 + 7 + 0.09, 3.2, M["black"])
    with P.zone(prio=2):
        for k in range(rng.randint(2, 5)):
            P.crate(x0 + 5.8 + rng.uniform(0, 1.5), y0 + rng.uniform(1, 6), rng.uniform(0, 90), rng)


def silo(M, x, y, rng):
    m = kit.mat_paint_rust("silo%d" % rng.randint(0, 999), '#a8a8a0', 0.6) if hasattr(kit, "mat_paint_rust") else MAT("metal:#a8a8a0")
    cyl(x, y, 0, 5.0, 1.0, m, 24)
    sphere(x, y, 5.0, 1.0, m, scale=(1, 1, 0.6))
    kit.solid(x - 1, y - 1, x + 1, y + 1, 5.6, "silo")


def field(x0, y0, x1, y1, rng, crop=None):
    """Abandoned crop field: furrow rows (dark/light stripes) under a soft-edged patch, dead stalks."""
    crop = crop or rng.choice(["furrow", "stubble", "dead"])
    stops = {"furrow": [(0.3, '#4a3e30'), (0.5, '#5e4e3a'), (0.7, '#6e5c44')],
             "stubble": [(0.3, '#8a7a4e'), (0.5, '#9a8a5a'), (0.7, '#aa9a66')],
             "dead": [(0.3, '#6a6640'), (0.5, '#7a744a'), (0.7, '#8a8256')]}[crop]
    kit.patch(x0, y0, x1, y1, stops)
    dark = MAT("flat:#3e3428:1.0")
    y = y0 + 0.3
    while y < y1 - 0.3:
        box(x0 + 0.3, y, 0.0045, x1 - 0.3, y + 0.12, 0.0055, dark)
        y += 0.55
    with P.zone(prio=1):
        for k in range(int((x1 - x0) * (y1 - y0) / 3)):
            P.grass_tuft(rng.uniform(x0, x1), rng.uniform(y0, y1), 0, rng, n=rng.randint(3, 8))
