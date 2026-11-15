"""Second half of render_map3d.py: builds the Blender scene from the data the first half wrote to /tmp/wm and
renders it, then adds names and markers. Run render_map3d.py, not this (it calls this in a fresh process to keep
memory down)."""
import os, sys, json, math, time, argparse
ap = argparse.ArgumentParser(); ap.add_argument("--res", type=int, default=2048); ap.add_argument("--samples", type=int, default=24)
ap.add_argument("--crop", default="")
A = ap.parse_args()
import numpy as np
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import locations as LOC
T0 = time.time()
def log(*a): print("[%5.1fs]" % (time.time() - T0), *a, flush=True)
N = A.res; W = 100.0; ZS = 6.0; WL = 0.0
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "worldmap"); TMP = "/tmp/wm"; FONT = "/usr/share/fonts/truetype/dejavu/"
ys, xs = np.mgrid[0:N, 0:N].astype(np.float32); X, Y = xs / N, ys / N
H = np.load(TMP + "/height.npy")
g = np.load(TMP + "/geo.npz"); geo_v, geo_c = g["v"], g["c"]
fl, fn = g["f"], g["n"]
ROADS = json.load(open(TMP + "/roads.json"))
# ======================================================================= Blender
log("blender scene")
import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

def mesh_obj(name, verts, faces_list, colors=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts.tolist() if isinstance(verts, np.ndarray) else verts, [], faces_list)
    if colors is not None:
        at = me.color_attributes.new("col", 'FLOAT_COLOR', 'POINT')
        c4 = np.concatenate([colors, np.ones((len(colors), 1), np.float32)], 1)
        at.data.foreach_set("color", c4.ravel())
    ob = bpy.data.objects.new(name, me); sc.collection.objects.link(ob)
    return ob

# terrain mesh (half resolution grid) with smooth shading
G = N // 2 + 1
Hg = ndimage.zoom(H, G / N, order=1)[:G, :G]
gx_, gy_ = np.meshgrid(np.linspace(-W / 2, W / 2, G), np.linspace(W / 2, -W / 2, G))
verts = np.stack([gx_, gy_, Hg * ZS], -1).reshape(-1, 3).astype(np.float32)
idx = np.arange(G * G).reshape(G, G)
quads = np.stack([idx[:-1, :-1], idx[1:, :-1], idx[1:, 1:], idx[:-1, 1:]], -1).reshape(-1, 4)
me = bpy.data.meshes.new("terrain")
me.vertices.add(len(verts)); me.vertices.foreach_set("co", verts.ravel())
me.loops.add(quads.size); me.loops.foreach_set("vertex_index", quads.ravel())
me.polygons.add(len(quads)); me.polygons.foreach_set("loop_start", np.arange(0, quads.size, 4))
me.update(calc_edges=True)
me.shade_smooth()
terrain = bpy.data.objects.new("terrain", me); sc.collection.objects.link(terrain)
log("terrain %d verts" % len(verts))

def img(path, noncolor=False):
    im = bpy.data.images.load(path)
    if noncolor: im.colorspace_settings.name = 'Non-Color'
    return im

# terrain material: albedo + fine bump from a 16-bit height image + glow
hh = (H - H.min()) / (H.max() - H.min())
Image.fromarray((hh * 65535).astype(np.uint16)).save(TMP + "/height16.png")
mat = bpy.data.materials.new("terrain"); mat.use_nodes = True
nt = mat.node_tree; nd = nt.nodes; lk = nt.links
bsdf = nd["Principled BSDF"]
tc = nd.new("ShaderNodeTexCoord")
def tex(path, nc=False):
    t = nd.new("ShaderNodeTexImage"); t.image = img(path, nc); t.extension = 'EXTEND'; t.interpolation = 'Cubic'
    lk.new(tc.outputs["Generated"], t.inputs["Vector"]); return t
ta = tex(TMP + "/albedo.png"); th = tex(TMP + "/height16.png", True); tg = tex(TMP + "/glow.png", True)
lk.new(ta.outputs["Color"], bsdf.inputs["Base Color"])
bump = nd.new("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.35; bump.inputs["Distance"].default_value = (H.max() - H.min()) * ZS
lk.new(th.outputs["Color"], bump.inputs["Height"]); lk.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
bsdf.inputs["Roughness"].default_value = 0.92
bsdf.inputs["Emission Color"].default_value = (0.5, 1.0, 0.3, 1)
lk.new(tg.outputs["Color"], bsdf.inputs["Emission Strength"])
terrain.data.materials.append(mat)

# water plane
wm = bpy.data.meshes.new("water")
wm.from_pydata([(-W / 2, -W / 2, WL * ZS), (W / 2, -W / 2, WL * ZS), (W / 2, W / 2, WL * ZS), (-W / 2, W / 2, WL * ZS)], [], [(0, 1, 2, 3)])
wo = bpy.data.objects.new("water", wm); sc.collection.objects.link(wo)
wmat = bpy.data.materials.new("water"); wmat.use_nodes = True
wb = wmat.node_tree.nodes["Principled BSDF"]
wb.inputs["Base Color"].default_value = (0.07, 0.13, 0.14, 1); wb.inputs["Roughness"].default_value = 0.12
wwn = wmat.node_tree.nodes; wwl = wmat.node_tree.links
wn = wwn.new("ShaderNodeTexNoise"); wn.inputs["Scale"].default_value = 400; wbmp = wwn.new("ShaderNodeBump"); wbmp.inputs["Strength"].default_value = 0.08
wwl.new(wn.outputs["Fac"], wbmp.inputs["Height"]); wwl.new(wbmp.outputs["Normal"], wb.inputs["Normal"])
wo.data.materials.append(wmat)

# buildings (one mesh, per-vertex colour)
faces = []; p_ = 0
for n_ in fn.tolist():
    faces.append(tuple(fl[p_:p_ + n_].tolist())); p_ += n_
bo = mesh_obj("buildings", geo_v, faces, geo_c)
bmat = bpy.data.materials.new("bld"); bmat.use_nodes = True
an = bmat.node_tree.nodes.new("ShaderNodeAttribute"); an.attribute_name = "col"
bb = bmat.node_tree.nodes["Principled BSDF"]; bb.inputs["Roughness"].default_value = 0.85
bmat.node_tree.links.new(an.outputs["Color"], bb.inputs["Base Color"])
bo.data.materials.append(bmat)
log("buildings %d faces, dims %s, polys %d" % (len(faces), tuple(bo.dimensions), len(bo.data.polygons)))

# light: low warm sun from the north-west, cool sky fill
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 4.2; sun.data.angle = math.radians(1.2); sun.data.color = (1.0, 0.93, 0.82)
sun.rotation_euler = (math.radians(52), 0, math.radians(-135))
world = bpy.data.worlds.new("w"); sc.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.42, 0.5, 0.62, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.55
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam)
cam.data.type = 'ORTHO'; cam.data.ortho_scale = W; cam.location = (0, 0, 50); cam.data.clip_end = 200
sc.camera = cam
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = A.samples
sc.cycles.use_denoising = True; sc.cycles.max_bounces = 3; sc.cycles.diffuse_bounces = 2; sc.cycles.glossy_bounces = 1
sc.cycles.transmission_bounces = 2; sc.cycles.transparent_max_bounces = 2
sc.render.resolution_x = sc.render.resolution_y = N; sc.render.resolution_percentage = 100
sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'
sc.render.image_settings.file_format = 'PNG'; sc.render.filepath = TMP + "/render.png"
sc.render.threads_mode = 'AUTO'
sc.cycles.use_auto_tile = True; sc.cycles.tile_size = 512
import gc
gc.collect()
log("render %dx%d, %d samples" % (N, N, A.samples))
if A.crop:
    x0, y0, x1, y1 = map(float, A.crop.split(","))
    sc.render.use_border = True; sc.render.use_crop_to_border = True
    sc.render.border_min_x, sc.render.border_max_x = x0, x1; sc.render.border_min_y, sc.render.border_max_y = 1 - y1, 1 - y0
    sc.render.filepath = "/tmp/r3d/crop3d.png"; bpy.ops.render.render(write_still=True); log("crop done"); sys.exit(0)
if os.environ.get("WM_DEBUG"): bpy.ops.wm.save_as_mainfile(filepath=TMP + "/debug.blend")
bpy.ops.render.render(write_still=True)
log("rendered")

# ======================================================================= post: grade, names, markers
im = Image.open(TMP + "/render.png").convert("RGB")
a = np.asarray(im).astype(np.float32) / 255
a = np.clip((a - 0.5) * 1.05 + 0.5, 0, 1) * np.array([1.02, 1.0, 0.96])            # slight warm grade
v = np.clip(1 - (np.hypot(X - 0.5, Y - 0.5) / 0.78) ** 4, 0.65, 1)
a *= v[..., None]
im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
d = ImageDraw.Draw(im, "RGBA")
sx = N / 1200
tf = ImageFont.truetype(FONT + "DejaVuSerif-BoldItalic.ttf", int(22 * sx))
for (t, x, y, ang) in ((LOC.NAMES["river"], 0.6, 0.665, -62), (LOC.NAMES["lake"], 0.665, 0.065, 0), (LOC.NAMES["hills"], 0.1, 0.23, 0),
                       (LOC.NAMES["woods"], 0.44, 0.105, 0), (LOC.NAMES["city"], 0.82, 0.575, 0), (LOC.NAMES["waste"], 0.33, 0.55, 0),
                       (LOC.NAMES["marsh"], 0.6, 0.985, 0)):
    tw = int(d.textlength(t, font=tf)) + 12
    ti = Image.new("RGBA", (tw, int(34 * sx)), (0, 0, 0, 0)); td = ImageDraw.Draw(ti)
    td.text((7, 5), t, font=tf, fill=(10, 8, 6, 170)); td.text((6, 4), t, font=tf, fill=(240, 230, 200, 200))
    ti = ti.rotate(ang, expand=True, resample=Image.BICUBIC)
    im.alpha_composite(ti, (int(x * N - ti.width / 2), int(y * N - ti.height / 2)))
os.makedirs(OUT, exist_ok=True)
im.convert("RGB").save(os.path.join(OUT, "worldmap.png"), optimize=True)
road_out = ROADS
json.dump({"region": LOC.REGION, "size": [N, N], "names": LOC.NAMES,
           "locations": [dict(l, px=[round(l["pos"][0] * N), round(l["pos"][1] * N)]) for l in LOC.L], "roads": road_out},
          open(os.path.join(OUT, "locations.json"), "w"), indent=1)
lab = im.copy(); ld = ImageDraw.Draw(lab)
TC = {"hub": (250, 206, 60), "city": (236, 80, 56), "district": (226, 130, 76), "town": (110, 220, 100), "settlement": (150, 226, 140),
      "camp": (230, 186, 76), "landmark": (232, 214, 130), "dungeon": (226, 88, 80)}
RAD = {"hub": 14, "city": 15, "district": 9, "town": 12, "settlement": 9, "camp": 7, "landmark": 8, "dungeon": 8}
f1 = ImageFont.truetype(FONT + "DejaVuSansCondensed-Bold.ttf", int(16 * sx * 0.85))
f2 = ImageFont.truetype(FONT + "DejaVuSansCondensed-Bold.ttf", int(13 * sx * 0.85))
placed = []
for l in sorted(LOC.L, key=lambda l: -RAD[l["type"]]):
    x, y = l["pos"][0] * N, l["pos"][1] * N; r = RAD[l["type"]] * sx * 0.8; c = TC[l["type"]]
    ld.ellipse((x - r - 2, y - r - 2, x + r + 2, y + r + 2), outline=(16, 12, 8, 255), width=int(2 * sx))
    ld.ellipse((x - r, y - r, x + r, y + r), outline=c + (255,), width=int(2 * sx))
    ld.ellipse((x - 3, y - 3, x + 3, y + 3), fill=c + (255,))
    f = f1 if l["type"] in ("city", "town", "hub") else f2
    name = l["name"].replace("Port Sterling - ", ""); tw = ld.textlength(name, font=f); th = f.size + 2
    for (ox, oy) in ((r + 6, -th / 2), (-tw - r - 6, -th / 2), (-tw / 2, r + 4), (-tw / 2, -r - th - 4), (r + 6, 4), (-tw - r - 6, 4)):
        box_ = (x + ox, y + oy, x + ox + tw, y + oy + th)
        if box_[0] > 2 and box_[2] < N - 2 and all(box_[2] < q[0] or box_[0] > q[2] or box_[3] < q[1] or box_[1] > q[3] for q in placed): break
    placed.append(box_)
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (2, 2)):
        ld.text((box_[0] + dx, box_[1] + dy), name, font=f, fill=(14, 10, 6, 255))
    ld.text((box_[0], box_[1]), name, font=f, fill=c + (255,))
ft = ImageFont.truetype(FONT + "DejaVuSerif-Bold.ttf", int(40 * sx * 0.8))
t = LOC.REGION.upper(); tw = ld.textlength(t, font=ft)
ld.text((N - tw - 28, 22), t, font=ft, fill=(14, 10, 6, 255)); ld.text((N - tw - 30, 20), t, font=ft, fill=(232, 214, 170, 255))
lab.convert("RGB").save("/tmp/r3d/worldmap3d_labeled.png")
lab.convert("RGB").resize((1200, 1200), Image.LANCZOS).save("/tmp/r3d/worldmap3d_small.png")
log("done")
