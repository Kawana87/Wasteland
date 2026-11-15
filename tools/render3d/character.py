"""Pre-rendered player character for the game: a jointed low-poly survivor (blue jumpsuit, yellow stripe,
backpack), posed with simple forward kinematics and rendered at the game's exact dimetric angle.

Sheet layout (assets/sprites/player_r.png): 8 rows = screen directions (row k faces screen angle k*45deg,
0 = right, 2 = down, 4 = left, 6 = up), 8 columns = frames:
    0 idle | 1-4 walk cycle | 5 crouch idle | 6-7 crouch walk
Cells are CELL_W x CELL_H; the feet sit on ANCHOR. Renders at SS x supersampling and filters down.
python3 character.py [out_dir]"""
import sys, os, math, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Matrix, Vector, Euler
from lib import reset, lights, g2b
import fast as FAST
import props as P
from PIL import Image, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "sprites")
CELL_W, CELL_H = 32, 48
ANCHOR = (16, 45)
SS = 4                                   # supersampling
PX = 48 / math.sqrt(2)                   # game pixels per world unit along the tile diamond (to_screen uses 24/12)
MAT = P.MAT

C = {"suit": "fab:#3a5f94", "suit_d": "fab:#2e4c78", "stripe": "flat:#e0b640:0.5", "skin": "flat:#e0b090:0.6",
     "hair": "flat:#5a3a24:0.8", "boot": "flat:#3a2a20:0.6", "belt": "flat:#5a4030:0.6", "pack": "fab:#7a5a38",
     "roll": "fab:#8a7a5a", "glove": "flat:#4a3a2c:0.7", "metal": "metal:#8a8a84"}


# ------------------------------------------------------------------ geometry helpers (local frame: +X forward, +Y left, +Z up)
class Rig:
    def __init__(self):
        self.root = bpy.data.objects.new("rig", None)
        bpy.context.scene.collection.objects.link(self.root)
        self.obs = []

    def _own(self, o):
        o.parent = self.root
        self.obs.append(o)
        return o

    def limb(self, p0, p1, r0, r1, mat, segs=8):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        o = FAST.primitive_cone_add(vertices=segs, radius1=r0, radius2=r1, depth=d.length, location=(p0 + p1) / 2)
        o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
        o.data.materials.append(MAT(mat))
        for p in o.data.polygons: p.use_smooth = True
        return self._own(o)

    def ball(self, c, r, mat, scale=(1, 1, 1)):
        o = FAST.primitive_uv_sphere_add(segments=12, ring_count=8, radius=r, location=Vector(c))
        o.scale = scale
        o.data.materials.append(MAT(mat))
        for p in o.data.polygons: p.use_smooth = True
        return self._own(o)

    def block(self, c, size, mat, rot=(0, 0, 0)):
        o = FAST.primitive_cone_add(vertices=4, radius1=0.7071, radius2=0.7071, depth=1.0, location=Vector(c))
        o.rotation_euler = Euler(rot)
        o.data.materials.append(MAT(mat))
        # a 4-sided cylinder rotated 45deg = box; scale to size
        o.rotation_euler.rotate(Euler((0, 0, math.radians(45))))
        o.scale = (size[0], size[1], size[2])
        return self._own(o)

    def box(self, c, size, mat, M=None):
        """Axis-aligned box in the (possibly transformed) local frame M."""
        o = bpy.data.objects.new("bx", _cube_mesh())
        bpy.context.scene.collection.objects.link(o)
        T = (M or Matrix()) @ Matrix.Translation(Vector(c)) @ Matrix.Diagonal((size[0], size[1], size[2], 1))
        o.matrix_world = T
        o.data = o.data.copy(); o.data.materials.append(MAT(mat))
        return self._own(o)

    def clear(self):
        bpy.data.batch_remove(ids=self.obs + [self.root])


_CUBE = None


def _cube_mesh():
    global _CUBE
    if _CUBE is None:
        import bmesh
        _CUBE = bpy.data.meshes.new("unitcube")
        bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0); bm.to_mesh(_CUBE); bm.free()
    return _CUBE


def sag(a_deg, length):
    """Vector in the sagittal plane: 0 = straight down, positive = swung forward."""
    a = math.radians(a_deg)
    return Vector((math.sin(a) * length, 0, -math.cos(a) * length))


# ------------------------------------------------------------------ the survivor
def build(pose):
    """pose: dict hipL/hipR (thigh swing, deg), kneeL/kneeR (bend), lean (torso pitch), arms ('aim' or swing deg)."""
    R = Rig()
    hip_y = 0.075
    Lt, Ls = 0.27, 0.27
    pelvis_h = 0.64
    # legs first in a temporary frame to find how low the feet reach, then lift the body so a foot is on the ground
    legs = []
    for side, s in (("L", 1), ("R", -1)):
        a, k = pose["hip" + side], pose["knee" + side]
        hip = Vector((0, s * hip_y, 0))
        knee = hip + sag(a, Lt)
        ankle = knee + sag(a - k, Ls)
        legs.append((s, hip, knee, ankle))
    lowest = min(l[3].z for l in legs)
    z0 = 0.075 - lowest                       # pelvis height that puts the lowest ankle at boot height
    off = Vector((0, 0, z0))
    for (s, hip, knee, ankle) in legs:
        R.limb(hip + off, knee + off, 0.058, 0.05, C["suit"])
        R.limb(knee + off, ankle + off + Vector((0, 0, 0.03)), 0.05, 0.042, C["suit"])
        a = ankle + off
        R.box((a.x + 0.035, a.y, a.z - 0.04), (0.17, 0.085, 0.075), C["boot"])
        R.box((a.x + 0.0, a.y, a.z + 0.02), (0.1, 0.09, 0.07), C["boot"])
    # pelvis + upper body, pitched forward by `lean` around the pelvis
    pel = Vector((0, 0, z0))
    U = Matrix.Translation(pel) @ Matrix.Rotation(math.radians(pose.get("lean", 0)), 4, 'Y')
    R.box((0, 0, 0.0), (0.15, 0.2, 0.11), C["suit"], U)
    R.box((0, 0, 0.065), (0.155, 0.215, 0.04), C["belt"], U)
    R.box((0.07, 0.06, 0.06), (0.03, 0.05, 0.05), C["belt"], U)         # pouch
    def up(v):
        return U @ Vector(v)
    # torso: tapered, wider at the shoulders
    R.limb(up((0, 0, 0.06)), up((0, 0, 0.36)), 0.105, 0.125, C["suit"], 10).scale = (1.0, 1.0, 1.0)
    R.box((0.11, 0, 0.21), (0.012, 0.03, 0.3), C["stripe"], U)              # front stripe
    R.limb(up((0, 0, 0.35)), up((0, 0, 0.385)), 0.075, 0.055, C["stripe"], 10)   # collar
    # backpack + bedroll
    R.box((-0.15, 0, 0.21), (0.11, 0.2, 0.24), C["pack"], U)
    R.box((-0.21, 0, 0.17), (0.02, 0.14, 0.1), C["belt"], U)
    o = R.limb(up((-0.15, 0.12, 0.37)), up((-0.15, -0.12, 0.37)), 0.05, 0.05, C["roll"], 8)
    # head
    neck = up((0.0, 0, 0.385))
    R.limb(neck, up((0.005, 0, 0.43)), 0.04, 0.04, C["skin"], 8)
    hc = up((0.01, 0, 0.5))
    R.ball(hc, 0.092, C["skin"], (1.0, 0.92, 1.05))
    R.ball(up((-0.012, 0, 0.53)), 0.094, C["hair"], (1.02, 0.96, 0.9))     # hair cap (sits back and high)
    R.ball(up((0.085, 0.035, 0.505)), 0.012, "flat:#2a2020:0.4")            # eyes
    R.ball(up((0.085, -0.035, 0.505)), 0.012, "flat:#2a2020:0.4")
    # arms
    for side, s in (("L", 1), ("R", -1)):
        sh = up((0.0, s * 0.155, 0.33))
        if pose.get("arms") == "aim":
            # both hands forward at chest height, as if holding the gun the game draws
            elbow = up((0.13, s * 0.15, 0.2))
            hand = up((0.27, s * 0.04, 0.24))
        else:
            sw = pose.get("arm" + side, 0)
            elbow = sh + U.to_3x3() @ sag(sw, 0.24)
            hand = elbow + U.to_3x3() @ sag(sw + 20, 0.22)
        R.limb(sh, elbow, 0.045, 0.04, C["suit"])
        R.limb(elbow, hand, 0.04, 0.034, C["suit_d"])
        R.ball(hand, 0.036, C["glove"])
        R.ball(sh, 0.05, C["suit"])
    return R


def poses():
    """Column order of the sheet."""
    out = [dict(hipL=4, hipR=-4, kneeL=6, kneeR=6, lean=2, arms="aim")]
    for i in range(4):
        ph = i / 4 * 2 * math.pi
        a = 26 * math.sin(ph)
        out.append(dict(hipL=a, hipR=-a,
                        kneeL=8 + 34 * max(0.0, -math.cos(ph + 0.6)), kneeR=8 + 34 * max(0.0, math.cos(ph + 0.6)),
                        lean=5, arms="aim"))
    out.append(dict(hipL=62, hipR=40, kneeL=105, kneeR=95, lean=24, arms="aim"))
    for i in range(2):
        a = 12 if i == 0 else -12
        out.append(dict(hipL=55 + a, hipR=45 - a, kneeL=100, kneeR=95, lean=26, arms="aim"))
    return out


def facing_yaw(k):
    """Blender yaw (rad) so a model facing local +X looks toward screen angle k*45deg (0=right, 90=down)."""
    a = math.radians(k * 45)
    sx, sy = math.cos(a), math.sin(a)
    wx, wy = sx / 48.0 + sy / 24.0, sy / 24.0 - sx / 48.0       # Iso.screen_dir_to_world
    return math.atan2(-wy, wx)                                    # game y is Blender -Y


def setup_camera():
    sc = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    W, H = CELL_W * SS, CELL_H * SS
    cam.data.ortho_scale = max(W, H) / (PX * SS)      # ortho scale spans the larger side
    cam.rotation_euler = (math.radians(60), 0, math.radians(45))
    # look at a point above the feet; shift so the feet land on ANCHOR
    d = cam.rotation_euler.to_matrix() @ Vector((0, 0, 1))
    cam.location = Vector((0, 0, 0.6)) + d * 20
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = W, H
    sc.render.film_transparent = True
    sc.cycles.samples = 24
    from bpy_extras.object_utils import world_to_camera_view
    bpy.context.view_layer.update()
    v = world_to_camera_view(sc, cam, Vector((0, 0, 0)))
    fx, fy = v.x * W, (1 - v.y) * H
    tx, ty = ANCHOR[0] * SS + SS / 2, ANCHOR[1] * SS + SS / 2
    cam.data.shift_x = (fx - tx) / max(W, H)          # shift is in units of the larger side
    cam.data.shift_y = -(fy - ty) / max(W, H)
    return cam


def downsample(im):
    """SS x render -> game pixels: area filter, crisp alpha, a soft dark outline for readability."""
    from PIL import ImageEnhance
    small = im.resize((CELL_W, CELL_H), Image.BOX)
    rgb, al = small.convert("RGB"), small.getchannel("A")
    rgb = ImageEnhance.Color(ImageEnhance.Brightness(rgb).enhance(1.22)).enhance(1.15)   # match the game's brighter palette
    small = Image.merge("RGBA", (*rgb.split(), al))
    r, g, b, a = small.split()
    a = a.point(lambda v: 255 if v > 110 else 0)
    small = Image.merge("RGBA", (r, g, b, a))
    # un-premultiply-ish: pixels that were half covered came out dark-fringed; lift them slightly
    px = small.load()
    out = Image.new("RGBA", small.size, (0, 0, 0, 0))
    op = out.load()
    for y in range(CELL_H):
        for x in range(CELL_W):
            if px[x, y][3]:
                op[x, y] = px[x, y]
            else:
                n = any(0 <= x + dx < CELL_W and 0 <= y + dy < CELL_H and px[x + dx, y + dy][3]
                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                if n:
                    op[x, y] = (26, 20, 16, 150)
    return out


def resheet(big_path="/tmp/r3d/player_r_big.png"):
    """Re-run only the downsample step from the saved supersampled sheet (fast tweaks of the post look)."""
    big = Image.open(big_path).convert("RGBA")
    sheet = Image.new("RGBA", (CELL_W * 8, CELL_H * 8), (0, 0, 0, 0))
    for c in range(8):
        for r in range(8):
            cell = big.crop((c * CELL_W * SS, r * CELL_H * SS, (c + 1) * CELL_W * SS, (r + 1) * CELL_H * SS))
            sheet.paste(downsample(cell), (c * CELL_W, r * CELL_H))
    sheet.save(os.path.join(OUT, "player_r.png"))


def main():
    reset()
    sc = bpy.context.scene
    sc.view_settings.view_transform = 'Standard'
    lights()
    setup_camera()
    tmp = "/tmp/r3d_char.png"
    sheet = Image.new("RGBA", (CELL_W * 8, CELL_H * 8), (0, 0, 0, 0))
    big = Image.new("RGBA", (CELL_W * SS * 8, CELL_H * SS * 8), (0, 0, 0, 0))
    for col, pose in enumerate(poses()):
        for row in range(8):
            rig = build(pose)
            rig.root.rotation_euler = (0, 0, facing_yaw(row))
            sc.render.filepath = tmp
            bpy.ops.render.render(write_still=True)
            im = Image.open(tmp).convert("RGBA")
            big.paste(im, (col * CELL_W * SS, row * CELL_H * SS))
            sheet.paste(downsample(im), (col * CELL_W, row * CELL_H))
            rig.clear()
        print("frame", col, flush=True)
    sheet.save(os.path.join(OUT, "player_r.png"))
    big.save("/tmp/r3d/player_r_big.png")
    # anchor for Assets.off(): feet pixel inside one cell
    ap = os.path.join(ROOT, "assets", "rendered_anchors.json")
    an = json.load(open(ap)) if os.path.exists(ap) else {}
    an["player_r"] = list(ANCHOR)
    json.dump(an, open(ap, "w"), indent=0, sort_keys=True)
    # also patch the live anchors.json (make_assets.py merges rendered_anchors.json on its next run)
    gp = os.path.join(ROOT, "assets", "anchors.json")
    g = json.load(open(gp)); g.update(an)
    json.dump(g, open(gp, "w"), separators=(",", ":"), sort_keys=True)
    print("wrote", os.path.join(OUT, "player_r.png"))


if __name__ == "__main__":
    if os.environ.get("RESHEET"):
        resheet()
    else:
        main()
