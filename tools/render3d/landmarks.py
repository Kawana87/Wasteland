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
        for k in range(int((t1 - t0) / 0.35)):
            o = box(x0 + t0 + k * 0.35, y + 0.13, z0 - 0.05, x0 + t0 + k * 0.35 + 0.28, y + 0.15, z1 + 0.05, M["board"])
            o.rotation_euler.y = math.radians(rng.uniform(-6, 6))
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
            P.roof_clutter(x + w / 2, y0 + h / 2, 0, rng, z=H + 0.06)
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


def mall(M, x0, y0, rng, lot_rows=2):
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
    P.roof_clutter(x0 + 4, y0 + 3, 0, rng, z=H + 0.06); P.roof_clutter(x0 + 10, y0 + 3.5, 0, rng, z=H + 0.06)
    # parking lot: asphalt, painted bays, light poles, wrecks and carts
    lot_y0, lot_y1 = y0 + h + 1.8, y0 + h + 1.8 + 3.2 * lot_rows
    box(x0 - 1, lot_y0, 0.0, x0 + w + 1, lot_y1, 0.007, M["asphalt"])
    paint = MAT("flat:#c8c0a0:0.8")
    for r in range(lot_rows):
        yy = lot_y0 + 0.3 + r * 3.2
        for k in range(12):
            box(x0 + k * 1.2, yy, 0.007, x0 + k * 1.2 + 0.05, yy + 1.9, 0.009, paint)
    for k in range(int(w / 4.5) + 1):
        P.lamp_post(x0 + 1 + k * 4.5, lot_y0 + 2.6, 0, rng)
    for k in range(5):
        P.car_wreck(x0 + rng.uniform(0.5, w - 0.5), lot_y0 + 1.25 + 3.2 * rng.randint(0, lot_rows - 1), 90 + rng.uniform(-8, 8), rng)
    for k in range(4):
        P.shopping_cart(x0 + rng.uniform(0, w), rng.uniform(lot_y0, lot_y1), rng.uniform(0, 360), rng)
    P.litter(x0 + w / 2, (lot_y0 + lot_y1) / 2, 0, rng, n=30, r=6)
    return lot_y1


def park(M, x0, y0, w, h, rng):
    """Overgrown city park: dead lawn, paths, dry fountain, playground, benches, a statue."""
    grass = kit.mat_ground("parkgrass", '#6a6a3e', '#4e4e2e', '#7e7a4e', 4.0)
    box(x0, y0, 0.0, x0 + w, y0 + h, 0.012, grass)
    cx, cy = x0 + w / 2, y0 + h / 2
    kit.footpath([(x0, cy), (cx - 1.5, cy + 0.2), (cx, cy), (cx + 1.6, cy - 0.2), (x0 + w, cy)], width=0.9, z=0.016, seed=1)
    kit.footpath([(cx, y0), (cx + 0.2, cy - 1.5), (cx, cy), (cx - 0.3, cy + 1.6), (cx, y0 + h)], width=0.9, z=0.017, seed=2)
    # dry fountain
    conc = kit.mat_concrete("fount", '#9a968a')
    cyl(cx, cy, 0.0, 0.4, 1.0, conc, 24)
    cyl(cx, cy, 0.25, 0.42, 0.88, MAT("flat:#3a3428:1.0"), 24)
    cyl(cx, cy, 0.4, 1.2, 0.12, conc, 10)
    cyl(cx, cy, 1.2, 1.3, 0.4, conc, 16)
    # statue on a plinth
    sx, sy = x0 + 1.6, y0 + 1.6
    box(sx - .45, sy - .45, 0, sx + .45, sy + .45, 1.0, conc)
    bronze = MAT("paint:#5a6a4a:0.3")
    body, head, wr = kit.humanoid(bronze, 1.0)
    for o in [body]:
        o.location += g2b(sx, sy, 1.0)
    sphere(sx, sy, 2.14, 0.1, bronze)
    # playground: swing frame + slide
    px, py = x0 + w - 2.5, y0 + 1.5
    m = MAT("paint:%s:0.6" % rng.choice(["#c84a2a", "#3e6a8a", "#c8a040"]))
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
    sx2, sy2 = x0 + w - 1.5, y0 + h - 2.0
    for k in range(6):
        B(sx2 - .3, sy2 + 0.6 + k * 0.08, 0.2 + k * 0.25, sx2 + .3, sy2 + 0.66 + k * 0.08, 0.24 + k * 0.25, m)
    mesh([(sx2 - .3, sy2 + 0.5, 1.5), (sx2 + .3, sy2 + 0.5, 1.5), (sx2 + .3, sy2 - 1.2, 0.1), (sx2 - .3, sy2 - 1.2, 0.1)], [(0, 1, 2, 3)], MAT("metal:#a8a8a0"), "slide", solidify=0.03)
    for (bx, by, r) in ((cx - 2.2, cy - 1.0, 0), (cx + 2.2, cy + 1.0, 180), (cx - 1.0, cy + 2.4, 90)):
        P.bench(bx, by, r, rng)
    for k in range(6):
        P.tree(x0 + rng.uniform(0.5, w - 0.5), y0 + rng.uniform(0.5, h - 0.5), 0, random.Random(rng.random()), kind=rng.choice(["dead", "sparse", "sparse"]))
    for k in range(3):
        P.trash_can(x0 + rng.uniform(0.5, w - 0.5), y0 + rng.uniform(0.5, h - 0.5), 0, rng)
    P.scatter(x0, y0, x0 + w, y0 + h, 8, "wild", rng, avoid=[(cx - 1.2, cy - 1.2, cx + 1.2, cy + 1.2)])
    barbed = False
    P.wood_fence(x0, y0 + h, 0, rng, n=int(w / 0.9) - 1)


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
                o = box(a[0] - t_, a[1] + s0 - (t_ if k == 0 else 0), 0, a[0] + t_, a[1] + s1 + (t_ if k == n - 1 else 0), hcur, wall)
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
        bx, by = x0 + rng.uniform(0.3, w - 0.3), y0 + rng.uniform(0.3, h - 0.3)
        o = box(bx - 0.06, by - rng.uniform(0.6, 1.4), 0.05, bx + 0.06, by + rng.uniform(0.6, 1.4), 0.17, char)
        o.rotation_euler = (rng.uniform(-0.6, 0.6), rng.uniform(-0.3, 0.3), rng.uniform(0, 3.14))
        o.location.z += rng.uniform(0, 0.6)
    for k in range(rng.randint(2, 4)):
        P.rubble_pile(x0 + rng.uniform(0.6, w - 0.6), y0 + rng.uniform(0.6, h - 0.6), 0, rng, size=rng.uniform(0.7, 1.4),
                      mats=[wall, MAT("conc:#6a6660"), char])
    # scorch around the building
    for k in range(rng.randint(4, 8)):
        P.stain(x0 + rng.uniform(-1, w + 1), y0 + rng.uniform(-1, h + 1), 0, rng, col="#1e1a16", r=rng.uniform(0.5, 1.0))
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
    ob = bpy.data.objects.new("crater", me); bpy.context.scene.collection.objects.link(ob)
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
