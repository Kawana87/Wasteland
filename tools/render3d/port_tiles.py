"""Port tile sprites and tiling textures:
  diamonds (48x24, anchor [24,0]): floor_*, roof_flat0-2, roof_tin, roof_canopy, garden, stairs_up/down
  screen-space tiling textures (48x24, used by roof polygons): shingle_x/y0-4, gable_x/y0-11
All materials are periodic with period 1 tile (noise sampled in 4D on two circles), so tiles and texture
repeats join without seams. Gable textures also repeat every 16 game px vertically (the texture's lattice).
python3 port_tiles.py"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from lib import reset, lights, _nodes, _hex
import fast as FAST
import port_common as PC
from port_common import gz
from port_walls import NB, WALLS

TAU = 2 * math.pi
ROOFS = ["#6a4a3e", "#4a5058", "#7a3a2e", "#3e5a4e", "#8a7a5a"]


def pcoords(nb, plane="xy", vper=1.0):
    """Linear (u, v) and a periodic noise input for a plane. plane xy: horizontal, u=game x, v=game y.
    plane xz: south-facing wall plane (u=x, v=z/vper); plane yz: east-facing (u=game y, v=z/vper)."""
    tc = nb.n("ShaderNodeTexCoord")
    sep = nb.n("ShaderNodeSeparateXYZ"); nb.link(tc.outputs["Object"], sep.inputs[0])
    gx, gy, z = sep.outputs[0], nb.math('MULTIPLY', sep.outputs[1], -1.0), sep.outputs[2]
    if plane == "xy":
        u, v = gx, gy
    elif plane == "xz":
        u, v = gx, nb.math('DIVIDE', z, vper)
    else:
        u, v = gy, nb.math('DIVIDE', z, vper)
    r = 1 / TAU
    au, av = nb.math('MULTIPLY', u, TAU), nb.math('MULTIPLY', v, TAU)
    vec = nb.combine(nb.math('MULTIPLY', nb.math('COSINE', au), r), nb.math('MULTIPLY', nb.math('SINE', au), r),
                     nb.math('MULTIPLY', nb.math('COSINE', av), r))
    w = nb.math('MULTIPLY', nb.math('SINE', av), r)
    return u, v, vec, w


def pnoise(nb, vec, w, scale, detail=4.0, rough=0.6):
    nd = nb.n("ShaderNodeTexNoise")
    nd.noise_dimensions = '4D'
    nd.inputs["Scale"].default_value = scale
    nd.inputs["Detail"].default_value = detail
    nd.inputs["Roughness"].default_value = rough
    nb.link(vec, nd.inputs["Vector"]); nb.link(w, nd.inputs["W"])
    return nd.outputs[0]


def brick(nb, u, v, width, row, c1, c2, mortar, msize=0.012, offset=0.5):
    br = nb.n("ShaderNodeTexBrick")
    br.offset = offset
    br.inputs["Scale"].default_value = 1.0
    br.inputs["Mortar Size"].default_value = msize
    br.inputs["Brick Width"].default_value = width
    br.inputs["Row Height"].default_value = row
    for k, c in (("Color1", c1), ("Color2", c2), ("Mortar", mortar)):
        br.inputs[k].default_value = _hex(c)
    nb.link(nb.combine(u, v, 0.0), br.inputs["Vector"])
    return br.outputs["Color"], br.outputs["Fac"]


def finish(nb, bs, col, rough=0.9, bump=None, strength=0.3):
    nb.link(col, bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = rough
    if bump is not None:
        bp = nb.n("ShaderNodeBump"); bp.inputs["Strength"].default_value = strength; bp.inputs["Distance"].default_value = 0.01
        nb.link(bump, bp.inputs["Height"]); nb.link(bp.outputs["Normal"], bs.inputs["Normal"])


def dark(c, f):
    h = c.lstrip('#'); r, g, b = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    return "#%02x%02x%02x" % (int(r * f), int(g * f), int(b * f))


def mat_tile(kind, arg=None):
    m, nt, bs = _nodes("tile_%s_%s" % (kind, arg))
    nb = NB(nt)
    plane = "xy"
    if kind == "gable":
        plane = "xz" if arg[1] == "x" else "yz"
    u, v, vec, w = pcoords(nb, plane, gz(16) if kind == "gable" else 1.0)
    n1 = pnoise(nb, vec, w, 4.0, 5.0, 0.6)
    var = nb.math('ADD', 0.88, nb.math('MULTIPLY', n1, 0.24))
    bump = None
    if kind == "carpet":
        col = nb.mul_col("#8a3a34", var)
        dots = nb.math('MULTIPLY', nb.math('LESS_THAN', nb.math('FRACT', nb.math('MULTIPLY', u, 6)), 0.25),
                       nb.math('LESS_THAN', nb.math('FRACT', nb.math('MULTIPLY', v, 6)), 0.25))
        col = nb.mix(col, '#b85a44', dots)
        worn = nb.math('GREATER_THAN', pnoise(nb, vec, w, 2.5, 4.0, 0.6), 0.6)
        col = nb.mix(col, '#7a5a4a', nb.math('MULTIPLY', worn, 0.5))
    elif kind == "concrete":
        col = nb.mul_col("#8e897e", var)
        seam = nb.math('MAXIMUM', nb.math('LESS_THAN', nb.math('FRACT', u), 0.012), nb.math('LESS_THAN', nb.math('FRACT', v), 0.012))
        col = nb.mix(col, '#5a564e', seam)
    elif kind == "lino":
        ch = nb.n("ShaderNodeTexChecker"); ch.inputs["Scale"].default_value = 1.0
        ch.inputs["Color1"].default_value = _hex('#9ac0b0'); ch.inputs["Color2"].default_value = _hex('#e2dac2')
        nb.link(nb.combine(nb.math('MULTIPLY', u, 2.0), nb.math('MULTIPLY', v, 2.0), 0.0), ch.inputs["Vector"])
        col = nb.mul_col(ch.outputs["Color"], var)
    elif kind == "tile":
        ch = nb.n("ShaderNodeTexChecker"); ch.inputs["Scale"].default_value = 1.0
        ch.inputs["Color1"].default_value = _hex('#24201e'); ch.inputs["Color2"].default_value = _hex('#e6decc')
        nb.link(nb.combine(nb.math('MULTIPLY', u, 4.0), nb.math('MULTIPLY', v, 4.0), 0.0), ch.inputs["Vector"])
        col = nb.mul_col(ch.outputs["Color"], var)
    elif kind == "wood":
        col, bump = brick(nb, u, v, 0.5, 1 / 6, '#8a5a36', '#74482a', '#3a2618', 0.01)
        col = nb.mul_col(col, var)
    elif kind == "flat":
        base = ["#6e6a60", "#4c4c52", "#7a7466"][arg]
        col = nb.mul_col(base, var)
        grav = nb.math('GREATER_THAN', pnoise(nb, vec, w, 40.0, 2.0, 0.5), 0.62)
        col = nb.mix(col, dark(base, 1.35), nb.math('MULTIPLY', grav, 0.6))
        seam = nb.math('LESS_THAN', nb.math('FRACT', nb.math('ADD', u, 0.5)), 0.01)
        col = nb.mix(col, dark(base, 0.7), seam)
        stain = nb.math('GREATER_THAN', pnoise(nb, vec, w, 2.0, 4.0, 0.6), 0.62)
        col = nb.mix(col, dark(base, 0.75), nb.math('MULTIPLY', stain, 0.5))
    elif kind == "tin":
        rib = nb.math('SINE', nb.math('MULTIPLY', v, TAU * 10))
        col = nb.mul_col(nb.mul_col("#8a8478", var), nb.math('ADD', 0.86, nb.math('MULTIPLY', rib, 0.14)))
        rust = nb.math('GREATER_THAN', pnoise(nb, vec, w, 3.0, 5.0, 0.7), 0.56)
        col = nb.mix(col, '#8a4a2a', nb.math('MULTIPLY', rust, 0.75))
        bump = rib
    elif kind == "canopy":
        col = nb.mul_col("#e0dccb", nb.math('ADD', 0.92, nb.math('MULTIPLY', n1, 0.1)))
        seam = nb.math('LESS_THAN', nb.math('FRACT', nb.math('MULTIPLY', u, 2.0)), 0.015)
        col = nb.mix(col, '#a8a498', seam)
    elif kind == "garden":
        f = nb.math('FRACT', nb.math('MULTIPLY', v, 3.0))
        col = nb.mul_col(nb.ramp(f, [(0.0, '#4a3424'), (0.3, '#6a4a30'), (0.5, '#7a5a3a'), (0.75, '#5a4028'), (1.0, '#4a3424')]), var)
        bump = nb.math('SINE', nb.math('MULTIPLY', v, TAU * 3))
    elif kind == "shingle":
        i, ax = arg
        base = ROOFS[i]
        uu, vv = (u, v) if ax == "x" else (v, u)
        col, fac = brick(nb, uu, vv, 1 / 3, 1 / 6, base, dark(base, 0.86), dark(base, 0.62), 0.012)
        col = nb.mul_col(col, var)
        # each course slightly darker at its lower edge (the overlap shadow)
        f = nb.math('FRACT', nb.math('MULTIPLY', vv, 6.0))
        col = nb.mul_col(col, nb.ramp(f, [(0.0, '#bcbcbc'), (0.22, '#ffffff'), (1.0, '#f0f0f0')]))
        moss = nb.math('GREATER_THAN', pnoise(nb, vec, w, 2.5, 5.0, 0.7), 0.64)
        col = nb.mix(col, '#5a6a44', nb.math('MULTIPLY', moss, 0.35))
        bump = fac
    elif kind == "gable":
        pi, ax = arg
        style, base, trim = WALLS[pi]
        if style in ("streamline", "concrete", "panel"):
            style = "plaster"
        if style == "siding":
            f = nb.math('FRACT', nb.math('MULTIPLY', v, 5.0))
            col = nb.mul_col(nb.mul_col(base, var), nb.ramp(f, [(0.0, '#9a9a9a'), (0.16, '#c4c4c4'), (0.2, '#ffffff'), (1.0, '#f2f2f2')]))
            bump = f
        elif style == "brick":
            col, bump = brick(nb, u, v, 0.25, 1 / 7, base, dark(base, 0.82), trim, 0.012 / gz(16))
            col = nb.mul_col(col, var)
        elif style == "tin":
            rib = nb.math('SINE', nb.math('MULTIPLY', u, TAU * 14))
            col = nb.mul_col(nb.mul_col(base, var), nb.math('ADD', 0.86, nb.math('MULTIPLY', rib, 0.14)))
            bump = rib
        else:
            col = nb.mul_col(base, var)
    else:
        raise ValueError(kind)
    finish(nb, bs, col, 0.9, bump)
    return m


def plane(mat, kind="xy", x0=-0.004, x1=1.004, y0=-0.004, y1=1.004):
    b = FAST.Batch("pl")
    if kind == "xy":
        b.cube(Vector(((x0 + x1) / 2, -(y0 + y1) / 2, -0.001)), (x1 - x0, y1 - y0, 0.002), mat)
    elif kind == "xz":
        b.cube(Vector((0, 0.0, 0)), (8, 0.002, 8), mat)
    else:
        b.cube(Vector((0.0, 0, 0)), (0.002, 8, 8), mat)
    return b.done()


def stairs(up=True):
    """Flat stair sprite on a floor tile (it is drawn at floor level): treads across the tile, lit edges
    stepping up (up) or darkening into a well (down)."""
    b = FAST.Batch("stairs")
    wood = PC_flat("#9a7a50"); wood_d = PC_flat("#5a4028"); dk = PC_flat("#16120e"); edge = PC_flat("#c8a878")
    n = 5
    b.cube(Vector((0.5, -0.5, -0.001)), (1.0, 1.0, 0.002), dk if not up else wood_d)
    for k in range(n):
        x0, x1 = k / n + 0.01, (k + 1) / n - 0.01
        if up:
            col = wood if k % 2 == 0 else PC_flat("#8a6a44")
        else:
            col = PC_flat(["#7a5a3a", "#5a4230", "#3e2e22", "#2a2018", "#1e1812"][k])
        b.cube(Vector(((x0 + x1) / 2, -0.5, 0.0005)), (x1 - x0, 0.84, 0.001), col)
        b.cube(Vector((x1 - 0.01 if up else x0 + 0.01, -0.5, 0.001)), (0.02, 0.84, 0.001), edge if up else wood_d)
    for yy in (0.06, 0.94):
        b.cube(Vector((0.5, -yy, 0.001)), (1.0, 0.1, 0.001), wood_d)
    return b.done()


_F = {}


def PC_flat(col):
    from lib import mat_flat
    if col not in _F:
        _F[col] = mat_flat("f" + col, col, 0.85, noise=0.12)
    return _F[col]


def garden_plants(rng):
    b = FAST.Batch("plants")
    leaf = PC_flat("#5a8a3a"); leaf2 = PC_flat("#7aa04a"); red = PC_flat("#c84a3a")
    for r_ in range(3):
        yy = (r_ + 0.5) / 3
        for k in range(4):
            xx = (k + 0.5) / 4 + rng.uniform(-0.06, 0.06)
            s = rng.uniform(0.06, 0.09)
            b.ico(Vector((xx, -yy, gz(3))), s, leaf if k % 2 else leaf2, scale=(1, 1, 0.8))
            if rng.random() < 0.4:
                b.ico(Vector((xx + 0.04, -yy + 0.03, gz(4.5))), 0.022, red)
    return b.done(smooth=True)


def main(only=None):
    reset()
    lights()
    rng = random.Random(3)
    diamonds = [("floor_carpet", ("carpet", None)), ("floor_concrete", ("concrete", None)), ("floor_lino", ("lino", None)),
                ("floor_tile", ("tile", None)), ("floor_wood", ("wood", None)), ("roof_flat0", ("flat", 0)),
                ("roof_flat1", ("flat", 1)), ("roof_flat2", ("flat", 2)), ("roof_tin", ("tin", None)),
                ("roof_canopy", ("canopy", None)), ("garden", ("garden", None))]
    for name, (k, a) in diamonds:
        obs = [plane(mat_tile(k, a))]
        if k == "garden":
            obs.append(garden_plants(rng))
        PC.sprite(name, 48, 24, 24, 0, samples=16, bright=1.12, alpha_cut=100)
        PC.clear(obs)
    for name, up in (("stairs_up", True), ("stairs_down", False)):
        ob = stairs(up)
        PC.sprite(name, 48, 24, 24, 0, samples=16, bright=1.12, alpha_cut=100)
        PC.clear([ob])
    print("diamonds done", flush=True)
    for i in range(len(ROOFS)):
        for ax in "xy":
            ob = plane(mat_tile("shingle", (i, ax)), "xy", -3, 3, -3, 3)
            PC.sprite("shingle_%s%d" % (ax, i), 48, 24, 24, 12, samples=16, bright=1.12)
            PC.clear([ob])
    for pi in range(len(WALLS)):
        for ax in "xy":
            ob = plane(mat_tile("gable", (pi, ax)), "xz" if ax == "x" else "yz")
            PC.sprite("gable_%s%d" % (ax, pi), 48, 24, 24, 12, samples=16, bright=1.12 * (1.08 if ax == "x" else 1.0))
            PC.clear([ob])
    print("textures done", flush=True)


if __name__ == "__main__":
    main()
