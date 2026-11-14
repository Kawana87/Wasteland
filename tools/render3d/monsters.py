"""Creature lineup: every monster built from a joint skeleton wrapped with Blender's skin modifier,
rendered at game scale (64 px per tile) from two directions."""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import kit, props as P
from kit import skin_body, humanoid, mat_skin_rot, mat_hide, mat_two
import bpy
import fast as FAST
from PIL import Image, ImageDraw
from post import fallout_grade

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r3d"
sc = reset()
M = kit.materials()
R = random.Random(3)


def eyes(x, y, z, sep, r, mat, fwd=(0, 1)):
    for s in (-1, 1):
        sphere(x + s * sep, y + fwd[1] * r, z, r, mat)


def ghoul():
    rot = mat_skin_rot("ghoul_skin")
    rags = mat_two("rags", '#8a7a56', '#3e3a34', 0.47)
    body, head, wr = humanoid(rags, 1.0, hunch=0.12, arm_len=1.25, bulk=0.82, walk=0.5)
    sphere(*head, 0.09, rot, scale=(0.9, 1.0, 1.15))
    eyes(head[0], head[1] + 0.05, head[2] + 0.01, 0.035, 0.018, mat_flat("geye", '#e8d870', 0.3, emit='#c8b040', noise=0))
    for w in wr:
        for f in range(3):
            FAST.primitive_cone_add(vertices=4, radius1=0.012, depth=0.08, location=g2b(w[0] + (f - 1) * 0.02, w[1] + 0.02, w[2] - 0.06))
            bpy.context.active_object.data.materials.append(rot)


def brute():
    skin = mat_hide("brute_skin", '#7a8a56', '#6a7848', 0.5, 6.0, 0.6)
    leather = mat_flat("harness", '#4a3424', 0.6, noise=0.3)
    body, head, wr = humanoid(skin, 1.55, hunch=0.1, arm_len=1.1, bulk=1.7, walk=0.0)
    sphere(head[0], head[1] + 0.04, head[2] - 0.02, 0.15, skin, scale=(1.05, 1.0, 1.0))
    eyes(head[0], head[1] + 0.17, head[2], 0.05, 0.02, mat_flat("beye", '#e8c040', 0.3, noise=0))
    box(-0.25, -0.2, 0.72, 0.25, 0.2, 0.92, leather)          # belt / loincloth
    box(-0.12, 0.17, 0.4, 0.12, 0.2, 0.75, leather)
    for s in (-1, 1):                                          # shoulder straps + spiked pad
        o = box(-0.04, -0.2, 0.9, 0.04, 0.2, 1.55, leather); o.rotation_euler.y = math.radians(28 * s)
    box(-0.42, -0.14, 1.42, -0.2, 0.14, 1.56, M["metal"], bevel=0.03)
    # big pipe club in the right hand
    w = wr[1]
    o = cyl(w[0] + 0.05, w[1] + 0.05, w[2] - 0.55, w[2] + 0.1, 0.045, M["metal"], 8)
    o.rotation_euler.x = math.radians(-20)


def shellback():
    shell = mat_hide("shell", '#6a5a40', '#4a3a28', 0.45, 3.0, 0.4)
    belly = mat_flat("belly", '#a08a60', 0.6, noise=0.3)
    claw = mat_hide("claw", '#8a5a3a', '#6a3a24', 0.5, 5.0, 0.4)
    sphere(0, 0, 0.32, 0.5, shell, scale=(1.0, 1.2, 0.55))
    sphere(0, 0.05, 0.22, 0.45, belly, scale=(0.95, 1.1, 0.35))
    for k in range(6):   # segmented ridges on the shell
        a = -0.45 + k * 0.18
        o = cyl(0, a, 0.44 + 0.08 * math.cos(a * 2), 0.46 + 0.08 * math.cos(a * 2), 0.42 * math.cos(a * 1.2), shell, 12)
        o.scale = (1, 0.15, 1)
    for s in (-1, 1):
        for k in range(3):   # legs
            y = -0.3 + k * 0.3
            skin_body([(s * 0.4, y, 0.25), (s * 0.7, y + 0.05, 0.3), (s * 0.85, y + 0.1, 0.0)], [(0, 1), (1, 2)],
                      [(0.06, 0.06), (0.05, 0.05), (0.025, 0.025)], claw, levels=1)
        # big claws at the front
        skin_body([(s * 0.3, 0.45, 0.3), (s * 0.45, 0.75, 0.32), (s * 0.4, 0.95, 0.3)], [(0, 1), (1, 2)],
                  [(0.07, 0.07), (0.09, 0.07), (0.1, 0.06)], claw, levels=1)
        FAST.primitive_cone_add(vertices=6, radius1=0.06, depth=0.25, location=g2b(s * 0.37, 1.1, 0.33), rotation=(math.radians(-90), 0, 0))
        bpy.context.active_object.data.materials.append(claw)
        cyl(s * 0.12, 0.5, 0.35, 0.55, 0.015, claw, 6)           # eye stalks
        sphere(s * 0.12, 0.5, 0.56, 0.03, mat_flat("seye", '#e85a2a', 0.3, noise=0))


def mole_rat():
    skin = mat_skin_rot("rat_skin", '#b08a7a', '#8a6458', '#c09a8a')
    skin_body([(0, -0.35, 0.18), (0, -0.1, 0.22), (0, 0.15, 0.22), (0, 0.38, 0.17)], [(0, 1), (1, 2), (2, 3)],
              [(0.14, 0.13), (0.19, 0.17), (0.18, 0.16), (0.11, 0.1)], skin)
    sphere(0, 0.48, 0.16, 0.09, skin, scale=(1, 1.3, 0.9))
    for s in (-1, 1):
        FAST.primitive_cone_add(vertices=4, radius1=0.02, depth=0.08, location=g2b(s * 0.025, 0.6, 0.11), rotation=(math.radians(180), 0, 0))
        bpy.context.active_object.data.materials.append(mat_flat("teeth", '#e8e0c0', 0.4, noise=0))
        for (y, f) in ((-0.25, 1), (0.25, -1)):
            skin_body([(s * 0.12, y, 0.15), (s * 0.16, y + 0.03 * f, 0.0)], [(0, 1)], [(0.04, 0.04), (0.03, 0.03)], skin, levels=1)
    skin_body([(0, -0.48, 0.15), (0, -0.75, 0.08), (0.08, -0.95, 0.03)], [(0, 1), (1, 2)], [(0.03, 0.03), (0.02, 0.02), (0.01, 0.01)], skin, levels=1)


def hound():
    fur = mat_hide("hound_fur", '#6a5038', '#8a6a48', 0.55, 7.0, 0.85)
    J = [(0, -0.35, 0.5), (0, -0.05, 0.52), (0, 0.25, 0.55), (0, 0.42, 0.72), (0, 0.58, 0.72)]
    E = [(0, 1), (1, 2), (2, 3), (3, 4)]
    Rr = [(0.11, 0.12), (0.12, 0.13), (0.13, 0.15), (0.07, 0.07), (0.06, 0.07)]
    for s in (-1, 1):
        for (y, f) in ((-0.3, 0.06), (0.22, -0.06)):
            b = len(J)
            J += [(s * 0.08, y, 0.45), (s * 0.09, y + f, 0.22), (s * 0.09, y + f * 0.5, 0.02)]
            E += [(0 if y < 0 else 2, b), (b, b + 1), (b + 1, b + 2)]
            Rr += [(0.06, 0.06), (0.04, 0.04), (0.03, 0.035)]
    b = len(J)
    J += [(0, -0.48, 0.58), (0, -0.7, 0.66)]
    E += [(0, b), (b, b + 1)]
    Rr += [(0.03, 0.03), (0.015, 0.015)]
    skin_body(J, E, Rr, fur)
    sphere(0, 0.68, 0.72, 0.06, fur, scale=(0.9, 1.6, 0.8))                 # snout
    for s in (-1, 1):
        FAST.primitive_cone_add(vertices=4, radius1=0.03, depth=0.1, location=g2b(s * 0.05, 0.52, 0.82))
        bpy.context.active_object.data.materials.append(fur)
    eyes(0, 0.62, 0.77, 0.035, 0.012, mat_flat("heye", '#e8a040', 0.3, noise=0))
    for k in range(5):   # mangy bald patches
        sphere(R.uniform(-.08, .08), R.uniform(-.3, .2), 0.6, 0.05, mat_skin_rot("mange", '#a07a6a', '#7a5a4a', '#b08a7a'))


def roach():
    shell = mat_flat("roach", '#5a3a20', 0.25, noise=0.3)
    sphere(0, -0.1, 0.18, 0.28, shell, scale=(0.8, 1.4, 0.45))
    sphere(0, 0.32, 0.15, 0.12, shell, scale=(1.1, 0.9, 0.7))
    o = box(-0.005, -0.5, 0.25, 0.005, 0.25, 0.32, mat_flat("seam", '#2a1a10'))
    for s in (-1, 1):
        for k in range(3):
            y = -0.25 + k * 0.22
            skin_body([(s * 0.15, y, 0.15), (s * 0.4, y + 0.05 * (k - 1), 0.2), (s * 0.55, y + 0.12 * (k - 1), 0.0)], [(0, 1), (1, 2)],
                      [(0.025, 0.025), (0.02, 0.02), (0.01, 0.01)], shell, levels=1)
        skin_body([(s * 0.04, 0.42, 0.18), (s * 0.2, 0.75, 0.3), (s * 0.35, 1.0, 0.25)], [(0, 1), (1, 2)],
                  [(0.008, 0.008), (0.006, 0.006), (0.004, 0.004)], shell, levels=1)


def cattle():
    hide = mat_hide("hide", '#8a6a48', '#d8ccb0', 0.6, 2.2, 0.8)
    J = [(0, -0.55, 0.75), (0, -0.15, 0.78), (0, 0.3, 0.8)]
    E = [(0, 1), (1, 2)]
    Rr = [(0.24, 0.28), (0.27, 0.3), (0.25, 0.28)]
    for s in (-1, 1):
        for y in (-0.5, 0.25):
            b = len(J)
            J += [(s * 0.15, y, 0.6), (s * 0.15, y, 0.3), (s * 0.15, y, 0.02)]
            E += [(0 if y < 0 else 2, b), (b, b + 1), (b + 1, b + 2)]
            Rr += [(0.09, 0.09), (0.06, 0.06), (0.05, 0.05)]
        # two necks, two heads
        b = len(J)
        J += [(s * 0.16, 0.52, 0.98), (s * 0.3, 0.74, 0.95)]
        E += [(2, b), (b, b + 1)]
        Rr += [(0.09, 0.09), (0.11, 0.13)]
    skin_body(J, E, Rr, hide)
    for s in (-1, 1):
        sphere(s * 0.32, 0.86, 0.9, 0.08, mat_flat("muzzle", '#d8a890', 0.6, noise=0.2), scale=(1, 1.2, 0.8))
        for h in (-1, 1):
            FAST.primitive_cone_add(vertices=6, radius1=0.025, depth=0.16, location=g2b(s * 0.3 + h * 0.07, 0.72, 1.08), rotation=(0, math.radians(40 * h), 0))
            bpy.context.active_object.data.materials.append(mat_flat("horn", '#e0d8c0', 0.5, noise=0))
    skin_body([(0, -0.68, 0.85), (0, -0.88, 0.5)], [(0, 1)], [(0.035, 0.035), (0.02, 0.02)], hide, levels=1)


CRITTERS = [("ghoul", ghoul), ("brute", brute), ("shellback", shellback), ("mole rat", mole_rat), ("wild hound", hound),
            ("giant roach", roach), ("two-headed cattle", cattle)]

sc.render.film_transparent = True
lights()
CW, CH = 260, 240
cam = camera(0, 0, CW, CH, 0.75)
cam.data.ortho_scale /= 2.0          # shown at 2x zoom so the detail is visible
sc.cycles.samples = 40
cells = []
for name, fn in CRITTERS:
    row = []
    for ang in (210, 120):
        for ob in list(bpy.data.objects):
            if ob.type == 'MESH':
                bpy.data.objects.remove(ob, do_unlink=True)
        g = box(-3, -3, -0.05, 3, 3, 0.0, mat_flat("sc", '#808080'))
        g.is_shadow_catcher = True
        before = {o.name for o in bpy.data.objects}
        fn()
        for o in bpy.data.objects:
            if o.name not in before and o.type == 'MESH':
                rot_z(o, ang, (0, 0))
        sc.render.filepath = os.path.join(OUT, "_m.png")
        bpy.ops.render.render(write_still=True)
        row.append(Image.open(sc.render.filepath).copy())
    cells.append((name, row))
# reference figure for scale: the player (from the first test) is ~1.2 tiles tall
LH = 14
cols = 4
rows = (len(cells) + 1) // 2
sheet = Image.new("RGBA", (cols * CW, rows * (CH + LH)), (92, 80, 64, 255))
for i, (name, row) in enumerate(cells):
    x, y = (i % 2) * 2 * CW, (i // 2) * (CH + LH)
    sheet.alpha_composite(row[0], (x, y))
    sheet.alpha_composite(row[1], (x + CW, y))
out = fallout_grade(sheet.convert("RGB"))
d = ImageDraw.Draw(out)
for i, (name, row) in enumerate(cells):
    x, y = (i % 2) * 2 * CW, (i // 2) * (CH + LH)
    d.rectangle([x, y + CH, x + 2 * CW - 1, y + CH + LH - 1], fill=(28, 24, 20))
    d.text((x + 4, y + CH + 1), name + "   (2x zoom)", fill=(242, 214, 120))
out.save(os.path.join(OUT, "monsters.png"))
print("monsters done")
