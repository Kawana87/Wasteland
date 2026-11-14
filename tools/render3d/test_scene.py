"""Fallout-2-style look test: one ruined building in cutaway, street, car, props, characters.

Renders a single frame at game resolution with the same camera the sprite pipeline will use,
then reduces it to a 256-colour palette.   python3 tools/render3d/test_scene.py OUT_DIR
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from lib import _nodes, _mix, _coord, _noise, _ramp
import bpy

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r3d"
os.makedirs(OUT, exist_ok=True)
R = random.Random(4)
sc = reset()

WALL_T = 0.11      # half thickness of a wall (walls are ~0.22 tile thick)
WALL_H = 2.0       # full storey
CUT_H = 0.85       # cutaway height for the near walls

M = {
    "stucco": mat_stucco("stucco"),
    "stucco_in": mat_stucco("stucco_in", '#9a9282', '#5e584e'),
    "brick": mat_brick("brick"),
    "brick_y": mat_brick("brick_y", axis='y'),
    "cap": mat_flat("cap", '#2e2a28', 0.9, noise=0.1),
    "planks": mat_planks("planks"),
    "dirt": mat_ground("dirt"),
    "asphalt": mat_asphalt("asphalt"),
    "conc": mat_concrete("conc"),
    "frame": mat_flat("frame", '#3a302a', 0.8),
    "glass": mat_flat("glass", '#2a3a40', 0.15, metal=0.2, noise=0.0),
    "door": mat_planks("door", '#5a3a2a', '#4a2e20'),
    "leather": mat_flat("leather", '#7a4a2e', 0.5, noise=0.3),
    "fabric": mat_flat("fabric", '#6a7a5a', 0.95, noise=0.25),
    "wood": mat_planks("wood", '#7a5a3a', '#6a4a2e'),
    "metal": mat_paint_rust("metal", '#7a7e78', 0.35),
    "barrel": mat_paint_rust("barrel", '#8a6a2a', 0.55),
    "car": mat_paint_rust("car", '#5e9a90', 0.3),
    "car2": mat_paint_rust("car2", '#c8bea4', 0.3),
    "chrome": mat_flat("chrome", '#c8c8c0', 0.25, metal=0.9, noise=0.0),
    "tire": mat_flat("tire", '#1e1c1a', 0.9),
    "red": mat_paint_rust("red", '#b03a26', 0.35),
    "bark": mat_flat("bark", '#4a3a2c', 0.95, noise=0.4),
    "mattress": mat_flat("mattress", '#b8ac8a', 0.95, noise=0.3),
    "skin": mat_flat("skin", '#c89070', 0.6, noise=0.1),
    "jump": mat_flat("jump", '#3a5f94', 0.7, noise=0.1),
    "yellow": mat_flat("yellow", '#d8b040', 0.6, noise=0.1),
    "hair": mat_flat("hair", '#4a3424', 0.9, noise=0.2),
    "boots": mat_flat("boots", '#2e2420', 0.7, noise=0.1),
    "leath2": mat_flat("leath2", '#4a3022', 0.6, noise=0.25),
    "pants": mat_flat("pants", '#3a3632', 0.9, noise=0.2),
    "spike": mat_flat("spike", '#a8a49a', 0.3, metal=0.8, noise=0.0),
    "rubble": mat_concrete("rubble", '#8a8276'),
    "paper": mat_flat("paper", '#d8d0b8', 0.9, noise=0.2),
}

# ------------------------------------------------------------------ ground: dirt, sidewalk with curb, road
box(-12, -12, -0.1, 26, 26, 0.0, M["dirt"], name="ground")
box(-12, 9.0, -0.02, 26, 12.2, 0.006, M["asphalt"], name="road")
box(-12, 8.0, 0.0, 26, 9.0, 0.07, M["conc"], bevel=0.02, name="sidewalk")
for k in range(-6, 20):    # slab joints
    box(k - 0.01, 8.0, 0.07, k + 0.01, 9.0, 0.072, M["cap"], name="joint")
box(-12, 12.2, 0.0, 26, 13.0, 0.07, M["conc"], bevel=0.02, name="sidewalk2")


# ------------------------------------------------------------------ walls
def wall(x0, y0, x1, y1, h, mat_out, mat_in=None, openings=(), cap=True, name="wall"):
    """Wall along a tile edge from (x0,y0) to (x1,y1), axis aligned. openings: (t0, t1, z0, z1) along its length."""
    horiz = abs(y1 - y0) < 1e-6
    L = abs(x1 - x0) if horiz else abs(y1 - y0)
    cuts = sorted(openings)
    # split the wall into vertical slabs around openings
    def slab(t0, t1, z0, z1):
        if t1 - t0 < 1e-4 or z1 - z0 < 1e-4:
            return
        if horiz:
            a = min(x0, x1)
            box(a + t0, y0 - WALL_T, z0, a + t1, y0 + WALL_T, z1, mat_out, name=name)
        else:
            a = min(y0, y1)
            box(x0 - WALL_T, a + t0, z0, x0 + WALL_T, a + t1, z1, mat_out, name=name)
    t = 0.0
    for (o0, o1, oz0, oz1) in cuts:
        slab(t, o0, 0, h)
        slab(o0, o1, 0, min(oz0, h))
        slab(o0, o1, min(oz1, h), h)
        # frame around the opening
        if oz1 <= h:
            fr = 0.05
            if horiz:
                a = min(x0, x1)
                box(a + o0 - fr, y0 - WALL_T - .02, oz0 - fr, a + o0, y0 + WALL_T + .02, oz1 + fr, M["frame"], name="frame")
                box(a + o1, y0 - WALL_T - .02, oz0 - fr, a + o1 + fr, y0 + WALL_T + .02, oz1 + fr, M["frame"], name="frame")
                box(a + o0, y0 - WALL_T - .02, oz1, a + o1, y0 + WALL_T + .02, oz1 + fr, M["frame"], name="frame")
                if oz0 > 0.05:
                    box(a + o0 - fr, y0 - WALL_T - .05, oz0 - fr, a + o1 + fr, y0 + WALL_T + .05, oz0, M["frame"], name="sill")
            else:
                a = min(y0, y1)
                box(x0 - WALL_T - .02, a + o0 - fr, oz0 - fr, x0 + WALL_T + .02, a + o0, oz1 + fr, M["frame"], name="frame")
                box(x0 - WALL_T - .02, a + o1, oz0 - fr, x0 + WALL_T + .02, a + o1 + fr, oz1 + fr, M["frame"], name="frame")
                box(x0 - WALL_T - .02, a + o0, oz1, x0 + WALL_T + .02, a + o1, oz1 + fr, M["frame"], name="frame")
                if oz0 > 0.05:
                    box(x0 - WALL_T - .05, a + o0 - fr, oz0 - fr, x0 + WALL_T + .05, a + o1 + fr, oz0, M["frame"], name="sill")
        t = o1
    slab(t, L, 0, h)
    if cap:   # dark flat top, like Fallout's cut walls
        if horiz:
            box(min(x0, x1) - WALL_T, y0 - WALL_T - .005, h, max(x0, x1) + WALL_T, y0 + WALL_T + .005, h + 0.02, M["cap"], name="cap")
        else:
            box(x0 - WALL_T - .005, min(y0, y1) - WALL_T, h, x0 + WALL_T + .005, max(y0, y1) + WALL_T, h + 0.02, M["cap"], name="cap")


def window(x0, y0, x1, y1, t0, t1, z0, z1):
    horiz = abs(y1 - y0) < 1e-6
    a = min(x0, x1) if horiz else min(y0, y1)
    # dark glass, some panes broken (missing)
    n = 3
    for i in range(n):
        if R.random() < 0.35:
            continue
        s0 = t0 + (t1 - t0) * i / n + 0.01
        s1 = t0 + (t1 - t0) * (i + 1) / n - 0.01
        if horiz:
            box(a + s0, y0 - 0.01, z0, a + s1, y0 + 0.01, z1, M["glass"], name="glass")
        else:
            box(x0 - 0.01, a + s0, z0, x0 + 0.01, a + s1, z1, M["glass"], name="glass")
    for i in range(1, n):
        s = t0 + (t1 - t0) * i / n
        if horiz:
            box(a + s - .015, y0 - .03, z0, a + s + .015, y0 + .03, z1, M["frame"], name="mullion")
        else:
            box(x0 - .03, a + s - .015, z0, x0 + .03, a + s + .015, z1, M["frame"], name="mullion")


# building footprint x 1..9, y 1..7.  North (y=1) and west (x=1) walls are full height (we look into the room),
# south (y=7) and east (x=9) walls are cut away to CUT_H so you can see in.
WIN = (0.0, 0.0, 0.9, 1.7)
wall(1, 1, 9, 1, WALL_H, M["stucco_in"], openings=[(1.2, 2.0, 0.9, 1.7), (4.6, 5.4, 0.9, 1.7), (6.4, 7.2, 0.9, 1.7)])
for (t0, t1) in ((1.2, 2.0), (4.6, 5.4), (6.4, 7.2)):
    window(1, 1, 9, 1, t0, t1, 0.9, 1.7)
wall(1, 1, 1, 7, WALL_H, M["stucco_in"], openings=[(1.0, 1.8, 0.0, 1.55), (3.8, 4.6, 0.9, 1.7)])
window(1, 1, 1, 7, 3.8, 4.6, 0.9, 1.7)
box(1 - 0.08, 2.0, 0.0, 1 - 0.02, 2.8, 1.55, M["door"], name="door_closed")   # a closed door in the west wall
wall(1, 7, 9, 7, CUT_H, M["brick"], openings=[(2.0, 2.8, 0.0, 1.55), (5.0, 5.8, 0.5, 1.7)])
wall(9, 1, 9, 7, CUT_H, M["brick_y"], openings=[(2.2, 3.0, 0.5, 1.7)])
# interior walls: full height at the back, a room divider with a doorway
wall(5, 1, 5, 4, WALL_H, M["stucco_in"], openings=[(1.6, 2.4, 0.0, 1.55)])
wall(5, 4, 9, 4, WALL_H, M["stucco_in"], openings=[(0.8, 1.6, 0.0, 1.55)])
# collapsed corner: broken wall stubs and rubble at the south-east
box(1, 1, 0.0, 9, 7, 0.03, M["planks"], name="floor")
for k in range(26):
    x, y = R.uniform(7.0, 9.6), R.uniform(5.6, 7.6)
    s = R.uniform(0.06, 0.2)
    ob = box(x - s, y - s, 0, x + s, y + s * 0.8, R.uniform(0.05, 0.25), M["rubble"], bevel=0.02, name="rubble")
    ob.rotation_euler = (R.uniform(-.3, .3), R.uniform(-.3, .3), R.uniform(0, 6.3))

# ------------------------------------------------------------------ furniture
def couch(x, y):
    box(x, y, 0.1, x + 1.2, y + 0.5, 0.35, M["leather"], bevel=0.05)
    box(x, y, 0.35, x + 1.2, y + 0.16, 0.75, M["leather"], bevel=0.05)
    box(x - 0.02, y, 0.1, x + 0.14, y + 0.5, 0.55, M["leather"], bevel=0.05)
    box(x + 1.06, y, 0.1, x + 1.22, y + 0.5, 0.55, M["leather"], bevel=0.05)
    for (a, b) in ((x + .1, y + .1), (x + 1.1, y + .1), (x + .1, y + .4), (x + 1.1, y + .4)):
        box(a - .03, b - .03, 0, a + .03, b + .03, 0.1, M["frame"])

def table(x, y, w=0.9, d=0.6, round_=False):
    if round_:
        cyl(x, y, 0.62, 0.66, 0.45, M["wood"], 24)
        cyl(x, y, 0.0, 0.62, 0.05, M["frame"])
        cyl(x, y, 0.0, 0.03, 0.22, M["frame"], 16)
    else:
        box(x, y, 0.6, x + w, y + d, 0.66, M["wood"], bevel=0.01)
        for (a, b) in ((x + .05, y + .05), (x + w - .05, y + .05), (x + .05, y + d - .05), (x + w - .05, y + d - .05)):
            box(a - .03, b - .03, 0, a + .03, b + .03, 0.6, M["wood"])

def chair(x, y, ang=0):
    obs = [box(x - .18, y - .18, 0.38, x + .18, y + .18, 0.43, M["wood"]),
           box(x - .18, y - .18, 0.43, x + .18, y - .14, 0.85, M["wood"])]
    for (a, b) in ((-.15, -.15), (.15, -.15), (-.15, .15), (.15, .15)):
        obs.append(box(x + a - .02, y + b - .02, 0, x + a + .02, y + b + .02, 0.38, M["wood"]))
    for o in obs:
        rot_z(o, ang, (x, y))

def shelf(x, y, w=1.0):
    box(x, y, 0, x + w, y + 0.32, 1.7, M["wood"], bevel=0.01)
    cols = [M["red"], M["fabric"], M["paper"], M["jump"], M["yellow"], M["leath2"]]
    for k in range(4):
        z = 0.1 + k * 0.4
        box(x + 0.04, y + 0.3, z, x + w - 0.04, y + 0.33, z + 0.34, M["frame"])
        xx = x + 0.06
        while xx < x + w - 0.1:
            bw = R.uniform(0.04, 0.09)
            if R.random() < 0.8:
                box(xx, y + 0.06, z + 0.02, xx + bw, y + 0.3, z + R.uniform(0.2, 0.32), R.choice(cols))
            xx += bw + 0.01

def bed(x, y):
    box(x, y, 0.15, x + 0.9, y + 1.9, 0.3, M["wood"], bevel=0.02)
    box(x + 0.03, y + 0.03, 0.3, x + 0.87, y + 1.87, 0.45, M["mattress"], bevel=0.05)
    box(x, y, 0.0, x + 0.9, y + 0.08, 0.8, M["wood"], bevel=0.02)
    box(x + 0.1, y + 0.12, 0.45, x + 0.8, y + 0.45, 0.55, M["paper"], bevel=0.05)
    box(x + 0.03, y + 0.9, 0.45, x + 0.87, y + 1.88, 0.5, M["fabric"], bevel=0.03)

def fridge(x, y):
    box(x, y, 0, x + 0.6, y + 0.6, 1.6, mat_paint_rust("fridge", '#b8b09a', 0.3), bevel=0.08)
    box(x + 0.5, y + 0.6, 0.9, x + 0.53, y + 0.64, 1.3, M["chrome"])

def barrel(x, y, mat=None):
    cyl(x, y, 0, 0.85, 0.28, mat or M["barrel"], 20)
    for z in (0.15, 0.7):
        cyl(x, y, z, z + 0.04, 0.29, M["frame"], 20)

def crate(x, y, s=0.5, h=0.5):
    box(x, y, 0, x + s, y + s, h, M["wood"], bevel=0.02)

couch(2.0, 1.25)
table(3.0, 3.3, round_=True)
chair(2.4, 3.5, 90)
chair(3.6, 2.8, -30)
shelf(1.2, 4.9 - 0.5 if False else 5.6, 1.0) if False else None
shelf(3.2, 1.2, 1.4)
bed(7.8, 1.3)
fridge(5.3, 4.3)
box(6.0, 4.25, 0, 7.4, 4.8, 0.9, M["wood"], bevel=0.01)          # kitchen counter
box(5.95, 4.2, 0.9, 7.45, 4.85, 0.95, M["conc"])
box(6.2, 4.3, 0.95, 6.6, 4.6, 1.0, M["metal"])
barrel(1.5, 6.3); barrel(2.05, 6.45, M["metal"])
crate(5.6, 1.3); crate(5.65, 1.35, 0.4, 0.95)
for k in range(10):   # scattered papers / junk
    x, y = R.uniform(1.5, 8.5), R.uniform(1.5, 6.5)
    box(x, y, 0.02, x + 0.15, y + 0.1, 0.025, M["paper"])

# ------------------------------------------------------------------ street props
def car(x, y, ang):
    obs = []
    L, W = 1.35, 0.55
    obs.append(box(x - L, y - W, 0.22, x + L, y + W, 0.55, M["car"], bevel=0.12))
    obs.append(box(x - 0.55, y - W + 0.07, 0.5, x + 0.45, y + W - 0.07, 0.86, M["glass"], bevel=0.1))
    obs.append(box(x - 0.45, y - W + 0.05, 0.84, x + 0.3, y + W - 0.05, 0.93, M["car2"], bevel=0.04))
    for (a, b) in ((-0.5, -W + 0.08), (0.38, -W + 0.08), (-0.5, W - 0.08), (0.38, W - 0.08)):
        obs.append(box(x + a - 0.03, y + b - 0.03, 0.55, x + a + 0.03, y + b + 0.03, 0.86, M["car2"]))
    for v in (-W + 0.08, W - 0.08):
        f = box(x - L, y + v - 0.04, 0.5, x - L + 0.5, y + v + 0.04, 0.68, M["car"], bevel=0.03)
        obs.append(f)
    obs.append(box(x + L - 0.02, y - W, 0.22, x + L + 0.06, y + W, 0.34, M["chrome"], bevel=0.02))
    obs.append(box(x - L - 0.06, y - W, 0.22, x - L + 0.02, y + W, 0.34, M["chrome"], bevel=0.02))
    for (a, b) in ((-0.82, -W), (0.82, -W), (-0.82, W), (0.82, W)):
        t = cyl(x + a, y + b, 0.0, 0.0001, 0.2, M["tire"], 20)
        bpy.ops.object.delete()
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=0.22, depth=0.16, location=g2b(x + a, y + b, 0.22),
                                            rotation=(math.radians(90), 0, 0))
        w = bpy.context.active_object; w.data.materials.append(M["tire"]); bpy.ops.object.shade_smooth()
        obs.append(w)
    for o in obs:
        rot_z(o, ang, (x, y))

car(3.5, 10.3, 12)
car(12.0, 11.0, 168)

def hydrant(x, y):
    cyl(x, y, 0.07, 0.6, 0.11, M["red"])
    sphere(x, y, 0.6, 0.11, M["red"])
    cyl(x, y, 0.38, 0.45, 0.16, M["red"], rot=None)

def lamp(x, y):
    cyl(x, y, 0.07, 3.0, 0.05, M["metal"], 10)
    box(x - 0.04, y - 0.04, 2.95, x + 0.7, y + 0.04, 3.0, M["metal"])
    sphere(x + 0.7, y, 2.9, 0.12, mat_flat("bulb", '#f0e6b8', 0.3, emit='#f0d890', noise=0))

def fence(x0, y, n):
    for i in range(n + 1):
        box(x0 + i * 0.9 - .04, y - .04, 0, x0 + i * 0.9 + .04, y + .04, 0.95, M["wood"])
    for z in (0.35, 0.75):
        box(x0, y - .02, z, x0 + n * 0.9, y + .02, z + 0.1, M["wood"])

def dead_tree(x, y):
    cyl(x, y, 0, 1.8, 0.09, M["bark"], 8)
    for (a, h, l) in ((40, 1.2, 0.8), (160, 1.5, 0.7), (260, 1.0, 0.6), (320, 1.7, 0.5)):
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.035, depth=l,
            location=g2b(x + math.cos(math.radians(a)) * l * 0.35, y + math.sin(math.radians(a)) * l * 0.35, h + l * 0.3),
            rotation=(math.radians(50) * math.sin(math.radians(a)), math.radians(50) * math.cos(math.radians(a)), 0))
        bpy.context.active_object.data.materials.append(M["bark"])

hydrant(7.5, 8.4)
lamp(10.3, 8.5)
fence(10.0, 3.0, 4)
dead_tree(11.5, 6.0)
barrel(10.6, 7.0, M["metal"]); barrel(11.0, 7.4)
crate(-1.5, 7.2)
for k in range(30):     # junk on the ground outside
    x, y = R.uniform(-3, 14), R.uniform(-2, 13)
    if 0.8 < x < 9.2 and 0.8 < y < 7.2:
        continue
    s = R.uniform(0.04, 0.14)
    ob = box(x - s, y - s, 0, x + s, y + s, R.uniform(0.03, 0.15), R.choice([M["rubble"], M["rubble"], M["metal"], M["paper"]]), bevel=0.01, name="junk")
    ob.rotation_euler = (R.uniform(-.4, .4), R.uniform(-.4, .4), R.uniform(0, 6.3))
def bush(x, y):
    for k in range(9):
        a = R.uniform(0, 6.28)
        l = R.uniform(0.25, 0.5)
        bpy.ops.mesh.primitive_cylinder_add(vertices=4, radius=0.012, depth=l,
            location=g2b(x + math.cos(a) * l * 0.3, y + math.sin(a) * l * 0.3, l * 0.4),
            rotation=(math.sin(a) * 0.9, math.cos(a) * 0.9, 0))
        bpy.context.active_object.data.materials.append(M["bark"])
for (bx, by) in ((-2, 2), (12.5, 1.5), (6, -1.5), (-3, 6), (13, 8.5)):
    bush(bx, by)
for (tx, ty, tz) in ((-0.5, 7.4, 0.08), (-0.5, 7.4, 0.24), (-0.1, 7.7, 0.08)):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.2, minor_radius=0.08, location=g2b(tx, ty, tz))
    bpy.context.active_object.data.materials.append(M["tire"])
scorch = mat_flat("scorch", '#2a2420', 1.0, noise=0.5)
box(2.5, 11.0, 0.006, 3.6, 11.7, 0.008, scorch)
# tyre
bpy.ops.mesh.primitive_torus_add(major_radius=0.2, minor_radius=0.08, location=g2b(8.6, 9.6, 0.08))
bpy.context.active_object.data.materials.append(M["tire"])


# ------------------------------------------------------------------ characters
def mat_two(name, top, bottom, zcut):
    """Clothing: one colour above zcut (object space), another below."""
    m, nt, bs = _nodes(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    cmp = nt.nodes.new("ShaderNodeMath"); cmp.operation = 'GREATER_THAN'
    nt.links.new(sep.outputs[2], cmp.inputs[0]); cmp.inputs[1].default_value = zcut
    col = _mix(nt, bottom, top, cmp.outputs[0])
    co = _coord(nt)
    n = _noise(nt, co, 25.0, 6.0, 0.6)
    folds = _ramp(nt, n.outputs[0], [(0.3, '#9a9a9a'), (0.7, '#ffffff')])
    mm = nt.nodes.new("ShaderNodeMix"); mm.data_type = 'RGBA'; mm.blend_type = 'MULTIPLY'; mm.inputs[0].default_value = 0.5
    nt.links.new(col, mm.inputs[6]); nt.links.new(folds, mm.inputs[7])
    nt.links.new(mm.outputs[2], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.8
    return m

CLOTH = {"player": mat_two("c_player", '#3a5f94', '#34588a', 0.5), "raider": mat_two("c_raider", '#5a3a28', '#2e2a28', 0.53)}

def person(x, y, ang, kind="player", walk=0.0):
    """Organic low-poly figure (skin modifier over a joint skeleton), ~1.2 tiles tall.
    walk = -1..1 swings legs and arms."""
    sw = walk * 0.16
    J = [(0, 0, 0.55), (0, 0, 0.74), (0, 0, 0.92), (0, 0, 1.03)]                    # pelvis spine chest neck
    E = [(0, 1), (1, 2), (2, 3)]
    R_ = [(0.12, 0.085), (0.105, 0.075), (0.145, 0.085), (0.045, 0.045)]
    for side in (-1, 1):
        f = sw * side
        base = len(J)
        J += [(side * 0.085, 0, 0.52), (side * 0.09, f * 0.6, 0.29), (side * 0.09, f * 1.1, 0.07), (side * 0.09, f * 1.1 + 0.08, 0.04)]
        E += [(0, base), (base, base + 1), (base + 1, base + 2), (base + 2, base + 3)]
        R_ += [(0.07, 0.07), (0.055, 0.055), (0.045, 0.045), (0.04, 0.03)]
    for side in (-1, 1):
        f = -sw * side
        base = len(J)
        J += [(side * 0.17, 0, 0.97), (side * 0.2, f * 0.6, 0.76), (side * 0.21, f * 1.1, 0.57)]
        E += [(2, base), (base, base + 1), (base + 1, base + 2)]
        R_ += [(0.055, 0.055), (0.042, 0.042), (0.033, 0.033)]
    me = bpy.data.meshes.new("body")
    me.from_pydata([g2b(*j) for j in J], E, [])
    ob = bpy.data.objects.new("body", me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.modifiers.new("skin", 'SKIN')
    for i, r in enumerate(R_):
        me.skin_vertices[0].data[i].radius = r
    me.skin_vertices[0].data[0].use_root = True
    sub = ob.modifiers.new("sub", 'SUBSURF'); sub.levels = 2; sub.render_levels = 2
    me.materials.append(CLOTH[kind])
    for poly in me.polygons: poly.use_smooth = True
    obs = [ob]
    # head, hands, boots
    obs.append(sphere(x * 0, 0, 1.14, 0.095, M["skin"], scale=(0.95, 1.0, 1.12)))
    for side in (-1, 1):
        f = -sw * side
        obs.append(sphere(side * 0.21, f * 1.15, 0.53, 0.035, M["skin"]))
        lf = sw * side
        obs.append(box(side * 0.09 - 0.05, lf * 1.1 - 0.06, 0.0, side * 0.09 + 0.05, lf * 1.1 + 0.12, 0.1, M["boots"], bevel=0.03))
    if kind == "player":
        obs.append(sphere(0, -0.01, 1.19, 0.095, M["hair"], scale=(1.02, 1.05, 0.75)))
        obs.append(box(-0.11, -0.19, 0.64, 0.11, -0.08, 0.96, M["leather"], bevel=0.04))     # backpack
        obs.append(box(-0.02, 0.083, 0.58, 0.02, 0.095, 1.0, M["yellow"]))                  # suit stripe
        obs.append(box(-0.13, -0.09, 1.0, 0.13, 0.09, 1.04, M["yellow"], bevel=0.02))       # collar
    else:
        for side in (-1, 1):
            obs.append(box(side * 0.15 - 0.08, -0.1, 0.95, side * 0.15 + 0.08, 0.1, 1.06, M["metal"], bevel=0.03))
            bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=0.025, depth=0.1, location=g2b(side * 0.19, 0, 1.11))
            c = bpy.context.active_object; c.data.materials.append(M["spike"]); obs.append(c)
        obs.append(box(-0.015, -0.1, 1.17, 0.015, 0.08, 1.3, M["red"]))                     # mohawk
        obs.append(box(-0.14, -0.1, 0.5, 0.14, 0.1, 0.56, M["leath2"]))                    # belt
    for o in obs:
        o.location += g2b(x, y, 0)
        rot_z(o, ang, (x, y))
    return obs

person(4.2, 5.8, 200, "player", 0.6)
person(6.5, 2.5, 30, "raider", 0.0)
person(10.0, 10.0 - 0.6, 250, "raider", -0.6)

# ------------------------------------------------------------------ light, camera, render
lights()
camera(5.2, 6.2, 768, 432, 0.4)
sc.cycles.samples = 64
sc.render.filepath = os.path.join(OUT, "scene_raw.png")
bpy.ops.render.render(write_still=True)
print("rendered", sc.render.filepath)

# ------------------------------------------------------------------ character sprite sheet: 8 directions + walk frames
from PIL import Image
for ob in list(bpy.data.objects):
    if ob.type == 'MESH':
        bpy.data.objects.remove(ob, do_unlink=True)
sc.render.film_transparent = True
camera(0, 0, 64, 96, 0.7)
sc.cycles.samples = 48
frames = []
for kind in ("player", "raider"):
    row = []
    for d in range(8):
        for ob in list(bpy.data.objects):
            if ob.type == 'MESH':
                bpy.data.objects.remove(ob, do_unlink=True)
        person(0, 0, d * 45, kind, [0.0, 0.6, 0.0, -0.6][d % 4] if kind == "player" else 0.0)
        sc.render.filepath = os.path.join(OUT, f"_c_{kind}_{d}.png")
        bpy.ops.render.render(write_still=True)
        row.append(Image.open(sc.render.filepath))
    frames.append(row)
sheet = Image.new("RGBA", (64 * 8, 96 * 2), (0, 0, 0, 0))
for j, row in enumerate(frames):
    for i, im in enumerate(row):
        sheet.paste(im, (i * 64, j * 96))
sheet.save(os.path.join(OUT, "chars_raw.png"))
print("chars done")
