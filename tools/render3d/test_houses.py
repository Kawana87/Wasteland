"""Render test 2: a street of varied, closed houses with visible doors in different states."""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import kit
from kit import house, box, R
import bpy
from bpy_extras.object_utils import world_to_camera_view
from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r3d"
os.makedirs(OUT, exist_ok=True)
sc = reset()
M = kit.materials()
W, H = 1152, 648

# ground, street running along x between two rows of houses
box(-20, -20, -0.1, 40, 40, 0.0, M["dirt"], name="ground")
box(-20, 7.0, -0.02, 40, 9.4, 0.006, M["asphalt"], name="road")
box(-20, 6.2, 0.0, 40, 7.0, 0.07, M["conc"], bevel=0.02)
box(-20, 9.4, 0.0, 40, 10.2, 0.07, M["conc"], bevel=0.02)

labels = []   # (game x, y, z, text)

# 1. L-shaped ranch: gable cross roof, chimney, porch, door OPEN
house(M, 0, 1, [(0, 0, 5, 3, 1), (0, 3, 2, 2, 1)], M["siding_seafoam"], "gable", "sh_brown",
      door=("s", 3, 3.5, "open"), shutters=M["frame"], chimney=(1.0, 0.6), porch=(2.0, 3.0, 5.0, 4.0))
labels.append((3.5, 4.3, 1.0, "open"))
# 2. two-storey house with a one-storey wing: hip roof, door LOCKED
house(M, 7, 0, [(0, 0, 4, 4, 2), (4, 1, 2, 3, 1)], M["siding_cream"], "hip", "sh_slate",
      door=("s", 4, 2.0, "locked"), shutters=M["door_paint"])
labels.append((9.0, 4.3, 1.0, "locked"))
# 3. U-shaped brick duplex with flat roof, two doors: closed + boarded
house(M, 15, 0, [(0, 0, 6, 2, 1), (0, 2, 2, 3, 1), (4, 2, 2, 3, 1)], {True: M["brick"], False: M["brick_y"]}, "flat",
      door=("s", 2, 3.0, "closed"), extra_doors=[("e", 2, 3.5, "boarded")], win_state="boarded")
labels.append((18.0, 2.3, 1.0, "closed"))
labels.append((17.2, 3.5, 1.0, "boarded"))
# 4. tin shack with a shed roof, door BOARDED (sealed, can't enter)
house(M, 1, 11, [(0, 0, 3, 2, 1)], {True: M["tin"], False: M["tin_y"]}, "shed", door=("e", 3, 1.0, "boarded"))
labels.append((4.1, 12.0, 1.0, "sealed"))
# 5. ruined house: half the roof caved in, door torn off
house(M, 7, 11, [(0, 0, 5, 3, 1)], M["siding_salmon"], "gable", "sh_red", door=("e", 5, 1.5, "broken"),
      ruined=True, win_state="broken")
labels.append((12.1, 12.5, 1.0, "broken in"))
# 6. T-shaped cottage with a steep gable and shutters, door CLOSED
house(M, 15, 11, [(0, 0, 4, 2, 1), (1, 2, 2, 2, 1)], M["siding_blue"], "gable", "sh_green",
      door=("e", 3, 3.0, "closed"), shutters=M["trim"], chimney=(3.4, 0.5))
labels.append((18.1, 14.0, 1.0, "closed"))

# a few street props for scale
def barrel(x, y, m):
    kit.cyl(x, y, 0, 0.85, 0.28, m, 20)
for (x, y) in ((5.6, 5.2), (13.4, 5.4), (6.0, 10.6)):
    barrel(x, y, M["barrel"])
for k in range(40):
    x, y = R.uniform(-4, 24), R.uniform(-2, 16)
    s = R.uniform(0.04, 0.14)
    ob = box(x - s, y - s, 0, x + s, y + s, R.uniform(0.03, 0.15), R.choice([M["rubble"], M["rubble"], M["metal"]]), bevel=0.01, name="junk")
    ob.rotation_euler = (R.uniform(-.4, .4), R.uniform(-.4, .4), R.uniform(0, 6.3))

lights()
cam = camera(10.0, 7.5, W, H, 0.8)
sc.cycles.samples = 64
sc.render.filepath = os.path.join(OUT, "houses_raw.png")
bpy.ops.render.render(write_still=True)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from post import fallout_grade
im = fallout_grade(Image.open(sc.render.filepath))
im.save(os.path.join(OUT, "houses.png"))
# annotated copy: door states
ann = im.copy()
d = ImageDraw.Draw(ann)
for (x, y, z, t) in labels:
    v = world_to_camera_view(sc, cam, g2b(x, y, z))
    px, py = v.x * W, (1 - v.y) * H
    tw = 6 * len(t) + 6
    d.rectangle([px - tw / 2, py - 26, px + tw / 2, py - 14], fill=(20, 18, 16))
    d.text((px - tw / 2 + 3, py - 26), t, fill=(242, 214, 120))
    d.line([px, py - 14, px, py - 4], fill=(242, 214, 120))
ann.save(os.path.join(OUT, "houses_labeled.png"))
print("houses done")
