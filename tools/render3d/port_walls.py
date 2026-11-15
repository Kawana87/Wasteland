"""Port the thin building walls (wall_*, low_*, stub_*) to Blender renders.

Same names, canvases (28x60) and anchors ([2,45] x-axis, [26,45] y-axis) as tools/art_build.py, so
BuildingView keeps working unchanged. Each wall piece is ONE mesh with its origin at the segment start,
and every texture repeats exactly once per tile along the wall (noise is sampled on a circle), so
segments placed side by side join without seams.
python3 port_walls.py [palette indices...]"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from lib import reset, lights, _nodes, _hex
import fast as FAST
import port_common as PC
from port_common import gz

WALLS = [
    ("siding", "#7fa596", "#e8e0c8"), ("siding", "#c88c74", "#f0e0c0"), ("siding", "#d6c79a", "#8a5a3a"),
    ("siding", "#8ea6b8", "#e8e4d4"), ("plaster", "#cfc4a8", "#a89878"), ("tin", "#8a7a66", "#6a5a48"),
    ("brick", "#8e4a3a", "#c8b8a0"), ("brick", "#a8885e", "#e0d4b4"), ("concrete", "#9a978c", "#c8c4b4"),
    ("streamline", "#e2dccb", "#c24a3a"), ("streamline", "#e2dccb", "#3e8a86"), ("panel", "#7e8a7c", "#a8b0a0"),
]
MODES = ("plain", "win", "broken", "boarded", "cracked", "door", "shop", "garage",
         "doorlock", "doorbar", "dooropen", "doorbroken", "doorsealed")
H = gz(28)          # one storey
T = 0.035           # half wall thickness
TAU = 2 * math.pi


# ------------------------------------------------------------------ node helpers
class NB:
    def __init__(self, nt):
        self.nt = nt

    def n(self, kind, **kw):
        nd = self.nt.nodes.new(kind)
        for k, v in kw.items():
            setattr(nd, k, v)
        return nd

    def link(self, a, b):
        self.nt.links.new(a, b)

    def math(self, op, a, b=None, clamp=False):
        nd = self.n("ShaderNodeMath", operation=op)
        nd.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None: continue
            if isinstance(v, (int, float)): nd.inputs[i].default_value = v
            else: self.link(v, nd.inputs[i])
        return nd.outputs[0]

    def mix(self, a, b, fac):
        nd = self.n("ShaderNodeMix", data_type='RGBA')
        for idx, v in ((0, fac), (6, a), (7, b)):
            if isinstance(v, str): nd.inputs[idx].default_value = _hex(v)
            elif isinstance(v, (int, float)): nd.inputs[idx].default_value = v
            else: self.link(v, nd.inputs[idx])
        return nd.outputs[2]

    def ramp(self, fac, stops):
        nd = self.n("ShaderNodeValToRGB")
        cr = nd.color_ramp
        while len(cr.elements) > len(stops): cr.elements.remove(cr.elements[-1])
        while len(cr.elements) < len(stops): cr.elements.new(0.5)
        for e, (p, c) in zip(cr.elements, stops):
            e.position = p
            e.color = _hex(c) if isinstance(c, str) else c
        self.link(fac, nd.inputs[0])
        return nd.outputs[0]

    def noise(self, vec, scale, detail=4.0, rough=0.6):
        nd = self.n("ShaderNodeTexNoise")
        nd.inputs["Scale"].default_value = scale
        nd.inputs["Detail"].default_value = detail
        nd.inputs["Roughness"].default_value = rough
        self.link(vec, nd.inputs["Vector"])
        return nd.outputs[0]

    def combine(self, x, y, z):
        nd = self.n("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            if isinstance(v, (int, float)): nd.inputs[i].default_value = v
            else: self.link(v, nd.inputs[i])
        return nd.outputs[0]

    def mul_col(self, col, f):
        nd = self.n("ShaderNodeMix", data_type='RGBA', blend_type='MULTIPLY')
        nd.inputs[0].default_value = 1.0
        if isinstance(col, str): nd.inputs[6].default_value = _hex(col)
        else: self.link(col, nd.inputs[6])
        if isinstance(f, (int, float)): nd.inputs[7].default_value = (f, f, f, 1)
        else:
            g = self.n("ShaderNodeCombineColor")
            for i in range(3): self.link(f, g.inputs[i])
            self.link(g.outputs[0], nd.inputs[7])
        return nd.outputs[2]


def coords(nb, axis):
    """(along 0..1 per tile, height, periodic 3D vector for noise)."""
    tc = nb.n("ShaderNodeTexCoord")
    sep = nb.n("ShaderNodeSeparateXYZ")
    nb.link(tc.outputs["Object"], sep.inputs[0])
    a = sep.outputs[0] if axis == "x" else nb.math('MULTIPLY', sep.outputs[1], -1.0)
    z = sep.outputs[2]
    ang = nb.math('MULTIPLY', a, TAU)
    r = 1.0 / TAU
    per = nb.combine(nb.math('MULTIPLY', nb.math('COSINE', ang), r), nb.math('MULTIPLY', nb.math('SINE', ang), r), z)
    return a, z, per


def scaled(nb, vec, sx, sz):
    m = nb.n("ShaderNodeMapping")
    m.inputs["Scale"].default_value = (sx, sx, sz)
    nb.link(vec, m.inputs[0])
    return m.outputs[0]


def wall_mat(pi, axis):
    style, base, trim = WALLS[pi]
    m, nt, bs = _nodes("w%d%s" % (pi, axis))
    nb = NB(nt)
    a, z, per = coords(nb, axis)
    zn = nb.math('DIVIDE', z, H)                       # 0 at the floor, 1 at the top of the storey
    nz = nb.noise(scaled(nb, per, 5.0, 2.0), 1.0, 5.0, 0.6)
    var = nb.math('ADD', 0.88, nb.math('MULTIPLY', nz, 0.22))
    bump = None
    if style == "siding":
        bh = H / 8.0
        f = nb.math('FRACT', nb.math('DIVIDE', z, bh))
        shade = nb.ramp(f, [(0.0, '#9a9a9a'), (0.16, '#c4c4c4'), (0.2, '#ffffff'), (0.92, '#f2f2f2'), (1.0, '#ffffff')])
        col = nb.mix(base, base, 0.0)
        col = nb.mul_col(col, var)
        sh = nb.n("ShaderNodeMix", data_type='RGBA', blend_type='MULTIPLY'); sh.inputs[0].default_value = 1.0
        nb.link(col, sh.inputs[6]); nb.link(shade, sh.inputs[7]); col = sh.outputs[2]
        peel = nb.math('GREATER_THAN', nb.noise(scaled(nb, per, 9.0, 3.0), 1.0, 6.0, 0.7), 0.66)
        col = nb.mix(col, '#9a9282', peel)
        bump = f
    elif style == "plaster":
        col = nb.mul_col(base, var)
    elif style == "tin":
        rib = nb.math('SINE', nb.math('MULTIPLY', a, TAU * 14))
        shade = nb.math('ADD', 0.86, nb.math('MULTIPLY', rib, 0.14))
        col = nb.mul_col(nb.mul_col(base, var), shade)
        rust = nb.math('GREATER_THAN', nb.noise(scaled(nb, per, 4.0, 1.5), 1.0, 6.0, 0.7), 0.6)
        col = nb.mix(col, '#7a4a2a', nb.math('MULTIPLY', rust, 0.7))
        bump = rib
    elif style == "brick":
        br = nb.n("ShaderNodeTexBrick")
        br.offset = 0.5
        br.inputs["Scale"].default_value = 1.0
        br.inputs["Mortar Size"].default_value = 0.012
        br.inputs["Brick Width"].default_value = 0.25
        br.inputs["Row Height"].default_value = H / 12.0
        br.inputs["Color1"].default_value = _hex(base)
        c2 = [min(1.0, v * 0.82) for v in _hex(base)[:3]] + [1.0]
        br.inputs["Color2"].default_value = c2
        br.inputs["Mortar"].default_value = _hex(trim)
        nb.link(nb.combine(a, z, 0.0), br.inputs["Vector"])
        col = nb.mul_col(br.outputs["Color"], var)
        bump = br.outputs["Fac"]
    elif style == "concrete":
        col = nb.mul_col(base, var)
        seam = nb.math('MAXIMUM', nb.math('LESS_THAN', nb.math('ABSOLUTE', nb.math('SUBTRACT', zn, 0.5)), 0.012),
                       nb.math('LESS_THAN', nb.math('ABSOLUTE', nb.math('SUBTRACT', nb.math('FRACT', nb.math('ADD', a, 0.5)), 0.5)), 0.01))
        col = nb.mix(col, '#5a5850', seam)
    elif style == "streamline":
        col = nb.mul_col(base, nb.math('ADD', 0.93, nb.math('MULTIPLY', nz, 0.1)))
        band = nb.math('MULTIPLY', nb.math('GREATER_THAN', zn, 0.62), nb.math('LESS_THAN', zn, 0.74))
        col = nb.mix(col, trim, band)
        chrome = nb.math('MULTIPLY', nb.math('GREATER_THAN', zn, 0.55), nb.math('LESS_THAN', zn, 0.575))
        col = nb.mix(col, '#c8c8c0', chrome)
        skirt = nb.math('LESS_THAN', zn, 0.1)
        col = nb.mix(col, trim, nb.math('MULTIPLY', skirt, 0.85))
    else:   # panel
        col = nb.mul_col(base, var)
        fa = nb.math('FRACT', nb.math('MULTIPLY', a, 2.0))
        seam = nb.math('MAXIMUM', nb.math('LESS_THAN', fa, 0.03), nb.math('GREATER_THAN', fa, 0.97))
        col = nb.mix(col, '#3e4a40', seam)
        bump = seam
    # grime: dirt splashed up from the ground, a few rain streaks
    dirt = nb.ramp(zn, [(0.0, '#ffffff'), (0.22, '#000000')])
    col = nb.mix(col, '#5a4a38', nb.math('MULTIPLY', nb.n("ShaderNodeSeparateColor").outputs[0] if False else dirt, 0.4))
    streak = nb.noise(scaled(nb, per, 14.0, 0.25), 1.0, 3.0, 0.5)
    col = nb.mix(col, '#3a3228', nb.math('MULTIPLY', nb.math('GREATER_THAN', streak, 0.62), 0.25))
    nb.link(col, bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.9
    if bump is not None:
        bp = nb.n("ShaderNodeBump")
        bp.inputs["Strength"].default_value = 0.35
        bp.inputs["Distance"].default_value = 0.01
        nb.link(bump, bp.inputs["Height"]); nb.link(bp.outputs["Normal"], bs.inputs["Normal"])
    return m


def flat(name, col, rough=0.8, metal=0.0):
    from lib import mat_flat
    return mat_flat(name, col, rough, metal=metal, noise=0.12)


# ------------------------------------------------------------------ geometry
class Wall:
    """Boxes in wall-local coords (u along 0..1, w across, +w = the visible face, z up), one mesh."""
    def __init__(self, axis):
        self.axis = axis
        self.b = FAST.Batch("wall")

    def box(self, u0, u1, w0, w1, z0, z1, mat, tilt=0.0):
        cu, cw, cz = (u0 + u1) / 2, (w0 + w1) / 2, (z0 + z1) / 2
        su, sw, sz = abs(u1 - u0), abs(w1 - w0), abs(z1 - z0)
        if su < 1e-5 or sw < 1e-5 or sz < 1e-5:
            return
        if self.axis == "x":      # game (u, w, z) -> blender (u, -w, z)
            self.b.cube(Vector((cu, -cw, cz)), (su, sw, sz), mat, rot=(0, tilt, 0))
        else:                     # game (w, u, z) -> blender (w, -u, z)
            self.b.cube(Vector((cw, -cu, cz)), (sw, su, sz), mat, rot=(tilt, 0, 0))

    def done(self):
        return self.b.done()


def build_wall(axis, pi, mode, mats, hh=None, rng=None):
    style, base, trim = WALLS[pi]
    rng = rng or random.Random(pi * 31 + len(mode) + (axis == "x"))
    hh = H if hh is None else hh
    W = Wall(axis)
    wm = mats["wall"]
    trimm = mats["trim"] if style != "streamline" else mats["chrome"]
    E = T                                   # run past the ends into the corner
    opening = None
    if mode in ("win", "broken", "boarded"):
        opening = (0.26, 0.74, gz(11), gz(22))
    elif mode.startswith("door"):
        opening = (0.3, 0.7, 0.0, gz(19))
    elif mode == "shop":
        opening = (0.06, 0.94, gz(2), gz(23))
    elif mode == "garage":
        opening = (0.06, 0.94, 0.0, gz(21))
    if mode == "stub":
        # broken-off wall: an irregular ragged top (random walk over many thin steps, smoothed so it
        # reads as crumbled masonry, not battlements), one or two loose chunks
        n = 18
        h = rng.uniform(6, 16)
        raw = []
        for k in range(n):
            h = max(3, min(20, h + rng.uniform(-3.5, 3.5)))
            raw.append(h)
        hts = [(raw[max(0, k - 1)] + raw[k] * 2 + raw[min(n - 1, k + 1)]) / 4 for k in range(n)]
        # every variant meets its neighbours at the same height (9 px) so a run of broken segments reads
        # as one continuous ragged wall, not separate notched blocks
        END = 9.0
        for k in range(n):
            t = min(k, n - 1 - k) / 4.0
            if t < 1.0:
                hts[k] = END + (hts[k] - END) * t
        for k in range(n):
            u0, u1 = k / n - (E if k == 0 else 0), (k + 1) / n + (E if k == n - 1 else 0)
            W.box(u0, u1, -T, T, 0, gz(hts[k] + (rng.uniform(-0.6, 0.6) if 2 < k < n - 3 else 0.0)), wm)
        for j in range(rng.randint(1, 2)):
            k = rng.randrange(n)
            cu = k / n
            W.box(cu, cu + 0.07, -T * 0.9, T * 0.9, gz(hts[k]), gz(hts[k] + rng.uniform(1.5, 3)), wm, tilt=rng.uniform(-0.4, 0.4))
        return W.done()
    if opening is None:
        W.box(-E, 1 + E, -T, T, 0, hh, wm)
    else:
        o0, o1, z0, z1 = opening
        W.box(-E, o0, -T, T, 0, hh, wm)
        W.box(o1, 1 + E, -T, T, 0, hh, wm)
        W.box(o0, o1, -T, T, 0, z0, wm)
        W.box(o0, o1, -T, T, z1, hh, wm)
        fr = 0.035
        fw = T + 0.012
        if mode not in ("garage",):
            W.box(o0 - fr, o0, -fw, fw, z0, z1 + fr * 0.8, trimm)
            W.box(o1, o1 + fr, -fw, fw, z0, z1 + fr * 0.8, trimm)
            W.box(o0 - fr, o1 + fr, -fw, fw, z1, z1 + fr * 0.8, trimm)
        if mode in ("win", "broken", "boarded", "shop"):
            W.box(o0 - fr * 1.6, o1 + fr * 1.6, -fw, fw + 0.02, z0 - gz(1.2), z0, trimm)     # sill
        if mode == "win":
            W.box(o0, o1, -0.006, 0.006, z0, z1, mats["glass"])
            W.box((o0 + o1) / 2 - 0.012, (o0 + o1) / 2 + 0.012, -0.01, 0.012, z0, z1, trimm)
            W.box(o0, o1, -0.01, 0.012, (z0 + z1) / 2 - gz(0.5), (z0 + z1) / 2 + gz(0.5), trimm)
        elif mode == "broken":
            W.box(o0, o1, -T, -T + 0.004, z0, z1, mats["dark"])
            for (ua, ub, za, zb) in ((o0, o0 + 0.07, z1 - gz(4), z1), (o1 - 0.1, o1, z1 - gz(2.5), z1), (o0, o0 + 0.05, z0, z0 + gz(3))):
                W.box(ua, ub, -0.004, 0.004, za, zb, mats["glass"])
        elif mode == "boarded":
            W.box(o0, o1, -T, -T + 0.004, z0, z1, mats["dark"])
            for k, zc in enumerate((z0 + (z1 - z0) * 0.2, z0 + (z1 - z0) * 0.55, z0 + (z1 - z0) * 0.88)):
                W.box(o0 - 0.05, o1 + 0.05, fw, fw + 0.016, zc - gz(1.6), zc + gz(1.6), mats["plank"], tilt=math.radians(rng.uniform(-7, 7)))
        elif mode == "shop":
            W.box(o0, o1, -0.006, 0.006, z0, z1, mats["glass"])
            W.box(0.49, 0.51, -0.012, 0.014, z0, z1, trimm)
        elif mode == "garage":
            W.box(o0, o1, -0.012, 0.004, z0, z1, mats["metal"])
            n = 7
            for k in range(n):
                zz = z0 + (z1 - z0) * (k + 0.5) / n
                W.box(o0, o1, 0.004, 0.012, zz - gz(0.35), zz + gz(0.35), mats["metal_d"])
            W.box(o0 - 0.03, o1 + 0.03, -fw, fw, z1, z1 + gz(1.5), trimm)
            W.box(o0 - 0.03, o0, -fw, fw, z0, z1, trimm); W.box(o1, o1 + 0.03, -fw, fw, z0, z1, trimm)
        elif mode.startswith("door"):
            leaf = mats["leaf"]
            if mode in ("door", "doorlock", "doorbar", "doorsealed"):
                W.box(o0, o1, -0.012, 0.01, z0, z1, leaf)
                W.box(o0 + 0.05, o1 - 0.05, 0.01, 0.014, z1 - gz(7), z1 - gz(3), mats["dark"])     # little window
                W.box(o1 - 0.07, o1 - 0.045, 0.01, 0.022, gz(8.5), gz(10), mats["brass"])         # knob
            elif mode == "dooropen":
                W.box(o0, o1, -T, -T + 0.004, z0, z1, mats["dark"])
                W.box(o0, o0 + 0.03, -0.36, -0.0, z0, z1 - gz(0.5), leaf)                        # leaf swung in at the hinge
            else:   # broken
                W.box(o0, o1, -T, -T + 0.004, z0, z1, mats["dark"])
                h = gz(rng.uniform(10, 17))
                W.box(o0, o0 + 0.08, -0.012, 0.01, z0, h, leaf)
                W.box(o1 - 0.05, o1, -0.012, 0.01, z0, gz(rng.uniform(5, 12)), leaf)
                W.box(o0 + 0.1, o0 + 0.22, -0.012, 0.01, z1 - gz(3), z1, leaf)
            if mode == "doorlock":
                W.box(o0 - 0.02, o1 + 0.02, 0.012, 0.02, gz(9), gz(10.2), mats["metal"])
                W.box(0.47, 0.53, 0.018, 0.03, gz(6.5), gz(9.3), mats["brass"])
            if mode in ("doorbar", "doorsealed"):
                zs = (gz(3), gz(9.5), gz(16)) if mode == "doorbar" else tuple(gz(v) for v in (1.8, 4.8, 7.8, 10.8, 13.8, 16.8))
                for k, zc in enumerate(zs):
                    W.box(o0 - 0.05, o1 + 0.05, fw, fw + 0.016, zc - gz(1.4), zc + gz(1.4), mats["plank"],
                          tilt=math.radians((6 if k % 2 else -6) + rng.uniform(-3, 3)))
    if mode == "cracked":
        cu = 0.5
        z = gz(4)
        while z < hh - gz(3):
            nu = cu + rng.uniform(-0.05, 0.05)
            W.box(min(cu, nu) - 0.006, max(cu, nu) + 0.006, T, T + 0.003, z, z + gz(2.2), mats["dark"])
            cu, z = nu, z + gz(2)
        W.box(0.12, 0.3, T, T + 0.002, gz(4), gz(10), mats["stain"])
    # cap along the top
    W.box(-E, 1 + E, -T * 1.35, T * 1.35, hh, hh + gz(1.0), mats["cap"])
    return W.done()


def mats_for(pi, axis):
    style, base, trim = WALLS[pi]
    leaf = "#3e8a86" if style == "streamline" else "#7a4a30"
    return {"wall": wall_mat(pi, axis), "trim": flat("t%d" % pi, trim, 0.7), "cap": flat("c%d" % pi, trim, 0.7),
            "chrome": flat("chrome", "#b8b8b0", 0.35, 0.6), "glass": flat("glass", "#2e4250", 0.15, 0.3),
            "dark": flat("dark", "#16120e", 1.0), "plank": flat("plank", "#7a5a3a", 0.9),
            "metal": flat("metal", "#9a9a90", 0.5, 0.5), "metal_d": flat("metal_d", "#6e6e66", 0.5, 0.5),
            "leaf": flat("leaf%d" % pi, leaf, 0.7), "brass": flat("brass", "#c8a040", 0.3, 0.8),
            "char": flat("char%d" % pi, "#4a4038", 0.95), "stain": flat("stain", "#5a4a3a", 1.0)}


def main(pals):
    reset()
    sc = bpy.context.scene
    lights()
    for pi in pals:
        for axis in "xy":
            mats = mats_for(pi, axis)
            ax = 2 if axis == "x" else 26
            shade = 1.08 if axis == "x" else 1.0
            for mode in (os.environ["ONLY"].split(",") if os.environ.get("ONLY") else MODES + ("low", "stub")):
                if mode == "low":
                    ob = build_wall(axis, pi, "plain", mats, hh=gz(5))
                    name = "low_%s%d" % (axis, pi)
                elif mode.startswith("stub"):
                    v = int(mode[4:] or 0)
                    ob = build_wall(axis, pi, "stub", mats, rng=random.Random(pi * 97 + v * 31 + (axis == "x")))
                    name = "stub_%s%d" % (axis, pi) + ("" if v == 0 else "_%d" % v)
                else:
                    ob = build_wall(axis, pi, mode, mats)
                    name = "wall_%s%d%s" % (axis, pi, "" if mode == "plain" else "_" + mode)
                PC.sprite(name, 28, 60, ax, 45, samples=16, bright=1.12 * shade, sat=1.05)
                PC.clear([ob])
        print("palette", pi, flush=True)


if __name__ == "__main__":
    pals = [int(a) for a in sys.argv[1:]] or list(range(len(WALLS)))
    main(pals)
