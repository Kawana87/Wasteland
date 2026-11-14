class_name TerrainMesh
extends MeshInstance2D
## Builds the sloped ground as one mesh of triangles (two per tile), drawn back-to-front.
## Lighting is worked out per triangle here; texture/dither happens in terrain.gdshader.

const LIGHT := Vector3(0.40, 0.22, 0.89)

const MAT_COL := {
	0: Color("6b7548"),   # grass
	1: Color("7a7848"),   # dry grass
	2: Color("7a6648"),   # dirt patch
	3: Color("8a8478"),   # gravel
	4: Color("7e786c"),   # rock (steep slopes)
	5: Color("4a484e"),   # road
	6: Color("8f897f"),   # sidewalk
	7: Color("6b4a32"),   # wood floor
	8: Color("bdb49c"),   # checker tile (colours set in shader)
	9: Color("7a3a34"),   # carpet
	10: Color("8a867c"),  # concrete
	12: Color("4a484e"),  # cracked road
	13: Color("4a484e"),  # pothole
}

func build(w: World) -> void:
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var order := []
	for y in World.N:
		for x in World.N:
			order.append(Vector2i(x, y))
	order.sort_custom(func(p, q): return (p.x + p.y < q.x + q.y) if p.x + p.y != q.x + q.y else p.x < q.x)
	var front := _winding(Iso.to_screen(0, 0), Iso.to_screen(1, 0), Iso.to_screen(1, 1)) > 0.0
	for t in order:
		var x: int = t.x
		var y: int = t.y
		var A := Vector3(x, y, w.vh(x, y))
		var B := Vector3(x + 1, y, w.vh(x + 1, y))
		var C := Vector3(x + 1, y + 1, w.vh(x + 1, y + 1))
		var D := Vector3(x, y + 1, w.vh(x, y + 1))
		_tri(w, A, B, C, front, verts, cols, uvs)
		_tri(w, A, C, D, front, verts, cols, uvs)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh = m
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	material = mat
	z_index = -4096
	z_as_relative = false

static func _winding(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)

func _tri(w: World, A: Vector3, B: Vector3, C: Vector3, front: bool, verts: PackedVector2Array, cols: PackedColorArray, uvs: PackedVector2Array) -> void:
	var a := Iso.to_screen(A.x, A.y, A.z)
	var b := Iso.to_screen(B.x, B.y, B.z)
	var c := Iso.to_screen(C.x, C.y, C.z)
	var wd := _winding(a, b, c)
	if wd == 0.0 or (wd > 0.0) != front:
		return   # faces away from the camera; something in front will cover it
	var u := Vector3(B.x - A.x, B.y - A.y, (B.z - A.z) / 16.0)
	var v := Vector3(C.x - A.x, C.y - A.y, (C.z - A.z) / 16.0)
	var n := u.cross(v)
	if n.z < 0.0:
		n = -n
	n = n.normalized()
	var lit := maxf(0.0, n.dot(LIGHT))
	var steep := Vector2(n.x, n.y).length() / maxf(0.05, n.z)
	var cx := (A.x + B.x + C.x) / 3.0
	var cy := (A.y + B.y + C.y) / 3.0
	var m := _material(w, cx, cy, steep)
	var col: Color = MAT_COL[m]
	col.a = lit
	for p in [[a, A], [b, B], [c, C]]:
		verts.append(p[0])
		cols.append(col)
		uvs.append(Vector2(p[1].x + m * 1000.0, p[1].y))

func _material(w: World, x: float, y: float, steep: float) -> int:
	if steep > 1.25:
		return 4
	var tx := clampi(int(floor(x)), 0, World.N - 1)
	var ty := clampi(int(floor(y)), 0, World.N - 1)
	var i := w.idx(tx, ty)
	var t := w.T[i]
	var g := w.G[i]
	if t == World.ROAD:
		return 13 if g == 2 else (12 if g == 1 else 5)
	if t == World.SIDE:
		return 6
	if t == World.FLOOR:
		var b: World.Bld = w.bld(w.BID[i])
		return [7, 8, 9, 10][b.fkind] if b else 7
	match g:
		1: return 1
		2: return 2
		4: return 3
	return 0
