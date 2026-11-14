"""Building art: floor tiles, roof textures, thin walls in many styles, furniture."""
import math, random
from px2 import Cv, sh, mix, hx, lit3, noise, HW, HH, S
from PIL import Image

WALL_H = 28
# index -> (style, base colour, trim colour).  MUST match BuildingView.PAL_INFO / World palette use.
WALLS = [
    ("siding", "#7fa596", "#e8e0c8"),      # 0 seafoam
    ("siding", "#c88c74", "#f0e0c0"),      # 1 salmon
    ("siding", "#d6c79a", "#8a5a3a"),      # 2 butter
    ("siding", "#8ea6b8", "#e8e4d4"),      # 3 powder blue
    ("plaster", "#cfc4a8", "#a89878"),     # 4 interior
    ("tin", "#8a7a66", "#6a5a48"),         # 5 tin shack
    ("brick", "#8e4a3a", "#c8b8a0"),       # 6 red brick
    ("brick", "#a8885e", "#e0d4b4"),       # 7 tan brick
    ("concrete", "#9a978c", "#c8c4b4"),    # 8 municipal concrete
    ("streamline", "#e2dccb", "#c24a3a"),  # 9 diner (white, red band)
    ("streamline", "#e2dccb", "#3e8a86"),  # 10 gas / motel (white, teal band)
    ("panel", "#7e8a7c", "#a8b0a0"),       # 11 factory panels
]
ROOFS = ["#6a4a3e", "#4a5058", "#7a3a2e", "#3e5a4e", "#8a7a5a"]   # shingle colours


def wall_col(style, base, trim, u, v, seed=0, period=None):
    """Colour of a wall at (u tiles along, v logical px up). Before face shading."""
    b = hx(base)
    n = noise(u * 7 + seed, v * .25, 1, seed)
    if style == "siding":
        row = v % 4
        c = sh(b, .8) if row < .8 else (sh(b, 1.06) if row > 3.2 else b)
        if n > .72:
            c = mix(c, "#9a8a6a", .55)     # paint peeled to grey wood
    elif style == "plaster":
        c = sh(b, .97 + n * .05)
        if v < 2.5:
            c = sh(trim, .9)
    elif style == "tin":
        k = int(u * 48) % 4
        c = sh(b, [1.1, 1.0, .85, .95][k])
        if n > .4:
            c = mix(c, "#8a4a2a", .5 + (n - .4))
    elif style == "brick":
        row = int(v // 2.5)
        off = 0.09 if row % 2 else 0
        bu = (u + off) % 0.18
        if v % 2.5 < .55 or bu < .02:
            c = sh(trim, .82)
        else:
            k = (int((u + off) / .18) * 7 + row * 3) % 5
            c = sh(b, [1.0, .92, 1.06, .88, .97][k])
    elif style == "concrete":
        c = sh(b, .97 + n * .06)
        if (u * 4) % 1 < .04 or v % 8 < .5:
            c = sh(b, .78)
        if n > .6:
            c = mix(c, "#6a6458", .35)
    elif style == "streamline":
        c = b
        if 21 <= v <= 24:
            c = hx(trim)
        elif 18.5 <= v < 19.5 or v < 2.0:
            c = hx("#b8b8b0") if v >= 2 else sh(trim, .8)
        if n > .75:
            c = mix(c, "#a89a7a", .4)
    elif style == "panel":
        c = sh(b, 1.0 + (.06 if (u * 8) % 1 < .5 else -.02))
        if (u * 8) % 1 < .06:
            c = sh(b, .75)
        if n > .5:
            c = mix(c, "#7a5a3a", .35)
    else:
        c = b
    # grime near the ground, sun-bleach near the top
    if v < 5:
        c = sh(c, .78 + v * .044)
    return c


def wall(axis, pi, mode, hh=WALL_H):
    style, base, trim = WALLS[pi]
    ax = 2 if axis == "x" else 26
    c = Cv(28, 45 + 12 + 3, ax, 45)
    r = random.Random(pi * 31 + len(mode) + (axis == "x"))
    shade = .97 if axis == "x" else .74

    def fn(u, v):
        col = wall_col(style, base, trim, u, v, seed=pi)
        tr = hx(trim) if style != "streamline" else hx("#b8b8b0")
        if mode in ("win", "broken", "boarded") and .26 <= u <= .74 and 11 <= v <= 22:
            fr = u < .3 or u > .7 or v < 12 or v > 21
            if fr:
                col = tr
            elif mode == "broken":
                col = hx("#9ab0b8") if ((int(u * 48) * 7 + int(v) * 3) % 11 == 0 or (v < 13.5 and int(u * 48) % 3 == 0)) else hx("#1e1816")
            elif mode == "boarded":
                col = hx("#4a3424") if int(v - u * 10) % 4 == 0 else hx("#7a5a3a")
            else:
                col = hx("#2e4250")
                if abs(u - .5) < .02 or abs(v - 16.5) < .4:
                    col = tr
                elif (u * 48 + v * 1.5) % 14 < 2:
                    col = hx("#7a9aa8")
            # little sill under the window
            if 10 <= v < 11:
                col = sh(tr, .8)
        if mode == "shop" and .06 <= u <= .94 and 2 <= v <= 23:
            fr = u < .1 or u > .9 or v < 3 or v > 22 or abs(u - .5) < .02
            col = tr if fr else (hx("#7a9aa8") if (u * 48 + v * 1.5) % 20 < 3 else hx("#2e4250"))
            if not fr and r.random() < .004:
                col = hx("#c8d8e0")
        if mode.startswith("door") and .3 <= u <= .7 and v <= 19:
            fr = u < .34 or u > .66 or v > 18
            leaf = hx("#7a4a30") if style != "streamline" else hx("#3e8a86")
            col = tr if fr else leaf
            if not fr:
                if mode in ("door", "doorlock", "doorbar", "doorsealed"):
                    if abs(u - .6) < .02 and 8 < v < 10:
                        col = hx("#e8d080")
                    if 12 < v < 16 and .4 < u < .6:
                        col = hx("#3a4a50")
                    if int(u * 48) % 4 == 0:
                        col = sh(leaf, .85)
                elif mode == "dooropen":
                    col = hx("#1a1410") if u > .4 else sh(leaf, .8)     # door swung inward, edge visible at the hinge
                    if u > .4 and v < 2:
                        col = hx("#3a2e24")
                elif mode == "doorbroken":
                    jag = (int(u * 48) * 7 + int(v) * 3) % 5
                    col = hx("#1a1410")
                    if (u < .4 and jag < 3) or (v < 3 and jag < 2) or (u > .6 and v > 12 and jag == 0):
                        col = sh(leaf, .75)
            if mode == "doorlock":
                if abs(v - 9.5) < .6 and .28 <= u <= .72 and int(u * 48) % 2 == 0:
                    col = hx("#9a9a94")
                if .46 < u < .54 and 7 < v < 10.5:
                    col = hx("#c8a040") if v > 7.6 else hx("#7a6020")
            if mode in ("doorbar", "doorsealed"):
                boards = (3, 9.5, 16) if mode == "doorbar" else (1.5, 4.5, 7.5, 10.5, 13.5, 16.5)
                for k, bz in enumerate(boards):
                    tilt = (u - .5) * (6 if k % 2 else -6)
                    if abs(v - bz - tilt) < 1.2 and .26 <= u <= .74:
                        col = sh("#8a6a44" if k % 2 else "#7a5a3a", .9 if int(u * 48) % 9 else .6)
        if mode == "garage" and .06 <= u <= .94 and v <= 21:
            col = sh("#9a9a90" if style != "tin" else "#8a7a66", 1.0 if int(v) % 3 else .78)
            if u < .09 or u > .91 or v > 20:
                col = tr
            if noise(u * 9, v * .3, 1, 5) > .6:
                col = mix(col, "#8a4a2a", .5)
        if mode == "cracked":
            cx = .5 + .08 * math.sin(v * .7)
            if abs(u - cx) < .015 and 4 < v < hh - 3:
                col = hx("#2a1e18")
            if .1 < u < .3 and 4 < v < 10 and (int(u * 48) + int(v)) % 2 == 0:
                col = sh(col, .7)
        # trim at the top of the wall
        if v > hh - 1.5:
            col = sh(trim, 1.0) if style != "brick" else sh(trim, .9)
        return sh(col, shade)

    if mode == "stub":
        hts = []
        h = 10.0
        for i in range(25):
            h = max(3, min(20, h + r.randint(-3, 3)))
            hts.append(h)

        def stub_fn(u, v):
            k = min(24, int(u * 24))
            if v > hts[k]:
                return None
            if v > hts[k] - 1.2:
                return sh(base, .55)
            return sh(wall_col(style, base, trim, u, v, seed=pi), shade)
        if axis == "x":
            c.face_s(0, 1, 0, 0, 20, stub_fn)
        else:
            c.face_e(0, 0, 1, 0, 20, stub_fn)
        return c
    if axis == "x":
        c.face_s(0, 1, 0, 0, hh, fn)
        c.face_top(0, -.05, 1, .02, hh, lambda u, v: sh(trim, 1.12))
    else:
        c.face_e(0, 0, 1, 0, hh, fn)
        c.face_top(-.05, 0, .02, 1, hh, lambda u, v: sh(trim, 1.12))
    return c


def walls():
    for pi in range(len(WALLS)):
        for axis in "xy":
            for mode in ("plain", "win", "broken", "boarded", "cracked", "door", "shop", "garage",
                         "doorlock", "doorbar", "dooropen", "doorbroken", "doorsealed"):
                suf = "" if mode == "plain" else "_" + mode
                wall(axis, pi, mode).save(f"wall_{axis}{pi}{suf}")
            wall(axis, pi, "plain", 5).save(f"low_{axis}{pi}")
            wall(axis, pi, "stub").save(f"stub_{axis}{pi}")


# ------------------------------------------------------------------ diamonds (floors, flat roofs)
def diamond(name, fn):
    c = Cv(48, 24, 24, 0)
    c.face_top(0, 0, 1, 1, 0, fn)
    c.save(name)


def tiles():
    r = random.Random(5)
    diamond("floor_wood", lambda u, v: sh("#7a5236", .82) if (v * 6) % 1 < .12 else sh("#7a5236", .94 + r.random() * .12))
    diamond("floor_tile", lambda u, v: hx("#e2dccb") if (int(u * 4) + int(v * 4)) % 2 else hx("#2e2a2a"))
    diamond("floor_carpet", lambda u, v: sh("#7a3a34", 1.15) if (int(u * 12) + int(v * 12)) % 5 == 0 else sh("#7a3a34", .95 + r.random() * .08))
    diamond("floor_concrete", lambda u, v: sh("#8a867c", .9 + r.random() * .14) if (u * 2) % 1 > .03 else sh("#8a867c", .75))
    diamond("floor_lino", lambda u, v: hx("#9ab8a8") if (int(u * 3) + int(v * 3)) % 2 else hx("#d8d0b8"))
    diamond("garden", lambda u, v: hx("#5a4630") if int(v * 6) % 2 else (hx("#e0603a") if r.random() < .06 else sh("#6fae4a", .9 + r.random() * .2)))
    diamond("stairs_down", lambda u, v: hx("#2a1e18") if int(v * 6) % 2 else hx("#6a5038"))
    diamond("stairs_up", lambda u, v: hx("#a08060") if int(v * 6) % 2 == 0 else hx("#7a5a3a"))
    for i, col in enumerate(["#5a5650", "#4a4a4e", "#6a6258"]):
        def tar(u, v, col=col):
            n = r.random()
            c = sh(col, .9 + n * .18)
            if (u * 2) % 1 < .03 or (v * 2) % 1 < .03:
                c = sh(col, .8)
            return c
        diamond(f"roof_flat{i}", tar)
    diamond("roof_tin", lambda u, v: sh("#8a7a66", [1.1, 1.0, .85, .95][int(u * 24) % 4]) if noise(u * 5, v * 5) < .4 else mix(sh("#8a7a66", .9), "#8a4a2a", .5))
    diamond("roof_canopy", lambda u, v: sh("#e2dccb", .95 + r.random() * .06) if (u * 2) % 1 > .03 else sh("#e2dccb", .8))


# ------------------------------------------------------------------ screen-space textures for polygon roofs / gables
def tex48(name, fn):
    im = Image.new("RGBA", (48, 24))
    px = im.load()
    for y in range(24):
        for x in range(48):
            px[x, y] = hx(fn(x, y)) + (255,)
    from px2 import OUT_DIR
    import os
    im.save(os.path.join(OUT_DIR, name + ".png"))


def roof_textures():
    for i, col in enumerate(ROOFS):
        for ax in "xy":
            def shingle(x, y, col=col, ax=ax):
                k = (y - x / 2) if ax == "x" else (y + x / 2)
                row = int(math.floor(k / 4))
                seam = (x + (row % 2) * 4) % 8 == 0
                f = .78 if (k % 4) < 1 else (1.0 if not seam else .85)
                rr = ((x * 7 + row * 13) % 11) / 11
                return sh(col, f * (.94 + rr * .12))
            tex48(f"shingle_{ax}{i}", shingle)
    for pi, (style, base, trim) in enumerate(WALLS):
        for ax in "xy":
            shade = .97 if ax == "x" else .74

            def gab(x, y, style=style, base=base, trim=trim, ax=ax, shade=shade, pi=pi):
                if ax == "x":
                    u = (x / 24.0) % 1
                    v = ((x / 2 - y) / 1.5) % 16
                else:
                    u = (-x / 24.0) % 1
                    v = ((-x / 2 - y) / 1.5) % 16
                st = style if style not in ("streamline", "concrete", "panel") else "plaster"
                return sh(wall_col(st, base, trim, u, v + 8, seed=pi), shade)
            tex48(f"gable_{ax}{pi}", gab)


# ------------------------------------------------------------------ furniture
FURN = {   # long side, depth, height (logical px) — sizes match World.FURN_SIZE
    'counter': (1.0, .5, 12), 'stove': (.5, .5, 12), 'fridge': (.5, .5, 28), 'table': (.9, .6, 10),
    'chair': (.3, .3, 6), 'couch': (1.0, .45, 8), 'armchair': (.45, .45, 8), 'tv': (.4, .3, 12),
    'bookshelf': (.9, .3, 26), 'bed': (1.0, .6, 7), 'dresser': (.6, .35, 14), 'desk': (.8, .45, 11),
    'filing': (.35, .35, 16), 'shopshelf': (1.0, .35, 20), 'shopcounter': (1.0, .4, 12),
    'workbench': (.9, .4, 11), 'barrel': (.35, .35, 12), 'mattress': (.9, .55, 3),
    'booth': (1.0, .45, 12), 'jukebox': (.45, .35, 22), 'terminal': (.6, .4, 16), 'locker': (.8, .3, 26),
    'stool': (.25, .25, 8), 'vending': (.5, .4, 28),
}


def furniture(name, orient):
    L_, D, H = FURN[name]
    sx, sy = (L_, D) if orient == 'a' else (D, L_)
    c = Cv(72, 84, 36, 60)
    x0, y0, x1, y1 = -sx / 2, -sy / 2, sx / 2, sy / 2
    front = 's' if orient == 'a' else 'e'
    r = random.Random(hash(name) % 1000 + (orient == 'a'))

    def box(a0, b0, a1, b1, z0, z1, col, tex=None, top=None):
        """box in furniture-local (along, depth) coords: along = long side, depth from the wall."""
        if orient == 'a':
            c.box(x0 + a0, y0 + b0, x0 + a1, y0 + b1, z0, z1, col, tex, top)
        else:
            c.box(x0 + b0, y0 + a0, x0 + b1, y0 + a1, z0, z1, col, tex, top)

    def ft(fn):   # wrap: fn(u, v, col) applied only on the front face
        return lambda f, u, v, col: fn(u, v, col) if f == front else col

    if name == 'counter':
        box(0, 0, L_, D, 0, 11, "#d8ccb0", ft(lambda u, v, col: sh(col, .7) if (u * 4) % 1 < .05 or abs(v - 7) < .5 else col))
        box(0, 0, L_, D, 11, 12.5, "#8ac0b0")
    elif name == 'stove':
        box(0, 0, L_, D, 0, 12, "#e8e4d8", ft(lambda u, v, col: "#2a2a2a" if .1 < u < .4 and 2 < v < 8 else col))
        for (a, b) in ((.15, .15), (.35, .15), (.15, .35), (.35, .35)):
            p = c.P(x0 + (a if orient == 'a' else b), y0 + (b if orient == 'a' else a), 12)
            c.ellipse(p[0], p[1], 2.5, 1.3, "#2a2a2a")
    elif name == 'fridge':
        box(0, 0, L_, D, 0, 28, "#e8e2cc", ft(lambda u, v, col: ("#c8c8c0" if abs(v - 19) < .5 else (hx("#b8b8b0") if .38 < u < .42 and (12 < v < 17 or 21 < v < 26) else col))))
    elif name == 'table':
        for (a, b) in ((.08, .08), (L_ - .08, .08), (.08, D - .08), (L_ - .08, D - .08)):
            box(a - .03, b - .03, a + .03, b + .03, 0, 9, "#c8c8c0")
        box(0, 0, L_, D, 9, 10.5, "#c84a3a")
    elif name in ('chair', 'stool'):
        box(.04, .04, L_ - .04, D - .04, 0, 5 if name == 'chair' else 7, "#8a8a84")
        box(0, 0, L_, D, 5 if name == 'chair' else 7, 6.5 if name == 'chair' else 8.5, "#c84a3a")
        if name == 'chair':
            box(0, 0, L_, .06, 6, 13, "#c84a3a")
    elif name in ('couch', 'armchair', 'booth'):
        col = {"couch": "#6a8a6a", "armchair": "#a86a4a", "booth": "#c84a3a"}[name]
        box(0, 0, L_, D, 0, 6, col)
        box(0, 0, L_, .14, 6, 12 if name != 'booth' else 15, sh(col, 1.05))
        if name != 'booth':
            box(0, 0, .1, D, 6, 9, sh(col, .95)); box(L_ - .1, 0, L_, D, 6, 9, sh(col, .95))
        else:
            box(.1, .3, L_ - .1, D + .25 if False else D, 9, 10, "#c8c8c0")
    elif name == 'tv':
        box(0, 0, L_, D, 0, 12, "#7a5234", ft(lambda u, v, col: ("#6a8a7a" if .06 < u < .3 and 4 < v < 11 else ("#3a4a44" if .05 < u < .31 and 3 < v < 12 else col))))
        p = c.P(0, 0, 12)
        c.line(p, (p[0] - 4, p[1] - 8), "#2a2a2a"); c.line(p, (p[0] + 4, p[1] - 8), "#2a2a2a")
    elif name == 'bookshelf':
        cols = ["#8a3a2a", "#3a5a7a", "#7a7a3a", "#5a3a5a", "#c8a050", "#3a6a4a"]
        def books(u, v, col):
            if v % 6.5 < 1:
                return sh(col, .7)
            k = int(u * 26)
            return sh(cols[(k * 7 + int(v / 6.5) * 3) % 6], .85 + (k % 3) * .08) if r.random() > .12 else "#2a2018"
        box(0, 0, L_, D, 0, 26, "#7a5638", ft(books))
    elif name in ('bed', 'mattress'):
        if name == 'bed':
            box(0, 0, L_, D, 0, 3, "#6a4a30")
            box(0, 0, .08, D, 0, 10, "#6a4a30")
        z = 3 if name == 'bed' else 0
        box(.02, .02, L_ - .02, D - .02, z, z + 4, "#d8d0b8" if name == 'bed' else "#a89a7a")
        if name == 'bed':
            box(.1, .1, .3, D - .1, z + 4, z + 5.5, "#f0ead8")
            box(.35, .02, L_ - .02, D - .02, z + 4, z + 5, "#6a7a9a")
    elif name in ('dresser', 'desk', 'filing', 'locker'):
        col = {"dresser": "#8a6040", "desk": "#7a5a3a", "filing": "#9aa0a0", "locker": "#6a7a6a"}[name]
        def drawers(u, v, cc):
            if name == 'locker':
                return sh(cc, .7) if (u * 4.5) % 1 < .05 or (abs(v - 20) < .5) else cc
            if v % 4.5 < .6:
                return sh(cc, .7)
            if abs((u * 4) % 1 - .5) < .06 and v % 4.5 > 2 and v % 4.5 < 3:
                return "#d8c890"
            return cc
        box(0, 0, L_, D, 0, H, col, ft(drawers))
        if name == 'desk':
            box(.1, .1, .3, .3, H, H + 4, "#3a3a3a")
            box(.45, .1, .6, .25, H, H + 1, "#e8e0d0")
    elif name == 'terminal':
        box(0, 0, L_, D, 0, 10, "#7a5a3a")
        box(.15, .05, .5, .32, 10, 17, "#c8c0a8", ft(lambda u, v, col: "#2a6a3a" if .08 < u < .27 and 2 < v < 6 else col))
    elif name == 'shopshelf':
        def goods(u, v, cc):
            if v % 6.5 < 1:
                return sh(cc, .65)
            k = int(u * 20)
            return ["#c84a3a", "#e8c040", "#3e8a86", "#d8d0b8", "#7a9a4a"][(k * 3 + int(v / 6.5)) % 5] if r.random() > .25 else "#3a3430"
        box(0, 0, L_, D, 0, 20, "#8a8a82", ft(goods))
    elif name == 'shopcounter':
        box(0, 0, L_, D, 0, 11, "#a08a6a", ft(lambda u, v, col: sh(col, .8) if v % 4 < .6 else col))
        box(0, 0, L_, D, 11, 12, "#d8ccb0")
        box(.6, .1, .85, .3, 12, 16, "#5a5a54")
    elif name == 'workbench':
        for (a, b) in ((.05, .05), (L_ - .05, .05), (.05, D - .05), (L_ - .05, D - .05)):
            box(a - .03, b - .03, a + .03, b + .03, 0, 10, "#5a3a24")
        box(0, 0, L_, D, 10, 12, "#a07a4a")
        box(.1, .05, .3, .2, 12, 14, "#8a8a8a"); box(.5, .1, .7, .15, 12, 13, "#c84a2a")
    elif name == 'barrel':
        p = (x0 + sx / 2, y0 + sy / 2)
        c.cyl(p[0], p[1], .16, 0, 12, "#7a5a3a", bands=((3, "#5a3a24"), (9, "#5a3a24")))
    elif name == 'jukebox':
        box(0, 0, L_, D, 0, 18, "#8a4a30", ft(lambda u, v, col: ("#f2c040" if (abs(u - .22) < .03 or v > 15) else ("#3a2a3a" if 6 < v < 14 and .06 < u < .39 else col))))
        box(0, 0, L_, D, 18, 22, "#e8c060")
    elif name == 'vending':
        box(0, 0, L_, D, 0, 28, "#b83a2a", ft(lambda u, v, col: ("#e8e0d0" if v > 22 else ("#2e4250" if .06 < u < .3 and 8 < v < 20 else col))))
    c.save(f"furn_{name}_{orient}", outline=True)


def furnishings():
    for nm in FURN:
        for o in "ab":
            furniture(nm, o)


def build():
    walls()
    tiles()
    roof_textures()
    furnishings()
