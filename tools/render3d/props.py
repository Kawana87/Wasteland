"""Prop library for the pre-rendered art. Every prop is a function prop(P, x, y, rot, rng) that builds
the object around (x, y) (game tiles, z up) and returns the list of Blender objects it made.
Pass a different rng and you get a slightly different object (colours, wear, contents, sizes),
so no two houses or streets look copy-pasted. Names and designs are original."""
import math, random
import bpy
import fast as FAST
from lib import box, cyl, sphere, g2b, rot_z, mat_flat, mat_paint_rust, mat_planks, mat_concrete, mat_stucco
from lib import _nodes, _coord, _noise, _ramp, _bump, _hex, _mix, grit, grime
from kit import mesh

# ------------------------------------------------------------------ materials (cached)
_MC = {}


def mat_fabric(name, col, pattern=None):
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    n = _noise(nt, co, 30.0, 6.0, 0.6)
    c = _ramp(nt, n.outputs[0], [(0.3, '#7a7a7a'), (0.7, '#ffffff')])
    base = col
    if pattern == "check":
        ch = nt.nodes.new("ShaderNodeTexChecker")
        ch.inputs["Scale"].default_value = 18.0
        ch.inputs["Color1"].default_value = _hex(col)
        r, g, b = [int(col[i:i + 2], 16) for i in (1, 3, 5)]
        ch.inputs["Color2"].default_value = _hex('#%02x%02x%02x' % (int(r * .6), int(g * .6), int(b * .6)))
        nt.links.new(co, ch.inputs["Vector"])
        base = ch.outputs["Color"]
    mm = nt.nodes.new("ShaderNodeMix"); mm.data_type = 'RGBA'; mm.blend_type = 'MULTIPLY'; mm.inputs[0].default_value = 0.5
    if isinstance(base, str):
        mm.inputs[6].default_value = _hex(base)
    else:
        nt.links.new(base, mm.inputs[6])
    nt.links.new(c, mm.inputs[7])
    nt.links.new(grime(nt, mm.outputs[2], co, 0.45, False), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.95
    _bump(nt, bs, n.outputs[0], 0.3, 0.01)
    return m


def mat_rock(name, a='#7a7266', b='#5a544a'):
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    n = _noise(nt, co, 6.0, 10.0, 0.7)
    col = _ramp(nt, n.outputs[0], [(0.35, b), (0.55, a), (0.7, '#9a9284')])
    nt.links.new(grit(nt, col, co, 0.45, 60.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.95
    _bump(nt, bs, n.outputs[0], 1.0, 0.03)
    return m


def mat_leaf(name, a, b):
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    n = _noise(nt, co, 14.0, 6.0, 0.7)
    col = _ramp(nt, n.outputs[0], [(0.38, b), (0.5, a), (0.62, b)])
    nt.links.new(grit(nt, col, co, 0.5, 40.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.9
    _bump(nt, bs, n.outputs[0], 1.0, 0.03)
    return m


def MAT(key):
    """Lazily-made materials. Keys like 'paint:#8a3a2a:0.4', 'fab:#6a7a5a', 'flat:#hex'."""
    if key in _MC:
        return _MC[key]
    kind, _, rest = key.partition(":")
    if kind == "paint":
        col, rust = rest.split(":")
        m = mat_paint_rust("p" + str(len(_MC)), col, float(rust))
    elif kind == "fab":
        col, _, pat = rest.partition(":")
        m = mat_fabric("f" + str(len(_MC)), col, pat or None)
    elif kind == "flat":
        col, _, rough = rest.partition(":")
        m = mat_flat("m" + str(len(_MC)), col, float(rough or 0.8))
    elif kind == "metal":
        m = mat_flat("mt" + str(len(_MC)), rest, 0.35, metal=0.9, noise=0.1)
    elif kind == "wood":
        a, b = rest.split(":")
        m = mat_planks("w" + str(len(_MC)), a, b)
    elif kind == "rock":
        a, b = rest.split(":")
        m = mat_rock("r" + str(len(_MC)), a, b)
    elif kind == "leaf":
        a, b = rest.split(":")
        m = mat_leaf("l" + str(len(_MC)), a, b)
    elif kind == "conc":
        m = mat_concrete("c" + str(len(_MC)), rest)
    elif kind == "glow":
        m = mat_flat("g" + str(len(_MC)), rest, 0.4, emit=rest, noise=0.0)
    else:
        raise KeyError(key)
    _MC[key] = m
    return m


WOODS = [("#7a5a3a", "#6a4a2e"), ("#5a3e28", "#4a3220"), ("#8a6a48", "#74583a"), ("#4a3428", "#3a281e")]
PAINTS = ["#8a3a2a", "#3e6a5a", "#5a6a8a", "#c8b890", "#7a8a5a", "#a87a4a", "#6a5a4a", "#b85a44", "#5e9a90", "#d6c79a"]
FABRICS = ["#6a7a5a", "#7a4a2e", "#8a6a4a", "#5a5a6a", "#9a4a3a", "#6a5a7a", "#8a8a6a", "#4a5a4a"]


def wood(rng):
    return MAT("wood:%s:%s" % rng.choice(WOODS))


def paint(rng, rust=None):
    return MAT("paint:%s:%.2f" % (rng.choice(PAINTS), rust if rust is not None else rng.uniform(0.2, 0.5)))


def fabric(rng, pattern=False):
    return MAT("fab:%s%s" % (rng.choice(FABRICS), ":check" if pattern and rng.random() < 0.4 else ""))


# ------------------------------------------------------------------ helpers
def _new_since(before):
    return [o for o in bpy.data.objects if o.name not in before]


# Placement context read by validate.py: every prop instance becomes one tagged group.
ZONE = "ext"          # ext | int (inside a building) | roof
PRIO = 2              # 2 placed by hand, 1 random placement inside a builder, 0 scatter
_DEPTH = [0]
_GID = [0]
DECALS = {"stain", "litter", "pebbles", "grass_tuft", "pothole", "weeds_line"}


class zone:
    """with zone("int"): ... / with zone(prio=1): ... — sets placement context for the props made inside."""
    def __init__(self, z=None, prio=None):
        self.z, self.p = z, prio
    def __enter__(self):
        global ZONE, PRIO
        self.old = (ZONE, PRIO)
        if self.z is not None: ZONE = self.z
        if self.p is not None: PRIO = self.p
    def __exit__(self, *a):
        global ZONE, PRIO
        ZONE, PRIO = self.old


def prop(fn):
    """Decorator: collects the objects a builder makes and rotates them around (x, y)."""
    def wrap(x, y, rot=0.0, rng=None, **kw):
        rng = rng or random.Random()
        import lib as _lib
        n0 = len(_lib.REG)
        _DEPTH[0] += 1
        try:
            fn(x, y, rng, **kw)
        finally:
            _DEPTH[0] -= 1
        obs = []
        for o in _lib.REG[n0:]:
            try:
                o.name; obs.append(o)
            except ReferenceError:
                pass
        if rot:
            for o in obs:
                rot_z(o, rot, (x, y))
        if _DEPTH[0] == 0:
            _GID[0] += 1
            for o in obs:
                o["grp"] = _GID[0]; o["pname"] = fn.__name__; o["zone"] = ZONE; o["prio"] = PRIO
        return obs
    wrap.__name__ = fn.__name__
    return wrap


def tip(obs, pivot, deg, axis='X'):
    """Tip a whole assembly over as one rigid body, around a horizontal axis through pivot at ground level."""
    from mathutils import Matrix
    p = g2b(pivot[0], pivot[1], 0)
    T = Matrix.Translation(p) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-p)
    bpy.context.view_layer.update()
    for o in obs:
        o.matrix_world = T @ o.matrix_world


def B(x0, y0, z0, x1, y1, z1, m, bev=0.0):
    return box(x0, y0, z0, x1, y1, z1, m, bevel=bev)


def legs4(x0, y0, x1, y1, z, m, t=0.03, inset=0.05):
    for (a, b) in ((x0 + inset, y0 + inset), (x1 - inset, y0 + inset), (x0 + inset, y1 - inset), (x1 - inset, y1 - inset)):
        B(a - t, b - t, 0, a + t, b + t, z, m)


def tilt(objs, rng, amt=6):
    for o in objs:
        o.rotation_euler.x += math.radians(rng.uniform(-amt, amt))
        o.rotation_euler.y += math.radians(rng.uniform(-amt, amt))


# ================================================================== INTERIOR
@prop
def chair(x, y, rng, style=None):
    style = style or rng.choice(["wood", "diner", "office"])
    if style == "wood":
        m = wood(rng)
        legs4(x - .18, y - .18, x + .18, y + .18, 0.4, m, 0.022, 0.03)
        B(x - .19, y - .19, 0.4, x + .19, y + .19, 0.45, m)
        B(x - .19, y - .19, 0.45, x + .19, y - .15, 0.9, m)
        for k in range(3):
            B(x - .15 + k * .12, y - .19, 0.5, x - .12 + k * .12, y - .15, 0.85, m)
    elif style == "diner":
        chrome = MAT("metal:#c0c0b8")
        for (a, b) in ((-.15, -.15), (.15, -.15), (-.15, .15), (.15, .15)):
            cyl(x + a, y + b, 0, 0.42, 0.015, chrome, 6)
        B(x - .19, y - .19, 0.42, x + .19, y + .19, 0.5, MAT("fab:%s" % rng.choice(["#b03a2a", "#3e8a86", "#c8a040"])), 0.04)
        B(x - .19, y - .21, 0.55, x + .19, y - .15, 0.88, MAT("fab:%s" % rng.choice(["#b03a2a", "#3e8a86"])), 0.04)
    else:
        cyl(x, y, 0.05, 0.4, 0.03, MAT("metal:#3a3a3a"), 8)
        for k in range(5):
            a = k * 1.2566
            B(x + math.cos(a) * .2 - .02, y + math.sin(a) * .2 - .02, 0, x + math.cos(a) * .2 + .02, y + math.sin(a) * .2 + .02, 0.05, MAT("metal:#2a2a2a"))
        B(x - .2, y - .2, 0.4, x + .2, y + .2, 0.5, fabric(rng), 0.05)
        B(x - .2, y - .24, 0.5, x + .2, y - .16, 0.95, fabric(rng), 0.05)
    if rng.random() < 0.15:   # knocked over
        pass


@prop
def couch(x, y, rng, w=None, torn=None):
    w = w or rng.choice([1.2, 1.5, 1.8])
    m = MAT("fab:%s" % rng.choice(FABRICS)) if rng.random() < 0.7 else MAT("flat:#7a4a2e:0.5")
    x0 = x - w / 2
    B(x0, y - .25, 0.12, x0 + w, y + .25, 0.38, m, 0.05)
    B(x0, y - .25, 0.38, x0 + w, y - .08, 0.8, m, 0.06)
    B(x0 - .03, y - .25, 0.12, x0 + .14, y + .25, 0.58, m, 0.05)
    B(x0 + w - .14, y - .25, 0.12, x0 + w + .03, y + .25, 0.58, m, 0.05)
    n = int(w / 0.55)
    for k in range(n):   # seat cushions, some missing
        if rng.random() < 0.85:
            cx = x0 + 0.15 + (w - 0.3) * (k + 0.5) / n
            B(cx - (w - 0.3) / n / 2 + 0.02, y - .1, 0.38, cx + (w - 0.3) / n / 2 - 0.02, y + .24, 0.48, m, 0.04)
    legs4(x0, y - .25, x0 + w, y + .25, 0.12, MAT("flat:#2a2018"), 0.025, 0.06)
    if torn if torn is not None else rng.random() < 0.4:
        B(x0 + w * rng.uniform(.2, .6), y - .2, 0.47, x0 + w * rng.uniform(.6, .8), y + .1, 0.49, MAT("flat:#c8bc9a"))


@prop
def armchair(x, y, rng):
    m = MAT("fab:%s" % rng.choice(FABRICS))
    B(x - .3, y - .3, 0.12, x + .3, y + .3, 0.4, m, 0.06)
    B(x - .3, y - .3, 0.4, x + .3, y - .12, 0.9, m, 0.07)
    B(x - .34, y - .3, 0.12, x - .2, y + .3, 0.62, m, 0.05)
    B(x + .2, y - .3, 0.12, x + .34, y + .3, 0.62, m, 0.05)
    legs4(x - .3, y - .3, x + .3, y + .3, 0.12, MAT("flat:#2a2018"), 0.025, 0.05)


@prop
def bed(x, y, rng, size=None, frame=None):
    w = size or rng.choice([0.95, 1.4])
    L = 1.9
    m = wood(rng)
    x0, y0 = x - w / 2, y - L / 2
    if frame if frame is not None else rng.random() < 0.8:
        B(x0, y0, 0.12, x0 + w, y0 + L, 0.28, m, 0.02)
        B(x0, y0 - 0.02, 0, x0 + w, y0 + 0.06, 0.85, m, 0.02)
        B(x0, y0 + L - 0.06, 0, x0 + w, y0 + L + 0.02, 0.5, m, 0.02)
        z = 0.28
    else:
        z = 0.0
    stain = MAT("fab:%s" % rng.choice(["#b8ac8a", "#a89a7a", "#c8bc9a"]))
    B(x0 + .03, y0 + .03, z, x0 + w - .03, y0 + L - .03, z + 0.18, stain, 0.05)
    for k in range(1 if w < 1.2 else 2):
        px = x0 + 0.1 + k * (w - 0.2) / 2
        B(px, y0 + 0.12, z + .18, px + (w - 0.3) / (1 if w < 1.2 else 2) * (0.9 if w < 1.2 else 1.0), y0 + 0.42, z + 0.28, MAT("fab:#e0d8c4"), 0.05)
    if rng.random() < 0.85:   # blanket, rumpled
        bl = fabric(rng, True)
        o = B(x0 + .02, y0 + 0.75 + rng.uniform(-.1, .2), z + .18, x0 + w - .02, y0 + L - .02, z + .24, bl, 0.03)
        o.rotation_euler.z = math.radians(rng.uniform(-6, 6))


@prop
def bunkbed(x, y, rng):
    m = MAT("metal:#5a6058")
    for (a, b) in ((-.45, -.95), (.45, -.95), (-.45, .95), (.45, .95)):
        B(x + a - .03, y + b - .03, 0, x + a + .03, y + b + .03, 1.7, m)
    for z in (0.3, 1.15):
        B(x - .45, y - .95, z, x + .45, y + .95, z + .05, m)
        B(x - .42, y - .92, z + .05, x + .42, y + .92, z + .2, MAT("fab:%s" % rng.choice(["#6a6a52", "#7a7a62"])), 0.05)


@prop
def mattress(x, y, rng):
    o = B(x - .45, y - .95, 0, x + .45, y + .95, 0.16, MAT("fab:%s" % rng.choice(["#a89a7a", "#8a7e64", "#b0a280"])), 0.05)
    o.rotation_euler.z = math.radians(rng.uniform(-15, 15))
    if rng.random() < 0.6:
        B(x - .3, y - .5, 0.16, x + .4, y + .6, 0.19, fabric(rng, True), 0.03)


@prop
def table(x, y, rng, shape=None, w=None, d=None):
    shape = shape or rng.choice(["rect", "round", "rect"])
    m = wood(rng) if rng.random() < 0.6 else MAT("paint:%s:0.3" % rng.choice(["#c84a3a", "#3e8a86", "#d8d0b8"]))
    if shape == "round":
        r = rng.uniform(0.35, 0.5)
        cyl(x, y, 0.66, 0.71, r, m, 24)
        cyl(x, y, 0.0, 0.66, 0.045, MAT("metal:#5a5a58"), 10)
        cyl(x, y, 0.0, 0.03, 0.22, MAT("metal:#5a5a58"), 16)
    else:
        w = w or rng.uniform(0.8, 1.2)
        d = d or rng.uniform(0.55, 0.75)
        B(x - w / 2, y - d / 2, 0.66, x + w / 2, y + d / 2, 0.72, m, 0.01)
        legs4(x - w / 2, y - d / 2, x + w / 2, y + d / 2, 0.66, m, 0.03, 0.06)
    clutter_top(x, y, 0.72, rng, 0.4)


def clutter_top(x, y, z, rng, rad):
    """Bottles, cans, plates, papers on a surface."""
    for k in range(rng.randint(0, 4)):
        px, py = x + rng.uniform(-rad, rad), y + rng.uniform(-rad * .6, rad * .6)
        kind = rng.random()
        if kind < 0.3:
            cyl(px, py, z, z + rng.uniform(0.12, 0.2), 0.03, MAT("flat:%s:0.2" % rng.choice(["#3a5a3a", "#5a3a20", "#2e4a4a"])), 8)
        elif kind < 0.55:
            cyl(px, py, z, z + 0.08, 0.03, MAT("metal:%s" % rng.choice(["#9a9a90", "#b83a2a", "#c8a040"])), 8)
        elif kind < 0.75:
            cyl(px, py, z, z + 0.015, 0.09, MAT("flat:#d8d0c0:0.4"), 16)
        else:
            o = B(px - .08, py - .05, z, px + .08, py + .05, z + 0.005, MAT("flat:#d8d0b8"))
            o.rotation_euler.z = rng.uniform(0, 6.3)


@prop
def coffee_table(x, y, rng):
    m = wood(rng)
    B(x - .45, y - .25, 0.32, x + .45, y + .25, 0.37, m, 0.01)
    legs4(x - .45, y - .25, x + .45, y + .25, 0.32, m, 0.025, 0.05)
    clutter_top(x, y, 0.37, rng, 0.3)


@prop
def bookshelf(x, y, rng, w=None):
    w = w or rng.choice([0.8, 1.0, 1.2])
    m = wood(rng)
    H = rng.choice([1.5, 1.8])
    B(x - w / 2, y - .16, 0, x + w / 2, y - .13, H, MAT("flat:#1e1610"))            # dark back
    B(x - w / 2, y - .16, 0, x - w / 2 + .03, y + .16, H, m)                          # sides
    B(x + w / 2 - .03, y - .16, 0, x + w / 2, y + .16, H, m)
    B(x - w / 2, y - .16, H - .03, x + w / 2, y + .16, H, m)
    rows = int(H / 0.4)
    fill = rng.uniform(0.3, 0.95)
    cols = ["#8a3a2a", "#3a5a7a", "#7a7a3a", "#5a3a5a", "#c8a050", "#3a6a4a", "#d8d0b8", "#6a4a2e"]
    for k in range(rows):
        z = 0.05 + k * (H - 0.1) / rows
        B(x - w / 2 + .03, y - .13, z, x + w / 2 - .03, y + .17, z + 0.03, m)
        xx = x - w / 2 + 0.06
        while xx < x + w / 2 - 0.1:
            bw = rng.uniform(0.03, 0.08)
            if rng.random() < fill:
                h = rng.uniform(0.18, 0.3)
                o = B(xx, y - .1, z + .03, xx + bw, y + .14, z + .03 + h, MAT("flat:%s" % rng.choice(cols)))
                if rng.random() < 0.12:
                    o.rotation_euler.y = math.radians(rng.choice([-25, 25]))
            xx += bw + 0.008


@prop
def dresser(x, y, rng):
    m = wood(rng) if rng.random() < 0.6 else paint(rng)
    w = rng.uniform(0.7, 1.0)
    h = rng.uniform(0.8, 1.1)
    B(x - w / 2, y - .22, 0.06, x + w / 2, y + .22, h, m, 0.015)
    n = int(h / 0.25)
    for k in range(n):
        z = 0.1 + k * (h - 0.1) / n
        out = 0.12 if rng.random() < 0.2 else 0.0
        B(x - w / 2 + .03, y + .2 + out - 0.0, z + .02, x + w / 2 - .03, y + .235 + out, z + (h - .1) / n - .02, m)
        cyl(x, y + .245 + out, z + (h - .1) / n / 2 - .01, z + (h - .1) / n / 2 + .01, 0.02, MAT("metal:#b8963a"), 6,
            rot=(math.radians(90), 0, 0))
    legs4(x - w / 2, y - .22, x + w / 2, y + .22, 0.06, m, 0.025, 0.04)
    if rng.random() < 0.5:
        clutter_top(x, y, h, rng, 0.25)


@prop
def wardrobe(x, y, rng):
    m = wood(rng)
    B(x - .45, y - .28, 0, x + .45, y + .28, 1.9, m, 0.015)
    B(x - .005, y + .28, 0.1, x + .005, y + .29, 1.8, MAT("flat:#1e1610"))
    if rng.random() < 0.4:   # one door hanging open
        o = B(x, y + .28, 0.1, x + .44, y + .31, 1.8, m)
        rot_z(o, -70, (x + .44, y + .3))


@prop
def filing_cabinet(x, y, rng):
    m = MAT("paint:%s:0.35" % rng.choice(["#7a7e78", "#5a6a5a", "#8a8a7a"]))
    B(x - .22, y - .3, 0, x + .22, y + .3, 1.3, m, 0.01)
    for k in range(4):
        z = 0.08 + k * 0.31
        out = 0.25 if rng.random() < 0.15 else 0.0
        B(x - .2, y + .28 + out, z, x + .2, y + .31 + out, z + 0.27, m)
        B(x - .05, y + .31 + out, z + 0.18, x + .05, y + .34 + out, z + 0.21, MAT("metal:#c0c0b8"))
    if rng.random() < 0.6:
        for k in range(rng.randint(2, 6)):
            o = B(x + rng.uniform(-.6, .6) - .1, y + rng.uniform(.4, 1.0) - .07, 0.01, x + rng.uniform(-.6, .6) + .1, y + rng.uniform(.4, 1.0) + .07, 0.015, MAT("flat:#d8d0b8"))
            o.rotation_euler.z = rng.uniform(0, 6.3)


@prop
def locker_row(x, y, rng, n=None):
    n = n or rng.randint(2, 4)
    m = MAT("paint:%s:0.4" % rng.choice(["#5a6a5a", "#4a5a6a", "#7a7a6a"]))
    for k in range(n):
        lx = x - n * 0.2 + k * 0.4
        B(lx, y - .25, 0, lx + 0.39, y + .25, 1.8, m, 0.008)
        for v in range(3):
            B(lx + .08, y + .25, 1.45 + v * 0.07, lx + .3, y + .26, 1.48 + v * 0.07, MAT("flat:#1a1a1a"))
        if rng.random() < 0.3:
            o = B(lx, y + .25, 0.05, lx + .38, y + .28, 1.75, m)
            rot_z(o, -80, (lx + .38, y + .26))


@prop
def footlocker(x, y, rng):
    m = MAT("paint:%s:0.4" % rng.choice(["#4a5a3a", "#5a4a3a", "#3a4a5a"]))
    B(x - .35, y - .2, 0, x + .35, y + .2, 0.35, m, 0.02)
    B(x - .36, y - .21, 0.27, x + .36, y + .21, 0.3, MAT("metal:#8a8a80"))
    B(x - .04, y + .2, 0.2, x + .04, y + .23, 0.28, MAT("metal:#b8963a"))


@prop
def safe(x, y, rng):
    m = MAT("paint:#3a3e3a:0.3")
    B(x - .3, y - .3, 0, x + .3, y + .3, 0.75, m, 0.03)
    cyl(x + .05, y + .31, 0.42, 0.44, 0.07, MAT("metal:#c0c0b8"), 16, rot=(math.radians(90), 0, 0))
    B(x - .2, y + .3, 0.3, x - .15, y + .34, 0.55, MAT("metal:#c0c0b8"))


@prop
def fridge(x, y, rng):
    m = MAT("paint:%s:%.2f" % (rng.choice(["#c8c0a8", "#a8c4b0", "#d8b8a0", "#b8b09a"]), rng.uniform(0.2, 0.45)))
    B(x - .3, y - .3, 0, x + .3, y + .3, 1.6, m, 0.08)
    B(x - .29, y + .3, 1.0, x + .29, y + .31, 1.02, MAT("flat:#2a2a2a"))
    B(x + .2, y + .3, 1.1, x + .24, y + .35, 1.4, MAT("metal:#c0c0b8"))
    if rng.random() < 0.25:   # door open, empty shelves visible
        o = B(x - .3, y + .3, 0.05, x + .3, y + .38, 1.0, m, 0.03)
        rot_z(o, 95, (x - .3, y + .34))


@prop
def stove(x, y, rng):
    m = MAT("paint:%s:%.2f" % (rng.choice(["#e0d8c4", "#c8c0a8", "#d8c090"]), rng.uniform(0.2, 0.4)))
    B(x - .3, y - .3, 0, x + .3, y + .3, 0.9, m, 0.03)
    B(x - .3, y - .3, 0.9, x + .3, y - .2, 1.15, m, 0.02)
    for (a, b) in ((-.14, -.06), (.14, -.06), (-.14, .16), (.14, .16)):
        cyl(x + a, y + b, 0.9, 0.92, 0.08, MAT("flat:#1e1e1e:0.5"), 12)
    B(x - .22, y + .3, 0.2, x + .22, y + .31, 0.6, MAT("flat:#1e1e1e:0.3"))
    if rng.random() < 0.5:
        cyl(x + .14, y - .06, 0.92, 1.05, 0.11, MAT("metal:#7a7a74"), 12)


@prop
def counter(x, y, rng, w=None, sink=None):
    w = w or rng.choice([1.0, 1.4, 1.8])
    base = wood(rng) if rng.random() < 0.5 else paint(rng)
    top = MAT("flat:%s:0.4" % rng.choice(["#8ac0b0", "#d8c8a0", "#c8b0a8", "#e0d8c8"]))
    B(x - w / 2, y - .28, 0.05, x + w / 2, y + .28, 0.88, base, 0.01)
    B(x - w / 2 - .02, y - .3, 0.88, x + w / 2 + .02, y + .31, 0.93, top)
    n = int(w / 0.5)
    for k in range(n):
        cx = x - w / 2 + (k + 0.5) * w / n
        B(cx - w / n / 2 + .03, y + .28, 0.12, cx + w / n / 2 - .03, y + .29, 0.82, base)
    if sink if sink is not None else rng.random() < 0.5:
        B(x - .2, y - .18, 0.86, x + .2, y + .18, 0.935, MAT("metal:#9a9a94"))
        cyl(x, y - .22, 0.93, 1.12, 0.015, MAT("metal:#c0c0b8"), 6)
    clutter_top(x, y, 0.93, rng, w / 2 - 0.1)


@prop
def toilet(x, y, rng):
    m = MAT("paint:%s:0.25" % rng.choice(["#e8e4d8", "#d8d0c0", "#c8d4c8"]))
    cyl(x, y + .05, 0, 0.4, 0.18, m, 16)
    cyl(x, y + .05, 0.4, 0.44, 0.2, m, 16)
    B(x - .2, y - .25, 0.4, x + .2, y - .08, 0.8, m, 0.03)


@prop
def bathtub(x, y, rng):
    m = MAT("paint:%s:0.3" % rng.choice(["#e8e4d8", "#c8d8d0", "#e0c8c0"]))
    B(x - .4, y - .85, 0.1, x + .4, y + .85, 0.6, m, 0.12)
    B(x - .32, y - .77, 0.3, x + .32, y + .77, 0.62, MAT("flat:#3a3a36:0.3"), 0.08)
    for (a, b) in ((-.33, -.75), (.33, -.75), (-.33, .75), (.33, .75)):
        sphere(x + a, y + b, 0.08, 0.06, MAT("metal:#b8963a"))


@prop
def sink_stand(x, y, rng):
    m = MAT("paint:#e0dcd0:0.3")
    cyl(x, y, 0, 0.7, 0.07, m, 12)
    B(x - .25, y - .2, 0.7, x + .25, y + .2, 0.82, m, 0.06)
    B(x - .3, y - .25, 1.0, x + .3, y - .23, 1.6, MAT("flat:#4a5a60:0.1"))   # mirror


@prop
def tv(x, y, rng, style=None):
    style = style or rng.choice(["console", "set"])
    m = wood(rng)
    scr = MAT("flat:%s:0.15" % rng.choice(["#4a5a50", "#3a4a48", "#5a6a5a"]))
    if style == "console":
        B(x - .45, y - .25, 0.05, x + .45, y + .25, 0.75, m, 0.03)
        B(x - .32, y + .25, 0.3, x + .1, y + .26, 0.65, scr, 0.03)
        for k in range(2):
            cyl(x + .22, y + .26, 0.5 - k * 0.15, 0.52 - k * 0.15, 0.04, MAT("metal:#b8963a"), 10, rot=(math.radians(90), 0, 0))
        legs4(x - .45, y - .25, x + .45, y + .25, 0.05, m, 0.02, 0.05)
    else:
        B(x - .22, y - .2, 0.0, x + .22, y + .2, 0.4, m, 0.05)
        B(x - .17, y + .2, 0.08, x + .17, y + .21, 0.34, scr, 0.03)
        for s in (-1, 1):
            o = cyl(x, y, 0.4, 0.75, 0.006, MAT("metal:#8a8a84"), 4)
            o.rotation_euler.y = math.radians(25 * s)


@prop
def radio(x, y, rng):
    m = wood(rng)
    B(x - .2, y - .12, 0, x + .2, y + .12, 0.3, m, 0.06)
    B(x - .15, y + .12, 0.05, x + .05, y + .13, 0.25, MAT("fab:#c8b890"))
    cyl(x + .12, y + .13, 0.12, 0.14, 0.03, MAT("metal:#b8963a"), 10, rot=(math.radians(90), 0, 0))


@prop
def terminal(x, y, rng):
    """Vacuum-tube era computer terminal on a desk."""
    desk = MAT("paint:%s:0.35" % rng.choice(["#7a7e78", "#6a7060"]))
    B(x - .5, y - .3, 0.68, x + .5, y + .3, 0.74, desk, 0.01)
    B(x - .5, y - .3, 0, x - .1, y + .3, 0.68, desk, 0.01)
    legs4(x - .5, y - .3, x + .5, y + .3, 0.68, desk, 0.025, 0.04)
    case = MAT("paint:#c8c0a8:0.25")
    B(x - .05, y - .25, 0.74, x + .4, y + .15, 1.12, case, 0.05)
    B(x + .02, y + .15, 0.82, x + .33, y + .16, 1.06, MAT("glow:#3aa04a"), 0.02)
    B(x - .05, y + .15, 0.74, x + .4, y + .28, 0.79, case, 0.02)


@prop
def lamp(x, y, rng):
    cyl(x, y, 0, 0.03, 0.15, MAT("metal:#3a3a3a"), 12)
    cyl(x, y, 0.03, 1.4, 0.015, MAT("metal:#8a8a84"), 6)
    sh = MAT("fab:%s" % rng.choice(["#d8c8a0", "#c8a878", "#a88a6a"]))
    FAST.primitive_cone_add(vertices=12, radius1=0.2, radius2=0.12, depth=0.25, location=g2b(x, y, 1.45))
    o = FAST.LAST[0]; o.data.materials.append(sh)
    if rng.random() < 0.3:
        o.rotation_euler.x = math.radians(25)


@prop
def rug(x, y, rng):
    m = MAT("fab:%s:check" % rng.choice(["#7a3a2e", "#3a4a6a", "#6a5a2e", "#4a5a3a"]))
    w, d = rng.uniform(1.0, 1.8), rng.uniform(0.8, 1.3)
    o = B(x - w / 2, y - d / 2, 0.0, x + w / 2, y + d / 2, 0.012, m)
    o.rotation_euler.z = math.radians(rng.uniform(-8, 8))


@prop
def cardboard_boxes(x, y, rng):
    m = MAT("flat:%s:0.95" % rng.choice(["#a08058", "#8a6e4a", "#b09068"]))
    z = 0
    for k in range(rng.randint(1, 3)):
        s = rng.uniform(0.25, 0.45)
        o = B(x - s / 2, y - s / 2, z, x + s / 2, y + s / 2, z + s * 0.8, m, 0.01)
        o.rotation_euler.z = math.radians(rng.uniform(-20, 20))
        z += s * 0.8
        x += rng.uniform(-0.06, 0.06)


@prop
def ammo_crate(x, y, rng):
    m = MAT("paint:#4a5a3a:0.35")
    B(x - .32, y - .2, 0, x + .32, y + .2, 0.32, m, 0.015)
    for s in (-1, 1):
        B(x + s * .33 - .03, y - .05, 0.2, x + s * .33 + .03, y + .05, 0.24, MAT("metal:#6a6a64"))
    if rng.random() < 0.5:
        o = B(x - .32, y - .2, 0.32, x + .32, y + .2, 0.36, m)
        o.rotation_euler.x = math.radians(-35)


@prop
def jukebox(x, y, rng):
    B(x - .35, y - .25, 0, x + .35, y + .25, 1.2, MAT("paint:#8a4a30:0.3"), 0.06)
    cyl(x, y, 1.15, 1.35, 0.35, MAT("glow:#e8a040"), 24, rot=(math.radians(90), 0, 0))
    B(x - .25, y + .25, 0.5, x + .25, y + .26, 0.95, MAT("flat:#2a1e2a"))


@prop
def vending(x, y, rng):
    col = rng.choice(["#b83a2a", "#3e7a8a", "#c8a040"])
    B(x - .35, y - .3, 0, x + .35, y + .3, 1.75, MAT("paint:%s:0.35" % col), 0.04)
    B(x - .3, y + .3, 0.5, x + .05, y + .31, 1.5, MAT("flat:#2e4250:0.1"))
    B(x - .32, y + .3, 1.55, x + .32, y + .31, 1.7, MAT("glow:#f0e6c8"))


@prop
def booth(x, y, rng):
    m = MAT("fab:%s" % rng.choice(["#b03a2a", "#3e8a86"]))
    for s in (-1, 1):
        B(x - .6, y + s * .55 - .22, 0.1, x + .6, y + s * .55 + .22, 0.45, m, 0.05)
        B(x - .6, y + s * .7 - .07, 0.45, x + .6, y + s * .7 + .07, 1.05, m, 0.05)
    B(x - .55, y - .3, 0.7, x + .55, y + .3, 0.76, MAT("paint:#d8d0b8:0.2"), 0.03)
    cyl(x, y, 0, 0.7, 0.05, MAT("metal:#c0c0b8"), 8)


@prop
def workbench(x, y, rng):
    m = wood(rng)
    B(x - .6, y - .3, 0.8, x + .6, y + .3, 0.88, m, 0.01)
    legs4(x - .6, y - .3, x + .6, y + .3, 0.8, m, 0.035, 0.05)
    B(x - .6, y - .3, 0.2, x + .6, y + .3, 0.24, m)
    B(x - .6, y - .32, 0.88, x + .6, y - .28, 1.6, MAT("flat:#6a5a44"))   # pegboard
    for k in range(rng.randint(2, 5)):
        tx = x + rng.uniform(-.5, .5)
        B(tx - .015, y - .27, rng.uniform(1.1, 1.4), tx + .015, y - .25, 1.5, MAT("metal:#8a8a84"))
    B(x - .3, y - .1, 0.88, x - .05, y + .12, 1.0, MAT("paint:#c84a2a:0.4"))   # vice
    clutter_top(x + .3, y, 0.88, rng, 0.2)


# ================================================================== CITY / WASTELAND
@prop
def dumpster(x, y, rng, lid=None):
    m = MAT("paint:%s:%.2f" % (rng.choice(["#3e5a3e", "#4a5a6a", "#5a4a3a", "#2e4a3a"]), rng.uniform(0.35, 0.65)))
    B(x - .8, y - .45, 0.12, x + .8, y + .45, 1.0, m, 0.03)
    for (a, b) in ((-.7, -.35), (.7, -.35), (-.7, .35), (.7, .35)):
        cyl(x + a, y + b, 0, 0.12, 0.06, MAT("flat:#1e1e1e"), 8)
    state = lid or rng.choice(["closed", "open", "half"])
    if state == "closed":
        B(x - .82, y - .47, 1.0, x + .82, y + .47, 1.06, m)
    else:
        B(x - .78, y - .43, 0.6, x + .78, y + .43, 0.98, MAT("flat:#2a2622"))
        for k in range(rng.randint(3, 7)):
            sphere(x + rng.uniform(-.6, .6), y + rng.uniform(-.3, .3), rng.uniform(0.85, 1.05), rng.uniform(0.12, 0.2),
                   MAT("flat:%s:0.3" % rng.choice(["#2a2a2e", "#3a3a40", "#4a4030"])), scale=(1, 1, 0.8))
        o = B(x - .82, y - .47, 1.0, x + .82, y - .4, 1.7 if state == "open" else 1.3, m)
    for k in range(rng.randint(1, 5)):   # spilled trash
        sphere(x + rng.uniform(-1, 1), y + rng.uniform(.5, 1.0), 0.1, rng.uniform(0.1, 0.17), MAT("flat:#2e2e32:0.3"), scale=(1, 1, 0.75))


@prop
def trash_can(x, y, rng, tipped=None):
    m = MAT("paint:%s:%.2f" % (rng.choice(["#8a8a84", "#6a6e68", "#5a6a5a"]), rng.uniform(0.3, 0.6)))
    if tipped if tipped is not None else rng.random() < 0.3:
        o = cyl(x, y, 0.22, 0.22 + 0.7, 0.22, m, 16)
        o.rotation_euler = (math.radians(90), 0, rng.uniform(0, 6.3))
        o.location.z = 0.22
        for k in range(rng.randint(2, 5)):
            sphere(x + rng.uniform(-.6, .6), y + rng.uniform(-.6, .6), 0.06, rng.uniform(0.06, 0.12), MAT("flat:%s" % rng.choice(["#d8d0b8", "#3a3a3a", "#8a6a4a"])), scale=(1, 1, 0.5))
    else:
        cyl(x, y, 0, 0.7, 0.22, m, 16)
        for z in (0.2, 0.5):
            cyl(x, y, z, z + 0.03, 0.225, MAT("metal:#7a7a74"), 16)
        if rng.random() < 0.6:
            cyl(x, y, 0.7, 0.76, 0.24, m, 16)
        else:
            sphere(x, y, 0.72, 0.18, MAT("flat:#2e2e32:0.3"), scale=(1, 1, 0.6))


@prop
def trash_bags(x, y, rng, n=None):
    """Lumpy garbage bags with a tied neck, in a few plastic colours, slumped against each other."""
    cols = ["#2a2a2e", "#2a2a2e", "#3e4a3a", "#5a5a56", "#b8b4a8", "#4a3e30"]
    for k in range(n or rng.randint(2, 5)):
        px, py = x + rng.uniform(-.45, .45), y + rng.uniform(-.35, .35)
        r = rng.uniform(0.13, 0.21)
        m = MAT("flat:%s:0.72" % rng.choice(cols))
        o = FAST.primitive_ico_sphere_add(subdivisions=2, radius=r, location=g2b(px, py, r * 0.62))
        o.data.materials.append(m)
        tex = bpy.data.textures.get("bagnoise") or bpy.data.textures.new("bagnoise", 'CLOUDS')
        tex.noise_scale = 0.12
        d = o.modifiers.new("lump", 'DISPLACE'); d.texture = tex; d.strength = r * 0.35
        o.scale = (rng.uniform(.95, 1.25), rng.uniform(.8, 1.0), rng.uniform(.62, .85))
        o.rotation_euler = (rng.uniform(-.3, .3), rng.uniform(-.3, .3), rng.uniform(0, 6.3))
        FAST.shade_smooth()
        c = FAST.primitive_cone_add(vertices=6, radius1=0.045, radius2=0.012, depth=0.09, location=g2b(px + rng.uniform(-.04, .04), py, r * 1.25))
        c.data.materials.append(m)


def _in_building(px, py, pad=0.12):
    import kit as _k
    return any(s[0] - pad < px < s[2] + pad and s[1] - pad < py < s[3] + pad for s in _k.SOLIDS if s[5] != "doorway")


@prop
def litter(x, y, rng, n=None, r=1.5):
    """Papers, cans, bottles, wrappers scattered flat on the ground (one batched object)."""
    bt = FAST.Batch("litter")
    for k in range(n or rng.randint(6, 14)):
        px, py = x + rng.uniform(-r, r), y + rng.uniform(-r, r)
        if ZONE != "int" and _in_building(px, py):
            continue
        t = rng.random()
        if t < 0.5:
            bt.cube(g2b(px, py, 0.003), (0.14, 0.10, 0.006), MAT("flat:%s" % rng.choice(["#d8d0b8", "#c8c0a0", "#e0d8c8", "#b8b098"])),
                    rot=(math.radians(rng.uniform(-6, 6)), 0, rng.uniform(0, 6.3)))
        elif t < 0.75:
            bt.cone(g2b(px, py, 0.03), 0.028, 0.028, 0.1, 8, MAT("metal:%s" % rng.choice(["#9a9a90", "#b83a2a", "#c8a040", "#4a6a8a"])),
                    rot=(math.radians(90), 0, rng.uniform(0, 6.3)))
        else:
            bt.cone(g2b(px, py, 0.035), 0.035, 0.035, 0.18, 8, MAT("flat:%s:0.2" % rng.choice(["#3a5a3a", "#5a3a20", "#2e4a4a"])),
                    rot=(math.radians(90), 0, rng.uniform(0, 6.3)))
    bt.done()


@prop
def rubble_pile(x, y, rng, size=1.0, mats=None):
    mats = mats or [MAT("conc:#8a8478"), MAT("conc:#7a7466"), MAT("paint:#8a4434:0.2")]
    n = int(14 * size * size) + 4
    for k in range(n):
        a = rng.uniform(0, 6.3)
        d = rng.uniform(0, size * 0.8) ** 0.8
        px, py = x + math.cos(a) * d, y + math.sin(a) * d * 0.8
        s = rng.uniform(0.06, 0.22) * (1.2 - d / (size + .1) * 0.5)
        h = max(0.0, (size * 0.5 - d * 0.4)) * rng.uniform(0.3, 1.0)
        o = B(px - s, py - s * 0.7, h * 0.6, px + s, py + s * 0.7, h * 0.6 + s * rng.uniform(0.5, 1.2), rng.choice(mats), 0.015)
        o.rotation_euler = (rng.uniform(-.5, .5), rng.uniform(-.5, .5), rng.uniform(0, 6.3))
    for k in range(int(size * 3)):   # rebar
        o = cyl(x + rng.uniform(-size * .5, size * .5), y + rng.uniform(-size * .4, size * .4), 0.1, 0.1 + rng.uniform(0.4, 0.9), 0.01, MAT("paint:#5a3a24:0.7"), 4)
        o.rotation_euler = (rng.uniform(-.8, .8), rng.uniform(-.8, .8), 0)


@prop
def barrel(x, y, rng, kind=None):
    kind = kind or rng.choice(["rust", "rust", "toxic", "blue", "olive"])
    col = {"rust": "#8a6a2a", "toxic": "#c8b040", "blue": "#3a5a8a", "olive": "#5a6a3a"}[kind]
    m = MAT("paint:%s:%.2f" % (col, rng.uniform(0.35, 0.7)))
    if rng.random() < 0.2:
        o = cyl(x, y, 0.28, 0.28 + 0.85, 0.28, m, 20)
        o.rotation_euler = (math.radians(90), 0, rng.uniform(0, 6.3)); o.location.z = 0.28
        if kind == "toxic":
            o2 = cyl(x + 0.5, y + 0.3, 0.0, 0.01, 0.4, MAT("glow:#6ad02a"), 20)
        return
    cyl(x, y, 0, 0.85, 0.28, m, 20)
    for z in (0.18, 0.66):
        cyl(x, y, z, z + 0.035, 0.29, m, 20)
    if kind == "toxic":
        B(x - .12, y + .27, 0.4, x + .12, y + .3, 0.55, MAT("flat:#2a2420"))
        if rng.random() < 0.6:
            o = cyl(x + rng.uniform(.2, .5), y + rng.uniform(.2, .5), 0.0, 0.008, rng.uniform(0.25, 0.45), MAT("glow:#6ad02a"), 20)


@prop
def tire_stack(x, y, rng, n=None):
    for k in range(n or rng.randint(1, 4)):
        FAST.primitive_torus_add(major_radius=0.22, minor_radius=0.09, location=g2b(x + rng.uniform(-.06, .06), y + rng.uniform(-.06, .06), 0.09 + k * 0.17))
        o = FAST.LAST[0]; o.data.materials.append(MAT("flat:#1e1c1a:0.9"))
        o.rotation_euler = (rng.uniform(-.1, .1), rng.uniform(-.1, .1), 0)


@prop
def pallet(x, y, rng):
    m = MAT("wood:#9a7a50:#7a6040")
    for k in range(5):
        B(x - .5 + k * .24, y - .4, 0.1, x - .4 + k * .24, y + .4, 0.13, m)
    for s in (-1, 0, 1):
        B(x - .5, y + s * .35 - .04, 0, x + .5, y + s * .35 + .04, 0.1, m)


@prop
def crate(x, y, rng, s=None):
    s = s or rng.uniform(0.45, 0.7)
    m = MAT("wood:#9a7a50:#7a6040")
    B(x - s / 2, y - s / 2, 0, x + s / 2, y + s / 2, s, m, 0.01)
    for (a, b) in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        B(x + a * s / 2 - .03, y + b * s / 2 - .03, 0, x + a * s / 2 + .03, y + b * s / 2 + .03, s, MAT("wood:#6a5034:#5a4028"))
    if rng.random() < 0.4:
        crate(x + rng.uniform(-.1, .1), y + rng.uniform(-.1, .1), 0, rng, s=s * 0.8) if False else None


@prop
def sandbags(x, y, rng, n=None):
    m = MAT("fab:%s" % rng.choice(["#a89a72", "#9a8c66", "#8a7e5a"]))
    n = n or rng.randint(3, 5)
    for row in range(3):
        for k in range(n - (row % 2)):
            px = x - n * 0.2 + k * 0.4 + (0.2 if row % 2 else 0)
            sphere(px, y, 0.09 + row * 0.15, 0.2, m, scale=(1.0, 0.65, 0.42))


@prop
def barricade(x, y, rng):
    m = MAT("wood:#8a6a44:#6e5234")
    for s in (-1, 1):
        for d in (-1, 1):
            o = B(x + s * 0.6 - .03, y - .03, 0, x + s * 0.6 + .03, y + .03, 0.9, m)
            o.rotation_euler.x = math.radians(20 * d)
    for z, col in ((0.75, "#e8e0d0"), (0.45, "#c84a2a")):
        B(x - .75, y - .02, z, x + .75, y + .02, z + 0.14, MAT("paint:%s:0.4" % col))


@prop
def jersey(x, y, rng):
    m = MAT("conc:#a8a294")
    mesh([(x - .9, y - .3, 0), (x + .9, y - .3, 0), (x + .9, y + .3, 0), (x - .9, y + .3, 0),
          (x - .9, y - .12, 0.3), (x + .9, y - .12, 0.3), (x + .9, y + .12, 0.3), (x - .9, y + .12, 0.3),
          (x - .9, y - .08, 0.8), (x + .9, y - .08, 0.8), (x + .9, y + .08, 0.8), (x - .9, y + .08, 0.8)],
         [(0, 1, 5, 4), (4, 5, 9, 8), (3, 7, 6, 2), (7, 11, 10, 6), (8, 9, 10, 11), (1, 2, 6, 5), (5, 6, 10, 9), (0, 4, 7, 3), (4, 8, 11, 7)], m)


@prop
def chainlink(x, y, rng, n=3, wire=True):
    post = MAT("metal:#7a7a74")
    for k in range(n + 1):
        cyl(x + k * 1.0, y, 0, 1.6, 0.025, post, 6)
    mesh_m = MAT("flat:#8a8a84:0.4")
    for k in range(n):
        if rng.random() < 0.15:
            continue
        sag = rng.uniform(0, 0.15)
        B(x + k, y - .005, 0.05, x + k + 1, y + .005, 1.5 - sag, mesh_m)
    if wire:
        for z in (1.62, 1.72):
            B(x, y - .008, z, x + n, y + .008, z + 0.012, MAT("metal:#5a5a54"))


@prop
def wood_fence(x, y, rng, n=4):
    m = MAT("wood:#7a5a3a:#5e4430")
    for k in range(n + 1):
        o = B(x + k * 0.9 - .04, y - .04, 0, x + k * 0.9 + .04, y + .04, 0.95, m)
        if rng.random() < 0.2:
            o.rotation_euler.x = math.radians(rng.uniform(-15, 15))
    for z in (0.35, 0.75):
        for k in range(n):
            if rng.random() < 0.85:
                B(x + k * 0.9, y - .02, z, x + (k + 1) * 0.9, y + .02, z + 0.1, m)


@prop
def street_sign(x, y, rng):
    cyl(x, y, 0, 2.1, 0.025, MAT("metal:#7a7a74"), 6)
    kind = rng.choice(["stop", "street", "rad"])
    if kind == "stop":
        FAST.primitive_cylinder_add(vertices=8, radius=0.25, depth=0.02, location=g2b(x, y + 0.03, 2.0), rotation=(math.radians(90), 0, math.radians(22.5)))
        FAST.LAST[0].data.materials.append(MAT("paint:#b83a2a:0.35"))
    elif kind == "street":
        B(x - .35, y - .01, 2.05, x + .35, y + .01, 2.2, MAT("paint:#3e6a4a:0.35"))
        B(x - .01, y - .35, 2.22, x + .01, y + .35, 2.37, MAT("paint:#3e6a4a:0.35"))
    else:
        o = B(x - .2, y - .01, 1.75, x + .2, y + .01, 2.15, MAT("paint:#e0c040:0.35"))
        o.rotation_euler.y = math.radians(45)
    if rng.random() < 0.3:
        for ob in bpy.context.selected_objects:
            pass


@prop
def traffic_light(x, y, rng, fallen=None):
    pole = MAT("paint:#4a5048:0.4")
    if fallen if fallen is not None else rng.random() < 0.4:
        o = cyl(x, y, 0.08, 0.08 + 3.0, 0.06, pole, 8)
        o.rotation_euler = (math.radians(90), 0, rng.uniform(0, 6.3)); o.location.z = 0.08
        B(x + .5, y - .15, 0, x + .8, y + .15, 0.3, MAT("paint:#c8a040:0.3"))
        return
    cyl(x, y, 0, 3.0, 0.06, pole, 8)
    B(x - .05, y - .05, 2.9, x + 1.4, y + .05, 2.98, pole)
    B(x + 1.15, y - .14, 2.2, x + 1.43, y + .14, 2.9, MAT("paint:#c8a040:0.3"))
    for k, c in enumerate(("#4a2020", "#4a4020", "#204a20")):
        cyl(x + 1.29, y + .15, 2.75 - k * 0.22, 2.77 - k * 0.22, 0.07, MAT("flat:%s:0.3" % c), 10, rot=(math.radians(90), 0, 0))


@prop
def parking_meter(x, y, rng):
    cyl(x, y, 0, 1.0, 0.03, MAT("metal:#5a5a54"), 6)
    B(x - .08, y - .06, 1.0, x + .08, y + .06, 1.25, MAT("paint:#7a7e78:0.4"), 0.03)


@prop
def shopping_cart(x, y, rng):
    m = MAT("metal:#9a9a94")
    tipped = rng.random() < 0.3
    obs = []
    for k in range(6):
        obs.append(B(x - .4 + k * .16, y - .25, 0.35, x - .39 + k * .16, y + .25, 0.8, m))
    for z in (0.35, 0.8):
        obs.append(B(x - .4, y - .25, z, x + .42, y - .24, z + .01, m)); obs.append(B(x - .4, y + .24, z, x + .42, y + .25, z + .01, m))
    obs.append(B(x - .4, y - .26, 0.33, x + .42, y + .26, 0.35, m))
    obs.append(B(x + .42, y - .26, 0.8, x + .55, y + .26, 0.84, MAT("paint:#c84a2a:0.4")))
    for (a, b) in ((-.35, -.2), (.35, -.2), (-.35, .2), (.35, .2)):
        obs.append(B(x + a - .01, y + b - .01, 0.05, x + a + .01, y + b + .01, 0.35, m))
        obs.append(cyl(x + a, y + b, 0, 0.06, 0.04, MAT("flat:#1e1e1e"), 8))
    if tipped:
        tip(obs, (x, y + 0.26), 82)


@prop
def newsbox(x, y, rng):
    B(x - .2, y - .17, 0.3, x + .2, y + .17, 0.95, MAT("paint:%s:0.4" % rng.choice(["#3a7a5a", "#2a4a8a", "#c8a040"])), 0.02)
    for (a, b) in ((-.15, -.12), (.15, -.12), (-.15, .12), (.15, .12)):
        B(x + a - .015, y + b - .015, 0, x + a + .015, y + b + .015, 0.3, MAT("metal:#5a5a54"))
    B(x - .16, y + .17, 0.55, x + .16, y + .18, 0.85, MAT("flat:#2e3a40:0.1"))


@prop
def bench(x, y, rng):
    m = MAT("wood:#7a5a3a:#6a4a2e")
    iron = MAT("metal:#3a3a38")
    for s in (-1, 1):
        B(x + s * .7 - .04, y - .25, 0, x + s * .7 + .04, y + .25, 0.45, iron)
        B(x + s * .7 - .04, y - .27, 0.45, x + s * .7 + .04, y - .21, 0.95, iron)
    for k in range(3):
        if rng.random() < 0.85:
            B(x - .85, y - .22 + k * .15, 0.42, x + .85, y - .1 + k * .15, 0.46, m)
    for k in range(2):
        if rng.random() < 0.8:
            B(x - .85, y - .26, 0.6 + k * .18, x + .85, y - .22, 0.72 + k * .18, m)


@prop
def skeleton(x, y, rng):
    bone = MAT("flat:%s:0.6" % rng.choice(["#d8d0b8", "#c8bc9a"]))
    sphere(x, y, 0.08, 0.09, bone, scale=(1, 1.15, 0.9))
    for k in range(7):
        o = B(x - .12, y + 0.15 + k * 0.05, 0.02, x + .12, y + 0.17 + k * 0.05, 0.05, bone)
    B(x - .015, y + .1, 0.02, x + .015, y + .5, 0.06, bone)
    for s in (-1, 1):
        o = B(x + s * 0.08 - .015, y + .5, 0.02, x + s * 0.08 + .015, y + .95, 0.05, bone)
        o.rotation_euler.z = math.radians(s * rng.uniform(0, 20))
        o = B(x + s * 0.18 - .012, y + .15, 0.02, x + s * 0.18 + .012, y + .5, 0.04, bone)
        o.rotation_euler.z = math.radians(s * rng.uniform(-30, 30))


@prop
def junk_pile(x, y, rng):
    """Scrap heap: sheet metal, pipes, tyres, boards — what settlements are built from."""
    mats = [MAT("paint:#7a7e78:0.6"), MAT("paint:#8a6a3a:0.7"), MAT("wood:#7a5a3a:#5e4430"), MAT("paint:#5e9a90:0.6")]
    for k in range(rng.randint(8, 14)):
        px, py = x + rng.uniform(-.6, .6), y + rng.uniform(-.5, .5)
        t = rng.random()
        z = rng.uniform(0, 0.35)
        if t < 0.4:
            o = B(px - rng.uniform(.2, .5), py - .01, z, px + rng.uniform(.2, .5), py + .01, z + rng.uniform(.3, .6), rng.choice(mats))
        elif t < 0.7:
            o = cyl(px, py, z, z + rng.uniform(0.5, 1.0), rng.uniform(0.02, 0.05), rng.choice(mats[:2]), 8)
        else:
            o = B(px - .3, py - .05, z, px + .3, py + .05, z + .03, rng.choice(mats))
        o.rotation_euler = (rng.uniform(-1.2, 1.2), rng.uniform(-1.2, 1.2), rng.uniform(0, 6.3))
    if rng.random() < 0.6:
        tire_stack(x + rng.uniform(-.4, .4), y + rng.uniform(-.4, .4), 0, rng, n=1)


@prop
def generator(x, y, rng):
    B(x - .5, y - .3, 0.1, x + .5, y + .3, 0.7, MAT("paint:%s:0.5" % rng.choice(["#c8a040", "#5a6a3a", "#8a3a2a"])), 0.04)
    cyl(x - .2, y, 0.7, 0.9, 0.12, MAT("metal:#5a5a54"), 12)
    cyl(x + .3, y - .1, 0.7, 1.3, 0.03, MAT("metal:#3a3a38"), 6)
    for s in (-1, 1):
        B(x - .55, y + s * .28 - .03, 0, x + .55, y + s * .28 + .03, 0.1, MAT("metal:#3a3a38"))


@prop
def water_tank(x, y, rng):
    cyl(x, y, 0.6, 1.8, 0.55, MAT("paint:%s:0.55" % rng.choice(["#7a7e78", "#5a6a6a"])), 20)
    for (a, b) in ((-.4, -.4), (.4, -.4), (-.4, .4), (.4, .4)):
        B(x + a - .04, y + b - .04, 0, x + a + .04, y + b + .04, 0.65, MAT("wood:#6a5034:#5a4028"))


@prop
def campfire_pit(x, y, rng):
    for k in range(9):
        a = k / 9 * 6.283
        sphere(x + math.cos(a) * .35, y + math.sin(a) * .35, 0.06, 0.09, MAT("rock:#7a7266:#5a544a"), scale=(1, 1, 0.7))
    for k in range(4):
        o = cyl(x, y, 0.05, 0.05 + 0.5, 0.035, MAT("flat:#2a2018"), 6)
        o.rotation_euler = (math.radians(80), 0, k * 0.8)
    sphere(x, y, 0.02, 0.2, MAT("glow:#e86a20"), scale=(1, 1, 0.3))


@prop
def lean_to(x, y, rng):
    """Scrap shelter: sheet metal leaning on poles with a tarp."""
    for s in (-1, 1):
        cyl(x + s * .8, y - .5, 0, 1.4, 0.04, MAT("wood:#6a5034:#5a4028"), 6)
    mesh([(x - 1.0, y - .55, 1.45), (x + 1.0, y - .55, 1.45), (x + 1.0, y + .7, 0.1), (x - 1.0, y + .7, 0.1)], [(0, 1, 2, 3)],
         MAT("paint:%s:0.6" % rng.choice(["#7a7e78", "#5e9a90", "#8a6a3a"])), "lean", solidify=0.03)
    mesh([(x - 1.0, y - .55, 1.4), (x - 1.0, y + .7, 0.05), (x - 1.0, y - .55, 0.05)], [(0, 1, 2)], MAT("fab:#7a6a4a"), "tarp")
    mattress(x, y - .1, 90, rng)


@prop
def mailbox(x, y, rng):
    cyl(x, y, 0, 1.0, 0.03, MAT("wood:#6a5034:#5a4028"), 6)
    B(x - .1, y - .2, 1.0, x + .1, y + .2, 1.18, MAT("paint:%s:0.5" % rng.choice(["#3a5a8a", "#8a8a84", "#5a7a5a"])), 0.06)


@prop
def hydrant(x, y, rng):
    m = MAT("paint:%s:0.45" % rng.choice(["#b03a26", "#c8a040"]))
    cyl(x, y, 0, 0.55, 0.11, m, 12)
    sphere(x, y, 0.55, 0.11, m)
    cyl(x, y, 0.33, 0.4, 0.16, m, 12)
    for s in (-1, 1):
        cyl(x + s * .13, y, 0.36, 0.43, 0.04, m, 8, rot=(0, math.radians(90), 0))


@prop
def phone_booth(x, y, rng):
    m = MAT("paint:%s:0.45" % rng.choice(["#3a6a6a", "#8a3a2a", "#5a5a54"]))
    for (a, b) in ((-.38, -.38), (.38, -.38), (-.38, .38), (.38, .38)):
        B(x + a - .04, y + b - .04, 0, x + a + .04, y + b + .04, 2.2, m)
    B(x - .42, y - .42, 2.2, x + .42, y + .42, 2.35, m, 0.02)
    for (a0, b0, a1, b1) in ((-.38, -.38, .38, -.37), (-.38, -.38, -.37, .38)):
        B(x + a0, y + b0, 0.2, x + a1, y + b1, 2.1, MAT("flat:#3a4a50:0.1"))
    if rng.random() < 0.6:
        B(x - .38, y + .37, 0.2, x + .38, y + .38, 2.1, MAT("flat:#3a4a50:0.1"))
    B(x - .3, y - .33, 1.1, x - .1, y - .25, 1.4, MAT("flat:#1e1e1e"))


@prop
def car_wreck(x, y, rng, style=None, col=None, hood=True):
    """50s sedan / truck wreck. style: sedan, truck, burned."""
    style = style or rng.choice(["sedan", "sedan", "truck", "burned"])
    col = col or rng.choice(["#5e9a90", "#a85444", "#c8a858", "#5a6a8a", "#8a8a7a", "#d8d0b8"])
    body = MAT("paint:%s:%.2f" % (col, rng.uniform(0.3, 0.6))) if style != "burned" else MAT("flat:#38322c:0.95")
    roof = MAT("paint:%s:0.35" % rng.choice(["#d8d0b8", col])) if style != "burned" else MAT("paint:#2a2420:0.9")
    glass = MAT("flat:#2a3a40:0.15") if style != "burned" else MAT("flat:#141210:0.9")
    chrome = MAT("metal:#c0c0b8") if style != "burned" else MAT("flat:#2a2420")
    L, W = (1.35, 0.55) if style != "truck" else (1.45, 0.58)
    B(x - L, y - W, 0.22, x + L, y + W, 0.55, body, 0.12)
    if style == "truck":
        B(x + 0.0, y - W + .05, 0.5, x + 0.85, y + W - .05, 0.95, glass, 0.08)
        B(x + 0.05, y - W + .03, 0.93, x + 0.8, y + W - .03, 1.0, roof, 0.04)
        B(x - L, y - W, 0.55, x - 0.05, y - W + .06, 0.75, body); B(x - L, y + W - .06, 0.55, x - 0.05, y + W, 0.75, body)
        B(x - L, y - W, 0.55, x - L + .06, y + W, 0.75, body)
        if rng.random() < 0.6:
            for k in range(rng.randint(1, 3)):
                B(x - L + .2 + k * .3, y - .3, 0.55, x - L + .45 + k * .3, y + .1, 0.8, MAT("wood:#9a7a50:#7a6040"), 0.01)
    else:
        B(x - 0.55, y - W + .07, 0.5, x + 0.45, y + W - .07, 0.86, glass, 0.1)
        B(x - 0.45, y - W + .05, 0.84, x + 0.3, y + W - .05, 0.93, roof, 0.04)
        for v in (-W + .08, W - .08):
            B(x - L, y + v - .04, 0.5, x - L + 0.45, y + v + .04, 0.66, body, 0.03)
    for s in (-1, 1):
        B(x + s * L - .04, y - W, 0.22, x + s * L + .04, y + W, 0.34, chrome, 0.02)
    for (a, b) in ((-0.82, -W), (0.82, -W), (-0.82, W), (0.82, W)):
        if style == "burned" or rng.random() < 0.15:
            continue   # wheel missing, sits on the axle
        FAST.primitive_cylinder_add(vertices=16, radius=0.22, depth=0.16, location=g2b(x + a, y + b, 0.22), rotation=(math.radians(90), 0, 0))
        w = FAST.LAST[0]; w.data.materials.append(MAT("flat:#1e1c1a:0.9"))
    if style == "burned":
        for o in bpy.context.scene.objects:
            pass
    if hood and rng.random() < 0.4 and style != "truck":   # hood popped open
        o = B(x + 0.45, y - W + .05, 0.55, x + L - .05, y + W - .05, 0.58, body)
        o.rotation_euler.y = math.radians(-35)


@prop
def billboard(x, y, rng):
    for s in (-1, 1):
        B(x + s * 1.0 - .06, y - .06, 0, x + s * 1.0 + .06, y + .06, 2.4, MAT("wood:#5a4030:#4a3424"))
    B(x - 1.4, y - .04, 2.4, x + 1.4, y + .04, 4.0, MAT("paint:%s:0.55" % rng.choice(["#d8c8a0", "#c84a3a", "#3e8a86"])))
    B(x - 1.45, y - .07, 2.35, x + 1.45, y + .07, 2.42, MAT("wood:#5a4030:#4a3424"))


@prop
def lamp_post(x, y, rng):
    m = MAT("paint:#4a5048:0.4")
    o = cyl(x, y, 0, 3.0, 0.05, m, 10)
    lean = rng.random() < 0.3
    B(x - .04, y - .04, 2.95, x + .7, y + .04, 3.0, m)
    sphere(x + .7, y, 2.9, 0.12, MAT("flat:#d8d0a8:0.3"))
    if lean:
        for ob in (o,):
            ob.rotation_euler.y = math.radians(rng.choice([-8, 8]))


# ================================================================== NATURE
def _branch(x, y, z, dirv, length, r, depth, rng, bark, tips, leafy):
    import mathutils
    d = mathutils.Vector(dirv).normalized()
    end = (x + d.x * length, y + d.y * length, z + d.z * length)
    mid = ((x + end[0]) / 2, (y + end[1]) / 2, (z + end[2]) / 2)
    FAST.primitive_cone_add(vertices=7, radius1=r, radius2=r * 0.68, depth=length, location=g2b(*mid))
    o = FAST.LAST[0]
    o.data.materials.append(bark)
    bd = mathutils.Vector((d.x, -d.y, d.z))
    o.rotation_euler = bd.to_track_quat('Z', 'Y').to_euler()
    if depth <= 0 or r < 0.012:
        tips.append(end)
        return
    n = rng.choice([2, 2, 3])
    for k in range(n):
        ang = rng.uniform(0.35, 0.8)
        az = rng.uniform(0, 6.283)
        # perturb the direction
        perp = mathutils.Vector((math.cos(az), math.sin(az), 0))
        nd = (d * math.cos(ang) + perp * math.sin(ang)).normalized()
        nd.z = max(nd.z, -0.1) + (0.15 if leafy else 0.05)
        _branch(end[0], end[1], end[2], nd, length * rng.uniform(0.6, 0.78), r * 0.62, depth - 1, rng, bark, tips, leafy)


@prop
def tree(x, y, rng, kind=None):
    """kind: dead, sparse, scrub, pine.  Branching is random per seed, so every tree differs."""
    kind = kind or rng.choice(["dead", "dead", "sparse", "scrub"])
    bark = MAT("flat:%s:0.95" % rng.choice(["#4a3a2c", "#5a4a3a", "#3a3028", "#6a5a48"]))
    tips = []
    if kind == "pine":
        h = rng.uniform(2.2, 3.2)
        cyl(x, y, 0, h * 0.3, 0.08, bark, 7)
        leaf = MAT("leaf:%s:%s" % rng.choice([("#4e6a44", "#384e34"), ("#5a6a40", "#40502e"), ("#6a6a48", "#4a4a34")]))
        for k in range(5):
            z = h * 0.22 + k * h * 0.15
            rr = (5 - k) * 0.17 * rng.uniform(0.85, 1.15)
            FAST.primitive_cone_add(vertices=9, radius1=rr, depth=h * 0.3, location=g2b(x + rng.uniform(-.04, .04), y, z + h * 0.12))
            o = FAST.LAST[0]; o.data.materials.append(leaf)
            o.rotation_euler.z = rng.uniform(0, 6.3)
        return
    h = rng.uniform(0.9, 1.5) if kind != "scrub" else rng.uniform(0.3, 0.6)
    lean = (rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 1.0)
    _branch(x, y, 0, lean, h, rng.uniform(0.09, 0.14) if kind != "scrub" else 0.05, 3 if kind != "scrub" else 2, rng, bark, tips, kind != "dead")
    if kind in ("sparse", "scrub"):
        leaf = MAT("leaf:%s:%s" % rng.choice([("#6a7a40", "#4a5a30"), ("#8a8a48", "#6a6a34"), ("#7a6a3a", "#5a4a2a"), ("#5a6a3a", "#3e4a2a")]))
        for t in tips:
            if rng.random() < (0.55 if kind == "sparse" else 0.8):
                FAST.primitive_ico_sphere_add(subdivisions=1, radius=rng.uniform(0.12, 0.24), location=g2b(*t))
                o = FAST.LAST[0]; o.data.materials.append(leaf)
                o.scale = (1, 1, rng.uniform(0.6, 0.9))
                o.rotation_euler = (rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3))


@prop
def joshua_tree(x, y, rng):
    bark = MAT("flat:#6a5a44:0.95")
    spikes = MAT("leaf:#7a8a4a:#5a6a34")
    tips = []
    _branch(x, y, 0, (rng.uniform(-.1, .1), rng.uniform(-.1, .1), 1), rng.uniform(0.7, 1.1), 0.09, 2, rng, bark, tips, True)
    for t in tips:
        for k in range(22):
            a, b = rng.uniform(0, 6.3), rng.uniform(-1.0, 1.6)
            FAST.primitive_cone_add(vertices=4, radius1=0.03, depth=0.38, location=g2b(t[0], t[1], t[2] + 0.05))
            o = FAST.LAST[0]; o.data.materials.append(spikes)
            o.rotation_euler = (b, 0, a)


@prop
def cactus(x, y, rng):
    m = MAT("leaf:#5a7a4a:#3e5a34")
    h = rng.uniform(0.8, 1.5)
    cyl(x, y, 0, h, 0.11, m, 10)
    sphere(x, y, h, 0.11, m)
    for k in range(rng.randint(0, 3)):
        s = rng.choice([-1, 1])
        z0 = rng.uniform(0.35, h * 0.7)
        cyl(x + s * 0.2, y, z0 + 0.05, z0 + rng.uniform(0.25, 0.55), 0.07, m, 8)
        o = cyl(x + s * 0.1, y, z0, z0 + 0.02, 0.07, m, 8)
        o.rotation_euler.y = math.radians(90)
        o.scale = (1, 1, 10)


@prop
def shrub(x, y, rng):
    leaf = MAT("leaf:%s:%s" % rng.choice([("#6a7a40", "#4a5a30"), ("#8a8a48", "#6a6a34"), ("#7a6a3a", "#5a4a2a")]))
    for k in range(rng.randint(4, 8)):
        FAST.primitive_ico_sphere_add(subdivisions=1, radius=rng.uniform(0.12, 0.22),
                                              location=g2b(x + rng.uniform(-.25, .25), y + rng.uniform(-.25, .25), rng.uniform(0.08, 0.25)))
        o = FAST.LAST[0]; o.data.materials.append(leaf)
        o.scale = (1, 1, 0.75)


@prop
def deadbush(x, y, rng):
    bark = MAT("flat:%s:0.95" % rng.choice(["#6a5a40", "#5a4a34", "#7a6a50"]))
    tips = []
    for k in range(rng.randint(3, 5)):
        a = rng.uniform(0, 6.3)
        _branch(x, y, 0, (math.cos(a) * 0.6, math.sin(a) * 0.6, 1), rng.uniform(0.2, 0.35), 0.015, 1, rng, bark, tips, False)


@prop
def tumbleweed(x, y, rng):
    m = MAT("flat:#8a7a54:0.95")
    r = rng.uniform(0.2, 0.32)
    for k in range(26):
        a, b = rng.uniform(0, 6.3), rng.uniform(0, 3.14)
        o = cyl(x, y, r, r + 0.001, 0.006, m, 4)
        bpy.data.objects.remove(o, do_unlink=True)
        FAST.primitive_torus_add(major_radius=r * rng.uniform(0.6, 1.0), minor_radius=0.006, major_segments=10, minor_segments=3,
                                         location=g2b(x + rng.uniform(-.05, .05), y + rng.uniform(-.05, .05), r))
        o = FAST.LAST[0]; o.data.materials.append(m)
        o.rotation_euler = (a, b, rng.uniform(0, 6.3))


@prop
def grass_tuft(x, y, rng, n=None):
    m = MAT("leaf:%s:%s" % rng.choice([("#8a8a4a", "#6a6a34"), ("#7a7a44", "#5a5a30"), ("#9a8a5a", "#7a6a40"), ("#6a7a40", "#4a5a2e")]))
    bt = FAST.Batch("tuft")
    for k in range(n or rng.randint(12, 22)):
        h = rng.uniform(0.18, 0.42)
        bt.cone(g2b(x + rng.uniform(-.12, .12), y + rng.uniform(-.12, .12), h / 2), 0.018, 0.0, h, 3, m, rot=(rng.uniform(-.5, .5), rng.uniform(-.5, .5), 0))
    bt.done()


@prop
def rock(x, y, rng, size=None):
    size = size or rng.uniform(0.15, 0.7)
    FAST.primitive_ico_sphere_add(subdivisions=3, radius=size, location=g2b(x, y, size * 0.3))
    o = FAST.LAST[0]
    o.data.materials.append(MAT("rock:%s:%s" % rng.choice([("#7a7266", "#5a544a"), ("#8a7a64", "#6a5a46"), ("#6a6660", "#4a4844"), ("#9a8a70", "#7a6a52")])))
    tex = bpy.data.textures.new("rn%d" % rng.randint(0, 99999), 'CLOUDS')
    tex.noise_scale = rng.uniform(0.3, 0.6)
    d = o.modifiers.new("disp", 'DISPLACE'); d.texture = tex; d.strength = size * 0.5
    o.scale = (rng.uniform(0.8, 1.4), rng.uniform(0.8, 1.2), rng.uniform(0.45, 0.8))
    o.rotation_euler.z = rng.uniform(0, 6.3)
    FAST.shade_flat()


@prop
def pebbles(x, y, rng, n=None, r=0.6):
    bt = FAST.Batch("pebbles")
    m = MAT("rock:#7a7266:#5a544a")
    for k in range(n or rng.randint(4, 10)):
        s_ = rng.uniform(0.03, 0.08)
        if ZONE != "int" and _in_building(x, y):
            break
        bt.ico(g2b(x + rng.uniform(-r, r), y + rng.uniform(-r, r), s_ * 0.3), s_, m, scale=(1, 1, 0.6))
    bt.done()


@prop
def stain(x, y, rng, col=None, r=None):
    """Flat decal: oil or water marks, a few overlapping blotches so it isn't a perfect circle."""
    r = r or rng.uniform(0.2, 0.5)
    m = MAT("flat:%s:1.0" % (col or rng.choice(["#3e362c", "#463c30", "#38322a"])))
    for k in range(rng.randint(2, 4)):
        o = cyl(x + rng.uniform(-r, r) * 0.6, y + rng.uniform(-r, r) * 0.6, 0.0, 0.002 + k * 0.0004, r * rng.uniform(0.4, 0.8), m, 12)
        for p in o.data.polygons: p.use_smooth = False
        o.scale = (1.0, rng.uniform(0.4, 0.9), 1.0)
        o.rotation_euler.z = rng.uniform(0, 6.3)


def roof_units(x0, y0, x1, y1, z, rng, n=None, margin=0.25):
    """Rooftop AC units + vent pipes inside a roof rectangle (inside the parapet), never overlapping.
    Small roofs get one unit; big ones two or three."""
    with zone("roof"):
        _roof_units(x0, y0, x1, y1, z, rng, n, margin)


def _roof_units(x0, y0, x1, y1, z, rng, n, margin):
    area = (x1 - x0) * (y1 - y0)
    if n is None:
        n = 1 if area < 40 else (2 if area < 90 else 3)
    placed = []
    def fits(cx, cy, hw, hd):
        if cx - hw < x0 + margin or cx + hw > x1 - margin or cy - hd < y0 + margin or cy + hd > y1 - margin:
            return False
        return all(abs(cx - a) > hw + aw + 0.3 or abs(cy - b) > hd + ad + 0.3 for (a, b, aw, ad) in placed)
    for k in range(n):
        for t in range(30):
            cx, cy = rng.uniform(x0, x1), rng.uniform(y0, y1)
            if fits(cx, cy, 0.35, 0.25):
                _ac_unit(cx, cy, 0, rng, z=z); placed.append((cx, cy, 0.35, 0.25)); break
    for k in range(rng.randint(0, 2)):
        for t in range(20):
            cx, cy = rng.uniform(x0, x1), rng.uniform(y0, y1)
            if fits(cx, cy, 0.06, 0.06):
                _vent(cx, cy, 0, rng, z=z); placed.append((cx, cy, 0.06, 0.06)); break


@prop
def _ac_unit(x, y, rng, z=2.0):
    B(x - .35, y - .25, z, x + .35, y + .25, z + 0.45, MAT("paint:#8a8a84:0.4"), 0.02)
    cyl(x, y, z + 0.45, z + 0.47, 0.18, MAT("flat:#2a2a28"), 12)


@prop
def _vent(x, y, rng, z=2.0):
    cyl(x, y, z, z + rng.uniform(0.2, 0.35), 0.06, MAT("metal:#7a7a74"), 8)


@prop
def roof_clutter(x, y, rng, z=2.0):
    for k in range(rng.randint(1, 3)):
        px, py = x + rng.uniform(-1.5, 1.5), y + rng.uniform(-1.0, 1.0)
        B(px - .35, py - .25, z, px + .35, py + .25, z + 0.45, MAT("paint:#8a8a84:0.4"), 0.02)
        cyl(px, py, z + 0.45, z + 0.47, 0.18, MAT("flat:#2a2a28"), 12)
    for k in range(rng.randint(1, 3)):
        cyl(x + rng.uniform(-2, 2), y + rng.uniform(-1.5, 1.5), z, z + 0.3, 0.06, MAT("metal:#7a7a74"), 8)
    if rng.random() < 0.4:
        cyl(x + rng.uniform(-1, 1), y + rng.uniform(-1, 1), z, z + 1.6, 0.015, MAT("metal:#6a6a64"), 4)


DEBRIS = {
    "city": [(litter, 6, {"r": 0.7}), (trash_bags, 1.2, {}), (rubble_pile, 2, {"size": 0.5}), (cardboard_boxes, 1, {}),
             (tire_stack, 1, {"n": 1}), (stain, 3, {}), (barrel, 0.5, {}), (pallet, 0.4, {}), (trash_can, 0.6, {"tipped": True}),
             (junk_pile, 0.3, {}), (skeleton, 0.15, {})],
    "suburb": [(litter, 1.2, {"r": 0.6, "n": 4}), (grass_tuft, 6, {}), (deadbush, 2, {}), (stain, 0.4, {}), (tire_stack, 0.3, {"n": 1}),
               (rubble_pile, 0.5, {"size": 0.4}), (pebbles, 2, {}), (trash_bags, 0.25, {"n": 1}), (shrub, 0.6, {})],
    "wild": [(grass_tuft, 8, {}), (pebbles, 3, {}), (deadbush, 2, {}), (rock, 1.2, {}), (shrub, 0.8, {}), (litter, 0.5, {"r": 0.5}),
             (skeleton, 0.08, {}), (tire_stack, 0.1, {"n": 1})],
}


def scatter(x0, y0, x1, y1, density, style, rng, avoid=()):
    """Scatter debris over a rectangle. density = items per 10 square tiles. avoid: rects to keep clear."""
    global PRIO
    old = PRIO; PRIO = 0
    try:
        _scatter(x0, y0, x1, y1, density, style, rng, avoid)
    finally:
        PRIO = old


def _scatter(x0, y0, x1, y1, density, style, rng, avoid):
    pool = DEBRIS[style]
    tot = sum(w for _, w, _ in pool)
    n = int((x1 - x0) * (y1 - y0) * density / 10.0)
    for i in range(n):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        if any(a0 - .3 < x < a1 + .3 and b0 - .3 < y < b1 + .3 for (a0, b0, a1, b1) in avoid):
            continue
        if style == "city":
            import kit as _k
            anchors = [s_[:4] for s_ in _k.SOLIDS] + list(_k.PAVED)
            if anchors:
                d = min(math.hypot(max(a0 - x, 0, x - a1), max(b0 - y, 0, y - b1)) for (a0, b0, a1, b1) in anchors)
                if rng.random() > math.exp(-d / 2.5):
                    continue          # junk thins out away from streets and buildings
        r = rng.uniform(0, tot)
        for fn, w, kw in pool:
            r -= w
            if r <= 0:
                fn(x, y, rng.uniform(0, 360), random.Random(rng.random()), **kw)
                break


# ------------------------------------------------------------------ small furniture for small rooms
@prop
def pantry_shelf(x, y, rng):
    """Narrow metal shelving with cans, jars and boxes — pantries and storage closets."""
    m = MAT("paint:%s:0.45" % rng.choice(["#7a7e78", "#8a8a7a", "#5a6a5a"]))
    w, d, H = 0.8, 0.32, 1.6
    for (a, b) in ((-w / 2, -d / 2), (w / 2, -d / 2), (-w / 2, d / 2), (w / 2, d / 2)):
        B(x + a - .015, y + b - .015, 0, x + a + .015, y + b + .015, H, m)
    for k in range(4):
        z = 0.12 + k * 0.45
        B(x - w / 2, y - d / 2, z, x + w / 2, y + d / 2, z + 0.02, m)
        xx = x - w / 2 + 0.05
        while xx < x + w / 2 - 0.08:
            if rng.random() < 0.6:
                t = rng.random()
                if t < 0.5:
                    cyl(xx + 0.03, y + rng.uniform(-.08, .08), z + 0.02, z + 0.02 + rng.uniform(0.08, 0.14), 0.03, MAT("metal:%s" % rng.choice(["#9a9a90", "#b83a2a", "#c8a040", "#4a6a8a"])), 8)
                elif t < 0.75:
                    cyl(xx + 0.03, y + rng.uniform(-.08, .08), z + 0.02, z + 0.2, 0.035, MAT("flat:%s:0.2" % rng.choice(["#8a6a3a", "#5a7a4a", "#a8a088"])), 8)
                else:
                    B(xx, y - .1, z + .02, xx + .12, y + .1, z + rng.uniform(0.15, 0.3), MAT("flat:%s:0.9" % rng.choice(["#a08058", "#c8b890", "#8a6e4a"])))
            xx += rng.uniform(0.07, 0.12)


@prop
def nightstand(x, y, rng):
    m = wood(rng)
    B(x - .2, y - .18, 0.05, x + .2, y + .18, 0.55, m, 0.01)
    B(x - .17, y + .18, 0.32, x + .17, y + .19, 0.5, m)
    legs4(x - .2, y - .18, x + .2, y + .18, 0.05, m, 0.02, 0.03)
    if rng.random() < 0.6:
        cyl(x - .05, y, 0.55, 0.57, 0.06, MAT("metal:#5a5a54"), 10)
        cyl(x - .05, y, 0.57, 0.8, 0.012, MAT("metal:#8a8a84"), 6)
        bpy_cone = FAST.primitive_cone_add(vertices=10, radius1=0.1, radius2=0.06, depth=0.12, location=g2b(x - .05, y, 0.84))
        bpy_cone.data.materials.append(MAT("fab:#d8c8a0"))
    else:
        clutter_top(x, y, 0.55, rng, 0.12)


@prop
def side_table(x, y, rng):
    m = wood(rng)
    B(x - .22, y - .22, 0.5, x + .22, y + .22, 0.54, m)
    legs4(x - .22, y - .22, x + .22, y + .22, 0.5, m, 0.018, 0.03)
    clutter_top(x, y, 0.54, rng, 0.12)


@prop
def coat_rack(x, y, rng):
    cyl(x, y, 0, 1.6, 0.02, MAT("wood:#5a3e28:#4a3220"), 6)
    for k in range(4):
        a = k * 1.57
        o = B(x - .01, y - .01, 1.45, x + .18, y + .01, 1.48, MAT("wood:#5a3e28:#4a3220"))
        rot_z(o, math.degrees(a), (x, y))
    if rng.random() < 0.6:
        B(x - .1, y + .02, 0.9, x + .1, y + .1, 1.45, fabric(rng))


# ------------------------------------------------------------------ mall / retail
@prop
def clothing_rack(x, y, rng, kind=None):
    """Chrome rack: straight rail or round, with faded garments (some fallen on the floor)."""
    kind = kind or rng.choice(["rail", "round"])
    chrome = MAT("metal:#a8a8a0")
    cols = ["#8a4a3a", "#4a5a7a", "#7a7a5a", "#a88a5a", "#5a6a4a", "#9a8a7a", "#6a4a5a"]
    if kind == "rail":
        for a in (-.55, .55):
            B(x + a - .015, y - .015, 0, x + a + .015, y + .015, 1.25, chrome)
            B(x + a - .02, y - .2, 0, x + a + .02, y + .2, 0.03, chrome)
        B(x - .58, y - .012, 1.22, x + .58, y + .012, 1.25, chrome)
        t = -0.5
        while t < 0.5:
            if rng.random() < 0.7:
                B(x + t, y - .2, rng.uniform(0.45, 0.75), x + t + 0.05, y + .2, 1.2, MAT("fab:%s" % rng.choice(cols)))
            t += rng.uniform(0.06, 0.12)
    else:
        cyl(x, y, 0, 0.03, 0.3, chrome, 12); cyl(x, y, 0, 1.15, 0.015, chrome, 6)
        cyl(x, y, 1.12, 1.15, 0.45, chrome, 20)
        for k in range(rng.randint(5, 12)):
            a = rng.uniform(0, 6.28)
            o = B(x + math.cos(a) * .45 - .03, y + math.sin(a) * .45 - .18, rng.uniform(0.5, 0.75), x + math.cos(a) * .45 + .03, y + math.sin(a) * .45 + .18, 1.1, MAT("fab:%s" % rng.choice(cols)))
            rot_z(o, math.degrees(a) + 90, (x + math.cos(a) * .45, y + math.sin(a) * .45))
    for k in range(rng.randint(0, 3)):
        o = B(x + rng.uniform(-.6, .6) - .2, y + rng.uniform(.2, .5) - .15, 0, x + rng.uniform(-.6, .6) + .2, y + rng.uniform(.2, .5) + .15, 0.03, MAT("fab:%s" % rng.choice(cols)))
        o.rotation_euler.z = rng.uniform(0, 3)


@prop
def mannequin(x, y, rng, fallen=None):
    import kit
    plastic = MAT("paint:%s:0.15" % rng.choice(["#e0d8c8", "#d0c8b8", "#c8bca8"]))
    obs = []
    obs.append(cyl(x, y, 0, 0.03, 0.18, MAT("metal:#5a5a54"), 12)); obs.append(cyl(x, y, 0, 0.55, 0.012, MAT("metal:#5a5a54"), 6))
    body, head, wr = kit.humanoid(plastic, 0.95)
    body.location += g2b(x, y, 0.0); obs.append(body)
    if rng.random() < 0.7:
        obs.append(sphere(x, y, head[2] * 1.0 + 0.1, 0.1, plastic))
    if rng.random() < 0.6:
        obs.append(B(x - .17, y - .1, 0.95, x + .17, y + .1, 1.4, MAT("fab:%s" % rng.choice(["#8a3a3a", "#3a5a8a", "#c8a050", "#5a7a5a"]))))
    if fallen if fallen is not None else rng.random() < 0.35:
        tip(obs, (x, y + 0.15), 86)


@prop
def gondola(x, y, rng, w=2.0, stock=None):
    """Double-sided store shelving unit (along x), stock from full to looted."""
    stock = stock if stock is not None else rng.uniform(0.1, 0.8)
    m = MAT("paint:%s:0.4" % rng.choice(["#d8d0c0", "#a8b0a8", "#c8c0a8"]))
    B(x - w / 2, y - .04, 0, x + w / 2, y + .04, 1.5, m)
    B(x - w / 2, y - .3, 0, x + w / 2, y + .3, 0.12, m)
    for z in (0.5, 0.9, 1.3):
        for sgn in (-1, 1):
            B(x - w / 2, y + sgn * .04 if sgn > 0 else y - .3, z, x + w / 2, y + .3 if sgn > 0 else y - .04, z + 0.02, m)
    goods = ["#b83a2a", "#c8a040", "#4a6a8a", "#5a7a4a", "#a08058", "#d8c8a0", "#7a4a6a"]
    for z in (0.12, 0.52, 0.92, 1.32):
        for sgn in (-1, 1):
            t = -w / 2 + 0.05
            while t < w / 2 - 0.1:
                if rng.random() < stock:
                    h = rng.uniform(0.1, 0.25)
                    B(x + t, y + sgn * 0.08 if sgn > 0 else y - 0.27, z + 0.02, x + t + rng.uniform(0.06, 0.12), y + 0.27 if sgn > 0 else y - 0.08, z + 0.02 + h,
                      MAT("flat:%s:0.6" % rng.choice(goods)))
                t += rng.uniform(0.1, 0.18)
    for k in range(int((1 - stock) * 6)):
        cx, cy = x + rng.uniform(-w / 2, w / 2), y + rng.choice([-1, 1]) * rng.uniform(0.4, 0.8)
        o = B(cx - .05, cy - .05, 0, cx + .05, cy + .05, 0.12, MAT("flat:%s:0.6" % rng.choice(goods)))
        o.rotation_euler = (rng.uniform(0, 1.6), 0, rng.uniform(0, 3))


@prop
def checkout(x, y, rng):
    """Checkout lane: belt counter, register, candy rack, lane light pole."""
    m = MAT("paint:%s:0.35" % rng.choice(["#b8b0a0", "#8a9a8a", "#a89070"]))
    B(x - .9, y - .25, 0, x + .9, y + .25, 0.85, m, 0.02)
    B(x - .85, y - .2, 0.85, x + .4, y + .2, 0.87, MAT("flat:#2a2a28:0.7"))
    B(x + .5, y - .18, 0.87, x + .85, y + .18, 1.07, MAT("paint:#4a4a44:0.4"), 0.01)
    B(x + .55, y - .15, 1.07, x + .8, y - .05, 1.25, MAT("flat:#2a3a3a:0.2"))
    cyl(x + .85, y - .25, 0.85, 2.0, 0.025, MAT("metal:#8a8a84"), 6)
    B(x + .7, y - .32, 1.9, x + 1.0, y - .18, 2.1, MAT("paint:%s:0.3" % rng.choice(["#c84a3a", "#3a6a9a"])))
    B(x - .9, y + .25, 0, x - .4, y + .45, 1.1, MAT("metal:#7a7a74"))


@prop
def cart_corral(x, y, rng, n=None):
    """Pipe-rail cart corral (along x) with a few carts nested inside, some missing."""
    m = MAT("paint:#7a8a6a:0.5")
    L = 2.6
    for sy in (-.35, .35):
        B(x - L / 2, y + sy - .02, 0.85, x + L / 2, y + sy + .02, 0.9, m)
        for t in (-L / 2, 0, L / 2):
            B(x + t - .025, y + sy - .025, 0, x + t + .025, y + sy + .025, 0.9, m)
    B(x + L / 2 - .02, y - .35, 0.85, x + L / 2 + .02, y + .35, 0.9, m)
    for k in range(n if n is not None else rng.randint(0, 3)):
        _cart_parts(x - L / 2 + 0.55 + k * 0.42, y, MAT("metal:#9a9a94"))


def _cart_parts(x, y, m):
    for kk in range(5):
        B(x - .35 + kk * .16, y - .22, 0.35, x - .34 + kk * .16, y + .22, 0.78, m)
    B(x - .35, y - .23, 0.33, x + .35, y + .23, 0.35, m)
    B(x - .35, y - .23, 0.77, x + .35, y + .23, 0.79, m)
    B(x + .35, y - .24, 0.78, x + .46, y + .24, 0.82, MAT("paint:#c84a2a:0.4"))
    for (a, b) in ((-.3, -.18), (.3, -.18), (-.3, .18), (.3, .18)):
        cyl(x + a, y + b, 0, 0.06, 0.035, MAT("flat:#1e1e1e"), 8)


@prop
def pylon_sign(x, y, rng):
    """Tall roadside mall sign on twin posts, panels faded and a few knocked out."""
    m = MAT("paint:#6a6a64:0.5")
    for a in (-.6, .6):
        B(x + a - .1, y - .1, 0, x + a + .1, y + .1, 4.2, m)
    B(x - 1.3, y - .18, 4.2, x + 1.3, y + .18, 5.4, MAT("paint:#b84a3a:0.5"))
    for k in range(3):
        if rng.random() < 0.8:
            B(x - 1.1 + k * 0.75, y + .18, 4.4, x - 0.5 + k * 0.75, y + .19, 5.2, MAT("flat:#e8e0c8:0.6"))
    for k in range(3):
        z = 3.0 - k * 0.7
        c = rng.choice(["#3a5a8a", "#c8a040", "#5a7a5a", "#7a4a6a"])
        if rng.random() < 0.75:
            B(x - 1.0, y - .12, z, x + 1.0, y + .12, z + 0.55, MAT("paint:%s:0.5" % c))
            B(x - 0.8, y + .12, z + 0.15, x + rng.uniform(-0.2, 0.7), y + .13, z + 0.4, MAT("flat:#e8e0c8:0.6"))


@prop
def planter(x, y, rng, r=0.9, tree_kind="dead"):
    """Concrete planter with dried soil, a dead tree and weeds."""
    c = MAT("conc:#9a968a")
    B(x - r, y - r, 0, x + r, y + r, 0.45, c, 0.02)
    B(x - r + .1, y - r + .1, 0.45, x + r - .1, y + r - .1, 0.4501, MAT("flat:#4a3e30:1.0"))
    tree(x, y, 0, random.Random(rng.random()), kind=tree_kind)
    for k in range(rng.randint(1, 3)):
        grass_tuft(x + rng.uniform(-r + .2, r - .2), y + rng.uniform(-r + .2, r - .2), 0, rng)
    bpy.context.view_layer.update()


@prop
def kiosk(x, y, rng):
    """Mall concourse kiosk: counter ring with a canopy on posts."""
    m = MAT("paint:%s:0.4" % rng.choice(["#3e7a6a", "#b03a26", "#c8a040"]))
    B(x - .8, y - .5, 0, x + .8, y + .5, 0.95, m, 0.02)
    B(x - .85, y - .55, 0.95, x + .85, y + .55, 1.0, MAT("paint:#d8d0bc:0.3"))
    for (a, b) in ((-.75, -.45), (.75, -.45), (-.75, .45), (.75, .45)):
        B(x + a - .02, y + b - .02, 1.0, x + a + .02, y + b + .02, 2.0, MAT("metal:#8a8a84"))
    B(x - .9, y - .6, 2.0, x + .9, y + .6, 2.1, m)
    clutter_top(x, y, 1.0, rng, 0.5)


@prop
def bus_stop(x, y, rng):
    m = MAT("metal:#6a7a7a")
    for a in (-.9, .9):
        B(x + a - .03, y - .4, 0, x + a + .03, y - .34, 2.1, m)
        B(x + a - .03, y + .34, 0, x + a + .03, y + .4, 2.1, m)
    B(x - 1.0, y - .45, 2.1, x + 1.0, y + .45, 2.16, MAT("paint:#b84a3a:0.5"))
    B(x - .9, y - .4, 0.6, x + .9, y - .37, 2.0, MAT("glass:#2a3a40") if False else MAT("flat:#3a4a50:0.2"))
    B(x - .8, y - .25, 0.42, x + .8, y + .05, 0.47, MAT("wood:#6a5034:#5a4028"))


@prop
def pothole(x, y, rng, r=None):
    r = r or rng.uniform(0.25, 0.55)
    for k in range(rng.randint(2, 3)):
        o = cyl(x + rng.uniform(-r, r) * .4, y + rng.uniform(-r, r) * .4, 0.0, 0.0105 + k * 0.0003, r * rng.uniform(0.5, 0.9),
                MAT("flat:%s:1.0" % rng.choice(["#2a2622", "#3a342c", "#4a4034"])), 10)
        o.scale = (1, rng.uniform(0.5, 0.9), 1); o.rotation_euler.z = rng.uniform(0, 6)
    if rng.random() < 0.5:
        pebbles(x, y, 0, rng, n=5, r=r)


@prop
def weeds_line(x, y, rng, L=2.0, axis="x"):
    """Weeds pushing up through a crack or a painted line."""
    for k in range(int(L / 0.3)):
        t = -L / 2 + k * 0.3 + rng.uniform(-.1, .1)
        if rng.random() < 0.6:
            grass_tuft(x + (t if axis == "x" else rng.uniform(-.06, .06)), y + (t if axis == "y" else rng.uniform(-.06, .06)), 0, rng, n=rng.randint(2, 5))
