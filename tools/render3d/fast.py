"""Fast replacements for bpy.ops.mesh.primitive_* (operators get slower with every object in the
scene; building meshes with bmesh stays fast). Same keyword names; the result becomes the active object."""
import bpy, bmesh, math
from mathutils import Vector


LAST = [None]


def active():
    return LAST[0]


def _make(bm, name, location, rotation, scale=(1, 1, 1)):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob); __import__('lib').REG.append(ob)
    ob.location = location
    ob.rotation_euler = rotation
    ob.scale = scale
    LAST[0] = ob          # setting the view layer's active object is O(scene size); track it here instead
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
    ob = LAST[0]
    if ob and ob.type == 'MESH':
        for p in ob.data.polygons:
            p.use_smooth = True


def shade_flat():
    ob = LAST[0]
    if ob and ob.type == 'MESH':
        for p in ob.data.polygons:
            p.use_smooth = False


class Batch:
    """Many small parts in ONE object (grass blades, pebbles, litter): Blender slows down per object,
    not per polygon, so tiny props are built as a single mesh with per-part materials."""
    def __init__(self, name="batch"):
        from mathutils import Matrix, Euler
        self.M, self.E = Matrix, Euler
        self.bm = bmesh.new(); self.name = name; self.mats = []

    def _mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _mx(self, loc, rot, scale):
        return self.M.Translation(loc) @ self.E(rot).to_matrix().to_4x4() @ self.M.Diagonal((scale[0], scale[1], scale[2], 1.0))

    def _tag(self, verts, mat):
        mi = self._mi(mat)
        fs = {f for v in verts for f in v.link_faces}
        for f in fs:
            f.material_index = mi

    def cone(self, loc, r1, r2, depth, segs, mat, rot=(0, 0, 0), scale=(1, 1, 1)):
        r = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=depth,
                                  matrix=self._mx(loc, rot, scale))
        self._tag(r["verts"], mat)

    def ico(self, loc, radius, mat, subdiv=1, rot=(0, 0, 0), scale=(1, 1, 1)):
        r = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=radius, matrix=self._mx(loc, rot, scale))
        self._tag(r["verts"], mat)

    def cube(self, loc, size, mat, rot=(0, 0, 0)):
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=self._mx(loc, rot, size))
        self._tag(r["verts"], mat)

    def done(self, smooth=False):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me); self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        for p in me.polygons:
            p.use_smooth = smooth
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob); __import__('lib').REG.append(ob)
        ob["batch"] = True     # pieces were pre-filtered against buildings; validator leaves it whole
        LAST[0] = ob
        return ob
