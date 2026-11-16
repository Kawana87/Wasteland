"""Port standalone game sprites (props, trees, cars, furniture) to Blender renders.

Each sprite keeps its canvas size (from the current png) and anchor (anchors.json). The model is built
with the render-lab prop library at the world origin, scaled to game size (lab storey 2.0 -> game 1.43),
centred if the sprite is anchored at its middle, and shrunk further only if it would not fit the canvas.
python3 port_props.py [name-prefix ...]"""
import sys, os, math, random, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Matrix
from PIL import Image
from lib import reset, lights, box, cyl, sphere, g2b, rot_z
import fast as FAST
import props as P
import kit
import port_common as PC
from port_common import gz, ZPX

MAT = P.MAT
LAB = 2.0 / (28 * PC.GZ * 1.0)          # lab units per game unit-storey...
LAB2GAME = (28 * PC.GZ) / 2.0           # lab storey (2.0) -> game storey (28 game px)
ANCH = json.load(open(os.path.join(PC.ROOT, "assets", "anchors.json")))
ORIG = "/tmp/sprites_orig"


ALIAS = {"tree3": "tree0", "tree4": "tree0", "tree5": "tree0", "tree6": "tree0", "tree7": "tree0",
         "tree_dead1": "tree_dead", "tree_dead2": "tree_dead",
         "rock0": "rubble0", "rock1": "rubble0", "rock2": "deadbush", "boulder": "tree0", "cactus0": "tree0", "cactus1": "tree0",
         "cave_mouth": "billboard_x", "mine_entrance": "billboard_x", "vault_door": "billboard_x", "manhole": "rubble0",
         "ladder_up": "lamp", "minecart": "tent", "mine_support": "tent", "stalagmite": "tree0", "pipes": "tent", "crystal": "rubble0",
         "reeds0": "deadbush", "reeds1": "deadbush", "tumbleweed": "deadbush", "saltrock": "rubble0", "redrock": "tree0"}


def canvas(name):
    name = ALIAS.get(name, name)
    p = os.path.join(ORIG, name + ".png")
    if not os.path.exists(p):
        p = os.path.join(PC.SPR, name + ".png")
    return Image.open(p).size


def world_bbox(obs):
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in obs:
        if o.type != 'MESH':
            continue
        oe = o.evaluated_get(dg)
        pts += [oe.matrix_world @ Vector(c) for c in oe.bound_box]
    return pts


def screen_extent(pts, ax, ay):
    xs, ys = [], []
    for p in pts:
        gx, gy, z = p.x, -p.y, p.z
        xs.append(ax + (gx - gy) * 24)
        ys.append(ay + (gx + gy) * 12 - z * ZPX)
    return min(xs), max(xs), min(ys), max(ys)


def orig_box(name):
    """Opaque bounding box (w, h in px) of the original pixel-art sprite: the size players are used to."""
    name = ALIAS.get(name, name)
    p = os.path.join(ORIG, name + ".png")
    if not os.path.exists(p):
        return None
    a = Image.open(p).convert("RGBA").getchannel("A").point(lambda v: 255 if v > 200 else 0)
    bb = a.getbbox()
    return (bb[2] - bb[0], bb[3] - bb[1]) if bb else None


def render_prop(name, build, scale=LAB2GAME, center=False, outline=True, bright=1.1, sat=1.05, samples=20,
                fit_xy=None, margin=0.0, match=True, alpha_cut=70):
    w, h = canvas(name)
    ax, ay = ANCH.get(ALIAS.get(name, name), (w // 2, h - 1))
    PC.set_anchor(name, ax, ay)
    n0 = PC.mark()
    build()
    obs = PC.new_objects_since(n0)
    emp = bpy.data.objects.new("pivot", None)
    bpy.context.scene.collection.objects.link(emp)
    bpy.context.view_layer.update()
    for o in obs:
        mw = o.matrix_world.copy()
        o.parent = emp
        o.matrix_world = mw
    s = scale
    emp.scale = (s, s, s)
    pts = world_bbox(obs)
    if fit_xy:          # scale so the footprint matches (long, depth) in tiles
        gx = [p.x for p in pts]; gy = [-p.y for p in pts]
        lx, ly = max(gx) - min(gx), max(gy) - min(gy)
        k = min(fit_xy[0] / max(lx, 1e-3), fit_xy[1] / max(ly, 1e-3))
        s *= k; emp.scale = (s, s, s); pts = world_bbox(obs)
    if center:
        gx = [p.x for p in pts]; gy = [-p.y for p in pts]
        emp.location = Vector((-(max(gx) + min(gx)) / 2, (max(gy) + min(gy)) / 2, 0))
        pts = world_bbox(obs)
    ob_ = orig_box(name) if (match and not fit_xy) else None
    if ob_:
        x0, x1, y0, y1 = screen_extent(pts, ax, ay)
        if match == "h":
            k = ob_[1] / max(y1 - y0, 1)
        elif match == "w":
            k = ob_[0] / max(x1 - x0, 1)
        else:
            k = min(ob_[0] / max(x1 - x0, 1), ob_[1] / max(y1 - y0, 1))
        k = max(0.4, min(6.0, k))
        s *= k; emp.scale = (s, s, s); emp.location = emp.location * k
        pts = world_bbox(obs)
    def rescale(k):
        nonlocal s
        s *= k; emp.scale = (s, s, s); emp.location = emp.location * k
    # quick test renders on a canvas padded by the sprite size on every side, so overflow is measured
    # instead of clipped; match the original's size (first passes), then make it fit the real canvas
    for it in range(8):
        PC.frame(w * 3, h * 3, ax + w, ay + h)
        test = PC.shrink(PC.render_raw(samples=2), w * 3, h * 3, alpha_cut=alpha_cut)
        bb = test.getchannel("A").getbbox()
        if not bb:
            rescale(1.5); continue
        bb = (bb[0] - w, bb[1] - h, bb[2] - w, bb[3] - h)
        bw, bh = bb[2] - bb[0], bb[3] - bb[1]
        k = 1.0
        if ob_ and it < 3:
            if match == "h": k = ob_[1] / max(bh, 1)
            elif match == "w": k = ob_[0] / max(bw, 1)
            else: k = min(ob_[0] / max(bw, 1), ob_[1] / max(bh, 1))
        lim = []
        # room on each side of the anchor; a side where the anchor sits on the edge (poles, flags) is
        # allowed to touch it
        M_ = 1.5     # keep a pixel of air so nothing is shaved by the canvas edge
        if bb[0] < ax - 1 and ax > 3: lim.append((ax - M_) / max(ax - bb[0], 1e-3))
        if bb[2] > ax + 1 and w - ax > 3: lim.append((w - ax - M_) / max(bb[2] - ax, 1e-3))
        if bb[1] < ay - 1 and ay > 3: lim.append((ay - M_) / max(ay - bb[1], 1e-3))
        if bb[3] > ay + 1 and h - ay > 3: lim.append((h - ay - M_) / max(bb[3] - ay, 1e-3))
        k = max(0.3, min([k] + lim))
        if os.environ.get("PDEBUG"): print("DBG", name, it, bb, ob_, round(k, 3), flush=True)
        if abs(k - 1.0) < 0.02:
            break
        rescale(k * (0.98 if k < 1 else 1.0))
    out = PC.sprite(name, w, h, ax, ay, samples=samples, bright=bright, sat=sat, outline=outline, alpha_cut=alpha_cut)
    PC.clear(obs + [emp])
    return out


# ------------------------------------------------------------------ custom models (lab units, origin = base)
def leafy_tree(rng, size=1.0, col=None):
    bark = MAT("flat:%s:0.95" % rng.choice(["#5a4632", "#4a3a2c", "#6a5440"]))
    h = 1.3 * size
    cyl(0, 0, 0, h, 0.09 * size, bark, 8)
    for k in range(2):
        a = rng.uniform(0, 6.28)
        o = cyl(math.cos(a) * 0.12, math.sin(a) * 0.12, h * 0.6, h * 0.95, 0.04, bark, 6)
    leaf = col or rng.choice([("#5a7a3a", "#3e5a2a"), ("#6a8a40", "#4a6a2e"), ("#7a8a44", "#56662e")])
    m = MAT("leaf:%s:%s" % leaf)
    bt = FAST.Batch("canopy")
    for k in range(rng.randint(9, 14)):
        a = rng.uniform(0, 6.28); r = rng.uniform(0, 0.5) * size
        bt.ico(g2b(math.cos(a) * r, math.sin(a) * r, h + rng.uniform(-0.1, 0.55) * size), rng.uniform(0.28, 0.42) * size, m, subdiv=2)
    o = bt.done(smooth=False)
    tex = bpy.data.textures.new("lt%d" % rng.randint(0, 99999), 'CLOUDS'); tex.noise_scale = 0.25
    d = o.modifiers.new("d", 'DISPLACE'); d.texture = tex; d.strength = 0.12


def flag(col, rng):
    cyl(0, 0, 0, 2.6, 0.05, MAT("metal:#8a8a84"), 6)
    sphere(0, 0, 2.62, 0.04, MAT("metal:#c8c8c0"))
    bt = FAST.Batch("cloth")
    for k in range(6):
        u = k / 6
        bt.cube(g2b(0.05 + u * 0.9 + 0.075, 0.0, 2.25 - math.sin(u * 3) * 0.06), (0.16, 0.015, 0.62), MAT("fab:%s" % col),
                rot=(0, math.sin(u * 4) * 0.12, 0))
    bt.done()


def campfire(rng, frame):
    P.campfire_pit(0, 0, 0, random.Random(4))
    fl = [MAT("glow:#ffb040"), MAT("glow:#ff7020"), MAT("glow:#ffe080")]
    r2 = random.Random(10 + frame)
    for k in range(5):
        a = r2.uniform(0, 6.28); r = r2.uniform(0, 0.12)
        hgt = r2.uniform(0.25, 0.55) * (1.15 if frame else 0.9)
        o = FAST.primitive_cone_add(vertices=6, radius1=0.08, radius2=0.0, depth=hgt, location=g2b(math.cos(a) * r, math.sin(a) * r, 0.12 + hgt / 2))
        o.data.materials.append(fl[k % 3])
        o.rotation_euler = (r2.uniform(-.25, .25), r2.uniform(-.25, .25), 0)


def poster_mat():
    """Old atomic-age billboard: cream field with 'THE FUTURE!' in red, teal and red bands, weathered."""
    from PIL import Image as I, ImageDraw, ImageFont, ImageFilter
    import random as _r
    W_, H_ = 512, 256
    im = I.new("RGB", (W_, H_), (226, 214, 176))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 150, W_, 200), fill=(58, 134, 128)); d.rectangle((0, 200, W_, H_), fill=(196, 74, 54))
    try:
        f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 66)
    except Exception:
        f = ImageFont.load_default()
    tw = d.textlength("THE FUTURE!", font=f)
    d.text(((W_ - tw) / 2, 48), "THE FUTURE!", fill=(184, 58, 40), font=f)
    rr = _r.Random(3)
    for k in range(260):     # flaking paint
        x, y = rr.randrange(W_), rr.randrange(H_)
        d.ellipse((x, y, x + rr.randint(2, 9), y + rr.randint(2, 6)), fill=(150, 130, 100))
    im = im.filter(ImageFilter.GaussianBlur(0.6))
    path = "/tmp/r3d_poster.png"; im.save(path)
    from lib import _nodes
    m, nt, bs = _nodes("poster")
    tx = nt.nodes.new("ShaderNodeTexImage"); tx.image = bpy.data.images.load(path)
    nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"]); bs.inputs["Roughness"].default_value = 0.9
    return m


def billboard(axis):
    """Two posts, a framed poster panel facing the camera side (+y for x, +x for y)."""
    wood = MAT("wood:#5a4232:#4a3628"); frame = MAT("flat:#3a2e24:0.8")
    L, z0, z1 = 2.4, 1.6, 2.9
    for t in (-0.85, 0.85):          # posts stand behind the panel
        x, y = (t, -0.12) if axis == "x" else (-0.12, t)
        box(x - 0.05, y - 0.05, 0, x + 0.05, y + 0.05, z1 + 0.05, wood)
    if axis == "x":
        box(-L / 2 - 0.05, -0.06, z0 - 0.05, L / 2 + 0.05, 0.02, z1 + 0.05, frame)
        verts = [(-L / 2, 0.025, z0), (L / 2, 0.025, z0), (L / 2, 0.025, z1), (-L / 2, 0.025, z1)]
    else:
        box(-0.06, -L / 2 - 0.05, z0 - 0.05, 0.02, L / 2 + 0.05, z1 + 0.05, frame)
        verts = [(0.025, L / 2, z0), (0.025, -L / 2, z0), (0.025, -L / 2, z1), (0.025, L / 2, z1)]
    ob = kit.mesh(verts, [(0, 1, 2, 3)], poster_mat(), "poster")
    me = ob.data
    uv = me.uv_layers.new()
    for i, c in enumerate([(0, 0), (1, 0), (1, 1), (0, 1)]):
        uv.data[i].uv = c


def picket(axis):
    m = MAT("paint:#e0d8c8:0.5")
    for k in range(7):
        u = -0.5 + (k + 0.5) / 7
        x, y = (u, 0) if axis == "x" else (0, u)
        box(x - 0.025, y - 0.025, 0, x + 0.025, y + 0.025, 0.75 - (0.05 if k % 2 else 0), m)
    for zz in (0.25, 0.55):
        if axis == "x":
            box(-0.5, -0.02, zz, 0.5, 0.02, zz + 0.05, m)
        else:
            box(-0.02, -0.5, zz, 0.02, 0.5, zz + 0.05, m)


def utility_pole():
    w = MAT("wood:#5a4232:#4a3628")
    cyl(0, 0, 0, 4.6, 0.07, w, 8)
    box(-0.55, -0.04, 4.2, 0.55, 0.04, 4.3, w)
    for s in (-0.45, 0.0, 0.45):
        cyl(s, 0, 4.3, 4.42, 0.03, MAT("flat:#c8c0a8:0.4"), 6)
    box(0.07, -0.08, 3.4, 0.23, 0.08, 3.75, MAT("metal:#8a8a84"))


def antenna():
    m = MAT("metal:#8a8a84")
    cyl(0, 0, 0, 3.3, 0.03, m, 6)
    for k, zz in enumerate((1.6, 2.2, 2.8)):
        L = 0.55 - k * 0.12
        box(-L, -0.015, zz, L, 0.015, zz + 0.03, m)
    box(-0.12, -0.12, 0, 0.12, 0.12, 0.05, m)


def radio_tower():
    m = MAT("paint:#b84a3a:0.5"); m2 = MAT("paint:#d8d0c0:0.5")
    H = 3.6
    for (a, b) in ((-.3, -.3), (.3, -.3), (-.3, .3), (.3, .3)):
        o = cyl(a * 0.6, b * 0.6, 0, H, 0.03, m, 6)
    for k in range(7):
        zz = k * H / 7
        r = 0.18
        for (x0, y0, x1, y1) in ((-r, -r, r, -r + .02), (-r, r - .02, r, r), (-r, -r, -r + .02, r), (r - .02, -r, r, r)):
            box(x0, y0, zz, x1, y1, zz + 0.03, m if k % 2 else m2)
    sphere(0, 0, H + 0.05, 0.06, MAT("glow:#ff4030"))


def watchtower():
    w = MAT("wood:#6a5034:#5a4028"); w2 = MAT("wood:#7a5e3e:#5a4028")
    for (a, b) in ((-.55, -.55), (.55, -.55), (-.55, .55), (.55, .55)):
        box(a - .06, b - .06, 0, a + .06, b + .06, 2.6, w)
    for zz in (0.9, 1.8):
        o = box(-.55, .53, zz - .4, .55, .57, zz + .4, w); o.rotation_euler.y = 0.6
    box(-.75, -.75, 2.6, .75, .75, 2.7, w2)
    for (x0, y0, x1, y1) in ((-.75, .69, .75, .75), (.69, -.75, .75, .75), (-.75, -.75, .75, -.69), (-.75, -.75, -.69, .75)):
        box(x0, y0, 2.7, x1, y1, 3.15, w2)
    for (a, b) in ((-.7, -.7), (.7, -.7), (-.7, .7), (.7, .7)):
        box(a - .03, b - .03, 2.7, a + .03, b + .03, 3.6, w)
    kit.mesh([(-.9, -.9, 3.6), (.9, -.9, 3.6), (.9, .9, 3.6), (-.9, .9, 3.6), (0, 0, 4.0)], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)],
             MAT("paint:#7a7a70:0.7"), "troof", solidify=0.03, center=True)


def water_tower():
    leg = MAT("paint:#7a7a74:0.6"); tank = MAT("paint:%s:0.5" % "#a8a49a")
    for (a, b) in ((-.9, -.9), (.9, -.9), (-.9, .9), (.9, .9)):
        cyl(a, b, 0, 4.2, 0.07, leg, 8)
    for zz in (1.4, 2.8):
        for (x0, y0, x1, y1) in ((-.9, -.93, .9, -.87), (-.9, .87, .9, .93), (-.93, -.9, -.87, .9), (.87, -.9, .93, .9)):
            box(x0, y0, zz, x1, y1, zz + 0.05, leg)
    cyl(0, 0, 4.2, 6.6, 1.25, tank, 28)
    o = FAST.primitive_cone_add(vertices=28, radius1=1.32, radius2=0.1, depth=0.7, location=g2b(0, 0, 6.95))
    o.data.materials.append(MAT("paint:#8a8478:0.6"))
    cyl(0, 0, 5.2, 5.6, 1.27, MAT("paint:#c84a3a:0.5"), 28)
    box(0.95, -0.05, 0, 1.0, 0.05, 6.6, leg)


def fuel_pump():
    col = MAT("paint:#c84a3a:0.5")
    box(-0.2, -0.15, 0, 0.2, 0.15, 1.2, col, 0.03)
    box(-0.16, 0.15, 0.62, 0.16, 0.16, 0.95, MAT("flat:#e0d8c0:0.5"))
    box(-0.22, -0.17, 1.2, 0.22, 0.17, 1.3, MAT("paint:#e0d8c8:0.4"))
    box(0.2, -0.05, 0.5, 0.26, 0.05, 0.9, MAT("flat:#1e1c1a:0.6"))
    box(-0.26, -0.2, -0.02, 0.26, 0.2, 0.05, MAT("conc:#8a8478"))


def water_pump():
    m = MAT("paint:#4a5a4a:0.6")
    cyl(0, 0, 0, 0.9, 0.06, m, 10)
    box(0.0, -0.03, 0.75, 0.32, 0.03, 0.8, m)
    o = box(-0.45, -0.025, 0.85, 0.0, 0.025, 0.9, m); o.rotation_euler.y = math.radians(-20)
    box(-0.25, -0.25, -0.02, 0.25, 0.25, 0.08, MAT("conc:#8a8478"))
    cyl(0.25, 0, 0.0, 0.15, 0.12, MAT("wood:#6a5034:#5a4028"), 10)


def tent():
    can = MAT("fab:#8a7a52")
    kit.mesh([(-0.6, -0.55, 0), (0.6, -0.55, 0), (0.6, 0, 0.85), (-0.6, 0, 0.85)], [(0, 1, 2, 3)], can, "t1", solidify=0.02, center=True)
    kit.mesh([(-0.6, 0.55, 0), (0.6, 0.55, 0), (0.6, 0, 0.85), (-0.6, 0, 0.85)], [(0, 1, 2, 3)], MAT("fab:#7a6a46"), "t2", solidify=0.02, center=True)
    kit.mesh([(0.6, -0.55, 0), (0.6, 0.55, 0), (0.6, 0, 0.85)], [(0, 1, 2)], MAT("flat:#1e1812:1.0"), "t3", center=True)
    cyl(-0.65, 0, 0, 0.95, 0.02, MAT("wood:#6a5034:#5a4028"), 6); cyl(0.65, 0, 0, 0.95, 0.02, MAT("wood:#6a5034:#5a4028"), 6)


def cache(open_):
    w = MAT("paint:#5a6a44:0.6"); trim = MAT("metal:#8a8a84")
    box(-0.32, -0.22, 0, 0.32, 0.22, 0.32, w, 0.02)
    for x in (-0.25, 0.25):
        box(x - 0.02, -0.23, 0, x + 0.02, 0.23, 0.33, trim)
    if open_:
        o = box(-0.32, -0.22, 0.32, 0.32, -0.19, 0.72, w); o.rotation_euler.x = 0.25
        box(-0.28, -0.18, 0.2, 0.28, 0.18, 0.31, MAT("flat:#16120e:1.0"))
        for k in range(3):
            box(-0.2 + k * 0.14, -0.08, 0.28, -0.1 + k * 0.14, 0.06, 0.36, MAT("flat:%s:0.6" % ["#c8a040", "#8a3a2a", "#4a6a8a"][k]))
    else:
        box(-0.33, -0.23, 0.32, 0.33, 0.23, 0.37, w, 0.02)
        box(-0.04, 0.22, 0.2, 0.04, 0.24, 0.3, MAT("metal:#c8a040"))


def crate_open():
    w = MAT("wood:#9a7a50:#7a6040")
    for (x0, y0, x1, y1) in ((-.3, -.3, .3, -.26), (-.3, .26, .3, .3), (-.3, -.3, -.26, .3), (.26, -.3, .3, .3)):
        box(x0, y0, 0, x1, y1, 0.55, w)
    box(-.27, -.27, 0, .27, .27, 0.04, w)
    o = box(-.3, .3, 0, .3, .34, 0.6, w); o.rotation_euler.x = -1.2
    for k in range(4):
        box(-.2 + k * 0.1, -.1, 0.05, -.13 + k * 0.1, 0.1, 0.32, MAT("flat:%s:0.8" % ["#c8b890", "#a08058", "#8a6e4a", "#d8c8a0"][k]))


def stump():
    bark = MAT("flat:#5a4632:0.95")
    cyl(0, 0, 0, 0.25, 0.2, bark, 12)
    cyl(0, 0, 0.25, 0.26, 0.17, MAT("flat:#b89a6a:0.8"), 12)
    for k in range(3):
        a = k * 2.1
        o = box(0, -0.03, 0, 0.32, 0.03, 0.06, bark); rot_z(o, math.degrees(a), (0, 0))


def pillar():
    c = MAT("conc:#a8a090")
    box(-0.13, -0.13, 0, 0.13, 0.13, 3.1, c)
    box(-0.17, -0.17, 3.0, 0.17, 0.17, 3.15, c)
    box(-0.17, -0.17, 0, 0.17, 0.17, 0.12, c)


def post():
    box(-0.04, -0.04, 0, 0.04, 0.04, 0.95, MAT("wood:#6a5034:#5a4028"))


def puddle():
    m = MAT("glow:#7adf4a") if False else None
    from lib import mat_flat
    mt = mat_flat("toxic", "#6ac040", 0.15, emit="#4a9a2a")
    for k in range(3):
        o = cyl(random.Random(k).uniform(-.25, .25), random.Random(k + 9).uniform(-.12, .12), 0.0, 0.006, [0.42, 0.3, 0.22][k], mt, 16)
        o.scale = (1.0, 0.6, 1.0)


def bag():
    o = FAST.primitive_ico_sphere_add(subdivisions=2, radius=0.2, location=g2b(0, 0, 0.17))
    o.scale = (1.0, 0.85, 0.85); o.data.materials.append(MAT("fab:#8a7a52"))
    cyl(0, 0, 0.3, 0.38, 0.05, MAT("fab:#6a5a3a"), 8)


def awning(col, axis):
    """Wall-mounted striped awning on a 1-tile segment, sloping out of the wall face (+w) and down."""
    for k in range(6):
        u0, u1 = k / 6, (k + 1) / 6
        c = col if k % 2 == 0 else "#e0d8c0"
        if axis == "x":
            pts = [(u0, 0, 0), (u1, 0, 0), (u1, 0.55, -0.32), (u0, 0.55, -0.32)]
        else:
            pts = [(0, u0, 0), (0, u1, 0), (0.55, u1, -0.32), (0.55, u0, -0.32)]
        kit.mesh(pts, [(0, 1, 2, 3)], MAT("fab:%s" % c), "aw", solidify=0.015, center=True)
    if axis == "x":
        box(0, 0.53, -0.42, 1.0, 0.57, -0.3, MAT("fab:%s" % col))
    else:
        box(0.53, 0, -0.42, 0.57, 1.0, -0.3, MAT("fab:%s" % col))


def roof_tank():
    for (a, b) in ((-.35, -.35), (.35, -.35), (-.35, .35), (.35, .35)):
        cyl(a, b, 0, 0.8, 0.04, MAT("wood:#5a4232:#4a3628"), 6)
    cyl(0, 0, 0.8, 2.0, 0.5, MAT("wood:#7a5a3a:#5a4028"), 20)
    o = FAST.primitive_cone_add(vertices=20, radius1=0.55, radius2=0.05, depth=0.35, location=g2b(0, 0, 2.17))
    o.data.materials.append(MAT("wood:#5a4232:#4a3628"))
    for zz in (1.0, 1.5, 1.9):
        cyl(0, 0, zz, zz + 0.04, 0.51, MAT("metal:#4a4a44"), 20)


def car(spr, k):
    rng = random.Random({"teal": 3, "red": 5, "yellow": 7, "burned": 9}[spr])
    col = {"teal": "#5e9a90", "red": "#a85444", "yellow": "#c8a858", "burned": None}[spr]
    P.car_wreck(0, 0, k * 45, rng, style="burned" if spr == "burned" else "sedan", col=col, hood=False)


def barrel_up(kind):
    body = {"blue": "paint:#3a5a8a:0.5", "rust": "paint:#8a4a2a:0.75", "toxic": "paint:#d8b830:0.45"}[kind]
    cyl(0, 0, 0, 0.9, 0.28, MAT(body), 18)
    for zz in (0.2, 0.68):
        cyl(0, 0, zz, zz + 0.05, 0.29, MAT("metal:#4a4a44"), 18)
    cyl(0, 0, 0.9, 0.92, 0.26, MAT("metal:#6a6a64"), 18)
    if kind == "toxic":
        cyl(0, 0, 0.36, 0.52, 0.285, MAT("flat:#1e1c1a:0.6"), 18)
        cyl(0.05, 0.02, 0.92, 0.935, 0.12, MAT("flat:#6ac040:0.2"), 12)


def chain_fence():
    """One tile of chain-link: posts, top rail and a see-through diamond mesh."""
    from lib import _nodes, _hex
    post = MAT("metal:#7a7a74")
    for x in (-0.5, 0.5):
        cyl(x, 0, 0, 1.55, 0.03, post, 6)
    box(-0.5, -0.015, 1.5, 0.5, 0.015, 1.54, post)
    m, nt, bs = _nodes("chainmesh")
    bs.inputs["Base Color"].default_value = _hex("#9a9a92"); bs.inputs["Metallic"].default_value = 0.6
    tc = nt.nodes.new("ShaderNodeTexCoord"); mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Rotation"].default_value = (0, math.radians(45), 0); mp.inputs["Scale"].default_value = (22, 22, 22)
    nt.links.new(tc.outputs["Object"], mp.inputs[0])
    br = nt.nodes.new("ShaderNodeTexBrick"); br.inputs["Mortar Size"].default_value = 0.12; br.offset = 0.0
    br.inputs["Brick Width"].default_value = 1.0; br.inputs["Row Height"].default_value = 1.0
    nt.links.new(mp.outputs[0], br.inputs["Vector"])
    kit._alpha_out(m, nt, bs, br.outputs["Fac"])
    box(-0.5, -0.004, 0.04, 0.5, 0.004, 1.5, m)


def console_tv(rng):
    w = P.wood(rng)
    box(-0.32, -0.25, 0.18, 0.32, 0.25, 0.8, w, 0.02)
    for (a, b) in ((-0.28, -0.2), (0.28, -0.2), (-0.28, 0.2), (0.28, 0.2)):
        box(a - .02, b - .02, 0, a + .02, b + .02, 0.18, w)
    box(-0.24, 0.25, 0.32, 0.12, 0.26, 0.72, MAT("flat:#3a4a48:0.25"))
    box(-0.22, 0.26, 0.34, 0.1, 0.265, 0.7, MAT("flat:#5a7a72:0.2"))
    for k in range(2):
        box(0.17, 0.25, 0.5 + k * 0.12, 0.25, 0.27, 0.56 + k * 0.12, MAT("metal:#c8a040"))
    for s_ in (-1, 1):
        o = box(-0.005, -0.005, 0.8, 0.005, 0.005, 1.15, MAT("metal:#2a2a28")); o.rotation_euler.y = s_ * 0.45


def stool():
    m = MAT("metal:#8a8a84")
    cyl(0, 0, 0, 0.55, 0.03, m, 8)
    cyl(0, 0, 0.55, 0.62, 0.15, MAT("paint:#b83a2a:0.4"), 14)
    cyl(0, 0, 0.0, 0.03, 0.15, m, 12)


def desk(rng):
    w = P.wood(rng)
    box(-0.6, -0.3, 0.68, 0.6, 0.3, 0.74, w, 0.01)
    box(0.2, -0.28, 0.05, 0.58, 0.28, 0.68, w)
    for (a, b) in ((-0.56, -0.26), (-0.56, 0.26)):
        box(a - .025, b - .025, 0, a + .025, b + .025, 0.68, w)
    for k in range(3):
        box(0.24, 0.28, 0.1 + k * 0.19, 0.54, 0.29, 0.25 + k * 0.19, MAT("metal:#c8a040"))
    P.clutter_top(-0.1, 0, 0.74, rng, 0.25)


FURN = {   # long side, depth (tiles) — World.FURN_SIZE
    'counter': (1.0, .5), 'stove': (.5, .5), 'fridge': (.5, .5), 'table': (.9, .6), 'chair': (.3, .3), 'couch': (1.0, .45),
    'armchair': (.45, .45), 'tv': (.4, .3), 'bookshelf': (.9, .3), 'bed': (1.0, .6), 'dresser': (.6, .35), 'desk': (.8, .45),
    'filing': (.35, .35), 'shopshelf': (1.0, .35), 'shopcounter': (1.0, .4), 'workbench': (.9, .4), 'barrel': (.35, .35),
    'mattress': (.9, .55), 'booth': (1.0, .45), 'jukebox': (.45, .35), 'terminal': (.6, .4), 'locker': (.8, .3),
    'stool': (.25, .25), 'vending': (.5, .4),
}


def furn_builder(nm, orient):
    rot = 0 if orient == "a" else -90
    r = random.Random(hash(nm) % 997)
    f = {'counter': lambda: P.counter(0, 0, rot, r, w=1.2, sink=False), 'stove': lambda: P.stove(0, 0, rot, r),
         'fridge': lambda: P.fridge(0, 0, rot, r), 'table': lambda: P.table(0, 0, rot, r, shape="rect"),
         'chair': lambda: P.chair(0, 0, rot + 180, r, style="wood"), 'couch': lambda: P.couch(0, 0, rot, r, w=1.5),
         'armchair': lambda: P.armchair(0, 0, rot, r), 'tv': lambda: _rot(lambda: console_tv(r), rot), 'bookshelf': lambda: P.bookshelf(0, 0, rot, r, w=1.0),
         'bed': lambda: P.bed(0, 0, rot, r, size=1.4), 'dresser': lambda: P.dresser(0, 0, rot, r), 'desk': lambda: _rot(lambda: desk(r), rot),
         'filing': lambda: P.filing_cabinet(0, 0, rot, r), 'shopshelf': lambda: P.gondola(0, 0, rot, r, w=1.4, stock=0.55),
         'shopcounter': lambda: P.checkout(0, 0, rot, r), 'workbench': lambda: P.workbench(0, 0, rot, r),
         'barrel': lambda: P.barrel(0, 0, rot, r, kind="rust"), 'mattress': lambda: P.mattress(0, 0, rot, r),
         'booth': lambda: P.booth(0, 0, rot, r), 'jukebox': lambda: P.jukebox(0, 0, rot, r), 'terminal': lambda: P.terminal(0, 0, rot, r),
         'locker': lambda: P.locker_row(0, 0, rot, r, n=3), 'stool': lambda: stool(), 'vending': lambda: P.vending(0, 0, rot, r)}
    return f[nm]


def _rot(fn, deg):
    n0 = PC.mark(); fn()
    if deg:
        for o in PC.new_objects_since(n0):
            rot_z(o, deg, (0, 0))


# ---- underground entrances and props
def cave_mouth(rng):
    m = P.MAT("rock:#7a6e60:#56504a")
    for x, y, sz in ((0.0, 0.0, 1.05), (-0.7, 0.5, 0.7), (0.6, -0.7, 0.75), (-0.2, -0.6, 0.6), (0.4, 0.6, 0.55)):
        P.rock(x, y, 0, rng, size=sz)
    dark = P.MAT("flat:#050403:1.0")
    sphere(0.62, 0.62, 0.25, 0.62, dark, scale=(1.0, 1.0, 0.9))


def mine_entrance(rng):
    P.rock(-0.3, -0.3, 0, rng, size=1.0)
    P.rock(0.6, -0.6, 0, rng, size=0.65)
    P.rock(-0.6, 0.6, 0, rng, size=0.65)
    w = P.MAT("wood:#6a4a2e:#4a3220")
    dark = P.MAT("flat:#0a0806:1.0")
    box(0.1, -0.35, 0.0, 0.55, 0.35, 0.95, dark)
    for y in (-0.42, 0.42):
        box(0.5, y - 0.07, 0.0, 0.64, y + 0.07, 1.05, w)
    box(0.5, -0.55, 1.0, 0.66, 0.55, 1.14, w)
    box(0.66, -0.3, 1.16, 0.7, 0.3, 1.42, P.MAT("wood:#8a6a48:#74583a"))
    for k in range(4):
        box(0.7 + k * 0.28, -0.32, 0.0, 0.8 + k * 0.28, 0.32, 0.04, w)
    for y in (-0.2, 0.2):
        box(0.6, y - 0.02, 0.04, 1.8, y + 0.02, 0.07, P.MAT("metal:#5a5048"))


def vault_door(rng):
    for x, y, sz in ((-0.4, -0.2, 1.1), (0.3, -0.8, 0.8), (-0.8, 0.6, 0.8), (0.0, 0.5, 0.7)):
        P.rock(x, y, 0, rng, size=sz)
    conc = P.MAT("conc:#8a8478")
    box(0.35, -0.8, 0.0, 0.75, 0.8, 1.55, conc)
    o = cyl(0.8, 0.0, 0.0, 0.18, 0.62, P.MAT("paint:#b8a040:0.3"), 24)
    o.rotation_euler = (0, 1.5708, 0)
    o.location = g2b(0.8, 0.0, 0.72)
    for k in range(12):
        import math
        a = k * math.tau / 12
        t = cyl(0.8, 0.0, 0.0, 0.2, 0.08, P.MAT("metal:#6a6458"), 8)
        t.rotation_euler = (0, 1.5708, 0)
        t.location = g2b(0.82, math.cos(a) * 0.62, 0.72 + math.sin(a) * 0.62)
    c = cyl(0.8, 0.0, 0.0, 0.24, 0.16, P.MAT("metal:#3a3630"), 12)
    c.rotation_euler = (0, 1.5708, 0)
    c.location = g2b(0.88, 0.0, 0.72)
    box(0.75, -0.95, 0.0, 1.6, 0.95, 0.06, conc)


def manhole():
    cyl(0, 0, 0.0, 0.04, 0.42, P.MAT("metal:#4a4640"), 24)
    for k in range(5):
        box(-0.3 + k * 0.15, -0.3, 0.04, -0.27 + k * 0.15, 0.3, 0.06, P.MAT("metal:#2e2c28"))


def ladder_up():
    m = P.MAT("metal:#7a7064")
    for y in (-0.22, 0.22):
        box(-0.04, y - 0.03, 0.0, 0.04, y + 0.03, 2.4, m)
    for k in range(9):
        box(-0.03, -0.22, 0.2 + k * 0.25, 0.03, 0.22, 0.24 + k * 0.25, m)



def minecart(rng):
    rust = P.MAT("paint:#6a5a4a:0.7")
    box(-0.45, -0.3, 0.18, 0.45, 0.3, 0.62, rust)
    for x in (-0.3, 0.3):
        for y in (-0.32, 0.32):
            c = cyl(x, y, 0, 0.06, 0.12, P.MAT("metal:#2e2c28"), 12)
            c.rotation_euler = (1.5708, 0, 0)
            c.location = g2b(x, y, 0.13)
    for k in range(6):
        P.rock(rng.uniform(-0.3, 0.3), rng.uniform(-0.2, 0.2), 0, rng, size=0.13)
        FAST.LAST[0].location.z += 0.6


def mine_support(rng):
    w = P.MAT("wood:#6a4a2e:#4a3220")
    for y in (-0.5, 0.5):
        box(-0.07, y - 0.07, 0.0, 0.07, y + 0.07, 1.25, w)
    box(-0.09, -0.62, 1.2, 0.09, 0.62, 1.36, w)
    cyl(0, 0, 1.0, 1.18, 0.07, P.MAT("glow:#ffcc66"), 10)


def stalagmites(rng):
    m = P.MAT("rock:#8a7e6c:#5e564a")
    for k in range(4):
        x, y = rng.uniform(-0.3, 0.3), rng.uniform(-0.25, 0.25)
        h = rng.uniform(0.4, 1.1)
        FAST.primitive_cone_add(vertices=7, radius1=rng.uniform(0.1, 0.2), radius2=0.01, depth=h, location=g2b(x, y, h / 2))
        FAST.LAST[0].data.materials.append(m)


def pipes():
    m = P.MAT("metal:#6a6050")
    for z in (0.25, 0.55):
        c = cyl(0, 0, 0, 1.6, 0.08, m, 12)
        c.rotation_euler = (1.5708, 0, 0)
        c.location = g2b(0, 0.8, z)
    v = cyl(0, 0, 0.0, 0.04, 0.16, P.MAT("paint:#a83a2a:0.4"), 12)
    v.rotation_euler = (0, 1.5708, 0)
    v.location = g2b(0.12, 0.0, 0.55)


def crystal(rng):
    m = P.MAT("glow:#6aff9a")
    for k in range(5):
        x, y = rng.uniform(-0.15, 0.15), rng.uniform(-0.12, 0.12)
        h = rng.uniform(0.25, 0.6)
        FAST.primitive_cone_add(vertices=5, radius1=0.07, radius2=0.0, depth=h, location=g2b(x, y, h / 2), rotation=(rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 0))
        FAST.LAST[0].data.materials.append(m)


def red_spire(rng):
    m = P.MAT("rock:#a8603e:#7a4028")
    z = 0.0
    for k, r in enumerate((0.55, 0.45, 0.38, 0.3)):
        h = rng.uniform(0.35, 0.55)
        o = box(-r, -r * 0.8, z, r, r * 0.8, z + h, m)
        rot_z(o, rng.uniform(-15, 15), (0, 0))
        z += h
    P.rock(0.5, 0.3, 0, rng, size=0.25)


def reeds(rng, n):
    bt = FAST.Batch("reeds")
    ms = [P.MAT("leaf:#7a8a4a:#5a6a34"), P.MAT("leaf:#9a8a5a:#6a5a3a")]
    for k in range(n):
        h = rng.uniform(0.45, 0.95)
        x, y = rng.uniform(-.25, .25), rng.uniform(-.2, .2)
        bt.cone(g2b(x, y, h / 2), 0.02, 0.004, h, 3, ms[k % 2], rot=(rng.uniform(-.25, .25), rng.uniform(-.25, .25), 0))
        if k % 4 == 0:
            cyl(x, y, h - 0.12, h + 0.02, 0.03, P.MAT("flat:#5a3a24:0.9"), 6)
    bt.done()


def salt_crust(rng):
    m = P.MAT("rock:#e8e2d4:#c8c0ae")
    for k in range(5):
        x, y = rng.uniform(-0.3, 0.3), rng.uniform(-0.25, 0.25)
        h = rng.uniform(0.08, 0.26)
        o = box(x - 0.09, y - 0.07, 0, x + 0.09, y + 0.07, h, m)
        rot_z(o, rng.uniform(0, 90), (x, y))


def specs():
    R = lambda s=1: random.Random(s)
    S = {}
    S["ac_unit"] = dict(build=lambda: P._ac_unit(0, 0, 0, R(), z=0.0))
    S["antenna"] = dict(build=antenna)
    S["bag"] = dict(build=bag)
    S["barrel"] = dict(build=lambda: barrel_up("blue"))
    S["barrel_rust"] = dict(build=lambda: barrel_up("rust"))
    S["barrel_toxic"] = dict(build=lambda: barrel_up("toxic"))
    S["bench"] = dict(build=lambda: P.bench(0, 0, 0, R(5)))
    S["billboard_x"] = dict(build=lambda: billboard("x"))
    S["billboard_y"] = dict(build=lambda: billboard("y"))
    S["bones"] = dict(build=lambda: P.skeleton(0, 0, 20, R(7)))
    S["bricks"] = dict(build=lambda: P.rubble_pile(0, 0, 0, R(8), size=0.6, mats=[MAT("paint:#8e4a3a:0.6"), MAT("paint:#a85a44:0.6")]))
    S["cache"] = dict(build=lambda: cache(False))
    S["cache_open"] = dict(build=lambda: cache(True))
    S["campfire0"] = dict(build=lambda: campfire(R(), 0))
    S["campfire1"] = dict(build=lambda: campfire(R(), 1))
    S["cart"] = dict(build=lambda: P.shopping_cart(0, 0, 20, random.Random(11)))
    S["crate"] = dict(build=lambda: P.crate(0, 0, 0, R(12), s=0.6))
    S["crate_open"] = dict(build=crate_open)
    S["deadbush"] = dict(build=lambda: P.deadbush(0, 0, 0, R(13)))
    S["fence"] = dict(build=chain_fence)
    S["flag"] = dict(build=lambda: flag("#d8c8a0", R()))
    S["flag_main"] = dict(build=lambda: flag("#e0b640", R()))
    S["flag_raider"] = dict(build=lambda: flag("#b83a2a", R()))
    S["fuelpump"] = dict(build=fuel_pump)
    S["hydrant"] = dict(build=lambda: P.hydrant(0, 0, 0, R(15)))
    S["jersey_x"] = dict(build=lambda: P.jersey(0, 0, 0, R(16)))
    S["jersey_y"] = dict(build=lambda: P.jersey(0, 0, 90, R(16)))
    S["lamp"] = dict(build=lambda: P.lamp_post(0, 0, 0, random.Random(2)))
    S["mailbox"] = dict(build=lambda: P.mailbox(0, 0, 0, R(17)))
    S["newsbox"] = dict(build=lambda: P.newsbox(0, 0, 0, R(18)))
    S["papers"] = dict(build=lambda: P.litter(0, 0, 0, R(19), n=8, r=0.45), outline=False)
    S["phonebooth"] = dict(build=lambda: P.phone_booth(0, 0, 0, R(20)))
    S["picket_x"] = dict(build=lambda: picket("x"))
    S["picket_y"] = dict(build=lambda: picket("y"))
    S["pillar"] = dict(build=pillar)
    S["pole"] = dict(build=utility_pole)
    S["post"] = dict(build=post)
    S["puddle_toxic"] = dict(build=puddle, outline=False)
    S["pump"] = dict(build=water_pump)
    S["roof_tank"] = dict(build=roof_tank)
    S["roof_vent"] = dict(build=lambda: P._vent(0, 0, 0, R(21), z=0.0))
    for k in range(3):
        S["rubble%d" % k] = dict(build=(lambda k=k: lambda: P.rubble_pile(0, 0, 0, R(30 + k), size=0.9))())
        S["tuft%d" % k] = dict(build=(lambda k=k: lambda: P.grass_tuft(0, 0, 0, R(40 + k), n=12))(), outline=False)
        S["tree%d" % k] = dict(build=(lambda k=k: lambda: leafy_tree(R(50 + k), 1.0 + k * 0.12))())
    S["shrub"] = dict(build=lambda: P.shrub(0, 0, 0, R(22)))
    S["rock0"] = dict(build=lambda: P.rock(0, 0, 0, R(80), size=0.42))
    S["rock1"] = dict(build=lambda: [P.rock(0, 0, 0, R(81), size=0.3), P.rock(0.35, 0.2, 0, R(82), size=0.2)])
    S["rock2"] = dict(build=lambda: P.pebbles(0, 0, 0, R(83), n=7, r=0.4), outline=False)
    S["boulder"] = dict(build=lambda: [P.rock(0, 0, 0, R(84), size=0.75), P.rock(0.6, 0.3, 0, R(85), size=0.3)], match=False, scale=LAB2GAME * 1.0)
    S["redrock"] = dict(build=lambda: red_spire(R(86)), match="h")
    S["cactus0"] = dict(build=lambda: P.cactus(0, 0, 0, R(87)), match=False, scale=LAB2GAME * 0.9)
    S["cactus1"] = dict(build=lambda: [P.cactus(0, 0, 0, R(88)), P.cactus(0.4, 0.2, 0, R(89))], match=False, scale=LAB2GAME * 0.8)
    S["reeds0"] = dict(build=lambda: reeds(R(90), 14))
    S["reeds1"] = dict(build=lambda: reeds(R(91), 22))
    S["tumbleweed"] = dict(build=lambda: P.tumbleweed(0, 0, 0, R(92)))
    S["saltrock"] = dict(build=lambda: salt_crust(R(93)))
    S["cave_mouth"] = dict(build=lambda: cave_mouth(R(100)), match=False, scale=LAB2GAME * 0.95)
    S["mine_entrance"] = dict(build=lambda: mine_entrance(R(101)), match=False, scale=LAB2GAME * 0.95)
    S["vault_door"] = dict(build=lambda: vault_door(R(102)), match=False, scale=LAB2GAME * 0.95)
    S["manhole"] = dict(build=lambda: manhole(), match="w", outline=False)
    S["ladder_up"] = dict(build=lambda: ladder_up(), match="h")
    S["minecart"] = dict(build=lambda: minecart(R(103)), match="w")
    S["mine_support"] = dict(build=lambda: mine_support(R(104)), match="w")
    S["stalagmite"] = dict(build=lambda: stalagmites(R(105)), match="h")
    S["pipes"] = dict(build=lambda: pipes(), match="w")
    S["crystal"] = dict(build=lambda: crystal(R(106)), match="w")
    S["stump"] = dict(build=stump)
    S["tent"] = dict(build=tent)
    S["tire"] = dict(build=lambda: P.tire_stack(0, 0, 0, R(23), n=1))
    S["tower"] = dict(build=watchtower)
    S["trashbag"] = dict(build=lambda: P.trash_bags(0, 0, 0, R(24), n=1))
    S["tree_dead"] = dict(build=lambda: P.tree(0, 0, 0, R(25), kind="dead"))
    S["tree_dead1"] = dict(build=lambda: P.tree(0, 0, 0, R(61), kind="dead"))
    S["tree_dead2"] = dict(build=lambda: P.tree(0, 0, 0, R(62), kind="sparse"))
    S["tree3"] = dict(build=lambda: P.tree(0, 0, 0, R(63), kind="pine"))
    S["tree4"] = dict(build=lambda: P.tree(0, 0, 0, R(64), kind="pine"))
    S["tree5"] = dict(build=lambda: leafy_tree(R(65), 0.85, ("#8a8a48", "#6a6a34")))
    S["tree6"] = dict(build=lambda: P.tree(0, 0, 0, R(66), kind="scrub"))
    S["tree7"] = dict(build=lambda: leafy_tree(R(67), 1.25, ("#4e6a34", "#3a5228")))
    S["vending_x"] = dict(build=lambda: P.vending(0, 0, 0, R(26)))
    S["vending_y"] = dict(build=lambda: P.vending(0, 0, -90, R(26)))
    S["watertower"] = dict(build=water_tower)
    S["workbench"] = dict(build=lambda: P.workbench(0, 0, 0, R(27)))
    for col in ("3e8a86", "c84a3a", "d8b040"):
        for ax in "xy":
            S["awning_%s_%s" % (col, ax)] = dict(build=(lambda c=col, a=ax: lambda: awning("#" + c, a))(), scale=1.0, outline=False, match=False)
    for spr in ("teal", "red", "yellow", "burned"):
        for k in range(8):
            S["car_%s_%d" % (spr, k)] = dict(build=(lambda s=spr, k=k: lambda: car(s, k))(), scale=0.9, match=False)
    for nm, sz in FURN.items():
        for o in "ab":
            fx = sz if o == "a" else (sz[1], sz[0])
            S["furn_%s_%s" % (nm, o)] = dict(build=furn_builder(nm, o), center=True, fit_xy=fx, bright=1.3, sat=1.12)
    return S


def main(prefixes):
    reset()
    lights()
    S = specs()
    done = 0
    TALL = ("flag", "lamp", "pole", "pillar", "antenna", "post", "tower", "watertower", "phonebooth", "fuelpump", "pump",
            "campfire", "mailbox", "hydrant", "newsbox", "roof_tank", "tree", "vending")
    for name, sp in S.items():
        if "match" not in sp and name.startswith(TALL):
            sp["match"] = "h"
        if prefixes and not any(name.startswith(p) for p in prefixes):
            continue
        kw = {k: v for k, v in sp.items() if k != "build"}
        try:
            render_prop(name, sp["build"], **kw)
            done += 1
        except Exception as e:
            print("FAILED", name, repr(e), flush=True)
    print("rendered", done, flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
