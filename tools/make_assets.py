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

def hx(h): return tuple(h) if not isinstance(h, str) else tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
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

def car_rot(ang, body, burned=False):
    """1950s sedan rotated to world angle ang (radians), centred on (0,0)."""
    Ln, Wd = 2.6, 1.05
    ca, sa = math.cos(ang), math.sin(ang)
    def M(u, v):
        u -= Ln / 2; v -= Wd / 2
        return (u * ca - v * sa, u * sa + v * ca)
    def m(pts): return [M(u, v) for u, v in pts]
    before = L.img.copy()
    side_v = Wd if (-sa + ca) > 0 else 0.0           # long side facing the camera
    for (u, flat) in ((.5, False), (2.1, burned)):
        x, y = M(u, side_v)
        c = L.P(x, y, 4)
        for yy in range(-5, 6):
            for xx in range(-5, 6):
                ry = 4 if flat else 5
                d = (xx / 4.2) ** 2 + (yy / ry) ** 2
                if d <= 1: L.setp(c[0] + xx, c[1] + yy + (1 if flat else 0), "#1a1a1a" if d > .45 else ("#3a3a3a" if burned else "#d8d4c8") if d > .25 else "#5a5a5a")
    bl, br, bL, bR, bT = body if body else ("#3a3430", "#4a4038", "#4a3e36", "#5a4a40", "#6a5a4a")
    pts = []
    pts += L.loft(m(L.foot(0, 0, Ln, Wd, .32, .07)), m(L.foot(0, 0, Ln, Wd, .32)), 3, 7, bl, br, bT)
    pts += L.loft(m(L.foot(0, 0, Ln, Wd, .32)), m(L.foot(0, 0, Ln, Wd, .32, .12)), 7, 12, bL, bR, bT)
    sv = side_v - .01 if side_v else .01
    L.dr.line([L.P(*M(.25, sv), 8), L.P(*M(Ln - .2, sv), 8)], fill=hx("#5a5048" if burned else "#d8d8cc"))
    for fv in (.12, Wd - .12):
        L.dr.polygon([L.P(*M(.05, fv), 12), L.P(*M(.75, fv), 12), L.P(*M(.06, fv), 17)], fill=hx(bT), outline=L.OUT)
    cb = [(.8, .14), (1.9, .14), (1.9, Wd - .14), (.8, Wd - .14)]
    ct = [(1.0, .24), (1.6, .24), (1.6, Wd - .24), (1.0, Wd - .24)]
    pts += L.loft(m(cb), m(ct), 12, 20, "#2a2420" if burned else "#3e5662", "#3a302a" if burned else "#5e7e8a", "#5a4a40" if burned else "#d8d0b8")
    L.dr.polygon(L.hull(pts), outline=L.OUT)
    xs = [q[0] for q in pts]; ys = [q[1] for q in pts]
    bodycols = [hx(c) for c in (bl, br, bL, bR, bT)]
    for yy in range(max(0, min(ys)), min(L.H, max(ys) + 1)):
        for xx in range(max(0, min(xs)), min(L.W, max(xs) + 1)):
            c = L.px[xx, yy]
            if c == before.getpixel((xx, yy)): continue
            if any(sum(abs(c[i] - bc[i]) for i in range(3)) < 40 for bc in bodycols):
                n = math.sin(xx * .31 + yy * .52 + ang) + math.sin(xx * .13 - yy * .37) * 1.2 + random.uniform(-.35, .35)
                if burned:
                    if n > .9: L.px[xx, yy] = hx("#6a3a24")
                    elif n > .3 and random.random() < .4: L.px[xx, yy] = hx("#2a2420")
                elif n > 1.55: L.px[xx, yy] = hx("#7a4024")
                elif n > 1.25: L.px[xx, yy] = hx("#9a5a2e")

for name, body in bodies.items():
    for k in range(8):
        keyed(80, 64); L.OX, L.OY = 40, 34
        random.seed(k * 31 + len(name))
        car_rot(k * math.pi / 4, body, burned=(body is None))
        save(unkey(), f"car_{name}_{k}")      # anchor (40,34) = car ground centre; k*45 deg world angle

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
def wall(axis, pal, window, Hh, name, interior=False, mode="plain"):
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
                frame = u in (5, 11) or v in (11, 21)
                if frame: c = shade(base, .55)
                elif mode == "broken": c = hx("#9ab0b8") if (u * 7 + v * 3) % 11 == 0 or (v < 13 and u % 3 == 0) else hx("#1a1412")
                elif mode == "boarded": c = hx("#4a3424") if (v - u // 3) % 4 == 0 else (hx("#c0c0c0") if (u, v) in ((6, 14), (10, 18)) else hx("#7a5a3a"))
                else: c = hx("#3a4a5a") if (u + v) % 7 else hx("#6a8090")
            if mode == "cracked" and not interior:
                cx_ = 8 + int(3 * math.sin(v * 0.7))
                if u == cx_ and 4 < v < Hh - 3: c = hx("#2a1e18")
                if 2 <= u <= 6 and 4 <= v <= 9 and (u + v) % 2 == 0: c = shade(base, .7)
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
        wall(axis, p, True, WALL_H, f"wall_{axis}{i}_broken", interior=(i == 4), mode="broken")
        wall(axis, p, True, WALL_H, f"wall_{axis}{i}_boarded", interior=(i == 4), mode="boarded")
        wall(axis, p, False, WALL_H, f"wall_{axis}{i}_cracked", interior=(i == 4), mode="cracked")
        wall(axis, p, False, 5, f"low_{axis}{i}", interior=(i == 4))
        # collapsed stub: jagged broken-off wall
        im = Image.new("RGBA", (18, WALL_H + 11), (0, 0, 0, 0)); d = im.load()
        base = hx(p["x"] if axis == 'x' else p["y"]); rr = random.Random(i * 7 + (axis == 'x'))
        hh = 10
        for u in range(17):
            hh = max(3, min(20, hh + rr.randint(-3, 3)))
            sx = 1 + u if axis == 'x' else 17 - u
            gy = WALL_H + 1 + u // 2
            for v in range(hh):
                c = shade(base, .86) if v % 5 == 0 else base
                if v == hh - 1: c = shade(base, .6)
                d[sx, gy - v] = c + (255,)
        save(im, f"stub_{axis}{i}")


# ---------------------------------------------------------------- furniture (two orientations)
# a = long side along world x (sits against a north wall), b = long side along world y (west wall)
FURN = {
    'counter': (1.0, .5, 12, '#c8bca0', '#8a6040', '#a07050', 'drawers'),
    'stove': (.5, .5, 12, '#d8d8d0', '#a8a8a0', '#c0c0b8', 'stove'),
    'fridge': (.5, .5, 28, '#d4d6c8', '#a8ac9e', '#bcc0b2', 'fridge'),
    'table': (.9, .6, 10, '#9a6a3a', '#5a3c24', '#6a4630', 'table'),
    'chair': (.3, .3, 6, '#7a5234', '#5a3c28', '#6a4430', 'chair'),
    'couch': (1.0, .45, 8, '#6a7a5a', '#4a5a3e', '#5a6a4a', 'couch'),
    'armchair': (.45, .45, 8, '#8a5a4a', '#6a3a2a', '#7a4a3a', 'couch'),
    'tv': (.4, .3, 12, '#4a4440', '#2a2420', '#3a3430', 'tv'),
    'bookshelf': (.9, .3, 26, '#7a5638', '#5a3c24', '#6a4630', 'shelf'),
    'bed': (1.0, .6, 7, '#c8c0a8', '#6a5a7a', '#7a6a8a', 'bed'),
    'dresser': (.6, .35, 14, '#8a6040', '#6a4528', '#7a5234', 'drawers'),
    'desk': (.8, .45, 11, '#7a5a3a', '#5a3c24', '#6a4630', 'drawers'),
    'filing': (.35, .35, 16, '#9aa0a0', '#6e7474', '#848a8a', 'drawers'),
    'shopshelf': (1.0, .35, 20, '#8a8a82', '#6a6a62', '#7a7a72', 'goods'),
    'shopcounter': (1.0, .4, 12, '#a08a6a', '#6a5a44', '#7a6a54', 'register'),
    'workbench': (.9, .4, 11, '#a07a4a', '#6a4a2a', '#8a6a3a', 'tools'),
    'barrel': (.35, .35, 12, '#7a5a3a', '#5a3a24', '#6a4a2e', 'barrel'),
    'mattress': (.9, .55, 3, '#a89a7a', '#6a5a44', '#7a6a54', 'bed'),
}
def furniture(name, orient):
    Lg, Dp, Hh, top, left, right, kind = FURN[name]
    sx, sy = (Lg, Dp) if orient == 'a' else (Dp, Lg)
    x0, y0 = -sx / 2, -sy / 2
    keyed(48, 56); L.OX, L.OY = 24, 40
    random.seed(hash(name + orient) % 997)
    front = 'L' if orient == 'a' else 'R'
    def fp(u, z, face=front):   # point on a face: u 0..1 along it, z height
        return L.P(x0 + u * sx, y0 + sy, z) if face == 'L' else L.P(x0 + sx, y0 + u * sy, z)
    def hline(z, col, face=front, a=.05, b=.95):
        L.dr.line([fp(a, z, face), fp(b, z, face)], fill=hx(col))
    if kind == 'table':
        for (lx, ly) in ((x0 + .05, y0 + .05), (x0 + sx - .1, y0 + .05), (x0 + .05, y0 + sy - .1), (x0 + sx - .1, y0 + sy - .1)):
            L.box(lx, ly, .05, .05, 8, left, left, right, outline=None)
        L.box(x0, y0, sx, sy, 2, top, left, right, z0=8)
    elif kind == 'chair':
        L.box(x0, y0, sx, sy, 2, top, left, right, z0=4)
        for (lx, ly) in ((x0, y0 + sy - .05), (x0 + sx - .05, y0 + sy - .05), (x0 + sx - .05, y0)):
            L.box(lx, ly, .05, .05, 4, left, left, right, outline=None)
        L.box(x0, y0, sx, .06, 7, top, left, right, z0=6)
    elif kind == 'couch':
        L.box(x0, y0, sx, sy, 5, top, left, right)
        if orient == 'a': L.box(x0, y0, sx, .15, 6, top, left, right, z0=5)
        else: L.box(x0, y0, .15, sy, 6, top, left, right, z0=5)
        for _ in range(12):
            q = L.P(x0 + random.uniform(0, sx), y0 + random.uniform(0, sy), 5); L.setp(q[0], q[1], shade(hx(top), .8))
    elif kind == 'tv':
        L.box(x0 + .08, y0 + .08, sx - .16, sy - .16, 4, left, left, right)
        L.box(x0, y0, sx, sy, 9, top, left, right, z0=4)
        for z in range(6, 12):
            L.dr.line([fp(.15, z), fp(.85, z)], fill=hx("#2a3a3a" if z % 3 else "#4a6a6a"))
    elif kind == 'bed':
        L.box(x0, y0, sx, sy, Hh, top, left, right)
        if orient == 'a': L.box(x0 + .03, y0 + .03, .25, sy - .06, 2, "#e8e0d0", "#b8b0a0", "#c8c0b0", z0=Hh, outline=None)
        else: L.box(x0 + .03, y0 + .03, sx - .06, .25, 2, "#e8e0d0", "#b8b0a0", "#c8c0b0", z0=Hh, outline=None)
        for _ in range(25):
            q = L.P(x0 + random.uniform(.3, sx), y0 + random.uniform(.05, sy), Hh) if orient == 'a' else L.P(x0 + random.uniform(.05, sx), y0 + random.uniform(.3, sy), Hh)
            L.setp(q[0], q[1], random.choice(["#6a5a7a", "#7a6a8a", "#8a7a9a"]))
    elif kind == 'barrel':
        L.box(x0, y0, sx, sy, Hh, top, left, right)
        for z in (3, 9):
            hline(z, "#3a2418", 'L'); hline(z, "#3a2418", 'R')
        for _ in range(10):
            q = fp(random.random(), random.uniform(0, Hh), random.choice('LR')); L.setp(q[0], q[1], "#9a5a2e")
    else:
        L.box(x0, y0, sx, sy, Hh, top, left, right)
        if kind == 'drawers':
            for z in range(4, Hh - 1, 4):
                hline(z, shade(hx(left if front == 'L' else right), .7))
                q = fp(.5, z + 2); L.setp(q[0], q[1], "#d8c49a")
        elif kind == 'fridge':
            hline(18, "#8a948a"); q = fp(.8, 22); L.setp(q[0], q[1], "#3a403a"); q = fp(.8, 12); L.setp(q[0], q[1], "#3a403a")
            for _ in range(14):
                q = fp(random.random(), random.uniform(0, 28)); L.setp(q[0], q[1], "#8a5a3a")
        elif kind == 'stove':
            for (u, v) in ((.3, .3), (.7, .3), (.3, .7), (.7, .7)):
                q = L.P(x0 + u * sx, y0 + v * sy, Hh); L.setp(q[0], q[1], "#2a2a2a"); L.setp(q[0] + 1, q[1], "#2a2a2a")
            hline(8, "#2a2a2a", a=.2, b=.8)
        elif kind == 'shelf' or kind == 'goods':
            cols = ["#8a4040", "#4a6a7a", "#c0a060", "#5a7a4a", "#6a5a7a", "#c8c0a8"]
            for z in range(5, Hh, 6):
                hline(z, "#2a1e14" if kind == 'shelf' else "#4a4a44")
                u = .06
                while u < .94:
                    if random.random() < .65:
                        c = random.choice(cols)
                        for zz in range(z + 1, z + random.randint(3, 5)):
                            q = fp(u, zz); L.setp(q[0], q[1], c)
                    u += .07
        elif kind == 'register':
            L.box(x0 + sx * .6, y0 + sy * .2, .2, .2, 4, "#4a4a44", "#2a2a24", "#3a3a34", z0=Hh)
        elif kind == 'tools':
            for _ in range(8):
                q = L.P(x0 + random.uniform(.1, sx - .1), y0 + random.uniform(.1, sy - .1), Hh); L.setp(q[0], q[1], random.choice(["#9aa0a6", "#c83a2a", "#2a2a2a"]))
    save(unkey(), f"furn_{name}_{orient}")
for nm in FURN:
    furniture(nm, 'a'); furniture(nm, 'b')

# ---------------------------------------------------------------- outdoor debris / props
def prop(name, size, anchor, fn):
    keyed(*size); L.OX, L.OY = anchor; fn(); save(unkey(), name)
def rubble_pile(seed, cols):
    def f():
        rr = random.Random(seed)
        for k in range(26):
            u, v = rr.gauss(0, .25), rr.gauss(0, .18)
            h = max(1, int(5 * (1 - (u * u + v * v) * 3)))
            c = rr.choice(cols)
            L.box(u - .05, v - .05, .1 + rr.random() * .06, .1, h + rr.randint(0, 2), c, shade(hx(c), .7), shade(hx(c), .85), z0=0, outline=None)
    return f
for i in range(3):
    prop(f"rubble{i}", (40, 30), (20, 22), rubble_pile(i, ["#9a9488", "#7e786c", "#8a5a46", "#b0a07a", "#6a645a"]))
prop("bricks", (40, 30), (20, 22), rubble_pile(9, ["#8a5a46", "#7a4434", "#a86a54", "#6a3a2a"]))
def papers():
    for _ in range(8):
        q = L.P(random.uniform(-.4, .4), random.uniform(-.3, .3), 0); L.setp(q[0], q[1], "#e8e0c8"); L.setp(q[0] + 1, q[1], "#d0c8b0")
prop("papers", (32, 20), (16, 10), papers)
def bag():
    for yy in range(-6, 1):
        for xx in range(-5, 6):
            if (xx / 5.2) ** 2 + ((yy + 3) / 3.4) ** 2 <= 1: L.setp(20 + xx, 22 + yy, "#2a3a2a" if xx > -1 else "#3a4e3a")
    L.setp(19, 15, "#2a3a2a"); L.setp(18, 18, "#5a6e5a")
prop("trashbag", (40, 30), (20, 22), bag)
def tire():
    for yy in range(-3, 4):
        for xx in range(-6, 7):
            d = (xx / 6) ** 2 + (yy / 3.2) ** 2
            if d <= 1: L.setp(20 + xx, 22 + yy, "#1e1e1e" if d > .3 else "#4a4a3a")
prop("tire", (40, 30), (20, 22), tire)
prop("barrel_rust", (20, 26), (10, 20), lambda: (L.box(-.17, -.17, .34, .34, 12, "#7a4a2a", "#5a3420", "#6a3e26"), [L.setp(*L.P(random.uniform(-.17, .17), .17, random.uniform(0, 12)), "#a0622e") for _ in range(14)]))
def toxic():
    L.box(-.17, -.17, .34, .34, 12, "#c0a030", "#8a7020", "#a08828")
    for z in (3, 9):
        L.dr.line([L.P(-.17, .17, z), L.P(.17, .17, z)], fill=hx("#3a3010")); L.dr.line([L.P(.17, -.17, z), L.P(.17, .17, z)], fill=hx("#3a3010"))
    for (u, v) in ((0, 0), (.05, .02), (-.04, .03), (.02, -.04)):
        q = L.P(u, v, 12); L.setp(q[0], q[1], "#8aff6a")
prop("barrel_toxic", (20, 26), (10, 20), toxic)
prop("jersey_x", (44, 30), (22, 22), lambda: (L.box(-.5, -.12, 1.0, .24, 9, "#b8b2a4", "#8a8478", "#9e988a"), L.dr.line([L.P(-.45, .12, 5), L.P(.45, .12, 5)], fill=hx("#c8a040"))))
prop("jersey_y", (44, 30), (22, 22), lambda: (L.box(-.12, -.5, .24, 1.0, 9, "#b8b2a4", "#8a8478", "#9e988a"), L.dr.line([L.P(.12, -.45, 5), L.P(.12, .45, 5)], fill=hx("#c8a040"))))
def skull():
    for (x, y, c) in ((0, 0, "#e8e0c8"), (1, 0, "#e8e0c8"), (2, 0, "#e8e0c8"), (0, 1, "#e8e0c8"), (1, 1, "#2a2420"), (2, 1, "#e8e0c8"), (0, 2, "#d0c8b0"), (2, 2, "#d0c8b0"),
                      (5, 2, "#d8d0b8"), (6, 2, "#d8d0b8"), (7, 2, "#d8d0b8"), (4, 3, "#d8d0b8")):
        L.setp(8 + x, 10 + y, c)
prop("bones", (24, 16), (12, 12), skull)
def puddle():
    rr = random.Random(4)
    for yy in range(-5, 6):
        for xx in range(-12, 13):
            d = (xx / 12) ** 2 + (yy / 5) ** 2 + rr.uniform(-.15, .15)
            if d <= 1: L.setp(16 + xx, 8 + yy, "#6aa04a" if d > .75 else ("#9ad06a" if (xx + yy) % 7 == 0 else "#7ab85a"))
prop("puddle_toxic", (32, 16), (16, 8), puddle)
def cart():
    L.dr.line([L.P(-.25, -.15, 6), L.P(.25, -.15, 8)], fill=hx("#9a9a9a"))
    for (u, v) in ((-.25, -.15), (.25, -.15), (.25, .15), (-.25, .15)):
        L.dr.line([L.P(u, v, 1), L.P(u, v, 8)], fill=hx("#8a8a8a"))
    for z in (2, 5, 8):
        L.dr.polygon([L.P(-.25, -.15, z), L.P(.25, -.15, z), L.P(.25, .15, z), L.P(-.25, .15, z)], outline=hx("#9a9a9a"))
    for (u, v) in ((-.22, -.12), (.22, .12), (-.22, .12), (.22, -.12)):
        q = L.P(u, v, 0); L.setp(q[0], q[1], "#2a2a2a")
prop("cart", (32, 30), (16, 22), cart)
def pole():
    L.dr.line([(4, 2), (4, 60)], fill=hx("#5a4a3a"), width=2)
    L.dr.line([(0, 6), (9, 6)], fill=hx("#5a4a3a"))
    for x in (0, 8): L.setp(x, 5, "#c8c0a8")
prop("pole", (10, 62), (4, 60), pole)                      # wires attach at (0,5)/(8,5) relative to top
def sign():
    L.dr.line([(9, 6), (11, 30)], fill=hx("#7a7a72"), width=1)
    L.dr.polygon([(9, 0), (16, 6), (9, 12), (2, 6)], fill=hx("#c8a040"), outline=hx("#1e1622"))
    for (x, y) in ((9, 4), (8, 6), (10, 6), (9, 7)): L.setp(x, y, "#1e1622")
prop("sign_rad", (20, 32), (11, 30), sign)
def bush():
    rr = random.Random(2)
    for _ in range(30):
        a = rr.uniform(3.4, 6.0); l = rr.uniform(3, 9)
        L.dr.line([(12, 15), (12 + math.cos(a) * l, 15 + math.sin(a) * l)], fill=hx(rr.choice(["#6a5a3a", "#7a6a44", "#5a4a30"])))
prop("deadbush", (24, 16), (12, 15), bush)
def fence():
    for k in range(4):
        L.box(-.5 + k * .3, -.03, .06, .06, 10 - (6 if k == 2 else 0), "#8a7458", "#5a4632", "#6a543a", outline=None)
    L.dr.line([L.P(-.5, 0, 7), L.P(-.2, 0, 7)], fill=hx("#8a7458")); L.dr.line([L.P(.1, 0, 6), L.P(.4, 0, 7)], fill=hx("#8a7458"))
prop("fence", (40, 30), (20, 22), fence)
for i in range(3):
    def tuft(i=i):
        rr = random.Random(i)
        for k in range(6):
            x = 4 + rr.randint(-3, 3); hgt = rr.randint(2, 6)
            for z in range(hgt): L.setp(x + (1 if z > hgt - 2 and k % 2 else 0), 7 - z, rr.choice(["#8a9a5a", "#6a7a44", "#a8a868", "#7a7040"]))
    prop(f"tuft{i}", (9, 8), (4, 7), tuft)

# ---------------------------------------------------------------- creatures & NPCs
GH = dict(PL, j="#4a4a3e", J="#5e5e4e", k="#34342a", h="#3a3a2a", H="#4a4a38", s="#8a9a6a", S="#6a7a50", e="#d8f060", p="#3e3a32", P="#2a2620", B="#5a5040", n="#3a3428", b="#2a2420")
def ghoul_extra(f, oy):
    d = f.load()
    for (x, y) in ((5, oy + 9), (10, oy + 11), (6, oy + 13)):
        d[x, y] = hx("#7a2a2a") + (255,)                                           # wounds
save(human_sheet(GH, ghoul_extra), "ghoul")
for nm, pal in (("settler1", dict(PL, j="#7a6a4a", J="#9a8a5a", k="#5a4a34", h="#6a4a2a", s="#d8a07a")),
                ("settler2", dict(PL, j="#4a5a7a", J="#5a6a8a", k="#34405a", h="#c8b890", H="#e0d0a8", s="#e8c0a0")),
                ("settler3", dict(PL, j="#8a3a3a", J="#a04848", k="#6a2a2a", h="#2a1a12", s="#8a5a3a", S="#6a4028")),
                ("trader", dict(PL, j="#6a5a3a", J="#8a7a4a", k="#4a3e28", h="#4a3020", s="#c08a60", B="#9a7a4a", n="#7a5a3a"))):
    save(human_sheet(pal), nm)
BR = {'o': "#1e1622", 'g': "#8a9a4a", 'G': "#6a7a38", 'y': "#a8b860", 'e': "#e0d040", 'm': "#3a2a20", 'a': "#6a5a4a", 'A': "#4a3e30", 'k': "#2a2420", 'w': "#d8d0b0"}
BRUTE = ["......oooooo......", ".....ogggggGo.....", ".....ogeggegGo....", ".....oggmmggGo....", "......oGGGGGo.....",
         "...oooogggggoooo..", "..ogggyggggggGGGo.", ".ogggyygggggggGGGo", ".oggyyggaaaaggGGGo", "ogggyggaAAAaggGGGo",
         "ogggogggaaaagggoGGo", "oggo.ogggggggo.oGo.", "oyyo.ogggggggo.oyyo", "owwo.oaaaaaaao.owwo", ".oo..oaAAAAAAo..oo.",
         ".....ogggooggggo...", ".....ogggo.oggGo...", ".....ogggo.oggGo...", ".....oGGGo.oGGGo...", "....okkkko.okkkko..", "....oooooo.oooooo.."]
BRUTE = [r[:18].ljust(18, '.') for r in BRUTE]
BRUTE_W = BRUTE[:15] + [".....ogggooggggo...", ".....ogggo..oggGo..", "....ogggo...oggGo..", "....oGGGo...oGGGo..", "...okkkko...okkkko.", "...oooooo...oooooo."]
BRUTE_W = [r[:18].ljust(18, '.') for r in BRUTE_W]
def back_brute(rows):
    r = list(rows); r[2] = ".....ogggggggo...."; r[3] = ".....ogggggGGo...."; return r
save(sheet([rows_img(BRUTE, BR, 20, 26, 1, 4), rows_img(BRUTE_W, BR, 20, 26, 1, 4), rows_img(back_brute(BRUTE), BR, 20, 26, 1, 4), rows_img(back_brute(BRUTE_W), BR, 20, 26, 1, 4)]), "brute")
SB = {'o': "#1e1622", 's': "#8a6a4a", 'S': "#6a4a32", 'h': "#a88a5a", 'e': "#e04a3a", 'c': "#b07a4a", 'l': "#5a3a24"}
SHELL = ["......oooooooo........", "....oohhhhhhhhoo......", "...ohhsshhsshhhho.....", "..ohsssssssssssSSo....",
         "oooshssshssssssSSSoooo", "occossssssssssSSSoocco", "oco.oSSSSSSSSSSSo.oeoo", ".o..olo.olo.olo.o..o..", "....o...o...o...o....."]
SHELL2 = SHELL[:7] + ["..o.olo.olo.olo.o.....", "...o...o...o...o......"]
save(sheet([rows_img(SHELL, SB, 22, 11, 0, 1), rows_img(SHELL2, SB, 22, 11, 0, 1)]), "shellback")
CR = {'o': "#1e1622", 'b': "#2a2a30", 'B': "#4a4a52", 'y': "#e0c040"}
CROW_SIT = ["..oo..", ".obbyy", "obBbo.", ".obbo.", "..o.o."]
CROW_F1 = ["o....o", "ob..bo", ".obbo.", "..by..", "......"]
CROW_F2 = ["......", "..by..", "obbbbo", "o....o", "......"]
save(sheet([rows_img(CROW_SIT, CR, 8, 6, 1, 1), rows_img(CROW_F1, CR, 8, 6, 1, 1), rows_img(CROW_F2, CR, 8, 6, 1, 1)]), "crow")
CW = {'o': "#1e1622", 'c': "#a08060", 'C': "#7a5a40", 'w': "#e8e0c8", 'h': "#5a4030", 'p': "#d0a090"}
COW = ["oo..oo..............", "oco.oco.............", "occwocc.............", ".occccooooooooo.....", "..oCcccccccccccco...",
       "...occccwwccccccCo..", "...oCcccwwcccccCCo..", "....oCCCCCCCCCCCo...", "....oho.oho..oho.oho", "....oo..oo...oo..oo."]
COW2 = COW[:8] + ["....oho..oho.oho..oh", "....oo....oo.oo...oo"]
COW = [r[:20].ljust(20, '.') for r in COW]; COW2 = [r[:20].ljust(20, '.') for r in COW2]
save(sheet([rows_img(COW, CW, 20, 11, 0, 1), rows_img(COW2, CW, 20, 11, 0, 1)]), "cattle")

# corrugated tin walls for settlement shacks (palette 5)
TIN = dict(top="#9a9488", x="#8a7a68", y="#6e6252", roof="#7a6a5a")
def tin_wall(axis, window, Hh, name):
    w, h = 18, Hh + 11
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = im.load()
    base = hx(TIN["x"] if axis == 'x' else TIN["y"]); rr = random.Random(hash(name) % 1000)
    for u in range(17):
        sx = 1 + u if axis == 'x' else 17 - u
        gy = Hh + 1 + u // 2
        for v in range(Hh):
            c = shade(base, 1.12 if u % 3 == 0 else (.86 if u % 3 == 2 else 1.0))
            if rr.random() < .06 or (4 < v < 12 and 9 < u < 15): c = shade(hx("#8a4a2a"), .9 + rr.random() * .2)
            if window and 5 <= u <= 11 and 11 <= v <= 19:
                c = shade(base, .5) if (u in (5, 11) or v in (11, 19)) else hx("#2a2420")
            if v == 0: c = shade(base, .7)
            d[sx, gy - v] = c + (255,)
        d[sx, gy - Hh] = hx(TIN["top"]) + (255,); d[sx, gy - Hh - 1] = hx("#1e1622") + (255,)
    save(im, name)
for axis in ('x', 'y'):
    tin_wall(axis, False, WALL_H, f"wall_{axis}5"); tin_wall(axis, True, WALL_H, f"wall_{axis}5_win")
    for m in ("broken", "boarded", "cracked"): tin_wall(axis, m != "cracked", WALL_H, f"wall_{axis}5_{m}")
    tin_wall(axis, False, 5, f"low_{axis}5"); tin_wall(axis, False, 12, f"stub_{axis}5")
diamond(lambda x, y: shade(hx(TIN["roof"]), 1.12 if x % 3 == 0 else .9) if (x * 5 + y * 3) % 17 else hx("#8a4a2a"), "roof5")
im = Image.new("RGBA", (12, 30), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
d.rectangle([3, 8, 8, 29], fill=hx("#5a5a52")); d.rectangle([2, 4, 9, 8], fill=hx("#6a6a62"), outline=hx("#1e1622")); d.line([(9, 14), (11, 14), (11, 18)], fill=hx("#4a4a44"))
save(im, "pump")

print("sprites written to", os.path.abspath(OUT))
