"""Fast replacements for bpy.ops.mesh.primitive_* (operators get slower with every object in the
scene; building meshes with bmesh stays fast). Same keyword names; the result becomes the active object."""
import bpy, bmesh, math
from mathutils import Vector


def _make(bm, name, location, rotation, scale=(1, 1, 1)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = location
    ob.rotation_euler = rotation
    ob.scale = scale
    bpy.context.view_layer.objects.active = ob
    return ob


def primitive_cone_add(vertices=32, radius1=1.0, radius2=0.0, depth=2.0, location=(0, 0, 0), rotation=(0, 0, 0), **kw):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=vertices, radius1=radius1, radius2=radius2, depth=depth)
    return _make(bm, "cone", location, rotation)


def primitive_cylinder_add(vertices=32, radius=1.0, depth=2.0, location=(0, 0, 0), rotation=(0, 0, 0), **kw):
    return primitive_cone_add(vertices, radius, radius, depth, location, rotation)


def primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=(0, 0, 0), rotation=(0, 0, 0), **kw):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=ring_count, radius=radius)
    return _make(bm, "sphere", location, rotation)


def primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=(0, 0, 0), rotation=(0, 0, 0), **kw):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    return _make(bm, "ico", location, rotation)


def primitive_torus_add(major_radius=1.0, minor_radius=0.25, major_segments=24, minor_segments=8, location=(0, 0, 0), rotation=(0, 0, 0), **kw):
    bm = bmesh.new()
    rings = []
    for i in range(major_segments):
        a = i / major_segments * math.tau
        ring = []
        for j in range(minor_segments):
            b = j / minor_segments * math.tau
            r = major_radius + minor_radius * math.cos(b)
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), minor_radius * math.sin(b))))
        rings.append(ring)
    for i in range(major_segments):
        for j in range(minor_segments):
            a, b = rings[i][j], rings[(i + 1) % major_segments][j]
            c, d = rings[(i + 1) % major_segments][(j + 1) % minor_segments], rings[i][(j + 1) % minor_segments]
            bm.faces.new((a, b, c, d))
    return _make(bm, "torus", location, rotation)


def shade_smooth():
    ob = bpy.context.view_layer.objects.active
    if ob and ob.type == 'MESH':
        for p in ob.data.polygons:
            p.use_smooth = True


def shade_flat():
    ob = bpy.context.view_layer.objects.active
    if ob and ob.type == 'MESH':
        for p in ob.data.polygons:
            p.use_smooth = False
