class_name TerrainMesh
extends MeshInstance2D
## Builds the sloped ground as one mesh of triangles (two per tile), drawn back-to-front.
## Lighting is worked out per triangle here; texture/dither happens in terrain.gdshader.

const LIGHT := Vector3(0.40, 0.22, 0.89)

const MAT_COL := {
	0: Color("6f6f48"),   # grass (dry, like the pre-rendered ground)
	1: Color("837a50"),   # dry grass
	2: Color("7c664a"),   # dirt patch
	3: Color("8a8478"),   # gravel
	4: Color("7e786c"),   # rock (steep slopes)
	5: Color("4a484e"),   # road
	6: Color("8f897f"),   # sidewalk
	7: Color("6b4a32"),   # wood floor
	8: Color("bdb49c"),   # checker tile (colours set in shader)
	9: Color("7a3a34"),   # carpet
	10: Color("8a867c"),  # concrete
	11: Color("8a7454"),  # dirt track
	12: Color("4a484e"),  # cracked road
	13: Color("4a484e"),  # pothole
	14: Color("9ab8a8"),  # linoleum (colours set in shader)
	15: Color("3d6a78"),  # water (animated in shader)
	16: Color("d8d2c2"),  # salt crust
	17: Color("9a5a3a"),  # red canyon rock
	18: Color("4e5236"),  # marsh mud
	19: Color("5e7a6a"),  # crater glass
	20: Color("6a5434"),  # ploughed field
	21: Color("b89e74"),  # sand
	22: Color("4f5a34"),  # forest floor
	23: Color("6e6a62"),  # cracked concrete lot
	24: Color("a87a50"),  # red sand
}

const G_MAT := {1: 1, 2: 2, 4: 3, 5: 16, 6: 17, 7: 18, 8: 19, 9: 20, 10: 21, 11: 22, 12: 24, 13: 23}

var chunk := Vector2i()

## One chunk of ground: CH x CH tiles, two triangles each, drawn back to front. Positions are world
## screen coordinates; the shader gets the chunk origin so it can find world tile positions.
func build(w: World, ccx: int, ccy: int, near: Array) -> void:
	chunk = Vector2i(ccx, ccy)
	var x0 := ccx * World.CH
	var y0 := ccy * World.CH
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var front := _winding(Iso.to_screen(0, 0), Iso.to_screen(1, 0), Iso.to_screen(1, 1)) > 0.0
	for s in range(0, 2 * World.CH - 1):
		for x in range(maxi(0, s - World.CH + 1), mini(s, World.CH - 1) + 1):
			var y := s - x
			var X := x0 + x
			var Y := y0 + y
			var A := Vector3(X, Y, w.vh(X, Y))
			var B := Vector3(X + 1, Y, w.vh(X + 1, Y))
			var C := Vector3(X + 1, Y + 1, w.vh(X + 1, Y + 1))
			var D := Vector3(X, Y + 1, w.vh(X, Y + 1))
			_tile_m = _material(w, X + 0.5, Y + 0.5, 0.0)
			_tri(w, A, B, C, front, verts, cols, uvs, x0, y0)
			_tri(w, A, C, D, front, verts, cols, uvs, x0, y0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh = m
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var maps := GroundMaps.build(w, ccx, ccy, near)
	for k in maps:
		mat.set_shader_parameter(k + "_map", maps[k])
	mat.set_shader_parameter("origin", Vector2(x0, y0))
	mat.set_shader_parameter("city", 1.0 if w.density(x0 + 16, y0 + 16) > 110 else 0.0)
	material = mat
	z_index = -4096
	z_as_relative = false

const SHADER := preload("res://shaders/terrain.gdshader")

static func _winding(a: Vector2, b: Vector2, c: Vector2) -> float:
	return (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)

func _tri(w: World, A: Vector3, B: Vector3, C: Vector3, front: bool, verts: PackedVector2Array, cols: PackedColorArray, uvs: PackedVector2Array, x0: int, y0: int) -> void:
	var a := Vector2((A.x - A.y) * 24.0, (A.x + A.y) * 12.0 - A.z * Iso.S)
	var b := Vector2((B.x - B.y) * 24.0, (B.x + B.y) * 12.0 - B.z * Iso.S)
	var c := Vector2((C.x - C.y) * 24.0, (C.x + C.y) * 12.0 - C.z * Iso.S)
	var wd := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if wd == 0.0 or (wd > 0.0) != front:
		return   # faces away from the camera; something in front will cover it
	var n := Vector3(B.x - A.x, B.y - A.y, (B.z - A.z) * 0.0625).cross(Vector3(C.x - A.x, C.y - A.y, (C.z - A.z) * 0.0625))
	if n.z < 0.0:
		n = -n
	n = n.normalized()
	var lit := maxf(0.0, n.dot(LIGHT))
	var steep := sqrt(n.x * n.x + n.y * n.y) / maxf(0.05, n.z)
	var m: int
	if steep > 1.25:
		var bb := w.biome(int(A.x), int(A.y))
		m = 17 if bb == World.B_CANYON or bb == World.B_GORGE else 4
	else:
		m = _tile_m
	var col: Color = MAT_COL[m]
	col.a = lit
	verts.append(a); verts.append(b); verts.append(c)
	cols.append(col); cols.append(col); cols.append(col)
	var mo := m * 1000.0 - x0
	uvs.append(Vector2(A.x + mo, A.y - y0)); uvs.append(Vector2(B.x + mo, B.y - y0)); uvs.append(Vector2(C.x + mo, C.y - y0))

var _tile_m := 0

func _material(w: World, x: float, y: float, steep: float) -> int:
	if steep > 1.25:
		var bb := w.biome(int(x), int(y))
		return 17 if bb == World.B_CANYON or bb == World.B_GORGE else 4
	var tx := clampi(int(floor(x)), 0, World.N - 1)
	var ty := clampi(int(floor(y)), 0, World.N - 1)
	var i := w.idx(tx, ty)
	var t := w.T[i]
	var g := w.G[i]
	# roads, sidewalks and tracks are painted per pixel from GroundMaps; this is what shows at their edges
	if t == World.ROAD or t == World.SIDE:
		return 3 if w.in_city(x, y) else 1
	if t == World.DIRT_ROAD:
		return 2
	if t == World.FLOOR:
		var b: World.Bld = w.bld(w.BID[i])
		return [7, 8, 9, 10, 14][b.fkind] if b else 7
	if t == World.WATER:
		return 15
	return G_MAT.get(g, 0)
