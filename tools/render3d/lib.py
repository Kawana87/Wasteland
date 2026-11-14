"""Helpers for the pre-rendered art pipeline (Blender as a Python module: pip install bpy).

Everything is modelled in GAME coordinates: x and y in tiles (x goes screen right-down,
y goes screen left-down), z up in tiles. g2b() converts to Blender space (Y flipped).
The camera is a true 2:1 dimetric orthographic camera, like Fallout 1/2's renders.
"""
import bpy, bmesh, math, random
import fast as FAST
from mathutils import Vector, Euler

TILE_PX = 64                      # width of one tile diamond on screen
PX_PER_UNIT = TILE_PX / math.sqrt(2)


def g2b(x, y, z=0.0):
    return Vector((x, -y, z))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.view_settings.view_transform = 'Standard'
    sc.view_settings.look = 'None'
    return sc


# ------------------------------------------------------------------ materials
def _nodes(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bs.outputs[0], out.inputs[0])
    return m, nt, bs


def _hex(c, a=1.0):
    c = c.lstrip('#')
    rgb = [int(c[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [v ** 2.2 for v in rgb] + [a]   # sRGB -> linear


def _coord(nt, scale=1.0):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    nt.links.new(tc.outputs["Object"], mp.inputs[0])
    return mp.outputs[0]


def _ramp(nt, fac, stops):
    r = nt.nodes.new("ShaderNodeValToRGB")
    els = r.color_ramp.elements
    while len(els) > 1:
        els.remove(els[-1])
    els[0].position = stops[0][0]
    els[0].color = _hex(stops[0][1])
    for p, c in stops[1:]:
        e = els.new(p)
        e.color = _hex(c)
    nt.links.new(fac, r.inputs[0])
    return r.outputs[0]


def _noise(nt, co, scale, detail=6.0, rough=0.6):
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = rough
    nt.links.new(co, n.inputs["Vector"])
    return n


def _bump(nt, bs, height, strength=0.4, dist=0.02):
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = strength
    b.inputs["Distance"].default_value = dist
    nt.links.new(height, b.inputs["Height"])
    nt.links.new(b.outputs[0], bs.inputs["Normal"])


def _mix(nt, a, b, fac):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = 'RGBA'
    nt.links.new(fac, m.inputs[0])
    if isinstance(a, str):
        m.inputs[6].default_value = _hex(a)
    else:
        nt.links.new(a, m.inputs[6])
    if isinstance(b, str):
        m.inputs[7].default_value = _hex(b)
    else:
        nt.links.new(b, m.inputs[7])
    return m.outputs[2]


def grime(nt, col, co, amount=0.5, streaks=True):
    """Darken a colour with blotchy dirt and vertical water streaks."""
    n = _noise(nt, co, 3.0, 8.0, 0.7)
    dirt = _ramp(nt, n.outputs[0], [(0.45, '#ffffff'), (0.75, '#6a5a48')])
    out = _mix(nt, col, dirt, _val(nt, amount))
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = 'RGBA'
    m.blend_type = 'MULTIPLY'
    m.inputs[0].default_value = amount
    nt.links.new(col, m.inputs[6])
    nt.links.new(dirt, m.inputs[7])
    out = m.outputs[2]
    if streaks:
        sep = nt.nodes.new("ShaderNodeMapping")
        sep.inputs["Scale"].default_value = (14.0, 14.0, 0.6)
        nt.links.new(co, sep.inputs[0])
        s = _noise(nt, sep.outputs[0], 1.0, 4.0, 0.5)
        st = _ramp(nt, s.outputs[0], [(0.5, '#ffffff'), (0.7, '#8a7a66')])
        m2 = nt.nodes.new("ShaderNodeMix")
        m2.data_type = 'RGBA'
        m2.blend_type = 'MULTIPLY'
        m2.inputs[0].default_value = 0.6
        nt.links.new(out, m2.inputs[6])
        nt.links.new(st, m2.inputs[7])
        out = m2.outputs[2]
    return out


def _val(nt, v):
    n = nt.nodes.new("ShaderNodeValue")
    n.outputs[0].default_value = v
    return n.outputs[0]


def grit(nt, col, co, amount=0.35, scale=160.0):
    """High-frequency speckle: what makes pre-rendered sprites look gritty instead of CG-clean."""
    n = _noise(nt, co, scale, 2.0, 0.5)
    g = _ramp(nt, n.outputs[0], [(0.35, '#8a8a8a'), (0.65, '#ffffff')])
    m = nt.nodes.new("ShaderNodeMix"); m.data_type = 'RGBA'; m.blend_type = 'MULTIPLY'
    m.inputs[0].default_value = amount
    nt.links.new(col, m.inputs[6]); nt.links.new(g, m.inputs[7])
    return m.outputs[2]


def cracks(nt, col, co, scale=2.0, width=0.015, dark='#2a2420'):
    n = _noise(nt, co, scale, 4.0, 0.55)
    sub = nt.nodes.new("ShaderNodeMath"); sub.operation = 'SUBTRACT'
    nt.links.new(n.outputs[0], sub.inputs[0]); sub.inputs[1].default_value = 0.5
    ab = nt.nodes.new("ShaderNodeMath"); ab.operation = 'ABSOLUTE'
    nt.links.new(sub.outputs[0], ab.inputs[0])
    r = _ramp(nt, ab.outputs[0], [(0.0, dark), (width, '#ffffff')])
    m = nt.nodes.new("ShaderNodeMix"); m.data_type = 'RGBA'; m.blend_type = 'MULTIPLY'
    m.inputs[0].default_value = 1.0
    nt.links.new(col, m.inputs[6]); nt.links.new(r, m.inputs[7])
    return m.outputs[2], ab.outputs[0]


def mat_stucco(name, base='#a8a090', dark='#6e665a'):
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    n = _noise(nt, co, 40.0, 10.0, 0.75)
    col = _ramp(nt, n.outputs[0], [(0.3, dark), (0.55, base), (0.8, '#c8c0b0')])
    c = grime(nt, col, co, 0.6)
    c, _ = cracks(nt, c, co, 1.5, 0.008)
    nt.links.new(grit(nt, c, co, 0.4), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.95
    _bump(nt, bs, n.outputs[0], 0.9, 0.015)
    return m


def mat_brick(name, brick='#8a4434', brick2='#6a3226', mortar='#8a8070', axis='x'):
    """axis: 'x' for walls running along game x (face normal is y), 'y' for walls along game y."""
    m, nt, bs = _nodes(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Rotation"].default_value = (math.radians(90), 0, 0) if axis == 'x' else (math.radians(90), 0, math.radians(90))
    nt.links.new(tc.outputs["Object"], mp.inputs[0])
    co = mp.outputs[0]
    b = nt.nodes.new("ShaderNodeTexBrick")
    b.inputs["Scale"].default_value = 4.0
    b.inputs["Mortar Size"].default_value = 0.025
    b.inputs["Color1"].default_value = _hex(brick)
    b.inputs["Color2"].default_value = _hex(brick2)
    b.inputs["Mortar"].default_value = _hex(mortar)
    b.inputs["Brick Width"].default_value = 0.5
    b.inputs["Row Height"].default_value = 0.17
    nt.links.new(co, b.inputs["Vector"])
    n = _noise(nt, co, 30.0, 8.0, 0.7)
    rough = _ramp(nt, n.outputs[0], [(0.3, '#8a8a8a'), (0.7, '#ffffff')])
    m1 = nt.nodes.new("ShaderNodeMix"); m1.data_type = 'RGBA'; m1.blend_type = 'MULTIPLY'
    m1.inputs[0].default_value = 1.0
    nt.links.new(b.outputs["Color"], m1.inputs[6]); nt.links.new(rough, m1.inputs[7])
    nt.links.new(grit(nt, grime(nt, m1.outputs[2], co, 0.55), co, 0.4), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.9
    inv = nt.nodes.new("ShaderNodeMath"); inv.operation = 'ADD'
    nt.links.new(b.outputs["Fac"], inv.inputs[0]); nt.links.new(n.outputs[0], inv.inputs[1])
    _bump(nt, bs, inv.outputs[0], 0.8, 0.02)
    return m


def mat_planks(name, wood='#6a4a30', wood2='#4a3220'):
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (1.0, 5.0, 1.0)
    nt.links.new(co, mp.inputs[0])
    b = nt.nodes.new("ShaderNodeTexBrick")
    b.inputs["Scale"].default_value = 1.0
    b.inputs["Mortar Size"].default_value = 0.03
    b.inputs["Color1"].default_value = _hex(wood)
    b.inputs["Color2"].default_value = _hex(wood2)
    b.inputs["Mortar"].default_value = _hex('#2a1e16')
    b.inputs["Brick Width"].default_value = 1.6
    b.inputs["Row Height"].default_value = 0.2
    nt.links.new(mp.outputs[0], b.inputs["Vector"])
    n = _noise(nt, mp.outputs[0], 6.0, 6.0, 0.6)
    st = _ramp(nt, n.outputs[0], [(0.3, '#7a7a7a'), (0.7, '#ffffff')])
    m1 = nt.nodes.new("ShaderNodeMix"); m1.data_type = 'RGBA'; m1.blend_type = 'MULTIPLY'
    m1.inputs[0].default_value = 1.0
    nt.links.new(b.outputs["Color"], m1.inputs[6]); nt.links.new(st, m1.inputs[7])
    nt.links.new(grit(nt, grime(nt, m1.outputs[2], co, 0.45, False), co, 0.35), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.8
    _bump(nt, bs, b.outputs["Fac"], 0.5, 0.01)
    return m


def mat_ground(name, a='#76664e', b='#56493a', c='#8e7e62', scale=3.0):
    """Dusty dirt with pebbles."""
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    n = _noise(nt, co, scale, 10.0, 0.7)
    col = _ramp(nt, n.outputs[0], [(0.35, b), (0.5, a), (0.65, c)])
    v = nt.nodes.new("ShaderNodeTexVoronoi")
    v.inputs["Scale"].default_value = 18.0
    nt.links.new(co, v.inputs["Vector"])
    peb = _ramp(nt, v.outputs["Distance"], [(0.0, '#4a3e30'), (0.12, '#ffffff')])
    m1 = nt.nodes.new("ShaderNodeMix"); m1.data_type = 'RGBA'; m1.blend_type = 'MULTIPLY'
    m1.inputs[0].default_value = 0.6
    nt.links.new(col, m1.inputs[6]); nt.links.new(peb, m1.inputs[7])
    cc, crk = cracks(nt, m1.outputs[2], co, 1.2, 0.012, '#3a3026')
    nt.links.new(grit(nt, cc, co, 0.45, 120.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 1.0
    add = nt.nodes.new("ShaderNodeMath"); add.operation = 'ADD'
    nt.links.new(n.outputs[0], add.inputs[0]); nt.links.new(v.outputs["Distance"], add.inputs[1])
    _bump(nt, bs, add.outputs[0], 0.7, 0.03)
    return m


def mat_asphalt(name):
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    n = _noise(nt, co, 25.0, 10.0, 0.8)
    col = _ramp(nt, n.outputs[0], [(0.3, '#2a2826'), (0.55, '#3e3a36'), (0.75, '#56504a')])
    c, crk = cracks(nt, col, co, 1.3, 0.012, '#121010')
    c2, _ = cracks(nt, c, co, 3.7, 0.008, '#1a1816')
    nt.links.new(grit(nt, c2, co, 0.4, 140.0), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.95
    _bump(nt, bs, crk, 0.6, 0.02)
    return m


def mat_concrete(name, base='#8a8478', seams=1.0):
    m, nt, bs = _nodes(name)
    co = _coord(nt)
    n = _noise(nt, co, 20.0, 10.0, 0.7)
    col = _ramp(nt, n.outputs[0], [(0.3, '#5e5a52'), (0.55, base), (0.8, '#a8a294')])
    c, crk = cracks(nt, grime(nt, col, co, 0.5, False), co, 1.8, 0.01)
    nt.links.new(grit(nt, c, co, 0.4), bs.inputs["Base Color"])
    bs.inputs["Roughness"].default_value = 0.95
    _bump(nt, bs, n.outputs[0], 0.7, 0.01)
    return m


def mat_paint_rust(name, paint='#5e9a90', rust=0.45):
    m, nt, bs = _nodes(name)
    co = _coord(nt, 1.0)
    n = _noise(nt, co, 4.0, 10.0, 0.7)
    fac = _ramp(nt, n.outputs[0], [(1.0 - rust - 0.05, '#000000'), (1.0 - rust + 0.05, '#ffffff')])
    n2 = _noise(nt, co, 30.0, 6.0, 0.6)
    rc = _ramp(nt, n2.outputs[0], [(0.3, '#4a2414'), (0.7, '#9a5a2e')])
    col = _mix(nt, paint, rc, fac)
    nt.links.new(grit(nt, grime(nt, col, co, 0.35, False), co, 0.3), bs.inputs["Base Color"])
    rough = _ramp(nt, fac, [(0.0, '#606060'), (1.0, '#f0f0f0')])
    nt.links.new(rough, bs.inputs["Roughness"])
    bs.inputs["Metallic"].default_value = 0.3
    _bump(nt, bs, fac, 0.3, 0.01)
    return m


def mat_flat(name, col, rough=0.8, metal=0.0, emit=None, noise=0.15):
    m, nt, bs = _nodes(name)
    if noise > 0:
        co = _coord(nt)
        n = _noise(nt, co, 12.0, 6.0, 0.6)
        c = _ramp(nt, n.outputs[0], [(0.3, '#' + ''.join('%02x' % int(min(255, v * (1 - noise))) for v in bytes.fromhex(col.lstrip('#')))), (0.7, col)])
        nt.links.new(c, bs.inputs["Base Color"])
    else:
        bs.inputs["Base Color"].default_value = _hex(col)
    bs.inputs["Roughness"].default_value = rough
    bs.inputs["Metallic"].default_value = metal
    if emit:
        bs.inputs["Emission Color"].default_value = _hex(emit)
        bs.inputs["Emission Strength"].default_value = 3.0
    return m


# ------------------------------------------------------------------ geometry
_COLL = None


def _link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def box(x0, y0, z0, x1, y1, z1, mat, bevel=0.0, name="box"):
    """Axis-aligned box in game coords."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(me)
    bm.free()
    ob = _link(bpy.data.objects.new(name, me))
    ob.scale = (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
    ob.location = g2b((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    me.materials.append(mat)
    if bevel > 0:
        bpy.context.view_layer.objects.active = ob
        md = ob.modifiers.new("bev", 'BEVEL')
        md.width = bevel
        md.segments = 2
        md.affect = 'EDGES'
    _apply_scale(ob)
    return ob


def _apply_scale(ob):
    me = ob.data
    s = ob.scale.copy()
    for v in me.vertices:
        v.co = Vector((v.co.x * s.x, v.co.y * s.y, v.co.z * s.z))
    ob.scale = (1, 1, 1)


def cyl(x, y, z0, z1, r, mat, verts=16, name="cyl", rot=None):
    ob = FAST.primitive_cylinder_add(vertices=verts, radius=r, depth=z1 - z0, location=g2b(x, y, (z0 + z1) / 2))
    pass
    ob.name = name
    ob.data.materials.append(mat)
    if rot:
        ob.rotation_euler = rot
    FAST.shade_smooth()
    return ob


def sphere(x, y, z, r, mat, name="sph", scale=(1, 1, 1)):
    ob = FAST.primitive_uv_sphere_add(segments=16, ring_count=10, radius=r, location=g2b(x, y, z))
    pass
    ob.name = name
    ob.scale = scale
    ob.data.materials.append(mat)
    FAST.shade_smooth()
    return ob


def rot_z(ob, deg, pivot=None):
    """Rotate an object around a vertical axis through pivot (game xy)."""
    if pivot is not None:
        p = g2b(pivot[0], pivot[1], 0)
        ob.location = p + Matrix_rot(deg) @ (ob.location - p)
    ob.rotation_euler.z += math.radians(-deg)


def Matrix_rot(deg):
    from mathutils import Matrix
    return Matrix.Rotation(math.radians(-deg), 3, 'Z')


# ------------------------------------------------------------------ camera + light
def camera(cx, cy, width_px, height_px, cz=0.0):
    sc = bpy.context.scene
    cam = bpy.data.cameras.new("cam")
    cam.type = 'ORTHO'
    cam.ortho_scale = width_px / PX_PER_UNIT
    ob = _link(bpy.data.objects.new("cam", cam))
    ob.rotation_euler = Euler((math.radians(60), 0, math.radians(45)))
    fwd = ob.rotation_euler.to_matrix() @ Vector((0, 0, -1))
    ob.location = g2b(cx, cy, cz) - fwd * 60
    cam.clip_end = 200
    sc.camera = ob
    sc.render.resolution_x = width_px
    sc.render.resolution_y = height_px
    sc.render.resolution_percentage = 100
    return ob


def lights(sun_strength=3.2, ambient=0.55, warm=True):
    sc = bpy.context.scene
    sun = bpy.data.lights.new("sun", 'SUN')
    sun.energy = sun_strength
    sun.angle = math.radians(6)
    sun.color = (1.0, 0.93, 0.8) if warm else (1, 1, 1)
    ob = _link(bpy.data.objects.new("sun", sun))
    # light comes from the screen's upper left (game -x, a little +y), fairly high
    d = Vector((1.0, -0.35, -1.25)).normalized()   # direction the light travels, game coords
    db = Vector((d.x, -d.y, d.z))
    ob.rotation_euler = db.to_track_quat('-Z', 'Y').to_euler()
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.55, 0.55, 0.56, 1)
    bg.inputs[1].default_value = ambient
    sc.world = w
