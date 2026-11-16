"""Player-buildable base pieces, rendered in Blender.

Walls sit on tile EDGES exactly like building walls: canvas 28x60, anchor [2,45] for the x axis and [26,45]
for the y axis, origin at the segment start, one tile long. Rotating a piece = switching axis. Floors are
48x24 diamonds anchored at [24,0] like floor_* tiles.

Names:  bw_<mat>_<piece>_<axis>   mat in scrap|wood|stone|concrete|fence
        piece in wall|window|doorway|door|half|gate (fence: wall|gate)
        bf_<mat>                  floors: scrap|wood|stone|concrete
python3 port_build.py [mat ...]"""
import sys, os, math, random, zlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from lib import reset, lights, mat_flat
import fast as FAST
import port_common as PC
from port_common import gz

H = gz(28)                      # one storey, same as building walls
HALF = gz(11)
T = 0.04                        # half thickness of a solid wall
TIERS = ("scrap", "wood", "stone", "concrete")
PIECES = ("wall", "window", "doorway", "door", "half", "gate")


class Wall:
    """Boxes in wall-local coords: u along the edge 0..1, w across (+w faces the camera), z up."""
    def __init__(self, axis):
        self.axis = axis
        self.b = FAST.Batch("bw")

    def box(self, u0, u1, w0, w1, z0, z1, mat, tilt=0.0, lean=0.0):
        cu, cw, cz = (u0 + u1) / 2, (w0 + w1) / 2, (z0 + z1) / 2
        su, sw, sz = abs(u1 - u0), abs(w1 - w0), abs(z1 - z0)
        if min(su, sw, sz) < 1e-5:
            return
        if self.axis == "x":
            self.b.cube(Vector((cu, -cw, cz)), (su, sw, sz), mat, rot=(lean, tilt, 0))
        else:
            self.b.cube(Vector((cw, -cu, cz)), (sw, su, sz), mat, rot=(tilt, -lean, 0))

    def done(self):
        return self.b.done()


M = {}
def mat(name, col, rough=0.8, metal=0.0, noise=0.15):
    if name not in M:
        M[name] = mat_flat("b_" + name, col, rough, metal=metal, noise=noise)
    return M[name]


def opening_for(piece):
    if piece == "window":
        return (0.3, 0.7, gz(13), gz(20))                 # a firing slit / small window
    if piece in ("doorway", "door"):
        return (0.28, 0.72, 0.0, gz(20))
    if piece == "gate":
        return (0.06, 0.94, 0.0, gz(21))
    return None


# ------------------------------------------------------------------ materials per tier
def solid_spans(op, top):
    """Pieces of the wall face around an opening: list of (u0, u1, z0, z1)."""
    if op is None:
        return [(0.0, 1.0, 0.0, top)]
    o0, o1, z0, z1 = op
    out = [(0.0, o0, 0.0, top), (o1, 1.0, 0.0, top)]
    if z0 > 0: out.append((o0, o1, 0.0, z0))
    if z1 < top: out.append((o0, o1, z1, top))
    return out


def scrap(W, piece, rng, top):
    """Corrugated sheets of mismatched colour, lapped and bolted to rough posts."""
    cols = ["#8a5a3e", "#7a7468", "#6e8a86", "#9a6a40", "#5e6458", "#a08a5a"]
    post = mat("scrap_post", "#4a3a2a", 0.9)
    op = opening_for(piece)
    for (u0, u1, z0, z1) in solid_spans(op, top):
        u = u0
        while u < u1 - 1e-3:
            w = min(u1 - u, rng.uniform(0.22, 0.34))
            c = mat("scrap_%d" % rng.randrange(len(cols)), rng.choice(cols), 0.6, 0.35)
            off = rng.uniform(-0.006, 0.006)
            W.box(u - 0.01, u + w + 0.01, -0.012 + off, 0.012 + off, z0, z1 + (gz(rng.uniform(0, 1.5)) if z1 == top else 0), c,
                  tilt=math.radians(rng.uniform(-2, 2)))
            n = max(2, int(w / 0.05))                       # corrugation ribs
            for k in range(n):
                uu = u + (k + 0.5) * w / n
                W.box(uu - 0.008, uu + 0.008, 0.012 + off, 0.02 + off, z0, z1, c)
            u += w
    for uu in (0.02, 0.98) + ((0.5,) if op is None else ()):
        W.box(uu - 0.025, uu + 0.025, -0.03, -0.012, 0, top + gz(1.5), post)
    if op is not None and piece != "window":
        o0, o1, oz0, oz1 = op
        W.box(o0 - 0.03, o0, -0.03, 0.03, 0, oz1 + gz(1), post); W.box(o1, o1 + 0.03, -0.03, 0.03, 0, oz1 + gz(1), post)
        W.box(o0 - 0.03, o1 + 0.03, -0.03, 0.03, oz1, oz1 + gz(1.5), post)
    leaf(W, piece, op, mat("scrap_door", "#7a6a50", 0.6, 0.4), rng)


def wood(W, piece, rng, top):
    """Rough horizontal boards nailed to square posts."""
    post = mat("wood_post", "#4e3622", 0.9)
    tones = ["#7a5636", "#6a4a2e", "#86603c", "#5e4228"]
    op = opening_for(piece)
    bh = gz(3.4)
    for (u0, u1, z0, z1) in solid_spans(op, top):
        z = z0
        row = 0
        while z < z1 - 1e-4:
            h = min(bh, z1 - z)
            c = mat("wood_%d" % ((row + int(u0 * 7)) % len(tones)), tones[(row + int(u0 * 7)) % len(tones)], 0.9)
            W.box(u0 - 0.004, u1 + 0.004, -0.015, 0.015, z + gz(0.25), z + h, c, tilt=math.radians(rng.uniform(-0.8, 0.8)))
            z += bh; row += 1
    for uu in (0.03, 0.97) + ((0.5,) if op is None else ()):
        W.box(uu - 0.03, uu + 0.03, -0.045, -0.015, 0, top + gz(2), post)
        W.box(uu - 0.034, uu + 0.034, -0.049, -0.011, top + gz(1.2), top + gz(2.2), post)
    if op is not None and piece != "window":
        o0, o1, oz0, oz1 = op
        W.box(o0 - 0.035, o0, -0.04, 0.04, 0, oz1 + gz(1), post); W.box(o1, o1 + 0.035, -0.04, 0.04, 0, oz1 + gz(1), post)
        W.box(o0 - 0.035, o1 + 0.035, -0.04, 0.04, oz1, oz1 + gz(2), post)
    leaf(W, piece, op, mat("wood_door", "#5a3e26", 0.85), rng, planks=True)


def stone(W, piece, rng, top):
    """Rubble-stone blocks in mortar, coursed, with a flat cap."""
    tones = ["#8a8272", "#7a7262", "#9a9080", "#6e685c", "#a09684"]
    mortar = mat("stone_mortar", "#5a544a", 1.0)
    op = opening_for(piece)
    ch = gz(4.2)
    for (u0, u1, z0, z1) in solid_spans(op, top):
        W.box(u0, u1, -T + 0.004, T - 0.004, z0, z1, mortar)
        z = z0; row = 0
        while z < z1 - 1e-4:
            h = min(ch, z1 - z)
            u = u0 - (0.08 if row % 2 else 0.0)
            while u < u1 - 1e-3:
                w = rng.uniform(0.12, 0.22)
                a, b = max(u, u0), min(u + w, u1)
                if b - a > 0.02:
                    c = mat("stone_%d" % rng.randrange(len(tones)), rng.choice(tones), 0.95)
                    d = rng.uniform(0, 0.006)
                    W.box(a + 0.006, b - 0.006, -T - d, T + d, z + gz(0.35), z + h - gz(0.35), c)
                u += w
            z += ch; row += 1
    cap = mat("stone_cap", "#9a9282", 0.95)
    if piece != "half" or True:
        W.box(-0.02, 1.02, -T - 0.012, T + 0.012, top, top + gz(1.6), cap)
    if op is not None and piece not in ("window",):
        o0, o1, oz0, oz1 = op
        W.box(o0 - 0.02, o1 + 0.02, -T - 0.01, T + 0.01, oz1, oz1 + gz(2.2), mat("stone_lintel", "#6e6458", 0.9))
    leaf(W, piece, op, mat("stone_door", "#4e4a44", 0.5, 0.5), rng, iron=True)


def concrete(W, piece, rng, top):
    """Precast panels with seams, a cap beam, and rebar sticking out of chipped corners."""
    panel = mat("conc", "#9a968a", 0.95)
    panel2 = mat("conc2", "#8a867a", 0.95)
    seam = mat("conc_seam", "#4a4842", 1.0)
    rebar = mat("rebar", "#6a4a32", 0.6, 0.6)
    op = opening_for(piece)
    for (u0, u1, z0, z1) in solid_spans(op, top):
        W.box(u0, u1, -T - 0.01, T + 0.01, z0, z1, panel if int(u0 * 10) % 2 == 0 else panel2)
    W.box(0.497, 0.503, T + 0.01, T + 0.014, 0, top, seam) if op is None else None
    for zz in (gz(9.5), gz(19)):
        if zz < top - gz(2):
            for (u0, u1, z0, z1) in solid_spans(op, top):
                if z0 <= zz <= z1:
                    W.box(u0, u1, T + 0.01, T + 0.013, zz - gz(0.2), zz + gz(0.2), seam)
    W.box(-0.01, 1.01, -T - 0.022, T + 0.022, top, top + gz(2.2), mat("conc_cap", "#a8a498", 0.95))
    if piece in ("wall", "half") and rng.random() < 0.9:          # chipped top corner + rebar
        cu = rng.choice((0.12, 0.82))
        for k in range(3):
            W.box(cu + k * 0.03, cu + k * 0.03 + 0.008, -0.006, 0.006, top, top + gz(rng.uniform(2.5, 4.5)), rebar, tilt=math.radians(rng.uniform(-12, 12)))
    if op is not None and piece != "window":
        o0, o1, oz0, oz1 = op
        W.box(o0 - 0.025, o1 + 0.025, -T - 0.02, T + 0.02, oz1, oz1 + gz(2.6), mat("conc_cap", "#a8a498", 0.95))
    if piece == "window":
        o0, o1, oz0, oz1 = op
        W.box(o0, o1, -0.006, 0.006, oz0, oz1, mat("bars_dark", "#1a1814", 1.0))
        for k in range(4):
            uu = o0 + (k + 0.5) * (o1 - o0) / 4
            W.box(uu - 0.006, uu + 0.006, T * 0.3, T * 0.6, oz0, oz1, rebar)
    leaf(W, piece, op, mat("conc_door", "#5e6e64", 0.5, 0.5), rng, iron=True)


def fence(W, piece, rng, top):
    """Chain-link on pipe posts: cheap, see-through, keeps critters out, stops nothing else."""
    pipe = mat("pipe", "#8a8a84", 0.4, 0.7)
    wire = mat("wire", "#9a9a92", 0.4, 0.7)
    th = gz(22)
    for uu in (0.02, 0.98) + ((0.5,) if piece == "wall" else ()):
        W.box(uu - 0.015, uu + 0.015, -0.015, 0.015, 0, th + gz(1), pipe)
    W.box(0.0, 1.0, -0.01, 0.01, th - gz(0.6), th, pipe)
    if piece == "gate":
        for uu in (0.06, 0.5, 0.94):
            W.box(uu - 0.012, uu + 0.012, 0.012, 0.03, gz(1), th - gz(1), pipe)
        W.box(0.06, 0.94, 0.012, 0.03, gz(1), gz(2), pipe)
    n = 16
    for k in range(n + 1):                               # diamond mesh, coarse enough to read at 28 px
        u = k / n
        W.box(u - 0.003, u + 0.003, -0.004, 0.004, gz(1), th - gz(0.6), wire, tilt=math.radians(20))
        W.box(u - 0.003, u + 0.003, -0.004, 0.004, gz(1), th - gz(0.6), wire, tilt=math.radians(-20))
    for k in range(5):                                   # barbed wire on top
        W.box(k / 5, (k + 1) / 5, -0.004, 0.004, th + gz(2) + gz(k % 2), th + gz(2.4) + gz(k % 2), wire)


def leaf(W, piece, op, m, rng, planks=False, iron=False):
    if op is None:
        return
    o0, o1, z0, z1 = op
    if piece == "door":
        W.box(o0, o1, -0.014, 0.012, z0, z1 - gz(0.3), m)
        if planks:
            for k in range(3):
                W.box(o0, o1, 0.012, 0.018, gz(4 + k * 6), gz(5.6 + k * 6), m)
        if iron:
            for zz in (gz(4), gz(15)):
                W.box(o0, o1, 0.012, 0.018, zz, zz + gz(1.2), mat("iron", "#2e2c28", 0.5, 0.6))
        W.box(o1 - 0.07, o1 - 0.045, 0.012, 0.026, gz(9), gz(10.5), mat("brass", "#c8a040", 0.3, 0.8))
    elif piece == "gate":
        mid = (o0 + o1) / 2
        for (a, b) in ((o0, mid - 0.006), (mid + 0.006, o1)):
            W.box(a, b, -0.014, 0.012, z0 + gz(0.5), z1 - gz(0.4), m)
            if planks or iron:
                W.box(a, b, 0.012, 0.018, gz(6), gz(7.5), mat("iron", "#2e2c28", 0.5, 0.6))
                W.box(a, b, 0.012, 0.018, gz(15), gz(16.5), mat("iron", "#2e2c28", 0.5, 0.6))
    elif piece == "window":
        W.box(o0, o1, -T * 0.6, -T * 0.5, z0, z1, mat("dark", "#16120e", 1.0))
    elif piece == "doorway":
        W.box(o0, o1, -T * 0.6, -T * 0.5, z0, z1, mat("dark", "#16120e", 1.0)) if False else None


BUILDERS = {"scrap": scrap, "wood": wood, "stone": stone, "concrete": concrete, "fence": fence}


# ------------------------------------------------------------------ floors
def floor(tier):
    b = FAST.Batch("bf")
    rng = random.Random(zlib.crc32(tier.encode()))
    def tile(x0, x1, y0, y1, z0, z1, m, rot=0.0):
        b.cube(Vector(((x0 + x1) / 2, -(y0 + y1) / 2, (z0 + z1) / 2)), (x1 - x0, y1 - y0, z1 - z0), m, rot=(0, 0, rot))
    z = 0.0
    if tier == "wood":
        tones = ["#7a5636", "#6a4a2e", "#86603c", "#5e4228"]
        n = 6
        for k in range(n):
            tile(-0.002, 1.002, k / n + 0.004, (k + 1) / n - 0.004, -0.02, 0.0, mat("fw_%d" % (k % 4), tones[(k * 3) % 4], 0.9))
        tile(0, 1, 0, 1, -0.03, -0.021, mat("fw_gap", "#2e2218", 1.0))
    elif tier == "scrap":
        cols = ["#7a7468", "#8a6a4e", "#6e7a74"]
        for (x0, x1, y0, y1) in ((0, 0.55, 0, 0.5), (0.55, 1, 0, 0.62), (0, 0.48, 0.5, 1), (0.48, 1, 0.62, 1)):
            c = mat("fs_%d" % rng.randrange(3), rng.choice(cols), 0.55, 0.45)
            tile(x0 + 0.006, x1 - 0.006, y0 + 0.006, y1 - 0.006, -0.02, rng.uniform(-0.002, 0.004), c)
            for (rx, ry) in ((x0 + 0.05, y0 + 0.05), (x1 - 0.05, y0 + 0.05), (x0 + 0.05, y1 - 0.05), (x1 - 0.05, y1 - 0.05)):
                tile(rx - 0.012, rx + 0.012, ry - 0.012, ry + 0.012, 0.0, 0.008, mat("rivet", "#a8a49a", 0.4, 0.6))
        tile(0, 1, 0, 1, -0.03, -0.021, mat("fs_gap", "#1e1a16", 1.0))
    elif tier == "stone":
        tones = ["#8a8272", "#7a7262", "#9a9080", "#6e685c"]
        tile(0, 1, 0, 1, -0.03, -0.012, mat("stone_mortar", "#5a544a", 1.0))
        y = 0.0
        while y < 0.999:
            hgt = rng.uniform(0.22, 0.34); hgt = min(hgt, 1 - y)
            x = 0.0
            while x < 0.999:
                w = min(rng.uniform(0.22, 0.4), 1 - x)
                tile(x + 0.012, x + w - 0.012, y + 0.012, y + hgt - 0.012, -0.02, rng.uniform(-0.004, 0.002),
                     mat("fst_%d" % rng.randrange(4), rng.choice(tones), 0.95))
                x += w
            y += hgt
    elif tier == "concrete":
        tile(0, 1, 0, 1, -0.02, 0.0, mat("conc", "#9a968a", 0.95))
        tile(0.497, 0.503, 0, 1, 0.0, 0.002, mat("conc_seam", "#4a4842", 1.0))
        tile(0, 1, 0.497, 0.503, 0.0, 0.002, mat("conc_seam", "#4a4842", 1.0))
    return b.done()


def main(tiers):
    reset()
    lights()
    for tier in tiers:
        pieces = ("wall", "gate") if tier == "fence" else PIECES
        for piece in pieces:
            for axis in "xy":
                rng = random.Random(zlib.crc32((tier + piece).encode()))       # same look on both axes
                W = Wall(axis)
                top = HALF if piece == "half" else H
                BUILDERS[tier](W, piece, rng, top)
                ob = W.done()
                name = "bw_%s_%s_%s" % (tier, piece, axis)
                PC.sprite(name, 28, 60, 2 if axis == "x" else 26, 45, samples=16, bright=1.12 * (1.08 if axis == "x" else 1.0), sat=1.05)
                PC.set_anchor(name, 2 if axis == "x" else 26, 45)
                PC.clear([ob])
        if tier != "fence":
            ob = floor(tier)
            PC.sprite("bf_" + tier, 48, 24, 24, 0, samples=16, bright=1.12, alpha_cut=100)
            PC.set_anchor("bf_" + tier, 24, 0)
            PC.clear([ob])
        print("tier", tier, flush=True)


if __name__ == "__main__":
    os.environ["PYTHONHASHSEED"] = "0"
    main(sys.argv[1:] or list(TIERS) + ["fence"])
