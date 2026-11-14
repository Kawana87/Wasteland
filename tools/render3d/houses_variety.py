"""Random house generator test: eight houses from one function with different seeds —
footprints, siding, roofs, porches, chimneys, shutters, doors and damage all vary."""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import kit, props as P
from kit import house
import bpy
from PIL import Image
from post import fallout_grade

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/r3d"
sc = reset()
M = kit.materials()

FOOTPRINTS = [
    [(0, 0, 4, 3, 1)],
    [(0, 0, 5, 3, 1), (0, 3, 2, 2, 1)],                  # L
    [(0, 0, 5, 3, 1), (3, 3, 2, 2, 1)],                  # L mirrored
    [(0, 0, 4, 2, 1), (1, 2, 2, 2, 1)],                  # T
    [(0, 0, 3, 3, 2), (3, 1, 2, 2, 1)],                  # two-storey + wing
    [(0, 0, 4, 4, 2)],                                    # two-storey box
    [(0, 0, 6, 2, 1), (0, 2, 2, 2, 1), (4, 2, 2, 2, 1)],  # U
    [(0, 0, 3, 2, 1)],                                    # cottage
]
SIDING = ["siding_seafoam", "siding_cream", "siding_salmon", "siding_blue", "siding_mint", "stucco"]
ROOFS = ["sh_brown", "sh_slate", "sh_red", "sh_green"]


def random_house(ox, oy, rng):
    fp = rng.choice(FOOTPRINTS)
    w = max(p[0] + p[2] for p in fp)
    h = max(p[1] + p[3] for p in fp)
    wall = M[rng.choice(SIDING)] if rng.random() < 0.8 else {True: M["brick"], False: M["brick_y"]}
    roof = rng.choice(["gable", "gable", "hip", "flat"]) if wall is not M["stucco"] else rng.choice(["flat", "hip"])
    main = fp[0]
    side = rng.choice(["s", "e"])
    if side == "s":
        door = ("s", main[1] + main[3], main[0] + rng.uniform(1.0, main[2] - 1.0), rng.choice(["open", "closed", "locked", "boarded", "closed"]))
    else:
        door = ("e", main[0] + main[2], main[1] + rng.uniform(1.0, main[3] - 1.0), rng.choice(["open", "closed", "locked", "boarded"]))
    porch = None
    if side == "s" and rng.random() < 0.5 and main[2] >= 4:
        px = max(main[0] + 0.5, door[2] - 1.5)
        porch = (px, main[1] + main[3], min(px + 3.0, main[0] + main[2] - 0.2), main[1] + main[3] + 1.0)
    house(M, ox, oy, fp, wall, roof, rng.choice(ROOFS), door=door,
          shutters=rng.choice([None, M["frame"], M["trim"], M["door_paint"]]),
          chimney=(rng.uniform(0.5, w - 0.5), 0.5) if rng.random() < 0.5 else None,
          porch=porch, win_state=rng.choice(["glass", "glass", "broken", "boarded"]))
    # yard dressing
    if rng.random() < 0.6:
        P.wood_fence(ox - 0.4, oy + h + 1.6, 0, rng, n=rng.randint(2, 5))
    if rng.random() < 0.5:
        P.mailbox(ox + w + 0.6, oy + h + 0.8, 0, rng)
    P.scatter(ox - 1, oy - 1, ox + w + 1.5, oy + h + 2.2, 4, "suburb", rng, avoid=[(ox, oy, ox + w, oy + h + (1.0 if porch else 0))])


kit.terrain(-10, -10, 40, 30, kit.mat_terrain(), amp=0.12)
rng = random.Random(77)
k = 0
for j in range(2):
    for i in range(4):
        random_house(i * 8.5, j * 9.0, random.Random(100 + k * 13))
        k += 1
for t in range(10):
    P.tree(rng.uniform(-4, 34), rng.uniform(-4, 20), 0, random.Random(t * 7), kind=rng.choice(["dead", "dead", "sparse"]))
lights()
camera(15.5, 8.0, 1280, 720, 0.6)
sc.cycles.samples = 56
sc.render.filepath = os.path.join(OUT, "houses_variety_raw.png")
bpy.ops.render.render(write_still=True)
fallout_grade(Image.open(sc.render.filepath)).save(os.path.join(OUT, "houses_variety.png"))
print("variety done")
