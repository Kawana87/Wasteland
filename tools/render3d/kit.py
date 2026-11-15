"""Reusable building blocks for the pre-rendered art: materials, thin walls with openings, doors,
windows, roofs, houses with multi-part footprints, and creatures built with Blender's skin modifier."""
import math, random
import bpy
from lib import *
from lib import _nodes, _mix, _coord, _noise, _ramp, _bump, _hex, grit, grime, cracks

WALL_T = 0.11
STOREY = 2.0
R = random.Random(7)


# ------------------------------------------------------------------ extra materials
def mat_siding(name, paint, axis_free=True, peel=0.45):
    """Clapboard siding: horizontal boards with shadow lines, peeling paint."""
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    w = nt.nodes.new("ShaderNodeTexWave")
    w.wave_type = 'BANDS'; w.bands_direction = 'Z'; w.wave_profile = 'SAW'
    w.inputs["Scale"].default_value = 7.0
    w.inputs["Distortion"].default_value = 0.0
    nt.links.new(co, w.inputs["Vector"])
    lines = _ramp(nt, w.outputs["Fac"], [(0.0, '#5a5a5a'), (0.12, '#ffffff'), (0.9, '#e8e8e8'), (1.0, '#b0b0b0')])
    n = _noise(nt, co, 5.0, 8.0, 0.7)
    peelf = _ramp(nt, n.outputs[0], [(1 - peel - 0.03, '#000000'), (1 - peel + 0.03, '#ffffff')])
    col = _mix(nt, paint, '#7a6e5c', peelf)
    mm = nt.nodes.new("ShaderNodeMix"); mm.data_type = 'RGBA'; mm.blend_type = 'MULTIPLY'; mm.inputs[0].default_value = 1.0
    nt.links.new(col, mm.inputs[6]); nt.links.new(lines, mm.inputs[7])
    nt.links.new(grit(nt, grime(nt, mm.outputs[2], co, 0.55), co, 0.35), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.9
    _bump(nt, bs, w.outputs["Fac"], 0.5, 0.02)
    return m


def mat_shingles(name, col, col2, axis='x'):
    """Roof shingles: rows run parallel to the ridge. axis = ridge direction (game)."""
    m, nt, bs = _nodes(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Rotation"].default_value = (0, 0, 0 if axis == 'x' else math.radians(90))
    nt.links.new(tc.outputs["Object"], mp.inputs[0])
    b = nt.nodes.new("ShaderNodeTexBrick")
    b.inputs["Scale"].default_value = 1.0
    b.inputs["Mortar Size"].default_value = 0.012
    b.inputs["Color1"].default_value = _hex(col)
    b.inputs["Color2"].default_value = _hex(col2)
    b.inputs["Mortar"].default_value = _hex('#1e1a18')
    b.inputs["Brick Width"].default_value = 0.28
    b.inputs["Row Height"].default_value = 0.11
    nt.links.new(mp.outputs[0], b.inputs["Vector"])
    c = grime(nt, b.outputs["Color"], mp.outputs[0], 0.5, False)
    n = _noise(nt, mp.outputs[0], 2.0, 6.0, 0.6)
    moss = _ramp(nt, n.outputs[0], [(0.62, '#000000'), (0.7, '#ffffff')])
    c = _mix(nt, c, '#4a4a30', moss)
    nt.links.new(grit(nt, c, mp.outputs[0], 0.35), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.9
    _bump(nt, bs, b.outputs["Fac"], 0.7, 0.02)
    return m


def mat_tin(name, axis='x'):
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    w = nt.nodes.new("ShaderNodeTexWave")
    w.wave_type = 'BANDS'; w.bands_direction = 'X' if axis == 'x' else 'Y'
    w.inputs["Scale"].default_value = 9.0
    w.inputs["Distortion"].default_value = 0.0
    nt.links.new(co, w.inputs["Vector"])
    corr = _ramp(nt, w.outputs["Fac"], [(0.0, '#8a8a8a'), (0.5, '#ffffff'), (1.0, '#8a8a8a')])
    n = _noise(nt, co, 3.0, 8.0, 0.7)
    rust = _ramp(nt, n.outputs[0], [(0.35, '#000000'), (0.6, '#ffffff')])
    col = _mix(nt, '#8a8a84', '#7a4424', rust)
    mm = nt.nodes.new("ShaderNodeMix"); mm.data_type = 'RGBA'; mm.blend_type = 'MULTIPLY'; mm.inputs[0].default_value = 1.0
    nt.links.new(col, mm.inputs[6]); nt.links.new(corr, mm.inputs[7])
    nt.links.new(grit(nt, mm.outputs[2], co, 0.3), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.7
    bs.inputs["Metallic"].default_value = 0.5
    _bump(nt, bs, w.outputs["Fac"], 0.6, 0.02)
    return m


def mat_skin_rot(name, a='#8a7a56', b='#5a4a34', c='#9a6a5a'):
    """Mottled, rotting skin for ghouls."""
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    n = _noise(nt, co, 9.0, 8.0, 0.7)
    col = _ramp(nt, n.outputs[0], [(0.35, b), (0.5, a), (0.62, c), (0.72, b)])
    nt.links.new(grit(nt, col, co, 0.4, 60.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.6
    _bump(nt, bs, n.outputs[0], 0.8, 0.01)
    return m


def mat_hide(name, a, b, spots=0.5, scale=4.0, rough=0.8):
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    n = _noise(nt, co, scale, 6.0, 0.6)
    col = _ramp(nt, n.outputs[0], [(spots - 0.03, a), (spots + 0.03, b)])
    n2 = _noise(nt, co, 40.0, 4.0, 0.6)
    fur = _ramp(nt, n2.outputs[0], [(0.3, '#9a9a9a'), (0.7, '#ffffff')])
    mm = nt.nodes.new("ShaderNodeMix"); mm.data_type = 'RGBA'; mm.blend_type = 'MULTIPLY'; mm.inputs[0].default_value = 0.6
    nt.links.new(col, mm.inputs[6]); nt.links.new(fur, mm.inputs[7])
    nt.links.new(mm.outputs[2], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = rough
    _bump(nt, bs, n2.outputs[0], 0.4, 0.01)
    return m


def mat_two(name, top, bottom, zcut):
    m, nt, bs = _nodes(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    cmp = nt.nodes.new("ShaderNodeMath"); cmp.operation = 'GREATER_THAN'
    nt.links.new(sep.outputs[2], cmp.inputs[0]); cmp.inputs[1].default_value = zcut
    if isinstance(top, str) and isinstance(bottom, str):
        col = _mix(nt, bottom, top, cmp.outputs[0])
    co = _coord(nt)
    n = _noise(nt, co, 25.0, 6.0, 0.6)
    folds = _ramp(nt, n.outputs[0], [(0.3, '#9a9a9a'), (0.7, '#ffffff')])
    mm = nt.nodes.new("ShaderNodeMix"); mm.data_type = 'RGBA'; mm.blend_type = 'MULTIPLY'; mm.inputs[0].default_value = 0.5
    nt.links.new(col, mm.inputs[6]); nt.links.new(folds, mm.inputs[7])
    nt.links.new(mm.outputs[2], bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.8
    return m


def materials():
    M = {
        "stucco": mat_stucco("stucco", '#a89c84', '#6a604e'),
        "brick": mat_brick("brick"), "brick_y": mat_brick("brick_y", axis='y'),
        "cap": mat_flat("cap", '#2e2a28', 0.9, noise=0.1),
        "dirt": mat_ground("dirt"), "asphalt": mat_asphalt("asphalt"), "conc": mat_concrete("conc"),
        "frame": mat_flat("frame", '#3a302a', 0.8), "trim": mat_flat("trim", '#d8d0bc', 0.8, noise=0.25),
        "glass": mat_flat("glass", '#2a3a40', 0.15, metal=0.2, noise=0.0),
        "door": mat_planks("door", '#5a3a2a', '#4a2e20'), "door_paint": mat_paint_rust("door_paint", '#8a3a2a', 0.35),
        "wood": mat_planks("wood", '#7a5a3a', '#6a4a2e'), "board": mat_planks("board", '#8a6a44', '#6e5234'),
        "metal": mat_paint_rust("metal", '#7a7e78', 0.35), "brass": mat_flat("brass", '#b8963a', 0.35, metal=0.9, noise=0.0),
        "chain": mat_flat("chain", '#6a6a66', 0.4, metal=0.9, noise=0.0),
        "barrel": mat_paint_rust("barrel", '#8a6a2a', 0.55), "tire": mat_flat("tire", '#1e1c1a', 0.9),
        "red": mat_paint_rust("red", '#b03a26', 0.35), "bark": mat_flat("bark", '#4a3a2c', 0.95, noise=0.4),
        "rubble": mat_concrete("rubble", '#8a8276'), "char": mat_flat("char", '#1e1a18', 0.95, noise=0.4),
        "skin": mat_flat("skin", '#c89070', 0.6, noise=0.1), "boots": mat_flat("boots", '#2e2420', 0.7, noise=0.1),
        "tin": mat_tin("tin"), "tin_y": mat_tin("tin_y", 'y'),
        "white": mat_flat("white", '#e0d8c8', 0.4, noise=0.0), "black": mat_flat("black", '#141210', 0.4, noise=0.0),
    }
    for nm, (a, b) in {"sh_brown": ('#5a4034', '#4a3428'), "sh_slate": ('#4a5058', '#3e434a'), "sh_red": ('#7a3a2e', '#64302a'),
                       "sh_green": ('#3e5a4e', '#344c42')}.items():
        M[nm + "_x"] = mat_shingles(nm + "_x", a, b, 'x')
        M[nm + "_y"] = mat_shingles(nm + "_y", a, b, 'y')
    for nm, col in {"seafoam": '#7fa596', "cream": '#d6c79a', "salmon": '#c88c74', "blue": '#8ea6b8', "mint": '#a8c4a0'}.items():
        M["siding_" + nm] = mat_siding("siding_" + nm, col)
    return M


# ------------------------------------------------------------------ mesh helpers
def mesh(verts, faces, mat, name="mesh", smooth=False, solidify=0.0):
    me = bpy.data.meshes.new(name)
    me.from_pydata([g2b(*v) for v in verts], [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob); __import__('lib').REG.append(ob)
    me.materials.append(mat)
    if smooth:
        for p in me.polygons: p.use_smooth = True
    if solidify:
        md = ob.modifiers.new("sol", 'SOLIDIFY'); md.thickness = solidify
    return ob


def pivot_rot(obs, deg, px, py):
    for o in obs:
        rot_z(o, deg, (px, py))


# ------------------------------------------------------------------ walls, windows, doors
def wall_run(M, a, b, h, mat, openings=(), cap=True, z0=0.0, frames=True):
    """Straight wall on a tile edge from a to b (game xy). openings: list of (t0, t1, oz0, oz1, kind)."""
    horiz = abs(a[1] - b[1]) < 1e-6
    L = abs(b[0] - a[0]) if horiz else abs(b[1] - a[1])
    lo = min(a[0], b[0]) if horiz else min(a[1], b[1])
    fixed = a[1] if horiz else a[0]
    jit = R.uniform(-0.003, 0.003)      # tiny thickness offset so overlapping corners never z-fight
    E = WALL_T                          # walls run past their ends into the corner column

    def slab(t0, t1, za, zb, m=mat, th=WALL_T + jit, name="wall"):
        if t1 - t0 < 1e-4 or zb - za < 1e-4:
            return None
        if horiz:
            return box(lo + t0, fixed - th, z0 + za, lo + t1, fixed + th, z0 + zb, m, name=name)
        return box(fixed - th, lo + t0, z0 + za, fixed + th, lo + t1, z0 + zb, m, name=name)
    t = -E
    for (o0, o1, oz0, oz1, kind) in sorted(openings):
        slab(t, o0, 0, h)
        slab(o0, o1, 0, min(oz0, h))
        slab(o0, o1, min(oz1, h), h)
        fr = 0.06
        if not frames or oz0 >= h:
            t = o1
            continue
        slab(o0 - fr, o0, oz0 - (fr if oz0 > 0 else 0), oz1 + fr, M["trim"], WALL_T + 0.025, "frame")
        slab(o1, o1 + fr, oz0 - (fr if oz0 > 0 else 0), oz1 + fr, M["trim"], WALL_T + 0.025, "frame")
        slab(o0, o1, oz1, oz1 + fr, M["trim"], WALL_T + 0.025, "frame")
        if oz0 > 0.05:
            slab(o0 - fr, o1 + fr, oz0 - fr, oz0, M["trim"], WALL_T + 0.05, "sill")
        t = o1
    slab(t, L + E, 0, h)
    if cap:
        # thin top course in the wall's own material, broken at any opening that reaches the top
        # (doorways through cut-away walls): it never bridges a threshold
        t = -E
        for (o0, o1, oz0, oz1, kind) in sorted(openings):
            if oz1 >= h - 1e-3:
                slab(t, o0, h, h + 0.02, mat, WALL_T + 0.004 + jit, "cap")
                t = o1
        slab(t, L + E, h, h + 0.02, mat, WALL_T + 0.004 + jit, "cap")


def edge_point(a, b, t, out_n, off=0.0):
    horiz = abs(a[1] - b[1]) < 1e-6
    lo = min(a[0], b[0]) if horiz else min(a[1], b[1])
    if horiz:
        return (lo + t, a[1] + out_n[1] * off)
    return (a[0] + out_n[0] * off, lo + t)


PLANK_H = 0.13        # every board in the game has the same cross-section
PLANK_MAX = 1.6       # longest single board; wider openings get butt-jointed boards


def board_up(make, t0, t1, z0, z1, axis, over=0.08, tilt=5.0):
    """Nail boards across an opening. All boards share one size: the count follows the opening's height,
    the length follows its width (split into equal boards when wider than PLANK_MAX), same overhang each side."""
    W = (t1 - t0) + 2 * over
    nseg = max(1, math.ceil(W / PLANK_MAX)); seg = W / nseg
    n = max(2, round((z1 - z0) / 0.26))
    obs = []
    for k in range(n):
        zc = z0 + (z1 - z0) * (k + 0.5) / n
        stagger = (seg * 0.5 if (k % 2 and nseg > 1) else 0.0)
        a = t0 - over
        cuts = [a] + [a + stagger + seg * i for i in range(1, nseg)] + [t1 + over]
        for i in range(len(cuts) - 1):
            ob = make(cuts[i] + 0.005, cuts[i + 1] - 0.005, zc - PLANK_H / 2, zc + PLANK_H / 2)
            ob.rotation_euler.rotate_axis(axis, math.radians(R.uniform(-tilt, tilt)))
            obs.append(ob)
    return obs


def window(M, a, b, t0, t1, z0, z1, out_n, state="glass", shutters=None, zbase=0.0):
    horiz = abs(a[1] - b[1]) < 1e-6
    lo = min(a[0], b[0]) if horiz else min(a[1], b[1])
    fx = a[1] if horiz else a[0]
    def pane(s0, s1, za, zb, m, off=0.0, th=0.012):
        if horiz:
            return box(lo + s0, fx + out_n[1] * off - th, zbase + za, lo + s1, fx + out_n[1] * off + th, zbase + zb, m)
        return box(fx + out_n[0] * off - th, lo + s0, zbase + za, fx + out_n[0] * off + th, lo + s1, zbase + zb, m)
    n = 2
    for i in range(n):
        s0 = t0 + (t1 - t0) * i / n + 0.01
        s1 = t0 + (t1 - t0) * (i + 1) / n - 0.01
        if state == "glass" or (state == "broken" and R.random() < 0.4):
            pane(s0, s1, z0, z1, M["glass"])
        else:
            pane(s0, s1, z0, z1, M["black"], -0.05)
    pane((t0 + t1) / 2 - 0.02, (t0 + t1) / 2 + 0.02, z0, z1, M["trim"], 0.0, 0.03)
    pane(t0, t1, (z0 + z1) / 2 - 0.02, (z0 + z1) / 2 + 0.02, M["trim"], 0.0, 0.03)
    if state == "boarded":
        board_up(lambda p0, p1, za, zb: pane(p0, p1, za, zb, M["board"], WALL_T + 0.04, 0.02), t0, t1, z0, z1, 'Y' if horiz else 'X')
    if shutters:
        w = (t1 - t0) * 0.42
        pane(t0 - 0.08 - w, t0 - 0.08, z0 - 0.04, z1 + 0.04, shutters, WALL_T + 0.02, 0.02)
        pane(t1 + 0.08, t1 + 0.08 + w, z0 - 0.04, z1 + 0.04, shutters, WALL_T + 0.02, 0.02)


def door(M, a, b, t0, t1, out_n, state="closed", paint=None):
    """Door in a doorway. state: open, closed, locked, boarded, broken."""
    horiz = abs(a[1] - b[1]) < 1e-6
    lo = min(a[0], b[0]) if horiz else min(a[1], b[1])
    fx = a[1] if horiz else a[0]
    H = 1.55
    mat = paint or M["door_paint"]
    obs = []
    def slab(s0, s1, za, zb, m, off, th):
        if horiz:
            return box(lo + s0, fx + out_n[1] * off - th, za, lo + s1, fx + out_n[1] * off + th, zb, m)
        return box(fx + out_n[0] * off - th, lo + s0, za, fx + out_n[0] * off + th, lo + s1, zb, m)
    # stoop outside
    if horiz:
        box(lo + t0 - 0.15, fx + out_n[1] * 0.12 - 0.22, 0, lo + t1 + 0.15, fx + out_n[1] * 0.12 + 0.22, 0.09, M["conc"])
    else:
        box(fx + out_n[0] * 0.12 - 0.22, lo + t0 - 0.15, 0, fx + out_n[0] * 0.12 + 0.22, lo + t1 + 0.15, 0.09, M["conc"])
    if state == "broken":
        d = slab(t0, t1, 0.0, 0.05, mat, 0.6, 0.0)  # door lying on the ground outside, flat
        if horiz:
            d.location += g2b(0, out_n[1] * 0.3, 0)
        return
    d = slab(t0 + 0.02, t1 - 0.02, 0.0, H - 0.02, mat, 0.0, 0.03)
    knob_t = t1 - 0.12
    k = slab(knob_t - 0.03, knob_t + 0.03, 0.78, 0.84, M["brass"], 0.05, 0.03)
    obs = [d, k]
    if state == "open":
        hinge = edge_point(a, b, t0 + 0.02, out_n)
        ang = -100 if (out_n[0] + out_n[1]) > 0 else 100
        if horiz:
            ang = -ang
        pivot_rot(obs, ang, hinge[0], hinge[1])
    if state == "locked":
        # chain across the frame and a padlock
        for i in range(7):
            s = t0 - 0.02 + (t1 - t0 + 0.04) * i / 6
            slab(s - 0.025, s + 0.025, 0.8 - 0.03 * (i % 2), 0.84 - 0.03 * (i % 2), M["chain"], 0.07, 0.015)
        slab((t0 + t1) / 2 - 0.05, (t0 + t1) / 2 + 0.05, 0.66, 0.8, M["brass"], 0.09, 0.03)
    if state == "boarded":
        board_up(lambda p0, p1, za, zb: slab(p0, p1, za, zb, M["board"], 0.08, 0.02), t0, t1, 0.15, 1.45, 'Y' if horiz else 'X')


_door_fn = door


# ------------------------------------------------------------------ roofs
PAVED = []       # roads, sidewalks, lots: nature props never grow out of these
SOLIDS = []      # building volumes [(x0, y0, x1, y1, ztop, kind)] for validate.py


def solid(x0, y0, x1, y1, ztop, kind="bld"):
    SOLIDS.append((min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1), ztop, kind))


def roof_gable(M, x0, y0, x1, y1, z, rise, roof_mat, gable_mat, axis=None, over=0.22, hip=False):
    if axis is None:
        axis = 'x' if (x1 - x0) >= (y1 - y0) else 'y'
    o = over
    if axis == 'x':
        ym = (y0 + y1) / 2
        half = (y1 - y0) / 2
        ins = half + o if hip else 0.0
        ze = z - rise * o / half          # eaves drop below the wall top so the slope rests on the walls
        e = [(x0 - o, y0 - o, ze), (x1 + o, y0 - o, ze), (x1 + o, y1 + o, ze), (x0 - o, y1 + o, ze)]
        r = [(x0 - o + ins, ym, z + rise), (x1 + o - ins, ym, z + rise)]
        faces = [(0, 1, 5, 4), (4, 5, 2, 3)]
        if hip:
            faces += [(0, 4, 3), (1, 2, 5)]
        ob = mesh(e + r, faces, roof_mat, "roof", solidify=0.06)
        if not hip:
            for xx in (x0, x1):
                mesh([(xx, y0 - 0.04, z - 0.02), (xx, y1 + 0.04, z - 0.02), (xx, ym, z + rise - 0.03)], [(0, 1, 2)], gable_mat, "gable", solidify=WALL_T)
    else:
        xm = (x0 + x1) / 2
        half = (x1 - x0) / 2
        ins = half + o if hip else 0.0
        ze = z - rise * o / half
        e = [(x0 - o, y0 - o, ze), (x1 + o, y0 - o, ze), (x1 + o, y1 + o, ze), (x0 - o, y1 + o, ze)]
        r = [(xm, y0 - o + ins, z + rise), (xm, y1 + o - ins, z + rise)]
        faces = [(0, 4, 5, 3), (4, 1, 2, 5)]
        if hip:
            faces += [(0, 1, 4), (3, 5, 2)]
        ob = mesh(e + r, faces, roof_mat, "roof", solidify=0.06)
        if not hip:
            for yy in (y0, y1):
                mesh([(x0 - 0.04, yy, z - 0.02), (x1 + 0.04, yy, z - 0.02), (xm, yy, z + rise - 0.03)], [(0, 1, 2)], gable_mat, "gable", solidify=WALL_T)
    # fascia boards along the eaves
    return ob


def roof_flat(M, cells, z, mat):
    for (cx, cy) in cells:
        box(cx, cy, z - 0.02, cx + 1, cy + 1, z + 0.04, mat)


def roof_shed(M, x0, y0, x1, y1, z, rise, mat):
    o = 0.15
    return mesh([(x0 - o, y0 - o, z + rise), (x1 + o, y0 - o, z + rise), (x1 + o, y1 + o, z), (x0 - o, y1 + o, z)], [(0, 1, 2, 3)], mat, "shed", solidify=0.05)


# ------------------------------------------------------------------ houses
DIR = {"n": (0, -1), "s": (0, 1), "w": (-1, 0), "e": (1, 0)}


def window_ok(a, b, t, juncs, margin=0.72):
    """True if a window centred t along run a-b stays clear of every wall junction on that line
    (corners, wings, dividers): windows never get sliced by a wall that meets them."""
    horiz = abs(a[1] - b[1]) < 1e-6
    lo = min(a[0], b[0]) if horiz else min(a[1], b[1])
    fixed = a[1] if horiz else a[0]
    c = lo + t
    for (jx, jy) in juncs:
        if horiz and abs(jy - fixed) < 0.15 and abs(jx - c) < margin:
            return False
        if not horiz and abs(jx - fixed) < 0.15 and abs(jy - c) < margin:
            return False
    return True


def outer_runs(cells):
    """Merge the outer unit edges of a cell set into straight runs: [(a, b, side)]."""
    edges = {"n": [], "s": [], "w": [], "e": []}
    for (x, y) in cells:
        if (x, y - 1) not in cells: edges["n"].append((y, x))
        if (x, y + 1) not in cells: edges["s"].append((y + 1, x))
        if (x - 1, y) not in cells: edges["w"].append((x, y))
        if (x + 1, y) not in cells: edges["e"].append((x + 1, y))
    runs = []
    for side, lst in edges.items():
        lst.sort()
        i = 0
        while i < len(lst):
            fixed, start = lst[i]
            end = start + 1
            j = i + 1
            while j < len(lst) and lst[j][0] == fixed and lst[j][1] == end:
                end += 1; j += 1
            if side in ("n", "s"):
                runs.append(((start, fixed), (end, fixed), side))
            else:
                runs.append(((fixed, start), (fixed, end), side))
            i = j
    return runs


DOOR_FIXES = []


def _fix_door(cells, ox, oy, door):
    """Make sure the front door lands on a real outside wall (an attached wing can cover the side it asked for).
    If it doesn't, move it to the middle of the longest visible (south, then east) outside run."""
    side, dfix, dpos, state = door
    runs = outer_runs(cells)
    def ok(sd, fx, ps):
        for (a, b, rs) in runs:
            if rs != sd: continue
            horiz = sd in ("n", "s")
            fixed = a[1] if horiz else a[0]
            lo = min(a[0], b[0]) if horiz else min(a[1], b[1]); L = abs(b[0] - a[0]) if horiz else abs(b[1] - a[1])
            if abs(fixed - (fx + (oy if horiz else ox))) < 0.01 and lo + 0.5 < ps + (ox if horiz else oy) < lo + L - 0.5:
                return True
        return False
    if ok(side, dfix, dpos):
        return door
    for want in ("s", "e"):
        cands = [(abs(b[0] - a[0]) + abs(b[1] - a[1]), a, b) for (a, b, rs) in runs if rs == want]
        if cands:
            L, a, b = max(cands)
            if L >= 2:
                horiz = want == "s"
                nd = (want, (a[1] - oy) if horiz else (a[0] - ox), ((a[0] + b[0]) / 2 - ox) if horiz else ((a[1] + b[1]) / 2 - oy), state)
                DOOR_FIXES.append((door, nd))
                return nd
    return door


def house(M, ox, oy, parts, wall_mat, roof="gable", roof_mat="sh_brown", door=None, door_state="closed",
          shutters=None, chimney=None, porch=None, win_state="glass", ruined=False, extra_doors=()):
    """parts: [(x, y, w, h, storeys)] relative to (ox, oy).
    door: (side, part_index, t) — t is the offset along that run. roof: gable | hip | flat | shed."""
    cells = {}
    for (px, py, w, h, st) in parts:
        for y in range(py, py + h):
            for x in range(px, px + w):
                cells[(ox + x, oy + y)] = max(st, cells.get((ox + x, oy + y), 0))
    maxst = max(cells.values())
    if door:
        door = _fix_door(set(cells), ox, oy, door)
    doors = [door] + list(extra_doors) if door else list(extra_doors)
    for s_ in range(maxst):
        level = {c for c, st in cells.items() if st > s_}
        runs_here = outer_runs(level)
        juncs = [p for (a, b, sd) in runs_here for p in (a, b)]
        # where a taller part meets a lower one, the lower roofline also counts as a junction
        for (a, b, sd) in outer_runs(set(cells)):
            juncs += [a, b]
        for (a, b, side) in runs_here:
            horiz = side in ("n", "s")
            L = abs(b[0] - a[0]) if horiz else abs(b[1] - a[1])
            lo = min(a[0], b[0]) if horiz else min(a[1], b[1])
            fixed = a[1] if horiz else a[0]
            openings = []
            my_doors = []
            if s_ == 0:
                for d in doors:
                    dside, dfix, dpos, dstate = d
                    dfix += (oy if horiz else ox)
                    dpos += (ox if horiz else oy)
                    if dside == side and abs(dfix - fixed) < 0.01 and lo + 0.5 < dpos < lo + L - 0.5:
                        t = dpos - lo
                        openings.append((t - 0.42, t + 0.42, 0.0, 1.6, "door"))
                        my_doors.append((t, dstate))
            t = 1.0
            while t < L - 0.6:
                if all(abs(t - o[0] - 0.42) > 1.0 for o in openings) and window_ok(a, b, t, juncs):
                    openings.append((t - 0.38, t + 0.38, 0.85, 1.65, "win"))
                t += 1.6
            out_n = DIR[side]
            wm = wall_mat if not isinstance(wall_mat, dict) else wall_mat[horiz]
            wall_run(M, a, b, STOREY, wm, openings, cap=(roof == "flat"), z0=s_ * STOREY)
            for (t0, t1, z0, z1, kind) in openings:
                if kind == "win":
                    st = R.choice([win_state, win_state, "glass"]) if win_state != "glass" else "glass"
                    window(M, a, b, t0, t1, z0, z1, out_n, st, shutters, zbase=s_ * STOREY)
            for (t, dstate) in my_doors:
                _door_fn(M, a, b, t - 0.42, t + 0.42, out_n, dstate)
        # floor between storeys shows where a lower roof meets a taller wall: skip
    # floor (dark, mostly hidden)
    for (x, y) in cells:
        box(x, y, 0, x + 1, y + 1, 0.03, M["wood"])
    # roofs per part
    for (px, py, w, h, st) in parts:
        x0, y0, x1, y1 = ox + px, oy + py, ox + px + w, oy + py + h
        z = STOREY * st
        solid(x0, y0, x1, y1, z + (min(w, h) * 0.42 if roof in ("gable", "hip") else 0.1))
        rm = roof_mat
        if roof in ("gable", "hip"):
            axis = 'x' if w >= h else 'y'
            gm = wall_mat if not isinstance(wall_mat, dict) else wall_mat[axis == 'y']
            if ruined:
                # half the roof caved in: only one slope, plus charred rafters
                rise = min(w, h) * 0.42
                ob = roof_gable(M, x0, y0, x1, y1, z, rise, M[rm + "_" + axis], gm, axis)
                for k in range(int(max(w, h) * 2)):
                    if axis == 'x':
                        xx = x0 + 0.25 + k * 0.5
                        if xx > x1: break
                        bx = box(xx - 0.04, (y0 + y1) / 2 - 0.04, z, xx + 0.04, (y0 + y1) / 2 + 0.04, z + rise, M["char"])
                bpy.data.objects.remove(ob, do_unlink=True)
                hm = (y0 + y1) / 2 if axis == 'x' else None
                mesh([(x0 - .2, y0 - .2, z), (x1 + .2, y0 - .2, z), (x1 + .2, (y0 + y1) / 2, z + rise), (x0 - .2, (y0 + y1) / 2, z + rise)],
                     [(0, 1, 2, 3)], M[rm + "_x"], "roof", solidify=0.06)
            else:
                roof_gable(M, x0, y0, x1, y1, z, min(w, h) * 0.42, M[rm + "_" + axis], gm, axis, hip=(roof == "hip"))
        elif roof == "shed":
            roof_shed(M, x0, y0, x1, y1, z, 0.35, M["tin"])
        else:
            roof_flat(M, [(x, y) for (x, y) in cells if x0 <= x < x1 and y0 <= y < y1], z, M["conc"])
    if chimney:
        cx, cy = ox + chimney[0], oy + chimney[1]
        box(cx - 0.22, cy - 0.22, 0, cx + 0.22, cy + 0.22, STOREY * maxst + 1.6, M["brick"])
        box(cx - 0.26, cy - 0.26, STOREY * maxst + 1.5, cx + 0.26, cy + 0.26, STOREY * maxst + 1.62, M["cap"])
    if porch:
        x0, y0, x1, y1 = porch
        x0 += ox; x1 += ox; y0 += oy; y1 += oy
        box(x0, y0, 0, x1, y1, 0.12, M["wood"])
        for (px, py) in ((x0 + 0.1, y1 - 0.1), (x1 - 0.1, y1 - 0.1), ((x0 + x1) / 2, y1 - 0.1)):
            box(px - 0.05, py - 0.05, 0.12, px + 0.05, py + 0.05, 1.7, M["trim"])
        mesh([(x0 - 0.1, y0, 1.9), (x1 + 0.1, y0, 1.9), (x1 + 0.1, y1 + 0.15, 1.65), (x0 - 0.1, y1 + 0.15, 1.65)], [(0, 1, 2, 3)], M[roof_mat + "_x"], "porchroof", solidify=0.05)
        box(x0, y1 - 0.12, 0.6, x1, y1 - 0.08, 0.66, M["trim"])
    return cells


# ------------------------------------------------------------------ creatures
def skin_body(joints, edges, radii, mat, name="body", levels=2):
    me = bpy.data.meshes.new(name)
    me.from_pydata([g2b(*j) for j in joints], edges, [])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob); __import__('lib').REG.append(ob)
    bpy.context.view_layer.objects.active = ob
    ob.modifiers.new("skin", 'SKIN')
    for i, r in enumerate(radii):
        me.skin_vertices[0].data[i].radius = r
    me.skin_vertices[0].data[0].use_root = True
    sub = ob.modifiers.new("sub", 'SUBSURF'); sub.levels = levels; sub.render_levels = levels
    me.materials.append(mat)
    for p in me.polygons: p.use_smooth = True
    return ob


def humanoid(mat_body, scale=1.0, hunch=0.0, arm_len=1.0, bulk=1.0, walk=0.0):
    """Returns (body object, head position, wrist positions). Facing +y (toward the camera's left)."""
    s = scale
    sw = walk * 0.16
    J = [(0, 0, 0.55 * s), (0, hunch * 0.4, 0.74 * s), (0, hunch, 0.92 * s), (0, hunch * 1.4, 1.03 * s)]
    E = [(0, 1), (1, 2), (2, 3)]
    Rr = [(0.12 * s * bulk, 0.085 * s * bulk), (0.105 * s * bulk, 0.075 * s * bulk), (0.15 * s * bulk, 0.09 * s * bulk), (0.05 * s, 0.05 * s)]
    for side in (-1, 1):
        f = sw * side
        b = len(J)
        J += [(side * 0.085 * s * bulk, 0, 0.52 * s), (side * 0.09 * s * bulk, f * 0.6 + 0.03, 0.29 * s), (side * 0.09 * s * bulk, f * 1.1, 0.07 * s), (side * 0.09 * s * bulk, f * 1.1 + 0.09 * s, 0.04 * s)]
        E += [(0, b), (b, b + 1), (b + 1, b + 2), (b + 2, b + 3)]
        Rr += [(0.07 * s * bulk, 0.07 * s * bulk), (0.055 * s * bulk, 0.055 * s * bulk), (0.045 * s, 0.045 * s), (0.04 * s, 0.03 * s)]
    wrists = []
    for side in (-1, 1):
        f = -sw * side
        b = len(J)
        sh = (side * 0.18 * s * bulk, hunch, 0.97 * s)
        el = (side * 0.22 * s * bulk, hunch + f * 0.6 + 0.04, (0.97 - 0.21 * arm_len) * s)
        wr = (side * 0.23 * s * bulk, hunch + f * 1.1 + 0.06, (0.97 - 0.42 * arm_len) * s)
        J += [sh, el, wr]
        E += [(2, b), (b, b + 1), (b + 1, b + 2)]
        Rr += [(0.058 * s * bulk, 0.058 * s * bulk), (0.045 * s * bulk, 0.045 * s * bulk), (0.035 * s * bulk, 0.035 * s * bulk)]
        wrists.append(wr)
    ob = skin_body(J, E, Rr, mat_body)
    head = (0, hunch * 1.6, 1.14 * s)
    return ob, head, wrists


# ------------------------------------------------------------------ natural terrain
def mat_terrain(name="terrain"):
    """Blends dirt, cracked earth, sand, gravel and dry grass by large-scale noise."""
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    def layer(scale, stops):
        n = _noise(nt, co, scale, 8.0, 0.65)
        return _ramp(nt, n.outputs[0], stops), n
    dirt, nd = layer(3.0, [(0.35, '#56493a'), (0.5, '#76664e'), (0.65, '#8e7e62')])
    sand, _ = layer(5.0, [(0.4, '#9a8a68'), (0.6, '#b0a07c')])
    grass, ng = layer(9.0, [(0.3, '#5a5a34'), (0.5, '#7a7a44'), (0.7, '#8a845a')])
    gravel, _ = layer(60.0, [(0.3, '#5a5650'), (0.5, '#7a766c'), (0.7, '#9a9488')])
    m1 = _noise(nt, co, 0.35, 3.0, 0.5)
    f1 = _ramp(nt, m1.outputs[0], [(0.45, '#000000'), (0.6, '#ffffff')])
    c = _mix(nt, dirt, sand, f1)
    m2 = _noise(nt, co, 0.5, 4.0, 0.6)
    f2 = _ramp(nt, m2.outputs[0], [(0.52, '#000000'), (0.62, '#ffffff')])
    c = _mix(nt, c, grass, f2)
    m3 = _noise(nt, co, 0.8, 3.0, 0.5)
    f3 = _ramp(nt, m3.outputs[0], [(0.62, '#000000'), (0.7, '#ffffff')])
    c = _mix(nt, c, gravel, f3)
    c, crk = cracks(nt, c, co, 1.1, 0.01, '#3a3026')
    nt.links.new(grit(nt, c, co, 0.45, 120.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 1.0
    _bump(nt, bs, nd.outputs[0], 0.8, 0.04)
    return m


def terrain(x0, y0, x1, y1, mat, amp=0.25, scale=0.6, res=3, flat=()):
    """Displaced ground grid (game coords). flat: list of (x0,y0,x1,y1) rects pushed back to z=0 (roads, lots)."""
    import bmesh as _bm
    TERRAIN.update({"amp": amp, "scale": scale, "flat": list(flat)})
    nx, ny = int((x1 - x0) * res), int((y1 - y0) * res)
    me = bpy.data.meshes.new("terrain")
    bm = _bm.new()
    verts = {}
    import math as _m
    for j in range(ny + 1):
        for i in range(nx + 1):
            gx, gy = x0 + (x1 - x0) * i / nx, y0 + (y1 - y0) * j / ny
            z = amp * (_m.sin(gx * scale * 1.3 + 0.7) * _m.cos(gy * scale * 0.9 + 1.1) + 0.5 * _m.sin(gx * scale * 2.7 + gy * scale * 1.9))
            for (a0, b0, a1, b1) in flat:
                dx = max(a0 - gx, 0, gx - a1)
                dy = max(b0 - gy, 0, gy - b1)
                d = (dx * dx + dy * dy) ** 0.5
                z *= min(1.0, d / 1.5)
            z = min(z, 0.0) if False else z
            verts[(i, j)] = bm.verts.new(g2b(gx, gy, z - 0.02))
    for j in range(ny):
        for i in range(nx):
            bm.faces.new((verts[(i, j)], verts[(i + 1, j)], verts[(i + 1, j + 1)], verts[(i, j + 1)]))
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("terrain", me)
    bpy.context.scene.collection.objects.link(ob); __import__('lib').REG.append(ob)
    me.materials.append(mat)
    for p in me.polygons: p.use_smooth = True
    return ob


# ------------------------------------------------------------------ node maths helpers
def _math(nt, op, a, b=None):
    n = nt.nodes.new("ShaderNodeMath"); n.operation = op
    for i, v in enumerate((a, b)):
        if v is None: continue
        if isinstance(v, (int, float)): n.inputs[i].default_value = v
        else: nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def _sep(nt, vec):
    s = nt.nodes.new("ShaderNodeSeparateXYZ"); nt.links.new(vec, s.inputs[0])
    return s.outputs


def _alpha_out(m, nt, bs, alpha):
    """Replace the material output with Mix(Transparent, BSDF) driven by alpha."""
    out = [n for n in nt.nodes if n.bl_idname == "ShaderNodeOutputMaterial"][0]
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mx = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(alpha, mx.inputs[0]); nt.links.new(tr.outputs[0], mx.inputs[1]); nt.links.new(bs.outputs[0], mx.inputs[2])
    nt.links.new(mx.outputs[0], out.inputs[0])
    try:
        m.blend_method = 'HASHED'
    except Exception:
        pass


def mat_road(name, L, hw, ends=(False, False), axis='x', box_edges=False):
    """Asphalt with ragged, dusty edges, drifted dirt, cracks and patch repairs.
    ends: erode the road into broken chunks at its -/+ end (a dead end into the dirt)."""
    m, nt, bs = _nodes(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    co = tc.outputs["Object"]
    xyz = _sep(nt, co)
    along = xyz[0] if axis == 'x' else xyz[1]
    across = xyz[1] if axis == 'x' else xyz[0]
    n1 = _noise(nt, co, 2.2, 6.0, 0.7).outputs[0]
    n2 = _noise(nt, co, 9.0, 4.0, 0.6).outputs[0]
    # edge metric: 0 on the centre line, ~1 at the edge, made ragged by noise
    e = _math(nt, 'DIVIDE', _math(nt, 'ABSOLUTE', across), hw)
    if box_edges:      # parking lots: every side fades, not just the long ones
        e = _math(nt, 'MAXIMUM', e, _math(nt, 'DIVIDE', _math(nt, 'ABSOLUTE', along), L / 2))
    e = _math(nt, 'ADD', e, _math(nt, 'MULTIPLY', _math(nt, 'SUBTRACT', n1, 0.5), 0.45))
    e = _math(nt, 'ADD', e, _math(nt, 'MULTIPLY', _math(nt, 'SUBTRACT', n2, 0.5), 0.18))
    for k, flag in enumerate(ends):
        if not flag: continue
        # distance from this end, in tiles; crumble over the last ~3 tiles
        d = _math(nt, 'SUBTRACT', L / 2, along) if k == 1 else _math(nt, 'ADD', along, L / 2)
        ef = _math(nt, 'SUBTRACT', 1.15, _math(nt, 'DIVIDE', d, 3.0))
        ef = _math(nt, 'ADD', ef, _math(nt, 'MULTIPLY', _math(nt, 'SUBTRACT', n1, 0.5), 1.2))
        ef = _math(nt, 'ADD', ef, _math(nt, 'MULTIPLY', _math(nt, 'SUBTRACT', n2, 0.5), 0.6))
        e = _math(nt, 'MAXIMUM', e, ef)
    # soft edge: asphalt thins out into the ground over a band instead of stopping on a line
    alpha = _ramp(nt, e, [(0.8, '#ffffff'), (0.9, '#8a8a8a'), (1.0, '#000000')])
    # asphalt colour + cracks + repair patches
    a = _noise(nt, co, 25.0, 10.0, 0.8)
    col = _ramp(nt, a.outputs[0], [(0.3, '#3a3836'), (0.55, '#4c4844'), (0.75, '#625c56')])
    col, crk = cracks(nt, col, co, 1.3, 0.014, '#121010')
    col, _ = cracks(nt, col, co, 3.7, 0.01, '#1a1816')
    col, _ = cracks(nt, col, co, 0.7, 0.008, '#0e0c0a')
    br = nt.nodes.new("ShaderNodeTexBrick")
    br.inputs["Scale"].default_value = 0.6
    br.inputs["Color1"].default_value = _hex('#000000'); br.inputs["Color2"].default_value = _hex('#ffffff')
    br.inputs["Mortar Size"].default_value = 0.0
    br.inputs["Brick Width"].default_value = 1.3; br.inputs["Row Height"].default_value = 0.7
    nt.links.new(co, br.inputs["Vector"])
    patchf = _math(nt, 'MULTIPLY', _math(nt, 'GREATER_THAN', _sep(nt, br.outputs["Color"])[0], 0.9),
                   _math(nt, 'GREATER_THAN', _noise(nt, co, 0.8, 2.0, 0.5).outputs[0], 0.58))
    col = _mix(nt, col, '#1e1c1c', patchf)
    # dust and drifted dirt: stronger towards the edges, plus random drifts across the road
    dust = _math(nt, 'ADD', _math(nt, 'MULTIPLY', e, 1.0), _math(nt, 'MULTIPLY', _noise(nt, co, 0.7, 4.0, 0.6).outputs[0], 0.95))
    dustf = _ramp(nt, dust, [(1.0, '#000000'), (1.22, '#ffffff')])
    # edge gradient: the dirt takes over gradually towards the ragged edge
    edgef = _ramp(nt, e, [(0.62, '#000000'), (0.92, '#ffffff')])
    dustf = _math(nt, 'MAXIMUM', _sep(nt, dustf)[0], _sep(nt, edgef)[0])
    # broken, lighter asphalt crumbs along the shoulder
    shoulder = _ramp(nt, e, [(0.7, '#000000'), (0.84, '#ffffff')])
    crumbs = _math(nt, 'MULTIPLY', shoulder, _math(nt, 'GREATER_THAN', _noise(nt, co, 14.0, 2.0, 0.5).outputs[0], 0.55))
    col = _mix(nt, col, '#6e665c', crumbs)
    dirt = _ramp(nt, _noise(nt, co, 3.0, 8.0, 0.7).outputs[0], [(0.3, '#56493a'), (0.5, '#76664e'), (0.7, '#8e7e62')])
    col = _mix(nt, col, dirt, dustf)
    nt.links.new(grit(nt, col, co, 0.4, 140.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.95
    _bump(nt, bs, crk, 0.6, 0.02)
    _alpha_out(m, nt, bs, alpha)
    return m


def road(x0, y0, x1, y1, ends=(False, False), z=0.008, name="road", lot=False):
    """Asphalt strip with soft eroded edges. lot=True: a parking lot (all four sides fade)."""
    PAVED.append((x0, y0, x1, y1))
    axis = 'x' if (x1 - x0) >= (y1 - y0) else 'y'
    L = (x1 - x0) if axis == 'x' else (y1 - y0)
    hw = ((y1 - y0) if axis == 'x' else (x1 - x0)) / 2
    pad = 0.45
    if lot:      # lots: the faded band sits outside the usable rectangle
        L += 2 * pad; hw += pad
    m = mat_road(name + str(R.randint(0, 99999)), L, hw + (0.0 if lot else 0.0), ends, axis, box_edges=lot)
    ex = pad if lot else 0.0
    if axis == 'x':
        ob = mesh([(x0 - ex, y0 - pad, z), (x1 + ex, y0 - pad, z), (x1 + ex, y1 + pad, z), (x0 - ex, y1 + pad, z)], [(0, 1, 2, 3)], m, name)
    else:
        ob = mesh([(x0 - pad, y0 - ex, z), (x1 + pad, y0 - ex, z), (x1 + pad, y1 + ex, z), (x0 - pad, y1 + ex, z)], [(0, 1, 2, 3)], m, name)
    # object coords centred on the road so the material's along/across maths works
    import mathutils
    c = g2b((x0 + x1) / 2, (y0 + y1) / 2, 0)
    for v in ob.data.vertices:
        v.co.x -= c.x; v.co.y -= c.y
    ob.location = (c.x, c.y, 0)
    ob.visible_shadow = False
    return ob


def mat_footpath(name):
    """Worn dirt trail: lighter packed earth with pebbles, soft ragged edges (uses the ribbon's UV)."""
    m, nt, bs = _nodes(name)
    uv = nt.nodes.new("ShaderNodeUVMap")
    uvo = _sep(nt, uv.outputs[0])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    co = tc.outputs["Object"]
    v = _math(nt, 'MULTIPLY', _math(nt, 'ABSOLUTE', _math(nt, 'SUBTRACT', uvo[1], 0.5)), 2.0)
    n = _noise(nt, co, 3.0, 6.0, 0.7).outputs[0]
    e = _math(nt, 'ADD', v, _math(nt, 'MULTIPLY', _math(nt, 'SUBTRACT', n, 0.5), 0.7))
    alpha = _ramp(nt, e, [(0.55, '#ffffff'), (0.95, '#000000')])
    col = _ramp(nt, _noise(nt, co, 8.0, 8.0, 0.7).outputs[0], [(0.35, '#9a8668'), (0.6, '#b4a282')])
    # two faint ruts worn down the middle
    rut = _ramp(nt, _math(nt, 'ABSOLUTE', _math(nt, 'SUBTRACT', v, 0.35)), [(0.0, '#8a7a60'), (0.12, '#ffffff')])
    m2 = nt.nodes.new("ShaderNodeMix"); m2.data_type = 'RGBA'; m2.blend_type = 'MULTIPLY'; m2.inputs[0].default_value = 0.5
    nt.links.new(col, m2.inputs[6]); nt.links.new(rut, m2.inputs[7]); col = m2.outputs[2]
    vo = nt.nodes.new("ShaderNodeTexVoronoi"); vo.inputs["Scale"].default_value = 30.0
    nt.links.new(co, vo.inputs["Vector"])
    peb = _ramp(nt, vo.outputs["Distance"], [(0.0, '#5a4e40'), (0.1, '#ffffff')])
    mm = nt.nodes.new("ShaderNodeMix"); mm.data_type = 'RGBA'; mm.blend_type = 'MULTIPLY'; mm.inputs[0].default_value = 0.6
    nt.links.new(col, mm.inputs[6]); nt.links.new(peb, mm.inputs[7])
    nt.links.new(grit(nt, mm.outputs[2], co, 0.25, 120.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 1.0
    _alpha_out(m, nt, bs, alpha)
    return m


_FP = {}
TERRAIN = {"amp": 0.0, "scale": 0.6, "flat": []}


def ground_z(gx, gy):
    """Height of the last terrain() at a game point (so paths and props can sit on it)."""
    import math as _m
    amp, scale, flat = TERRAIN["amp"], TERRAIN["scale"], TERRAIN["flat"]
    z = amp * (_m.sin(gx * scale * 1.3 + 0.7) * _m.cos(gy * scale * 0.9 + 1.1) + 0.5 * _m.sin(gx * scale * 2.7 + gy * scale * 1.9))
    for (a0, b0, a1, b1) in flat:
        dx = max(a0 - gx, 0, gx - a1); dy = max(b0 - gy, 0, gy - b1)
        z *= min(1.0, (dx * dx + dy * dy) ** 0.5 / 1.5)
    return z - 0.02


def footpath(points, width=0.6, z=0.012, wobble=0.15, seed=0):
    """A worn trail along points (game xy): smoothed, wobbled, tapered at both ends."""
    import bmesh as _bm
    rr = random.Random(seed)
    pts = [Vector((p[0], p[1])) for p in points]
    # Catmull-Rom resample
    dense = []
    for i in range(len(pts) - 1):
        p0 = pts[max(i - 1, 0)]; p1 = pts[i]; p2 = pts[i + 1]; p3 = pts[min(i + 2, len(pts) - 1)]
        seg = max(2, int((p2 - p1).length * 4))
        for k in range(seg):
            t = k / seg
            t2, t3 = t * t, t * t * t
            dense.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    dense.append(pts[-1])
    off = 0.0
    for i in range(len(dense)):
        off = off * 0.85 + rr.uniform(-wobble, wobble) * 0.3
        if 0 < i < len(dense) - 1:
            d = (dense[i + 1] - dense[i - 1]).normalized()
            dense[i] = dense[i] + Vector((-d.y, d.x)) * off
    bm = _bm.new()
    uvl = bm.loops.layers.uv.new()
    rows = []
    total = len(dense) - 1
    for i, p in enumerate(dense):
        d = (dense[min(i + 1, total)] - dense[max(i - 1, 0)]).normalized()
        nrm = Vector((-d.y, d.x))
        taper = min(1.0, i / 3.0, (total - i) / 3.0) * 0.6 + 0.4
        w = width * taper * rr.uniform(0.85, 1.15) / 2
        a = p + nrm * w; b = p - nrm * w
        rows.append((bm.verts.new(g2b(a.x, a.y, ground_z(a.x, a.y) + z)), bm.verts.new(g2b(b.x, b.y, ground_z(b.x, b.y) + z)), i))
    for k in range(total):
        va, vb, i = rows[k]; vc, vd, j = rows[k + 1]
        f = bm.faces.new((va, vc, vd, vb))
        for loop, uvv in zip(f.loops, ((i * 0.25, 0), (j * 0.25, 0), (j * 0.25, 1), (i * 0.25, 1))):
            loop[uvl].uv = uvv
    me = bpy.data.meshes.new("path")
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("path", me)
    bpy.context.scene.collection.objects.link(ob); __import__('lib').REG.append(ob)
    if "m" not in _FP:
        _FP["m"] = mat_footpath("footpath")
    me.materials.append(_FP["m"])
    ob.visible_shadow = False
    return ob


def plan_path(start, goal, blockers, rng, step=1.5):
    """Simple desire line: wobbly polyline from start to goal that walks around blocking rectangles."""
    pts = [start]
    cur = Vector(start)
    g = Vector(goal)
    for it in range(40):
        if (g - cur).length < step:
            break
        d = (g - cur).normalized()
        nxt = cur + d * step + Vector((rng.uniform(-.3, .3), rng.uniform(-.3, .3)))
        hit = None
        for (a0, b0, a1, b1) in blockers:
            if a0 - .4 < nxt.x < a1 + .4 and b0 - .4 < nxt.y < b1 + .4:
                hit = (a0, b0, a1, b1)
        if hit:
            a0, b0, a1, b1 = hit
            corners = [Vector((a0 - .8, b0 - .8)), Vector((a1 + .8, b0 - .8)), Vector((a0 - .8, b1 + .8)), Vector((a1 + .8, b1 + .8))]
            corners.sort(key=lambda c: (c - cur).length + (g - c).length)
            nxt = corners[0]
        pts.append((nxt.x, nxt.y))
        cur = nxt
    pts.append(goal)
    return pts


def mat_patch(name, hx, hy, stops, scale=4.0):
    """Ground-cover decal (lawn, gravel, dirt yard): colour from noise, alpha fading out over a ragged band at
    the edges so it melts into the terrain instead of sitting on it like a mat."""
    m, nt, bs = _nodes(name)
    tc = nt.nodes.new("ShaderNodeTexCoord"); co = tc.outputs["Object"]
    xyz = _sep(nt, co)
    n1 = _noise(nt, co, 0.9, 6.0, 0.7).outputs[0]
    n2 = _noise(nt, co, 4.0, 4.0, 0.6).outputs[0]
    e = _math(nt, 'MAXIMUM', _math(nt, 'DIVIDE', _math(nt, 'ABSOLUTE', xyz[0]), hx), _math(nt, 'DIVIDE', _math(nt, 'ABSOLUTE', xyz[1]), hy))
    e = _math(nt, 'ADD', e, _math(nt, 'MULTIPLY', _math(nt, 'SUBTRACT', n1, 0.5), 0.35))
    e = _math(nt, 'ADD', e, _math(nt, 'MULTIPLY', _math(nt, 'SUBTRACT', n2, 0.5), 0.15))
    alpha = _ramp(nt, e, [(0.62, '#ffffff'), (0.82, '#7a7a7a'), (0.97, '#000000')])
    # patchy inside too: bald spots where the dirt shows through
    bald = _ramp(nt, _noise(nt, co, 1.6, 5.0, 0.6).outputs[0], [(0.3, '#000000'), (0.42, '#ffffff')])
    alpha = _math(nt, 'MULTIPLY', _sep(nt, alpha)[0], _sep(nt, bald)[0])
    col = _ramp(nt, _noise(nt, co, scale, 8.0, 0.65).outputs[0], stops)
    nt.links.new(grit(nt, col, co, 0.4, 120.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 1.0
    _alpha_out(m, nt, bs, alpha)
    return m


def patch(x0, y0, x1, y1, stops, z=0.004, name="patch"):
    pad = 0.6
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 + pad, (y1 - y0) / 2 + pad
    m = mat_patch(name + str(R.randint(0, 99999)), hx, hy, stops)
    ob = mesh([(x0 - pad, y0 - pad, z), (x1 + pad, y0 - pad, z), (x1 + pad, y1 + pad, z), (x0 - pad, y1 + pad, z)], [(0, 1, 2, 3)], m, name)
    c = g2b(cx, cy, 0)
    for v in ob.data.vertices:
        v.co.x -= c.x; v.co.y -= c.y
    ob.location = (c.x, c.y, 0)
    ob.visible_shadow = False
    return ob
