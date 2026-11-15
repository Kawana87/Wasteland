"""Shared harness for porting game sprites to Blender renders.

Every game sprite has a canvas (w x h px) and an anchor pixel (the screen point of its world position).
render_sprite() renders whatever is in the scene so that game-world origin (0,0,0) lands exactly on the
anchor, at the game's projection: Iso.to_screen(x, y, z) = ((x - y) * 24, (x + y) * 12 - z * 1.5)
(z in game "pixels"). Use gz(px) to convert game z pixels to Blender units.
"""
import sys, os, math, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from PIL import Image, ImageEnhance

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPR = os.path.join(ROOT, "assets", "sprites")
SS = 4
PX = 48 / math.sqrt(2)                       # screen px per world unit along a tile edge (ground)
ZPX = PX * math.sin(math.radians(60))        # screen px per world unit of height, for the 60deg camera
GZ = 1.5 / ZPX                               # world units per game-z pixel (to_screen uses z * 1.5)


def gz(px):
    return px * GZ


_CAM = None


def camera():
    global _CAM
    sc = bpy.context.scene
    if _CAM is None:
        cam = bpy.data.objects.new("pcam", bpy.data.cameras.new("pcam"))
        sc.collection.objects.link(cam)
        cam.data.type = 'ORTHO'
        cam.rotation_euler = (math.radians(60), 0, math.radians(45))
        d = cam.rotation_euler.to_matrix() @ Vector((0, 0, 1))
        cam.location = d * 40
        cam.data.clip_end = 200
        sc.camera = cam
        _CAM = cam
    return _CAM


def frame(w, h, ax, ay):
    """Point the camera so world origin lands on pixel corner (ax, ay) of a w x h canvas."""
    sc = bpy.context.scene
    cam = camera()
    W, H = w * SS, h * SS
    sc.render.resolution_x, sc.render.resolution_y = W, H
    sc.render.film_transparent = True
    big = max(W, H)
    cam.data.ortho_scale = big / (PX * SS)
    # with zero shift the origin projects to the image centre; shift it onto the anchor
    cam.data.shift_x = (W / 2 - ax * SS) / big
    cam.data.shift_y = -(H / 2 - ay * SS) / big


def check_projection():
    """Sanity: (1,0,0) must land 24px right / 12px down of the origin, z of 1 game px -> 1.5px up."""
    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene
    frame(100, 100, 50, 50)
    bpy.context.view_layer.update()
    def px(p):
        v = world_to_camera_view(sc, camera(), Vector(p))
        return (v.x * 100, (1 - v.y) * 100)
    o = px((0, 0, 0)); ex = px((1, 0, 0)); ey = px((0, -1, 0)); ez = px((0, 0, gz(10)))
    return o, ex, ey, ez


def render_raw(path="/tmp/r3d_port.png", samples=20):
    sc = bpy.context.scene
    sc.cycles.samples = samples
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return Image.open(path).convert("RGBA")


def shrink(im, w, h, bright=1.0, sat=1.0, alpha_cut=110, outline=False, soft_alpha=False):
    """Supersampled render -> game pixels."""
    small = im.resize((w, h), Image.BOX)
    rgb, al = small.convert("RGB"), small.getchannel("A")
    if bright != 1.0:
        rgb = ImageEnhance.Brightness(rgb).enhance(bright)
    if sat != 1.0:
        rgb = ImageEnhance.Color(rgb).enhance(sat)
    if not soft_alpha:
        al = al.point(lambda v: 255 if v > alpha_cut else 0)
    out = Image.merge("RGBA", (*rgb.split(), al))
    if outline:
        px = out.load()
        add = []
        for y in range(h):
            for x in range(w):
                if px[x, y][3] == 0 and any(0 <= x + dx < w and 0 <= y + dy < h and px[x + dx, y + dy][3] == 255
                                            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    add.append((x, y))
        for (x, y) in add:
            px[x, y] = (30, 24, 20, 140)
    return out


def sprite(name, w, h, ax, ay, samples=20, **kw):
    frame(w, h, ax, ay)
    im = render_raw(samples=samples)
    out = shrink(im, w, h, **kw)
    out.save(os.path.join(SPR, name + ".png"))
    return out


def clear(objs):
    objs = [o for o in objs if o is not None]
    if objs:
        bpy.data.batch_remove(ids=objs)


def new_objects_since(n0):
    import lib
    out = []
    for o in lib.REG[n0:]:
        try:
            o.name; out.append(o)
        except ReferenceError:
            pass
    return out


def mark():
    import lib
    return len(lib.REG)


def set_anchor(name, ax, ay):
    ap = os.path.join(ROOT, "assets", "rendered_anchors.json")
    an = json.load(open(ap)) if os.path.exists(ap) else {}
    an[name] = [ax, ay]
    json.dump(an, open(ap, "w"), indent=0, sort_keys=True)
