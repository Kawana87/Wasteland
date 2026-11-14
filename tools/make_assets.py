"""Generates all placeholder pixel-art sprites for Wasteland.

Run from the repo root:   python3 tools/make_assets.py
Needs Pillow (pip install pillow). Output goes to assets/sprites/.
Everything here is placeholder art meant to be swapped for hand-made sprites later;
keep file names and sizes the same and the game will pick the new art up.
"""
import os, sys, math, random
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pixlib as L

OUT = os.path.join(HERE, "..", "assets", "sprites")
os.makedirs(OUT, exist_ok=True)
random.seed(1234)
KEY = (255, 0, 255)

def hx(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
def shade(c, f): return tuple(max(0, min(255, int(v * f))) for v in c)
def save(img, name): img.save(os.path.join(OUT, name + ".png"))

def keyed(w, h):
    """Point pixlib at a fresh magenta canvas so its helpers draw into it."""
    L.img = Image.new("RGB", (w, h), KEY); L.px = L.img.load(); L.dr = ImageDraw.Draw(L.img)
    L.W, L.H = w, h
    L.shadow = lambda *a, **k: None
def unkey():
    im = L.img.convert("RGBA"); d = im.load()
    for y in range(im.height):
        for x in range(im.width):
            if d[x, y][:3] == KEY: d[x, y] = (0, 0, 0, 0)
    return im

def rows_img(rows, pal, w=None, h=None, ox=0, oy=0, flip=False):
    w = w or len(rows[0]); h = h or len(rows)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = im.load()
    for j, r in enumerate(rows):
        if flip: r = r[::-1]
        for i, ch in enumerate(r):
            if ch != '.': d[ox + i, oy + j] = hx(pal[ch]) + (255,)
    return im

def sheet(frames):
    w = sum(f.width for f in frames); h = max(f.height for f in frames)
    s = Image.new("RGBA", (w, h), (0, 0, 0, 0)); x = 0
    for f in frames: s.paste(f, (x, 0)); x += f.width
    return s

# ---------------------------------------------------------------- characters
HUMAN = ["....oooo....", "...oHHhho...", "..oHhhhhho..", "..ohssssSo..", "..osesseSo..", "..ossssSSo..",
         "...oSSSSo...", "..ookSSkoo..", ".okJJjjjkBo.", ".oJjjjjjkBno", "oJjjjjjjkBno", "osJjjjjkkBno",
         "oSojjjjkkono", ".oopppppPoo.", "..opppPPPo..", "..oppPoPPo..", "..oppPoPPo..", "..oPPo.oPo..",
         ".obbbo.obbo.", ".ooooo.oooo."]
WALK_LEGS = ["..oppPoPPo..", "..oppPooPo..", "..obbo.oPo..", "..ooo..obbo.", ".......oooo."]
def back_of(rows):
    r = list(rows); r[3] = "..ohhhhhho.."; r[4] = "..oHhhhhho.."; r[5] = "..ohhhhhHo.."; return r
def crouch_of(rows):
    return rows[:13] + [".opppppPPo..", ".obbbobbbo..", ".oooooooo..."]
def human_sheet(pal, extra=None):
    front = HUMAN; back = back_of(HUMAN)
    fw = front[:15] + WALK_LEGS; bw = back[:15] + WALK_LEGS
    frames = []
    for rows, oy in ((front, 4), (fw, 4), (back, 4), (bw, 4), (crouch_of(front), 8), (crouch_of(back), 8)):
        f = rows_img(rows, pal, 16, 24, 2, oy)
        if extra: extra(f, oy)
        frames.append(f)
    return sheet(frames)

PL = {'o': "#1e1622", 'h': "#4a2c1e", 'H': "#6e4430", 's': "#e0b08a", 'S': "#b88060", 'e': "#1e1622",
      'j': "#5a6a4a", 'J': "#7a8a5a", 'k': "#3e4a34", 'p': "#4a4a5a", 'P': "#34343e", 'b': "#3a2a20", 'B': "#8a6a3a", 'n': "#6a4a2a"}
save(human_sheet(PL), "player")
SV = dict(PL, j="#8a4a3a", J="#a85a48", k="#6a3a2a", h="#2a1a12", H="#3a2a1e", s="#c08a60", S="#9a6a48", B="#5a6a7a", n="#3a4a5a")
save(human_sheet(SV), "survivor")
RD = dict(PL, j="#5a3a2a", J="#7a5038", k="#3a2418", h="#2a1a12", H="#3a2418", s="#d8a07a", S="#b07858", p="#4a4038", P="#34302a", B="#3a3a3a", n="#2a2a2a")
def raider_extra(f, oy):
    d = f.load()
    for (x, y) in ((7, oy - 2), (8, oy - 2), (7, oy - 1), (8, oy - 1), (7, oy - 3)):   # mohawk
        d[x, y] = hx("#c83a2a") + (255,)
    for x in range(5, 11): d[x, oy + 5] = hx("#3a3a3a") + (255,)                       # bandana mask
    for (x, y) in ((2, oy + 8), (13, oy + 8)): d[x, y] = hx("#c0c0b0") + (255,)        # shoulder spikes
save(human_sheet(RD, raider_extra), "raider")

HD = {'o': "#1e1622", 'p': "#b07a6a", 'P': "#8a5a4a", 'r': "#6a3a3a", 'R': "#e0d040", 'w': "#e8e0c8"}
HOUND = ["............oo..", "...........oPPo.", "o.........oPpPRo", "Po..ooooooopPppo", ".oPppppppppppwwo",
         "..oprprprpppppo.", "..oPPPPPPPPPPo..", "..oPo.oPo.oPo...", "..oo..oo..oo...."]
HOUND2 = HOUND[:7] + ["...oPooPo.oPo...", "...oo.oo..oo...."]
save(sheet([rows_img(HOUND, HD, 16, 10, 0, 1), rows_img(HOUND2, HD, 16, 10, 0, 1)]), "hound")
RP = {'o': "#1e1622", 'g': "#6a5a4a", 'G': "#4a3e34", 'e': "#e04a3a", 't': "#c08a8a"}
RAT = [".....oo.", ".oooogeo", "ogggggGo", "tooGGoo.", ".o.o.o.."]
RAT2 = RAT[:4] + ["..o.o.o."]
save(sheet([rows_img(RAT, RP, 8, 6, 0, 1), rows_img(RAT2, RP, 8, 6, 0, 1)]), "rat")
DP = {'o': "#1e1622", 'd': "#a0703a", 'D': "#7a5028", 'l': "#c09060", 'e': "#1e1622"}
DOG = ["..........oo..", ".........oDdo.", "o........odedo", "do.ooooooodddo", ".odddddddddoo.",
       "..oldddddDDo..", "..oDDDDDDDDo..", "..odo.odo.odo.", "..ooo.ooo.ooo."]
DOG2 = DOG[:7] + ["...odoodo.odo.", "...ooooo..ooo."]
save(sheet([rows_img(DOG, DP, 14, 10, 0, 1), rows_img(DOG2, DP, 14, 10, 0, 1)]), "dog")

# awareness icons
save(rows_img(["oooo", "o..o", "..o.", ".o..", "....", ".o.."], {'o': "#f2c36b"}), "icon_suspicious")
save(rows_img(["oo", "oo", "oo", "oo", "..", "oo"], {'o': "#e04a3a"}), "icon_alert")

# ---------------------------------------------------------------- trees, cars
for i in range(3):
    keyed(24, 38); L.OX, L.OY = 12, 36; random.seed(70 + i); L.tree(0, 0, 0, 0.9 + i * 0.1); save(unkey(), f"tree{i}")
keyed(24, 38); L.OX, L.OY = 12, 36; random.seed(99); L.tree(0, 0, 0, dead=True); save(unkey(), "tree_dead")
keyed(14, 10); L.OX, L.OY = 7, 6
L.box(-.18, -.18, .36, .36, 4, "#c8a070", "#7a5a3a", "#5e4430"); save(unkey(), "stump")

bodies = {'teal': ("#4a7470", "#5a8680", "#5a8a82", "#6e9e94", "#86b2a6"),
          'red': ("#7a4a3a", "#8a5a46", "#8a5444", "#9e6450", "#b47a62"),
          'yellow': ("#8a7a4a", "#9a8a56", "#9a8a54", "#aa9a62", "#c0b07a"), 'burned': None}
for name, body in bodies.items():
    for axis in ('x', 'y'):
        keyed(80, 60); L.OX, L.OY = 40, 30
        Ln, Wd = 2.6, 1.05
        cx, cy = (-Ln / 2, -Wd / 2) if axis == 'x' else (-Wd / 2, -Ln / 2)
        random.seed(hash(name + axis) % 1000)
        if body: L.car(cx, cy, 0, axis, body=body)
        else: L.car(cx, cy, 0, axis, burned=True)
        save(unkey(), f"car_{name}_{axis}")      # anchor (40,30) = car ground centre

# ---------------------------------------------------------------- props
def block_sprite(w, h, top, left, right, name, size, anchor):
    keyed(*size); L.OX, L.OY = anchor
    L.box(-w / 2, -w / 2, w, w, h, top, left, right); save(unkey(), name)
block_sprite(.38, 6, "#c99a4a", "#9a6a30", "#7a5020", "crate", (16, 16), (8, 12))
block_sprite(.38, 6, "#3b2a1e", "#9a6a30", "#7a5020", "crate_open", (16, 16), (8, 12))
block_sprite(.42, 7, "#a05040", "#6a3024", "#7a3a2c", "cache", (16, 18), (8, 13))
block_sprite(.42, 7, "#3b2a1e", "#6a3024", "#7a3a2c", "cache_open", (16, 18), (8, 13))
bag = Image.new("RGBA", (8, 8), (0, 0, 0, 0)); bd = ImageDraw.Draw(bag)
bd.rectangle([1, 2, 6, 7], fill=hx("#5a4a32"), outline=hx("#1e1622")); bd.rectangle([2, 1, 5, 2], fill=hx("#7a6a4a")); save(bag, "bag")
block_sprite(.8, 12, "#8a9a5a", "#5e6a3a", "#7a8a4a", "tent", (30, 30), (15, 24))
block_sprite(.55, 7, "#a07a4a", "#6a4a2a", "#8a6a3a", "workbench", (22, 20), (11, 15))
block_sprite(.32, 8, "#4a6a8a", "#2e4a6a", "#3a5a7a", "barrel", (14, 16), (7, 12))
keyed(24, 52); L.OX, L.OY = 12, 48
L.box(-.22, -.22, .44, .44, 34, "#7a5a3a", "#4a3424", "#5e4430")
L.box(-.32, -.32, .64, .64, 4, "#8a6a44", "#5e4430", "#6e5038", z0=34); save(unkey(), "tower")
for f in range(2):
    im = Image.new("RGBA", (16, 18), (0, 0, 0, 0)); d = im.load()
    for k in range(6):
        a = k / 6 * 6.283; d[int(8 + math.cos(a) * 6), int(15 + math.sin(a) * 2.5)] = hx("#8a8478") + (255,)
    for x in range(3, 13): d[x, 14] = hx("#5e4430") + (255,)
    for yy in range(8):
        for xx in range(-3, 4):
            if abs(xx) <= 3 - yy // 3: d[8 + xx, 13 - yy - f] = (hx("#f2d06b") if abs(xx) < 2 and yy < 4 else hx("#f28c28")) + (255,)
    save(im, f"campfire{f}")
for name, col in (("flag_main", "#f2c36b"), ("flag", "#6fae4a"), ("flag_raider", "#a83a2a")):
    im = Image.new("RGBA", (10, 30), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.line([(1, 0), (1, 29)], fill=hx("#5a4a3a")); d.rectangle([2, 0, 8, 3], fill=hx(col)); d.rectangle([2, 4, 6, 5], fill=hx(col)); save(im, name)
im = Image.new("RGBA", (2, 15), (0, 0, 0, 0)); d = ImageDraw.Draw(im); d.rectangle([0, 1, 1, 14], fill=hx("#7a5a3a")); d.rectangle([0, 0, 1, 0], fill=hx("#c8b890")); save(im, "post")

# ---------------------------------------------------------------- tiles (32x16 diamonds)
def inDia(x, y):
    if y < 0 or y >= 16: return False
    hw = (y + 1) * 2 if y < 8 else (16 - y) * 2
    return 16 - hw <= x < 16 + hw
def diamond(fn, name):
    im = Image.new("RGBA", (32, 16), (0, 0, 0, 0)); d = im.load()
    for y in range(16):
        for x in range(32):
            if inDia(x, y): d[x, y] = fn(x, y) + (255,)
    save(im, name)
r = random.Random(5)
diamond(lambda x, y: hx("#5a3c28") if ((x >> 1) + y) % 4 == 0 else shade(hx("#6b4a32"), .94 + r.random() * .12), "floor_wood")
diamond(lambda x, y: hx("#bdb49c") if ((x >> 2) + (y >> 1)) % 2 else hx("#8a8476"), "floor_tile")
diamond(lambda x, y: hx("#a85a4a") if (x + y * 2) % 7 == 0 else hx("#7a3a34"), "floor_carpet")
diamond(lambda x, y: shade(hx("#8a867c"), .92 + r.random() * .14), "floor_concrete")
diamond(lambda x, y: hx("#5a4630") if ((x >> 1) + y) % 4 < 2 else (hx("#e0603a") if (x * 7 + y * 3) % 9 == 0 else hx("#6fae4a")), "garden")
diamond(lambda x, y: hx("#2a1e18") if ((x >> 1) + y) % 3 else hx("#6a5038"), "stairs_down")
diamond(lambda x, y: hx("#a08060") if ((x >> 1) + y) % 3 == 0 else hx("#7a5a3a"), "stairs_up")
PALS = [dict(top="#c9b080", x="#b89a6a", y="#9a7e56", roof="#5a4a4a"),
        dict(top="#c08a72", x="#8f5a46", y="#7a4a3a", roof="#4a3c44"),
        dict(top="#a8b0b4", x="#859aa4", y="#6e7f8a", roof="#3e4652"),
        dict(top="#b4b48a", x="#90906a", y="#7a7a52", roof="#4a4a3a"),
        dict(top="#ddd2b8", x="#cfc2a6", y="#b8aa8e", roof="#5a4a4a")]   # 4 = interior plaster
for i, p in enumerate(PALS):
    diamond(lambda x, y, p=p: shade(hx(p["roof"]), .82) if ((x >> 1) + y) % 3 == 0 else hx(p["roof"]), f"roof{i}")

# ---------------------------------------------------------------- thin walls
WALL_H = 28
def wall(axis, pal, window, Hh, name, interior=False):
    """axis 'x': wall runs along world +x (screen down-right). anchor = segment start at ground."""
    w, h = 18, Hh + 11
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = im.load()
    base = hx(pal["x"] if axis == 'x' else pal["y"]); top = hx(pal["top"])
    for u in range(17):                       # u: 0..16 along the wall (screen px)
        sx = 1 + u if axis == 'x' else 17 - u
        gy = Hh + 1 + u // 2                  # ground y at this column
        for v in range(Hh):                   # v: height above ground
            y = gy - v
            if interior: c = base if (u + v) % 9 else shade(base, .94)
            else: c = shade(base, .86) if (v % 5 == 0 or ((u + (v // 5) % 2 * 4) % 8 == 0)) else base
            if window and 5 <= u <= 11 and 11 <= v <= 21:
                c = shade(base, .55) if (u in (5, 11) or v in (11, 21)) else (hx("#3a4a5a") if (u + v) % 7 else hx("#6a8090"))
            if v == 0: c = shade(base, .7)
            d[sx, y] = c + (255,)
        for t in (0, 1):                      # top cap
            d[sx, gy - Hh - t] = (top if t == 0 else shade(top, 1.08)) + (255,)
        d[sx, gy - Hh - 2] = hx("#1e1622") + (255,)
    save(im, name)
for i, p in enumerate(PALS):
    for axis in ('x', 'y'):
        wall(axis, p, False, WALL_H, f"wall_{axis}{i}", interior=(i == 4))
        wall(axis, p, True, WALL_H, f"wall_{axis}{i}_win", interior=(i == 4))
        wall(axis, p, False, 5, f"low_{axis}{i}", interior=(i == 4))
print("sprites written to", os.path.abspath(OUT))
