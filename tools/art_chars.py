"""Characters and creatures, drawn procedurally from body parts so variants are cheap.

Humanoid frames are 24x36, anchor (12, 35) = between the feet.
Frame order: front idle, front walk, back idle, back walk, crouch front, crouch back.
"""
import random, math
from px2 import Cv, sh, mix, hx, sheet

FW, FH = 24, 36


def part(c, x0, y0, x1, y1, col, light=True):
    """Rect with left-lit shading and a top highlight row."""
    w = max(1, x1 - x0)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            t = (x - x0) / w
            f = 1.12 - 0.34 * t if light else 1.0
            if y == y0:
                f += 0.06
            c.put(x, y, sh(col, f))


def human(pal, view="front", walk=0, crouch=False, seed=0):
    rnd = random.Random(seed)
    c = Cv(FW, FH, 12, 35)
    skin, hair = pal["skin"], pal.get("hair", "#4a3424")
    jk, jk2 = pal["jacket"], pal.get("trim", sh(pal["jacket"], .8))
    pants, boots = pal["pants"], pal.get("boots", "#2e2420")
    back = view == "back"
    dy = 5 if crouch else 0
    # legs
    if crouch:
        part(c, 6, 27, 10, 31, pants); part(c, 13, 27, 17, 31, pants)
        part(c, 5, 32, 10, 34, boots); part(c, 13, 32, 18, 34, boots)
    else:
        la = -2 if walk == 1 else 0
        ra = 0 if walk == 1 else 0
        lx = 7 if walk == 1 else 8
        rx = 13 if walk == 1 else 12
        part(c, lx, 24, lx + 3, 31 + la, pants)
        part(c, rx, 24, rx + 3, 31 + ra, pants)
        part(c, lx - (1 if walk else 0), 32 + la, lx + 3, 34 + la, boots)
        part(c, rx, 32 + ra, rx + 3 + (1 if walk else 0), 34 + ra, boots)
        if pal.get("coat"):   # long coat over the legs
            part(c, 7, 24, 16, 29, pal["coat"])
    # backpack (behind body from the front, on top from the back)
    if pal.get("pack") and not back:
        part(c, 7, 13 + dy, 16, 15 + dy, sh(pal["pack"], .8))
    # torso
    part(c, 7, 13 + dy, 16, 23 + dy, jk)
    part(c, 7, 23 + dy, 16, 24 + dy, pal.get("belt", "#3a2a1e"))
    if pal.get("stripe") and not back:
        for y in range(13 + dy, 23 + dy):
            c.put(11, y, pal["stripe"]); c.put(12, y, sh(pal["stripe"], .85))
    if pal.get("stripe") and back:
        for y in range(13 + dy, 23 + dy):
            c.put(11, y, sh(pal["stripe"], .9)); c.put(12, y, sh(pal["stripe"], .8))
    if pal.get("vest"):
        part(c, 8, 14 + dy, 15, 20 + dy, pal["vest"])
        if not back:
            c.put(9, 16 + dy, sh(pal["vest"], 1.3)); c.put(14, 16 + dy, sh(pal["vest"], .7))
    if pal.get("collar") and not back:
        part(c, 9, 13 + dy, 14, 13 + dy, pal["collar"])
    if pal.get("ragged"):
        for x in range(7, 17):
            if rnd.random() < .45:
                c.px[x, 24 + dy] = (0, 0, 0, 0)
        for k in range(4):
            c.put(rnd.randint(8, 15), rnd.randint(15, 22) + dy, skin)
    # arms (swing when walking)
    sw = 1 if walk else 0
    part(c, 4, 14 + dy - sw, 6, 22 + dy - sw, jk2)
    part(c, 17, 14 + dy + sw, 19, 22 + dy + sw, sh(jk2, .85))
    c.rect(4, 23 + dy - sw, 6, 24 + dy - sw, skin if not pal.get("gloves") else pal["gloves"])
    c.rect(17, 23 + dy + sw, 19, 24 + dy + sw, sh(skin, .85) if not pal.get("gloves") else sh(pal["gloves"], .85))
    if pal.get("pads"):
        part(c, 3, 13 + dy, 7, 15 + dy, pal["pads"]); part(c, 16, 13 + dy, 20, 15 + dy, pal["pads"])
        c.put(3, 12 + dy, "#c8c0b0"); c.put(20, 12 + dy, "#c8c0b0")
    if pal.get("pack") and back:
        part(c, 8, 14 + dy, 15, 22 + dy, pal["pack"])
        c.rect(8, 17 + dy, 15, 17 + dy, sh(pal["pack"], .7))
        c.put(9, 15 + dy, sh(pal["pack"], 1.3))
    # head
    hy = 4 + dy
    part(c, 8, hy + 1, 15, hy + 8, skin)
    c.rect(10, hy + 9, 13, hy + 9, sh(skin, .8))   # neck
    style = pal.get("style", "short")
    hc = hair
    if back:
        part(c, 8, hy, 15, hy + 7, hc)
        if style == "long":
            part(c, 8, hy + 7, 15, hy + 10, hc)
    else:
        if style in ("short", "long", "mohawk", "beard"):
            part(c, 8, hy, 15, hy + 2, hc)
            c.put(8, hy + 3, hc); c.put(15, hy + 3, sh(hc, .8))
            if style == "long":
                part(c, 7, hy + 2, 8, hy + 9, hc); part(c, 15, hy + 2, 16, hy + 9, sh(hc, .8))
        if style == "beard":
            part(c, 9, hy + 6, 14, hy + 8, hc)
        eyes = pal.get("eyes", "#1e1622")
        c.put(10, hy + 4, eyes); c.put(13, hy + 4, eyes)
        c.put(10, hy + 3, sh(skin, .75)); c.put(13, hy + 3, sh(skin, .75))
        if style != "beard":
            c.put(11, hy + 7, sh(skin, .7)); c.put(12, hy + 7, sh(skin, .7))
        if pal.get("paint"):
            c.rect(9, hy + 5, 14, hy + 5, pal["paint"])
        if pal.get("mask"):
            part(c, 9, hy + 5, 14, hy + 8, pal["mask"])
            c.put(11, hy + 8, "#1e1622"); c.put(12, hy + 8, "#1e1622")
        if pal.get("patches"):
            for k in range(3):
                c.put(rnd.randint(8, 15), rnd.randint(hy + 1, hy + 8), pal["patches"])
    if style == "mohawk":
        part(c, 11, hy - 3, 12, hy + (1 if not back else 6), pal.get("mohawk", "#c84a2a"))
    if style == "bald":
        part(c, 8, hy, 15, hy + 1, sh(skin, 1.05))
    if style == "helmet":
        part(c, 7, hy - 1, 16, hy + 3, pal.get("helm", "#6a6a5a"))
        c.rect(7, hy + 3, 16, hy + 3, sh(pal.get("helm", "#6a6a5a"), .7))
    if style == "cap":
        part(c, 8, hy - 1, 15, hy + 2, pal.get("helm", "#8a3a2a"))
        if not back:
            c.rect(7, hy + 2, 16, hy + 2, sh(pal.get("helm", "#8a3a2a"), .7))
    if style == "hat":
        hcol = pal.get("helm", "#6a4a2a")
        part(c, 9, hy - 3, 14, hy + 1, hcol)
        c.rect(5, hy + 1, 18, hy + 2, sh(hcol, .85))
    if style == "hood":
        part(c, 7, hy - 1, 16, hy + 3, hc); part(c, 7, hy + 3, 8, hy + 9, hc); part(c, 15, hy + 3, 16, hy + 9, sh(hc, .8))
    if pal.get("goggles") and not back:
        c.rect(9, hy + 3, 14, hy + 4, "#3a3430"); c.put(10, hy + 3, "#9ad0d8"); c.put(13, hy + 3, "#9ad0d8")
    return c


def human_sheet(pal, name, seed=0):
    fr = [human(pal, "front", 0, seed=seed), human(pal, "front", 1, seed=seed),
          human(pal, "back", 0, seed=seed), human(pal, "back", 1, seed=seed),
          human(pal, "front", 0, True, seed=seed), human(pal, "back", 0, True, seed=seed)]
    for f in fr:
        f.outline()
    sheet(fr, name)


PALS = {
    "player": dict(skin="#e0b090", hair="#5a3a24", jacket="#3a5f94", trim="#335480", pants="#335480", boots="#3a2a20",
                   stripe="#e0b640", collar="#e0b640", pack="#7a5a38", belt="#5a4030", style="short"),
    "survivor": dict(skin="#c89070", hair="#2a2020", jacket="#5e6e44", pants="#4a4038", style="cap", helm="#7a6a3a", pack="#6a5a40"),
    "raider": dict(skin="#d8a080", hair="#2a1a14", jacket="#5a3a28", trim="#4a3022", pants="#2e2a28", pads="#7a7064",
                   style="mohawk", mohawk="#c83a24", paint="#a82a1e", vest="#4a3a30", gloves="#2a2420"),
    "ghoul": dict(skin="#9a8458", hair="#4a3a28", jacket="#5a5448", trim="#4a463c", pants="#3e3a34", style="bald",
                  patches="#6a4a34", ragged=True, eyes="#e8d870"),
    "settler1": dict(skin="#d8a07a", hair="#6a4a2a", jacket="#8a6a44", pants="#4a4a52", style="hat", helm="#7a5a34", vest="#5a4a34"),
    "settler2": dict(skin="#b07a5a", hair="#2a2020", jacket="#7a4a4a", pants="#4a4038", style="long", hair2="#2a2020"),
    "settler3": dict(skin="#e8c0a0", hair="#a8a090", jacket="#6a7a8a", pants="#5a4a3a", style="beard"),
    "trader": dict(skin="#c89070", hair="#3a2a20", jacket="#7a6a4e", pants="#4a3e30", coat="#6a5a42", style="hat",
                   helm="#4a3a2a", pack="#8a6a3a", goggles=True),
}


def brute(view, walk):
    c = Cv(30, 39, 15, 38)
    skin, dark = "#8a9a5e", "#6a7848"
    gear = "#5a4a3a"
    back = view == "back"
    # legs
    la = -2 if walk else 0
    part(c, 8, 27, 13, 35 + la, skin); part(c, 16, 27, 21, 35, skin)
    part(c, 7, 35 + la, 13, 37 + la, "#3a3028"); part(c, 16, 35, 22, 37, "#3a3028")
    part(c, 8, 25, 21, 29, gear)   # loincloth / belt
    # torso: big and hunched
    part(c, 6, 11, 23, 25, skin)
    part(c, 8, 12, 21, 14, sh(skin, 1.1))
    if not back:
        for y in range(16, 24, 3):
            c.rect(10, y, 19, y, sh(skin, .85))
        c.line((7, 12), (22, 22), gear)
        c.line((7, 13), (22, 23), sh(gear, .8))
    # arms hang low
    sw = 1 if walk else 0
    part(c, 1, 12 - sw, 6, 28 - sw, skin); part(c, 23, 12 + sw, 28, 28 + sw, dark)
    part(c, 0, 28 - sw, 6, 31 - sw, sh(skin, .9)); part(c, 23, 28 + sw, 29, 31 + sw, sh(dark, .9))
    # small head sunk between shoulders
    part(c, 11, 5, 18, 12, skin)
    if not back:
        c.rect(11, 8, 18, 8, sh(skin, .7))
        c.put(13, 9, "#e8c040"); c.put(16, 9, "#e8c040")
        c.rect(13, 11, 16, 11, "#3a2a20")
        c.put(13, 12, "#d8d0b0"); c.put(16, 12, "#d8d0b0")
    else:
        c.rect(11, 5, 18, 6, sh(skin, .8))
    c.outline()
    return c


def shellback(f):
    c = Cv(33, 17, 16, 15)
    shell, belly = "#7a6448", "#a08a60"
    lg = 1 if f else -1
    for i, x in enumerate((6, 10, 22, 26)):
        o = lg if i % 2 else -lg
        c.line((x, 11), (x - 3 + o, 15), "#4a3a2a"); c.line((x + 1, 11), (x - 2 + o, 15), "#5a4a34")
    c.ellipse(16, 10, 12, 5, belly)
    for y in range(2, 12):
        for x in range(4, 29):
            d = ((x - 16) / 12.5) ** 2 + ((y - 8) / 6.5) ** 2
            if d <= 1:
                t = (x - 4) / 25
                col = sh(shell, 1.18 - 0.4 * t - (y - 2) * 0.015)
                if (x + (y // 3) * 3) % 7 == 0 or y in (5, 8):
                    col = sh(col, .78)
                c.put(x, y, col)
    # claws
    for (x0, s) in ((1, 1), (28, -1)):
        o = 1 if f else 0
        c.ellipse(x0 + 2 * s + 1, 10 - o, 2.5, 2, "#8a5a3a")
        c.put(x0 + 4 * s + 1, 8 - o, "#c8a070")
    c.put(13, 7, "#e85a2a"); c.put(19, 7, "#e85a2a")
    c.outline()
    return c


def rat(f):
    c = Cv(12, 9, 6, 8)
    body = "#b08a7a"
    c.ellipse(6, 5, 4.5, 2.6, body)
    c.ellipse(5, 4, 3, 1.5, sh(body, 1.12))
    c.ellipse(10, 5, 1.8, 1.6, sh(body, .95))
    c.put(11, 6, "#f0e8d0"); c.put(10, 4, "#1e1622")
    c.line((1, 5), (0, 7 if f else 6), "#8a6a5a")
    c.put(3, 8 if f else 7, "#6a4a3a"); c.put(8, 7 if f else 8, "#6a4a3a")
    c.outline()
    return c


def dog(f):
    c = Cv(21, 15, 10, 14)
    fur, dark = "#8a6440", "#5a3e26"
    legs = (2, 0) if f else (0, 2)
    for i, x in enumerate((5, 7, 13, 15)):
        part(c, x, 9, x + 1, 13 - legs[i % 2] // 2, dark if i % 2 else fur)
    part(c, 4, 5, 16, 10, fur)
    part(c, 5, 5, 15, 6, sh(fur, 1.15))
    part(c, 15, 2, 19, 7, fur)
    c.put(20, 5, "#2a1e18"); c.put(17, 3, "#1e1622")
    c.rect(16, 1, 17, 2, dark)
    c.rect(15, 7, 16, 7, "#a83a2a")
    c.line((4, 6), (1, 3 if f else 4), fur)
    c.outline()
    return c


def cattle(f):
    c = Cv(30, 17, 15, 16)
    hide, spot = "#a08460", "#6a5038"
    for i, x in enumerate((6, 9, 19, 22)):
        o = (1 if (i % 2) == f else 0)
        part(c, x, 10, x + 2, 15 - o, sh(hide, .8))
    part(c, 4, 4, 23, 11, hide)
    part(c, 5, 4, 22, 5, sh(hide, 1.12))
    c.ellipse(10, 7, 3, 2, spot); c.ellipse(18, 9, 2, 1.5, spot)
    for (hx_, hy) in ((24, 3), (26, 6)):   # two heads
        part(c, hx_, hy, hx_ + 4, hy + 4, sh(hide, .95))
        c.put(hx_ + 4, hy + 3, "#d8a890"); c.put(hx_ + 2, hy + 1, "#1e1622")
        c.put(hx_ + 1, hy - 1, "#e0d8c0")
    c.line((4, 6), (2, 10 if f else 9), sh(hide, .7))
    c.outline()
    return c


def crow(f):
    c = Cv(12, 9, 6, 8)
    k = "#2a2630"
    if f == 0:
        c.ellipse(6, 5, 3, 2, k); c.ellipse(8.5, 3.5, 1.6, 1.4, k)
        c.put(10, 4, "#c8a040"); c.put(9, 3, "#d8d0c0"); c.put(5, 8, "#5a4a30"); c.put(7, 8, "#5a4a30")
    else:
        c.ellipse(6, 5, 2.5, 1.5, k)
        if f == 1:
            c.line((1, 1), (5, 4), k); c.line((11, 1), (7, 4), k)
        else:
            c.line((1, 7), (5, 5), k); c.line((11, 7), (7, 5), k)
        c.put(8, 4, "#c8a040")
    c.outline(col=(60, 56, 66))
    return c


def icons():
    q = Cv(6, 9, 3, 9)
    for (x, y) in ((1, 0), (2, 0), (3, 0), (4, 1), (4, 2), (3, 3), (2, 4), (2, 5), (2, 7)):
        q.put(x, y, "#f2c36b")
    q.save("icon_suspicious", outline=False)
    a = Cv(4, 10, 2, 10)
    a.rect(1, 0, 2, 5, "#e84a3a"); a.rect(1, 8, 2, 9, "#e84a3a")
    a.save("icon_alert", outline=False)


def build():
    for name, pal in PALS.items():
        human_sheet(pal, name, seed=len(name))
    sheet([brute("front", 0), brute("front", 1), brute("back", 0), brute("back", 1)], "brute")
    sheet([shellback(0), shellback(1)], "shellback")
    sheet([rat(0), rat(1)], "rat")
    sheet([dog(0), dog(1)], "dog")
    sheet([cattle(0), cattle(1)], "cattle")
    sheet([crow(0), crow(1), crow(2)], "crow")
    icons()
