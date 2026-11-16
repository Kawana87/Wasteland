"""Inventory icons: one small 3D model per item, rendered with the game camera to assets/sprites/icon_<id>.png
(64x64, transparent). Models are built along +x, then turned so their long side reads left-to-right on screen.
python3 icons.py [ids...]"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from lib import reset, lights, box, cyl, sphere, rot_z, mat_flat
import lib
import port_common as PC

M = {}
def m(col, rough=0.6, metal=0.0, noise=0.12):
    k = (col, rough, metal)
    if k not in M:
        M[k] = mat_flat("i%d" % len(M), col, rough, metal=metal, noise=noise)
    return M[k]

HX = (0, math.pi / 2, 0)            # cylinder lying along game x
HY = (math.pi / 2, 0, 0)            # cylinder lying along game y
STEEL, DARK, RUST, WOOD, BRASS = "#8a8a84", "#2e2c2a", "#8a5a3a", "#7a5032", "#c8a040"


def hcyl(x0, x1, y, z, r, mat, v=12):
    return cyl((x0 + x1) / 2, y, z - (x1 - x0) / 2, z + (x1 - x0) / 2, r, mat, v, rot=HX)


def pipe_pistol():
    hcyl(-0.35, 0.45, 0, 0.42, 0.06, m(RUST, 0.7, 0.3))
    box(-0.4, -0.06, 0.32, -0.05, 0.06, 0.5, m(STEEL, 0.5, 0.5))
    box(-0.38, -0.05, 0.0, -0.18, 0.05, 0.34, m(WOOD, 0.8))
    box(-0.15, -0.015, 0.2, -0.05, 0.015, 0.32, m(DARK, 0.5, 0.5))


def pistol_10mm():
    box(-0.4, -0.06, 0.3, 0.42, 0.06, 0.5, m("#5a5a58", 0.4, 0.7))
    hcyl(0.42, 0.5, 0, 0.42, 0.03, m(DARK, 0.4, 0.6))
    box(-0.36, -0.055, -0.05, -0.12, 0.055, 0.32, m("#3a3634", 0.7))
    box(-0.1, -0.012, 0.18, 0.08, 0.012, 0.22, m(DARK, 0.4, 0.6)); box(0.06, -0.012, 0.18, 0.09, 0.012, 0.3, m(DARK, 0.4, 0.6))


def smg():
    box(-0.45, -0.07, 0.28, 0.35, 0.07, 0.48, m("#4a4a46", 0.5, 0.6))
    hcyl(0.35, 0.65, 0, 0.4, 0.04, m(DARK, 0.4, 0.6))
    box(0.0, -0.05, -0.12, 0.12, 0.05, 0.28, m(DARK, 0.5, 0.6))
    box(-0.4, -0.05, 0.05, -0.28, 0.05, 0.3, m("#3a3634", 0.7))
    for z in (0.3, 0.44):
        hcyl(-0.85, -0.45, 0, z, 0.018, m(STEEL, 0.4, 0.7), 8)
    box(-0.88, -0.03, 0.28, -0.82, 0.03, 0.46, m(STEEL, 0.4, 0.7))


def shotgun():
    for y in (-0.04, 0.04):
        hcyl(-0.1, 0.65, y, 0.42, 0.04, m("#3a3a38", 0.4, 0.7))
    box(-0.25, -0.07, 0.34, 0.0, 0.07, 0.48, m("#4a4a46", 0.5, 0.6))
    box(-0.75, -0.06, 0.22, -0.22, 0.06, 0.42, m(WOOD, 0.8))
    box(-0.78, -0.065, 0.1, -0.6, 0.065, 0.36, m(WOOD, 0.8))


def rifle():
    hcyl(0.0, 0.95, 0, 0.45, 0.03, m("#3a3a38", 0.4, 0.7))
    box(-0.25, -0.06, 0.36, 0.25, 0.06, 0.5, m("#4a4a46", 0.5, 0.6))
    box(-0.95, -0.06, 0.24, -0.2, 0.06, 0.44, m(WOOD, 0.8))
    box(-0.95, -0.065, 0.1, -0.75, 0.065, 0.38, m(WOOD, 0.8))
    hcyl(-0.25, 0.25, 0, 0.62, 0.045, m(DARK, 0.3, 0.6))
    box(-0.05, -0.02, 0.5, 0.05, 0.02, 0.6, m(DARK, 0.4, 0.6))


def pipe():
    hcyl(-0.7, 0.7, 0, 0.1, 0.06, m(STEEL, 0.5, 0.6))
    hcyl(0.62, 0.74, 0, 0.1, 0.08, m("#6a6a64", 0.5, 0.6))
    hcyl(-0.7, -0.35, 0, 0.1, 0.065, m("#3a3028", 0.9))


def machete():
    box(-0.1, -0.012, 0.05, 0.8, 0.012, 0.22, m("#b0b0a8", 0.25, 0.8))
    box(0.55, -0.013, 0.05, 0.8, 0.013, 0.12, m(RUST, 0.6, 0.4))
    box(-0.5, -0.04, 0.08, -0.1, 0.04, 0.2, m("#3a2a1e", 0.8))


def spiked_bat():
    o = cyl(0.05, 0, -0.6, 0.6, 0.075, m(WOOD, 0.8), 12, rot=HX)
    o.scale = (1.0, 1.0, 1.0)
    hcyl(0.2, 0.68, 0, 0.0, 0.1, m(WOOD, 0.8))
    for k in range(10):
        a = k * 2.4
        x = 0.25 + (k % 5) * 0.09
        box(x - 0.01, -0.01 + math.cos(a) * 0.1, math.sin(a) * 0.1 - 0.01, x + 0.01, 0.01 + math.cos(a) * 0.17, math.sin(a) * 0.17 + 0.01, m(STEEL, 0.4, 0.7))


def cap():
    sphere(0, 0, 0.0, 0.32, m("#6a4a30", 0.8), scale=(1.0, 1.0, 0.7))
    box(0.15, -0.3, 0.0, 0.55, 0.3, 0.04, m("#5a3e28", 0.8))
    box(-0.4, -0.4, -0.3, 0.6, 0.4, 0.0, m("#000000"))


def road_helmet():
    sphere(0, 0, 0.0, 0.36, m("#b04030", 0.4), scale=(1.0, 1.0, 0.85))
    box(0.22, -0.28, -0.05, 0.4, 0.28, 0.12, m("#2a2a28", 0.2, 0.3))
    box(-0.45, -0.45, -0.4, 0.45, 0.45, -0.02, m("#000000"))


def _torso(col, rough=0.7, metal=0.0):
    box(-0.32, -0.08, 0.0, 0.32, 0.08, 0.7, m(col, rough, metal))
    for s in (-1, 1):
        box(s * 0.32 - 0.12 * (s < 0), -0.07, 0.25, s * 0.32 + 0.12 * (s > 0), 0.07, 0.68, m(col, rough, metal))


def jacket():
    _torso("#5a3a26", 0.6)
    box(-0.02, 0.08, 0.05, 0.02, 0.09, 0.68, m("#8a8a84", 0.4, 0.6))
    box(-0.2, 0.08, 0.6, 0.2, 0.1, 0.72, m("#4a2e1e", 0.6))


def raider_plates():
    _torso("#5a4a3a", 0.8)
    for (x0, z0) in ((-0.28, 0.4), (0.02, 0.4), (-0.26, 0.08), (0.04, 0.1)):
        box(x0, 0.08, z0, x0 + 0.24, 0.12, z0 + 0.26, m(RUST, 0.5, 0.5))
    for s in (-1, 1):
        box(s * 0.36 - 0.1, -0.1, 0.55, s * 0.36 + 0.1, 0.1, 0.75, m("#7a7468", 0.5, 0.6))


def combat_vest():
    box(-0.3, -0.1, 0.0, 0.3, 0.1, 0.66, m("#4e5a3e", 0.8))
    for k in range(3):
        box(-0.27 + k * 0.19, 0.1, 0.12, -0.12 + k * 0.19, 0.16, 0.34, m("#3e4a30", 0.8))
    box(-0.3, 0.1, 0.48, 0.3, 0.13, 0.54, m("#2e3624", 0.8))


def _rounds(n, r, h, case, tip, spacing=None):
    sp = spacing or r * 2.3
    for k in range(n):
        x = (k - (n - 1) / 2) * sp
        cyl(x, 0, 0, h, r, m(case, 0.3, 0.8), 10)
        sphere(x, 0, h, r * 0.95, m(tip, 0.4, 0.6), scale=(1, 1, 1.4))


def ammo_pistol():
    box(-0.42, -0.25, 0, 0.42, 0.25, 0.18, m("#6a5a3a", 0.8))
    box(-0.43, -0.26, 0.18, 0.43, 0.26, 0.2, m("#8a7a4a", 0.8))
    _rounds(4, 0.05, 0.2, BRASS, "#9a7040")
    for o in bpy.context.scene.objects:
        pass


def ammo_shell():
    for k in range(4):
        x = (k - 1.5) * 0.18
        cyl(x, 0, 0, 0.36, 0.07, m("#b03028", 0.5), 12)
        cyl(x, 0, 0, 0.09, 0.075, m(BRASS, 0.3, 0.8), 12)


def ammo_rifle():
    _rounds(5, 0.045, 0.5, BRASS, "#8a5a30", 0.13)


def medkit():
    box(-0.4, -0.3, 0, 0.4, 0.3, 0.32, m("#d8d4c8", 0.5))
    box(-0.06, 0.3, 0.06, 0.06, 0.31, 0.27, m("#c02020", 0.5)); box(-0.17, 0.3, 0.12, 0.17, 0.31, 0.21, m("#c02020", 0.5))
    box(-0.06, -0.05, 0.32, 0.06, 0.05, 0.33, m("#c02020", 0.5)); box(-0.17, -0.02, 0.32, 0.17, 0.02, 0.33, m("#c02020", 0.5))
    box(-0.12, -0.04, 0.32, 0.12, 0.04, 0.4, m("#5a5a54", 0.5, 0.5))


def food():
    cyl(0, 0, 0, 0.55, 0.22, m("#b8b4a8", 0.3, 0.8), 20)
    cyl(0, 0, 0.1, 0.45, 0.225, m("#c86a30", 0.6), 20)
    cyl(0, 0, 0.2, 0.32, 0.228, m("#e8d8a0", 0.6), 20)


def lockpick():
    box(-0.5, -0.015, 0.0, 0.4, 0.015, 0.03, m(STEEL, 0.3, 0.8))
    box(0.36, -0.015, 0.0, 0.4, 0.015, 0.1, m(STEEL, 0.3, 0.8))
    box(-0.45, 0.06, 0.0, 0.35, 0.09, 0.03, m("#9a9a92", 0.3, 0.8))
    box(-0.6, -0.04, -0.01, -0.4, 0.13, 0.05, m("#3a3028", 0.8))


def scrap():
    rng = random.Random(4)
    for k in range(6):
        x, y = rng.uniform(-0.3, 0.3), rng.uniform(-0.25, 0.25)
        o = box(x - 0.18, y - 0.08, k * 0.04, x + 0.18, y + 0.08, k * 0.04 + 0.04, m(rng.choice([RUST, STEEL, "#6e7a74"]), 0.6, 0.5))
        rot_z(o, rng.uniform(0, 180), (x, y))
    hcyl(-0.35, 0.3, 0.15, 0.3, 0.04, m(STEEL, 0.5, 0.6))


def cloth():
    for k, c in enumerate(("#8a6a50", "#6a7a8a", "#9a8a6a")):
        box(-0.32 + k * 0.03, -0.24, k * 0.12, 0.32 + k * 0.03, 0.24, k * 0.12 + 0.11, m(c, 0.9))
    box(-0.02, -0.25, 0.0, 0.03, 0.25, 0.37, m("#c8b88a", 0.9))


def wood():
    for k in range(3):
        for j in range(3 - k):
            hcyl(-0.45, 0.45, (j - (2 - k) / 2) * 0.17, 0.08 + k * 0.15, 0.08, m(WOOD, 0.85))


def caps():
    for k in range(5):
        x, y = (k % 3 - 1) * 0.22, (k // 3) * 0.2 - 0.1
        cyl(x, y, k * 0.01, k * 0.01 + 0.05, 0.1, m(["#c02020", "#c8a040", "#2a6ab0"][k % 3], 0.4, 0.6), 16)


def water():
    for k, (x, y) in enumerate(((-0.2, -0.1), (0.15, -0.12), (0.0, 0.18))):
        cyl(x, y, 0, 0.42, 0.13, m("#7ab0c0", 0.15, 0.0, 0.05), 18)
        cyl(x, y, 0.42, 0.5, 0.06, m("#4a8aa0", 0.3), 12)
        cyl(x, y, 0.5, 0.56, 0.065, m("#2a5a8a", 0.5), 12)
        cyl(x, y, 0.12, 0.28, 0.135, m("#e8e0c8", 0.6), 18)


def salt():
    sphere(0, 0, 0.2, 0.34, m("#d8d0bc", 0.95))
    cyl(0, 0, 0.0, 0.3, 0.33, m("#c8bea4", 0.95), 16)
    cyl(0, 0, 0.3, 0.44, 0.12, m("#a89a7a", 0.9), 12)
    box(-0.1, -0.34, 0.08, 0.1, -0.33, 0.22, m("#8a3a2a", 0.8))


def glass():
    rng = random.Random(7)
    for k in range(7):
        x, y = rng.uniform(-0.3, 0.3), rng.uniform(-0.25, 0.25)
        h = rng.uniform(0.15, 0.4)
        o = box(x - 0.08, y - 0.06, 0, x + 0.08, y + 0.06, h, m(rng.choice(["#4ac0a0", "#3a9a8a", "#6ad0b0"]), 0.05, 0.0, 0.02))
        rot_z(o, rng.uniform(0, 90), (x, y))


def copper():
    for k in range(5):
        cyl(0, 0, k * 0.07, k * 0.07 + 0.06, 0.32 - (k % 2) * 0.02, m("#c87a40", 0.35, 0.9), 24)
    cyl(0, 0, 0, 0.36, 0.14, m("#3a2a20", 0.8), 16)


def fuel():
    box(-0.32, -0.12, 0, 0.32, 0.12, 0.55, m("#b03a28", 0.5, 0.3))
    box(-0.2, -0.04, 0.55, 0.05, 0.04, 0.66, m("#2e2c2a", 0.5, 0.5))
    cyl(0.2, 0, 0.55, 0.68, 0.05, m("#c8a040", 0.4, 0.8), 10)
    box(-0.33, -0.13, 0.22, 0.33, 0.13, 0.26, m("#7a2418", 0.6))


def tech():
    box(-0.4, -0.3, 0, 0.4, 0.3, 0.05, m("#2a6a3a", 0.6))
    for k in range(6):
        x, y = -0.25 + (k % 3) * 0.25, -0.12 + (k // 3) * 0.24
        box(x - 0.06, y - 0.05, 0.05, x + 0.06, y + 0.05, 0.12, m("#2e2c2a", 0.5, 0.4))
    for k in range(3):
        cyl(-0.25 + k * 0.25, 0.0, 0.05, 0.3, 0.05, m("#d8c8a0", 0.1, 0.0, 0.02), 10)


def produce():
    cyl(0, 0, 0, 0.22, 0.36, m("#8a6a3a", 0.9), 18)
    rng = random.Random(3)
    for k in range(7):
        x, y = rng.uniform(-0.22, 0.22), rng.uniform(-0.22, 0.22)
        sphere(x, y, 0.28, 0.1, m(rng.choice(["#c03a2a", "#d89a30", "#6a9a3a"]), 0.6))


ICONS = {"water": water, "salt": salt, "glass": glass, "copper": copper, "fuel": fuel, "tech": tech, "produce": produce,
         "pipe_pistol": pipe_pistol, "pistol_10mm": pistol_10mm, "smg": smg, "shotgun": shotgun, "rifle": rifle,
         "pipe": pipe, "machete": machete, "spiked_bat": spiked_bat, "cap": cap, "road_helmet": road_helmet,
         "jacket": jacket, "raider_plates": raider_plates, "combat_vest": combat_vest, "ammo_pistol": ammo_pistol,
         "ammo_shell": ammo_shell, "ammo_rifle": ammo_rifle, "medkit": medkit, "food": food, "lockpick": lockpick,
         "scrap": scrap, "cloth": cloth, "wood": wood, "caps": caps}


def main(ids):
    reset(); lights()
    for k in ids:
        n0 = len(lib.REG)
        ICONS[k]()
        obs = [o for o in lib.REG[n0:] if o.name]
        flat = k in ("cap", "road_helmet")
        for o in obs:
            if flat and o.data.materials and o.data.materials[0].name.endswith("i0") is False and any(mm.name == m("#000000").name for mm in o.data.materials):
                o.hide_render = True
            rot_z(o, -45, (0, 0))
        PC.sprite("icon_" + k, 64, 64, 32, 40, samples=24, bright=1.15, outline=True)
        PC.clear(obs)
        print("icon", k, flush=True)


if __name__ == "__main__":
    main(sys.argv[1:] or list(ICONS))
