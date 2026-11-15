"""Procedural spray-paint graffiti textures (PIL) and a helper to stick them on walls in Blender.
Wasteland-flavoured slogans, scribbled tags, arrows and crude marks — with outlines, overspray and drips."""
import os, math, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

WORDS = ["KEEP OUT", "LOOTERS SHOT", "NO WATER", "REPENT", "THE END", "TURN BACK", "HELP", "FREE", "DOOM",
         "GO HOME", "MUTIES", "WE LIVED", "NO HOPE", "SAFE?", "DEAD ZONE", "MINE", "RUN", "1 MILE >", "TRADE", "CLEAN WATER"]
COLS = [(196, 52, 38), (52, 140, 70), (40, 80, 160), (230, 226, 210), (24, 22, 20), (220, 180, 40), (180, 60, 150)]
FONTS = ["/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"]
_CACHE = {}


def _font(size):
    for f in FONTS:
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def make(out_dir, seed):
    """Returns path of a 256x128 RGBA graffiti texture."""
    path = os.path.join(out_dir, "graf_%d.png" % seed)
    if os.path.exists(path):
        return path
    r = random.Random(seed)
    W, H = 512, 256
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col = r.choice(COLS)
    kind = r.random()
    if kind < 0.6:
        word = r.choice(WORDS)
        size = r.randint(70, 120) if len(word) < 8 else r.randint(48, 70)
        f = _font(size)
        tw = d.textlength(word, font=f)
        x = max(8, (W - tw) / 2 + r.uniform(-20, 20))
        y = H / 2 - size * 0.6 + r.uniform(-15, 15)
        outline = r.choice(COLS) if r.random() < 0.5 else None
        # letters one by one with a little jitter so it looks hand-sprayed
        for ch in word:
            dy = r.uniform(-8, 8)
            if outline and outline != col:
                d.text((x, y + dy), ch, font=f, fill=col + (255,), stroke_width=4, stroke_fill=outline + (255,))
            else:
                d.text((x, y + dy), ch, font=f, fill=col + (255,))
            x += d.textlength(ch, font=f) * r.uniform(0.9, 1.05)
    elif kind < 0.8:
        # scribbled tag: loopy strokes
        x, y = 40, H / 2
        pts = []
        for i in range(r.randint(18, 30)):
            x += r.uniform(8, 22)
            y = H / 2 + math.sin(i * r.uniform(0.6, 1.4)) * r.uniform(20, 60)
            pts.append((x, y))
        d.line(pts, fill=col + (255,), width=r.randint(8, 14), joint="curve")
        d.line([(pts[0][0], pts[-1][1] + 40), (pts[-1][0], pts[-1][1] + 30)], fill=col + (255,), width=6)
    else:
        # arrow or big X
        if r.random() < 0.5:
            d.line([(60, H / 2), (W - 120, H / 2)], fill=col + (255,), width=22)
            d.polygon([(W - 140, H / 2 - 50), (W - 40, H / 2), (W - 140, H / 2 + 50)], fill=col + (255,))
        else:
            d.line([(W / 2 - 90, 30), (W / 2 + 90, H - 30)], fill=col + (255,), width=26)
            d.line([(W / 2 + 90, 30), (W / 2 - 90, H - 30)], fill=col + (255,), width=26)
    # drips below painted pixels
    px = im.load()
    for k in range(r.randint(6, 18)):
        x = r.randint(0, W - 1)
        for y in range(H - 1, 0, -1):
            if px[x, y][3] > 0:
                L = r.randint(10, 60)
                for j in range(L):
                    if y + j < H:
                        for dx in (0, 1, 2):
                            if x + dx < W:
                                px[x + dx, y + j] = px[x, y][:3] + (int(255 * (1 - j / L)),)
                break
    # overspray: soft halo + speckle, then fade a bit (old paint)
    halo = im.filter(ImageFilter.GaussianBlur(5))
    hp = halo.load()
    for y in range(H):
        for x in range(W):
            a = hp[x, y][3]
            if a and px[x, y][3] == 0 and r.random() < 0.5:
                px[x, y] = hp[x, y][:3] + (int(a * 0.6),)
    fade = r.uniform(0.85, 1.0)
    for y in range(H):
        for x in range(W):
            c = px[x, y]
            if c[3]:
                a = c[3] * fade * (0.55 if r.random() < 0.15 else 1.0)
                px[x, y] = c[:3] + (int(a),)
    im.save(path)
    return path


def place(out_dir, x, y, z, w, h, facing, seed, offset=0.004):
    """Stick a graffiti decal on a wall face. facing 's' (wall faces +y) or 'e' (wall faces +x).
    (x, y) is the left edge on the wall surface, z the bottom; w, h in tiles."""
    import bpy
    from lib import g2b
    from lib import _nodes
    path = make(out_dir, seed)
    key = path
    if key not in _CACHE:
        m, nt, bs = _nodes("graf%d" % seed)
        img = bpy.data.images.load(path)
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
        nt.links.new(tex.outputs["Color"], bs.inputs["Base Color"])
        bs.inputs["Roughness"].default_value = 0.6
        out = [n for n in nt.nodes if n.bl_idname == "ShaderNodeOutputMaterial"][0]
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mx = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(tex.outputs["Alpha"], mx.inputs[0]); nt.links.new(tr.outputs[0], mx.inputs[1]); nt.links.new(bs.outputs[0], mx.inputs[2])
        nt.links.new(mx.outputs[0], out.inputs[0])
        _CACHE[key] = m
    m = _CACHE[key]
    if facing == "s":
        vs = [(x, y + offset, z), (x + w, y + offset, z), (x + w, y + offset, z + h), (x, y + offset, z + h)]
    else:
        vs = [(x + offset, y + w, z), (x + offset, y, z), (x + offset, y, z + h), (x + offset, y + w, z + h)]
    me = bpy.data.meshes.new("graf")
    me.from_pydata([g2b(*v) for v in vs], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new()
    for i, l in enumerate(me.loops):
        uv.data[i].uv = [(0, 0), (1, 0), (1, 1), (0, 1)][i]
    ob = bpy.data.objects.new("graf", me)
    bpy.context.scene.collection.objects.link(ob); __import__('lib').REG.append(ob)
    me.materials.append(m)
    ob.visible_shadow = False
    return ob
