"""Drawing helpers for the 1.5x art pass (tiles are 48x24 px, heights are 'logical' px x 1.5).

Every sprite is drawn on a Cv canvas with an anchor point (ax, ay). The anchor is the
world point the sprite stands on; make_assets.py writes all anchors to anchors.json and the
game reads them, so offsets never have to be hand-typed in GDScript.
"""
from PIL import Image, ImageDraw
import math, random, os, json

S = 1.5                 # logical px (game heights) -> screen px
HW, HH = 24, 12         # half a tile on screen
OUTLINE = (26, 20, 30)
ANCHORS = {}
OUT_DIR = None


def hx(c):
    if isinstance(c, str):
        return tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))
    return tuple(c[:3])


def sh(c, f):
    c = hx(c)
    return tuple(max(0, min(255, int(v * f))) for v in c)


def mix(a, b, t):
    a, b = hx(a), hx(b)
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def lit3(base):
    """top, south-facing (lit), east-facing (shade) versions of a colour."""
    return sh(base, 1.13), sh(base, 0.97), sh(base, 0.72)


def noise(x, y, s=1.0, seed=0):
    return (math.sin(x * 1.7 * s + y * .9 * s + 1.3 + seed) + math.sin(x * .6 * s - y * 1.9 * s + .4 + seed * 2)
            + math.sin((x + y) * 3.1 * s + seed * 3)) / 3


class Cv:
    def __init__(self, w, h, ax, ay):
        self.im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.im.load()
        self.w, self.h, self.ax, self.ay = w, h, ax, ay

    # ---- projection
    def P(self, x, y, z=0.0):
        return (self.ax + (x - y) * HW, self.ay + (x + y) * HH - z * S)

    def Pi(self, x, y, z=0.0):
        p = self.P(x, y, z)
        return (int(round(p[0])), int(round(p[1])))

    def inv(self, sx, sy, z):
        a = (sx - self.ax) / HW
        b = (sy + z * S - self.ay) / HH
        return ((a + b) / 2, (b - a) / 2)

    # ---- pixels
    def put(self, x, y, c, a=255):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h and c is not None:
            self.px[x, y] = hx(c) + (a,)

    def get(self, x, y):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[x, y]
        return (0, 0, 0, 0)

    def blend(self, x, y, c, t):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            o = self.px[x, y]
            if o[3] == 0:
                return
            self.px[x, y] = mix(o, c, t) + (o[3],)

    def rect(self, x0, y0, x1, y1, c, a=255):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                self.put(x, y, c, a)

    def poly(self, pts, c, outline=None):
        d = ImageDraw.Draw(self.im)
        d.polygon([(round(p[0]), round(p[1])) for p in pts], fill=hx(c) + (255,),
                  outline=(hx(outline) + (255,)) if outline else None)

    def line(self, a, b, c, w=1):
        d = ImageDraw.Draw(self.im)
        d.line([(round(a[0]), round(a[1])), (round(b[0]), round(b[1]))], fill=hx(c) + (255,), width=w)

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((x + .5 - cx) / max(.01, rx)) ** 2 + ((y + .5 - cy) / max(.01, ry)) ** 2 <= 1.0:
                    self.put(x, y, c)

    # ---- iso faces. fn(u, v) -> colour or None. u in tiles along the face, v in logical px up.
    def face_s(self, x0, x1, y, z0, z1, fn):
        """face at constant world y (runs along x), seen from the south."""
        sa = self.P(x0, y)[0]
        sb = self.P(x1, y)[0]
        for sx in range(int(math.floor(min(sa, sb))), int(math.ceil(max(sa, sb))) + 1):
            x = (sx + .5 - self.ax) / HW + y
            if x < x0 - 1e-6 or x > x1 + 1e-6:
                continue
            gy = self.ay + (x + y) * HH
            for sy in range(int(gy - z1 * S) - 1, int(gy - z0 * S) + 2):
                z = (gy - (sy + .5)) / S
                if z0 - 1e-6 <= z <= z1 + 1e-6:
                    self.put(sx, sy, fn(x - x0, z - z0))

    def face_e(self, x, y0, y1, z0, z1, fn):
        """face at constant world x (runs along y), seen from the east."""
        sa = self.P(x, y0)[0]
        sb = self.P(x, y1)[0]
        for sx in range(int(math.floor(min(sa, sb))), int(math.ceil(max(sa, sb))) + 1):
            y = x - (sx + .5 - self.ax) / HW
            if y < y0 - 1e-6 or y > y1 + 1e-6:
                continue
            gy = self.ay + (x + y) * HH
            for sy in range(int(gy - z1 * S) - 1, int(gy - z0 * S) + 2):
                z = (gy - (sy + .5)) / S
                if z0 - 1e-6 <= z <= z1 + 1e-6:
                    self.put(sx, sy, fn(y - y0, z - z0))

    def face_top(self, x0, y0, x1, y1, z, fn):
        pts = [self.P(x0, y0, z), self.P(x1, y0, z), self.P(x1, y1, z), self.P(x0, y1, z)]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        for sy in range(int(min(ys)) - 1, int(max(ys)) + 2):
            for sx in range(int(min(xs)) - 1, int(max(xs)) + 2):
                wx, wy = self.inv(sx + .5, sy + .5, z)
                if x0 - 1e-6 <= wx <= x1 + 1e-6 and y0 - 1e-6 <= wy <= y1 + 1e-6:
                    self.put(sx, sy, fn(wx - x0, wy - y0))

    def box(self, x0, y0, x1, y1, z0, z1, base, tex=None, top=None, edge=True):
        """Shaded iso box. tex(face, u, v, col) may alter colours ('t','s','e')."""
        ct, cs, ce = lit3(base)
        if top is not None:
            ct = hx(top)
        f = tex or (lambda face, u, v, c: c)
        self.face_e(x1, y0, y1, z0, z1, lambda u, v: f('e', u, v, ce))
        self.face_s(x0, x1, y1, z0, z1, lambda u, v: f('s', u, v, cs))
        self.face_top(x0, y0, x1, y1, z1, lambda u, v: f('t', u, v, ct))
        if edge:   # bright rim where top meets the lit face
            self.line(self.P(x0, y1, z1), self.P(x1, y1, z1), sh(ct, 1.1))

    def cyl(self, cx, cy, r, z0, z1, base, top=None, bands=()):
        """Vertical cylinder (barrels, tanks, poles)."""
        c0 = self.P(cx, cy, z0)
        c1 = self.P(cx, cy, z1)
        rx = r * HW * 1.414
        ry = r * HH * 1.414
        for sx in range(int(c0[0] - rx) - 1, int(c0[0] + rx) + 2):
            t = (sx + .5 - c0[0]) / max(.01, rx)
            if abs(t) > 1:
                continue
            k = math.sqrt(1 - t * t)
            light = 0.78 + 0.32 * (-t * 0.7 + k * 0.3)
            col = sh(base, light)
            ytop = c1[1] + k * ry
            ybot = c0[1] + k * ry
            for sy in range(int(ytop), int(ybot) + 1):
                zz = (c0[1] + k * ry - sy) / S
                cc = col
                for (bz, bc) in bands:
                    if abs(zz - bz) < 0.8:
                        cc = sh(bc, light)
                self.put(sx, sy, cc)
        self.ellipse(c1[0], c1[1], rx, ry, top if top is not None else sh(base, 1.15))

    # ---- post
    def outline(self, col=OUTLINE, inner=True):
        """1px selective outline: dark ring outside the sprite, tinted by what it touches."""
        w, h = self.w, self.h
        src = self.im.copy()
        sp = src.load()
        for y in range(h):
            for x in range(w):
                if sp[x, y][3] != 0:
                    continue
                n = None
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < w and 0 <= yy < h and sp[xx, yy][3] > 0:
                        n = sp[xx, yy]
                        break
                if n:
                    self.px[x, y] = mix(n, col, 0.78) + (255,)

    def save(self, name, outline=False):
        if outline:
            self.outline()
        self.im.save(os.path.join(OUT_DIR, name + ".png"))
        ANCHORS[name] = [round(self.ax), round(self.ay)]


def write_anchors():
    out = dict(ANCHORS)
    rp = os.path.join(OUT_DIR, "..", "rendered_anchors.json")    # sprites from the Blender pipeline (tools/render3d)
    if os.path.exists(rp):
        out.update(json.load(open(rp)))
    with open(os.path.join(OUT_DIR, "..", "anchors.json"), "w") as f:
        json.dump(out, f, separators=(",", ":"), sort_keys=True)


def sheet(frames, name):
    """frames: list of Cv of equal size; anchor is the first frame's."""
    w = sum(f.w for f in frames)
    h = max(f.h for f in frames)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    x = 0
    for f in frames:
        im.paste(f.im, (x, 0))
        x += f.w
    im.save(os.path.join(OUT_DIR, name + ".png"))
    ANCHORS[name] = [frames[0].ax, frames[0].ay]
