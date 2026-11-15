"""Pre-rendered creatures for the game, 8 screen directions each (rows like player_r: row k faces screen
angle k*45deg). Columns: walk frames (2), crow: sit + 2 flap frames, brute: humanoid rig (8 columns like
the player sheet). Jointed rigs posed with simple forward kinematics.
python3 port_creatures.py [names]"""
import sys, os, math, random, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Matrix
from PIL import Image
from lib import reset, lights
import props as P
import character as CH
import port_common as PC

MAT = P.MAT


def quad(spec, ph):
    """Four-legged animal facing local +X. spec sizes in world units; ph = walk phase 0..1."""
    R = CH.Rig()
    L, Hh, W = spec["len"], spec["height"], spec["width"]
    leg = spec["leg"]
    body_z = leg + Hh * 0.45
    hide = spec["hide"]
    R.ball((0, 0, body_z), 1.0, hide, (L * 0.55, W * 0.5, Hh * 0.5))
    if spec.get("patches"):
        R.ball((-L * 0.1, W * 0.18, body_z + Hh * 0.18), 1.0, spec["patches"], (L * 0.22, W * 0.32, Hh * 0.3))
    a = math.sin(ph * 2 * math.pi) * spec.get("swing", 28)
    for (fx, sy, sgn) in ((L * 0.36, 1, 1), (L * 0.36, -1, -1), (-L * 0.36, 1, -1), (-L * 0.36, -1, 1)):
        hip = Vector((fx, sy * W * 0.32, body_z - Hh * 0.2))
        ang = a * sgn
        knee = hip + CH.sag(ang, leg * 0.55)
        foot = knee + CH.sag(ang * 0.4 - (12 if fx < 0 else -6), leg * 0.5)
        R.limb(hip, knee, spec["thick"], spec["thick"] * 0.8, hide)
        R.limb(knee, foot, spec["thick"] * 0.8, spec["thick"] * 0.6, spec.get("lower", hide))
    # neck + head
    hx = L * 0.55
    head = Vector((hx + spec["neck"], 0, body_z + spec["head_up"]))
    R.limb(Vector((hx * 0.7, 0, body_z + Hh * 0.15)), head, W * 0.22, W * 0.18, hide)
    R.ball(head, 1.0, spec.get("head_mat", hide), spec["head"])
    hs = spec["head"]
    R.ball(head + Vector((hs[0] * 0.9, 0, -hs[2] * 0.2)), 1.0, spec.get("snout", hide), (hs[0] * 0.5, hs[1] * 0.6, hs[2] * 0.55))
    for sy in (1, -1):
        R.ball(head + Vector((hs[0] * 0.55, sy * hs[1] * 0.55, hs[2] * 0.3)), hs[0] * 0.13, spec.get("eye", "flat:#141010:0.3"))
        if spec.get("ears"):
            R.limb(head + Vector((-hs[0] * 0.2, sy * hs[1] * 0.5, hs[2] * 0.6)), head + Vector((-hs[0] * 0.4, sy * hs[1] * 0.8, hs[2] * 1.5)),
                   hs[0] * 0.25, 0.005, spec.get("ear_mat", hide), 6)
        if spec.get("horns"):
            R.limb(head + Vector((0, sy * hs[1] * 0.6, hs[2] * 0.7)), head + Vector((hs[0] * 0.3, sy * hs[1] * 1.6, hs[2] * 1.4)),
                   0.025, 0.006, "flat:#e0d8c0:0.5", 6)
    if spec.get("tail"):
        t0 = Vector((-L * 0.55, 0, body_z + Hh * 0.1))
        sw = math.sin(ph * 2 * math.pi + 1) * 0.08
        R.limb(t0, t0 + Vector((-spec["tail"], sw, spec.get("tail_up", 0.05))), spec["thick"] * 0.6, 0.008, spec.get("tail_mat", hide), 6)
    return R


def shellback(ph):
    R = CH.Rig()
    shell = "rock:#5a6a4a:#3e4a34"
    R.ball((0, 0, 0.2), 1.0, shell, (0.42, 0.32, 0.24))
    R.ball((0, 0, 0.12), 1.0, "flat:#8a7a5a:0.8", (0.45, 0.34, 0.1))
    for k, fx in enumerate((0.25, 0.0, -0.25)):
        for sy in (1, -1):
            a = math.sin(ph * 2 * math.pi + k * 2.0 + (0 if sy > 0 else math.pi)) * 25
            hip = Vector((fx, sy * 0.28, 0.12))
            tip = hip + Vector((math.sin(math.radians(a)) * 0.12, sy * 0.16, -0.12))
            R.limb(hip, tip, 0.035, 0.02, "flat:#6a5a40:0.8", 6)
    hd = Vector((0.5, 0, 0.14))
    R.ball(hd, 1.0, "flat:#7a6a4a:0.7", (0.13, 0.12, 0.09))
    for sy in (1, -1):
        R.ball(hd + Vector((0.08, sy * 0.06, 0.04)), 0.022, "glow:#d8c040")
        R.limb(hd + Vector((0.09, sy * 0.04, -0.03)), hd + Vector((0.2, sy * 0.01, -0.05)), 0.02, 0.004, "flat:#e0d8c0:0.5", 5)
    return R


def crow(frame):
    R = CH.Rig()
    blk = "flat:#1e1c20:0.6"
    z = 0.14 if frame == 0 else 0.45
    R.ball((0, 0, z), 1.0, blk, (0.11, 0.06, 0.065))
    R.ball((0.1, 0, z + 0.05), 0.045, blk)
    R.limb(Vector((0.13, 0, z + 0.05)), Vector((0.2, 0, z + 0.035)), 0.016, 0.002, "flat:#d8b040:0.5", 5)
    R.limb(Vector((-0.08, 0, z)), Vector((-0.2, 0, z + 0.02)), 0.03, 0.01, blk, 5)
    if frame == 0:
        for sy in (1, -1):
            R.limb(Vector((0, sy * 0.02, z - 0.05)), Vector((0.01, sy * 0.02, 0.0)), 0.006, 0.006, "flat:#3a3028:0.6", 4)
    else:
        up = 0.16 if frame == 1 else -0.08
        for sy in (1, -1):
            R.box((0.0, sy * 0.13, z + up * 0.5), (0.1, 0.18, 0.012), blk,
                  Matrix.Translation(Vector((0, 0, 0))) @ Matrix.Rotation(sy * math.atan2(up, 0.14), 4, 'X'))
    return R


SPECS = {
    "dog": dict(len=0.52, height=0.22, width=0.18, leg=0.2, thick=0.035, neck=0.08, head_up=0.14, head=(0.09, 0.075, 0.075),
                hide="fab:#8a6040", snout="fab:#6a4630", ears=True, tail=0.18, tail_up=0.1, patches="fab:#c8a878"),
    "rat": dict(len=0.4, height=0.16, width=0.16, leg=0.06, thick=0.025, neck=0.05, head_up=0.03, head=(0.08, 0.06, 0.055),
                hide="flat:#9a7a6a:0.9", snout="flat:#c89a8a:0.7", tail=0.32, tail_up=0.0, tail_mat="flat:#c89a8a:0.7",
                eye="glow:#e04030", swing=35),
    "cattle": dict(len=1.0, height=0.45, width=0.42, leg=0.42, thick=0.06, neck=0.12, head_up=0.12, head=(0.16, 0.12, 0.13),
                   hide="fab:#8a7a5a", patches="fab:#4a3a2a", snout="flat:#c8a090:0.7", horns=True, tail=0.3, tail_up=-0.15, swing=18),
}
# cell, anchor, frames, target height (game px on screen) — sized against the 40px player
CELLS = {"dog": ((28, 22), (14, 18), 2, 17), "rat": ((20, 14), (10, 11), 2, 9), "cattle": ((64, 40), (32, 31), 2, 24),
         "shellback": ((44, 28), (22, 22), 2, 17), "crow": ((16, 16), (8, 13), 3, 8), "brute": ((44, 60), (22, 56), 8, 54)}


def render_sheet(name):
    (cw, ch), (ax, ay), ncol, target = CELLS[name]
    sheet = Image.new("RGBA", (cw * ncol, ch * 8), (0, 0, 0, 0))
    scale = None
    for row in range(8):
        for col in range(ncol):
            if name in SPECS:
                rig = quad(SPECS[name], col / ncol)
            elif name == "shellback":
                rig = shellback(col / ncol)
            elif name == "crow":
                rig = crow(col)
            else:   # brute: the humanoid rig, bulked up
                rig = CH.build(CH.poses()[col], "brute")
            rig.root.rotation_euler = (0, 0, CH.facing_yaw(row))
            if scale is None:
                # size once from the side view so every frame shares one scale
                PC.frame(cw, ch, ax, ay)
                rig.root.scale = (1, 1, 1)
                test = PC.shrink(PC.render_raw(samples=2), cw, ch)
                bb = test.getchannel("A").getbbox()
                hh = (bb[3] - bb[1]) if bb else ch
                scale = target / max(hh, 1)
            rig.root.scale = (scale, scale, scale)
            PC.frame(cw, ch, ax, ay)
            im = PC.render_raw(samples=16)
            sheet.paste(PC.shrink(im, cw, ch, bright=1.18, sat=1.1, outline=True, alpha_cut=90), (col * cw, row * ch))
            rig.clear()
    nm = name + "_r"
    sheet.save(os.path.join(PC.SPR, nm + ".png"))
    PC.set_anchor(nm, ax, ay)
    print("wrote", nm, flush=True)


def main(names):
    reset()
    lights()
    CH._CUBE = None
    CH.OUTFITS["brute"] = {"suit": "flat:#7a8a5a:0.8", "suit_d": "flat:#6a7a4a:0.8", "legs": "fab:#4a3e30", "skin": "flat:#7a8a5a:0.8",
                           "stripe_on": False, "backpack": False, "hair_style": "bald", "pads": "metal:#6a6458", "glove": "flat:#6a7a4a:0.8",
                           "vest": None, "boot": "flat:#3a3028:0.8", "eyes": "glow:#e8a030", "hunch": 8.0}
    for n in names:
        render_sheet(n)


if __name__ == "__main__":
    main(sys.argv[1:] or list(CELLS))
