"""Outdoor art: trees, retro cars, props, debris, street furniture, signs."""
import math, random
from px2 import Cv, sh, mix, hx, lit3, noise, HW, HH, S

FONT = {
    'A': ["010", "101", "111", "101", "101"], 'B': ["110", "101", "110", "101", "110"], 'C': ["011", "100", "100", "100", "011"],
    'D': ["110", "101", "101", "101", "110"], 'E': ["111", "100", "110", "100", "111"], 'F': ["111", "100", "110", "100", "100"],
    'G': ["011", "100", "101", "101", "011"], 'H': ["101", "101", "111", "101", "101"], 'I': ["111", "010", "010", "010", "111"],
    'J': ["001", "001", "001", "101", "010"], 'K': ["101", "101", "110", "101", "101"], 'L': ["100", "100", "100", "100", "111"],
    'M': ["101", "111", "111", "101", "101"], 'N': ["110", "101", "101", "101", "101"], 'O': ["010", "101", "101", "101", "010"],
    'P': ["110", "101", "110", "100", "100"], 'Q': ["010", "101", "101", "110", "011"], 'R': ["110", "101", "110", "101", "101"],
    'S': ["011", "100", "010", "001", "110"], 'T': ["111", "010", "010", "010", "010"], 'U': ["101", "101", "101", "101", "111"],
    'V': ["101", "101", "101", "101", "010"], 'W': ["101", "101", "111", "111", "101"], 'X': ["101", "101", "010", "101", "101"],
    'Y': ["101", "101", "010", "010", "010"], 'Z': ["111", "001", "010", "100", "111"], '0': ["111", "101", "101", "101", "111"],
    '1': ["010", "110", "010", "010", "111"], '2': ["110", "001", "010", "100", "111"], '5': ["111", "100", "110", "001", "110"],
    '-': ["000", "000", "111", "000", "000"], ' ': ["000", "000", "000", "000", "000"], '.': ["000", "000", "000", "000", "010"],
    '&': ["010", "101", "010", "101", "011"], '!': ["010", "010", "010", "000", "010"],
}


def text_w(s):
    return len(s) * 4 - 1


def text(c, x, y, s, col, shear=0.0, shadow=None):
    """Draw pixel text. shear = dy per px of x (0.5 for south-facing walls, -0.5 for east)."""
    cx = 0
    for ch in s.upper():
        g = FONT.get(ch, FONT[' '])
        for j, row in enumerate(g):
            for i, b in enumerate(row):
                if b == '1':
                    px = cx + i
                    yy = y + j + int(math.floor(px * shear))
                    if shadow:
                        c.put(x + px + 1, yy + 1, shadow)
                    c.put(x + px, yy, col)
        cx += 4


# ------------------------------------------------------------------ trees
def blob_tree(seed, kind):
    r = random.Random(seed)
    c = Cv(36, 57, 18, 54)
    bark = "#5a4030"
    if kind == "dead":
        c.rect(16, 30, 19, 53, bark)
        c.rect(16, 30, 16, 53, sh(bark, 1.25))
        def br(x, y, a, ln, w):
            if ln < 3:
                return
            x2 = x + math.cos(a) * ln
            y2 = y - math.sin(a) * ln
            c.line((x, y), (x2, y2), sh(bark, 1.1 if math.cos(a) < 0 else .85), w)
            br(x2, y2, a + r.uniform(.2, .6), ln * .62, max(1, w - 1))
            br(x2, y2, a - r.uniform(.2, .6), ln * .6, max(1, w - 1))
        br(17.5, 32, math.pi / 2, 14, 2)
        c.outline()
        return c
    leaf = {"oak": "#6a7a40", "sparse": "#8a8a48", "pine": "#4e6a44"}[kind]
    c.rect(16, 34, 19, 53, bark)
    c.rect(16, 34, 16, 53, sh(bark, 1.3))
    c.rect(19, 34, 19, 53, sh(bark, .7))
    if kind == "pine":
        for k in range(5):
            y0 = 8 + k * 7
            hw = 4 + k * 2.6
            for y in range(y0, y0 + 10):
                w = hw * (y - y0 + 2) / 12
                for x in range(int(18 - w), int(18 + w) + 1):
                    t = (x - (18 - w)) / max(1, 2 * w)
                    f = 1.18 - .45 * t - (y - y0) * .01
                    if r.random() < .08:
                        f *= .8
                    c.put(x, y, sh(leaf, f))
        c.outline()
        return c
    n = 9 if kind == "oak" else 6
    blobs = []
    for i in range(n):
        a = r.uniform(0, 6.28)
        d = r.uniform(0, 9)
        blobs.append((18 + math.cos(a) * d * 1.1, 22 + math.sin(a) * d * .75, r.uniform(6.5, 9) if kind == "oak" else r.uniform(5, 7)))
    for y in range(57):
        for x in range(36):
            best = None
            for (bx, by, br_) in blobs:
                dd = ((x - bx) ** 2 + (y - by) ** 2) / (br_ * br_)
                if dd <= 1 and (best is None or by > best[1]):
                    best = (bx, by, br_, dd)
            if best:
                bx, by, br_, dd = best
                lx = (x - bx) / br_
                ly = (y - by) / br_
                f = 1.0 - lx * .22 - ly * .26 - (y - 12) * .006
                if r.random() < .1:
                    f *= .82
                if r.random() < .05:
                    f *= 1.15
                q = 1.2 if f > 1.08 else (1.0 if f > .86 else (.8 if f > .7 else .66))
                c.put(x, y, sh(leaf, q))
    c.outline()
    return c


def trees():
    blob_tree(70, "oak").save("tree0")
    blob_tree(71, "sparse").save("tree1")
    blob_tree(72, "pine").save("tree2")
    blob_tree(99, "dead").save("tree_dead")
    c = Cv(21, 15, 10, 9)
    c.cyl(0, 0, .17, 0, 6, "#6a4a30", top="#c8a070")
    c.save("stump", outline=True)


# ------------------------------------------------------------------ cars (8 rotations)
LW = (-0.85, 0.45)
LN = math.hypot(*LW)
LW = (LW[0] / LN, LW[1] / LN)


def shade_n(base, nx, ny):
    d = nx * LW[0] + ny * LW[1]
    return sh(base, 0.86 + 0.16 * d)


def loft(c, bot, top, zb, zt, base, topcol=None, rim=None):
    """Prism from a bottom polygon to a (smaller) top polygon. Polygons are world (x, y)."""
    n = len(bot)
    faces = []
    for i in range(n):
        a, b = bot[i], bot[(i + 1) % n]
        ta, tb = top[i], top[(i + 1) % n]
        ex, ey = b[0] - a[0], b[1] - a[1]
        nx, ny = ey, -ex
        ln = math.hypot(nx, ny) or 1
        nx, ny = nx / ln, ny / ln
        if nx + ny <= 0.02:
            continue
        depth = (a[0] + b[0] + a[1] + b[1]) / 2
        faces.append((depth, [c.P(a[0], a[1], zb), c.P(b[0], b[1], zb), c.P(tb[0], tb[1], zt), c.P(ta[0], ta[1], zt)], shade_n(base, nx, ny)))
    faces.sort(key=lambda f: f[0])
    for _, pts, col in faces:
        c.poly(pts, col)
    c.poly([c.P(p[0], p[1], zt) for p in top], topcol if topcol else sh(base, 1.14))
    if rim:
        for i in range(n):
            a, b = top[i], top[(i + 1) % n]
            ex, ey = b[0] - a[0], b[1] - a[1]
            if ey - ex > 0.02 or (-ex + ey) < -0.02:
                pass
        # front-facing rim lines
        for i in range(n):
            a, b = top[i], top[(i + 1) % n]
            nx, ny = (b[1] - a[1]), -(b[0] - a[0])
            if nx + ny > 0.02:
                c.line(c.P(a[0], a[1], zt), c.P(b[0], b[1], zt), rim)


def rect_pts(u0, v0, u1, v1, ca, sa, ox=0, oy=0):
    out = []
    for (u, v) in ((u0, v0), (u1, v0), (u1, v1), (u0, v1)):
        out.append((ox + u * ca - v * sa, oy + u * sa + v * ca))
    return out


def car(ang, body, roof, burned, seed):
    r = random.Random(seed)
    c = Cv(120, 90, 60, 54)
    ca, sa = math.cos(ang), math.sin(ang)
    L, W = 1.35, 0.55   # half length / width (tiles)
    M = lambda u0, v0, u1, v1: rect_pts(u0, v0, u1, v1, ca, sa)
    # wheels (only the visible side matters, draw all four as dark ellipses)
    for (u, v) in ((-0.82, -W + .02), (0.82, -W + .02), (-0.82, W - .02), (0.82, W - .02)):
        x, y = u * ca - v * sa, u * sa + v * ca
        p = c.P(x, y, 4)
        flat = burned and r.random() < .5
        c.ellipse(p[0], p[1] + (1 if flat else 0), 5.5, 6 if not flat else 4.5, "#1a1818")
        c.ellipse(p[0], p[1], 2.6, 2.8, "#3a3634" if burned else "#c8c4b8")
    if burned:
        body, roof = "#4e4440", "#3a3430"
    # lower body with rounded corners (octagon)
    def octo(l, w, cut):
        pts = [(-l + cut, -w), (l - cut, -w), (l, -w + cut), (l, w - cut), (l - cut, w), (-l + cut, w), (-l, w - cut), (-l, -w + cut)]
        return [(u * ca - v * sa, u * sa + v * ca) for (u, v) in pts]
    loft(c, octo(L, W, .12), octo(L, W, .12), 3, 9, body)
    loft(c, octo(L, W, .12), octo(L - .06, W - .05, .14), 9, 12, sh(body, 1.04))
    # chrome strip
    chrome = "#5a5048" if burned else "#e8e8dc"
    side = W if (-sa + ca) > 0 else -W
    a = c.P(-L * ca - side * sa, -L * sa + side * ca, 7)
    b = c.P(L * ca - side * sa, L * sa + side * ca, 7)
    c.line(a, b, chrome)
    # tail fins at the rear corners
    for v in (-W + .06, W - .06):
        p0 = (-L * ca - v * sa, -L * sa + v * ca)
        p1 = (-(L - .45) * ca - v * sa, -(L - .45) * sa + v * ca)
        c.poly([c.P(p0[0], p0[1], 12), c.P(p1[0], p1[1], 12), c.P(p0[0], p0[1], 15.5)], sh(body, 1.1), outline=sh(body, .7))
    # cabin
    cab = M(-0.5, -W + .1, 0.4, W - .1)
    ctop = M(-0.32, -W + .2, 0.18, W - .2)
    glass = "#2a2420" if burned else "#3e5a66"
    loft(c, cab, ctop, 12, 18.5, glass, topcol=sh(roof, .92) if not burned else "#2e2620")
    if not burned:   # glint on the glass
        g = c.P(0.2 * ca - side * .9 * sa, 0.2 * sa + side * .9 * ca, 16)
        c.line(g, (g[0] + 3, g[1] - 2), "#a8c8d0")
    # headlights / bumpers
    for v in (-W + .14, W - .14):
        p = c.P(L * ca - v * sa, L * sa + v * ca, 8)
        c.put(p[0], p[1], "#f2e8b0" if not burned else "#3a3430")
    # rust and burn noise over the body
    for y in range(c.h):
        for x in range(c.w):
            px = c.px[x, y]
            if px[3] == 0:
                continue
            n = math.sin(x * .31 + y * .52 + ang * 3) + math.sin(x * .13 - y * .37 + seed) * 1.2 + r.uniform(-.4, .4)
            if burned:
                if n > 1.7:
                    c.px[x, y] = mix(px, "#7a4a2a", .5) + (255,)
                elif n > .6 and r.random() < .25:
                    c.px[x, y] = mix(px, "#1e1a18", .6) + (255,)
            elif n > 1.85:
                c.px[x, y] = mix(px, "#7a4024", .7) + (255,)
            elif n > 1.6:
                c.px[x, y] = mix(px, "#9a5a2e", .45) + (255,)
    c.outline()
    return c


CAR_COLS = {"teal": ("#5e9a90", "#d8d0b8"), "red": ("#a85444", "#d8ccb0"),
            "yellow": ("#c8a858", "#7a5a3a"), "burned": (None, None)}


def cars():
    for name, (body, roof) in CAR_COLS.items():
        for k in range(8):
            car(k * math.pi / 4, body, roof, body is None, k * 31 + len(name)).save(f"car_{name}_{k}")


# ------------------------------------------------------------------ small props
def crate_like(name, size, col, open_=False, metal=False):
    c = Cv(26, 26, 13, 19)
    hs = size / 2
    def tex(face, u, v, cc):
        if metal:
            return sh(cc, .85) if (int(u * 30) % 6 == 0 and face != 't') else cc
        if face == 't' and open_:
            return "#2e2218" if 0.06 < u < size - .06 and 0.06 < v < size - .06 else cc
        if face != 't' and (int(v) % 4 == 0):
            return sh(cc, .78)
        return cc
    c.box(-hs, -hs, hs, hs, 0, 9 if not metal else 10, col, tex)
    c.save(name, outline=True)


def props():
    crate_like("crate", .4, "#b08a4e")
    crate_like("crate_open", .4, "#b08a4e", open_=True)
    crate_like("cache", .45, "#8a4a3a", metal=True)
    crate_like("cache_open", .45, "#5a3a30", metal=True)
    c = Cv(14, 14, 7, 12)
    c.ellipse(7, 8, 5, 4, "#6a5a3a"); c.ellipse(6, 7, 3, 2, "#8a7a52"); c.rect(5, 2, 8, 4, "#7a6a4a")
    c.save("bag", outline=True)
    c = Cv(48, 46, 24, 36)                         # tent: A-frame
    cl = "#8a9a5a"
    c.poly([c.P(-.42, -.42, 0), c.P(.42, -.42, 0), c.P(.42, 0, 16), c.P(-.42, 0, 16)], sh(cl, .8))
    c.poly([c.P(-.42, 0, 16), c.P(.42, 0, 16), c.P(.42, .42, 0), c.P(-.42, .42, 0)], sh(cl, 1.05))
    c.poly([c.P(.42, -.42, 0), c.P(.42, .42, 0), c.P(.42, 0, 16)], sh(cl, .72))
    c.poly([c.P(.42, -.1, 0), c.P(.42, .1, 0), c.P(.42, 0, 9)], "#2a2418")
    c.save("tent", outline=True)
    c = Cv(36, 32, 18, 22)
    c.box(-.3, -.18, .3, .18, 0, 10, "#9a7a4a")
    c.box(-.2, -.1, -.05, .05, 10, 13, "#8a8a8a")
    c.box(.05, -.12, .2, .0, 10, 11, "#c84a2a")
    c.save("workbench", outline=True)
    c = Cv(21, 26, 10, 20)
    c.cyl(0, 0, .17, 0, 12, "#4a6a8a", bands=((3, "#2e4a6a"), (9, "#2e4a6a")))
    c.save("barrel", outline=True)
    c = Cv(36, 80, 18, 72)                          # watchtower
    for (x, y) in ((-.25, -.25), (.25, -.25), (-.25, .25), (.25, .25)):
        c.box(x - .04, y - .04, x + .04, y + .04, 0, 34, "#6a4a30")
    c.line(c.P(-.25, .25, 4), c.P(.25, .25, 30), "#5a3e28")
    c.box(-.34, -.34, .34, .34, 34, 38, "#8a6a44")
    c.box(-.34, .3, .34, .34, 38, 44, "#7a5a3a")
    c.box(.3, -.34, .34, .34, 38, 44, "#7a5a3a")
    c.save("tower", outline=True)
    for f in range(2):
        c = Cv(24, 27, 12, 23)
        for k in range(7):
            a = k / 7 * 6.283
            p = c.P(math.cos(a) * .2, math.sin(a) * .2, 0)
            c.ellipse(p[0], p[1], 1.6, 1.2, "#8a8478")
        c.line((6, 21), (18, 21), "#5e4430", 2)
        for yy in range(11):
            for xx in range(-5, 6):
                if abs(xx) <= 5 - yy // 2 + (1 if (xx + yy + f) % 3 == 0 else 0):
                    col = "#fff0a0" if abs(xx) < 2 and yy < 5 else ("#f2b040" if abs(xx) < 4 else "#e06a20")
                    c.put(12 + xx + (f if yy > 6 else 0), 20 - yy - f, col)
        c.save(f"campfire{f}")
    for name, col in (("flag_main", "#f2c36b"), ("flag", "#6fae4a"), ("flag_raider", "#a83a2a")):
        c = Cv(15, 45, 1, 44)
        c.rect(1, 0, 2, 44, "#5a4a3a"); c.rect(1, 0, 1, 44, "#7a6a54")
        for y in range(1, 9):
            for x in range(3, 14 - (y % 3)):
                c.put(x, y, sh(col, 1.1 - (x - 3) * .03 - (0.12 if (x + y) % 5 == 0 else 0)))
        c.save(name, outline=True)
    c = Cv(5, 23, 2, 21)
    c.rect(1, 1, 3, 21, "#7a5a3a"); c.rect(1, 1, 1, 21, "#9a7a54"); c.rect(1, 0, 3, 0, "#c8b890")
    c.save("post")
    c = Cv(24, 48, 12, 44)                          # hand pump on a well slab
    c.box(-.25, -.25, .25, .25, 0, 4, "#8a8478")
    c.box(-.05, -.05, .05, .05, 4, 22, "#4a5a5a")
    c.line(c.P(0, 0, 22), c.P(.25, -.15, 18), "#3a4a4a", 2)
    c.save("pump", outline=True)


# ------------------------------------------------------------------ debris
def debris():
    for i in range(3):
        r = random.Random(40 + i)
        c = Cv(42, 30, 21, 22)
        cols = [("#8a8478", "#6e6a60", "#a8a294"), ("#9a5a44", "#7a4434", "#b06a50"), ("#7a7064", "#5e564a", "#948a7a")][i]
        for k in range(16):
            x, y = r.uniform(-.45, .45), r.uniform(-.3, .3)
            s = r.uniform(.05, .13)
            c.box(x - s, y - s, x + s, y + s, 0, r.uniform(2, 7), r.choice(cols))
        c.save(f"rubble{i}", outline=True)
    r = random.Random(7)
    c = Cv(36, 24, 18, 18)
    for k in range(9):
        x, y = r.uniform(-.35, .35), r.uniform(-.2, .2)
        c.box(x - .1, y - .04, x + .1, y + .04, 0, 2.5, r.choice(["#9a4a34", "#8a4430", "#a85a40"]))
    c.save("bricks", outline=True)
    c = Cv(30, 15, 15, 8)
    for k in range(7):
        x, y = r.uniform(-8, 8), r.uniform(-3, 3)
        c.rect(15 + x, 8 + y, 18 + x, 9 + y, r.choice(["#d8d0b8", "#c8c0a8", "#e8e0d0"]))
    c.save("papers")
    c = Cv(24, 21, 12, 17)
    c.ellipse(12, 12, 7, 5, "#2e2e32"); c.ellipse(10, 10, 4, 3, "#46464c"); c.rect(11, 5, 13, 7, "#2e2e32")
    c.save("trashbag", outline=True)
    c = Cv(24, 18, 12, 13)
    c.ellipse(12, 10, 8, 5, "#1e1c1c"); c.ellipse(12, 10, 4, 2.4, "#4a4440"); c.ellipse(12, 10, 2.5, 1.2, "#1e1c1c")
    c.save("tire", outline=True)
    c = Cv(21, 29, 10, 23)
    c.cyl(0, 0, .16, 0, 13, "#8a5a3a", bands=((3, "#6a3a24"), (10, "#6a3a24")))
    c.save("barrel_rust", outline=True)
    c = Cv(21, 29, 10, 23)
    c.cyl(0, 0, .16, 0, 13, "#c8b040", bands=((4, "#2a2420"), (9, "#2a2420")))
    c.ellipse(10, 6, 3, 1.5, "#8ae04a"); c.put(12, 10, "#8ae04a"); c.put(12, 11, "#6ac03a")
    c.save("barrel_toxic", outline=True)
    for ax in "xy":
        c = Cv(51, 33, 25, 24)
        if ax == "x":
            c.box(-.5, -.1, .5, .1, 0, 9, "#a8a294")
            c.box(-.5, -.04, .5, .04, 9, 12, "#bab4a6")
        else:
            c.box(-.1, -.5, .1, .5, 0, 9, "#a8a294")
            c.box(-.04, -.5, .04, .5, 9, 12, "#bab4a6")
        c.save(f"jersey_{ax}", outline=True)
    c = Cv(27, 18, 13, 12)
    c.ellipse(9, 9, 3, 2.5, "#d8d0b8"); c.put(8, 9, "#2a2420"); c.put(10, 9, "#2a2420")
    c.line((13, 11), (22, 9), "#c8c0a8", 2); c.line((15, 13), (21, 14), "#c8c0a8")
    c.save("bones", outline=True)
    c = Cv(48, 21, 24, 11)
    c.ellipse(24, 11, 18, 7, "#4a6a2a"); c.ellipse(22, 10, 12, 4, "#7ac03a"); c.ellipse(20, 9, 5, 2, "#b8f070")
    c.save("puddle_toxic")
    c = Cv(36, 33, 18, 25)
    for k in range(5):
        c.line(c.P(-.3 + k * .15, -.18, 4), c.P(-.3 + k * .15, -.18, 14), "#9a9a98")
    c.box(-.32, -.2, .32, .2, 4, 6, "#8a8a88")
    c.line(c.P(-.32, .2, 14), c.P(.32, .2, 14), "#b8b8b4")
    c.line(c.P(-.32, -.2, 14), c.P(-.32, .2, 14), "#b8b8b4")
    c.ellipse(*c.P(-.25, .2, 1), 2, 2, "#2a2424"); c.ellipse(*c.P(.25, .2, 1), 2, 2, "#2a2424")
    c.save("cart", outline=True)
    c = Cv(27, 96, 6, 92)                           # power pole with crossarm
    c.rect(4, 4, 8, 92, "#5a4434"); c.rect(4, 4, 4, 92, "#7a5e48")
    c.rect(0, 9, 26, 11, "#4a3a2c")
    for x in (1, 13, 24):
        c.rect(x, 7, x + 1, 8, "#a8b0a8")
    c.save("pole", outline=True)
    c = Cv(33, 48, 16, 45)                          # radiation warning sign
    c.rect(15, 15, 17, 45, "#6a6a6a")
    c.poly([(16, 1), (31, 16), (16, 31), (1, 16)], "#e0c040", outline="#2a2420")
    c.ellipse(16, 16, 3, 3, "#2a2420")
    for a in (0, 2.09, 4.19):
        c.poly([(16, 16), (16 + math.cos(a - .5) * 9, 16 + math.sin(a - .5) * 9), (16 + math.cos(a + .5) * 9, 16 + math.sin(a + .5) * 9)], "#2a2420")
    c.ellipse(16, 16, 1.5, 1.5, "#e0c040")
    c.save("sign_rad")
    r = random.Random(3)
    c = Cv(36, 24, 18, 21)
    def twig(x, y, a, ln):
        if ln < 2:
            return
        x2, y2 = x + math.cos(a) * ln, y - math.sin(a) * ln
        c.line((x, y), (x2, y2), "#6a5a40")
        twig(x2, y2, a + r.uniform(.3, .7), ln * .6)
        twig(x2, y2, a - r.uniform(.3, .7), ln * .6)
    for a in (1.2, 1.6, 2.0):
        twig(18, 21, a, 8)
    c.save("deadbush", outline=True)
    c = Cv(48, 36, 24, 26)                          # chain-link fence section
    for k in range(3):
        p0 = c.P(-.5 + k * .5, 0, 0)
        c.line(p0, (p0[0], p0[1] - 20), "#7a7a78")
    for y in range(18):
        for xx in range(-24, 25):
            if (xx + y * 2) % 5 == 0 or (xx - y * 2) % 5 == 0:
                p = c.P(xx / 48, 0, 0)
                c.put(p[0], p[1] - 1 - y, "#9a9a96")
    c.save("fence")
    for i in range(3):
        r = random.Random(60 + i)
        c = Cv(12, 11, 6, 10)
        for k in range(5 + i):
            x = r.randint(2, 9)
            c.line((x, 10), (x + r.randint(-2, 2), 10 - r.randint(3, 7)), r.choice(["#8a9a5a", "#6a7a44", "#a8a868", "#7a7040"]))
        c.save(f"tuft{i}")


# ------------------------------------------------------------------ retro street furniture & signs
def neon_tube(c, pts, col):
    for i in range(len(pts) - 1):
        c.line(pts[i], pts[i + 1], col, 2)


def street():
    # retro street lamp: curved arm, round globe
    c = Cv(27, 102, 6, 99)
    c.rect(4, 12, 7, 99, "#4a5054"); c.rect(4, 12, 4, 99, "#6a7074")
    c.rect(2, 94, 9, 99, "#3a4044")
    for k in range(12):
        a = k / 11 * 1.8
        c.put(6 + math.sin(a) * 12, 12 - math.cos(a) * 9 + 6, "#4a5054")
        c.put(6 + math.sin(a) * 12, 13 - math.cos(a) * 9 + 6, "#4a5054")
    c.ellipse(20, 14, 4, 3, "#f0e6b8"); c.rect(17, 11, 23, 11, "#3a4044")
    c.save("lamp", outline=True)
    # fire hydrant
    c = Cv(15, 26, 7, 23)
    c.cyl(0, 0, .09, 0, 10, "#c84a2a", top="#e06a40")
    c.rect(2, 10, 12, 12, "#b03a24"); c.ellipse(7, 7, 3, 2, "#e8783a")
    c.save("hydrant", outline=True)
    # mailbox on a post
    c = Cv(18, 33, 9, 30)
    c.rect(8, 12, 9, 30, "#6a4a30")
    c.box(-.12, -.06, .12, .06, 13, 19, "#3a5a8a")
    c.save("mailbox", outline=True)
    # cola vending machine (made-up brand)
    for ax in "xy":
        c = Cv(36, 60, 18, 48)
        if ax == "x":
            c.box(-.22, -.14, .22, .14, 0, 28, "#b83a2a")
            p = c.P(-.18, .14, 25)
            text(c, int(p[0]) + 1, int(p[1]) + 1, "ATOM", "#f0e8d0", shear=.5)
            for k in range(3):
                q = c.P(-.14 + k * .1, .14, 11)
                c.rect(q[0], q[1] - 6, q[0] + 2, q[1] - 2, "#e8c040")
        else:
            c.box(-.14, -.22, .14, .22, 0, 28, "#b83a2a")
            p = c.P(.14, -.18, 25)
            text(c, int(p[0]) - 14, int(p[1]) + 8, "ATOM", "#f0e8d0", shear=-.5)
            for k in range(3):
                q = c.P(.14, -.14 + k * .1, 11)
                c.rect(q[0] - 2, q[1] - 6, q[0], q[1] - 2, "#e8c040")
        c.save(f"vending_{ax}", outline=True)
    # phone booth
    c = Cv(33, 69, 16, 57)
    c.box(-.18, -.18, .18, .18, 0, 34, "#3a6a6a", tex=lambda f, u, v, cc: ("#2e3e44" if (f != 't' and 6 < v < 28 and .05 < u < .31) else cc))
    c.box(-.2, -.2, .2, .2, 34, 37, "#2e5656")
    c.save("phonebooth", outline=True)
    # bus-stop bench
    c = Cv(42, 30, 21, 22)
    c.box(-.4, -.08, .4, .08, 0, 5, "#7a5a3a")
    c.box(-.4, -.1, .4, -.06, 5, 11, "#8a6a44")
    c.save("bench", outline=True)
    # newspaper box
    c = Cv(18, 27, 9, 22)
    c.box(-.1, -.1, .1, .1, 0, 11, "#3a7a5a")
    c.save("newsbox", outline=True)
    # broken robot husk: round body, dome head, tripod legs (generic retro bot)
    c = Cv(36, 45, 18, 38)
    c.line(c.P(-.15, .1, 0), c.P(-.05, 0, 10), "#5a5a58", 2)
    c.line(c.P(.15, .1, 0), c.P(.05, 0, 10), "#5a5a58", 2)
    c.cyl(0, 0, .18, 10, 20, "#8a9090", bands=((14, "#6a7070"),))
    c.ellipse(*c.P(0, 0, 23), 7, 5, "#a0a8a8")
    c.ellipse(*c.P(0, .05, 23), 2.5, 2, "#e04a2a")
    c.line(c.P(.15, .1, 17), c.P(.4, .25, 6), "#6a7070", 2)
    c.save("robot", outline=True)
    # gas pump (retro, rounded top, made-up brand colours)
    c = Cv(27, 54, 13, 44)
    c.box(-.15, -.12, .15, .12, 0, 4, "#8a8478")
    c.box(-.1, -.08, .1, .08, 4, 24, "#d8d0c0", tex=lambda f, u, v, cc: (sh("#3e8a86", .97 if f == 's' else .75) if 13 < v < 18 else cc))
    c.ellipse(*c.P(0, 0, 26), 4, 3, "#e84a3a")
    p = c.P(-.05, .08, 20)
    c.rect(p[0], p[1] - 2, p[0] + 3, p[1], "#2e3e3e")
    c.save("fuelpump", outline=True)
    # canopy pillar
    c = Cv(15, 72, 7, 68)
    c.box(-.06, -.06, .06, .06, 0, 42, "#e2dccb", tex=lambda f, u, v, cc: (sh("#3e8a86", .9) if 34 < v < 38 else cc))
    c.save("pillar", outline=True)
    # rooftop / ground props
    c = Cv(36, 30, 18, 20)
    c.box(-.28, -.2, .28, .2, 0, 9, "#9a9a92", tex=lambda f, u, v, cc: (sh(cc, .75) if f == 's' and int(u * 40) % 3 == 0 and 2 < v < 7 else cc))
    c.ellipse(*c.P(0, 0, 9), 6, 3, "#4a4a46")
    c.save("ac_unit", outline=True)
    c = Cv(15, 21, 7, 16)
    c.cyl(0, 0, .07, 0, 7, "#8a8a84", top="#2a2a28")
    c.save("roof_vent", outline=True)
    c = Cv(42, 66, 21, 54)
    for (x, y) in ((-.2, -.2), (.2, -.2), (-.2, .2), (.2, .2)):
        c.box(x - .03, y - .03, x + .03, y + .03, 0, 12, "#5a4a3a")
    c.cyl(0, 0, .3, 12, 30, "#8a6a4a", bands=((16, "#5a4434"), (24, "#5a4434")))
    c.poly([c.P(-.3, -.3, 30), c.P(.3, -.3, 30), c.P(.3, .3, 30), c.P(-.3, .3, 30), c.P(0, 0, 38)][0:3] + [c.P(0, 0, 38)], "#6a5040")
    c.save("roof_tank", outline=True)
    c = Cv(21, 72, 10, 66)
    c.line((10, 66), (10, 2), "#6a6a6a")
    for y in (14, 28, 42):
        c.line((4, y), (16, y), "#6a6a6a")
    c.put(10, 1, "#e84a3a")
    c.save("antenna")
    # water tower on legs with a dome (big landmark)
    c = Cv(84, 180, 42, 168)
    for (x, y) in ((-.5, -.5), (.5, -.5), (-.5, .5), (.5, .5)):
        c.box(x - .05, y - .05, x + .05, y + .05, 0, 70, "#6a6e70")
    c.line(c.P(-.5, .5, 10), c.P(.5, .5, 60), "#5a5e60")
    c.line(c.P(.5, .5, 10), c.P(-.5, .5, 60), "#5a5e60")
    c.cyl(0, 0, .7, 70, 96, "#c8c4b0", bands=((83, "#3e8a86"), (84, "#3e8a86")))
    for k in range(10):
        p = c.P(0, 0, 96 + k * 1.2)
        c.ellipse(p[0], p[1], .7 * HW * 1.414 * (1 - k / 10), .7 * HH * 1.414 * (1 - k / 10), sh("#c8c4b0", 1.1 - k * .02))
    c.save("watertower", outline=True)
    # billboards (one per facing). Faces south (x) or east (y). Made-up ads.
    for ax in "xy":
        c = Cv(132, 132, 66, 110)
        poles = ((-.9, 0), (.9, 0)) if ax == "x" else ((0, -.9), (0, .9))
        for (x, y) in poles:
            c.box(x - .04, y - .04, x + .04, y + .04, 0, 40, "#5a4a3a")
        def board(f, u, v, cc):
            if f == 't':
                return cc
            if v < 2 or v > 34 or u < .04 or u > 2.36:
                return sh("#4a3a2a", .97 if f == 's' else .75)
            band = "#e0d4b0" if v > 16 else ("#3e8a86" if v > 8 else "#c84a3a")
            n = noise(u * 9, v * .4, 1, 3)
            if n > .7:
                band = mix(band, "#8a7a5a", .5)
            return sh(band, .97 if f == 's' else .78)
        if ax == "x":
            c.box(-1.2, -.04, 1.2, .04, 40, 76, "#e0d4b0", tex=board)
            p = c.P(-0.9, .04, 70)
            text(c, int(p[0]), int(p[1]), "THE FUTURE!", "#c84a3a", shear=.5)
        else:
            c.box(-.04, -1.2, .04, 1.2, 40, 76, "#e0d4b0", tex=board)
            p = c.P(.04, 0.9, 70)
            text(c, int(p[0]), int(p[1]) + 1, "THE FUTURE!", "#c84a3a", shear=-.5)
        c.save(f"billboard_{ax}", outline=True)
    # picket fence sections
    for ax in "xy":
        c = Cv(30, 30, 15, 19) if True else None
        for k in range(5):
            u = -.4 + k * .2
            x, y = (u, 0) if ax == "x" else (0, u)
            p = c.P(x, y, 0)
            c.rect(p[0], p[1] - 10, p[0] + 1, p[1], "#e0d8c4")
            c.put(p[0], p[1] - 11, "#c8c0ac")
        a = c.P(-.5, 0, 6) if ax == "x" else c.P(0, -.5, 6)
        b = c.P(.5, 0, 6) if ax == "x" else c.P(0, .5, 6)
        c.line(a, b, "#c8c0ac")
        c.save(f"picket_{ax}", outline=True)
    # shrub
    r = random.Random(11)
    c = Cv(27, 21, 13, 18)
    for k in range(6):
        c.ellipse(13 + r.uniform(-6, 6), 12 + r.uniform(-3, 3), r.uniform(3, 5), r.uniform(2.5, 4), sh("#5a6a3a", r.uniform(.85, 1.15)))
    c.save("shrub", outline=True)


# ------------------------------------------------------------------ standalone neon signs
def signs():
    # tall motel sign: arrow-shaped board on a pole
    c = Cv(54, 132, 12, 126)
    c.rect(10, 40, 13, 126, "#5a5a5a"); c.rect(10, 40, 10, 126, "#7a7a7a")
    c.poly([(2, 4), (44, 4), (52, 22), (44, 40), (2, 40)], "#2e4e5a", outline="#1e2a30")
    text(c, 6, 9, "STAR", "#f2e6a0")
    text(c, 6, 17, "LITE", "#f2e6a0")
    text(c, 6, 28, "MOTEL", "#ff6a5a")
    neon_tube(c, [(4, 6), (42, 6), (49, 22), (42, 38), (4, 38), (4, 6)], "#5ae0d8")
    c.save("sign_motel", outline=True)
    # gas station pole sign with a comet
    c = Cv(48, 150, 24, 144)
    c.rect(22, 50, 25, 144, "#5a5a5a"); c.rect(22, 50, 22, 144, "#7a7a7a")
    c.ellipse(24, 26, 22, 22, "#e2dccb")
    c.ellipse(24, 26, 19, 19, "#3e8a86")
    text(c, 10, 22, "COMET", "#f2e6c8")
    c.line((30, 12), (40, 6), "#f2c040", 2); c.line((28, 14), (36, 12), "#f2c040")
    c.ellipse(29, 13, 2.5, 2.5, "#fff0a0")
    c.save("sign_gas", outline=True)
    # rooftop diner sign (faces south-east, readable from the camera)
    c = Cv(84, 54, 42, 50)
    c.rect(20, 34, 22, 50, "#4a4a4a"); c.rect(62, 34, 64, 50, "#4a4a4a")
    c.poly([(2, 10), (82, 10), (82, 34), (2, 34)], "#2a2a3a", outline="#1a1a24")
    text(c, 10, 14, "ORBIT", "#ff7a6a")
    text(c, 40, 24, "DINER", "#7ae8e0")
    c.ellipse(70, 16, 4, 4, "#f2c040")
    c.line((62, 16), (78, 16), "#f2c040")
    c.save("sign_diner", outline=True)
    # simple flat wall signs for shops; facing south (x) or east (y)
    for word, bg, fg in (("GROCERY", "#3e6a4a", "#f2e6c8"), ("HARDWARE", "#8a3a2a", "#f2e6c8"), ("CLINIC", "#e2dccb", "#c84a3a"),
                         ("RADIO", "#2a3a5a", "#f2c040"), ("BAR", "#5a2a3a", "#ff8a7a"), ("CITY HALL", "#6a6a60", "#f2e6c8"),
                         ("GARAGE", "#4a4a40", "#f2c040"), ("FACTORY", "#4a4a40", "#e8e0c0")):
        w = text_w(word) + 6
        for ax in "xy":
            hh = 11
            if ax == "x":
                c = Cv(w + 4, hh + w // 2 + 6, 2, hh + 2)
                for i in range(w):
                    for j in range(hh):
                        c.put(2 + i, 2 + j + i // 2, sh(bg, 1.0 if 0 < j < hh - 1 else .7))
                text(c, 5, 5, word, fg, shear=.5)
            else:
                c = Cv(w + 4, hh + w // 2 + 6, w + 2, hh + 2)
                for i in range(w):
                    for j in range(hh):
                        c.put(w + 1 - i, 2 + j + i // 2, sh(bg, .82 if 0 < j < hh - 1 else .6))
                # text reads left->right going up-left... draw mirrored so it reads correctly on an east face
                tx = 3
                for k, ch in enumerate(word):
                    pass
                text(c, 3, 5 + (w - 6) // 2, word, fg, shear=-.5)
            c.save(f"wsign_{word.lower().replace(' ', '')}_{ax}", outline=True)
    # awnings for shopfronts (one tile long)
    for col in ("#c84a3a", "#3e8a86", "#d8b040"):
        for ax in "xy":
            c = Cv(30, 30, 2 if ax == "x" else 26, 12)
            for i in range(25):
                for j in range(8):
                    stripe = (i // 4) % 2 == 0
                    cc = col if stripe else "#e8e0d0"
                    if ax == "x":
                        c.put(2 + i, 12 + j + i // 2 - 4 + j // 2, sh(cc, 1.05 - j * .03))
                    else:
                        c.put(26 - i, 12 + j + i // 2 - 4 + j // 2, sh(cc, .85 - j * .03))
            c.save(f"awning_{col[1:]}_{ax}", outline=True)


def build():
    trees()
    cars()
    props()
    debris()
    street()
    signs()
