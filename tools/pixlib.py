from PIL import Image, ImageDraw, ImageFont
import math, random

W, H = 384, 216
img = Image.new("RGB", (W, H), (34, 26, 44))
px = img.load()
dr = ImageDraw.Draw(img)
OX, OY = 176, 50
OUT = (30, 22, 34)

def hx(h): return tuple(int(h[i:i+2], 16) for i in (1, 3, 5)) if isinstance(h, str) else h
def P(x, y, z=0): return (int(round(OX + (x - y) * 16)), int(round(OY + (x + y) * 8 - z)))
def inv(sx, sy, z=0):
    a = (sx - OX) / 16.0; b = (sy + z - OY) / 8.0
    return ((a + b) / 2, (b - a) / 2)
def setp(x, y, c):
    x, y = int(x), int(y)
    if 0 <= x < W and 0 <= y < H: px[x, y] = hx(c)
def getp(x, y):
    x, y = int(x), int(y)
    return px[x, y] if (0 <= x < W and 0 <= y < H) else (0, 0, 0)
def dark(c, f): return tuple(max(0, min(255, int(v * f))) for v in hx(c))
def mix(a, b, t): a, b = hx(a), hx(b); return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))

# ---------------- terrain ----------------
def noise2(x, y, s=1.0):
    return (math.sin(x * 1.7 * s + y * .9 * s + 1.3) + math.sin(x * .6 * s - y * 1.9 * s + .4) + math.sin((x + y) * 3.1 * s)) / 3

def top_tex(mat, wx, wy):
    r = random.random()
    n = noise2(wx, wy)
    if mat == 'grass':
        if r < .05: return "#8a9a5a"
        if r < .09: return "#4f5a34"
        return "#6b7548" if n > -.2 else "#5f6a40"
    if mat == 'dry':
        if r < .06: return "#9a9060"
        return "#7a7848" if n > 0 else "#6e6a40"
    if mat == 'dirt':
        return "#7a6244" if r > .08 else "#8a7254"
    if mat == 'road':
        if r < .04: return "#3a383f"
        return "#4a484e" if n > -.5 else "#45434a"
    if mat == 'walk':
        if (wx % 1) < .05 or (wy % 1) < .05: return "#6e6a64"
        return "#8f897f" if r > .07 else "#7e786f"
    if mat == 'rock':
        return "#7a7468" if n > 0 else "#6a645a"
    if mat == 'water':
        rip = math.sin(wx * 9 + wy * 3 + n * 2)
        if rip > .93: return "#9ab4b0"
        return "#4a6a70" if n > 0 else "#42606a"
    if mat == 'mud':
        return "#5a4a36" if r > .1 else "#6a5a44"
    return "#ff00ff"

def face_tex(mat, u, z, side):
    r = random.random()
    if mat == 'water':
        streak = (int(u * 40) + int(z * .3)) % 5
        return "#c8dcd8" if streak == 0 or r < .15 else "#7a9ca0" if side == 'L' else "#8aacb0"
    base = {"L": ("#54463a", "#463a2e"), "R": ("#8a7456", "#7a6648")}[side]
    if mat in ('rock',):
        base = {"L": ("#5a564e", "#4a463e"), "R": ("#8e887a", "#7e786a")}[side]
    if z % 7 == 0: return dark(base[1], .9)
    return base[0] if r > .12 else base[1]

def render_terrain(hfun, mfun, xr, yr):
    tiles = [(x, y) for x in range(*xr) for y in range(*yr)]
    tiles.sort(key=lambda t: (t[0] + t[1], t[0]))
    for (x, y) in tiles:
        h = hfun(x, y); m = mfun(x, y)
        # top
        pts = [P(x, y, h), P(x + 1, y, h), P(x + 1, y + 1, h), P(x, y + 1, h)]
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        for sy in range(min(ys), max(ys) + 1):
            for sx in range(min(xs), max(xs) + 1):
                wx, wy = inv(sx + .5, sy + .5, h)
                if x <= wx < x + 1 and y <= wy < y + 1:
                    setp(sx, sy, top_tex(m, wx, wy))
        # south face (+y)
        hs = hfun(x, y + 1) if (y + 1) < yr[1] else -40
        if h > hs:
            fm = m if m == 'water' else ('rock' if h - hs > 16 else 'dirt')
            for i in range(0, 41):
                u = i / 40
                for z in range(hs, h):
                    sx, sy = P(x + u, y + 1, z); setp(sx, sy, face_tex(fm, x + u, z, 'L'))
                sx, sy = P(x + u, y + 1, hs); setp(sx, sy, OUT if fm != 'water' else "#d8e8e4")
            if m != 'water':
                for i in range(0, 33):
                    sx, sy = P(x + i / 32, y + 1, h); setp(sx, sy, mix(top_tex(m, x, y), "#ffffff", .15))
        he = hfun(x + 1, y) if (x + 1) < xr[1] else -40
        if h > he:
            fm = m if m == 'water' else ('rock' if h - he > 16 else 'dirt')
            for i in range(0, 41):
                u = i / 40
                for z in range(he, h):
                    sx, sy = P(x + 1, y + u, z); setp(sx, sy, face_tex(fm, y + u, z, 'R'))
                sx, sy = P(x + 1, y + u, he); setp(sx, sy, OUT if fm != 'water' else "#d8e8e4")
            if m != 'water':
                for i in range(0, 33):
                    sx, sy = P(x + 1, y + i / 32, h); setp(sx, sy, mix(top_tex(m, x, y), "#ffffff", .1))

# ---------------- primitives ----------------
def box(x0, y0, sx, sy, h, top, left, right, z0=0, outline=OUT, deco=None):
    x1, y1 = x0 + sx, y0 + sy
    t = [P(x0, y0, z0 + h), P(x1, y0, z0 + h), P(x1, y1, z0 + h), P(x0, y1, z0 + h)]
    lf = [P(x0, y1, z0), P(x1, y1, z0), P(x1, y1, z0 + h), P(x0, y1, z0 + h)]
    rt = [P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z0 + h), P(x1, y0, z0 + h)]
    dr.polygon(lf, fill=hx(left)); dr.polygon(rt, fill=hx(right)); dr.polygon(t, fill=hx(top))
    if deco: deco()
    if outline:
        sil = [P(x0, y0, z0 + h), P(x1, y0, z0 + h), P(x1, y0, z0), P(x1, y1, z0), P(x0, y1, z0), P(x0, y1, z0 + h)]
        dr.polygon(sil, outline=outline)
        dr.line([P(x0, y1, z0 + h), P(x1, y1, z0 + h), P(x1, y0, z0 + h)], fill=mix(top, "#ffffff", .15))

def speckle(x0, y0, sx, sy, z0, h, cols, n, face='L'):
    for _ in range(n):
        if face == 'L': sxp, syp = P(x0 + random.uniform(0, sx), y0 + sy, z0 + random.uniform(0, h))
        else: sxp, syp = P(x0 + sx, y0 + random.uniform(0, sy), z0 + random.uniform(0, h))
        setp(sxp, syp, random.choice(cols))

def shadow(cx, cy, w=10, h=3, f=.65):
    for yy in range(-h, h + 1):
        for xx in range(-w, w + 1):
            if (xx / w) ** 2 + (yy / h) ** 2 <= 1:
                c = getp(cx + xx, cy + yy); setp(cx + xx, cy + yy, (int(c[0] * f), int(c[1] * f), int(c[2] * f * 1.05)))

def sprite(rows, pal, x, y, flip=False):
    for j, row in enumerate(rows):
        if flip: row = row[::-1]
        for i, ch in enumerate(row):
            if ch != '.': setp(x + i, y + j, pal[ch])

def hull(points):
    pts = sorted(set(points))
    if len(pts) < 3: return pts
    def cross(o, a, b): return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0: lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0: up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]

def loft(bot, top, zb, zt, left, right, topc):
    n = len(bot); allp = []
    for i in range(n):
        a, b = bot[i], bot[(i + 1) % n]; c, d = top[(i + 1) % n], top[i]
        ex, ey = b[0] - a[0], b[1] - a[1]; nx, ny = ey, -ex
        quad = [P(a[0], a[1], zb), P(b[0], b[1], zb), P(c[0], c[1], zt), P(d[0], d[1], zt)]
        allp += quad
        if nx + ny > 1e-6:
            l = math.hypot(nx, ny); t = max(0, ny / l) / (max(0, ny / l) + max(0, nx / l) + 1e-6)
            dr.polygon(quad, fill=mix(right, left, t))
    dr.polygon([P(x, y, zt) for x, y in top], fill=hx(topc))
    return allp

def tree(tx, ty, tz=0, s=1.0, dead=False):
    bx, by = P(tx, ty, tz)
    shadow(bx, by, 12, 4)
    for yy in range(by - 16, by + 1):
        for xx in range(bx - 2, bx + 2): setp(xx, yy, "#5e4430" if xx < bx else "#4a3424")
    dr.line([(bx - 3, by - 16), (bx - 3, by)], fill=OUT); dr.line([(bx + 2, by - 16), (bx + 2, by)], fill=OUT)
    if dead:
        def branch(x, y, a, l, w):
            if l < 3: return
            x2, y2 = x + math.cos(a) * l, y + math.sin(a) * l
            dr.line([(x, y), (x2, y2)], fill=hx("#4a3424"), width=w)
            branch(x2, y2, a - random.uniform(.3, .7), l * .68, max(1, w - 1))
            branch(x2, y2, a + random.uniform(.3, .7), l * .68, max(1, w - 1))
        branch(bx, by - 15, -1.57, 13, 2); return
    blobs = [(0, -30, 12), (-9, -22, 8), (9, -22, 8), (-4, -37, 7), (6, -35, 7)]
    pts = {}
    for (dx, dy, r) in blobs:
        r *= s
        for yy in range(int(-r) - 1, int(r) + 2):
            for xx in range(int(-r) - 1, int(r) + 2):
                if xx * xx + yy * yy <= r * r and random.random() > .04:
                    pts[(bx + dx + xx, by + int(dy * s) + yy)] = (xx + yy) / r
    for (X, Y), l in pts.items():
        edge = any((X + a, Y + b) not in pts for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if edge: setp(X, Y, OUT); continue
        d = ((X * 7 + Y * 13) % 5) / 10
        setp(X, Y, "#9aa65a" if l + d < -.55 else "#76884a" if l + d < -.1 else "#5a6a3a" if l + d < .5 else "#424e2c")

def weed(wx, wy, wz=0, n=4, cols=("#8a9a5a", "#6a7a44", "#a8a868", "#7a7040")):
    b = P(wx, wy, wz)
    for k in range(n):
        x = b[0] + random.randint(-3, 3); h = random.randint(2, 5)
        for z in range(h): setp(x + (1 if z > h - 2 and k % 2 else 0), b[1] - z, random.choice(cols))

def rubble(wx, wy, wz, n, cols, spread=.35):
    for _ in range(n):
        a = P(wx + random.gauss(0, spread), wy + random.gauss(0, spread * .6), wz)
        c = random.choice(cols); setp(a[0], a[1], c)
        if random.random() < .5: setp(a[0] + 1, a[1], c)

def foot(u0, v0, L, Wd, c, ins=0.0):
    u0 += ins; v0 += ins; L -= 2 * ins; Wd -= 2 * ins; c = max(.02, c - ins * .5)
    return [(u0 + c, v0), (u0 + L - c, v0), (u0 + L, v0 + c), (u0 + L, v0 + Wd - c), (u0 + L - c, v0 + Wd), (u0 + c, v0 + Wd), (u0, v0 + Wd - c), (u0, v0 + c)]

def car(cx, cy, z0=0, axis='x', body=("#4a7470", "#5a8680", "#5a8a82", "#6e9e94", "#86b2a6"), burned=False):
    """1950s sedan. axis 'x' = length along world x, 'y' = along world y."""
    L, Wd = 2.6, 1.05
    def m(pts):
        if axis == 'x': return [(cx + u, cy + v) for u, v in pts]
        return [(cx + v, cy + u) for u, v in reversed(pts)]
    def M(u, v): return (cx + u, cy + v) if axis == 'x' else (cx + v, cy + u)
    before = img.copy()
    side_v = Wd  # visible long side is +v
    for (u, flat) in ((.5, False), (2.1, burned)):
        x, y = M(u, side_v)
        c = P(x, y, z0 + 4)
        for yy in range(-5, 6):
            for xx in range(-5, 6):
                ry = 4 if flat else 5
                d = (xx / 4.2) ** 2 + (yy / ry) ** 2
                if d <= 1: setp(c[0] + xx, c[1] + yy + (1 if flat else 0), "#1a1a1a" if d > .45 else ("#3a3a3a" if burned else "#d8d4c8") if d > .25 else "#5a5a5a")
    cxm, cym = M(L / 2, Wd / 2); s = P(cxm, cym, z0); shadow(s[0], s[1] + 2, 24, 6)
    bl, br, bL, bR, bT = body
    if burned: bl, br, bL, bR, bT = "#3a3430", "#4a4038", "#4a3e36", "#5a4a40", "#6a5a4a"
    pts = []
    pts += loft(m(foot(0, 0, L, Wd, .32, .07)), m(foot(0, 0, L, Wd, .32)), z0 + 3, z0 + 7, bl, br, bT)
    pts += loft(m(foot(0, 0, L, Wd, .32)), m(foot(0, 0, L, Wd, .32, .12)), z0 + 7, z0 + 12, bL, bR, bT)
    a, b = M(.25, Wd - .01), M(L - .2, Wd - .01)
    dr.line([P(*a, z0 + 8), P(*b, z0 + 8)], fill=hx("#d8d8cc" if not burned else "#5a5048"))
    for fv in (.12, Wd - .12):
        dr.polygon([P(*M(.05, fv), z0 + 12), P(*M(.75, fv), z0 + 12), P(*M(.06, fv), z0 + 17)], fill=hx(bT), outline=OUT)
    cb = [(.8, .14), (1.9, .14), (1.9, Wd - .14), (.8, Wd - .14)]
    ct = [(1.0, .24), (1.6, .24), (1.6, Wd - .24), (1.0, Wd - .24)]
    pts += loft(m(cb), m(ct), z0 + 12, z0 + 20, "#2a2420" if burned else "#3e5662", "#3a302a" if burned else "#5e7e8a", "#5a4a40" if burned else "#d8d0b8")
    if not burned:
        for u in (1.25, 1.5):
            dr.line([P(*M(u - .1, Wd - .14), z0 + 12), P(*M(u, Wd - .24), z0 + 20)], fill=hx("#c8c0a8"))
    dr.polygon(hull(pts), outline=OUT)
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    bodycols = [hx(c) for c in (bl, br, bL, bR, bT)]
    for yy in range(max(0, min(ys)), min(H, max(ys) + 1)):
        for xx in range(max(0, min(xs)), min(W, max(xs) + 1)):
            c = px[xx, yy]
            if c == before.getpixel((xx, yy)): continue
            if any(sum(abs(c[i] - bc[i]) for i in range(3)) < 40 for bc in bodycols):
                n = math.sin(xx * .31 + yy * .52 + cx) + math.sin(xx * .13 - yy * .37 + cy) * 1.2 + random.uniform(-.35, .35)
                if burned:
                    if n > .9: px[xx, yy] = hx("#6a3a24")
                    elif n > .3 and random.random() < .4: px[xx, yy] = hx("#2a2420")
                else:
                    if n > 1.55: px[xx, yy] = hx("#7a4024")
                    elif n > 1.25: px[xx, yy] = hx("#9a5a2e")

def text_px(x, y, s, col, size=8):
    try: f = ImageFont.load_default(size=size)
    except TypeError: f = ImageFont.load_default()
    mask = Image.new("1", (W, H), 0); md = ImageDraw.Draw(mask)
    md.fontmode = "1"; md.text((x, y), s, fill=1, font=f)
    mp = mask.load()
    for yy in range(H):
        for xx in range(W):
            if mp[xx, yy]: px[xx, yy] = hx(col)

# characters
PL = {'o': "#1e1622", 'h': "#4a2c1e", 'H': "#6e4430", 's': "#e0b08a", 'S': "#b88060", 'e': "#1e1622",
      'j': "#5a6a4a", 'J': "#7a8a5a", 'k': "#3e4a34", 'p': "#4a4a5a", 'P': "#34343e", 'b': "#3a2a20", 'B': "#8a6a3a", 'n': "#6a4a2a"}
PLAYER = ["....oooo....", "...oHHhho...", "..oHhhhhho..", "..ohssssSo..", "..osesseSo..", "..ossssSSo..",
          "...oSSSSo...", "..ookSSkoo..", ".okJJjjjkBo.", ".oJjjjjjkBno", "oJjjjjjjkBno", "osJjjjjkkBno",
          "oSojjjjkkono", ".oopppppPoo.", "..opppPPPo..", "..oppPoPPo..", "..oppPoPPo..", "..oPPo.oPo..",
          ".obbbo.obbo.", ".ooooo.oooo."]
SURV = dict(PL, j="#8a4a3a", J="#a85a48", k="#6a3a2a", h="#2a1a12", H="#3a2a1e", s="#c08a60", S="#9a6a48")
ZP = {'o': "#1e1622", 'h': "#3a2a20", 'z': "#8fa070", 'Z': "#6a7a52", 'R': "#e04a3a", 'r': "#6a2a2a",
      't': "#6e665a", 'T': "#4e4840", 'q': "#40405a", 'Q': "#2e2e3e"}
WALKER = ["....oooo....", "...ohZZho...", "..ozzzzzZo..", "..oRzzRzZo..", "..ozzzzZZo..", "..ozrrrZo...",
          "...oZZZo....", "....ottTo...", "oooottttTo..", "zzzZttrtTTo.", "oooottttTTo.", "...otttrTTo.",
          "...oTTTTTo..", "...oqqqQQo..", "...oqqoQQo..", "..oqqo.oQQo.", "..oqqo.oQo..", "..oZZo..oQo.",
          ".oZZZo.oZZo.", ".ooooo.oooo."]
DP = {'o': "#1e1622", 'd': "#a0703a", 'D': "#7a5028", 'l': "#c09060", 'e': "#1e1622"}
DOG = ["..........oo..", ".........oDdo.", "o........odedo", "do.ooooooodddo", ".odddddddddoo.",
       "..oldddddDDo..", "..oDDDDDDDDo..", "..odo.odo.odo.", "..ooo.ooo.ooo."]
def person(rows, pal, wx, wy, wz=0, flip=False):
    p = P(wx, wy, wz); shadow(p[0], p[1], 6, 2)
    sprite(rows, pal, p[0] - len(rows[0]) // 2, p[1] - len(rows), flip)
    return p

def fire(wx, wy, wz=0):
    p = P(wx, wy, wz)
    for yy in range(-9, 0):
        for xx in range(-3, 4):
            if abs(xx) <= 3 - (-yy) // 3:
                setp(p[0] + xx, p[1] + yy - 6, "#f2d06b" if abs(xx) < 2 and yy > -6 else "#f28c28")
    return p

def grade(lights, base=.64, sat=.72):
    bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    for sy in range(H):
        for sx in range(W):
            r, g, b = px[sx, sy]
            glow = 0
            for (lx, ly, rad, st) in lights:
                d = math.hypot(sx - lx, (sy - ly) * 1.6)
                glow = max(glow, st * max(0.0, 1 - d / rad))
            thr = (bayer[sy % 4][sx % 4] + .5) / 16
            lvl = glow * 4
            step = int(lvl) + (1 if (lvl - int(lvl)) > thr else 0)
            k = base + step * .1
            rr, gg, bb = r * k * (1 + .1 * step), g * k * (1 + .03 * step), b * k * (1.05 - .06 * step)
            lum = .3 * rr + .59 * gg + .11 * bb
            rr, gg, bb = lum + (rr - lum) * sat, lum + (gg - lum) * sat, lum + (bb - lum) * sat
            rr, gg, bb = rr * 1.03 + 4, gg + 3, bb * .86
            px[sx, sy] = (min(255, max(0, int(rr))), min(255, max(0, int(gg))), min(255, max(0, int(bb))))

def save(name):
    img.save(f"/home/claude/art/{name}_native.png")
    img.resize((W * 4, H * 4), Image.NEAREST).save(f"/home/claude/art/{name}_x4.png")
